-- SPDX-License-Identifier: GPL-3.0-or-later
-- Blessing of Protection, Freedom and Sacrifice. Each is a blessing, and a paladin's blessings are one per target: the
-- Hand takes your long blessing off them. Your cast (UNIT_SPELLCAST_SENT names its target; a hidden name is the member
-- a button of ours cast on, else your target or mouseover: Roster.SentTo) starts the Hand's own clock (its duration,
-- with your talents that lengthen it) and a countdown card on the alerts overlay that only shows it; at its end a
-- restore names the blessing they lost (the one Cute Auras shares out to them, else the last you gave them). In a fight
-- the restore is an art card and their row in the bar's flyout glows (a secure button can't be set there); out of a
-- fight, or once the fight ends, the restore card is the game's secure button set to them: a click blesses them. It
-- goes once they have it again, once any blessing of yours lands on them, or on a right-click. "Alerts on screen" off:
-- no cards, the row's glow alone.
local _, A = ...
local H = A.Part("Hands", { pending = {}, order = {} })
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
local lastBless = {} -- [guid] = the blessing you last gave them (this session)
local handAt = {}    -- [guid] = the time of your last Hand on them (a newer Hand's clock wins)

-- the blessing they lose: Cute Auras' share-out, else your last on them
local function lostBlessing(guid)
  for _, o in ipairs(A.Assign.Owed(guid) or {}) do
    if o.key:find("^bless:") then return o.key:sub(7) end
  end
  return lastBless[guid]
end
function H.Glowing(guid) return H.pending[guid] ~= nil end

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
-- the cards' words (the test cards use them too): the member's name first, a blessing's short name, a line that wraps
----------------------------------------------------------------------------
function H.HandWords(name, handName, bless)
  local entry = bless and D.BLESS[bless]
  local title = (name or "?") .. ": " .. (L.Short(handName) or "Hand")
  if entry then return title, "Then " .. L.Short(L.SpellName(entry.ranks[1], entry.name)) .. " goes back on." end
  return title, "Ends as the count runs out."
end
-- where: "secure" the click card, "next" waiting behind it, "fight" in a fight (row: their row in the bar's list glows)
function H.RestoreWords(name, bless, handName, where, row)
  local entry = D.BLESS[bless]
  local short = L.Short(L.SpellName(entry.ranks[1], entry.name))
  local title = (name or "?") .. ": " .. short
  if where == "secure" then return title, "Your " .. (L.Short(handName) or "Hand") .. " took it off. Click: bless them again." end
  if where == "next" then return title, "Next, once the card above is done." end
  if row then return title, "Their row glows in the bar's " .. short .. " list." end
  return title, "Target them and give them " .. short .. "."
end

----------------------------------------------------------------------------
-- the secure restore card: the first pending restore, set out of a fight only (at the overlay's top, the rebuff card
-- under it)
----------------------------------------------------------------------------
local button
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
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
end
local function place()
  A.Alerts.ShapeCard(button, A.Alerts.IconSize())
  button:ClearAllPoints()
  button:SetPoint("TOP", A.Alerts.Anchor(), "TOP", 0, 0)
end
-- a pending restore's art card: in a fight (where), or waiting behind the secure card out of one
local function artCard(guid, where)
  local p, m = H.pending[guid], A.Roster.ByGUID(guid)
  if not (p and m) then return end
  local entry = D.BLESS[p.bless]
  -- (their row: the bar keeps the group's part in a fight, and they are on your list for that blessing)
  local s = A.Settings()
  local row = false
  if s.fight ~= "hide" and s.group ~= false and not (A.Bar and A.Bar.Never("duty:bless:" .. p.bless)) then
    for _, o in ipairs(A.Assign.Owed(guid) or {}) do if o.key == "bless:" .. p.bless then row = true end end
  end
  local title, text = H.RestoreWords(m.me and "You" or m.name, p.bless, p.handName, where, row)
  A.Alerts.Show("restore:" .. guid, { icon = L.SpellIcon(entry.ranks[1], entry.icon), class = m.class, color = C.QUEST,
    keep = true, title = title, text = text,
    tip = where == "fight" and "After the fight a click card blesses them, one at a time." or nil,
    onDismiss = function() H.Done(guid) end })
end
-- out of a fight: the first pending restore on the secure card, its art card hidden, the others' saying they are next;
-- none (or alerts off), the card hidden and the rebuff card back at the top
local function setSecure()
  frames()
  local first
  if A.Alerts.On() then
    for _, guid in ipairs(H.order) do if H.pending[guid] and H.pending[guid].ready then first = guid break end end
  end
  if not first then
    if button:IsShown() then button:Hide() end
    button.guid = nil
    if A.Rebuff and A.Rebuff.StackUnder then A.Rebuff.StackUnder(nil) end
    return
  end
  local p = H.pending[first]
  local m = A.Roster.ByGUID(first)
  if not m then H.Done(first) return end
  local entry = D.BLESS[p.bless]
  local id = S.Best(entry, m.level)
  if not id then H.Done(first) return end
  button:SetAttribute("type1", "spell")
  button:SetAttribute("spell", id)
  button:SetAttribute("unit", m.unit)
  L.Art(button.icon, L.SpellIcon(id, entry.icon))
  local title, text = H.RestoreWords(m.me and "You" or m.name, p.bless, p.handName, "secure")
  button.title:SetText(title)
  button.title:SetTextColor(L.ClassColor(m.class))
  button.text:SetText(text)
  button.guid = first
  place()
  if not button:IsShown() then button:Show() end
  if A.Rebuff and A.Rebuff.StackUnder then A.Rebuff.StackUnder(button) end
  A.Alerts.Hide("restore:" .. first)
  for _, guid in ipairs(H.order) do
    if guid ~= first and A.Alerts.Has("restore:" .. guid) then artCard(guid, "next") end
  end
end
function H.Refresh() A.OutOfFight("hands: card", setSecure) end
function H.Done(guid)
  if not H.pending[guid] then return end
  H.pending[guid] = nil
  for i = #H.order, 1, -1 do if H.order[i] == guid then table.remove(H.order, i) end end
  A.Alerts.Hide("restore:" .. guid)
  if A.Bar then A.Bar.GlowMember(guid, false) end
  H.Refresh()
end

-- a Hand ended: the restore, art now; the secure card out of a fight. Out of a fight their auras are plain: a Hand still
-- on them (a talent the data does not know) puts the end off to the aura's own
local cNames, cIds, cPool = {}, {}, {}
local function ended(guid, bless, handName, hand, tries)
  local m = A.Roster.ByGUID(guid)
  if not (m and bless and D.BLESS[bless]) then return end
  if not A.Fighting() and hand and (tries or 0) < 5 then
    local _, _, hidden = S.ReadAuras(m.unit, cNames, cIds, cPool)
    local on = not hidden and S.On(hand, cNames, cIds)
    if on then
      local left = on.exp and (on.exp - A.Now()) or 1
      local t = handAt[guid]
      A.After(math.max(0.2, math.min(left, 30)) + 0.1, function()
        if handAt[guid] == t then ended(guid, bless, handName, hand, (tries or 0) + 1) end
      end, "hands: still on")
      return
    end
  end
  handAt[guid] = nil
  H.pending[guid] = { bless = bless, handName = handName, ready = true, at = A.Now() }
  for i = #H.order, 1, -1 do if H.order[i] == guid then table.remove(H.order, i) end end
  table.insert(H.order, guid)
  if A.Bar then A.Bar.GlowMember(guid, true) end
  if A.Fighting() then artCard(guid, "fight") end
  if A.Alerts.On() then A.Alerts.Sound() end
  H.Refresh()
end

local function onSucceeded(_, unit, castGUID, spell)
  if plain(unit) ~= "player" then return end
  local sp, cg = plain(spell), plain(castGUID)
  if type(sp) ~= "number" then return end
  local guid = A.Roster.SentTo(cg)
  if BLESS[sp] then
    -- (any blessing of yours on them replaces the one they lost: their restore is done)
    if guid then lastBless[guid] = BLESS[sp]; if H.pending[guid] then H.Done(guid) end end
    return
  end
  local h = HAND[sp]
  if not (h and guid) or A.Settings().hands == false then return end
  local m = A.Roster.ByGUID(guid)
  if not m then return end
  local bless = lostBlessing(guid)
  local handName = L.SpellName(sp, h.entry.name)
  local t = A.Now()
  local dur = h.dur + H.Bonus(h.entry)
  -- (the Hand's own clock: the card only shows it, so a card dismissed, or alerts off, still brings the restore)
  handAt[guid] = t
  A.After(dur, function() if handAt[guid] == t then ended(guid, bless, handName, h.entry) end end, "hands: end")
  local title, text = H.HandWords(m.me and "You" or m.name, handName, bless)
  A.Alerts.Show("hand:" .. guid, { icon = L.SpellIcon(sp, h.entry.icon), class = m.class, color = C.PINK,
    title = title, text = text, expires = t + dur, duration = dur })
end

-- out of a fight: a restore done once they have the blessing again (anyone's of that kind), or they left
local copy = {}
function H.Check()
  if A.Fighting() or #H.order == 0 then return end
  for i = #copy, 1, -1 do copy[i] = nil end
  for i, guid in ipairs(H.order) do copy[i] = guid end
  for _, guid in ipairs(copy) do
    local p = H.pending[guid]
    local m = A.Roster.ByGUID(guid)
    if not m then H.Done(guid)
    elseif p then
      local _, _, hidden = S.ReadAuras(m.unit, cNames, cIds, cPool)
      if not hidden and S.On(D.BLESS[p.bless], cNames, cIds) then H.Done(guid) end
    end
  end
end
-- Settings: the Hands off, every restore let go
function H.Setting()
  if A.Settings().hands ~= false then return end
  for k in pairs(handAt) do handAt[k] = nil end
  for i = #H.order, 1, -1 do H.Done(H.order[i]) end
end

function H:Init()
  frames()
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onSucceeded)
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
  A.On("GROUP_ROSTER_UPDATE", function() if not A.Fighting() then H.Check() end end)
end
