-- ForeverProbe: one honest question, asked forty ways -- what can an addon
-- see in the Forever beta client? Everything lands in SavedVariables
-- (ForeverProbeDB), written when you log out or /reload. Send that file.
--
-- Written to run on ANY client: every probe is pcall'd, and both the classic
-- (1.12-style) and modern (C_*) API shapes are tried. Wrong guesses report
-- themselves instead of erroring.

local function say(msg)
  msg = "|cffe5cc80Probe:|r " .. tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(msg)
  else
    print(msg)
  end
end

local function grab(fn, ...)
  local out = { pcall(fn, ...) }
  if out[1] then
    table.remove(out, 1)
    return out
  end
  return { error = tostring(out[2]) }
end

-- A hidden tooltip we can point at things and read.
local tip
-- Takes the METHOD NAME, because the tooltip does not exist until first use
-- and different clients carry different setters.
local function tipLines(method, ...)
  if not tip then
    local ok = pcall(function()
      tip = CreateFrame("GameTooltip", "ForeverProbeTip", nil, "GameTooltipTemplate")
      tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end)
    if not ok then tip = nil; return nil end
  end
  tip:ClearLines()
  local fn = tip[method]
  if not fn then return nil end
  local ok = pcall(fn, tip, ...)
  if not ok then return nil end
  local lines = {}
  for i = 1, tip:NumLines() do
    local l = _G["ForeverProbeTipTextLeft" .. i]
    local t = l and l:GetText()
    if t and t ~= "" then lines[#lines + 1] = t end
  end
  return lines
end

local function dump()
  local D = {}
  ForeverProbeDB = D
  D.when = date and date("%Y-%m-%d %H:%M:%S") or "?"

  -- Client identity: the first fact everything else hangs on.
  D.build = grab(function() return GetBuildInfo() end)
  D.interface = select(4, GetBuildInfo())

  -- Which of the APIs we care about exist at all.
  local names = {
    "C_Timer", "C_Map", "C_QuestLog", "C_Spell", "C_Item", "C_TradeSkillUI",
    "C_ClassTalents", "C_SpecializationInfo", "C_CurrencyInfo", "C_UnitAuras",
    "CombatLogGetCurrentEventInfo", "GetNumTalentTabs", "GetTalentInfo",
    "GetTalentTabInfo", "GetTalentPrereqs", "GetNumSpellTabs", "GetSpellTabInfo",
    "GetSpellBookItemName", "GetSpellName", "UnitXP", "UnitXPMax", "GetXPExhaustion",
    "GetNumBattlefieldScores", "GetBattlefieldScore", "GetBattlefieldWinner",
    "RequestBattlefieldScoreData", "GetBattlefieldInstanceRunTime",
    "IsActiveBattlefieldArena", "GetPVPLifetimeStats", "GetGuildInfo",
    "GetInventoryItemLink", "GetItemInfo", "GetContainerItemLink",
    "C_Container", "UnitGUID", "GetRealmName", "GetNormalizedRealmName",
    "math", "InterfaceOptionsFrame_OpenToCategory", "Settings",
  }
  D.api = {}
  for _, n in ipairs(names) do D.api[n] = _G[n] ~= nil end
  D.api["math.randomseed"] = math and math.randomseed ~= nil
  D.api["GetContainerItemLink_C"] = C_Container and C_Container.GetContainerItemLink ~= nil

  -- Every C_ namespace: the shape of the modern surface.
  D.c_namespaces = {}
  for k in pairs(_G) do
    if type(k) == "string" and string.sub(k, 1, 2) == "C_" then
      D.c_namespaces[#D.c_namespaces + 1] = k
    end
  end
  table.sort(D.c_namespaces)

  -- Who am I, and what does a GUID look like here.
  D.me = grab(function()
    return UnitName("player"), UnitLevel("player"), (select(2, UnitClass("player"))),
           (UnitRace and select(2, UnitRace("player"))), UnitFactionGroup and UnitFactionGroup("player"),
           GetRealmName and GetRealmName()
  end)
  D.guid = grab(function() return UnitGUID("player") end)
  D.xp = grab(function() return UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() end)

  -- THE prize: full talent trees with live values, if the classic API held.
  D.talents = {}
  if GetNumTalentTabs and GetTalentInfo then
    for t = 1, (GetNumTalentTabs() or 0) do
      local tab = { info = grab(function() return GetTalentTabInfo(t) end), talents = {} }
      local i = 1
      while i <= 60 do
        local r = grab(function() return GetTalentInfo(t, i) end)
        if not r[1] then break end
        r.tooltip = tipLines("SetTalent", t, i)
        r.prereq = GetTalentPrereqs and grab(function() return GetTalentPrereqs(t, i) end) or nil
        tab.talents[i] = r
        i = i + 1
      end
      D.talents[t] = tab
    end
  else
    D.talents.note = "no classic talent API; check C_ClassTalents / C_SpecializationInfo in c_namespaces"
  end

  -- Spellbook, with tooltip text: racials live in the General tab.
  D.spellbook = {}
  if GetNumSpellTabs and GetSpellTabInfo then
    for t = 1, (GetNumSpellTabs() or 0) do
      local name, _, offset, num = GetSpellTabInfo(t)
      local tab = { name = name, spells = {} }
      for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
        local sn, sr
        if GetSpellBookItemName then sn, sr = GetSpellBookItemName(i, "spell")
        elseif GetSpellName then sn, sr = GetSpellName(i, "spell") end
        if sn then
          local lines = tipLines("SetSpellBookItem", i, "spell") or tipLines("SetSpell", i, "spell")
          tab.spells[#tab.spells + 1] = { sn, sr or "", lines }
        end
      end
      D.spellbook[t] = tab
    end
  end

  -- What I am wearing, links and tooltips: the seed of the gear datamine.
  D.gear = {}
  for slot = 1, 19 do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if link then
      D.gear[slot] = { link = link, tooltip = tipLines("SetInventoryItem", "player", slot) }
    end
  end

  -- Combat log shape: modern payload accessor, or classic varargs?
  D.cleu = D.cleu or { events = 0 }
  D.cleu.modern = CombatLogGetCurrentEventInfo ~= nil

  say("dumped. Log out (or /reload) and send WTF/.../SavedVariables/ForeverProbe.lua")
  say("client: " .. table.concat({ tostring(D.build[1]), tostring(D.build[2]), "toc " .. tostring(D.interface) }, " / "))
end

-- Count combat-log arguments live: five events is enough to know the shape.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(f.RegisterEvent, f, "COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    pcall(dump)
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local D = ForeverProbeDB
    if not D or (D.cleu.events or 0) >= 5 then return end
    local n, sub
    if CombatLogGetCurrentEventInfo then
      local p = { CombatLogGetCurrentEventInfo() }
      n, sub = #p, tostring(p[2])
    else
      n, sub = select("#", ...), tostring((select(2, ...)))
    end
    D.cleu.events = (D.cleu.events or 0) + 1
    D.cleu[D.cleu.events] = { args = n, subevent = sub }
  end
end)

SLASH_FOREVERPROBE1 = "/probe"
SlashCmdList.FOREVERPROBE = function() pcall(dump) end
