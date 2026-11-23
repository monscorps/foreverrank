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

local function newClient(o)
  local c = { o = o, units = {}, events = {}, timers = {}, clock = 1000, combat = false, casts = {}, chat = {}, menus = {}, frames = {},
              known = {}, bags = {}, equipped = {}, items = {}, tooltips = {}, profs = o.profs or {}, zone = o.zone or "Elwynn Forest", subzone = "",
              said = {}, plainAuras = {}, drivers = {}, equips = {} }
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
               WeaponSlot = { MainHand = 0, OffHand = 1 }, AddOnRestrictionType = { Combat = 1, Encounter = 2 } }
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
      -- members hidden with no unit
      f.__shown = false
      local function sec(fn) local was = c.restricted; c.restricted = true; fn(); c.restricted = was end
      local function update(self)
        if not self:IsVisible() then return end
        local list = self.__attrs.nameList
        local order, units = {}, {}
        local i = 0
        for n in (list or ""):gmatch("[^,]+") do i = i + 1; order[n] = order[n] or i end
        if c.o.raid and self.__attrs.showRaid then
          for k = 1, 40 do local x = c.units["raid" .. k]; if x and order[x.name] then units[#units + 1] = "raid" .. k end end
        elseif not c.o.raid and c.o.group and self.__attrs.showParty then
          if self.__attrs.showPlayer and order[c.units.player.name] then units[#units + 1] = "player" end
          for k = 1, 4 do local x = c.units["party" .. k]; if x and order[x.name] then units[#units + 1] = "party" .. k end end
        end
        table.sort(units, function(a, b) return order[c.units[a].name] < order[c.units[b].name] end)
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
  -- a click as the game does it: a wrap's pre snippet, the button's own and hooked OnClick, the wrap's post snippet
  -- (both edges of a click, each the button heard (RegisterForClicks), each running a wrap's snippets as the game does)
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
    -- name, then SUCCEEDED, unless the game refused it (c.refuse: the global cooldown, a cast going, range))
    if c.castEvents then
      for k = before + 1, #c.casts do
        local cast = c.casts[k]
        if cast.type == "spell" then
          c.castN = (c.castN or 0) + 1
          local cg, who = "cast-auto-" .. c.castN, c.units[cast.unit or "target"]
          FIRE(c, "UNIT_SPELLCAST_SENT", "player", who and who.name or "", cg, cast.spell)
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
    GetOwner = function(self) return self.owner end, GetWidth = function() return 240 end }
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
  env.UnitName = function(u) local x = U(u); return x and x.name or nil end
  env.UnitClass = function(u) local x = U(u); if not x then return nil end return CLASS_NAME[x.class], x.class, 1 end
  env.UnitLevel = function(u) local x = U(u); return x and x.level or 0 end
  env.UnitIsDeadOrGhost = function(u) local x = U(u); return x and x.dead or false end
  env.UnitIsConnected = function(u) local x = U(u); return x and x.online ~= false end
  env.UnitIsVisible = function(u) local x = U(u); return x and x.visible ~= false end
  env.UnitGroupRolesAssigned = function(u) local x = U(u); return x and x.assigned or "NONE" end
  env.UnitIsGroupLeader = function(u) local x = U(u); return x and x.leader or false end
  env.UnitIsGroupAssistant = function(u) return false end
  env.UnitIsFriend = function() return true end
  env.UnitIsUnit = function(a, b) return U(a) and U(b) and U(a).guid == U(b).guid end
  env.UnitExists = function(u) return U(u) ~= nil end
  env.UnitIsDead = function(u) local x = U(u); return x and x.dead or false end
  env.IsInGroup = function(cat) if cat == 2 then return false end return (c.o.group and #c.o.group > 1) or false end
  env.IsInRaid = function() return c.o.raid or false end
  env.GetNumGroupMembers = function() return c.o.group and #c.o.group or 0 end
  env.GetNumSubgroupMembers = function() return c.o.group and math.min(#c.o.group - 1, 4) or 0 end
  env.GetRaidRosterInfo = function(i) local x = c.units["raid" .. i]; if not x then return nil end return x.name, 0, x.sub or 1, x.level, CLASS_NAME[x.class], x.class end
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
  env.C_Secrets = { ShouldAurasBeSecret = function() return c.combat end, ShouldSpellAuraBeSecret = function(id) return c.combat and not c.plainAuras[id] end,
    ShouldUnitIdentityBeSecret = function() return false end }
  env.C_UnitAuras = {
    GetAuraDataByIndex = function(u, i, filter)
      c.auraReads = c.auraReads or {}
      c.auraReads[u] = (c.auraReads[u] or 0) + 1
      local x = U(u)
      local a = x and x.auras and x.auras[i]
      if not a then return nil end
      if c.combat then return { name = secret(), spellId = secret(), applications = secret(), expirationTime = secret(), sourceUnit = secret(), duration = secret() } end
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
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
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
    GetItemSpell = function(id) local it = item(id); if it.spell then return "Use", it.spell end return nil end,
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
  -- the addon channel: every client in the world with a group hears it, the sender too (Forever echoes it)
  env.C_ChatInfo = { RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, msg, ch)
      if c.lockdown then return 11 end
      c.said[#c.said + 1] = msg
      for _, other in ipairs(WORLD) do
        if other.o.group == c.o.group then
          local me = c.units.player
          other.inbox[#other.inbox + 1] = { prefix, msg, ch, me.name .. "-Realm" }
        end
      end
      return 0
    end }
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
  assert(card.title:GetText():find("Bramblewoode", 1, true) and card.text:GetText():find("Click", 1, true), "who and what: " .. card.title:GetText() .. " / " .. card.text:GetText())
  c.hover(card)
  local tip = table.concat(c.env.GameTooltip.lines, " | ")
  assert(c.env.GameTooltip.owner == card and tip:find("Right-click: dismiss", 1, true), "the card's tooltip: " .. tip)
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
  -- the bar hidden in a fight: the card says to target them
  c.A.Settings().fight = "hide"
  fight(c, true)
  hand(c, g.ROG, 10278, 1); tick(c, 0.5); hand(c, g.WAR, 1044, 2)
  tick(c, 11)
  local a = Al.cards["restore:" .. war]
  assert(a and a.text:GetText():find("Target them", 1, true), "no bar in a fight: " .. (a and a.text:GetText() or "none"))
  FITS(a.text, "restore line, no row")
  fight(c, false)
  tick(c, 2)
  assert(card:IsShown() and card.guid == rog, "the first on the secure card")
  local nextCard = Al.cards["restore:" .. war]
  assert(nextCard and nextCard.text:GetText():find("Next", 1, true) and not (nextCard.spec.tip or ""):find("Once the fight ends", 1, true),
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
  c.A.Settings().consume = "off"; c.A.Bar.Dirty("all"); tick(c, 1)
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
  c.A.Settings().consume = "off"; c.A.Bar.Dirty("all"); tick(c, 1)
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

test("group icons: a member's name whole under its icon, never under the next; the wash on the icon whose list holds the member", function()
  local g = party5long()
  local c = g.c3
  tick(c, 2)
  local list = {}
  for _, rec in ipairs(shown(c, "group")) do list[#list + 1] = icon(c, "group", rec.key) end
  assert(#list >= 2, "the paladin's blessings: " .. #list)
  local long = false
  for i, b in ipairs(list) do
    FITS(b.word, "a group icon's word")
    if TEXT_WIDTH(b.word.__text, 11) > 38 then long = true end
    if i > 1 then
      local a = list[i - 1]
      local ax, bx = a.__points[1][4], b.__points[1][4]
      assert(ax + 16 + a.word.__w / 2 <= bx + 16 - b.word.__w / 2, "a word under the next icon's: " .. a.word.__text .. " / " .. b.word.__text)
    end
  end
  assert(long, "a twelve-letter name to fit")
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

test("the bar holds still as a group icon's name changes: its column fits the longest name in its list", function()
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
  local bar = c.env.CuteAurasBar
  local b = icon(c, "group", "duty:fort")
  assert(b and b:IsShown(), "the Fortitude icon")
  local width, col = bar.__w, b.word.__w
  local seen, steps = {}, 0
  for _ = 1, 6 do
    if not b:IsShown() then break end
    local word = b.word.__text
    if word == "You" or seen[word] then break end
    seen[word] = true
    steps = steps + 1
    assert(bar.__w == width and b.word.__w == col, "the bar and the column hold still under '" .. word .. "': " .. bar.__w .. " / " .. width)
    -- the one named gets it
    for _, m in ipairs(group) do
      if m.name == word then
        m.auras[#m.auras + 1] = { id = 10937, src = "player", exp = c.clock + 1800, dur = 1800 }
        fire(c, "UNIT_AURA", tokenOf(c, m))
      end
    end
    tick(c, 4)
  end
  assert(steps >= 3, "three names shown one after another: " .. steps)
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
  local consume = widget(page, "Potions, elixirs, flasks and Well Fed")
  local off
  for _, x in ipairs(consume.buttons) do if x.text.__text == "Off" then off = x end end
  c.click(off)
  assert(pull.__alpha == 0.45 and pull.label.__text == "Before the pull: consumables Off", "greyed: " .. pull.label.__text)
  assert(TEXT_WIDTH(pull.label.__text, 12) <= pull.__w - 22, "its words fit")
  for _, x in ipairs(consume.buttons) do if x.text.__text == "Instances" then c.click(x) end end
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
  c.A.Settings().alertSize = "normal"
  local hN = Al.CardHeight()
  c.A.Settings().alertSize = "small"
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

test("Upgrade: Inner Fire 5 on you and rank 6 learned asks for rank 6, on each of the learning events; the word fits", function()
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
    assert(rec and rec.word == "Upgrade" and rec.click.spell == 10952 and rec.click.unit == "player", ev .. ": Upgrade to rank 6: " .. tostring(rec and rec.word))
    assert(rec.why == "Rank 5 on you; you know rank 6." and rec.lit, rec.why)
  end
  local b = icon(c, "own", "self:innerfire")
  assert(b:IsShown() and b:GetAttribute("spell") == 10952 and b:GetAttribute("unit") == "player", "the secure button casts rank 6 on you")
  FITS(b.word, "Upgrade under its icon")
  -- (its column as wide as the word: the next icon, the group's first, never under it)
  local g = c.env.CuteAurasBarGroup
  local first
  for _, x in pairs(g.__children) do if x.word and x:IsShown() and (not first or x.__points[1][4] < first.__points[1][4]) then first = x end end
  assert(first, "a group icon beside it")
  local ownX, grpX = c.env.CuteAurasBarOwn.__points[1][4], g.__points[1][4]
  assert(ownX + b.__points[1][4] + 16 + b.word.__w / 2 <= grpX + first.__points[1][4] + 16 - first.word.__w / 2, "Upgrade runs under the next icon's word")
  c.casts = {}
  c.click(b)
  assert(c.casts[1] and c.casts[1].spell == 10952, "the click casts 10952")
  me.auras = { { id = 10952, src = "player", exp = c.clock + 600, dur = 600 } }
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  assert(not find(shown(c, "mine"), "self:innerfire"), "rank 6 on: nothing")
  -- (gone, the same icon asks Buff again in its own column)
  me.auras = {}
  fire(c, "UNIT_AURA", "player"); tick(c, 1)
  assert(find(shown(c, "mine"), "self:innerfire").word == "Buff" and b:IsShown() and b.word.__w == 38, "Buff, its column back to 38: " .. b.word.__w)
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
  assert(rec and rec.word == "Upgrade" and rec.click.spell == "Dampen Magic" and rec.click.unit == "player", "Upgrade, by the name: " .. tostring(rec and rec.word))
  local b = icon(c, "own", "habit:Dampen Magic")
  assert(b:GetAttribute("spell") == "Dampen Magic", "the secure button casts the name: the game's highest rank")
  FITS(b.word, "Upgrade under the habit")
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
  assert(rec and rec.word == "Upgrade", "rank 3 learned, rank 2 on: Upgrade again: " .. tostring(rec and rec.word))
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
  assert(rec and rec.word == "Upgrade", "the elixir's aura and your rank 1, rank 2 known: your rank's Upgrade: " .. keysOf(shown(c, "mine")))
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
  assert(find(shown(c, "mine"), "self:innerfire").word == "Upgrade", "rank 5 on, rank 6 known: Upgrade")
  never(icon(c, "own", "self:innerfire"), "Never: Upgrade Inner Fire")
  local set = c.A.Settings().never
  assert(set["up:Inner Fire"] and set["buff:innerfire"] == nil and not find(shown(c, "mine"), "self:innerfire"), "its own key (the spell's), the Upgrade gone")
  on({})
  local rec = find(shown(c, "mine"), "self:innerfire")
  assert(rec and rec.word == "Buff", "Inner Fire gone: Buff still asked: " .. tostring(rec and rec.word))
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
  assert(find(shown(d, "mine"), "habit:Dampen Magic").word == "Upgrade", "rank 1 on, rank 2 known: Upgrade")
  d.A.Bar.Menu(icon(d, "own", "habit:Dampen Magic"))
  local chose = false
  for _, e in ipairs(d.menus[#d.menus]) do if e.text == "Never: Upgrade Dampen Magic" then e.fn(); chose = true end end
  assert(chose, "the menu has Never: Upgrade Dampen Magic")
  tick(d, 1)
  assert(d.A.Settings().never["up:Dampen Magic"] and not find(shown(d, "mine"), "habit:Dampen Magic"), "the Upgrade gone, its own key")
  mg.auras = {}
  fire(d, "UNIT_AURA", "player"); tick(d, 1)
  rec = find(shown(d, "mine"), "habit:Dampen Magic")
  assert(rec and rec.word == "Buff", "Dampen Magic gone: Buff still asked: " .. tostring(rec and rec.word))
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
  assert(rec and rec.word == "Upgrade" and rec.click.spell == 10432, "rank 6 on: Upgrade to 10432: " .. tostring(rec and rec.click and rec.click.spell))
  assert(rec.why == "Rank 6 on you; you know rank 7.", rec.why)
  on({ { id = 10432, src = "player", exp = c.clock + 600, dur = 600 } })
  assert(not find(shown(c, "mine"), "self:shield"), "rank 7 on: nothing")
  on({})
  rec = find(shown(c, "mine"), "self:shield")
  assert(rec and rec.word == "Buff" and rec.click.spell == 10432, "none on: the Buff casts rank 7: " .. tostring(rec and rec.click and rec.click.spell))
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
  assert(rec and rec.word == "Upgrade" and rec.click.spell == 7301, "Frost Armor 2 on: Upgrade to 3: " .. tostring(rec and rec.word))
  c.A.Bar.Menu(icon(c, "own", "self:armor"))
  local chose = false
  for _, e in ipairs(c.menus[#c.menus]) do if e.text == "Never: Upgrade Frost Armor" then e.fn(); chose = true end end
  assert(chose, "the menu has Never: Upgrade Frost Armor")
  tick(c, 1)
  assert(c.A.Settings().never["up:Frost Armor"] and not find(shown(c, "mine"), "self:armor"), "the Upgrade gone, by the spell's key")
  on(7302)
  rec = find(shown(c, "mine"), "self:armor")
  assert(rec and rec.word == "Upgrade" and rec.click.spell == 7320 and rec.neverName == "Upgrade Ice Armor",
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
  assert(d.A.Settings().never["up:Frost Armor"] and rec and rec.word == "Upgrade" and rec.click.spell == 11735,
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
  for i, x in ipairs({ { 13447, 17535 }, { 9179, 11396 }, { 13454, 17539 } }) do
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

print(string.format("OK (%d scenarios)", passed))
