-- Mock WoW client for Cute. Loads the addon into separate clients (each its own globals), gives them one guild, routes
-- their addon messages (back to the sender too, as the game does), drives events and timers, opens every page for an
-- officer and a member, and fails on any widget method outside a whitelist of real API methods. It lays the window out
-- like the game does and reports clipped text, overlapping text, text the game's font cannot draw, and buttons too
-- near an edge. It counts SetPoint and SetText calls (OPS), so a scenario can hold a draw's cost to the rows in view.
-- Forever's names are mocked as the client gives them: a character made with a surname has UnitName's second return
-- as that surname, the roster and the channel name it with both words, and a roster name can be a Kstring.
-- The mock defines what Forever's generated API docs list (C_Club for the guild, C_GuildInfo for its Guild Info, kept
-- per guild in one table, C_SpecializationInfo, C_MajorFactions, C_Traits, C_SkillInfo, GetMirrorTimerProgress...),
-- what QuestBank reads on this client (GetInventoryItemLink, the taxi
-- nodes) and, named one by one in UNDOCUMENTED below with the evidence for each, the globals no doc lists that Cute
-- reads all the same: the Legacy window's achievement calls on every client, the statistics API (which only the
-- mainline panel calls, never loaded on camelot) on o.withStats clients alone, so the gate runs Cute with it and
-- without it. A stat reading anything else reads nil here too, and the registry scenario fails on it.
-- Every scenario runs twice, in a loop: once with a seed (a small fixture, below, standing in for Known.lua, so the
-- scenarios do not move with what gen_known.py writes) and once with none, as a copy without Known.lua runs. The real
-- Known.lua, where gen_known.py has written it, is loaded by the two scenarios that weigh it (the seed, and rule 4 in
-- Blackrock Depths).
--   luajit tools/cute/harness.lua                   run every scenario, both passes
--   luajit tools/cute/harness.lua --layout out.json  also write the window, page by page, for tools/questbank/render_layout.py
math.randomseed = nil -- the client has none
local HERE = (arg and arg[0] and arg[0]:match("^(.*)/") or ".")
local LAYOUT_OUT
for i = 1, #arg do if arg[i] == "--layout" then LAYOUT_OUT = arg[i + 1] end end
-- the loop: this file loads itself once per pass; each pass adds its layout problems and layouts to CUTE_RESULTS, and
-- the last prints them all
if not CUTE_PASS then
  -- (the collector runs before the heap doubles: the gate's peak stays near 300 MB on a machine that has little to spare)
  collectgarbage("setpause", 120)
  CUTE_RESULTS = { problems = {}, layouts = {} }
  local passes = { "seed", "none" }
  for i, pass in ipairs(passes) do
    CUTE_PASS, CUTE_LAST = pass, i == #passes
    print(pass == "seed" and "== with the seed (the fixture standing in for Known.lua)" or "== with no seed")
    collectgarbage() -- (the last pass's clients and widgets, gone before the next one makes its own)
    assert(loadfile(arg[0]))(...)
  end
  return
end
local SEEDED = CUTE_PASS == "seed"

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
SetResizable SetResizeBounds StartSizing CreateMaskTexture AddMaskTexture SetScale GetScale SetHitRectInsets
IsForbidden SetPushedTexture GetTextColor SetMultiLine HighlightText SetRotation SetAtlas SetPassThroughButtons SetCooldown
SetHideCountdownNumbers SetUserPlaced GetZoom SetZoom GetZoomLevels SetStartPoint SetEndPoint SetThickness CreateLine SetTextInsets
SetAttribute GetAttribute SetGradient SetClipsChildren PingLocation SetSnapToPixelGrid SetTexelSnappingBias]])
-- (the last three lines: the quest engine's, for a client made with o.quest = true; QuestBank's harness lists them)
local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }
-- a PlayerModel's own and a QuestPOIFrame's own (the quest engine's journal and map files), as QuestBank's harness has them
local MODEL = { SetDisplayInfo = true, SetCreature = true, SetPortraitZoom = true, ClearModel = true, SetKeepModelOnHide = true }
local POI = { DrawBlob = true, DrawNone = true, SetMapID = true, SetFillTexture = true, SetBorderTexture = true, SetFillAlpha = true,
  SetBorderAlpha = true, SetBorderScalar = true }
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
-- every widget made, in order, held weakly: a client gone (left, or its scenario over) and everything it drew are
-- collected, so the run's memory stays with the clients alive (everything() walks them in order). A widget is held by
-- its parent (__kids), as the game holds a frame's children, and a client's frames by the client: one alive keeps
-- all it drew, so the layout checks see every widget as before
local function adopt(parent, o)
  if not parent then return end
  local kids = rawget(parent, "__kids")
  if not kids then kids = {}; rawset(parent, "__kids", kids) end
  kids[#kids + 1] = o
end
local ALL, NALL = setmetatable({}, { __mode = "v" }), 0
local function everything()
  local i = 0
  return function()
    while i < NALL do
      i = i + 1
      local o = ALL[i]
      if o then return i, o end
    end
  end
end
local rectOf, GEN = nil, 0 -- (layout, below: a size asked of an anchored frame is worked out as the game would)
local OPS = { n = 0 } -- SetPoint and SetText calls, every client
local function newObj(kind, template, parent)
  local o = { __kind = kind, __scripts = {}, __events = {}, __shown = true, __w = 0, __h = 0, __text = "", __value = 0, __min = 0,
              __max = 0, __points = {}, __parent = parent, __alpha = 1, __size = 12, __wrap = true, __justify = "CENTER" }
  o.__backdrop = template and template:find("BackdropTemplate") and true or false
  o.__template = template
  if template == "UIPanelCloseButton" then o.__w, o.__h = 24, 24 end
  NALL = NALL + 1
  ALL[NALL] = o
  adopt(parent, o)
  local mt = {}
  mt.__index = function(t, k)
    if METHODS[k] or (BACKDROP[k] and t.__backdrop) or (MODEL[k] and kind == "PlayerModel") or (POI[k] and kind == "QuestPOIFrame") then
      return function(self, ...)
        local a = { ... }
        local n = select("#", ...)
        if k == "SetPoint" or k == "SetText" then OPS.n = OPS.n + 1 end
        if k == "SetScript" then self.__scripts[a[1]] = a[2]
        -- (the quest engine's: a line, the minimap's zoom, an atlas, an attribute, a model, a quest area)
        elseif k == "CreateLine" then local x = newObj("Line", nil, self); x.__layer = a[2] or "ARTWORK"; return x
        elseif k == "SetThickness" then self.__thick = a[1]
        elseif k == "SetStartPoint" then self.__start = { a[1], a[2], a[3], a[4] }
        elseif k == "SetEndPoint" then self.__stop = { a[1], a[2], a[3], a[4] }
        elseif k == "GetZoom" then return self.__zoom or 0
        elseif k == "SetZoom" then self.__zoom = a[1]
        elseif k == "GetZoomLevels" then return 6
        elseif k == "GetTextColor" then local col = self.__color or { 1, 1, 1 }; return col[1], col[2], col[3], 1
        elseif k == "SetRotation" then self.__rot = a[1]
        elseif k == "PingLocation" then self.__pings = self.__pings or {}; table.insert(self.__pings, { a[1], a[2] })
        elseif k == "SetAtlas" then self.__tex = "atlas:" .. tostring(a[1]); self.__atlas = a[1]; self.__color = nil
        elseif k == "SetCooldown" then self.__cd = { a[1], a[2] }
        elseif k == "SetAttribute" then self.__attr = self.__attr or {}; self.__attr[a[1]] = a[2]
        elseif k == "GetAttribute" then return self.__attr and self.__attr[a[1]] or nil
        elseif k == "IsForbidden" then return false
        elseif k == "SetDisplayInfo" then self.__display, self.__creature = a[1], nil
        elseif k == "SetCreature" then self.__creature, self.__display = a[1], nil
        elseif k == "SetPortraitZoom" then self.__portraitZoom = a[1]
        elseif k == "ClearModel" then self.__display, self.__creature = nil, nil
        elseif k == "SetKeepModelOnHide" then self.__keepModel = a[1]
        elseif k == "SetMapID" then self.__poiMap = a[1]
        elseif k == "DrawBlob" then self.__blobQuest, self.__blobs = a[1], (self.__blobs or 0) + 1
        elseif k == "DrawNone" then self.__blobQuest = nil
        elseif k == "SetPassThroughButtons" then
          if self.__client and self.__client.combat then error("ADDON_ACTION_BLOCKED: SetPassThroughButtons in combat", 2) end
          self.__passThrough = { ... }
        elseif k == "GetScript" then return self.__scripts[a[1]]
        elseif k == "HookScript" then local old = self.__scripts[a[1]]; self.__scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
        elseif k == "RegisterEvent" then self.__events[a[1]] = true
        elseif k == "RegisterUnitEvent" then self.__events[a[1]] = true; self.__units = self.__units or {}; self.__units[a[1]] = a[2]
        elseif k == "UnregisterEvent" then self.__events[a[1]] = nil
        elseif k == "CreateTexture" then local x = newObj("Texture", nil, self); x.__layer = a[2] or "ARTWORK"; return x
        elseif k == "CreateFontString" then local x = newObj("FontString", nil, self); x.__layer = a[2] or "OVERLAY"; return x
        elseif k == "CreateMaskTexture" then local x = newObj("Texture", nil, self); x.__layer = "MASK"; return x
        elseif k == "AddMaskTexture" then self.__mask = a[1]
        -- (SimpleFrameAPIDocumentation.lua: left, right, top, bottom; a negative one widens what a click takes in)
        elseif k == "SetHitRectInsets" then self.__hit = { a[1], a[2], a[3], a[4] }
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
        elseif k == "SetParent" then self.__parent = a[1]; adopt(a[1], self)
        elseif k == "SetTexture" then self.__tex = a[1]; self.__color = nil
        elseif k == "SetColorTexture" then self.__tex = "color"; self.__color = { a[1], a[2], a[3], a[4] }
        elseif k == "SetVertexColor" then self.__vertex = { a[1], a[2], a[3], a[4] }
        elseif k == "SetBackdrop" then
          self.__inset = a[1] and a[1].insets and a[1].insets.left or 0
          -- (a flat one: the window's skin, a 1 px edge of the plain white texture; the quest engine's frames take it from Cute)
          self.__flat = (a[1] and a[1].edgeFile == "Interface\\Buttons\\WHITE8x8" and a[1].edgeSize == 1) or nil
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
          for _, x in everything() do if x.__parent == self and x.__kind ~= "Texture" and x.__kind ~= "FontString" and x.__kind ~= "Line" then out[#out + 1] = x end end
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
-- the guild's Guild Info as the server keeps it, by the guild's club id (C_GuildInfo.GetInfoText, SetInfoText), and the
-- ranks allowed to edit it (CanEditGuildInfo: rank index INFO_EDIT and above, the guild master's choice in the game)
local INFO, INFO_EDIT = {}, 1
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
-- sent it), named as the channel names that sender (c.sender: "Name-Realm", or a Forever name's two words). A whisper
-- (m.to, the client its target names) reaches that client alone, guild or none. A client made with c.got = {} keeps
-- every message it received, for a scenario to read off the bus, each with what JUDGE (set by a scenario) found in it
-- as it was delivered: the ids the officers' policy, as it stood at that moment, keeps to the officers
local JUDGE = nil
local function deliver()
  while #BUS > 0 do
    local m = table.remove(BUS, 1)
    local closed
    if JUDGE then closed = JUDGE(m.from, m.msg) or false end
    for _, c in ipairs(clients) do
      if (m.to and c == m.to) or (not m.to and c.inGuild) then
        if c.got then c.got[#c.got + 1] = { msg = m.msg, channel = m.channel, from = m.from.sender, closed = closed or nil, at = c.clock } end
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
  -- ItemConstantsDocumentation.lua and BagIndexConstantsDocumentation.lua, the part Cute reads
  ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Projectile = 6, Tradegoods = 7, Miscellaneous = 15 },
  ItemConsumableSubclass = { Generic = 0, Potion = 1, Elixir = 2, Flasksphials = 3, Scroll = 4, Fooddrink = 5, Itemenhancement = 6, Bandage = 7, Other = 8 },
  BagIndex = { Keyring = -1, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 },
  SendAddonMessageResult = { Success = 0, InvalidMessage = 2, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9, AddOnMessageLockdown = 11 },
  -- RestrictedActionsConstantsDocumentation.lua: the chat restriction (5) and its states
  AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
  AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
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

-- the standing names the client's GlobalStrings give (Blizzard_FrameXMLUtil/Mainline/ReputationUtil.lua reads them by number)
for i, name in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do BASE["FACTION_STANDING_LABEL" .. i] = name end

-- items by class and subclass, as C_Item.GetItemInfoInstant gives them: { classID, subClassID }. An id the table lacks
-- is Miscellaneous; an id in a client's o.serverItems is one the client's own data lacks (GetItemInfoInstant returns
-- nothing, C_Item.GetItemInfo knows it once cached), as a server-sent Forever item may be
local ITEM_CLASS = { [118] = { 0, 1 }, [858] = { 0, 1 }, [2455] = { 0, 1 }, [2454] = { 0, 2 }, [3390] = { 0, 2 }, [13510] = { 0, 3 }, [4540] = { 0, 5 }, [159] = { 0, 5 },
  [1251] = { 0, 7 }, [5512] = { 0, 0 }, [2589] = { 7, 5 }, [5000] = { 15, 0 }, [5001] = { 4, 1 },
  -- worn items of the kinds the enchants are learned by: a bow, a gun, a wand, a dagger, a shield, a book held in the
  -- off hand (4.0, Miscellaneous armour, as the game classes one)
  [5018] = { 2, 2 }, [5019] = { 2, 3 }, [6018] = { 2, 19 }, [6022] = { 2, 15 }, [6020] = { 4, 6 }, [6021] = { 4, 0 },
  -- a cloth bracer and a leather one, as the seed's wrist enchants take (4.1, 4.2)
  [6030] = { 4, 1 }, [6031] = { 4, 2 } }
-- the names C_Item.GetItemSubClassInfo gives those kinds (the default worn item is 15.0, Miscellaneous Junk)
local SUBCLASS_NAME = { ["2.2"] = "Bows", ["2.3"] = "Guns", ["2.19"] = "Wands", ["2.15"] = "Daggers", ["4.6"] = "Shields", ["4.0"] = "Miscellaneous", ["4.1"] = "Cloth", ["4.2"] = "Leather", ["15.0"] = "Junk" }
-- the spells C_Spell.GetSpellName names: Fishing under two ids (Classic's first rank and another), the Hearthstone
local SPELL_NAME = { [7620] = "Fishing", [131474] = "Fishing", [8690] = "Hearthstone", [133] = "Fireball" }
-- the reputation list a character shows: { factionID, name, reaction, currentStanding, threshold, nextThreshold, isHeader,
-- isHeaderWithRep }. A plain header has no standing of its own; Guild is a header with rep
local FACTIONS = { { 469, "Alliance", 0, 0, 0, 0, true }, { 72, "Stormwind", 5, 3500, 3000, 9000 }, { 47, "Ironforge", 4, 1200, 0, 3000 },
  { 1168, "Guild", 4, 0, 0, 3000, true, true }, { 930, "Exodar", 6, 9500, 9000, 21000 }, { 1100, "Other", 0, 0, 0, 0, true }, { 589, "Wintersaber Trainers", 2, -4000, -6000, -3000 } }

local EPOCH = 1792300000

----------------------------------------------------------------------------
-- the seed fixture: Known.lua's fixed format, small. Four dungeons (two the beta saw, one past the beta's cap with no
-- boss known, one from research whose wings share its instance), eleven bosses (one optional) with thirty-nine items
-- of loot, four enchant slots (neck for any Miscellaneous armour, wrist for cloth to plate, main hand for two-handed
-- axes and one-handed swords, each enchant naming its kinds, off hand for shields: none of them the kinds the shared
-- scenarios wear, so those keep their meaning), a smooth XP curve and five factions. Fifty facts for Rule 0 to ask:
-- 39 items, 6 enchant recipes, 5 factions, so a share of absent ones is a whole count at the thresholds
----------------------------------------------------------------------------
local FIX = { build = "1.60.1.70338", xp = {} }
for l = 1, 59 do FIX.xp[l] = math.floor((300 + 450 * l + 40 * l * l) / 100 + 0.5) * 100 end
-- { instance, name, min, max, conf, { { boss, encounter, items of loot, optional }, ... }, wings }; the Deadmines'
-- quests (FIX.quests: two Alliance ones with QuestBank's ids, one opening at 21, a Horde one, one the catalog gave
-- no id), and one dungeon research names without an instance id (FIX.awaited: no map in the client it was made from)
FIX.dungeons = {
  { 36, "The Deadmines", 18, 23, "beta", { { "Rhahk'Zor", 1230, 4 }, { "Glubtok", 1236, 4 }, { "Mr. Smite", 1238, 3 }, { "Edwin VanCleef", 1234, 4 } } },
  { 48, "Blackfathom Deeps", 24, 32, "beta", { { "Ghamoo-ra", 1240, 4 }, { "Lady Sarevess", 1241, 3, true }, { "Twilight Lord Kelris", 1242, 4 }, { "Aku'mai", 1243, 4 } } },
  { 9001, "Krol'dok Stronghold", 32, 38, "data", {} },
  { 129, "Razorfen Downs", 37, 46, "data", { { "Tuten'kash", 1250, 3 }, { "Mordresh Fire Eye", 1251, 3 }, { "Amnennar the Coldbringer", 1252, 3 } }, { "Halls", "Crypt" } },
}
FIX.quests = { [36] = { { name = "Red Silk Bandanas", id = 214, level = 17, min = 14, side = "a" }, { name = "The Defias Brotherhood", id = 166, level = 22, min = 14, side = "a" },
  { name = "Underground Assault", id = 2040, level = 20, min = 21, side = "a" }, { name = "The Horde's Errand", id = 9990, level = 20, min = 15, side = "h" },
  { name = "Oh Brother. . .", level = 20, min = 15 } } }
FIX.awaited = { { name = "The Drowned City", min = 35, max = 40 } }
FIX.items, FIX.loot = {}, {}
do
  local nextItem = 30001
  for _, d in ipairs(FIX.dungeons) do
    for _, b in ipairs(d[6]) do
      FIX.loot[b[2]] = {}
      for _ = 1, b[3] do FIX.items[#FIX.items + 1] = nextItem; table.insert(FIX.loot[b[2]], nextItem); nextItem = nextItem + 1 end
    end
  end
end
FIX.spells = { 27001, 7418, 7428, 13529, 7788, 13378 }
FIX.factions = { [72] = "Stormwind", [47] = "Ironforge", [930] = "Exodar", [589] = "Wintersaber Trainers", [69] = "Darnassus" }
local function fixtureSource(f)
  f = f or FIX
  local out = { "local _, C = ...", "C.Known = {", string.format("  v = 1, build = %q, generated = \"2026-10-19\", betaCap = 30, cap = 60,", f.build),
    "  sources = { \"codex/loot.json\", \"research/wago/1.60.1.70338/DungeonEncounter.csv\" },", "  dungeons = {" }
  for _, d in ipairs(f.dungeons) do
    local bosses = {}
    for _, b in ipairs(d[6]) do
      local loot = {}
      for _, id in ipairs(FIX.loot[b[2]] or {}) do loot[#loot + 1] = tostring(id) end
      bosses[#bosses + 1] = string.format("{ name = %q, enc = %d, conf = %q, loot = { %s }%s }", b[1], b[2], d[5], table.concat(loot, ", "), b[4] and ", optional = true" or "")
    end
    local wings = {}
    for _, wname in ipairs(d[7] or {}) do wings[#wings + 1] = string.format("%q", wname) end
    local quests = {}
    for _, q in ipairs((f.quests or FIX.quests)[d[1]] or {}) do
      quests[#quests + 1] = string.format("{ name = %q%s, level = %d, min = %d%s }", q.name, q.id and (", id = " .. q.id) or "", q.level, q.min, q.side and string.format(", side = %q", q.side) or "")
    end
    out[#out + 1] = string.format("    [%d] = { name = %q, min = %d, max = %d, new = %s, conf = %q, kind = \"party\",%s%s bosses = { %s } },",
      d[1], d[2], d[3], d[4], tostring(d[1] == 9001), d[5], d[7] and (" wings = { " .. table.concat(wings, ", ") .. " },") or "",
      #quests > 0 and (" quests = { " .. table.concat(quests, ", ") .. " },") or "", table.concat(bosses, ", "))
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "  awaited = {"
  for _, a in ipairs(f.awaited or FIX.awaited) do out[#out + 1] = string.format("    { name = %q, min = %d, max = %d, new = true, conf = \"data\", kind = \"party\" },", a.name, a.min, a.max) end
  out[#out + 1] = "  },"
  out[#out + 1] = "  enchants = {"
  out[#out + 1] = "    [2] = { conf = \"data\", kinds = { \"4.0\" }, list = { { spell = 27001, name = \"Enchant Necklace - Agility\", ench = 2564 } } },"
  out[#out + 1] = "    [9] = { conf = \"beta\", kinds = { \"4.1\", \"4.2\", \"4.3\", \"4.4\" }, list = { { spell = 7418, name = \"Enchant Bracer - Minor Health\", ench = 41 }, { spell = 7428, name = \"Enchant Bracer - Minor Deflection\", ench = 924 } } },"
  out[#out + 1] = "    [16] = { conf = \"data\", kinds = { \"2.1\", \"2.7\" }, list = { { spell = 13529, name = \"Enchant 2H Weapon - Lesser Impact\", ench = 1897, kinds = { \"2.1\" } }, { spell = 7788, name = \"Enchant Weapon - Minor Striking\", ench = 250, kinds = { \"2.1\", \"2.7\" } } } },"
  out[#out + 1] = "    [17] = { conf = \"data\", kinds = { \"4.6\" }, list = { { spell = 13378, name = \"Enchant Shield - Minor Stamina\", ench = 848 } } },"
  out[#out + 1] = "  },"
  local xp, xc = {}, {}
  for l = 1, 59 do xp[l] = string.format("[%d] = %d", l, f.xp[l]); xc[l] = string.format("[%d] = %q", l, l <= 30 and "beta" or "data") end
  out[#out + 1] = "  xp = { " .. table.concat(xp, ", ") .. " },"
  out[#out + 1] = "  xpConf = { " .. table.concat(xc, ", ") .. " },"
  local fac = {}
  for id, name in pairs(FIX.factions) do fac[#fac + 1] = string.format("[%d] = { name = %q, conf = \"data\" }", id, name) end
  table.sort(fac)
  out[#out + 1] = "  factions = { " .. table.concat(fac, ", ") .. " },"
  out[#out + 1] = "}"
  return table.concat(out, "\n")
end
local FIXTURE = fixtureSource()
local REAL_KNOWN = HERE .. "/Cute/Known.lua"
-- the module addons a client can have besides Cute (o.modules names them): folders under tools/cute/test, never in the
-- zip, read as the client reads a toc
local MODULES_DIR = HERE .. "/test"
local function readToc(path)
  local toc = { fields = {}, deps = {}, files = {} }
  for line in assert(io.open(path)):read("*a"):gmatch("[^\r\n]+") do
    local key, value = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
    if key then toc.fields[key] = value
    elseif line:match("%.lua$") then toc.files[#toc.files + 1] = line end
  end
  for d in (toc.fields.Dependencies or ""):gmatch("[^,%s]+") do toc.deps[#toc.deps + 1] = d end
  return toc
end
-- every faction this client's data has, by id (GetFactionDataByID answers for these whether or not the character
-- has met them)
local FACTION_DB = { [69] = "Darnassus" }

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
  -- the loot window's slots, read for a boss's loot (Rules.lua rule 8): Forever's loot frame reads them, the toc loading
  -- it for every game type (Blizzard_UIPanels_Game.toc:127, [Family]\LootFrame.lua with no AllowLoadGameType; the
  -- camelot family is mainline, which the same toc's [ExcludeLoadGameType camelot] on mainline files shows, line 44)
  GetNumLootItems = "Blizzard_UIPanels_Game/Mainline/LootFrame.lua:227 (LootFrameMixin:Open)",
  GetLootSlotInfo = "Mainline/LootFrame.lua:228: texture, item, quantity, currencyID, itemQuality, ...",
  GetLootSlotLink = "Mainline/LootFrame.lua:69 and 515",
  -- whether this character may edit Guild Info, which the policy is saved to (Policy.lua P:SaveState)
  CanEditGuildInfo = "Blizzard_Communities/GuildInfo.lua:53 (CommunitiesGuildInfoFrame_UpdatePermissions: the Guild Info edit button by it)",
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
  -- (the clock: the server's, which every client online shares, so a client made later starts where the others are)
  local now = 1000
  for _, x in ipairs(clients) do if x.clock > now then now = x.clock end end
  local c = { env = env, o = o, name = o.name .. "-" .. ((o.surname and o.fullNameSurname) and o.surname or (o.realm or "Forever")), timers = {}, clock = now, frames = {}, sent = {}, chat = {},
              hooks = {}, C = {}, inGuild = o.inGuild ~= false, secret = false, throw = false, oversize = {}, dayShift = 0,
              showOffline = o.showOffline ~= false }
  c.sender = o.sender or (o.name .. "-" .. (o.realm or "Forever"))
  c.born = c.clock
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
    -- o.unitEventThrows: a client whose RegisterUnitEvent throws (Cute falls back to RegisterEvent and its unit check)
    if o.unitEventThrows then f.RegisterUnitEvent = function() error("RegisterUnitEvent is not available") end end
    c.frames[#c.frames + 1] = f
    return f
  end
  env.C_Timer = { After = function(sec, f) c.timers[#c.timers + 1] = { t = c.clock + sec, f = f } end }
  env.GetTime = function() return c.clock end
  env.time = function() return EPOCH + c.clock end
  -- (SystemTimeDocumentation.lua; the server's clock, the same for clients made together)
  env.GetServerTime = function() return EPOCH + c.clock end
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
  env.UnitGUID = api(function(unit)
    if unit == "player" then return o.guid end
    local i = type(unit) == "string" and unit:match("^party(%d)$")
    local name = i and (o.party or {})[tonumber(i)]
    local r = type(unit) == "string" and unit:match("^raid(%d+)$")
    if r then name = (o.raid or {})[tonumber(r)] end
    return name and guidOf(name) or nil
  end)
  -- the group: o.party names the party members (in a raid, the others of your five), o.raidGroup puts you in a raid
  -- (UnitInRaid gives your raid index) and o.raid names its members raid1 to raid40, you among them; IsInInstance
  -- follows the instance GetInstanceInfo says you are in
  env.UnitExists = api(function(unit)
    if unit == "player" then return true end
    local i = type(unit) == "string" and unit:match("^party(%d)$")
    return i ~= nil and (o.party or {})[tonumber(i)] ~= nil
  end)
  env.UnitInRaid = api(function(unit) if unit == "player" and (o.raidGroup or o.raid) then return 1 end return nil end)
  env.IsInInstance = api(function() local kind = o.instance or "none"; return kind ~= "none", kind end)
  -- o.lackSpells: recipes this client does not have (Rule 0 asks DoesSpellExist)
  env.C_Spell = { GetSpellName = api(function(id) return SPELL_NAME[id] end), DoesSpellExist = api(function(id) return not (o.lackSpells or {})[id] end) }
  -- the build (o.build, the fixture's by default) and the level cap (o.maxLevel, 60 by default; o.noCap: neither
  -- function reads)
  env.GetBuildInfo = api(function() local v, b = (o.build or FIX.build):match("^(.*)%.(%d+)$"); return v, b, "Oct 1 2026", 16001, v, "" end)
  env.GetMaxPlayerLevel = api(function() if o.noCap then return nil end return o.maxLevel or 60 end)
  env.GetMaxLevelForPlayerExpansion = api(function() if o.noCap then return nil end return o.maxLevel or 60 end)
  env.GetRealmName = api(function() return o.realm or "Forever" end)
  env.UnitClass = api(function() return o.class, o.class, CLASS_ID[o.class] end)
  env.GetNormalizedRealmName = api(function() return o.realm or "Forever" end)
  env.GetMoney = api(function() return o.money or 0 end)
  env.GetBindLocation = api(function() return o.hearth or "Goldshire" end)
  -- the worn items; o.invLate: the inventory has not arrived yet (nothing in any slot) until c.invReady, as it can come
  -- after the loading screen with UNIT_INVENTORY_CHANGED
  local function worn(slot) if o.invLate and not c.invReady then return nil end return (o.items or {})[slot] end
  c.worn = worn
  -- o.secretLinks: the link is a secret for every slot (the owner's client gave nothing readable for most); the item id
  -- and quality still read, as Forever's character sheet reads them
  env.GetInventoryItemLink = api(function(_, slot) if o.secretLinks and worn(slot) then return secret("string") end return worn(slot) end)
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
    GetInventoryItemID = api(function(_, slot) return linkId(worn(slot)) end),
    GetInventoryItemQuality = api(function(_, slot) local id = linkId(worn(slot)); return id and (id % 3) + 1 or nil end),
    GetInventoryItemDurability = api(function(slot) if worn(slot) then return o.dur or 80, 100 end end),
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
    -- c.lootWindow: the loot window open now, { { itemID, quality }, ... }
    GetNumLootItems = api(function() return #(c.lootWindow or {}) end),
    GetLootSlotLink = api(function(i) local it = (c.lootWindow or {})[i]; return it and ("|cff1eff00|Hitem:" .. it[1] .. ":0|h[Item]|h|r") or nil end),
    GetLootSlotInfo = api(function(i) local it = (c.lootWindow or {})[i]; if it then return 132, "Item " .. it[1], 1, it[3], it[2] or 3, false, false, nil, false, false end end),
    -- (o.canEditInfo says it for this character; else the roster's rank against INFO_EDIT)
    CanEditGuildInfo = api(function()
      if o.canEditInfo ~= nil then return o.canEditInfo end
      for _, m in ipairs(GUILD) do if m.guid == o.guid then return m.rank <= INFO_EDIT end end
      return false
    end),
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
  -- name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, ...
  env.GetInstanceInfo = api(function()
    local kind = o.instance or "none"
    return o.instName or (kind == "none" and "Eastern Kingdoms" or "Instance"), kind, 1, "Normal", 5, 0, false, o.instanceID or 0, 5, nil, false
  end)
  env.GetRealZoneText = api(function() return o.zone or "Elwynn Forest" end)
  env.NumTaxiNodes = api(function() return 5 end)
  env.TaxiNodeGetType = api(function(i) return i <= 3 and "REACHABLE" or "DISTANT" end)
  env.RequestTimePlayed = function() c.timers[#c.timers + 1] = { t = c.clock + 1, f = function() fire(c, "TIME_PLAYED_MSG", o.played or 36000, o.playedLevel or 3600) end } end
  env.IsInGuild = api(function() return c.inGuild end)
  env.C_Club = {
    GetGuildClubId = api(function() return c.inGuild and 7 or nil end),
    GetClubMembers = api(function(id) local out = {}; if id == 7 then for i = 1, #GUILD do out[i] = i end end return out end),
    -- (ClubDocumentation.lua: the club's memberCount, NeverSecret; c.memberCount stands in for a guild the list is
    -- still loading for)
    -- (c.noMemberCount: ClubInfo.memberCount is Nilable, and a client may give none)
    GetClubInfo = api(function(id) if id == 7 then return { clubId = 7, name = "Cute", clubType = 2, memberCount = (not c.noMemberCount) and (c.memberCount or #GUILD) or nil } end end),
    GetMemberInfo = api(function(id, i)
      local m = id == 7 and GUILD[i]
      if not m then return nil end
      -- (c.infoGaps: members whose info the client has not got yet, as at login: GetMemberInfo returns nothing)
      if c.infoGaps and c.infoGaps[i] then return nil end
      c.memberReads = (c.memberReads or 0) + 1
      -- (the server knows a character's level: a member whose client runs here is listed at the level it is)
      local level = m.level
      for _, x in ipairs(clients) do if x.o.guid == m.guid and type(x.o.level) == "number" then level = x.o.level end end
      return { name = m.name, guid = m.guid, memberId = i, presence = m.online ~= false and 1 or 3, guildRank = m.rankName or ("Rank " .. m.rank), guildRankOrder = m.rank + 1,
        level = level, classID = CLASS_ID[m.class], zone = m.zone or "Elwynn Forest", isSelf = m.guid == o.guid }
    end),
    GetMemberInfoForSelf = api(function(id)
      if id ~= 7 then return nil end
      for i, m in ipairs(GUILD) do if m.guid == o.guid then return c.env.C_Club.GetMemberInfo(7, i) end end
    end),
  }
  -- PlayerScriptDocumentation.lua: a GUID's class, race, sex, name and realm, or nothing for one the client does not
  -- know. A guild member's name here is its roster entry's guidName (what the live client gives is not known yet: a
  -- scenario says), nothing where it has none
  env.GetPlayerInfoByGUID = api(function(guid)
    for _, m in ipairs(GUILD) do
      if m.guid == guid and m.guidName then c.guidAsked = (c.guidAsked or 0) + 1; return m.class, m.class, "Human", "Human", 2, m.guidName, "" end
    end
    return nil
  end)
  env.C_CreatureInfo = { GetClassInfo = api(function(id) local file = CLASS_FILE[id]; if file then return { className = file, classFile = file, classID = id } end end) }
  -- Guild Info (GuildInfoDocumentation.lua): the guild's text (c.infoSecret: a secret, as inside an encounter), and
  -- SetInfoText, which only a character allowed to edit it calls, from a click (c.hardware), the client's 499 letters at
  -- most (Blizzard_Communities/GuildInfo.lua: the edit box's SetMaxLetters)
  env.C_GuildInfo = { CanSpeakInGuildChat = api(function() return c.mute ~= true end), GuildRoster = function() c.rosterAsked = (c.rosterAsked or 0) + 1; c.timers[#c.timers + 1] = { t = c.clock + 0.5, f = function() fire(c, "GUILD_ROSTER_UPDATE") end } end,
    GetInfoText = api(function()
      if c.infoSecret then return secret("string") end
      return INFO[c.env.C_Club.GetGuildClubId()] or ""
    end),
    SetInfoText = function(text)
      assert(c.hardware, "SetInfoText outside a click")
      assert(c.env.CanEditGuildInfo() == true, "SetInfoText by a character not allowed to edit Guild Info")
      local letters = 0
      for _ in tostring(text):gmatch("[^\128-\191]") do letters = letters + 1 end
      assert(type(text) == "string" and letters <= 499, "Guild Info over 499 letters: " .. letters)
      -- (c.infoDrop: the game takes the call and keeps nothing, as a server refusing it would)
      if c.infoDrop then return end
      INFO[c.env.C_Club.GetGuildClubId()] = text
      c.infoSets = (c.infoSets or 0) + 1
    end }
  -- your side (UnitDocumentation.lua): o.faction, Alliance by default; the Guide reads the seed's quests for it
  env.UnitFactionGroup = api(function(unit) if unit == "player" then local f = o.faction or "Alliance"; return f, f end return nil end)
  -- invites (PartyInfoDocumentation.lua; Blizzard_Communities' guild roster calls InviteUnit with a member's name):
  -- c.invites keeps who was invited; one in combat fails the scenario; o.cantInvite: in a group led by another
  c.invites = {}
  env.C_PartyInfo = {
    InviteUnit = function(name) assert(not c.combat, "an invite in combat"); c.invites[#c.invites + 1] = name end,
    CanInvite = api(function() return not o.cantInvite end),
  }
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
    GetItemSubClassInfo = api(function(class, sub) return SUBCLASS_NAME[class .. "." .. sub] or ("Subclass " .. sub), false end),
    GetItemCount = api(function(id) return (o.counts or {})[id] or 0 end),
    GetDetailedItemLevelInfo = api(function(link) if o.uncached then return nil end return 20 + (itemId(link) % 40) end),
    GetItemQualityByID = api(function(link) return (itemId(link) % 3) + 1 end),
    -- name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, texture, sellPrice, classID, subclassID
    GetItemInfo = api(function(link)
      local id = itemId(link)
      local cls = ITEM_CLASS[id] or (o.serverItems or {})[id] or { 15, 0 }
      return "Item " .. id, type(link) == "string" and link or ("item:" .. id), (id % 3) + 1, 20 + (id % 40), 1, "Misc", "Junk", 20, "", 0, (o.prices or {})[id] or 0, cls[1], cls[2]
    end),
    -- itemID, itemType, itemSubType, itemEquipLoc, icon, classID, subClassID; nothing for an item the client's data lacks
    GetItemInfoInstant = api(function(x)
      local id = itemId(x)
      -- (o.lackItems: items this client's data lacks altogether, as Rule 0 meets on a client other than the seed's)
      if (o.serverItems or {})[id] or (o.lackItems or {})[id] then return nil end
      local cls = ITEM_CLASS[id] or { 15, 0 }
      return id, "Type", "Subtype", "", 0, cls[1], cls[2]
    end),
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
  -- an aura: { name, spellId, sourceUnit, duration }
  env.C_UnitAuras = { GetAuraDataByIndex = api(function(_, i) local a = (o.auras or {})[i]; if a then return { name = a[1], spellId = a[2], sourceUnit = a[3], duration = a[4] or 0 } end end) }
  env.UnitIsUnit = api(function(a, b) return a == b end)
  -- the party is the guild unless o.strangers
  env.UnitIsInMyGuild = api(function(unit) return unit ~= "player" and type(unit) == "string" and unit:match("^party%d$") ~= nil and not o.strangers end)
  -- the reputation list (FACTIONS, or o.factions); o.folded: the headers are folded, so the list shows them alone
  local function factionRows()
    local out = {}
    for _, f in ipairs(o.factions or FACTIONS) do if not o.folded or f[7] then out[#out + 1] = f end end
    return out
  end
  local function factionData(f)
    local standing = ((o.standing or {})[f[1]]) or f[4]
    return { factionID = f[1], name = f[2], description = "", reaction = f[3], currentReactionThreshold = f[5], nextReactionThreshold = f[6], currentStanding = standing,
      atWarWith = false, canToggleAtWar = false, isChild = false, isHeader = f[7] or false, isHeaderWithRep = f[8] or false, isCollapsed = false, isWatched = false,
      hasBonusRepGain = false, canSetInactive = false, isAccountWide = false }
  end
  env.C_Reputation = {
    GetNumFactions = api(function() return #factionRows() end),
    GetFactionDataByIndex = api(function(i) local f = factionRows()[i]; return f and factionData(f) or nil end),
    -- (by id: the character's list, else any faction the client's data has, unless o.lackFactions says it lacks it)
    GetFactionDataByID = api(function(id)
      if (o.lackFactions or {})[id] then return nil end
      for _, f in ipairs(o.factions or FACTIONS) do if f[1] == id then return factionData(f) end end
      for _, f in ipairs(FACTIONS) do if f[1] == id then return factionData(f) end end
      if FACTION_DB[id] or o.allFactions then return factionData({ id, FACTION_DB[id] or ("Faction " .. id), 4, 0, 0, 3000 }) end
    end),
  }
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
  -- the chat lockdown (ChatInfoDocumentation.lua, RestrictedActionsDocumentation.lua): c.chatLocked holds addon chat
  -- back as a dungeon or an encounter does, every send answered 11; c.lock11 answers that many sends 11 while the
  -- functions say nothing (a lockdown the client does not report)
  env.C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return kind == 5 and c.chatLocked == true end }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) c.prefix = p; return c.prefixResult or 0 end,
    InChatMessagingLockdown = function() return c.chatLocked == true end,
    AreOutgoingAddonChatMessagesRestricted = function() return false end,
    -- GUILD, or a WHISPER to a target the channel names (a client's c.sender); a target no client online has is
    -- TargetOffline (12)
    SendAddonMessage = function(prefix, msg, channel, target)
      assert(prefix == "Cute" and (channel == "GUILD" or (channel == "WHISPER" and type(target) == "string")), "the Cute prefix on GUILD or a whisper with its target: " .. tostring(prefix) .. " " .. tostring(channel))
      if #msg > 255 then c.oversize[#c.oversize + 1] = msg; return 2 end
      local to
      if channel == "WHISPER" then
        for _, x in ipairs(clients) do if x.sender == target then to = x end end
        if not to then return 12 end
      end
      if c.chatLocked then c.lockedSends = (c.lockedSends or 0) + 1; return 11 end
      if c.lock11 and c.lock11 > 0 then c.lock11 = c.lock11 - 1; return 11 end
      if c.throttle and c.throttle > 0 then c.throttle = c.throttle - 1; return 3 end
      if c.fail and c.fail > 0 then c.fail = c.fail - 1; return 9 end
      -- (c.refuse: a result chosen per message, nil to send it: one kind refused while the rest go)
      if c.refuse then local r = c.refuse(msg, channel, target); if r then return r end end
      c.sent[#c.sent + 1] = { msg = msg, at = c.clock, channel = channel, target = target }
      BUS[#BUS + 1] = { from = c, prefix = prefix, msg = msg, channel = channel, to = to }
      return 0
    end,
    SendChatMessage = function(text, kind) if c.hooks.SendChatMessage then c.hooks.SendChatMessage(text, kind) end end,
  }
  -- o.withPerform: C_ChatInfo.PerformEmote (ChatInfoDocumentation.lua), what typed emotes call; DoEmote, where a client
  -- has both, its deprecated wrapper (Deprecated_ChatInfo.lua)
  if o.withPerform then
    env.C_ChatInfo.PerformEmote = function(token) if c.hooks.PerformEmote then c.hooks.PerformEmote(token) end return true end
    if o.withEmote then env.DoEmote = function(token) return env.C_ChatInfo.PerformEmote(token) end end
  end
  env.math = setmetatable({ random = function(a, b) if a and b then return a + (c.clock % (b - a + 1)) end return 0.5 end }, { __index = math })
  -- a client that lacks a function (o.without = { Name = true }): the global is gone, as on a client without it
  for name in pairs(o.without or {}) do env[name] = nil end

  -- the client's addon list (C_AddOns, Forever's AddOnsDocumentation.lua): Cute, then the module addons o.modules
  -- names (o.lod = { Name = false } makes one no LoadOnDemand addon). c.addonState is the game's AddOns list, per
  -- character, kept by the GUID as the mainline client's own code passes it (o.addonState: one account's, shared by
  -- the clients a scenario makes for it, as the game keeps it across logins); a module addon loads when asked
  -- (LoadAddOn) or, enabled and no LoadOnDemand one, at login after Cute (login below). Never in combat
  c.addonState, c.addonCalls = o.addonState or {}, {}
  local list = { { name = "Cute", toc = readToc(HERE .. "/Cute/Cute.toc"), loaded = true } }
  for _, name in ipairs(o.modules or {}) do
    -- (a folder under test/ first, else beside Cute/, where the build writes Cute_Quest)
    local dir = MODULES_DIR .. "/" .. name
    local probe = io.open(dir .. "/" .. name .. ".toc")
    if probe then probe:close() else dir = HERE .. "/" .. name end
    local a = { name = name, dir = dir, private = {} }
    a.toc = readToc(a.dir .. "/" .. name .. ".toc")
    a.lod = a.toc.fields.LoadOnDemand == "1"
    if (o.lod or {})[name] ~= nil then a.lod = o.lod[name] end
    list[#list + 1] = a
  end
  c.addons = list
  local function addon(x) if type(x) == "number" then return list[x] end for _, a in ipairs(list) do if a.name == x then return a end end end
  local function enabledFor(a, who) local st = c.addonState[a.name]; if st == nil or st[who] == nil then return true end return st[who] end
  c.addonEnabled = function(name) local a = addon(name); return a ~= nil and enabledFor(a, o.guid) end
  local function forMe(who) assert(who == o.guid, "the AddOns list is asked per character by GUID: " .. tostring(who)); return who end
  function c.loadAddon(a)
    for _, file in ipairs(a.toc.files) do
      local src = assert(io.open(a.dir .. "/" .. file)):read("*a")
      assert(not src:find("[\128-\255]"), a.name .. "/" .. file .. " has a byte the game's font would draw as a box")
      local fn = assert(loadstring(src, "@" .. a.name .. "/" .. file))
      setfenv(fn, env)
      fn(a.name, a.private)
    end
    a.loaded = true
    fire(c, "ADDON_LOADED", a.name, false)
  end
  env.C_AddOns = {
    GetNumAddOns = api(function() return #list end),
    GetAddOnInfo = api(function(x)
      local a = addon(x)
      if not a then error("AddOn index must be in the range of 1 to " .. #list) end
      local on = enabledFor(a, o.guid)
      return a.name, a.toc.fields.Title or a.name, a.toc.fields.Notes or "", on, on and (a.lod and not a.loaded and "DEMAND_LOADED" or "") or "DISABLED", "INSECURE"
    end),
    GetAddOnMetadata = api(function(x, field) local a = addon(x); return a and a.toc.fields[field] or nil end),
    GetAddOnDependencies = api(function(x) local a = addon(x); return unpack(a and a.toc.deps or {}) end),
    IsAddOnLoadOnDemand = api(function(x) local a = addon(x); return a and a.lod or false end),
    IsAddOnLoaded = api(function(x) local a = addon(x); local l = a and a.loaded or false; return l, l end),
    GetAddOnEnableState = api(function(x, who) forMe(who); local a = addon(x); return (a and enabledFor(a, who)) and 2 or 0 end),
    EnableAddOn = function(x, who) forMe(who); c.addonCalls[#c.addonCalls + 1] = "enable " .. x; c.addonState[x] = c.addonState[x] or {}; c.addonState[x][who] = true end,
    DisableAddOn = function(x, who) forMe(who); c.addonCalls[#c.addonCalls + 1] = "disable " .. x; c.addonState[x] = c.addonState[x] or {}; c.addonState[x][who] = false end,
    SaveAddOns = function() c.addonCalls[#c.addonCalls + 1] = "save" end,
    LoadAddOn = function(x)
      assert(not c.combat, "an addon loaded in combat")
      c.addonCalls[#c.addonCalls + 1] = "load " .. tostring(x)
      local a = addon(x)
      if not a then return false, "MISSING" end
      if a.loaded then return true end
      if not enabledFor(a, o.guid) then return false, "DISABLED" end
      c.loadAddon(a)
      return true
    end,
  }
  env.InCombatLockdown = function() return c.combat == true end
  -- o.quest: the quest engine's mocks (test/quest_mocks.lua), what Cute_Quest's copy of QuestBank reads that Cute's own
  -- mock lacks; after Cute's (the addon list among them), never over them
  if o.quest then dofile(HERE .. "/test/quest_mocks.lua")(env, c, o, newObj, api, secret) end

  -- load the addon, file by file, as the TOC lists them. Known.lua is the seed of the pass (the fixture, or none), or
  -- the one a client asks for: o.seed = "real" (the generated file), "fixture", false (none) or a source of its own
  local toc = io.open(HERE .. "/Cute/Cute.toc"):read("*a")
  for file in toc:gmatch("\n([%w_]+%.lua)") do
    local src
    if file == "Known.lua" then
      local seed = o.seed
      if seed == nil then seed = SEEDED and "fixture" or false end
      if seed == "fixture" then src = FIXTURE
      elseif seed == "real" then local f = io.open(REAL_KNOWN); src = f and f:read("*a"); if f then f:close() end
      elseif type(seed) == "string" then src = seed end
    else
      src = assert(io.open(HERE .. "/Cute/" .. file)):read("*a")
    end
    if src then
      assert(not src:find("[\128-\255]"), file .. " has a byte the game's font would draw as a box")
      local fn, err = loadstring(src, "@Cute/" .. file)
      assert(fn, err)
      setfenv(fn, env)
      fn("Cute", c.C)
    end
  end
  clients[#clients + 1] = c
  return c
end

local function login(c, db, reloading)
  c.env.CuteDB = db or {}
  fire(c, "ADDON_LOADED", "Cute")
  -- the module addons the game loads itself: enabled for this character and no LoadOnDemand ones, after Cute
  for _, a in ipairs(c.addons) do if not a.loaded and not a.lod and c.addonEnabled(a.name) then c.loadAddon(a) end end
  fire(c, "PLAYER_ENTERING_WORLD", not reloading, reloading or false)
  tick(c, 1) -- the roster arrives
end
local function leave(c) for i = #clients, 1, -1 do if clients[i] == c then table.remove(clients, i) end end end

-- a click is a hardware event on its client (c.hardware while it runs: SetInfoText takes one)
local function hardware(b, fn) local c = b.__client; if c then c.hardware = true end; fn(); if c then c.hardware = false end end
local function click(b) assert(b and b.__scripts.OnClick, "a button with OnClick"); b.__checked = not b.__checked; hardware(b, function() b.__scripts.OnClick(b, "LeftButton") end) end
local function press(b) assert(b and b.__scripts.OnClick, "a button with OnClick"); hardware(b, function() b.__scripts.OnClick(b, "LeftButton") end) end
local function hover(o) if o.__scripts.OnEnter then o.__scripts.OnEnter(o) end end
-- the Guide's page, switched on first where it is off (a fresh install starts without it: scenario 9 and the modules')
local function openGuide(c) if not c.C.Modules.OnKey("guide") then c.C.Modules.Set("guide", true) end c.C.UI:Open("guide") end
-- the Guide's band, line by line (the next best thing, where the knowledge comes from), and a line's tooltip
local function bandLine(c, i) local n = 0; for _, l in ipairs(c.C.UI.bandLines.items) do if l:IsShown() then n = n + 1; if n == i then return l end end end end
-- the Guide's head row: the pick's line, the first row of its list (its tooltip holds the reasons, the source and, for
-- an officer, the guild's line and what the guild learned)
local function guideHead(c) for _, r in ipairs(c.C.UI.lists.guide.items) do if r:IsShown() and r.idx == 1 then return r end end end
local function tipOf(o) local l0 = #lines; if o.__scripts.OnEnter then o.__scripts.OnEnter(o) end; return table.concat(lines, "\n", l0 + 1) end
-- a row's tooltip filler read into text, a double line as "left | right"
local function tipText(fill) local out = {}; fill({ AddLine = function(_, t) out[#out + 1] = t end, AddDoubleLine = function(_, l, r) out[#out + 1] = l .. " | " .. r end }); return table.concat(out, "\n") end
-- a dungeon in range's card as the Guide would draw it, whether or not it is the pick (G.Items draws the pick's rows
-- alone; G.CardRows any card's): its rows, the card and the plan
local function cardOf(c, name, officer)
  local _, plan = c.C.Guide.Items(officer)
  for _, card in ipairs(plan.cards) do if card.d.name == name then return c.C.Guide.CardRows(card, plan), card, plan end end
end
-- the tabs shown, left to right, and Settings' sections listed, top to bottom, by id
local function tabsShown(c)
  local out = {}
  for id, b in pairs(c.C.UI.tabs) do if b:IsShown() then out[#out + 1] = { id = id, x = b.__points[1].x } end end
  table.sort(out, function(a, b) return a.x < b.x end)
  for i, t in ipairs(out) do out[i] = t.id end
  return table.concat(out, " ")
end
local function sectionsShown(c)
  local out = {}
  for _, f in ipairs(c.frames) do if f.section and f:IsVisible() then out[#out + 1] = { id = f.section, y = f.__points[1].y } end end
  table.sort(out, function(a, b) return a.y > b.y end)
  for i, t in ipairs(out) do out[i] = t.id end
  return table.concat(out, " ")
end
local function msgs(c, kind) local n = 0; for _, m in ipairs(c.sent) do if m.msg:sub(1, 2) == kind then n = n + 1 end end return n end
-- the chat lines a client printed, the line of what is new in this version left out (Core.lua prints it ten seconds
-- after the first login on a version)
-- (what is new in this version, and a first run's welcome, left out)
local function chatLines(c)
  local out, news = {}, c.C.COLOR .. "Cute " .. c.C.version .. "|r: "
  for _, m in ipairs(c.chat) do if m:sub(1, #news) ~= news and not m:find("|r: /cute or the elf on the minimap opens the guild window.", 1, true) then out[#out + 1] = m end end
  return out
end
local function sameColor(a, b) return a and b and math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01 end
-- a shown row of the table, and a shown cell of a row, by the stat id
local function rowOf(c, short) for _, r in ipairs(c.C.UI.rows.items) do if r:IsShown() and r.row and r.row.short == short then return r end end end
local function cellOf(r, id) for _, cell in ipairs(r.cells) do if cell:IsShown() and cell.def and cell.def.id == id then return cell end end end
local function shownHeaders(c) local n = 0; for _, h in ipairs(c.C.UI.headerCells.items) do if h:IsShown() then n = n + 1 end end return n end
-- a check box (a CheckButton) or a check row (a Button holding its box as a visual, UI.lua checkRow) that is shown
local function checkBox(c, test) for _, fr in ipairs(c.frames) do if (fr.__kind == "CheckButton" or fr.checkRow) and fr:IsVisible() and test(fr) then return fr end end end
-- every text shown in a client's window, for a scenario that asks what is there (or never is)
local texts

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
-- what a widget is clipped to: every scrolling ancestor's view, intersected (a scroll frame inside another, as the
-- quest engine's journal list under Cute's scroll area, shows only what both let through)
local function clipOf(o)
  local clip
  for _, a in ipairs(ancestors(o)) do
    if a.__child then
      local cr = rectOf(a)
      if cr then clip = clip and { l = math.max(clip.l, cr.l), r = math.min(clip.r, cr.r), t = math.min(clip.t, cr.t), b = math.max(clip.b, cr.b) } or cr end
    end
  end
  return clip
end
local function checkLayout(root, label)
  GEN = GEN + 1
  local problems, texts = {}, {}
  local rootRect = rectOf(root)
  for _, o in everything() do
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
        local clip = clipOf(o)
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
        local clip = clipOf(o)
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
  for idx, o in everything() do
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
          local cr = clipOf(o)
          if cr then it.clip = { x = cr.l - rr.l, y = rr.t - cr.t, w = cr.r - cr.l, h = cr.t - cr.b } end
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
    items = { [1] = "item:1234:0", [5] = "item:1235:2", [7] = "item:1236:0", [16] = "item:1240:0" }, auras = { { "Power Word: Fortitude", 1243 }, { "Inner Fire", 588, "player", 600 } },
    bags = { [0] = { [1] = { link = "item:118", count = 5 }, [2] = { link = "item:4540", count = 10 }, [3] = { link = "item:13510", count = 1 }, [4] = { link = "item:2589", count = 20 } } },
    counts = { [5512] = 1 }, done = {}, log = { [4183] = 3 } }
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

function texts(c) local out = {}; for _, o in everything() do if o.__kind == "FontString" and o.__shown and o.__text ~= "" and visible(o) and o.__parent and o.__parent.__client == c then out[#out + 1] = o.__text end end return table.concat(out, "\n") end

makeGuild()
-- the two clients most scenarios share have the statistics API; scenario 17 makes clients without it
local yezin = newClient(charOf(NAMES[2], { withStats = true }))
local kaka = newClient(charOf(NAMES[4], { level = 37, xp = 120, money = 54321, zone = "Desolace", withStats = true }))
login(yezin)
login(kaka)
-- a policy's token, on the wire and in Guild Info: "+" Everyone, "-" Only you, the id's code (Policy.lua)
local function tok(id, vis) return (vis == "all" and "+" or "-") .. yezin.C.Policy.Code(id) end
-- Cute's line for a policy (a CuteDB.policy, its list and ranks), as an officer's save writes it: the policy itself in
-- it, or with full false its fingerprint alone
local function infoLine(policy, full, at)
  local P = yezin.C.Policy
  return P.LineText(at or EPOCH, policy.threshold or 1, P:Diff(policy), full ~= false)
end
-- an officer's Save to Guild Info, as the click in Settings makes it (Comm.lua M:SaveLine)
local function saveLine(c) c.hardware = true; local ok, why = c.C.Comm:SaveLine(); c.hardware = false; return ok, why end

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
  -- (a statistic the game shows as "--", never recorded, is nothing: Stats.lua S.Quantity)
  local never = {}
  for _, st in ipairs(yezin.stats) do if st[4] == "--" then never["g" .. st[2]] = true end end
  for _, def in ipairs(S.list) do
    if def.read and yezin.C.Sample:Value(def.id) == nil and not never[def.id] then nils[#nils + 1] = def.id .. (yezin.C.Sample:Error(def.id) and (" (" .. yezin.C.Sample:Error(def.id) .. ")") or "") end
  end
  assert(#nils == 0, "stats that read nil on the documented client: " .. table.concat(nils, ", "))
  assert(yezin.C.Sample:Value("spec") == "Arms" and yezin.C.Sample:Value("pvp_rank") == 0 and yezin.C.Sample:Value("cooking") == 60 and yezin.C.Sample:Value("first_aid") == 1
    and yezin.C.Sample:Value("prof1") == "Mining 150" and yezin.C.Sample:Value("mount") == false, "spec, PvP, skills and the mount read through the documented namespaces")
  -- Ready counts only the gaps the guild may see: with the defaults durability and potions, not the eleven empty slots
  -- the officers keep (in their own column); with Empty slots opened, the one gap reads as gaps
  assert(yezin.C.Sample:Value("ready") == 2 and S.ReadyCountsText() == "durability under 50% and no potions" and next(yezin.C.Sample:Value("empty_slots")),
    "readiness counts what everyone may see: " .. tostring(yezin.C.Sample:Value("ready")) .. ", " .. S.ReadyCountsText())
  do
    local db = yezin.env.CuteDB
    local saved = db.policy
    db.policy = { vis = { empty_slots = "all" } }
    yezin.C.Sample:Read("ready")
    assert(yezin.C.Sample:Value("ready") == 1 and yezin.C.UI.Format(S.byId.ready, 1) == "gaps" and S.ReadyCountsText() == "an empty slot, durability under 50% and no potions",
      "readiness: one gap (empty slots, opened) reads as gaps: " .. tostring(yezin.C.Sample:Value("ready")))
    db.policy = saved
    yezin.C.Sample:Read("ready")
  end
  -- no Everyone stat may rebuild an Only-you one (Stats.lua reveals, Policy.lua P:Route): with the defaults, and with
  -- each policy id closed alone and opened alone (every stat, the discovered categories, the game's), every stat or
  -- category that goes to the guild reveals only what goes there too, a hidden stat goes its stat's way, and Ready
  -- counts only what goes to the guild. Every id a stat reveals is one the policy knows
  do
    local P, db = yezin.C.Policy, yezin.env.CuteDB
    local ids, known = {}, {}
    for _, def in ipairs(S.list) do ids[#ids + 1] = def.id end
    for _, f in ipairs(S.FOUND) do ids[#ids + 1] = "gc_" .. f[1] end
    for _, c in ipairs(S.game.cats) do ids[#ids + 1] = "gc" .. c.id end
    for _, id in ipairs(ids) do known[id] = true end
    local declared = 0
    for _, id in ipairs(ids) do
      local def = S.byId[id]
      for _, r in ipairs((def and def.reveals) or S.CatReveals(id) or {}) do assert(known[r], id .. " reveals " .. r .. ", which no policy pair sets"); declared = declared + 1 end
    end
    assert(declared >= 15 and S.byId.enchanted.reveals and S.byId.ready.counts, "the registry declares what reveals what: " .. declared)
    -- (the walk below checks that routing follows the declarations; this list, kept apart from the registry, checks
    -- that the declarations are there: each edge the README names, a stat or category and what a member could work out
    -- from it. Taking one out of Stats.lua fails here)
    local MUST = { enchanted = { "unenchanted", "empty_slots" }, ilvl_slots = { "empty_slots", "old_gear" }, potions = { "consumed" },
      elixirs = { "consumed" }, flasks = { "consumed" }, food = { "consumed" }, bosses = { "gc_bosses" }, dungeons = { "gc_dungeons" },
      dungeons_seen = { "gc_dungeons" }, raids = { "gc_raids", "weekly_raids" }, weekly_raids = { "gc_raids" }, deaths = { "deaths_today", "deaths_lvl" },
      quests_done = { "quests_today" }, played = { "played_lvl" }, gc_bosses = { "bosses" }, gc_dungeons = { "dungeons", "dungeons_seen" },
      gc_raids = { "raids", "weekly_raids" }, xp_hour = { "to60", "xp_session" }, xp_session = { "xp_hour" }, to60 = { "xp_hour" } }
    for id, list in pairs(MUST) do
      local have = {}
      for _, r in ipairs((S.byId[id] and S.byId[id].reveals) or S.CatReveals(id) or {}) do have[r] = true end
      for _, r in ipairs(list) do assert(have[r], id .. " must say it reveals " .. r) end
    end
    assert(S.HIDDEN.ench_kinds.with == "enchanted" and S.HIDDEN.xpmax.with == "level", "the hidden stats ride with theirs")
    local function walk(label)
      for _, id in ipairs(ids) do
        if P:Route(id) == "all" then
          local def = S.byId[id]
          for _, r in ipairs((def and def.reveals) or S.CatReveals(id) or {}) do
            assert(P:Route(r) == "all", label .. ": " .. id .. " goes to the guild and reveals " .. r .. ", which goes to the officers")
          end
        end
      end
      for _, h in pairs(S.HIDDEN) do if h.with then assert(P:Route(h.id) == P:Route(h.with), label .. ": " .. h.id .. " goes " .. h.with .. "'s way") end end
      for id in pairs(S.ReadyCounts()) do assert(P:Route(id) == "all", label .. ": Ready counts " .. id .. ", which goes to the officers") end
    end
    local saved = db.policy
    db.policy = { vis = {} }
    walk("the defaults")
    assert(P:Route("enchanted") == "self" and P:Route("ench_kinds") == "self" and P:KeptWith("enchanted") == "unenchanted" and P:Route("ilvl_slots") == "self",
      "with the defaults Enchanted slots and the kinds riding with it go to the officers, kept with Missing enchants")
    for _, id in ipairs(ids) do
      db.policy = { vis = { [id] = "self" } }; walk(id .. " closed")
      db.policy = { vis = { [id] = "all" } }; walk(id .. " opened")
    end
    db.policy = { vis = { unenchanted = "all" } }
    assert(P:Route("enchanted") == "self" and P:KeptWith("enchanted") == "empty_slots", "Missing enchants opened alone: Enchanted slots still kept, with Empty slots")
    db.policy = { vis = { unenchanted = "all", empty_slots = "all" } }
    assert(P:Route("enchanted") == "all" and P:Route("ench_kinds") == "all", "both opened: Enchanted slots goes to the guild")
    db.policy = saved
  end
  -- every stat the officers can set has its code for life, two letters (a module's goes by "_" and its id), none twice,
  -- and the discovered categories theirs; a statistics category goes by its number. FNV-1a as published, and Guild
  -- Info's line read back as written, the policy in it; one with its fingerprint alone (0.6.0's first builds wrote such
  -- a line where the guild's text left no room) is a line nobody can read, so no policy is taken by its fingerprint
  do
    local seen, P = {}, yezin.C.Policy
    for _, def in ipairs(S.list) do
      if def.cat ~= "game" and def.cat ~= "found" then
        assert(type(def.code) == "string" and def.code:match("^%l[%l%d]$") and not seen[def.code], "a code for life: " .. def.id .. " " .. tostring(def.code))
        seen[def.code] = def.id
        assert(S.byCode[def.code] == def.id and P.Code(def.id) == def.code, "the code names its stat: " .. def.id)
      end
    end
    for _, f in ipairs(S.FOUND) do assert(f[3] and not seen[f[3]] and S.byCode[f[3]] == "gc_" .. f[1], "a discovered category's code: " .. f[1]); seen[f[3]] = f[1] end
    assert(P.Code("gc130") == "130", "a statistics category by its number")
    assert(P.Fnv("", 2166136261) == 0x811c9dc5 and P.Fnv("a", 2166136261) == 0xe40c292c and P.Fnv("foobar", 2166136261) == 0xbf9cf968, "FNV-1a, 32 bits")
    local pol = { vis = { gold = "all", zone = "self", gc130 = "self", unenchanted = "self", gc_bosses = "all" }, threshold = 2 }
    assert(P:Diff(pol) == "-130+go-zo", "what differs from the defaults, by code: " .. P:Diff(pol))
    local full, short = P.ParseLine("Our raids: Tue 20:00\n" .. infoLine(pol)), P.ParseLine(infoLine(pol, false) .. "\n")
    assert(full and full.diff == "-130+go-zo" and full.thr == 2 and full.fp == P:Fp(pol) and short and short.fp == nil and short.diff == nil and not short.newer,
      "the line read back: " .. infoLine(pol))
    local defaults = P.ParseLine(infoLine({ vis = {}, threshold = 1 }, false))
    assert(defaults and defaults.diff == "" and defaults.fp == P:Fp({ vis = {}, threshold = 1 }), "the defaults' line carries nothing and reads")
    assert(#P:Fp(pol) == 16 and P:Fp(pol) ~= P:Fp({ vis = { gold = "all", zone = "self", gc130 = "self" }, threshold = 1 }), "the ranks are in the fingerprint")
    assert(P.ParseLine("Cute 1 rule: be nice") == nil and P.ParseLine("Cute 2 k8z2qa 1 0123456789abcdef +go").newer, "the guild's own line is no line; a newer Cute's is one")
  end
  assert(yezin.C.Sample:Value("gold") == 123456 and yezin.C.UI.Format(S.byId.gold, 123456) == "12g" and S.FmtGold(9500) == "95s" and S.FmtGold(7) == "7c", "gold keeps copper and shows gold")
  assert(yezin.C.Sample:Value("resist_fire") == 0, "resists read")
  -- the XP left to 60 runs over the curve the guild learns (Rules.lua rule 6): the seed's where members have not agreed
  -- on a level, else the members' own UnitXPMax (here everyone's 1000), the levels nobody reported estimated
  local XPLeft, curve = yezin.C.Sample.XPLeft, yezin.C.Rules.XPCurve()
  assert(XPLeft(59, 0, 171800) == 171800 and XPLeft(60, 0, 1) == 0, "the last level's rest, and nothing past 60")
  if SEEDED then
    assert(XPLeft(58, 165700, 165800) == 100 + FIX.xp[59] and curve[59].state == "data" and curve[20].state == "beta" and curve[42].v == FIX.xp[42],
      "the seed's curve where the members have not agreed: " .. tostring(curve[59].v) .. " " .. tostring(curve[59].state))
  else
    -- (no seed, and only your own level reported so far: one member's word is no curve, so the levels ahead wait for the
    -- guild's, and so does hours to 60)
    assert(curve[42] == nil and curve[59] == nil and XPLeft(58, 165700, 165800) == nil,
      "no seed: one member's XP is no curve yet: " .. tostring(curve[42] and curve[42].state))
  end
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
  print(string.format("registry: %d stats (leveling %d, prog %d, funny %d, officer %d, statistics %d from the client, %d discovered at login), every read stat has a value on the documented client; undocumented globals mocked on evidence: %s",
    #S.list, counts.leveling, counts.prog, counts.funny, counts.officer, counts.game, #S.byCat.found, table.concat(undoc, ", ")))
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
  assert(bare.C.Sample:Value("ready") == 2, "readiness still reads without the durability input (the potions are there): " .. tostring(bare.C.Sample:Value("ready")))
  local noted = 0
  for _, e in ipairs(bare.env.CuteDB.errors) do if e.msg == "GetInventoryItemDurability is missing on this client" then noted = noted + e.count end end
  assert(noted == 1 and #chatLines(bare) == 0, "noted once for /cute errors, no chat line: " .. noted)
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
  -- (0.4.0: a client's own text survives the wire whole, accents included, where 0.3.x dropped every byte over 127;
  -- a byte that is no UTF-8, a control character and a sequence cut short still go)
  assert(M.Decode(S.byId.zone, "A\195\169B\1C") == "A\195\169BC", "text in keeps UTF-8 and loses control characters")
  assert(M.Decode(S.byId.zone, "A\233B\195") == "AB" and M.Encode(S.byId.zone, "For\195\170t d'Elwynn") == "For\195\170t d'Elwynn", "a stray byte goes; an accent travels")
  assert(M.Encode(S.byId.zone, string.rep("\195\169", 20)) == string.rep("\195\169", 12), "cut at 24 bytes without splitting a character")
  assert(M.Decode(S.byId.lc_cats, "12a") == nil and M.Decode(S.byId.lc_cats, "2") == "2", "pips in are digits only")
  assert(M.Decode(S.byId.empty_slots, "-5") == nil and M.Decode(S.byId.level, "zzzzzzzzzzzz") == nil, "lists and ints in are bounded")
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
  -- the hello, the full record, and the full record again in answer to Kaka's hello: no deltas. Yezin is an officer:
  -- with Kaka's enchanted chest beside her own, her client has learned the chest takes one, which Kaka's client hears
  -- of no member with the defaults, so she says so once (the officers' word, 1N); holding no policy, and the guild no
  -- line in Guild Info, she sends none
  local kinds = {}
  for _, m in ipairs(yezin.sent) do kinds[#kinds + 1] = m.msg:sub(1, 2) end
  assert(msgs(yezin, "1D") == 0 and msgs(yezin, "1N") == 1 and msgs(yezin, "1P") == 0 and #yezin.sent <= 3 + 2 * fulls,
    "a quiet client sends nothing beyond the hello, its answers and the officers' word: " .. #yezin.sent .. " messages in 45 s: " .. table.concat(kinds, " "))
  assert(kaka.C.Stats.WordEnchant(5) and kaka.C.Stats.EnchantSeen(5) == 0 and not kaka.env.CuteDB.roster["Yezin-Forever"].stats.enchanted,
    "Kaka's client learned the chest from the officers' word, from no member's enchants")
  local e = kaka.env.CuteDB.roster["Yezin-Forever"]
  assert(e and e.stats.level == 42 and e.stats.zone == "Duskwood", "Kaka's roster holds Yezin's level and zone")
  local e2 = yezin.env.CuteDB.roster["Kaka-Forever"]
  assert(e2 and e2.stats.level == 37 and e2.stats.gold == 54321, "Yezin's roster holds Kaka's level and gold (in copper)")
  assert(e2.stats.enchanted and e2.stats.enchanted[5] == true and e2.stats.enchanted[1] == nil and e2.stats.empty_slots[2] == true, "lists arrive as sets")
  -- one message a second from each
  local last
  for _, m in ipairs(yezin.sent) do if last then assert(m.at - last >= 1 - 1e-9, "one message a second: " .. (m.at - last)) end last = m.at end
  -- every message came back to its sender too, as the game hands it back: neither keeps a record of itself
  assert(not yezin.env.CuteDB.roster[yezin.sender] and not kaka.env.CuteDB.roster[kaka.sender], "no client keeps its own messages as a member's record")
  -- (and the ask the stamp of the officers' word the asker holds, none yet, 0, and the fingerprint of the policy it
  -- routes by, the defaults')
  assert(yezin.sent[1].msg == "1R|" .. yezin.o.guid .. "|0|0|" .. yezin.C.Policy:Fp() and e.stats.guid == yezin.o.guid, "the ask and the full record carry the sender's GUID: " .. yezin.sent[1].msg)
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
  local flushed, statPasses, labels = 0, 0, 0
  for i = before + 1, #kaka.sent do
    if kaka.sent[i].msg:find("g2001=", 1, true) then statPasses = statPasses + 1
    elseif kaka.sent[i].msg:sub(1, 2) == "1L" then labels = labels + 1
    else flushed = flushed + 1 end
  end
  assert(flushed >= 1 and flushed <= 3, "a quiet client sends only its flushes in five minutes: " .. flushed)
  -- (the answer to Yezin's hello goes first; the own pass then finds nothing left unsent, values or labels)
  assert(statPasses >= 1 and statPasses <= 2, "the statistics went in answer to the hello, and of their own accord only what was left: " .. statPasses)
  assert(labels == 1, "the labels of Kaka's factions went once, after the statistics: " .. labels)
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
  kaka.C.Policy:Receive("Yezin-Forever", at - 10, 1, tok("gold", "self"))
  assert(kaka.C.Policy:Vis("gold") == "all", "older policies are ignored")
  -- a policy that lands before the roster is known waits for the ranks, then applies
  local early = newClient(charOf(NAMES[13]))
  early.env.CuteDB = {}
  fire(early, "ADDON_LOADED", "Cute")
  assert(not early.C.Roster.trusted, "no roster yet")
  local h = early.C.Policy:Receive("Yezin-Forever", at + 5, 1, tok("gold", "all") .. ";" .. tok("deaths", "self"))
  assert(type(h) == "table" and early.C.Policy:Vis("deaths") == "all", "kept, not applied")
  fire(early, "PLAYER_ENTERING_WORLD", true, false)
  -- (Guild Info empty, and never read here: taken as no line from a read eleven seconds after an ask made since the
  -- first read: the ask ten seconds on, and the one twelve seconds after it)
  tick(early, 24)
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
  -- Kaka leaves the guild: gone after two roster reads a minute apart (two in a row seconds apart are one miss)
  local saved = GUILD[4]
  table.remove(GUILD, 4)
  fire(yezin, "GUILD_ROSTER_UPDATE")
  assert(yezin.env.CuteDB.roster["Kaka-Forever"], "one miss keeps the record")
  fire(yezin, "GUILD_ROSTER_UPDATE")
  assert(yezin.env.CuteDB.roster["Kaka-Forever"], "a second read seconds on is the same miss")
  tickAll(61)
  fire(yezin, "GUILD_ROSTER_UPDATE")
  assert(not yezin.env.CuteDB.roster["Kaka-Forever"], "two misses a minute apart prune it")
  table.insert(GUILD, 4, saved)
  fire(yezin, "GUILD_ROSTER_UPDATE")
  kaka.C.Comm:Full()
  tickAll(12)
  assert(yezin.env.CuteDB.roster["Kaka-Forever"], "back after Kaka sends again")
  -- a client with the older roster API, its guild window hiding offline members: a partial list prunes nobody
  print("roster: you first, online and class from the guild through C_Club, no-addon members listed, prune after two misses")
end

-- 9: the window, every page, for the officer and the member; the look. A fresh install is the dashboard alone: the
-- Guide is a module, off until its box in Settings > Modules is ticked, which brings its tab and its section at once
do
  for _, c in ipairs({ yezin, kaka }) do c.C.UI:Open("race") end
  assert(tabsShown(yezin) == "race prog shame game officers me settings", "the officer's fresh install, the dashboard alone: " .. tabsShown(yezin))
  assert(tabsShown(kaka) == "race prog shame game me settings", "the member's: " .. tabsShown(kaka))
  yezin.C.UI:Open("guide")
  assert(yezin.C.UI.page == "race", "the Guide off: asking for its page opens Race")
  -- /cute guide while it is off switches it on for this character, as its box would, says so and opens its page
  -- (0.6.1: a second way to the box); /cute modules lists each module, on or off, and opens Settings there
  local c0 = #yezin.chat
  yezin.env.SlashCmdList.CUTE("guide")
  assert(yezin.C.UI.page == "guide" and yezin.C.Char().modules.guide == true and yezin.C.Modules.byId.guide.active
    and table.concat(yezin.chat, "\n", c0 + 1):find("Guide is on for this character; untick it in Settings, Modules to switch it off.", 1, true),
    "/cute guide while it is off: " .. table.concat(yezin.chat, "\n", c0 + 1))
  assert(tabsShown(yezin):find("^race guide prog"), "its tab after Race: " .. tabsShown(yezin))
  -- the page as 0.7.0 draws it: the band says the quest module is off (one line; a click opens Settings > Modules), the
  -- list is the pick's line and the picked dungeon alone, the rest in the head's tooltip
  do
    local t = texts(yezin)
    local _, plan = yezin.C.Guide.Items(true)
    assert(t:find("Tick Quests in Settings, Modules for the step now.", 1, true), "the band says the quest module is off:\n" .. t)
    -- (with the seed the pick is a dungeon and its card follows; with none nothing is known at 42 and the head stands alone)
    assert(t:find(plan.next.line, 1, true) and (not plan.next.card or (t:find("Bosses", 1, true) and t:find("Online", 1, true))), "the pick's line, then its card: name, bosses, mates:\n" .. t)
    assert(not t:find("Missing enchants", 1, true) and not t:find("Next up", 1, true) and not t:find("Pace", 1, true) and not t:find("Learned in play", 1, true)
      and not t:find("In range at level", 1, true) and not t:find("The guild, per dungeon", 1, true), "nothing else on the page:\n" .. t)
    local n = 0
    for _, r in ipairs(yezin.C.UI.lists.guide.items) do if r:IsShown() and r.bar:IsShown() then n = n + 1 end end
    assert(n == (plan.next.card and 1 or 0), "one card, marked, or none: " .. n)
    -- G.Items works out what the page draws alone: the pick's card's rows (none where nothing fits), nothing of
    -- 0.6.0's page (the other cards' rows, the gear and pace strips, Next up, the officers' lines)
    local items = yezin.C.Guide.Items(true)
    assert(#items == (plan.next.card and #yezin.C.Guide.CardRows(plan.next.card, plan) or 0), "the items are the pick's card's rows alone: " .. #items)
    for _, it in ipairs(items) do assert(it.kind == "card" or it.kind == "bosses" or it.kind == "quests" or it.kind == "mate" or it.kind == "more", "no row of another kind: " .. tostring(it.kind)) end
    assert(type(plan.learned) == "table" and plan.learned[1] and (plan.cards[1] == nil or plan.cards[1].known ~= nil), "the plan: the learned lines for the officer, every dungeon in range with its counts")
    -- the module's notes say what this page is (its box's tooltip in Settings, Modules; the page's mock says the same),
    -- not 0.6.0's page of every dungeon, the gear and pace strips and Next up
    local notes = "The step now from Quests, then the one dungeon to run: its bosses, quests and guild mates to invite; officers see the guild per dungeon in its tooltip."
    assert(yezin.C.Modules.byId.guide.notes == notes, "the Guide's notes: " .. tostring(yezin.C.Modules.byId.guide.notes))
    yezin.C.UI:Open("settings", "modules")
    local box = checkBox(yezin, function(cb) return cb.label and cb.label:GetText() == "Guide" end)
    assert(tipOf(box):find(notes, 1, true), "its box's tooltip says so:\n" .. tipOf(box))
    local mock = assert(io.open(HERE .. "/../../addons/cute/index.html")):read("*a")
    assert(mock:find('GUIDE_NOTES = "' .. notes .. '"', 1, true), "the page's mock says the same")
    yezin.C.UI:Open("guide")
    local head = guideHead(yezin)
    -- (the guild's line at the right where the column holds it whole; else, never cut, on a line of its own under the
    -- head, the head's right empty)
    local who = head and head.who:IsShown() and head.who:GetText() or ""
    local under
    for _, r in ipairs(yezin.C.UI.lists.guide.items) do if r:IsShown() and r.idx == 2 then under = r.name:GetText() end end
    assert(head and head.name:GetText() == plan.next.line and (who == plan.guild.line or (who == "" and under == plan.guild.line)),
      "the officer's head: the pick's line, the guild's line whole at its right or on the line under it: " .. who .. " / " .. tostring(under))
    assert(not t:find("%.%.%.\n") or not t:find(plan.guild.line:sub(1, 12), 1, true) or t:find(plan.guild.line, 1, true), "the guild's line never cut")
    local ht = tipOf(head)
    assert(ht:find("Learned in play", 1, true) and ht:find(SEEDED and "From research" or "Nothing shipped with this copy", 1, true) and ht:find(plan.guild.line, 1, true),
      "the head's tooltip: the reasons, the source, the guild's line, what the guild learned:\n" .. ht)
    press(bandLine(yezin, 1))
    assert(yezin.C.UI.page == "settings" and yezin.C.UI.section == "modules", "a click on the band's line opens Settings > Modules")
    yezin.C.UI:Open("guide")
  end
  c0 = #yezin.chat
  yezin.env.SlashCmdList.CUTE("modules")
  assert(yezin.C.UI.page == "settings" and yezin.C.UI.section == "modules" and yezin.chat[#yezin.chat]:find("modules: Guide on. The dashboard's pages are always on.", 1, true),
    "/cute modules lists the Guide on and opens Settings there: " .. table.concat(yezin.chat, "\n", c0 + 1))
  yezin.C.Modules.Set("guide", false)
  assert(yezin.chat[#yezin.chat] == yezin.chat[c0 + 1], "switched off by the box, nothing said")
  yezin.env.SlashCmdList.CUTE("modules")
  assert(yezin.chat[#yezin.chat]:find("modules: Guide off. The dashboard's pages are always on.", 1, true), "/cute modules lists it off: " .. yezin.chat[#yezin.chat])
  yezin.C.UI:Open("settings", "modules")
  assert(sectionsShown(yezin) == "general vis rules modules race prog shame officers", "the officer's sections: " .. sectionsShown(yezin))
  check(yezin.C.UI.frame, "officer settings, modules, a fresh install")
  -- /cute <page>: a page by its module's id or title; an officer's page asked for by a member, and a word that is no
  -- page or command, say so and open nothing
  for _, d in ipairs({ { "statistics", "game" }, { "Hall of Shame", "shame" }, { "shame", "shame" }, { "me", "me" }, { "race", "race" } }) do
    kaka.env.SlashCmdList.CUTE(d[1])
    assert(kaka.C.UI.page == d[2], "/cute " .. d[1] .. " opens " .. d[2])
  end
  local k0 = #kaka.chat
  kaka.env.SlashCmdList.CUTE("officers")
  kaka.env.SlashCmdList.CUTE("banana")
  local said = table.concat(kaka.chat, "\n", k0 + 1)
  assert(kaka.C.UI.page == "race" and kaka.C.UI.frame:IsShown() and said:find("the Officers page is for officer ranks.", 1, true) and said:find('no page or command "banana". /cute help lists them.', 1, true),
    "the member's /cute officers and /cute banana:\n" .. said)
  for _, c in ipairs({ yezin, kaka }) do
    c.C.UI:Open("settings", "modules")
    local box = checkBox(c, function(cb) return cb.label and cb.label:GetText() == "Guide" end)
    assert(box and not box:GetChecked() and not box.__disabled, "the Guide's box, unticked on a fresh install")
    click(box)
    assert(c.C.UI.page == "settings" and tabsShown(c):find("^race guide prog") and c.C.Char().modules.guide == true, "ticked: its tab after Race at once, kept for this character: " .. tabsShown(c))
    assert(sectionsShown(c):find("modules race guide prog shame", 1, true), "and its section: " .. sectionsShown(c))
  end
  assert(tabsShown(kaka) == "race guide prog shame game me settings", "the member's tabs with the Guide: " .. tabsShown(kaka))
  -- the Guide's section: the two thresholds only it reads, greyed for the member
  yezin.C.UI:Open("settings", "guide")
  assert(texts(yezin):find("Members near your level", 1, true) and texts(yezin):find("Dungeons ahead", 1, true), "the Guide's section:\n" .. texts(yezin))
  check(yezin.C.UI.frame, "officer settings, the Guide's section")
  kaka.C.UI:Open("settings", "guide")
  local steps = 0
  for _, b in ipairs(kaka.frames) do if b.__kind == "Button" and b:IsVisible() and b.label and (b.label:GetText() == "-" or b.label:GetText() == "+") then steps = steps + 1; assert(b.__disabled, "a member's step is greyed") end end
  assert(steps == 4, "two thresholds, a step down and up each: " .. steps)
  check(kaka.C.UI.frame, "member settings, the Guide's section")
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
  local f = pages(yezin, "officer", { "race", "guide", "prog", "shame", "game", "officers", "me", "settings" })
  assert(yezin.C.UI.tabs.officers:IsShown(), "the officer sees the Officers tab")
  pages(kaka, "member", { "race", "guide", "prog", "shame", "game", "me", "settings" })
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
  -- the default columns fit the window at 1040 wide: every one shown, no "do not fit" line (Prog's eleven, the
  -- Officers' with what members met in play beside the officers' own)
  local fit = {}
  for _, page in ipairs({ "prog", "officers" }) do
    yezin.C.UI:Open(page)
    local used, room = 0, yezin.C.UI.scroll:Width() - 150 - 8
    for _, h in ipairs(yezin.C.UI.headerCells.items) do if h:IsShown() and h.def then used = used + h:GetWidth() end end
    assert(shownHeaders(yezin) - 1 == #yezin.C.UI.DEFAULT_COLS[page] and not texts(yezin):find("do not fit", 1, true),
      page .. ": every default column shown at 1040 wide: " .. (shownHeaders(yezin) - 1) .. " of " .. #yezin.C.UI.DEFAULT_COLS[page])
    fit[#fit + 1] = string.format("%s %d columns in %d of %d px", page, shownHeaders(yezin) - 1, used, room)
  end
  -- readiness on the prog page: a verdict in colour, what it counts in the tooltip. With the defaults it counts
  -- durability and potions, so Yezin's empty slots, which the officers keep, leave her ready; an officer is told they
  -- are in their own column
  yezin.C.UI:Open("prog")
  local readyCell = cellOf(rowOf(yezin, "Yezin"), "ready")
  assert(readyCell and readyCell.label:GetText() == "ready" and sameColor(readyCell.label.__color, yezin.C.UI.COLORS.GOOD), "readiness shows ready in green: " .. tostring(readyCell and readyCell.label:GetText()))
  local n0 = #lines
  hover(readyCell)
  local tip = table.concat(lines, "\n", n0 + 1)
  assert(tip:find("No gaps.", 1, true) and tip:find("Counts durability under 50% and no potions.", 1, true) and tip:find("in their own columns", 1, true), "the tooltip says what it counts: " .. tip)
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
  for _, page in ipairs({ "race", "guide", "prog", "shame", "game", "officers", "me", "settings" }) do
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
  print("window: every page opens for both views at both sizes, the look holds, self-only cells hidden from the member, sorting, scrolling and resizing hold; at 1040 wide " .. table.concat(fit, ", "))
end

-- 10: settings: a member cannot flip visibility; an officer's click plus Broadcast reaches the member; boxes follow clicks
do
  kaka.C.UI:Open("settings", "vis")
  local flipped = checkBox(kaka, function(cb) return cb.__disabled and cb.statId ~= nil end)
  assert(flipped, "the member's visibility boxes are disabled")
  local before = kaka.C.Policy:Vis("level")
  -- even a click on a disabled box (a macro could) changes nothing
  click(flipped)
  assert(kaka.C.Policy:Vis("level") == before, "a member's click changes no policy")
  -- the officer clicks Level to only-you in Settings and broadcasts
  yezin.C.UI:Open("settings", "vis")
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
  -- a stat kept with another: Enchanted slots, which the officers leave to Everyone, would tell members Missing
  -- enchants, which they keep. Its pair shows Only you, greyed for the officer too, with the one it goes with and why
  -- in the tooltip; a click changes nothing. Once the officers open Missing enchants and Empty slots it is theirs to
  -- set again, Everyone as they left it
  local ench = checkBox(yezin, function(cb) return cb.statId == "enchanted" and cb.vis == "self" end)
  assert(ench and ench:GetChecked() and ench.__disabled and texts(yezin):find("Enchanted slots  |cff8a8a8awith Missing enchants|r", 1, true),
    "Enchanted slots shows Only you, greyed, with Missing enchants")
  local said = tipOf(ench)
  assert(said:find("Kept to the officers while Missing enchants is: a member could work it out from this.", 1, true), "its tooltip says why:\n" .. said)
  click(checkBox(yezin, function(cb) return cb.statId == "enchanted" and cb.vis == "all" end))
  assert(yezin.C.Policy:Vis("enchanted") == "all" and yezin.C.Policy:Route("enchanted") == "self", "a click on a kept pair changes nothing")
  check(yezin.C.UI.frame, "officer settings, a stat kept with another")
  local vis = yezin.env.CuteDB.policy.vis
  local keep = { unenchanted = vis.unenchanted, empty_slots = vis.empty_slots }
  vis.unenchanted, vis.empty_slots = "all", "all"
  yezin.C.UI:Draw()
  local open = checkBox(yezin, function(cb) return cb.statId == "enchanted" and cb.vis == "all" end)
  assert(open and open:GetChecked() and not open.__disabled and not texts(yezin):find("with Missing enchants", 1, true), "the gaps opened: Enchanted slots is the officers' to set, Everyone")
  vis.unenchanted, vis.empty_slots = keep.unenchanted, keep.empty_slots
  yezin.C.UI:Draw()
  -- the Minimap button box: its fill follows the click and the button goes with it
  yezin.C.UI:Open("settings", "general")
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
  yezin.C.UI:Open("settings", "general")
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
    for _, page in ipairs({ "race", "guide", "prog", "shame", "game", "officers" }) do
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
  assert(lone.C.Comm.hello and msgs(lone, "1R") == 1 and msgs(lone, "1F") >= 1 and lone.sent[1].msg:sub(1, #lone.o.guid + 4) == "1R|" .. lone.o.guid .. "|", "the hello on joining, the ask first: " .. tostring(lone.sent[1] and lone.sent[1].msg))
  -- (the level-up came while her record waited for the policy, so it went with the record: no delta before it)
  local firstD, firstF
  for i, m in ipairs(lone.sent) do local k = m.msg:sub(1, 2); if k == "1D" and not firstD then firstD = i end; if k == "1F" and not firstF then firstF = i end end
  assert(firstF and (not firstD or firstD > firstF), "no delta before the record after the hello")
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
  if SEEDED then
    assert(S:Value("to60") == math.floor(left / rate + 0.5) and S:Value("to60") > 0, "hours to 60 from the levels ahead: " .. tostring(S:Value("to60")))
  else
    -- (no seed and nobody else heard from: this character's own two levels are one member's word, no curve, so hours
    -- to 60 waits for the guild's and shows a dash)
    assert(left == nil and S:Value("to60") == 0 and c.C.UI.Format(c.C.Stats.byId.to60, 0) == "-", "no seed, no guild: hours to 60 waits: " .. tostring(S:Value("to60")))
  end
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
  -- the consumables by the game's item classes, one scan of the bags for them all: two stacks of potions, an elixir, a
  -- flask, food and drink, bandages; a healthstone (Generic), cloth and a grey count as none of them; an item the
  -- client's own data lacks (a server-sent one) is placed by C_Item.GetItemInfo's class and subclass. (0.4.0: these
  -- replace 0.3.x's Classic item ids, Major Healing Potion and the like, which Forever may never drop)
  c.o.serverItems = { [990001] = { 0, 1 } }
  c.o.bags = { [0] = { [1] = { link = "item:118", count = 5 }, [2] = { link = "item:858", count = 3 }, [3] = { link = "item:2454", count = 2 }, [4] = { link = "item:13510", count = 1 },
    [5] = { link = "item:4540", count = 10 }, [6] = { link = "item:159", count = 4 } },
    [1] = { [1] = { link = "item:1251", count = 8 }, [2] = { link = "item:5512", count = 1 }, [3] = { link = "item:2589", count = 20 }, [4] = { link = "item:5000", count = 3, quality = 0 },
    [5] = { link = "item:990001", count = 2 } } }
  local slotReads, realInfo = 0, c.env.C_Container.GetContainerItemInfo
  c.env.C_Container.GetContainerItemInfo = function(...) slotReads = slotReads + 1; return realInfo(...) end
  fire(c, "BAG_UPDATE_DELAYED")
  tick(c, 2)
  c.env.C_Container.GetContainerItemInfo = realInfo
  assert(S:Value("potions") == 10 and S:Value("elixirs") == 2 and S:Value("flasks") == 1 and S:Value("food") == 14 and S:Value("bandages") == 8,
    "potions, elixirs, flasks, food and bandages by class: " .. table.concat({ tostring(S:Value("potions")), tostring(S:Value("elixirs")), tostring(S:Value("flasks")), tostring(S:Value("food")), tostring(S:Value("bandages")) }, " "))
  assert(S:Value("stones") == 1 and slotReads == 16 + 4 * 10, "one scan of the five bags served every count: " .. slotReads .. " slot reads")
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
  assert(reads >= 10, "the heartbeat reads the registry every minute: " .. reads)
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
  assert(noted and #chatLines(c) == 0, "the missing function is noted for /cute errors without a chat line")
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
  assert(e.C.Sample:Value("gchat") == 2 and e.C.Sample:Value("where") == 2, "two guild lines sent, where-are-you in party and in guild; the guild events count nothing: " .. tostring(e.C.Sample:Value("gchat")))
  -- "where are you" counts in any chat (the owner's "where are you?" in /say did not in 0.2.0), whole words only
  for _, line in ipairs({ { "where are you?", "SAY" }, { "Where R U", "WHISPER" }, { "wya", "PARTY" }, { "hvor er du??", "SAY" }, { "ok, where you at", "RAID" } }) do
    e.env.C_ChatInfo.SendChatMessage(line[1], line[2])
  end
  e.env.C_ChatInfo.SendChatMessage("where are your boots", "SAY")
  e.env.C_ChatInfo.SendChatMessage("nowhere", "SAY")
  assert(e.C.Sample:Value("where") == 7, "five more asks count, 'where are your boots' and 'nowhere' do not: " .. tostring(e.C.Sample:Value("where")))
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
        -- (a whole identifier: LootSlot loots, GetLootSlotLink only reads)
        if code:find("%f[%w_]" .. (name:gsub("%p", "%%%0")) .. "%f[^%w_]") and not (name == "COMBAT_LOG_EVENT_UNFILTERED" and code:find("==", 1, true)) then found[#found + 1] = file .. ":" .. n .. " " .. name end
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
  assert(yezin.C.Sample:Value("g2001") == 1234 and yezin.C.Sample:Value("g2008") == nil, "the quantity string parsed, -- read as nothing")
  assert(S.Quantity("1 234") == 1234 and S.Quantity("1.234.567") == 1234567 and S.Quantity("--") == nil and S.Quantity("") == nil and S.Quantity(nil) == nil
    and S.Quantity("1,5") == 1 and S.Quantity("1,234.5") == 1234 and S.Quantity("|cffffffff42|r") == 42 and S.Quantity("75%") == 75
    and S.Quantity("1 day 2 hours") == nil
    and S.Quantity("12|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 34|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 56|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t") == 123456,
    "the parser: separators, decimals, colours, money as copper")
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
  assert(noted and #chatLines(plain) == 0, "noted for /cute errors, no chat line")
  tickAll(45)
  local e = plain.env.CuteDB.roster["Yezin-Forever"]
  assert(e and e.stats.level and e.stats.g2001 == nil, "the first full record has no statistics")
  -- (one pass forced for the guild in ten minutes a responder, whoever asks: Yezin's last answered the storm's asks,
  -- so this one comes when the ten minutes are over, Comm.lua M:AnswerGame)
  local due = yezin.C.Comm.passAt and (yezin.C.Comm.passAt + 600 - yezin.C.Now()) or 0
  tickAll(math.max(60, math.ceil(due) + 5))
  assert(e.stats.g2001 == 1234 and e.stats.g2008 == nil, "the statistics pass answered the hello; a receiver without the API keeps them as ints, a never recorded one as nothing: " .. tostring(e.stats.g2001))
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
  yezin.C.UI:Open("settings", "vis")
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
  kaka.C.UI:Open("settings", "vis")
  check(kaka.C.UI.frame, "member settings, statistics categories")
  -- the page: categories left, the open one's statistics right with your value and the leader; a click ranks everyone
  -- (the page's two columns are two virtual lists: the categories, and the statistics with their rankings)
  local function lineOf(c, test)
    for _, list in ipairs({ c.C.UI.catLines, c.C.UI.lines }) do for _, l in ipairs(list.items) do if l:IsShown() and test(l) then return l end end end
  end
  -- (0.4.0: the discovered categories come first, Reputation here from the mock's factions; the page opens on it)
  yezin.C.UI:Open("game")
  assert(yezin.C.UI.page == "game" and yezin.C.UI.gameCat == "rep", "opens on the first category with entries, the discovered above the game's: " .. tostring(yezin.C.UI.gameCat))
  press(lineOf(yezin, function(l) return l.cat and l.cat.id == 130 end))
  assert(yezin.C.UI.gameCat == 130, "Kills opened")
  local kills = lineOf(yezin, function(l) return l.def and l.def.id == "g2001" and not l.member end)
  assert(kills and kills.val:GetText() == "1300" and kills.val.__justify == "RIGHT", "your value, right-aligned: " .. tostring(kills and kills.val:GetText()))
  assert(kills.who:GetText():find("Yezin", 1, true) and kills.who:GetText():find("1300", 1, true), "the leader, named and valued: " .. kills.who:GetText())
  local catLines = 0
  for _, l in ipairs(yezin.C.UI.catLines.items) do if l:IsShown() and l.cat then catLines = catLines + 1 end end
  assert(catLines == 5, "Reputation and the game's four categories on the left: " .. catLines)
  check(yezin.C.UI.frame, "officer statistics")
  press(kills)
  local ranked = {}
  for _, l in ipairs(yezin.C.UI.lines.items) do if l:IsShown() and l.member and l.def.id == "g2001" then ranked[#ranked + 1] = l end end
  assert(#ranked >= 2 and ranked[1].member.row.short == "Yezin" and ranked[1].name:GetText():find("^1%.") and ranked[2].name:GetText():find("^2%."), "a click ranks every member, the leader first: " .. #ranked)
  check(yezin.C.UI.frame, "officer statistics, a statistic opened")
  for _, l in ipairs(yezin.C.UI.lines.items) do if l:IsShown() then hover(l) end end
  -- the member: Kills is only-you, so it names no leader (its own value is the one it may see: the leader would always
  -- be itself) and Yezin's is a dash in the ranking
  kaka.C.UI:Open("game")
  press(lineOf(kaka, function(l) return l.cat and l.cat.id == 130 end))
  local kkills = lineOf(kaka, function(l) return l.def and l.def.id == "g2001" and not l.member end)
  assert(kkills and kkills.who:GetText() == "-" and tipText(kkills.tip):find("Only the officers see who leads.", 1, true), "the member sees no leader under only-you: " .. kkills.who:GetText())
  press(kkills)
  local dash = lineOf(kaka, function(l) return l.member and l.member.row.short == "Yezin" and l.def.id == "g2001" end)
  assert(dash and dash.who:GetText() == "-" and dash.member.hidden, "Yezin's kills are a dash for the member")
  local own = lineOf(kaka, function(l) return l.member and l.member.row.me and l.def.id == "g2001" end)
  assert(own and not own.name:GetText():find("^%d+%."), "and the member's own row no place: it would stand first alone: " .. tostring(own and own.name:GetText()))
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
  -- a client without the statistics API still shows what it discovered (its factions), the reason for the rest in a
  -- note under the categories
  plain.C.UI:Open("game")
  local note = plain.C.UI.gameNoteLabel
  assert(plain.C.UI.gameCat == "rep" and note and note:IsShown() and note:GetText():find("GetStatisticsCategoryList is missing", 1, true), "the discovered shown, the note says why the game's are not")
  check(plain.C.UI.frame, "member statistics, discovered only")
  plain.C.UI.frame:SetSize(760, 420)
  plain.C.UI:Open("game")
  check(plain.C.UI.frame, "member statistics, discovered only, small window")
  plain.C.UI.frame:SetSize(1040, 640)
  plain.C.UI:Open("me")
  check(plain.C.UI.frame, "member me, no statistics")
  assert(not note:IsShown(), "the note goes with the page")
  leave(plain)
  -- the empty state: no statistics API and nothing discovered (a character with no reputation list yet)
  local empty = newClient(charOf(NAMES[19], { factions = {} }))
  login(empty)
  empty.C.UI:Open("game")
  local said, counters = false, false
  for _, l in ipairs(empty.C.UI.labels.items) do
    if l:IsShown() and l:GetText():find("GetStatisticsCategoryList is missing", 1, true) then said = true end
    if l:IsShown() and l:GetText():find("counters stay on the other pages", 1, true) then counters = true end
  end
  assert(said and counters, "the empty state names the reason and says where the addon's own counters are")
  check(empty.C.UI.frame, "member statistics, empty state")
  leave(empty)
  -- a login with 300 statistics: under twenty messages per client in its first minute, every statistic across by
  -- the second, the whole login under forty-five
  local big1 = newClient(charOf(NAMES[12], { withStats = true, manyStats = 300 }))
  local big2 = newClient(charOf(NAMES[16], { withStats = true, manyStats = 300 }))
  login(big1); login(big2)
  tickAll(60)
  assert(#big1.sent < 20 and #big2.sent < 20, "under twenty messages in the first minute with 311 statistics: " .. #big1.sent .. ", " .. #big2.sent)
  assert(big2.env.CuteDB.roster[big1.name] and big2.env.CuteDB.roster[big1.name].stats.g3001 == nil, "none of them in that minute")
  tickAll(70)
  -- (the member gets every statistic but the Kills category's, which the officers keep to themselves since above: 77
  -- of them, whispered to the officers alone)
  local n, private, open = 0, 0, 0
  for id in pairs(big2.env.CuteDB.roster[big1.name].stats) do if id:match("^g%d+$") then n = n + 1; if big2.C.Policy:Route(id) == "self" then private = private + 1 end end end
  -- (a statistic never recorded, "--", is nothing, and a 0 kept as nothing: two of the fixture's)
  local valued = 0
  for _, def in ipairs(big1.C.Stats.byCat.game) do
    local v = big1.C.Sample:Value(def.id)
    if v ~= nil and v ~= 0 then valued = valued + 1; if big1.C.Policy:Route(def.id) == "all" then open = open + 1 end end
  end
  assert(n == open and open == 232 and private == 0, "every statistic the member may see across within two minutes, none kept from it: " .. n .. " of " .. open .. ", " .. private)
  local told = 0
  for id in pairs(yezin.env.CuteDB.roster[big1.name].stats) do if id:match("^g%d+$") then told = told + 1 end end
  assert(told == valued and valued == 309, "the officer has all 309 with a value: " .. told .. " of " .. valued)
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
  -- (what the reset opened again goes to the guild from every member: their queues drain before the next scenario)
  tickAll(15)
  print(string.format("policy chunks: %d messages for %d entries, applied whole; a reset replaces them", chunks, #ids))
end

-- 19: Forever's names. A character has two words ("Helga Bluntforce"): UnitName gives the first name and the surname,
-- the roster and the channel name it with both, and 0.3.0 showed Helga three times ("Helga (you)", "Helga Bluntforce
-- (no addon)" and a grey "Helga Bluntforce" of question marks: her own messages, handed back by the game, kept as a
-- member's record). Here: one row for you, named as the roster names you; your own messages dropped, even under a
-- sender string that matches none of your names (a Kstring), by the GUID they carry; a member whose roster name is a
-- Kstring joined to its record by GUID; ranks by the roster's name for the sender string; a GUID the roster gives a
-- member the sender string does not name never taken; 0.3.0's ghost record gone at login; /cute diag
do
  local function forever(first, rank, rankName, class, level, rosterName)
    GUILD[#GUILD + 1] = { name = rosterName, guid = guidOf(first), rank = rank, rankName = rankName, class = class, level = level, online = true }
    return { first, rank, rankName, class, level }
  end
  local H = forever("Helga", 0, "Guild Master", "WARRIOR", 30, "Helga Bluntforce")
  local T = forever("Thora", 1, "Officer", "PRIEST", 28, "Thora Bjorn")
  local I = forever("Icee", 3, "Raider", "MAGE", 26, "Icee Cake")
  local K = forever("Ser", 3, "Raider", "ROGUE", 25, "|Kq77|k") -- the roster gives this one's name as a Kstring
  -- (which GetPlayerInfoByGUID reads: a member online whose name reads in no form would leave every sender string
  -- matched by one word unsure, scenario 44)
  GUILD[#GUILD].guidName = "Ser"
  forever("Thora Stonehew", 4, "Member", "HUNTER", 59, "Thora Stonehew") -- Thora's namesake, without the addon so far
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
  assert(helga.C.Roster:MeOfficer() and helga.C.Roster:IsOfficer("Thora Bjorn") and not helga.C.Roster:IsOfficer("|Kq88|k") and not helga.C.Roster:IsOfficer("Ser Caliber"), "ranks by the roster's name for the sender string, none for a Kstring")
  assert(ser.C.Policy:Receive("Thora Bjorn", math.floor(EPOCH + ser.clock), 1, tok("gold", "all")) and ser.C.Policy:Vis("gold") == "all", "an officer with two names is an officer")
  assert(helga.C.Policy:Describe():find("Set by ", 1, true), "who set the policy, named")
  -- the GUID decides over a name, and the roster over a GUID. Thora's saved key is "Thora-Forever" (her first name and
  -- the realm), and a channel that named someone so would match her by name: a delta before any full record is taken
  -- for hers. A full record under it carrying Icee's GUID is not hers (a GUID not yours came under it), and not Icee's
  -- either: its first name is another, which no client can change in its sender string, so the GUID is dropped and the
  -- record marked suspect, standing apart with the deltas after it; neither Thora's row has it. Her namesake's GUID
  -- under it the roster cannot judge: "Thora" with no surname may be either Thora, so it is unsure, never another's
  local TR, tdb = thora.C.Roster, thora.env.CuteDB.roster
  assert(thora.C.Me() == "Thora-Forever", "Thora's saved key: " .. tostring(thora.C.Me()))
  thora.C.Comm:Receive("1D|3|level=1m", "GUILD", "Thora-Forever")
  assert(not tdb["Thora-Forever"] and TR.selfSenders["Thora-Forever"] == "name", "a delta under your name, no GUID: taken for yours")
  thora.C.Comm:Receive("1F|1|1|3|guid=" .. icee.o.guid .. ";level=1n", "GUILD", "Thora-Forever")
  local twin = tdb["Thora-Forever"]
  assert(twin and twin.stats.level == 59 and twin.stats.guid == nil and TR.selfSenders["Thora-Forever"] == nil, "another's GUID under your saved key: not yours, the name match forgotten, the GUID not taken")
  assert(twin.suspect and twin.suspect.why == "sent Icee Cake's GUID as its own", "and the record marked: " .. tostring(twin.suspect and twin.suspect.why))
  local stonehew = guidOf("Thora Stonehew")
  assert(TR:SenderMember("Thora-Forever") == nil and TR:Vouch("Thora-Forever", stonehew) == nil and TR:Vouch("Thora Stonehew", stonehew) == "same"
    and TR:Vouch("Thora Bjorn", stonehew) == "other", "the namesake's GUID under the first name alone: unsure; under the whole name theirs, under Thora's another's")
  thora.C.Comm:Receive("1D|3|level=1o", "GUILD", "Thora-Forever")
  assert(twin.stats.level == 60 and TR.selfSenders["Thora-Forever"] == nil, "the delta after it lands on that record, not taken for yours")
  thora.C.Roster:Refresh()
  local twins, apart, thoras = nil, nil, 0
  for _, r in ipairs(TR:Rows()) do
    if r.short == "Thora Stonehew" then twins = r end
    if r.key == "Thora-Forever" then apart = r end
    if r.me or r.short == "Thora Bjorn" then thoras = thoras + 1 end
  end
  assert(twins and not twins.addon and apart and apart.stats.level == 60 and apart.suspect and thoras == 1, "the namesake's row has no record, the one under your saved key stands apart, marked; Thora one row")
  thora.C.Policy:Set("gold", "all")
  assert(thora.C.Policy:Describe():find("Set by Thora Bjorn,", 1, true), "your own policy is yours, whoever has your saved key: " .. thora.C.Policy:Describe())
  -- under the sender string the roster names Thora by, a full record carrying another's GUID is hers, handed back:
  -- nobody else sends under it, and her Cute sends no GUID but hers. Dropped, with her own delta after it
  assert(TR.selfSenders["Thora Bjorn"] == "guid", "Thora's sender string, known by her GUID")
  thora.C.Comm:Receive("1F|1|1|3|guid=" .. guidOf("Thora Ashby") .. ";level=a", "GUILD", "Thora Bjorn")
  assert(not tdb["Thora Bjorn"], "another's GUID under the sender string the roster names you by: yours, no record")
  thora.C.Comm:Receive("1D|3|level=1p", "GUILD", "Thora Bjorn")
  assert(not tdb["Thora Bjorn"] and TR.selfSenders["Thora Bjorn"] == "guid", "your delta under it: yours")
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
  print("forever names: one row for you named as the roster names you, your own messages dropped by GUID under any sender string, Kstring names joined by GUID, ranks by the roster's name for the sender, emotes by GUID, another's GUID under your saved key taken by neither and a namesake's unsure, 0.3.0's ghost record gone, /cute diag")
end

-- 20: gear on a client whose GetInventoryItemLink gives a secret for every slot (0.3.0 showed 15 of 17 slots empty,
-- 0 of 17 unenchanted and item level "?" for a character in full gear): the item ids and qualities read as Forever's
-- character sheet reads them, the levels from the ids, and the enchants read nil with the reason (Missing enchants
-- only once the guild has learned a slot this client cannot read: a slot nobody enchants asks for no link)
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
  assert(S:Value("enchanted") == nil and tostring(S:Error("enchanted")):find("no readable item link for 4 worn slots", 1, true), "no enchants read without links: " .. tostring(S:Error("enchanted")))
  assert(type(S:Value("unenchanted")) == "table" and next(S:Value("unenchanted")) == nil, "nothing missing while the guild has learned no slot")
  -- with the defaults a member's client hears no member's enchants (Enchanted slots follows Missing enchants): two
  -- members' records, one edited to send them anyway, teach nothing. The officers' word teaches chest (the chest worn
  -- here is the same kind): now the chest's link is needed, and there is none
  c.C.Roster:Apply("Someone-Forever", { guid = "Player-4242-0BADBEEF", enchanted = { [5] = true }, ench_kinds = "5:15.0" })
  c.C.Roster:Apply("Another-Forever", { guid = "Player-4242-0BADBEF0", enchanted = { [5] = true }, ench_kinds = "5:15.0" })
  tick(c, 2)
  assert(type(S:Value("unenchanted")) == "table" and next(S:Value("unenchanted")) == nil and not c.C.Stats.EnchantLearned(5),
    "members' enchants teach a member's client nothing with the defaults")
  c.C.Comm:Receive("1N|" .. string.format("%.0f", EPOCH + c.clock) .. "|n5=15.0", "GUILD", "Yezin-Forever")
  tick(c, 4)
  assert(S:Value("unenchanted") == nil and tostring(S:Error("unenchanted")):find("no readable item link for 1 worn slot that takes an enchant", 1, true), "no enchant count without links: " .. tostring(S:Error("unenchanted")))
  assert(S:Value("ready") == 2, "readiness still reads (it counts durability and potions; the empty slots are the officers')")
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
  -- the Statistics ranking: Total kills opened ranks 151 (Kills opened first: the page opens on the discovered Reputation)
  UI:Open("game")
  for _, l in ipairs(UI.catLines.items) do if l:IsShown() and l.cat and l.cat.id == 130 then press(l); break end end
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
  -- a burst of thirty members' records (each a ding, as the roster allows): one Draw a second later; none while the
  -- window is hidden
  draws = UI.draws
  for i = 1, 30 do big.C.Roster:Apply(made[i * 2].name, { level = math.min(60, made[i * 2].level + 1) }) end
  tick(big, 2)
  assert(UI.draws == draws + 1, "thirty records, one draw: " .. (UI.draws - draws))
  UI.frame:Hide()
  draws = UI.draws
  for i = 1, 30 do big.C.Roster:Apply(made[i * 2].name, { level = made[i * 2].level }) end
  tick(big, 3)
  assert(UI.draws == draws, "none while hidden")
  big.C.Roster.Rows = realRows
  leave(big)
  makeGuild()
  print("400 members: " .. table.concat(report, "; ") .. "; ten sampler ticks draw nothing; thirty records draw once, hidden none")
end

-- saved variables whose policy, from an officer (mine: that officer's own client), opens Missing enchants and Empty
-- slots, so Enchanted slots and the kinds of the enchanted items go to the guild: the scenarios that weigh how the
-- guild learns its enchants from its members run on it
local function gapsOpen(mine)
  return { policy = { vis = { unenchanted = "all", empty_slots = "all" }, by = mine or "Officer-Forever", mine = mine and true or nil, rank = 1, at = EPOCH - 100, threshold = 1 } }
end

-- run fn with a guild and clients of its own: the scenario's messages reach none of the others, and the others' none of
-- its; the shared guild and clients come back afterwards
local function isolated(guild, fn)
  local keepClients, keepGuild, keepInfo, keepEdit = {}, GUILD, INFO, INFO_EDIT
  for i, c in ipairs(clients) do keepClients[i] = c end
  for i = #clients, 1, -1 do clients[i] = nil end
  GUILD, INFO = guild, {}
  fn()
  for i = #clients, 1, -1 do clients[i] = nil end
  for i, c in ipairs(keepClients) do clients[i] = c end
  GUILD, INFO, INFO_EDIT = keepGuild, keepInfo, keepEdit
end

-- members the roster lists for the GUIDs a scenario makes up for its records (a record's GUID is a voice in what the
-- guild learns only where the roster lists a member with it: Roster.lua R:VoiceOf), offline, and the roster read again.
-- list: { { sender string, GUID, level }, ... }
local function listed(c, list)
  for _, x in ipairs(list) do
    local have = false
    for _, m in ipairs(GUILD) do if m.guid == x[2] then have = true end end
    if not have then GUILD[#GUILD + 1] = { name = x[1], guid = x[2], rank = 3, rankName = "Raider", class = "MAGE", level = x[3] or 40, online = false } end
  end
  c.C.Roster:Refresh()
end

-- 22: gear without a reload. 0.3.1's gear stats listened to PLAYER_EQUIPMENT_CHANGED alone; on a login whose inventory
-- arrives after the loading screen (UNIT_INVENTORY_CHANGED, which Forever's own character sheet refreshes on) and on an
-- enchant (the link changes, no equipment changes) nothing read them again until the five-minute heartbeat or a
-- /reload. Here the client's slots read nothing until UNIT_INVENTORY_CHANGED fires three seconds after login: with
-- the Prog page open, the empty-slot and item-level cells fill in on their own, without a draw; another unit's
-- inventory reads nothing; then an enchant applied (only UNIT_INVENTORY_CHANGED fires) clears Missing enchants
do
  local c = newClient(charOf(NAMES[10], { invLate = true }))
  login(c)
  local S = c.C.Sample
  c.env.CuteDB.settings.columns.prog = { ilvl = true, empty_slots = true, unenchanted = true, ready = true }
  c.C.UI:Open("prog")
  local me = rowOf(c, "Lindel")
  assert(cellOf(me, "empty_slots").label:GetText() == "15/17" and cellOf(me, "ilvl").label:GetText() == "?", "before the inventory: every slot empty, no item level: " .. cellOf(me, "empty_slots").label:GetText())
  tick(c, 2) -- the gear pass two seconds after the loading screen: the inventory is still not there
  c.invReady = true
  fire(c, "UNIT_INVENTORY_CHANGED", "party1")
  tick(c, 2)
  assert(cellOf(me, "empty_slots").label:GetText() == "15/17", "another unit's inventory reads nothing")
  local draws = c.C.UI.draws
  fire(c, "UNIT_INVENTORY_CHANGED", "player")
  tick(c, 2.5)
  assert(c.clock < c.born + 10, "before the ten-second pass: " .. (c.clock - c.born))
  assert(cellOf(me, "empty_slots").label:GetText() == "11/17" and cellOf(me, "ilvl").label:GetText() == "46", "the cells filled on their own: " .. cellOf(me, "empty_slots").label:GetText() .. ", " .. cellOf(me, "ilvl").label:GetText())
  -- (one draw at most; the read kept the enchanted chest it saw, a first voice waiting for a second)
  assert(c.C.UI.draws <= draws + 1 and c.env.CuteDB.known.enchant[5], "your row refilled; one draw at most: " .. (c.C.UI.draws - draws))
  -- the guild has legs of this kind enchanted (the officers' word says so: with the defaults a member's client hears
  -- no member's enchants): Missing enchants names them, on the open page
  c.C.Comm:Receive("1N|" .. string.format("%.0f", EPOCH + c.clock) .. "|n7=15.0", "GUILD", "Yezin-Forever")
  tick(c, 5)
  assert(cellOf(me, "unenchanted").label:GetText() == "1" and S:Value("unenchanted")[7], "legs missing their enchant: " .. cellOf(me, "unenchanted").label:GetText())
  -- an enchant applied: the link changes, the item does not; only UNIT_INVENTORY_CHANGED fires
  local pec = 0
  for _, f in ipairs(c.frames) do if f.__events.PLAYER_EQUIPMENT_CHANGED then pec = pec + 1 end end
  c.o.items[7] = "item:1236:1900"
  fire(c, "UNIT_INVENTORY_CHANGED", "player")
  tick(c, 2.5)
  assert(cellOf(me, "unenchanted").label:GetText() == "0" and S:Value("enchanted")[7], "Missing enchants cleared on the open page: " .. cellOf(me, "unenchanted").label:GetText())
  assert(S:Value("ready") == 2, "the verdict counts what everyone may see: the legs and the empty slots are the officers'")
  check(c.C.UI.frame, "member prog, the inventory arrived late")
  c.env.CuteDB.settings.columns.prog = nil
  -- the heartbeat is a minute now; a quiet minute reads every stat and sends nothing new (scenario 5 holds the five
  -- quiet minutes to their flushes)
  local reads = 0
  local real = c.env.C_SpecializationInfo.GetSpecialization
  c.env.C_SpecializationInfo.GetSpecialization = function(...) reads = reads + 1; return real(...) end
  tick(c, 125)
  c.env.C_SpecializationInfo.GetSpecialization = real
  assert(reads >= 2, "the heartbeat reads the registry every minute: " .. reads)
  leave(c)
  print("gear without a reload: a late inventory fills empty slots and item level on the open page by UNIT_INVENTORY_CHANGED (another unit's ignored), an enchant clears Missing enchants without PLAYER_EQUIPMENT_CHANGED, the heartbeat every minute")
end

-- 23: the enchantable slots are learned, not listed. An officer and three members, nobody with a head or shoulder
-- enchant (Forever has none yet) and nobody with a neck enchant until Astrid gets one, which alone teaches nothing (one
-- addon's word changes no one's knowledge); then Bjorn gets one too: Cecil's Missing enchants names the neck on its
-- next read, the officer sees it on receipt, and head and shoulder are never named. The knowledge counts members once
-- by GUID (a delta that comes before the GUID teaches nothing), survives a /reload and Astrid leaving the guild, and is
-- taught by records saved before that carry a GUID. (Everyone's neck is the same kind of item here, 15.0; scenario 26
-- holds the kinds apart.) The officers open Missing enchants and Empty slots here, so Enchanted slots goes to the
-- guild and every member learns from the others' enchants; scenario 43 learns them with the defaults, from the
-- officers' word
do
  local function member(name, rank, rankName, class) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rankName, class = class, level = 30, online = true } end
  local guild = { member("Odda", 1, "Officer", "PRIEST"), member("Astrid", 3, "Raider", "WARRIOR"), member("Bjorn", 3, "Raider", "MAGE"), member("Cecil", 3, "Raider", "ROGUE") }
  isolated(guild, function()
    local gear = function() return { [1] = "item:3001:0", [2] = "item:3002:0", [3] = "item:3003:0", [5] = "item:3005:0", [16] = "item:3016:0" } end
    local odda = newClient(charOf({ "Odda", 1, "Officer", "PRIEST", 30 }, { items = { [1] = "item:3101:0", [5] = "item:3105:0" } }))
    local astrid = newClient(charOf({ "Astrid", 3, "Raider", "WARRIOR", 30 }, { items = gear() }))
    local bjorn = newClient(charOf({ "Bjorn", 3, "Raider", "MAGE", 30 }, { items = gear() }))
    local cecil = newClient(charOf({ "Cecil", 3, "Raider", "ROGUE", 30 }, { items = gear() }))
    for _, c in ipairs({ odda, astrid, bjorn, cecil }) do login(c, gapsOpen(c == odda and "Odda-Forever")) end
    tickAll(45)
    local function missing(c) local v = c.C.Sample:Value("unenchanted"); local out = {}; for slot in pairs(v or {}) do out[#out + 1] = slot end table.sort(out); return table.concat(out, ",") end
    for _, c in ipairs({ astrid, bjorn, cecil }) do
      assert(missing(c) == "" and next(c.env.CuteDB.known.enchant) == nil, c.o.name .. ": nothing learned, nothing missing: " .. missing(c))
    end
    -- Astrid's neck enchanted: her own read keeps it and her delta carries it, one voice, which asks nobody for one
    astrid.o.items[2] = "item:3002:2564"
    fire(astrid, "UNIT_INVENTORY_CHANGED", "player")
    tickAll(6)
    for _, c in ipairs({ bjorn, cecil }) do
      assert(missing(c) == "", c.o.name .. ": one member's enchant teaches nothing: " .. missing(c))
      local k = c.env.CuteDB.known.enchant[2]
      assert(k and k.n == 1 and k.who[astrid.o.guid] and not c.C.Stats.EnchantLearned(2), "the guild's knowledge: one member seen with one, kept, not learned")
    end
    -- Bjorn's too: the second voice. Cecil's next read names the neck
    bjorn.o.items[2] = "item:3002:2564"
    fire(bjorn, "UNIT_INVENTORY_CHANGED", "player")
    tickAll(6)
    assert(missing(cecil) == "2", "Cecil shows the neck missing: " .. missing(cecil))
    local k = cecil.env.CuteDB.known.enchant[2]
    assert(k and k.n == 2 and k.who[astrid.o.guid] and k.who[bjorn.o.guid], "the guild's knowledge: two members seen with one")
    assert(missing(astrid) == "" and missing(bjorn) == "" and astrid.env.CuteDB.known.enchant[2].n == 2, "Astrid and Bjorn have theirs; each counts once")
    for _, c in ipairs({ odda, astrid, bjorn, cecil }) do
      assert(not c.env.CuteDB.known.enchant[1] and not c.env.CuteDB.known.enchant[3], c.o.name .. ": head and shoulder never learned")
    end
    -- the officer: Cecil's Missing enchants arrived; the tooltip names the slot and how many have one
    assert(odda.env.CuteDB.roster["Cecil-Forever"].stats.unenchanted[2], "the officer has Cecil's missing neck")
    odda.env.CuteDB.settings.columns.prog = { ready = true, unenchanted = true, enchanted = true }
    odda.C.UI:Open("prog")
    local cell = cellOf(rowOf(odda, "Cecil"), "unenchanted")
    assert(cell and cell.label:GetText() == "1", "the officer's view: 1 missing for Cecil: " .. tostring(cell and cell.label:GetText()))
    local l0 = #lines
    hover(cell)
    local tip = table.concat(lines, "\n", l0 + 1)
    assert(tip:find("Neck | seen on 2 members", 1, true) and not tip:find("Head", 1, true), "the tooltip: " .. tip)
    l0 = #lines
    hover(cellOf(rowOf(odda, "Cecil"), "ready"))
    tip = table.concat(lines, "\n", l0 + 1)
    assert(tip:find("a missing enchant", 1, true), "the verdict's gaps name it: " .. tip)
    check(odda.C.UI.frame, "officer prog, a learned enchant slot")
    -- an older client's list (0.3.x named head and shoulder): this client shows only the slots it knows the guild enchants
    odda.C.Roster:Apply("Cecil-Forever", { unenchanted = { [1] = true, [2] = true, [3] = true } })
    odda.C.UI:Draw()
    assert(cellOf(rowOf(odda, "Cecil"), "unenchanted").label:GetText() == "1", "head and shoulder from an older client left out")
    -- counted once each, by GUID, however many messages carry it
    bjorn.C.Comm:Full()
    tickAll(12)
    assert(cecil.env.CuteDB.known.enchant[2].n == 2, "two members seen, each once: " .. cecil.env.CuteDB.known.enchant[2].n)
    -- /diag names the slot
    local n0 = #cecil.chat
    cecil.env.SlashCmdList.CUTE("diag")
    assert(table.concat(cecil.chat, "\n", n0 + 1):find("known: enchant slots Neck (2: Junk 2)", 1, true), "/cute diag names the learned slots and kinds")
    -- a /reload keeps the knowledge
    local db = cecil.env.CuteDB
    leave(cecil)
    local again = newClient(charOf({ "Cecil", 3, "Raider", "ROGUE", 30 }, { items = gear() }))
    login(again, db, true)
    assert(missing(again) == "2" and again.env.CuteDB.known.enchant[2].n == 2, "after a /reload: still known, still missing")
    -- Astrid and Bjorn leave the guild: their records are pruned, the knowledge stays
    table.remove(GUILD, 3); table.remove(GUILD, 2)
    fire(again, "GUILD_ROSTER_UPDATE"); tickAll(61); fire(again, "GUILD_ROSTER_UPDATE")
    assert(not again.env.CuteDB.roster["Astrid-Forever"] and not again.env.CuteDB.roster["Bjorn-Forever"], "their records pruned")
    again.C.Sample:ReadAll()
    assert(missing(again) == "2" and again.env.CuteDB.known.enchant[2], "the neck stays learned after they left")
    -- records saved before teach a fresh knowledge (a member's back enchant in a record, the knowledge lost)
    db.known = nil
    -- (and one without a GUID teaches nothing: counted under its sender string, that member would count twice once the
    -- GUID came)
    -- (Someone and Dagny are members the roster lists: a GUID it gives nobody is no voice, scenario 46)
    GUILD[#GUILD + 1] = { name = "Someone-Forever", guid = "Player-4242-0FACADE0", rank = 3, rankName = "Raider", class = "MAGE", level = 30, online = false }
    GUILD[#GUILD + 1] = member("Dagny", 3, "Raider", "MAGE")
    db.roster["Someone-Forever"] = { seen = EPOCH + again.clock, online = true, at = {}, stats = { guid = "Player-4242-0FACADE0", enchanted = { [15] = true }, ench_kinds = "15:15.0" } }
    db.roster["Nameless-Forever"] = { seen = EPOCH + again.clock, online = true, at = {}, stats = { enchanted = { [8] = true }, ench_kinds = "8:15.0" } }
    leave(again)
    local fresh = newClient(charOf({ "Cecil", 3, "Raider", "ROGUE", 30 }, { items = gear() }))
    login(fresh, db, true)
    assert(fresh.env.CuteDB.known.enchant[15] and fresh.env.CuteDB.known.enchant[15].n == 1, "the saved record's back enchant is kept, a first voice")
    assert(not fresh.env.CuteDB.known.enchant[8], "a saved record without a GUID taught nothing")
    -- a delta that comes before any full record (no GUID yet) teaches nothing; the full record after it counts the
    -- member once (0.4.0's first build counted the delta under the sender string and the record again under the GUID)
    fresh.C.Roster:Apply("Dagny-Forever", { enchanted = { [9] = true }, ench_kinds = "9:15.0" })
    assert(not fresh.env.CuteDB.known.enchant[9], "a delta without a GUID teaches nothing yet")
    fresh.C.Roster:Apply("Dagny-Forever", { guid = guidOf("Dagny"), enchanted = { [9] = true }, ench_kinds = "9:15.0" })
    fresh.C.Roster:Apply("Dagny-Forever", { ench_kinds = "9:15.0" })
    assert(fresh.env.CuteDB.known.enchant[9].n == 1 and fresh.env.CuteDB.known.enchant[9].kinds["15.0"].n == 1, "the full record counts Dagny once: " .. fresh.env.CuteDB.known.enchant[9].n)
    for _, c in ipairs({ odda, astrid, bjorn, fresh }) do leave(c) end
  end)
  print("learned enchants: one member's neck enchant teaches nothing, a second makes the neck missing for the others on their next read and for the officer on receipt; head and shoulder never; counted once per member by GUID (a delta before the GUID teaches nothing); kept across a /reload, the members leaving, and kept from saved records with a GUID")
end

-- 24: what the guild meets in play is discovered and shared. Xavi enters a dungeon and kills its bosses (ENCOUNTER_END,
-- BOSS_KILL where none came, never twice), a /reload and a run back are no new entry, another dungeon and a raid are;
-- the reputation list (headers left out, one with rep kept) is read once a second however many UPDATE_FACTION come,
-- and by id once the headers are folded. Rona never met any of it: the labels message gives her the bosses under
-- their instance, a UTF-8 name whole, a name with ; and | cleaned. The policy per discovered category, the raid buffs
-- learned from guild mates, a saved record full of 0.3.x's removed ids, and the Statistics page's new categories at
-- both sizes for both views
do
  local function member(name, rank, rankName, class) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rankName, class = class, level = 30, online = true } end
  local guild = { member("Wynn", 1, "Officer", "PALADIN"), member("Xavi", 3, "Raider", "HUNTER"), member("Rona", 3, "Raider", "DRUID") }
  isolated(guild, function()
    -- (a guild text, so Xavi's Guild Info reads inside the dungeon after his /reload: an empty text there is no answer,
    -- and no line read before the /reload stands for it, Policy.lua P:ReadLine)
    INFO[7] = "Welcome to <Cute>!"
    local wynn = newClient(charOf({ "Wynn", 1, "Officer", "PALADIN", 30 }, { factions = {} }))
    local xavi = newClient(charOf({ "Xavi", 3, "Raider", "HUNTER", 30 }))
    -- (Rona has a reputation list of her own: the standing ranges she learns from it name Xavi's standings)
    local rona = newClient(charOf({ "Rona", 3, "Raider", "DRUID", 30 }))
    for _, c in ipairs({ wynn, xavi, rona }) do login(c) end
    tickAll(45)
    local X = xavi.C.Sample
    local function V(id) return X:Value(id) end
    local function enter(kind, id, name) xavi.o.instance, xavi.o.instanceID, xavi.o.instName = kind, id, name; fire(xavi, "PLAYER_ENTERING_WORLD", false, false) end
    -- a dungeon entered
    local dungeons = V("dungeons")
    enter("party", 36, "The Deadmines")
    assert(V("i36") == 1 and V("dungeons") == dungeons + 1 and V("dungeons_seen") == 1, "an entry: " .. tostring(V("i36")))
    assert(xavi.env.CuteDB.known.labels.i36 == "The Deadmines" and xavi.env.CuteDB.known.kind[36] == "party", "the instance labelled, a dungeon")
    -- a boss by ENCOUNTER_END, then its BOSS_KILL: once
    fire(xavi, "ENCOUNTER_END", 1234, "Edwin VanCleef", 1, 5, 1, {})
    fire(xavi, "BOSS_KILL", 1234, "Edwin VanCleef")
    tick(xavi, 6)
    assert(V("e1234") == 1 and V("bosses") == 1, "a kill counted once: " .. tostring(V("e1234")))
    -- BOSS_KILL alone (a UTF-8 name): counted five seconds on; a wipe (success 0) is no kill
    fire(xavi, "BOSS_KILL", 1235, "Thorvald Bj\195\182rnsson")
    fire(xavi, "ENCOUNTER_END", 1236, "Glubtok", 1, 5, 0, {})
    assert(V("e1235") == nil, "not yet: BOSS_KILL waits for an ENCOUNTER_END")
    tick(xavi, 6)
    assert(V("e1235") == 1 and V("e1236") == nil, "BOSS_KILL alone counts; a wipe does not")
    -- BOSS_KILL first, ENCOUNTER_END within five seconds: once; the name carries ; and |, which never travel
    fire(xavi, "BOSS_KILL", 1237, "Mor;ladim|x")
    tick(xavi, 2)
    fire(xavi, "ENCOUNTER_END", 1237, "Mor;ladim|x", 1, 5, 1, {})
    tick(xavi, 6)
    assert(V("e1237") == 1 and V("bosses") == 3 and xavi.env.CuteDB.known.labels.e1237 == "Morladimx", "once, the label cleaned: " .. tostring(xavi.env.CuteDB.known.labels.e1237))
    assert(xavi.env.CuteDB.chars[xavi.name].firstKill[1234], "the first kill's time kept")
    -- a /reload inside: no entry
    local db = xavi.env.CuteDB
    leave(xavi)
    local xo = xavi.o
    xavi = newClient(xo)
    login(xavi, db, true)
    X = xavi.C.Sample
    assert(V("i36") == 1, "a /reload is no entry: " .. tostring(V("i36")))
    -- out to the world and back to the same dungeon (a wipe's run back): no entry; another dungeon, then back: entries
    enter("none", 0, "Westfall")
    enter("party", 36, "The Deadmines")
    assert(V("i36") == 1, "the same dungeon again after the world: no entry")
    enter("party", 48, "Blackfathom Deeps")
    enter("party", 36, "The Deadmines")
    assert(V("i48") == 1 and V("i36") == 2 and V("dungeons_seen") == 2, "another dungeon, then back: two entries")
    -- a raid: Raids, the weekly count
    local weekly = V("weekly_raids")
    enter("raid", 2000, "Ashen Sanctum")
    assert(V("i2000") == 1 and V("raids") >= 1 and V("weekly_raids") == weekly + 1 and xavi.env.CuteDB.known.kind[2000] == "raid", "a raid entered")
    -- the reputation list: headers without rep left out, a header with rep kept; a storm of UPDATE_FACTION reads it once
    local S = xavi.C.Stats
    assert(S.byId.f72 and S.byId.f1168 and S.byId.f589 and not S.byId.f469 and not S.byId.f1100, "the factions, the plain headers left out")
    assert(V("f72") == 3500 and V("f589") == -4000 and S.byId.f72.fmt(3500) == "Friendly" and S.byId.f589.fmt(-4000) == "Hostile", "standings, named by the reaction ranges learned")
    local listReads, realNum = 0, xavi.env.C_Reputation.GetNumFactions
    xavi.env.C_Reputation.GetNumFactions = function(...) listReads = listReads + 1; return realNum(...) end
    xavi.o.standing = { [72] = 9500 }
    for _ = 1, 20 do fire(xavi, "UPDATE_FACTION"); tick(xavi, 0.04) end
    tick(xavi, 2)
    assert(listReads == 1 and V("f72") == 9500 and S.byId.f72.fmt(9500) == "Honored", "twenty UPDATE_FACTION, one read: " .. listReads)
    xavi.env.C_Reputation.GetNumFactions = realNum
    -- the headers folded: the list shows them alone; the factions are asked by id
    xavi.o.folded, xavi.o.standing = true, { [72] = 9600, [930] = 12000 }
    fire(xavi, "UPDATE_FACTION")
    tick(xavi, 2)
    assert(V("f72") == 9600 and V("f930") == 12000, "read by id while folded: " .. tostring(V("f72")))
    xavi.o.folded = nil
    -- Rona never met any of it: the values and the labels arrive, the bosses under their instance
    tickAll(130)
    local K = rona.env.CuteDB.known
    -- (one member's word names them and files them, where the seed does not already; the kind of an instance the seed
    -- does not name stays unsure until a second member agrees: Stats.lua S.KindOf)
    local RS = rona.C.Stats
    assert(RS.LabelOf("e1234") == "Edwin VanCleef" and RS.InstOf(1234) == 36 and RS.LabelOf("i36") == "The Deadmines" and RS.KindOf(36) == "party", "the labels reached Rona")
    local raidKind, raidSure = RS.KindOf(2000)
    assert(K.labels.e1235 == "Thorvald Bj\195\182rnsson" and K.labels.e1237 == "Morladimx" and raidKind == "raid" and not raidSure and not K.kind[2000],
      "a UTF-8 label whole, the cleaned one as sent; the raid's kind one member's word")
    assert(not K.mine.e1234 and rona.C.Stats.byId.e1234 and rona.C.Stats.byId.e1234.label == "Edwin VanCleef", "defined on Rona as another's")
    local xr = rona.env.CuteDB.roster["Xavi-Forever"]
    assert(xr.stats.e1234 == 1 and xr.stats.i36 == 2 and xr.stats.f72 == 9600 and xr.stats.bosses == 3, "Xavi's values on Rona's roster")
    local board = rona.C.Stats.Board()
    local names = {}
    for _, cat in ipairs(board.cats) do names[#names + 1] = tostring(cat.id) .. "=" .. cat.name end
    local list = table.concat(names, " ")
    assert(list:find("bosses=Bosses b36=The Deadmines dungeons=Dungeons raids=Raids rep=Reputation", 1, true), "the categories: " .. list)
    local inDeadmines = {}
    for _, def in ipairs(board.byCat.b36) do inDeadmines[#inDeadmines + 1] = def.label end
    assert(table.concat(inDeadmines, ", ") == "Edwin VanCleef, Morladimx, Thorvald Bj\195\182rnsson", "the bosses under their instance: " .. table.concat(inDeadmines, ", "))
    -- the page: Rona opens on Bosses' first instance; Xavi leads, Rona's own value a dash
    local function lineOf(c, test) for _, lst in ipairs({ c.C.UI.catLines, c.C.UI.lines }) do for _, l in ipairs(lst.items) do if l:IsShown() and test(l) then return l end end end end
    rona.C.UI:Open("game")
    assert(rona.C.UI.gameCat == "b36", "the page opens on the first instance's bosses: " .. tostring(rona.C.UI.gameCat))
    local edwin = lineOf(rona, function(l) return l.def and l.def.id == "e1234" and not l.member end)
    assert(edwin and edwin.who:GetText():find("Xavi", 1, true) and edwin.val:GetText() == "-", "Xavi leads, Rona has not met it: " .. tostring(edwin and edwin.who:GetText()))
    check(rona.C.UI.frame, "member statistics, discovered bosses")
    press(edwin)
    check(rona.C.UI.frame, "member statistics, a boss ranked")
    for _, l in ipairs(rona.C.UI.lines.items) do if l:IsShown() then hover(l) end end
    press(lineOf(rona, function(l) return l.cat and l.cat.id == "rep" end))
    local exodar = lineOf(rona, function(l) return l.def and l.def.id == "f930" and not l.member end)
    assert(exodar and exodar.who:GetText():find("Xavi", 1, true) and exodar.who:GetText():find("Honored", 1, true), "a member's standing named: " .. tostring(exodar and exodar.who:GetText()))
    check(rona.C.UI.frame, "member statistics, reputation")
    press(lineOf(rona, function(l) return l.cat and l.cat.id == "raids" end))
    check(rona.C.UI.frame, "member statistics, raids")
    -- the officer: the same at both sizes; the parent row opens its first child
    wynn.C.UI:Build()
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      wynn.C.UI.frame:SetSize(size[1], size[2])
      wynn.C.UI:Open("game")
      press(lineOf(wynn, function(l) return l.cat and l.cat.id == "bosses" end))
      assert(wynn.C.UI.gameCat == "b36", "Bosses opens its first instance")
      check(wynn.C.UI.frame, string.format("officer statistics, discovered, %dx%d", size[1], size[2]))
      rona.C.UI.frame:SetSize(size[1], size[2])
      rona.C.UI:Open("game")
      check(rona.C.UI.frame, string.format("member statistics, discovered, %dx%d", size[1], size[2]))
    end
    wynn.C.UI.frame:SetSize(1040, 640); rona.C.UI.frame:SetSize(1040, 640)
    -- the policy per discovered category: Bosses only-you; Settings has the four pairs
    wynn.C.Policy:Set("gc_bosses", "self")
    wynn.C.Comm:SendPolicy()
    tickAll(3)
    assert(rona.C.Policy:Vis("e1234") == "self" and rona.C.Policy:Vis("i36") == "all" and rona.C.Policy:Vis("f72") == "all", "Bosses only-you covers every instance's bosses")
    rona.C.UI:Open("game")
    press(lineOf(rona, function(l) return l.cat and l.cat.id == "b36" end))
    edwin = lineOf(rona, function(l) return l.def and l.def.id == "e1234" and not l.member end)
    assert(edwin.who:GetText() == "-", "the member sees no leader under only-you")
    wynn.C.UI:Open("settings", "vis")
    local pairs4 = 0
    for _, fr in ipairs(wynn.frames) do if fr.__kind == "CheckButton" and fr:IsVisible() and fr.vis == "self" and type(fr.statId) == "string" and fr.statId:match("^gc_%l+$") then pairs4 = pairs4 + 1 end end
    assert(pairs4 == 4, "four discovered pairs in Settings: " .. pairs4)
    check(wynn.C.UI.frame, "officer settings, discovered categories")
    -- the Me page counts what you discovered; the Officers page what the guild learned
    xavi.C.UI:Open("me")
    assert(texts(xavi):find("Discovered: 3 bosses in 1 instance, 2 dungeons, 1 raid, 5 factions, on the Statistics page.", 1, true), "the Me page counts:\n" .. texts(xavi))
    check(xavi.C.UI.frame, "member me, discovered counts")
    wynn.C.UI:Open("officers")
    assert(texts(wynn):find("Learned in play: 3 bosses in 1 instance, 2 dungeons, 1 raid, 5 factions.", 1, true), "the Officers page line:\n" .. texts(wynn))
    check(wynn.C.UI.frame, "officer officers, learned in play")
    -- labels that do not parse are skipped; a long one is cut on a character. (A label is a member's word: from a sender
    -- the roster gives no GUID, none is taken)
    local body = "e77:36=Slab;x9=nope;i5:z=bad kind;f12=Darnassus;f13=" .. string.rep("\195\182", 40) .. ";e88=" .. string.rep("A", 80)
    assert(rona.C.Comm:ReceiveLabels(body, "Stranger-Elsewhere") == 0 and not K.labels.f12, "a stranger's labels: none taken")
    -- (on the officer's client: Bosses is the officers' now, and a member's client passes a boss's label by, as it says
    -- who met the boss)
    local WK = wynn.env.CuteDB.known
    local n = wynn.C.Comm:ReceiveLabels(body, xavi.sender)
    assert(n == 4 and WK.labels.f12 == "Darnassus" and WK.labels.f13 == string.rep("\195\182", 30) and #WK.labels.e88 == 60 and WK.inst[77] == 36 and not WK.labels.x9 and not WK.kind[5], "parsed and cleaned: " .. n)
    n = rona.C.Comm:ReceiveLabels(body, xavi.sender)
    assert(n == 2 and K.labels.f12 == "Darnassus" and not K.labels.e88 and not K.inst[77], "a member's client takes the factions' labels and passes the bosses' by: " .. n)
    -- the raid buffs: a guild mate's long buff on Xavi is remembered; a short one, a stranger's and his own are not.
    -- Remembered is not yet a raid buff (0.4.0's first build counted any long buff a guild mate ever cast, for ever, so
    -- one Soulstone while leveling stood as missing for good): one counts once two guild mates have cast it, or one has
    -- three times; a missing one counts only in a group or an instance; one no guild mate cast for two weeks goes
    xavi.o.instance, xavi.o.instanceID, xavi.o.instName = "none", 0, nil
    xavi.o.party = { "Wynn" }
    local INNER = { "Inner Fire", 588, "player", 600 }
    local function aura(list) xavi.o.auras = list; fire(xavi, "UNIT_AURA", "player"); tick(xavi, 2) end
    aura({ { "Arcane Intellect", 1459, "party1", 1800 }, { "Renew", 139, "party1", 15 }, INNER, { "Soulstone Resurrection", 20707, "party1", 1800 } })
    aura({ { "Arcane Intellect", 1459, "party1", 1800 }, INNER, { "Soulstone Resurrection", 20707, "party1", 1800 } })
    local B = xavi.env.CuteDB.known.buffs
    assert(B["Arcane Intellect"] and B["Soulstone Resurrection"] and not B.Renew and not B["Inner Fire"] and V("buffs_missing") == 0, "Arcane Intellect and the Soulstone remembered, nothing missing")
    assert(B["Arcane Intellect"].times == 1, "a buff still on at the next look is no new time: " .. tostring(B["Arcane Intellect"].times))
    aura({ INNER })
    assert(V("buffs_missing") == 0, "one guild mate, once: remembered, not a raid buff yet")
    -- a second guild mate's Arcane Intellect makes it one; the Soulstone, cast once, never is
    xavi.o.party = { "Wynn", "Rona" }
    aura({ { "Arcane Intellect", 1459, "party2", 1800 }, INNER })
    aura({ INNER })
    assert(B["Arcane Intellect"].nfrom == 2 and V("buffs_missing") == 1, "two guild mates: the missing Arcane Intellect counts")
    -- three times from one guild mate makes one too
    for _ = 1, 3 do aura({ { "Mark of the Wild", 1126, "party1", 1800 }, INNER }); aura({ INNER }) end
    assert(B["Mark of the Wild"].times == 3 and B["Mark of the Wild"].nfrom == 1 and V("buffs_missing") == 2, "three times from Wynn: Mark of the Wild counts")
    xavi.env.CuteDB.settings.columns.prog = { buffs_missing = true }
    xavi.C.UI:Open("prog")
    local l0 = #lines
    hover(cellOf(rowOf(xavi, "Xavi"), "buffs_missing"))
    local tip = table.concat(lines, "\n", l0 + 1)
    assert(tip:find("Arcane Intellect | from 2 guild mates, 2 times", 1, true) and tip:find("Mark of the Wild | from 1 guild mate, 3 times", 1, true) and not tip:find("Soulstone", 1, true), "your own tooltip names them and why:\n" .. tip)
    -- alone outside an instance nothing is missing, and the tooltip says why
    xavi.o.party = nil
    fire(xavi, "GROUP_ROSTER_UPDATE")
    tick(xavi, 2)
    assert(V("buffs_missing") == 0, "solo: nothing missing")
    l0 = #lines
    hover(cellOf(rowOf(xavi, "Xavi"), "buffs_missing"))
    assert(table.concat(lines, "\n", l0 + 1):find("Counted in a group or an instance; you are in neither.", 1, true), "the solo tooltip")
    -- in an instance alone: counted again
    xavi.o.instance = "party"
    fire(xavi, "UNIT_AURA", "player")
    tick(xavi, 2)
    assert(V("buffs_missing") == 2, "in an instance: counted")
    -- two weeks with no guild mate's Mark of the Wild: forgotten
    B["Mark of the Wild"].last = B["Mark of the Wild"].last - 15 * 86400
    fire(xavi, "UNIT_AURA", "player")
    tick(xavi, 2)
    assert(V("buffs_missing") == 1 and not B["Mark of the Wild"] and B["Arcane Intellect"], "forgotten after two weeks unseen")
    xavi.o.instance = "none"
    xavi.env.CuteDB.settings.columns.prog = nil
    -- a saved record with 0.3.x's removed ids, and a policy naming them: kept, ignored, never shown
    wynn.env.CuteDB.roster["Oldtimer-Forever"] = { seen = EPOCH + wynn.clock, online = true, at = {}, stats = { level = 40, attune_mc = "2", attune_ony_a = "2210", rep = "4444444",
      keys = { [12344] = true }, world_buffs = { [22888] = true }, flask_on = true, pot_health = 5, pot_mana = 3, protpots = 2, raid_recipes = { [17635] = true }, shards = 9, totems = 4, poisons = 20 } }
    wynn.env.CuteDB.policy.vis.attune_mc = "self"
    wynn.env.CuteDB.settings.sort.prog = { id = "attune_mc", desc = true }
    wynn.env.CuteDB.settings.columns.prog = { attune_mc = true, keys = true, ready = true, ilvl = true }
    wynn.C.Roster:Changed()
    for _, page in ipairs({ "race", "prog", "shame", "game", "officers", "me", "settings" }) do
      wynn.C.UI:Open(page)
      local t = texts(wynn)
      for _, gone in ipairs({ "Molten", "Onyxia", "Attune", "World buffs", "Flask active", "Health potions", "Soul shards", "Raid recipes" }) do
        assert(not t:find(gone, 1, true), page .. " shows a removed stat: " .. gone)
      end
      check(wynn.C.UI.frame, "officer " .. page .. ", a record with removed ids")
    end
    wynn.C.UI:Open("prog")
    assert(shownHeaders(wynn) == 3, "a saved column of a removed stat is no column: " .. shownHeaders(wynn))
    wynn.env.CuteDB.settings.columns.prog = nil
    wynn.C.Comm:Full()
    tickAll(10)
    for _, c in ipairs({ wynn, xavi, rona }) do leave(c) end
  end)
  print("discovered: dungeon entries (a /reload and a run back none), bosses by ENCOUNTER_END and BOSS_KILL counted once, a raid, factions read once a second and by id when folded; the labels reach a member who never met them, UTF-8 whole, ; and | cleaned; the policy per category; raid buffs from two guild mates or three times from one, in a group or an instance, forgotten after two weeks; removed ids ignored; the new categories at both sizes")
end

-- 25: the budget at login with everything at once: 300 statistics, 40 bosses in 18 instances, 60 factions. The first
-- minute stays under twenty messages; the statistics, the discoveries and their labels follow, all of them across
do
  local function member(name, rank, class) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = "Raider", class = class, level = 50, online = true } end
  isolated({ member("Petra", 3, "MAGE"), member("Quinn", 3, "PRIEST") }, function()
    local factions = {}
    for i = 1, 60 do factions[i] = { 2100 + i, "Faction of the " .. i .. "th Shore", 4, 100 * i, 0, 3000 } end
    local labels, mine, inst, kind, counters = {}, {}, {}, {}, {}
    for i = 1, 18 do labels["i" .. (300 + i)] = "Instance " .. i .. " of the Deep"; mine["i" .. (300 + i)] = true; kind[300 + i] = "party"; counters["i" .. (300 + i)] = i end
    -- (each boss with the level of its first kill, and a dozen with the loot Petra saw drop: Rules.lua's evidence)
    local loot = {}
    for i = 1, 40 do
      local id = "e" .. (7000 + i); labels[id] = "Boss " .. i .. " the Unbowed"; mine[id] = true; inst[7000 + i] = 301 + (i % 18); counters[id] = 1 + i % 3
      counters["k" .. (7000 + i)] = 20 + i % 25
      if i <= 12 then loot[7000 + i] = { items = { [60000 + i] = EPOCH, [61000 + i] = EPOCH }, mine = { [60000 + i] = true, [61000 + i] = true } } end
    end
    local db = { chars = { ["Petra-Forever"] = { counters = counters } }, known = { labels = labels, mine = mine, inst = inst, kind = kind, loot = loot } }
    local petra = newClient(charOf({ "Petra", 3, "Raider", "MAGE", 50 }, { withStats = true, manyStats = 300, factions = factions }))
    local quinn = newClient(charOf({ "Quinn", 3, "Raider", "PRIEST", 50 }, { withStats = true, manyStats = 300, factions = {} }))
    login(petra, db); login(quinn)
    assert(#petra.C.Stats.byCat.found == 40 + 18 + 60, "Petra's discoveries defined at login: " .. #petra.C.Stats.byCat.found)
    tickAll(60)
    local first = #petra.sent
    assert(first < 20 and #quinn.sent < 20, "under twenty messages in the first minute: " .. first .. ", " .. #quinn.sent)
    tickAll(180)
    local rec = quinn.env.CuteDB.roster["Petra-Forever"]
    local n = { g = 0, e = 0, i = 0, f = 0, k = 0 }
    for id in pairs(rec.stats) do local p = id:match("^([gefik])%d+$"); if p then n[p] = n[p] + 1 end end
    -- (311 statistics, two of them never recorded or nought: nothing, Stats.lua S.Quantity)
    assert(n.g == 309 and n.e == 40 and n.i == 18 and n.f == 60 and n.k == 40, string.format("every value across: %d statistics, %d bosses, %d instances, %d factions, %d kill levels", n.g, n.e, n.i, n.f, n.k))
    local lootN = 0
    for enc in pairs(quinn.env.CuteDB.known.loot) do if enc > 7000 and enc <= 7012 then lootN = lootN + 1 end end
    assert(lootN == 12 and quinn.env.CuteDB.known.loot[7001].items[60001], "and the loot of the twelve bosses: " .. lootN)
    assert(#quinn.C.Stats.byCat.found == 40 + 18 + 60, "and every label: Quinn defined them all: " .. #quinn.C.Stats.byCat.found)
    local labelMsgs = msgs(petra, "1L")
    assert(#petra.oversize == 0 and labelMsgs >= 1 and #petra.sent < 80, "the whole login: " .. #petra.sent .. " messages, " .. labelMsgs .. " of labels")
    print(string.format("budget: 300 statistics, 40 bosses in 18 instances and 60 factions: %d messages in the first minute, %d in all (%d of labels), everything across", first, #petra.sent, labelMsgs))
    leave(petra); leave(quinn)
  end)
end

-- 26: the enchants are learned per slot and kind of item. Hela's and Arrow's scoped bows teach Ranged for bows, never
-- for a wand or a gun; Tanka's and Bulwark's enchanted shields teach Off hand for shields, never for a book held in the
-- off hand (two of each: one member's word teaches nothing, scenario 23). (0.4.0's first
-- build learned the slot alone: one scoped hunter made every wand user show Ranged missing and drop to "gaps", the
-- owner's head-and-shoulder complaint over again.) Everyone wears full gear, so an enchant is the only gap there is.
-- The officers open the gear gaps here, as in scenario 23, so the members learn from each other and Ready counts them
do
  local function member(name, rank, rankName, class) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rankName, class = class, level = 40, online = true } end
  local guild = { member("Hela", 1, "Officer", "HUNTER"), member("Magey", 3, "Raider", "MAGE"), member("Bowen", 3, "Raider", "HUNTER"), member("Tanka", 3, "Raider", "WARRIOR"),
    member("Prisca", 3, "Raider", "PRIEST"), member("Shieldo", 3, "Raider", "PALADIN"), member("Gunnar", 3, "Raider", "HUNTER"),
    member("Arrow", 3, "Raider", "HUNTER"), member("Bulwark", 3, "Raider", "WARRIOR") }
  isolated(guild, function()
    -- every slot worn (15.0, the default kind), plus what the scenario puts in the off hand and the ranged slot
    local function full(extra)
      local t = {}
      for _, s in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) do t[s] = "item:" .. (4000 + s) .. ":0" end
      for s, link in pairs(extra) do t[s] = link end
      return t
    end
    local who = {
      hela = newClient(charOf({ "Hela", 1, "Officer", "HUNTER", 40 }, { items = full({ [18] = "item:5018:30" }) })),          -- a scoped bow
      magey = newClient(charOf({ "Magey", 3, "Raider", "MAGE", 40 }, { items = full({ [17] = "item:6021:0", [18] = "item:6018:0" }) })), -- a book, a wand
      bowen = newClient(charOf({ "Bowen", 3, "Raider", "HUNTER", 40 }, { items = full({ [18] = "item:5018:0" }) })),        -- a bow, no scope
      tanka = newClient(charOf({ "Tanka", 3, "Raider", "WARRIOR", 40 }, { items = full({ [17] = "item:6020:20" }) })),      -- an enchanted shield
      prisca = newClient(charOf({ "Prisca", 3, "Raider", "PRIEST", 40 }, { items = full({ [17] = "item:6021:0", [18] = "item:6018:0" }) })),
      shieldo = newClient(charOf({ "Shieldo", 3, "Raider", "PALADIN", 40 }, { items = full({ [17] = "item:6020:0" }) })),   -- a shield, no enchant
      gunnar = newClient(charOf({ "Gunnar", 3, "Raider", "HUNTER", 40 }, { items = full({ [18] = "item:5019:0" }) })),      -- a gun: nobody has scoped one
      arrow = newClient(charOf({ "Arrow", 3, "Raider", "HUNTER", 40 }, { items = full({ [18] = "item:5018:30" }) })),        -- a scoped bow
      bulwark = newClient(charOf({ "Bulwark", 3, "Raider", "WARRIOR", 40 }, { items = full({ [17] = "item:6020:20" }) })),  -- an enchanted shield
    }
    for _, c in pairs(who) do login(c, gapsOpen(c == who.hela and "Hela-Forever")) end
    tickAll(45)
    local function missing(c) local v = c.C.Sample:Value("unenchanted"); local out = {}; for slot in pairs(v or {}) do out[#out + 1] = slot end table.sort(out); return table.concat(out, ",") end
    for name, c in pairs(who) do
      local k = c.env.CuteDB.known.enchant
      assert(k[18] and k[18].kinds["2.2"] and not k[18].kinds["2.19"] and not k[18].kinds["2.3"] and k[17] and k[17].kinds["4.6"] and not k[17].kinds["4.0"],
        name .. ": Ranged learned for bows only, Off hand for shields only")
    end
    for _, name in ipairs({ "magey", "prisca", "gunnar", "hela", "tanka", "arrow", "bulwark" }) do
      local c = who[name]
      assert(missing(c) == "" and c.C.Sample:Value("ready") == 2, name .. ": nothing to enchant that can be, ready: " .. missing(c) .. ", " .. tostring(c.C.Sample:Value("ready")))
    end
    assert(missing(who.bowen) == "18" and who.bowen.C.Sample:Value("ready") == 1, "Bowen's bow has no scope: " .. missing(who.bowen))
    assert(missing(who.shieldo) == "17" and who.shieldo.C.Sample:Value("ready") == 1, "Shieldo's shield has no enchant: " .. missing(who.shieldo))
    -- the hidden kinds travel and are kept, and show nowhere
    -- (0.5.0: with the enchant's id, which marks the seed's enchants the guild has as seen)
    assert(who.magey.env.CuteDB.roster["Hela-Forever"].stats.ench_kinds == "18:2.2:30", "Hela's kinds on Magey's roster: " .. tostring(who.magey.env.CuteDB.roster["Hela-Forever"].stats.ench_kinds))
    for _, def in ipairs(who.hela.C.Stats.list) do assert(def.id ~= "ench_kinds", "ench_kinds is in no list") end
    -- the officer sees Bowen's and Shieldo's on receipt, the tooltip by slot; Bowen's own names the kind he wears
    local hela = who.hela
    hela.env.CuteDB.settings.columns.prog = { ready = true, unenchanted = true }
    hela.C.UI:Open("prog")
    assert(cellOf(rowOf(hela, "Bowen"), "unenchanted").label:GetText() == "1" and cellOf(rowOf(hela, "Magey"), "unenchanted").label:GetText() == "0", "the officer's view: Bowen 1, Magey 0")
    local l0 = #lines
    hover(cellOf(rowOf(hela, "Bowen"), "unenchanted"))
    assert(table.concat(lines, "\n", l0 + 1):find("Ranged | seen on 2 members", 1, true), "the officer's tooltip:\n" .. table.concat(lines, "\n", l0 + 1))
    check(hela.C.UI.frame, "officer prog, enchants by kind")
    local bowen = who.bowen
    bowen.env.CuteDB.settings.columns.prog = { unenchanted = true }
    bowen.C.UI:Open("prog")
    l0 = #lines
    hover(cellOf(rowOf(bowen, "Bowen"), "unenchanted"))
    assert(table.concat(lines, "\n", l0 + 1):find("Ranged (Bows) | seen on 2 members", 1, true), "Bowen's own tooltip names the kind:\n" .. table.concat(lines, "\n", l0 + 1))
    -- two minutes on, the wand is still never asked for
    tickAll(120)
    assert(missing(who.magey) == "" and missing(who.prisca) == "", "a wand and a book never asked for")
    -- Bowen scopes his bow: nothing missing, and the guild has seen three scoped bows
    bowen.o.items[18] = "item:5018:30"
    fire(bowen, "UNIT_INVENTORY_CHANGED", "player")
    tickAll(6)
    assert(missing(bowen) == "" and hela.env.CuteDB.known.enchant[18].kinds["2.2"].n == 3, "Bowen scoped: three seen")
    for _, c in pairs(who) do leave(c) end
  end)
  print("enchants by kind: two scoped bows teach Ranged for bows and two shield enchants Off hand for shields; a wand, a gun and a book held in the off hand are never asked for, their wearers ready; an unscoped bow and a bare shield are, the officer sees them on receipt; the kinds travel hidden")
end

-- 27: the smaller rules. GET_ITEM_INFO_RECEIVED re-reads the gear and bag stats only for an item you wear or carry; a
-- client whose RegisterUnitEvent throws still hears UNIT_INVENTORY_CHANGED (every unit's, the unit check keeping
-- yours); a Fishing cast is known by its name, whatever its spell id; the improved healthstones count
do
  local c = newClient(charOf(NAMES[11], { counts = { [19005] = 1, [5512] = 1, [19013] = 2 } }))
  login(c)
  tick(c, 15)
  local S = c.C.Sample
  -- the item info filter
  local scheduled, real = {}, S.Schedule
  S.Schedule = function(self, id) scheduled[id] = (scheduled[id] or 0) + 1; return real(self, id) end
  fire(c, "GET_ITEM_INFO_RECEIVED", 99999, true)
  assert(not scheduled.ilvl and not scheduled.potions, "an item you neither wear nor carry re-reads nothing")
  fire(c, "GET_ITEM_INFO_RECEIVED", 1234, true)
  assert(scheduled.ilvl and scheduled.unenchanted, "a worn item's info re-reads the gear stats")
  fire(c, "GET_ITEM_INFO_RECEIVED", 118, true)
  assert(scheduled.potions, "a carried item's info re-reads the bag stats")
  S.Schedule = real
  -- fishing by name: Classic's rank id and another id both named Fishing count; a Fireball does not; nor does anything
  -- for a character without the skill
  local fish = S:Value("fish") or 0
  for _, id in ipairs({ 7620, 131474, 133 }) do
    fire(c, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
    fire(c, "LOOT_OPENED")
  end
  assert(S:Value("fish") == fish + 2, "two Fishing casts by name, not the Fireball: " .. tostring(S:Value("fish")))
  -- healthstones: the improved ranks a talented warlock conjures (Forever's own item list) count with the plain ones
  S:Read("stones")
  assert(S:Value("stones") == 4, "Minor, improved Minor and two improved Major: " .. tostring(S:Value("stones")))
  leave(c)
  local plain = newClient(charOf(NAMES[12], { skills = { { 186, "Mining", 150, 225 } } }))
  login(plain)
  tick(plain, 15)
  local before = plain.C.Sample:Value("fish") or 0
  fire(plain, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 7620)
  fire(plain, "LOOT_OPENED")
  assert((plain.C.Sample:Value("fish") or 0) == before, "no Fishing skill, no fish")
  leave(plain)
  -- RegisterUnitEvent throwing: the events are registered all the same, and another unit's still reads nothing
  local t = newClient(charOf(NAMES[13], { invLate = true, unitEventThrows = true }))
  login(t)
  local f = t.C.Sample.frame
  assert(f.__events.UNIT_INVENTORY_CHANGED and f.__events.UNIT_AURA and not (f.__units and f.__units.UNIT_INVENTORY_CHANGED), "registered for every unit")
  tick(t, 2) -- (the gear pass two seconds after the loading screen, before the inventory comes)
  t.invReady = true
  fire(t, "UNIT_INVENTORY_CHANGED", "party1")
  tick(t, 2)
  local empty = 0
  for _ in pairs(t.C.Sample:Value("empty_slots") or {}) do empty = empty + 1 end
  assert(empty == 15, "another unit's event reads nothing: " .. empty)
  fire(t, "UNIT_INVENTORY_CHANGED", "player")
  tick(t, 2)
  assert(t.clock < t.born + 10, "before the ten-second pass: " .. (t.clock - t.born))
  empty = 0
  for _ in pairs(t.C.Sample:Value("empty_slots") or {}) do empty = empty + 1 end
  assert(empty == 11, "yours reads the slots: " .. empty)
  leave(t)
  print("smaller rules: item info re-reads only for your own items; RegisterUnitEvent failing falls back to every unit's with the unit check; Fishing by name; the improved healthstones")
end

-- 28: the seed. With the fixture: read whole (its wings, optional boss and each main-hand enchant's kinds too), Rule 0
-- asks its fifty facts at login a frame's worth at a time (the Guide says it is checking until then) and finds none
-- absent, the states and their words are the seed's (beta, data), a one-handed sword is offered the weapon enchant and
-- never the two-hander's, /cute diag prints them. A partial seed is read for what it has, its boss without an
-- encounter id joining as the seed's when one of that name is killed there; one that names nothing is none. With no
-- seed: none, and /cute diag says so. The real Known.lua, where gen_known.py has written it: read whole, fresh against
-- a client that has what it names, no head or shoulder enchant and no Classic raid in it, neck enchants there, a dagger
-- never offered a two-hander's enchant nor a shield an off-hand's, a cloth bracer advice at 20 and missing at 30, the
-- Guide drawn with it for a member and an officer at both sizes
do
  local R = yezin.C.Rules
  if SEEDED then
    local s = R.Seed()
    assert(s and s.dungeons[36] and #s.dungeons[36].bosses == 4 and s.bosses[1234].inst == 36 and s.bosses[1234].loot[1] == FIX.loot[1234][1]
      and s.enchants[2].kinds["4.0"] and #s.enchants[9].list == 2 and s.xp[59] == FIX.xp[59] and s.factions[72].name == "Stormwind"
      and s.dungeons[129].wings and not s.dungeons[36].wings and s.bosses[1241].optional and not s.bosses[1240].optional
      and s.enchants[16].list[1].kinds["2.1"] and not s.enchants[16].list[1].kinds["2.7"] and s.enchants[9].list[1].kinds == nil, "the fixture read whole")
    assert(R.SeedState() == "fresh" and R.check.total == 50 and R.check.absent == 0, "Rule 0: fifty facts asked, none absent: " .. tostring(R.check.total))
    local m = R.Model()
    assert(m.dungeons[36].state == "beta" and m.dungeons[129].state == "data" and m.bosses[1250].state == "data" and m.xp[20].state == "beta"
      and m.xp[40].state == "data" and m.factions[69].state == "data" and m.dungeons[9001].new, "the seed's states: the beta's and research's")
    assert(R.Words(m.dungeons[129]) == "from research" and R.Words(m.dungeons[48]) == "seen in the beta", "in words")
    -- each enchant names the kinds it takes: a one-handed sword is offered the weapon enchant, never the two-hander's
    local function named(list) local out = {}; for _, x in ipairs(list) do out[#out + 1] = x.name end return table.concat(out, ", ") end
    assert(named((R.SlotEnchants(16, "2.7"))) == "Enchant Weapon - Minor Striking" and named((R.SlotEnchants(16, "2.1"))) == "Enchant 2H Weapon - Lesser Impact, Enchant Weapon - Minor Striking"
      and named((R.SlotEnchants(16))) == named((R.SlotEnchants(16, "2.1"))) and select(2, R.SlotEnchants(16, "2.15")) == 0, "the main hand's enchants by kind")
    -- Rule 0 a frame's worth at a time: at the loading screen it is still checking (and the seed counts for nothing),
    -- done a frame on
    local slow = newClient(charOf(NAMES[13], { items = { [1] = "item:1234:0", [9] = "item:6030:0" } }))
    slow.env.CuteDB = {}
    fire(slow, "ADDON_LOADED", "Cute")
    fire(slow, "PLAYER_ENTERING_WORLD", true, false)
    assert(slow.C.Rules.SeedState() == "checking" and slow.C.Rules.check.i == 50 and not slow.C.Stats.EnchantKnown(9), "fifty asked in the first frame, still checking: " .. slow.C.Rules.check.i)
    openGuide(slow)
    assert(texts(slow):find("Checking what we knew against this client, 50 of 50.", 1, true), "the Guide says it is checking, and how far it got:\n" .. texts(slow))
    check(slow.C.UI.frame, "member guide, checking")
    tick(slow, 1)
    assert(slow.C.Rules.SeedState() == "fresh" and slow.C.Stats.EnchantKnown(9, "4.1") and slow.C.Sample:Value("unenchanted")[9], "done a frame on: the seed's wrist now asks for an enchant")
    slow.C.UI:Draw()
    assert(tipOf(guideHead(slow)):find("From research and the beta, checked against this client", 1, true), "and the Guide's head says where its knowledge comes from")
    leave(slow)
    -- a partial seed: a dungeon without a range, one without a name, one whose range is upside down, a boss without an id,
    -- loot that is no id, an enchant slot past the gear, a recipe without a name, an XP value below zero
    local partial = newClient(charOf(NAMES[13], { seed = [[
local _, C = ...
C.Known = { build = "1.60.1.70338", dungeons = { [36] = { name = "The Deadmines", min = 18 }, [37] = { min = 20, max = 25 },
  [38] = { name = "Odd Hold", min = 30, max = 25, conf = "beta", bosses = { { name = "Nameless" }, { name = "Yorg", enc = 77, loot = { "a", 5 } } } } },
  enchants = { [40] = { list = {} }, [9] = { list = { { spell = "x" }, { spell = 7418, name = "Enchant Bracer - Minor Health" } } } }, xp = { [1] = 100, [2] = -5 } }
]] }))
    login(partial)
    local ps = partial.C.Rules.Seed()
    assert(ps.dungeons[36] and ps.dungeons[36].min == nil and not ps.dungeons[37] and ps.dungeons[38].min == 25 and ps.dungeons[38].max == 30
      and #ps.dungeons[38].bosses == 1 and #ps.bosses[77].loot == 1 and ps.bosses[77].loot[1] == 5 and ps.bosses[77].conf == "beta" and not ps.enchants[40]
      and #ps.enchants[9].list == 1 and ps.enchants[9].kinds == nil and ps.xp[1] == 100 and ps.xp[2] == nil, "a partial seed read for what it has")
    assert(partial.C.Rules.SeedState() == "fresh" and partial.C.Rules.check.total == 2, "Rule 0 asks what it names: " .. partial.C.Rules.check.total)
    -- the boss it names without an encounter id joins as the seed's when one of that name is killed there, not as new;
    -- once met, the dungeon is shown by the name this game gives it, the seed's kept for its tooltip
    partial.C.Stats.Label("i38", "The Odd Hold", true, nil, "party")
    partial.C.Stats.Label("e900", "Nameless", true, 38)
    -- (a kill a group mate named back, rule 9: a label alone joins nothing)
    assert(not partial.C.Rules:Rebuild().bosses[900], "a label and no corroborated kill: nothing joins")
    local mate = guidOf("Mate")
    partial.C.Char().counters.e900 = 1
    partial.C.Rules.Claim(partial.o.guid, 900, EPOCH, { [mate] = true })
    partial.C.Rules.Claim(mate, 900, EPOCH + 5, { [partial.o.guid] = true })
    local pm = partial.C.Rules:Rebuild()
    assert(pm.bosses[900] and pm.bosses[900].seeded and pm.bosses[900].state == "seen" and pm.bosses[900].n == 1 and pm.dungeons[38].name == "The Odd Hold" and pm.dungeons[38].seedName == "Odd Hold",
      "a seeded boss without an id met by name, seen by the one who killed it, the dungeon named as the game names it: " .. tostring(pm.bosses[900] and pm.bosses[900].state))
    for _, ch in ipairs(partial.C.Rules.Changes()) do assert(not ch.what:find("Nameless", 1, true) and not ch.what:find("Odd Hold", 1, true), "nothing new: " .. ch.what) end
    openGuide(partial)
    check(partial.C.UI.frame, "member guide, a partial seed")
    leave(partial)
    local blank = newClient(charOf(NAMES[13], { seed = "local _, C = ...\nC.Known = { v = 1, dungeons = {} }" }))
    login(blank)
    assert(blank.C.Rules.Seed() == nil and blank.C.Rules.SeedState() == "none", "a seed that names nothing is none")
    leave(blank)
  else
    assert(R.Seed() == nil and R.SeedState() == "none" and R.check.state == "done", "no seed: none")
  end
  local n0 = #yezin.chat
  yezin.env.SlashCmdList.CUTE("diag")
  local out = table.concat(yezin.chat, "\n", n0 + 1)
  assert(out:find(SEEDED and "diag seed: fresh | build 1.60.1.70338 (this client too) | absent: items 0 of 39, enchants 0 of 6, factions 0 of 5 | data " or "diag seed: none shipped", 1, true), "/cute diag:\n" .. out)
  -- the real Known.lua
  local realNote = "not there yet (gen_known.py writes it); the fixture stands in"
  local f = SEEDED and io.open(REAL_KNOWN) or nil
  if f then
    local src = f:read("*a")
    f:close()
    local build = src:match('build%s*=%s*"([^"]+)"')
    -- (both in a cloth bracer; the officer at 30 with a dagger in the main hand and a shield in the off hand)
    local real = newClient(charOf(NAMES[13], { seed = "real", build = build, allFactions = true, level = 20,
      items = { [1] = "item:1234:0", [5] = "item:1235:2", [9] = "item:6030:0" } }))
    local boss = newClient(charOf(NAMES[3], { seed = "real", build = build, allFactions = true, level = 30,
      items = { [1] = "item:1234:0", [5] = "item:1235:2", [9] = "item:6030:0", [16] = "item:6022:0", [17] = "item:6020:0" } }))
    login(real); login(boss)
    local RR = real.C.Rules
    local rs = RR.Seed()
    assert(rs and type(real.C.Known) == "table", "the real Known.lua loads")
    local nd, nb, ni = 0, 0, 0
    for _, d in pairs(rs.dungeons) do
      nd = nd + 1
      assert(not d.name:find("Molten Core", 1, true) and not d.name:find("Onyxia", 1, true), "no Classic raid in the seed: " .. d.name)
    end
    for _ in pairs(rs.bosses) do nb = nb + 1 end
    for _ in pairs(rs.items) do ni = ni + 1 end
    assert(nd > 0, "the real seed names dungeons")
    assert(not rs.enchants[1] and not rs.enchants[3] and rs.enchants[2], "neck enchants, and no head or shoulder enchant")
    assert(RR.SeedState() == "fresh", "fresh against a client that has what it names: " .. tostring((select(2, RR.SeedState()))))
    -- the enchants a worn item is offered take its kind: a dagger never a two-hander's, a shield never an off-hand's
    -- (where the seed names no kinds per enchant, a hand slot's are counted and not named)
    for _, x in ipairs((RR.SlotEnchants(16, "2.15"))) do assert(not x.name:find("2H", 1, true), "a dagger offered " .. x.name) end
    for _, x in ipairs((RR.SlotEnchants(17, "4.6"))) do assert(not x.name:find("Off-Hand", 1, true), "a shield offered " .. x.name) end
    local _, unplaced = RR.SlotEnchants(16, "2.15")
    assert(#(RR.SlotEnchants(16, "2.15")) + unplaced > 0, "the main hand's enchants named or counted for a dagger")
    -- the research's slots count from the enchant level: the bracer at 20 is advice, at 30 it is missing
    assert(not real.C.Sample:Value("unenchanted")[9] and boss.C.Sample:Value("unenchanted")[9] and boss.C.Sample:Value("unenchanted")[16]
      and boss.C.Sample:Value("unenchanted")[17], "under 30 the research's wrist is not missing; at 30 the wrist, the dagger and the shield are")
    -- (the research's slots under the enchant level were the Guide's advice row; 0.7.0's page is the pick alone, and
    -- the fact stands in the rules: the cloth wrist is one the seed can enchant, counted as missing from level 30)
    assert(RR.SeedEnchantable(9, "4.1") and not RR.SeedEnchantable(9, "4.1", 20) and RR.SeedEnchantable(9, "4.1", 30), "under 30 the research's wrist is advice, not missing: counted from 30")
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      for _, c in ipairs({ real, boss }) do
        c.C.UI:Build()
        c.C.UI.frame:SetSize(size[1], size[2])
        openGuide(c)
        check(c.C.UI.frame, string.format("%s guide, the real seed, %dx%d", c == boss and "officer" or "member", size[1], size[2]))
        for _, l in ipairs(c.C.UI.lists.guide.items) do if l:IsShown() then hover(l) end end
        c.C.UI.frame:SetSize(1040, 640)
      end
    end
    realNote = string.format("%d dungeons, %d bosses, %d items, fresh; a dagger and a shield offered only what takes them; its wrist advice at 20, missing at 30; the Guide drawn with it at both sizes", nd, nb, ni)
    leave(real); leave(boss)
  end
  print(SEEDED and ("seed: the fixture read whole, its wings, optional boss and enchant kinds too, and checked a frame's worth at a time (the Guide checking until then), a partial seed read for what it has, its boss without an id met by name, an empty one none; the real Known.lua: " .. realNote)
    or "seed: none, and every rule runs on the guild's play")
end

-- 29: Rule 0 at its edges (with the seed). Fifteen of the fifty facts absent is 30 %, not over the share: fresh, with
-- the absent loot, recipes and factions marked so (a slot whose recipes are all absent asks for nothing); sixteen is
-- over: stale. A client lacking over 40 % of the seed's items (17 of 39): stale, and nothing from the seed counts as missing (a cloth
-- bracer the fresh seed asks an enchant for is not asked for), the Guide says the game differs and runs on the guild's
-- play: the Deadmines met through one boss, For you names that boss alone as left and the officers' line counts one of
-- one; an officer's staleShare of 45 % makes it fresh again. Another build of the same major version, a minor one
-- (1.60.1 to 1.60.2) or a new minor version (1.61): fresh while what it names is there, the beta's facts read as
-- research. Another major version: stale, whatever is there
if SEEDED then isolated({ { name = "Rulo-Forever", guid = guidOf("Rulo"), rank = 1, rankName = "Officer", class = "MAGE", level = 40, online = true },
  { name = "Sablewing-Forever", guid = guidOf("Sablewing"), rank = 3, rankName = "Raider", class = "HUNTER", level = 35, online = true } }, function()
  local function lacking(n) local t = {}; for i = 1, n do t[FIX.items[i]] = true end return t end
  local bracer = { [1] = "item:1234:0", [5] = "item:1235:2", [9] = "item:6030:0" }
  local function client(o) o.items = o.items or bracer; o.level = o.level or 35; local c = newClient(charOf(NAMES[13], o)); login(c); return c end
  local fresh = client({ lackItems = lacking(10), lackFactions = { [69] = true, [589] = true }, lackSpells = { [7428] = true, [13378] = true, [27001] = true } })
  local R = fresh.C.Rules
  assert(R.check.absent == 15 and R.check.total == 50 and R.SeedState() == "fresh", "15 of 50 absent is 30 %: fresh: " .. R.check.absent)
  local m = R.Model()
  assert(m.bosses[1230].loot[FIX.loot[1230][1]] == "absent" and m.bosses[1238].loot[FIX.loot[1238][3]] == "beta" and m.factions[69].state == "absent" and m.factions[72].state == "seen",
    "the absent loot and factions marked, the rest the seed's (Stormwind seen: it is on this character's list)")
  assert(R.SlotState(2) == "absent" and R.SlotState(17) == "absent" and R.SlotState(9) == "beta", "a slot whose recipes are all absent is absent; the wrist keeps one")
  local list = R.SlotEnchants(9)
  assert(#list == 2 and list[1].name == "Enchant Bracer - Minor Deflection" and list[1].state == "absent" and list[2].state == "beta", "the wrist's recipes, the absent one marked")
  assert(fresh.C.Sample:Value("unenchanted")[9], "the fresh seed asks the cloth bracer for an enchant")
  local over = client({ lackItems = lacking(16) })
  local st, why = over.C.Rules.SeedState()
  assert(st == "stale" and why == "32% of what it names is not in this client (items 16 of 39, enchants 0 of 6, factions 0 of 5)", "16 of 50: stale: " .. tostring(why))
  -- over 40 % of the seed's items (17 of 39): stale, and the seed counts as nothing
  local forty = client({ lackItems = lacking(17) })
  local F = forty.C.Rules
  assert(F.SeedState() == "stale" and not forty.C.Sample:Value("unenchanted")[9] and not forty.C.Stats.EnchantKnown(9, "4.1"), "a stale seed asks for no enchant")
  assert(F.Model().dungeons[36].state == "stale" and F.Words(F.Model().bosses[1230]) == "from research this game no longer matches", "every seeded fact stale")
  local now, soon = F.DungeonsFor(20)
  assert(#now == 0 and #soon == 0, "and recommends nothing")
  openGuide(forty)
  assert(tipOf(guideHead(forty)):find("The game differs from what we knew; learning from the guild.", 1, true), "the Guide's head says so:\n" .. tipOf(guideHead(forty)))
  for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
    forty.C.UI.frame:SetSize(size[1], size[2])
    openGuide(forty)
    check(forty.C.UI.frame, string.format("member guide, a stale seed, %dx%d", size[1], size[2]))
  end
  forty.C.UI.frame:SetSize(1040, 640)
  -- a stale seed's bosses are neither left nor counted: the Deadmines met through one boss (Rhahk'Zor, killed by two
  -- members at 35 in one group, each naming the other: rule 9), For you names that boss alone, the officers' line
  -- counts one of one and its tooltip names no other (the first 0.5.0 build listed the seed's other three as left and
  -- counted "1 of 4")
  forty.env.CuteDB.roster["Run1-Forever"] = { stats = { guid = "Player-9-0000RUN1", level = 35, e1230 = 1, k1230 = 35 }, at = {}, seen = forty.C.Now() }
  forty.env.CuteDB.roster["Run2-Forever"] = { stats = { guid = "Player-9-0000RUN2", level = 35, e1230 = 1, k1230 = 35 }, at = {}, seen = forty.C.Now() }
  listed(forty, { { "Run1-Forever", "Player-9-0000RUN1", 35 }, { "Run2-Forever", "Player-9-0000RUN2", 35 } })
  F.Claim("Player-9-0000RUN1", 1230, EPOCH, { ["Player-9-0000RUN2"] = true })
  F.Claim("Player-9-0000RUN2", 1230, EPOCH + 3, { ["Player-9-0000RUN1"] = true })
  F:Rebuild()
  assert(F.Model().dungeons[36].state == "seen" and F.Model().dungeons[36].min == 35 and F.Model().bosses[1236].state == "stale", "the Deadmines met, its other bosses still stale")
  local rows, dmCard = cardOf(forty, "The Deadmines", true)
  assert(dmCard, "the Deadmines in range, met")
  local left, quests = rows[2], rows[3]
  assert(quests and quests.kind ~= "quests", "a stale seed's quests are neither listed nor counted: " .. tostring(quests and quests.name))
  assert(left and left.kind == "bosses" and #left.pips == 1 and left.pips[1].name == "Rhahk'Zor" and left.pips[1].state == "left" and left.who == "1 left",
    "the card's pips name the met boss alone: " .. tostring(left and left.pips and #left.pips))
  assert(dmCard.known == 1 and (F.Model().bosses[1230].n or 0) > 0, "the guild's count: one boss known, killed by the guild: " .. tostring(dmCard.known))
  local said = tipText(rows[1].tip)
  assert(said:find("Rhahk'Zor", 1, true) and not said:find("Glubtok", 1, true) and not said:find("Edwin VanCleef", 1, true), "its tooltip names the met boss alone:\n" .. said)
  forty.C.UI.frame:SetSize(760, 420)
  openGuide(forty)
  check(forty.C.UI.frame, "member guide, a stale seed, the Deadmines met, 760x420")
  forty.C.UI.frame:SetSize(1040, 640)
  -- an officer's staleShare of 45 %: fresh again, and the bracer is asked for once more
  local at = math.floor(EPOCH + forty.clock) + 30
  assert(forty.C.Policy:Receive("Rulo-Forever", at, 1, "r_staleshare=0.45:" .. guidOf("Rulo")), "the officer's rule applied")
  -- (Guild Info empty here: no line from a read eleven seconds after the ask ten seconds on, then the word applies)
  tick(forty, 24)
  assert(F.Get("staleShare") == 0.45 and F.SeedState() == "fresh" and forty.C.Sample:Value("unenchanted")[9], "fresh again under the officer's share")
  -- another build of the same major version: fresh, the beta's facts as research; another major version: stale
  local later = client({ build = "1.60.1.70450" })
  local L = later.C.Rules
  assert(L.SeedState() == "fresh" and L.BetaAsData() and L.Model().dungeons[36].state == "data" and L.Model().xp[20].state == "data" and L.SlotState(9) == "data",
    "another build: the beta's facts read as research")
  openGuide(later)
  assert(tipOf(guideHead(later)):find("This client is 1.60.1.70450: what the beta showed counts as research until the guild sees it.", 1, true), "the head's source says so in its tooltip")
  check(later.C.UI.frame, "member guide, another build")
  local minor = client({ build = "1.61.0.71000" })
  assert(minor.C.Rules.SeedState() == "fresh" and minor.C.Rules.BetaAsData() and minor.C.Rules.Model().dungeons[36].state == "data",
    "a new minor version with nothing absent: fresh, the beta's facts as research")
  local newer = client({ build = "2.0.0.80000" })
  st, why = newer.C.Rules.SeedState()
  assert(st == "stale" and why == "this client is build 2.0.0.80000, the research 1.60.1.70338, another major version", "another major version: stale: " .. tostring(why))
  for _, c in ipairs({ fresh, over, forty, later, minor, newer }) do leave(c) end
  print("rule 0: 30 % absent fresh, the absent facts marked; over it stale; over 40 % of the items stale with nothing from the seed counted and the Guide saying so (the Deadmines met through one boss two members killed together: that boss alone left, one of one counted), fresh again under an officer's 45 %; another build or minor version reads the beta as research; another major version stale")
end) end

-- 30: the rules learn from the guild's play, at their edges, and the Guide shows it. A guild of an officer (Ruler, 26)
-- and six, who kill in groups, each kill named back by a group mate (rule 9): four kill Rhahk'Zor in the Deadmines at
-- 18, 19, 20 and 22 (the seed's 18-23 stands; with no seed the levels seen do, and say so), Ed's at 30, with Ada on
-- her second run, makes five: the 10th to 90th percentile sets one aside at either end, 19-22, and the kill at 30
-- stretches nothing. Ada opens a bag's container and loots a trash corpse of greys within the minute, neither the
-- boss's; then his, and Cy his too: the seed's item and a new one are seen by two, a grey is no loot; four kills leave
-- the unseen loot plain, six note it. Two full runs that miss Mr. Smite leave him; the third doubts him. Fen and Ed
-- kill two bosses in Krol'dok Stronghold, past the beta's cap with none seeded: they join under it, a world boss joins
-- nothing.
-- Two members agree on level 31's XP: the seed's stands; the third replaces it. A cloth bracer is asked for an enchant
-- at 30 (the seed's wrist), not at 19; thirteen days of a member at 30 wearing one leaves it, fourteen doubt the slot
-- and it is asked for no more; a member at 29 starts no clock. The Guide's ranges and Next up at their edges. Ruler
-- retunes rangeMembers to 4 in Settings (the values whole at 760 wide) and broadcasts: the members apply it,
-- Blackfathom's four kills learn its range, /cute rules says who; a member's own rules, and an officer's out of bounds,
-- change nothing. The Guide for a member and the officer, at both sizes
do
  local function member(name, rank, class, level) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank == 1 and "Officer" or "Raider", class = class, level = level, online = true } end
  local guild = { member("Ruler", 1, "PALADIN", 26), member("Ada", 3, "WARRIOR", 18), member("Bo", 3, "MAGE", 19), member("Cy", 3, "PRIEST", 20), member("Di", 3, "ROGUE", 22),
    member("Ed", 3, "HUNTER", 30), member("Fen", 3, "DRUID", 34) }
  isolated(guild, function()
    local wrist = { [1] = "item:1234:0", [5] = "item:1235:2", [7] = "item:1236:0", [16] = "item:1240:0", [9] = "item:6030:0" }
    local function make(name, rank, class, level, extra)
      local o = { items = wrist }
      for k, v in pairs(extra or {}) do o[k] = v end
      return newClient(charOf({ name, rank, rank == 1 and "Officer" or "Raider", class, level }, o))
    end
    local ruler, ada, bo, cy, di, ed, fen = make("Ruler", 1, "PALADIN", 26), make("Ada", 3, "WARRIOR", 18, { items = { [1] = "item:1234:0" } }), make("Bo", 3, "MAGE", 19),
      make("Cy", 3, "PRIEST", 20), make("Di", 3, "ROGUE", 22, { items = { [1] = "item:1234:0" } }), make("Ed", 3, "HUNTER", 30), make("Fen", 3, "DRUID", 34, { items = { [1] = "item:1234:0" } })
    local all = { ruler, ada, bo, cy, di, ed, fen }
    for _, c in ipairs(all) do login(c) end
    tickAll(45)
    local R = ruler.C.Rules
    local function settle() tickAll(35) end -- (a kill, its claims and the model built again: at most once in thirty seconds, Rules.lua R:Dirty)
    local function enter(c, kind, id, name) c.o.instance, c.o.instanceID, c.o.instName = kind, id, name; fire(c, "PLAYER_ENTERING_WORLD", false, false) end
    local function kill(c, enc, name) fire(c, "ENCOUNTER_END", enc, name, 1, 5, 1, {}) end
    -- a group: each in the others' party (UnitGUID of party1-4, which rule 9's claims name)
    local function group(list) for _, c in ipairs(list) do local p = {}; for _, x in ipairs(list) do if x ~= c then p[#p + 1] = x.o.name end end c.o.party = p end end
    local function dm() return R.Model().dungeons[36] end
    -- rule 3: four members kill Rhahk'Zor together; Ada and Cy loot him (rule 8)
    group({ ada, bo, cy, di })
    for _, c in ipairs({ ada, bo, cy, di }) do enter(c, "party", 36, "The Deadmines"); kill(c, 1230, "Rhahk'Zor") end
    tick(ada, 20)
    -- a container opened from the bags (isFromItem), and a trash corpse of greys: neither is the boss's, nor takes its place
    ada.lootWindow = { { 50020, 3 } }
    fire(ada, "LOOT_OPENED", false, true)
    ada.lootWindow = { { 50021, 0 } }
    fire(ada, "LOOT_OPENED", false, false)
    ada.lootWindow = { { FIX.loot[1230][1], 3 }, { 50001, 2 }, { 50002, 0 }, { 50003, 4, 1 } } -- the seed's, a new one, a grey, a currency
    fire(ada, "LOOT_OPENED", false, false)
    ada.lootWindow = nil
    settle()
    assert(not R.Model().bosses[1230].loot[50001], "one member's window: a first voice, no loot seen yet")
    cy.lootWindow = { { FIX.loot[1230][1], 3 }, { 50001, 2 } }
    fire(cy, "LOOT_OPENED", false, false)
    cy.lootWindow = nil
    settle()
    local d = dm()
    if SEEDED then assert(d.range == "seed" and d.min == 18 and d.max == 23 and d.levels == 4, "four members: the seed's range stands: " .. tostring(d.range))
    else assert(d.range == "seen" and d.min == 18 and d.max == 22 and R.RangeWords(d) == "18-22" and select(2, R.RangeWords(d)) == "killed at these levels by 4 members", "four members, no seed: the levels seen") end
    local rz = R.Model().bosses[1230]
    assert(rz.state == "seen" and rz.n == 4 and R.Words(rz) == "seen by 4 members" and rz.kills == 4, "rule 1: seen by four, four kills")
    assert(rz.loot[50001] == "seen" and rz.loot[50002] == nil and rz.loot[50003] == nil and ruler.env.CuteDB.known.loot[1230].items[50001], "rule 8: the loot window's items reached the officer, the grey and the currency left out")
    assert(not rz.loot[50020] and not rz.loot[50021], "a container from the bags and a corpse of greys are no boss's loot, and leave its window to come")
    if SEEDED then assert(rz.loot[FIX.loot[1230][1]] == "seen" and rz.loot[FIX.loot[1230][2]] == "beta" and not rz.lootQuiet, "the seed's item seen, the rest the beta's; four kills note nothing") end
    -- a loot window later than the minute, or a second one, is no boss's
    tick(bo, 61)
    bo.lootWindow = { { 50009, 3 } }
    fire(bo, "LOOT_OPENED", false, false)
    tick(ada, 1)
    ada.lootWindow = { { 50010, 3 } }
    fire(ada, "LOOT_OPENED", false, false)
    ada.lootWindow = nil
    -- alone, a kill teaches nothing: no group mate names it back
    enter(ed, "party", 36, "The Deadmines"); kill(ed, 1230, "Rhahk'Zor")
    settle()
    assert(dm().levels == 4 and R.Model().bosses[1230].n == 4, "Ed's kill alone: still four: " .. tostring(dm().levels))
    -- the fifth: Ed again, with Ada on her second run
    group({ ada, ed })
    kill(ed, 1230, "Rhahk'Zor"); kill(ada, 1230, "Rhahk'Zor")
    settle()
    d = dm()
    assert(d.range == "learned" and d.min == 19 and d.max == 22 and d.levels == 5 and select(2, R.RangeWords(d)) == "learned from 5 members",
      "five members: the 10th to 90th percentile, one level set aside at either end, so the kill at 30 stretches nothing: " .. tostring(d.min) .. "-" .. tostring(d.max))
    rz = R.Model().bosses[1230]
    assert(not rz.loot[50009] and not rz.loot[50010], "a window after the minute, or a second one, is no boss's")
    if SEEDED then assert(rz.lootQuiet and rz.kills == 7, "seven kills, Ed's two and Ada's second: the unseen loot noted: " .. tostring(rz.kills)) end
    -- rule 4: full runs (every boss the guild met there: Rhahk'Zor, Glubtok, Edwin) that never met Mr. Smite
    group({ ada, bo, cy, di })
    for _, c in ipairs({ ada, bo }) do kill(c, 1236, "Glubtok"); kill(c, 1234, "Edwin VanCleef") end
    settle()
    local smite = R.Model().bosses[1238]
    if SEEDED then assert(smite.state == "beta" and smite.runs == 2, "two full runs: Mr. Smite stands: " .. tostring(smite.state)) else assert(smite == nil, "no seed: Mr. Smite is not known") end
    kill(cy, 1236, "Glubtok"); kill(cy, 1234, "Edwin VanCleef")
    settle()
    smite = R.Model().bosses[1238]
    if SEEDED then assert(smite.state == "doubted" and smite.runs == 3 and R.Words(smite) == "doubted: not seen in 3 runs", "three: doubted: " .. tostring(smite.state)) end
    -- rule 2: Krol'dok Stronghold, past the beta's cap, no bosses seeded: Fen's and Ed's kills join under it; a world boss
    -- nowhere
    group({ fen, ed })
    for _, c in ipairs({ fen, ed }) do enter(c, "party", 9001, "Krol'dok Stronghold"); kill(c, 9101, "Krol'dok the Brute"); kill(c, 9102, "Shaman Vrakk") end
    for _, c in ipairs({ fen, ed }) do enter(c, "none", 0, nil); kill(c, 9200, "Azuregos") end
    settle()
    local kd = R.Model().dungeons[9001]
    assert(kd and kd.name == "Krol'dok Stronghold" and #kd.bosses == 2 and R.Model().bosses[9101].inst == 9001 and R.Model().bosses[9102].state == "seen"
      and not R.Model().bosses[9101].seeded and not R.Model().dungeons[0] and not R.Model().bosses[9200], "the bosses joined under the right instance, the world boss under none")
    assert(kd.seeded == SEEDED and (SEEDED and kd.range == "seed" and kd.min == 32 or kd.range == "seen" and kd.min == 30 and kd.max == 34), "its range: the seed's, or the levels seen")
    -- the Guide's lists at their edges (by the ranges learned: the Deadmines 19-22, the seed's Blackfathom 24-32 and
    -- Krol'dok 32-38): For you holds the dungeons whose range holds your level, Next up the ones opening within five
    local function names(list) local out = {}; for _, x in ipairs(list) do out[#out + 1] = x.name end return table.concat(out, ",") end
    local now, soon = R.DungeonsFor(22)
    assert(names(now):find("The Deadmines", 1, true), "22 is the Deadmines' top: in: " .. names(now))
    now = R.DungeonsFor(23)
    assert(not names(now):find("The Deadmines", 1, true), "23 is past it: " .. names(now))
    now, soon = R.DungeonsFor(18)
    assert(not names(now):find("The Deadmines", 1, true) and names(soon):find("The Deadmines", 1, true), "18 is under it: next up: " .. names(now) .. " / " .. names(soon))
    if SEEDED then
      -- (Krol'dok opens at 32: five levels on from 27, six from 26)
      now, soon = R.DungeonsFor(26)
      assert(not names(soon):find("Krol", 1, true) and not names(now):find("Krol", 1, true), "26: Krol'dok six levels on: not yet: " .. names(soon))
      now, soon = R.DungeonsFor(27)
      assert(names(soon) == "Krol'dok Stronghold", "27: Krol'dok opens within five levels: " .. names(soon))
    end
    -- rule 5 and 4: the cloth bracer is asked for an enchant where the seed has the wrist, from the enchant level (Ed at
    -- 30, not Bo at 19); the clock starts with a member at 30 wearing one (Ed), never with one at 29
    local K = ed.env.CuteDB.known
    if SEEDED then
      assert(ed.C.Sample:Value("unenchanted")[9] and R.SlotState(9) == "beta", "the seed's wrist: the bracer asked for an enchant at 30")
      assert(not bo.C.Sample:Value("unenchanted")[9] and next(bo.C.Sample:Value("unenchanted")) == nil, "at 19 only what the guild has enchanted is: nothing")
      assert(K.watch[9], "the clock started: Ed, at 30, wears one")
      -- (the level the guild roster gives: the server's word)
      ruler.env.CuteDB.known.watch[9] = nil
      ed.o.level = 29
      fire(ruler, "GUILD_ROSTER_UPDATE")
      R:Rebuild()
      assert(ruler.env.CuteDB.known.watch[9] == nil, "a member at 29 starts no clock")
      ed.o.level = 30
      fire(ruler, "GUILD_ROSTER_UPDATE")
      R:Rebuild()
      assert(ruler.env.CuteDB.known.watch[9], "at 30 it does")
      local t0 = ed.C.Now()
      K.watch[9] = t0 - 13 * 86400
      ed.C.Sample:Read("unenchanted")
      assert(ed.C.Sample:Value("unenchanted")[9] and ed.C.Rules.SlotState(9) == "beta", "thirteen days: still asked for")
      K.watch[9] = t0 - 14 * 86400
      ed.C.Sample:Read("unenchanted")
      assert(not ed.C.Sample:Value("unenchanted")[9] and ed.C.Rules.SlotState(9) == "doubted", "fourteen: the wrist doubted, asked for no more")
      K.watch[9] = t0
      ed.C.Sample:Read("unenchanted")
    else
      assert(not ed.C.Sample:Value("unenchanted")[9], "no seed: nobody has a wrist enchant, so none is asked for")
    end
    -- rule 6: Di, Ed and Fen reach 31, where the XP to 32 is 43000 (the seed says otherwise); two agree, then three
    local function ding(c) c.o.level, c.o.xp, c.o.xpmax = 31, 0, 43000; fire(c, "PLAYER_LEVEL_UP", 31); tickAll(130) end
    ding(di); ding(ed)
    R:Rebuild()
    local x = R.Model().xp[31]
    if SEEDED then assert(x.v == FIX.xp[31] and x.state == "data", "two agree: the seed's stands: " .. tostring(x.v))
    else assert(x.v == 43000 and x.state == "seen" and x.n == 2, "no seed: what the members reported") end
    ding(fen)
    R:Rebuild()
    x = R.Model().xp[31]
    assert(x.v == 43000 and x.state == "seen" and x.n == 3, "three agree: their value: " .. tostring(x.v))
    assert(R.XPCurve()[31].v == 43000, "and the curve runs on it")
    -- XP: members gain some, for the pace
    for i, c in ipairs({ ada, bo, cy }) do c.o.xp = 350 + 50 * i end
    tickAll(130)
    for i, c in ipairs({ ada, bo, cy }) do c.o.xp = 350 + 100 * i end
    tickAll(130)
    -- Blackfathom: four kill Ghamoo-ra; with rangeMembers 5 its range is not learned
    group({ ada, bo, cy, ed })
    for _, c in ipairs({ ada, bo, cy, ed }) do enter(c, "party", 48, "Blackfathom Deeps"); kill(c, 1240, "Ghamoo-ra") end
    settle()
    assert(R.Model().dungeons[48].range ~= "learned", "four kills: not learned at five")
    -- the officer retunes rangeMembers to 4 in Settings, and broadcasts
    ruler.C.UI:Open("settings", "rules")
    local minus
    for _, b in ipairs(ruler.frames) do
      if b.__kind == "Button" and b:IsVisible() and b.label and b.label:GetText() == "-" and b.__scripts.OnEnter then
        local n0 = #lines
        hover(b)
        if table.concat(lines, "\n", n0 + 1):find("Members to learn a range", 1, true) then minus = b end
      end
    end
    assert(minus and not minus.__disabled, "the officer's step down for rangeMembers")
    press(minus)
    assert(R.Get("rangeMembers") == 4 and R.SetBy("rangeMembers") == ruler.o.guid, "set here, by the officer")
    -- a step back up to the default clears the officers' setting (0.5.0's first cut kept it set to the default's value)
    local plus
    for _, b in ipairs(ruler.frames) do
      if b.__kind == "Button" and b:IsVisible() and b.label and b.label:GetText() == "+" and b.__scripts.OnEnter then
        local n0 = #lines
        hover(b)
        if table.concat(lines, "\n", n0 + 1):find("Members to learn a range", 1, true) then plus = b end
      end
    end
    assert(plus, "the officer's step up for rangeMembers")
    press(plus)
    assert(R.Get("rangeMembers") == R.RULES.rangeMembers and R.SetBy("rangeMembers") == nil, "back at the default, the setting is cleared")
    press(minus)
    assert(R.Get("rangeMembers") == 4 and R.SetBy("rangeMembers") == ruler.o.guid, "set again")
    check(ruler.C.UI.frame, "officer settings, a rule retuned")
    -- at the narrowest window every rule's value shows whole beside its buttons (a label may be cut, never the number)
    local function ruleValues()
      GEN = GEN + 1
      local out = {}
      for _, o in everything() do
        if o.__kind == "FontString" and o.__shown and visible(o) and o.__parent and o.__parent.__client == ruler and o.__justify == "RIGHT" and o.__w == 44 then out[#out + 1] = o end
      end
      table.sort(out, function(a, b) return rectOf(a).t > rectOf(b).t end)
      local texts = {}
      for _, o in ipairs(out) do texts[#texts + 1] = o.__text end
      return table.concat(texts, ",")
    end
    -- (the Guide's two in its own section, the rest under Rules)
    local want, wantGuide = {}, {}
    for _, t in ipairs(R.TUNE) do if t[8] then wantGuide[#wantGuide + 1] = R.Show(t[1]) else want[#want + 1] = R.Show(t[1]) end end
    assert(#wantGuide == 2, "the Guide's two thresholds")
    ruler.C.Modules.Set("guide", true)
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      ruler.C.UI.frame:SetSize(size[1], size[2])
      ruler.C.UI:Open("settings", "rules")
      assert(ruleValues() == table.concat(want, ","), string.format("every rule's value whole at %dx%d: %s", size[1], size[2], ruleValues()))
      check(ruler.C.UI.frame, string.format("officer settings, the rules, %dx%d", size[1], size[2]))
      ruler.C.UI:Open("settings", "guide")
      assert(ruleValues() == table.concat(wantGuide, ","), string.format("the Guide's values whole at %dx%d: %s", size[1], size[2], ruleValues()))
      check(ruler.C.UI.frame, string.format("officer settings, the Guide's rules, %dx%d", size[1], size[2]))
    end
    ruler.C.UI.frame:SetSize(1040, 640)
    ruler.C.Comm:SendPolicy()
    settle()
    for _, c in ipairs({ ada, bo, cy }) do assert(c.C.Rules.Get("rangeMembers") == 4, c.o.name .. " applied the officer's rule") end
    assert(R.Model().dungeons[48].range == "learned" and cy.C.Rules.Model().dungeons[48].range == "learned", "Blackfathom's four kills learn its range now")
    local c0 = #cy.chat
    cy.env.SlashCmdList.CUTE("rules")
    local said = table.concat(cy.chat, "\n", c0 + 1)
    assert(said:find("Members to learn a range (rangeMembers): 4, set by Ruler", 1, true) and said:find("(doubtRuns): 3, the default", 1, true), "/cute rules:\n" .. said)
    -- a member's own rules are no one's; an officer's out of bounds is dropped
    ada.C.Policy:SetRule("doubtRuns", 9)
    ada.C.Comm:SendPolicy()
    settle()
    assert(bo.C.Rules.Get("doubtRuns") == 3 and R.Get("doubtRuns") == 3, "a member's rule changes nothing")
    assert(ada.C.Policy:Receive("Ruler-Forever", ada.env.CuteDB.policy.at + 5, 1, "r_rangemembers=99:" .. ruler.o.guid .. ";r_doubtruns=2:" .. ruler.o.guid) and ada.C.Rules.Get("rangeMembers") == 5
      and ada.C.Rules.Get("doubtRuns") == 2, "out of bounds dropped (the default back), in bounds kept")
    -- the Guide: Cy (a member, 20) and Ruler (the officer), at both sizes
    -- the Guide: Cy (a member, 20) and Ruler (the officer), at both sizes. The Deadmines' card as the Guide draws it
    -- (the page draws the pick's rows alone; G.CardRows any dungeon in range's)
    local rows, dmCard, cyPlan = cardOf(cy, "The Deadmines", false)
    assert(dmCard and rows[1].kind == "card" and rows[1].val == "19-22" and rows[1].who == "seen", "Cy's dungeons: the Deadmines, learned 19-22, seen")
    -- under its card: the bosses as pips, the quests, and the guild mates online in its range within three levels of
    -- Cy's (Bo, in Cy's group already; Ada at 18 below the range, Di at 23 past it since her ding)
    local pips, quests, mates = rows[2], nil, {}
    for i = 2, #rows do
      local it = rows[i]
      if it.kind == "quests" then quests = it end
      if it.kind == "mate" and it.mate then mates[#mates + 1] = it.name .. " " .. it.val .. (it.mate.grouped and " (" .. it.who .. ")" or "") end
    end
    assert(table.concat(mates, ", ") == "Bo 19 (in your group)", "the mates online in range near Cy's level: " .. table.concat(mates, ", "))
    local function states(p) local out = {}; for _, x in ipairs(p.pips) do out[#out + 1] = x.name .. "=" .. x.state end return table.concat(out, ",") end
    local RC = cy.C.Rules
    if SEEDED then
      assert(pips.kind == "bosses" and pips.who == "every one killed but the doubted" and states(pips) == "Rhahk'Zor=killed,Glubtok=killed,Mr. Smite=doubted,Edwin VanCleef=killed",
        "Cy's bosses as pips, every one killed but the doubted: " .. states(pips))
      -- the quests for an Alliance character at 20: two to take, one the catalog gave no id (named, not counted), one
      -- opening at 21, the Horde's left out
      assert(quests and quests.who == "2 to take" and quests.name == "Red Silk Bandanas, The Defias Brotherhood, Oh Brother. . ." and #quests.qlist == 4,
        "the Deadmines' quests for Cy: " .. tostring(quests and quests.name) .. " / " .. tostring(quests and quests.who))
      -- Blackfathom in range for Cy too (the pick's tooltip weighs both); at 20 the research's cloth wrist is not
      -- missing (the rules count it from the enchant level, 30), and the rules name what Forever has for it (the
      -- Guide's advice and gear strips left the page in 0.7.0)
      local bfd
      for _, card in ipairs(cyPlan.cards) do if card.d.name == "Blackfathom Deeps" then bfd = card end end
      assert(bfd and tipText(cyPlan.next.tip):find("Blackfathom Deeps | ", 1, true) and tipText(cyPlan.next.tip):find("The Deadmines | ", 1, true), "Blackfathom in range for Cy, both weighed in the pick's tooltip:\n" .. tipText(cyPlan.next.tip))
      assert(RC.SeedEnchantable(9, "4.1") and not RC.SeedEnchantable(9, "4.1", 20) and not cy.C.Sample:Value("unenchanted")[9] and RC.SeedSlotState(9) == "beta",
        "at 20 the research's wrist is advice, not missing")
      local names = {}
      for _, x in ipairs((RC.SlotEnchants(9, "4.1"))) do if x.state ~= "absent" then names[#names + 1] = x.name end end
      assert(table.concat(names, ", ") == "Enchant Bracer - Minor Deflection, Enchant Bracer - Minor Health", "what Forever has for a cloth wrist: " .. table.concat(names, ", "))
    else
      assert(pips.kind == "bosses" and pips.who == "every one killed" and #pips.pips == 3 and not quests and not cy.C.Sample:Value("unenchanted")[9],
        "no seed: the bosses the guild met, all killed; no quests known; no enchant asked for: " .. states(pips))
    end
    -- Ed, at 31: the wrist missing, by the seed's word
    if SEEDED then
      assert(ed.C.Sample:Value("unenchanted")[9] and ed.C.Stats.EnchantSource(9, "4.1") == "seen in the beta", "at 31 the wrist is missing, by the seed's word: " .. tostring(ed.C.Stats.EnchantSource(9, "4.1")))
    end
    assert(type(cy.C.Sample.values.xp_hour) == "number" and cy.C.Sample.values.xp_hour > 0, "Cy's pace read: " .. tostring(cy.C.Sample.values.xp_hour))
    -- the officer: what the guild learned is the head's tooltip (plan.learned, from R.Changes); a dungeon's tooltip
    -- names every boss with how many members were seen killing it
    local _, rulerPlan = ruler.C.Guide.Items(true)
    local RR2 = ruler.C.Rules
    local learned = {}
    for _, ch in ipairs(RR2.Changes()) do learned[ch.what] = ch end
    local function learnedLine(what) for _, l in ipairs(rulerPlan.learned) do if l:sub(1, #what) == what then return l end end end
    local dm = RR2.Model().dungeons[36]
    assert(dm and RR2.RangeWords(dm) == "19-22", "the Deadmines learned 19-22: " .. tostring(dm and RR2.RangeWords(dm)))
    local killed, known = 0, 0
    for _, enc in ipairs(dm.bosses or {}) do local b = RR2.Model().bosses[enc]; if b and b.state ~= "stale" then known = known + 1; if (b.n or 0) > 0 then killed = killed + 1 end end end
    assert(killed == 3 and known == (SEEDED and 4 or 3), "the guild killed 3 of its " .. known .. " bosses: " .. killed)
    local said = tipText(ruler.C.Guide.DungeonTip(dm))
    assert(said:find("Rhahk'Zor | seen by 5 members", 1, true) and (not SEEDED or said:find("Mr. Smite | doubted: not seen in 3 runs; not by you", 1, true)), "every boss in its tooltip, one count each:\n" .. said)
    if SEEDED then
      assert(learned["New boss: Krol'dok the Brute"] and learnedLine("New boss: Krol'dok the Brute") and RR2.SeedState() == "fresh" and #RR2.Changes() > 0, "what the guild's play changed")
      assert(learned["Doubted: Mr. Smite"] and learned["XP to reach 32: 43000"] and learned["Range learned: The Deadmines"].detail == "19-22 (research 18-23), from 5 members"
        and learnedLine("Range learned: The Deadmines") == "Range learned: The Deadmines: 19-22 (research 18-23), from 5 members",
        "doubted, the XP corrected, the range learned against the research's, each in the head's tooltip")
    else
      -- with no research nothing is a change from it: Learned in play is what the guild learned, each dungeon once with
      -- its bosses counted on its line and named in its tooltip, no line a boss (the first 0.5.0 build said "13 changes
      -- from the research" here, a line for every dungeon and boss)
      local changes = RR2.Changes()
      local whats = {}
      for _, ch in ipairs(changes) do
        whats[#whats + 1] = ch.what
        assert(not ch.what:find("^New ") and not ch.detail:find("research", 1, true), "no seed: nothing called a change from research: " .. ch.what .. " | " .. ch.detail)
      end
      assert(#changes == 7 and RR2.SeedState() == "none" and learned["No research shipped with this copy"], "no seed: what the guild learned:\n" .. table.concat(whats, "\n"))
      local dl = learned["Dungeon: The Deadmines"]
      assert(dl and dl.detail == "3 bosses, seen by 5 members" and learned["Dungeon: Krol'dok Stronghold"].detail == "2 bosses, seen by 2 members"
        and learned["Dungeon: Blackfathom Deeps"].detail == "1 boss, seen by 4 members" and learned["Range learned: The Deadmines"].detail == "19-22, from 5 members"
        and learned["Enchant slot: Chest"] and not learned["Krol'dok the Brute"], "no seed: each dungeon once, its bosses counted: " .. tostring(dl and dl.detail))
      assert(learnedLine("Dungeon: The Deadmines") == "Dungeon: The Deadmines: 3 bosses, seen by 5 members", "and in the head's tooltip")
      local names = table.concat(dl.names or {}, "\n")
      assert(names:find("Rhahk'Zor", 1, true) and names:find("Glubtok", 1, true) and names:find("Edwin VanCleef", 1, true), "its bosses named:\n" .. names)
    end
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      for _, c in ipairs({ cy, ruler }) do
        c.C.UI:Build()
        c.C.UI.frame:SetSize(size[1], size[2])
        openGuide(c)
        check(c.C.UI.frame, string.format("%s guide, %dx%d", c == ruler and "officer" or "member", size[1], size[2]))
        for _, l in ipairs(c.C.UI.lists.guide.items) do if l:IsShown() then hover(l) end end
        -- the end of the list, scrolled
        local bar = c.C.UI.scroll.bar
        local _, max = bar:GetMinMaxValues()
        bar:SetValue(max)
        check(c.C.UI.frame, string.format("%s guide, %dx%d, the end", c == ruler and "officer" or "member", size[1], size[2]))
        c.C.UI.frame:SetSize(1040, 640)
      end
    end
    openGuide(cy)
    local first = texts(cy)
    local _, cyPlan = cy.C.Guide.Items(false)
    assert(first:find(cyPlan.next.line, 1, true) and tipOf(guideHead(cy)):find(SEEDED and "From research and the beta, checked against this client" or "Nothing shipped with this copy", 1, true),
      "the page opens on the pick, where it comes from in the head's tooltip")
    -- /cute diag on the officer: the seed's state, with what was learned
    local d0 = #ruler.chat
    ruler.env.SlashCmdList.CUTE("diag")
    local diag = table.concat(ruler.chat, "\n", d0 + 1)
    assert(diag:find(SEEDED and "diag seed: fresh" or "diag seed: none shipped", 1, true) and (not SEEDED or diag:find("doubted 1", 1, true)), "/cute diag:\n" .. diag)
    for _, c in ipairs(all) do leave(c) end
  end)
  print("rules: kills in groups, each named back by a group mate (one alone teaches nothing); a range learned from five members, one at either end set aside (four: the seed's, or the levels seen), loot from a boss's window within the minute and not from a bag's container or a corpse of greys, a boss doubted after three full runs (two: not), Krol'dok's bosses joining under it, level 31's XP replaced when three agree (two: not), the research's wrist missing at 30 and advice at 19, doubted after fourteen days (thirteen: not; a member at 29 starts no clock), For you and Next up at their edges, an officer's rule retuned in Settings (every value whole at 760 wide) and applied by the members, the Guide for a member and an officer at both sizes, the officer's dungeons one line each")
end

-- 31: the level cap (rule 7): the game's, the lower of the two calls that reads; the seed's 60 where neither does; a
-- member past it raises it; deaths count while leveling below it
do
  local function member(name, level) return { name = name .. "-Forever", guid = guidOf(name), rank = 3, rankName = "Raider", class = "MAGE", level = level, online = true } end
  isolated({ member("Capa", 25), member("Capb", 25) }, function()
    local a = newClient(charOf({ "Capa", 3, "Raider", "MAGE", 25 }, { maxLevel = 30 }))
    local b = newClient(charOf({ "Capb", 3, "Raider", "MAGE", 25 }, { noCap = true }))
    login(a); login(b)
    tickAll(45)
    assert(a.C.Rules.Cap() == 30 and b.C.Rules.Cap() == 60, "the game's 30; the seed's (or the fallback's) 60: " .. a.C.Rules.Cap() .. " " .. b.C.Rules.Cap())
    a.o.level = 30
    fire(a, "PLAYER_DEAD")
    assert(a.C.Sample:Value("deaths_lvl") == 0, "a death at the cap is no leveling death")
    b.o.level = 32
    fire(b, "PLAYER_LEVEL_UP", 32)
    -- (the game's roster lists Capb at 32: the server's word, which a level the addon reports is held to)
    fire(a, "CLUB_MEMBER_UPDATED")
    tickAll(5)
    assert(a.C.Rules.Cap() == 32, "a member past the game's cap raises it: " .. a.C.Rules.Cap())
    leave(a); leave(b)
  end)
  print("cap: the game's, else the seed's 60; a member past it raises it; deaths at the cap are not leveling deaths")
end

-- 32: rule 4 where a dungeon is no corridor (with the seed). A full run is a member who killed every boss there the
-- guild has met. One seeded boss missing from three such runs is doubted (the Deadmines' Mr. Smite, scenario 30); two
-- missing take six: three runs that miss Glubtok and Mr. Smite doubt neither, six doubt both. A run that missed a boss
-- the guild met is no full run. Never a boss the seed marks optional (Blackfathom's Lady Sarevess), while Kelris,
-- missing alone there, is doubted; never in a dungeon whose wings share one instance (Razorfen Downs, marked so). With
-- the real Known.lua: three runs of Blackrock Depths to the Emperor that spare Moira and skip the Grim Guzzler doubt
-- none of its bosses (a rule that read the seed's order as the path doubted nine), and nine through Scarlet
-- Monastery's Graveyard and Library none of the Armory's or the Cathedral's (its wings marked). A run is full only
-- once the guild has seen two bosses there: nine members who killed only the Deadmines' first doubt none of the other
-- three (the first 0.5.0 build took them for nine full runs and doubted all three); with two seen, the other two take
-- six full runs, five doubting neither
if SEEDED then isolated({ { name = "Runa-Forever", guid = guidOf("Runa"), rank = 3, rankName = "Raider", class = "MAGE", level = 40, online = true } }, function()
  -- members' saved records, each the encounters one member killed, every kill one a group mate named back (rule 9,
  -- scenario 30 sends the claims); the model built from them alone (who met what carries over from one build of it to
  -- the next, so each case starts from none)
  local function runs(c, list)
    local roster = c.env.CuteDB.roster
    for key in pairs(roster) do if key:match("^Run%d") then roster[key] = nil end end
    local kills = {}
    c.env.CuteDB.known.kills = kills
    local members = {}
    for i, encs in ipairs(list) do
      local st = { guid = "Player-9-0000RUN" .. i, level = 40 }
      for _, e in ipairs(encs) do st["e" .. e] = 1; kills[e] = kills[e] or {}; kills[e][st.guid] = true end
      roster["Run" .. i .. "-Forever"] = { stats = st, at = {}, seen = c.C.Now() }
      members[i] = { "Run" .. i .. "-Forever", st.guid, 40 }
    end
    listed(c, members)
    c.env.CuteDB.known.model = nil
    c.C.Rules.model = nil
    return c.C.Rules:Rebuild()
  end
  local function times(n, encs) local out = {}; for i = 1, n do out[i] = encs end return out end
  local c = newClient(charOf({ "Runa", 3, "Raider", "MAGE", 40 }, {}))
  login(c)
  local R = c.C.Rules
  local m = runs(c, times(3, { 1230, 1234 }))
  assert(m.bosses[1236].state == "beta" and m.bosses[1238].state == "beta" and m.bosses[1236].runs == 3, "two bosses missing from three full runs: neither doubted")
  m = runs(c, times(6, { 1230, 1234 }))
  assert(m.bosses[1236].state == "doubted" and m.bosses[1238].state == "doubted" and R.Words(m.bosses[1236]) == "doubted: not seen in 6 runs", "six: both")
  m = runs(c, { { 1230, 1236, 1234 }, { 1230, 1236, 1234 }, { 1230, 1234 } })
  assert(m.bosses[1238].state == "beta" and m.bosses[1238].runs == 2, "a run that missed Glubtok, whom the guild met, is no full run")
  m = runs(c, times(3, { 1240, 1243 }))
  assert(m.bosses[1241].state == "beta" and m.bosses[1242].state == "doubted", "Blackfathom: the optional Lady Sarevess never doubted; Kelris, missing alone, is")
  m = runs(c, times(9, { 1250, 1252 }))
  assert(m.bosses[1251].state == "data", "Razorfen Downs, wings sharing one instance: never doubted")
  -- one boss seen: no run is full, whatever the count
  m = runs(c, times(9, { 1230 }))
  assert(m.bosses[1236].state == "beta" and m.bosses[1238].state == "beta" and m.bosses[1234].state == "beta" and m.bosses[1236].runs == nil,
    "the guild has seen only the first boss: nine members who killed it are no full runs, nothing doubted: " .. tostring(m.bosses[1236].state))
  -- two seen, two missing: doubtRuns full runs each, six; five doubt neither
  m = runs(c, times(5, { 1230, 1236 }))
  assert(m.bosses[1238].state == "beta" and m.bosses[1234].state == "beta" and m.bosses[1238].runs == 5, "two bosses seen, five full runs: neither of the other two doubted")
  m = runs(c, times(6, { 1230, 1236 }))
  assert(m.bosses[1238].state == "doubted" and m.bosses[1234].state == "doubted" and R.Words(m.bosses[1234]) == "doubted: not seen in 6 runs", "six: both")
  leave(c)
  local note = "the real Known.lua not there yet"
  local f = io.open(REAL_KNOWN)
  if f then
    local src = f:read("*a")
    f:close()
    local real = newClient(charOf({ "Runa", 3, "Raider", "MAGE", 40 }, { seed = "real", build = src:match('build%s*=%s*"([^"]+)"'), allFactions = true }))
    login(real)
    local brd = real.C.Rules.Seed() and real.C.Rules.Seed().dungeons[230]
    if brd then
      m = runs(real, times(3, { 227, 230, 231, 232, 233, 234, 235, 236, 237, 242, 244, 2790 }))
      local doubted = {}
      for _, enc in ipairs(m.dungeons[230].bosses) do if m.bosses[enc].state == "doubted" then doubted[#doubted + 1] = m.bosses[enc].name end end
      assert(#doubted == 0, "three runs of Blackrock Depths to the Emperor doubt none of its bosses: " .. table.concat(doubted, ", "))
      note = string.format("three runs of Blackrock Depths to the Emperor doubt none of its %d bosses", #m.dungeons[230].bosses)
    else
      note = "the real Known.lua has no Blackrock Depths"
    end
    -- Scarlet Monastery's wings share one instance and a run is one wing: nine members through the Graveyard and the
    -- Library meet four of its seven bosses and doubt none of the Armory's or the Cathedral's (the first 0.5.0 seed
    -- named the wings in a comment only, so Rule 4 doubted Herod, Fairbanks and Whitemane)
    local sm = real.C.Rules.Seed() and real.C.Rules.Seed().dungeons[189]
    if sm then
      m = runs(real, times(9, { 444, 2779, 446, 447 }))
      local doubted = {}
      for _, enc in ipairs(m.dungeons[189].bosses) do if m.bosses[enc].state == "doubted" then doubted[#doubted + 1] = m.bosses[enc].name end end
      assert(sm.wings and #doubted == 0, "nine runs of Scarlet Monastery's Graveyard and Library doubt none of the Armory's or the Cathedral's bosses: "
        .. (sm.wings and "" or "its wings unmarked; ") .. table.concat(doubted, ", "))
      note = note .. "; nine of Scarlet Monastery's Graveyard and Library, its wings marked, doubt none of the Armory's or the Cathedral's"
    else
      note = note .. "; the real Known.lua has no Scarlet Monastery"
    end
    leave(real)
  end
  print("rule 4: two bosses missing take six full runs (three: neither), a run short of what the guild met is none, an optional boss and a dungeon of wings never doubted, no run full while the guild has seen one boss there (nine: nothing doubted), two seen: six full runs doubt the other two, five not; " .. note)
end) end

-- 33: rule 5 widens the seed, never narrows it. The seed's wrist takes cloth to plate. Lea and Lex, at 30, wear leather
-- bracers enchanted with Minor Health; Clo, at 30, a bare cloth one, Lia, at 30, a bare leather one, Kit, at 20, a bare
-- cloth one. The guild has seen the wrist enchanted on leather alone: Lia's bracer is missing by the guild's word
-- ("seen on 2 members"), Clo's still by the seed's ("seen in the beta"), in Missing enchants and in the Guide, where
-- Minor Health is seen on two members and Minor Deflection is the beta's; Kit's is advice, the beta's. (The first 0.5.0
-- build made the whole wrist "seen" at Lea's enchant: Clo's bracer stopped counting, Kit's advice went, and every
-- wrist enchant read "seen on 0 members".) With no seed only the leather bracer is asked for. The officers open the
-- gear gaps here, as in scenario 23, so the members hear each other's enchants
do
  local function member(name, level) return { name = name .. "-Forever", guid = guidOf(name), rank = 3, rankName = "Raider", class = "PRIEST", level = level, online = true } end
  isolated({ member("Lea", 30), member("Clo", 30), member("Lia", 30), member("Kit", 20), member("Lex", 30) }, function()
    local function make(name, level, bracer) return newClient(charOf({ name, 3, "Raider", "PRIEST", level }, { items = { [1] = "item:1234:0", [9] = bracer } })) end
    local lea, clo, lia, kit = make("Lea", 30, "item:6031:41"), make("Clo", 30, "item:6030:0"), make("Lia", 30, "item:6031:0"), make("Kit", 20, "item:6030:0")
    local lex = make("Lex", 30, "item:6031:41")
    for _, c in ipairs({ lea, clo, lia, kit, lex }) do login(c, gapsOpen()) end
    tickAll(45)
    local function missing(c) return (c.C.Sample:Value("unenchanted") or {})[9] == true end
    for _, c in ipairs({ clo, lia, kit }) do
      assert(c.C.Stats.EnchantLearned(9, "4.2") and not c.C.Stats.EnchantLearned(9, "4.1"), c.o.name .. ": the guild has seen the wrist enchanted on leather alone")
    end
    assert(missing(lia) and not missing(lea) and lia.C.Stats.EnchantSource(9, "4.2") == "seen on 2 members", "Lia's bare leather bracer missing by the guild's word, Lea's enchanted")
    if SEEDED then
      local R = clo.C.Rules
      assert(R.SlotState(9) == "seen" and R.SeedSlotState(9) == "beta", "the wrist seen by the guild, the seed's own word on it kept: " .. tostring(R.SeedSlotState(9)))
      assert(missing(clo) and clo.C.Stats.EnchantSource(9, "4.1") == "seen in the beta",
        "Clo's cloth bracer still missing at 30, by the seed's word: " .. tostring(clo.C.Stats.EnchantSource(9, "4.1")))
      local list = R.SlotEnchants(9, "4.1")
      assert(#list == 2 and list[1].name == "Enchant Bracer - Minor Health" and list[1].state == "seen" and list[1].n == 2 and list[2].state == "beta",
        "each enchant seen only once that enchant was: " .. tostring(list[2] and list[2].state))
      assert(not missing(kit) and kit.C.Rules.SeedEnchantable(9, "4.1") and not kit.C.Rules.SeedEnchantable(9, "4.1", 20) and kit.C.Rules.SeedSlotState(9) == "beta", "Kit at 20: the cloth bracer is advice, the beta's")
    else
      assert(not missing(clo), "no seed: a cloth bracer nobody enchanted is not asked for")
    end
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      for _, c in ipairs({ clo, kit }) do
        openGuide(c)
        c.C.UI.frame:SetSize(size[1], size[2])
        openGuide(c)
        check(c.C.UI.frame, string.format("member guide, %s, two kinds in the wrist, %dx%d", c.o.name, size[1], size[2]))
        for _, l in ipairs(c.C.UI.lists.guide.items) do if l:IsShown() then hover(l) end end
        c.C.UI.frame:SetSize(1040, 640)
      end
    end
    for _, c in ipairs({ lea, clo, lia, kit, lex }) do leave(c) end
  end)
  print(SEEDED and "rule 5: two members' leather bracer enchants leave the seed counting a cloth one at 30 (Missing enchants and the Guide, the seed's word), the leather one missing by the guild's, each enchant seen only once it was, the cloth one advice at 20"
    or "rule 5, no seed: only the kind the guild enchanted is asked for")
end

-- 34: the Guide where nothing is known to take an enchant, and its notes. Nolo, an officer alone, wears nothing
-- enchanted; with no seed, or a stale one (17 of the fixture's 39 items lacking), the Gear line says no enchant slot is
-- known yet rather than that every worn item has one. A note takes the row's whole width (at 760 the name's column cut
-- it, the rest of the row empty) and its tooltip holds the whole text. Nolo enchanting his chest is one voice, which
-- teaches nothing; with a guild mate's enchanted chest beside it the guild knows a slot and the line says every worn
-- item that takes one has one; Learned in play names the slot as learned, not as new to research it has none of
do
  isolated({ { name = "Nolo-Forever", guid = guidOf("Nolo"), rank = 1, rankName = "Officer", class = "MAGE", level = 35, online = true } }, function()
    local lacking = {}
    for i = 1, 17 do lacking[FIX.items[i]] = true end
    local c = newClient(charOf({ "Nolo", 1, "Officer", "MAGE", 35 }, { lackItems = lacking, items = { [1] = "item:1234:0", [5] = "item:1235:0", [16] = "item:1240:0" } }))
    login(c)
    tickAll(10)
    assert(c.C.Rules.SeedState() == (SEEDED and "stale" or "none"), "the seed: " .. c.C.Rules.SeedState())
    local function learned() local out = {}; for _, ch in ipairs(c.C.Rules.Changes()) do out[ch.what] = ch end return out end
    local function known() for _, slot in ipairs(c.C.Stats.GEAR) do if c.C.Stats.EnchantLearned(slot) or c.C.Rules.SeedEnchantable(slot) then return true end end return false end
    assert(not known(), "no slot known to take an enchant yet")
    -- (0.7.0: the gear strips left the page; the page is one card at 760 wide)
    openGuide(c)
    c.C.UI.frame:SetSize(760, 420)
    openGuide(c)
    check(c.C.UI.frame, "officer guide, nothing known to take an enchant, 760x420")
    c.C.UI.frame:SetSize(1040, 640)
    -- the chest enchanted: one voice, nothing known yet; a guild mate's record with an enchanted chest: a slot known,
    -- nothing missing
    c.o.items[5] = "item:1235:2"
    fire(c, "UNIT_INVENTORY_CHANGED", "player")
    tick(c, 5)
    assert(not known(), "Nolo's chest alone teaches nothing")
    listed(c, { { "Mate-Forever", guidOf("Mate"), 35 } })
    c.C.Roster:Apply("Mate-Forever", { guid = guidOf("Mate"), enchanted = { [5] = true }, ench_kinds = "5:15.0:2" })
    tick(c, 5)
    local it = learned()
    assert(known() and c.C.Stats.EnchantLearned(5) and not c.C.Sample:Value("unenchanted")[5], "a slot known: nothing missing (the chest enchanted)")
    local _, plan = c.C.Guide.Items(true)
    assert(it["Enchant slot: Chest"] and it["Enchant slot: Chest"].detail == "seen on 2 members" and not it["New enchant slot: Chest"]
      and plan.learned[1] and table.concat(plan.learned, "\n"):find("Enchant slot: Chest: seen on 2 members", 1, true), "Learned in play: the slot learned, not new to research, in the head's tooltip")
    openGuide(c)
    check(c.C.UI.frame, "officer guide, a slot learned with no research to weigh it, 1040x640")
    leave(c)
  end)
  print("guide: nothing known to take an enchant (no seed or a stale one), the page one card at 760 wide; a slot learned with no research named as learned in the head's tooltip")
end

-- 35: versions. Every Cute sends its version (addon_ver); one newer than yours, number by number (0.5.10 is newer than
-- 0.5.9), says so once a session in chat and in the window's status line until you update; an older, an equal or a
-- malformed one says nothing. A /reload is the same session; the next login says it again; once updated, nothing. The
-- first login on a version prints its changelog line once, ten seconds on: the page's line for it (Changes.lua, which
-- build.py writes from the page's changelog before zipping)
do
  local function member(name) return { name = name .. "-Forever", guid = guidOf(name), rank = 3, rankName = "Raider", class = "MAGE", level = 30, online = true } end
  isolated({ member("Vera"), member("Neo"), member("Nia") }, function()
    local function char(name) return charOf({ name, 3, "Raider", "MAGE", 30 }) end
    local function told(c, s) local n = 0; for _, m in ipairs(c.chat) do if m:find(s, 1, true) then n = n + 1 end end return n end
    local vera, neo = newClient(char("Vera")), newClient(char("Neo"))
    local V = vera.C
    local mine = V.version
    -- two versions newer than this one (the minor bumped), so the scenario moves with the toc
    local function bump(v, n) local major, minor = v:match("^(%d+)%.(%d+)"); return major .. "." .. (tonumber(minor) + n) .. ".0" end
    local newer1, newer2 = bump(mine, 1), bump(mine, 2)
    -- numbers, not text; anything but dotted numbers is no version
    assert(V.VersionNewer("0.5.10", "0.5.9") and not V.VersionNewer("0.5.9", "0.5.10") and V.VersionNewer("0.6", "0.5.9") and not V.VersionNewer("0.5.0", "0.5")
      and V.VersionNewer("1.0.0", "0.99.99") and not V.VersionNewer(mine, mine), "versions compared number by number")
    for _, bad in ipairs({ "", "5", "0.5.x", "0..5", ".5.1", "0.5.1.", "0.5.0-beta", "banana", "1.2.3.4.5", "1234567.0.0", " 0.6.0", "-1.0.0" }) do
      assert(V.ParseVersion(bad) == nil and not V.VersionNewer(bad, "0.0.1"), "no version: '" .. bad .. "'")
    end
    -- older, equal and malformed versions arriving: nothing said, nothing shown (Wim, alone, before any hello)
    local wim = newClient(char("Wim"))
    login(wim)
    for _, v in ipairs({ "0.4.0", "0.4.99", mine, mine .. ".0", "0.5.x", "9.9.9 ", "", "banana" }) do wim.C.Roster:Apply("Jumble-Forever", { guid = guidOf("Jumble"), addon_ver = v }) end
    wim.C.UI:Open("race")
    assert(told(wim, "is out") == 0 and wim.C.newer == nil and not wim.C.UI.status:GetText():find("update", 1, true), "older, equal and malformed: nothing")
    leave(wim)
    -- Neo runs a newer Cute: one member's version alone says nothing (an edited copy's would make every client online
    -- say an update is out); Nia's too: their records tell Vera, once; Neo hears an older one and says nothing
    neo.C.version = newer1
    login(vera); login(neo)
    tickAll(45)
    assert(told(vera, "is out") == 0 and V.newer == nil, "one member's newer version alone says nothing")
    local nia = newClient(char("Nia"))
    nia.C.version = newer1
    login(nia)
    tickAll(45)
    assert(told(vera, "Cute " .. newer1 .. "|r is out (you have " .. mine .. "): foreverrank.com/addons/cute") == 1 and V.newer == newer1, "Vera told once:\n" .. table.concat(vera.chat, "\n"))
    assert(told(neo, "is out") == 0 and neo.C.newer == nil, "Neo, newer than Vera, is told nothing")
    -- a newer one again, and junk: no second line; the status line keeps the newest
    for _, v in ipairs({ "0.4.9", mine, newer2 .. "-beta", "banana" }) do vera.C.Roster:Apply("Jumble-Forever", { guid = guidOf("Jumble"), addon_ver = v }) end
    vera.C.Roster:Apply("Neo-Forever", { addon_ver = newer2 })
    assert(V.newer == newer1, "one member at the newer one still: the first kept")
    vera.C.Roster:Apply("Nia-Forever", { addon_ver = newer2 })
    assert(told(vera, "is out") == 1 and V.newer == newer2, "one line a session, the newest kept: " .. tostring(V.newer))
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      vera.C.UI:Open("race")
      vera.C.UI.frame:SetSize(size[1], size[2])
      vera.C.UI:Open("race")
      assert(vera.C.UI.status:GetText():find("update available", 1, true), "the status line says an update is available: " .. vera.C.UI.status:GetText())
      check(vera.C.UI.frame, string.format("member race, an update available, %dx%d", size[1], size[2]))
      vera.C.UI.frame:SetSize(1040, 640)
    end
    neo.C.UI:Open("race")
    assert(not neo.C.UI.status:GetText():find("update", 1, true), "Neo's status line says none")
    -- Vera's first run (her saved variables empty) says hello, naming /cute, and not what is new in a version she never
    -- ran before; the version counts as told
    local news = V.COLOR .. "Cute " .. mine .. "|r: "
    assert(told(vera, "/cute or the elf on the minimap opens the guild window.") == 1 and told(vera, news) == 0 and vera.env.CuteDB.toldChanges == mine,
      "a first run: the welcome, once, and no news:\n" .. table.concat(vera.chat, "\n"))
    -- a /reload is the same session: the update still shown, neither line said again
    local db = vera.env.CuteDB
    leave(vera)
    local again = newClient(char("Vera"))
    login(again, db, true)
    tick(again, 20)
    assert(again.C.newer == newer2 and told(again, "is out") == 0 and told(again, news) == 0, "after a /reload: the update shown, nothing said")
    leave(again)
    -- the next login says the update again, not what is new
    local nextDay = newClient(char("Vera"))
    login(nextDay, db)
    tick(nextDay, 20)
    assert(told(nextDay, "Cute " .. newer2 .. "|r is out (you have " .. mine .. ")") == 1 and told(nextDay, news) == 0, "the next login: the update said again, what is new not:\n" .. table.concat(nextDay.chat, "\n"))
    leave(nextDay)
    -- updated to the newer one with the same saved records: nothing; and a first login on a version whose line Changes.lua
    -- lacks says nothing of it
    local updated = newClient(char("Vera"))
    updated.C.version = newer2
    login(updated, db)
    tick(updated, 20)
    assert(updated.C.newer == nil and told(updated, "is out") == 0 and told(updated, "Cute " .. newer2 .. "|r: ") == 0, "updated: nothing")
    leave(updated)
    -- saved variables of 0.4.0: what is new in this version, once, the page's line for it; no welcome
    local old = newClient(char("Vera"))
    login(old, { toldChanges = "0.4.0" })
    tick(old, 20)
    assert(told(old, news) == 1 and told(old, "opens the guild window") == 0 and old.env.CuteDB.toldChanges == mine, "from 0.4.0: what is new, once")
    local said
    for _, m in ipairs(old.chat) do if m:sub(1, #news) == news then said = m:sub(#news + 1) end end
    assert(said == V.CHANGES[mine] and not said:find("\n", 1, true), "one line, Changes.lua's")
    -- (and the versions it skipped, newest first, three at most: a 0.5.x user hears where the Guide went)
    local between, lines = 0, 0
    for v in pairs(V.CHANGES) do if V.VersionNewer(v, "0.4.0") and V.VersionNewer(mine, v) then between = between + 1 end end
    for _, m in ipairs(old.chat) do if m:find("^" .. V.COLOR:gsub("|", "%%|") .. "Cute %d") and m:sub(1, #news) ~= news then lines = lines + 1 end end
    assert(lines == math.min(3, between), "the skipped versions' lines, three at most: " .. lines .. " of " .. between)
    leave(old)
    -- Changes.lua, generated by build.py from the page: every changelog line the page has, the toc's version among them
    local page = assert(io.open(HERE .. "/../../addons/cute/index.html")):read("*a")
    local n = 0
    for v, body in page:gmatch("<li><b>(%d+%.%d+%.%d+)</b>(.-)</li>") do
      local text = body:gsub("<[^>]+>", ""):gsub("&#39;", "'"):gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):gsub("%s+", " ")
      text = text:gsub("^ ", ""):gsub(" $", "")
      assert(V.CHANGES[v] == text, "Changes.lua says what the page says for " .. v .. ":\n" .. tostring(V.CHANGES[v]) .. "\n" .. text)
      n = n + 1
    end
    local listed = 0
    for _ in pairs(V.CHANGES) do listed = listed + 1 end
    local toc = assert(io.open(HERE .. "/Cute/Cute.toc")):read("*a")
    assert(n > 0 and listed == n and V.CHANGES[mine] and toc:match("## Version:%s*(%S+)") == mine and toc:find("\nChanges.lua\n", 1, true),
      "Changes.lua holds the page's " .. n .. " lines, the toc's version among them, and the toc loads it")
    leave(neo)
  end)
  print("versions: a newer one said once a session (0.5.10 after 0.5.9) and shown in the status line until updated, older, equal and malformed ones nothing, a /reload the same session, the next login again; what is new printed once a version, the page's line from Changes.lua; a first run says hello naming /cute instead")
end

-- 36: modules. A fresh install is the dashboard alone (scenario 9); so is a character that ran 0.5.x, where the Guide
-- was a fixed tab (What's new says so at that login), a character new to that account and one from 0.4.0, and they
-- stay without it at the later logins on those saved variables. A module addon
-- (tools/cute/test/Cute_Example: "## LoadOnDemand: 1", "## Dependencies: Cute", "## X-Cute-Module: 1") is listed in
-- Settings > Modules from the client's addon list, by its toc's title, and not loaded; ticked, it loads at once, no
-- reload, and its tab, its section, its event and its stat come with it; ticked in combat, it waits for combat to end
-- and says so. Unticked, its tab, section and event go at once, its page asked for opens Race, and the game's AddOns
-- list has it off for this character: the next login does not load it, and ticked there it is on in the list again
-- and loads. One that is no LoadOnDemand addon is loaded by the game while it is on in the list, shows nothing while it
-- is off in Cute, and once unticked the game does not load it at the next login. Every Settings section and every page
-- at both sizes, for an officer and a member, with the Guide and the module on
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true } end
  isolated({ member("Moda", 1), member("Pim", 3) }, function()
    local function char(name, extra) return charOf({ name, name == "Moda" and 1 or 3, "", "MAGE", 30 }, extra) end
    local function boxOf(c, title) return checkBox(c, function(cb) return cb.label and cb.label:GetText() == title end) end
    -- 0.5.x's saved variables: every character in them starts with the dashboard alone too, as What's new says at that
    -- login (0.6.0's first builds kept the Guide on for them, under a line saying the opposite); a character new to the
    -- account, or saved variables from 0.4.0 (no Guide then), start without it
    local old = newClient(char("Moda"))
    local db = { version = "0.5.0", toldChanges = "0.5.0", chars = { [old.name] = { counters = { falls = 3 } }, ["Alt-Forever"] = { counters = {} } } }
    login(old, db)
    old.C.UI:Open("race")
    assert(not old.C.Modules.OnKey("guide") and tabsShown(old) == "race prog shame game officers me settings", "a character that ran 0.5.0 starts with the dashboard alone: " .. tabsShown(old))
    assert(not (db.chars["Alt-Forever"].modules or {}).guide and db.chars[old.name].counters.falls == 3, "every character 0.5.0 saved, its counters kept")
    tick(old, 11)
    local told = false
    -- (this version's line, from Changes.lua: 0.6.0's said "Starts with only the statistics")
    local line = old.C.CHANGES[old.C.version]
    for _, l in ipairs(old.chat) do if type(line) == "string" and l:find(line, 1, true) then told = true end end
    assert(told, "and What's new says so")
    leave(old)
    local alt = newClient(char("Pim"))
    login(alt, db)
    alt.C.UI:Open("race")
    assert(not alt.C.Modules.OnKey("guide") and tabsShown(alt) == "race prog shame game me settings", "a character new to the account: the dashboard alone")
    leave(alt)
    local db4 = { version = "0.4.0", chars = { ["Moda-Forever"] = { counters = {} }, ["Pim-Forever"] = { counters = {} } } }
    local older = newClient(char("Moda"))
    login(older, db4)
    assert(not older.C.Modules.OnKey("guide"), "from 0.4.0, which had no Guide: off")
    leave(older)
    -- the second login on those saved variables, by the other character 0.4.0 saved: still off (0.6.0's first build
    -- ran 0.5.x's carry-over at every login, and this one got the Guide), and the first character's too
    for _, name in ipairs({ "Pim", "Moda" }) do
      local again = newClient(char(name))
      login(again, db4)
      assert(not again.C.Modules.OnKey("guide") and not db4.chars["Pim-Forever"].modules.guide, name .. " at a later login on 0.4.0's saved variables: off")
      leave(again)
    end

    -- the module addon, LoadOnDemand: listed, not loaded; ticked, loaded at once with its tab, section, event and stat
    local state = {} -- the account's AddOns list, kept across its logins
    local moda = newClient(char("Moda", { modules = { "Cute_Example" }, addonState = state }))
    login(moda)
    tickAll(5)
    local M, ex = moda.C.Modules, moda.addons[2]
    assert(#M.found == 1 and M.found[1].name == "Cute_Example" and M.found[1].lod and M.found[1].title == "Cute Example", "found in the client's addon list, its title plain")
    assert(not ex.loaded and not M.byId.example, "listed, not loaded")
    moda.C.UI:Open("settings", "modules")
    local box = boxOf(moda, "Cute Example")
    assert(box and not box:GetChecked(), "its box, by the toc's title, unticked")
    check(moda.C.UI.frame, "officer settings, modules, a module addon found")
    click(box)
    assert(ex.loaded and M.byId.example and M.byId.example.active, "ticked: loaded at once, no reload")
    assert(tabsShown(moda) == "race prog shame game officers me example settings", "its tab, in its order: " .. tabsShown(moda))
    assert(sectionsShown(moda) == "general vis rules modules race prog shame officers example", "its section: " .. sectionsShown(moda))
    assert(boxOf(moda, "Example") and boxOf(moda, "Example"):GetChecked(), "its box ticked, named as it registered")
    assert(moda.C.Stats.byId.ex_heard and moda.C.Sample:Value("ex_heard") == 0, "its stat in the registry, read")
    fire(moda, "PLAYER_LEVEL_UP", 31)
    moda.C.UI:Open("example")
    assert(moda.C.UI.page == "example" and texts(moda):find("Level ups heard while on: 1.", 1, true), "its page, its event heard:\n" .. texts(moda))
    check(moda.C.UI.frame, "officer, a module addon's page")
    moda.C.UI:Open("settings", "example")
    click(boxOf(moda, "Count wide"))
    assert(ex.private.wide == true, "its own section's box")
    check(moda.C.UI.frame, "officer settings, a module addon's section")
    tick(moda, 70)
    assert(moda.C.Sample:Value("ex_heard") == 1, "its stat read on the heartbeat")

    -- the folder's second module: its own row, off; ticked, its tab and its onToggle; the first unticked alone keeps
    -- the folder on in the AddOns list, both off turns it off
    local M2 = moda.C.Modules
    moda.C.UI:Open("settings", "modules")
    assert(M2.byId.example_two and M2.byId.example_two.key == "Cute_Example:example_two" and M2.byId.example.primary == true and not M2.byId.example_two.primary, "the second module keyed under the folder")
    assert(boxOf(moda, "Example two") and not boxOf(moda, "Example two"):GetChecked() and not tabsShown(moda):find("example_two"), "listed off, no tab")
    click(boxOf(moda, "Example two"))
    assert(M2.byId.example_two.active and tabsShown(moda):find("example_two") and moda.addons[2].private.toggled == 1 and moda.addons[2].private.lastOn == true, "ticked: its tab, onToggle(true) once: " .. tabsShown(moda))
    click(boxOf(moda, "Example")) -- (the primary's row, named as it registered)
    assert(not M2.byId.example.active and M2.byId.example_two.active and not (state.Cute_Example and state.Cute_Example[moda.o.guid] == false) and M2.AddonOn("Cute_Example"), "the first off alone: the folder stays on in the AddOns list")
    click(boxOf(moda, "Example two"))
    assert(moda.addons[2].private.toggled == 2 and moda.addons[2].private.lastOn == false and state.Cute_Example[moda.o.guid] == false, "both off: onToggle(false), off in the AddOns list")
    click(boxOf(moda, "Example")) -- (back where the scenario's next lines expect it: the first on)
    moda.C.UI:Open("example")
    local host = moda.C.UI:Host("example_host")
    assert(host:IsShown() and host:GetParent() == moda.C.UI.scroll.child, "a host frame under the scroll child")
    moda.C.UI:Open("race")
    assert(not host:IsShown(), "a draw that does not ask for the host hides it")

    -- ticked in combat: nothing loads until combat ends, and the box says so
    local pim = newClient(char("Pim", { modules = { "Cute_Example" } }))
    login(pim)
    tickAll(5)
    pim.combat = true
    pim.C.UI:Open("settings", "modules")
    click(boxOf(pim, "Cute Example"))
    assert(not pim.addons[2].loaded and texts(pim):find("loads after combat", 1, true), "ticked in combat: it waits, and says so")
    check(pim.C.UI.frame, "member settings, modules, a module waiting for combat to end")
    pim.combat = false
    fire(pim, "PLAYER_REGEN_ENABLED")
    assert(pim.addons[2].loaded and pim.C.Modules.byId.example.active and tabsShown(pim) == "race prog shame game me example settings" and not texts(pim):find("after combat", 1, true),
      "loaded as combat ends: " .. tabsShown(pim))

    -- every Settings section and every page, at both sizes, for the officer and the member, the Guide on too
    for _, c in ipairs({ moda, pim }) do boxOf(c, "Guide") end
    moda.C.UI:Open("settings", "modules"); click(boxOf(moda, "Guide"))
    pim.C.UI:Open("settings", "modules"); click(boxOf(pim, "Guide"))
    assert(sectionsShown(moda) == "general vis rules modules race guide prog shame officers example", "the officer's sections: " .. sectionsShown(moda))
    assert(sectionsShown(pim) == "general vis rules modules race guide prog shame example", "the member's: " .. sectionsShown(pim))
    local seen = 0
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      for _, c in ipairs({ moda, pim }) do
        local who = c == moda and "officer" or "member"
        local officer = c.C.Roster:MeOfficer()
        assert(officer == (c == moda), "the officer and the member")
        c.C.UI.frame:SetSize(size[1], size[2])
        for _, sec in ipairs(c.C.SettingsPage.Sections(officer)) do
          c.C.UI:Open("settings", sec.id)
          assert(c.C.UI.section == sec.id, "Settings opens at " .. sec.id)
          -- the officers' sections greyed for the member: every step, button and pair
          if sec.officers and not officer then
            local n = 0
            for _, f in ipairs(c.frames) do
              local t = f.__kind == "Button" and f.label and f.label.__text or ""
              if f:IsVisible() and ((f.__kind == "CheckButton" and f.statId) or t == "-" or t == "+" or t == "Broadcast now" or t:find(" to defaults$")) then
                n = n + 1
                assert(f.__disabled, "greyed for the member in " .. sec.title .. ": " .. tostring(f.statId or t))
              end
            end
            assert(n > 4, "the member's " .. sec.title .. " has its controls: " .. n)
          end
          check(c.C.UI.frame, string.format("%s settings, %s, %dx%d", who, sec.title, size[1], size[2]))
          seen = seen + 1
        end
        for _, m in ipairs(c.C.Modules.Pages(officer)) do
          c.C.UI:Open(m.id)
          assert(c.C.UI.page == m.id, who .. " could open " .. m.id)
          check(c.C.UI.frame, string.format("%s %s, the modules on, %dx%d", who, m.id, size[1], size[2]))
        end
      end
    end
    for _, c in ipairs({ moda, pim }) do c.C.UI.frame:SetSize(1040, 640) end

    -- unticked: its tab, section and event go at once; off in the game's AddOns list for this character
    moda.C.UI:Open("settings", "modules")
    click(boxOf(moda, "Example"))
    assert(tabsShown(moda) == "race guide prog shame game officers me settings" and not sectionsShown(moda):find("example", 1, true), "unticked: its tab and section gone at once")
    fire(moda, "PLAYER_LEVEL_UP", 32)
    assert(ex.private.heard == 1, "its event no longer heard")
    assert(state.Cute_Example and state.Cute_Example[moda.o.guid] == false, "off in the game's AddOns list for this character")
    assert(texts(moda):find("its stats leave at the next login", 1, true), "its stat stays until the next login, and its box says so")
    check(moda.C.UI.frame, "officer settings, modules, a module unticked")
    moda.C.UI:Open("example")
    assert(moda.C.UI.page == "race", "its page asked for opens Race")
    local saved = moda.env.CuteDB
    leave(moda)
    -- the next login: not loaded, no stat, its box unticked; ticked there, on in the list again and loaded
    local again = newClient(char("Moda", { modules = { "Cute_Example" }, addonState = state }))
    login(again, saved)
    tickAll(5)
    assert(not again.addons[2].loaded and not again.C.Modules.byId.example and not again.C.Stats.byId.ex_heard, "the next login does not load it")
    again.C.UI:Open("settings", "modules")
    local box2 = boxOf(again, "Cute Example")
    assert(box2 and not box2:GetChecked(), "its box unticked")
    local n0 = #again.addonCalls
    click(box2)
    local calls = table.concat(again.addonCalls, ", ", n0 + 1)
    assert(again.addons[2].loaded and state.Cute_Example[again.o.guid] == true and calls == "enable Cute_Example, save, load Cute_Example", "ticked again: on in the list for this character, then loaded: " .. calls)
    assert(tabsShown(again) == "race guide prog shame game officers me example settings", "its tab back: " .. tabsShown(again))
    leave(again)

    -- no LoadOnDemand addon: the game loads it while it is on in the list; off in Cute it shows nothing; unticked in
    -- Cute, the game leaves it out at the next login
    local st2 = {}
    local nl = newClient(char("Pim", { modules = { "Cute_Example" }, lod = { Cute_Example = false }, addonState = st2 }))
    login(nl)
    nl.C.UI:Open("race")
    assert(nl.addons[2].loaded and nl.C.Modules.byId.example and not nl.C.Modules.byId.example.active and tabsShown(nl) == "race prog shame game me settings",
      "loaded by the game, off in Cute: no tab")
    nl.C.UI:Open("settings", "modules")
    click(boxOf(nl, "Example"))
    assert(nl.C.Modules.byId.example.active and tabsShown(nl) == "race prog shame game me example settings", "ticked: its tab")
    click(boxOf(nl, "Example"))
    assert(st2.Cute_Example[nl.o.guid] == false and tabsShown(nl) == "race prog shame game me settings", "unticked: off in the list")
    local nlDb = nl.env.CuteDB
    leave(nl)
    local nl2 = newClient(char("Pim", { modules = { "Cute_Example" }, lod = { Cute_Example = false }, addonState = st2 }))
    login(nl2, nlDb)
    assert(not nl2.addons[2].loaded, "the next login: the game does not load it")
    leave(nl2)
    leave(pim)
    print(string.format("modules: a fresh install the dashboard alone, 0.5.0's characters too (What's new says so), a new one and 0.4.0's start without and stay without at the later logins; a module addon found by its toc, loaded at once when ticked (after combat when ticked in combat) with its tab, section, event and stat, gone at once when unticked and off in the game's AddOns list, so the next login does not load it, on again when ticked there; a module the game loads itself shows nothing while off in Cute; %d Settings sections and every page at both sizes for both views", seen))
  end)
end

-- 36b: Cute_Quest, the quest engine as a module addon (tools/cute/Cute_Quest, written by build.py from QuestBank): listed
-- by its toc's title and not loaded; its folder's row ticked, it loads, the saved variables are one table under two
-- names, the engine logs in from the bridge (never from PLAYER_LOGIN, which is past), the catalog is built, the step
-- frame is up and flat; Data.lua is never loaded for a character that keeps every quest module off
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Rone", 1), member("Pim", 3) }, function()
    local state = {}
    local rone = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = state, quest = true }))
    login(rone)
    tickAll(5)
    local M = rone.C.Modules
    assert(#M.found == 1 and M.found[1].name == "Cute_Quest" and M.found[1].lod and M.found[1].title == "Quests", "found by its toc, its row titled Quests from the start (X-Cute-Title): " .. tostring(M.found[1] and M.found[1].title))
    assert(not rone.addons[2].loaded and rone.addons[2].private.Data == nil, "not loaded: no catalog in memory")
    rone.C.UI:Open("settings", "modules")
    local box = checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Quests" end)
    assert(box, "its row in Settings > Modules, Quests before it loads")
    click(box)
    tick(rone, 6) -- (the bridge's login, the engine's first plan four seconds on)
    local a = rone.addons[2]
    local QB = a.private
    assert(a.loaded and QB.Data and QB.Data.Q and QB.Engine == QB and not QB.dormant, "loaded: the catalog built, this copy the engine")
    assert(rone.env.CuteQuestDB and rone.env.QuestBankDB == rone.env.CuteQuestDB and rone.env.CuteQuestDB.settings, "one saved table under both names, the settings in it")
    assert(QB.loginDone and QB.state and QB.state.level == 5, "the engine logged in from the bridge: level " .. tostring(QB.state and QB.state.level))
    assert(rone.env.CuteQuestDB.settings.mapPage == false and rone.env.CuteQuestDB.settings.post.auto == false and rone.env.CuteQuestDB.settings.welcome == nil, "the module's defaults set once")
    assert(rone.env.SlashCmdList.QUESTBANK, "/qb is routed")
    assert(#(rone.env.CuteQuestDB.errors or {}) == 0, "no engine error recorded")
    for _, l in ipairs(rone.chat) do assert(not l:find("QuestBank", 1, true) and not l:find("/qb", 1, true), "the engine said nothing at login: " .. l) end
    -- the Quests module registered as the folder's primary: its tab after the Guide, its section; the Guide's band
    -- shows the step now (the engine's first step for a level-5 warrior in Northshire with quest 7 in the log)
    local function boxOf(c, title) return checkBox(c, function(cb) return cb.label and cb.label:GetText() == title end) end
    assert(M.byId.quests and M.byId.quests.primary and M.byId.quests.active, "Quests on, the folder's primary")
    if not rone.C.Modules.OnKey("guide") then rone.C.Modules.Set("guide", true) end
    assert(tabsShown(rone):find(" guide quests ", 1, true), "the Quests tab after the Guide: " .. tabsShown(rone))
    rone.C.UI:Open("guide")
    local t = texts(rone)
    assert(not t:find("Tick Quests in Settings", 1, true), "the band no longer says to switch Quests on:\n" .. t)
    local steps = QB.Guide.Steps()
    assert(steps[1] and t:find(QB.Guide.Text(steps[1]), 1, true), "the step now in the band: " .. tostring(steps[1] and QB.Guide.Text(steps[1])) .. "\n" .. t)
    local sf = rone.env.QuestBankStep
    assert(sf and sf:IsShown() and sf.__flat, "the step frame up, in Cute's skin")
    check(rone.C.UI.frame, "guide with the quest band")
    -- the officer's guild line whole: at the head's right where it fits, else on a line of its own under the head
    local _, gp = rone.C.Guide.Items(true)
    assert(gp.guild and gp.guild.line and texts(rone):find(gp.guild.line, 1, true), "the guild's line whole on the Guide, nothing cut: " .. tostring(gp.guild and gp.guild.line) .. "\n" .. texts(rone))
    rone.C.UI:Open("quests")
    local tq = texts(rone)
    assert(tq:find("Now", 1, true) and tq:find("Available", 1, true) and tq:find("Most XP a minute", 1, true), "the Quests page's three heads:\n" .. tq)
    -- (xpm) the page's first place is the engine's Now order[1], by XP a minute, its set's XP and minutes on the row
    do
      local order = QB.UI.PlaceGroups(nil, true)
      local rows = rone.C.UI.lists.quests.items
      local g1 = order[1]
      assert(g1 and rows[1].name:GetText() == "Now" and rows[2].name:GetText() == g1.cat.name,
        "the first place is the engine's: " .. tostring(rows[2] and rows[2].name:GetText()) .. " against " .. tostring(g1 and g1.cat.name))
      if #g1.set > 0 then
        assert(rows[2].who:GetText():find("^%d+ quests?, %d+ min$") and rows[2].val:GetText() == QB.Short(g1.setXP) .. " XP",
          "its set's quests, minutes and XP: " .. tostring(rows[2].who:GetText()) .. " / " .. tostring(rows[2].val:GetText()))
      end
    end
    check(rone.C.UI.frame, "quests page")
    -- the right column (quests and minutes) keeps clear of the scroll view's edge and the window's
    local view, win = rectOf(rone.C.UI.scroll), rectOf(rone.C.UI.frame)
    for _, row in ipairs(rone.C.UI.lists.quests.items) do
      if row:IsShown() and row.who:IsShown() then
        local rr = rectOf(row.who)
        assert(rr and rr.r <= view.r - 4 and rr.r <= win.r - 24, string.format("the Quests page's right column at the edge: '%s' ends %d px from the view's edge, %d from the window's", tostring(row.who:GetText()), view.r - rr.r, win.r - rr.r))
      end
    end
    rone.C.UI:Open("settings", "quests")
    local ts = texts(rone)
    assert(ts:find("Accept for me", 1, true) and ts:find("Progress in mob tooltips", 1, true), "the Quests section's rows:\n" .. ts)
    assert(ts:find("Step frame", 1, true) and ts:find("Direction arrow", 1, true), "the step frame's and the arrow's rows are the Quests section's:\n" .. ts)
    -- 6.1.1: the game's quest tracker out of sight while the step frame shows (QuestBank's Guide section has the same)
    local trk = checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Hide the game's quest tracker while the step frame shows" end)
    assert(trk and trk:GetChecked() and rone.env.CuteQuestDB.settings.guide.hideTracker == true, "the tracker's row, on:\n" .. ts)
    click(trk)
    assert(rone.env.CuteQuestDB.settings.guide.hideTracker == false, "unticked: the engine's setting off")
    click(checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Hide the game's quest tracker while the step frame shows" end))
    assert(rone.env.CuteQuestDB.settings.guide.hideTracker == true, "ticked again")
    rone.C.UI:Open("settings", "guide")
    assert(not texts(rone):find("Step frame", 1, true) and not texts(rone):find("Direction arrow", 1, true), "and not the Guide's")
    -- the arrow's row writes the engine's setting and shows or hides the arrow
    rone.C.UI:Open("settings", "quests")
    click(checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Direction arrow" end))
    assert(rone.env.CuteQuestDB.settings.arrow == false and rone.env.QuestBankArrow and not rone.env.QuestBankArrow:IsShown(), "the arrow's row: off")
    click(checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Direction arrow" end))
    assert(rone.env.CuteQuestDB.settings.arrow == true and rone.env.QuestBankArrow:IsShown(), "and on again")
    -- Route, ticked: keyed under the folder, its tab; the band's summary and run button, the legs numbered
    rone.C.UI:Open("settings", "modules")
    click(boxOf(rone, "Route"))
    assert(M.byId.route and M.byId.route.key == "Cute_Quest:route" and M.byId.route.active and tabsShown(rone):find("route", 1, true), "Route on, keyed under the folder: " .. tabsShown(rone))
    rone.C.UI:Open("route")
    local tr = texts(rone)
    assert(tr:find(" XP, level ", 1, true) and (tr:find("Start run", 1, true) or tr:find("End run", 1, true)), "the route's band: the summary and the run button:\n" .. tr)
    assert(tr:find("^1%. ") or tr:find("\n1%. ") or tr:find("Nothing to hand in yet.", 1, true), "the legs numbered, or the empty line:\n" .. tr)
    check(rone.C.UI.frame, "route page")
    rone.C.UI:Open("settings", "route")
    assert(texts(rone):find("Follow", 1, true) and texts(rone):find("hearthstone", 1, true), "the Route section's rows")
    -- Journal and Gear: the engine's pages on hosts under the scroll area, one shown at a time
    rone.C.UI:Open("settings", "modules")
    for _, name in ipairs({ "Journal", "Gear" }) do click(boxOf(rone, name)) end
    rone.C.UI:Open("journal")
    local host = rone.C.UI.hosts.journal
    assert(host and host:IsShown() and #(host.__kids or {}) > 0, "the journal attached to its host")
    check(rone.C.UI.frame, "journal page")
    rone.C.UI:Open("gear")
    assert(not host:IsShown() and rone.C.UI.hosts.gear and rone.C.UI.hosts.gear:IsShown(), "the gear host shown, the journal's hidden")
    check(rone.C.UI.frame, "gear page")
    -- the Journal's four kinds are its band's chips, no section: a click flips one and the journal draws again
    rone.C.UI:Open("journal")
    local function chip(label) for _, b in ipairs(rone.C.UI.bandButtons.items) do if b:IsShown() and b.label:GetText() == label then return b end end end
    assert(chip("Bosses") and chip("Rares") and chip("Trash") and chip("Chests and events"), "the four kinds as chips:\n" .. texts(rone))
    assert(rone.env.CuteQuestDB.settings.djShow.trash == false and not sectionsShown(rone):find("journal", 1, true), "trash off by the engine's default; no Journal section: " .. sectionsShown(rone))
    press(chip("Trash"))
    assert(rone.env.CuteQuestDB.settings.djShow.trash == true, "a chip clicked: the kind shown")
    press(chip("Trash"))
    assert(rone.env.CuteQuestDB.settings.djShow.trash == false, "and hidden again")
    rone.C.UI:Open("settings", "gear")
    assert(texts(rone):find("2 levels ahead", 1, true) and not texts(rone):find("An upgrade is", 1, true), "the Gear section: its one row, no note")
    -- Map and Camp: no page, a section each; their switches set the engine's flags, on and off with the module
    rone.C.UI:Open("settings", "modules")
    for _, name in ipairs({ "Map", "Camp" }) do click(boxOf(rone, name)) end
    assert(not tabsShown(rone):find("map", 1, true) and not tabsShown(rone):find("camp", 1, true), "no tab for a module without a page: " .. tabsShown(rone))
    assert(sectionsShown(rone):find("map", 1, true) and sectionsShown(rone):find("camp", 1, true), "their sections: " .. sectionsShown(rone))
    -- the rows that went: the frame's lock (its own menu has it), the engine's note of what the game shows (dead in
    -- Cute), the minimap's far view, the sleeping bag and the sellers
    rone.C.UI:Open("settings", "quests")
    assert(not texts(rone):find("Lock the step frame", 1, true) and not texts(rone):find("foreverrank.com", 1, true) and texts(rone):find("Step frame", 1, true), "Quests: no lock row, no note row")
    rone.C.UI:Open("settings", "map")
    assert(not texts(rone):find("far view", 1, true) and texts(rone):find("Route pins on the world map", 1, true), "Map: no far view row")
    -- 6.1.1: low-level (grey) quests' ! off unless asked (QuestBank's map section has the same row)
    local low = checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Low-level quests" end)
    assert(low and not low:GetChecked() and rone.env.CuteQuestDB.settings.mapLowLevel == false, "Map: the Low-level quests row, off:\n" .. texts(rone))
    click(low)
    assert(rone.env.CuteQuestDB.settings.mapLowLevel == true, "ticked: the engine's setting on")
    click(checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Low-level quests" end))
    assert(rone.env.CuteQuestDB.settings.mapLowLevel == false, "and off again")
    -- 6.1.1: one stroke, you to where the arrow leads; the whole route when asked (QuestBank's map section has it too)
    local whole = checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Show the whole route" end)
    assert(whole and not whole:GetChecked() and rone.env.CuteQuestDB.settings.wholeRoute == false, "Map: the whole route's row, off:\n" .. texts(rone))
    click(whole)
    assert(rone.env.CuteQuestDB.settings.wholeRoute == true, "ticked: the engine's setting on")
    click(checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Show the whole route" end))
    rone.C.UI:Open("settings", "camp")
    assert(not texts(rone):find("Sleeping bag", 1, true) and not texts(rone):find("Sellers", 1, true) and texts(rone):find("Camp bar", 1, true), "Camp: the bar, the banner and the light alone:\n" .. texts(rone))
    -- 6.1.1: the party's buffs (QuestBank's camp section has the same row); six rows at most in Camp and in Map
    assert(texts(rone):find("Party members' buffs", 1, true) and texts(rone):find("Missing buffs", 1, true), "Camp: the missing-buffs and party rows:\n" .. texts(rone))
    local function rowsOf(id)
      local n = 0
      local col = setmetatable({}, { __index = function(_, k) return function() if k == "Check" or k == "Choice" or k == "Step" or k == "Edit" then n = n + 1 end end end })
      M.byId[id].settings(M.byId[id], col)
      return n
    end
    assert(rowsOf("camp") <= 6 and rowsOf("map") <= 6, string.format("Camp and Map keep six rows at most: %d, %d", rowsOf("camp"), rowsOf("map")))
    local s = rone.env.CuteQuestDB.settings
    assert(s.mapIcons == true and s.pins == true and s.minimapGivers == true and s.campBar == true and s.glow.on == true, "on: the switches on")
    rone.C.UI:Open("settings", "map")
    click(checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "A ! on the minimap for quests you can take" end))
    assert(s.minimapGivers == false, "a row writes the engine's setting")
    rone.C.UI:Open("settings", "modules")
    click(boxOf(rone, "Map")); click(boxOf(rone, "Camp"))
    assert(s.mapIcons == false and s.pins == false and s.minimapPins == false and s.campBar == false and s.glow.on == false, "off: the switches off")
    for _, name in ipairs({ "Map", "Camp" }) do click(boxOf(rone, name)) end
    -- every page at both sizes for an officer with every quest module on
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      rone.C.UI.frame:SetSize(size[1], size[2])
      for _, page in ipairs({ "guide", "quests", "route", "journal", "gear", "settings" }) do
        rone.C.UI:Open(page)
        check(rone.C.UI.frame, string.format("officer, every quest module on: %s, %dx%d", page, size[1], size[2]))
      end
      for _, section in ipairs({ "quests", "route", "map", "gear", "camp", "guide" }) do
        rone.C.UI:Open("settings", section)
        check(rone.C.UI.frame, string.format("officer, every quest module on: settings %s, %dx%d", section, size[1], size[2]))
      end
    end
    rone.C.UI.frame:SetSize(1040, 640)
    -- unticked: the engine's guide off, the frame hidden, the band says so again
    rone.C.UI:Open("settings", "modules")
    click(boxOf(rone, "Quests"))
    assert(not M.byId.quests.active and rone.env.CuteQuestDB.settings.guide.on == false and not sf:IsShown(), "off: the engine's guide off, the frame hidden")
    rone.C.UI:Open("guide")
    assert(texts(rone):find("Tick Quests in Settings, Modules", 1, true), "the band says so again")
    rone.C.UI:Open("settings", "modules")
    click(boxOf(rone, "Quests"))
    assert(M.byId.quests.active and sf:IsShown(), "on again: the frame back")
    assert(#(rone.env.CuteQuestDB.errors or {}) == 0, "no engine error recorded")
    leave(rone)
    print("cute quest: listed by its toc and not loaded; ticked, the engine's copy loads, logs in from the bridge, builds its catalog; one saved table under both names; /qb routed")
  end)
end

-- 36b (ii): the switches follow the boxes, on the saved table. The module's files register as they load, before the
-- saved variables arrive (ADDON_LOADED), and 0.7.0's first build ran each switch then, on a table thrown away a moment
-- later: Quests ticked alone left the engine's defaults on (map icons, route pins, the minimap route, the camp bar and
-- the light, with Map and Camp unticked), Map ticked alone set nothing, at the next login with Quests alone the guide
-- stayed off, and the once-a-session prune of the runs ran on the thrown-away table. Now the Bridge runs each switch
-- again once the table is in; a switch off keeps what its flags were for the switch on, so a row's choice survives
-- off and on and a login; Quests off puts the arrow away and on brings it back
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
  isolated({ member("Rone", 1) }, function()
    local state = {}
    local function client() return newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = state, quest = true })) end
    local function flags(s) return string.format("mapIcons=%s pins=%s minimapPins=%s minimapLines=%s minimapGivers=%s mmExtended=%s campBar=%s buffs=%s glow=%s guide=%s frame=%s arrow=%s",
      tostring(s.mapIcons), tostring(s.pins), tostring(s.minimapPins), tostring(s.minimapLines), tostring(s.minimapGivers), tostring(s.mmExtended),
      tostring(s.campBar), tostring(s.remind.buffs), tostring(s.glow.on), tostring(s.guide.on), tostring(s.guide.frame), tostring(s.arrow)) end
    local function stepShown(c) return c.env.QuestBankStep ~= nil and c.env.QuestBankStep:IsShown() end
    -- a saved table from before with more runs than the engine keeps: the prune must run on it, not on a throwaway
    local runs = {}
    for i = 1, 25 do runs[i] = { started = i, ended = i + 1, done = {} } end
    local c = client()
    c.env.CuteQuestDB = { runs = runs }
    login(c); tickAll(5)
    c.C.Modules.Set("Cute_Quest", true); tick(c, 6)
    local QB, s = c.addons[2].private, c.env.CuteQuestDB.settings
    assert(QB.ready and c.env.QuestBankDB == c.env.CuteQuestDB and #c.env.CuteQuestDB.runs == QB.MAX_RUNS, "the prune ran on the saved table: " .. #c.env.CuteQuestDB.runs .. " runs kept")
    assert(s.guide.on == true and s.guide.frame == true and stepShown(c), "Quests ticked alone: the guide on, the frame up: " .. flags(s))
    assert(s.mapIcons == false and s.pins == false and s.minimapPins == false and s.minimapLines == false and s.minimapGivers == false and s.mmExtended == false,
      "Map unticked: no quest icons, no route pins, no route on the minimap, no far view: " .. flags(s))
    assert(s.campBar == false and s.remind.buffs == false and s.remind.party == false and s.glow.on == false, "Camp unticked: no camp bar, no buffs banner, no party's buffs, no light: " .. flags(s))
    assert(s.cuteOff.map.mapIcons == true and s.cuteOff.camp.campBar == true, "what the flags were is kept for the switch on")
    -- Map ticked: its flags back as they were (the engine's defaults); a row's choice survives off and on
    c.C.Modules.Set("Cute_Quest:map", true); tick(c, 1)
    assert(s.mapIcons == true and s.pins == true and s.minimapPins == true and s.minimapLines == true and s.minimapGivers == true and s.mmExtended == true and s.cuteOff.map == nil, "Map ticked: every flag back on: " .. flags(s))
    s.minimapGivers = false -- (the row "A ! on the minimap for quests you can take")
    c.C.Modules.Set("Cute_Quest:map", false); tick(c, 1)
    assert(s.mapIcons == false and s.minimapGivers == false, "Map unticked again: off")
    c.C.Modules.Set("Cute_Quest:map", true); tick(c, 1)
    assert(s.mapIcons == true and s.pins == true and s.minimapGivers == false, "Map ticked again: the row's choice kept: " .. flags(s))
    -- Camp ticked: the bar and the light; the light's switch goes through Glow.Set, which puts the game's settings back
    c.C.Modules.Set("Cute_Quest:camp", true); tick(c, 1)
    assert(s.campBar == true and s.remind.buffs == true and s.remind.party == true and s.glow.on == true, "Camp ticked: the bar, the banner, the party's buffs, the light: " .. flags(s))
    c.C.Modules.Set("Cute_Quest:camp", false); tick(c, 1)
    assert(s.campBar == false and s.glow.on == false, "Camp unticked: off again: " .. flags(s))
    -- Quests off: the guide off, the arrow put away; on: the arrow back
    assert(s.arrow == true, "the engine's arrow on (its default)")
    c.C.Modules.Set("Cute_Quest", false); tick(c, 1)
    assert(s.guide.on == false and s.arrow == false and s.cuteArrow == true and not stepShown(c), "Quests unticked: the guide off, the arrow put away: " .. flags(s))
    c.C.Modules.Set("Cute_Quest", true); tick(c, 1)
    assert(s.guide.on == true and s.arrow == true and s.cuteArrow == nil and stepShown(c) and c.env.QuestBankArrow and c.env.QuestBankArrow:IsShown(), "Quests ticked again: the arrow back: " .. flags(s))
    -- the step frame hidden by its row stays hidden over the switch and a login (0.7.0's switch set it shown again)
    s.guide.frame = false; QB.StepFrame.Apply()
    assert(not stepShown(c), "the frame hidden by its row")
    c.C.Modules.Set("Cute_Quest:map", false); tick(c, 1)
    c.C.Modules.Set("Cute_Quest", false); tick(c, 1)
    assert(#(c.env.CuteQuestDB.errors or {}) == 0, "no engine error recorded")
    local db, qdb = c.env.CuteDB, copy(c.env.CuteQuestDB)
    leave(c)
    -- the next login, nothing on: Map ticked alone loads the addon and sets its flags alone (its row's choice kept)
    local c2 = client()
    c2.env.CuteQuestDB = qdb
    login(c2, db); tickAll(5)
    assert(not c2.addons[2].loaded, "nothing on: not loaded")
    c2.C.Modules.Set("Cute_Quest:map", true); tick(c2, 6)
    local s2 = c2.env.CuteQuestDB.settings
    assert(c2.addons[2].loaded and s2.mapIcons == true and s2.pins == true and s2.minimapPins == true and s2.mmExtended == true and s2.minimapGivers == false,
      "Map ticked alone at a login: its flags on, the row's choice kept: " .. flags(s2))
    assert(s2.guide.on == false and s2.arrow == false and s2.campBar == false and s2.glow.on == false and not stepShown(c2), "Quests and Camp unticked: the guide, the arrow, the bar and the light off: " .. flags(s2))
    c2.C.Modules.Set("Cute_Quest:map", false); tick(c2, 1)
    assert(#(c2.env.CuteQuestDB.errors or {}) == 0, "no engine error recorded")
    local db2, qdb2 = c2.env.CuteDB, copy(c2.env.CuteQuestDB)
    leave(c2)
    -- the next login, Quests ticked alone: the guide on, the arrow back, the frame still hidden as its row left it; the
    -- Guide's band shows the step
    local c3 = client()
    c3.env.CuteQuestDB = qdb2
    login(c3, db2); tickAll(5)
    c3.C.Modules.Set("Cute_Quest", true); tick(c3, 6)
    local s3, QB3 = c3.env.CuteQuestDB.settings, c3.addons[2].private
    assert(s3.guide.on == true and s3.arrow == true and s3.cuteArrow == nil and s3.guide.frame == false and not stepShown(c3), "Quests ticked alone at a login: the guide on, the arrow back, the frame as its row left it: " .. flags(s3))
    assert(s3.mapIcons == false and s3.campBar == false and s3.glow.on == false, "Map and Camp still off: " .. flags(s3))
    if not c3.C.Modules.OnKey("guide") then c3.C.Modules.Set("guide", true) end
    c3.C.UI:Open("guide")
    local steps = QB3.Guide.Steps()
    assert(steps[1] and texts(c3):find(QB3.Guide.Text(steps[1]), 1, true) and not texts(c3):find("Tick Quests", 1, true), "the band shows the step now:\n" .. texts(c3))
    -- the frame's row ticked again: up at this login and the next, where Cute loads the module itself (Quests still on)
    s3.guide.frame = true; QB3.StepFrame.Apply()
    assert(stepShown(c3), "the frame back by its row")
    local db3, qdb3 = c3.env.CuteDB, copy(c3.env.CuteQuestDB)
    leave(c3)
    local c4 = client()
    c4.env.CuteQuestDB = qdb3
    login(c4, db3); tickAll(6)
    local s4 = c4.env.CuteQuestDB.settings
    assert(c4.addons[2].loaded and c4.C.Modules.byId.quests.active and s4.guide.on == true and s4.arrow == true and stepShown(c4), "loaded by Cute at the login with Quests on: the guide on, the frame up: " .. flags(s4))
    assert(s4.mapIcons == false and s4.minimapGivers == false and s4.campBar == false, "Map and Camp still off: " .. flags(s4))
    assert(#(c4.env.CuteQuestDB.errors or {}) == 0, "no engine error recorded")
    leave(c4)
    print("cute quest: the switches run on the saved table, each flag following its box; a row's choice and the frame's survive off, on and a login; Quests off puts the arrow away, on brings it back")
  end)
end

-- 36b (iii): the engine's chat for a Cute-only player. Its lines carry Cute's prefix (0.7.0's first build said
-- "QuestBank" in a guild that never installed it), and the copy is quiet: a quest complete, one gone from the log, a
-- waypoint clicked, a run's start and end and the "/qb errors ... Discord" line say nothing (the step frame and the
-- arrow say those things); the rest of the engine's lines still come
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Rone", 1) }, function()
    local c = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    login(c); tickAll(5)
    c.C.Modules.Set("Cute_Quest", true); tick(c, 6)
    local QB = c.addons[2].private
    assert(QB.quiet == true and QB.loggedIn, "the copy quiet, logged in")
    local function said(fn)
      local n0 = #c.chat
      fn()
      return table.concat(c.chat, "\n", n0 + 1)
    end
    assert(said(function() QB:Print("probe line") end) == c.C.COLOR .. "Cute|r: probe line", "Cute's prefix: " .. c.chat[#c.chat])
    assert(said(function() assert(QB.API.SayWaypoint(1453, 50, 50, "Northshire Abbey", true) == true) end) == "", "a waypoint clicked: nothing said")
    assert(said(function() QB.Run.Start(); tick(c, 1); QB.Run.Stop() end) == "" and QB.Run.Get() == nil, "a run started and ended: nothing said")
    -- the quest in the log complete, then gone from the log: nothing said either way
    local id = next(c.o.log)
    c.complete = { [id] = true }
    assert(said(function() fire(c, "QUEST_LOG_UPDATE"); tick(c, 1) end) == "" and QB.wasComplete[id] == true, "a quest complete: nothing said")
    c.o.log[id] = nil
    assert(said(function() fire(c, "QUEST_LOG_UPDATE"); tick(c, 1) end) == "" and QB:Plan().removed[id], "a quest gone from the log without a hand-in: nothing said, the plan knows")
    assert(said(function() QB.Err.Record("a probe error", "", "probe") end) == "" and c.env.CuteQuestDB.errors[1].msg == "a probe error", "the errors line: nothing said, the error recorded")
    c.env.CuteQuestDB.errors = nil
    leave(c)
    print("cute quest: the engine's chat carries Cute's prefix; a quest complete or gone, a waypoint, a run and the errors line say nothing")
  end)
end

-- 36b (iv): the band's party rows. The engine's party steps (one a member of your group, by name) go in the band under
-- your own and the time to level, three at most; the rest fold into one line, "and N more in your group", whose
-- tooltip names them all. A raid of five filled 0.7.0's first band with five rows
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Rone", 1) }, function()
    local c = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    login(c); tickAll(5)
    c.C.Modules.Set("Cute_Quest", true); tick(c, 6)
    if not c.C.Modules.OnKey("guide") then c.C.Modules.Set("guide", true) end
    local QB = c.addons[2].private
    local party = {}
    for i, n in ipairs({ "Ada", "Bo", "Cy", "Di", "Ed" }) do party[i] = { name = n, class = "MAGE", text = "Kill Kobold Vermin " .. i .. "/8" } end
    local real = QB.Guide.MemberSteps
    QB.Guide.MemberSteps = function() return party end
    c.C.UI:Open("guide")
    local t = texts(c)
    assert(t:find("Ada: Kill Kobold Vermin 1/8", 1, true) and t:find("Cy: Kill Kobold Vermin 3/8", 1, true) and not t:find("Di: Kill", 1, true) and not t:find("Ed: Kill", 1, true),
      "three of the five in the band:\n" .. t)
    assert(t:find("and 2 more in your group", 1, true), "the rest folded into one line:\n" .. t)
    local more
    for _, l in ipairs(c.C.UI.bandLines.items) do if l:IsShown() and l.name:GetText() == "and 2 more in your group" then more = l end end
    assert(more and tipOf(more):find("Di: Kill Kobold Vermin 4/8", 1, true) and tipOf(more):find("Ed: Kill Kobold Vermin 5/8", 1, true), "its tooltip names them: " .. tostring(more and tipOf(more)))
    check(c.C.UI.frame, "guide, a party of five in the band")
    party[4], party[5] = nil, nil
    c.C.UI:Draw()
    assert(not texts(c):find("more in your group", 1, true) and texts(c):find("Cy: Kill", 1, true), "three: no fold")
    QB.Guide.MemberSteps = real
    leave(c)
    print("cute quest: the band shows three of the party's steps, the rest in one line's tooltip")
  end)
end

-- 36b (v): the band's line while Quests is ticked without a step. "Tick Quests in Settings, Modules" is for Quests off
-- alone (0.7.0's first build said it with Quests ticked while the engine had not read the log, and while the addon
-- waited for combat to end); ticked, the band says what it waits for: "Quests loads after combat." until the addon
-- loads, "Reading your quest log." until the engine has read it
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Rone", 1) }, function()
    local c = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    login(c); tickAll(5)
    if not c.C.Modules.OnKey("guide") then c.C.Modules.Set("guide", true) end
    c.C.UI:Open("guide")
    assert(texts(c):find("Tick Quests in Settings, Modules for the step now.", 1, true), "off: where to switch it on")
    c.combat = true
    c.C.Modules.Set("Cute_Quest", true)
    assert(not c.addons[2].loaded and c.C.Modules.pending.Cute_Quest and c.C.Modules.Waiting(), "ticked in combat: waiting")
    c.C.UI:Open("guide")
    local t = texts(c)
    assert(t:find("Quests loads after combat.", 1, true) and not t:find("Tick Quests", 1, true), "the band says it loads after combat:\n" .. t)
    check(c.C.UI.frame, "guide, Quests waiting for combat to end")
    c.combat = false
    fire(c, "PLAYER_REGEN_ENABLED")
    tick(c, 6)
    local QB = c.addons[2].private
    assert(c.addons[2].loaded and QB.logReady and not c.C.Modules.Waiting(), "loaded as combat ends, the log read")
    c.C.UI:Open("guide")
    t = texts(c)
    local steps = QB.Guide.Steps()
    assert(steps[1] and t:find(QB.Guide.Text(steps[1]), 1, true) and not t:find("after combat", 1, true), "the step now:\n" .. t)
    -- the log not read yet (the game's QUEST_LOG_UPDATE still to come): the band says so, never to tick Quests
    QB.logReady = nil
    c.C.UI:Draw()
    t = texts(c)
    assert(t:find("Reading your quest log.", 1, true) and not t:find("Tick Quests", 1, true), "the log unread: the band says so:\n" .. t)
    QB.logReady = true
    c.C.UI:Draw()
    assert(texts(c):find(QB.Guide.Text(steps[1]), 1, true), "read: the step again")
    leave(c)
    print("cute quest: the band says what Quests waits for while ticked (combat's end, the log); Tick Quests is for off alone")
  end)
end

-- [stage: engine] that stage's tests go right below this line
-- 36e (the launch round's engine, Cute's side). Cute_Quest inside Cute, as a new member meets it: the engine never
-- talks to the whole guild (0.7.0's 1S, 1Q and 1R went to GUILD around the officers' Who sees what; off for a fresh
-- install and once for a 0.7 save), the party still hears it; the minimap is the engine's only while the Map module is
-- on (a right-click otherwise the game's ping, the wheel the game's zoom, no tracking entry, Target tracking left alone);
-- a step without a quest clicked opens the Quests page, never Race; the engine's errors and a call the game blocked are
-- on /cute errors; PLAYER_ENTERING_WORLD reaches the engine's frames once whether Cute loads it in that event or in
-- play; the engine's words name Cute, never QuestBank or /qb; a hand-in says nothing
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  local function copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = copy(v) end return o end
  isolated({ member("Rone", 1), member("Pim", 3) }, function()
    local c = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    login(c); tickAll(5)
    c.C.Modules.Set("Cute_Quest", true)
    local QB = c.addons[2].private
    -- PLAYER_ENTERING_WORLD, ticked in play: every frame of the engine's that waits on it hears it once, a frame later
    local heardPEW = {}
    for _, key in ipairs({ "Travel", "Glow", "Timer", "Target", "Mini" }) do
      local m = QB[key]
      local fr = m and (m.eventFrame or m.frame)
      assert(fr, "the engine's " .. key .. " has its event frame")
      heardPEW[key] = 0
      fr:HookScript("OnEvent", function(_, event) if event == "PLAYER_ENTERING_WORLD" then heardPEW[key] = heardPEW[key] + 1 end end)
    end
    tick(c, 6)
    for key, n in pairs(heardPEW) do assert(n == 1, "ticked in play: the engine's " .. key .. " heard PLAYER_ENTERING_WORLD once: " .. n) end
    local s = c.env.CuteQuestDB.settings
    -- the guild: nothing of the engine's to GUILD, its own hello at 12 s included; the party still hears it
    assert(s.share.guild == false and s.share.party == true and s.cuteGuildOff == true, "a fresh install: the engine shares with the party alone")
    tick(c, 20)
    for _, m in ipairs(c.outbox) do assert(m[3] ~= "GUILD", "nothing of the engine's to the guild: " .. tostring(m[2]):sub(1, 40)) end
    -- (the look above can see one: with the switch on, the engine's share goes to GUILD)
    s.share.guild = true; QB.Sync:Broadcast(true); tick(c, 1)
    local seenGuild = false
    for _, m in ipairs(c.outbox) do if m[3] == "GUILD" then seenGuild = true end end
    assert(seenGuild, "with the switch on a share goes to GUILD: the look sees it")
    s.share.guild = false
    for k = #c.outbox, 1, -1 do c.outbox[k] = nil end
    -- the minimap with the Map module off: the game's own
    local Mini, mini = QB.Mini, c.env.Minimap
    assert(not Mini.Owned() and not Mini.hooked, "Map off: the minimap is not the engine's, nothing hooked")
    local clicks, wheels, menus = c.gameClicks or 0, c.gameWheel or 0, #c.contextMenus
    mini.__scripts.OnMouseUp(mini, "RightButton"); tick(c, 1)
    mini.__scripts.OnMouseWheel(mini, 1)
    assert((c.gameClicks or 0) == clicks + 1 and #c.contextMenus == menus and (c.gameWheel or 0) == wheels + 1, "Map off: a right-click is the game's ping, the wheel the game's zoom")
    assert(c.menus == nil or c.menus.MENU_MINIMAP_TRACKING == nil, "Map off: no entry in the game's tracking menu")
    assert(c.tracking[2].active == false, "Map off: Target tracking left as the game has it")
    -- Map on: the engine's (its menu on a right-click, Target tracking)
    c.C.Modules.Set("Cute_Quest:map", true); tick(c, 1)
    assert(Mini.Owned() and Mini.hooked, "Map on: the minimap is the engine's")
    menus = #c.contextMenus
    mini.__scripts.OnMouseUp(mini, "RightButton"); tick(c, 1)
    assert(#c.contextMenus == menus + 1, "Map on: a right-click opens the engine's menu")
    local named = false
    for _, e in ipairs(c.contextMenus[#c.contextMenus]) do
      assert(not (e.text or ""):find("QuestBank", 1, true), "the minimap's menu names Cute: " .. tostring(e.text))
      if e.text == "Cute settings" then named = true end
    end
    assert(named, "the menu's last line: Cute settings")
    assert(c.tracking[2].active == true, "Map on: Target on the minimap")
    -- (the review round) the engine's size for the minimap while Map is on (Ctrl-wheel)
    local cont = c.env.MinimapCluster.MinimapContainer
    local s0 = cont:GetScale() or 1
    c.env.MinimapCluster.__anchored = nil
    Mini.SetScale(1.5)
    assert(math.abs((cont:GetScale() or 1) - 1.5) < 0.01, "Map on: the engine sizes the minimap")
    -- Map off again: the game's again (the minimap's own update, a frame of the game's, sees it too)
    local ov = c.env.QuestBankMinimap
    local function frameTick() if ov and ov.__scripts.OnUpdate then ov.__scripts.OnUpdate(ov, 1) end end
    c.C.Modules.Set("Cute_Quest:map", false); tick(c, 1); frameTick()
    clicks, wheels, menus = c.gameClicks or 0, c.gameWheel or 0, #c.contextMenus
    mini.__scripts.OnMouseUp(mini, "RightButton"); tick(c, 1)
    mini.__scripts.OnMouseWheel(mini, 1)
    assert((c.gameClicks or 0) == clicks + 1 and #c.contextMenus == menus and (c.gameWheel or 0) == wheels + 1, "Map off again: the game's ping and zoom")
    -- (the review round) and what the engine set goes back: Target tracking as the game had it before, the game's size
    -- and place (Edit Mode's anchor); the engine's own choices kept for Map on again
    assert(c.tracking[2].active == false, "Map off again: Target tracking back as the game had it")
    assert(math.abs((cont:GetScale() or 1) - s0) < 0.01 and c.env.MinimapCluster.__anchored, "Map off again: the game's size and place: " .. tostring(cont:GetScale()))
    assert(Mini.FreeDB().scale == 1.5 and Mini.TrackDB().target == true, "the engine's size and Target kept for Map on again")
    c.C.Modules.Set("Cute_Quest:map", true); tick(c, 1); frameTick()
    assert(c.tracking[2].active == true and math.abs((cont:GetScale() or 1) - 1.5) < 0.01, "Map on again: Target and the engine's size back")
    c.C.Modules.Set("Cute_Quest:map", false); tick(c, 1); frameTick()
    assert(c.tracking[2].active == false and math.abs((cont:GetScale() or 1) - s0) < 0.01, "and off: the game's again")
    -- a step without a quest (travel, train, grind, corpse) clicked: the Quests page, never Race; Route on: Route
    QB.UI:Open(3)
    assert(c.C.UI.page == "quests", "Route off: a travel step opens Quests: " .. tostring(c.C.UI.page))
    QB.Arrow:Set(true)
    local arrowTip = tipOf(c.env.QuestBankArrow)
    assert(arrowTip:find("Click: the Quests page.", 1, true) and not arrowTip:find("Route page", 1, true), "the arrow's click, as it is: " .. arrowTip)
    -- (the review round) and a step with no quest in the step frame: its tooltip names the page its click opens
    do
      local G0, SF0 = QB.Guide, QB.StepFrame
      local keep0 = G0.steps
      G0.steps = { { kind = "travel", text = "Fly to Ironforge", c = 0, wx = -4821, wy = -1155 } }
      G0.ver = G0.ver + 1; SF0.Apply(); SF0.Refresh()
      local row = c.env.QuestBankStep.rows[1]
      local rowTip = tipOf(row)
      if row.__scripts.OnLeave then row.__scripts.OnLeave(row) end
      assert(rowTip:find("Click: the Quests page.", 1, true) and not rowTip:find("the way there", 1, true), "a travel step's click, as it is: " .. rowTip)
      G0.steps = keep0; G0.ver = G0.ver + 1; SF0.Refresh()
    end
    c.C.Modules.Set("Cute_Quest:route", true); tick(c, 1)
    QB.UI:Open(3)
    assert(c.C.UI.page == "route", "Route on: the Route page: " .. tostring(c.C.UI.page))
    -- (the review round) a stop out of a town on the Route page: its place in words, as the map's pins, the step frame
    -- and the arrow name it, not Model.lua's zone and spot (kept for matching)
    do
      local D = QB.Data
      local argus
      for i, n in ipairs(D.NPC) do if n[1] == "Smith Argus" then argus = i end end
      local keepPlan, keepMode = QB.routePlan, QB.Target.Mode
      QB.Target.Mode = function() return "plan" end
      QB.routePlan = { legs = { { stop = { name = "Elwynn Forest (42, 65)", npcs = { argus }, m = 1429, x = 42, y = 65 }, rows = {}, t = 51, travel = 4, kind = "foot", arrive = 5, leave = 5 } },
                       xp = 0, level = 5, t = 51, byQuest = {} }
      c.C.UI:Open("route")
      local shown = texts(c)
      assert(shown:find("1. Goldshire", 1, true) and not shown:find("Elwynn Forest (", 1, true), "the Route page's stop: its place:\n" .. shown)
      QB.routePlan, QB.Target.Mode = keepPlan, keepMode
    end
    c.C.Modules.Set("Cute_Quest:route", false); tick(c, 1)
    -- the engine's words: Cute's name, no /qb
    local G, SF, A = QB.Guide, QB.StepFrame, QB.Arrow
    assert(G.Text({ kind = "reward", name = "Talbar Mantle" }) == "Choose a reward: Talbar Mantle is Cute's pick", "the reward step names Cute")
    local keep = G.steps
    G.steps = {}
    G.ver = G.ver + 1
    SF.Refresh()
    local sfr = c.env.QuestBankStep
    assert(sfr and sfr.now:GetText() == "Nothing to do: /cute quests", "an empty step frame points at Cute's page: " .. tostring(sfr and sfr.now:GetText()))
    G.steps = keep; G.ver = G.ver + 1; SF.Refresh()
    s.arrowMode = "pin"; s.arrowPin = nil
    A:Set(true); A:Update()
    assert(c.env.QuestBankArrow.dist:GetText() == "Click a quest or a stop in Cute", "the arrow's empty line names Cute: " .. tostring(c.env.QuestBankArrow.dist:GetText()))
    s.arrowMode = nil
    A:Menu()
    local looked = false
    for _, e in ipairs(c.contextMenus[#c.contextMenus]) do
      if (e.text or ""):find("^Look: ") then looked = e.text end
      assert(not (e.text or ""):find("QuestBank", 1, true) and not (e.text or ""):find("/qb", 1, true), "the arrow's menu names Cute: " .. tostring(e.text))
    end
    assert(looked == "Look: Cute's arrow", "the arrow's look: " .. tostring(looked))
    -- a hand-in: nothing said
    local n0 = #c.chat
    fire(c, "QUEST_TURNED_IN", next(c.o.log), 450); tick(c, 1)
    assert(#c.chat == n0, "a hand-in: nothing said: " .. tostring(c.chat[#c.chat]))
    -- the engine's errors and a call the game blocked: on /cute errors. (The review round) a blocked call is noted
    -- quietly, no line in chat (Cute's "ran into a problem" included); an engine error says so once a session, as
    -- Cute's own do; a repeat of either goes no further than the engine's own count (no Cute.Safe each time: an error
    -- in an OnUpdate repeats twenty times a second)
    c.env.CUTE_DEV = false
    local safeCalls, realSafe = 0, c.env.Cute.Safe
    c.env.Cute.Safe = function(...) safeCalls = safeCalls + 1; return realSafe(...) end
    local bf = QB.blockedFrame
    local b0 = #c.chat
    for _ = 1, 3 do bf.__scripts.OnEvent(bf, "ADDON_ACTION_BLOCKED", "Cute_Quest", "Frame:SetPassThroughButtons()") end
    assert(#c.chat == b0, "a blocked call: nothing in chat: " .. tostring(c.chat[#c.chat]))
    assert(safeCalls == 0, "a blocked call: noted, never raised through Cute.Safe: " .. safeCalls)
    for _ = 1, 3 do QB.Err.Record("an engine probe error", "", "probe") end
    assert(safeCalls == 1, "an engine error three times: to Cute once: " .. safeCalls)
    c.env.Cute.Safe = realSafe
    c.env.CUTE_DEV = true
    local list, probe, held = c.env.CuteDB.errors or {}, nil, nil
    for _, e in ipairs(list) do
      if e.msg == "an engine probe error" and e.where == "quest engine: probe" then probe = e end
      if e.msg:find("the game blocked Frame:SetPassThroughButtons()", 1, true) and e.where == "quest engine: blocked call" then held = e end
    end
    assert(probe and held, "both on Cute's list: " .. #list)
    for i = n0 + 1, #c.chat do assert(not c.chat[i]:find("stopped by the game", 1, true) and not c.chat[i]:find("/qb", 1, true), "no engine line about it: " .. c.chat[i]) end
    local e0 = #c.chat
    c.env.SlashCmdList.CUTE("errors")
    assert(table.concat(c.chat, "\n", e0 + 1):find("an engine probe error", 1, true), "/cute errors lists the engine's")
    c.env.CuteDB.errors, c.env.CuteQuestDB.errors = nil, nil
    if c.env.CuteQuestDB.diag then c.env.CuteQuestDB.diag.blocked = nil end
    local db, qdb = c.env.CuteDB, copy(c.env.CuteQuestDB)
    leave(c)
    -- a 0.7 save, its guild sharing on: off once, at the next load; the next login loads the engine inside
    -- PLAYER_ENTERING_WORLD (Quests on): each frame hears it once, the game's delivery or the replay, never both
    qdb.settings.cuteGuildOff, qdb.settings.share.guild = nil, true
    local d = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    d.env.CuteQuestDB = qdb
    local count, realLoad = {}, d.loadAddon
    d.loadAddon = function(a)
      realLoad(a)
      if a.name ~= "Cute_Quest" then return end
      for key in pairs(heardPEW) do
        local m = a.private[key]
        local fr = m and (m.eventFrame or m.frame)
        count[key] = 0
        if fr then fr:HookScript("OnEvent", function(_, event) if event == "PLAYER_ENTERING_WORLD" then count[key] = count[key] + 1 end end) end
      end
    end
    login(d, db); tickAll(6)
    local DQ = d.addons[2].private
    assert(d.addons[2].loaded and DQ.loginDone, "loaded by Cute at the login")
    for key in pairs(heardPEW) do assert(count[key] == 1, "loaded inside PLAYER_ENTERING_WORLD: the engine's " .. key .. " heard it once: " .. tostring(count[key])) end
    local ds = d.env.CuteQuestDB.settings
    assert(ds.share.guild == false and ds.cuteGuildOff == true and ds.share.party == true, "a 0.7 save: guild sharing off once, the party kept")
    leave(d)
    print("cute quest: nothing to the guild (a fresh install, a 0.7 save once); the minimap the engine's only with Map on, the game's ping and zoom otherwise; a travel step opens Quests; the engine's errors and blocked calls on /cute errors; PLAYER_ENTERING_WORLD once; the engine's words name Cute; a hand-in says nothing")
  end)
end

-- 36c: QuestBank loaded beside Cute: Cute_Quest's copy sleeps. Its files return at their second line (no catalog built, no
-- event frame, no /qb of its own), the engine the pages read is QuestBankAPI (QuestBank's own table), the band draws
-- QuestBank's step, the module toggles set none of QuestBank's settings, and QuestBank's step frame is left as it is
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Pim", 3) }, function()
    local pim = newClient(charOf({ "Pim", 3, "Raider", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    local isLoaded = pim.env.C_AddOns.IsAddOnLoaded
    pim.env.C_AddOns.IsAddOnLoaded = function(x) if x == "QuestBank" then return true, true end return isLoaded(x) end
    local settings = { guide = { on = true, frame = true }, arrow = true, mapIcons = true, pins = true, campBar = true, glow = { on = true, style = "sparkle" }, remind = { buffs = true, bag = true, wood = true }, share = { party = true }, djShow = { boss = true, rare = true, trash = false, other = true } }
    local step = { kind = "objective", qid = 7, text = "Kill Kobold Vermin 3/8" }
    pim.env.QuestBankAPI = {
      version = "6.1.0", logReady = true, state = { level = 5, log = {} }, routeNow = { legs = {}, xp = 0, level = 5, t = 0 },
      Settings = function() return settings end, MarkDirty = function() end, Comma = tostring, Short = tostring,
      Model = { Busy = function() return false end }, Data = { CAT = {} }, Quest = { Get = function() return nil end },
      Guide = { Steps = function() return { step } end, Text = function(s) return s.text end, TimeToLevel = function() return "about 9 min to level 6", 9, true end, MemberSteps = function() return {} end },
      StepFrame = { Menu = function() end, Apply = function() end }, Arrow = { Set = function(on) settings.arrow = on end },
      UI = { PlaceGroups = function() return {}, {}, nil, nil, nil end, Candidates = function() return {} end, QuestClick = function() end, QuestTooltip = function() end },
      Target = { Route = function() return { legs = {}, xp = 0, level = 5, t = 0 } end }, Run = { Get = function() return nil end },
      DMap = { Attach = function() end, Refresh = function() end }, Gear = { Attach = function() end, Refresh = function() end, RefreshSoon = function() end },
    }
    login(pim)
    tickAll(5)
    local framesBefore = #pim.frames
    pim.C.Modules.Set("Cute_Quest", true)
    tick(pim, 6)
    local a = pim.addons[2]
    local QB = a.private
    assert(a.loaded and QB.dormant == true and QB.Engine == pim.env.QuestBankAPI, "loaded, dormant, the engine QuestBank's")
    assert(QB.Data == nil and QB.Guide == nil and QB.eventFrame == nil and QB.loginDone == nil, "the copy's files returned at once: no catalog, no guide, no event frame")
    assert(pim.env.SLASH_QUESTBANK1 == nil and pim.env.SlashCmdList.QUESTBANK == nil, "no /qb from the copy")
    -- (the registry's own frame per module, redrawing a page while it is on, is Cute's, not the copy's)
    local registry = {}
    for _, def in pairs(pim.C.Modules.byId) do if def.frame then registry[def.frame] = true end end
    for i = framesBefore + 1, #pim.frames do
      local f = pim.frames[i]
      assert(registry[f] or not (f.__events and f.__events.QUEST_TURNED_IN), "no frame of the copy hears QUEST_TURNED_IN")
    end
    assert(pim.env.CuteQuestDB == nil, "no saved table of the copy's own while it sleeps")
    if not pim.C.Modules.OnKey("guide") then pim.C.Modules.Set("guide", true) end
    pim.C.UI:Open("guide")
    assert(texts(pim):find("Kill Kobold Vermin 3/8", 1, true) and texts(pim):find("about 9 min to level 6", 1, true), "the band draws QuestBank's step:\n" .. texts(pim))
    pim.C.Modules.Set("Cute_Quest", false)
    assert(settings.guide.on == true and settings.arrow == true, "the toggle set none of QuestBank's settings")
    leave(pim)
    print("cute quest: with QuestBank loaded the copy sleeps, the pages read QuestBankAPI, nothing runs twice")
  end)
end

-- 36c (ii): QuestBank 6.0.1 beside Cute, the one shipped before QuestBankAPI: loaded, so the copy sleeps, and no engine
-- for the pages. 0.7.0's first build took the sleeping copy for the engine (nil or QB) and every page but Quests
-- errored; the band said to tick Quests while it was ticked. Now there is no engine (QB.Engine nil, QB.missing the
-- line), every page draws that one line, every section has it, and the band says it where the step would be
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Pim", 3) }, function()
    local pim = newClient(charOf({ "Pim", 3, "Raider", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    local isLoaded, meta = pim.env.C_AddOns.IsAddOnLoaded, pim.env.C_AddOns.GetAddOnMetadata
    pim.env.C_AddOns.IsAddOnLoaded = function(x) if x == "QuestBank" then return true, true end return isLoaded(x) end
    pim.env.C_AddOns.GetAddOnMetadata = function(x, field) if x == "QuestBank" then return field == "Version" and "6.0.1" or nil end return meta(x, field) end
    pim.env.QuestBankAPI = nil
    login(pim)
    tickAll(5)
    for _, key in ipairs({ "Cute_Quest", "Cute_Quest:route", "Cute_Quest:map", "Cute_Quest:journal", "Cute_Quest:gear", "Cute_Quest:camp" }) do pim.C.Modules.Set(key, true) end
    if not pim.C.Modules.OnKey("guide") then pim.C.Modules.Set("guide", true) end
    tick(pim, 6)
    local QB = pim.addons[2].private
    local LINE = "QuestBank 6.1.0 or newer is needed; yours is 6.0.1."
    assert(QB.dormant == true and QB.Engine == nil and QB.missing == LINE, "no engine, the line: " .. tostring(QB.missing))
    assert(pim.env.Cute.QuestBand and pim.env.Cute.QuestBand.On() == false and pim.env.Cute.QuestBand.Why() == LINE, "the band registered, off, with the line")
    local function errors() return #((pim.env.CuteDB and pim.env.CuteDB.errors) or {}) + #((pim.env.CuteQuestDB and pim.env.CuteQuestDB.errors) or {}) end
    local n0 = errors()
    pim.C.UI:Open("guide")
    local t = texts(pim)
    assert(t:find(LINE, 1, true) and not t:find("Tick Quests", 1, true), "the Guide's band says what is needed, not to tick Quests:\n" .. t)
    for _, page in ipairs({ "quests", "route", "journal", "gear" }) do
      pim.C.UI:Open(page)
      local tp = texts(pim)
      assert(tp:find(LINE, 1, true), page .. " page: the one line:\n" .. tp)
      check(pim.C.UI.frame, "QuestBank 6.0.1 beside Cute: " .. page)
    end
    for _, section in ipairs({ "quests", "route", "map", "gear", "camp" }) do
      pim.C.UI:Open("settings", section)
      local ts = texts(pim)
      assert(ts:find(LINE, 1, true), section .. " section: the one line:\n" .. ts)
    end
    assert(errors() == n0, "no error recorded: " .. (errors() - n0))
    -- the switches set nothing, off and on
    for _, key in ipairs({ "Cute_Quest:map", "Cute_Quest:camp", "Cute_Quest" }) do pim.C.Modules.Set(key, false) end
    assert(errors() == n0 and pim.env.CuteQuestDB == nil, "unticked: nothing set, no table of the copy's own")
    leave(pim)
    print("cute quest: QuestBank 6.0.1 beside Cute: no engine, every page and section one line saying what is needed, the band too")
  end)
end

-- 36d: memory: what the module keeps after login with every quest page opened (reachable from its private table and its
-- saved variables; LuaJIT's layout), and the garbage the engine's own code makes with nothing changed. The budgets are
-- QuestBank's (its harness, the memory block): 11 MB kept, a re-plan with the window shut under 100 KB, the Guide's
-- Replan under 64 KB. ownBytes charges an allocation to the file of the function that made it: Cute_Quest/ only
if SEEDED then
  local function ownBytes(fn)
    local getinfo, count = debug.getinfo, collectgarbage
    local acc, mine, last, mark = 0, false, 0, 0
    local function hook(ev)
      local now = count("count")
      if mine then acc = acc + (now - last) end
      local info = getinfo(ev == "call" and 2 or 3, "S")
      if info and info.what ~= "C" then mine = info.source:find("Cute_Quest/", 1, true) ~= nil end
      if count("count") - mark > 65536 then collectgarbage("collect"); collectgarbage("stop"); mark = count("count") end
      last = count("count")
    end
    if jit then jit.off(); jit.flush() end
    collectgarbage("collect"); collectgarbage("stop")
    last = count("count"); mark = last
    debug.sethook(hook, "cr")
    fn()
    debug.sethook()
    collectgarbage("restart")
    if jit then jit.on() end
    return acc * 1024
  end
  -- what a client's quest module keeps: everything reachable from the roots (a widget counted as a small table, the
  -- module's own fields on it followed; the upvalues of the module's own functions followed, where its caches live)
  local function pow2(n) local p = 1; while p < n do p = p * 2 end; return p end
  local function kept(c, roots)
    collectgarbage("collect"); collectgarbage("collect") -- (a weak table's dead entries go first)
    local seen = { [c] = true, [c.env] = true, [BASE] = true, [_G] = true, [ALL] = true, [clients] = true, [c.frames] = true, [c.timers] = true }
    seen[c.C] = true
    local total, queue, qi = 0, roots, 1
    local function push(v)
      local tv = type(v)
      if tv == "string" then
        if not seen[v] then seen[v] = true; total = total + 17 + #v end
      elseif (tv == "table" or tv == "function") and not seen[v] then
        queue[#queue + 1] = v
      end
    end
    while qi <= #queue do
      local v = queue[qi]
      queue[qi], qi = false, qi + 1
      if v and not seen[v] then
        seen[v] = true
        if type(v) == "table" then
          if rawget(v, "__kind") and rawget(v, "__scripts") then
            total = total + 150
            for k, x in pairs(v) do if type(k) ~= "string" or not k:find("^__") then push(k); push(x) end end
            for _, s in pairs(rawget(v, "__scripts")) do push(s) end
          else
            local n, h = #v, 0
            for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then h = h + 1 end end
            total = total + 64 + (n > 0 and pow2(n) * 8 or 0) + (h > 0 and pow2(h) * 24 or 0)
            local mt = debug.getmetatable(v)
            if type(mt) == "table" then push(mt) end
            for k, x in pairs(v) do push(k); push(x) end
          end
        else
          local info = debug.getinfo(v, "Su")
          total = total + 40 + 8 * (info.nups or 0)
          if info.source:find("Cute_Quest/", 1, true) then
            for i = 1, info.nups or 0 do local _, x = debug.getupvalue(v, i); push(x) end
          end
        end
      end
    end
    return total / 1024
  end
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = "Officer", class = "PALADIN", level = 20, online = true } end
  isolated({ member("Memo", 1) }, function()
    local mc = newClient(charOf({ "Memo", 1, "Officer", "PALADIN", 20 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    login(mc)
    tickAll(5)
    for _, key in ipairs({ "Cute_Quest", "Cute_Quest:route", "Cute_Quest:map", "Cute_Quest:journal", "Cute_Quest:gear", "Cute_Quest:camp" }) do mc.C.Modules.Set(key, true) end
    if not mc.C.Modules.OnKey("guide") then mc.C.Modules.Set("guide", true) end
    tick(mc, 6)
    local QB = mc.addons[2].private
    QB.Model.Finish()
    for _, page in ipairs({ "guide", "quests", "route", "journal", "gear" }) do mc.C.UI:Open(page) end
    mc.C.UI.frame:Hide()
    local KEEP_BUDGET = 11 * 1024
    local keptKB = kept(mc, { QB, mc.env.QuestBankDB })
    print(string.format("cute quest memory: kept after login and every page %.0f KB (budget %d KB)", keptKB, KEEP_BUDGET))
    assert(keptKB < KEEP_BUDGET, string.format("the quest module keeps %.0f KB, over its budget of %d KB", keptKB, KEEP_BUDGET))
    QB:Changed()
    local refresh = ownBytes(function() QB:Changed(); QB:Changed() end) / 2
    print(string.format("cute quest: a refresh with the window shut %.0f KB of garbage", refresh / 1024))
    assert(refresh < 100 * 1024, string.format("a refresh with nothing changed made %.0f KB (at most 100)", refresh / 1024))
    QB.Guide.Replan()
    local replan = ownBytes(function() QB.Guide.Replan() end)
    print(string.format("cute quest: the Guide's Replan with nothing changed %.0f KB", replan / 1024))
    assert(replan < 64 * 1024, string.format("the Guide's Replan made %.0f KB (at most 64)", replan / 1024))
    leave(mc)
  end)
end

-- 37: Only-you is routing, not hiding (0.6.0). Three officers (Ofa the guild master, Ofb, Ofc) and two members (Mia,
-- with 300 statistics, and Mo) log in together; the officers keep Gold, the gear gaps and the Kills statistics to
-- themselves. Every message each client receives is read off the bus: a member's client never gets another member's
-- Only-you value, on GUILD or whispered; the officers get Mia's, whispered to each of them and to no one else. Each
-- client stays under twenty messages in its first minute with three officers online. Ofl, an officer who logs in an
-- hour later, gets them in the answer to his ask, the Kills statistics with the statistics pass. Ofa opens Gold to
-- everyone: Mia's goes on GUILD and Mo has it; Ofa closes it again: Mo's client deletes it as the policy arrives, and
-- Mia's next gold goes to the officers alone. Mo's saved variables from 0.5.0, holding Mia's gold and gear gaps, are
-- purged at his next login once the roster says he is no officer. A whisper from outside the guild, one carrying a
-- member's GUID among them, is ignored
-- the leak judge of the privacy scenarios. The ids a message carries, each as the id the policy routes it by: the
-- values of a 1D or 1F, the labels of a 1L (a boss, an instance, a faction, a boss's loot), the bosses of a 1K's claims
-- and the group each names (Grouped with)
local function wireIds(msg)
  local out = {}
  local body = msg:match("^1D|[^|]*|(.*)$") or msg:match("^1F|%d+|%d+|[^|]*|(.*)$")
  if body then for id in body:gmatch("([%l%d_]+)=") do out[#out + 1] = id end return out end
  body = msg:match("^1L|(.*)$")
  if body then for key in body:gmatch("([^=;]+)=") do local id = key:match("^([efil]%d+)"); if id then out[#out + 1] = id end end return out end
  body = msg:match("^1K|(.*)$")
  if body then for enc in body:gmatch("(%d+)@") do out[#out + 1] = "e" .. enc end; out[#out + 1] = "group" end
  return out
end
-- where the officers' policy (theirs as they set it: policy, a CuteDB.policy) sends an id, the id as the sender's
-- client knows it (its statistics' categories, its instances' kinds), never by the sender's own policy
local function officersRoute(policy, sender, id)
  local db = sender.env.CuteDB
  local p = db.policy
  db.policy = policy
  local r = sender.C.Policy:Route(id)
  db.policy = p
  return r
end
-- JUDGE for a scenario: each message judged as it is delivered by the policy the officers' saved variables hold then
local function judgeBy(officerDb)
  return function(from, msg)
    if not (from and from.env and from.env.CuteDB) then return nil end
    local out
    for _, id in ipairs(wireIds(msg)) do if officersRoute(officerDb.policy, from, id) == "self" then out = out or {}; out[#out + 1] = id end end
    return out
  end
end
-- what a member's client received that it should not have: a message from another client carrying a value, a label or
-- a claim the officers' policy kept to the officers when it was delivered, and any whisper. from: the client's got
-- list from that index on
local function leakedTo(c, from)
  local out = {}
  for i = from or 1, #(c.got or {}) do
    local m = c.got[i]
    if m.from ~= c.sender then
      for _, id in ipairs(m.closed or {}) do out[#out + 1] = m.from .. " " .. id end
      if m.channel == "WHISPER" then out[#out + 1] = "a whisper from " .. m.from end
    end
  end
  return out
end

collectgarbage() -- (the scenarios before leave much to collect; the gate's peak stays where it was)
do
  local function member(name, rank, level) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = level or 30, online = true } end
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Ofc", 1), member("Mia", 3), member("Mo", 3), member("Ofl", 1) }, function()
    local policy = { vis = { gc130 = "self" }, by = "Ofa-Forever", rank = 0, at = EPOCH, threshold = 1 }
    local function db(mine)
      local p = {}
      for k, v in pairs(policy) do p[k] = v end
      p.vis = { gc130 = "self" }
      if mine then p.mine, p.by = true, "Ofa-Forever" end
      return { policy = p }
    end
    local function char(name, rank, extra) return charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra) end
    local ofa, ofb, ofc = newClient(char("Ofa", 0, { withStats = true })), newClient(char("Ofb", 1)), newClient(char("Ofc", 1))
    local mia = newClient(char("Mia", 3, { withStats = true, manyStats = 300, money = 777777 }))
    local mo = newClient(char("Mo", 3, { withStats = true, money = 4242 }))
    local start = mia.clock
    for _, c in ipairs({ ofa, mia, mo }) do c.got = {} end
    local ofaDb = db(true)
    -- (every message judged as it is delivered by the officers' policy as it stands then: Ofa's)
    JUDGE = judgeBy(ofaDb)
    login(ofa, ofaDb); login(ofb, db()); login(ofc, db()); login(mia, db()); login(mo, db())
    tickAll(60)
    -- the login's first minute, three officers online: under twenty messages each
    local firstMinute = {}
    for _, c in ipairs({ ofa, ofb, ofc, mia, mo }) do
      local n = 0
      for _, m in ipairs(c.sent) do if m.at <= start + 60 then n = n + 1 end end
      assert(n < 20, c.o.name .. ": under twenty messages in the first minute with three officers online: " .. n)
      firstMinute[#firstMinute + 1] = c.o.name .. " " .. n
    end
    tickAll(90)
    -- every message a client received, read off the bus: none carries a value, label or claim the officers' policy kept
    -- to them when it was delivered
    local leaked = leakedTo
    for _, c in ipairs({ mia, mo }) do
      local l = leaked(c)
      assert(#l == 0, c.o.name .. " received another member's Only-you values: " .. table.concat(l, ", "))
      for key, e in pairs(c.env.CuteDB.roster) do
        for id in pairs(e.stats) do assert(c.C.Policy:Route(id) == "all", c.o.name .. " holds " .. key .. "'s " .. id) end
      end
    end
    local mr = mo.env.CuteDB.roster["Mia-Forever"]
    assert(mr and mr.stats.level == 30 and mr.stats.g2007 == 17 and mr.stats.gold == nil and mr.stats.empty_slots == nil and mr.stats.g2001 == nil,
      "Mo has Mia's open values (her level, her Deaths statistics), none of her gold, gear gaps or Kills")
    -- the officers have hers, whispered to them and to nobody else
    for _, o in ipairs({ ofa, ofb, ofc }) do
      local r = o.env.CuteDB.roster["Mia-Forever"]
      assert(r and r.stats.gold == 777777 and type(r.stats.empty_slots) == "table" and type(r.stats.unenchanted) == "table" and r.stats.g2001 == 1234,
        o.o.name .. " has Mia's gold, gear gaps and Kills: " .. tostring(r and r.stats.gold))
    end
    local whispers, toOfficers = 0, {}
    for _, m in ipairs(mia.sent) do
      if m.channel == "WHISPER" then
        whispers = whispers + 1
        toOfficers[m.target] = true
        assert(m.target == "Ofa-Forever" or m.target == "Ofb-Forever" or m.target == "Ofc-Forever", "Mia whispers to the officers alone: " .. tostring(m.target))
      else
        for _, id in ipairs(wireIds(m.msg)) do assert(officersRoute(ofaDb.policy, mia, id) == "all", "Mia sent " .. id .. " on GUILD") end
      end
    end
    assert(whispers > 0 and toOfficers["Ofa-Forever"] and toOfficers["Ofb-Forever"] and toOfficers["Ofc-Forever"], "a copy to each officer")
    -- Ofl, an officer, logs in an hour later: the answer to his ask carries Mia's Only-you values, the Kills with the
    -- statistics pass
    local ofl = newClient(char("Ofl", 1))
    login(ofl, db())
    tickAll(45)
    local lr = ofl.env.CuteDB.roster["Mia-Forever"]
    assert(lr and lr.stats.gold == 777777 and type(lr.stats.unenchanted) == "table", "the late officer has Mia's gold from the answer to his ask")
    tickAll(60)
    assert(lr.stats.g2001 == 1234, "and her Kills from the statistics pass's answer")
    assert(#leaked(mo) == 0, "Mo still received none")
    -- Ofa opens Gold to everyone: Mia's goes on GUILD, Mo has it
    local before = #mia.sent
    ofa.C.Policy:Set("gold", "all")
    ofa.C.Comm:SendPolicy()
    tickAll(6)
    assert(mo.C.Policy:Route("gold") == "all" and mr.stats.gold == 777777, "opened: Mia's gold reached Mo: " .. tostring(mr.stats.gold))
    local onGuild = false
    for i = before + 1, #mia.sent do if mia.sent[i].channel == "GUILD" and mia.sent[i].msg:find("gold=", 1, true) then onGuild = true end end
    assert(onGuild, "on GUILD")
    -- and closes it: Mo's client deletes it as the policy arrives; Mia's next gold goes to the officers alone
    ofa.C.Policy:Set("gold", "self")
    ofa.C.Comm:SendPolicy()
    tickAll(4)
    assert(mr.stats.gold == nil and mr.at.gold == nil, "closed: Mo's client deleted Mia's gold")
    mia.o.money = 800000
    fire(mia, "PLAYER_MONEY")
    tickAll(6)
    assert(mr.stats.gold == nil and ofb.env.CuteDB.roster["Mia-Forever"].stats.gold == 800000, "Mia's next gold: the officers' alone")
    -- the queue, a minute of changes with four officers online (Ofl too): Mia's gold changes every second, her deaths
    -- every third. 0.6.0's first build queued a guild delta and a whisper per officer each second, dropping only copies
    -- of the same text, and fell 175 messages behind in a minute. Now a delta goes into the one waiting the same way, so
    -- the queue holds five at most (the guild's and one per officer); the guild's deltas go ahead of the whispers, so
    -- none waits behind one, a second at most; each officer ends with her last gold, and Mo with her deaths. Then twenty
    -- seconds of deaths every second too, the guild's deltas taking every turn: a whisper still goes once it has waited
    -- ten seconds (Comm.lua's FAIR), the four one a second after another
    tickAll(10)
    local MC = mia.C.Comm
    assert(#mia.C.Roster:OfficerTargets() == 4 and #MC.out == 0, "four officers online, nothing waiting")
    local real, s0 = mia.env.C_ChatInfo.SendAddonMessage, #mia.sent
    local q -- what a phase measured: the queue's longest, guild messages behind a whisper sent, whispers per officer, the longest waits
    mia.env.C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
      q.most = math.max(q.most, #MC.out)
      for _, e in ipairs(MC.out) do
        if e.target == target then
          local waited = mia.clock - e.at
          if target then q.whisperWait = math.max(q.whisperWait, waited) else q.guildWait = math.max(q.guildWait, waited) end
          break
        end
      end
      if channel == "WHISPER" then
        q.toEach[target] = (q.toEach[target] or 0) + 1
        for _, e in ipairs(MC.out) do if not e.target then q.behind = q.behind + 1 end end
      end
      return real(prefix, msg, channel, target)
    end
    local function phase(seconds, every)
      q = { most = 0, behind = 0, toEach = {}, guildWait = 0, whisperWait = 0 }
      for s = 1, seconds do
        mia.o.money = mia.o.money + 7
        fire(mia, "PLAYER_MONEY")
        if s % every == 0 then fire(mia, "PLAYER_DEAD") end
        tickAll(1)
        q.most = math.max(q.most, #MC.out)
      end
      tickAll(15)
      return q
    end
    mia.o.money = 800000
    local minute = phase(60, 3)
    assert(minute.most <= 5 and minute.behind == 0 and minute.guildWait <= 1.05,
      string.format("the queue held %d at most, %d guild messages waited behind a whisper, one guild message %.2f s", minute.most, minute.behind, minute.guildWait))
    for _, o in ipairs({ ofa, ofb, ofc, ofl }) do assert(o.env.CuteDB.roster["Mia-Forever"].stats.gold == 800420, o.o.name .. " has Mia's last gold") end
    assert(mr.stats.deaths == mia.C.Sample:Value("deaths") and mr.stats.gold == nil, "Mo has her deaths, none of her gold")
    local guildDeltas = 0
    for i = s0 + 1, #mia.sent do if mia.sent[i].channel == "GUILD" and mia.sent[i].msg:find("deaths=", 1, true) then guildDeltas = guildDeltas + 1 end end
    local sent1 = #mia.sent - s0
    local busy = phase(20, 1)
    mia.env.C_ChatInfo.SendAddonMessage = real
    for _, t in ipairs(mia.C.Roster:OfficerTargets()) do assert((busy.toEach[t] or 0) >= 1, "the guild's deltas every second: " .. t .. " still whispered") end
    assert(busy.most <= 5 and busy.whisperWait <= 14.05, string.format("a whisper waited %.2f s at most, the queue %d", busy.whisperWait, busy.most))
    for _, o in ipairs({ ofa, ofb, ofc, ofl }) do assert(o.env.CuteDB.roster["Mia-Forever"].stats.gold == 800560, o.o.name .. " has Mia's last gold again") end
    local queueNote = string.format("a minute of gold every second and deaths every third with four officers online: %d messages, the queue at most %d, %d guild deltas none behind a whisper (the longest wait %.2f s), %d whispers to each officer; with the guild's deltas every second a whisper waited %.0f s at most",
      sent1, minute.most, guildDeltas, minute.guildWait, minute.toEach["Ofa-Forever"] or 0, busy.whisperWait)
    -- the member's view: a dash where the officers keep a value, the header says who sees it
    mo.env.CuteDB.settings.columns.officers = nil
    mo.env.CuteDB.settings.columns.prog = { ready = true, unenchanted = true, empty_slots = true }
    mo.C.UI:Open("prog")
    assert(cellOf(rowOf(mo, "Mia"), "unenchanted").label:GetText() == "-", "Mo sees a dash for Mia's Missing enchants")
    check(mo.C.UI.frame, "member prog, Only-you values never received")
    -- 0.5.0's saved variables: Mo's client held Mia's gold and gear gaps; his next login purges them once the roster
    -- says he is no officer and Guild Info has been read (a guild with no line: the policy he holds)
    local moDb = mo.env.CuteDB
    moDb.roster["Mia-Forever"].stats.gold, moDb.roster["Mia-Forever"].stats.empty_slots, moDb.roster["Mia-Forever"].stats.g2001 = 123, { [2] = true }, 99
    leave(mo)
    local mo2 = newClient(char("Mo", 3, { withStats = true }))
    mo2.env.CuteDB = moDb
    fire(mo2, "ADDON_LOADED", "Cute")
    assert(moDb.roster["Mia-Forever"].stats.gold == 123, "before the roster: kept (nobody knows yet whether Mo is an officer)")
    fire(mo2, "PLAYER_ENTERING_WORLD", true, false)
    -- (a guild with no line: taken as such from a read eleven seconds after the ask ten seconds on)
    tickAll(25)
    local st = moDb.roster["Mia-Forever"].stats
    assert(st.gold == nil and st.empty_slots == nil and st.g2001 == nil and st.level == 30 and st.g2007 == 17, "purged at login: none of Mia's Only-you values, the rest kept")
    -- an officer's saved file keeps them (what remains true, and the page says so)
    assert(ofc.env.CuteDB.roster["Mia-Forever"].stats.gold == 800560, "an officer's client holds them")
    -- a whisper from outside the guild is ignored, one carrying a guild member's GUID too
    local eve = newClient(charOf({ "Eve", 3, "Raider", "ROGUE", 30 }, { inGuild = false }))
    eve.inGuild = false
    login(eve)
    -- (an edited copy's queue, sending whatever Guild Info says or does not)
    eve.C.Policy.line = false
    eve.C.Comm.Queue({ msg = "1D|4|gold=zz", target = "Ofa-Forever" })
    eve.C.Comm.Queue({ msg = "1F|1|1|4|guid=" .. mia.o.guid .. ";gold=1", target = "Ofa-Forever" })
    tickAll(4)
    local fromEve = 0
    for _, m in ipairs(ofa.got) do if m.from == eve.sender then fromEve = fromEve + 1 end end
    assert(fromEve == 2 and not ofa.env.CuteDB.roster["Eve-Forever"] and ofa.env.CuteDB.roster["Mia-Forever"].stats.gold == 800560, "two whispers from outside the guild reached Ofa and changed nothing")
    for _, c in ipairs({ ofa, ofb, ofc, mia, mo2, ofl, eve }) do leave(c) end
    JUDGE = nil
    print("privacy: a member's client never receives another's Only-you values, on GUILD or whispered (read off the bus); the officers get them, whispered to each and to no one else; first minute with three officers online " .. table.concat(firstMinute, ", ") .. " messages; a late officer gets them answering his ask; opening a stat sends it on GUILD, closing it deletes members' copies; " .. queueNote .. "; 0.5.0's saved records purged at login; a whisper from outside the guild ignored")
  end)
end

-- 38: a modified addon cannot steer the guild (0.6.0). An officer (Tru) and four members, one of them running a copy
-- of Cute edited to send anything (Mod: here his client's queue carries forged messages, as such a copy would send
-- them). What cannot be is dropped and Mod marked suspect with the reason, for the officers alone: an XP percentage
-- over 100, a count of deaths going down, a level the guild roster contradicts (the roster's level shows). One voice
-- teaches nothing: Mod's claimed neck enchant asks nobody for one, his dungeon of his own making with its boss and its
-- range joins nothing, and his kill naming Ann, who never names him back, is no corroborated kill; Ann and Ben's
-- kill in one group is. Tru marks Mod untrusted on the Officers page (a click on his row, Mark untrusted, Broadcast):
-- Ann's client leaves him out of what it learns (the neck Cat and Mod enchanted is Cat's alone again) and of the
-- rankings (the Hall of Shame's Deaths), and the officer's rows say so; Trust again undoes it
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 30, online = true } end
  isolated({ member("Tru", 1), member("Ann", 3), member("Ben", 3), member("Cat", 3), member("Mod", 3) }, function()
    local neck = function() return { [1] = "item:3001:0", [2] = "item:3002:0", [5] = "item:3005:0" } end
    local function char(name, rank) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "WARRIOR", 30 }, { items = neck() })) end
    local tru, ann, ben, cat, mod = char("Tru", 1), char("Ann", 3), char("Ben", 3), char("Cat", 3), char("Mod", 3)
    for _, c in ipairs({ tru, ann, ben, cat, mod }) do login(c) end
    tickAll(45)
    local function forge(msg) mod.C.Comm.Queue({ msg = msg }); tickAll(3) end
    local tm = tru.env.CuteDB.roster["Mod-Forever"]
    local xp0 = tm.stats.xp
    -- out of bounds: an XP percentage of 1295
    forge("1D|4|xp=zz")
    assert(tm.stats.xp == xp0 and tm.suspect and tm.suspect.why == "XP into level 1295, out of bounds (0 to 100)", "dropped, Mod suspect: " .. tostring(tm.suspect and tm.suspect.why))
    -- a lifetime count going down
    forge("1D|4|deaths=5")
    forge("1D|4|deaths=1")
    assert(tm.stats.deaths == 5 and tm.suspect.why == "Deaths went down from 5 to 1" and tm.suspect.n == 2, "a count never goes down: " .. tostring(tm.suspect.why))
    -- a level the guild roster contradicts: held while the roster may still catch up (half a minute), then dropped,
    -- marked, the roster's shown
    forge("1D|4|level=1o")
    tickAll(32)
    assert(tm.stats.level == 30 and tm.suspect.why == "level 60 where the guild roster says 30", "the roster's level wins: " .. tostring(tm.suspect.why))
    tru.env.CuteDB.settings.columns.race = nil
    tru.C.UI:Open("race")
    local r = rowOf(tru, "Mod")
    assert(r and r.name:GetText() == "Mod  (suspect)" and cellOf(r, "level").label:GetText() == "30", "the officer's row: marked, the roster's level: " .. tostring(r and r.name:GetText()))
    local l0 = #lines
    hover(r)
    assert(table.concat(lines, "\n", l0 + 1):find("Suspect: level 60 where the guild roster says 30", 1, true), "its tooltip says why")
    ann.C.UI:Open("race")
    local ar = rowOf(ann, "Mod")
    assert(ar and ar.name:GetText() == "Mod" and ann.env.CuteDB.roster["Mod-Forever"].stats.level == 30, "the member's row: no mark (the officers' alone), the forged level dropped there too")
    l0 = #lines
    hover(ar)
    assert(not table.concat(lines, "\n", l0 + 1):find("Suspect", 1, true), "and no reason in the member's tooltip")
    -- one voice teaches nothing: Mod's claimed neck enchant
    forge("1D|4|enchanted=1;ench_kinds=2:15.0:2564")
    ann.C.Sample:Read("unenchanted")
    assert(not ann.C.Sample:Value("unenchanted")[2] and not ann.C.Stats.EnchantLearned(2), "Mod's neck alone asks Ann for none")
    -- his own dungeon, its boss and his kill at 30, his claim naming Ann, who never names him back
    local sfx = ann.o.guid:match("([^%-]+)$")
    forge("1L|i7777:p=Fake Keep;e8888:7777=Fake Boss")
    forge("1D|4|i7777=1;e8888=1;k8888=u")
    forge("1K|8888@" .. mod.C.Comm.b36(EPOCH + mod.clock) .. ":" .. sfx)
    tickAll(4)
    local m = tru.C.Rules.Model()
    assert(not m.dungeons[7777] and not m.bosses[8888] and not tru.C.Rules.Corroborated(8888, mod.o.guid), "Mod's dungeon, boss and range join nothing, his kill uncorroborated")
    -- Ann and Ben kill Rhahk'Zor in one group: each names the other, the kill corroborated and taught
    for _, pair in ipairs({ { ann, ben }, { ben, ann } }) do
      local c = pair[1]
      c.o.party = { pair[2].o.name }
      c.o.instance, c.o.instanceID, c.o.instName = "party", 36, "The Deadmines"
      fire(c, "PLAYER_ENTERING_WORLD", false, false)
    end
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {}); fire(ben, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    -- Cat kills it alone: no group mate names her
    cat.o.instance, cat.o.instanceID, cat.o.instName = "party", 36, "The Deadmines"
    fire(cat, "PLAYER_ENTERING_WORLD", false, false)
    fire(cat, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    -- (the model built again at most once in thirty seconds from what members send, Rules.lua R:Dirty)
    tickAll(35)
    local R = tru.C.Rules
    assert(R.Corroborated(1230, ann.o.guid) and R.Corroborated(1230, ben.o.guid) and not R.Corroborated(1230, cat.o.guid), "Ann's and Ben's kill corroborated, Cat's alone not")
    assert(R.Model().bosses[1230] and R.Model().bosses[1230].n == 2, "the boss seen by the two who killed it together: " .. tostring(R.Model().bosses[1230] and R.Model().bosses[1230].n))
    -- Cat's neck enchanted beside Mod's claim: two voices, Ann's neck asked for
    cat.o.items[2] = "item:3002:2564"
    fire(cat, "UNIT_INVENTORY_CHANGED", "player")
    tickAll(6)
    ann.C.Sample:Read("unenchanted")
    assert(ann.C.Sample:Value("unenchanted")[2], "Cat's and Mod's necks: two voices, Ann's neck asked for")
    -- Tru marks Mod untrusted on the Officers page and broadcasts
    tru.C.UI:Open("officers")
    local function bandButton(c, label) for _, b in ipairs(c.C.UI.bandButtons.items) do if b:IsShown() and b.label:GetText() == label then return b end end end
    local mark = bandButton(tru, "Mark untrusted")
    assert(mark and mark.__disabled, "Mark untrusted waits for a member to be picked")
    assert(texts(tru):find("Suspect: Mod. Click a row for why.", 1, true), "the band names the suspect:\n" .. texts(tru))
    check(tru.C.UI.frame, "officer officers, a suspect")
    press(rowOf(tru, "Mod"))
    assert(texts(tru):find("Mod: suspect: level 60 where the guild roster says 30.", 1, true), "picked: his state and why")
    mark = bandButton(tru, "Mark untrusted")
    assert(mark and not mark.__disabled, "now it can")
    press(mark)
    assert(tru.C.Policy:Untrusted(mod.o.guid) and bandButton(tru, "Trust again"), "marked, the button says Trust again")
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      tru.C.UI.frame:SetSize(size[1], size[2])
      tru.C.UI:Open("officers")
      check(tru.C.UI.frame, string.format("officer officers, a member untrusted, %dx%d", size[1], size[2]))
    end
    tru.C.UI.frame:SetSize(1040, 640)
    assert(rowOf(tru, "Mod").name:GetText() == "Mod  (untrusted)", "the officer's row says so")
    press(bandButton(tru, "Broadcast policy now"))
    tickAll(4)
    assert(ann.C.Policy:Untrusted(mod.o.guid) and not ann.C.Stats.EnchantLearned(2), "Ann's client applied it: the neck is Cat's alone again, unlearned")
    ann.C.Sample:Read("unenchanted")
    assert(not ann.C.Sample:Value("unenchanted")[2], "and her neck is asked for no more")
    -- out of the rankings: Mod's five deaths lead nothing
    ann.C.UI:Open("shame")
    for _, card in ipairs(ann.C.UI.cards.items) do
      if card:IsShown() and card.def.id == "deaths" then for _, e in pairs(card.top) do assert(e.short ~= "Mod", "Mod is in no ranking") end end
    end
    -- Trust again undoes it
    tru.C.UI:Open("officers")
    press(bandButton(tru, "Trust again"))
    assert(not tru.C.Policy:Untrusted(mod.o.guid), "trusted again")
    tru.C.Comm:SendPolicy()
    tickAll(4)
    assert(not ann.C.Policy:Untrusted(mod.o.guid), "Ann's client trusts him again")
    -- (the officers' word that adds the neck back goes a minute after the last at most: one that takes back goes at once)
    tickAll(60)
    assert(ann.C.Stats.EnchantLearned(2), "Ann's client counts his word again")
    for _, c in ipairs({ tru, ann, ben, cat, mod }) do leave(c) end
    print("trust: an XP of 1295 %, deaths going down and a level the roster contradicts dropped and Mod marked suspect with the reason, for the officers alone; one voice teaches nothing (a neck enchant, a dungeon, its boss and range); a kill counts where a group mate names it back; an untrusted member is left out of learning and the rankings, marked on the officers' rows, trusted again at a click")
  end)
end

-- 39: the Guide that guides (0.6.0): what to do next, and with whom. Vee, a member at 20, an Alliance priest; Gil, an
-- officer at 30; Bo at 19 runs Cute; Lu, Ra, Mo, Nox and Pi are online between 18 and 23 without it, Zed at 20 is
-- offline, Kay at 24 is past the Deadmines. With the seed: the band's next best thing is the rules' pick, "Run The
-- Deadmines" with its reason in the tooltip, and its card is marked; the card has its range on a level bar, its word
-- (beta), four pips not killed, its quests as they stand for an Alliance character at 20 (one done, one in the log, one
-- opening at 21, the Horde's left out, one the catalog gave no id) and six mates nearest first: four, then "and 2 more"
-- (a click shows them all), class-coloured, with Invite buttons. Inviting Bo goes to the sender string his Cute speaks
-- under, Lu to the roster's name; never in combat (the buttons greyed, a press inviting nobody), nor where the client
-- says you cannot; Bo in Vee's group says so. Next up has Blackfathom Deeps at 24; Gil's has Krol'dok and The Drowned
-- City, which the research names without an instance id, until he and Bo enter "the Drowned City" (instance 9100):
-- then it is the seed's dungeon under that id, found, its range the seed's, and one member's other instance of that
-- name (Vee's 9200) neither takes it nor joins. Gil's band is the guild's version: most members are 18-23, the
-- Deadmines. Nothing fits, said plainly: at 14, and with every boss killed and every quest done. With no seed the
-- band says no dungeon is known for the level. /cute diag shows the modules on and the trust marks. Every view at both
-- sizes, at the top and scrolled to the end, every row and band line hovered
do
  local function member(name, rank, class, level, online)
    return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = class, level = level, online = online ~= false }
  end
  isolated({ member("Gil", 1, "PALADIN", 30), member("Vee", 3, "PRIEST", 20), member("Bo", 3, "MAGE", 19), member("Lu", 3, "DRUID", 21), member("Ra", 3, "MAGE", 19),
    member("Mo", 3, "SHAMAN", 18), member("Nox", 3, "ROGUE", 22), member("Pi", 3, "WARLOCK", 23), member("Zed", 3, "WARRIOR", 20, false), member("Kay", 3, "HUNTER", 24) }, function()
    local gil = newClient(charOf({ "Gil", 1, "Officer", "PALADIN", 30 }))
    local vee = newClient(charOf({ "Vee", 3, "Raider", "PRIEST", 20 }, { done = { [214] = true }, log = { [166] = 2 } }))
    local bo = newClient(charOf({ "Bo", 3, "Raider", "MAGE", 19 }))
    for _, c in ipairs({ gil, vee, bo }) do login(c); c.C.Modules.Set("guide", true) end
    tickAll(45)
    local function items(c, officer) local list = c.C.Guide.Items(officer); return list end
    local function card(list, name) for i, it in ipairs(list) do if it.kind == "card" and it.name == name then return i, it end end end
    local function under(list, at)
      local out = { mates = {} }
      for i = at + 1, #list do
        local it = list[i]
        if it.kind == "card" or it.kind == "gap" or it.kind == "head" then break end
        if it.kind == "mate" and it.mate then out.mates[#out.mates + 1] = it.name .. " " .. it.val else out[it.kind] = it end
      end
      return out
    end
    local function rowOfMate(c, name) for _, r in ipairs(c.C.UI.lists.guide.items) do if r:IsShown() and r.invite.mate and r.invite.mate.name == name then return r end end end
    local function views(label)
      for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
        for _, c in ipairs({ vee, gil }) do
          c.C.UI:Build()
          c.C.UI.frame:SetSize(size[1], size[2])
          c.C.UI:Open("guide")
          local who = string.format("%s guide, %s, %dx%d", c == gil and "officer" or "member", label, size[1], size[2])
          check(c.C.UI.frame, who)
          for _, l in ipairs(c.C.UI.bandLines.items) do if l:IsShown() then hover(l) end end
          for _, l in ipairs(c.C.UI.lists.guide.items) do if l:IsShown() then hover(l); if l.invite:IsShown() then hover(l.invite) end end end
          local bar = c.C.UI.scroll.bar
          local _, max = bar:GetMinMaxValues()
          bar:SetValue(max)
          check(c.C.UI.frame, who .. ", the end")
          for _, l in ipairs(c.C.UI.lists.guide.items) do if l:IsShown() then hover(l) end end
          c.C.UI.frame:SetSize(1040, 640)
        end
      end
    end
    if SEEDED then
      -- the next best thing, its reason in the tooltip, and its card marked
      local list, plan = vee.C.Guide.Items(false)
      local at, dm = card(list, "The Deadmines")
      assert(dm and dm.val == "18-23" and dm.who == "beta" and dm.pick and plan.next.card and plan.next.card.d.id == 36, "the Deadmines' card, its range, its word, marked the pick")
      assert(plan.next.line == "Run The Deadmines: 6 guild mates online in range, 4 bosses you have not killed, 1 quest", "the next best thing: " .. plan.next.line)
      vee.C.UI:Open("guide")
      local band = guideHead(vee)
      assert(band.name:GetText() == plan.next.line, "the list's head: " .. tostring(band.name:GetText()))
      local why = tipOf(band)
      assert(why:find("guild mates online in range first, then what is left for you there", 1, true) and why:find("The Deadmines | 6 mates, 4 bosses, 1 quest", 1, true), "its reason in the tooltip:\n" .. why)
      -- the card's parts: four pips not killed; the quests for an Alliance priest at 20; six mates, four shown
      local u = under(list, at)
      local pips = {}
      for _, p in ipairs(u.bosses.pips) do pips[#pips + 1] = p.state end
      assert(table.concat(pips, ",") == "left,left,left,left" and u.bosses.who == "4 left", "four pips, none killed: " .. table.concat(pips, ","))
      -- (the one the catalog gave no id is named, never counted: the client cannot say whether it was done)
      assert(u.quests.name == "The Defias Brotherhood, Oh Brother. . ." and u.quests.who == "1 in your log", "the quests: " .. u.quests.name .. " / " .. tostring(u.quests.who))
      local qt = tipText(u.quests.tip)
      assert(qt:find("Red Silk Bandanas (17) | done", 1, true) and qt:find("Underground Assault (20) | from level 21", 1, true) and qt:find("Oh Brother. . . (20) | not known whether done", 1, true)
        and not qt:find("Horde", 1, true), "the quests' tooltip:\n" .. qt)
      assert(table.concat(u.mates, ", ") == "Bo 19, Lu 21, Ra 19, Mo 18" and u.more and u.more.name == "and 2 more online in range", "the mates nearest first, four shown: " .. table.concat(u.mates, ", "))
      assert(tipText(u.more.tip):find("Nox 22", 1, true) and not table.concat(u.mates, ","):find("Zed", 1, true) and not table.concat(u.mates, ","):find("Kay", 1, true), "the rest in its tooltip; Zed offline and Kay past the range left out")
      -- the level bar: the range on the track, green, and Vee's tick; the mates class-coloured
      local cr
      for _, r in ipairs(vee.C.UI.lists.guide.items) do if r:IsShown() and r.name:GetText() == "The Deadmines" then cr = r end end
      assert(cr and cr.track:IsShown() and cr.seg:IsShown() and cr.mark:IsShown() and cr.bar:IsShown(), "the card's level bar and its mark as the pick")
      local br = rowOfMate(vee, "Bo")
      local mc = vee.env.RAID_CLASS_COLORS.MAGE
      assert(br and sameColor(br.name.__color, { mc.r, mc.g, mc.b }), "Bo's name in the mage's colour")
      -- invites: Bo by the sender string his Cute speaks under, Lu by the roster's name; each says so for a minute
      press(br.invite)
      press(rowOfMate(vee, "Lu").invite)
      assert(vee.invites[1] == "Bo-Forever" and vee.invites[2] == "Lu-Forever" and #vee.invites == 2, "the invites: " .. table.concat(vee.invites, ", "))
      tick(vee, 1)
      assert(rowOfMate(vee, "Bo").invite.label:GetText() == "Invited" and rowOfMate(vee, "Bo").invite.__disabled, "Bo's button says invited")
      -- never in combat: the buttons greyed as combat starts, a press inviting nobody; back after it
      vee.combat = true
      fire(vee, "PLAYER_REGEN_DISABLED")
      tick(vee, 1)
      local ra = rowOfMate(vee, "Ra")
      assert(ra.invite.__disabled and tipOf(ra.invite):find("Not in combat", 1, true), "in combat the buttons are greyed")
      press(ra.invite)
      assert(#vee.invites == 2, "a press in combat invites nobody")
      vee.combat = false
      fire(vee, "PLAYER_REGEN_ENABLED")
      tick(vee, 1)
      assert(not rowOfMate(vee, "Ra").invite.__disabled, "after combat they are back")
      -- in a group led by another the client says you cannot invite; Bo in your group says so, no button
      vee.o.cantInvite = true
      vee.C.UI:Draw()
      assert(rowOfMate(vee, "Ra").invite.__disabled and tipOf(rowOfMate(vee, "Ra").invite):find("leader or an assistant", 1, true), "where the client says you cannot invite")
      vee.o.cantInvite = nil
      vee.o.party = { "Bo" }
      fire(vee, "GROUP_ROSTER_UPDATE")
      tick(vee, 1)
      local inGroup
      for _, r in ipairs(vee.C.UI.lists.guide.items) do if r:IsShown() and r.name:GetText() == "Bo" then inGroup = r end end
      assert(inGroup and not inGroup.invite:IsShown() and inGroup.who:GetText() == "in your group", "Bo in your group: no button")
      -- the rest shown at a click, and fewer again
      local moreRow
      for _, r in ipairs(vee.C.UI.lists.guide.items) do if r:IsShown() and r.name:GetText() == "and 2 more online in range" then moreRow = r end end
      press(moreRow)
      assert(rowOfMate(vee, "Pi") and rowOfMate(vee, "Nox"), "a click shows them all")
      views("six mates shown")
      vee.C.Guide.open[36] = nil
      -- next to open (plan.soon, the pick's tooltip names the first): Blackfathom at 24 for Vee; Krol'dok and The Drowned
      -- City (awaited, no instance id) for Gil
      local function nextUp(c, officer) local _, p = c.C.Guide.Items(officer); local out = {}; for _, d in ipairs(p.soon) do out[#out + 1] = d.min .. " " .. d.name .. " " .. c.C.Rules.RangeWords(d) end return table.concat(out, ", ") end
      assert(nextUp(vee, false) == "24 Blackfathom Deeps 24-32", "Vee's next up: " .. nextUp(vee, false))
      assert(nextUp(gil, true) == "32 Krol'dok Stronghold 32-38, 35 The Drowned City 35-40", "Gil's next up, the awaited one by name: " .. nextUp(gil, true))
      local dc = gil.C.Rules.Model().awaited[1]
      assert(dc and dc.awaited and dc.id == nil and dc.min == 35 and #dc.bosses == 0 and gil.C.Guide.Word(dc) == "research", "seeded by name and range, no id, no bosses")
      -- the guild's version, for the officer
      local _, gp = gil.C.Guide.Items(true)
      gil.C.UI:Open("guide")
      assert(gp.guild.line == "Most members are 18-23: The Deadmines" and guideHead(gil).who:GetText() == gp.guild.line, "the officer's head, the guild's line at its right: " .. tostring(gp.guild.line))
      assert(tipOf(guideHead(gil)):find("8 of 10 members are between 18 and 23", 1, true), "its counts in the tooltip")
      -- the awaited dungeon found. Its tooltip says what places it; one member's entry does not (one edited copy's
      -- label and entry would): Gil alone in "the Drowned City", instance 9100, and Vee alone in "Drowned City" (9200)
      -- place nothing; with Bo's entry too, two members' entries place 9100, and Vee's lone 9200 neither takes it nor
      -- joins
      local awaitedTip
      local _, gp0 = gil.C.Guide.Items(true)
      for _, d in ipairs(gp0.soon) do if d.name == "The Drowned City" then awaitedTip = tipText(gil.C.Guide.DungeonTip(d)) end end
      assert(awaitedTip and awaitedTip:find("two members entering it, or a kill there a group mate names back, give it its place", 1, true), "the awaited one's tooltip:\n" .. tostring(awaitedTip))
      local function enter(c, id, name) c.o.instance, c.o.instanceID, c.o.instName = "party", id, name; fire(c, "PLAYER_ENTERING_WORLD", false, false) end
      enter(gil, 9100, "the Drowned City"); enter(vee, 9200, "Drowned City")
      tickAll(12)
      gil.C.Rules:Rebuild()
      assert(#gil.C.Rules.Model().awaited == 1 and not gil.C.Rules.Model().dungeons[9100] and not gil.C.Rules.Model().dungeons[9200], "one member's entry places nothing")
      enter(bo, 9100, "the Drowned City")
      tickAll(12)
      gil.C.Rules:Rebuild()
      local m = gil.C.Rules.Model()
      local found = m.dungeons[9100]
      assert(found and found.seeded and found.found and found.min == 35 and found.range == "seed" and found.seedName == "The Drowned City" and #m.awaited == 0 and not m.dungeons[9200],
        "the seed's dungeon takes the instance most members entered: " .. tostring(found and found.name))
      local changes = {}
      for _, ch in ipairs(gil.C.Rules.Changes()) do changes[#changes + 1] = ch.what end
      assert(table.concat(changes, "\n"):find("Found: the Drowned City", 1, true), "Learned in play says so:\n" .. table.concat(changes, "\n"))
      assert(nextUp(gil, true) == "32 Krol'dok Stronghold 32-38, 35 the Drowned City 35-40", "Next up names it as the game does: " .. nextUp(gil, true))
      views("the seed")
      -- nothing fits, said plainly: at 14 (the Deadmines opens at 18), and at 20 with every boss killed and every quest done
      vee.o.level = 14
      vee.C.Sample:Read("level")
      local _, p14 = vee.C.Guide.Items(false)
      assert(p14.next.line == "No dungeon known for level 14 yet; The Deadmines opens at 18." and not p14.next.card, "at 14: " .. p14.next.line)
      vee.o.level = 20
      vee.C.Sample:Read("level")
      for _, enc in ipairs({ 1230, 1236, 1238, 1234 }) do vee.C.Char().counters["e" .. enc] = 1 end
      vee.o.done = { [214] = true, [166] = true, [2040] = true }
      local _, p20 = vee.C.Guide.Items(false)
      assert(p20.next.line == "Nothing left for you in range at level 20; Blackfathom Deeps opens at 24." and not p20.next.card, "everything done: " .. p20.next.line)
      views("nothing left")
    else
      local _, plan = vee.C.Guide.Items(false)
      assert(plan.next.line == "No dungeon known for level 20 yet." and #plan.cards == 0, "no seed, nothing met: " .. plan.next.line)
      local _, gp = gil.C.Guide.Items(true)
      assert(gp.guild.line == "Most members are 18-23: no dungeon known for those levels yet.", "the officer's: " .. gp.guild.line)
      views("no seed")
    end
    -- /cute diag: the modules on, and the trust marks (the officer's with names)
    local n0 = #gil.chat
    gil.env.SlashCmdList.CUTE("diag")
    local diag = table.concat(gil.chat, "\n", n0 + 1)
    assert(diag:find("diag modules: on Guide", 1, true) and diag:find("diag trust: suspect 0 | untrusted 0", 1, true), "/cute diag:\n" .. diag)
    for _, c in ipairs({ gil, vee, bo }) do leave(c) end
    print(SEEDED and "guide: the next best thing the rules' pick with its reason, its card marked; a card's range on a level bar, its word, pips, quests for your side and level, the mates online in range class-coloured with Invite (by the sender string or the roster's name; never in combat, nor where the client says no; a group mate says so; the rest at a click); Next up as a timeline with the research's dungeon by name until two members' entries place it, one placing nothing; the officers' guild version; nothing fitting said plainly; /cute diag's modules and trust; every view at both sizes"
      or "guide, no seed: no dungeon known said plainly, the officers' version too; every view at both sizes")
  end)
end

-- 40: a member's copy cannot pass for another member (0.6.0). Ofa, the guild master, and three members (Mia, whose gold
-- goes to the officers alone, Ann, Ben) run Cute; Mal runs a copy edited to put any GUID in its messages (his queue carries
-- forged messages, as such a copy would send them). The roster gives every member the officers' GUIDs; who sent a
-- message is the channel's word all the same, and which name a GUID has the roster's. An ask carrying Ofa's GUID gets
-- Mal none of Mia's Only-you values; a full record carrying it neither gets them nor takes Ofa's place as the one Mia
-- whispers to, and Ofa gets Mia's next gold; a policy from Mal after it is a member's and changes nothing; two records
-- of his, under his GUID and Ben's, are one voice for the neck they claim, and Ben's record stays Ben's; his kill
-- claims, one under Ben's GUID naming himself, corroborate nothing. Each forgery marks him suspect for the officers,
-- with the reason, and Ofa's client never takes him for her. A forged record that came before the roster was known is
-- judged once it is: the GUID dropped, the record marked, nothing learned from it
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 30, online = true } end
  isolated({ member("Ofa", 0), member("Mia", 3), member("Ann", 3), member("Ben", 3), member("Mal", 3) }, function()
    local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "WARRIOR", 30 }, extra)) end
    local ofa, mia, ann, ben, mal = char("Ofa", 0), char("Mia", 3, { money = 777777 }), char("Ann", 3), char("Ben", 3), char("Mal", 3)
    for _, c in ipairs({ ofa, mia, ann, ben, mal }) do login(c) end
    tickAll(45)
    local function forge(msg) mal.C.Comm.Queue({ msg = msg }); tickAll(3) end
    -- the whispers a client sent to Mal, from its message `from` on
    local function toMal(c, from) local n = 0; for i = from or 1, #c.sent do if c.sent[i].channel == "WHISPER" and c.sent[i].target == mal.sender then n = n + 1 end end return n end
    local function why(c) local e = c.env.CuteDB.roster["Mal-Forever"]; return e and e.suspect and e.suspect.why end
    assert(ofa.env.CuteDB.roster["Mia-Forever"].stats.gold == 777777 and toMal(mia) == 0, "before: Ofa has Mia's gold, whispered to her alone")
    -- (1) an ask carrying Ofa's GUID: answered as anyone's, and Mal gets none of Mia's Only-you values. (Mal's own ask at
    -- login was answered, and one ask a sender in three minutes starts an answer: this one comes after them)
    tickAll(150)
    local s0 = #mia.sent
    forge("1R|" .. ofa.o.guid)
    tickAll(25)
    assert(#mia.sent > s0 and toMal(mia, s0 + 1) == 0, "an ask with Ofa's GUID: Mia answers and whispers Mal nothing")
    assert(why(ofa) == "sent Ofa's GUID as its own" and ofa.C.Roster.selfSenders["Mal-Forever"] == nil, "Mal marked suspect, and Ofa's client never takes him for her: " .. tostring(why(ofa)))
    -- (2) a full record carrying it: Mia whispers to Ofa still, Ofa's and Mal's records stay their own
    s0 = #mia.sent
    forge("1F|1|1|4|guid=" .. ofa.o.guid .. ";level=u")
    tickAll(5)
    local targets = mia.C.Roster:OfficerTargets()
    assert(toMal(mia, s0 + 1) == 0 and #targets == 1 and targets[1] == "Ofa-Forever", "a record with Ofa's GUID: Mia whispers Mal nothing and Ofa still: " .. table.concat(targets, ", "))
    local mr = mia.env.CuteDB.roster
    assert(mr["Ofa-Forever"] and mr["Ofa-Forever"].stats.guid == ofa.o.guid and mr["Mal-Forever"].stats.guid == mal.o.guid, "Ofa's record stays Ofa's, Mal's keeps his own GUID")
    mia.o.money = 800000
    fire(mia, "PLAYER_MONEY")
    tickAll(6)
    assert(ofa.env.CuteDB.roster["Mia-Forever"].stats.gold == 800000 and toMal(mia) == 0, "Mia's next gold goes to Ofa, never to Mal")
    -- (3) a policy from Mal after it, opening Gold and marking Ofa untrusted: a member's, so nothing changes
    forge(string.format("1P|%d|1|1/1|%s;u=%s", EPOCH + mal.clock + 30, tok("gold", "all"), ofa.o.guid))
    assert(mia.C.Policy:Route("gold") == "self" and not mia.C.Policy:Untrusted(ofa.o.guid) and not ann.C.Policy:Untrusted(ofa.o.guid), "Mal's policy changes nothing")
    s0 = #mia.sent
    mia.o.money = 810000
    fire(mia, "PLAYER_MONEY")
    tickAll(6)
    for i = s0 + 1, #mia.sent do assert(mia.sent[i].channel == "WHISPER" or not mia.sent[i].msg:find("gold=", 1, true), "Mia's gold never on GUILD") end
    assert(ofa.env.CuteDB.roster["Mia-Forever"].stats.gold == 810000, "and on to Ofa")
    -- (4) one copy, two GUIDs: his own and Ben's, the same neck enchant in each, one voice; Ben's record stays Ben's
    forge("1F|1|1|4|guid=" .. mal.o.guid .. ";enchanted=1;ench_kinds=2:15.0:2564")
    forge("1F|1|1|4|guid=" .. ben.o.guid .. ";enchanted=1;ench_kinds=2:15.0:2564")
    -- (the officer's client weighs them: a member's hears no member's enchants with the defaults)
    local neck = ofa.C.Stats.Known().enchant[2]
    assert(neck and neck.kinds["15.0"].n == 1 and not ofa.C.Stats.EnchantLearned(2) and not ann.C.Stats.EnchantLearned(2), "Mal's two records are one voice: the neck not learned")
    local ar = ann.env.CuteDB.roster
    assert(ar["Ben-Forever"] and ar["Ben-Forever"].stats.guid == ben.o.guid and ar["Mal-Forever"].stats.guid == mal.o.guid, "Ben's record stays Ben's on Ann's client, Mal's his own")
    assert(why(ofa) == "sent Ben's GUID as its own", "marked again, with the reason: " .. tostring(why(ofa)))
    -- (5) his kill claims: one naming Ben, then, under Ben's GUID, one naming himself; nobody names him back
    local t = mal.C.Comm.b36(EPOCH + mal.clock)
    forge("1K|1230@" .. t .. ":" .. ben.o.guid:match("([^%-]+)$"))
    forge("1F|1|1|4|guid=" .. ben.o.guid .. ";level=u")
    forge("1K|1230@" .. t .. ":" .. mal.o.guid:match("([^%-]+)$"))
    for _, c in ipairs({ ofa, ann }) do
      assert(not c.C.Rules.Corroborated(1230, mal.o.guid) and not c.C.Rules.Corroborated(1230, ben.o.guid), "Mal's claims corroborate no kill: " .. c.o.name)
    end
    -- the officer's view: his row says suspect, the band names him, the tooltip says why
    ofa.C.UI:Open("officers")
    assert(rowOf(ofa, "Mal").name:GetText() == "Mal  (suspect)" and texts(ofa):find("Suspect: Mal. Click a row for why.", 1, true), "the officer's view names the suspect")
    assert(tipOf(rowOf(ofa, "Mal")):find("Suspect: sent Ben's GUID as its own", 1, true), "and why")
    check(ofa.C.UI.frame, "officer officers, a member who sent others' GUIDs")
    for _, c in ipairs({ ofa, mia, ann, ben }) do assert(toMal(c) == 0, c.o.name .. " whispered Mal nothing") end
    -- (6) before the roster is known: Ben logs in again and Mal's record with Ofa's GUID and the neck lands first. It is
    -- held in memory and makes no record yet; once the roster is known it is judged: the GUID dropped, the record
    -- marked, and nothing learned from it
    leave(ben)
    local ben2 = char("Ben", 3)
    ben2.env.CuteDB = {}
    fire(ben2, "ADDON_LOADED", "Cute")
    assert(not ben2.C.Roster.trusted, "no roster yet")
    ben2.C.Comm:Receive("1F|1|1|4|guid=" .. ofa.o.guid .. ";enchanted=1;ench_kinds=2:15.0:2564", "GUILD", "Mal-Forever")
    assert(ben2.env.CuteDB.roster["Mal-Forever"] == nil, "before the roster: held in memory, no record made from it")
    fire(ben2, "PLAYER_ENTERING_WORLD", true, false)
    tick(ben2, 1)
    local early = ben2.env.CuteDB.roster["Mal-Forever"]
    local k2 = ben2.C.Stats.Known()
    assert(ben2.C.Roster.trusted and early and early.stats.guid == nil and early.suspect and early.suspect.why == "sent Ofa's GUID as its own", "the roster known: judged by it, the GUID dropped, the record marked")
    assert(not (k2.enchant and k2.enchant[2]), "and the neck it claimed taught nothing")
    tickAll(30)
    local t2 = ben2.C.Roster:OfficerTargets()
    assert(#t2 == 1 and t2[1] == "Ofa-Forever" and ben2.env.CuteDB.roster["Ofa-Forever"].stats.guid == ofa.o.guid, "Ben whispers to Ofa alone: " .. table.concat(t2, ", "))
    for _, c in ipairs({ ofa, mia, ann, ben2, mal }) do leave(c) end
    print("forgery: who sent a message is the channel's word and whose GUID the roster's: an ask or a record carrying the officer's GUID gets no Only-you value and takes no officer's place, the officer gets the next one; a policy after it changes nothing; one copy under two GUIDs is one voice and the other member's record stays theirs; claims under another's GUID corroborate nothing; each forgery marked suspect with the reason; one that came before the roster was known judged once it is")
  end)
end

-- 41: the policy lives in Guild Info (0.6.0). A member who was offline when the officers closed a stat holds an older
-- policy, and 0.6.0's first builds routed by it; members passing the officers' policy on to each other then kept
-- finding timing gaps. Now an officer saves the policy to Guild Info, one line at the end of the guild's text, and every
-- client routes by the policy whose fingerprint is the line's. Every message is judged as it is delivered, by the
-- officers' policy as it stands then, never by the sender's. The officers (Ofa) close Deaths and Enchanted slots and
-- keep Gold and the gear gaps, which the older policy opened. Only the guild master may edit Guild Info here.
-- (b) The guild's text is too long for the whole line beside it: nothing is saved (0.6.0's first builds saved the
-- fingerprint alone, and took the policy from anyone whose copy matched it, which a forged copy could), and Settings
-- say how much shorter; shortened, the line carries the policy. Bea logs in with the older one and no officer online:
-- she routes by the line at its first read, nobody passes anything on, nothing the officers closed goes. (c) Mal's forged policies,
-- their fingerprints not the line's, change nothing. (d) Ofb, an officer with the older policy as her own, changes
-- nothing on any client; her own change, unsaved (she may not edit Guild Info, and her Settings say why), routes on her
-- client alone. (e) The guild shortens its text, Ofa closes the zone and saves: the line carries the policy now, the
-- guild's text kept, Cute's line replaced, and the clients online follow within seconds. A value waiting in the queue
-- leaves by the line it finds. (a) Mia logs in with the older one: the line says it all, nothing waits. (f) A guild with
-- no line: two members alone with the older policy use it until an officer logs in (irreducible), then stop. (g) One
-- account in two guilds: each guild's line routes that guild, and an alt's login changes nothing in the other
collectgarbage()
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true } end
  local OLD, NEW = EPOCH, EPOCH + 500
  local function db(at, by, mine)
    local vis = at == NEW and { gold = "self", deaths = "self", enchanted = "self" } or { gold = "all", unenchanted = "all", empty_slots = "all" }
    return { policy = { vis = vis, by = by or "Ofa-Forever", mine = mine or nil, rank = 0, at = at, threshold = 1 } }
  end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function policies(list) local n = 0; for _, c in ipairs(list) do n = n + msgs(c, "1P") end return n end
  local function lines(text) local n = 0; for _ in (text .. "\n"):gmatch("Cute 1 [^\n]*\n") do n = n + 1 end return n end
  local budget41
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Mo", 3), member("Ann", 3), member("Bea", 3), member("Mal", 3) }, function()
    INFO_EDIT = 0
    -- the guild's own text, long enough that only the fingerprint fits beside it
    local TEXT = ("Welcome to <Cute>!\nRaids Tue and Thu at 20:00. Be nice to the healers, bring your own potions. "):rep(6):sub(1, 463)
    INFO[7] = TEXT
    local ofa, mo, ann = char("Ofa", 0), char("Mo", 3), char("Ann", 3)
    local function late(c) c.clock = mo.clock; return c end
    local ofaDb = db(NEW, nil, true)
    JUDGE = judgeBy(ofaDb)
    mo.got = {}
    login(ofa, ofaDb); login(mo, db(NEW)); login(ann, db(NEW))
    tickAll(45)
    assert(ofa.C.Policy:Unsaved() and mo.C.Policy.line == false, "no line yet: Ofa may save one")
    local ok, why = saveLine(ofa)
    assert(not ok and INFO[7] == TEXT and tostring(why):find("^Guild Info is full: its text needs %d+ bytes fewer") and not ofa.C.Policy:SaveState().ok,
      "too long for the whole line: nothing saved, no line with its fingerprint alone: " .. tostring(why))
    TEXT = TEXT:sub(1, 400)
    INFO[7] = TEXT
    ok, why = saveLine(ofa)
    assert(ok and INFO[7]:sub(1, #TEXT + 1) == TEXT .. "\n" and lines(INFO[7]) == 1 and #INFO[7] <= 499 and ofa.C.Policy.line.diff,
      "saved: the guild's text kept, Cute's line after it, the policy in it: " .. tostring(why) .. " " .. INFO[7]:sub(#TEXT + 1))
    tickAll(15)
    for _, c in ipairs({ mo, ann }) do assert(c.C.Policy:Holds(), c.o.name .. " routes by the line's policy, which it held") end
    -- (b) Bea, the older policy, no officer online; Mo and Ann hold the line's (the one whose GUID comes first answers)
    leave(ofa)
    local bea = late(char("Bea", 3, { money = 4242 }))
    local p0, g0 = policies({ mo, ann }), #mo.got
    bea.got = {}
    login(bea, db(OLD))
    assert(bea.C.Policy:Holds() and bea.C.Policy:Vis("gold") == "self" and bea.C.Policy:Vis("deaths") == "self" and bea.C.Policy:Route("enchanted") == "self",
      "Bea routes by the line's policy at its first read")
    tickAll(45)
    assert(#leakedTo(mo, g0 + 1) == 0, "Bea sent nothing the officers closed: " .. table.concat(leakedTo(mo, g0 + 1), ", "))
    assert(policies({ mo, ann }) == p0 and bea.sent[1] and bea.sent[1].msg:sub(1, 2) == "1R", "nobody passed anything on; her ask first: " .. (policies({ mo, ann }) - p0))
    assert(mo.env.CuteDB.roster["Bea-Forever"] and mo.env.CuteDB.roster["Bea-Forever"].stats.level == 30, "then her record")
    local s0 = #bea.sent
    bea.o.money = 5000
    fire(bea, "PLAYER_MONEY")
    fire(bea, "PLAYER_DEAD")
    tickAll(6)
    for i = s0 + 1, #bea.sent do assert(not (bea.sent[i].channel == "GUILD" and (bea.sent[i].msg:find("gold=", 1, true) or bea.sent[i].msg:find("deaths=", 1, true))), "Bea's gold and deaths not on GUILD: " .. bea.sent[i].msg) end
    -- (c) Mal's forged policies: the officer ranks to the guild master alone, Gold and Deaths opened, the zone closed
    local mal = late(char("Mal", 3))
    login(mal, db(OLD))
    tickAll(30)
    local function forge(msg) mal.C.Comm.Queue({ msg = msg, first = true }); tickAll(3) end
    local now = EPOCH + bea.clock
    forge(string.format("1P|%d|0|1/1|%s;%s", now, tok("gold", "all"), tok("deaths", "all")))
    forge(string.format("1P|%d|1|1/1|%s", now + 30, tok("zone", "self")))
    for _, c in ipairs({ bea, mo }) do
      assert(c.C.Policy:Holds() and c.C.Policy:Threshold() == 1 and c.C.Policy:Vis("gold") == "self" and c.C.Policy:Vis("deaths") == "self" and c.C.Policy:Vis("zone") == "all",
        "a forged policy, its fingerprint not the line's, changes nothing on " .. c.o.name)
    end
    -- (d) Ofb, an officer whose own policy is the older one: her answers and her login change nothing; her own change,
    -- unsaved, routes on her client alone, and her Settings say why she cannot save it
    local ofb = late(char("Ofb", 1, { money = 1234 }))
    login(ofb, db(OLD, "Ofb-Forever", true))
    tickAll(30)
    assert(ofb.C.Policy:Holds() and ofb.C.Policy:Vis("gold") == "self" and mo.C.Policy:Holds() and bea.C.Policy:Holds(), "Ofb takes the line's policy; nobody takes hers")
    local m0 = #mo.got
    ofb.C.Policy:Set("gold", "all")
    ofb.C.Comm:PolicySoon()
    tickAll(8)
    assert(ofb.C.Policy:Route("gold") == "all" and ofb.C.Policy:Settled() and ofb.C.Policy:Describe():find("not saved", 1, true), "her change routes on her client: " .. ofb.C.Policy:Describe())
    for _, c in ipairs({ mo, ann, bea }) do assert(c.C.Policy:Route("gold") == "self" and c.C.Policy:Holds(), "and on nobody else's: " .. c.o.name) end
    for _, x in ipairs(leakedTo(mo, m0 + 1)) do assert(x == "Ofb-Forever gold", "only her own gold, by her own choice: " .. x) end
    ofb.C.UI:Open("settings", "vis")
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      ofb.C.UI.frame:SetSize(size[1], size[2])
      ofb.C.UI:Open("settings", "vis")
      assert(texts(ofb):find("Saving needs a rank allowed to edit Guild Info.", 1, true), "her Settings say who may save it")
      check(ofb.C.UI.frame, "officer settings, a change she may not save, " .. size[1])
    end
    local saveBtn
    for _, b in ipairs(ofb.C.UI.bandButtons.items) do if b:IsShown() and b.label and b.label:GetText() == "Save to Guild Info" then saveBtn = b end end
    assert(saveBtn and saveBtn.__disabled, "and her Save to Guild Info is greyed")
    ofb.C.UI.frame:SetSize(1040, 640)
    ofb.C.UI.frame:Hide()
    leave(ofb)
    -- (e) the guild shortens its text in the game's own editor; Ofa closes the zone and saves from her Settings: the line
    -- carries the policy now, the guild's text kept and Cute's line replaced; the clients online follow
    local ofa2 = late(char("Ofa", 0))
    INFO[7] = "Welcome to <Cute>!\n" .. INFO[7]:match("(Cute 1 [^\n]*)$")
    login(ofa2, ofaDb)
    tickAll(30)
    assert(ofa2.C.Policy:Holds() and not ofa2.C.Policy:Unsaved(), "Ofa holds the line's policy: nothing to save")
    ofa2.C.Policy:Set("zone", "self")
    ofa2.C.UI:Open("settings", "vis")
    assert(texts(ofa2):find("Unsaved. Cute's line: ", 1, true), "her Settings show the line's length")
    for _, b in ipairs(ofa2.C.UI.bandButtons.items) do if b:IsShown() and b.label and b.label:GetText() == "Save to Guild Info" then saveBtn = b end end
    assert(not saveBtn.__disabled and tipOf(saveBtn):find("Cute 1 ", 1, true), "the button, its tooltip the line")
    check(ofa2.C.UI.frame, "officer settings, a change to save")
    press(saveBtn)
    ofa2.C.UI.frame:Hide()
    local info = INFO[7]
    assert(info:match("^Welcome to <Cute>!\nCute 1 %w+ 1 %x+ [%+%-]") and lines(info) == 1 and ofa2.C.Policy.line.diff, "the guild's text kept, one line, the policy in it: " .. info)
    tickAll(5)
    for _, c in ipairs({ mo, ann, bea, mal }) do assert(c.C.Policy:Holds() and c.C.Policy:Route("zone") == "self", c.o.name .. " follows the new line within seconds") end
    -- a guild's text that leaves no room for the line: nothing saved, and Settings say how much shorter
    local keep = INFO[7]
    INFO[7] = ("x"):rep(480) .. "\n" .. keep:match("(Cute 1 [^\n]*)$")
    ofa2.C.Policy:Set("level", "self")
    local full = ofa2.C.Policy:SaveState()
    local need = 480 + 1 + #full.line - 499
    assert(not full.ok and full.why:find("Guild Info is full: its text needs " .. need .. " bytes fewer", 1, true) and not saveLine(ofa2) and INFO[7]:sub(1, 480) == ("x"):rep(480),
      "Guild Info full: " .. tostring(full.why))
    ofa2.C.Policy:Set("level", "all")
    INFO[7] = keep
    assert(not ofa2.C.Policy:Unsaved(), "set back as it was: nothing to save")
    -- a save the game did not keep: the next read says so, in chat, and the line Guild Info holds stands
    ofa2.infoDrop = true
    ofa2.C.Policy:Set("level", "self")
    assert(saveLine(ofa2) and INFO[7] == keep, "the call taken, nothing kept")
    -- (a read of the line from before is the game's copy until the ask once more, twelve seconds after the first, has
    -- been answered)
    tickAll(25)
    local told = false
    for _, l in ipairs(chatLines(ofa2)) do if l:find("Guild Info does not hold the policy you saved", 1, true) then told = true end end
    assert(told and ofa2.C.Policy:Unsaved() and ofa2.C.Policy:EditPending() and ofa2.C.Policy:Vis("level") == "self" and ofa2.C.Policy.line.fp == yezin.C.Policy.ParseLine(keep).fp
      and mo.C.Policy:Holds() and mo.C.Policy:Route("level") == "all", "Ofa is told, her change back and not saved, the line Guild Info holds read (scenario 52(d))")
    ofa2.C.Policy:Set("level", "all")
    assert(not ofa2.C.Policy:Unsaved() and ofa2.C.Policy:Holds(), "set back as the line says: nothing to save")
    ofa2.infoDrop = nil
    -- where a value goes is decided as it leaves: Ofa opens Gold and saves, Bea's gold changes and its delta waits behind
    -- the client's throttle, Ofa closes Gold and saves meanwhile; the delta leaves without it, the gold to Ofa alone
    ofa2.C.Policy:Set("gold", "all")
    assert(saveLine(ofa2))
    -- (the game answers a roster request every ten seconds at most: a client reads Guild Info again within that)
    tickAll(12)
    local br = mo.env.CuteDB.roster["Bea-Forever"]
    assert(br.stats.gold == 5000, "opened: Bea's gold on GUILD: " .. tostring(br.stats.gold))
    local g1 = #mo.got
    bea.o.money = 6000
    bea.throttle = 2
    fire(bea, "PLAYER_MONEY")
    tick(bea, 2.2)
    assert(bea.C.Comm.queued.gold == bea.C.Comm.b36(6000), "the gold queued for GUILD, waiting behind the throttle")
    ofa2.C.Policy:Set("gold", "self")
    assert(saveLine(ofa2))
    tickAll(14)
    local l = leakedTo(mo, g1 + 1)
    assert(#l == 0 and br.stats.gold == nil and ofa2.env.CuteDB.roster["Bea-Forever"].stats.gold == 6000, "the waiting delta left without the gold, which went to Ofa: " .. table.concat(l, ", "))
    -- (a) Mia, the older policy: the line says it all, nothing waits
    local mia = late(char("Mia", 3, { money = 777777 }))
    local start, g2 = mia.clock, #mo.got
    login(mia, db(OLD))
    assert(mia.C.Policy:Holds() and mia.C.Policy:Vis("gold") == "self" and mia.C.Policy:Route("zone") == "self", "at the roster's first read Mia routes by the line")
    mia.env.SlashCmdList.CUTE("diag")
    local said = false
    for _, l in ipairs(mia.chat) do if l:find("diag policy: line " .. mia.C.Policy.line.fp .. " carrying the policy", 1, true) and not l:find("waiting", 1, true) then said = true end end
    assert(said, "/cute diag says where her policy comes from")
    tickAll(60)
    assert(#leakedTo(mo, g2 + 1) == 0, "nothing the officers closed went on GUILD: " .. table.concat(leakedTo(mo, g2 + 1), ", "))
    local ask, record
    for _, m in ipairs(mia.sent) do
      if not ask and m.msg:sub(1, 2) == "1R" then ask = m.at end
      if not record and m.msg:sub(1, 2) == "1F" then record = m.at end
    end
    assert(ask and record and record - ask <= 2, "her record right after her ask: " .. tostring(record and ask and record - ask))
    local n = 0
    for _, m in ipairs(mia.sent) do if m.at <= start + 60 then n = n + 1 end end
    assert(n < 20, "Mia's first minute: " .. n)
    budget41 = n
    local mr = mo.env.CuteDB.roster["Mia-Forever"]
    assert(mr and mr.stats.level == 30 and mr.stats.gold == nil and mr.stats.deaths == nil and mr.stats.zone == nil and ofa2.env.CuteDB.roster["Mia-Forever"].stats.gold == 777777,
      "Mo has Mia's record, none of what the officers closed; Ofa her gold, whispered")
    for _, c in ipairs({ ofa2, mo, ann, bea, mal, mia }) do leave(c) end
    JUDGE = nil
  end)
  -- (f) no line: Cid and Dee, the older policy both, nobody else online
  isolated({ member("Ofa", 0), member("Cid", 3), member("Dee", 3) }, function()
    local cid, dee = char("Cid", 3, { money = 1111 }), char("Dee", 3, { money = 2222 })
    local ofaDb = db(NEW, nil, true)
    JUDGE = judgeBy(ofaDb)
    dee.got = {}
    login(cid, db(OLD)); login(dee, db(OLD))
    tickAll(45)
    local got = {}
    for _, x in ipairs(leakedTo(dee)) do got[x] = true end
    assert(got["Cid-Forever gold"] and dee.env.CuteDB.roster["Cid-Forever"].stats.gold == 1111 and dee.C.Policy:Describe():find("no Cute line", 1, true),
      "irreducible: in a guild with no line, with no officer online they use the older policy, and what it opens goes on GUILD")
    local ofa = newClient(charOf({ "Ofa", 0, "Officer", "MAGE", 30 }))
    ofa.clock = dee.clock
    login(ofa, ofaDb)
    -- (her policy goes once her client has read Guild Info: some twenty seconds on with no line there; the answers to
    -- her ask that leave before it go by the older policy, part of what is irreducible without a line)
    tickAll(40)
    local cr = dee.env.CuteDB.roster["Cid-Forever"]
    assert(dee.C.Policy:Vis("gold") == "self" and cr.stats.gold == nil and cr.stats.deaths == nil, "an officer logs in: Dee's client deletes Cid's gold and deaths")
    local mark = #dee.got
    cid.o.money = 3333
    fire(cid, "PLAYER_MONEY")
    tickAll(6)
    local l = leakedTo(dee, mark + 1)
    assert(#l == 0 and ofa.env.CuteDB.roster["Cid-Forever"].stats.gold == 3333, "from then on nothing goes on GUILD, Cid's gold to Ofa alone: " .. table.concat(l, ", "))
    for _, c in ipairs({ cid, dee, ofa }) do leave(c) end
    JUDGE = nil
  end)
  -- (g) one account in two guilds: guild 8's line keeps Raids to its officers; the alt there logs in, then the main in
  -- guild 7, whose line keeps Gold
  isolated({ member("Ofa", 0), member("Mo", 3), member("Xo", 0), member("Xalt", 3) }, function()
    local function club8(c)
      local cc = c.env.C_Club
      local gm, gi, gs = cc.GetClubMembers, cc.GetMemberInfo, cc.GetMemberInfoForSelf
      cc.GetGuildClubId = function() return c.inGuild and 8 or nil end
      cc.GetClubMembers = function(id) return gm(id == 8 and 7 or id) end
      cc.GetMemberInfo = function(id, i) return gi(id == 8 and 7 or id, i) end
      cc.GetMemberInfoForSelf = function(id) return gs(id == 8 and 7 or id) end
    end
    local seven = { vis = { gold = "self", zone = "self" }, threshold = 1 }
    local eight = { vis = { gold = "all", gc_raids = "self" }, threshold = 2 }
    INFO[7], INFO[8] = "Guild seven.\n" .. infoLine(seven), infoLine(eight)
    local account = {}
    local mo = char("Mo", 3, { money = 4242 })
    login(mo, account)
    tickAll(30)
    assert(account.policy and mo.C.Policy:Holds() and mo.C.Policy:Route("zone") == "self" and mo.C.Policy:Threshold() == 1, "guild 7's line routes Mo")
    leave(mo)
    local xalt = char("Xalt", 3)
    club8(xalt)
    login(xalt, account)
    tickAll(30)
    assert(xalt.C.Policy:Holds() and xalt.C.Policy:Route("zone") == "all" and xalt.C.Policy:Route("gold") == "all" and xalt.C.Policy:Route("gc_raids") == "self" and xalt.C.Policy:Threshold() == 2,
      "guild 8's line routes its alt")
    assert(account.policies and account.policies["7"] and account.policies["7"].policy.vis.zone == "self", "guild 7's kept for its characters, untouched")
    leave(xalt)
    local mo2 = char("Mo", 3, { money = 4242 })
    login(mo2, account)
    assert(mo2.C.Policy:Holds() and mo2.C.Policy:Route("zone") == "self" and mo2.C.Policy:Route("gc_raids") == "all" and mo2.C.Policy:Threshold() == 1, "back in guild 7: its own line, the alt changed nothing")
    leave(mo2)
  end)
  print("Guild Info: the policy saved as one line, the guild's text kept, only Cute's line replaced; a guild's text too long for the whole line saves nothing (no line with the fingerprint alone), a member with an older policy routes by the line at its first read, nothing passed on (Mia's first minute " .. tostring(budget41) .. " messages); forged policies, an officer's older one and an unsaved change route nothing elsewhere, Settings say who may save; a value waiting in the queue leaves by the line it finds; each guild its own line; with no line, two members alone use the older one until an officer logs in (irreducible)")
end

-- 42: what a member's client keeps of the others once the officers close a category (0.6.0). Ofa and Ofb, officers;
-- Ann, Mo, Zed and Yu, members; the officers keep the Kills statistics to themselves and open the gear gaps (so
-- Enchanted slots goes to the guild). Yu's client lists no statistics
-- at login (still loading): Zed's are held aside, not dropped, and once Yu's probe defines them the Deaths one is kept
-- and a Kills one (sent on GUILD as a 0.5.x client would) dropped, by their own categories. Ann and Mo kill Rhahk'Zor
-- together, both see its loot window and both wear an enchanted neck; then, while Mo is offline, the officers keep
-- Bosses and Enchanted slots to themselves and save it to Guild Info. Ann's client takes the others' GUIDs out of what
-- it learned (the kills, who saw the loot, who wore the enchant, the model) at once; Mo's at his next login, from Guild
-- Info's line with no officer online. Each keeps what was learned, and on how many members. Then Ann logs in again with
-- both officers online: her answer to Ofa's ask comes before her own pass, which still tells Ofb her kill, its label
-- and its claim, and tells Ofa none of them twice
collectgarbage()
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 30, online = true } end
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Ann", 3), member("Mo", 3), member("Zed", 3), member("Yu", 3) }, function()
    -- (the officers open the gear gaps, so Enchanted slots goes to the guild until they close it)
    local function db(mine) return { policy = { vis = { gc130 = "self", unenchanted = "all", empty_slots = "all" }, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = EPOCH + 100, threshold = 1 } } end
    local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "WARRIOR", 30 }, extra)) end
    local function neck() return { [1] = "item:3001:0", [2] = "item:3002:2564", [5] = "item:3005:0" } end
    local ofa, ofb, ann, mo = char("Ofa", 0), char("Ofb", 1), char("Ann", 3, { items = neck() }), char("Mo", 3, { items = neck() })
    local zed, yu = char("Zed", 3, { withStats = true }), char("Yu", 3, { withStats = true })
    yu.statsEmpty = true
    local ofaDb, ofbDb, annDb, moDb = db(true), db(), db(), db()
    JUDGE = judgeBy(ofaDb)
    for _, c in ipairs({ mo, yu }) do c.got = {} end
    login(ofa, ofaDb); login(ofb, ofbDb); login(ann, annDb); login(mo, moDb); login(zed, db()); login(yu, db())
    -- (1) Yu's probe finds no statistics at login and asks again at 30 s and two minutes; Zed's come meanwhile
    tickAll(110)
    zed.C.Comm.Queue({ msg = "1D|4|g2001=1" })
    tickAll(3)
    -- (that one, a Kills statistic on GUILD as a 0.5.x client sends it, and a boss's loot below are the only things the
    -- officers keep that the members get)
    local zr = yu.env.CuteDB.roster["Zed-Forever"]
    local held = yu.C.Roster.held["Zed-Forever"]
    assert(zr and zr.stats.level == 30 and zr.stats.g2007 == nil and held and held.v.g2007 and held.v.g2007.v == 17 and held.v.g2001,
      "on Yu's client Zed's statistics wait, neither kept nor dropped")
    yu.statsEmpty = false
    tickAll(45)
    assert(yu.C.Stats.game.defined and zr.stats.g2007 == 17 and zr.stats.g2001 == nil and next(yu.C.Roster.held) == nil, "defined: Deaths kept, the Kills one dropped by its category")
    -- (2) Ann and Mo kill Rhahk'Zor in one group, each sees its loot window; both wear an enchanted neck
    for _, pair in ipairs({ { ann, mo }, { mo, ann } }) do
      local c = pair[1]
      c.o.party = { pair[2].o.name }
      c.o.instance, c.o.instanceID, c.o.instName = "party", 36, "The Deadmines"
      fire(c, "PLAYER_ENTERING_WORLD", false, false)
    end
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {}); fire(mo, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    for _, c in ipairs({ ann, mo }) do c.lootWindow = { { 50001, 3 } }; fire(c, "LOOT_OPENED", false, false); c.lootWindow = nil end
    tickAll(15)
    local mk = moDb.known
    assert(mk.kills[1230] and mk.kills[1230][ann.o.guid] and mk.loot[1230].by[50001][ann.o.guid] and mk.enchant[2].who[ann.o.guid]
      and mk.enchant[2].kinds["15.0"].who[ann.o.guid] and mk.model.bosses[1230].who[ann.o.guid], "before: Mo's client learned Ann's kill, her loot window and her neck, by her GUID")
    -- the stores a member's saved variables keep by GUID: another member's GUID in any of them, or nil
    local everyone = { ofa, ofb, ann, mo, zed, yu }
    local function holds(t, guids, path, depth)
      if type(t) ~= "table" or depth > 8 then return nil end
      for k, v in pairs(t) do
        if (type(k) == "string" and guids[k]) or (type(v) == "string" and guids[v]) then return path .. "." .. tostring(k) end
        local g = holds(v, guids, path .. "." .. tostring(k), depth + 1)
        if g then return g end
      end
      return nil
    end
    -- (where one is: "kills.1230.Player-..."). The stores Bosses and Enchanted slots cover; who entered a dungeon is
    -- the Dungeons category's, which the officers leave open here
    -- (and the labels' voices of the bosses, and who brought a boss's loot first; the count of labels each said stays
    -- no more than the voices left)
    local function trace(cdb, me)
      local guids = {}
      for _, x in ipairs(everyone) do if x.o.guid ~= me then guids[x.o.guid] = true end end
      local k = cdb.known
      local bossVoices = {}
      for id, v in pairs(k.voice or {}) do if id:match("^e%d+$") then bossVoices[id] = v end end
      for _, store in ipairs({ { "kills", k.kills }, { "loot", k.loot }, { "enchant", k.enchant }, { "model.bosses", k.model and k.model.bosses },
        { "voice", bossVoices }, { "lootFrom", k.lootFrom } }) do
        local g = holds(store[2], guids, store[1], 0)
        if g then return g end
      end
      for g, n in pairs(k.vn or {}) do
        local left = 0
        for _, v in pairs(k.voice or {}) do if v[g] then left = left + 1 end end
        if guids[g] and n > left then return "vn." .. g end
      end
      return nil
    end
    -- (3) the officers keep Bosses and Enchanted slots to themselves while Mo is offline
    leave(mo)
    ofa.C.Policy:Set("gc_bosses", "self")
    ofa.C.Policy:Set("enchanted", "self")
    assert(saveLine(ofa))
    tickAll(15)
    local function learned(c, label)
      local b = c.C.Rules.Model().bosses[1230]
      assert(c.C.Stats.EnchantLearned(2, "15.0") and c.C.Stats.EnchantSeen(2, "15.0") == 2 and b and b.n == 2 and b.loot[50001] == "seen",
        label .. ": what was learned stays, on two members: " .. tostring(b and b.n))
    end
    assert(trace(annDb, ann.o.guid) == nil, "Ann's client holds no other member's GUID in what it learned: " .. tostring(trace(annDb, ann.o.guid)))
    learned(ann, "Ann")
    local amo = annDb.roster["Mo-Forever"].stats
    assert(amo.e1230 == nil and amo.enchanted == nil and amo.ench_kinds == nil and amo.level == 30, "nor Mo's kills and enchants in his record")
    -- (4) Mo logs in with no officer online: Guild Info's line says the closings, and his client takes the GUIDs out
    leave(ofa); leave(ofb)
    local mo2 = char("Mo", 3, { items = neck() })
    mo2.clock = ann.clock
    mo2.got = mo.got
    login(mo2, moDb)
    tickAll(40)
    assert(mo2.C.Policy:Holds() and mo2.C.Policy:Vis("gc_bosses") == "self" and mo2.C.Policy:Vis("enchanted") == "self", "Guild Info's line closed Bosses and Enchanted on Mo's client")
    assert(trace(moDb, mo.o.guid) == nil, "Mo's saved variables hold no other member's GUID in what they learned: " .. tostring(trace(moDb, mo.o.guid)))
    learned(mo2, "Mo")
    -- a boss's loot from a 0.5.x client, on GUILD, would name Zed as one who saw it: Mo's client passes it by
    zed.C.Comm.Queue({ msg = "1L|l1230=" .. zed.C.Comm.b36(50001) .. ";e1230:36=Rhahk'Zor" })
    tickAll(3)
    assert(trace(moDb, mo.o.guid) == nil, "a boss's loot the officers keep teaches Mo's client nothing")
    -- (5) both officers online; Ann logs in again. Her answer to Ofa's ask before her own pass tells Ofa alone; her
    -- own pass still tells Ofb, and Ofa nothing twice
    local ofa2, ofb2 = char("Ofa", 0), char("Ofb", 1)
    ofa2.clock, ofb2.clock = ann.clock, ann.clock
    login(ofa2, ofaDb); login(ofb2, ofbDb)
    tickAll(30)
    leave(ann)
    local ann2 = char("Ann", 3, { items = neck() })
    ann2.clock = ofa2.clock
    ofa2.got, ofb2.got = {}, {}
    login(ann2, annDb)
    tickAll(50)
    ann2.C.Comm:FullGame(true, { ofa2.sender })
    tickAll(10)
    local function told(c, what) local k = 0; for _, m in ipairs(c.got) do if m.from == ann2.sender and m.channel == "WHISPER" and m.msg:find(what, 1, true) then k = k + 1 end end return k end
    assert(told(ofa2, "e1230:36=") == 1 and told(ofa2, "1K|1230@") == 1 and told(ofa2, "e1230=") == 1 and told(ofb2, "e1230:36=") == 0,
      "the answer to Ofa's ask told her the kill, its label and its claim, and Ofb nothing")
    tickAll(45)
    assert(told(ofb2, "e1230:36=") == 1 and told(ofb2, "1K|1230@") == 1 and told(ofb2, "e1230=") == 1, "Ann's own pass told Ofb")
    assert(told(ofa2, "e1230:36=") == 1 and told(ofa2, "1K|1230@") == 1 and told(ofa2, "e1230=") == 1, "and Ofa nothing twice")
    for _, c in ipairs({ mo, yu }) do
      local l = leakedTo(c)
      table.sort(l)
      assert(table.concat(l, ", ") == "Zed-Forever e1230, Zed-Forever g2001, Zed-Forever l1230", c.o.name .. " received only what Zed sent as 0.5.x would: " .. table.concat(l, ", "))
    end
    for _, c in ipairs({ ann2, mo2, zed, yu, ofa2, ofb2 }) do leave(c) end
    JUDGE = nil
    print("traces: a statistic not defined yet held aside and kept or dropped by its category once defined; Bosses and Enchanted closed: the others' GUIDs gone from the kills, the loot, the enchants and the model, on the client online at once and on one logging in later from Guild Info's line, what was learned kept on two members; an answer before the own pass leaves the other officer told")
  end)
end

-- 43: no Everyone stat rebuilds an Only-you one (0.6.0). With the defaults the officers keep the gear gaps (Missing
-- enchants, Empty slots); Enchanted slots, which with the slots the guild knows take an enchant would list a
-- character's missing ones, goes their way too, the kinds of the enchanted items with it, and Ready counts only what
-- everyone may see. Ofa, an officer (an enchanted chest); Ann (an enchanted neck, a bare chest, empty slots), Bo (an
-- enchanted neck and chest) and Cy (a bare neck, an enchanted chest), members; Mal runs an edited copy; Dee logs in
-- later. Read off the bus and out of the saved variables: Cy's client cannot list Ann's missing enchants from anything
-- it receives or saves. Cy learns the neck and the chest take an enchant all the same, from the officers' word (1N:
-- slots and kinds, no GUID, no name, no count), and Missing enchants asks for his neck "from the officers"; Mal's word,
-- from no officer, teaches nothing; the research's wrist the officer's client doubts is doubted on Cy's from the word. Dee asks with no word and gets the officer's; Cy asking again with the word he
-- holds gets none. With Bosses kept to the officers too, Ann's and Bo's kill in one group reaches Cy as the officers'
-- word: the boss seen, "from the officers", none of their kills on his client
collectgarbage()
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 30, online = true } end
  isolated({ member("Ofa", 0), member("Ann", 3), member("Bo", 3), member("Cy", 3), member("Mal", 3), member("Dee", 3) }, function()
    local function char(name, rank, items) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "WARRIOR", 30 }, { items = items })) end
    local ofa = char("Ofa", 0, { [1] = "item:3001:0", [5] = "item:3005:7" })
    local ann = char("Ann", 3, { [1] = "item:3001:0", [2] = "item:3002:2564", [5] = "item:3005:0" })
    local bo = char("Bo", 3, { [1] = "item:3001:0", [2] = "item:3002:2564", [5] = "item:3005:7" })
    local cy = char("Cy", 3, { [1] = "item:3001:0", [2] = "item:3002:0", [5] = "item:3005:7" })
    local mal = char("Mal", 3, { [1] = "item:3001:0" })
    local ofaDb = { policy = { vis = {}, by = "Ofa-Forever", mine = true, rank = 0, at = EPOCH + 100, threshold = 1 } }
    JUDGE = judgeBy(ofaDb)
    cy.got = {}
    local start = cy.clock
    login(ofa, ofaDb)
    for _, c in ipairs({ ann, bo, cy, mal }) do login(c) end
    tickAll(60)
    local firstMinute = {}
    for _, c in ipairs({ ofa, ann, bo, cy }) do
      local n = 0
      for _, m in ipairs(c.sent) do if m.at <= start + 60 then n = n + 1 end end
      assert(n < 20, c.o.name .. ": under twenty messages in the first minute: " .. n)
      firstMinute[#firstMinute + 1] = c.o.name .. " " .. n
    end
    tickAll(90)
    -- (1) the officer has Ann's gaps; Cy's client has nothing to list them from
    local oa = ofa.env.CuteDB.roster["Ann-Forever"].stats
    assert(oa.unenchanted and oa.unenchanted[5] and oa.enchanted and oa.enchanted[2] and next(oa.empty_slots), "the officer has Ann's missing chest, her neck and her empty slots")
    local GEAR = { enchanted = true, ench_kinds = true, unenchanted = true, empty_slots = true, ilvl_slots = true, old_gear = true }
    for _, m in ipairs(cy.got) do
      if m.from ~= cy.sender then
        assert(m.channel ~= "WHISPER", "Cy was whispered nothing")
        for _, id in ipairs(wireIds(m.msg)) do assert(not GEAR[id], "Cy received " .. m.from .. "'s " .. id) end
      end
    end
    assert(#leakedTo(cy) == 0, "nothing the officers keep reached Cy: " .. table.concat(leakedTo(cy), ", "))
    local cdb = cy.env.CuteDB
    for key, e in pairs(cdb.roster) do for id in pairs(e.stats) do assert(not GEAR[id], "Cy's saved variables hold " .. key .. "'s " .. id) end end
    for slot, rec in pairs(cdb.known.enchant or {}) do
      for g in pairs(rec.who or {}) do assert(g == cy.o.guid, "Cy's knowledge names no other member's enchant: slot " .. slot) end
      for _, kr in pairs(rec.kinds or {}) do for g in pairs(kr.who or {}) do assert(g == cy.o.guid, "nor by kind of item") end end
    end
    -- Ann's Ready on Cy's client counts what everyone may see: ready, her missing chest and empty slots the officers'
    local ca = cdb.roster["Ann-Forever"].stats
    assert(ca.ready == 2 and #cy.C.Stats.ReadyGaps(ca) == 0 and oa.ready == 2, "Ann's Ready tells Cy nothing of her gaps: " .. tostring(ca.ready))
    -- (2) Cy learned the neck and the chest from the officers' word, which names nobody
    local words = {}
    for _, m in ipairs(cy.got) do if m.msg:sub(1, 2) == "1N" then words[#words + 1] = m end end
    assert(#words >= 1 and words[1].from == ofa.sender, "the officer said what the guild learned: " .. #words)
    for _, m in ipairs(words) do
      local body = m.msg:match("^1N|%d+|%d+/%d+|(.*)$")
      for kv in body:gmatch("[^;]+") do assert(kv:match("^n%d+=[%d%.,]+$"), "the word holds slots and kinds alone: " .. kv) end
      for _, c in ipairs({ ofa, ann, bo, cy, mal }) do
        assert(not body:find(c.o.guid:match("([^%-]+)$"), 1, true) and not body:find(c.o.name, 1, true), "the word names no member: " .. body)
      end
    end
    assert(cy.C.Stats.EnchantLearned(2, "15.0") and cy.C.Stats.EnchantLearned(5) and cy.C.Stats.EnchantSeen(2) == 0 and cy.C.Stats.EnchantSource(2, "15.0") == "from the officers",
      "Cy learned the neck and the chest, from the officers: " .. cy.C.Stats.EnchantSource(2, "15.0"))
    assert((cy.C.Sample:Value("unenchanted") or {})[2] and (ann.C.Sample:Value("unenchanted") or {})[5], "Missing enchants asks for Cy's neck, and Ann's chest on her own client")
    cy.env.CuteDB.settings.columns.prog = { ready = true, unenchanted = true }
    cy.C.UI:Open("prog")
    assert(cellOf(rowOf(cy, "Ann"), "unenchanted").label:GetText() == "-", "a dash for Ann's Missing enchants")
    local tip = tipOf(cellOf(rowOf(cy, "Cy"), "unenchanted"))
    assert(tip:find("Neck (Junk) | from the officers", 1, true), "his own tooltip names the source:\n" .. tip)
    check(cy.C.UI.frame, "member prog, the officers' word")
    -- (3) Mal's word, from no officer, teaches nothing
    mal.C.Comm.Queue({ msg = "1N|" .. string.format("%.0f", EPOCH + mal.clock) .. "|n9=4.1;n7=15.0" })
    tickAll(4)
    assert(not cy.C.Stats.EnchantLearned(9) and not cy.C.Stats.EnchantLearned(7) and not cdb.known.word["Mal-Forever"], "Mal's word taught Cy nothing")
    -- (the research's wrist, worn by members at 30 for fifteen days with no enchant seen there, as the officer's client
    -- tells from the empty slots it alone receives: doubted, and the word says so)
    if SEEDED then
      ofa.env.CuteDB.known.watch = ofa.env.CuteDB.known.watch or {}
      ofa.env.CuteDB.known.watch[9] = ofa.C.Now() - 15 * 86400
      assert(ofa.C.Rules.SeedSlotState(9) == "doubted" and cy.C.Rules.SeedSlotState(9) ~= "doubted", "the officer's client doubts the wrist, Cy's cannot tell")
      ofa.C.Comm:WordSoon()
      tickAll(12)
      assert(cy.C.Rules.SeedSlotState(9) == "doubted" and cy.C.Rules.WordDoubted(9), "Cy's client doubts it from the officers' word")
    end
    -- (4) Dee logs in with no word: the officer answers his ask with it; Cy asking again with the word he holds: none
    local dee = char("Dee", 3, { [1] = "item:3001:0", [2] = "item:3002:0" })
    dee.clock = cy.clock
    local o0 = msgs(ofa, "1N")
    login(dee)
    tickAll(30)
    assert(msgs(ofa, "1N") == o0 + 1 and dee.C.Stats.WordEnchant(2) and (dee.C.Sample:Value("unenchanted") or {})[2], "Dee's ask got the officer's word: " .. (msgs(ofa, "1N") - o0))
    o0 = msgs(ofa, "1N")
    cy.C.Comm:Ask()
    tickAll(30)
    assert(msgs(ofa, "1N") == o0, "Cy's ask, with the word he holds, got none again")
    -- (5) Bosses kept to the officers too: Ann's and Bo's kill in one group reaches Cy as the officers' word
    ofa.C.Policy:Set("gc_bosses", "self")
    ofa.C.Comm:SendPolicy()
    tickAll(4)
    for _, pair in ipairs({ { ann, bo }, { bo, ann } }) do
      local c = pair[1]
      c.o.party = { pair[2].o.name }
      c.o.instance, c.o.instanceID, c.o.instName = "party", 36, "The Deadmines"
      fire(c, "PLAYER_ENTERING_WORLD", false, false)
    end
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {}); fire(bo, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    -- (a word that only adds goes a minute after the officer's last at most: closing Bosses said the dungeon, the kill
    -- comes in the next)
    tickAll(80)
    local ob = ofa.C.Rules.Model().bosses[1230]
    assert(ofa.C.Rules.Corroborated(1230, ann.o.guid) and ob and ob.n == 2, "the officer weighed the kill: two members: " .. tostring(ob and ob.n))
    local cb = cy.C.Rules.Model().bosses[1230]
    assert(cb and cb.state == "seen" and cb.officers and cy.C.Rules.Words(cb) == "from the officers" and cy.C.Rules.Model().dungeons[36], "Cy's model has the boss seen, from the officers")
    assert(not cdb.roster["Ann-Forever"].stats.e1230 and not (cdb.known.kills and cdb.known.kills[1230]) and #leakedTo(cy) == 0, "and none of their kills")
    for _, c in ipairs({ ofa, ann, bo, cy, mal, dee }) do leave(c) end
    JUDGE = nil
    print("gear gaps: with the defaults a member's client cannot list another's missing enchants from anything it receives or saves (no Enchanted slots, no kinds, Ready counting durability and potions); it learns the slots from the officers' word, which names nobody, and an edited copy's word teaches nothing; a late member's ask gets the word, a current one none; with Bosses kept, a kill reaches members as the officers' word; first minute " .. table.concat(firstMinute, ", "))
  end)
end

-- 44: sender strings and roster names in each form the live client may give them (0.6.0). QuestBank found Forever's
-- sender carrying a surname its name API does not give, and ClubMemberInfo.name may be a Kstring; which forms this
-- client gives is not known yet, and matched as one text every member would be marked suspect and no officer known. In
-- each form an officer (Ofa Stone) and a member (Mia Lark, whose gold goes to the officers alone) run Cute: nobody is
-- marked, Mia takes Ofa for an officer and whispers her gold to her alone, and a record and an ask carrying Ofa's GUID
-- under Mal's sender string are still marked and take nothing. Then two members sharing a first name (Helga Xan, an
-- officer, and Helga Yin) under a sender string giving the first name alone: unsure, nobody marked, no officer by it,
-- while another first name with a Helga's GUID is still another's; and with Kstrings, a Helga online whose name reads
-- in no form leaves the officer Helga matched by one word unsure, nothing whispered to either, until she logs off.
-- /cute diag's names line gives the shapes, no name
collectgarbage()
do
  local PEOPLE = { { "Ofa", "Stone", 0 }, { "Mia", "Lark", 3 }, { "Mal", "Grim", 3 } }
  local FORMS = {
    { what = "'First Last-Realm' against 'First Last'", sender = function(f, l) return f .. " " .. l .. "-Forever" end, roster = function(f, l) return f .. " " .. l end,
      names = "senders: 2 words + realm (3); roster: 2 words (3); GUID names: not needed; vouched 1, unsure 0, other 1" },
    { what = "'First-Realm' against 'First Last'", sender = function(f) return f .. "-Forever" end, roster = function(f, l) return f .. " " .. l end,
      names = "senders: 1 word + realm (3); roster: 2 words (3); GUID names: not needed; vouched 1, unsure 0, other 1" },
    { what = "'First Last' against 'First'", sender = function(f, l) return f .. " " .. l end, roster = function(f) return f end,
      names = "senders: 2 words (3); roster: 1 word (3); GUID names: not needed; vouched 1, unsure 0, other 1" },
    { what = "'First Last' against Kstrings, GetPlayerInfoByGUID giving 'First'", sender = function(f, l) return f .. " " .. l end,
      roster = function(_, _, i) return "|Kq" .. i .. "|k" end, guidName = function(f) return f end,
      names = "senders: 2 words (3); roster: Kstring (3); GUID names: 1 word (3); vouched 1, unsure 0, other 1" },
  }
  local function guildOf(people, form)
    local g = {}
    for i, p in ipairs(people) do
      g[i] = { name = form.roster(p[1], p[2], i), guidName = form.guidName and form.guidName(p[1], p[2]) or nil, guid = guidOf(p[1] == "Helga" and (p[1] .. " " .. p[2]) or p[1]),
        rank = p[3], rankName = p[3] <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }
    end
    return g
  end
  local function char(p, form, extra)
    local o = charOf({ p[1], p[3], "", "MAGE", 30 }, extra)
    o.surname, o.sender = p[2], form.sender(p[1], p[2])
    return newClient(o)
  end
  -- the names line /cute diag prints on a client
  local function namesLine(c)
    local n0 = #c.chat
    c.env.SlashCmdList.CUTE("diag")
    for i = n0 + 1, #c.chat do local l = c.chat[i]:match("diag names: (.*)$"); if l then return l end end
  end
  local said = {}
  for _, form in ipairs(FORMS) do
    isolated(guildOf(PEOPLE, form), function()
      local ofa, mia = char(PEOPLE[1], form), char(PEOPLE[2], form, { money = 777777 })
      local mal = form.sender("Mal", "Grim")
      login(ofa); login(mia)
      tickAll(45)
      for _, c in ipairs({ ofa, mia }) do
        for key, e in pairs(c.env.CuteDB.roster) do assert(not e.suspect, form.what .. ": " .. c.o.name .. " marked nobody: " .. tostring(e.suspect and e.suspect.why)) end
        assert(c.C.Roster:MyRowCount() == 1 and not c.env.CuteDB.roster[c.sender], form.what .. ": one row of you, no record of yourself")
      end
      local targets = mia.C.Roster:OfficerTargets()
      assert(mia.C.Roster:OfficerSender(ofa.sender) and #targets == 1 and targets[1] == ofa.sender, form.what .. ": Mia takes Ofa for an officer: " .. table.concat(targets, ", "))
      local or_ = ofa.env.CuteDB.roster[mia.sender]
      assert(or_ and or_.stats.gold == 777777 and ofa.C.Roster:Vouch(mia.sender, mia.o.guid) == "same", form.what .. ": Ofa has Mia's gold, her GUID borne out")
      for _, m in ipairs(mia.sent) do
        assert(m.channel == "GUILD" and not m.msg:find("[|;]gold=") or m.target == ofa.sender, form.what .. ": Mia's gold whispered to Ofa alone: " .. m.channel .. " " .. tostring(m.target) .. " " .. m.msg)
      end
      -- Mal's copy, Ofa's GUID in a record and in an ask under his own sender string: marked, nothing taken
      mia.C.Comm:Receive("1F|1|1|4|guid=" .. ofa.o.guid .. ";level=u", "GUILD", mal)
      ofa.C.Comm:Receive("1R|" .. ofa.o.guid, "GUILD", mal)
      for _, c in ipairs({ mia, ofa }) do
        local e = c.env.CuteDB.roster[mal]
        assert(e and e.suspect and e.suspect.why:find("GUID", 1, true) and not e.stats.guid and c.C.Roster.selfSenders[mal] == nil, form.what .. ": Mal marked on " .. c.o.name .. "'s client: " .. tostring(e and e.suspect and e.suspect.why))
      end
      targets = mia.C.Roster:OfficerTargets()
      assert(#targets == 1 and targets[1] == ofa.sender, form.what .. ": still Ofa alone")
      -- someone outside the guild whispers under a name like Ofa's (in this form, where it is not Ofa's own sender
      -- string, which nobody else has): it makes no record, takes over none, and is whispered nothing
      local stranger = form.sender("Ofa", "Fake")
      if stranger ~= ofa.sender then
        for _, c in ipairs({ mia, ofa }) do
          c.C.Comm:Receive("1F|1|1|4|guid=" .. ofa.o.guid .. ";level=u;e1230=zz", "WHISPER", stranger)
          c.C.Comm:Receive("1D|4|gold=1", "WHISPER", stranger)
          assert(not c.env.CuteDB.roster[stranger] and not c.C.Roster:GuildSender(stranger), form.what .. ": a stranger's whisper makes no record on " .. c.o.name .. "'s client")
        end
        assert(mia.env.CuteDB.roster[ofa.sender] and mia.env.CuteDB.roster[ofa.sender].stats.guid == ofa.o.guid and not mia.env.CuteDB.roster[ofa.sender].stats.e1230,
          form.what .. ": Ofa's record stays hers")
        targets = mia.C.Roster:OfficerTargets()
        assert(#targets == 1 and targets[1] == ofa.sender, form.what .. ": and Mia whispers to Ofa alone")
      end
      local line = namesLine(mia)
      assert(line == form.names, form.what .. ": /cute diag's names line:\n" .. tostring(line))
      for _, word in ipairs({ "ofa", "mia", "mal", "stone", "lark", "grim" }) do assert(not line:lower():find(word, 1, true), "the names line names nobody: " .. line) end
      said[#said + 1] = line
      leave(ofa); leave(mia)
    end)
  end
  -- two members sharing a first name, the sender string giving it alone: either Helga may have sent it
  local form = FORMS[2]
  local people = { { "Ann", "Lee", 3 }, { "Helga", "Xan", 1 }, { "Helga", "Yin", 3 }, { "Mal", "Grim", 3 } }
  isolated(guildOf(people, form), function()
    local ann = char(people[1], form)
    login(ann)
    tickAll(10)
    local AR, adb = ann.C.Roster, ann.env.CuteDB.roster
    local hx, hy = guidOf("Helga Xan"), guidOf("Helga Yin")
    ann.C.Comm:Receive("1F|1|1|4|guid=" .. hx .. ";level=u", "GUILD", "Helga-Forever")
    local he = adb["Helga-Forever"]
    assert(he and he.stats.guid == nil and not he.suspect, "a first name two members share: unsure, no GUID kept (no row, voice or invite of either), nobody marked")
    assert(AR:SenderMember("Helga-Forever") == nil and AR:Vouch("Helga-Forever", hy) == nil and not AR:OfficerSender("Helga-Forever") and #AR:OfficerTargets() == 0,
      "either Helga's GUID unsure under it; no officer by it, though Helga Xan is one, and nothing whispered to it")
    ann.C.Comm:Receive("1F|1|1|4|guid=" .. hx .. ";level=u", "GUILD", "Mal-Forever")
    assert(AR:Vouch("Mal-Forever", hx) == "other" and adb["Mal-Forever"].suspect and not adb["Mal-Forever"].stats.guid, "another first name with a Helga's GUID: another's, marked")
    local line = namesLine(ann)
    assert(line == "senders: 1 word + realm (3); roster: 2 words (4); GUID names: not needed; vouched 0, unsure 0, other 1", "/cute diag's names line:\n" .. tostring(line))
    leave(ann)
  end)
  -- a namesake online whose name reads in no form (GetPlayerInfoByGUID gives nothing for her): while she is online, a
  -- sender string that matches the officer by one word may be hers, so it names nobody, and nothing is whispered to it
  do
    local function gm(name, guidName, guid, rank, online) return { name = name, guidName = guidName, guid = guid, rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = online ~= false } end
    isolated({ gm("|Kq1|k", "Helga", guidOf("Helga Stone"), 0), gm("|Kq2|k", "Mia", guidOf("Mia"), 3), gm("|Kq3|k", nil, guidOf("Helga Yin"), 3) }, function()
      local stone = newClient(charOf({ "Helga", 0, "", "MAGE", 30 }, { surname = "Stone", sender = "Helga Stone", guid = guidOf("Helga Stone") }))
      local mia = newClient(charOf({ "Mia", 3, "", "MAGE", 30 }, { surname = "Lark", sender = "Mia Lark", money = 777777 }))
      local yin = newClient(charOf({ "Helga", 3, "", "MAGE", 30 }, { surname = "Yin", sender = "Helga Yin", guid = guidOf("Helga Yin") }))
      login(stone); login(mia); login(yin)
      tickAll(45)
      local MR, db = mia.C.Roster, mia.env.CuteDB.roster
      assert(not MR:OfficerSender("Helga Yin") and not MR:IsOfficer("Helga Yin") and not (db["Helga Yin"] and db["Helga Yin"].suspect), "Yin is nobody's officer, and her honest record marks nobody")
      local s0 = #mia.sent
      mia.C.Comm:Receive("1R||0|0", "GUILD", "Helga Yin")
      mia.C.Comm:Receive(string.format("1P|%d|1|1/1|gold=a", EPOCH + mia.clock), "GUILD", "Helga Yin")
      tickAll(25)
      for i = s0 + 1, #mia.sent do assert(mia.sent[i].target ~= "Helga Yin", "nothing whispered to her") end
      assert(mia.C.Policy:Route("gold") == "self", "and her policy opens nothing")
      mia.C.Comm:Receive("1F|1|1|4|guid=" .. guidOf("Helga Stone") .. ";level=u", "GUILD", "Helga Yin")
      assert(db["Helga Stone"], "the officer's record is not folded away")
      -- Yin offline: the officer known again
      leave(yin)
      GUILD[3].online = false
      fire(mia, "GUILD_ROSTER_UPDATE")
      tickAll(5)
      assert(MR:OfficerSender("Helga Stone") and table.concat(MR:OfficerTargets(), ",") == "Helga Stone", "with her offline, Helga Stone is the officer again: " .. table.concat(MR:OfficerTargets(), ","))
      for _, c in ipairs({ stone, mia }) do leave(c) end
    end)
  end

  print("sender forms: " .. #FORMS .. " forms of the sender string against the roster's names (" .. table.concat((function() local w = {}; for i, f in ipairs(FORMS) do w[i] = f.what end; return w end)(), "; ") .. "): nobody marked, the officer known and whispered to alone, a forged GUID still marked; a first name two members share unsure, no officer by it, and a namesake online whose name reads in no form taking no officer's place; /cute diag shapes, e.g. " .. said[2])
end

-- 45: what the third round's review found (0.6.0), each case one that failed before its fix. (a) A member's forged
-- policy lowering the officer ranks to the guild master alone changes nothing, with no line in Guild Info and with one:
-- a rank-1 officer stays an officer on every client, her values kept, and the members whisper to her as before. (b) The
-- saved variables are the account's: a member alt logging in on the officer main's purges nothing. (c) A member made
-- an officer asks again and gets what does not change. (d) An officer still on 0.5.x is no one to whisper to. (e) A
-- roster slow at login: Guild Info is not read until it comes, so nothing goes but the ask (nothing by the stale
-- policy), and an officer's client keeps the whispers that came before it. (f) A 0.5.x member's Ready, which counted
-- the gear gaps, is not kept. (g) A policy of several messages applies whole: re-broadcast with a change, nothing it
-- closes goes on GUILD meanwhile; two officers online and a member logging in leave every client whole, the guild
-- master's own policy hers. (h) A waiting delta never lets an
-- older value arrive after it. (i) A thousand junk labels from one copy define nothing and keep no own boss, instance
-- or faction out; one copy's label places no awaited dungeon and renames nothing; a forged first kind does not keep a
-- dungeon open; junk loot keeps no own item out; made-up codes in a member's policy are taken nowhere; a policy stamped
-- far ahead is not taken; an untrusted member's labels teach nothing. (j) One forged ask a few seconds apart makes
-- nobody resend. (k) A cohort holding the policy Guild Info names answers a member holding another not at all (it
-- answered once, with the channel's delay, while members passed the policy on): she reads the line herself. (l) A double
-- ding is no suspect. (m) The policy held, asked for again, costs no purge; a record's chunk builds no rows. (n) The
-- word of several messages applies whole. (o) What a member's window shows: no leader on an Only-you stat, a Settings
-- box its label ticks
collectgarbage()
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true } end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function pol(mine, vis, at) return { policy = { vis = vis or {}, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = 1 } } end
  local function rec(c, who) return c.env.CuteDB.roster[who .. "-Forever"] end
  local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end return n end
  local said = {}

  -- (a) a member's forged policy with threshold 0 against a rank-1 officer, without a line and with one
  isolated({ member("Ofa", 0), member("Ofi", 1), member("Mia", 3), member("Mal", 3) }, function()
    local ofa, ofi, mia, mal = char("Ofa", 0), char("Ofi", 1), char("Mia", 3, { money = 777777 }), char("Mal", 3)
    login(ofa, pol(true)); login(ofi, pol()); login(mia, pol()); login(mal, pol())
    tickAll(60)
    assert(ofi.C.Roster:MeOfficer() and rec(ofi, "Mia").stats.gold == 777777, "before: Ofi an officer, holding Mia's gold")
    for round = 1, 2 do
      mal.C.Comm.Queue({ msg = string.format("1P|%d|0|1/1|", EPOCH + mal.clock + 30), first = true })
      tickAll(3)
      for _, c in ipairs({ ofa, ofi, mia }) do assert(c.C.Policy:Threshold() == 1, "the officer ranks stay the officers' on " .. c.o.name .. ", round " .. round) end
      assert(ofi.C.Roster:MeOfficer() and rec(ofi, "Mia").stats.gold == 777777 and rec(ofi, "Mia").stats.empty_slots, "Ofi keeps what she holds")
      assert(table.concat(mia.C.Roster:OfficerTargets(), ",") == ofa.sender .. "," .. ofi.sender, "Mia whispers to both: " .. table.concat(mia.C.Roster:OfficerTargets(), ","))
      -- (then the guild master saves the line)
      if round == 1 then assert(saveLine(ofa)); tickAll(15) end
    end
    for _, c in ipairs({ ofa, ofi, mia, mal }) do leave(c) end
    said[#said + 1] = "a forged policy narrows nothing"
  end)

  -- (b) one account: the officer main and a member alt share the saved variables
  isolated({ member("Ofa", 0), member("Alto", 3), member("Mia", 3), member("Mo", 3) }, function()
    local account = pol(true)
    local ofa, mia, mo = char("Ofa", 0), char("Mia", 3, { money = 777777 }), char("Mo", 3)
    login(ofa, account); login(mia, pol()); login(mo, pol())
    tickAll(60)
    assert(account.roster["Mia-Forever"].stats.gold == 777777, "the officer main holds Mia's gold")
    leave(mia); leave(ofa)
    for _, g in ipairs(GUILD) do if g.name == "Mia-Forever" or g.name == "Ofa-Forever" then g.online = false end end
    local alt = char("Alto", 3)
    login(alt, account)
    tickAll(10)
    local e = account.roster["Mia-Forever"]
    assert(not alt.C.Roster:MeOfficer() and e and e.stats.gold == 777777 and e.stats.empty_slots, "the member alt's login purges nothing of the officer's file")
    assert(not alt.C.Policy:CanSee(false, false, "gold"), "and the alt's window shows none of it")
    for _, c in ipairs({ alt, mo }) do leave(c) end
    said[#said + 1] = "an alt keeps its officer main's file"
  end)

  -- (c) made an officer: a fresh ask, and what does not change comes; (d) an officer on 0.5.x is whispered nothing
  isolated({ member("Ofa", 0), member("Mo", 2), member("Mia", 3), member("Ofb", 1) }, function()
    local ofa, mo, mia = char("Ofa", 0), char("Mo", 2), char("Mia", 3, { money = 777777 })
    login(ofa, pol(true)); login(mo, pol()); login(mia, pol())
    tickAll(60)
    assert(not mo.C.Roster:MeOfficer() and rec(mo, "Mia").stats.gold == nil, "Mo, rank 2, is no officer")
    ofa.C.Policy:SetThreshold(2)
    ofa.C.Comm:SendPolicy()
    tickAll(30)
    local e = rec(mo, "Mia")
    assert(mo.C.Roster:MeOfficer() and e.stats.gold == 777777 and e.stats.empty_slots, "made one, Mo asked again and has what does not change: " .. tostring(e.stats.gold))
    -- Ofb, an officer still on 0.5.x (its record says so, and its ask has no stamp)
    mia.C.Comm:Receive("1F|1|1|4|guid=" .. guidOf("Ofb") .. ";addon_ver=0.5.2;level=u", "GUILD", "Ofb-Forever")
    mia.C.Comm:Receive("1R|" .. guidOf("Ofb"), "GUILD", "Ofb-Forever")
    local targets = table.concat(mia.C.Roster:OfficerTargets(), ",")
    assert(not targets:find("Ofb", 1, true) and not mia.C.Comm.askers["Ofb-Forever"], "an officer on 0.5.x is no one to whisper to: " .. targets)
    for _, c in ipairs({ ofa, mo, mia }) do leave(c) end
    said[#said + 1] = "a new officer asks again; a 0.5.x one is whispered nothing"
  end)

  -- (e) a roster slow at login, a member's and an officer's
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
    local NEW = EPOCH + 500
    local ofaDb = pol(true, { gold = "self", deaths = "self" }, NEW)
    INFO[7] = infoLine(ofaDb.policy)
    local ofa, mo = char("Ofa", 0), char("Mo", 3)
    JUDGE = judgeBy(ofaDb)
    mo.got = {}
    login(ofa, ofaDb); login(mo, pol(nil, { gold = "self", deaths = "self" }, NEW))
    tickAll(45)
    local mia = char("Mia", 3, { money = 777777 })
    local real, slow = mia.env.C_Club.GetClubMembers, true
    mia.env.C_Club.GetClubMembers = function(...) if slow then return {} end return real(...) end
    local g0 = #mo.got
    login(mia, pol(nil, { gold = "all" }))
    tickAll(40)
    local sent = {}
    for _, m in ipairs(mia.sent) do sent[#sent + 1] = m.msg:sub(1, 2) end
    -- (the ask too waits for the roster: answers that came before it would crowd the early buffer)
    assert(mia.C.Comm.holding and not mia.C.Roster.trusted and mia.C.Policy.line == nil and table.concat(sent, " ") == "", "with no roster Guild Info is not read, and nothing goes, the ask waiting for it: " .. table.concat(sent, " "))
    slow = false
    fire(mia, "GUILD_ROSTER_UPDATE")
    tickAll(10)
    assert(mia.sent[1] and mia.sent[1].msg:sub(1, 3) == "1R|", "the ask first once the roster read")
    local l = leakedTo(mo, g0 + 1)
    assert(#l == 0 and not mia.C.Comm.holding and mia.C.Policy:Route("gold") == "self", "nothing went by the stale policy: " .. table.concat(l, ", "))
    JUDGE = nil
    for _, c in ipairs({ ofa, mo, mia }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
    local mia, mo = char("Mia", 3, { money = 777777 }), char("Mo", 3, { money = 4242 })
    login(mia, pol()); login(mo, pol())
    tickAll(60)
    local ofa = char("Ofa", 0)
    local real, slow = ofa.env.C_Club.GetClubMembers, true
    ofa.env.C_Club.GetClubMembers = function(...) if slow then return {} end return real(...) end
    login(ofa, pol(true))
    -- (the hello's ask waits for the roster; /cute resend asks at once)
    tickAll(10)
    ofa.C.Comm:Ask()
    tickAll(30)
    assert(#ofa.C.Comm.early > 0, "whispers before the officer's roster is known are kept: " .. #ofa.C.Comm.early)
    slow = false
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tickAll(5)
    assert(rec(ofa, "Mo").stats.gold == 4242 and rec(ofa, "Mia").stats.gold == 777777, "and taken once it is")
    for _, c in ipairs({ ofa, mo, mia }) do leave(c) end
    said[#said + 1] = "a slow roster holds the record and keeps the whispers"
  end)

  -- (f) a 0.5.x member's Ready
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mal", 3) }, function()
    local mia, mal = char("Mia", 3), char("Mal", 3)
    login(mia, pol()); login(mal, pol())
    tickAll(60)
    local b36 = mal.C.Comm.b36
    mal.C.Comm.Queue({ msg = "1F|1|1|4|guid=" .. mal.o.guid .. ";ready=1;durability=" .. b36(80) .. ";potions=" .. b36(5) .. ";unenchanted=1;addon_ver=0.5.2" })
    tickAll(3)
    local e = rec(mia, "Mal").stats
    assert(e.ready == nil and e.unenchanted == nil and e.durability == 80, "a 0.5.x Ready, which counted the gear gaps, is not kept: " .. tostring(e.ready))
    for _, c in ipairs({ mia, mal }) do leave(c) end
    said[#said + 1] = "0.5.x's Ready dropped"
  end)
  collectgarbage()

  -- (g) a policy of several messages: re-broadcast with a change; two officers at once
  isolated({ member("Ofa", 0), member("Kim", 3), member("Lee", 3) }, function()
    local ofa, kim, lee = char("Ofa", 0), char("Kim", 3), char("Lee", 3)
    for _, c in ipairs({ ofa, kim, lee }) do login(c) end
    tickAll(45)
    for _, def in ipairs(ofa.C.Stats.list) do if def.cat == "leveling" or def.cat == "prog" then ofa.C.Policy:Set(def.id, "self") end end
    ofa.C.Comm:SendPolicy()
    tickAll(60)
    assert(kim.C.Policy:Route("zone") == "self", "the long policy reached Kim")
    JUDGE = judgeBy(ofa.env.CuteDB)
    lee.got = {}
    ofa.C.Policy:Set("deaths", "self")
    ofa.C.Comm:SendPolicy()
    local s0 = #kim.sent
    tickAll(10)
    local l = leakedTo(lee)
    local onGuild = {}
    for i = s0 + 1, #kim.sent do if kim.sent[i].channel == "GUILD" and kim.sent[i].msg:sub(1, 2) == "1D" then onGuild[#onGuild + 1] = kim.sent[i].msg:sub(1, 60) end end
    assert(#l == 0 and kim.C.Policy:Route("zone") == "self", "re-broadcast in parts, taken whole, nothing it closes on GUILD meanwhile: " .. table.concat(l, ", ") .. " | " .. table.concat(onGuild, " | "))
    JUDGE = nil
    for _, c in ipairs({ ofa, kim, lee }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mo", 3), member("Mia", 3) }, function()
    local CLOSE = { "deaths", "falls", "drownings", "fatigue", "hearth_waste", "afk", "dance", "sit", "emotes", "gchat", "inspected", "fish", "jumps", "ghost_yards", "where", "grey_gold", "zone", "xp", "gc130" }
    local function db(m) local vis = {}; for _, id in ipairs(CLOSE) do vis[id] = "self" end; return pol(m, vis) end
    local function open(c) local n = 0; for _, id in ipairs(CLOSE) do if c.C.Policy:Vis(id) ~= "self" then n = n + 1 end end return n end
    local ofa, ofb, mo = char("Ofa", 0), char("Ofb", 1), char("Mo", 3)
    login(ofa, db(true)); login(ofb, db()); login(mo, db())
    tickAll(60)
    local mia = char("Mia", 3)
    login(mia, db())
    tickAll(25)
    for _, c in ipairs({ ofb, mo, mia }) do assert(open(c) == 0, "two officers' parts under one stamp leave " .. c.o.name .. " whole: " .. open(c) .. " open") end
    assert(open(ofa) == 0 and ofa.env.CuteDB.policy.mine and ofa.env.CuteDB.policy.by == ofa.C.Me(), "and the guild master's own policy hers")
    local m0 = #mo.sent
    fire(mo, "PLAYER_DEAD")
    tickAll(4)
    for i = m0 + 1, #mo.sent do assert(not (mo.sent[i].channel == "GUILD" and mo.sent[i].msg:find("deaths=", 1, true)), "Mo's death goes to the officers alone") end
    for _, c in ipairs({ ofa, ofb, mo, mia }) do leave(c) end
    said[#said + 1] = "a policy in parts applies whole"
  end)

  -- (h) a delta merged ahead of a record's chunk: the record's older value never arrives after it
  isolated({ member("Mia", 3), member("Mo", 3) }, function()
    local mia, mo = char("Mia", 3), char("Mo", 3)
    login(mia, pol()); login(mo, pol())
    tickAll(60)
    local C1 = mia.C
    C1.Comm:Full({})
    fire(mia, "PLAYER_DEAD"); C1.Comm:Changed()
    C1.Comm:Full({})
    fire(mia, "PLAYER_DEAD"); C1.Comm:Changed()
    tickAll(20)
    local e = rec(mo, "Mia")
    assert(e.stats.deaths == 2 and not e.suspect, "the newest value last, nobody marked: " .. tostring(e.stats.deaths) .. " " .. tostring(e.suspect and e.suspect.why))
    for _, c in ipairs({ mia, mo }) do leave(c) end
    said[#said + 1] = "no older value after a newer"
  end)
  collectgarbage()

  -- (i) one edited copy's labels, loot, policies and stamps
  isolated({ member("Ofa", 0), member("Ann", 3), member("Vee", 3), member("Mod", 3) }, function()
    local ofa, ann, vee, mod = char("Ofa", 0), char("Ann", 3), char("Vee", 3), char("Mod", 3)
    for _, c in ipairs({ ofa, ann, vee, mod }) do login(c) end
    tickAll(45)
    local found0 = #ann.C.Stats.byCat.found
    -- a thousand junk labels, no value for any
    local msgs, cur = {}, "1L|"
    for i = 1, 1000 do
      local p = "e" .. (900000 + i) .. ":1=Junk" .. i
      if #cur + #p + 1 > 255 then msgs[#msgs + 1] = cur; cur = "1L|" end
      cur = cur .. (cur == "1L|" and "" or ";") .. p
    end
    msgs[#msgs + 1] = cur
    -- and junk loot for a boss, forged kinds and names for the seed's dungeon, made-up codes in a policy
    msgs[#msgs + 1] = "1L|l1230=" .. (function() local t = {}; for i = 1, 24 do t[i] = mod.C.Comm.b36(50000 + i) end return table.concat(t, ".") end)()
    msgs[#msgs + 1] = "1L|i36:r=Lol Keep"
    local zq = {}
    for i = 1, 20 do zq[i] = string.format("-zq%03d", i) end
    msgs[#msgs + 1] = string.format("1P|%d|1|1/1|%s", EPOCH + mod.clock, table.concat(zq, ";"))
    for _, m in ipairs(msgs) do mod.C.Comm.Queue({ msg = m }) end
    tickAll(#msgs + 5)
    local AS = ann.C.Stats
    assert(#AS.byCat.found == found0, "a thousand junk labels define nothing: " .. (#AS.byCat.found - found0))
    assert(not (ann.env.CuteDB.policy and ann.env.CuteDB.policy.extra and #ann.env.CuteDB.policy.extra > 0), "made-up codes in a member's policy are taken nowhere")
    -- Ann's own play: her boss, her instance, her loot window, all defined and counted
    ann.o.instance, ann.o.instanceID, ann.o.instName = "party", 36, "The Deadmines"
    vee.o.instance, vee.o.instanceID, vee.o.instName = "party", 36, "The Deadmines"
    fire(ann, "PLAYER_ENTERING_WORLD", false, false)
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    tickAll(3)
    assert(AS.byId.e1230 and AS.byId.i36 and ann.C.Char().counters.e1230 == 1 and ann.C.Char().counters.i36 == 1, "her own kill and entry defined and counted")
    assert(ann.C.Rules.LearnLoot(1230, { 50001 }, true) and ann.env.CuteDB.known.loot[1230].items[50001], "her own loot item kept")
    -- (with no seed nobody had named the boss, and the junk was not taken; where the seed names it, one member's items
    -- are 24 at most and keep nobody's out: scenario 46)
    local junk = 0
    for id in pairs(ann.env.CuteDB.known.loot[1230].items) do if id > 50001 and id <= 50024 then junk = junk + 1 end end
    assert(junk == 0 or (SEEDED and junk <= 24), "the junk loot for a boss nobody had named not taken: " .. junk)
    -- one copy's kind: Dungeons closed, Vee's client deletes Ann's entries though Mod said the Deadmines is a raid
    fire(vee, "PLAYER_ENTERING_WORLD", false, false)
    tickAll(130)
    assert(rec(vee, "Ann").stats.i36 == 1 and ann.C.Rules.Model().dungeons[36].name ~= "Lol Keep", "Vee holds Ann's entry; one copy renames nothing")
    ofa.C.Policy:Set("gc_dungeons", "self")
    ofa.C.Comm:SendPolicy()
    tickAll(4)
    assert(rec(vee, "Ann").stats.i36 == nil and vee.C.Policy:Route("i36") == "self", "a forged kind keeps no dungeon open")
    -- an officer's policy stamped far ahead: not taken, and its sender marked
    ann.C.Policy:Receive(ofa.sender, 9999999999, 1, tok("gold", "all"))
    assert(ann.C.Policy:Vis("gold") == "self", "a policy stamped far ahead is not taken")
    -- an untrusted member's labels teach nothing
    ofa.C.Policy:SetUntrusted(mod.o.guid, true)
    ofa.C.Comm:SendPolicy()
    tickAll(4)
    local n = ann.C.Comm:ReceiveLabels("e990001:777=Made Up Boss;i777:r=Made Up Raid;f69=Darnassus", mod.sender)
    assert(n == 0 and not ann.env.CuteDB.known.labels.e990001, "an untrusted member's labels teach nothing")
    for _, c in ipairs({ ofa, ann, vee, mod }) do leave(c) end
    said[#said + 1] = "one copy's labels, loot, kinds, policies and stamps change nothing"
  end)
  if SEEDED then
    -- one copy's label places no awaited dungeon: Gil and Bo enter "the Drowned City", Mod named it first
    isolated({ member("Gil", 1), member("Vee", 3), member("Bo", 3), member("Mod", 3) }, function()
      local gil, vee, bo, mod = char("Gil", 1), char("Vee", 3), char("Bo", 3), char("Mod", 3)
      for _, c in ipairs({ gil, vee, bo, mod }) do login(c) end
      tickAll(45)
      mod.C.Comm.Queue({ msg = "1L|i9100:p=Pit of Lies;i36:p=Lol Keep" })
      tickAll(3)
      for _, c in ipairs({ gil, bo }) do
        c.o.instance, c.o.instanceID, c.o.instName = "party", 9100, "the Drowned City"
        fire(c, "PLAYER_ENTERING_WORLD", false, false)
      end
      tickAll(130)
      local d = vee.C.Rules.Model().dungeons[9100]
      assert(d and d.seeded and d.name == "the Drowned City" and vee.C.Rules.Model().dungeons[36].name == "The Deadmines", "two members place it, one copy's label renames nothing")
      for _, c in ipairs({ gil, vee, bo, mod }) do leave(c) end
    end)
  end
  collectgarbage()

  -- (j) a forged ask every twenty seconds
  isolated({ member("Ofa", 0), member("Bea", 3), member("Cy", 3), member("Mal", 3) }, function()
    local a, b, cy, mal = char("Ofa", 0), char("Bea", 3), char("Cy", 3), char("Mal", 3)
    for _, c in ipairs({ a, b, cy, mal }) do login(c) end
    tickAll(240)
    local n0 = #a.sent + #b.sent + #cy.sent
    for _ = 1, 6 do mal.C.Comm.Queue({ msg = "1R|" .. mal.o.guid .. "|0|0" }); tickAll(20) end
    local fulls = 0
    for _, c in ipairs({ a, b, cy }) do for _, m in ipairs(c.sent) do if m.msg:sub(1, 2) == "1F" and m.at > mal.clock - 120 then fulls = fulls + 1 end end end
    assert(fulls <= 3 * 6, "six asks in two minutes: one answer each at most: " .. fulls .. " chunks, " .. (#a.sent + #b.sent + #cy.sent - n0) .. " messages")
    said[#said + 1] = (#a.sent + #b.sent + #cy.sent - n0) .. " messages for six forged asks"
    for _, c in ipairs({ a, b, cy, mal }) do leave(c) end
  end)

  -- (k) a cohort holding the policy Guild Info names, the guild's text long, each with its own random, the channel's
  -- delay a second: no answer, Mia reads the line herself
  local cohort = { "Mo", "Ann", "Bea", "Cid", "Dee", "Eli" }
  local people = { member("Ofa", 0), member("Mia", 3) }
  for _, n in ipairs(cohort) do people[#people + 1] = member(n, 3) end
  isolated(people, function()
    local NEW = EPOCH + 500
    INFO[7] = ("Welcome to <Cute>! Raids Tue and Thu at 20:00. "):rep(9) .. "\n" .. infoLine({ vis = { gold = "self", zone = "self" } })
    local list = {}
    for i, n in ipairs(cohort) do
      local c = char(n, 3)
      local seed = 12345 + i * 7919
      c.env.math = setmetatable({ random = function(a, b)
        seed = (seed * 1103515245 + 12345) % 2147483648
        local r = seed / 2147483648
        if a and b then return a + math.floor(r * (b - a + 1)) end
        return r
      end }, { __index = math })
      list[#list + 1] = c
      login(c, pol(nil, { gold = "self", zone = "self" }, NEW))
    end
    tickAll(45)
    local mia = char("Mia", 3)
    local s0 = {}
    for _, c in ipairs(list) do s0[c] = #c.sent end
    login(mia, pol(nil, { gold = "all" }))
    local realDeliver = deliver
    deliver = function() end
    for _ = 1, 30 do tickAll(1); realDeliver() end
    deliver = realDeliver
    deliver()
    local answers = 0
    for _, c in ipairs(list) do for i = s0[c] + 1, #c.sent do if c.sent[i].msg:sub(1, 2) == "1P" then answers = answers + 1 end end end
    assert(#INFO[7] <= 499 and answers == 0 and mia.C.Policy:Holds() and mia.C.Policy:Vis("gold") == "self", "six members holding it answer none: " .. answers)
    for _, c in ipairs(list) do leave(c) end
    leave(mia)
    said[#said + 1] = "a cohort answers none"
  end)
  collectgarbage()

  -- (l) two dings a second apart; (m) an echo costs no purge, a record's chunk builds no rows
  isolated({ member("Ofa", 0), member("Mia", 3) }, function()
    local ofa, mia = char("Ofa", 0), char("Mia", 3, { level = 5 })
    for _, g in ipairs(GUILD) do if g.name == "Mia-Forever" then g.level = 5 end end
    login(ofa, pol(true)); login(mia, pol())
    tickAll(60)
    -- (Ofa's roster lags twelve seconds behind the dings, as the game answers a roster request every ten at most)
    local lag = ofa.clock + 12
    local realInfo = ofa.env.C_Club.GetMemberInfo
    ofa.env.C_Club.GetMemberInfo = function(id, i) local r = realInfo(id, i); if r and r.guid == mia.o.guid and ofa.clock < lag then r.level = 5 end return r end
    local soon, realSoon = 0, ofa.C.Roster.Soon
    ofa.C.Roster.Soon = function(...) soon = soon + 1; return realSoon(...) end
    for _, l in ipairs({ 6, 7 }) do mia.o.level = l; fire(mia, "PLAYER_LEVEL_UP", l); tickAll(1) end
    tickAll(40)
    ofa.C.Roster.Soon, ofa.env.C_Club.GetMemberInfo = realSoon, realInfo
    local e = rec(ofa, "Mia")
    assert(soon > 0 and e.stats.level == 7 and not e.suspect, "two dings before a lagging roster has them: held, no suspect, the level kept: " .. tostring(e.suspect and e.suspect.why))
    local purges, rows = 0, 0
    local P, R = mia.C.Policy, mia.C.Roster
    local realPurge, realRows = P.Purge, R.Rows
    P.Purge = function(...) purges = purges + 1; return realPurge(...) end
    R.Rows = function(...) rows = rows + 1; return realRows(...) end
    if mia.C.UI.frame then mia.C.UI.frame:Hide() end
    for _ = 1, 3 do mia.C.Comm:Ask(); tickAll(10) end
    assert(purges == 0, "three echoes of the policy Mia holds: no purge: " .. purges)
    ofa.C.Comm:Full({})
    tickAll(10)
    assert(rows == 0, "a record's chunks build no rows while the window is hidden: " .. rows)
    P.Purge, R.Rows = realPurge, realRows
    for _, c in ipairs({ ofa, mia }) do leave(c) end
    said[#said + 1] = "a double ding no suspect; an echo no purge"
  end)

  -- (n) the officers' word in several messages applies once whole
  isolated({ member("Ofa", 0), member("Mo", 3) }, function()
    local ofa, mo = char("Ofa", 0), char("Mo", 3)
    login(ofa, pol(true)); login(mo, pol())
    tickAll(45)
    local at = string.format("%.0f", EPOCH + mo.clock)
    mo.C.Comm:Receive("1N|" .. at .. "|1/2|n2=15.0", "GUILD", ofa.sender)
    assert(not mo.C.Stats.WordEnchant(2), "half a word is not taken")
    mo.C.Comm:Receive("1N|" .. at .. "|2/2|n5=15.0", "GUILD", ofa.sender)
    assert(mo.C.Stats.WordEnchant(2) and mo.C.Stats.WordEnchant(5), "the whole word, once its parts are in")
    assert(not mo.C.Rules.ReceiveWord(ofa.sender, 9999999999, "n7=15.0") and not mo.C.Stats.WordEnchant(7), "a word stamped far ahead is not taken")
    for _, c in ipairs({ ofa, mo }) do leave(c) end
  end)

  -- (p) a whisper from a member heard on the guild channel whose full record has not come yet waits for it; the
  -- records saved by 0.5.x, all made by guild messages, are taken as heard there
  isolated({ member("Ofa", 0), member("Neo", 3), member("Mo", 3) }, function()
    local ofa = char("Ofa", 0)
    login(ofa, { version = "0.5.0", roster = { ["Mo-Forever"] = { seen = EPOCH, online = true, stats = { guid = guidOf("Mo"), level = 30 }, at = {} } } })
    tickAll(30)
    assert(rec(ofa, "Mo").ch and ofa.C.Roster:GuildSender("Mo-Forever", guidOf("Mo")) == true, "0.5.x's saved records count as heard on the guild channel")
    local neo = guidOf("Neo")
    ofa.C.Comm:Receive("1R|" .. neo .. "|0|0", "GUILD", "Neo-Forever")
    ofa.C.Comm:Receive("1F|1|1|4|guid=" .. neo .. ";gold=" .. ofa.C.Comm.b36(4242), "WHISPER", "Neo-Forever")
    assert(not (rec(ofa, "Neo") and rec(ofa, "Neo").stats.gold), "Neo's whisper waits for his record")
    ofa.C.Comm:Receive("1F|1|2|4|guid=" .. neo .. ";level=u", "GUILD", "Neo-Forever")
    assert(rec(ofa, "Neo").stats.gold == 4242 and rec(ofa, "Neo").stats.guid == neo, "and is taken once it came")
    leave(ofa)
  end)

  -- (q) the Guide's Invite for a mate whose Cute speaks under a Kstring, no name to send to: the roster's name, a plain
  -- one, instead; and the officers' busiest levels by counts per level, as by every pair
  if SEEDED then
    isolated({ member("Gil", 1), member("Vee", 3), member("Bo", 3) }, function()
      for _, g in ipairs(GUILD) do g.level = g.name == "Gil-Forever" and 30 or (g.name == "Vee-Forever" and 20 or 19) end
      local gil = newClient(charOf({ "Gil", 1, "Officer", "PALADIN", 30 }))
      local vee = newClient(charOf({ "Vee", 3, "Raider", "PRIEST", 20 }))
      local bo = newClient(charOf({ "Bo", 3, "Raider", "MAGE", 19 }, { sender = "|Kf7|k" }))
      for _, c in ipairs({ gil, vee, bo }) do login(c) end
      tickAll(60)
      openGuide(vee)
      local row
      for _, r in ipairs(vee.C.UI.lists.guide.items) do if r:IsShown() and r.invite.mate and r.invite.mate.name == "Bo" then row = r end end
      assert(row and row.invite.mate.invite == "Bo-Forever", "a Kstring sender string is no name to invite: the roster's name: " .. tostring(row and row.invite.mate.invite))
      press(row.invite)
      assert(#vee.invites == 1 and vee.invites[1] == "Bo-Forever", "the invite went to the roster's name")
      for _, c in ipairs({ gil, vee, bo }) do leave(c) end
    end)
  end
  do
    local rows, levels = {}, {}
    for i = 1, 300 do local l = 1 + (i * 37) % 60; rows[i] = { level = l }; levels[i] = l end
    table.sort(levels)
    local span, lo, best = math.max(1, 2 * yezin.C.Rules.Get("guideWindow")), nil, 0
    for _, l in ipairs(levels) do
      local n = 0
      for _, x in ipairs(levels) do if x >= l and x <= l + span - 1 then n = n + 1 end end
      if n > best then lo, best = l, n end
    end
    local pick = yezin.C.Guide.GuildPick(rows)
    assert(pick.line:find("Most members are " .. (span == 1 and tostring(lo) or (lo .. "-" .. (lo + span - 1))), 1, true), "the busiest levels, counted per level: " .. pick.line .. " (" .. lo .. ")")
  end

  -- (r) the smaller ones. With no line and no policy anywhere nothing waits; a repeat kill claimed while Guild Info
  -- cannot be read goes once it is; a claim held back as it leaves (Bosses closed meanwhile) goes to the officers;
  -- Bosses opened, a member who never met the boss gets its label and shows it; Level closed takes the others' XP
  -- samples out (their votes kept); with Dungeons closed a dungeon's who-set is not put back from the kills in it
  isolated({ member("Ofa", 0), member("Ann", 3), member("Mo", 3), member("Zed", 3) }, function()
    local ofa, ann = char("Ofa", 0), char("Ann", 3)
    login(ofa, {}); login(ann, {})
    tickAll(25)
    assert(not ann.C.Comm.holding and not (ann.env.CuteDB.policy and ann.env.CuteDB.policy.at), "with no line and no policy anywhere nothing waits, and nothing is stored")
    for _, c in ipairs({ ofa, ann }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Ann", 3), member("Mo", 3), member("Zed", 3) }, function()
    local function claimed(name) return { chars = { [name .. "-Forever"] = { counters = {}, modules = {}, claims = { [1230] = { t = EPOCH, with = {} } } } } } end
    local ann, mo = char("Ann", 3, { party = { "Mo" } }), char("Mo", 3, { party = { "Ann" } })
    -- (Guild Info a secret at login, as inside an encounter: nothing of theirs leaves but the ask)
    INFO[7] = "Welcome to <Cute>!"
    ann.infoSecret, mo.infoSecret = true, true
    login(ann, claimed("Ann")); login(mo, claimed("Mo"))
    tick(ann, 9); tick(mo, 9)
    assert(ann.C.Comm.holding, "the record still waits")
    for _, c in ipairs({ ann, mo }) do
      c.o.instance, c.o.instanceID, c.o.instName = "party", 36, "The Deadmines"
      fire(c, "PLAYER_ENTERING_WORLD", false, false)
      fire(c, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    end
    tickAll(20)
    assert(ann.C.Comm.holding and msgs(ann, "1K") == 0, "the claim waits with the record")
    for _, c in ipairs({ ann, mo }) do c.infoSecret = false; fire(c, "GUILD_ROSTER_UPDATE") end
    tickAll(20)
    local sent = false
    for _, m in ipairs(ann.sent) do if m.msg:find("^1K|1230@") and not m.msg:find("1230@" .. ann.C.Comm.b36(EPOCH) .. ":", 1, true) then sent = true end end
    assert(sent and ann.C.Rules.Corroborated(1230, mo.o.guid), "the repeat kill claimed during the wait went as it ended, and Mo's names Ann back")
    for _, c in ipairs({ ann, mo }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Ann", 3), member("Mo", 3), member("Zed", 3) }, function()
    local ofa, ann, mo, zed = char("Ofa", 0), char("Ann", 3, { party = { "Mo" } }), char("Mo", 3, { party = { "Ann" } }), char("Zed", 3)
    login(ofa, pol(true, { gc_bosses = "self" })); login(ann, pol(nil, { gc_bosses = "self" })); login(mo, pol(nil, { gc_bosses = "self" })); login(zed, pol(nil, { gc_bosses = "self" }))
    tickAll(45)
    for _, c in ipairs({ ann, mo }) do
      c.o.instance, c.o.instanceID, c.o.instName = "party", 36, "The Deadmines"
      fire(c, "PLAYER_ENTERING_WORLD", false, false)
      fire(c, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    end
    tickAll(10)
    assert(not zed.C.Stats.byId.e1230 or not rec(zed, "Ann").stats.e1230, "Bosses kept: Zed has none of it")
    ofa.C.Policy:Set("gc_bosses", "all")
    ofa.C.Comm:SendPolicy()
    tickAll(10)
    assert(rec(zed, "Ann").stats.e1230 == 1 and zed.C.Stats.byId.e1230 and zed.env.CuteDB.known.labels.e1230, "Bosses opened: Zed gets the kill and its label, and shows it")
    -- a kill claim waiting behind the throttle while the officers close Bosses again goes to them, whispered
    ann.throttle = 3
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    tick(ann, 0.5)
    ofa.C.Policy:Set("gc_bosses", "self")
    ofa.C.Comm:SendPolicy()
    tickAll(20)
    local whispered = false
    for _, m in ipairs(ann.sent) do if m.channel == "WHISPER" and m.target == ofa.sender and m.msg:find("^1K|1230@") then whispered = true end end
    assert(whispered, "the claim held back went to the officer")
    for _, c in ipairs({ ofa, ann, mo, zed }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
    local mo = guidOf("Mo")
    local mia = char("Mia", 3)
    login(mia, { known = { xp = { [30] = { [mo] = 9999 } } } })
    tickAll(40)
    mia.env.CuteDB.policy = { vis = { level = "self" }, by = "Ofa-Forever", rank = 0, at = EPOCH, threshold = 1 }
    mia.C.Policy:Purge()
    local k = mia.env.CuteDB.known
    assert(not k.xp[30][mo] and k.xpKept[30][9999] == 1, "Level closed: Mo's XP sample out of what Mia's client learned, its vote kept")
    if SEEDED then
      mia.env.CuteDB.policy = { vis = { gc_dungeons = "self" }, by = "Ofa-Forever", rank = 0, at = EPOCH, threshold = 1 }
      k.kills = { [1230] = { [mo] = true } }
      mia.env.CuteDB.roster["Mo-Forever"] = { seen = EPOCH, online = true, ch = true, stats = { guid = mo, e1230 = 1 }, at = {} }
      mia.C.Roster:Identity()
      mia.C.Rules:Rebuild()
      local d = mia.C.Rules.Model().dungeons[36]
      assert(d and not (d.who or {})[mo] and mia.C.Rules.Model().bosses[1230].who[mo], "Dungeons closed: Mo's kill names the boss, and puts him back in the dungeon's who-set no more")
    end
    leave(mia)
    said[#said + 1] = "the smaller ones"
  end)

  -- (o) a member's window: no leader on an Only-you card, the Settings boxes ticked by their labels
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
    local ofa, mia, mo = char("Ofa", 0), char("Mia", 3), char("Mo", 3)
    login(ofa, pol(true, { whispers = "self" })); login(mia, pol(nil, { whispers = "self" })); login(mo, pol(nil, { whispers = "self" }))
    tickAll(45)
    mia.env.CuteDB.settings.shame = nil
    mia.C.UI:Open("shame")
    local card
    for _, cd in ipairs(mia.C.UI.cards.items) do if cd:IsShown() and cd.def and cd.def.id == "whispers" then card = cd end end
    assert(card and card.leader:GetText():find("only the officers see who leads", 1, true) and #card.top == 0, "the member's card names no leader: " .. tostring(card and card.leader:GetText()))
    assert(tipOf(card):find("Only the officers see who leads", 1, true), "and its tooltip says why")
    check(mia.C.UI.frame, "member hall of shame, a card kept to the officers")
    mia.C.UI:Open("settings", "modules")
    -- (0.6.1: the row is the button, the box a visual inside it, so a click anywhere on the row ticks it; nothing
    -- leans on a hit rect widened over the label, which the live client's Modules boxes never took)
    local box = checkBox(mia, function(fr) return fr.label and fr.label:GetText() == "Guide" end)
    assert(box and box.checkRow and box.__kind == "Button" and not box.__hit and box.box.__kind == "Frame" and not box.box.__mouse, "the Guide's row is a button, its box a frame inside it, no hit-rect insets")
    GEN = GEN + 1
    local rr, lr, br = rectOf(box), rectOf(box.label), rectOf(box.box)
    assert(rr and lr and br and rr.l <= br.l and br.r <= lr.l and lr.r <= rr.r and rr.r - rr.l >= 300 and rr.t - rr.b == 20 and rr.t >= br.t and br.b >= rr.b,
      string.format("the row spans its box and its label: row %d-%d, box %d-%d, label %d-%d", rr.l, rr.r, br.l, br.r, lr.l, lr.r))
    -- every check in Settings is such a row: none left with a hit rect
    for _, fr in ipairs(mia.frames) do assert(not fr.__hit, "a widget with hit-rect insets: " .. tostring(fr.__kind) .. " '" .. tostring(fr.label and fr.label:GetText()) .. "'") end
    mia.C.UI:Open("settings", "general")
    local n = 0
    for _, fr in ipairs(mia.frames) do if fr.checkRow and fr:IsVisible() then n = n + 1 end end
    assert(n == 8, "General: four check rows and the four Role choices, all rows: " .. n)
    for _, c in ipairs({ ofa, mia, mo }) do leave(c) end
  end)
  print("the third round: " .. table.concat(said, "; "))
end

-- 46: what the fourth round of review found (0.6.0), each case one that failed before its fix (the namesake whose name
-- reads in no form is in scenario 44, the ding a lagging roster has not caught up with in 45(l)). (a) Closing Bosses or
-- Reputation takes the other members' GUIDs out of the labels' voices and a boss's loot's first bringers, on a
-- member's client and on an officer's made a member again, and a member's client takes no label of a category the
-- officers keep. (b) A member made an officer gets what does not change, whichever client's roster sees it first. (c)
-- Whispers that came before a slow roster are judged by the newest policy. (d) A kill claim names its group: it goes
-- the way of Grouped with too. (e) A Ready that counted a gap the officers have since closed is not kept. (f) One
-- account in two guilds: each guild's policy its own. (g) One copy's junk loot keeps nobody's out, and (h) its kill
-- claims switch off nobody's corroboration, your own kill's least of all. (i) An officer's file is not purged by a
-- roster read that lacks her, nor by a threshold the officers changed while she was away. (j) A GUID the roster gives
-- nobody is no voice. (k) The seed's names stand over one member's word on the Statistics page. (l) Two namesakes under
-- one sender string: nobody marked. (m) A busy queue lets nothing closed out. (n) Made-up statistics categories in one
-- copy's policies route nothing, fill nothing and fold into no officer's policy. (o) A delta waiting behind a full
-- one takes the next change.
-- (p) An officer's ask a /reload repeats gets the whispered part alone. (q) The officers' word: a long one said once,
-- cut to the 64 messages a receiver takes, its enchant slots kept. (r) Saved statistics wait for the probe's last
-- word. (s) One copy's burst before the roster loads pushes no officer's answer out. (t) Level closed and opened again
-- counts a member once. (u) No officer lowers the officer ranks past their own rank. (v) A member's ranking of a stat
-- the officers keep numbers nobody, and (w) a change in Settings goes to the guild on its own. (x) The smaller ones:
-- two officers' policies of one second end every client on the same one, a whisper makes no record, a 0.5.x officer's
-- file is not purged by its member alt, a suspect's reason keeps no value the officers keep
collectgarbage()
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  -- (each client its own copy of the list: one client's change is no other's)
  local function pol(mine, vis, at, thr)
    local copy = {}
    for k, v in pairs(vis or {}) do copy[k] = v end
    return { policy = { vis = copy, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = thr or 1 } }
  end
  local function rec(c, who) return c.env.CuteDB.roster[who .. "-Forever"] end
  local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end return n end
  local function g(name) for _, m in ipairs(GUILD) do if m.name == name .. "-Forever" then return m end end end
  local function enter(c, inst, name, mates)
    c.o.party = mates
    c.o.instance, c.o.instanceID, c.o.instName = "party", inst, name
    fire(c, "PLAYER_ENTERING_WORLD", false, false)
  end
  local said = {}

  -- (a) the traces of the labels and the loot
  isolated({ member("Ofa", 0), member("Ann", 3), member("Mo", 2), member("Zed", 3) }, function()
    local ofa, ann, mo, zed = char("Ofa", 0), char("Ann", 3), char("Mo", 2), char("Zed", 3)
    local ofaDb, zedDb, moDb = pol(true), pol(), pol()
    login(ofa, ofaDb); login(ann, pol()); login(mo, moDb); login(zed, zedDb)
    tickAll(30)
    enter(ann, 36, "The Deadmines", { "Mo" }); enter(mo, 36, "The Deadmines", { "Ann" })
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {}); fire(mo, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    for _, c in ipairs({ ann, mo }) do c.lootWindow = { { 50001, 3 } }; fire(c, "LOOT_OPENED", false, false); c.lootWindow = nil end
    tickAll(120)
    local k = zedDb.known
    local function others(t) local n = 0; for gg in pairs(t or {}) do if gg ~= zed.o.guid then n = n + 1 end end return n end
    local function voiced(prefix) local n = 0; for id, v in pairs(k.voice or {}) do if id:sub(1, 1) == prefix then n = n + others(v) end end return n end
    assert(voiced("e") > 0 and voiced("f") > 0 and k.loot[1230] and k.loot[1230].from, "before: Zed's client heard the others' labels and loot, by GUID")
    ofa.C.Policy:Set("gc_bosses", "self"); ofa.C.Policy:Set("gc_rep", "self")
    ofa.C.Comm:SendPolicy()
    tickAll(5)
    assert(voiced("e") == 0 and voiced("f") == 0, "Bosses and Reputation closed: no other member's GUID among the labels' voices")
    assert(k.loot[1230].from == nil and k.lootFrom == nil, "nor as who brought a boss's loot first")
    -- (the count of labels each member said goes with them: no more than the voices left)
    for gg, n in pairs(k.vn or {}) do
      local left = 0
      for _, v in pairs(k.voice or {}) do if v[gg] then left = left + 1 end end
      assert(n <= left, "the count of labels each said goes with them: " .. n .. " of " .. left)
    end
    assert(zed.C.Stats.byId.e1230 and zed.C.Stats.byId.e1230.label == "Rhahk'Zor", "what was learned stays")
    -- a label from a 0.5.x client on GUILD now: no voice taken
    zed.C.Comm:Receive("1L|e1230:36=Rhahk'Zor;f72=Stormwind", "GUILD", ann.sender)
    assert(voiced("e") == 0 and voiced("f") == 0, "a member's client takes no label of a category the officers keep")
    -- Mo made an officer (threshold 2) hears a member's boss whispered; made a member again, his file keeps no trace
    ofa.C.Policy:SetThreshold(2); ofa.C.Comm:SendPolicy()
    tickAll(5)
    assert(mo.C.Roster:MeOfficer(), "Mo an officer")
    zed.C.Stats.Label("e1999", "Zed's Boss", true, 36)
    zed.C.Comm:LabelSoon("e1999")
    tickAll(5)
    assert(moDb.known.voice and moDb.known.voice.e1999 and moDb.known.voice.e1999[zed.o.guid], "Mo, an officer, holds Zed's label of his boss by his GUID")
    ofa.C.Policy:SetThreshold(1); ofa.C.Comm:SendPolicy()
    tickAll(5)
    assert(not mo.C.Roster:MeOfficer() and not (moDb.known.voice.e1999 and moDb.known.voice.e1999[zed.o.guid]), "a member again: Zed's GUID out of the voices Mo holds")
    for _, c in ipairs({ ofa, ann, mo, zed }) do leave(c) end
    said[#said + 1] = "closing takes the voices out"
  end)
  collectgarbage()

  -- (b) promoted later in the session, either roster first
  for _, order in ipairs({ "the new officer's roster first", "the others' first" }) do
    isolated({ member("Ofa", 0), member("Mo", 3), member("Mia", 3) }, function()
      local vis = { gc130 = "self" }
      local ofa, mo, mia = char("Ofa", 0), char("Mo", 3), char("Mia", 3, { money = 777777, withStats = true })
      login(ofa, pol(true, vis)); login(mo, pol(nil, vis)); login(mia, pol(nil, vis))
      tickAll(200)
      assert(not mo.C.Roster:MeOfficer() and rec(mo, "Mia").stats.gold == nil, "Mo a member")
      g("Mo").rank = 1
      if order == "the others' first" then fire(mia, "GUILD_ROSTER_UPDATE"); fire(ofa, "GUILD_ROSTER_UPDATE"); tickAll(3) end
      fire(mo, "GUILD_ROSTER_UPDATE")
      tickAll(2)
      fire(mia, "GUILD_ROSTER_UPDATE"); fire(ofa, "GUILD_ROSTER_UPDATE")
      tickAll(100)
      local e = rec(mo, "Mia")
      assert(mo.C.Roster:MeOfficer() and e.stats.gold == 777777 and e.stats.empty_slots and e.stats.g2001 == 1234,
        order .. ": Mo has what does not change, the Kills statistic too: " .. tostring(e.stats.gold) .. " " .. tostring(e.stats.g2001))
      for _, c in ipairs({ ofa, mo, mia }) do leave(c) end
    end)
  end
  said[#said + 1] = "a promotion reaches the new officer"
  collectgarbage()

  -- (c) a slow roster, the threshold raised while Mo was away
  isolated({ member("Ofa", 0), member("Mo", 2), member("Mia", 3) }, function()
    local NEW = EPOCH + 500
    local ofa, mia = char("Ofa", 0), char("Mia", 3, { money = 777777 })
    login(ofa, pol(true, {}, NEW, 2)); login(mia, pol(nil, {}, NEW, 2))
    tickAll(45)
    local mo = char("Mo", 2)
    local real, slow = mo.env.C_Club.GetClubMembers, true
    mo.env.C_Club.GetClubMembers = function(...) if slow then return {} end return real(...) end
    login(mo, pol(nil, {}, EPOCH + 100, 1))
    -- (the hello's ask waits for the roster; /cute resend asks at once)
    tickAll(10)
    mo.C.Comm:Ask()
    tickAll(30)
    assert(#mo.C.Comm.early > 0, "Mia's whispers wait for Mo's roster")
    slow = false
    fire(mo, "GUILD_ROSTER_UPDATE")
    -- (Guild Info empty: no line from a read ten seconds on; a whisper dropped before it is asked for again then)
    tickAll(30)
    assert(mo.C.Roster:MeOfficer() and rec(mo, "Mia").stats.gold == 777777, "judged by the newest policy, which makes Mo an officer: kept")
    for _, c in ipairs({ ofa, mo, mia }) do leave(c) end
    said[#said + 1] = "early whispers judged by the newest policy"
  end)

  -- (d) a kill claim with Grouped with kept to the officers
  isolated({ member("Ofa", 0), member("Ann", 3), member("Mo", 3), member("Cy", 3) }, function()
    local ofa, ann, mo, cy = char("Ofa", 0), char("Ann", 3), char("Mo", 3), char("Cy", 3)
    local ofaDb = pol(true, { group = "self" })
    login(ofa, ofaDb); login(ann, pol(nil, { group = "self" })); login(mo, pol(nil, { group = "self" })); login(cy, pol(nil, { group = "self" }))
    tickAll(45)
    JUDGE = judgeBy(ofaDb)
    cy.got = {}
    enter(ann, 36, "The Deadmines", { "Mo" }); enter(mo, 36, "The Deadmines", { "Ann" })
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {}); fire(mo, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    tickAll(10)
    local claims = 0
    for _, m in ipairs(cy.got) do if m.msg:sub(1, 2) == "1K" then claims = claims + 1 end end
    assert(claims == 0 and #leakedTo(cy) == 0, "no claim naming the group reached Cy: " .. claims .. " " .. table.concat(leakedTo(cy), ", "))
    assert(ofa.C.Rules.Corroborated(1230, ann.o.guid) and ofa.C.Rules.Corroborated(1230, mo.o.guid), "the officers' clients weigh them")
    assert(cy.C.Comm:ReceiveClaims("1230@" .. cy.C.Comm.b36(EPOCH) .. ":" .. mo.o.guid:match("([^%-]+)$"), ann.sender) == 0, "and Cy's passes one on GUILD by")
    JUDGE = nil
    for _, c in ipairs({ ofa, ann, mo, cy }) do leave(c) end
    said[#said + 1] = "claims go as Grouped with does"
  end)
  collectgarbage()

  -- (e) a Ready that counted a gap the officers have since closed
  isolated({ member("Ofa", 0), member("Bo", 3), member("Cy", 3) }, function()
    local vis = { empty_slots = "all", unenchanted = "all" }
    local ofa, bo, cy = char("Ofa", 0), char("Bo", 3, { items = { [1] = "item:1234:0" } }), char("Cy", 3)
    login(ofa, pol(true, vis)); login(bo, pol(nil, vis)); login(cy, pol(nil, vis))
    tickAll(45)
    assert(rec(cy, "Bo").stats.ready ~= nil and rec(cy, "Bo").stats.empty_slots, "Cy holds Bo's Ready, which counts his empty slots")
    leave(bo)
    ofa.C.Policy:Set("empty_slots", "self"); ofa.C.Policy:Set("unenchanted", "self")
    ofa.C.Comm:SendPolicy()
    tickAll(5)
    assert(rec(cy, "Bo").stats.ready == nil and rec(cy, "Bo").stats.empty_slots == nil, "closed: his Ready goes with them, until his next read")
    for _, c in ipairs({ ofa, cy }) do leave(c) end
    said[#said + 1] = "a Ready counting a closed gap goes"
  end)

  -- (f) one account in two guilds
  local account = {}
  local function club8(c)
    local cc = c.env.C_Club
    local gm, gi, gs = cc.GetClubMembers, cc.GetMemberInfo, cc.GetMemberInfoForSelf
    cc.GetGuildClubId = function() return c.inGuild and 8 or nil end
    cc.GetClubMembers = function(id) return gm(id == 8 and 7 or id) end
    cc.GetMemberInfo = function(id, i) return gi(id == 8 and 7 or id, i) end
    cc.GetMemberInfoForSelf = function(id) return gs(id == 8 and 7 or id) end
  end
  isolated({ member("Xo", 0), member("Xalt", 3) }, function()
    local xo, xalt = char("Xo", 0), char("Xalt", 3)
    club8(xo); club8(xalt)
    login(xo, { policy = { vis = { gold = "all" }, by = "Xo-Forever", mine = true, rank = 0, at = EPOCH + 900, threshold = 2 } })
    login(xalt, account)
    tickAll(30)
    assert(account.policy and account.policy.by == "Xo-Forever", "guild X's policy held on the account")
    for _, c in ipairs({ xo, xalt }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Mo", 3), member("Mia", 3) }, function()
    local ofaDb = pol(true, {}, EPOCH + 100)
    local ofa, mo = char("Ofa", 0), char("Mo", 3)
    JUDGE = judgeBy(ofaDb)
    login(ofa, ofaDb); login(mo, pol(nil, {}, EPOCH + 100))
    tickAll(30)
    mo.got = {}
    local mia = char("Mia", 3, { money = 777777 })
    login(mia, account)
    tickAll(30)
    assert(#leakedTo(mo) == 0 and mia.C.Policy:Route("gold") == "self" and mia.C.Policy:Threshold() == 1, "<Cute>'s own policy: " .. table.concat(leakedTo(mo), ", "))
    assert(account.policies and account.policies["8"] and account.policies["8"].policy.by == "Xo-Forever", "guild X's kept for its characters")
    JUDGE = nil
    for _, c in ipairs({ ofa, mo, mia }) do leave(c) end
    said[#said + 1] = "each guild its own policy"
  end)
  collectgarbage()

  -- (g) junk loot, (h) junk claims
  isolated({ member("Ofa", 0), member("Mal", 3), member("Ann", 3), member("Ben", 3), member("Cid", 3) }, function()
    local cid = char("Cid", 3)
    login(cid)
    tickAll(30)
    local CC, K = cid.C, cid.env.CuteDB.known
    CC.Comm:Receive("1L|e1230:36=Rhahk'Zor", "GUILD", "Ann-Forever")
    local a, b = {}, {}
    for i = 1, 24 do a[#a + 1] = CC.Comm.b36(900000 + i) end
    for i = 25, 40 do b[#b + 1] = CC.Comm.b36(900000 + i) end
    CC.Comm:Receive("1L|l1230=" .. table.concat(a, "."), "GUILD", "Mal-Forever")
    CC.Comm:Receive("1L|l1230=" .. table.concat(b, "."), "GUILD", "Mal-Forever")
    assert(count(K.loot[1230].items) <= 24, "one member's items, 24 a boss at most: " .. count(K.loot[1230].items))
    CC.Comm:ReceiveLabels("l1230=" .. CC.Comm.b36(55555), "Ann-Forever")
    CC.Comm:ReceiveLabels("l1230=" .. CC.Comm.b36(55555), "Ben-Forever")
    CC.Rules:Rebuild()
    local item = K.loot[1230].items[55555]
    assert(item and count(K.loot[1230].by[55555]) == 2 and (not SEEDED or CC.Rules.Model().bosses[1230].loot[55555] == "seen"), "Ann's and Ben's item kept, two voices")
    -- a forger's claims: 120 messages of 34
    local taken = 0
    for i = 1, 120 do
      local p = {}
      for j = 1, 34 do p[#p + 1] = ((i - 1) * 34 + j) .. "@1:" end
      taken = taken + CC.Comm:ReceiveClaims(table.concat(p, ";"), "Mal-Forever")
    end
    local t = EPOCH + cid.clock
    CC.Rules.Claim(guidOf("Ann"), 1230, t, { [guidOf("Ben")] = true })
    CC.Rules.Claim(guidOf("Ben"), 1230, t, { [guidOf("Ann")] = true })
    CC.Rules.Claim(cid.o.guid, 1236, t, { [guidOf("Ann")] = true })
    CC.Rules.Claim(guidOf("Ann"), 1236, t, { [cid.o.guid] = true })
    assert(CC.Rules.Corroborated(1230, guidOf("Ann")) and CC.Rules.Corroborated(1236, cid.o.guid), "after 4080 forged claims, a kill is still corroborated, your own too")
    -- an established guild's first kills, told again at every login: a hundred members, forty bosses each
    for m = 1, 100 do for bb = 1, 40 do CC.Rules.Claim(string.format("Player-4242-1%07X", m), 2000 + bb, EPOCH, {}) end end
    CC.Rules.Claim(guidOf("Ann"), 1238, t, { [guidOf("Ben")] = true })
    CC.Rules.Claim(guidOf("Ben"), 1238, t, { [guidOf("Ann")] = true })
    assert(CC.Rules.Corroborated(1238, guidOf("Ann")), "and after four thousand honest ones")
    leave(cid)
    said[#said + 1] = "junk loot and claims crowd nothing out"
  end)
  collectgarbage()

  -- (i) an officer's file: one read that lacks her; a threshold raised while she was away
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
    local db = pol()
    local ofa, mia, mo = char("Ofa", 0), char("Mia", 3, { money = 777777 }), char("Mo", 3)
    login(ofa, db); login(mia, pol()); login(mo, pol())
    tickAll(60)
    leave(ofa); leave(mia)
    g("Mia").online = false
    local ofa2 = char("Ofa", 0)
    local hide = true
    local real = ofa2.env.C_Club.GetMemberInfo
    ofa2.env.C_Club.GetMemberInfo = function(id, i) local r = real(id, i); if hide and r and r.guid == ofa2.o.guid then return nil end return r end
    login(ofa2, db)
    tickAll(40)
    hide = false
    fire(ofa2, "GUILD_ROSTER_UPDATE")
    tickAll(5)
    assert(ofa2.C.Roster:MeOfficer() and db.roster["Mia-Forever"].stats.gold == 777777, "a roster read without her deleted nothing")
    for _, c in ipairs({ ofa2, mo }) do leave(c) end
  end)
  isolated({ member("Ofb", 0), member("Ofa", 1), member("Mia", 3), member("Mo", 3) }, function()
    local db = { policy = { vis = {}, by = "Ofb-Forever", rank = 0, at = EPOCH, threshold = 1 } }
    local ofa, mia, mo = char("Ofa", 1), char("Mia", 3, { money = 777777 }), char("Mo", 3)
    login(ofa, db); login(mia, pol()); login(mo, pol())
    tickAll(60)
    leave(ofa); leave(mia)
    g("Mia").online = false
    g("Ofa").rank = 2
    local ofb = char("Ofb", 0)
    login(ofb, { policy = { vis = {}, by = "Ofb-Forever", mine = true, rank = 0, at = EPOCH + 100, threshold = 2 } })
    tickAll(10)
    local ofa2 = char("Ofa", 2)
    login(ofa2, db)
    tickAll(40)
    assert(ofa2.C.Roster:MeOfficer() and db.roster["Mia-Forever"].stats.gold == 777777, "the threshold the officers raised meanwhile keeps her an officer: nothing deleted")
    for _, c in ipairs({ ofa2, ofb, mo }) do leave(c) end
    said[#said + 1] = "an officer's file kept"
  end)
  collectgarbage()

  -- (j) made-up GUIDs where the roster cannot vouch
  do
    local function gm(name, guid, rank) return { name = name, guid = guid, rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true } end
    isolated({ gm("Helga", guidOf("Helga Xan"), 3), gm("Helga", guidOf("Helga Yin"), 3), gm("Ofa", guidOf("Ofa"), 0) }, function()
      local ofa = newClient(charOf({ "Ofa", 0, "", "MAGE", 30 }, { surname = "Stone", sender = "Ofa Stone" }))
      login(ofa)
      tickAll(20)
      for _, fake in ipairs({ "Player-4242-0BAD0001", "Player-4242-0BAD0002" }) do
        ofa.C.Comm:Receive("1F|1|1|4|guid=" .. fake .. ";ench_kinds=5:4.1:2564;level=u", "GUILD", "Helga Yin")
        ofa.C.Comm:Receive("1L|i777:p=Fake Keep", "GUILD", "Helga Yin")
        ofa.C.Roster:Refresh(); ofa.C.Roster:Refresh()
      end
      assert(not ofa.C.Stats.EnchantLearned(5) and not ofa.C.Stats.Sure("i777"), "two made-up GUIDs are no two voices")
      leave(ofa)
      said[#said + 1] = "a made-up GUID no voice"
    end)
  end

  -- (k) the seed's names over one member's word
  if SEEDED then
    isolated({ member("Ofa", 0), member("Mal", 3), member("Ann", 3), member("Cid", 3) }, function()
      local cid = char("Cid", 3)
      login(cid)
      tickAll(30)
      cid.C.Comm:Receive("1F|1|1|4|guid=" .. guidOf("Ann") .. ";level=u", "GUILD", "Ann-Forever")
      cid.C.Comm:Receive("1L|e1230:99=Mal was here;i36:p=Mal Town", "GUILD", "Mal-Forever")
      cid.C.Comm:Receive("1D|4|e1230=1;i36=1", "GUILD", "Ann-Forever")
      local S = cid.C.Stats
      assert(S.byId.e1230 and S.byId.e1230.label == "Rhahk'Zor" and S.byId.i36 and S.byId.i36.label == "The Deadmines" and S.InstOf(1230) == 36,
        "the Statistics page names them as the seed does: " .. tostring(S.byId.e1230 and S.byId.e1230.label))
      leave(cid)
      said[#said + 1] = "the seed's names stand"
    end)
  end

  -- (l) two namesakes under one sender string
  do
    local function gm(name, guid, rank) return { name = name, guid = guid, rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true } end
    isolated({ gm("Ann Lee", guidOf("Ann"), 3), gm("Helga Xan", guidOf("Helga Xan"), 1), gm("Helga Yin", guidOf("Helga Yin"), 3) }, function()
      local ann = newClient(charOf({ "Ann", 3, "", "MAGE", 30 }, { surname = "Lee", sender = "Ann-Forever" }))
      login(ann)
      tickAll(10)
      ann.C.Comm:Receive("1F|1|1|4|guid=" .. guidOf("Helga Xan") .. ";level=u;deaths=z", "GUILD", "Helga-Forever")
      ann.C.Comm:Receive("1F|1|1|4|guid=" .. guidOf("Helga Yin") .. ";level=u;deaths=1", "GUILD", "Helga-Forever")
      ann.C.Comm:Receive("1D|4|deaths=2", "GUILD", "Helga-Forever")
      local e = ann.env.CuteDB.roster["Helga-Forever"]
      assert(e and not e.suspect and not e.stats.guid, "two namesakes under one sender string: nobody marked, no GUID kept: " .. tostring(e and e.suspect and e.suspect.why))
      leave(ann)
      said[#said + 1] = "namesakes marked by nobody"
    end)
  end
  collectgarbage()

  -- (m) the policy ahead of a busy queue
  isolated({ member("Ofa", 0), member("Mo", 3), member("Ann", 3), member("Mia", 3) }, function()
    local OLD, NEW = EPOCH, EPOCH + 500
    local function db(at, mine)
      local vis = at == NEW and { gold = "self", deaths = "self", enchanted = "self" } or { gold = "all", unenchanted = "all", empty_slots = "all" }
      return { policy = { vis = vis, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at, threshold = 1 } }
    end
    local ofa, mo, ann = char("Ofa", 0), char("Mo", 3), char("Ann", 3)
    local ofaDb = db(NEW, true)
    -- (the guild's text long, Cute's line after it)
    INFO[7] = ("Welcome to <Cute>! Raids Tue and Thu at 20:00. "):rep(9) .. "\n" .. infoLine(ofaDb.policy)
    JUDGE = judgeBy(ofaDb)
    login(ofa, ofaDb); login(mo, db(NEW)); login(ann, db(NEW))
    tickAll(45)
    for _, c in ipairs({ ofa, mo, ann }) do for i = 1, 40 do c.C.Comm.Queue({ msg = "1Z|" .. i }) end end
    mo.got = {}
    local mia = char("Mia", 3, { money = 777777 })
    mia.clock = mo.clock
    login(mia, db(OLD))
    tickAll(60)
    assert(#leakedTo(mo) == 0 and mia.C.Policy:Holds(), "forty messages waiting on every holder: still nothing closed on GUILD: " .. table.concat(leakedTo(mo), ", "))
    JUDGE = nil
    for _, c in ipairs({ ofa, mo, ann, mia }) do leave(c) end
    said[#said + 1] = "the policy first"
  end)

  -- (n) made-up statistics categories in one copy's policies: they crowd out no member's answer and fill nothing
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3), member("Mal", 3) }, function()
    local NEW = EPOCH + 500
    INFO[7] = ("Welcome to <Cute>! Raids Tue and Thu at 20:00. "):rep(9) .. "\n" .. infoLine({ vis = { gold = "self", zone = "self" } })
    local mia = char("Mia", 3, { money = 777777 })
    login(mia, pol(nil, { gold = "all" }, EPOCH))
    tickAll(40)
    for r = 1, 20 do
      local p = {}
      for i = 1, 20 do p[#p + 1] = "-" .. (100000 + r * 100 + i) end
      mia.C.Comm:Receive(string.format("1P|%d|1|1/1|%s", EPOCH + mia.clock, table.concat(p, ";")), "GUILD", "Mal-Forever")
    end
    tickAll(30)
    assert(mia.C.Policy:Holds() and mia.C.Policy:Settled() and mia.C.Policy:Route("gold") == "self", "four hundred made-up categories from a member route nothing: the line does")
    local n = 0
    for id in pairs(mia.env.CuteDB.policy.vis) do if id:match("^gc1%d%d%d%d%d$") then n = n + 1 end end
    assert(n == 0, "and fill nothing: " .. n)
    leave(mia)
  end)
  isolated({ member("Ofa", 0), member("Mal", 3), member("Zed", 3) }, function()
    local ofa, zed = char("Ofa", 0, { withStats = true }), char("Zed", 3)
    login(ofa, pol(true, {}, EPOCH)); login(zed, pol(nil, {}, EPOCH))
    tickAll(30)
    local p = {}
    for i = 1, 400 do p[#p + 1] = "-" .. (1000 + i) end
    for i = 1, #p, 20 do ofa.C.Comm:Receive(string.format("1P|%d|1|%d/20|%s", EPOCH + ofa.clock, (i + 19) / 20, table.concat(p, ";", i, math.min(#p, i + 19))), "GUILD", "Mal-Forever") end
    ofa.C.Policy:Set("level", "all")
    local at, thr, parts = ofa.C.Policy:Parts()
    local junk = 0
    for id in pairs(ofa.env.CuteDB.policy.vis) do if id:match("^gc1%d%d%d$") then junk = junk + 1 end end
    assert(junk == 0 and #parts < 60, "an officer's change folds no made-up category in: " .. junk .. " " .. #parts)
    for _, c in ipairs({ ofa, zed }) do leave(c) end
    said[#said + 1] = "made-up categories fill nothing"
  end)
  collectgarbage()

  -- (o) a delta waiting behind a full one
  isolated({ member("Ofa", 0), member("Mia", 3) }, function()
    local ofa, mia = char("Ofa", 0), char("Mia", 3)
    login(ofa, pol(true)); login(mia, pol())
    tickAll(150)
    local MC = mia.C.Comm
    for i = 1, 40 do MC.Queue({ msg = "1Z|" .. i }) end
    local n = 0
    for _, def in ipairs(mia.C.Stats.list) do
      if n < 40 and def.kind == "int" and not def.slow and not def.hidden and not def.with and def.cat ~= "game" and def.cat ~= "found" and def.id ~= "deaths" and mia.C.Policy:Route(def.id) == "all" then
        n = n + 1
        mia.C.Sample.values[def.id] = 900000 + n
        mia.C.Sample.dirty[def.id] = true
      end
    end
    MC:Changed()
    for _ = 1, 30 do mia.C.Sample:Bump("deaths"); tickAll(1) end
    local waiting = 0
    for _, e in ipairs(MC.out) do if not e.target and type(e.msg) == "string" and e.msg:sub(1, 3) == "1D|" and e.msg:find("deaths=", 1, true) then waiting = waiting + 1 end end
    assert(waiting <= 1, "thirty deaths a second apart wait in one delta: " .. waiting)
    for _, c in ipairs({ ofa, mia }) do leave(c) end
    said[#said + 1] = "a full delta no line"
  end)

  -- (p) an officer's asks a /reload repeats
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
    local ofa, mia, mo = char("Ofa", 0), char("Mia", 3, { withStats = true }), char("Mo", 3)
    login(ofa, pol(true)); login(mia, pol()); login(mo, pol())
    tickAll(200)
    -- (one ask, its answers over; then two more within ASK_AGAIN, as /reloads would)
    local guild, whispered = {}, {}
    for round, wait in ipairs({ 95, 75, 95 }) do
      local s = #mia.sent
      ofa.C.Comm:Ask()
      tickAll(wait)
      guild[round], whispered[round] = 0, 0
      for i = s + 1, #mia.sent do
        local m = mia.sent[i]
        if m.channel == "GUILD" and (m.msg:sub(1, 2) == "1F" or m.msg:sub(1, 2) == "1L") then guild[round] = guild[round] + 1 end
        if m.channel == "WHISPER" then whispered[round] = whispered[round] + 1 end
      end
    end
    assert(guild[1] > 0 and guild[2] + guild[3] == 0 and whispered[2] + whispered[3] > 0,
      "the officer's repeated asks get the whispered part alone: " .. table.concat(guild, "/") .. " on GUILD, " .. table.concat(whispered, "/") .. " whispered")
    for _, c in ipairs({ ofa, mia, mo }) do leave(c) end
    said[#said + 1] = "an officer's repeated ask whispered alone"
  end)
  collectgarbage()

  -- (q) the officers' word: long, cut, said once (a guild with a line: the officers' clients hold the policy at the
  -- first read, so the first word goes as timed, a second or so after the records)
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mo", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, ofb, mo = char("Ofa", 0), char("Ofb", 1), char("Mo", 3)
    local function stub(c)
      c.C.Rules.WordParts = function()
        local out = { "n2=15.0" }
        for i = 1, 401 do out[#out + 1] = "b" .. (5000 + i) .. ":36:s=" .. string.rep("Boss", 13) .. i end
        return out
      end
    end
    stub(ofa); stub(ofb)
    login(ofa, pol(true)); login(ofb, pol()); login(mo, pol())
    tickAll(200)
    local words = { 0, 0 }
    for i, c in ipairs({ ofa, ofb }) do for _, m in ipairs(c.sent) do if m.msg:sub(1, 2) == "1N" then words[i] = words[i] + 1 end end end
    assert(words[1] + words[2] <= 64 + 8 and mo.C.Stats.WordEnchant(2), "a word past 64 messages cut to what a receiver takes, said once, its slot kept: " .. words[1] .. " and " .. words[2])
    for _, c in ipairs({ ofa, ofb, mo }) do leave(c) end
    said[#said + 1] = "the word said once, cut to fit"
  end)
  collectgarbage()

  -- (r) saved statistics while the probe is pending
  isolated({ member("Ofa", 0), member("Zed", 3), member("Yu", 3) }, function()
    local yu = char("Yu", 3, { withStats = true })
    yu.statsEmpty = true
    local db = pol(nil, { gc130 = "self" })
    db.roster = { ["Zed-Forever"] = { seen = EPOCH, online = true, ch = true, stats = { guid = guidOf("Zed"), level = 30, g2007 = 17, g2001 = 99 }, at = {} } }
    login(yu, db)
    tickAll(40)
    assert(yu.C.Roster.wasOfficer == false and db.roster["Zed-Forever"].stats.g2007 == 17, "a Deaths statistic not defined yet is not purged")
    yu.statsEmpty = false
    tickAll(130)
    assert(db.roster["Zed-Forever"].stats.g2007 == 17 and db.roster["Zed-Forever"].stats.g2001 == nil, "defined: Deaths kept, the Kills one purged by its category")
    leave(yu)
    said[#said + 1] = "saved statistics wait for the probe"
  end)

  -- (s) a burst before the roster loads
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3), member("Mal", 3) }, function()
    local NEW = EPOCH + 500
    local ofaDb = pol(true, { gold = "self", deaths = "self" }, NEW)
    local ofa, mo = char("Ofa", 0), char("Mo", 3)
    JUDGE = judgeBy(ofaDb)
    mo.got = {}
    login(ofa, ofaDb); login(mo, pol(nil, { gold = "self", deaths = "self" }, NEW))
    tickAll(45)
    local mia = char("Mia", 3, { money = 777777 })
    local real, slow = mia.env.C_Club.GetClubMembers, true
    mia.env.C_Club.GetClubMembers = function(...) if slow then return {} end return real(...) end
    local g0 = #mo.got
    login(mia, pol(nil, { gold = "all" }))
    for _ = 1, 200 do mia.C.Comm:Receive("1P|0|1|1/1|", "GUILD", "Mal-Forever") end
    tickAll(40)
    slow = false
    fire(mia, "GUILD_ROSTER_UPDATE")
    tickAll(30)
    assert(#leakedTo(mo, g0 + 1) == 0 and mia.C.Policy:Route("gold") == "self", "the officer's answer kept: " .. table.concat(leakedTo(mo, g0 + 1), ", "))
    JUDGE = nil
    for _, c in ipairs({ ofa, mo, mia }) do leave(c) end
    said[#said + 1] = "one sender's burst pushes nothing out"
  end)
  collectgarbage()

  -- (t) Level closed and opened again, twice
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
    local mo = guidOf("Mo")
    local mia = char("Mia", 3)
    login(mia, { known = { xp = { [30] = { [mo] = 9999 } } } })
    tickAll(40)
    for _ = 1, 2 do
      mia.env.CuteDB.policy = { vis = { level = "self" }, by = "Ofa-Forever", rank = 0, at = EPOCH, threshold = 1 }
      mia.C.Policy:Purge()
      mia.env.CuteDB.policy = { vis = {}, by = "Ofa-Forever", rank = 0, at = EPOCH, threshold = 1 }
      mia.C.Rules.LearnXP(30, mo, 9999)
    end
    local v, state, n = mia.C.Rules.XPCurveLearns(30)
    assert(n == nil or n <= 1 or v ~= 9999, "one member counted once however often Level closes: " .. tostring(n))
    leave(mia)
    said[#said + 1] = "a member counted once"
  end)
  collectgarbage()

  -- (u) the officer ranks never past your own
  isolated({ member("Ofa", 0), member("Yan", 1), member("Obi", 1), member("Mia", 3) }, function()
    local ofa, yan, obi, mia = char("Ofa", 0), char("Yan", 1), char("Obi", 1), char("Mia", 3, { money = 777777 })
    login(ofa, pol(true)); login(yan, pol()); login(obi, pol()); login(mia, pol())
    tickAll(60)
    yan.C.UI:Open("settings", "vis")
    local minus
    for _, fr in ipairs(yan.frames) do
      if fr.__kind == "Button" and fr:IsVisible() and fr.__scripts.OnEnter then
        local tip = tipOf(fr)
        if tip:find("Officer ranks", 1, true) and fr.label and fr.label:GetText() == "-" then minus = fr end
      end
    end
    assert(minus and minus.__disabled, "a rank-1 officer's minus is greyed at 0 to 1")
    assert(yan.C.Policy:SetThreshold(0) == false and yan.C.Policy:Threshold() == 1, "and refused")
    mia.C.Comm:Receive(string.format("1P|%d|0|1/1|", EPOCH + mia.clock), "GUILD", yan.sender)
    assert(mia.C.Policy:Threshold() == 1 and mia.C.Roster:IsOfficer(obi.sender), "a rank-1 officer's policy cannot leave rank 1 out")
    for _, c in ipairs({ ofa, yan, obi, mia }) do leave(c) end
    said[#said + 1] = "the ranks never past your own"
  end)

  -- (v) a member's ranking of a stat the officers keep, (w) a change in Settings goes on its own
  isolated({ member("Ofa", 0), member("Kim", 3), member("Lee", 3) }, function()
    local ofa, kim, lee = char("Ofa", 0, { withStats = true }), char("Kim", 3, { withStats = true }), char("Lee", 3)
    login(ofa, pol(true, { gc130 = "self" })); login(kim, pol(nil, { gc130 = "self" })); login(lee, pol(nil, { gc130 = "self" }))
    tickAll(120)
    kim.C.UI:Open("game")
    local function lineOf(c, test) for _, lst in ipairs({ c.C.UI.catLines, c.C.UI.lines }) do for _, l in ipairs(lst.items) do if l:IsShown() and test(l) then return l end end end end
    press(lineOf(kim, function(l) return l.cat and l.cat.id == 130 end) or lineOf(kim, function(l) return l.cat and tostring(l.cat.id) == "130" end))
    local stat = lineOf(kim, function(l) return l.def and l.def.id == "g2001" and not l.member end)
    assert(stat, "Total kills listed")
    press(stat)
    local own = lineOf(kim, function(l) return l.member and l.member.row.me end)
    assert(own and not own.name:GetText():find("^%d+%."), "the member's own row unnumbered: " .. tostring(own and own.name:GetText()))
    -- Ofa ticks Only you for Deaths in Settings, and presses nothing more
    ofa.C.UI:Open("settings", "vis")
    local box = checkBox(ofa, function(fr) return fr.statId == "deaths" and fr.vis == "self" end)
    assert(box, "the Deaths pair")
    click(box)
    tickAll(8)
    assert(lee.C.Policy:Route("deaths") == "self", "the change reached Lee on its own")
    for _, c in ipairs({ ofa, kim, lee }) do leave(c) end
    said[#said + 1] = "no place on a kept stat; a change goes on its own"
  end)
  collectgarbage()

  -- (x) the smaller ones
  isolated({ member("Ofa", 0), member("Ofi", 1), member("Mia", 3), member("Zed", 3), member("Alto", 3), member("Mal", 3) }, function()
    local T = EPOCH + 100
    local ofa, ofi, mia = char("Ofa", 0), char("Ofi", 1), char("Mia", 3)
    login(ofa, pol(true, { gold = "self" }, T)); login(ofi, pol(nil, { gold = "self" }, T)); login(mia, pol(nil, { gold = "self" }, T))
    tickAll(30)
    -- a whisper from a sender heard on GUILD with no record makes none
    ofa.C.Comm:Receive("1R|", "GUILD", "Zed-Forever")
    ofa.C.Comm:Receive("1D|4|gold=1", "WHISPER", "Zed-Forever")
    assert(not rec(ofa, "Zed"), "a whisper makes no record")
    -- the policy held, said again, costs no snapshot of every route
    local snaps, realSnap = 0, mia.C.Policy.Snapshot
    mia.C.Policy.Snapshot = function(...) snaps = snaps + 1; return realSnap(...) end
    mia.C.Comm:Receive(string.format("1P|%d|1|1/1|", T), "GUILD", ofa.sender)
    mia.C.Policy.Snapshot = realSnap
    assert(snaps == 0, "the policy held, said again, takes no snapshot: " .. snaps)
    -- two officers' policies stamped in one second (a guild with no line): every client ends on the same one, whichever
    -- came first
    local zed = char("Zed", 3)
    login(zed, pol(nil, { gold = "self" }, T))
    tickAll(25)
    local one = string.format("1P|%d|1|1/1|%s", T + 5, tok("gold", "all"))
    local two = string.format("1P|%d|1|1/1|%s", T + 5, tok("level", "self"))
    mia.C.Comm:Receive(one, "GUILD", ofi.sender); mia.C.Comm:Receive(two, "GUILD", ofa.sender)
    zed.C.Comm:Receive(two, "GUILD", ofa.sender); zed.C.Comm:Receive(one, "GUILD", ofi.sender)
    assert(mia.C.Policy:Fp() == zed.C.Policy:Fp() and mia.env.CuteDB.policy.at == T + 5, "the same one on every client")
    leave(zed)
    -- the officer's Ready tooltip on a 0.5.x member's verdict, which counted every gap
    local b36 = ofa.C.Comm.b36
    ofa.C.Comm:Receive("1F|1|1|4|guid=" .. guidOf("Mal") .. ";ready=1;durability=" .. b36(80) .. ";potions=" .. b36(5) .. ";addon_ver=0.5.2", "GUILD", "Mal-Forever")
    ofa.env.CuteDB.settings.columns.prog = { ready = true }
    ofa.C.UI:Open("prog")
    local cell = rowOf(ofa, "Mal") and cellOf(rowOf(ofa, "Mal"), "ready")
    local tip = cell and tipOf(cell) or ""
    assert(cell and cell.label:GetText() == "gaps" and tip:find("Counted by Cute 0.5.2", 1, true) and not tip:find("No gaps.", 1, true), "a 0.5.x Ready's tooltip says what it counted: " .. tip)
    -- a row without the addon is no one to mark untrusted
    ofa.C.UI:Open("officers")
    local alto = rowOf(ofa, "Alto")
    assert(alto and not alto.row.addon, "Alto has no Cute")
    press(alto)
    assert(ofa.C.UI.picked == nil, "a row without the addon is not picked")
    assert(not ofa.C.Stats.byId.last_login.hint:lower():find("epoch", 1, true), "Last login's description is a player's")
    for _, c in ipairs({ ofa, ofi, mia }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Alto", 3), member("Mia", 3) }, function()
    -- 0.5.x's saved variables: the officer main's file, no officerOf; the member alt logs in first
    local db = { version = "0.5.2", policy = { vis = {}, by = "Ofa-Forever", mine = true, rank = 0, at = EPOCH, threshold = 1 },
      chars = { ["Ofa-Forever"] = { counters = {} }, ["Alto-Forever"] = { counters = {} } },
      roster = { ["Mia-Forever"] = { seen = EPOCH, online = true, stats = { guid = guidOf("Mia"), level = 30, gold = 4242 }, at = {} } } }
    local alto = char("Alto", 3)
    login(alto, db)
    tickAll(40)
    assert(db.roster["Mia-Forever"].stats.gold == 4242, "a 0.5.x officer's file is not purged by its member alt")
    leave(alto)
  end)
  isolated({ member("Ofa", 0), member("Ofi", 1), member("Mia", 3) }, function()
    local ofa, ofi, mia = char("Ofa", 0), char("Ofi", 1), char("Mia", 3)
    login(ofa, pol(true)); login(ofi, pol()); login(mia, pol())
    tickAll(30)
    local b36 = ofi.C.Comm.b36
    ofi.C.Comm:Receive("1D|4|bank_in=" .. b36(50000), "WHISPER", mia.sender)
    ofi.C.Comm:Receive("1D|4|bank_in=0", "WHISPER", mia.sender)
    assert(rec(ofi, "Mia").suspect and rec(ofi, "Mia").suspect.why:find("50000", 1, true), "Ofi's client marks it, the value in the reason")
    g("Ofi").rank = 3
    fire(ofi, "GUILD_ROSTER_UPDATE")
    tickAll(3)
    local s = rec(ofi, "Mia").suspect
    assert(not ofi.C.Roster:MeOfficer() and s and not s.why:find("50000", 1, true), "a member again: the mark stays, the value out of its reason: " .. tostring(s and s.why))
    for _, c in ipairs({ ofa, ofi, mia }) do leave(c) end
    said[#said + 1] = "the smaller ones"
  end)
  print("the fourth round: " .. table.concat(said, "; "))
end

-- 47: what the fifth round of review found (0.6.0), once the policy lived in Guild Info, each case one that failed
-- before its fix. (a) A raid of forty: each kill claim fits one message (it was 364 bytes, never sent) and the kill is
-- corroborated. (b) Closing Level keeps an XP value this client and one other member agreed on. (c) An officer demoted
-- after their own last change purges, in the session and at the next login. (d) A character of the account in a
-- second guild deletes and strips nothing of the first guild's records and knowledge. (e) A member's Ready held by an
-- officer when the officers closed a gap it counted goes once that officer is a member, at the next login or at once.
-- (f) With Grouped with kept to the officers, members learn the bosses from the officers' word. (g) A forged ask every
-- two seconds gets the policy a few times, not thirty. (h) An officer who was away while another marked a member
-- untrusted, trusted one again and retuned or reset a rule undoes none of it with a change of their own. (i) The
-- Guide's Settings section says a change goes on its own. (j) A run of clicks sends the policy once, three seconds
-- after the last. (k) An untrusted member's labels name nothing, what he said before the mark included. (l) A copy
-- sending a namesake's GUID takes nothing of hers. (m) The officers' word, unchanged, keeps its stamp: no member
-- holding it is answered, a /reload restamps nothing
collectgarbage()
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function pol(mine, vis, at, thr)
    local copy = {}
    for k, v in pairs(vis or {}) do copy[k] = v end
    return { policy = { vis = copy, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = thr or 1 } }
  end
  local function rec(db, who) return db.roster[who .. "-Forever"] end
  local function g(name) for _, m in ipairs(GUILD) do if m.name == name .. "-Forever" then return m end end end
  local function enter(c, kind, inst, name, mates)
    c.o.party = mates
    c.o.instance, c.o.instanceID, c.o.instName = kind, inst, name
    fire(c, "PLAYER_ENTERING_WORLD", false, false)
  end
  local said = {}

  -- (a) a raid of forty: Ann and Mo in one five, the rest of the raid without Cute
  isolated({ member("Ofa", 0), member("Ann", 3), member("Mo", 3) }, function()
    local raid = { "Ann", "Mo" }
    for i = 1, 38 do raid[#raid + 1] = "Raider" .. i end
    local ofa = char("Ofa", 0)
    local ann = char("Ann", 3, { raid = raid })
    local mo = char("Mo", 3, { raid = raid })
    login(ofa, pol(true)); login(ann, pol()); login(mo, pol())
    tickAll(45)
    enter(ann, "raid", 409, "Molten Core", { "Mo", "Raider1", "Raider2", "Raider3" })
    enter(mo, "raid", 409, "Molten Core", { "Ann", "Raider1", "Raider2", "Raider3" })
    local k0 = msgs(ann, "1K") + msgs(mo, "1K")
    fire(ann, "ENCOUNTER_END", 663, "Lucifron", 9, 40, 1, {}); fire(mo, "ENCOUNTER_END", 663, "Lucifron", 9, 40, 1, {})
    tickAll(10)
    assert(msgs(ann, "1K") + msgs(mo, "1K") - k0 == 2 and #ann.oversize == 0 and #mo.oversize == 0, "each claim went, in one message: " .. (msgs(ann, "1K") + msgs(mo, "1K") - k0))
    for _, c in ipairs({ ann, mo }) do for _, m in ipairs(c.sent) do assert(#m.msg <= 255, "a message over 255 bytes: " .. #m.msg) end end
    assert(ofa.C.Rules.Corroborated(663, ann.o.guid) and ofa.C.Rules.Corroborated(663, mo.o.guid), "the raid kill corroborated")
    -- a claim kept from before the cap, its whole raid named, is cut to fit as it goes
    local with = {}
    for _, n in ipairs(raid) do if n ~= "Ann" then with[guidOf(n)] = true end end
    ann.env.CuteDB.chars[ann.name].claims[664] = { t = EPOCH + ann.clock, with = with }
    ann.C.Comm:Claims(true)
    tickAll(5)
    assert(#ann.oversize == 0, "a kept claim of a whole raid fits too")
    for _, c in ipairs({ ofa, ann, mo }) do leave(c) end
    said[#said + 1] = "a raid's kill claim fits and is corroborated"
  end)

  -- (b) Level closed: Mia's own XP sample and Ann's agree
  isolated({ member("Ofa", 0), member("Mia", 3), member("Ann", 3) }, function()
    local mia = char("Mia", 3)
    login(mia, pol())
    tickAll(30)
    local k = mia.env.CuteDB.known
    k.xp[75] = { [mia.o.guid] = 123457, [guidOf("Ann")] = 123457 }
    mia.C.Rules.StripTraces({ level = true })
    local v, st, n = mia.C.Rules.XPCurveLearns(75)
    assert(k.xp[75][guidOf("Ann")] == nil and v == 123457 and st == "seen" and n == 2, "Ann's GUID out, the value two agreed on kept: " .. tostring(v) .. " " .. tostring(n))
    -- Ann seen again later counts once, not twice
    k.xp[75][guidOf("Ann")] = 123457
    v, st, n = mia.C.Rules.XPCurveLearns(75)
    assert(v == 123457 and n == 2, "Ann seen again counts once: " .. tostring(n))
    leave(mia)
    said[#said + 1] = "Level closed keeps what you and one other agreed on"
  end)

  -- (c) an officer demoted after their own last change: in the session, then at the next login with the same file
  isolated({ member("Ofi", 1), member("Mia", 3) }, function()
    local db = pol()
    local ofi, mia = char("Ofi", 1), char("Mia", 3, { money = 777777 })
    login(ofi, db); login(mia, pol())
    tickAll(40)
    ofi.C.Policy:Set("deaths", "self")
    tickAll(10)
    assert(rec(db, "Mia").stats.gold == 777777 and db.policy.mine, "Ofi holds Mia's gold, the policy her own change")
    g("Ofi").rank = 3
    fire(ofi, "GUILD_ROSTER_UPDATE")
    tickAll(3)
    assert(not ofi.C.Roster:MeOfficer() and rec(db, "Mia").stats.gold == nil and rec(db, "Mia").stats.deaths == nil, "demoted: her client deletes Mia's Only-you values")
    leave(ofi)
    rec(db, "Mia").stats.gold = 777777
    db.chars[ofi.name].officerOf = nil -- (as a file whose officer logged out before the roster said otherwise)
    local ofi2 = char("Ofi", 3)
    login(ofi2, db)
    tickAll(30)
    assert(rec(db, "Mia").stats.gold == nil, "at the next login, a member, the same")
    for _, c in ipairs({ ofi2, mia }) do leave(c) end
    said[#said + 1] = "an officer demoted after their own change purges"
  end)

  -- (d) one account in two guilds: Ofa, an officer of guild 7, holds Mia's gold and their kill; the account's Alto,
  -- a member of guild 8, whose line keeps Bosses and Gold to its officers, plays two minutes
  do
    local account = {}
    isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
      local ofa, mia, mo = char("Ofa", 0), char("Mia", 3, { money = 777777 }), char("Mo", 3)
      login(ofa, account)
      account.policy = pol(true).policy
      login(mia, pol()); login(mo, pol())
      tickAll(60)
      enter(mia, "party", 36, "The Deadmines", { "Mo" }); enter(mo, "party", 36, "The Deadmines", { "Mia" })
      fire(mia, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {}); fire(mo, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
      tickAll(60)
      assert(rec(account, "Mia").stats.gold == 777777 and account.known.kills[1230][guidOf("Mia")], "Ofa holds Mia's gold and her kill")
      for _, c in ipairs({ ofa, mia, mo }) do leave(c) end
    end)
    isolated({ member("Xo", 0), member("Alto", 3), member("Xmo", 3) }, function()
      local function club8(c)
        local cc = c.env.C_Club
        local gm, gi, gs = cc.GetClubMembers, cc.GetMemberInfo, cc.GetMemberInfoForSelf
        cc.GetGuildClubId = function() return c.inGuild and 8 or nil end
        cc.GetClubMembers = function(id) return gm(id == 8 and 7 or id) end
        cc.GetMemberInfo = function(id, i) return gi(id == 8 and 7 or id, i) end
        cc.GetMemberInfoForSelf = function(id) return gs(id == 8 and 7 or id) end
      end
      INFO[8] = infoLine({ vis = { gc_bosses = "self", gold = "self" }, threshold = 1 })
      local xo, alto, xmo = char("Xo", 0), char("Alto", 3), char("Xmo", 3)
      club8(xo); club8(alto); club8(xmo)
      login(xo, pol(true, { gc_bosses = "self", gold = "self" })); login(xmo, pol(nil, { gc_bosses = "self", gold = "self" }))
      tickAll(10)
      login(alto, account)
      tickAll(130)
      assert(alto.C.Policy:Holds() and alto.C.Policy:Route("gold") == "self" and rec(account, "Xmo") and not rec(account, "Mia"), "Alto routes by guild 8's line, its records its own")
      for _, c in ipairs({ xo, alto, xmo }) do leave(c) end
    end)
    isolated({ member("Ofa", 0), member("Mia", 3), member("Mo", 3) }, function()
      g("Mia").online, g("Mo").online = false, false
      local ofa = char("Ofa", 0)
      login(ofa, account)
      tickAll(20)
      local r = rec(account, "Mia")
      assert(r and r.stats.gold == 777777 and account.known.kills[1230] and account.known.kills[1230][guidOf("Mia")], "back in guild 7: Mia's record, her gold and her kill all there")
      assert(account.policies["8"] and account.policies["8"].roster["Xmo-Forever"], "guild 8's records kept for its characters")
      leave(ofa)
    end)
    said[#said + 1] = "another guild deletes and strips nothing of this one's"
  end

  -- (e) Bo's Ready, held by Cy while an officer when the officers closed the empty slots and the enchants it counted
  for _, when in ipairs({ "at the next login", "at once" }) do
    isolated({ member("Ofa", 0), member("Bo", 3), member("Cy", 1) }, function()
      local vis = { empty_slots = "all", unenchanted = "all" }
      local cyDb, ofaDb = pol(nil, vis), pol(true, vis)
      INFO[7] = infoLine(ofaDb.policy)
      local ofa, bo, cy = char("Ofa", 0), char("Bo", 3, { items = { [1] = "item:1234:0" } }), char("Cy", 1)
      login(ofa, ofaDb); login(bo, pol(nil, vis)); login(cy, cyDb)
      tickAll(45)
      assert(rec(cyDb, "Bo").stats.ready ~= nil, "Cy holds Bo's Ready")
      leave(bo); g("Bo").online = false
      ofa.C.Policy:Set("empty_slots", "self"); ofa.C.Policy:Set("unenchanted", "self")
      assert(saveLine(ofa))
      tickAll(15)
      assert(cy.C.Roster:MeOfficer() and rec(cyDb, "Bo").stats.ready ~= nil, "Cy, an officer, keeps it")
      g("Cy").rank = 3
      if when == "at once" then
        fire(cy, "GUILD_ROSTER_UPDATE")
        tickAll(3)
      else
        leave(cy)
        cy = char("Cy", 3)
        login(cy, cyDb)
        tickAll(70)
      end
      local s = rec(cyDb, "Bo").stats
      assert(not cy.C.Roster:MeOfficer() and s.empty_slots == nil and s.ready == nil, when .. ": a member now, Bo's Ready goes with his gaps")
      for _, c in ipairs({ ofa, cy }) do leave(c) end
    end)
  end
  said[#said + 1] = "a Ready an officer held goes once they are a member"

  -- (f) Grouped with kept to the officers: Ann and Mo kill Rhahk'Zor together, Cy learns it from the officers' word
  isolated({ member("Ofa", 0), member("Ann", 3), member("Mo", 3), member("Cy", 3) }, function()
    local vis = { group = "self" }
    local ofaDb = pol(true, vis)
    INFO[7] = infoLine(ofaDb.policy)
    local ofa, ann, mo, cy = char("Ofa", 0), char("Ann", 3), char("Mo", 3), char("Cy", 3)
    login(ofa, ofaDb); login(ann, pol(nil, vis)); login(mo, pol(nil, vis)); login(cy, pol(nil, vis))
    tickAll(45)
    enter(ann, "party", 36, "The Deadmines", { "Mo" }); enter(mo, "party", 36, "The Deadmines", { "Ann" })
    fire(ann, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {}); fire(mo, "ENCOUNTER_END", 1230, "Rhahk'Zor", 1, 5, 1, {})
    tickAll(90)
    assert(not cy.C.Rules.Corroborated(1230, ann.o.guid), "no claim reached Cy: no kill corroborated there")
    local b = cy.C.Rules.Model().bosses[1230]
    assert(b and b.state == "seen" and b.officers and cy.C.Rules.Word().bosses[1230], "Cy has the boss from the officers' word: " .. tostring(b and b.state))
    for _, c in ipairs({ ofa, ann, mo, cy }) do leave(c) end
    said[#said + 1] = "Grouped with kept: the word says the bosses"
  end)

  -- (g) a copy asks every two seconds for a minute, its stamp and fingerprint none
  isolated({ member("Ofa", 0), member("Mia", 3), member("Zed", 3) }, function()
    local ofaDb = pol(true, { gold = "all" })
    INFO[7] = infoLine(ofaDb.policy)
    local ofa, mia, zed = char("Ofa", 0), char("Mia", 3), char("Zed", 3)
    login(ofa, ofaDb); login(mia, pol(nil, { gold = "all" })); login(zed, pol())
    tickAll(60)
    local p0 = msgs(ofa, "1P") + msgs(mia, "1P")
    for _ = 1, 30 do
      zed.C.Comm.Queue({ msg = "1R|" .. zed.o.guid .. "|0|0|0000000000000000", first = true })
      tickAll(2)
    end
    local n = msgs(ofa, "1P") + msgs(mia, "1P") - p0
    assert(n >= 1 and n <= 3, "the policy a few times in a minute, not once an ask: " .. n)
    for _, c in ipairs({ ofa, mia, zed }) do leave(c) end
    said[#said + 1] = "a copy's asks get the policy twice a minute"
  end)

  -- (h) Ofb, while Ofa was away, marks Mo untrusted, trusts Zed again, retunes one rule and puts another back to its
  -- default; Ofa logs in after Ofb has left, no other officer online, and changes the zone: none of it is undone
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Mo", 3), member("Zed", 3) }, function()
    local ofaDb = pol(true, nil, EPOCH + 50)
    ofaDb.policy.untrusted = { [guidOf("Zed")] = true }
    ofaDb.policy.rules, ofaDb.policy.ruleBy = { doubtRuns = 4 }, { doubtRuns = guidOf("Ofa") }
    INFO[7] = infoLine(ofaDb.policy)
    local ofbDb = pol()
    local ofa, ofb, mia, mo = char("Ofa", 0), char("Ofb", 1), char("Mia", 3), char("Mo", 3)
    login(ofa, ofaDb); login(ofb, ofbDb); login(mia, pol()); login(mo, pol())
    tickAll(60)
    assert(mia.C.Policy:Untrusted(guidOf("Zed")) and mia.C.Rules.Get("doubtRuns") == 4, "Ofa's word held")
    leave(ofa); g("Ofa").online = false
    for _, c in ipairs({ ofb, mia, mo }) do fire(c, "GUILD_ROSTER_UPDATE") end
    tickAll(5)
    ofb.C.Policy:SetUntrusted(guidOf("Mo"), true)
    ofb.C.Policy:SetUntrusted(guidOf("Zed"), false)
    ofb.C.Policy:SetRule("rangeMembers", 4)
    ofb.C.Policy:SetRule("doubtRuns", nil)
    ofb.C.Comm:PolicySoon()
    tickAll(10)
    local P, R = mia.C.Policy, mia.C.Rules
    assert(P:Untrusted(guidOf("Mo")) and not P:Untrusted(guidOf("Zed")) and R.Get("rangeMembers") == 4 and R.Get("doubtRuns") == R.RULES.doubtRuns,
      "Mia holds Ofb's changes, the default back too")
    leave(ofb); g("Ofb").online = false
    for _, c in ipairs({ mia, mo }) do fire(c, "GUILD_ROSTER_UPDATE") end
    g("Ofa").online = true
    local ofa2 = char("Ofa", 0)
    login(ofa2, ofaDb)
    tickAll(60)
    ofa2.C.Policy:Set("zone", "self")
    ofa2.C.Policy:SetRule("guideAhead", 4)
    assert(saveLine(ofa2))
    ofa2.C.Comm:PolicySoon()
    tickAll(10)
    assert(P:Route("zone") == "self" and R.Get("guideAhead") == 4, "Ofa's change taken")
    assert(P:Untrusted(guidOf("Mo")) and not P:Untrusted(guidOf("Zed")) and R.Get("rangeMembers") == 4 and R.Get("doubtRuns") == R.RULES.doubtRuns,
      "and none of Ofb's undone: Mo untrusted, Zed trusted, her rules")
    -- Ofb back: Ofa's client takes what it missed, item by item, and keeps its own change
    g("Ofb").online = true
    local ofb2 = char("Ofb", 1)
    login(ofb2, ofbDb)
    tickAll(30)
    ofb2.C.Comm:SendPolicy()
    tickAll(5)
    assert(ofa2.C.Policy:Untrusted(guidOf("Mo")) and ofa2.C.Rules.Get("guideAhead") == 4, "Ofa's client has Ofb's marks and keeps its own rule")
    for _, c in ipairs({ ofa2, ofb2, mia, mo }) do leave(c) end
    said[#said + 1] = "an officer away undoes nothing another set meanwhile"
  end)

  -- (i) the Guide's section, (j) a run of clicks
  isolated({ member("Ofa", 0), member("Mia", 3) }, function()
    local ofa, mia = char("Ofa", 0), char("Mia", 3)
    login(ofa, pol(true)); login(mia, pol())
    tickAll(30)
    ofa.C.Modules.Set("guide", true)
    ofa.C.UI:Open("settings", "guide")
    local t = texts(ofa)
    assert(t:find("A change goes to the guild on its own.", 1, true) and not t:find("Broadcast now sends them", 1, true), "the Guide's section says what happens")
    ofa.C.UI.frame:Hide()
    for _, c in ipairs({ ofa, mia }) do leave(c) end
  end)
  isolated({ member("Ofa", 0), member("Mia", 3) }, function()
    local ofa, mia = char("Ofa", 0), char("Mia", 3)
    login(ofa, pol(true)); login(mia, pol())
    tickAll(30)
    local p0, last = msgs(ofa, "1P"), nil
    for i = 1, 6 do
      ofa.C.Policy:SetRule("guideWindow", 3 + (i % 2))
      ofa.C.Comm:PolicySoon()
      last = ofa.clock
      tickAll(1)
    end
    tickAll(5)
    local sent = {}
    for _, m in ipairs(ofa.sent) do if m.msg:sub(1, 2) == "1P" then sent[#sent + 1] = m.at end end
    assert(msgs(ofa, "1P") - p0 == 1 and sent[#sent] >= last + 3, "one policy, three seconds after the last click: " .. (msgs(ofa, "1P") - p0))
    for _, c in ipairs({ ofa, mia }) do leave(c) end
    said[#said + 1] = "the Guide's note; a run of clicks sends once"
  end)

  -- (k) Mal's junk labels and values, then Mal marked untrusted: nothing of his names or defines anything, this
  -- session or the next
  isolated({ member("Ofa", 0), member("Mia", 3), member("Mal", 3) }, function()
    local miaDb = pol()
    local ofa, mia, mal = char("Ofa", 0), char("Mia", 3), char("Mal", 3)
    login(ofa, pol(true)); login(mia, miaDb); login(mal, pol())
    tickAll(30)
    mal.C.Comm.Queue({ msg = "1D|4|e999001=1;i999036=2" })
    mal.C.Comm.Queue({ msg = "1L|e999001:999036=Junk Name;i999036:p=Junk Place" })
    tickAll(5)
    assert(mia.C.Stats.LabelOf("e999001") == "Junk Name", "Mal's labels name his junk")
    ofa.C.Policy:SetUntrusted(guidOf("Mal"), true)
    ofa.C.Comm:PolicySoon()
    tickAll(10)
    local S = mia.C.Stats
    assert(mia.C.Policy:Untrusted(guidOf("Mal")) and not S.LabelOf("e999001") and not S.LabelOf("i999036") and not S.KindOf(999036), "marked: his names name nothing")
    leave(mia)
    local mia2 = char("Mia", 3)
    login(mia2, miaDb)
    tickAll(10)
    S = mia2.C.Stats
    assert(not S.byId.e999001 and not S.byId.i999036 and not S.LabelOf("e999001"), "nor at the next login")
    for _, c in ipairs({ ofa, mia2, mal }) do leave(c) end
    said[#said + 1] = "an untrusted member's labels name nothing"
  end)

  -- (l) namesakes, "Helga Xan" and "Helga Yin" as the channel names them, "Helga" both as the roster does: Yin's copy
  -- sends Xan's GUID
  do
    local people = { { "Mia", "Lark", 3 }, { "Helga", "Xan", 1 }, { "Helga", "Yin", 3 } }
    local function gid(p) return guidOf(p[1] == "Helga" and (p[1] .. " " .. p[2]) or p[1]) end
    local list = {}
    for i, p in ipairs(people) do list[i] = { name = p[1], guid = gid(p), rank = p[3], rankName = p[3] <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true } end
    local function mk(p)
      local o = charOf({ p[1], p[3], "", "MAGE", 30 })
      o.surname, o.sender, o.guid = p[2], p[1] .. " " .. p[2], gid(p)
      return newClient(o)
    end
    -- (in either order: Xan first, then the copy; the copy first, alone with Mia, then Xan. The roster cannot vouch
    -- for a GUID under either sender string, so no record keeps one: neither is a voice or joined to a row)
    for _, copyFirst in ipairs({ false, true }) do
      isolated(list, function()
        local mia, xan = mk(people[1]), mk(people[2])
        local MR, hx = mia.C.Roster, guidOf("Helga Xan")
        login(mia)
        if not copyFirst then login(xan) end
        tickAll(45)
        local db = mia.env.CuteDB.roster
        mia.C.Comm:Receive("1F|1|1|4|guid=" .. hx .. ";level=u;deaths=zz", "GUILD", "Helga Yin")
        if copyFirst then login(xan); tickAll(45) end
        local y, x = db["Helga Yin"], db["Helga Xan"]
        assert(x and x.stats.guid == nil and y and y.stats.guid == nil, "neither record keeps a GUID the roster cannot vouch for")
        for _, r in ipairs(MR:Rows()) do assert(not (r.key == "Helga Yin" and r.guid == hx), "the copy takes no row of Xan's") end
        assert(MR:GuidOf("Helga Yin") ~= hx and mia.C.Comm:ReceiveLabels("e1230:36=X", "Helga Yin") == 0, "nor her GUID, nor her voice")
        for _, c in ipairs({ mia, xan }) do leave(c) end
      end)
    end
    said[#said + 1] = "a namesake's copy takes nothing of hers, first or not"
  end

  -- (m) the officers' word unchanged keeps its stamp: Ann's ask is answered under it, Bea, holding it, is not answered,
  -- and Ofa's /reload says it under it again
  isolated({ member("Ofa", 0), member("Mo", 3), member("Ann", 3), member("Bea", 3) }, function()
    local ofaDb, beaDb = pol(true), pol()
    local function stub(c) c.C.Rules.WordParts = function() return { "n2=4.1", "x11=d" } end end
    local ofa, mo = char("Ofa", 0), char("Mo", 3)
    login(ofa, ofaDb); stub(ofa); login(mo, pol())
    tickAll(60)
    ofa.C.Comm:WordSoon(true)
    tickAll(20)
    local function stamps(c)
      local out = {}
      for _, m in ipairs(c.sent) do local at = m.msg:match("^1N|(%d+)|"); if at then out[at] = true end end
      local list = {}
      for at in pairs(out) do list[#list + 1] = at end
      return list
    end
    assert(#stamps(ofa) == 1 and mo.C.Rules.WordStamp() > 0, "Mo holds Ofa's word")
    local ann = char("Ann", 3)
    login(ann, pol())
    tickAll(40)
    assert(ann.C.Rules.WordStamp() > 0 and #stamps(ofa) == 1, "Ann asked: answered under the same stamp: " .. #stamps(ofa))
    local bea = char("Bea", 3)
    login(bea, beaDb)
    tickAll(30)
    leave(bea)
    local n0 = msgs(ofa, "1N")
    bea = char("Bea", 3)
    login(bea, beaDb)
    tickAll(40)
    assert(msgs(ofa, "1N") == n0, "Bea, holding it, is not answered")
    leave(ofa)
    local ofa2 = char("Ofa", 0)
    login(ofa2, ofaDb, true); stub(ofa2)
    tickAll(40)
    local a, b = stamps(ofa2), mo.C.Rules.WordStamp()
    assert(#a <= 1 and (#a == 0 or tonumber(a[1]) == b), "a /reload says it under the stamp it had")
    for _, c in ipairs({ ofa2, mo, ann, bea }) do leave(c) end
    said[#said + 1] = "an unchanged word keeps its stamp"
  end)
  print("the fifth round: " .. table.concat(said, "; "))
end

-- 48: what the sixth round of review found (0.6.0), each case one that failed before its fix. (a) An officer demoted
-- with a change not saved keeps none of it: neither the members' Only-you values (a stat opened) nor the officer's
-- place (the ranks raised). (b) A client that cannot read Guild Info again (an encounter, a secret text) sends nothing
-- after an officer's newer policy until it does: no stat the save closed on GUILD, no whisper to a rank it no longer
-- names. (c) An alt's file is an officer's only while the roster ranks that character an officer: one demoted while
-- offline is purged at the alt's login. (d) Save to Guild Info is refused inside an instance, where Guild Info may read
-- empty and the guild's text would be lost. (e) A character the line's ranks make an officer, logging in inside an
-- instance, asks again once it holds the line and gets what it dropped meanwhile. (f) A line with its fingerprint
-- alone is read by nobody, and a member's policy of that fingerprint routes nothing. (g) Guild Info is read on the
-- roster's answer, not on PLAYER_GUILD_UPDATE, and one event that came while C_Club listed nobody is read once it lists
-- the guild. (h) One voice keeps at most four enchant kinds a slot of its own. (i) A level said again and again is
-- held from its first time and marked. (j) An untrusted member's made-up version announces nothing. (k) A member's
-- policy asks for no roster read, and an untrusted member's asks get the officers' policy once in five minutes. (l)
-- 0.5.x's saved variables are the guild's whose roster lists their records: an alt's login in a second guild prunes
-- and takes nothing. (m) A module's stat a line keeps routes by it once the module is on, and an officer's click on it
-- keeps the line's other choices. (n) An officer's change not saved costs the members nothing they learned from the
-- officers' word. (o) The smaller ones: the officers' word once in half an hour to one asker; an item's stamp no later
-- than its word's; the roster's minute refreshes once; a module switched off in the game's AddOns list stays off;
-- Broadcast now says who sees what goes by Guild Info; the Me page's members' view waits for the save; a member's
-- purge keeps no stat it cannot name (a module's, the module off)
collectgarbage()
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function pol(mine, vis, at, thr)
    local copy = {}
    for k, v in pairs(vis or {}) do copy[k] = v end
    return { policy = { vis = copy, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = thr or 1 } }
  end
  local function rec(db, who) return db.roster[who .. "-Forever"] end
  local function g(name) for _, m in ipairs(GUILD) do if m.name == name .. "-Forever" then return m end end end
  local function chatHas(c, s) for _, l in ipairs(c.chat) do if l:find(s, 1, true) then return true end end return false end
  -- what one client received from another since a mark: on GUILD with a value of id, or whispered
  local function gotFrom(c, from, from0, test)
    local n = 0
    for i = from0 or 1, #(c.got or {}) do local m = c.got[i]; if m.from == from.sender and test(m) then n = n + 1 end end
    return n
  end
  local said = {}

  -- (a) Ofi, an officer, opens Gold (or raises the ranks to hers and the members') and does not save; then demoted
  for _, how in ipairs({ "opens Gold", "raises the ranks" }) do
    isolated({ member("Ofi", 1), member("Mia", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local db = pol()
      local ofi, mia = char("Ofi", 1), char("Mia", 3, { money = 777777 })
      login(ofi, db); login(mia, pol())
      tickAll(40)
      assert(rec(db, "Mia").stats.gold == 777777, how .. ": Ofi holds Mia's gold")
      if how == "opens Gold" then ofi.C.Policy:Set("gold", "all") else assert(ofi.C.Policy:SetThreshold(3)) end
      tickAll(5)
      assert(db.policy.edit and ofi.C.Policy:Describe():find("not saved", 1, true), how .. ": her change, not saved")
      g("Ofi").rank = 3
      fire(ofi, "GUILD_ROSTER_UPDATE")
      tickAll(3)
      local P = ofi.C.Policy
      assert(not ofi.C.Roster:MeOfficer() and rec(db, "Mia").stats.gold == nil and not P:CanSee(false, false, "gold") and not db.policy.edit
        and not P:Describe():find("not saved", 1, true) and chatHas(ofi, "Guild Info's officer ranks do not include yours"),
        how .. ", then demoted: her change gives way, Mia's gold deleted: " .. tostring(rec(db, "Mia").stats.gold) .. " " .. P:Describe())
      for _, c in ipairs({ ofi, mia }) do leave(c) end
    end)
  end
  said[#said + 1] = "an officer demoted with a change not saved keeps none of it"

  -- (b) Mia reads Guild Info no more (a secret text, an encounter); Ofa closes Deaths (or the ranks to herself) and saves
  for _, how in ipairs({ "Deaths closed", "the ranks lowered" }) do
    isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Zed", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local ofa, ofb, mia, zed = char("Ofa", 0), char("Ofb", 1), char("Mia", 3, { money = 4444 }), char("Zed", 3)
      login(ofa, pol(true)); login(ofb, pol()); login(mia, pol()); login(zed, pol())
      tickAll(40)
      mia.infoSecret = true
      if how == "Deaths closed" then ofa.C.Policy:Set("deaths", "self") else assert(ofa.C.Policy:SetThreshold(0)) end
      assert(saveLine(ofa))
      zed.got, ofb.got = {}, {}
      tickAll(1)
      fire(mia, "PLAYER_DEAD")
      mia.o.money = 9999
      fire(mia, "PLAYER_MONEY")
      tickAll(30)
      local P = mia.C.Policy
      assert(not P:Settled() and P:Describe():find("newer policy", 1, true), how .. ": Mia waits for Guild Info: " .. P:Describe())
      assert(gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and m.msg:find("deaths=", 1, true) end) == 0, how .. ": no death of hers on GUILD")
      assert(gotFrom(ofb, mia, 1, function(m) return m.channel == "WHISPER" end) == 0, how .. ": nothing whispered meanwhile")
      -- out of it: Guild Info read, the new line routes her
      mia.infoSecret = false
      fire(mia, "GUILD_ROSTER_UPDATE")
      tickAll(10)
      assert(P:Settled() and (how == "Deaths closed" and P:Route("deaths") == "self" or P:Threshold() == 0), how .. ": read again, the new line routes her")
      if how == "Deaths closed" then assert(gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and m.msg:find("deaths=", 1, true) end) == 0, "still no death on GUILD")
      else assert(gotFrom(ofb, mia, 1, function(m) return m.channel == "WHISPER" end) == 0, "nothing whispered to Ofb, an officer no more") end
      for _, c in ipairs({ ofa, ofb, mia, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "a client that cannot read Guild Info again sends nothing after a save"

  -- (c) Ofa holds Mia's gold, logs out and is demoted while offline; Alto, her alt, logs in. And Ofa still an officer:
  -- Alto's login keeps it
  for _, demoted in ipairs({ true, false }) do
    isolated({ member("Ofa", 1), member("Alto", 3), member("Mia", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local db = pol()
      local ofa, mia = char("Ofa", 1), char("Mia", 3, { money = 777777 })
      login(ofa, db); login(mia, pol())
      tickAll(40)
      assert(rec(db, "Mia").stats.gold == 777777 and db.chars[ofa.name].officerOf == 7, "Ofa holds Mia's gold, an officer at her last login")
      leave(ofa)
      if demoted then g("Ofa").rank = 3 end
      local alto = char("Alto", 3)
      login(alto, db)
      tickAll(40)
      if demoted then
        assert(not alto.C.Roster:AccountOfficer() and rec(db, "Mia").stats.gold == nil, "Ofa demoted since: Alto's login purges her file")
      else
        assert(alto.C.Roster:AccountOfficer() and rec(db, "Mia").stats.gold == 777777, "Ofa an officer still: her file kept")
      end
      for _, c in ipairs({ alto, mia }) do leave(c) end
    end)
  end
  said[#said + 1] = "an alt's file an officer's only while the roster says so"

  -- (d) Ofa in a dungeon, Guild Info reading empty there: no save, the guild's text kept
  isolated({ member("Ofa", 0), member("Mia", 3) }, function()
    local TEXT = "Welcome to <Cute>! Raids Tue and Thu."
    INFO[7] = TEXT .. "\n" .. infoLine(pol().policy)
    local before = INFO[7]
    local ofa = char("Ofa", 0)
    login(ofa, pol(true))
    tickAll(30)
    ofa.o.instance = "party"
    ofa.env.C_GuildInfo.GetInfoText = function() return "" end
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tickAll(2)
    ofa.C.Policy:Set("gold", "all")
    local st = ofa.C.Policy:SaveState()
    assert(not st.ok and st.why == "Save outside an instance: Guild Info may read empty here." and not saveLine(ofa) and INFO[7] == before,
      "inside an instance nothing is saved: " .. tostring(st.why) .. " | " .. INFO[7])
    leave(ofa)
    said[#said + 1] = "no save inside an instance"
  end)

  -- (e) Ofo, rank 2, an officer by the line's ranks, logs in on a fresh install inside an instance (Guild Info a secret)
  isolated({ member("Ofo", 2), member("Mia", 3) }, function()
    local vis = { deaths = "self" }
    INFO[7] = infoLine({ vis = vis, threshold = 2 })
    local mia = char("Mia", 3, { money = 777777 })
    login(mia, pol(nil, vis, nil, 2))
    tickAll(40)
    local ofo = char("Ofo", 2)
    ofo.infoSecret = true
    login(ofo, {})
    tickAll(60)
    assert(not ofo.C.Policy:Settled() and rec(ofo.env.CuteDB, "Mia") and rec(ofo.env.CuteDB, "Mia").stats.gold == nil, "unsettled: Mia's whispered gold dropped")
    ofo.infoSecret = false
    fire(ofo, "GUILD_ROSTER_UPDATE")
    tickAll(60)
    assert(ofo.C.Roster:MeOfficer() and rec(ofo.env.CuteDB, "Mia").stats.gold == 777777, "out of it, an officer: asked again, Mia's gold came: " .. tostring(rec(ofo.env.CuteDB, "Mia").stats.gold))
    for _, c in ipairs({ ofo, mia }) do leave(c) end
    said[#said + 1] = "an officer by the line, logged in in an instance, gets what it dropped"
  end)

  -- (f) Guild Info holding a line with its fingerprint alone (0.6.0's first builds saved such a line), of a policy that
  -- opens Gold and Deaths; Mal, a member, sends that very policy
  isolated({ member("Ofa", 0), member("Mo", 3), member("Bea", 3), member("Mal", 3) }, function()
    local open = { vis = { gold = "all", deaths = "all" }, threshold = 1 }
    INFO[7] = ("Welcome to <Cute>! "):rep(20) .. "\n" .. infoLine(open, false)
    local mo, bea, mal = char("Mo", 3), char("Bea", 3, { money = 4242 }), char("Mal", 3)
    mo.got = {}
    login(mo, pol()); login(bea, pol()); login(mal, pol())
    tickAll(20)
    local P = bea.C.Policy
    assert(type(P.line) == "table" and not P.line.fp and not P:Settled() and P:Describe():find("cannot be read", 1, true), "the line read by nobody: " .. P:Describe())
    local diff = bea.C.Policy:Diff(open)
    mal.C.Comm.Queue({ msg = string.format("1P|%d|1|1/1|%s", EPOCH + mal.clock, diff:gsub("([%+%-])", ";%1"):sub(2)), first = true })
    tickAll(10)
    fire(bea, "PLAYER_DEAD")
    tickAll(20)
    assert(not P:Settled() and P:Route("gold") == "self" and P:Route("deaths") == "all" and gotFrom(mo, bea, 1, function(m) return m.channel == "GUILD" and (m.msg:find("gold=", 1, true) or m.msg:find("deaths=", 1, true)) ~= nil end) == 0,
      "a member's policy of the line's fingerprint routes nothing, and nothing of Bea's goes")
    for _, c in ipairs({ mo, bea, mal }) do leave(c) end
    said[#said + 1] = "a line with its fingerprint alone read by nobody"
  end)

  -- (g) Pell joins a guild whose Guild Info closes Deaths; the text reads empty until the roster's answer brings it
  isolated({ member("Ofa", 0), member("Pell", 3) }, function()
    INFO[7] = infoLine({ vis = { deaths = "self" }, threshold = 1 })
    local pell = char("Pell", 3, { inGuild = false })
    pell.inGuild = false
    login(pell, pol())
    tickAll(5)
    local blank, real = true, pell.env.C_GuildInfo.GetInfoText
    pell.env.C_GuildInfo.GetInfoText = function() if blank then return "" end return real() end
    pell.inGuild = true
    fire(pell, "PLAYER_GUILD_UPDATE", "player")
    assert(pell.C.Policy.line == nil and not pell.C.Policy:Settled(), "PLAYER_GUILD_UPDATE reads no Guild Info: nothing goes by the defaults")
    blank = false
    tickAll(2)
    assert(type(pell.C.Policy.line) == "table" and pell.C.Policy:Route("deaths") == "self", "the roster's answer reads it")
    leave(pell)
  end)
  isolated({ member("Ofa", 0), member("Mia", 3) }, function()
    INFO[7] = infoLine({ vis = { deaths = "self" }, threshold = 1 })
    local mia = char("Mia", 3)
    local real, slow = mia.env.C_Club.GetClubMembers, true
    mia.env.C_Club.GetClubMembers = function(...) if slow then return {} end return real(...) end
    login(mia, pol())
    tickAll(5)
    slow = false
    fire(mia, "CLUB_MEMBERS_UPDATED")
    tickAll(5)
    assert(type(mia.C.Policy.line) == "table" and not mia.C.Comm.holding, "the Guild Info event that came while C_Club listed nobody is read once it lists the guild")
    leave(mia)
    said[#said + 1] = "Guild Info read on the roster's answer"
  end)

  -- (h) Mal sends a hundred records, each with a new kind and enchant in every slot
  isolated({ member("Ofa", 0), member("Mal", 3) }, function()
    local ofa, mal = char("Ofa", 0), char("Mal", 3)
    login(ofa); login(mal)
    tickAll(45)
    for i = 1, 100 do
      local p = {}
      for _, s in ipairs({ 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }) do p[#p + 1] = s .. ":" .. (100 + i) .. "." .. s .. ":" .. (1000 + i) end
      mal.C.Comm.Queue({ msg = "1D|" .. mal.C.REGVER .. "|ench_kinds=" .. table.concat(p, " "):sub(1, 200), first = true })
      tickAll(1)
    end
    local most = 0
    for _, r in pairs(ofa.env.CuteDB.known.enchant or {}) do
      local nk, ne = 0, 0
      for _, kr in pairs(r.kinds or {}) do if kr.n == 1 and kr.who and kr.who[guidOf("Mal")] then nk = nk + 1 end end
      for _, er in pairs(r.ench or {}) do if er.n == 1 and er.who and er.who[guidOf("Mal")] then ne = ne + 1 end end
      most = math.max(most, nk, ne)
    end
    assert(most > 0 and most <= 4, "one voice keeps four kinds and enchants of its own a slot at most: " .. most)
    for _, c in ipairs({ ofa, mal }) do leave(c) end
    said[#said + 1] = "one voice four enchant kinds a slot"
  end)

  -- (i) Mal says level 35, the roster 30, every twenty seconds for three minutes
  isolated({ member("Ofa", 0), member("Mo", 3), member("Mal", 3) }, function()
    local mo, mal = char("Mo", 3), char("Mal", 3)
    login(mo); login(mal)
    tickAll(45)
    local a0 = mo.rosterAsked or 0
    for _ = 1, 9 do mal.C.Comm.Queue({ msg = "1D|" .. mal.C.REGVER .. "|level=" .. mal.C.Comm.b36(35), first = true }); tickAll(20) end
    local e = rec(mo.env.CuteDB, "Mal")
    assert(type(e.suspect) == "table" and e.stats.level ~= 35 and (mo.rosterAsked or 0) - a0 <= 20, "marked, the roster asked a few times: " .. ((mo.rosterAsked or 0) - a0))
    for _, c in ipairs({ mo, mal }) do leave(c) end
    said[#said + 1] = "a level said again and again marked"
  end)

  -- (j) Mal says Cute 99.0.0 is out; Ofa marks him untrusted; Mo's next login announces nothing
  isolated({ member("Ofa", 0), member("Mo", 3), member("Mal", 3) }, function()
    local ofa, mo, mal = char("Ofa", 0), char("Mo", 3), char("Mal", 3)
    login(ofa, pol(true)); login(mo, pol()); login(mal, pol())
    tickAll(45)
    mal.C.Comm.Queue({ msg = "1D|" .. mal.C.REGVER .. "|addon_ver=99.0.0", first = true })
    tickAll(3)
    ofa.C.Policy:SetUntrusted(guidOf("Mal"), true)
    ofa.C.Comm:SendPolicy()
    tickAll(10)
    assert(mo.C.Policy:Untrusted(guidOf("Mal")), "Mo holds the mark")
    local db = mo.env.CuteDB
    leave(mo)
    local mo2 = char("Mo", 3)
    mo2.clock = ofa.clock
    login(mo2, db)
    tickAll(15)
    mal.C.Comm.Queue({ msg = "1D|" .. mal.C.REGVER .. "|addon_ver=98.0.0", first = true })
    tickAll(3)
    assert(mo2.C.newer == nil and not chatHas(mo2, "is out"), "an untrusted member's version announces nothing: " .. tostring(mo2.C.newer))
    for _, c in ipairs({ ofa, mo2, mal }) do leave(c) end
    said[#said + 1] = "an untrusted member's version announces nothing"
  end)

  -- (k) Mal, a member, sends six junk policies ten seconds apart; then, untrusted, asks four times half a minute apart
  for _, line in ipairs({ true, false }) do
    isolated({ member("Ofa", 0), member("Mo", 3), member("Mal", 3) }, function()
      if line then INFO[7] = infoLine(pol().policy) end
      local ofa, mo, mal = char("Ofa", 0), char("Mo", 3), char("Mal", 3)
      login(ofa, pol(true)); login(mo, pol()); login(mal, pol())
      tickAll(65)
      local a0 = mo.rosterAsked or 0
      for i = 1, 6 do mal.C.Comm.Queue({ msg = string.format("1P|%d|1|1/1|-z%d", EPOCH + mal.clock, i), first = true }); tickAll(10) end
      assert((mo.rosterAsked or 0) - a0 <= 2, "a member's policies ask for no roster read: " .. ((mo.rosterAsked or 0) - a0))
      ofa.C.Policy:SetUntrusted(guidOf("Mal"), true)
      ofa.C.Comm:SendPolicy()
      tickAll(10)
      local p0 = msgs(ofa, "1P")
      for _ = 1, 4 do mal.C.Comm.Queue({ msg = "1R|" .. mal.o.guid .. "|0|0|" .. string.format("%016x", math.random(1, 2 ^ 30)), first = true }); tickAll(31) end
      assert(msgs(ofa, "1P") - p0 <= 1, "an untrusted member's asks: the policy once in five minutes: " .. (msgs(ofa, "1P") - p0))
      for _, c in ipairs({ ofa, mo, mal }) do leave(c) end
    end)
  end
  said[#said + 1] = "a member's policy asks for no roster read"

  -- (l) a 0.5.0 file (Ofa's policy, Mia's record with her gold); the account's first 0.6.0 login is Alto's in guild 8
  do
    local account = { version = "0.5.0", toldChanges = "0.5.0", chars = { ["Ofa-Forever"] = { counters = {} } },
      policy = { vis = { gold = "self", deaths = "self" }, by = "Ofa-Forever", mine = true, rank = 0, at = EPOCH, threshold = 1 },
      roster = { ["Mia-Forever"] = { seen = EPOCH + 1000, online = false, stats = { guid = guidOf("Mia"), level = 30, gold = 777777, addon_ver = "0.5.0" }, at = {} } } }
    local function club8(c)
      local cc = c.env.C_Club
      local gm, gi, gs = cc.GetClubMembers, cc.GetMemberInfo, cc.GetMemberInfoForSelf
      cc.GetGuildClubId = function() return c.inGuild and 8 or nil end
      cc.GetClubMembers = function(id) return gm(id == 8 and 7 or id) end
      cc.GetMemberInfo = function(id, i) return gi(id == 8 and 7 or id, i) end
      cc.GetMemberInfoForSelf = function(id) return gs(id == 8 and 7 or id) end
    end
    isolated({ member("Xo", 0), member("Alto", 3) }, function()
      local alto = char("Alto", 3)
      club8(alto)
      login(alto, account)
      tickAll(130)
      assert(not rec(account, "Mia") and account.knownClub ~= "8", "guild 8 takes none of it")
      leave(alto)
    end)
    isolated({ member("Ofa", 0), member("Mia", 3) }, function()
      g("Mia").online = false
      local ofa = char("Ofa", 0)
      login(ofa, account)
      tickAll(20)
      local r = rec(account, "Mia")
      assert(r and r.stats.gold == 777777 and account.policy.vis.deaths == "self" and ofa.C.Policy:Route("deaths") == "self" and account.policyClub == "7" and account.knownClub == "7",
        "guild 7, whose roster lists Mia, takes the file: her record and the officers' policy")
      assert(not account.policies["?"] and account.policies["8"] and not account.policies["8"].roster["Mia-Forever"], "and guild 8 keeps its own")
      leave(ofa)
    end)
    said[#said + 1] = "0.5.x's file the guild's whose roster lists it"
  end

  -- (m) a line that keeps Cute_Example's stat to the officers, taken before the module is on
  isolated({ member("Moda", 1), member("Pim", 3) }, function()
    INFO[7] = yezin.C.Policy.LineText(EPOCH, 1, "-_ex_heard-zo", true)
    local pim = newClient(charOf({ "Pim", 3, "", "MAGE", 30 }, { modules = { "Cute_Example" }, addonState = {} }))
    login(pim)
    tickAll(15)
    local P = pim.C.Policy
    assert(P:Holds() and P:Route("zone") == "self", "Pim routes by the line")
    local s0 = #pim.sent
    pim.C.Modules.Set("Cute_Example", true)
    tickAll(5)
    fire(pim, "PLAYER_LEVEL_UP", 31)
    tickAll(75)
    assert(pim.C.Stats.byId.ex_heard and P:Route("ex_heard") == "self" and P:Holds(), "the module on: its stat routes as the line says: " .. P:Route("ex_heard"))
    for i = s0 + 1, #pim.sent do assert(not (pim.sent[i].channel == "GUILD" and pim.sent[i].msg:find("ex_heard=", 1, true)), "not on GUILD: " .. pim.sent[i].msg) end
    local moda = newClient(charOf({ "Moda", 1, "", "MAGE", 30 }, { modules = { "Cute_Example" }, addonState = {} }))
    login(moda)
    tickAll(15)
    moda.C.Modules.Set("Cute_Example", true)
    tickAll(3)
    moda.C.Policy:Set("ex_heard", "self")
    assert(moda.C.Policy:Diff() == "-_ex_heard-zo" and moda.C.Policy:Route("zone") == "self", "Moda's click keeps the line's other choices: '" .. moda.C.Policy:Diff() .. "'")
    for _, c in ipairs({ pim, moda }) do leave(c) end
    said[#said + 1] = "a module's stat routes by the line once on"
  end)

  -- (n) Ofa saves the line; then opens Missing enchants and Empty slots without saving: Cy keeps what the word told him
  do
    local function wm(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 30, online = true } end
    isolated({ wm("Ofa", 0), wm("Ann", 3), wm("Bo", 3), wm("Cy", 3) }, function()
      local function wc(name, rank, items) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "WARRIOR", 30 }, { items = items })) end
      local ofa = wc("Ofa", 0, { [1] = "item:3001:0", [5] = "item:3005:7" })
      local ann = wc("Ann", 3, { [1] = "item:3001:0", [2] = "item:3002:2564", [5] = "item:3005:0" })
      local bo = wc("Bo", 3, { [1] = "item:3001:0", [2] = "item:3002:2564", [5] = "item:3005:7" })
      local cy = wc("Cy", 3, { [1] = "item:3001:0", [2] = "item:3002:0", [5] = "item:3005:7" })
      local ofaDb = { policy = { vis = {}, by = "Ofa-Forever", mine = true, rank = 0, at = EPOCH + 100, threshold = 1 } }
      login(ofa, ofaDb)
      for _, c in ipairs({ ann, bo, cy }) do login(c) end
      tickAll(150)
      assert(saveLine(ofa))
      tickAll(30)
      if SEEDED then
        ofa.env.CuteDB.known.watch = ofa.env.CuteDB.known.watch or {}
        ofa.env.CuteDB.known.watch[9] = ofa.C.Now() - 15 * 86400
        ofa.C.Comm:WordSoon()
        tickAll(12)
      end
      assert(cy.C.Stats.WordEnchant(2) and cy.C.Stats.WordEnchant(5) and (not SEEDED or cy.C.Rules.WordDoubted(9)), "Cy holds the officers' word")
      ofa.C.Policy:Set("unenchanted", "all")
      ofa.C.Policy:Set("empty_slots", "all")
      tickAll(30)
      assert(ofa.C.Policy:EditPending() and cy.C.Policy:Route("enchanted") == "self", "Ofa's change not saved; Cy routes by the line")
      assert(cy.C.Stats.WordEnchant(2) and cy.C.Stats.WordEnchant(5) and (not SEEDED or (cy.C.Rules.WordDoubted(9) and cy.C.Rules.SeedSlotState(9) == "doubted")),
        "Cy keeps what the word told him")
      for _, c in ipairs({ ofa, ann, bo, cy }) do leave(c) end
      said[#said + 1] = "an unsaved change costs the members nothing of the word"
    end)
  end

  -- (o) the smaller ones
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Mal", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, ofb, mia, mal = char("Ofa", 0), char("Ofb", 1), char("Mia", 3), char("Mal", 3)
    login(ofa, pol(true)); login(ofb, pol()); login(mia, pol()); login(mal, pol())
    ofa.C.Rules.WordParts = function() return { "n2=4.1", "x11=d" } end
    tickAll(60)
    -- the officers' word to one asker once in half an hour
    ofa.C.Comm:WordSoon(true)
    tickAll(20)
    local n0 = msgs(ofa, "1N")
    for _ = 1, 3 do mal.C.Comm.Queue({ msg = "1R|" .. mal.o.guid .. "|0|0|", first = true }); tickAll(181) end
    assert(msgs(ofa, "1N") - n0 <= 1, "the same word once to one asker: " .. (msgs(ofa, "1N") - n0))
    -- an item stamped far ahead: no later than its word
    ofb.C.Comm.Queue({ msg = string.format("1P|%d|1|1/1|u=%s@zzzzzzzz", EPOCH + ofb.clock, guidOf("Mia")), first = true })
    tickAll(5)
    tickAll(2)
    ofa.C.Policy:SetUntrusted(guidOf("Mia"), false)
    ofa.C.Comm:SendPolicy()
    tickAll(10)
    assert(not mal.C.Policy:Untrusted(guidOf("Mia")), "a mark stamped ahead undone by an officer's trust")
    -- the roster's minute: one refresh, on its answer
    local n, realRefresh = 0, mia.C.Roster.Refresh
    mia.C.Roster.Refresh = function(...) n = n + 1; return realRefresh(...) end
    tickAll(120)
    mia.C.Roster.Refresh = realRefresh
    assert(n <= 3, "two minutes quiet: a refresh a minute: " .. n)
    -- Broadcast now with a change not saved
    ofa.C.Policy:Set("gold", "all")
    ofa.C.Comm:Broadcast()
    assert(chatHas(ofa, "who sees what goes by Guild Info: Save to Guild Info to change it."), "Broadcast now says who sees what goes by Guild Info")
    -- the Me page's members' view waits for the save
    ofa.C.UI.meView = true
    ofa.C.UI:Open("me")
    assert(not ofa.C.UI.meView and texts(ofa):find("members go by Guild Info, save your change first", 1, true), "the members' view waits for the save")
    check(ofa.C.UI.frame, "officer me, a change not saved")
    ofa.C.UI.frame:Hide()
    for _, c in ipairs({ ofa, ofb, mia, mal }) do leave(c) end
  end)
  isolated({ member("Moda", 1) }, function()
    local state = {}
    local moda = newClient(charOf({ "Moda", 1, "", "MAGE", 30 }, { modules = { "Cute_Example" }, addonState = state }))
    login(moda)
    moda.C.Modules.Set("Cute_Example", true)
    assert(moda.addons[2].loaded and moda.C.Modules.OnKey("Cute_Example"), "ticked: on")
    local db = moda.env.CuteDB
    leave(moda)
    state.Cute_Example = state.Cute_Example or {}
    state.Cute_Example[moda.o.guid] = false -- (switched off at character select)
    local again = newClient(charOf({ "Moda", 1, "", "MAGE", 30 }, { modules = { "Cute_Example" }, addonState = state }))
    login(again, db)
    assert(not again.addons[2].loaded and state.Cute_Example[again.o.guid] == false and not again.C.Modules.OnKey("Cute_Example"), "switched off in the game's list: it stays off, its box unticked")
    leave(again)
  end)
  -- a module's stat the line keeps, held from before in a member's file, the module off on her client: purged
  isolated({ member("Moda", 1), member("Mia", 3) }, function()
    INFO[7] = yezin.C.Policy.LineText(EPOCH, 1, "-_ex_heard", true)
    local db = { roster = { ["Moda-Forever"] = { seen = EPOCH, online = false, stats = { guid = guidOf("Moda"), level = 30, ex_heard = 5 }, at = {} } } }
    local mia = char("Mia", 3)
    login(mia, db)
    tickAll(40)
    assert(rec(db, "Moda") and rec(db, "Moda").stats.ex_heard == nil and rec(db, "Moda").stats.level == 30, "a stat this client cannot name is not kept by a member's purge")
    leave(mia)
  end)
  said[#said + 1] = "the smaller ones"
  print("the sixth round: " .. table.concat(said, "; "))
end

-- 49: what the seventh round of review found (0.6.0), each case one that failed before its fix. (a) Addon version is
-- nobody's to set: closed, every member's whispers to the officers stopped and the Ready column went. (b) An alt of
-- the account is known by its GUID: a namesake officer of the guild vouches for no alt of another realm. (c) An
-- officer's change not saved waits for her while her member alt plays, and the alt is told nothing. (d) XP/hour goes
-- with Hours to 60, which the level, the XP and the pace rebuild. (e) The doubt after an officer's save survives a
-- /reload: the line read last does not come back. (f) A guild with no line: an officer demoted while away is purged
-- half a minute after the hello, whoever is online. (g) Who sees what waits for Guild Info to be read. (h) The game's
-- "the roster changed" with the text from before ends no wait, and an empty text at login is no line yet. (i) Who is
-- an officer for what others send goes by the line's ranks, and an untrusted officer's marks are taken by nobody. (j)
-- A change from before the guild had a line is no change once the line says the same. (k) 0.5.x's saved variables are
-- judged by what was saved, not by what this session heard before the roster listed anyone. (l) Namesakes the roster
-- names by the first name alone, told apart by the name the game gives each GUID. (m) The smaller ones: a click not
-- saved sends no word; a /reload says the word no more unasked, and an echo of it changes nothing; answers wait while
-- the client waits for the line; the ask after a save keeps ten seconds from any other
collectgarbage()
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function pol(mine, vis, at, thr)
    local copy = {}
    for k, v in pairs(vis or {}) do copy[k] = v end
    return { policy = { vis = copy, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = thr or 1 } }
  end
  local function rec(db, who) return db.roster[who .. "-Forever"] end
  local function g(name) for _, m in ipairs(GUILD) do if m.name == name .. "-Forever" then return m end end end
  local function chatHas(c, s) for _, l in ipairs(c.chat) do if l:find(s, 1, true) then return true end end return false end
  local function gotFrom(c, from, from0, test)
    local n = 0
    for i = from0 or 1, #(c.got or {}) do local m = c.got[i]; if m.from == from.sender and test(m) then n = n + 1 end end
    return n
  end
  local said = {}

  -- (a) a line that closes Addon version (an edited one), and Ofa's click on it
  isolated({ member("Ofa", 0), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = yezin.C.Policy.LineText(EPOCH, 1, tok("addon_ver", "self"), true)
    local ofa, mia, zed = char("Ofa", 0), char("Mia", 3), char("Zed", 3)
    login(ofa, pol(true)); login(mia, pol()); login(zed, pol())
    tickAll(60)
    local P = mia.C.Policy
    assert(P:Holds() and P:Vis("addon_ver") == "all" and P:Route("addon_ver") == "all", "a line that closes Addon version: everyone's all the same")
    assert(#mia.C.Roster:OfficerTargets() == 1 and rec(mia.env.CuteDB, "Ofa").stats.addon_ver ~= nil and rec(mia.env.CuteDB, "Zed").stats.ready ~= nil,
      "Mia whispers to Ofa and holds Zed's Ready: " .. #mia.C.Roster:OfficerTargets())
    assert(ofa.C.Policy:Set("addon_ver", "self") == false and ofa.C.Policy:Vis("addon_ver") == "all", "an officer's click on it is refused")
    -- (every id the whispers and Ready go by travels to everyone, whatever the officers close)
    local keep, all = mia.env.CuteDB.policy, { vis = {}, threshold = 1 }
    for _, def in ipairs(mia.C.Stats.list) do all.vis[def.id] = "self" end
    mia.env.CuteDB.policy = all
    P.ver = P.ver + 1
    local av, gd = P:Route("addon_ver"), P:Route("guid")
    mia.env.CuteDB.policy = keep
    P.ver = P.ver + 1
    assert(av == "all" and gd == "all", "everything closed: the version and the GUID still everyone's")
    for _, c in ipairs({ ofa, mia, zed }) do leave(c) end
    said[#said + 1] = "Addon version nobody's to set"
  end)

  -- (b) Bob's account holds an alt named like the guild's officer Anna, on another realm (officer of no guild, or
  -- with a GUID of its own), and Mia's gold from before
  for _, alt in ipairs({ { officerOf = false }, { guid = "Player-9-0000A17" } }) do
    isolated({ member("Anna", 1), member("Bob", 3), member("Mia", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local db = pol()
      alt.counters = {}
      db.chars = { ["Anna-Elsewhere"] = alt }
      db.roster = { ["Mia-Forever"] = { seen = EPOCH, online = false, stats = { guid = guidOf("Mia"), level = 30, gold = 777777, addon_ver = "0.6.0" }, at = {} } }
      local anna, bob = char("Anna", 1), char("Bob", 3)
      login(anna, pol(true)); login(bob, db)
      tickAll(40)
      assert(not bob.C.Roster:AccountOfficer() and rec(db, "Mia").stats.gold == nil, "a namesake officer vouches for no alt of Bob's: Mia's gold purged")
      for _, c in ipairs({ anna, bob }) do leave(c) end
    end)
  end
  said[#said + 1] = "an alt known by its GUID"

  -- (c) Ofa opens Gold and does not save; Alto, her alt, plays; Ofa logs in again (and Ofb saved meanwhile, or not)
  for _, saved in ipairs({ false, true }) do
    isolated({ member("Ofa", 1), member("Ofb", 0), member("Alto", 3), member("Mia", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local db = pol()
      local ofa = char("Ofa", 1)
      login(ofa, db)
      tickAll(30)
      ofa.C.Policy:Set("gold", "all")
      assert(db.policy.edit and ofa.C.Policy:Vis("gold") == "all", "Ofa's change, not saved")
      local t = ofa.clock
      leave(ofa)
      local alto = char("Alto", 3)
      alto.clock = t
      login(alto, db)
      tickAll(30)
      assert(not chatHas(alto, "your change") and alto.C.Policy:Settled() and alto.C.Policy:Route("gold") == "self", "Alto routes by the line, told nothing")
      if saved then
        local ofb = char("Ofb", 0)
        login(ofb, pol())
        tickAll(20)
        ofb.C.Policy:Set("deaths", "self")
        assert(saveLine(ofb))
        tickAll(5)
        leave(ofb)
      end
      t = alto.clock
      leave(alto)
      local ofa2 = char("Ofa", 1)
      ofa2.clock = t
      login(ofa2, db)
      tickAll(30)
      local P = ofa2.C.Policy
      if saved then
        assert(chatHas(ofa2, "another officer saved the policy to Guild Info: your change, not saved, gave way to it.") and P:Vis("gold") == "self"
          and P:Route("deaths") == "self" and not P:EditPending(), "another officer saved meanwhile: her change gave way, and she is told")
      else
        assert(P:EditPending() and P:Vis("gold") == "all" and not chatHas(ofa2, "gave way"), "her change waited for her: " .. P:Describe())
      end
      leave(ofa2)
    end)
  end
  said[#said + 1] = "an officer's change not saved waits for her"

  -- (d) Hours to 60 closed alone
  do
    local P = yezin.C.Policy
    local keep = yezin.env.CuteDB.policy
    yezin.env.CuteDB.policy = { vis = { to60 = "self" }, threshold = 1 }
    P.ver = P.ver + 1
    local r, w = P:Route("xp_hour"), P:KeptWith("xp_hour")
    yezin.env.CuteDB.policy = keep
    P.ver = P.ver + 1
    assert(r == "self" and w == "to60", "Hours to 60 closed: XP/hour goes with it: " .. r .. " " .. tostring(w))
    said[#said + 1] = "XP/hour with Hours to 60"
  end

  -- (e) 48(b), then Mia reloads while her Guild Info is still the game's copy from before and her asks go unanswered
  -- (a secret text kept the line nil whether or not the doubt survived, so the case could not fail: the ninth round)
  for _, how in ipairs({ "Deaths closed", "the ranks lowered" }) do
    isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Zed", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local ofa, ofb, mia, zed = char("Ofa", 0), char("Ofb", 1), char("Mia", 3, { money = 4444 }), char("Zed", 3)
      login(ofa, pol(true)); login(ofb, pol()); login(mia, pol()); login(zed, pol())
      tickAll(40)
      local old = INFO[7]
      mia.env.C_GuildInfo.GetInfoText = function() return old end
      mia.env.C_GuildInfo.GuildRoster = function() end
      if how == "Deaths closed" then ofa.C.Policy:Set("deaths", "self") else assert(ofa.C.Policy:SetThreshold(0)) end
      assert(saveLine(ofa))
      tickAll(2)
      assert(mia.C.Policy.doubt, how .. ": Mia waits for Guild Info")
      local db = mia.env.CuteDB
      leave(mia)
      local mia2 = char("Mia", 3, { money = 4444 })
      local pinned, realGet, realAsk = true, mia2.env.C_GuildInfo.GetInfoText, mia2.env.C_GuildInfo.GuildRoster
      mia2.env.C_GuildInfo.GetInfoText = function(...) if pinned then return old end return realGet(...) end
      mia2.env.C_GuildInfo.GuildRoster = function() end
      zed.got, ofb.got = {}, {}
      login(mia2, db, true)
      fire(mia2, "GUILD_ROSTER_UPDATE", true)
      fire(mia2, "PLAYER_DEAD")
      tickAll(30)
      local P = mia2.C.Policy
      assert(not P:Settled() and P.doubt, how .. ": after the /reload she still waits: " .. P:Describe())
      assert(gotFrom(zed, mia2, 1, function(m) return m.channel == "GUILD" and m.msg:find("deaths=", 1, true) end) == 0, how .. ": no death of hers on GUILD")
      assert(gotFrom(ofb, mia2, 1, function(m) return m.channel == "WHISPER" end) == 0, how .. ": nothing whispered meanwhile")
      pinned = false
      mia2.env.C_GuildInfo.GuildRoster = realAsk
      fire(mia2, "GUILD_ROSTER_UPDATE")
      tickAll(10)
      assert(P:Settled() and (how == "Deaths closed" and P:Route("deaths") == "self" or P:Threshold() == 0), how .. ": read again, the new line routes her")
      assert(how ~= "Deaths closed" or gotFrom(zed, mia2, 1, function(m) return m.channel == "GUILD" and m.msg:find("deaths=", 1, true) end) == 0, how .. ": her death never on GUILD")
      for _, c in ipairs({ ofa, ofb, mia2, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "a doubt survives a /reload"

  -- (f) no line: Ofi, an officer, closes Deaths and holds Mia's gold; demoted while away, she logs in again (alone, or
  -- with Ofa online holding the same word)
  for _, other in ipairs({ false, true }) do
    isolated({ member("Ofa", 0), member("Ofi", 1), member("Mia", 3) }, function()
      local db = pol()
      local ofa = other and char("Ofa", 0) or nil
      local ofi, mia = char("Ofi", 1), char("Mia", 3, { money = 777777 })
      if ofa then login(ofa, pol()) end
      login(ofi, db); login(mia, pol())
      tickAll(40)
      ofi.C.Policy:Set("deaths", "self")
      ofi.C.Comm:PolicySoon()
      tickAll(10)
      assert(rec(db, "Mia").stats.gold == 777777 and db.chars[ofi.name].officerOf == 7, "Ofi holds Mia's gold, an officer at her last login")
      local t = ofi.clock
      leave(ofi)
      g("Ofi").rank = 3
      local ofi2 = char("Ofi", 3)
      ofi2.clock = t
      login(ofi2, db)
      tickAll(90)
      assert(not ofi2.C.Roster:MeOfficer() and rec(db, "Mia").stats.gold == nil, (other and "Ofa online" or "alone") .. ": half a minute after the hello her file is a member's: " .. tostring(rec(db, "Mia").stats.gold))
      for _, c in ipairs({ ofa, ofi2, mia }) do if c then leave(c) end end
    end)
  end
  said[#said + 1] = "the first purge waits half a minute at most"

  -- (g) Ofa logs in inside a dungeon, Guild Info reading empty there
  isolated({ member("Ofa", 0), member("Mia", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa = char("Ofa", 0)
    ofa.o.instance = "party"
    local real = ofa.env.C_GuildInfo.GetInfoText
    ofa.env.C_GuildInfo.GetInfoText = function() return "" end
    login(ofa, pol(true))
    tickAll(10)
    local P = ofa.C.Policy
    assert(P.line == nil and ofa.C.Roster:MeOfficer(), "inside, Guild Info not read yet")
    assert(not P:Set("gold", "all") and P:Vis("gold") == "self" and not P:SetThreshold(2) and not P:Reset() and not P:Unsaved(), "who sees what waits for Guild Info")
    ofa.C.UI:Open("settings", "vis")
    assert(texts(ofa):find("Saving waits for Guild Info to be read.", 1, true) and checkBox(ofa, function(cb) return cb.statId == "gold" end)
      and not checkBox(ofa, function(cb) return cb.statId == "gold" and not cb.__disabled end), "Settings shows the pairs greyed, and why")
    check(ofa.C.UI.frame, "officer settings, Guild Info not read yet")
    ofa.C.UI.frame:Hide()
    ofa.o.instance = nil
    ofa.env.C_GuildInfo.GetInfoText = real
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tickAll(5)
    assert(P:Holds() and P:Route("gold") == "self" and not chatHas(ofa, "another officer saved"), "out of it: the line read, nothing said that was not so")
    leave(ofa)
    said[#said + 1] = "who sees what waits for Guild Info"
  end)

  -- (h) Mia's Guild Info is the game's copy from before, and her own asks go unanswered: Ofa closes Zone and saves,
  -- and the game says the roster changed
  isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol(nil, { zone = "all" }).policy)
    local ofa, mia, zed = char("Ofa", 1), char("Mia", 3), char("Zed", 3)
    login(ofa, pol(true, { zone = "all" })); login(mia, pol(nil, { zone = "all" })); login(zed, pol(nil, { zone = "all" }))
    tickAll(70)
    local old, pinned = INFO[7], true
    local realGet, realAsk = mia.env.C_GuildInfo.GetInfoText, mia.env.C_GuildInfo.GuildRoster
    mia.env.C_GuildInfo.GetInfoText = function(...) if pinned then return old end return realGet(...) end
    mia.env.C_GuildInfo.GuildRoster = function() mia.rosterAsked = (mia.rosterAsked or 0) + 1 end
    ofa.C.Policy:Set("zone", "self")
    assert(saveLine(ofa))
    tick(ofa, 1)
    zed.got = {}
    local P = mia.C.Policy
    assert(P.doubt and not P:Settled(), "Mia waits for Guild Info")
    fire(mia, "GUILD_ROSTER_UPDATE", true)
    assert(P.doubt and not P:Settled() and P:Route("zone") == "all", "the game's 'the roster changed', the text from before: no answer")
    mia.o.zone = "Elsewhere"; mia.C.Sample.values.zone = "Elsewhere"; mia.C.Sample.dirty.zone = true; mia.C.Comm:Changed()
    tick(mia, 2); tick(zed, 2)
    assert(gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and m.msg:find("zone=Elsewhere", 1, true) end) == 0, "her zone stays off GUILD")
    pinned = false
    mia.env.C_GuildInfo.GuildRoster = realAsk
    fire(mia, "GUILD_ROSTER_UPDATE", false)
    tickAll(3)
    assert(P:Settled() and P:Route("zone") == "self" and gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and m.msg:find("zone=Elsewhere", 1, true) end) == 0, "the answer: the new line routes her")
    for _, c in ipairs({ ofa, mia, zed }) do leave(c) end
  end)
  isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
    local NEW = EPOCH + 500
    INFO[7] = infoLine(pol(nil, { zone = "self" }).policy, true, NEW)
    local ofa, zed = char("Ofa", 1), char("Zed", 3)
    login(ofa, pol(true, { zone = "self" }, NEW)); login(zed, pol(nil, { zone = "self" }, NEW))
    tickAll(70)
    zed.got = {}
    local mia = char("Mia", 3, { zone = "Secretplace" })
    local cold, realGet, realAsk = true, mia.env.C_GuildInfo.GetInfoText, mia.env.C_GuildInfo.GuildRoster
    mia.env.C_GuildInfo.GetInfoText = function(...) if cold then return "" end return realGet(...) end
    mia.env.C_GuildInfo.GuildRoster = function() mia.rosterAsked = (mia.rosterAsked or 0) + 1 end
    login(mia, pol(nil, { zone = "all" }))
    fire(mia, "GUILD_ROSTER_UPDATE", true)
    assert(mia.C.Policy.line == nil and not mia.C.Policy:Settled(), "an empty text at login is no line yet")
    for _ = 1, 9 do tick(mia, 1); tick(zed, 1); tick(ofa, 1) end
    cold = false
    mia.env.C_GuildInfo.GuildRoster = realAsk
    fire(mia, "GUILD_ROSTER_UPDATE", false)
    tickAll(10)
    assert(mia.C.Policy:Route("zone") == "self" and gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and m.msg:find("Secretplace", 1, true) end) == 0,
      "the roster's answer brings the line, and her zone never went on GUILD")
    for _, c in ipairs({ ofa, mia, zed }) do leave(c) end
    said[#said + 1] = "a read of the text from before ends no wait"
  end)

  -- (i) Ofa, who cannot save, raises the ranks to 2; Rae, of rank 2, sends a policy marking Mia untrusted. Then Ofa
  -- marks Ofb, an officer, untrusted, and Ofb's copy marks Mo
  isolated({ member("Ofa", 1), member("Ofb", 1), member("Mo", 3), member("Rae", 2), member("Mia", 3) }, function()
    INFO_EDIT = 0
    INFO[7] = infoLine(pol().policy)
    local ofa, ofb, mo, rae, mia = char("Ofa", 1), char("Ofb", 1), char("Mo", 3), char("Rae", 2), char("Mia", 3)
    login(ofa, pol(true)); login(ofb, pol()); login(mo, pol()); login(rae, pol()); login(mia, pol())
    tickAll(70)
    assert(ofa.C.Policy:SetThreshold(2))
    ofa.C.Comm:PolicySoon()
    tickAll(5)
    assert(ofa.C.Policy:EditPending() and not ofa.C.Policy:SaveState().ok, "Ofa's ranks raised, not saved")
    local now = math.floor(rae.C.ServerNow())
    rae.C.Comm.Queue({ msg = "1P|" .. now .. "|2|1/1|u=" .. mia.o.guid .. "@" .. rae.C.Comm.b36(now), first = true })
    tickAll(3)
    ofa.C.Comm:Broadcast()
    tickAll(8)
    assert(not ofa.C.Policy:Untrusted(mia.o.guid) and not mo.C.Policy:Untrusted(mia.o.guid), "a rank-2 copy is no officer, Ofa's change not saved or not")
    ofa.C.Policy:SetUntrusted(ofb.o.guid, true)
    ofa.C.Comm:PolicySoon()
    tickAll(8)
    assert(mo.C.Policy:Untrusted(ofb.o.guid), "Mo holds Ofb untrusted")
    local now2 = math.floor(ofb.C.ServerNow())
    ofb.C.Comm.Queue({ msg = "1P|" .. now2 .. "|1|1/1|u=" .. mo.o.guid .. "@" .. ofb.C.Comm.b36(now2), first = true })
    tickAll(5)
    assert(not mia.C.Policy:Untrusted(mo.o.guid) and not ofa.C.Policy:Untrusted(mo.o.guid), "an untrusted officer's marks are taken by nobody")
    for _, c in ipairs({ ofa, ofb, mo, rae, mia }) do leave(c) end
    said[#said + 1] = "officers by the line's ranks, an untrusted one heard by nobody"
  end)

  -- (j) no line: Ofa opens Gold; Ofb takes her word and saves it; then Ofa closes Deaths
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3) }, function()
    local ofa, ofb, mia = char("Ofa", 0), char("Ofb", 1), char("Mia", 3)
    login(ofa, pol(true)); login(ofb, pol()); login(mia, pol())
    tickAll(40)
    local P = ofa.C.Policy
    assert(P.line == false)
    P:Set("gold", "all")
    ofa.C.Comm:PolicySoon()
    tickAll(10)
    assert(ofb.C.Policy:Vis("gold") == "all" and saveLine(ofb))
    tickAll(30)
    assert(P:Holds() and not P:Unsaved() and not P:Describe():find("not saved", 1, true), "Ofb saved what Ofa changed: nothing of hers unsaved: " .. P:Describe())
    P:Set("deaths", "self")
    ofa.C.Comm:PolicySoon()
    tickAll(70)
    assert(P:Settled() and P:Vis("deaths") == "self" and P:EditPending() and not chatHas(ofa, "gave way"), "her next click is hers until she saves it")
    for _, c in ipairs({ ofa, ofb, mia }) do leave(c) end
    said[#said + 1] = "a change from before the line, the line saying the same, no change"
  end)

  -- (k) a 0.5.x file (Ofa's policy, Mia's gold) and a roster that lists nobody for forty seconds at login
  do
    local function club8(c)
      local cc = c.env.C_Club
      local gm, gi, gs = cc.GetClubMembers, cc.GetMemberInfo, cc.GetMemberInfoForSelf
      cc.GetGuildClubId = function() return c.inGuild and 8 or nil end
      cc.GetClubMembers = function(id) return gm(id == 8 and 7 or id) end
      cc.GetMemberInfo = function(id, i) return gi(id == 8 and 7 or id, i) end
      cc.GetMemberInfoForSelf = function(id) return gs(id == 8 and 7 or id) end
    end
    local function slowly(c)
      local real = c.env.C_Club.GetClubMembers
      c.slow = true
      c.env.C_Club.GetClubMembers = function(...) if c.slow then return {} end return real(...) end
    end
    local function account05()
      return { version = "0.5.0", toldChanges = "0.5.0", chars = { ["Ofa-Forever"] = { counters = {} } },
        policy = { vis = { gold = "self", deaths = "self" }, by = "Ofa-Forever", mine = true, rank = 0, at = EPOCH, threshold = 1 },
        roster = { ["Mia-Forever"] = { seen = EPOCH + 1000, online = false, stats = { guid = guidOf("Mia"), level = 30, gold = 777777, addon_ver = "0.5.0" }, at = {} } } }
    end
    -- parked by Alto's guild 8; Ofa's guild 7, its roster slow, Bo online
    local account = account05()
    isolated({ member("Xo", 0), member("Alto", 3) }, function()
      local alto = char("Alto", 3)
      club8(alto)
      login(alto, account)
      tickAll(130)
      leave(alto)
    end)
    assert(account.policies and account.policies["?"], "guild 8 parked the file")
    isolated({ member("Ofa", 0), member("Mia", 3), member("Bo", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      g("Mia").online = false
      local bo = char("Bo", 3, { money = 5555 })
      login(bo, pol())
      tickAll(20)
      local ofa = char("Ofa", 0)
      slowly(ofa)
      login(ofa, account)
      tickAll(40)
      ofa.slow = false
      fire(ofa, "CLUB_MEMBERS_UPDATED")
      -- (the ask went once the roster read; the answers two to forty seconds on)
      tickAll(45)
      local r = rec(account, "Mia")
      assert(r and r.stats.gold == 777777 and account.policies["?"] == nil and rec(account, "Bo"), "guild 7 takes its file, the slow roster notwithstanding")
      for _, c in ipairs({ ofa, bo }) do leave(c) end
    end)
    -- Alto's first login, in guild 8, its roster slow, Xo online
    local fresh = account05()
    isolated({ member("Xo", 3), member("Alto", 3) }, function()
      local xo = char("Xo", 3)
      club8(xo)
      login(xo, { policyClub = "8", knownClub = "8" })
      tickAll(20)
      local alto = char("Alto", 3)
      club8(alto)
      slowly(alto)
      login(alto, fresh)
      tickAll(40)
      alto.slow = false
      fire(alto, "CLUB_MEMBERS_UPDATED")
      tickAll(130)
      local parked = fresh.policies and fresh.policies["?"]
      assert(parked and rec(parked, "Mia") and fresh.policyClub == "8" and fresh.knownClub ~= "8" and not (fresh.policy and fresh.policy.by == "Ofa-Forever") and not rec(fresh, "Mia"),
        "guild 8 takes none of it, the slow roster notwithstanding")
      for _, c in ipairs({ xo, alto }) do leave(c) end
    end)
    said[#said + 1] = "0.5.x's file judged by what was saved"
  end

  -- (l) two Helgas the roster names "Helga" alone; the channel names them with their surnames, and so does the name
  -- the game gives each GUID
  do
    local people = { { "Ofa", "Kay", 0 }, { "Helga", "Bluntforce", 3 }, { "Helga", "Ironfist", 3 } }
    local function gid(p) return guidOf(p[1] .. " " .. p[2]) end
    local list = {}
    for i, p in ipairs(people) do list[i] = { name = p[1], guidName = p[1] .. " " .. p[2], guid = gid(p), rank = p[3], rankName = p[3] <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true } end
    local function mk(p) local o = charOf({ p[1], p[3], "", "MAGE", 30 }); o.surname, o.sender, o.guid = p[2], p[1] .. " " .. p[2], gid(p); return newClient(o) end
    isolated(list, function()
      local ofa, h1, h2 = mk(people[1]), mk(people[2]), mk(people[3])
      login(ofa); login(h1); login(h2)
      tickAll(60)
      local db = ofa.env.CuteDB.roster
      assert(db["Helga Bluntforce"] and db["Helga Bluntforce"].stats.guid == gid(people[2]) and db["Helga Ironfist"] and db["Helga Ironfist"].stats.guid == gid(people[3]),
        "each namesake's record keeps her GUID")
      local n, extra = 0, 0
      for _, r in ipairs(ofa.C.Roster:Rows()) do
        if r.name == "Helga" and r.addon then n = n + 1 end
        if not r.guild and not r.me then extra = extra + 1 end
      end
      assert(n == 2 and extra == 0, "both rows show their Cute, no row of a record nobody claims: " .. n .. " " .. extra)
      for _, c in ipairs({ ofa, h1, h2 }) do leave(c) end
    end)
    said[#said + 1] = "namesakes told apart by the GUID's name"
  end

  -- (m) the smaller ones. The officers' word: a click not saved sends none; a /reload says it no more, unasked; an echo
  -- of it changes nothing
  isolated({ member("Ofa", 0), member("Mo", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofaDb = pol(true)
    local ofa, mo = char("Ofa", 0), char("Mo", 3)
    login(ofa, ofaDb); login(mo, pol())
    local small, big = { "n2=4.1", "x11=d" }, {}
    for i = 1, 40 do big[i] = string.format("b%d:%d:s=Boss number %d", 2000 + i, 30, i) end
    local function stub(c) c.C.Rules.WordParts = function() if c.C.Policy:EditPending() then return big end return small end end
    stub(ofa)
    tickAll(60)
    ofa.C.Comm:WordSoon(true)
    tickAll(20)
    local n0 = msgs(ofa, "1N")
    assert(n0 >= 1 and mo.C.Rules.WordStamp() > 0, "Mo holds Ofa's word")
    ofa.C.Policy:Set("gold_earned", "self")
    ofa.C.Comm:PolicySoon()
    tickAll(70)
    assert(msgs(ofa, "1N") == n0, "a click not saved sends no word: " .. (msgs(ofa, "1N") - n0))
    ofa.C.Policy:Set("gold_earned", "all")
    tickAll(70)
    local dirt, real = 0, mo.C.Rules.Dirty
    mo.C.Rules.Dirty = function(...) dirt = dirt + 1; return real(...) end
    for _, m in ipairs(ofa.sent) do if m.msg:sub(1, 2) == "1N" then mo.C.Comm:Receive(m.msg, "GUILD", ofa.sender) end end
    mo.C.Rules.Dirty = real
    assert(dirt == 0, "an echo of the word held changes nothing: " .. dirt)
    local t = ofa.clock
    leave(ofa)
    local ofa2 = char("Ofa", 0)
    ofa2.clock = t
    login(ofa2, ofaDb, true)
    stub(ofa2)
    tickAll(40)
    assert(msgs(ofa2, "1N") == 0, "a /reload says the word Mo holds no more, unasked: " .. msgs(ofa2, "1N"))
    for _, c in ipairs({ ofa2, mo }) do leave(c) end
  end)
  -- answers wait while the client waits for the line; the ask after a save keeps ten seconds from any other
  isolated({ member("Ofa", 0), member("Mia", 3), member("Nia", 3), member("Noa", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, mia = char("Ofa", 0), char("Mia", 3, { money = 1000 })
    login(ofa, pol(true)); login(mia, pol())
    -- (past Mia's own statistics pass, a minute and a half after her hello)
    tickAll(130)
    fire(mia, "PLAYER_GUILD_UPDATE", "player")
    local a0 = mia.rosterAsked or 0
    tickAll(3)
    mia.o.instance = "party"
    mia.infoSecret = true
    ofa.C.Policy:Set("zone", "self")
    assert(saveLine(ofa))
    tickAll(1)
    assert(mia.C.Policy.doubt and (mia.rosterAsked or 0) == a0, "the ask after the save waits ten seconds from the last: " .. ((mia.rosterAsked or 0) - a0))
    tickAll(8)
    assert((mia.rosterAsked or 0) == a0 + 1, "then asks: " .. ((mia.rosterAsked or 0) - a0))
    local function queued1F() local n = 0; for _, m in ipairs(mia.C.Comm.out) do if type(m) == "table" and (m.msg or ""):sub(1, 2) == "1F" then n = n + 1 end end return n end
    for _, who in ipairs({ "Nia", "Noa" }) do
      local c = char(who, 3)
      login(c, pol())
      mia.o.money = mia.o.money + 100
      fire(mia, "PLAYER_MONEY")
      tickAll(40)
    end
    assert(not mia.C.Policy:Settled() and queued1F() == 0, "while Mia waits for the line, the asks' answers wait too: " .. queued1F())
    mia.o.instance = nil
    mia.infoSecret = false
    local s0 = msgs(mia, "1F")
    fire(mia, "GUILD_ROSTER_UPDATE")
    tickAll(40)
    assert(mia.C.Policy:Settled() and msgs(mia, "1F") > s0, "settled: the answer goes, once")
    for _, c in ipairs({ ofa, mia }) do leave(c) end
  end)
  said[#said + 1] = "the smaller ones"
  print("the seventh round: " .. table.concat(said, "; "))
end

-- 50: what the eighth round of review found (0.6.0), each case one that failed before its fix. (a) No line read in an
-- earlier session stands for this one: a member who was away when an officer saved, logging in or reloading where
-- Guild Info reads empty (cold at login, or inside an instance), sends nothing until a read says something, and a guild
-- that had no line is no exception. (b) The three paces go together. (c) A 0.5.x file whose setter the roster cannot
-- name is purged. (d) Save to Guild Info waits while Guild Info is to be read again: another officer's save heard, or
-- its own not read back yet. (e) An officer who does not hold the line sends no policy. (f) A member's Ready tooltip on
-- an officer's client counts what the member's client counted. (g) The smaller ones: an officer's ranks raised and not
-- saved whisper to nobody new; a purge routes each id once
collectgarbage()
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function pol(mine, vis, at, thr)
    local copy = {}
    for k, v in pairs(vis or {}) do copy[k] = v end
    return { policy = { vis = copy, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = thr or 1 } }
  end
  local function rec(db, who) return db.roster[who .. "-Forever"] end
  local function chatHas(c, s) for _, l in ipairs(c.chat) do if l:find(s, 1, true) then return true end end return false end
  local function gotFrom(c, from, from0, test)
    local n = 0
    for i = from0 or 1, #(c.got or {}) do local m = c.got[i]; if m.from == from.sender and test(m) then n = n + 1 end end
    return n
  end
  local function secret(m) return m.channel == "GUILD" and m.msg:find("Secretplace", 1, true) end
  local said = {}

  -- (a) Mia reads the line (or a guild with no line) and logs out; Ofa closes Zone and saves; Mia logs in again, two
  -- minutes or an hour on, with Guild Info reading empty: cold at login outside (the game's answer to her ask a few
  -- seconds away), or inside a dungeon
  for _, how in ipairs({ "cold", "cold, no line before", "inside", "inside, no line before", "inside, no line before, an hour on" }) do
    isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
      local noLine = how:find("no line before", 1, true) ~= nil
      INFO[7] = noLine and "Welcome to <Cute>!" or infoLine(pol().policy)
      local ofa, zed, mia = char("Ofa", 1), char("Zed", 3), char("Mia", 3)
      local db = pol()
      login(ofa, pol(true)); login(zed, pol()); login(mia, db)
      tickAll(70)
      assert(mia.C.Policy:Settled() and mia.C.Policy:Route("zone") == "all", how .. ": Mia read Guild Info")
      leave(mia)
      assert(ofa.C.Policy:Set("zone", "self") and saveLine(ofa))
      tickAll(20)
      assert(zed.C.Policy:Route("zone") == "self", how .. ": Zed routes by the new line")
      leave(ofa)
      tickAll(how:find("an hour", 1, true) and 3600 or 100)
      zed.got = {}
      local inside = how:find("inside", 1, true) ~= nil
      local mia2 = char("Mia", 3, { zone = "Secretplace", instance = inside and "party" or nil })
      local cold, realGet, realAsk = true, mia2.env.C_GuildInfo.GetInfoText, mia2.env.C_GuildInfo.GuildRoster
      mia2.env.C_GuildInfo.GetInfoText = function(...) if cold then return "" end return realGet(...) end
      -- (cold: the game's answer to her asks is slow too)
      if not inside then mia2.env.C_GuildInfo.GuildRoster = function() mia2.rosterAsked = (mia2.rosterAsked or 0) + 1 end end
      login(mia2, db)
      if not inside then fire(mia2, "GUILD_ROSTER_UPDATE", true) end
      fire(mia2, "PLAYER_DEAD")
      for _ = 1, inside and 30 or 8 do tick(mia2, 1); tick(zed, 1) end
      local P = mia2.C.Policy
      assert(not P:Settled() and P.line == nil, how .. ": the empty text is no answer, and no line from before stands: " .. P:Describe())
      assert(gotFrom(zed, mia2, 1, secret) == 0 and gotFrom(zed, mia2, 1, function(m) return m.channel == "GUILD" and m.msg:sub(1, 2) ~= "1R" end) == 0,
        how .. ": nothing of hers on GUILD meanwhile: " .. gotFrom(zed, mia2, 1, secret))
      -- out of it (or the game's answer come): the new line routes her
      cold = false
      mia2.o.instance = nil
      mia2.env.C_GuildInfo.GuildRoster = realAsk
      fire(mia2, "GUILD_ROSTER_UPDATE")
      tickAll(20)
      assert(P:Settled() and P:Route("zone") == "self" and gotFrom(zed, mia2, 1, secret) == 0, how .. ": read, the new line routes her, her zone never on GUILD")
      for _, c in ipairs({ mia2, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "no line from an earlier session stands"

  -- (b) the paces: Hours to 60, XP/hour and XP/hour today, each closed alone, close all three; the line says so too
  do
    local P = yezin.C.Policy
    local keep = yezin.env.CuteDB.policy
    for _, id in ipairs({ "to60", "xp_hour", "xp_session" }) do
      yezin.env.CuteDB.policy = { vis = { [id] = "self" }, threshold = 1 }
      P.ver = P.ver + 1
      for _, other in ipairs({ "to60", "xp_hour", "xp_session" }) do
        assert(P:Route(other) == "self", id .. " closed: " .. other .. " goes with it")
      end
    end
    yezin.env.CuteDB.policy = keep
    P.ver = P.ver + 1
  end
  isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol(nil, { xp_hour = "self" }).policy)
    local ofa, mia, zed = char("Ofa", 1), char("Mia", 3), char("Zed", 3)
    login(ofa, pol(true, { xp_hour = "self" })); login(mia, pol(nil, { xp_hour = "self" })); login(zed, pol(nil, { xp_hour = "self" }))
    tickAll(70)
    zed.got = {}
    for _ = 1, 20 do mia.o.xp = (mia.o.xp or 0) + 37; fire(mia, "PLAYER_XP_UPDATE", "player"); tickAll(60) end
    assert(gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and (m.msg:find("xp_session=", 1, true) or m.msg:find("to60=", 1, true) or m.msg:find("xp_hour=", 1, true)) end) == 0,
      "XP/hour closed: none of the paces of Mia's on GUILD")
    local r = rec(zed.env.CuteDB, "Mia")
    assert(r and r.stats.xp_session == nil and r.stats.to60 == nil and r.stats.xp_hour == nil, "Zed holds none of her paces")
    for _, c in ipairs({ ofa, mia, zed }) do leave(c) end
  end)
  said[#said + 1] = "the paces go together"

  -- (c) Mia's account ran 0.5.x as Oldo, who set the policy; Oldo is gone from the guild (or renamed), or still in it, an
  -- officer
  for _, oldo in ipairs({ "gone", "an officer" }) do
    local guild = { member("Ofa", 0), member("Mia", 3), member("Bob", 3, { online = false }) }
    if oldo == "an officer" then guild[#guild + 1] = member("Oldo", 1, { online = false }) end
    isolated(guild, function()
      INFO[7] = infoLine(pol().policy)
      local db = { version = "0.5.0", toldChanges = "0.5.0",
        policy = { vis = {}, mine = true, by = "Oldo-Forever", at = 1000, rank = 0, threshold = 1 },
        chars = { ["Oldo-Forever"] = { counters = {} } },
        roster = { ["Bob-Forever"] = { seen = EPOCH + 1000, online = false, stats = { guid = guidOf("Bob"), level = 30, gold = 4242, addon_ver = "0.5.0" }, at = {} } } }
      local mia = char("Mia", 3)
      login(mia, db)
      tickAll(90)
      if oldo == "gone" then
        assert(not mia.C.Roster:AccountOfficer() and rec(db, "Bob").stats.gold == nil, "a setter the roster cannot name vouches for nothing: Bob's gold purged")
      else
        assert(mia.C.Roster:AccountOfficer() and rec(db, "Bob").stats.gold == 4242, "Oldo an officer still: the file is an officer's, kept")
      end
      leave(mia)
    end)
  end
  said[#said + 1] = "a 0.5.x setter the roster cannot name keeps no file"

  -- (d) Ofb has a change of his own; Ofa closes Deaths and saves while Ofb's asks go unanswered (or his Guild Info is the
  -- game's copy from before). Then Ofa saves twice in a row, her Guild Info the game's copy from before
  for _, how in ipairs({ "muted", "stale" }) do
    isolated({ member("Ofa", 1), member("Ofb", 1), member("Mia", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local ofa, ofb, mia = char("Ofa", 1), char("Ofb", 1), char("Mia", 3)
      login(ofa, pol(true)); login(ofb, pol()); login(mia, pol())
      tickAll(70)
      local old = INFO[7]
      local realGet, realAsk = ofb.env.C_GuildInfo.GetInfoText, ofb.env.C_GuildInfo.GuildRoster
      if how == "muted" then ofb.env.C_GuildInfo.GuildRoster = function() end
      else ofb.env.C_GuildInfo.GetInfoText = function() return old end end
      assert(ofb.C.Policy:Set("quests_done", "self"))
      assert(ofa.C.Policy:Set("deaths", "self") and saveLine(ofa))
      tickAll(1)
      local st = ofb.C.Policy:SaveState()
      assert(ofb.C.Policy.doubt and not st.ok and st.why == "Another officer saved Guild Info since you read it: wait a moment.", how .. ": Ofb may not save meanwhile: " .. tostring(st.why))
      assert(not saveLine(ofb) and INFO[7]:find("-" .. yezin.C.Policy.Code("deaths"), 1, true), how .. ": Ofa's line stands")
      ofb.env.C_GuildInfo.GetInfoText, ofb.env.C_GuildInfo.GuildRoster = realGet, realAsk
      fire(ofb, "GUILD_ROSTER_UPDATE")
      tickAll(60)
      assert(mia.C.Policy:Route("deaths") == "self" and ofb.C.Policy:Route("deaths") == "self" and chatHas(ofb, "gave way"), how .. ": Ofb read it, and his change gave way, said so")
      for _, c in ipairs({ ofa, ofb, mia }) do leave(c) end
    end)
  end
  isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol(nil, { zone = "all" }).policy)
    local ofa, zed = char("Ofa", 1, { zone = "Secretplace" }), char("Zed", 3)
    login(ofa, pol(true, { zone = "all" })); login(zed, pol(nil, { zone = "all" }))
    tickAll(70)
    local old, pinned = INFO[7], true
    local realGet = ofa.env.C_GuildInfo.GetInfoText
    ofa.env.C_GuildInfo.GetInfoText = function(...) if pinned then return old end return realGet(...) end
    assert(ofa.C.Policy:Set("zone", "self") and saveLine(ofa))
    tickAll(2)
    zed.got = {}
    assert(ofa.C.Policy:Set("deaths", "self"))
    local st = ofa.C.Policy:SaveState()
    assert(not st.ok and st.why == "Guild Info is being read again after a save: wait a moment." and not saveLine(ofa), "a second save waits for the first to be read back: " .. tostring(st.why))
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tickAll(3)
    assert(not chatHas(ofa, "does not hold") and ofa.C.Policy:Route("zone") == "self" and gotFrom(zed, ofa, 1, function(m) return m.channel == "GUILD" and m.msg:find("zone=", 1, true) end) == 0,
      "the copy from before reverts nothing, says nothing that is not so, and her zone stays off GUILD")
    pinned = false
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tickAll(20)
    assert(saveLine(ofa) and INFO[7]:find("-" .. yezin.C.Policy.Code("deaths"), 1, true) and INFO[7]:find("-" .. yezin.C.Policy.Code("zone"), 1, true), "read back, the second save goes: " .. INFO[7])
    for _, c in ipairs({ ofa, zed }) do leave(c) end
  end)
  said[#said + 1] = "a save waits while Guild Info is to be read again"

  -- (e) Ofb, away while Ofa closed Deaths, logs in inside a dungeon (Guild Info a secret) and retunes a rule; Zed is
  -- inside one too
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, ofb, mia, zed = char("Ofa", 0), char("Ofb", 1), char("Mia", 3), char("Zed", 3, { money = 1000 })
    login(ofa, pol(true)); login(ofb, pol()); login(mia, pol()); login(zed, pol())
    tickAll(70)
    local dbB = ofb.env.CuteDB
    leave(ofb)
    assert(ofa.C.Policy:Set("deaths", "self") and saveLine(ofa))
    tickAll(40)
    zed.infoSecret, zed.o.instance = true, "party"
    fire(zed, "PLAYER_ENTERING_WORLD", false, false)
    local ofb2 = char("Ofb", 1, { instance = "party" })
    ofb2.infoSecret = true
    login(ofb2, dbB)
    tickAll(15)
    local p0 = msgs(ofb2, "1P")
    assert(not ofb2.C.Policy:Settled() and p0 == 0, "Ofb waits for Guild Info: no policy of his at login")
    ofb2.C.Policy:SetRule("rangeMembers", 5)
    ofb2.C.Comm:PolicySoon()
    ofb2.C.Comm:Broadcast()
    tickAll(10)
    assert(msgs(ofb2, "1P") == 0 and not mia.C.Policy.doubt and not zed.C.Policy.doubt and zed.C.Policy:Settled(), "his clicks send nothing meanwhile: nobody waits for Guild Info")
    assert(chatHas(ofb2, "the policy goes to the guild once Guild Info is read."), "Broadcast says it waits")
    ofb2.infoSecret, ofb2.o.instance = false, nil
    fire(ofb2, "GUILD_ROSTER_UPDATE")
    tickAll(20)
    assert(ofb2.C.Policy:Settled() and msgs(ofb2, "1P") > 0 and ofa.env.CuteDB.policy.rules.rangeMembers == 5 and mia.C.Policy:Settled(), "read: his rule goes, and nobody is left waiting")
    for _, c in ipairs({ ofa, ofb2, mia, zed }) do leave(c) end
  end)
  said[#said + 1] = "an officer who does not hold the line sends no policy"

  -- (f) Kaka's Ready, ready with three empty slots she has not reported since; Ofa opens Empty slots and does not save,
  -- then saves
  isolated({ member("Ofa", 0), member("Kaka", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local db = pol(true)
    db.roster = { ["Kaka-Forever"] = { seen = EPOCH, online = true, at = {}, stats = { guid = guidOf("Kaka"), level = 30, ready = 2,
      empty_slots = { [1] = true, [3] = true, [5] = true }, durability = 80, potions = 5, addon_ver = "0.6.0" } } }
    local ofa = char("Ofa", 0)
    login(ofa, db)
    tickAll(30)
    local function tipOf()
      ofa.C.UI:Open("prog")
      local cell = cellOf(rowOf(ofa, "Kaka"), "ready")
      local n0 = #lines
      hover(cell)
      return cell.label:GetText(), table.concat(lines, "\n", n0 + 1)
    end
    local cell, tip = tipOf()
    assert(cell == "ready" and tip:find("No gaps.", 1, true) and tip:find("Counts durability under 50% and no potions.", 1, true), "before: " .. tip)
    assert(ofa.C.Policy:Set("empty_slots", "all") and ofa.C.Policy:Unsaved())
    cell, tip = tipOf()
    assert(cell == "ready" and tip:find("No gaps.", 1, true) and tip:find("Counts durability under 50% and no potions.", 1, true) and not tip:find("empty slots", 1, true),
      "a change not saved: the tooltip counts what Kaka's client counted: " .. tip)
    assert(saveLine(ofa))
    tickAll(20)
    cell, tip = tipOf()
    assert(tip:find("3 empty slots", 1, true) and tip:find("Counted before the officers' last change", 1, true), "saved: the gaps it counts now, and the verdict said to be from before: " .. tip)
    ofa.C.UI.frame:Hide()
    leave(ofa)
  end)
  said[#said + 1] = "a member's Ready tooltip counts what their client counted"

  -- (g) Ofa, who cannot save, raises the ranks to 2: Rae, of rank 2, is whispered nothing, and nothing loops; Zed's purge
  -- routes each id once
  isolated({ member("Ofa", 1), member("Rae", 2), member("Mia", 3) }, function()
    INFO_EDIT = 0
    INFO[7] = infoLine(pol().policy)
    local ofa, rae, mia = char("Ofa", 1, { money = 1000 }), char("Rae", 2), char("Mia", 3)
    login(ofa, pol(true)); login(rae, pol()); login(mia, pol())
    tickAll(70)
    assert(ofa.C.Policy:SetThreshold(2) and not ofa.C.Policy:SaveState().ok)
    for _, t in ipairs(ofa.C.Roster:OfficerTargets()) do assert(t ~= rae.sender, "Rae, an officer by no line, is no target") end
    local n, real = 0, ofa.C.Comm.Changed
    ofa.C.Comm.Changed = function(self, ...) n = n + 1; return real(self, ...) end
    rae.got = {}
    ofa.o.money = 5000
    fire(ofa, "PLAYER_MONEY")
    tickAll(30)
    ofa.C.Comm.Changed = real
    assert(n <= 12 and gotFrom(rae, ofa, 1, function(m) return m.channel == "WHISPER" end) == 0, "no whisper queued, dropped and queued again: " .. n)
    for _, c in ipairs({ ofa, rae, mia }) do leave(c) end
  end)
  isolated({ member("Ofa", 1), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local zed = char("Zed", 3)
    login(zed, pol())
    tickAll(30)
    local ids = { "gold", "deaths", "zone", "level", "quests_done", "xp_hour", "to60", "played", "empty_slots", "unenchanted" }
    for i = 1, 50 do
      local st = { guid = string.format("Player-1-%08X", 0x5000 + i), level = 30 }
      for _, id in ipairs(ids) do st[id] = 1 end
      zed.env.CuteDB.roster[("Fake%d-Forever"):format(i)] = { seen = EPOCH, at = {}, stats = st }
    end
    local P = zed.C.Policy
    local n, real = 0, P.Route
    P.Route = function(self, id) n = n + 1; return real(self, id) end
    P:Purge()
    P.Route = real
    assert(n <= 3 * (#ids + 3), "each id routed once, not once a record: " .. n)
    leave(zed)
  end)
  said[#said + 1] = "the smaller ones"
  print("the eighth round: " .. table.concat(said, "; "))
end

-- 51: what the ninth round of review found (0.6.0), each case one that failed before its fix: the doubt, from an
-- officer's save (or any hint the line changed) to the read that confirms a line, under one rule set. (a) The doubt and
-- the wait survive a /reload, the saver's own too: the game's copy from before is no answer after it, whether pinned
-- or catching up quietly seconds after the save. (b) An empty text at login is no line yet two seconds after an ask
-- the game never answered. (c) A roster read that lacks the officer alt, or lists it without a rank, says nothing: a
-- member alt's purge waits, and runs only once two reads half a minute apart have lacked it. (d) An officer who missed
-- a save and clicks Broadcast sends the old line's routing, which puts nobody in doubt (one that closes more does). (e)
-- A member whose client dropped a value while it routed by the line from before (an opening raises no doubt), a stat
-- the officers had just opened, asks once as the line read changes. (f) Ready counts by the policy in force as the record leaves. (g) Another officer's policy during the saver's
-- own wait replaces nothing: the copy from before is no answer, nothing false said. (h) An officer the officers marked
-- untrusted cancels no honest officer's answer and teaches no word. (i) An officer's column headers say what the
-- members go by, the change not saved marked. (j) A line deleted from Guild Info by hand is missing, not absent: the
-- last line read routes, nothing leaves, and the officers are asked to save it again
collectgarbage()
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function pol(mine, vis, at, thr)
    local copy = {}
    for k, v in pairs(vis or {}) do copy[k] = v end
    return { policy = { vis = copy, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = thr or 1 } }
  end
  local function rec(db, who) return db.roster[who .. "-Forever"] end
  local function chatHas(c, s) local n = 0; for _, l in ipairs(c.chat) do if l:find(s, 1, true) then n = n + 1 end end return n end
  local function gotFrom(c, from, from0, test)
    local n = 0
    for i = from0 or 1, #(c.got or {}) do local m = c.got[i]; if m.from == from.sender and test(m) then n = n + 1 end end
    return n
  end
  local function onGuild(id) return function(m) return m.channel == "GUILD" and m.msg:match("^1[DF]|") ~= nil and m.msg:find("[|;]" .. id .. "=") ~= nil end end
  -- Guild Info as the game's copy from before: pinned to a text until unpinned, the asks going unanswered meanwhile
  local function pin(c, text)
    local realGet, realAsk = c.env.C_GuildInfo.GetInfoText, c.env.C_GuildInfo.GuildRoster
    local on = true
    c.env.C_GuildInfo.GetInfoText = function(...) if on then return text end return realGet(...) end
    c.env.C_GuildInfo.GuildRoster = function() if not on then return realAsk() end end
    return function() on = false end
  end
  local said = {}

  -- (a) Mia (or Ofa, who saved) reloads while her Guild Info is the game's copy from before, catching up a few seconds
  -- after the reload (one pinned for good is the server's text after the wait, by design: scenario 49(h))
  for _, how in ipairs({ "catching up", "the saver, catching up" }) do
    isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
      INFO[7] = infoLine(pol(nil, { zone = "all" }).policy)
      local ofa, mia, zed = char("Ofa", 1, { zone = "Secretplace" }), char("Mia", 3, { zone = "Secretplace" }), char("Zed", 3)
      login(ofa, pol(true, { zone = "all" })); login(mia, pol(nil, { zone = "all" })); login(zed, pol(nil, { zone = "all" }))
      tickAll(70)
      local saver = how:find("saver", 1, true) ~= nil
      local who = saver and ofa or mia
      local old = INFO[7]
      local unpin = pin(who, old)
      assert(ofa.C.Policy:Set("zone", "self") and saveLine(ofa))
      tick(ofa, 1)
      if not saver then assert(mia.C.Policy.doubt, how .. ": Mia waits for Guild Info") end
      local db = who.env.CuteDB
      leave(who)
      local who2 = char(saver and "Ofa" or "Mia", saver and 1 or 3, { zone = "Secretplace" })
      local unpin2 = pin(who2, old)
      zed.got = {}
      login(who2, db, true)
      fire(who2, "GUILD_ROSTER_UPDATE", true)
      local P = who2.C.Policy
      assert(not P:Settled() and (P.waitFor ~= nil), how .. ": after the /reload the copy from before is no answer: " .. P:Describe())
      who2.o.zone = "Elsewhere"; who2.C.Sample.values.zone = "Elsewhere"; who2.C.Sample.dirty.zone = true; who2.C.Comm:Changed()
      tickAll(4)
      assert(gotFrom(zed, who2, 1, onGuild("zone")) == 0 and not P:Settled(), how .. ": her zone stays off GUILD")
      unpin2()
      tickAll(30)
      assert(P:Settled() and P:Route("zone") == "self" and P.line.fp ~= yezin.C.Policy.ParseLine(old).fp, how .. ": the new line routes her: " .. P:Describe())
      assert(gotFrom(zed, who2, 1, onGuild("zone")) == 0, how .. ": her zone never went on GUILD")
      assert(chatHas(who2, "does not hold") == 0, how .. ": nothing false said")
      unpin()
      for _, c in ipairs({ ofa, mia, who2, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "the doubt and the wait survive a /reload"

  -- (b) an empty text at login, no officer online, and the game's "the roster changed" two seconds after an ask it
  -- never answered
  isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
    local NEW = EPOCH + 500
    INFO[7] = infoLine(pol(nil, { zone = "self" }).policy, true, NEW)
    local zed = char("Zed", 3)
    login(zed, pol(nil, { zone = "self" }, NEW))
    tickAll(70)
    zed.got = {}
    local mia = char("Mia", 3, { zone = "Secretplace" })
    local unpin = pin(mia, "")
    login(mia, pol(nil, { zone = "all" }))
    fire(mia, "GUILD_ROSTER_UPDATE", true)
    for _ = 1, 11 do tick(mia, 1); tick(zed, 1) end
    assert(mia.C.Policy.emptyWait and mia.C.Policy.emptyWait.asked, "her ask went")
    fire(mia, "GUILD_ROSTER_UPDATE", false)
    tickAll(5)
    assert(mia.C.Policy.line == nil and not mia.C.Policy:Settled(), "two seconds after the ask, an empty text is no line yet: " .. mia.C.Policy:Describe())
    assert(gotFrom(zed, mia, 1, onGuild("zone")) == 0, "her zone stays off GUILD")
    unpin()
    fire(mia, "GUILD_ROSTER_UPDATE", false)
    tickAll(10)
    assert(mia.C.Policy:Settled() and mia.C.Policy:Route("zone") == "self" and gotFrom(zed, mia, 1, onGuild("zone")) == 0, "the roster's answer brings the line, her zone never on GUILD")
    for _, c in ipairs({ mia, zed }) do leave(c) end
  end)
  said[#said + 1] = "an empty text no line two seconds after an ask"

  -- (c) Ofa, an officer, holds Zed's gold; Alto, her alt, logs in on a roster whose first reads lack Ofa, or list her
  -- with no rank; and Ofa gone from the guild
  for _, how in ipairs({ "missing", "no rank", "gone" }) do
    isolated({ member("Ofa", 1), member("Alto", 3), member("Zed", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local db = pol()
      local ofa, zed = char("Ofa", 1), char("Zed", 3, { money = 777777 })
      login(ofa, db); login(zed, pol())
      tickAll(40)
      assert(rec(db, "Zed").stats.gold == 777777 and db.chars[ofa.name].officerOf == 7 and db.chars[ofa.name].guid == ofa.o.guid, "Ofa holds Zed's gold, an officer at her last login")
      leave(ofa)
      local alto = char("Alto", 3)
      if how == "gone" then
        for i = #GUILD, 1, -1 do if GUILD[i].name == "Ofa-Forever" then table.remove(GUILD, i) end end
      else
        -- (the roster lacks her, or her rank, for the first twenty seconds of Alto's session)
        local real, until_ = alto.env.C_Club.GetMemberInfo, alto.clock + 20
        alto.env.C_Club.GetMemberInfo = function(id, i)
          local m = real(id, i)
          if m and m.guid == ofa.o.guid and alto.clock < until_ then
            if how == "missing" then return nil end
            m.guildRankOrder = nil
          end
          return m
        end
      end
      login(alto, db)
      tickAll(30)
      if how == "gone" then
        assert(rec(db, "Zed").stats.gold == 777777 and alto.C.Roster:AccountOfficer() == nil, how .. ": one read that lacks Ofa says nothing")
        tickAll(70)
        assert(rec(db, "Zed").stats.gold == nil and alto.C.Roster:AccountOfficer() == false, how .. ": two reads half a minute apart: no character of the guild, the file purged")
      else
        assert(rec(db, "Zed").stats.gold == 777777 and alto.C.Roster:AccountOfficer() == nil, how .. ": a slow roster deletes nothing: " .. tostring(alto.C.Roster:AccountOfficer()))
        tickAll(70)
        assert(rec(db, "Zed").stats.gold == 777777 and alto.C.Roster:AccountOfficer() == true, how .. ": read whole, the file is an officer's")
      end
      for _, c in ipairs({ alto, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "an incomplete roster read purges nothing"

  -- (d) Ofb misses Ofa's save (off the bus while its 1P went) and clicks Broadcast: the old line's routing, stamped
  -- now, puts nobody in doubt; Mia, inside an instance, goes on sending. Where Ofa had opened Gold instead, Ofb's stale
  -- policy closes more than the line: the doubt rises, and ends at the next read
  for _, how in ipairs({ "closed", "opened" }) do
    isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Zed", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local ofa, ofb, mia, zed = char("Ofa", 0), char("Ofb", 1), char("Mia", 3), char("Zed", 3)
      login(ofa, pol(true)); login(ofb, pol()); login(mia, pol()); login(zed, pol())
      tickAll(40)
      leave(ofb)
      if how == "closed" then ofa.C.Policy:Set("deaths", "self") else ofa.C.Policy:Set("gold", "all") end
      assert(saveLine(ofa))
      tickAll(3)
      tick(ofb, 3)
      clients[#clients + 1] = ofb
      assert(mia.C.Policy:Settled() and ofb.C.Policy:Settled() and ofb.C.Policy.line.fp ~= mia.C.Policy.line.fp, how .. ": Ofb missed the save")
      if how == "closed" then mia.infoSecret = true end
      ofb.C.Comm:Broadcast()
      tickAll(2)
      if how == "closed" then
        assert(not mia.C.Policy.doubt and not zed.C.Policy.doubt and mia.C.Policy:Settled(), how .. ": the old line's routing puts nobody in doubt: " .. mia.C.Policy:Describe())
        fire(mia, "PLAYER_DEAD")
        ofa.got, zed.got = {}, {}
        tickAll(60)
        assert(gotFrom(ofa, mia, 1, function(m) return m.channel == "WHISPER" end) > 0 and gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and m.msg:sub(1, 2) == "1D" end) > 0,
          how .. ": Mia, in an instance, goes on sending")
      else
        assert(mia.C.Policy.doubt and not mia.C.Policy:Settled(), how .. ": a policy that closes more than the line raises the doubt")
        tickAll(25)
        assert(mia.C.Policy:Settled() and mia.C.Policy:Route("gold") == "all", how .. ": the next read ends it")
      end
      for _, c in ipairs({ ofa, ofb, mia, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "a stale officer's routing raises no doubt"

  -- (e) the line keeps Hearthstone to the officers; Mia's roster ask went a second before Ofa opens it and saves, so
  -- her read waits and she drops Zed's hearth, sent once: as her read brings the new line she asks, once, and holds it
  isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol(nil, { hearth = "self" }).policy)
    local ofa, mia, zed = char("Ofa", 1), char("Mia", 3), char("Zed", 3, { hearth = "Stormwind" })
    login(ofa, pol(true, { hearth = "self" })); login(mia, pol(nil, { hearth = "self" })); login(zed, pol(nil, { hearth = "self" }))
    tickAll(200)
    assert(rec(mia.env.CuteDB, "Zed").stats.hearth == nil and rec(ofa.env.CuteDB, "Zed").stats.hearth == "Stormwind", "the officers alone hold Zed's hearth")
    mia.C.Roster.askedAt = mia.C.Now() - 1
    local asks = msgs(mia, "1R")
    assert(ofa.C.Policy:Set("hearth", "all") and saveLine(ofa))
    tickAll(4)
    -- (an opening raises no doubt: she routes by the line from before until her read, and drops what came by the new one)
    assert(not mia.C.Policy.doubt and mia.C.Policy:Route("hearth") == "self" and rec(mia.env.CuteDB, "Zed").stats.hearth == nil, "Mia routes by the line from before, and dropped what came")
    tickAll(120)
    assert(mia.C.Policy:Settled() and mia.C.Policy:Route("hearth") == "all", "Mia read the line")
    assert(msgs(mia, "1R") == asks + 1, "she asked once as the doubt ended: " .. (msgs(mia, "1R") - asks))
    assert(rec(mia.env.CuteDB, "Zed").stats.hearth == "Stormwind", "and holds Zed's hearth")
    for _, c in ipairs({ ofa, mia, zed }) do leave(c) end
  end)
  said[#said + 1] = "a value dropped before the line read asked for again"

  -- (f) the line keeps Empty slots to the officers; Mia's held policy opened it. She logs in where Guild Info is a
  -- secret, her Ready counting the empty slots meanwhile, then reads the line: the record released counts by it
  isolated({ member("Ofa", 1), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, zed = char("Ofa", 1), char("Zed", 3)
    login(ofa, pol(true)); login(zed, pol())
    tickAll(40)
    local mia = char("Mia", 3)
    mia.infoSecret = true
    zed.got = {}
    login(mia, pol(nil, { empty_slots = "all" }))
    tickAll(30)
    assert(not mia.C.Policy:Settled() and mia.C.Sample.values.ready == 1 and gotFrom(zed, mia, 1, onGuild("ready")) == 0, "held back, her Ready counts the empty slots meanwhile")
    mia.infoSecret = false
    fire(mia, "GUILD_ROSTER_UPDATE")
    tickAll(20)
    assert(mia.C.Policy:Settled() and mia.C.Policy:Route("empty_slots") == "self" and mia.C.Sample.values.ready == 2, "the line routes her, Ready counted by it")
    assert(gotFrom(zed, mia, 1, function(m) return m.channel == "GUILD" and m.msg:find("[|;]ready=1") ~= nil end) == 0 and gotFrom(zed, mia, 1, onGuild("ready")) > 0,
      "the record released carries the Ready counted by the line, never the one from before")
    for _, c in ipairs({ ofa, mia, zed }) do leave(c) end
  end)
  said[#said + 1] = "Ready by the policy in force as the record leaves"

  -- (g) Ofa saves while her Guild Info is the game's copy from before; Ofb's Broadcast two seconds later (or his old
  -- line's parts stamped just after the save) replaces nothing: the copy from before is no answer, nothing false said
  for _, how in ipairs({ "broadcast", "inject" }) do
    isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3) }, function()
      INFO[7] = infoLine(pol(nil, { zone = "all" }).policy)
      local ofa, ofb, mia = char("Ofa", 0, { zone = "Secretplace" }), char("Ofb", 1), char("Mia", 3)
      login(ofa, pol(true, { zone = "all" })); login(ofb, pol(nil, { zone = "all" })); login(mia, pol(nil, { zone = "all" }))
      tickAll(70)
      local old = INFO[7]
      local oldFp = ofa.C.Policy.line.fp
      local unpin = pin(ofa, old)
      local at0, thr0, parts0 = ofb.C.Policy:Parts()
      assert(ofa.C.Policy:Set("zone", "self") and saveLine(ofa))
      local P = ofa.C.Policy
      assert(P.line.fp ~= oldFp and P.waitFor and P.waitFor.old.fp == oldFp, how .. ": the save waits for the line from before to go")
      ofa.chat = {}
      mia.got = {}
      if how == "broadcast" then
        ofb.clock = ofb.clock + 2
        ofb.C.Comm:Broadcast()
      else
        P:Receive(ofb.sender, math.floor(ofa.C.ServerNow()) + 1, thr0, table.concat(parts0, ";"), 1, 1)
      end
      tickAll(2)
      assert(not P.doubt and P.waitFor and P.waitFor.old.fp == oldFp and P:Settled(), how .. ": the wait runs on, the old routing raising no doubt")
      fire(ofa, "GUILD_ROSTER_UPDATE")
      assert(P.line.fp ~= oldFp and P:Route("zone") == "self" and not P.doubt, how .. ": the copy from before is no answer")
      assert(chatHas(ofa, "does not hold") == 0, how .. ": nothing false said")
      tickAll(5)
      assert(gotFrom(mia, ofa, 1, onGuild("zone")) == 0, how .. ": her zone stays off GUILD")
      unpin()
      tickAll(25)
      assert(P.line.fp ~= oldFp and P:Settled() and not P.waitFor and chatHas(ofa, "does not hold") == 0, how .. ": read back: the line she saved, and nothing false said")
      for _, c in ipairs({ ofa, ofb, mia }) do leave(c) end
    end)
  end
  said[#said + 1] = "another officer's policy replaces no wait"

  -- (h) Ofa marks Ofb, an officer, untrusted. Ofb's copy answers Mia's ask with a policy stamped ahead: Ofa answers all
  -- the same; and Ofb's word teaches Mia nothing
  isolated({ member("Ofa", 1), member("Ofb", 1), member("Mia", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, ofb, mia = char("Ofa", 1), char("Ofb", 1), char("Mia", 3)
    login(ofa, pol(true)); login(ofb, pol()); login(mia, pol())
    tickAll(70)
    ofa.C.Policy:SetUntrusted(ofb.o.guid, true)
    ofa.C.Comm:PolicySoon()
    tickAll(8)
    assert(mia.C.Policy:Untrusted(ofb.o.guid) and ofa.C.Policy:Untrusted(ofb.o.guid), "Ofb untrusted on every client")
    tickAll(60)
    mia.got = {}
    mia.env.CuteDB.policy.at = EPOCH
    mia.C.Comm:Ask()
    tickAll(0.5)
    local now = math.floor(ofb.C.ServerNow())
    ofb.C.Comm.Queue({ msg = "1P|" .. (now + 30) .. "|1|1/1|", first = true })
    tickAll(6)
    assert(gotFrom(mia, ofa, 1, function(m) return m.msg:sub(1, 2) == "1P" end) >= 1, "Ofa answers Mia's ask: an untrusted officer's policy covers nothing")
    ofb.C.Comm.Queue({ msg = "1N|" .. now .. "|1/1|n11=4.0", first = true })
    tickAll(3)
    local w = mia.C.Rules.Word()
    assert(not (w and w.enchant and w.enchant[11]), "an untrusted officer's word teaches nothing")
    for _, c in ipairs({ ofa, ofb, mia }) do leave(c) end
  end)
  said[#said + 1] = "an untrusted officer cancels and teaches nothing"

  -- (i) Ofa opens Empty slots and Gold, closes Zone, and saves nothing: her headers say what the members go by, the
  -- change marked not saved
  isolated({ member("Ofa", 0), member("Kaka", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, kaka = char("Ofa", 0), char("Kaka", 3)
    login(ofa, pol(true)); login(kaka, pol())
    tickAll(30)
    local function headTip(id)
      ofa.C.UI:Open("prog")
      for _, h in ipairs(ofa.C.UI.headerCells.items) do
        if h:IsShown() and h.def and h.def.id == id then local n0 = #lines; hover(h); return table.concat(lines, "\n", n0 + 1) end
      end
      error("no header for " .. id)
    end
    local tip = headTip("ready")
    assert(tip:find("Counts now: durability under 50% and no potions.", 1, true) and not tip:find("not saved", 1, true), "before: " .. tip)
    assert(ofa.C.Policy:Set("empty_slots", "all") and ofa.C.Policy:Set("gold", "all") and ofa.C.Policy:Set("zone", "self") and ofa.C.Policy:EditPending())
    tip = headTip("ready")
    assert(tip:find("Counts now: durability under 50% and no potions.", 1, true) and tip:find("Your change, not saved yet, would count an empty slot, durability under 50% and no potions.", 1, true),
      "a change not saved: the header counts what the members' clients count, the change marked: " .. tip)
    local gold, zone = ofa.C.UI.WhoSees("gold"), ofa.C.UI.WhoSees("zone")
    assert(gold:find("^Only you and the officers see this.") and gold:find("not saved yet, would show it to everyone", 1, true), "Gold: the members whisper it still: " .. gold)
    assert(zone:find("^Everyone sees this.") and zone:find("not saved yet, would keep it", 1, true), "Zone: the members send it still: " .. zone)
    assert(kaka.C.Policy:Route("gold") == "self" and kaka.C.Policy:Route("zone") == "all" and kaka.C.UI.WhoSees("gold") == "Only you and the officers see this.", "Kaka's say the line")
    ofa.C.UI.frame:Hide()
    for _, c in ipairs({ ofa, kaka }) do leave(c) end
  end)
  said[#said + 1] = "headers say what the members go by"

  -- (j) Ofa closes Quests done and saves; Mia reads the line and logs out; an officer deletes the line by hand, tidying
  -- Guild Info. Zed reads it missing and sends nothing; Ofa is told, once, and may save; Mia logs in again (Ofa online,
  -- or not) and sends nothing either; Ofa saves again and the guild goes on. A recruit who never read the line cannot
  -- know one existed (irreducible, the README says)
  for _, ofaOnline in ipairs({ true, false }) do
    isolated({ member("Ofa", 0), member("Mia", 3), member("Zed", 3) }, function()
      INFO[7] = "Welcome to <Cute>!"
      local ofa, mia, zed = char("Ofa", 0), char("Mia", 3), char("Zed", 3)
      local miaDb = pol()
      login(ofa, pol(true)); login(zed, pol()); login(mia, miaDb)
      tickAll(30)
      assert(ofa.C.Policy:Set("quests_done", "self") and saveLine(ofa))
      tickAll(30)
      assert(mia.C.Policy:Holds() and zed.C.Policy:Holds() and mia.env.CuteDB.lines and mia.env.CuteDB.lines["7"].line, "the line read and kept")
      leave(mia)
      INFO[7] = "Welcome to <Cute>!"
      ofa.chat = {}
      zed.got = {}
      fire(ofa, "GUILD_ROSTER_UPDATE"); fire(zed, "GUILD_ROSTER_UPDATE")
      tickAll(30)
      assert(zed.C.Policy.missing and not zed.C.Policy:Settled() and zed.C.Policy:Route("quests_done") == "self", "Zed: the line is missing, the last read routes: " .. zed.C.Policy:Describe())
      assert(ofa.C.Policy:Describe():find("missing from Guild Info; Save to Guild Info", 1, true) and chatHas(ofa, "missing from Guild Info") == 1 and ofa.C.Policy:Unsaved() and ofa.C.Policy:SaveState().ok,
        "Ofa: told once, and may save it back: " .. ofa.C.Policy:Describe() .. " / " .. tostring(ofa.C.Policy:SaveState().why))
      fire(ofa, "GUILD_ROSTER_UPDATE")
      tickAll(65)
      assert(chatHas(ofa, "missing from Guild Info") == 1, "told once")
      if not ofaOnline then leave(ofa) end
      local mia2 = char("Mia", 3)
      login(mia2, miaDb)
      tickAll(40)
      assert(mia2.C.Policy.missing and not mia2.C.Policy:Settled() and mia2.C.Policy:Route("quests_done") == "self", "Mia, back: the line is missing: " .. mia2.C.Policy:Describe())
      assert(gotFrom(zed, mia2, 1, function(m) return m.channel == "GUILD" and m.msg:sub(1, 2) ~= "1R" end) == 0 and gotFrom(zed, zed, 1, onGuild("quests_done")) == 0,
        "nothing of theirs on GUILD meanwhile")
      if not ofaOnline then clients[#clients + 1] = ofa end
      assert(saveLine(ofa))
      tickAll(30)
      for _, c in ipairs({ ofa, mia2, zed }) do assert(c.C.Policy:Holds() and not c.C.Policy.missing and c.C.Policy:Route("quests_done") == "self", c.o.name .. ": saved again, the line routes") end
      assert(rec(zed.env.CuteDB, "Mia") and rec(zed.env.CuteDB, "Mia").stats.level == 30 and gotFrom(zed, mia2, 1, onGuild("quests_done")) == 0, "Mia's record went, her quests not")
      for _, c in ipairs({ ofa, mia2, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "a line deleted by hand is missing, not absent"
  print("the ninth round: " .. table.concat(said, "; "))
end

-- 52: what the tenth round of review found (0.6.0), each case one that failed before its fix. (a) A second officer's
-- Save seconds after another's, on the game's copy from before, that officer's policy heard: refused until a read
-- confirms the line, the other's policy no stricter than the line or stricter; nothing written over the line, and the
-- stat it closed stays off GUILD. (b) The same two saves in one second, before either heard the other: the second is
-- taken (nothing says otherwise yet), and the first officer is told at the read-back that another saved over her
-- save, her change back on the new line, not saved, and saved again, both changes in the line; the second officer
-- told his change stands. (c) An officer whose roster read lists her without a rank mid-session (a blip) keeps the
-- whispers that come meanwhile, and a value her client dropped is asked for again at the next read whatever the roster
-- said of her. (d) A save the game refused, and a relog within the wait: told after the relog, the change back, not
-- saved, and saved again
collectgarbage()
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function pol(mine, vis, at, thr)
    local copy = {}
    for k, v in pairs(vis or {}) do copy[k] = v end
    return { policy = { vis = copy, by = "Ofa-Forever", mine = mine or nil, rank = 0, at = at or EPOCH, threshold = thr or 1 } }
  end
  local function rec(db, who) return db.roster[who .. "-Forever"] end
  local function chatHas(c, s) local n = 0; for _, l in ipairs(c.chat) do if l:find(s, 1, true) then n = n + 1 end end return n end
  local function gotFrom(c, from, from0, test)
    local n = 0
    for i = from0 or 1, #(c.got or {}) do local m = c.got[i]; if m.from == from.sender and test(m) then n = n + 1 end end
    return n
  end
  local function onGuild(id) return function(m) return m.channel == "GUILD" and m.msg:match("^1[DF]|") ~= nil and m.msg:find("[|;]" .. id .. "=") ~= nil end end
  local function pin(c, text)
    local realGet, realAsk = c.env.C_GuildInfo.GetInfoText, c.env.C_GuildInfo.GuildRoster
    local on = true
    c.env.C_GuildInfo.GetInfoText = function(...) if on then return text end return realGet(...) end
    c.env.C_GuildInfo.GuildRoster = function() if not on then return realAsk() end end
    return function() on = false end
  end
  local said = {}

  -- (a) Ofa opens Gold (no stricter than the line: the doubt is nobody's) or closes Deaths and saves; Ofb, holding a
  -- change not saved and the game's copy from before, clicks Save two seconds later
  for _, how in ipairs({ "opened", "closed" }) do
    isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Zed", 3) }, function()
      INFO[7] = infoLine(pol().policy)
      local ofa, ofb, mia, zed = char("Ofa", 0), char("Ofb", 1), char("Mia", 3), char("Zed", 3)
      login(ofa, pol(true)); login(ofb, pol()); login(mia, pol()); login(zed, pol())
      tickAll(70)
      local old = INFO[7]
      assert(ofb.C.Policy:Set(how == "opened" and "deaths" or "zone", "self"))
      local unpin = pin(ofb, old)
      assert(ofa.C.Policy:Set(how == "opened" and "gold" or "deaths", how == "opened" and "all" or "self") and saveLine(ofa))
      local saved = INFO[7]
      tickAll(2)
      local st = ofb.C.Policy:SaveState()
      assert(not st.ok and st.why:find("since you read", 1, true), how .. ": Ofb's Save two seconds on is refused: " .. tostring(st.why))
      assert(not saveLine(ofb) and INFO[7] == saved, how .. ": nothing written over Ofa's line")
      ofa.chat = {}
      unpin()
      tickAll(30)
      assert(INFO[7] == saved, how .. ": Ofa's line stands")
      local P = ofb.C.Policy
      assert(P:Settled() and P.line.fp == ofa.C.Policy.line.fp and not P.unread and not P.doubt, how .. ": Ofb read it: " .. P:Describe())
      assert(chatHas(ofa, "does not hold") == 0 and chatHas(ofa, "saved over") == 0, how .. ": nothing false said to Ofa")
      if how == "opened" then
        assert(mia.C.Policy:Route("gold") == "all" and P:Route("deaths") == "all" and not P:EditPending(), how .. ": the line routes everyone, Ofb's change given way")
      else
        zed.got = {}
        fire(mia, "PLAYER_DEAD")
        tickAll(6)
        assert(mia.C.Policy:Route("deaths") == "self" and gotFrom(zed, mia, 1, onGuild("deaths")) == 0, how .. ": Mia's deaths, closed by Ofa's line, stay off GUILD")
      end
      assert(P:Set("zone", "self") and P:SaveState().ok, how .. ": Ofb may save a change made on the line read: " .. tostring(P:SaveState().why))
      for _, c in ipairs({ ofa, ofb, mia, zed }) do leave(c) end
    end)
  end
  said[#said + 1] = "a second officer's save seconds after another's refused"

  -- (b) Ofa closes Deaths and saves; Ofb, on the game's copy from before, closes Zone and saves in the same second,
  -- before either heard the other
  isolated({ member("Ofa", 0), member("Ofb", 1), member("Mia", 3), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, ofb, mia, zed = char("Ofa", 0), char("Ofb", 1), char("Mia", 3), char("Zed", 3)
    login(ofa, pol(true)); login(ofb, pol()); login(mia, pol()); login(zed, pol())
    tickAll(70)
    local old = INFO[7]
    assert(ofb.C.Policy:Set("zone", "self"))
    local unpin = pin(ofb, old)
    assert(ofa.C.Policy:Set("deaths", "self") and saveLine(ofa))
    local first = INFO[7]
    assert(saveLine(ofb) and INFO[7] ~= first, "Ofb's save in the same second is taken: nothing said otherwise yet")
    ofa.chat, ofb.chat = {}, {}
    unpin()
    tickAll(30)
    local P = ofa.C.Policy
    assert(chatHas(ofa, "another officer saved over your save") == 1 and chatHas(ofa, "does not hold") == 0, "Ofa told, once, that another officer saved over her save: " .. table.concat(ofa.chat, " / "))
    assert(P.line.fp == ofb.C.Policy.line.fp and P:Unsaved() and P:EditPending() and P:Route("deaths") == "self" and P:Route("zone") == "self", "her change back on Ofb's line, not saved: " .. P:Describe())
    assert(mia.C.Policy:Settled() and mia.C.Policy:Route("zone") == "self" and mia.C.Policy:Route("deaths") == "all", "the members route by Ofb's line meanwhile: " .. mia.C.Policy:Describe())
    assert(P:SaveState().ok, "and she may save it again: " .. tostring(P:SaveState().why))
    assert(saveLine(ofa))
    tickAll(30)
    zed.got = {}
    fire(mia, "PLAYER_DEAD")
    tickAll(6)
    assert(mia.C.Policy:Settled() and mia.C.Policy:Route("deaths") == "self" and mia.C.Policy:Route("zone") == "self" and gotFrom(zed, mia, 1, onGuild("deaths")) == 0,
      "saved again: both changes in the line, Mia's deaths off GUILD: " .. mia.C.Policy:Describe())
    assert(P:Holds() and chatHas(ofa, "saved over") == 1, "Ofa holds the line she saved")
    assert(chatHas(ofb, "your change stands") == 1 and chatHas(ofb, "saved over") == 0 and ofb.C.Policy:Holds(), "Ofb told his change stands in her line: " .. table.concat(ofb.chat, " / "))
    for _, c in ipairs({ ofa, ofb, mia, zed }) do leave(c) end
  end)
  said[#said + 1] = "two saves in one second: the first officer told, her change back"

  -- (c) Ofa, an officer holding Zed's gold; her roster lists her without a rank for twenty seconds; Zed's gold changes
  -- meanwhile, whispered to her
  isolated({ member("Ofa", 1), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, zed = char("Ofa", 1), char("Zed", 3, { money = 1000 })
    login(ofa, pol(true)); login(zed, pol())
    tickAll(40)
    local R = ofa.C.Roster
    assert(rec(ofa.env.CuteDB, "Zed").stats.gold == 1000 and R:MeOfficer() and R.wasOfficer == true, "Ofa holds Zed's gold")
    local real, until_ = ofa.env.C_Club.GetMemberInfo, ofa.clock + 20
    ofa.env.C_Club.GetMemberInfo = function(id, i)
      local m = real(id, i)
      if m and m.guid == ofa.o.guid and ofa.clock < until_ then local c = {}; for k, v in pairs(m) do c[k] = v end; c.guildRankOrder = nil; return c end
      return m
    end
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tick(ofa, 1)
    assert(not R:SelfKnown() and not R:MeOfficer() and R.wasOfficer == true and R:OfficerStill(), "the blip: the roster lists her without a rank, an officer still")
    local asks = msgs(ofa, "1R")
    ofa.got = {}
    zed.o.money = 2000
    fire(zed, "PLAYER_MONEY")
    tickAll(8)
    assert(gotFrom(ofa, zed, 1, function(m) return m.channel == "WHISPER" end) > 0, "Zed whispered her meanwhile")
    assert(rec(ofa.env.CuteDB, "Zed").stats.gold == 2000 and not R.lostUnsettled, "and she holds it: " .. tostring(rec(ofa.env.CuteDB, "Zed").stats.gold))
    tickAll(20)
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tickAll(5)
    assert(R:SelfKnown() and R:MeOfficer() and msgs(ofa, "1R") == asks, "the roster lists her rank again; nothing to ask for")
    -- (a value her client dropped all the same, whatever the roster said of her meanwhile: asked for again at the
    -- next read that lists her, not only as she becomes an officer)
    R.lostUnsettled = true
    fire(ofa, "GUILD_ROSTER_UPDATE")
    tickAll(2)
    assert(msgs(ofa, "1R") == asks + 1 and not R.lostUnsettled, "a value dropped while an officer is asked for again: " .. (msgs(ofa, "1R") - asks))
    for _, c in ipairs({ ofa, zed }) do leave(c) end
  end)
  said[#said + 1] = "a roster blip keeps the whispers"

  -- (d) Ofa closes Level and saves; the game takes the call and keeps nothing; she relogs two seconds on, within the wait
  isolated({ member("Ofa", 1), member("Zed", 3) }, function()
    INFO[7] = infoLine(pol().policy)
    local ofa, zed = char("Ofa", 1), char("Zed", 3)
    local db = pol(true)
    login(ofa, db); login(zed, pol())
    tickAll(40)
    ofa.infoDrop = true
    assert(ofa.C.Policy:Set("level", "self") and saveLine(ofa))
    tick(ofa, 2)
    local k = db.lines and db.lines["7"]
    assert(k and k.wait and k.saved and k.saved.fp == ofa.C.Policy.line.fp and k.saved.diff == "-le" and k.saved.base == yezin.C.Policy.ParseLine(INFO[7]).fp, "the save kept with the guild")
    leave(ofa)
    local ofa2 = char("Ofa", 1)
    login(ofa2, db, true)
    tickAll(60)
    local P = ofa2.C.Policy
    assert(chatHas(ofa2, "does not hold") == 1 and chatHas(ofa2, "change is back, not saved") == 1, "after the relog: told that the game did not take it: " .. table.concat(ofa2.chat, " / "))
    assert(type(P.line) == "table" and P.line.fp == yezin.C.Policy.ParseLine(INFO[7]).fp and P:Unsaved() and P:EditPending() and P:Route("level") == "self" and not k.saved and not k.wait,
      "her change back, not saved, on the line Guild Info holds: " .. P:Describe())
    assert(P:SaveState().ok and zed.C.Policy:Route("level") == "all" and zed.C.Policy:Holds(), "she may save it again; Zed routes by the line meanwhile")
    assert(saveLine(ofa2))
    tickAll(30)
    assert(P:Holds() and not P:Unsaved() and zed.C.Policy:Route("level") == "self" and chatHas(ofa2, "does not hold") == 1, "saved again, the guild follows: " .. P:Describe())
    for _, c in ipairs({ ofa2, zed }) do leave(c) end
  end)
  said[#said + 1] = "a save the game refused survives a relog as a change not saved"
  print("the tenth round: " .. table.concat(said, "; "))
end

-- 51: what the owner's live client showed (0.6.1): ticking the Guide in Settings > Modules did nothing, and no Lua
-- model of the client reproduced it. Each case closes one way it could happen on a client that swallows errors
-- (scriptErrors 0), modelled as that client would meet it: the harness's fatal errors are off for the moment the
-- error is thrown. (a) An error thrown in a click's path, in the draw (a secret compared, say) or before it: recorded
-- under /cute errors with its path, the choice kept, drawing reset, so the window draws again at the next refresh
-- (0.6.0 left UI.drawing set and every later Refresh returned early). (b) Rule 0: an ask that throws mid-chain is
-- recorded and the chain goes on to its verdict; a chain that stalls (a frame that never comes) is closed by the
-- watchdog thirty seconds on, the Guide filling in, and the band says how far it got meanwhile. (c) A character key
-- that flips call by call (UnitFullName's second return the surname one call, nothing the next) saves and reads the
-- modules under one key: the first non-nil key is this session's
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 42, online = true } end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "WARRIOR", 42 }, extra)) end
  local function guideBox(c) return checkBox(c, function(cb) return cb.label and cb.label:GetText() == "Guide" end) end
  local function errorsWhere(c) local out = {}; for _, e in ipairs(c.env.CuteDB.errors or {}) do out[#out + 1] = tostring(e.where) end; return table.concat(out, ", ") end
  local function chatHas(c, s) local n = 0; for _, l in ipairs(c.chat) do if l:find(s, 1, true) then n = n + 1 end end return n end
  local said = {}

  -- (a) the error in the draw: Roster:MeOfficer throws on its second call of the click (Settings_Draw's), as a secret
  -- rank compared with <= would on the live client; then an error before the draw, in Modules.Set
  isolated({ member("Helga", 1), member("Pim", 3) }, function()
    local c = char("Helga", 1, { surname = "Bluntforce", fullNameSurname = true, sender = "Helga Bluntforce" })
    login(c)
    c.env.SlashCmdList.CUTE("modules")
    local box = guideBox(c)
    assert(box and not box:GetChecked(), "the Guide's row, unticked")
    local n0 = #(c.env.CuteDB.errors or {}) -- (a quiet note or two from login: a client function this mock lacks)
    local R = c.C.Roster
    local real, calls = R.MeOfficer, 0
    R.MeOfficer = function(self) calls = calls + 1; if calls == 2 then error("attempt to compare a secret number value") end return real(self) end
    c.env.CUTE_DEV = false
    click(box)
    c.env.CUTE_DEV = true
    R.MeOfficer = real
    local me = c.C.Me()
    assert(c.env.CuteDB.chars[me].modules.guide == true and c.C.Modules.byId.guide.active, "the tick took: the choice saved, the module on")
    local e = c.env.CuteDB.errors[1]
    assert(e and e.where == "draw" and e.msg:find("secret number", 1, true) and #c.env.CuteDB.errors == n0 + 1, "the error recorded under its path: " .. errorsWhere(c))
    assert(chatHas(c, "ran into a problem and carried on. /cute errors shows the details.") == 1, "and said once")
    assert(c.C.UI.drawing == false, "drawing reset after the failed draw")
    local l0 = #c.chat
    c.env.SlashCmdList.CUTE("errors")
    local listed = false
    for i = l0 + 1, #c.chat do if c.chat[i]:find("secret number", 1, true) and c.chat[i]:find("(x1, last ", 1, true) and c.chat[i]:find(") draw", 1, true) then listed = true end end
    assert(listed, "/cute errors lists it with its path: " .. table.concat(c.chat, "\n", l0 + 1))
    -- the next refresh draws the window whole: the Guide's tab and section there
    c.C.UI:Refresh()
    tick(c, 1)
    assert(tabsShown(c):find("^race guide prog") and sectionsShown(c):find("modules race guide", 1, true) and guideBox(c):GetChecked(),
      "the window keeps refreshing: the tab, the section, the row ticked: " .. tabsShown(c) .. " / " .. sectionsShown(c))
    check(c.C.UI.frame, "officer settings, modules, after a swallowed error in the draw")
    -- an error before the draw, in the choice itself: recorded under the check, the window drawn again all the same
    local M = c.C.Modules
    local realSet = M.Set
    M.Set = function(key, on) error("boom in Set " .. key) end
    c.env.CUTE_DEV = false
    click(guideBox(c))
    c.env.CUTE_DEV = true
    M.Set = realSet
    assert(c.env.CuteDB.errors[1].where == "check" and c.env.CuteDB.errors[1].msg:find("boom in Set guide", 1, true), "the error in the choice recorded under the check: " .. errorsWhere(c))
    assert(c.env.CuteDB.chars[me].modules.guide == true and not c.C.UI.drawing, "the choice as it was; drawing clear")
    c.C.UI:Refresh()
    tick(c, 1)
    assert(guideBox(c):GetChecked() and tabsShown(c):find("^race guide prog"), "drawn again from the choice kept: " .. tabsShown(c))
    leave(c)
  end)
  said[#said + 1] = "an error in a click's path is recorded with its path, the choice kept, the window drawing again"

  -- (b) Rule 0, with the seed (the fixture's fifty facts, asked in one frame, the verdict a frame on). First an ask
  -- that throws past C.Ask's own pcall on one item (the live client indexing a secret, say): recorded with the id,
  -- skipped, the other forty-nine asked and the verdict in. Then a chain that stalls: the frame's callback dropped
  -- (the one zero-second timer Cute sets), the band saying how far it got, the watchdog closing it at thirty seconds
  -- on what was asked, saying so under /cute errors, the Guide filling in
  local function errorOf(c, where) for _, e in ipairs(c.env.CuteDB.errors or {}) do if e.where == where then return e end end end
  if SEEDED then isolated({ member("Helga", 1) }, function()
    local c = char("Helga", 1)
    c.env.CuteDB = {}
    fire(c, "ADDON_LOADED", "Cute")
    local realAsk = c.C.Ask
    c.C.Ask = function(fn, id, ...) if tostring(id) == "30010" then error("attempt to index a secret value") end return realAsk(fn, id, ...) end
    c.env.CUTE_DEV = false
    fire(c, "PLAYER_ENTERING_WORLD", true, false)
    c.env.CUTE_DEV = true
    local R = c.C.Rules
    assert(R.SeedState() == "checking" and R.check.i == 50 and R.check.n == 50, "fifty asked in the first frame, one of them thrown: " .. tostring(R.check.i))
    local e = errorOf(c, "rules: rule 0")
    assert(e and e.msg == "rule 0: item 30010: attempt to index a secret value" or (e and e.msg:find("^rule 0: item 30010: .*attempt to index a secret value")), "the throw recorded with its kind and id: " .. tostring(e and e.msg))
    openGuide(c)
    assert(texts(c):find("Checking what we knew against this client, 50 of 50.", 1, true), "the band says how far it got:\n" .. texts(c))
    tick(c, 1)
    c.C.Ask = realAsk
    assert(R.SeedState() == "fresh" and R.check.total == 49 and R.check.absent == 0, "the verdict a frame on, on the forty-nine answered: " .. R.SeedState() .. " " .. tostring(R.check.total))
    assert(not errorOf(c, "rules: rule 0 watchdog"), "no watchdog needed")
    c.C.UI:Draw()
    assert(not texts(c):find("Checking what we knew", 1, true) and tipOf(guideHead(c)):find("From research and the beta, checked against this client", 1, true), "the Guide filled in")
    check(c.C.UI.frame, "officer guide, after an ask that threw")
    leave(c)
    -- the stalled chain
    local d = char("Helga", 1)
    d.env.CuteDB = {}
    fire(d, "ADDON_LOADED", "Cute")
    local realAfter, dropped = d.env.C_Timer.After, 0
    d.env.C_Timer.After = function(sec, f) if sec == 0 then dropped = dropped + 1; return end return realAfter(sec, f) end
    fire(d, "PLAYER_ENTERING_WORLD", true, false)
    d.env.C_Timer.After = realAfter
    local RD = d.C.Rules
    assert(dropped == 1 and RD.SeedState() == "checking" and RD.check.i == 50, "the next frame's step dropped: still checking")
    openGuide(d)
    tick(d, 20)
    assert(RD.SeedState() == "checking" and texts(d):find("Checking what we knew against this client, 50 of 50.", 1, true), "twenty seconds on, still checking, the band saying so")
    tick(d, 11)
    assert(RD.SeedState() == "fresh" and RD.check.state == "done" and RD.check.total == 50, "the watchdog closed it at thirty seconds, on what was asked: " .. RD.SeedState())
    local w = errorOf(d, "rules: rule 0 watchdog")
    assert(w and w.msg == "rule 0 did not finish: 50 of 50 asked in 30 s; judged on those", "and said so under /cute errors: " .. tostring(w and w.msg))
    d.C.UI:Draw()
    assert(tipOf(guideHead(d)):find("From research and the beta, checked against this client", 1, true) and not texts(d):find("Checking what we knew", 1, true), "the Guide filled in:\n" .. texts(d))
    tick(d, 30)
    assert(RD.check.total == 50 and errorOf(d, "rules: rule 0 watchdog").count == 1, "nothing counted twice")
    leave(d)
  end) end
  said[#said + 1] = "Rule 0 skips an ask that throws, the watchdog closes a stalled chain, the band says how far it got"

  -- (c) the key flips call by call: UnitFullName's second return the surname one call, nothing the next (so 0.6.0's
  -- C.Me gave Helga-Bluntforce and Helga-Forever by turns, and a choice saved under one was read under the other)
  isolated({ member("Helga", 1), member("Pim", 3) }, function()
    local c = char("Helga", 1, { surname = "Bluntforce", fullNameSurname = true, sender = "Helga Bluntforce" })
    local n = 0
    c.env.UnitFullName = function() n = n + 1; if n % 2 == 1 then return "Helga", "Bluntforce" end return "Helga", "" end
    login(c)
    local me = c.C.Me()
    assert(me == "Helga-Bluntforce" and c.C.Me() == me and c.C.Me() == me, "the first read is the session's key: " .. tostring(me))
    c.env.SlashCmdList.CUTE("modules")
    click(guideBox(c))
    local keys = {}
    for k in pairs(c.env.CuteDB.chars) do keys[#keys + 1] = k end
    assert(#keys == 1 and keys[1] == me and c.env.CuteDB.chars[me].modules.guide == true, "saved under that key alone: " .. table.concat(keys, ", "))
    assert(c.C.Modules.byId.guide.active and tabsShown(c):find("^race guide prog") and guideBox(c):GetChecked(), "and read back under it: the tab, the row ticked: " .. tabsShown(c))
    assert(c.C.Char() == c.env.CuteDB.chars[me], "C.Char is that record, every call")
    -- a /reload reads the same file under the same key, whichever way the call reads first
    local db = c.env.CuteDB
    leave(c)
    local d = char("Helga", 1, { surname = "Bluntforce", fullNameSurname = true, sender = "Helga Bluntforce" })
    login(d, db, true)
    assert(d.C.Me() == me and d.C.Modules.byId.guide.active, "after a /reload: the Guide on for this character")
    leave(d)
  end)
  said[#said + 1] = "a key that flips call by call saves and reads under one"

  print("the owner's client: " .. table.concat(said, "; "))
end

-- [stage: core] that stage's tests go right below this line
-- core: Cute's channel, roster and rules hardened for a guild of hundreds (the robustness and scale audits of 0.7.0):
-- the send queue survives an error and waits out the chat lockdown, a partial roster deletes nobody, a /reload asks
-- nothing, an ask says since when it holds the guild, mixed versions answer each other, and the work per roster read
-- and per rebuild stays bounded
do
  local function member(name, rank, extra) local m = { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "MAGE", level = 30, online = true }; for k, v in pairs(extra or {}) do m[k] = v end; return m end
  local function char(name, rank, extra) return newClient(charOf({ name, rank, rank <= 1 and "Officer" or "Raider", "MAGE", 30 }, extra)) end
  local function errorWith(c, s) for _, e in ipairs(c.env.CuteDB.errors or {}) do if e.msg:find(s, 1, true) then return e end end end
  local function kinds(c, from) local out = {}; for i = from or 1, #c.sent do out[#out + 1] = c.sent[i].msg:sub(1, 2) end return table.concat(out, " ") end
  local function count(c, kind, from) local n = 0; for i = from or 1, #c.sent do if c.sent[i].msg:sub(1, 2) == kind then n = n + 1 end end return n end
  local function unlock(c) c.chatLocked = false; fire(c, "ADDON_RESTRICTION_STATE_CHANGED", 5, 0) end
  local function lock(c) fire(c, "ADDON_RESTRICTION_STATE_CHANGED", 5, 1); c.chatLocked = true end
  local said = {}

  -- (a) an error while a message is on its way (its done, its covered check): recorded, that message gone, the queue
  -- going on. 0.7.0's pump stopped for the session: nothing of the member's left until /reload
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local off, mem = char("Coraline", 1), char("Cobb", 3)
    login(off); login(mem)
    tickAll(30)
    assert(off.env.CuteDB.roster[mem.sender] and off.env.CuteDB.roster[mem.sender].stats.zone == "Duskwood", "the member's record arrived")
    mem.env.CUTE_DEV = false
    mem.C.Comm.Queue({ msg = "1X|boom", done = function() error("boom in done") end })
    tickAll(3)
    mem.C.Comm.Queue({ msg = "1X|bang", covered = function() error("boom in covered") end })
    tickAll(3)
    mem.env.CUTE_DEV = true
    assert(errorWith(mem, "boom in done") and errorWith(mem, "boom in covered"), "both errors recorded")
    mem.o.zone = "Tanaris"
    fire(mem, "ZONE_CHANGED_NEW_AREA")
    tickAll(6)
    assert(off.env.CuteDB.roster[mem.sender].stats.zone == "Tanaris", "the queue went on after the errors: " .. tostring(off.env.CuteDB.roster[mem.sender].stats.zone))
    assert(#mem.C.Comm.out == 0, "nothing stuck in the queue: " .. #mem.C.Comm.out)
  end)
  said[#said + 1] = "an error on a message's way is recorded and the queue goes on"

  -- (b) the chat lockdown: a login inside a dungeon. Nothing is tried while the game holds addon chat back (no try
  -- counted, nothing given up), the ask goes first as it ends and the guild answers it; result 11 alone (a lockdown the
  -- functions do not report) is waited out the same way; a responder locked when an ask comes owes the answer rather
  -- than queueing it, and pays it as its lockdown ends; a kill claim waits out five minutes of lockdown and a run of
  -- throttles. 0.7.0 tried every ten seconds, gave each message up after five, and never asked again
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3), member("Cato", 3), member("Cass", 3) }, function()
    local off, a = char("Coraline", 1), char("Cobb", 3)
    login(off); login(a)
    tickAll(30)
    local c = char("Cyra", 3)
    c.chatLocked = true
    login(c)
    tickAll(150)
    assert(#c.sent == 0 and not errorWith(c, "addon message not sent"), "nothing sent, nothing given up while locked: " .. kinds(c))
    assert(c.C.Comm:Locked() and c.C.Comm.LockReport and c.C.Comm:LockReport():find("^lockdown on"), "the lockdown said: " .. tostring(c.C.Comm.LockReport and c.C.Comm:LockReport()))
    unlock(c)
    tickAll(2)
    assert(c.sent[1] and c.sent[1].msg:sub(1, 3) == "1R|", "the ask first, as the lockdown ends: " .. kinds(c))
    tickAll(60)
    assert(c.env.CuteDB.roster[off.sender] and c.env.CuteDB.roster[a.sender], "the guild answered her ask")
    assert(off.env.CuteDB.roster[c.sender] and off.env.CuteDB.roster[c.sender].stats.guid == c.o.guid, "and has her record")
    -- result 11 alone, six times in a row: waited out, nothing given up
    c.lock11 = 6
    c.o.zone = "Tanaris"
    fire(c, "ZONE_CHANGED_NEW_AREA")
    tickAll(100)
    assert(off.env.CuteDB.roster[c.sender].stats.zone == "Tanaris" and not errorWith(c, "addon message not sent") and c.lock11 == 0, "result 11 waited out, no try counted")
    -- a responder locked as an ask comes: the answer owed, not queued; paid as the lockdown ends
    lock(a)
    local d = char("Cato", 3)
    login(d)
    tickAll(45)
    assert(a.C.Comm.answerOwed and not d.env.CuteDB.roster[a.sender], "the answer owed while locked")
    local queued = 0
    for _, m in ipairs(a.C.Comm.out) do if m.msg:sub(1, 2) == "1F" then queued = queued + 1 end end
    assert(queued == 0, "no record queued behind the lockdown: " .. queued)
    unlock(a)
    tickAll(30)
    assert(d.env.CuteDB.roster[a.sender] and d.env.CuteDB.roster[a.sender].stats.guid == a.o.guid and not a.C.Comm.answerOwed, "paid as it ended")
    -- a kill claim through five minutes of lockdown, then a run of throttles: never given up
    local before = count(a, "1K")
    lock(a)
    a.C.Comm:Claim(4242, EPOCH + a.clock, { [c.o.guid] = true })
    tickAll(300)
    a.chatLocked = false -- (no event: the queue asks again on its own)
    a.throttle = 12
    tickAll(60)
    -- (a message behind it may run out its own tries in so long a run: the claim no longer takes them all at the head, (t))
    assert(count(a, "1K") == before + 1, "the claim went, late: " .. kinds(a))
  end)
  said[#said + 1] = "the chat lockdown waits without counting tries: the login ask goes as it ends, result 11 alone waited out, an answer owed and paid, a claim kept through five minutes and a run of throttles"

  -- (c) a partial guild list deletes nobody: members the client has not read yet (GetMemberInfo gives nothing, as while
  -- the club loads at login), or a list shorter than the club's memberCount, are no departure however many reads say
  -- so; a member gone from two whole lists a minute apart is (0.7.0 took every list for whole: two reads at login a
  -- second apart deleted the unread members' saved records)
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3), member("Cato", 3), member("Cass", 3) }, function()
    local off = char("Coraline", 1)
    local others = { char("Cobb", 3), char("Cyra", 3), char("Cato", 3) }
    login(off)
    for _, x in ipairs(others) do login(x) end
    tickAll(30)
    local db = off.env.CuteDB.roster
    for _, x in ipairs(others) do assert(db[x.sender], "a record for each member") end
    -- Cyra and Cato not read yet: two reads a second apart, then two a minute apart
    off.infoGaps = { [3] = true, [4] = true }
    for _ = 1, 2 do fire(off, "GUILD_ROSTER_UPDATE"); tickAll(1) end
    tickAll(61)
    for _ = 1, 2 do fire(off, "GUILD_ROSTER_UPDATE"); tickAll(61) end
    assert(db[others[2].sender] and db[others[3].sender], "the unread members' records kept")
    assert(not off.C.Roster.listedWhole, "the list said not whole")
    off.infoGaps = nil
    -- a list shorter than the club says
    local gone = table.remove(GUILD, 2)
    off.memberCount = #GUILD + 1
    for _ = 1, 3 do fire(off, "GUILD_ROSTER_UPDATE"); tickAll(61) end
    assert(db[others[1].sender], "a list shorter than the club's count deletes nobody")
    -- whole lists: one read, another seconds on (one miss), a third a minute on (pruned)
    off.memberCount = nil
    fire(off, "GUILD_ROSTER_UPDATE"); tickAll(2)
    fire(off, "GUILD_ROSTER_UPDATE")
    assert(db[others[1].sender], "two whole lists seconds apart are one miss")
    tickAll(61)
    fire(off, "GUILD_ROSTER_UPDATE")
    assert(not db[others[1].sender] and db[others[2].sender], "two whole lists a minute apart prune the one gone")
    table.insert(GUILD, 2, gone)
  end)
  said[#said + 1] = "a partial roster deletes nobody: unread members, a list shorter than the club; two whole lists a minute apart prune"

  -- (d) a /reload asks nothing and sends no record: only what changed since the last send before it, as a delta, and
  -- nobody online resends theirs (0.7.0's /reload asked, and every client online sent its whole record again). (e) A
  -- login asks with since, how far this character held the guild at its last logout: each responder sends what went
  -- on GUILD after it, marked as such (a 0.7 client reads the ask as before, its fingerprint none), not its whole
  -- record. (f) The ask of a client that holds no record of a sender gets that sender's part since, and asks for the
  -- whole one by its GUID (1Q), a minute on
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, a, b = char("Coraline", 1), char("Cobb", 3), char("Cyra", 3)
    login(off); login(a); login(b)
    tickAll(200)
    fire(a, "PLAYER_LOGOUT")
    local db = a.env.CuteDB
    local held = db.chars[a.name].hold
    assert(type(held) == "table" and held.club == "7" and tonumber(held.at), "the hold moved at logout, the login's ask answered")
    leave(a)
    -- (d)
    local o0, b0 = #off.sent, #b.sent
    local a2 = char("Cobb", 3, { zone = "Tanaris" })
    login(a2, db, true)
    tickAll(150)
    assert(count(a2, "1R") == 0 and count(a2, "1F") == 0 and #a2.sent <= 3, "a /reload asks nothing and sends no record: " .. kinds(a2))
    assert(off.env.CuteDB.roster[a2.sender].stats.zone == "Tanaris" and b.env.CuteDB.roster[a2.sender].stats.zone == "Tanaris", "what changed went")
    assert(count(off, "1F", o0 + 1) == 0 and count(b, "1F", b0 + 1) == 0, "nobody resent a record: " .. kinds(off, o0 + 1) .. " / " .. kinds(b, b0 + 1))
    fire(a2, "PLAYER_LOGOUT")
    assert(db.chars[a.name].hold.at == held.at, "a /reload's logout moves no hold: it asked nothing")
    leave(a2)
    -- (e) Cyra's zone changes while Cobb is away; his login asks since his hold
    b.o.zone = "Feralas"
    fire(b, "ZONE_CHANGED_NEW_AREA")
    tickAll(30)
    local b1 = #b.sent
    local a3 = char("Cobb", 3, { zone = "Tanaris" })
    login(a3, db)
    tickAll(150)
    local ask
    for _, m in ipairs(a3.sent) do if m.msg:sub(1, 3) == "1R|" then ask = ask or m.msg end end
    local hex = ask and ask:match("^1R|[^|]*|%d+|%d*|(%x*)$")
    assert(hex and #hex > 16 and tonumber(hex:sub(17), 16) == held.at, "the ask carries the hold as since: " .. tostring(ask))
    local s1, s2, fp7 = ask:match("^1R|[^|]*|(%d+)|?(%d*)|?(%x*)$")
    assert(tonumber(s1) and tonumber(s2) and #fp7 ~= 16, "a 0.7 client reads its stamps, and no fingerprint")
    local fs = {}
    for i = b1 + 1, #b.sent do if b.sent[i].msg:sub(1, 2) == "1F" then fs[#fs + 1] = b.sent[i].msg end end
    assert(#fs >= 1 and #fs <= 2, "Cyra answers with a part, not her whole record: " .. #fs .. " chunks")
    for _, m in ipairs(fs) do assert(m:find("^1F|%d+|%d+|%d+s|") and m:match("^1F|%d+|%d+|[^|]*|(.*)$"), "marked since, read by a 0.7 client as a record: " .. m) end
    assert(table.concat(fs, " "):find("zone=Feralas", 1, true), "with the zone: " .. table.concat(fs, " "))
    assert(a3.env.CuteDB.roster[b.sender].stats.zone == "Feralas" and a3.env.CuteDB.roster[b.sender].stats.level == 30, "Cobb holds her record as it is")
    -- (an ask made for a reason, /cute resend here, wants every record whole: no since)
    local r0 = #a3.sent
    a3.env.SlashCmdList.CUTE("resend")
    tickAll(3)
    local resend
    for k = r0 + 1, #a3.sent do if a3.sent[k].msg:sub(1, 3) == "1R|" then resend = a3.sent[k].msg end end
    assert(resend and #(resend:match("|(%x*)$") or "") == 16, "/cute resend asks whole: " .. tostring(resend))
    -- (its answer, whole, had all come before the hold: (ab), M:Borne)
    tickAll(150)
    fire(a3, "PLAYER_LOGOUT")
    leave(a3)
    -- (f) Cobb's file lost Cyra's record (0.7.0's partial roster deleted such), his hold still says he has the guild
    db.roster[b.sender] = nil
    local b2 = #b.sent
    local a4 = char("Cobb", 3, { zone = "Tanaris" })
    login(a4, db)
    tickAll(200)
    assert(count(a4, "1Q") == 1 and a4.sent[#a4.sent].msg == "1Q|" .. b.o.guid or count(a4, "1Q") == 1, "asked Cyra's whole record by her GUID: " .. kinds(a4))
    local whole = false
    for i = b2 + 1, #b.sent do if b.sent[i].msg:find("^1F|1|%d+|%d+|") then whole = true end end
    local r = a4.env.CuteDB.roster[b.sender]
    assert(whole and r and r.stats.guid == b.o.guid and r.stats.durability ~= nil and r.stats.zone == "Feralas", "and has it whole")
    for _, x in ipairs({ off, b, a4 }) do leave(x) end
  end)
  said[#said + 1] = "a /reload asks nothing and resends nothing; a login asks since its hold and is sent what changed; a record lost is asked for whole by GUID"
  -- (f2) a file that lost many records (0.7.0's partial roster could delete dozens): one ask without since, every
  -- record whole, in place of a 1Q each
  do
    local guild = { member("Coraline", 1) }
    for i = 1, 14 do guild[#guild + 1] = member("Qq" .. i, 3) end
    isolated(guild, function()
      local c = char("Coraline", 1)
      login(c)
      tickAll(80)
      local s0 = #c.sent
      for i = 1, 12 do
        c.C.Comm:Receive("1F|1|1|4s|guid=" .. guidOf("Qq" .. i) .. ";level=u", "GUILD", "Qq" .. i .. "-Forever")
      end
      tickAll(10)
      local asks, wholes = {}, 0
      for k = s0 + 1, #c.sent do
        local m = c.sent[k].msg
        if m:sub(1, 3) == "1R|" then asks[#asks + 1] = m end
        if m:sub(1, 3) == "1Q|" then wholes = wholes + 1 end
      end
      assert(#asks == 1 and #(asks[1]:match("|(%x*)$") or "") == 16 and wholes == 0, "twelve records missing: one ask without since, no 1Q: " .. #asks .. " asks, " .. wholes .. " 1Q")
    end)
  end
  said[#said + 1] = "a file missing many records asks once, whole"

  -- (g) mixed versions: a 0.5.x ask (no stamp) gets the record and never the statistics pass; a 0.7 ask (no since) the
  -- whole record and the pass; asks within ten minutes of a pass wait for the next one, whoever asks
  isolated({ member("Coraline", 1), member("Cyra", 3), member("Cass", 3), member("Cato", 3), member("Cid", 3) }, function()
    local off, b = char("Coraline", 1), char("Cyra", 3, { withStats = true })
    login(off); login(b)
    tickAll(200)
    local function pass(from) for i = from + 1, #b.sent do if b.sent[i].msg:find("g2001=", 1, true) then return true end end return false end
    local b0 = #b.sent
    b.C.Comm:Receive("1R|" .. guidOf("Cass"), "GUILD", "Cass-Forever")
    tickAll(150)
    assert(count(b, "1F", b0 + 1) >= 3 and not pass(b0), "a 0.5.x ask: the record, no pass: " .. kinds(b, b0 + 1))
    local b1 = #b.sent
    local fp = b.C.Policy:Fp()
    b.C.Comm:Receive("1R|" .. guidOf("Cato") .. "|0|0|" .. fp, "GUILD", "Cato-Forever")
    tickAll(150)
    assert(count(b, "1F", b1 + 1) >= 4 and pass(b1), "a 0.7 ask: the record and the pass: " .. kinds(b, b1 + 1))
    local b2 = #b.sent
    b.C.Comm:Receive("1R|" .. guidOf("Cid") .. "|0|0|" .. fp, "GUILD", "Cid-Forever")
    tickAll(150)
    assert(not pass(b2), "another ask within ten minutes: no second pass yet")
    tickAll(400)
    assert(pass(b2), "the next pass as the ten minutes end")
    for _, x in ipairs({ off, b }) do leave(x) end
  end)
  said[#said + 1] = "a 0.5.x ask gets no statistics pass, a 0.7 ask the whole record and one, one pass in ten minutes"

  -- (h) scale: a guild of 400, 150 online, three of them running Cute here (an officer and two members) holding 120 of
  -- the others' records; a login wave of 25 asks in a minute, about half from members whose since this login's records
  -- cover. Each client's queue stays short and what it sends in five minutes stays bounded: the answers coalesce, a
  -- since gets what changed, the pass goes once in ten minutes (0.7.0 answered every new asker whole, its record and
  -- its pass, the guild's traffic growing with the square of those online)
  do
    local guild = {}
    for i = 1, 397 do guild[i] = { name = "Mm" .. i .. "-Forever", guid = string.format("Player-4242-%08X", 0x0B000000 + i), rank = 3, rankName = "Raider", class = "MAGE", level = 20 + i % 40, online = i <= 147 } end
    guild[#guild + 1] = member("Coraline", 1); guild[#guild + 1] = member("Cobb", 3); guild[#guild + 1] = member("Cyra", 3)
    isolated(guild, function()
      local function saved()
        local roster = {}
        for i = 1, 120 do
          local st = { guid = guild[i].guid, level = guild[i].level, addon_ver = "0.7.1", zone = "Duskwood", deaths = i, gold = 1000 * i }
          for j = 1, 30 do st["g" .. (3000 + j)] = i + j end
          roster[guild[i].name] = { seen = EPOCH + 900, online = guild[i].online, stats = st, at = {}, ch = true }
        end
        return { roster = roster }
      end
      local cs = { char("Coraline", 1, { withStats = true }), char("Cobb", 3, { withStats = true }), char("Cyra", 3, { withStats = true }) }
      for _, c in ipairs(cs) do login(c, saved()) end
      tickAll(240)
      local before, most = {}, {}
      for i, c in ipairs(cs) do before[i] = #c.sent; most[i] = 0 end
      for k = 1, 25 do
        local m = guild[150 + k]
        for _, c in ipairs(cs) do
          local since = (k % 2 == 0 and c.C.Comm.base) and string.format("%x", math.floor(c.C.Comm.base + 5)) or ""
          c.C.Comm:Receive("1R|" .. m.guid .. "|0|0|" .. c.C.Policy:Fp() .. since, "GUILD", m.name)
        end
        for _ = 1, 2 do tickAll(1); for i, c in ipairs(cs) do most[i] = math.max(most[i], #c.C.Comm.out) end end
      end
      for _ = 1, 250 do tickAll(1); for i, c in ipairs(cs) do most[i] = math.max(most[i], #c.C.Comm.out) end end
      local note = {}
      for i, c in ipairs(cs) do
        local n = #c.sent - before[i]
        note[#note + 1] = c.o.name .. " " .. n .. " sent, queue " .. most[i]
        -- (0.7.1 here: the officer 48, each member 29; the officer answers the officers' word to askers holding an older one)
        assert(n <= (i == 1 and 42 or 22) and most[i] <= 30, "a login wave of 25 asks: " .. c.o.name .. " sent " .. n .. ", its queue at most " .. most[i] .. ": " .. kinds(c, before[i] + 1))
      end
      said[#said + 1] = "400 members, 150 online, a wave of 25 asks: " .. table.concat(note, "; ")
    end)
  end

  -- (i) the work per roster read and per rebuild, a guild of 500 and an officer holding 500 records of 230 values each
  -- (130 of them statistics and discoveries): a read with nothing changed walks no record and asks no officer list
  -- again; a member coming online asks no officer list again; a storm of 300 records changing discoveries over a minute
  -- builds the model three times at most, and records that change nothing build it never (0.7.0 walked every record at
  -- every read, built the officer list again at every online flip, and the model every three seconds)
  do
    local guild = {}
    for i = 1, 499 do guild[i] = { name = "Pp" .. i .. "-Forever", guid = string.format("Player-4242-%08X", 0x0C000000 + i), rank = 3, rankName = "Raider", class = "MAGE", level = 20 + i % 40, online = i <= 150 } end
    guild[#guild + 1] = member("Coraline", 1)
    isolated(guild, function()
      local roster = {}
      for i = 1, 499 do
        local st = { guid = guild[i].guid, level = guild[i].level, addon_ver = "0.7.1", zone = "Duskwood" }
        for j = 1, 96 do st["d" .. j] = j end
        for j = 1, 100 do st["g" .. (3000 + j)] = i + j end
        for j = 1, 10 do st["e" .. (5000 + j)] = 1; st["k" .. (5000 + j)] = 20 + j end
        for j = 1, 10 do st["i" .. (600 + j)] = 1 end
        roster[guild[i].name] = { seen = EPOCH + 900, online = guild[i].online, stats = st, at = {}, ch = true }
      end
      local c = char("Coraline", 1)
      login(c, { roster = roster })
      tickAll(120)
      local R, Rules = c.C.Roster, c.C.Rules
      local calls = { memberOf = 0, takes = 0, rebuild = 0 }
      local realMemberOf, realTakes, realRebuild = R.MemberOf, R.TakesWhispers, Rules.Rebuild
      R.MemberOf = function(...) calls.memberOf = calls.memberOf + 1; return realMemberOf(...) end
      R.TakesWhispers = function(...) calls.takes = calls.takes + 1; return realTakes(...) end
      Rules.Rebuild = function(...) calls.rebuild = calls.rebuild + 1; return realRebuild(...) end
      -- a read with nothing changed
      local reads = c.memberReads or 0
      fire(c, "GUILD_ROSTER_UPDATE")
      R:OfficerTargets()
      assert(calls.memberOf == 0 and calls.takes == 0, "a read with nothing changed walks no record: " .. calls.memberOf .. " member lookups, " .. calls.takes .. " officer checks")
      assert((c.memberReads or 0) - reads <= 500, "one GetMemberInfo a member: " .. ((c.memberReads or 0) - reads))
      -- a member comes online
      guild[300].online = true
      fire(c, "GUILD_ROSTER_UPDATE")
      R:OfficerTargets()
      assert(calls.takes == 0, "a member online asks no officer list again: " .. calls.takes)
      -- 300 records changing a discovery over a minute; then the same values again
      tickAll(40)
      calls.rebuild = 0
      for k = 1, 300 do
        c.C.Comm:Receive("1D|4|e" .. (5100 + k) .. "=1", "GUILD", guild[k].name)
        if k % 5 == 0 then tickAll(1) end
      end
      tickAll(40)
      local storm = calls.rebuild
      assert(storm >= 1 and storm <= 3, "300 records over a minute build the model three times at most: " .. storm)
      calls.rebuild = 0
      for k = 1, 300 do c.C.Comm:Receive("1D|4|e" .. (5100 + k) .. "=1;zone=Duskwood;level=" .. c.C.Comm.b36(guild[k].level), "GUILD", guild[k].name); if k % 5 == 0 then tickAll(1) end end
      tickAll(40)
      assert(calls.rebuild == 0, "records that change nothing build nothing: " .. calls.rebuild)
      R.MemberOf, R.TakesWhispers, Rules.Rebuild = realMemberOf, realTakes, realRebuild
      said[#said + 1] = string.format("500 records of 230 values: a quiet read walks none, an online flip asks no officer list, a storm of 300 builds %d times, an echo none", storm)
    end)
  end

  -- (j) a file left odd (a record and a character that are no tables) is cleaned at load: the roster reads, Guild Info
  -- with it, and the record goes; a handler of an event that raises leaves the event's others to run (the zone read
  -- again on a loading screen whose instance check raised); /cute errors doubles a | in what it prints
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local off = char("Coraline", 1)
    login(off)
    local c = char("Cobb", 3)
    c.env.CUTE_DEV = false
    login(c, { policyClub = "7", roster = { ["Junk-Forever"] = 5, ["Odd-Forever"] = { stats = 7, at = "x", seen = "y" } }, chars = { ["Cobb-Forever"] = 7 } })
    tickAll(40)
    assert(not errorWith(c, "attempt to"), "no error from the odd file: " .. tostring(errorWith(c, "attempt to") and errorWith(c, "attempt to").msg))
    assert(c.env.CuteDB.roster["Junk-Forever"] == nil and type(c.env.CuteDB.roster["Odd-Forever"].stats) == "table" and type(c.env.CuteDB.chars["Cobb-Forever"]) == "table", "cleaned at load")
    assert(c.C.Policy:Settled() and off.env.CuteDB.roster[c.sender] and off.env.CuteDB.roster[c.sender].stats.guid == c.o.guid, "Guild Info read, the record sent")
    local S = c.C.Sample
    local real = S.InstanceCheck
    S.InstanceCheck = function() error("boom in the instance check") end
    c.o.zone = "Feralas"
    fire(c, "PLAYER_ENTERING_WORLD", false, false)
    tick(c, 2)
    S.InstanceCheck = real
    assert(S:Value("zone") == "Feralas" and errorWith(c, "boom in the instance check"), "the zone read again though the instance check raised")
    c.C.Err.Record("a |Tlink|t in an error", "", "where |r")
    local n0 = #c.chat
    c.env.SlashCmdList.CUTE("errors")
    local out = table.concat(c.chat, "\n", n0 + 1)
    assert(out:find("a ||Tlink||t in an error", 1, true) and out:find("where ||r", 1, true), "/cute errors doubles the |: " .. out)
    c.env.CUTE_DEV = true
  end)
  said[#said + 1] = "an odd saved file cleaned at load, an event's handlers each on their own, /cute errors' | doubled"

  -- (k) a renamed character takes its counters along (the record its GUID kept under the old key); typed emotes
  -- count through C_ChatInfo.PerformEmote, once each where DoEmote wraps it
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local c = char("Cobb", 3, { withPerform = true, withEmote = true })
    login(c, { chars = { ["Cobbold-Forever"] = { guid = guidOf("Cobb"), counters = { deaths = 9, dance = 2 } } } })
    assert(c.C.Sample:Value("deaths") == 9 and c.env.CuteDB.chars["Cobbold-Forever"] == nil and c.env.CuteDB.chars[c.name].counters.deaths == 9, "the old key's counters taken over: " .. tostring(c.C.Sample:Value("deaths")))
    c.env.C_ChatInfo.PerformEmote("DANCE")
    c.env.C_ChatInfo.PerformEmote("Dance")
    c.env.DoEmote("SIT")
    assert(c.C.Sample:Value("dance") == 4 and c.C.Sample:Value("sit") == 1, "emotes by PerformEmote's token, DoEmote's once: dance " .. tostring(c.C.Sample:Value("dance")) .. ", sit " .. tostring(c.C.Sample:Value("sit")))
  end)
  said[#said + 1] = "a rename keeps the counters, typed emotes counted by token"

  -- (l) leaving the guild: the window shows you alone at once; half a minute on, still out, the values the officers kept
  -- to themselves leave the records (an officer who left held every member's Only-you values for good), unless another
  -- character of the account is one of its officers
  for _, alt in ipairs({ false, true }) do
    isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
      local off, a = char("Coraline", 1), char("Cobb", 3, { money = 777777 })
      local db = alt and { chars = { ["Altea-Forever"] = { guid = guidOf("Altea"), officerOf = 7, counters = {} } } } or nil
      login(off, db); login(a)
      tickAll(60)
      local rec = off.env.CuteDB.roster[a.sender]
      assert(rec and rec.stats.gold == 777777, "the officer holds the member's gold")
      off.inGuild = false
      fire(off, "PLAYER_GUILD_UPDATE", "player")
      local rows = off.C.Roster:Rows()
      assert(#rows == 1 and rows[1].me, "out of the guild: you alone in the window: " .. #rows)
      tickAll(100)
      if alt then assert(rec.stats.gold == 777777, "an officer alt of the account: kept")
      else assert(rec.stats.gold == nil and rec.stats.level ~= nil, "left: the gold gone, the rest kept") end
    end)
  end
  said[#said + 1] = "leaving the guild shows you alone and takes the officers' values out, unless an alt is one"

  -- (m) a newer Cute's line beside this one's in Guild Info: this one's read (a newer format alone holds the client);
  -- the statistics read in slices of a hundred a frame; the mount read on its events, not every minute; a raid's bag
  -- changes scanned a second after the last
  do
    local P = yezin.C.Policy
    local v1 = infoLine({ vis = { gold = "self" }, threshold = 1 })
    local both = P.ParseLine("Welcome!\n" .. v1 .. "\nCute 2 abc 1 0123456789abcdef +zz")
    assert(both and both.fp and not both.newer, "this format's line read beside a newer one")
    local alone = P.ParseLine("Welcome!\nCute 2 abc 1 0123456789abcdef +zz")
    assert(alone and alone.newer, "a newer format alone: newer")
  end
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local c = char("Cobb", 3, { withStats = true, manyStats = 300 })
    login(c)
    tickAll(60)
    local reads = c.statReads or 0
    c.C.Sample.gamePassAt = nil
    fire(c, "CRITERIA_UPDATE")
    local first = (c.statReads or 0) - reads
    tick(c, 1)
    local all = (c.statReads or 0) - reads
    assert(first <= 100 and all >= 300, "the statistics in slices: " .. first .. " in the first frame, " .. all .. " in all")
    local mounts = 0
    local real = c.env.C_MountJournal.GetMountIDs
    c.env.C_MountJournal.GetMountIDs = function(...) mounts = mounts + 1; return real(...) end
    tick(c, 200)
    assert(mounts == 0, "the heartbeat walks no mount: " .. mounts)
    fire(c, "NEW_MOUNT_ADDED", 1)
    tick(c, 2)
    assert(mounts == 1, "a mount added: read once: " .. mounts)
    c.env.C_MountJournal.GetMountIDs = real
    c.C.Sample.track.inRaid = true
    local scans = 0
    local bag = c.C.Stats.BagClear
    c.C.Stats.BagClear = function(...) scans = scans + 1; return bag(...) end
    for _ = 1, 20 do fire(c, "BAG_UPDATE_DELAYED"); tick(c, 0.05) end
    tick(c, 2)
    c.C.Stats.BagClear = bag
    c.C.Sample.track.inRaid = false
    assert(scans == 1, "twenty bag changes in a raid: one scan: " .. scans)
  end)
  said[#said + 1] = "a newer line beside ours read as ours, statistics in slices, the mount on its events, a raid's bags once a burst"

  -- (o) /cute help is two short lines, the paste tools under /cute help more; a statistic or discovery that came keeps
  -- no time of its own (the registry's stats do, for their tooltips), and a file's old ones go once at load; gold that
  -- changes at every coin goes once in ten seconds, its last value always
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local off = char("Coraline", 1)
    local db = { policyClub = "7", roster = { ["Old-Forever"] = { seen = EPOCH + 900, stats = { g3001 = 4, level = 20 }, at = { g3001 = EPOCH, level = EPOCH } } } }
    login(off, db)
    local n0 = #off.chat
    off.env.SlashCmdList.CUTE("help")
    assert(#off.chat == n0 + 2 and off.chat[n0 + 2]:find("/cute help more", 1, true), "two lines of help")
    off.env.SlashCmdList.CUTE("help more")
    assert(#off.chat == n0 + 3 and off.chat[n0 + 3]:find("/cute diag", 1, true), "the paste tools under help more")
    local old = db.roster["Old-Forever"]
    assert(old.at.g3001 == nil and old.at.level == EPOCH, "a file's old statistic times gone at load, the rest kept")
    local c = char("Cobb", 3, { withStats = true, money = 1000 })
    login(c)
    tickAll(40)
    local e = off.env.CuteDB.roster[c.sender]
    tickAll(100)
    assert(e.stats.g2001 and e.at.g2001 == nil and e.at.level, "a statistic that came keeps no time, the level does")
    local w0 = 0
    for _, m in ipairs(c.sent) do if m.channel == "WHISPER" then w0 = w0 + 1 end end
    for _ = 1, 30 do c.o.money = c.o.money + 3; fire(c, "PLAYER_MONEY"); tickAll(1) end
    tickAll(12)
    local w = -w0
    for _, m in ipairs(c.sent) do if m.channel == "WHISPER" then w = w + 1 end end
    assert(w <= 4 and e.stats.gold == c.o.money, "thirty seconds of gold at every coin: " .. w .. " whispers to the officer, the last value there")
  end)
  said[#said + 1] = "help in two lines, statistics keep no times, gold once in ten seconds"

  -- (n) /cute diag says what launch day needs to see, no name in it: the last send result each way, the lockdown as each
  -- function says it, whether this rank may speak in guild chat, how far this character holds the guild, the list
  -- against the club's count and the namesakes nobody can tell apart, and what the busy paths cost
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local off, c = char("Coraline", 1), char("Cobb", 3)
    login(off); login(c)
    tickAll(130)
    local n0 = #c.chat
    c.env.SlashCmdList.CUTE("diag")
    local out = table.concat(c.chat, "\n", n0 + 1)
    for _, want in ipairs({ "diag channel: GUILD result 0 ", "| WHISPER ", "| prefix 0 | CanSpeakInGuildChat true",
      "diag lockdown off (InChatMessagingLockdown false, restriction false, event never, result 11 never) | AreOutgoingAddonChatMessagesRestricted false",
      "diag sync: holds the guild to nothing | this login fresh, its record whole ", "| answers owed: record no, pass no; askers 1, 0 waiting",
      "diag list: 2 of 2 read (0 not read), whole | unsure namesakes 0",
      "diag perf: refresh ", "rebuild ", "receive ", "| last minute: addon " }) do
      assert(out:find(want, 1, true), "/cute diag says " .. want .. ":\n" .. out)
    end
    local tail = out:sub((out:find("diag channel:", 1, true)))
    assert(not tail:find("Coraline", 1, true) and not tail:find("Cobb", 1, true), "and names nobody:\n" .. tail)
    c.chatLocked = true
    lock(c)
    n0 = #c.chat
    c.env.SlashCmdList.CUTE("diag")
    assert(table.concat(c.chat, "\n", n0 + 1):find("diag lockdown on (InChatMessagingLockdown true, restriction true", 1, true), "the lockdown said as it holds")
    unlock(c)
  end)
  said[#said + 1] = "/cute diag: the channel, the lockdown, the hold, the list, the cost, no name"

  -- (p) a since the responder cannot bear out is answered whole. The asker's hold moves at its logout whether or not
  -- every answer came, so each responder judges a since by the answer it gave that asker's ask before it: one that went
  -- after the since (a pass deferred behind the ten minutes, an answer owed through a lockdown and paid once the asker
  -- had gone) or never (an ask passed by within three minutes of the last) bears out nothing. A first build took
  -- every since, and the asker never had what it missed
  local function cyraOf(c) return c.env.CuteDB.roster["Cyra-Forever"] end
  local function oldFile() return { chars = { ["Cobb-Forever"] = { guid = guidOf("Cobb"), counters = {}, hold = { club = "7", at = EPOCH + 100 } } },
    roster = { ["Cyra-Forever"] = { seen = EPOCH + 100, stats = { guid = guidOf("Cyra"), level = 30, zone = "Old" }, at = {}, ch = true } } } end
  -- a pass deferred: Cyra forced one for Cato, so Cobb's waits out the ten minutes; he logs out before it goes
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3), member("Cato", 3) }, function()
    local off, b = char("Coraline", 1), char("Cyra", 3, { withStats = true })
    login(off); login(b)
    tickAll(200)
    b.C.Comm:Receive("1R|" .. guidOf("Cato") .. "|0|0|" .. b.C.Policy:Fp(), "GUILD", "Cato-Forever")
    tickAll(100)
    assert(b.C.Comm.passAt, "Cyra forced a pass for Cato")
    local db = oldFile()
    local a = char("Cobb", 3)
    login(a, db)
    tickAll(200)
    assert(cyraOf(a).stats.zone == "Duskwood" and cyraOf(a).stats.g2001 == nil, "Cobb has Cyra's record, her pass waits: " .. tostring(cyraOf(a).stats.g2001))
    fire(a, "PLAYER_LOGOUT"); leave(a)
    local hold = db.chars["Cobb-Forever"].hold.at
    assert(hold > EPOCH + 100, "his hold moved")
    tickAll(500)
    local a2 = char("Cobb", 3)
    login(a2, db)
    tickAll(800)
    assert(cyraOf(a2).stats.g2001 == 1234, "his next ask, since that hold, has her pass whole: " .. tostring(cyraOf(a2).stats.g2001))
    for _, x in ipairs({ off, b, a2 }) do leave(x) end
  end)
  -- an answer owed through a lockdown, paid after the asker left; then an ask passed by within three minutes
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, b = char("Coraline", 1), char("Cyra", 3)
    login(off); login(b)
    tickAll(200)
    lock(b)
    local db = oldFile()
    local a = char("Cobb", 3)
    login(a, db)
    tickAll(200)
    assert(cyraOf(a).stats.zone == "Old" and b.C.Comm.answerOwed, "Cyra owes Cobb her record")
    fire(a, "PLAYER_LOGOUT"); leave(a)
    unlock(b)
    tickAll(60)
    local a2 = char("Cobb", 3)
    login(a2, db)
    tickAll(120)
    assert(cyraOf(a2).stats.zone == "Duskwood", "his next ask has her record whole: " .. tostring(cyraOf(a2).stats.zone))
    fire(a2, "PLAYER_LOGOUT"); leave(a2)
    -- she moves while he is away; he is back within three minutes of his last ask, which she passes by
    b.o.zone = "Feralas"
    fire(b, "ZONE_CHANGED_NEW_AREA")
    tickAll(5)
    local a3 = char("Cobb", 3)
    login(a3, db)
    tickAll(110)
    assert(cyraOf(a3).stats.zone == "Duskwood", "an ask within three minutes of the last is passed by")
    fire(a3, "PLAYER_LOGOUT"); leave(a3)
    tickAll(200)
    local a4 = char("Cobb", 3)
    login(a4, db)
    tickAll(120)
    assert(cyraOf(a4).stats.zone == "Feralas", "the next ask, since a hold that ask bore out nothing of, has her record whole: " .. tostring(cyraOf(a4).stats.zone))
    for _, x in ipairs({ off, b, a4 }) do leave(x) end
  end)
  said[#said + 1] = "a since the responder's last answer to that asker does not bear out is answered whole: a pass deferred, an answer owed through a lockdown, an ask passed by"

  -- (q) the hold leaves a minute: what went on GUILD in the second the asker logged out (still on its way, as the game's
  -- server time counts whole seconds) is sent again at its next ask. A first build held the logout's own second
  -- and a part sent in it, "after" nothing, was never sent again
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, a, b = char("Coraline", 1), char("Cobb", 3), char("Cyra", 3)
    b.env.GetServerTime = function() return EPOCH + math.floor(b.clock) end
    local db = {}
    login(off); login(a, db); login(b)
    tickAll(200)
    b.o.zone = "Feralas"
    b.C.Sample:Set("zone", "Feralas")
    tick(b, 1)
    tick(a, 1); tick(off, 1)
    fire(a, "PLAYER_LOGOUT"); leave(a)
    local hold = db.chars["Cobb-Forever"].hold.at
    assert(hold <= EPOCH + a.clock - 60, "the hold a minute before the logout: " .. (EPOCH + a.clock - hold))
    tick(b, 1)
    assert(b.sent[#b.sent].msg:find("zone=Feralas", 1, true), "her zone went in the second he logged out")
    tickAll(10)
    local a2 = char("Cobb", 3)
    login(a2, db)
    tickAll(120)
    assert(cyraOf(a2).stats.zone == "Feralas", "his next ask has it: " .. tostring(cyraOf(a2).stats.zone))
    for _, x in ipairs({ off, b, a2 }) do leave(x) end
  end)
  said[#said + 1] = "the hold leaves a minute, so a part sent as the asker logged out goes again"

  -- (r) an ask heard while this client's record waits for the policy (a /reload reads Guild Info again: seconds, or a
  -- whole run inside an instance) is answered once it holds it. A first build dropped the answer whose time came
  -- while it waited, and a /reload's release sends only what changed
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, r = char("Coraline", 1), char("Cobb", 3)
    login(off); login(r)
    tickAll(60)
    local db = r.env.CuteDB
    fire(r, "PLAYER_LOGOUT"); leave(r)
    local r2 = char("Cobb", 3)
    r2.infoSecret = true
    login(r2, db, true)
    local a = char("Cyra", 3)
    login(a)
    tickAll(60)
    assert(r2.C.Comm.holding and not a.env.CuteDB.roster[r2.sender], "Cobb's record waits for Guild Info")
    r2.infoSecret = false
    fire(r2, "GUILD_ROSTER_UPDATE")
    tickAll(30)
    local rec = a.env.CuteDB.roster[r2.sender]
    assert(not r2.C.Comm.holding and rec and rec.stats.guid == r2.o.guid, "her ask answered once he holds the policy")
    for _, x in ipairs({ off, r2, a }) do leave(x) end
  end)
  said[#said + 1] = "an ask heard while the record waits for the policy is answered as it goes"

  -- (s) an answer owed through a lockdown the event never ends (an open-world encounter: InChatMessagingLockdown alone,
  -- or a client the event never reaches) is paid within LOCK_POLL seconds of its end, the queue empty or not, and the
  -- statistics pass with it. A first build paid it only at the event, a loading screen or the policy settling
  -- (with his queue as it is, and with it empty, its pump stopped)
  for _, empty in ipairs({ false, true }) do isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, r = char("Coraline", 1), char("Cobb", 3, { withStats = true })
    login(off); login(r)
    tickAll(150)
    r.chatLocked = true
    local a = char("Cyra", 3)
    login(a)
    tickAll(120)
    assert(r.C.Comm.answerOwed and r.C.Comm.gameOwed and not a.env.CuteDB.roster[r.sender], "Cobb owes Cyra his record and pass")
    if empty then
      for i = #r.C.Comm.out, 1, -1 do table.remove(r.C.Comm.out, i) end
      tickAll(15)
    end
    r.chatLocked = false
    tickAll(60)
    local rec = a.env.CuteDB.roster[r.sender]
    assert(not r.C.Comm.answerOwed and rec and rec.stats.guid == r.o.guid, "paid as the lockdown ended, no event: " .. tostring(r.C.Comm.answerOwed))
    tickAll(30)
    assert(not r.C.Comm.gameOwed and rec.stats.g2001 == 1234, "and the pass: " .. tostring(rec.stats.g2001))
    for _, x in ipairs({ off, r, a }) do leave(x) end
  end) end
  said[#said + 1] = "an answer owed through a lockdown with no end event is paid as it ends"

  -- (t) a kill claim the client keeps answering "later" (9, GeneralError, every time) goes to the back of the queue
  -- after RETRIES tries, and what waits behind it goes; it goes itself once the client takes it. A first build
  -- retried it at the head of the queue for good, and nothing else of the member's ever left
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local off, a = char("Coraline", 1), char("Cobb", 3)
    login(off); login(a)
    tickAll(60)
    a.refuse = function(msg) if msg:sub(1, 3) == "1K|" then return 9 end end
    a.C.Comm:Claim(4242, EPOCH + a.clock, {})
    tickAll(2)
    a.o.zone = "Tanaris"
    a.C.Sample:Set("zone", "Tanaris")
    tickAll(90)
    assert(off.env.CuteDB.roster[a.sender].stats.zone == "Tanaris", "the queue went past the refused claim: " .. tostring(off.env.CuteDB.roster[a.sender].stats.zone))
    a.refuse = nil
    tickAll(120)
    assert(count(a, "1K") == 1, "and the claim went once the client took it: " .. kinds(a))
    for _, x in ipairs({ off, a }) do leave(x) end
  end)
  said[#said + 1] = "a claim refused again and again goes to the back of the queue, the rest going past it"

  -- (u) a /reload in a raid's lockdown (after a wipe, say) keeps what waited for it to end: a repeat kill's claim still
  -- queued, and the record owed to a member who logged in meanwhile, both sent once it ends. A first build kept
  -- neither: a repeat kill's claim is kept nowhere else, and nothing answered that member's ask again
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, a = char("Coraline", 1), char("Cobb", 3)
    login(off); login(a)
    tickAll(60)
    lock(a)
    a.C.Comm:Claim(4242, EPOCH + a.clock, { [off.o.guid] = true })
    local b = char("Cyra", 3)
    login(b, { roster = { ["Cobb-Forever"] = { seen = EPOCH + 100, stats = { guid = guidOf("Cobb"), level = 30, zone = "Old" }, at = {}, ch = true } } })
    tickAll(60)
    assert(a.C.Comm.answerOwed and count(a, "1K") == 0, "the claim waits, the answer is owed")
    local db = a.env.CuteDB
    fire(a, "PLAYER_LOGOUT"); leave(a)
    local a2 = char("Cobb", 3)
    a2.chatLocked = true
    login(a2, db, true)
    tickAll(60)
    assert(count(a2, "1K") == 0 and b.env.CuteDB.roster[a2.sender].stats.zone == "Old", "still locked after the /reload")
    unlock(a2)
    tickAll(60)
    assert(count(a2, "1K") == 1, "the claim went after the /reload: " .. kinds(a2))
    local rec = b.env.CuteDB.roster[a2.sender]
    assert(rec.stats.zone == "Duskwood", "and Cyra has the record owed her: " .. tostring(rec.stats.zone))
    for _, x in ipairs({ off, a2, b }) do leave(x) end
  end)
  said[#said + 1] = "a /reload in the lockdown keeps a queued kill claim and an owed answer"

  -- (v) a record asked for whole by GUID (1Q: a file that lost it, a since part from a sender it holds nothing of) is
  -- answered with its statistics pass too. A first build sent the record alone, and the asker's later asks, all
  -- since its hold, never brought what the pass had said before it
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, a, b = char("Coraline", 1), char("Cobb", 3), char("Cyra", 3, { withStats = true })
    local db = {}
    login(off); login(a, db); login(b)
    tickAll(200)
    assert(db.roster[b.sender].stats.g2001 == 1234, "Cobb has Cyra's statistics")
    fire(a, "PLAYER_LOGOUT"); leave(a)
    db.roster[b.sender] = nil
    b.o.zone = "Feralas"
    b.C.Sample:Set("zone", "Feralas")
    tickAll(30)
    local a2 = char("Cobb", 3)
    login(a2, db)
    tickAll(700)
    local rec = db.roster[b.sender]
    assert(count(a2, "1Q") == 1 and rec and rec.stats.zone == "Feralas", "Cobb asked her record whole and has it")
    assert(rec.stats.g2001 == 1234, "and her statistics: " .. tostring(rec.stats.g2001))
    for _, x in ipairs({ off, b, a2 }) do leave(x) end
  end)
  said[#said + 1] = "a record asked for whole by GUID comes with its statistics pass"

  -- (w) an officer out of the guild by any road keeps none of its members' Only-you values: kicked while offline (a
  -- login out of any guild, half a minute on), or gone into another guild before half a minute was out (the records
  -- parked for the guild left, those values taken out first). An alt of another guild that was never one of its
  -- officers parks an officer's file whole. A first build took them out only from an officer who stayed online
  -- half a minute after leaving
  do
    local function club8(c)
      local cc = c.env.C_Club
      local gm, gi, gs = cc.GetClubMembers, cc.GetMemberInfo, cc.GetMemberInfoForSelf
      cc.GetGuildClubId = function() return c.inGuild and 8 or nil end
      cc.GetClubMembers = function(id) return gm(id == 8 and 7 or id) end
      cc.GetMemberInfo = function(id, i) return gi(id == 8 and 7 or id, i) end
      cc.GetMemberInfoForSelf = function(id) return gs(id == 8 and 7 or id) end
    end
    for _, how in ipairs({ "offline", "another", "alt" }) do
      isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
        local off, a = char("Coraline", 1), char("Cobb", 3, { money = 777777 })
        local db = {}
        login(off, db); login(a)
        tickAll(60)
        local rec = db.roster[a.sender]
        assert(rec and rec.stats.gold == 777777, "the officer holds the member's gold")
        local roster = db.roster
        if how == "offline" then
          fire(off, "PLAYER_LOGOUT"); leave(off)
          tickAll(10)
          local off2 = char("Coraline", 1, { inGuild = false })
          login(off2, db)
          tickAll(100)
          assert(rec.stats.gold == nil and rec.stats.level ~= nil, "kicked while offline: the gold gone at the guildless login, the rest kept: " .. tostring(rec.stats.gold))
        elseif how == "another" then
          off.inGuild = false
          fire(off, "PLAYER_GUILD_UPDATE", "player")
          tickAll(5)
          club8(off)
          off.inGuild = true
          fire(off, "PLAYER_GUILD_UPDATE", "player")
          tickAll(5)
          assert(db.policies and db.policies["7"] and db.policies["7"].roster == roster, "guild 7's records parked")
          assert(rec.stats.gold == nil and rec.stats.level ~= nil, "gone into another guild within seconds: the gold gone: " .. tostring(rec.stats.gold))
        else
          fire(off, "PLAYER_LOGOUT"); leave(off)
          local alt = char("Cyra", 3)
          club8(alt)
          login(alt, db)
          tickAll(100)
          assert(db.policies and db.policies["7"] and db.policies["7"].roster == roster and rec.stats.gold == 777777, "an alt of guild 8 parks the officer's file whole")
        end
      end)
    end
  end
  said[#said + 1] = "an officer out of the guild by any road keeps no Only-you values; another guild's alt parks them whole"

  -- (x) a client whose list never reads whole (ClubInfo.memberCount is Nilable) still keeps its file bounded: a record
  -- unseen ninety days goes, and past the cap the longest unseen. A first build pruned by age and cap only at a
  -- whole list, and such a file grew for good
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local roster = { ["Gone-Forever"] = { seen = EPOCH + 1000 - 91 * 86400, stats = { level = 20 }, at = {}, ch = true } }
    for i = 1, 1005 do roster["Zz" .. i .. "-Forever"] = { seen = EPOCH + i, stats = { level = 20 }, at = {}, ch = true } end
    local off = char("Coraline", 1)
    off.noMemberCount = true
    login(off, { policyClub = "7", roster = roster })
    tickAll(80)
    assert(not off.C.Roster.listedWhole, "no list reads whole")
    local n = 0
    for _ in pairs(off.env.CuteDB.roster) do n = n + 1 end
    assert(off.env.CuteDB.roster["Gone-Forever"] == nil and n <= 1000 and off.env.CuteDB.roster["Zz1005-Forever"], "unseen ninety days gone, the file within its cap: " .. n)
  end)
  said[#said + 1] = "a list that never reads whole still prunes by age and cap"

  -- (y) one member's records hold one version each: a copy that says 32 made-up versions fills nothing, and a real one
  -- that two members run is still announced. A first build kept 32 versions for the whole guild, and one copy's
  -- 32 silenced every update after them for the session
  isolated({ member("Coraline", 1), member("Cobb", 3) }, function()
    local c = char("Coraline", 1)
    login(c)
    tickAll(20)
    for i = 1, 40 do c.C.SawVersion("9.0." .. i, guidOf("Cobb")) end
    assert(c.C.newer == nil, "one voice announces nothing")
    c.C.SawVersion("0.9.3", guidOf("Cyra"))
    c.C.SawVersion("0.9.3", guidOf("Cato"))
    assert(c.C.newer == "0.9.3", "two members' version announced after a copy's forty: " .. tostring(c.C.newer))
  end)
  said[#said + 1] = "a copy's made-up versions fill nothing, a real update still told"

  -- (z) the officers to whisper to follow who a sender string names: a member online whose name reads in no form (a
  -- Kstring the GUID call does not resolve) may be any one-word sender's namesake, so an officer known by one word is no
  -- target while one is online, and one again once they are gone. A first build cached the list by the records
  -- and the officers alone: a stale officer was whispered, refused and queued again every change, or a resolved one
  -- told nothing
  isolated({ member("Coraline", 1), member("Cobb", 3), { name = "|Kq77|k", guid = guidOf("Kay"), rank = 3, rankName = "Raider", class = "MAGE", level = 30, online = false } }, function()
    local off, a = char("Coraline", 1), char("Cobb", 3, { money = 1000 })
    login(off); login(a)
    tickAll(60)
    assert(off.env.CuteDB.roster[a.sender].stats.gold == 1000 and #a.C.Roster:OfficerTargets() == 1, "Coraline is told Cobb's gold")
    GUILD[3].online = true
    fire(a, "GUILD_ROSTER_UPDATE")
    assert(#a.C.Roster:OfficerTargets() == 0, "an unread name online: a one-word sender names nobody for sure")
    -- (a record changes meanwhile: the list built again while the name is unread)
    a.C.Roster:Identity()
    assert(#a.C.Roster:OfficerTargets() == 0, "built again, still none")
    GUILD[3].online = false
    fire(a, "GUILD_ROSTER_UPDATE")
    assert(#a.C.Roster:OfficerTargets() == 1, "an officer again once it is gone")
    tickAll(20)
    a.o.money = 2000
    fire(a, "PLAYER_MONEY")
    tickAll(20)
    assert(off.env.CuteDB.roster[a.sender].stats.gold == 2000, "told the gold again: " .. tostring(off.env.CuteDB.roster[a.sender].stats.gold))
  end)
  said[#said + 1] = "the officers to whisper to follow an unread name online"

  -- (aa) a file 0.7.0 wrote keeps no statistic it stored as 0 from "--" (never recorded), in the records held and those
  -- parked, even where the first slimming pass ran: a 0.7.1 sender never sends that id again, so the 0 stayed for good
  -- beside the "-" of members heard since
  isolated({ member("Coraline", 1) }, function()
    local db = { slimAt = true, policyClub = "7", roster = { ["Old-Forever"] = { seen = EPOCH + 900, stats = { g3001 = 0, g3002 = 5, level = 20 }, at = {} } },
      policies = { ["8"] = { roster = { ["Far-Forever"] = { seen = EPOCH + 900, stats = { g3001 = 0, level = 20 }, at = {} } } } } }
    local c = char("Coraline", 1)
    login(c, db)
    local old = db.roster["Old-Forever"].stats
    assert(old.g3001 == nil and old.g3002 == 5 and old.level == 20, "a stored 0 statistic gone, the rest kept")
    assert(db.policies["8"].roster["Far-Forever"].stats.g3001 == nil and db.policies["8"].roster["Far-Forever"].stats.level == 20, "and in a parked guild's records")
  end)
  said[#said + 1] = "a file's statistics stored as 0 from never recorded go once at load"

  -- (ab) an ask whole after a since-ask of the same login (/cute resend, the officers' button, many records missing) is
  -- answered, record and pass, though it comes within ASK_AGAIN of the first: the first's answer was a part. A first
  -- build passed it by as an ask made a moment ago (and a file missing many records, which marks each asked,
  -- never had them that session)
  isolated({ member("Coraline", 1), member("Cobb", 3), member("Cyra", 3) }, function()
    local off, a = char("Coraline", 1), char("Cobb", 3, { withStats = true })
    login(off); login(a)
    tickAll(700)
    local fp = a.C.Policy:Fp()
    a.C.Comm:Receive("1R|" .. guidOf("Cyra") .. "|0|0|" .. fp .. string.format("%x", math.floor(a.C.Comm.base + 5)), "GUILD", "Cyra-Forever")
    tickAll(60)
    local s0 = #a.sent
    a.C.Comm:Receive("1R|" .. guidOf("Cyra") .. "|0|0|" .. fp, "GUILD", "Cyra-Forever")
    tickAll(45)
    local whole, pass = false, false
    for i = s0 + 1, #a.sent do if a.sent[i].msg:find("^1F|1|%d+|%d+|guid=") then whole = true end end
    assert(whole, "her ask whole, a minute after her since-ask, answered whole: " .. kinds(a, s0 + 1))
    tickAll(120)
    for i = s0 + 1, #a.sent do if a.sent[i].msg:find("g2001=", 1, true) then pass = true end end
    assert(pass, "and with the pass: " .. kinds(a, s0 + 1))
  end)
  said[#said + 1] = "an ask whole after a since-ask is answered, record and pass"

  print("core: " .. table.concat(said, "; "))
end

-- [stage: merge1] that stage's tests go right below this line
-- (the merge round) the Quests section has the engine's two switches QuestBank's Guide section has: "Say XP after each
-- hand-in" (sayXP, off: the line in chat as a quest is handed in, complete or dropped) and "Hide the game's quest tracker
-- while the step frame shows" (guide.hideTracker, on); each writes the engine's setting, both labels whole at either
-- window size, and the section keeps eight rows at most
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Rone", 1), member("Pim", 3) }, function()
    local c = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    login(c); tickAll(5)
    c.C.Modules.Set("Cute_Quest", true); tick(c, 6)
    local s = c.env.CuteQuestDB.settings
    local SAY, TRACKER = "Say XP after each hand-in", "Hide the game's quest tracker while the step frame shows"
    local function row(label) return checkBox(c, function(cb) return cb.label and cb.label:GetText() == label end) end
    c.C.UI:Open("settings", "quests")
    local say, trk = row(SAY), row(TRACKER)
    assert(say and not say:GetChecked() and s.sayXP ~= true, "the Say XP row, off by default:\n" .. texts(c))
    assert(trk and trk:GetChecked() and s.guide.hideTracker == true, "the tracker's row, on:\n" .. texts(c))
    -- off: a hand-in says nothing; ticked: the engine's sayXP on, and the hand-in's line said
    local n0 = #c.chat
    fire(c, "QUEST_TURNED_IN", next(c.o.log), 450); tick(c, 1)
    assert(#c.chat == n0, "off: a hand-in says nothing: " .. tostring(c.chat[#c.chat]))
    click(say)
    assert(s.sayXP == true, "ticked: the engine's sayXP on")
    fire(c, "QUEST_TURNED_IN", next(c.o.log), 450); tick(c, 1)
    assert(#c.chat > n0 and c.chat[#c.chat]:find("450 XP", 1, true), "on: the hand-in's line: " .. tostring(c.chat[#c.chat]))
    click(row(SAY))
    assert(s.sayXP == false, "unticked: off again")
    click(row(TRACKER))
    assert(s.guide.hideTracker == false, "the tracker's row unticked: the engine's setting off")
    click(row(TRACKER))
    assert(s.guide.hideTracker == true, "and on again")
    -- eight rows at most (a Check, a Choice, a Step or an Edit is a row)
    local n = 0
    local col = setmetatable({}, { __index = function(_, k) return function() if k == "Check" or k == "Choice" or k == "Step" or k == "Edit" then n = n + 1 end end end })
    c.C.Modules.byId.quests.settings(c.C.Modules.byId.quests, col)
    assert(n <= 8, "the Quests section keeps eight rows at most: " .. n)
    -- both labels whole at either size (Cute's FitText would cut a label too long with "...")
    for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
      c.C.UI.frame:SetSize(size[1], size[2])
      c.C.UI:Open("settings", "quests")
      assert(row(SAY) and row(TRACKER), "both labels whole at " .. size[1] .. " x " .. size[2] .. ":\n" .. texts(c))
    end
    assert(#(c.env.CuteQuestDB.errors or {}) == 0, "no engine error recorded")
    leave(c)
    print(string.format("merge1: the Quests section: Say XP after each hand-in (off; ticked, the hand-in's line) and the tracker's row (on), labels whole at both sizes, %d rows", n))
  end)
end

-- this pass's problems and layouts join the run's; the last pass prints them all
for _, p in ipairs(problems) do table.insert(CUTE_RESULTS.problems, (SEEDED and "[seed] " or "[no seed] ") .. p) end
for _, l in ipairs(layouts) do l.label = (SEEDED and "seed: " or "no seed: ") .. l.label; table.insert(CUTE_RESULTS.layouts, l) end
if CUTE_LAST then
  local seen, unique = {}, {}
  for _, p in ipairs(CUTE_RESULTS.problems) do if not seen[p] then seen[p] = true; unique[#unique + 1] = p end end
  print("layout problems:", #unique)
  for i = 1, math.min(80, #unique) do print("  " .. unique[i]) end
  if LAYOUT_OUT then
    local f = assert(io.open(LAYOUT_OUT, "w"))
    f:write(json(CUTE_RESULTS.layouts))
    f:close()
    print("layout written to " .. LAYOUT_OUT)
  end
  print(#unique == 0 and "OK" or "OK, with layout problems above")
end
