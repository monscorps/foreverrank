-- SPDX-License-Identifier: GPL-3.0-or-later
-- Buffing again after a death in a fight, by the one buffer who owes it. An addon can't set a secure button in a fight,
-- so the game's own secure code does it: out of a fight Cute Auras gives a secure handler, for each member you owe a
-- buff (Assign.lua), their unit, your spells for them, and a state driver on their death, "[@raid5,dead] 1; 0". In a
-- fight, a member who dies and comes back (a combat resurrection, a soulstone, Reincarnation) joins the handler's queue,
-- and its snippet points the rebuff card (a secure button at the alerts overlay's top) at the first one and your first
-- spell for them. A click casts it and moves on to their next spell; the secure code can't tell a cast that landed from
-- one the game refused (the global cooldown, a cast going, range), so the spell goes to the back of their list and
-- comes round again, and the card says which of your spells the game has seen land (UNIT_SPELLCAST_SUCCEEDED). A
-- right-click is "done with them": the next member. A member who leaves or joins in a fight moves the unit tokens
-- (raid5 is someone else then): a group header of the game's watches each member by name and points their slot at
-- their new unit. Your own death keeps the queue while the group fights on. After the fight the queue is cleared; the
-- bar's own reading of auras takes over. Hunters are left out: Feign Death reads as a death.
local _, A = ...
local Rb = A.Part("Rebuff", { slots = 0, shows = 0, done = {} })
local L, S = A.Look, A.Spells
local C = L.C
local plain, call = A.Plain, A.Call

-- (the restricted snippets: strings the game runs in its secure environment, no table constructors, attributes for state)
-- a member's death and return; self is the handler, stateid "dN", newstate 1 dead or 0 alive (the state driver hands
-- a number: SecureStateDriver.lua's tonumber, the string only on an old client). Dead again before your click: out of
-- the queue (the card moves on if it showed them); back up in a fight, or while you are dead in one ("hold"): queued,
-- all your spells for them again ("rev" counts their returns, for the card's words)
local STATE = [[
  local i = tonumber(strsub(stateid, 2))
  if not i then return end
  local q = self:GetAttribute("queue") or ","
  if newstate == 1 or newstate == "1" then
    self:SetAttribute("dead" .. i, 1)
    if strfind(q, "," .. i .. ",", 1, true) then
      self:SetAttribute("queue", (gsub(q, "," .. i .. ",", ",")))
      if self:GetFrameRef("btn"):GetAttribute("idx") == i then self:RunAttribute("next") end
    end
    return
  end
  if not self:GetAttribute("dead" .. i) then return end
  self:SetAttribute("dead" .. i, nil)
  if not (PlayerInCombat() or self:GetAttribute("hold")) then return end
  if not strfind(q, "," .. i .. ",", 1, true) then q = q .. i .. "," end
  self:SetAttribute("queue", q)
  self:SetAttribute("p" .. i, self:GetAttribute("s" .. i))
  self:SetAttribute("rev" .. i, (self:GetAttribute("rev" .. i) or 0) + 1)
  self:RunAttribute("next")
]]
-- the card set to the first queued member and their first spell left, or hidden with none; hidden while you are dead
-- (the queue kept for when you are back). "idx" is set last: the card's words are painted once, from it
local NEXT = [[
  local b = self:GetFrameRef("btn")
  local q = self:GetAttribute("queue") or ","
  if UnitIsDead("player") then
    b:SetAttribute("idx", nil)
    b:Hide()
    return
  end
  while true do
    local i = tonumber(strmatch(q, "^,(%d+),"))
    if not i then
      self:SetAttribute("queue", ",")
      b:SetAttribute("idx", nil)
      b:Hide()
      return
    end
    local p = self:GetAttribute("p" .. i) or ""
    local first = strmatch(p, "^([^,]+)")
    local u = self:GetAttribute("u" .. i)
    if first and u then
      b:SetAttribute("*type1", "spell")
      b:SetAttribute("unit", u)
      b:SetAttribute("spell", tonumber(first) or first)
      b:SetAttribute("idx", i)
      b:Show()
      return
    end
    q = "," .. (strmatch(q, "^,%d+,(.*)$") or "")
    self:SetAttribute("queue", q)
  end
]]
-- the card's click (self the card, control the handler). Right: done with them, out of the queue, nothing cast. Left,
-- with any modifier: the cast, then POST. Any other button: nothing
local PRE = [[
  local i = self:GetAttribute("idx")
  if button == "RightButton" then
    if i then
      control:SetAttribute("queue", (gsub(control:GetAttribute("queue") or ",", "," .. i .. ",", ",")))
      control:SetAttribute("p" .. i, nil)
    end
    control:RunAttribute("next")
    return false
  end
  if button ~= "LeftButton" then return false end
  return nil, "cast"
]]
-- after the cast: the spell to the back of their list, the next one on the card (a refused click comes round again)
local POST = [[
  local i = self:GetAttribute("idx")
  if i and message == "cast" then
    local p = control:GetAttribute("p" .. i) or ""
    local first, rest = strmatch(p, "^([^,]+),?(.*)$")
    if first and rest ~= "" then control:SetAttribute("p" .. i, rest .. "," .. first) end
  end
  control:RunAttribute("next")
]]
-- a slot's member on a new unit (the watcher's child below heard it; self the handler, ... the slot): their dead state
-- read again and their driver on the new unit; gone from the group, the slot let go
local REMAP = [[
  local i = ...
  local u = self:GetAttribute("u" .. i)
  UnregisterStateDriver(self, "d" .. i)
  if u then
    if UnitIsDead(u) then self:SetAttribute("dead" .. i, 1) else self:SetAttribute("dead" .. i, nil) end
    RegisterStateDriver(self, "d" .. i, "[@" .. u .. ",dead] 1; 0")
  else
    self:SetAttribute("dead" .. i, nil)
    self:SetAttribute("queue", (gsub(self:GetAttribute("queue") or ",", "," .. i .. ",", ",")))
  end
  if self:GetFrameRef("btn"):IsShown() then self:RunAttribute("next") end
]]
-- the watcher's child: the game's group header set its unit (a roster change, in a fight too); a new one goes to the
-- handler, for its slot
local WATCH = [[
  if name ~= "unit" then return end
  local h = self:GetFrameRef("rb")
  local i = self:GetAttribute("slot")
  if not (h and i) or h:GetAttribute("u" .. i) == value then return end
  h:SetAttribute("u" .. i, value)
  h:RunAttribute("remap", i)
]]
Rb.SNIPPETS = { STATE = STATE, NEXT = NEXT, PRE = PRE, POST = POST, REMAP = REMAP, WATCH = WATCH }

-- the card's words: its title (who, first), its line (state "cast" a spell to cast, "on" the spell shown landed, "all"
-- every one did)
function Rb.Words(name, spellName, state)
  local title = (name or "A member") .. " is up again"
  spellName = spellName or "Your buff"
  if state == "all" then return title, "All your buffs are on them. Right-click: done." end
  if state == "on" then return title, spellName .. " is on them. A click casts it again." end
  return title, spellName .. ". Click to buff them."
