-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Map page (page 8 of the QuestBank window, the Forever client only): the game's own map canvas inside the window,
-- built in Lua from Blizzard_MapCanvas's mixins. Five of Blizzard's data providers give it the game's art and explored
-- areas, the zones lit and named under the mouse, your arrow and your party, and the quests' blue areas; QuestBank's
-- layers go on top (QuestMap.lua's icons, Pins.lua's route pins), its own frames with the game's atlases. Above the
-- map a bar of crumbs (Azeroth > Eastern Kingdoms > Elwynn Forest), Here, the dungeons on the map and the game's own
-- map; under it the zone's name and levels; beside it the zone's quests. It opens on your zone and follows you until
-- you go elsewhere. The game's world map is left as it was, QuestBank's layers on it as before.
local _, QB = ...
local MP = { follow = true }
QB.MapPage = MP

local MAP_W, MAP_H, PANEL_W, NAV_H, STRIP_H = 548, 365, 256, 26, 51
local GAP = 8           -- between the map and the quest panel
local CRUMB_MAX = 140   -- a crumb's widest
local SEP_W = 14        -- the ">" between two crumbs
local GOLD = { 1, 0.82, 0.3 }
local INK = { 0.86, 0.8, 0.68 }
local SOFT = { 0.6, 0.55, 0.47 }
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

-- Blizzard's providers on this canvas: each makes its one pin when it is added (out of combat) and writes nothing the
-- world map shares. The providers of quests, POIs, offers, world quests, bonus objectives, vignettes, the waypoint,
-- flight points and dungeon entrances never come here: they share the world map's caches, fire its events or make
-- pins again in a fight, all as QuestBank
local BLIZZARD = { "MapExplorationDataProviderMixin", "MapHighlightDataProviderMixin", "AreaLabelDataProviderMixin",
                   "GroupMembersDataProviderMixin", "QuestBlobDataProviderMixin" }

-- the panel's sections, as the zone's quests come from QuestMap.lua (QM.ZoneQuests)
local SECTIONS = { { key = "ready", name = "Ready to hand in" }, { key = "log", name = "In your log" }, { key = "pickup", name = "To pick up" } }

-- Forever's client with the game's map canvas and the five providers (not Classic Era)
function MP.Available()
  if not (QB.QuestMap and QB.QuestMap.Available() and MapCanvasMixin and MapCanvasScrollControllerMixin and Mixin
    and CreateFromMixins and secureexecuterange) then return false end
  for _, name in ipairs(BLIZZARD) do
    if not _G[name] then return false end
  end
  return true
end

-- the Map key and the sidebar open this page, unless Settings (or /qb map game) gave them back to the game's map
function MP.On() return MP.Available() and QB:Settings().mapPage ~= false end

----------------------------------------------------------------------------
-- the canvas
----------------------------------------------------------------------------
-- MapCanvasMixin with three of its methods again, without the call that empties the game's shared quest and POI
-- caches each frame, on show and on a new map: run from QuestBank's frame it would leave them written by QuestBank,
-- and the world map, the battlefield map and the flight map read them
local Canvas = {}
local function providerShow(dp) dp:OnShow() end
local function providerMapChanged(dp) dp:OnMapChanged() end

function Canvas:OnUpdate()
  self:UpdatePinSuppression()
  self:UpdatePinNudging()
  self:ProcessCursorHandlers()
  self:RunDataProviderOnUpdate()
end

function Canvas:OnShow()
  self:RefreshAll(true)
  secureexecuterange(self.dataProviders, providerShow)
  self:RegisterEvent("HANDLE_UI_ACTION")
end

function Canvas:OnMapChanged()
  secureexecuterange(self.dataProviders, providerMapChanged)
  QB.Try("map page", MP.MapChanged)
end

local function info(id)
  if type(id) ~= "number" or not (C_Map and C_Map.GetMapInfo) then return nil end
  local ok, i = pcall(C_Map.GetMapInfo, id)
  return ok and type(i) == "table" and i or nil
end

-- only a map with art may be shown: Blizzard's scroll container reads its first art layer unchecked
local function hasArt(id)
  if type(id) ~= "number" or not (C_Map and C_Map.MapHasArt) then return false end
  local ok, art = pcall(C_Map.MapHasArt, id)
  return ok and QB.Plain(art) == true
