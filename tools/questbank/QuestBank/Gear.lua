-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Gear page: the character sheet's slots, two columns as the game's paper doll lays them out, what you wear in
-- each (its icon on the slot's own art, its name in its quality colour, its item level) and beside it the best
-- upgrade you can get for that slot: a quest reward within reach (the finders' judgement, item by item: your armour
-- class, your weapon skills, your class, "2 levels ahead" as set) or a dungeon drop at your level (the journal's
-- bosses' recorded loot, judged the same way), whichever has the highest item level above what you wear. A quest's
-- choice (one reward of several) is offered for one slot only: the slot with the most to lose without it. A click puts
-- the quest on your pick-up list or opens the journal on the boss; Shift links the item in chat, Ctrl tries it on.
local _, QB = ...
if QB.dormant then return end
local G = {}
QB.Gear = G

local plain = QB.Plain
local ICON = 36          -- a slot, as the character pane draws it
local ROW = 44           -- a slot's row
local COL = 396          -- a column
local GAP = 12           -- between the columns
local SIDE = 4           -- the grid's margin inside the page (a button on the page's edge is an edge too near)
local TOP = 30           -- the header line above the columns
local EQ_W = 104         -- the worn piece's name and level
local UP_X = 166         -- the upgrade block, from the row's left
local SMALL = 26         -- the upgrade's face and icon
local LEFT = 9           -- the left column's slots (the rest go right)
local BELOW = 8          -- a dungeon whose top level is this far under yours is behind you
local ASK = 24           -- items asked of the server in one refresh
local ASK_FOR = 15       -- seconds an asked-for item counts as loading

local INK = { 0.93, 0.88, 0.78 }
local SOFT = { 0.66, 0.60, 0.50 }
local GOLD = { 1, 0.82, 0 }
-- a host's skin (QB.Skin: Cute_Quest): its font, and its colours for INK, SOFT and GOLD (the skin's ACCENT)
local function tone(c)
  local sk = QB.Skin
  if not sk then return c end
  if c == INK then return sk.INK or c elseif c == SOFT then return sk.SOFT or c elseif c == GOLD then return sk.ACCENT or c end
  return c
end
local GOOD = { 0.42, 0.86, 0.45 }
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
                  { 0.9, 0.8, 0.5 }, { 0, 0.8, 1 } }
-- the bags' green upgrade arrow (atlas bags-greenarrow in Interface\ContainerFrame\Bags), as the Quest Log draws it
local UPGRADE_TC = { 66 / 512, 86 / 512, 93 / 256, 115 / 256 }

