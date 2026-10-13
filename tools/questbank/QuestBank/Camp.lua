-- SPDX-License-Identifier: GPL-3.0-or-later
-- The camp bar: a row of icons, the way a WeakAura shows a buff, up whenever one of them has something to say. Each
-- icon is the game's secure button for its item, so a click is yours: QuestBank only sets which item it uses, and
-- only out of a fight. Each has its own switch in Settings:
--   food   Well Fed with its minutes; gone: the food you carry that gives it, lit, a click eats it; none: grey
--   fire   the campfire kit you carry and how many; a click lights it
--   camp   the best camp feature you can place: the shared one-hour cooldown as a sweep, lit when a campfire is near
--          and the cooldown is up; a click places it
--   bag    the Cozy Sleeping Bag with your Well Rested stacks, lit when you stand still under three; a click unfurls it
-- Alt-drag moves the bar. In a fight it dims and keeps its buttons as they are; in dungeons it hides if asked.
-- What the game tells: your professions (GetProfessions), your bags (Game.ScanItems), your buffs (C_UnitAuras), the
-- spell a kit casts (D.CAMP[id].sp, seen on UNIT_SPELLCAST_SUCCEEDED), the campfire under your Interact key.
local _, QB = ...
local Camp = {}
QB.Camp = Camp

local STILL = 20          -- seconds standing still before the sleeping bag lights
local CAMP_CD = 3600      -- the shared camp cooldown
local TICK = 2            -- seconds between looks
Camp.STILL, Camp.CAMP_CD = STILL, CAMP_CD

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
local function settings()
  local s = QB:Settings()
  if type(s.remind) ~= "table" then s.remind = { camp = true, food = true, bag = true, fire = true, quietInstance = true } end
  if s.remind.fire == nil then s.remind.fire = true end
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

-- your helpful auras by name: the stacks of one (Camp.Buffs), or what the game says of it (Camp.Auras: stacks, when
-- it runs out on GetTime's clock, its icon)
function Camp.Auras()
  local out = {}
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if get then
    for i = 1, 60 do
      local ok, a = pcall(get, "player", i, "HELPFUL")
      if not ok or type(a) ~= "table" then break end
      local n = plain(a.name)
      if type(n) == "string" then
        local exp = plain(a.expirationTime)
        out[n] = { n = plain(a.applications) or 1, exp = type(exp) == "number" and exp > 0 and exp or nil, icon = plain(a.icon) }
      end
    end
  end
  return out
end
function Camp.Buffs()
  local out = {}
  for n, a in pairs(Camp.Auras()) do out[n] = a.n end
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

-- the campfire kits you carry, the best first
function Camp.Kits(bags)
  bags = bags or carried()
  local out = {}
  for id, e in pairs(QB.Data.CAMP or {}) do if e.t == "kit" and bags[id] then out[#out + 1] = { id = id, e = e } end end
  table.sort(out, function(a, b) return (a.e.s or 0) > (b.e.s or 0) end)
  return out
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
-- the bar
----------------------------------------------------------------------------
local ART = "Interface\\AddOns\\QuestBank\\art\\"
local SIZE, GAP = 40, 6
local ORDER = { "food", "fire", "camp", "bag" }
local bar, icons = nil, {}
local campAt, fireAt, lastMove, lastPos

local function quiet()
  if settings().quietInstance ~= false and IsInInstance then
    local ok, inside = pcall(IsInInstance)
    if ok and plain(inside) == true then return true end
  end
  return false
end
local function fighting() return InCombatLockdown and InCombatLockdown() or false end

local function barFrame()
  if bar then return bar end
  bar = CreateFrame("Frame", "QuestBankCampBar", UIParent)
  bar:SetSize(SIZE, SIZE)
  bar:SetFrameStrata("MEDIUM")
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  local pos = settings().pos
  if type(pos) == "table" and pos.x then bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y) else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -190) end
  bar.elapsed = 0
  return bar
end

local function moveStart(_, button)
  if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() and not fighting() then bar:StartMoving(); bar.moving = true end
end
local function moveStop()
  if not bar.moving then return end
  bar.moving = nil
  bar:StopMovingOrSizing()
  local x, y = bar:GetCenter()
  if x then settings().pos = { x = x, y = y } end
end

