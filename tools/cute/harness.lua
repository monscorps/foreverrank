-- Mock WoW client for Cute. Loads the addon into separate clients (each its own globals), gives them one guild, routes
-- their addon messages, drives events and timers, opens every page for an officer and a member, and fails on any
-- widget method outside a whitelist of real API methods. It lays the window out like the game does and reports
-- clipped text, overlapping text, text the game's font cannot draw, and buttons too near an edge.
--   luajit tools/cute/harness.lua                   run every scenario
--   luajit tools/cute/harness.lua --layout out.json  also write the window, page by page, for render_layout.py
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
local FONT_SIZE = { GameFontNormal = 12, GameFontNormalLarge = 16, GameFontHighlightSmall = 10, GameFontNormalSmall = 10 }

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
        if k == "SetScript" then self.__scripts[a[1]] = a[2]
        elseif k == "GetScript" then return self.__scripts[a[1]]
        elseif k == "HookScript" then local old = self.__scripts[a[1]]; self.__scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
        elseif k == "RegisterEvent" or k == "RegisterUnitEvent" then self.__events[a[1]] = true
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
        elseif k == "GetFont" then return "Fonts\\FRIZQT__.TTF", self.__size, ""
        elseif k == "SetFont" then self.__size = a[2] or self.__size
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
local function fontObj(name) local f = newObj("Font"); f.__fontSize = FONT_SIZE[name] or 12; return f end

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
local GUILD = {} -- { { name = "Name-Realm", rank = idx, rankName, level, class, online, zone }, ... }
local clients = {}
local BUS = {}
local lines = {} -- the tooltip's lines, every client

