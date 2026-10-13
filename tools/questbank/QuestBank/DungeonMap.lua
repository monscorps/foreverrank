-- SPDX-License-Identifier: GPL-3.0-or-later
-- A map for every dungeon: Blizzard's own floor art, which the client ships for each Classic dungeon and the City of
-- Dalaran (D.DMAP, gen_data), with the bosses and what they drop (the site's loot records, by item id: the client
-- names the items), the dungeon's quests from the catalog and where you stand with each, and a waypoint on the
-- entrance. Opened from a dungeon's card on the Party page, from /qb map <name>, or /qb map for the list. Inside an
-- instance the game hides where you are, so the map is a map, not a tracker (every addon's is).
local _, QB = ...
local DM = {}
QB.DMap = DM

local TILE = 256
local COLS, ROWS = 4, 3
local SCALE = 0.62            -- 1002 x 668 art shown at 621 x 414
local SIDE = 250              -- the panel with bosses and quests
local MAX_ITEMS_ON_TIP = 12

local plain = QB.Plain

function DM.Data(key) return QB.Data.DMAP and QB.Data.DMAP[key] or nil end

-- the dungeon categories that have a map or bosses, by name for /qb map
function DM.List()
  local out = {}
  for _, c in ipairs(QB.Data.CAT) do
    if c.dungeon and DM.Data(c.key) then out[#out + 1] = c end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function DM.Find(text)
  text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local best
  for _, c in ipairs(DM.List()) do
    local n = c.name:lower()
    if n == text then return c end
    if n:find(text, 1, true) and (not best or #c.name < #best.name) then best = c end
  end
  return best
end

-- the item's name as the client knows it (asked of the server when it does not yet)
local function itemName(id)
  local name
  if C_Item and C_Item.GetItemNameByID then
    local ok, n = pcall(C_Item.GetItemNameByID, id)
    if ok then name = plain(n) end
  elseif GetItemInfo then
    local ok, n = pcall(GetItemInfo, id)
    if ok then name = plain(n) end
  end
  if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return name or ("item " .. id)
end
DM.ItemName = itemName

-- the quests of a dungeon with where you stand: done, in the log (and finished), or still to take
function DM.Quests(key)
  local out, Q, API = {}, QB.Quest, QB.API
  for id in pairs(QB.Data.Q) do
    local q = Q.Get(id)
    if q and q.cat and q.cat.key == key and Q.ForMe(q) then
      local st = API.IsDone(id) and "done" or (QB.state.log[id] and (QB.state.log[id].complete and "ready" or "log") or "open")
      out[#out + 1] = { q = q, st = st }
    end
  end
  table.sort(out, function(a, b) if a.q.lvl ~= b.q.lvl then return (a.q.lvl or 0) < (b.q.lvl or 0) end return a.q.name < b.q.name end)
  return out
end

local STATUS = { done = { "done", 0.5, 0.5, 0.5 }, ready = { "ready to hand in", 0.3, 0.9, 0.3 }, log = { "in your log", 1, 0.82, 0.3 }, open = { "to take", 0.9, 0.9, 0.9 } }

local frame
local function build()
  local f = CreateFrame("Frame", "QuestBankDungeonMap", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  local W, H = 1002 * SCALE, 668 * SCALE
  f:SetSize(W + SIDE + 36, H + 70)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:SetClampedToScreen(true)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 18, -14)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetPoint("TOPRIGHT", -4, -4)
  f.map = CreateFrame("Frame", nil, f)
  f.map:SetSize(W, H)
  f.map:SetPoint("TOPLEFT", 14, -44)
  f.tiles = {}
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local t = f.map:CreateTexture(nil, "BACKGROUND")
      t:SetSize(TILE * SCALE, TILE * SCALE)
      t:SetPoint("TOPLEFT", c * TILE * SCALE, -r * TILE * SCALE)
      f.tiles[#f.tiles + 1] = t
    end
  end
  f.noArt = f.map:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.noArt:SetPoint("CENTER")
  f.noArt:SetText("The client has no map art for this dungeon yet.")
  f.floors = {}
  f.side = CreateFrame("Frame", nil, f)
  f.side:SetSize(SIDE, H)
  f.side:SetPoint("TOPLEFT", f.map, "TOPRIGHT", 10, 0)
  f.bossHead = f.side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.bossHead:SetPoint("TOPLEFT", 0, 0)
  f.bossHead:SetText("Bosses and their loot")
  f.bossRows = {}
  f.questHead = f.side:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.questRows = {}
  f.entrance = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.entrance:SetSize(150, 22)
  f.entrance:SetPoint("BOTTOMLEFT", 14, 12)
  f.entrance:SetText("Waypoint: entrance")
  f.entrance:SetScript("OnClick", QB.Safe(function()
    local e = f.cat and f.cat.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, f.cat.name .. " entrance") end
  end, "dungeon map"))
  f.credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.credit:SetPoint("BOTTOMRIGHT", -14, 14)
  f.credit:SetText("Loot: players' games and foreverrank.com's records. Positions inside are hidden by the game.")
  if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankDungeonMap") end
  f:Hide()
  return f
end

local function row(list, i, parent, height)
  local r = list[i]
  if r then return r end
  r = CreateFrame("Button", nil, parent)
  r:SetSize(SIDE, height)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", 2, 0)
  r.text:SetWidth(SIDE - 70)
  r.text:SetJustifyH("LEFT")
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.right:SetPoint("RIGHT", -2, 0)
  r.right:SetWidth(66)
  r.right:SetJustifyH("RIGHT")
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  list[i] = r
  return r
end

function DM.ShowFloor(n)
  local f = frame
  local d = f.data
  local floor = d and d.floors and d.floors[n]
  f.floor = n
  for i, t in ipairs(f.tiles) do
    if floor and floor[i] then t:SetTexture(floor[i]); t:Show() else t:Hide() end
  end
  f.noArt:SetShown(not floor)
  for i, b in ipairs(f.floors) do b:SetEnabled(i ~= n) end
end

function DM.Open(cat)
  frame = frame or build()
  local f = frame
  local d = DM.Data(cat.key) or { floors = {}, bosses = {} }
  f.cat, f.data = cat, d
  f.title:SetText(cat.name .. (cat.where and cat.where ~= "" and ("  |cff9a8a70" .. cat.where .. "|r") or ""))
  -- floor buttons
  for i = 1, math.max(#d.floors, #f.floors) do
    local b = f.floors[i]
    if not b and i <= #d.floors then
      b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
      b:SetSize(64, 20)
      b:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 160 + (i - 1) * 68, -4)
      b:SetText("Floor " .. i)
      b.n = i
      b:SetScript("OnClick", function(self) DM.ShowFloor(self.n) end)
      f.floors[i] = b
    end
    if b then b:SetShown(i <= #d.floors and #d.floors > 1) end
  end
  DM.ShowFloor(1)
  -- bosses
  local y = -18
  local wing
  for i, b in ipairs(d.bosses) do
    local r = row(f.bossRows, i, f.side, 16)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r.boss = b
    local prefix = (b.w and b.w ~= wing) and ("|cffc6af8d" .. b.w .. "|r  ") or ""
    wing = b.w or wing
    r.text:SetText(prefix .. (b.k == "boss" and "" or ("|cff9a8a70" .. b.k .. "|r ")) .. b.n)
    r.right:SetText(#b.i > 0 and (#b.i .. (#b.i == 1 and " item" or " items")) or "")
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.boss.n, 1, 1, 1)
      if #self.boss.i == 0 then GameTooltip:AddLine("No loot recorded yet.", 0.6, 0.6, 0.6) end
      for j = 1, math.min(MAX_ITEMS_ON_TIP, #self.boss.i) do GameTooltip:AddLine(itemName(self.boss.i[j]), 0.78, 0.69, 0.55) end
      GameTooltip:Show()
    end)
    r:Show()
    y = y - 16
  end
  for i = #d.bosses + 1, #f.bossRows do f.bossRows[i]:Hide() end
  if #d.bosses == 0 then y = y - 2 end
  -- quests
  f.questHead:ClearAllPoints()
  f.questHead:SetPoint("TOPLEFT", 0, y - 10)
  f.questHead:SetText("Quests")
  y = y - 28
  local qs = DM.Quests(cat.key)
  for i, e in ipairs(qs) do
    local r = row(f.questRows, i, f.side, 16)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r.q = e.q
    local st = STATUS[e.st]
    r.text:SetText(string.format("%s |cff6b4d28L%d|r", e.q.name, e.q.lvl or 0))
    r.right:SetText(st[1])
    r.right:SetTextColor(st[2], st[3], st[4])
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      if QB.UI and QB.UI.QuestTooltip then QB.UI.QuestTooltip(GameTooltip, self.q, QB:Status(self.q)) else GameTooltip:SetText(self.q.name) end
      GameTooltip:Show()
    end)
    r:SetScript("OnClick", function(self) if QB.UI and QB.UI.QuestMenu then QB.UI.QuestMenu(self.q) end end)
    r:Show()
    y = y - 16
  end
  for i = #qs + 1, #f.questRows do f.questRows[i]:Hide() end
  f.entrance:SetShown(cat.entrance ~= nil)
  f:Show()
  return f
end

function DM.Toggle(cat)
  if frame and frame:IsShown() and frame.cat == cat then frame:Hide() else DM.Open(cat) end
end

-- /qb map [name]
function DM.Command(rest)
  local list = DM.List()
  if rest and rest ~= "" then
    local cat = DM.Find(rest)
    if cat then DM.Open(cat) else QB:Print("No dungeon called '" .. rest .. "'. /qb map lists them.") end
    return
  end
  local items = {}
  for _, c in ipairs(list) do items[#items + 1] = { c.name, function() DM.Open(c) end } end
  if QB.UI and QB.UI.ShowMenu then QB.UI:ShowMenu("Dungeon maps", items) end
end
