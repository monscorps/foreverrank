-- Mock WoW Forever client for ForeverProbe (addon/ForeverProbe), modelled on tools/questbank/harness.lua.
--
-- The client modelled: Classic content on the modern (Mainline) UI with the 12.x addon API and Midnight's
-- addon restrictions. So: C_SpellBook / C_Container / C_Timer / BackdropTemplate exist, the Classic-only
-- globals (GetSpellTabInfo, GetNumSkillLines, GetSkillLineInfo, UnitAura, GetContainerNumSlots...) do not,
-- RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") raises "Attempt to register for restricted event", and one
-- scenario hands the chat XP payload over as a secret value (issecretvalue(x) is true; string functions,
-- indexing, comparisons and arithmetic on it raise errors).
--
-- Widgets answer only to a whitelist of real methods and error on anything else; SetScript checks the
-- widget has that script; each client gets its own globals (setfenv) so SavedVariables and slash commands
-- don't leak between scenarios; events reach only frames that registered them; C_Timer runs on a fake clock.
-- Every step runs protected, and every event handler and timer callback runs protected like the client
-- does, so one error never hides the next. The report lists each error with its file:line.
--
--   cd /Users/mikalbot/foreverrank && luajit tools/foreverprobe/harness.lua
--   luajit tools/foreverprobe/harness.lua --verbose     also prints the addon's chat output, error stacks, the export
-- Two unverified client behaviours can be switched on, each adding a scenario (not run by default):
--   --strict-setfont   FontInstance:SetFont(file, height) without the flags argument errors
--   --quest-xp-chat    a quest hand-in also prints "You gain N experience." on CHAT_MSG_COMBAT_XP_GAIN
--
-- Exit status: 0 when no step errored, 1 otherwise. The addon's files are read, never written.
math.randomseed = nil -- the client has none

local HERE = (arg and arg[0] and arg[0]:match("^(.*)/")) or "."
local ROOT = HERE .. "/../.."
local ADDON = "ForeverProbe"
local ADDON_DIR = ROOT .. "/addon/ForeverProbe/"
local OLD_PROBE_DIR = ROOT .. "/probe/ForeverProbe/"
local VERBOSE, STRICT_SETFONT, QUEST_CHAT = false, false, false
for i = 1, #arg do
  if arg[i] == "--verbose" then VERBOSE = true end
  if arg[i] == "--strict-setfont" then STRICT_SETFONT = true end
  if arg[i] == "--quest-xp-chat" then QUEST_CHAT = true end
end

local CLIENT = { version = "1.60.1", build = "70058", date = "Sep 29 2026", interface = 16001 }

local function readFile(p)
  local f = assert(io.open(p, "rb"), "can't read " .. p)
  local s = f:read("*a")
  f:close()
  return s
end

local function readToc(path)
  local toc = { files = {}, meta = {} }
  for line in readFile(path):gmatch("[^\r\n]+") do
    local k, v = line:match("^##%s*([%w%-_]+)%s*:%s*(.-)%s*$")
    if k then toc.meta[k] = v
    elseif not line:match("^%s*#") and line:match("%S") then toc.files[#toc.files + 1] = line:match("^%s*(.-)%s*$") end
  end
  return toc
end
local TOC = readToc(ADDON_DIR .. "ForeverProbe.toc")

----------------------------------------------------------------------------
-- secret values (Midnight): a sentinel the addon can hold and pass on, but not read
----------------------------------------------------------------------------
local SECRETS = setmetatable({}, { __mode = "k" })
local function isSecret(x) return type(x) == "table" and SECRETS[x] ~= nil end
local secretMT = {}
local function secret(v)
  local s = setmetatable({}, secretMT)
  SECRETS[s] = { v = v }
  return s
end
local function refuse(what) return function() error("attempt to " .. what .. " a secret value", 2) end end
secretMT.__index = function(_, k) error(("attempt to index a secret value (field '%s')"):format(tostring(k)), 2) end
secretMT.__newindex = refuse("index")
secretMT.__len = refuse("get length of")
secretMT.__lt = refuse("compare")
secretMT.__le = refuse("compare")
secretMT.__call = refuse("call")
for _, m in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do secretMT[m] = refuse("perform arithmetic on") end
secretMT.__concat = function(a, b) -- concatenation is allowed and stays secret
  local function raw(x) if isSecret(x) then return SECRETS[x].v end return x end
  return secret(raw(a) .. raw(b))
end
secretMT.__tostring = function() return "<secret>" end -- harness printing only

-- the client's string library refuses secrets in any argument
local function guardedString()
  local s = {}
  for k, fn in pairs(string) do
    s[k] = function(...)
      for i = 1, select("#", ...) do
        if isSecret((select(i, ...))) then
          error(("bad argument #%d to '%s' (string functions can't read a secret value)"):format(i, k), 2)
        end
      end
      return fn(...)
    end
  end
  return s
end

----------------------------------------------------------------------------
-- widgets
----------------------------------------------------------------------------
local METHODS = {}
local function allow(t, list) for m in list:gmatch("%S+") do t[m] = true end end
-- the QuestBank harness whitelist, plus the event and tooltip methods ForeverProbe (and the 0.1.0 probe) touch
allow(METHODS, [[SetPoint ClearAllPoints SetAllPoints SetSize SetWidth SetHeight GetWidth GetHeight Show Hide SetShown IsShown
IsVisible SetAlpha GetAlpha GetParent GetPoint GetCenter GetEffectiveScale SetParent CreateTexture CreateFontString
SetScript GetScript HookScript RegisterEvent UnregisterEvent UnregisterAllEvents IsEventRegistered SetFrameStrata SetFrameLevel
SetToplevel EnableMouse EnableMouseWheel SetMovable SetClampedToScreen RegisterForDrag StartMoving StopMovingOrSizing GetName
IsMouseOver SetScrollChild SetVerticalScroll GetVerticalScroll SetText GetText SetNormalTexture SetHighlightTexture
SetPushedTexture RegisterForClicks SetEnabled Enable Disable GetFontString SetOrientation SetThumbTexture SetMinMaxValues
GetMinMaxValues SetValueStep SetValue GetValue SetTexture SetColorTexture SetTexCoord SetVertexColor SetDesaturated
SetBlendMode SetFontObject SetFont GetFont SetTextColor SetJustifyH SetJustifyV SetWordWrap GetStringWidth GetStringHeight
SetAutoFocus HighlightText SetFocus ClearFocus SetMultiLine SetChecked GetChecked SetMaxLetters HasFocus IsEnabled SetRotation
RegisterUnitEvent]])
local TOOLTIP = {}
allow(TOOLTIP, "SetOwner AddLine AddDoubleLine ClearLines NumLines SetInventoryItem SetSpellBookItem SetTalent SetHyperlink SetSpellByID")
local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }

-- which scripts each widget type has (Frame:SetScript on a missing one errors in the client)
local SCRIPTS = {}
allow(SCRIPTS, "OnEvent OnUpdate OnShow OnHide OnEnter OnLeave OnMouseDown OnMouseUp OnMouseWheel OnDragStart OnDragStop OnSizeChanged OnLoad OnReceiveDrag OnAttributeChanged")
local SCRIPTS_BY = {
  Frame = SCRIPTS,
  Button = setmetatable({}, { __index = SCRIPTS }),
  EditBox = setmetatable({}, { __index = SCRIPTS }),
  ScrollFrame = setmetatable({}, { __index = SCRIPTS }),
  Slider = setmetatable({}, { __index = SCRIPTS }),
  GameTooltip = setmetatable({}, { __index = SCRIPTS }),
}
allow(SCRIPTS_BY.Button, "OnClick OnDoubleClick PreClick PostClick")
SCRIPTS_BY.CheckButton = SCRIPTS_BY.Button
allow(SCRIPTS_BY.EditBox, "OnEscapePressed OnEnterPressed OnTextChanged OnEditFocusGained OnEditFocusLost OnChar OnTabPressed OnCursorChanged OnSpacePressed")
allow(SCRIPTS_BY.ScrollFrame, "OnScrollRangeChanged OnVerticalScroll OnHorizontalScroll")
allow(SCRIPTS_BY.Slider, "OnValueChanged OnMinMaxChanged")
allow(SCRIPTS_BY.GameTooltip, "OnTooltipCleared OnTooltipSetDefaultAnchor")

