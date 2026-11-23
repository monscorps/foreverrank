-- SPDX-License-Identifier: GPL-3.0-or-later
-- Blessing of Protection, Freedom and Sacrifice. Each is a blessing, and a paladin's blessings are one per target: the
-- Hand takes your long blessing off them. Your cast (UNIT_SPELLCAST_SENT names its target; a hidden name falls back to
-- your target or mouseover) starts a countdown card on the alerts overlay; at its end a restore card names the blessing
-- they lost (the one Cute Auras shares out to them, else the last you gave them). In a fight the card is art and their
-- row in the bar's flyout glows (a secure button can't be set there); out of a fight, or once the fight ends, the
-- restore card is the game's secure button set to them: a click blesses them. It goes once they have it again.
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
local sent = {}      -- [castGUID] = the target's GUID

local function memberFor(targetName)
  local m = A.Roster.ByName(targetName)
  if m then return m end
  for _, u in ipairs({ "target", "mouseover" }) do
    local g = plain(call(UnitGUID, u))
    if g and A.Roster.ByGUID(g) and A.Yes(UnitIsFriend, "player", u) then return A.Roster.ByGUID(g) end
  end
  return nil
end
local function onSent(_, unit, target, castGUID, spell)
  if plain(unit) ~= "player" then return end
  local sp, cg = plain(spell), plain(castGUID)
  if not (type(sp) == "number" and cg and (HAND[sp] or BLESS[sp])) then return end
  local m = memberFor(plain(target))
  if m then sent[cg] = m.guid end
end

-- the blessing they lose: Cute Auras' share-out, else your last on them
local function lostBlessing(guid)
  for _, o in ipairs(A.Assign.Owed(guid) or {}) do
    if o.key:find("^bless:") then return o.key:sub(7) end
  end
  return lastBless[guid]
end
function H.Glowing(guid) return H.pending[guid] ~= nil end

----------------------------------------------------------------------------
-- the secure restore card: the first pending restore, set out of a fight only (one slot under the rebuff card)
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
  button.icon:SetPoint("LEFT", button, "LEFT", 7, 0)
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.title = L.Text(button, 14, C.WHITE, 190, "LEFT")
  button.title:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 9, -4)
  button.text = L.Text(button, 11, C.INK, 190, "LEFT")
  button.text:SetPoint("TOPLEFT", button.title, "BOTTOMLEFT", 0, -3)
  button.hi = button:CreateTexture(nil, "HIGHLIGHT"); button.hi:SetAllPoints(); button.hi:SetColorTexture(1, 1, 1, 0.08)
  button:HookScript("OnClick", function(_, b) if b == "LeftButton" then A.After(0.8, H.Check, "hands: after a click") end end)
  button:HookScript("OnShow", function() if A.Alerts then A.Alerts.Layout() end end)
  button:HookScript("OnHide", function() if A.Alerts then A.Alerts.Layout() end end)
  button:Hide()
  H.button = button
end
local function place()
  local s = A.Alerts.IconSize()
  button:SetSize(s + 210, s + 8)
  button.icon:SetSize(s, s)
  -- (its own slot, the second: the rebuff card may take the first in a fight, where nothing secure can move)
  button:ClearAllPoints()
  button:SetPoint("TOP", A.Alerts.Anchor(), "TOP", 0, -(s + 8 + 6))
end
-- out of a fight: the first pending restore on the secure card, its art card hidden; none, the card hidden
local function setSecure()
  frames()
  local first
  for _, guid in ipairs(H.order) do if H.pending[guid] and H.pending[guid].ready then first = guid break end end
  if not first then
    if button:IsShown() then button:Hide() end
    button.guid = nil
    return
  end
  local p = H.pending[first]
  local m = A.Roster.ByGUID(first)
  if not m then H.Done(first) return setSecure() end
  local entry = D.BLESS[p.bless]
  local id = S.Best(entry, m.level)
  if not id then H.Done(first) return setSecure() end
  button:SetAttribute("type1", "spell")
  button:SetAttribute("spell", id)
  button:SetAttribute("unit", m.unit)
  L.Art(button.icon, L.SpellIcon(id, entry.icon))
  button.title:SetText(L.SpellName(entry.ranks[1], entry.name) .. " back on " .. (m.me and "you" or m.name))
  button.title:SetTextColor(L.ClassColor(m.class))
  button.text:SetText("Your " .. (p.handName or "Hand") .. " took it off. Click to bless them.")
  button.guid = first
  place()
  if not button:IsShown() then button:Show() end
  A.Alerts.Hide("restore:" .. first)
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

-- a Hand ended: the restore, art now; the secure card out of a fight
local function ended(guid, bless, handName)
  local m = A.Roster.ByGUID(guid)
  if not (m and bless and D.BLESS[bless]) then return end
  H.pending[guid] = { bless = bless, handName = handName, ready = true, at = A.Now() }
  table.insert(H.order, guid)
  if A.Bar then A.Bar.GlowMember(guid, true) end
  local entry = D.BLESS[bless]
  if A.Fighting() then
    A.Alerts.Show("restore:" .. guid, { icon = L.SpellIcon(entry.ranks[1], entry.icon), class = m.class, color = C.QUEST, sound = true, keep = true,
      title = L.SpellName(entry.ranks[1], entry.name) .. " back on " .. (m.me and "you" or m.name),
      text = "In a fight: their row glows in the bar's " .. (L.SpellName(entry.ranks[1], entry.name) or "blessing") .. " list.",
      tip = "Once the fight ends this card is a click that blesses them." })
  end
  if A.Alerts then A.Alerts.Sound() end
  H.Refresh()
end

local function onSucceeded(_, unit, castGUID, spell)
  if plain(unit) ~= "player" then return end
  local sp, cg = plain(spell), plain(castGUID)
  if type(sp) ~= "number" then return end
  local guid = cg and sent[cg]
  if cg then sent[cg] = nil end
  if BLESS[sp] then
    if guid then lastBless[guid] = BLESS[sp]; if H.pending[guid] and H.pending[guid].bless == BLESS[sp] then H.Done(guid) end end
    return
  end
  local h = HAND[sp]
  if not (h and guid) or A.Settings().hands == false then return end
  local m = A.Roster.ByGUID(guid)
  if not m then return end
  local bless = lostBlessing(guid)
  local handName = L.SpellName(sp, h.entry.name)
  local t = A.Now()
  local entry = bless and D.BLESS[bless]
  A.Alerts.Show("hand:" .. guid, { icon = L.SpellIcon(sp, h.entry.icon), class = m.class, color = C.PINK,
    title = handName .. ": " .. (m.me and "you" or m.name),
    text = entry and (L.SpellName(entry.ranks[1], entry.name) .. " goes back on as it ends.") or "Ends in the time shown.",
    expires = t + h.dur, duration = h.dur,
    onEnd = function() ended(guid, bless, handName) end })
end

-- out of a fight: a restore done once they have the blessing again (anyone's of that kind), or they left
local cNames, cIds, cPool, copy = {}, {}, {}, {}
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

function H:Init()
  frames()
  A.OnUnit("UNIT_SPELLCAST_SENT", { "player" }, onSent)
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onSucceeded)
  A.On("PLAYER_REGEN_ENABLED", function() A.After(0.5, function() H.Check(); H.Refresh() end, "hands: after the fight") end)
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