local function icon(key)
  local b = icons[key]
  if b then return b end
  b = CreateFrame("Button", "QuestBankCamp_" .. key, barFrame(), "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("alt-type1", "noop") -- Alt-click moves the bar, never uses the item
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(0, 0, 0, 1)
  b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.glow:SetTexture(ART .. "glow")
  b.glow:SetBlendMode("ADD")
  b.glow:SetPoint("CENTER")
  b.glow:SetSize(SIZE * 1.9, SIZE * 1.9)
  b.glow:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.time:SetPoint("BOTTOM", 0, 2)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("TOPRIGHT", -2, -2)
  b.hi = b:CreateTexture(nil, "HIGHLIGHT")
  b.hi:SetAllPoints()
  b.hi:SetColorTexture(1, 1, 1, 0.12)
  b:HookScript("OnMouseDown", moveStart)
  b:HookScript("OnMouseUp", moveStop)
  b:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.tip[1], 1, 0.82, 0.3)
    for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end
    GameTooltip:AddLine("Alt-drag moves the bar.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  icons[key] = b
  return b
end

local function mins(sec)
  if not sec or sec <= 0 then return "" end
  if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600 + 0.5)) end
  if sec >= 60 then return string.format("%dm", math.ceil(sec / 60)) end
  return string.format("%ds", math.ceil(sec))
end

local function itemCD(id)
  local get = C_Container and C_Container.GetItemCooldown
  if not (get and id) then return 0, 0 end
  local ok, start, dur = pcall(get, id)
  start, dur = ok and plain(start) or 0, ok and plain(dur) or 0
  if type(start) ~= "number" or type(dur) ~= "number" or dur <= 1.5 then return 0, 0 end
  return start, dur
end

local function count(id)
  local get = C_Item and C_Item.GetItemCount or GetItemCount
  local ok, n = pcall(get, id)
  n = ok and plain(n) or 0
  return type(n) == "number" and n or 0
end