end

local function playerMap()
  if not (MapUtil and MapUtil.GetDisplayableMapForPlayer) then return nil end
  local ok, m = pcall(MapUtil.GetDisplayableMapForPlayer)
  return ok and QB.Plain(m) or nil
end

-- the map on show: the canvas's, or yours while there is none yet (a login in a fight)
local function shownMap()
  if MP.canvas then return QB.Plain(MP.canvas:GetMapID()) end
  return playerMap()
end

-- Ctrl and a left click: QuestBank's waypoint there (the canvas asks this before it opens a zone)
local function ctrlClick(canvas, button, x, y)
  if button ~= "LeftButton" or not (IsControlKeyDown and IsControlKeyDown()) then return false end
  local m = QB.Plain(canvas:GetMapID())
  x, y = QB.Plain(x), QB.Plain(y)
  if not (m and type(x) == "number" and type(y) == "number") then return false end
  QB.Try("map page click", QB.API.SetWaypoint, m, x * 100, y * 100, "Map")
  return true
end

local function setMap(canvas, mapID) canvas:SetMapID(mapID) end

-- the canvas, once, out of combat: Blizzard's providers make their pins as they are added, and a pin made in a fight
-- calls a protected function (SetPassThroughButtons) as QuestBank. Built hidden on a holder of its own, as the
-- templates would build it, and put into the page when the page first shows (MP.Place)
local function build()
  if MP.canvas or not MP.Available() then return end
  if QB.Pins.InCombat() then MP.events:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
  MP.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:SetSize(MAP_W - 4, MAP_H - 4)
  holder:SetPoint("CENTER")
  holder:Hide()
  local canvas = CreateFrame("Frame", "QuestBankMapCanvas", holder)
  Mixin(canvas, MapCanvasMixin, Canvas)
  canvas:SetSize(MAP_W - 4, MAP_H - 4)
  canvas:SetPoint("TOPLEFT")
  -- the two children MapCanvasMixin reads (its template declares them): the scroll frame with the map on its child,
  -- over the whole canvas, and the frame its lock reasons give the mouse to
  canvas.ScrollContainer = CreateFrame("ScrollFrame", nil, canvas, "MapCanvasFrameScrollContainerTemplate")
  canvas.ScrollContainer:ClearAllPoints()
  canvas.ScrollContainer:SetAllPoints(canvas)
  canvas.BorderFrame = CreateFrame("Frame", nil, canvas)
  canvas.BorderFrame:SetAllPoints(canvas)
  canvas:OnLoad()
  for _, s in ipairs({ "OnUpdate", "OnShow", "OnHide", "OnEvent" }) do canvas:SetScript(s, canvas[s]) end
  canvas:SetFrameStrata("MEDIUM")
  -- a click into a zone opens it, a right-click goes up to its parent; the wheel zooms and a drag pans
  canvas:SetShouldNavigateOnClick(true)
  canvas:SetShouldZoomInOnClick(false)
  canvas:SetShouldPanOnClick(false)
  for _, name in ipairs(BLIZZARD) do canvas:AddDataProvider(CreateFromMixins(_G[name])) end
  QB.QuestMap:AddTo(canvas)
  QB.Pins.AddTo(canvas)
  canvas:AddCanvasClickHandler(ctrlClick)
  MP.canvas = canvas
  -- your zone now, hidden: its art loads and QuestBank's layers make their frames (they make none in a fight), so a
  -- first open in one shows them
  MP.Go(playerMap(), "here")
  if MP.frame then MP.Place() end -- the page was opened first (in the fight): the map goes in now
end

-- the zone you are in, while the map follows you; the end of the fight the canvas waited for
MP.events = CreateFrame("Frame")
MP.events:SetScript("OnEvent", QB.Safe(function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then build()
  elseif MP.follow then MP.Go(playerMap(), "follow") end
end, "map page"))

-- at login (Core.lua): the canvas as soon as Blizzard's map code is loaded
function MP:Init()
  if MP.waiting or not QB.QuestMap.Available() then return end
  MP.events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  MP.waiting = QB.Pins.WhenMap(QB.Safe(build, "map page"), "map page: waiting for the map") or true
end

