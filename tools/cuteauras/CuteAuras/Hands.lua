-- SPDX-License-Identifier: GPL-3.0-or-later
-- Blessing of Protection, Freedom and Sacrifice. Each is a blessing, and a paladin's blessings are one per target: the
-- Hand takes your long blessing off them. Your cast (UNIT_SPELLCAST_SENT names its target; a hidden name is the member
-- a button of ours cast on, else your target or mouseover: Roster.SentTo) starts the Hand's own clock (its duration,
-- with your talents that lengthen it) and a silent countdown on the alerts overlay that only shows it; at its end a
-- restore, in the countdown's slot, names the blessing they lost (the one of yours last read on them or last cast on
-- them, the newer, while it can still be on them; none since, by a read or a death, or neither: the one Cute Auras
-- shares out to them). One alert a member: a new Hand on them takes their restore's slot, and the restore comes back at
-- its end. In a fight the restore is art, silent, and their row in the bar's flyout glows (a secure button can't be set
-- there); out of a fight, or 0.5 s after it, the first restore is the click icon, the game's secure button set to them
-- (one sound): a click blesses them, and the next one takes it 0.4 s later. Dead while the group fights on (the game
-- ends your own fight), it stays art, and the click icon waits for the group's end or for you back; its sound plays
-- only while you are alive. A restore goes once they have the blessing again, once any blessing of yours lands on them,
-- or on a right-click; a blessing of yours on them while your Hand is on takes the Hand off, and no restore comes at its
-- end. A member who leaves moves the unit tokens: the click icon hides until the roster is read again, then is set to
-- its member's unit. Their row glows only in your list of the blessing the restore names. "Alerts on screen" off: no
-- alerts, the row's glow alone.
local _, A = ...
local H = A.Part("Hands", { pending = {}, order = {}, saw = {} })
local L, S, D = A.Look, A.Spells, A.Data
local C = L.C
local plain, call = A.Plain, A.Call

local HAND, BLESS = {}, {} -- [spell id] = { key, dur } / [spell id] = blessing key (any rank, Greater too)
for key, e in pairs(D.HANDS) do for i, id in ipairs(e.ranks) do HAND[id] = { key = key, dur = e.durs[i] or e.dur, entry = e } end end
for key, e in pairs(D.BLESS) do
  for _, id in ipairs(e.ranks) do BLESS[id] = key end
  for _, id in ipairs(e.group or {}) do BLESS[id] = key end
end
H.HAND, H.BLESS = HAND, BLESS
local lastBless = {} -- [guid] = { key, at }: the blessing you last gave them (this session)
-- (H.saw[guid] = { key, at }: a blessing of yours an out-of-fight read found on them, Buffs.lua's teachRead, put on at
-- at; { at } alone: that read found none of yours, or they died then)

