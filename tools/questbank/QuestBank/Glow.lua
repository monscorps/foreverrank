-- SPDX-License-Identifier: GPL-3.0-or-later
-- A light on what your Interact key would use: gold for a quest object (one named in an objective of a quest in
-- your log, or that starts a quest) or a quest NPC (one with a quest for you to take or hand in), green for an herb,
-- orange for ore, blue for a chest, white for any other NPC (vendors, trainers) or plain object (off until asked
-- for). The game's soft targeting picks the thing ("softinteract"); its nameplate carries the light. Three styles:
-- "sparkle" (a soft glow with small sparkles orbiting and twinkling round it), "light" (the glow under a breathing
-- ring and a slow-turning sparkle) and "game" (nothing of QuestBank's: the game's own highlight on the nameplate,
-- with its health bar). Switching the light on sets the game's soft-interact settings so things all around you
-- within reach get a nameplate; the values they had are kept and put back when you switch it off or log out. Only
-- reads of units and cvar writes: nothing of the game's is replaced, and nothing is done in a fight.
local _, QB = ...
local Glow = {}
QB.Glow = Glow

-- the game's settings the light needs, and the values it sets
local CVARS = { SoftTargetInteract = "3", SoftTargetInteractArc = "2", SoftTargetInteractRange = "15",
                SoftTargetNameplateInteract = "1", SoftTargetIconInteract = "1" }
Glow.CVARS = CVARS
local COLORS = { quest = { 1, 0.82, 0.2 }, herb = { 0.35, 0.9, 0.35 }, ore = { 1, 0.55, 0.15 }, chest = { 0.35, 0.6, 1 },
                 other = { 0.9, 0.9, 0.9 }, npc = { 0.9, 0.9, 0.9 } }
Glow.COLORS = COLORS
local CHEST = { "chest", "cache", "crate", "barrel", "strongbox", "footlocker", "coffer", "lockbox", "stash", "satchel", "bag", "trunk", "urn", "supplies" }
-- the styles, in the order Settings offers them
Glow.STYLES = { "sparkle", "light", "game" }
local STYLE = { sparkle = true, light = true, game = true }

local plain = QB.Plain
-- the settings, with what an older save lacks filled in
local function settings()
  local s = QB:Settings()
  if type(s.glow) ~= "table" then s.glow = { on = true, other = true } end
  local g = s.glow
  if not STYLE[g.style] then g.style = "sparkle" end
  if g.npcs == nil then g.npcs = true end
  return g
end
Glow.Settings = settings

function Glow.Style() return settings().style end
function Glow.SetStyle(style)
  if not STYLE[style] then return false end
  settings().style = style
  Glow.Update()
  return true
end

