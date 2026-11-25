-- Mock Forever client for Cute Auras. Loads the addon into several clients (each its own globals) that share a group and
-- an addon channel, drives the bar, the alerts, the secure rebuff handler, Hands, the blessings and biome gear, and
-- fails on: a widget method outside the real API's list, a protected call in a fight (ADDON_ACTION_BLOCKED), a secret
-- value used as a plain one, a restricted snippet with a table constructor, and any error a part caught (A.errors).
--   luajit tools/cuteauras/harness.lua
math.randomseed = nil -- (the client has none)
local HERE = (arg and arg[0] and arg[0]:match("^(.*)/") or ".")
local DIR = HERE .. "/CuteAuras/"

----------------------------------------------------------------------------
-- secret values: a table the client hands back in a fight; any arithmetic, comparison or concat on one errors
----------------------------------------------------------------------------
local SECRET_MT = {}
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__lt", "__le", "__concat", "__len", "__index", "__call", "__unm" }) do
  SECRET_MT[op] = function() error("a secret value used as a plain one", 2) end
end
local function secret() return setmetatable({}, SECRET_MT) end
local function issecret(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end

----------------------------------------------------------------------------
-- widgets
----------------------------------------------------------------------------
local METHODS = {}
for m in ([[SetPoint ClearAllPoints SetAllPoints SetSize SetWidth SetHeight GetWidth GetHeight Show Hide SetShown IsShown IsVisible
SetAlpha GetAlpha GetParent GetCenter GetEffectiveScale SetParent CreateTexture CreateFontString SetScript GetScript HookScript
RegisterEvent UnregisterEvent RegisterUnitEvent SetFrameStrata SetFrameLevel EnableMouse SetMovable SetClampedToScreen RegisterForDrag
StartMoving StopMovingOrSizing GetName SetText GetText RegisterForClicks SetTexture SetColorTexture SetTexCoord SetVertexColor
SetDesaturated SetFontObject SetFont GetFont SetTextColor SetJustifyH SetJustifyV SetWordWrap SetScale GetScale GetLeft GetTop
SetAttribute GetAttribute SetCooldown SetHideCountdownNumbers SetShadowOffset SetShadowColor GetFrameLevel IsProtected GetRight GetBottom
SetHighlightTexture CreateMaskTexture AddMaskTexture SetMaxLines GetStringWidth GetUnboundedStringWidth EnableMouseWheel]]):gmatch("%S+") do METHODS[m] = true end
local PROTECTED_CALL = { Show = true, Hide = true, SetShown = true, SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
  SetSize = true, SetWidth = true, SetHeight = true, SetAttribute = true, SetParent = true, SetScale = true, EnableMouse = true,
  StopMovingOrSizing = true, StartMoving = true }

-- text width in Friz Quadrata (tools/cute/harness.lua's table), close enough to see what does not fit
local CHAR = {}
for ch in ("iljtfr'.,:;|!I ()[]"):gmatch(".") do CHAR[ch] = 0.30 end
for ch in ("mwMW"):gmatch(".") do CHAR[ch] = 0.86 end
for ch in ("ABCDEFGHJKLNOPQRSTUVXYZ"):gmatch(".") do CHAR[ch] = 0.66 end
for ch in ("0123456789"):gmatch(".") do CHAR[ch] = 0.56 end
local function textWidth(s, size)
  local w = 0
  for ch in (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gmatch(".") do w = w + (CHAR[ch] or 0.53) end
  return w * (size or 12)
end
-- the lines a word-wrapped string takes at a width (whole words to a line, as the game wraps)
local function wrapLines(s, size, width)
  local lines, cur = 1, 0
  local space = textWidth(" ", size)
  for word in (s or ""):gmatch("%S+") do
    local w = textWidth(word, size)
    if cur == 0 then cur = w
    elseif cur + space + w <= width then cur = cur + space + w
    else lines = lines + 1; cur = w end
  end
  return lines
end
TEXT_WIDTH, WRAP_LINES = textWidth, wrapLines

local newObj
local function protectedChain(o)
  local p = o
  while p do if p.__secure then return true end p = nil end
  return o.__protected or o.__secure
end
function newObj(c, kind, template, parent, name)
  local o = { __kind = kind, __template = template, __scripts = {}, __shown = true, __attrs = {}, __points = {}, __w = 0, __h = 0,
              __text = "", __alpha = 1, __scale = 1, __parent = parent, __name = name, __client = c, __children = {} }
  if parent then parent.__children[#parent.__children + 1] = o end
  setmetatable(o, { __index = function(t, k)
    -- (a field the addon keeps on a frame reads nil, as on the client; a method the client lacks is no function)
    if not METHODS[k] then return nil end
    return function(self, ...)
      local a = { ... }
      if PROTECTED_CALL[k] and (rawget(self, "__secure") or rawget(self, "__protected")) and self.__client.combat and not self.__client.restricted then
        error("ADDON_ACTION_BLOCKED: " .. k .. " on a protected frame in a fight (" .. tostring(self.__name) .. ")", 2)
      end
      if k == "SetScript" then self.__scripts[a[1]] = a[2]
      elseif k == "GetScript" then return self.__scripts[a[1]]
      elseif k == "HookScript" then
        local old = self.__scripts[a[1]]
        self.__scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
      elseif k == "CreateTexture" then return newObj(self.__client, "Texture", nil, self)
      elseif k == "CreateFontString" then return newObj(self.__client, "FontString", nil, self)
      elseif k == "CreateMaskTexture" then return newObj(self.__client, "Texture", nil, self)
      elseif k == "Show" then local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
      elseif k == "Hide" then local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
      elseif k == "SetShown" then if a[1] then self:Show() else self:Hide() end
      elseif k == "IsShown" then return self.__shown
      elseif k == "IsVisible" then local p = self; while p do if not p.__shown then return false end p = p.__parent end return true
      elseif k == "SetSize" then self.__w, self.__h = a[1], a[2]
      elseif k == "SetWidth" then self.__w = a[1]
      elseif k == "SetHeight" then self.__h = a[1]
      elseif k == "GetWidth" then return self.__w
      elseif k == "GetHeight" then return self.__h
      elseif k == "SetPoint" then self.__points[#self.__points + 1] = a
      elseif k == "ClearAllPoints" then self.__points = {}
      elseif k == "SetText" then
        if issecret(a[1]) then self.__text = "<secret>" else self.__text = a[1] == nil and "" or tostring(a[1]) end
      elseif k == "GetText" then return self.__text
      elseif k == "SetTexture" then self.__tex = a[1]
      elseif k == "SetColorTexture" then self.__color = { a[1], a[2], a[3], a[4] }
      elseif k == "SetDesaturated" then self.__desat = a[1] and true or false
      elseif k == "SetTextColor" then self.__textColor = { a[1], a[2], a[3] }
      elseif k == "SetAlpha" then self.__alpha = a[1]
      elseif k == "GetAlpha" then return self.__alpha
      elseif k == "SetScale" then self.__scale = a[1]
      elseif k == "GetScale" then return self.__scale
      elseif k == "GetEffectiveScale" then return self.__scale
      elseif k == "GetCenter" then return 800, 500
      elseif k == "GetTop" then return 700
      -- (a frame's edges: the screen's own, else where a test put the frame (__left, __right); nil before it is laid
      -- out, as the client answers)
      elseif k == "GetLeft" then if self.__left then return self.__left end if self.__parent == nil then return 0 end return nil
      elseif k == "GetRight" then if self.__right then return self.__right end if self.__parent == nil then return self.__w end return nil
      elseif k == "SetClampedToScreen" then self.__clamped = a[1] and true or false
      elseif k == "GetName" then return self.__name
      elseif k == "GetParent" then return self.__parent
      elseif k == "IsProtected" then return self.__secure or self.__protected or false
      elseif k == "SetCooldown" then self.__cd = { a[1], a[2] }
      elseif k == "GetFont" then return "Fonts\\FRIZQT__.TTF", self.__size or 12
      elseif k == "SetFont" then self.__size = a[2]
      elseif k == "SetWordWrap" then self.__wrap = a[1] and true or false
      elseif k == "SetMaxLines" then self.__maxLines = a[1]
      elseif k == "GetStringWidth" or k == "GetUnboundedStringWidth" then return textWidth(self.__text, self.__size)
      elseif k == "RegisterEvent" then self.__client.events[a[1]] = self.__client.events[a[1]] or {}; self.__client.events[a[1]][self] = true
      elseif k == "RegisterUnitEvent" then
        local ev = a[1]
        self.__client.events[ev] = self.__client.events[ev] or {}
        self.__client.events[ev][self] = { select(2, ...) }
      elseif k == "SetAttribute" then
        local name, v = a[1], a[2]
        local was = self.__attrs[name]
        self.__attrs[name] = v
        -- (the client fires OnAttributeChanged on every SetAttribute, the value changed or not: SecureStateDriver.lua
        -- compares before it sets for that reason)
        if self.__scripts.OnAttributeChanged then self.__scripts.OnAttributeChanged(self, name, v) end
      elseif k == "GetAttribute" then return self.__attrs[a[1]]
      elseif k == "RegisterForClicks" then self.__clickEdges = a
      elseif k == "StartMoving" then self.__moving = true
      elseif k == "StopMovingOrSizing" then self.__moving = nil
      end
    end
  end })
  return o
end

----------------------------------------------------------------------------
-- the restricted environment: snippets run in a sandbox with the client's handle methods
----------------------------------------------------------------------------
local function handle(c, f)
  if not f then return nil end
  local h = { __frame = f }
  function h:GetAttribute(n) return f.__attrs[n] end
  function h:SetAttribute(n, v) c.restricted = true; f:SetAttribute(n, v); c.restricted = false end
  function h:Show() c.restricted = true; f:Show(); c.restricted = false end
  function h:Hide() c.restricted = true; f:Hide(); c.restricted = false end
  function h:IsShown() return f.__shown end
  function h:GetFrameRef(label) return handle(c, f.__attrs["frameref-" .. label]) end
  function h:RunAttribute(name, ...) return c.runSnippet(f, f.__attrs[name], "self,...", f, ...) end
  function h:RegisterAutoHide(d) f.__autohide = d end
  function h:AddToAutoHide(o) f.__autohideWith = true end
  return h
end
local function sandbox(c)
  return { strsub = string.sub, strfind = string.find, strmatch = string.match, gsub = string.gsub, tonumber = tonumber, tostring = tostring,
           PlayerInCombat = function() return c.combat end, UnitExists = function(u) return c.units[u] ~= nil end,
           UnitIsDead = function(u) return c.units[u] and c.units[u].dead or false end,
           UnitIsGhost = function() return false end,
           -- (the environment's own: a snippet may register a driver in a fight, the game's secure code doing it)
           RegisterStateDriver = function(h, state, cond) c.registerDriver(h.__frame, state, cond) end,
           UnregisterStateDriver = function(h, state) if c.drivers[h.__frame] then c.drivers[h.__frame][state] = nil end end }
end

----------------------------------------------------------------------------
-- a client
----------------------------------------------------------------------------
local WORLD
local CLASS_NAME = { PRIEST = "Priest", PALADIN = "Paladin", MAGE = "Mage", WARRIOR = "Warrior", ROGUE = "Rogue", DRUID = "Druid",
  HUNTER = "Hunter", SHAMAN = "Shaman", WARLOCK = "Warlock" }
local SPELL_NAMES, SPELL_DESC, SPELL_LEVELS = {}, {}, {}
local AREA_NAMES = { [1] = "Dun Morogh", [618] = "Winterspring", [12] = "Elwynn Forest", [40] = "Westfall", [10] = "Duskwood", [139] = "Eastern Plaguelands",
  [357] = "Feralas", [2557] = "Dire Maul", [33] = "Stranglethorn Vale", [35] = "Booty Bay", [440] = "Tanaris" }

-- a member's name as the server writes a chat sender: Forever's surname after the first name, then the realm (o.sender:
-- as given, for a client whose UnitName gives the first name alone)
local function SENDER(m) return m.sender or (m.name .. (m.surname and (" " .. m.surname) or "") .. "-Realm") end
local function newClient(o)
  local c = { o = o, units = {}, events = {}, timers = {}, clock = 1000, combat = false, casts = {}, chat = {}, menus = {}, frames = {},
              known = {}, bags = {}, equipped = {}, items = {}, tooltips = {}, profs = o.profs or {}, zone = o.zone or "Elwynn Forest", subzone = "",
              said = {}, sent = {}, plainAuras = {}, drivers = {}, equips = {}, addons = o.addons }
  local env = {}
  setmetatable(env, { __index = _G })
  env._G = env
  c.env = env
  env.issecretvalue = issecret
  env.GetTime = function() return c.clock end
  env.time = function() return math.floor(c.clock) end
  env.GetServerTime = function() return math.floor(c.clock) end
  env.math = math; env.string = string; env.table = table
  env.UIParent = newObj(c, "Frame", nil, nil, "UIParent"); env.UIParent.__w, env.UIParent.__h = 1600, 1000
  env.GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12 end }
  env.Minimap = newObj(c, "Frame", nil, env.UIParent, "Minimap"); env.Minimap.__w, env.Minimap.__h = 140, 140
  env.GetCursorPosition = function() return 900, 600 end
  env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  env.LOCALIZED_CLASS_NAMES_MALE = CLASS_NAME
  env.UISpecialFrames = {}
  env.SlashCmdList = {}
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.chat[#c.chat + 1] = m end }
  env.Enum = { TooltipDataLineType = { ErrorLine = 22, ItemSpellTriggerLearn = 15, FlavorText = 37 }, SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11 },
               WeaponSlot = { MainHand = 0, OffHand = 1 },
               -- (RestrictedActionsConstantsDocumentation.lua's)
               AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
               AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 } }
  -- the client's addon restrictions: c.restrict = { [type] = true } while one is active; lifting one tells
  -- ADDON_RESTRICTION_STATE_CHANGED(type, Inactive) after it is off, every restriction read inactive while it tells
  env.C_RestrictedActions = {
    IsAddOnRestrictionActive = function(t) if c.telling or not c.restrict then return false end return c.restrict[t] == true end,
    GetAddOnRestrictionState = function(t) return c.restrict and c.restrict[t] and 2 or 0 end }
  function c.lift(t)
    if c.restrict then c.restrict[t] = nil end
    c.telling = true
    FIRE(c, "ADDON_RESTRICTION_STATE_CHANGED", t, 0)
    c.telling = false
  end
  env.Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
  env.SOUNDKIT = { RAID_WARNING = 8959 }
  env.ITEM_SET_BONUS, env.ITEM_SET_BONUS_GRAY = "Set: %s", "(%d) Set: %s"
  env.PlaySound = function(k) c.sounds = (c.sounds or 0) + 1 end
  env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2
  env.NUM_BAG_SLOTS = 4
  env.InCombatLockdown = function() return c.combat end
  -- (a member's own fight: their unit's combat flag, else yours; you dead are out of it, as the game has you)
  env.UnitAffectingCombat = function(u)
    local x = c.units[u]
    if u == "player" then return c.combat end
    if x and x.combat ~= nil then return x.combat end
    return c.combat
  end
  env.IsEncounterInProgress = function() return c.encounter or false end
  -- frames
  env.CreateFrame = function(kind, name, parent, template)
    local secure = template and template:find("Secure") and true or false
    if secure and c.combat then error("ADDON_ACTION_BLOCKED: a secure frame made in a fight", 2) end
    local f = newObj(c, kind, template, parent or env.UIParent, name)
    if name then env[name] = f end
    c.frames[#c.frames + 1] = f
    if secure then
      f.__secure = true
      local p = parent
      while p and p ~= env.UIParent do p.__protected = true; p = p.__parent end
    end
    if template == "CooldownFrameTemplate" then f.__kind = "Cooldown" end
    if template == "SecureActionButtonTemplate" then
      -- (the action on one edge: the button's useOnKeyDown, else the game's ActionButtonUseKeyDown, on by default)
      f.__scripts.OnClick = function(self, button, down)
        local useDown = self.__attrs.useOnKeyDown
        if useDown == nil then useDown = c.keyDown ~= false end
        if not ((down and useDown) or (not down and not useDown)) then return end
        -- (SecureButton_GetModifiedAttribute: prefix..name..suffix, *name..suffix, prefix..name*, *name*, name)
        local prefix, suffix = c.mod or "", ({ LeftButton = "1", RightButton = "2", MiddleButton = "3" })[button] or ""
        local at = self.__attrs
        local ty = at[prefix .. "type" .. suffix] or at["*type" .. suffix] or at[prefix .. "type*"] or at["*type*"] or at.type
        if ty then c.casts[#c.casts + 1] = { type = ty, spell = self.__attrs.spell, item = self.__attrs.item, macro = self.__attrs.macrotext,
          unit = self.__attrs.unit, slot = self.__attrs["target-slot"], from = self.__name } end
      end
    end
    if template == "SecureHandlerAttributeTemplate" then
      -- (SecureHandler_AttributeOnAttributeChanged: a name that starts with _ is skipped)
      f.__scripts.OnAttributeChanged = function(self, name, value)
        if name:match("^_") then return end
        local body = self.__attrs._onattributechanged
        if body then c.runSnippet(self, body, "self,name,value", self, name, value) end
      end
    end
    if template == "SecureGroupHeaderTemplate" then
      -- the game's group header (SecureGroupHeaders.lua): hidden at first; while visible, on its attributes, its OnShow
      -- and GROUP_ROSTER_UPDATE (in a fight too), the members of nameList by their unit, each on a child in the list's
      -- order (sortMethod NAMELIST); a child made when more are needed (CreateFrame, never in a fight), one past the
      -- members hidden with no unit. A member's name as its GetGroupRosterInfo reads it: a raid's from
      -- GetRaidRosterInfo, a party's UnitName's two answers joined with "-"
      f.__shown = false
      local function sec(fn) local was = c.restricted; c.restricted = true; fn(); c.restricted = was end
      local function update(self)
        if not self:IsVisible() then return end
        local list = self.__attrs.nameList
        local order, units = {}, {}
        local i = 0
        for n in (list or ""):gmatch("[^,]+") do i = i + 1; order[n] = order[n] or i end
        local nameOf = {}
        local function partyName(u) local n, s = env.UnitName(u); if s and s ~= "" then n = n .. "-" .. s end return n end
        if c.o.raid and self.__attrs.showRaid then
          for k = 1, 40 do
            local n = c.units["raid" .. k] and env.GetRaidRosterInfo(k)
            if n and order[n] then units[#units + 1] = "raid" .. k; nameOf["raid" .. k] = n end
          end
        elseif not c.o.raid and c.o.group and self.__attrs.showParty then
          local n = partyName("player")
          if self.__attrs.showPlayer and order[n] then units[#units + 1] = "player"; nameOf.player = n end
          for k = 1, 4 do
            n = c.units["party" .. k] and partyName("party" .. k)
            if n and order[n] then units[#units + 1] = "party" .. k; nameOf["party" .. k] = n end
          end
        end
        table.sort(units, function(a, b) return order[nameOf[a]] < order[nameOf[b]] end)
        for k = 1, math.max(1, #units) do
          if not self.__attrs["child" .. k] then
            local ch = env.CreateFrame(self.__attrs.templateType or "Button", self.__name and (self.__name .. "UnitButton" .. k), self, self.__attrs.template)
            self.__attrs["child" .. k] = ch
            local init = self.__attrs.initialConfigFunction
            if init then c.runSnippet(self, init, "self", ch) end
          end
        end
        for k, u in ipairs(units) do
          local ch = self.__attrs["child" .. k]
          sec(function() ch:SetAttribute("unit", u) end)
          sec(function() ch:Show() end)
        end
        local k = #units + 1
        while self.__attrs["child" .. k] do
          local ch = self.__attrs["child" .. k]
          sec(function() ch:Hide() end)
          sec(function() ch:SetAttribute("unit", nil) end)
          k = k + 1
        end
      end
      f.__scripts.OnAttributeChanged = function(self, name) if name == "_ignore" or self.__attrs._ignore then return end update(self) end
      f.__scripts.OnShow = update
      f.__scripts.OnEvent = function(self, ev) if ev == "GROUP_ROSTER_UPDATE" or ev == "UNIT_NAME_UPDATE" then update(self) end end
      f:RegisterEvent("GROUP_ROSTER_UPDATE")
    end
    if template == "SecureHandlerStateTemplate" then
      f.__scripts.OnAttributeChanged = function(self, name, value)
        local stateid = name:match("^state%-(.+)")
        if stateid and self.__attrs["_onstate-" .. stateid] then c.runSnippet(self, self.__attrs["_onstate-" .. stateid], "self,stateid,newstate", self, stateid, value) end
      end
    end
    return f
  end
  c.runSnippet = function(header, body, signature, selfFrame, ...)
    assert(type(body) == "string", "a snippet")
    assert(not body:find("{", 1, true), "a restricted snippet with a table constructor")
    local chunk = assert(loadstring("return function(" .. signature .. ")\n" .. body .. "\nend", "snippet"))
    header.__env = header.__env or sandbox(c)
    header.__env.control = handle(c, header)
    setfenv(chunk, header.__env)
    return chunk()(handle(c, selfFrame), ...)
  end
  env.SecureHandlerSetFrameRef = function(f, label, ref) f.__attrs["frameref-" .. label] = ref end
  env.SecureHandlerWrapScript = function(f, script, header, pre, post)
    if c.combat then error("ADDON_ACTION_BLOCKED: a wrap in a fight", 2) end
    for _, s in ipairs({ pre, post }) do assert(not (s and s:find("{", 1, true)), "a restricted snippet with a table constructor") end
    f.__wraps = f.__wraps or {}
    f.__wraps[script] = { header = header, pre = pre, post = post }
  end
  function c.registerDriver(f, state, cond)
    c.drivers[f] = c.drivers[f] or {}
    c.drivers[f][state] = { cond = cond }
    c.resolveDrivers()
  end
  env.RegisterStateDriver = function(f, state, cond)
    if c.combat then error("ADDON_ACTION_BLOCKED: RegisterStateDriver in a fight", 2) end
    c.registerDriver(f, state, cond)
  end
  -- (a snippet run on a header: an insecure caller in a fight is blocked, SecureHandlers.lua's _execute attribute)
  env.SecureHandlerExecute = function(f, body)
    if c.combat then error("ADDON_ACTION_BLOCKED: SecureHandlerExecute in a fight", 2) end
    c.runSnippet(f, body, "self", f)
  end
  env.UnregisterStateDriver = function(f, state)
    if c.combat then error("ADDON_ACTION_BLOCKED: UnregisterStateDriver in a fight", 2) end
    if c.drivers[f] then c.drivers[f][state] = nil end
  end
  function c.resolveDrivers()
    for f, list in pairs(c.drivers) do
      for state, d in pairs(list) do
        local v
        if d.cond == "[combat] hide; show" then v = c.combat and "hide" or "show"
        elseif d.cond == "[combat] 1; 0" then v = c.combat and "1" or "0"
        else
          local unit = d.cond:match("^%[@([%w]+),dead%] 1; 0$")
          assert(unit, "a driver the mock knows: " .. d.cond)
          v = (c.units[unit] and c.units[unit].dead) and "1" or "0"
        end
        -- (the game's driver hands a number where the value reads as one, and sets it only when it differs from the
        -- frame's attribute: SecureStateDriver.lua's resolveDriver)
        if state == "visibility" then
          if d.value ~= v then
            d.value = v
            c.restricted = true
            if v == "show" then f:Show() else f:Hide() end
            c.restricted = false
          end
        elseif f.__attrs["state-" .. state] ~= (tonumber(v) or v) then
          d.value = v
          c.restricted = true
          f:SetAttribute("state-" .. state, tonumber(v) or v)
          c.restricted = false
        end
      end
    end
  end
  -- a click as the game does it: its PreClick, a wrap's pre snippet, the button's own and hooked OnClick, the wrap's post
  -- snippet (both edges of a click, each the button heard (RegisterForClicks), each running a wrap's snippets as the game
  -- does)
  function c.click(f, button)
    button = button or "LeftButton"
    local before = #c.casts
    local edges = f.__clickEdges or { "LeftButtonUp" }
    local function hears(down)
      for _, e in ipairs(edges) do
        if (e == "AnyUp" and not down) or (e == "AnyDown" and down) or e == button .. (down and "Down" or "Up") then return true end
      end
      return false
    end
    for _, down in ipairs({ true, false }) do
      if hears(down) then
        if f.__scripts.PreClick then f.__scripts.PreClick(f, button, down) end
        local w = f.__wraps and f.__wraps.OnClick
        local msg, go = nil, true
        if w then
          local nb
          nb, msg = c.runSnippet(w.header, w.pre, "self,button,down", f, button, down)
          if nb == false then go = false end
        end
        if go then
          if f.__scripts.OnClick then f.__scripts.OnClick(f, button, down) end
          if w and w.post and msg ~= nil then c.runSnippet(w.header, w.post, "self,message,button,down", f, msg, button, down) end
        end
      end
    end
    -- (with c.castEvents: a spell the click cast is heard as the game tells it after the click, SENT with its target's
    -- name (c.hideNames: hidden, as the client may), then SUCCEEDED, unless the game refused it (c.refuse: the global
    -- cooldown, a cast going, range))
    if c.castEvents then
      for k = before + 1, #c.casts do
        local cast = c.casts[k]
        if cast.type == "spell" then
          c.castN = (c.castN or 0) + 1
          local cg, who = "cast-auto-" .. c.castN, c.units[cast.unit or "target"]
          FIRE(c, "UNIT_SPELLCAST_SENT", "player", c.hideNames and secret() or (who and who.name or ""), cg, cast.spell)
          if not c.refuse then FIRE(c, "UNIT_SPELLCAST_SUCCEEDED", "player", cg, cast.spell) end
        end
      end
    end
  end
  function c.hover(f)
    local w = f.__wraps and f.__wraps.OnEnter
    if w then c.runSnippet(w.header, w.pre, "self", f) end
    if f.__scripts.OnEnter then f.__scripts.OnEnter(f) end
  end
  env.GameTooltip = { SetOwner = function(self, o, anchor) self.owner = o; self.anchor = anchor; self.point = nil; self.lines = {} end,
    ClearAllPoints = function(self) self.point = nil end, SetPoint = function(self, ...) self.point = { ... } end, SetText = function(self, t) self.lines = { t } end,
    AddLine = function(self, t) self.lines = self.lines or {}; self.lines[#self.lines + 1] = t end, Show = function() end, Hide = function(self) self.owner = nil end,
    GetOwner = function(self) return self.owner end, GetWidth = function() return 240 end,
    SetItemByID = function(self, id) self.lines = { (c.items[id] or {}).name or ("Item " .. id) } end }
  env.MenuUtil = { CreateContextMenu = function(owner, gen)
    local entries = {}
    local root = {}
    function root:CreateButton(text, fn) entries[#entries + 1] = { kind = "button", text = text, fn = fn } end
    function root:CreateCheckbox(text, get, set) entries[#entries + 1] = { kind = "check", text = text, get = get, fn = set } end
    function root:CreateDivider() end
    function root:CreateTitle(text) entries[#entries + 1] = { kind = "title", text = text } end
    gen(owner, root)
    c.menus[#c.menus + 1] = entries
  end }
  env.Settings = { RegisterCanvasLayoutCategory = function() return { ID = 1 } end, RegisterAddOnCategory = function() end }
  -- timers
  env.C_Timer = { After = function(s, fn) c.timers[#c.timers + 1] = { at = c.clock + s, fn = fn } end }
  -- units
  local function U(u) return c.units[u] end
  env.UnitGUID = function(u) local x = U(u); if not x then return nil end if c.combat and x.secretId then return secret() end return x.guid end
  -- (Forever's client: the first name, then the surname, Camelot's NameUtil.lua; nil second when the member has none)
  env.UnitName = function(u) local x = U(u); if not x then return nil end return x.name, x.surname end
  env.UnitClass = function(u) local x = U(u); if not x then return nil end return CLASS_NAME[x.class], x.class, 1 end
  env.UnitLevel = function(u) local x = U(u); return x and x.level or 0 end
  env.UnitIsDeadOrGhost = function(u) local x = U(u); return x and x.dead or false end
  -- (a hunter's Feign Death: dead to UnitIsDeadOrGhost, as the client reads it, and feigning)
  env.UnitIsFeignDeath = function(u) local x = U(u); return x and x.feign or false end
  env.UnitIsConnected = function(u) local x = U(u); return x and x.online ~= false end
  env.UnitIsVisible = function(u) local x = U(u); return x and x.visible ~= false end
  env.UnitGroupRolesAssigned = function(u) local x = U(u); return x and x.assigned or "NONE" end
  env.UnitIsGroupLeader = function(u) local x = U(u); return x and x.leader or false end
  env.UnitIsGroupAssistant = function(u) local x = U(u); return x and x.assist or false end
  env.UnitIsFriend = function() return true end
  env.UnitIsUnit = function(a, b) return U(a) and U(b) and U(a).guid == U(b).guid end
  env.UnitExists = function(u) return U(u) ~= nil end
  env.UnitIsDead = function(u) local x = U(u); return x and x.dead or false end
  -- (an instance group, a battleground's: c.instGroup; a premade there is in its home group too)
  env.IsInGroup = function(cat) if cat == 2 then return c.instGroup or false end return (c.o.group and #c.o.group > 1) or false end
  env.IsInRaid = function() return c.o.raid or false end
  env.GetNumGroupMembers = function() return c.o.group and #c.o.group or 0 end
  env.GetNumSubgroupMembers = function() return c.o.group and math.min(#c.o.group - 1, 4) or 0 end
  -- (the raid's roster names a member as the server writes it, Forever's surname after the first name, never UnitName's
  -- first name alone)
  env.GetRaidRosterInfo = function(i) local x = c.units["raid" .. i]; if not x then return nil end return x.name .. (x.surname and (" " .. x.surname) or ""), 0, x.sub or 1, x.level, CLASS_NAME[x.class], x.class end
  env.IsResting = function() return c.resting or false end
  env.IsInInstance = function() if c.instance then return true, c.instance end return false, "none" end
  env.IsMounted = function() return false end
  env.UnitOnTaxi = function() return c.taxi or false end
  env.UnitInVehicle = function() return false end
  env.UnitHasVehicleUI = function() return false end
  env.IsSwimming = function() return c.swimming or false end
  env.IsSubmerged = function() return c.submerged or false end
  env.CanDualWield = function() return c.dualWield or false end
  env.IsAltKeyDown = function() return false end
  env.CanInspect = function() return false end
  -- (a cast or channel going on: its name first, as the client answers; nil when none)
  env.UnitCastingInfo = function() return c.casting end
  env.UnitChannelInfo = function() return c.channel end
  -- auras
  -- (the auras secret in a fight; c.secretAuras true keeps them so out of one, as the client may for a while after it)
  local function aurasSecret() return c.combat or c.secretAuras == true end
  env.C_Secrets = { ShouldAurasBeSecret = aurasSecret, ShouldSpellAuraBeSecret = function(id) return aurasSecret() and not c.plainAuras[id] end,
    ShouldUnitIdentityBeSecret = function() return false end }
  env.C_UnitAuras = {
    GetAuraDataByIndex = function(u, i, filter)
      c.auraReads = c.auraReads or {}
      c.auraReads[u] = (c.auraReads[u] or 0) + 1
      local x = U(u)
      local a = x and x.auras and x.auras[i]
      if not a then return nil end
      if aurasSecret() then return { name = secret(), spellId = secret(), applications = secret(), expirationTime = secret(), sourceUnit = secret(), duration = secret() } end
      -- (a.secretId: an aura whose spell id the client keeps secret, its name plain)
      return { name = a.name or SPELL_NAMES[a.id] or ("Aura " .. a.id), spellId = a.secretId and secret() or a.id, applications = a.n or 1, expirationTime = a.exp or 0,
               sourceUnit = a.src, duration = a.dur or 0, icon = 1 }
    end,
    GetUnitAuraBySpellID = function(u, id)
      if c.combat and not c.plainAuras[id] then error("RequiresNonSecretAura", 2) end
      local x = U(u)
      for _, a in ipairs(x and x.auras or {}) do if a.id == id then return { spellId = id } end end
      return nil
    end,
  }
  -- spells
  env.C_SpellBook = { IsSpellKnown = function(id) return c.known[id] == true end }
  env.C_Spell = { GetSpellName = function(id) return SPELL_NAMES[id] end, GetSpellTexture = function(id) return 100000 + (id % 1000) end,
    GetSpellDescription = function(id) return SPELL_DESC[id] or "" end,
    IsSpellInRange = function(id, u) local x = U(u); if not x then return nil end if x.far then return false end return true end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
    -- (the SpellQueueWindow setting, in milliseconds: 400 by default)
    GetSpellQueueWindow = function() return c.queueWindow or 400 end,
    -- (a name looked up in your spellbook: the highest rank of it you know, else its first; an id stays itself; nothing
    -- for a spell the client lacks)
    GetSpellIDForSpellIdentifier = function(x)
      if type(x) == "number" then return x end
      local best, first
      for id, n in pairs(SPELL_NAMES) do
        if n == x then
          if not first or id < first then first = id end
          local lv, blv = SPELL_LEVELS[id] or 0, best and (SPELL_LEVELS[best] or 0) or -1
          if c.known[id] and (lv > blv or (lv == blv and id > best)) then best = id end
        end
      end
      return best or first
    end,
    -- (the level a rank is learned at: its SpellLevels' BaseLevel; 0 for one without)
    GetSpellLevelLearned = function(id) return SPELL_LEVELS[id] or 0 end }
  -- items and bags
  local function item(id) return c.items[id] or {} end
  env.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and (c.bagSlots or 16) or 0 end,
    GetContainerItemID = function(bag, slot) for _, b in ipairs(c.bags) do if b.bag == bag and b.slot == slot then return b.id end end return nil end,
    GetContainerItemCooldown = function(bag, slot) for _, b in ipairs(c.bags) do if b.bag == bag and b.slot == slot then return b.cdStart or 0, b.cd or 0, 1 end end return 0, 0, 1 end,
    GetItemCooldown = function(id) for _, b in ipairs(c.bags) do if b.id == id then return b.cdStart or 0, b.cd or 0, 1 end end return 0, 0, 1 end,
    GetContainerNumFreeSlots = function(bag) if bag ~= 0 then return 0, 0 end return c.freeSlots or (16 - #c.bags), 0 end,
  }
  -- (a bag slot's place, as ItemLocation:CreateFromBagAndSlot makes it)
  env.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
  env.C_Item = {
    GetItemCount = function(id) local n = 0; for _, b in ipairs(c.bags) do if b.id == id then n = n + (b.count or 1) end end return n end,
    GetItemInfo = function(id) local it = item(id); return it.name or ("Item " .. id), nil, 2, it.ilvl or 10, it.minLevel or 0, nil, nil, 1, it.equipLoc or "", 1, it.price or 1 end,
    GetItemInfoInstant = function(id) local it = item(id); return id, nil, nil, it.equipLoc or "", 1, it.classID or 15, it.subID or 0 end,
    IsEquippableItem = function(id) return (item(id).equipLoc or "") ~= "" end,
    GetItemSpell = function(id) local it = item(id); if it.spell and not it.uncached then return "Use", it.spell end return nil end,
    -- (a server-sent item the client has no data for yet: it.uncached; asking loads it, GET_ITEM_INFO_RECEIVED after)
    IsItemDataCachedByID = function(id) return not item(id).uncached end,
    RequestLoadItemDataByID = function(id) c.loadAsked = c.loadAsked or {}; c.loadAsked[id] = (c.loadAsked[id] or 0) + 1 end,
    GetItemIconByID = function(id) return 200000 + id % 1000 end,
    IsUsableItem = function(id) return item(id).usable ~= false end,
    -- (an item's range to a unit: nil for a unit not there, as the client answers)
    IsItemInRange = function(id, u) local x = U(u); if not x then return nil end return not x.far end,
    -- (the server's answer a moment later: the swap made, PLAYER_EQUIPMENT_CHANGED for each slot it changed; or
    -- refused with the game's red error and nothing changed: dead, a Unique-Equipped limit, a one-hander in the off
    -- hand without dual wield; a piece not yet bound asks the bind popup first and waits)
    EquipItemByName = function(id, slot)
      c.equips[#c.equips + 1] = { id, slot }
      c.timers[#c.timers + 1] = { at = c.clock + 0.2, fn = function() c.serverEquip(id, slot) end }
    end,
    GetItemUniquenessByID = function(id) local it = item(id); return it.unique or (it.limitCat ~= nil), it.limitCat and "Limit" or nil, it.limitMax, it.limitCat end,
    IsBound = function(loc) for _, b in ipairs(c.bags) do if b.bag == loc.bag and b.slot == loc.slot then return not b.boe end end return true end,
    GetDetailedItemLevelInfo = function(id) local it = item(id); return it.ilvl or 10, false, it.ilvl or 10 end,
  }
  -- equipping: the bag piece to the slot, the slot's piece to that bag slot (a two-hander's off hand to a free slot)
  function c.equipNow(id, slot)
    local from
    for i, b in ipairs(c.bags) do if b.id == id then from = i end end
    local old = c.equipped[slot]
    c.equipped[slot] = id
    if from and old then c.bags[from] = { id = old, bag = 0, slot = c.bags[from].slot }
    elseif from then table.remove(c.bags, from) end
    FIRE(c, "PLAYER_EQUIPMENT_CHANGED", slot, true)
    if slot == 16 and item(id).equipLoc == "INVTYPE_2HWEAPON" and c.equipped[17] then
      local oh = c.equipped[17]
      c.equipped[17] = nil
      c.bags[#c.bags + 1] = { id = oh, bag = 0, slot = 16 }
      FIRE(c, "PLAYER_EQUIPMENT_CHANGED", 17, false)
    end
    FIRE(c, "BAG_UPDATE_DELAYED")
  end
  c.uiErrors, c.bindPopups = {}, 0
  function c.serverEquip(id, slot)
    local me = c.units.player
    local held = false
    for _, b in ipairs(c.bags) do if b.id == id then held = b end end
    if not held then return end
    if me and me.dead then c.uiErrors[#c.uiErrors + 1] = "You can't do that while dead." return end
    if c.refuse and c.refuse[id] then c.uiErrors[#c.uiErrors + 1] = "Inventory is full." return end
    if held.boe then c.bindPopups = c.bindPopups + 1; FIRE(c, "EQUIP_BIND_CONFIRM", slot) return end
    local it = item(id)
    if slot == 17 and it.equipLoc == "INVTYPE_WEAPON" and not c.dualWield then c.uiErrors[#c.uiErrors + 1] = "You cannot dual-wield" return end
    if it.limitCat then
      local n = 0
      for s2, x in pairs(c.equipped) do if s2 ~= slot and item(x).limitCat == it.limitCat then n = n + 1 end end
      if n >= (it.limitMax or 1) then c.uiErrors[#c.uiErrors + 1] = "Unique-Equipped" return end
    end
    c.equipNow(id, slot)
  end
  env.GetInventoryItemID = function(_, slot) return c.equipped[slot] end
  -- (a weapon's oil, stone or poison: c.enchant[slot] true while one is on)
  env.GetWeaponEnchantInfo = function() local e = c.enchant or {}; return e[16] == true, 0, 0, 0, e[17] == true, 0, 0, 0 end
  env.GetInventoryItemCooldown = function(_, slot) local e = c.equipCD and c.equipCD[slot]; if e then return e[1], e[2], 1 end return 0, 0, 1 end
  env.C_TooltipInfo = {
    -- (an item's tooltip as the client gives it once loaded: its name and at least one more line)
    GetBagItem = function(bag, slot) for _, b in ipairs(c.bags) do if b.bag == bag and b.slot == slot then return { lines = c.tooltips[b.id] or { { leftText = item(b.id).name or "x" }, { leftText = "Use: something." } } } end end end,
    GetItemByID = function(id) return { lines = c.tooltips[id] or { { leftText = item(id).name or "x" }, { leftText = "Use: something." } } } end,
    GetInventoryItem = function(_, slot) local id = c.equipped[slot]; return { lines = id and c.tooltips[id] or { { leftText = "x" } } } end,
  }
  env.GetProfessions = function() local p = c.profs; return p[1] and 1 or nil, p[2] and 2 or nil, nil, p[3] and 3 or nil, p[4] and 4 or nil, nil end
  env.GetProfessionInfo = function(i) local p = c.profs[i]; if not p then return nil end return p[1], 0, p[2], 300 end
  -- talents: c.spec = skill line with the points
  env.C_ClassTalents = { GetActiveConfigID = function() return c.o.spec and 77 or nil end, GetTraitTreeForSpec = function() return 9 end }
  -- (dual spec: the spec group you are in, its combat config; c.o.spec is the talents of the active one)
  env.C_SpecializationInfo = { GetActiveSpecGroup = function() return c.specGroup or 1 end, GetCombatConfigIDForSpecGroup = function(g) return c.o.spec and (76 + g) or nil end }
  -- (Legacy, Forever's account perks: c.o.legacy = { [node] = rank }, its trees' configs 500 + the tree; no Legacy, no
  -- config, as a client without it answers)
  env.C_Traits = { GetConfigInfo = function() return { treeIDs = { 9 } } end,
    GetConfigIDByTreeID = function(tree) if c.o.legacy and (tree == 1187 or tree == 1188 or tree == 1189) then return 500 + tree end return nil end,
    GetGroupDisplayInfoByTreeID = function() return { { groupID = 1, skillLineID = c.o.spec or 0 }, { groupID = 2, skillLineID = 1 } } end,
    GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 1, currencyInfos = { { spent = 31 } } }, { traitNodeGroupID = 2, currencyInfos = { { spent = 5 } } } } end,
    -- (the tree's nodes: c.o.talents = { [spell id] = ranks taken }, one node each, its entry and definition the spell;
    -- a node never taken has rank 0, as the game lists every node of the tree)
    GetTreeNodes = function() local ids = { 900 }; for sp in pairs(c.o.talents or {}) do ids[#ids + 1] = sp end table.sort(ids); return ids end,
    GetNodeInfo = function(_, node) local r = (c.o.talents or {})[node] or (c.o.legacy or {})[node] or 0
      return { ID = node, activeRank = r, ranksPurchased = r, entryIDs = { node }, activeEntry = r > 0 and { entryID = node, rank = r } or nil } end,
    GetEntryInfo = function(_, entry) return { definitionID = entry } end,
    GetDefinitionInfo = function(def) return { spellID = def } end }
  -- places
  env.GetZoneText = function() return c.zone end
  env.GetRealZoneText = function() return c.zone end
  env.GetSubZoneText = function() return c.subzone end
  env.GetMinimapZoneText = function() return c.subzone ~= "" and c.subzone or c.zone end
  -- maps: where you stand (c.pos = { m, x, y }, 0 to 1), a map's place in its continent's yards (MAPS: a linear frame
  -- each, as the client's GetWorldPosFromMapPos answers: the continent, a Vector2D), the user's waypoint (c.waypoint)
  -- and its tracking (c.superTracked)
  local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
  env.CreateVector2D = vec
  env.UiMapPoint = { CreateFromCoordinates = function(m, x, y, z) return { uiMapID = m, position = vec(x, y), z = z } end }
  env.C_Map = { GetAreaInfo = function(id) return AREA_NAMES[id] end,
    GetBestMapForUnit = function(u) if u == "player" and c.pos and not c.instance then return c.pos.m end return nil end,
    GetPlayerMapPosition = function(m, u) if u == "player" and c.pos and c.pos.m == m and not c.instance then return vec(c.pos.x, c.pos.y) end return nil end,
    GetWorldPosFromMapPos = function(m, p) local M = MAPS[m]; if not M then return end return M.cont, vec(M.x0 + p.x * M.w, M.y0 + p.y * M.h) end,
    CanSetUserWaypointOnMap = function(m) return MAPS[m] ~= nil end,
    SetUserWaypoint = function(pt) if not MAPS[pt.uiMapID] then error("a waypoint on a map without one", 2) end c.waypoint = pt; return true end }
  env.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) c.superTracked = v end }
  env.UnitFactionGroup = function(u) local x = U(u); if not x then return nil end local f = x.faction or "Alliance"; return f, f end
  -- the merchant window: c.merchant = { item ids }, its NPC the unit "npc"
  env.GetMerchantNumItems = function() return c.merchant and #c.merchant or 0 end
  env.GetMerchantItemID = function(i) return c.merchant and c.merchant[i] or nil end
  -- the addon channel: every client in the world with a group hears it, the sender too (Forever echoes it); a whisper
  -- only its target's client (named by its sender's name, the realm cut, or its first name). c.sent keeps each with its
  -- prefix, channel and target
  env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, msg, ch, target)
      if c.lockdown then return 11 end
      c.said[#c.said + 1] = msg
      c.sent[#c.sent + 1] = { prefix = prefix, msg = msg, ch = ch, to = target, at = c.clock }
      for _, other in ipairs(WORLD) do
        local m = other.o.me
        if other.o.group == c.o.group and (ch ~= "WHISPER" or (m and (SENDER(m):match("^[^%-]+") == target or m.name == target))) then
          local me = c.units.player
          other.inbox[#other.inbox + 1] = { prefix, msg, ch, SENDER(me) }
        end
      end
      return 0
    end }
  -- addons loaded beside Cute Auras: c.addons = { [name] = { Version = ..., Title = ... } }
  env.C_AddOns = {
    IsAddOnLoaded = function(n) local on = c.addons ~= nil and c.addons[n] ~= nil; return on, on end,
    GetAddOnMetadata = function(n, field) local a = c.addons and c.addons[n]; return a and a[field] or nil end }
  c.inbox = {}
  return c
end

-- the group: one table shared by its clients; each client's units as the game names them for it
-- the maps the tests stand on: continent, origin and size in yards (a linear frame, as GetWorldPosFromMapPos is)
MAPS = { [1429] = { cont = 0, x0 = -10000, y0 = -2000, w = 3500, h = 2300 }, [1436] = { cont = 0, x0 = -11500, y0 = -1000, w = 3500, h = 2300 },
         [1411] = { cont = 1, x0 = -1000, y0 = -5000, w = 5300, h = 3500 } }
local function seat(c)
  local g = c.o.group
  c.units = {}
  if not g then c.units.player = c.o.me; return end
  if c.o.raid then
    for i, m in ipairs(g) do c.units["raid" .. i] = m; if m == c.o.me then c.units.player = m end end
  else
    c.units.player = c.o.me
    local k = 0
    for _, m in ipairs(g) do if m ~= c.o.me then k = k + 1; c.units["party" .. k] = m end end
  end
end

local function fire(c, event, ...)
  local list = c.events[event]
  if not list then return end
  local frames = {}
  for f, filt in pairs(list) do frames[#frames + 1] = { f, filt } end
  for _, p in ipairs(frames) do
    local f, filt = p[1], p[2]
    local ok = true
    if type(filt) == "table" then
      ok = false
      local u = ...
      for _, x in ipairs(filt) do if x == u then ok = true end end
    end
    if ok and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
  end
end
FIRE = fire
-- time goes on: timers due, OnUpdate scripts of shown frames, addon messages delivered, drivers looked at
local function tick(c, seconds)
  local stop = c.clock + (seconds or 0)
  repeat
    local step = math.min(0.1, math.max(0, stop - c.clock))
    c.clock = c.clock + step
    local due = {}
    for i = #c.timers, 1, -1 do if c.timers[i].at <= c.clock then due[#due + 1] = c.timers[i]; table.remove(c.timers, i) end end
    table.sort(due, function(a, b) return a.at < b.at end)
    for _, t in ipairs(due) do t.fn() end
    for _, f in ipairs(c.frames) do
      if f.__scripts.OnUpdate and f.__shown then f.__scripts.OnUpdate(f, step) end
    end
    -- (the game's tooltip asks its owner's UpdateTooltip every 0.2 s while it shows: GameTooltip_OnUpdate)
    local gt = c.env.GameTooltip
    gt.updateT = (gt.updateT or 0.2) - step
    if gt.updateT <= 0 then
      gt.updateT = 0.2
      local owner = gt.owner
      if type(owner) == "table" and owner.UpdateTooltip then owner:UpdateTooltip() end
    end
    for _, x in ipairs(WORLD) do
      local box = x.inbox
      x.inbox = {}
      for _, m in ipairs(box) do fire(x, "CHAT_MSG_ADDON", m[1], m[2], m[3], m[4]) end
    end
    c.resolveDrivers()
  until c.clock >= stop
end
local function tickAll(seconds)
  for _ = 1, math.max(1, math.floor((seconds or 0) / 0.5)) do for _, c in ipairs(WORLD) do tick(c, 0.5) end end
end

-- loading the addon into a client
local function load(c)
  seat(c)
  local A = {}
  local toc = assert(io.open(DIR .. "CuteAuras.toc")):read("*a")
  for file in toc:gmatch("\n([%w_]+%.lua)") do
    local fn = assert(loadstring(assert(io.open(DIR .. file)):read("*a"), "@" .. file))
    setfenv(fn, c.env)
    fn("CuteAuras", A)
  end
  c.A = A
  c.env.CuteAurasDB = c.o.db
  fire(c, "PLAYER_LOGIN")
  fire(c, "PLAYER_ENTERING_WORLD")
  return c
end
local function fight(c, on)
  c.combat = on
  fire(c, on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
  c.resolveDrivers()
end

----------------------------------------------------------------------------
-- the names of the spells the tests use (the client's, from the generated data)
----------------------------------------------------------------------------
do
  local D = {}
  local fn = assert(loadstring(assert(io.open(DIR .. "Data.lua")):read("*a")))
  setfenv(fn, { })
  local A = {}
  fn("CuteAuras", A)
  D = A.Data
  for _, list in pairs(D.BUFFS) do
    for _, e in ipairs(list) do
      for _, sp in ipairs(e.one or { e }) do for i, id in ipairs(sp.ranks) do SPELL_NAMES[id], SPELL_LEVELS[id] = sp.name, sp.levels[i] end end
      for i, id in ipairs(e.group or {}) do SPELL_NAMES[id], SPELL_LEVELS[id] = e.groupName, e.groupLevels[i] end
    end
  end
  for _, e in pairs(D.BLESS) do
    for i, id in ipairs(e.ranks) do SPELL_NAMES[id], SPELL_LEVELS[id] = e.name, e.levels[i] end
    for i, id in ipairs(e.group or {}) do SPELL_NAMES[id], SPELL_LEVELS[id] = e.groupName, e.groupLevels[i] end
  end
  for _, e in pairs(D.HANDS) do for i, id in ipairs(e.ranks) do SPELL_NAMES[id], SPELL_LEVELS[id] = e.name, e.levels[i] end end
  -- (Dampen Magic, a mage's habit in the tests: rank 1 at level 12, 2 at 24, as SpellLevels says)
  SPELL_LEVELS[604], SPELL_LEVELS[8450] = 12, 24
  SPELL_NAMES[1283391], SPELL_NAMES[1229741], SPELL_NAMES[1229739] = "Campfire Nearby", "Camp Benefits", "Welcoming Campfire"
  SPELL_DESC[1306908] = "Movement speed increased by 3% in Snowy areas."
  SPELL_DESC[17538] = "Increases Agility by 25 and chance to get a critical strike by 2% for 1 hour."
  SPELL_DESC[11396] = "Increases Intellect by 25 for 1 hour."
  SPELL_DESC[3593] = "Increases the player's maximum health by 120 for 1 hour."
  HARNESS_DATA = D
end
local D = HARNESS_DATA

local function member(o)
  o.guid = o.guid or ("Player-1-" .. o.name)
  o.auras = o.auras or {}
  return o
end
-- (every rank a level has learned; of two ids of one level in a list, the first alone: the second is the rank's proc,
-- Lightning Shield's bolt (26364 after 324), never learned, as IsSpellKnown answers in the game)
local function knowAll(c, class, level)
  for _, e in ipairs(D.BUFFS[class] or {}) do
    for _, sp in ipairs(e.one or { e }) do
      for i, id in ipairs(sp.ranks) do
        local lv = sp.levels[i] or 0
        if lv <= level and (i == 1 or lv ~= (sp.levels[i - 1] or 0)) then c.known[id] = true end
      end
    end
    for i, id in ipairs(e.group or {}) do if (e.groupLevels[i] or 0) <= level then c.known[id] = true end end
  end
  if class == "PALADIN" then
    for _, e in pairs(D.BLESS) do for i, id in ipairs(e.ranks) do if e.levels[i] <= level then c.known[id] = true end end end
    for _, e in pairs(D.HANDS) do for i, id in ipairs(e.ranks) do if e.levels[i] <= level then c.known[id] = true end end end
  end
end
local function noErrors(c, label)
  if #c.A.errors > 0 then
    local t = {}
    for _, e in ipairs(c.A.errors) do t[#t + 1] = type(e) == "table" and (e.msg .. " (" .. (e.n or 1) .. "x)") or tostring(e) end
    error((label or "") .. ": the addon caught errors:\n  " .. table.concat(t, "\n  "), 2)
  end
end
-- a card's text fits its room at Friz: a title on its one line, a line in its lines (word-wrapped), never cut
function FITS(fs, label)
  local w, lines, t = fs.__w, (fs.__wrap and fs.__maxLines) or 1, fs.__text or ""
  assert(w and w > 0, label .. ": a width")
  if lines == 1 then
    assert(TEXT_WIDTH(t, fs.__size) <= w, string.format("%s: '%s' is %d wide at %s, its room %d", label, t, TEXT_WIDTH(t, fs.__size), tostring(fs.__size), w))
  else
    local n = WRAP_LINES(t, fs.__size, w)
    assert(n <= lines, string.format("%s: '%s' takes %d lines at %s, room for %d", label, t, n, tostring(fs.__size), lines))
  end
end
local function shown(c, part) return c.A.Bar.Shown(part) end
local function find(list, key) for _, r in ipairs(list or {}) do if r.key == key then return r end end return nil end
local function icon(c, which, key) return c.env["CuteAuras" .. (which == "group" and "Group_" or "Bar_") .. key:gsub("[^%w]", "_")] end
local passed = 0
local function test(name, fn)
  WORLD = {}
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then io.stderr:write("FAIL " .. name .. "\n" .. tostring(err) .. "\n"); os.exit(1) end
  passed = passed + 1
  print("ok  " .. name)
end
local function client(o)
  local c = newClient(o)
  WORLD[#WORLD + 1] = c
  return c
end

----------------------------------------------------------------------------
-- scenarios
----------------------------------------------------------------------------
test("solo priest: Inner Fire and Fortitude on yourself, secure clicks set, nothing caught", function()
  local me = member({ name = "Solo", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 1)
  noErrors(c, "login")
  local mine = shown(c, "mine")
  assert(find(mine, "self:innerfire"), "Inner Fire missing on the bar")
  local duty = find(shown(c, "group"), "duty:fort")
  assert(duty, "Fortitude on yourself")
  local b = icon(c, "group", "duty:fort")
  assert(b and b:GetAttribute("type1") == "spell" and b:GetAttribute("unit") == "player", "the duty icon casts on you")
  assert(b:GetAttribute("spell") == 2791, "the highest Fortitude a level 40 knows (rank 4, 2791): " .. tostring(b:GetAttribute("spell")))
  -- with the aura on, it goes (Inner Fire 4, the highest a level 40 knows: a lower one asks for an Upgrade)
  table.insert(me.auras, { id = 2791, src = "player", exp = c.clock + 3600, dur = 3600 })
  table.insert(me.auras, { id = 1006, src = "player", exp = c.clock + 600, dur = 600 })
  fire(c, "UNIT_AURA", "player")
  tick(c, 1)
  assert(not find(shown(c, "group"), "duty:fort") and not find(shown(c, "mine"), "self:innerfire"), "buffed: nothing to do")
  noErrors(c)
end)

test("camp: Sit by a fire, a feature you may place, blueprints only when usable (no level, class or race outside yours)", function()
  local me = member({ name = "Camper", class = "WARRIOR", level = 30, auras = { { id = 1283391, exp = 0 } } })
  local c = client({ me = me, profs = { { "Blacksmithing", 160 }, { "Alchemy", 50 } } })
  c.items[279944] = { name = "Sharpening Wheel" }
  c.items[279988] = { name = "Anvil" }
  c.items[273085] = { name = "Blueprint: Fermenter" }   -- Alchemy 140: not yours
  c.items[273086] = { name = "Blueprint: Anvil" }       -- Blacksmithing 140: yours
  c.items[273113] = { name = "Blueprint: Master Forge" } -- Blacksmithing 300: the red line
  c.tooltips[273113] = { { leftText = "Blueprint: Master Forge" }, { leftText = "Requires Blacksmithing (300)", leftColor = { r = 1, g = 0.125, b = 0.125 } } }
  c.items[273099] = { name = "Blueprint: Spinning Wheel", minLevel = 45 }
  local slot = 0
  for _, id in ipairs({ 279944, 273085, 273086, 273113, 273099 }) do slot = slot + 1; c.bags[#c.bags + 1] = { id = id, bag = 0, slot = slot } end
  c.profs = { { "Blacksmithing", 160 }, { "Alchemy", 50 } }
  load(c)
  tick(c, 1)
  noErrors(c, "camp")
  local camp = shown(c, "camp")
  assert(find(camp, "sit"), "Sit by the fire")
  local place = find(camp, "place279944")
  assert(place and place.click.item == 279944, "the Sharpening Wheel to place")
  local bp = find(camp, "blueprint")
  assert(bp and bp.count == nil or (bp and bp.count == 1), "one blueprint usable")
  assert(bp.click.item == 273086, "only Blueprint: Anvil is yours: " .. tostring(bp.click.item))
  -- the Use reminder's rule: a red line, a level above yours
  assert(c.A.Spells.Usable(273113, 0, 4) == false, "a red requirement line: not usable")
  assert(c.A.Spells.Usable(273099, 0, 5) == false, "a required level above yours: not usable")
  noErrors(c)
end)

-- (a refresh of the whole bar now, as an event would ask)
local function campNow(c) c.A.Bar.Dirty(); tick(c, 1) end
local function keysOf(list) local t = {}; for _, r in ipairs(list or {}) do t[#t + 1] = r.key end return table.concat(t, ",") end
-- (standing still 20 s: the moment the pause icons wait for)
local function standStill(c) fire(c, "PLAYER_STOPPED_MOVING"); tick(c, 21) end

test("food: best fits your role then item level (no fishing or zone-speed food, no recipe); never a food above your level", function()
  assert(D.FOOD[728] == nil, "Recipe: Westfall Stew (Item class 9) is no food")
  assert(D.FOOD[8957].w == "" and D.FOOD[267341].w == "" and D.FOOD[20452].w == "str" and D.FOOD[13933].w == "spell", "the foods' words")
  local function setup(class, level)
    local me = member({ name = "Eater" .. class, class = class, level = level })
    local c = client({ me = me })
    -- (each ilvl 55 save Sweetpaw Jam's 60, as ItemSparse says; Spinefin Halibut the lowest id; Baked Salmon the cheapest)
    c.items[8957] = { name = "Spinefin Halibut", classID = 0, subID = 5, ilvl = 55, minLevel = 45, price = 6 }
    c.items[13933] = { name = "Lobster Stew", classID = 0, subID = 5, ilvl = 55, minLevel = 45, price = 12 }
    c.items[20452] = { name = "Smoked Desert Dumplings", classID = 0, subID = 5, ilvl = 55, minLevel = 45, price = 50 }
    c.items[267341] = { name = "Sweetpaw Jam", classID = 0, subID = 8, ilvl = 60, minLevel = 55, price = 100 }
    c.items[13935] = { name = "Baked Salmon", classID = 0, subID = 5, ilvl = 55, minLevel = 45, price = 2 }
    c.items[724] = { name = "Goretusk Liver Pie", classID = 0, subID = 5, ilvl = 15, minLevel = 5, price = 8 }
    -- (a recipe a game learned as food before this round: the client's class says recipe, never eaten)
    c.items[728] = { name = "Recipe: Westfall Stew", classID = 9, subID = 5, ilvl = 15, price = 1 }
    c.o.db = { acct = { food = { [728] = true } } }
    local slot = 0
    for _, id in ipairs({ 8957, 13933, 20452, 267341, 13935, 724, 728 }) do slot = slot + 1; c.bags[#c.bags + 1] = { id = id, bag = 0, slot = slot, count = 5 } end
    load(c)
    tick(c, 1)
    return c
  end
  local c = setup("WARRIOR", 60)
  local Camp = c.A.Camp
  assert(Camp.BestFood(true) == 20452, "a warrior's best: the Dumplings' Strength, not the Jam's Hyjal speed, the Halibut's Fishing or the Stew's spell damage: " .. tostring(Camp.BestFood(true)))
  assert(Camp.BestFood(false) == 13935, "the camp's Eat: the cheapest Well Fed, never the recipe: " .. tostring(Camp.BestFood(false)))
  -- in a dungeon: the Well Fed reminder offers the same
  c.instance = "party"
  campNow(c)
  local fedRec = find(shown(c, "mine"), "food")
  assert(fedRec and fedRec.click.item == 20452, "the dungeon's Eat: the Dumplings: " .. tostring(fedRec and fedRec.click.item))
  noErrors(c, "warrior")
  local m = setup("MAGE", 60)
  assert(m.A.Camp.BestFood(true) == 13933, "a mage's best: the first spell-damage food: " .. tostring(m.A.Camp.BestFood(true)))
  -- level 40: every level-45 food is out; the pie (level 5) is the one left, both ways
  local low = setup("WARRIOR", 40)
  assert(low.A.Camp.BestFood(true) == 724 and low.A.Camp.BestFood(false) == 724, "level 40: only Goretusk Liver Pie: " .. tostring(low.A.Camp.BestFood(false)))
  noErrors(low, "low")
end)

test("camp: the oven and the feast wait while a feature does, after Eat; theirs is the shared hour", function()
  local me = member({ name = "Baker", class = "WARRIOR", level = 60, auras = { { id = 1283391, exp = 0 } } })
  local c = client({ me = me, profs = { { "Blacksmithing", 160 }, { "Skinning", 300 }, { "Fishing", 1 }, { "Cooking", 300 } } })
  c.items[279944] = { name = "Sharpening Wheel" }
  c.items[279938] = { name = "Trapper's Workbench" }
  c.items[279982] = { name = "Iron Oven" }
  c.items[279957] = { name = "Cookie's Feast" }
  c.items[724] = { name = "Goretusk Liver Pie", classID = 0, subID = 5, ilvl = 15, price = 8 }
  local slot = 0
  for _, id in ipairs({ 279944, 279938, 279982, 279957, 724 }) do slot = slot + 1; c.bags[#c.bags + 1] = { id = id, bag = 0, slot = slot } end
  load(c)
  tick(c, 1)
  noErrors(c, "baker")
  local camp = shown(c, "camp")
  assert(keysOf(camp) == "sit,place279938,place279944,eat" or keysOf(camp) == "sit,place279944,place279938,eat",
    "Sit, both features and Eat; the oven and the feast wait: " .. keysOf(camp))
  -- both features' buffs on: the oven and the feast, after Eat, each saying the hour is shared
  table.insert(me.auras, { id = 1230172, exp = c.clock + 3600 })
  table.insert(me.auras, { id = 1229519, exp = c.clock + 3600 })
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  camp = shown(c, "camp")
  local oven, feast = find(camp, "cookfire279982"), find(camp, "cookfire279957")
  assert(oven and feast and camp[#camp].key:find("^cookfire") and find(camp, "eat"), "the oven and the feast now, last: " .. keysOf(camp))
  assert(oven.why:find("share an hour's cooldown", 1, true), "the oven's tooltip says the hour: " .. tostring(oven.why))
  -- the oven placed: its spell spends the hour (the item's own cooldown not read yet): no feast, no feature
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", D.COOKFIRE[279982].sp)
  me.auras = { { id = 1283391, exp = 0 } }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  camp = shown(c, "camp")
  assert(not find(camp, "cookfire279957") and not find(camp, "place279944") and not find(camp, "place279938"), "the hour spent by the oven: " .. keysOf(camp))
  noErrors(c)
end)

test("camp: Legacy's Field Guide shortens the shared hour, Gourmand lengthens Well Fed's minutes", function()
  local function setup(legacy)
    local me = member({ name = "Guide", class = "WARRIOR", level = 30, auras = { { id = 1283391, exp = 0 } } })
    local c = client({ me = me, legacy = legacy, profs = { { "Blacksmithing", 160 } } })
    c.items[279944] = { name = "Sharpening Wheel" }
    c.items[724] = { name = "Goretusk Liver Pie", classID = 0, subID = 5, ilvl = 15, price = 8 }
    c.bags = { { id = 279944, bag = 0, slot = 1 }, { id = 724, bag = 0, slot = 2 } }
    load(c)
    tick(c, 1)
    return c, me
  end
  local c = setup({ [110304] = 3, [110313] = 1 })
  local place = find(shown(c, "camp"), "place279944")
  assert(place and place.why:find("share a 45-minute cooldown", 1, true), "Field Guide 3: 45 minutes: " .. tostring(place and place.why))
  local eat = find(shown(c, "camp"), "eat")
  assert(eat and eat.why:find("+3 Strength, 20 min", 1, true), "Gourmand 1: 15 min reads 20: " .. tostring(eat and eat.why))
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1307392)
  campNow(c)
  assert(not find(shown(c, "camp"), "place279944"), "placed: the hour runs")
  c.clock = c.clock + 2701
  campNow(c)
  assert(find(shown(c, "camp"), "place279944"), "Field Guide 3: Place again after 45 minutes")
  noErrors(c)
  -- no Legacy: the hour, and still hidden at 46 minutes
  local d = setup(nil)
  local p0 = find(shown(d, "camp"), "place279944")
  assert(p0 and p0.why:find("share an hour's cooldown", 1, true), "no Legacy: an hour")
  assert(find(shown(d, "camp"), "eat").why:find("15 min", 1, true), "no Gourmand: 15 min")
  fire(d, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1307392)
  d.clock = d.clock + 2760
  campNow(d)
  assert(not find(shown(d, "camp"), "place279944"), "no Field Guide: hidden at 46 minutes")
  noErrors(d)
end)

test("camp: Light only a kit you may use and off its cooldown; a non-cook gets the one-time Cook instead", function()
  local me = member({ name = "Lighter", class = "WARRIOR", level = 30 })
  local c = client({ me = me, profs = { { "Cooking", 150 } } })
  c.known[2550] = true
  c.items[279974] = { name = "Expert Campfire Kit" }
  c.tooltips[279974] = { { leftText = "Expert Campfire Kit" }, { leftText = "Requires Cooking (220)", leftColor = { r = 1, g = 0.125, b = 0.125 } } }
  c.items[279981] = { name = "Basic Campfire Kit" }
  c.bags = { { id = 279974, bag = 0, slot = 1 }, { id = 279981, bag = 0, slot = 2 } }
  load(c)
  standStill(c)
  noErrors(c, "lighter")
  local rec = find(shown(c, "camp"), "fire")
  assert(rec and rec.click.item == 279981, "Cooking 150: the Basic kit, not the Expert one: " .. tostring(rec and rec.click.item))
  -- lit: the kits' 5-minute cooldown, no Light (and no Buy: a kit is in the bags)
  c.bags[2].cdStart, c.bags[2].cd = c.clock, 300
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1307227)
  campNow(c)
  assert(not find(shown(c, "camp"), "fire") and not find(shown(c, "camp"), "wood"), "a kit on cooldown: nothing to light: " .. keysOf(shown(c, "camp")))
  noErrors(c)
  -- not a cook, a kit handed to them: no Light; Cook once, for ten minutes
  local me2 = member({ name = "Nocook", class = "WARRIOR", level = 10 })
  local n = client({ me = me2 })
  n.items[279981] = { name = "Basic Campfire Kit" }
  n.tooltips[279981] = { { leftText = "Basic Campfire Kit" }, { leftText = "Requires Cooking (1)", leftColor = { r = 1, g = 0.125, b = 0.125 } } }
  n.bags = { { id = 279981, bag = 0, slot = 1 } }
  load(n)
  standStill(n)
  assert(not find(shown(n, "camp"), "fire"), "a kit you can't use: no Light")
  local cook = find(shown(n, "camp"), "cook")
  assert(cook and cook.lit == false and cook.word == "Cook", "the Cook nudge")
  n.clock = n.clock + 601
  campNow(n)
  assert(not find(shown(n, "camp"), "cook"), "Cook: ten minutes, then never")
  noErrors(n)
end)

test("camp: Buy, the nearest seller of Simple Wood or Flint and Tinder, on the game's map pin; merchants you open win", function()
  local me = member({ name = "Woodless", class = "WARRIOR", level = 20, faction = "Alliance" })
  local c = client({ me = me, profs = { { "Cooking", 60 } } })
  c.known[2550] = true
  c.pos = { m = 1429, x = 0.44, y = 0.60 }
  load(c)
  -- a kit lit once (the spell heard): a cook who has used one
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1307227)
  standStill(c)
  noErrors(c, "woodless")
  local rec = find(shown(c, "camp"), "wood")
  assert(rec and rec.lit == false and rec.word == "Buy", "Buy: no kit, no wood, no flint: " .. keysOf(shown(c, "camp")))
  assert(rec.why:find("you have neither", 1, true) and rec.why:find("Classic data", 1, true), "a Classic seller, said so: " .. rec.why)
  assert(rec.seller and rec.seller.m == 1429, "a seller on your map")
  -- its click: the game's own pin there, tracked; no secure action
  local b = icon(c, "own", "wood")
  assert(b and b:GetAttribute("type1") == nil, "an unlit icon casts nothing")
  c.click(b, "LeftButton")
  assert(c.waypoint and c.waypoint.uiMapID == 1429 and math.abs(c.waypoint.position.x - rec.seller.x) < 1e-6 and c.superTracked == true,
    "the pin on the seller, tracked")
  -- a merchant you open that sells both, a little farther than the seed would be: noted, and the one shown
  c.units.npc = { name = "Test Trader", guid = "Creature-0-1-0-1-99999-0000001" }
  c.pos = { m = 1429, x = 0.47, y = 0.60 }
  c.merchant = { 117, 4470, 4471 }
  fire(c, "MERCHANT_SHOW")
  local seen = c.env.CuteAurasDB.acct.sell["99999"]
  assert(seen and seen.g == 3 and seen.m == 1429, "the merchant noted with its goods and place")
  c.pos = { m = 1429, x = 0.44, y = 0.60 }
  campNow(c)
  rec = find(shown(c, "camp"), "wood")
  assert(rec and rec.why:find("Test Trader sells both", 1, true) and not rec.why:find("Classic data", 1, true), "the merchant seen in play: " .. tostring(rec and rec.why))
  -- a merchant that sells neither any more: let go
  c.merchant = { 117 }
  fire(c, "MERCHANT_UPDATE")
  assert(c.env.CuteAurasDB.acct.sell["99999"] == nil, "a merchant without the goods: let go")
  -- wood and flint in the bags: Make, not Buy; in town, a seller farther than 2 minutes: nothing
  c.known[1229737] = true
  c.bags = { { id = 4470, bag = 0, slot = 1 }, { id = 4471, bag = 0, slot = 2 } }
  c.items[4470], c.items[4471] = { name = "Simple Wood" }, { name = "Flint and Tinder" }
  campNow(c)
  rec = find(shown(c, "camp"), "fire")
  assert(rec and rec.word == "Make" and not find(shown(c, "camp"), "wood"), "wood and flint: Make: " .. keysOf(shown(c, "camp")))
  c.bags = {}
  c.resting = true
  c.pos = { m = 1411, x = 0.5, y = 0.5 }
  campNow(c)
  assert(not find(shown(c, "camp"), "wood"), "no seller of your side on that continent: nothing")
  noErrors(c)
end)

-- a party of five: two priests and a paladin run Cute Auras, a rogue, a warrior tank and a hunter don't
local function party5()
  local P1 = member({ name = "Aprie", class = "PRIEST", level = 50, guid = "Player-1-A1", assigned = "HEALER" })
  local P2 = member({ name = "Bprie", class = "PRIEST", level = 50, guid = "Player-1-B2" })
  local PAL = member({ name = "Cpal", class = "PALADIN", level = 50, guid = "Player-1-C3" })
  local ROG = member({ name = "Drog", class = "ROGUE", level = 50, guid = "Player-1-D4" })
  local WAR = member({ name = "Ewar", class = "WARRIOR", level = 50, guid = "Player-1-E5", assigned = "TANK" })
  local group = { P1, P2, PAL, ROG, WAR }
  local c1 = client({ me = P1, group = group, spec = 56 })
  local c2 = client({ me = P2, group = group, spec = 78 })
  local c3 = client({ me = PAL, group = group, spec = 184 })
  knowAll(c1, "PRIEST", 50); knowAll(c2, "PRIEST", 50); knowAll(c3, "PALADIN", 50)
  load(c1); load(c2); load(c3)
  tickAll(12)
  return { c1 = c1, c2 = c2, c3 = c3, P1 = P1, P2 = P2, PAL = PAL, ROG = ROG, WAR = WAR, group = group }
end

test("party: the clients hear each other and share Fortitude out the same way (the first priest by GUID gives it all)", function()
  local g = party5()
  for _, c in ipairs({ g.c1, g.c2, g.c3 }) do noErrors(c, "party") end
  assert(g.c1.A.Comm.peers[g.P2.guid] and g.c1.A.Comm.peers[g.PAL.guid], "priest one heard the others")
  assert(g.c2.A.Comm.peers[g.P1.guid], "priest two heard priest one")
  local d1 = find(g.c1.A.Assign.duties, nil)
  local function duty(c, key) for _, d in ipairs(c.A.Assign.duties) do if d.key == key then return d end end end
  assert(duty(g.c1, "fort") and #duty(g.c1, "fort").targets == 5, "priest A gives Fortitude to all five")
  assert(not duty(g.c2, "fort"), "priest B gives none: not every priest")
  -- the shadow priest gives Divine Spirit? A knows it at 50 (talent ranks known by both here): the first by GUID again
  assert(duty(g.c1, "spirit") and not duty(g.c2, "spirit"), "Divine Spirit: one priest")
  -- Divine Spirit only to mana users: never the rogue or the warrior
  for _, m in ipairs(duty(g.c1, "spirit").targets) do assert(m.class ~= "ROGUE" and m.class ~= "WARRIOR", "Spirit to a " .. m.class) end
end)

test("blessings by role: the tank Kings, the rogue Might, healers Wisdom, never Wisdom without a mana bar", function()
  local g = party5()
  local As = g.c3.A.Assign
  local pal = g.PAL.guid
  local function of(class, role) return As.BlessingOf(pal, class .. ":" .. role) end
  assert(of("WARRIOR", "tank") == "kings", "the tank: Kings, got " .. tostring(of("WARRIOR", "tank")))
  assert(of("ROGUE", "melee") == "might", "the rogue: Might")
  assert(of("PRIEST", "healer") == "wisdom", "the holy priest: Wisdom")
  assert(of("PRIEST", "caster") == "wisdom", "the shadow priest (their spec announced): Wisdom")
  assert(of("PALADIN", "melee") == "might", "a Retribution paladin: Might first")
  -- every client computes the same
  assert(g.c1.A.Assign.BlessingOf(pal, "ROGUE:melee") == "might", "priest one's client agrees")
  -- the paladin's bar: Might, Kings and Wisdom duties
  local keys = {}
  for _, d in ipairs(As.duties) do keys[d.key] = #d.targets end
  assert(keys["bless:might"] and keys["bless:kings"] and keys["bless:wisdom"], "three blessings to give")
  noErrors(g.c3)
end)

test("two paladins: the k-th gives each bucket its k-th wish; a hand-set blessing travels and wins", function()
  local A1 = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-P1", leader = true })
  local A2 = member({ name = "Bpal", class = "PALADIN", level = 55, guid = "Player-1-P2" })
  local R = member({ name = "Crog", class = "ROGUE", level = 60, guid = "Player-1-R3" })
  local M = member({ name = "Dmag", class = "MAGE", level = 60, guid = "Player-1-M4" })
  local group = { A1, A2, R, M }
  local c1 = client({ me = A1, group = group, spec = 594 })
  local c2 = client({ me = A2, group = group, spec = 184 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "PALADIN", 55)
  load(c1); load(c2)
  tickAll(12)
  local As = c1.A.Assign
  assert(As.BlessingOf(A1.guid, "ROGUE:melee") == "might" and As.BlessingOf(A2.guid, "ROGUE:melee") == "kings", "rogue: Might from the first, Kings from the second")
  assert(As.BlessingOf(A1.guid, "MAGE:caster") == "wisdom" and As.BlessingOf(A2.guid, "MAGE:caster") == "kings", "mage: Wisdom, then Kings")
  -- the second paladin sets their own Kings to Might for the mage... a mage with Might is wrong, but it is their call
  c2.A.Assign.Set(A2.guid, "MAGE:caster", "might")
  tickAll(3)
  assert(c1.A.Assign.BlessingOf(A2.guid, "MAGE:caster") == "might", "the hand-set blessing reached the other client")
  -- the second paladin (not the leader) may not change the first's
  assert(c2.A.Assign.Set(A1.guid, "MAGE:caster", "kings") == false, "only the paladin, the leader or an assist")
  noErrors(c1); noErrors(c2)
end)

test("a death in a fight: the one buffer who owes it gets the secure rebuff card; a click casts; nothing blocked", function()
  local g = party5()
  local c = g.c1
  c.castEvents = true
  local rb = c.env.CuteAurasRebuff
  assert(rb and not rb:IsShown(), "the card hidden at rest")
  assert(c.A.Rebuff.slots >= 3, "slots for the owed members: " .. c.A.Rebuff.slots)
  fight(c, true); fight(g.c2, true)
  g.ROG.dead = true
  tickAll(1)
  assert(not rb:IsShown(), "dead: nothing yet")
  g.ROG.dead = false -- (a soulstone, a battle res)
  tickAll(1)
  assert(rb:IsShown(), "back up: the card shows")
  local unit = rb:GetAttribute("unit")
  assert(c.units[unit] == g.ROG, "set to the rogue: " .. tostring(unit))
  assert(rb:GetAttribute("spell") == 10937, "Fortitude rank 5 for a level 50: " .. tostring(rb:GetAttribute("spell")))
  assert(not g.c2.env.CuteAurasRebuff:IsShown(), "the other priest owes nothing: no card")
  assert(c.A.Rebuff.shows == 1, "one card shown: " .. c.A.Rebuff.shows)
  tick(c, 3)
  local sounds = c.sounds or 0
  c.casts = {}
  c.click(rb)
  assert(#c.casts == 1 and c.casts[1].unit == unit, "the click cast on the rogue")
  -- (the game saw it land: the card says so and waits for a right-click; your own click plays no sound, counts no card)
  assert(rb:IsShown() and rb.text:GetText():find("All your buffs are on them", 1, true), "landed: " .. rb.text:GetText())
  assert((c.sounds or 0) == sounds and c.A.Rebuff.shows == 1, "no sound and no new card for your own click")
  c.click(rb, "MiddleButton")
  assert(#c.casts == 1 and rb:IsShown(), "a middle click: nothing")
  c.click(rb, "RightButton")
  assert(#c.casts == 1 and not rb:IsShown(), "a right-click: done with them, nothing cast")
  -- a second death: the warrior (no mana: Fortitude only); a shift-click casts too
  g.WAR.dead = true; tickAll(1); g.WAR.dead = false; tickAll(1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.WAR, "the warrior next")
  c.mod = "shift-"
  c.click(rb)
  c.mod = nil
  assert(#c.casts == 2 and c.casts[2].unit == rb:GetAttribute("unit"), "a shift-click cast")
  c.click(rb, "RightButton")
  assert(not rb:IsShown(), "the warrior done")
  -- the other priest, owed Fortitude and Divine Spirit: a click the game refuses (the global cooldown) comes round again
  g.P2.dead = true; tickAll(1); g.P2.dead = false; tickAll(1)
  assert(rb:IsShown() and rb:GetAttribute("spell") == 10937, "Fortitude first")
  c.casts = {}
  c.click(rb)
  local spirit = rb:GetAttribute("spell")
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.P2 and spirit ~= 10937, "then Divine Spirit: " .. tostring(spirit))
  assert(rb.text:GetText():find("Click to buff them", 1, true), "Divine Spirit not cast yet: " .. rb.text:GetText())
  c.refuse = true
  c.click(rb)
  c.refuse = nil
  assert(rb:IsShown() and rb:GetAttribute("spell") == 10937 and rb.text:GetText():find("is on them", 1, true), "back to Fortitude, which landed: " .. rb.text:GetText())
  c.click(rb)
  assert(rb:GetAttribute("spell") == spirit, "the refused Divine Spirit came round again")
  c.click(rb)
  assert(#c.casts == 4 and rb.text:GetText():find("All your buffs", 1, true), "both landed: " .. rb.text:GetText())
  c.click(rb, "RightButton")
  assert(not rb:IsShown(), "done")
  fight(c, false); fight(g.c2, false)
  tickAll(2)
  assert(not rb:IsShown(), "after the fight the queue is cleared")
  -- dying and coming back out of a fight queues nothing (the bar reads auras then)
  g.ROG.dead = true; tickAll(1); g.ROG.dead = false; tickAll(1)
  assert(not rb:IsShown(), "out of a fight: no card")
  for _, x in ipairs({ g.c1, g.c2, g.c3 }) do noErrors(x, "rebuff") end
end)

test("rebuff: dead again before the click, off the card; back up again, back on it with their first spell", function()
  local g = party5()
  local c = g.c1
  local rb = c.env.CuteAurasRebuff
  fight(c, true)
  g.P2.dead = true; tick(c, 1); g.P2.dead = false; tick(c, 1)
  g.ROG.dead = true; tick(c, 1); g.ROG.dead = false; tick(c, 1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.P2, "the priest first, the rogue queued")
  c.click(rb)
  assert(rb:GetAttribute("spell") ~= 10937, "the priest's Divine Spirit next")
  g.P2.dead = true; tick(c, 1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.ROG, "dead again: the card moves to the rogue")
  c.click(rb, "RightButton")
  assert(not rb:IsShown(), "the rogue done; the dead priest is not on the card")
  g.P2.dead = false; tick(c, 1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.P2 and rb:GetAttribute("spell") == 10937, "back up again: Fortitude first again")
  fight(c, false)
  noErrors(c, "dead again")
end)

test("rebuff: your own death keeps the queue while the group fights; a member raised meanwhile is queued; back with you", function()
  local g = party5()
  local c = g.c1
  local rb = c.env.CuteAurasRebuff
  fight(c, true)
  g.ROG.dead = true; tick(c, 1); g.ROG.dead = false; tick(c, 1)
  assert(rb:IsShown(), "the rogue's card")
  -- you die: your fight ends (PLAYER_REGEN_ENABLED), the group's goes on
  g.P1.dead = true
  for _, m in ipairs({ g.P2, g.PAL, g.ROG, g.WAR }) do m.combat = true end
  fight(c, false)
  tick(c, 1)
  assert(not rb:IsShown(), "dead: the card hidden")
  assert(c.A.Rebuff.held, "the queue kept")
  g.WAR.dead = true; tick(c, 1); g.WAR.dead = false; tick(c, 1)
  assert(not rb:IsShown(), "a member raised while you are dead: still hidden")
  tick(c, 5)
  -- a soulstone: you are back, the group still fights
  g.P1.dead = false
  fire(c, "PLAYER_ALIVE")
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.ROG, "back: the rogue's card again")
  c.click(rb, "RightButton")
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.WAR, "then the warrior, raised while you were dead")
  -- the group's fight ends: the queue cleared
  for _, m in ipairs({ g.P2, g.PAL, g.ROG, g.WAR }) do m.combat = false end
  tick(c, 3)
  assert(not rb:IsShown() and not c.A.Rebuff.held, "the group's fight over: cleared")
  -- a wipe: you die with the group out of its fight: nothing kept
  fight(c, true)
  g.ROG.dead = true; tick(c, 1); g.ROG.dead = false; tick(c, 1)
  g.P1.dead = true
  fight(c, false)
  tick(c, 1)
  assert(not c.A.Rebuff.held and not rb:IsShown(), "a wipe: cleared")
  g.P1.dead = false
  noErrors(c, "own death")
end)

test("rebuff: a member leaving in a fight moves the raid's units; each slot follows its member, never a false back up", function()
  local list = {}
  local classes = { "PRIEST", "WARRIOR", "MAGE", "HUNTER", "ROGUE", "MAGE" }
  for i, cl in ipairs(classes) do list[i] = member({ name = "Raider" .. i, class = cl, level = 60, guid = string.format("Player-1-%02d", i) }) end
  local c = client({ me = list[1], group = list, raid = true })
  knowAll(c, "PRIEST", 60)
  load(c)
  tick(c, 12)
  local rb = c.env.CuteAurasRebuff
  local Rb = c.A.Rebuff
  assert(Rb.slots == 4, "four owed (not you, not the hunter): " .. Rb.slots)
  local function slotOf(m) for i = 1, Rb.slots do if c.units[Rb.handler:GetAttribute("u" .. i)] == m then return i end end end
  local rog, mage2 = list[5], list[6]
  assert(slotOf(rog) and slotOf(mage2), "the rogue and the second mage have slots")
  fight(c, true)
  -- the warrior dies and leaves the raid mid-fight: raid3 and up move down one
  list[2].dead = true; tick(c, 1)
  table.remove(list, 2)
  seat(c)
  fire(c, "GROUP_ROSTER_UPDATE")
  tick(c, 1)
  assert(not rb:IsShown(), "the living member now on the warrior's old unit is no false back up")
  assert(c.units[Rb.handler:GetAttribute("u" .. 4)] == rog or slotOf(rog), "the rogue's slot follows them")
  for i = 1, Rb.slots do
    local u = Rb.handler:GetAttribute("u" .. i)
    assert(u == nil or c.units[u] ~= list[3], "no slot on the hunter (Feign Death would fire it): " .. tostring(u))
  end
  -- the rogue dies and comes back: the card names the rogue on the rogue's new unit
  rog.dead = true; tick(c, 1); rog.dead = false; tick(c, 1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == rog, "the rogue's card on their new unit: " .. tostring(rb:GetAttribute("unit")))
  assert(rb.title:GetText():find(rog.name, 1, true), "named: " .. rb.title:GetText())
  -- the bar's Fortitude list: each row names the member its click now reaches
  local b = icon(c, "group", "duty:fort")
  local fly = b and c.env[b:GetName() .. "Fly"]
  assert(fly, "the Fortitude flyout")
  local n = 0
  for _, r in ipairs(fly.rows) do
    if r:IsShown() then
      local u = r:GetAttribute("unit")
      local who = c.units[u]
      local want = who and (who == list[1] and "You" or who.name) or "?"
      assert(r.name:GetText() == want, "row on " .. tostring(u) .. " says " .. r.name:GetText() .. ", not " .. want)
      n = n + 1
    end
  end
  assert(n > 0, "rows checked")
  -- the hunter feigns death on the rogue's old unit: nothing
  c.click(rb, "RightButton")
  list[3].dead = true; tick(c, 1); list[3].dead = false; tick(c, 1)
  assert(not rb:IsShown(), "Feign Death on a moved unit queues nothing")
  fight(c, false)
  tick(c, 2)
  noErrors(c, "roster in a fight")
end)

test("a hunter's Feign Death never queues a rebuff", function()
  local P = member({ name = "Apr", class = "PRIEST", level = 40, guid = "Player-1-A" })
  local Hn = member({ name = "Bhu", class = "HUNTER", level = 40, guid = "Player-1-B" })
  local c = client({ me = P, group = { P, Hn } })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 5)
  fight(c, true)
  Hn.dead = true; tick(c, 1); Hn.dead = false; tick(c, 1)
  assert(not c.env.CuteAurasRebuff:IsShown(), "no card for a hunter")
  fight(c, false)
  noErrors(c)
end)

test("Blessing of Protection: a countdown, then the blessing it took off; a click once the fight ends", function()
  local g = party5()
  local c = g.c3
  local rogGUID = g.ROG.guid
  fight(c, true)
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Drog", "cast-1", 10278)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 10278)
  local Al = c.A.Alerts
  assert(Al.Has("hand:" .. rogGUID), "the countdown card")
  tick(c, 11)
  assert(not Al.Has("hand:" .. rogGUID), "the countdown ended")
  assert(Al.Has("restore:" .. rogGUID), "in a fight: the restore card as art")
  assert(c.A.Hands.Glowing(rogGUID), "the rogue's row glows")
  fight(c, false)
  tick(c, 2)
  local rb = c.env.CuteAurasRestore
  assert(rb:IsShown(), "after the fight: the secure restore card")
  assert(c.units[rb:GetAttribute("unit")] == g.ROG and c.A.Data.BLESS.might.ranks[5] == rb:GetAttribute("spell"), "Might rank 5 (level 50) on the rogue: " .. tostring(rb:GetAttribute("spell")))
  assert(not Al.Has("restore:" .. rogGUID), "the art card gave way")
  c.casts = {}
  c.click(rb)
  assert(#c.casts == 1, "the click blessed")
  table.insert(g.ROG.auras, { id = rb:GetAttribute("spell"), src = "party1" })
  tick(c, 2)
  fire(c, "UNIT_AURA", "party3")
  tick(c, 1)
  assert(not rb:IsShown() and not c.A.Hands.Glowing(rogGUID), "blessed again: done")
  noErrors(c, "hands")
end)

-- long names (twelve letters, the game's most) for the cards' words to fit
local function party5long()
  local P1 = member({ name = "Thunderhoofe", class = "PRIEST", level = 50, guid = "Player-1-A1", assigned = "HEALER" })
  local P2 = member({ name = "Moonwhispers", class = "PRIEST", level = 50, guid = "Player-1-B2" })
  local PAL = member({ name = "Wolfwardenmw", class = "PALADIN", level = 50, guid = "Player-1-C3" })
  local ROG = member({ name = "Bramblewoode", class = "ROGUE", level = 50, guid = "Player-1-D4" })
  local WAR = member({ name = "Wardenwallow", class = "WARRIOR", level = 50, guid = "Player-1-E5", assigned = "TANK" })
  local group = { P1, P2, PAL, ROG, WAR }
  local c1 = client({ me = P1, group = group, spec = 56 })
  local c3 = client({ me = PAL, group = group, spec = 184 })
  knowAll(c1, "PRIEST", 50); knowAll(c3, "PALADIN", 50)
  load(c1); load(c3)
  tickAll(12)
  return { c1 = c1, c3 = c3, P1 = P1, P2 = P2, PAL = PAL, ROG = ROG, WAR = WAR }
end
local function hand(c, who, spell, n)
  fire(c, "UNIT_SPELLCAST_SENT", "player", who.name, "cast-h" .. n, spell)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-h" .. n, spell)
end

test("Hands: their own clock (a dismissed countdown still restores); right-click or any blessing ends a restore; alerts off", function()
  local g = party5long()
  local c = g.c3
  -- (the cards' look: their words on the card)
  c.A.Settings().alertLook = "normal"; c.A.Alerts.Restyle()
  local Al, Hn = c.A.Alerts, c.A.Hands
  local rog, war = g.ROG.guid, g.WAR.guid
  local card = c.env.CuteAurasRestore
  fight(c, true)
  hand(c, g.ROG, 10278, 1)
  local cd = Al.cards["hand:" .. rog]
  assert(cd, "the countdown card")
  FITS(cd.title, "countdown title"); FITS(cd.text, "countdown line")
  c.click(cd, "RightButton")
  assert(not Al.Has("hand:" .. rog), "dismissed")
  tick(c, 11)
  assert(Hn.Glowing(rog) and Al.Has("restore:" .. rog), "the Hand's own clock: the restore came all the same")
  local art = Al.cards["restore:" .. rog]
  FITS(art.title, "restore title"); FITS(art.text, "restore line in a fight")
  assert(art.text:GetText():find("row glows", 1, true), "the rogue has a row in the bar's Might list: " .. art.text:GetText())
  -- the in-fight restore dismissed: the restore with it, no secure card after the fight
  c.click(art, "RightButton")
  assert(not Hn.Glowing(rog), "dismissed: no glow")
  fight(c, false); tick(c, 2)
  assert(not card:IsShown(), "and no secure card after the fight")
  -- out of a fight: the secure card at the overlay's top, its words whole, a tooltip; a right-click drops it
  hand(c, g.ROG, 10278, 2)
  tick(c, 11)
  assert(card:IsShown() and card.guid == rog, "the secure restore card")
  assert(card.__points[1][2] == c.env.CuteAurasAlerts and card.__points[1][5] == 0, "at the overlay's top, no hole above it")
  FITS(card.title, "secure restore title"); FITS(card.text, "secure restore line")
  assert(card.title:GetText() == "Bramblewoode: Might" and card.text:GetText() == "Protection is over: bless with Might again.", "who and what: " .. card.title:GetText() .. " / " .. card.text:GetText())
  c.hover(card)
  local tip = table.concat(c.env.GameTooltip.lines, " | ")
  assert(c.env.GameTooltip.owner == card and tip:find("Click: bless them. Right-click: dismiss.", 1, true), "the card's tooltip: " .. tip)
  c.casts = {}
  c.click(card, "RightButton")
  assert(#c.casts == 0 and not card:IsShown() and not Hn.Glowing(rog), "a right-click: dismissed, nothing cast")
  -- any blessing of yours on them ends it (Kings for Might: one blessing a paladin)
  hand(c, g.WAR, 1044, 3)
  tick(c, 11)
  assert(card:IsShown() and card.guid == war, "the warrior's restore")
  hand(c, g.WAR, c.A.Data.BLESS.wisdom.ranks[1], 4)
  assert(not Hn.Glowing(war) and not card:IsShown(), "another blessing landed: done")
  -- alerts off: no countdown, no restore card; the glow alone
  c.A.Settings().alerts = false
  hand(c, g.ROG, 1044, 5)
  assert(not Al.Has("hand:" .. rog), "alerts off: no countdown")
  tick(c, 11)
  assert(Hn.Glowing(rog) and not card:IsShown(), "alerts off: the row glows, no card")
  c.A.Settings().alerts = true
  Hn.Refresh()
  assert(card:IsShown() and card.guid == rog, "alerts on again: the card")
  -- the rebuff card is an alert too: alerts off, none
  local p = g.c1
  p.A.Settings().alerts = false
  p.A.Rebuff.Update()
  assert(p.A.Rebuff.slots == 0, "alerts off: no rebuff slots")
  fight(p, true)
  g.WAR.dead = true; tick(p, 1); g.WAR.dead = false; tick(p, 1)
  assert(not p.env.CuteAurasRebuff:IsShown(), "alerts off: no rebuff card")
  fight(p, false)
  noErrors(c, "hands"); noErrors(p, "rebuff off")
end)

test("Hands: Guardian's Favor makes Freedom longer (ranks from the talent tree); a Hand still on them puts the restore off", function()
  local g = party5long()
  local c = g.c3
  local Hn = c.A.Hands
  local war = g.WAR.guid
  c.A.Settings().alertLook = "normal"; c.A.Alerts.Restyle()
  assert(c.A.Data.HANDS.freedom.mods and c.A.Data.HANDS.freedom.mods[20174] == 3, "the client's tables: +3 s a rank")
  c.o.talents = { [20174] = 2 }
  fire(c, "TRAIT_CONFIG_UPDATED")
  fight(c, true)
  hand(c, g.WAR, 1044, 1)
  assert(c.A.Alerts.cards["hand:" .. war].spec.duration == 16, "two ranks: 16 s, got " .. c.A.Alerts.cards["hand:" .. war].spec.duration)
  tick(c, 11)
  assert(not Hn.Glowing(war), "at 11 s Freedom is still on: no restore")
  tick(c, 6)
  assert(Hn.Glowing(war), "at 16 s: the restore")
  fight(c, false); tick(c, 2)
  Hn.Done(war)
  -- no talent: out of a fight, Freedom still on them (a talent the data does not know) waits for the aura's end
  c.o.talents = {}
  fire(c, "TRAIT_CONFIG_UPDATED")
  hand(c, g.WAR, 1044, 2)
  local aura = { id = 1044, exp = c.clock + 15, dur = 15 }
  table.insert(g.WAR.auras, aura)
  tick(c, 11)
  assert(not Hn.Glowing(war), "Freedom still on at 11 s: no restore yet")
  for i = #g.WAR.auras, 1, -1 do if g.WAR.auras[i] == aura then table.remove(g.WAR.auras, i) end end
  tick(c, 5)
  assert(Hn.Glowing(war), "the aura gone: the restore")
  noErrors(c, "guardian's favor")
end)

test("Hands: two restores from a fight, the second says it is next; in a fight the words fit the bar; the rebuff card under the restore", function()
  local g = party5long()
  local c = g.c3
  local Al, Hn = c.A.Alerts, c.A.Hands
  local rog, war = g.ROG.guid, g.WAR.guid
  local card, rb = c.env.CuteAurasRestore, c.env.CuteAurasRebuff
  c.A.Settings().alertLook = "normal"; c.A.Alerts.Restyle()
  -- the bar hidden in a fight: the card says to target them
  c.A.Settings().fight = "hide"
  fight(c, true)
  hand(c, g.ROG, 10278, 1); tick(c, 0.5); hand(c, g.WAR, 1044, 2)
  tick(c, 11)
  local a = Al.cards["restore:" .. war]
  assert(a and a.text:GetText() == "Freedom is over. Target them and give them Kings.", "no bar in a fight: " .. (a and a.text:GetText() or "none"))
  assert(a.title:GetText() == "Wardenwallow: Kings" and a.spec.tip == "After the fight, a click on it blesses them.", "its title and grey line: " .. a.title:GetText())
  FITS(a.text, "restore line, no row")
  fight(c, false)
  tick(c, 2)
  assert(card:IsShown() and card.guid == rog, "the first on the secure card")
  local nextCard = Al.cards["restore:" .. war]
  assert(nextCard and nextCard.text:GetText() == "Next, once the one before it is done." and nextCard.spec.tip == nil,
    "the second waits, saying so: " .. (nextCard and nextCard.text:GetText() or "none"))
  FITS(nextCard.text, "next line")
  -- the rebuff card stacks under the restore card, the art cards under both
  assert(rb.__points[1][2] == card and rb.__points[1][3] == "BOTTOM", "the rebuff card under the restore card")
  fight(c, true)
  local P2 = g.P2
  P2.dead = true; tick(c, 1); P2.dead = false; tick(c, 1)
  assert(rb:IsShown(), "a rebuff for the priest in a fight (the paladin owes a blessing)")
  FITS(rb.title, "rebuff title"); FITS(rb.text, "rebuff line")
  c.hover(rb)
  assert(c.env.GameTooltip.owner == rb and table.concat(c.env.GameTooltip.lines, " "):find("Right-click: done", 1, true), "the rebuff card's tooltip")
  hand(c, g.P2, 1044, 3)
  local cd = Al.cards["hand:" .. P2.guid]
  local want = card:GetHeight() + rb:GetHeight() + 2 * Al.GAP
  assert(cd.__points[1][5] == -want, "the countdown under both secure cards: " .. tostring(cd.__points[1][5]) .. " for " .. want)
  fight(c, false)
  tick(c, 12)
  noErrors(c, "two restores")
end)

test("a fight with everything moving: no protected call, no error, the group's icons stay", function()
  local g = party5()
  local c = g.c3
  tick(c, 2)
  local before = #shown(c, "group")
  assert(before > 0, "the paladin has blessings to give")
  fight(c, true)
  -- events that would lay the bar out: all wait for the fight's end
  for _, ev in ipairs({ "UNIT_AURA", "GROUP_ROSTER_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "ZONE_CHANGED", "SPELLS_CHANGED" }) do fire(c, ev, "player") end
  c.A.Assign.Changed(); c.A.Rebuff.Update(); c.A.Bar.Dirty("all")
  tick(c, 3)
  assert(c.env.CuteAurasBarGroup:IsShown(), "the group's part stays in a fight")
  assert(not c.env.CuteAurasBarOwn:IsShown(), "yours hides (the state driver)")
  -- the flyout opens on hover through the secure wrap
  local b = icon(c, "group", c.A.Bar.Shown("group")[1].key)
  c.hover(b)
  local fly = c.env[b:GetName() .. "Fly"]
  assert(fly and fly:IsShown(), "the flyout opened in a fight")
  fight(c, false)
  tick(c, 3)
  noErrors(c, "fight")
end)

test("addon messages locked down in a fight wait for its end", function()
  local g = party5()
  local c = g.c1
  fight(c, true)
  c.lockdown = true
  local n = #c.said
  c.A.Comm.Hello(true)
  tick(c, 2)
  assert(#c.said == n, "nothing sent in the lockdown")
  c.lockdown = false
  fight(c, false)
  tick(c, 3)
  assert(#c.said > n, "sent after the fight")
  noErrors(c)
end)

test("biome gear: a Snowy trinket in your bags in Winterspring, its swap; Show it in and Never; back on when you leave", function()
  local me = member({ name = "Biomer", class = "MAGE", level = 55 })
  local c = client({ me = me, zone = "Winterspring" })
  c.items[249469] = { name = "Frozen Heart of the Mountain", equipLoc = "INVTYPE_TRINKET", spell = 1249110 }
  c.items[5000] = { name = "Plain Charm", equipLoc = "INVTYPE_TRINKET" }
  c.items[5001] = { name = "Other Charm", equipLoc = "INVTYPE_TRINKET" }
  c.equipped[13], c.equipped[14] = 5000, 5001
  c.bags[1] = { id = 249469, bag = 0, slot = 1 }
  knowAll(c, "MAGE", 55)
  load(c)
  tick(c, 2)
  noErrors(c, "biome")
  local here = c.A.Gear.Here()
  assert(here.snowy, "Winterspring is Snowy (the client's area group)")
  local gear = shown(c, "gear")
  assert(#gear == 1 and gear[1].click.macro:find("item:249469", 1, true), "the swap: " .. tostring(gear[1] and gear[1].click.macro))
  local inv = gear[1].inv
  -- its menu: Show it in, four contexts
  local b = icon(c, "own", gear[1].key)
  c.A.Bar.Menu(b)
  local menu = c.menus[#c.menus]
  local checks = 0
  for _, e in ipairs(menu) do if e.kind == "check" then checks = checks + 1 end end
  assert(checks == 4, "Solo, PvP, 5-man, Raid")
  -- not in raids: in a raid it stays quiet
  c.A.Gear.SetShow(249469, "raid", false)
  c.instance = "raid"
  c.A.Bar.Dirty("gear"); tick(c, 1)
  assert(#shown(c, "gear") == 0, "quiet in a raid")
  c.instance = nil
  c.A.Bar.Dirty("gear"); tick(c, 1)
  assert(#shown(c, "gear") == 1, "back in the open world")
  -- the swap clicked: the piece it replaced kept for later
  c.casts = {}
  c.click(icon(c, "own", gear[1].key))
  local old = c.equipped[inv]
  -- (the macro's /equipslot, as the game does it: PLAYER_EQUIPMENT_CHANGED for the slot, the old piece in the bag)
  c.equipNow(249469, inv)
  tick(c, 2)
  assert(c.A.Char().gearHome[inv] == old, "the piece it replaced kept for back")
  assert(#shown(c, "gear") == 0, "worn here: nothing")
  -- leave the snow
  c.zone = "Elwynn Forest"
  fire(c, "ZONE_CHANGED_NEW_AREA")
  tick(c, 2)
  local back = shown(c, "gear")[1]
  assert(back and back.kind == "back" and back.click.macro:find("item:" .. old, 1, true), "the old piece back on")
  assert(back.never == "gear:249469", "the back icon's Never is the piece's one Never: " .. tostring(back.never))
  -- Never for this piece
  c.A.Gear.SetNever(249469, true)
  c.zone = "Winterspring"; c.equipped[inv] = old; c.bags[1] = { id = 249469, bag = 0, slot = 1 }
  fire(c, "ZONE_CHANGED_NEW_AREA"); fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 2)
  assert(#shown(c, "gear") == 0, "never")
  noErrors(c)
end)

test("biome gear learned from a tooltip: a server-sent piece the data doesn't know", function()
  local me = member({ name = "Ghosty", class = "PRIEST", level = 50 })
  local c = client({ me = me, zone = "Duskwood" })
  c.items[990001] = { name = "Phantom Hood", equipLoc = "INVTYPE_HEAD" }
  c.tooltips[990001] = { { leftText = "Phantom Hood" }, { leftText = "Equip: Increases healing done by up to 20 and damage done by up to 7 for all magical spells and effects while in Haunted areas." } }
  c.items[4000] = { name = "Plain Hood", equipLoc = "INVTYPE_HEAD" }
  c.equipped[1] = 4000
  c.bags[1] = { id = 990001, bag = 0, slot = 1 }
  load(c)
  tick(c, 2)
  local biomes = c.A.Gear.BiomesOf(990001, 0, 1)
  assert(biomes and biomes[1] == "haunted", "the tooltip says Haunted")
  assert(c.A.Gear.Here().haunted, "Duskwood is Haunted")
  local gear = shown(c, "gear")
  assert(#gear == 1 and gear[1].inv == 1, "swap the hood in")
  -- the Biome gear tab draws
  c.A.Window.Open("gear")
  c.A.Window.Open("blessings")
  c.A.Window.Open("settings")
  noErrors(c, "window")
end)

test("the test alerts and Move mode draw without errors; three cards as play makes them; none with alerts off", function()
  local me = member({ name = "Tester", class = "DRUID", level = 30 })
  local c = client({ me = me })
  load(c)
  c.A.Settings().alertLook = "normal"
  c.A.Alerts.Test()
  tick(c, 2)
  assert(c.A.Alerts.Has("test:hand") and c.A.Alerts.Has("test:restore") and c.A.Alerts.Has("test:rebuff"), "the test cards")
  assert(not c.A.Alerts.Has("test:swap"), "no biome swap card: swaps are bar icons, never an alert")
  for _, key in ipairs({ "test:hand", "test:restore", "test:rebuff" }) do
    local f = c.A.Alerts.cards[key]
    FITS(f.title, key .. " title"); FITS(f.text, key .. " line")
    assert(f.icon.icon.__tex ~= 134400, key .. ": a real icon, not the question mark")
  end
  c.A.Settings_.Move(true)
  c.A.Settings_.Move(true)
  tick(c, 16)
  assert(not c.A.Alerts.Has("test:rebuff"), "they go")
  c.env.SlashCmdList.CUTEAURAS("diag")
  -- alerts off: chat says so, nothing drawn
  c.A.Settings().alerts = false
  c.chat = {}
  c.A.Alerts.Test()
  assert(not c.A.Alerts.Has("test:hand") and c.chat[1]:find("Alerts are off", 1, true), "alerts off: " .. tostring(c.chat[1]))
  noErrors(c)
end)

test("the alerts' default spot clears the game's error lines and raid warnings on a short screen", function()
  local me = member({ name = "Tester", class = "DRUID", level = 30 })
  local c = client({ me = me })
  load(c)
  local an = c.env.CuteAurasAlerts
  local function y() return an.__points[1][5] end
  assert(an.__points[1][2] == c.env.UIParent and an.__points[1][3] == "CENTER", "under the screen's centre")
  -- (UIParent 1000 tall: the top 290 under the screen's top, under RaidWarningFrame's 182 to 282)
  assert(y() == 210, "1000 tall: " .. y())
  c.env.UIParent.__h = 768; c.A.Alerts.Place()
  assert(y() == 94, "768 tall (UI scale 1 at 1366x768): " .. y())
  c.env.UIParent.__h = 1080; c.A.Alerts.Place()
  assert(y() == 230, "1080 tall: the old spot, 310 under the top: " .. y())
  noErrors(c)
end)

test("a raid of ten, two priests: subgroups split between them", function()
  local list = {}
  local classes = { "PRIEST", "WARRIOR", "MAGE", "ROGUE", "HUNTER", "PRIEST", "WARRIOR", "MAGE", "ROGUE", "DRUID" }
  for i, cl in ipairs(classes) do list[i] = member({ name = "R" .. i, class = cl, level = 60, guid = string.format("Player-1-%02d", i), sub = i <= 5 and 1 or 2 }) end
  local c1 = client({ me = list[1], group = list, raid = true })
  local c6 = client({ me = list[6], group = list, raid = true })
  knowAll(c1, "PRIEST", 60); knowAll(c6, "PRIEST", 60)
  load(c1); load(c6)
  tickAll(12)
  local function targets(c) for _, d in ipairs(c.A.Assign.duties) do if d.key == "fort" then return d.targets end end return {} end
  local t1, t6 = targets(c1), targets(c6)
  assert(#t1 == 5 and #t6 == 5, "five each: " .. #t1 .. " and " .. #t6)
  for _, m in ipairs(t1) do assert(m.sub == 1, "the first priest has subgroup one") end
  -- the group version for three or more of a subgroup with the candle
  c1.items[17029] = { name = "Sacred Candle" }
  c1.bags[1] = { id = 17029, bag = 0, slot = 1, count = 5 }
  fire(c1, "BAG_UPDATE_DELAYED")
  tick(c1, 2)
  local b = icon(c1, "group", "duty:fort")
  assert(b and b:GetAttribute("spell") == 21564, "Prayer of Fortitude: " .. tostring(b and b:GetAttribute("spell")))
  noErrors(c1); noErrors(c6)
end)

test("a raid of forty: five paladins, four priests; every client agrees, a refresh stays cheap, memory stays put", function()
  local classes = { "WARRIOR", "WARRIOR", "ROGUE", "ROGUE", "MAGE", "MAGE", "WARLOCK", "HUNTER", "PRIEST", "PALADIN" }
  local list = {}
  for i = 1, 40 do
    local cl = classes[(i - 1) % #classes + 1]
    list[i] = member({ name = "M" .. i, class = cl, level = 60, guid = string.format("Player-1-%03d", i), sub = math.floor((i - 1) / 5) + 1,
                       assigned = (i == 1 or i == 2) and "TANK" or nil })
  end
  local cs = {}
  for i, m in ipairs(list) do
    if m.class == "PALADIN" or m.class == "PRIEST" then
      local c = client({ me = m, group = list, raid = true })
      knowAll(c, m.class, 60)
      cs[#cs + 1] = c
    end
  end
  for _, c in ipairs(cs) do load(c) end
  tickAll(15)
  -- the same share-out on every client
  local function sig(c)
    local out = {}
    for _, pal in ipairs(c.A.Assign.paladins or {}) do
      for _, b in ipairs(c.A.Assign.bucketList) do out[#out + 1] = pal.guid .. b.key .. tostring(c.A.Assign.BlessingOf(pal.guid, b.key)) end
    end
    return table.concat(out, ";")
  end
  local first = sig(cs[1])
  assert(first ~= "", "blessings shared out")
  for _, c in ipairs(cs) do assert(sig(c) == first, "every client agrees") end
  -- each paladin gives at most one blessing to each bucket, and no two give one bucket the same
  local A1 = cs[1].A.Assign
  for _, b in ipairs(A1.bucketList) do
    local seen = {}
    for _, pal in ipairs(A1.paladins) do
      local k = A1.BlessingOf(pal.guid, b.key)
      if k then assert(not seen[k], "two paladins give " .. b.key .. " " .. k); seen[k] = true end
    end
  end
  -- fortitude: four priests, eight subgroups, two each
  for _, c in ipairs(cs) do
    for _, d in ipairs(c.A.Assign.duties) do if d.key == "fort" then assert(#d.targets == 10, "ten each: " .. #d.targets) end end
  end
  local c = cs[1]
  -- (measured with LuaJIT's compiler off, as the client runs: a trace it compiles mid-batch counts as Lua memory, tens
  -- of KB at a moment no refresh decides)
  if jit then jit.off(); jit.flush() end
  for _ = 1, 100 do c.A.Bar.Refresh() end -- (the pools filled, every lazy table made once)
  -- (a leak grows with every refresh: two batches of a hundred, the second must not grow as the first did)
  local function batch()
    collectgarbage("collect"); collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 100 do c.A.Bar.Refresh() end
    collectgarbage("collect"); collectgarbage("collect")
    return collectgarbage("count") - before
  end
  local t0 = os.clock()
  local timers0 = #c.timers
  local g1 = batch()
  local per = (os.clock() - t0) / 100 * 1000
  local g2 = batch()
  if jit then jit.on() end
  print("    timers queued by 100 refreshes: " .. (#c.timers - timers0))
  print(string.format("    raid of 40: a full refresh %.2f ms in the mock, memory %+.0f KB then %+.0f KB a hundred refreshes", per, g1, g2))
  assert(g1 < 60 and g2 < 60, "memory grows with refreshes: " .. g1 .. " and " .. g2 .. " KB")
  for _, x in ipairs(cs) do noErrors(x, "raid") end
end)

test("consumables: an elixir learned by habit, asked for in a raid, its countdown; Well Fed in a raid; two that replace each other", function()
  local me = member({ name = "Sipper", class = "WARRIOR", level = 60 })
  local c = client({ me = me })
  local food
  for id in pairs(D.FOOD) do food = id; break end
  c.items[13452] = { name = "Elixir of the Mongoose", classID = 0, subID = 2, spell = 17538 }
  c.items[9187] = { name = "Elixir of Greater Agility", classID = 0, subID = 2, spell = 11334 }
  c.items[food] = { name = "Some Food", classID = 0, subID = 5, spell = 433 }
  c.bags = { { id = 13452, bag = 0, slot = 1, count = 5 }, { id = 9187, bag = 0, slot = 2, count = 5 }, { id = food, bag = 0, slot = 3, count = 10 } }
  load(c)
  tick(c, 1)
  local function use(id, spell, dur)
    fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast" .. c.clock, spell)
    for i = #me.auras, 1, -1 do if me.auras[i].id == spell then table.remove(me.auras, i) end end
    me.auras[#me.auras + 1] = { id = spell, src = "player", exp = c.clock + dur, dur = dur }
    fire(c, "UNIT_AURA", "player")
    tick(c, 2)
  end
  local function drop(spell)
    for i = #me.auras, 1, -1 do if me.auras[i].id == spell then table.remove(me.auras, i) end end
    fire(c, "UNIT_AURA", "player")
    tick(c, 2)
  end
  use(13452, 17538, 3600); drop(17538); use(13452, 17538, 3600); drop(17538)
  local h = c.A.Char().consume
  assert(h[13452] and h[13452].hits == 2, "used twice: a habit (" .. tostring(h[13452] and h[13452].hits) .. ")")
  assert(not find(shown(c, "mine"), "consume13452"), "the open world: not asked (dungeons and raids by default)")
  c.instance = "raid"
  fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 2)
  local rec = find(shown(c, "mine"), "consume13452")
  assert(rec and rec.word == "Drink" and rec.click.item == 13452, "in a raid: drink it")
  -- Well Fed in a raid: missing, the best food you carry
  local fedRec = find(shown(c, "mine"), "food")
  assert(fedRec and fedRec.word == "Eat" and fedRec.click.item == food, "not Well Fed in a raid: eat")
  me.auras[#me.auras + 1] = { id = 19705, src = "player", exp = c.clock + 100, dur = 900 }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  fedRec = find(shown(c, "mine"), "food")
  assert(fedRec and fedRec.status == "warn" and fedRec.word:find("^1:"), "Well Fed under two minutes: its countdown, " .. tostring(fedRec and fedRec.word))
  -- the elixir on, 50 s left: its countdown; the scheduled look comes without an event
  use(13452, 17538, 90)
  assert(not find(shown(c, "mine"), "consume13452"), "on for 90 s: nothing")
  tick(c, 32)
  rec = find(shown(c, "mine"), "consume13452")
  assert(rec and rec.status == "warn", "under a minute: the countdown came by itself")
  -- a second elixir taking the first's place: one group, one icon
  use(9187, 11334, 3600) -- (the mongoose's aura is still on: no pair yet)
  drop(11334); drop(17538)
  -- use B while A is on, A's aura going in the same second: the pair learned
  use(13452, 17538, 3600)
  for i = #me.auras, 1, -1 do if me.auras[i].id == 17538 then table.remove(me.auras, i) end end
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "castB", 11334)
  me.auras[#me.auras + 1] = { id = 11334, src = "player", exp = c.clock + 3600, dur = 3600 }
  fire(c, "UNIT_AURA", "player"); tick(c, 2)
  assert(c.A.Buffs.GroupOf(13452) == c.A.Buffs.GroupOf(9187), "the two are one group")
  drop(11334)
  local n = 0
  for _, r in ipairs(shown(c, "mine")) do if r.key:find("^consume") then n = n + 1 end end
  assert(n == 1, "one icon for the group: " .. n)
  -- off: nothing
  c.A.Consume.Settings().on = false; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(not find(shown(c, "mine"), "consume13452") and not find(shown(c, "mine"), "food"), "off")
  noErrors(c)
end)

test("a late joiner hears the group and the group hears it; a blessing set by hand reaches it", function()
  local P1 = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-L1", leader = true })
  local P2 = member({ name = "Bpri", class = "PRIEST", level = 60, guid = "Player-1-L2" })
  local W = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-L3" })
  local g1 = { P1, P2, W }
  local c1 = client({ me = P1, group = g1 })
  local c2 = client({ me = P2, group = g1 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "PRIEST", 60)
  load(c1); load(c2)
  tickAll(10)
  c1.A.Assign.Set(P1.guid, "WARRIOR:melee", "kings")
  tickAll(3)
  -- a second priest joins, its client starting now
  local P3 = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-L0" })
  local g2 = { P1, P2, W, P3 }
  c1.o.group, c2.o.group = g2, g2
  seat(c1); seat(c2)
  local c3 = client({ me = P3, group = g2 })
  knowAll(c3, "PRIEST", 60)
  fire(c1, "GROUP_ROSTER_UPDATE"); fire(c2, "GROUP_ROSTER_UPDATE")
  load(c3)
  tickAll(15)
  assert(c3.A.Comm.peers[P1.guid] and c3.A.Comm.peers[P2.guid], "the joiner heard both")
  assert(c1.A.Comm.peers[P3.guid] and c2.A.Comm.peers[P3.guid], "both heard the joiner")
  local function fortOf(c) for _, d in ipairs(c.A.Assign.duties) do if d.key == "fort" then return #d.targets end end return 0 end
  -- (Player-1-L0 sorts first: the joiner gives Fortitude now, the other priest none)
  assert(fortOf(c3) == 4 and fortOf(c2) == 0, "one priest gives Fortitude: " .. fortOf(c3) .. " and " .. fortOf(c2))
  assert(c3.A.Assign.BlessingOf(P1.guid, "WARRIOR:melee") == "kings", "the hand-set blessing reached the joiner")
  for _, c in ipairs({ c1, c2, c3 }) do noErrors(c, "late joiner") end
end)

test("hover: the tooltip beside the list, never over it; far members grey the icon; a raid's list in columns", function()
  local g = party5()
  local c = g.c1
  tick(c, 2)
  local b = icon(c, "group", "duty:fort")
  assert(b, "Fortitude to give")
  c.hover(b)
  local fly = c.env[b:GetName() .. "Fly"]
  local tt = c.env.GameTooltip
  assert(fly:IsShown() and tt.anchor == "ANCHOR_NONE" and tt.point and tt.point[2] == fly and tt.point[3] == "BOTTOMRIGHT", "the tooltip sits right of the list")
  -- everyone missing Fortitude is far: the icon waits and casts nothing
  for _, m in ipairs(g.group) do if not m.me then m.far = true end end
  g.P1.auras[#g.P1.auras + 1] = { id = 10938, src = "player", exp = c.clock + 3600 }
  fire(c, "UNIT_AURA", "player"); c.A.Bar.Dirty("group"); tick(c, 2)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.lit == false and rec.word == "Far" and b:GetAttribute("type1") == nil, "far: waiting, no cast (" .. tostring(rec and rec.word) .. ")")
  for _, m in ipairs(g.group) do m.far = nil end
  -- a raid's Kings list: ten rows a column
  local list = {}
  for i = 1, 25 do list[i] = member({ name = "K" .. i, class = i == 1 and "PALADIN" or "WARRIOR", level = 60, guid = string.format("Player-1-K%02d", i), sub = math.floor((i - 1) / 5) + 1 }) end
  local cp = client({ me = list[1], group = list, raid = true })
  knowAll(cp, "PALADIN", 60)
  load(cp); tick(cp, 10)
  local kb
  for _, r in ipairs(shown(cp, "group")) do if r.flyout and #r.flyout > 10 then kb = icon(cp, "group", r.key) end end
  assert(kb, "a blessing for more than ten")
  local f = cp.env[kb:GetName() .. "Fly"]
  assert(f.__h <= 10 * 22 + 4 and f.__w >= 300, "columns of ten: " .. f.__w .. " x " .. f.__h)
  noErrors(c); noErrors(cp)
end)

test("dual spec: a switch from Retribution to Holy, heard by the group; Before the pull fits the spec", function()
  local PAL = member({ name = "Duo", class = "PALADIN", level = 60, guid = "Player-1-D1" })
  local PRI = member({ name = "Pri", class = "PRIEST", level = 60, guid = "Player-1-D2" })
  local g = { PAL, PRI }
  local c1 = client({ me = PAL, group = g, spec = 184 })
  local c2 = client({ me = PRI, group = g, spec = 56 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "PRIEST", 60)
  load(c1); load(c2)
  tickAll(10)
  assert(c1.A.Roster.MyRole() == "melee" and c2.A.Comm.peers[PAL.guid].role == "melee", "Retribution: melee")
  c1.o.spec, c1.specGroup = 594, 2
  fire(c1, "ACTIVE_TALENT_GROUP_CHANGED")
  tickAll(8)
  assert(c1.A.Roster.MyRole() == "healer", "Holy now: healer")
  assert(c2.A.Comm.peers[PAL.guid].role == "healer", "the priest's client heard the switch")
  assert(c2.A.Assign.BlessingOf(PAL.guid, "PALADIN:healer") == "wisdom", "a Holy paladin's own blessing: Wisdom")
  -- Before the pull: an Agility elixir is no healer's, an Intellect one and a health one are
  c1.items[13452] = { name = "Elixir of the Mongoose", classID = 0, subID = 2, spell = 17538 }
  c1.items[9179] = { name = "Elixir of Greater Intellect", classID = 0, subID = 2, spell = 11396 }
  c1.items[3825] = { name = "Elixir of Fortitude", classID = 0, subID = 2, spell = 3593 }
  c1.bags = { { id = 13452, bag = 0, slot = 1 }, { id = 9179, bag = 0, slot = 2 }, { id = 3825, bag = 0, slot = 3 } }
  fire(c1, "BAG_UPDATE_DELAYED")
  fire(c1, "READY_CHECK")
  tick(c1, 5)
  local pull = shown(c1, "pull")
  assert(find(pull, "flask9179") and find(pull, "flask3825"), "Intellect and health for a healer")
  assert(not find(pull, "flask13452"), "never Agility for a healer")
  noErrors(c1); noErrors(c2)
end)

test("biome gear: ordinary items are never biome pieces; a swap wears its biome's colour; the minimap button", function()
  local me = member({ name = "Plain", class = "PRIEST", level = 50 })
  local c = client({ me = me, zone = "Winterspring" })
  -- the client's own text of two biome spells whose words begin like ordinary items'
  SPELL_DESC[1318326] = "Increases damage and healing done by magical spells and effects by up to 29. This effect is doubled in Marsh and Swamp areas."
  SPELL_DESC[1316053] = "Restores 5 Mana per 5 sec. Restores an additional 10 Mana per 5 sec in Forest and Grassland areas."
  c.items[990010] = { name = "Robe of Plain Power", equipLoc = "INVTYPE_CHEST" }
  c.tooltips[990010] = { { leftText = "Robe of Plain Power" }, { leftText = "Equip: Increases damage and healing done by magical spells and effects by up to 29." } }
  c.items[990011] = { name = "Ring of Plain Mana", equipLoc = "INVTYPE_FINGER" }
  c.tooltips[990011] = { { leftText = "Ring of Plain Mana" }, { leftText = "Equip: Restores 5 Mana per 5 sec." } }
  c.items[990012] = { name = "Reed of the Marsh", equipLoc = "INVTYPE_HOLDABLE" }
  c.tooltips[990012] = { { leftText = "Reed of the Marsh" }, { leftText = "Equip: Increases damage and healing done by magical spells and effects by up to 31. This effect is doubled in Marsh and Swamp areas." } }
  c.items[249469] = { name = "Frozen Heart of the Mountain", equipLoc = "INVTYPE_TRINKET", spell = 1249110 }
  c.items[5000] = { name = "Plain Charm", equipLoc = "INVTYPE_TRINKET" }
  c.equipped[13], c.equipped[14] = 5000, 5000
  c.bags = { { id = 990010, bag = 0, slot = 1 }, { id = 990011, bag = 0, slot = 2 }, { id = 990012, bag = 0, slot = 3 }, { id = 249469, bag = 0, slot = 4 } }
  load(c)
  tick(c, 2)
  local G = c.A.Gear
  assert(G.BiomesOf(990010, 0, 1) == nil, "an ordinary spell power robe is no biome piece")
  assert(G.BiomesOf(990011, 0, 2) == nil, "an ordinary mana ring is no biome piece")
  local reed = G.BiomesOf(990012, 0, 3)
  assert(reed and reed[1] == "swamp", "the marsh reed is (another rank's numbers)")
  local n = 0
  for _, p in ipairs(G.Scan()) do n = n + 1 end
  assert(n == 2, "two biome pieces: the reed and the heart, " .. n)
  local rec = shown(c, "gear")[1]
  -- (the bar's 2 px bar means the part: a gear swap keeps the gear part's pink, its word the ink; the biome's colour
  -- is on its name in the tooltip and the Biome gear tab)
  local gb = icon(c, "own", rec.key)
  local PINK, INK = c.A.Look.C.PINK, c.A.Look.C.INK
  assert(gb.bar.__color[1] == PINK[1] and gb.bar.__color[2] == PINK[2] and gb.bar.__color[3] == PINK[3], "a swap's bar is the gear part's pink")
  assert(gb.word.__textColor[1] == INK[1] and gb.word.__textColor[3] == INK[3], "its word the ink")
  -- (no two biomes' colours alike: each pair apart by 0.25 or more, the three channels' differences summed)
  local keys = {}
  for k in pairs(G.COLOR) do keys[#keys + 1] = k end
  for i = 1, #keys do for j = i + 1, #keys do
    local a, b = G.COLOR[keys[i]], G.COLOR[keys[j]]
    local d = math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) + math.abs(a[3] - b[3])
    assert(d >= 0.25, keys[i] .. " and " .. keys[j] .. " are too alike: " .. d)
  end end
  assert(G.Colored("snowy"):find("Snowy", 1, true) and G.Colored("snowy"):find("^|cff"), "coloured names")
  -- the minimap button: there, a click opens the window, Settings hides it
  local mb = c.env.CuteAurasMinimapButton
  assert(mb and mb:IsShown(), "the minimap button")
  mb.__scripts.OnClick(mb, "LeftButton")
  assert(c.env.CuteAurasWindow:IsShown(), "a click opens the window")
  mb.__scripts.OnClick(mb, "RightButton")
  assert(#c.menus > 0, "a right-click, the menu")
  c.A.Settings().minimap = false; c.A.Minimap.Update()
  assert(not mb:IsShown(), "hidden from Settings")
  c.A.Window.Open("gear")
  noErrors(c)
end)

-- (a ready check: Before the pull's icons, keys in the bar's order)
local function pullKeys(c)
  local out = {}
  for _, r in ipairs(shown(c, "pull")) do out[#out + 1] = r.key end
  return table.concat(out, " ")
end
test("Before the pull: flasks, then elixirs that fit you; never a healing, mana or utility potion; habits of any kind; Off is off", function()
  local me = member({ name = "Puller", class = "WARRIOR", level = 60 })
  local c = client({ me = me, db = { chars = { [me.guid] = { role = "melee" } } } })
  local function it(id, name, cls, sub, spell) c.items[id] = { name = name, classID = cls, subID = sub, spell = spell } end
  it(118, "Minor Healing Potion", 0, 1, 439); it(929, "Healing Potion", 0, 1, 441); it(3827, "Mana Potion", 0, 1, 2023)
  it(2459, "Swiftness Potion", 0, 1, 2379); it(5996, "Elixir of Water Breathing", 0, 2, 7178)
  it(9179, "Elixir of Greater Intellect", 0, 2, 11396); it(9206, "Elixir of Giants", 0, 2, 11405)
  it(13452, "Elixir of the Mongoose", 0, 2, 17538); it(13510, "Flask of the Titans", 0, 3, 17626)
  it(13455, "Greater Stoneshield Potion", 0, 1, 17540); it(20079, "Spirit of Zanza", 0, 8, 24382)
  local slot = 0
  for _, id in ipairs({ 118, 929, 3827, 2459, 5996, 9179, 9206, 13452, 13510, 13455, 20079 }) do slot = slot + 1; c.bags[#c.bags + 1] = { id = id, bag = 0, slot = slot, count = 3 } end
  -- (the text of a client in another language: the role is read from the client's tables, not from English words)
  SPELL_DESC[11405] = "Erhöht die Stärke um 25."
  load(c)
  tick(c, 1)
  fire(c, "READY_CHECK"); tick(c, 4)
  local keys = pullKeys(c)
  assert(keys:find("^flask13510 flask9206 flask13452"), "the flask first, then the two elixirs that fit a warrior: " .. keys)
  for _, id in ipairs({ 118, 929, 3827, 2459, 5996, 9179, 13455, 20079 }) do
    assert(not keys:find("flask" .. id .. "%f[%D]"), "never asked before it is a habit: " .. id .. " in " .. keys)
  end
  assert(c.A.Buffs.Fits(9206, "melee") and not c.A.Buffs.Fits(9206, "healer"), "Strength: a melee's, never a healer's, whatever the text's language")
  -- a potion and Spirit of Zanza learned by habit: asked, after the elixirs, four at most
  local h = c.A.Char().consume
  h[13455] = { hits = 2, miss = 0, spell = 17540 }; h[20079] = { hits = 2, miss = 0, spell = 24382 }
  c.A.Bar.Dirty("all"); tick(c, 1)
  keys = pullKeys(c)
  local n = 0
  for _, r in ipairs(shown(c, "pull")) do if r.key:find("^flask") then n = n + 1 end end
  assert(n == 4 and keys:find("flask13510 flask9206 flask13452 flask13455"), "flask, elixirs, then the habits, four at most: " .. keys)
  local zanza = find(shown(c, "pull"), "flask13455")
  assert(zanza.click.item == 13455 and zanza.click.unit == "player", "on you")
  -- Off: nothing at a ready check either
  c.A.Consume.Settings().on = false; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(#shown(c, "pull") == 0, "consumables Off: no food, no flask at the ready check: " .. pullKeys(c))
  SPELL_DESC[11405] = nil
  noErrors(c)
end)

test("Before the pull: Well Fed or an elixir about to end is asked again with its countdown; a group covered by your last bottle's aura", function()
  local me = member({ name = "Timer", class = "ROGUE", level = 60 })
  local c = client({ me = me, db = { chars = { [me.guid] = { role = "melee" } } } })
  local food
  for id in pairs(D.FOOD) do food = id; break end
  c.items[food] = { name = "Some Food", classID = 0, subID = 5, spell = 433 }
  c.items[13452] = { name = "Elixir of the Mongoose", classID = 0, subID = 2, spell = 17538 }
  c.items[9187] = { name = "Elixir of Greater Agility", classID = 0, subID = 2, spell = 11334 }
  c.items[9206] = { name = "Elixir of Giants", classID = 0, subID = 2, spell = 11405 }
  c.bags = { { id = food, bag = 0, slot = 1, count = 5 }, { id = 9187, bag = 0, slot = 2 }, { id = 9206, bag = 0, slot = 3 } }
  load(c)
  tick(c, 1)
  -- the Mongoose learned and paired with Greater Agility; its last bottle used: its aura on, an hour left
  local h = c.A.Char().consume
  h[13452] = { hits = 2, miss = 0, spell = 17538 }
  c.A.Acct().pairs = { [13452] = 9187 }
  me.auras = { { id = 17538, src = "player", exp = c.clock + 3000, dur = 3600 }, { id = 19705, src = "player", exp = c.clock + 90, dur = 900 },
               { id = 11405, src = "player", exp = c.clock + 40, dur = 3600 } }
  fire(c, "UNIT_AURA", "player")
  fire(c, "READY_CHECK"); tick(c, 4)
  local keys = pullKeys(c)
  assert(not keys:find("flask9187"), "the Mongoose on (from the last bottle): its partner not asked: " .. keys)
  local fed = find(shown(c, "pull"), "pullfood")
  assert(fed and fed.status == "warn" and fed.word:find("^1:") and fed.timed, "Well Fed with 1:30 left: eat again, its countdown: " .. tostring(fed and fed.word))
  local giants = find(shown(c, "pull"), "flask9206")
  assert(giants and giants.status == "warn" and giants.word:find("^0:") and giants.timed, "an elixir with 40 s left: its countdown: " .. tostring(giants and giants.word))
  local was = giants.word
  tick(c, 3)
  giants = find(shown(c, "pull"), "flask9206")
  assert(giants and giants.word ~= was, "the countdown ticks: " .. was .. " then " .. tostring(giants and giants.word))
  noErrors(c)
end)

test("consumables: a habit asked for and ignored three times ten minutes is forgotten; a use resets it; one-offs never fill the list", function()
  local me = member({ name = "Forget", class = "WARRIOR", level = 60 })
  local c = client({ me = me })
  c.items[5996] = { name = "Elixir of Water Breathing", classID = 0, subID = 2, spell = 7178 }
  c.bags = { { id = 5996, bag = 0, slot = 1, count = 5 } }
  load(c)
  tick(c, 1)
  local function use(id, spell, dur)
    fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast" .. c.clock, spell)
    for i = #me.auras, 1, -1 do if me.auras[i].id == spell then table.remove(me.auras, i) end end
    me.auras[#me.auras + 1] = { id = spell, src = "player", exp = c.clock + dur, dur = dur }
    fire(c, "UNIT_AURA", "player"); tick(c, 2)
  end
  local function drop(spell)
    for i = #me.auras, 1, -1 do if me.auras[i].id == spell then table.remove(me.auras, i) end end
    fire(c, "UNIT_AURA", "player"); tick(c, 2)
  end
  use(5996, 7178, 1800); drop(7178); use(5996, 7178, 1800); drop(7178)
  local h = c.A.Char().consume
  assert(h[5996] and h[5996].hits == 2, "a quest's two Water Breathings: a habit")
  c.instance = "party"; fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 2)
  assert(find(shown(c, "mine"), "consume5996"), "asked in the dungeon")
  -- ten minutes on the bar, not used: one miss (no event needed); a use resets it
  tick(c, 601)
  assert(h[5996].miss == 1, "ten minutes ignored: a miss (" .. tostring(h[5996].miss) .. ")")
  use(5996, 7178, 1800)
  assert(h[5996].miss == 0, "used: kept up again")
  drop(7178)
  tick(c, 601); tick(c, 600)
  assert(h[5996] and h[5996].miss == 2, "twice ignored: " .. tostring(h[5996] and h[5996].miss))
  tick(c, 600)
  assert(h[5996] == nil, "three times ignored: forgotten")
  assert(c.A.Char().consumeQuiet[5996], "and quiet")
  assert(not find(shown(c, "mine"), "consume5996"), "and no more asked")
  -- thirty used once, long ago: a new one is still learned
  for i = 1, 30 do h[700000 + i] = { hits = 1, miss = 0, at = i } end
  c.items[9187] = { name = "Elixir of Greater Agility", classID = 0, subID = 2, spell = 11334 }
  c.bags[#c.bags + 1] = { id = 9187, bag = 0, slot = 2, count = 5 }
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 1)
  use(9187, 11334, 3600)
  assert(h[9187] and h[9187].hits == 1 and h[700001] == nil, "the oldest one-off made room")
  noErrors(c)
end)

test("habits: kept by the spell's name; a new rank is the same habit, cast by name; ignored twice ten minutes, forgotten", function()
  local me = member({ name = "Damp", class = "MAGE", level = 60 })
  local c = client({ me = me })
  SPELL_NAMES[604], SPELL_NAMES[8450] = "Dampen Magic", "Dampen Magic"
  c.known[604], c.known[8450] = true, true
  load(c)
  tick(c, 1)
  local function on(id) me.auras[#me.auras + 1] = { id = id, src = "player", exp = c.clock + 600, dur = 600 }; fire(c, "UNIT_AURA", "player"); tick(c, 2) end
  local function off(id) for i = #me.auras, 1, -1 do if me.auras[i].id == id then table.remove(me.auras, i) end end; fire(c, "UNIT_AURA", "player"); tick(c, 2) end
  on(604); off(604); on(604); off(604); on(604)
  local h = c.A.Char().habit
  assert(h["Dampen Magic"] and h["Dampen Magic"].hits == 2 and h["Dampen Magic"].id == 604, "rank 1 recast twice: a habit by its name")
  -- rank 2 learned and cast: the same habit, no icon while it is on
  off(604); on(8450)
  local n = 0
  for k in pairs(h) do n = n + 1 end
  assert(n == 1 and h["Dampen Magic"].id == 8450, "one habit, its rank the new one")
  assert(not find(shown(c, "mine"), "habit:Dampen Magic"), "rank 2 on: nothing asked")
  off(8450)
  local rec = find(shown(c, "mine"), "habit:Dampen Magic")
  assert(rec and rec.click.spell == "Dampen Magic" and rec.click.unit == "player", "off: asked, the click casts the name (the highest rank)")
  local b = icon(c, "own", "habit:Dampen Magic")
  assert(b and b:GetAttribute("spell") == "Dampen Magic", "the secure button casts it by name")
  -- ignored: ten minutes, a miss; twenty, forgotten
  tick(c, 601)
  assert(h["Dampen Magic"].miss == 1, "ten minutes ignored: a miss")
  tick(c, 600)
  assert(h["Dampen Magic"] == nil and not find(shown(c, "mine"), "habit:Dampen Magic"), "twice ignored: forgotten")
  -- a habit kept by a rank's id (0.1.1) moves to its name
  local c2 = client({ me = member({ name = "Old", class = "MAGE", level = 60 }), db = { chars = { ["Player-1-Old"] = { habit = { [604] = { hits = 3, miss = 0 } } } } } })
  c2.known[604] = true
  load(c2); tick(c2, 1)
  local h2 = c2.A.Char().habit
  assert(h2[604] == nil and h2["Dampen Magic"] and h2["Dampen Magic"].id == 604, "moved to its name")
  assert(find(shown(c2, "mine"), "habit:Dampen Magic"), "and asked")
  -- (a Never on it by its id, from 0.1.1: by its name now, still hidden)
  local c3 = client({ me = member({ name = "Older", class = "MAGE", level = 60 }), db = { settings = { never = { ["buff:604"] = "Dampen Magic" } },
    chars = { ["Player-1-Older"] = { habit = { [604] = { hits = 3, miss = 0 } } } } } })
  c3.known[604] = true
  load(c3); tick(c3, 1)
  local never = c3.A.Settings().never
  assert(never["buff:604"] == nil and never["buff:Dampen Magic"] == "Dampen Magic", "the Never moved to the name")
  assert(not find(shown(c3, "mine"), "habit:Dampen Magic"), "and it stays hidden")
  noErrors(c3)
  SPELL_NAMES[604], SPELL_NAMES[8450] = nil, nil
  noErrors(c); noErrors(c2)
end)

test("a juju is learned and asked on you; a quest item's disguise never is", function()
  local me = member({ name = "Juju", class = "WARRIOR", level = 60 })
  local c = client({ me = me })
  c.items[12451] = { name = "Juju Power", classID = 12, subID = 0, spell = 16323 }
  c.items[18258] = { name = "Gordok Ogre Suit", classID = 12, subID = 0, spell = 22736 }
  c.bags = { { id = 12451, bag = 0, slot = 1, count = 5 }, { id = 18258, bag = 0, slot = 2 } }
  load(c)
  tick(c, 1)
  assert(c.A.Buffs.KindOf(12451) == "Use" and c.A.Buffs.KindOf(18258) == nil, "a juju is a consumable; a disguise is not")
  for _ = 1, 2 do
    for _, x in ipairs({ { 12451, 16323 }, { 18258, 22736 } }) do
      fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast" .. c.clock, x[2])
      me.auras[#me.auras + 1] = { id = x[2], src = "player", exp = c.clock + 600, dur = 600 }
      fire(c, "UNIT_AURA", "player"); tick(c, 2)
    end
    me.auras = {}
    fire(c, "UNIT_AURA", "player"); tick(c, 2)
  end
  local h = c.A.Char().consume
  assert(h[12451] and h[12451].hits == 2 and h[18258] == nil, "the juju learned, the suit never")
  c.instance = "raid"; fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 2)
  local rec = find(shown(c, "mine"), "consume12451")
  assert(rec and rec.word == "Use" and rec.click.unit == "player", "asked, on you (a juju takes a target)")
  noErrors(c)
end)

test("soulstone: never on a healer offline or out of sight; a far one greys the icon; a stone on any healer you can see ends it", function()
  local W = member({ name = "Lock", class = "WARLOCK", level = 60, guid = "Player-1-W9" })
  local H1 = member({ name = "Aheal", class = "PRIEST", level = 60, guid = "Player-1-H1", assigned = "HEALER", online = false })
  local H2 = member({ name = "Bheal", class = "PRIEST", level = 60, guid = "Player-1-H2", assigned = "HEALER" })
  local R = member({ name = "Crog", class = "ROGUE", level = 60, guid = "Player-1-R3" })
  local group = { W, H1, H2, R }
  local c = client({ me = W, group = group })
  c.items[16896] = { name = "Major Soulstone" }
  c.bags = { { id = 16896, bag = 0, slot = 1 } }
  load(c)
  tickAll(10)
  local rec = find(shown(c, "group"), "soulstone")
  assert(rec and rec.word == "Bheal" and rec.click.unit and c.units[rec.click.unit] == H2, "the first healer offline: the next one, " .. tostring(rec and rec.word))
  -- the healer far: greyed, no cast
  H2.far = true
  c.A.Bar.Dirty("group"); tick(c, 2)
  rec = find(shown(c, "group"), "soulstone")
  local b = icon(c, "group", "soulstone")
  assert(rec and rec.far and rec.lit == false and rec.word == "Far" and b:GetAttribute("type1") == nil, "out of range: waits, greyed")
  H2.far = nil
  -- out of sight (another zone): not chosen, and nobody else to take it
  H2.visible = false
  c.A.Bar.Dirty("group"); tick(c, 2)
  assert(not find(shown(c, "group"), "soulstone"), "no healer in sight: nothing")
  H2.visible = nil
  -- back, with a stone on: done
  H2.auras[#H2.auras + 1] = { id = 20765, src = "player", exp = c.clock + 1800, dur = 1800 }
  local unit
  for u, x in pairs(c.units) do if x == H2 then unit = u end end
  fire(c, "UNIT_AURA", unit); tick(c, 2)
  assert(not find(shown(c, "group"), "soulstone"), "a stone on the healer: nothing")
  noErrors(c)
end)

test("group buffs: the reagent of the rank cast (Holy Candle for Prayer 1); a buff about to end counts as missing, its countdown", function()
  -- (the priest has it already: the next missing one is a level 45)
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-Q1", auras = { { id = 10938, src = "player", exp = 1000 + 3500, dur = 3600 } } })
  local list = { P }
  for i = 2, 5 do list[i] = member({ name = "L" .. i, class = "WARRIOR", level = 45, guid = "Player-1-Q" .. i }) end
  local c = client({ me = P, group = list })
  knowAll(c, "PRIEST", 60)
  c.items[17029] = { name = "Sacred Candle" }
  c.items[17028] = { name = "Holy Candle" }
  c.bags = { { id = 17029, bag = 0, slot = 1, count = 5 } }
  load(c)
  tickAll(10)
  local b = icon(c, "group", "duty:fort")
  -- (level 45 takes Prayer of Fortitude 1 at most, and it needs a Holy Candle: Sacred Candles alone, one at a time)
  assert(b and b:GetAttribute("spell") == 10937, "no Holy Candle: the single buff, the rank a 45 takes: " .. tostring(b and b:GetAttribute("spell")))
  c.bags[2] = { id = 17028, bag = 0, slot = 2, count = 5 }
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 2)
  assert(b:GetAttribute("spell") == 21562, "a Holy Candle: Prayer of Fortitude 1: " .. tostring(b:GetAttribute("spell")))
  -- everyone has it, an hour left: nothing; then three minutes left on two: those two, the shortest time as its word
  for _, m in ipairs(list) do m.auras = { { id = 10938, src = "player", exp = c.clock + 3000, dur = 3600 } } end
  for u in pairs(c.units) do fire(c, "UNIT_AURA", u) end
  tick(c, 2)
  assert(not find(shown(c, "group"), "duty:fort"), "everyone with an hour: nothing to do")
  list[3].auras[1].exp = c.clock + 200
  list[4].auras[1].exp = c.clock + 150
  for u, x in pairs(c.units) do if x == list[3] or x == list[4] then fire(c, "UNIT_AURA", u) end end
  tick(c, 2)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 2 and rec.status == "warn" and rec.timed and rec.word:find("^2:2"), "two about to end: " .. tostring(rec and rec.word))
  assert(c.units[rec.click.unit] == list[4], "the one ending first is buffed first")
  local fly = c.env[b:GetName() .. "Fly"]
  local s1, s2, s3 = fly.rows[1].state:GetText(), fly.rows[2].state:GetText(), fly.rows[3].state:GetText()
  assert(s1:find("^%d:%d%d$") and s2:find("^%d:%d%d$") and s3 == "on", "the list shows their time left, first: " .. s1 .. ", " .. s2 .. ", " .. s3)
  local was = rec.word
  tick(c, 2)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.word ~= was, "the countdown ticks: " .. was .. " then " .. tostring(rec and rec.word))
  noErrors(c)
end)

test("the group's auras are kept until their own UNIT_AURA; the clock runs only for a countdown; the 3 s look is a timer", function()
  local P = member({ name = "Kpri", class = "PRIEST", level = 60, guid = "Player-1-K1" })
  local list = { P }
  for i = 2, 5 do list[i] = member({ name = "K" .. i, class = "WARRIOR", level = 60, guid = "Player-1-K" .. i }) end
  local c = client({ me = P, group = list })
  knowAll(c, "PRIEST", 60)
  load(c)
  tickAll(10)
  assert(find(shown(c, "group"), "duty:fort"), "Fortitude owed")
  assert(not c.A.Bar.clockOn, "a group icon with no countdown: no clock")
  for _, f in ipairs(c.frames) do assert(not f.__scripts.OnUpdate or f == c.A.Bar.clock, "no frame ticks every frame for the 3 s look") end
  -- refreshes with nothing changed: no aura read
  c.auraReads = {}
  for _ = 1, 20 do c.A.Bar.Refresh() end
  for u, n in pairs(c.auraReads) do assert(u == "player", "twenty refreshes, the group's auras kept: " .. u .. " read " .. n .. " times") end
  -- a member's aura changes: read again on their own UNIT_AURA
  list[2].auras = { { id = 10938, src = "player", exp = c.clock + 3000, dur = 3600 } }
  local unit
  for u, x in pairs(c.units) do if x == list[2] then unit = u end end
  fire(c, "UNIT_AURA", unit); tick(c, 2)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 4, "their UNIT_AURA: read again, one fewer missing: " .. tostring(rec and rec.count))
  -- the 3 s look still comes (a member walking into range), as a timer
  list[3].far = true; list[4].far = true; list[5].far = true; P.auras = { { id = 10938, src = "player", exp = c.clock + 3000, dur = 3600 } }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.word == "Far", "all far")
  list[3].far = nil
  tick(c, 4)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.word == "K3", "the 3 s look saw them walk in: " .. tostring(rec and rec.word))
  noErrors(c)
end)

----------------------------------------------------------------------------
-- the share-out's rules over reloads, opt-outs, ranks and the grid
----------------------------------------------------------------------------
-- a /reload: PLAYER_LOGOUT on the old client (the game writes the saved variables then), the old one gone, a new one
-- with those saved variables, its spells, its clock and its group (load it after)
local function reload(c)
  fire(c, "PLAYER_LOGOUT")
  for i, x in ipairs(WORLD) do if x == c then table.remove(WORLD, i) break end end
  local o = {}
  for k, v in pairs(c.o) do o[k] = v end
  o.db = c.env.CuteAurasDB
  local n = client(o)
  n.clock = c.clock
  for id in pairs(c.known) do n.known[id] = true end
  return n
end
local function dutyOf(c, key) for _, d in ipairs(c.A.Assign.duties) do if d.key == key then return d end end return nil end
local function fortOf(c) local d = dutyOf(c, "fort"); return d and #d.targets or 0 end
-- a widget on a page by its words: a check's or a choice's label, a button's text
local function widget(page, text)
  for _, o in ipairs(page.__children) do
    if (o.label and o.label.__text == text) or (o.text and o.text.__text == text) then return o end
    local inner = widget(o, text)
    if inner then return inner end
  end
  return nil
end
local function gridCell(c, pal, bucket)
  for _, cell in ipairs(c.A.Window.pages.blessings.cells) do
    if cell.pal == pal and cell.bucket == bucket and cell:IsShown() then return cell end
  end
  return nil
end

test("blessings set by hand survive your /reload; a clear stays stamped; a tie ends the same on every client; leaving lets go", function()
  local P = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-H1" })
  local Q = member({ name = "Bpal", class = "PALADIN", level = 60, guid = "Player-1-H2", leader = true })
  local W = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-H3", assigned = "TANK" })
  local group = { P, Q, W }
  local c1 = client({ me = P, group = group, spec = 184 })
  local c2 = client({ me = Q, group = group, spec = 184 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "PALADIN", 60)
  load(c1); load(c2)
  tickAll(12)
  local tank = "WARRIOR:tank"
  assert(c2.A.Assign.BlessingOf(P.guid, tank) == "kings", "Cute Auras' choice: the first paladin gives the tank Kings")
  c1.A.Assign.Set(P.guid, tank, "might")
  tickAll(3)
  assert(c2.A.Assign.BlessingOf(P.guid, tank) == "might" and c2.A.Assign.BlessingOf(Q.guid, tank) == "kings", "the hand-set Might heard")
  -- P reloads: the Might it set comes back from the saved variables, and both clients still agree
  c1 = reload(c1)
  load(c1)
  assert(c1.A.Assign.BlessingOf(P.guid, tank) == "might", "at login already: " .. tostring(c1.A.Assign.BlessingOf(P.guid, tank)))
  tickAll(12)
  for _, c in ipairs({ c1, c2 }) do
    assert(c.A.Assign.BlessingOf(P.guid, tank) == "might" and c.A.Assign.BlessingOf(Q.guid, tank) == "kings", "both agree after the reload")
  end
  local function gives(c, key, m)
    for _, t in ipairs((dutyOf(c, key) or { targets = {} }).targets) do if t.guid == m.guid then return true end end
    return false
  end
  assert(gives(c1, "bless:might", W) and not gives(c1, "bless:kings", W), "P's bar asks for Might on the tank, not Kings")
  assert(c1.env.CuteAurasDB.chars[P.guid].group == nil, "what was saved is read once")
  -- the leader's clear, then an older Might still waiting out a lockdown: the clear stays, as Cute Auras' choice
  local As1, As2 = c1.A.Assign, c2.A.Assign
  local b = "PALADIN:melee"
  assert(As1.SetOverride(P.guid, b, nil, 5000, Q.guid), "the leader clears it")
  assert(As1.SetOverride(P.guid, b, "wisdom", 4990, P.guid) == false, "an older blessing after a clear loses")
  assert(As1.overrides[P.guid][b].clear, "the clear is kept, stamped")
  -- two setters in the same second, heard in either order: the same one wins everywhere
  As1.SetOverride(P.guid, b, "kings", 5100, P.guid); As1.SetOverride(P.guid, b, "wisdom", 5100, Q.guid)
  As2.SetOverride(P.guid, b, "wisdom", 5100, Q.guid); As2.SetOverride(P.guid, b, "kings", 5100, P.guid)
  assert(As1.overrides[P.guid][b].key == As2.overrides[P.guid][b].key, "a tie ends the same on both clients")
  tickAll(2)
  -- a saved group older than an hour is never read back
  local c3 = reload(c1)
  c3.o.db.chars[P.guid].group.at = c3.clock - 4000
  load(c3)
  assert(next(c3.A.Comm.peers) == nil and next(c3.A.Assign.overrides) == nil, "an old save: nothing read back")
  tickAll(12)
  -- leaving the group lets the hand-set blessings go, and nothing is kept for a next login
  c3.o.group = nil; seat(c3)
  fire(c3, "GROUP_ROSTER_UPDATE")
  tick(c3, 2)
  assert(next(c3.A.Assign.overrides) == nil, "left: the hand-set blessings let go")
  fire(c3, "PLAYER_LOGOUT")
  assert(c3.env.CuteAurasDB.chars[P.guid].group == nil, "nothing saved out of a group")
  for _, c in ipairs({ c2, c3 }) do noErrors(c, "reload") end
end)

test("a /reload in a fight: the saved hellos give the group's share-out at once, never you as the only buffer", function()
  local g = party5()
  assert(fortOf(g.c1) == 5 and fortOf(g.c2) == 0, "priest A gives Fortitude, priest B none")
  fight(g.c1, true); fight(g.c3, true)
  local c2 = reload(g.c2)
  load(c2)
  fight(c2, true)
  tickAll(3)
  assert(c2.A.Comm.peers[g.P1.guid] and c2.A.Comm.peers[g.P1.guid].restored, "priest A's hello read back from the save")
  assert(c2.A.Comm.peers[g.PAL.guid] and c2.A.Comm.peers[g.PAL.guid].role == "melee", "the paladin's role read back")
  assert(fortOf(c2) == 0 and c2.A.Assign.Owed(g.ROG.guid) == nil, "the reloaded priest owes nobody Fortitude: " .. fortOf(c2))
  -- the fight ends: the real hellos replace the saved ones, and the share-out stays
  fight(g.c1, false); fight(g.c3, false); fight(c2, false)
  tickAll(12)
  assert(not c2.A.Comm.peers[g.P1.guid].restored and fortOf(c2) == 0 and fortOf(g.c1) == 5, "heard again, the same share-out")
  for _, c in ipairs({ g.c1, c2, g.c3 }) do noErrors(c, "reload in a fight") end
end)

test("a buffer who opts out (Never, the group's part off, Nothing in an instance) hands the buff to another", function()
  local g = party5()
  assert(fortOf(g.c1) == 5 and fortOf(g.c2) == 0, "priest A gives Fortitude")
  -- Never on the Fortitude icon
  g.c1.A.Bar.SetNever("duty:fort", "Power Word: Fortitude")
  tickAll(5)
  assert(fortOf(g.c1) == 0 and fortOf(g.c2) == 5, "Never: priest B gives it now: " .. fortOf(g.c1) .. " and " .. fortOf(g.c2))
  assert(g.c1.A.Assign.Owed(g.ROG.guid) == nil or not g.c1.A.Assign.Owed(g.ROG.guid)[1] or g.c1.A.Assign.Owed(g.ROG.guid)[1].key ~= "fort", "no rebuff owed for it")
  g.c1.A.Bar.SetNever("duty:fort", nil, false)
  tickAll(5)
  assert(fortOf(g.c1) == 5 and fortOf(g.c2) == 0, "back from Never")
  -- the group's part off in Settings
  g.c1.A.Window.Open("settings")
  local row = widget(g.c1.A.Window.pages.settings, "Buffs you give the group")
  g.c1.click(row)
  tickAll(5)
  assert(g.c1.A.Settings().group == false and fortOf(g.c1) == 0 and fortOf(g.c2) == 5, "group part off: priest B gives it")
  g.c1.click(row)
  tickAll(5)
  assert(fortOf(g.c1) == 5, "group part on again")
  -- Nothing in dungeons and raids, inside one
  g.c1.A.Settings().instance = "none"
  for _, c in ipairs({ g.c1, g.c2, g.c3 }) do c.instance = "party"; fire(c, "PLAYER_ENTERING_WORLD") end
  tickAll(6)
  assert(fortOf(g.c1) == 0 and fortOf(g.c2) == 5, "Nothing in an instance: priest B gives it")
  for _, c in ipairs({ g.c1, g.c2, g.c3 }) do c.instance = nil; fire(c, "PLAYER_ENTERING_WORLD") end
  tickAll(6)
  assert(fortOf(g.c1) == 5, "out again: priest A")
  -- a paladin's blessing on Never: the share-out gives that bucket the next one
  assert(g.c1.A.Assign.BlessingOf(g.PAL.guid, "PRIEST:healer") == "wisdom", "Wisdom to the healer")
  g.c3.A.Bar.SetNever("duty:bless:wisdom", "Blessing of Wisdom")
  tickAll(5)
  assert(g.c1.A.Assign.BlessingOf(g.PAL.guid, "PRIEST:healer") == "kings", "Wisdom on Never: Kings, on every client")
  for _, c in ipairs({ g.c1, g.c2, g.c3 }) do noErrors(c, "opt out") end
end)

test("single buffs go to the highest rank announced: a level 28 priest never covers a level 60's party", function()
  local LOW = member({ name = "Alow", class = "PRIEST", level = 28, guid = "Player-1-A0" })
  local HI = member({ name = "Zhi", class = "PRIEST", level = 60, guid = "Player-1-Z9" })
  local WAR = member({ name = "Bwar", class = "WARRIOR", level = 60, guid = "Player-1-B1" })
  local group = { LOW, HI, WAR }
  local c1 = client({ me = LOW, group = group })
  local c2 = client({ me = HI, group = group })
  knowAll(c1, "PRIEST", 28); knowAll(c2, "PRIEST", 60)
  load(c1); load(c2)
  tickAll(12)
  assert(fortOf(c2) == 3 and fortOf(c1) == 0, "the level 60 gives Fortitude, not the first by GUID: " .. fortOf(c1) .. " and " .. fortOf(c2))
  noErrors(c1); noErrors(c2)
end)

test("blessings: a paladin who knows more keeps the one only they give; a class over two buckets lines up for Greater", function()
  -- a level 26 (Kings, Might, Wisdom) and a level 14 (Might, Wisdom; Kings at 20)
  local P1 = member({ name = "Apal", class = "PALADIN", level = 26, guid = "Player-1-K1" })
  local P2 = member({ name = "Bpal", class = "PALADIN", level = 14, guid = "Player-1-K2" })
  local R = member({ name = "Crog", class = "ROGUE", level = 26, guid = "Player-1-K3" })
  local M = member({ name = "Dmag", class = "MAGE", level = 26, guid = "Player-1-K4" })
  local group = { P1, P2, R, M }
  local c1 = client({ me = P1, group = group, spec = 184 })
  local c2 = client({ me = P2, group = group, spec = 184 })
  knowAll(c1, "PALADIN", 26); knowAll(c2, "PALADIN", 14)
  load(c1); load(c2)
  tickAll(12)
  for _, c in ipairs({ c1, c2 }) do
    local As = c.A.Assign
    assert(As.BlessingOf(P1.guid, "ROGUE:melee") == "kings" and As.BlessingOf(P2.guid, "ROGUE:melee") == "might",
      "rogue: Kings from the 26, Might from the 14: " .. tostring(As.BlessingOf(P1.guid, "ROGUE:melee")) .. ", " .. tostring(As.BlessingOf(P2.guid, "ROGUE:melee")))
    assert(As.BlessingOf(P1.guid, "MAGE:caster") == "kings" and As.BlessingOf(P2.guid, "MAGE:caster") == "wisdom", "mage: Kings and Wisdom")
  end
  noErrors(c1); noErrors(c2)

  -- two level 60 paladins, warrior damage and a warrior tank: each paladin gives every warrior one blessing, Greater on
  WORLD = {}
  local A1 = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-G1" })
  local A2 = member({ name = "Bpal", class = "PALADIN", level = 60, guid = "Player-1-G2" })
  local T = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-G3", assigned = "TANK" })
  local W1 = member({ name = "Dwar", class = "WARRIOR", level = 60, guid = "Player-1-G4" })
  local W2 = member({ name = "Ewar", class = "WARRIOR", level = 60, guid = "Player-1-G5" })
  local g2 = { A1, A2, T, W1, W2 }
  local d1 = client({ me = A1, group = g2, spec = 184 })
  local d2 = client({ me = A2, group = g2, spec = 184 })
  knowAll(d1, "PALADIN", 60); knowAll(d2, "PALADIN", 60)
  load(d1); load(d2)
  tickAll(12)
  for _, c in ipairs({ d1, d2 }) do
    local As = c.A.Assign
    for _, pal in ipairs({ A1, A2 }) do
      assert(As.BlessingOf(pal.guid, "WARRIOR:tank") == As.BlessingOf(pal.guid, "WARRIOR:melee"), "one blessing to every warrior")
    end
    assert(As.BlessingOf(A1.guid, "WARRIOR:tank") ~= As.BlessingOf(A2.guid, "WARRIOR:tank"), "the tank still gets both")
  end
  for _, c in ipairs({ d1, d2 }) do
    local found = false
    for _, d in ipairs(c.A.Assign.duties) do if d.bless and d.greater.WARRIOR then found = true end end
    assert(found, "a Greater blessing for the warriors")
  end
  noErrors(d1); noErrors(d2)
end)

test("the grid: a click cycles only what that paladin gives (no Wisdom without a mana bar); one they can't give is never a blank", function()
  local P1 = member({ name = "Apal", class = "PALADIN", level = 26, guid = "Player-1-K1", leader = true })
  local P2 = member({ name = "Bpal", class = "PALADIN", level = 14, guid = "Player-1-K2" })
  local R = member({ name = "Crog", class = "ROGUE", level = 26, guid = "Player-1-K3" })
  local M = member({ name = "Dmag", class = "MAGE", level = 26, guid = "Player-1-K4" })
  local group = { P1, P2, R, M }
  local c1 = client({ me = P1, group = group, spec = 184 })
  local c2 = client({ me = P2, group = group, spec = 184 })
  knowAll(c1, "PALADIN", 26); knowAll(c2, "PALADIN", 14)
  load(c1); load(c2)
  tickAll(12)
  local As = c2.A.Assign
  c2.A.Window.Open("blessings")
  assert(As.BlessingOf(P2.guid, "MAGE:caster") == "wisdom", "the 14 gives the mage Wisdom")
  local cell = gridCell(c2, P2.guid, "MAGE:caster")
  assert(cell, "the cell")
  c2.hover(cell)
  assert(c2.env.GameTooltip.lines[3] == "Click: Blessing of Might.", "the tooltip says what a click sets: " .. tostring(c2.env.GameTooltip.lines[3]))
  c2.click(cell)
  tick(c2, 1)
  assert(As.BlessingOf(P2.guid, "MAGE:caster") == "might", "Wisdom, then Might (no Kings at 14)")
  cell = gridCell(c2, P2.guid, "MAGE:caster")
  c2.click(cell)
  c2.click(cell) -- (a second click before the share-out runs again steps on from the one set, not the old one)
  tick(c2, 1)
  assert(As.BlessingOf(P2.guid, "MAGE:caster") == "might", "Might, Wisdom, Might: " .. tostring(As.BlessingOf(P2.guid, "MAGE:caster")))
  -- the rogue: Might, and nothing else that paladin gives it (no Kings, no Wisdom without a mana bar)
  local was = As.overrides[P2.guid] and As.overrides[P2.guid]["ROGUE:melee"]
  c2.click(gridCell(c2, P2.guid, "ROGUE:melee"))
  tick(c2, 1)
  assert((As.overrides[P2.guid] and As.overrides[P2.guid]["ROGUE:melee"]) == was and As.BlessingOf(P2.guid, "ROGUE:melee") == "might", "nothing else to set")
  -- the leader sets Kings for the 14: never honoured, and never a blank either
  c1.A.Assign.Set(P2.guid, "ROGUE:melee", "kings")
  tickAll(3)
  for _, c in ipairs({ c1, c2 }) do assert(c.A.Assign.BlessingOf(P2.guid, "ROGUE:melee") == "might", "Cute Auras' choice stays") end
  noErrors(c1); noErrors(c2)
end)

test("the grid fits a raid: 8 paladins across, 20 kinds of member down, tanks first, the rest a scroll away", function()
  -- (each member's class and the role the group or their own Cute Auras gives: twenty buckets)
  local spec = { [1] = 594, [2] = 267, [3] = 184, [4] = 594, [5] = 267, [6] = 184, [7] = 594, [8] = 184 }
  local rows = {
    { "DRUID", nil }, { "DRUID", "TANK" }, { "DRUID", "DAMAGER" }, { "HUNTER" }, { "MAGE" }, { "PRIEST" }, { "PRIEST", "DAMAGER" },
    { "ROGUE" }, { "WARLOCK" }, { "WARRIOR" }, { "WARRIOR", "TANK" }, { "SHAMAN" }, { "SHAMAN", "DAMAGER" },
  }
  local list = {}
  for i = 1, 8 do list[#list + 1] = member({ name = "Paladin" .. i, class = "PALADIN", level = 60, guid = string.format("Player-1-P%02d", i) }) end
  for i, r in ipairs(rows) do list[#list + 1] = member({ name = "Member" .. i, class = r[1], level = 60, guid = string.format("Player-1-M%02d", i), assigned = r[2] }) end
  -- (four who chose Tank in their own Settings: a mage, a rogue, a hunter and a warlock)
  local chosen = {}
  for i, cl in ipairs({ "MAGE", "ROGUE", "HUNTER", "WARLOCK" }) do
    local m = member({ name = "Chose" .. i, class = cl, level = 60, guid = string.format("Player-1-T%02d", i) })
    list[#list + 1] = m
    chosen[#chosen + 1] = m
  end
  for i, m in ipairs(list) do m.sub = math.floor((i - 1) / 5) + 1 end
  local cs = {}
  for i = 1, 8 do
    local c = client({ me = list[i], group = list, raid = true, spec = spec[i] })
    knowAll(c, "PALADIN", 60)
    cs[#cs + 1] = c
  end
  for _, m in ipairs(chosen) do
    local c = client({ me = m, group = list, raid = true, db = { chars = { [m.guid] = { role = "tank" } } } })
    knowAll(c, m.class, 60)
    cs[#cs + 1] = c
  end
  for _, c in ipairs(cs) do load(c) end
  tickAll(15)
  local c = cs[1]
  local As = c.A.Assign
  assert(#As.paladins == 8, "eight paladins: " .. #As.paladins)
  assert(#As.bucketList == 20, "twenty buckets: " .. #As.bucketList)
  c.A.Window.Open("blessings")
  local page = c.A.Window.pages.blessings
  local function x(o) return o.__points[1][4] end
  local function y(o) return o.__points[1][5] end
  local function check()
    for _, col in ipairs(page.cols) do
      if col:IsShown() then assert(x(col) + col.__w <= 612, "a paladin's name past the page: " .. (x(col) + col.__w)); FITS(col, "a paladin's name") end
    end
    for _, cell in ipairs(page.cells) do
      if cell:IsShown() then
        assert(x(cell) + cell.__w <= 612, "a cell past the page's right: " .. (x(cell) + cell.__w))
        assert(y(cell) - cell.__h >= -444 + 32, "a cell into the words under the grid: " .. (y(cell) - cell.__h))
      end
    end
    for _, r in ipairs(page.rows) do if r:IsShown() then FITS(r, "a row's name") end end
    FITS(page.title, "the title"); FITS(page.more, "the scroll line")
    -- (the words under the grid: thirteen members without Cute Auras, as many names as fit, the rest counted)
    for _, t in ipairs(page.lines) do if t:IsShown() then FITS(t, "a line under the grid") end end
  end
  check()
  local without
  for _, t in ipairs(page.lines) do if t:IsShown() and t.__text:find("^Without Cute Auras") then without = t.__text end end
  assert(without and without:find("Member1, ", 1, true) and without:find(" and %d+ more%.$"), "the names that fit, the rest counted: " .. tostring(without))
  local shownRows = {}
  for _, r in ipairs(page.rows) do if r:IsShown() then shownRows[#shownRows + 1] = r.__text end end
  assert(#shownRows == 17, "seventeen rows fit: " .. #shownRows)
  assert(shownRows[1]:find("Tank") and shownRows[7]:find("Tank"), "tanks first: " .. shownRows[1] .. " / " .. shownRows[7])
  local hasWarTank = false
  for _, t in ipairs(shownRows) do if t:find("^Warrior, Tank") then hasWarTank = true end end
  assert(hasWarTank, "the warrior tanks on the page")
  assert(page.more.__text == "Scroll: 1-17 of 20", "the scroll line: " .. page.more.__text)
  -- the wheel: the last rows
  page.__scripts.OnMouseWheel(page, -5)
  check()
  assert(page.more.__text == "Scroll: 4-20 of 20", "scrolled to the end: " .. page.more.__text)
  for _, x2 in ipairs(cs) do noErrors(x2, "grid") end
end)

test("your role is each character's: an alt never announces the main's; Swap for me is each character's too", function()
  local db = { settings = { role = "tank", gear = { auto = true } } }
  local main = member({ name = "Main", class = "WARRIOR", level = 60 })
  local c = client({ me = main, db = db })
  load(c)
  tick(c, 1)
  assert(c.A.Roster.MyRole() == "melee", "an old account-wide Tank let go: " .. tostring(c.A.Roster.MyRole()))
  assert(db.settings.role == nil and db.settings.gear.auto == nil, "the old account-wide values cleared")
  c.A.Window.Open("settings")
  local roleRow = widget(c.A.Window.pages.settings, "Your role")
  local tankButton
  for _, b in ipairs(roleRow.buttons) do if b.value == "tank" then tankButton = b end end
  c.click(tankButton)
  tick(c, 1)
  assert(c.A.Roster.MyRole() == "tank" and db.chars[main.guid].role == "tank", "Tank on the main")
  c.A.Window.Open("gear")
  c.click(widget(c.A.Window.pages.gear, "Swap for me (out of a fight)"))
  assert(db.chars[main.guid].gearAuto == true, "Swap for me on the main")
  noErrors(c)
  -- an alt on the same account
  WORLD = {}
  local alt = member({ name = "Alt", class = "MAGE", level = 60 })
  local c2 = client({ me = alt, db = db })
  load(c2)
  tick(c2, 1)
  assert(c2.A.Roster.MyRole() == "caster", "the alt is a caster, not the main's tank: " .. tostring(c2.A.Roster.MyRole()))
  assert(c2.A.Char().gearAuto == nil, "the alt's Swap for me is off")
  noErrors(c2)
end)

test("self buffs: another paladin's aura on you is theirs; you are asked for another kind, and never for one already there", function()
  local P1 = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-S1" })
  local P2 = member({ name = "Bpal", class = "PALADIN", level = 60, guid = "Player-1-S2" })
  local group = { P1, P2 }
  local c = client({ me = P2, group = group, spec = 184 })
  knowAll(c, "PALADIN", 60)
  load(c)
  tick(c, 2)
  -- P1's Devotion Aura on you
  P2.auras = { { id = 10293, src = "party1", exp = 0 } }
  fire(c, "UNIT_AURA", "player")
  campNow(c)
  assert(find(shown(c, "mine"), "self:aura"), "another's Devotion Aura doesn't count as yours")
  local b = icon(c, "mine", "self:aura")
  assert(b and b:GetAttribute("spell") == 10301, "asked for Retribution Aura, not a second Devotion: " .. tostring(b and b:GetAttribute("spell")))
  -- your own on too: nothing asked
  table.insert(P2.auras, { id = 10301, src = "player", exp = 0 })
  fire(c, "UNIT_AURA", "player")
  campNow(c)
  assert(not find(shown(c, "mine"), "self:aura"), "your own aura is up")
  -- your Devotion under theirs: yours is kept, nothing asked
  P2.auras = { { id = 10293, src = "party1", exp = 0 }, { id = 10293, src = "player", exp = 0 } }
  fire(c, "UNIT_AURA", "player")
  campNow(c)
  assert(not find(shown(c, "mine"), "self:aura"), "yours and theirs both: yours counts")
  noErrors(c)
end)

-- (a biome piece the client sends with only its tooltip to go by: "<words> in <Biome> areas")
local function biomeItem(c, id, name, equipLoc, biomeWord, more)
  c.items[id] = { name = name, equipLoc = equipLoc }
  for k, v in pairs(more or {}) do c.items[id][k] = v end
  c.tooltips[id] = { { leftText = name }, { leftText = "Equip: Increases Stamina by 5 in " .. biomeWord .. " areas." } }
end
local function bagsOf(c, ids)
  c.bags = {}
  for i, id in ipairs(ids) do c.bags[i] = { id = id, bag = 0, slot = i } end
  fire(c, "BAG_UPDATE_DELAYED")
end

test("biome gear: a set bonus or flavour text never makes a biome piece; a subzone counts in its own zone only", function()
  local me = member({ name = "Setter", class = "MAGE", level = 20 })
  local c = client({ me = me, zone = "Tirisfal Glades" })
  SPELL_DESC[1321560] = "When your Mana falls below 15%, restore 120 Mana over 6 sec. Restores twice as much Mana in Haunted and Wasteland areas. May only occur once every 2 min."
  -- Rotmender's Raiment: every piece shows the set's 4-piece bonus, which names Haunted and Wasteland
  c.items[990020] = { name = "Rotmender's Gloves", equipLoc = "INVTYPE_HAND" }
  c.tooltips[990020] = { { leftText = "Rotmender's Gloves" }, { leftText = "Equip: Increases Intellect by 4." },
    { leftText = "Rotmender's Raiment (0/5)" }, { leftText = "(4) Set: " .. SPELL_DESC[1321560] } }
  -- an active set bonus ("Set: "), and flavour text with a biome's words
  c.items[990021] = { name = "Frostbitten Wraps", equipLoc = "INVTYPE_WRIST" }
  c.tooltips[990021] = { { leftText = "Frostbitten Wraps" }, { leftText = "Set: Movement speed increased by 3% in Snowy areas." },
    { leftText = "\"Worn in Snowy areas long ago.\"", type = 37 } }
  -- the same text as the piece's own Equip line: a biome piece
  c.items[990022] = { name = "Ghostly Gloves", equipLoc = "INVTYPE_HAND" }
  c.tooltips[990022] = { { leftText = "Ghostly Gloves" }, { leftText = "Equip: " .. SPELL_DESC[1321560] } }
  c.bags = { { id = 990020, bag = 0, slot = 1 }, { id = 990021, bag = 0, slot = 2 }, { id = 990022, bag = 0, slot = 3 } }
  load(c)
  tick(c, 2)
  local G = c.A.Gear
  assert(G.BiomesOf(990020, 0, 1) == nil, "a set bonus naming Haunted and Wasteland makes no lone piece a biome piece")
  assert(G.BiomesOf(990021, 0, 2) == nil, "an active set bonus or flavour text neither")
  local own = G.BiomesOf(990022, 0, 3)
  assert(own and own[1] == "haunted" and own[2] == "wasteland", "the same words on the piece's own Equip line do")
  -- places: the outdoor Dire Maul (a Feralas subzone) is not the Haunted instance of that name
  c.zone, c.subzone = "Feralas", "Dire Maul"
  local here = G.Here()
  assert(here.forest and not here.haunted, "the ruins of Dire Maul in Feralas: Feralas' Forest, not Haunted")
  c.zone, c.subzone = "Dire Maul", ""
  assert(G.Here().haunted, "inside the instance: Haunted")
  c.zone, c.subzone = "Tanaris", "Booty Bay"
  assert(not G.Here().forest, "a subzone's name counts in its own zone only (Booty Bay is Stranglethorn's)")
  noErrors(c)
end)

test("biome gear: a gated aura teaches a place only once the place has settled; old bare-name places let go; the tab forgets them", function()
  local me = member({ name = "Wanderer", class = "HUNTER", level = 30, auras = { { id = 1306905, exp = 0 } } })
  local db = { acct = { biomePlaces = { ["Loch Modan"] = { snowy = true } } } }
  local c = client({ me = me, zone = "Dun Morogh", db = db })
  c.subzone = "Kharanos"
  load(c)
  tick(c, 5)
  local places = db.acct.biomePlaces
  assert(places["Dun Morogh|Kharanos"] and places["Dun Morogh|Kharanos"].snowy, "learned where it settled")
  assert(places["Loch Modan"] == nil, "a place kept by its bare name before is let go")
  -- ride into Loch Modan: the zone text changes at once, Fang of the Forlorn's Snowy aura goes a moment later
  c.zone, c.subzone = "Loch Modan", "Thelsamar"
  fire(c, "ZONE_CHANGED_NEW_AREA"); fire(c, "UNIT_AURA", "player")
  tick(c, 1)
  me.auras = {}
  fire(c, "UNIT_AURA", "player")
  tick(c, 5)
  assert(places["Loch Modan|Thelsamar"] == nil and places["Loch Modan|"] == nil, "the last zone's aura taught Loch Modan nothing")
  assert(not c.A.Gear.Here().snowy, "Loch Modan is not Snowy")
  -- the tab: how many, and Forget learned places
  c.A.Window.Open("gear")
  local page = c.A.Window.pages.gear
  assert(page.learned.__text == "1 place learned from your biome auras.", page.learned.__text)
  local forget = widget(page, "Forget learned places")
  assert(forget and forget:IsShown(), "the button")
  c.click(forget)
  assert(next(places) == nil, "forgotten")
  assert(not forget:IsShown() and page.learned.__text == "No places learned from your biome auras yet.", "nothing left to forget")
  noErrors(c)
end)

test("Swap for me: never mid-cast or dead; the next piece follows by itself; a slot you change by hand stays yours here; a refused swap waits", function()
  local me = member({ name = "Swapper", class = "MAGE", level = 55 })
  local c = client({ me = me, zone = "Winterspring" })
  c.items[249469] = { name = "Frozen Heart of the Mountain", equipLoc = "INVTYPE_TRINKET", spell = 1249110 }
  biomeItem(c, 990030, "Frost Cloak", "INVTYPE_CLOAK", "Snowy")
  c.items[5000] = { name = "Plain Charm", equipLoc = "INVTYPE_TRINKET" }
  c.items[5001] = { name = "Other Charm", equipLoc = "INVTYPE_TRINKET" }
  c.items[5002] = { name = "Plain Cloak", equipLoc = "INVTYPE_CLOAK" }
  c.equipped[13], c.equipped[14], c.equipped[15] = 5000, 5001, 5002
  c.bags = { { id = 249469, bag = 0, slot = 1 }, { id = 990030, bag = 0, slot = 2 } }
  load(c)
  c.A.Char().gearAuto = true
  -- channelling Fishing: UnitChannelInfo answers its name, never true
  c.channel = "Fishing"
  c.A.Bar.Dirty("gear"); tick(c, 5)
  assert(#shown(c, "gear") == 2, "two swaps for the snow: " .. keysOf(shown(c, "gear")))
  assert(#c.equips == 0, "never mid-channel")
  -- dead: the bar away, nothing put on
  c.channel = nil; me.dead = true
  fire(c, "PLAYER_DEAD"); tick(c, 5)
  assert(#c.equips == 0 and #c.uiErrors == 0, "never while dead")
  me.dead = false
  fire(c, "PLAYER_ALIVE"); tick(c, 1)
  assert(#c.equips == 1, "alive: the first swap, " .. #c.equips)
  -- the second follows once the 3 s are up, with no other event
  tick(c, 4)
  assert(#c.equips == 2, "the second piece by itself: " .. #c.equips)
  assert(c.equipped[15] == 990030 and (c.equipped[13] == 249469 or c.equipped[14] == 249469), "both worn")
  local home = c.A.Char().gearHome
  assert(home[15] == 5002, "the cloak it replaced kept, once the game made the swap")
  -- the cloak taken off by hand for the plain one: left alone while the biomes here stay the same
  c.equipNow(5002, 15)
  tick(c, 8)
  assert(#c.equips == 2 and c.equipped[15] == 5002, "a slot changed by hand stays yours here")
  assert(find(shown(c, "gear"), "gear:in:15"), "its swap still on the bar for a click")
  -- elsewhere (its trinket goes back) and back in the snow: Swap for me does the cloak again
  c.zone = "Elwynn Forest"; fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 5)
  c.zone = "Winterspring"; fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 8)
  assert(c.equipped[15] == 990030, "the cloak again after the biomes changed")
  -- a swap the game refuses: tried once, not again for a minute, while the next goes on
  c.zone = "Elwynn Forest"; fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 10)
  assert(c.equipped[15] == 5002, "back in Elwynn: the plain cloak back on")
  c.refuse = { [990030] = true }
  c.zone = "Winterspring"; fire(c, "ZONE_CHANGED_NEW_AREA")
  local n = #c.equips
  tick(c, 20)
  local tries = 0
  for i = n + 1, #c.equips do if c.equips[i][1] == 990030 then tries = tries + 1 end end
  assert(tries == 1 and #c.uiErrors == 1, "a refused swap tried once: " .. tries .. ", errors " .. #c.uiErrors)
  noErrors(c)
end)

test("Swap for me: a piece not yet bound to you is offered, never put on for you (no bind popup)", function()
  local me = member({ name = "Binder", class = "PRIEST", level = 50 })
  local c = client({ me = me, zone = "Winterspring" })
  biomeItem(c, 990030, "Frost Cloak", "INVTYPE_CLOAK", "Snowy")
  c.items[5002] = { name = "Plain Cloak", equipLoc = "INVTYPE_CLOAK" }
  c.equipped[15] = 5002
  c.bags = { { id = 990030, bag = 0, slot = 1, boe = true } }
  load(c)
  c.A.Char().gearAuto = true
  c.A.Bar.Dirty("gear"); tick(c, 10)
  local rec = shown(c, "gear")[1]
  assert(rec and rec.unbound, "offered, known as unbound")
  assert(#c.equips == 0 and c.bindPopups == 0, "never put on for you")
  c.A.Bar.Tip(icon(c, "own", rec.key), rec)
  local said = table.concat(c.env.GameTooltip.lines, " | ")
  assert(said:find("binds it to you", 1, true), "its tooltip says why: " .. said)
  assert(not said:find("on-use trinket", 1, true), "no trinket rule on a cloak")
  noErrors(c)
end)

test("biome gear: Unique-Equipped seals never two at once; the pair's slot that loses least; the higher item level first", function()
  local me = member({ name = "Sealer", class = "WARRIOR", level = 50 })
  local c = client({ me = me, zone = "Elwynn Forest" })
  for _, x in ipairs({ { 271903, "Enriched Seal", 53 }, { 271904, "Volunteer's Lucky Seal", 38 }, { 271906, "Volunteer's Lucky Seal", 53 } }) do
    c.items[x[1]] = { name = x[2], equipLoc = "INVTYPE_TRINKET", limitCat = 715, limitMax = 1, ilvl = x[3] }
  end
  c.items[5000] = { name = "Plain Charm", equipLoc = "INVTYPE_TRINKET" }
  c.items[5003] = { name = "Ready Charm", equipLoc = "INVTYPE_TRINKET", spell = 9999 }
  c.equipped[13], c.equipped[14] = 271903, 5000
  c.bags = { { id = 271904, bag = 0, slot = 1 } }
  load(c)
  tick(c, 2)
  assert(#shown(c, "gear") == 0, "a second Seal of Battle never offered beside the first: " .. keysOf(shown(c, "gear")))
  -- two seals in the bags; a ready on-use charm in 13, a passive one in 14: one seal, the item level 53, over the passive
  c.equipped[13], c.equipped[14] = 5003, 5000
  bagsOf(c, { 271904, 271906 })
  tick(c, 2)
  local gear = shown(c, "gear")
  assert(#gear == 1, "one seal only: " .. keysOf(gear))
  assert(gear[1].item == 271906 and gear[1].inv == 14, "the 53 seal over the passive charm: " .. gear[1].item .. " in " .. gear[1].inv)
  -- an empty slot before anything
  c.equipped[14] = nil
  c.A.Bar.Dirty("gear"); tick(c, 1)
  gear = shown(c, "gear")
  assert(gear[1].inv == 14 and gear[1].why:find("slot is empty", 1, true), "into the empty slot: " .. gear[1].why)
  -- its tooltip: an on-use trinket rule only for an on-use trinket
  c.items[271906].spell = 9998
  c.A.Bar.Dirty("gear"); tick(c, 1)
  gear = shown(c, "gear")
  c.A.Bar.Tip(icon(c, "own", gear[1].key), gear[1])
  assert(table.concat(c.env.GameTooltip.lines, " | "):find("on-use trinket", 1, true), "an on-use trinket: the 30 s rule")
  noErrors(c)
end)

test("biome gear: weapons as the game allows: no one-hander in the off hand without dual wield or over a shield; a two-hander's off hand kept", function()
  local me = member({ name = "Blade", class = "MAGE", level = 55 })
  local c = client({ me = me, zone = "Winterspring" })
  c.items[278223] = { name = "Snow Dagger", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2 }
  c.items[278224] = { name = "Yjn'raathma", equipLoc = "INVTYPE_WEAPON", classID = 2 }
  c.items[6000] = { name = "Plain Shield", equipLoc = "INVTYPE_SHIELD", classID = 4 }
  c.items[6001] = { name = "Plain Sword", equipLoc = "INVTYPE_WEAPON", classID = 2 }
  c.items[6002] = { name = "Plain Mace", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2 }
  c.equipped[16] = 278223
  c.bags = { { id = 278224, bag = 0, slot = 1 } }
  load(c)
  tick(c, 2)
  assert(#shown(c, "gear") == 0, "no dual wield: no one-hander for the off hand")
  c.dualWield = true; c.equipped[17] = 6000
  c.A.Bar.Dirty("gear"); tick(c, 1)
  assert(#shown(c, "gear") == 0, "never over a shield")
  c.equipped[17] = 6001
  c.A.Bar.Dirty("gear"); tick(c, 1)
  local r = shown(c, "gear")[1]
  assert(r and r.inv == 17, "over an off-hand weapon, for one who dual wields")
  -- a two-hander for here over a mace and a shield: a free bag slot for the shield, which comes back with "back"
  biomeItem(c, 990040, "Glacier Maul", "INVTYPE_2HWEAPON", "Snowy", { classID = 2 })
  c.equipped[16], c.equipped[17] = 6002, 6000
  c.freeSlots = 0
  bagsOf(c, { 990040 })
  tick(c, 1)
  assert(#shown(c, "gear") == 0, "no free bag slot for the shield: no swap")
  c.freeSlots = nil
  c.A.Bar.Dirty("gear"); tick(c, 1)
  r = shown(c, "gear")[1]
  assert(r and r.inv == 16 and r.old17 == 6000, "the maul, the shield noted")
  c.click(icon(c, "own", r.key))
  c.equipNow(990040, 16)
  tick(c, 2)
  local home = c.A.Char().gearHome
  assert(home[16] == 6002 and home[17] == 6000, "both kept for back: " .. tostring(home[16]) .. ", " .. tostring(home[17]))
  c.zone = "Elwynn Forest"; fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 2)
  local back = shown(c, "gear")[1]
  assert(back and back.kind == "back" and back.click.macro == "/equipslot 16 item:6002\n/equipslot 17 item:6000", "both back on: " .. tostring(back and back.click.macro))
  noErrors(c)
end)

test("biome gear: Water seen while you swim, with no event; Volcanic can't be told, its piece never swapped off", function()
  local me = member({ name = "Swimmer", class = "DRUID", level = 55 })
  local c = client({ me = me, zone = "Elwynn Forest" })
  c.items[19141] = { name = "Luffa", equipLoc = "INVTYPE_TRINKET", spell = 23595 }
  c.items[249470] = { name = "Molten Heart of the Mountain", equipLoc = "INVTYPE_TRINKET", spell = 1249113 }
  c.items[5000] = { name = "Plain Charm", equipLoc = "INVTYPE_TRINKET" }
  c.equipped[13], c.equipped[14] = 249470, 5000
  c.bags = { { id = 19141, bag = 0, slot = 1 } }
  load(c)
  tick(c, 5)
  assert(#shown(c, "gear") == 0, "dry: nothing")
  c.swimming = true
  tick(c, 2)
  local r = shown(c, "gear")[1]
  assert(r and r.item == 19141 and r.inv == 14, "swimming, no event: the Luffa, over the plain charm, never the Molten Heart")
  c.swimming = false
  tick(c, 2)
  assert(#shown(c, "gear") == 0, "ashore: gone")
  c.A.Window.Open("gear")
  local row
  for _, x in ipairs(c.A.Window.pages.gear.rows) do if x.id == 249470 and x:IsShown() then row = x end end
  assert(row and row.state.__text == "Can't tell", "Volcanic can't be told: " .. tostring(row and row.state.__text))
  FITS(row.state, "the state")
  noErrors(c)
end)

test("Biome gear tab: the bar's Never is the row's; can't-wear pieces say so; more than nine said; the defaults head the columns", function()
  local me = member({ name = "Tabby", class = "MAGE", level = 30 })
  local db = { settings = { never = { ["gear:back:249469"] = "Frozen Heart" } } }
  local c = client({ me = me, zone = "Winterspring", db = db })
  c.items[249469] = { name = "Frozen Heart of the Mountain", equipLoc = "INVTYPE_TRINKET", spell = 1249110 }
  biomeItem(c, 990030, "Frost Cloak", "INVTYPE_CLOAK", "Snowy")
  biomeItem(c, 990050, "Frost Mail", "INVTYPE_CHEST", "Snowy")
  c.tooltips[990050][3] = { leftText = "Mail", leftColor = { r = 1, g = 0.125, b = 0.125 } }
  biomeItem(c, 990051, "High Frost Ring", "INVTYPE_FINGER", "Snowy", { minLevel = 48 })
  c.items[5002] = { name = "Plain Cloak", equipLoc = "INVTYPE_CLOAK" }
  c.equipped[15] = 5002
  c.bags = { { id = 249469, bag = 0, slot = 1 }, { id = 990030, bag = 0, slot = 2 }, { id = 990050, bag = 0, slot = 3 }, { id = 990051, bag = 0, slot = 4 } }
  load(c)
  tick(c, 2)
  local G = c.A.Gear
  -- an old "back" icon's Never moved to the piece's one key
  assert(G.Never(249469) and db.settings.never["gear:back:249469"] == nil, "the old back Never is the piece's Never now")
  G.SetNever(249469, false)
  c.A.Bar.Dirty("gear"); tick(c, 1)
  -- Never from the bar's right-click
  local cloak = find(shown(c, "gear"), "gear:in:15")
  assert(cloak, "the cloak's swap: " .. keysOf(shown(c, "gear")))
  c.A.Bar.Menu(icon(c, "own", cloak.key))
  for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Never: Frost Cloak" then e.fn() end end
  tick(c, 1)
  assert(G.Never(990030) and not find(shown(c, "gear"), "gear:in:15"), "Never on the bar")
  c.A.Window.Open("gear")
  local page = c.A.Window.pages.gear
  local rowOf = function(id) for _, x in ipairs(page.rows) do if x.id == id and x:IsShown() then return x end end end
  local row = rowOf(990030)
  assert(row.ctx[1].__alpha == 0.4 and row.never.__alpha == 1, "the row shows the bar's Never: its contexts dimmed")
  c.click(row.never)
  tick(c, 1)
  assert(not G.Never(990030) and find(shown(c, "gear"), "gear:in:15"), "the row's Never clicked: back on the bar")
  -- pieces you can't wear: the reason, never "Works here"
  assert(rowOf(990050).state.__text == "Can't wear", "a mage and mail: " .. rowOf(990050).state.__text)
  assert(rowOf(990051).state.__text == "Level 48", "a ring for level 48: " .. rowOf(990051).state.__text)
  assert(rowOf(990030).state.__text == "Works here", "the cloak works here")
  -- worn first, then what you can wear, then what you can't
  assert(page.rows[1].id == 249469 or page.rows[1].id == 990030, "a wearable piece first")
  assert(page.rows[3].id == 990050 or page.rows[3].id == 990051, "the ones you can't wear last")
  -- the defaults sit over the rows' own toggles, 48 wide, inside the page, with a tooltip each
  for i, b in ipairs(page.defaultChips) do
    local x = b.__points[1][4]
    assert(b.__w == 48 and x == row.ctx[i].__points[1][4] and x + 48 <= 612, "the defaults' column " .. i)
  end
  assert(row.never.__points[1][4] + 48 <= 612, "Never inside the page")
  c.hover(page.defaultChips[3])
  assert(table.concat(c.env.GameTooltip.lines, " "):find("5-man dungeons", 1, true), "a tooltip on the defaults")
  c.hover(row.ctx[4])
  assert(table.concat(c.env.GameTooltip.lines, " "):find("raids", 1, true), "a tooltip on a row's toggle")
  c.click(page.defaultChips[4])
  assert(G.Settings().show.raid == false, "a default clicked")
  -- more than nine pieces: said
  local ids = { 249469, 990030, 990050, 990051 }
  for i = 1, 8 do biomeItem(c, 990100 + i, "Frost Band " .. i, "INVTYPE_WRIST", "Snowy"); ids[#ids + 1] = 990100 + i end
  bagsOf(c, ids)
  page:Sync()
  assert(page.more.__text == "And 3 more, not shown here.", page.more.__text)
  noErrors(c)
end)

test("the window: Move and Test step the window aside and bring it back; the bar's box is named; Done ends Move", function()
  local me = member({ name = "Mover", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 1)
  local Wn, win = c.A.Window, nil
  Wn.Open("settings")
  win = c.env.CuteAurasWindow
  local page = Wn.pages.settings
  local moveBtn = widget(page, "Move")
  assert(moveBtn and win:IsShown(), "the Move button on an open window")
  c.click(moveBtn)
  local bar, anchor = c.env.CuteAurasBar, c.env.CuteAurasAlerts
  assert(Wn.Moving() and not win:IsShown(), "moving: the window steps aside from the boxes it would cover")
  assert(anchor.box:IsShown() and bar.moveBox:IsShown(), "both pink boxes")
  assert(bar.moveLabel:IsShown() and bar.moveLabel.__text == "Cute Auras bar", "the bar's box is named as the alerts' is")
  assert(anchor.done and anchor.done:IsShown() and anchor.done.text.__text == "Done", "a Done on the alerts' box")
  -- (the Done sits in the box under its name, inside the box)
  local d = anchor.done.__points[1]
  assert(d[4] >= 0 and d[4] + anchor.done.__w <= 260 and d[5] - anchor.done.__h >= -64 and d[5] <= -26, "Done inside the box, under the name")
  c.click(anchor.done)
  assert(not Wn.Moving() and win:IsShown() and not anchor.done:IsShown() and not bar.moveBox:IsShown(), "Done: the boxes go, the window comes back")
  assert(moveBtn.text.__text == "Move", "the button says Move again")
  -- Move from the chat with the window closed: opening it meanwhile shows Done; ending it does not open it again
  win:Hide()
  c.env.SlashCmdList.CUTEAURAS("move")
  Wn.Open("settings")
  assert(moveBtn.text.__text == "Done", "while moving, the window's button says Done: " .. moveBtn.text.__text)
  c.click(moveBtn)
  assert(not Wn.Moving() and moveBtn.text.__text == "Move", "Done from the window")
  win:Hide()
  c.env.SlashCmdList.CUTEAURAS("move"); c.env.SlashCmdList.CUTEAURAS("move")
  assert(not win:IsShown(), "moved from the chat with the window closed: it stays closed")
  -- Test: the window steps aside for the cards' 15 s and comes back as they go
  Wn.Open("settings")
  c.click(widget(page, "Test"))
  assert(not win:IsShown() and c.A.Alerts.Has("test:rebuff"), "the test cards, the window aside")
  tick(c, 16)
  assert(win:IsShown() and not c.A.Alerts.Has("test:rebuff"), "the cards gone, the window back")
  -- alerts off: the chat line says so and the window stays
  c.A.Settings().alerts = false
  c.click(widget(page, "Test"))
  assert(win:IsShown(), "alerts off: nothing to show, the window stays")
  noErrors(c)
end)

test("the Settings tab: every box in the page, none over another, its words whole; /cauras minimap answers and the box follows", function()
  local me = member({ name = "Setter", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 1)
  c.A.Window.Open("settings")
  local page = c.A.Window.pages.settings
  local rects = {}
  for _, w in ipairs(page.widgets) do
    local pt = w.__points[1]
    local x, y = pt[4], pt[5]
    assert(x + w.__w <= 612 and y - w.__h >= -444, "inside the page: " .. tostring(w.label and w.label.__text))
    for _, r in ipairs(rects) do
      if r.x == x then assert(y - w.__h >= r.y or y <= r.y - r.h, "over another: " .. w.label.__text .. " and " .. r.text) end
    end
    rects[#rects + 1] = { x = x, y = y, h = w.__h, text = w.label.__text }
    if w.note then FITS(w.note, "a note") end
    if w.tick then assert(TEXT_WIDTH(w.label.__text, 12) <= w.__w - 22, "a check's words: " .. w.label.__text) end
    for _, b in ipairs(w.buttons or {}) do
      assert(TEXT_WIDTH(b.text.__text, 10) <= b.__w - 4, "a choice's option: " .. b.text.__text)
      assert(x + b.__points[1][4] + b.__w <= 612, "a choice's option past the page: " .. b.text.__text)
    end
  end
  -- every piece on the page (the boxes, the headings, the Nevers line, the buttons), with the Nevers line at its
  -- longest: inside the page, inside its column (left to 306, right from 312), none over another
  local function allFit(when)
    local boxes = {}
    for _, o in ipairs(page.__children) do
      local pt = o.__points[1]
      if pt and pt[2] == page and o.__shown then
        local x, y, w, h, what = pt[4], pt[5], o.__w, o.__h, nil
        if o.__kind == "FontString" then w, h, what = TEXT_WIDTH(o.__text, o.__size), o.__size + 2, o.__text
        else what = (o.label and o.label.__text) or (o.text and o.text.__text) or "?" end
        assert(w > 0 and h > 0, when .. ": a size: " .. what)
        assert(x >= 0 and x + w <= (x < 312 and 306 or 612) and y <= 0 and y - h >= -444, when .. ": inside its column and the page: " .. what)
        for _, r in ipairs(boxes) do
          assert(x >= r.x + r.w or r.x >= x + w or y - h >= r.y or r.y - r.h >= y, when .. ": " .. what .. " over " .. r.what)
        end
        boxes[#boxes + 1] = { x = x, y = y, w = w, h = h, what = what }
      end
    end
    return #boxes
  end
  local n0 = allFit("nothing hidden")
  -- (the consumables: one check and its note, where the four-way row was; what is asked where is the Consumables tab)
  local cons = widget(page, "Potions, elixirs, flasks and food")
  assert(cons and cons.tick and cons.__h == 34 and cons.note.__text == "What is asked where: the Consumables tab.", "the consumables' check and its note")
  assert(cons.__points[1][5] == -340 and cons.__points[1][5] - cons.__h > -390, "above the Nevers line")
  assert(widget(page, "Potions, elixirs, flasks and Well Fed") == nil and widget(page, "Instances") == nil, "the four-way row is gone")
  local never = c.A.Settings().never
  for i = 1, 32 do never["test:" .. i] = "Test " .. i end
  page:Sync()
  assert(page.nevers.__text == "32 of 32 hidden for good (right-click, Never)." and page.show:IsShown(), "the Nevers line at its longest")
  assert(allFit("32 hidden") == n0 + 1, "the Show them all button counted")
  for i = 1, 32 do never["test:" .. i] = nil end
  page:Sync()
  -- Buffs others give you: on by default, under Your buffs and weapon, indented, greyed while that part is off (it
  -- shows there); the camp's two boxes the same under the camp's
  local others, yours = widget(page, "Buffs others give you"), widget(page, "Your buffs and weapon")
  assert(others and others.tick:IsShown() and c.A.Settings().others ~= false, "on by default")
  assert(others.__points[1][4] == yours.__points[1][4] + 16 and others.__points[1][5] == yours.__points[1][5] - yours.__h, "indented under Your buffs and weapon")
  c.click(yours)
  assert(others.__alpha == 0.45, "Your buffs and weapon off: greyed")
  c.click(yours)
  assert(others.__alpha == 1, "back")
  local camp, feat, bp = widget(page, "Camp, food and sleeping bag"), widget(page, "Camp items at the fire near you"), widget(page, "Blueprints you can use")
  assert(feat.__points[1][4] == 16 and bp.__points[1][4] == 16 and feat.__points[1][5] == camp.__points[1][5] - camp.__h, "the camp's two under it, indented")
  c.click(camp)
  assert(feat.__alpha == 0.45 and bp.__alpha == 0.45 and others.__alpha == 1, "camp off: its two greyed")
  c.click(camp)
  assert(feat.__alpha == 1 and bp.__alpha == 1, "back")
  -- the minimap button under its own heading, not the group's
  local box = widget(page, "Button on the minimap")
  local heads = {}
  for _, o in ipairs(page.__children) do
    if o.__kind == "FontString" and (o.__text == "Group" or o.__text == "Minimap") then heads[o.__text] = o.__points[1][5] end
  end
  assert(box and heads.Minimap and box.__points[1][5] < heads.Minimap and heads.Minimap < heads.Group, "the minimap button under Minimap, past Group")
  for _, w in ipairs(page.widgets) do
    if w ~= box and w.__points[1][4] == box.__points[1][4] then assert(w.__points[1][5] > heads.Minimap, "nothing of the group's under Minimap") end
  end
  -- /cauras minimap: a reply, and the open page's box follows; a click then shows it again
  assert(box.tick:IsShown(), "ticked")
  c.chat = {}
  c.env.SlashCmdList.CUTEAURAS("minimap")
  assert(c.chat[1] and c.chat[1]:find("Minimap button hidden", 1, true), "the reply: " .. tostring(c.chat[1]))
  assert(not box.tick:IsShown() and not c.env.CuteAurasMinimapButton:IsShown(), "the box follows the command")
  c.click(box)
  assert(box.tick:IsShown() and c.env.CuteAurasMinimapButton:IsShown(), "a click shows it again, ticked")
  c.chat = {}
  c.env.SlashCmdList.CUTEAURAS("minimap"); c.env.SlashCmdList.CUTEAURAS("minimap")
  assert(c.chat[2]:find("Minimap button shown", 1, true), "shown: " .. tostring(c.chat[2]))
  -- the Biome gear tab's empty line: whole, on two lines at most
  c.A.Window.Open("gear")
  local gear = c.A.Window.pages.gear
  assert(gear.empty:IsShown(), "no biome pieces")
  FITS(gear.empty, "the empty line")
  noErrors(c)
end)

test("Never: past 32 hidden the menu says why and where; Settings counts them of 32", function()
  local never = {}
  for i = 1, 32 do never["gear:" .. (990000 + i)] = "Piece " .. i end
  local me = member({ name = "Hoarder", class = "PRIEST", level = 40 })
  local c = client({ me = me, db = { settings = { never = never } } })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 1)
  local rec = find(shown(c, "mine"), "self:innerfire")
  assert(rec, "Inner Fire on the bar")
  c.A.Bar.Menu(icon(c, "own", rec.key))
  c.chat = {}
  for _, e in ipairs(c.menus[#c.menus]) do if e.text:find("^Never: ") then assert(e.fn() == nil, "a menu callback answers nothing: the menu closes") end end
  tick(c, 1)
  assert(find(shown(c, "mine"), "self:innerfire"), "the list full: it stays")
  assert(c.chat[1] and c.chat[1]:find("32 hidden for good already", 1, true) and c.chat[1]:find("Show them all", 1, true), "said why: " .. tostring(c.chat[1]))
  c.A.Window.Open("settings")
  local page = c.A.Window.pages.settings
  assert(page.nevers.__text:find("^32 of 32 hidden"), "the count of 32: " .. page.nevers.__text)
  c.click(widget(page, "Show them all"))
  c.A.Bar.Menu(icon(c, "own", rec.key))
  for _, e in ipairs(c.menus[#c.menus]) do if e.text:find("^Never: ") then e.fn() end end
  tick(c, 1)
  assert(not find(shown(c, "mine"), "self:innerfire") and page.nevers.__text:find("^1 of 32"), "room made: Never works: " .. page.nevers.__text)
  noErrors(c)
end)

test("errors: a repeat counts up on its own line; kept over a /reload; the slash command, the boxes and the menus are caught too", function()
  local me = member({ name = "Buggy", class = "PRIEST", level = 40 })
  local c = client({ me = me, db = {} })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 1)
  local A = c.A
  -- an OnUpdate's error every frame for 30 frames, then another: two lines, the first counted
  local every = A.Safe(function() error("every frame") end, "clock")
  for _ = 1, 30 do every() end
  A.Safe(function() error("once") end, "other")()
  local kinds, times = A.ErrorCount()
  assert(kinds == 2 and times == 31 and A.errors[1].n == 30, "two kinds, 31 times: " .. kinds .. ", " .. times)
  c.chat = {}
  c.env.SlashCmdList.CUTEAURAS("errors")
  assert(c.chat[1]:find("every frame", 1, true) and c.chat[1]:find("(30 times)", 1, true), "said with its count: " .. c.chat[1])
  -- kept in the saved variables over a /reload
  local n = reload(c)
  load(n)
  tick(n, 1)
  assert(#n.A.errors == 2 and n.A.errors[1].n == 30, "kept over the reload: " .. #n.A.errors)
  assert(n.env.CuteAurasDB.errors == n.A.errors, "in CuteAurasDB")
  -- a new version starts clean
  n.env.CuteAurasDB.errors[1].v = "0.0.1"
  local n2 = reload(n)
  load(n2)
  assert(#n2.A.errors == 1 and n2.A.errors[1].msg:find("once", 1, true), "an old version's errors let go: " .. #n2.A.errors)
  n2.env.SlashCmdList.CUTEAURAS("errors clear")
  assert(#n2.A.errors == 0 and #n2.env.CuteAurasDB.errors == 0, "cleared")
  -- what runs outside the parts' own guards lands there too: the slash command, a Settings box, a menu entry
  local A2 = n2.A
  local refresh, update = A2.Bar.Refresh, A2.Minimap.Update
  A2.Bar.Refresh = function() error("refresh broke") end
  n2.env.SlashCmdList.CUTEAURAS("refresh")
  assert(#A2.errors == 1 and A2.errors[1].msg:find("^slash command: "), "the slash command: " .. tostring(A2.errors[1] and A2.errors[1].msg))
  A2.Minimap.Update = function() error("update broke") end
  A2.Window.Open("settings")
  n2.click(widget(A2.Window.pages.settings, "Button on the minimap"))
  assert(#A2.errors == 2 and A2.errors[2].msg:find("^window: Button on the minimap"), "a Settings box: " .. tostring(A2.errors[2] and A2.errors[2].msg))
  A2.Window.Open = function() error("open broke") end
  local mb = n2.env.CuteAurasMinimapButton
  mb.__scripts.OnClick(mb, "RightButton")
  for _, e in ipairs(n2.menus[#n2.menus]) do if e.text == "Settings" then assert(e.fn() == nil, "a menu entry answers nothing: the menu closes") end end
  assert(#A2.errors == 3 and A2.errors[3].msg:find("^minimap menu: Settings"), "a menu entry: " .. tostring(A2.errors[3] and A2.errors[3].msg))
  A2.Bar.Refresh, A2.Minimap.Update = refresh, update
  A2.ClearErrors()
  noErrors(n2)
end)

test("group icons: a member's name cut to fit (a prefix, no dots), whole in rec.word and the tooltip; verbs never cut; the wash on the icon whose list holds the member", function()
  local g = party5long()
  local c = g.c3
  tick(c, 2)
  local L = c.A.Look
  local list = {}
  for _, rec in ipairs(shown(c, "group")) do list[#list + 1] = icon(c, "group", rec.key) end
  assert(#list >= 2, "the paladin's blessings: " .. #list)
  local cut, clicks = 0, 0
  for i, b in ipairs(list) do
    local rec, text = b.rec, b.word.__text
    FITS(b.word, "a group icon's word")
    assert(TEXT_WIDTH(text, 11) <= 32, "at most 32 wide: " .. text)
    assert(b.caWord == rec.word, "the whole word kept on the icon: " .. tostring(b.caWord))
    if rec.class and rec.status == nil then
      -- (a name: its shown text a prefix of the whole, which the tooltip's Click line keeps)
      assert(rec.word:sub(1, #text) == text and #text > 0 and not text:find("%.%."), "a prefix of the name: " .. text .. " of " .. rec.word)
      if text ~= rec.word then cut = cut + 1 end
      -- (yours reads You, its Click line "buff yourself")
      if rec.clickWord and rec.word ~= "You" then
        local clickLine
        c.hover(b)
        for _, l in ipairs(c.env.GameTooltip.lines) do if l:find("^Click: ") then clickLine = l end end
        assert(clickLine and clickLine:find(rec.word, 1, true), "the Click line names them whole: " .. tostring(clickLine))
        clicks = clicks + 1
      end
    else
      assert(text == rec.word, "a verb whole: " .. text)
    end
    if i > 1 then
      local a = list[i - 1]
      local ax, bx = a.__points[1][4], b.__points[1][4]
      assert(ax + 16 + TEXT_WIDTH(a.word.__text, 11) / 2 + 4 <= bx + 16 - TEXT_WIDTH(text, 11) / 2, "a word under the next icon's: " .. a.word.__text .. " / " .. text)
    end
  end
  assert(cut >= 1 and clicks >= 1, "a twelve-letter name cut, a Click line read: " .. cut .. ", " .. clicks)
  -- the cut by the harness's widths: Bramb (31.7), Moon, Thund, Warde, Ysold (Ysolde is 33.9); short names, countdowns
  -- and verbs whole
  local fs = L.Text(c.env.UIParent, 11, L.C.INK, 36)
  for full, want in pairs({ Bramblewoode = "Bramb", Moonwhispers = "Moon", Thunderhoofe = "Thund", Wardenwallow = "Warde",
      Ysolde = "Ysold", Kit = "Kit", Anna = "Anna", You = "You", ["9:59"] = "9:59", ["59:59"] = "59:59", Done = "Done", Eat = "Eat",
      Far = "Far", ["All on"] = "All on", Buff = "Buff", Apply = "Apply" }) do
    assert(L.Fit(fs, full, L.ROOM) == want, full .. " reads " .. tostring(L.Fit(fs, full, L.ROOM)) .. ", not " .. want)
  end
  -- through the bar's paint: every word fitted, the whole kept on the icon and the record
  local b = L.Icon(nil, c.env.UIParent, false, true)
  for _, r in ipairs({ { word = "Bramblewoode", class = "ROGUE", want = "Bramb" }, { word = "You", class = "PRIEST", want = "You" },
      { word = "4:59", status = "warn", want = "4:59" }, { word = "Done", status = "good", want = "Done" }, { word = "Far", status = "warn", want = "Far" },
      { word = "All on", want = "All on" }, { word = "Eat", want = "Eat" } }) do
    r.lit = true
    L.Paint(b, r)
    assert(b.word.__text == r.want and b.caWord == r.word and r.word ~= nil, r.word .. " painted as " .. b.word.__text)
  end
  local grp = c.env.CuteAurasBarGroup
  local last = list[#list]
  assert(grp.__w >= last.__points[1][4] + 32, "the group's part as wide as its icons")
  -- the wash: a Hand's restore on the rogue lights the icon whose list holds the rogue, no other
  local rog, war = g.ROG.guid, g.WAR.guid
  local function holds(b, guid) for _, e in ipairs(b.rec and b.rec.flyout or {}) do if e.guid == guid then return true end end return false end
  local Hn = c.A.Hands
  fight(c, true)
  hand(c, g.ROG, 10278, 1)
  tick(c, 11)
  assert(Hn.Glowing(rog), "the rogue's restore")
  local lit = 0
  for _, b in ipairs(list) do
    assert(b.glowTex:IsShown() == holds(b, rog), "only the rogue's list's icon washes: " .. b.rec.key)
    if b.glowTex:IsShown() then lit = lit + 1 end
  end
  assert(lit == 1, "one icon lit: " .. lit)
  -- the warrior's too, then the warrior's done: the rogue's icon stays lit
  hand(c, g.WAR, 1044, 2)
  tick(c, 11)
  Hn.Done(war)
  for _, b in ipairs(list) do assert(b.glowTex:IsShown() == holds(b, rog), "the rogue's still pending: " .. b.rec.key) end
  fight(c, false)
  tick(c, 2)
  -- a hidden icon keeps no wash, and comes back with the wash that is true then
  c.A.Settings().group = false; c.A.Bar.Dirty("all"); tick(c, 1)
  for _, b in ipairs(list) do assert(not b:IsShown() and not b.glowTex:IsShown(), "hidden: no wash") end
  Hn.Done(rog)
  c.A.Settings().group = true; c.A.Bar.Dirty("all"); tick(c, 1)
  for _, b in ipairs(list) do if b:IsShown() then assert(not b.glowTex:IsShown(), "back with nothing pending: no wash") end end
  c.A.Settings().group = false; c.A.Bar.Dirty("all"); tick(c, 1)
  hand(c, g.ROG, 10278, 3)
  tick(c, 11)
  assert(Hn.Glowing(rog), "a restore while the part is off")
  c.A.Settings().group = true; c.A.Bar.Dirty("all"); tick(c, 1)
  local any = false
  for _, b in ipairs(list) do if b:IsShown() and holds(b, rog) then any = true; assert(b.glowTex:IsShown(), "back with the restore pending: washed") end end
  assert(any, "the rogue's icon back")
  noErrors(c)
end)

test("a group icon's list stays on the screen; its tooltip goes to the side with room, never over the names", function()
  local g = party5()
  local c = g.c1
  tick(c, 2)
  local b = icon(c, "group", "duty:fort")
  c.hover(b)
  local fly = c.env[b:GetName() .. "Fly"]
  local tt = c.env.GameTooltip
  assert(fly.__clamped, "the list is clamped to the screen")
  local function at() return tt.point[1], tt.point[2], tt.point[3] end
  -- room on the right (the screen 1600 wide, the tooltip 240): right of the list
  fly.__left, fly.__right = 400, 700
  c.hover(b)
  local p, rel, q = at()
  assert(p == "BOTTOMLEFT" and rel == fly and q == "BOTTOMRIGHT", "right of the list: " .. p)
  -- the list near the right edge: left of it
  fly.__left, fly.__right = 1000, 1590
  c.hover(b)
  p, rel, q = at()
  assert(p == "BOTTOMRIGHT" and rel == fly and q == "BOTTOMLEFT", "left of the list: " .. p)
  -- a list across the screen: above it
  fly.__left, fly.__right = 100, 1500
  c.hover(b)
  p, rel, q = at()
  assert(p == "BOTTOM" and rel == fly and q == "TOP", "above the list: " .. p)
  -- the bar at twice the size: the room counted in the screen's units
  c.env.CuteAurasBar.__scale = 2; fly.__scale = 2
  fly.__left, fly.__right = 300, 700
  c.hover(b)
  p = at()
  assert(p == "BOTTOMRIGHT", "at scale 2 the list's right edge is 1400: left of it: " .. p)
  noErrors(c)
end)

----------------------------------------------------------------------------
-- the reviewers' regressions after the 61-finding round (2026-11-23)
----------------------------------------------------------------------------
local function tokenOf(c, m) for k, v in pairs(c.units) do if v == m and k ~= "player" and k ~= "target" then return k end end end

test("rebuff: a member still dead when the slots are made again, raised in the next fight, is queued", function()
  local g = party5()
  local c = g.c1
  local rb = c.env.CuteAurasRebuff
  fight(c, true); fight(g.c2, true)
  g.ROG.dead = true
  tickAll(1)
  -- the fight ends with the rogue on the floor: the slots are made again out of the fight
  fight(c, false); fight(g.c2, false)
  tickAll(2)
  c.A.Rebuff.Update(); tickAll(1)
  assert(not rb:IsShown(), "dead out of a fight: no card")
  -- the next pull: a druid's battle res
  fight(c, true); fight(g.c2, true)
  tickAll(1)
  g.ROG.dead = false
  tickAll(1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.ROG, "raised in the next fight: the rogue's card")
  fight(c, false); fight(g.c2, false)
  tickAll(2)
  for _, x in ipairs({ g.c1, g.c2, g.c3 }) do noErrors(x, "dead across fights") end
end)

test("biome gear: old Never keys move to one key a piece, thirty at once, the flag set only when done", function()
  local me = member({ name = "Mover", class = "MAGE", level = 60 })
  local never = { ["duty:fort"] = "Fortitude" }
  for i = 1, 30 do never["gear:back:" .. (20000 + i)] = "Piece " .. i end
  local db = { settings = { never = never } }
  local c = client({ me = me, db = db })
  load(c)
  tick(c, 1)
  local G = c.A.Gear
  G.Settings()
  for i = 1, 30 do
    assert(never["gear:back:" .. (20000 + i)] == nil and never["gear:" .. (20000 + i)] == "Piece " .. i, "piece " .. i .. " moved")
  end
  assert(never["duty:fort"] == "Fortitude", "another key untouched")
  assert(db.settings.gear.neverOne == true, "the move marked done")
  noErrors(c)
end)

test("a saved group is read back only into the same group, never a next one sharing a paladin", function()
  local P = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-S1" })
  local Q = member({ name = "Bpal", class = "PALADIN", level = 60, guid = "Player-1-S2" })
  local W = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-S3", assigned = "TANK" })
  local R = member({ name = "Drog", class = "ROGUE", level = 60, guid = "Player-1-S4" })
  local groupA = { P, Q, W, R }
  local c1 = client({ me = P, group = groupA, spec = 184 })
  local c2 = client({ me = Q, group = groupA, spec = 184 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "PALADIN", 60)
  load(c1); load(c2)
  tickAll(12)
  c1.A.Assign.Set(P.guid, "WARRIOR:tank", "might")
  tickAll(3)
  assert(c1.A.Comm.peers[Q.guid], "Q heard in group A")
  -- P logs out in group A and in again in group B: Q and three strangers
  fire(c1, "PLAYER_LOGOUT")
  WORLD = {}
  local X1 = member({ name = "Xmag", class = "MAGE", level = 60, guid = "Player-1-S5" })
  local X2 = member({ name = "Xpri", class = "PRIEST", level = 60, guid = "Player-1-S6" })
  local X3 = member({ name = "Xwar", class = "WARRIOR", level = 60, guid = "Player-1-S7", assigned = "TANK" })
  local n = client({ me = P, group = { P, Q, X1, X2, X3 }, spec = 184, db = c1.env.CuteAurasDB })
  n.clock = c1.clock
  knowAll(n, "PALADIN", 60)
  load(n)
  assert(n.A.Comm.peers[Q.guid] == nil, "Q's hello from group A not read back into group B")
  assert(next(n.A.Assign.overrides) == nil, "group A's hand-set blessings not read back")
  -- the same group again: read back (a /reload)
  fire(n, "PLAYER_LOGOUT")
  WORLD = {}
  local m = client({ me = P, group = { P, Q, X1, X2, X3 }, spec = 184, db = n.env.CuteAurasDB })
  m.clock = n.clock
  knowAll(m, "PALADIN", 60)
  load(m)
  noErrors(n); noErrors(m)
end)

test("the bar holds still as a group icon's name changes: its width and every icon's x the same, click boxes 32 x 32, the list 166 wide with whole names", function()
  local P = member({ name = "Al", class = "PRIEST", level = 50, guid = "Player-1-W1", assigned = "HEALER" })
  local A1 = member({ name = "Bo", class = "WARRIOR", level = 50, guid = "Player-1-W2", assigned = "TANK" })
  local A2 = member({ name = "Christophe", class = "ROGUE", level = 50, guid = "Player-1-W3" })
  local A3 = member({ name = "Di", class = "MAGE", level = 50, guid = "Player-1-W4" })
  local A4 = member({ name = "Ed", class = "WARRIOR", level = 50, guid = "Player-1-W5" })
  local group = { P, A1, A2, A3, A4 }
  local c = client({ me = P, group = group, spec = 56 })
  knowAll(c, "PRIEST", 50)
  load(c)
  tick(c, 12)
  -- (yours first: the list then walks the others' names)
  P.auras[#P.auras + 1] = { id = 10937, src = "player", exp = c.clock + 1800, dur = 1800 }
  fire(c, "UNIT_AURA", "player")
  tick(c, 4)
  local bar, grp = c.env.CuteAurasBar, c.env.CuteAurasBarGroup
  local b = icon(c, "group", "duty:fort")
  assert(b and b:IsShown(), "the Fortitude icon")
  -- (every shown icon's x, by its key)
  local function xs()
    local t = {}
    for _, part in ipairs({ "camp", "mine", "pull", "gear" }) do for _, rec in ipairs(shown(c, part)) do t[rec.key] = icon(c, "own", rec.key).__points[1][4] end end
    for _, rec in ipairs(shown(c, "group")) do t[rec.key] = grp.__points[1][4] .. "+" .. icon(c, "group", rec.key).__points[1][4] end
    return t
  end
  local width, at = bar.__w, xs()
  local seen, steps = {}, 0
  for _ = 1, 6 do
    if not b:IsShown() then break end
    -- (the record keeps the whole name; the icon shows it cut to fit)
    local word = b.rec.word
    if word == "You" or seen[word] then break end
    seen[word] = true
    steps = steps + 1
    assert(bar.__w == width, "the bar holds still under '" .. word .. "': " .. bar.__w .. " / " .. width)
    local now = xs()
    for k, x in pairs(at) do assert(now[k] == x, "'" .. k .. "' holds still under '" .. word .. "': " .. tostring(now[k]) .. " / " .. x) end
    assert(b.__w == 32 and b.__h == 32 and b.word.__w == 36, "a 32 x 32 click box, its word's box 36: " .. b.__w .. " x " .. b.__h)
    assert(TEXT_WIDTH(b.word.__text, 11) <= 32 and word:sub(1, #b.word.__text) == b.word.__text, "the name cut to fit: " .. b.word.__text)
    -- the list: one column 166 wide, every name in it whole
    local fly = c.env[b:GetName() .. "Fly"]
    assert(fly and fly.__w == 166, "the list 166 wide: " .. tostring(fly and fly.__w))
    for _, m in ipairs(group) do
      if m ~= P then
        local whole = false
        for _, r in ipairs(fly.rows) do if r:IsShown() and r.name.__text == m.name then whole = true; FITS(r.name, "a name in the list") end end
        assert(whole, "whole in the list: " .. m.name)
      end
    end
    -- the one named gets it
    for _, m in ipairs(group) do
      if m.name == word then
        m.auras[#m.auras + 1] = { id = 10937, src = "player", exp = c.clock + 1800, dur = 1800 }
        fire(c, "UNIT_AURA", tokenOf(c, m))
      end
    end
    tick(c, 4)
  end
  assert(steps >= 3 and seen.Christophe, "three names shown one after another, Christophe among them: " .. steps)
  noErrors(c)
end)

test("the Blessings tab says why your column is gone; consumables Off greys Before the pull; Small cards are smaller", function()
  local P = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-V1" })
  local Q = member({ name = "Bpal", class = "PALADIN", level = 60, guid = "Player-1-V2" })
  local W = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-V3", assigned = "TANK" })
  local group = { P, Q, W }
  local c1 = client({ me = P, group = group, spec = 184 })
  local c2 = client({ me = Q, group = group, spec = 184 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "PALADIN", 60)
  load(c1); load(c2)
  tickAll(12)
  local c = c1
  c.A.Window.Open("settings")
  local page = c.A.Window.pages.settings
  c.click(widget(page, "Buffs you give the group"))
  tickAll(3)
  c.A.Window.Open("blessings")
  local bp = c.A.Window.pages.blessings
  FITS(bp.title, "the Blessings tab's title")
  assert(bp.title.__text:find("You give no blessings now: Buffs you give the group is off", 1, true), bp.title.__text)
  c.A.Window.Open("settings")
  c.click(widget(page, "Buffs you give the group"))
  tickAll(3)
  c.A.Window.Open("blessings")
  assert(not bp.title.__text:find("You give no", 1, true), "back: " .. bp.title.__text)
  -- every blessing on Never
  for _, k in ipairs({ "kings", "might", "wisdom" }) do c.A.Bar.SetNever("duty:bless:" .. k, k, true) end
  tickAll(2)
  bp:Sync()
  assert(bp.title.__text:find("every blessing you know is on Never", 1, true), bp.title.__text)
  -- consumables Off: Before the pull greyed and saying so; the row back with it
  c.A.Window.Open("settings")
  local pull = widget(page, "Before the pull (ready check)")
  local consume = widget(page, "Potions, elixirs, flasks and food")
  c.click(consume)
  assert(c.A.Consume.Settings().on == false and not consume.tick:IsShown(), "consumables off")
  assert(pull.__alpha == 0.45 and pull.label.__text == "Before the pull: consumables Off", "greyed: " .. pull.label.__text)
  assert(TEXT_WIDTH(pull.label.__text, 12) <= pull.__w - 22, "its words fit")
  c.click(consume)
  assert(pull.__alpha == 1 and pull.label.__text == "Before the pull (ready check)", "back")
  -- the consumables row greyed only with your buffs and Before the pull both off
  c.click(widget(page, "Your buffs and weapon"))
  assert(consume.__alpha == 1, "Before the pull still shows them")
  c.click(pull)
  assert(consume.__alpha == 0.45, "both off: greyed")
  c.click(pull); c.click(widget(page, "Your buffs and weapon"))
  -- the Hands note follows the bar: no group list in a fight, nothing at all
  c.click(widget(page, "Alerts on screen"))
  local hands = widget(page, "Protection, Freedom and Sacrifice")
  assert(hands.note.__text:find("row in the bar glows", 1, true), hands.note.__text)
  for _, x in ipairs(widget(page, "In a fight").buttons) do if x.text.__text == "Hide the bar" then c.click(x) end end
  assert(hands.note.__text == "Alerts off and no group list in a fight: nothing.", hands.note.__text)
  FITS(hands.note, "the Hands note")
  c.click(widget(page, "Alerts on screen"))
  -- Small cards: smaller words and a shorter card than Normal, the words still whole
  local Al = c.A.Alerts
  c.A.Settings().alertLook = "normal"
  local hN = Al.CardHeight()
  c.A.Settings().alertLook = "small"
  local hS = Al.CardHeight()
  assert(hS < hN, "Small shorter: " .. hS .. " / " .. hN)
  local t, x = Al.Fonts()
  assert(t < 14 and x < 11, "Small's words smaller")
  Al.Restyle()
  noErrors(c1); noErrors(c2)
end)

test("Biome gear tab: Never's tooltip says what a click does; the dimmed toggles wait; a full Never list says so", function()
  local me = member({ name = "Tabby", class = "MAGE", level = 30 })
  local c = client({ me = me, zone = "Winterspring" })
  biomeItem(c, 990030, "Frost Cloak", "INVTYPE_CLOAK", "Snowy")
  c.items[5002] = { name = "Plain Cloak", equipLoc = "INVTYPE_CLOAK" }
  c.equipped[15] = 5002
  c.bags = { { id = 990030, bag = 0, slot = 2 } }
  load(c)
  tick(c, 2)
  local G = c.A.Gear
  c.A.Window.Open("gear")
  local page = c.A.Window.pages.gear
  local row
  for _, x in ipairs(page.rows) do if x.id == 990030 and x:IsShown() then row = x end end
  assert(row, "the cloak's row")
  local function tip(b) c.hover(b); return table.concat(c.env.GameTooltip.lines, " ") end
  assert(tip(row.never):find("never show on the bar, wherever", 1, true), "off: what a click does: " .. tip(row.never))
  G.SetShow(990030, "raid", false)
  c.click(row.never)
  assert(G.Never(990030), "Never on")
  assert(tip(row.never):find("show them again", 1, true), "on: " .. tip(row.never))
  assert(tip(row.ctx[1]):find("click Never", 1, true), "a dimmed toggle says why: " .. tip(row.ctx[1]))
  c.click(row.ctx[4])
  c.click(row.never)
  assert(not G.Never(990030) and G.ShowsIn(990030, "raid") == false, "the raid choice kept under Never")
  -- the bar's Nevers full: the click says so
  for i = 1, c.A.Bar.NEVER_MAX do c.A.Settings().never["x:" .. i] = "x" end
  c.chat = {}
  c.click(row.never)
  assert(not G.Never(990030) and c.chat[1] and c.chat[1]:find("hidden for good already", 1, true), "full: " .. tostring(c.chat[1]))
  -- the minimap menu's Test steps the window aside, as Settings' Test does
  c.A.Window.Open("settings")
  c.click(c.env.CuteAurasMinimapButton, "RightButton")
  for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Test the alerts" then e.fn() end end
  assert(not c.env.CuteAurasWindow:IsShown() and c.A.Alerts.Has("test:hand"), "the window aside while the test cards show")
  tick(c, 16)
  assert(c.env.CuteAurasWindow:IsShown(), "and back after")
  noErrors(c)
end)

----------------------------------------------------------------------------
-- lower ranks (the owner, 2026-11-23: "lower rank buff than ideal for your lvl"): a member's buff at less power than
-- the rank you give them counts as missing; your own at a lower rank than you know asks for an Upgrade
----------------------------------------------------------------------------
-- a priest at 60 who gives Fortitude to a rogue (a twelve-letter name, the widest the tests have) and a warrior; the
-- rogue carries rank 4 from a priest of level 40, gone since
local function lowParty()
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-L1" })
  local R = member({ name = "Wolfwardenmw", class = "ROGUE", level = 60, guid = "Player-1-L2" })
  local W = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-L3", assigned = "TANK" })
  local c = client({ me = P, group = { P, R, W }, spec = 56 })
  knowAll(c, "PRIEST", 60)
  local function fort(id, src) return { id = id, src = src, exp = c.clock + 3000, dur = 3600 } end
  P.auras, W.auras, R.auras = { fort(10938, "player") }, { fort(10938, "player") }, { fort(2791, nil) }
  load(c)
  tick(c, 12)
  return c, R, fort
end
local function rowOf(fly, name) for _, r in ipairs(fly.rows) do if r:IsShown() and r.name.__text == name then return r end end end

test("low rank: Fortitude 4 on a level 60 rogue is named, Low rank in its row, a click gives rank 6; Prayer 2 is fine; a hidden id never low", function()
  local c, R, fort = lowParty()
  local tok = tokenOf(c, R)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 1 and rec.word == R.name and rec.class == "ROGUE" and rec.status == nil and rec.lit,
    "the rogue named, as for a missing buff: " .. tostring(rec and rec.word))
  local b = icon(c, "group", "duty:fort")
  assert(b:GetAttribute("spell") == 10938 and b:GetAttribute("unit") == tok, "the icon gives rank 6 to the rogue: " .. tostring(b:GetAttribute("spell")))
  c.casts = {}
  c.click(b)
  assert(c.casts[1] and c.casts[1].spell == 10938 and c.casts[1].unit == tok, "its click casts 10938 on them")
  assert(rec.why:find("^Rank 4 on them; you give rank 6%."), "the tooltip's ranks: " .. rec.why)
  c.hover(b)
  assert(table.concat(c.env.GameTooltip.lines, " "):find("Rank 4 on them; you give rank 6.", 1, true), "said on hover")
  -- the list: the rogue first, as a missing one; Low rank in the warning colour, the icon not greyed; its click rank 6
  local fly = c.env[b:GetName() .. "Fly"]
  local row = rowOf(fly, R.name)
  assert(row and row == fly.rows[1] and row.state.__text == "Low rank", "Low rank, first: " .. tostring(row and row.state.__text))
  local warn = c.A.Look.C.WARN
  assert(row.state.__textColor[1] == warn[1] and row.state.__textColor[3] == warn[3] and row.icon.__desat == false, "the warning colour, not greyed")
  assert(rowOf(fly, "Cwar").state.__text == "on" and rowOf(fly, "Cwar").icon.__desat == true, "the warrior's rank 6: on, greyed")
  FITS(row.state, "Low rank"); FITS(row.name, "a twelve-letter name")
  -- (side by side, their boxes apart: the name's from the icon's right (4 + 16 + 6), the state's to 4 from the row's
  -- right; any name that fits its box clear of any state)
  assert(26 + row.name.__w <= row.__w - 4 - row.state.__w,
    string.format("the name's box (26 to %d) runs into the state's (%d to %d)", 26 + row.name.__w, row.__w - 4 - row.state.__w, row.__w - 4))
  c.casts = {}
  c.click(row)
  assert(c.casts[1] and c.casts[1].spell == 10938 and c.casts[1].unit == tok, "the row's click casts 10938 on them")
  -- the share-out as it was: the rogue is still yours, no new computation
  local gen = c.A.Assign.gen
  assert(#dutyOf(c, "fort").targets == 3, "Fortitude to all three")
  -- Prayer of Fortitude 2 on them, as strong as rank 6: fine; Prayer 1 at level 60: low, named so
  R.auras = { fort(21564, nil) }
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  assert(not find(shown(c, "group"), "duty:fort"), "Prayer of Fortitude 2: fine")
  R.auras = { fort(21562, nil) }
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.word == R.name and rec.why:find("^Prayer of Fortitude rank 1 on them; you give rank 6%."), "Prayer 1 at 60: low: " .. tostring(rec and rec.why))
  -- rank 4 whose spell id the client hides: on by its name, never low
  R.auras = { { id = 2791, secretId = true, exp = c.clock + 3000, dur = 3600 } }
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  assert(not find(shown(c, "group"), "duty:fort"), "a hidden spell id: on, never low")
  -- rank 4 within five minutes of its end: Low rank still, named, no countdown (a click replaces it all the same)
  R.auras = { { id = 2791, exp = c.clock + 200, dur = 3600 } }
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.word == R.name and rec.status == nil and not rec.timed and rowOf(fly, R.name).state.__text == "Low rank",
    "low rank and ending: " .. tostring(rec and rec.word))
  assert(c.A.Assign.gen == gen, "the share-out never moved for a rank")
  noErrors(c)
end)

test("low rank in a fight: nothing changes, the row still gives rank 6; the bar looks again after it", function()
  local c, R, fort = lowParty()
  local tok = tokenOf(c, R)
  local b = icon(c, "group", "duty:fort")
  local fly = c.env[b:GetName() .. "Fly"]
  local row = rowOf(fly, R.name)
  assert(row and row.state.__text == "Low rank", "out of a fight: Low rank")
  fight(c, true)
  tick(c, 1)
  -- (another priest gives them rank 6 mid-fight: the client hides the auras, the bar holds still)
  R.auras = { fort(10938, nil) }
  fire(c, "UNIT_AURA", tok); tick(c, 4)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.word == R.name and b:IsShown() and row.state.__text == "Low rank" and b:GetAttribute("spell") == 10938, "in a fight: as it was")
  c.casts = {}
  c.hover(b)
  c.click(row)
  assert(c.casts[1] and c.casts[1].spell == 10938 and c.casts[1].unit == tok, "the row's click in a fight: rank 6 on them")
  fight(c, false)
  tick(c, 3)
  assert(not find(shown(c, "group"), "duty:fort"), "after the fight: rank 6 on them, nothing owed")
  noErrors(c)
end)

test("low rank blessings: Might 5 on the warrior you give Might is low while you know 7; a Greater Might as strong is fine", function()
  local PAL = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-N1" })
  local WAR = member({ name = "Bwar", class = "WARRIOR", level = 60, guid = "Player-1-N2" })
  local c = client({ me = PAL, group = { PAL, WAR }, spec = 184 })
  knowAll(c, "PALADIN", 60)
  local function aura(id, src) return { id = id, src = src, exp = c.clock + 3000, dur = 3600 } end
  -- (Might 5 from another paladin, gone since)
  PAL.auras, WAR.auras = { aura(25291, "player") }, { aura(19837, nil) }
  load(c)
  tick(c, 12)
  assert(c.A.Assign.BlessingOf(PAL.guid, "WARRIOR:melee") == "might", "you give the warrior Might")
  local tok = tokenOf(c, WAR)
  local rec = find(shown(c, "group"), "duty:bless:might")
  assert(rec and rec.count == 1 and rec.word == WAR.name, "the warrior named: " .. tostring(rec and rec.word))
  assert(rec.why:find("^Rank 5 on them; you give rank 7%."), rec.why)
  local b = icon(c, "group", "duty:bless:might")
  assert(b:GetAttribute("spell") == 25291 and b:GetAttribute("unit") == tok, "the click gives Might 7: " .. tostring(b:GetAttribute("spell")))
  local row = rowOf(c.env[b:GetName() .. "Fly"], WAR.name)
  assert(row and row.state.__text == "Low rank" and row:GetAttribute("spell") == 25291, "Low rank in the list, its click Might 7")
  local gen = c.A.Assign.gen
  -- Greater Blessing of Might 2 (133 attack power, as rank 7): fine, all on; Greater 1 (112): low
  WAR.auras = { aura(25916, nil) }
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  rec = find(shown(c, "group"), "duty:bless:might")
  assert(rec and rec.word == "All on" and rec.count == nil, "Greater Might 2: fine: " .. tostring(rec and rec.word))
  WAR.auras = { aura(25782, nil) }
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  rec = find(shown(c, "group"), "duty:bless:might")
  assert(rec and rec.word == WAR.name and rec.why:find("^Greater Blessing of Might rank 1 on them; you give rank 7%."), "Greater 1: low: " .. tostring(rec and rec.why))
  assert(c.A.Assign.gen == gen and c.A.Assign.BlessingOf(PAL.guid, "WARRIOR:melee") == "might", "the share-out as it was")
  noErrors(c)
end)

test("low rank: the group version never weaker than the single rank: Holy Candles alone, or Prayer 2 not trained, give Fortitude 6 one by one until the icon clears; Greater Might 1 under Might 7 too", function()
  -- a level 60 priest, four level 60s without Fortitude, Holy Candles alone (Prayer of Fortitude 2 takes a Sacred Candle)
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-V1" })
  local list = { P }
  for i = 2, 5 do list[i] = member({ name = "V" .. i, class = i % 2 == 0 and "WARRIOR" or "ROGUE", level = 60, guid = "Player-1-V" .. i }) end
  local c = client({ me = P, group = list, spec = 56 })
  knowAll(c, "PRIEST", 60)
  local function fort(id, src) return { id = id, src = src, exp = c.clock + 3000, dur = 3600 } end
  c.items[17028], c.items[17029] = { name = "Holy Candle" }, { name = "Sacred Candle" }
  c.bags = { { id = 17028, bag = 0, slot = 1, count = 20 } }
  P.auras = { fort(10938, "player") }
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 4 and b:GetAttribute("spell") == 10938,
    "Holy Candles alone: Fortitude 6, never Prayer 1 (56 Stamina under 70): " .. tostring(b and b:GetAttribute("spell")))
  -- (Prayer 1 on all four from before: each a lower rank, each given Fortitude 6, one click each, and the icon clears)
  for i = 2, 5 do list[i].auras = { fort(21562, nil) } end
  for u in pairs(c.units) do fire(c, "UNIT_AURA", u) end
  tick(c, 2)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 4 and rec.why:find("^Prayer of Fortitude rank 1 on them; you give rank 6%.") and rec.clickWord == "buff " .. rec.word,
    "Prayer 1 on them: low, a click buffs one: " .. tostring(rec and rec.why))
  for n = 1, 4 do
    c.casts = {}
    c.click(b)
    local cast = c.casts[1]
    assert(cast and cast.spell == 10938, "click " .. n .. ": Fortitude 6, never Prayer 1 again: " .. tostring(cast and cast.spell))
    c.units[cast.unit].auras = { fort(10938, "player") }
    fire(c, "UNIT_AURA", cast.unit); tick(c, 2)
  end
  assert(not find(shown(c, "group"), "duty:fort"), "four clicks, all at rank 6: the icon gone")
  -- Sacred Candles: Prayer of Fortitude 2, as strong as rank 6, for the four with Prayer 1 again
  for i = 2, 5 do list[i].auras = { fort(21562, nil) } end
  c.bags[2] = { id = 17029, bag = 0, slot = 2, count = 5 }
  fire(c, "BAG_UPDATE_DELAYED")
  for u in pairs(c.units) do fire(c, "UNIT_AURA", u) end
  tick(c, 2)
  assert(b:GetAttribute("spell") == 21564, "a Sacred Candle: Prayer of Fortitude 2: " .. tostring(b:GetAttribute("spell")))
  -- Prayer 2 not trained (a book): Fortitude 6 again, candles or not
  c.known[21564] = nil
  fire(c, "SPELLS_CHANGED"); tick(c, 2)
  assert(b:GetAttribute("spell") == 10938, "Prayer 1 the only one known: Fortitude 6: " .. tostring(b:GetAttribute("spell")))
  noErrors(c)
  -- a paladin who knows Might 7 (133) and Greater Might 1 (112) alone, three warriors: Might 7, one at a time
  local PAL = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-V6" })
  local ws = { PAL }
  for i = 2, 4 do ws[i] = member({ name = "W" .. i, class = "WARRIOR", level = 60, guid = "Player-1-V" .. (5 + i) }) end
  local d = client({ me = PAL, group = ws, spec = 184 })
  knowAll(d, "PALADIN", 60)
  d.known[25782], d.known[25916] = true, true
  d.items[21177] = { name = "Symbol of Kings" }
  d.bags = { { id = 21177, bag = 0, slot = 1, count = 20 } }
  PAL.auras = { { id = 25291, src = "player", exp = d.clock + 3000, dur = 3600 } }
  load(d)
  tick(d, 12)
  local pb = icon(d, "group", "duty:bless:might")
  assert(pb and pb:GetAttribute("spell") == 25916, "Greater Might 2 known: the three warriors' Greater: " .. tostring(pb and pb:GetAttribute("spell")))
  d.known[25916] = nil
  fire(d, "SPELLS_CHANGED"); tick(d, 2)
  assert(pb:GetAttribute("spell") == 25291, "Greater Might 1 alone, 112 under 133: Might 7: " .. tostring(pb:GetAttribute("spell")))
  for i = 2, 4 do ws[i].auras = { { id = 25782, exp = d.clock + 3000, dur = 3600 } } end
  for u in pairs(d.units) do fire(d, "UNIT_AURA", u) end
  tick(d, 2)
  local prec = find(shown(d, "group"), "duty:bless:might")
  assert(prec and prec.count == 3 and pb:GetAttribute("spell") == 25291, "Greater Might 1 on them: low, Might 7 on one, never Greater 1 again")
  noErrors(d)
end)

test("low rank: a party of mixed levels: the group version for those it gives full power, on one of them (Prayer 2 on a 60, then Fortitude 5 on the 45; Greater Might 2 the same); three 45s still get Prayer 1", function()
  -- a level 60 priest (Fortitude on already), a level 45 listed first, then three level 60s, none with Fortitude
  local function party(levels, bags, known)
    local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-Q1" })
    local list = { P }
    for i, lv in ipairs(levels) do list[i + 1] = member({ name = "Q" .. i .. "x" .. lv, class = "WARRIOR", level = lv, guid = "Player-1-Q" .. (i + 1) }) end
    local c = client({ me = P, group = list, spec = 56 })
    knowAll(c, "PRIEST", 60)
    for id, v in pairs(known or {}) do c.known[id] = v or nil end
    c.items[17028], c.items[17029] = { name = "Holy Candle" }, { name = "Sacred Candle" }
    c.bags = bags
    P.auras = { { id = 10938, src = "player", exp = c.clock + 3000, dur = 3600 } }
    load(c)
    tick(c, 12)
    return c, list
  end
  local HOLY, SACRED = { id = 17028, bag = 0, slot = 1, count = 20 }, { id = 17029, bag = 0, slot = 2, count = 20 }
  local function clickOf(c)
    c.casts = {}
    c.click(icon(c, "group", "duty:fort"))
    local cast = c.casts[1]
    return cast and cast.spell, cast and c.units[cast.unit]
  end
  local function land(c, who, id)
    for _, m in ipairs(who) do m.auras = { { id = id, exp = c.clock + 3000, dur = 3600 } } end
    for u in pairs(c.units) do fire(c, "UNIT_AURA", u) end
    tick(c, 2)
  end
  -- both candles: Prayer 2 on a 60 (the 45 is too low for it), then Fortitude 5 on the 45
  local c, list = party({ 45, 60, 60, 60 }, { HOLY, SACRED })
  local spell, at = clickOf(c)
  assert(spell == 21564 and at and at.level == 60, "Prayer of Fortitude 2 on a 60, never Prayer 1 on the 45: " .. tostring(spell) .. " on " .. tostring(at and at.name))
  land(c, { list[3], list[4], list[5] }, 21564)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 1 and rec.word == list[2].name, "the 45 left: " .. tostring(rec and rec.word))
  spell, at = clickOf(c)
  assert(spell == 10937 and at == list[2], "then Fortitude 5 on the 45: " .. tostring(spell))
  noErrors(c)
  -- Prayer 1 the only group rank known, Holy Candles: Prayer 1 would be low on the three 60s: one at a time, the 45 first
  c, list = party({ 45, 60, 60, 60 }, { HOLY }, { [21564] = false })
  spell, at = clickOf(c)
  assert(spell == 10937 and at == list[2], "Fortitude 5 on the 45, never Prayer 1: " .. tostring(spell))
  noErrors(c)
  -- three 45s and a 60, Holy Candles: Prayer 1 serves the three; on all four, the 60 alone is low after
  c, list = party({ 45, 45, 45, 60 }, { HOLY })
  spell, at = clickOf(c)
  assert(spell == 21562 and at and at.level == 45, "Prayer of Fortitude 1 on a 45: " .. tostring(spell) .. " on " .. tostring(at and at.name))
  land(c, { list[2], list[3], list[4], list[5] }, 21562)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 1 and rec.word == list[5].name and rec.why:find("^Prayer of Fortitude rank 1 on them; you give rank 6%."),
    "the 60 alone low: " .. tostring(rec and rec.word) .. " " .. tostring(rec and rec.why))
  noErrors(c)
  -- a paladin giving warriors Might: a 45 first, three 60s: Greater Might 2 on a 60, never Greater 1 on the 45
  local PAL = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-Q6" })
  local ws = { PAL, member({ name = "R45", class = "WARRIOR", level = 45, guid = "Player-1-Q7" }) }
  for i = 3, 5 do ws[i] = member({ name = "R" .. i, class = "WARRIOR", level = 60, guid = "Player-1-Q" .. (5 + i) }) end
  local d = client({ me = PAL, group = ws, spec = 184 })
  knowAll(d, "PALADIN", 60)
  d.known[25782], d.known[25916] = true, true
  d.items[21177] = { name = "Symbol of Kings" }
  d.bags = { { id = 21177, bag = 0, slot = 1, count = 20 } }
  PAL.auras = { { id = 25291, src = "player", exp = d.clock + 3000, dur = 3600 } }
  load(d)
  tick(d, 12)
  local pb = icon(d, "group", "duty:bless:might")
  local u = pb and pb:GetAttribute("unit")
  assert(pb and pb:GetAttribute("spell") == 25916 and d.units[u] and d.units[u].level == 60,
    "Greater Might 2 on a 60: " .. tostring(pb and pb:GetAttribute("spell")) .. " on " .. tostring(u))
  noErrors(d)
end)

test("low rank: a member with none is buffed before one with a lower rank, as the buffs from others order theirs", function()
  local c, R, fort = lowParty()
  local W
  for _, m in pairs(c.units) do if m.name == "Cwar" then W = m end end
  local tok = tokenOf(c, W)
  W.auras = {}
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.count == 2 and rec.word == "Cwar", "the warrior with none first, not the rogue with rank 4: " .. tostring(rec and rec.word))
  assert(rec.why == "1 member is missing it. 1 member has a lower rank.", rec.why)
  local b = icon(c, "group", "duty:fort")
  assert(b:GetAttribute("unit") == tok and b:GetAttribute("spell") == 10938, "its click buffs the warrior")
  -- (the warrior buffed: the rogue's lower rank next)
  W.auras = { fort(10938, "player") }
  fire(c, "UNIT_AURA", tok); tick(c, 2)
  rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.word == R.name and rec.why:find("^Rank 4 on them; you give rank 6%."), "then the rogue: " .. tostring(rec and rec.word))
  noErrors(c)
end)

-- (an Upgrade asked: since 0.2.3 its word is Buff, in amber (warn), kept apart from the plain Buff by its own Never key)
local function upgrade(rec) return rec ~= nil and rec.word == "Buff" and rec.status == "warn" and type(rec.never) == "string" and rec.never:sub(1, 3) == "up:" end
test("Upgrade: Inner Fire 5 on you and rank 6 learned asks for rank 6 (Buff, in amber), on each of the learning events; the word fits", function()
  local me = member({ name = "Upri", class = "PRIEST", level = 60 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 60)
  c.known[10952] = nil
  local function rank5() me.auras = { { id = 10951, src = "player", exp = c.clock + 600, dur = 600 } }; fire(c, "UNIT_AURA", "player"); tick(c, 1) end
  rank5()
  load(c)
  tick(c, 1)
  assert(not find(shown(c, "mine"), "self:innerfire"), "rank 5, the highest known: nothing")
  for _, ev in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP" }) do
    c.known[10952] = nil
    rank5()
    assert(not find(shown(c, "mine"), "self:innerfire"), ev .. ": rank 5 known at most, nothing")
    c.known[10952] = true
    tick(c, 1)
    assert(not find(shown(c, "mine"), "self:innerfire"), ev .. ": not before the game says")
    fire(c, ev); tick(c, 1)
    local rec = find(shown(c, "mine"), "self:innerfire")
    assert(upgrade(rec) and rec.click.spell == 10952 and rec.click.unit == "player", ev .. ": Upgrade to rank 6: " .. tostring(rec and rec.word))
    assert(rec.why == "Rank 5 on you; you know rank 6." and rec.lit, rec.why)
  end
  local b = icon(c, "own", "self:innerfire")
  assert(b:IsShown() and b:GetAttribute("spell") == 10952 and b:GetAttribute("unit") == "player", "the secure button casts rank 6 on you")
  FITS(b.word, "Upgrade's Buff under its icon")
  -- (the next icon, the group's first, never under its word)
  local g = c.env.CuteAurasBarGroup
  local first
  for _, x in pairs(g.__children) do if x.word and x:IsShown() and (not first or x.__points[1][4] < first.__points[1][4]) then first = x end end
  assert(first, "a group icon beside it")
  local ownX, grpX = c.env.CuteAurasBarOwn.__points[1][4], g.__points[1][4]
  assert(ownX + b.__points[1][4] + 16 + b.word.__w / 2 <= grpX + first.__points[1][4] + 16 - first.word.__w / 2, "Upgrade's Buff runs under the next icon's word")
  c.casts = {}
  c.click(b)
  assert(c.casts[1] and c.casts[1].spell == 10952, "the click casts 10952")
  me.auras = { { id = 10952, src = "player", exp = c.clock + 600, dur = 600 } }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  assert(not find(shown(c, "mine"), "self:innerfire"), "rank 6 on: nothing")
  -- (gone, the same icon asks the plain Buff again, its word's box the grid's 36)
  me.auras = {}
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  local plainBuff = find(shown(c, "mine"), "self:innerfire")
  assert(plainBuff.word == "Buff" and not upgrade(plainBuff) and b:IsShown() and b.word.__w == 36, "the plain Buff, its box 36: " .. b.word.__w)
  noErrors(c)
end)

test("Upgrade: a habit on you at a lower rank than you know, cast by its name; another's or a hidden id never", function()
  SPELL_NAMES[604], SPELL_NAMES[8450] = "Dampen Magic", "Dampen Magic"
  local me = member({ name = "Hab", class = "MAGE", level = 30 })
  local c = client({ me = me, db = { chars = { ["Player-1-Hab"] = { habitByName = true, habit = { ["Dampen Magic"] = { id = 604, hits = 3, miss = 0 } } } } } })
  c.known[604] = true
  local function on(t) me.auras = { t }; fire(c, "UNIT_AURA", "player"); tick(c, 1) end
  me.auras = { { id = 604, src = "player", exp = c.clock + 600, dur = 600 } }
  load(c)
  tick(c, 1)
  assert(not find(shown(c, "mine"), "habit:Dampen Magic"), "rank 1, the highest known: nothing")
  c.known[8450] = true
  fire(c, "LEARNED_SPELL_IN_TAB"); tick(c, 1)
  local rec = find(shown(c, "mine"), "habit:Dampen Magic")
  assert(upgrade(rec) and rec.click.spell == "Dampen Magic" and rec.click.unit == "player", "Upgrade, by the name: " .. tostring(rec and rec.word))
  local b = icon(c, "own", "habit:Dampen Magic")
  assert(b:GetAttribute("spell") == "Dampen Magic", "the secure button casts the name: the game's highest rank")
  FITS(b.word, "Upgrade's Buff under the habit")
  -- (the click casts rank 2 over rank 1 while it is still on: the habit follows the rank on you, so a rank 3 learned
  -- within the same ten minutes asks Upgrade again)
  c.click(b)
  assert(c.casts[#c.casts] and c.casts[#c.casts].spell == "Dampen Magic", "the click cast it by name")
  on({ id = 8450, src = "player", exp = c.clock + 600, dur = 600 })
  assert(not find(shown(c, "mine"), "habit:Dampen Magic"), "rank 2 cast over rank 1: nothing")
  SPELL_NAMES[8451], SPELL_LEVELS[8451] = "Dampen Magic", 36
  c.known[8451] = true
  fire(c, "LEARNED_SPELL_IN_TAB"); tick(c, 1)
  rec = find(shown(c, "mine"), "habit:Dampen Magic")
  assert(upgrade(rec), "rank 3 learned, rank 2 on: Upgrade again: " .. tostring(rec and rec.word))
  c.known[8451], SPELL_NAMES[8451], SPELL_LEVELS[8451] = nil, nil, nil
  fire(c, "LEARNED_SPELL_IN_TAB"); tick(c, 1)
  assert(not find(shown(c, "mine"), "habit:Dampen Magic"), "rank 2, the highest known again: nothing")
  -- another mage's rank 1 on you, or yours whose spell id the client hides: nothing to ask
  on({ id = 604, src = nil, exp = c.clock + 600, dur = 600 })
  assert(not find(shown(c, "mine"), "habit:Dampen Magic"), "another's rank 1: not yours to upgrade")
  on({ id = 604, src = "player", secretId = true, exp = c.clock + 600, dur = 600 })
  assert(not find(shown(c, "mine"), "habit:Dampen Magic"), "a hidden spell id: never lower")
  on({ id = 8450, src = "player", exp = c.clock + 600, dur = 600 })
  assert(not find(shown(c, "mine"), "habit:Dampen Magic"), "rank 2 on: nothing")
  SPELL_NAMES[604], SPELL_NAMES[8450] = nil, nil
  noErrors(c)
end)

test("Upgrade: a habit's name on you from an elixir or a piece of gear (Water Breathing) is no rank of it; a level not told is never lower", function()
  -- (the shaman's Water Breathing, 131, learned at 22; the elixir's aura 7178 has no level (0), a piece of gear's 11789 20)
  SPELL_NAMES[131], SPELL_NAMES[7178], SPELL_NAMES[11789] = "Water Breathing", "Water Breathing", "Water Breathing"
  SPELL_LEVELS[131], SPELL_LEVELS[11789] = 22, 20
  local me = member({ name = "Wsha", class = "SHAMAN", level = 40 })
  local c = client({ me = me, db = { chars = { ["Player-1-Wsha"] = { habitByName = true, habit = { ["Water Breathing"] = { id = 131, hits = 3, miss = 0 } } } } } })
  knowAll(c, "SHAMAN", 40)
  c.known[131] = true
  local function on(t) me.auras = { t }; fire(c, "UNIT_AURA", "player"); tick(c, 1) end
  -- (the elixir drunk: its aura yours)
  me.auras = { { id = 7178, src = "player", exp = c.clock + 1800, dur = 1800 } }
  load(c)
  tick(c, 1)
  assert(not find(shown(c, "mine"), "habit:Water Breathing"), "an elixir's Water Breathing: no Upgrade")
  assert(c.A.Spells.Lower(7178, 131) == false and c.A.Spells.Lower(131, 7178) == false, "a level not told (0) is never lower, nor higher")
  on({ id = 11789, src = "player", exp = 0, dur = 0 })
  assert(not find(shown(c, "mine"), "habit:Water Breathing"), "a piece of gear's Water Breathing (level 20): no Upgrade")
  on({ id = 131, src = "player", exp = c.clock + 600, dur = 600 })
  assert(not find(shown(c, "mine"), "habit:Water Breathing"), "your own on: nothing")
  -- (a second rank, made up for the test: Water Breathing has one) the elixir's aura first, your rank 1 too: yours is
  -- the one weighed, its Upgrade asked
  SPELL_NAMES[99131], SPELL_LEVELS[99131] = "Water Breathing", 40
  c.known[99131] = true
  me.auras = { { id = 7178, src = "player", exp = c.clock + 1800, dur = 1800 }, { id = 131, src = "player", exp = c.clock + 600, dur = 600 } }
  fire(c, "LEARNED_SPELL_IN_TAB"); fire(c, "UNIT_AURA", "player"); tick(c, 1)
  local rec = find(shown(c, "mine"), "habit:Water Breathing")
  assert(upgrade(rec), "the elixir's aura and your rank 1, rank 2 known: your rank's Upgrade: " .. keysOf(shown(c, "mine")))
  SPELL_NAMES[131], SPELL_NAMES[7178], SPELL_NAMES[11789], SPELL_NAMES[99131] = nil, nil, nil, nil
  SPELL_LEVELS[131], SPELL_LEVELS[11789], SPELL_LEVELS[99131] = nil, nil, nil
  noErrors(c)
end)

test("Upgrade: its own Never (a lower rank kept on purpose): the Buff still asked when it is gone; Never on the Buff hides both", function()
  local me = member({ name = "Upri", class = "PRIEST", level = 60 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 60)
  local function on(t) me.auras = t; fire(c, "UNIT_AURA", "player"); tick(c, 1) end
  local function never(b, text)
    c.A.Bar.Menu(b)
    local chose = false
    for _, e in ipairs(c.menus[#c.menus]) do if e.text == text then e.fn(); chose = true end end
    assert(chose, "the menu has " .. text)
    tick(c, 1)
  end
  me.auras = { { id = 10951, src = "player", exp = c.clock + 600, dur = 600 } }
  load(c)
  tick(c, 1)
  assert(upgrade(find(shown(c, "mine"), "self:innerfire")), "rank 5 on, rank 6 known: Upgrade")
  never(icon(c, "own", "self:innerfire"), "Never: Upgrade Inner Fire")
  local set = c.A.Settings().never
  assert(set["up:Inner Fire"] and set["buff:innerfire"] == nil and not find(shown(c, "mine"), "self:innerfire"), "its own key (the spell's), the Upgrade gone")
  on({})
  local rec = find(shown(c, "mine"), "self:innerfire")
  assert(rec and rec.word == "Buff" and not upgrade(rec), "Inner Fire gone: Buff still asked: " .. tostring(rec and rec.word))
  -- Never on the Buff: nothing of Inner Fire, its Upgrade neither
  set["up:Inner Fire"] = nil
  never(icon(c, "own", "self:innerfire"), "Never: Inner Fire")
  assert(set["buff:innerfire"] and not find(shown(c, "mine"), "self:innerfire"), "Never: Inner Fire")
  on({ { id = 10951, src = "player", exp = c.clock + 600, dur = 600 } })
  assert(not find(shown(c, "mine"), "self:innerfire"), "rank 5 on: no Upgrade either")
  noErrors(c)
  -- a habit the same: Never: Upgrade Dampen Magic keeps its Buff
  SPELL_NAMES[604], SPELL_NAMES[8450] = "Dampen Magic", "Dampen Magic"
  local mg = member({ name = "Hab", class = "MAGE", level = 30 })
  local d = client({ me = mg, db = { chars = { ["Player-1-Hab"] = { habitByName = true, habit = { ["Dampen Magic"] = { id = 604, hits = 3, miss = 0 } } } } } })
  d.known[604], d.known[8450] = true, true
  mg.auras = { { id = 604, src = "player", exp = d.clock + 600, dur = 600 } }
  load(d)
  tick(d, 1)
  assert(upgrade(find(shown(d, "mine"), "habit:Dampen Magic")), "rank 1 on, rank 2 known: Upgrade")
  d.A.Bar.Menu(icon(d, "own", "habit:Dampen Magic"))
  local chose = false
  for _, e in ipairs(d.menus[#d.menus]) do if e.text == "Never: Upgrade Dampen Magic" then e.fn(); chose = true end end
  assert(chose, "the menu has Never: Upgrade Dampen Magic")
  tick(d, 1)
  assert(d.A.Settings().never["up:Dampen Magic"] and not find(shown(d, "mine"), "habit:Dampen Magic"), "the Upgrade gone, its own key")
  mg.auras = {}
  fire(d, "UNIT_AURA", "player"); tick(d, 1)
  rec = find(shown(d, "mine"), "habit:Dampen Magic")
  assert(rec and rec.word == "Buff" and not upgrade(rec), "Dampen Magic gone: Buff still asked: " .. tostring(rec and rec.word))
  SPELL_NAMES[604], SPELL_NAMES[8450] = nil, nil
  noErrors(d)
end)

test("Upgrade: Lightning Shield's ranks counted as the game does (a proc spell shares each rank's name and level): rank 6 on, 7 known; the Buff casts 7", function()
  local me = member({ name = "Lsha", class = "SHAMAN", level = 60 })
  local c = client({ me = me })
  knowAll(c, "SHAMAN", 60)
  assert(c.known[10432] and not c.known[26363], "the trainer's rank known, never its proc")
  local function on(t) me.auras = t; fire(c, "UNIT_AURA", "player"); tick(c, 1) end
  me.auras = { { id = 10431, src = "player", exp = c.clock + 600, dur = 600 } }
  load(c)
  tick(c, 1)
  local rec = find(shown(c, "mine"), "self:shield")
  assert(upgrade(rec) and rec.click.spell == 10432, "rank 6 on: Upgrade to 10432: " .. tostring(rec and rec.click and rec.click.spell))
  assert(rec.why == "Rank 6 on you; you know rank 7.", rec.why)
  on({ { id = 10432, src = "player", exp = c.clock + 600, dur = 600 } })
  assert(not find(shown(c, "mine"), "self:shield"), "rank 7 on: nothing")
  on({})
  rec = find(shown(c, "mine"), "self:shield")
  assert(rec and rec.word == "Buff" and not upgrade(rec) and rec.click.spell == 10432, "none on: the Buff casts rank 7: " .. tostring(rec and rec.click and rec.click.spell))
  noErrors(c)
end)

test("Upgrade: its Never names one spell and hides that one: Never: Upgrade Frost Armor still asks Ice Armor's, and the account's warlock its Demon Armor's", function()
  local me = member({ name = "Upmag", class = "MAGE", level = 40 })
  local c = client({ me = me })
  knowAll(c, "MAGE", 40)
  local function aura(id, dur) return { id = id, src = "player", exp = c.clock + dur - 100, dur = dur } end
  local function on(id) me.auras = { aura(1461, 3600), aura(id, 1800) }; fire(c, "UNIT_AURA", "player"); tick(c, 1) end
  -- (Arcane Intellect 3 on, the most a 40 knows; Frost Armor 2, rank 3 known)
  me.auras = { aura(1461, 3600), aura(7300, 1800) }
  load(c)
  tick(c, 1)
  local rec = find(shown(c, "mine"), "self:armor")
  assert(upgrade(rec) and rec.click.spell == 7301, "Frost Armor 2 on: Upgrade to 3: " .. tostring(rec and rec.word))
  c.A.Bar.Menu(icon(c, "own", "self:armor"))
  local chose = false
  for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Never: Upgrade Frost Armor" then e.fn(); chose = true end end
  assert(chose, "the menu has Never: Upgrade Frost Armor")
  tick(c, 1)
  assert(c.A.Settings().never["up:Frost Armor"] and not find(shown(c, "mine"), "self:armor"), "the Upgrade gone, by the spell's key")
  on(7302)
  rec = find(shown(c, "mine"), "self:armor")
  assert(upgrade(rec) and rec.click.spell == 7320 and rec.neverName == "Upgrade Ice Armor",
    "Ice Armor 1 on, 2 known: its own Upgrade still asked: " .. tostring(rec and rec.word))
  noErrors(c)
  -- the account's warlock (Nevers are the account's): Demon Armor 4 on, 5 known
  local wl = member({ name = "Uplock", class = "WARLOCK", level = 60 })
  local d = client({ me = wl, db = c.env.CuteAurasDB })
  knowAll(d, "WARLOCK", 60)
  wl.auras = { { id = 11734, src = "player", exp = d.clock + 1700, dur = 1800 } }
  load(d)
  tick(d, 1)
  rec = find(shown(d, "mine"), "self:armor")
  assert(d.A.Settings().never["up:Frost Armor"] and upgrade(rec) and rec.click.spell == 11735,
    "the warlock's Demon Armor 4: Upgrade, the mage's Never not theirs: " .. tostring(rec and rec.word))
  noErrors(d)
end)

----------------------------------------------------------------------------
-- buffs others give you (the owner, 2026-11-23: "nnotified when u are missing buff from others"): in yours, greyed, the
-- giver's name under it, after 30 s out of a fight, at once at a ready check
----------------------------------------------------------------------------
-- a level 60 mage running Cute Auras (Arcane Intellect and Ice Armor on: nothing of its own to ask; Divine Spirit on,
-- unless o.noSpirit), a priest who doesn't, a warrior tank (o.noTank: none); o.priest: the priest's fields, o.more:
-- more members (a party: five at most)
local function fromParty(o)
  o = o or {}
  local M = member({ name = "Amag", class = "MAGE", level = 60, guid = "Player-1-F1" })
  local P = member({ name = "Bprie", class = "PRIEST", level = 60, guid = "Player-1-F2" })
  for k, v in pairs(o.priest or {}) do P[k] = v end
  local W = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-F3", assigned = "TANK" })
  local group = { M, P }
  if not o.noTank then group[3] = W end
  for _, x in ipairs(o.more or {}) do group[#group + 1] = x end
  assert(#group <= 5, "a party of five at most")
  local c = client({ me = M, group = group, spec = 8 })
  knowAll(c, "MAGE", 60)
  M.auras = { { id = 10157, src = "player", exp = c.clock + 3500, dur = 3600 }, { id = 10220, src = "player", exp = c.clock + 1700, dur = 1800 } }
  if not o.noSpirit then M.auras[3] = { id = 27841, exp = c.clock + 3500, dur = 3600 } end
  load(c)
  return c, M, P, W
end
local function fromKeys(c)
  local t = {}
  for _, r in ipairs(shown(c, "mine")) do if r.key:find("^from:") then t[#t + 1] = r.key .. "=" .. tostring(r.word) end end
  return table.concat(t, ",")
end
local function tipOf(c, b) c.hover(b); return c.env.GameTooltip.lines end

test("from others: a priest not running Cute Auras, Fortitude missing 30 s: greyed, the priest's name, no click; gone as it lands", function()
  local c, M, P = fromParty()
  tick(c, 29)
  assert(fromKeys(c) == "", "not before 30 s: " .. fromKeys(c))
  tick(c, 2)
  local rec = find(shown(c, "mine"), "from:fort")
  assert(rec and rec.word == "Bprie" and rec.class == "PRIEST" and rec.status == nil and rec.lit == false and rec.click == nil,
    "Fortitude, the priest named: " .. fromKeys(c))
  assert(fromKeys(c) == "from:fort=Bprie", "Fortitude alone (Divine Spirit on): " .. fromKeys(c))
  local b = icon(c, "own", "from:fort")
  assert(b and b:IsShown() and b.icon.__desat == true and b.icon.__alpha < 1, "its icon greyed")
  assert(b.word.__text == "Bprie" and b.word.__textColor[1] == 1 and b.word.__textColor[2] == 1, "the name in its class colour")
  FITS(b.word, "the giver's name")
  assert(b:GetAttribute("type1") == nil and b:GetAttribute("spell") == nil, "no secure action: not a buff you cast")
  c.casts = {}
  c.click(b)
  assert(#c.casts == 0, "a click casts nothing")
  local lines = tipOf(c, b)
  assert(lines[1] == "Power Word: Fortitude" and lines[2] == "Missing. Bprie can give it.", "the tooltip: " .. tostring(lines[2]))
  for _, l in ipairs(lines) do assert(not l:find("^Click"), "no click line: " .. l) end
  -- (after your own buffs: an Upgrade or a Buff of yours stands before it; Ice Armor removed, not a hole the read stops at)
  table.remove(M.auras, 2)
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  local mine = shown(c, "mine")
  assert(mine[1].key == "self:armor" and mine[2].key == "from:fort", "yours first: " .. keysOf(mine))
  table.insert(M.auras, 2, { id = 10220, src = "player", exp = c.clock + 1700, dur = 1800 })
  -- the priest buffs you: gone at once; it ends: 30 s again
  M.auras[#M.auras + 1] = { id = 10938, exp = c.clock + 3600, dur = 3600 }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  assert(fromKeys(c) == "", "on you: gone: " .. fromKeys(c))
  table.remove(M.auras)
  fire(c, "UNIT_AURA", "player"); tick(c, 20)
  assert(fromKeys(c) == "", "its wait started again: " .. fromKeys(c))
  tick(c, 12)
  assert(fromKeys(c) == "from:fort=Bprie", "30 s later: " .. fromKeys(c))
  noErrors(c)
end)

test("from others: a ready check shows it at once; the giver offline, dead or out of sight: nothing, the wait again after", function()
  local c, M, P = fromParty()
  tick(c, 5)
  fire(c, "READY_CHECK"); tick(c, 4)
  local rec = find(shown(c, "mine"), "from:fort")
  assert(rec and rec.word == "Bprie", "at a ready check, at once: " .. fromKeys(c))
  assert(tipOf(c, icon(c, "own", "from:fort"))[2] == "Missing. Bprie can give it.", "its line")
  fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
  tick(c, 30)
  assert(fromKeys(c) == "from:fort=Bprie", "missing 30 s: " .. fromKeys(c))
  local tok = tokenOf(c, P)
  P.online = false
  fire(c, "UNIT_CONNECTION", tok); tick(c, 1)
  assert(fromKeys(c) == "", "the priest offline: nothing: " .. fromKeys(c))
  P.online = true
  fire(c, "UNIT_CONNECTION", tok); tick(c, 2)
  assert(fromKeys(c) == "", "back online: they get their 30 s: " .. fromKeys(c))
  tick(c, 30)
  assert(fromKeys(c) == "from:fort=Bprie", "then named: " .. fromKeys(c))
  P.dead = true
  fire(c, "UNIT_FLAGS", tok); tick(c, 1)
  assert(fromKeys(c) == "", "the priest dead: nothing: " .. fromKeys(c))
  P.dead = false
  fire(c, "UNIT_FLAGS", tok); tick(c, 31)
  assert(fromKeys(c) == "from:fort=Bprie", "alive, 30 s on: " .. fromKeys(c))
  -- (out of sight fires no event: the 5 s look sees it)
  P.visible = false
  tick(c, 6)
  assert(fromKeys(c) == "", "out of sight: nothing: " .. fromKeys(c))
  P.visible = nil
  noErrors(c)
end)

test("from others: nothing in a fight; 30 s out of it again after; nothing dead, on a taxi, or with the setting off", function()
  local c, M, P = fromParty()
  tick(c, 20)
  fight(c, true)
  tick(c, 40)
  assert(fromKeys(c) == "", "in a fight: nothing: " .. fromKeys(c))
  fight(c, false)
  tick(c, 3)
  assert(fromKeys(c) == "", "out of it: its 30 s start again: " .. fromKeys(c))
  tick(c, 30)
  assert(fromKeys(c) == "from:fort=Bprie", "30 s out of the fight: " .. fromKeys(c))
  -- shown, then a fight: your part hides with it, and no read changes it
  fight(c, true); tick(c, 1)
  assert(not c.env.CuteAurasBarOwn:IsShown(), "in a fight your part is hidden")
  fight(c, false); tick(c, 3)
  assert(fromKeys(c) == "", "after it: the wait again")
  tick(c, 30)
  assert(fromKeys(c) == "from:fort=Bprie", "back: " .. fromKeys(c))
  -- dead, on a taxi: nothing, and the wait again after
  M.dead = true
  fire(c, "PLAYER_DEAD"); tick(c, 1)
  assert(fromKeys(c) == "" and not c.env.CuteAurasBar:IsShown(), "dead: nothing")
  M.dead = false
  fire(c, "PLAYER_ALIVE"); tick(c, 2)
  assert(fromKeys(c) == "", "alive: the wait again: " .. fromKeys(c))
  c.taxi = true
  tick(c, 40); c.A.Bar.Dirty("all"); tick(c, 1)
  assert(fromKeys(c) == "", "on a taxi: nothing")
  c.taxi = false
  c.A.Bar.Dirty("all"); tick(c, 31)
  assert(fromKeys(c) == "from:fort=Bprie", "off the taxi, 30 s: " .. fromKeys(c))
  -- Settings, Buffs others give you: off hides them all
  c.A.Window.Open("settings")
  local page = c.A.Window.pages.settings
  local box = widget(page, "Buffs others give you")
  assert(box and box.tick:IsShown(), "on by default")
  c.click(box); tick(c, 1)
  assert(c.A.Settings().others == false and fromKeys(c) == "", "off: nothing: " .. fromKeys(c))
  tick(c, 40)
  assert(fromKeys(c) == "", "off stays off")
  c.click(box); tick(c, 1)
  assert(fromKeys(c) == "", "on again: its 30 s first")
  tick(c, 31)
  assert(fromKeys(c) == "from:fort=Bprie", "on again: " .. fromKeys(c))
  noErrors(c)
end)

test("from others: the share-out's priest is named (every client the same), not the first priest by GUID; never yourself", function()
  local M = member({ name = "Amag", class = "MAGE", level = 60, guid = "Player-1-S4" })
  local P1 = member({ name = "Bnoca", class = "PRIEST", level = 60, guid = "Player-1-S1" })
  local P2 = member({ name = "Cpri", class = "PRIEST", level = 60, guid = "Player-1-S2" })
  local P3 = member({ name = "Dpri", class = "PRIEST", level = 60, guid = "Player-1-S3" })
  local group = { M, P1, P2, P3 }
  local cm = client({ me = M, group = group, spec = 8 })
  local c2 = client({ me = P2, group = group, spec = 56 })
  local c3 = client({ me = P3, group = group, spec = 56 })
  knowAll(cm, "MAGE", 60); knowAll(c2, "PRIEST", 60); knowAll(c3, "PRIEST", 60)
  M.auras = { { id = 10157, src = "player", exp = cm.clock + 3500, dur = 3600 }, { id = 10220, src = "player", exp = cm.clock + 1700, dur = 1800 } }
  load(cm); load(c2); load(c3)
  tickAll(34)
  for _, c in ipairs({ cm, c2, c3 }) do
    assert(c.A.Assign.GiverOf("fort", M.guid) == P2.guid and c.A.Assign.GiverOf("fort", P3.guid) == P2.guid, "every client: Cpri gives Fortitude")
  end
  local rec = find(shown(cm, "mine"), "from:fort")
  assert(rec and rec.word == "Cpri", "the share-out's priest, not Bnoca (first by GUID, no Cute Auras): " .. fromKeys(cm))
  assert(find(shown(cm, "mine"), "from:spirit").word == "Cpri", "Divine Spirit from Cpri too: " .. fromKeys(cm))
  local line = tipOf(cm, icon(cm, "own", "from:fort"))[2]
  assert(line == "Missing. Cpri gives it (shared out by Cute Auras).", line)
  -- the giver's own client: its own Fortitude is its duty, never a reminder; the other priest's names Cpri
  assert(not find(shown(c2, "mine"), "from:fort") and find(shown(c2, "group"), "duty:fort"), "never yourself: " .. fromKeys(c2))
  assert(find(shown(c3, "mine"), "from:fort").word == "Cpri", "the other priest is reminded of Cpri: " .. fromKeys(c3))
  -- (Shadow Protection: never, until a priest running Cute Auras switches it on and so announces it)
  assert(not find(shown(cm, "mine"), "from:shadow"), "no Shadow Protection")
  c2.A.Settings().opt.shadow = true; c2.A.Comm.GivesChanged()
  tickAll(34)
  assert(fromKeys(cm) == "from:fort=Cpri,from:shadow=Cpri,from:spirit=Cpri", "announced: Shadow Protection asked too: " .. fromKeys(cm))
  for _, c in ipairs({ cm, c2, c3 }) do noErrors(c) end
end)

test("from others: the share-out's paladin for your blessing (a lower rank too); no Blessing from one without it then", function()
  local M = member({ name = "Amag", class = "MAGE", level = 60, guid = "Player-1-K1" })
  local NP = member({ name = "Bnopal", class = "PALADIN", level = 60, guid = "Player-1-K2" })
  local PAL = member({ name = "Cpal", class = "PALADIN", level = 60, guid = "Player-1-K3" })
  local group = { M, NP, PAL }
  local cm = client({ me = M, group = group, spec = 8 })
  local cp = client({ me = PAL, group = group, spec = 594 })
  knowAll(cm, "MAGE", 60); knowAll(cp, "PALADIN", 60)
  M.auras = { { id = 10157, src = "player", exp = cm.clock + 3500, dur = 3600 }, { id = 10220, src = "player", exp = cm.clock + 1700, dur = 1800 } }
  load(cm); load(cp)
  tickAll(34)
  assert(cm.A.Assign.BlesserOf("MAGE:caster", "wisdom") == PAL.guid, "the share-out: Wisdom to the mage from Cpal")
  assert(fromKeys(cm) == "from:bless:wisdom=Cpal", "Wisdom from Cpal; no Blessing from Bnopal while the share-out gives one: " .. fromKeys(cm))
  local b = icon(cm, "own", "from:bless:wisdom")
  local lines = tipOf(cm, b)
  assert(lines[1] == "Blessing of Wisdom" and lines[2] == "Missing. Cpal gives it (shared out by Cute Auras).", tostring(lines[2]))
  -- Wisdom 4 from another paladin, gone since: a lower rank than Cpal's 6; Greater Wisdom 2, as strong: fine
  M.auras[3] = { id = 19853, exp = cm.clock + 3000, dur = 3600 }
  fire(cm, "UNIT_AURA", "player"); tickAll(2)
  assert(tipOf(cm, b)[2] == "Rank 4 on you; Cpal gives rank 6 (shared out by Cute Auras).", "the lower rank, at once (it was waiting already)")
  M.auras[3] = { id = 25918, exp = cm.clock + 3000, dur = 3600 }
  fire(cm, "UNIT_AURA", "player"); tickAll(2)
  assert(fromKeys(cm) == "", "Greater Wisdom 2: fine: " .. fromKeys(cm))
  -- the paladin's own client: its blessing is its duty, never a reminder
  for _, r in ipairs(shown(cp, "mine")) do assert(not r.key:find("^from:bless"), "never yourself: " .. r.key) end
  noErrors(cm); noErrors(cp)
end)

test("from others: never named for what they opted out of: a priest's Fortitude on Never, a paladin's blessings off", function()
  local M = member({ name = "Amag", class = "MAGE", level = 60, guid = "Player-1-N2" })
  local P = member({ name = "Bpri", class = "PRIEST", level = 60, guid = "Player-1-N3" })
  local PAL = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-N1" })
  local group = { M, P, PAL }
  local cm = client({ me = M, group = group, spec = 8 })
  local cp = client({ me = P, group = group, spec = 56, db = { settings = { never = { ["duty:fort"] = "Power Word: Fortitude" } } } })
  local cl = client({ me = PAL, group = group, spec = 594, db = { settings = { blessings = false } } })
  knowAll(cm, "MAGE", 60); knowAll(cp, "PRIEST", 60); knowAll(cl, "PALADIN", 60)
  M.auras = { { id = 10157, src = "player", exp = cm.clock + 3500, dur = 3600 }, { id = 10220, src = "player", exp = cm.clock + 1700, dur = 1800 } }
  load(cm); load(cp); load(cl)
  tickAll(34)
  assert(not cm.A.Assign.Shared("fort") and cm.A.Assign.Shared("spirit") and #cm.A.Assign.paladins == 0, "Fortitude and the blessings not announced, Divine Spirit is")
  assert(fromKeys(cm) == "from:spirit=Bpri", "their choices kept: no Fortitude, no Blessing asked of them: " .. fromKeys(cm))
  noErrors(cm); noErrors(cp); noErrors(cl)
end)

test("from others: a warrior is never asked for Arcane Intellect or Wisdom, a hand-set Wisdom too; Fortitude still", function()
  local W = member({ name = "Awar", class = "WARRIOR", level = 60, guid = "Player-1-W1" })
  local M = member({ name = "Bmag", class = "MAGE", level = 60, guid = "Player-1-W2" })
  local PAL = member({ name = "Cpal", class = "PALADIN", level = 60, guid = "Player-1-W3" })
  local P = member({ name = "Dprie", class = "PRIEST", level = 60, guid = "Player-1-W4" })
  local group = { W, M, PAL, P }
  local cw = client({ me = W, group = group })
  -- (the paladin gives Wisdom alone: Kings and Might on Never)
  local cp = client({ me = PAL, group = group, spec = 594, db = { settings = { never = { ["duty:bless:kings"] = "Kings", ["duty:bless:might"] = "Might" } } } })
  knowAll(cw, "WARRIOR", 60); knowAll(cp, "PALADIN", 60)
  load(cw); load(cp)
  tickAll(12)
  assert(cw.A.Comm.peers[PAL.guid] and cw.A.Comm.peers[PAL.guid].knownText == "wisdom:6", "the paladin gives Wisdom alone: " .. tostring(cw.A.Comm.peers[PAL.guid] and cw.A.Comm.peers[PAL.guid].knownText))
  -- the paladin sets Wisdom for warriors by hand: the share-out's word, still never asked of a warrior
  cp.A.Assign.Set(PAL.guid, "WARRIOR:melee", "wisdom")
  tickAll(34)
  assert(cw.A.Assign.BlesserOf("WARRIOR:melee", "wisdom") == PAL.guid, "the warrior's bucket: Wisdom from Cpal")
  assert(fromKeys(cw) == "from:fort=Dprie", "Fortitude alone, never Arcane Intellect or Wisdom: " .. fromKeys(cw))
  noErrors(cw); noErrors(cp)
end)

test("from others: rank 3 Fortitude on a level 60 with a level 60 priest: Rank 3 on you; a priest of 30 gives no more; Prayer 2 is fine", function()
  local function fort(c, id) return { id = id, exp = c.clock + 3000, dur = 3600 } end
  local c, M = fromParty()
  M.auras[#M.auras + 1] = fort(c, 1245)
  fire(c, "UNIT_AURA", "player"); tick(c, 31)
  local rec = find(shown(c, "mine"), "from:fort")
  assert(rec and rec.word == "Bprie" and rec.lit == false, "a lower rank counts: " .. fromKeys(c))
  assert(tipOf(c, icon(c, "own", "from:fort"))[2] == "Rank 3 on you; Bprie can give rank 6.", "its line")
  M.auras[#M.auras] = fort(c, 21564)
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  assert(fromKeys(c) == "", "Prayer of Fortitude 2, as strong as rank 6: fine: " .. fromKeys(c))
  M.auras[#M.auras] = fort(c, 21562)
  fire(c, "UNIT_AURA", "player"); tick(c, 31)
  assert(tipOf(c, icon(c, "own", "from:fort"))[2] == "Prayer of Fortitude rank 1 on you; Bprie can give rank 6.", "Prayer 1 at 60: low")
  noErrors(c)
  -- a priest of 30 knows rank 3 at most: nothing more to give
  local d, M2 = fromParty({ priest = { level = 30 } })
  M2.auras[#M2.auras + 1] = fort(d, 1245)
  fire(d, "UNIT_AURA", "player"); tick(d, 40)
  assert(fromKeys(d) == "", "a level 30 priest gives rank 3 at most: " .. fromKeys(d))
  -- (and with none on, rank 3 is theirs to give: named)
  table.remove(M2.auras)
  fire(d, "UNIT_AURA", "player"); tick(d, 31)
  assert(fromKeys(d) == "from:fort=Bprie", "none on: the level 30 priest: " .. fromKeys(d))
  noErrors(d)
  -- rank 3 on, the level 30 priest first by GUID and a level 60 one after: the one who gives more is named
  local H = member({ name = "Hprie", class = "PRIEST", level = 60, guid = "Player-1-F9" })
  local e, M3 = fromParty({ priest = { level = 30 }, more = { H } })
  M3.auras[#M3.auras + 1] = fort(e, 1245)
  fire(e, "UNIT_AURA", "player"); tick(e, 31)
  assert(fromKeys(e) == "from:fort=Hprie" and tipOf(e, icon(e, "own", "from:fort"))[2] == "Rank 3 on you; Hprie can give rank 6.", "the level 60 priest: " .. fromKeys(e))
  noErrors(e)
end)

test("from others: a tank is asked for Thorns by a druid without Cute Auras; Earth Shield only from a shaman running it", function()
  local W = member({ name = "Awar", class = "WARRIOR", level = 60, guid = "Player-1-T1", assigned = "TANK" })
  local DR = member({ name = "Wolfwardenmw", class = "DRUID", level = 60, guid = "Player-1-T2" })
  local SH = member({ name = "Csha", class = "SHAMAN", level = 60, guid = "Player-1-T3" })
  local group = { W, DR, SH }
  local cw = client({ me = W, group = group })
  knowAll(cw, "WARRIOR", 60)
  -- (Mark of the Wild on: Thorns, a tank's, the one asked)
  W.auras = { { id = 9885, exp = cw.clock + 3500, dur = 3600 } }
  load(cw)
  tick(cw, 31)
  assert(fromKeys(cw) == "from:thorns=Wolfwardenmw", "Thorns from the druid; no Earth Shield from a shaman without Cute Auras (a rune, not a level's): " .. fromKeys(cw))
  -- the shaman runs Cute Auras and has Earth Shield: the share-out's, named
  local cs = client({ me = SH, group = group, spec = 374 })
  knowAll(cs, "SHAMAN", 60)
  load(cs)
  tickAll(34)
  assert(cw.A.Assign.GiverOf("earthshield", W.guid) == SH.guid, "the share-out gives the tank's Earth Shield to the shaman")
  assert(fromKeys(cw) == "from:earthshield=Csha,from:thorns=Wolfwardenmw", "Earth Shield from the shaman running it: " .. fromKeys(cw))
  -- (a twelve-letter name, the game's longest, whole under its icon, its column clear of the one before)
  local a, b = icon(cw, "own", "from:earthshield"), icon(cw, "own", "from:thorns")
  FITS(b.word, "a twelve-letter giver")
  assert(a.__points[1][4] + 16 + a.word.__w / 2 <= b.__points[1][4] + 16 - b.word.__w / 2, "the two names side by side, none under the other")
  noErrors(cw); noErrors(cs)
end)

test("from others: three at most, missing first; Never hides one (a from: key of the 32) and the next shows; a paladin without it: one Blessing", function()
  local D1 = member({ name = "Edru", class = "DRUID", level = 60, guid = "Player-1-F5" })
  local PA = member({ name = "Gpal", class = "PALADIN", level = 60, guid = "Player-1-F7" })
  local PB = member({ name = "Fpal", class = "PALADIN", level = 60, guid = "Player-1-F6" })
  local function fort(c, id) return { id = id, exp = c.clock + 3000, dur = 3600 } end
  local c, M, P = fromParty({ more = { D1, PA, PB }, noSpirit = true, noTank = true })
  -- (Fortitude 3 on: low, after the missing ones)
  M.auras[#M.auras + 1] = fort(c, 1245)
  fire(c, "UNIT_AURA", "player"); tick(c, 31)
  -- missing: Mark of the Wild, Divine Spirit (trained in Forever: a level 60 priest without Cute Auras can give it), a
  -- blessing; low: Fortitude. Four to show, three at most: the low one cut
  assert(fromKeys(c) == "from:motw=Edru,from:spirit=Bprie,from:bless=Fpal", "three, missing first, by key, then blessings: " .. fromKeys(c))
  local bl = find(shown(c, "mine"), "from:bless")
  assert(bl.name == "Blessing" and bl.tex == c.A.Look.SpellIcon(19742, 135970), "Blessing, Wisdom's icon (a mage's first wish)")
  assert(tipOf(c, icon(c, "own", "from:bless"))[2] == "No blessing on you. Fpal can give one.", "its line")
  -- the priest runs Cute Auras: the share-out's answer is the same priest, the same three
  local cp = client({ me = P, group = c.o.group, spec = 56 })
  knowAll(cp, "PRIEST", 60)
  load(cp)
  tickAll(34)
  assert(c.A.Assign.Shared("spirit") and c.A.Assign.GiverOf("spirit", c.o.me.guid) == P.guid, "the share-out gives you Divine Spirit from the priest")
  assert(fromKeys(c) == "from:motw=Edru,from:spirit=Bprie,from:bless=Fpal", "three, missing first, the low Fortitude cut: " .. fromKeys(c))
  -- Never on Mark of the Wild: its key from:motw, counted; the low Fortitude takes its place
  local n0 = c.A.Bar.NeverCount()
  c.A.Bar.Menu(icon(c, "own", "from:motw"))
  for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Never: Mark of the Wild" then e.fn() end end
  tick(c, 1)
  assert(c.A.Settings().never["from:motw"] and c.A.Bar.NeverCount() == n0 + 1, "a from: key, counted in the 32")
  assert(fromKeys(c) == "from:spirit=Bprie,from:bless=Fpal,from:fort=Bprie", "Never hides it, the next shows: " .. fromKeys(c))
  -- a blessing on you (Kings, any paladin's): no Blessing
  M.auras[#M.auras + 1] = { id = 20217, exp = c.clock + 3000, dur = 3600 }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  assert(not find(shown(c, "mine"), "from:bless"), "a blessing on: no Blessing: " .. fromKeys(c))
  noErrors(c)
end)

test("from others: a group refresh (a member's aura, a member offline, the 3 s look) reads none of your auras; your own change does", function()
  local c, M, P = fromParty()
  tick(c, 31)
  assert(fromKeys(c) == "from:fort=Bprie", "named: " .. fromKeys(c))
  local ua = c.env.C_UnitAuras
  local get, mine = ua.GetAuraDataByIndex, 0
  ua.GetAuraDataByIndex = function(u, ...) if u == "player" then mine = mine + 1 end return get(u, ...) end
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  assert(mine > 0, "your own change: read")
  mine = 0
  local tok = tokenOf(c, P)
  fire(c, "UNIT_AURA", tok); tick(c, 1)
  tick(c, 4)
  P.online = false
  fire(c, "UNIT_CONNECTION", tok); tick(c, 1)
  assert(fromKeys(c) == "", "the group refresh read it again: the priest offline, nothing: " .. fromKeys(c))
  assert(mine == 0, "group refreshes read your auras " .. mine .. " times")
  ua.GetAuraDataByIndex = get
  noErrors(c)
end)

test("from others: a giver out of sight from the start, back in sight with no event: the 5 s look sees them, named 30 s on", function()
  local W = member({ name = "Awar", class = "WARRIOR", level = 60, guid = "Player-1-Z1" })
  local P = member({ name = "Bprie", class = "PRIEST", level = 60, guid = "Player-1-Z2", visible = false })
  local c = client({ me = W, group = { W, P } })
  load(c)
  tick(c, 40)
  assert(fromKeys(c) == "", "out of sight: nothing: " .. fromKeys(c))
  P.visible = nil
  tick(c, 29)
  assert(fromKeys(c) == "", "back in sight: its 30 s first: " .. fromKeys(c))
  tick(c, 7)
  assert(fromKeys(c) == "from:fort=Bprie", "named within 5 s of its 30: " .. fromKeys(c))
  noErrors(c)
end)

test("from others: the priest who gives the strongest rank is named, not a level 30 first by GUID; of equal ranks, the first by GUID", function()
  local H = member({ name = "Hprie", class = "PRIEST", level = 60, guid = "Player-1-F9" })
  local G = member({ name = "Gprie", class = "PRIEST", level = 60, guid = "Player-1-F8" })
  local c = fromParty({ priest = { level = 30 }, more = { H, G } })
  tick(c, 31)
  assert(fromKeys(c) == "from:fort=Gprie", "a level 60, the first by GUID of the two, not Bprie (30, first of all): " .. fromKeys(c))
  assert(tipOf(c, icon(c, "own", "from:fort"))[2] == "Missing. Gprie can give it.", "its line")
  -- (Gprie out of sight: Hprie, the other 60, at the next look)
  G.visible = false
  tick(c, 6)
  assert(fromKeys(c) == "from:fort=Hprie", "Gprie out of sight: Hprie: " .. fromKeys(c))
  noErrors(c)
end)

test("from others: after the consumables; a full bar cuts the greyed ones, never food or an elixir you can use", function()
  local D1 = member({ name = "Edru", class = "DRUID", level = 60, guid = "Player-1-F5" })
  local c = fromParty({ more = { D1 }, noSpirit = true })
  local food = 12218
  c.items[food] = { name = "Monster Omelet", classID = 0, subID = 5, spell = 433 }
  c.bags = { { id = food, bag = 0, slot = 1, count = 10 } }
  local habits = {}
  -- (Sages' Intellect and Spirit, Giants' Strength, Greater Arcane's spell damage: three kins, one icon each)
  for i, x in ipairs({ { 13447, 17535 }, { 9206, 11405 }, { 13454, 17539 } }) do
    c.items[x[1]] = { name = "Elixir " .. i, classID = 0, subID = 2, spell = x[2] }
    c.bags[#c.bags + 1] = { id = x[1], bag = 0, slot = i + 1, count = 3 }
    habits[x[1]] = { hits = 2, miss = 0, spell = x[2] }
  end
  c.A.Char().consume = habits
  c.instance = "party"
  fire(c, "ZONE_CHANGED_NEW_AREA"); fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 31)
  local mine = shown(c, "mine")
  local nFood, nUse, nFrom = 0, 0, 0
  for _, r in ipairs(mine) do
    if r.key == "food" then nFood = nFood + 1 elseif r.key:find("^consume") then nUse = nUse + 1 elseif r.key:find("^from:") then nFrom = nFrom + 1 end
  end
  assert(#mine == 6 and nFood == 1 and nUse == 3 and nFrom == 2, "six: food, three elixirs, then two of the three from others: " .. keysOf(mine))
  assert(mine[1].key == "food" and mine[6].key:find("^from:"), "the greyed ones last: " .. keysOf(mine))
  noErrors(c)
end)

test("from others: Not now just after a fight stays quiet when a reminder of another's buff ends its wait; ten minutes on, both back", function()
  local c, M = fromParty()
  -- (Ice Armor gone: a Buff of yours to dismiss; Divine Spirit, after it, kept on: removed, not a hole the aura read stops at)
  table.remove(M.auras, 2)
  fire(c, "UNIT_AURA", "player"); tick(c, 31)
  assert(find(shown(c, "mine"), "self:armor") and fromKeys(c) == "from:fort=Bprie", "both: " .. keysOf(shown(c, "mine")))
  fight(c, true); tick(c, 5)
  fight(c, false); tick(c, 3)
  assert(find(shown(c, "mine"), "self:armor") and fromKeys(c) == "", "after the fight: your Buff; Fortitude waits again: " .. keysOf(shown(c, "mine")))
  c.A.Bar.Menu(icon(c, "own", "self:armor"))
  local chose = false
  for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Not now" then e.fn(); chose = true end end
  assert(chose, "the menu has Not now")
  tick(c, 1)
  assert(#shown(c, "mine") == 0, "Not now: your part quiet")
  tick(c, 35)
  assert(#shown(c, "mine") == 0, "Fortitude's wait over: still quiet, the Buff you dismissed not back: " .. keysOf(shown(c, "mine")))
  -- (a ready check within the ten minutes: Fortitude shows at once, as a ready check says; the Buff you put off stays off)
  tick(c, 200)
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(fromKeys(c) == "from:fort=Bprie" and not find(shown(c, "mine"), "self:armor"),
    "a ready check: Fortitude, not your Buff: " .. keysOf(shown(c, "mine")))
  fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
  assert(fromKeys(c) == "from:fort=Bprie" and not find(shown(c, "mine"), "self:armor"),
    "after it: still Fortitude alone: " .. keysOf(shown(c, "mine")))
  tick(c, 600)
  assert(find(shown(c, "mine"), "self:armor") and fromKeys(c) == "from:fort=Bprie", "ten minutes on: both back: " .. keysOf(shown(c, "mine")))
  noErrors(c)
end)

test("from others: the Blessing's icon is one its paladin can give: Kings for a tank (trained at 20 in Forever); Might when they are too low for it or Wisdom", function()
  local W = member({ name = "Awar", class = "WARRIOR", level = 60, guid = "Player-1-U1", assigned = "TANK" })
  -- (a level 60 paladin without Cute Auras: Kings is trained at 20 in Forever, not a talent, so theirs)
  local PAL = member({ name = "Bpal", class = "PALADIN", level = 60, guid = "Player-1-U2" })
  local c = client({ me = W, group = { W, PAL } })
  knowAll(c, "WARRIOR", 60)
  load(c)
  tick(c, 31)
  local rec = find(shown(c, "mine"), "from:bless")
  assert(rec and rec.word == "Bpal" and rec.tex == c.A.Look.SpellIcon(20217, 135995), "a tank (Kings, Might): Kings' icon: " .. tostring(rec and rec.tex))
  noErrors(c)
  -- a level 18 paladin: no Kings yet (20), Might
  local W2 = member({ name = "Dwar", class = "WARRIOR", level = 60, guid = "Player-1-U5", assigned = "TANK" })
  local PAL2 = member({ name = "Epal", class = "PALADIN", level = 18, guid = "Player-1-U6" })
  local e = client({ me = W2, group = { W2, PAL2 } })
  knowAll(e, "WARRIOR", 60)
  load(e)
  tick(e, 31)
  rec = find(shown(e, "mine"), "from:bless")
  assert(rec and rec.word == "Epal" and rec.tex == e.A.Look.SpellIcon(19740, 135906), "a level 18 paladin (Kings at 20): Might's icon: " .. tostring(rec and rec.tex))
  noErrors(e)
  local M = member({ name = "Amag", class = "MAGE", level = 60, guid = "Player-1-U3" })
  local P2 = member({ name = "Cpal", class = "PALADIN", level = 12, guid = "Player-1-U4" })
  local d = client({ me = M, group = { M, P2 }, spec = 8 })
  knowAll(d, "MAGE", 60)
  M.auras = { { id = 10157, src = "player", exp = d.clock + 3500, dur = 3600 }, { id = 10220, src = "player", exp = d.clock + 1700, dur = 1800 } }
  load(d)
  tick(d, 31)
  rec = find(shown(d, "mine"), "from:bless")
  assert(rec and rec.word == "Cpal" and rec.tex == d.A.Look.SpellIcon(19740, 135906), "a level 12 paladin (Wisdom at 14): Might's icon: " .. tostring(rec and rec.tex))
  noErrors(d)
end)

test("from others: your part off, then on: the waits start again (a buff that came and went, a ready check, while it was off)", function()
  local c, M = fromParty()
  tick(c, 31)
  assert(fromKeys(c) == "from:fort=Bprie", "named: " .. fromKeys(c))
  c.A.Window.Open("settings")
  local box = widget(c.A.Window.pages.settings, "Your buffs and weapon")
  c.click(box); tick(c, 1)
  assert(c.A.Settings().mine == false and fromKeys(c) == "", "your part off: " .. fromKeys(c))
  -- Fortitude lands while it is off, and ends
  M.auras[#M.auras + 1] = { id = 10938, exp = c.clock + 3600, dur = 3600 }
  fire(c, "UNIT_AURA", "player"); tick(c, 60)
  table.remove(M.auras)
  fire(c, "UNIT_AURA", "player"); tick(c, 5)
  c.click(box); tick(c, 1)
  assert(c.A.Settings().mine ~= false and fromKeys(c) == "", "on again: its 30 s first, not the wait from before: " .. fromKeys(c))
  tick(c, 30)
  assert(fromKeys(c) == "from:fort=Bprie", "30 s on: " .. fromKeys(c))
  -- a ready check while it is off ends no wait after
  c.click(box); tick(c, 1)
  fire(c, "READY_CHECK"); tick(c, 4)
  fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
  c.click(box); tick(c, 1)
  assert(fromKeys(c) == "", "on again after a ready check: its 30 s first: " .. fromKeys(c))
  tick(c, 31)
  assert(fromKeys(c) == "from:fort=Bprie", "30 s on: " .. fromKeys(c))
  noErrors(c)
end)

-- (a warrior owes no buff: no duty, so no 3 s look of the group's part; only the reminders' own 5 s look sees a giver
-- walk out of sight and back, which fires no event)
test("from others: a warrior's reminder: its priest (no Cute Auras) out of sight and back, no event: gone, then named again", function()
  local W = member({ name = "Awar", class = "WARRIOR", level = 60, guid = "Player-1-Y1" })
  local P = member({ name = "Bprie", class = "PRIEST", level = 60, guid = "Player-1-Y2" })
  local c = client({ me = W, group = { W, P } })
  knowAll(c, "WARRIOR", 60)
  load(c)
  tick(c, 31)
  assert(#c.A.Assign.duties == 0, "a warrior owes nothing: no 3 s look")
  assert(fromKeys(c) == "from:fort=Bprie", "named: " .. fromKeys(c))
  P.visible = false
  tick(c, 6)
  assert(fromKeys(c) == "", "out of sight, no event: gone within 5 s: " .. fromKeys(c))
  P.visible = nil
  tick(c, 36)
  assert(fromKeys(c) == "from:fort=Bprie", "back in sight, no event: named again: " .. fromKeys(c))
  noErrors(c)
end)

test("from others: a warrior's reminder: its priest running Cute Auras out of sight and back, no event: gone, then named again", function()
  local W = member({ name = "Awar", class = "WARRIOR", level = 60, guid = "Player-1-Y3" })
  local P = member({ name = "Bprie", class = "PRIEST", level = 60, guid = "Player-1-Y4" })
  local group = { W, P }
  local cw = client({ me = W, group = group })
  local cp = client({ me = P, group = group, spec = 56 })
  knowAll(cw, "WARRIOR", 60); knowAll(cp, "PRIEST", 60)
  load(cw); load(cp)
  tickAll(34)
  assert(#cw.A.Assign.duties == 0, "a warrior owes nothing: no 3 s look")
  assert(cw.A.Assign.Shared("fort") and fromKeys(cw) == "from:fort=Bprie", "the share-out's priest named: " .. fromKeys(cw))
  P.visible = false
  tickAll(6)
  assert(fromKeys(cw) == "", "out of sight, no event: gone within 5 s: " .. fromKeys(cw))
  P.visible = nil
  tickAll(40)
  assert(fromKeys(cw) == "from:fort=Bprie", "back in sight, no event: named again: " .. fromKeys(cw))
  noErrors(cw); noErrors(cp)
end)

test("from others: a level 40 takes Fortitude 5 at most (rank 6 lands on 50 and up): rank 5 on is never asked again, rank 4 asks for 5, either way", function()
  local M = member({ name = "Amag", class = "MAGE", level = 40, guid = "Player-1-X1" })
  local P = member({ name = "Bprie", class = "PRIEST", level = 60, guid = "Player-1-X2" })
  local group = { M, P }
  local c = client({ me = M, group = group, spec = 8 })
  knowAll(c, "MAGE", 40)
  local function aura(id, src) return { id = id, src = src, exp = c.clock + 3000, dur = 3600 } end
  -- (Arcane Intellect 3 and Ice Armor 2, the most a level 40 knows; Divine Spirit 3, the most that lands on a 40)
  M.auras = { aura(1461, "player"), { id = 7320, src = "player", exp = c.clock + 1700, dur = 1800 }, aura(14819), aura(10937) }
  load(c)
  tick(c, 40)
  assert(fromKeys(c) == "", "Fortitude 5 on a level 40, a priest of 60 without Cute Auras: nothing asked: " .. fromKeys(c))
  M.auras[4] = aura(2791)
  fire(c, "UNIT_AURA", "player"); tick(c, 31)
  assert(fromKeys(c) == "from:fort=Bprie", "Fortitude 4: rank 5 is theirs to give: " .. fromKeys(c))
  local line = tipOf(c, icon(c, "own", "from:fort"))[2]
  assert(line == "Rank 4 on you; Bprie can give rank 5.", line)
  -- the priest runs Cute Auras (no Fortitude of their own: their duty shows, its list with the mage)
  P.auras = {}
  local cp = client({ me = P, group = group, spec = 56 })
  knowAll(cp, "PRIEST", 60)
  load(cp)
  tickAll(12)
  line = tipOf(c, icon(c, "own", "from:fort"))[2]
  assert(line == "Rank 4 on you; Bprie gives rank 5 (shared out by Cute Auras).", line)
  local b = icon(cp, "group", "duty:fort")
  local fly = cp.env[b:GetName() .. "Fly"]
  assert(rowOf(fly, "Amag") and rowOf(fly, "Amag").state.__text == "Low rank", "the priest's list: rank 4 on the 40 is low")
  M.auras[4] = aura(10937)
  fire(c, "UNIT_AURA", "player"); fire(cp, "UNIT_AURA", tokenOf(cp, M)); tickAll(40)
  assert(fromKeys(c) == "", "Fortitude 5, the share-out's priest of 60: nothing asked: " .. fromKeys(c))
  assert(rowOf(fly, "Amag").state.__text == "on", "the priest's list: rank 5 on the 40 is on, not Low rank: " .. rowOf(fly, "Amag").state.__text)
  noErrors(c); noErrors(cp)
end)

----------------------------------------------------------------------------
-- your casts in a fight (the owner, 2026-11-24: "buffed myself during combat icon acted like it still didnt register
-- me buffing myself"), and the look after a fight the client still restricts
----------------------------------------------------------------------------
-- (a cast as the game tells it: SENT with the target's name, then SUCCEEDED unless it never landed)
local function castIn(c, target, spell, cg, landed)
  fire(c, "UNIT_SPELLCAST_SENT", "player", target, cg, spell)
  if landed ~= false then fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", cg, spell) end
end
local function sameColor(t, col) return t and t[1] == col[1] and t[2] == col[2] and t[3] == col[3] end
local function chatLine(c, pat) for i = #c.chat, 1, -1 do if c.chat[i]:find(pat) then return c.chat[i] end end end

test("in a fight: Fortitude cast on yourself reads Done, dimmed, your row on; nothing blocked; gone once the fight's look reads it", function()
  local me = member({ name = "Solo", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 2)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.lit and rec.word == "You", "Fortitude owed to yourself")
  local b = icon(c, "group", "duty:fort")
  local fly = c.env[b:GetName() .. "Fly"]
  assert(b.word.__text == "You" and b.icon.__desat == false and rowOf(fly, "You").state.__text == "missing", "before: lit, your row missing")
  fight(c, true)
  tick(c, 1)
  -- (its click, as the game tells it: SENT with your own name, SUCCEEDED; the aura lands, hidden in the fight)
  c.castEvents = true
  c.casts = {}
  c.click(b)
  c.castEvents = nil
  assert(c.casts[1] and c.casts[1].spell == 2791 and c.casts[1].unit == "player", "the click cast Fortitude 4 on you")
  table.insert(me.auras, { id = 2791, src = "player", exp = c.clock + 3600, dur = 3600 })
  fire(c, "UNIT_AURA", "player")
  tick(c, 1)
  local C = c.A.Look.C
  assert(b:IsShown() and b.word.__text == "Done" and sameColor(b.word.__textColor, C.GOOD), "the icon's word: Done: " .. b.word.__text)
  assert(b.icon.__desat == true and b.icon.__alpha == 0.55, "dimmed as a waiting icon is")
  FITS(b.word, "Done under the icon")
  local row = rowOf(fly, "You")
  assert(row and row.state.__text == "on" and sameColor(row.state.__textColor, C.GOOD) and row.icon.__desat == true, "your row: on, greyed: " .. tostring(row and row.state.__text))
  local tip = tipOf(c, b)
  assert(tip[2] == "Done in this fight.", "its tooltip says so: " .. tostring(tip[2]))
  for _, l in ipairs(tip) do assert(not l:find("^Click: "), "no click line for a buff already given: " .. l) end
  noErrors(c, "a cast in a fight")
  fight(c, false)
  tick(c, 2)
  assert(not find(shown(c, "group"), "duty:fort") and not b:IsShown(), "after the fight: the aura read, nothing owed")
  noErrors(c)
end)

-- a priest of 60 with Sacred Candles and four warriors: one dead, one out of range
local function prayerParty()
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-F1" })
  local list = { P }
  for i, n in ipairs({ "Bwar", "Cdead", "Dfall", "Efar" }) do list[i + 1] = member({ name = n, class = "WARRIOR", level = 60, guid = "Player-1-F" .. (i + 1) }) end
  list[3].dead = true
  list[5].far = true
  local c = client({ me = P, group = list })
  knowAll(c, "PRIEST", 60)
  c.items[17029] = { name = "Sacred Candle" }
  c.bags = { { id = 17029, bag = 0, slot = 1, count = 5 } }
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  assert(b and b:GetAttribute("spell") == 21564 and b.count.__text == "4", "Prayer of Fortitude 2 for the four who can take it, on you: " .. tostring(b and b.count.__text))
  return c, list, b, c.env[b:GetName() .. "Fly"]
end

test("in a fight: Prayer of Fortitude on one member marks the party's rows, never the dead, the far or one dead now; the count drops; the read after is the truth", function()
  local c, list, b, fly = prayerParty()
  fight(c, true)
  tick(c, 1)
  list[4].dead = true -- (Dfall, alive at the last read)
  castIn(c, "Bwar", 21564, "cast-p1")
  tick(c, 1)
  local C = c.A.Look.C
  for _, n in ipairs({ "You", "Bwar" }) do
    local r = rowOf(fly, n)
    assert(r.state.__text == "on" and r.icon.__desat == true and sameColor(r.state.__textColor, C.GOOD), n .. ": on: " .. r.state.__text)
  end
  assert(rowOf(fly, "Cdead").state.__text == "dead", "the dead one: dead")
  assert(rowOf(fly, "Efar").state.__text == "far", "the far one: far")
  assert(rowOf(fly, "Dfall").state.__text == "missing", "the one dead now: as last read, not on")
  assert(b.count.__text == "2", "two still miss it: " .. b.count.__text)
  assert(b.word.__text == "Done" and b.icon.__desat == true, "you, its click's member, marked: Done")
  assert(tipOf(c, b)[2] == "Done in this fight. Hover for the others.", "the others are in its list")
  noErrors(c, "Prayer in a fight")
  -- (the client's truth after it: on you; taken off Bwar meanwhile; Dfall raised)
  table.insert(list[1].auras, { id = 21564, src = "player", exp = c.clock + 3600, dur = 3600 })
  list[4].dead = nil
  fight(c, false)
  tick(c, 2)
  local rec = find(shown(c, "group"), "duty:fort")
  assert(rec and rec.lit and rec.word == "Bwar" and rec.count == 3, "Bwar named again from the read: " .. tostring(rec and rec.word))
  assert(b.word.__text == "Bwar" and b.icon.__desat == false and b.icon.__alpha == 1 and b.count.__text == "3", "the icon painted from the read, no mark left")
  local r = rowOf(fly, "Bwar")
  assert(r.state.__text == "missing" and r.icon.__desat == false and sameColor(r.state.__textColor, C.QUEST), "Bwar's row from the read: " .. r.state.__text)
  assert(rowOf(fly, "You").state.__text == "on", "yours on")
  noErrors(c)
end)

test("in a fight, no mark: a cast sent and never landed, a target that can't be told, no SENT, a lower rank, a spell not the duty's, a hidden name guessed from your target", function()
  local c, list, b, fly = prayerParty()
  fight(c, true)
  tick(c, 1)
  local function unchanged(what)
    assert(b.word.__text == "You" and b.icon.__desat == false and b.count.__text == "4", what .. ": the icon as it was: " .. b.word.__text .. " " .. b.count.__text)
    for _, n in ipairs({ "You", "Bwar" }) do assert(rowOf(fly, n).state.__text == "missing", what .. ": " .. n .. " still missing") end
  end
  castIn(c, "Bwar", 21564, "cast-n1", false)
  tick(c, 1); unchanged("sent, never landed")
  -- (the name hidden, no target or mouseover that is a member)
  castIn(c, secret(), 21564, "cast-n2")
  tick(c, 1); unchanged("a hidden name")
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-n3", 21564)
  tick(c, 1); unchanged("no SENT")
  -- (a lower rank than the row's: Fortitude 1 on Bwar, Low rank once read; Inner Fire 1 under the 6 its icon casts)
  castIn(c, "Bwar", 1243, "cast-n7")
  castIn(c, "", 588, "cast-n8")
  tick(c, 1); unchanged("a lower rank")
  local inner = icon(c, "own", "self:innerfire")
  assert(inner and inner.word.__text == "Buff", "Inner Fire 1: yours still asks for rank 6")
  -- (Divine Spirit and Inner Fire on yourself: not Fortitude's; Divine Spirit's own icon is Done, and yours of Inner Fire)
  castIn(c, "Apri", 27841, "cast-n4")
  castIn(c, "", 10952, "cast-n5")
  tick(c, 1); unchanged("other spells")
  assert(icon(c, "group", "duty:spirit").word.__text == "Done", "Divine Spirit's own icon marked")
  assert(inner.word.__text == "Done" and inner.icon.__desat == true, "Inner Fire 6: yours Done (hidden in the fight)")
  -- (the name hidden, your target a member: a guess (a mouseover macro or a self-cast key casts elsewhere), no mark)
  c.units.target = list[2]
  castIn(c, secret(), 10938, "cast-n6")
  tick(c, 1); unchanged("a hidden name, your target a member")
  -- (Fortitude 6 told on Bwar: Bwar's row on, the icon still yours)
  castIn(c, "Bwar", 10938, "cast-n9")
  tick(c, 1)
  assert(rowOf(fly, "Bwar").state.__text == "on" and rowOf(fly, "You").state.__text == "missing", "one rank: its target alone")
  assert(b.word.__text == "You" and b.icon.__desat == false and b.count.__text == "3", "the icon still buffs you, three to go: " .. b.count.__text)
  assert(tipOf(c, b)[2] == "In this fight: 1 done, 3 to go.", "said so: " .. tostring(tipOf(c, b)[2]))
  noErrors(c)
end)

test("in a fight: a raid's Prayer marks the target's subgroup alone; a Greater blessing the target's class alone", function()
  -- (a raid of ten, one priest giving all of it: Prayer of Fortitude on R7 of subgroup two)
  local list = {}
  for i = 1, 10 do list[i] = member({ name = "R" .. i, class = i == 1 and "PRIEST" or "WARRIOR", level = 60, guid = string.format("Player-1-%02d", i), sub = i <= 5 and 1 or 2 }) end
  local c = client({ me = list[1], group = list, raid = true })
  knowAll(c, "PRIEST", 60)
  c.items[17029] = { name = "Sacred Candle" }
  c.bags = { { id = 17029, bag = 0, slot = 1, count = 5 } }
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  assert(b and b.count.__text == "10" and b.word.__text == "You", "all ten owed, Prayer on you first")
  local fly = c.env[b:GetName() .. "Fly"]
  fight(c, true)
  tick(c, 1)
  castIn(c, "R7", 21564, "cast-r1")
  tick(c, 1)
  for i = 2, 10 do
    local want = i >= 6 and "on" or "missing"
    assert(rowOf(fly, "R" .. i).state.__text == want, "R" .. i .. ": " .. want .. ": " .. rowOf(fly, "R" .. i).state.__text)
  end
  assert(b.word.__text == "You" and b.icon.__desat == false and b.count.__text == "5", "your subgroup still to do: " .. b.count.__text)
  noErrors(c, "a raid's Prayer")
  -- (a paladin of a party owing Might to a rogue and three warriors, the rogue first: Greater Might cast on a warrior)
  WORLD = {}
  local PAL = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-G1" })
  local party = { PAL }
  for i, n in ipairs({ "Bwar", "Cwar", "Dwar" }) do party[i + 1] = member({ name = n, class = "WARRIOR", level = 60, guid = "Player-1-G" .. (i + 1) }) end
  party[5] = member({ name = "Erog", class = "ROGUE", level = 60, guid = "Player-1-G5" })
  c = client({ me = PAL, group = party, spec = 594 })
  knowAll(c, "PALADIN", 60)
  c.known[25916] = true
  c.items[21177] = { name = "Symbol of Kings" }
  c.bags = { { id = 21177, bag = 0, slot = 1, count = 20 } }
  load(c)
  tick(c, 12)
  b = icon(c, "group", "duty:bless:might")
  assert(b and b.word.__text == "Erog" and b.count.__text == "4", "Might owed to four, the rogue first: " .. tostring(b and b.word.__text))
  fly = c.env[b:GetName() .. "Fly"]
  fight(c, true)
  tick(c, 1)
  castIn(c, "Cwar", 25916, "cast-g1")
  tick(c, 1)
  for _, n in ipairs({ "Bwar", "Cwar", "Dwar" }) do assert(rowOf(fly, n).state.__text == "on", n .. ": on") end
  assert(rowOf(fly, "Erog").state.__text == "missing", "the rogue: not a warrior")
  assert(b.word.__text == "Erog" and b.icon.__desat == false and b.count.__text == "", "the rogue still to do, one left (no badge for one)")
  assert(tipOf(c, b)[2] == "In this fight: 3 done, 1 to go.", "said so: " .. tostring(tipOf(c, b)[2]))
  noErrors(c)
end)

-- a priest of 40 owing herself Fortitude, Inner Fire to put up: in a fight Fortitude lands from another priest and
-- she casts Inner Fire; the fight ends with the client still restricting, or keeping auras secret, for 3 s
local function lateFight(how)
  local me = member({ name = "Late", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 2)
  assert(find(shown(c, "group"), "duty:fort") and find(shown(c, "mine"), "self:innerfire"), "Fortitude owed, Inner Fire asked")
  fight(c, true)
  tick(c, 1)
  table.insert(me.auras, { id = 2791, exp = c.clock + 3600, dur = 3600 })
  table.insert(me.auras, { id = 1006, src = "player", exp = c.clock + 600, dur = 600 })
  castIn(c, "", 1006, "cast-l1")
  fire(c, "UNIT_AURA", "player")
  tick(c, 1)
  if how == "restrict" then c.restrict = { [c.env.Enum.AddOnRestrictionType.Combat] = true } else c.secretAuras = true end
  fight(c, false)
  return c
end
local function stale(c)
  local mine = icon(c, "own", "self:innerfire")
  return find(shown(c, "group"), "duty:fort") ~= nil and icon(c, "group", "duty:fort"):IsShown() and mine:IsShown() and mine.word.__text == "Done"
end

test("after a fight the client still restricts for 3 s: the bar looks again as the restriction lifts, and without its event within a second", function()
  -- the Combat restriction, lifted with ADDON_RESTRICTION_STATE_CHANGED
  local c = lateFight("restrict")
  tick(c, 3.5)
  assert(c.env.CuteAurasBarOwn:IsShown(), "yours shows again out of the fight")
  local mine = icon(c, "own", "self:innerfire")
  assert(stale(c) and mine.icon.__desat == true and mine.icon.__alpha == 0.55, "refused: Fortitude still asked, your Inner Fire Done, dimmed")
  c.lift(c.env.Enum.AddOnRestrictionType.Combat)
  tick(c, 0.2)
  assert(not find(shown(c, "group"), "duty:fort") and not find(shown(c, "mine"), "self:innerfire"), "the restriction lifted: looked again at once")
  assert(not icon(c, "group", "duty:fort"):IsShown() and not mine:IsShown(), "both gone")
  noErrors(c, "lifted")
  -- auras kept secret, lifted with no event: the next second's try
  WORLD = {}
  c = lateFight("secret")
  tick(c, 3.5)
  assert(stale(c), "auras secret: refused")
  c.secretAuras = nil
  tick(c, 0.2)
  assert(stale(c), "no event: not yet")
  tick(c, 0.6)
  assert(not find(shown(c, "group"), "duty:fort") and not find(shown(c, "mine"), "self:innerfire"), "the second's try went through")
  noErrors(c)
end)

test("/cauras diag: the look after the last fight, refused how often, why, and when it went through", function()
  local me = member({ name = "Diag", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 2)
  c.env.SlashCmdList.CUTEAURAS("diag")
  assert(chatLine(c, "After a fight: no fight yet%.$"), "before any fight")
  fight(c, true); tick(c, 1)
  c.restrict = { [c.env.Enum.AddOnRestrictionType.Encounter] = true }
  fight(c, false)
  tick(c, 2.5)
  c.env.SlashCmdList.CUTEAURAS("diag")
  -- (refused: the look 1 s after the fight and each second's try, and any other refresh asked meanwhile)
  local line = chatLine(c, "After the last fight")
  local n = tonumber(line and line:match("After the last fight: (%d+) refreshes refused, by Encounter; still waiting%.$"))
  assert(n and n >= 2, "still waiting: " .. tostring(line))
  c.restrict = nil
  c.secretAuras = true
  tick(c, 1)
  c.secretAuras = nil
  c.lift(c.env.Enum.AddOnRestrictionType.Encounter)
  tick(c, 0.2)
  c.env.SlashCmdList.CUTEAURAS("diag")
  line = chatLine(c, "After the last fight")
  local m = tonumber(line and line:match("After the last fight: (%d+) refreshes refused, by Encounter and auras secret; read again 3%.%d s after it%.$"))
  assert(m and m > n, "read again: " .. tostring(line))
  noErrors(c)
end)

----------------------------------------------------------------------------
-- the marks, reviewed: only what a cast reaches, let go when it is taken off, the member a cast went to told exactly
----------------------------------------------------------------------------
local function namedRows(fly, name)
  local n = 0
  for _, r in ipairs(fly.rows) do if r:IsShown() and r.name.__text == name then n = n + 1 end end
  return n
end
local function marksOf(c, key)
  local rec, t = find(shown(c, "group"), key), {}
  for _, x in ipairs(rec and rec.flyout or {}) do if x.mark then t[#t + 1] = x.name end end
  table.sort(t)
  return table.concat(t, ","), rec
end
-- a priest of 60 with Sacred Candles and four warriors, all alive and in range
local function prayerFive()
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-V1" })
  local list = { P }
  for i, n in ipairs({ "Bwar", "Cwar", "Dwar", "Ewar" }) do list[i + 1] = member({ name = n, class = "WARRIOR", level = 60, guid = "Player-1-V" .. (i + 1) }) end
  local c = client({ me = P, group = list })
  knowAll(c, "PRIEST", 60)
  c.items[17029] = { name = "Sacred Candle" }
  c.bags = { { id = 17029, bag = 0, slot = 1, count = 5 } }
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  assert(b and b:GetAttribute("spell") == 21564 and b.count.__text == "5", "Prayer of Fortitude 2 for all five")
  return c, list, b, c.env[b:GetName() .. "Fly"]
end

test("in a fight: a member leaves; the row left on no one stays '?', never painted back to its old member by a mark", function()
  local c, list, b, fly = prayerFive()
  fight(c, true)
  tick(c, 1)
  -- (Bwar leaves: the party's tokens shift, party4 now no one; its row was Ewar's)
  table.remove(list, 2)
  seat(c)
  fire(c, "GROUP_ROSTER_UPDATE")
  tick(c, 1)
  local nobody
  for _, r in ipairs(fly.rows) do if r:IsShown() and r:GetAttribute("unit") == "party4" then nobody = r end end
  assert(nobody and nobody.name.__text == "?" and nobody.state.__text == "", "party4's row: no one")
  assert(namedRows(fly, "Ewar") == 1, "Ewar once, on the row that now reaches him")
  castIn(c, "Apri", 21564, "cast-v1")
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "Cwar,Dwar,Ewar,You", "the four still here marked: " .. marksOf(c, "duty:fort"))
  assert(nobody.name.__text == "?" and nobody.state.__text == "" and not nobody.glow:IsShown(), "party4's row still no one: " .. nobody.name.__text .. " " .. nobody.state.__text)
  assert(namedRows(fly, "Ewar") == 1, "Ewar still once: " .. namedRows(fly, "Ewar"))
  assert(rowOf(fly, "You").state.__text == "on", "your row, still yours: on")
  noErrors(c)
end)

test("in a fight: a group rank marks no one it can't land on: Prayer of Fortitude 2 leaves a level 45 missing, Prayer 1 reaches him", function()
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-Q1" })
  local list = { P }
  for i, lv in ipairs({ 45, 60, 60, 60 }) do list[i + 1] = member({ name = "Low" .. i, class = "WARRIOR", level = lv, guid = "Player-1-Q" .. (i + 1) }) end
  list[2].name = "Young"
  local c = client({ me = P, group = list })
  knowAll(c, "PRIEST", 60)
  c.items[17028], c.items[17029] = { name = "Holy Candle" }, { name = "Sacred Candle" }
  c.bags = { { id = 17028, bag = 0, slot = 1, count = 20 }, { id = 17029, bag = 0, slot = 2, count = 20 } }
  P.auras = { { id = 10938, src = "player", exp = c.clock + 3000, dur = 3600 } }
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  assert(b and b:GetAttribute("spell") == 21564 and b.count.__text == "4" and b.word.__text ~= "Young", "Prayer 2 on a 60, four missing it")
  local fly = c.env[b:GetName() .. "Fly"]
  fight(c, true)
  tick(c, 1)
  c.castEvents = true
  c.casts = {}
  c.click(b)
  c.castEvents = nil
  assert(c.casts[1] and c.casts[1].spell == 21564, "the click cast Prayer 2")
  tick(c, 1)
  assert(rowOf(fly, "Young").state.__text == "missing", "the 45: Prayer 2 never lands on him: " .. rowOf(fly, "Young").state.__text)
  for i = 2, 4 do assert(rowOf(fly, "Low" .. i).state.__text == "on", "Low" .. i .. ": on") end
  assert(b.word.__text == "Done" and b.count.__text == "", "the three it reaches done, the 45 left (no badge for one)")
  assert(tipOf(c, b)[2] == "Done in this fight. Hover for the others.", "the 45 is in its list: " .. tostring(tipOf(c, b)[2]))
  -- (Prayer 2 cast on him: it lands on the others, never on him)
  castIn(c, "Young", 21564, "cast-q2")
  tick(c, 1)
  assert(rowOf(fly, "Young").state.__text == "missing", "Prayer 2 on the 45 himself: still missing")
  -- (Prayer 1, learned at 48: it lands on a 45, at Fortitude 5's power, his best)
  castIn(c, "Young", 21562, "cast-q3")
  tick(c, 1)
  assert(rowOf(fly, "Young").state.__text == "on" and b.word.__text == "Done", "Prayer 1 reaches him")
  noErrors(c)
end)

test("in a fight: a mark let go: a Hand or another blessing of yours on them, a Greater of another kind on their class, a death; row and icon as last read", function()
  local PAL = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-H1" })
  local party = { PAL }
  for i, n in ipairs({ "Bwar", "Cwar" }) do party[i + 1] = member({ name = n, class = "WARRIOR", level = 60, guid = "Player-1-H" .. (i + 1) }) end
  party[4] = member({ name = "Erog", class = "ROGUE", level = 60, guid = "Player-1-H4" })
  local c = client({ me = PAL, group = party, spec = 594 })
  knowAll(c, "PALADIN", 60)
  c.known[25898] = true
  c.items[21177] = { name = "Symbol of Kings" }
  c.bags = { { id = 21177, bag = 0, slot = 1, count = 20 } }
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:bless:might")
  assert(b and b.count.__text == "3", "Might owed to three: " .. tostring(b and b.count.__text))
  local fly = c.env[b:GetName() .. "Fly"]
  local pick, why, clickLine = b.word.__text, tipOf(c, b)[2], nil
  for _, l in ipairs(tipOf(c, b)) do if l:find("^Click: ") then clickLine = l end end
  assert(clickLine, "a click line as read")
  local C = c.A.Look.C
  local function asRead(what)
    assert(b.word.__text == pick and b.icon.__desat == false and b.count.__text == "3", what .. ": the icon as read: " .. b.word.__text .. " " .. b.count.__text)
    local tip = tipOf(c, b)
    assert(tip[2] == why, what .. ": its words as read: " .. tostring(tip[2]))
    local has = false
    for _, l in ipairs(tip) do if l == clickLine then has = true end end
    assert(has, what .. ": its click line back")
    for _, n in ipairs({ "Bwar", "Cwar", "Erog" }) do
      local r = rowOf(fly, n)
      assert(r.state.__text == "missing" and r.icon.__desat == false and sameColor(r.state.__textColor, C.QUEST), what .. ": " .. n .. " missing: " .. r.state.__text)
    end
  end
  fight(c, true)
  tick(c, 1)
  -- (Might on the one its click blesses: Done; then Blessing of Protection on them takes it off)
  castIn(c, pick, 25291, "cast-h1")
  tick(c, 1)
  assert(b.word.__text == "Done" and rowOf(fly, pick).state.__text == "on", "Might on " .. pick .. ": Done")
  castIn(c, pick, 10278, "cast-h2")
  tick(c, 1)
  asRead("a Hand on them")
  -- (Might on each warrior; Kings on Cwar takes his off; Greater Kings on Cwar every warrior's, Bwar's too)
  castIn(c, "Bwar", 25291, "cast-h3")
  castIn(c, "Cwar", 25291, "cast-h4")
  tick(c, 1)
  assert(rowOf(fly, "Bwar").state.__text == "on" and rowOf(fly, "Cwar").state.__text == "on", "both warriors on")
  castIn(c, "Cwar", 20217, "cast-h5")
  tick(c, 1)
  assert(rowOf(fly, "Cwar").state.__text == "missing" and rowOf(fly, "Bwar").state.__text == "on", "Kings on Cwar: his Might gone, Bwar's kept")
  castIn(c, "Cwar", 25898, "cast-h6")
  tick(c, 1)
  asRead("Greater Kings on the warriors")
  -- (Might on Erog, then he dies: every buff gone)
  castIn(c, "Erog", 25291, "cast-h7")
  tick(c, 1)
  assert(rowOf(fly, "Erog").state.__text == "on", "Erog on")
  party[4].dead = true
  fire(c, "UNIT_HEALTH", "party3")
  tick(c, 1)
  asRead("a death")
  noErrors(c, "let go")
  -- (yours: Inner Fire Done in a fight, then you die)
  WORLD = {}
  local me = member({ name = "Solo", class = "PRIEST", level = 40 })
  c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 2)
  local inner = icon(c, "own", "self:innerfire")
  assert(inner.word.__text == "Buff", "Inner Fire asked")
  fight(c, true)
  tick(c, 1)
  castIn(c, "", 1006, "cast-h8")
  tick(c, 1)
  assert(inner.word.__text == "Done" and inner.icon.__desat == true, "Inner Fire Done")
  me.dead = true
  fire(c, "UNIT_HEALTH", "player")
  tick(c, 1)
  assert(inner.word.__text == "Buff" and inner.icon.__desat == false and inner.icon.__alpha == 1, "you died: asked again: " .. inner.word.__text)
  noErrors(c)
end)

test("in a fight: a name told that is no member's is no one, not your target or mouseover; a hidden name from the bar's own click is the member it clicked; from elsewhere, no one", function()
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-W1" })
  local list = { P }
  for i, n in ipairs({ "Bwar", "Cwar", "Dwar" }) do list[i + 1] = member({ name = n, class = "WARRIOR", level = 60, guid = "Player-1-W" .. (i + 1) }) end
  local c = client({ me = P, group = list })
  knowAll(c, "PRIEST", 60)
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  local fly = c.env[b:GetName() .. "Fly"]
  assert(b.word.__text == "You" and b.count.__text == "4", "Fortitude owed to four, you first")
  fight(c, true)
  tick(c, 1)
  -- (a hunter's pet buffed, your target; your mouse resting on Bwar, then on you)
  c.units.target = member({ name = "Wolf", class = "HUNTER", level = 60, guid = "Pet-0-1" })
  c.units.mouseover = list[2]
  castIn(c, "Wolf", 10938, "cast-w1")
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "" and rowOf(fly, "Bwar").state.__text == "missing" and b.count.__text == "4", "the pet: no one marked: " .. marksOf(c, "duty:fort"))
  c.units.mouseover = P
  castIn(c, "Wolf", 10938, "cast-w2")
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "" and b.word.__text == "You", "the mouse on you: still no one")
  -- (the bar's own row for Bwar clicked, Cwar your target, the name hidden: Bwar, as the click cast on him)
  c.units.target, c.units.mouseover = list[3], nil
  c.castEvents, c.hideNames = true, true
  c.casts = {}
  c.click(rowOf(fly, "Bwar"))
  c.castEvents, c.hideNames = nil, nil
  assert(c.casts[1] and c.casts[1].unit == "party1", "the row cast on Bwar")
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "Bwar" and rowOf(fly, "Cwar").state.__text == "missing", "Bwar marked, not your target: " .. marksOf(c, "duty:fort"))
  -- (the icon itself, its click on you: you)
  c.castEvents, c.hideNames = true, true
  c.click(b)
  c.castEvents, c.hideNames = nil, nil
  assert(c.casts[2] and c.casts[2].unit == "player", "the icon cast on you")
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "Bwar,You" and b.word.__text == "Done", "you marked, not your target: " .. marksOf(c, "duty:fort"))
  -- (a hidden name from elsewhere, after: Cwar your target, a guess, marks no one)
  castIn(c, secret(), 10938, "cast-w3")
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "Bwar,You", "no mark from your target for a hidden name: " .. marksOf(c, "duty:fort"))
  noErrors(c)
end)

test("in a fight: the icon's click is Prayer; a single Fortitude on its member alone leaves it lit, Done once everyone it reaches has it", function()
  local c, list, b, fly = prayerParty()
  local clickLine
  for _, l in ipairs(tipOf(c, b)) do if l:find("^Click: ") then clickLine = l end end
  fight(c, true)
  tick(c, 1)
  c.castEvents = true
  c.casts = {}
  c.click(rowOf(fly, "You"))
  c.castEvents = nil
  assert(c.casts[1] and c.casts[1].spell == 10938 and c.casts[1].unit == "player", "your row cast Fortitude 6 on you")
  tick(c, 1)
  assert(rowOf(fly, "You").state.__text == "on" and rowOf(fly, "Bwar").state.__text == "missing", "you on, Bwar still missing")
  assert(b.word.__text == "You" and b.icon.__desat == false and b.count.__text == "3", "its Prayer still reaches the others: lit, three to go: " .. b.word.__text)
  local tip = tipOf(c, b)
  assert(tip[2] == "In this fight: 1 done, 3 to go.", "said so: " .. tostring(tip[2]))
  local has = false
  for _, l in ipairs(tip) do if l == clickLine then has = true end end
  assert(has, "its click line kept: " .. tostring(clickLine))
  -- (Bwar and Dfall too: everyone the Prayer reaches has it; Efar, out of range, left in its list)
  castIn(c, "Bwar", 10938, "cast-s1")
  tick(c, 1)
  assert(b.word.__text == "You", "Dfall still to do")
  castIn(c, "Dfall", 10938, "cast-s2")
  tick(c, 1)
  assert(b.word.__text == "Done" and b.icon.__desat == true and b.count.__text == "", "Done: " .. b.word.__text)
  assert(tipOf(c, b)[2] == "Done in this fight. Hover for the others.", "Efar in its list")
  noErrors(c)
end)

test("in a fight: a member who left gets no mark from a Prayer; one dead now is read by their unit now, not the read's", function()
  local c, list, b, fly = prayerFive()
  fight(c, true)
  tick(c, 1)
  -- (Bwar leaves: Cwar on party1, Dwar on party2, Ewar on party3; then Dwar dies)
  table.remove(list, 2)
  seat(c)
  fire(c, "GROUP_ROSTER_UPDATE")
  tick(c, 1)
  list[3].dead = true
  castIn(c, "Apri", 21564, "cast-l1")
  tick(c, 1)
  local marks, rec = marksOf(c, "duty:fort")
  assert(marks == "Cwar,Ewar,You", "the living still here: " .. marks)
  assert(rec.count == 2 and b.count.__text == "2", "Bwar and Dwar still to go: " .. tostring(rec.count))
  assert(b.word.__text == "Done", "everyone the Prayer reaches has it")
  -- (the rows the shift renamed keep their blank state: none reads on but yours)
  for _, r in ipairs(fly.rows) do
    if r:IsShown() and r.name.__text ~= "You" then assert(r.state.__text == "", r.name.__text .. ": " .. r.state.__text) end
  end
  noErrors(c)
end)

test("after a fight, the client still restricting: a cast reads Done, not Done in this fight; so far, not in this fight", function()
  local me = member({ name = "Late", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 2)
  fight(c, true)
  tick(c, 1)
  c.restrict = { [c.env.Enum.AddOnRestrictionType.Combat] = true }
  fight(c, false)
  tick(c, 2)
  assert(not c.A.Fighting() and c.A.Bar.Blocked(), "out of the fight, the bar still can't read")
  local mine = icon(c, "own", "self:innerfire")
  castIn(c, "", 1006, "cast-d1")
  tick(c, 0.5)
  assert(mine.word.__text == "Done" and tipOf(c, mine)[2] == "Done.", "Inner Fire: " .. tostring(tipOf(c, mine)[2]))
  local b = icon(c, "group", "duty:fort")
  castIn(c, "Late", 2791, "cast-d2")
  tick(c, 0.5)
  assert(b.word.__text == "Done" and tipOf(c, b)[2] == "Done.", "Fortitude: " .. tostring(tipOf(c, b)[2]))
  noErrors(c, "solo")
  WORLD = {}
  local fly
  c, _, b, fly = prayerParty()
  fight(c, true)
  tick(c, 1)
  c.restrict = { [c.env.Enum.AddOnRestrictionType.Combat] = true }
  fight(c, false)
  tick(c, 2)
  castIn(c, "Bwar", 10938, "cast-d3")
  tick(c, 0.5)
  assert(rowOf(fly, "Bwar").state.__text == "on" and tipOf(c, b)[2] == "So far: 1 done, 3 to go.", "the party: " .. tostring(tipOf(c, b)[2]))
  noErrors(c)
end)

test("out of a fight, auras secret: a cast's mark goes with the first read that goes through, whatever asked for it", function()
  local me = member({ name = "Hush", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 2)
  local inner = icon(c, "own", "self:innerfire")
  assert(inner:IsShown() and inner.word.__text == "Buff", "Inner Fire asked")
  -- (the client keeps auras secret out of a fight: the bar can't read; Inner Fire cast, its aura not told yet)
  c.secretAuras = true
  castIn(c, "", 1006, "cast-x1")
  tick(c, 0.3)
  assert(inner.word.__text == "Done", "marked Done")
  -- (secret no more; the first refresh that goes through is the camp's, for a bag's cooldown)
  c.secretAuras = nil
  fire(c, "BAG_UPDATE_COOLDOWN")
  tick(c, 0.2)
  assert(inner.word.__text == "Buff" and inner.icon.__desat == false, "read again: no aura on you, asked again: " .. inner.word.__text)
  noErrors(c)
end)

----------------------------------------------------------------------------
-- the marks, reviewed again: told only by a name or a click of ours (a queued click too, the rebuff and restore
-- cards'), let go by any blessing of yours, Feign Death no death; a death's watch and a lifted restriction kept cheap
----------------------------------------------------------------------------
-- a priest of 60 with Fortitude (and Divine Spirit) herself, Fortitude missing on a tank, a rogue, a warrior and a mage
local function fortFour()
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-K1" })
  local T = member({ name = "Btank", class = "WARRIOR", level = 60, guid = "Player-1-K2", assigned = "TANK" })
  local R = member({ name = "Crog", class = "ROGUE", level = 60, guid = "Player-1-K3" })
  local W = member({ name = "Dwar", class = "WARRIOR", level = 60, guid = "Player-1-K4" })
  local M = member({ name = "Emag", class = "MAGE", level = 60, guid = "Player-1-K5" })
  local c = client({ me = P, group = { P, T, R, W, M } })
  P.auras = { { id = 10938, src = "player", exp = c.clock + 3500, dur = 3600 }, { id = 27841, src = "player", exp = c.clock + 3500, dur = 3600 } }
  knowAll(c, "PRIEST", 60)
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  assert(b and b.count.__text == "4" and b.word.__text ~= "You", "Fortitude 6 owed to the four: " .. tostring(b and b.count.__text))
  local g = { P = P, T = T, R = R, W = W, M = M }
  local pick
  for _, m in pairs(g) do if m.name == b.word.__text then pick = m end end
  return c, g, b, c.env[b:GetName() .. "Fly"], pick
end

test("in a fight: a hidden name not from a click of ours is a guess and marks no one: your target, your mouseover, yourself; never a false Done", function()
  local c, g, b, fly, pick = fortFour()
  local other = pick == g.R and g.W or g.R
  fight(c, true)
  tick(c, 1)
  -- (the pick your target, a /cast [@mouseover,help] Fortitude on another: it lands on them, the name hidden)
  c.units.target, c.units.mouseover = pick, other
  castIn(c, secret(), 10938, "cast-g1")
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "", "your target not marked: " .. marksOf(c, "duty:fort"))
  assert(b.word.__text == pick.name and b.count.__text == "4" and rowOf(fly, pick.name).state.__text == "missing", "no Done: " .. b.word.__text)
  assert(rowOf(fly, other.name).state.__text == "missing", "the one it landed on: as read")
  -- (an enemy your target, the mouse on a member's frame: the self-cast key lands on you)
  c.units.target = member({ name = "Ogre", class = "WARRIOR", level = 60, guid = "Creature-0-99" })
  local friend = c.env.UnitIsFriend
  c.env.UnitIsFriend = function(_, u) return u ~= "target" end
  castIn(c, secret(), 10938, "cast-g2")
  c.env.UnitIsFriend = friend
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == "", "your mouseover not marked: " .. marksOf(c, "duty:fort"))
  noErrors(c, "a guess")
  -- (yourself your target, Dampen Magic, a habit of yours, cast by a mouseover macro on Bob: yours not Done)
  WORLD = {}
  local me = member({ name = "Damp", class = "MAGE", level = 60, guid = "Player-1-M1" })
  local bob = member({ name = "Bob", class = "WARRIOR", level = 60, guid = "Player-1-M2" })
  c = client({ me = me, group = { me, bob } })
  SPELL_NAMES[604], SPELL_NAMES[8450] = "Dampen Magic", "Dampen Magic"
  c.known[604], c.known[8450] = true, true
  load(c)
  tick(c, 1)
  local function on(id) me.auras[#me.auras + 1] = { id = id, src = "player", exp = c.clock + 600, dur = 600 }; fire(c, "UNIT_AURA", "player"); tick(c, 2) end
  local function off(id) for i = #me.auras, 1, -1 do if me.auras[i].id == id then table.remove(me.auras, i) end end; fire(c, "UNIT_AURA", "player"); tick(c, 2) end
  on(8450); off(8450); on(8450); off(8450); on(8450); off(8450)
  local hb = icon(c, "own", "habit:Dampen Magic")
  assert(hb and hb:IsShown() and hb.word.__text == "Buff", "Dampen Magic asked: " .. tostring(hb and hb.word.__text))
  fight(c, true)
  tick(c, 1)
  c.units.target, c.units.mouseover = me, bob
  castIn(c, secret(), 8450, "cast-g3")
  tick(c, 1)
  assert(hb.word.__text == "Buff", "a cast on Bob: yours still asked: " .. hb.word.__text)
  -- (told on you: Done)
  castIn(c, "Damp", 8450, "cast-g4")
  tick(c, 1)
  assert(hb.word.__text == "Done", "on you: Done: " .. hb.word.__text)
  noErrors(c)
end)

test("in a fight: a click the game queued behind the global cooldown is told by its SENT a moment on; past the spell queue window, after another SENT or of another spell, no one", function()
  local c, g, b, fly = fortFour()
  local spirit = icon(c, "group", "duty:spirit")
  local sfly = spirit and c.env[spirit:GetName() .. "Fly"]
  assert(sfly and rowOf(sfly, "Emag") and rowOf(sfly, "Emag").state.__text == "missing", "Divine Spirit owed to the mage")
  fight(c, true)
  tick(c, 1)
  c.units.target = g.T -- (a friendly member: a guess would name the tank)
  -- (Crog's row clicked, its cast queued: SENT 0.3 s on, the name hidden)
  c.casts = {}
  c.click(rowOf(fly, "Crog"))
  assert(c.casts[1] and c.casts[1].spell == 10938 and c.units[c.casts[1].unit] == g.R, "the row casts Fortitude 6 on Crog")
  tick(c, 0.3)
  castIn(c, secret(), 10938, "cast-q1")
  tick(c, 0.5)
  assert(marksOf(c, "duty:fort") == "Crog", "queued: Crog: " .. marksOf(c, "duty:fort"))
  -- (Dwar's row clicked, refused: a SENT 0.6 s on is another cast's; a smaller window, 0.2 s on)
  c.click(rowOf(fly, "Dwar"))
  tick(c, 0.6)
  castIn(c, secret(), 10938, "cast-q2")
  tick(c, 0.5)
  assert(marksOf(c, "duty:fort") == "Crog", "past the window: " .. marksOf(c, "duty:fort"))
  c.queueWindow = 50
  c.click(rowOf(fly, "Dwar"))
  tick(c, 0.2)
  castIn(c, secret(), 10938, "cast-q3")
  c.queueWindow = nil
  tick(c, 0.5)
  assert(marksOf(c, "duty:fort") == "Crog", "past a 50 ms window: " .. marksOf(c, "duty:fort"))
  -- (Dwar's row clicked, another SENT first: the click is that one's)
  c.click(rowOf(fly, "Dwar"))
  castIn(c, secret(), 6346, "cast-q4") -- (Fear Ward, no duty of hers)
  castIn(c, secret(), 10938, "cast-q5")
  tick(c, 0.5)
  assert(marksOf(c, "duty:fort") == "Crog", "another SENT first: " .. marksOf(c, "duty:fort"))
  -- (Dwar's row right-clicked: it casts nothing, so it tells nothing)
  c.click(rowOf(fly, "Dwar"), "RightButton")
  castIn(c, secret(), 10938, "cast-q7")
  tick(c, 0.5)
  assert(marksOf(c, "duty:fort") == "Crog", "a right-click: " .. marksOf(c, "duty:fort"))
  -- (Emag's Fortitude row clicked, Divine Spirit sent: not the row's spell, Emag's Divine Spirit as read)
  c.click(rowOf(fly, "Emag"))
  castIn(c, secret(), 27841, "cast-q6")
  tick(c, 0.5)
  assert(rowOf(sfly, "Emag").state.__text == "missing" and marksOf(c, "duty:spirit") == "", "another spell: no one: " .. marksOf(c, "duty:spirit"))
  noErrors(c)
end)

test("in a fight: the rebuff card's click is told with the name hidden: the member it cast on, not your target; the restore card's after a fight the client restricts", function()
  local c, g, b, fly, pick = fortFour()
  local other = pick == g.R and g.W or g.R
  local rb = c.env.CuteAurasRebuff
  fight(c, true)
  tick(c, 1)
  other.dead = true; tick(c, 1); other.dead = false; tick(c, 1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == other, "the rebuff card for " .. other.name)
  c.units.target = pick
  c.castEvents, c.hideNames = true, true
  c.casts = {}
  c.click(rb)
  c.castEvents, c.hideNames = nil, nil
  assert(c.casts[1] and c.units[c.casts[1].unit] == other, "the card cast on " .. other.name)
  tick(c, 1)
  assert(marksOf(c, "duty:fort") == other.name, "the card's member marked, not your target: " .. marksOf(c, "duty:fort"))
  assert(b.word.__text == pick.name and rowOf(fly, pick.name).state.__text == "missing", "no Done for your target: " .. b.word.__text)
  noErrors(c, "rebuff")
  -- (a paladin's Blessing of Protection on the rogue in a fight; after it the client still restricts: the restore
  -- card's click, the name hidden, marks the rogue's Might)
  WORLD = {}
  local p5 = party5()
  c = p5.c3
  fight(c, true)
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Drog", "cast-r1", 10278)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-r1", 10278)
  tick(c, 11)
  c.restrict = { [c.env.Enum.AddOnRestrictionType.Combat] = true }
  fight(c, false)
  tick(c, 2)
  local restore = c.env.CuteAurasRestore
  assert(restore:IsShown() and c.units[restore:GetAttribute("unit")] == p5.ROG, "the restore card for the rogue")
  assert(c.A.Bar.Blocked() and marksOf(c, "duty:bless:might") == "", "the bar can't read; no mark yet")
  c.units.target = p5.WAR
  c.castEvents, c.hideNames = true, true
  c.casts = {}
  c.click(restore)
  c.castEvents, c.hideNames = nil, nil
  assert(c.casts[1] and c.units[c.casts[1].unit] == p5.ROG, "the card blessed the rogue")
  tick(c, 0.5)
  assert(marksOf(c, "duty:bless:might") == "Drog", "the rogue marked: " .. marksOf(c, "duty:bless:might"))
  noErrors(c)
end)

test("in a fight: any blessing of yours lets a mark go: one Cute Auras doesn't list (Salvation, should Forever add it) on the target's class; one whose target wasn't told, everyone's", function()
  local PAL = member({ name = "Apal", class = "PALADIN", level = 60, guid = "Player-1-J1" })
  local party = { PAL }
  for i, n in ipairs({ "Bwar", "Cwar" }) do party[i + 1] = member({ name = n, class = "WARRIOR", level = 60, guid = "Player-1-J" .. (i + 1) }) end
  party[4] = member({ name = "Erog", class = "ROGUE", level = 60, guid = "Player-1-J4" })
  local c = client({ me = PAL, group = party, spec = 594 })
  knowAll(c, "PALADIN", 60)
  SPELL_NAMES[1038] = "Blessing of Salvation"
  c.known[1038] = true
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:bless:might")
  assert(b and b.count.__text == "3", "Might owed to three")
  fight(c, true)
  tick(c, 1)
  castIn(c, "Bwar", 25291, "cast-b1"); castIn(c, "Cwar", 25291, "cast-b2"); castIn(c, "Erog", 25291, "cast-b3")
  tick(c, 1)
  assert(marksOf(c, "duty:bless:might") == "Bwar,Cwar,Erog" and b.word.__text == "Done", "Might on all three: Done")
  castIn(c, "Bwar", 1038, "cast-b4")
  tick(c, 1)
  assert(marksOf(c, "duty:bless:might") == "Erog", "Salvation on Bwar: the warriors' let go (as a Greater's, it can't be told): " .. marksOf(c, "duty:bless:might"))
  assert(b.word.__text == "Done" and b.count.__text == "2", "Erog, its click's, still on; the warriors two to go: " .. b.word.__text .. " " .. b.count.__text)
  -- (Kings, its name hidden, no click of ours: it may have landed on Erog)
  castIn(c, secret(), 20217, "cast-b5")
  tick(c, 1)
  assert(marksOf(c, "duty:bless:might") == "", "a blessing on someone not told: every mark let go: " .. marksOf(c, "duty:bless:might"))
  assert(b.word.__text == "Erog" and b.count.__text == "3", "the icon as read: " .. b.word.__text)
  -- (Might on Erog again, then Salvation on a pet, told by its name: no member, nothing let go)
  castIn(c, "Erog", 25291, "cast-b6")
  castIn(c, "Wolf", 1038, "cast-b7")
  tick(c, 1)
  assert(marksOf(c, "duty:bless:might") == "Erog", "a blessing on a pet: kept: " .. marksOf(c, "duty:bless:might"))
  noErrors(c)
end)

test("in a fight: Feign Death is no death: a Prayer reaches a feigning hunter and their mark stays; a real death lets it go", function()
  local P = member({ name = "Apri", class = "PRIEST", level = 60, guid = "Player-1-L1" })
  local Hn = member({ name = "Bhun", class = "HUNTER", level = 60, guid = "Player-1-L2" })
  local W = member({ name = "Cwar", class = "WARRIOR", level = 60, guid = "Player-1-L3" })
  local c = client({ me = P, group = { P, Hn, W } })
  knowAll(c, "PRIEST", 60)
  c.items[17029] = { name = "Sacred Candle" }
  c.bags = { { id = 17029, bag = 0, slot = 1, count = 5 } }
  load(c)
  tick(c, 12)
  local b = icon(c, "group", "duty:fort")
  local fly = c.env[b:GetName() .. "Fly"]
  fight(c, true)
  tick(c, 1)
  Hn.dead, Hn.feign = true, true
  castIn(c, "Apri", 21564, "cast-f1")
  tick(c, 1)
  assert(rowOf(fly, "Bhun").state.__text == "on", "the feigning hunter reached: " .. rowOf(fly, "Bhun").state.__text)
  fire(c, "UNIT_HEALTH", tokenOf(c, Hn))
  tick(c, 1)
  assert(rowOf(fly, "Bhun").state.__text == "on", "feigning: still on: " .. rowOf(fly, "Bhun").state.__text)
  Hn.feign = false
  fire(c, "UNIT_HEALTH", tokenOf(c, Hn))
  tick(c, 1)
  assert(rowOf(fly, "Bhun").state.__text == "missing", "dead: let go: " .. rowOf(fly, "Bhun").state.__text)
  noErrors(c)
end)

test("a death's watch costs nothing past a group member's health, and nothing once a read went through since the last mark (the group's part off too)", function()
  local me = member({ name = "Solo", class = "PRIEST", level = 40 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 40)
  load(c)
  tick(c, 2)
  c.A.Settings().group = false
  c.A.Bar.Refresh()
  tick(c, 1)
  local inner = icon(c, "own", "self:innerfire")
  fight(c, true)
  tick(c, 1)
  castIn(c, "", 1006, "cast-z1")
  tick(c, 1)
  assert(inner.word.__text == "Done", "Inner Fire marked")
  local real, n = c.env.UnitIsDeadOrGhost, 0
  c.env.UnitIsDeadOrGhost = function(u) n = n + 1; return real(u) end
  c.units.nameplate1 = member({ name = "Boar", class = "WARRIOR", level = 30, guid = "Creature-0-1", dead = true })
  c.units.boss1 = c.units.nameplate1
  for _ = 1, 50 do fire(c, "UNIT_HEALTH", "nameplate1"); fire(c, "UNIT_HEALTH", "boss1") end
  assert(n == 0, "in the fight, a mob's health: no look: " .. n)
  fire(c, "UNIT_HEALTH", "player")
  assert(n == 1, "yours: looked at: " .. n)
  fight(c, false)
  tick(c, 3)
  assert(inner.word.__text == "Buff", "the fight's read: asked again")
  n = 0
  for _ = 1, 50 do fire(c, "UNIT_HEALTH", "player") end
  c.env.UnitIsDeadOrGhost = real
  assert(n == 0, "after the read, the group's part off: no look: " .. n)
  noErrors(c)
end)

test("after a fight, restrictions lifting in one frame (a boss's end: Combat, Encounter, Chat) are one look", function()
  local c = lateFight("restrict")
  local E = c.env.Enum.AddOnRestrictionType
  c.restrict[E.Encounter] = true
  tick(c, 3.5)
  assert(c.A.Bar.late.waiting and stale(c), "a look waits")
  local before = c.A.Bar.refreshes
  c.lift(E.Combat); c.lift(E.Encounter); c.lift(E.Chat)
  tick(c, 0.1)
  assert(c.A.Bar.refreshes - before == 1, "one look: " .. (c.A.Bar.refreshes - before))
  assert(not stale(c) and not c.A.Bar.late.waiting, "looked again")
  -- (two lifted, Encounter still on: one look refused, still waiting; Encounter lifted: the look)
  WORLD = {}
  c = lateFight("restrict")
  c.restrict[E.Encounter] = true
  tick(c, 3.5)
  local refused = c.A.Bar.late.refused
  c.lift(E.Combat); c.lift(E.Chat)
  tick(c, 0.1)
  assert(c.A.Bar.late.waiting and stale(c), "Encounter still on: waiting")
  assert(c.A.Bar.late.refused - refused == 1, "one look refused: " .. (c.A.Bar.late.refused - refused))
  before = c.A.Bar.refreshes
  c.lift(E.Encounter)
  tick(c, 0.1)
  assert(c.A.Bar.refreshes - before == 1 and not stale(c), "Encounter lifted: one look")
  noErrors(c, "one lifted, then the other")
  -- (a look that went through before the frame's: none more)
  WORLD = {}
  c = lateFight("restrict")
  tick(c, 3.5)
  c.lift(E.Combat)
  before = c.A.Bar.refreshes
  c.A.Bar.Refresh()
  tick(c, 0.1)
  assert(c.A.Bar.refreshes - before == 1 and not stale(c), "looked once: " .. (c.A.Bar.refreshes - before))
  noErrors(c)
end)

----------------------------------------------------------------------------
-- 0.2.3, blessings and PallyPower: names with a surname, PallyPower's messages heard and spoken (PallySync.lua), your
-- casts setting your column, the Hand restore, the Blessings tab
----------------------------------------------------------------------------
-- a PallyPower message from a member with no client here (PallyPower alone): to the group, every client of it hears it,
-- or a whisper, only to's client
local function ppSay(from, text, to)
  for _, x in ipairs(WORLD) do
    local inGroup = false
    for _, m in ipairs(x.o.group or {}) do if m == from then inGroup = true end end
    if inGroup and (to == nil or x.o.me == to) then
      x.inbox[#x.inbox + 1] = { "PLPWR", text, to and "WHISPER" or (x.o.raid and "RAID" or "PARTY"), SENDER(from) }
    end
  end
end
-- the PLPWR messages a client sent, one kind's alone when asked
local function ppOut(c, kind)
  local t = {}
  for _, s in ipairs(c.sent) do if s.prefix == "PLPWR" and (not kind or s.msg:match("^%u+") == kind) then t[#t + 1] = s end end
  return t
end
-- PallyPower's own reading of a SELF, as its source reads one (PallyPower.lua:1954-1985, read, not copied): the six slots
-- by position, a rank hex unless "n" and its talent a decimal digit (its leader's Auto-Assign adds them: a nil errors,
-- PallyPower.lua:4797-4803), the nine row characters "n" or "" as 0, else a digit added to 0
local function ppReadSelf(msg)
  local numbers, assign = msg:match("SELF ([0-9a-fn]*)@([0-9n]*)")
  assert(numbers and assign, "PallyPower's SELF pattern: " .. msg)
  local ranks = {}
  for i = 1, 6 do
    local r, t = numbers:sub(i * 2 - 1, i * 2 - 1), numbers:sub(i * 2, i * 2)
    if r ~= "n" then
      ranks[i] = { rank = tonumber(r, 16), talent = tonumber(t) }
      assert(ranks[i].rank and ranks[i].talent, "slot " .. i .. " reads as two numbers: " .. msg)
      local _ = ranks[i].rank + ranks[i].talent
    end
  end
  local row = {}
  for i = 1, 9 do
    local ch = assign:sub(i, i)
    if ch == "n" or ch == "" then ch = 0 end
    row[i] = ch + 0
  end
  return ranks, row
end
local PP_ADDON = { PallyPower = { Version = "v1.6.13-classic-beta", Title = "PallyPower Forever" } }
-- a party with a paladin running PallyPower alone (Ysolde, no client here): Orren (paladin, Cute Auras), Tamsin (rogue,
-- Cute Auras, the lowest GUID: the asker), Brok (warrior tank, the leader, Cute Auras and PallyPower), Rask (warrior,
-- no addon). Every name carries a surname in chat
local function ppParty(o)
  o = o or {}
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
  local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-0D", assigned = "TANK", leader = true })
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
  local group = { TA, OR, YS, BR, RA }
  local c1 = client({ me = OR, group = group, spec = 184, addons = o.orrenPP and PP_ADDON or nil })
  local c2 = client({ me = TA, group = group, spec = 253 })
  local c3 = client({ me = BR, group = group, spec = 257, addons = PP_ADDON })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60); knowAll(c3, "WARRIOR", 60)
  if o.symbols then c1.bags[#c1.bags + 1] = { id = 21177, bag = 0, slot = 1, count = o.symbols } end
  load(c1); load(c2); load(c3)
  tickAll(o.wait or 12)
  return { c1 = c1, c2 = c2, c3 = c3, OR = OR, YS = YS, TA = TA, BR = BR, RA = RA, group = group, all = { c1, c2, c3 } }
end
local YS_SELF = "SELF 607010nnnnnn@221333113"
local function ovOf(c, pal, bucket) local o = c.A.Assign.overrides[pal]; return o and o[bucket] end

test("names: a sender with a surname, a realm or an underscore is its member; of two first names alike, the surname decides", function()
  local ME = member({ name = "Wren", surname = "Hollow", class = "PRIEST", level = 60, guid = "Player-1-N1" })
  local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-N2" })
  local group = { ME, YS }
  local c = client({ me = ME, group = group })
  knowAll(c, "PRIEST", 60)
  load(c)
  tick(c, 5)
  local R = c.A.Roster
  assert(R.ByGUID(YS.guid).surname == "Ashbrook" and R.ByGUID(YS.guid).name == "Ysolde", "the surname kept beside the name")
  for _, s in ipairs({ "Ysolde Ashbrook-Realm", "Ysolde Ashbrook", "Ysolde-Realm", "Ysolde_Ashbrook" }) do
    local m = R.SenderMember(s)
    assert(m and m.guid == YS.guid, s .. " is Ysolde")
  end
  assert(R.mySender == "Wren Hollow-Realm", "our own hello's echo names us: " .. tostring(R.mySender))
  assert(R.NamesLine() == "Names: sender two words and realm; UnitName one word, surname yes", R.NamesLine())
  -- (a cast's target told with the surname is that member too: Roster.ByName, for Hands and the marks)
  assert(R.ByName("Ysolde Ashbrook") and R.ByName("Ysolde Ashbrook").guid == YS.guid and R.ByName("Ysolde") == R.ByName("Ysolde Ashbrook"), "ByName with a surname")
  assert(R.ByName("Gnoll Raider") == nil, "no such member")
  -- UnitName's second answer a realm, not a surname: the only Ysolde still
  YS.surname = "Otherrealm"
  R.Scan()
  assert(R.SenderMember("Ysolde Ashbrook") and R.SenderMember("Ysolde Ashbrook").guid == YS.guid, "the only Ysolde")
  -- two of them: the second word breaks the tie
  YS.surname = "Ashbrook"
  local Y2 = member({ name = "Ysolde", surname = "Fenwick", class = "MAGE", level = 60, guid = "Player-1-N3" })
  group[3] = Y2
  seat(c)
  R.Scan()
  assert(R.SenderMember("Ysolde Fenwick").guid == Y2.guid and R.SenderMember("Ysolde Ashbrook-Realm").guid == YS.guid, "the surname decides")
  local was = R.unsure or 0
  assert(R.SenderMember("Ysolde") == nil and R.unsure == was + 1, "two Ysoldes, no surname: nobody, names unsure + 1")
  assert(R.SenderMember("Nobody Here-Realm") == nil, "no such member")
  noErrors(c)
end)

test("O1 from senders with a surname (UnitName the first name alone): a leader's grid click is taken everywhere; a sender naming a third member is refused", function()
  local LD = member({ name = "Corra", class = "PALADIN", level = 60, guid = "Player-1-S1", leader = true, sender = "Corra Ashgrove-Realm" })
  local P = member({ name = "Orren", class = "PALADIN", level = 60, guid = "Player-1-S2", sender = "Orren Lightsworn-Realm" })
  local W = member({ name = "Tamsin", class = "ROGUE", level = 60, guid = "Player-1-S3", sender = "Tamsin Reed-Realm" })
  local group = { LD, P, W }
  local c1 = client({ me = LD, group = group, spec = 184 })
  local c2 = client({ me = P, group = group, spec = 184 })
  local c3 = client({ me = W, group = group, spec = 253 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "PALADIN", 60); knowAll(c3, "ROGUE", 60)
  load(c1); load(c2); load(c3)
  tickAll(12)
  local b = "ROGUE:melee"
  assert(c1.A.Assign.BlessingOf(P.guid, b) == "kings", "Cute Auras' choice: Orren gives the rogue Kings")
  c1.A.Assign.Set(P.guid, b, "might")
  tickAll(3)
  for _, c in ipairs({ c1, c2, c3 }) do
    assert(c.A.Assign.BlessingOf(P.guid, b) == "might", "the leader's click taken")
    assert((c.A.Comm.refusedName or 0) == 0, "none refused")
  end
  -- an O1 naming the leader, sent by the rogue's client: refused
  local stamp = c3.env.GetServerTime() + 5
  c3.inbox[#c3.inbox + 1] = { "CuteAuras", string.format("O1|%s|%s|%s|kings|%d", LD.guid, P.guid, b, stamp), "PARTY", "Tamsin Reed-Realm" }
  tick(c3, 1)
  assert(c3.A.Comm.refusedName == 1, "O1 refused for name + 1: " .. tostring(c3.A.Comm.refusedName))
  assert(c3.A.Assign.BlessingOf(P.guid, b) == "might", "the cell stays")
  for _, c in ipairs({ c1, c2, c3 }) do noErrors(c, "O1 names") end
end)

test("PallyPower: Ysolde's SELF lists them on every client; their row fixes their cells; Orren fills the rest; the rogue's reminder says it was set in PallyPower", function()
  local g = ppParty()
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  for _, c in ipairs(g.all) do
    local As, Ps = c.A.Assign, c.A.PallySync
    assert(Ps.pals[g.YS.guid], "listed")
    local k = As.KnownOf(c.A.Roster.ByGUID(g.YS.guid))
    assert(k and k.wisdom == 6 and k.might == 7 and k.kings == 1, "their ranks")
    local pals = {}
    for _, p in ipairs(As.paladins) do pals[#pals + 1] = p.guid end
    assert(#pals == 2, "two columns: " .. table.concat(pals, ","))
    assert(As.BlesserFor(c.A.Roster.ByGUID(g.TA.guid), "might") == g.YS.guid, "Might on the rogue: Ysolde")
    assert(As.BlessingOf(g.YS.guid, "ROGUE:melee") == "might" and As.BlessingOf(g.OR.guid, "ROGUE:melee") == "kings", "Orren: Kings for rogues, not Might")
    assert(As.BlessingOf(g.YS.guid, "WARRIOR:tank") == "might" and As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings", "the tank: Might from Ysolde, Kings from Orren")
    assert(As.Source(g.YS.guid) == "pp" and As.Source(g.OR.guid) == "cute", "the sources")
  end
  -- Orren's own duties: no Might for the rogue
  local function gives(c, key, m)
    local d = dutyOf(c, key)
    for _, t in ipairs(d and d.targets or {}) do if t.guid == m.guid then return true end end
    return false
  end
  assert(gives(g.c1, "bless:kings", g.TA) and not gives(g.c1, "bless:might", g.TA), "Orren's bar: Kings for Tamsin")
  -- Tamsin lacks both: Ysolde named for Might (set in PallyPower), Orren for Kings (Cute Auras)
  local c = g.c2
  tick(c, 31)
  local recs = {}
  for _, r in ipairs(shown(c, "mine")) do recs[r.key] = r end
  local rm, rk = recs["from:bless:might"], recs["from:bless:kings"]
  assert(rm and rm.word == "Ysolde", "Might from Ysolde on the bar: " .. fromKeys(c))
  assert(c.A.Buffs.FromText(rm) == "Missing. Ysolde gives it (set in PallyPower).", c.A.Buffs.FromText(rm))
  assert(rk and c.A.Buffs.FromText(rk) == "Missing. Orren gives it (shared out by Cute Auras).", rk and c.A.Buffs.FromText(rk))
  -- a lower Might on Tamsin: Ysolde gives rank 7
  table.insert(g.TA.auras, { id = 19837, src = "party9", exp = c.clock + 3000, dur = 3600 })
  fire(c, "UNIT_AURA", "player")
  tick(c, 1)
  recs = {}
  for _, r in ipairs(shown(c, "mine")) do recs[r.key] = r end
  rm = recs["from:bless:might"]
  assert(rm and c.A.Buffs.FromText(rm) == "Rank 5 on you; Ysolde gives rank 7 (set in PallyPower).", rm and c.A.Buffs.FromText(rm))
  for _, x in ipairs(g.all) do noErrors(x, "SELF heard") end
end)

test("PallyPower: a SELF read with care: a 10-column row uses 9, a short one is bad and changes nothing, junk raises nothing; a non-paladin or a stranger is ignored; an empty row empties theirs", function()
  local g = ppParty()
  ppSay(g.YS, "SELF 607010nnnnnn@2213331131")
  tickAll(2)
  local As = g.c2.A.Assign
  assert(As.BlessingOf(g.YS.guid, "ROGUE:melee") == "might", "a 10-column build: the first 9")
  for _, c in ipairs(g.all) do
    local Ps = c.A.PallySync
    local bad = Ps.stats.bad or 0
    ppSay(g.YS, "SELF 6070@22")
    ppSay(g.YS, "SELF zz@")
    tick(c, 1)
    assert(Ps.stats.bad == bad + 2, "bad + 2: " .. tostring(Ps.stats.bad))
    assert(c.A.Assign.BlessingOf(g.YS.guid, "ROGUE:melee") == "might" and Ps.pals[g.YS.guid].ranks.might == 7, "nothing changed")
  end
  -- Rask, a warrior, and a stranger send a SELF: nobody lists them
  ppSay(g.RA, YS_SELF)
  for _, c in ipairs(g.all) do c.inbox[#c.inbox + 1] = { "PLPWR", YS_SELF, "PARTY", "Stranger Far-Realm" } end
  tickAll(2)
  for _, c in ipairs(g.all) do
    assert(not c.A.PallySync.pals[g.RA.guid], "a warrior's SELF ignored")
    local n = 0
    for _ in pairs(c.A.PallySync.pals) do n = n + 1 end
    assert(n == 1, "Ysolde alone listed: " .. n)
  end
  -- their row emptied: still known, giving nothing; Orren gives the rogue Might again
  ppSay(g.YS, "SELF 607010nnnnnn@nnnnnnnnn")
  tickAll(2)
  for _, c in ipairs(g.all) do
    local A2 = c.A.Assign
    assert(c.A.PallySync.pals[g.YS.guid] and A2.BlessingOf(g.YS.guid, "ROGUE:melee") == nil, "their row empty")
    assert(A2.BlessingOf(g.OR.guid, "ROGUE:melee") == "might", "Orren's choice again: Might")
    assert(A2.BlesserFor(c.A.Roster.ByGUID(g.TA.guid), "might") == g.OR.guid, "Might from Orren now")
  end
  for _, x in ipairs(g.all) do noErrors(x, "SELF robustness") end
end)

test("PallyPower: a leader's ASSIGN for Orren (Cute Auras alone) is their client's own cell, sent once as O1 with pp; MASSIGN, PASSIGN, NASSIGN; a plain member refused; 0 puts it back", function()
  local g = ppParty()
  local c1 = g.c1
  local function each(f) for _, c in ipairs(g.all) do f(c, c.A.Assign) end end
  assert(c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might" and c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings", "Cute Auras' choice first")
  local n = #c1.said
  ppSay(g.BR, "ASSIGN Orren Lightsworn 1 3")
  tickAll(3)
  local stamp
  each(function(c, As)
    for _, bk in ipairs({ "WARRIOR:melee", "WARRIOR:tank" }) do
      local ov = ovOf(c, g.OR.guid, bk)
      assert(ov and ov.key == "kings" and ov.pp and ov.from == g.OR.guid, "warriors: Kings, Orren's own cell marked pp")
      assert(As.BlessingOf(g.OR.guid, bk) == "kings", "Kings for the warriors")
    end
    local s = ovOf(c, g.OR.guid, "WARRIOR:melee").stamp
    assert(stamp == nil or s == stamp, "one stamp on every client")
    stamp = s
  end)
  local o1 = 0
  local og = g.OR.guid:gsub("%p", "%%%0")
  for i = n + 1, #c1.said do if c1.said[i]:match("^O1|" .. og .. "|" .. og .. "|WARRIOR:%a+|kings|%d+|pp$") then o1 = o1 + 1 end end
  assert(o1 == 2, "two O1s with field 7 pp: " .. o1)
  assert(g.c2.A.PallySync.stats.taken == nil or g.c2.A.PallySync.stats.taken == 0, "the rogue's client took nothing itself")
  local mine = c1.A.Assign.Mine()
  local pp = 0
  for _, e in ipairs(mine) do if e[5] == "pp" then pp = pp + 1 end end
  assert(pp == 2, "As.Mine holds them, marked pp: " .. pp)
  -- the rogue's client reloads with nothing saved: Orren's resend after its Q1 brings them back
  local c2 = reload(g.c2)
  c2.o.db.chars[g.TA.guid].group = nil
  load(c2)
  g.c2 = c2; g.all[2] = c2
  tickAll(12)
  local ov = ovOf(c2, g.OR.guid, "WARRIOR:melee")
  assert(ov and ov.key == "kings" and ov.pp and ov.stamp == stamp, "resent after the Q1")
  -- from a plain member: refused, nothing changes
  local ref = g.c3.A.PallySync.stats.refused or 0
  ppSay(g.RA, "ASSIGN Orren Lightsworn 1 2")
  tickAll(3)
  assert(g.c3.A.PallySync.stats.refused == ref + 1, "refused + 1")
  each(function(c, As) assert(As.BlessingOf(g.OR.guid, "WARRIOR:melee") == "kings", "still Kings") end)
  -- 0 from the leader: back to Cute Auras' choice
  ppSay(g.BR, "ASSIGN Orren Lightsworn 1 0")
  tickAll(3)
  each(function(c, As)
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might" and As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings", "Cute Auras' choice again")
  end)
  -- MASSIGN: Might for every class from Orren
  ppSay(g.BR, "MASSIGN Orren Lightsworn 2")
  tickAll(3)
  each(function(c, As)
    for _, bk in ipairs({ "WARRIOR:melee", "WARRIOR:tank", "ROGUE:melee", "PALADIN:melee", "PALADIN:healer" }) do
      assert(As.BlessingOf(g.OR.guid, bk) == "might", "Might for " .. bk)
    end
  end)
  -- PASSIGN: rogues Might, druids Kings (none here), the rest back to Cute Auras' choice
  ppSay(g.BR, "PASSIGN Orren Lightsworn@n2n3nnnnn")
  tickAll(3)
  each(function(c, As)
    assert(As.BlessingOf(g.OR.guid, "ROGUE:melee") == "might" and ovOf(c, g.OR.guid, "ROGUE:melee").pp, "rogues: Might, set in PallyPower")
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings" and As.BlessingOf(g.OR.guid, "PALADIN:healer") == "wisdom", "the rest: Cute Auras' choice")
  end)
  -- NASSIGN: Might for Brok alone, the tank bucket theirs alone
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 2")
  tickAll(3)
  each(function(c, As) assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "might" and As.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", "Brok: Might") end)
  for _, x in ipairs(g.all) do noErrors(x, "leader's ASSIGN") end
end)

test("PallyPower: NASSIGN fixes one member's cell from a PallyPower paladin; CLEAR from the leader drops every PallyPower cell, Orren's pp cells by O1; a grid cell stays; a member's CLEAR is ignored", function()
  local g = ppParty()
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  -- Brok alone in WARRIOR:tank gets Kings from Ysolde; Rask's WARRIOR:melee keeps Ysolde's Might
  ppSay(g.YS, "NASSIGN Ysolde_Ashbrook 1 Brok_Ironhide 3")
  tickAll(2)
  for _, c in ipairs(g.all) do
    local As = c.A.Assign
    assert(As.BlessingOf(g.YS.guid, "WARRIOR:tank") == "kings" and As.BlessingOf(g.YS.guid, "WARRIOR:melee") == "might", "Ysolde's member cell for Brok")
    assert(As.BlesserFor(c.A.Roster.ByGUID(g.BR.guid), "kings") == g.YS.guid, "Kings on Brok from Ysolde")
  end
  ppSay(g.YS, "NASSIGN Ysolde_Ashbrook 1 Brok_Ironhide 3@Ysolde_Ashbrook 2 Tamsin_Reed 3")
  tickAll(2)
  assert(g.c2.A.Assign.BlessingOf(g.YS.guid, "ROGUE:melee") == "kings", "both entries taken: Tamsin's Kings")
  -- the leader's Kings for Orren's warriors, and Orren's own grid click for the paladin healers
  ppSay(g.BR, "ASSIGN Orren Lightsworn 1 3")
  g.c1.A.Assign.Set(g.OR.guid, "PALADIN:healer", "might")
  tickAll(3)
  assert(ovOf(g.c2, g.OR.guid, "WARRIOR:melee").pp, "Orren's pp cell heard")
  -- a plain member's CLEAR: nothing
  ppSay(g.RA, "CLEAR")
  tickAll(2)
  for _, c in ipairs(g.all) do assert(next(c.A.PallySync.row) and next(c.A.PallySync.member), "a member's CLEAR ignored") end
  -- the leader's CLEAR
  ppSay(g.BR, "CLEAR")
  tickAll(3)
  for _, c in ipairs(g.all) do
    local As, Ps = c.A.Assign, c.A.PallySync
    assert(next(Ps.row) == nil and next(Ps.member) == nil, "every PallyPower cell dropped")
    assert(Ps.pals[g.YS.guid], "Ysolde still listed")
    assert(As.BlessingOf(g.YS.guid, "ROGUE:melee") == nil, "Ysolde gives nothing now")
    local ov = ovOf(c, g.OR.guid, "WARRIOR:melee")
    assert(ov and ov.clear, "Orren's pp cell cleared by their O1")
    assert(As.BlessingOf(g.OR.guid, "PALADIN:healer") == "might", "the grid's cell stays")
  end
  -- CLEAR SKIP the same
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  ppSay(g.BR, "CLEAR SKIP")
  tickAll(2)
  for _, c in ipairs(g.all) do assert(next(c.A.PallySync.row) == nil, "CLEAR SKIP too") end
  for _, x in ipairs(g.all) do noErrors(x, "CLEAR") end
  -- a member's own cell in a bucket of two rogues: Tamsin's Kings from Ysolde; Ysolde's Might, the row's, for the other rogue
  WORLD = {}
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
  local KE = member({ name = "Kestra", surname = "Moor", class = "ROGUE", level = 60, guid = "Player-1-0F" })
  local group = { TA, OR, YS, KE }
  local c1 = client({ me = OR, group = group, spec = 184 })
  local c2 = client({ me = TA, group = group, spec = 253 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60)
  load(c1); load(c2)
  tickAll(12)
  ppSay(YS, YS_SELF)
  ppSay(YS, "NASSIGN Ysolde_Ashbrook 2 Tamsin_Reed 3")
  tickAll(2)
  for _, c in ipairs({ c1, c2 }) do
    local As, R = c.A.Assign, c.A.Roster
    assert(As.BlessingOf(YS.guid, "ROGUE:melee") == "might" and As.BlessingOf(OR.guid, "ROGUE:melee") == "kings", "the bucket: Ysolde's row's Might, Orren's Kings")
    assert(As.BlesserFor(R.ByGUID(TA.guid), "kings") == YS.guid, "Tamsin's Kings: Ysolde's own cell for Tamsin")
    assert(As.BlesserFor(R.ByGUID(TA.guid), "might") == nil, "Tamsin's Might: nobody (Ysolde gives Tamsin Kings)")
    assert(As.BlesserFor(R.ByGUID(KE.guid), "might") == YS.guid and As.BlesserFor(R.ByGUID(KE.guid), "kings") == OR.guid, "Kestra: the bucket's")
  end
  noErrors(c1, "member cells"); noErrors(c2, "member cells")
end)

test("PallyPower: the mirror guard: Orren's own SELF never lists them; a new hello keeps the first one's place ahead of a waiting SELF; the first batch waits for our hello", function()
  local g = ppParty()
  -- (Orren's own batch, a PallyPower REQ answered: their S1, then their SELF)
  ppSay(g.YS, "REQ")
  tickAll(6)
  assert(#ppOut(g.c1, "SELF") >= 1, "Orren's own SELF went")
  local s1
  for i, x in ipairs(g.c1.sent) do if x.prefix == "CuteAuras" and x.msg:find("^S1|") then s1 = s1 or i end end
  local self1
  for i, x in ipairs(g.c1.sent) do if x.prefix == "PLPWR" and x.msg:find("^SELF ") then self1 = self1 or i end end
  assert(s1 and self1 and s1 < self1, "an S1 ahead of it: " .. tostring(s1) .. " " .. tostring(self1))
  for _, c in ipairs(g.all) do assert(not c.A.PallySync.pals[g.OR.guid], "Orren runs Cute Auras alone: never listed") end
  -- a SELF heard before Orren's hello (Tamsin's client forgot it): listed, then let go when the hello says "-"
  g.c2.A.Comm.peers[g.OR.guid] = nil
  ppSay(g.OR, "SELF 607010nnnnnn@221333113")
  tickAll(1)
  assert(g.c2.A.PallySync.pals[g.OR.guid], "no hello yet: listed")
  g.c1.A.Comm.Hello(true)
  tickAll(2)
  assert(not g.c2.A.PallySync.pals[g.OR.guid] and g.c2.A.Comm.peers[g.OR.guid].ppField == "-", "the hello's - lets them go")
  -- the queue: a hello waiting, a SELF behind it, a newer hello takes the first one's place
  local Cm = g.c1.A.Comm
  local q = Cm.queue
  for i = #q, 1, -1 do q[i] = nil end
  Cm.Send("H1|" .. g.OR.guid .. "|old")
  Cm.Send("SELF 607010nnnnnn@nnnnnnnnn", "PLPWR")
  Cm.Send("SELF 607010nnnnnn@333333333", "PLPWR")
  Cm.Send("H1|" .. g.OR.guid .. "|new")
  assert(#q == 2, "one hello, one SELF: " .. #q)
  assert(q[1].msg == "H1|" .. g.OR.guid .. "|new" and q[2].msg == "SELF 607010nnnnnn@333333333" and q[2].prefix == "PLPWR", "the hello ahead, each the newer")
  tickAll(2)
  -- no hello sent in this group yet: the batch waits for it
  local c1 = g.c1
  Cm.helloSent = false
  local before = #c1.sent
  ppSay(g.YS, "REQ")
  tickAll(5)
  for i = before + 1, #c1.sent do assert(c1.sent[i].prefix ~= "PLPWR", "nothing on PLPWR before our hello") end
  Cm.Hello(true)
  tickAll(4)
  local h, s
  for i = before + 1, #c1.sent do
    local x = c1.sent[i]
    if not h and x.msg:find("^H1|") then h = i end
    if not s and x.prefix == "PLPWR" and x.msg:find("^SELF ") then s = i end
  end
  assert(h and s and h < s, "the hello, then the SELF: " .. tostring(h) .. " " .. tostring(s))
  for _, x in ipairs(g.all) do noErrors(x, "mirror") end
end)

test("PallyPower: what we send: exactly 27 bytes of SELF as PallyPower reads it, ASELF, FREEASSIGN, to the group; a Never'd Wisdom is nn", function()
  local g = ppParty({ symbols = 40 })
  local c1 = g.c1
  ppSay(g.YS, "REQ")
  tickAll(4)
  local out = ppOut(c1)
  assert(#out == 3, "one batch: " .. #out)
  local s = out[1].msg
  assert(#s == 27 and s:match("^SELF [0-9a-fn]+@[0-9n]+$") and #s:match("^SELF (%S+)@") == 12 and #s:match("@(%S+)$") == 9, "27 bytes: " .. s)
  assert(s:sub(1, 18) == "SELF 607010nnnnnn@", "Wisdom 6, Might 7, Kings 1: " .. s)
  assert(out[2].msg == "ASELF nnnnnnnnnnnnnn@0", out[2].msg)
  assert(out[3].msg == "FREEASSIGN NO | SYMCOUNT 40 | COOLDOWNS:n:n:n:n", out[3].msg)
  for _, x in ipairs(out) do assert(x.ch == "PARTY" and x.to == nil, "to the group") end
  -- PallyPower's reading: ranks 6, 7, 1, talents 0; the row each class's largest bucket from Orren
  local ranks, row = ppReadSelf(s)
  assert(ranks[1].rank == 6 and ranks[2].rank == 7 and ranks[3].rank == 1 and ranks[1].talent == 0 and not ranks[4], "the ranks as PallyPower reads them")
  local As = c1.A.Assign
  local digit = { wisdom = 1, might = 2, kings = 3 }
  local order = { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
  for i, class in ipairs(order) do
    local best
    for _, b in ipairs(As.bucketList) do if b.class == class and (not best or #b > #best or (#b == #best and b.key < best.key)) then best = b end end
    local want = best and digit[As.BlessingOf(g.OR.guid, best.key)] or 0
    assert(row[i] == want, class .. ": " .. row[i] .. " for " .. want)
  end
  -- Wisdom on Never: slot 1 nn
  c1.A.Bar.SetNever("duty:bless:wisdom", "Blessing of Wisdom", true)
  tickAll(3)
  ppSay(g.YS, "REQ")
  tickAll(25)
  out = ppOut(c1, "SELF")
  assert(out[#out].msg:sub(1, 18) == "SELF nn7010nnnnnn@" and #out[#out].msg == 27, "Never'd Wisdom: " .. out[#out].msg)
  for _, x in ipairs(g.all) do noErrors(x, "write format") end
end)

test("PallyPower: when we send: nothing before PallyPower is heard; three REQs, one batch within 3 s; three changes in 15 s, one batch; nothing leaves in a fight or a lockdown", function()
  local g = ppParty()
  local c1 = g.c1
  tickAll(40)
  assert(#ppOut(c1) == 0, "no PallyPower heard: nothing sent")
  -- three REQs in 2 s
  local t0 = c1.clock
  ppSay(g.YS, "REQ"); tickAll(1)
  ppSay(g.YS, "REQ"); tickAll(1)
  ppSay(g.YS, "REQ")
  tickAll(2)
  local selfs = ppOut(c1, "SELF")
  assert(#selfs == 1 and selfs[1].at - t0 <= 3, "one batch within 3 s: " .. #selfs .. (selfs[1] and (" at " .. (selfs[1].at - t0)) or ""))
  -- three changes of the row in 15 s: one batch
  tickAll(20)
  local n = #ppOut(c1, "SELF")
  local As = c1.A.Assign
  As.Set(g.OR.guid, "ROGUE:melee", "kings"); tickAll(5)
  As.Set(g.OR.guid, "ROGUE:melee", "might"); tickAll(5)
  As.Set(g.OR.guid, "ROGUE:melee", "kings"); tickAll(20)
  assert(#ppOut(c1, "SELF") == n + 1, "three changes, one batch: " .. (#ppOut(c1, "SELF") - n))
  -- a REQ heard while a change's batch waits makes it an answer: it goes even when the change is undone first
  n = #ppOut(c1, "SELF")
  As.Set(g.OR.guid, "ROGUE:melee", "might")
  tickAll(4)
  ppSay(g.YS, "REQ")
  As.Set(g.OR.guid, "ROGUE:melee", "kings")
  tickAll(4)
  assert(#ppOut(c1, "SELF") == n + 1, "the REQ answered: " .. (#ppOut(c1, "SELF") - n))
  tickAll(20)
  -- in a fight nothing leaves; after it the batch goes
  n = #ppOut(c1, "SELF")
  fight(c1, true)
  ppSay(g.YS, "REQ")
  tickAll(6)
  assert(#ppOut(c1, "SELF") == n, "nothing in a fight")
  fight(c1, false)
  tickAll(3)
  assert(#ppOut(c1, "SELF") == n + 1, "the batch after the fight")
  -- a lockdown (result 11): nothing leaves; it goes once lifted
  tickAll(6)
  n = #ppOut(c1, "SELF")
  c1.lockdown = true
  ppSay(g.YS, "REQ")
  tickAll(6)
  assert(#ppOut(c1, "SELF") == n, "nothing in a lockdown")
  c1.lockdown = false
  tickAll(8)
  assert(#ppOut(c1, "SELF") == n + 1, "the batch after the lockdown")
  for _, x in ipairs(g.all) do noErrors(x, "write timing") end
end)

test("PallyPower on Orren's own client: their hello says pp, Cute Auras sends nothing on PLPWR, their echoed SELF fixes their set cells on every client, empty ones keep Cute Auras' choice, casts teach nothing", function()
  local g = ppParty({ orrenPP = true })
  local c1 = g.c1
  for _, c in ipairs({ g.c2, g.c3 }) do assert(c.A.Comm.peers[g.OR.guid].ppField == "pp", "their hello's field 8") end
  ppSay(g.YS, "REQ")
  tickAll(5)
  assert(#ppOut(c1) == 0, "Cute Auras sends nothing on PLPWR there")
  -- their PallyPower's SELF, echoed to their own client too: rogues Might, nothing else set
  ppSay(g.OR, "SELF 607010nnnnnn@n2nnnnnnn")
  tickAll(2)
  for _, c in ipairs(g.all) do
    local As = c.A.Assign
    assert(c.A.PallySync.pals[g.OR.guid], "listed from their own SELF")
    assert(As.BlessingOf(g.OR.guid, "ROGUE:melee") == "might" and As.Source(g.OR.guid, "ROGUE:melee") == "pp", "rogues: Might, their PallyPower's")
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings" and As.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", "empty cells: Cute Auras' choice")
  end
  -- Orren's Kings on Rask, whose cell is Might: nothing taught
  table.insert(g.RA.auras, { id = 20217, src = "player", exp = c1.clock + 3600, dur = 3600 })
  fire(c1, "UNIT_AURA", tokenOf(c1, g.RA))
  tickAll(4)
  assert(ovOf(c1, g.OR.guid, "WARRIOR:melee") == nil, "casts teach nothing while PallyPower runs here")
  for _, x in ipairs(g.all) do noErrors(x, "PallyPower here") end
end)

test("PallyPower: one asker sends REQ (a paladin 10 s with no hello or SELF, the tab, after a fight); a whispered SELF is relayed once and parsed everywhere; Orren answers PallyPower's REQ, not the asker's", function()
  local g = ppParty()
  local c1, c2, c3 = g.c1, g.c2, g.c3
  assert(#ppOut(c2, "REQ") == 1, "the asker asked once: " .. #ppOut(c2, "REQ"))
  assert(#ppOut(c1, "REQ") == 0 and #ppOut(c3, "REQ") == 0, "nobody else")
  assert(#ppOut(c1) == 0, "Orren does not answer the asker's REQ")
  -- (not the asker: Orren's tab and fight ask nothing)
  tickAll(30)
  c1.A.Window.Open("blessings")
  fight(c1, true); tick(c1, 1); fight(c1, false)
  tickAll(4)
  assert(#ppOut(c1, "REQ") == 0, "Orren is not the asker")
  tickAll(30)
  assert(#ppOut(c2, "REQ") == 1, "never two")
  -- the tab: in a fight, nothing; out of it, one
  fight(c2, true)
  c2.A.Window.Open("blessings")
  tickAll(2)
  assert(#ppOut(c2, "REQ") == 1, "never in a fight")
  fight(c2, false)
  c2.env.CuteAurasWindow:Hide()
  c2.A.Window.Open("blessings")
  tickAll(2)
  assert(#ppOut(c2, "REQ") == 2, "the tab asks: " .. #ppOut(c2, "REQ"))
  -- Ysolde whispers a SELF to the asker: one P1, every client lists them once
  local p1 = #c2.said
  ppSay(g.YS, YS_SELF, g.TA)
  tickAll(3)
  local relays = 0
  for i = p1 + 1, #c2.said do if c2.said[i]:find("^P1|") then relays = relays + 1 end end
  assert(relays == 1, "one relay: " .. relays)
  for _, c in ipairs(g.all) do
    assert(c.A.PallySync.pals[g.YS.guid] and c.A.Assign.BlessingOf(g.YS.guid, "ROGUE:melee") == "might", "listed through the relay")
  end
  -- a whisper to another member is never read
  ppSay(g.YS, "SELF 607010nnnnnn@nnnnnnnnn", g.OR)
  tickAll(3)
  for _, c in ipairs(g.all) do assert(c.A.Assign.BlessingOf(g.YS.guid, "ROGUE:melee") == "might", "a whisper to Orren ignored") end
  -- a P1 from a client that is not the asker: never read
  g.c3.inbox[#g.c3.inbox + 1] = { "CuteAuras", "P1|" .. SENDER(g.YS) .. "|SELF 607010nnnnnn@nnnnnnnnn", "PARTY", SENDER(g.OR) }
  tickAll(2)
  assert(g.c3.A.Assign.BlessingOf(g.YS.guid, "ROGUE:melee") == "might", "a P1 from Orren ignored")
  -- the NASSIGN PallyPower whispers with its SELF: passed on too, every client has it
  ppSay(g.YS, "NASSIGN Ysolde_Ashbrook 2 Tamsin_Reed 3", g.TA)
  tickAll(3)
  for _, c in ipairs(g.all) do assert(c.A.PallySync.MemberCell(g.YS.guid, g.TA.guid) == "kings", "the whispered NASSIGN relayed") end
  -- Orren answers PallyPower's REQ within 3 s
  tickAll(20)
  local n, t0 = #ppOut(c1, "SELF"), c1.clock
  ppSay(g.YS, "REQ")
  tickAll(3)
  local selfs = ppOut(c1, "SELF")
  assert(#selfs == n + 1 and selfs[#selfs].at - t0 <= 3, "answered within 3 s")
  -- after a fight, with a PallyPower paladin here: one REQ, then none for 5 minutes
  tickAll(30)
  local r = #ppOut(c2, "REQ")
  fight(c2, true); tick(c2, 2); fight(c2, false)
  tickAll(4)
  assert(#ppOut(c2, "REQ") == r + 1, "after a fight: asked")
  tickAll(40)
  fight(c2, true); tick(c2, 2); fight(c2, false)
  tickAll(4)
  assert(#ppOut(c2, "REQ") == r + 1, "not again within 5 minutes")
  -- the diag's line: counts and words, never a name
  local line = c2.A.PallySync.DiagLine()
  assert(line:find("^PallyPower: here no; asker yes; heard %d+ %(SELF %d+, set %d+, clear %d+, REQ %d+, whispered 2, relayed 2, other %d+%); taken %d+, refused %d+, names unsure 0, bad 0, secret 0; paladins on it 1; sent 3 %(SELF 0, REQ 3%); O1 refused for name 0$"), line)
  assert(c3.A.PallySync.DiagLine():find("^PallyPower: here yes v1%.6%.13%-classic%-beta %(PallyPower Forever%); asker no;"), c3.A.PallySync.DiagLine())
  for _, m in ipairs(g.group) do assert(not line:find(m.name, 1, true) and not line:find(m.surname, 1, true), "no name in the diag") end
  for _, x in ipairs(g.all) do noErrors(x, "REQ") end
end)

test("PallyPower: a secret text or sender counts secret; out of a group nothing is read; an unknown message is other", function()
  local g = ppParty()
  local c = g.c1
  local Ps = c.A.PallySync
  c.inbox[#c.inbox + 1] = { "PLPWR", secret(), "PARTY", SENDER(g.YS) }
  c.inbox[#c.inbox + 1] = { "PLPWR", YS_SELF, "PARTY", secret() }
  tick(c, 1)
  assert(Ps.stats.secret == 2, "secret + 2: " .. tostring(Ps.stats.secret))
  assert(not Ps.pals[g.YS.guid], "nothing taken")
  local other = Ps.stats.other or 0
  ppSay(g.YS, "FOO bar")
  tick(c, 1)
  assert(Ps.stats.other == other + 1, "other + 1")
  -- out of a group: nothing
  local me = member({ name = "Solo", surname = "Wanderer", class = "PALADIN", level = 60, guid = "Player-1-Z1" })
  local cs = client({ me = me })
  knowAll(cs, "PALADIN", 60)
  load(cs)
  cs.inbox[#cs.inbox + 1] = { "PLPWR", YS_SELF, "PARTY", SENDER(g.YS) }
  tick(cs, 1)
  assert((cs.A.PallySync.stats.heard or 0) == 0 and next(cs.A.PallySync.pals) == nil, "out of a group: ignored")
  noErrors(c, "secret"); noErrors(cs, "solo")
end)

test("PallyPower: Ysolde leaves and their column goes; a /reload in the same group brings them back from the save, a new group does not", function()
  local g = ppParty()
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  -- Orren reloads: Ysolde is back at login, before any message
  local c1 = reload(g.c1)
  load(c1)
  g.c1, g.all[1] = c1, c1
  assert(c1.A.PallySync.pals[g.YS.guid] and c1.A.PallySync.heardAny, "restored from the save, PallyPower heard in this group")
  tick(c1, 1)
  assert(c1.A.Assign.BlessingOf(g.YS.guid, "ROGUE:melee") == "might" and c1.A.Assign.BlessingOf(g.OR.guid, "ROGUE:melee") == "kings", "their row back, the share-out the same")
  tickAll(12)
  -- a save read into another group: nothing
  local cx = reload(c1)
  cx.o.db.chars[g.OR.guid].group.members = { "Player-9-X1", "Player-9-X2", "Player-9-X3" }
  load(cx)
  g.c1, g.all[1] = cx, cx
  assert(next(cx.A.PallySync.pals) == nil, "a new group: nothing read back")
  tickAll(12)
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  -- Ysolde leaves
  table.remove(g.group, 3)
  for _, c in ipairs(g.all) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
  tickAll(4)
  for _, c in ipairs(g.all) do
    assert(not c.A.PallySync.pals[g.YS.guid] and c.A.PallySync.row[g.YS.guid] == nil, "forgotten")
    assert(#c.A.Assign.paladins == 1 and c.A.Assign.BlessingOf(g.OR.guid, "ROGUE:melee") == "might", "one column; Orren gives rogues Might again")
  end
  for _, x in ipairs(g.all) do noErrors(x, "prune and save") end
end)

test("teach: your Kings on the only rogue out of a fight sets your rogue cell to Kings (hand-set, O1); not in a fight, not a Hand, never over the leader's", function()
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-T1" })
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-T2" })
  local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-T3", assigned = "TANK", leader = true })
  local group = { OR, TA, BR }
  local c1 = client({ me = OR, group = group, spec = 184 })
  local c2 = client({ me = TA, group = group, spec = 253 })
  local c3 = client({ me = BR, group = group, spec = 257, addons = PP_ADDON })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60); knowAll(c3, "WARRIOR", 60)
  load(c1); load(c2); load(c3)
  tickAll(12)
  local b = "ROGUE:melee"
  local tok = tokenOf(c1, TA)
  assert(c1.A.Assign.BlessingOf(OR.guid, b) == "might", "Cute Auras' choice: Might")
  -- in a fight: nothing
  fight(c1, true)
  TA.auras = { { id = 20217, src = "player", exp = c1.clock + 3600, dur = 3600 } }
  fire(c1, "UNIT_AURA", tok)
  tickAll(3)
  assert(ovOf(c1, OR.guid, b) == nil, "nothing taught in a fight")
  fight(c1, false)
  tickAll(4)
  local ov = ovOf(c1, OR.guid, b)
  assert(ov and ov.key == "kings" and ov.from == OR.guid and not ov.pp, "after the fight: Kings, hand-set")
  assert(c2.A.Assign.BlessingOf(OR.guid, b) == "kings", "sent as O1")
  -- a grid click back to Might while that Kings is still on: the click stays (a blessing put on before it teaches
  -- nothing); a Kings put on after it teaches again
  tickAll(2)
  c1.A.Assign.Set(OR.guid, b, "might")
  tickAll(2)
  fire(c1, "UNIT_AURA", tok)
  tickAll(6)
  assert(c1.A.Assign.BlessingOf(OR.guid, b) == "might", "the click stays")
  TA.auras = { { id = 20217, src = "player", exp = c1.clock + 3600, dur = 3600 } }
  fire(c1, "UNIT_AURA", tok)
  tickAll(4)
  assert(c1.A.Assign.BlessingOf(OR.guid, b) == "kings", "a new Kings teaches")
  -- a Hand never teaches
  TA.auras = { { id = 1044, src = "player", exp = c1.clock + 10, dur = 10 } }
  fire(c1, "UNIT_AURA", tok)
  c1.A.Assign.Set(OR.guid, b, "might")
  tickAll(4)
  assert(c1.A.Assign.BlessingOf(OR.guid, b) == "might", "a Hand: nothing")
  -- the leader's cell (an O1 from the leader): never taught over
  tickAll(2)
  c3.A.Assign.Set(OR.guid, b, "might")
  tickAll(3)
  TA.auras = { { id = 20217, src = "player", exp = c1.clock + 3600, dur = 3600 } }
  fire(c1, "UNIT_AURA", tok)
  tickAll(4)
  assert(c1.A.Assign.BlessingOf(OR.guid, b) == "might" and ovOf(c1, OR.guid, b).from == BR.guid, "the leader's Might stays")
  -- the leader's PallyPower (pp): never taught over either
  tickAll(2)
  ppSay(BR, "ASSIGN Orren Lightsworn 2 2")
  tickAll(3)
  assert(ovOf(c1, OR.guid, b).pp, "pp cell")
  fire(c1, "UNIT_AURA", tok)
  tickAll(4)
  assert(c1.A.Assign.BlessingOf(OR.guid, b) == "might" and ovOf(c1, OR.guid, b).pp, "the pp Might stays")
  for _, x in ipairs({ c1, c2, c3 }) do noErrors(x, "teach") end
end)

test("Hands: the restore names the blessing of yours read on them, else your last cast on them, else the share-out", function()
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-J1" })
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-J2" })
  local DU = member({ name = "Dunstan", surname = "Vale", class = "WARRIOR", level = 60, guid = "Player-1-J3" })
  local KE = member({ name = "Kestra", surname = "Moor", class = "WARRIOR", level = 60, guid = "Player-1-J4" })
  local group = { OR, RA, DU, KE }
  local c = client({ me = OR, group = group, spec = 184 })
  knowAll(c, "PALADIN", 60)
  load(c)
  tick(c, 12)
  local Hn, As = c.A.Hands, c.A.Assign
  assert(As.BlessingOf(OR.guid, "WARRIOR:melee") == "might", "the share-out: Might for warriors")
  -- your Kings read on Rask (Dunstan and Kestra without it: nothing taught)
  RA.auras = { { id = 20217, src = "player", exp = c.clock + 3600, dur = 3600 } }
  fire(c, "UNIT_AURA", tokenOf(c, RA))
  tick(c, 4)
  assert(Hn.saw[RA.guid] and Hn.saw[RA.guid].key == "kings", "read: Kings")
  assert(As.BlessingOf(OR.guid, "WARRIOR:melee") == "might", "not every warrior: nothing taught")
  RA.auras = {}
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Rask", "cast-f1", 1044)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f1", 1044)
  tick(c, 1)
  -- your last cast on Dunstan: Kings (no aura read)
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Dunstan", "cast-k1", 20217)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-k1", 20217)
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Dunstan", "cast-f2", 1044)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f2", 1044)
  tick(c, 1)
  -- Kestra: neither
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Kestra", "cast-f3", 1044)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f3", 1044)
  tick(c, 16)
  assert(Hn.pending[RA.guid] and Hn.pending[RA.guid].bless == "kings", "Rask: the Kings read: " .. tostring(Hn.pending[RA.guid] and Hn.pending[RA.guid].bless))
  assert(Hn.pending[DU.guid] and Hn.pending[DU.guid].bless == "kings", "Dunstan: your last cast")
  assert(Hn.pending[KE.guid] and Hn.pending[KE.guid].bless == "might", "Kestra: the share-out")
  local rb = c.env.CuteAurasRestore
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == RA and rb:GetAttribute("spell") == 20217, "the click casts Kings on Rask")
  -- your Might cast on Rask after that read, then a Freedom: the newer, your cast, names Might
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Rask", "cast-m1", 25291)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-m1", 25291)
  assert(not Hn.pending[RA.guid], "a blessing of yours ends the restore")
  tick(c, 1)
  fire(c, "UNIT_SPELLCAST_SENT", "player", "Rask", "cast-f4", 1044)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f4", 1044)
  tick(c, 12)
  assert(Hn.pending[RA.guid] and Hn.pending[RA.guid].bless == "might", "the newer cast over the older read")
  noErrors(c, "hands restore")
end)

test("data: Forever's blessings are Kings, Might and Wisdom; no Salvation, Light or Sanctuary in Data.lua", function()
  local keys = {}
  for k in pairs(D.BLESS) do keys[#keys + 1] = k end
  table.sort(keys)
  assert(table.concat(keys, ",") == "kings,might,wisdom", table.concat(keys, ","))
  local src = assert(io.open(DIR .. "Data.lua")):read("*a")
  for _, id in ipairs({ 1038, 19977, 25890, 25895, 20911 }) do
    assert(not src:find("%f[%d]" .. id .. "%f[%D]"), "spell " .. id .. " in Data.lua")
  end
end)

test("Blessings tab with Ysolde on PallyPower: their column shows their row, its cell says Set in PallyPower and does not click; the title and the lines say so", function()
  local g = ppParty()
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  local c = g.c1
  c.A.Window.Open("blessings")
  local bp = c.A.Window.pages.blessings
  assert(bp.title.__text == "Ysolde uses PallyPower: shown as set there. Click your column; right-click for Cute Auras' choice.", bp.title.__text)
  FITS(bp.title, "the title")
  local cell = gridCell(c, g.YS.guid, "ROGUE:melee")
  assert(cell, "their column")
  assert(cell.icon.__tex == c.A.Look.SpellIcon(D.BLESS.might.ranks[1], D.BLESS.might.icon), "their Might for rogues")
  c.hover(cell)
  local tl = c.env.GameTooltip.lines
  assert(tl[1] == "Blessing of Might" and tl[2] == "Set in PallyPower." and tl[3] == "Change it in PallyPower." and #tl == 3, table.concat(tl, " / "))
  -- (the leader's grid: their cells do not click there either)
  local c3 = g.c3
  c3.A.Window.Open("blessings")
  c3.click(gridCell(c3, g.YS.guid, "ROGUE:melee"))
  c3.click(gridCell(c3, g.YS.guid, "ROGUE:melee"), "RightButton")
  tickAll(2)
  for _, x in ipairs(g.all) do assert(x.A.Assign.overrides[g.YS.guid] == nil, "their cells do not click") end
  local texts = {}
  for _, t in ipairs(bp.lines) do if t:IsShown() then texts[#texts + 1] = t.__text end end
  local all = table.concat(texts, "\n")
  assert(all:find("Set in PallyPower: Ysolde.", 1, true), all)
  local without
  for _, t in ipairs(texts) do if t:find("^Without Cute Auras") then without = t end end
  assert(without and without:find("Rask", 1, true) and not without:find("Ysolde", 1, true), tostring(without))
  for _, t in ipairs(bp.lines) do if t:IsShown() then FITS(t, "a line under the grid") end end
  -- a cell of Orren's the leader set in PallyPower
  ppSay(g.BR, "ASSIGN Orren Lightsworn 2 3")
  tickAll(3)
  c.A.Window.Refresh()
  c.hover(gridCell(c, g.OR.guid, "ROGUE:melee"))
  assert(c.env.GameTooltip.lines[2] == "Set by the leader in PallyPower.", tostring(c.env.GameTooltip.lines[2]))
  for _, x in ipairs(g.all) do noErrors(x, "tab") end
end)

----------------------------------------------------------------------------
-- consumables (0.2.3): the Consumables tab's choices, what a carried item asks with no habit, groups, quiet, Well Fed,
-- the shared potion cooldown, the 0.2.2 saves, the tab's fit, an item the client has no data for yet, the bar's menu,
-- a weapon's oil
----------------------------------------------------------------------------
local CN = {
  mongoose = { 13452, "Elixir of the Mongoose", 0, 2, 17538 }, gagi = { 9187, "Elixir of Greater Agility", 0, 2, 11334 },
  garcane = { 13454, "Greater Arcane Elixir", 0, 2, 17539 }, giants = { 9206, "Elixir of Giants", 0, 2, 11405 },
  titans = { 13510, "Flask of the Titans", 0, 3, 17626 }, wisdom = { 13511, "Flask of Distilled Wisdom", 0, 3, 17627 },
  stone = { 13455, "Greater Stoneshield Potion", 0, 1, 17540 }, heal = { 13446, "Major Healing Potion", 0, 1, 17534 },
  zanza = { 20079, "Spirit of Zanza", 0, 8, 24382 }, rum = { 21151, "Rumsey Rum Black Label", 0, 5, 25804 },
  disguise = { 990800, "Venture Co. Disguise", 12, 0, 990801 }, wizard = { 20749, "Brilliant Wizard Oil", 0, 8, 25122 },
  manaoil = { 20748, "Brilliant Mana Oil", 0, 8, 25123 }, scroll = { 10305, "Scroll of Protection IV", 0, 4, 12175 },
  juju = { 12460, "Juju Might", 12, 0, 16329 },
}
local DUMPLINGS = 20452
-- a client carrying these (CN entries, 5 each; food: Smoked Desert Dumplings), its role chosen when given
local function consumer(o)
  local me = member({ name = o.name or "Sipper", class = o.class or "WARRIOR", level = 60 })
  local db = o.db or {}
  if o.role then db.chars = db.chars or {}; db.chars[me.guid] = db.chars[me.guid] or {}; db.chars[me.guid].role = o.role end
  local c = client({ me = me, db = db })
  local slot = 0
  for _, x in ipairs(o.items or {}) do
    c.items[x[1]] = { name = x[2], classID = x[3], subID = x[4], spell = x[5] }
    slot = slot + 1
    c.bags[#c.bags + 1] = { id = x[1], bag = 0, slot = slot, count = 5 }
  end
  if o.food then
    c.items[DUMPLINGS] = { name = "Smoked Desert Dumplings", classID = 0, subID = 5, ilvl = 55, minLevel = 45, price = 50 }
    slot = slot + 1
    c.bags[#c.bags + 1] = { id = DUMPLINGS, bag = 0, slot = slot, count = 5 }
  end
  load(c)
  tick(c, 1)
  return c, me
end
-- where you stand: nil (the open world), "party", "raid", "pvp"
local function goTo(c, kind) c.instance = kind; fire(c, "ZONE_CHANGED_NEW_AREA"); tick(c, 2) end
local function auraOn(c, me, spell, left)
  for i = #me.auras, 1, -1 do if me.auras[i].id == spell then table.remove(me.auras, i) end end
  me.auras[#me.auras + 1] = { id = spell, src = "player", exp = c.clock + (left or 3600), dur = 3600 }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
end
local function auraOff(c, me, spell)
  for i = #me.auras, 1, -1 do if me.auras[i].id == spell then table.remove(me.auras, i) end end
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
end
local function consumeKeys(c)
  local t = {}
  for _, r in ipairs(shown(c, "mine")) do if r.key:find("^consume") or r.key == "food" then t[#t + 1] = r.key end end
  return table.concat(t, " ")
end
-- the Consumables tab, and an item's row on it
local function cnPage(c) c.A.Window.Open("consume"); return c.A.Window.pages.consume end
local function cnRow(page, id)
  page:Sync()
  for _, r in ipairs(page.rows) do if r.id == id and r.name:IsShown() then return r end end
  return nil
end

test("consumables: a tank's carried elixir is asked in a 5-man with no habit; the world only once chosen; a city asks nothing; a role only guessed hides nothing", function()
  local c = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose } })
  goTo(c, "party")
  local rec = find(shown(c, "mine"), "consume13452")
  assert(rec and rec.word == "Drink" and rec.click.item == 13452 and rec.click.unit == "player", "a 5-man: drink it, on you: " .. keysOf(shown(c, "mine")))
  assert(rec.why == "It fits your role.", tostring(rec.why))
  goTo(c, nil)
  assert(not find(shown(c, "mine"), "consume13452"), "the open world: elixirs are off there by default")
  local page = cnPage(c)
  local row = cnRow(page, 13452)
  assert(row and row.state.__text == "Not here" and not row.chips[1].on and row.chips[3].on, "Not here; World off, 5-man on: " .. tostring(row and row.state.__text))
  c.click(row.chips[1])
  tick(c, 1)
  assert(c.A.Consume.Settings().items[13452].solo == true, "World chosen")
  rec = find(shown(c, "mine"), "consume13452")
  assert(rec and rec.why == "You chose it for here.", "World clicked: asked in the open world")
  -- a city or an inn: nothing on your part; only a ready check asks there
  c.resting = true; fire(c, "PLAYER_UPDATE_RESTING"); tick(c, 1)
  assert(not find(shown(c, "mine"), "consume13452"), "resting: nothing asked")
  row = cnRow(page, 13452)
  assert(row.state.__text == "In town", row.state.__text)
  assert(page.here.__text == "Here: World, in a city or inn: only a ready check asks.", page.here.__text)
  FITS(page.here, "the top line")
  c.resting = false; fire(c, "PLAYER_UPDATE_RESTING"); tick(c, 1)
  -- your role Auto, no talents, no group mark: the class's guess, which hides nothing
  c.A.Char().role = nil
  local role, spec, from = c.A.Roster.MyRole()
  assert(role == "healer" and spec == nil and from == "class", "a paladin's guess: " .. tostring(role) .. " " .. tostring(from))
  goTo(c, "party")
  assert(find(shown(c, "mine"), "consume13452"), "a guessed healer is still asked for the Mongoose")
  page:Sync()
  assert(page.here.__text == "Here: 5-man. Your role: Healer (a guess: Settings, Your role).", page.here.__text)
  FITS(page.here, "the top line")
  c.A.Char().role = "tank"
  page:Sync()
  assert(page.here.__text == "Here: 5-man. Your role: Tank (your choice).", page.here.__text)
  noErrors(c)
end)

test("consumables: a tank's Greater Arcane Elixir is not their role in a raid; Raid clicked, it is asked there and at a ready check, whatever the role", function()
  local c = consumer({ class = "WARRIOR", role = "tank", items = { CN.garcane } })
  goTo(c, "raid")
  assert(not find(shown(c, "mine"), "consume13454"), "spell damage is no tank's")
  local page = cnPage(c)
  local row = cnRow(page, 13454)
  assert(row.state.__text == "Not your role" and not row.chips[4].on, row.state.__text)
  c.click(row.chips[4])
  tick(c, 1)
  assert(find(shown(c, "mine"), "consume13454"), "Raid chosen: asked")
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(find(shown(c, "pull"), "flask13454"), "and before the pull: " .. pullKeys(c))
  c.A.Char().role = "caster"; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(find(shown(c, "pull"), "flask13454"), "a caster: still")
  c.A.Char().role = "tank"; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(find(shown(c, "pull"), "flask13454"), "a tank again: still, its own choice")
  noErrors(c)
end)

test("consumables: a kind's default off leaves an item with its own choice on; its own Raid off hides it at a ready check too; Never everywhere; Back to the defaults", function()
  local c = consumer({ class = "WARRIOR", role = "melee", items = { CN.mongoose, CN.giants } })
  goTo(c, "raid")
  assert(find(shown(c, "mine"), "consume13452") and find(shown(c, "mine"), "consume9206"), "both fit a melee in a raid: " .. consumeKeys(c))
  local page = cnPage(c)
  -- Elixirs' default for raids off: neither (no choice of their own)
  local head
  for _, h in ipairs(page.heads) do if h.name.__text == "Elixirs" and h.name:IsShown() then head = h end end
  assert(head and head.chips[4].on and head.chips[4].outline, "the Elixirs' defaults, outlined")
  c.click(head.chips[4]); tick(c, 1)
  assert(c.A.Consume.Settings().kinds.elixir.raid == false, "the default off")
  assert(not find(shown(c, "mine"), "consume13452") and not find(shown(c, "mine"), "consume9206"), "no elixir in a raid now: " .. consumeKeys(c))
  -- the Mongoose's own Raid on: it alone
  c.click(cnRow(page, 13452).chips[4]); tick(c, 1)
  assert(find(shown(c, "mine"), "consume13452") and not find(shown(c, "mine"), "consume9206"), "its own choice: " .. consumeKeys(c))
  -- its own Raid off: not at a ready check either (Giants fits and is asked there: the kinds don't limit a ready check)
  c.click(cnRow(page, 13452).chips[4]); tick(c, 1)
  assert(c.A.Consume.Settings().items[13452].raid == false, "Raid off by its own choice")
  fire(c, "READY_CHECK"); tick(c, 4)
  local keys = pullKeys(c)
  assert(not keys:find("flask13452") and keys:find("flask9206"), "a ready check: " .. keys)
  c.A.Bar.PullEnd(); tick(c, 1)
  -- Never: nowhere
  c.click(cnRow(page, 13452).never); tick(c, 1)
  assert(c.A.Settings().never["consume:13452"], "the Never key")
  local row = cnRow(page, 13452)
  assert(row.state.__text == "Never" and row.chips[1].__alpha == 0.4, "Never: its places dimmed")
  for _, w in ipairs({ "solo", "pvp", "dungeon", "raid" }) do assert(not c.A.Consume.Asks(13452, w), "never asked in " .. w) end
  -- right-click the row: back to the defaults
  c.click(row.hit, "RightButton")
  local menu = c.menus[#c.menus]
  assert(menu[1].text == "Back to the defaults", tostring(menu[1] and menu[1].text))
  menu[1].fn()
  assert(c.A.Consume.Settings().items[13452] == nil, "its choice gone")
  noErrors(c)
end)

test("consumables: kin elixirs are one group: the one used last; One like it on; seen on you together, both asked", function()
  local c, me = consumer({ class = "ROGUE", role = "melee", items = { CN.mongoose, CN.gagi } })
  local h = c.A.Char().consume
  h[13452] = { hits = 1, miss = 0, at = 100, spell = 17538 }
  h[9187] = { hits = 1, miss = 0, at = 200, spell = 11334 }
  goTo(c, "party")
  assert(consumeKeys(c) == "consume9187", "one icon, the one used last: " .. consumeKeys(c))
  auraOn(c, me, 17538)
  assert(consumeKeys(c) == "", "the Mongoose on: nothing: " .. consumeKeys(c))
  local page = cnPage(c)
  assert(cnRow(page, 9187).state.__text == "One like it on", cnRow(page, 9187).state.__text)
  assert(cnRow(page, 13452).state.__text:find("^On you %d"), cnRow(page, 13452).state.__text)
  c.hover(cnRow(page, 9187).hit)
  assert(table.concat(c.env.GameTooltip.lines, " | "):find("Replaces: Elixir of the Mongoose.", 1, true), table.concat(c.env.GameTooltip.lines, " | "))
  -- both on at once: they stack, so no group
  auraOn(c, me, 11334)
  assert(c.A.Acct().kinStacks["elixir:agi"] == true, "the kin let go")
  auraOff(c, me, 17538); auraOff(c, me, 11334)
  assert(find(shown(c, "mine"), "consume13452") and find(shown(c, "mine"), "consume9187"), "both asked: " .. consumeKeys(c))
  noErrors(c)
end)

test("consumables: one flask at a time until two are seen together", function()
  local c, me = consumer({ class = "PRIEST", role = "healer", items = { CN.titans, CN.wisdom } })
  goTo(c, "raid")
  c.A.Consume.SetChoice(13511, "raid", true)
  auraOn(c, me, 17626)
  assert(not find(shown(c, "mine"), "consume13511"), "the Titans on: Distilled Wisdom not asked: " .. consumeKeys(c))
  local page = cnPage(c)
  c.hover(cnRow(page, 13511).hit)
  assert(table.concat(c.env.GameTooltip.lines, " | "):find("One flask at a time.", 1, true), "its tooltip says so")
  auraOn(c, me, 17627)
  assert(c.A.Acct().flasksStack == true, "two flasks seen together")
  auraOff(c, me, 17627)
  assert(find(shown(c, "mine"), "consume13511"), "Distilled Wisdom asked with the Titans on: " .. consumeKeys(c))
  noErrors(c)
end)

test("consumables: quiet: three times 600 s on screen unused; a use or a chip clears it; a chosen one never; a ready check still asks; a fight's time is not on screen", function()
  local c = consumer({ class = "WARRIOR", role = "melee", items = { CN.mongoose } })
  local Cn = c.A.Consume
  goTo(c, "party")
  assert(find(shown(c, "mine"), "consume13452"), "asked")
  tick(c, 601)
  assert(Cn.MissCount(13452) == 1, "ten minutes on screen: a miss (" .. Cn.MissCount(13452) .. ")")
  tick(c, 600); tick(c, 600)
  assert(c.A.Char().consumeQuiet[13452] and not find(shown(c, "mine"), "consume13452"), "three misses: quiet, not asked")
  local page = cnPage(c)
  assert(cnRow(page, 13452).state.__text == "Unused", cnRow(page, 13452).state.__text)
  c.hover(cnRow(page, 13452).hit)
  assert(table.concat(c.env.GameTooltip.lines, " | "):find("Shown 30 minutes and not used", 1, true), "its tooltip says why")
  -- a ready check still asks it
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(find(shown(c, "pull"), "flask13452"), "a ready check ignores quiet: " .. pullKeys(c))
  c.A.Bar.PullEnd(); tick(c, 1)
  -- a use lets it speak again
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-q1", 17538); tick(c, 8)
  assert(c.A.Char().consumeQuiet[13452] == nil and find(shown(c, "mine"), "consume13452"), "used: asked again")
  -- quiet again, then a chip on its row
  c.A.Char().consumeQuiet[13452] = 1; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(not find(shown(c, "mine"), "consume13452"), "quiet")
  c.click(cnRow(page, 13452).chips[3]); tick(c, 1)
  assert(c.A.Char().consumeQuiet[13452] == nil and c.A.Consume.Settings().items[13452].dungeon == true, "a chip click: chosen, not quiet")
  -- chosen: never quiet
  tick(c, 601); tick(c, 600); tick(c, 600)
  assert(c.A.Char().consumeQuiet[13452] == nil and find(shown(c, "mine"), "consume13452"), "a chosen one is never quieted")
  noErrors(c)
  -- time on screen: a minute in a fight (yours hidden) and a minute out, round after round
  local c2 = consumer({ class = "WARRIOR", role = "melee", items = { CN.mongoose } })
  goTo(c2, "party")
  for round = 1, 10 do
    fight(c2, true); tick(c2, 60)
    fight(c2, false); tick(c2, 60)
    local n = c2.A.Consume.MissCount(13452)
    if round < 10 then assert(n == 0, "round " .. round .. ": no miss yet, " .. n)
    else assert(n == 1, "round 10: the first miss, " .. n) end
  end
  noErrors(c2)
end)

test("consumables: a use in a fight counts: two uses make a habit once the fight is over; a use waits for auras that can be read", function()
  local c, me = consumer({ class = "WARRIOR", role = "melee", items = { CN.mongoose } })
  fight(c, true)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f1", 17538)
  me.auras = { { id = 17538, src = "player", exp = c.clock + 3600, dur = 3600 } }
  tick(c, 30)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f2", 17538)
  tick(c, 30)
  fight(c, false); tick(c, 3)
  local e = c.A.Char().consume[13452]
  assert(e and e.hits == 2, "two uses in the fight: a habit (" .. tostring(e and e.hits) .. ")")
  -- a use whose aura can't be read for a while after the fight: still counted at the first read that sees
  local c2, me2 = consumer({ class = "WARRIOR", role = "melee", items = { CN.giants } })
  fight(c2, true)
  fire(c2, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-g1", 11405)
  me2.auras = { { id = 11405, src = "player", exp = c2.clock + 3600, dur = 3600 } }
  c2.secretAuras = true
  fight(c2, false); tick(c2, 10)
  c2.secretAuras = false
  tick(c2, 3)
  local e2 = c2.A.Char().consume[9206]
  assert(e2 and e2.hits == 1, "counted after the auras could be read (" .. tostring(e2 and e2.hits) .. ")")
  noErrors(c); noErrors(c2)
end)

test("consumables: Well Fed in a 5-man and a raid, not in a battleground unless chosen; the world is the camp's Eat; its last 2 minutes anywhere; its Never everywhere", function()
  local c, me = consumer({ class = "WARRIOR", role = "melee", food = true })
  goTo(c, "party")
  local fed = find(shown(c, "mine"), "food")
  assert(fed and fed.word == "Eat" and fed.click.item == DUMPLINGS, "a 5-man: eat")
  goTo(c, "raid")
  assert(find(shown(c, "mine"), "food"), "a raid: eat")
  goTo(c, "pvp")
  assert(not find(shown(c, "mine"), "food"), "a battleground: not by default")
  c.A.Consume.SetChoice("fed", "pvp", true); tick(c, 1)
  assert(find(shown(c, "mine"), "food"), "its PvP chosen: eat")
  goTo(c, nil)
  assert(find(shown(c, "camp"), "eat") and not find(shown(c, "mine"), "food"), "the open world: the camp's Eat")
  c.A.Consume.SetChoice("fed", "solo", false); c.A.Bar.Dirty("all"); tick(c, 1)
  assert(not find(shown(c, "camp"), "eat"), "World off: no camp Eat")
  -- under two minutes: its countdown anywhere out of town, every chip off
  for _, w in ipairs({ "pvp", "dungeon", "raid" }) do c.A.Consume.SetChoice("fed", w, false) end
  auraOn(c, me, 19705, 100)
  fed = find(shown(c, "mine"), "food")
  assert(fed and fed.status == "warn" and fed.word:find("^1:"), "the open world, under 2 minutes: " .. tostring(fed and fed.word))
  goTo(c, "raid")
  assert(find(shown(c, "mine"), "food"), "a raid, every chip off: still the countdown")
  local page = cnPage(c)
  c.hover(cnRow(page, "fed").hit)
  assert(table.concat(c.env.GameTooltip.lines, " | "):find("Its last 2 minutes count down wherever you are, out of town.", 1, true), "Well Fed's tooltip")
  -- Never: no Eat, no countdown, no pull food, no camp Eat
  c.A.Consume.ClearChoice("fed")
  c.click(cnRow(page, "fed").never); tick(c, 1)
  assert(c.A.Settings().never.eat, "Well Fed's Never is eat")
  assert(not find(shown(c, "mine"), "food"), "no countdown")
  auraOff(c, me, 19705)
  assert(not find(shown(c, "mine"), "food"), "no Eat")
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(not find(shown(c, "pull"), "pullfood"), "no food before the pull")
  c.A.Bar.PullEnd(); goTo(c, nil)
  assert(not find(shown(c, "camp"), "eat"), "no camp Eat")
  noErrors(c)
end)

test("consumables: a Greater Stoneshield Potion is asked only where chosen, after flasks and elixirs before the pull; the potions' shared cooldown waits", function()
  local c = consumer({ class = "WARRIOR", role = "tank", items = { CN.stone, CN.heal, CN.titans, CN.mongoose, CN.giants } })
  goTo(c, "raid")
  assert(not find(shown(c, "mine"), "consume13455"), "a potion: nowhere by default")
  local page = cnPage(c)
  local row = cnRow(page, 13455)
  local potions
  for _, h in ipairs(page.heads) do if h.name.__text == "Potions" and h.name:IsShown() then potions = h end end
  assert(row and potions, "its row under Potions")
  for j = 1, 4 do assert(not row.chips[j].on, "every chip off") end
  assert(cnRow(page, 13446) == nil, "a healing potion has no row")
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(not find(shown(c, "pull"), "flask13455"), "not before the pull either: " .. pullKeys(c))
  c.A.Bar.PullEnd(); tick(c, 1)
  c.click(row.chips[4]); tick(c, 1)
  local rec = find(shown(c, "mine"), "consume13455")
  assert(rec and rec.word == "Drink" and rec.lit, "chosen for Raid: asked: " .. consumeKeys(c))
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(pullKeys(c) == "flask13510 flask9206 flask13452 flask13455", "after the flask and elixirs, four: " .. pullKeys(c))
  c.A.Bar.PullEnd(); tick(c, 1)
  -- a Major Healing Potion drunk 30 s ago: every potion's 2 minutes
  for _, b in ipairs(c.bags) do if b.id == 13455 or b.id == 13446 then b.cdStart, b.cd = c.clock - 30, 120 end end
  row = cnRow(page, 13455)
  assert(row.state.__text == "Cooldown 1:30", row.state.__text)
  fire(c, "BAG_UPDATE_COOLDOWN"); tick(c, 1)
  rec = find(shown(c, "mine"), "consume13455")
  assert(rec and not rec.lit and rec.cdDur == 120, "waiting, its sweep")
  assert(icon(c, "own", "consume13455"):GetAttribute("type1") == nil, "no click while it waits")
  tick(c, 91)
  rec = find(shown(c, "mine"), "consume13455")
  assert(rec and rec.lit and not rec.cdDur, "its cooldown over: lit, with no event")
  noErrors(c)
end)

test("consumables: Spirit of Zanza and Rumsey Rum are Other, asked in a raid for a melee; a disguise or a healing potion never has a row", function()
  local c = consumer({ class = "ROGUE", role = "melee", items = { CN.zanza, CN.rum, CN.disguise, CN.heal } })
  assert(c.A.Consume.KindOf(20079) == "other" and c.A.Consume.KindOf(21151) == "other", "both Other")
  assert(not c.A.Buffs.Fits(20079, "melee"), "Spirit alone is no melee's")
  goTo(c, "raid")
  assert(find(shown(c, "mine"), "consume20079") and find(shown(c, "mine"), "consume21151"), "both asked: " .. consumeKeys(c))
  local page = cnPage(c)
  assert(cnRow(page, 20079) and cnRow(page, 21151), "their rows")
  assert(cnRow(page, 990800) == nil and cnRow(page, 13446) == nil, "no row for a disguise or a healing potion")
  assert(c.A.Consume.KindOf(990800) == nil, "a disguise is no consumable")
  noErrors(c)
end)

test("consumables: 0.2.2 saves: Off, Instances, Always and Ready check keep asking what they asked; the old Nevers a member each", function()
  -- Off
  local c = consumer({ class = "WARRIOR", role = "melee", food = true, items = { CN.mongoose }, db = { settings = { consume = "off" } } })
  local s = c.A.Settings()
  assert(s.consume == nil and s.consumables.on == false and s.consumables.habits == "inst", "Off: off")
  assert(c.A.Settings().consume == nil, "never put back")
  c.A.Window.Open("settings")
  local pull = widget(c.A.Window.pages.settings, "Before the pull: consumables Off")
  assert(pull and pull.__alpha == 0.45, "Before the pull greyed, saying consumables are Off")
  assert(find(shown(c, "camp"), "eat"), "the camp's Eat in the open world still")
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(#shown(c, "pull") == 0, "nothing at a ready check: " .. pullKeys(c))
  noErrors(c)
  -- Instances, with a potion and a flask habit: both in a 5-man and a raid
  local habits = { [13455] = { hits = 2, miss = 0, spell = 17540 }, [13510] = { hits = 2, miss = 0, spell = 17626 } }
  local function charDb(name, settings, h)
    return { settings = settings, chars = { ["Player-1-" .. name] = { role = "melee", consume = h } } }
  end
  local c2 = consumer({ name = "Inst", items = { CN.stone, CN.titans }, db = charDb("Inst", { consume = "instance" }, habits) })
  assert(c2.A.Consume.Settings().habits == "inst" and c2.A.Consume.Settings().kinds.potion.raid == false, "Instances: the defaults")
  for _, where in ipairs({ "party", "raid" }) do
    goTo(c2, where)
    assert(find(shown(c2, "mine"), "consume13455") and find(shown(c2, "mine"), "consume13510"), where .. ": both habits: " .. consumeKeys(c2))
  end
  noErrors(c2)
  -- Always: habits in the open world too, and only habits there
  local c3 = consumer({ name = "Alw", items = { CN.stone, CN.mongoose }, db = charDb("Alw", { consume = "always" }, { [13455] = { hits = 2, miss = 0, spell = 17540 } }) })
  assert(c3.A.Consume.Settings().habits == "world", "Always: world")
  goTo(c3, nil)
  assert(find(shown(c3, "mine"), "consume13455") and not find(shown(c3, "mine"), "consume13452"), "the world: the habit, not the fitting elixir: " .. consumeKeys(c3))
  noErrors(c3)
  -- Ready check: habits only before the pull, every kind off, Well Fed's countdown still
  local c4, me4 = consumer({ name = "Pul", food = true, items = { CN.stone, CN.mongoose }, db = charDb("Pul", { consume = "pull" }, { [13455] = { hits = 2, miss = 0, spell = 17540 } }) })
  local t4 = c4.A.Consume.Settings()
  assert(t4.habits == "pull" and t4.kinds.elixir.dungeon == false and t4.kinds.fed.solo == true and t4.kinds.fed.raid == false, "Ready check: kinds off but Well Fed's world")
  goTo(c4, "party")
  assert(consumeKeys(c4) == "", "a 5-man: nothing: " .. consumeKeys(c4))
  auraOn(c4, me4, 19705, 100)
  assert(consumeKeys(c4) == "food", "Well Fed's countdown only: " .. consumeKeys(c4))
  auraOff(c4, me4, 19705)
  fire(c4, "READY_CHECK"); tick(c4, 4)
  local keys = pullKeys(c4)
  assert(keys:find("pullfood") and keys:find("flask13452") and keys:find("flask13455"), "everything at a ready check: " .. keys)
  noErrors(c4)
  -- the Nevers: flask:<g> before the pull, and out of a fight but as a habit (0.2.2 asked it there only as one),
  -- consume:<g> everywhere, a key for each member of its learned group
  local c5 = consumer({ name = "Nev", items = { CN.mongoose, CN.gagi }, db = { settings = { consume = "instance", never = { ["flask:13452"] = "Elixir of the Mongoose" } },
    acct = { pairs = { [13452] = 9187 } }, chars = { ["Player-1-Nev"] = { role = "melee" } } } })
  local never = c5.A.Settings().never
  assert(never["flask:13452"] == nil and never["pull:13452"] and never["pull:9187"], "flask: became pull: for both")
  fire(c5, "READY_CHECK"); tick(c5, 4)
  assert(not pullKeys(c5):find("flask13452") and not pullKeys(c5):find("flask9187"), "hidden before the pull: " .. pullKeys(c5))
  c5.A.Bar.PullEnd(); goTo(c5, "party")
  assert(consumeKeys(c5) == "", "no habit: not asked in a 5-man either: " .. consumeKeys(c5))
  local page = cnPage(c5)
  c5.hover(cnRow(page, 13452).hit)
  local tl = table.concat(c5.env.GameTooltip.lines, " | ")
  assert(tl:find("A Never from 0.2.2: not before the pull, and elsewhere only as a habit or where you choose.", 1, true)
    and tl:find("Right-click: back to the defaults.", 1, true), tl)
  local c6 = consumer({ name = "Nev2", items = { CN.mongoose, CN.gagi }, db = { settings = { consume = "instance", never = { ["consume:13452"] = "Elixir of the Mongoose" } },
    acct = { pairs = { [13452] = 9187 } }, chars = { ["Player-1-Nev2"] = { role = "melee" } } } })
  never = c6.A.Settings().never
  assert(never["consume:13452"] and never["consume:9187"], "consume: for both")
  goTo(c6, "party")
  assert(consumeKeys(c6) == "", "hidden in a 5-man: " .. consumeKeys(c6))
  fire(c6, "READY_CHECK"); tick(c6, 4)
  assert(not pullKeys(c6):find("flask13452") and not pullKeys(c6):find("flask9187"), "and at a ready check now: " .. pullKeys(c6))
  noErrors(c5); noErrors(c6)
end)

test("Consumables tab: twenty items in five kinds and Well Fed fit the page; words fit their boxes; the scroll counts headers and rows, never ends on a header", function()
  local list = { CN.titans, CN.wisdom, { 13512, "Flask of Supreme Power", 0, 3, 17628 }, { 13513, "Flask of Chromatic Resistance", 0, 3, 17629 },
    CN.mongoose, CN.gagi, CN.giants, CN.garcane, { 3825, "Elixir of Lesser Fortitude", 0, 2, 3593 }, { 3391, "Elixir of Ogre Strength", 0, 2, 3164 },
    CN.stone, { 13457, "Greater Fire Protection Potion", 0, 1, 17543 }, { 4623, "Lesser Stoneshield Potion", 0, 1, 4941 }, { 9036, "Magic Resistance Potion", 0, 1, 11364 },
    CN.scroll, { 954, "Scroll of Strength", 0, 4, 8118 }, { 1477, "Scroll of Agility II", 0, 4, 8116 },
    CN.zanza, CN.rum, CN.juju }
  assert(#list == 20, "twenty")
  local c = consumer({ class = "WARRIOR", role = "melee", food = true, items = list })
  c.bagSlots = 24
  for _, b in ipairs(c.bags) do b.count = 200 end
  fire(c, "BAG_UPDATE_DELAYED")
  goTo(c, "raid")
  local page = cnPage(c)
  page.first = 1
  page:Sync()
  -- the state words at their longest, the chips' words
  for _, w in ipairs({ "Cooldown 1:59", "On you 120:00", "One like it on", "Not your role", "In a fight", "None left", "Not here", "Missing", "Unused" }) do
    assert(TEXT_WIDTH(w, 11) <= 90, "a state's word: " .. w)
  end
  for _, w in ipairs({ "World", "PvP", "5-man", "Raid", "Never" }) do assert(TEXT_WIDTH(w, 10) <= 44, "a chip's word: " .. w) end
  -- every D.CONSUME entry's sub line with 200 in your bags
  local Cn = c.A.Consume
  for sp, words in pairs(D.CONSUME) do
    local t = Cn.SubLine(words, 200)
    assert(TEXT_WIDTH(t, 10) <= 220, "a sub line: " .. t .. " (" .. sp .. ")")
  end
  assert(Cn.SubLine(D.CONSUME[16329], 5) == "Attack power. 5 in your bags", Cn.SubLine(D.CONSUME[16329], 5))
  assert(Cn.SubLine("agi crit", 5) == "Agility, crit. 5 in your bags" and Cn.SubLine("agi crit", 0) == "Agility, crit." and Cn.SubLine("", 5) == "5 in your bags", "the sub line's forms")
  -- the rects of every part shown: inside the page, none over another
  local function rectsOf()
    local boxes = {}
    local function add(o, what)
      if not o:IsShown() then return end
      local pt = o.__points[1]
      assert(pt and pt[2] == page and pt[1] == "TOPLEFT", what .. ": placed on the page")
      local x, y, w, h = pt[4], pt[5], o.__w, o.__h
      if o.__kind == "FontString" then
        local tw = TEXT_WIDTH(o.__text, o.__size)
        assert(tw <= o.__w, what .. ": '" .. o.__text .. "' fits its " .. o.__w)
        h = o.__size + 2
        if o.__justify == "RIGHT" then x = x + o.__w - tw end
        w = tw
      end
      assert(x >= 0 and x + w <= 612 and y <= 0 and y - h >= -444, what .. ": inside the page")
      for _, r in ipairs(boxes) do
        assert(x >= r.x + r.w or r.x >= x + w or y - h >= r.y or r.y - r.h >= y, what .. " over " .. r.what)
      end
      boxes[#boxes + 1] = { x = x, y = y, w = w, h = h, what = what }
    end
    add(page.here, "the top line"); add(page.more, "the scroll line"); add(page.empty, "the empty line")
    for i, hd in ipairs(page.heads) do
      add(hd.name, "header " .. i); add(hd.label, "header " .. i .. "'s label"); add(hd.rule, "header " .. i .. "'s rule")
      for j, b in ipairs(hd.chips) do
        add(b, "header " .. i .. "'s chip " .. j)
        if b:IsShown() then assert(b.__points[1][5] - 18 - 5 == hd.rule.__points[1][5], "the chips end 5 px over the rule") end
      end
    end
    for i, r in ipairs(page.rows) do
      add(r.icon, "row " .. i .. "'s icon"); add(r.name, "row " .. i .. "'s name"); add(r.sub, "row " .. i .. "'s sub line"); add(r.state, "row " .. i .. "'s state")
      for j, b in ipairs(r.chips) do add(b, "row " .. i .. "'s chip " .. j) end
      add(r.never, "row " .. i .. "'s Never")
    end
    return #boxes
  end
  rectsOf()
  -- 6 headers and 21 rows: 27 entries, 14 fit
  local seenE = {}
  for _, e in ipairs(page.entries) do seenE[#seenE + 1] = tostring(e.head or e.id) end
  assert(page.total == 27, "entries " .. tostring(page.total) .. ": " .. table.concat(seenE, " "))
  assert(page.more.__text == "Scroll: " .. page.shownFirst .. "-" .. page.shownLast .. " of 27", page.more.__text)
  assert(not page.entries[page.shownLast].head, "never ends on a header")
  local last = page.shownLast
  page.__scripts.OnMouseWheel(page, -1)
  assert(page.shownFirst == 2, "the wheel moves one entry")
  rectsOf()
  for _ = 1, 30 do page.__scripts.OnMouseWheel(page, -1) end
  assert(page.shownLast == 27 and not page.entries[page.shownLast].head, "the end")
  rectsOf()
  for k = 1, 27 do
    page.first = k; page:Sync()
    assert(not page.entries[page.shownLast].head, "a header last at " .. k)
    rectsOf()
  end
  -- the Never chips with consumables off: greyed list, the top line says so
  c.A.Consume.Settings().on = false
  page:Sync()
  assert(page.here.__text == "Off in Settings: nothing here is asked; the camp's Eat follows Camp." and page.list.__alpha == 0.45, page.here.__text)
  FITS(page.here, "the off line")
  -- no items: the empty line under Food
  local c2 = consumer({ class = "WARRIOR", role = "melee" })
  local p2 = cnPage(c2)
  assert(p2.empty:IsShown() and p2.total == 2, "Well Fed alone, and the empty line")
  noErrors(c); noErrors(c2)
end)

test("consumables: an item the client has no data for yet is asked for, never kept as none; its data in, the bar asks with no bag change", function()
  local c = consumer({ class = "WARRIOR", role = "melee" })
  c.items[990900] = { name = "Elixir of the Deep", classID = 0, subID = 2, spell = 990901, uncached = true }
  c.items[990910] = { name = "Rough Stone", classID = 7, subID = 0 }
  SPELL_DESC[990901] = "Increases Agility by 30 for 1 hour."
  c.bags = { { id = 990900, bag = 0, slot = 1, count = 3 }, { id = 990910, bag = 0, slot = 2, count = 3 } }
  fire(c, "BAG_UPDATE_DELAYED")
  goTo(c, "party")
  local Bf = c.A.Buffs
  assert(c.loadAsked and (c.loadAsked[990900] or 0) >= 1, "its data asked for")
  assert(Bf.itemAuraOf[990900] == nil, "never kept as none")
  assert(Bf.itemAuraOf[990910] == false, "a cached item with no use: kept as none")
  assert(not find(shown(c, "mine"), "consume990900"), "not yet")
  c.items[990900].uncached = nil
  fire(c, "GET_ITEM_INFO_RECEIVED", 990900, true); tick(c, 1)
  assert(Bf.itemAuraOf[990900] == 990901 and c.A.Consume.KindOf(990900) == "elixir", "an elixir now")
  assert(find(shown(c, "mine"), "consume990900"), "asked, with no bag event: " .. consumeKeys(c))
  SPELL_DESC[990901] = nil
  noErrors(c)
end)

test("consumables: the bar's right-click: Never names it, Consumables..., Settings..., then Ask for it in World, PvP, 5-man, Raid; the gear's menu the same words", function()
  local c = consumer({ class = "ROGUE", role = "melee", items = { CN.mongoose, CN.gagi } })
  c.A.Char().consume[13452] = { hits = 1, miss = 0, at = 300, spell = 17538 }
  goTo(c, "party")
  assert(consumeKeys(c) == "consume13452", consumeKeys(c))
  c.A.Bar.Menu(icon(c, "own", "consume13452"))
  local m = c.menus[#c.menus]
  local words = {}
  for _, e in ipairs(m) do words[#words + 1] = e.text end
  assert(table.concat(words, ", ") == "Not now, Never: Elixir of the Mongoose, Consumables..., Settings..., Ask for it in, World, PvP, 5-man, Raid", table.concat(words, ", "))
  assert(m[5].kind == "title" and m[6].kind == "check", "a title, then checkboxes")
  assert(m[6].get() == false and m[8].get() == true, "World off, 5-man on")
  m[6].fn()
  assert(c.A.Consume.Settings().items[13452].solo == true and m[6].get() == true, "World chosen from the menu")
  m[3].fn()
  assert(c.A.Window.frame:IsShown() and c.A.Window.pages.consume:IsShown(), "Consumables... opens the tab")
  c.A.Window.Open("settings")
  c.env.SlashCmdList.CUTEAURAS("consumables")
  assert(c.A.Window.pages.consume:IsShown(), "/cauras consumables opens it too")
  -- the diag's line: where you stand, your role and where it came from, the counts; no name
  c.chat = {}
  c.env.SlashCmdList.CUTEAURAS("diag")
  local line
  for _, l in ipairs(c.chat) do if l:find("Consumables on", 1, true) then line = l end end
  assert(line and line:find("habits inst; here 5-man; role melee (your choice); carried 2, fit 2, chosen 0, habits 0, quiet 0, cooling 0; asked 1; never 0, pull-only 0", 1, true), tostring(line))
  assert(not line:find("Sipper", 1, true), "no name")
  m[2].fn(); tick(c, 1)
  assert(c.A.Settings().never["consume:13452"] and consumeKeys(c) == "consume9187", "Never hides the Mongoose alone: " .. consumeKeys(c))
  -- the food's menu: Ask for it in sets Well Fed's
  local G = c.A.Gear
  local gw = {}
  for _, x in ipairs(G.CONTEXTS) do gw[#gw + 1] = x[2] end
  assert(table.concat(gw, ", ") == "World, PvP, 5-man, Raid", "the gear's places: " .. table.concat(gw, ", "))
  noErrors(c)
end)

test("consumables: a weapon's oil chosen for raids on a bare main hand: one weapon16; the one used last; else the lower id", function()
  local c = consumer({ class = "MAGE", role = "caster", items = { CN.wizard } })
  c.items[5005] = { name = "Plain Staff", equipLoc = "INVTYPE_2HWEAPON" }
  c.equipped[16] = 5005
  assert(c.A.Consume.KindOf(20749) == "weapon", "an oil is a weapon's")
  goTo(c, "raid")
  assert(not find(shown(c, "mine"), "weapon16"), "a weapon's oil: nowhere by default")
  c.A.Consume.SetChoice(20749, "raid", true); tick(c, 1)
  local rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.word == "Apply" and rec.click.item == 20749 and rec.click.slot == 16, "the oil on the main hand")
  assert(rec.name == "Your weapon" and rec.why == "Nothing on it: you chose this for here.", tostring(rec.why))
  -- a per-weapon habit too: still one
  c.A.Char().weapon = { [5005] = { item = 20749, hits = 3 } }
  c.A.Bar.Dirty("all"); tick(c, 1)
  local n = 0
  for _, r in ipairs(shown(c, "mine")) do if r.key == "weapon16" then n = n + 1 end end
  assert(n == 1, "one icon a slot: " .. n)
  c.enchant = { [16] = true }; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(not find(shown(c, "mine"), "weapon16"), "something on it: nothing")
  c.enchant = nil
  -- two oils on for raids, neither chosen, no habit of this weapon's (that one would come first): the one used last,
  -- else the lower id
  c.A.Char().weapon = {}
  c.A.Consume.ClearChoice(20749)
  c.A.Consume.SetKindDefault("weapon", "raid", true)
  c.items[20748] = { name = "Brilliant Mana Oil", classID = 0, subID = 8, spell = 25123 }
  c.bags[#c.bags + 1] = { id = 20748, bag = 0, slot = 9, count = 5 }
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 20748, "neither used: the lower id, " .. tostring(rec and rec.click.item))
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-o1", 25122); tick(c, 2)
  c.A.Bar.Dirty("all"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 20749, "the one used last, " .. tostring(rec and rec.click.item))
  local page = cnPage(c)
  assert(cnRow(page, 20749).sub.__text == "Main hand", cnRow(page, 20749).sub.__text)
  noErrors(c)
end)

----------------------------------------------------------------------------
-- the bar (0.2.3): tighter. One fixed grid, every icon on a 36 px step in its part (32 px icons, 4 apart), the parts
-- 8 apart, 4 px of padding; a verb at most 32 px wide, any other word (a member's name) cut to fit on a character
-- boundary, no dots
----------------------------------------------------------------------------
-- the bar's icons as laid out, yours (camp, mine, pull, gear) then the group's
local function barIcons(c)
  local own, grp = {}, {}
  for _, part in ipairs({ "camp", "mine", "pull", "gear" }) do
    for _, rec in ipairs(shown(c, part)) do own[#own + 1] = icon(c, "own", rec.key) end
  end
  for _, rec in ipairs(shown(c, "group")) do grp[#grp + 1] = icon(c, "group", rec.key) end
  return own, grp
end
-- every icon at (i - 1) x 36 in its part, the group's part PADX + yours + 8 in, the bar 8 + its icons' width
local function gridOK(c, label)
  local own, grp = barIcons(c)
  local bar, ownF, grpF = c.env.CuteAurasBar, c.env.CuteAurasBarOwn, c.env.CuteAurasBarGroup
  for which, list in pairs({ own = own, group = grp }) do
    local f = which == "own" and ownF or grpF
    for i, b in ipairs(list) do
      local p = b and b.__points[1]
      assert(b and b:IsShown() and p and p[2] == f and p[4] == (i - 1) * 36 and p[5] == 0,
        string.format("%s: %s icon %d at %s, not %d", label, which, i, tostring(p and p[4]), (i - 1) * 36))
    end
  end
  local nOwn, nGrp = #own, #grp
  local wOwn, wGrp = nOwn > 0 and (nOwn * 36 - 4) or 0, nGrp > 0 and (nGrp * 36 - 4) or 0
  local gap = (nOwn > 0 and nGrp > 0) and 8 or 0
  assert(ownF.__points[1][4] == 4, label .. ": yours 4 px in: " .. tostring(ownF.__points[1][4]))
  assert(grpF.__points[1][4] == 4 + wOwn + gap, string.format("%s: the group's part at %s, not %d", label, tostring(grpF.__points[1][4]), 4 + wOwn + gap))
  assert(bar.__w == 8 + wOwn + gap + wGrp, string.format("%s: the bar %s wide, not %d", label, tostring(bar.__w), 8 + wOwn + gap + wGrp))
  return own, grp
end
-- every shown word fits its 36 px box and is at most 32 wide; a verb (no member's name) whole; neighbours' words 4 px
-- apart or more, across the part gap too
local function wordsOK(c, label)
  local own, grp = barIcons(c)
  local ox, gx = c.env.CuteAurasBarOwn.__points[1][4], c.env.CuteAurasBarGroup.__points[1][4]
  local row = {}
  for _, b in ipairs(own) do row[#row + 1] = { b = b, x = ox + b.__points[1][4] } end
  for _, b in ipairs(grp) do row[#row + 1] = { b = b, x = gx + b.__points[1][4] } end
  for i, e in ipairs(row) do
    local b, rec = e.b, e.b.rec
    local text = b.word.__text
    FITS(b.word, label .. ": " .. rec.key .. "'s word")
    assert(b.word.__w == 36, label .. ": a word's box 36 wide: " .. b.word.__w)
    local w = TEXT_WIDTH(text, 11)
    assert(w <= 32, string.format("%s: '%s' %.1f wide, over 32", label, text, w))
    if not (rec.class and rec.status == nil) then
      assert(text == (rec.word or ""), label .. ": a verb whole: '" .. text .. "' for '" .. tostring(rec.word) .. "'")
      assert(TEXT_WIDTH(rec.word or "", 11) <= 32, label .. ": a verb over 32: " .. tostring(rec.word))
    end
    if i > 1 then
      local a = row[i - 1]
      local aRight = a.x + 16 + TEXT_WIDTH(a.b.word.__text, 11) / 2
      local bLeft = e.x + 16 - w / 2
      assert(aRight + 4 <= bLeft, string.format("%s: '%s' and '%s' %.1f apart", label, a.b.word.__text, text, bLeft - aRight))
    end
  end
  return #row
end
-- the words the providers give the bar, read from the code: every string literal in what a statement assigns to
-- rec.word (a "%" format aside), and the words of the kind tables (Consume.lua's KIND_WORD and LEGACY)
local function splitTop(s)
  local out, cur, depth, q, i = {}, {}, 0, nil, 1
  while i <= #s do
    local ch = s:sub(i, i)
    if q then
      cur[#cur + 1] = ch
      if ch == "\\" then cur[#cur + 1] = s:sub(i + 1, i + 1); i = i + 1 elseif ch == q then q = nil end
    elseif ch == '"' or ch == "'" then q = ch; cur[#cur + 1] = ch
    elseif ch == "(" or ch == "{" or ch == "[" then depth = depth + 1; cur[#cur + 1] = ch
    elseif ch == ")" or ch == "}" or ch == "]" then depth = depth - 1; cur[#cur + 1] = ch
    elseif ch == ";" and depth == 0 then break
    elseif ch == "," and depth == 0 then out[#out + 1] = table.concat(cur); cur = {}
    else cur[#cur + 1] = ch end
    i = i + 1
  end
  out[#out + 1] = table.concat(cur)
  return out
end
local function providerWords()
  local words, n = {}, 0
  local function take(s, where)
    for lit in s:gmatch('"([^"]*)"') do
      if not lit:find("%", 1, true) then
        if not words[lit] then n = n + 1 end
        words[lit] = where
      end
    end
  end
  local toc = assert(io.open(DIR .. "CuteAuras.toc")):read("*a")
  for file in toc:gmatch("\n([%w_]+%.lua)") do
    local ln = 0
    for line in io.lines(DIR .. file) do
      ln = ln + 1
      local where = file .. ":" .. ln
      if not line:find("^%s*%-%-") then
        if line:find("^local KIND_WORD = {") or line:find("^local LEGACY = {") then take(line, where) end
        local from = 1
        while true do
          local s, e = line:find("rec%.word", from)
          if not s then break end
          from = e + 1
          -- (the list it stands in: rec.a, rec.word, rec.b = ...)
          local left, right = line:sub(1, s - 1), line:sub(e + 1)
          local before = 0
          while true do
            local l2 = left:match("^(.-)rec%.[%w_]+%s*,%s*$")
            if not l2 then break end
            left, before = l2, before + 1
          end
          while true do
            local r2 = right:match("^%s*,%s*rec%.[%w_]+(.*)$")
            if not r2 then break end
            right = r2
          end
          local rhs = right:match("^%s*=%s*([^=].*)$")
          if rhs then
            local expr = splitTop(rhs)[before + 1]
            if expr then take(expr, where) end
          end
        end
      end
    end
  end
  return words, n
end

test("the bar's grid: every icon (i - 1) x 36 in its part, the group's part 8 past yours, the bar as wide as its icon count", function()
  -- a paladin with long-named members: blessings in the group's part
  local g = party5long()
  local c = g.c3
  tick(c, 2)
  local _, grp = gridOK(c, "the paladin")
  assert(#grp >= 2, "the paladin's blessings: " .. #grp)
  -- a tank paladin in a 5-man, no spells: Eat and Drink in yours, nothing in the group's
  local d = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose }, food = true })
  goTo(d, "party")
  local own2, grp2 = gridOK(d, "yours alone")
  assert(#own2 >= 2 and #grp2 == 0, "yours alone: " .. #own2 .. " / " .. #grp2)
  -- the priest of the long-named party: both parts
  local p = g.c1
  local own3, grp3 = gridOK(p, "the priest")
  assert(#own3 + #grp3 >= 1, "the priest's bar")
  noErrors(c); noErrors(d); noErrors(p)
end)

-- the mockup's bar: Eat, Buff, Drink, Drink, Apply in yours, four group icons whose lists hold twelve-letter names
local function sceneBar()
  local me = member({ name = "Scener", class = "WARRIOR", level = 60 })
  local c = client({ me = me })
  load(c)
  tick(c, 1)
  local B = c.A.Bar
  local WORDS = { "Eat", "Buff", "Drink", "Drink", "Apply" }
  local NAMES = { { "Bramblewoode", "ROGUE" }, { "Moonwhispers", "PRIEST" }, { "Thunderhoofe", "WARRIOR" }, { "Wardenwallow", "WARRIOR" } }
  B.Add({ key = "scene-mine", part = "mine", order = 1, groups = { "mine" }, read = function(add)
    for i, w in ipairs(WORDS) do
      local rec = add()
      rec.key, rec.tex, rec.lit, rec.word, rec.name = "scene" .. i, 134400, true, w, "Scene " .. i
      if w == "Buff" then rec.status = "warn" end
    end
  end })
  B.Add({ key = "scene-group", part = "group", order = 1, groups = { "group" }, read = function(add)
    for i, n in ipairs(NAMES) do
      local rec = add()
      rec.key, rec.tex, rec.lit, rec.word, rec.class, rec.name = "scene" .. (10 + i), 135987, true, n[1], n[2], "Scene " .. (10 + i)
      rec.flyout = {}
      for j, m in ipairs(NAMES) do rec.flyout[j] = { unit = "player", guid = "Player-1-S" .. j, name = m[1], class = m[2], spell = 1243 } end
    end
  end })
  B.Dirty("all")
  tick(c, 1)
  return c
end

test("the bar's scene: Eat, Buff, Drink, Drink, Apply and four group icons with long names are 332 wide; the diag's Bar line", function()
  local c = sceneBar()
  local own, grp = gridOK(c, "the scene")
  assert(#own == 5 and #grp == 4, "five of yours, four of the group's: " .. #own .. " / " .. #grp)
  assert(c.env.CuteAurasBar.__w == 332, "332 wide: " .. c.env.CuteAurasBar.__w)
  wordsOK(c, "the scene")
  c.chat = {}
  c.A.Diag()
  local line
  for _, l in ipairs(c.chat) do if l:find("Bar: ", 1, true) then line = l end end
  assert(line and line:find("Bar: 9 icons, 332 wide; widest word 29 of 32; names cut 4", 1, true), "the diag's Bar line: " .. tostring(line))
  noErrors(c)
end)

test("the bar's words fit: every word a provider gives is at most 32 wide, every shown word fits its box, neighbours 4 apart", function()
  local words, n = providerWords()
  for _, w in ipairs({ "Eat", "Sit", "Place", "Make", "Buy", "Cook", "Craft", "Light", "Sleep", "Use", "Drink", "Read", "Apply",
      "Buff", "Swap", "Done", "Far", "All on", "You" }) do
    assert(words[w], "the code's word read: " .. w)
  end
  for w, where in pairs(words) do
    assert(TEXT_WIDTH(w, 11) <= 32, string.format("a verb at most 32 wide: '%s' is %.1f (%s)", w, TEXT_WIDTH(w, 11), where))
  end
  assert(n >= 19, "the words read: " .. n)
  -- the shown bars: the scene, the long-named party's paladin and priest, a tank's consumables, an Upgrade's Buff
  local c = sceneBar()
  wordsOK(c, "the scene")
  local g = party5long()
  tick(g.c3, 2)
  assert(wordsOK(g.c3, "the paladin") >= 2, "the paladin's icons")
  wordsOK(g.c1, "the priest")
  local d = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose }, food = true })
  goTo(d, "party")
  assert(wordsOK(d, "the tank") >= 2, "the tank's icons")
  local me = member({ name = "Upri", class = "PRIEST", level = 60 })
  local e = client({ me = me })
  knowAll(e, "PRIEST", 60)
  me.auras = { { id = 10951, src = "player", exp = e.clock + 600, dur = 600 } }
  load(e)
  tick(e, 1)
  assert(wordsOK(e, "the Upgrade") >= 1, "the priest's icons")
  for _, x in ipairs({ c, g.c1, g.c3, d, e }) do noErrors(x) end
end)

test("the bar's words: a name cut on a character boundary (UTF-8), never mid-letter", function()
  local c = client({ me = member({ name = "Utf", class = "MAGE", level = 60 }) })
  load(c)
  tick(c, 1)
  local L = c.A.Look
  -- "Aeroskoebingen" with its letters: AE (C3 86), o-slash (C3 B8) twice
  local full = "\195\134r\195\184sk\195\184bingen"
  local fs = L.Text(c.env.UIParent, 11, L.C.INK, 36)
  for room = 1, 80 do
    local r = L.Fit(fs, full, room)
    assert(full:sub(1, #r) == r and #r >= 2, "a prefix, a letter at least: room " .. room)
    local nextByte = full:byte(#r + 1)
    assert(not (nextByte and nextByte >= 128 and nextByte <= 191), "cut on a character boundary at room " .. room .. ": " .. #r .. " bytes")
    if #r > 2 then assert(TEXT_WIDTH(r, 11) <= room, "fits room " .. room .. ": " .. TEXT_WIDTH(r, 11)) end
  end
  assert(L.Fit(fs, full, L.ROOM) ~= full, "cut at 32")
  -- through the bar's paint: a member named so
  local b = L.Icon(nil, c.env.UIParent, false, true)
  L.Paint(b, { word = full, class = "ROGUE", lit = true })
  local t = b.word.__text
  local nextByte = full:byte(#t + 1)
  assert(full:sub(1, #t) == t and #t < #full and not (nextByte >= 128 and nextByte <= 191), "painted on a boundary: " .. #t)
  assert(b.caWord == full, "the whole word kept")
  noErrors(c)
end)

test("Upgrade is gone: Inner Fire 5 on, rank 6 known, reads Buff in amber; its Never still names the Upgrade; no Upgrade in the code", function()
  local words = providerWords()
  assert(words.Upgrade == nil, "no Upgrade assigned to rec.word: " .. tostring(words.Upgrade))
  local me = member({ name = "Upri", class = "PRIEST", level = 60 })
  local c = client({ me = me })
  knowAll(c, "PRIEST", 60)
  me.auras = { { id = 10951, src = "player", exp = c.clock + 600, dur = 600 } }
  load(c)
  tick(c, 1)
  local rec = find(shown(c, "mine"), "self:innerfire")
  assert(rec and rec.word == "Buff" and rec.status == "warn" and rec.click.spell == 10952, "Buff, warn: " .. tostring(rec and rec.word) .. " " .. tostring(rec and rec.status))
  assert(rec.why == "Rank 5 on you; you know rank 6." and rec.neverName == "Upgrade Inner Fire", tostring(rec.why))
  local b = icon(c, "own", "self:innerfire")
  local WARN = c.A.Look.C.WARN
  assert(b.word.__text == "Buff" and b.word.__textColor[1] == WARN[1] and b.word.__textColor[2] == WARN[2], "Buff in amber")
  c.A.Bar.Menu(b)
  local has = false
  for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Never: Upgrade Inner Fire" then has = true end end
  assert(has, "the menu still reads Never: Upgrade Inner Fire")
  -- gone: the plain Buff, in the ink
  me.auras = {}
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  rec = find(shown(c, "mine"), "self:innerfire")
  local INK = c.A.Look.C.INK
  assert(rec and rec.word == "Buff" and rec.status == nil and b.word.__textColor[1] == INK[1], "the plain Buff in the ink")
  noErrors(c)
end)

----------------------------------------------------------------------------
-- alerts as icons (0.2.3): every alert a 36 px icon by default, its words in the tooltip; one icon a member (a Hand's
-- countdown, then its restore in the same slot); the click icon hidden by its guard as a fight starts; Show as
----------------------------------------------------------------------------
do
  -- (the client's answers the tests read: Freedom's art, the rogue's colour)
  local function realArt(c)
    local tex = c.env.C_Spell.GetSpellTexture
    c.env.C_Spell.GetSpellTexture = function(id) if id == 1044 then return 135968 end return tex(id) end
    rawset(c.env.RAID_CLASS_COLORS, "ROGUE", { r = 1, g = 0.96, b = 0.41 })
  end
  local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end
  local function indexOf(list, v) for i, x in ipairs(list) do if x == v then return i end end end
  local function lines(c, f) local t = tipOf(c, f); return table.concat(t, " | "), #t end

  test("alerts as icons: Freedom in a fight is one 36 px art icon, Freedom's art, its sweep, a pink bar, the rogue's name; the words in its tooltip; silent", function()
    local g = party5long()
    local c = g.c3
    local Al, Hn, C = c.A.Alerts, c.A.Hands, c.A.Look.C
    local rog = g.ROG.guid
    assert(c.A.Settings().alertLook == "icons" and Al.Icons(), "icons by default: " .. tostring(c.A.Settings().alertLook))
    realArt(c)
    fight(c, true)
    local sounds = c.sounds or 0
    local t = c.clock
    hand(c, g.ROG, 1044, 1)
    assert(count(Al.cards) == 1, "one icon")
    local f = Al.cards["hand:" .. rog]
    assert(f and f.__w == 36 and f.__h == 36 and f.icon.__w == 36 and f.icon.__h == 36, "36 x 36: " .. tostring(f and f.__w))
    assert(f.icon.icon.__tex == 135968, "Freedom's art: " .. tostring(f.icon.icon.__tex))
    assert(f.icon.cd.__cd and f.icon.cd.__cd[1] == t and f.icon.cd.__cd[2] == 10, "the game's sweep over its 10 s")
    assert(f.bar:IsShown() and sameColor(f.bar.__color, C.PINK) and f.bar.__w == 36 and f.bar.__h == 2, "a pink bar")
    local bp = f.bar.__points[1]
    assert(bp[1] == "TOP" and bp[2] == f.icon and bp[3] == "BOTTOM" and bp[5] == -4, "4 px under the icon")
    assert(f.name:IsShown() and f.name.__text == "Bramblewoode" and f.name.__size == 10 and f.name.__w == 76, "the name: " .. f.name.__text)
    assert(f.name.__textColor[1] == 1 and f.name.__textColor[2] == 0.96 and f.name.__textColor[3] == 0.41, "in the rogue's colour")
    local np = f.name.__points[1]
    assert(np[1] == "TOP" and np[2] == f.icon and np[3] == "BOTTOM" and np[5] == -10, "10 px under the icon")
    assert(not f.bg:IsShown() and not f.side:IsShown() and not f.title:IsShown() and not f.text:IsShown(), "no box, strip, title or line")
    assert(f.big:IsShown() and f.big.__size == 15, "the seconds in 15 pt")
    assert(f.__points[1][2] == c.env.CuteAurasAlerts and f.__points[1][1] == "TOP" and f.__points[1][4] == 0 and f.__points[1][5] == 0, "alone: the overlay's top centre")
    local tip, n = lines(c, f)
    assert(n == 3 and tip == "Bramblewoode: Freedom | Then bless with Might again. | Right-click: dismiss.", "its tooltip: " .. tip)
    assert((c.sounds or 0) == sounds, "a Hand's countdown is silent")
    -- (none known: the line says so)
    local ti, li = Hn.HandWords("Bramblewoode", "Blessing of Freedom", nil)
    assert(ti == "Bramblewoode: Freedom" and li == "Nothing to give back after.", li)
    -- (yourself: You)
    hand(c, g.PAL, 1044, 2)
    local me = Al.cards["hand:" .. g.PAL.guid]
    assert(me and me.name.__text == "You", "you: " .. tostring(me and me.name.__text))
    fight(c, false); tick(c, 12)
    noErrors(c)
  end)

  test("alerts: a countdown's seconds are whole and rounded up (10 at 0.5 s, 6 at 4.5 s, 1 at 9.5 s), in Icons and Cards", function()
    for _, look in ipairs({ "icons", "normal" }) do
      WORLD = {}
      local g = party5long()
      local c = g.c3
      c.A.Settings().alertLook = look; c.A.Alerts.Restyle()
      fight(c, true)
      hand(c, g.ROG, 1044, 1)
      local f = c.A.Alerts.cards["hand:" .. g.ROG.guid]
      tick(c, 0.5)
      assert(f.big.__text == "10", look .. " at 0.5 s: " .. f.big.__text)
      tick(c, 4)
      assert(f.big.__text == "6", look .. " at 4.5 s: " .. f.big.__text)
      tick(c, 5)
      assert(f.big.__text == "1", look .. " at 9.5 s: " .. f.big.__text)
      fight(c, false); tick(c, 2)
      noErrors(c, look)
    end
  end)

  test("alerts: at a Hand's end in a fight the restore takes its slot: gold edge and bar, the row glows, a left-click casts nothing, a right-click lets it go, no sound", function()
    local g = party5long()
    local c = g.c3
    local Al, Hn, C = c.A.Alerts, c.A.Hands, c.A.Look.C
    local rog, war = g.ROG.guid, g.WAR.guid
    fight(c, true)
    hand(c, g.ROG, 1044, 1); tick(c, 0.5); hand(c, g.WAR, 10278, 2); tick(c, 0.5)
    assert(Al.order[1] == "hand:" .. rog and Al.order[2] == "hand:" .. war, "oldest left: " .. table.concat(Al.order, ","))
    local cd = Al.cards["hand:" .. rog]
    local x, y = cd.__points[1][4], cd.__points[1][5]
    assert(x < Al.cards["hand:" .. war].__points[1][4] and y == 0, "the rogue's left of the warrior's")
    local sounds = c.sounds or 0
    tick(c, 9.2)
    assert(not Al.Has("hand:" .. rog) and Al.Has("hand:" .. war), "the rogue's Freedom over, the warrior's Protection still counting")
    local r = Al.cards["restore:" .. rog]
    assert(r and Al.order[1] == "restore:" .. rog, "the restore in the countdown's slot: " .. table.concat(Al.order, ","))
    assert(r.__points[1][4] == x and r.__points[1][5] == y, "the same place")
    local e = r.icon.edge
    assert(sameColor(e.__color, C.QUEST) and e.__points[1][4] == -2 and e.__points[1][5] == 2, "a 2 px gold edge")
    assert(r.bar:IsShown() and sameColor(r.bar.__color, C.QUEST), "a gold bar")
    assert(r.name.__text == "Bramblewoode" and not r.icon.icon.__desat, "named, lit")
    assert(Hn.Glowing(rog), "their row glows")
    local tip = lines(c, r)
    assert(tip == "Bramblewoode: Might | Freedom is over. Their row glows in the bar's Might list. | After the fight, a click on it blesses them. | Right-click: dismiss.", "its tooltip: " .. tip)
    c.casts = {}
    c.click(r)
    assert(#c.casts == 0 and Al.Has("restore:" .. rog), "a left-click casts nothing")
    c.click(r, "RightButton")
    assert(not Al.Has("restore:" .. rog) and not Hn.Glowing(rog), "a right-click: the icon and the glow gone")
    tick(c, 1)
    assert(Al.Has("restore:" .. war) and Al.order[1] == "restore:" .. war, "the warrior's in its own slot")
    assert((c.sounds or 0) == sounds, "no sound in a fight")
    assert(Al.cards["restore:" .. war].__points[1][5] == 0, "no click icon: the art row at the top")
    -- the rebuff an icon too: the buff's art, the teal bar, the member's name under it, its words in the tooltip; at the
    -- click row's centre, the art row under it
    local rb = c.env.CuteAurasRebuff
    g.P2.dead = true; tick(c, 1); g.P2.dead = false; tick(c, 1)
    assert(rb:IsShown() and rb.__w == 36 and rb.__h == 36, "the rebuff icon: " .. rb.__w)
    assert(rb.name:IsShown() and rb.name.__text == "Moonwhispers" and rb.bar:IsShown() and sameColor(rb.bar.__color, C.GROUP), "named, a teal bar")
    assert(not rb.title:IsShown() and not rb.text:IsShown() and not rb.bg:IsShown() and sameColor(rb.edge.__color, { 0, 0, 0 }), "no box, a black edge")
    assert(rb.__points[1][2] == c.env.CuteAurasAlerts and rb.__points[1][4] == 0 and rb.__points[1][5] == 0, "the click row's centre")
    tip = lines(c, rb)
    assert(tip == "Moonwhispers is up again | Blessing of Wisdom. Click to buff them. | Click: cast it. Right-click: done with them.", "its tooltip: " .. tip)
    assert(Al.cards["restore:" .. war].__points[1][5] == -64, "the art row under it: " .. Al.cards["restore:" .. war].__points[1][5])
    fight(c, false); tick(c, 2)
    noErrors(c)
  end)

  test("alerts: after the fight the restore is the click icon at the overlay's top centre, one sound; one click, one cast; the next one 0.4 s after, never at once", function()
    local g = party5long()
    local c = g.c3
    local Al, Hn, C, D = c.A.Alerts, c.A.Hands, c.A.Look.C, c.A.Data
    local rog, war = g.ROG.guid, g.WAR.guid
    local card = c.env.CuteAurasRestore
    fight(c, true)
    hand(c, g.ROG, 1044, 1)
    tick(c, 11)
    local sounds = c.sounds or 0
    fight(c, false)
    tick(c, 0.3)
    assert(not card:IsShown() and Al.Has("restore:" .. rog), "art until the look 0.5 s after the fight")
    tick(c, 0.5)
    assert(card:IsShown() and card.guid == rog and not Al.Has("restore:" .. rog), "the click icon, its art gone")
    assert(card.__w == 36 and card.__h == 36, "36 x 36: " .. card.__w .. " x " .. card.__h)
    local pt = card.__points[1]
    assert(pt[1] == "TOP" and pt[2] == c.env.CuteAurasAlerts and pt[3] == "TOP" and pt[4] == 0 and pt[5] == 0, "at the overlay's top centre")
    assert(card:GetAttribute("spell") == D.BLESS.might.ranks[5] and c.units[card:GetAttribute("unit")] == g.ROG, "Might for level 50 on the rogue")
    assert((c.sounds or 0) == sounds + 1, "one sound: " .. ((c.sounds or 0) - sounds))
    assert(card.name.__text == "Bramblewoode" and card.name:IsShown() and sameColor(card.bar.__color, C.QUEST) and card.bar:IsShown(), "its name and gold bar")
    assert(sameColor(card.edge.__color, C.QUEST) and card.edge.__points[1][4] == -2, "its gold edge")
    assert(not card.bg:IsShown() and not card.side:IsShown() and not card.title:IsShown() and not card.text:IsShown(), "no box")
    local tip = lines(c, card)
    assert(tip == "Bramblewoode: Might | Freedom is over: bless with Might again. | Click: bless them. Right-click: dismiss.", "its tooltip: " .. tip)
    tick(c, 3)
    assert((c.sounds or 0) == sounds + 1, "one sound only")
    c.casts = {}
    c.castEvents = true
    c.click(card)
    c.castEvents = nil
    assert(#c.casts == 1 and c.units[c.casts[1].unit] == g.ROG, "one click, one cast")
    assert(not card:IsShown() and not Hn.Glowing(rog), "done: the click icon gone at once")
    -- two waiting: the second desaturated beside the click icon, the click icon takes it 0.4 s after the first is done
    fight(c, true)
    hand(c, g.ROG, 1044, 2); tick(c, 0.5); hand(c, g.WAR, 1044, 3)
    tick(c, 11)
    fight(c, false); tick(c, 1)
    assert(card:IsShown() and card.guid == rog, "the first on the click icon")
    local w = Al.cards["restore:" .. war]
    assert(w and w.icon.icon.__desat and w.spec.row == "click", "the second waits, desaturated")
    local cx, wx = card.__points[1][4], w.__points[1][4]
    assert(w.__points[1][5] == 0 and w.__points[1][2] == c.env.CuteAurasAlerts and wx > cx, "beside it, in the click row")
    local cw = math.ceil(TEXT_WIDTH("Bramblewoode", 10))
    local ww = math.ceil(TEXT_WIDTH("Wardenwallow", 10))
    assert(math.abs((wx - cx) - (cw / 2 + 8 + ww / 2)) < 0.01 and math.abs(cx + wx) < 0.01 + math.abs(cw - ww) / 2, "slots 8 apart, the row centred: " .. cx .. " " .. wx)
    tip = lines(c, w)
    assert(tip == "Wardenwallow: Kings | Next, once the one before it is done. | Right-click: dismiss.", "the waiting one's tooltip: " .. tip)
    -- (a fight between: both art in the art row at the top, the click icon's first, as they stood; back after it)
    fight(c, true)
    assert(not card:IsShown() and table.concat(Al.order, ",") == "restore:" .. rog .. ",restore:" .. war, "in a fight: " .. table.concat(Al.order, ","))
    local a, b = Al.cards["restore:" .. rog], Al.cards["restore:" .. war]
    assert(a.spec.row == nil and b.spec.row == nil and not b.icon.icon.__desat and a.__points[1][5] == 0 and a.__points[1][4] < b.__points[1][4], "the art row, the rogue's left")
    fight(c, false); tick(c, 1)
    assert(card:IsShown() and card.guid == rog and Al.cards["restore:" .. war].spec.row == "click", "back after the fight")
    c.casts = {}
    c.castEvents = true
    c.click(card)
    c.castEvents = nil
    assert(#c.casts == 1 and not card:IsShown(), "the first done: hidden at once")
    assert(c.units[card:GetAttribute("unit")] == g.ROG, "still set to the first: a fast second click never blesses the next")
    Hn.Refresh()
    assert(not card:IsShown(), "another look meanwhile: still hidden")
    tick(c, 0.2)
    assert(not card:IsShown(), "never at once")
    tick(c, 0.3)
    assert(card:IsShown() and card.guid == war and c.units[card:GetAttribute("unit")] == g.WAR and card:GetAttribute("spell") == D.BLESS.kings.ranks[1], "0.4 s after: the warrior's Kings")
    assert(not Al.Has("restore:" .. war), "its art gone")
    noErrors(c)
  end)

  test("alerts: one icon a member: a new Hand takes their waiting restore's slot, the glow off during it; a fight hides the click icon (its guard) and its restore shows as art; the button back only through setSecure", function()
    local g = party5long()
    local c = g.c3
    local Al, Hn, D = c.A.Alerts, c.A.Hands, c.A.Data
    local rog = g.ROG.guid
    local card = c.env.CuteAurasRestore
    -- in a fight: a restore waits as art; a new Freedom on them takes its slot
    fight(c, true)
    hand(c, g.WAR, 10278, 1); tick(c, 0.5)
    hand(c, g.ROG, 1044, 2)
    tick(c, 10.5)
    assert(Al.Has("restore:" .. rog) and Hn.Glowing(rog), "the rogue's restore")
    local at = indexOf(Al.order, "restore:" .. rog)
    hand(c, g.ROG, 1044, 3)
    assert(Al.Has("hand:" .. rog) and not Al.Has("restore:" .. rog), "one icon for the rogue")
    assert(Al.order[at] == "hand:" .. rog, "in the restore's slot: " .. table.concat(Al.order, ","))
    assert(not Hn.Glowing(rog), "no glow during the Hand: a blessing now would take it off")
    tick(c, 10.5)
    assert(Al.Has("restore:" .. rog) and not Al.Has("hand:" .. rog) and Hn.Glowing(rog) and Hn.pending[rog].bless == "might", "the restore back at its end")
    fight(c, false); tick(c, 1)
    Hn.Done(g.WAR.guid); tick(c, 1)
    assert(card:IsShown() and card.guid == rog, "the click icon holds the rogue's restore")
    -- the guard: a secure state handler on [combat] that only hides the click icon
    local guard = c.env.CuteAurasRestoreGuard
    assert(guard and guard.__template == "SecureHandlerStateTemplate" and c.drivers[guard] and c.drivers[guard].fight
      and c.drivers[guard].fight.cond == "[combat] 1; 0" and guard.__attrs["frameref-b"] == card, "the guard and its driver")
    fight(c, true)
    assert(not card:IsShown(), "the fight hid the click icon")
    local r = Al.cards["restore:" .. rog]
    assert(r and r.spec.row == nil and r.__points[1][5] == 0, "its restore as art, in the art row (no click icon above it)")
    assert(lines(c, r):find("After the fight, a click on it blesses them.", 1, true), "in-fight words")
    -- a Freedom on the rogue in the fight: its slot taken, one icon, nothing to click that would cast Might on them
    at = indexOf(Al.order, "restore:" .. rog)
    hand(c, g.ROG, 1044, 4)
    assert(Al.order[at] == "hand:" .. rog and not Al.Has("restore:" .. rog) and not card:IsShown(), "one icon, no click icon")
    tick(c, 10.5)
    assert(Al.Has("restore:" .. rog) and not card:IsShown(), "its end: the restore as art again, the click icon still hidden")
    fight(c, false)
    assert(not card:IsShown(), "the guard never shows it")
    tick(c, 0.3)
    assert(not card:IsShown(), "nor anything before the look after the fight")
    tick(c, 0.5)
    assert(card:IsShown() and card.guid == rog and c.units[card:GetAttribute("unit")] == g.ROG and card:GetAttribute("spell") == D.BLESS.might.ranks[5], "back through setSecure, set to the restore")
    -- a fight with nothing waiting: the guard hides an already hidden button, nothing else
    Hn.Done(rog); tick(c, 1)
    fight(c, true); fight(c, false); tick(c, 1)
    assert(not card:IsShown(), "nothing to show")
    noErrors(c)
  end)

  test("alerts: three Hands ending in one tick: three restores, each in its countdown's slot (the ends run after the walk)", function()
    local g = party5long()
    local c = g.c3
    local Al, Hn = c.A.Alerts, c.A.Hands
    fight(c, true)
    local t0, n0 = c.clock, #c.timers
    hand(c, g.ROG, 1044, 1); hand(c, g.WAR, 1044, 2); hand(c, g.P2, 1044, 3)
    -- (the Hands' own timers a little late, as a frame's OnUpdate may come first in the game: the countdowns end them)
    local late = 0
    for i = n0 + 1, #c.timers do
      local tm = c.timers[i]
      if math.abs(tm.at - (t0 + 10)) < 0.01 then tm.at = tm.at + 0.25; late = late + 1 end
    end
    assert(late == 3, "three Hands' timers: " .. late)
    local before = { Al.order[1], Al.order[2], Al.order[3] }
    assert(#Al.order == 3, "three countdowns")
    tick(c, 10.1)
    assert(#Al.order == 3, "three icons: " .. table.concat(Al.order, ","))
    for i, key in ipairs(before) do
      local want = key:gsub("^hand:", "restore:")
      assert(Al.order[i] == want and Al.Has(want), "slot " .. i .. ": " .. tostring(Al.order[i]) .. " for " .. want)
    end
    for _, m in ipairs({ g.ROG, g.WAR, g.P2 }) do assert(Hn.Glowing(m.guid), m.name .. " glows") end
    tick(c, 1)
    assert(#Al.order == 3, "the late timers changed nothing")
    fight(c, false); tick(c, 2)
    noErrors(c)
  end)

  test("alerts: Show as reads Icons, Small cards, Cards, Big cards; Cards are 258 x 56 as before; a switch in a fight restyles the art at once, the click icon after it; the test icons", function()
    local g = party5long()
    local c = g.c3
    local Al, C = c.A.Alerts, c.A.Look.C
    local rog, war = g.ROG.guid, g.WAR.guid
    local card = c.env.CuteAurasRestore
    c.A.Window.Open("settings")
    local page = c.A.Window.pages.settings
    local ch = widget(page, "Show as")
    assert(ch and widget(page, "Card size") == nil, "Show as in place of Card size")
    local words = {}
    for _, b in ipairs(ch.buttons) do words[#words + 1] = b.text.__text end
    assert(table.concat(words, ",") == "Icons,Small cards,Cards,Big cards", table.concat(words, ","))
    local last = ch.buttons[#ch.buttons]
    assert(last.__points[1][4] + last.__w == 253 and 253 <= ch.__w, "253 wide in its 290 row: " .. (last.__points[1][4] + last.__w))
    assert(ch.buttons[1].bg.__color[1] == C.PINK[1], "Icons lit")
    -- Cards
    c.click(ch.buttons[3])
    assert(c.A.Settings().alertLook == "normal" and not Al.Icons(), "Cards")
    fight(c, true)
    hand(c, g.ROG, 1044, 1)
    local f = Al.cards["hand:" .. rog]
    assert(f.__w == 258 and f.__h == 56, "a card as today: " .. f.__w .. " x " .. f.__h)
    assert(f.bg:IsShown() and f.title:IsShown() and f.text:IsShown() and not f.name:IsShown() and not f.bar:IsShown(), "its words on it")
    tick(c, 11)
    fight(c, false); tick(c, 1)
    assert(card:IsShown() and card.__w == 258 and card.__h == 56 and card.title:IsShown() and not card.name:IsShown(), "the click card as today")
    -- Icons, switched in a fight: the art at once, the click icon after the fight
    fight(c, true)
    hand(c, g.WAR, 1044, 2)
    c.click(ch.buttons[1])
    assert(c.A.Settings().alertLook == "icons", "Icons")
    local w = Al.cards["hand:" .. war]
    assert(w.__w == 36 and w.__h == 36 and w.name:IsShown() and not w.bg:IsShown(), "the art 36 x 36 at once")
    local r = Al.cards["restore:" .. rog]
    assert(r and r.__w == 36, "the in-fight restore too")
    assert(card.__w == 258, "the click icon waits for the fight's end")
    fight(c, false); tick(c, 1)
    assert(card.__w == 36 and card.__h == 36 and card.name:IsShown() and not card.title:IsShown(), "after the fight: the click icon")
    tick(c, 12)
    noErrors(c)
    -- the test icons: hand, restore, rebuff left to right, each named, 217 px across inside the 260 px Move box
    WORLD = {}
    local t = client({ me = member({ name = "Tester", class = "DRUID", level = 30 }) })
    load(t)
    t.A.Alerts.Test()
    local A2 = t.A.Alerts
    assert(table.concat(A2.order, ",") == "test:hand,test:restore,test:rebuff", table.concat(A2.order, ","))
    local left, right
    for _, key in ipairs(A2.order) do
      local x = A2.cards[key]
      assert(x.__w == 36 and x.name.__text == "Bramblewoode", key .. ": named")
      local half = math.ceil(TEXT_WIDTH("Bramblewoode", 10)) / 2
      left = left or (x.__points[1][4] - half)
      right = x.__points[1][4] + half
    end
    assert(math.abs(right - left - 217) < 0.01 and left >= -130 and right <= 130, "217 across, inside the box: " .. (right - left))
    local h, rs, rb = A2.cards["test:hand"], A2.cards["test:restore"], A2.cards["test:rebuff"]
    assert(h.spec.duration == 10 and sameColor(h.bar.__color, C.PINK), "Protection counting from 10")
    assert(sameColor(rs.icon.edge.__color, C.QUEST) and sameColor(rs.bar.__color, C.QUEST), "Kings with the gold edge")
    assert(sameColor(rb.bar.__color, C.GROUP) and sameColor(rb.icon.edge.__color, { 0, 0, 0 }), "Fortitude with the teal bar")
    noErrors(t)
  end)

  test("alerts: Card size becomes Show as: Normal (every save's copied default) loads as Icons, said once in chat; Small and Big keep their cards", function()
    for _, case in ipairs({ { "normal", "icons", 1 }, { "big", "big", 0 }, { "small", "small", 0 }, { false, "icons", 0 } }) do
      WORLD = {}
      local db = { settings = { alertSize = case[1] or nil } }
      local c = client({ me = member({ name = "Migra", class = "PRIEST", level = 40 }), db = db })
      knowAll(c, "PRIEST", 40)
      load(c)
      local s = c.A.Settings()
      assert(s.alertLook == case[2] and s.alertSize == nil and s.alertLookNote == nil, tostring(case[1]) .. ": " .. tostring(s.alertLook))
      local function said(x)
        local n = 0
        for _, line in ipairs(x.chat) do if line:find("Alerts now show as icons. Settings, Show as, brings the cards back.", 1, true) then n = n + 1 end end
        return n
      end
      assert(said(c) == case[3], tostring(case[1]) .. ": the chat line " .. said(c) .. " times")
      tick(c, 2)
      local again = reload(c)
      load(again)
      assert(said(again) == 0 and again.A.Settings().alertLook == case[2] and again.A.Settings().alertSize == nil, "never again after a reload")
      noErrors(c); noErrors(again)
    end
  end)
end

----------------------------------------------------------------------------
-- 0.2.3's diag: six new lines after today's (numbers and words, never a member's name), the spec's examples
----------------------------------------------------------------------------
do
  -- a tank paladin by talents (Protection, 267) in a 5-man, running Cute Auras with a rogue; a paladin running
  -- PallyPower alone and a warrior with no addon. Every name carries a surname in chat
  local function diagParty()
    local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
    local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
    local group = { TA, OR, YS, RA }
    local c = client({ me = OR, group = group, spec = 267 })
    local c2 = client({ me = TA, group = group, spec = 253 })
    knowAll(c, "PALADIN", 60); knowAll(c2, "ROGUE", 60)
    -- (the spec's example screen: 768 tall)
    c.env.UIParent.__h = 768
    -- six counted items carried: three that fit a tank (two of one kin), one for casters, a flask habit, a potion chosen
    -- for 5-mans whose cooldown runs (a healing potion drunk 30 s ago)
    for i, x in ipairs({ CN.mongoose, CN.gagi, CN.giants, CN.garcane, CN.titans, CN.stone }) do
      c.items[x[1]] = { name = x[2], classID = x[3], subID = x[4], spell = x[5] }
      c.bags[#c.bags + 1] = { id = x[1], bag = 0, slot = i, count = 5 }
    end
    c.bags[6].cdStart, c.bags[6].cd = c.clock - 30, 120
    load(c); load(c2)
    -- two habits: the flask carried, a juju not
    local h = c.A.Consume.Habits()
    h[13510] = { hits = 2, miss = 0, at = 500, spell = 17626 }
    h[12460] = { hits = 3, miss = 0, at = 400, spell = 16329 }
    c.A.Consume.SetChoice(13455, "dungeon", true)
    -- (Elixir of Giants and the flask on you: asked are the potion, waiting on its cooldown, and one of the agility kin)
    OR.auras[#OR.auras + 1] = { id = 11405, src = "player", exp = c.clock + 3600, dur = 3600 }
    OR.auras[#OR.auras + 1] = { id = 17626, src = "player", exp = c.clock + 7200, dur = 7200 }
    c.instance, c2.instance = "party", "party"
    fire(c, "ZONE_CHANGED_NEW_AREA"); fire(c2, "ZONE_CHANGED_NEW_AREA")
    tickAll(12)
    return { c = c, c2 = c2, TA = TA, OR = OR, YS = YS, RA = RA, group = group }
  end

  test("/cauras diag: Consumables, PallyPower, Names, Target's blessings, Bar and Alerts after today's lines, in that order; the role's source and habits; no member's name or part of one", function()
    local g = diagParty()
    local c = g.c
    -- PallyPower heard: Ysolde's SELF
    ppSay(g.YS, YS_SELF)
    tickAll(3)
    -- your target the warrior, your Might and Ysolde's Kings on them
    g.RA.auras[#g.RA.auras + 1] = { id = D.BLESS.might.ranks[#D.BLESS.might.ranks], src = "player", exp = c.clock + 3000, dur = 3600 }
    g.RA.auras[#g.RA.auras + 1] = { id = D.BLESS.kings.ranks[1], src = "party2", exp = c.clock + 3000, dur = 3600 }
    c.units.target = g.RA
    -- two Hands out of a fight, both over: one restore on the click icon, the other waiting beside it
    hand(c, g.TA, 10278, 1); hand(c, g.RA, 10278, 2)
    tick(c, 11)
    c.chat = {}
    c.env.SlashCmdList.CUTEAURAS("diag")
    local lines = {}
    for _, l in ipairs(c.chat) do lines[#lines + 1] = (l:gsub("^|cffff9ad5Cute Auras|r ", "")) end
    -- today's lines first, the six new ones last, in the spec's order
    local at
    for i, l in ipairs(lines) do if l:find("^After ") then at = i end end
    assert(at and lines[at - 1]:find("^Comm sent "), "today's lines end with the fight's: " .. table.concat(lines, " / "))
    assert(#lines == at + 6, "six new lines after today's: " .. (#lines - at))
    local cons, pp, names, tgt, bar, al = lines[at + 1], lines[at + 2], lines[at + 3], lines[at + 4], lines[at + 5], lines[at + 6]
    -- (where you stand, the role and where it came from, habits; the spec's example)
    assert(cons == "Consumables on, habits inst; here 5-man; role tank (talents, spec 267); carried 6, fit 3, chosen 1, habits 2, quiet 0, cooling 1; asked 2; never 0, pull-only 0", cons)
    -- (the rogue's client, the lowest GUID, is the asker: its REQ for Ysolde, silent 10 s; Ysolde's SELF heard; it took
    -- cells from Orren's column, so Orren's row changed and one batch of ours went: sent counts a batch as one)
    assert(pp == "PallyPower: here no; asker no; heard 2 (SELF 1, set 0, clear 0, REQ 1, whispered 0, relayed 0, other 0); taken 0, refused 0, names unsure 0, bad 0, secret 0; paladins on it 1; sent 1 (SELF 1, REQ 0); O1 refused for name 0", pp)
    local pp2 = g.c2.A.PallySync.DiagLine()
    assert(pp2:find("; asker yes;", 1, true) and pp2:find("; sent 1 (SELF 0, REQ 1);", 1, true), "the asker's line: " .. pp2)
    assert(names == "Names: sender two words and realm; UnitName one word, surname yes", names)
    assert(tgt == "Target's blessings: might yours, kings theirs; hidden no", tgt)
    -- (the bar as laid out: its icons, its width, its widest verb at the client's width, the names cut to fit)
    local own, grp = barIcons(c)
    local n, cut, widest = 0, 0, 0
    for _, b in ipairs(own) do n = n + 1; widest = math.max(widest, TEXT_WIDTH(b.rec.word, 11)) end
    for _, b in ipairs(grp) do
      n = n + 1
      if b.word.__text ~= b.rec.word then cut = cut + 1 end
      if not (b.rec.class and b.rec.status == nil) then widest = math.max(widest, TEXT_WIDTH(b.rec.word, 11)) end
    end
    assert(cut >= 1, "a name cut on the bar, so the line is tested against one")
    assert(bar == string.format("Bar: %d icons, %d wide; widest word %d of 32; names cut %d", n, c.env.CuteAurasBar.__w, math.ceil(widest), cut), bar)
    assert(al == "Alerts icons, scale 100%, shown 2, click icons 1, restores waiting 1, rebuff slots 3; overlay 94 over the centre (UI 768 tall)", al)
    -- no member's name, surname or a cut of one (three letters or more) in any of them
    for _, l in ipairs({ cons, pp, names, tgt, bar, al }) do
      for _, m in ipairs(g.group) do
        for _, word in ipairs({ m.name, m.surname }) do
          for k = 3, #word do assert(not l:find(word:sub(1, k), 1, true), "a name in the diag: " .. word:sub(1, k) .. " in " .. l) end
        end
      end
    end
    -- the target's line: none on them; no target; a hidden aura; two of one kind
    g.RA.auras = {}
    fire(c, "UNIT_AURA", "target")
    assert(c.A.Buffs.TargetBlessLine() == "Target's blessings: none; hidden no", c.A.Buffs.TargetBlessLine())
    g.RA.auras = { { id = D.BLESS.might.group[#D.BLESS.might.group], src = "player", exp = c.clock + 3000, dur = 3600 },
                   { id = D.BLESS.might.ranks[1], src = "party2", exp = c.clock + 3000, dur = 3600 },
                   { id = 1243, secretId = true, src = "party1" },
                   { id = D.BLESS.kings.group[1], secretId = true, src = "party1" } }
    -- (two paladins' Might on one target, both shown; a Greater Kings whose id is secret known by its name)
    assert(c.A.Buffs.TargetBlessLine() == "Target's blessings: greater might yours, might theirs, greater kings theirs; hidden yes", c.A.Buffs.TargetBlessLine())
    c.units.target = nil
    assert(c.A.Buffs.TargetBlessLine() == "Target's blessings: no target", c.A.Buffs.TargetBlessLine())
    -- in a fight the client hides every aura: nothing read, hidden yes
    c.units.target = g.RA
    fight(c, true)
    assert(c.A.Buffs.TargetBlessLine() == "Target's blessings: none; hidden yes", c.A.Buffs.TargetBlessLine())
    fight(c, false)
    -- (the first line names the version)
    -- (the rebuff's count says what it counts: alerts are icons now, not cards)
    assert(lines[1]:find("^0%.2%.3, group true, members 4, running Cute Auras 2, duties %d+, rebuff slots 3, rebuffs shown %d+$"), lines[1])
    noErrors(c); noErrors(g.c2)
  end)

  test("the window's four tabs named alike everywhere: the minimap's menu lists them in order and each opens its page; its tooltip and the game's Settings page name them", function()
    local c = client({ me = member({ name = "Tabby", class = "PRIEST", level = 60 }) })
    local canvas
    c.env.Settings.RegisterCanvasLayoutCategory = function(f) canvas = f; return { ID = 1 } end
    load(c)
    c.A.Window.Open("settings")
    -- the window's tabs, left to right
    local tabs = {}
    for _, f in ipairs(c.frames) do
      if f.__kind == "Button" and f.__parent == c.env.CuteAurasWindow and f.__w == 104 and f.text then tabs[#tabs + 1] = f end
    end
    table.sort(tabs, function(a, b) return a.__points[1][4] < b.__points[1][4] end)
    local words = {}
    for i, t in ipairs(tabs) do words[i] = t.text.__text end
    assert(table.concat(words, ", ") == "Settings, Consumables, Blessings, Biome gear", "the tabs: " .. table.concat(words, ", "))
    -- the minimap's right-click: the same tabs in the same order, each opening its page
    local mb = c.env.CuteAurasMinimapButton
    mb.__scripts.OnClick(mb, "RightButton")
    local m = c.menus[#c.menus]
    local entries = {}
    for _, e in ipairs(m) do if e.kind == "button" then entries[#entries + 1] = e end end
    local names = {}
    for i = 1, #words do names[i] = entries[i] and entries[i].text end
    assert(table.concat(names, ", ") == table.concat(words, ", "), "the minimap's menu: " .. table.concat(names, ", "))
    for i, key in ipairs({ "settings", "consume", "blessings", "gear" }) do
      entries[i].fn()
      assert(c.A.Window.pages[key]:IsShown(), words[i] .. " opens its page")
    end
    -- its tooltip and the game's Settings page name every tab
    c.hover(mb)
    local tip = c.env.GameTooltip.lines[2]
    assert(tip == "Click: settings, consumables, blessings and biome gear. Right-click: menu. Drag: move.", tostring(tip))
    local note = canvas and canvas.note and canvas.note.__text
    assert(note == "Its settings, consumables, blessings and biome gear live in its own window (/cauras).", tostring(note))
    for _, w in ipairs(words) do
      assert(tip:find(w:lower(), 1, true) and note:find(w:lower(), 1, true), "named: " .. w)
    end
    noErrors(c)
  end)

  test("the version: 0.2.3 in Core.lua and the toc; the toc loads the spec's files in the spec's order", function()
    local c = client({ me = member({ name = "Verso", class = "MAGE", level = 60 }) })
    load(c)
    assert(c.A.version == "0.2.3", c.A.version)
    local toc = assert(io.open(DIR .. "CuteAuras.toc")):read("*a")
    assert(toc:match("\n## Version: ([^\n]+)\n") == "0.2.3", "the toc's Version: " .. tostring(toc:match("\n## Version: ([^\n]+)\n")))
    local files = {}
    for f in toc:gmatch("\n([%w_]+)%.lua") do files[#files + 1] = f end
    assert(table.concat(files, ", ") == "Core, Data, Look, Spells, Roster, Comm, PallySync, Assign, Bar, Camp, Buffs, Consume, Gear, Alerts, Rebuff, Hands, Window, Minimap",
      table.concat(files, ", "))
    noErrors(c)
  end)
end

----------------------------------------------------------------------------
-- 0.2.3, the review's first round: PallyPower's REQ while its paladins fight, a late joiner, the asker; our SELF taken
-- back; a NASSIGN removal; a long relay; the Hand restore while you are dead and after a blessing ran out; consumables
-- before the pull (doubled, an elixir already up, a kind's default, the menu), groups of one aura, the weapon's oil, a
-- cooldown's click, the tab's clock, a 0.2.2 habit with no stat words; the site's picture
----------------------------------------------------------------------------
do
  local function nREQ(c) return #ppOut(c, "REQ") end
  local function allCombat(list, on) for _, m in ipairs(list) do m.combat = on end end

  test("review: the asker's REQ waits while a paladin who may run PallyPower still fights, after the asker's own fight and at the first look", function()
    -- the asker (Tamsin) leaves her fight first; Ysolde, listed, fights on: her answer would be lost
    local g = ppParty()
    local c2 = g.c2
    ppSay(g.YS, YS_SELF, g.TA)
    tickAll(3)
    assert(c2.A.PallySync.pals[g.YS.guid], "Ysolde listed through the relay")
    tickAll(40)
    local r = nREQ(c2)
    fight(c2, true); tick(c2, 2)
    g.YS.combat = true
    fight(c2, false)
    tickAll(6)
    assert(nREQ(c2) == r, "Ysolde still in her fight: no REQ yet (" .. (nREQ(c2) - r) .. ")")
    g.YS.combat = false
    tickAll(4)
    assert(nREQ(c2) == r + 1, "Ysolde out of it: the after-fight REQ (" .. (nREQ(c2) - r) .. ")")
    for _, x in ipairs(g.all) do noErrors(x, "after a fight") end
    -- the first look: Ysolde fights while the asker has none of its own
    WORLD = {}
    g = ppParty({ wait = 1 })
    c2 = g.c2
    g.YS.combat = true
    tickAll(16)
    assert(nREQ(c2) == 0, "Ysolde fighting: the first REQ waits (" .. nREQ(c2) .. ")")
    g.YS.combat = false
    tickAll(5)
    assert(nREQ(c2) == 1, "out of it: one REQ (" .. nREQ(c2) .. ")")
    for _, x in ipairs(g.all) do noErrors(x, "the first look") end
  end)

  test("review: a paladin asked once whose answer never came is asked again after a fight, three REQs at most", function()
    local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
    local c = client({ me = TA, group = { TA, YS, RA }, spec = 253 })
    knowAll(c, "ROGUE", 60)
    load(c)
    tick(c, 12)
    assert(nREQ(c) == 1, "Ysolde silent 10 s: asked (" .. nREQ(c) .. ")")
    local function fightOnce() fight(c, true); tick(c, 2); fight(c, false); tick(c, 4) end
    tick(c, 30)
    fightOnce()
    assert(nREQ(c) == 2, "no answer: asked again after the fight (" .. nREQ(c) .. ")")
    tick(c, 300)
    fightOnce()
    assert(nREQ(c) == 3, "and again after the next, five minutes on (" .. nREQ(c) .. ")")
    tick(c, 300)
    fightOnce()
    assert(nREQ(c) == 3, "three at most: a paladin without PallyPower is let be (" .. nREQ(c) .. ")")
    noErrors(c)
  end)

  test("review: a Cute Auras paladin who joins after a PallyPower paladin's SELF: the asker asks again once its hello has reached them; both agree", function()
    local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
    local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E", leader = true })
    local group = { TA, YS, RA }
    local c2 = client({ me = TA, group = group, spec = 253 })
    knowAll(c2, "ROGUE", 60)
    load(c2)
    tickAll(12)
    ppSay(YS, YS_SELF, TA)
    tickAll(3)
    assert(c2.A.PallySync.pals[YS.guid], "the asker lists Ysolde")
    tickAll(40)
    -- Orren (Cute Auras alone) joins
    group[#group + 1] = OR
    local c1 = client({ me = OR, group = group, spec = 184 })
    knowAll(c1, "PALADIN", 60)
    load(c1)
    for _, c in ipairs({ c1, c2 }) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
    local r = nREQ(c2)
    tickAll(10)
    assert(nREQ(c2) == r + 1, "the asker asks again for the newcomer (" .. (nREQ(c2) - r) .. ")")
    assert(c1.A.PallySync.Asker() == TA.guid, "Orren knows Tamsin asks")
    assert(nREQ(c1) == 0, "Orren is not the asker")
    -- Ysolde's PallyPower answers the asker by whisper: relayed, Orren lists them
    ppSay(YS, YS_SELF, TA)
    tickAll(8)
    assert(c1.A.PallySync.pals[YS.guid] and c1.A.PallySync.heardAny, "Orren lists Ysolde")
    for _, key in ipairs({ "ROGUE:melee", "WARRIOR:melee" }) do
      local a, b = c1.A.Assign.BlessingOf(OR.guid, key), c2.A.Assign.BlessingOf(OR.guid, key)
      assert(a == b, key .. ": Orren's cell the same on both clients: " .. tostring(a) .. " / " .. tostring(b))
    end
    assert(#c1.A.Assign.paladins == 2 and #c2.A.Assign.paladins == 2, "two paladins on both")
    assert(#ppOut(c1, "SELF") >= 1, "Orren now speaks to PallyPower")
    tickAll(40)
    assert(nREQ(c2) == r + 1, "one REQ for one join")
    noErrors(c1, "joiner"); noErrors(c2, "asker")
  end)

  test("review: the asker runs Cute Auras without PallyPower and is online: never a client running PallyPower, never one gone offline", function()
    -- the lowest GUID runs PallyPower too: the next one asks
    local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-00", assigned = "TANK", leader = true })
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
    local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
    local group = { BR, OR, YS }
    local c1 = client({ me = OR, group = group, spec = 184 })
    local c3 = client({ me = BR, group = group, spec = 257, addons = PP_ADDON })
    knowAll(c1, "PALADIN", 60); knowAll(c3, "WARRIOR", 60)
    load(c1); load(c3)
    tickAll(14)
    assert(c1.A.PallySync.Asker() == OR.guid and c3.A.PallySync.Asker() == OR.guid, "Orren asks, on both clients")
    assert(nREQ(c1) == 1 and nREQ(c3) == 0, "Orren's REQ for the silent Ysolde: " .. nREQ(c1) .. ", " .. nREQ(c3))
    -- a whisper to Brok's client is not relayed; one to the asker is, and Brok's client takes it
    ppSay(YS, YS_SELF, OR)
    tickAll(3)
    assert(c3.A.PallySync.pals[YS.guid], "relayed by Orren")
    noErrors(c1, "pp asker"); noErrors(c3, "pp asker")
    -- the asker gone offline (still in the group): the next one asks
    WORLD = {}
    local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
    YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
    group = { TA, OR, RA }
    c1 = client({ me = OR, group = group, spec = 184 })
    local c2 = client({ me = TA, group = group, spec = 253 })
    knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60)
    load(c1); load(c2)
    tickAll(12)
    assert(c1.A.PallySync.Asker() == TA.guid, "Tamsin asks")
    TA.online = false
    for i, x in ipairs(WORLD) do if x == c2 then table.remove(WORLD, i) break end end
    group[#group + 1] = YS
    seat(c1); fire(c1, "GROUP_ROSTER_UPDATE")
    tickAll(14)
    assert(c1.A.PallySync.Asker() == OR.guid, "Tamsin offline: Orren asks")
    assert(nREQ(c1) == 1, "Orren's REQ for the silent Ysolde (" .. nREQ(c1) .. ")")
    noErrors(c1, "offline asker")
  end)

  test("review: a paladin who stops giving blessings takes its SELF back (no ranks, an empty row, 27 bytes) and answers REQs with it", function()
    local g = ppParty()
    local c1 = g.c1
    local EMPTY = "SELF nnnnnnnnnnnn@nnnnnnnnn"
    ppSay(g.YS, "REQ")
    tickAll(4)
    local selfs = ppOut(c1, "SELF")
    assert(#selfs == 1 and selfs[1].msg ~= EMPTY, "our SELF first")
    tickAll(20)
    -- Blessings shared out by Cute Auras off
    local n = #ppOut(c1)
    c1.A.Settings().blessings = false
    c1.A.Comm.GivesChanged()
    tickAll(25)
    local out = ppOut(c1)
    assert(#out == n + 3, "one batch: " .. (#out - n))
    assert(out[n + 1].msg == EMPTY and #out[n + 1].msg == 27, "an empty SELF: " .. out[n + 1].msg)
    assert(out[n + 2].msg == "ASELF nnnnnnnnnnnnnn@0" and out[n + 3].msg:find("^FREEASSIGN NO | SYMCOUNT %d+ | COOLDOWNS:n:n:n:n$"), "then ASELF and FREEASSIGN")
    local ranks, row = ppReadSelf(out[n + 1].msg)
    assert(next(ranks) == nil, "no ranks as PallyPower reads them")
    for i = 1, 9 do assert(row[i] == 0, "an empty row") end
    -- a REQ while silent: answered with the empty SELF
    tickAll(20)
    ppSay(g.YS, "REQ")
    tickAll(4)
    selfs = ppOut(c1, "SELF")
    assert(selfs[#selfs].msg == EMPTY, "answered empty: " .. selfs[#selfs].msg)
    local nSelf = #selfs
    assert(nSelf == 3, "three SELFs: ours, the empty one, the answer: " .. nSelf)
    -- blessings back on: our SELF again
    tickAll(20)
    c1.A.Settings().blessings = true
    c1.A.Comm.GivesChanged()
    tickAll(25)
    selfs = ppOut(c1, "SELF")
    assert(#selfs == nSelf + 1 and selfs[#selfs].msg ~= EMPTY and selfs[#selfs].msg:sub(1, 18) == "SELF 607010nnnnnn@", "our SELF back: " .. selfs[#selfs].msg)
    -- a paladin who never spoke in this group stays quiet
    WORLD = {}
    g = ppParty()
    g.c1.A.Settings().blessings = false
    g.c1.A.Comm.GivesChanged()
    ppSay(g.YS, "REQ")
    tickAll(25)
    assert(#ppOut(g.c1) == 0, "never spoke here: nothing to take back")
    for _, x in ipairs(g.all) do noErrors(x, "silent") end
  end)

  test("review: a leader's NASSIGN removal for your column clears the bucket it set, though another member joined that bucket since", function()
    local g = ppParty()
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 2")
    tickAll(3)
    for _, c in ipairs(g.all) do
      local ov = ovOf(c, g.OR.guid, "WARRIOR:tank")
      assert(ov and ov.key == "might" and ov.pp, "Brok alone in the tank bucket: Might, pp")
    end
    -- Rask marked a tank too: two in that bucket
    g.RA.assigned = "TANK"
    for _, c in ipairs(g.all) do fire(c, "PLAYER_ROLES_ASSIGNED") end
    tickAll(3)
    assert(#g.c1.A.Assign.buckets["WARRIOR:tank"] == 2, "two tanks")
    local taken = g.c1.A.PallySync.stats.taken or 0
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 0")
    tickAll(3)
    for _, c in ipairs(g.all) do
      local ov = ovOf(c, g.OR.guid, "WARRIOR:tank")
      assert(ov and ov.clear and ov.key == nil, "the removal taken: back to Cute Auras' choice")
      assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings", "Cute Auras' choice for the tanks: " .. tostring(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank")))
    end
    assert(g.c1.A.PallySync.stats.taken == taken + 1, "taken once")
    -- a NASSIGN for a member who is not alone in their bucket sets nothing, and counts nothing
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
    tickAll(3)
    assert((ovOf(g.c1, g.OR.guid, "WARRIOR:tank") or {}).key == nil and g.c1.A.PallySync.stats.taken == taken + 1, "not alone: nothing taken")
    for _, x in ipairs(g.all) do noErrors(x, "NASSIGN removal") end
  end)

  test("review: a whispered NASSIGN too long to relay whole goes on in parts, whole entries each; every entry reaches every client", function()
    local QU = member({ name = "Quillane", surname = "Thornberrywick", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    local BA = member({ name = "Bartholomew", surname = "Stormhammerson", class = "PALADIN", level = 60, guid = "Player-1-0C" })
    local CH = member({ name = "Christophera", surname = "Windwhisperer", class = "MAGE", level = 60, guid = "Player-1-0D" })
    local EV = member({ name = "Evangelinea", surname = "Brightmantle", class = "PRIEST", level = 60, guid = "Player-1-0E" })
    local MX = member({ name = "Maximiliann", surname = "Goldenbranch", class = "WARRIOR", level = 60, guid = "Player-1-0F" })
    local c = client({ me = QU, group = { QU, BA, CH, EV, MX }, spec = 253 })
    knowAll(c, "ROGUE", 60)
    load(c)
    tick(c, 12)
    ppSay(BA, "SELF 607010nnnnnn@221333113", QU)
    tick(c, 3)
    assert(c.A.PallySync.pals[BA.guid], "listed")
    local text = "NASSIGN Bartholomew_Stormhammerson 2 Quillane_Thornberrywick 3@Bartholomew_Stormhammerson 7 Christophera_Windwhisperer 3"
      .. "@Bartholomew_Stormhammerson 3 Evangelinea_Brightmantle 3@Bartholomew_Stormhammerson 1 Maximiliann_Goldenbranch 3"
    assert(#text <= 255 and #("P1|" .. SENDER(BA) .. "|" .. text) > 255, "fits PallyPower's whisper, not one relay: " .. #text)
    local p1 = #c.said
    ppSay(BA, text, QU)
    tick(c, 4)
    local parts = 0
    for i = p1 + 1, #c.said do
      if c.said[i]:find("^P1|") then parts = parts + 1; assert(#c.said[i] <= 255, "each part fits: " .. #c.said[i]) end
    end
    assert(parts == 2, "two parts: " .. parts)
    for _, m in ipairs({ QU, CH, EV, MX }) do
      assert(c.A.PallySync.MemberCell(BA.guid, m.guid) == "kings", m.name .. "'s cell relayed")
    end
    noErrors(c)
  end)

  test("review: your death while the group fights holds the Hand's click icon and its sound; the group's end shows it, silent while you are dead; a Hand ending then is art", function()
    local g = party5long()
    local c = g.c3
    local Al = c.A.Alerts
    local rog = g.ROG.guid
    local card = c.env.CuteAurasRestore
    local others = { g.P1, g.P2, g.ROG, g.WAR }
    fight(c, true)
    hand(c, g.ROG, 1044, 1)
    tick(c, 11)
    assert(Al.Has("restore:" .. rog) and not card:IsShown(), "in the fight: the restore as art")
    local sounds = c.sounds or 0
    -- you die; the group fights on: your fight ends
    g.PAL.dead = true
    allCombat(others, true)
    fight(c, false)
    tick(c, 3)
    assert(not card:IsShown() and Al.Has("restore:" .. rog), "dead, the group fighting: the art stays, no click icon")
    assert((c.sounds or 0) == sounds, "no sound while the group fights")
    -- the group's fight over, you still dead: the click icon, silent
    allCombat(others, false)
    tick(c, 3)
    assert(card:IsShown() and card.guid == rog and not Al.Has("restore:" .. rog), "the group's fight over: the click icon")
    assert((c.sounds or 0) == sounds, "dead: no sound yet")
    -- back up: its one sound
    g.PAL.dead = false
    fire(c, "PLAYER_ALIVE"); tick(c, 1)
    assert(card:IsShown() and (c.sounds or 0) == sounds + 1, "alive: one sound (" .. ((c.sounds or 0) - sounds) .. ")")
    tick(c, 3)
    assert((c.sounds or 0) == sounds + 1, "one only")
    noErrors(c, "death")
    -- a Hand that ends while you lie dead and the group fights: its restore is art, no click icon, no sound
    WORLD = {}
    g = party5long()
    c = g.c3
    Al, rog, card = c.A.Alerts, g.ROG.guid, c.env.CuteAurasRestore
    others = { g.P1, g.P2, g.ROG, g.WAR }
    fight(c, true)
    hand(c, g.ROG, 1044, 1)
    tick(c, 2)
    sounds = c.sounds or 0
    g.PAL.dead = true
    allCombat(others, true)
    fight(c, false)
    tick(c, 10)
    assert(Al.Has("restore:" .. rog) and not card:IsShown(), "the Hand over while you are dead: its restore as art")
    assert((c.sounds or 0) == sounds, "no sound")
    allCombat(others, false)
    g.PAL.dead = false
    fire(c, "PLAYER_ALIVE"); tick(c, 3)
    assert(card:IsShown() and card.guid == rog and (c.sounds or 0) == sounds + 1, "back, the fight over: the click icon and its sound")
    noErrors(c, "a Hand ending while dead")
  end)

  test("review: the Hand restore never names a blessing of yours that ran out or that a death took off; the share-out then", function()
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-J1" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-J2" })
    local DU = member({ name = "Dunstan", surname = "Vale", class = "WARRIOR", level = 60, guid = "Player-1-J3" })
    local KE = member({ name = "Kestra", surname = "Moor", class = "WARRIOR", level = 60, guid = "Player-1-J4" })
    local c = client({ me = OR, group = { OR, RA, DU, KE }, spec = 184 })
    knowAll(c, "PALADIN", 60)
    load(c)
    tick(c, 12)
    local Hn, As = c.A.Hands, c.A.Assign
    assert(As.BlessingOf(OR.guid, "WARRIOR:melee") == "might", "the share-out: Might for warriors")
    local function freedom(m, n)
      fire(c, "UNIT_SPELLCAST_SENT", "player", m.name, "cast-rf" .. n, 1044)
      fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-rf" .. n, 1044)
    end
    -- your Kings on Rask, put on an hour less 100 s ago: read; then it runs out
    RA.auras = { { id = 20217, src = "player", exp = c.clock + 100, dur = 3600 } }
    fire(c, "UNIT_AURA", tokenOf(c, RA))
    tick(c, 4)
    assert(Hn.saw[RA.guid] and Hn.saw[RA.guid].key == "kings", "read: Kings")
    tick(c, 110)
    freedom(RA, 1)
    tick(c, 12)
    assert(Hn.pending[RA.guid] and Hn.pending[RA.guid].bless == "might", "Kings ran out: the share-out's Might, not " .. tostring(Hn.pending[RA.guid] and Hn.pending[RA.guid].bless))
    Hn.Done(RA.guid)
    -- your Kings read on Dunstan, your Kings cast on Kestra; in a fight both die and are raised; a Freedom on each
    DU.auras = { { id = 20217, src = "player", exp = c.clock + 3600, dur = 3600 } }
    fire(c, "UNIT_AURA", tokenOf(c, DU))
    tick(c, 4)
    assert(Hn.saw[DU.guid] and Hn.saw[DU.guid].key == "kings", "read: Kings on Dunstan")
    fire(c, "UNIT_SPELLCAST_SENT", "player", "Kestra", "cast-rk1", 20217)
    fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-rk1", 20217)
    tick(c, 1)
    fight(c, true)
    for _, m in ipairs({ DU, KE }) do
      m.dead = true; fire(c, "UNIT_HEALTH", tokenOf(c, m)); tick(c, 1)
      m.dead = false; m.auras = {}; fire(c, "UNIT_HEALTH", tokenOf(c, m)); tick(c, 1)
    end
    freedom(DU, 2); freedom(KE, 3)
    tick(c, 12)
    assert(Hn.pending[DU.guid] and Hn.pending[DU.guid].bless == "might", "Dunstan died: the share-out's Might")
    assert(Hn.pending[KE.guid] and Hn.pending[KE.guid].bless == "might", "Kestra died: your cast is gone too")
    fight(c, false); tick(c, 2)
    noErrors(c, "stale restore")
  end)

  test("review: Before the pull and your part never ask one item twice; the pull's start and end read your part again", function()
    local c = consumer({ class = "WARRIOR", role = "melee", food = true, items = { CN.titans, CN.mongoose } })
    c.instance = "raid"
    fire(c, "PLAYER_ENTERING_WORLD"); tick(c, 2)
    local mine = consumeKeys(c)
    assert(mine:find("consume13510") and mine:find("consume13452") and mine:find("food"), "entering a raid, yours first: " .. mine)
    tick(c, 5)
    assert(consumeKeys(c) == "", "Before the pull on: nothing of these in yours: " .. consumeKeys(c))
    assert(pullKeys(c) == "pullfood flask13510 flask13452", "the pull: " .. pullKeys(c))
    -- an aura of yours changing meanwhile, then the pull's end: yours again
    fire(c, "UNIT_AURA", "player"); tick(c, 1)
    c.A.Bar.PullEnd(); tick(c, 1)
    mine = consumeKeys(c)
    assert(mine:find("consume13510") and mine:find("consume13452") and mine:find("food") and pullKeys(c) == "", "the pull over: yours again: " .. mine)
    noErrors(c)
  end)

  test("review: Before the pull never asks for a flask or elixir whose own buff is up for 3 minutes or more; its group neither", function()
    local c, me = consumer({ class = "WARRIOR", role = "melee", items = { CN.titans, CN.mongoose, CN.giants, CN.gagi } })
    goTo(c, "raid")
    auraOn(c, me, 17538, 3300)
    auraOn(c, me, 17626, 7000)
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(pullKeys(c) == "flask9206", "the Titans and the Mongoose up, Greater Agility its kin: only Giants: " .. pullKeys(c))
    c.A.Bar.PullEnd(); tick(c, 1)
    -- under 3 minutes left: its countdown
    auraOn(c, me, 17538, 100)
    fire(c, "READY_CHECK"); tick(c, 4)
    local rec = find(shown(c, "pull"), "flask9187") or find(shown(c, "pull"), "flask13452")
    assert(rec and rec.status == "warn" and rec.word:find("^1:"), "the Mongoose ending: its group's countdown: " .. pullKeys(c))
    noErrors(c)
  end)

  test("review: Before the pull also asks what a kind's default asks here (Other in raids: Spirit of Zanza, Juju Might)", function()
    local c = consumer({ class = "ROGUE", role = "melee", food = true, items = { CN.zanza, CN.juju, CN.mongoose } })
    goTo(c, "raid")
    local mine = consumeKeys(c)
    assert(mine:find("consume20079") and mine:find("consume12460"), "asked in the raid: " .. mine)
    fire(c, "READY_CHECK"); tick(c, 4)
    local keys = pullKeys(c)
    assert(keys == "pullfood flask13452 flask12460 flask20079", "the ready check asks them too: " .. keys)
    c.A.Bar.PullEnd(); tick(c, 1)
    -- not in a 5-man (Other is off there by default)
    goTo(c, "party")
    fire(c, "READY_CHECK"); tick(c, 4)
    keys = pullKeys(c)
    assert(not keys:find("flask20079") and not keys:find("flask12460"), "a 5-man: " .. keys)
    noErrors(c)
  end)

  test("review: a Before the pull icon's right-click shows where the pull asks for it, and one click stops it here", function()
    local c = consumer({ class = "WARRIOR", role = "tank", items = { CN.titans } })
    goTo(c, "party")
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(find(shown(c, "pull"), "flask13510"), "a tank's Titans before the pull: " .. pullKeys(c))
    c.A.Bar.Menu(icon(c, "own", "flask13510"))
    local m = c.menus[#c.menus]
    local box = {}
    for _, e in ipairs(m) do if e.kind == "check" then box[e.text] = e end end
    assert(box["5-man"] and box["5-man"].get() == true, "5-man checked: the pull asks it here")
    box["5-man"].fn(); tick(c, 1)
    assert(c.A.Consume.Settings().items[13510].dungeon == false, "one click: not in 5-man dungeons")
    assert(not find(shown(c, "pull"), "flask13510") and box["5-man"].get() == false, "gone, and the box says so: " .. pullKeys(c))
    noErrors(c)
  end)

  test("review: one aura matched by name to two items is no stack: two ranks of a scroll, the two Natural flasks", function()
    SPELL_NAMES[8117], SPELL_NAMES[12174] = "Agility", "Agility"
    SPELL_NAMES[1293740], SPELL_NAMES[1293743] = "Flask of Natural Accuracy", "Flask of Natural Accuracy"
    local c, me = consumer({ class = "ROGUE", role = "melee", items = { { 4425, "Scroll of Agility III", 0, 4, 8117 }, { 10309, "Scroll of Agility IV", 0, 4, 12174 },
      { 274273, "Flask of Natural Accuracy", 0, 3, 1293740 }, { 274276, "Flask of Natural Swiftness", 0, 3, 1293743 } } })
    goTo(c, "raid")
    auraOn(c, me, 12174)
    auraOn(c, me, 1293743)
    local ks = c.A.Acct().kinStacks or {}
    assert(not ks["scroll:agi"], "one Agility on you is one aura")
    assert(c.A.Acct().flasksStack ~= true, "one flask on you is one flask")
    auraOff(c, me, 12174); auraOff(c, me, 1293743)
    local keys = consumeKeys(c)
    local nScroll, nFlask = 0, 0
    for k in keys:gmatch("%S+") do
      if k == "consume4425" or k == "consume10309" then nScroll = nScroll + 1 end
      if k == "consume274273" or k == "consume274276" then nFlask = nFlask + 1 end
    end
    assert(nScroll == 1 and nFlask == 1, "one of each asked: " .. keys)
    SPELL_NAMES[8117], SPELL_NAMES[12174], SPELL_NAMES[1293740], SPELL_NAMES[1293743] = nil, nil, nil, nil
    noErrors(c)
  end)

  test("review: a weapon's oil is never a lure or an armor's: D.IMBUE holds what goes on a main hand; a fisher's Nightcrawlers no Weapon row", function()
    for _, sp in ipairs({ 8087, 8088, 8089, 8090, 8532, 9092, 1265220, 1331725, 1219740, 463868 }) do
      assert(not D.IMBUE[sp], "not a main hand's: " .. sp)
    end
    for _, sp in ipairs({ 16138, 25122, 25123, 2823 }) do assert(D.IMBUE[sp], "kept: " .. sp) end
    local c = consumer({ class = "MAGE", role = "caster", items = { CN.wizard, { 6530, "Nightcrawlers", 0, 8, 8088 } } })
    c.items[5005] = { name = "Plain Staff", equipLoc = "INVTYPE_2HWEAPON" }
    c.equipped[16] = 5005
    assert(c.A.Consume.KindOf(6530) ~= "weapon", "a lure is no weapon's")
    c.A.Consume.SetKindDefault("weapon", "raid", true)
    goTo(c, "raid")
    local rec = find(shown(c, "mine"), "weapon16")
    assert(rec and rec.click.item == 20749, "the oil, not the lure: " .. tostring(rec and rec.click.item))
    local page = cnPage(c)
    assert(cnRow(page, 6530) == nil and cnRow(page, 20749), "no row for the lure")
    noErrors(c)
  end)

  test("review: a weapon's oil from the Consumables tab is asked only with consumables on and out of a city; the icon's Never reads Never on its row", function()
    local c = consumer({ class = "MAGE", role = "caster", items = { CN.wizard } })
    c.items[5005] = { name = "Plain Staff", equipLoc = "INVTYPE_2HWEAPON" }
    c.equipped[16] = 5005
    c.A.Consume.SetChoice(20749, "solo", true); tick(c, 1)
    assert(find(shown(c, "mine"), "weapon16"), "chosen for World: asked")
    c.resting = true; fire(c, "PLAYER_UPDATE_RESTING"); tick(c, 1)
    assert(not find(shown(c, "mine"), "weapon16"), "in a city: nothing")
    local page = cnPage(c)
    assert(cnRow(page, 20749).state.__text == "In town", cnRow(page, 20749).state.__text)
    c.resting = false; fire(c, "PLAYER_UPDATE_RESTING"); tick(c, 1)
    assert(find(shown(c, "mine"), "weapon16"), "out of town: asked again")
    c.A.Consume.Settings().on = false; c.A.Bar.Dirty("all"); tick(c, 1)
    assert(not find(shown(c, "mine"), "weapon16"), "consumables Off: nothing")
    c.A.Consume.Settings().on = true; c.A.Bar.Dirty("all"); tick(c, 1)
    assert(find(shown(c, "mine"), "weapon16"), "on again")
    -- the icon's Never: the bar never asks, and the row says so
    c.A.Bar.Menu(icon(c, "own", "weapon16"))
    local m = c.menus[#c.menus]
    m[2].fn(); tick(c, 1)
    assert(not find(shown(c, "mine"), "weapon16"), "Never: gone")
    local row = cnRow(page, 20749)
    assert(row.state.__text == "Never", "its row: " .. row.state.__text)
    noErrors(c)
  end)

  test("review: an item waiting out its cooldown says so on its tooltip and promises no click; the tab's timed words tick while it is open", function()
    local c = consumer({ class = "WARRIOR", role = "tank", items = { CN.stone, CN.heal } })
    goTo(c, "raid")
    c.A.Consume.SetChoice(13455, "raid", true); tick(c, 1)
    for _, b in ipairs(c.bags) do if b.id == 13455 or b.id == 13446 then b.cdStart, b.cd = c.clock - 30, 120 end end
    fire(c, "BAG_UPDATE_COOLDOWN"); tick(c, 1)
    local rec = find(shown(c, "mine"), "consume13455")
    assert(rec and not rec.lit and rec.clickWord == nil, "waiting: no click promised")
    local tip = table.concat(tipOf(c, icon(c, "own", "consume13455")), " | ")
    assert(not tip:find("Click:", 1, true) and tip:find("Ready when its cooldown ends.", 1, true), "its tooltip: " .. tip)
    -- the tab open: its Cooldown counts down, then Missing, with no event
    local page = cnPage(c)
    local function stateOf(id) for _, r in ipairs(page.rows) do if r.id == id and r.name:IsShown() then return r.state.__text end end end
    local first = stateOf(13455)
    assert(first:find("^Cooldown 1:2"), first)
    tick(c, 30)
    local later = stateOf(13455)
    assert(later ~= first and later:find("^Cooldown 0:5"), "30 s on: " .. tostring(later))
    tick(c, 62)
    assert(stateOf(13455) == "Missing", "its cooldown over: " .. tostring(stateOf(13455)))
    rec = find(shown(c, "mine"), "consume13455")
    assert(rec and rec.lit and rec.clickWord == "use it", "lit: a click uses it")
    noErrors(c)
  end)

  test("review: a 0.2.2 habit with no stat words (Swiftness of Zanza) has its row; its uses are seen, so it is kept; a new one is learned", function()
    local ZS = { 20081, "Swiftness of Zanza", 0, 8, 24383 }
    local c, me = consumer({ class = "ROGUE", role = "melee", items = { ZS } })
    c.A.Char().consume[20081] = { hits = 2, miss = 0, spell = 24383, at = 5 }
    goTo(c, "party")
    local rec = find(shown(c, "mine"), "consume20081")
    assert(rec and rec.word == "Use" and rec.why == "You keep this one up.", "the habit asked: " .. consumeKeys(c))
    local page = cnPage(c)
    local row = cnRow(page, 20081)
    assert(row and row.chips[3].on, "its row, asked in 5-man dungeons")
    c.env.CuteAurasWindow:Hide()
    -- shown ten minutes, then drunk, four times: kept
    for round = 1, 4 do
      tick(c, 590)
      fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-zs" .. round, 24383)
      auraOn(c, me, 24383, 7200)
      tick(c, 3)
      auraOff(c, me, 24383)
    end
    local e = c.A.Char().consume[20081]
    assert(e and e.hits >= 2 and (c.A.Char().consumeQuiet or {})[20081] == nil, "drunk each time: kept, never quiet")
    noErrors(c)
    -- a new character: two uses with a lasting aura, a habit
    local c2, me2 = consumer({ name = "Fresh", class = "ROGUE", role = "melee", items = { ZS } })
    for i = 1, 2 do
      fire(c2, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-zn" .. i, 24383)
      auraOn(c2, me2, 24383, 7200)
      tick(c2, 2)
      auraOff(c2, me2, 24383)
    end
    local e2 = c2.A.Char().consume[20081]
    assert(e2 and e2.hits == 2, "learned: " .. tostring(e2 and e2.hits))
    noErrors(c2)
  end)

  test("review: the site's picture (mock.html) draws 0.2.3: the bar on its 36 px step, Buff in amber, no Upgrade; the alerts an icon row, no card", function()
    local html = assert(io.open(HERE .. "/mock.html")):read("*a")
    local css = html:match("<style>(.-)</style>")
    local body = html:match("<body>(.-)</body>")
    assert(css and body, "its style and body")
    assert(not html:find("Upgrade", 1, true) and not css:find(".ic.wide", 1, true), "no Upgrade, no wide column")
    local bar = css:match("%.bar {([^}]*)}")
    assert(bar and bar:find("gap: 4px;", 1, true) and bar:find("padding: 4px 4px 9px;", 1, true), "the bar: 4 px apart, 4 px in: " .. tostring(bar))
    local part = css:match("%.part {([^}]*)}")
    assert(part and part:find("gap: 4px;", 1, true), "icons 4 px apart: " .. tostring(part))
    local w = css:match("%.ic %.w {([^}]*)}")
    assert(w and w:find("left: %-2px;") and w:find("width: 36px;", 1, true), "a word's box the 36 px step: " .. tostring(w))
    assert(body:find('<div class="w t" style="color:var(--warn)">Buff</div>', 1, true), "Buff in amber")
    -- yours in one part (camp, mine, gear), the group's 8 px after it
    local parts = 0
    for _ in body:gmatch('<div class="part') do parts = parts + 1 end
    assert(parts == 2, "two parts, yours and the group's: " .. parts)
    -- the alerts: icons in rows, their words in no box
    assert(not body:find('class="card"', 1, true) and not css:find("%.card "), "no card")
    local icons = 0
    for _ in body:gmatch('<div class="al[ "]') do icons = icons + 1 end
    assert(icons == 3, "three alert icons: " .. icons)
    assert(not body:find("Then Might goes back on.", 1, true), "0.2.2's words gone")
  end)
end


----------------------------------------------------------------------------
-- 0.2.3, the review's second round: a REQ held while a paladin who may answer fights, stamped when it leaves; a
-- PallyPower leader's class cells for your column kept apart from a member's own (a 0 from its grid's menu, a class
-- not in the group yet); no leaders in a battleground; the Consumables tab through a fight and past an aura's end; the
-- tab's oil on the bar; the Blessings tab's title; the ready check's Eat menu; an item chosen with no use counted; a
-- role change read at once
----------------------------------------------------------------------------
do
  local function nREQ(c) return #ppOut(c, "REQ") end

  test("review 2: a REQ waiting in the queue as a pull starts leaves only once no paladin who may answer fights; later messages pass it; it counts as sent when it leaves", function()
    local g = ppParty()
    local c = g.c2
    local Ps = c.A.PallySync
    tickAll(35)
    local before = nREQ(c)
    -- the asker's own messages ahead of it, the tab opened, then a pull
    for i = 1, 4 do c.A.Comm.Send("Z1|filler|" .. i) end
    Ps.AskTab()
    tick(c, 0.4)
    fight(c, true); g.YS.combat = true
    tick(c, 5)
    -- the asker out of it first; Ysolde, who may run PallyPower, fights on
    fight(c, false)
    c.A.Comm.Send("Z1|after")
    tick(c, 6)
    assert(nREQ(c) == before, "Ysolde still fights: the REQ waits (" .. (nREQ(c) - before) .. ")")
    local passed = false
    for _, s in ipairs(c.said) do if s == "Z1|after" then passed = true end end
    assert(passed, "a later message passes the waiting REQ")
    assert((Ps.stats.sentReq or 0) == before, "a REQ waiting is not counted sent: " .. tostring(Ps.stats.sentReq))
    g.YS.combat = false
    tick(c, 5)
    assert(nREQ(c) == before + 1, "Ysolde out of it: the REQ goes (" .. (nREQ(c) - before) .. ")")
    assert(Ps.stats.sentReq == before + 1, "counted once it left: " .. tostring(Ps.stats.sentReq))
    tick(c, 120)
    assert(nREQ(c) == before + 1, "one REQ for it (" .. (nREQ(c) - before) .. ")")
    for _, x in ipairs(g.all) do noErrors(x, "REQ held") end
  end)

  test("review 2: a PallyPower leader's grid (a 0 for members no NASSIGN set) leaves the leader's class cells for Orren; a member's own NASSIGN and its removal never move Orren's SELF row", function()
    local g = ppParty()
    local c1 = g.c1
    local function each(f) for _, c in ipairs(g.all) do f(c, c.A.Assign) end end
    local function row() return (c1.A.PallySync.SelfText():match("@(%S+)$")) end
    local function cells(want, label)
      each(function(c, As)
        for bk, key in pairs(want) do
          assert(As.BlessingOf(g.OR.guid, bk) == key, label .. ": " .. bk .. " " .. tostring(As.BlessingOf(g.OR.guid, bk)) .. ", not " .. key)
        end
      end)
    end
    ppSay(g.BR, "PASSIGN Orren Lightsworn@33nnnnnnn")
    tickAll(3)
    cells({ ["ROGUE:melee"] = "kings", ["WARRIOR:melee"] = "kings", ["WARRIOR:tank"] = "kings" }, "the leader's Kings")
    assert(row():sub(1, 2) == "33", "Orren's SELF row: " .. row())
    -- the leader opens Tamsin's menu in PallyPower's grid, and right-clicks Rask: a 0 for each, though no NASSIGN set them
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 2 Tamsin_Reed 0")
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 0")
    tickAll(3)
    cells({ ["ROGUE:melee"] = "kings", ["WARRIOR:melee"] = "kings", ["WARRIOR:tank"] = "kings" }, "a 0 for nothing set: still the leader's")
    assert(row():sub(1, 2) == "33", "Orren's SELF row unchanged: " .. row())
    -- Might for Tamsin alone: her bucket's; the rogues' class cell in Orren's SELF stays the leader's Kings
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 2 Tamsin_Reed 2")
    tickAll(3)
    cells({ ["ROGUE:melee"] = "might" }, "Tamsin's own Might")
    assert(row():sub(1, 2) == "33", "a member's own cell is no class cell: " .. row())
    -- a newer class cell meanwhile: Tamsin keeps her own (PallyPower's own beats its class's); the SELF says the new one
    ppSay(g.BR, "ASSIGN Orren Lightsworn 2 1")
    tickAll(3)
    cells({ ["ROGUE:melee"] = "might" }, "Tamsin's own still")
    assert(row():sub(2, 2) == "1", "the rogues' new class cell: " .. row())
    -- its removal: the class cell, the newer one
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 2 Tamsin_Reed 0")
    tickAll(3)
    cells({ ["ROGUE:melee"] = "wisdom" }, "back to the class cell")
    -- Orren's own click for the tank, newer than the leader's Kings; a NASSIGN for Brok and its removal: Orren's click again
    c1.A.Assign.Set(g.OR.guid, "WARRIOR:tank", "might")
    tickAll(3)
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 1")
    tickAll(3)
    cells({ ["WARRIOR:tank"] = "wisdom", ["WARRIOR:melee"] = "kings" }, "Brok's own")
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 0")
    tickAll(3)
    cells({ ["WARRIOR:tank"] = "might", ["WARRIOR:melee"] = "kings" }, "Orren's own click back")
    assert(row():sub(1, 2) == "31", "the SELF row: " .. row())
    for _, x in ipairs(g.all) do noErrors(x, "NASSIGN 0") end
  end)

  test("review 2: a leader's PallyPower cell for a class not in the group stays in Orren's SELF, over a reload too, and is Orren's for that class once one joins", function()
    local g = ppParty()
    local function row(c) return (c.A.PallySync.SelfText():match("@(%S+)$")) end
    ppSay(g.BR, "PASSIGN Orren Lightsworn@33nnnn3nn")
    tickAll(3)
    assert(row(g.c1):sub(7, 7) == "3", "mages: the leader's Kings, none here: " .. row(g.c1))
    -- Orren reloads in the same group
    local c1 = reload(g.c1)
    load(c1)
    g.c1, g.all[1] = c1, c1
    tickAll(12)
    assert(row(c1):sub(1, 2) == "33" and row(c1):sub(7, 7) == "3", "kept over the reload: " .. row(c1))
    -- a mage takes Rask's place: Kings from Orren on every client
    local MA = member({ name = "Maelis", surname = "Duskweaver", class = "MAGE", level = 60, guid = "Player-1-0F" })
    g.group[5] = MA
    for _, c in ipairs(g.all) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
    tickAll(6)
    for _, c in ipairs(g.all) do
      local ov = ovOf(c, g.OR.guid, "MAGE:caster")
      assert(ov and ov.key == "kings" and ov.pp and ov.from == g.OR.guid, "the mage's bucket: the leader's Kings, Orren's own cell")
      assert(c.A.Assign.BlessingOf(g.OR.guid, "MAGE:caster") == "kings", "Kings for the mage: " .. tostring(c.A.Assign.BlessingOf(g.OR.guid, "MAGE:caster")))
    end
    assert(row(c1):sub(7, 7) == "3", "the SELF row: " .. row(c1))
    -- Orren's own click for the mage afterwards wins, and is not taken back
    c1.A.Assign.Set(g.OR.guid, "MAGE:caster", "wisdom")
    tickAll(6)
    for _, c in ipairs(g.all) do assert(c.A.Assign.BlessingOf(g.OR.guid, "MAGE:caster") == "wisdom", "Orren's click kept") end
    for _, x in ipairs(g.all) do noErrors(x, "a class not here") end
  end)

  test("review 2: in a battleground (an instance group in an instance) PallyPower has no leaders: the leader's CLEAR and cells for another paladin are refused there; a paladin's own still count", function()
    local g = ppParty()
    ppSay(g.YS, YS_SELF)
    tickAll(2)
    local inGroup = {}
    for i, c in ipairs(g.all) do
      inGroup[i] = c.env.IsInGroup
      local was = inGroup[i]
      c.env.IsInGroup = function(cat) if cat == 2 then return true end return was(cat) end
      c.instance = "pvp"
    end
    local ref = {}
    for i, c in ipairs(g.all) do ref[i] = c.A.PallySync.stats.refused or 0 end
    ppSay(g.BR, "CLEAR")
    ppSay(g.BR, "PASSIGN Ysolde Ashbrook@333333333")
    ppSay(g.BR, "NASSIGN Ysolde_Ashbrook 2 Tamsin_Reed 3")
    ppSay(g.BR, "ASSIGN Orren Lightsworn 1 3")
    tickAll(3)
    for i, c in ipairs(g.all) do
      local As, Ps = c.A.Assign, c.A.PallySync
      assert(Ps.row[g.YS.guid] and As.BlessingOf(g.YS.guid, "ROGUE:melee") == "might", "Ysolde's own row kept")
      assert(Ps.MemberCell(g.YS.guid, g.TA.guid) == nil, "no member cell taken")
      assert(ovOf(c, g.OR.guid, "WARRIOR:melee") == nil and ovOf(c, g.OR.guid, "WARRIOR:tank") == nil, "nothing set for Orren")
      assert(Ps.stats.refused == ref[i] + 3, "refused + 3: " .. tostring(Ps.stats.refused) .. " from " .. ref[i])
    end
    -- Ysolde's own ASSIGN counts
    ppSay(g.YS, "ASSIGN Ysolde Ashbrook 2 3")
    tickAll(2)
    for _, c in ipairs(g.all) do assert(c.A.Assign.BlessingOf(g.YS.guid, "ROGUE:melee") == "kings", "their own cell taken") end
    -- out of it: the leader leads again
    for i, c in ipairs(g.all) do c.env.IsInGroup = inGroup[i]; c.instance = nil end
    ppSay(g.BR, "ASSIGN Orren Lightsworn 1 3")
    tickAll(3)
    for _, c in ipairs(g.all) do
      local ov = ovOf(c, g.OR.guid, "WARRIOR:melee")
      assert(ov and ov.key == "kings" and ov.pp, "the leader's cell for Orren taken outside")
    end
    for _, x in ipairs(g.all) do noErrors(x, "battleground") end
  end)

  test("review 2: the Consumables tab open through a fight: In a fight as it starts, its countdown again as it ends, with no other event", function()
    local c, me = consumer({ class = "WARRIOR", role = "tank", items = { CN.mongoose } })
    goTo(c, "party")
    auraOn(c, me, 17538, 2470)
    local page = cnPage(c)
    page:Sync()
    local function stateOf(id) for _, r in ipairs(page.rows) do if r.id == id and r.name:IsShown() then return r.state.__text end end end
    assert(stateOf(13452):find("^On you %d"), stateOf(13452))
    fight(c, true); tick(c, 2)
    assert(stateOf(13452) == "In a fight", "in the fight: " .. stateOf(13452))
    fight(c, false); tick(c, 2)
    local s = stateOf(13452)
    assert(s:find("^On you %d"), "the fight over: its countdown again, " .. s)
    tick(c, 2)
    assert(stateOf(13452) ~= s and stateOf(13452):find("^On you %d"), "and it ticks: " .. stateOf(13452))
    noErrors(c)
  end)

  test("review 2: an aura past its end that the client still lists reads Missing on the tab, Well Fed's too, never a bare On you", function()
    local c, me = consumer({ class = "WARRIOR", role = "tank", items = { CN.mongoose }, food = true })
    goTo(c, "party")
    auraOn(c, me, 17538, 3)
    me.auras[#me.auras + 1] = { id = 24799, src = "player", exp = c.clock + 3, dur = 900 }
    fire(c, "UNIT_AURA", "player"); tick(c, 0.5)
    local page = cnPage(c)
    assert(cnRow(page, 13452).state.__text:find("^On you %d"), cnRow(page, 13452).state.__text)
    assert(cnRow(page, "fed").state.__text:find("^On you %d"), cnRow(page, "fed").state.__text)
    tick(c, 4)
    local row, fed = cnRow(page, 13452), cnRow(page, "fed")
    assert(row.state.__text == "Missing", "the elixir's end passed, its aura still listed: " .. row.state.__text)
    assert(fed.state.__text == "Missing", "Well Fed's: " .. fed.state.__text)
    noErrors(c)
  end)

  test("review 2: the tab's oil on a bare main hand: its Never is that oil's own, its row's chips agree and its Never chip undoes it; its menu has Consumables... and Ask for it in; the per-weapon habit keeps your weapon", function()
    local c = consumer({ class = "MAGE", role = "caster", items = { CN.wizard } })
    c.items[5005] = { name = "Plain Staff", equipLoc = "INVTYPE_2HWEAPON" }
    c.equipped[16] = 5005
    goTo(c, "raid")
    c.A.Consume.SetChoice(20749, "raid", true); tick(c, 1)
    assert(find(shown(c, "mine"), "weapon16"), "chosen for Raid: asked")
    c.A.Bar.Menu(icon(c, "own", "weapon16"))
    local m = c.menus[#c.menus]
    local words = {}
    for _, e in ipairs(m) do words[#words + 1] = e.text end
    local want = { "Not now", "Never: Brilliant Wizard Oil", "Consumables...", "Settings...", "Ask for it in" }
    for _, p in ipairs(c.A.Consume.PLACES) do want[#want + 1] = p[2] end
    assert(table.concat(words, ", ") == table.concat(want, ", "), "its menu: " .. table.concat(words, ", "))
    for _, e in ipairs(m) do if e.kind == "check" and e.text == "Raid" then assert(e.get() == true, "Raid ticked") end end
    m[2].fn(); tick(c, 1)
    local never = c.A.Settings().never
    assert(never["consume:20749"] and never.weapon == nil, "the oil's own Never")
    assert(not find(shown(c, "mine"), "weapon16"), "Never: gone")
    local page = cnPage(c)
    local row = cnRow(page, 20749)
    assert(row.state.__text == "Never" and not row.chips[4].on and row.never.on, "its row: Never, Raid unlit, Never lit: " .. row.state.__text)
    c.click(row.never); tick(c, 1)
    row = cnRow(page, 20749)
    assert(row.state.__text == "Missing" and row.chips[4].on and not row.never.on, "Never undone on its row: " .. row.state.__text)
    assert(find(shown(c, "mine"), "weapon16"), "asked again")
    -- the per-weapon habit: its own Never, your weapon
    c.A.Consume.ClearChoice(20749)
    c.A.Char().weapon = { [5005] = { item = 20749, hits = 3 } }
    c.A.Bar.Dirty("all"); tick(c, 1)
    c.A.Bar.Menu(icon(c, "own", "weapon16"))
    m = c.menus[#c.menus]
    assert(m[2].text == "Never: your weapon", m[2].text)
    noErrors(c)
  end)

  test("review 2: a paladin who gives no blessings, with a PallyPower paladin heard: the Blessings tab's title names the box, not a column to click", function()
    local g = ppParty()
    ppSay(g.YS, YS_SELF)
    tickAll(2)
    local c1 = g.c1
    c1.A.Settings().blessings = false
    c1.A.Comm.GivesChanged()
    tickAll(3)
    c1.A.Window.Open("blessings")
    local p = c1.A.Window.pages.blessings
    p:Sync()
    assert(p.title.__text == "You give no blessings now: Blessings shared out by Cute Auras is off (Settings).", p.title.__text)
    FITS(p.title, "the title")
    for _, x in ipairs(g.all) do noErrors(x, "title") end
  end)

  test("review 2: the ready check's Eat icon has no Ask for it in (Well Fed's boxes do not ask it; its Never does); a flask's keeps its boxes", function()
    local c = consumer({ class = "WARRIOR", role = "tank", items = { CN.mongoose }, food = true })
    goTo(c, "raid")
    c.A.Consume.SetChoice(13452, "raid", true)
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(find(shown(c, "pull"), "pullfood") and find(shown(c, "pull"), "flask13452"), "Eat and the elixir before the pull: " .. pullKeys(c))
    c.A.Bar.Menu(icon(c, "own", "pullfood"))
    local m = c.menus[#c.menus]
    for _, e in ipairs(m) do assert(e.kind == "button", "no box or title on the food's menu: " .. e.text) end
    local names = {}
    for _, e in ipairs(m) do names[#names + 1] = e.text end
    assert(table.concat(names, ", ") == "Not now, Never: Food before the pull, Consumables..., Settings...", table.concat(names, ", "))
    c.A.Bar.Menu(icon(c, "own", "flask13452"))
    m = c.menus[#c.menus]
    local checks = 0
    for _, e in ipairs(m) do if e.kind == "check" then checks = checks + 1 end end
    assert(checks == 4, "the elixir's four boxes: " .. checks)
    noErrors(c)
  end)

  test("review 2: an item with no stat words chosen for a raid is asked there and at a ready check, with no use counted", function()
    local c = consumer({ class = "WARRIOR", role = "tank" })
    c.items[5996] = { name = "Elixir of Water Breathing", classID = 0, subID = 2, spell = 7178 }
    c.bags = { { id = 5996, bag = 0, slot = 1, count = 5 } }
    fire(c, "BAG_UPDATE_DELAYED"); tick(c, 1)
    assert(c.A.Consume.Words(5996) == "" and not c.A.Consume.Counts(5996), "no words, no use")
    c.A.Consume.SetChoice(5996, "raid", true)
    goTo(c, "raid")
    assert(find(shown(c, "mine"), "consume5996"), "chosen for Raid: asked there, " .. consumeKeys(c))
    local row = cnRow(cnPage(c), 5996)
    assert(row and row.state.__text == "Missing" and row.chips[4].on, "its row: " .. tostring(row and row.state.__text))
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(find(shown(c, "pull"), "flask5996"), "and before the pull: " .. pullKeys(c))
    noErrors(c)
  end)

  test("review 2: your role changed in Settings or by the group's mark: your consumables are read again at once", function()
    local c, me = consumer({ class = "PALADIN", role = "healer", items = { CN.giants } })
    goTo(c, "party")
    assert(not find(shown(c, "mine"), "consume9206"), "a healer: no Elixir of Giants")
    c.A.Window.Open("settings")
    local roleRow = widget(c.A.Window.pages.settings, "Your role")
    local function pick(v) for _, b in ipairs(roleRow.buttons) do if b.value == v then c.click(b) end end end
    pick("tank"); tick(c, 2)
    assert(find(shown(c, "mine"), "consume9206"), "Tank chosen: asked at once, " .. consumeKeys(c))
    pick("healer"); tick(c, 2)
    assert(not find(shown(c, "mine"), "consume9206"), "Heal chosen: gone at once")
    -- Auto with no talents read: the class's guess hides nothing; then the group marks you a healer
    pick("auto"); tick(c, 2)
    assert(find(shown(c, "mine"), "consume9206"), "a guess: asked")
    me.assigned = "HEALER"
    fire(c, "PLAYER_ROLES_ASSIGNED"); tick(c, 2)
    assert(not find(shown(c, "mine"), "consume9206"), "marked a healer: gone at once")
    noErrors(c)
  end)
end

----------------------------------------------------------------------------
-- review round 3: a potion drunk in a fight that outlasts it; a leader's NASSIGN for a member gone; PallyPower's copy of
-- our row after a leader's 0 or CLEAR; PallyPower turned on in the group; the weapon habit and the oil's Never; the
-- Consumables tab on an aura change; an item with no stat words; the Blessings titles for one who is no paladin; the
-- rebuff's name and its slot; a member leaving teaches nothing; Before the pull's order in a group
----------------------------------------------------------------------------
do
  test("review 3: a 2-minute potion drunk in a fight counts by its length from the drink, also when the fight goes on past its end; a healing potion never", function()
    for _, len in ipairs({ 10, 80, 150 }) do
      local c, me = consumer({ class = "WARRIOR", role = "tank", items = { CN.stone, CN.heal } })
      fight(c, true)
      fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-s" .. len, 17540)
      me.auras = { { id = 17540, src = "player", exp = c.clock + 120, dur = 120 } }
      tick(c, 5)
      fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-h" .. len, 17534)
      tick(c, len - 5)
      -- (its two minutes over in the fight: the client lists it no more)
      if len > 120 then me.auras = {} end
      fight(c, false); tick(c, 10)
      local e = c.A.Char().consume[13455]
      assert(e and e.hits == 1, "the fight went on " .. len .. " s after the drink: counted once (" .. tostring(e and e.hits) .. ")")
      assert(c.A.Char().consume[13446] == nil, "a healing potion in the fight: no use counted")
      noErrors(c, "a potion in a fight")
    end
  end)

  test("review 3: a leader's NASSIGN for a member who leaves: that bucket gets back what it covered, the next member there the leader's class cell, on every client and in Orren's SELF", function()
    local g = ppParty()
    local function row() return (g.c1.A.PallySync.SelfText():match("@(%S+)$")) end
    ppSay(g.YS, "SELF 607010nnnnnn@3nnnnnnnn")
    tickAll(3)
    ppSay(g.BR, "PASSIGN Orren Lightsworn@2nnnnnnnn")
    tickAll(3)
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
    tickAll(3)
    for _, c in ipairs(g.all) do
      assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "kings", "Rask's own Kings from Orren")
    end
    assert(row():sub(1, 1) == "2", "the warriors' class cell in Orren's SELF: " .. row())
    -- Rask leaves; a warrior with no addon takes the place
    local KE = member({ name = "Kerr", surname = "Bladeson", class = "WARRIOR", level = 60, guid = "Player-1-0F" })
    g.group[5] = KE
    for _, c in ipairs(g.all) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
    tickAll(10)
    for _, c in ipairs(g.all) do
      local As = c.A.Assign
      assert(As.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", "Kerr: the leader's Might from Orren, " .. tostring(As.BlessingOf(g.OR.guid, "WARRIOR:melee")))
      assert(As.BlessingOf(g.YS.guid, "WARRIOR:melee") == "kings", "and Ysolde's Kings")
    end
    local ov = ovOf(g.c1, g.OR.guid, "WARRIOR:melee")
    assert(ov and ov.key == "might" and ov.pp, "Orren's cell: the leader's class cell again")
    assert(row():sub(1, 1) == "2", "Orren's SELF row: " .. row())
    for _, x in ipairs(g.all) do noErrors(x, "NASSIGN, a member gone") end
  end)

  test("review 3: a leader's NASSIGN for a member who left while Orren reloaded: put back after the reload, sent, and the next warrior there gets the class cell", function()
    local g = ppParty()
    ppSay(g.BR, "PASSIGN Orren Lightsworn@2nnnnnnnn")
    tickAll(3)
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
    tickAll(3)
    assert(g.c2.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "kings", "Rask's own Kings")
    local c1 = reload(g.c1)
    table.remove(g.group, 5)
    for _, c in ipairs({ g.c2, g.c3 }) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
    load(c1)
    g.c1, g.all[1] = c1, c1
    tickAll(12)
    for _, c in ipairs(g.all) do
      local ov = ovOf(c, g.OR.guid, "WARRIOR:melee")
      assert(ov and ov.key == "might" and ov.pp, "Rask gone over the reload: the bucket's cell back to the leader's Might, " .. tostring(ov and ov.key))
    end
    local KE = member({ name = "Kerr", surname = "Bladeson", class = "WARRIOR", level = 60, guid = "Player-1-0F" })
    g.group[#g.group + 1] = KE
    for _, c in ipairs(g.all) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
    tickAll(6)
    for _, c in ipairs(g.all) do
      assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", "Kerr: Might from Orren, " .. tostring(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee")))
    end
    for _, x in ipairs(g.all) do noErrors(x, "NASSIGN over a reload") end
  end)

  test("review 3: a leader's 0 or CLEAR for Orren's column changes PallyPower's copy of it, not what Orren casts: Orren's SELF goes again", function()
    local g = ppParty()
    ppSay(g.BR, "REQ")
    tickAll(24)
    local list = ppOut(g.c1, "SELF")
    assert(#list >= 1, "Orren answered the leader's REQ")
    local self0 = list[#list].msg
    assert(self0:match("@(%S+)$"):sub(1, 1) == "2" and g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", "Orren gives the warriors Might: " .. self0)
    local n = #list
    -- the leader right-clicks Orren's warrior cell in PallyPower's grid: a 0 there, Might still cast
    ppSay(g.BR, "ASSIGN Orren Lightsworn 1 0")
    tickAll(24)
    list = ppOut(g.c1, "SELF")
    assert(#list == n + 1 and list[#list].msg == self0, "after the leader's 0: one SELF, the same Might (" .. (#list - n) .. ")")
    assert(g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", "Orren still gives Might")
    n = #list
    ppSay(g.BR, "CLEAR")
    tickAll(24)
    list = ppOut(g.c1, "SELF")
    assert(#list == n + 1 and list[#list].msg == self0, "after the leader's CLEAR: one SELF again (" .. (#list - n) .. ")")
    -- a cell from the leader Orren's cells take: its own SELF, once
    n = #list
    ppSay(g.BR, "ASSIGN Orren Lightsworn 1 3")
    tickAll(24)
    list = ppOut(g.c1, "SELF")
    assert(#list == n + 1 and list[#list].msg:match("@(%S+)$"):sub(1, 1) == "3", "the leader's Kings: one SELF saying so (" .. (#list - n) .. ")")
    for _, x in ipairs(g.all) do noErrors(x, "PallyPower's copy") end
  end)

  test("review 3: a member turns PallyPower on and reloads in the group: its SELF came before its new hello, so the asker asks again and every client lists it", function()
    local g = ppParty()
    tickAll(40)
    local nReq = #ppOut(g.c2, "REQ")
    local c1 = reload(g.c1)
    c1.o.addons = PP_ADDON; c1.addons = PP_ADDON
    load(c1)
    g.c1, g.all[1] = c1, c1
    -- (PallyPower's SELF at its login, before Cute Auras' hello: no S1 before it, so the old hello is let go and the
    -- SELF is PallyPower's at once)
    ppSay(g.OR, "SELF 607010nnnnnn@2n2222222")
    tickAll(1)
    assert(g.c2.A.PallySync.pals[g.OR.guid], "PallyPower's SELF, no S1 before it: listed at once")
    tickAll(45)
    assert(g.c2.A.Comm.peers[g.OR.guid].ppField == "pp", "the new hello heard")
    assert(#ppOut(g.c2, "REQ") > nReq, "the asker asks again (" .. (#ppOut(g.c2, "REQ") - nReq) .. ")")
    -- Orren's PallyPower answers the asker by whisper; the asker passes it to the group
    ppSay(g.OR, "SELF 607010nnnnnn@2n2222222", g.TA)
    tickAll(4)
    for _, c in ipairs(g.all) do
      assert(c.A.PallySync.pals[g.OR.guid], c.o.me.name .. ": Orren listed")
      assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", c.o.me.name .. ": Orren's PallyPower Might, " .. tostring(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee")))
    end
    for _, x in ipairs(g.all) do noErrors(x, "PallyPower turned on") end
  end)

  test("review 3: an oil's own Never, or its place unticked, also stops the per-weapon habit asking for that oil; a habit the tab has no say on keeps asking", function()
    local c = consumer({ class = "MAGE", role = "caster", items = { CN.wizard } })
    c.items[5005] = { name = "Plain Staff", equipLoc = "INVTYPE_2HWEAPON" }
    c.equipped[16] = 5005
    c.A.Char().weapon = { [5005] = { item = 20749, hits = 3 } }
    goTo(c, "raid")
    c.A.Consume.SetChoice(20749, "raid", true); tick(c, 1)
    local rec = find(shown(c, "mine"), "weapon16")
    assert(rec and rec.never == "consume:20749", "the tab's oil")
    c.A.Bar.SetNever(rec.never, rec.neverName); tick(c, 1)
    assert(not find(shown(c, "mine"), "weapon16"), "Never: Brilliant Wizard Oil, and the habit asks it no more")
    assert(cnRow(cnPage(c), 20749).state.__text == "Never", "its row: Never")
    c.A.Bar.SetNever("consume:20749", nil, false); tick(c, 1)
    assert(find(shown(c, "mine"), "weapon16"), "its Never undone: asked again")
    c.A.Consume.SetChoice(20749, "raid", false); tick(c, 1)
    assert(not find(shown(c, "mine"), "weapon16"), "Raid unticked: the habit asks it no more there")
    -- the open world: no choice of its own there, the habit as in 0.2.2
    goTo(c, nil)
    rec = find(shown(c, "mine"), "weapon16")
    assert(rec and rec.never == "weapon" and rec.click.item == 20749, "the habit in the open world: " .. tostring(rec and rec.never))
    noErrors(c, "the oil's Never")
  end)

  test("review 3: the Consumables tab reads again when your auras change with no bag event: Well Fed lands, its row says so", function()
    local c, me = consumer({ class = "WARRIOR", role = "tank", food = true })
    goTo(c, "party")
    local page = cnPage(c)
    page:Sync()
    local function stateOf(id) for _, r in ipairs(page.rows) do if r.id == id and r.name:IsShown() then return r.state.__text end end end
    assert(stateOf("fed") == "Missing", "not fed: " .. tostring(stateOf("fed")))
    me.auras[#me.auras + 1] = { id = 24799, src = "player", exp = c.clock + 900, dur = 900 }
    fire(c, "UNIT_AURA", "player"); tick(c, 2)
    assert(stateOf("fed"):find("^On you %d"), "Well Fed landed: " .. tostring(stateOf("fed")))
    noErrors(c, "the tab on an aura")
  end)

  test("review 3: an item with no stat words used once reads Off in a 5-man and a raid, never Not your role", function()
    local c = consumer({ class = "WARRIOR", role = "tank" })
    c.items[5996] = { name = "Elixir of Water Breathing", classID = 0, subID = 2, spell = 7178 }
    c.bags = { { id = 5996, bag = 0, slot = 1, count = 5 } }
    c.A.Consume.Habits()[5996] = { hits = 1, miss = 0, spell = 7178, at = 1000 }
    fire(c, "BAG_UPDATE_DELAYED"); tick(c, 1)
    for _, where in ipairs({ "party", "raid" }) do
      goTo(c, where)
      local row = cnRow(cnPage(c), 5996)
      assert(row and row.state.__text == "Off", where .. ": " .. tostring(row and row.state.__text))
      assert(not find(shown(c, "mine"), "consume5996"), "not asked")
    end
    noErrors(c, "no stat words")
  end)

  test("review 3: a member who is no paladin is never told to click a column of theirs; the leader is told to click a cell", function()
    local g = ppParty()
    local function title(c)
      c.A.Window.Open("blessings")
      local p = c.A.Window.pages.blessings
      p:Sync()
      FITS(p.title, c.o.me.name .. "'s title")
      return p.title.__text
    end
    assert(title(g.c2) == "Each paladin sets their own column; the leader or an assist can set any.", title(g.c2))
    assert(title(g.c3) == "Click a cell to change a blessing; right-click for Cute Auras' choice.", title(g.c3))
    assert(title(g.c1) == "Click your column to change a blessing; right-click for Cute Auras' choice.", title(g.c1))
    ppSay(g.YS, YS_SELF)
    tickAll(2)
    assert(title(g.c2) == "Ysolde uses PallyPower: shown as set there.", title(g.c2))
    assert(title(g.c3) == "Ysolde uses PallyPower: shown as set there. Click another paladin's cell to change it.", title(g.c3))
    assert(title(g.c1) == "Ysolde uses PallyPower: shown as set there. Click your column; right-click for Cute Auras' choice.", title(g.c1))
    for _, x in ipairs(g.all) do noErrors(x, "titles") end
  end)

  test("review 3: the rebuff moved to a member with a longer name out of a fight: the click row laid out again for it", function()
    local PAL = member({ name = "Wolfwardenmw", class = "PALADIN", level = 50, guid = "Player-1-C3" })
    local BO = member({ name = "Bo", class = "ROGUE", level = 50, guid = "Player-1-D4" })
    local BR = member({ name = "Bramblewoode", class = "PRIEST", level = 50, guid = "Player-1-B2" })
    local WAR = member({ name = "Wardenwallow", class = "WARRIOR", level = 50, guid = "Player-1-E5", assigned = "TANK" })
    local group = { PAL, BO, BR, WAR }
    local c = client({ me = PAL, group = group, spec = 184 })
    knowAll(c, "PALADIN", 50)
    load(c)
    tick(c, 12)
    local card, rb = c.env.CuteAurasRestore, c.env.CuteAurasRebuff
    fight(c, true)
    hand(c, WAR, 1044, 1)
    tick(c, 11)
    BO.dead = true; tick(c, 1); BO.dead = false; tick(c, 1)
    assert(rb:IsShown() and rb.name.__text == "Bo", "the rebuff for Bo")
    -- you die while the group fights on; a member raised meanwhile waits; then you are back, out of a fight
    PAL.dead = true
    for _, m in ipairs({ BO, BR, WAR }) do m.combat = true end
    fight(c, false); tick(c, 1)
    BR.dead = true; tick(c, 1); BR.dead = false; tick(c, 1)
    PAL.dead = false
    fire(c, "PLAYER_ALIVE"); tick(c, 1)
    assert(card:IsShown() and rb:IsShown() and rb.name.__text == "Bo", "the restore and the rebuff for Bo")
    -- (the restore's slot left of the rebuff's, 8 apart, the row centred: its x is half the gap and the rebuff's slot)
    local function restoreX(name) return -(8 + math.max(36, math.ceil(TEXT_WIDTH(name, 10)))) / 2 end
    assert(math.abs(card.__points[1][4] - restoreX("Bo")) < 0.01, "the restore beside Bo's slot: " .. card.__points[1][4])
    c.click(rb, "RightButton")
    assert(rb:IsShown() and rb.name.__text == "Bramblewoode", "the rebuff now for Bramblewoode: " .. tostring(rb.name.__text))
    assert(math.abs(card.__points[1][4] - restoreX("Bramblewoode")) < 0.01, "the click row laid out again for the longer name: " .. card.__points[1][4] .. ", not " .. restoreX("Bramblewoode"))
    noErrors(c, "rebuff name")
  end)

  test("review 3: a member leaving out of a fight teaches nothing: the reads before the roster and the share-out are read again never take the member who moved into their unit", function()
    -- (with a member's aura change just before the leave, the group's read waits past the roster's scan, whose records
    -- are filled again in place; without one, it comes at once, before the scan, on the moved tokens)
    for _, auraFirst in ipairs({ true, false }) do
      local label = auraFirst and "after the scan" or "before the scan"
      local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-U1" })
      local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-U2" })
      local PR = member({ name = "Pell", surname = "Ashdown", class = "PRIEST", level = 60, guid = "Player-1-U3" })
      local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-U4", assigned = "TANK", leader = true })
      local group = { OR, TA, PR, BR }
      local c1 = client({ me = OR, group = group, spec = 184 })
      knowAll(c1, "PALADIN", 60)
      load(c1)
      tick(c1, 12)
      local As, D, H = c1.A.Assign, c1.A.Data, c1.A.Hands
      local cells = { ["ROGUE:melee"] = As.BlessingOf(OR.guid, "ROGUE:melee"), ["PRIEST:healer"] = As.BlessingOf(OR.guid, "PRIEST:healer"),
                      ["WARRIOR:tank"] = As.BlessingOf(OR.guid, "WARRIOR:tank") }
      assert(cells["ROGUE:melee"] ~= cells["PRIEST:healer"] and cells["PRIEST:healer"] ~= cells["WARRIOR:tank"], "three blessings")
      -- your blessings on them as the share-out says, cast after the cells were set
      TA.auras = { { id = D.BLESS[cells["ROGUE:melee"]].ranks[1], src = "player", exp = c1.clock + 3600, dur = 3600 } }
      PR.auras = { { id = D.BLESS[cells["PRIEST:healer"]].ranks[1], src = "player", exp = c1.clock + 3600, dur = 3600 } }
      BR.auras = { { id = D.BLESS[cells["WARRIOR:tank"]].ranks[1], src = "player", exp = c1.clock + 3600, dur = 3600 } }
      for _, u in ipairs({ "party1", "party2", "party3" }) do fire(c1, "UNIT_AURA", u) end
      tick(c1, 5)
      assert(H.saw[PR.guid] and H.saw[PR.guid].key == cells["PRIEST:healer"], label .. ": the priest's noted")
      local sent = #c1.sent
      if auraFirst then fire(c1, "UNIT_AURA", "party2"); tick(c1, 0.1) end
      -- the rogue leaves: the tokens move at once
      table.remove(group, 2)
      seat(c1)
      fire(c1, "GROUP_ROSTER_UPDATE")
      tick(c1, 0.2)
      local saw = H.saw[PR.guid]
      assert(saw and saw.key == cells["PRIEST:healer"], label .. ": the priest never noted with the tank's blessing: " .. tostring(saw and saw.key))
      tick(c1, 3)
      local mine = As.overrides[OR.guid]
      assert(mine == nil or next(mine) == nil, label .. ": no cell taught")
      for i = sent + 1, #c1.sent do assert(not c1.sent[i].msg:find("^O1"), label .. ": no O1 sent: " .. c1.sent[i].msg) end
      assert(As.BlessingOf(OR.guid, "PRIEST:healer") == cells["PRIEST:healer"], label .. ": the priest's cell kept: " .. tostring(As.BlessingOf(OR.guid, "PRIEST:healer")))
      saw = H.saw[PR.guid]
      assert(saw and saw.key == cells["PRIEST:healer"], label .. ": the priest's blessing noted as theirs: " .. tostring(saw and saw.key))
      noErrors(c1, "a member leaving, " .. label)
    end
  end)

  test("review 3: before the pull a group's member is the first by your choice, your habit, then a fit; the one whose buff ends keeps its place, with its own countdown and click", function()
    -- a healer's Distilled Wisdom habit, Titans carried
    local c, me = consumer({ class = "PRIEST", role = "healer", items = { CN.titans, CN.wisdom }, food = true })
    c.A.Consume.Habits()[13511] = { hits = 5, miss = 0, spell = 17627, at = 1000 }
    goTo(c, "raid")
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(find(shown(c, "pull"), "flask13511") and not find(shown(c, "pull"), "flask13510"), "the habit's flask: " .. pullKeys(c))
    -- its buff on, 2:30 left: its own countdown on its own icon
    local c2, me2 = consumer({ class = "PRIEST", role = "healer", items = { CN.titans, CN.wisdom }, food = true })
    c2.A.Consume.Habits()[13511] = { hits = 5, miss = 0, spell = 17627, at = 1000 }
    goTo(c2, "raid")
    auraOn(c2, me2, 17627, 150)
    fire(c2, "READY_CHECK"); tick(c2, 4)
    local r = find(shown(c2, "pull"), "flask13511")
    assert(r and r.status == "warn" and r.word:find("^2:%d%d$") and r.click.item == 13511, "its own countdown: " .. pullKeys(c2))
    assert(not find(shown(c2, "pull"), "flask13510"), "no Titans")
    -- chosen for Raid, no habit
    local c3 = consumer({ class = "PRIEST", role = "healer", items = { CN.titans, CN.wisdom }, food = true })
    c3.A.Consume.SetChoice(13511, "raid", true)
    goTo(c3, "raid")
    fire(c3, "READY_CHECK"); tick(c3, 4)
    assert(find(shown(c3, "pull"), "flask13511") and not find(shown(c3, "pull"), "flask13510"), "the chosen flask: " .. pullKeys(c3))
    -- a rogue's Mongoose habit, 2:00 left, Greater Agility carried: the Mongoose's countdown, its own click
    local c4, me4 = consumer({ class = "ROGUE", role = "melee", items = { CN.mongoose, CN.gagi }, food = true })
    c4.A.Consume.Habits()[13452] = { hits = 4, miss = 0, spell = 17538, at = 2000 }
    goTo(c4, "party")
    auraOn(c4, me4, 17538, 120)
    fire(c4, "READY_CHECK"); tick(c4, 4)
    local m = find(shown(c4, "pull"), "flask13452")
    assert(m and m.click.item == 13452 and m.status == "warn", "the Mongoose's countdown: " .. pullKeys(c4))
    assert(not find(shown(c4, "pull"), "flask9187"), "no Greater Agility: " .. pullKeys(c4))
    -- Greater Agility chosen for 5-man, the Mongoose (a fit) on and ending: the Mongoose keeps its place
    local c5, me5 = consumer({ class = "ROGUE", role = "melee", items = { CN.mongoose, CN.gagi }, food = true })
    c5.A.Consume.SetChoice(9187, "dungeon", true)
    goTo(c5, "party")
    fire(c5, "READY_CHECK"); tick(c5, 4)
    assert(find(shown(c5, "pull"), "flask9187") and not find(shown(c5, "pull"), "flask13452"), "the chosen one first: " .. pullKeys(c5))
    fire(c5, "READY_CHECK_FINISHED"); tick(c5, 12)
    auraOn(c5, me5, 17538, 120)
    fire(c5, "READY_CHECK"); tick(c5, 4)
    m = find(shown(c5, "pull"), "flask13452")
    assert(m and m.status == "warn" and not find(shown(c5, "pull"), "flask9187"), "the ending Mongoose's countdown on its own: " .. pullKeys(c5))
    for _, x in ipairs({ c, c2, c3, c4, c5 }) do noErrors(x, "the pull's order") end
  end)
end

----------------------------------------------------------------------------
-- review 4: the restore's click icon after a member leaves, two Hands on one member, the glow in the restore's own
-- list; PallyPower paladins whose hello says it runs there asked for their SELF, a PallyPower client passing whispers
-- on, a leader's NASSIGN after a role change or in a grown bucket, a 0 then a CLEAR; a premade in a battleground; the
-- rebuff watchers' raid names; the Consumables tab's words (On you first, Settings that stop the bar, a level), its
-- chips' tooltips and the bar's Never on it, Well Fed's World chip, the main hand's poison, a chosen item's own buff
-- before the pull, an item you can't use, the camp's Eat Never
----------------------------------------------------------------------------

test("review 4: a member before them leaving out of a fight: the restore click icon follows its member's new unit, a stale unit's read ends nothing, and no click blesses the member who moved in", function()
  local g = party5()
  local c = g.c3
  local Hn, D = c.A.Hands, c.A.Data
  local rog = g.ROG.guid
  hand(c, g.ROG, 10278, 1)
  tick(c, 13)
  local rb = c.env.CuteAurasRestore
  assert(Hn.pending[rog] and Hn.pending[rog].bless == "might", "the rogue's restore: Might")
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.ROG, "the click icon on the rogue")
  -- the warrior carries a Might (another paladin's); the second priest leaves: the warrior moves into the rogue's unit
  g.WAR.auras[#g.WAR.auras + 1] = { id = D.BLESS.might.ranks[1], src = "raid9", exp = c.clock + 3000, dur = 3600 }
  for i, m in ipairs(g.group) do if m == g.P2 then table.remove(g.group, i) break end end
  seat(c)
  fire(c, "GROUP_ROSTER_UPDATE")
  assert(Hn.pending[rog], "the warrior's Might under the rogue's old unit ends nothing")
  assert(not rb:IsShown() or c.units[rb:GetAttribute("unit")] == g.ROG, "before the roster is read again, no click reaches the warrior")
  tick(c, 3)
  assert(Hn.pending[rog], "still the rogue's restore")
  assert(rb:IsShown() and rb.guid == rog, "the click icon back on the rogue")
  assert(c.units[rb:GetAttribute("unit")] == g.ROG, "its unit the rogue's now: " .. tostring(rb:GetAttribute("unit")))
  c.casts = {}
  c.click(rb)
  assert(#c.casts == 1 and c.units[c.casts[1].unit] == g.ROG, "the click blesses the rogue")
  noErrors(c, "a member before them left")
end)

test("review 4: a second Hand on a member whose first is still on keeps the blessing the first took off; a blessing of yours between them is the one the second takes", function()
  local function setup()
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-J1" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-J2" })
    local DU = member({ name = "Dunstan", surname = "Vale", class = "WARRIOR", level = 60, guid = "Player-1-J3" })
    local KE = member({ name = "Kestra", surname = "Moor", class = "WARRIOR", level = 60, guid = "Player-1-J4" })
    local c = client({ me = OR, group = { OR, RA, DU, KE }, spec = 184 })
    knowAll(c, "PALADIN", 60)
    load(c)
    tick(c, 12)
    return c, OR, RA
  end
  local function cast(c, who, id, n)
    fire(c, "UNIT_SPELLCAST_SENT", "player", who.name, "cast-r4-" .. n, id)
    fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-r4-" .. n, id)
  end
  local c, OR, RA = setup()
  local Hn, As = c.A.Hands, c.A.Assign
  assert(As.BlessingOf(OR.guid, "WARRIOR:melee") == "might", "the share-out: Might")
  RA.auras = { { id = 20217, src = "player", exp = c.clock + 3600, dur = 3600 } }
  fire(c, "UNIT_AURA", tokenOf(c, RA))
  tick(c, 4)
  assert(Hn.saw[RA.guid] and Hn.saw[RA.guid].key == "kings", "read: your Kings on Rask")
  -- Sacrifice takes the Kings off; a read out of the fight finds none of yours; a second Sacrifice while the first runs
  RA.auras = { { id = 20729, src = "player", exp = c.clock + 30, dur = 30 } }
  cast(c, RA, 20729, 1)
  fire(c, "UNIT_AURA", tokenOf(c, RA))
  tick(c, 5)
  assert(Hn.saw[RA.guid] and Hn.saw[RA.guid].key == nil, "the read found none of yours")
  tick(c, 5)
  cast(c, RA, 20729, 2)
  local card = c.A.Alerts.cards["hand:" .. RA.guid]
  assert(card and card.spec and card.spec.text == "Then bless with Kings again.", "the second Hand's line: " .. tostring(card and card.spec and card.spec.text))
  tick(c, 29)
  RA.auras = {}
  fire(c, "UNIT_AURA", tokenOf(c, RA))
  tick(c, 4)
  assert(Hn.pending[RA.guid] and Hn.pending[RA.guid].bless == "kings", "the restore: Kings, " .. tostring(Hn.pending[RA.guid] and Hn.pending[RA.guid].bless))
  local rb = c.env.CuteAurasRestore
  assert(rb:IsShown() and rb:GetAttribute("spell") == c.A.Spells.Best(c.A.Data.BLESS.kings, 60), "the click casts Kings: " .. tostring(rb:GetAttribute("spell")))
  -- your Might on them while a Hand is on (it took the Hand off), then Freedom while the first Hand's clock runs: Might
  local c2, OR2, RA2 = setup()
  local Hn2 = c2.A.Hands
  RA2.auras = { { id = 20217, src = "player", exp = c2.clock + 3600, dur = 3600 } }
  fire(c2, "UNIT_AURA", tokenOf(c2, RA2))
  tick(c2, 4)
  fight(c2, true)
  cast(c2, RA2, 20729, 3)
  tick(c2, 2)
  cast(c2, RA2, 25291, 4)
  tick(c2, 2)
  cast(c2, RA2, 1044, 5)
  tick(c2, 12)
  assert(Hn2.pending[RA2.guid] and Hn2.pending[RA2.guid].bless == "might", "the Might you gave between: " .. tostring(Hn2.pending[RA2.guid] and Hn2.pending[RA2.guid].bless))
  noErrors(c, "two Hands"); noErrors(c2, "a blessing between")
end)

test("review 4: in a fight the gold glow is only where the restore's blessing is: a member who lost your Kings, their share-out Might, glows in no list", function()
  local g = party5long()
  local c = g.c3
  local Hn, Al, D = c.A.Hands, c.A.Alerts, c.A.Data
  local rog = g.ROG.guid
  tick(c, 2)
  assert(c.A.Assign.BlessingOf(g.PAL.guid, c.A.Assign.Bucket(c.A.Roster.ByGUID(rog))) == "might", "the rogue's share-out: Might")
  -- your Kings on the rogue from before (an hour's, put on before anything here), read out of the fight
  g.ROG.auras = { { id = D.BLESS.kings.ranks[1], src = "player", exp = c.clock + 3000, dur = 3600 } }
  fire(c, "UNIT_AURA", tokenOf(c, g.ROG))
  tick(c, 4)
  assert(Hn.saw[rog] and Hn.saw[rog].key == "kings", "read: your Kings")
  fight(c, true)
  hand(c, g.ROG, 10278, 1)
  g.ROG.auras = {}
  tick(c, 11)
  assert(Hn.pending[rog] and Hn.pending[rog].bless == "kings", "the restore names the Kings")
  local r = Al.cards["restore:" .. rog]
  assert(r and r.spec.text == "Protection is over. Target them and give them Kings.", "no row: " .. tostring(r and r.spec.text))
  local list = {}
  for _, rec in ipairs(shown(c, "group")) do list[#list + 1] = icon(c, "group", rec.key) end
  assert(#list >= 2, "the paladin's icons")
  for _, b in ipairs(list) do
    assert(not b.glowTex:IsShown(), "no wash on " .. b.rec.key)
    for _, e in ipairs(b.rec.flyout or {}) do assert(not e.glow, "no glow in the list of " .. b.rec.key) end
  end
  assert(not Hn.Glowing(rog, "duty:bless:might") and Hn.Glowing(rog, "duty:bless:kings") and Hn.Glowing(rog), "glowing only where Kings is")
  -- the next read keeps it so
  c.A.Bar.Dirty("all"); tick(c, 2)
  for _, b in ipairs(list) do
    if b:IsShown() then
      assert(not b.glowTex:IsShown(), "no wash after a read on " .. b.rec.key)
      for _, e in ipairs(b.rec.flyout or {}) do assert(not e.glow, "no glow after a read in " .. b.rec.key) end
    end
  end
  -- a Hand on a member whose share-out is the blessing they lost: their row there glows, as before
  hand(c, g.WAR, 1044, 2)
  tick(c, 11)
  local war = g.WAR.guid
  local wk = Hn.pending[war] and Hn.pending[war].bless
  local lit = 0
  for _, b in ipairs(list) do
    if b:IsShown() and b.glowTex:IsShown() then lit = lit + 1; assert(b.rec.key == "duty:bless:" .. tostring(wk), "the warrior's list washes: " .. b.rec.key) end
  end
  assert(lit == 1, "one icon washed: " .. lit)
  noErrors(c, "the glow")
end)

test("review 4: a paladin whose hello says PallyPower runs there is asked for its SELF when nothing of theirs was heard: a newcomer, or the asker back from a crash, lists them", function()
  local function nREQ(c) return #ppOut(c, "REQ") end
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
  local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-0D", assigned = "TANK", leader = true })
  local group = { OR, RA, BR }
  local c1 = client({ me = OR, group = group, spec = 184, addons = PP_ADDON })
  knowAll(c1, "PALADIN", 60)
  load(c1)
  tickAll(12)
  -- Orren's PallyPower: warriors Might from Orren
  local OR_SELF = "SELF 607010nnnnnn@2nnnnnnnn"
  ppSay(OR, OR_SELF)
  tickAll(3)
  assert(c1.A.PallySync.pals[OR.guid], "Orren's own client lists them")
  tickAll(30)
  -- Tamsin, a paladin running Cute Auras alone, joins: the asker
  local TA = member({ name = "Tamsin", surname = "Reed", class = "PALADIN", level = 60, guid = "Player-1-0A" })
  group[#group + 1] = TA
  local c2 = client({ me = TA, group = group, spec = 184 })
  knowAll(c2, "PALADIN", 60)
  load(c2)
  for _, c in ipairs({ c1, c2 }) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
  tickAll(30)
  assert(c2.A.PallySync.IsAsker(), "Tamsin asks")
  assert(nREQ(c2) >= 1, "a REQ for Orren, whose hello says PallyPower runs there: " .. nREQ(c2))
  -- Orren's PallyPower answers by whisper (Tamsin leads nothing); Tamsin passes it on
  ppSay(OR, OR_SELF, TA)
  tickAll(4)
  assert(c2.A.PallySync.pals[OR.guid], "Tamsin lists Orren")
  for _, key in ipairs({ "WARRIOR:melee", "WARRIOR:tank" }) do
    for _, pal in ipairs({ OR, TA }) do
      local a, b = c1.A.Assign.BlessingOf(pal.guid, key), c2.A.Assign.BlessingOf(pal.guid, key)
      assert(a == b, key .. ": the two clients agree on " .. pal.name .. ": " .. tostring(a) .. " / " .. tostring(b))
    end
  end
  assert(c2.A.Assign.BlessingOf(OR.guid, "WARRIOR:melee") == "might" and c2.A.Assign.BlessingOf(TA.guid, "WARRIOR:melee") ~= "might", "Orren Might, Tamsin another")
  -- Tamsin's client crashes (no logout save) and comes back: asked again, listed again
  for i, x in ipairs(WORLD) do if x == c2 then table.remove(WORLD, i) break end end
  local o = {}
  for k, v in pairs(c2.o) do o[k] = v end
  o.db = nil
  local n = client(o)
  n.clock = c2.clock
  for id in pairs(c2.known) do n.known[id] = true end
  load(n)
  tickAll(30)
  assert(nREQ(n) >= 1, "back from the crash: a REQ")
  ppSay(OR, OR_SELF, TA)
  tickAll(4)
  assert(n.A.PallySync.pals[OR.guid] and n.A.Assign.BlessingOf(OR.guid, "WARRIOR:melee") == "might", "listed again")
  -- asked once: no REQ again for them while they stay listed
  local before = nREQ(n)
  tickAll(60)
  assert(nREQ(n) == before, "no more REQs: " .. nREQ(n) .. " after " .. before)
  noErrors(c1, "both addons"); noErrors(n, "the asker back")
end)

test("review 4: PallyPower on every Cute Auras client: the lowest of them passes a whispered SELF to the group, and sends no REQ", function()
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
  local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-0D", assigned = "TANK", leader = true })
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local group = { TA, OR, YS, BR, RA }
  local c1 = client({ me = OR, group = group, spec = 184, addons = PP_ADDON })
  local c3 = client({ me = BR, group = group, spec = 257, addons = PP_ADDON })
  knowAll(c1, "PALADIN", 60); knowAll(c3, "WARRIOR", 60)
  load(c1); load(c3)
  tickAll(12)
  assert(c1.A.PallySync.IsAsker() and not c3.A.PallySync.IsAsker(), "Orren, the lower GUID, passes whispers on")
  -- Ysolde's PallyPower answers Orren's PallyPower's REQ by whisper
  ppSay(YS, "SELF 607010nnnnnn@221333113", OR)
  tickAll(4)
  for _, c in ipairs({ c1, c3 }) do
    assert(c.A.PallySync.pals[YS.guid], c.o.me.name .. " lists Ysolde")
    assert(c.A.Assign.BlessingOf(YS.guid, "ROGUE:melee") == "might", c.o.me.name .. ": Ysolde's Might for rogues")
  end
  assert(c1.A.Assign.BlessingOf(OR.guid, "ROGUE:melee") ~= "might", "Orren gives the rogue another blessing")
  tickAll(60)
  assert(#ppOut(c1, "REQ") == 0 and #ppOut(c3, "REQ") == 0, "PallyPower there asks; Cute Auras sends nothing on PLPWR")
  -- a whisper to Brok, not the one who passes them on and long in the group: nothing passed (a newcomer passes on what
  -- its PallyPower's REQ as it joined brings it: review 5)
  ppSay(YS, "SELF 607010nnnnnn@221333113", BR)
  tickAll(2)
  assert((c3.A.PallySync.stats.relayed or 0) == 0, "Brok passes nothing on")
  noErrors(c1, "the PallyPower asker"); noErrors(c3, "the other")
end)

test("review 4: a leader's cell for one member (NASSIGN) follows them out of their bucket: the member left behind gets the class cell, the member keeps theirs where they are alone", function()
  local g = ppParty()
  ppSay(g.BR, "PASSIGN Orren Lightsworn@2nnnnnnnn")
  tickAll(3)
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
  tickAll(3)
  for _, c in ipairs(g.all) do
    assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "kings" and c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank") == "might", c.o.me.name .. ": Rask Kings, Brok Might")
  end
  -- the warriors swap roles: Rask tanks, Brok plays damage
  g.RA.assigned = "TANK"
  g.BR.assigned = nil
  g.c3.A.Char().role = "melee"
  for _, c in ipairs(g.all) do fire(c, "PLAYER_ROLES_ASSIGNED") end
  tickAll(12)
  for _, c in ipairs(g.all) do
    local As, R = c.A.Assign, c.A.Roster
    assert(As.Bucket(R.ByGUID(g.RA.guid)) == "WARRIOR:tank" and As.Bucket(R.ByGUID(g.BR.guid)) == "WARRIOR:melee", "swapped")
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings", c.o.me.name .. ": Rask still Kings, " .. tostring(As.BlessingOf(g.OR.guid, "WARRIOR:tank")))
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", c.o.me.name .. ": Brok the class cell, " .. tostring(As.BlessingOf(g.OR.guid, "WARRIOR:melee")))
  end
  local row = g.c1.A.PallySync.SelfText():match("@(%S+)$")
  assert(row:sub(1, 1) == "2", "Orren's SELF row: warriors Might, " .. row)
  -- a removal puts back the bucket it holds now
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 0")
  tickAll(3)
  for _, c in ipairs(g.all) do
    assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank") == "might" and c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", c.o.me.name .. ": both the class cell")
  end
  for _, x in ipairs(g.all) do noErrors(x, "a NASSIGN's member moved") end
end)

test("review 4: a leader's change to one member's cell (NASSIGN) once their bucket has grown puts back what it covered; the same cell again changes nothing", function()
  local g = ppParty()
  ppSay(g.BR, "PASSIGN Orren Lightsworn@2nnnnnnnn")
  tickAll(3)
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
  tickAll(3)
  assert(g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "kings", "Rask alone: Kings")
  -- Kerr, a warrior who deals damage, takes Ysolde's place: the melee warriors two
  local KE = member({ name = "Kerr", surname = "Bladeson", class = "WARRIOR", level = 60, guid = "Player-1-0F" })
  g.group[3] = KE
  for _, c in ipairs(g.all) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
  tickAll(10)
  assert(#g.c1.A.Assign.buckets["WARRIOR:melee"] == 2, "two in the bucket")
  assert(g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "kings", "the cell stays as it was")
  -- the same cell again: nothing
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
  tickAll(3)
  assert(g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "kings", "the same: nothing changes")
  -- the leader switches Rask to Might in PallyPower: the bucket back to the class cell, Might
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 2")
  tickAll(3)
  for _, c in ipairs(g.all) do
    local ov = ovOf(c, g.OR.guid, "WARRIOR:melee")
    assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "might", c.o.me.name .. ": Might, " .. tostring(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee")))
    assert(ov and ov.key == "might" and ov.pp, c.o.me.name .. ": the leader's class cell, marked pp")
  end
  -- a later class ASSIGN reaches the bucket again
  ppSay(g.BR, "ASSIGN Orren Lightsworn 1 1")
  tickAll(3)
  assert(g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee") == "wisdom", "the class cell reaches it: " .. tostring(g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:melee")))
  for _, x in ipairs(g.all) do noErrors(x, "a NASSIGN in a grown bucket") end
end)

test("review 4: a leader's 0 for a class then a CLEAR: every cell of yours a leader set is Cute Auras' own again, and your casts teach it", function()
  local g = ppParty()
  local As = g.c1.A.Assign
  local me = g.OR.guid
  ppSay(g.BR, "ASSIGN Orren Lightsworn 1 3")
  tickAll(3)
  ppSay(g.BR, "ASSIGN Orren Lightsworn 1 0")
  tickAll(3)
  local ov = ovOf(g.c1, me, "WARRIOR:melee")
  assert(ov and ov.clear and ov.pp, "the leader's 0: a clear, marked pp")
  ppSay(g.BR, "CLEAR")
  tickAll(3)
  for _, bk in ipairs({ "WARRIOR:melee", "WARRIOR:tank" }) do
    local o = ovOf(g.c1, me, bk)
    assert(o and o.clear and not o.pp, bk .. ": a plain clear after the CLEAR")
    for _, c in ipairs(g.all) do
      local x = ovOf(c, me, bk)
      assert(x and x.clear and not x.pp, c.o.me.name .. " has it plain too: " .. bk)
    end
  end
  assert(As.Teach("WARRIOR:melee", "kings"), "your casts teach the warriors' cell again")
  for _, x in ipairs(g.all) do noErrors(x, "a 0 then a CLEAR") end
end)

test("review 4: a premade in a battleground speaks where the battleground's raid hears it: our messages and PallyPower's on INSTANCE_CHAT, as PallyPower speaks there", function()
  local g = ppParty()
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  for _, c in ipairs(g.all) do c.instGroup = true; c.instance = "pvp" end
  local from = {}
  for i, c in ipairs(g.all) do from[i] = #c.sent end
  for _, c in ipairs(g.all) do c.A.Comm.GivesChanged() end
  -- Orren speaks to PallyPower on a REQ
  ppSay(g.YS, "REQ")
  tickAll(8)
  local n = 0
  for i, c in ipairs(g.all) do
    assert(c.A.Comm.Channel() == "INSTANCE_CHAT", c.o.me.name .. ": " .. tostring(c.A.Comm.Channel()))
    for k = from[i] + 1, #c.sent do
      local s = c.sent[k]
      n = n + 1
      assert(s.ch == "INSTANCE_CHAT", c.o.me.name .. " sent " .. s.msg:sub(1, 12) .. " on " .. tostring(s.ch))
    end
  end
  assert(n >= 3 and #ppOut(g.c1, "SELF") >= 1, "hellos and Orren's SELF went: " .. n)
  -- out of the battleground's instance, a home group: its own channel again
  for _, c in ipairs(g.all) do c.instGroup = false; c.instance = nil end
  assert(g.c1.A.Comm.Channel() == "PARTY", "home: " .. tostring(g.c1.A.Comm.Channel()))
  -- an instance group alone, outside its instance (a queue's group): INSTANCE_CHAT, as before
  local was = g.c1.env.IsInGroup
  g.c1.env.IsInGroup = function(cat) if cat == 2 then return true end return false end
  assert(g.c1.A.Comm.Channel() == "INSTANCE_CHAT", "an instance group alone: " .. tostring(g.c1.A.Comm.Channel()))
  g.c1.env.IsInGroup = was
  for _, x in ipairs(g.all) do noErrors(x, "a premade in a battleground") end
end)

test("review 4: in a raid each rebuff watcher names its member as the raid's roster does: a member with a surname keeps their slot past a fight's end and a roster update, and their combat res brings the card", function()
  local list = {}
  local who = { { "Ysolde", "Ashbrook", "PRIEST" }, { "Brok", "Ironhide", "WARRIOR" }, { "Mirel", "Dawnfield", "MAGE" }, { "Tamsin", "Reed", "ROGUE" } }
  for i, x in ipairs(who) do list[i] = member({ name = x[1], surname = x[2], class = x[3], level = 60, guid = string.format("Player-1-%02d", i) }) end
  local c = client({ me = list[1], group = list, raid = true })
  knowAll(c, "PRIEST", 60)
  load(c)
  tick(c, 12)
  local Rb, rb = c.A.Rebuff, c.env.CuteAurasRebuff
  assert(Rb.slots == 3, "three owed: " .. Rb.slots)
  -- a fight and its end (the slots set again), then a roster update
  fight(c, true); tick(c, 2); fight(c, false); tick(c, 2)
  fire(c, "GROUP_ROSTER_UPDATE"); tick(c, 2)
  for i = 1, Rb.slots do assert(Rb.handler:GetAttribute("u" .. i), "slot " .. i .. " keeps its unit") end
  local rog = list[4]
  fight(c, true)
  rog.dead = true; tick(c, 1); rog.dead = false; tick(c, 1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == rog, "the rogue's card: " .. tostring(rb:GetAttribute("unit")))
  -- in a party, the same members' slots kept too (the header joins the surname there, as we do)
  local plist = {}
  for i, x in ipairs(who) do plist[i] = member({ name = x[1], surname = x[2], class = x[3], level = 60, guid = string.format("Player-1-%02d", i) }) end
  local c2 = client({ me = plist[1], group = plist })
  knowAll(c2, "PRIEST", 60)
  load(c2)
  tick(c2, 12)
  fight(c2, true); tick(c2, 2); fight(c2, false); tick(c2, 2)
  fire(c2, "GROUP_ROSTER_UPDATE"); tick(c2, 2)
  local Rb2 = c2.A.Rebuff
  for i = 1, Rb2.slots do assert(Rb2.handler:GetAttribute("u" .. i), "party slot " .. i .. " keeps its unit") end
  fight(c2, true)
  plist[4].dead = true; tick(c2, 1); plist[4].dead = false; tick(c2, 1)
  assert(c2.env.CuteAurasRebuff:IsShown(), "the party rogue's card")
  noErrors(c, "a raid with surnames"); noErrors(c2, "a party with surnames")
end)

test("review 4: Well Fed's World chip turns the camp's Eat off and on at once, and so does Back to the defaults", function()
  local c = consumer({ class = "WARRIOR", role = "melee", food = true })
  tick(c, 1)
  assert(find(shown(c, "camp"), "eat"), "the camp's Eat in the open world: " .. keysOf(shown(c, "camp")))
  local page = cnPage(c)
  local row = cnRow(page, "fed")
  assert(row.chips[1].key == "solo" and row.chips[1].on, "World lit")
  c.click(row.chips[1])
  tick(c, 1)
  assert(not c.A.Consume.Asks("fed", "solo") and not find(shown(c, "camp"), "eat"), "World off: no Eat at once: " .. keysOf(shown(c, "camp")))
  c.click(cnRow(page, "fed").chips[1])
  tick(c, 1)
  assert(find(shown(c, "camp"), "eat"), "World on: the Eat back at once")
  c.A.Consume.SetChoice("fed", "solo", false); tick(c, 1)
  assert(not find(shown(c, "camp"), "eat"), "off from the menu")
  c.A.Consume.ClearChoice("fed"); tick(c, 1)
  assert(find(shown(c, "camp"), "eat"), "back to the defaults: the Eat back")
  noErrors(c, "Well Fed's World chip")
end)

test("review 4: the tab reads On you while a chosen potion's buff is up through its cooldown, and while your last flask's buff is up", function()
  local c, me = consumer({ class = "WARRIOR", role = "tank", items = { CN.stone, CN.heal, CN.titans } })
  goTo(c, "raid")
  local Cn = c.A.Consume
  Cn.SetChoice(13455, "raid", true)
  Cn.SetChoice(13510, "raid", true)
  tick(c, 1)
  for _, b in ipairs(c.bags) do if b.id == 13455 or b.id == 13446 then b.cdStart, b.cd = c.clock, 120 end end
  auraOn(c, me, 17540, 120)
  fire(c, "BAG_UPDATE_COOLDOWN"); tick(c, 1)
  local page = cnPage(c)
  local st = cnRow(page, 13455).state
  assert(st.__text:find("^On you %d") and sameColor(st.__textColor, c.A.Look.C.GOOD), "the potion's buff on you: " .. st.__text)
  -- its buff gone, the cooldown still running: Cooldown
  auraOff(c, me, 17540)
  assert(cnRow(page, 13455).state.__text:find("^Cooldown %d"), "no buff, cooling: " .. cnRow(page, 13455).state.__text)
  -- the last flask drunk: none in your bags, its two hours on you
  for i = #c.bags, 1, -1 do if c.bags[i].id == 13510 then table.remove(c.bags, i) end end
  fire(c, "BAG_UPDATE_DELAYED")
  auraOn(c, me, 17626, 7000)
  local fr = cnRow(page, 13510)
  assert(fr and fr.state.__text:find("^On you"), "the last flask on you: " .. tostring(fr and fr.state.__text))
  -- gone: None left
  auraOff(c, me, 17626)
  assert(cnRow(page, 13510).state.__text == "None left", cnRow(page, 13510).state.__text)
  noErrors(c, "On you first")
end)

test("review 4: a chip's tooltip says what the next click does once it is clicked, the cursor still on it", function()
  local c = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose } })
  goTo(c, "party")
  local page = cnPage(c)
  local row = cnRow(page, 13452)
  local chip = row.chips[3]
  assert(chip.key == "dungeon" and chip.on, "5-man lit")
  local before = table.concat(tipOf(c, chip), " | ")
  assert(before:find("Click: not there", 1, true), before)
  c.click(chip)
  tick(c, 0.5)
  local after = table.concat(c.env.GameTooltip.lines, " | ")
  assert(not chip.on and after == "5-man | Click: ask for it in 5-man dungeons when its buff is missing.", "the new words: " .. after)
  -- Never
  local nv = row.never
  tipOf(c, nv)
  c.click(nv)
  tick(c, 0.5)
  assert(nv.on and table.concat(c.env.GameTooltip.lines, " | ") == "Never | Never asked. Click to ask for it again.", table.concat(c.env.GameTooltip.lines, " | "))
  c.click(nv); tick(c, 0.5)
  -- a kind's default
  local head
  for _, h in ipairs(page.heads) do if h.name:IsShown() and h.name.__text == "Elixirs" then head = h end end
  local dc = head.chips[4]
  local was = dc.on
  tipOf(c, dc)
  c.click(dc)
  tick(c, 0.5)
  assert(dc.on ~= was and c.env.GameTooltip.lines[2] == dc.tip, "the default's new words: " .. tostring(c.env.GameTooltip.lines[2]))
  noErrors(c, "a chip's tooltip")
end)

test("review 4: a Never chosen from the bar's right-click shows on the open Consumables tab at once", function()
  local c = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose } })
  goTo(c, "party")
  local page = cnPage(c)
  local row = cnRow(page, 13452)
  assert(row.state.__text == "Missing" and not row.never.on, "asked: " .. row.state.__text)
  local b = icon(c, "own", "consume13452")
  c.click(b, "RightButton")
  for _, e in ipairs(c.menus[#c.menus]) do if e.text and e.text:find("^Never") then e.fn() end end
  tick(c, 1)
  assert(not find(shown(c, "mine"), "consume13452"), "off the bar")
  -- (the row as it stands, no Sync of the test's own)
  assert(row.id == 13452 and row.state.__text == "Never" and row.never.on and not row.chips[3].on, "the tab says Never: " .. row.state.__text)
  noErrors(c, "a bar Never")
end)

test("review 4: the Consumables tab says when Settings keep the bar from asking: Your buffs and weapon off, Nothing in dungeons, Show the bar off, the camp off for the open world's Eat", function()
  local c = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose }, food = true })
  goTo(c, "party")
  local page = cnPage(c)
  local s = c.A.Settings()
  local function state(id) return cnRow(page, id).state.__text end
  assert(state(13452) == "Missing" and state("fed") == "Missing", "asked")
  s.mine = false; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(consumeKeys(c) == "", "the bar asks nothing: " .. consumeKeys(c))
  assert(state(13452) == "Off in Settings" and state("fed") == "Off in Settings", "the rows: " .. state(13452) .. " / " .. state("fed"))
  assert(page.here.__text == "Here: 5-man. Your buffs and weapon is off in Settings: only Before the pull asks.", page.here.__text)
  FITS(page.here, "the mine-off line")
  assert(page.list.__alpha == 1, "Before the pull still asks: the list not greyed")
  s.pull = false; page:Sync()
  assert(page.here.__text == "Here: 5-man. Your buffs and weapon and Before the pull are off in Settings: nothing is asked.", page.here.__text)
  FITS(page.here, "both off")
  s.mine, s.pull = true, true
  s.instance = "none"; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(state(13452) == "Off in Settings", state(13452))
  assert(page.here.__text == "Here: 5-man. In dungeons and raids is Nothing in Settings: nothing is asked here.", page.here.__text)
  FITS(page.here, "the Nothing line")
  assert(page.list.__alpha == 0.45, "nothing asked: greyed")
  s.instance = "buffs"
  s.on = false; page:Sync()
  assert(page.here.__text == "Show the bar is off in Settings: nothing is asked." and state(13452) == "Off in Settings", page.here.__text)
  FITS(page.here, "the bar off")
  s.on = true; page:Sync()
  assert(state(13452) == "Missing", "all on again: " .. state(13452))
  -- the open world: the camp off, Well Fed's Eat off there; the elixir asked nowhere in the world
  goTo(c, nil)
  s.mine = false; page:Sync()
  assert(page.here.__text == "Here: World. Your buffs and weapon is off in Settings: only Before the pull and the camp's Eat ask.", page.here.__text)
  FITS(page.here, "the world's line")
  assert(state("fed") == "Missing", "the camp's Eat still asks: " .. state("fed"))
  s.mine = true
  s.camp = false; c.A.Bar.Dirty("all"); tick(c, 1)
  assert(state("fed") == "Off in Settings", "the camp's Eat off: " .. state("fed"))
  s.camp = true; page:Sync()
  assert(state("fed") == "Missing", state("fed"))
  for _, w in ipairs({ "Off in Settings", "Level 60", "Can't use" }) do assert(TEXT_WIDTH(w, 11) <= 90, "a state's word: " .. w) end
  noErrors(c, "Settings say")
end)

test("review 4: with two poisons asked in one place the main hand gets its own habit's, not the one put on the off hand last; a choice still comes first", function()
  local instant = { 8928, "Instant Poison VI", 0, 8, 11340 }
  local deadly = { 20844, "Deadly Poison V", 0, 8, 25351 }
  local c = consumer({ class = "ROGUE", role = "melee", items = { instant, deadly } })
  c.items[5005] = { name = "Plain Dagger", equipLoc = "INVTYPE_WEAPONMAINHAND" }
  c.items[5006] = { name = "Plain Sword", equipLoc = "INVTYPE_WEAPONOFFHAND" }
  c.equipped[16] = 5005; c.equipped[17] = 5006
  c.A.Char().weapon = { [5005] = { item = 8928, hits = 5 }, [5006] = { item = 20844, hits = 5 } }
  goTo(c, "raid")
  local rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 8928, "the habit alone: Instant")
  c.A.Consume.SetChoice(8928, "raid", true)
  c.A.Consume.SetChoice(20844, "raid", true)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-p1", 11340); tick(c, 5)
  fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-p2", 25351); tick(c, 2)
  c.A.Bar.Dirty("all"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 8928, "both ticked: the main hand's own, Instant: " .. tostring(rec and rec.click.item))
  -- the Weapon kind's default on for raids, no choices: the same
  c.A.Consume.ClearChoice(8928); c.A.Consume.ClearChoice(20844)
  c.A.Consume.SetKindDefault("weapon", "raid", true)
  c.A.Bar.Dirty("all"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 8928, "by default: Instant: " .. tostring(rec and rec.click.item))
  -- Deadly alone chosen for raids: the choice wins over the habit
  c.A.Consume.SetChoice(20844, "raid", true)
  c.A.Bar.Dirty("all"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 20844, "a choice first: " .. tostring(rec and rec.click.item))
  noErrors(c, "two poisons")
end)

test("review 4: before the pull an item chosen for here that never counted is not asked while its own buff has 3 minutes or more; under that its countdown", function()
  local wb = { 5996, "Elixir of Water Breathing", 0, 2, 7178 }
  local c, me = consumer({ class = "WARRIOR", role = "tank", items = { wb } })
  c.A.Consume.SetChoice(5996, "raid", true)
  goTo(c, "raid")
  assert(not c.A.Consume.Counts(5996), "never counted")
  auraOn(c, me, 7178, 1700)
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(not find(shown(c, "pull"), "flask5996"), "its buff on for 28 minutes: not asked: " .. pullKeys(c))
  fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
  auraOn(c, me, 7178, 100)
  fire(c, "READY_CHECK"); tick(c, 4)
  local r = find(shown(c, "pull"), "flask5996")
  assert(r and r.status == "warn", "under 3 minutes: its countdown: " .. pullKeys(c))
  fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
  auraOff(c, me, 7178)
  fire(c, "READY_CHECK"); tick(c, 4)
  r = find(shown(c, "pull"), "flask5996")
  assert(r and r.word == "Drink", "gone: asked plainly")
  noErrors(c, "a chosen item's own buff")
end)

test("review 4: a consumable you can't use yet is never asked, on the bar or before the pull; the tab says its level", function()
  local c, me = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose, CN.giants } })
  me.level = 40
  c.items[13452].minLevel = 46
  c.items[13452].usable = false
  fire(c, "PLAYER_LEVEL_UP"); tick(c, 1)
  goTo(c, "party")
  c.A.Bar.Dirty("all"); tick(c, 1)
  assert(not find(shown(c, "mine"), "consume13452"), "the Mongoose above your level: not asked: " .. consumeKeys(c))
  assert(find(shown(c, "mine"), "consume9206"), "Giants asked: " .. consumeKeys(c))
  local page = cnPage(c)
  assert(cnRow(page, 13452).state.__text == "Level 46", cnRow(page, 13452).state.__text)
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(not find(shown(c, "pull"), "flask13452"), "nor before the pull: " .. pullKeys(c))
  fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
  -- the game's own no (a class or race line): Can't use
  c.items[9206].usable = false
  c.A.Bar.Dirty("all"); tick(c, 1)
  assert(not find(shown(c, "mine"), "consume9206"), "Giants not usable: not asked")
  assert(cnRow(page, 9206).state.__text == "Can't use", cnRow(page, 9206).state.__text)
  -- your level reached: asked
  me.level = 46
  c.items[13452].usable = nil
  fire(c, "PLAYER_LEVEL_UP"); tick(c, 1)
  c.A.Bar.Dirty("all"); tick(c, 1)
  assert(find(shown(c, "mine"), "consume13452"), "at 46: asked: " .. consumeKeys(c))
  noErrors(c, "can't use yet")
end)

test("review 4: the camp's Eat right-click names what its Never hides: Well Fed", function()
  local c = consumer({ class = "PALADIN", role = "tank", food = true })
  tick(c, 1)
  local b = icon(c, "own", "eat")
  assert(b and b.rec and b.rec.key == "eat", "the camp's Eat")
  c.click(b, "RightButton")
  local label
  for _, e in ipairs(c.menus[#c.menus] or {}) do if e.text and e.text:find("^Never") then label = e.text end end
  assert(label == "Never: Well Fed", "the Never's words: " .. tostring(label))
  noErrors(c, "the camp's Eat Never")
end)

----------------------------------------------------------------------------
-- review round 5 (0.2.3)
----------------------------------------------------------------------------
-- a Consumables row as it reads now, without reading the page again (cnRow syncs it, which hides what the page's own
-- events left there)
local function cnRowNow(page, id)
  for _, r in ipairs(page.rows) do if r.id == id and r.name:IsShown() then return r end end
  return nil
end

test("review 5: the open Consumables tab follows your rest: an inn's rest area with no zone change says In town, and out of it again", function()
  local c = consumer({ class = "PALADIN", role = "tank", food = true, items = { CN.mongoose } })
  goTo(c, nil)
  local page = cnPage(c)
  page:Sync()
  tick(c, 2)
  assert(cnRowNow(page, "fed").state.__text == "Missing", "not fed in the world: " .. cnRowNow(page, "fed").state.__text)
  assert(not page.timed, "nothing ticks")
  -- the inn's rest area: no zone event, only the rest
  c.resting = true; fire(c, "PLAYER_UPDATE_RESTING"); tick(c, 2)
  assert(cnRowNow(page, "fed").state.__text == "In town", "resting: " .. cnRowNow(page, "fed").state.__text)
  assert(page.here.__text:find("in a city or inn", 1, true), page.here.__text)
  c.resting = false; fire(c, "PLAYER_UPDATE_RESTING"); tick(c, 2)
  assert(cnRowNow(page, "fed").state.__text == "Missing", "out again: " .. cnRowNow(page, "fed").state.__text)
  assert(page.here.__text:find("Your role", 1, true), page.here.__text)
  noErrors(c, "the rest area")
end)

test("review 5: Biome gear's defaults say what they rule (every piece with no choice of its own) and what a click does, on and off; a piece's own toggle too", function()
  local c = client({ me = member({ name = "Frostling", class = "MAGE", level = 60 }) })
  load(c)
  c.A.Window.Open("gear")
  local page = c.A.Window.pages.gear
  page:Sync()
  local G = c.A.Gear
  local function tip(b) c.hover(b); return table.concat(c.env.GameTooltip.lines, " ") end
  local b = page.defaultChips[1]
  local on = tip(b)
  assert(not on:find("A new piece", 1, true), "no 'new piece': " .. on)
  assert(on:find("no choice of their own", 1, true) and on:find("Click: not there.", 1, true), "on: " .. on)
  c.click(b)
  assert(G.Settings().show.solo == false, "World off")
  tick(c, 0.5)
  local off = tip(b)
  assert(off:find("^World Click: show", 1) or off:find("Click: show", 1, true), "off: " .. off)
  assert(not off:find("swaps show on the bar in the open world", 1, true), "an off chip never says they show: " .. off)
  noErrors(c, "the gear defaults")
end)

test("review 5: with a PallyPower paladin in the group the Blessings tab still says a right-click gives a cell back to Cute Auras' choice; a cell set by hand says it too", function()
  local g = ppParty()
  ppSay(g.YS, YS_SELF)
  tickAll(2)
  local c1 = g.c1
  c1.A.Window.Open("blessings")
  local p = c1.A.Window.pages.blessings
  p:Sync()
  FITS(p.title, "the title")
  assert(p.title.__text:find("right-click for Cute Auras' choice", 1, true), p.title.__text)
  -- Orren sets their rogue cell by hand: its tooltip names the right-click
  c1.A.Assign.Set(g.OR.guid, "ROGUE:melee", "wisdom")
  tickAll(1)
  p:Sync()
  c1.hover(gridCell(c1, g.OR.guid, "ROGUE:melee"))
  local lines = table.concat(c1.env.GameTooltip.lines, " | ")
  assert(lines:find("Set by hand.", 1, true) and lines:find("Right-click: Cute Auras' choice.", 1, true), lines)
  -- a leader who is no paladin: the cell's tooltip says it (their title has no room)
  local c3 = g.c3
  c3.A.Window.Open("blessings")
  local p3 = c3.A.Window.pages.blessings
  p3:Sync()
  FITS(p3.title, "the leader's title")
  c3.hover(gridCell(c3, g.OR.guid, "ROGUE:melee"))
  lines = table.concat(c3.env.GameTooltip.lines, " | ")
  assert(lines:find("Right-click: Cute Auras' choice.", 1, true), "the leader: " .. lines)
  -- a cell of Cute Auras' choice says nothing of a right-click
  c1.hover(gridCell(c1, g.OR.guid, "WARRIOR:melee"))
  lines = table.concat(c1.env.GameTooltip.lines, " | ")
  assert(lines:find("Cute Auras' choice.", 1, true) and not lines:find("Right-click", 1, true), lines)
  for _, x in ipairs(g.all) do noErrors(x, "the right-click hint") end
end)

test("review 5: the open Consumables tab after a fight reads your auras once the bar has: an elixir drunk in the fight reads On you, never Missing from before the pull", function()
  local c, me = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose } })
  goTo(c, "party")
  local page = cnPage(c)
  page:Sync()
  tick(c, 1)
  assert(cnRowNow(page, 13452).state.__text == "Missing", "before the pull: " .. cnRowNow(page, 13452).state.__text)
  fight(c, true); tick(c, 2)
  assert(cnRowNow(page, 13452).state.__text == "In a fight", "in it: " .. cnRowNow(page, 13452).state.__text)
  -- the elixir drunk in the fight
  me.auras[#me.auras + 1] = { id = 17538, src = "player", exp = c.clock + 3600, dur = 3600 }
  fire(c, "UNIT_AURA", "player"); tick(c, 5)
  local refreshes = c.A.Bar.refreshes
  fight(c, false)
  -- (each half second: never Missing once the fight is over; On you once the bar has read)
  for _ = 1, 8 do
    tick(c, 0.5)
    local w = cnRowNow(page, 13452).state.__text
    assert(w ~= "Missing", "after the fight the tab says Missing for an elixir on you")
  end
  assert(c.A.Bar.refreshes > refreshes, "the bar read again")
  tick(c, 10)
  local w = cnRowNow(page, 13452).state.__text
  assert(w:find("^On you"), "14 s on: " .. w)
  assert(not find(shown(c, "mine"), "consume13452"), "the bar asks nothing")
  noErrors(c, "after the fight")
end)

test("review 5: a potion habit greyed on the potions' shared cooldown is not a reminder ignored: its time waiting never counts toward quiet", function()
  local c = consumer({ class = "WARRIOR", role = "tank", items = { CN.stone, CN.heal } })
  local h = c.A.Char().consume
  h[13455] = { hits = 2, miss = 0, at = 100, spell = 17540 }
  goTo(c, "party")
  assert(find(shown(c, "mine"), "consume13455"), "asked: " .. consumeKeys(c))
  -- a healing potion every two minutes: the shared cooldown never ends, 32 minutes of it
  for _ = 1, 16 do
    for _, b in ipairs(c.bags) do if b.id == 13455 or b.id == 13446 then b.cdStart, b.cd = c.clock, 120 end end
    fire(c, "BAG_UPDATE_COOLDOWN"); tick(c, 120)
    local rec = find(shown(c, "mine"), "consume13455")
    assert(rec and rec.lit == false, "shown waiting")
  end
  assert(h[13455] and (h[13455].miss or 0) == 0, "no miss counted: " .. tostring(h[13455] and h[13455].miss))
  assert(not (c.A.Char().consumeQuiet and c.A.Char().consumeQuiet[13455]), "not quiet")
  -- its cooldown over, its time lit counts as before: 600 s on screen unused is one miss
  for _, b in ipairs(c.bags) do b.cdStart, b.cd = nil, nil end
  fire(c, "BAG_UPDATE_COOLDOWN"); tick(c, 2)
  assert(find(shown(c, "mine"), "consume13455").lit, "lit")
  tick(c, 605); c.A.Bar.Dirty("all"); tick(c, 1)
  assert(h[13455] and h[13455].miss == 1, "a miss once lit 600 s: " .. tostring(h[13455] and h[13455].miss))
  noErrors(c, "the shared cooldown")
end)

test("review 5: a ready check in the open world shows one Eat, Before the pull's (your role's best food); the camp's Eat comes back after it", function()
  local c = consumer({ class = "WARRIOR", role = "melee", food = true, items = { CN.mongoose } })
  goTo(c, nil)
  assert(find(shown(c, "camp"), "eat"), "the camp's Eat in the world: " .. keysOf(shown(c, "camp")))
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(find(shown(c, "pull"), "pullfood"), "Before the pull's food: " .. pullKeys(c))
  assert(not find(shown(c, "camp"), "eat"), "one Eat, not two: camp " .. keysOf(shown(c, "camp")) .. ", pull " .. pullKeys(c))
  fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
  assert(not c.A.Bar.PullOn(), "the pull over")
  assert(find(shown(c, "camp"), "eat"), "the camp's Eat back: " .. keysOf(shown(c, "camp")))
  -- Before the pull off in Settings: the camp's Eat stays through a ready check
  c.A.Settings().pull = false
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(find(shown(c, "camp"), "eat"), "Before the pull off: the camp's Eat: " .. keysOf(shown(c, "camp")))
  noErrors(c, "one Eat")
end)

test("review 5: kin by the school a spell elixir raises: Greater Arcane Elixir stacks with Shadow Power, so a warlock is asked both; Arcane Elixir and the Greater one are one kin", function()
  local shadow = { 9264, "Elixir of Shadow Power", 0, 2, 11474 }
  local arcane = { 9155, "Arcane Elixir", 0, 2, 11390 }
  local c, me = consumer({ class = "WARLOCK", role = "caster", items = { CN.garcane, shadow, arcane } })
  goTo(c, "raid")
  local keys = consumeKeys(c)
  -- (one of Arcane Elixir and the Greater one, never both: they replace each other)
  local arc = (keys:find("consume13454", 1, true) and 1 or 0) + (keys:find("consume9155", 1, true) and 1 or 0)
  assert(arc == 1 and keys:find("consume9264", 1, true), "an arcane one and Shadow Power: " .. keys)
  auraOn(c, me, 17539)
  keys = consumeKeys(c)
  assert(keys:find("consume9264", 1, true), "Greater Arcane Elixir on: Shadow Power still asked: " .. keys)
  local page = cnPage(c)
  assert(cnRow(page, 9264).state.__text == "Missing", "Shadow Power's row: " .. cnRow(page, 9264).state.__text)
  assert(cnRow(page, 9155).state.__text == "One like it on", "Arcane Elixir's row: " .. cnRow(page, 9155).state.__text)
  fire(c, "READY_CHECK"); tick(c, 4)
  assert(find(shown(c, "pull"), "flask9264"), "before the pull: " .. pullKeys(c))
  -- what the row says it raises: the school's damage
  assert(cnRow(page, 9264).sub.__text:find("^Shadow damage"), cnRow(page, 9264).sub.__text)
  noErrors(c, "spell kin")
end)

test("review 5: the bar's weapon pick goes on the weapon in your main hand: a sharpening stone chosen for raids is never asked for a mace, whose own Weightstone habit still is; with a sword it is", function()
  local sharp = { 12404, "Dense Sharpening Stone", 0, 8, 16138 }
  local weight = { 12643, "Dense Weightstone", 0, 8, 16622 }
  local c = consumer({ class = "WARRIOR", role = "melee", items = { sharp, weight } })
  c.items[5007] = { name = "Plain Mace", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subID = 4 }
  c.items[5008] = { name = "Plain Sword", equipLoc = "INVTYPE_WEAPONMAINHAND", classID = 2, subID = 7 }
  c.equipped[16] = 5007
  c.A.Char().weapon = { [5007] = { item = 12643, hits = 4 } }
  goTo(c, "raid")
  local rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 12643, "the mace's habit: " .. tostring(rec and rec.click.item))
  -- the sharpening stone chosen for raids (for the sword they wield most nights)
  c.A.Consume.SetChoice(12404, "raid", true)
  c.A.Bar.Dirty("all"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 12643, "a mace takes no sharpening stone: " .. tostring(rec and rec.click.item) .. " " .. tostring(rec and rec.why))
  local page = cnPage(c)
  assert(cnRow(page, 12404).state.__text == "Wrong weapon", "its row with a mace: " .. cnRow(page, 12404).state.__text)
  FITS(cnRow(page, 12404).state, "the row's state")
  -- the sword in the main hand: the stone chosen for here
  c.equipped[16] = 5008
  fire(c, "PLAYER_EQUIPMENT_CHANGED", 16); tick(c, 1)
  c.A.Bar.Dirty("all"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 12404, "a sword: the sharpening stone: " .. tostring(rec and rec.click.item))
  assert(cnRow(page, 12404).state.__text == "Missing", "its row with a sword: " .. cnRow(page, 12404).state.__text)
  -- both stones asked for here by the kind's default, a mace with no habit: the Weightstone, whatever was used last
  c.A.Consume.ClearChoice(12404)
  c.A.Char().weapon = {}
  c.A.Consume.SetKindDefault("weapon", "raid", true)
  c.A.Char().consume[12404] = { hits = 0, at = 900 }
  c.equipped[16] = 5007
  fire(c, "PLAYER_EQUIPMENT_CHANGED", 16); tick(c, 1)
  c.A.Bar.Dirty("all"); tick(c, 1)
  rec = find(shown(c, "mine"), "weapon16")
  assert(rec and rec.click.item == 12643, "a bare mace, both asked: the Weightstone: " .. tostring(rec and rec.click.item))
  noErrors(c, "the weapon's kind")
end)

test("review 5: a Hand's restore for a member who died is over: no click icon names a corpse after a wipe, and no sound when you come back", function()
  local g = party5long()
  local c = g.c3
  local hb = c.env.CuteAurasRestore
  fight(c, true)
  hand(c, g.ROG, 1044, 1)
  -- the group wipes before Freedom ends: the rogue and you dead, the fight over
  g.ROG.dead = true; g.PAL.dead = true
  fight(c, false)
  tick(c, 12)
  assert(not (hb:IsShown() and hb.guid == g.ROG.guid), "no click icon for the dead rogue")
  -- you are raised at your corpse, the rogue still dead: no sound, no click icon
  local sounds = c.sounds or 0
  g.PAL.dead = false
  fire(c, "PLAYER_UNGHOST"); tick(c, 2)
  assert(not hb:IsShown(), "back: no click icon for a corpse")
  assert((c.sounds or 0) == sounds, "back: no sound for a corpse")
  -- the rogue back: their blessings gone with the death, the bar asks for them; no restore waits
  g.ROG.dead = false
  fire(c, "UNIT_HEALTH", tokenOf(c, g.ROG)); fire(c, "UNIT_AURA", tokenOf(c, g.ROG)); tick(c, 2)
  assert(not hb:IsShown() and not c.A.Hands.Glowing(g.ROG.guid), "no restore after the death")
  -- a member who dies out of a fight with a restore waiting: it ends
  hand(c, g.WAR, 1044, 2)
  tick(c, 12)
  assert(hb:IsShown() and hb.guid == g.WAR.guid, "the warrior's restore")
  g.WAR.dead = true
  fire(c, "UNIT_AURA", tokenOf(c, g.WAR)); tick(c, 2)
  assert(not hb:IsShown() and not c.A.Hands.Glowing(g.WAR.guid), "dead: the restore over")
  g.WAR.dead = false
  noErrors(c, "a restore for the dead")
end)

test("review 5: Show as switched in a fight while the rebuff shows: the art never lies over the rebuff, which keeps its look and place till the fight ends", function()
  -- (how far down a secure button reaches: the icon look's name under it, a card's own height, hung under the restore)
  local function bottomOf(c, f)
    local p = f.__points[1]
    local Al = c.A.Alerts
    local top = (p[2] == Al.Anchor()) and p[5] or -((p[2]:GetHeight() or 0) + Al.GAP)
    return top - (f.rowH or f.__h)
  end
  local function artTop(c)
    local hi
    for _, f in pairs(c.A.Alerts.cards) do
      local y = f.__points[1][5]
      if not hi or y > hi then hi = y end
    end
    return hi
  end
  -- Icons, then Cards in a fight
  local g = party5long()
  local c = g.c3
  local rb = c.env.CuteAurasRebuff
  c.A.Settings().alertLook = "icons"; c.A.Alerts.Restyle(); tick(c, 1)
  fight(c, true)
  hand(c, g.ROG, 1044, 1)
  g.WAR.dead = true; tick(c, 1); g.WAR.dead = false; tick(c, 1)
  assert(rb:IsShown(), "the rebuff for the warrior raised in the fight")
  c.A.Settings().alertLook = "normal"; c.A.Alerts.Restyle()
  assert(rb.__w == 36, "the rebuff keeps its icon till the fight ends")
  local top, low = artTop(c), bottomOf(c, rb)
  assert(top and top <= low - c.A.Alerts.GAP, "Cards: the art from " .. tostring(top) .. ", the rebuff down to " .. low)
  fight(c, false); tick(c, 3)
  noErrors(c, "icons to cards")
  -- Cards with the restore card up as the fight starts, then Icons in it
  WORLD = {}
  g = party5long()
  c = g.c3
  rb = c.env.CuteAurasRebuff
  c.A.Settings().alertLook = "normal"; c.A.Alerts.Restyle(); tick(c, 1)
  hand(c, g.ROG, 1044, 1)
  tick(c, 12)
  assert(c.env.CuteAurasRestore:IsShown(), "the restore card")
  fight(c, true)
  g.WAR.dead = true; tick(c, 1); g.WAR.dead = false; tick(c, 1)
  assert(rb:IsShown() and c.A.Rebuff.under ~= nil, "the rebuff card hung under the restore's place")
  hand(c, g.P2, 1044, 2)
  c.A.Settings().alertLook = "icons"; c.A.Alerts.Restyle()
  top, low = artTop(c), bottomOf(c, rb)
  assert(top and top <= low - c.A.Alerts.GAP, "Icons: the art row from " .. tostring(top) .. ", the rebuff card down to " .. low)
  fight(c, false); tick(c, 3)
  noErrors(c, "cards to icons")
end)

test("review 5: a /reload keeps that we spoke to PallyPower here: fallen silent before the empty SELF left, it leaves after the reload; silent after one, a REQ is answered with it", function()
  local EMPTY = "SELF nnnnnnnnnnnn@nnnnnnnnn"
  -- Orren unticks Blessings and reloads 3 s later, the empty SELF still waiting
  local g = ppParty()
  ppSay(g.YS, YS_SELF)
  tickAll(30)
  local selfs = ppOut(g.c1, "SELF")
  assert(#selfs >= 1 and selfs[#selfs].msg ~= EMPTY, "Orren spoke: " .. #selfs)
  g.c1.A.Settings().blessings = false
  g.c1.A.Comm.GivesChanged()
  tickAll(3)
  local c1 = reload(g.c1)
  load(c1)
  g.c1, g.all[1] = c1, c1
  tickAll(30)
  local after = ppOut(c1, "SELF")
  assert(#after >= 1 and after[#after].msg == EMPTY, "the empty SELF after the reload: " .. #after .. " " .. tostring(after[#after] and after[#after].msg))
  -- a REQ while silent: answered with it
  local n = #after
  ppSay(g.YS, "REQ")
  tickAll(10)
  after = ppOut(c1, "SELF")
  assert(#after == n + 1 and after[#after].msg == EMPTY, "a REQ answered: " .. (#after - n))
  for _, x in ipairs(g.all) do noErrors(x, "silent over a reload") end
end)

test("review 5: a /reload keeps that PallyPower was heard here, a leader alone on it: after the reload Blessings off sends the empty SELF, a REQ is answered, a Never changes the SELF", function()
  local EMPTY = "SELF nnnnnnnnnnnn@nnnnnnnnn"
  local g = ppParty()
  ppSay(g.BR, "REQ")
  tickAll(26)
  assert(#ppOut(g.c1, "SELF") >= 1, "Orren answered the leader")
  local c1 = reload(g.c1)
  load(c1)
  g.c1, g.all[1] = c1, c1
  tickAll(15)
  assert(c1.A.PallySync.heardAny, "PallyPower heard here, kept over the reload")
  -- a Never on Might: the row changes, the SELF follows
  local before = #ppOut(c1, "SELF")
  c1.A.Bar.SetNever("duty:bless:might", "Blessing of Might")
  tickAll(25)
  local list = ppOut(c1, "SELF")
  assert(#list > before and list[#list].msg == c1.A.PallySync.SelfText(), "the changed SELF sent: " .. (#list - before))
  -- Blessings off: the empty SELF
  c1.A.Settings().blessings = false
  c1.A.Comm.GivesChanged()
  tickAll(25)
  list = ppOut(c1, "SELF")
  assert(list[#list].msg == EMPTY, "the empty SELF: " .. list[#list].msg)
  for _, x in ipairs(g.all) do noErrors(x, "heard over a reload") end
end)

test("review 5: two premades enter one battleground: each says hello where the battleground hears it, so no paladin running Cute Auras is read as PallyPower and the blessings settle", function()
  local A1 = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local A2 = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local B1 = member({ name = "Kael", surname = "Dawn", class = "PALADIN", level = 60, guid = "Player-1-0F" })
  local B2 = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
  local gA, gB = { A1, A2 }, { B1, B2 }
  local cA1 = client({ me = A1, group = gA, spec = 253 })
  local cA2 = client({ me = A2, group = gA, spec = 184 })
  local cB1 = client({ me = B1, group = gB, spec = 184 })
  local cB2 = client({ me = B2, group = gB, spec = 26 })
  knowAll(cA1, "ROGUE", 60); knowAll(cA2, "PALADIN", 60); knowAll(cB1, "PALADIN", 60); knowAll(cB2, "WARRIOR", 60)
  local all = { cA1, cA2, cB1, cB2 }
  for _, c in ipairs(all) do load(c) end
  tickAll(12)
  -- the battleground: one raid of all four, an instance group inside its instance; each premade still its home group
  local bg = { A1, A2, B1, B2 }
  for _, c in ipairs(all) do c.o.group = bg; c.o.raid = true; c.instGroup = true; c.instance = "pvp"; seat(c) end
  for _, c in ipairs(all) do fire(c, "GROUP_ROSTER_UPDATE"); fire(c, "PLAYER_ENTERING_WORLD") end
  tickAll(30)
  for _, c in ipairs(all) do
    local n = 0
    for _ in pairs(c.A.Comm.peers) do n = n + 1 end
    assert(n == 3, c.o.me.name .. " hears the other three: " .. n)
    assert(next(c.A.PallySync.pals) == nil, c.o.me.name .. ": no paladin read as PallyPower")
    assert(#c.A.Assign.paladins == 2, c.o.me.name .. ": both paladins share out")
  end
  -- the share-out the same everywhere, one of each blessing on the rogue and the warrior, and no SELF on PLPWR
  for _, key in ipairs({ "ROGUE:melee", "WARRIOR:melee" }) do
    local o, k = cA2.A.Assign.BlessingOf(A2.guid, key), cA2.A.Assign.BlessingOf(B1.guid, key)
    assert(o and k and o ~= k, key .. ": one of each, " .. tostring(o) .. " / " .. tostring(k))
    for _, c in ipairs(all) do
      assert(c.A.Assign.BlessingOf(A2.guid, key) == o and c.A.Assign.BlessingOf(B1.guid, key) == k, c.o.me.name .. " agrees on " .. key)
    end
  end
  tickAll(60)
  assert(#ppOut(cA2) == 0 and #ppOut(cB1) == 0, "nothing on PLPWR: no PallyPower here")
  for _, c in ipairs(all) do noErrors(c, "two premades") end
end)

test("review 5: a paladin running both addons who turns Cute Auras' blessings off (or puts one on Never) keeps their PallyPower column in every share-out", function()
  local function party()
    local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
    local KA = member({ name = "Kael", surname = "Dawn", class = "PALADIN", level = 60, guid = "Player-1-0F" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E", leader = true })
    local group = { TA, OR, KA, RA }
    local c1 = client({ me = OR, group = group, spec = 184, addons = PP_ADDON })
    local c2 = client({ me = TA, group = group, spec = 253 })
    local c3 = client({ me = KA, group = group, spec = 184 })
    knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60); knowAll(c3, "PALADIN", 60)
    load(c1); load(c2); load(c3)
    tickAll(12)
    return { c1 = c1, c2 = c2, c3 = c3, OR = OR, KA = KA, all = { c1, c2, c3 } }
  end
  local function check(g, label)
    for _, c in ipairs(g.all) do
      local As = c.A.Assign
      local listed = false
      for _, p in ipairs(As.paladins) do if p.guid == g.OR.guid then listed = true end end
      assert(listed, label .. ", " .. c.o.me.name .. ": Orren's column in the share-out")
      for _, key in ipairs({ "ROGUE:melee", "WARRIOR:melee" }) do
        assert(As.BlessingOf(g.OR.guid, key) == "might", label .. ", " .. c.o.me.name .. ": Orren's PallyPower Might for " .. key .. ": " .. tostring(As.BlessingOf(g.OR.guid, key)))
        assert(As.BlessingOf(g.KA.guid, key) == "kings", label .. ", " .. c.o.me.name .. ": Kael Kings for " .. key .. ": " .. tostring(As.BlessingOf(g.KA.guid, key)))
        assert(As.Source(g.OR.guid, key) == "pp", label .. ": set in PallyPower")
      end
    end
  end
  -- Blessings shared out by Cute Auras off on Orren's client; their PallyPower gives everyone Might
  local g = party()
  g.c1.A.Settings().blessings = false
  g.c1.A.Comm.GivesChanged()
  tickAll(6)
  ppSay(g.OR, "SELF 607010nnnnnn@222222222")
  tickAll(6)
  check(g, "Blessings off")
  -- the rogue's reminder names Orren for Might
  local pg = g.c2.A.Assign.BlesserFor(g.c2.A.Roster.Me(), "might")
  assert(pg == g.OR.guid, "Tamsin's Might from Orren: " .. tostring(pg))
  -- Orren's own bar asks no blessing of Cute Auras' (its own are off), PallyPower casts them
  for _, d in ipairs(g.c1.A.Assign.duties) do assert(not d.bless, "Orren's client: no blessing duty: " .. d.key) end
  -- Orren's Blessings tab: their PallyPower's column, and why Cute Auras adds nothing to it
  g.c1.A.Window.Open("blessings")
  local bp = g.c1.A.Window.pages.blessings
  bp:Sync()
  FITS(bp.title, "Orren's title")
  assert(bp.title.__text == "Your PallyPower sets your column; Cute Auras fills none of it: Blessings shared out by Cute Auras is off.", bp.title.__text)
  assert(gridCell(g.c1, g.OR.guid, "ROGUE:melee"), "Orren's column drawn")
  for _, x in ipairs(g.all) do noErrors(x, "blessings off") end
  -- Blessings on, Might on Never in Cute Auras: PallyPower's Might cells still count
  WORLD = {}
  g = party()
  g.c1.A.Bar.SetNever("duty:bless:might", "Blessing of Might")
  tickAll(6)
  ppSay(g.OR, "SELF 607010nnnnnn@222222222")
  tickAll(6)
  check(g, "Might on Never")
  for _, x in ipairs(g.all) do noErrors(x, "a Never") end
end)

test("review 5: a leader's same cell for every member of a shared bucket (NASSIGN for both warrior tanks) is that bucket's for your column too, as for a PallyPower paladin; one changed or removed, the class cell again", function()
  local g = ppParty()
  ppSay(g.BR, "PASSIGN Orren Lightsworn@2nnnnnnnn")
  tickAll(3)
  g.RA.assigned = "TANK"
  for _, c in ipairs(g.all) do fire(c, "PLAYER_ROLES_ASSIGNED") end
  tickAll(3)
  assert(#g.c1.A.Assign.buckets["WARRIOR:tank"] == 2, "two warrior tanks")
  local function tank() return g.c1.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank") end
  local function agree(want, label)
    for _, c in ipairs(g.all) do
      local got = c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank")
      assert(got == want, label .. ", " .. c.o.me.name .. ": Orren's tanks " .. tostring(got) .. ", not " .. want)
    end
  end
  agree("might", "the class cell")
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 3@Orren_Lightsworn 1 Rask_Stonefist 3")
  tickAll(3)
  agree("kings", "Kings for both tanks")
  -- one at a time: the first waits, the second makes it the bucket's
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 0")
  tickAll(3)
  agree("might", "Rask's removed")
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
  tickAll(3)
  agree("kings", "Rask's again")
  -- one changed: they differ, the class cell
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 1")
  tickAll(3)
  agree("might", "Rask's Wisdom")
  ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
  tickAll(3)
  agree("kings", "Rask's Kings again")
  -- Brok leaves the group: Rask alone in the bucket keeps their own Kings
  for i, m in ipairs(g.group) do if m == g.BR then table.remove(g.group, i) break end end
  for _, c in ipairs(g.all) do if c.o.me ~= g.BR then seat(c); fire(c, "GROUP_ROSTER_UPDATE") end end
  for i, c in ipairs(g.all) do if c.o.me == g.BR then table.remove(g.all, i) break end end
  for i, x in ipairs(WORLD) do if x.o.me == g.BR then table.remove(WORLD, i) break end end
  tickAll(6)
  assert(#g.c1.A.Assign.buckets["WARRIOR:tank"] == 1, "Rask alone")
  agree("kings", "Brok gone, Rask's own")
  -- the same for Ysolde, PallyPower alone: one rule
  ppSay(g.YS, YS_SELF)
  tickAll(3)
  ppSay(g.YS, "NASSIGN Ysolde_Ashbrook 1 Rask_Stonefist 1")
  tickAll(3)
  assert(g.c1.A.Assign.BlessingOf(g.YS.guid, "WARRIOR:tank") == "wisdom", "Ysolde's tank")
  -- Orren's SELF row for warriors stays the class's (its largest bucket that is no member's own)
  local row = g.c1.A.PallySync.SelfText():match("@(%S+)$")
  assert(row:sub(1, 1) == "2", "warriors Might in Orren's SELF: " .. row)
  for _, x in ipairs(g.all) do noErrors(x, "a shared bucket's NASSIGN") end
end)

test("review 5: a member who turns Cute Auras off and goes back to PallyPower: their PallyPower SELF is theirs (no S1 before it), listed on every client; the asker is another; a live one's own SELF never is", function()
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-01" })
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local KA = member({ name = "Kael", surname = "Dawn", class = "PALADIN", level = 60, guid = "Player-1-0F" })
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E", leader = true })
  local group = { OR, TA, KA, RA }
  local c1 = client({ me = OR, group = group, spec = 184 })
  local c2 = client({ me = TA, group = group, spec = 253 })
  local c3 = client({ me = KA, group = group, spec = 184 })
  knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60); knowAll(c3, "PALADIN", 60)
  load(c1); load(c2); load(c3)
  tickAll(12)
  -- a live Orren speaking to PallyPower (Rask's PallyPower asks): their own SELF, many times, never listed
  for _ = 1, 3 do
    ppSay(RA, "REQ")
    tickAll(8)
  end
  assert(#ppOut(c1, "SELF") >= 3, "Orren answered: " .. #ppOut(c1, "SELF"))
  for _, c in ipairs({ c2, c3 }) do
    assert(not c.A.PallySync.pals[OR.guid], c.o.me.name .. ": Orren's own SELF never lists them")
    assert(c.A.PallySync.Asker() == OR.guid, "Orren, the lowest GUID, asks")
  end
  -- Orren disables Cute Auras and reloads: their client is gone, their PallyPower speaks
  for i, x in ipairs(WORLD) do if x == c1 then table.remove(WORLD, i) break end end
  ppSay(OR, "SELF 607010nnnnnn@333333333")
  tickAll(6)
  for _, c in ipairs({ c2, c3 }) do
    assert(c.A.PallySync.pals[OR.guid], c.o.me.name .. ": Orren's PallyPower listed")
    assert(c.A.PallySync.Asker() ~= OR.guid, c.o.me.name .. ": the asker is another now")
    for _, key in ipairs({ "ROGUE:melee", "WARRIOR:melee" }) do
      assert(c.A.Assign.BlessingOf(OR.guid, key) == "kings", c.o.me.name .. ": Orren's Kings for " .. key .. ": " .. tostring(c.A.Assign.BlessingOf(OR.guid, key)))
      assert(c.A.Assign.BlessingOf(KA.guid, key) == "might", c.o.me.name .. ": Kael's Might for " .. key .. ": " .. tostring(c.A.Assign.BlessingOf(KA.guid, key)))
    end
    assert(c.A.Assign.Source(OR.guid, "ROGUE:melee") == "pp", "set in PallyPower")
  end
  -- a full queue drops its oldest, never an S1 (its SELF behind it would read as PallyPower's)
  local Cm = c3.A.Comm
  local q = Cm.queue
  for k = #q, 1, -1 do q[k] = nil end
  c3.lockdown = true
  Cm.Send("S1|" .. KA.guid)
  Cm.Send("SELF 607010nnnnnn@nnnnnnnnn", "PLPWR")
  for k = 1, 30 do Cm.Send("O1|" .. KA.guid .. "|" .. KA.guid .. "|B" .. k .. "|kings|1") end
  assert(q[1].msg == "S1|" .. KA.guid and q[2].msg:find("^SELF "), "the S1 kept ahead of its SELF: " .. q[1].msg)
  for k = #q, 1, -1 do q[k] = nil end
  c3.lockdown = nil
  for _, c in ipairs({ c2, c3 }) do noErrors(c, "Cute Auras turned off") end
end)

test("review 5: a member whose old hello says Cute Auras alone sending what only PallyPower sends (a leader's PASSIGN) runs PallyPower: their hello is let go, the asker another", function()
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-01", leader = true })
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local group = { RA, TA, OR }
  local c1 = client({ me = RA, group = group, spec = 71 })
  local c2 = client({ me = TA, group = group, spec = 253 })
  local c3 = client({ me = OR, group = group, spec = 184 })
  knowAll(c1, "WARRIOR", 60); knowAll(c2, "ROGUE", 60); knowAll(c3, "PALADIN", 60)
  load(c1); load(c2); load(c3)
  tickAll(12)
  assert(c2.A.PallySync.Asker() == RA.guid, "Rask asks")
  -- Rask turns Cute Auras off and reloads; their PallyPower gives Orren's column Kings for warriors
  for i, x in ipairs(WORLD) do if x == c1 then table.remove(WORLD, i) break end end
  ppSay(RA, "PASSIGN Orren Lightsworn@3nnnnnnnn")
  tickAll(4)
  for _, c in ipairs({ c2, c3 }) do
    assert(c.A.Comm.peers[RA.guid] == nil, c.o.me.name .. ": Rask's old hello let go")
    assert(c.A.PallySync.Asker() ~= RA.guid, c.o.me.name .. ": the asker another")
    assert(c.A.Assign.BlessingOf(OR.guid, "WARRIOR:melee") == "kings", c.o.me.name .. ": the leader's Kings for Orren")
  end
  for _, c in ipairs({ c2, c3 }) do noErrors(c, "a leader on PallyPower") end
end)

test("review 5: PallyPower on every Cute Auras client: a newcomer passes on what PallyPower whispers to it, so it lists the PallyPower paladins already there and every client agrees", function()
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local YS = member({ name = "Ysolde", surname = "Ashbrook", class = "PALADIN", level = 60, guid = "Player-1-0C" })
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E", leader = true })
  local group = { TA, YS, RA }
  local c1 = client({ me = TA, group = group, spec = 253, addons = PP_ADDON })
  knowAll(c1, "ROGUE", 60)
  load(c1)
  tickAll(12)
  ppSay(YS, YS_SELF)
  tickAll(4)
  assert(c1.A.PallySync.pals[YS.guid], "Tamsin lists Ysolde")
  -- Orren, a paladin running both, joins; their PallyPower asks (REQ) and Ysolde's whispers its answer to Orren
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local c2 = client({ me = OR, spec = 184, addons = PP_ADDON })
  knowAll(c2, "PALADIN", 60)
  load(c2)
  tickAll(3)
  group[#group + 1] = OR
  c2.o.group = group
  for _, c in ipairs({ c1, c2 }) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
  tickAll(3)
  ppSay(YS, YS_SELF, OR)
  tickAll(10)
  assert(c2.A.PallySync.pals[YS.guid], "Orren lists Ysolde")
  for _, key in ipairs({ "ROGUE:melee", "WARRIOR:melee" }) do
    for _, pal in ipairs({ YS, OR }) do
      local a, b = c1.A.Assign.BlessingOf(pal.guid, key), c2.A.Assign.BlessingOf(pal.guid, key)
      assert(a == b, key .. ": the clients agree on " .. pal.name .. ": " .. tostring(a) .. " / " .. tostring(b))
    end
  end
  assert(c2.A.Assign.BlessingOf(OR.guid, "ROGUE:melee") ~= "might", "Orren never doubles Ysolde's Might")
  assert(#ppOut(c1, "REQ") == 0 and #ppOut(c2, "REQ") == 0, "Cute Auras sends no REQ: PallyPower there asks")
  -- long in the group, a whisper (its PallyPower's grid opened) is passed on by the asker alone
  tickAll(30)
  local n = c2.A.PallySync.stats.relayed or 0
  ppSay(YS, YS_SELF, OR)
  tickAll(4)
  assert((c2.A.PallySync.stats.relayed or 0) == n, "Orren, no newcomer now, passes nothing on")
  for _, c in ipairs({ c1, c2 }) do noErrors(c, "a newcomer on PallyPower") end
end)

test("review 5: PallyPower on every Cute Auras client: the last paladin running Cute Auras alone turns PallyPower on and reloads; every client lists them", function()
  local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
  local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
  local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E", leader = true })
  local group = { TA, OR, RA }
  local c1 = client({ me = TA, group = group, spec = 253, addons = PP_ADDON })
  local c2 = client({ me = OR, group = group, spec = 184 })
  knowAll(c1, "ROGUE", 60); knowAll(c2, "PALADIN", 60)
  load(c1); load(c2)
  tickAll(12)
  -- Orren turns PallyPower on and reloads: their PallyPower's SELF (SPELLS_CHANGED, 1 s) leaves before their hello (3 s)
  local n = reload(c2)
  n.o.addons = PP_ADDON; n.addons = PP_ADDON
  ppSay(OR, "SELF 607010nnnnnn@333333333")
  tickAll(1)
  load(n)
  tickAll(60)
  assert(c1.A.Comm.peers[OR.guid] and c1.A.Comm.peers[OR.guid].ppField == "pp", "Orren's new hello")
  assert(c1.A.PallySync.pals[OR.guid], "Tamsin lists Orren")
  assert(c1.A.Assign.BlessingOf(OR.guid, "ROGUE:melee") == "kings", "Orren's PallyPower Kings for rogues")
  for _, c in ipairs({ c1, n }) do noErrors(c, "PallyPower turned on") end
end)

----------------------------------------------------------------------------
-- review 6: Before the pull and a fight, Not now on it; your own PallyPower column over a reload in a fight; a
-- member's own cells kept while they are away; a second NASSIGN in a bucket; spell text not loaded yet; long names
----------------------------------------------------------------------------
do
  test("review 6: Before the pull never opens in a fight: a pull 2 s after the ready check, or a raid's entry read in a fight, asks for nothing after it; a check all answered at once ends it 10 s on", function()
    local c = consumer({ class = "WARRIOR", role = "melee", items = { CN.mongoose, CN.titans }, food = true })
    goTo(c, "raid")
    fire(c, "READY_CHECK"); tick(c, 1)
    fire(c, "READY_CHECK_FINISHED"); tick(c, 1)
    fight(c, true); tick(c, 3)
    assert(not c.A.Bar.PullOn(), "Before the pull never opens in the fight")
    fight(c, false); tick(c, 3)
    assert(not c.A.Bar.PullOn() and pullKeys(c) == "", "nothing asked after it: " .. pullKeys(c))
    tick(c, 20)
    assert(pullKeys(c) == "", "nor later: " .. pullKeys(c))
    -- (the raid's entry, a /reload in its fight: the 5 s start finds the fight on)
    fight(c, true)
    fire(c, "PLAYER_ENTERING_WORLD"); tick(c, 6)
    assert(not c.A.Bar.PullOn(), "none in the fight after the entry")
    fight(c, false); tick(c, 3)
    assert(not c.A.Bar.PullOn() and pullKeys(c) == "", "none after that fight: " .. pullKeys(c))
    -- a check all answered in 1 s, no fight: open from 3 s on, over 10 s after the finish, not at 45 s
    fire(c, "READY_CHECK"); tick(c, 1)
    fire(c, "READY_CHECK_FINISHED"); tick(c, 3)
    assert(c.A.Bar.PullOn() and pullKeys(c) ~= "", "open from 3 s: " .. pullKeys(c))
    tick(c, 8)
    assert(not c.A.Bar.PullOn() and pullKeys(c) == "", "over 10 s after the finish: " .. pullKeys(c))
    noErrors(c)
  end)

  local function notNow(c, key)
    c.A.Bar.Menu(icon(c, "own", key))
    local chose = false
    for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Not now" then e.fn(); chose = true end end
    assert(chose, "a Not now for " .. key)
  end
  test("review 6: Not now on a Before the pull icon quiets Before the pull, which runs its course: the same flasks and food never come straight back in your part, nor the camp's Eat", function()
    local c = consumer({ class = "WARRIOR", role = "tank", items = { CN.titans, CN.mongoose }, food = true })
    goTo(c, "raid")
    tick(c, 5)
    local before = consumeKeys(c)
    assert(before ~= "", "yours asks before the check")
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(find(shown(c, "pull"), "flask13510") and consumeKeys(c) == "", "the pull asks instead: " .. pullKeys(c) .. " | " .. consumeKeys(c))
    notNow(c, "flask13510"); tick(c, 2)
    assert(pullKeys(c) == "" and consumeKeys(c) == "", "Not now: none of them anywhere: " .. pullKeys(c) .. " | " .. consumeKeys(c))
    assert(c.A.Bar.PullOn(), "Before the pull runs on, quiet")
    fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
    assert(not c.A.Bar.PullOn() and consumeKeys(c) == before, "over 10 s after the finish; yours asks as before the check: " .. consumeKeys(c))
    -- (a second check in the ten minutes: Before the pull still quiet, yours aside for it)
    tick(c, 60)
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(pullKeys(c) == "" and consumeKeys(c) == "", "the second check: " .. pullKeys(c) .. " | " .. consumeKeys(c))
    fire(c, "READY_CHECK_FINISHED"); tick(c, 12)
    assert(consumeKeys(c) == before, "and after it: " .. consumeKeys(c))
    noErrors(c)
    -- the open world: Not now on Before the pull's Eat; the camp's Eat stays aside till the pull is over
    local w = consumer({ class = "PALADIN", role = "tank", items = { CN.mongoose }, food = true })
    goTo(w, nil)
    assert(find(shown(w, "camp"), "eat"), "the camp's Eat: " .. keysOf(shown(w, "camp")))
    fire(w, "READY_CHECK"); tick(w, 4)
    assert(find(shown(w, "pull"), "pullfood") and not find(shown(w, "camp"), "eat"), "Before the pull's Eat alone: " .. pullKeys(w))
    notNow(w, "pullfood"); tick(w, 2)
    assert(pullKeys(w) == "" and not find(shown(w, "camp"), "eat"), "Not now: no Eat at all: " .. pullKeys(w) .. " | " .. keysOf(shown(w, "camp")))
    fire(w, "READY_CHECK_FINISHED"); tick(w, 12)
    assert(not w.A.Bar.PullOn() and find(shown(w, "camp"), "eat"), "the camp's Eat back after the pull: " .. keysOf(shown(w, "camp")))
    noErrors(w)
  end)

  test("review 6: a paladin running both addons who reloads in a fight keeps their own PallyPower column on their own client; the share-out is every client's", function()
    local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
    local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-0D", assigned = "TANK", leader = true })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E" })
    local group = { TA, OR, BR, RA }
    local c1 = client({ me = OR, group = group, spec = 184, addons = PP_ADDON })
    local c2 = client({ me = TA, group = group, spec = 253, addons = PP_ADDON })
    knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60)
    load(c1); load(c2)
    tickAll(12)
    -- Orren's PallyPower: Might for warriors and rogues
    ppSay(OR, "SELF 607010nnnnnn@22nnnnnnn")
    tickAll(4)
    local function duties(c) local t = {}; for _, d in ipairs(c.A.Assign.duties) do t[#t + 1] = d.key .. ":" .. #d.targets end return table.concat(t, " ") end
    local was = duties(c1)
    for _, c in ipairs({ c1, c2 }) do
      assert(c.A.PallySync.pals[OR.guid] and c.A.Assign.BlessingOf(OR.guid, "WARRIOR:tank") == "might", "Orren's PallyPower Might for warriors")
    end
    -- a /reload in a fight: PallyPower's SELF at login refused in the lockdown, lost
    fight(c1, true); fight(c2, true)
    local n = reload(c1)
    n.lockdown = true
    load(n)
    fight(n, true)
    tickAll(6)
    fight(n, false); fight(c2, false); n.lockdown = false
    tickAll(120)
    assert(n.A.PallySync.pals[OR.guid], "Orren lists themselves after the reload")
    assert(n.A.Assign.BlessingOf(OR.guid, "WARRIOR:tank") == "might" and n.A.Assign.Source(OR.guid, "WARRIOR:tank") == "pp",
      "Orren's own client reads their PallyPower Might: " .. tostring(n.A.Assign.BlessingOf(OR.guid, "WARRIOR:tank")) .. "/" .. tostring(n.A.Assign.Source(OR.guid, "WARRIOR:tank")))
    assert(c2.A.Assign.BlessingOf(OR.guid, "WARRIOR:tank") == "might", "Tamsin's too")
    assert(duties(n) == was, "Orren's duties as before the reload: " .. duties(n) .. " (were " .. was .. ")")
    for _, c in ipairs({ n, c2 }) do noErrors(c, "a reload in a fight, both addons") end
  end)

  -- (a member leaves the group, on every client but their own, and is invited back)
  local function leaveAndBack(g, who, wait)
    local without = {}
    for _, m in ipairs(g.group) do if m ~= who then without[#without + 1] = m end end
    local mine
    for _, c in ipairs(g.all) do if c.o.me == who then mine = c end end
    for _, c in ipairs(g.all) do if c ~= mine then c.o.group = without; seat(c); fire(c, "GROUP_ROSTER_UPDATE") end end
    tickAll(4)
    for _, c in ipairs(g.all) do if c ~= mine then c.o.group = g.group; seat(c); fire(c, "GROUP_ROSTER_UPDATE") end end
    tickAll(wait or 30)
  end
  test("review 6: a member's own cell (NASSIGN) is kept while they are away, as PallyPower keeps it by name: a PallyPower paladin's, and a leader's in a column running Cute Auras alone", function()
    local g = ppParty()
    ppSay(g.YS, YS_SELF)
    tickAll(3)
    -- Ysolde's own Kings for Brok; the leader's own Wisdom for Rask from Orren
    ppSay(g.YS, "NASSIGN Ysolde_Ashbrook 1 Brok_Ironhide 3")
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 1")
    tickAll(4)
    local function check(label)
      for _, c in ipairs({ g.c1, g.c2 }) do
        local As = c.A.Assign
        assert(c.A.PallySync.MemberCell(g.YS.guid, g.BR.guid) == "kings", label .. ": Ysolde's own Kings for Brok on " .. c.o.me.name)
        assert(As.BlessingOf(g.YS.guid, "WARRIOR:tank") == "kings", label .. ": Ysolde's WARRIOR:tank, " .. tostring(As.BlessingOf(g.YS.guid, "WARRIOR:tank")))
        assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") ~= "kings", label .. ": Orren never doubles Ysolde's Kings on Brok")
        assert(As.BlessingOf(g.OR.guid, "WARRIOR:melee") == "wisdom", label .. ": the leader's Wisdom for Rask from Orren on " .. c.o.me.name .. ", " .. tostring(As.BlessingOf(g.OR.guid, "WARRIOR:melee")))
      end
    end
    check("set")
    leaveAndBack(g, g.BR)
    check("Brok back")
    leaveAndBack(g, g.RA)
    check("Rask back")
    -- over Orren's reload while the member is away (Brok: Ysolde's cell; Rask: the leader's in Orren's column): kept too
    for _, who in ipairs({ g.BR, g.RA }) do
      local c1 = reload(g.c1)
      local without = {}
      for _, m in ipairs(g.group) do if m ~= who then without[#without + 1] = m end end
      g.c2.o.group = without; seat(g.c2); fire(g.c2, "GROUP_ROSTER_UPDATE")
      c1.o.group = without
      load(c1)
      g.c1, g.all[1] = c1, c1
      tickAll(12)
      for _, c in ipairs({ g.c1, g.c2 }) do c.o.group = g.group; seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
      tickAll(30)
      check(who.name .. " back after Orren's reload")
    end
    for _, x in ipairs(g.all) do noErrors(x, "a member away and back") end
  end)

  test("review 6: a second member's own cell (NASSIGN) in a bucket that holds one keeps what the first covered: Orren's SELF keeps the leader's class cell, and it is the bucket's again once both are removed", function()
    local g = ppParty()
    local function row() return (g.c1.A.PallySync.SelfText():match("@(%S+)$")) end
    ppSay(g.BR, "PASSIGN Orren Lightsworn@2nnnnnnnn")
    tickAll(3)
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 3")
    tickAll(3)
    assert(g.c2.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank") == "kings", "Brok's own Kings")
    -- Rask turns tank: the bucket is Brok's and Rask's; the leader gives Rask Kings from Orren too
    g.RA.assigned = "TANK"
    for _, c in ipairs(g.all) do fire(c, "PLAYER_ROLES_ASSIGNED") end
    tickAll(3)
    assert(#g.c1.A.Assign.buckets["WARRIOR:tank"] == 2, "two warrior tanks")
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 3")
    tickAll(20)
    assert(row():sub(1, 1) == "2", "Orren's SELF keeps the leader's Might for warriors: " .. row())
    for _, s in ipairs(ppOut(g.c1, "SELF")) do assert(s.msg:match("@(%S+)$"):sub(1, 1) ~= "3", "no SELF sent with Kings for warriors: " .. s.msg) end
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 0")
    tickAll(3)
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 0")
    tickAll(3)
    for _, c in ipairs(g.all) do
      assert(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank") == "might", "both removed: the leader's Might again on " .. c.o.me.name .. ", " .. tostring(c.A.Assign.BlessingOf(g.OR.guid, "WARRIOR:tank")))
    end
    local ov = ovOf(g.c1, g.OR.guid, "WARRIOR:tank")
    assert(ov and ov.key == "might" and ov.pp, "Orren's cell: the leader's class cell")
    for _, x in ipairs(g.all) do noErrors(x, "a second NASSIGN in a bucket") end
  end)

  test("review 6: two members with their own cells (NASSIGN) swap roles in one share-out: each keeps theirs where they are now, and a removal gives the leader's class cell back", function()
    local TA = member({ name = "Tamsin", surname = "Reed", class = "ROGUE", level = 60, guid = "Player-1-0A" })
    local OR = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-0B" })
    local VE = member({ name = "Vessa", surname = "Moorwind", class = "PRIEST", level = 60, guid = "Player-1-0C", leader = true })
    local BR = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-0D", assigned = "TANK" })
    local RA = member({ name = "Rask", surname = "Stonefist", class = "WARRIOR", level = 60, guid = "Player-1-0E", assigned = "DAMAGER" })
    local group = { TA, OR, VE, BR, RA }
    local c1 = client({ me = OR, group = group, spec = 184 })
    local c2 = client({ me = TA, group = group, spec = 253 })
    knowAll(c1, "PALADIN", 60); knowAll(c2, "ROGUE", 60)
    load(c1); load(c2)
    tickAll(12)
    local function cell(c, bk) return c.A.Assign.BlessingOf(OR.guid, bk) end
    ppSay(VE, "PASSIGN Orren Lightsworn@2nnnnnnnn")
    tickAll(3)
    ppSay(VE, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 3@Orren_Lightsworn 1 Rask_Stonefist 1")
    tickAll(4)
    for _, c in ipairs({ c1, c2 }) do
      assert(cell(c, "WARRIOR:tank") == "kings" and cell(c, "WARRIOR:melee") == "wisdom", "Brok's Kings, Rask's Wisdom")
    end
    -- both roles change at once
    BR.assigned, RA.assigned = "DAMAGER", "TANK"
    for _, c in ipairs({ c1, c2 }) do fire(c, "PLAYER_ROLES_ASSIGNED") end
    tickAll(6)
    for _, c in ipairs({ c1, c2 }) do
      assert(cell(c, "WARRIOR:tank") == "wisdom" and cell(c, "WARRIOR:melee") == "kings",
        "each keeps theirs: tank " .. tostring(cell(c, "WARRIOR:tank")) .. ", melee " .. tostring(cell(c, "WARRIOR:melee")) .. " on " .. c.o.me.name)
    end
    ppSay(VE, "NASSIGN Orren_Lightsworn 1 Rask_Stonefist 0")
    tickAll(4)
    for _, c in ipairs({ c1, c2 }) do
      assert(cell(c, "WARRIOR:tank") == "might" and cell(c, "WARRIOR:melee") == "kings", "Rask's removed: the leader's Might on the tank, Brok's Kings kept: " .. tostring(cell(c, "WARRIOR:tank")) .. ", " .. tostring(cell(c, "WARRIOR:melee")))
    end
    ppSay(VE, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 0")
    tickAll(4)
    for _, c in ipairs({ c1, c2 }) do assert(cell(c, "WARRIOR:melee") == "might", "Brok's removed: Might") end
    for _, c in ipairs({ c1, c2 }) do noErrors(c, "a swap") end
  end)

  test("review 6: a server-sent elixir whose spell text has not loaded yet is never kept as having no stat words: once the text is in, it is asked", function()
    local c = consumer({ class = "WARRIOR", role = "melee" })
    c.items[990930] = { name = "Elixir of the Shallows", classID = 0, subID = 2, spell = 990931 }
    -- (the tooltip has its name and level before the spell's text: no Use line yet)
    c.tooltips[990930] = { { leftText = "Elixir of the Shallows" }, { leftText = "Requires Level 50" } }
    c.items[990932] = { name = "Juju of the Shallows", classID = 12, subID = 0, spell = 990933 }
    c.tooltips[990932] = { { leftText = "Juju of the Shallows" }, { leftText = "Quest Item" } }
    c.bags = { { id = 990930, bag = 0, slot = 1, count = 3 }, { id = 990932, bag = 0, slot = 2, count = 3 } }
    fire(c, "BAG_UPDATE_DELAYED")
    goTo(c, "raid")
    assert(not find(shown(c, "mine"), "consume990930"), "not yet")
    local Cn = c.A.Consume
    assert(Cn.Words(990930) == "" and Cn.KindOf(990932) == nil, "no words yet")
    -- the text comes in
    SPELL_DESC[990931] = "Increases Agility by 30 for 1 hour."
    SPELL_DESC[990933] = "Increases Strength by 30 for 10 min."
    c.tooltips[990930] = nil; c.tooltips[990932] = nil
    fire(c, "SPELL_TEXT_UPDATE", 990931); fire(c, "SPELL_TEXT_UPDATE", 990933); tick(c, 1)
    assert(Cn.Words(990930) == "agi", "its words now: " .. tostring(Cn.Words(990930)))
    assert(Cn.KindOf(990932) == "other", "the juju an Other now: " .. tostring(Cn.KindOf(990932)))
    assert(find(shown(c, "mine"), "consume990930"), "asked, with no bag event: " .. consumeKeys(c))
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(find(shown(c, "pull"), "flask990930"), "and before the pull: " .. pullKeys(c))
    SPELL_DESC[990931], SPELL_DESC[990933] = nil, nil
    noErrors(c)
  end)

  test("review 6: the Blessings grid's paladin names fit their columns, cut clean with no dots, seven paladins across a raid; a cell's tooltip names the paladin in full", function()
    local ME = member({ name = "Orren", surname = "Lightsworn", class = "PALADIN", level = 60, guid = "Player-1-L00" })
    local names = { "Wardenwallow", "Bramblewicke", "Thornquillan", "Emberhollows", "Ravenmarshes", "Duskwhistler" }
    local group, pals = { ME }, {}
    for i, nm in ipairs(names) do
      local m = member({ name = nm, surname = "Testvale", class = "PALADIN", level = 60, guid = string.format("Player-1-L%02d", i) })
      group[#group + 1] = m; pals[#pals + 1] = m
    end
    group[#group + 1] = member({ name = "Brok", surname = "Ironhide", class = "WARRIOR", level = 60, guid = "Player-1-L20", assigned = "TANK", leader = true })
    for i, m in ipairs(group) do m.sub = math.floor((i - 1) / 5) + 1 end
    local c = client({ me = ME, group = group, raid = true, spec = 184 })
    knowAll(c, "PALADIN", 60)
    load(c)
    tickAll(12)
    for _, m in ipairs(pals) do ppSay(m, "SELF 607010nnnnnn@nnnnnnnnn") end
    tickAll(4)
    assert(#c.A.Assign.paladins == 7, "seven paladins: " .. #c.A.Assign.paladins)
    c.A.Window.Open("blessings")
    local page = c.A.Window.pages.blessings
    local shownN = 0
    for _, col in ipairs(page.cols) do
      if col:IsShown() then
        shownN = shownN + 1
        FITS(col, "a paladin's name")
        assert(not col.__text:find("%.%.%."), "no dots: " .. col.__text)
      end
    end
    assert(shownN == 7, "seven columns: " .. shownN)
    local cell
    for _, x in ipairs(page.cells) do if x:IsShown() and x.pal == pals[1].guid then cell = x end end
    assert(cell, "a cell of " .. names[1] .. "'s column")
    local lines = tipOf(c, cell)
    assert(lines[2] == "Set in PallyPower." and lines[#lines] == "Paladin: " .. names[1] .. ".", "the tooltip names the paladin in full, last: " .. table.concat(lines, " | "))
    -- (a name that fits, and yours: You, no line for it)
    local mine
    for _, x in ipairs(page.cells) do if x:IsShown() and x.pal == ME.guid then mine = x end end
    lines = tipOf(c, mine)
    assert(not table.concat(lines, " | "):find("Paladin:", 1, true), "yours: " .. table.concat(lines, " | "))
    noErrors(c)
  end)
end

----------------------------------------------------------------------------
-- review 7: Move mode let go in a fight; glows and words after a member leaves in a fight; a SELF still queued at a
-- /reload; the after-fight REQ; a 0.2.2 ready check's Never; a ready check in town; mp5's words; the weapon row; a
-- second ready check; spell text on the open tab; a leader's 0 under a member's own cell
----------------------------------------------------------------------------
do
  test("review 7: Move mode: a drag let go in a fight stops after it, never in it, its place saved then; a release in a fight with no drag started changes nothing", function()
    local g = party5long()
    local c = g.c3
    c.A.Window.Move(true)
    local bar, an = c.env.CuteAurasBar, c.env.CuteAurasAlerts
    assert(bar.__protected and an.__protected, "both protected: secure buttons in them")
    for _, f in ipairs({ bar, an }) do
      local key = f == bar and "pos" or "alertPos"
      c.A.Settings()[key] = nil
      f.__scripts.OnDragStart(f)
      assert(f.__moving, f.__name .. ": dragged")
      fight(c, true)
      f.__scripts.OnDragStop(f)
      assert(f.__moving and c.A.Settings()[key] == nil, f.__name .. ": let go in the fight, it follows on till the fight ends")
      fight(c, false); tick(c, 1)
      assert(not f.__moving and c.A.Settings()[key] ~= nil, f.__name .. ": stopped and saved after the fight")
      -- (dragged in a fight: nothing starts, and the release changes nothing)
      c.A.Settings()[key] = nil
      fight(c, true)
      f.__scripts.OnDragStart(f)
      f.__scripts.OnDragStop(f)
      assert(not f.__moving, f.__name .. ": no drag in a fight")
      fight(c, false); tick(c, 1)
      assert(not f.__moving and c.A.Settings()[key] == nil, f.__name .. ": nothing to stop or save after it")
      -- (out of a fight: at once, as before)
      f.__scripts.OnDragStart(f); f.__scripts.OnDragStop(f)
      assert(not f.__moving and c.A.Settings()[key] ~= nil, f.__name .. ": out of a fight, stopped and saved at once")
    end
    c.A.Window.Move(true)
    assert(not c.A.Window.Moving(), "Done")
    noErrors(c)
  end)

  test("review 7: a member leaves in a fight while restores wait: a row its blessing's list now reaches glows, a renamed one does not; the words say target them where no row of that list reaches them, and that icon's wash goes", function()
    local g = party5long()
    local c = g.c3
    local Al, Hn = c.A.Alerts, c.A.Hands
    local war, p2 = g.WAR.guid, g.P2.guid
    local kingsB, wisB = icon(c, "group", "duty:bless:kings"), icon(c, "group", "duty:bless:wisdom")
    local kings, wis = c.env[kingsB:GetName() .. "Fly"], c.env[wisB:GetName() .. "Fly"]
    fight(c, true)
    hand(c, g.WAR, 1044, 1); hand(c, g.P2, 1044, 2)
    tick(c, 11)
    assert(Hn.Glowing(war, "duty:bless:kings") and Hn.Glowing(p2, "duty:bless:wisdom"), "both wait: the tank's Kings, the priest's Wisdom")
    assert(rowOf(kings, g.WAR.name).glow:IsShown() and rowOf(wis, g.P2.name).glow:IsShown(), "their rows glow")
    assert(kingsB.glowTex:IsShown() and wisB.glowTex:IsShown(), "both washes")
    local function words(guid) return Al.cards["restore:" .. guid].spec.text end
    assert(words(war) == "Freedom is over. Their row glows in the bar's Kings list.", words(war))
    -- the healer leaves in the fight: party1 is the second priest now, party2 the rogue, party3 the tank, party4 no one
    local grp = c.o.group
    for i, m in ipairs(grp) do if m == g.P1 then table.remove(grp, i) break end end
    seat(c)
    fire(c, "GROUP_ROSTER_UPDATE")
    tick(c, 1)
    -- (Kings: its one row, party4, no one; Wisdom: party1 reaches the priest now, party2 the rogue)
    local kr = kings.rows[1]
    assert(kr.name.__text == "?" and not kr.glow:IsShown(), "the Kings row on no one: " .. kr.name.__text)
    assert(not kingsB.glowTex:IsShown(), "no Kings row reaches the tank: no Kings wash")
    local pr = rowOf(wis, g.P2.name)
    assert(pr and pr:GetAttribute("unit") == "party1" and pr.glow:IsShown(), "the Wisdom row that reaches the priest now glows")
    assert(not rowOf(wis, g.ROG.name).glow:IsShown(), "the row renamed to the rogue does not")
    assert(wisB.glowTex:IsShown(), "the Wisdom wash stays")
    local mr = rowOf(c.env[icon(c, "group", "duty:bless:might"):GetName() .. "Fly"], g.WAR.name)
    assert(mr and not mr.glow:IsShown(), "the tank in the Might list now: no glow, Kings is theirs")
    assert(words(war) == "Freedom is over. Target them and give them Kings.", "the tank's words: " .. words(war))
    assert(words(p2) == "Freedom is over. Their row glows in the bar's Wisdom list.", "the priest's: " .. words(p2))
    FITS(Al.cards["restore:" .. war].text, "the restore's words")
    assert(Al.order[1] == "restore:" .. war, "the tank's in its own slot still: " .. table.concat(Al.order, ","))
    fight(c, false); tick(c, 2)
    noErrors(c)
  end)

  test("review 7: a SELF still queued in a fight at a /reload is never saved as sent: after the reload it goes out", function()
    local EMPTY = "SELF nnnnnnnnnnnn@nnnnnnnnn"
    local g = ppParty()
    ppSay(g.YS, YS_SELF)
    tickAll(30)
    local n = #ppOut(g.c1, "SELF")
    assert(n >= 1 and ppOut(g.c1, "SELF")[n].msg ~= EMPTY, "Orren spoke")
    -- Blessings off in a fight: the empty SELF queued behind it; a /reload in that fight
    fight(g.c1, true)
    g.c1.A.Settings().blessings = false
    g.c1.A.Comm.GivesChanged()
    tickAll(20)
    assert(#ppOut(g.c1, "SELF") == n and g.c1.A.Comm.Waiting("PLPWR", "SELF"), "the empty SELF waits in the queue")
    local c1 = reload(g.c1)
    load(c1)
    g.c1, g.all[1] = c1, c1
    tickAll(60)
    local after = ppOut(c1, "SELF")
    assert(#after >= 1 and after[#after].msg == EMPTY, "the empty SELF after the reload: " .. #after .. " " .. tostring(after[#after] and after[#after].msg))
    for _, x in ipairs(g.all) do noErrors(x, "a SELF queued at a reload") end
  end)

  test("review 7: a REQ that left before the pull answers nothing sent in the fight: the after-fight REQ waits out its 30 s and goes", function()
    local g = ppParty()
    local c2 = g.c2
    ppSay(g.YS, YS_SELF)
    tickAll(60)
    assert(c2.A.PallySync.IsAsker(), "Tamsin asks")
    local r0 = #ppOut(c2, "REQ")
    c2.A.Window.Open("blessings")
    tickAll(2)
    assert(#ppOut(c2, "REQ") == r0 + 1, "the tab's REQ: " .. (#ppOut(c2, "REQ") - r0))
    tickAll(4)
    fight(c2, true); tick(c2, 12); fight(c2, false)
    tickAll(6)
    assert(#ppOut(c2, "REQ") == r0 + 1, "none within 30 s of the tab's")
    tickAll(30)
    assert(#ppOut(c2, "REQ") == r0 + 2, "the after-fight REQ, 30 s after the tab's: " .. (#ppOut(c2, "REQ") - r0))
    -- (a REQ that left after the fight answers it: the next fight in 5 minutes asks nothing)
    tickAll(40)
    fight(c2, true); tick(c2, 5); fight(c2, false)
    tickAll(40)
    assert(#ppOut(c2, "REQ") == r0 + 2, "one after-fight REQ in 5 minutes: " .. (#ppOut(c2, "REQ") - r0))
    for _, x in ipairs(g.all) do noErrors(x, "the after-fight REQ") end
  end)

  test("review 7: a 0.2.2 ready check's Never on a flask or elixir keeps it off the bar out of a fight: no fit or kind default brings it back; a habit still asks there, as in 0.2.2", function()
    local db = { settings = { consume = "instance", never = { ["flask:13510"] = "Flask of the Titans", ["flask:13452"] = "Elixir of the Mongoose" } } }
    local c = consumer({ name = "Oldtank", class = "WARRIOR", role = "tank", items = { CN.titans, CN.mongoose }, db = db })
    local never = c.A.Settings().never
    assert(never["pull:13510"] and never["pull:13452"], "flask: became pull:")
    for _, where in ipairs({ "party", "raid" }) do
      goTo(c, where)
      assert(not find(shown(c, "mine"), "consume13510") and not find(shown(c, "mine"), "consume13452"), where .. ": neither asked: " .. consumeKeys(c))
    end
    local page = cnPage(c)
    local row = cnRow(page, 13510)
    assert(row.state.__text == "Never", "its state: " .. row.state.__text)
    c.hover(row.hit)
    local tl = table.concat(c.env.GameTooltip.lines, " | ")
    assert(tl:find("A Never from 0.2.2: not before the pull, and elsewhere only as a habit or where you choose.", 1, true), tl)
    -- (a place chosen asks it there)
    c.A.Consume.SetChoice(13452, "raid", true); tick(c, 1)
    assert(find(shown(c, "mine"), "consume13452"), "chosen for raids: asked: " .. consumeKeys(c))
    noErrors(c)
    -- a habit with that Never: asked out of a fight, as 0.2.2 did; never before the pull
    local h = { settings = { consume = "instance", never = { ["flask:13510"] = "Flask of the Titans" } },
      chars = { ["Player-1-Oldhab"] = { role = "tank", consume = { [13510] = { hits = 3, miss = 0, spell = 17626 } } } } }
    local c2 = consumer({ name = "Oldhab", class = "WARRIOR", items = { CN.titans }, db = h })
    goTo(c2, "raid")
    assert(find(shown(c2, "mine"), "consume13510"), "the habit asked in a raid: " .. consumeKeys(c2))
    fire(c2, "READY_CHECK"); tick(c2, 4)
    assert(not pullKeys(c2):find("flask13510"), "never before the pull: " .. pullKeys(c2))
    noErrors(c2)
  end)

  test("review 7: in a city or inn the Consumables tab's top line says a ready check still asks there, as Before the pull does; Before the pull off, nothing", function()
    local c = consumer({ class = "WARRIOR", role = "melee", food = true, items = { CN.titans, CN.mongoose } })
    c.resting = true; fire(c, "PLAYER_UPDATE_RESTING"); tick(c, 1)
    local page = cnPage(c)
    page:Sync()
    assert(page.here.__text == "Here: World, in a city or inn: only a ready check asks.", page.here.__text)
    FITS(page.here, "the top line")
    fire(c, "READY_CHECK"); tick(c, 4)
    assert(pullKeys(c) ~= "", "a ready check asks there: " .. pullKeys(c))
    c.A.Bar.PullEnd(); tick(c, 1)
    c.A.Settings().pull = false
    page:Sync()
    assert(page.here.__text == "Here: World, in a city or inn: nothing is asked there.", page.here.__text)
    noErrors(c)
  end)

  test("review 7: the Consumables tab names Mana regen for mp5: Mageblood Potion's line, and beside another stat", function()
    local Cn
    local c = consumer({ class = "PRIEST", role = "healer", items = { { 20007, "Mageblood Potion", 0, 1, 24363 } } })
    Cn = c.A.Consume
    assert(Cn.SubLine("mp5", 5) == "Mana regen. 5 in your bags", Cn.SubLine("mp5", 5))
    assert(Cn.SubLine("hp mp5", 5) == "Health, mana regen. 5 in your bags", Cn.SubLine("hp mp5", 5))
    assert(Cn.SubLine("heal spell mp5", 2) == "Healing, spell damage. 2 in your bags", Cn.SubLine("heal spell mp5", 2))
    local row = cnRow(cnPage(c), 20007)
    assert(row and row.sub.__text == "Mana regen. 5 in your bags", "Mageblood's line: " .. tostring(row and row.sub.__text))
    FITS(row.sub, "Mageblood's line")
    noErrors(c)
  end)

  test("review 7: the open Consumables tab's Weapon row follows the oil's end (UNIT_INVENTORY_CHANGED), as the bar does", function()
    local c = consumer({ class = "MAGE", role = "caster", items = { CN.wizard } })
    c.items[5005] = { name = "Plain Staff", equipLoc = "INVTYPE_2HWEAPON" }
    c.equipped[16] = 5005
    goTo(c, "raid")
    c.A.Consume.SetChoice(20749, "raid", true)
    c.enchant = { [16] = true }
    fire(c, "UNIT_INVENTORY_CHANGED", "player"); tick(c, 1)
    local page = cnPage(c)
    page:Sync()
    tick(c, 1)
    assert(cnRowNow(page, 20749).state.__text == "On you" and not page.timed, "the oil on: " .. cnRowNow(page, 20749).state.__text)
    -- the oil runs out: no aura, no bag change, only the inventory's event
    c.enchant = nil
    fire(c, "UNIT_INVENTORY_CHANGED", "player"); tick(c, 2)
    assert(find(shown(c, "mine"), "weapon16"), "the bar asks for it")
    assert(cnRowNow(page, 20749).state.__text == "Missing", "the tab too: " .. cnRowNow(page, 20749).state.__text)
    noErrors(c)
  end)

  test("review 7: a ready check answered within 3 s while an earlier Before the pull still runs ends 10 s after its finish, not at 45 s: a second check, and a raid's entry", function()
    local c = consumer({ class = "WARRIOR", role = "melee", items = { CN.mongoose, CN.titans }, food = true })
    goTo(c, "party")
    fire(c, "READY_CHECK"); tick(c, 20)
    fire(c, "READY_CHECK_FINISHED"); tick(c, 3)
    assert(c.A.Bar.PullOn(), "the first check's pull runs on")
    fire(c, "READY_CHECK"); tick(c, 1)
    fire(c, "READY_CHECK_FINISHED"); tick(c, 4)
    assert(c.A.Bar.PullOn() and pullKeys(c) ~= "", "the second check's pull: " .. pullKeys(c))
    tick(c, 8)
    assert(not c.A.Bar.PullOn() and pullKeys(c) == "", "over 10 s after the second finish: " .. pullKeys(c))
    assert(consumeKeys(c) ~= "", "yours asks again: " .. consumeKeys(c))
    noErrors(c)
    -- a raid's entry (60 s), then a check answered in 1 s
    local r = consumer({ name = "Raider", class = "WARRIOR", role = "melee", items = { CN.mongoose, CN.titans }, food = true })
    goTo(r, "raid")
    fire(r, "PLAYER_ENTERING_WORLD"); tick(r, 20)
    assert(r.A.Bar.PullOn(), "the entry's pull")
    fire(r, "READY_CHECK"); tick(r, 1)
    fire(r, "READY_CHECK_FINISHED"); tick(r, 12)
    assert(not r.A.Bar.PullOn() and pullKeys(r) == "", "over 10 s after the finish, not at the entry's 60 s or the check's 45: " .. pullKeys(r))
    noErrors(r)
  end)

  test("review 7: the open Consumables tab reads again when a spell's text comes in: the server-sent elixir's row shows, as the bar asks for it", function()
    local c = consumer({ class = "WARRIOR", role = "melee" })
    c.items[990930] = { name = "Elixir of the Shallows", classID = 0, subID = 2, spell = 990931 }
    c.tooltips[990930] = { { leftText = "Elixir of the Shallows" }, { leftText = "Requires Level 50" } }
    c.bags = { { id = 990930, bag = 0, slot = 1, count = 3 } }
    fire(c, "BAG_UPDATE_DELAYED")
    goTo(c, "raid")
    local page = cnPage(c)
    tick(c, 1)
    assert(not cnRowNow(page, 990930) and page.empty:IsShown(), "no words yet: no row")
    SPELL_DESC[990931] = "Increases Agility by 30 for 1 hour."
    c.tooltips[990930] = nil
    fire(c, "SPELL_TEXT_UPDATE", 990931); tick(c, 2)
    SPELL_DESC[990931] = nil
    assert(find(shown(c, "mine"), "consume990930"), "the bar asks for it: " .. consumeKeys(c))
    assert(cnRowNow(page, 990930) and not page.empty:IsShown(), "and its row on the open tab")
    noErrors(c)
  end)

  test("review 7: a leader's 0 for your warriors while each warrior has their own cell (NASSIGN) sends none for warriors, never the leader's old blessing; removed, Cute Auras' choice", function()
    local g = ppParty()
    -- Rask leaves: Brok, the tank, the only warrior
    table.remove(g.group, 5)
    for _, c in ipairs(g.all) do seat(c); fire(c, "GROUP_ROSTER_UPDATE") end
    tickAll(25)
    local As = g.c1.A.Assign
    local function warriors() local t = ppOut(g.c1, "SELF"); return t[#t] and t[#t].msg:match("@(.)"), #t end
    local choice = As.BlessingOf(g.OR.guid, "WARRIOR:tank")
    ppSay(g.BR, "ASSIGN Orren Lightsworn 1 2")
    tickAll(25)
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "might" and warriors() == "2", "the leader's Might for warriors")
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 1")
    tickAll(25)
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "wisdom", "Brok's own Wisdom")
    local _, n = warriors()
    ppSay(g.BR, "ASSIGN Orren Lightsworn 1 0")
    tickAll(25)
    local w, n2 = warriors()
    assert(n2 > n and w == "n", "the leader's 0: no blessing for warriors in Orren's SELF, not the old Might: " .. tostring(w))
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == "wisdom", "Brok's own Wisdom kept")
    ppSay(g.BR, "NASSIGN Orren_Lightsworn 1 Brok_Ironhide 0")
    tickAll(25)
    assert(As.BlessingOf(g.OR.guid, "WARRIOR:tank") == choice, "removed: Cute Auras' choice, " .. tostring(As.BlessingOf(g.OR.guid, "WARRIOR:tank")))
    w = warriors()
    assert(w == g.c1.A.PallySync.SelfText():match("@(.)") and w ~= "n" and w ~= "2", "the SELF follows: " .. tostring(w))
    for _, x in ipairs(g.all) do noErrors(x, "a leader's 0 under a member's own cell") end
  end)
end

print(string.format("OK (%d scenarios)", passed))