-- the blessing they lose: yours as last read on them or last cast on them, the newer, while it can still be on them (a
-- blessing's hour); a newer read or death that found none of yours, or neither, Cute Auras' share-out
local function fresh(e)
  if not e then return nil end
  if e.key == nil then return e end
  local entry = D.BLESS[e.key]
  if not entry or A.Now() - (e.at or 0) >= (entry.dur or 3600) then return nil end
  return e
end
local function lostBlessing(guid)
  local saw, cast = fresh(H.saw[guid]), fresh(lastBless[guid])
  local pick = saw or cast
  if saw and cast and cast.at > saw.at then pick = cast end
  if pick and pick.key then return pick.key end
  for _, o in ipairs(A.Assign.Owed(guid) or {}) do
    if o.key:find("^bless:") then return o.key:sub(7) end
  end
  return nil
end
-- (a member waiting for a restore glows only where its blessing is: key, a list's duty ("bless:might", or the bar's
-- "duty:bless:might"), else anywhere. Their share-out from you another blessing, no list of yours glows for them, and
-- the restore's words say to target them)
function H.Glowing(guid, key)
  local p = H.pending[guid]
  if not p then return false end
  if key == nil then return true end
  return key == "bless:" .. p.bless or key == "duty:bless:" .. p.bless
end
-- (a member's unit still theirs: one who left moves the unit tokens at once, and the roster reads them again 0.3 s on,
-- H.Rostered; a token someone else holds now is never read or clicked as theirs)
local function theirs(m) return plain(call(UnitGUID, m.unit)) == m.guid end
-- (dead or a ghost, not feigning: a death took every blessing off them, so a restore for them is over; the bar asks
-- for their blessings again once they are back)
local function deadNow(m) return A.Yes(UnitIsDeadOrGhost, m.unit) and not A.Yes(UnitIsFeignDeath, m.unit) end

----------------------------------------------------------------------------
-- a Hand's length with your talents: a talent the client's tables say lengthens it (D.HANDS[key].mods, seconds a
-- rank), its ranks from your talent tree (C_Traits), else one rank where the game says you have it
----------------------------------------------------------------------------
local ranks -- [talent spell id] = ranks taken, read once a talent change
local function readRanks()
  ranks = {}
  local CT, T, SI = C_ClassTalents, C_Traits, C_SpecializationInfo
  if not (CT and T and type(T.GetTreeNodes) == "function") then return end
  local cfg
  if SI and type(SI.GetActiveSpecGroup) == "function" and type(SI.GetCombatConfigIDForSpecGroup) == "function" then
    local g = plain(call(SI.GetActiveSpecGroup))
    if type(g) == "number" then cfg = plain(call(SI.GetCombatConfigIDForSpecGroup, g)) end
  end
  cfg = cfg or plain(call(CT.GetActiveConfigID))
  if type(cfg) ~= "number" then return end
  local info = call(T.GetConfigInfo, cfg)
  local tree = type(info) == "table" and type(info.treeIDs) == "table" and plain(info.treeIDs[1]) or nil
  local nodes = tree and call(T.GetTreeNodes, tree)
  for _, node in ipairs(type(nodes) == "table" and nodes or {}) do
    local n = call(T.GetNodeInfo, cfg, node)
    local r = type(n) == "table" and plain(n.activeRank) or nil
    local entry = type(n) == "table" and type(n.activeEntry) == "table" and plain(n.activeEntry.entryID) or nil
    if type(r) == "number" and r > 0 and entry then
      local e = call(T.GetEntryInfo, cfg, entry)
      local def = type(e) == "table" and plain(e.definitionID) or nil
      local d = def and call(T.GetDefinitionInfo, def)
      local sp = type(d) == "table" and plain(d.spellID) or nil
      if type(sp) == "number" then ranks[sp] = r end
    end
  end
end
function H.Bonus(entry)
  if not (entry and entry.mods) then return 0 end
  if not ranks then readRanks() end
  local add = 0
  for talent, per in pairs(entry.mods) do
    local r = ranks[talent] or (A.Yes(IsPlayerSpell, talent) and 1) or 0
    add = add + per * r
  end
  return add
end

----------------------------------------------------------------------------
-- the words (the tooltips', and the Cards look's line; the test alerts use them too): the member's name first, a
-- blessing's or Hand's short name
----------------------------------------------------------------------------
function H.HandWords(name, handName, bless)
  local entry = bless and D.BLESS[bless]
  local title = (name or "?") .. ": " .. (L.Short(handName) or "Hand")
  if entry then return title, "Then bless with " .. L.Short(L.SpellName(entry.ranks[1], entry.name)) .. " again." end
  return title, "Nothing to give back after."
end
-- where: "secure" the click icon, "next" waiting after it, "fight" in a fight (row: their row in the bar's list glows)
function H.RestoreWords(name, bless, handName, where, row)
  local entry = D.BLESS[bless]
  local short = L.Short(L.SpellName(entry.ranks[1], entry.name))
  local title = (name or "?") .. ": " .. short
  local hand = L.Short(handName) or "Hand"
  if where == "secure" then return title, hand .. " is over: bless with " .. short .. " again." end
  if where == "next" then return title, "Next, once the one before it is done." end
  if row then return title, hand .. " is over. Their row glows in the bar's " .. short .. " list." end
  return title, hand .. " is over. Target them and give them " .. short .. "."
end
H.FIGHT_TIP = "After the fight, a click on it blesses them."

----------------------------------------------------------------------------
-- the secure restore: the first pending restore on the click icon (the game's button: a click blesses them), set,
-- sized and placed out of a fight only. Its guard, a secure state handler on [combat], hides it as a fight starts, so
-- no click casts a blessing that would take a new Hand off them; it only hides, so the button comes back only through
-- setSecure after the fight, never with a stale spell or unit
----------------------------------------------------------------------------
local button
-- (the driver hands its state as a number, SecureStateDriver.lua's tonumber; the string on an old client)
local GUARD = [[
  if newstate == 1 or newstate == "1" then self:GetFrameRef("b"):Hide() end
]]
H.GUARD = GUARD
local function makeGuard()
  if H.guard or not button then return end
  local g = CreateFrame("Frame", "CuteAurasRestoreGuard", UIParent, "SecureHandlerStateTemplate")
  if type(SecureHandlerSetFrameRef) == "function" then SecureHandlerSetFrameRef(g, "b", button) end
  g:SetAttribute("_onstate-fight", GUARD)
  if type(RegisterStateDriver) == "function" then RegisterStateDriver(g, "fight", "[combat] 1; 0") end
  H.guard = g
end
local function frames()
  if button then return end
  local anchor = A.Alerts.Anchor()
  button = CreateFrame("Button", "CuteAurasRestore", anchor, "SecureActionButtonTemplate")
  button:RegisterForClicks("AnyUp")
  button:SetAttribute("useOnKeyDown", false)
  button.bg = L.Fill(button, "BACKGROUND", C.PANEL, 0.85); button.bg:SetAllPoints()
  button.side = button:CreateTexture(nil, "BORDER")
  button.side:SetPoint("TOPLEFT"); button.side:SetPoint("BOTTOMLEFT"); button.side:SetWidth(3)
  button.side:SetColorTexture(C.QUEST[1], C.QUEST[2], C.QUEST[3], 1)
  -- (the icon look's parts: the gold edge round the icon, the gold bar and the name under it; art, never a frame of its
  -- own anchored to this button)
  button.edge = button:CreateTexture(nil, "BACKGROUND")
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.bar = button:CreateTexture(nil, "ARTWORK")
  button.bar:SetColorTexture(C.QUEST[1], C.QUEST[2], C.QUEST[3], 1)
  button.name = L.Text(button, 10, C.WHITE, 76)
  button.title = L.Text(button, 14, C.WHITE, 190, "LEFT")
  button.text = L.Text(button, 11, C.INK, 190, "LEFT", 2)
  button.hi = button:CreateTexture(nil, "HIGHLIGHT"); button.hi:SetAllPoints(); button.hi:SetColorTexture(1, 1, 1, 0.08)
  -- (the member and blessing a click casts, noted before it: a name the client hides in the cast's SENT is them;
  -- Roster.MemberFor)
  button:HookScript("PreClick", A.Roster.NoteClick)
  -- (a left click blesses them: a look at their auras after; a right click casts nothing (type1 only) and drops it)
  button:HookScript("OnClick", function(self, b)
    if b == "LeftButton" then A.After(0.8, H.Check, "hands: after a click")
    elseif b == "RightButton" and self.guid then H.Done(self.guid) end
  end)
  button:HookScript("OnEnter", function(self)
    A.Alerts.Tip(self, self.title:GetText(), self.text:GetText(), nil, "Click: bless them. Right-click: dismiss.")
  end)
  button:HookScript("OnLeave", function() A.Alerts.Untip() end)
  button:HookScript("OnShow", function() if A.Alerts then A.Alerts.Layout() end end)
  button:HookScript("OnHide", function() if A.Alerts then A.Alerts.Layout() end end)
  button:Hide()
  H.button = button
  A.OutOfFight("hands: guard", makeGuard)
end
-- the button's look for Show as (out of a fight: the caller's setSecure)
local function shapeButton()
  local Al = A.Alerts
  if Al.Icons() then Al.ShapeIcon(button) else Al.ShapeCard(button, Al.IconSize()) end
  Al.Edge(button.edge, button.icon, true)
end
-- its place in the click row (the overlay's Layout says where), out of a fight only
function H.Place(x)
  if not button or A.Fighting() then return end
  button:ClearAllPoints()
  button:SetPoint("TOP", A.Alerts.Anchor(), "TOP", x or 0, 0)
end
-- a pending restore's art: in a fight (where "fight"), or waiting after the click icon out of one ("next", at: its
-- place in the line); take: the alert whose slot it takes; before: a new one's place, before that alert
local function artCard(guid, where, take, at, before)
  local p, m = H.pending[guid], A.Roster.ByGUID(guid)
  if not (p and m) then return end
  local entry = D.BLESS[p.bless]
  -- (their row: the bar keeps the group's part in a fight, they are on your list for that blessing, and a shown row of
  -- that list reaches them, a member gone in the fight moving the unit tokens under the rows)
  local s = A.Settings()
  local row = false
  if s.fight ~= "hide" and s.group ~= false and not (A.Bar and A.Bar.Never("duty:bless:" .. p.bless)) then
    for _, o in ipairs(A.Assign.Owed(guid) or {}) do if o.key == "bless:" .. p.bless then row = true end end
  end
  if row and A.Bar and A.Bar.Reaches then row = A.Bar.Reaches(guid, p.bless) end
  local who = m.me and "You" or m.name
  local title, text = H.RestoreWords(who, p.bless, p.handName, where, row)
  A.Alerts.Show("restore:" .. guid, { icon = L.SpellIcon(entry.ranks[1], entry.icon), name = who, class = m.class,
    color = C.QUEST, gold = true, dim = where == "next", row = where == "next" and "click" or nil, at = at,
    keep = true, title = title, text = text, take = take, before = before, tip = where == "fight" and H.FIGHT_TIP or nil,
    onDismiss = function() H.Done(guid) end })
end
-- a roster change in a fight renamed the bar's rows (B.RenameRows): each restore's art, in its slot, says again whether
-- a row of its blessing's list reaches them
function H.Renamed()
  if not A.Fighting() then return end
  for _, guid in ipairs(H.order) do
    if H.pending[guid] and A.Alerts.Has("restore:" .. guid) then artCard(guid, "fight") end
  end
end
-- out of a fight: the first pending restore on the click icon, its art gone, the others' art waiting after it (one
-- sound when a restore first shows there); none (or alerts off), the button hidden. Within 0.4 s of one done it stays
-- hidden, whatever asks (holdUntil)
local holdUntil = 0
-- (you dead while the group fights on: the game ended your fight, not theirs; the click icon waits)
local function deadInFight()
  return A.Yes(UnitIsDeadOrGhost, "player") and A.Rebuff ~= nil and A.Rebuff.GroupFighting()
end
local function setSecure()
  frames()
  local wait = holdUntil - A.Now()
  if wait > 0 and not button:IsShown() then A.After(wait, H.Refresh, "hands: the next restore") return end
  local first
  if A.Alerts.On() then
    for _, guid in ipairs(H.order) do if H.pending[guid] and H.pending[guid].ready then first = guid break end end
  end
  if not first then
    if button:IsShown() then button:Hide() end
    button.guid = nil
    A.Alerts.Layout()
    return
  end
  local p = H.pending[first]
  local m = A.Roster.ByGUID(first)
  if not m then H.Done(first) return end
  -- (their unit someone else's now, the roster not read again yet: no click, H.Rostered sets it)
  if not theirs(m) then
    if button:IsShown() then button:Hide() end
    button.guid = nil
    A.Alerts.Layout()
    return
  end
  if deadNow(m) then H.Done(first) return end
  local entry = D.BLESS[p.bless]
  local id = S.Best(entry, m.level)
  if not id then H.Done(first) return end
  button:SetAttribute("type1", "spell")
  button:SetAttribute("spell", id)
  button:SetAttribute("unit", m.unit)
  L.Art(button.icon, L.SpellIcon(id, entry.icon))
  local who = m.me and "You" or m.name
  local title, text = H.RestoreWords(who, p.bless, p.handName, "secure")
  button.title:SetText(title)
  button.title:SetTextColor(L.ClassColor(m.class))
  button.text:SetText(text)
  A.Alerts.Name(button, who, m.class)
  button.guid = first
  shapeButton()
  A.Alerts.Hide("restore:" .. first)
  for i, guid in ipairs(H.order) do
    if guid ~= first and H.pending[guid] then artCard(guid, "next", nil, i) end
  end
  if not button:IsShown() then button:Show() end
  A.Alerts.Layout()
  -- (its one sound when you can click it: alive)
  if not p.sounded and not A.Yes(UnitIsDeadOrGhost, "player") then p.sounded = true; A.Alerts.Sound() end
end
-- (in a fight nothing: the look 0.5 s after it sets the click icon. Dead while the group fights: a look every 2 s
-- until its fight is over or you are back)
local polling = false
function H.Refresh()
  if A.Fighting() then return end
  if deadInFight() then
    if not polling then
      polling = true
      A.After(2, function() polling = false; H.Refresh() end, "hands: the group's fight")
    end
    return
  end
  setSecure()
end
function H.Done(guid)
  if not H.pending[guid] then return end
  H.pending[guid] = nil
  for i = #H.order, 1, -1 do if H.order[i] == guid then table.remove(H.order, i) end end
  A.Alerts.Hide("restore:" .. guid)
  if A.Bar then A.Bar.GlowMember(guid, false) end
  if button and button.guid == guid then
    -- (the click icon goes at once and the next restore takes it 0.4 s later: a fast double click never blesses the
    -- next member; in a fight its guard hid it already)
    button.guid = nil
    if not A.Fighting() and button:IsShown() then button:Hide() end
    holdUntil = A.Now() + 0.4
    A.After(0.4, H.Refresh, "hands: the next restore")
    return
  end
  H.Refresh()
end

-- a Hand ended: the restore, art in a fight in the countdown's slot; out of one the click icon. Out of a fight their
-- auras are plain: a Hand still on them (a talent the data does not know) puts the end off to the aura's own
local running = {} -- [guid] = { t, bless, handName, entry }: the Hand on them (a newer Hand's clock wins)
local ending = {}  -- [guid] = t: that Hand's end already looking at their auras (the countdown's end and the timer's
                   -- start one look, not two)
local cNames, cIds, cPool = {}, {}, {}
local function ended(guid, t, tries)
  local r = running[guid]
  if not (r and r.t == t) then return end
  local m = A.Roster.ByGUID(guid)
  if not (m and r.bless and D.BLESS[r.bless]) then running[guid], ending[guid] = nil, nil; return end
  if not A.Fighting() and r.entry and (tries or 0) < 5 then
    local _, _, hidden = S.ReadAuras(m.unit, cNames, cIds, cPool)
    local on = not hidden and S.On(r.entry, cNames, cIds)
    if on then
      local left = on.exp and (on.exp - A.Now()) or 1
      ending[guid] = t
      A.After(math.max(0.2, math.min(left, 30)) + 0.1, function() ended(guid, t, (tries or 0) + 1) end, "hands: still on")
      return
    end
  end
  running[guid], ending[guid] = nil, nil
  H.pending[guid] = { bless = r.bless, handName = r.handName, ready = true, at = A.Now() }
  for i = #H.order, 1, -1 do if H.order[i] == guid then table.remove(H.order, i) end end
  table.insert(H.order, guid)
  if A.Bar then A.Bar.GlowMember(guid, true) end
  -- (no sound in a fight: nothing to click there; the click icon's own after it. Dead while the group fights: art too)
  if A.Fighting() or deadInFight() then artCard(guid, "fight", "hand:" .. guid)
  else A.Alerts.Hide("hand:" .. guid) end
  H.Refresh()
end
-- a Hand's end, from its own timer or its countdown's (the one that comes first; the other finds it done)
function H.EndNow(guid, t)
  if ending[guid] == t then return end
  ended(guid, t)
end

local function onSucceeded(_, unit, castGUID, spell)
  if plain(unit) ~= "player" then return end
  local sp, cg = plain(spell), plain(castGUID)
  if type(sp) ~= "number" then return end
  local guid = A.Roster.SentTo(cg)
  if BLESS[sp] then
    -- (any blessing of yours on them replaces the one they lost: their restore is done. A Hand of yours still on them
    -- is gone with it, one blessing a paladin: no restore at its end, and a Hand after it takes this one)
    if guid then
      lastBless[guid] = { key = BLESS[sp], at = A.Now() }
      if running[guid] then running[guid], ending[guid] = nil, nil; A.Alerts.Hide("hand:" .. guid) end
      if H.pending[guid] then H.Done(guid) end
    end
    return
  end
  local h = HAND[sp]
  if not (h and guid) or A.Settings().hands == false then return end
  local m = A.Roster.ByGUID(guid)
  if not m then return end
  -- (a restore waiting on them: the new Hand takes its slot, and its blessing is still the one they lost; a Hand of
  -- yours still on them: the one it took off, never a read since that found none of yours)
  local waiting = H.pending[guid]
  local bless = (waiting and waiting.bless) or (running[guid] and running[guid].bless) or lostBlessing(guid)
  local handName = L.SpellName(sp, h.entry.name)
  local t = A.Now()
  local dur = h.dur + H.Bonus(h.entry)
  -- (the Hand's own clock: the countdown only shows it, so one dismissed, or alerts off, still brings the restore)
  running[guid], ending[guid] = { t = t, bless = bless, handName = handName, entry = h.entry }, nil
  A.After(dur, function() H.EndNow(guid, t) end, "hands: end")
  local who = m.me and "You" or m.name
  local title, text = H.HandWords(who, handName, bless)
  A.Alerts.Show("hand:" .. guid, { icon = L.SpellIcon(sp, h.entry.icon), name = who, class = m.class, color = C.PINK,
    title = title, text = text, expires = t + dur, duration = dur, take = waiting and ("restore:" .. guid) or nil,
    onEnd = function() H.EndNow(guid, t) end })
  -- (their glow off while the Hand is on: a blessing now would take it off; the restore comes back at its end)
  if waiting then H.Done(guid) end
end

-- out of a fight: a restore done once they have the blessing again (anyone's of that kind), they died, or they left
local copy = {}
function H.Check()
  if A.Fighting() or #H.order == 0 then return end
  for i = #copy, 1, -1 do copy[i] = nil end
  for i, guid in ipairs(H.order) do copy[i] = guid end
  for _, guid in ipairs(copy) do
    local p = H.pending[guid]
    local m = A.Roster.ByGUID(guid)
    if not m then H.Done(guid)
    elseif p and theirs(m) and deadNow(m) then H.Done(guid)
    elseif p and theirs(m) then
      local _, _, hidden = S.ReadAuras(m.unit, cNames, cIds, cPool)
      if not hidden and S.On(D.BLESS[p.bless], cNames, cIds) then H.Done(guid) end
    end
  end
end
-- the roster read again (Roster.Changed): out of a fight, the restores looked at and the click icon set to its member's
-- unit now
function H.Rostered()
  if #H.order == 0 or A.Fighting() then return end
  H.Check()
  H.Refresh()
end
-- Settings: the Hands off, every restore let go
function H.Setting()
  if A.Settings().hands ~= false then return end
  for k in pairs(running) do running[k] = nil end
  for k in pairs(ending) do ending[k] = nil end
  for i = #H.order, 1, -1 do H.Done(H.order[i]) end
end

function H:Init()
  frames()
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onSucceeded)
  -- (a fight starts: its guard hides the click icon, and every restore shows as art, in the art row, where a new Hand
  -- on them takes its slot)
  A.On("PLAYER_REGEN_DISABLED", function()
    -- (the click icon's restore, the oldest, before the ones that waited after it, as they stood)
    local before
    for _, guid in ipairs(H.order) do
      if H.pending[guid] and A.Alerts.Has("restore:" .. guid) then before = "restore:" .. guid break end
    end
    for _, guid in ipairs(H.order) do if H.pending[guid] then artCard(guid, "fight", nil, nil, before) end end
  end)
  A.On("PLAYER_REGEN_ENABLED", function() A.After(0.5, function() H.Check(); H.Refresh() end, "hands: after the fight") end)
  for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "SPELLS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
    A.On(ev, function() ranks = nil end)
  end
  -- (a group member's auras only, one look in half a second: never every nameplate's)
  local checkSoon = false
  A.On("UNIT_AURA", function(_, unit)
    unit = plain(unit)
    if #H.order == 0 or A.Fighting() or checkSoon or type(unit) ~= "string" then return end
    if not (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then return end
    checkSoon = true
    A.After(0.5, function() checkSoon = false; H.Check() end, "hands: a look")
  end)
  -- (a member who left moves the unit tokens: the click icon whose unit someone else holds now hides until the roster
  -- is read again, H.Rostered)
  A.On("GROUP_ROSTER_UPDATE", function()
    if A.Fighting() then return end
    H.Check()
    if button and button:IsShown() and button.guid and plain(call(UnitGUID, button:GetAttribute("unit"))) ~= button.guid then
      button:Hide()
      button.guid = nil
      A.Alerts.Layout()
    end
  end)
  -- (back from the dead: the click icon, and its sound)
  for _, ev in ipairs({ "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    A.On(ev, function() if #H.order > 0 then H.Refresh() end end)
  end
  -- (a member's death: every blessing on them gone, yours too. Looked at only for a group member whose newest note is a
  -- blessing of yours: once their death is noted, their health costs nothing more)
  A.On("UNIT_HEALTH", function(_, unit)
    if next(lastBless) == nil and next(H.saw) == nil then return end
    unit = plain(unit)
    local m = type(unit) == "string" and A.Roster.ByUnit(unit)
    if not m then return end
    local s, c = H.saw[m.guid], lastBless[m.guid]
    local newest = s
    if c and (not s or c.at > s.at) then newest = c end
    if not (newest and newest.key) then return end
    if A.Yes(UnitIsDeadOrGhost, unit) and not A.Yes(UnitIsFeignDeath, unit) then H.saw[m.guid] = { at = A.Now() } end
  end)
end
