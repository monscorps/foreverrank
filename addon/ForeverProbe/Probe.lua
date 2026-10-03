--[[ ForeverProbe: quiet, read-only character snapshots for foreverrank.com.
     Nothing automated, nothing sent; one chat line the first time a new version loads. Data sits in
     SavedVariables until the player exports it themselves.            ]]

local ADDON, NS = ...
NS.version = "0.4.7"

local safe = NS.util.Safe

local function now() return date("!%Y-%m-%dT%H:%M:%SZ") end

local f = CreateFrame("Frame")
NS.events = f

-- The beta-day probe (0.1.0) saved a different table under the same name. Its keys go; anything
-- 0.2/0.3 wrote on top of it (pace history, the bar's place, the guild roster) stays. Every table we
-- write into is made sure of once, on first use.
local BETA_DAY = { "when", "build", "interface", "api", "c_namespaces", "me", "guid", "xp", "talents", "spellbook", "gear", "cleu" }
local normalized
local function db()
  local d = ForeverProbeDB
  if not normalized then
    if type(d) ~= "table" then d = {} end
    if type(d.meta) ~= "table" or d.cleu ~= nil or d.c_namespaces ~= nil then
      for _, k in ipairs(BETA_DAY) do d[k] = nil end
    end
    for _, k in ipairs({ "meta", "snapshots", "trainers", "seenItems", "pace" }) do
      if type(d[k]) ~= "table" then d[k] = {} end
    end
    d.meta.schema = 4
    ForeverProbeDB = d
    normalized = true
  end
  return ForeverProbeDB
end
NS.db = db

-- ---------------------------------------------------------------- spells --
-- Learned spells only. The book also lists spells you can't cast yet (FutureSpell) and flyouts,
-- whose IDs aren't spells: the future ones go in a list of their own.
local function scanSpells()
  local out, future = {}, {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local T = Enum and Enum.SpellBookItemType
    local SPELL, FUTURE = T and T.Spell or 1, T and T.FutureSpell or 2
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    for li = 1, (safe(C_SpellBook.GetNumSpellBookSkillLines) or 0) do
      local info = safe(C_SpellBook.GetSpellBookSkillLineInfo, li)
      local offset = info and (info.itemIndexOffset or 0) or 0
      local count = info and (info.numSpellBookItems or 0) or 0
      for i = offset + 1, offset + count do
        local it = safe(C_SpellBook.GetSpellBookItemInfo, i, bank)
        local id = it and it.spellID
        if id then
          if (it.itemType == SPELL and not it.isOffSpec) or (it.itemType == nil and IsSpellKnown and safe(IsSpellKnown, id)) then
            out[#out + 1] = id
          elseif it.itemType == FUTURE or it.isOffSpec then
            future[#future + 1] = id
          end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellBookItemInfo then
    for t = 1, (safe(GetNumSpellTabs) or 0) do
      local _, _, offset, num = safe(GetSpellTabInfo, t)
      for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local kind, id = safe(GetSpellBookItemInfo, i, "spell")
        if kind == "SPELL" and id then out[#out + 1] = id
        elseif kind == "FUTURESPELL" and id then future[#future + 1] = id end
      end
    end
  end
  return out, future
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
  local out, owned = {}, {}
  -- the runes you own come from the owned-only list; "known" means one of those
  for _, cat in ipairs(safe(C_Engraving.GetRuneCategories, false, true) or {}) do
    for _, rune in ipairs(safe(C_Engraving.GetRunesForCategory, cat, true) or {}) do
      if rune.skillLineAbilityID then owned[rune.skillLineAbilityID] = true end
    end
  end
  for _, cat in ipairs(safe(C_Engraving.GetRuneCategories, false, false) or {}) do
    for _, rune in ipairs(safe(C_Engraving.GetRunesForCategory, cat, false) or {}) do
      out[#out + 1] = { id = rune.skillLineAbilityID, name = rune.name, known = owned[rune.skillLineAbilityID] or nil }
    end
  end
  if #out > 0 then return out end
end

-- --------------------------------------------------------------- snapshot --
function NS.snapshot(reason)
  local d = db()
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  local version, build, _, iface = GetBuildInfo()
  local spells, future = scanSpells()
  local snap = {
    at = now(), why = reason, char = NS.util.CharKey(),
    name = UnitName("player"), realm = safe(GetRealmName),
    level = UnitLevel("player"), race = race, class = class,
    xp = safe(UnitXP, "player"), xpMax = safe(UnitXPMax, "player"),
    zone = safe(GetRealZoneText), version = version, build = build, interface = iface,
    spells = spells, futureSpells = future, items = scanItems(), engraving = scanEngraving(),
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
-- the latest list from each trainer: a class trainer seen every two levels is one entry, not twenty
local function scanTrainer()
  if not GetNumTrainerServices then return end
  local n = safe(GetNumTrainerServices)
  if not n or n == 0 then return end
  local STATE = { available = true, unavailable = true, used = true }
  local rows = {}
  for i = 1, n do
    -- this client (the modern trainer window): name, state, icon, level, rank, category.
    -- Classic clients: name, rank, category.
    local a, b, _, lvlM, sub = safe(GetTrainerServiceInfo, i)
    local name, state, rank, isHeader
    if STATE[b] then
      name, state, rank = a, b, sub
    else
      local _, _, cat = safe(GetTrainerServiceInfo, i)
      name, rank, isHeader = a, b, cat == "header"
    end
    local level = safe(GetTrainerServiceLevelReq, i) or lvlM
    if name and not isHeader then
      rows[#rows + 1] = { n = name, r = rank, lvl = level, c = safe(GetTrainerServiceCost, i), t = state }
    end
  end
  if #rows == 0 then return end
  local d = db()
  local npc, zone = safe(UnitName, "npc"), safe(GetRealZoneText)
  -- one entry per trainer; each visit adds what it showed (the window filters what it lists)
  local entry
  for _, t in ipairs(d.trainers) do if t.npc == npc and t.zone == zone then entry = t end end
  if not entry then
    entry = { npc = npc, zone = zone, services = {} }
    d.trainers[#d.trainers + 1] = entry
  end
  entry.at = now()
  entry.chars = entry.chars or {}
  entry.chars[NS.util.CharKey()] = true
  local have = {}
  for k, sv in ipairs(entry.services) do have[(sv.n or "") .. "\0" .. (sv.r or "")] = k end
  for _, row in ipairs(rows) do
    local k = have[(row.n or "") .. "\0" .. (row.r or "")]
    if k then entry.services[k] = row else entry.services[#entry.services + 1] = row end
  end
  while #d.trainers > 40 do table.remove(d.trainers, 1) end
end

-- ------------------------------------------------ QuestBank's discoveries --
-- QuestBank (optional) notes quests, their NPCs and XP as players meet them. When it runs too,
-- ForeverProbe carries those notes in its saved file and its export, so they reach foreverrank.com
-- with everything else. Neither addon needs the other.
function NS.questbank()
  local qb = QuestBankDB
  local disc = type(qb) == "table" and type(qb.disc) == "table" and qb.disc or nil
  if not disc then return nil end
  return { at = now(), version = disc.ver, build = disc.build, disc = disc }
end

-- ----------------------------------------------------------------- events --
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    -- a snapshot at login and /reload, not on every loading screen
    local initial, reload = ...
    if initial or reload or initial == nil then
      C_Timer.After(5, function() NS.util.Try("login snapshot", NS.snapshot, "login") end)
      -- once per version: say it's running and where its file goes, so nobody has to guess whether it loaded
      C_Timer.After(6, function() NS.util.Try("hello", function()
        local m = db().meta
        if m.greeted == NS.version then return end
        DEFAULT_CHAT_FRAME:AddMessage(("|cffe5cc80ForeverProbe|r %s is running. The game writes its file, ForeverProbe.lua, when you log out or /reload; if you run the Companion, it uploads it from there. /probe for the panel."):format(NS.version))
        m.greeted = NS.version
      end) end)
    end
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(2, function() NS.util.Try("level-up snapshot", NS.snapshot, "levelup") end)
  elseif event == "TRAINER_SHOW" then
    C_Timer.After(0.5, function() NS.util.Try("trainer scan", scanTrainer) end)
  elseif event == "PLAYER_LOGOUT" then
    local ok, qb = pcall(NS.questbank)
    db().questbank = ok and qb or nil
    if NS.onLogout then NS.util.Try("logout", NS.onLogout) end
  end
  if NS.onEvent then NS.util.Try(event, NS.onEvent, event, ...) end
end)