----------------------------------------------------------------------------
-- going places
----------------------------------------------------------------------------
-- show a map, one with art. why: "user" (a crumb, a menu, /qb map) stops following you; "here" and "follow" follow
function MP.Go(mapID, why)
  local canvas = MP.canvas
  if not (canvas and hasArt(mapID)) then return false end
  MP.follow = why ~= "user"
  MP.going = true
  QB.Try("map page", setMap, canvas, mapID)
  MP.going = false
  return true
end

-- your zone, and the map follows you again
function MP.Here()
  MP.follow = true
  MP.Go(playerMap(), "here")
  MP.Update()
end

-- the canvas has a new map (Canvas:OnMapChanged): one QuestBank didn't ask for is a click into a zone or out to its
-- parent, and the map stays there
function MP.MapChanged()
  if not MP.going then MP.follow = false end
  MP.Update()
end

-- the zones in a map that have art of their own, by name: a continent's on the world map, a zone's on a continent
function MP.Children(mapID)
  local out = {}
  if not (C_Map and C_Map.GetMapChildrenInfo) then return out end
  local ok, kids = pcall(C_Map.GetMapChildrenInfo, mapID)
  for _, k in ipairs(ok and type(kids) == "table" and kids or {}) do
    local id = QB.Plain(k.mapID)
    if hasArt(id) and (QB.Plain(k.mapType) == CONTINENT or QB.QuestMap.Draws(id)) then out[#out + 1] = { id = id, name = QB.Plain(k.name) or "?" } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- /qb map <name>: the zone of that name, or the shortest that has it in its name
function MP.Find(text)
  text = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local best, bestName
  for id, name in pairs(QB.Data.MAPNAME or {}) do
    local n = name:lower()
    if n == text then return id end
    if text ~= "" and n:find(text, 1, true) and (not bestName or #name < #bestName) then best, bestName = id, name end
  end
  return best
end

local function menuOK() return MenuUtil and MenuUtil.CreateContextMenu and true or false end

-- a crumb's menu: the zones in it
function MP.ChildMenu(owner, mapID)
  local kids = MP.Children(mapID)
  if #kids == 0 or not menuOK() then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    for _, k in ipairs(kids) do root:CreateButton(k.name, function() MP.Go(k.id, "user") end) end
  end)
end

-- the journal's dungeons whose entrance is on this map, or on a continent in one of its zones, by level
function MP.Dungeons(mapID)
  local out = {}
  for _, c in ipairs(QB.DMap.List()) do
    local e = c.entrance
    local parent = e and info(e.m)
    if e and (e.m == mapID or (parent and QB.Plain(parent.parentMapID) == mapID)) then out[#out + 1] = c end
  end
  return out
end

-- the Dungeons button: one picked opens in the Dungeon Journal
function MP.DungeonMenu(owner)
  local list = MP.Dungeons(shownMap())
  if #list == 0 or not menuOK() then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    for _, c in ipairs(list) do
      local lv = QB.DMap.Levels(c.key)
      root:CreateButton(lv[1] > 0 and string.format("%s  %d-%d", c.name, lv[1], lv[2]) or c.name, function() QB.DMap.Open(c) end)
    end
  end)
end

----------------------------------------------------------------------------
-- the page
----------------------------------------------------------------------------
local function tip(owner, title, about)
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(title, GOLD[1], GOLD[2], GOLD[3])
  GameTooltip:AddLine(about, 1, 1, 1, true)
  GameTooltip:Show()
end
local function untip() GameTooltip:Hide() end

-- a 24 px button with the game's icon, and its word in the tooltip
local function iconButton(parent, atlas, file, title, about)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  QB.Art(b.icon, atlas, file)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self) tip(self, title, self.about or about) end)
  b:SetScript("OnLeave", untip)
  return b
end

local function textWidth(t) return (t.GetUnboundedStringWidth or t.GetStringWidth)(t) or 0 end

-- a crumb: a click opens its map; on the map shown already, or with the right button, its zones
local function crumb(f, i)
  local b = QB.DMap.Pill(f.nav, "", 80)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" or self.last then MP.ChildMenu(self, self.mapID) else MP.Go(self.mapID, "user") end
  end)
  b:SetScript("OnEnter", function(self)
    tip(self, self.text:GetText(), self.last and "Click: the zones in it." or "Click: open it. Right-click: the zones in it.")
  end)
  b:SetScript("OnLeave", untip)
  f.crumbs[i] = b
  return b