-- the NPCs with quests, by name: who starts which quest (D.Q[id][7]) and who ends it ([6], or the Horde's own
-- hand-in where it has one), read once per data table and faction
local npcIndex, npcFor, npcFac
local function questNPCs()
  local D = QB.Data
  local fac = QB.faction or (QB.API and QB.API.Faction and QB.API.Faction()) or "A"
  if npcIndex and npcFor == D.Q and npcFac == fac then return npcIndex end
  npcIndex, npcFor, npcFac = {}, D.Q, fac
  local function note(idx, key, id)
    local n = idx and idx > 0 and D.NPC and D.NPC[idx]
    if not n then return end
    local e = npcIndex[n[1]]
    if not e then e = { give = {}, turn = {} }; npcIndex[n[1]] = e end
    local list = e[key]
    list[#list + 1] = id
  end
  for id, r in pairs(D.Q or {}) do
    local turn = r[6]
    if fac == "H" and D.TURNH and D.TURNH[id] then turn = D.TURNH[id] end
    note(r[7], "give", id)
    note(turn, "turn", id)
  end
  return npcIndex
end

-- a quest NPC: one that ends a quest in your log that is ready to hand in, or starts one you can take now
function Glow.QuestNPC(name)
  name = plain(name)
  if type(name) ~= "string" or name == "" then return false end
  local e = questNPCs()[name]
  if not e then return false end
  local log = QB.state and QB.state.log or {}
  for _, id in ipairs(e.turn) do
    local l = log[id]
    if l and l.complete then return true end
  end
  for _, id in ipairs(e.give) do
    if not log[id] then
      local q = QB.Quest.Get(id)
      local st = q and QB:Status(q)
      if st and st.code == "todo" and not st.behind then return true end
    end
  end
  return false
end

-- what kind of thing this is, by its name (and its guid: an NPC is "quest" or "npc")
function Glow.Kind(name, guid)
  name = plain(name)
  if type(name) ~= "string" or name == "" then return nil end
  guid = plain(guid)
  if type(guid) == "string" and guid:find("^Creature") then return Glow.QuestNPC(name) and "quest" or "npc" end
  local G = QB.Data.GATHER or {}
  if G[name] then return G[name] end
  -- a quest object: named in an objective of a quest in your log that is not finished
  local log = QB.state and QB.state.log or {}
  local lower = name:lower()
  for id in pairs(log) do
    for _, o in ipairs(QB.API.Objectives(id) or {}) do
      local t = plain(o.text)
      if type(t) == "string" and not o.done and t:lower():find(lower, 1, true) then return "quest" end
    end
  end
  for _, w in ipairs(CHEST) do if lower:find(w, 1, true) then return "chest" end end
  return "other"
end

local saved -- the cvars as they were before the light set them (settings.glow.saved survives a crash)
local function setCVars()
  if not (GetCVar and SetCVar) then return end
  local g = settings()
  g.saved = g.saved or {}
  for name, want in pairs(CVARS) do
    local ok, v = pcall(GetCVar, name)
    v = ok and plain(v) or nil
    if v ~= nil and g.saved[name] == nil then g.saved[name] = v end
    if v ~= want then pcall(SetCVar, name, want) end
  end
  saved = g.saved
end

local function restoreCVars()
  local g = settings()
  if not (SetCVar and type(g.saved) == "table") then g.saved = nil; return end
  for name, v in pairs(g.saved) do pcall(SetCVar, name, v) end
  g.saved = nil
  saved = nil
end

-- the light's art: QuestBank's own textures (art/, drawn by make_art.py)
local ART = "Interface\\AddOns\\QuestBank\\art\\"
-- the sparkles of the sparkle style: each on its own orbit (r its radius, w its turn in radians a second, a0 where
-- it starts), twinkling at its own pace (f, p) and size (s). A fixed set, so the burst looks the same at every
-- object, and the client's own random is never needed
local SPARKS = {
  { r = 26, w = 0.45, a0 = 0.0, f = 2.6, p = 0.0, s = 16 },
  { r = 19, w = -0.6, a0 = 0.9, f = 3.1, p = 1.1, s = 13 },
  { r = 30, w = 0.35, a0 = 1.8, f = 2.2, p = 2.3, s = 18 },
  { r = 16, w = -0.8, a0 = 2.7, f = 3.6, p = 0.6, s = 11 },
  { r = 23, w = 0.55, a0 = 3.6, f = 2.9, p = 1.7, s = 14 },
  { r = 32, w = -0.4, a0 = 4.5, f = 2.4, p = 2.9, s = 17 },
  { r = 21, w = 0.7, a0 = 5.4, f = 3.3, p = 0.3, s = 12 },
}
Glow.SPARKS = SPARKS
local SQUASH = 0.55 -- the orbits lie flat round the object, as a ring on the ground is seen

local light
local function lightFrame()
  if light then return light end
  light = CreateFrame("Frame", "QuestBankGlow", UIParent)
  light:SetSize(64, 64)
  light:SetFrameStrata("BACKGROUND")
  local function tex(layer, size, file)
    local t = light:CreateTexture(nil, layer)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    t:SetTexture(ART .. file)
    t:SetBlendMode("ADD")
    return t
  end
  light.core = tex("BACKGROUND", 80, "glow.tga")
  light.ring = tex("ARTWORK", 46, "ring.tga")
  light.spark = tex("OVERLAY", 54, "sparkle.tga")
  light.sparks = {}
  for i, sp in ipairs(SPARKS) do light.sparks[i] = tex("OVERLAY", sp.s, "sparkle.tga") end
  light.t = 0
  light.style = "light"
  light:SetScript("OnUpdate", function(self, dt) Glow.Animate(self, dt) end)
  light:Hide()
  return light
end

-- one frame of the light. The light style breathes its glow and ring and turns its sparkle. The sparkle style
-- breathes its glow and carries each sparkle round its orbit, twinkling: it swells and brightens, then fades to a
-- speck, each at its own pace, turning slowly as it goes
function Glow.Animate(self, dt)
  self.t = self.t + (dt or 0)
  if self.t > 36000 then self.t = self.t - 36000 end
  local t = self.t
  local breath = 0.5 + 0.5 * math.sin(t * 3)
  if self.style == "sparkle" then
    self.core:SetAlpha(0.3 + 0.16 * breath)
    for i, sp in ipairs(SPARKS) do
      local tx = self.sparks[i]
      local ang = sp.a0 + t * sp.w
      local tw = 0.5 + 0.5 * math.sin(t * sp.f + sp.p)
      tw = tw * tw
      local size = sp.s * (0.6 + 0.7 * tw)
      tx:SetSize(size, size)
      tx:SetPoint("CENTER", self, "CENTER", sp.r * math.cos(ang), sp.r * SQUASH * math.sin(ang))
      tx:SetAlpha(0.12 + 0.88 * tw)
      if tx.SetRotation then tx:SetRotation(t * (sp.w > 0 and 0.5 or -0.5) + sp.a0) end
    end
    return
  end
  self.core:SetAlpha(0.28 + 0.18 * breath)
  self.ring:SetAlpha(0.55 + 0.35 * breath)
  self.ring:SetSize(42 + 8 * breath, 42 + 8 * breath)
  self.spark:SetAlpha(0.7 + 0.3 * (1 - breath))
  if self.spark.SetRotation then self.spark:SetRotation(t * 0.6) end
end

-- the style's parts shown, in the kind's colour (the sparkles a shade brighter, as a spark is)
local function dress(f, style, kind)
  local c = COLORS[kind] or COLORS.other
  local b1, b2, b3 = math.min(1, c[1] + 0.3), math.min(1, c[2] + 0.3), math.min(1, c[3] + 0.3)
  f.core:SetVertexColor(c[1], c[2], c[3])
  f.ring:SetVertexColor(c[1], c[2], c[3])
  f.spark:SetVertexColor(b1, b2, b3)
  local sparkle = style == "sparkle"
  f.ring:SetShown(not sparkle)
  f.spark:SetShown(not sparkle)
  for _, t in ipairs(f.sparks) do
    t:SetVertexColor(b1, b2, b3)
    t:SetShown(sparkle)
  end
  if f.style ~= style then f.style = style; Glow.Animate(f, 0) end
end

-- the light goes on the soft-interact target's nameplate; without one there is no place on screen for it
function Glow.Update()
  local g = settings()
  local f = lightFrame()
  local function off(kind) f:Hide(); Glow.kind = kind end
  -- the game's own style draws nothing of QuestBank's; the soft-interact settings still show the game's highlight
  if not g.on or g.style == "game" then return off(nil) end
  if InCombatLockdown and InCombatLockdown() and g.combat ~= true then return off(nil) end
  if not (UnitExists and plain(UnitExists("softinteract")) == true) then return off(nil) end
  -- an object or an NPC; anything else (a player, a pet, a vehicle) keeps the game's own cursor icon and nothing more
  local guid = plain(UnitGUID and UnitGUID("softinteract"))
  local isNPC = type(guid) == "string" and guid:find("^Creature") ~= nil
  if type(guid) == "string" and not isNPC and not guid:find("^GameObject") then return off(nil) end
  if isNPC and not g.npcs then return off(nil) end
  local name = plain(UnitName and UnitName("softinteract"))
  local kind = Glow.Kind(name, guid) or (isNPC and "npc" or "other")
  if kind == "other" and not g.other then return off(nil) end
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and select(2, pcall(C_NamePlate.GetNamePlateForUnit, "softinteract"))
  if type(plate) ~= "table" then return off(kind) end
  dress(f, g.style, kind)
  f:SetParent(plate)
  f:ClearAllPoints()
  f:SetPoint("CENTER", plate, "CENTER", 0, -10)
  f:SetFrameLevel((plate.GetFrameLevel and plate:GetFrameLevel() or 1) + 1)
  f:Show()
  Glow.kind, Glow.name = kind, name
end

function Glow.Set(on)
  local g = settings()
  g.on = on and true or false
  if g.on then setCVars() else restoreCVars() end
  Glow.Update()
end

function Glow:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event)
    if event == "PLAYER_LOGOUT" then if settings().on then restoreCVars() end return end
    if event == "PLAYER_ENTERING_WORLD" and settings().on then setCVars() end
    Glow.Update()
  end, "glow"))
  for _, e in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
                       "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "QUEST_LOG_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
  end
end
