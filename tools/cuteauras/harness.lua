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
SetAttribute GetAttribute SetCooldown SetHideCountdownNumbers SetShadowOffset SetShadowColor GetFrameLevel IsProtected GetRight GetBottom]]):gmatch("%S+") do METHODS[m] = true end
local PROTECTED_CALL = { Show = true, Hide = true, SetShown = true, SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
  SetSize = true, SetWidth = true, SetHeight = true, SetAttribute = true, SetParent = true, SetScale = true, EnableMouse = true,
  StopMovingOrSizing = true, StartMoving = true }

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
      elseif k == "SetAlpha" then self.__alpha = a[1]
      elseif k == "GetAlpha" then return self.__alpha
      elseif k == "SetScale" then self.__scale = a[1]
      elseif k == "GetScale" then return self.__scale
      elseif k == "GetEffectiveScale" then return self.__scale
      elseif k == "GetCenter" then return 800, 500
      elseif k == "GetTop" then return 700
      elseif k == "GetName" then return self.__name
      elseif k == "GetParent" then return self.__parent
      elseif k == "IsProtected" then return self.__secure or self.__protected or false
      elseif k == "SetCooldown" then self.__cd = { a[1], a[2] }
      elseif k == "GetFont" then return "Fonts\\FRIZQT__.TTF", 12
      elseif k == "RegisterEvent" then self.__client.events[a[1]] = self.__client.events[a[1]] or {}; self.__client.events[a[1]][self] = true
      elseif k == "RegisterUnitEvent" then
        local ev = a[1]
        self.__client.events[ev] = self.__client.events[ev] or {}
        self.__client.events[ev][self] = { select(2, ...) }
      elseif k == "SetAttribute" then
        local name, v = a[1], a[2]
        local was = self.__attrs[name]
        self.__attrs[name] = v
        if self.__scripts.OnAttributeChanged and was ~= v then self.__scripts.OnAttributeChanged(self, name, v) end
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
  local h = {}
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
           UnitIsDead = function(u) return c.units[u] and c.units[u].dead or false end }
end

----------------------------------------------------------------------------
-- a client
----------------------------------------------------------------------------
local WORLD
local CLASS_NAME = { PRIEST = "Priest", PALADIN = "Paladin", MAGE = "Mage", WARRIOR = "Warrior", ROGUE = "Rogue", DRUID = "Druid",
  HUNTER = "Hunter", SHAMAN = "Shaman", WARLOCK = "Warlock" }
