-- SPDX-License-Identifier: GPL-3.0-or-later
-- Reminders, as small toasts at the top of the screen, each with a button that uses the item (a secure button: the
-- click is yours, QuestBank only sets what it uses). Four kinds, each with its own switch in Settings, all quiet in
-- a fight and, if asked, in dungeons:
--   camp   a campfire was lit (yours, or one you walk up to): the camp features your professions can place that you
--          carry, with what each gives, when the shared one-hour camp cooldown is up
--   food   Well Fed ran out and you carry food that gives it
--   bag    you stand still outdoors with the Cozy Sleeping Bag packed and fewer than three Well Rested stacks
--   buff   a camp buff you had ran out and the camp cooldown is up
-- What the game tells: your professions (GetProfessions), your bags (Game.ScanItems), your buffs (C_UnitAuras), the
-- spell a kit casts (D.CAMP[id].sp, seen on UNIT_SPELLCAST_SUCCEEDED), the campfire under your Interact key.
local _, QB = ...
local Camp = {}
QB.Camp = Camp

local STILL = 20          -- seconds standing still before the sleeping-bag reminder
local AGAIN = 600         -- seconds before the same reminder is shown again
local CAMP_CD = 3600      -- the shared camp cooldown
local TICK = 2            -- seconds between looks
local MAX_TOASTS = 3
Camp.STILL, Camp.AGAIN, Camp.CAMP_CD = STILL, AGAIN, CAMP_CD

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
local function settings()
  local s = QB:Settings()
  if type(s.remind) ~= "table" then s.remind = { camp = true, food = true, bag = true, buff = false, quietInstance = true } end
  return s.remind
end

-- your professions by name, with the skill
function Camp.Professions()
  local out = {}
  if not (GetProfessions and GetProfessionInfo) then return out end
  local ok, a, b, _, fish, cook, aid = pcall(GetProfessions)
  if not ok then return out end
  for _, i in ipairs({ a, b, fish, cook, aid }) do
    if i then
      local okI, name, _, skill = pcall(GetProfessionInfo, i)
      name, skill = plain(name), plain(skill)
      if okI and type(name) == "string" and type(skill) == "number" then out[name] = skill end
    end
  end
  return out
end

-- your helpful auras by name, and the stacks of one
function Camp.Buffs()
  local out = {}
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if get then
    for i = 1, 60 do
      local ok, a = pcall(get, "player", i, "HELPFUL")
      if not ok or type(a) ~= "table" then break end
      local n = plain(a.name)
      if type(n) == "string" then out[n] = plain(a.applications) or 1 end
    end
  end
  return out
end

local function carried()
  local set = {}
  for _, id in ipairs(QB.Game and QB.Game.ScanItems and QB.Game.ScanItems() or {}) do set[id] = true end
  return set
end

