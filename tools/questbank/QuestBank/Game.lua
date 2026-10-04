-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's notes on the game itself, for foreverrank.com's spellbook and item database. Blizzard sends many
-- Forever spells and items from the server, so no datamine of the client has them; players' games do:
--   snap    per class and race: the spells learned and the item ids worn and carried, from the highest-level
--           character's latest reading
--   items   the tooltip of every weapon, armor piece and recipe the game shows you (bags, loot, quest rewards,
--           vendors, chat links), once per build, and again after six hours: Blizzard retunes items without one
-- Only on the Forever client, only while Settings' "Note items and spells you see" is ticked (it is by default;
-- unticking it clears what was noted), and never a name: class and race tokens, levels, ids and the item's own
-- text, in QuestBankDB.game.
-- It does what the ForeverProbe addon did: that addon's notes are taken over once, and while it is still
-- loaded QuestBank says, once a version, that its folder can go.
local _, QB = ...
local Game = {}
QB.Game = Game

local MAX_ITEMS = 1000  -- tooltips kept: QuestBank.lua is uploaded whole, so it stays a small file
local MAX_LINES = 30    -- lines kept of one tooltip
local REREAD = 6 * 3600 -- read an item again after this long
local KEEP = { [2] = true, [4] = true, [9] = true } -- weapons, armor, recipes
Game.MAX_ITEMS, Game.MAX_LINES = MAX_ITEMS, MAX_LINES
Game.RETIRED = "QuestBank now notes what ForeverProbe did. You can delete the ForeverProbe folder from Interface\\AddOns."

local plain = QB.Plain

-- the client: its version ("1.60.1"), build number and interface number
local function client()
  if not GetBuildInfo then return nil end
  local version, build, _, iface = GetBuildInfo()
  version = plain(version)
  return type(version) == "string" and version or nil, tonumber(plain(build)), tonumber(plain(iface))
end

-- Forever's interface numbers are 16xxx; Classic Era (11xxx) and every other client are left alone
function Game.Forever()
  local _, _, iface = client()
  return iface ~= nil and iface >= 16000 and iface <= 16999
end

-- noting: the Forever client, with the Settings box ticked
local function on()
  if not Game.Forever() then return false end
  local s = QuestBankDB and QuestBankDB.settings
  return not (type(s) == "table" and s.noteGame == false)
end
Game.On = on

local function db()
  QuestBankDB = QuestBankDB or {}
  local g = QuestBankDB.game
  if type(g) ~= "table" or g.v ~= 1 then
    g = { v = 1 }
    QuestBankDB.game = g
  end
  if type(g.snap) ~= "table" then g.snap = {} end
  if type(g.items) ~= "table" then g.items = {} end
  local version, build, iface = client()
  g.client, g.build, g.iface = version or g.client, build or g.build, iface or g.iface
  return g
end
Game.DB = db

