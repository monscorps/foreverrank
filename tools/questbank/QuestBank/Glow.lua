-- SPDX-License-Identifier: GPL-3.0-or-later
-- A light on what your Interact key would use: gold for a quest object (one named in an objective of a quest in
-- your log, one the game says belongs to a quest in your log, or that starts a quest) or a quest NPC (one with a
-- quest for you to take or hand in), green for an herb, orange for ore, blue for a chest, white for any other NPC
-- (vendors, trainers) or plain object. The game's soft targeting picks the thing ("softinteract"); its nameplate
-- carries the light. Three styles: "sparkle" (a soft glow with small sparkles orbiting and twinkling round it),
-- "light" (the glow under a breathing ring and a slow-turning sparkle) and "game" (nothing of QuestBank's: the game's
-- own highlight and interact icon on the nameplate). Switching the light on sets the game's soft-interact settings so
-- things all around you within reach get a nameplate, and with it the game's interact icon: for an object (an herb, a
-- vein, a chest, a quest object) it sets the interact icons as the game's own Show All does, which its Default leaves
-- off for objects; 5.4.2 left them at Default, and objects never lit. The values the settings had are kept, listed in
-- Settings, and put back when you switch the light off, press Restore the game's settings, type /qb sparkle reset, or
-- log out. One you change yourself (while it is on, or since it set it) is left as you set it, that one alone: every
-- other goes back to its own value. Only reads of units and cvar writes: nothing of the game's is replaced, and
-- nothing is written in a fight or before the game has read its settings.
-- 5.4.4, the owner's play test ("people like sparkle but hate the health bars popping up with it"): the soft-interact
-- nameplate (SoftTargetNameplateInteract) is what put a health bar over every NPC the light was on. It is an option of
-- its own now, off (glow.plates): the light sits on the game's interact icon's plate, which carries no bar, and a save
-- that had the setting changed by 5.4.3 gets the player's own value back at the next login (release, below). And the
-- light picks its NPCs: quest givers and hand-ins, and a trainer you can use (a profession you could learn or train a
-- rank of, your class's trainer with new spells); every other NPC only with "Every other NPC too" (glow.everyNpc). The
-- game's own interact icon is the game's, on the one thing under your Interact key.
local _, QB = ...
if QB.dormant then return end
local Glow = {}
QB.Glow = Glow

-- the game's settings the light needs and the values it sets, in the order Settings lists them, with the name and
-- the words for each value shown there. The interact key on for the keyboard and mouse too (the game's Controls,
-- Enable Interact Key: 3 is Enum.SoftTargetEnableFlags.Any, 1 the gamepad alone), looking all round you to 15 yards,
-- a nameplate on what it would use and the game's interact icon there (Blizzard_NamePlates draws the icon on the
-- soft-interact target's plate). Which objects get a plate and an icon the game decides in its own code, not in its
-- Lua; its Accessibility, Interact Icons, Show All is its own way to put the icon on every object, and the light sets
-- the three icon settings as Show All does (icons: those three; Blizzard_SettingsDefinitions_Frame/Accessibility.lua).
-- Not yet seen in game: whether an object needs the low-priority icons as well as the icons on objects. A setting
-- this client has not got is left out (GetCVar answers nil for it)
local ONOFF = { ["0"] = "Off", ["1"] = "On" }
local LIST = {
  { cvar = "SoftTargetInteract", want = "3", label = "Interact key",
    values = { ["0"] = "Off", ["1"] = "Gamepad only", ["2"] = "Keyboard and mouse", ["3"] = "On" },
    where = "The game's Settings: Controls, Enable Interact Key." },
  { cvar = "SoftTargetInteractArc", want = "2", label = "Interact arc",
    values = { ["0"] = "Straight ahead", ["1"] = "In front", ["2"] = "All round" },
    where = "Not in the game's Settings: how far round you the Interact key looks." },
  { cvar = "SoftTargetInteractRange", want = "15", label = "Interact range", unit = "yards",
    where = "Not in the game's Settings: how far away the Interact key looks." },
  { cvar = "SoftTargetNameplateInteract", want = "1", label = "Interact target's nameplate", values = ONOFF, plates = true,
    where = "Not in the game's Settings: a full nameplate, with its health bar, on what the Interact key would use. Set only with the light's Health bars option on." },
  { cvar = "SoftTargetIconInteract", want = "1", label = "Interact icons", values = ONOFF, icons = true,
    where = "The game's Settings: Accessibility, Interact Icons (Default and Show All turn it on)." },
  { cvar = "SoftTargetIconGameObject", want = "1", label = "Interact icons on objects", values = ONOFF, icons = true,
    where = "The game's Settings: Accessibility, Interact Icons (Show All turns it on). The game's Default leaves it off, and with it off an herb, a vein, a chest or a quest object has no interact icon and no nameplate for the light." },
  { cvar = "SoftTargetLowPriorityIcons", want = "1", label = "Low-priority interact icons", values = ONOFF, icons = true,
    where = "The game's Settings: Accessibility, Interact Icons (Show All turns it on)." },
}
Glow.LIST = LIST
local CVARS, BYNAME = {}, {}
for _, s in ipairs(LIST) do CVARS[s.cvar] = s.want; BYNAME[s.cvar:lower()] = s end
Glow.CVARS = CVARS
-- the game's Interact Icons is one dropdown over four settings: the three icons above and the enemy icons, which the
-- light reads and never sets. Its Default, Show All and None each write all four (Accessibility.lua)
local SIBLING = "SoftTargetIconEnemy"
local SIBLING_L = SIBLING:lower()

-- a setting's value in words ("On", "All round", "15 yards"); one with no words as it is
function Glow.Words(s, v)
  if v == nil then return "-" end
  if s.unit then return v .. " " .. s.unit end
  return s.values and s.values[v] or v
end
-- two values of a setting the same ("15" and "15.000" are)
local function same(a, b)
  if a == b then return true end
  local x, y = tonumber(a), tonumber(b)
  return x ~= nil and x == y
end
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
-- the health bars over what the light is on (the soft-interact nameplate): only when asked for
local function platesOn() return settings().plates == true end
Glow.PlatesOn = platesOn
-- a setting the light sets now: every one, but the nameplate's with the health bars off
local function sets(s) return not s.plates or platesOn() end
Glow.Sets = sets

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

-- The game's settings. Each one's own value is kept in settings.glow: saved, the value to put back, and yours, a
-- setting the light leaves as you set it, with how it became yours ("changed" by you while the light was on, or found
-- at a value of yours as it set them: at "login", or as you switched it "on"); or in settings.glow.chars[you] for a
-- setting the game keeps per character (GetCVarInfo says so). Each setting is judged on its own: one of yours never
-- takes another's kept value with it. saved is noted the first time the light changes a setting and kept until it is
-- put back for good (switched off, Restore the game's settings, /qb sparkle reset). Logging out puts the values back
-- but keeps them: the next login can tell the light's value, the game's own and one you set while QuestBank was not
-- running apart, and put right a game that closed before it could put them back. seen holds the light's last reading
-- of the enemy icons, which it never sets: moved since, the game's Interact Icons was picked by you
local writing = false -- QuestBank's own write under way: the CVAR_UPDATE it fires (at once) is not yours
local mine = {}       -- the settings the light set, or found at its value, this session
local pending, pendingWhy -- "apply" or "restore", held back in a fight or till the game has read its settings; who
                          -- asked to restore, or how a value of yours would be found ("login" or "on") to apply
local varsLoaded = false -- VARIABLES_LOADED seen: the game has read its settings from its config
local refusedNow = {} -- the settings the game would not take back this session: a loading screen does not try them
                      -- again (Restore the game's settings does), so chat says it once a session

local function inFight()
  local P = QB.Pins
  if P and P.InCombat then return P.InCombat() and true or false end
  return InCombatLockdown and InCombatLockdown() and true or false
end

-- the game's settings read from its config yet (C_CVar.AreCVarsLoaded, or VARIABLES_LOADED seen; a client without
-- either has them). Before, a value read is the game's default and one written is overwritten as they load, firing a
-- CVAR_UPDATE that would pass for yours. The game's own Settings wait for both VARIABLES_LOADED and the first loading
-- screen (Blizzard_SettingsRegistrar.lua); the light waits as long
local function loaded()
  if varsLoaded then return true end
  local C = C_CVar
  if not (C and C.AreCVarsLoaded) then return true end
  local ok, yes = pcall(C.AreCVarsLoaded)
  return not ok or plain(yes) ~= false
end
-- out of a fight with the game's settings loaded: the time a setting may be written
local function free() return not inFight() and loaded() end

-- a setting's value now, as text; nil when this client has no such setting (GetCVar answers nil, SetCVar would
-- refuse) or keeps it from addons (GetCVarInfo: secure, read-only or locked). Second, the game keeps it per character
local function current(name)
  if not GetCVar then return nil end
  local ok, v = pcall(GetCVar, name)
  v = ok and plain(v) or nil
  if v == nil then return nil end
  local perChar = false
  local info = (C_CVar and C_CVar.GetCVarInfo) or GetCVarInfo
  if info then
    local ok2, _, _, _, char, locked, secure, readOnly = pcall(info, name)
    if ok2 then
      if plain(locked) == true or plain(secure) == true or plain(readOnly) == true then return nil end
      perChar = plain(char) == true
    end
  end
  return tostring(v), perChar
end

-- where a setting's own value is kept (field: "saved", or "seen" for the enemy icons' reading): this character's,
-- then the account's; for one with none yet (make), this character's for a setting kept per character, else the
-- account's
local function holder(name, perChar, make, field)
  field = field or "saved"
  local g = settings()
  local chars = type(g.chars) == "table" and g.chars or nil
  local ch = chars and QB.charKey and chars[QB.charKey]
  local b
  if type(ch) == "table" and type(ch[field]) == "table" and ch[field][name] ~= nil then b = ch
  elseif type(g[field]) == "table" and g[field][name] ~= nil then b = g
  elseif not make then return nil
  elseif perChar and QB.charKey then
    if not chars then chars = {}; g.chars = chars end
    b = type(ch) == "table" and ch or {}
    chars[QB.charKey] = b
  else b = g end
  if type(b.saved) ~= "table" then b.saved = {} end
  if type(b.yours) ~= "table" then b.yours = {} end
  if field == "seen" and type(b.seen) ~= "table" then b.seen = {} end
  return b