end

local function separator(f, i)
  local s = QB.DMap.Text(f.nav, "GameFontNormal", 12, SOFT, SEP_W, "CENTER")
  s:SetText(">")
  f.seps[i] = s
  return s
end

local function buildPage(page)
  local DM, T = QB.DMap, QB.Data.TEX
  local f = CreateFrame("Frame", nil, page)
  f:SetAllPoints(page)
  -- the nav bar: crumbs from the left; Here, the dungeons and the game's map on the right
  f.nav = CreateFrame("Frame", nil, f)
  f.nav:SetPoint("TOPLEFT", 0, 0)
  f.nav:SetSize(MAP_W, NAV_H)
  f.crumbs, f.seps = {}, {}
  f.game = iconButton(f.nav, nil, T.sideMap, "Game's map", "The game's world map on your zone.")
  f.game:SetPoint("RIGHT", -4, 0)
  f.game:SetScript("OnClick", function() QB.UI.OpenMap() end)
  f.dungeons = iconButton(f.nav, "Dungeon", QB.QuestMap.ART.dungeon.file, "Dungeons", "The dungeons whose entrance is on this map.")
  f.dungeons:SetPoint("RIGHT", f.game, "LEFT", -4, 0)
  f.dungeons:SetScript("OnClick", function(self) MP.DungeonMenu(self) end)
  f.here = iconButton(f.nav, "Waypoint-MapPin-Tracked", T.mapPin, "Here", "Your zone; the map follows you again.")
  f.here:SetPoint("RIGHT", f.dungeons, "LEFT", -4, 0)
  f.here:SetScript("OnClick", function() MP.Here() end)
  -- the map in a frame of its own; until the canvas is built, a word on why
  f.map = DM.Panel(f, 0.9)
  f.map:SetPoint("TOPLEFT", 0, -(NAV_H + 4))
  f.map:SetSize(MAP_W, MAP_H)
  f.later = DM.Text(f.map, "GameFontNormal", 12, SOFT, MAP_W - 40, "CENTER")
  f.later:SetPoint("CENTER")
  -- under it, the zone and its levels
  f.strip = CreateFrame("Frame", nil, f)
  f.strip:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 0, -6)
  f.strip:SetSize(MAP_W, STRIP_H)
  f.zone = DM.Text(f.strip, "GameFontNormalLarge", 16, GOLD, 300)
  f.zone:SetPoint("TOPLEFT", 8, -6)
  f.levels = DM.Text(f.strip, "GameFontNormal", 12, INK, 300)
  f.levels:SetPoint("TOPLEFT", 8, -28)
  -- beside it, the zone's quests: a header for each kind with its count
  f.panel = DM.Panel(f, 0.6)
  f.panel:SetPoint("TOPLEFT", MAP_W + GAP, 0)
  f.panel:SetPoint("BOTTOMRIGHT", 0, 0)
  f.heads = {}
  for i, s in ipairs(SECTIONS) do
    local h = CreateFrame("Frame", nil, f.panel)
    h:SetSize(PANEL_W - 16, 22)
    h:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 26)
    h.caret = h:CreateTexture(nil, "ARTWORK")
    h.caret:SetSize(14, 14)
    h.caret:SetPoint("LEFT", 2, 0)
    QB.UI.Caret(h.caret, true)
    h.label = DM.Text(h, "GameFontNormal", 12, GOLD, PANEL_W - 90)
    h.label:SetPoint("LEFT", 22, 0)
    h.label:SetText(s.name)
    h.count = DM.Text(h, "GameFontNormal", 12, INK, 40, "RIGHT")
    h.count:SetPoint("RIGHT", -4, 0)
    f.heads[s.key] = h
  end
  f.empty = DM.Text(f.panel, "GameFontNormal", 12, SOFT, PANEL_W - 24, "CENTER")
  f.empty:SetPoint("TOP", 0, -24)
  return f
end