local KINDS = { Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, Slider = true,
  StatusBar = true, GameTooltip = true }
local TEMPLATES = { BackdropTemplate = true, UIPanelButtonTemplate = true, UIPanelCloseButton = true,
  UIPanelScrollFrameTemplate = true, GameTooltipTemplate = true, InputBoxTemplate = true, UICheckButtonTemplate = true }

-- events this client knows; registering anything else errors ("Attempt to register unknown event")
local KNOWN_EVENTS = {}
allow(KNOWN_EVENTS, [[ADDON_LOADED PLAYER_LOGIN PLAYER_LOGOUT PLAYER_ENTERING_WORLD PLAYER_LEVEL_UP PLAYER_XP_UPDATE
CHAT_MSG_COMBAT_XP_GAIN CHAT_MSG_SYSTEM QUEST_TURNED_IN QUEST_LOG_UPDATE PLAYER_DEAD TRAINER_SHOW TRAINER_CLOSED
GUILD_ROSTER_UPDATE UNIT_AURA COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT PLAYER_MONEY SKILL_LINES_CHANGED UPDATE_EXHAUSTION
LOOT_READY QUEST_DETAIL QUEST_COMPLETE MERCHANT_SHOW ITEM_DATA_LOAD_RESULT]])
local RESTRICTED_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true }

local NOOP = function() end
local H = {} -- method implementations; anything whitelisted but not here is a no-op

function H.SetScript(self, name, fn)
  local ok = SCRIPTS_BY[self.__kind]
  if ok and not ok[name] then
    error(("%s:SetScript(): %s doesn't have a \"%s\" script"):format(self.__kind, self.__name or "<unnamed>", tostring(name)), 2)
  end
  if fn ~= nil and type(fn) ~= "function" then error(self.__kind .. ":SetScript(): Usage: SetScript(\"type\", function)", 2) end
  self.__scripts[name] = fn
end
function H.GetScript(self, name) return self.__scripts[name] end
function H.HookScript(self, name, fn)
  local old = self.__scripts[name]
  self.__scripts[name] = function(...) if old then old(...) end fn(...) end
end
function H.RegisterEvent(self, ev)
  if type(ev) ~= "string" then error("Frame:RegisterEvent(): Usage: RegisterEvent(\"event\")", 2) end
  if RESTRICTED_EVENTS[ev] then error("Frame:RegisterEvent(): Attempt to register for restricted event " .. ev, 2) end
  if not KNOWN_EVENTS[ev] then error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. ev .. "\"", 2) end
  self.__events[ev] = true
  return true
end
H.RegisterUnitEvent = H.RegisterEvent
function H.UnregisterEvent(self, ev) self.__events[ev] = nil end
function H.UnregisterAllEvents(self) self.__events = {} end
function H.IsEventRegistered(self, ev) return self.__events[ev] == true end
function H.CreateTexture(self, _, layer) local x = self.__new("Texture", nil, self); x.__layer = layer or "ARTWORK"; return x end
function H.CreateFontString(self, _, layer, inherits)
  local x = self.__new("FontString", nil, self)
  x.__layer = layer or "OVERLAY"
  if inherits then x.__font = inherits end
  return x
end
function H.Show(self) local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function H.Hide(self) local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function H.SetShown(self, v) if v then H.Show(self) else H.Hide(self) end end
function H.IsShown(self) return self.__shown end
function H.IsVisible(self) return self.__shown and (not self.__parent or self.__parent.__shown ~= false) end
function H.SetSize(self, w, h) self.__w, self.__h = w, h or w end
function H.SetWidth(self, w)
  if type(w) ~= "number" or w ~= w then error(self.__kind .. ":SetWidth(): Usage: SetWidth(width)", 2) end
  self.__w = w
end
function H.SetHeight(self, h) self.__h = h end
function H.GetWidth(self) return self.__w end
function H.GetHeight(self) return self.__h end
function H.SetFont(self, path, size, flags)
  if type(path) ~= "string" or type(size) ~= "number" then
    error(self.__kind .. ":SetFont(): Usage: self:SetFont(fontFile, height, flags)", 2)
  end
  if self.__client.o.strictSetFont and flags == nil then
    error(self.__kind .. ":SetFont(): Usage: self:SetFont(fontFile, height, flags)", 2)
  end
  self.__font = path
  self.__size = size
end
function H.SetFontObject(self, fo) self.__font = fo end
function H.GetFont(self) return self.__font, self.__size or 12, "" end
function H.SetText(self, t)
  if (self.__kind == "FontString" or self.__kind == "EditBox") and not self.__font then
    error(self.__kind .. ":SetText(): Font not set", 2)
  end
  if isSecret(t) then self.__text = t else self.__text = t == nil and "" or tostring(t) end
end
function H.GetText(self) return self.__text end
function H.SetPoint(self, point, a2, a3, a4, a5)
  if type(point) ~= "string" then error(self.__kind .. ":SetPoint(): Usage: SetPoint(\"point\" [, region or nil] [, \"relativePoint\"] [, offsetX, offsetY])", 2) end
  local rel, relPoint, x, y = nil, point, 0, 0
  if type(a2) == "number" then x, y = a2, a3 or 0
  elseif a2 ~= nil then
    rel = a2
    if type(a3) == "string" then relPoint, x, y = a3, a4 or 0, a5 or 0 else x, y = a3 or 0, a4 or 0 end
  end
  for i = #self.__points, 1, -1 do if self.__points[i][1] == point then table.remove(self.__points, i) end end
  table.insert(self.__points, { point, rel or self.__parent, relPoint, x, y })
end
function H.ClearAllPoints(self) self.__points = {} end
function H.GetPoint(self, i)
  local p = self.__points[i or 1]
  if not p then return nil end
  return p[1], p[2], p[3], p[4], p[5]
end
function H.StartMoving(self) self.__moving = true end
function H.StopMovingOrSizing(self)
  -- the client re-anchors a moved frame to the screen; model it as TOPLEFT against UIParent's BOTTOMLEFT
  if self.__moving then self.__points = { { "TOPLEFT", self.__client.env.UIParent, "BOTTOMLEFT", 700, 1000 } } end
  self.__moving = false