-- a list of ids, each once and in order, without anything the client hid
local function idList(list)
  local out, have = {}, {}
  for _, v in ipairs(type(list) == "table" and list or {}) do
    if type(v) == "table" then v = v.id end
    v = tonumber(plain(v))
    if v and v > 0 and not have[v] then have[v] = true; out[#out + 1] = v end
  end
  table.sort(out)
  return out
end

----------------------------------------------------------------------------
-- what a character knows and carries
----------------------------------------------------------------------------
-- learned spells only: the book also lists spells you can't cast yet, other specs' and flyouts (no spell ids)
local function scanSpells()
  local ids = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local T = Enum and Enum.SpellBookItemType
    local SPELL = T and T.Spell or 1
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local okN, n = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    for li = 1, (okN and tonumber(plain(n)) or 0) do
      local okL, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, li)
      info = okL and plain(info) or nil
      if type(info) == "table" then
        local offset, count = tonumber(plain(info.itemIndexOffset)) or 0, tonumber(plain(info.numSpellBookItems)) or 0
        for i = offset + 1, offset + count do
          local okI, it = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
          it = okI and plain(it) or nil
          if type(it) == "table" then
            local kind, id = plain(it.itemType), plain(it.spellID)
            local known = kind == SPELL and not plain(it.isOffSpec)
            if kind == nil and id and IsSpellKnown then
              local okK, k = pcall(IsSpellKnown, id)
              known = okK and plain(k) and true or false
            end
            if known then ids[#ids + 1] = id end
          end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
    local okN, n = pcall(GetNumSpellTabs)
    for t = 1, (okN and tonumber(plain(n)) or 0) do
      local okT, _, _, offset, num = pcall(GetSpellTabInfo, t)
      offset, num = okT and tonumber(plain(offset)) or 0, okT and tonumber(plain(num)) or 0
      for i = offset + 1, offset + num do
        local okI, kind, id = pcall(GetSpellBookItemInfo, i, "spell")
        if okI and plain(kind) == "SPELL" then ids[#ids + 1] = id end
      end
    end
  end
  return idList(ids)
end

-- what you wear (slots 1-19) and carry (bags 0-4), each item once
local function scanItems()
  local ids = {}
  if GetInventoryItemID then
    for slot = 1, 19 do
      local ok, id = pcall(GetInventoryItemID, "player", slot)
      if ok then ids[#ids + 1] = id end
    end
  end
  local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getItem = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  if getSlots and getItem then
    for bag = 0, 4 do
      local okS, n = pcall(getSlots, bag)
      for slot = 1, (okS and tonumber(plain(n)) or 0) do
        local ok, id = pcall(getItem, bag, slot)
        if ok then ids[#ids + 1] = id end
      end
    end
  end
  return idList(ids)
end

-- one class and race's reading: a higher level wins, then the later reading
local function better(new, old)
  if type(old) ~= "table" then return true end
  local nl, ol = new.level or 0, tonumber(old.level) or 0
  if nl ~= ol then return nl > ol end
  return (new.at or 0) >= (tonumber(old.at) or 0)
end

function Game.Snap()
  if not on() then return end
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  class, race = plain(class), plain(race)
  local level = tonumber(plain(UnitLevel("player")))
  if type(class) ~= "string" or class == "" or type(race) ~= "string" or race == "" or not level or level < 1 then return end
  local g = db()
  local key = class .. "/" .. race
  local old = g.snap[key]
  if type(old) == "table" and (tonumber(old.level) or 0) > level then return end -- a higher character's reading stands
  local snap = { class = class, race = race, level = level, at = time(), build = g.build, spells = scanSpells(), items = scanItems() }
  -- a book the client hasn't filled yet reads empty: keep what this level showed before
  if #snap.spells == 0 and type(old) == "table" and old.level == level and type(old.spells) == "table" then snap.spells = old.spells end
  g.snap[key] = snap
end

----------------------------------------------------------------------------
-- item tooltips: the hook only notes the id; reading happens a moment later in QuestBank's own code
----------------------------------------------------------------------------
local queue, queued, pending, skip, tries = {}, {}, {}, {}, {}
local scheduled = false
local count, countOf -- tooltips kept, and in which table

local function buildOf(e)
  return type(e) == "table" and tonumber(tostring(e.b or ""):match("(%d+)$")) or 0
end

local function atOf(e)
  return type(e) == "table" and tonumber(e.at) or 0
end

local function newer(a, b)
  local ba, bb = buildOf(a), buildOf(b)
  if ba ~= bb then return ba > bb end
  return atOf(a) > atOf(b)
end

-- the oldest tooltip by build, then by when it was read: the first to go when the table is full
local function oldest(items)
  local id0, e0
  for id, e in pairs(items) do
    if not id0 or newer(e0, e) then id0, e0 = id, e end
  end
  return id0
end

-- down to the cap, dropping the oldest; returns how many are kept
local function trim(items)
  local list = {}
  for id, e in pairs(items) do list[#list + 1] = { id = id, b = buildOf(e), at = atOf(e) } end
  if #list > MAX_ITEMS then
    table.sort(list, function(a, b)
      if a.b ~= b.b then return a.b < b.b end
      if a.at ~= b.at then return a.at < b.at end
      return tostring(a.id) < tostring(b.id)
    end)
    for i = 1, #list - MAX_ITEMS do items[list[i].id] = nil end
    return MAX_ITEMS
  end
  return #list
end

local function kept(items)
  if countOf ~= items then
    count, countOf = 0, items
    for _ in pairs(items) do count = count + 1 end
  end
  return count
end

local want

-- one item's tooltip as the game shows it at this build
local function capture(id)
  local g = db()
  local items = g.items
  local tag = (g.client and (g.client .. ".") or "") .. tostring(g.build or "")
  local e = items[id]
  if skip[id] or (type(e) == "table" and e.b == tag and time() - atOf(e) < REREAD) then return end
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not info then return end
  local ok, name, _, quality, ilvl, reqLevel, _, _, _, equipLoc, icon, _, classID, subclassID, bindType, _, setID = pcall(info, id)
  name = ok and plain(name) or nil
  if type(name) ~= "string" then
    -- not in the client's cache yet: asked for, and ITEM_DATA_LOAD_RESULT brings it back
    if C_Item and C_Item.RequestLoadItemDataByID and not pending[id] then
      pending[id] = true
      pcall(C_Item.RequestLoadItemDataByID, id)
    end
    return
  end
  classID = plain(classID)
  if not KEEP[classID] then skip[id] = true; return end
  local lines, partial = {}, false
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local okT, data = pcall(C_TooltipInfo.GetItemByID, id)
    data = okT and plain(data) or nil
    local list = type(data) == "table" and plain(data.lines) or nil
    if type(list) == "table" then
      local T = Enum and Enum.TooltipDataLineType
      for i, line in ipairs(list) do
        line = plain(line)
        if type(line) == "table" then
          local left, right, kind = plain(line.leftText), plain(line.rightText), plain(line.type)
          -- a recipe's tooltip goes on with the crafted item's: keep the recipe's own lines only
          if classID == 9 and T and (kind == T.NestedBlock or kind == T.Blank or kind == T.Separator) and #lines > 0 then break end
          if type(left) == "string" and left ~= "" and not (i == 1 and left == name) then
            if left == RETRIEVING_ITEM_INFO or left:match("^%a+:%s*$") then partial = true end
            lines[#lines + 1] = (type(right) == "string" and right ~= "") and (left .. "\t" .. right) or left
            if classID == 9 and left:match("^Use:") then break end
          end
        end
        if #lines >= MAX_LINES then break end
      end
    end
  end
  if partial then
    -- the server hasn't sent the effect text yet: try again shortly, a few times, then keep what there is
    tries[id] = (tries[id] or 0) + 1
    if tries[id] <= 3 then
      C_Timer.After(3, QB.Safe(function() want(id) end, "item notes"))
      return
    end
  end
  local function num(v) v = plain(v); return type(v) == "number" and v or nil end
  local function str(v) v = plain(v); return type(v) == "string" and v ~= "" and v or nil end
  if type(e) ~= "table" then
    if kept(items) >= MAX_ITEMS then
      local gone = oldest(items)
      if gone then items[gone] = nil; count = count - 1 end
    end
    count = count + 1
  end
  -- (a grey item's quality is 0, and stays 0)
  items[id] = { b = tag, at = time(), lc = str(GetLocale and GetLocale()), n = name, q = num(quality), l = num(ilvl), r = num(reqLevel),
                el = str(equipLoc), c = classID, u = num(subclassID), bd = num(bindType), ic = num(icon), e = num(setID), x = lines }
end

local function flush()
  scheduled = false
  local ids = queue
  queue = {}
  for _, id in ipairs(ids) do queued[id] = nil end
  for _, id in ipairs(ids) do
    if on() then QB.Try("item notes", capture, id) end
  end
end

function want(id)
  id = tonumber(plain(id))
  if not id or id <= 0 or queued[id] or skip[id] or not on() then return end
  queued[id] = true
  queue[#queue + 1] = id
  if not scheduled then
    scheduled = true
    C_Timer.After(0.5, QB.Safe(flush, "item notes"))
  end
end
Game.Want = want

local function idOf(link)
  link = plain(link)
  return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

----------------------------------------------------------------------------
-- ForeverProbe's notes, taken over once; its saved variable only exists while it is loaded.
-- Never its names: a snapshot's character, realm and guild stay where they were.
----------------------------------------------------------------------------
-- "2026-10-01T12:00:00Z" -> seconds since 1970 (ForeverProbe wrote its times as text)
local function isoTime(s)
  if type(s) ~= "string" then return nil end
  local y, m, d, H, M, S = s:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  local days = era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
  return days * 86400 + tonumber(H) * 3600 + tonumber(M) * 60 + tonumber(S)
end

local function copyTip(e)
  local x = {}
  for _, line in ipairs(e.x) do
    if type(line) == "string" then x[#x + 1] = line end
    if #x >= MAX_LINES then break end
  end
  local function num(v) return type(v) == "number" and v or nil end
  local function str(v) return type(v) == "string" and v ~= "" and v or nil end
  return { b = str(e.b) or (num(e.b) and tostring(e.b)) or nil, at = num(e.at), lc = str(e.lc), n = e.n, q = num(e.q), l = num(e.l),
           r = num(e.r), el = str(e.el), c = num(e.c), u = num(e.u), bd = num(e.bd), ic = num(e.ic), e = num(e.e), x = x }
end

function Game.Import()
  local fp = ForeverProbeDB
  if type(fp) ~= "table" or not on() then return end
  local g = db()
  if g.imported then return end
  if type(fp.items) == "table" then
    for k, e in pairs(fp.items) do
      local id = tonumber(k)
      if id and id > 0 and type(e) == "table" and type(e.n) == "string" and type(e.x) == "table" then
        local tip = copyTip(e)
        if type(g.items[id]) ~= "table" or newer(tip, g.items[id]) then g.items[id] = tip end
      end
    end
    trim(g.items)
    countOf = nil
  end
  if type(fp.snapshots) == "table" then
    for _, sn in ipairs(fp.snapshots) do
      if type(sn) == "table" then
        local class, race, level, iface = sn.class, sn.race, tonumber(sn.level), tonumber(sn.interface)
        if type(class) == "string" and class ~= "" and type(race) == "string" and race ~= "" and level and level >= 1
          and (not iface or (iface >= 16000 and iface <= 16999)) then
          local snap = { class = class:upper(), race = race, level = level, at = isoTime(sn.at), build = tonumber(sn.build),
                         spells = idList(sn.spells), items = idList(sn.items) }
          local key = snap.class .. "/" .. race
          if better(snap, g.snap[key]) then g.snap[key] = snap end
        end
      end
    end
  end
  g.imported = true
end

-- ForeverProbe still loaded: say once a version that QuestBank does its job now. On the Forever client not before
-- its notes are taken over (the box unticked, or the import failed): once its folder is gone they can't be
function Game.Retire()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if type(isLoaded) ~= "function" then return end
  local ok, loaded = pcall(isLoaded, "ForeverProbe")
  if not ok or not plain(loaded) then return end
  if Game.Forever() and type(ForeverProbeDB) == "table" then
    local g = QuestBankDB and QuestBankDB.game
    if not (type(g) == "table" and g.imported) then return end
  end
  local s = QB:Settings()
  if s.toldRetired == QB.version then return end
  s.toldRetired = QB.version
  QB:Print(Game.RETIRED)
end

-- the Settings box. Unticked, what was noted goes too: QuestBank.lua is uploaded whole, and the box is the player's
-- say over what foreverrank.com gets. Ticked, ForeverProbe's notes are taken over if it is still there
function Game.SetOn(yes)
  QB:Settings().noteGame = yes and true or false
  if not Game.Forever() then return end
  if yes then
    db()
    QB.Try("old notes", Game.Import)
    QB.Try("old notes", Game.Retire)
  elseif QuestBankDB then
    QuestBankDB.game = nil
  end
end

----------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------
function Game.OnEvent(event, a1, a2)
  if event == "PLAYER_ENTERING_WORLD" then
    -- at login and /reload, not on every loading screen
    if a1 or a2 or a1 == nil then C_Timer.After(8, QB.Safe(Game.Snap, "spell notes")) end
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(2, QB.Safe(Game.Snap, "spell notes")) -- once the spellbook has the new level's spells
  elseif event == "PLAYER_LOGOUT" then
    Game.Snap()
  elseif event == "ITEM_DATA_LOAD_RESULT" then
    local id = tonumber(plain(a1))
    if id and pending[id] then
      pending[id] = nil
      if plain(a2) then want(id) end
    end
  elseif event == "LOOT_READY" and GetNumLootItems and GetLootSlotLink then
    for i = 1, (tonumber(plain(GetNumLootItems())) or 0) do want(idOf(GetLootSlotLink(i))) end
  elseif event == "MERCHANT_SHOW" and GetMerchantNumItems and GetMerchantItemID then
    for i = 1, (tonumber(plain(GetMerchantNumItems())) or 0) do want(GetMerchantItemID(i)) end
  end
end

-- how much is noted, for /qb discoveries and the Settings page: item tooltips, and class and race spellbooks
function Game.Count()
  local g = QuestBankDB and QuestBankDB.game
  if type(g) ~= "table" then return 0, 0 end
  local ni, ns = 0, 0
  for _ in pairs(type(g.items) == "table" and g.items or {}) do ni = ni + 1 end
  for _ in pairs(type(g.snap) == "table" and g.snap or {}) do ns = ns + 1 end
  return ni, ns
end

function Game:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  -- once the other addons have loaded: ForeverProbe's notes, then the line about it
  C_Timer.After(6, function()
    QB.Try("old notes", Game.Import)
    QB.Try("old notes", Game.Retire)
  end)
  if not Game.Forever() then return end
  f:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2) Game.OnEvent(event, a1, a2) end, "item notes"))
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT", "LOOT_READY", "MERCHANT_SHOW", "ITEM_DATA_LOAD_RESULT" }) do
    pcall(f.RegisterEvent, f, e)
  end
  -- every item tooltip the game shows (bags, chat links, anything hovered); quest rewards come through Discover
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, QB.Safe(function(_, data)
      if type(data) == "table" then want(data.id) end
    end, "item notes"))
  end
  if on() then db() end
end
