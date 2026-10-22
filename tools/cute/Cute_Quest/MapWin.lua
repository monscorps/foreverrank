-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Map window (M, CuteMapFrame, the Map module's: sub-project F). QuestBank's map canvas (MapPage.lua, built at login
-- out of combat) in a window of Cute's one builder: the header (the title, "Game's map", the cog, the close), under it
-- the crumbs (Azeroth > Eastern Kingdoms > Redridge Mountains), Here and each layer's switch with its game icon and
-- count; the canvas on the left; our list on the right, 320 px (260 at the window's smallest). The canvas does what the
-- game's map does (MapPage.lua under the Bridge's QB.mapWindow): the wheel zooms smoothly and goes through zones, a drag
-- pans and stops at the zone's edge, a click enters a zone, a right-click goes up, Ctrl-click puts a spot on the arrow;
-- and four of the game's own providers draw here as on the world map: your corpse, the area points of interest, the map
-- links (the doors and portals between maps) and the graveyards while you are dead. The list: the zone's name and
-- levels, then Ready to hand in, In your log, To pick up (by XP a minute), a two-line row a quest with its objectives or
-- whom it comes from, then Finds here; a row hovered lights its pins, a pin hovered lights its row and scrolls it into
-- view; a click reads the quest (Reader.lua), Back returns. All finds: every find you can see, by zone, yours first.
-- Not a UI panel: it opens and closes in a fight; Esc closes it.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local MW = {}
QB.MapWin = MW

local W, H, MIN_W, MIN_H = 1120, 640, 860, 500
local LIST_W, LIST_NARROW = 320, 260
local DOT = " \194\183 "
local BOOK = 133741 -- (INV_Misc_Book_09: the Finds layer's and the Finds list's icon)
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function callable(name) return type(_G[name]) == "function" end
local function inCombat() return callable("InCombatLockdown") and plain(InCombatLockdown()) == true end

-- the window's place among Cute's (the core's one builder, UI.lua's SPEC): its size, its smallest, its row under the
-- header (the crumbs and the layers: MW.DrawRow in place of the tabs), the page it opens on, its cog's Settings section
local SPEC = Cute.Window and Cute.Window("quests") and Cute.Window("quests").SPEC
if type(SPEC) == "table" and not SPEC.map then
  SPEC.map = { name = "CuteMapFrame", title = "Map", w = W, h = H, minW = MIN_W, minH = MIN_H, tabs = true, foot = false, home = "map", cog = "map" }
end

-- QuestBank loaded beside Cute (this copy sleeps): its own Map page shows its map
local function engineMap() return (not QB.dormant) and E and E.MapPage or nil end
local tickFailed = false -- (the map's frame tick failed once this session: said once, MW's box below)

----------------------------------------------------------------------------
-- the four of the game's own providers the world map has and QuestBank's page did not (Blizzard_WorldMap.lua:213,
-- 229-231): your corpse, the area points of interest, the map links, the graveyards. Each makes its pins as it draws
-- (AcquirePin, whose SetPassThroughButtons is protected and restricted in a fight: SimpleScriptRegionAPIDocumentation
-- .lua:665-669), so in a fight none draws: the pins of the map drawn before stay, another map's hide, and each draws when
-- the fight ends. The area points read the client (C_AreaPoiInfo) in place of GetAreaPOIsForPlayerByMapIDCached, whose
-- cache the world map reads (SharedMapPoiTemplates.lua:409), and carry no widget sets (an area point's icon and tooltip
-- widgets register with the game's widget manager); a map link to a map without art is left out (its right-click would
-- open it, and the canvas reads a map's first art layer unchecked)
----------------------------------------------------------------------------
local later = {}
local function pinsHeld() return E.Pins and E.Pins.InCombat and E.Pins.InCombat() or inCombat() end
local function mapOf(dp) local map = dp:GetMap(); return map and plain(map:GetMapID()) or nil end
local function deferred(mixin, own)
  local dp = CreateFromMixins(mixin, own or {})
  local draw = dp.RefreshAllData
  dp.RefreshAllData = function(self, fromOnShow)
    if pinsHeld() then
      later[self] = true
      if MW.events then MW.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
      if mapOf(self) ~= self.cuteFor then pcall(self.RemoveAllData, self) end
      return
    end
    later[self] = nil
    self.cuteFor = mapOf(self)
    return draw(self, fromOnShow)
  end
  return dp
end
local AreaPoints = {
  RefreshAllData = function(self)
    self:RemoveAllData()
    local map = self:GetMap()
    local m = mapOf(self)
    local A = C_AreaPoiInfo
    if type(m) ~= "number" or not (A and A.GetAreaPOIForMap and A.GetAreaPOIInfo) then return end
    local ok, ids = pcall(A.GetAreaPOIForMap, m)
    for _, id in ipairs(ok and type(plain(ids)) == "table" and ids or {}) do
      id = plain(id)
      local okI, poi = pcall(A.GetAreaPOIInfo, m, id)
      if type(id) == "number" and okI and type(plain(poi)) == "table" then
        poi.dataProvider, poi.iconWidgetSet, poi.tooltipWidgetSet = self, nil, nil
        map:AcquirePin(self:GetPinTemplate(), poi)
      end
    end
  end,
}
local MapLinks = {
  RefreshAllData = function(self)
    self:RemoveAllData()
    local map = self:GetMap()
    local m = mapOf(self)
    if type(m) ~= "number" or not (C_Map and C_Map.GetMapLinksForMap) then return end
    local MP = engineMap()
    local ok, links = pcall(C_Map.GetMapLinksForMap, m)
    for _, link in ipairs(ok and type(plain(links)) == "table" and links or {}) do
      local to = type(link) == "table" and plain(link.linkedUiMapID)
      if type(to) == "number" and MP and MP.HasArt(to) then map:AcquirePin("MapLinkPinTemplate", link) end
    end
  end,
}
local PROVIDERS = { { "DeathMapDataProviderMixin" }, { "AreaPOIDataProviderMixin", AreaPoints }, { "MapLinkDataProviderMixin", MapLinks },
  { "SelectableGraveyardDataProviderMixin" } }
-- added once, to the canvas the window shows (out of combat or in: adding draws nothing)
function MW.Providers(canvas)
  if MW.added or not (canvas and CreateFromMixins) then return end
  MW.added = {}
  for _, p in ipairs(PROVIDERS) do
    local mixin = _G[p[1]]
    if type(mixin) == "table" then
      local dp = deferred(mixin, p[2])
      dp.cuteName = p[1]
      canvas:AddDataProvider(dp)
      MW.added[#MW.added + 1] = dp
    end
  end
end
-- the fight over (or the game no longer holding addons back): the providers that waited draw, if the map shows
local function drawLater()
  if pinsHeld() then return end
  local MP = engineMap()
  local shown = MP and MP.canvas and MP.canvas:IsVisible()
  for dp in pairs(later) do
    later[dp] = nil
    if shown then dp:RefreshAllData() end
  end
end
-- your corpse and the graveyards come and go with your death: drawn again while the map shows
local function deathChanged()
  local MP = engineMap()
  if not (MP and MP.canvas and MP.canvas:IsVisible()) then return end
  for _, dp in ipairs(MW.added or {}) do
    if dp.cuteName == "DeathMapDataProviderMixin" or dp.cuteName == "SelectableGraveyardDataProviderMixin" then dp:RefreshAllData() end
  end
end
MW.events = CreateFrame("Frame")
MW.events:SetScript("OnEvent", Cute.Safe(function(self, event, _, state)
  if event == "PLAYER_REGEN_ENABLED" then
    pcall(self.UnregisterEvent, self, "PLAYER_REGEN_ENABLED")
    drawLater()
  elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
    local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
    if plain(state) == inactive then drawLater() end
  else
    deathChanged()
  end
end, "map window: the game's providers"))
for _, ev in ipairs({ "ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do pcall(MW.events.RegisterEvent, MW.events, ev) end

----------------------------------------------------------------------------
-- the row under the header: the crumbs, Here and the layers
----------------------------------------------------------------------------
local function info(m)
  if type(m) ~= "number" or not (C_Map and C_Map.GetMapInfo) then return nil end
  local ok, i = pcall(C_Map.GetMapInfo, m)
  return ok and type(i) == "table" and i or nil
end
local function shownMap()
  local MP = engineMap()
  return MP and MP.canvas and plain(MP.canvas:GetMapID()) or nil
end
local function playerMap()
  if not (MapUtil and MapUtil.GetDisplayableMapForPlayer) then return nil end
  local ok, m = pcall(MapUtil.GetDisplayableMapForPlayer)
  return ok and plain(m) or nil
end
local function tip(owner, title, about)
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(title, 1, 1, 1)
  if about then GameTooltip:AddLine(about, 0.85, 0.85, 0.85, true) end
  GameTooltip:Show()
end
-- the layers, as MapPage.lua's switches (its TOGGLES: the three of the quests, the route, the dungeons, the flight paths)
-- and the finds; each with the game's icon and how many there are on this map, a layer with none here not drawn
local FINDS = { key = "mapFinds", name = "Finds", file = BOOK, count = "finds" }
local function layers()
  local MP = engineMap()
  local out = {}
  for _, t in ipairs(MP and MP.TOGGLES or {}) do out[#out + 1] = t end
  out[#out + 1] = FINDS
  return out
end
local function layerOn(t)
  local MP = engineMap()
  if t == FINDS then return E:Settings().mapFinds ~= false end
  return MP and MP.LayerOn(t) or false
end
-- a layer's art: MapPage.lua's for its own (In your log's an objective's cursor under the kind marks, as its pins), the
-- book for the finds
local function artOf(t)
  local MP = engineMap()
  if MP and MP.ToggleArt and t ~= FINDS then return MP.ToggleArt(t) end
  return t.atlas, t.file
end
-- In your log's section head, as its switch: the quest disc's glyph, or the cursor its pins are under the kind marks
local function logIcon()
  local MP = engineMap()
  for _, t in ipairs(MP and MP.TOGGLES or {}) do
    if t.key == "mapObj" then
      local atlas, file = artOf(t)
      if atlas ~= t.atlas then return { art = { atlas, file } } end
    end
  end
  return { poi = "log" }
end
local function toggleLayer(t)
  local MP = engineMap()
  if not MP then return end
  if t == FINDS then
    local s = E:Settings()
    s.mapFinds = (s.mapFinds == false) and nil or false
    if MP.finds and MP.canvas and MP.canvas:IsVisible() then MP.finds:RefreshAllData() end
    Cute.Refresh()
    return
  end
  MP.ToggleLayer(t.key)
end
local function crumbButton(ui, i)
  local b = ui.Button(ui.tabRow, "", 80, 20)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", Cute.Safe(function(self, which)
    local MP = engineMap()
    if not MP then return end
    if which == "RightButton" or self.last or self.noArt then MP.ChildMenu(self, self.mapID) else MP.Go(self.mapID, "user") end
  end, "map window: a crumb"))
  b:SetScript("OnEnter", Cute.Safe(function(self)
    tip(self, self.label:GetText(), self.noArt and "No map art for it on this client. Click: the zones in it."
      or (self.last and "Click: the zones in it." or "Click: open it. Right-click: the zones in it."))
  end, "map window: a crumb"))
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ui.mapCrumbs[i] = b
  return b
end
local function layerButton(ui, i)
  local b = CreateFrame("Button", nil, ui.tabRow)
  b:SetSize(44, 22)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT", 4, 0)
  b.count = ui.Text(b, 11, ui.COLORS.INK, "LEFT")
  b.count:SetPoint("LEFT", 23, 0)
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  b:SetScript("OnClick", Cute.Safe(function(self) if self.t then toggleLayer(self.t) end end, "map window: a layer"))
  b:SetScript("OnEnter", Cute.Safe(function(self)
    if not self.t then return end
    tip(self, self.t.name, layerOn(self.t) and "On the map. Click: hide them." or "Hidden. Click: show them on the map.")
  end, "map window: a layer"))
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ui.mapLayers[i] = b
  return b
end
-- the row (the window's tab row: DrawTabs, which the builder calls before each draw of the page)
function MW.DrawRow(ui)
  local MP = engineMap()
  local row = ui.tabRow
  for _, b in pairs(ui.tabs or {}) do b:Hide() end -- (the Map module's own tab: the window has one page)
  ui.mapCrumbs, ui.mapLayers = ui.mapCrumbs or {}, ui.mapLayers or {}
  local K = ui.COLORS
  local rowW = (ui.frame:GetWidth() or W) - 16 - 14
  -- the layers on the right, with something on this map
  local m = shownMap()
  -- (the zone's quests read now: the row is drawn before the page, which reads them again for its list)
  local counts = (MP and m) and MP.Counts(m, MP.ZoneQuests(m)) or {}
  local x, n = 0, 0
  local list = layers()
  for i = #list, 1, -1 do
    local t = list[i]
    local c = counts[t.count] or 0
    if c > 0 then
      n = n + 1
      local b = ui.mapLayers[n] or layerButton(ui, n)
      b.t = t
      ui.Art(b.icon, artOf(t))
      b.count:SetText(tostring(c))
      local w = 23 + math.ceil(((b.count.GetUnboundedStringWidth or b.count.GetStringWidth)(b.count) or 0)) + 6
      b:SetWidth(w)
      local on = layerOn(t)
      b.icon:SetDesaturated(not on)
      b:SetAlpha(on and 1 or 0.45)
      b:ClearAllPoints()
      b:SetPoint("RIGHT", row, "RIGHT", -x, 0)
      b:Show()
      x = x + w + 2
    end
  end
  for i = n + 1, #ui.mapLayers do ui.mapLayers[i]:Hide() end
  -- Here, then the crumbs from the left: the map shown and the maps it lies in, the outermost first
  if not ui.mapHere then
    ui.mapHere = ui.Button(row, "Here", 54, 20)
    ui.mapHere:SetScript("OnClick", Cute.Safe(function() local P = engineMap(); if P then P.Here() end end, "map window: here"))
    ui.mapHere:SetScript("OnEnter", function(self) tip(self, "Here", "Your zone; the map follows you again.") end)
    ui.mapHere:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local chain, id = {}, m
  for _ = 1, 6 do
    local i = info(id)
    if not i then break end
    table.insert(chain, 1, { id = id, name = plain(i.name) or "?" })
    id = plain(i.parentMapID)
    if type(id) ~= "number" or id <= 0 then break end
  end
  local room = math.max(120, rowW - x - 8 - 54 - 8)
  local each = #chain > 0 and math.floor((room - (#chain - 1) * 4) / #chain) or room
  local cx = 0
  for i, c in ipairs(chain) do
    local b = ui.mapCrumbs[i] or crumbButton(ui, i)
    b.mapID, b.last, b.noArt = c.id, i == #chain, not (MP and MP.HasArt(c.id))
    b.label:SetText(c.name)
    local w = math.min(each, math.ceil(((b.label.GetUnboundedStringWidth or b.label.GetStringWidth)(b.label) or 0)) + 16)
    b:SetWidth(math.max(24, w))
    b:SetLabel(c.name)
    ui.Color(b.label, b.last and K.WHITE or (b.noArt and K.MUTE or K.INK))
    b:ClearAllPoints()
    b:SetPoint("LEFT", row, "LEFT", cx, 0)
    b:Show()
    cx = cx + math.max(24, w) + 4
  end
  for i = #chain + 1, #ui.mapCrumbs do ui.mapCrumbs[i]:Hide() end
  ui.mapHere:ClearAllPoints()
  ui.mapHere:SetPoint("LEFT", row, "LEFT", cx + 4, 0)
  ui.mapHere:SetShown(MP ~= nil)
end

----------------------------------------------------------------------------
-- the header's button to the game's own map: QuestBank's tested path (the Bridge's UI.OpenMap: OpenWorldMap, HideUIPanel),
-- out of combat; Cute's window steps aside for the game's
----------------------------------------------------------------------------
local function gameMap()
  if inCombat() or not (E and E.UI and E.UI.OpenMap) then return end
  local w = Cute.Window and Cute.Window("map")
  if E.UI.OpenMap() and w and w.frame then w.frame:Hide() end
end
local function gameButton(ui)
  local b = ui.Button(ui.head, "Game's map", 90, 20)
  local w = math.ceil(((b.label.GetUnboundedStringWidth or b.label.GetStringWidth)(b.label) or 0) + 20)
  b:SetWidth(w)
  b:SetPoint("RIGHT", -(ui.headRight or 30), 0)
  b:SetScript("OnClick", Cute.Safe(gameMap, "map window: the game's map"))
  b:SetScript("OnEnter", Cute.Safe(function(self)
    tip(self, "Game's map", inCombat() and "After combat." or "The game's own world map on your zone, with Cute's icons while \"Our icons on the game's map\" is on.")
  end, "map window: the game's map"))
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ui.mapGame = b
end

----------------------------------------------------------------------------
-- the list: a host of the scroll area's, drawn only where it shows (rows of two heights: a head 24, a quest 34)
----------------------------------------------------------------------------
local function rowOf(ui, host)
  local L = ui.Look
  local r = L.MakeRow(host)
  r:HookScript("OnEnter", function(self) local P = engineMap(); if P and self.mapKey then P.Hover(self.mapKey) end end)
  r:HookScript("OnLeave", function(self) local P = engineMap(); if P and self.mapKey and P.hover == self.mapKey then P.Hover(nil) end end)
  return r
end
-- the rows in view, from the list's tops (a scroll draws again only what comes into view)
local MARGIN = 120
local function render(ui)
  local v = ui.mapList
  if not v then return end
  local offset = ui.scroll.bar:GetValue() or 0
  local view = ui.scroll:View()
  local items, tops = v.items, v.tops
  local lo, hi = 1, #items
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if tops[mid] <= offset - MARGIN then lo = mid else hi = mid - 1 end
  end
  v.pool:Reset(); v.roundPool:Reset()
  for i = lo, #items do
    if tops[i] > offset + view + MARGIN then break end
    local it = items[i]
    local r = (it.round and v.roundPool or v.pool):Get()
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", v.host, "TOPLEFT", 0, -tops[i])
    local spec = it.spec
    spec.bg = (it.key ~= nil and it.key == ui.mapLit) and 0.06 or it.bg
    ui.Look.FillRow(r, spec, v.w)
    -- (a narrow two-line row's second line ends before its value, which stands in the row's middle: Look's FillRow
    -- gives it the whole width when the who column goes)
    if spec.kind == "two" and spec.val and spec.line2 then
      local x = spec.lvl and 56 or (spec.icon and 34 or 10)
      local room = v.w - x - 8 - (spec.rew and 24 or 0) - (spec.valW or 56) - 8
      r.line2:SetWidth(room)
      ui.FitText(r.line2, spec.line2, room - 2)
    end
    -- (a head's word on its right as wide as it is, the head's name the rest: Look keeps 200 px for it, a wide list's)
    if spec.kind == "head" and spec.who then
      local ww = math.min(120, math.ceil(((r.who.GetUnboundedStringWidth or r.who.GetStringWidth)(r.who) or 0)) + 4)
      r.who:SetWidth(ww)
      local x = spec.icon and 30 or 10
      local room = v.w - x - 8 - ww - 8
      r.name:SetWidth(room)
      ui.FitText(r.name, spec.name, room - 2)
    end
    r.mapKey = it.key
  end
  v.pool:HideRest(); v.roundPool:HideRest()
end
-- a list of items { spec (a Look row), key (a quest's id or a find's key), bg } into the scroll area. The rows whose icon
-- is cut round (the finds) have widgets of their own: a slot's round mask is put on once and never taken off
local function setList(ui, scroll, items)
  local host = Cute.Host(ui, "mapList")
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", 0, 0)
  local w = scroll:Width()
  local v = ui.mapList or {}
  ui.mapList = v
  if v.hostFrame ~= host then
    v.host, v.hostFrame = host, host
    v.pool = ui.Pool(host, function(parent) return rowOf(ui, parent) end)
    v.roundPool = ui.Pool(host, function(parent) return rowOf(ui, parent) end)
  end
  v.items, v.tops, v.w = items, {}, w
  local L, y = ui.Look, 0
  for i, it in ipairs(items) do
    v.tops[i] = y
    it.bg, it.round = it.spec.bg, (it.spec.icon and it.spec.icon.round) and true or nil
    y = y + (it.spec.h or L.H[it.spec.kind or "row"] or L.H.row)
  end
  host:SetSize(w, math.max(1, y))
  scroll:SetContentHeight(y + 8)
  ui.virtual = function() render(ui) end
end
-- a row lit (a pin hovered or clicked on the map: its row comes into view)
function MW.Light(ui, key, show)
  if ui.mapLit == key then return end
  ui.mapLit = key
  local v = ui.mapList
  if not (v and ui.frame and ui.frame:IsShown()) then return end
  -- (the quest to read in the list's place: the row is lit when the list comes back, and the reader's scroll is its own)
  if QB.Reader.Open(ui) or not (v.host and v.host:IsShown()) then return end
  if key ~= nil and show then
    for i, it in ipairs(v.items) do
      if it.key == key then
        local view = ui.scroll:View()
        local at = ui.scroll.bar:GetValue() or 0
        local top = v.tops[i]
        if top < at or top + 34 > at + view then
          local _, maxv = ui.scroll.bar:GetMinMaxValues()
          ui.scroll.bar:SetValue(math.max(0, math.min(maxv or 0, top - (view - 34) / 2)))
        end
        break
      end
    end
  end
  render(ui)
end

-- where an NPC stands, in words: the town within 200 yards (Travel.lua TV.TownNear), else its zone
local function placeOf(npc)
  if not npc then return nil end
  local n = npc.idx and E.Data.NPC[npc.idx]
  local town = n and E.Travel and E.Travel.TownNear and E.Travel.TownNear(n[5], n[6], n[7], 200)
  return town or npc.place or (E.Data.MAPNAME and E.Data.MAPNAME[npc.m]) or nil
end
-- a held quest's objectives in a line, each its cursor at 12 px and "Kobold Vermin 3/8"; a finished one the ready check
-- and the muted grey (as the Quests tab's rows)
local MUTE = "|cff858585"
local function objectivesLine(e, L)
  local parts = {}
  for slot, o in ipairs(e.objectives or {}) do
    local text = plain(o.text)
    local name, have, need
    if E.Guide.ParseLine then name, have, need = E.Guide.ParseLine(text) else name = text end
    if name and name ~= "" then
      local words = (have and need) and string.format("%s %d/%d", name, have, need) or name
      if plain(o.done) == true then parts[#parts + 1] = L.Inline("ready", 12) .. " " .. MUTE .. words .. "|r"
      else parts[#parts + 1] = L.Inline(QB.ObjKind(e.id, slot, text), 12) .. " " .. words end
    end
  end
  return #parts > 0 and table.concat(parts, "   ") or nil
end
-- a quest as a row (pattern A, two lines, the narrow form: no who column)
local function questRow(ui, it, K, L)
  local q, st = it.q, it.st
  local e = E.state.log[q.id]
  local icon
  if e then icon = { poi = e.complete and "ready" or "log" } else icon = { art = q.repeatable and "repeatable" or "accept" } end
  if E.QuestMap and E.QuestMap.Grey and E.QuestMap.Grey(q, E.state.level) then icon.desat = true end
  local line2
  if e and e.complete then
    local n = q.turn
    line2 = n and n.n and ("to " .. n.n .. ((placeOf(n) and (DOT .. placeOf(n))) or "")) or "ready to hand in"
  elseif e then
    line2 = objectivesLine(e, L) or "in your log"
  else
    local n = q.give
    line2 = (n and n.n and ("from " .. n.n .. ((placeOf(n) and (DOT .. placeOf(n))) or ""))) or "who gives it is not known yet"
  end
  local target = E.Target and E.Target.cur and E.Target.cur.qid == q.id
  return { kind = "two", bar = K.QUEST, icon = icon, lvl = tostring(q.lvl or "") .. (q.group and "+" or ""), lvlC = L.LevelColor(q.lvl),
    name = q.name, nameC = target and K.WHITE or nil, bg = target and 0.06 or nil, line2 = line2,
    val = it.xp and it.xp > 0 and E.Comma(math.floor(it.xp + 0.5)) or nil,
    fn = function(_, which) QB.RowClick(ui, q, st, which) end,
    tip = function(t) E.UI.QuestTooltip(t, q, st, it.xp) end }
end
-- XP a minute, by quest, as the Quests tab weighs places (Lists.lua UI.PlaceGroups: the engine keeps its lists a second)
local function rates()
  local out = {}
  if not (E.UI and E.UI.PlaceGroups) then return out end
  local ok, order = pcall(E.UI.PlaceGroups)
  for _, g in ipairs(ok and type(order) == "table" and order or {}) do
    for _, it in ipairs(g.quests or {}) do if it.rate and it.rate == it.rate and it.rate < math.huge then out[it.id] = it.rate end end
  end
  return out
end
-- a find as a row: its icon round, its name, its kind, how and who on line 2, "new" while QuestBank's data lacks it
local function findRow(ui, f, K, zone)
  return { kind = "two", bar = K.NEW, icon = { art = { nil, f.icon }, crop = true, round = true }, name = f.name or f.kindWord,
    line2 = f.kindWord .. DOT .. f.how .. DOT .. f.who .. (zone and (DOT .. zone) or ""), val = f.new and "new" or nil, valC = K.NEW,
    fn = function() MW.ShowFind(ui, f) end,
    tip = function(t)
      t:AddLine(f.name or f.kindWord, 1, 1, 1)
      t:AddLine(f.how .. DOT .. f.who, 0.85, 0.85, 0.85)
      if f.new then t:AddLine("Seen in play by you", 0.47, 0.69, 1) end
      t:AddLine("Click: the map goes to it.", 0.5, 0.5, 0.5)
    end }
end
-- (sub-project G) the finds a list shows: yours, the data's and the guild's once two agree (a single guild mate's, dim, and
-- a rare a guild mate sees now are the map's alone)
local function listed(list)
  local out = {}
  for _, f in ipairs(list) do if not (f.dim or f.ping) then out[#out + 1] = f end end
  return out
end
-- the map to show for map m: m itself with its art, else the nearest map above it with art (the canvas shows no map
-- without art, and MP.Go says so in chat), and a spot of m (fractions) where it lies on that map (Pins.lua P.Project:
-- nil off it). Nil where no map up to the world has art
local function withArt(MP, m, x, y)
  local id = m
  for _ = 1, 6 do
    if MP.HasArt(id) then
      if id ~= m and x then x, y = E.Pins.Project({ m = m, x = x * 100, y = y * 100 }, id) end
      return id, x, y
    end
    local i = info(id)
    id = i and plain(i.parentMapID)
    if type(id) ~= "number" or id <= 0 then return nil end
  end
  return nil
end
-- a find shown: its zone on the map (or the map above it with art), panned to its first spot where that lies on it, its
-- pins lit
function MW.ShowFind(ui, f)
  local MP = engineMap()
  if not (MP and f) then return end
  local s = f.spots and f.spots[1]
  local m, x, y = withArt(MP, f.m, s and s[1], s and s[2])
  if not m then return end
  if shownMap() ~= m then MP.Go(m, "user") end
  if x and y and MP.canvas then pcall(MP.canvas.PanTo, MP.canvas, x, y) end
  MP.Hover(f.fkey)
  MW.Light(ui, f.fkey, false)
end

-- the band's pieces of the map's own (a kit: shown by the draw that uses it, the band's shared pools left as the reader
-- has them): the zone's head, and the Finds list's Back, count and words
local function kit(ui)
  return ui:Kit("map", function(k)
    k.name = ui.Text(k, 15, ui.COLORS.WHITE, "LEFT")
    k.name:SetPoint("TOPLEFT", 4, -6)
    k.levels = ui.Text(k, 12, ui.COLORS.DIM, "LEFT")
    k.count = ui.Text(k, 11, ui.COLORS.DIM, "RIGHT")
    k.count:SetPoint("TOPRIGHT", -4, -9)
    k.count:SetWidth(90)
    k.note = ui.Text(k, 12, ui.COLORS.DIM, "LEFT")
    k.note:SetPoint("TOPLEFT", 4, -30)
    k.note:SetWordWrap(true)
    k.back = ui.Button(k, "Back", 70, 20)
    k.back:SetPoint("TOPLEFT", 0, -3)
  end)
end
-- the zone's head in the band: its name, its levels in their colours, how many quests
local function head(ui, m, n)
  local L = ui.Look
  local k = kit(ui)
  k.back:Hide(); k.note:Hide()
  local i = info(m)
  local w = ui.scroll:Width()
  k.name:Show()
  ui.FitText(k.name, i and plain(i.name) or "", w - 150)
  local nw = math.min(w - 150, math.ceil(((k.name.GetUnboundedStringWidth or k.name.GetStringWidth)(k.name) or 0)))
  local ok, lo, hi = false, nil, nil
  if C_Map and C_Map.GetMapLevels then ok, lo, hi = pcall(C_Map.GetMapLevels, m) end
  lo, hi = ok and plain(lo), ok and plain(hi)
  if type(lo) == "number" and type(hi) == "number" and lo > 0 then
    k.levels:ClearAllPoints(); k.levels:SetPoint("TOPLEFT", 4 + nw + 8, -9)
    k.levels:SetWidth(60)
    k.levels:SetText(lo == hi and (ui.Hex(L.LevelColor(lo)) .. lo .. "|r") or (ui.Hex(L.LevelColor(lo)) .. lo .. "|r-" .. ui.Hex(L.LevelColor(hi)) .. hi .. "|r"))
    k.levels:Show()
  else
    k.levels:Hide()
  end
  k.count:SetText(n and (n == 1 and "1 quest" or (n .. " quests")) or "")
  k.count:SetShown(n ~= nil)
  k:SetHeight(30)
  ui:SetBand(30)
end

-- the zone's list: ready, in your log, to pick up, then the finds here; a continent: its zones with quests for you
local function zoneList(ui, scroll, m)
  local MP = engineMap()
  local K, L = ui.COLORS, ui.Look
  local items = {}
  local function add(spec, key) items[#items + 1] = { spec = spec, key = key } end
  if MP.IsContinent(m) then
    head(ui, m, nil)
    local zones = {}
    for _, z in ipairs(MP.ZonesOf(m)) do
      local zl = MP.ZoneQuests(z)
      local n = #zl.ready + #zl.log + #zl.pickup
      if n > 0 then zones[#zones + 1] = { z = z, zl = zl, n = n, name = (info(z) and plain(info(z).name)) or "?" } end
    end
    table.sort(zones, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    add({ kind = "head", bar = K.QUEST, icon = { art = "accept" }, name = "Zones with quests for you", who = tostring(#zones) })
    for _, zz in ipairs(zones) do
      local parts = {}
      if #zz.zl.ready > 0 then parts[#parts + 1] = #zz.zl.ready .. " ready" end
      if #zz.zl.log > 0 then parts[#parts + 1] = #zz.zl.log .. " in your log" end
      if #zz.zl.pickup > 0 then parts[#parts + 1] = #zz.zl.pickup .. " to pick up" end
      -- (a zone without art on this client goes nowhere, as its crumb: the canvas shows no map without art)
      local art = MP.HasArt(zz.z)
      add({ kind = "two", bar = K.QUEST, icon = { art = { nil, 134269 }, crop = true, desat = not art }, name = zz.name, line2 = table.concat(parts, DOT),
        fn = art and function() MP.Go(zz.z, "user") end or nil,
        tip = function(t) t:AddLine(zz.name, 1, 1, 1); t:AddLine(art and "Click: open it." or "No map art for it on this client.", 0.5, 0.5, 0.5) end })
    end
    if #zones == 0 then add({ kind = "note", x = 10, name = "No quests known here at your level." }) end
    setList(ui, scroll, items)
    return
  end
  -- (the zone's quests read now: the quest log changes between two map changes)
  local lists = MP.ZoneQuests(m)
  MP.lists, MP.zone = lists, true
  local n = #lists.ready + #lists.log + #lists.pickup
  head(ui, m, n)
  local rate = rates()
  local pickup = {}
  for _, it in ipairs(lists.pickup) do pickup[#pickup + 1] = it end
  table.sort(pickup, function(a, b)
    local ra, rb = rate[a.q.id] or -1, rate[b.q.id] or -1
    if ra ~= rb then return ra > rb end
    if a.xp ~= b.xp then return a.xp > b.xp end
    return a.q.name < b.q.name
  end)
  local sections = {
    { name = "Ready to hand in", icon = { poi = "ready" }, list = lists.ready, whoC = K.GOOD },
    { name = "In your log", icon = logIcon(), list = lists.log },
    { name = "To pick up", icon = { art = "accept" }, list = pickup },
  }
  for _, s in ipairs(sections) do
    if #s.list > 0 then
      add({ kind = "head", bar = K.QUEST, icon = s.icon, name = s.name, who = tostring(#s.list), whoC = s.whoC })
      for _, it in ipairs(s.list) do add(questRow(ui, it, K, L), it.q.id) end
    end
  end
  if n == 0 then add({ kind = "note", x = 10, name = "No quests known here at your level." }) end
  -- the finds here, and the way to all of them
  local finds = E:Settings().mapFinds ~= false and listed(MP.Finds(m)) or {}
  add({ kind = "head", bar = K.NEW, icon = { art = { nil, BOOK }, crop = true }, name = "Finds here", who = "All finds", whoC = K.INK,
    fn = function() MW.ShowFinds(ui) end,
    tip = function(t) t:AddLine("All finds", 1, 1, 1); t:AddLine("Click: every find you can see, by zone.", 0.85, 0.85, 0.85, true) end })
  for _, f in ipairs(finds) do add(findRow(ui, f, K), f.fkey) end
  if #finds == 0 then add({ kind = "note", x = 10, name = "Nothing found here yet." }) end
  setList(ui, scroll, items)
end

-- the Finds list: every find you can see, by zone, this zone first, then the nearest
local function zoneYards(m)
  local M = E.Model
  local me = E.API and E.API.WorldPosition and E.API.WorldPosition()
  local w = M and M.World and M.World(m, 50, 50)
  if not (me and w and me.c == w.c) then return math.huge end
  return math.sqrt((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2)
end
-- the quest being read ends (the footer, /cute finds or Show finds opened the list over it), its pins let go
local function endReading(ui)
  local r = ui.reading
  if not r then return nil end
  ui.reading = nil
  local MP = engineMap()
  if MP and MP.focus then MP.Focus(MP.focus) end
  return r
end
function MW.ShowFinds(ui)
  local r = endReading(ui)
  ui.mapFinds = true
  ui.mapFindsScroll = r and r.scroll or (ui.scroll.bar:GetValue() or 0)
  ui.scrollTo = 0
  ui:Draw()
end
local function findsList(ui, scroll)
  local MP = engineMap()
  local K = ui.COLORS
  local here = shownMap()
  local zones, total = {}, 0
  for _, m in ipairs(MP.FindMaps()) do
    local list = listed(MP.Finds(m))
    if #list > 0 then
      zones[#zones + 1] = { m = m, list = list, d = m == here and -1 or zoneYards(m), name = (info(m) and plain(info(m).name)) or (E.Data.MAPNAME and E.Data.MAPNAME[m]) or "?" }
      total = total + #list
    end
  end
  table.sort(zones, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.name < b.name end)
  -- the band: Back, how many, and what the list holds
  local k = kit(ui)
  k.name:Hide(); k.levels:Hide()
  k.back:Show()
  k.back:SetScript("OnClick", Cute.Safe(function() ui.mapFinds = nil; ui.scrollTo = ui.mapFindsScroll; ui:Draw() end, "map window: back"))
  k.count:SetText(total == 1 and "1 find" or (total .. " finds"))
  k.count:Show()
  local w = scroll:Width()
  k.note:SetWidth(w - 8)
  k.note:SetText("Yours, the guild's once two agree, and what players' games and guides gave foreverrank.com. Never a book's text or where a key leads.")
  k.note:Show()
  local nh = math.ceil(k.note:GetStringHeight() or 28)
  k:SetHeight(30 + nh + 6)
  ui:SetBand(30 + nh + 6)
  local items = {}
  for _, z in ipairs(zones) do
    items[#items + 1] = { spec = { kind = "head", bar = K.NEW, name = z.name, who = tostring(#z.list) } }
    for _, f in ipairs(z.list) do items[#items + 1] = { spec = findRow(ui, f, K), key = f.fkey } end
  end
  if total == 0 then items[1] = { spec = { kind = "note", x = 10, name = "Nothing found yet." } } end
  setList(ui, scroll, items)
end

----------------------------------------------------------------------------
-- the page
----------------------------------------------------------------------------
-- the canvas's box on the left of the content, the list's room on the right (the band and the scroll area start after
-- the box: UI:SetInset); "Showing ... on the arrow" over the canvas's foot for a moment after a Ctrl-click
local function boxOf(ui)
  local b = ui.mapBox
  if b then return b end
  b = CreateFrame("Frame", nil, ui.content, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetPoint("TOPLEFT", 8, -8)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(0, 0, 0, 1)
    b:SetBackdropBorderColor(0, 0, 0, 1)
  end
  b.inner = CreateFrame("Frame", nil, b)
  b.inner:SetPoint("TOPLEFT", 1, -1)
  b.later = ui.Text(b, 12, ui.COLORS.DIM, "CENTER")
  b.later:SetPoint("CENTER")
  b.said = CreateFrame("Frame", nil, b)
  b.said:SetPoint("BOTTOMLEFT", 8, 8)
  b.said:SetHeight(20)
  b.said:SetFrameLevel((b:GetFrameLevel() or 1) + 40)
  b.said.bg = b.said:CreateTexture(nil, "BACKGROUND")
  b.said.bg:SetAllPoints()
  b.said.bg:SetColorTexture(0.035, 0.035, 0.035, 0.85)
  b.said.text = ui.Text(b.said, 12, ui.COLORS.INK, "LEFT")
  b.said.text:SetPoint("LEFT", 6, 0)
  b.said:Hide()
  -- (while it shows: the canvas's route strokes, the arrow's step, a lit row's fade: MapPage.lua MP.Tick). Every frame, so
  -- through pcall, which makes nothing (the launch audit: Cute.Safe made a table and a closure a frame, 15 to 35 KB a
  -- second of garbage while M was open); an error goes to Cute's list once
  b:SetScript("OnUpdate", function(_, dt)
    local MP = engineMap()
    if not (MP and MP.canvas) then return end
    local ok, err = pcall(MP.Tick, dt or 0)
    if not ok and not tickFailed then
      tickFailed = true
      Cute.Safe(function() error(err, 0) end, "map window: tick")()
    end
  end)
  ui.mapBox = b
  return b
end
function MW.Say(ui, text)
  local b = ui.mapBox
  if not b then return end
  b.said.text:SetText(text)
  local w = math.ceil(((b.said.text.GetUnboundedStringWidth or b.said.text.GetStringWidth)(b.said.text) or 0)) + 12
  b.said:SetWidth(math.min(w, (b:GetWidth() or 400) - 16))
  ui.FitText(b.said.text, text, (b:GetWidth() or 400) - 28)
  b.said:Show()
  local mark = (MW.saidN or 0) + 1
  MW.saidN = mark
  C_Timer.After(3, Cute.Safe(function() if MW.saidN == mark then b.said:Hide() end end, "map window: said"))
end
local function hooksFor(ui)
  return { strata = "HIGH",
    -- (the map shown changed, or its quests: drawn now for a new map, else within the second; never inside a draw)
    Changed = function(m) if ui.drawing then return end if m ~= ui.mapFor then ui:Draw() else ui:Refresh() end end,
    Route = function() if not ui.drawing then ui:Refresh() end end,
    Reveal = function(ids) MW.Light(ui, type(ids) == "table" and ids[1] or nil, true) end,
    Hovered = function(id) MW.Light(ui, id, true) end,
    Showing = function(text) MW.Say(ui, "Showing " .. text .. " on the arrow") end,
  }
end
-- the room: the list 320 px wide (260 at the window's smallest), the map the rest, both under the window's row. (The
-- content panel: the window less 8 px on the left and 9 on the right, UI.lua's builder; the scroll area 8 in from the
-- inset and 18 from the right)
local function insetOf(ui)
  local fw = ui.frame:GetWidth() or W
  return fw - 17 - 26 - (fw >= 1000 and LIST_W or LIST_NARROW)
end
-- the map's box runs to the window's foot whatever the finds footer does, which stands under the list alone (the canvas
-- resized resets its zoom: MapCanvas_ScrollContainerMixin.lua, OnCanvasSizeChanged)
local function layout(ui)
  local MP = engineMap()
  local fh = ui.frame:GetHeight() or H
  local inset = insetOf(ui)
  ui:SetInset(inset)
  local b = boxOf(ui)
  local bw, bh = inset - 12, fh - 73 - 14
  b:SetSize(bw, bh)
  b.inner:SetSize(bw - 2, bh - 2)
  b:Show()
  local canvas = MP and MP.canvas
  b.later:SetShown(canvas == nil)
  b.later:SetText(inCombat() and "The map is ready after combat." or "No map on this client.")
  if not canvas then return false end
  if MP.host == nil or MP.host.frame ~= b.inner then
    MW.Providers(canvas)
    MP.Host(b.inner, hooksFor(ui))
  else
    MP.Fit()
  end
  return true
end

-- the zones M showed, the newest first (four at most: the menu leaves your own out and names three; this session's)
MW.recent = {}
local function remember(m)
  if not (E.QuestMap and E.QuestMap.Draws(m)) then return end
  local r = MW.recent
  for i = #r, 1, -1 do if r[i] == m then table.remove(r, i) end end
  table.insert(r, 1, m)
  while #r > 4 do r[#r] = nil end
end

function MW.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "map") end
  local K = ui.COLORS
  if QB.dormant then
    -- (QuestBank loaded: its own Map page is its map; this copy sleeps)
    local items = { { spec = { kind = "note", x = 10, name = "QuestBank is loaded: its own Map page shows the map (/qb map)." } } }
    if ui.mapBox then ui.mapBox:Hide() end
    ui:SetInset(0)
    setList(ui, scroll, items)
    return
  end
  local MP = engineMap()
  if not ui.mapGame then gameButton(ui) end
  ui.mapGame:SetOn(not inCombat())
  local ready = layout(ui)
  if ready and ui.mapClosed ~= false then
    -- (opened: on your zone, following you, as the game's map opens)
    ui.mapClosed = false
    MP.follow = true
    MP.Go(playerMap(), "here")
    MP.Update()
  end
  local m = shownMap()
  if m ~= ui.mapFor then remember(m) end
  ui.mapFor = m
  QB.Reader.Left(ui)
  if QB.Reader.Open(ui) then
    -- the quest to read in place of the list, its pins lit and the map on them (MapPage.lua MP.Focus)
    local id = ui.reading.id
    if ready and MP.focus ~= id then
      if MP.focus then MP.Focus(MP.focus) end
      MP.Focus(id)
    end
    if ui.mapBox and ui.mapList and ui.mapList.host then ui.mapList.host:Hide() end
    return QB.Reader.Draw(ui, scroll)
  end
  if ready and MP.focus then MP.Focus(MP.focus) end
  if not ready then
    head(ui, playerMap(), nil)
    setList(ui, scroll, { { spec = { kind = "note", x = 10, name = inCombat() and "The map is ready after combat." or "No map on this client." } } })
    return
  end
  if ui.mapFinds then return findsList(ui, scroll) end
  zoneList(ui, scroll, m)
end

-- the Map window on the Finds list (/cute finds, the footers, Settings > Data you share's Show finds); a character without
-- the Map module is told where it is switched on
function MW.OpenFinds()
  local w = Cute.Window and Cute.Window("map")
  if not (w and Cute.ModuleOn("map")) then Cute.Print("the finds are on the Map window: tick Map in Settings, Modules.") return end
  Cute.Open("map")
  if w.frame and w.frame:IsShown() then MW.ShowFinds(w) end
end

----------------------------------------------------------------------------
-- (sub-project G) the footer of L and M, only while there is something to say: the finds of yours QuestBank's data
-- lacks, and how many of them a guild mate's find agrees with ("14 new finds, a dot, 3 confirmed by the guild", the numbers
-- in INK), its 2 px NEW bar and the book's icon at 14 px; a click opens M on the Finds list, its tooltip the privacy
-- sentence (Cute/Finds.lua's words). The scroll area and the side column end above it (the window's foot); on M it
-- stands under the list alone, and the map's box keeps its height (a canvas resized loses the zoom chosen on it)
----------------------------------------------------------------------------
local FOOT = 24
local function footerOf(ui)
  local b = ui.findsFoot
  if b then return b end
  local K = ui.COLORS
  b = CreateFrame("Button", nil, ui.content)
  b:SetHeight(FOOT - 1)
  b.line = b:CreateTexture(nil, "ARTWORK")
  b.line:SetColorTexture(K.LINE[1], K.LINE[2], K.LINE[3], 1)
  b.line:SetPoint("TOPLEFT", 0, 1)
  b.line:SetPoint("TOPRIGHT", 9, 1)
  b.line:SetHeight(1)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetColorTexture(K.NEW[1], K.NEW[2], K.NEW[3], 1)
  b.bar:SetPoint("TOPLEFT", 0, -4)
  b.bar:SetPoint("BOTTOMLEFT", 0, 4)
  b.bar:SetWidth(2)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(14, 14)
  b.icon:SetPoint("LEFT", 10, 0)
  b.icon:SetTexture(BOOK)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.text = ui.Text(b, 11, K.DIM, "LEFT")
  b.text:SetPoint("LEFT", 30, 0)
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  b:SetScript("OnClick", Cute.Safe(function() MW.OpenFinds() end, "the finds' footer"))
  b:SetScript("OnEnter", Cute.Safe(function(self)
    local F = Cute.Finds
    tip(self, "Finds", F and F.PRIVACY)
    GameTooltip:AddLine("Click: the Map window's Finds list.", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
  end, "the finds' footer"))
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ui.findsFoot = b
  return b
end
function MW.Footer(ui)
  local MP, F = engineMap(), Cute.Finds
  local new, sure = 0, 0
  if MP and MP.FindTally and F and F.FooterText and Cute.ModuleOn("map") then new, sure = MP.FindTally() end
  local foot = new > 0 and FOOT or 0
  if foot > 0 then
    local b = footerOf(ui)
    -- (on M under the list alone, from its inset: the map's box keeps the whole height)
    local left = ui.key == "map" and (insetOf(ui) + 1) or 1
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", left, 1)
    b:SetPoint("BOTTOMRIGHT", -10, 1)
    b.text:SetText(F.FooterText(new, sure, ui.Hex(ui.COLORS.INK)))
    b.text:SetWidth(math.max(60, (ui.frame:GetWidth() or W) - left - 70))
    b:Show()
  elseif ui.findsFoot then
    ui.findsFoot:Hide()
  end
  if (ui.foot or 0) ~= foot then ui.foot = foot; ui:PlaceScroll() end
end

-- the window: made with the builder the first time it opens (UI.lua UI.BuildWindow), its row the crumbs and layers, the
-- canvas's place kept between opens; closed, the next open is on your zone again
local win = Cute.Window and Cute.Window("map")
if win then
  win.DrawTabs = function(self) MW.DrawRow(self); MW.Footer(self) end
  local built = win.OnBuilt
  win.OnBuilt = function(self)
    if built then built(self) end
    self.frame:HookScript("OnHide", function() self.mapClosed = true; self.mapFinds = nil; endReading(self) end)
  end
end

-- (sub-project G) the quest window's footer (L), the Map window's: drawn with its tabs, before each page draws (UI.lua's
-- drawBody, as the Map window's row)
do
  local qw = Cute.Window and Cute.Window("quests")
  local tabs = qw and qw.DrawTabs
  if tabs then qw.DrawTabs = function(self, page, officer) tabs(self, page, officer); MW.Footer(self) end end
end

-- /cute diag's look line (Band.lua's Cute.QuestBand.Diag) ends with the map window's state as only the live client shows
-- it, no names: the canvas's frame strata and a pin's (whether the pins, made at login in the canvas's MEDIUM, follow the
-- window's HIGH), the wheel's mode (MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_SMOOTH is 1), the game's providers added and
-- those waiting for a fight's end, and the area points and map links drawn on the map shown
function MW.DiagLine()
  local MP = engineMap()
  local canvas = MP and MP.canvas
  if not canvas then return "map window: no canvas" .. (inCombat() and " (a fight)" or "") end
  local function strata(f) local ok, v = pcall(function() return f:GetFrameStrata() end); return ok and tostring(v) or "?" end
  local pin = E.QuestMap and E.QuestMap.pageProvider and E.QuestMap.pageProvider.active[1]
  local waiting = 0
  for _ in pairs(later) do waiting = waiting + 1 end
  local sc = canvas.ScrollContainer
  local function pins(template)
    local ok, n = pcall(function() return canvas:GetNumActivePinsByTemplate(template) end)
    return ok and tostring(n) or "?"
  end
  return string.format("map window: canvas %s, a pin %s, wheel %s, providers %d (%d waiting), area points %s, map links %s, hosted %s",
    strata(canvas), pin and strata(pin) or "none", tostring(sc and sc.mouseWheelZoomMode), #(MW.added or {}), waiting,
    pins("AreaPOIPinTemplate"), pins("MapLinkPinTemplate"), MP.host and "yes" or "no")
end
do
  local band = Cute.QuestBand
  local diag = band and band.Diag
  if diag then
    band.Diag = function()
      local ok, line = pcall(diag)
      local okM, map = pcall(MW.DiagLine)
      return tostring(ok and line or "?") .. "; " .. tostring(okM and map or "map window: ?")
    end
  end
end

-- M on map m (the menu's zones below, the Route tab's "Open in the map"): opened, in front of the window it was opened
-- from (an open M is drawn again, not raised, by Cute.Open), on m where it has art (MP.Go says so where it has none);
-- with no m, where it was
function MW.OpenOn(m)
  Cute.Open("map")
  local w = Cute.Window and Cute.Window("map")
  local f = w and w.frame
  if f and f:IsShown() and f.Raise then f:Raise() end
  local MP = engineMap()
  if MP and m then MP.Go(m, "user") end
end
-- (sub-project F) the menu's Map entry (Cute/Windows.lua W.Menu): your zone, the last three zones M showed but yours, its
-- Finds list, the game's own map (gameMap, as the header's button)
local openOn = MW.OpenOn
Cute.MapMenu = function()
  local mine = playerMap()
  local zones = {}
  for _, m in ipairs(MW.recent) do
    local i = info(m)
    if m ~= mine and #zones < 3 and i and plain(i.name) then zones[#zones + 1] = { plain(i.name), function() openOn(m) end } end
  end
  return {
    here = function() Cute.Open("map"); local MP = engineMap(); if MP then MP.Here() end end,
    zones = zones, finds = function() MW.OpenFinds() end, game = gameMap, fight = inCombat(),
  }
end

-- (sub-project F) /cute finds: the Map window on the Finds list (Cute's own words before the core's, as Windows.lua wraps
-- them; a character without the Map module is told where it is switched on)
do
  local core = SlashCmdList.CUTE
  if core then
    SlashCmdList.CUTE = function(msg)
      local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
      if m == "finds" then MW.OpenFinds() return end
      return core(msg)
    end
  end
end