end
function H.GetName(self) return self.__name end
function H.GetParent(self) return self.__parent end
function H.SetScrollChild(self, child) self.__child = child; child.__scrollParent = self end
function H.SetFocus(self) self.__focus = true end
function H.ClearFocus(self) self.__focus = false end
function H.HasFocus(self) return self.__focus or false end
function H.HighlightText(self) self.__highlighted = true end
function H.IsEnabled(self) return not self.__disabled end
function H.GetEffectiveScale() return 1 end
function H.GetCenter() return 800, 500 end
-- tooltip
function H.SetOwner(self, owner, anchor) self.__owner, self.__anchor, self.__lines = owner, anchor, {} end
function H.ClearLines(self) self.__lines = {} end
function H.NumLines(self) return #(self.__lines or {}) end
function H.AddLine(self, text)
  self.__lines = self.__lines or {}
  self.__lines[#self.__lines + 1] = tostring(text)
end
function H.AddDoubleLine(self, l, r)
  self.__lines = self.__lines or {}
  self.__lines[#self.__lines + 1] = tostring(l) .. "  |  " .. tostring(r)
end

local function newObj(client, kind, template, parent)
  local o = { __kind = kind, __template = template, __parent = parent, __client = client, __scripts = {}, __events = {},
              __shown = true, __w = 0, __h = 0, __text = "", __points = {} }
  o.__backdrop = template and template:find("BackdropTemplate") and true or false
  if template == "UIPanelButtonTemplate" or template == "UIPanelCloseButton" or template == "UICheckButtonTemplate" then
    o.__font = "template"
  end
  if kind == "Button" or kind == "CheckButton" then o.__font = o.__font or "button" end
  o.__new = function(k, t, p) return newObj(client, k, t, p) end
  client.frames[#client.frames + 1] = o
  return setmetatable(o, { __index = function(t, k)
    if METHODS[k] or (kind == "GameTooltip" and TOOLTIP[k]) then return H[k] or NOOP end
    if BACKDROP[k] then if t.__backdrop then return NOOP end return nil end
    if type(k) == "string" and (k:match("^%l") or k:match("^__")) then return nil end -- plain fields read nil, like on a real frame
    error("unknown widget method: " .. tostring(k) .. " on " .. kind, 2)
  end })
end

----------------------------------------------------------------------------
-- SavedVariables: written at logout like the client does (strings, numbers, booleans, tables; no functions)
----------------------------------------------------------------------------
local function svWrite(v, seen)
  local t = type(v)
  if t == "string" then return string.format("%q", v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    return string.format("%.17g", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" and not isSecret(v) then
    if seen[v] then error("SavedVariables: table saved twice (cycle or shared reference)") end
    seen[v] = true
    local parts = {}
    for k, x in pairs(v) do
      local ks
      if type(k) == "string" then ks = "[" .. string.format("%q", k) .. "]"
      elseif type(k) == "number" then ks = "[" .. string.format("%.17g", k) .. "]" end
      local xs = ks and svWrite(x, seen)
      if ks and xs then parts[#parts + 1] = ks .. " = " .. xs end
    end
    seen[v] = nil
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return nil
end
local function svRoundTrip(v)
  if v == nil then return nil end
  local src = svWrite(v, {})
  return assert(loadstring("return " .. src))()
end

----------------------------------------------------------------------------
-- a client: its own globals, character and clock
----------------------------------------------------------------------------
local XP_TO_NEXT = { [10] = 7600, [11] = 8800, [12] = 10100, [13] = 11400, [14] = 12900, [15] = 14400, [59] = 209800 }

local function baseLua(c)
  local env = {}
  for _, k in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "setmetatable",
    "getmetatable", "rawget", "rawset", "rawequal", "unpack", "loadstring", "setfenv", "getfenv", "_VERSION",
    "collectgarbage", "gcinfo" }) do env[k] = _G[k] end
  env.tostring = function(x) if isSecret(x) then return x end return tostring(x) end
  env.tonumber = function(x, b) if isSecret(x) then return x end return tonumber(x, b) end
  env.type = function(x) if isSecret(x) then return type(SECRETS[x].v) end return type(x) end
  env.math = {}
  for k, v in pairs(math) do if k ~= "randomseed" then env.math[k] = v end end
  env.table = {}
  for k, v in pairs(table) do env.table[k] = v end
  env.string = guardedString()
  env.coroutine = coroutine
  env.bit = require("bit")
  env.date, env.time, env.difftime = os.date, os.time, os.difftime
  -- the client's aliases
  env.strmatch, env.strfind, env.format, env.strlower, env.strupper, env.strsub, env.gsub, env.strlen =
    env.string.match, env.string.find, env.string.format, env.string.lower, env.string.upper, env.string.sub, env.string.gsub, env.string.len
  env.tinsert, env.tremove, env.floor, env.ceil, env.max, env.min, env.abs =
    table.insert, table.remove, math.floor, math.ceil, math.max, math.min, math.abs
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.issecretvalue = function(x) return isSecret(x) end
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    c.printed[#c.printed + 1] = table.concat(parts, " ")
  end
  return env
end

local function newClient(label, o)
  local c = { label = label, o = o, clock = 1000, timers = {}, frames = {}, printed = {}, steps = {}, checks = {},
              level = o.level, xp = o.xp or 0, rested = o.rested, gained = 0, ns = {},
              expect = { kills = 0, base = 0, quests = 0, total = 0 } }
  local env = baseLua(c)
  env._G = env
  c.env = env

  env.UIParent = newObj(c, "Frame"); env.UIParent.__name = "UIParent"; env.UIParent:SetSize(1920, 1080)
  env.WorldFrame = newObj(c, "Frame"); env.WorldFrame.__name = "WorldFrame"
  env.GameTooltip = newObj(c, "GameTooltip", "GameTooltipTemplate", env.UIParent); env.GameTooltip.__name = "GameTooltip"
  env.GameTooltip.__shown = false
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.printed[#c.printed + 1] = tostring(m) end }
  env.SlashCmdList = {}
  env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  env.BackdropTemplateMixin = {}
  env.CreateFrame = function(kind, name, parent, template)
    if not KINDS[kind] then error("CreateFrame(): Unknown frame type '" .. tostring(kind) .. "'", 2) end
    if template then
      for t in template:gmatch("[^,%s]+") do
        if not TEMPLATES[t] then error("CreateFrame(): Couldn't find inherited node \"" .. t .. "\"", 2) end
      end
    end
    local f = newObj(c, kind, template, parent)
    f.__name = name
    if name then env[name] = f end
    return f
  end

  -- C_Timer on the fake clock; NewTimer/NewTicker callbacks get their handle, like the client
  local function schedule(sec, fn, n, api, passHandle)
    if type(sec) ~= "number" or type(fn) ~= "function" then error("Usage: " .. api .. "(seconds, callback)", 3) end
    local h = { t = c.clock + sec, sec = sec, fn = fn, left = n or 1, passHandle = passHandle }
    function h:Cancel() self.cancelled = true end
    function h:IsCancelled() return self.cancelled == true end
    c.timers[#c.timers + 1] = h
    return h
  end
  env.C_Timer = {
    After = function(sec, fn) schedule(sec, fn, 1, "C_Timer.After") end,
    NewTimer = function(sec, fn) return schedule(sec, fn, 1, "C_Timer.NewTimer", true) end,
    NewTicker = function(sec, fn, n) return schedule(sec, fn, n or math.huge, "C_Timer.NewTicker", true) end,
  }
  env.GetTime = function() return c.clock end

  -- the character
  env.UnitName = function(unit)
    if unit == "npc" then return c.npcName end
    if unit == "player" then return o.name end
  end
  env.UnitGUID = function(unit) if unit == "player" then return "Player-4455-0ABCDEF0" end end
  env.UnitClass = function() return "Mage", "MAGE", 8 end
  env.UnitRace = function() return "Human", "Human", 1 end
  env.UnitFactionGroup = function() return "Alliance", "Alliance" end
  env.UnitLevel = function() return c.level end
  env.UnitXP = function() return c.xp end
  env.UnitXPMax = function() if o.maxLevel then return 0 end return XP_TO_NEXT[c.level] or 10000 end
  env.GetXPExhaustion = function() return c.rested end
  env.GetMaxPlayerLevel = function() return 60 end
  env.GetRealmName = function() return "Forever Normal" end
  env.GetNormalizedRealmName = function() return "ForeverNormal" end
  env.GetRealZoneText = function() return c.zone or "Elwynn Forest" end
  env.GetBuildInfo = function() return CLIENT.version, CLIENT.build, CLIENT.date, CLIENT.interface end
  env.GetMoney = function() return 123456 end
  env.GetInventoryItemID = function(_, slot) local ids = { [1] = 7413, [5] = 6096, [16] = 2132, [18] = 5071 }; return ids[slot] end
  env.GetInventoryItemLink = function(_, slot)
    local id = env.GetInventoryItemID("player", slot)
    return id and ("|cffffffff|Hitem:" .. id .. "::::::::12:::::::|h[Item " .. id .. "]|h|r") or nil
  end
  env.GetPlayerInfoByGUID = function() return "Mage", "MAGE", "Human", "Human", 2, "Someone", "Forever Normal" end

  -- modern spellbook: a General line and a class line whose last two entries are not learned yet
  env.Enum = { SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
               SpellBookSpellBank = { Player = 0, Pet = 1 } }
  local book = {
    { spellID = 6603, itemType = 1 }, { spellID = 20599, itemType = 1 }, { spellID = 20864, itemType = 1 },
    { spellID = 133, itemType = 1 }, { spellID = 168, itemType = 1 }, { spellID = 1459, itemType = 1 },
    { spellID = 116, itemType = 1 }, { spellID = 2136, itemType = 2 }, { spellID = 120, itemType = 2 },
  }
  for _, e in ipairs(book) do e.actionID = e.spellID end
  env.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 2 end,
    GetSpellBookSkillLineInfo = function(i)
      if i == 1 then return { name = "General", itemIndexOffset = 0, numSpellBookItems = 3 } end
      if i == 2 then return { name = "Mage", itemIndexOffset = 3, numSpellBookItems = 6 } end
    end,
    GetSpellBookItemInfo = function(slot, bank)
      if bank ~= 0 and bank ~= 1 then error("bad argument #2 to 'GetSpellBookItemInfo' (Enum.SpellBookSpellBank expected)", 2) end
      return book[slot]
    end,
  }
  env.C_Spell = { GetSpellLink = function(id) return "|cff71d5ff|Hspell:" .. id .. ":0|h[Spell " .. id .. "]|h|r" end }
  env.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemID = function(bag, slot) if bag == 0 and slot <= 3 then return ({ 6948, 2070, 159 })[slot] end end,
  }
  -- items: c.itemClass[id] (default 4, armor), c.unloaded[id] = not in the client's cache yet
  c.itemClass, c.unloaded, c.tipHooks, c.loadRequests = {}, {}, {}, {}
  env.C_Item = {
    GetItemInfo = function(id)
      if c.unloaded[id] then return nil end
      return "Item " .. id, "|cff1eff00|Hitem:" .. id .. "::::::::12:::::::|h[Item " .. id .. "]|h|r", 2, 27, 22, "Armor", "Cloth", 1,
        "INVTYPE_CHEST", 132000 + id % 1000, 815, c.itemClass[id] or 4, 1, 1
    end,
    RequestLoadItemDataByID = function(id) c.loadRequests[#c.loadRequests + 1] = id end,
  }
  env.Enum.TooltipDataType = { Item = 0, Spell = 1, Unit = 2 }
  env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 0 then c.tipHooks[#c.tipHooks + 1] = fn end end }
  env.C_TooltipInfo = {
    GetItemByID = function(id)
      return { id = id, lines = { { leftText = "Item " .. id }, { leftText = "Binds when picked up" }, { leftText = "Chest", rightText = "Cloth" },
        { leftText = "39 Armor" }, { leftText = "+5 Stamina" }, { leftText = "Item Level 27" }, { leftText = "Requires Level 22" } } }
    end,
  }
  c.loot = {}
  env.GetNumLootItems = function() return #c.loot end
  env.GetLootSlotLink = function(i) local id = c.loot[i]; return id and ("|cff1eff00|Hitem:" .. id .. "::::::::12:::::::|h[Item " .. id .. "]|h|r") or nil end
  if o.engraving then
    env.C_Engraving = {
      GetRuneCategories = function() return { 5, 7 } end,
      GetRunesForCategory = function(cat)
        return { { skillLineAbilityID = cat * 100 + 1, name = "Rune " .. cat, learnedAbilitySpellIDs = { 400000 + cat } } }
      end,
    }
  end

  -- professions, modern style: prof1, prof2, archaeology, fishing, cooking
  env.GetProfessions = function() return 1, 2, nil, 3, 4 end
  env.GetProfessionInfo = function(i)
    local p = ({ { "Tailoring", 75, 150 }, { "Enchanting", 60, 150 }, { "Fishing", 40, 75 }, { "Cooking", 55, 75 } })[i]
    if p then return p[1], 136249, p[2], p[3], 2, 0, 197, 0, 0, 0, p[1] end
  end

  -- guild
  env.IsInGuild = function() return o.guild == true end
  env.GetGuildInfo = function() if o.guild then return "Forever Guild", "Member", 3, nil end end
  env.GetNumGuildMembers = function() if o.guild then return 3, 2, 2 end return 0, 0, 0 end
  env.GetGuildRosterInfo = function(i)
    local m = ({ { "Bjørn-ForeverNormal", 14, true }, { "Kari-ForeverNormal", 22, true }, { "Ola-ForeverNormal", 9, false } })[i]
    if m then return m[1], "Member", 3, m[2], "Mage", "Elwynn Forest", "", "", m[3], 0, "MAGE", 0, 0, false, false, 0, "Player-4455-1" end
  end
  env.C_GuildInfo = { GuildRoster = function()
    c.rosterRequests = (c.rosterRequests or 0) + 1
    if o.guild then env.C_Timer.After(0.5, function() c.fire("GUILD_ROSTER_UPDATE", false) end) end
  end }

  -- trainer window
  env.GetNumTrainerServices = function() return c.trainerOpen and 4 or 0 end
  env.GetTrainerServiceInfo = function(i)
    local s = ({ { "Class Skills", nil, "header", true }, { "Frostbolt", "Rank 3", "available" },
                 { "Arcane Intellect", "Rank 1", "used" }, { "Frost Nova", "Rank 2", "unavailable" } })[i]
    if s then return s[1], s[2], s[3], s[4] end
  end
  env.GetTrainerServiceCost = function(i) return i * 900, false, 0 end
  env.GetTrainerServiceLevelReq = function(i) return 10 + i end

  -- combat-log flag constants still exist; the combat log does not reach addons
  env.COMBATLOG_OBJECT_REACTION_HOSTILE = 0x40
  env.COMBATLOG_OBJECT_TYPE_PLAYER = 0x400

  -- enUS GlobalStrings for the chat XP lines
  env.COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
  env.COMBATLOG_XPGAIN_EXHAUSTION1_GROUP = "%s dies, you gain %d experience. (%s exp %s bonus, +%d group bonus)"
  env.COMBATLOG_XPGAIN_EXHAUSTION1_RAID = "%s dies, you gain %d experience. (%s exp %s bonus, -%d raid penalty)"
  env.COMBATLOG_XPGAIN_EXHAUSTION2 = "%s dies, you gain %d experience. (%s exp %s bonus)"
  env.COMBATLOG_XPGAIN_EXHAUSTION4 = "%s dies, you gain %d experience. (%s exp %s penalty)"
  env.COMBATLOG_XPGAIN_EXHAUSTION4_GROUP = "%s dies, you gain %d experience. (%s exp %s penalty, +%d group bonus)"
  env.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
  env.COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s dies, you gain %d experience. (+%d group bonus)"
  env.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience."
  env.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP = "You gain %d experience. (+%d group bonus)"

  -- deliberately absent (Classic-only or removed in 11.x/12.x): GetSpellTabInfo, GetNumSpellTabs, GetSpellLink,
  -- GetNumSkillLines, GetSkillLineInfo, UnitAura, GetContainerNumSlots, GetContainerItemID, GuildRoster,
  -- CombatLogGetCurrentEventInfo (the combat log is closed to addons), GetNumTalentTabs, GetTalentInfo.

  -- protected call: record an error against the running step, like the client's error handler
  function c.protect(where, fn, ...)
    local ok, e = xpcall(fn, function(err) return { msg = tostring(err), tb = debug.traceback("", 2) } end, ...)
    if not ok then
      local s = c.cur or { errors = {} }
      s.errors[#s.errors + 1] = { where = where, msg = e.msg, tb = e.tb }
    end
    return ok
  end
  -- events go to every frame that registered them, each handler protected on its own
  function c.fire(event, ...)
    local n = 0
    for _, f in ipairs(c.frames) do
      if f.__events[event] and f.__scripts.OnEvent then
        n = n + 1
        c.protect("OnEvent " .. event, f.__scripts.OnEvent, f, event, ...)
      end
    end
    return n
  end
  return c
end

-- run what falls due on the clock (timer callbacks protected one by one), then advance it
local function tick(c, seconds)
  local target = c.clock + seconds
  for _ = 1, 10000 do
    local best, bi
    for i, h in ipairs(c.timers) do
      if not h.cancelled and h.t <= target and (not best or h.t < best.t) then best, bi = h, i end
    end
    if not best then break end
    c.clock = math.max(c.clock, best.t)
    best.left = best.left - 1
    if best.left <= 0 then table.remove(c.timers, bi) else best.t = best.t + best.sec end
    if best.passHandle then c.protect("timer", best.fn, best) else c.protect("timer", best.fn) end
  end
  for i = #c.timers, 1, -1 do if c.timers[i].cancelled then table.remove(c.timers, i) end end
  c.clock = target
end

local function slash(c, line)
  local cmd, rest = line:match("^(/%S+)%s*(.-)$")
  cmd = cmd:lower()
  for k, v in pairs(c.env) do
    if type(k) == "string" and type(v) == "string" then
      local name = k:match("^SLASH_(.-)%d+$")
      if name and v:lower() == cmd and c.env.SlashCmdList[name] then
        c.protect("slash " .. line, c.env.SlashCmdList[name], rest)
        return true
      end
    end
  end
  error("no slash command " .. cmd .. " is registered")
end

local function step(c, label, fn)
  local s = { label = label, errors = {}, notes = {} }
  c.steps[#c.steps + 1] = s
  c.cur = s
  local printed = #c.printed
  local ok, e = xpcall(fn, function(err) return { msg = tostring(err), tb = debug.traceback("", 2) } end)
  if not ok then s.errors[#s.errors + 1] = { where = "harness", msg = e.msg, tb = e.tb } end
  for i = printed + 1, #c.printed do s.notes[#s.notes + 1] = "chat: " .. c.printed[i] end
  c.cur = nil
  return s
end
local function note(c, text) if c.cur then c.cur.notes[#c.cur.notes + 1] = text end end
local function check(c, label, ok, detail)
  c.checks[#c.checks + 1] = { label = label, ok = ok and true or false, detail = detail }
end

local function loadFiles(c, dir, files, addonName)
  for _, f in ipairs(files) do
    step(c, "load " .. f, function()
      local chunk, err = loadstring(readFile(dir .. f), "@Interface/AddOns/" .. addonName .. "/" .. f)
      if not chunk then error(err) end
      setfenv(chunk, c.env)
      c.protect("file load", chunk, addonName, c.ns)
    end)
  end
end

----------------------------------------------------------------------------
-- playing: XP the way the client reports it
----------------------------------------------------------------------------
local function gain(c, amount, restedUsed)
  c.gained = c.gained + amount
  if restedUsed and restedUsed > 0 and c.rested then
    c.rested = c.rested - restedUsed
    if c.rested <= 0 then c.rested = nil end
  end
  c.xp = c.xp + amount
  local ding
  while not c.o.maxLevel and XP_TO_NEXT[c.level] and c.xp >= XP_TO_NEXT[c.level] do
    c.xp = c.xp - XP_TO_NEXT[c.level]
    c.level = c.level + 1
    ding = c.level
  end
  return ding
end

local function chatXP(c, msg)
  if c.o.secretChat then msg = secret(msg) end
  return c.fire("CHAT_MSG_COMBAT_XP_GAIN", msg, "", "", "", "", "", 0, 0, "", 0, 0, "", 0, false, false, false, false)
end

-- a kill: the chat line built from the client's own GlobalStrings, and the XP bar moving
local function kill(c, mob, base, rested, group, order)
  local E, total = c.env, base + rested + group
  local msg
  if rested > 0 and group > 0 then msg = string.format(E.COMBATLOG_XPGAIN_EXHAUSTION1_GROUP, mob, total, "+" .. rested, "Rested", group)
  elseif rested > 0 then msg = string.format(E.COMBATLOG_XPGAIN_EXHAUSTION1, mob, total, "+" .. rested, "Rested")
  elseif group > 0 then msg = string.format(E.COMBATLOG_XPGAIN_FIRSTPERSON_GROUP, mob, total, group)
  else msg = string.format(E.COMBATLOG_XPGAIN_FIRSTPERSON, mob, total) end
  c.expect.kills = c.expect.kills + 1
  c.expect.base = c.expect.base + base
  c.expect.groupBonus = (c.expect.groupBonus or 0) + group
  c.expect.total = c.expect.total + total
  local ding = gain(c, total, rested)
  note(c, "chat line: " .. msg .. (c.o.secretChat and "  (delivered as a secret value)" or ""))
  if ding then
    c.fire("PLAYER_LEVEL_UP", ding, 12, 20, 1, 1, 0, 0, 0, 0)
    c.fire("PLAYER_XP_UPDATE", "player")
    chatXP(c, msg)
  elseif order == "xp-first" then
    c.fire("PLAYER_XP_UPDATE", "player")
    chatXP(c, msg)
  else
    chatXP(c, msg)
    c.fire("PLAYER_XP_UPDATE", "player")
  end
  return ding
end

local function charStore(c)
  local db = c.env.ForeverProbeDB
  return db and db.chars and db.chars[c.o.name .. "-Forever Normal"]
end

local function ledgerTotals(c)
  local s = charStore(c)
  local t = { total = 0, base = 0, kills = 0, quests = 0, unknown = 0, records = 0 }
  if not s then return t end
  local recs = {}
  for _, r in ipairs(s.history or {}) do recs[#recs + 1] = r end
  if s.current then recs[#recs + 1] = s.current end
  for _, r in ipairs(recs) do
    t.records = t.records + 1
    local b = r.xpBySource or {}
    t.total = t.total + (b.kill or 0) + (b.quest or 0) + (b.unknown or 0)
    t.unknown = t.unknown + (b.unknown or 0)
    t.base = t.base + (r.baseXP or 0)
    t.kills = t.kills + (r.killCount or 0)
    t.quests = t.quests + (r.questCount or 0)
  end
  return t
end

-- JSON check for the export blob (what foreverrank.com has to parse)
local function jsonValid(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local value
  local function str()
    if s:sub(i, i) ~= '"' then return false, "string expected at " .. i end
    i = i + 1
    while true do
      local ch = s:sub(i, i)
      if ch == "" then return false, "unterminated string" end
      if ch == '"' then i = i + 1 return true end
      if ch == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e:match('^["\\/bfnrt]$') then i = i + 2
        elseif e == "u" and s:sub(i + 2, i + 5):match("^%x%x%x%x$") then i = i + 6
        else return false, ("invalid escape \\%s at %d"):format(e == "\n" and "<newline>" or e, i) end
      elseif ch:byte() < 32 then return false, ("raw control character %d at %d"):format(ch:byte(), i)
      else i = i + 1 end
    end
  end
  local function list(close, member)
    i = i + 1
    ws()
    if s:sub(i, i) == close then i = i + 1 return true end
    while true do
      ws()
      local ok, e = member()
      if not ok then return ok, e end
      ws()
      local d = s:sub(i, i)
      i = i + 1
      if d == close then return true end
      if d ~= "," then return false, ("',' or '%s' expected at %d"):format(close, i - 1) end
    end
  end
  value = function()
    ws()
    local ch = s:sub(i, i)
    if ch == "{" then
      return list("}", function()
        local ok, e = str()
        if not ok then return ok, e end
        ws()
        if s:sub(i, i) ~= ":" then return false, "':' expected at " .. i end
        i = i + 1
        return value()
      end)
    elseif ch == "[" then return list("]", value)
    elseif ch == '"' then return str() end
    local lit = s:match("^true", i) or s:match("^false", i) or s:match("^null", i)
    if lit then i = i + #lit return true end
    local num = s:match("^%-?%d+%.?%d*[eE]?[%-+]?%d*", i)
    if num and #num > 0 then i = i + #num return true end
    return false, ("unexpected '%s' at %d"):format(ch, i)
  end
  local ok, e = value()
  if not ok then return false, e end
  ws()
  if i <= #s then return false, "trailing data at " .. i end
  return true
end

local function button(c, label)
  for _, f in ipairs(c.frames) do
    if f.__kind == "Button" and f.__template == "UIPanelButtonTemplate" and f.__text == label then return f end
  end
end
local function bar(c) return c.env.ForeverProbeBar end
local function panel(c) return c.env.ForeverProbePanel end

local function hover(c, frame)
  local tip = c.env.GameTooltip
  tip.__lines = {}
  if not frame then note(c, "no pace bar frame") return end
  if frame.__scripts.OnEnter then c.protect("OnEnter", frame.__scripts.OnEnter, frame) end
  note(c, "bar shown: " .. tostring(frame.__shown) .. "; tooltip: " .. table.concat(tip.__lines or {}, " / "))
  if frame.__scripts.OnLeave then c.protect("OnLeave", frame.__scripts.OnLeave, frame) end
end

----------------------------------------------------------------------------
-- the scenario steps
----------------------------------------------------------------------------
local function boot(c)
  loadFiles(c, ADDON_DIR, TOC.files, ADDON)
  step(c, "SavedVariables loaded, ADDON_LOADED", function()
    c.env.ForeverProbeDB = svRoundTrip(c.o.db)
    c.fire("ADDON_LOADED", ADDON)
  end)
  step(c, "PLAYER_LOGIN", function() c.fire("PLAYER_LOGIN") end)
  step(c, "PLAYER_ENTERING_WORLD (login)", function() c.fire("PLAYER_ENTERING_WORLD", true, false) end)
  step(c, "timers, first 10 s (pace init +2 s, login snapshot +5 s, guild roster +8 s)", function() tick(c, 10) end)
end

local function play(c)
  step(c, "hover the pace bar", function() hover(c, bar(c)) end)
  step(c, "kill, rested (chat line, then PLAYER_XP_UPDATE)", function() kill(c, "Kobold Vermin", 75, 75, 0, "chat-first"); tick(c, 2) end)
  step(c, "kill, plain (PLAYER_XP_UPDATE, then chat line)", function() kill(c, "Kobold Worker", 80, 0, 0, "xp-first"); tick(c, 2) end)
  step(c, "kill in a group, rested", function() kill(c, "Kobold Laborer", 70, 70, 14, "chat-first"); tick(c, 2) end)
  step(c, "XP with no chat line (exploration), reconciled", function()
    gain(c, 45); c.expect.base = c.expect.base + 45; c.expect.total = c.expect.total + 45
    c.fire("PLAYER_XP_UPDATE", "player"); tick(c, 2)
  end)
  step(c, "quest turn-in (QUEST_TURNED_IN 120 XP, then PLAYER_XP_UPDATE)", function()
    gain(c, 120); c.expect.base = c.expect.base + 120; c.expect.total = c.expect.total + 120; c.expect.quests = c.expect.quests + 1
    c.expect.questXP = (c.expect.questXP or 0) + 120
    c.fire("QUEST_TURNED_IN", 176, 120, 350)
    if c.o.questChat then chatXP(c, string.format(c.env.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED, 120)) end
    c.fire("PLAYER_XP_UPDATE", "player"); tick(c, 2)
  end)
  step(c, "kill that levels up (PLAYER_LEVEL_UP, PLAYER_XP_UPDATE, chat line)", function()
    local ding = kill(c, "Defias Thug", 45, 45, 0)
    note(c, "level now " .. c.level .. (ding and " (dinged)" or " (NO ding: harness numbers off)"))
    tick(c, 3)
  end)
  step(c, "PLAYER_DEAD", function() c.fire("PLAYER_DEAD") end)
  step(c, "GUILD_ROSTER_UPDATE arrives", function()
    local n = c.fire("GUILD_ROSTER_UPDATE", false)
    note(c, "delivered to " .. n .. " frame(s)" .. (n == 0 and " (nobody registered it)" or ""))
  end)
  step(c, "trainer window (TRAINER_SHOW)", function()
    c.trainerOpen, c.npcName = true, "Maginor Dumas"
    c.fire("TRAINER_SHOW"); tick(c, 1)
    c.trainerOpen, c.npcName = false, nil
  end)
  step(c, "hover the pace bar again", function()
    hover(c, bar(c))
    local shown
    for _, l in ipairs(c.env.GameTooltip.__lines or {}) do shown = shown or l:match("^This level  |  (.*)$") end
    local H, U = c.ns.History, c.ns.util
    if H and U and shown then
      local live = U.FormatTime(H:Elapsed())
      check(c, "tooltip 'This level' is the live level time", shown == live, ("tooltip says %s, History:Elapsed() is %s"):format(shown, live))
    end
  end)
  step(c, "idle 2 min, then a loading screen (PLAYER_ENTERING_WORLD) and 10 s", function()
    tick(c, 120)
    local H = c.ns.History
    c.before = { elapsed = H and H.Elapsed and H:Elapsed(), samples = H and H.KillXPSamples and #H:KillXPSamples() }
    c.zone = "Westfall"
    c.fire("PLAYER_ENTERING_WORLD", false, false); tick(c, 10)
    c.after = { elapsed = H and H.Elapsed and H:Elapsed(), samples = H and H.KillXPSamples and #H:KillXPSamples() }
  end)
end

local function commands(c)
  step(c, "/probe", function()
    slash(c, "/probe")
    local p = panel(c)
    note(c, "panel: " .. (p and ("shown=" .. tostring(p.__shown) .. ", status '" .. tostring(p.status and p.status.__text):gsub("\n", " / ") .. "'") or "not built"))
  end)
  step(c, "/probe export", function()
    slash(c, "/probe export")
    local box = c.env.ForeverProbeBox
    local blob = box and box.__text or ""
    c.blob = blob
    note(c, ("copy box: %d chars, starts '%s'"):format(#blob, blob:sub(1, 40)))
    if VERBOSE then note(c, "export: " .. blob) end
  end)
  step(c, "/probe bar (hide)", function() slash(c, "/probe bar"); note(c, "bar shown: " .. tostring(bar(c) and bar(c).__shown)) end)
  step(c, "/probe bar (show)", function() slash(c, "/probe bar"); note(c, "bar shown: " .. tostring(bar(c) and bar(c).__shown)) end)
  step(c, "/probe debug", function() slash(c, "/probe debug") end)
end

local function panelButtons(c)
  for _, label in ipairs({ "Export data", "Pace bar", "Pace bar", "New snapshot" }) do
    step(c, "panel button '" .. label .. "'", function()
      local b = button(c, label)
      if not b then note(c, "button not found (panel never built)") return end
      c.protect("OnClick " .. label, b.__scripts.OnClick, b, "LeftButton", false)
    end)
  end
  step(c, "pace bar: drag, then right-click", function()
    local b = bar(c)
    c.protect("OnDragStart", b.__scripts.OnDragStart, b, "LeftButton")
    c.protect("OnDragStop", b.__scripts.OnDragStop, b)
    c.protect("OnMouseUp", b.__scripts.OnMouseUp, b, "RightButton")
    note(c, "bar shown after right-click: " .. tostring(b.__shown))
    slash(c, "/probe bar")
  end)
end

local function logout(c)
  local saved
  step(c, "logout (SavedVariables written)", function()
    c.fire("PLAYER_LOGOUT")
    saved = svRoundTrip(c.env.ForeverProbeDB)
    note(c, ("ForeverProbe.lua: %d bytes"):format(#(svWrite(c.env.ForeverProbeDB, {}) or "")))
  end)
  return saved
end

----------------------------------------------------------------------------
-- checks: what the steps produced, beyond "did it throw"
----------------------------------------------------------------------------
local function snapshots(c) local d = c.env.ForeverProbeDB return d and d.snapshots or {} end

local function playChecks(c)
  local t = ledgerTotals(c)
  check(c, "every XP point gained is in the History", t.total == c.gained, ("history %d XP, gained %d"):format(t.total, c.gained))
  if c.o.secretChat then
    -- the chat line can't be read: kills can't be told apart and the group bonus can't be separated,
    -- but the rested bonus still comes out, from the rested pool
    local groupBonus = c.expect.groupBonus or 0
    check(c, "kills can't be counted from unreadable lines", t.kills == 0, ("counted %d"):format(t.kills))
    check(c, "base XP with the rested bonus taken out (group bonus unknowable)", t.base == c.expect.base + groupBonus,
      ("base %d, expected %d (true base %d + group bonus %d)"):format(t.base, c.expect.base + groupBonus, c.expect.base, groupBonus))
    check(c, "quest counted", t.quests == c.expect.quests, ("%d of %d"):format(t.quests, c.expect.quests))
    check(c, "all kill XP reconciled from the XP bar", t.unknown == c.gained - (c.expect.questXP or 0),
      ("%d XP reconciled"):format(t.unknown))
  else
    check(c, "kills counted", t.kills == c.expect.kills, ("counted %d of %d kills"):format(t.kills, c.expect.kills))
    check(c, "base XP (rested and group bonus taken out)", t.base == c.expect.base, ("base %d, expected %d"):format(t.base, c.expect.base))
    check(c, "quest counted", t.quests == c.expect.quests, ("%d of %d"):format(t.quests, c.expect.quests))
    check(c, "XP the chat parser missed", t.unknown == 45, ("%d XP reconciled as unknown (45 expected, the exploration)"):format(t.unknown))
  end
  if c.before and c.after and c.before.elapsed then
    check(c, "level timer keeps running across a loading screen", c.after.elapsed >= c.before.elapsed,
      ("Elapsed %.0f s before the loading screen, %.0f s 10 s after it"):format(c.before.elapsed, c.after.elapsed))
    check(c, "kill samples (mobs-to-level range) survive a loading screen", c.after.samples >= c.before.samples,
      ("%d samples before, %d after"):format(c.before.samples, c.after.samples))
  end
  local snaps = snapshots(c)
  local why = {}
  for _, s in ipairs(snaps) do why[#why + 1] = tostring(s.why) end
  check(c, "snapshots taken", #snaps > 0, #snaps .. " (" .. table.concat(why, ", ") .. ")")
  local last = snaps[#snaps]
  if last then
    local meta = c.env.ForeverProbeDB.meta or {}
    check(c, "export says which addon version made it", meta.addon == TOC.meta.Version,
      ("meta.addon = %s, TOC Version = %s (the 0.1.0 beta-day probe also said 0.1.0)"):format(tostring(meta.addon), TOC.meta.Version))
    check(c, "professions in the snapshot (Tailoring, Enchanting, Fishing, Cooking)", #(last.skills or {}) == 4,
      ("%d: %s"):format(#(last.skills or {}), (function() local n = {} for _, s in ipairs(last.skills or {}) do n[#n + 1] = s.n end return table.concat(n, ", ") end)()))
    local learned = 7
    check(c, "snapshot spells are the learned ones (7 learned, 2 greyed-out future spells in the book)", #(last.spells or {}) == learned,
      ("%d spell IDs recorded"):format(#(last.spells or {})))
  end
  if c.blob == nil then -- the slash commands weren't run in this scenario
  elseif #c.blob > 0 then
    local body = c.blob:match("^FPROBE2:(.*)$")
    local ok, e = false, "no FPROBE2: prefix"
    if body then ok, e = jsonValid(body) end
    check(c, "export blob parses as JSON", ok, e or (#c.blob .. " chars"))
  else
    check(c, "export blob produced", false, "copy box empty")
  end
end

----------------------------------------------------------------------------
-- the 0.1.0 beta-day probe, run in its own client to produce its SavedVariables
----------------------------------------------------------------------------
local function oldProbeSavedVariables()
  local c = newClient("0.1.0 probe", { name = "Bjørn", level = 12, xp = 9500, rested = 600, guild = true })
  local toc = readToc(OLD_PROBE_DIR .. "ForeverProbe.toc")
  loadFiles(c, OLD_PROBE_DIR, toc.files, ADDON)
  step(c, "PLAYER_ENTERING_WORLD", function() c.fire("PLAYER_ENTERING_WORLD", true, false) end)
  step(c, "/probe", function() slash(c, "/probe") end)
  local errs = 0
  for _, s in ipairs(c.steps) do errs = errs + #s.errors end
  local db = svRoundTrip(c.env.ForeverProbeDB)
  local keys = {}
  for k in pairs(db or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  return db, keys, errs, c
end

----------------------------------------------------------------------------
-- scenarios
----------------------------------------------------------------------------
local SCENARIOS = {}
local function scenario(title, c) c.title = title; SCENARIOS[#SCENARIOS + 1] = c; return c end

-- 1. fresh install
local c1 = scenario("1. Fresh install (level 12 mage, rested, in a guild; C_Engraving present)",
  newClient("fresh", { name = "Bjørn", level = 12, xp = 9500, rested = 600, guild = true, engraving = true }))
boot(c1)
play(c1)
commands(c1)
panelButtons(c1)
step(c1, "direct call, unreachable in the client: Nemesis:OnGuildRoster()", function()
  if c1.ns.Nemesis and c1.ns.Nemesis.OnGuildRoster then
    c1.protect("Nemesis:OnGuildRoster", c1.ns.Nemesis.OnGuildRoster, c1.ns.Nemesis)
    local g = c1.env.ForeverProbeDB.guild
    local m = g and g.roster and g.roster[1]
    check(c1, "guild roster rows carry level and online (direct call)", m and m.lvl == 14 and m.on == 1,
      m and ("first row: n=%s lvl=%s on=%s"):format(tostring(m.n), tostring(m.lvl), tostring(m.on)) or "no roster saved")
  end
end)
playChecks(c1)
check(c1, "pace bar visible", bar(c1) and bar(c1).__shown, "")
step(c1, "items: hover a chest piece, loot two (one the client hasn't loaded), hover a food", function()
  for _, fn in ipairs(c1.tipHooks) do fn({}, { id = 280001 }) end
  c1.unloaded[280003] = true
  c1.loot = { 280002, 280003 }
  c1.fire("LOOT_READY")
  c1.itemClass[4536] = 0
  for _, fn in ipairs(c1.tipHooks) do fn({}, { id = 4536 }) end
  tick(c1, 1)
  c1.unloaded[280003] = nil
  c1.fire("ITEM_DATA_LOAD_RESULT", 280003, true)
  tick(c1, 1)
  for _, fn in ipairs(c1.tipHooks) do fn({}, { id = 280001 }) end -- again: kept once
  tick(c1, 1)
end)
do
  local it = (c1.env.ForeverProbeDB or {}).items or {}
  local a = it[280001]
  check(c1, "a hovered item's tooltip is kept", a and a.n == "Item 280001" and a.l == 27 and a.r == 22 and a.c == 4 and a.b == CLIENT.build,
    a and ("%s ilvl %s req %s class %s build %s"):format(tostring(a.n), tostring(a.l), tostring(a.r), tostring(a.c), tostring(a.b)) or "nothing kept")
  check(c1, "its lines skip the name and keep the right column", a and a.x[1] == "Binds when picked up" and a.x[2] == "Chest\tCloth" and #a.x == 6,
    a and table.concat(a.x, " | ") or "")
  check(c1, "looted items are kept, the late one once the client has it", it[280002] ~= nil and it[280003] ~= nil and #c1.loadRequests == 1,
    ("280002 %s, 280003 %s, load requests %d"):format(tostring(it[280002] ~= nil), tostring(it[280003] ~= nil), #c1.loadRequests))
  check(c1, "food is not kept (weapons, armor and recipes only)", it[4536] == nil, "")
end
do
  local n = 0; for _, line in ipairs(c1.printed) do if line:find("is running. The game writes its file", 1, true) then n = n + 1 end end
  check(c1, "says once in chat that it is running", n == 1, ("%d time(s)"):format(n))
end
local saved1 = logout(c1)

-- 1b. the next session with 1's SavedVariables
local c1b = scenario("1b. Relog with scenario 1's SavedVariables", newClient("relog", {
  name = "Bjørn", level = c1.level, xp = c1.xp, rested = c1.rested, guild = true, engraving = true, db = saved1 }))
boot(c1b)
step(c1b, "hover the pace bar", function() hover(c1b, bar(c1b)) end)
step(c1b, "/probe debug", function() slash(c1b, "/probe debug") end)
step(c1b, "/probe", function() slash(c1b, "/probe") end)
do
  local s = charStore(c1b)
  local n = 0; for _, line in ipairs(c1b.printed) do if line:find("is running. The game writes its file", 1, true) then n = n + 1 end end
  check(c1b, "the same version doesn't say it again", n == 0, ("%d time(s)"):format(n))
  check(c1b, "level record carried over (level 13 current, level 12 in history)",
    s and s.current and s.current.level == 13 and s.history and s.history[1] and s.history[1].level == 12,
    s and ("current %s, history %d"):format(tostring(s.current and s.current.level), #(s.history or {})) or "no store")
  local p = bar(c1b) and bar(c1b).__points[1]
  local want = saved1 and saved1.pace and saved1.pace.pos
  check(c1b, "pace bar position restored where it was dragged", p and want and p[1] == want[1] and p[3] == want[2] and p[4] == want[3] and p[5] == want[4],
    p and ("%s %s %s %s (saved %s)"):format(tostring(p[1]), tostring(p[3]), tostring(p[4]), tostring(p[5]), want and table.concat(want, " ") or "nothing") or "no point")
end

-- 2. SavedVariables left by the 0.1.0 beta-day probe
local oldDB, oldKeys, oldErrs = oldProbeSavedVariables()
local c2 = scenario("2. ForeverProbeDB left by the 0.1.0 beta-day probe (keys: " .. table.concat(oldKeys, ", ") .. ")",
  newClient("old-db", { name = "Bjørn", level = 12, xp = 9500, rested = 600, guild = true, db = oldDB }))
boot(c2)
play(c2)
commands(c2)
panelButtons(c2)
playChecks(c2)
do
  local d = c2.env.ForeverProbeDB or {}
  local left = {}
  for _, k in ipairs(oldKeys) do if d[k] ~= nil then left[#left + 1] = k end end
  check(c2, "0.1.0's dump is cleared or migrated", #left == 0, "still saved: " .. table.concat(left, ", "))
end

-- 2b. the beta-day table with 0.2/0.3's pace history and bar position on top: those stay
do
  local mixed = {}
  for k, v in pairs(oldDB) do mixed[k] = v end
  mixed.pace = { pos = { "TOPLEFT", "BOTTOMLEFT", 700, 1000 } }
  mixed.chars = { ["Bjørn-Forever Normal"] = { history = { { level = 11, elapsed = 900, baseXP = 8800, killBaseXP = 6000,
    xpBySource = { kill = 6000, quest = 2800, unknown = 0 }, killCount = 60, questCount = 4, deaths = 0, restedConsumed = 0, largestGap = 0 } } } }
  local c2b = scenario("2b. The beta-day table with 0.3.0's pace history written on top of it",
    newClient("mixed-db", { name = "Bjørn", level = 12, xp = 9500, rested = 600, guild = true, db = mixed }))
  boot(c2b)
  local d = c2b.env.ForeverProbeDB or {}
  local left = {}
  for _, k in ipairs(oldKeys) do if d[k] ~= nil then left[#left + 1] = k end end
  check(c2b, "the beta-day keys are gone", #left == 0, "still saved: " .. table.concat(left, ", "))
  local hist = d.chars and d.chars["Bjørn-Forever Normal"] and d.chars["Bjørn-Forever Normal"].history
  check(c2b, "0.3.0's level history survives", hist and #hist == 1 and hist[1].baseXP == 8800, hist and ("records " .. #hist) or "gone")
  check(c2b, "0.3.0's bar position survives", d.pace and d.pace.pos and d.pace.pos[3] == 700, d.pace and d.pace.pos and "kept" or "gone")
end

-- 3. max level
local c3 = scenario("3. Max level (level 60, UnitXPMax 0)", newClient("max", { name = "Kari", level = 60, xp = 0, maxLevel = true, guild = true }))
boot(c3)
step(c3, "hover the pace bar", function() hover(c3, bar(c3)) end)
step(c3, "PLAYER_XP_UPDATE", function() c3.fire("PLAYER_XP_UPDATE", "player"); tick(c3, 2) end)
step(c3, "quest turn-in at max level (QUEST_TURNED_IN, 0 XP)", function() c3.fire("QUEST_TURNED_IN", 2040, 0, 5400); tick(c3, 2) end)
step(c3, "trainer window (TRAINER_SHOW)", function()
  c3.trainerOpen, c3.npcName = true, "Maginor Dumas"; c3.fire("TRAINER_SHOW"); tick(c3, 1); c3.trainerOpen = false
end)
commands(c3)
step(c3, "timers, 10 s (ticker)", function() tick(c3, 10) end)
check(c3, "pace bar hidden at max level", bar(c3) and not bar(c3).__shown, "shown=" .. tostring(bar(c3) and bar(c3).__shown))
do
  local body = c3.blob and c3.blob:match("^FPROBE2:(.*)$")
  local ok, e = false, "no blob"
  if body then ok, e = jsonValid(body) end
  check(c3, "export blob parses as JSON", ok, e or "")
end

-- 4. fresh install, chat XP payloads are secret values
local c4 = scenario("4. Fresh install, CHAT_MSG_COMBAT_XP_GAIN payload is a secret value",
  newClient("secret", { name = "Bjørn", level = 12, xp = 9500, rested = 600, guild = true, secretChat = true }))
boot(c4)
play(c4)
commands(c4)
playChecks(c4)

-- 5, 6. unverified client behaviours, on request
if STRICT_SETFONT then
  local c5 = scenario("5. ASSUMED (unverified): SetFont(file, height) without flags errors",
    newClient("strict-font", { name = "Bjørn", level = 12, xp = 9500, rested = 600, guild = true, strictSetFont = true }))
  boot(c5)
  commands(c5)
end
if QUEST_CHAT then
  local c6 = scenario("6. ASSUMED (unverified): a quest hand-in also prints \"You gain N experience.\"",
    newClient("quest-chat", { name = "Bjørn", level = 12, xp = 9500, rested = 600, guild = true, questChat = true }))
  boot(c6)
  play(c6)
  playChecks(c6)
end

----------------------------------------------------------------------------
-- report
----------------------------------------------------------------------------
local function addonFrames(tb)
  local out = {}
  for line in (tb or ""):gmatch("[^\n]+") do
    local where = line:match("(Interface/AddOns/[^:]+:%d+)")
    if where then out[#out + 1] = where end
  end
  return out
end

local total, all = 0, {}
for _, c in ipairs(SCENARIOS) do
  print(("\n== %s"):format(c.title))
  for _, s in ipairs(c.steps) do
    if #s.errors == 0 then
      print("   ok     " .. s.label)
    else
      print("   ERROR  " .. s.label)
      for _, e in ipairs(s.errors) do
        total = total + 1
        all[#all + 1] = { scen = c.title:match("^(%S+)"), step = s.label, where = e.where, msg = e.msg }
        print(("          [%s] %s"):format(e.where, e.msg))
        if VERBOSE then print("          stack: " .. table.concat(addonFrames(e.tb), " < ")) end
      end
    end
    if VERBOSE then for _, n in ipairs(s.notes) do print("          " .. n) end
    else for _, n in ipairs(s.notes) do if not n:match("^chat:") and not n:match("^chat line") then print("          " .. n) end end end
  end
  local recorded = c.env.ForeverProbeDB and c.env.ForeverProbeDB.meta and c.env.ForeverProbeDB.meta.errors or {}
  for _, e in ipairs(recorded) do
    total = total + 1
    all[#all + 1] = { scen = c.title:match("^(%S+)"), step = "recorded by util.Try", where = e.where or "?", msg = e.msg or "" }
    print(("   ERROR  recorded by ForeverProbe (%s, x%d): %s"):format(e.where or "?", e.n or 1, e.msg or ""))
  end
  if #c.checks > 0 then
    print("   checks:")
    for _, k in ipairs(c.checks) do print(("   %-6s %s%s"):format(k.ok and "PASS" or "WRONG", k.label, (k.detail and k.detail ~= "") and (": " .. k.detail) or "")) end
  end
end

print(("\n0.1.0 probe run to make scenario 2's SavedVariables: %d error(s) inside it (it pcalls everything)"):format(oldErrs))
print(("TOC: Interface %s, client %d; Version %s; files %s"):format(TOC.meta.Interface, CLIENT.interface, TOC.meta.Version, table.concat(TOC.files, " ")))
print(("\n%d error(s) across %d scenarios"):format(total, #SCENARIOS))
local seen = {}
for _, e in ipairs(all) do
  local key = e.scen .. "|" .. e.msg
  if not seen[key] then
    seen[key] = 0
    local n = 0
    for _, x in ipairs(all) do if x.scen .. "|" .. x.msg == key then n = n + 1 end end
    print(("  %-3s x%d  %s    (first at: %s)"):format(e.scen, n, e.msg, e.step))
  end
end
os.exit(total == 0 and 0 or 1)