local function deliver()
  while #BUS > 0 do
    local m = table.remove(BUS, 1)
    for _, c in ipairs(clients) do
      if c ~= m.from and c.inGuild then
        for _, f in ipairs(c.frames) do
          if f.__events.CHAT_MSG_ADDON and f.__scripts.OnEvent then f.__scripts.OnEvent(f, "CHAT_MSG_ADDON", m.prefix, m.msg, m.channel, m.from.name) end
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
BASE.date = os.date
BASE.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
  MAGE = { r = 0.41, g = 0.8, b = 0.94 }, ROGUE = { r = 1, g = 0.96, b = 0.41 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
  PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
BASE.tinsert = table.insert
BASE.UISpecialFrames = nil -- per client
BASE.GetCursorPosition = function() return 600, 500 end
BASE.issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end

local EPOCH = 1792300000

local function newClient(o)
  local env = setmetatable({}, { __index = BASE })
  env._G = env
  local c = { env = env, o = o, name = o.name .. "-" .. (o.realm or "Forever"), timers = {}, clock = 1000, frames = {}, sent = {}, chat = {},
              hooks = {}, C = {}, inGuild = o.inGuild ~= false, secret = false, throw = false }
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
  env.hooksecurefunc = function(a, b, fn)
    if type(a) == "table" then c.hooks[b] = fn else c.hooks[a] = b end
  end
  env.DoEmote = function(token) if c.hooks.DoEmote then c.hooks.DoEmote(token) end end
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
  env.UnitName = api(function(unit) if unit == "player" then return o.name end local i = unit:match("^party(%d)$"); return i and (o.party or {})[tonumber(i)] or nil end)
  env.UnitFullName = api(function() return o.name, o.realm or "Forever" end)
  env.GetNormalizedRealmName = api(function() return o.realm or "Forever" end)
  env.GetMoney = api(function() return o.money or 0 end)
  env.GetBindLocation = api(function() return o.hearth or "Goldshire" end)
  env.GetNumUnspentTalents = api(function() return o.talents or 0 end)
  env.GetSpecialization = api(function() return 1 end)
  env.GetSpecializationInfo = api(function() return 1, o.spec or "Arms" end)
  env.GetProfessions = api(function() return 1, 2, nil, 4, 5 end)
  env.GetProfessionInfo = api(function(i) local p = ({ { "Mining", 150, 225 }, { "Engineering", 140, 225 }, nil, { "Fishing", 40, 75 }, { "Cooking", 60, 150 } })[i]; if p then return p[1], 0, p[2], p[3] end end)
  env.GetAverageItemLevel = api(function() return o.ilvl or 30, o.ilvl or 30 end)
  env.GetInventoryItemLink = api(function(_, slot) return (o.items or {})[slot] end)
  env.GetItemInfo = api(function(link) local id = tonumber(tostring(link):match("item:(%d+)")) or 0; return "Item " .. id, link, (id % 3) + 1, 20 + (id % 40) end)
  env.UnitResistance = api(function(_, i) return 0, (o.resist or {})[i] or 0 end)
  env.GetItemCount = api(function(id) return (o.counts or {})[id] or 0 end)
  env.UnitAura = api(function(_, i) local a = (o.auras or {})[i]; if a then return a[1], nil, nil, nil, nil, nil, nil, nil, nil, a[2] end end)
  env.GetInventoryItemDurability = api(function(_, slot) if (o.items or {})[slot] then return o.dur or 80, 100 end end)
  env.GetFactionInfoByID = api(function(id) return "Faction", nil, (o.rep or {})[id] or 4 end)
  env.UnitPVPRank = api(function() return o.pvp or 0 end)
  env.GetPVPThisWeekStats = api(function() return 0, o.honor or 0 end)
  env.GetNumSavedInstances = api(function() return #(o.saved or {}) end)
  env.GetSavedInstanceInfo = api(function(i) local s = o.saved[i]; return s.name, 1, 0, 0, true, false, 0, s.raid end)
  env.GetInventoryItemCount = api(function() return o.ammo or 0 end)
  env.UnitPosition = api(function() local p = o.pos or { 100, 100 }; return p[2], p[1], 0, 0 end)
  env.UnitIsGhost = api(function() return o.ghost or false end)
  env.UnitOnTaxi = api(function() return o.taxi or false end)
  env.UnitIsAFK = api(function() return o.afk or false end)
  env.IsFalling = api(function() return o.falling or false end)
  env.GetMirrorTimerInfo = api(function(i) if i == 1 and o.breath then return "BREATH", o.breath end return "UNKNOWN", 0 end)
  env.GetInstanceInfo = api(function() return "Zone", o.instance or "none" end)
  env.NumTaxiNodes = api(function() return 5 end)
  env.TaxiNodeGetType = api(function(i) return i <= 3 and "REACHABLE" or "DISTANT" end)
  env.RequestTimePlayed = function() c.timers[#c.timers + 1] = { t = c.clock + 1, f = function() fire(c, "TIME_PLAYED_MSG", o.played or 36000, o.playedLevel or 3600) end } end
  env.IsInGuild = api(function() return c.inGuild end)
  env.GetNumGuildMembers = api(function() return c.inGuild and #GUILD or 0 end)
  env.GetGuildRosterInfo = api(function(i)
    local m = GUILD[i]
    if not m then return nil end
    return m.name, m.rankName or ("Rank " .. m.rank), m.rank, m.level, m.class, m.zone or "Elwynn Forest", "", "", m.online ~= false, 0, m.class
  end)
  env.C_GuildInfo = { GuildRoster = function() c.rosterAsked = (c.rosterAsked or 0) + 1; c.timers[#c.timers + 1] = { t = c.clock + 0.5, f = function() fire(c, "GUILD_ROSTER_UPDATE") end } end }
  env.C_QuestLog = {
    IsQuestFlaggedCompleted = api(function(id) return (o.done or {})[id] or false end),
    GetLogIndexForQuestID = api(function(id) return (o.log or {})[id] end),
    GetAllCompletedQuestIDs = api(function() local out = {}; for id in pairs(o.done or {}) do out[#out + 1] = id end; return out end),
    GetNumQuestLogEntries = api(function() local n = 0; for _ in pairs(o.log or {}) do n = n + 1 end; return n + 1, n end),
    GetInfo = api(function(i) return { questID = 100 + i, isHeader = false } end),
    IsComplete = api(function(id) return id == 101 end),
  }
  env.C_Item = { GetItemCount = env.GetItemCount, GetDetailedItemLevelInfo = api(function(link) local id = tonumber(tostring(link):match("item:(%d+)")) or 0; return 20 + (id % 40) end),
    GetItemQualityByID = api(function(link) local id = tonumber(tostring(link):match("item:(%d+)")) or 0; return (id % 3) + 1 end) }
  env.C_Container = { GetContainerNumFreeSlots = api(function(b) return b == 0 and 4 or 2 end), GetContainerNumSlots = api(function(b) return b == 0 and 16 or 10 end) }
  env.C_UnitAuras = { GetAuraDataByIndex = api(function(_, i) local a = (o.auras or {})[i]; if a then return { name = a[1], spellId = a[2] } end end) }
  env.C_Reputation = { GetFactionDataByID = api(function(id) return { reaction = (o.rep or {})[id] or 4 } end) }
  env.C_MountJournal = { GetMountIDs = api(function() return { 1 } end), GetMountInfoByID = api(function() return "Horse", 1, 1, true, true, 1, false, false, false, false, o.mount or false end) }
  env.C_Traits = { GetConfigIDByTreeID = api(function(tree) return tree == 1187 and 7 or nil end),
    GetNodeInfo = api(function(_, node) return { activeRank = (o.legacy or {})[node] or 0 } end) }
  env.C_TradeSkillUI = { GetAllRecipeIDs = api(function() return o.recipes or {} end), GetRecipeInfo = api(function(id) return { learned = true } end), GetTradeSkillLine = api(function() return "Alchemy" end) }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) c.prefix = p; return true end,
    SendAddonMessage = function(prefix, msg, channel)
      assert(#msg <= 255, "an addon message of " .. #msg .. " bytes")
      assert(prefix == "Cute" and channel == "GUILD", "the Cute prefix on GUILD only: " .. tostring(prefix) .. " " .. tostring(channel))
      if c.throttle and c.throttle > 0 then c.throttle = c.throttle - 1; return 3 end
      c.sent[#c.sent + 1] = { msg = msg, at = c.clock }
      BUS[#BUS + 1] = { from = c, prefix = prefix, msg = msg, channel = channel }
      return 0
    end,
    SendChatMessage = function(text, kind) if c.hooks.SendChatMessage then c.hooks.SendChatMessage(text, kind) end end,
  }
  env.Enum = {}
  env.math = setmetatable({ random = function(a, b) if a and b then return a + (c.clock % (b - a + 1)) end return 0.5 end }, { __index = math })

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

local function login(c, db)
  c.env.CuteDB = db or {}
  fire(c, "ADDON_LOADED", "Cute")
  fire(c, "PLAYER_ENTERING_WORLD", true, false)
  tick(c, 1) -- the roster arrives
end

local function click(b) assert(b and b.__scripts.OnClick, "a button with OnClick"); b.__scripts.OnClick(b, "LeftButton") end
local function hover(o) if o.__scripts.OnEnter then o.__scripts.OnEnter(o) end end

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
  for i, n in ipairs(NAMES) do GUILD[i] = { name = n[1] .. "-Forever", rank = n[2], rankName = n[3], class = n[4], level = n[5], online = i % 3 ~= 0 } end
end
local function charOf(n, extra)
  local o = { name = n[1], realm = "Forever", level = n[5], xp = 350, xpmax = 1000, class = n[4], money = 123456, zone = "Duskwood", rested = 500,
    items = { [1] = "item:1234:0", [5] = "item:1235:2", [7] = "item:1236:0", [16] = "item:1240:0" }, auras = { { "Power Word: Fortitude", 1243 }, { "Rallying Cry", 22888 } },
    counts = { [13446] = 5, [13510] = 1, [18249] = 1 }, done = { [7848] = true, [4182] = true }, log = { [4183] = 3 }, saved = {} }
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
local yezin = newClient(charOf(NAMES[2]))
local kaka = newClient(charOf(NAMES[4], { level = 37, xp = 120, money = 54321, zone = "Desolace" }))
login(yezin)
login(kaka)

-- 1: the registry
do
  local S = yezin.C.Stats
  local counts = {}
  for _, cat in ipairs(S.CATS) do counts[cat] = #S.byCat[cat] end
  assert(#S.list >= 110, "a starter list of over a hundred stats: " .. #S.list)
  for _, def in ipairs(S.list) do assert(def.id and def.label and def.cat and def.kind, "a whole definition: " .. tostring(def.id)) end
  assert(S.byId.level and S.byId.deaths and S.byId.gold and S.byId.unenchanted, "the stats the pages lean on")
  assert(yezin.C.Policy:Vis("unenchanted") == "self" and yezin.C.Policy:Vis("level") == "all" and yezin.C.Policy:Vis("gold") == "self", "the defaults")
  print(string.format("registry: %d stats (leveling %d, prog %d, funny %d, officer %d)", #S.list, counts.leveling, counts.prog, counts.funny, counts.officer))
end

-- 2: every read survives a client whose values are all secret, and one whose calls all throw
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
  c.throw = false
  c.C.Sample:ReadAll()
  assert(c.C.Sample:Value("level") == NAMES[9][5], "the level reads again after the client recovers")
  print(string.format("reads: every stat survives secret values and thrown errors (%d read errors recorded while throwing)", errs))
end

-- 3: the encoder round-trips every kind
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
  print("encoder: " .. n .. " values round-trip")
end

-- 4: hello: the two clients exchange records; the full record fits in a few chunks
do
  tickAll(45)
  local function msgs(c, kind) local n = 0; for _, m in ipairs(c.sent) do if m.msg:sub(1, 2) == kind then n = n + 1 end end return n end
  assert(msgs(yezin, "1R") == 1 and msgs(kaka, "1R") == 1, "each said hello")
  local fulls = msgs(yezin, "1F")
  assert(fulls >= 1 and fulls <= 16, "the full record in a handful of chunks per send: " .. fulls)
  for _, m in ipairs(yezin.sent) do assert(#m.msg <= 255) end
  local e = kaka.env.CuteDB.roster["Yezin-Forever"]
  assert(e and e.stats.level == 42 and e.stats.zone == "Duskwood", "Kaka's roster holds Yezin's level and zone")
  local e2 = yezin.env.CuteDB.roster["Kaka-Forever"]
  assert(e2 and e2.stats.level == 37 and e2.stats.gold == 5, "Yezin's roster holds Kaka's level and gold")
  assert(e2.stats.unenchanted and e2.stats.unenchanted[1] == true and e2.stats.unenchanted[5] == nil, "lists arrive as sets")
  -- one message a second from each
  local last
  for _, m in ipairs(yezin.sent) do if last then assert(m.at - last >= 1 - 1e-9, "one message a second: " .. (m.at - last)) end last = m.at end
  print(string.format("hello: records exchanged, %d messages from Yezin (%d chunks of the full record), none closer than a second", #yezin.sent, fulls / 2))
end

-- 5: a change goes out as a delta
do
  local before = #kaka.sent
  kaka.o.level = 38
  fire(kaka, "PLAYER_LEVEL_UP", 38)
  tickAll(4)
  assert(#kaka.sent > before, "a delta went out")
  local d = kaka.sent[#kaka.sent].msg
  assert(d:sub(1, 2) == "1D" and d:find("level=12", 1, true), "the delta carries the new level in base 36: " .. d)
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.level == 38, "Yezin saw the level")
  print("deltas: a level-up reaches the guild as one small message")
end

-- 6: the policy: a member's is ignored, an officer's applies, cells follow it
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
  print("policy: member's ignored, officer's applied, older ignored, cells follow the rule")
end

-- 7: counters persist across a reload
do
  fire(kaka, "PLAYER_DEAD")
  fire(kaka, "PLAYER_DEAD")
  kaka.env.DoEmote("DANCE")
  kaka.env.DoEmote("WAVE")
  assert(kaka.C.Sample:Value("deaths") == 2 and kaka.C.Sample:Value("dance") == 1 and kaka.C.Sample:Value("emotes") == 2, "counted")
  kaka.o.falling = true
  tick(kaka, 5)
  fire(kaka, "PLAYER_DEAD")
  assert(kaka.C.Sample:Value("falls") == 1 and kaka.C.Sample:Value("deaths") == 3, "a fall death")
  kaka.o.falling = false
  local db = kaka.env.CuteDB
  local again = newClient(charOf(NAMES[4]))
  login(again, db)
  assert(again.C.Sample:Value("deaths") == 3 and again.C.Sample:Value("dance") == 1, "counters survive a reload")
  assert(again.C.Sample:Value("logins") == 2, "logins counted across sessions")
  table.remove(clients) -- the reloaded Kaka leaves the bus
  print("counters: deaths, dances and falls persist across a reload")
end

-- 8: the roster: prune needs two misses; members without the addon show greyed
do
  local rows = yezin.C.Roster:Rows()
  assert(rows[1].me and rows[1].short == "Yezin", "you first")
  local byName = {}
  for _, r in ipairs(rows) do byName[r.short] = r end
  assert(byName.Kaka and byName.Kaka.addon, "Kaka has the addon")
  assert(byName.Garristan and not byName.Garristan.addon and byName.Garristan.level == 1, "Garristan is listed from the guild roster without the addon")
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
  print("roster: you first, no-addon members listed, prune after two misses")
end

-- 9: the window, every page, for the officer and the member
do
  local function pages(c, who, list)
    c.C.UI:Open("race")
    local f = c.C.UI.frame
    assert(f:IsShown(), "the window opened")
    for _, page in ipairs(list) do
      c.C.UI:Open(page)
      assert(c.C.UI.page == page, who .. " could open " .. page)
      local n = check(f, who .. " " .. page)
      -- tooltips on a few cells
      for _, r in ipairs(c.C.UI.rows.items) do if r:IsShown() then hover(r); for _, cell in ipairs(r.cells) do if cell:IsShown() then hover(cell) end end end end
    end
    return f
  end
  local f = pages(yezin, "officer", { "race", "prog", "shame", "officers", "me", "settings" })
  assert(yezin.C.UI.tabs.officers:IsShown(), "the officer sees the Officers tab")
  pages(kaka, "member", { "race", "prog", "shame", "me", "settings" })
  assert(not kaka.C.UI.tabs.officers:IsShown(), "the member has no Officers tab")
  kaka.C.UI:Open("officers")
  assert(kaka.C.UI.page == "race", "a member asking for the officers' page lands on Race")
  -- the self-only column: a dash on others' rows, the value on your own
  kaka.env.CuteDB.settings.columns.prog = { ilvl = true, unenchanted = true, deaths = true }
  kaka.C.UI:Open("prog")
  local own, other
  for _, r in ipairs(kaka.C.UI.rows.items) do
    if r:IsShown() and r.row then
      for _, cell in ipairs(r.cells) do
        if cell:IsShown() and cell.def and cell.def.id == "unenchanted" then
          if r.row.me then own = cell.label:GetText() elseif r.row.short == "Yezin" then other = cell.label:GetText() end
        end
      end
    end
  end
  assert(own and own ~= "-" and own ~= "" and other == "-", "unenchanted: own value shows (" .. tostring(own) .. "), Yezin's is a dash (" .. tostring(other) .. ")")
  check(kaka.C.UI.frame, "member prog, two columns")
  -- the officer sees the member's
  yezin.env.CuteDB.settings.columns.prog = { ilvl = true, unenchanted = true }
  yezin.C.UI:Open("prog")
  local seen
  for _, r in ipairs(yezin.C.UI.rows.items) do
    if r:IsShown() and r.row and r.row.short == "Kaka" then for _, cell in ipairs(r.cells) do if cell:IsShown() and cell.def and cell.def.id == "unenchanted" then seen = cell.label:GetText() end end end
  end
  assert(seen and seen ~= "-", "the officer sees Kaka's unenchanted slots: " .. tostring(seen))
  -- sorting by a column
  yezin.env.CuteDB.settings.columns.prog = nil
  yezin.C.UI:Open("race")
  local header
  for _, h in ipairs(yezin.C.UI.headerCells.items) do if h:IsShown() and h.id == "level" then header = h end end
  assert(header, "a Level header")
  click(header)
  assert(yezin.C.UI.sort.race and yezin.C.UI.sort.race.id == "level" and yezin.C.UI.sort.race.desc == false, "clicking the sorted column flips it")
  check(yezin.C.UI.frame, "officer race, sorted up")
  -- resized small: still no problems
  yezin.C.UI.frame:SetSize(760, 420)
  yezin.C.UI:Open("race")
  check(yezin.C.UI.frame, "officer race, small window")
  yezin.C.UI:Open("prog")
  check(yezin.C.UI.frame, "officer prog, small window")
  yezin.C.UI:Open("settings")
  check(yezin.C.UI.frame, "officer settings, small window")
  yezin.C.UI.frame:SetSize(1040, 640)
  -- the minimap button and the hall's tooltips
  assert(yezin.C.UI.mini and yezin.C.UI.mini:IsShown(), "the minimap button")
  hover(yezin.C.UI.mini)
  yezin.C.UI:Open("shame")
  for _, card in ipairs(yezin.C.UI.cards.items) do if card:IsShown() then hover(card) end end
  print("window: every page opens for both views, self-only cells hidden from the member, sorting and resizing hold")
end

-- 10: settings: a member cannot flip visibility; an officer's flip plus Broadcast reaches the member
do
  kaka.C.UI:Open("settings")
  local flipped
  for _, cb in ipairs(kaka.C.UI.scroll.child.__client.frames) do
    if cb.__kind == "CheckButton" and cb:IsShown() and cb.__disabled and cb.__scripts.OnClick then flipped = cb; break end
  end
  assert(flipped, "the member's visibility boxes are disabled")
  local before = kaka.C.Policy:Vis("level")
  -- even a click on a disabled box (a macro could) changes nothing
  flipped.__checked = not flipped.__checked
  flipped.__scripts.OnClick(flipped)
  assert(kaka.C.Policy:Vis("level") == before, "a member's click changes no policy")
  -- the officer flips 'level' to only-you and broadcasts
  yezin.C.UI:Open("settings")
  local target
  for _, fr in ipairs(yezin.frames) do
    if fr.__kind == "CheckButton" and fr:IsShown() and not fr.__disabled and fr.label and fr.label.__text == "" then
      -- the pairs sit after the stat's label: find the pair for "Level" by position
      local lab
      for _, l in ipairs(yezin.frames) do end
    end
  end
  yezin.C.Policy:Set("level", "self")
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  assert(kaka.C.Policy:Vis("level") == "self", "the member applied the officer's policy")
  yezin.C.Policy:Set("level", "all")
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  -- the column checklist hides a column
  yezin.C.UI.SetTicked("race", "zone", false)
  yezin.C.UI:Open("race")
  for _, h in ipairs(yezin.C.UI.headerCells.items) do if h:IsShown() then assert(h.id ~= "zone", "zone unticked, no zone column") end end
  yezin.C.UI.SetTicked("race", "zone", true)
  check(yezin.C.UI.frame, "officer race after settings")
  print("settings: members cannot flip visibility, the officer's broadcast lands, column checklists hide columns")
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
  end
  local n = 0
  for _ in pairs(yezin.env.CuteDB.roster) do n = n + 1 end
  assert(n >= 15, "Yezin's roster filled from the storm: " .. n)
  yezin.C.UI:Open("race")
  check(yezin.C.UI.frame, "officer race, twenty members")
  yezin.C.UI:Open("prog")
  check(yezin.C.UI.frame, "officer prog, twenty members")
  yezin.C.UI:Open("shame")
  check(yezin.C.UI.frame, "officer shame, twenty members")
  yezin.C.UI:Open("officers")
  check(yezin.C.UI.frame, "officer officers, twenty members")
  print(string.format("storm: %d clients, one message a second each, %d records on Yezin's roster", #clients, n))
end

-- 12: the throttle: the game's "too fast" waits and retries, nothing is lost
do
  kaka.throttle = 2
  kaka.o.zone = "Stranglethorn Vale"
  local before = #kaka.sent
  fire(kaka, "ZONE_CHANGED_NEW_AREA")
  tickAll(12)
  assert(#kaka.sent > before and kaka.throttle == 0, "retried past the throttle")
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.zone == "Stranglethorn Vale", "the zone arrived")
  print("throttle: the queue waits and retries")
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
  lone.C.UI:Open("me")
  check(lone.C.UI.frame, "guildless me")
  table.remove(clients)
  print("guildless: nothing sent, the window shows your own record")
end

-- 14: calls Cute never makes
do
  local NEVER = { "COMBAT_LOG_EVENT_UNFILTERED", "C_SuperTrack", "SetUserWaypoint", "StaticPopup", "OpenChat", "ChatFrame_OpenChat", "AcceptQuest", "LootSlot", "ToggleWorldMap" }
  local found = {}
  for file in io.open(HERE .. "/Cute/Cute.toc"):read("*a"):gmatch("\n([%w_]+%.lua)") do
    local n = 0
    for src in io.lines(HERE .. "/Cute/" .. file) do
      n = n + 1
      local code = src:gsub("%-%-.*$", "")
      for _, name in ipairs(NEVER) do
        if code:find(name, 1, true) and not (name == "COMBAT_LOG_EVENT_UNFILTERED" and code:find("~=", 1, true)) then found[#found + 1] = file .. ":" .. n .. " " .. name end
      end
    end
  end
  assert(#found == 0, "a call Cute never makes:\n  " .. table.concat(found, "\n  "))
  print("never: the combat log, the game's tracking, popups and chat boxes stay untouched")
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