-- what each icon shows now: nil to hide it, else { tex, time, count, lit, grey, item, cd = { start, dur }, tip }
function Camp.State()
  local s = settings()
  local out = {}
  local auras, bags, t = Camp.Auras(), carried(), now()
  if s.food then
    local fed = auras["Well Fed"]
    if fed then
      out.food = { tex = fed.icon or 136000, time = fed.exp and mins(fed.exp - t) or "", tip = { "Well Fed", fed.exp and ("Runs out in " .. mins(fed.exp - t) .. ".") or "" } }
    else
      local foods = Camp.Foods(bags)
      local f = foods[1]
      if f then
        out.food = { tex = "Interface\\Icons\\" .. f.e.i, count = count(f.id), lit = true, item = f.id,
                     tip = { "Not Well Fed", f.e.n .. ": " .. (f.e.g or "Well Fed") .. ". Click to eat." } }
      else
        out.food = { tex = 133945, grey = true, tip = { "Not Well Fed", "No food in your bags that gives Well Fed." } }
      end
    end
  end
  local cdStart, cdDur = 0, 0
  if s.camp then
    local list = Camp.Placeable(bags)
    local best = list[1]
    if best then
      cdStart, cdDur = itemCD(best.id)
      if cdDur == 0 and campAt and t - campAt < CAMP_CD then cdStart, cdDur = campAt, CAMP_CD end
      local up = cdDur == 0 or (cdStart + cdDur - t) <= 0
      local near = fireAt and t - fireAt < 300
      local names = {}
      for i = 1, math.min(4, #list) do names[#names + 1] = list[i].e.n .. (list[i].e.g and (": " .. list[i].e.g) or "") end
      out.camp = { tex = "Interface\\Icons\\" .. best.e.i, lit = up and near, grey = not up, item = best.id, cd = (not up) and { cdStart, cdDur } or nil,
                   time = (not up) and mins(cdStart + cdDur - t) or "",
                   tip = { up and (near and "Place a camp feature" or "Camp features ready") or ("Camp cooldown: " .. mins(cdStart + cdDur - t)),
                           table.concat(names, "\n"), up and (near and "Click to place the first." or "Light a campfire, then click to place the first.") or "All camp features share an hour's cooldown." } }
    end
  end
  if s.fire then
    local kits = Camp.Kits(bags)
    local k = kits[1]
    if k then
      out.fire = { tex = "Interface\\Icons\\" .. k.e.i, count = count(k.id), item = k.id, lit = out.camp and not out.camp.grey and not (fireAt and t - fireAt < 300),
                   tip = { k.e.n, string.format("Holds %d camp feature%s. Click to light it.", k.e.cap or 3, (k.e.cap or 3) == 1 and "" or "s") } }
    end
  end
  if s.bag and bags[211527] then
    local me = QB.API.WorldPosition()
    if me and lastPos and math.abs(me.wx - lastPos.wx) + math.abs(me.wy - lastPos.wy) > 2 then lastMove = t end
    if me then lastPos = me end
    lastMove = lastMove or t
    local rested = auras["Well Rested"]
    local stacks = rested and rested.n or 0
    local still = t - lastMove >= STILL and not (UnitOnTaxi and plain(UnitOnTaxi("player")) == true)
    out.bag = { tex = "Interface\\Icons\\" .. ((QB.Data.CAMP[211527] or {}).i or "inv_misc_bag_bigbagofenchantments"), count = stacks > 0 and stacks or nil,
                time = rested and rested.exp and mins(rested.exp - t) or "", lit = stacks < 3 and still, grey = stacks == 0 and not still, item = 211527,
                tip = { "Well Rested " .. stacks .. "/3", "A minute in the Cozy Sleeping Bag adds a stack of bonus XP. Click to unfurl it." } }
  end
  return out
end

function Camp.Refresh()
  local f = barFrame()
  if quiet() then
    if not fighting() then f:Hide() end
    Camp.visible = 0
    return
  end
  local fight = fighting()
  local st = Camp.State()
  local x, n = 0, 0
  for _, key in ipairs(ORDER) do
    local d, b = st[key], icon(key)
    if d then
      n = n + 1
      b.icon:SetTexture(d.tex)
      b.icon:SetDesaturated(d.grey and true or false)
      b.icon:SetAlpha(d.grey and 0.55 or 1)
      b.time:SetText(d.time or "")
      b.count:SetText(d.count and d.count > 1 and tostring(d.count) or (key == "bag" and d.count and tostring(d.count) or ""))
      b.glow:SetShown(d.lit and true or false)
      b.edge:SetColorTexture(d.lit and 1 or 0, d.lit and 0.75 or 0, d.lit and 0.2 or 0, 1)
      if d.cd then b.cd:SetCooldown(d.cd[1], d.cd[2]) else b.cd:SetCooldown(0, 0) end
      b.tip = d.tip
      b.state = d
      if not fight then
        b:SetAttribute("type", d.item and "item" or nil)
        b:SetAttribute("item", d.item and ("item:" .. d.item) or nil)
        b:ClearAllPoints()
        b:SetPoint("LEFT", f, "LEFT", x, 0)
        b:Show()
      end
      x = x + SIZE + GAP
    elseif not fight then
      b:Hide()
    end
  end
  if not fight then
    f:SetSize(math.max(SIZE, x - GAP), SIZE)
    f:SetShown(n > 0 and QB:Settings().campBar ~= false)
  end
  f:SetAlpha(fight and 0.45 or 1)
  Camp.visible = (QB:Settings().campBar ~= false) and n or 0
end

function Camp.CooldownLeft()
  if not campAt then return 0 end
  return math.max(0, CAMP_CD - (now() - campAt))
end

-- a campfire is here: yours lit, or one under your Interact key
function Camp.OnFire()
  fireAt = now()
  Camp.Refresh()
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
    if FEATURE[sp] then campAt = now(); Camp.Refresh() end
  elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
    local name = plain(UnitName and UnitName("softinteract"))
    local guid = plain(UnitGUID and UnitGUID("softinteract"))
    if type(name) == "string" and type(guid) == "string" and guid:find("^GameObject") and name:lower():find("campfire", 1, true) then
      if not fireAt or now() - fireAt > 60 then Camp.OnFire() end
    end
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "BAG_UPDATE_DELAYED" then
    Camp.Refresh()
  elseif event == "PLAYER_ENTERING_WORLD" then
    lastMove = now()
    Camp.Refresh()
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
    Camp.Refresh()
  end, "camp bar"))
  for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                       "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" }) do
    pcall(f.RegisterEvent, f, e)
  end
end
