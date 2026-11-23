-- SPDX-License-Identifier: GPL-3.0-or-later
-- Buffing again after a death in a fight, by the one buffer who owes it. An addon can't set a secure button in a fight,
-- so the game's own secure code does it: out of a fight Cute Auras gives a secure handler, for each member you owe a
-- buff (Assign.lua), their unit, your spells for them, and a state driver on their death, "[@raid5,dead] 1; 0". In a
-- fight, a member who dies and comes back (a combat resurrection, a soulstone, Reincarnation) joins the handler's queue,
-- and its snippet points the rebuff card (a secure button at the alerts overlay's top) at the first one and your first
-- spell for them. A click casts it and moves on: the next spell, then the next member. After the fight the queue is
-- cleared; the bar's own reading of auras takes over. Hunters are left out: Feign Death reads as a death.
local _, A = ...
local Rb = A.Part("Rebuff", { slots = 0, shows = 0 })
local L, S = A.Look, A.Spells
local C = L.C
local plain, call = A.Plain, A.Call

-- (the restricted snippets: strings the game runs in its secure environment, no table constructors, attributes for state)
-- a member's death and return; self is the handler, stateid "dN", newstate 1 dead or 0 alive (the state driver hands
-- a number: SecureStateDriver.lua's tonumber, the string only on an old client)
local STATE = [[
  local i = tonumber(strsub(stateid, 2))
  if not i then return end
  if newstate == 1 or newstate == "1" then self:SetAttribute("dead" .. i, 1) return end
  if not self:GetAttribute("dead" .. i) then return end
  self:SetAttribute("dead" .. i, nil)
  if not PlayerInCombat() then return end
  local q = self:GetAttribute("queue") or ","
  if not strfind(q, "," .. i .. ",", 1, true) then q = q .. i .. "," end
  self:SetAttribute("queue", q)
  self:SetAttribute("p" .. i, self:GetAttribute("s" .. i))
  self:RunAttribute("next")
]]
-- the card set to the first queued member and their first spell left, or hidden with none
local NEXT = [[
  local b = self:GetFrameRef("btn")
  local q = self:GetAttribute("queue") or ","
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
    if first then
      b:SetAttribute("type1", "spell")
      b:SetAttribute("unit", self:GetAttribute("u" .. i))
      b:SetAttribute("spell", tonumber(first) or first)
      b:SetAttribute("idx", i)
      b:Show()
      return
    end
    q = "," .. (strmatch(q, "^,%d+,(.*)$") or "")
    self:SetAttribute("queue", q)
  end
]]
-- the card's click: its spell done, the next (a click that fails, out of range, moves on too: the bar asks again after)
local PRE = [[ return nil, "done" ]]
local POST = [[
  local i = self:GetAttribute("idx")
  if i then
    local p = control:GetAttribute("p" .. i) or ""
    control:SetAttribute("p" .. i, (gsub(p, "^[^,]*,?", "")))
  end
  control:RunAttribute("next")
]]
Rb.SNIPPETS = { STATE = STATE, NEXT = NEXT, PRE = PRE, POST = POST }

local handler, button
local function paint()
  local b = button
  if not b then return end
  local unit, spell = b:GetAttribute("unit"), b:GetAttribute("spell")
  if not (unit and spell) then return end
  local m = A.Roster.ByUnit(unit)
  local name = plain(call(UnitName, unit))
  L.Art(b.icon, L.SpellIcon(spell, 134400))
  b.title:SetText("Back up: " .. (type(name) == "string" and name or (m and m.name) or "a member"))
  if m and m.class then b.title:SetTextColor(L.ClassColor(m.class)) else b.title:SetTextColor(C.WHITE[1], C.WHITE[2], C.WHITE[3]) end
  b.text:SetText((L.SpellName(spell, "Your buff") or "Your buff") .. ". Click to buff them.")
  b.born = A.Now()
  Rb.shows = Rb.shows + 1
  if A.Alerts then A.Alerts.Sound() end
end
local function shape()
  if not button or A.Fighting() then return end
  local s = A.Alerts.IconSize()
  button:SetSize(s + 210, s + 8)
  button.icon:SetSize(s, s)
  button.title:SetFont(L.Font(), 14, "OUTLINE")
end
Rb.Restyle = function() A.OutOfFight("rebuff: size", shape) end
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
  button.icon:SetPoint("LEFT", button, "LEFT", 7, 0)
  button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.title = L.Text(button, 14, C.WHITE, 190, "LEFT")
  button.title:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 9, -4)
  button.text = L.Text(button, 11, C.INK, 190, "LEFT")
  button.text:SetPoint("TOPLEFT", button.title, "BOTTOMLEFT", 0, -3)
  button.hi = button:CreateTexture(nil, "HIGHLIGHT"); button.hi:SetAllPoints(); button.hi:SetColorTexture(1, 1, 1, 0.08)
  button:Hide()
  shape()
  handler:SetAttribute("next", NEXT)
  handler:SetAttribute("queue", ",")
  if type(SecureHandlerSetFrameRef) == "function" then SecureHandlerSetFrameRef(handler, "btn", button) end
  if type(SecureHandlerWrapScript) == "function" then SecureHandlerWrapScript(button, "OnClick", handler, PRE, POST) end
  -- (insecure art follows the secure attributes: the card's words, its sound; the overlay's stack moves under it)
  button:HookScript("OnAttributeChanged", function(_, name)
    if name == "unit" or name == "spell" then A.Safe(paint, "rebuff: paint")() end
  end)
  button:HookScript("OnShow", function() if A.Alerts then A.Alerts.Layout() end end)
  button:HookScript("OnHide", function() if A.Alerts then A.Alerts.Layout() end end)
  Rb.handler, Rb.button = handler, button
end

-- out of a fight: each owed member a slot (unit, spells, the driver on their death); the old slots let go
local function update()
  frames()
  local list = {}
  if A.Settings().rebuff ~= false and A.Roster.InGroup() then
    for _, m in ipairs(A.Roster.members) do
      local owed = A.Assign.Owed(m.guid)
      if owed and not m.me and m.class ~= "HUNTER" then
        local ids = {}
        for _, o in ipairs(owed) do
          local id = S.Best(o.entry, m.level)
          if id then ids[#ids + 1] = tostring(id) end
        end
        if #ids > 0 then list[#list + 1] = { unit = m.unit, spells = table.concat(ids, ",") } end
      end
    end
  end
  for i, e in ipairs(list) do
    handler:SetAttribute("u" .. i, e.unit)
    handler:SetAttribute("s" .. i, e.spells)
    handler:SetAttribute("p" .. i, nil)
    handler:SetAttribute("_onstate-d" .. i, STATE)
    if type(RegisterStateDriver) == "function" then RegisterStateDriver(handler, "d" .. i, "[@" .. e.unit .. ",dead] 1; 0") end
  end
  for i = #list + 1, Rb.slots do
    if type(UnregisterStateDriver) == "function" then UnregisterStateDriver(handler, "d" .. i) end
    handler:SetAttribute("u" .. i, nil)
    handler:SetAttribute("s" .. i, nil)
    handler:SetAttribute("p" .. i, nil)
    handler:SetAttribute("dead" .. i, nil)
  end
  Rb.slots = #list
  handler:SetAttribute("queue", ",")
  button:SetAttribute("idx", nil)
  if button:IsShown() then button:Hide() end
end
function Rb.Update() A.OutOfFight("rebuff", update) end

function Rb:Init()
  frames()
  A.On("PLAYER_REGEN_ENABLED", function() Rb.Update() end)
  Rb.Update()
end
