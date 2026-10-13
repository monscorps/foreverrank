-- SPDX-License-Identifier: GPL-3.0-or-later
-- A light on the object your Interact key would use: gold for a quest object (one named in an objective of a quest
-- in your log, or that starts a quest), green for an herb, orange for ore, blue for a chest, white for anything else
-- (off until asked for). The game's soft targeting picks the object ("softinteract"); its nameplate carries the
-- light. Switching the light on sets the game's soft-interact settings so objects all around you within reach get
-- a nameplate; the values they had are kept and put back when you switch it off or log out. Only reads of units and
-- cvar writes: nothing of the game's is replaced, and nothing is done in a fight.
local _, QB = ...
local Glow = {}
QB.Glow = Glow

-- the game's settings the light needs, and the values it sets
local CVARS = { SoftTargetInteract = "3", SoftTargetInteractArc = "2", SoftTargetInteractRange = "15",
                SoftTargetNameplateInteract = "1", SoftTargetIconInteract = "1" }
Glow.CVARS = CVARS
local COLORS = { quest = { 1, 0.82, 0.2 }, herb = { 0.35, 0.9, 0.35 }, ore = { 1, 0.55, 0.15 }, chest = { 0.35, 0.6, 1 }, other = { 0.9, 0.9, 0.9 } }
Glow.COLORS = COLORS
local CHEST = { "chest", "cache", "crate", "barrel", "strongbox", "footlocker", "coffer", "lockbox", "stash", "satchel", "bag", "trunk", "urn", "supplies" }

local plain = QB.Plain
local function settings()
  local s = QB:Settings()
  if type(s.glow) ~= "table" then s.glow = { on = true, other = true } end
  return s.glow
end

-- what kind of thing this is, by its name
function Glow.Kind(name)
  name = plain(name)
  if type(name) ~= "string" or name == "" then return nil end
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

-- the light: a soft glow under a slow-turning sparkle and a breathing ring, QuestBank's own textures (art/)
local ART = "Interface\\AddOns\\QuestBank\\art\\"
local light
local function lightFrame()
  if light then return light end
  light = CreateFrame("Frame", "QuestBankGlow", UIParent)
  light:SetSize(64, 64)
  light:SetFrameStrata("BACKGROUND")
  light.core = light:CreateTexture(nil, "BACKGROUND")
  light.core:SetSize(80, 80)
  light.core:SetPoint("CENTER")
  light.core:SetTexture(ART .. "glow.tga")
  light.core:SetBlendMode("ADD")
  light.ring = light:CreateTexture(nil, "ARTWORK")
  light.ring:SetSize(46, 46)
  light.ring:SetPoint("CENTER")
  light.ring:SetTexture(ART .. "ring.tga")
  light.ring:SetBlendMode("ADD")
  light.spark = light:CreateTexture(nil, "OVERLAY")
  light.spark:SetSize(54, 54)
  light.spark:SetPoint("CENTER")
  light.spark:SetTexture(ART .. "sparkle.tga")
  light.spark:SetBlendMode("ADD")
  light.t = 0
  light:SetScript("OnUpdate", function(self, dt)
    self.t = self.t + (dt or 0)
    local breath = 0.5 + 0.5 * math.sin(self.t * 3)
    self.core:SetAlpha(0.28 + 0.18 * breath)
    self.ring:SetAlpha(0.55 + 0.35 * breath)
    self.ring:SetSize(42 + 8 * breath, 42 + 8 * breath)
    self.spark:SetAlpha(0.7 + 0.3 * (1 - breath))
    if self.spark.SetRotation then self.spark:SetRotation(self.t * 0.6) end
  end)
  light:Hide()
  return light
end

-- the light goes on the soft-interact target's nameplate; without one there is no place on screen for it
function Glow.Update()
  local g = settings()
  local f = lightFrame()
  if not g.on or (InCombatLockdown and InCombatLockdown() and g.combat ~= true) then f:Hide(); Glow.kind = nil; return end
  if not (UnitExists and plain(UnitExists("softinteract")) == true) then f:Hide(); Glow.kind = nil; return end
  -- objects only: an NPC you could talk to keeps the game's own cursor icon and nothing more
  local guid = plain(UnitGUID and UnitGUID("softinteract"))
  if type(guid) == "string" and not guid:find("^GameObject") then f:Hide(); Glow.kind = nil; return end
  local name = plain(UnitName and UnitName("softinteract"))
  local kind = Glow.Kind(name) or "other"
  if kind == "other" and not g.other then f:Hide(); Glow.kind = nil; return end
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and select(2, pcall(C_NamePlate.GetNamePlateForUnit, "softinteract"))
  if type(plate) ~= "table" then f:Hide(); Glow.kind = kind; return end
  local c = COLORS[kind]
  f.ring:SetVertexColor(c[1], c[2], c[3])
  f.core:SetVertexColor(c[1], c[2], c[3])
  f.spark:SetVertexColor(math.min(1, c[1] + 0.3), math.min(1, c[2] + 0.3), math.min(1, c[3] + 0.3))
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
