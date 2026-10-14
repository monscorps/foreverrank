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
SetFontObject SetFont GetFont SetTextColor SetJustifyH SetJustifyV SetWordWrap GetStringWidth GetUnboundedStringWidth GetStringHeight
SetAutoFocus HighlightText SetFocus ClearFocus SetMultiLine SetChecked GetChecked SetMaxLetters HasFocus IsEnabled SetRotation RegisterUnitEvent
SetAtlas SetPassThroughButtons SetCooldown SetHideCountdownNumbers SetScale GetScale GetLeft GetTop GetChildren GetNumPoints SetUserPlaced GetZoom SetZoom GetZoomLevels SetStartPoint SetEndPoint SetThickness GetFrameLevel CreateLine SetTextInsets SetAttribute GetAttribute CreateMaskTexture AddMaskTexture SetGradient]])
local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }
-- a PlayerModel's own: the creature it shows, by display id or by NPC id, its camera, and whether it keeps the model
-- while hidden
local MODEL = { SetDisplayInfo = true, SetCreature = true, SetPortraitZoom = true, ClearModel = true, SetKeepModelOnHide = true }
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
  -- Forever's red X: 24 px of art edge to edge (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml); the 32 px padded one
  -- was Classic's
  if template == "UIPanelCloseButton" then o.__w, o.__h = 24, 24 end
  ALL[#ALL + 1] = o
  local mt = {}
  mt.__index = function(t, k)
    if METHODS[k] or (BACKDROP[k] and t.__backdrop) or (MODEL[k] and kind == "PlayerModel") then
      return function(self, ...)
        local a = { ... }
        local n = select("#", ...)
        if k == "SetScript" then self.__scripts[a[1]] = a[2]
        elseif k == "GetScript" then return self.__scripts[a[1]]
        elseif k == "HookScript" then local old = self.__scripts[a[1]]; self.__scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
        elseif k == "CreateTexture" then local x = newObj("Texture", nil, self); x.__layer = a[2] or "ARTWORK"; return x
        elseif k == "CreateFontString" then local x = newObj("FontString", nil, self); x.__layer = a[2] or "OVERLAY"; return x
        elseif k == "CreateLine" then local x = newObj("Line", nil, self); x.__layer = a[2] or "ARTWORK"; return x
        elseif k == "CreateMaskTexture" then local x = newObj("Texture", nil, self); x.__layer = "MASK"; return x
        elseif k == "AddMaskTexture" then self.__mask = a[1]
        elseif k == "SetStartPoint" then self.__start = { a[1], a[2], a[3], a[4] }
        elseif k == "SetEndPoint" then self.__stop = { a[1], a[2], a[3], a[4] }
        elseif k == "GetZoom" then return self.__zoom or 0
        elseif k == "SetZoom" then self.__zoom = a[1]
        elseif k == "GetZoomLevels" then return 6
        elseif k == "GetFrameLevel" then return self.__level or 2
        elseif k == "Show" then local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
        elseif k == "Hide" then local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
        elseif k == "SetShown" then if a[1] then self:Show() else self:Hide() end
        elseif k == "IsShown" or k == "IsVisible" then return self.__shown
        -- (a size set now is what the game reports at once; the last layout's is stale)
        elseif k == "SetSize" then self.__w, self.__h = a[1], a[2] or a[1]; self.__wset, self.__hset = true, true; self.__rw, self.__rh = nil, nil
        elseif k == "SetWidth" then self.__w = a[1]; self.__wset = true; self.__rw = nil
        elseif k == "SetHeight" then self.__h = a[1]; self.__hset = true; self.__rh = nil
        elseif k == "GetWidth" then return self.__rw or self.__w
        elseif k == "GetHeight" then return self.__rh or self.__h
        elseif k == "SetText" then self.__text = a[1] == nil and "" or tostring(a[1])
        elseif k == "GetText" then return self.__text
        elseif k == "GetStringWidth" or k == "GetUnboundedStringWidth" then return textWidth(self.__text, self.__size)
        elseif k == "GetStringHeight" then return self.__size + 2
        elseif k == "GetFont" then return "Fonts\\FRIZQT__.TTF", self.__size, ""
        elseif k == "SetFont" then self.__size = a[2] or self.__size
        elseif k == "SetFontObject" then self.__size = a[1] and a[1].__fontSize or 12
        elseif k == "SetJustifyH" then self.__justify = a[1]
        elseif k == "SetWordWrap" then self.__wrap = a[1] and true or false
        elseif k == "SetTextColor" then self.__color = { a[1], a[2], a[3] }
        elseif k == "SetAlpha" then self.__alpha = a[1]
        elseif k == "GetAlpha" then return self.__alpha
        elseif k == "SetAttribute" then self.__attr = self.__attr or {}; self.__attr[a[1]] = a[2]
        elseif k == "GetAttribute" then return self.__attr and self.__attr[a[1]]
        elseif k == "SetMinMaxValues" then self.__min, self.__max = a[1], a[2]
        elseif k == "GetMinMaxValues" then return self.__min, self.__max
        elseif k == "SetValue" then self.__value = a[1]; if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, a[1]) end
        elseif k == "GetValue" then return self.__value
        elseif k == "GetCenter" then return 500, 400
        elseif k == "GetEffectiveScale" then return 1
        elseif k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0
        elseif k == "GetName" then return self.__name
        elseif k == "GetParent" then return self.__parent
        elseif k == "SetParent" then self.__parent = a[1]
        elseif k == "SetTexture" then self.__tex = a[1]; self.__color = nil; self.__atlas = nil
        elseif k == "SetAtlas" then self.__atlas = a[1]; self.__tex = "atlas:" .. tostring(a[1])
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
        elseif k == "GetScale" then return self.__scale or 1
        elseif k == "SetCooldown" then self.__cd = { a[1], a[2] }
        elseif k == "SetDisplayInfo" then self.__display, self.__creature = a[1], nil
        elseif k == "SetCreature" then self.__creature, self.__display = a[1], nil
        elseif k == "SetPortraitZoom" then self.__portraitZoom = a[1]
        elseif k == "ClearModel" then self.__display, self.__creature = nil, nil
        elseif k == "SetKeepModelOnHide" then self.__keepModel = a[1]
        elseif k == "GetLeft" then return self.__left or 0
        elseif k == "GetTop" then return self.__top or 0
        elseif k == "GetNumPoints" then return #self.__points
        elseif k == "GetChildren" then
          local out = {}
          for _, x in ipairs(ALL) do if x.__parent == self and x.__kind ~= "Texture" and x.__kind ~= "FontString" and x.__kind ~= "Line" then out[#out + 1] = x end end
          return unpack(out)
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
-- the client draws a creature's portrait from its display id into a texture. PORTRAIT.defer: as in the game, the
-- picture comes later: the texture stays empty until the portraits are ready (a test then fires PORTRAITS_UPDATED)
local PORTRAIT = { defer = false, ready = false, calls = 0 }
BASE.SetPortraitTextureFromCreatureDisplayID = function(t, id)
  PORTRAIT.calls = PORTRAIT.calls + 1
  if PORTRAIT.defer and not PORTRAIT.ready then t.__tex, t.__portrait = nil, nil; return end
  t.__tex = "portrait:" .. tostring(id); t.__portrait = id
end
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
  -- the minimap in its cluster and container, as the client builds it (Blizzard_Minimap/Mainline/Minimap.xml)
  env.MinimapCluster = newObj("Frame", nil, env.UIParent); env.MinimapCluster:SetSize(256, 256)
  env.MinimapCluster.__left, env.MinimapCluster.__top = 1344, 1000
  rawset(env.MinimapCluster, "ApplySystemAnchor", function(self) self.__anchored = true end) -- Edit Mode's own (a mixin method)
  env.MinimapCluster.MinimapContainer = newObj("Frame", nil, env.MinimapCluster); env.MinimapCluster.MinimapContainer:SetSize(215, 226)
  env.Minimap = newObj("Frame", nil, env.MinimapCluster.MinimapContainer); env.Minimap:SetSize(140, 140); env.Minimap.__points = {}
  env.Minimap:SetPoint("TOPRIGHT", env.UIParent, "TOPRIGHT", -20, -20)
  -- the minimap's tracking list: c.tracking = { { name, filterID, active }, ... }; the game's menu, as Menu.ModifyMenu sees it
  c.tracking = { { name = "Battlemaster", filterID = 4, active = false }, { name = "Target", filterID = 16384, active = false },
                 { name = "Focus", filterID = 32768, active = false } }
  -- professions: c.profs = { { name, skill }, ... } (two crafts, then fishing, cooking, first aid as the game lists them)
  env.GetProfessions = function() local p = c.profs or {}; return p[1] and 1 or nil, p[2] and 2 or nil, nil, p[3] and 3 or nil, p[4] and 4 or nil, p[5] and 5 or nil end
  env.GetProfessionInfo = function(i) local p = (c.profs or {})[i]; if not p then return nil end return p[1], 0, p[2], 300, 0, 0, 0, 0 end
  env.UnitOnTaxi = env.UnitOnTaxi or function() return c.taxi or false end
  env.C_Minimap = { GetViewRadius = function() return c.miniRadius or 233.33 end,
    GetNumTrackingTypes = function() return #c.tracking end,
    GetTrackingFilter = function(i) local t = c.tracking[i]; return t and { filterID = t.filterID } or nil end,
    GetTrackingInfo = function(i) local t = c.tracking[i]; return t and { name = t.name, active = t.active, texture = 0, type = "other" } or nil end,
    SetTracking = function(i, on) local t = c.tracking[i]; if t then t.active = on and true or false end end }
  env.Enum = env.Enum or {}
  env.C_CVar = { GetCVarBool = function(name) return (c.cvars or {})[name] == "1" end }
  c.menus = {}
  env.Menu = { ModifyMenu = function(tag, fn) c.menus[tag] = fn end }
  c.cvars = c.cvars or {}
  env.GetCVar = env.GetCVar or function(name) return (c.cvars or {})[name] end
  -- c.cvarChanges: { name, value, statusTextDisplay then } for each real change, the ones the client fires CVAR_UPDATE
  -- for (setting a CVar to the value it has fires nothing)
  env.SetCVar = function(name, v)
    c.cvars = c.cvars or {}
    v = tostring(v)
    if c.cvars[name] ~= v then c.cvarChanges = c.cvarChanges or {}; table.insert(c.cvarChanges, { name, v, c.cvars.statusTextDisplay }) end
    c.cvars[name] = v
  end
  -- soft targeting: c.soft = { name, plate } is the object the Interact key would use
  env.UnitExists = env.UnitExists or function(unit)
    if unit == "softinteract" then return c.soft ~= nil end
    local i = unit and unit:match("^party(%d)$")
    if i then return (c.party or {})[tonumber(i)] ~= nil end
    return true
  end
  env.C_NamePlate = { GetNamePlateForUnit = function(unit) if unit == "softinteract" and c.soft then return c.soft.plate end return nil end }
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
    -- where it was made, for the edge check's messages: the line that called CreateFrame and the one above it
    local where = {}
    for lvl = 2, 3 do
      local info = debug.getinfo(lvl, "Sl")
      if info and info.currentline and info.currentline > 0 then where[#where + 1] = info.short_src:match("[^/]+$") .. ":" .. info.currentline end
    end
    f.__where = table.concat(where, " < ")
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
  -- the client's event registry, as far as chat links use it: a clicked addon link fires "SetItemRef"
  env.EventRegistry = { cbs = {},
    RegisterCallback = function(self, event, fn, owner) self.cbs[event] = self.cbs[event] or {}; table.insert(self.cbs[event], { fn, owner }) end,
    TriggerEvent = function(self, event, ...) for _, cb in ipairs(self.cbs[event] or {}) do cb[1](cb[2], ...) end end }
  env.GetTime = function() return c.clock end
  local t0 = os.time()
  env.time = function() return t0 + math.floor(c.clock - 1000) end
  env.IsShiftKeyDown = function() return c.shift end
  env.GetBindLocation = function() return o.bind or "Stormwind City" end
  env.IsPlayerSpell = function() return o.riding or false end
  env.AuraUtil = { FindAuraByName = function(name) if c.rested and name == "Well Rested" then return name end end }
  -- the party as the game shows it: c.party = { { name, class file, level, pos = { inst, wx, wy } }, ... } (party1..)
  local function partyOf(unit) local i = unit and unit:match("^party(%d)$"); return i and (c.party or {})[tonumber(i)] end
  env.UnitName = function(unit)
    if unit == "npc" then return c.npcName end
    if unit == "softinteract" then return c.soft and c.soft.name end
    local pm = partyOf(unit); if pm then return pm[1] end
    return o.name
  end
  env.GetNumGroupMembers = function() return c.party and (#c.party + 1) or 0 end
  env.UnitPosition = function(unit)
    local pm = partyOf(unit)
    if pm then return pm.pos and pm.pos.wy, pm.pos and pm.pos.wx, 0, pm.pos and pm.pos.inst end
    if unit == "player" then return (c.pos or {}).wy or 100, (c.pos or {}).wx or 100, 0, (c.pos or {}).inst or 0 end
    return nil
  end
  c.pushed = {}
  env.QuestLogPushQuest = function(index) c.pushed[#c.pushed + 1] = index end
  env.UnitGUID = function(unit)
    if unit == "npc" then return c.npcGUID end
    if unit == "softinteract" then return c.soft and (c.soft.guid or "GameObject-0-4455-0-12-2843-0000A1B2C3") or nil end
    return "Player-1234-" .. string.format("%08X", #o.name * 7919 + (o.level or 1))
  end
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
  env.IsAltKeyDown = function() return c.alt or false end
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
    GetAuraDataByIndex = function(unit, i, filter)
      if filter == "HELPFUL" and c.buffs then local n = c.buffs[i]; return n and { name = n, spellId = 0 } or nil end
      local a = (c.auras or {})[i]; return a and { spellId = a } or nil
    end,
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
  env.UnitLevel = function(unit) local pm = partyOf(unit); if pm then return pm[3] end return c.level or o.level end
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
  env.UnitClass = function(unit) local pm = partyOf(unit); if pm then return pm[2], pm[2], 0 end return o.className, o.class, o.classID end
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
    -- c.itemName[id] (a secret one, say), c.unloaded[id] = not in the client's cache yet, c.itemLevel[id] (27 by default)
    GetItemInfo = function(id)
      if c.unloaded[id] then return nil end
      return c.itemName[id] or ("Item " .. id), "|cffffffff|Hitem:" .. id .. "::::::::20:::::::|h[Item " .. id .. "]|h|r", c.itemQuality[id],
        c.itemLevel[id] or 27, 22, "Armor", "Cloth", 1, "INVTYPE_CHEST", 133328, 815, c.itemClass[id] or 4, 1, 1, 0, nil
    end,
    RequestLoadItemDataByID = function(id) c.loadRequests[#c.loadRequests + 1] = id end,
  }
  c.itemClass, c.itemQuality, c.itemName, c.unloaded, c.loadRequests, c.itemLevel = {}, {}, {}, {}, {}, {}
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
  -- the loot window and a vendor's wares: c.loot = { id, ... }, c.merchant = { id, ... }. For the drop-source notes
  -- (Loot.lua) a loot entry may be a table { id, src = { { guid, qty }, ... }, q = quality, quest = bool, questID = n,
  -- kind = 1 item, 2 money, 3 currency }; c.lootSrc is the whole window's source when an entry names none
  c.loot, c.merchant = {}, {}
  env.GetNumLootItems = function() return #c.loot end
  env.GetLootSlotLink = function(i)
    local e = c.loot[i]
    local id = type(e) == "table" and e.id or e
    return id and ("|cff1eff00|Hitem:" .. id .. "::::::::12:::::::|h[Item " .. id .. "]|h|r") or nil
  end
  env.GetLootSlotType = function(i) local e = c.loot[i]; return type(e) == "table" and e.kind or 1 end
  env.GetLootSlotInfo = function(i)
    local e = c.loot[i]
    if type(e) ~= "table" then return 133328, "Item " .. tostring(e), 1, nil, 2, false, false, nil, false, false end
    return 133328, "Item " .. tostring(e.id), e.n or 1, nil, e.q == nil and 2 or e.q, false, e.quest or false, e.questID, false, e.kind == 2
  end
  env.GetLootSourceInfo = function(i)
    local e = c.loot[i]
    local out = {}
    for _, s in ipairs(type(e) == "table" and e.src or c.lootSrc or {}) do out[#out + 1] = s[1]; out[#out + 1] = s[2] or 1 end
    return unpack(out)
  end
  -- the instance you are in: c.instance = { name, difficultyID, instanceID }; IsInInstance is set per test
  env.GetInstanceInfo = function()
    local I = c.instance or { "none", 0, 0 }
    return I[1], I[1] == "none" and "none" or "party", I[2], "Normal", 5, 0, false, I[3], 5, nil, false
  end
  env.IsFishingLoot = function() return c.fishing or false end
  env.GetMerchantNumItems = function() return #c.merchant end
  env.GetMerchantItemID = function(i) return c.merchant[i] end
  env.C_QuestLog = {
    IsPushableQuest = function(id) return (c.pushable or {})[id] == true end,
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
    -- c.noPos: the client gives no position (the tram, a loading screen)
    GetPlayerMapPosition = function() if c.noPos then return nil end return { x = 0.66, y = 0.62, GetXY = function(self) return self.x, self.y end } end,
    -- c.instWorld[m]: a map inside an instance, on the instance's own continent (not 0 or 1)
    GetWorldPosFromMapPos = function(m)
      if (c.instWorld or {})[m] then return 36, { x = 0, y = 0, GetXY = function(self) return self.x, self.y end } end
      return o.world[1], { x = o.world[2], y = o.world[3], GetXY = function(self) return self.x, self.y end }
    end,
    GetMapRectOnMap = function() return 0.4, 0.6, 0.4, 0.6 end,
    -- zones and cities 3, continents 2, the world 1 (Enum.UIMapType); c.mapTypes overrides one
    GetMapInfo = function(id)
      local kind = (c.mapTypes or {})[id] or ({ [947] = 1, [1414] = 2, [1415] = 2 })[id] or 3
      return { mapID = id, mapType = kind, parentMapID = kind == 3 and 1415 or 947, name = "Map " .. id }
    end,
  }
  env.C_Texture = { GetAtlasInfo = function(name) if (c.noAtlas or {})[name] then return nil end return { file = 1, width = 32, height = 32 } end }
  env.InCombatLockdown = function() return c.combat or false end
  -- flight points (Travel.lua). c.taxiKnown = { [TaxiNodes id] = true }: the world map's flight points this character
  -- has found (nil: the client answers nothing); every flight master of the faction with an id is listed, on its own
  -- map and its continent's (1415, 1414). c.taxiNoContinent: the continent maps answer nothing. c.taxiSecret: ids and
  -- flags are secret values. c.taxiOpen = { map, nodes = { { nodeID, name, state (0 here, 1 can fly, 2 can't), slotIndex } } }:
  -- a flight master's map, open (openTaxi below)
  env.C_TaxiMap = {
    GetTaxiNodesForMap = function(m)
      if c.taxiKnown == nil or (c.taxiNoContinent and (m == 1414 or m == 1415)) then return {} end
      local out = {}
      for _, h in ipairs(c.QB.Data.HUB[o.faction == "Horde" and "H" or "A"]) do
        if h[6] > 0 and (h[7] == m or (m == 1415 and h[2] == 0) or (m == 1414 and h[2] == 1)) then
          out[#out + 1] = { nodeID = c.taxiSecret and SECRET.num() or h[6], name = h[1], faction = 0,
            isUndiscovered = c.taxiSecret and SECRET.bool() or not c.taxiKnown[h[6]], position = env.CreateVector2D(h[8] / 100, h[9] / 100) }
        end
      end
      return out
    end,
    GetAllTaxiNodes = function() return c.taxiOpen and c.taxiOpen.nodes or {} end,
  }
  local function taxiSlot(i) for _, n in ipairs(c.taxiOpen and c.taxiOpen.nodes or {}) do if n.slotIndex == i then return n end end end
  env.GetTaxiMapID = function() return c.taxiOpen and c.taxiOpen.map end
  env.NumTaxiNodes = function() return c.taxiOpen and #c.taxiOpen.nodes or 0 end
  env.TaxiNodeName = function(i) local n = taxiSlot(i); return n and n.name or "INVALID" end
  env.TaxiNodeGetType = function(i) local n = taxiSlot(i); return n and ({ [0] = "CURRENT", [1] = "REACHABLE", [2] = "UNREACHABLE" })[n.state] or "NONE" end
  env.TakeTaxiNode = function(slot) c.took = slot end
  -- a post-hook on a global function (or a table's)
  env.hooksecurefunc = function(a, b, fn)
    local t, name = env, a
    if type(a) == "table" then t, name = a, b else fn = b end
    local old = t[name]
    assert(type(old) == "function", "hooksecurefunc needs a function: " .. tostring(name))
    rawset(t, name, function(...) local r = { old(...) }; fn(...); return unpack(r) end)
  end
  env.UnitIsDeadOrGhost = function() return c.ghost or false end
  env.ERR_NEWTAXIPATH = "New flight path discovered!"
  -- Astral Recall: c.recallCD = when it was cast (15 min)
  env.C_Spell = {
    GetSpellTexture = function(id) return id == 556 and 136010 or 134400 end,
    GetSpellCooldown = function() return { startTime = c.recallCD or 0, duration = c.recallCD and 900 or 0, isEnabled = true, modRate = 1 } end,
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
    GetMapID = function() return map.id end,
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
  -- the game's panel code (UIParentPanelManager, Blizzard_WorldMap): OpenWorldMap shows the map, which puts itself on
  -- the player's zone (c.playerMap, its OnShow); HideUIPanel shuts it. Called by an addon in combat both are blocked
  -- (the red message). c.panelCalls lists the calls
  c.panelCalls = {}
  env.MapUtil = { GetDisplayableMapForPlayer = function() return c.playerMap or 1453 end }
  env.OpenWorldMap = function(mapID)
    c.panelCalls[#c.panelCalls + 1] = "open"
    if c.combat then c.panelBlocked = true; return end
    if not map.shown then map.id = env.MapUtil.GetDisplayableMapForPlayer(); map:Open() end
    if mapID then map:SetMapID(mapID) end
  end
  env.HideUIPanel = function(f)
    c.panelCalls[#c.panelCalls + 1] = "hide"
    if c.combat then c.panelBlocked = true; return end
    if f == env.WorldMapFrame and map.shown then map:Close() end
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

-- travel guidance: a client's faction hub row for a town (one with flights first) and its index
local function hubOf(c, town)
  local best, bi
  for i, h in ipairs(c.QB.Data.HUB[c.o.faction == "Horde" and "H" or "A"]) do
    if h[1] == town and (not best or best[10] ~= 0) then best, bi = h, i end
  end
  assert(best, "a hub called " .. town)
  return best, bi
end
-- the player stands here (every map position is this spot, as the mock's maps go)
local function standAt(c, cont, wx, wy) c.o.world = { cont, wx, wy } end
-- an event to Travel.lua's own frame
local function fireTV(c, event, ...) local f = c.QB.Travel.frame; f.__scripts.OnEvent(f, event, ...) end
-- a flight master's map opens: nodes = { { nodeID, name, state, slotIndex } }, a button for each slot
local function openTaxi(c, nodes, map)
  local env = c.env
  c.taxiOpen = { map = map, nodes = nodes }
  if not env.TaxiFrame then env.CreateFrame("Frame", "TaxiFrame", env.UIParent) end
  env.TaxiFrame:Show()
  for _, n in ipairs(nodes) do
    if not env["TaxiButton" .. n.slotIndex] then env.CreateFrame("Button", "TaxiButton" .. n.slotIndex, env.TaxiFrame) end
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
  -- (the older tests read every place's quests on Available: open them all; the 5.3 block tests the folded default)
  if c.QB.UI then c.QB.UI.allOpen = true; c.QB.UI.longTips = true end
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

-- every button sits well inside QuestBank's window: a page's 6 px or more inside the content panel, the window's own
-- (the sidebar, the header, the close X) 6 px or more inside the window's border. The edge is where the frame's backdrop
-- starts (its insets: 3 px for the panel, 7 for the window). In a scroll view only across counts (down, it scrolls), and
-- nothing reaches past the view's sides. A slider counts its knob where the knob is wider. Every page is checked
local EDGE_GAP = 6
local function interactive(o)
  local k = o.__kind
  return k == "Button" or k == "CheckButton" or k == "EditBox" or k == "Slider" or (k == "Frame" and o.__mouse == true)
end
local function buttonName(o)
  if o.__text and o.__text ~= "" then return plain(o.__text):sub(1, 24) end
  for _, x in ipairs(ALL) do
    if x.__parent == o and x.__kind == "FontString" and x.__text ~= "" then return plain(x.__text):sub(1, 24) end
  end
  return o.__where or "?"
end
local function checkEdges(root, label)
  local out = {}
  local QBx = root.__client and root.__client.QB
  local UI = QBx and QBx.UI
  if not (UI and UI.frame == root and UI.content) then return out end
  local page = {}
  for i, v in ipairs(UI.views or {}) do page[v] = i end
  local panel, win = rectOf(UI.content), rectOf(root)
  for _, o in ipairs(ALL) do
    if o ~= root and o ~= UI.content and not page[o] and interactive(o) and visible(o) then
      local anc = ancestors(o)
      local inRoot, inPanel, clip = false, false, nil
      for _, a in ipairs(anc) do
        if a == root then inRoot = true end
        if a == UI.content then inPanel = true end
        if a.__child and not clip then clip = rectOf(a) end
      end
      local r = inRoot and rectOf(o)
      if r and r.r - r.l > 0 and r.t - r.b > 0 then
        local l, rt = r.l, r.r
        local knob = o.__kind == "Slider" and type(o.__thumb) == "table" and o.__thumb.__w or 0
        if knob > rt - l then local over = (knob - (rt - l)) / 2; l, rt = l - over, rt + over end
        local box, inset, what = win, root.__inset or 0, "window"
        if inPanel then box, inset, what = panel, UI.content.__inset or 0, "page" end
        local sides = { { "left", l - (box.l + inset) }, { "right", (box.r - inset) - rt } }
        if not clip then
          sides[3] = { "top", (box.t - inset) - r.t }
          sides[4] = { "bottom", r.b - (box.b + inset) }
        end
        local msg
        for _, s in ipairs(sides) do
          if s[2] < EDGE_GAP and not msg then
            msg = string.format("[%s '%s'] sits %d px from the %s's %s edge", o.__kind, buttonName(o), math.floor(s[2] + 0.5), what, s[1])
          end
        end
        if not msg and clip and (l < clip.l - 1 or rt > clip.r + 1) then
          msg = string.format("[%s '%s'] reaches past its scroll view", o.__kind, buttonName(o))
        end
        if msg then out[#out + 1] = label .. ": " .. msg end
      end
    end
  end
  return out
end

-- the characters the game's font draws: Friz Quadrata has the Western set (Windows-1252) and draws a hollow box for
-- anything else (a triangle, an arrow, a check). The drawn layout pages can't show this: the browser has the glyph.
-- Colour codes, |T textures|t, |A atlases|a and a link's |H data|h are not drawn as text and are left out
local CP1252 = {}
for _, cp in ipairs({ 0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x017D,
  0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x017E, 0x0178 }) do CP1252[cp] = true end
local function undrawable(str)
  local s = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|h", "")
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local b2, b3, b4 = (s:byte(i + 1) or 0) % 64, (s:byte(i + 2) or 0) % 64, (s:byte(i + 3) or 0) % 64
    local cp, len
    if c < 0x80 then cp, len = c, 1
    elseif c >= 0xF0 then cp, len = (c % 8) * 262144 + b2 * 4096 + b3 * 64 + b4, 4
    elseif c >= 0xE0 then cp, len = (c % 16) * 4096 + b2 * 64 + b3, 3
    elseif c >= 0xC0 then cp, len = (c % 32) * 64 + b2, 2
    else return string.format("a stray byte 0x%02X", c) end
    if not ((cp >= 0x20 and cp <= 0x7E) or cp == 9 or cp == 10 or (cp >= 0xA0 and cp <= 0xFF) or CP1252[cp]) then
      return string.format("U+%04X", cp)
    end
    i = i + len
  end
end

-- a button whose art is cut round: a texture of its own carries a mask
local function round(o)
  if o.__round == nil then
    o.__round = false
    for _, x in ipairs(ALL) do if x.__parent == o and x.__mask then o.__round = true break end end
  end
  return o.__round
end

-- every problem with the window as it is on screen now
local function checkLayout(root, label)
  GEN = GEN + 1
  local problems, texts = {}, {}
  local rootRect = rectOf(root)
  for _, o in ipairs(ALL) do
    -- a button's own label (UIPanelButtonTemplate) is drawn in the same font
    if o.__kind ~= "FontString" and o.__kind ~= "EditBox" and o.__text ~= "" and visible(o) then
      local bad = undrawable(o.__text)
      if bad then
        local inside = false
        for _, a in ipairs(ancestors(o)) do if a == root then inside = true end end
        if inside then problems[#problems + 1] = string.format("%s: [%s '%s'] has %s, which the game's font draws as a box", label, o.__kind, plain(o.__text):sub(1, 40), bad) end
      end
    end
    if o.__kind == "FontString" and o.__text ~= "" and visible(o) then
      local anc = ancestors(o)
      local inside = false
      for _, a in ipairs(anc) do if a == root then inside = true end end
      if inside then
        local bad = undrawable(o.__text)
        if bad then problems[#problems + 1] = string.format("%s: '%s' has %s, which the game's font draws as a box", label, plain(o.__text):sub(1, 40), bad) end
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
          -- a scroll view shows only the part inside it, as it does with text
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
      if a.button or b.button then
        local btn, other = a.button and a or b, a.button and b or a
        for _, x in ipairs(ancestors(other.o)) do if x == btn.o then nested = true end end
        if a.button and b.button then nested = false end
      end
      -- two round buttons (a portrait in a ring, cut round by a mask: the journal's boss pins) touch as circles do
      if not nested and overlap(a.r, b.r, 1.5) and a.button and b.button and round(a.o) and round(b.o) then
        local dx, dy = (a.r.l + a.r.r - b.r.l - b.r.r) / 2, (a.r.t + a.r.b - b.r.t - b.r.b) / 2
        if math.sqrt(dx * dx + dy * dy) >= (a.r.r - a.r.l + b.r.r - b.r.l) / 2 - 1.5 then nested = true end
      end
      if not nested and overlap(a.r, b.r, 1.5) then
        local name = function(t) return t.button and ("[button " .. plain(t.o.__text or ""):sub(1, 20) .. "]") or plain(t.o.__text):sub(1, 40) end
        problems[#problems + 1] = string.format("%s: '%s' overlaps '%s'", label, name(a), name(b))
        if os.getenv("QB_DEBUG_OVERLAP") then print("overlap", a.o.boss and a.o.boss.n, b.o.boss and b.o.boss.n, a.r.l, a.r.t, b.r.l, b.r.t) end
      end
    end
  end
  for _, p in ipairs(checkEdges(root, label)) do problems[#problems + 1] = p end
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
              if o.__tex ~= "color" then it.raw = o.__tex end
              if o.__mask then it.mask = true end
              if o.__atlas then it.atlas = o.__atlas end
              if o.__rot and o.__rot ~= 0 then it.rot = o.__rot end
              if o.__desat then it.desat = true end
              it.c = o.__color or o.__vertex
              it.tc, it.blend, it.desat = o.__tc, o.__blend, o.__desat or nil
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
-- 3.8.0: where you are decides (QB:Opt, settings.profiles) and the decide-yourself key (settings.autoKey)
do
  local set, env = QB:Settings(), owner.env
  assert(set.autoKey == "shift" and type(set.profiles) == "table" and next(set.profiles.party) == nil and set.clock.show == false, "defaults: Shift, no overrides, no strip")
  -- (this character may be held at a cap: that context is left out of the comparisons below)
  local function ctx() local t = {} for _, c in ipairs(QB.Contexts()) do if c ~= "cap" then t[#t + 1] = c end end return table.concat(t, ",") end
  local inGroup, inInst = env.IsInGroup, env.IsInInstance
  env.IsInGroup = function() return false end
  assert(ctx() == "" and QB:Opt("autoAccept") == false, "alone outdoors: no context, the plain setting: " .. ctx())
  env.IsInGroup = function() return true end
  assert(ctx() == "party", "in a group: the party context")
  set.profiles.party.autoAccept = true
  assert(QB:Opt("autoAccept") == true and QB:Opt("autoTurnIn") == false, "the party override, the rest inherited")
  env.IsInInstance = function() return true, "party" end
  set.profiles.dungeon.autoAccept = false
  assert(ctx() == "dungeon,party" and QB:Opt("autoAccept") == false, "a dungeon comes before the party: its override wins")
  env.IsInInstance = function() return true, "pvp" end
  assert(ctx() == "pvp,party", "a battleground is the pvp context")
  env.IsInInstance = function() return SECRET.num(), SECRET.str() end
  assert(ctx() == "party", "a hidden instance answer: no dungeon, no pvp, no error")
  env.IsInInstance = function() return false, "none" end
  env.GetZonePVPInfo = function() return "combat" end
  assert(ctx() == "pvp,party", "a contested zone at war: pvp")
  env.GetZonePVPInfo = nil
  set.profiles.party.clockShow = true
  assert(QB:Opt("clockShow") == true, "the strip can be switched on by context")
  set.profiles.party.clockShow = nil
  assert(QB:Opt("clockShow") == false, "and reads the strip setting otherwise")
  set.profiles.party.autoAccept, set.profiles.dungeon.autoAccept = nil, nil
  env.IsInGroup, env.IsInInstance = inGroup, inInst
  -- the key
  local Auto = QB.Auto
  owner.shift, owner.ctrl = true, false
  assert(Auto.ByHand() == true, "Shift held: by hand")
  set.autoKey = "ctrl"
  assert(Auto.ByHand() == false, "the key is Ctrl now: Shift does nothing")
  owner.ctrl = true
  assert(Auto.ByHand() == true, "Ctrl held: by hand")
  set.autoKey = "none"
  assert(Auto.ByHand() == false, "no key: never by hand")
  set.autoKey = "shift"
  owner.shift, owner.ctrl = false, false
end
-- 3.8.0: timers (Timer.lua): time at each level, time per quest, the strip
do
  local T, env = QB.Timer, owner.env
  assert(T and T.eventFrame and T.QUESTS == 300 and not T.frame, "timers on, the strip not built until asked for")
  local function ev(e, ...) T.eventFrame.__scripts.OnEvent(T.eventFrame, e, ...) end
  local lvl0 = QB.state.level
  ev("PLAYER_ENTERING_WORLD")
  local L = T.DB().levels[lvl0]
  assert(L and L.at and L.played == 0 and T.LevelTime() == 0, "entering the world starts this level's clock")
  tick(owner, 600)
  assert(T.LevelTime() == 600, "ten minutes in: 600 s at this level")
  ev("QUEST_ACCEPTED", 1, 7)
  assert(T.DB().quests[7] and T.DB().quests[7].a and T.QuestTime(7) == 0, "a quest accepted (log index first, the id second)")
  tick(owner, 480)
  local took, done = T.QuestTime(7)
  assert(took == 480 and done == false, "eight minutes in the log")
  ev("QUEST_ACCEPTED", SECRET.num(), SECRET.num())
  ev("QUEST_TURNED_IN", SECRET.num(), 100)
  assert(T.QuestTime(7) == 480, "hidden ids: nothing noted, nothing broken")
  ev("QUEST_TURNED_IN", 7, 250)
  tick(owner, 60)
  took, done = T.QuestTime(7)
  assert(took == 480 and done == true, "handed in: the time it took stays")
  assert(T.Span(45) == "45s" and T.Span(480) == "8m" and T.Span(4320) == "1h 12m", "spans")
  local chat0 = #owner.chat
  ev("PLAYER_LEVEL_UP", lvl0 + 1)
  assert(QB.state.level == lvl0 + 1 and T.DB().levels[lvl0 + 1] and T.LevelTime(lvl0) == 1140 and T.LevelTime() == 0, "a level up: the old level's time is kept, the new one starts")
  assert(#owner.chat == chat0 + 1 and owner.chat[#owner.chat]:find("Level " .. (lvl0 + 1) .. " in 19m of play at level " .. lvl0, 1, true), "the level-up line: " .. tostring(owner.chat[#owner.chat]))
  for i = 1, 310 do ev("QUEST_ACCEPTED", 1, 10000 + i) end
  local n = 0; for _ in pairs(T.DB().quests) do n = n + 1 end
  assert(n == 300 and not T.DB().quests[7], "no more than 300 quests kept; the handed-in one went first")
  -- the strip: off by default, on by setting, on by context, text
  assert(not T.frame, "off: no frame")
  T.Set(true)
  assert(T.frame and T.frame:IsShown() and T.frame.text:GetText():find("Lvl " .. (lvl0 + 1) .. " ", 1, true), "on: the strip shows the level: " .. tostring(T.frame.text:GetText()))
  QB.state.log[10001] = QB.state.log[10001] or {}
  T.Update()
  assert(T.frame.text:GetText():find("quest ", 1, true), "the oldest quest in the log is timed: " .. T.frame.text:GetText())
  QB.state.log[10001] = nil
  tick(owner, 2)
  T.Set(false)
  assert(not T.frame:IsShown() and QB:Settings().clock.show == false, "off again")
  QB:Settings().profiles.party.clockShow = true
  local inGroup = env.IsInGroup
  env.IsInGroup = function() return true end
  ev("GROUP_ROSTER_UPDATE")
  assert(T.frame:IsShown(), "a context profile switches the strip on when you join a group")
  env.IsInGroup = inGroup
  QB:Settings().profiles.party.clockShow = nil
  ev("GROUP_ROSTER_UPDATE")
  assert(not T.frame:IsShown(), "and off again when it no longer applies")
  QB.state.level = lvl0
  T.DB().levels, T.DB().quests = {}, {}
end
-- 3.8.0: chat links (Link.lua): QuestBank's quest links open the quest's menu; an item tooltip names the quests that give it
do
  local L, env = QB.Link, owner.env
  local q = QB.Quest.Get(7)
  assert(q and L.Format(q) == "|cffc6af8d|Haddon:QuestBank:quest:7|h[" .. q.name .. "]|h|r", "the link: " .. L.Format(q))
  assert(L.Parse("addon:QuestBank:quest:7") == 7 and L.Parse("addon:Other:quest:7") == nil and L.Parse("item:2589") == nil and L.Parse(SECRET.str()) == nil, "parsing")
  assert(#env.EventRegistry.cbs.SetItemRef == 1, "one SetItemRef callback on the Forever client")
  env.EventRegistry:TriggerEvent("SetItemRef", "addon:QuestBank:quest:7", L.Format(q), "LeftButton", nil)
  local menu = env.QuestBankMenu
  assert(menu and menu:IsShown() and menu.title:GetText() == q.name, "a click opens the quest's menu")
  menu:Hide()
  env.EventRegistry:TriggerEvent("SetItemRef", "addon:QuestBank:quest:999999999", "[x]", "LeftButton", nil)
  assert(not menu:IsShown() and owner.chat[#owner.chat]:find("doesn't know quest 999999999", 1, true), "an unknown quest: said, no menu")
  env.EventRegistry:TriggerEvent("SetItemRef", "item:2589", "[Linen Cloth]", "LeftButton", nil)
  assert(not menu:IsShown(), "other links are not QuestBank's business")
  -- item tooltips: a reward item names its quests, a plain item nothing
  local idx = L.RewardIndex()
  local iid, qids = next(idx)
  assert(iid and #qids >= 1, "the reward index holds items")
  local lines = {}
  local tip = { AddLine = function(_, s) lines[#lines + 1] = s end }
  L.ItemTip(tip, { id = iid })
  assert(#lines >= 1 and lines[1]:find("^Reward of: ") and lines[1]:find("%(L%d+"), "a reward item: " .. tostring(lines[1]))
  lines = {}
  L.ItemTip(tip, { id = 2589 })
  assert(#lines == 0, "linen cloth: no quest gives it")
  L.ItemTip({}, { id = iid }); L.ItemTip(tip, { id = SECRET.num() })
  assert(#lines == 0, "a tooltip without AddLine, a hidden id: nothing, no error")
end
-- 3.9.0: the route on the minimap (Minimap.lua): numbered stops, lines, pick-ups, dungeon entrances; its size, place
-- and zoom
do
  local Mini, env, P = QB.Mini, owner.env, QB.Pins
  assert(Mini and Mini.ready and env.QuestBankMinimap, "the overlay sits on the minimap")
  -- a flat world for the test: map 1429, 1 percent = 30 yards north-south and 40 east-west, from (0, 0)
  local saveWorld, savePos = env.C_Map.GetWorldPosFromMapPos, env.C_Map.GetPlayerMapPosition
  env.C_Map.GetWorldPosFromMapPos = function(m, v) return 0, { x = -v.y * 3000, y = -v.x * 4000, GetXY = function(self) return self.x, self.y end } end
  env.C_Map.GetPlayerMapPosition = function() return { x = 0.50, y = 0.50, GetXY = function(self) return self.x, self.y end } end
  local saveList = P.list
  P.list = { { m = 1429, x = 50, y = 48, num = 1, name = "Goldshire", when = "At 0:10", lines = {} },   -- 60 yards north
             { m = 1429, x = 52, y = 50, num = 2, name = "Crossroads", when = "At 0:20", lines = {} },  -- 80 yards east
             { m = 1429, x = 90, y = 50, num = 3, name = "Far away", when = "At 1:00", lines = {} } }  -- 1600 yards east
  c = owner; c.miniRadius = 200
  Mini.Invalidate()
  Mini.Place()
  local f = env.QuestBankMinimap
  local shown = {}
  for _, child in ipairs(c.frames) do if child.__parent == f and child.d and child:IsShown() then shown[#shown + 1] = child end end
  assert(#shown >= 3, "three stops on the minimap: " .. #shown)
  local byName = {}
  for _, p in ipairs(shown) do byName[p.d.name] = p end
  local g = byName.Goldshire
  local function at(p) return p.__points[1].x, p.__points[1].y end -- (the harness's GetPoint is a stub)
  local gx, gy = at(g)
  assert(math.abs(gx) < 0.01 and math.abs(gy - 21) < 0.01 and g:GetAlpha() == 1, string.format("60 yards north at radius 200 on a 140 px map: 21 px up (%s, %s)", gx, gy))
  local x2, y2 = at(byName.Crossroads)
  assert(math.abs(x2 - 28) < 0.01 and math.abs(y2) < 0.01, string.format("80 yards east: 28 px right (%s, %s)", x2, y2))
  local far = byName["Far away"]
  local x3 = at(far)
  assert(math.abs(x3 - 63) < 0.01 and far:GetAlpha() < 1, "a stop past the reach sits on the rim, dimmer: " .. tostring(x3))
  assert(byName.Goldshire.num:GetText() == "1" and byName.Crossroads.num:GetText() == "2", "numbered")
  assert(Mini.linesShown == 2, "you to stop 1 and stop 1 to stop 2; nothing to the far one: " .. tostring(Mini.linesShown))
  -- the minimap turning with you: facing west puts north on the right
  c.cvars = { rotateMinimap = "1" }; c.facing = math.pi / 2
  Mini.Place()
  local rx, ry = at(byName.Goldshire)
  assert(math.abs(rx - 21) < 0.01 and math.abs(ry) < 0.01, string.format("rotated: north is to the right (%s, %s)", rx, ry))
  c.cvars = nil; c.facing = nil
  -- the minimap sized and moved: the container's scale (as Edit Mode's Size slider sets it), the cluster's place
  local cont, cl = env.MinimapCluster.MinimapContainer, env.MinimapCluster
  assert(env.Minimap.__scripts.OnMouseWheel, "the wheel over the minimap is QuestBank's")
  c.ctrl = true
  env.Minimap.__scripts.OnMouseWheel(env.Minimap, 1)
  local free = QB:Settings().miniFree
  assert(math.abs(cont:GetScale() - 1.1) < 0.001 and math.abs(free.scale - 1.1) < 0.001 and free.orig == 1, "Ctrl-wheel sizes the minimap, and the size is kept")
  for _ = 1, 30 do Mini.Wheel(1) end
  assert(math.abs(cont:GetScale() - Mini.MaxScale()) < 0.001 and Mini.MaxScale() <= 4, "never past what fits the screen")
  for _ = 1, 30 do Mini.Wheel(-1) end
  assert(math.abs(cont:GetScale() - 0.6) < 0.001, "nor smaller than 60%")
  Mini.SetScale(1.1)
  c.ctrl = false
  local zl = cl.__points[1]
  assert(zl and zl.point == "TOPLEFT" and zl.rel == env.UIParent, "sizing keeps the minimap's centre where it was (the cluster moves)")
  -- the wheel zooms the game's minimap and nothing else: at its widest the wheel out stays there (5.3.1's far zoom
  -- into QuestBank's own map art and its big map are gone; the Map is the game's world map)
  env.Minimap.__zoom = 1
  Mini.Wheel(-1)
  assert(env.Minimap.__zoom == 0, "the wheel out: the game's zoom")
  Mini.Wheel(-1); Mini.Wheel(-1)
  assert(env.Minimap.__zoom == 0 and Mini.Radius() == 200, "at the widest it stays the game's widest: " .. tostring(Mini.Radius()))
  Mini.Wheel(1)
  assert(env.Minimap.__zoom == 1, "the wheel in: the game's zoom")
  env.Minimap.__zoom = 0
  assert(Mini.Big == nil and Mini.Far == nil and Mini.Zoom == nil and Mini.DrawArt == nil and env.QuestBankBigMapArt == nil and QB.Data.MAPTILES == nil,
    "no big map, no far zoom, no map art of QuestBank's own")
  -- Alt-drag moves it; where it ends is kept
  c.alt = true
  env.Minimap.__scripts.OnMouseDown(env.Minimap, "LeftButton")
  assert(Mini.dragging, "Alt and the left button start a move")
  env.Minimap.__scripts.OnMouseUp(env.Minimap, "LeftButton")
  assert(not Mini.dragging and free.x == 500 and free.y == 400, "the move ends and its place is kept")
  c.alt = false
  env.Minimap.__scripts.OnMouseDown(env.Minimap, "LeftButton")
  assert(not Mini.dragging, "a plain click doesn't move it")
  -- the Minimap bigger and smaller keys: 15% a press, kept as your size; in a fight nothing is touched
  env.QuestBankKeys.Bigger()
  assert(math.abs(cont:GetScale() - 1.265) < 0.001 and math.abs(free.scale - 1.265) < 0.001, "the bigger key, kept")
  env.QuestBankKeys.Smaller()
  assert(math.abs(cont:GetScale() - 1.1) < 0.001 and math.abs(free.scale - 1.1) < 0.001, "the smaller key")
  c.combat = true
  env.QuestBankKeys.Bigger()
  assert(math.abs(cont:GetScale() - 1.1) < 0.001, "in a fight nothing is touched")
  c.combat = false
  -- other addons' buttons: LibDBIcon's refreshed from their own angle, a stray one put back on the rim
  local refreshed = {}
  env.LibStub = function(name) if name == "LibDBIcon-1.0" then return { GetButtonList = function() return { "Foo" } end, Refresh = function(_, n) refreshed[#refreshed + 1] = n end } end end
  local stray = env.CreateFrame("Button", nil, env.Minimap)
  stray:SetPoint("CENTER", env.Minimap, "CENTER", 300, 0)
  rawset(stray, "GetPoint", function() return "CENTER", env.Minimap, "CENTER", 300, 0 end)
  local nr, nm = Mini.RescueButtons()
  assert(nr == 1 and refreshed[1] == "Foo" and nm == 1 and math.abs(stray.__points[1].x - 80) < 0.01 and stray.__points[1].y == 0, "a stray button back on the rim, same direction")
  stray:Hide(); rawset(stray, "GetPoint", nil); stray:ClearAllPoints()
  env.LibStub = nil
  Mini.ResetFree()
  assert(cont:GetScale() == 1 and next(QB:Settings().miniFree) == nil, "/qb minimap reset: the game's size again")
  -- off: nothing shown
  QB:Settings().minimapPins = false
  Mini.Place()
  assert(not byName.Goldshire:IsShown(), "the setting off clears the pins")
  QB:Settings().minimapPins = true
  P.list = saveList
  env.C_Map.GetWorldPosFromMapPos, env.C_Map.GetPlayerMapPosition = saveWorld, savePos
  Mini.Invalidate(); Mini.Place()
end
-- 3.9.0: dungeon maps (DungeonMap.lua): the client's floor art, the bosses with their recorded loot, the quests
do
  local DM, env = QB.DMap, owner.env
  local D = QB.Data.DMAP
  assert(D and D.d1581 and #D.d1581.floors == 2 and #D.d1581.floors[1] == 12 and #D.d1581.bosses >= 5, "the Deadmines: two floors of twelve tiles and its bosses")
  assert(D.d209 and #D.d209.floors == 7 and D.d16544 and #D.d16544.floors == 2 and D.d796 and D.d796.bosses[1].w, "Shadowfang's seven floors, the City of Dalaran's two, the Monastery's wings")
  local list = DM.List()
  assert(#list >= 15, "the dungeons with a map or bosses: " .. #list)
  local dm = DM.Find("deadmines")
  assert(dm and dm.key == "d1581" and DM.Find("Scarlet").key == "d796" and DM.Find("nothing like it") == nil, "finding a dungeon by part of its name")
  local U = QB.UI
  U:ShowTab(4)
  local f = DM.Open(dm)
  assert(f and env.QuestBankDungeonMap == f and f.name:GetText():find("The Deadmines", 1, true) and f.level:GetText():find("LV", 1, true), "the journal opens on the dungeon")
  assert(U.frame:IsShown() and U.tab == 7 and U.views[7]:IsShown() and f:GetParent() == U.views[7], "inside the QuestBank window, on its own page")
  assert(f.listPanel:GetWidth() + 8 + 1002 * 0.4 <= 812 and f.map:GetWidth() <= 812 - 228 and f.map:GetHeight() <= 452 - 78, "the floor art fits the page")
  assert(#f.tiles == 12 and f.tiles[1].__tex == D.d1581.floors[1][1] and f.tiles[12].__tex == D.d1581.floors[1][12] and f.tabs[1]:IsShown(), "floor 1's tiles, and the Map tab")
  assert(f.floors[1] and f.floors[2] and f.floors[2]:IsShown() and not f.floors[1]:IsEnabled(), "two floor buttons, the shown one greyed")
  DM.ShowFloor(2)
  assert(f.tiles[1].__tex == D.d1581.floors[2][1] and f.floors[1]:IsEnabled() and not f.floors[2]:IsEnabled(), "floor 2")
  -- the bosses on the floor: a portrait where each stands (VanCleef on his ship, two thirds across, halfway down)
  local van
  for i = 1, f.pinCount do if f.pins[i].boss.n == "Edwin VanCleef" then van = f.pins[i] end end
  assert(van and van:IsShown(), "VanCleef's pin on floor 2")
  local pt = van.__points[1]
  assert(pt.relPoint == "TOPLEFT" and pt.rel == f.map and math.abs(pt.x - 0.606 * f.map:GetWidth()) < 16 and math.abs(pt.y + 0.459 * f.map:GetHeight()) < 16, "where he stands (give or take a nudge from a neighbour)")
  assert(van.face.__portrait == 2029, "his pin is his own portrait, drawn by the client from his model")
  van.__scripts.OnClick(van)
  assert(f.boss.n == "Edwin VanCleef" and f.tab == "bosses" and f.lootName:GetText() == "Edwin VanCleef", "a pin opens the boss's loot")
  DM.ShowFloor(1)
  for i = 1, f.pinCount do assert(f.pins[i].boss.f == 1, "floor 1 shows floor 1's bosses only") end
  assert(f.pinCount >= 2, "floor 1 has bosses: " .. f.pinCount)
  DM.ShowBoss(van.boss)
  assert(f.floor == 2, "picking a boss turns the map to its floor")
  DM.ShowTab("map")
  local shownBosses = 0
  for _, r in ipairs(f.bossRows) do if r:IsShown() then shownBosses = shownBosses + 1 end end
  assert(shownBosses == #D.d1581.bosses - 1 and shownBosses == #DM.Visible(D.d1581) and f.bossRows[1].text:GetText():find("Rhahk'Zor", 1, true), "a row a boss, the trash hidden at first")
  DM.ShowBoss(D.d1581.bosses[1])
  assert(f.lootHead:GetText():find("items", 1, true) and f.lootName:GetText():find("Rhahk'Zor", 1, true), "the first boss is shown with its item count")
  assert(f.lootRows[1] and f.lootRows[1]:IsShown() and f.lootRows[1].text:GetText() ~= "", "a loot row with a name")
  assert(f.rows[1] and f.rows[1]:IsShown() and f.rows[1].name:GetText() ~= "", "the dungeon list has rows")
  f.search:SetText("rhahk"); f.search.__scripts.OnTextChanged(f.search)
  local shownRows = 0; for _, r in ipairs(f.rows) do if r:IsShown() then shownRows = shownRows + 1 end end
  assert(shownRows == 1 and f.rows[1].cat.key == "d1581", "searching a boss name narrows the list to its dungeon: " .. shownRows)
  f.search:SetText(""); f.search.__scripts.OnTextChanged(f.search)
  assert(type(DM.ItemName(872)) == "string" and type(DM.ItemName(999999999)) == "string", "items are named by the client, or by id until it answers")
  local qs = DM.Quests("d1581")
  assert(#qs >= 3, "the Deadmines' quests: " .. #qs)
  local shownQ = 0
  for _, r in ipairs(f.questRows) do if r:IsShown() then shownQ = shownQ + 1 end end
  assert(shownQ == #qs and f.entrance:IsShown(), "a row a quest, and the entrance button")
  DM.Toggle(dm)
  assert(U.tab == 4 and not U.views[7]:IsShown(), "toggled back to the Party page")
  local rc = DM.Find("Ragefire")
  DM.Open(rc)
  assert(U.tab == 7 and not f.floors[2]:IsShown() and not f.entrance:IsShown(), "Ragefire: one floor (no buttons), no entrance known")
  -- a loot row's second line: slot and kind, never a hole (a table.concat over a nil was a Lua error in 5.2)
  for _, b in ipairs(QB.Data.DMAP.d2437.bosses) do DM.ShowBoss(b) end
  local chat0 = #owner.chat
  DM.Command("nothing like it")
  assert(#owner.chat == chat0 + 1 and owner.chat[#owner.chat]:find("No dungeon called", 1, true), "an unknown name is said")
  DM.Command("stockade")
  assert(f.cat.key == "d717", "/qb map stockade")
  DM.Command("")
  assert(not U.frame:IsShown(), "/qb map on the journal's page closes the window")
  DM.Command("")
  assert(U.frame:IsShown() and U.tab == 7 and f.cat.key == "d717", "and opens it again where it was")
  U:ShowTab(1)
end
-- 3.9.0: Target and Focus on the minimap (Minimap.lua): kept per character, set again after each loading screen
do
  local Mini, env = QB.Mini, owner.env
  c = owner
  assert(c.menus.MENU_MINIMAP_TRACKING, "QuestBank adds to the game's tracking menu")
  assert(Mini.TrackDB().target == true and Mini.TrackDB().focus == nil, "Target on by default, Focus as the game has it")
  c.tracking[2].active, c.tracking[3].active = false, false
  assert(Mini.ApplyTracking() == 1 and c.tracking[2].active == true and c.tracking[3].active == false, "after a loading screen: Target set, Focus left alone")
  -- the menu: a divider, a title, two boxes that read and set the tracking
  local entries = {}
  local root = { CreateDivider = function() entries[#entries + 1] = "divider" end, CreateTitle = function(_, t) entries[#entries + 1] = "title " .. t end,
                 CreateCheckbox = function(_, text, isOn, setOn) entries[#entries + 1] = { text = text, isOn = isOn, setOn = setOn } end }
  c.menus.MENU_MINIMAP_TRACKING(nil, root)
  assert(#entries == 4 and entries[1] == "divider" and entries[2] == "title QuestBank" and entries[3].text == "Target on the minimap" and entries[4].text == "Focus on the minimap", "the menu's entries")
  assert(entries[3].isOn() == true and entries[4].isOn() == false, "the boxes read the game's state")
  entries[4].setOn()
  assert(c.tracking[3].active == true and Mini.TrackDB().focus == true, "ticking Focus sets it and keeps the choice")
  entries[3].setOn()
  assert(c.tracking[2].active == false and Mini.TrackDB().target == false, "unticking Target")
  -- show-all on: the game lists both itself; QuestBank adds nothing and sets nothing
  c.cvars = { minimapTrackingShowAll = "1" }
  entries = {}
  c.menus.MENU_MINIMAP_TRACKING(nil, root)
  assert(#entries == 0 and Mini.ApplyTracking() == false, "with show-all on QuestBank stays out of it")
  c.cvars = nil
  Mini.TrackDB().target, Mini.TrackDB().focus = true, nil
end
-- 3.9.0: the light on the object your Interact key would use (Glow.lua)
do
  local Glow, env = QB.Glow, owner.env
  c = owner
  local f = Glow.frame
  local function ev(e, ...) f.__scripts.OnEvent(f, e, ...) end
  assert(f and QB:Settings().glow.on == true and QB:Settings().glow.other == true, "on by default, plain objects too")
  c.cvars = { SoftTargetInteract = "0", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10", SoftTargetNameplateInteract = "0", SoftTargetIconInteract = "1" }
  ev("PLAYER_ENTERING_WORLD")
  assert(c.cvars.SoftTargetInteract == "3" and c.cvars.SoftTargetInteractArc == "2" and c.cvars.SoftTargetNameplateInteract == "1", "entering the world sets the soft-interact settings")
  assert(QB:Settings().glow.saved.SoftTargetInteract == "0" and QB:Settings().glow.saved.SoftTargetIconInteract == "1", "and keeps what they were")
  local plate = env.CreateFrame("Frame")
  c.soft = { name = "Peacebloom", plate = plate }
  ev("PLAYER_SOFT_INTERACT_CHANGED")
  local L = env.QuestBankGlow
  assert(L and L:IsShown() and Glow.kind == "herb" and L:GetParent() == plate, "an herb: the green light on its nameplate")
  c.soft = { name = "Copper Vein", plate = plate }; ev("PLAYER_SOFT_INTERACT_CHANGED")
  assert(Glow.kind == "ore", "ore: orange")
  c.soft = { name = "Old Jug", plate = plate }; ev("PLAYER_SOFT_INTERACT_CHANGED")
  assert(L:IsShown() and Glow.kind == "other", "a plain object: white")
  QB:Settings().glow.other = false; ev("PLAYER_SOFT_INTERACT_CHANGED")
  assert(not L:IsShown() and Glow.kind == nil, "plain objects switched off: nothing")
  QB:Settings().glow.other = true
  c.soft = { name = "Innkeeper Farley", plate = plate, guid = "Creature-0-4455-0-12-295-0000A1B2C3" }; ev("PLAYER_SOFT_INTERACT_CHANGED")
  assert(not L:IsShown(), "an NPC keeps the game's own cursor icon, no light")
  c.soft = { name = "Sunken Chest", plate = plate }; ev("PLAYER_SOFT_INTERACT_CHANGED")
  assert(Glow.kind == "chest", "a chest: blue")
  -- a quest object: named in an objective of a quest in the log
  local saveObj = env.C_QuestLog.GetQuestObjectives
  env.C_QuestLog.GetQuestObjectives = function(id) if id == 7 then return { { text = "Kobold Candle: 0/3", finished = false } } end return {} end
  QB.state.log[7] = QB.state.log[7] or {}
  c.soft = { name = "Kobold Candle", plate = plate }; ev("PLAYER_SOFT_INTERACT_CHANGED")
  assert(Glow.kind == "quest", "a quest object: gold")
  env.C_QuestLog.GetQuestObjectives = saveObj
  c.soft = nil; ev("PLAYER_SOFT_INTERACT_CHANGED")
  assert(not L:IsShown(), "nothing under the key: no light")
  c.soft = { name = "Peacebloom", plate = plate }
  c.combat = true; ev("PLAYER_REGEN_DISABLED")
  assert(not L:IsShown(), "in a fight: off")
  c.combat = false; ev("PLAYER_REGEN_ENABLED")
  assert(L:IsShown(), "and back after it")
  Glow.Set(false)
  assert(not L:IsShown() and c.cvars.SoftTargetInteract == "0" and c.cvars.SoftTargetNameplateInteract == "0" and QB:Settings().glow.saved == nil, "off: the settings go back as they were")
  Glow.Set(true)
  assert(c.cvars.SoftTargetInteract == "3", "on again")
  ev("PLAYER_LOGOUT")
  assert(c.cvars.SoftTargetInteract == "0", "logging out puts them back too")
  c.soft = nil; c.cvars = {}
  QB:Settings().glow.saved = nil
end
-- 3.9.0: walked trails (Walk.lua): noted every 15 yards outdoors, a jump starts a new trail, drawn on the minimap
do
  local Walk, Mini, env = QB.Walk, QB.Mini, owner.env
  c = owner
  assert(Walk and Walk.frame and Walk.STEP == 15 and Walk.BREAK == 150 and Walk.MAX_POINTS == 12000, "trails on, the numbers")
  local W = Walk.DB()
  W[0], W[1] = nil, nil
  local function at(wx, wy) return Walk.Note({ c = 0, wx = wx, wy = wy }) end
  assert(at(1000, 2000) == true and at(1005, 2000) == false and at(1016, 2000) == true, "the first point, a step too short, a step on")
  assert(#W[0] == 1 and #W[0][1] == 4 and W[0][1][3] == 1016, "one trail of two points")
  assert(at(1400, 2000) == true and #W[0] == 2, "a jump of 150 yards or more starts a new trail")
  local saveInst = env.IsInInstance
  env.IsInInstance = function() return true, "party" end
  assert(Walk.Note() == false, "inside an instance nothing is noted")
  env.IsInInstance = saveInst
  QB:Settings().walkRecord = false
  assert(at(1500, 2000) == false, "off: nothing")
  QB:Settings().walkRecord = true
  -- the cap: the oldest trail goes
  for i = 1, 12010 do at(1400 + i * 20, 2000) end
  local n = 0; for _, t in ipairs(W[0]) do n = n + #t / 2 end
  assert(n <= 12000 and W[0][1][1] ~= 1000, "no more than 12,000 points a continent; the first trail went")
  -- near: segments around a point, on the minimap
  W[0] = { { 1000, 2000, 1015, 2000, 1030, 2000, 1045, 2000 }, { 9000, 9000, 9015, 9000 } }
  Walk.dirty = true
  local near = Walk.Near(0, 1020, 2000, 100)
  assert(#near == 3 and Walk.Near(0, 5000, 5000, 100)[1] == nil, "the three segments of the first trail near its middle; none far away: " .. #near)
  local saveWorld, savePos = env.C_Map.GetWorldPosFromMapPos, env.C_Map.GetPlayerMapPosition
  env.C_Map.GetWorldPosFromMapPos = function(m, v) return 0, { x = v.y * 2000, y = v.x * 4000, GetXY = function(self) return self.x, self.y end } end
  env.C_Map.GetPlayerMapPosition = function() return { x = 0.5, y = 0.5, GetXY = function(self) return self.x, self.y end } end -- (1000, 2000)
  c.miniRadius = 200
  Mini.Place()
  assert(Mini.trailsShown == 3, "the three segments drawn near you on the minimap: " .. tostring(Mini.trailsShown))
  -- the golden path: your trails know the way from you (1000, 2000) to a stop at (1045, 2000); none to (9000, 9000)
  Walk.dirtyNodes = true
  local path = Walk.Path(0, { wx = 1000, wy = 2000 }, { wx = 1045, wy = 2000 })
  assert(path and #path == 4 and path[1][1] == 1000 and path[#path][1] == 1045 and path[2][1] == 1015, "the way along the trail, point by point: " .. tostring(path and #path))
  assert(Walk.Path(0, { wx = 1000, wy = 2000 }, { wx = 9000, wy = 9000 }) == nil, "no trail joins the far point: no path")
  assert(Walk.Path(0, { wx = 1000, wy = 2000 }, { wx = 1000, wy = 2600 }) == nil, "a goal nowhere near a trail: no path")
  local P = QB.Pins
  local saveList2 = P.list
  P.list = { { m = 1429, x = 50, y = 48.5, num = 1, name = "Along the trail", when = "", lines = {} } } -- (0.485 * 2000 = 970 ... see the flat world below)
  env.C_Map.GetWorldPosFromMapPos = function(m, v) return 0, { x = 1000 + (0.5 - v.y) * 3000, y = 2000 + (0.5 - v.x) * 4000, GetXY = function(self) return self.x, self.y end } end
  -- the stop at map (51.125, 50) is 45 yards east: (1000, 2000 - 45)... our trail runs north; put the trail east instead
  W[0] = { { 1000, 2000, 1000, 1985, 1000, 1970, 1000, 1955 } }
  Walk.dirty, Walk.dirtyNodes = true, true
  P.list = { { m = 1429, x = 51.125, y = 50, num = 1, name = "Along the trail", when = "", lines = {} } }
  Mini.Invalidate(); Mini.Place()
  assert(Mini.linesShown == 3, "the line to stop 1 follows the trail, leg by leg: " .. tostring(Mini.linesShown))
  P.list = saveList2
  W[0] = { { 1000, 2000, 1015, 2000, 1030, 2000, 1045, 2000 }, { 9000, 9000, 9015, 9000 } }
  Walk.dirty, Walk.dirtyNodes = true, true
  env.C_Map.GetWorldPosFromMapPos = function(m, v) return 0, { x = v.y * 2000, y = v.x * 4000, GetXY = function(self) return self.x, self.y end } end
  Mini.Invalidate(); Mini.Place()
  QB:Settings().walkShow = false
  Mini.Place()
  assert(Mini.trailsShown == 0, "not when switched off")
  QB:Settings().walkShow = true
  env.C_Map.GetWorldPosFromMapPos, env.C_Map.GetPlayerMapPosition = saveWorld, savePos
  W[0] = nil
  Mini.Invalidate(); Mini.Place()
end
-- 5.3: health and mana numbers on the portraits: the game's own Status Text, from QuestBank's settings
do
  local U = QB.UI
  c = owner
  U:ShowTab(5)
  local v = U.views[5]
  assert(#v.statusBtns == 4 and U.StatusText() == "NONE" and not v.statusBtns[1]:IsEnabled(), "off by default, Off greyed as the one in use")
  v.statusBtns[4].__scripts.OnClick(v.statusBtns[4])
  assert(c.cvars.statusText == "1" and c.cvars.statusTextDisplay == "BOTH" and U.StatusText() == "BOTH" and not v.statusBtns[4]:IsEnabled(), "Both: numbers and percent, always shown")
  v.statusBtns[1].__scripts.OnClick(v.statusBtns[1])
  assert(c.cvars.statusText == "0" and U.StatusText() == "NONE", "Off")
  -- from one kind shown to another: the bars redraw only when the switch changes (CVAR_UPDATE for statusText), so it
  -- goes off and on again after the kind is set. 5.3.1 set the kind alone: Numbers then Percent changed nothing
  local function redrawnAs()
    local as
    for _, ch in ipairs(c.cvarChanges or {}) do if ch[1] == "statusText" and ch[2] == "1" then as = ch[3] end end
    return as
  end
  v.statusBtns[2].__scripts.OnClick(v.statusBtns[2])
  assert(U.StatusText() == "NUMERIC", "Numbers")
  c.cvarChanges = {}
  v.statusBtns[3].__scripts.OnClick(v.statusBtns[3])
  assert(U.StatusText() == "PERCENT" and c.cvars.statusText == "1" and redrawnAs() == "PERCENT", "Numbers then Percent: the bars redraw as Percent: " .. tostring(redrawnAs()))
  c.cvarChanges = {}
  v.statusBtns[4].__scripts.OnClick(v.statusBtns[4])
  assert(U.StatusText() == "BOTH" and redrawnAs() == "BOTH", "Percent then Both: redrawn too")
  -- not in a fight: nothing changes, a line says when
  c.combat = true
  local nChat = #c.chat
  v.statusBtns[2].__scripts.OnClick(v.statusBtns[2])
  assert(U.StatusText() == "BOTH" and #c.chat == nChat + 1 and c.chat[#c.chat]:find("fight", 1, true), "in a fight: as it was")
  c.combat = false
  v.statusBtns[1].__scripts.OnClick(v.statusBtns[1])
  U:ShowTab(1)
end
-- the key bindings: one QuestBank section in the game's Key Bindings, a line for the window, each page, the Map
-- and the minimap's size; a page's key opens the window on that page and shuts it there. The Map is the game's own
-- world map on your zone, opened through the game's panel code, with QuestBank's icons on it
do
  local U, env = QB.UI, owner.env
  c = owner
  local xml = io.open(HERE .. "/QuestBank/Bindings.xml"):read("*a"):gsub("<!%-%-.-%-%->", "")
  local keys, order = {}, {}
  for attrs, body in xml:gmatch("<Binding ([^>]*)>(.-)</Binding>") do
    local name = attrs:match('name="([^"]+)"')
    assert(name and attrs:match('category="([^"]+)"') == "BINDING_HEADER_QUESTBANK" and not attrs:find("header=", 1, true),
      "every key in QuestBank's own section, without the blank header row: " .. tostring(name))
    assert(type(env["BINDING_NAME_" .. name]) == "string" and env["BINDING_NAME_" .. name] ~= "", "each key named in Key Bindings: " .. name)
    local fn = assert(loadstring(body, name))
    setfenv(fn, env)
    keys[name], order[#order + 1] = fn, name
  end
  assert(env.BINDING_HEADER_QUESTBANK == "QuestBank" and #order == 11, "the QuestBank section, eleven keys: " .. #order)
  local pages = 0
  for _, e in ipairs(U.SIDEBAR) do
    if e.name and not e.group then
      assert(e.key and keys["QUESTBANK_" .. e.key] and env["BINDING_NAME_QUESTBANK_" .. e.key] == e.name, "a key for the sidebar's " .. e.name .. ", named as there")
      if e.tab then pages = pages + 1 end
    end
  end
  assert(pages == 7 and keys.QUESTBANK_WINDOW and keys.QUESTBANK_MAP and keys.QUESTBANK_MINIMAP_BIGGER and keys.QUESTBANK_MINIMAP_SMALLER, "seven pages, the window, the Map, the minimap's size")
  assert(env.BINDING_NAME_QUESTBANK_MAP == "Map" and keys.QUESTBANK_BIGMAP == nil and env.BINDING_NAME_QUESTBANK_BIGMAP == nil, "Map, not Big map")
  -- a page's key: the window on that page; again, shut; another page's key while it is open: that page
  local wasOpen, wasTab = U.frame:IsShown(), U.tab
  U.frame:Hide()
  for _, e in ipairs(U.SIDEBAR) do
    if e.tab then
      keys["QUESTBANK_" .. e.key]()
      assert(U.frame:IsShown() and U.tab == e.tab and U.views[e.tab]:IsShown(), "the " .. e.name .. " key opens the window there")
      keys["QUESTBANK_" .. e.key]()
      assert(not U.frame:IsShown(), "and again shuts it: " .. e.name)
    end
  end
  keys.QUESTBANK_NOW()
  keys.QUESTBANK_LOG()
  assert(U.frame:IsShown() and U.tab == 1, "open on Now, the Quest Log key: the Quest Log")
  keys.QUESTBANK_WINDOW()
  assert(not U.frame:IsShown(), "the window key shuts it")
  keys.QUESTBANK_WINDOW()
  assert(U.frame:IsShown() and U.tab == 1, "and opens it where it was")
  -- the Map: the sidebar's entry, the key, the settings button and /qb bigmap open the game's world map on your zone
  local map = c.map
  local mapWas, idWas = map.shown, map.id
  map:Close()
  c.panelCalls, c.playerMap = {}, 1453
  local side
  for _, b in ipairs(U.sideButtons) do if b.entry.name == "Map" then side = b end end
  assert(side and not side.entry.tab and side.label:GetText() == "Map", "the sidebar's Map, an action, not a page")
  side.__scripts.OnClick(side)
  assert(map.shown and map.id == 1453 and c.panelCalls[1] == "open" and U.frame:IsShown() and U.tab == 1, "the sidebar's Map: the game's map, on your zone; the window stays as it was")
  assert(#ours(c, "QuestBankQuestPinTemplate") > 0, "QuestBank's icons on it")
  side.__scripts.OnClick(side)
  assert(map.shown and #c.panelCalls == 1, "open on your zone already: left as it is")
  map.id = 1429
  side.__scripts.OnClick(side)
  assert(map.shown and map.id == 1453 and c.panelCalls[2] == "hide" and c.panelCalls[3] == "open", "open on another zone: shut and opened on yours")
  keys.QUESTBANK_MAP()
  assert(not map.shown and c.panelCalls[4] == "hide", "the Map key shuts it")
  keys.QUESTBANK_MAP()
  assert(map.shown and c.panelCalls[5] == "open", "and opens it")
  -- in a fight the game blocks an addon opening a panel: nothing is called, a line says so
  c.combat = true
  local nCalls, nChat = #c.panelCalls, #c.chat
  keys.QUESTBANK_MAP()
  side.__scripts.OnClick(side)
  assert(#c.panelCalls == nCalls and not c.panelBlocked and map.shown and #c.chat == nChat + 2 and c.chat[#c.chat]:find("fight", 1, true), "in a fight: nothing tried")
  c.combat = false
  for _, cmd in ipairs({ "bigmap", "map-open" }) do
    map:Close()
    env.SlashCmdList.QUESTBANK(cmd)
    assert(map.shown and map.id == 1453, "/qb " .. cmd .. " opens the Map")
  end
  map:Close()
  U:ShowTab(5)
  local v = U.views[5]
  assert(v.map and v.map:GetText() == "Map" and v.bigmap == nil, "the settings button is Map")
  v.map.__scripts.OnClick(v.map)
  assert(map.shown and map.id == 1453, "and opens the game's map")
  -- back as it was
  map.id = idWas
  if mapWas then map:RefreshAll() else map:Close() end
  c.playerMap, c.panelCalls = nil, {}
  U:ShowTab(wasTab or 1)
  U.frame:SetShown(wasOpen)
end
-- 5.3: dungeon entrances on the zone maps: hovered, how many of their quests you have done, a check on each done one
do
  local QM, U = QB.QuestMap, QB.UI
  c = owner
  local list = QM:Build(1436)
  local dm
  for _, d in ipairs(list) do if d.kind == "dungeon" and d.cat.key == "d1581" then dm = d end end
  assert(dm and math.abs(dm.x - 0.425) < 0.001 and math.abs(dm.y - 0.717) < 0.001, "the Deadmines' entrance on Westfall's map")
  local qs = QB.DMap.Quests("d1581")
  local doneN = 0
  for _, e in ipairs(qs) do if e.st == "done" then doneN = doneN + 1 end end
  lines = {}
  local icon = { data = dm }
  -- the tooltip as the icon's hover draws it
  local f = QM.IconMethods and QM.IconMethods.OnMouseEnter
  assert(f, "the icon's hover")
  f(icon)
  local all = table.concat(lines, "\n")
  print("dungeon tooltip:", (all:gsub("\n", " | ")):sub(1, 220))
  assert(all:find(string.format("The Deadmines | %d/%d quests done", doneN, #qs), 1, true), "its name and N/M quests done")
  U:ShowTab(1)
  QM.ClickForTest(dm, "LeftButton")
  assert(U.tab == 7 and QB.DMap.Fill and owner.env.QuestBankDungeonMap.cat.key == "d1581" and owner.env.QuestBankDungeonMap.tab == "quests", "a click opens the Journal on its quests")
  U:ShowTab(1)
end
-- 5.3: the camp bar (Camp.lua): Well Fed, the campfire kit, camp features with the shared cooldown, the sleeping bag
do
  local Camp, env = QB.Camp, owner.env
  c = owner
  local f = Camp.frame
  local function ev(e, ...) f.__scripts.OnEvent(f, e, ...) end
  local D = QB.Data
  assert(f and D.CAMP and D.CAMP[279944] and D.CAMP[279944].sp and D.CAMP[279981].t == "kit" and D.CAMP[279988].base == 279944 and D.FOOD[2888], "the camp and food tables")
  local set = QB:Settings().remind
  assert(set.camp and set.food and set.bag and set.fire and set.quietInstance, "defaults: every icon on")
  c.profs = { { "Blacksmithing", 150 }, { "Alchemy", 10 }, { "Fishing", 0 }, { "Cooking", 60 }, { "First Aid", 30 } }
  local saveBags = owner.o.bagSlots
  owner.o.bagSlots = { { 279944, 1 }, { 279988, 1 }, { 279956, 1 }, { 279968, 1 }, { 2888, 5 }, { 211527, 1 }, { 279981, 2 } }
  local pr = Camp.Professions()
  assert(pr.Blacksmithing == 150 and pr["First Aid"] == 30 and pr.Alchemy == 10, "professions read")
  local pl = Camp.Placeable()
  assert(#pl == 2 and pl[1].e.n == "Anvil" and pl[2].e.n == "First Aid Kit", "placeable: the anvil over the wheel, the kit; no mana well at Alchemy 10")
  c.buffs = {}
  ev("PLAYER_ENTERING_WORLD")
  local bar = env.QuestBankCampBar
  local function ic(k) return env["QuestBankCamp_" .. k] end
  assert(bar and bar:IsShown() and Camp.visible == 4, "the bar is up with four icons: " .. tostring(Camp.visible))
  -- food: not fed, ribs in the bag: lit, the click eats them
  local food = ic("food")
  assert(food:IsShown() and food.state.lit and food:GetAttribute("type") == "item" and food:GetAttribute("item") == "item:2888" and food.count:GetText() == "5", "not fed: the ribs, lit, five of them, a click eats one")
  -- fed: the buff's own icon with its minutes
  local saveAura = env.C_UnitAuras.GetAuraDataByIndex
  env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
    if i == 1 then return { name = "Well Fed", applications = 0, expirationTime = env.GetTime() + 600, icon = 136000 } end
  end
  Camp.Refresh()
  assert(food.time:GetText() == "10m" and not food.state.lit and food:GetAttribute("type") == nil, "fed: ten minutes left, nothing to click")
  env.C_UnitAuras.GetAuraDataByIndex = saveAura
  -- the campfire kit, then the anvil: lit only with a fire near and the cooldown up
  local fire, camp = ic("fire"), ic("camp")
  Camp.Refresh()
  assert(fire:IsShown() and fire:GetAttribute("item") == "item:279981" and fire.count:GetText() == "2" and fire.state.lit, "two campfire kits; lit while features wait for a fire")
  assert(camp:IsShown() and camp:GetAttribute("item") == "item:279988" and not camp.state.lit and not camp.state.grey, "the anvil, ready, waiting for a fire")
  ev("UNIT_SPELLCAST_SUCCEEDED", "player", nil, D.CAMP[279981].sp)
  assert(camp.state.lit and not fire.state.lit, "the fire lit: the anvil lights up, the kit doesn't")
  ev("UNIT_SPELLCAST_SUCCEEDED", "player", nil, D.CAMP[279988].sp)
  assert(camp.state.grey and camp.state.cd and camp.time:GetText() == "1h" and Camp.CooldownLeft() > 3500, "placed: the hour's cooldown sweeps, greyed")
  -- the game's own cooldown wins when it answers
  local saveCD = env.C_Container.GetItemCooldown
  env.C_Container.GetItemCooldown = function(id) if id == 279988 then return env.GetTime() - 3000, 3600, 1 end return 0, 0, 1 end
  Camp.Refresh()
  assert(camp.time:GetText() == "10m", "the item's own cooldown: ten minutes left")
  env.C_Container.GetItemCooldown = saveCD
  -- the sleeping bag: lit after 20 s standing still under three stacks
  local bag = ic("bag")
  assert(bag:IsShown() and not bag.state.lit and bag:GetAttribute("item") == "item:211527", "the bag, not lit while you move")
  tick(owner, 25)
  Camp.Refresh()
  assert(bag.state.lit, "still for 20 s: the bag lights up")
  -- a switch off takes its icon away
  QB:Settings().remind.food = false
  Camp.Refresh()
  assert(not food:IsShown() and Camp.visible == 3, "the food switch off: no food icon")
  QB:Settings().remind.food = true
  -- in a fight: dimmed, its buttons left alone (the game's secure buttons)
  c.combat = true; ev("PLAYER_REGEN_DISABLED")
  owner.o.bagSlots = {}
  Camp.Refresh()
  assert(bar:GetAlpha() < 1 and fire:IsShown() and fire:GetAttribute("item") == "item:279981", "in a fight nothing moves or changes its click")
  c.combat = false; ev("PLAYER_REGEN_ENABLED")
  assert(bar:GetAlpha() == 1 and not fire:IsShown() and food:IsShown() and food.state.grey, "after it: the kit is gone, no food is grey")
  -- in a dungeon: hidden
  local saveInst = env.IsInInstance
  env.IsInInstance = function() return true, "party" end
  Camp.Refresh()
  assert(not bar:IsShown(), "in a dungeon with quiet on: hidden")
  env.IsInInstance = saveInst
  -- Alt-drag moves it and the place is kept
  c.alt = true
  food.__scripts.OnMouseDown(food, "LeftButton"); food.__scripts.OnMouseUp(food, "LeftButton")
  c.alt = false
  assert(type(QB:Settings().remind.pos) == "table" and QB:Settings().remind.pos.x == 500, "Alt-drag moves the bar and keeps its place")
  QB:Settings().remind.pos = nil
  owner.o.bagSlots = saveBags; c.profs = nil; c.buffs = nil
  Camp.Refresh()
end
-- 5.3: the minimap leads to the work: objectives as the game's cursor icons, the line to the nearest unfinished one, its name in a
-- label
do
  local Mini, env, P, D = QB.Mini, owner.env, QB.Pins, QB.Data
  c = owner
  local saveWorld, savePos, saveList = env.C_Map.GetWorldPosFromMapPos, env.C_Map.GetPlayerMapPosition, P.list
  env.C_Map.GetWorldPosFromMapPos = function(m, v) return 0, { x = -v.y * 3000, y = -v.x * 4000, GetXY = function(self) return self.x, self.y end } end
  env.C_Map.GetPlayerMapPosition = function() return { x = 0.50, y = 0.50, GetXY = function(self) return self.x, self.y end } end
  D.SPOT[777777] = "k,1,1429,520,500,10,c"                      -- 80 yards east of you
  QB.Quest.Get(777777) -- (unknown to the catalog: named by id)
  table.insert(QB.state.logOrder, 1, { id = 777777, complete = false })
  P.list = { { m = 1429, x = 50, y = 40, num = 1, name = "Goldshire", when = "", lines = {} } } -- 300 yards north
  c.miniRadius = 200
  Mini.Invalidate(); Mini.Place()
  local obj
  for _, fr in ipairs(c.frames) do if fr.d and fr.d.kind == "obj" and fr.d.id == 777777 and fr:IsShown() then obj = fr end end
  assert(obj and (obj.icon.__tex == "atlas:Crosshair_Attack_32" or obj.icon.__tex == 131013) and math.abs(obj.__points[1].x - 28) < 0.01, "a kill objective is the game's sword cursor, 80 yards east: 28 px: " .. tostring(obj and obj.icon.__tex))
  assert(Mini.target and Mini.target.kind == "obj" and Mini.target.id == 777777, "the nearer objective is the target, not stop 1")
  assert(Mini.linesShown >= 1 and env.QuestBankMinimapLabel:IsShown() and Mini.labelText == "Quest 777777", "a line to it, and its name in the label: " .. tostring(Mini.labelText))
  QB:Settings().minimapObjectives = false
  c.miniRadius = 400 -- (Goldshire inside the circle, so its label shows)
  Mini.Place()
  assert(Mini.target and Mini.target.kind == "stop" and Mini.labelText == "Goldshire", "objectives off: stop 1 is the target")
  c.miniRadius = 200
  QB:Settings().minimapObjectives = nil
  D.SPOT[777777] = nil
  table.remove(QB.state.logOrder, 1)
  P.list = saveList
  env.C_Map.GetWorldPosFromMapPos, env.C_Map.GetPlayerMapPosition = saveWorld, savePos
  Mini.Invalidate(); Mini.Place()
end
-- 5.3: the short tooltip, abandoning from the menu, Best gear by slot
do
  local U, env = QB.UI, owner.env
  local q = QB.Quest.Get(QB.state.logOrder[1].id)
  local got = {}
  local tip = { AddLine = function(_, t) got[#got + 1] = t end, AddDoubleLine = function(_, a, b) got[#got + 1] = a .. " | " .. b end }
  U.longTips = false
  U.QuestTooltip(tip, q, QB:Status(q), 1234)
  assert(got[1] == q.name and got[2]:find("1,234 XP", 1, true) and got[#got] == "Shift: sources, chain and notes" and #got <= 6, "the short tooltip: " .. table.concat(got, " / "))
  got = {}
  owner.shift = true
  U.QuestTooltip(tip, q, QB:Status(q), 1234)
  owner.shift = false
  assert(#got > 6, "Shift: the long one")
  U.longTips = true
  -- abandon: the game's three calls, from the menu, asked twice
  local calls = {}
  env.C_QuestLog.SetSelectedQuest = function(id) calls[#calls + 1] = "select " .. id end
  env.C_QuestLog.SetAbandonQuest = function() calls[#calls + 1] = "mark" end
  env.C_QuestLog.AbandonQuest = function() calls[#calls + 1] = "abandon" end
  U.QuestMenu(q)
  local menu = env.QuestBankMenu
  local ab
  for _, b in ipairs(menu.items) do if b:IsShown() and b.label:GetText():find("Abandon this quest", 1, true) then ab = b end end
  assert(ab, "the menu offers to abandon a quest in the log")
  ab.__scripts.OnClick(ab)
  local yes
  for _, b in ipairs(menu.items) do if b:IsShown() and b.label:GetText():find("Yes, abandon it", 1, true) then yes = b end end
  assert(yes and #calls == 0, "it asks first")
  yes.__scripts.OnClick(yes)
  assert(table.concat(calls, ",") == "select " .. q.id .. ",mark,abandon", "then the game's own abandon: " .. table.concat(calls, ","))
  env.C_QuestLog.SetSelectedQuest, env.C_QuestLog.SetAbandonQuest, env.C_QuestLog.AbandonQuest = nil, nil, nil
  -- Best gear narrowed to a slot: a reward's equip location decides
  local saveInst = env.C_Item.GetItemInfoInstant
  env.C_Item.GetItemInfoInstant = function(id) return id, "Armor", "Cloth", id % 2 == 0 and "INVTYPE_HEAD" or "INVTYPE_FEET" end
  local R = QB.Data.RITEMS
  local qid, rid
  for id, r in pairs(R) do if r.c and r.c[1] and r.c[1] % 2 == 0 then qid, rid = id, r.c[1]; break end end
  assert(qid and U.RewardSlotFits(qid, "Head") and not U.RewardSlotFits(qid, "Ring"), "a head reward fits Head, not Ring")
  env.C_Item.GetItemInfoInstant = saveInst
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
  assert(#owner.said == said + 1 and owner.said[#owner.said][1] == "QuestBank: Quest 15 - accepted" and owner.said[#owner.said][2] == "PARTY", "a new quest in the log is said in party chat: " .. tostring(owner.said[#owner.said] and owner.said[#owner.said][1]))
  for _, e in ipairs(owner.log) do if e[1] == 15 then e[2] = 1 end end
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(#owner.said == said + 2 and owner.said[#owner.said][1] == "QuestBank: Quest 15 - completed", "and so is a quest turning complete: " .. tostring(owner.said[#owner.said][1]))
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
  -- 3.8.0: the key button cycles, a context switch cycles inherit, on, off, and the strip box follows the timer
  assert(v5.autoKey:GetText() == "Shift", "the key starts as Shift")
  for _, want in ipairs({ "Ctrl", "Alt", "No key", "Shift" }) do
    v5.autoKey.__scripts.OnClick(v5.autoKey, "LeftButton")
    assert(v5.autoKey:GetText() == want, "the key cycles to " .. want .. ": " .. tostring(v5.autoKey:GetText()))
  end
  assert(QB:Settings().autoKey == "shift", "and back to shift in the setting")
  local tb = v5.tri["party.autoAccept"]
  assert(tb and QB:Settings().profiles.party.autoAccept == nil, "a context switch starts as inherit")
  tb.__scripts.OnClick(tb, "LeftButton"); assert(QB:Settings().profiles.party.autoAccept == true, "one click: on")
  -- 5.4: on and off are the ready check's tick and cross (the font drew a box for a text check mark)
  UI:Refresh(); assert(tb:GetText() == "|T" .. QB.Data.TEX.ready .. ":14|t", "on: the ready check's tick: " .. tb:GetText())
  tb.__scripts.OnClick(tb, "LeftButton"); assert(QB:Settings().profiles.party.autoAccept == false, "two: off")
  UI:Refresh(); assert(tb:GetText() == "|T" .. QB.Data.TEX.notready .. ":14|t", "off: its cross")
  tb.__scripts.OnClick(tb, "LeftButton"); assert(QB:Settings().profiles.party.autoAccept == nil, "three: inherit again")
  v5.clockShow:SetChecked(true); v5.clockShow.__scripts.OnClick(v5.clockShow, "LeftButton")
  assert(QB:Settings().clock.show == true and QB.Timer.frame and QB.Timer.frame:IsShown(), "the strip box shows the strip")
  v5.clockShow:SetChecked(false); v5.clockShow.__scripts.OnClick(v5.clockShow, "LeftButton")
  assert(QB:Settings().clock.show == false and not QB.Timer.frame:IsShown(), "and hides it")
  local lay = checkLayout(UI.frame, "settings, scrolled")
  assert(#lay == 0, "the longer Settings page fits across and scrolls down: " .. table.concat(lay, "; "))
  local sf = v5.scroll
  local lo, hi = sf.bar:GetMinMaxValues()
  assert(sf.bar:IsShown() and hi > 0 and hi == 1170 - sf:GetHeight(), "the knob runs exactly what does not fit: " .. tostring(hi) .. " of " .. tostring(sf:GetHeight()))
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
    -- (within each section: zones, then dungeons)
    local last, wasDungeon = math.huge, nil
    for _, c in ipairs(UI.views[2].cards.items) do
      if c:IsShown() and c.skip:IsShown() and c.gain:GetText():sub(1, 1) == "+" then
        local isDungeon = c.skip.key and c.skip.key:sub(1, 1) == "d"
        if isDungeon ~= wasDungeon then last, wasDungeon = math.huge, isDungeon end
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
for tab = 1, 7 do
  UI:ShowTab(tab)
  QB.Model.Finish()
  UI:Refresh()
  -- (the journal is checked as it is drawn: on the Deadmines' map)
  if tab == 7 then QB.DMap.Open(QB.DMap.Find("deadmines"), "map"); QB.DMap.ShowFloor(2); UI:Refresh() end
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
  layouts[#layouts + 1] = dumpLayout(UI.frame, ({ "Quest Log", "Available", "Hand-in Route", "Party", "Settings", "Now", "Dungeon Journal" })[tab] .. " (one row hovered)")
  unhover()
end

-- 5.4: the Dungeon Journal, every dungeon on every tab and every boss's loot: nothing errors (a boss's level can be a
-- range, { 20, 21 }), and the long lists scroll inside the page (Blackrock Depths has 39 bosses and 24 quests, a trash
-- list 12 items; they ran up to 1285 px off the bottom of the window)
do
  local DM = QB.DMap
  UI:ShowTab(7); UI:Refresh()
  assert(DM.LevelText({ 20, 21 }) == "20-21" and DM.LevelText(52) == "52", "a boss's level, one or a range")
  local n, ranged, longest = 0, 0, { boss = 0, quest = 0 }
  local function check(label) for _, p in ipairs(checkLayout(UI.frame, label)) do problems[#problems + 1] = p end end
  for _, cat in ipairs(DM.List()) do
    local ok, f = pcall(DM.Open, cat, "bosses")
    assert(ok and f, "the journal opens on " .. cat.name .. ": " .. tostring(f))
    n = n + 1
    check("Dungeon Journal, " .. cat.name .. ", bosses")
    local most
    for _, b in ipairs(f.data.bosses or {}) do
      local okb, err = pcall(DM.ShowBoss, b)
      assert(okb, "a boss's loot opens: " .. cat.name .. ", " .. tostring(b.n) .. ": " .. tostring(err))
      if type(b.l) == "table" then
        ranged = ranged + 1
        assert(f.lootSub:GetText():find("level " .. DM.LevelText(b.l), 1, true), "a level range under the boss's name: " .. f.lootSub:GetText())
      end
      if not most or #b.i > #most.i then most = b end
    end
    if most then DM.ShowBoss(most); check("Dungeon Journal, " .. cat.name .. ", loot of " .. most.n) end
    DM.ShowTab("quests"); check("Dungeon Journal, " .. cat.name .. ", quests")
    DM.ShowTab("map"); check("Dungeon Journal, " .. cat.name .. ", map")
    longest.boss = math.max(longest.boss, #(f.data.bosses or {}))
    local qn = 0
    for _, r in ipairs(f.questRows) do if r:IsShown() then qn = qn + 1 end end
    longest.quest = math.max(longest.quest, qn)
  end
  assert(n >= 20 and ranged >= 1, "every dungeon opened (" .. n .. "), bosses with a level range among them (" .. ranged .. ")")
  -- the longest lists scroll: the knob runs exactly what does not fit, the wheel moves a row, and the last row,
  -- scrolled to, sits inside the list
  local f = DM.Open(DM.Find("blackrock depths"), "bosses")
  local sf = f.bossScroll
  local lo, hi = sf.bar:GetMinMaxValues()
  local rows = #DM.Visible(f.data)
  assert(rows >= 30 and sf.bar:IsShown() and hi == rows * 44 - 2 - sf.viewH, "Blackrock Depths' bosses scroll: " .. tostring(hi))
  sf.__scripts.OnMouseWheel(sf, -1)
  assert(sf.bar:GetValue() == 44 and sf.__scroll == 44, "a wheel notch scrolls one boss")
  sf.bar:SetValue(hi)
  check("Dungeon Journal, Blackrock Depths, bosses scrolled to the end")
  GEN = GEN + 1
  local last, view = rectOf(f.bossRows[rows]), rectOf(sf)
  assert(last.b >= view.b - 0.5 and last.t <= view.t + 0.5, "the last boss, scrolled to, is in view")
  DM.ShowBoss(f.data.bosses[1])
  assert(f.bossScroll.bar:GetValue() == hi, "showing a boss's loot keeps the list where it is")
  local trash
  for _, b in ipairs(f.data.bosses) do if #b.i >= 12 then trash = trash or b end end
  if trash then
    DM.ShowBoss(trash)
    local _, lh = f.lootScroll.bar:GetMinMaxValues()
    assert(f.lootScroll.bar:IsShown() and lh == 12 * 40 - 2 - f.lootScroll.viewH, "12 items of loot scroll: " .. lh)
    f.lootScroll.bar:SetValue(lh)
    DM.ShowBoss(trash)
    assert(f.lootScroll.bar:GetValue() == lh, "the same boss drawn again (an item's name came in) keeps its place")
    DM.ShowBoss(f.data.bosses[1] ~= trash and f.data.bosses[1] or f.data.bosses[2])
    assert(f.lootScroll.bar:GetValue() == 0, "another boss starts at the top")
  end
  DM.ShowTab("quests")
  local _, qh = f.questScroll.bar:GetMinMaxValues()
  assert(f.questScroll.bar:IsShown() and qh > 0, "Blackrock Depths' quests scroll")
  f.questScroll.bar:SetValue(qh)
  check("Dungeon Journal, Blackrock Depths, quests scrolled to the end")
  layouts[#layouts + 1] = dumpLayout(UI.frame, "Dungeon Journal, Blackrock Depths, quests scrolled to the end")
  DM.Open(DM.Find("blackrock depths"), "bosses")
  layouts[#layouts + 1] = dumpLayout(UI.frame, "Dungeon Journal, Blackrock Depths, Bosses+Rares")
  print(string.format("journal: %d dungeons on every tab, %d bosses with a level range; longest lists %d bosses, %d quests", n, ranged, longest.boss, longest.quest))
  DM.Open(DM.Find("deadmines"), "map"); DM.ShowFloor(2)
  UI:ShowTab(1); UI:Refresh()
end

-- 5.3.3: the Dungeon Journal's faces, chips and model (DungeonMap.lua). An entry's face is the first the client can
-- draw: the old journal's art, the portrait of its model (the client fills that in after the call, so it is drawn
-- again when the client says portraits changed; drawn only once, it stayed a blank ring), an achievement icon, its
-- kind's icon, and the default face for a boss only. Chips over the list show or hide bosses, rares, trash and
-- chests, here and on the map; the loot panel's face is one live model
do
  local DM, env = QB.DMap, owner.env
  local D = QB.Data.DMAP
  local function check(label) for _, p in ipairs(checkLayout(UI.frame, label)) do problems[#problems + 1] = p end end
  UI:ShowTab(7); UI:Refresh()
  local f = env.QuestBankDungeonMap
  local show = QB:Settings().djShow
  assert(show.boss and show.rare and show.trash == false and show.other, "at first bosses, rares, chests and events show, trash does not")
  local src = io.open(HERE .. "/QuestBank/DungeonMap.lua"):read("*a")
  assert(not src:find("\\194\\183", 1, true) and not src:find("\194\183", 1, true), "no middle dot in the journal's text: a comma")

  -- the face chain, an entry a branch, on one texture (each face undoes the last: the grey of trash, an atlas)
  local fix = { defaultFace = 521744, floors = {}, bosses = {
    { n = "Old Art", k = "boss", p = 5875512, d = 7125, o = 2, i = {} },
    { n = "Model Only", k = "boss", d = 2029, o = 0, i = {} },
    { n = "Achiever", k = "boss", a = 236693, i = {} },
    { n = "Faceless", k = "boss", o = 1, i = {} },
    { n = "Plain Rare", k = "rare", i = {} },
    { n = "Rare Model", k = "rare", d = 556, i = {} },
    { n = "Trash mobs", k = "trash", i = {} },
    { n = "Strongbox", k = "object", i = {} },
    { n = "Summoned", k = "quest", i = {} },
    { n = "Creature", k = "boss", c = 245999, a = 236694, i = {} },
  } }
  local B = {}
  for _, b in ipairs(fix.bosses) do B[b.n] = b end
  local t = f:CreateTexture()
  local calls = PORTRAIT.calls
  assert(DM.Face(t, B["Old Art"], fix) == "p" and t.__tex == 5875512 and PORTRAIT.calls == calls, "the journal's art first, never a blank portrait")
  assert(DM.Face(t, B["Trash mobs"], fix) == "kind" and t.__tex == 137025 and t.__desat, "trash with nothing: the grey skull")
  assert(DM.Face(t, B["Model Only"], fix) == "d" and t.__portrait == 2029 and PORTRAIT.calls == calls + 1 and not t.__desat, "a display id only: the client's portrait of the model")
  assert(DM.Face(t, B["Achiever"], fix) == "a" and t.__tex == 236693, "an achievement's boss icon next")
  assert(DM.Face(t, B["Strongbox"], fix) == "kind" and t.__tex == 132594, "an object: the chest")
  assert(DM.Face(t, B["Summoned"], fix) == "kind" and t.__atlas == "QuestNormal", "an event: the quest-giver's !")
  assert(DM.Face(t, B["Faceless"], fix) == "default" and t.__tex == 521744, "a boss with nothing: the journal's default face")
  assert(DM.Face(t, B["Plain Rare"], fix) == "kind" and t.__atlas == "nameplates-icon-elite-silver" and t.__tex ~= 521744, "a rare with nothing: the elite dragon, never the default face")
  assert(DM.Kind(B["Strongbox"]) == "other" and DM.KindLabel(B["Strongbox"]) == "Chest" and DM.KindLabel(B["Summoned"]) == "Event" and DM.KindLabel(B["Trash mobs"]) == "Trash", "kinds and their words")

  -- the list: bosses in encounter order (one the client does not know right after the one before it), rares, the rest
  D.dfix = fix
  DM.Fill({ key = "dfix", name = "Fixture Halls" }, "bosses")
  local names, badges = {}, {}
  for _, r in ipairs(f.bossRows) do if r:IsShown() then names[#names + 1] = r.boss.n; badges[r.boss.n] = r.badge:IsShown() and r.badge.__atlas end end
  assert(table.concat(names, ",") == "Model Only,Achiever,Faceless,Creature,Old Art,Plain Rare,Rare Model,Strongbox,Summoned", "the list's order: " .. table.concat(names, ","))
  assert(badges["Rare Model"] == "nameplates-icon-elite-silver" and not badges["Plain Rare"] and not badges["Summoned"] and not badges["Old Art"], "a rare with a face wears the elite badge; a face that is the kind's icon needs none")
  assert(f.bossRows[1].sub:GetText() == "" and not f.tabs[1]:IsShown() and f.tab == "bosses", "no wing or level, no floor art: no Map tab")
  DM.ShowTab("map")
  assert(f.tab == "bosses" and f.bossTab:IsShown(), "no Map tab to show")
  -- the loot panel's face: one live model where there is a display id, the creature where there is only its NPC id
  -- (the picture stays under it), else the picture alone; set once a boss
  local m = f.lootModel
  DM.ShowBoss(B["Old Art"])
  assert(m:IsShown() and m.__display == 7125 and m.__portraitZoom == 0.6 and not f.lootFace:IsShown() and f.lootRing:IsShown(), "a display id: the live model in its ring")
  m.__display = nil
  DM.ShowBoss(B["Old Art"])
  assert(m.__display == nil, "the same boss again (an item's name came in): the model is left as it is")
  DM.ShowBoss(B["Creature"])
  assert(m:IsShown() and m.__creature == 245999 and f.lootFace:IsShown() and f.lootFace.__tex == 236694, "an NPC id only: the creature, the picture under it")
  DM.ShowBoss(B["Faceless"])
  assert(not m:IsShown() and m.__display == nil and m.__creature == nil and f.lootFace:IsShown() and f.lootFace.__tex == 521744, "nothing live: the picture")
  local models = 0
  for _, o in ipairs(ALL) do if o.__kind == "PlayerModel" and o.__client == owner then models = models + 1 end end
  assert(models == 1 and m.__keepModel == true, "one model, whatever is shown, kept while the page is away: " .. models)
  assert(f.lootSub:GetText() == "Boss", "the loot panel's line: the kind's word")
  DM.ShowBoss(B["Strongbox"])
  assert(f.lootSub:GetText() == "Chest", "an object's word: Chest")

  -- portraits the client draws late: blank at first, all drawn again on PORTRAITS_UPDATED (a burst, one redraw 0.2 s
  -- later), else a second after the page shows; never while it is hidden
  PORTRAIT.defer, PORTRAIT.ready = true, false
  local deep = { floors = { { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } }, bosses = {} }
  for i = 1, 5 do deep.bosses[i] = { n = "Deep Boss " .. i, k = "boss", d = 1000 + i, i = {}, f = 1, x = i / 6, y = 0.5 } end
  D.dfix2 = deep
  DM.Fill({ key = "dfix2", name = "Fixture Deep" }, "bosses")
  local function faces()
    local list, blank = {}, 0
    for _, r in ipairs(f.bossRows) do if r:IsShown() then list[#list + 1] = r.icon end end
    for i = 1, f.pinCount do list[#list + 1] = f.pins[i].face end
    list[#list + 1] = f.lootFace
    for _, x in ipairs(list) do if not x.__portrait then blank = blank + 1 end end
    return #list, blank
  end
  local n, blank = faces()
  assert(n == 11 and blank == 11 and f.pinCount == 5, "five rows, five pins and the loot face, all blank so far: " .. n .. ", " .. blank)
  PORTRAIT.ready = true
  calls = PORTRAIT.calls
  f.__scripts.OnEvent(f, "PORTRAITS_UPDATED"); f.__scripts.OnEvent(f, "PORTRAITS_UPDATED")
  assert(PORTRAIT.calls == calls, "not at once: the event comes in bursts")
  tick(owner, 0.3)
  n, blank = faces()
  assert(PORTRAIT.calls - calls == 11 and blank == 0, "PORTRAITS_UPDATED: every face drawn from a model drawn again, once: " .. (PORTRAIT.calls - calls))
  PORTRAIT.ready = false
  DM.Fill({ key = "dfix2", name = "Fixture Deep" }, "bosses")
  PORTRAIT.ready = true
  tick(owner, 1.1)
  n, blank = faces()
  assert(blank == 0, "no event: drawn again a second after the dungeon opened")
  tick(owner, 3)
  PORTRAIT.ready = false
  DM.Fill({ key = "dfix2", name = "Fixture Deep" }, "bosses")
  tick(owner, 3.5)
  PORTRAIT.ready = true
  f:Hide()
  calls = PORTRAIT.calls
  f.__scripts.OnEvent(f, "PORTRAITS_UPDATED"); tick(owner, 0.3)
  assert(PORTRAIT.calls == calls and DM.RedrawFaces() == 0, "a hidden page draws nothing")
  f:Show()
  tick(owner, 1.1)
  n, blank = faces()
  assert(blank == 0, "the page shown again: drawn a second later")
  PORTRAIT.defer, PORTRAIT.ready = false, false
  D.dfix, D.dfix2 = nil, nil

  -- the chips: Blackrock Depths lists its bosses, rares and the rest at first, each chip counting its kind
  DM.Open(DM.Find("blackrock depths"), "bosses")
  local d = f.data
  local per = {}
  for _, b in ipairs(d.bosses) do local k = DM.Kind(b); per[k] = (per[k] or 0) + 1 end
  local function rows()
    local all, trash = 0, 0
    for _, r in ipairs(f.bossRows) do if r:IsShown() then all = all + 1; if DM.Kind(r.boss) == "trash" then trash = trash + 1 end end end
    return all, trash
  end
  local chip = {}
  for _, c in ipairs(f.chips) do chip[c.kind] = c end
  local all, trash = rows()
  assert(per.trash and per.trash > 0 and all == per.boss + per.rare + (per.other or 0) and trash == 0, "Blackrock Depths at first: no trash rows")
  for k, c in pairs(chip) do assert(c.text:GetText() == tostring(per[k] or 0), "the " .. k .. " chip counts its kind") end
  assert(chip.other:IsShown() == ((per.other or 0) > 0) and chip.boss:GetAlpha() == 1 and chip.trash:GetAlpha() == 0.45 and chip.trash.icon.__desat, "a chip that is off is faded")
  lines = {}; chip.trash.__scripts.OnEnter(chip.trash)
  assert(#lines == 1 and lines[1]:find("Click to show", 1, true), "a chip's tooltip")
  chip.trash.__scripts.OnClick(chip.trash)
  all, trash = rows()
  assert(all == #d.bosses and trash == per.trash and env.QuestBankDB.settings.djShow.trash == true and chip.trash:GetAlpha() == 1, "the Trash chip adds the trash, and is kept")
  check("Dungeon Journal, Blackrock Depths, with Trash")
  -- (drawn scrolled to the end, where the trash is listed)
  local _, hi = f.bossScroll.bar:GetMinMaxValues()
  f.bossScroll.bar:SetValue(hi)
  check("Dungeon Journal, Blackrock Depths, with Trash, scrolled to the end")
  layouts[#layouts + 1] = dumpLayout(UI.frame, "Dungeon Journal, Blackrock Depths, with Trash")
  -- trash on the map: small grey pins (the Stockade's trash stands where it was seen)
  DM.Open(DM.Find("stockade"), "map")
  local grey = 0
  for i = 1, f.pinCount do
    local p = f.pins[i]
    if DM.Kind(p.boss) == "trash" then grey = grey + 1; assert(p.size == 18 and p.ring.__vertex[1] == 0.55, "a trash pin: small and grey") end
  end
  assert(grey >= 1, "the Stockade's trash on its map: " .. grey)
  check("Dungeon Journal, The Stockade, map with trash")
  chip.trash.__scripts.OnClick(chip.trash)
  for i = 1, f.pinCount do assert(DM.Kind(f.pins[i].boss) ~= "trash", "trash off: off the map too") end
  -- every chip off: one line says why, no rows, no pins
  DM.Open(DM.Find("blackrock depths"), "bosses")
  for _, k in ipairs({ "boss", "rare", "other" }) do chip[k].__scripts.OnClick(chip[k]) end
  all = rows()
  assert(all == 0 and f.bossEmpty:IsShown() and f.bossEmpty:GetText() == "All hidden by the filter" and f.boss == nil and not f.lootModel:IsShown(), "all hidden: the line, no rows, no loot")
  DM.ShowTab("map")
  assert(f.pinCount == 0, "all hidden: no pins")
  check("Dungeon Journal, Blackrock Depths, all hidden")
  for _, k in ipairs({ "boss", "rare", "other" }) do chip[k].__scripts.OnClick(chip[k]) end
  assert(show.boss and show.rare and show.other and not show.trash and not f.bossEmpty:IsShown(), "back as it was")
  -- each wing together: the Monastery's wings in one block each, the bosses first in each
  DM.Open(DM.Find("scarlet monastery"), "bosses")
  local seen, last, order = {}, nil, {}
  for _, r in ipairs(f.bossRows) do
    if r:IsShown() then
      local w = r.boss.w
      assert(w == last or not seen[w], "the wing " .. tostring(w) .. " in one block")
      seen[w], last = true, w
      order[#order + 1] = DM.Kind(r.boss)
      assert(r.sub:GetText() == w, "a row's line: its wing")
    end
  end
  assert(order[1] == "boss" and DM.Kind(f.bossRows[1].boss) == "boss", "a wing starts with its bosses")
  DM.Open(DM.Find("City of Dalaran"), "bosses")
  check("Dungeon Journal, City of Dalaran")
  layouts[#layouts + 1] = dumpLayout(UI.frame, "Dungeon Journal, City of Dalaran")
  DM.Open(DM.Find("deadmines"), "map"); DM.ShowFloor(2)
  UI:ShowTab(1); UI:Refresh()
end

-- 5.4: the close X sits at the end of the title strip, well inside the window's border (it sat 3 px into the border);
-- Classic Era's padded 32 px X keeps its size, and its art lands in the same place
do
  GEN = GEN + 1
  local close
  for _, o in ipairs(ALL) do if o.__template == "UIPanelCloseButton" and o.__parent == UI.frame then close = o end end
  local r, w = rectOf(close), rectOf(UI.frame)
  assert(r.r - r.l == 20 and r.t - r.b == 20 and w.r - r.r == 14 and w.t - r.t == 13, "the close X: 20 px, 14 px in from the right and 13 from the top")
  local env = owner.env
  local real = env.CreateFrame
  env.CreateFrame = function(kind, name, parent, template)
    local f = real(kind, name, parent, template)
    if template == "UIPanelCloseButton" then f.__w, f.__h = 32, 32 end
    return f
  end
  local holder = real("Frame", nil, env.UIParent)
  local era = UI.CloseButton(holder)
  env.CreateFrame = real
  local p = era.__points[1]
  assert(era.__w == 32 and p.point == "TOPRIGHT" and p.x == -8 and p.y == -7, "Classic Era's X: 32 px with 6 px of air, so its art sits 14 and 13 px in too")
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
  -- its close X sits inside the border, as the window's does (it sat on the border's corner)
  local x
  for _, o in ipairs(ALL) do if o.__parent == lf and o.__template == "UIPanelCloseButton" then x = o end end
  assert(x and x.__w == 20 and x.__points[1].x == -14 and x.__points[1].y == -13, "the link box's close X is inside its border")
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
-- the next stop reads the arrow's way there (Travel.lua: the flight paths you know, boats, the hearthstone)
do
  local nextLeg
  for _, l in ipairs(v3.legs.items) do if not nextLeg and l:IsShown() and l ~= handed then nextLeg = l end end
  assert(nextLeg and nextLeg.name:GetText():find(QB.routeNow.legs[1].stop.name, 1, true) and nextLeg.travel:GetText():find(" · about %d+ min$"),
    "the next stop: the way the arrow shows it: " .. tostring(nextLeg and nextLeg.travel:GetText()))
  print("  next leg:", nextLeg.travel:GetText(), nextLeg.name:GetText())
end
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
  local x
  for _, o in ipairs(ALL) do if o.__parent == owner.env.QuestBankErrors and o.__template == "UIPanelCloseButton" then x = o end end
  assert(x and x.__w == 20 and x.__points[1].x == -14 and x.__points[1].y == -13, "the problems box's close X is inside its border")
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
-- 5.1: the party as the game shows it, with or without QuestBank: what each lacks, the share, the next step, together
do
  local S, env = owner.QB.Sync, owner.env
  owner.party = { { "Brann", "WARRIOR", 18, pos = { inst = 0, wx = -10500, wy = 1050 } }, { "Nowen", "ROGUE", 19, pos = { inst = 0, wx = -8700, wy = 500 } } }
  owner.pos = { inst = 0, wx = -8830, wy = 480 }
  owner.pushable = { [971] = true, [1275] = true, [1199] = true }
  local units = S.GroupUnits()
  assert(#units == 3 and units[1].me and units[2].name == "Brann" and units[2].class == "WARRIOR" and units[3].level == 19, "the group as the game lists it")
  assert(S.YardsTo(units[3]) == 132 and S.YardsTo(units[2]) > 1000, "yards to each member")
  local sh = S.Shareable()
  assert(#sh == 3, "three shareable quests in the log")
  local lackB, knownB = S:Lacking(units[2], sh)
  local lackN, knownN = S:Lacking(units[3], sh)
  assert(knownB and #lackB == 2 and not knownN and #lackN == 3, "Brann (QuestBank) lacks two; Nowen (no QuestBank) gets all three")
  UI:ShowTab(4); UI:Refresh()
  assert(v4.title:GetText() == "Party of 3", "the title: " .. v4.title:GetText())
  local rows = {}
  for _, m in ipairs(v4.members.items) do if m:IsShown() then rows[#rows + 1] = m end end
  assert(#rows == 2 and rows[1].name:GetText() == "Brann" and rows[1].lack:GetText() == "lacks 2 of yours" and rows[1].bank:GetText():find("QuestBank", 1, true), "Brann's row: " .. tostring(rows[1].lack:GetText()))
  assert(rows[2].name:GetText() == "Nowen" and rows[2].lack:GetText() == "share 3" and rows[2].bank:GetText() == "No QuestBank" and rows[2].sub:GetText():find("132 yd", 1, true), "Nowen's row: " .. tostring(rows[2].sub:GetText()))
  assert(v4.shareBtn:GetText() == "Share 3" and v4.shareBtn:IsEnabled() and v4.postBtn:IsEnabled(), "the share button counts what the party lacks")
  local tog = 0
  for _, r in ipairs(v4.together.items) do if r:IsShown() then tog = tog + 1 end end
  assert(tog >= 3 and v4.togetherHead:IsShown() and v4.together.items[1].status:GetText() == "2 of you", "quests you hold together: " .. tog)
  -- the share: one push now, the rest every second and a half
  owner.pushed = {}
  v4.shareBtn.__scripts.OnClick(v4.shareBtn)
  assert(#owner.pushed == 1, "the first quest is pushed at once")
  tick(owner, 2); assert(#owner.pushed == 2, "the second after the pause")
  tick(owner, 2); tick(owner, 2); assert(#owner.pushed == 3, "and the third; then it stops")
  -- the next step as a line for party chat
  local P = env.QuestBankPost
  local line = S.NextStepText()
  v4.postBtn.__scripts.OnClick(v4.postBtn)
  if line then
    assert(P:IsShown() and P.eb:GetText():find("^QuestBank next stop: ") and #P.eb:GetText() <= 255, "the next step is offered for chat: " .. P.eb:GetText())
    P.cancel.__scripts.OnClick(P.cancel)
  else
    assert(owner.chat[#owner.chat]:find("No next step", 1, true), "no route: said")
  end
  owner.party, owner.pushable = nil, nil
  UI:Refresh()
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
  -- drawn for review: the Minimap and Map rows and the health and mana numbers, near the bottom
  do
    local sf = v5.scroll
    local _, hi = sf.bar:GetMinMaxValues()
    sf.bar:SetValue(math.min(hi, 780)); UI:Refresh()
    layouts[#layouts + 1] = dumpLayout(UI.frame, "Settings, scrolled to the Map")
    sf.bar:SetValue(0); UI:Refresh()
  end
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

-- travel data for the step-by-step arrow (gen_data.py from travel.py): the route planner's hub rows keep their order and
-- first five fields (D.NPC's hub fields and D.DIST index them), every hub with flights carries its client flight master,
-- every flight decodes to two hubs, and the ten rides end on the two continents
do
  local D = QB.Data
  local old = {
    A = { { "Aerie Peak", 0, 284, -2003, 1 }, { "Booty Bay", 0, -14272, 300, 1 }, { "Booty Bay", 0, -14473, 464, 1 },
          { "Chillwind Camp", 0, 931, -1430, 0 }, { "Crown Guard Tower", 0, 1858, -3658, 0 } },
    H = { { "Booty Bay", 0, -14444, 510, 1 }, { "Crown Guard Tower", 0, 1858, -3658, 0 }, { "Eastwall Tower", 0, 2499, -4743, 0 },
          { "Flame Crest", 0, -7504, -2188, 0 }, { "Grom'gol", 0, -12414, 146, 1 } },
  }
  local at = {}
  for i = 1, #D.ALPHA do at[D.ALPHA:sub(i, i)] = i end
  for fac, rows in pairs(old) do
    local hubs = D.HUB[fac]
    for i, r in ipairs(rows) do
      for k = 1, 5 do assert(hubs[i][k] == r[k], fac .. " hub " .. i .. " field " .. k .. " moved: " .. tostring(hubs[i][k])) end
    end
    for i, h in ipairs(hubs) do
      assert(#h == 10, fac .. " hub " .. i .. " has its ten fields")
      assert(h[10] ~= 0 or (h[6] > 0 and h[7] > 0), fac .. " " .. h[1] .. ": a hub with flights has its TaxiNodes id and map")
    end
    local fly = D.FLY[fac]
    for e = 1, #fly, 4 do
      local a, b = at[fly:sub(e, e)], at[fly:sub(e + 1, e + 1)]
      local min = ((at[fly:sub(e + 2, e + 2)] - 1) * 64 + at[fly:sub(e + 3, e + 3)] - 1) / 10
      assert(a and b and a ~= b and a <= #hubs and b <= #hubs and min > 0, fac .. " flight " .. (e + 3) / 4 .. " decodes to two hubs")
    end
  end
  assert(#D.FLY.A == 588 and #D.FLY.H == 612, "147 Alliance and 153 Horde flights: " .. #D.FLY.A / 4 .. ", " .. #D.FLY.H / 4)
  assert(#D.LINK == 10, "ten rides: " .. #D.LINK)
  for _, l in ipairs(D.LINK) do
    for e = 4, 5 do assert(l[e][1] == 0 or l[e][1] == 1, l[2] .. " to " .. l[e][7] .. " ends on a continent") end
  end
end

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
  -- the minimap reads the pick-ups between the arrow's looks: the hand-in list and the arrow's choice on it stay, so the
  -- way to each hand-in is worked out once a second, not at every look
  do
    local TV, opts, vias = QB.Travel, 0, 0
    local saveOpts, saveVia = TV.Opts, TV.Via
    TV.Opts = function(...) opts = opts + 1; return saveOpts(...) end
    TV.Via = function(...) vias = vias + 1; return saveVia(...) end
    for i = 1, 20 do
      owner.clock = owner.clock + 0.05
      F.__scripts.OnUpdate(F, 0.05)
      if i % 2 == 0 then QB.Mini.List() end
    end
    TV.Opts, TV.Via = saveOpts, saveVia
    local n = #A.ListFor("handin")
    assert(A.Guided() and n >= 1 and opts >= 1 and opts <= 2 and vias <= 2 * n,
      string.format("a second of looks beside the minimap: %d plans of the ways, %d ways to %d hand-ins", opts, vias, n))
  end
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
  -- 5.3: a click opens the quest; its Giver button sets the waypoint
  local rq = row.q
  UI.detailOpen = {} -- (earlier tests poked rows open)
  row.__scripts.OnClick(row, "LeftButton")
  assert(UI.detailOpen[rq.id], "a click opens the quest's details")
  local det
  for _, c in ipairs(v2.cards.items) do for _, d in ipairs(c.details.items) do if d:IsShown() and d.q == rq then det = d end end end
  assert(det and det.from:GetText():find(rq.give.n, 1, true), "the details name the giver")
  det.goGive.__scripts.OnClick(det.goGive)
  t = A.Target()
  assert(A.Mode() == "pin" and t and t.kind == "pin" and t.name == rq.give.n, "the Giver button pins the arrow to the giver: " .. tostring(t and t.name))
  row.__scripts.OnClick(row, "LeftButton")
  assert(not UI.detailOpen[rq.id], "a second click closes it")
  assert(A.toldPin, "and it said so, once this session (the first pin above did)")
  -- the right-click menu: the four targets, the hearthstone in the steps, and Hide
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
  assert(#labels == 6 and hide and route and labels[4]:find("%(now%)") and labels[5] == "Hearthstone in the steps: on",
    "the menu lists the four targets, the current one marked, the hearthstone, and Hide: " .. table.concat(labels, " | "))
  for _, pr in ipairs(checkLayout(M, "arrow menu")) do problems[#problems + 1] = pr end
  route.__scripts.OnClick(route)
  assert(not M:IsShown() and A.Mode() == "route", "choosing the route from the menu")
  F.__scripts.OnClick(F, "RightButton")
  for _, b in ipairs(M.items) do if b:IsShown() and b.label:GetText() == "Hide the arrow" then b.__scripts.OnClick(b) end end
  assert(not F:IsShown() and not QB:Settings().arrow, "Hide in the menu hides it")
  QB:Settings().arrowPin = nil
end

----------------------------------------------------------------------------
-- travel guidance (Travel.lua): the router and the live guide, checked on what they hand the arrow (TV.Route's plan,
-- TV.Guide's g). Two fresh characters: a dwarf warrior for the Alliance and an orc warrior for the Horde
----------------------------------------------------------------------------
local function lightClient(o)
  local c = newClient(o)
  c.ev(c.QB.eventFrame, "ADDON_LOADED", "QuestBank")
  c.ev(c.QB.eventFrame, "PLAYER_LOGIN")
  tick(c, 1)
  return c
end
local brann = lightClient({
  name = "Brann", level = 30, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1, race = "Dwarf",
  log = { { 7, 0 } }, done = { [783] = true }, group = false, guild = false, world = { 0, -8833, 479 }, bind = "Goldshire",
  riding = false, bagSlots = {}, map = 1453,
})
do
  local c, TV, D = brann, brann.QB.Travel, brann.QB.Data
  local T = D.TEX
  local function here() return c.QB.API.WorldPosition() end
  local function place(h, dx, name) return { name = name or h[1], c = h[2], wx = h[3] + (dx or 0), wy = h[4] } end
  local function kinds(plan)
    local out = {}
    for _, l in ipairs(plan and plan.legs or {}) do out[#out + 1] = l.kind .. (l.town and (" " .. l.town) or "") end
    return table.concat(out, ", ")
  end
  local function has(plan, kind, town)
    for _, l in ipairs(plan and plan.legs or {}) do if l.kind == kind and (not town or l.town == town) then return l end end
  end
  local function learn() fireTV(c, "PLAYER_ENTERING_WORLD"); tick(c, 3.1) end
  local sw, lake, gz, th = hubOf(c, "Stormwind"), hubOf(c, "Lakeshire"), hubOf(c, "Gadgetzan"), hubOf(c, "Theramore")

  -- lands and binds: Teldrassil and Sardor Isle are islands; a bind's name finds its inn (an inn's own name too)
  assert(TV.Land(1, 9885, 2515) == 2 and TV.Land(1, 9802, 983) == 2, "Darnassus and Dolanaar are on Teldrassil's canopy")
  assert(TV.Land(1, 8644, 841) == 4 and TV.Land(1, 8532, 1024) == 4 and TV.Land(1, 8799, 970) == 4,
    "Rut'theran's flight master, pier and portal lie at the tree's foot, 1,300 yards below the canopy: a land of their own")
  assert(TV.Land(1, 6341, 558) == 1 and TV.Land(0, -8833, 479) == 0, "Auberdine and Stormwind are on their continents")
  local fm = hubOf(c, "Feathermoon")
  assert(TV.Land(1, fm[3], fm[4]) == 3, "Feathermoon's flight master is on Sardor Isle")
  assert(TV.Land(1, -4187, 3287) == 3 and TV.Land(1, -4120, 3287) == 3 and TV.Land(1, -4348, 2444) == 1,
    "Feathermoon's pier and a boat docked at it are on Sardor Isle; the Forgotten Coast's pier is not")
  -- up from Rut'theran to the canopy and down again: by the portal, never a walk up or down the tree
  local opts = TV.Opts("pin")
  local up = TV.Route({ c = 1, wx = 8644, wy = 841 }, { name = "Dolanaar", c = 1, wx = 9802, wy = 983 }, opts)
  assert(up and up.legs[1].kind == "portal" and up.legs[1].town == "Darnassus" and #up.legs == 2,
    "Rut'theran's flight master to Dolanaar: the portal up, then the walk: " .. kinds(up))
  local down = TV.Route({ c = 1, wx = 9802, wy = 983 }, { name = "Vesprystus", c = 1, wx = 8641, wy = 841 }, opts)
  assert(down and down.legs[1].kind == "portal" and down.legs[1].town == "Rut'theran Village" and #down.legs == 2,
    "Dolanaar to Rut'theran's flight master: the portal down, then the walk: " .. kinds(down))
  local off = TV.Route({ c = 1, wx = 9802, wy = 983 }, { name = "Auberdine", c = 1, wx = 6341, wy = 558 }, opts)
  assert(off and off.legs[1].kind == "portal" and has(off, "fly", "Auberdine"), "Dolanaar to Auberdine: the portal down, then the flight: " .. kinds(off))
  local home = TV.Route({ c = 1, wx = 6341, wy = 558 }, { name = "Denalan", c = 1, wx = 9510, wy = 719 }, opts)
  assert(home and has(home, "portal", "Darnassus"), "Auberdine to Denalan by Lake Al'Ameth: the portal up on the way: " .. kinds(home))
  assert(TV.Graph("A").n == 60 and TV.Graph("H").n == 50 and TV.Graph("A").h == #D.HUB.A, "the graphs: the hubs in D.HUB's order, then two docks a ride")
  local inn = {}
  for _, r in ipairs(D.BIND) do inn[r[1]] = r end
  for _, case in ipairs({ { "Stormwind City", "Stormwind" }, { "Goldshire", "Goldshire" }, { "Northshire Abbey", "Northshire Abbey" },
                          { "Thunderbrew Distillery", "Kharanos" }, { "The Crossroads", "Crossroads" }, { "The Sepulcher", "The Sepulcher" } }) do
    c.o.bind = case[1]
    local b, r = TV.Bind(), inn[case[2]]
    assert(b and r and b.name == case[1] and b.c == r[2] and b.wx == r[3] and b.wy == r[4], "bound at " .. case[1] .. ": the hearthstone lands at " .. case[2])
  end
  c.o.bind = "Nowhere"
  assert(TV.Bind() == nil, "a bind QuestBank has no inn for: nowhere")
  c.o.bind = "Goldshire"

  -- the client never says which flight points you know (no C_TaxiMap): every flight master counts, as before
  local saveTaxi = c.env.C_TaxiMap
  c.env.C_TaxiMap = nil
  learn()
  assert(next(TV.DB().known) == nil and next(TV.DB().readC) == nil, "nothing read: nothing kept")
  standAt(c, 0, sw[3], sw[4])
  local toGz = place(gz, 30)
  local plan = TV.Route(here(), toGz, TV.Opts("pin"))
  assert(has(plan, "fly"), "never read: the flights all count: " .. kinds(plan))
  local n, total, read = TV.Known("A", 0)
  assert(n == total and total == 18 and not read, "and the count says so: " .. n .. " of " .. total)
  local set = c.QB:Settings()
  set.arrowMode, set.arrowPin = "pin", { name = "Gadgetzan", c = toGz.c, wx = toGz.wx, wy = toGz.wy }
  local way = TV.WayLines()
  assert(way[1]:find("^Way to Gadgetzan, about %d+ min: ") and way[2]:find("known on Eastern Kingdoms (assumed)", 1, true),
    "/qb way: the steps and where the flight paths come from: " .. table.concat(way, " / "))
  print("/qb way: " .. table.concat(way, " / "))
  c.env.C_TaxiMap = saveTaxi

  -- the world map says none are found: tram, walk and boat from Stormwind to Theramore, never a flight
  c.taxiKnown = {}
  learn()
  local db = TV.DB()
  assert(db.known[2] == false and db.known[5] == false and db.readC[0] and db.readC[1], "the world map read: nothing found on either continent")
  assert(c.env.QuestBankDB.diag.taxi.cont > 40 and c.env.QuestBankDB.diag.taxi.known == 0, "diag: what the continent maps answered")
  local g = TV.Guide(here(), place(th), "pin")
  assert(g.plan and g.leg.kind == "tram" and has(g.plan, "boat", "Theramore") and not has(g.plan, "fly"),
    "nothing known: the tram first, then the boat, no flight: " .. kinds(g.plan))
  assert(g.state == "approach" and g.step == "Tram to Ironforge" and g.info:find("yards", 1, true) and g.aim == g.leg.start,
    "on the way to the tram: " .. tostring(g.state) .. " / " .. tostring(g.step) .. " / " .. tostring(g.info))
  print("nothing known, Stormwind to Theramore: " .. kinds(g.plan) .. string.format(" (%.1f min)", g.plan.min))

  -- the same continent: a flight you know is a step; one you don't, and the arrow walks you there
  c.taxiKnown = { [2] = true, [5] = true }
  fireTV(c, "TAXI_NODE_STATUS_CHANGED"); fireTV(c, "TAXI_NODE_STATUS_CHANGED")
  tick(c, 1.5)
  assert(db.known[2] == "m" and db.known[5] == "m" and db.known[6] == false, "the world map's word, a second after the change")
  local toLake = place(lake, 50)
  g = TV.Guide(here(), toLake, "pin")
  assert(g.leg.kind == "fly" and g.state == "at" and g.step == "Fly to Lakeshire" and g.info == "Talk to the flight master"
    and g.act.atlas == "flightmaster" and g.act.file == T.gryphon, "at Stormwind's flight master: fly to Lakeshire: " .. tostring(g.step) .. " / " .. tostring(g.info))
  assert(#g.trail == 2 and g.trail[1] == g.leg.icon and g.trail[2].file == T.foot, "the trail: the flight, then the walk")
  assert(TV.Summary(g.plan):find("^Flight · about %d+ min$"), "summed up: " .. TV.Summary(g.plan))
  local direct = math.sqrt((toLake.wx - sw[3]) ^ 2 + (toLake.wy - sw[4]) ^ 2) * 1.3 / 7 / 60
  local R = TV.Reach(here(), TV.Opts("pin"))
  assert(TV.Via(R, toLake) < 0.6 * direct, "by time, Lakeshire is near: " .. TV.Via(R, toLake))
  c.taxiKnown[5] = nil
  fireTV(c, "TAXI_NODE_STATUS_CHANGED"); tick(c, 1.5)
  g = TV.Guide(here(), toLake, "pin")
  assert(g.leg.kind == "walk" and g.state == "walk" and g.step == nil and g.info:find("yards", 1, true) and g.aim == toLake,
    "Lakeshire not known: walk there: " .. tostring(g.info))
  assert(TV.Via(TV.Reach(here(), TV.Opts("pin")), toLake) >= direct - 0.01, "and by time it is as far as the walk")
  -- a short way: walking straight beats a flight that saves too little
  c.taxiKnown[5] = true
  fireTV(c, "TAXI_NODE_STATUS_CHANGED"); tick(c, 1.5)
  local near = { name = "Trade District", c = 0, wx = sw[3] + 300, wy = sw[4] }
  assert(kinds(TV.Route(here(), near, TV.Opts("pin"))) == "walk", "300 yards: a walk")

  -- the flight master's map: the place you fly to glows; the flight; landing
  g = TV.Guide(here(), toLake, "pin")
  openTaxi(c, { { nodeID = 2, name = "Stormwind, Elwynn", state = 0, slotIndex = 1 }, { nodeID = 6, name = "Ironforge, Dun Morogh", state = 2, slotIndex = 2 },
                { nodeID = 5, name = "Lakeshire, Redridge", state = 1, slotIndex = 3 } }, 1463)
  fireTV(c, "TAXIMAP_OPENED")
  tick(c, 0)
  g = TV.Guide(here(), toLake, "pin")
  local mark = c.env.QuestBankTaxiMark
  assert(g.info == "Pick Lakeshire" and mark and mark:IsShown() and mark.__points[1].rel == c.env.TaxiButton3 and mark.__parent == c.env.UIParent,
    "the map open: pick Lakeshire, its button marked: " .. tostring(g.info))
  assert(db.known[2] == "t" and db.known[5] == "t" and db.known[6] == false, "the map's word: Current and Reachable known, Unreachable as it was")
  local routes = TV.stats.routes
  c.env.TakeTaxiNode(3)
  assert(c.took == 3 and TV.flying and TV.flying.to == select(2, hubOf(c, "Lakeshire")) and TV.flying.min > 0, "the flight picked: to Lakeshire")
  fireTV(c, "TAXIMAP_CLOSED")
  assert(not mark:IsShown(), "the mark goes with the map")
  c.taxiOpen, c.taxi = nil, true
  standAt(c, 0, sw[3] - 1000, sw[4] - 300)
  tick(c, 1)
  g = TV.Guide(here(), toLake, "pin")
  assert(g.state == "underway" and g.step == "Flying to Lakeshire" and (g.info:find("^Lands in %d+:%d%d$") or g.info == "Landing")
    and g.icon.file == T.gryphon, "in the air: " .. tostring(g.step) .. " / " .. tostring(g.info))
  for _ = 1, 20 do c.clock = c.clock + 0.05; TV.Guide(here(), toLake, "pin") end
  assert(TV.stats.routes == routes, "no planning in the air")
  c.taxi = false
  standAt(c, 0, lake[3], lake[4])
  g = TV.Guide(here(), toLake, "pin")
  assert(g.state == "walk" and g.step == nil and (db.known[5] == "f" or db.known[5] == "t") and TV.stats.routes == routes + 1,
    "landed: plan again, the last walk: " .. tostring(g.state))

  -- the other continent: flights you know, the boat, and when a flight master is learned, the plan takes it
  c.taxiKnown = { [2] = true, [6] = true, [7] = true, [32] = true }
  db.known = {}
  learn()
  standAt(c, 0, sw[3], sw[4])
  g = TV.Guide(here(), toGz, "pin")
  local legs = g.plan.legs
  assert(legs[#legs].kind == "walk" and has(g.plan, "boat", "Theramore") and not has(g.plan, "fly", "Gadgetzan"),
    "Stormwind to Gadgetzan: the boat to Theramore, then on foot: " .. kinds(g.plan))
  for _, l in ipairs(legs) do
    if l.kind == "fly" then assert(TV.Usable("A", l.from) and TV.Usable("A", l.to), "a flight only between flight masters you know: " .. kinds(g.plan)) end
  end
  assert(g.step == g.leg.step and (g.state == "at" or g.state == "approach"), "the first step shows")
  print("Stormwind to Gadgetzan, four known: " .. kinds(g.plan) .. string.format(" (%.1f min)", g.plan.min))
  local ver = TV.ver
  c.taxiKnown[39] = true
  fireTV(c, "TAXI_NODE_STATUS_CHANGED")
  tick(c, 2)
  g = TV.Guide(here(), toGz, "pin")
  assert(TV.ver > ver and has(g.plan, "fly", "Gadgetzan") and has(g.plan, "fly", "Gadgetzan").step == "Fly to Gadgetzan",
    "Gadgetzan learned: the plan flies there: " .. kinds(g.plan))

  -- a boat: wait on the pier; on board the plan stands; at the far pier the next step
  c.taxiKnown = {}
  learn()
  standAt(c, 0, -3905, -586)
  local toTh = place(th)
  g = TV.Guide(here(), toTh, "pin")
  assert(g.leg.kind == "boat" and g.state == "at" and g.step == "Boat to Theramore" and g.info == "Wait for the boat" and g.act.atlas == "flightmasterferry",
    "on the pier: " .. tostring(g.step) .. " / " .. tostring(g.info))
  -- steps back from the pier, toward town, are never boarding: the arrow leads back to it, and there it waits again
  -- (150 yards back, off the boat's way, you walked off: from then on only the pier again counts)
  local function lookFor(s, cont, x, y)
    standAt(c, cont, x, y)
    for _ = 1, math.floor(s / 0.05) do c.clock = c.clock + 0.05; g = TV.Guide(here(), toTh, "pin") end
    return g
  end
  -- (130 yards out on the boat's way, after that, is not on board either: you never went back to the pier)
  for _, at in ipairs({ { -3905, -631, "45 yards back" }, { -3905, -656, "70 yards back" }, { -3905, -696, "110 yards back" },
                        { -3905, -736, "150 yards back" }, { -3830, -480, "130 yards out on the boat's way" }, { -3905, -631, "45 yards back" } }) do
    lookFor(3, 0, at[1], at[2])
    assert(g.state == "approach" and g.step == "Boat to Theramore" and g.aim == g.leg.start and g.info:find("yards", 1, true),
      at[3] .. " from the pier: back to it, not on board: " .. tostring(g.state) .. " / " .. tostring(g.info))
  end
  lookFor(1, 0, -3905, -586)
  assert(g.state == "at" and g.info == "Wait for the boat", "on the pier again: wait for the boat: " .. tostring(g.info))
  -- on board, then back on the pier (off before it sailed far): waiting again, not on board
  lookFor(1, 0, -4008, 516)
  assert(g.state == "underway", "out to sea: on board")
  lookFor(1, 0, -3905, -586)
  assert(g.state == "at" and g.info == "Wait for the boat", "back on the pier: wait for the boat: " .. tostring(g.state) .. " / " .. tostring(g.info))
  routes = TV.stats.routes
  standAt(c, 0, -4008, 516) -- out to sea
  for _ = 1, 20 do
    c.clock = c.clock + 0.05
    g = TV.Guide(here(), toTh, "pin")
  end
  assert(g.state == "underway" and g.info:find("^On board · about %d+ min$") and TV.stats.routes == routes, "on board: " .. tostring(g.info))
  standAt(c, 1, -4016, -4741)
  g = TV.Guide(here(), toTh, "pin")
  assert(g.leg.kind == "walk" and g.state == "walk" and TV.stats.routes == routes + 1, "at Theramore's pier: walk on: " .. tostring(g.state))

  -- the tram: no position under the ground; out at the far end, the next step
  standAt(c, 0, -8346, 514)
  local toIf = place(hubOf(c, "Ironforge"))
  g = TV.Guide(here(), toIf, "pin")
  assert(g.leg.kind == "tram" and g.state == "at" and g.info == "Take the tram" and g.act.file == T.tram, "at the tram: " .. tostring(g.info))
  c.instance, c.noPos = { "Deeprun Tram", 0, 369 }, true
  g = TV.Guide(here(), toIf, "pin")
  assert(g.state == "underway" and g.step == "On the tram to Ironforge" and g.info == "Ride to the end", "on the tram: " .. tostring(g.step))
  c.instance, c.noPos = nil, nil
  standAt(c, 0, -4840, -1330)
  g = TV.Guide(here(), toIf, "pin")
  assert(g.leg.kind == "walk" and g.state == "walk", "out in Ironforge: walk on: " .. kinds(g.plan))

  -- the hearthstone: in your bags, nearly ready, and QuestBank knows where it lands
  c.o.bagSlots = { { 6948, 1 } }
  c.o.bind = "Goldshire"
  standAt(c, 1, gz[3], gz[4])
  local gs = inn.Goldshire
  local toInn = { name = "Innkeeper Farley", c = 0, wx = gs[3] + 5, wy = gs[4] }
  local function hearthLeg() return has(TV.Guide(here(), toInn, "pin").plan, "hearth") end
  g = TV.Guide(here(), toInn, "pin")
  assert(g.leg.kind == "hearth" and g.state == "at" and g.step == "Hearth to Goldshire" and g.short == "Goldshire" and g.info == "Use your Hearthstone"
    and g.act.file == T.hearth and g.aim == nil and g.cd == nil, "far from Goldshire, the hearthstone first: " .. kinds(g.plan))
  assert(math.abs(g.leg.finish.wx - gs[3]) < 1 and math.abs(g.leg.min - 0.5) < 0.01, "it lands at the inn, half a minute")
  assert(TV.HearthLine() == "Hearthstone: Goldshire, ready", TV.HearthLine())
  c.hearthCD = c.clock - 3560
  g = TV.Guide(here(), toInn, "pin")
  assert(g.leg.kind == "hearth" and g.info == "Ready in 0:40" and g.cd and g.cd.duration == 3600, "nearly ready: " .. tostring(g.info))
  c.combat = true
  assert(TV.Guide(here(), toInn, "pin").info == "After the fight", "in a fight")
  c.combat = false
  c.hearthCD = c.clock
  tick(c, 5.1)
  assert(not hearthLeg(), "an hour to go: no hearth step")
  assert(TV.HearthLine():find("ready in 60 min", 1, true), TV.HearthLine())
  c.hearthCD = nil
  tick(c, 5.1)
  assert(hearthLeg(), "ready again")
  local saveCD = c.env.C_Container.GetItemCooldown
  c.env.C_Container.GetItemCooldown = function() error("no cooldowns here") end
  tick(c, 5.1)
  assert(not hearthLeg(), "the cooldown unreadable: no hearth step")
  c.env.C_Container.GetItemCooldown = saveCD
  c.o.bind = "Nowhere"
  tick(c, 5.1)
  assert(not hearthLeg() and TV.HearthLine():find("learns where it goes", 1, true), "bound somewhere QuestBank has no inn for: no hearth step")
  local X = { 0, gs[3] + 120, gs[4] - 40 }
  standAt(c, X[1], X[2], X[3])
  fireTV(c, "HEARTHSTONE_BOUND")
  standAt(c, 1, gz[3], gz[4])
  local hl = hearthLeg()
  assert(hl and math.abs(hl.finish.wx - X[2]) < 5 and math.abs(hl.finish.wy - X[3]) < 5 and TV.DB().bind.src == "bound",
    "bound there: the hearthstone lands where you stood")
  c.o.bind = "Goldshire"
  -- cast: the plan stands; the loading screen; landed, the spot is the bind's
  tick(c, 5.1)
  g = TV.Guide(here(), toInn, "pin")
  assert(g.leg.kind == "hearth", "the hearth step again")
  routes = TV.stats.routes
  fireTV(c, "UNIT_SPELLCAST_START", "player", "Cast-1", 8690)
  g = TV.Guide(here(), toInn, "pin")
  assert(g.state == "underway" and g.info == "Hearthing" and g.step == "Hearth to Goldshire", "casting: " .. tostring(g.info))
  fireTV(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 8690)
  c.noPos = true
  assert(TV.Guide(here(), toInn, "pin").state == "underway" and TV.stats.routes == routes, "the loading screen: as it was")
  c.noPos = nil
  standAt(c, 0, gs[3] + 8, gs[4] + 3)
  tick(c, 1)
  assert(TV.cast == nil and TV.DB().bind.src == "landed" and TV.DB().bind.name == "Goldshire" and math.abs(TV.DB().bind.wx - gs[3] - 8) < 1,
    "landed: the hearthstone's own spot, noted")
  g = TV.Guide(here(), toInn, "pin")
  assert(g.state == "there" or g.state == "walk", "and from there, the walk: " .. tostring(g.state))
  standAt(c, 1, gz[3], gz[4])
  set.arrowHearth = false
  TV.ver = TV.ver + 1 -- (the arrow's menu does this)
  assert(not hearthLeg() and not TV.Hearth("pin"), "the hearthstone switched off: no hearth step")
  set.arrowHearth = true
  TV.ver = TV.ver + 1
  local saveRoute = c.QB.routeNow
  c.QB.routeNow = { legs = { { kind = "flight" } } }
  assert(not has(TV.Guide(here(), toInn, "route").plan, "hearth"), "on the route, only the route's own hearth")
  c.QB.routeNow = { legs = { { kind = "hearth" } } }
  TV.ver = TV.ver + 1 -- (or the next look at the hearthstone, within 5 seconds)
  hl = has(TV.Guide(here(), toInn, "route").plan, "hearth")
  assert(hl and TV.Hearth("route").penalty == 0, "the route's hearth: a step, free")
  c.QB.routeNow = saveRoute
  c.o.bagSlots = {}
  tick(c, 5.1)
  assert(not hearthLeg() and TV.HearthLine() == nil, "no hearthstone: no step, no line")

  -- secret values: nothing learned, nothing broken; a secret answer to "on a flight?" is no
  local before = {}
  for k, v in pairs(TV.DB().known) do before[k] = v end
  ver = TV.ver
  c.taxiKnown, c.taxiSecret = { [4] = true, [8] = true }, true
  learn()
  local same = TV.ver == ver
  for k, v in pairs(TV.DB().known) do same = same and before[k] == v end
  assert(same, "secret flight points: nothing changes")
  c.taxiSecret = nil
  local saveTaxiOn = c.env.UnitOnTaxi
  c.env.UnitOnTaxi = function() return SECRET.bool() end
  standAt(c, 0, sw[3], sw[4])
  g = TV.Guide(here(), toLake, "pin")
  assert(g.state ~= "underway", "a secret 'on a flight': not flying: " .. g.state)
  c.env.UnitOnTaxi = saveTaxiOn
  c.ghost = true
  g = TV.Guide(here(), toLake, "pin")
  assert(g.state == "ghost" and g.info == "Resurrect first" and g.act.atlas == "Navigation-Tombstone-Icon", "dead: resurrect first")
  c.ghost = nil
  c.env.IsInInstance = function() return true, "party" end
  g = TV.Guide(here(), toLake, "pin")
  assert(g.state == "instance" and g.info == "Leave the dungeon first" and g.act.atlas == "dungeon", "in a dungeon")
  c.env.IsInInstance = nil
  -- no way known to an island on the other continent; one on this continent: straight at it, as before
  g = TV.Guide(here(), { name = "Shandris", c = 1, wx = fm[3], wy = fm[4] + 20 }, "pin")
  assert(g.plan and has(g.plan, "boat", "Feathermoon") and not has(g.plan, "fly"), "Feathermoon, no flight known: the ferry: " .. kinds(g.plan))
  print("nothing known, Stormwind to Feathermoon: " .. kinds(g.plan) .. string.format(" (%.1f min)", g.plan.min))
  -- Feathermoon's pier, on the boat's north side: on Sardor Isle, the way on is a walk, planned once (no plan a look)
  local shandris = { name = "Shandris", c = 1, wx = fm[3], wy = fm[4] + 20 }
  standAt(c, 1, -4187, 3287)
  routes = TV.stats.routes
  for _ = 1, 20 do c.clock = c.clock + 0.05; g = TV.Guide(here(), shandris, "pin") end
  assert(g.leg.kind == "walk" and g.state == "walk" and TV.stats.routes == routes + 1,
    "landed on Feathermoon's pier: walk on, one plan: " .. kinds(g.plan) .. ", " .. TV.stats.routes - routes .. " plans")
  -- a step's far end counts as reached only on its land: were the pier's spot off the isle's box, the plan (the coast's
  -- pier, then the boat back here) would end within reach of you at every look, and plan again at every look
  local isle = D.LAND[#D.LAND]
  D.LAND[#D.LAND] = { 1, -5131, 2778, -4195, 3963, 3 }
  standAt(c, 0, sw[3], sw[4]); TV.Guide(here(), shandris, "pin")
  standAt(c, 1, -4187, 3287)
  routes = TV.stats.routes
  for _ = 1, 20 do c.clock = c.clock + 0.05; g = TV.Guide(here(), shandris, "pin") end
  D.LAND[#D.LAND] = isle
  assert(TV.stats.routes == routes + 1, "the far end on another land: one plan, not one a look: " .. TV.stats.routes - routes)
  standAt(c, 0, sw[3], sw[4]); TV.Guide(here(), shandris, "pin")
  -- the ferry from the Forgotten Coast, standing 4 yards off its line: on board once, then the walk, no flicker
  local ferry = { { -4348, 2444 }, { -4906, 2778 }, { -5054, 2971 }, { -5121, 3186 }, { -5130, 3471 }, { -5089, 3706 }, { -5010, 3853 },
                  { -4880, 3940 }, { -4693, 3962 }, { -4417, 3904 }, { -4196, 3783 }, { -4197, 3287 } }
  standAt(c, 1, -4348, 2444)
  g = TV.Guide(here(), shandris, "pin")
  assert(g.leg.kind == "boat" and g.state == "at" and g.step == "Boat to Feathermoon", "on the Forgotten Coast's pier: " .. kinds(g.plan))
  local boarded, last, after = 0, g.state, {}
  for i = 1, #ferry - 1 do
    local a, b = ferry[i], ferry[i + 1]
    for k = 1, 20 do
      standAt(c, 1, a[1] + (b[1] - a[1]) * k / 20 + 4, a[2] + (b[2] - a[2]) * k / 20)
      c.clock = c.clock + 0.5
      g = TV.Guide(here(), shandris, "pin")
      if g.state == "underway" and last ~= "underway" then boarded = boarded + 1 end
      last = g.state
    end
  end
  for _ = 1, 20 do c.clock = c.clock + 0.05; after[#after + 1] = TV.Guide(here(), shandris, "pin").state end
  assert(boarded == 1 and g.leg.kind == "walk" and table.concat(after, " "):find("^walk[ walk]*$"),
    "the ferry to Feathermoon: on board once, then the walk: " .. boarded .. " boardings, then " .. table.concat(after, " "))
  standAt(c, 0, sw[3], sw[4])
  -- a waypoint inside a dungeon: its entrance; an island with no way in: said so
  c.instWorld = { [1581] = true, [2521] = true }
  c.QB.API.SetWaypoint(1581, 50, 50, "Inside")
  assert(set.arrowPin.name == "The Deadmines entrance" and c.chat[#c.chat]:find("Waypoint: Inside", 1, true),
    "a click inside the Deadmines: the arrow's pin at its entrance: " .. tostring(set.arrowPin.name))
  assert(not set.arrow and c.QB.Arrow.temp and c.QB.Arrow.temp.name == "The Deadmines entrance", "the arrow off: shown for that click")
  c.QB.API.SetWaypoint(2521, 50, 50, "Zephras Isle")
  assert(set.arrowPin.none and set.arrowPin.name == "Zephras Isle", "no way in known: the pin says so")
  assert(not c.QB.Arrow.temp and not c.env.QuestBankArrow:IsShown(), "and the arrow shown for the last click goes: never the old place")
  c.instWorld = nil
  -- TomTom, the arrow off: QuestBank's arrow shows the way while there is more to it than the last walk; each click
  -- replaces the last one's, and a click with only a walk to it (or no way there) leaves TomTom's arrow alone
  c.addons = { TomTom = { loaded = true } }
  c.env.TomTom = { AddWaypoint = function() return 1 end, IsCrazyArrowEmpty = function() return true end, RemoveWaypoint = function() end }
  c.QB.API.SetWaypoint(1446, 50, 30, "Gadgetzan", nil, toGz)
  assert(c.env.QuestBankArrow:IsShown() and c.QB.Arrow.temp and c.QB.Arrow.temp.travel, "with TomTom, another continent: QuestBank's arrow too")
  c.QB.API.SetWaypoint(1453, 50, 50, "Here", nil, { c = 0, wx = sw[3] + 20, wy = sw[4] })
  assert(not c.QB.Arrow.temp and not c.env.QuestBankArrow:IsShown(), "with TomTom, a walk after Gadgetzan: TomTom's arrow alone, not the way to Gadgetzan")
  c.QB.API.SetWaypoint(1446, 50, 30, "Gadgetzan", nil, toGz)
  assert(c.QB.Arrow.temp and c.QB.Arrow.temp.name == "Gadgetzan", "Gadgetzan again: QuestBank's arrow again")
  c.instWorld = { [2521] = true }
  c.QB.API.SetWaypoint(2521, 50, 50, "Zephras Isle")
  assert(not c.QB.Arrow.temp and not c.env.QuestBankArrow:IsShown(), "with TomTom, no way in known: not the way to Gadgetzan either")
  c.instWorld = nil
  c.addons, c.env.TomTom = nil, nil
  set.arrowPin, set.arrowMode = nil, "route"

  -- the flight master's map has the last word: one the world map called known that the map leaves out is not known,
  -- and the world map's word goes for this build. A map with no ids: by name. "New flight path discovered!"
  c.taxiKnown = { [2] = true, [5] = true, [4] = true, [32] = true }
  db.known, db.readC = {}, {}
  learn()
  assert(db.known[4] == "m" and db.known[32] == "m" and db.readC[1], "the world map: Sentinel Hill and Theramore known")
  standAt(c, 0, sw[3] + 10, sw[4])
  openTaxi(c, { { nodeID = 5, name = "Lakeshire, Redridge", state = 1, slotIndex = 2 } }, 1463)
  fireTV(c, "TAXIMAP_OPENED")
  local tdiag = c.env.QuestBankDB.diag.taxi
  assert(db.known[2] == "t" and db.known[5] == "t" and db.known[4] == false and db.known[32] == nil and db.readC[0] and not db.readC[1]
    and tdiag.scanBad == "70170", "the map leaves Sentinel Hill out: not known, and the world map is doubted on this build")
  fireTV(c, "TAXIMAP_CLOSED")
  assert(db.known[4] == false and db.known[32] == nil and not db.readC[1] and TV.Usable("A", select(2, hubOf(c, "Theramore"))),
    "a doubted world map: its 'found' counts for nothing, and Kalimdor, never read but by it, counts every flight master again")
  local saveAll = c.env.C_TaxiMap.GetAllTaxiNodes
  c.env.C_TaxiMap.GetAllTaxiNodes = function() return {} end
  openTaxi(c, { { name = "Stormwind, Elwynn", state = 0, slotIndex = 1 }, { name = "Ironforge, Dun Morogh", state = 1, slotIndex = 2 },
                { name = "Lakeshire, Redridge", state = 1, slotIndex = 3 } }, 1463)
  fireTV(c, "TAXIMAP_OPENED")
  assert(db.known[6] == "t" and db.known[5] == "t" and TV.slots[2] == 6 and TV.cur == select(2, hubOf(c, "Stormwind")),
    "no ids on the map: the flight masters by name")
  fireTV(c, "TAXIMAP_CLOSED")
  c.env.C_TaxiMap.GetAllTaxiNodes, c.taxiOpen = saveAll, nil
  local thel = hubOf(c, "Thelsamar")
  standAt(c, 0, thel[3] + 20, thel[4])
  ver = TV.ver
  fireTV(c, "UI_INFO_MESSAGE", 0, "Quest accepted")
  assert(db.known[8] == false and TV.ver == ver, "another message: nothing")
  fireTV(c, "UI_INFO_MESSAGE", 0, "New flight path discovered!")
  assert(db.known[8] == "n" and TV.ver > ver, "a new flight path, here: Thelsamar")
  tdiag.scanBad = nil

  -- many ways, at random (a fixed seed): every plan keeps the rules, and fast
  local seed = 20261013
  local function rnd(k) seed = seed * 16807 % 2147483647; return seed % k + 1 end
  local spots = {}
  for i = 1, #D.NPC, 7 do local p = D.NPC[i]; if p[5] == 0 or p[5] == 1 then spots[#spots + 1] = { c = p[5], wx = p[6], wy = p[7], name = p[1] } end end
  local binds = {}
  for _, r in ipairs(D.BIND) do binds[#binds + 1] = r end
  local cases, plans, unreachable = 2000, 0, 0
  routes = TV.stats.routes
  TV.stats.maxMs = 0
  for _ = 1, cases do
    local fac = rnd(2) == 1 and "A" or "H"
    local G = TV.Graph(fac)
    local known, readC = {}, {}
    for i = 1, G.h do
      local r = rnd(4)
      if r == 1 then known[G.taxi[i]] = "t" elseif r == 2 then known[G.taxi[i]] = false end
    end
    if rnd(2) == 1 then readC[0] = 1 end
    if rnd(2) == 1 then readC[1] = 1 end
    db.known, db.readC = known, readC
    local o = { fac = fac, mf = rnd(2) == 1 and 1 or 0.625, druid = rnd(4) == 1, mode = "pin" }
    if rnd(3) == 1 then
      local b = binds[rnd(#binds)]
      o.hearth = { kind = "hearth", c = b[2], wx = b[3], wy = b[4], name = b[1], min = 0.5 + rnd(90) / 60, penalty = 3, left = 0 }
    end
    local from, to = spots[rnd(#spots)], spots[rnd(#spots)]
    local p = TV.Route(from, to, o)
    if not p then
      unreachable = unreachable + 1
      assert(TV.Land(from.c, from.wx, from.wy) ~= TV.Land(to.c, to.wx, to.wy), "on one land there is always a way: on foot")
    else
      plans = plans + 1
      assert(p.min >= 0 and p.min < 1e6, "a plan's minutes are a number")
      local at = from
      for i, l in ipairs(p.legs) do
        if l.kind == "fly" then
          assert(TV.Usable(fac, l.from, o.druid) and TV.Usable(fac, l.to, o.druid), "a flight between flight masters you can use")
        elseif l.kind == "hearth" then
          assert(i == 1 and o.hearth and l.walk == 0, "the hearth only first, and only when offered")
        elseif l.kind ~= "walk" then
          assert(l.link and D.LINK[l.link][1]:find(fac, 1, true), "a ride of the faction's own: " .. l.kind)
        end
        local stop = l.start or (l.kind == "walk" and l.finish)
        if stop then
          assert(TV.Land(at.c, at.wx, at.wy) == TV.Land(stop.c, stop.wx, stop.wy), "a walk on one land: " .. kinds(p))
        end
        at = l.finish
      end
      assert(p.legs[#p.legs].kind == "walk" and at.wx == to.wx and at.wy == to.wy, "the last step walks to the target")
    end
  end
  assert(TV.stats.routes == routes + cases and TV.stats.maxMs < 2, string.format("%d routes, the slowest %.2f ms", cases, TV.stats.maxMs))
  print(string.format("travel: %d random ways, %d planned, %d unreachable (another island), the slowest %.2f ms", cases, plans, unreachable, TV.stats.maxMs))
  -- standing still plans nothing; walking on re-plans every couple of seconds at most
  db.known, db.readC = { [2] = "t", [5] = "t" }, { [0] = 1, [1] = 1 }
  TV.ver = TV.ver + 1
  standAt(c, 0, sw[3], sw[4])
  TV.Guide(here(), toLake, "pin")
  routes = TV.stats.routes
  for _ = 1, 100 do c.clock = c.clock + 0.05; TV.Guide(here(), toLake, "pin") end
  assert(TV.stats.routes == routes, "100 idle looks: no planning")
  standAt(c, 0, sw[3] - 60, sw[4] - 20)
  for _ = 1, 20 do c.clock = c.clock + 0.05; TV.Guide(here(), toLake, "pin") end
  assert(TV.stats.routes == routes + 1, "moved: one plan in those two seconds: " .. TV.stats.routes - routes)
end

-- the Horde: nothing known in Orgrimmar, Undercity is a zeppelin away
local grosh = lightClient({
  name = "Grosh", level = 30, cap = 60, faction = "Horde", className = "Warrior", class = "WARRIOR", classID = 1, race = "Orc",
  log = { { 7, 0 } }, done = {}, group = false, guild = false, world = { 1, 1320, -4649 }, bind = "Orgrimmar",
  riding = false, bagSlots = {}, map = 1411,
})
do
  local c, TV = grosh, grosh.QB.Travel
  c.taxiKnown = {}
  fireTV(c, "PLAYER_ENTERING_WORLD"); tick(c, 3.1)
  local uc = hubOf(c, "Undercity")
  local g = TV.Guide(c.QB.API.WorldPosition(), { name = "Undercity", c = uc[2], wx = uc[3], wy = uc[4] }, "pin")
  assert(g.leg.kind == "zeppelin" and g.state == "at" and g.step == "Zeppelin to Undercity" and g.info == "Wait for the zeppelin"
    and g.act.file == c.QB.Data.TEX.zeppelin, "at the tower: the zeppelin to Undercity: " .. tostring(g.step) .. " / " .. tostring(g.info))
  -- across the tower to the Grom'gol zeppelin's platform, 51 yards on: not on board; the arrow leads back to Undercity's
  local toUc = { name = "Undercity", c = uc[2], wx = uc[3], wy = uc[4] }
  standAt(c, 1, 1361, -4631)
  for _ = 1, 40 do c.clock = c.clock + 0.05; g = TV.Guide(c.QB.API.WorldPosition(), toUc, "pin") end
  assert(g.state == "approach" and g.step == "Zeppelin to Undercity" and g.aim == g.leg.start,
    "on the Grom'gol platform: back to Undercity's, not on board: " .. tostring(g.state) .. " / " .. tostring(g.info))
  standAt(c, 1, 1318, -4658)
  g = TV.Guide(c.QB.API.WorldPosition(), toUc, "pin")
  assert(g.state == "at" and g.info == "Wait for the zeppelin", "back on Undercity's platform: wait: " .. tostring(g.info))
  standAt(c, 1, 1320, -4649)
  local plan = TV.Route(c.QB.API.WorldPosition(), { name = "Darnassus", c = 1, wx = 9885, wy = 2515 }, TV.Opts("pin"))
  assert(plan == nil, "Darnassus: no way the Horde takes")
  -- a shaman: Astral Recall before the hearthstone (a quarter of its cooldown), the stone while Recall waits
  c.o.class, c.o.riding, c.o.bagSlots = "SHAMAN", true, { { 6948, 1 } }
  local h = TV.Hearth("pin")
  assert(h and h.kind == "recall" and h.name == "Orgrimmar" and h.penalty == 3, "Astral Recall ready: it goes first")
  c.recallCD = c.clock - 100
  h = TV.Hearth("pin")
  assert(h and h.kind == "hearth", "Recall cooling down: the hearthstone")
  c.o.class, c.o.riding, c.o.bagSlots, c.recallCD = "WARRIOR", false, {}, nil
end

-- an arrow moved by an older QuestBank was kept by the point the game chose for its 170x84 frame (CENTER, BOTTOMLEFT):
-- kept by its top now, where that top was, so the arrow stays put as the lines under it come and go
do
  local c = newClient({
    name = "Moira", level = 30, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1, race = "Dwarf",
    log = { { 7, 0 } }, done = {}, group = false, guild = false, world = { 0, -8833, 479 }, bind = "Goldshire",
    riding = false, bagSlots = {}, map = 1453,
  })
  c.env.QuestBankDB = { settings = { arrow = true, arrowPos = { "CENTER", 30, -40 } } }
  c.ev(c.QB.eventFrame, "ADDON_LOADED", "QuestBank")
  c.ev(c.QB.eventFrame, "PLAYER_LOGIN")
  tick(c, 1)
  local F, set = c.env.QuestBankArrow, c.QB:Settings()
  local function at(x, y)
    local p = F.__points[1]
    return #F.__points == 1 and p.point == "TOP" and p.relPoint == "TOP" and p.rel == c.env.UIParent and p.x == x and p.y == y
      and set.arrowPos[1] == "TOP" and set.arrowPos[2] == x and set.arrowPos[3] == y
  end
  assert(F and F:IsShown() and at(30, -498), "kept by CENTER 30,-40 (1600x1000 screen): by its top, 42 above that centre")
  c.QB.Arrow.frame, set.arrowPos = nil, { "BOTTOMLEFT", 100, 200 }
  F = c.QB.Arrow:Create()
  assert(at(-615, -716), "kept by BOTTOMLEFT 100,200: by its top's middle, 85 right and 84 up")
  set.arrowPos = { "TOP", 12, -34 }
  c.QB.Arrow.frame = nil
  F = c.QB.Arrow:Create()
  assert(at(12, -34), "kept by its top already: as it was")
end

----------------------------------------------------------------------------
-- the arrow on screen, step by step (Arrow.lua over Travel.lua): what it shows in each state, its art, its turn and
-- colour, every town's name on its lines, the nearest hand-in by the way there, a pin with no way there, TomTom, and
-- the minimap's step pin. Each state is a sheet "Arrow: ..." on the layout page
----------------------------------------------------------------------------
do
  local c, TV, A, D = brann, brann.QB.Travel, brann.QB.Arrow, brann.QB.Data
  local T = D.TEX
  local set, db = c.QB:Settings(), TV.DB()
  local function here() return c.QB.API.WorldPosition() end
  local function learn() fireTV(c, "PLAYER_ENTERING_WORLD"); tick(c, 3.1) end
  local function aimAt(name, cont, wx, wy) set.arrowMode, set.arrowPin = "pin", { name = name, c = cont, wx = wx, wy = wy } end
  local function has(kind) for _, l in ipairs(A.g and A.g.plan and A.g.plan.legs or {}) do if l.kind == kind then return l end end end
  local sw, lake, gz, th = hubOf(c, "Stormwind"), hubOf(c, "Lakeshire"), hubOf(c, "Gadgetzan"), hubOf(c, "Theramore")
  local inn = {}
  for _, r in ipairs(D.BIND) do inn[r[1]] = r end
  A:Set(true)
  local F = c.env.QuestBankArrow
  -- one look: the 20-a-second update and a frame drawn
  local function look() F.__scripts.OnUpdate(F, 1) end
  local function step() return F.step:IsShown() and F.step:GetText() or nil end
  local function says() return tostring(step()) .. " / " .. F.dist:GetText() end
  local function sheet(label)
    for _, pr in ipairs(checkLayout(F, label)) do problems[#problems + 1] = pr end
    layouts[#layouts + 1] = dumpLayout(F, label)
  end
  c.facing = 0
  assert(F.arrow.__atlas == "npe_arrowup" and F.arrow.__desat and F.glow.__atlas == "npe_arrowupglow" and F.glow.__blend == "ADD",
    "the game's own arrow and its glow")

  -- the same continent: at Stormwind's flight master, Lakeshire known. Its icon takes the arrow's place
  c.taxiKnown = { [2] = true, [5] = true }
  db.known, db.readC = {}, {}
  learn()
  standAt(c, 0, sw[3], sw[4])
  aimAt("Lakeshire", 0, lake[3] + 50, lake[4])
  look()
  assert(F.name:GetText() == "Lakeshire" and step() == "Fly to Lakeshire" and F.dist:GetText() == "Talk to the flight master"
    and F.act:IsShown() and F.act.__atlas == "flightmaster" and not F.arrow:IsShown() and F.stepIcon:IsShown() and F.stepIcon.__atlas == "flightmaster",
    "at the flight master: " .. says())
  assert(F.trail[1]:IsShown() and F.trail[2]:IsShown() and not F.trail[3]:IsShown() and F.trail[1].__alpha == 1 and F.trail[2].__alpha == 0.5
    and F.trail[2].__tex == T.foot and F.__h == 130, "the steps left: the flight, then the walk")
  -- something to do here: a ping every couple of seconds, growing and fading
  local pinged, grown = 0, false
  for _ = 1, 130 do
    F.__scripts.OnUpdate(F, 0.016)
    if F.ping:IsShown() then pinged, grown = pinged + 1, grown or (F.ping.__w > 40 and F.ping.__w < 96 and F.ping.__alpha < 0.9) end
  end
  assert(pinged > 20 and pinged < 60 and grown, "a ping at the flight master: " .. pinged .. " frames")
  lines = {}; F.__scripts.OnEnter(F)
  local tip = table.concat(lines, "\n")
  assert(tip:find("|A:flightmaster:14:14|a Fly to Lakeshire | ", 1, true) and tip:find("Walk to Lakeshire | %d+ min") and tip:find("About %d+ min in all%.")
    and tip:find("Flight paths: 2 of 18 known here", 1, true) and lines[#lines]:find("^Click: the Hand%-in Route"), "the tooltip lists the steps: " .. tip)
  sheet("Arrow: at the flight master")
  -- on the way there, the arrow points at it; the minimap pins it and draws the line to it
  standAt(c, 0, sw[3] + 150, sw[4])
  look()
  assert(F.arrow:IsShown() and not F.act:IsShown() and step() == "Fly to Lakeshire" and F.dist:GetText():find("^150 yards · %d+ min$"),
    "on the way to the flight master: " .. says())
  c.QB.Mini.Place()
  local Mini = c.QB.Mini
  assert(Mini.target and Mini.target.kind == "step" and Mini.labelText == "Fly to Lakeshire" and Mini.linesShown >= 1,
    "the minimap: the flight master is the target, named: " .. tostring(Mini.labelText))
  sheet("Arrow: on the way to a flight master")
  -- Lakeshire not known: a walk, no step line
  c.taxiKnown[5] = nil
  fireTV(c, "TAXI_NODE_STATUS_CHANGED"); tick(c, 1.5)
  standAt(c, 0, sw[3], sw[4])
  look()
  assert(not F.step:IsShown() and not F.stepIcon:IsShown() and F.dist:GetText():find("yards", 1, true) and F.arrow:IsShown() and not F.trail[1]:IsShown()
    and F.__h == 98, "Lakeshire not known: walk there: " .. says())
  sheet("Arrow: walk")
  c.QB.Mini.Place()
  assert(Mini.target and Mini.target.kind ~= "step", "a walk: no step on the minimap")

  -- its turn and colour: green and glowing ahead, gold to the side, red behind; eased, the short way round
  local me = here()
  local b0 = math.atan2(lake[4] - me.wy, lake[3] + 50 - me.wx)
  c.facing = b0
  tick(c, 1)
  assert(math.abs(F.arrow.__rot) < 0.01 and F.arrow.__vertex[2] > F.arrow.__vertex[1] and F.glow.__alpha > 0, "facing it: green, glowing")
  sheet("Arrow: walk, facing it")
  c.facing = b0 - 1
  F.__scripts.OnUpdate(F, 0.016)
  assert(F.arrow.__rot > 0 and F.arrow.__rot < 1 and F.glow.__rot == F.arrow.__rot, "a turn eases in: " .. F.arrow.__rot)
  tick(c, 1)
  assert(math.abs(F.arrow.__rot - 1) < 0.01 and F.glow.__alpha == 0, "and settles: " .. F.arrow.__rot)
  c.facing = b0 + math.pi
  tick(c, 1)
  assert(F.arrow.__vertex[1] > F.arrow.__vertex[2] and F.glow.__alpha == 0, "behind you: red")
  c.facing = b0 - 3
  tick(c, 1)
  c.facing = b0 + 3
  for _ = 1, 40 do
    F.__scripts.OnUpdate(F, 0.016)
    assert(math.abs(F.arrow.__rot) > 2.9, "from 3 to -3 the short way, behind you: " .. F.arrow.__rot)
  end
  tick(c, 1)
  assert(math.abs(F.arrow.__rot + 3) < 0.01, "and settles: " .. F.arrow.__rot)
  -- which way you face is a secret: the arrow dims, upright
  c.facing = SECRET.num()
  look()
  assert(F.arrow.__alpha == 0.3 and F.arrow.__rot == 0 and F.dist:GetText():find("yards", 1, true), "facing unknown: dimmed")
  c.facing = b0
  look()
  assert(F.arrow.__alpha == 1 and math.abs(F.arrow.__rot) < 0.01, "and back")

  -- the flight master's map: pick Lakeshire, its button marked; in the air; landed
  c.taxiKnown[5] = true
  fireTV(c, "TAXI_NODE_STATUS_CHANGED"); tick(c, 1.5)
  look()
  openTaxi(c, { { nodeID = 2, name = "Stormwind, Elwynn", state = 0, slotIndex = 1 }, { nodeID = 6, name = "Ironforge, Dun Morogh", state = 2, slotIndex = 2 },
                { nodeID = 5, name = "Lakeshire, Redridge", state = 1, slotIndex = 3 } }, 1463)
  fireTV(c, "TAXIMAP_OPENED")
  tick(c, 0)
  local mark = c.env.QuestBankTaxiMark
  assert(step() == "Fly to Lakeshire" and F.dist:GetText() == "Pick Lakeshire" and mark:IsShown() and mark.__points[1].rel == c.env.TaxiButton3,
    "the map open: " .. says())
  sheet("Arrow: the flight master's map")
  local routes = TV.stats.routes
  c.env.TakeTaxiNode(3)
  fireTV(c, "TAXIMAP_CLOSED")
  c.taxiOpen, c.taxi = nil, true
  standAt(c, 0, sw[3] - 1000, sw[4] - 300)
  tick(c, 1)
  assert(step() == "Flying to Lakeshire" and (F.dist:GetText():find("^Lands in %d+:%d%d$") or F.dist:GetText() == "Landing")
    and F.stepIcon.__tex == T.gryphon and F.arrow:IsShown() and F.arrow.__alpha == 0.85 and TV.stats.routes == routes, "in the air: " .. says())
  sheet("Arrow: in the air")
  c.taxi = false
  standAt(c, 0, lake[3], lake[4])
  A:Update()
  F.__scripts.OnUpdate(F, 0.016)
  assert(not F.step:IsShown() and F.arrow:IsShown() and (db.known[5] == "f" or db.known[5] == "t"), "landed: the walk: " .. says())
  assert(F.ping:IsShown() and F.arrow.__w > 48 and F.arrow.__w < 60, "a new step: the arrow pops, a ping: " .. F.arrow.__w)
  tick(c, 1)
  assert(not F.ping:IsShown() and F.arrow.__w == 48, "and settles")

  -- a boat: wait on the pier, its icon in the arrow's place; on board the plan stands; at the far pier, walk on
  c.taxiKnown = {}
  learn()
  standAt(c, 0, -3905, -586)
  aimAt("Theramore", 1, th[3], th[4])
  look()
  assert(step() == "Boat to Theramore" and F.dist:GetText() == "Wait for the boat" and F.act.__atlas == "flightmasterferry", "on the pier: " .. says())
  sheet("Arrow: on the pier")
  local track
  for _, l in ipairs(D.LINK) do if l[2] == "b" and l[4][7] == "Menethil Harbor" and l[5][7] == "Theramore" then track = l[6] end end
  local pts = {}
  for cc, x, y in track:gmatch("(%-?%d+),(%-?[%d.]+),(%-?[%d.]+)") do pts[#pts + 1] = { tonumber(cc), tonumber(x), tonumber(y) } end
  routes = TV.stats.routes
  standAt(c, pts[4][1], pts[4][2], pts[4][3])
  for _ = 1, 20 do c.clock = c.clock + 0.05; look() end
  assert(step() == "Boat to Theramore" and F.dist:GetText():find("^On board · about %d+ min$") and F.act:IsShown() and TV.stats.routes == routes,
    "on board: " .. says())
  sheet("Arrow: on board")
  standAt(c, 1, -4016, -4741)
  look()
  assert(step() ~= "Boat to Theramore" and TV.stats.routes == routes + 1, "at Theramore's pier: the next step: " .. says())

  -- the tram: no position under the ground; out at the far end, walk on
  local ifh = hubOf(c, "Ironforge")
  standAt(c, 0, -8346, 514)
  aimAt("Ironforge", 0, ifh[3], ifh[4])
  look()
  assert(step() == "Tram to Ironforge" and F.dist:GetText() == "Take the tram" and F.act.__tex == T.tram, "at the tram: " .. says())
  sheet("Arrow: at the tram")
  c.instance, c.noPos = { "Deeprun Tram", 0, 369 }, true
  look()
  assert(step() == "On the tram to Ironforge" and F.dist:GetText() == "Ride to the end" and F.act:IsShown(), "on the tram: " .. says())
  sheet("Arrow: on the tram")
  c.instance, c.noPos = nil, nil
  standAt(c, 0, -4840, -1330)
  look()
  assert(not F.step:IsShown() and F.arrow:IsShown(), "out in Ironforge: walk on: " .. says())
  -- a flight master you haven't learned, on the way
  db.known = {}
  learn()
  standAt(c, 0, lake[3], lake[4] + 20)
  aimAt("Lakeshire Inn", 0, lake[3] + 300, lake[4])
  look()
  assert(step() == "Learn this flight path" and F.stepIcon.__atlas == "taxinode_undiscovered" and F.dist:GetText():find("yards", 1, true) and F.arrow:IsShown(),
    "at Lakeshire's flight master, not learned: " .. says())
  sheet("Arrow: learn this flight path")

  -- the hearthstone: its icon with the cooldown's swipe, and the menu's switch
  c.o.bagSlots, c.o.bind = { { 6948, 1 } }, "Goldshire"
  standAt(c, 1, gz[3], gz[4])
  local gs = inn.Goldshire
  aimAt("Innkeeper Farley", 0, gs[3] + 5, gs[4])
  look()
  assert(step() == "Hearth to Goldshire" and F.dist:GetText() == "Use your Hearthstone" and F.act.__tex == T.hearth and not F.cd:IsShown(),
    "far from Goldshire, the hearthstone: " .. says())
  sheet("Arrow: hearthstone")
  c.hearthCD = c.clock - 3560
  look()
  assert(F.dist:GetText() == "Ready in 0:40" and F.cd:IsShown() and F.cd.__cd[2] == 3600, "nearly ready: the swipe: " .. says())
  sheet("Arrow: hearthstone, nearly ready")
  c.hearthCD = nil
  look()
  assert(not F.cd:IsShown(), "ready: no swipe")
  local function menuItem(label)
    F.__scripts.OnClick(F, "RightButton")
    for _, b in ipairs(c.env.QuestBankMenu.items) do if b:IsShown() and b.label:GetText() == label then return b end end
  end
  local item = menuItem("Hearthstone in the steps: on")
  for _, pr in ipairs(checkLayout(c.env.QuestBankMenu, "arrow menu, hearthstone")) do problems[#problems + 1] = pr end
  item.__scripts.OnClick(item)
  look()
  assert(set.arrowHearth == false and not has("hearth") and step() ~= "Hearth to Goldshire", "the hearthstone switched off in the menu: " .. says())
  item = menuItem("Hearthstone in the steps: off")
  item.__scripts.OnClick(item)
  look()
  assert(set.arrowHearth == true and step() == "Hearth to Goldshire", "and on again")
  c.o.bind = "Nowhere"
  tick(c, 5.1)
  lines = {}; F.__scripts.OnEnter(F)
  assert(not has("hearth") and table.concat(lines, "\n"):find("Hearthstone: QuestBank learns where it goes", 1, true), "bound somewhere QuestBank has no inn for")
  c.o.bind, c.o.bagSlots = "Goldshire", {}
  tick(c, 5.1)

  -- the client never says which flight paths you know: they all count, and the tooltip says so
  local saveTaxi = c.env.C_TaxiMap
  c.env.C_TaxiMap = nil
  db.known, db.readC = {}, {}
  TV.ver = TV.ver + 1
  standAt(c, 0, sw[3], sw[4])
  aimAt("Gadgetzan", 1, gz[3] + 30, gz[4])
  look()
  lines = {}; F.__scripts.OnEnter(F)
  assert(has("fly") and table.concat(lines, "\n"):find("Flight paths: not read yet, so all count", 1, true), "assumed: " .. table.concat(lines, " / "))
  sheet("Arrow: a long way, every flight path counted")
  c.env.C_TaxiMap = saveTaxi

  -- dead, in a dungeon, no way there
  c.ghost = true
  look()
  assert(F.dist:GetText() == "Resurrect first" and F.act.__atlas == "Navigation-Tombstone-Icon" and F.act.__alpha == 0.5 and not F.trail[1]:IsShown(), "dead")
  sheet("Arrow: dead")
  c.ghost = nil
  c.env.IsInInstance = function() return true, "party" end
  look()
  assert(F.dist:GetText() == "Leave the dungeon first" and F.act.__atlas == "dungeon" and F.act.__alpha == 0.5, "in a dungeon")
  sheet("Arrow: in a dungeon")
  c.env.IsInInstance = nil
  c.instWorld = { [2521] = true }
  c.QB.API.SetWaypoint(2521, 50, 50, "Zephras Isle")
  look()
  assert(F.name:GetText() == "Zephras Isle" and F.dist:GetText() == "No known way there" and F.act.__atlas == "Waypoint-MapPin-Untracked"
    and F.act.__desat and F.act.__alpha == 0.5 and not F.step:IsShown(), "a click on an island QuestBank can't lead to: " .. says())
  sheet("Arrow: no known way there")
  c.instWorld = nil
  -- there
  aimAt("Here", 0, sw[3] + 5, sw[4])
  A:Update()
  F.__scripts.OnUpdate(F, 0.016)
  assert(F.dist:GetText() == "You're there" and F.act.__atlas == "Waypoint-MapPin-Tracked" and F.act.__alpha == 1 and not F.act.__desat and F.ping:IsShown(),
    "there: the pin, a ping")
  sheet("Arrow: there")

  -- every town on the lines: each fits whole, or the step by the town's name alone, never cut; the longest names go
  -- through the whole layout check
  local I = TV.Icons("A")
  local towns, seen = {}, {}
  for _, fac in ipairs({ "A", "H" }) do for _, h in ipairs(D.HUB[fac]) do if not seen[h[1]] then seen[h[1]], towns[#towns + 1] = true, h[1] end end end
  for _, b in ipairs(D.BIND) do if not seen[b[1]] then seen[b[1]], towns[#towns + 1] = true, b[1] end end
  table.sort(towns, function(a, b) if #a ~= #b then return #a > #b end return a < b end)
  local cases = { { "at", "Fly to %s", "Pick %s", I.fly, I.fly }, { "underway", "Flying to %s", "Lands in 12:34", I.flying },
                  { "at", "Hearth to %s", "Ready in 59:59", I.hearth, I.hearth } }
  local fake, shortened = { trail = { I.fly, I.boat, I.foot } }, 0
  me = here()
  for i, town in ipairs(towns) do
    for _, k in ipairs(cases) do
      fake.state, fake.step, fake.short, fake.icon, fake.info, fake.act = k[1], k[2]:format(town), town, k[4], k[3]:format(town), k[5]
      fake.aim, fake.plan = not k[5] and me or nil, k
      A:Draw(town, fake, me)
      if i <= 4 then for _, pr in ipairs(checkLayout(F, "arrow, " .. fake.step)) do problems[#problems + 1] = pr end end
      if i == 1 and k == cases[2] then layouts[#layouts + 1] = dumpLayout(F, "Arrow: the longest name, " .. town) end
      assert(not F.step:GetText():find("...", 1, true) and not F.dist:GetText():find("...", 1, true) and not F.name:GetText():find("...", 1, true),
        "every town fits: " .. fake.step)
      if F.step:GetText() == town then shortened = shortened + 1 end
    end
  end
  print(string.format("arrow: %d towns on its lines, %d steps by the town's name alone", #towns, shortened))
  look()

  -- the nearest hand-in by the way there: by air beats a nearer walk; with the flight unknown, the walk
  c.taxiKnown = { [2] = true, [5] = true }
  db.known, db.readC = {}, {}
  learn()
  standAt(c, 0, sw[3], sw[4])
  local byAir = { name = "By air", c = 0, wx = lake[3] + 50, wy = lake[4], idx = 1 }
  local onFoot = { name = "On foot", c = 0, wx = sw[3] + 1800, wy = sw[4], idx = 2 }
  local _, airYards = A.Bearing(here(), byAir)
  local _, footYards = A.Bearing(here(), onFoot)
  assert(footYards < airYards, "on foot is nearer as the crow flies")
  assert(A.Nearest({ onFoot, byAir }, here(), "handin") == byAir, "by air is quicker: it is the nearest")
  c.taxiKnown[5] = nil
  fireTV(c, "TAXI_NODE_STATUS_CHANGED"); tick(c, 1.5)
  assert(A.Nearest({ onFoot, byAir }, here(), "handin") == onFoot, "Lakeshire not known: the walk is")
  set.arrowTravel = false
  assert(A.Nearest({ byAir, onFoot }, here(), "pickup") == onFoot, "straight: as the crow flies")
  set.arrowTravel = true

  -- TomTom, the arrow off: QuestBank's arrow shows the way there, and goes once only the last walk is left
  A:Set(false)
  c.addons = { TomTom = { loaded = true } }
  c.env.TomTom = { AddWaypoint = function() return 1 end, IsCrazyArrowEmpty = function() return true end, RemoveWaypoint = function() end }
  c.QB.API.SetWaypoint(1446, 50, 30, "Gadgetzan", nil, { c = 1, wx = gz[3] + 30, wy = gz[4] })
  look()
  assert(F:IsShown() and A.temp and A.temp.travel and step(), "with TomTom, the way to Gadgetzan: " .. says())
  standAt(c, 1, gz[3] + 200, gz[4])
  look()
  assert(not F:IsShown() and not A.temp, "the last walk left: TomTom's arrow alone")
  c.addons, c.env.TomTom = nil, nil
  set.arrowPin, set.arrowMode = nil, "route"

  -- straight at it (/qb arrow straight): another continent says so, the arrow dimmed
  A:Set(true)
  set.arrowTravel = false
  standAt(c, 0, sw[3], sw[4])
  aimAt("Gadgetzan", 1, gz[3] + 30, gz[4])
  look()
  assert(F.dist:GetText() == "On the other continent" and not F.step:IsShown() and F.arrow.__alpha == 0.3 and F.arrow.__rot == 0, "straight: " .. says())
  sheet("Arrow: straight, another continent")
  set.arrowTravel = true
  -- Travel.lua breaking: noted once, and the arrow points straight for the rest of the session
  aimAt("Lakeshire", 0, lake[3] + 50, lake[4])
  local guide = TV.Guide
  TV.Guide = function() error("a broken guide") end
  c.env.QUESTBANK_DEV = false
  look()
  c.env.QUESTBANK_DEV = true
  TV.Guide = guide
  look()
  assert(TV.broken and not F.step:IsShown() and F.dist:GetText():find("yards", 1, true) and c.env.QuestBankDB.errors[1].msg:find("a broken guide", 1, true),
    "the guide broke: straight at it, the error kept: " .. says())
  TV.broken = nil
  set.arrowPin, set.arrowMode = nil, "route"
  A:Set(false)

  -- the Horde, on a client without the tutorial arrow: the old quest arrow, no glow; at the tower, the zeppelin
  local h = grosh
  h.noAtlas = { npe_arrowup = true }
  h.QB.Arrow:Set(true)
  local HF = h.env.QuestBankArrow
  assert(HF.arrow.__tex == h.QB.Data.TEX.questArrow and not HF.arrow.__atlas and not HF.glow:IsShown(), "no atlas: the quest arrow")
  h.facing = 0
  local uc = hubOf(h, "Undercity")
  h.QB:Settings().arrowMode, h.QB:Settings().arrowPin = "pin", { name = "Undercity", c = uc[2], wx = uc[3], wy = uc[4] }
  HF.__scripts.OnUpdate(HF, 1)
  assert(HF.step:GetText() == "Zeppelin to Undercity" and HF.dist:GetText() == "Wait for the zeppelin" and HF.act.__tex == h.QB.Data.TEX.zeppelin,
    "at the tower: " .. HF.step:GetText() .. " / " .. HF.dist:GetText())
  for _, pr in ipairs(checkLayout(HF, "Arrow: the zeppelin (Horde)")) do problems[#problems + 1] = pr end
  layouts[#layouts + 1] = dumpLayout(HF, "Arrow: the zeppelin (Horde)")
  h.QB.Arrow:Set(false)
  h.QB:Settings().arrowPin, h.QB:Settings().arrowMode, h.noAtlas = nil, "route", nil
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
  -- the game's quest log showed 7,850 for it on builds 70205 to 70245 (uploads of 2026-10-06 to 08): confirmed
  assert(villainy.confirmed, "Blackfathom Villainy: the computed cut value, as the game's quest log showed it")
  lines = {}
  QB.UI.QuestTooltip(owner.env.GameTooltip, knowledge, QB:Status(knowledge), QB.Model.XpAt(knowledge, 20), 100, 20)
  assert(not table.concat(lines, "\n"):find("An estimate", 1, true), "a confirmed quest no longer says its number is computed")
  assert(table.concat(lines, "\n"):find("2,750 x 2.375, as the game paid after the cut", 1, true), "and its source line says the game paid it")
  assert(QB.Model.Full(villainy) == 7850, "3,300 x 2.375 = 7,837.5, rounded to 7,850 (was 12,400), got " .. tostring(QB.Model.Full(villainy)))
  -- a cut quest nobody has confirmed yet: the tooltip says the number is computed, and whose number wins
  local estId
  for id in pairs(D.Q) do
    local q = Qs.Get(id)
    if q and q.nerfed and not q.confirmed and (not estId or id < estId) then estId = id end
  end
  assert(estId, "a cut quest nobody has confirmed yet")
  local est = Qs.Get(estId)
  lines = {}
  QB.UI.QuestTooltip(owner.env.GameTooltip, est, QB:Status(est), QB.Model.XpAt(est, 20), 100, 20)
  local text = table.concat(lines, "\n")
  assert(text:find("Forever XP", 1, true) and text:find("An estimate", 1, true), "the tooltip shows the cut XP and says why: " .. text:gsub("\n", " / "))
  lines = {}
  QB.UI.QuestTooltip(owner.env.GameTooltip, villainy, QB:Status(villainy), QB.Model.XpAt(villainy, 20), 100, 20)
  text = table.concat(lines, "\n")
  assert(text:find("Forever XP 7,850", 1, true) and not text:find("An estimate", 1, true), "a confirmed cut quest shows the game's number: " .. text:gsub("\n", " / "))
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

-- 3.6.2, the 8 October build: quests that share one completion bit in the client rule each other out (since that
-- build each step of Call of Earth: Durotar, Mulgore, Zephras Isle and the Alliance's); a tooltip line says where a
-- number comes from or what Blizzard changed that nobody has read since; the Valley of Bones quests need level 35 as
-- Blizzard's notes say, not the lowest level anyone took them at; a battleground quest from players' notes stays out.
-- The quest ids below are the data as of that build: when new uploads change one, update it with the reason.
do
  local D, Qs = QB.Data, QB.Quest
  local function rules(a, b)
    for _, x in ipairs(D.EXCL[a] or {}) do if x == b then return true end end
    return false
  end
  for id, others in pairs(D.EXCL) do
    for _, o in ipairs(others) do assert(rules(o, id), "ruling out goes both ways: " .. id .. " and " .. o) end
  end
  for _, pair in ipairs({ { 1516, 1519 }, { 1516, 94373 }, { 1517, 1520 }, { 1517, 92467 }, { 1520, 94374 }, { 1518, 92468 }, { 1521, 94375 } }) do
    assert(rules(pair[1], pair[2]), "a Call of Earth step rules out its twins: " .. pair[1] .. " and " .. pair[2])
  end
  assert(Qs.Get(92467).cls == 64 and Qs.Get(92466).cls == 64, "the Zephras Isle steps are a Shaman's, as their twins are")
  for id, note in pairs(D.NOTE) do
    local q = Qs.Get(id)
    lines = {}
    QB.UI.QuestTooltip(owner.env.GameTooltip, q, QB:Status(q), QB.Model.XpAt(q, 20), 100, 20)
    local text = table.concat(lines, "\n")
    assert(text:find(note, 1, true), "the note is in the tooltip: " .. id)
    assert(not q.reqStated or not text:find("may unlock before", 1, true), "a required level Blizzard gave isn't called an upper bound: " .. id)
  end
  local vob = Qs.Get(92841)
  assert(vob and vob.req == 35 and vob.reqStated and vob.seenOnly and vob.note, "Valley of Bones needs 35 (Blizzard's notes, 8 October)")
  for _, id in ipairs({ 92841, 99411 }) do
    lines = {}
    QB.UI.QuestTooltip(owner.env.GameTooltip, Qs.Get(id), QB:Status(Qs.Get(id)), nil, nil, nil)
    print("tooltip, " .. id .. ":", (table.concat(lines, " | "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  end
  -- Kyle's Gone Missing!, written by hand until a player's QuestBank sees it: Horde, XP not known, its sources named
  local kyle = Qs.Get(99411)
  assert(kyle and (not kyle.note or (kyle.side == 2 and kyle.xpUnknown and kyle.note:find("ForeverChanges", 1, true))),
    "Kyle's Gone Missing! says where its level comes from, and that its XP isn't known")
  assert(not D.Q[98895] and not D.Q[98896], "Darkspear Islands Clash is a battleground quest: left out")
  assert(D.Q[92456] and D.Q[96986], "the City of Dalaran's quests are in since the dungeon opened for testing")
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


-- 5.3: the Quest Log grid by place: one run a zone, the nearest first; ready ones first in each; a follow-up beside the
-- quest it follows. 5.4: each slot shows its place's icon (no zone badge on a quest icon), the item it rewards small in
-- the corner, a done quest the green glow and check, a quest in progress no mark at all
do
  local U = QB.UI
  U:ShowTab(1); U:Refresh()
  local v1 = U.views[1]
  local cells = v1.cells
  assert(cells and #cells > 0 and #U.logGroups >= 2, "the log in groups: " .. #U.logGroups)
  local ended, last = {}, nil
  for i, cell in ipairs(cells) do
    if cell.group ~= last then
      assert(not ended[cell.group], "a place's quests sit together (group " .. cell.group .. " again at slot " .. i .. ")")
      if last then ended[last] = true end
      last = cell.group
    end
  end
  for g = 1, #U.logGroups - 1 do assert(U.logGroups[g].near <= U.logGroups[g + 1].near, "the nearest place first") end
  local follows, stamped, rewarded = 0, 0, 0
  local Dt = QB.Data.TEX
  for i, cell in ipairs(cells) do
    local nxt = cells[i + 1]
    if cell.kind == "entry" and nxt and nxt.kind == "entry" and nxt.group == cell.group and nxt.it.q and cell.it.q then
      assert(cell.it.e.complete or not nxt.it.e.complete, "ready to hand in first in a place")
    end
    if cell.kind == "follow" then
      follows = follows + 1
      local prev = cells[i - 1]
      assert(prev and prev.kind == "entry" and prev.it.q == cell.from and prev.group == cell.group, "a follow-up right after the quest it follows")
      assert(v1.slots[i].follow == cell.from and v1.slots[i].icon:GetAlpha() < 1, "faded, and its tooltip names the quest before it")
    end
    local b = v1.slots[i]
    assert(b.zone == nil and b.stamp == nil, "no zone badge and no stamp on a slot any more")
    local q = cell.kind == "entry" and cell.it.q or cell.q
    if q then
      local want = q.cat and (q.cat.zi or q.cat.icon) or q.icon
      assert(b.icon.__tex == want, "the slot's picture is its place's icon: " .. q.name)
      local R = QB.Quest.Rewards(q)
      local first = R and ((R.c or {})[1] or (R.r or {})[1] or (R.u or {})[1])
      assert(b.rw:IsShown() == (first ~= nil) and b.rwBack:IsShown() == (first ~= nil), "the reward mark shows when it rewards an item: " .. q.name)
      if first then
        rewarded = rewarded + 1
        assert(b.rwId == first and b.rw.__tex == 133328, "the reward mark is that item's own icon: " .. q.name)
        assert(b.rw.__w <= 16 and b.rw.__points[1].rel == b.rwBack, "small, on its dark square in the corner")
      end
    end
    if cell.kind == "entry" and cell.it.e.complete and cell.it.q and not cell.it.cut then
      assert(b.glow:IsShown() and b.glow.__atlas == "bags-glow-green" and b.glow.__blend == "ADD" and b.mark:IsShown() and b.mark.__tex == Dt.ready,
        "a done quest glows green (the bags' own glow) with the check in its corner")
      stamped = stamped + 1
    else
      assert(not b.glow:IsShown(), "only done quests glow")
    end
    if cell.kind == "entry" and cell.it.q and not cell.it.cut and not cell.it.e.complete then
      assert(not b.mark:IsShown(), "a quest in progress has no mark: " .. cell.it.q.name)
    end
    if cell.kind == "entry" and (cell.it.cut or not cell.it.q) then
      assert(b.mark:IsShown() and b.mark.__tex == Dt.notready, "a cut quest keeps its red X")
    end
    assert(b.band:IsShown(), "each filled slot sits on its place's band")
  end
  assert(rewarded >= 5, "the owner's log has quests that reward items, marked: " .. rewarded)
  -- follow-ups take only the slots left over after the log and your pick-ups
  local inLog, picks, withNext = 0, 0, 0
  for _, cell in ipairs(cells) do
    if cell.kind == "entry" then inLog = inLog + 1; if cell.it.q and U.FollowUp(cell.it.q) then withNext = withNext + 1 end end
    if cell.kind == "pick" then picks = picks + 1 end
  end
  local room = QB.LOG_SLOTS - inLog - picks
  print("quest log groups:", #U.logGroups, "follow-ups shown:", follows, "of", withNext, "room", room, "done:", stamped, "with a reward:", rewarded)
  assert(stamped >= 1 and follows == math.min(room, withNext), "done quests in the owner's log, and as many follow-ups as there is room for")
  -- the slots: 49 px apart, so the 3 px band round each leaves a 7 px gap between places; the band runs on under the gap
  -- to a slot of the same place
  GEN = GEN + 1
  local s1, s2, s9 = rectOf(v1.slots[1]), rectOf(v1.slots[2]), rectOf(v1.slots[9])
  assert(s2.l - s1.l == 49 and s1.t - s9.t == 49, "the grid steps 49 px each way")
  local downs = 0
  for i = 1, #cells - 1 do
    local b = v1.slots[i]
    if cells[i + 1].group == cells[i].group and i % 8 ~= 0 then assert(b.band.__w == 50, "the band joins the next slot of its place")
    else assert(b.band.__w == 42, "the band ends at the place's last slot on the row") end
    if cells[i + 8] and cells[i + 8].group == cells[i].group then assert(b.band.__h == 50, "and the slot under it, same place"); downs = downs + 1
    else assert(b.band.__h == 42, "a place's band stops above another place") end
  end
  assert(downs >= 1, "the owner's log has a place over two rows")
  -- a quest with no place shows its own icon; with no reward known, no mark
  local bare = { id = -1, name = "Bare", icon = 136797 }
  assert(U.LogPicture(bare) == 136797 and U.LogReward(bare) == nil, "no place: the quest's own icon, and no reward mark")
  -- the game hasn't sent the reward's icon yet: a bag in the corner
  local saveIcon = owner.env.C_Item.GetItemIconByID
  owner.env.C_Item.GetItemIconByID = function() return nil end
  local withReward
  for _, cell in ipairs(cells) do local q = cell.kind == "entry" and cell.it.q or cell.q; if q and U.LogReward(q) then withReward = q break end end
  assert(select(2, U.LogReward(withReward)) == QB.Data.TEX.bag, "a bag until the item's icon comes")
  owner.env.C_Item.GetItemIconByID = saveIcon
  -- with room (twelve quests in the log): the follow-ups show, each right after its quest
  local few = {}
  for _, cell in ipairs(cells) do if cell.kind == "entry" and #few < 12 then few[#few + 1] = cell.it end end
  local fewCells = U.LogCells(few, {})
  local f2, n2 = 0, 0
  for i, cell in ipairs(fewCells) do
    if cell.kind == "entry" and cell.it.q and U.FollowUp(cell.it.q) then n2 = n2 + 1 end
    if cell.kind == "follow" then f2 = f2 + 1; assert(fewCells[i - 1].it.q == cell.from, "right after its quest") end
  end
  print("quest log, twelve quests: follow-ups shown:", f2, "of", n2)
  assert(f2 == n2 and f2 >= 1, "with free slots every follow-up shows beside its quest")
  U:Refresh()
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
  -- 5.3: Available folds: zones and dungeons are sections, a place opens on its banner, a quest on a click; a row
  -- shows what its quest gives; a report goes into the saved file for the next upload
  do
    local v2 = U.views[2]
    U.allOpen, U.cardOpen, U.detailOpen, U.secClosed = false, {}, {}, {}
    U:ShowTab(2); U:Refresh()
    local secs = {}
    for _, h in ipairs(v2.sections.items) do if h:IsShown() then secs[#secs + 1] = h end end
    assert(#secs >= 1 and secs[1].label:GetText():find("Zones", 1, true) and secs[1].sum:GetText():find("places", 1, true), "a Zones section with its sums")
    local open1 = 0
    for _, c in ipairs(v2.cards.items) do if c:IsShown() and c.head.key then for _, r in ipairs(c.rows.items) do if r:IsShown() then open1 = open1 + 1 end end end end
    assert(open1 == 0, "places start folded: no quest rows")
    local first
    for _, c in ipairs(v2.cards.items) do if c:IsShown() and c.head.key and not first then first = c end end
    first.head.__scripts.OnClick(first.head)
    local rows = {}
    for _, r in ipairs(first.rows.items) do if r:IsShown() then rows[#rows + 1] = r end end
    -- 5.4: the open and closed marks are the game's header art: the font draws a box for a text triangle
    assert(#rows > 0 and first.caret.__atlas == "campaign_headericon_open" and first.caret:IsShown(), "the banner opens its place: " .. #rows .. " rows")
    secs[1].__scripts.OnClick(secs[1])
    local shownC = 0
    for _, c in ipairs(v2.cards.items) do if c:IsShown() and c.head.key and not c.head.key:find("^d") then shownC = shownC + 1 end end
    assert(shownC == 0 and secs[1].caret.__atlas == "campaign_headericon_closed" and secs[1].label:GetText() == "Zones", "the Zones section folds away")
    secs[1].__scripts.OnClick(secs[1])
    -- a quest opens; its report is kept
    for _, c in ipairs(v2.cards.items) do if c:IsShown() and c.head.key == first.head.key then first = c end end
    local r1
    for _, r in ipairs(first.rows.items) do if r:IsShown() and r.q and not r1 then r1 = r end end
    r1.__scripts.OnClick(r1, "LeftButton")
    local det
    for _, d in ipairs(first.details.items) do if d:IsShown() then det = d end end
    assert(det and det.q == r1.q and det.rwHead:GetText() ~= "", "the quest opens under its row")
    local env1 = owner.env
    env1.QuestBankDB.reports = nil
    U.Report(r1.q, U.REPORTS[1])
    assert(env1.QuestBankDB.reports and env1.QuestBankDB.reports[1].id == r1.q.id and env1.QuestBankDB.reports[1].r == U.REPORTS[1], "the report is kept for the upload")
    local withIcons = 0
    for _, r in ipairs(first.rows.items) do if r:IsShown() and r.rw and r.rw[1]:IsShown() then withIcons = withIcons + 1 end end
    assert(withIcons > 0, "rows with reward icons: " .. withIcons)
    U.allOpen, U.cardOpen, U.detailOpen = true, {}, {}
    U:Refresh()
  end
  local v2 = U.views[2]
  assert(v2.intro:GetText():find("^Level %d+ to %d+$"), "the intro names the level window, nothing more: " .. tostring(v2.intro:GetText()))
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
  -- 5.4: a place with no zone of its own (the class quests) has no empty part between two dots
  for _, c in ipairs(NU.views[2].cards.items) do
    if c:IsShown() then assert(not c.where:GetText():find("\194\183%s*\194\183"), "no empty part in a card's line: " .. c.where:GetText()) end
  end
  assert(NU.views[2].intro:GetText():find("^Level %d+ to %d+$"), "the intro is the level window: " .. tostring(NU.views[2].intro:GetText()))
  -- a chain opens under its row
  U.candMemo = nil
  U:ShowTab(2); QB.Model.Finish(); U:Refresh()
  local v2 = U.views[2]
  local chainRow
  for _, c in ipairs(v2.cards.items) do if c:IsShown() then for _, r in ipairs(c.rows.items) do
    if r:IsShown() and r.q and r.chain:IsShown() and not chainRow then chainRow = r end
  end end end
  assert(chainRow, "a chain quest shows the toggle")
  assert(chainRow.chain.icon.__atlas == "campaign_headericon_closed", "folded: the game's closed header mark")
  -- a step under its chain is set 12 px in (no arrow glyph: the game's font has none)
  local function isStep(r) local p = r.name.__points[1]; return p and p.x == 58 and r.icon.__points[1].x == 34 end
  local id, card = chainRow.q.id, chainRow:GetParent()
  chainRow.chain.__scripts.OnClick(chainRow.chain)
  assert(U.chainOpen and U.chainOpen[id], "the click opens it")
  local subs, headRow = 0, nil
  for _, r in ipairs(card.rows.items) do
    if r:IsShown() and r.q and r.q.id == id then headRow = r end
    if r:IsShown() and isStep(r) then subs = subs + 1; assert(not r.chain:IsShown(), "a step under a chain carries no toggle of its own") end
  end
  assert(subs >= 1 and headRow and not isStep(headRow) and headRow.chain.icon.__atlas == "campaign_headericon_open", "its steps show under the row, the mark open (" .. subs .. " steps)")
  -- the chain open, its card scrolled into view: checked, and drawn for review
  do
    local p = card.__points and card.__points[1]
    if p and p.y then v2.scroll.bar:SetValue(-p.y) end
    for _, pr in ipairs(checkLayout(U.frame, "Available, a chain open")) do problems[#problems + 1] = pr end
    GEN = GEN + 1
    layouts[#layouts + 1] = dumpLayout(U.frame, "Available, a chain open")
    v2.scroll.bar:SetValue(0)
  end
  lines = {}; headRow.chain.__scripts.OnEnter(headRow.chain)
  assert(lines[1] == "The chain" and lines[2]:find("fold it away", 1, true), "the toggle's tooltip")
  headRow.chain.__scripts.OnClick(headRow.chain)
  subs = 0
  for _, r in ipairs(card.rows.items) do if r:IsShown() and isStep(r) then subs = subs + 1 end end
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

-- 5.4: several quests at once, on Available and on Now. Ctrl-click a row, or tick its box (the game's check box, on the
-- quest's icon while the mouse is on the row), and it is selected; the bar under the page counts the selection and
-- picks them all up, takes the ones on the list off it, or clears it. Each place's "+ all" puts every quest it shows
-- that you could pick up on the list
do
  local U = QB.UI
  local function rowsOf(v)
    local out = {}
    for _, c in ipairs(v.cards.items) do if c:IsShown() then for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q then out[#out + 1] = r end end end end
    return out
  end
  local function rowOf(v, id) for _, r in ipairs(rowsOf(v)) do if r.q.id == id then return r end end end
  local function ctrlClick(r) owner.ctrl = true; r.__scripts.OnClick(r, "LeftButton"); owner.ctrl = false end
  for _, tab in ipairs({ 2, 6 }) do
    local v, name = U.views[tab], tab == 2 and "Available" or "Now"
    U.allOpen, U.cardOpen, U.detailOpen, U.chainOpen, U.secClosed = true, {}, {}, {}, {}
    U:ShowTab(tab); QB.Model.Finish(); U:Refresh()
    local free, held = {}, nil
    for _, r in ipairs(rowsOf(v)) do
      if r.selectable and not QB:IsAdded(r.q.id) then free[#free + 1] = r.q.id end
      if QB.state.log[r.q.id] then held = held or r end
    end
    assert(#free >= 3, name .. ": quests to pick from: " .. #free)
    local a, b, c = free[1], free[2], free[3]
    -- a quest in your log is not picked this way (Shift-click cuts it; this is the pick-up list)
    assert(held and not held.selectable, name .. ": a quest in your log has no box")
    ctrlClick(held)
    assert(next(v.sel) == nil and not v.selBar:IsShown(), name .. ": Ctrl-click on it selects nothing")
    U.detailOpen = {}; U:Refresh()
    -- the box: on the row's icon while the mouse is on the row, gone when it leaves
    local ra = rowOf(v, a)
    assert(not ra.sel:IsShown(), name .. ": no box until the mouse is on the row")
    ra.__scripts.OnEnter(ra)
    assert(ra.sel:IsShown() and not ra.sel.check:IsShown() and ra.sel.box.__atlas == "checkbox-minimal" and ra.sel.__points[1].x == ra.icon.__points[1].x,
      name .. ": the mouse on the row: the game's check box over the quest's icon")
    if tab == 2 then ra.__hover = true; layouts[#layouts + 1] = dumpLayout(UI.frame, "Available, the mouse on a row: its box"); ra.__hover = nil end
    lines = {}; ra.__scripts.OnEnter(ra)
    assert(table.concat(lines, "\n"):find("Ctrl-click: select it", 1, true), name .. ": the row's tooltip says so")
    ra.__scripts.OnLeave(ra)
    assert(not ra.sel:IsShown(), name .. ": and gone when it leaves")
    -- Ctrl-click selects (and doesn't open the quest); the box selects too
    ctrlClick(ra)
    assert(v.sel[a] and not U.detailOpen[a], name .. ": Ctrl-click selects the quest and leaves it shut")
    assert(v.selBar:IsShown() and v.selBar.count:GetText() == "1 selected", name .. ": the bar counts it: " .. v.selBar.count:GetText())
    ra = rowOf(v, a)
    assert(ra.sel:IsShown() and ra.sel.check:IsShown() and ra.sel.check.__atlas == "checkmark-minimal" and ra.selBg:IsShown(), name .. ": ticked, the row washed gold")
    ra.__scripts.OnLeave(ra)
    assert(ra.sel:IsShown(), name .. ": a ticked box stays when the mouse leaves")
    local rb = rowOf(v, b)
    rb.__scripts.OnEnter(rb); rb.sel.__scripts.OnClick(rb.sel)
    assert(v.sel[b] and v.selBar.count:GetText() == "2 selected", name .. ": the box selects too")
    lines = {}; rb = rowOf(v, b); rb.sel.__scripts.OnEnter(rb.sel)
    assert(lines[1] == "Selected" and lines[2]:find("Ctrl-click", 1, true), name .. ": the box's tooltip")
    -- the page with the bar: the list ends above it, everything inside the page
    for _, p in ipairs(checkLayout(UI.frame, name .. ", two selected")) do problems[#problems + 1] = p end
    GEN = GEN + 1
    local sr, br = rectOf(v.scroll), rectOf(v.selBar)
    assert(sr.b >= br.t + 3, name .. ": the list ends above the bar")
    if tab == 2 then layouts[#layouts + 1] = dumpLayout(UI.frame, "Available, two quests selected") end
    -- Pick up all
    assert(v.selBar.pick:IsEnabled() and not v.selBar.remove:IsEnabled(), name .. ": neither is on the list: Pick up all, no Remove all")
    v.selBar.pick.__scripts.OnClick(v.selBar.pick)
    assert(QB:IsAdded(a) and QB:IsAdded(b) and not QB:IsAdded(c), name .. ": Pick up all puts both on the pick-up list")
    assert(next(v.sel) == nil and not v.selBar:IsShown(), name .. ": and the selection and its bar are gone")
    GEN = GEN + 1
    sr = rectOf(v.scroll)
    assert(sr.b == rectOf(v).b + 6, name .. ": the list runs to the bottom again")
    -- Remove all: only the selected ones on the list come off
    ctrlClick(rowOf(v, a)); ctrlClick(rowOf(v, c))
    assert(v.selBar.count:GetText() == "2 selected" and v.selBar.pick:IsEnabled() and v.selBar.remove:IsEnabled(), name .. ": one on the list, one not: both buttons")
    v.selBar.remove.__scripts.OnClick(v.selBar.remove)
    assert(not QB:IsAdded(a) and QB:IsAdded(b) and not QB:IsAdded(c) and next(v.sel) == nil, name .. ": Remove all takes off the selected one on the list, nothing else")
    -- Clear: nothing changes on the list
    ctrlClick(rowOf(v, c)); ctrlClick(rowOf(v, b))
    v.selBar.clear.__scripts.OnClick(v.selBar.clear)
    assert(next(v.sel) == nil and not v.selBar:IsShown() and QB:IsAdded(b) and not QB:IsAdded(c), name .. ": Clear unticks them, the list as it was")
    -- Ctrl-click twice unticks; a quest that can't be picked any more drops out of the selection
    ctrlClick(rowOf(v, c)); ctrlClick(rowOf(v, c))
    assert(next(v.sel) == nil, name .. ": a second Ctrl-click unticks it")
    v.sel[c] = true; v.sel[1999999] = true
    owner.done[c] = true
    U:Refresh()
    owner.done[c] = nil
    assert(next(v.sel) == nil, name .. ": a quest done since (or unknown) drops out of the selection")
    QB:SetAdded(b, false)
    assert(not QB:IsAdded(b) and not QB:SetAdded(b, false), "SetAdded says when nothing changed")
    -- the other page keeps its own selection
    U:Refresh()
    print(string.format("%s: picked %s and %s, removed one, cleared", name, QB.Quest.Get(a).name, QB.Quest.Get(b).name))
  end
  -- + all, on a place's banner: every quest it shows that you could pick up, open or folded
  for _, tab in ipairs({ 2, 6 }) do
    local v, name = U.views[tab], tab == 2 and "Available" or "Now"
    U.allOpen, U.cardOpen, U.detailOpen, U.chainOpen, U.expanded = tab == 6, {}, {}, {}, nil
    U:ShowTab(tab); U:Refresh()
    local card
    for _, cd in ipairs(v.cards.items) do if cd:IsShown() and cd.addAll:IsShown() and not card then card = cd end end
    assert(card, name .. ": a place with quests to pick up shows + all")
    local key, ids = card.head.key, card.addAll.ids
    assert(card.addAll.label:GetText() == "+ all" and #ids >= 1, name .. ": + all, for " .. #ids)
    lines = {}; card.addAll.__scripts.OnEnter(card.addAll)
    assert(lines[1] == string.format("Pick up all %d here", #ids), name .. ": its tooltip counts them: " .. tostring(lines[1]))
    -- folded, it takes what opening shows: the same quests the open card lists with a !
    U.cardOpen[key] = true; U:Refresh()
    for _, cd in ipairs(v.cards.items) do if cd:IsShown() and cd.head.key == key then card = cd end end
    local shownBang = {}
    for _, r in ipairs(card.rows.items) do if r:IsShown() and r.q and r.pick.pickable and not QB:IsAdded(r.q.id) then shownBang[#shownBang + 1] = r.q.id end end
    assert(#shownBang == #ids, name .. ": + all takes what the open place shows to pick up: " .. #shownBang .. " vs " .. #ids)
    for i, id in ipairs(ids) do assert(shownBang[i] == id, name .. ": the same quests, in the same order") end
    card.addAll.__scripts.OnClick(card.addAll)
    for _, id in ipairs(ids) do assert(QB:IsAdded(id), name .. ": + all put it on the list: " .. id) end
    for _, cd in ipairs(v.cards.items) do if cd:IsShown() and cd.head.key == key then card = cd end end
    for _, id in ipairs(card.addAll.ids or {}) do for _, old in ipairs(ids) do assert(id ~= old, name .. ": what is on the list is not offered again") end end
    for _, p in ipairs(checkLayout(UI.frame, name .. ", after + all")) do problems[#problems + 1] = p end
    for _, id in ipairs(ids) do QB:SetAdded(id, false) end
    print(string.format("%s: + all put %d quests of %s on the list", name, #ids, card.title:GetText()))
  end
  -- every place open, quests and chains open, scrolled: still all inside the page
  for _, tab in ipairs({ 2, 6 }) do
    local v, name = U.views[tab], tab == 2 and "Available" or "Now"
    U:ShowTab(tab)
    U.allOpen, U.cardOpen, U.secClosed, U.expanded, U.detailOpen, U.chainOpen = true, {}, {}, {}, {}, {}
    for _, cat in ipairs(QB.Data.CAT) do U.expanded[cat.key] = true end
    U:Refresh()
    local nd, nc = 0, 0
    for _, cd in ipairs(v.cards.items) do
      if cd:IsShown() then
        for _, r in ipairs(cd.rows.items) do if r:IsShown() and r.q and r.detailable and nd < 8 then U.detailOpen[r.q.id] = true; nd = nd + 1; break end end
        for _, r in ipairs(cd.rows.items) do if r:IsShown() and r.q and r.chain:IsShown() and nc < 4 and not U.detailOpen[r.q.id] then U.chainOpen[r.q.id] = true; nc = nc + 1; break end end
      end
    end
    -- and a selection, so the bar is up
    for _, r in ipairs(rowsOf(v)) do if r.selectable and next(v.sel) == nil then v.sel[r.q.id] = true end end
    U:Refresh()
    assert(nd > 0 and nc > 0 and v.selBar:IsShown(), name .. ": details and chains open, a selection")
    for _, p in ipairs(checkLayout(UI.frame, name .. ", every place open, " .. nd .. " quests and " .. nc .. " chains open")) do problems[#problems + 1] = p end
    local lo, hi = v.scroll.bar:GetMinMaxValues()
    for _, f in ipairs({ 0.33, 0.66, 1 }) do
      v.scroll.bar:SetValue(math.floor(hi * f))
      for _, p in ipairs(checkLayout(UI.frame, string.format("%s, every place open, scrolled %d%%", name, f * 100))) do problems[#problems + 1] = p end
    end
    v.scroll.bar:SetValue(0)
    v.sel = {}
  end
  U.allOpen, U.cardOpen, U.secClosed, U.expanded, U.detailOpen, U.chainOpen = true, {}, {}, nil, {}, {}
  U:ShowTab(1); U:Refresh()
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
  -- the slot choice shows on the title line, at the rows' right edge: inside the page (5.3 put it past the panel's edge)
  assert(v1.slotBtn:IsShown(), "Best gear offers the slot choice")
  for _, p in ipairs(checkLayout(U.frame, "Quest Log, Best gear")) do problems[#problems + 1] = p end
  layouts[#layouts + 1] = dumpLayout(U.frame, "Quest Log, Best gear")
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
  -- (the sweep at login read the six items worn and carried first, 300104 to 300109 going for them)
  assert(countOf(g.items) == G.MAX_ITEMS and not g.items[300110] and g.items[300111] and g.items[7413] and g.items[2070],
    "a full table drops its oldest for a new one")
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
  assert(not g.items[280016], "a hidden line: the tooltip is not kept half-read")
  tick(c, 12)
  assert(not g.items[280016], "read again a few times, still not kept")
  c.tipLines[280016] = nil -- the client shows it whole
  hover(c, 280016); tick(c, 1)
  assert(g.items[280016] and #g.items[280016].x == 6 and g.items[280016].x[1] == "Binds when picked up", "shown whole, it is kept")
  assert(countOf(g.items) == G.MAX_ITEMS, "still at most 1000")
  -- Settings: the box, and what it stops
  Q2.UI:Open(5); Q2.UI:Refresh()
  local v5 = Q2.UI.views[5]
  assert(v5.noteGame and v5.noteGame:GetChecked() and v5.noteGame:IsEnabled() and v5.noteGame.label:GetText() == "Note items, spells and loot, for foreverrank.com",
    "the Settings box, ticked by default")
  assert(v5.discText:GetText():find(", 1000 items, 0 drop sources.", 1, true) and not v5.discText:GetText():find("ForeverProbe", 1, true), "the count: " .. v5.discText:GetText())
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
  G.OnEvent("BAG_UPDATE_DELAYED"); G.OnEvent("PLAYER_REGEN_ENABLED"); G.Sweep()
  tick(c, 10)
  assert(c.env.QuestBankDB.game == nil and #c.loadRequests == 0 and not G.frame.__scripts.OnEvent,
    "nothing written: QuestBankDB.game isn't touched, nothing asked of the server, no event registered")
  -- the drop-source notes (Loot.lua) stay off here too: the frame got no handler, and a loot window with a creature
  -- behind it notes nothing, so disc.loot stays out of the file
  local Lo = Q2.Loot
  assert(Lo and Lo.frame and not Lo.frame.__scripts.OnEvent and not Lo.On(), "Classic Era: the loot notes register nothing")
  c.loot = { { id = 2589, src = { { "Creature-0-4455-0-12-197-0000A1B2C3", 1 } } } }
  Lo.OnEvent("LOOT_OPENED", false, false)
  assert(c.env.QuestBankDB.disc.loot == nil and c.env.QuestBankDB.disc.lootN == nil and (c.env.QuestBankDB.diag or {}).loot == nil, "and a loot window notes nothing")
  Lo.OnEvent("ENCOUNTER_LOOT_RECEIVED", 3303, 273037, "", 1, "Sigrun", "WARRIOR")
  tick(c, 10)
  assert(c.env.QuestBankDB.game == nil and #c.loadRequests == 0, "a drop announced to the group: nothing read here either")
  local d = c.env.QuestBankDB.disc
  assert(d and d.iface == 11507 and d.build == "63696", "the quest notes say which client wrote them")
  assert(owner.env.QuestBankDB.disc.iface == 16001, "and on Forever: " .. tostring(owner.env.QuestBankDB.disc.iface))
  assert(c.env.QuestBankDB.diag.addons.iface == 11507 and c.env.QuestBankDB.diag.addons.probe == nil, "the client's stamps, and nothing about ForeverProbe")
  -- a client without the bags' glow atlas: a done Quest Log slot glows with the action buttons' border, tinted green
  c.noAtlas = { ["bags-glow-green"] = true }
  Q2.UI:Open(5); Q2.UI:Refresh()
  c.noAtlas = nil
  local glow = Q2.UI.views[1].slots[1].glow
  assert(glow.__tex == "Interface\\Buttons\\UI-ActionButton-Border" and glow.__w > 60 and glow.__vertex and glow.__vertex[2] == 1
    and glow.__blend == "ADD", "no atlas: the action buttons' border, green, round the slot")
  local v5 = Q2.UI.views[5]
  assert(not v5.noteGame:IsEnabled() and not v5.noteGame:GetChecked() and v5.noteGame.label:GetText():find("Forever client only", 1, true)
    and not v5.discText:GetText():find("items", 1, true) and not v5.discText:GetText():find("drop", 1, true), "the Settings box is greyed out here, and says why")
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
  assert(not c.chat[#c.chat]:find("items", 1, true) and not c.chat[#c.chat]:find("drop", 1, true), "/qb discoveries: quests and NPCs only")
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
-- 5.3: the Route page guides a questing character: where to do the unfinished quests, nearest first, then hand in
do
  local N, U = newbie.QB, newbie.QB.UI
  local D = N.Data
  local e1 = N.state.logOrder[1]
  local saveSpot = D.SPOT[e1.id]
  D.SPOT[e1.id] = "k,1,1429,520,500,10,c"
  e1.complete = false
  local legs = U.ObjectiveLegs(5)
  assert(#legs >= 1 and legs[1].quests[1].id == e1.id and legs[1].mins >= 0 and legs[1].yards >= 0, "the nearest unfinished quest's place comes first")
  U:ShowTab(3); U:Refresh()
  local v3n = U.views[3]
  local first
  for _, l in ipairs(v3n.legs.items) do if l:IsShown() and not first then first = l end end
  assert(first and first.divider:IsShown() and first.divider:GetText() == "Do now" and first.name:GetText() == legs[1].name, "the page opens with Do now")
  assert(first.pin.stop and first.pin.stop.m == 1429, "with a waypoint on the place")
  D.SPOT[e1.id] = saveSpot
end

-- 3.6.2: who drops what (Loot.lua): a dwarf hunter looting in Elwynn and in the City of Dalaran on the Forever
-- client. Each creature or chest looted is noted by id with the item ids in its window, the map or the dungeon with
-- its difficulty, and the boss fight it ended; never a name, never a player; under the same Settings box as the
-- item notes, and gone with them when it is unticked
----------------------------------------------------------------------------
local torvald = newClient({
  name = "Torvald", level = 29, cap = 60, faction = "Alliance", className = "Hunter", class = "HUNTER", classID = 3, race = "Dwarf",
  log = {}, done = {}, group = false, guild = false, world = { 0, -9450, 60 }, map = 1429, bind = "Goldshire", riding = false, xp = 300,
  bagSlots = { { 2589, 3 } }, gear = { [16] = 2504 }, book = { { spellID = 75, itemType = 1 } },
})
login(torvald)
do
  local c, Q2 = torvald, torvald.QB
  local Lo, G = Q2.Loot, Q2.Game
  local DB = c.env.QuestBankDB
  local f = Lo.frame
  local function open(isFromItem) f.__scripts.OnEvent(f, "LOOT_OPENED", false, isFromItem or false) end
  local function ev(event, ...) f.__scripts.OnEvent(f, event, ...) end
  local function loot() return DB.disc.loot or {} end
  local function diag() return DB.diag and DB.diag.loot or {} end
  local function src(guid) return { { guid, 1 } } end
  local errs0 = #(DB.errors or {})
  assert(Lo.On() and G.On() and f.__scripts.OnEvent, "the Forever client with the box ticked: the loot notes are on")
  assert(Lo.LOOT_SOURCES == 400 and Lo.LOOT_ITEMS == 40 and Lo.AGAIN == 120 and Lo.KILL_WINDOW == 120, "the caps")
  local K = Q2.Discover.Key
  assert(K("Creature-0-4455-0-12-197-0000A1B2C3") == "c197" and K("GameObject-0-4455-0-12-2843-0000A1B2C3") == "o2843"
    and K("Vehicle-0-4455-0-12-1234-0000A1B2C3") == "c1234" and K("Player-1234-0000ABCD") == nil
    and K("Pet-0-4455-0-12-197-0000A1B2C3") == nil and K(SECRET.str()) == nil and K(nil) == nil,
    "a GUID's key: creatures and vehicles c, game objects o, nothing for players, pets and hidden values")

  -- in the world: a kobold's corpse with linen, some copper and a grey
  c.loot = { { id = 2589, src = src("Creature-0-4455-0-12-197-0000A1B2C3") }, { id = 0, kind = 2 }, { id = 2590, q = 0, src = src("Creature-0-4455-0-12-197-0000A1B2C3") } }
  open()
  local r = loot().c197
  assert(r and r.m == 1429 and r.n == 1 and r.b == 70170 and r.i[2589] == 1 and r.i[2590] == nil and countOf(r.i) == 1
    and r.im == nil and r.d == nil and r.e == nil and r.ex == nil, "a corpse in the world: the map, looted once, the build, the item; no coin, no grey")
  assert(diag().w == 1 and diag().s == 1 and not diag().h and not diag().f, "diag: one window, one with a source")
  assert(DB.disc.lootN == 1 and DB.disc.lootAt.c197 == 1, "the touch counter")
  -- the same corpse opened again (the window was closed with an item left): items added, not looted again; another
  -- kobold: looted again; a grey quest item is kept
  c.loot = { { id = 2589, src = src("Creature-0-4455-0-12-197-0000A1B2C3") }, { id = 2592, src = src("Creature-0-4455-0-12-197-0000A1B2C3") } }
  open()
  r = loot().c197
  assert(r.n == 1 and r.i[2589] == 1 and r.i[2592] == 1, "the same corpse again: a new item, not another time looted")
  c.loot = { { id = 2589, src = src("Creature-0-4455-0-12-197-0000A1B2C4") }, { id = 2591, q = 0, quest = true, src = src("Creature-0-4455-0-12-197-0000A1B2C4") } }
  open()
  r = loot().c197
  assert(r.n == 2 and r.i[2589] == 2 and r.i[2591] == 1, "another kobold: looted twice, the linen seen in two windows, a grey quest item kept")
  c.loot = { { id = 2593, q = 0, questID = 7, src = src("Creature-0-4455-0-12-197-0000A1B2C4") } }
  open()
  assert(loot().c197.i[2593] == 1 and loot().c197.n == 2, "a grey with a quest id is a quest item too")
  tick(c, 121)
  c.loot = { { id = 2589, src = src("Creature-0-4455-0-12-197-0000A1B2C4") } }
  open()
  assert(loot().c197.n == 3 and loot().c197.i[2589] == 3, "the same GUID past two minutes: looted again, as far as the notes can tell")

  -- the City of Dalaran: the Shade of the Archmage, whose kill event names its creature
  c.env.IsInInstance = function() return true, "party" end
  c.instance = { "City of Dalaran", 1, 2959 }
  ev("ENCOUNTER_START", 3303, "Shade of the Archmage", 1, 5)
  ev("ENCOUNTER_END", 3303, "Shade of the Archmage", 1, 5, 1, { { creatureID = 246020, creatureName = "Shade of the Archmage", remainingHealthPercent = 0 } })
  c.loot = { { id = 273031, src = src("Creature-0-4455-2959-12-246020-0000A1B2C9") }, { id = 273032, src = src("Creature-0-4455-2959-12-246020-0000A1B2C9") } }
  open()
  r = loot().c246020
  assert(r and r.im == 2959 and r.d == 1 and r.e == 3303 and r.ex == true and r.n == 1 and r.b == 70170 and r.i[273031] == 1 and r.i[273032] == 1 and r.m == nil,
    "a boss in Dalaran: the instance map and difficulty, the fight by its creature list, the items")
  assert(diag().eu == 1 and not diag().ee, "diag: the kill named its creatures")
  -- trash looted after it is not the boss: the list named 246020 only
  c.loot = { { id = 273033, src = src("Creature-0-4455-2959-12-246021-0000A1B2CA") } }
  open()
  assert(loot().c246021 and loot().c246021.e == nil and loot().c246021.im == 2959, "a trash creature after the kill: no fight")
  -- the list's creature id under another field name, as a string: still the fight's creature; the field names are noted
  ev("ENCOUNTER_START", 3298, "Arcane Anomaly", 1, 5)
  ev("ENCOUNTER_END", 3298, "Arcane Anomaly", 1, 5, 1, { { npcID = "245999", remainingHealthPercent = 0 } })
  c.loot = { { id = 273034, src = src("Creature-0-4455-2959-12-245999-0000A1B2D0") } }
  open()
  assert(loot().c245999 and loot().c245999.e == 3298 and loot().c245999.ex == true, "a creature id given as npcID text still links the fight by the game's list")
  assert(diag().uk == "npcID,remainingHealthPercent", "diag: the list's field names are noted, nothing else: " .. tostring(diag().uk))
  -- a kill that names no creatures: the first corpse looted within two minutes is taken for it, as a guess
  ev("ENCOUNTER_END", 3311, "Atrexis the Grave Knight", 1, 5, 1, nil)
  assert(diag().ee == 1, "diag: a kill without the list")
  tick(c, 30)
  c.loot = { { id = 273040, src = src("Creature-0-4455-2959-12-246030-0000A1B2CB") } }
  open()
  tick(c, 30)
  c.loot = { { id = 273041, src = src("Creature-0-4455-2959-12-246031-0000A1B2CC") } }
  open()
  assert(loot().c246030.e == 3311 and loot().c246030.ex == nil, "the first corpse after the kill: the fight, as a guess (no ex)")
  assert(loot().c246031.e == nil, "the second: nothing")
  tick(c, 121)
  ev("BOSS_KILL", 3312, "Mana Wraith")
  tick(c, 125)
  c.loot = { { id = 273042, src = src("Creature-0-4455-2959-12-246032-0000A1B2CD") } }
  open()
  assert(loot().c246032.e == nil, "a corpse more than two minutes after a kill: nothing")
  -- the game's own link stands over a guess
  ev("BOSS_KILL", 3310, "Lyn the Ignored")
  c.loot = { { id = 273031, src = src("Creature-0-4455-2959-12-246020-0000A1B2CE") } }
  open()
  assert(loot().c246020.e == 3303 and loot().c246020.ex == true and loot().c246020.n == 2 and loot().c246020.i[273031] == 2,
    "a creature the game once named for a fight keeps that fight")
  -- a wipe links nothing; a loading screen forgets the kill; so does a new fight starting
  ev("PLAYER_ENTERING_WORLD", false, true)
  ev("ENCOUNTER_END", 3298, "Arcane Anomaly", 1, 5, 0, nil)
  c.loot = { { id = 273043, src = src("Creature-0-4455-2959-12-246033-0000A1B2CF") } }
  open()
  assert(loot().c246033.e == nil, "a wipe: nothing")
  ev("ENCOUNTER_END", 3299, "Fel Ancient", 1, 5, 1, nil)
  ev("PLAYER_ENTERING_WORLD", false, true)
  c.loot = { { id = 273044, src = src("Creature-0-4455-2959-12-246034-0000A1B2D0") } }
  open()
  assert(loot().c246034.e == nil, "after a loading screen: the kill is forgotten")
  ev("ENCOUNTER_END", 3300, "Mana Devourer", 1, 5, 1, nil)
  ev("ENCOUNTER_START", 3301, "Mana Elemental", 1, 5)
  c.loot = { { id = 273045, src = src("Creature-0-4455-2959-12-246035-0000A1B2D1") } }
  open()
  assert(loot().c246035.e == nil, "a new fight started: the last kill's guess is off")

  -- hidden values: nothing noted, no error
  local n0 = countOf(loot())
  local h0 = diag().h or 0
  c.loot = { { id = 273050, src = src(SECRET.str()) } }
  open()
  assert(countOf(loot()) == n0 and diag().h == h0 + 1, "a hidden source: nothing noted, counted as hidden")
  ev("ENCOUNTER_END", SECRET.num(), "Unstable Sentinel", 1, 5, 1, nil)
  c.loot = { { id = 273051, src = src("Creature-0-4455-2959-12-246040-0000A1B2D2") } }
  open()
  assert(loot().c246040 and loot().c246040.e == nil, "a hidden encounter id: no kill to link")
  local numItems = c.env.GetNumLootItems
  c.env.GetNumLootItems = function() return SECRET.num() end
  c.loot = { { id = 273052, src = src("Creature-0-4455-2959-12-246041-0000A1B2D3") } }
  open()
  c.env.GetNumLootItems = numItems
  assert(not loot().c246041, "a hidden slot count: nothing")
  -- a hidden place: the items count, the place is unknown; what was noted before stands only where it still can (a
  -- map from outdoors is wrong for a corpse looted inside, a dungeon is wrong for one looted outdoors)
  c.env.IsInInstance = function() return false, "none" end
  c.loot = { { id = 273053, src = src("Creature-0-4455-0-12-246042-0000A1B2D4") } }
  open()
  assert(loot().c246042.m == 1429, "a creature first met outdoors: the map")
  c.env.IsInInstance = function() return true, "party" end
  c.instance[3] = SECRET.num()
  c.loot = { { id = 273053, src = src("Creature-0-4455-2959-12-246042-0000A1B2D8") } }
  open()
  c.instance[3] = 2959
  r = loot().c246042
  assert(r and r.i[273053] == 2 and r.n == 2 and r.im == nil and r.d == nil and r.m == nil, "a hidden instance id: the items count, the place is unknown, the map from outdoors goes")
  c.instance[2] = SECRET.num()
  c.loot = { { id = 273053, src = src("Creature-0-4455-2959-12-246021-0000A1B2D9") } }
  open()
  c.instance[2] = 1
  r = loot().c246021
  assert(r.i[273053] == 1 and r.im == 2959 and r.d == 1, "a hidden difficulty: the dungeon noted before stands, it is the same side")
  c.env.IsInInstance = function() return false, "none" end
  local best = c.env.C_Map.GetBestMapForUnit
  c.env.C_Map.GetBestMapForUnit = function() return SECRET.num() end
  c.loot = { { id = 273053, src = src("Creature-0-4455-0-12-246021-0000A1B2DA") } }
  open()
  assert(loot().c246021.im == nil and loot().c246021.d == nil and loot().c246021.m == nil, "outdoors with the map hidden: the dungeon noted before goes")
  c.env.C_Map.GetBestMapForUnit = best
  c.env.IsInInstance = function() return SECRET.num(), SECRET.str() end
  c.loot = { { id = 273053, src = src("Creature-0-4455-0-12-246020-0000A1B2DB") } }
  open()
  assert(loot().c246020.im == 2959 and loot().c246020.d == 1 and loot().c246020.m == nil, "not even inside or out known: the place noted before stands")
  c.env.IsInInstance = function() return true, "party" end
  ev("ENCOUNTER_END", 3302, "Unstable Sentinel", 1, 5, 1, SECRET.str())
  c.loot = { { id = 273054, src = src("Creature-0-4455-2959-12-246043-0000A1B2D5") } }
  open()
  assert(loot().c246043.e == 3302 and loot().c246043.ex == nil, "a hidden creature list is no list: the first corpse is a guess")
  ev("ENCOUNTER_END", 3302, "Unstable Sentinel", 1, 5, 1, { SECRET.str(), { creatureID = SECRET.num(), creatureName = "x" } })
  c.loot = { { id = 273055, src = src("Creature-0-4455-2959-12-246044-0000A1B2D6") } }
  open()
  assert(loot().c246044.e == 3302 and loot().c246044.ex == nil, "a list whose every creature is hidden: the same")
  -- a hidden source beside a plain one: the plain one is noted, and the window counts as hidden too
  c.loot = { { id = 273056, src = { { SECRET.str(), 1 }, { "Creature-0-4455-2959-12-246045-0000A1B2D7", 1 } } } }
  open()
  assert(loot().c246045 and loot().c246045.i[273056] == 1 and diag().h == h0 + 2, "a window half hidden: what shows is noted")

  -- kinds: a chest is an o key, a vehicle a c key; a player's corpse is nobody (skipped, not hidden); a lockbox,
  -- fishing, coins only, no source: skipped whole
  c.env.IsInInstance = function() return false, "none" end
  c.loot = { { id = 2589, src = src("GameObject-0-4455-0-12-2843-0000A1B2E0") }, { id = 2592, src = src("Vehicle-0-4455-0-12-1234-0000A1B2E1") } }
  open()
  assert(loot().o2843 and loot().o2843.i[2589] == 1 and loot().o2843.m == 1429 and loot().o2843.im == nil and loot().c1234 and loot().c1234.i[2592] == 1,
    "a chest: o; a vehicle: c; outdoors again: the map")
  n0 = countOf(loot())
  local f0, hh = diag().f or 0, diag().h
  c.loot = { { id = 2589, src = src("Player-1234-0000ABCD") } }
  open()
  assert(countOf(loot()) == n0 and diag().f == f0 + 1 and diag().h == hh, "a player's corpse: nothing, and not a hidden source")
  c.loot = { { id = 2589, src = src("Creature-0-4455-0-12-197-0000A1B2E2") } }
  open(true)
  assert(countOf(loot()) == n0 and loot().c197.n == 3 and diag().f == f0 + 2, "a window from an item (a lockbox): nothing")
  c.fishing = true
  open()
  c.fishing = nil
  assert(loot().c197.n == 3 and diag().f == f0 + 3, "fishing: nothing")
  c.loot = { { id = 0, kind = 2 } }
  open()
  assert(diag().f == f0 + 4, "coins only: nothing lootable")
  c.loot = { { id = 2589 } }
  c.lootSrc = {}
  open()
  c.lootSrc = nil
  assert(diag().f == f0 + 5 and countOf(loot()) == n0, "no source at all: nothing")
  local sourceInfo = c.env.GetLootSourceInfo
  c.env.GetLootSourceInfo = nil
  c.loot = { { id = 2589, src = src("Creature-0-4455-0-12-197-0000A1B2E3") } }
  open()
  c.env.GetLootSourceInfo = sourceInfo
  assert(countOf(loot()) == n0 and loot().c197.n == 3 and diag().h == hh + 1, "a client without GetLootSourceInfo: nothing, counted as hidden")

  -- the caps: 400 sources, the ones touched longest ago going first; 40 items a source, the least-seen going, and a
  -- new one left out while every kept item was seen more than once
  c.loot = { { id = 273060 } }
  for k = 1, Lo.LOOT_SOURCES + 5 do
    c.lootSrc = src("Creature-0-4455-0-12-" .. (500000 + k) .. "-0000B" .. string.format("%07X", k))
    open()
  end
  c.lootSrc = nil
  assert(countOf(loot()) == Lo.LOOT_SOURCES and countOf(DB.disc.lootAt) == Lo.LOOT_SOURCES, "at most 400 sources, and as many touch marks")
  assert(not loot().c197 and not loot().o2843 and not loot().c246020 and not loot().c500005 and loot().c500006 and loot().c500405,
    "the ones touched longest ago went first")
  local function many(a, b, guid)
    local t = {}
    for id = a, b do t[#t + 1] = { id = id } end
    c.loot, c.lootSrc = t, src(guid)
    open()
    c.lootSrc = nil
  end
  many(273001, 273040, "Creature-0-4455-0-12-600000-0000C000001")
  many(273001, 273039, "Creature-0-4455-0-12-600000-0000C000002")
  r = loot().c600000
  assert(r and countOf(r.i) == 40 and r.i[273001] == 2 and r.i[273040] == 1 and r.n == 2, "40 items on one source")
  many(273041, 273041, "Creature-0-4455-0-12-600000-0000C000003")
  assert(countOf(r.i) == 40 and r.i[273040] == nil and r.i[273041] == 1, "a 41st: the one seen fewest times goes")
  many(273041, 273041, "Creature-0-4455-0-12-600000-0000C000004")
  many(273042, 273042, "Creature-0-4455-0-12-600000-0000C000005")
  assert(countOf(r.i) == 40 and r.i[273042] == nil and r.i[273041] == 2 and r.n == 5, "every kept item seen twice: a new one is left out")
  assert(countOf(loot()) == Lo.LOOT_SOURCES and not loot().c500006, "and the source cap held")

  -- no names anywhere: every value a number, a boolean or a table; every key a source ("c123", "o123"), an item id,
  -- or one of the record's own fields
  local FIELDS = { im = true, m = true, d = true, e = true, ex = true, n = true, b = true, i = true }
  local function clean(v, path)
    if type(v) == "table" then
      for k, x in pairs(v) do
        assert(type(k) == "number" or (type(k) == "string" and (k:match("^[co]%d+$") or FIELDS[k])), "an odd key at " .. path .. ": " .. tostring(k))
        clean(x, path .. "." .. tostring(k))
      end
    else
      assert(type(v) == "number" or type(v) == "boolean", "a " .. type(v) .. " at " .. path .. ": " .. tostring(v))
    end
  end
  clean(DB.disc.loot, "loot"); clean(DB.disc.lootAt, "lootAt")
  names(c, DB.disc.loot, { "Shade of the Archmage", "Dalaran", "Torvald" })
  assert(type(DB.disc.lootN) == "number", "the counter is a number")

  -- the switch: unticked, the notes go with the item notes; a window notes nothing; ticked, the next window does
  G.SetOn(false)
  assert(DB.disc.loot == nil and DB.disc.lootAt == nil and DB.disc.lootN == nil and DB.game == nil, "unticked: the loot notes go")
  c.loot = { { id = 2589, src = src("Creature-0-4455-0-12-197-0000A1B2F0") } }
  open()
  assert(DB.disc.loot == nil and not Lo.On(), "and nothing is noted while it is off")
  G.SetOn(true)
  open()
  assert(DB.disc.loot and DB.disc.loot.c197 and DB.disc.loot.c197.n == 1 and DB.disc.lootN == 1 and Lo.Count() == 1, "ticked again: the next window notes")
  c.env.SlashCmdList.QUESTBANK("discoveries")
  local said = c.chat[#c.chat]
  assert(said:find(", 1 drop source.", 1, true), "/qb discoveries counts them: " .. said)
  c.loot = { { id = 2592, src = src("Creature-0-4455-0-12-198-0000A1B2F1") }, { id = 2593, src = src("Creature-0-4455-0-12-198-0000A1B2F1") } }
  open()
  local ns, ni = Lo.Count()
  assert(ns == 2 and ni == 3, "Count: sources, and the items under them")
  -- the Settings page: the count, the tooltip, the layout
  Q2.UI:Open(5); Q2.UI:Refresh()
  local v5 = Q2.UI.views[5]
  assert(v5.discText:GetText():find(", 2 drop sources.", 1, true), "the Settings page counts drop sources: " .. v5.discText:GetText())
  lines = {}
  v5.noteGame.__scripts.OnEnter(v5.noteGame)
  assert(table.concat(lines, " "):find("chests", 1, true) and table.concat(lines, " "):find("by id", 1, true), "the tooltip says what is noted: " .. table.concat(lines, " | "))
  v5.noteGame.__scripts.OnLeave(v5.noteGame)
  for _, pr in ipairs(checkLayout(Q2.UI.frame, "settings with the loot notes")) do problems[#problems + 1] = pr end
  local sf = v5.scroll
  local _, hi = sf.bar:GetMinMaxValues()
  sf.bar:SetValue(hi); Q2.UI:Refresh()
  for _, pr in ipairs(checkLayout(Q2.UI.frame, "settings with the loot notes, scrolled")) do problems[#problems + 1] = pr end
  sf.bar:SetValue(0)
  Q2.UI.frame:Hide()
  c.env.SlashCmdList.QUESTBANK("discoveries")
  said = c.chat[#c.chat]
  assert(said:find(", 2 drop sources.", 1, true), "/qb discoveries, plural: " .. said)
  assert(#(DB.errors or {}) == errs0, "no error through all of it")
  local dg = diag()
  print(string.format("loot notes: %d sources, %d items; windows %d, with a source %d, hidden %d, skipped %d; kills with a list %d, without %d",
    ns, ni, dg.w, dg.s, dg.h, dg.f, dg.eu, dg.ee))
end

----------------------------------------------------------------------------
-- 3.6.2: tooltips without a hover (Game.lua with Loot.lua). The owner's City of Dalaran run left two boss drops in
-- the bags with no tooltip in the upload: only hovered items were read. Now every item a loot window shows, every
-- drop the game announces to the group, and every item worn or carried is read, two every half second, never in a
-- fight, by the same reader with the same guards and caps
----------------------------------------------------------------------------
do
  local c, Q2 = torvald, torvald.QB
  local G, Lo = Q2.Game, Q2.Loot
  local DB = c.env.QuestBankDB
  local lf = Lo.frame
  local function src(guid) return { { guid, 1 } } end
  local function open(isFromItem) lf.__scripts.OnEvent(lf, "LOOT_OPENED", true, isFromItem or false) end -- auto-loot: the window is never seen
  local function has(ids) local n = 0; for _, id in ipairs(ids) do if DB.game.items[id] then n = n + 1 end end; return n end
  local reads, asked = { n = 0 }, {}
  local realTip, realLoad = c.env.C_TooltipInfo.GetItemByID, c.env.C_Item.RequestLoadItemDataByID
  c.env.C_TooltipInfo.GetItemByID = function(id) reads[id] = (reads[id] or 0) + 1; reads.n = reads.n + 1; return realTip(id) end
  c.env.C_Item.RequestLoadItemDataByID = function(id) asked[id] = (asked[id] or 0) + 1; return realLoad(id) end
  tick(c, 60) -- the loot tests' windows left ids in the queue: read out
  local g = DB.game
  local errs0 = #(DB.errors or {})
  assert(G.PACE == 0.5 and G.BATCH == 2 and G.LOADS == 2 and G.TRIES == 3, "the pace: two tooltips every half second")
  c.env.IsInInstance = function() return true, "party" end
  c.instance = { "City of Dalaran", 1, 2959 }
  -- what is worn and carried now, read before the rest (a sweep by hand; the game's comes at login and when the bags change)
  assert(not g.items[2504], "the worn axe was never hovered")
  G.Sweep(); tick(c, 1)
  assert(g.items[2504] and g.items[2504].n == "Item 2504", "the sweep reads what is worn")

  -- the owner's two drops, auto-looted and never hovered: the loot recorder queues them, the reader reads them
  local boss = "Creature-0-4455-2959-12-246050-0000A1B300"
  g.items[273035], reads[273035] = nil, nil -- (the loot tests' window of forty read it; forgotten, so the drop is new again)
  c.loot = { { id = 273035, src = src(boss) }, { id = 273048, src = src(boss) } }
  open()
  assert(not g.items[273035] and not g.items[273048] and not reads[273035], "the window only queues: nothing is read inside the event")
  tick(c, 1)
  local it = g.items[273035]
  assert(it and g.items[273048] and it.n == "Item 273035" and it.el == "INVTYPE_CHEST" and it.b == "1.60.1.70170" and #it.x == 6,
    "both drops have a tooltip without a hover")
  assert(DB.disc.loot.c246050 and DB.disc.loot.c246050.i[273035] == 1 and DB.disc.loot.c246050.i[273048] == 1, "and the source is noted as before")
  -- a lockbox's contents: no source to note, the tooltips still read
  local ns0 = countOf(DB.disc.loot)
  local f0 = DB.diag.loot.f
  c.loot = { { id = 273071, src = src("Creature-0-4455-2959-12-246051-0000A1B301") } }
  open(true)
  assert(not g.items[273071], "a lockbox's window: only queued")
  tick(c, 1)
  assert(g.items[273071] and countOf(DB.disc.loot) == ns0 and not DB.disc.loot.c246051 and DB.diag.loot.f == f0 + 1,
    "a window from an item: its items are read, no source noted")
  -- a boss drop another player looted and this one won: the game announces it to the group
  lf.__scripts.OnEvent(lf, "ENCOUNTER_LOOT_RECEIVED", 3303, 273070, "|cffa335ee|Hitem:273070::::::::29:::::::|h[Item 273070]|h|r", 1, "Torvald", "HUNTER")
  assert(not g.items[273070], "announced: only queued")
  tick(c, 1)
  assert(g.items[273070], "a drop the kill event announces is read, whoever looted the corpse")
  lf.__scripts.OnEvent(lf, "ENCOUNTER_LOOT_RECEIVED", 3303, SECRET.num(), SECRET.str(), 1, SECRET.str(), "HUNTER")
  tick(c, 1)

  -- the bags: ten new items, read two every half second, across ticks, so a bag full of new items never reads in
  -- one frame; the sweep waits five seconds after the bags change
  local bagged = {}
  c.o.bagSlots = { { 2589, 3 } }
  for i = 1, 10 do bagged[i] = 273100 + i; c.o.bagSlots[#c.o.bagSlots + 1] = { 273100 + i, 1 } end
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 4)
  assert(has(bagged) == 0, "the bags are looked through five seconds after they change, not at once")
  tick(c, 1)
  assert(has(bagged) == 0, "the sweep only queues")
  tick(c, 0.5)
  assert(has(bagged) == 2, "half a second on: two read (" .. has(bagged) .. ")")
  tick(c, 0.5)
  assert(has(bagged) == 4, "another half second: four (" .. has(bagged) .. ")")
  tick(c, 1.5)
  assert(has(bagged) == 10, "and all ten after three seconds (" .. has(bagged) .. ")")
  for _, id in ipairs(bagged) do assert(reads[id] == 1, "each read once") end
  -- the bags change again: every tooltip is fresh, nothing is read
  local n0 = reads.n
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 6)
  assert(reads.n == n0, "a sweep with every tooltip fresh reads nothing")
  -- duplicates collapse: the same id hovered three times, looted and in the bags is read once
  c.o.bagSlots[#c.o.bagSlots + 1] = { 273120, 1 }
  hover(c, 273120); hover(c, 273120); hover(c, 273120)
  c.loot = { { id = 273120, src = src("Creature-0-4455-2959-12-246052-0000A1B302") } }
  open()
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 10)
  assert(g.items[273120] and reads[273120] == 1, "hovered, looted and bagged: read once (" .. tostring(reads[273120]) .. ")")
  -- six hours on, the sweep reads it again
  g.items[273120].at = g.items[273120].at - 7 * 3600
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 6)
  assert(reads[273120] == 2, "read again after six hours")

  -- the cap holds: a full table, five new items in the bags and the worn axe unread at this build; the oldest six go
  local full = {}
  for i = 1, G.MAX_ITEMS do full[400000 + i] = { b = "1.60.1.69000", at = 1000 + i, n = "Old", c = 4, x = {} } end
  g.items = full
  c.o.bagSlots = {}
  for i = 1, 5 do c.o.bagSlots[i] = { 273130 + i, 1 } end
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 8)
  assert(countOf(g.items) == G.MAX_ITEMS and g.items[273131] and g.items[273135] and g.items[2504] and not g.items[400001] and not g.items[400006]
    and g.items[400007], "at most 1000: the oldest six went for the six new (" .. countOf(g.items) .. ")")

  -- an item the client hasn't loaded (server-sent): asked of the server, nothing kept until it answers; a failed
  -- answer is left for a later sweep, and the asking stops after two in a session
  c.o.bagSlots = { { 273201, 1 }, { 273202, 1 } }
  c.unloaded[273201], c.unloaded[273202] = true, true
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 7)
  assert(not g.items[273201] and not g.items[273202] and asked[273201] == 1 and asked[273202] == 1, "not loaded: asked for, nothing kept")
  fire(c, "ITEM_DATA_LOAD_RESULT", 273201, false)
  tick(c, 2)
  assert(not g.items[273201] and asked[273201] == 1, "the server said no: nothing kept, not asked again at once")
  c.unloaded[273202] = nil
  fire(c, "ITEM_DATA_LOAD_RESULT", 273202, true)
  assert(not g.items[273202], "the answer only queues")
  tick(c, 1)
  assert(g.items[273202] and g.items[273202].n == "Item 273202" and #g.items[273202].x == 6, "loaded: read on the server's answer")
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 7)
  assert(asked[273201] == 2 and not g.items[273201], "the next sweep asks again")
  fire(c, "ITEM_DATA_LOAD_RESULT", 273201, false)
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 7)
  assert(asked[273201] == 2 and not g.items[273201], "twice a session, then left for the next")
  fire(c, "ITEM_DATA_LOAD_RESULT", SECRET.num(), true); fire(c, "ITEM_DATA_LOAD_RESULT", 273201, SECRET.bool())
  tick(c, 1)
  -- a hidden name: the same, asked twice at most, never kept
  c.o.bagSlots = { { 273203, 1 } }
  c.itemName[273203] = SECRET.str()
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 7)
  fire(c, "ITEM_DATA_LOAD_RESULT", 273203, true); tick(c, 1)
  fire(c, "ITEM_DATA_LOAD_RESULT", 273203, true); tick(c, 1)
  fire(c, "ITEM_DATA_LOAD_RESULT", 273203, true); tick(c, 1)
  assert(not g.items[273203] and asked[273203] == 2, "a hidden name: asked twice, never kept (" .. tostring(asked[273203]) .. ")")

  -- a tooltip the server hasn't filled in ("Retrieving item information"): read again three times, three seconds
  -- apart, then left; nothing half-read is kept. The next sweep reads it whole
  c.o.bagSlots = { { 273204, 1 } }
  c.tipLines[273204] = { { leftText = "Item 273204" }, { leftText = "Retrieving item information" } }
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 6)
  assert(reads[273204] == 1 and not g.items[273204], "half-read: not kept")
  tick(c, 20)
  assert(reads[273204] == 4 and not g.items[273204], "read again three times, then left (" .. tostring(reads[273204]) .. ")")
  hover(c, 273204); tick(c, 10)
  assert(reads[273204] == 5 and not g.items[273204], "a hover reads once more, still not kept")
  c.tipLines[273204] = nil -- the server's text arrives
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 6)
  assert(g.items[273204] and g.items[273204].x[1] == "Binds when picked up" and reads[273204] == 6, "whole at last: kept")

  -- the body missing or hidden while the client has the name: GetItemByID returning nothing (MayReturnNothing in
  -- the client's documentation), an empty list, the list hidden, a line hidden, a line's left or right text hidden.
  -- None is kept half-read or lineless (a record with lines missing would stand for the item's stats in the
  -- Database): read again three times, then left; a later sweep reads it once more; whole at last, it is kept
  local gone = {}
  c.env.C_TooltipInfo.GetItemByID = function(id)
    reads[id] = (reads[id] or 0) + 1; reads.n = reads.n + 1
    if gone[id] then return nil end
    return realTip(id)
  end
  local bodies = { 273205, 273206, 273207, 273208, 273209, 273210 }
  gone[273205] = true
  c.tipLines[273206] = {}
  c.tipLines[273207] = SECRET.str()
  c.tipLines[273208] = { { leftText = "Item 273208" }, SECRET.str(), { leftText = "+5 Stamina" } }
  c.tipLines[273209] = { { leftText = "Item 273209" }, { leftText = SECRET.str() }, { leftText = "+5 Stamina" } }
  c.tipLines[273210] = { { leftText = "Item 273210" }, { leftText = "Chest", rightText = SECRET.str() }, { leftText = "+5 Stamina" } }
  c.o.bagSlots = {}
  for i, id in ipairs(bodies) do c.o.bagSlots[i] = { id, 1 } end
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 7)
  for _, id in ipairs(bodies) do assert(reads[id] == 1 and not g.items[id], "body missing or hidden: read, not kept (" .. id .. ")") end
  tick(c, 20)
  for _, id in ipairs(bodies) do assert(reads[id] == 4 and not g.items[id], "read again three times, then left (" .. id .. ": " .. tostring(reads[id]) .. ")") end
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 7)
  for _, id in ipairs(bodies) do assert(reads[id] == 5 and not g.items[id], "a later sweep reads it once more, still not kept (" .. id .. ")") end
  gone[273205] = nil
  for _, id in ipairs(bodies) do c.tipLines[id] = nil end -- the client shows them whole
  fire(c, "BAG_UPDATE_DELAYED"); tick(c, 7)
  for _, id in ipairs(bodies) do
    assert(g.items[id] and #g.items[id].x == 6 and g.items[id].x[1] == "Binds when picked up" and reads[id] == 6, "whole at last: kept (" .. id .. ")")
  end
  assert(#(DB.errors or {}) == errs0, "no error from a missing or hidden body")

  -- a fight: nothing is read, nothing looked through, nothing asked of the server, until it ends
  c.o.bagSlots = { { 273301, 1 }, { 273302, 1 } }
  c.combat = true
  n0 = reads.n
  local a0 = countOf(asked)
  c.loot = { { id = 273303, src = src("Creature-0-4455-2959-12-246060-0000A1B310") } }
  open()
  hover(c, 273304)
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 30)
  assert(reads.n == n0 and not g.items[273301] and not g.items[273303] and not g.items[273304] and countOf(asked) == a0, "in a fight: nothing read, nothing asked")
  assert(DB.disc.loot.c246060 and DB.disc.loot.c246060.i[273303] == 1, "(the loot source is noted as before)")
  c.combat = false
  fire(c, "PLAYER_REGEN_ENABLED")
  tick(c, 0.5)
  assert(g.items[273303] and g.items[273304], "the fight over: the queue goes on at once")
  tick(c, 10)
  assert(g.items[273301] and g.items[273302], "and the bags are looked through")
  -- the game holding addons back as in combat without InCombatLockdown (an encounter): the same wait
  c.env.Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1 }
  local held = true
  c.env.C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return kind == 1 and held end }
  n0 = reads.n
  hover(c, 273305)
  tick(c, 30)
  assert(reads.n == n0 and not g.items[273305], "held back in an encounter: nothing read")
  held = false
  fire(c, "ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
  tick(c, 0.5)
  assert(g.items[273305], "the encounter over: read")
  c.env.C_RestrictedActions, c.env.Enum.AddOnRestrictionType = nil, nil

  assert(#(DB.errors or {}) == errs0, "no error through all of it")
  names(c, g, { "Torvald", "Dalaran" })
  c.env.C_TooltipInfo.GetItemByID, c.env.C_Item.RequestLoadItemDataByID = realTip, realLoad
  local nAsked = 0
  for _ in pairs(asked) do nAsked = nAsked + 1 end
  print(string.format("tooltips without a hover: %d reads, %d records kept, %d items asked of the server", reads.n, countOf(g.items), nAsked))
end

----------------------------------------------------------------------------
-- 3.7.0: the event probe (Observe.lua). On the Forever client QuestBank counts, per unit event, whether the game
-- handed it readable values, secret values or nothing, in QuestBankDB.diag.ev, so the observer can be designed on
-- what this client really gives addons. Kinds only: never a name, never a player
----------------------------------------------------------------------------
do
  local c, Q2 = torvald, torvald.QB
  local Ob = Q2.Observe
  local DB = c.env.QuestBankDB
  assert(Ob and Ob.frame and Ob.On() and Ob.frame.__scripts.OnEvent, "the Forever client with the box ticked: the probe is on")
  assert(Ob.MAX_KEYS == 60, "the cap")
  local function ev() return DB.diag and DB.diag.ev or {} end
  Ob.Note("TEST_EVENT", { a = 1, b = "x" })
  local r = ev().TEST_EVENT
  assert(r and r.n == 1 and r.ok == 1 and r.sec == 0 and r.nl == 0 and r.s.a == "number" and r.s.b == "string", "a plain read: counted ok, kinds kept, values not")
  Ob.Note("TEST_EVENT", { a = SECRET.num(), b = "x" })
  r = ev().TEST_EVENT
  assert(r.n == 2 and r.ok == 1 and r.sec == 1 and r.s.a == "number", "a secret read: counted, the first sample stays")
  Ob.Note("TEST_EVENT2", { a = Ob.NIL, b = SECRET.str() })
  r = ev().TEST_EVENT2
  assert(r.n == 1 and r.ok == 0 and r.sec == 1 and r.nl == 1 and r.s.a == "nil" and r.s.b == "secret", "nil and secret both noted in the sample")
  -- the unit cast events: a target casting with everything readable, then a nameplate whose GUID is hidden
  local f = Ob.frame
  local function fire(event, ...) f.__scripts.OnEvent(f, event, ...) end
  local unitLevel, guidOf = c.env.UnitLevel, c.env.UnitGUID
  c.env.UnitLevel = function(u) if u == "target" or u:find("^nameplate") then return 31 end return unitLevel(u) end
  c.env.UnitClassification = function() return "elite" end
  c.env.UnitHealth = function() return 1200 end
  c.env.UnitHealthMax = function() return 4000 end
  c.env.UnitCastingInfo = function() return "Arcane Bolt", "Arcane Bolt", "", 1000, 2500, false, "cast-1", false, 1234 end
  c.env.UnitChannelInfo = function() return nil end
  c.env.UnitGUID = function(u) if u == "target" then return "Creature-0-4455-0-12-245999-0000A1B2C3" end if u:find("^nameplate") then return SECRET.str() end return guidOf(u) end
  fire("UNIT_SPELLCAST_START", "target", "cast-1", 1234)
  r = ev().UNIT_SPELLCAST_START
  assert(r and r.n == 1 and r.ok == 1 and r.s.guid == "string" and r.s.cast == "string" and r.s.castSpell == "number" and r.s.castId == "string"
    and r.s.spellId == "number" and r.s.unit == "string" and r.s.level == "number" and r.s.cls == "string" and r.s.hp == "number" and r.s.chan == "none",
    "a readable cast on the target: the unit's guid, level, class, health, the cast and the event's ids")
  assert(r.s.name == "string", "the creature's name is read (its kind kept, never the name)")
  fire("UNIT_SPELLCAST_START", "nameplate3", "cast-2", 1234)
  r = ev().UNIT_SPELLCAST_START
  assert(r.n == 2 and r.sec == 1 and r.nl == 0, "a nameplate with a hidden GUID counts as secret (not casting is not missing)")
  fire("UNIT_SPELLCAST_START", "player", "cast-3", 1)
  fire("UNIT_SPELLCAST_START", "party1", "cast-3", 1)
  fire("UNIT_SPELLCAST_START", SECRET.str(), "cast-3", 1)
  assert(ev().UNIT_SPELLCAST_START.n == 2, "our own casts, and a hidden unit, are not the probe's business")
  fire("UNIT_HEALTH", "target")
  assert(ev().UNIT_HEALTH.n == 1 and ev().UNIT_HEALTH.s.hp == "number", "health on the target")
  c.env.UnitCastingInfo = function() return nil end
  fire("UNIT_SPELLCAST_STOP", "target", "cast-1", 1234)
  r = ev().UNIT_SPELLCAST_STOP
  assert(r.ok == 1 and r.s.cast == "none" and r.s.castSpell == nil, "a cast that ended: no cast going on, nothing missing")
  fire("PLAYER_TARGET_CHANGED")
  assert(ev().PLAYER_TARGET_CHANGED.n == 1 and ev().PLAYER_TARGET_CHANGED.s.guid == "string", "a target change reads the target")
  -- auras on the player and party: the first harmful one, by C_UnitAuras
  local auraByIndex = c.env.C_UnitAuras.GetAuraDataByIndex
  c.env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
    if i == 1 and filter == "HARMFUL" then return { name = "Mana Burn", spellId = 1300001, sourceUnit = "target", isHarmful = true, dispelName = "Magic" } end
  end
  fire("UNIT_AURA", "player", { isFullUpdate = true })
  r = ev().UNIT_AURA
  assert(r and r.n == 1 and r.ok == 1 and r.s.n == "number" and r.s.name == "string" and r.s.spellId == "number" and r.s.source == "string" and r.s.kind == "string", "a harmful aura on the player: its source unit and school")
  fire("UNIT_AURA", "target")
  assert(ev().UNIT_AURA.n == 1, "auras on creatures are not read (only what lands on us)")
  c.env.C_UnitAuras.GetAuraDataByIndex = auraByIndex
  -- nameplates and rare vignettes
  fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
  assert(ev().NAME_PLATE_UNIT_ADDED.n == 1 and ev().NAME_PLATE_UNIT_ADDED.sec == 1 and ev().NAME_PLATE_UNIT_ADDED.s.level == "number", "a nameplate added reads the unit (its GUID hidden here)")
  c.env.C_VignetteInfo = { GetVignettes = function() return { "v-1" } end,
    GetVignetteInfo = function(id) return { vignetteGUID = id, objectGUID = "Creature-0-4455-0-12-7777-0000A1B2C3", name = "Grizzled Rare", atlasName = "VignetteKill", onWorldMap = true, onMinimap = true } end }
  fire("VIGNETTE_MINIMAP_UPDATED", "v-1", true)
  r = ev().VIGNETTE_MINIMAP_UPDATED
  assert(r and r.n == 1 and r.ok == 1 and r.s.objectGUID == "string" and r.s.atlas == "string", "a vignette: its object GUID and atlas")
  c.env.C_VignetteInfo = nil
  fire("VIGNETTE_MINIMAP_UPDATED", "v-2", true)
  assert(ev().VIGNETTE_MINIMAP_UPDATED.n == 2 and ev().VIGNETTE_MINIMAP_UPDATED.nl == 1, "a client without C_VignetteInfo: counted as missing")
  -- a merchant: the npc's GUID, the first item's id, price and link
  c.npcGUID = "Creature-0-4455-0-12-1234-0000A1B2C3"
  c.merchant = { 2589, 2592 }
  c.env.GetMerchantItemInfo = function(i) return "Linen Cloth", "", 13, 1, 0, true, nil end
  c.env.GetMerchantItemLink = function(i) return "|cffffffff|Hitem:2589::::::::29:::::|h[Linen Cloth]|h|r" end
  fire("MERCHANT_SHOW")
  r = ev().MERCHANT_SHOW
  assert(r and r.n == 1 and r.ok == 1 and r.s.guid == "string" and r.s.items == "number" and r.s.id == "number" and r.s.price == "number" and r.s.link == "string", "a merchant: who, how many, the first item's id, price and link")
  c.merchant = {}
  fire("MERCHANT_SHOW")
  assert(ev().MERCHANT_SHOW.n == 2 and ev().MERCHANT_SHOW.ok == 2, "an empty vendor: who and none, still ok")
  -- a chest: loot from a game object
  c.loot = { { id = 2589, src = { { "GameObject-0-4455-0-12-2843-0000A1B2C3", 1 } } } }
  fire("LOOT_OPENED", false, false)
  r = ev().LOOT_OPENED
  assert(r and r.n == 1 and r.ok == 1 and r.s.src == "string" and r.s.slots == "number", "a loot window: the first slot's source GUID")
  -- combat and encounter timing
  fire("PLAYER_REGEN_DISABLED"); fire("ENCOUNTER_START", 3303, "Shade of the Archmage", 1, 5); fire("ENCOUNTER_END", 3303, "Shade of the Archmage", 1, 5, 1); fire("PLAYER_REGEN_ENABLED")
  assert(ev().PLAYER_REGEN_DISABLED.n == 1 and ev().PLAYER_REGEN_ENABLED.n == 1 and ev().PLAYER_REGEN_ENABLED.s.t == "number"
    and ev().ENCOUNTER_START.s.id == "number" and ev().ENCOUNTER_START.s.t == "number" and ev().ENCOUNTER_START.s.diff == "number" and ev().ENCOUNTER_END.n == 1,
    "combat edges and the encounter id with a time")
  -- an event QuestBank registered but has no reader for: its argument count
  fire("SOMETHING_ELSE", 1, 2)
  assert(ev().SOMETHING_ELSE.s.nargs == "number", "an unknown event: counted with its argument count")
  -- with the box unticked nothing is counted
  DB.settings = DB.settings or {}
  DB.settings.noteGame = false
  local n0 = ev().UNIT_HEALTH.n
  f.__scripts.OnEvent(f, "UNIT_HEALTH", "target")
  assert(ev().UNIT_HEALTH.n == n0, "the box unticked: the frame's handler counts nothing")
  DB.settings.noteGame = nil
  c.env.UnitLevel, c.env.UnitGUID = unitLevel, guidOf
  c.env.UnitClassification, c.env.UnitHealth, c.env.UnitHealthMax, c.env.UnitCastingInfo, c.env.UnitChannelInfo = nil, nil, nil, nil, nil
  c.env.GetMerchantItemInfo, c.env.GetMerchantItemLink = nil, nil
  -- the readout, then the clear that the notes box does
  local chat0 = #c.chat
  c.env.SlashCmdList.QUESTBANK("events")
  local said = table.concat(c.chat, "\n", chat0 + 1)
  assert(#c.chat > chat0 and said:find("TEST_EVENT: 2 seen, 1 ok, 1 secret, 0 missing (a=number b=string)", 1, true), "/qb events lists the events with their counts: " .. said:sub(1, 200))
  Ob.Clear()
  assert(DB.diag.ev == nil, "clear drops the probe's counts")
  Ob.Note("X", { a = 1 })
  assert(ev().X.n == 1, "and counting starts again")
  -- the cap, and never a name in what is kept
  for i = 1, 70 do Ob.Note("FILL_" .. i, { a = i }) end
  assert(countOf(ev()) == 60, "no more than 60 event keys")
  local dump = {}
  for k, v in pairs(ev()) do for fld, kind in pairs(v.s) do dump[#dump + 1] = k .. fld .. kind end end
  assert(not table.concat(dump):find("Torvald", 1, true) and not table.concat(dump):find("Arcane Bolt", 1, true), "never a player's name, never a value")
  Ob.Clear()
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
  assert(#icons("obj") == 1 and icons("obj")[1].data.id == 18, "Zephras Isle draws its own spots")
  -- (since 3.6.2 Wowhead's NPC tooltips place the island's own quest givers too, so their ! show there as well: each
  -- one for a giver who stands on the island, with a quest you can take now)
  for _, pin in ipairs(icons("give")) do
    for _, q in ipairs(pin.data.quests) do
      assert(q.give and q.give.m == 2521 and MQ:Status(q).code == "todo", "an island ! is for a giver standing there: " .. q.name)
    end
  end
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
-- the quest survey (Survey.lua): out of combat and outside instances QuestBank asks the game about the quests of
-- D.SURVEY by id, two a second, and uses what it tells at once. A level-50 rogue on the Forever client; the server
-- below knows a Forever quest no list has (99999, the Shimmerwine Shanker, item 276903, level 52), a catalog quest
-- nobody knew the rewards of (10), a quest whose rewards come late, one with none; it says no to 99001 and never
-- answers 99004, and knows nothing of 80001
----------------------------------------------------------------------------
local function d0(c) return c.env.QuestBankDB.disc end
local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = deepCopy(v) end
  return o
end
-- the server's quests on a client, and the client's calls about them by id. c.server[id] = { t, lvl, xp, money, c, r,
-- late = reads before the rewards are all there, fail = the server says no, silent = it never answers, sync = the
-- answer comes inside the call, cached = the client has the quest already, noIds = its reward slots never give an id }
local function surveyClient(c, server)
  local env = c.env
  c.server, c.loadedQ, c.qAsked = server, {}, {}
  for id, s in pairs(server) do if s.cached then c.loadedQ[id] = true end end
  local function known(id) return c.loadedQ[id] and c.server[id] or nil end
  env.HaveQuestData = function(id) return c.loadedQ[id] and true or false end
  env.C_QuestLog.RequestLoadQuestByID = function(id)
    assert(not c.combat, "the survey asks nothing in a fight")
    local ask = { id = id, t = c.clock }
    c.qAsked[#c.qAsked + 1] = ask
    local s = c.server[id]
    if s and s.silent then return end
    local ok = s ~= nil and not s.fail
    if ok then c.loadedQ[id] = true end
    local function reply()
      ask.back = c.clock
      local f = c.QB.Survey.frame
      f.__scripts.OnEvent(f, "QUEST_DATA_LOAD_RESULT", id, ok)
    end
    -- data the client has answers inside the call (the event is synchronous); the rest a moment later
    if s and s.sync then reply() else env.C_Timer.After(0.2, reply) end
  end
  env.C_QuestLog.GetTitleForQuestID = function(id) local s = known(id); return s and s.t end
  env.C_QuestLog.GetQuestDifficultyLevel = function(id) local s = known(id); return s and s.lvl or 0 end
  env.HaveQuestRewardData = function(id)
    local s = known(id)
    if not s then return false end
    if (s.late or 0) > 0 then s.late = s.late - 1; return false end
    return true
  end
  env.GetNumQuestLogChoices = function(id) local s = known(id); return s and #(s.c or {}) or 0 end
  env.GetNumQuestLogRewards = function(id) local s = known(id); return s and #(s.r or {}) or 0 end
  env.GetQuestLogChoiceInfo = function(i, id)
    local s = known(id); local item = s and s.c[i]
    if item then return "Item " .. item, 133328, 1, 2, true, (not s.noIds) and item or nil end
  end
  env.GetQuestLogRewardInfo = function(i, id)
    local s = known(id); local item = s and s.r[i]
    if item then return "Item " .. item, 133328, 1, 2, true, item end
  end
  local logXP = env.GetQuestLogRewardXP
  env.GetQuestLogRewardXP = function(id) local s = known(id); if s then return s.xp or 0 end return logXP(id) end
  env.GetQuestLogRewardMoney = function(id) local s = known(id); return s and s.money or 0 end
  -- what the finder needs of an item without its cache: a dagger, leather and cloth chests, a leather belt; armor otherwise
  local INSTANT = { [276903] = { "INVTYPE_WEAPONMAINHAND", 2, 15 }, [2470] = { "INVTYPE_CHEST", 4, 2 }, [2435] = { "INVTYPE_CHEST", 4, 1 },
                    [2471] = { "INVTYPE_WAIST", 4, 2 } }
  env.C_Item.GetItemInfoInstant = function(id)
    local i = INSTANT[id] or { "INVTYPE_CHEST", 4, 1 }
    return id, "Armor", "Cloth", i[1], 133328, i[2], i[3]
  end
  local itemInfo = env.GetItemInfo
  env.GetItemInfo = function(id) local name, link = itemInfo(id); return c.itemName[id] or name, link end
  c.itemName[276903], c.itemLevel[276903] = "Shimmerwine Shanker", 52
  c.itemLevel[2470], c.itemLevel[2435], c.itemLevel[2471] = 50, 50, 50
end
local SERVER = {
  [99999] = { t = "Shimmerwine Shakedown", lvl = 51, xp = 6150, money = 4500, c = { 276903 }, r = {} },
  [99002] = { t = "Late Rewards", lvl = 30, c = { 2470 }, r = {}, late = 2 },
  [99003] = { t = "Empty Hands", lvl = 30, c = {}, r = {}, sync = true },
  [10] = { t = "The Scrimshank Redemption", lvl = 48, xp = 4400, c = { 2470, 2435 }, r = { 2471 } },
  [99001] = { fail = true },
  [99004] = { silent = true },
  [99006] = { t = "Already Here", lvl = 40, c = { 2435 }, r = {}, cached = true },
  [99007] = { t = "Never Whole", lvl = 40, c = { 2435 }, r = {}, noIds = true },
}
local RUNA = { name = "Runa", level = 50, cap = 60, faction = "Alliance", className = "Rogue", class = "ROGUE", classID = 4, race = "Human",
               log = {}, done = {}, group = false, guild = false, world = { 0, -8914, -133 }, bind = "Stormwind City", riding = true,
               bagSlots = {}, xp = 100, map = 1453 }
local runa = newClient(deepCopy(RUNA))
do
  local c, Q2 = runa, runa.QB
  local S, D2 = Q2.Survey, Q2.Data
  -- the real list: three ascending runs, the catalog's run exactly its quests with no rewards known
  local real = {}
  for run, s in ipairs(D2.SURVEY) do
    local ids = S.Decode(s)
    assert(#ids > 0, "run " .. run .. " has ids")
    for k, id in ipairs(ids) do
      assert(k == 1 or id > ids[k - 1], "each run ascends")
      assert(not real[id], "an id once")
      real[id] = run
      if run == 2 then assert(D2.Q[id] and D2.RUNK[id], "the catalog's run: a catalog quest with no rewards known: " .. id)
      elseif run == 4 then assert(D2.Q[id] and D2.RITEMS[id], "the check: catalog quests whose items Wowhead lists: " .. id)
      else assert(not D2.Q[id] and (run == 1) == (id >= 90000), "the other runs: ids the catalog lacks, the new range first: " .. id) end
    end
  end
  for id in pairs(D2.RUNK) do if D2.Q[id] then assert(real[id] == 2, "every catalog quest with no rewards known is asked about: " .. id) end end
  assert(S.Decode(S.Encode({ 1, 2, 33, 1057, 99999 }))[5] == 99999 and #S.Encode({ 99999 }) == 4, "the encoding reads back")
  assert(D2.RUNK[10] and not D2.RITEMS[10], "quest 10's rewards are not known before the survey")
  -- the check: three Forever quests whose items Wowhead lists, asked first
  local CHECK = S.Decode(D2.SURVEY[4])
  assert(#CHECK == 3, "three quests to check")
  for _, id in ipairs(CHECK) do
    local R = D2.RITEMS[id]
    assert(D2.Q[id] and R and ((R.c and #R.c > 0) or (R.r and #R.r > 0)), "a check quest has items on Wowhead's list: " .. id)
  end
  -- this test's list: the server's quests, and 80001, which it knows nothing of
  D2.SURVEY = { S.Encode({ 99001, 99002, 99003, 99004, 99006, 99007, 99999 }), S.Encode({ 10 }), S.Encode({ 80001 }), D2.SURVEY[4] }
  local WANT = { [99001] = true, [99002] = true, [99003] = true, [99004] = true, [99006] = true, [99007] = true, [99999] = true, [10] = true, [80001] = true }
  local server = deepCopy(SERVER)
  for _, id in ipairs(CHECK) do
    WANT[id] = true
    server[id] = { t = Q2.Data.QN[id], lvl = D2.Q[id][1], c = deepCopy(D2.RITEMS[id].c or {}), r = deepCopy(D2.RITEMS[id].r or {}) }
  end
  surveyClient(c, server)
  c.unloaded[2470] = true -- not in the item cache yet: its level comes once the server sends the item
  login(c)
  assert(S.frame and S.On() and #c.qAsked == 0, "nothing is asked in the first seconds after login")
  tick(c, 16)
  local first = #c.qAsked
  assert(first >= 2 and first <= 3 and c.qAsked[1].t >= 1000 + S.START, "it starts half a minute after login: " .. first)
  -- a fight: nothing is asked until it ends
  c.combat = true
  tick(c, 30)
  assert(#c.qAsked == first and S.state == "fight", "nothing in a fight")
  c.combat = false
  S.frame.__scripts.OnEvent(S.frame, "PLAYER_REGEN_ENABLED")
  tick(c, 1)
  assert(#c.qAsked > first, "it goes on when the fight ends")
  -- an instance: it stops, and the loading screen on the way out starts it again after a few seconds
  local inside = true
  c.env.IsInInstance = function() return inside, inside and "party" or "none" end
  tick(c, 1)
  local n = #c.qAsked
  tick(c, 40)
  assert(#c.qAsked == n and S.state == "instance", "nothing inside an instance")
  inside = false
  S.frame.__scripts.OnEvent(S.frame, "PLAYER_ENTERING_WORLD", false, false)
  tick(c, S.SETTLE - 1)
  assert(#c.qAsked == n, "not in the seconds after the loading screen")
  tick(c, 2)
  assert(#c.qAsked > n, "and on after them")
  -- a secret id, or an answer to a quest it never asked about (Blizzard's own requests fire the event too): nothing
  S.frame.__scripts.OnEvent(S.frame, "QUEST_DATA_LOAD_RESULT", SECRET.num(), true)
  S.frame.__scripts.OnEvent(S.frame, "QUEST_DATA_LOAD_RESULT", 4242, true)
  tick(c, 300)
  assert(S.state == "done", "done: " .. tostring(S.state))
  -- only the list's ids, PACE apart at the least, never more than FLIGHT waiting for an answer
  local count = {}
  for k = 1, 3 do assert(c.qAsked[k].id == CHECK[k], "the check is asked first") end
  assert(Q2.Survey.Checked() == "trusted", "the game showed the check quests' items")
  for k, a in ipairs(c.qAsked) do
    assert(WANT[a.id], "asked only about the list's quests: " .. a.id)
    count[a.id] = (count[a.id] or 0) + 1
    assert(k == 1 or a.t - c.qAsked[k - 1].t >= S.PACE - 1e-9, "paced: " .. (a.t - (c.qAsked[k - 1] or a).t))
    local waiting = 0
    for j = 1, k - 1 do
      local b = c.qAsked[j]
      if (not b.back or b.back > a.t) and a.t - b.t < S.TIMEOUT then waiting = waiting + 1 end
    end
    assert(waiting < S.FLIGHT, "at most " .. S.FLIGHT .. " waiting for an answer")
  end
  -- a quest the server says no to, one it never answers and one it doesn't know: three tries each, no more
  assert(count[99001] == S.TRIES and count[99004] == S.TRIES and count[80001] == S.TRIES, "three tries for a failure")
  for id, s in pairs(SERVER) do if not s.fail and not s.silent and not s.cached then assert(count[id] == 1, "asked once: " .. id) end end
  -- a quest the client has already is read without a question (its answer would come inside QuestBank's call)
  assert(not count[99006] and d0(c).survey[99006].c[1] == 2435, "read as the client has it")
  -- rewards that never come whole: the try fails, the title stays, three reads in all and the quest rests
  assert(d0(c).surveyNo[99007] == 3 and d0(c).survey[99007].t == "Never Whole" and d0(c).survey[99007].c == nil, "never whole: three tries")
  local d = c.env.QuestBankDB.disc
  assert(d.surveyB == 70170 and d.surveyNo[99001] == 3 and d.surveyNo[99004] == 3 and d.surveyNo[80001] == 3, "the tries are kept for this build")
  -- what the game told, kept per account
  local rec = d.survey[99999]
  assert(rec.t == "Shimmerwine Shakedown" and rec.lvl == 51 and rec.xp == 6150 and rec.pl == 50 and rec.money == 4500 and rec.b == 70170
    and #rec.c == 1 and rec.c[1] == 276903 and #rec.r == 0 and rec.at, "the title, rewards, XP, money and level are kept")
  assert(d.survey[99002].c[1] == 2470, "rewards that come late are read again until they are all there")
  assert(#d.survey[99003].c == 0 and #d.survey[99003].r == 0, "no item rewards: two empty lists (answered inside the call)")
  assert(d.survey[10].c[2] == 2435 and d.survey[10].r[1] == 2471, "a catalog quest's lists")
  assert(not d.q[99999] and not d.q[10], "the survey is no sighting: the quest notes stay as they were")
  local dg = c.env.QuestBankDB.diag.survey
  assert(dg.asked == #c.qAsked and dg.loaded == 11 and dg.rewards == 7 and dg.failed == 12, "the counts: " .. dg.asked .. " " .. dg.loaded .. " " .. dg.rewards .. " " .. dg.failed)
  for _, id in ipairs(CHECK) do assert(not D2.RSURV[id], "a check quest's lists stay Wowhead's: " .. id) end
  -- an item the client didn't have: asked of the server in turn (never in one go), and the quests waiting on its level
  -- are rated again when it comes
  local reqs = 0
  for _, i in ipairs(c.loadRequests) do if i == 2470 then reqs = reqs + 1 end end
  assert(reqs == 1 and D2.REWARD[99002] and D2.REWARD[99002][1] == 0, "the leather chest's level is asked for once")
  c.unloaded[2470] = nil
  S.frame.__scripts.OnEvent(S.frame, "ITEM_DATA_LOAD_RESULT", 2470, true)
  assert(D2.REWARD[99002][1] == 50 and D2.REWARD[99002][3] == 2470, "and it comes")
  -- used at once: the catalog quest's rewards in its tooltip and in the finders' facts (Available's gear chip reads them)
  assert(D2.RITEMS[10] and not D2.RUNK[10] and D2.REWARD[10][1] == 50 and D2.REWARD[10][2] % 2 == 1, "quest 10's rewards are in the catalog's tables")
  local q10 = Q2.Quest.Get(10)
  local _, how = Q2.Quest.Rewards(q10)
  assert(how == "survey", "and they say where they come from")
  lines = {}; Q2.UI.QuestTooltip(c.env.GameTooltip, q10, Q2:Status(q10), 1000)
  local t = table.concat(lines, "\n")
  assert(t:find("Choose one:", 1, true) and t:find("You get:", 1, true) and t:find("As the game told QuestBank.", 1, true), t)
  local function found(level)
    for _, row in ipairs(Q2.UI:FindRewards("gear", level)) do if row.q.id == 99999 then return row end end
  end
  -- the Forever quest no list has: Best gear finds it for the rogue at 51 (and at 50: the range reaches four levels up)
  local hit = found(51)
  assert(hit and hit.reward[1] == 52 and hit.reward[3] == 276903 and hit.q.name == "Shimmerwine Shakedown" and hit.q.surveyOnly, "Best gear at 51")
  assert(found(50), "and at 50")
  assert(hit.q.cat and hit.q.cat.name == "Seen in game" and not hit.q.give and not hit.q.turn, "seen in game, no giver")
  for _, cand in ipairs(Q2.UI:Candidates(nil, 51)) do assert(cand.id ~= 99999, "nothing but the finders suggests it") end
  -- on the page: the weapons, the dagger first
  local U = Q2.UI
  U.findMode, U.gearSlot = "gear", "Weapon"
  U:Open(1); U:Refresh()
  local row
  for _, r in ipairs(U.views[1].swaps) do if r:IsShown() and r.add and r.add.id == 99999 then row = r end end
  assert(row and row.gain:GetText() == "iL 52" and row.cutName:GetText():find("Shimmerwine Shanker", 1, true)
    and row.cutName:GetText():find("Seen in game", 1, true), "the row: " .. tostring(row and row.cutName:GetText()))
  for _, p in ipairs(checkLayout(U.frame, "Quest Log, Best gear, seen in game")) do problems[#problems + 1] = p end
  lines = {}; row.__scripts.OnEnter(row)
  t = table.concat(lines, "\n")
  assert(t:find("Seen in game: QuestBank asked the game about it", 1, true) and t:find("Level 51", 1, true) and not t:find("needs", 1, true)
    and t:find("As the game told QuestBank.", 1, true), t)
  local said = #c.chat
  row.__scripts.OnClick(row, "LeftButton")
  assert(#c.chat == said + 1 and c.chat[#c.chat]:find("Who gives Shimmerwine Shakedown isn't known yet", 1, true), "no waypoint: it says so")
  U.findMode, U.gearSlot = "xp", nil
  -- the item's own tooltip names the quest
  lines = {}; Q2.Link.ItemTip(c.env.GameTooltip, { id = 276903 })
  assert(table.concat(lines, "\n"):find("Reward of: Shimmerwine Shakedown (L51, Seen in game)", 1, true), table.concat(lines, "\n"))
  -- /qb survey
  said = #c.chat
  c.env.SlashCmdList.QUESTBANK("survey")
  assert(c.chat[said + 1]:find("12 of 12 quests done on this build", 1, true) and c.chat[said + 1]:find("Done for this game build.", 1, true), c.chat[said + 1])
  -- the Settings box: ticked by default here; unticked, nothing more is asked
  U:Open(5); U:Refresh()
  local v5 = U.views[5]
  assert(v5.survey:IsEnabled() and v5.survey:GetChecked() and v5.survey.label:GetText() == "Learn quests from the game", "the box")
  lines = {}; v5.survey.__scripts.OnEnter(v5.survey)
  assert(table.concat(lines, "\n"):find("12 of 12 quests done on this build, 7 with item rewards.", 1, true), table.concat(lines, "\n"))
  v5.survey:SetChecked(false); v5.survey.__scripts.OnClick(v5.survey, "LeftButton")
  assert(Q2:Settings().survey == false and S.state == "off" and not S.On(), "unticked: off")
  v5.survey:SetChecked(true); v5.survey.__scripts.OnClick(v5.survey, "LeftButton")
  assert(Q2:Settings().survey == true and S.On(), "ticked again")
  for _, p in ipairs(checkLayout(U.frame, "Settings, with the survey")) do problems[#problems + 1] = p end
  print(string.format("quest survey: %d questions, %d quests answered, the Shimmerwine Shanker in Best gear at iL %d", #c.qAsked, dg.loaded, hit.reward[1]))
end

-- after a reload the account's survey stands: what it learned is in the finders before any question, and only what is
-- new on the list is asked. A new build asks everything again. A client that answers every id with one quest's XP
-- (four quests of different levels paying the same) or one quest's rewards (six in a row) gives itself away
do
  local saved = deepCopy(runa.env.QuestBankDB)
  local again = newClient(deepCopy(RUNA))
  again.env.QuestBankDB = saved
  local Q2, S = again.QB, again.QB.Survey
  local server = deepCopy(SERVER)
  local CHECK = S.Decode(Q2.Data.SURVEY[4])
  for _, id in ipairs(CHECK) do
    server[id] = { t = Q2.Data.QN[id], lvl = Q2.Data.Q[id][1], c = deepCopy(Q2.Data.RITEMS[id].c or {}), r = deepCopy(Q2.Data.RITEMS[id].r or {}) }
  end
  for k = 0, 3 do server[99010 + k] = { t = "Same Pay " .. k, lvl = 20 + 10 * k, xp = 5000, c = {}, r = {} } end
  for k = 0, 5 do server[99020 + k] = { t = "Same Items " .. k, lvl = 40, c = { 2435 }, r = {} } end
  server[99005] = { t = "New On The List", lvl = 45, c = { 2471 }, r = {} }
  surveyClient(again, server)
  local list = { 99001, 99002, 99003, 99004, 99005, 99999 }
  for k = 0, 3 do list[#list + 1] = 99010 + k end
  for k = 0, 5 do list[#list + 1] = 99020 + k end
  table.sort(list)
  Q2.Data.SURVEY = { S.Encode(list), S.Encode({ 10 }), S.Encode({ 80001 }), Q2.Data.SURVEY[4] }
  login(again)
  local row
  for _, r in ipairs(Q2.UI:FindRewards("gear", 51)) do if r.q.id == 99999 then row = r end end
  assert(row and row.reward[1] == 52 and #again.qAsked == 0, "after a reload: in Best gear at once, before any question")
  assert(Q2.Data.RITEMS[10] and not Q2.Data.RUNK[10], "and the catalog quest's rewards too")
  tick(again, 400)
  local asked = {}
  for _, a in ipairs(again.qAsked) do asked[a.id] = (asked[a.id] or 0) + 1 end
  assert(not asked[99999] and not asked[10] and not asked[99001] and not asked[99004] and not asked[80001] and asked[99005] == 1,
    "only what is new on the list is asked on the same build")
  local d = again.env.QuestBankDB.disc
  assert(d.survey[99005].c[1] == 2471 and Q2.Data.REWARD[99005], "the new one is kept, and in the finders")
  for k = 0, 3 do assert(d.survey[99010 + k].xp == nil and d.survey[99010 + k].t == "Same Pay " .. k, "one XP for every level: not kept") end
  for k = 0, 5 do assert(d.survey[99020 + k].c == nil and not Q2.Data.RITEMS[99020 + k], "one reward list for six quests in a row: not kept") end
  assert(d.survey[99999].xp == 6150, "the readings before stay")
  -- a new build: every quest is asked again. This one shows no items for the check's quests: then no answer that a
  -- quest gives no items is kept (the earlier build's stands), and /qb survey says why
  again.env.GetBuildInfo = function() return "1.60.1", "70400", "Oct 14 2026", 16001 end
  for _, id in ipairs(CHECK) do server[id].c, server[id].r = {}, {}; again.loadedQ[id] = nil end
  again.loadedQ[99003] = nil
  S.Start(0)
  tick(again, 400)
  local fresh = 0
  for _, a in ipairs(again.qAsked) do if a.id == 99999 then fresh = fresh + 1 end end
  assert(fresh == 1 and d.surveyB == 70400 and d.survey[99999].b == 70400, "a new build asks again")
  assert(S.Checked() == "failed" and d.surveyNo[99003] == 3 and d.survey[99003].b == 70170, "no-item answers aren't kept when the check failed")
  local said = #again.chat
  again.env.SlashCmdList.QUESTBANK("survey")
  assert(again.chat[said + 1]:find("no-reward answers aren't kept", 1, true), again.chat[said + 1])
  print(string.format("quest survey after a reload: %d questions in all, the new build's with them", #again.qAsked))
end

-- the other end: players' uploads with survey answers (tools/fixtures/probe/QuestBank-survey.lua and a later build's,
-- merged by probe_pull.py) as gen_data.py builds them into Data.lua: a catalog quest with no rewards known takes the
-- game's lists, Wowhead's lists stand, the newest build's list wins, and a quest no list has goes to D.SURVEYED (in
-- the finders) with the Shimmerwine Shanker's facts. Where the generator's inputs are (research/), with python3
do
  local inputs = io.open(HERE .. "/../../research/questbank/manifest.json")
  if inputs then
    inputs:close()
    local p = io.popen("cd '" .. HERE .. "' && python3 gen_data.py --selftest-survey 2>&1")
    local out = p and p:read("*a") or ""
    if p then p:close() end
    assert(out:find("selftest-survey: OK", 1, true), "gen_data.py --selftest-survey:\n" .. out)
    print((out:match("(selftest%-survey: OK[^\n]*)")))
  else
    print("gen_data.py --selftest-survey: skipped (no research/ here)")
  end
end

----------------------------------------------------------------------------
-- calls QuestBank's code never makes, read from the files themselves (code only, comments left out). Each one runs
-- the game's own code as QuestBank, where the game later blocks it and blames QuestBank:
--   the game's waypoint and tracking (USER_WAYPOINT_UPDATED, SUPER_TRACKING_CHANGED and QUEST_WATCH_LIST_CHANGED run
--   Blizzard's listeners inside the call), Blizzard's popups (their list of popups on screen), opening the chat box
--   (the game's chat globals), the escort prompt's Yes with no click behind it and its count of a full log (MAX_QUESTS:
--   read, never written; the prompt reads it as it opens), the map canvas's pin calls, the world map laid out or moved
--   as QuestBank (ToggleWorldMap sizes it and fills its quest log, SetMapID redraws its pins; the Map opens through
--   OpenWorldMap, which the game's own panel code shows), and the loot window's actions (taking a slot, closing it,
--   rolling, the loot method: the drop-source notes only read the window)
----------------------------------------------------------------------------
do
  -- whole names (CanSetUserWaypointOnMap, a question, is fine; so is GetLootSlotInfo next to LootSlot), and the start of
  -- a family (StaticPopup_Show, _Hide...)
  local NEVER = { "SetUserWaypoint", "ClearUserWaypoint", "C_SuperTrack", "AddQuestWatch", "RemoveQuestWatch",
    "AddWorldQuestWatch", "AddQuestWatchForQuestID", "StaticPopupDialogs", "OpenChat", "ChatFrame_OpenChat", "ActivateChat",
    "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX", "ConfirmAcceptQuest", "AcquirePin", "RemoveAllPinsByTemplate",
    "RemovePin", "SetPinPosition", "MarkCanvasDirty", "UpdateQuestAcceptLogFullDialog", "MAX_QUESTLOG_QUESTS",
    "LootSlot", "CloseLoot", "ConfirmLootSlot", "ConfirmLootRoll", "RollOnLoot", "SetLootMethod", "ToggleWorldMap", "SetMapID" }

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