-- the canvas into the page's map frame (once it exists), over its border
function MP.Place()
  local f, canvas = MP.frame, MP.canvas
  f.later:SetShown(canvas == nil)
  f.later:SetText(QB.Pins.InCombat() and "Map after the fight" or "No map on this client")
  if not canvas or canvas:GetParent() == f.map then return end
  canvas:SetParent(f.map)
  canvas:ClearAllPoints()
  canvas:SetPoint("TOPLEFT", f.map, "TOPLEFT", 2, -2)
  canvas:SetSize(MAP_W - 4, MAP_H - 4)
  canvas:SetFrameLevel(f.map:GetFrameLevel() + 1)
  canvas:OnFrameSizeChanged()
end

-- the crumbs: the map shown and the maps it lies in, the outermost first
function MP.Crumbs()
  local f = MP.frame
  local chain, id = {}, shownMap()
  for _ = 1, 6 do
    local i = info(id)
    if not i then break end
    table.insert(chain, 1, { id = id, name = QB.Plain(i.name) or "?" })
    id = QB.Plain(i.parentMapID)
    if type(id) ~= "number" or id <= 0 then break end
  end
  local x = 4
  for i, c in ipairs(chain) do
    local b = f.crumbs[i] or crumb(f, i)
    b.mapID, b.last = c.id, i == #chain
    b.text:SetText(c.name)
    local w = math.min(CRUMB_MAX, math.floor(textWidth(b.text) + 20))
    b:SetWidth(w)
    b.text:SetWidth(w - 8)
    b:ClearAllPoints()
    b:SetPoint("LEFT", f.nav, "LEFT", x, 0)
    b:SetOn(b.last)
    b:Show()
    x = x + w
    if not b.last then
      local s = f.seps[i] or separator(f, i)
      s:ClearAllPoints()
      s:SetPoint("LEFT", f.nav, "LEFT", x, 0)
      s:Show()
      x = x + SEP_W
    end
  end
  for i = #chain + 1, #f.crumbs do f.crumbs[i]:Hide() end
  for i = math.max(#chain, 1), #f.seps do f.seps[i]:Hide() end
end

-- under the map: the zone's name and the levels the game gives it
function MP.Strip()
  local f, m = MP.frame, shownMap()
  local i = info(m)
  f.zone:SetText(i and QB.Plain(i.name) or "")
  local ok, lo, hi = false, nil, nil
  if m and C_Map and C_Map.GetMapLevels then ok, lo, hi = pcall(C_Map.GetMapLevels, m) end
  lo, hi = ok and QB.Plain(lo), ok and QB.Plain(hi)
  local known = type(lo) == "number" and type(hi) == "number" and lo > 0
  f.levels:SetText(known and (lo == hi and ("LV " .. lo) or string.format("LV %d-%d", lo, hi)) or "")
end

-- beside the map: how many of the zone's quests are ready to hand in, in your log and to pick up; a continent asks
-- for a zone
function MP.FillPanel()
  local f, m = MP.frame, shownMap()
  local zone = QB.QuestMap.Draws(m)
  local lists = {}
  if zone then lists.ready, lists.log, lists.pickup = QB.QuestMap.ZoneQuests(m) end
  local any = zone and (#lists.ready + #lists.log + #lists.pickup) > 0
  for _, s in ipairs(SECTIONS) do
    local h = f.heads[s.key]
    h:SetShown(any)
    h.count:SetText(any and tostring(#lists[s.key]) or "")
  end
  f.empty:SetShown(not any)
  f.empty:SetText(zone and "No quests here" or "Pick a zone")
end

-- everything about the map shown
function MP.Update()
  local f = MP.frame
  if not f then return end
  MP.Crumbs()
  MP.Strip()
  MP.FillPanel()
  local none = #MP.Dungeons(shownMap()) == 0
  f.dungeons.icon:SetDesaturated(none)
  f.dungeons.about = none and "No dungeon entrance on this map." or nil
end

-- the page of the QuestBank window (UI.lua): built the first time it shows
function MP.Attach(page)
  MP.frame = MP.frame or buildPage(page)
  MP.Place()
  return MP.frame
end

-- the page's refresh: back to your zone while the map follows you, then the bar, the strip and the panel
function MP.Refresh()
  if not MP.frame then return end
  MP.Place()
  if MP.follow then MP.Go(playerMap(), "follow") end
  MP.Update()
end