end

local handler, button
local watchers = {}
-- the spells of a slot, as numbers
local function slotSpells(i)
  local s = i and handler and handler:GetAttribute("s" .. i)
  local ids = {}
  if type(s) == "string" then for id in s:gmatch("[^,]+") do ids[#ids + 1] = tonumber(id) or id end end
  return ids
end
local function paint()
  local b = button
  if not b then return end
  local unit, spell, i = b:GetAttribute("unit"), b:GetAttribute("spell"), b:GetAttribute("idx")
  if not (unit and spell and i) then return end
  local m = A.Roster.ByUnit(unit)
  local name = plain(call(UnitName, unit))
  name = type(name) == "string" and name or (m and m.name) or nil
  local done = Rb.done[i] or {}
  local all = true
  for _, id in ipairs(slotSpells(i)) do if not done[id] then all = false end end
  local state = all and "all" or (done[spell] and "on") or "cast"
  local title, text = Rb.Words(name, L.SpellName(spell, "Your buff"), state)
  L.Art(b.icon, L.SpellIcon(spell, 134400))
  b.icon:SetDesaturated(state ~= "cast")
  b.title:SetText(title)
  if m and m.class then b.title:SetTextColor(L.ClassColor(m.class)) else b.title:SetTextColor(C.WHITE[1], C.WHITE[2], C.WHITE[3]) end
  b.text:SetText(text)
  -- (a new member on the card, or one back up again: the pulse, the count, the sound; your own clicks never)
  local key = i .. ":" .. tostring(handler:GetAttribute("rev" .. i) or 0)
  if Rb.painted ~= key then
    Rb.painted = key
    b.born = A.Now()
    Rb.shows = Rb.shows + 1
    if A.Alerts then A.Alerts.Sound() end
  end
end
local function shape()
  if not button or A.Fighting() then return end
  A.Alerts.ShapeCard(button, A.Alerts.IconSize())
end
Rb.Restyle = function() A.OutOfFight("rebuff: size", shape) end
-- out of a fight: the card at the overlay's top, or under Hands' restore card while that one shows
function Rb.StackUnder(card)
  if not button or A.Fighting() then return end
  button:ClearAllPoints()
  if card then button:SetPoint("TOP", card, "BOTTOM", 0, -A.Alerts.GAP)
  else button:SetPoint("TOP", A.Alerts.Anchor(), "TOP", 0, 0) end
end

-- your casts: a spell of the card's member sent (its target's name, where plain, theirs) and landed
local sent = {}
local function onSent(_, unit, target, castGUID, spell)
  if plain(unit) ~= "player" or not button then return end
  local sp, cg, i = plain(spell), plain(castGUID), button:GetAttribute("idx")
  if not (type(sp) == "number" and cg and i and button:IsShown()) then return end
  local mine = false
  for _, id in ipairs(slotSpells(i)) do if id == sp then mine = true end end
  if not mine then return end
  local t, who = plain(target), plain(call(UnitName, button:GetAttribute("unit")))
  if type(t) == "string" and t ~= "" and type(who) == "string" and t:match("^[^-]+") ~= who then return end
  sent[cg] = i
