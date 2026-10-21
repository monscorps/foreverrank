-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cards: one card, the core's (the run report's design, 8.1 and 8.2). A card is a guild member with a label, a title, a
-- line and a value; a run report's awards are cards, and so will the halls, the records and the achievements be. It
-- reads nothing of runs: CardFrame.lua lays cards out, Runs.lua and the others say what is on them.
--   Cards.Make(parent)    a card, 180 x 372 units
--   Cards.Fill(card, c)   c = { guid, name, class, race, sex, kind, label, title, line, value, valueLabel, headline, tip }
--   Cards.Find(guid)      the unit to draw a member by: player, partyN or raidN, target, focus, mouseover, nameplate1
--                         to 40; only one UnitIsVisible says is in sight and whose identity is plain
--                         (C_Secrets.ShouldUnitIdentityBeSecret; SetUnit is RequiresDeclassifiedUnitIdentity)
-- The picture: the member's own model where a unit shows them (a PlayerModel, the frame type Blizzard_Communities'
-- GuildNews uses on this client: SetUnit, then the pose); else the race model (the race's base model by display id,
-- SetDisplayInfo, as GuildNews draws its bosses), once a tester has seen it draw in game (17: Settings off until then);
-- else the icons: the class colour over the picture, the race's portrait and the class icon. There is no model by GUID
-- on this client, so a member out of sight never shows their own look.
local _, C = ...
local Cards = {}
C.Cards = Cards

-- two tokens beside the windows design's palette, on cards alone (their 3 px bar and their label): STAR, Cute's pink,
-- for GOLD STAR (and later GUILD FIRST and RECORD); BLOOPER for bloopers. Every other kind an EDGE bar, its label WHITE
Cards.STAR = { 0.949, 0.541, 0.816 }      -- #F28AD0
Cards.BLOOPER = { 0.941, 0.486, 0.353 }   -- #F07C5A
Cards.EDGE = { 0.42, 0.42, 0.42 }         -- #6B6B6B
Cards.GROUP = { 0.31, 0.82, 0.77 }        -- #4FD1C4, the dungeons-and-raids category's
local WHITE, INK, DIM = { 0.96, 0.96, 0.96 }, { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }
local PANEL, PANEL2, LINE = { 0.07, 0.07, 0.07 }, { 0.11, 0.11, 0.11 }, { 0.2, 0.2, 0.2 }
function Cards.KindColor(kind)
  if kind == "star" then return Cards.STAR end
  if kind == "blooper" then return Cards.BLOOPER end
  return nil
end

Cards.W, Cards.H = 180, 372