-- the slots in the character pane's order: its left column (Head to Wrist, the shirt and tabard left out) with its
-- bottom row, the three weapon slots, under it; its right column (Hands to the trinkets). id: the inventory slot
-- (the game's own number, asked of C_PaperDollInfo when it answers); art: the slot's paper-doll background (D.TEX);
-- loc: the equip locations that go in it; pair: the two slots that share one kind of piece
G.SLOTS = {
  { name = "Head", token = "HeadSlot", id = 1, art = "slotHead", loc = { INVTYPE_HEAD = 1 } },
  { name = "Neck", token = "NeckSlot", id = 2, art = "slotNeck", loc = { INVTYPE_NECK = 1 } },
  { name = "Shoulder", token = "ShoulderSlot", id = 3, art = "slotShoulder", loc = { INVTYPE_SHOULDER = 1 } },
  { name = "Back", token = "BackSlot", id = 15, art = "slotChest", loc = { INVTYPE_CLOAK = 1 } },
  { name = "Chest", token = "ChestSlot", id = 5, art = "slotChest", loc = { INVTYPE_CHEST = 1, INVTYPE_ROBE = 1 } },
  { name = "Wrist", token = "WristSlot", id = 9, art = "slotWrist", loc = { INVTYPE_WRIST = 1 } },
  { name = "Main hand", token = "MainHandSlot", id = 16, art = "slotMainHand",
    loc = { INVTYPE_WEAPON = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPONMAINHAND = 1 } },
  { name = "Off hand", token = "SecondaryHandSlot", id = 17, art = "slotOffHand",
    loc = { INVTYPE_SHIELD = 1, INVTYPE_HOLDABLE = 1, INVTYPE_WEAPONOFFHAND = 1 } },
  { name = "Ranged", token = "RangedSlot", id = 18, art = "slotRanged",
    loc = { INVTYPE_RANGED = 1, INVTYPE_RANGEDRIGHT = 1, INVTYPE_THROWN = 1 } },
  { name = "Hands", token = "HandsSlot", id = 10, art = "slotHands", loc = { INVTYPE_HAND = 1 } },
  { name = "Waist", token = "WaistSlot", id = 6, art = "slotWaist", loc = { INVTYPE_WAIST = 1 } },
  { name = "Legs", token = "LegsSlot", id = 7, art = "slotLegs", loc = { INVTYPE_LEGS = 1 } },
  { name = "Feet", token = "FeetSlot", id = 8, art = "slotFeet", loc = { INVTYPE_FEET = 1 } },
  { name = "Ring 1", token = "Finger0Slot", id = 11, art = "slotFinger", loc = { INVTYPE_FINGER = 1 }, pair = "ring" },
  { name = "Ring 2", token = "Finger1Slot", id = 12, art = "slotFinger", loc = { INVTYPE_FINGER = 1 }, pair = "ring" },
  { name = "Trinket 1", token = "Trinket0Slot", id = 13, art = "slotTrinket", loc = { INVTYPE_TRINKET = 1 }, pair = "trinket" },
  { name = "Trinket 2", token = "Trinket1Slot", id = 14, art = "slotTrinket", loc = { INVTYPE_TRINKET = 1 }, pair = "trinket" },
}

----------------------------------------------------------------------------
-- what you wear, and what beats it
----------------------------------------------------------------------------
-- the slot's number and its own background art, as the client gives them (the paper doll asks the same); the list's
-- numbers and the client's files where it answers nothing
local function slotInfo(slot)
  local get = (C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo) or GetInventorySlotInfo
  local id, art
  if type(get) == "function" then
    local ok, i, t = pcall(get, slot.token)
    if ok then id, art = plain(i), plain(t) end
  end
  if type(id) ~= "number" then id = slot.id end
  if type(art) ~= "string" then art = QB.Data.TEX[slot.art] or QB.Data.TEX.slot end
  return id, art
end

-- an item's level: the client's (the character sheet's number, once it has the item), else the catalog's
local function itemLevel(id, link)
  local CI = C_Item
  if CI and type(CI.GetDetailedItemLevelInfo) == "function" then
    local ok, l = pcall(CI.GetDetailedItemLevelInfo, link or id)
    l = ok and plain(l) or nil
    if type(l) == "number" and l > 0 then return l end
  end
  local l = QB.Survey and QB.Survey.ItemLevel and QB.Survey.ItemLevel(id)
  if type(l) == "number" and l > 0 then return l end
  local d = QB.Data.RIT and QB.Data.RIT[id]
  if d and d[1] > 0 then return d[1] end
  return nil
end

-- the piece in a slot: its id, link, name, quality, icon and level; nil for an empty slot. Every call to the client
-- through pcall and QB.Plain: it may hide any of it
local function worn(slotId)
  if not GetInventoryItemID then return nil end
  local ok, id = pcall(GetInventoryItemID, "player", slotId)
  id = ok and plain(id) or nil
  if type(id) ~= "number" or id == 0 then return nil end
  local w = { id = id }
  if GetInventoryItemLink then
    local okL, link = pcall(GetInventoryItemLink, "player", slotId)
    link = okL and plain(link) or nil
    if type(link) == "string" then w.link = link end
  end
  local name, link, quality, icon = QB.API.ItemInfo(id)
  w.name, w.link, w.quality, w.icon = name, w.link or link, quality, icon
  w.ilvl = itemLevel(id, w.link)
  return w
end

-- is the item one of the quest's reward choices (one pick among several), rather than one given along with the rest?
local function isChoice(qid, id)
  local R = QB.Data.RITEMS and QB.Data.RITEMS[qid]
  for _, c in ipairs(R and R.c or {}) do if c == id then return true end end
  return false
end

-- the quest rewards you could go and get for a slot: the finder's rows ("Best gear", narrowed to the slot's equip
-- locations: each quest's best piece for you, the highest item level first, "2 levels ahead" as the finder has it);
-- choice: the item is one of the quest's choices; rank: the finder's order (the most XP first at one item level)
local function questFinds(slot, level)
  local UI = QB.UI
  if not (UI and UI.FindRewards) then return {} end
  local out = {}
  for i, r in ipairs(UI:FindRewards("gear", level, slot.loc)) do
    out[i] = { id = r.item, ilvl = r.ilvl, q = r.q, st = r.st, mins = r.mins, req = r.req, kind = "quest", choice = isChoice(r.q.id, r.item), rank = i }
  end
  return out
end

-- items asked of the server and when, and the ones it has no data for
local asked, gone = {}, {}

-- the dungeon drops at your level, by equip location: every entry's recorded loot in the journal's dungeons whose
-- level range reaches yours (its low end at most "2 levels ahead" above you, its high end not far below), each item
-- judged as the finders judge a reward (UI.ItemUse: your armour class, weapon skills and class). An item whose level
-- the client has not sent yet is asked for, a few at a time, and counted as loading for a while
local function dungeonFinds(level, ahead)
  local DM, UI = QB.DMap, QB.UI
  local byLoc, loading, asks = {}, 0, 0
  if not (DM and DM.List and UI and UI.ItemUse) then return byLoc, loading end
  local now = GetTime and GetTime() or 0
  local CI = C_Item
  for _, cat in ipairs(DM.List()) do
    local lv = DM.Levels(cat.key)
    if lv[1] > 0 and lv[1] <= level + ahead and lv[2] >= level - BELOW then
      local d = DM.Data(cat.key)
      for _, b in ipairs(d and d.bosses or {}) do
        for _, id in ipairs(b.i) do
          if not gone[id] then
            local use, ilvl, loc = UI.ItemUse(id, level)
            if use == "gear" or use == "trinket" then
              if ilvl > 0 then
                local list = byLoc[loc]
                if not list then list = {}; byLoc[loc] = list end
                list[#list + 1] = { id = id, ilvl = ilvl, boss = b, cat = cat, data = d, lv = lv, kind = "drop" }
              else
                if not asked[id] and asks < ASK and CI and CI.RequestLoadItemDataByID then
                  asks = asks + 1
                  asked[id] = now
                  pcall(CI.RequestLoadItemDataByID, id)
                end
                if asked[id] and now - asked[id] < ASK_FOR then loading = loading + 1 end
              end
            end
          end
        end
      end
    end
  end
  return byLoc, loading
end

-- a slot's candidates, the best first: its quest finds and the drops for its equip locations above what you wear
-- (anything for an empty slot), the highest item level first, a quest reward before a drop at the same level, the
-- quests in the finder's order (the most XP first) and the drops by item
local function candidates(slot, finds, drops, beat)
  local out = {}
  for _, c in ipairs(finds) do if c.ilvl > beat then out[#out + 1] = c end end
  for loc in pairs(slot.loc) do
    for _, c in ipairs(drops[loc] or {}) do if c.ilvl > beat then out[#out + 1] = c end end
  end
  table.sort(out, function(a, b)
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if (a.q ~= nil) ~= (b.q ~= nil) then return a.q ~= nil end
    if a.q and b.q then return a.rank < b.rank end
    return a.id < b.id
  end)
  return out
end

-- may this candidate go to the slot? Not an item suggested already; not a quest's choice (one reward of several)
-- spent on another slot; not the pair's other slot's quest
local function allowed(c, slot, taken)
  if taken.item[c.id] then return false end
  if c.q then
    if c.choice and taken.choice[c.q.id] then return false end
    if slot.pair and taken.quest[slot.pair .. c.q.id] then return false end
  end
  return true
end

-- every slot's pick from its candidates. A quest's choice is one reward of several, so it counts for one slot: when
-- two slots want it, the one with the most to lose without it (its best against its next) gets it and the other
-- takes its next; a drop or a quest's fixed reward is one item, had once. Rounds until every slot is settled.
-- rows[i] = { slot, beat, cands }; returns pick[i], the slot's candidate or nil
local function assign(rows)
  local taken = { item = {}, quest = {}, choice = {} }
  local done, pick = {}, {}
  for _ = 1, #rows + 1 do
    local claims, open = {}, false
    for i, r in ipairs(rows) do
      if not done[i] then
        open = true
        local best, after
        for _, c in ipairs(r.cands) do
          if allowed(c, r.slot, taken) then
            if not best then best = c
            elseif not (c.q and best.q and c.q.id == best.q.id) then after = c; break end
          end
        end
        pick[i] = best
        r.regret = best and (best.ilvl - (after and after.ilvl or r.beat)) or 0
        if best and best.q and best.choice then
          local l = claims[best.q.id]
          if not l then l = {}; claims[best.q.id] = l end
          l[#l + 1] = i
        end
      end
    end
    if not open then break end
    -- a choice two slots claim goes to the one with the most to lose; the others wait for the next round
    local wait = {}
    for _, list in pairs(claims) do
      if #list > 1 then
        local win = list[1]
        for _, i in ipairs(list) do if rows[i].regret > rows[win].regret then win = i end end
        for _, i in ipairs(list) do if i ~= win then wait[i] = true end end
      end
    end
    for i, r in ipairs(rows) do
      if not done[i] and not wait[i] then
        local b = pick[i]
        if not b then done[i] = true
        elseif allowed(b, r.slot, taken) then -- (an earlier slot this round may have taken the very item: a ring)
          done[i] = true
          taken.item[b.id] = true
          if b.q and b.choice then taken.choice[b.q.id] = true end
          if r.slot.pair and b.q then taken.quest[r.slot.pair .. b.q.id] = true end
        end
      end
    end
  end
  return pick
end
G.Assign = assign

-- the page's answer, slot by slot: { slot, worn, best }, with the count, the item levels gained and how many items
-- are still loading. Read by the tests as well as the page
function G.Upgrades()
  local level = QB.state.level or 1
  local ahead = QB:Settings().finderAhead and 2 or 0
  local drops, loading = dungeonFinds(level, ahead)
  local rows = {}
  for i, slot in ipairs(G.SLOTS) do
    local w = worn(slot.id)
    local beat = w and (w.ilvl or 0) or 0
    rows[i] = { slot = slot, worn = w, beat = beat, cands = candidates(slot, questFinds(slot, level), drops, beat) }
  end
  local pick = assign(rows)
  local out = { n = 0, gain = 0, loading = loading }
  for i, r in ipairs(rows) do
    local best = pick[i]
    out[i] = { slot = r.slot, worn = r.worn, best = best }
    if r.worn and not r.worn.name then out.loading = out.loading + 1 end
    if best then out.n = out.n + 1; out.gain = out.gain + best.ilvl - r.beat end
  end
  return out
end

----------------------------------------------------------------------------
-- the page
----------------------------------------------------------------------------
local frame

local function fs(parent, font, size, color, w, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  if size and t.SetFont then local f, _, fl = t:GetFont(); if f then t:SetFont(f, size, fl) end end
  if QB.Skin and QB.Skin.font and t.SetFont then t:SetFont(QB.Skin.font, size or select(2, t:GetFont()), "") end
  if color then color = tone(color); t:SetTextColor(color[1], color[2], color[3]) end
  if w then t:SetWidth(w) end
  t:SetJustifyH(justify or "LEFT")
  t:SetWordWrap(false)
  return t
end

local function qualityColor(q)
  if type(q) == "number" and C_Item and C_Item.GetItemQualityColor then
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, q)
    if ok and type(r) == "number" then return { r, g, b } end
  end
  return QUALITY[q] or QUALITY[1]
end

local function fit(label, s)
  if QB.UI and QB.UI.FitText then return QB.UI.FitText(label, s) end
  label:SetText(s)
  return s
end

-- a square icon with the game's frame round it, tinted in the item's quality colour
local function framedIcon(parent, size, layerSub)
  local icon = parent:CreateTexture(nil, "ARTWORK", nil, layerSub or 1)
  icon:SetSize(size, size)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local rim = parent:CreateTexture(nil, "OVERLAY", nil, 1)
  rim:SetTexture(QB.Data.TEX.iconFrame)
  rim:SetAllPoints(icon)
  return icon, rim
end

local function sourceText(c)
  if c.q then
    local zone = c.q.cat and c.q.cat.name or ""
    local place = zone
    if c.mins and c.mins > 0 then place = place .. (place ~= "" and ", " or "") .. string.format("%d min", math.floor(c.mins + 0.5)) end
    if c.req and c.req > (QB.state.level or 1) then place = string.format("at %d: %s", c.req, place) end
    return "Quest: " .. c.q.name, place
  end
  local lv = c.lv or { 0, 0 }
  return c.boss.n, c.cat.name .. (lv[1] > 0 and string.format(", LV %d-%d", lv[1], lv[2]) or "")
end

-- the dressing room: Core.lua's QB.API.DressUp by the item's id (it finds the link, and asks the client for an item it
-- hasn't got yet); without it, the game's DressUpItemLink with the item's link where this client has it
function G.DressUp(c)
  if QB.API.DressUp then return QB.API.DressUp(c.id) end
  local link = c.link
  if not link then local _, l = QB.API.ItemInfo(c.id); link = l end
  link = link or ("item:" .. c.id)
  if type(DressUpItemLink) == "function" then
    if InCombatLockdown and InCombatLockdown() then QB:Print("The dressing room waits for the fight to end."); return false end
    local ok = pcall(DressUpItemLink, link)
    return ok
  end
  QB:Print("This client has no dressing room to try it on in.")
  return false
end

-- the try-on click: the Key Bindings' Dressing Room modifier (Core.lua's QB.DressClick, Ctrl unless rebound), plain
-- Ctrl without it
local function dressClick()
  if QB.DressClick then return QB.DressClick() end
  return (IsControlKeyDown and IsControlKeyDown()) and true or false
end
-- the hint goes on an item the dressing room can put on you (Core.lua's QB.API.Dressable; every item without it)
local function dressHint(id)
  if QB.API.Dressable and not QB.API.Dressable(id) then return "Shift-click: link it in chat." end
  return "Shift-click: link it in chat. Ctrl-click: try it on."
end

-- a click on an upgrade: Shift links the item, Ctrl tries it on, the right button opens the quest's menu, a plain
-- click puts the quest on your pick-up list (again: takes it off) or opens the journal on the boss
local function upgradeClick(r, which)
  local c = r.best
  if not c then return end
  if IsShiftKeyDown and IsShiftKeyDown() then QB.UI.LinkItemAlways(c.id); return end
  if dressClick() then G.DressUp(c); return end
  if c.q then
    if which == "RightButton" then QB.UI.QuestMenu(c.q, c.st); return end
    QB:SetAdded(c.q.id, not QB:IsAdded(c.q.id))
    QB.UI:Refresh()
    return
  end
  local DM = QB.DMap
  if DM and DM.Open then
    local f = DM.Open(c.cat, "bosses")
    if f and DM.ShowBoss then DM.ShowBoss(c.boss) end
  end
end

local function upgradeTip(tip, r)
  local c = r.best
  if not c then return end
  local ok = pcall(tip.SetItemByID, tip, c.id)
  local name = (QB.API.ItemInfo(c.id)) or ("Item " .. c.id)
  if not ok then tip:AddLine(name, 1, 1, 1) end
  local src, place = sourceText(c)
  tip:AddLine(" ")
  tip:AddLine(src, GOLD[1], GOLD[2], GOLD[3])
  if place ~= "" then tip:AddLine(place, INK[1], INK[2], INK[3]) end
  local w = r.worn
  tip:AddLine(w and string.format("Item level %d, over the %d you wear.", c.ilvl, w.ilvl or 0) or string.format("Item level %d, for an empty slot.", c.ilvl),
    GOOD[1], GOOD[2], GOOD[3])
  if c.q then
    if c.req and c.req > (QB.state.level or 1) then tip:AddLine(string.format("You can take it at level %d.", c.req), 1, 0.6, 0.3) end
    tip:AddLine(QB:IsAdded(c.q.id) and "On your pick-up list. Click: take it off." or "Click: put it on your pick-up list.", 0.6, 0.6, 0.6)
    tip:AddLine("Right-click: the quest's menu.", 0.6, 0.6, 0.6)
  else
    tip:AddLine("Click: the Dungeon Journal on " .. c.boss.n .. ".", 0.6, 0.6, 0.6)
  end
  tip:AddLine(dressHint(c.id), 0.6, 0.6, 0.6)
end

local function slotTip(tip, r)
  local w = r.worn
  if w then
    local ok = pcall(tip.SetInventoryItem, tip, "player", r.slotId)
    if not ok then tip:AddLine(w.name or ("Item " .. w.id), 1, 1, 1) end
    if r.best then
      tip:AddLine(" ")
      tip:AddLine(string.format("An upgrade beside it: item level %d over %d.", r.best.ilvl, w.ilvl or 0), GOOD[1], GOOD[2], GOOD[3])
    end
  else
    tip:AddLine(r.slot.name, GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Nothing worn here.", SOFT[1], SOFT[2], SOFT[3])
  end
  if w then tip:AddLine(dressHint(w.id), 0.6, 0.6, 0.6) end
end

local function slotClick(r)
  local w = r.worn
  if not w then return end
  if IsShiftKeyDown and IsShiftKeyDown() then QB.UI.LinkItemAlways(w.id)
  elseif dressClick() then G.DressUp(w) end
end

local function tooltip(b, fill)
  b:SetScript("OnEnter", QB.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip, self:GetParent())
    GameTooltip:Show()
  end, "gear tooltip"))
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function buildRow(f, i, slot)
  local T = QB.Data.TEX
  local col = i <= LEFT and 0 or 1
  local n = col == 0 and i or (i - LEFT)
  local r = CreateFrame("Frame", nil, f)
  r:SetSize(COL, ROW - 4)
  r:SetPoint("TOPLEFT", SIDE + col * (COL + GAP), -(TOP + (n - 1) * ROW))
  r.slot = slot
  r.slotId, r.art = slotInfo(slot)
  -- the slot: its paper-doll art, the piece's icon over it, the game's icon frame in the quality colour
  local s = CreateFrame("Button", nil, r)
  s:SetSize(ICON, ICON)
  s:SetPoint("TOPLEFT", 0, 0)
  s.back = s:CreateTexture(nil, "ARTWORK", nil, 0)
  s.back:SetAllPoints()
  s.back:SetTexture(r.art)
  s.icon, s.rim = framedIcon(s, ICON, 1)
  s.icon:SetAllPoints()
  s:SetHighlightTexture(T.hilite, "ADD")
  s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  s:SetScript("OnClick", QB.Safe(function(self) slotClick(self:GetParent()) end, "gear slot"))
  tooltip(s, slotTip)
  r.button = s
  r.name = fs(r, "GameFontNormal", 11, INK, EQ_W)
  r.name:SetPoint("TOPLEFT", ICON + 6, -5)
  r.sub = fs(r, "GameFontNormalSmall", 10, SOFT, EQ_W)
  r.sub:SetPoint("TOPLEFT", ICON + 6, -20)
  -- the green arrow, then the upgrade: the source's face (a boss's, the quest's icon), the item's icon, three short
  -- lines (the item and its level, where from, the place)
  r.arrow = r:CreateTexture(nil, "OVERLAY")
  r.arrow:SetTexture(T.upgrade)
  r.arrow:SetTexCoord(UPGRADE_TC[1], UPGRADE_TC[2], UPGRADE_TC[3], UPGRADE_TC[4])
  r.arrow:SetSize(12, 13)
  r.arrow:SetPoint("TOPLEFT", UP_X - 16, -12)
  local u = CreateFrame("Button", nil, r)
  u:SetSize(COL - UP_X, ROW - 4)
  u:SetPoint("TOPLEFT", UP_X, 0)
  u:SetHighlightTexture(T.rowHi, "ADD")
  u.face = u:CreateTexture(nil, "ARTWORK", nil, 1)
  u.face:SetSize(SMALL, SMALL)
  u.face:SetPoint("TOPLEFT", 0, -7)
  u.faceRim = u:CreateTexture(nil, "OVERLAY", nil, 1)
  u.faceRim:SetTexture(T.iconFrame)
  u.faceRim:SetAllPoints(u.face)
  u.faceRim:SetVertexColor(0.55, 0.45, 0.25)
  -- on your pick-up list: the ready check on the quest's icon
  u.mark = u:CreateTexture(nil, "OVERLAY", nil, 2)
  u.mark:SetTexture(T.ready)
  u.mark:SetSize(14, 14)
  u.mark:SetPoint("BOTTOMRIGHT", u.face, "BOTTOMRIGHT", 3, -3)
  u.icon, u.rim = framedIcon(u, SMALL, 1)
  u.icon:SetPoint("TOPLEFT", SMALL + 6, -7)
  local tx = SMALL * 2 + 12
  local tw = COL - UP_X - tx - 2
  u.name = fs(u, "GameFontNormal", 11, INK, tw - 44)
  u.name:SetPoint("TOPLEFT", tx, -1)
  u.ilvl = fs(u, "GameFontNormalSmall", 10, GOOD, 40, "RIGHT")
  u.ilvl:SetPoint("TOPRIGHT", -2, -2)
  u.src = fs(u, "GameFontNormalSmall", 10, GOLD, tw)
  u.src:SetPoint("TOPLEFT", tx, -14)
  u.place = fs(u, "GameFontNormalSmall", 10, SOFT, tw)
  u.place:SetPoint("TOPLEFT", tx, -27)
  u:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  u:SetScript("OnClick", QB.Safe(function(self, which) upgradeClick(self:GetParent(), which) end, "gear upgrade"))
  tooltip(u, upgradeTip)
  u:Hide()
  r.up = u
  return r
end

-- the faces drawn from a model, drawn again when the client says their portraits are in
local faces = {}
local facesSoon = false
local function redrawFaces()
  if not (frame and frame:IsVisible()) then return end
  for t, e in pairs(faces) do QB.DMap.Face(t, e.boss, e.data) end
end

local function build(page, w, h)
  local f = CreateFrame("Frame", nil, page)
  f:SetAllPoints()
  f.head = fs(f, "GameFontNormal", 13, GOLD, 520)
  f.head:SetPoint("TOPLEFT", SIDE, -5)
  f.note = fs(f, "GameFontNormalSmall", 10, SOFT, 200, "RIGHT")
  f.note:SetPoint("TOPRIGHT", -SIDE, -7)
  f.rows = {}
  for i, slot in ipairs(G.SLOTS) do f.rows[i] = buildRow(f, i, slot) end
  -- what you wear changed, an item's name or level came in, a portrait was drawn: the page again, a moment later
  f:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2)
    if event == "ITEM_DATA_LOAD_RESULT" then
      local id = tonumber(plain(a1))
      if id and plain(a2) == false then gone[id] = true end
    end
    if event == "PORTRAITS_UPDATED" then
      if facesSoon then return end
      facesSoon = true
      C_Timer.After(0.2, QB.Safe(function() facesSoon = false; redrawFaces() end, "gear faces"))
      return
    end
    G.RefreshSoon()
  end, "gear page"))
  for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "PORTRAITS_UPDATED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  return f
end

local function showWorn(r, w)
  local s = r.button
  r.worn = w
  if w then
    local qc = qualityColor(w.quality)
    s.icon:SetTexture(w.icon or QB.Data.TEX.unknown)
    s.icon:Show()
    s.rim:SetVertexColor(qc[1], qc[2], qc[3])
    s.rim:Show()
    s.back:Hide()
    r.name:SetTextColor(qc[1], qc[2], qc[3])
    fit(r.name, w.name or "loading...")
    r.sub:SetText(w.ilvl and string.format("%s, iL %d", r.slot.name, w.ilvl) or r.slot.name)
  else
    s.icon:Hide()
    s.rim:Hide()
    s.back:Show()
    r.name:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
    r.name:SetText(r.slot.name)
    r.sub:SetText("nothing worn")
  end
end

local function showUpgrade(r, c)
  local u = r.up
  r.best = c
  faces[u.face] = nil
  if not c then
    u:Hide()
    r.arrow:Hide()
    return
  end
  local name, link, quality, icon = QB.API.ItemInfo(c.id)
  c.link = c.link or link
  local qc = qualityColor(quality) -- (white until the client names the item)
  u.icon:SetTexture(icon or QB.Data.TEX.unknown)
  u.rim:SetVertexColor(qc[1], qc[2], qc[3])
  u.name:SetTextColor(qc[1], qc[2], qc[3])
  fit(u.name, name or "loading...")
  u.ilvl:SetText(string.format("iL %d", c.ilvl))
  local src, place = sourceText(c)
  fit(u.src, src)
  fit(u.place, place)
  u.face:SetDesaturated(false)
  u.face:SetVertexColor(1, 1, 1)
  if c.q then
    u.face:SetTexture(c.q.icon or QB.Data.TEX.questGeneric)
    u.face:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    u.mark:SetShown(QB:IsAdded(c.q.id))
  else
    local drew = QB.DMap.Face(u.face, c.boss, c.data)
    if drew == "d" then faces[u.face] = { boss = c.boss, data = c.data } end
    u.mark:Hide()
  end
  u:Show()
  r.arrow:Show()
end

-- the page is one of the QuestBank window's (UI.lua, page 9): built the first time it shows, to its size
function G.Attach(page, w, h)
  frame = frame or build(page, w, h)
  return frame
end

-- the page's refresh: what you wear and the best upgrade for every slot, the header's count
function G.Refresh()
  if not frame then return end
  local up = G.Upgrades()
  for i, e in ipairs(up) do
    local r = frame.rows[i]
    showWorn(r, e.worn)
    showUpgrade(r, e.best)
  end
  if up.n > 0 then
    frame.head:SetText(string.format("%d upgrade%s to get, +%d item level%s", up.n, up.n == 1 and "" or "s", up.gain, up.gain == 1 and "" or "s"))
  else
    frame.head:SetText(string.format("No upgrades to get at level %d", QB.state.level or 1))
  end
  frame.note:SetText(up.loading > 0 and "loading items..." or "")
  G.last = up
end

-- a refresh a moment later, while the page shows (hidden, it refreshes when it shows); many events in a burst make one
local soon = false
function G.RefreshSoon()
  if not (frame and frame:IsVisible()) or soon then return end
  soon = true
  C_Timer.After(0.3, QB.Safe(function()
    soon = false
    if frame:IsVisible() then G.Refresh() end
  end, "gear refresh"))
end

function G.Frame() return frame end