end
local function onSucceeded(_, unit, castGUID, spell)
  if plain(unit) ~= "player" then return end
  local sp, cg = plain(spell), plain(castGUID)
  local i = cg and sent[cg]
  if not (i and type(sp) == "number") then return end
  sent[cg] = nil
  Rb.done[i] = Rb.done[i] or {}
  Rb.done[i][sp] = true
  if button and button:GetAttribute("idx") == i then paint() end
end

local function frames()
  if button then return end
  local anchor = A.Alerts.Anchor()
  handler = CreateFrame("Frame", "CuteAurasRebuffHandler", UIParent, "SecureHandlerStateTemplate")
  button = CreateFrame("Button", "CuteAurasRebuff", anchor, "SecureActionButtonTemplate")
  -- (one edge: a wrap runs on every edge it hears, so a click that also heard its down would move the queue twice; the
  -- cast on the up, whatever the game's ActionButtonUseKeyDown says, SecureTemplates.lua's useOnKeyDown)
  button:RegisterForClicks("AnyUp")
  button:SetAttribute("useOnKeyDown", false)
  button:SetPoint("TOP", anchor, "TOP", 0, 0)
  button.bg = L.Fill(button, "BACKGROUND", C.PANEL, 0.85); button.bg:SetAllPoints()
  button.side = button:CreateTexture(nil, "BORDER")
  button.side:SetPoint("TOPLEFT"); button.side:SetPoint("BOTTOMLEFT"); button.side:SetWidth(3)
  button.side:SetColorTexture(C.GROUP[1], C.GROUP[2], C.GROUP[3], 1)
  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.title = L.Text(button, 14, C.WHITE, 190, "LEFT")
  button.text = L.Text(button, 11, C.INK, 190, "LEFT", 2)
  button.hi = button:CreateTexture(nil, "HIGHLIGHT"); button.hi:SetAllPoints(); button.hi:SetColorTexture(1, 1, 1, 0.08)
  button:Hide()
  shape()
  handler:SetAttribute("next", NEXT)
  handler:SetAttribute("remap", REMAP)
  handler:SetAttribute("queue", ",")
  if type(SecureHandlerSetFrameRef) == "function" then SecureHandlerSetFrameRef(handler, "btn", button) end
  if type(SecureHandlerWrapScript) == "function" then SecureHandlerWrapScript(button, "OnClick", handler, PRE, POST) end
  -- (the member and spell a click casts, noted before it: a name the client hides in the cast's SENT is them, for the
  -- bar's marks; Roster.MemberFor)
  button:HookScript("PreClick", A.Roster.NoteClick)
  -- (insecure art follows the secure attributes: the card's words once a pass ("idx", set last), its sound for a new
  -- member; a member back up again starts with none of your spells seen; the overlay's stack moves under it)
  button:HookScript("OnAttributeChanged", function(_, name, value)
    if name == "idx" and value ~= nil then A.Safe(paint, "rebuff: paint")() end
  end)
  handler:HookScript("OnAttributeChanged", function(_, name)
    local i = type(name) == "string" and tonumber(name:match("^rev(%d+)$"))
    if i then Rb.done[i] = nil end
  end)
  button:HookScript("OnEnter", function(self)
    A.Alerts.Tip(self, self.title:GetText(), self.text:GetText(), nil, "Click: cast it. Right-click: done with them.")
  end)
  button:HookScript("OnLeave", function() A.Alerts.Untip() end)
  button:HookScript("OnShow", function() if A.Alerts then A.Alerts.Layout() end end)
  button:HookScript("OnHide", function() Rb.painted = nil; if A.Alerts then A.Alerts.Layout() end end)
  Rb.handler, Rb.button = handler, button
end

-- slot i's watcher: a group header of the game's, its one child set to the unit of the member named (the game's own
-- code moves it in a fight when the roster changes); the child tells the handler (WATCH, REMAP)
local function watch(i, name)
  local w = watchers[i]
  if not w then
    -- (no parent: the game's header works only while visible, and UIParent hides with the interface)
    w = CreateFrame("Frame", "CuteAurasRebuffWatch" .. i, nil, "SecureGroupHeaderTemplate")
    w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    w:SetSize(1, 1)
    w:SetAttribute("template", "SecureHandlerAttributeTemplate")
    w:SetAttribute("templateType", "Frame")
    w:SetAttribute("showRaid", true)
    w:SetAttribute("showParty", true)
    w:SetAttribute("sortMethod", "NAMELIST")
    watchers[i] = w
  end
  w:SetAttribute("nameList", name)
  if not w:IsShown() then w:Show() end
  local child = w:GetAttribute("child1")
  if child and not child.cuteWired then
    child.cuteWired = true
    child:SetAttribute("slot", i)
    if type(SecureHandlerSetFrameRef) == "function" then SecureHandlerSetFrameRef(child, "rb", handler) end
    child:SetAttribute("_onattributechanged", WATCH)
  end
end
local function unwatch(i)
  local w = watchers[i]
  if w and w:IsShown() then w:Hide() end
end

-- the group fighting on: a boss, or a member still in a fight
local function groupFighting()
  if A.Yes(IsEncounterInProgress) then return true end
  for _, m in ipairs(A.Roster.members) do
    if not m.me and A.Yes(UnitAffectingCombat, m.unit) then return true end
  end
  return false
end
Rb.GroupFighting = groupFighting
-- your own death in a fight: the game ends your fight (PLAYER_REGEN_ENABLED) while the group's goes on. The queue is
-- kept ("hold": a member raised meanwhile is queued too), the card hidden until you are back (NEXT), and kept on while
-- the group fights; once its fight is over, or you let go of your body (a ghost is out of it), it is cleared
local function holding()
  if A.Yes(UnitIsGhost, "player") or not groupFighting() then return false end
  return Rb.held or A.Yes(UnitIsDeadOrGhost, "player")
end
local function poll()
  Rb.polling = nil
  if not Rb.held or A.Fighting() then return end
  if holding() then Rb.polling = true; A.After(2, poll, "rebuff: the group's fight") return end
  Rb.Update()
end
local function runNext()
  if type(SecureHandlerExecute) == "function" then SecureHandlerExecute(handler, [[ self:RunAttribute("next") ]]) end
end

-- out of a fight: each owed member a slot (unit, spells, the driver on their death, the watcher on their name); the
-- old slots let go
local function update()
  frames()
  if holding() then
    Rb.held = true
    handler:SetAttribute("hold", 1)
    runNext()
    if not Rb.polling then Rb.polling = true; A.After(2, poll, "rebuff: the group's fight") end
    return
  end
  local list = {}
  if A.Settings().rebuff ~= false and A.Alerts.On() and A.Roster.InGroup() then
    for _, m in ipairs(A.Roster.members) do
      local owed = A.Assign.Owed(m.guid)
      if owed and not m.me and m.class ~= "HUNTER" then
        local ids = {}
        for _, o in ipairs(owed) do
          local id = S.Best(o.entry, m.level)
          if id then ids[#ids + 1] = tostring(id) end
        end
        -- (the name as the game's header reads it: a member from another realm with it)
        local n, realm = call(UnitName, m.unit)
        n, realm = plain(n), plain(realm)
        if type(n) == "string" and type(realm) == "string" and realm ~= "" then n = n .. "-" .. realm end
        if #ids > 0 then list[#list + 1] = { unit = m.unit, spells = table.concat(ids, ","), name = type(n) == "string" and n or nil } end
      end
    end
  end
  for i, e in ipairs(list) do
    handler:SetAttribute("u" .. i, e.unit)
    handler:SetAttribute("s" .. i, e.spells)
    handler:SetAttribute("p" .. i, nil)
    -- (the driver only fires on a change: a member still dead from the last fight keeps state 1, so the slot is told
    -- from the unit now, as REMAP does, or their combat res in the next fight would never queue them)
    handler:SetAttribute("dead" .. i, A.Yes(UnitIsDeadOrGhost, e.unit) and 1 or nil)
    handler:SetAttribute("_onstate-d" .. i, STATE)
    if type(RegisterStateDriver) == "function" then RegisterStateDriver(handler, "d" .. i, "[@" .. e.unit .. ",dead] 1; 0") end
    if e.name then watch(i, e.name) else unwatch(i) end
  end
  for i = #list + 1, Rb.slots do
    if type(UnregisterStateDriver) == "function" then UnregisterStateDriver(handler, "d" .. i) end
    unwatch(i)
    handler:SetAttribute("u" .. i, nil)
    handler:SetAttribute("s" .. i, nil)
    handler:SetAttribute("p" .. i, nil)
    handler:SetAttribute("dead" .. i, nil)
  end
  Rb.slots = #list
  Rb.held, Rb.polling = nil, nil
  handler:SetAttribute("hold", nil)
  handler:SetAttribute("queue", ",")
  for k in pairs(Rb.done) do Rb.done[k] = nil end
  button:SetAttribute("idx", nil)
  if button:IsShown() then button:Hide() end
end
function Rb.Update() A.OutOfFight("rebuff", update) end

-- back from the dead (a soulstone, a resurrection) while the group fights: the card for the first queued member
local function backUp()
  if not Rb.held or A.Fighting() then return end
  if holding() and not A.Yes(UnitIsDeadOrGhost, "player") then runNext() else Rb.Update() end
end

function Rb:Init()
  frames()
  A.On("PLAYER_REGEN_ENABLED", function() Rb.Update() end)
  A.On("PLAYER_ALIVE", backUp)
  A.On("PLAYER_UNGHOST", backUp)
  A.OnUnit("UNIT_SPELLCAST_SENT", { "player" }, onSent)
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onSucceeded)
  Rb.Update()
end