----------------------------------------------------------------------------
-- the game's art, by file id (research/wago/1.60.1.70338/ManifestInterfaceData.csv): the race portraits
-- (Interface\ICONS\Achievement_Character_<Race>_<Sex>, 236439-236458) and the class icons (ClassIcon_<Class>,
-- 625998-626008, 1260827). The races by the clientFileString the game gives (UnitRace's second return,
-- C_CreatureInfo.GetRaceInfo, GetPlayerInfoByGUID's englishRace); the game's file names say Undead for Scourge
----------------------------------------------------------------------------
local PORTRAIT = { BloodElf = { 236440, 236439 }, Draenei = { 236442, 236441 }, Dwarf = { 236444, 236443 }, Gnome = { 236446, 236445 },
  Human = { 236448, 236447 }, NightElf = { 236450, 236449 }, Orc = { 236452, 236451 }, Tauren = { 236454, 236453 }, Troll = { 236456, 236455 },
  Scourge = { 236458, 236457 } }
local CLASS_ICON = { DEATHKNIGHT = 625998, DRUID = 625999, HUNTER = 626000, MAGE = 626001, MONK = 626002, PALADIN = 626003, PRIEST = 626004,
  ROGUE = 626005, SHAMAN = 626006, WARLOCK = 626007, WARRIOR = 626008, DEMONHUNTER = 1260827 }
-- the race's base model, male and female, from the client's ChrRaceXChrModel and ChrModel tables (1.60.1.70338): the
-- game's structure, like the class list
local RACE_MODEL = { Human = { 57899, 56658 }, Orc = { 51894, 53762 }, Dwarf = { 49242, 53768 }, NightElf = { 54918, 54439 },
  Scourge = { 54041, 56327 }, Tauren = { 55077, 56316 }, Gnome = { 51877, 53291 }, Troll = { 59071, 59223 }, BloodElf = { 62127, 62128 },
  Draenei = { 57027, 58232 } }
Cards.PORTRAIT, Cards.CLASS_ICON, Cards.RACE_MODEL = PORTRAIT, CLASS_ICON, RACE_MODEL
local function sexIndex(sex) if sex == 2 then return 1 elseif sex == 3 then return 2 end end
function Cards.Portrait(race, sex) local p = PORTRAIT[race or ""]; local i = sexIndex(sex); return p and i and p[i] or nil end
function Cards.RaceModel(race, sex) local p = RACE_MODEL[race or ""]; local i = sexIndex(sex); return p and i and p[i] or nil end
-- the race model draws only where a tester saw it draw in game (CuteDB.settings.raceModel, /cute run model on)
function Cards.RaceModelOn() return CuteDB ~= nil and type(CuteDB.settings) == "table" and CuteDB.settings.raceModel == true end

----------------------------------------------------------------------------
-- a member's unit and race
----------------------------------------------------------------------------
local function callable(name) return type(_G[name]) == "function" end
local function call(name, ...) if not callable(name) then return nil end return C.Get(_G[name], ...) end
local UNITS = { "player" }
for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end
for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end
for _, u in ipairs({ "target", "focus", "mouseover" }) do UNITS[#UNITS + 1] = u end
for i = 1, 40 do UNITS[#UNITS + 1] = "nameplate" .. i end
local function usable(unit)
  if call("UnitIsVisible", unit) ~= true then return false end
  local S = C_Secrets
  if type(S) == "table" and type(S.ShouldUnitIdentityBeSecret) == "function" and C.Get(S.ShouldUnitIdentityBeSecret, unit) ~= false then return false end
  return true
end
function Cards.Find(guid)
  if type(guid) ~= "string" then return nil end
  if guid == C.MyGUID() then return "player" end
  for _, u in ipairs(UNITS) do
    if call("UnitGUID", u) == guid and usable(u) then return u end
  end
  return nil
end
-- a member's race and sex where the card's own data lacks them: GetPlayerInfoByGUID (englishRace, sex: 2 male, 3
-- female; PlayerScriptDocumentation.lua), then the member's own Cute record (the hidden sex beside the GUID)
function Cards.RaceSex(guid, race, sex)
  if (not race or not sex) and type(guid) == "string" and callable("GetPlayerInfoByGUID") then
    local _, _, _, eng, s = C.Get(GetPlayerInfoByGUID, guid)
    race = race or (type(eng) == "string" and eng ~= "" and eng or nil)
    sex = sex or ((s == 2 or s == 3) and s or nil)
  end
  if not sex and type(guid) == "string" and C.Roster and C.Roster.KeysByGuid then
    local key = C.Roster:KeysByGuid()[guid]
    local e = key and CuteDB and CuteDB.roster and CuteDB.roster[key]
    local s = type(e) == "table" and type(e.stats) == "table" and e.stats.sex or nil
    if s == 2 or s == 3 then sex = s end
  end
  return race, sex
end
-- your own sex beside your GUID in your record (core: every card of you out of range draws by it)
local own = CreateFrame("Frame")
own:RegisterEvent("PLAYER_ENTERING_WORLD")
own:SetScript("OnEvent", C.Safe(function()
  local s = call("UnitSex", "player")
  if (s == 2 or s == 3) and C.Sample then C.Sample.values.sex = s end
end, "cards: sex"))

----------------------------------------------------------------------------
-- the card
----------------------------------------------------------------------------
local FLAT = "Interface\\Buttons\\WHITE8x8"
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local function UI() return C.UI end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
function Cards.Make(parent)
  local U = UI()
  local f = CreateFrame("Frame", nil, parent, BD)
  f:SetSize(Cards.W, Cards.H)
  U.Skin(f, PANEL2)
  f:EnableMouse(true)
  f.bar = U.Flat(f, "ARTWORK", Cards.EDGE, 1)
  f.bar:SetPoint("TOPLEFT", 1, -1)
  f.bar:SetPoint("TOPRIGHT", -1, -1)
  f.bar:SetHeight(3)
  f.label = U.Text(f, 11, WHITE, "CENTER", 168)
  f.label:SetPoint("TOP", 0, -10)
  -- the picture: 172 x 200 at x 4, y 28
  f.pic = CreateFrame("Frame", nil, f)
  f.pic:SetSize(172, 200)
  f.pic:SetPoint("TOPLEFT", 4, -28)
  f.picBg = U.Flat(f.pic, "BACKGROUND", PANEL, 1)
  f.picBg:SetAllPoints()
  f.tint = U.Flat(f.pic, "BORDER", WHITE, 0.15)
  f.tint:SetAllPoints()
  f.model = CreateFrame("PlayerModel", nil, f.pic)
  f.model:SetAllPoints()
  f.portraitEdge = U.Flat(f.pic, "ARTWORK", { 0, 0, 0 }, 1)
  f.portraitEdge:SetSize(98, 98)
  f.portraitEdge:SetPoint("CENTER", f.pic, "TOP", 0, -70)
  f.portrait = f.pic:CreateTexture(nil, "OVERLAY")
  f.portrait:SetSize(96, 96)
  f.portrait:SetPoint("CENTER", f.portraitEdge, "CENTER")
  f.classIcon = f.pic:CreateTexture(nil, "OVERLAY")
  f.name = U.Text(f, 15, WHITE, "CENTER", 168)
  f.name:SetPoint("TOP", 0, -234)
  f.title = U.Text(f, 13, WHITE, "CENTER", 168)
  f.title:SetPoint("TOP", 0, -254)
  f.line = U.Text(f, 12, INK, "CENTER", 168)
  f.line:SetWordWrap(true)
  f.line:SetHeight(32)
  f.line:SetJustifyV("TOP")
  f.line:SetPoint("TOP", 0, -274)
  f.rule = U.Flat(f, "ARTWORK", LINE, 1)
  f.rule:SetHeight(1)
  f.rule:SetPoint("TOPLEFT", 12, -316)
  f.rule:SetPoint("TOPRIGHT", -12, -316)
  f.value = U.Text(f, 15, WHITE, "CENTER", 168)
  f.value:SetPoint("TOP", 0, -326)
  f.valueLabel = U.Text(f, 11, DIM, "CENTER", 168)
  f.valueLabel:SetPoint("TOP", 0, -346)
  f:SetScript("OnEnter", C.Safe(function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    self.tip(GameTooltip)
    GameTooltip:Show()
  end, "card: tooltip"))
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

-- the picture, in the order of 8.2: the member's unit, the race model, the icons. Returns what it drew ("model",
-- "race", "icons") for the tooltip and /cute diag runs
local function picture(f, d)
  local U = UI()
  local cc = U.ClassColor(d.class)
  f.model:Hide(); f.tint:Hide(); f.portrait:Hide(); f.portraitEdge:Hide(); f.classIcon:Hide()
  local unit = Cards.Find(d.guid)
  if unit and type(f.model.SetUnit) == "function" then
    local ok = f.model:SetUnit(unit)
    if ok ~= false then
      f.model:SetPortraitZoom(0)
      f.model:SetCamDistanceScale(1.1)
      f.model:SetFacing(-0.35)
      f.model:SetAnimation(0)
      f.model:Show()
      return "model", unit
    end
  end
  local race, sex = Cards.RaceSex(d.guid, d.race, d.sex)
  f.tint:SetColorTexture(cc[1], cc[2], cc[3], 0.15)
  f.tint:Show()
  local display = Cards.RaceModelOn() and Cards.RaceModel(race, sex) or nil
  if display then
    f.model:SetDisplayInfo(display)
    f.model:SetPortraitZoom(0)
    f.model:SetCamDistanceScale(1.1)
    f.model:SetFacing(-0.35)
    f.model:SetAnimation(0)
    f.model:Show()
    return "race"
  end
  local file = Cards.Portrait(race, sex)
  local shown = false
  if file then shown = f.portrait:SetTexture(file) ~= false end
  f.portrait:SetShown(shown)
  f.portraitEdge:SetShown(shown)
  local icon = CLASS_ICON[d.class or ""]
  if icon and f.classIcon:SetTexture(icon) ~= false then
    f.classIcon:ClearAllPoints()
    if shown then
      f.classIcon:SetSize(32, 32)
      f.classIcon:SetPoint("BOTTOMRIGHT", f.portrait, "BOTTOMRIGHT", 8, -8)
    else
      f.classIcon:SetSize(72, 72)
      f.classIcon:SetPoint("CENTER", f.pic, "CENTER")
    end
    f.classIcon:Show()
  end
  return "icons"
end
Cards.Picture = picture

function Cards.Fill(f, d)
  local U = UI()
  local kc = Cards.KindColor(d.kind)
  local bar = kc or Cards.EDGE
  f.bar:SetColorTexture(bar[1], bar[2], bar[3], 1)
  color(f.label, kc or WHITE)
  f.label:SetText(d.label or "")
  -- a headline (or a first) has a 1 px white edge instead of black
  if f.SetBackdropBorderColor then
    if d.headline then f:SetBackdropBorderColor(WHITE[1], WHITE[2], WHITE[3], 1) else f:SetBackdropBorderColor(0, 0, 0, 1) end
  end
  f.drew = picture(f, d)
  color(f.name, U.ClassColor(d.class))
  U.FitText(f.name, d.name or "?", 164)
  U.FitText(f.title, d.title or "", 164)
  f.line:SetText(d.line or "")
  f.value:SetText(d.value or "")
  U.FitText(f.valueLabel, d.valueLabel or "", 164)
  f.tip = d.tip
  f:Show()
end

-- the card screen for a set (the design's unit interface, 2.3): R1 shows a run's report ("report", or "test" for the
-- test report); the halls' announcement and preview modes come with them
function Cards:Show(set, mode)
  if C.CardFrame and C.CardFrame.Report then C.CardFrame:Report(set, { test = mode == "test" }) end
end
