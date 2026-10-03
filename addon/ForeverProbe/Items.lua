--[[ ForeverProbe :: Items
     Blizzard sends most new Forever items from the server: the client's files never hold them, and they keep
     coming as the beta goes on. Whatever weapon, armor or recipe tooltip the game shows you (bags, loot, quest
     rewards, vendors, chat links), its text is kept here once per client build, so the next upload brings it
     to foreverrank.com's Database. Item data only: no names but the item's.                                   ]]
local ADDON, NS = ...

local KEEP = { [2] = true, [4] = true, [9] = true } -- weapons, armor, recipes
local MAX = 3000                                    -- items kept per build: plenty for a beta, small for an upload
local queue, queued, pending, skip = {}, {}, {}, {}
local scheduled = false
local build

local function plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function store()
  local d = NS.db()
  if type(d.items) ~= "table" then d.items = {} end
  return d.items
end

local function count(items)
  local n = 0
  for _ in pairs(items) do n = n + 1 end
  return n
end

-- one item's tooltip, as the game shows it at this build; false when the client hasn't loaded the item yet
local function capture(id)
  build = build or tostring(select(2, GetBuildInfo()) or "")
  local items = store()
  local e = items[id]
  if (e and e.b == build) or skip[id] then return true end
  if not C_Item or not C_Item.GetItemInfo then return true end
  local ok, name, _, quality, ilvl, reqLevel, _, _, _, equipLoc, icon, _, classID, subclassID, bindType = pcall(C_Item.GetItemInfo, id)
  name = ok and plain(name) or nil
  if type(name) ~= "string" then
    if C_Item.RequestLoadItemDataByID and not pending[id] then
      pending[id] = true
      pcall(C_Item.RequestLoadItemDataByID, id)
    end
    return false
  end
  classID = plain(classID)
  if not KEEP[classID] then skip[id] = true; return true end
  if not e and NS.itemCount and NS.itemCount >= MAX then return true end
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local okT, data = pcall(C_TooltipInfo.GetItemByID, id)
    if okT and type(data) == "table" and type(data.lines) == "table" then
      for i, line in ipairs(data.lines) do
        local left, right = plain(line.leftText), plain(line.rightText)
        if type(left) == "string" and left ~= "" and not (i == 1 and left == name) then
          lines[#lines + 1] = (type(right) == "string" and right ~= "") and (left .. "\t" .. right) or left
        end
        if #lines >= 40 then break end
      end
    end
  end
  local num = function(v) v = plain(v); return type(v) == "number" and v or nil end
  local str = function(v) v = plain(v); return type(v) == "string" and v ~= "" and v or nil end
  items[id] = { b = build, n = name, q = num(quality), l = num(ilvl), r = num(reqLevel), el = str(equipLoc), c = classID,
                u = num(subclassID), bd = num(bindType), ic = num(icon), x = lines, at = time() }
  if not e then NS.itemCount = (NS.itemCount or count(items)) + 1 end
  return true
end

local function flush()
  scheduled = false
  local ids = queue
  queue = {}
  for _, id in ipairs(ids) do
    queued[id] = nil
    capture(id) -- an item the client hasn't loaded comes back with ITEM_DATA_LOAD_RESULT
  end
end

-- every id goes through a short timer: the hook only notes it, the reading happens in ForeverProbe's own code
local function want(id)
  id = plain(id)
  if type(id) ~= "number" or id <= 0 or queued[id] or skip[id] then return end
  queued[id] = true
  queue[#queue + 1] = id
  if not scheduled and C_Timer then
    scheduled = true
    C_Timer.After(0.5, function() NS.util.Try("item capture", flush) end)
  end
end
NS.WantItem = want

local function idOf(link)
  link = plain(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)"))
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(_, data)
    if type(data) == "table" then want(data.id) end
  end)
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "LOOT_READY", "QUEST_DETAIL", "QUEST_COMPLETE", "MERCHANT_SHOW", "ITEM_DATA_LOAD_RESULT" }) do
  pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event, a1, a2)
  NS.util.Try("items " .. event, function()
    if event == "ITEM_DATA_LOAD_RESULT" then
      local id = plain(a1)
      if pending[id] then pending[id] = nil; if a2 then want(id) end end
    elseif event == "LOOT_READY" and GetNumLootItems and GetLootSlotLink then
      for i = 1, GetNumLootItems() do want(idOf(GetLootSlotLink(i))) end
    elseif (event == "QUEST_DETAIL" or event == "QUEST_COMPLETE") and GetQuestItemLink then
      for i = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do want(idOf(GetQuestItemLink("choice", i))) end
      for i = 1, (GetNumQuestRewards and GetNumQuestRewards() or 0) do want(idOf(GetQuestItemLink("reward", i))) end
    elseif event == "MERCHANT_SHOW" and GetMerchantNumItems and GetMerchantItemID then
      for i = 1, GetMerchantNumItems() do want(plain(GetMerchantItemID(i))) end
    end
  end)
end)
