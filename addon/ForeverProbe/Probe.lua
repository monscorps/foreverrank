--[[ ForeverProbe: quiet, read-only character snapshots for foreverrank.com.
     Nothing automated, nothing sent, no chat output. Data sits in
     SavedVariables until the player exports it themselves.            ]]

local ADDON, NS = ...
NS.version = "0.1.0"

local function safe(fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end

local function now() return date("!%Y-%m-%dT%H:%M:%SZ") end

local f = CreateFrame("Frame")
NS.events = f

local function db()
  ForeverProbeDB = ForeverProbeDB or { meta = {}, snapshots = {}, trainers = {}, seenItems = {}, pace = {} }
  ForeverProbeDB.pace = ForeverProbeDB.pace or {}
  return ForeverProbeDB
end
NS.db = db

-- ---------------------------------------------------------------- spells --
local function scanSpells()
  local out = {}
  -- Modern engine spellbook first, classic API as the fallback.
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local lines = safe(C_SpellBook.GetNumSpellBookSkillLines)
    for li = 1, (lines or 0) do
      local info = safe(C_SpellBook.GetSpellBookSkillLineInfo, li)
      local offset = info and (info.itemIndexOffset or 0) or 0
      local count = info and (info.numSpellBookItems or 0) or 0
      for i = offset + 1, offset + count do
        local itemInfo = safe(C_SpellBook.GetSpellBookItemInfo, i, 0)
        local id = itemInfo and (itemInfo.spellID or itemInfo.actionID)
        if id then out[#out + 1] = id end
      end
    end
  elseif GetNumSpellTabs then
    for t = 1, (safe(GetNumSpellTabs) or 0) do
      local _, _, offset, num = safe(GetSpellTabInfo, t)
      for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local link = safe(GetSpellLink, i, "spell")
        local id = link and tonumber(link:match("spell:(%d+)"))
        if id then out[#out + 1] = id end
      end
    end
  end
  return out
end

-- ------------------------------------------------------------- equipment --
local function scanItems()
  local out = {}
  for slot = 1, 19 do
    local id = safe(GetInventoryItemID, "player", slot)
    if id then out[#out + 1] = id end
  end
  local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local getItem = C_Container and C_Container.GetContainerItemID or GetContainerItemID
  if getSlots and getItem then
    for bag = 0, 4 do
      for slot = 1, (safe(getSlots, bag) or 0) do
        local id = safe(getItem, bag, slot)
        if id then out[#out + 1] = id end
      end
    end
  end
  return out
end

-- ------------------------------------------------- engraving, if it exists --
local function scanEngraving()
  if not C_Engraving then return end
  local out = {}
  local cats = safe(C_Engraving.GetRuneCategories, false, false)
  for _, cat in ipairs(cats or {}) do
    for _, rune in ipairs(safe(C_Engraving.GetRunesForCategory, cat, false) or {}) do
      out[#out + 1] = { id = rune.skillLineAbilityID, name = rune.name, known = rune.learnedAbilitySpellIDs and #rune.learnedAbilitySpellIDs > 0 }
    end
  end
  if #out > 0 then return out end
end

-- --------------------------------------------------------------- snapshot --
function NS.snapshot(reason)
  local d = db()
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  local build, _, _, iface = GetBuildInfo()
  local snap = {
    at = now(), why = reason,
    name = UnitName("player"), realm = safe(GetRealmName),
    guild = safe(GetGuildInfo, "player"),
    level = UnitLevel("player"), race = race, class = class,
    xp = safe(UnitXP, "player"), xpMax = safe(UnitXPMax, "player"),
    zone = safe(GetRealZoneText), build = build, interface = iface,
    spells = scanSpells(), items = scanItems(), engraving = scanEngraving(),
  }
  d.meta.addon = NS.version
  d.meta.lastSnapshot = snap.at
  if NS.progExtras then
    local ex = NS.progExtras()
    snap.money = ex.money
    snap.skills = ex.skills
  end
  local g = safe(GetGuildInfo, "player")
  if g then snap.guild = g end
  d.snapshots[#d.snapshots + 1] = snap
  while #d.snapshots > 20 do table.remove(d.snapshots, 1) end
  return snap
end

-- --------------------------------------------------------------- trainers --
local function scanTrainer()
  if not GetNumTrainerServices then return end
  local n = safe(GetNumTrainerServices)
  if not n or n == 0 then return end
  local rows = {}
  for i = 1, n do
    local name, rank, category = safe(GetTrainerServiceInfo, i)
    local cost = safe(GetTrainerServiceCost, i)
    local level = safe(GetTrainerServiceLevelReq, i)
    if name and category ~= "header" then
      rows[#rows + 1] = { n = name, r = rank, lvl = level, c = cost }
    end
  end
  if #rows == 0 then return end
  local d = db()
  d.trainers[#d.trainers + 1] = { at = now(), npc = safe(UnitName, "npc"), zone = safe(GetRealZoneText), services = rows }
  while #d.trainers > 40 do table.remove(d.trainers, 1) end
end

-- ----------------------------------------------------------------- events --
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("TRAINER_SHOW")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(5, function() NS.snapshot("login") end)
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(2, function() NS.snapshot("levelup") end)
  elseif event == "TRAINER_SHOW" then
    C_Timer.After(0.5, scanTrainer)
  end
  if NS.onEvent then NS.onEvent(event, ...) end
end)