local SPELL_NAMES, SPELL_DESC = {}, {}
local AREA_NAMES = { [1] = "Dun Morogh", [618] = "Winterspring", [12] = "Elwynn Forest", [40] = "Westfall", [10] = "Duskwood", [139] = "Eastern Plaguelands" }

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
  env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  env.LOCALIZED_CLASS_NAMES_MALE = CLASS_NAME
  env.UISpecialFrames = {}
  env.SlashCmdList = {}
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.chat[#c.chat + 1] = m end }
  env.Enum = { TooltipDataLineType = { ErrorLine = 22, ItemSpellTriggerLearn = 15 }, SendAddonMessageResult = { Success = 0, AddOnMessageLockdown = 11 },
               WeaponSlot = { MainHand = 0, OffHand = 1 }, AddOnRestrictionType = { Combat = 1, Encounter = 2 } }
  env.Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
  env.SOUNDKIT = { RAID_WARNING = 8959 }
  env.PlaySound = function(k) c.sounds = (c.sounds or 0) + 1 end
  env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2
  env.NUM_BAG_SLOTS = 4
  env.InCombatLockdown = function() return c.combat end
  env.UnitAffectingCombat = function() return c.combat end
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
        if button ~= "LeftButton" then return end
        local useDown = self.__attrs.useOnKeyDown
        if useDown == nil then useDown = c.keyDown ~= false end
        if not ((down and useDown) or (not down and not useDown)) then return end
        local ty = self.__attrs.type1 or self.__attrs.type
        if ty then c.casts[#c.casts + 1] = { type = ty, spell = self.__attrs.spell, item = self.__attrs.item, macro = self.__attrs.macrotext,
          unit = self.__attrs.unit, slot = self.__attrs["target-slot"], from = self.__name } end
      end
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
    local fn = assert(loadstring("local " .. signature:gsub("%.%.%.", "_v") .. " = ...\n" .. body, "snippet"))
    header.__env = header.__env or sandbox(c)
    header.__env.control = handle(c, header)
    setfenv(fn, header.__env)
    return fn(handle(c, selfFrame), ...)
  end
  env.SecureHandlerSetFrameRef = function(f, label, ref) f.__attrs["frameref-" .. label] = ref end
  env.SecureHandlerWrapScript = function(f, script, header, pre, post)
    if c.combat then error("ADDON_ACTION_BLOCKED: a wrap in a fight", 2) end
    for _, s in ipairs({ pre, post }) do assert(not (s and s:find("{", 1, true)), "a restricted snippet with a table constructor") end
    f.__wraps = f.__wraps or {}
    f.__wraps[script] = { header = header, pre = pre, post = post }
  end
  env.RegisterStateDriver = function(f, state, cond)
    if c.combat then error("ADDON_ACTION_BLOCKED: RegisterStateDriver in a fight", 2) end
    c.drivers[f] = c.drivers[f] or {}
    c.drivers[f][state] = { cond = cond }
    c.resolveDrivers()
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
        if d.value ~= v then
          d.value = v
          c.restricted = true
          -- (the game's driver hands a number where the value reads as one: SecureStateDriver.lua's tonumber)
          if state == "visibility" then if v == "show" then f:Show() else f:Hide() end
          else f:SetAttribute("state-" .. state, tonumber(v) or v) end
          c.restricted = false
        end
      end
    end
  end
  -- a click as the game does it: a wrap's pre snippet, the button's own and hooked OnClick, the wrap's post snippet
  -- (both edges of a click, each the button heard (RegisterForClicks), each running a wrap's snippets as the game does)
  function c.click(f, button)
    button = button or "LeftButton"
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
  end
  function c.hover(f)
    local w = f.__wraps and f.__wraps.OnEnter
    if w then c.runSnippet(w.header, w.pre, "self", f) end
    if f.__scripts.OnEnter then f.__scripts.OnEnter(f) end
  end
  env.GameTooltip = { SetOwner = function(self, o) self.owner = o; self.lines = {} end, SetText = function(self, t) self.lines = { t } end,
    AddLine = function(self, t) self.lines = self.lines or {}; self.lines[#self.lines + 1] = t end, Show = function() end, Hide = function(self) self.owner = nil end,
    GetOwner = function(self) return self.owner end }
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
  env.UnitOnTaxi = function() return false end
  env.UnitInVehicle = function() return false end
  env.UnitHasVehicleUI = function() return false end
  env.IsSwimming = function() return c.swimming or false end
  env.IsSubmerged = function() return false end
  env.IsAltKeyDown = function() return false end
  env.CanInspect = function() return false end
  env.UnitCastingInfo = function() return nil end
  env.UnitChannelInfo = function() return nil end
  -- auras
  env.C_Secrets = { ShouldAurasBeSecret = function() return c.combat end, ShouldSpellAuraBeSecret = function(id) return c.combat and not c.plainAuras[id] end,
    ShouldUnitIdentityBeSecret = function() return false end }
  env.C_UnitAuras = {
    GetAuraDataByIndex = function(u, i, filter)
      local x = U(u)
      local a = x and x.auras and x.auras[i]
      if not a then return nil end
      if c.combat then return { name = secret(), spellId = secret(), applications = secret(), expirationTime = secret(), sourceUnit = secret(), duration = secret() } end
      return { name = a.name or SPELL_NAMES[a.id] or ("Aura " .. a.id), spellId = a.id, applications = a.n or 1, expirationTime = a.exp or 0,
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
    IsSpellInRange = function(id, u) local x = U(u); if not x then return nil end return x.far and false or true end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
  -- items and bags
  local function item(id) return c.items[id] or {} end
  env.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemID = function(bag, slot) for _, b in ipairs(c.bags) do if b.bag == bag and b.slot == slot then return b.id end end return nil end,
    GetContainerItemCooldown = function(bag, slot) for _, b in ipairs(c.bags) do if b.bag == bag and b.slot == slot then return b.cdStart or 0, b.cd or 0, 1 end end return 0, 0, 1 end,
    GetItemCooldown = function(id) for _, b in ipairs(c.bags) do if b.id == id then return b.cdStart or 0, b.cd or 0, 1 end end return 0, 0, 1 end,
  }
  env.C_Item = {
    GetItemCount = function(id) local n = 0; for _, b in ipairs(c.bags) do if b.id == id then n = n + (b.count or 1) end end return n end,
    GetItemInfo = function(id) local it = item(id); return it.name or ("Item " .. id), nil, 2, it.ilvl or 10, it.minLevel or 0, nil, nil, 1, it.equipLoc or "", 1, it.price or 1 end,
    GetItemInfoInstant = function(id) local it = item(id); return id, nil, nil, it.equipLoc or "", 1, it.classID or 15, it.subID or 0 end,
    IsEquippableItem = function(id) return (item(id).equipLoc or "") ~= "" end,
    GetItemSpell = function(id) local it = item(id); if it.spell then return "Use", it.spell end return nil end,
    GetItemIconByID = function(id) return 200000 + id % 1000 end,
    IsUsableItem = function(id) return item(id).usable ~= false end,
    EquipItemByName = function(id, slot) c.equips[#c.equips + 1] = { id, slot } end,
  }
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
  env.C_Traits = { GetConfigInfo = function() return { treeIDs = { 9 } } end,
    GetGroupDisplayInfoByTreeID = function() return { { groupID = 1, skillLineID = c.o.spec or 0 }, { groupID = 2, skillLineID = 1 } } end,
    GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 1, currencyInfos = { { spent = 31 } } }, { traitNodeGroupID = 2, currencyInfos = { { spent = 5 } } } } end }
  -- places
  env.GetZoneText = function() return c.zone end
  env.GetRealZoneText = function() return c.zone end
  env.GetSubZoneText = function() return c.subzone end
  env.GetMinimapZoneText = function() return c.subzone ~= "" and c.subzone or c.zone end
  env.C_Map = { GetAreaInfo = function(id) return AREA_NAMES[id] end }
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
      for _, sp in ipairs(e.one or { e }) do for _, id in ipairs(sp.ranks) do SPELL_NAMES[id] = sp.name end end
      for _, id in ipairs(e.group or {}) do SPELL_NAMES[id] = e.groupName end
    end
  end
  for _, e in pairs(D.BLESS) do for _, id in ipairs(e.ranks) do SPELL_NAMES[id] = e.name end; for _, id in ipairs(e.group or {}) do SPELL_NAMES[id] = e.groupName end end
  for _, e in pairs(D.HANDS) do for _, id in ipairs(e.ranks) do SPELL_NAMES[id] = e.name end end
  SPELL_NAMES[1283391], SPELL_NAMES[1229741], SPELL_NAMES[1229739] = "Campfire Nearby", "Camp Benefits", "Welcoming Campfire"
  SPELL_DESC[1306908] = "Movement speed increased by 3% in Snowy areas."
  HARNESS_DATA = D
end
local D = HARNESS_DATA

local function member(o)
  o.guid = o.guid or ("Player-1-" .. o.name)
  o.auras = o.auras or {}
  return o
end
local function knowAll(c, class, level)
  for _, e in ipairs(D.BUFFS[class] or {}) do
    for _, sp in ipairs(e.one or { e }) do for i, id in ipairs(sp.ranks) do if (sp.levels[i] or 0) <= level then c.known[id] = true end end end
    for i, id in ipairs(e.group or {}) do if (e.groupLevels[i] or 0) <= level then c.known[id] = true end end
  end
  if class == "PALADIN" then
    for _, e in pairs(D.BLESS) do for i, id in ipairs(e.ranks) do if e.levels[i] <= level then c.known[id] = true end end end
    for _, e in pairs(D.HANDS) do for i, id in ipairs(e.ranks) do if e.levels[i] <= level then c.known[id] = true end end end
  end
end
local function noErrors(c, label)
  if #c.A.errors > 0 then error((label or "") .. ": the addon caught errors:\n  " .. table.concat(c.A.errors, "\n  "), 2) end
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
  -- with the aura on, it goes
  table.insert(me.auras, { id = 2791, src = "player", exp = c.clock + 3600, dur = 3600 })
  table.insert(me.auras, { id = 7128, src = "player", exp = c.clock + 600, dur = 600 })
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
  c.casts = {}
  c.click(rb)
  assert(#c.casts == 1 and c.casts[1].unit == unit, "the click cast on the rogue")
  assert(not rb:IsShown(), "the rogue owed one spell from this priest: done")
  -- a second death: the warrior, owed Fortitude and Divine Spirit? (no mana: Fortitude only)
  g.WAR.dead = true; tickAll(1); g.WAR.dead = false; tickAll(1)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.WAR, "the warrior next")
  c.click(rb)
  assert(not rb:IsShown(), "the warrior done")
  -- the other priest, owed Fortitude and Divine Spirit: one click each, neither skipped (a click is one edge)
  g.P2.dead = true; tickAll(1); g.P2.dead = false; tickAll(1)
  assert(rb:IsShown() and rb:GetAttribute("spell") == 10937, "Fortitude first")
  c.casts = {}
  c.click(rb)
  assert(rb:IsShown() and c.units[rb:GetAttribute("unit")] == g.P2 and rb:GetAttribute("spell") ~= 10937, "then Divine Spirit: " .. tostring(rb:GetAttribute("spell")))
  c.click(rb)
  assert(#c.casts == 2 and not rb:IsShown(), "two casts, two clicks, done")
  fight(c, false); fight(g.c2, false)
  tickAll(2)
  assert(not rb:IsShown(), "after the fight the queue is cleared")
  -- dying and coming back out of a fight queues nothing (the bar reads auras then)
  g.ROG.dead = true; tickAll(1); g.ROG.dead = false; tickAll(1)
  assert(not rb:IsShown(), "out of a fight: no card")
  for _, x in ipairs({ g.c1, g.c2, g.c3 }) do noErrors(x, "rebuff") end
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
  c.equipped[inv] = 249469
  c.bags[1] = { id = old, bag = 0, slot = 1 }
  fire(c, "PLAYER_EQUIPMENT_CHANGED"); fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 2)
  assert(#shown(c, "gear") == 0, "worn here: nothing")
  -- leave the snow
  c.zone = "Elwynn Forest"
  fire(c, "ZONE_CHANGED_NEW_AREA")
  tick(c, 2)
  local back = shown(c, "gear")[1]
  assert(back and back.kind == "back" and back.click.macro:find("item:" .. old, 1, true), "the old piece back on")
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

test("the test alerts and Move mode draw without errors", function()
  local me = member({ name = "Tester", class = "DRUID", level = 30 })
  local c = client({ me = me })
  load(c)
  c.A.Alerts.Test()
  tick(c, 2)
  assert(c.A.Alerts.Has("test:hand") and c.A.Alerts.Has("test:swap"), "the test cards")
  c.A.Settings_.Move(true)
  c.A.Settings_.Move(true)
  tick(c, 16)
  assert(not c.A.Alerts.Has("test:rebuff"), "they go")
  c.env.SlashCmdList.CUTEAURAS("diag")
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
  for _ = 1, 20 do c.A.Bar.Refresh() end -- (the pools filled once)
  collectgarbage("collect")
  local before = collectgarbage("count")
  local t0 = os.clock()
  local timers0 = #c.timers
  for _ = 1, 50 do c.A.Bar.Refresh() end
  local per = (os.clock() - t0) / 50 * 1000
  print("    timers queued by 50 refreshes: " .. (#c.timers - timers0))
  collectgarbage("collect")
  local after = collectgarbage("count")
  print(string.format("    raid of 40: a full refresh %.2f ms in the mock, memory %+.0f KB after 50", per, after - before))
  assert(after - before < 40, "memory grows with refreshes: " .. (after - before) .. " KB")
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

print(string.format("OK (%d scenarios)", passed))