end

-- the game's own values the light holds now, the account's and this character's
function Glow.Held()
  local g = settings()
  if type(g.saved) == "table" and next(g.saved) ~= nil then return true end
  local ch = type(g.chars) == "table" and QB.charKey and g.chars[QB.charKey]
  return type(ch) == "table" and type(ch.saved) == "table" and next(ch.saved) ~= nil
end

-- what the game's Interact Icons reads now, from its four settings as its own Settings read them (Accessibility.lua):
-- "Show All" with all four on, "None" with all four off, any other mix "Default"; nil when this client lacks one
local ICON_FOUR = { SIBLING }
for _, s in ipairs(LIST) do if s.icons then ICON_FOUR[#ICON_FOUR + 1] = s.cvar end end
function Glow.IconsReading()
  local on = 0
  for _, name in ipairs(ICON_FOUR) do
    local v = current(name)
    if v == nil then return nil end
    local n = tonumber(v)
    if n and n ~= 0 then on = on + 1 end
  end
  return on == #ICON_FOUR and "Show All" or on == 0 and "None" or "Default"
end

-- one setting as Settings shows it: its value now; the game's own value the light keeps for it (nil when it keeps
-- none; for one of yours, its value now); how it became yours (nil when it is not: "changed", "login" or "on"); and
-- whether the game kept its value (the light off, it would not take back the game's own this session). Nothing when
-- this client has not got it
function Glow.State(s)
  local v, perChar = current(s.cvar)
  if v == nil then return nil end
  local b = holder(s.cvar, perChar, false)
  local how = b and b.yours[s.cvar] or nil
  if how == true then how = "changed" end -- (a save from before how was kept)
  local was = b and (how and v or b.saved[s.cvar]) or nil
  local kept = refusedNow[s.cvar] == true and not settings().on and not how and was ~= nil and not same(v, was)
  return v, was, how, kept
end

local function refreshUI()
  local U = QB.UI
  if U and U.Refresh then U:Refresh() end
end

-- a value written: SetCVar says whether the game took it (false: an unknown, read-only or secure setting)
local function write(name, v)
  writing = true
  local ok, took = pcall(SetCVar, name, v)
  writing = false
  return ok and took ~= false
end

-- in chat, in one line: the settings that became yours ({ setting, value } each)
local function told(list)
  if #list == 0 then return end
  if #list == 1 then
    local s, v = list[1][1], list[1][2]
    QB:Print(string.format("%s is yours now (%s): the interact light leaves it as you set it.", s.label, Glow.Words(s, v)))
    return
  end
  local parts = {}
  for i, e in ipairs(list) do parts[i] = e[1].label .. " " .. Glow.Words(e[1], e[2]) end
  QB:Print("These are yours now: " .. table.concat(parts, ", ") .. ". The interact light leaves them as you set them.")
end

-- one setting made yours at its value now, that one alone: the light leaves it from then on, and every other setting
-- keeps the game's own value it holds for it. how: "changed", "login" or "on"; noted in list, for chat
local function claim(b, s, v, how, list)
  b.saved[s.cvar], b.yours[s.cvar], mine[s.cvar] = v, how, nil
  list[#list + 1] = { s, v }
end
-- the light has set the interact icons this session (any of the three)
local function iconsSet()
  for _, s in ipairs(LIST) do if s.icons and mine[s.cvar] then return true end end
  return false
end

-- the enemy icons moved from the light's last reading of them (make: the reading taken now when there is none): the
-- game's Interact Icons chosen by you, in its Settings or while QuestBank was not running. The reading is taken anew
local function siblingMoved(make)
  local e, perChar = current(SIBLING)
  local b = e ~= nil and holder(SIBLING, perChar, make, "seen") or nil
  if not b then return false end
  local was = b.seen[SIBLING]
  b.seen[SIBLING] = e
  return was ~= nil and not same(e, was)
end

-- the game's Interact Icons picked at Show All since the light last read the enemy icons: they moved, and the four
-- read Show All. Its pick writes all four, but only a value that changes says so (CVAR_UPDATE): the interact icons the
-- light had on already stay quiet, and are set by you all the same. One limit: the enemy icons switched on alone (a
-- console command) while the light's icons are on read the same, and take the quiet ones for yours
local function showAllPicked(make)
  return siblingMoved(make) and Glow.IconsReading() == "Show All"
end
-- one of the interact icons a Show All pick left quiet: not yours, at the light's value, and that is not the game's
-- own value kept for it (one at the game's own needs nothing: it goes back to the value it has)
local function quiet(s, v, b)
  local was = b.saved[s.cvar]
  return s.icons == true and not b.yours[s.cvar] and was ~= nil and same(v, s.want) and not same(v, was)
end

-- set the light's values, noting the game's own the first time. A value that is neither the game's own kept for it
-- nor the light's was set by you (while QuestBank was not running, or before the light set it this session): yours
-- from then on, left as it is, that setting alone; the interact icons a Show All pick left at the light's value too.
-- how: "login" or "on" (switched on), for Settings. One limit: a setting you set to the light's own value while
-- QuestBank was not running, Show All not picked, cannot be told from the light's own left by a game that closed
-- before it could put it back, and goes back as the game's own. In a fight, or before the game has read its
-- settings, when that is over
-- A setting the light no longer sets (the nameplate's, with the health bars off): the game's own value it holds goes
-- back, where the setting is still at the light's value (a 5.4.3 save, or the option just switched off); one you set
-- since is yours and left as it is. The value is let go either way. Out of a fight only (apply's caller sees to it);
-- refused by the game: kept, to try again at the next login. The names put back, for chat
local function release(s, back)
  local name = s.cvar
  mine[name] = nil
  local v, perChar = current(name)
  local b = v ~= nil and holder(name, perChar, false) or nil
  if not b then return end
  local was = b.saved[name]
  if was ~= nil and not b.yours[name] and not same(v, was) and same(v, s.want) then
    if write(name, was) then
      b.saved[name] = nil
      back[#back + 1] = s.label .. " " .. Glow.Words(s, was)
    else
      refusedNow[name] = true
    end
    return
  end
  b.saved[name], b.yours[name] = nil, nil
end
Glow.Release = release

local function apply(how)
  how = how or "login"
  if not SetCVar then return end
  if not free() then pending, pendingWhy = "apply", how; return end
  pending, pendingWhy = nil, nil
  local showAll = showAllPicked(true)
  local yours, back = {}, {}
  for _, s in ipairs(LIST) do
    local name, want = s.cvar, s.want
    local v, perChar = current(name)
    if v ~= nil and not sets(s) then
      release(s, back)
    elseif v ~= nil then
      local b = holder(name, perChar, true)
      local was = b.saved[name]
      if b.yours[name] then
        b.saved[name] = v
      elseif was == nil or (same(v, was) and not mine[name]) then
        -- (one the game will not take is not the light's: nothing kept for it)
        if same(v, want) or write(name, want) then
          if was == nil then b.saved[name] = v end
          mine[name] = true
        end
      elseif same(v, want) and (mine[name] or not (showAll and quiet(s, v, b))) then
        mine[name] = true -- as the light left it (this session, or a game that closed before it could put it back)
      else
        claim(b, s, v, how, yours)
      end
    end
  end
  told(yours)
  if #back > 0 then
    QB:Print("The interact light no longer puts a health bar over what it lights (Settings, Interact light, has it as an option): " .. table.concat(back, ", ") .. " is back as you had it.")
  end
end
Glow.Apply = apply

-- put the game's own values back, each where it differs; one of yours stays as it is. Before each write, the value
-- now: one that is neither the light's nor the game's own kept (or one of the interact icons a Show All pick left
-- quiet) you set since the light set it, in the game's Settings, by a command or while QuestBank was not running: it
-- stays as you set it, and the game's own value kept for it is let go. forget: the light lets go of them (else,
-- logging out, they are kept); one the game would not take back is kept all the same, to try again at the next login.
-- why: who asked; a "repair" (as a loading screen finds values still kept) does not try again one the game refused
-- this session. The settings written, the ones refused and the ones left as you set them, in words
local function putBack(forget, why)
  local showAll = showAllPicked(false)
  local done, refused, theirs, keep = {}, {}, {}, {}
  for _, s in ipairs(LIST) do
    local name = s.cvar
    local v, perChar = current(name)
    local b = v ~= nil and holder(name, perChar, false) or nil
    local was = b and b.saved[name] or nil
    if was ~= nil and not b.yours[name] and not same(v, was) then
      if not same(v, s.want) or (showAll and quiet(s, v, b)) then
        b.saved[name] = nil
        theirs[#theirs + 1] = s.label .. " " .. Glow.Words(s, v)
      elseif why == "repair" and refusedNow[name] then
        keep[name] = true
      elseif write(name, was) then
        done[#done + 1] = s.label .. " " .. Glow.Words(s, was)
        refusedNow[name] = nil
      else
        refused[#refused + 1] = s.label .. " " .. Glow.Words(s, was)
        keep[name], refusedNow[name] = true, true
      end
    end
  end
  mine = {}
  if forget then
    local g = settings()
    -- a holder's kept values, but for the refused ones, let go; false when nothing is left in it
    local function prune(b)
      local left
      if type(b.saved) == "table" then
        for name in pairs(keep) do
          if b.saved[name] ~= nil then left = left or {}; left[name] = b.saved[name] end
        end
      end
      b.saved, b.yours, b.seen = left, nil, nil
      return left ~= nil
    end
    prune(g)
    if type(g.chars) == "table" and QB.charKey then
      local ch = g.chars[QB.charKey]
      if not (type(ch) == "table" and prune(ch)) then g.chars[QB.charKey] = nil end
      if next(g.chars) == nil then g.chars = nil end
    end
  end
  return done, refused, theirs
end

local function said(why, done, refused, theirs)
  if why == "repair" then
    if #done > 0 then
      QB:Print("The game's settings the interact light changed were still changed: the game closed or reloaded before " .. (QB.NAME or "QuestBank") .. " could put them back. They are back as you had them: " .. table.concat(done, ", ") .. ".")
    end
  elseif why then
    QB:Print(#done > 0 and ("The interact light is off, and the game's settings it changed are back as you had them: " .. table.concat(done, ", ") .. ".")
      or (#refused > 0 or #theirs > 0) and "The interact light is off."
      or "The interact light is off. The game's settings are as you had them: it had nothing to put back.")
  end
  -- (said once: the game's own value kept for each is let go, so it is not judged again)
  if #theirs > 0 then
    QB:Print((#theirs == 1 and "Left as you set it since the interact light changed it: " or "Left as you set them since the interact light changed them: ")
      .. table.concat(theirs, ", ") .. ".")
  end
  if #refused > 0 then
    -- (a host has no Restore button: QB.host)
    QB:Print("The game would not take back " .. table.concat(refused, ", ") .. ". " .. (QB.NAME or "QuestBank") .. " keeps the game's own value and tries again at your next login"
      .. (QB.host and "." or "; Restore the game's settings tries now."))
  end
end

-- switch the light off and put back every game setting it changed, exactly as the game had it. why: who asked
-- ("button" and "slash" are answered in chat; "repair" when anything was still changed; nil, switched off, quietly).
-- In a fight nothing is written: they go back when it is over (and, as you log in, once the game has read them)
function Glow.Restore(why)
  settings().on = false
  Glow.Update()
  if not free() then
    pending, pendingWhy = "restore", why
    if inFight() and (why == "button" or why == "slash") then
      QB:Print("The interact light is off. The game's settings it changed go back as you had them when the fight is over.")
    end
    return false
  end
  pending, pendingWhy = nil, nil
  said(why, putBack(true, why))
  return true
end

-- a write held back in a fight, or until the game had read its settings, now it may go
local function flush()
  if not pending or not free() then return end
  local what, why = pending, pendingWhy
  pending, pendingWhy = nil, nil
  if what == "restore" then said(why, putBack(true, why))
  elseif settings().on then apply(why) end
  refreshUI()
end

-- a setting changed by anyone but QuestBank (you in the game's Settings, a console command, another addon) while the
-- light is on, after it set it this session: yours from then on, not fought, that setting alone; the others keep the
-- game's own values to go back to. The game's Interact Icons writes its four settings one after another, each that
-- changes with its CVAR_UPDATE, so each of the three that moves is yours as it moves. The enemy icons moving (the
-- light never sets them) mark a pick there: once its writes are done (the next frame), the icons a Show All left
-- quiet at the light's value are yours too. So Show All stays Show All, None stays None. (Its Default writes nothing
-- while the dropdown reads Default already, as the light's own mix does. None, then Default, does it.) Chat says what
-- became yours in one line, once the writes are done. (Before the light has set a setting this session, as the game
-- loads its settings, the next loading screen judges it; with the light off, a put-back still to come judges it
-- before it writes)
local heard, picked, soon = {}, false, false
local function settle()
  soon = false
  local g = settings()
  if picked then
    picked = false
    if g.on and iconsSet() and Glow.IconsReading() == "Show All" then
      for _, s in ipairs(LIST) do
        if s.icons and mine[s.cvar] then
          local v, perChar = current(s.cvar)
          local b = v ~= nil and holder(s.cvar, perChar, false) or nil
          if b and quiet(s, v, b) then claim(b, s, v, "changed", heard) end
        end
      end
    end
  end
  local list = heard
  heard = {}
  if g.on then told(list) end
  refreshUI()
end
local function later()
  if soon then return end
  soon = true
  if C_Timer and C_Timer.After then C_Timer.After(0, QB.Safe(settle, "glow: the game's settings changed")) else settle() end
end
local function changed(name, value)
  if writing or type(name) ~= "string" then return end
  local lname = name:lower()
  local s = BYNAME[lname]
  if not s and lname ~= SIBLING_L then return end
  if not settings().on then return end
  if not s then
    -- (the enemy icons alone: only once the light has set the icons this session; as the game loads its settings,
    -- the light's reading stays for the next loading screen to judge)
    if iconsSet() and siblingMoved(false) then picked = true; later() end
    return
  end
  local v, perChar = current(s.cvar)
  value = plain(value)
  if value ~= nil then v = tostring(value) end
  local b = v ~= nil and holder(s.cvar, perChar, false)
  if not (b and (b.yours[s.cvar] or mine[s.cvar])) then return end
  if b.yours[s.cvar] then b.saved[s.cvar] = v
  elseif same(v, s.want) then return
  else claim(b, s, v, "changed", heard) end
  later()
end

-- the light's art: QuestBank's own textures (art/, drawn by make_art.py)
local ART = QB.ART or "Interface\\AddOns\\QuestBank\\art\\" -- (a host holding a copy of the engine names its own folder: QB.ART)
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

-- the soft-interact target's nameplate: the game's own lookup first, else the plate whose unit is it, as the game's
-- own interact icon finds it (Blizzard_NamePlates: each plate's unit against "softinteract")
local function unitOf(p) return p.unitToken or p.namePlateUnitToken end
local function plateOf()
  local NP = C_NamePlate
  if not NP then return nil end
  if NP.GetNamePlateForUnit then
    local ok, p = pcall(NP.GetNamePlateForUnit, "softinteract")
    if ok and type(p) == "table" then return p end
  end
  if not (NP.GetNamePlates and UnitIsUnit) then return nil end
  local ok, plates = pcall(NP.GetNamePlates)
  if not (ok and type(plates) == "table") then return nil end
  for _, p in pairs(plates) do
    local okU, unit = pcall(unitOf, p)
    if okU and type(unit) == "string" then
      local okI, is = pcall(UnitIsUnit, unit, "softinteract")
      if okI and plain(is) == true then return p end
    end
  end
  return nil
end

-- the game's word that the soft-interact target belongs to a quest in your log (an object named otherwise than its
-- objective: "Large Crate" for "Crate of Supplies")
local function related()
  local QL = C_QuestLog
  if not (QL and QL.UnitIsRelatedToActiveQuest) then return false end
  local ok, yes = pcall(QL.UnitIsRelatedToActiveQuest, "softinteract")
  return ok and plain(yes) == true
end

-- the game's word whether the soft-interact target is a game object (as its own nameplates ask it,
-- Blizzard_NamePlateHealthBar.lua); nil when it gives none
local function isObject()
  if not UnitIsGameObject then return nil end
  local ok, yes = pcall(UnitIsGameObject, "softinteract")
  if not ok then return nil end
  yes = plain(yes)
  if yes == true or yes == false then return yes end
  return nil
end

----------------------------------------------------------------------------
-- which NPCs light (5.4.4): quest givers and hand-ins, and the trainers you can use. "It highlights the herbalism
-- trainer, why? Why would I need that when I have 2 professions?" (the owner, a level-21 mage): 5.4.3 lit every NPC
-- under the Interact key in white, as the NPCs switch did. A trainer is known by the line the game shows under its name
-- ("Herbalism Trainer", the unit's own tooltip data); a profession's is worth a light while you could learn it (fewer
-- than two of the game's main ones, or a secondary one you lack) or train a rank of it (your skill near its cap), your
-- class's while it has a spell for you (read at its window: TRAINER_SHOW; until then, at an even level, Classic's
-- rhythm). Every other NPC lights only with Every other NPC too
----------------------------------------------------------------------------
local SECONDARY = { Cooking = true, ["First Aid"] = true, Fishing = true } -- (Classic's three; the client's own names)
local RANK_NEAR = 25 -- skill points under its cap: a rank to train
local subtitles = {} -- ["Creature:id"] = the line under an NPC's name, or false: read once a session
-- (by the creature's id in its GUID: the line is the creature's, the same for every spawn of it. 5.4.4 as first built
-- kept one a spawn, and a long session's spawns piled up)
local function npcKey(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  return kind and (kind .. ":" .. id) or nil
end
Glow.NpcKey = npcKey

-- the line under the soft-interact NPC's name ("Herbalism Trainer"; the game wraps a subtitle in <>), or nil
function Glow.Subtitle(guid)
  local key = npcKey(guid)
  if key and subtitles[key] ~= nil then return subtitles[key] or nil end
  local TI = C_TooltipInfo
  local line
  if TI and TI.GetUnit then
    local ok, data = pcall(TI.GetUnit, "softinteract")
    data = ok and plain(data) or nil
    local lines = type(data) == "table" and plain(data.lines) or nil
    local l2 = type(lines) == "table" and plain(lines[2]) or nil
    local text = type(l2) == "table" and plain(l2.leftText) or nil
    if type(text) == "string" and text ~= "" then line = (text:gsub("^<(.*)>$", "%1")) end
  end
  if key then subtitles[key] = line or false end
  return line
end

-- your professions as the game lists them: by name, { skill, cap, main }; and how many main ones (the first two)
local function professions()
  local out, mains = {}, 0
  if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return out, 0 end
  local ok, a, b, c3, c4, c5, c6, c7 = pcall(GetProfessions)
  if not ok then return out, 0 end
  for i, idx in ipairs({ a or false, b or false, c3 or false, c4 or false, c5 or false, c6 or false, c7 or false }) do
    if idx then
      local okI, name, _, skill, cap = pcall(GetProfessionInfo, idx)
      name, skill, cap = plain(name), plain(skill), plain(cap)
      if okI and type(name) == "string" then
        out[name] = { skill = type(skill) == "number" and skill or 0, cap = type(cap) == "number" and cap or 0, main = i <= 2 }
        if i <= 2 then mains = mains + 1 end
      end
    end
  end
  return out, mains
end
Glow.Professions = professions

-- what this character's class trainer has for it, as its window last showed (QuestBankDB.chars[you].trainer):
-- { level, avail (spells to learn then), next (the lowest level a spell it lists needs) }
local function trainerDB(make)
  local db = QuestBankDB
  local chars = type(db) == "table" and type(db.chars) == "table" and db.chars or nil
  local ch = chars and QB.charKey and chars[QB.charKey]
  if type(ch) ~= "table" then return nil end
  if make and type(ch.trainer) ~= "table" then ch.trainer = {} end
  return type(ch.trainer) == "table" and ch.trainer or nil
end
function Glow.ReadTrainer()
  if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then return end
  if type(IsTradeskillTrainer) == "function" then
    local ok, trade = pcall(IsTradeskillTrainer)
    if ok and plain(trade) == true then return end -- (a profession's: its own rule above)
  end
  local ok, n = pcall(GetNumTrainerServices)
  n = ok and plain(n) or 0
  if type(n) ~= "number" then return end
  local avail, nextLvl = 0, nil
  local lvl = UnitLevel and plain(UnitLevel("player")) or 0
  for i = 1, n do
    -- (name, its type: "available", "unavailable", "used" or "header", icon, the level it needs: Blizzard_TrainerUI.lua)
    local okS, _, kind, _, req = pcall(GetTrainerServiceInfo, i)
    req, kind = okS and plain(req) or nil, okS and plain(kind) or nil
    if kind == "available" then avail = avail + 1
    elseif kind == "unavailable" and type(req) == "number" and req > (type(lvl) == "number" and lvl or 0) and (not nextLvl or req < nextLvl) then nextLvl = req end
  end
  local t = trainerDB(true)
  if t then t.level, t.avail, t.next = lvl, avail, nextLvl end
end

-- an NPC worth the light: a quest NPC ("quest"), a trainer you can use ("npc"), or nil
function Glow.Useful(name, guid)
  if Glow.QuestNPC(name) then return "quest" end
  local sub = Glow.Subtitle(guid)
  local what = type(sub) == "string" and sub:match("^(.-) Trainer$")
  if not what then return nil end
  local okC, className = pcall(UnitClass, "player")
  className = okC and plain(className) or nil
  local lvl = UnitLevel and plain(UnitLevel("player")) or 0
  if type(lvl) ~= "number" then lvl = 0 end
  if what == className then
    local t = trainerDB(false)
    if t and t.level then
      if (t.avail or 0) > 0 and lvl >= t.level then return "npc" end
      return (t.next and lvl >= t.next) and "npc" or nil
    end
    return (lvl > 1 and lvl % 2 == 0) and "npc" or nil
  end
  local mine, mains = professions()
  local p = mine[what]
  if p then return (p.cap > 0 and p.skill >= p.cap - RANK_NEAR) and "npc" or nil end
  if SECONDARY[what] then return "npc" end
  return mains < 2 and "npc" or nil
end

-- the light goes on the soft-interact target's nameplate; without one there is no place on screen for it
function Glow.Update()
  local g = settings()
  local f = lightFrame()
  local function off(kind) f:Hide(); Glow.kind = kind end
  -- the game's own style draws nothing of QuestBank's; the soft-interact settings still show the game's highlight
  if not g.on or g.style == "game" then return off(nil) end
  if InCombatLockdown and InCombatLockdown() and g.combat ~= true then return off(nil) end
  -- (its GUID says there is one, a game object's as much as a creature's; where the game withholds the GUID, it exists)
  local guid = plain(UnitGUID and UnitGUID("softinteract"))
  if type(guid) ~= "string" and not (UnitExists and plain(UnitExists("softinteract")) == true) then return off(nil) end
  -- an object or an NPC: the game's word first (UnitIsGameObject, which it never withholds; a GUID it does, where a
  -- unit's identity is restricted), the GUID's kind where it gives none. A unit that is not an object is an NPC to the
  -- NPCs switch, its GUID withheld or not; anything else (a player, a pet, a vehicle) keeps the game's own cursor icon
  -- and nothing more. The NPCs switch is for units alone: an object lights whatever it says
  local obj = isObject()
  if obj == nil then obj = type(guid) == "string" and guid:find("^GameObject") ~= nil end
  local isNPC = not obj
  if isNPC then
    if type(guid) == "string" then
      if not guid:find("^Creature") then return off(nil) end
    elseif UnitIsPlayer then
      local ok, p = pcall(UnitIsPlayer, "softinteract")
      if ok and plain(p) == true then return off(nil) end
    end
    if not g.npcs then return off(nil) end
  end
  local name = plain(UnitName and UnitName("softinteract"))
  local kind
  if isNPC then
    -- a quest NPC or a trainer you can use; any other only with Every other NPC too
    kind = Glow.Useful(name, guid)
    if not kind then
      if not g.everyNpc then return off(nil) end
      kind = "npc"
    end
  else kind = Glow.Kind(name, nil) or "other" end
  -- an object the game says belongs to a quest in your log is a quest object, whatever its name (an herb or a vein
  -- keeps its own colour, as by name)
  if not isNPC and (kind == "other" or kind == "chest") and related() then kind = "quest" end
  if kind == "other" and not g.other then return off(nil) end
  local plate = plateOf()
  if type(plate) ~= "table" then return off(kind) end
  -- a plate the game keeps from addons (a friendly plate in an instance says it is forbidden): no place for the light
  if plate.IsForbidden and select(2, pcall(plate.IsForbidden, plate)) then return off(kind) end
  dress(f, g.style, kind)
  f:SetParent(plate)
  f:ClearAllPoints()
  f:SetPoint("CENTER", plate, "CENTER", 0, -10)
  f:SetFrameLevel((plate.GetFrameLevel and plate:GetFrameLevel() or 1) + 1)
  f:Show()
  Glow.kind, Glow.name = kind, name
end

-- the health bars over what it lights (the soft-interact nameplate), on or off: set, or put back as you had it, now
-- (in a fight, when it is over) while the light is on
function Glow.SetPlates(on)
  settings().plates = on and true or false
  if settings().on then apply("on") end
  Glow.Update()
end

-- on: the light's settings set (in a fight, when it is over); off: every one put back as the game had it
function Glow.Set(on)
  if on then
    settings().on = true
    apply("on")
    Glow.Update()
  else
    Glow.Restore()
  end
end

-- /qb sparkle: reset (or off) puts the game's settings back and switches the light off, on switches it on, and
-- anything else says how it stands
function Glow.Command(rest)
  local want = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if want == "reset" or want == "restore" or want == "off" then
    Glow.Restore("slash")
  elseif want == "on" then
    Glow.Set(true)
    QB:Print("The interact light is on. /qb sparkle reset puts the game's settings back as you had them and switches it off.")
  else
    local n = 0
    for _, s in ipairs(LIST) do
      local v, was = Glow.State(s)
      if v ~= nil and was ~= nil and not same(v, was) then n = n + 1 end
    end
    QB:Print(string.format("The interact light is %s, and %s of the game's settings %s changed by it. /qb sparkle reset puts them back as you had them and switches it off; /qb sparkle on switches it on.",
      settings().on and "on" or "off", n == 0 and "none" or tostring(n), n == 1 and "is" or "are"))
  end
  refreshUI()
end

function Glow:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...)
    if event == "CVAR_UPDATE" then return changed(...) end
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then Glow.ReadTrainer(); return end
    if event == "PLAYER_LOGOUT" then
      -- put back, keeping them for the next login; nothing in a fight (the next login puts right what is left)
      if not free() then return end
      if pending == "restore" then
        local why = pendingWhy
        pending, pendingWhy = nil, nil
        putBack(true, why)
      elseif settings().on then
        putBack(false)
      end
      return
    end
    -- the game has read its settings (as you log in, after the first loading screen): what waited for it goes now
    if event == "VARIABLES_LOADED" then varsLoaded = true end
    -- (not as a fight starts: the game may not say so yet)
    if event ~= "PLAYER_REGEN_DISABLED" then flush() end
    if event == "PLAYER_ENTERING_WORLD" then
      -- the light on: its settings set. Off, with the game's own values still kept (a game that closed, or a reload in
      -- a fight, before they went back): put back once (one the game would not take back, tried once a session)
      if settings().on then apply("login")
      elseif pending ~= "restore" and Glow.Held() then Glow.Restore("repair") end
    end
    Glow.Update()
  end, "glow"))
  for _, e in ipairs({ "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
                       "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "QUEST_LOG_UPDATE", "CVAR_UPDATE",
                       "VARIABLES_LOADED", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
  end
end