-- the camp features you carry and can place: your profession's skill meets the item's
function Camp.Placeable(bags, profs)
  bags, profs = bags or carried(), profs or Camp.Professions()
  local out = {}
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.t == "feature" and bags[id] and e.p and (profs[e.p] or 0) >= (e.s or 0) then out[#out + 1] = { id = id, e = e } end
  end
  table.sort(out, function(a, b) return (a.e.s or 0) > (b.e.s or 0) or ((a.e.s or 0) == (b.e.s or 0) and a.e.n < b.e.n) end)
  -- a higher tier makes its base pointless: keep the best of each profession
  local best, seen = {}, {}
  for _, x in ipairs(out) do if not seen[x.e.p] then seen[x.e.p] = true; best[#best + 1] = x end end
  return best
end

-- the foods you carry that make you Well Fed
function Camp.Foods(bags)
  bags = bags or carried()
  local out = {}
  for id, e in pairs(QB.Data.FOOD or {}) do if bags[id] then out[#out + 1] = { id = id, e = e } end end
  table.sort(out, function(a, b) return a.e.n < b.e.n end)
  return out
end

----------------------------------------------------------------------------
-- the toasts
----------------------------------------------------------------------------
local ART = "Interface\\AddOns\\QuestBank\\art\\"
local stack, toasts = nil, {}
local function stackFrame()
  if stack then return stack end
  stack = CreateFrame("Frame", "QuestBankToasts", UIParent)
  stack:SetSize(420, 10)
  stack:SetPoint("TOP", UIParent, "TOP", 0, -90)
  stack:SetFrameStrata("HIGH")
  return stack
end
local function toast(i)
  local t = toasts[i]
  if t then return t end
  t = CreateFrame("Frame", nil, stackFrame(), BackdropTemplateMixin and "BackdropTemplate" or nil)
  t:SetSize(420, 52)
  if t.SetBackdrop then
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    t:SetBackdropColor(0.06, 0.08, 0.11, 0.94)
    t:SetBackdropBorderColor(0.55, 0.42, 0.18, 1)
  end
  t.icon = t:CreateTexture(nil, "ARTWORK")
  t.icon:SetSize(36, 36)
  t.icon:SetPoint("LEFT", 8, 0)
  t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t.title:SetPoint("TOPLEFT", 52, -8)
  t.title:SetWidth(270); t.title:SetJustifyH("LEFT")
  t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.text:SetPoint("TOPLEFT", 52, -27)
  t.text:SetWidth(270); t.text:SetJustifyH("LEFT")
  t.text:SetTextColor(0.75, 0.7, 0.6)
  -- the Use button: secure, so the click is the player's own; set only out of combat
  t.use = CreateFrame("Button", nil, t, "SecureActionButtonTemplate")
  t.use:SetSize(64, 22)
  t.use:SetPoint("RIGHT", -30, 0)
  t.use:RegisterForClicks("AnyUp", "AnyDown")
  t.use.bg = t.use:CreateTexture(nil, "BACKGROUND")
  t.use.bg:SetAllPoints()
  t.use.bg:SetColorTexture(0.35, 0.2, 0.08, 0.95)
  t.use.label = t.use:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t.use.label:SetPoint("CENTER")
  t.close = CreateFrame("Button", nil, t)
  t.close:SetSize(20, 20)
  t.close:SetPoint("RIGHT", -6, 0)
  t.close.x = t.close:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  t.close.x:SetPoint("CENTER"); t.close.x:SetText("x")
  t.close:SetScript("OnClick", function(self) Camp.Dismiss(self:GetParent().key) end)
  t:Hide()
  toasts[i] = t
  return t
end

local shown = {}   -- key -> { title, text, icon, item, verb, at }
local lastShown = {} -- key -> time it was last put up (AGAIN)
local function layout()
  local y, n = 0, 0
  local keys = {}
  for k in pairs(shown) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return shown[a].at < shown[b].at end)
  for _, k in ipairs(keys) do
    n = n + 1
    if n > MAX_TOASTS then break end
    local d, t = shown[k], toast(n)
    t.key = k
    t.icon:SetTexture(d.icon and ("Interface\\Icons\\" .. d.icon) or 134400)
    t.title:SetText(d.title)
    t.text:SetText(d.text)
    if d.item and not (InCombatLockdown and InCombatLockdown()) then
      t.use:SetAttribute("type", "item")
      t.use:SetAttribute("item", "item:" .. d.item)
      t.use.label:SetText(d.verb or "Use")
      t.use:Show()
    else
      t.use:Hide()
    end
    t:ClearAllPoints()
    t:SetPoint("TOP", stackFrame(), "TOP", 0, -y)
    t:Show()
    y = y + 58
  end
  for i = n + 1, #toasts do toasts[i]:Hide() end
  Camp.visible = math.min(n, MAX_TOASTS)
end

function Camp.Show(key, d)
  local t = now()
  if shown[key] then return false end
  if lastShown[key] and t - lastShown[key] < AGAIN then return false end
  d.at = t
  shown[key], lastShown[key] = d, t
  layout()
  return true
end

function Camp.Dismiss(key)
  if not shown[key] then return end
  shown[key] = nil
  layout()
end

function Camp.Clear()
  shown = {}
  layout()
end

----------------------------------------------------------------------------
-- the rules
----------------------------------------------------------------------------
local campAt, fireAt, lastMove, lastPos, lastBuffs = nil, nil, nil, nil, {}

local function quiet()
  if InCombatLockdown and InCombatLockdown() then return true end
  if settings().quietInstance ~= false and IsInInstance then
    local ok, inside = pcall(IsInInstance)
    if ok and plain(inside) == true then return true end
  end
  return false
end

function Camp.CooldownLeft()
  if not campAt then return 0 end
  return math.max(0, CAMP_CD - (now() - campAt))
end

-- a campfire is here: yours lit, or one under your Interact key
function Camp.OnFire()
  fireAt = now()
  if not settings().camp or quiet() then return end
  if Camp.CooldownLeft() > 0 then return end
  local list = Camp.Placeable()
  if #list == 0 then return end
  local names = {}
  for i = 1, math.min(3, #list) do names[#names + 1] = list[i].e.n .. (list[i].e.g and (" (" .. list[i].e.g .. ")") or "") end
  local first = list[1]
  Camp.Show("camp", { title = string.format("A campfire is lit. You can place %d thing%s.", #list, #list == 1 and "" or "s"),
                      text = table.concat(names, " \194\183 ") .. (#list > 3 and " ..." or ""), icon = first.e.i, item = first.id, verb = "Place" })
end

function Camp.Look()
  if quiet() then Camp.Clear(); return end
  local s = settings()
  local buffs = Camp.Buffs()
  -- food
  if s.food and not buffs["Well Fed"] then
    local foods = Camp.Foods()
    if #foods > 0 then
      local f = foods[1]
      Camp.Show("food", { title = "Well Fed is gone.", text = f.e.n .. " in your bags: " .. (f.e.g or "Well Fed") .. ".", icon = f.e.i, item = f.id, verb = "Eat" })
    end
  elseif buffs["Well Fed"] then Camp.Dismiss("food") end
  -- the sleeping bag
  if s.bag then
    local me = QB.API.WorldPosition()
    if me and lastPos and math.abs(me.wx - lastPos.wx) + math.abs(me.wy - lastPos.wy) > 2 then lastMove = now() end
    if me then lastPos = me end
    lastMove = lastMove or now()
    local stacks = buffs["Well Rested"] or 0
    local bags = carried()
    if bags[211527] and stacks < 3 and now() - lastMove >= STILL and not (UnitOnTaxi and plain(UnitOnTaxi("player")) == true) then
      Camp.Show("bag", { title = "Standing still with the sleeping bag packed.", text = "Unfurl it: a minute inside is +XP, stacks to 3" .. (stacks > 0 and (" (you have " .. stacks .. ")") or "") .. ".", icon = "inv_misc_bag_cenarionherbbag", item = 211527, verb = "Unfurl" })
    elseif stacks >= 3 then Camp.Dismiss("bag") end
  end
  -- a camp buff ran out
  if s.buff then
    for name in pairs(lastBuffs) do
      if not buffs[name] and Camp.IsCampBuff(name) and Camp.CooldownLeft() == 0 then
        Camp.Show("buff", { title = name .. " ran out.", text = "The camp cooldown is up: place it again at a campfire.", icon = "spell_fire_fire" })
      end
    end
  end
  lastBuffs = buffs
end

-- the camp buffs carry their feature's name, as far as players' games have shown
function Camp.IsCampBuff(name)
  for _, e in pairs(QB.Data.CAMP or {}) do if e.t == "feature" and e.n == name then return true end end
  return false
end

local KIT, FEATURE = {}, {}
local function index()
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.sp then
      if e.t == "kit" then KIT[e.sp] = id elseif e.t == "feature" then FEATURE[e.sp] = id end
    end
  end
end

function Camp.OnEvent(event, a1, a2, a3)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if plain(a1) ~= "player" then return end
    local sp = plain(a3)
    if KIT[sp] then Camp.OnFire() end
    if FEATURE[sp] then campAt = now(); Camp.Dismiss("camp"); Camp.Dismiss("buff") end
  elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
    local name = plain(UnitName and UnitName("softinteract"))
    local guid = plain(UnitGUID and UnitGUID("softinteract"))
    if type(name) == "string" and type(guid) == "string" and guid:find("^GameObject") and name:lower():find("campfire", 1, true) then
      if not fireAt or now() - fireAt > 60 then Camp.OnFire() end
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    Camp.Clear()
  elseif event == "PLAYER_ENTERING_WORLD" then
    lastMove = now()
  end
end

function Camp:Init()
  if self.frame then return end
  index()
  local f = CreateFrame("Frame")
  self.frame = f
  f.elapsed = 0
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) Camp.OnEvent(event, ...) end, "reminders"))
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    Camp.Look()
  end, "reminders"))
  for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
    pcall(f.RegisterEvent, f, e)
  end
end
