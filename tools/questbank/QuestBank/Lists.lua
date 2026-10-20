-- SPDX-License-Identifier: GPL-3.0-or-later
-- The window-free half of QuestBank's window, on the same QB.UI table UI.lua draws with: what every page and every
-- other part reads of a quest without a frame of its own: the quest tooltip and the reward lines, the chat links,
-- the right-click menu and its choices (skip, route again, abandon), a label cut after a word, the reward finders
-- (what an item is to you, the best reward of a quest, the finder's rows), where you stand and the minutes to a
-- giver, the candidates (every quest worth suggesting at your level, ranked), a chain's line, the quests done in one
-- spot, and the places with their quests as the Available page groups them (PlaceGroups). A host that draws its own
-- pages (Cute_Quest) copies this file and not UI.lua.
local _, QB = ...
if QB.dormant then return end
local UI = QB.UI or {}
QB.UI = UI

local INK = { 0.93, 0.88, 0.78 }
local INK_SOFT = { 0.66, 0.60, 0.50 }
local GOOD = { 0.42, 0.86, 0.45 }
local BAD = { 0.90, 0.38, 0.32 }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 0.95, 0.93, 0.88 }
local STATUS = {
  done = { 0.5, 0.5, 0.5 }, banked = GOOD, active = { 0.95, 0.72, 0.3 }, partial = { 0.95, 0.72, 0.3 },
  bagstart = { 0.95, 0.72, 0.3 }, item = INK_SOFT, locked = BAD, prereq = BAD, todo = INK_SOFT, follow = { 0.55, 0.65, 0.95 },
  wrong = { 0.5, 0.5, 0.5 },
}
local Q = QB.Quest

-- a label cut after a whole word with "..." when it is wider than its box (the game would cut it mid-letter); the
-- text as it is when it fits. room: the width it may take, its box's less a little by default. The text's own width
-- is the unbounded one where the client has it: a label of set width may report no more than its box
local function fitText(fs, s, room)
  room = room or (fs:GetWidth() - 4)
  local width = fs.GetUnboundedStringWidth or fs.GetStringWidth
  fs:SetText(s)
  if width(fs) <= room then return s end
  local cut = s
  while true do
    local shorter = cut:match("^(.*%S)%s+%S+$")
    if not shorter then break end
    cut = shorter:gsub("%s*\194\183$", ""):gsub("[,:;]$", "")
    fs:SetText(cut .. "...")
    if width(fs) <= room then return cut .. "..." end
  end
  return s
end
UI.FitText = fitText -- (the Map page's quest rows, MapPage.lua)

----------------------------------------------------------------------------
-- quests: tooltip and clicks shared by every page
----------------------------------------------------------------------------
local function npcLine(tip, label, n)
  if not n then return end
  local where
  -- (on a battleground's island off the two continents, with a map of its own, an NPC still has a place to name)
  if n.inside and not (n.m and n.m > 0) then
    where = n.n .. ", inside the dungeon"
  else
    local zone = QB.Data.MAPNAME[n.m] or ""
    where = string.format("%s, %s %.0f, %.0f", n.n, n.place or zone, n.x, n.y)
  end
  tip:AddDoubleLine(label, where, 0.6, 0.6, 0.6, 1, 1, 1)
end

-- shift-click with the chat box open puts a link in it, as the game's own quest log and bags do
-- chat, through ChatFrameUtil where the client has it (Forever's ChatEdit_* names are deprecation aliases).
-- Only into a chat box you have open and are typing in: QuestBank never opens one (ChatFrameUtil.OpenChat and
-- ChatFrame_OpenChat set the game's ACTIVE_CHAT_EDIT_BOX and the box's own fields and chat type, and from QuestBank's
-- code those carry its taint into what the box does next: sending, Shift-clicking a quest item in the tracker). With
-- the box focused already, InsertLink adds the text and its SetFocus does nothing
local function chatFn(new, old) return (ChatFrameUtil and ChatFrameUtil[new]) or _G[old] end
local function chatInsert(link) local f = chatFn("InsertLink", "ChatEdit_InsertLink"); if f then return f(link) end end
local function chatOpen()
  local active = chatFn("GetActiveWindow", "ChatEdit_GetActiveWindow")
  local box = active and active()
  if not (box and box.HasFocus and box:HasFocus()) then return false end
  return chatFn("InsertLink", "ChatEdit_InsertLink") and true or false
end

-- the short tooltip: name, level and place, XP, the rewards as icons, what stands out; Shift shows the long one
function UI.QuestTooltipShort(tip, q, st, xp)
  tip:AddLine(q.name, GOLD[1], GOLD[2], GOLD[3])
  local full = Q.Full(q)
  local xpText = q.turnIn and "No XP" or (q.xpUnknown and not q.liveFull) and "XP not known yet" or (QB.Comma(xp or full) .. " XP")
  tip:AddDoubleLine(string.format("L%d  \194\183  %s", q.lvl or 0, q.cat and q.cat.name or ""), xpText, 0.8, 0.8, 0.8, 1, 0.82, 0)
  local R = QB.Data.RITEMS and QB.Data.RITEMS[q.id]
  local icons = {}
  for _, key in ipairs({ "c", "r", "u" }) do
    for _, id in ipairs(R and R[key] or {}) do
      if #icons < 6 then
        local ic = C_Item and C_Item.GetItemIconByID and select(2, pcall(C_Item.GetItemIconByID, id))
        icons[#icons + 1] = "|T" .. (type(ic) == "number" and ic or 134400) .. ":20:20:0:0:64:64:5:59:5:59|t"
      end
    end
  end
  if #icons > 0 then tip:AddLine(((R and R.c and #R.c > 0) and "Choose: " or "") .. table.concat(icons, " "), 1, 1, 1) end
  if q.surveyOnly then tip:AddLine("Seen in game. Who gives it isn't known yet.", 0.75, 0.75, 1, true) end
  if st and st.text and st.text ~= "" and st.code ~= "todo" then
    local c = STATUS[st.code] or INK
    tip:AddLine(st.text, c[1], c[2], c[3])
  end
  local drop = QB.Data.DROP and QB.Data.DROP[q.id]
  if drop and drop < 30 then tip:AddLine(string.format("Its items drop %d%% of the time", math.floor(drop + 0.5)), drop < 15 and 0.9 or 0.85, drop < 15 and 0.4 or 0.7, 0.3) end
  tip:AddLine("Shift: sources, chain and notes", 0.5, 0.5, 0.5)
end

function UI.QuestTooltip(tip, q, st, xp, pct, plvl, rewardRow)
  if not (IsShiftKeyDown and IsShiftKeyDown()) and not UI.longTips then return UI.QuestTooltipShort(tip, q, st, xp) end
  tip:AddLine(q.name, GOLD[1], GOLD[2], GOLD[3])
  local cat = q.cat and q.cat.name or ""
  tip:AddDoubleLine(q.surveyOnly and string.format("Level %d", q.lvl) or string.format("Level %d, needs %d", q.lvl, q.req or 1), cat, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
  local full = Q.Full(q)
  local src
  if q.turnIn then
    src = "none: a writ's turn-in"
  elseif q.liveFull then
    src = QB.Live.Source(q) or "the game's own number"
  elseif q.xpUnknown then
    src = "not known yet"
  elseif q.surveyOnly then
    src = "as the game told QuestBank"
  elseif q.confirmed and q.seenOnly then
    src = QB.Comma(q.base) .. ", as players' games showed it"
  elseif q.confirmed then
    src = string.format(q.near and "%s x %s; the game paid within a few percent of this after the cut" or "%s x %s, as the game paid after the cut",
      QB.Comma(q.base), (tostring(q.mult):gsub("%.?0+$", "")))
  elseif q.dungeonMult then
    src = string.format("%s x %s, as its dungeon's other quests", QB.Comma(q.base), (tostring(q.mult):gsub("%.?0+$", "")))
  elseif q.unconfirmed then
    src = string.format("Classic %s, Forever multiplier not read yet", QB.Comma(q.base))
  elseif q.mult ~= 1 then
    src = string.format("%s x %s", QB.Comma(q.base), (tostring(q.mult):gsub("%.?0+$", "")))
  else
    src = QB.Comma(q.base) .. " x 1"
  end
  tip:AddDoubleLine("Forever XP " .. ((q.xpUnknown and not q.liveFull and not q.turnIn) and "?" or QB.Comma(full)), src, 1, 1, 1, 0.55, 0.75, 1)
  UI.RewardLines(tip, q)
  if st and st.behind and st.later then
    tip:AddLine(string.format("Probably behind you: %s, a later step of this chain, is %s, and the game only offers a step once the ones before it are handed in.", QB.Quest.Label(st.later), st.how == "held" and "in your log" or "done"), 1, 0.6, 0.3, true)
  end
  if q.sodLeftover then
    tip:AddLine("A Season of Discovery leftover in Forever's data: nobody has met its NPC in Forever yet, so QuestBank doesn't suggest it.", 1, 0.5, 0.3, true)
  end
  if q.classic and not q.liveFull then
    tip:AddLine("From the Classic database: not seen in Forever yet, so it may differ or not exist.", 1, 0.6, 0.3, true)
  end
  if q.seenOnly then
    -- the required level is the lowest anyone took it at, unless Blizzard's notes give it (the note below says so)
    tip:AddLine(string.format("New in Forever and known only from players' notes: Wowhead doesn't list it yet. Level %d as the game showed it%s.%s",
      q.lvl, q.reqStated and "" or string.format("; it may unlock before level %d", q.req or q.lvl),
      q.turn and "" or " Where it's handed in isn't known yet."), 0.75, 0.75, 1, true)
  end
  if q.surveyOnly then
    tip:AddLine("Seen in game: QuestBank asked the game about it. Who gives it, where, and for which side isn't known yet.", 0.75, 0.75, 1, true)
  end
  if q.note then tip:AddLine(q.note, 1, 0.6, 0.3, true) end
  if q.nerfed and not q.confirmed and not q.liveFull and not q.xpUnknown then
    tip:AddLine("An estimate: Wowhead's reading from before Blizzard's 1 October cut, with the cut applied. Quests in your log use the game's own number.", 1, 0.6, 0.3, true)
  end
  if q.liveFull and math.abs(q.liveFull - QB.Model.Listed(q)) > 25 then
    tip:AddLine(string.format(q.nerfed and "The catalog lists %s. QuestBank uses the game's number." or "Wowhead lists %s. QuestBank uses the game's number.", QB.Comma(QB.Model.Listed(q))), 1, 0.6, 0.3, true)
  end
  if xp then
    local line = (q.turnIn and "No XP " or (QB.Comma(xp) .. " XP ")) .. QB:OnTheDay()
    if pct and pct < 100 then line = line .. string.format(" (%d%% at level %d)", pct, plvl) end
    tip:AddLine(line, pct and pct < 100 and 1 or 0.6, pct and pct < 100 and 0.6 or 1, pct and pct < 100 and 0.3 or 0.6)
  end
  if st then
    local c = STATUS[st.code] or WHITE
    tip:AddLine(st.text, math.min(1, c[1] * 1.6 + 0.25), math.min(1, c[2] * 1.6 + 0.25), math.min(1, c[3] * 1.6 + 0.25), true)
  end
  -- every objective, and what it asks you to bring: in your bags and in your bank
  local e = QB.state.log[q.id]
  if e and e.objectives and #e.objectives > 0 then
    for _, o in ipairs(e.objectives) do
      if o.text and o.text ~= "" then
        if o.done then tip:AddLine("  " .. o.text, 0.4, 0.9, 0.4, true) else tip:AddLine("  " .. o.text, 0.9, 0.9, 0.9, true) end
      end
    end
  end
  local items = QB.Bank.Items(q)
  if items then
    local _, at = QB.Bank.Count(items[1].id)
    for _, it in ipairs(items) do
      local have = it.bags + it.bank
      local line = string.format("%s: %d of %d in your bags", it.name, math.min(it.bags, it.need), it.need)
      if it.bank > 0 then line = line .. string.format(", %d more in your bank", it.bank) end
      local enough = it.bags >= it.need
      local r, g, b = 0.9, 0.9, 0.9
      if enough then r, g, b = 0.4, 0.9, 0.4 elseif have >= it.need then r, g, b = 1, 0.82, 0 end
      tip:AddDoubleLine(line, enough and "all here" or (have >= it.need and "in your bank" or string.format("%d to go", it.need - have)), r, g, b, r, g, b)
    end
    if not at then tip:AddLine("Open your bank once and QuestBank remembers what's in it.", 0.6, 0.6, 0.6, true) end
  end
  if q.tip then tip:AddLine(q.tip, 0.85, 0.8, 0.7, true) end
  if q.group then tip:AddLine("Group quest.", 1, 0.5, 0.3) end
  local chain = Q.ChainText(q)
  if chain then tip:AddLine("Chain: " .. chain, 0.75, 0.75, 1, true) end
  if st and st.code == "prereq" then
    local cc = QB:ChainCost(q)
    if cc then
      local pay = ""
      if cc.xp > 0 then
        pay = QB:Mode() == "lock" and string.format("; the steps pay nothing at the cap (%s XP otherwise)", QB.Comma(cc.xp))
          or string.format("; the steps pay %s XP along the way", QB.Comma(cc.xp))
      end
      tip:AddLine(string.format("%d step%s first%s%s.", cc.n, cc.n == 1 and "" or "s",
        cc.minutes and cc.minutes > 0 and string.format(", about %d min of moving from where you stand", cc.minutes) or "", pay), 0.75, 0.75, 1, true)
    end
  end
  if q.nextSteps then
    local names = {}
    for _, n in ipairs(q.nextSteps) do
      local nq = Q.Get(n)
      if nq and Q.ForMe(nq) then names[#names + 1] = string.format("%s (%s)", nq.name, QB.Short(QB.Model.XpAt(nq, QB.state.level))) end
    end
    if #names > 0 then tip:AddLine("Leads on to: " .. table.concat(names, ", "), 0.75, 0.75, 1, true) end
  end
  local up, upV, upDepth = QB:Upgrade(q)
  if up then
    if QB:Banking() then
      tip:AddLine(string.format("Upgrade: hand it in now and bank %s instead%s, +%s XP.", up.name,
        upDepth > 1 and string.format(" (%d steps on)", upDepth) or "", QB.Comma(upV - (xp or QB.Model.XpAt(q, QB.state.level)))), 0.3, 1, 0.3, true)
    else
      tip:AddLine(string.format("Carry the chain on: %s pays %s XP%s.", up.name, QB.Comma(upV),
        upDepth > 1 and string.format(", %d steps on", upDepth) or ""), 0.3, 1, 0.3, true)
    end
  end
  npcLine(tip, "From", q.give)
  npcLine(tip, "Hand in", q.turn)
  local inLog = QB.state.log[q.id]
  local shift
  if inLog or (st and st.bag) then
    shift = QB:IsCut(q.id) and "Shift-click: keep it" or "Shift-click: cut it"
  else
    shift = QB:IsAdded(q.id) and "Shift-click: take it off your pick-up list" or "Shift-click: put it on your pick-up list"
  end
  -- how long it took, or has taken (Timer.lua)
  if QB.Timer then
    local took, done = QB.Timer.QuestTime(q.id)
    if took and took >= 60 then tip:AddLine(done and ("Took " .. QB.Timer.Span(took)) or ("Accepted " .. QB.Timer.Span(took) .. " ago"), 0.6, 0.6, 0.6) end
  end
  if chatOpen() then shift = "Shift-click: link it in chat" end
  if rewardRow then shift = "Shift-click: link the reward" end -- Find quests' reward rows link the item, not the quest
  tip:AddLine("Click: waypoint.  " .. shift .. ".  Right-click: more.", 0.5, 0.5, 0.5, true)
end

function UI.QuestLink(q)
  local link
  if GetQuestLink then
    local ok, l = pcall(GetQuestLink, q.id)
    if ok and type(l) == "string" and l:find("|Hquest:") then link = l end
  end
  if not link and C_QuestLog and C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, q.id) end
  -- the game makes the link once it knows the quest; until then, its name in brackets
  return link or ("[" .. q.name .. "]")
end

function UI.LinkQuest(q)
  if not chatOpen() then return false end
  chatInsert(UI.QuestLink(q))
  return true
end

function UI.LinkItem(id, name)
  if not (id and chatOpen()) then return false end
  local link
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if info then
    local ok, _, l = pcall(info, id)
    if ok and type(l) == "string" then link = l end
  end
  chatInsert(link or ("[" .. (name or ("Item " .. id)) .. "]"))
  return true
end

-- an item's link into chat: into the chat box you're typing in; else the link in the chat window, for you to
-- Shift-click once you open the box (the game's own click: Blizzard's code puts it in)
function UI.LinkItemAlways(id)
  if UI.LinkItem(id) then return true end
  local name, link = QB.API.ItemInfo(id)
  if link then
    QB:Print(link .. ": press Enter to open chat, then Shift-click this link to put it there.")
  else
    QB:Print(string.format("%s: the game hasn't sent this item yet. Press Enter to open chat, then try again.", name or ("Item " .. id)))
  end
  return false
end

-- a quest's reward items in a tooltip, by name in their quality colour; says so plainly when nobody knows them yet
function UI.RewardLines(tip, q)
  local rw, how = Q.Rewards(q)
  if how == "unknown" then
    tip:AddLine("Rewards: not known yet. Open the quest in game and QuestBank notes them.", 0.75, 0.75, 1, true)
    return
  end
  local c, r, u = rw and rw.c or {}, rw and rw.r or {}, rw and rw.u or {}
  if #c + #r + #u == 0 then
    tip:AddLine(how == "game" and "No item rewards (as your quest window showed)." or how == "survey" and "No item rewards (as the game told QuestBank)."
      or "No item rewards.", 0.6, 0.6, 0.6)
    return
  end
  local function line(id)
    local name, _, quality, icon = QB.API.ItemInfo(id)
    local cr, cg, cb = 0.8, 0.8, 0.8
    if quality and C_Item and C_Item.GetItemQualityColor then
      local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, quality)
      if ok and qr then cr, cg, cb = qr, qg, qb end
    elseif quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
      local col = ITEM_QUALITY_COLORS[quality]
      cr, cg, cb = col.r, col.g, col.b
    end
    tip:AddLine("   " .. (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. (name or ("Item " .. id .. " (the game is loading it)")), cr, cg, cb)
  end
  if #r > 0 then
    tip:AddLine("You get:", 1, 0.82, 0)
    for i = 1, math.min(#r, 6) do line(r[i]) end
  end
  if #c > 0 then
    tip:AddLine(#c > 1 and "Choose one:" or "Reward:", 1, 0.82, 0)
    for i = 1, math.min(#c, 6) do line(c[i]) end
  end
  if #u > 0 then
    tip:AddLine("Rewards include:", 1, 0.82, 0) -- a loot page lists them without saying which are a choice
    for i = 1, math.min(#u, 6) do line(u[i]) end
  end
  -- no Forever source lists them yet: the Classic database's, said as the map icons say it (the game's own answer, your
  -- quest window's or the survey's, replaces them: how is then "game" or "survey")
  local classic = how == "catalog" and QB.Data.RCLASSIC and QB.Data.RCLASSIC[q.id]
  if classic then tip:AddLine("Rewards from Classic data (may differ in Forever).", 1, 0.6, 0.3, true) end
  tip:AddLine((how == "game" and "As your quest window showed them. " or how == "survey" and "As the game told QuestBank. " or "")
    .. "Right-click the quest to link one in chat.", 0.6, 0.6, 0.6, true)
end

local questClick
function UI.QuestClick(q, st, which) QB.Try("click", questClick, q, st, which) end
questClick = function(q, st, which)
  if which == "RightButton" then UI.QuestMenu(q, st) return end
  if IsShiftKeyDown and IsShiftKeyDown() then
    if UI.LinkQuest(q) then return end
    QB:ToggleAdd(q.id)
    UI:Refresh()
    return
  end
  local target, about = q.turn, { qid = q.id, what = "turn" }
  if st and (st.code == "todo" or st.code == "locked" or st.code == "prereq") and q.give then target, about.what = q.give, "give" end
  if st and st.code == "prereq" and QB.Arrow then
    -- a chain: the giver of its first open step, or the turn-in of the step you hold
    local first, held = QB.Arrow.FirstStep(q, st)
    if first then
      target = (held and first.turn) or first.give or target
      about.qid, about.what = first.id, held and "turn" or "give"
    end
  end
  if target and not target.inside then
    -- shown on the arrow for now (it ends once you get there, or the quest is taken or handed in); no plan changes
    QB.API.SetWaypoint(target.m, target.x, target.y, target.n, nil, QB.Model.NpcPlace(target.idx, QB.faction), about)
  elseif not target and q.surveyOnly then
    -- a quest the survey alone knows: no NPC to point at, and it says so
    QB:Print(string.format("Who gives %s isn't known yet. The game told QuestBank its rewards, not where it starts.", q.name))
  end
end

function UI.QuestMenu(q, st)
  st = st or QB:Status(q)
  local items = {}
  local function way(n, what, kind)
    if n and not n.inside and n.m and n.m > 0 then
      items[#items + 1] = { string.format("Waypoint: %s (%s)", n.n, what), function() QB.API.SetWaypoint(n.m, n.x, n.y, n.n, nil, nil, { qid = q.id, what = kind }) end }
    end
  end
  way(q.give, "gives it", QB.state.log[q.id] and "turn" or "give")
  if not (q.give and q.turn and q.give.idx == q.turn.idx) then way(q.turn, "hand in", "turn") end
  local held = QB.state.log[q.id] or st.bag
  -- Skip this quest (out of the route for good, everywhere), and the same place brings it back
  if QB:IsSkipped(q.id) then
    items[#items + 1] = { "Route it again", function() UI.RouteAgain(q) end }
  elseif held and QB:IsCut(q.id) then
    items[#items + 1] = { "Keep it in the route", function() QB:ToggleAdd(q.id); UI:Refresh() end }
  elseif st.code ~= "done" and st.code ~= "wrong" then
    items[#items + 1] = { "Skip this quest", function() UI.SkipQuest(q) end }
  end
  if held then
    if QB.state.log[q.id] then
      items[#items + 1] = { "|cffe05a4aAbandon this quest|r", function() UI.ConfirmAbandon(q) end }
    end
  elseif st.code ~= "done" and st.code ~= "wrong" and not QB:IsSkipped(q.id) then
    items[#items + 1] = { QB:IsAdded(q.id) and "Take it off my pick-up list" or "Put it on my pick-up list", function() QB:ToggleAdd(q.id); UI:Refresh() end }
  end
  local rw = Q.Rewards(q)
  if rw then
    local ids, seen = {}, {}
    for _, list in ipairs({ rw.r or {}, rw.c or {}, rw.u or {} }) do
      for _, id in ipairs(list) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
    end
    for i = 1, math.min(#ids, 6) do
      local id = ids[i]
      local name = QB.API.ItemInfo(id)
      local what = name or ("item " .. id)
      items[#items + 1] = { chatOpen() and ("Link " .. what .. " in chat") or ("Show " .. what .. "'s link in chat"), function() UI.LinkItemAlways(id) end }
    end
  end
  items[#items + 1] = { "Copy the Wowhead link", function() UI:CopyLink(q.name, "https://www.wowhead.com/forever/quest=" .. q.id) end }
  UI:ShowMenu(q.name, items)
end

-- a name cut to n letters with "...", for a menu's line
function UI.Short(name, n)
  name = tostring(name or "")
  if #name <= n then return name end
  -- (a letter cut short at the end goes whole: its lead byte and whatever followed it; a letter of one byte stays)
  return (name:sub(1, n - 3):gsub("[%z\1-\127\194-\244][\128-\191]*$", function(c) return c:byte() >= 128 and "" or c end)) .. "..."
end

-- Skip this quest (QB:SetSkipped): out of the route for good, and never back through Accept for me, Now, Available or the
-- arrow until routed again; the route goes on to its next step at once. A quest in your log may also be given up, as a
-- second choice of its own (never on its own accord): "Also abandon it", asked in the game's own words
function UI.SkipQuest(q)
  if not q then return end
  QB:SetSkipped(q.id, true)
  QB:Print(string.format("Skipped %s: out of your route for good. Right-click it in QuestBank (or Shift-click its pin on the map) to Route it again.", q.name))
  if UI.frame and UI.frame:IsShown() then UI:Refresh() end
  if QB.state.log[q.id] then
    UI:ShowMenu("Skipped: " .. UI.Short(q.name, 22), { { "Keep it in my quest log", function() end },
      { "|cffe05a4aAlso abandon it|r", function() UI.ConfirmAbandon(q) end } })
  end
end
-- Route it again: un-skipped, and a quest you don't hold back on the pick-up list (skipping took it off), so it is
-- in the route as chat says (5.4.4 as first built said so of a pick-up that stayed out)
function UI.RouteAgain(q)
  if not q then return end
  QB:SetSkipped(q.id, false)
  local st = QB:Status(q)
  local pick = not (QB.state.log[q.id] or st.bag) and st.code ~= "done" and st.code ~= "wrong"
  if pick then QB:SetAdded(q.id, true) end
  QB:Print(string.format(pick and "%s is back in your route (on your pick-up list)." or "%s is back in your route.", q.name))
  if UI.frame and UI.frame:IsShown() then UI:Refresh() end
end

-- the game's own question before a quest is given up (ABANDON_QUEST_CONFIRM: 'Abandon "%s"?'), in QuestBank's menu: the
-- game's popup itself is never raised by QuestBank (its popup list would be written as QuestBank, and the game's next
-- popup could then be blocked; see the harness's calls QuestBank never makes), so the question is the game's and the
-- answer a click of yours
function UI.ConfirmAbandon(q)
  local ask = type(ABANDON_QUEST_CONFIRM) == "string" and ABANDON_QUEST_CONFIRM:find("%s", 1, true) and ABANDON_QUEST_CONFIRM:format(UI.Short(q.name, 20))
    or ("Abandon " .. UI.Short(q.name, 20) .. "?")
  UI:ShowMenu(ask, { { "|cffe05a4aYes, abandon it|r", function() UI.Abandon(q) end }, { "No, keep it", function() end } })
end

-- abandon a quest in your log, the game's own way (select it, mark it, abandon); a click in QuestBank's menu, asked twice
function UI.Abandon(q)
  local L = C_QuestLog
  local ok = false
  if L and L.SetSelectedQuest and L.SetAbandonQuest and L.AbandonQuest then
    ok = pcall(L.SetSelectedQuest, q.id) and pcall(L.SetAbandonQuest) and pcall(L.AbandonQuest)
  elseif SelectQuestLogEntry and SetAbandonQuest and AbandonQuest and GetQuestLogIndexByID then
    local idx = GetQuestLogIndexByID(q.id)
    ok = idx and idx > 0 and pcall(SelectQuestLogEntry, idx) and pcall(SetAbandonQuest) and pcall(AbandonQuest) or false
  end
  QB:Print(ok and ("Abandoned " .. q.name .. ".") or ("The game would not abandon " .. q.name .. " from here: use its quest log."))
end

-- what the finder looks for among the quests you could still take
UI.FINDS = {
  { key = "xp", name = "Highest XP", tip = "The quests that pay the most XP for a slot: advance a chain, fill a free slot, or swap out a weak quest." },
  { key = "gear", name = "Best gear", tip = "Quests whose reward is a piece you can wear or wield, the highest item level first." },
  { key = "trinket", name = "Trinkets", tip = "Quests that reward a trinket, a ring or a necklace, the highest item level first." },
  { key = "recipe", name = "Recipes", tip = "Quests that reward a recipe, pattern, plan or formula." },
}
UI.findMode = "xp"

-- each reward item judged on its own: what it is (C_Item.GetItemInfoInstant, the client's item table; D.RIT, read from
-- the same table, where the client answers nothing) and whether you can use it
local INVTYPE = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST", "INVTYPE_WAIST", "INVTYPE_LEGS",
  "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_SHIELD",
  "INVTYPE_RANGED", "INVTYPE_CLOAK", "INVTYPE_2HWEAPON", "INVTYPE_BAG", "INVTYPE_TABARD", "INVTYPE_ROBE", "INVTYPE_WEAPONMAINHAND",
  "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "INVTYPE_AMMO", "INVTYPE_THROWN", "INVTYPE_RANGEDRIGHT", "INVTYPE_QUIVER", "INVTYPE_RELIC" }
-- armour pieces count only in your own armour class; cloaks, jewellery, trinkets and held-in-off-hand items fit everyone
local ARMOR_SLOT = { INVTYPE_HEAD = 1, INVTYPE_SHOULDER = 1, INVTYPE_CHEST = 1, INVTYPE_ROBE = 1, INVTYPE_WRIST = 1, INVTYPE_HAND = 1,
  INVTYPE_WAIST = 1, INVTYPE_LEGS = 1, INVTYPE_FEET = 1 }
local ANYONE = { INVTYPE_CLOAK = 1, INVTYPE_FINGER = 1, INVTYPE_NECK = 1, INVTYPE_TRINKET = 1, INVTYPE_HOLDABLE = 1 }
local JEWEL = { INVTYPE_FINGER = 1, INVTYPE_NECK = 1, INVTYPE_TRINKET = 1 }
local WEAPON_SLOT = { INVTYPE_WEAPON = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 1,
  INVTYPE_RANGED = 1, INVTYPE_RANGEDRIGHT = 1, INVTYPE_THROWN = 1 }

-- an item's equip slot, class, subclass, item level (0: Forever's numbers not shown yet) and the classes it is limited
-- to (a class bitmask, nil for anyone)
function UI.ItemFacts(id)
  local loc, cls, sub
  local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if get then
    local ok, _, _, _, l, _, c, sc = pcall(get, id)
    if ok then loc, cls, sub = QB.Plain(l), QB.Plain(c), QB.Plain(sc) end
  end
  local d = QB.Data.RIT and QB.Data.RIT[id]
  if type(loc) ~= "string" then loc = d and INVTYPE[d[2]] or "" end
  if type(cls) ~= "number" then cls = d and d[3] end
  if type(sub) ~= "number" then sub = d and d[4] end
  local ilvl = d and d[1] or 0
  -- an item no list described (one the quest survey learned in this session): the game's own item level, once the
  -- client has the item (the survey asks the server for it and redraws when it comes)
  if not d and QB.Survey and QB.Survey.ItemLevel then ilvl = QB.Survey.ItemLevel(id) or 0 end
  return loc, cls, sub, ilvl, d and d[5]
end

-- the heaviest armour you wear at your level, from the client's skill tables (D.ARMOR): warriors and paladins mail until
-- plate at 40, hunters and shamans leather until mail at 40, rogues and druids leather, the others cloth. 1 cloth,
-- 2 leather, 3 mail, 4 plate; nil when the class is not known
function UI.MyArmor(level)
  local a = QB.Data.ARMOR and QB.Data.ARMOR[QB.state.class or ""]
  if not a then return nil end
  local best = 1
  for sub = 1, 4 do if a[sub] and a[sub] <= (level or QB.state.level or 60) then best = sub end end
  return best
end

-- what an item is to you: "gear" (a piece you can wear or wield), "trinket" (a trinket, ring or necklace, which is gear
-- too), "recipe", or nil (not for you, or not equipment); then its item level and equip slot
function UI.ItemUse(id, level)
  local loc, cls, sub, ilvl, mask = UI.ItemFacts(id)
  local bit = QB.API.ClassBit()
  if mask and bit > 0 and math.floor(mask / bit) % 2 == 0 then return nil, ilvl, loc end -- for other classes
  if cls == 9 then return "recipe", ilvl, loc end
  local class = QB.state.class or ""
  local use
  if ANYONE[loc] then
    use = JEWEL[loc] and "trinket" or "gear"
  elseif ARMOR_SLOT[loc] then
    local mine = UI.MyArmor(level)
    -- 0: a piece of no armour class (goggles and the like) fits anyone
    if cls == 4 and (sub == 0 or not mine or sub == mine) then use = "gear" end
  elseif loc == "INVTYPE_SHIELD" then
    local a = QB.Data.ARMOR and QB.Data.ARMOR[class]
    if not a or (a[6] and a[6] <= (level or 60)) then use = "gear" end
  elseif WEAPON_SLOT[loc] then
    local w = QB.Data.WEAPONS and QB.Data.WEAPONS[class]
    if cls == 2 and type(sub) == "number" and (not w or math.floor(w / 2 ^ sub) % 2 == 1) then use = "gear" end
  elseif loc == "INVTYPE_RELIC" then
    if mask then use = "gear" end -- a libram, idol or totem: its own class only
  end
  -- shirts, tabards, bags and ammunition are not gear
  return use, ilvl, loc
end

-- a quest's reward the finder shows for a kind ("gear", "trinket", "recipe") and, for gear, a slot: the best of its items
-- you can use, the highest item level first. Gear and trinkets need a known item level. Returns the item and its level.
-- slot: a slot's name (UI.GEAR_SLOTS), or the set of equip locations itself
-- (the Gear page asks this for every quest within reach and every slot: tens of thousands of calls a refresh, so the
-- lists it walks are made once)
local REWARD_KEYS, NO_ITEMS = { "c", "r", "u" }, {}
function UI.BestReward(qid, kind, level, slot)
  local want
  if type(slot) == "table" then want = slot
  elseif slot then for _, g in ipairs(UI.GEAR_SLOTS) do if g[1] == slot then want = g[2] end end end
  local R = QB.Data.RITEMS and QB.Data.RITEMS[qid]
  local bestId, bestL
  for _, key in ipairs(REWARD_KEYS) do
    for _, id in ipairs(R and R[key] or NO_ITEMS) do
      local use, ilvl, loc = UI.ItemUse(id, level)
      local hit
      if kind == "gear" then hit = (use == "gear" or use == "trinket") and ilvl > 0 and (not want or want[loc] ~= nil)
      elseif kind == "trinket" then hit = use == "trinket" and ilvl > 0
      elseif kind == "recipe" then hit = use == "recipe" end
      if hit and (not bestL or ilvl > bestL) then bestId, bestL = id, ilvl end
    end
  end
  return bestId, bestL
end

local function itemName(id)
  if not id or id == 0 then return nil end
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not name and GetItemInfo then name = GetItemInfo(id) end
  return name
end
UI.ItemName = itemName -- (UI.lua's rows)

-- the finder's rows for a reward kind: quests you can take now (any status but done, wrong or held), whatever their
-- quest level, with "2 levels ahead" ticked also those you can take within two levels; each with the best of its
-- rewards you can use, the highest item level first (recipes: the most XP first).
-- { q, value, st, item, ilvl, req, mins }. slot: for gear, a slot's name (UI.GEAR_SLOTS) or a set of equip locations,
-- the finder's own choice (UI.gearSlot) when none is given
function UI:FindRewards(kind, level, slot)
  if not QB.Data.RITEMS then return {} end
  local reqMax = level + (QB:Settings().finderAhead and 2 or 0)
  slot = kind == "gear" and (slot or UI.gearSlot) or nil
  local out = {}
  for _, c in ipairs(self:Candidates(nil, level, reqMax, true)) do
    if not c.behind then
      local id, ilvl = UI.BestReward(c.id, kind, level, slot)
      local q = id and Q.Get(c.id)
      if q then
        out[#out + 1] = { q = q, value = QB.Model.XpAt(q, level), st = QB:Status(q), item = id, ilvl = ilvl, req = c.req, mins = c.mins }
      end
    end
  end
  table.sort(out, function(a, b)
    if kind ~= "recipe" and a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if a.value ~= b.value then return a.value > b.value end
    return a.q.id < b.q.id
  end)
  return out
end

-- the slots the Best gear finder narrows to, by the item's equip location
UI.GEAR_SLOTS = { { "Head", { INVTYPE_HEAD = 1 } }, { "Neck", { INVTYPE_NECK = 1 } }, { "Shoulder", { INVTYPE_SHOULDER = 1 } },
  { "Back", { INVTYPE_CLOAK = 1 } }, { "Chest", { INVTYPE_CHEST = 1, INVTYPE_ROBE = 1 } }, { "Wrist", { INVTYPE_WRIST = 1 } },
  { "Hands", { INVTYPE_HAND = 1 } }, { "Waist", { INVTYPE_WAIST = 1 } }, { "Legs", { INVTYPE_LEGS = 1 } }, { "Feet", { INVTYPE_FEET = 1 } },
  { "Ring", { INVTYPE_FINGER = 1 } }, { "Trinket", { INVTYPE_TRINKET = 1 } },
  { "Weapon", { INVTYPE_WEAPON = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 1 } },
  { "Off hand", { INVTYPE_SHIELD = 1, INVTYPE_HOLDABLE = 1 } }, { "Ranged", { INVTYPE_RANGED = 1, INVTYPE_RANGEDRIGHT = 1, INVTYPE_THROWN = 1 } } }
-- does the quest reward a piece for this slot that you can use (judged item by item, as the finder does)?
function UI.RewardSlotFits(qid, slot, level)
  return UI.BestReward(qid, "gear", level or QB.state.level, slot) ~= nil
end

-- the best quests to fetch: for your faction and class, not done, not held, most XP on the day first.
-- Not the ones handed in inside a dungeon: those can't wait in your log for the day.
-- where you stand: the place the route model uses, the mount factor, and the flight master's town (none on an open
-- map off the two continents, Zephras Isle, where you walk)
function UI.Here()
  local fac = QB.faction
  local wp = QB.API.WorldPosition()
  local here
  if wp then
    here = QB.Model.Place(fac, wp.c, wp.wx, wp.wy)
    if here.hub == 0 and not QB.Model.Off(here.c) then here = nil end
  end
  local mf = QB.Model.Factor(QB:Mounted())
  local hub = here and QB.Data.HUB[fac] and QB.Data.HUB[fac][here.hub]
  return here, mf, hub and hub[1] or nil
end

-- minutes from where you stand to a quest's giver (a giver inside a dungeon: to its entrance, else to its
-- hand-in); nil when the giver can't be placed or you can't
function UI.MinutesTo(q, here, mf)
  if not (here and q) then return nil end
  local D, M, fac = QB.Data, QB.Model, QB.faction
  local giveIdx = q.giveIdx and q.giveIdx > 0 and q.giveIdx or nil
  local to = giveIdx and M.NpcPlace(giveIdx, fac) or nil
  if not to and giveIdx and D.NPC[giveIdx] and D.NPC[giveIdx][5] < 0 then
    local ent = q.cat and q.cat.entrance
    local w = ent and M.World and M.World(ent.m, ent.x, ent.y)
    to = (w and M.Place(fac, w.c, w.wx, w.wy)) or (q.turnIdx and q.turnIdx > 0 and M.NpcPlace(q.turnIdx, fac)) or nil
  end
  if not to then return nil end
  local mins = M.Between(here, to, fac, mf)
  if mins == math.huge then return nil end -- no way there is known (a place off every flight path, across the sea)
  return mins
end

-- reqMax (the reward finders): quests you can take at that level, whatever their quest level; else those needing at most
-- two levels more than yours, within the level window (QB:Range). finder: the reward finders' own quests too: the ones
-- the quest survey alone knows (Survey.lua: no giver or place), repeatables and the writs' turn-ins (no XP), which
-- nothing else suggests
function UI:Candidates(limit, level, reqMax, finder)
  local D = QB.Data
  local s = QB.state
  level = level or s.level
  local fac = QB.faction
  local banking = QB:Banking()
  local above, below = QB:Range()
  -- the same question asked several times a refresh: answer it once a second
  local key = table.concat({ limit or 0, level, s.level, s.logCount or 0, tostring(banking), fac or "", s.mapID or 0, above, below, QB:SkipSignature(), QB.doneVer or 0,
                             reqMax or "-", finder and 1 or 0, QB.surveyVer or 0 }, ":")
  local now = GetTime and GetTime() or 0
  UI.candMemo = UI.candMemo or {}
  local memo = UI.candMemo[key]
  if memo and now - memo.t < 1 then return memo.list end
  local bit, rbit = QB.API.ClassBit(), QB.API.RaceBit()
  -- questing: nothing far above you; banking: dungeon quests well above you are the big payers.
  -- Settings can widen or narrow both ends (QB:Range)
  local ceiling = level + above
  -- how far each giver is from you: the minutes column in both modes; questing, nearby quests come first
  local here, mf = UI.Here()
  local out = {}
  for id, r in pairs(D.Q) do
    local side, cls = r[3], r[9]
    local turn = D.NPC[(fac == "H" and D.TURNH and D.TURNH[id]) or r[6]]
    local race = D.RACE[id]
    if (side == 0 or (side == 1 and fac == "A") or (side == 2 and fac == "H"))
      and (cls == 0 or bit == 0 or math.floor(cls / bit) % 2 == 1)
      and (not race or rbit == 0 or rbit > 128 or math.floor(race / rbit) % 2 == 1)
      and r[2] <= (reqMax or s.level + 2) and r[1] >= level - below and (reqMax ~= nil or r[1] <= ceiling) and not s.log[id] and not D.FOLLOW[id]
      and math.floor(r[10] / 128) % 2 == 0 -- never suggest Season of Discovery leftovers
      -- nor, but in the reward finders, repeatables, a quest the survey alone knows or a writ's turn-in
      and (finder or (math.floor(r[10] / 4096) % 2 == 0 and math.floor(r[10] / 65536) % 2 == 0 and math.floor(r[10] / 131072) % 2 == 0))
      and not (turn and turn[5] < 0)
      and not QB:Skipped(r[8], turn and turn[5]) -- nor anything where you said to skip
      and not QB:IsSkipped(id) then -- nor a quest you skipped
      local live = QuestBankDB.live and QuestBankDB.live[id]
      out[#out + 1] = { id = id, full = live and live.full or math.floor(r[4] * r[5] + 0.5), lvl = r[1], req = r[2], cat = r[8], give = r[7],
                        turn = (fac == "H" and D.TURNH and D.TURNH[id]) or r[6] }
    end
  end
  local M = QB.Model
  local dropped = 0
  for _, c in ipairs(out) do
    local m = level - c.lvl
    local f = c.full
    if m >= 10 then f = f * 0.1 elseif m >= 6 then f = f * (1 - (m - 5) * 0.2) end
    c.value, c.rank = f, f
    c.behind = QB.Quest.Behind(c.id) and true or nil -- a later step is held or done: probably behind you (banking keeps the raw XP; the swap list leaves it out)
    -- the trip to the giver, in both modes (the Available tab shows the minutes)
    local giveIdx = c.give and c.give > 0 and c.give or nil
    local give = giveIdx and M.NpcPlace(giveIdx, fac) or nil
    local turnP = c.turn and c.turn > 0 and M.NpcPlace(c.turn, fac) or nil
    local to = give
    if not to and giveIdx and D.NPC[giveIdx] and D.NPC[giveIdx][5] < 0 then
      -- a giver inside a dungeon: the trip is to its entrance, or failing that to where it is handed in
      local ent = D.CAT[c.cat] and D.CAT[c.cat].entrance
      local w = ent and M.World and M.World(ent.m, ent.x, ent.y)
      to = (w and M.Place(fac, w.c, w.wx, w.wy)) or turnP
    end
    -- (a place no way is known to, off every flight path across the sea: the model says never; the row shows no
    -- minutes rather than a huge number, and questing it is a waste all the same)
    local trip = (here and to) and M.Between(here, to, fac, mf) or nil
    c.mins = (trip and trip < math.huge) and trip or nil
    if not banking then
      -- questing: XP for the time. The trip to the giver, the quest's own loop from giver to turn-in,
      -- and half of what its chain leads on to.
      -- a giver the catalog can't place (an item drop, a Forever quest nobody has met): no trip is known,
      -- so a modest ten minutes stands in, and it is never dropped on ignorance
      c.away = trip or ((here and not to) and 10 or 0)
      c.back = (give and turnP) and M.Between(give, turnP, fac, mf) or 0
      c.lead = QB:ChainLead(c.id)
      local minutes = c.away + c.back + 3 -- three for the quest itself, so one at your feet isn't infinite
      c.time = 1 / (1 + minutes / 10)
      c.rank = (f + c.lead * 0.5) * c.time * (c.behind and 0.25 or 1)
      -- a waste, for the swap list only (the Plan page still lists it in its zone): more than twenty minutes
      -- to a placed giver, or too little XP for the time, judged more strictly the further away: nothing
      -- under four minutes, the full 60 XP a minute (at level 20's scale) from sixteen
      local strict = math.max(0, math.min(1, (c.away - 4) / 12))
      c.waste = here ~= nil and to ~= nil and (c.away > 20 or (strict > 0 and (f + c.lead) / minutes < 60 * QB.Scale(level) * strict))
      if c.waste then dropped = dropped + 1 end
    end
  end
  UI.candDropped = dropped
  table.sort(out, function(a, b) return a.rank > b.rank end)
  local kept = {}
  for _, c in ipairs(out) do
    if not QB.API.IsDone(c.id) then
      kept[#kept + 1] = c
      if limit and #kept >= limit then break end
    end
  end
  local n = 0
  for k, m in pairs(UI.candMemo) do if now - m.t >= 1 then UI.candMemo[k] = nil else n = n + 1 end end
  UI.candMemo[key] = { t = now, list = kept }
  return kept
end

-- the bands' colours, one a place, in turn
UI.BAND = { { 0.36, 0.27, 0.12 }, { 0.14, 0.27, 0.36 }, { 0.17, 0.33, 0.17 }, { 0.36, 0.17, 0.17 }, { 0.27, 0.18, 0.36 }, { 0.32, 0.32, 0.14 } }

-- a quest's next step you could take once it is handed in: open, not in the log, not done
function UI.FollowUp(q)
  for _, nid in ipairs(q and q.nextSteps or {}) do
    local nq = Q.Get(nid)
    if nq and not QB.state.log[nid] and not QB.API.IsDone(nid) then
      local st = QB:Status(nq)
      if st.code ~= "wrong" and st.code ~= "done" then return nq end
    end
  end
  return nil
end

-- the whole line of a chain, for the drill-down: the steps before this quest (done, in your log, or still to
-- take), then the steps after it along the best-paying branch, three on at most
function UI.ChainLine(q, here, mf)
  local s, D = QB.state, QB.Data
  local out, seen = {}, { [q.id] = true }
  local function item(sq, done)
    if not sq or seen[sq.id] then return end
    seen[sq.id] = true
    local held = s.log[sq.id] ~= nil
    local st = (done and not held) and { code = "done", text = "Done" } or QB:Status(sq)
    out[#out + 1] = { q = sq, st = st, value = QB.Model.XpAt(sq, s.level), held = held or st.bag or false,
                      chosen = (not held) and st.code ~= "done" and QB:IsAdded(sq.id) or false, cut = held and QB:IsCut(sq.id) or false,
                      mins = UI.MinutesTo(sq, here, mf), sub = true }
  end
  for _, p in ipairs(q.pre or {}) do
    local sq = QB:PreStep(p) or (type(p) ~= "table" and Q.Get(p)) or nil
    item(sq, Q.PreDone(p))
  end
  local cur, hops = q, 0
  while cur and cur.nextSteps and hops < 3 do
    local best, bestV
    for _, nid in ipairs(cur.nextSteps) do
      local nq = Q.Get(nid)
      if nq and Q.ForMe(nq) and not seen[nid] then
        local v = QB.Model.XpAt(nq, s.level)
        if not bestV or v > bestV then best, bestV = nq, v end
      end
    end
    if not best then break end
    item(best, false)
    cur, hops = best, hops + 1
  end
  return out
end

-- the quests among these done in the same spot (their objective areas within 300 yards, from D.OBJ):
-- sets it.together = { names of the others } on each member of a group
function UI.Together(items)
  local OBJ = QB.Data.OBJ
  if not OBJ then return end
  local placed = {}
  for _, it in ipairs(items) do
    if it.q and it.st.code ~= "done" and OBJ[it.q.id] then placed[#placed + 1] = it end
  end
  for i = 1, #placed do
    for j = i + 1, #placed do
      local a, b = placed[i], placed[j]
      local near = false
      for _, pa in ipairs(OBJ[a.q.id]) do
        for _, pb in ipairs(OBJ[b.q.id]) do
          if pa[1] == pb[1] then
            local dx, dy = pa[2] - pb[2], pa[3] - pb[3]
            if dx * dx + dy * dy <= 300 * 300 then near = true end
          end
        end
      end
      if near then
        a.together = a.together or {}; b.together = b.together or {}
        a.together[#a.together + 1] = b.q.name
        b.together[#b.together + 1] = a.q.name
      end
    end
  end
end

-- every quest for you by place, as the Available page groups them: what you hold, what you chose to pick up, what
-- you could pick up now, what comes later, what a later step says you have done; each place with its counts and
-- score, the list in the page's order. level: yours by default; now: the Now view's order (what you hold and could
-- fetch there, the near places up), else the Available page's (zone by zone, or the richest first when banking).
-- Returns order (the places), groups (by category index), and where you stand (here, mf, hubName: UI.Here)
function UI.PlaceGroups(level, now)
  local D = QB.Data
  local s = QB.state
  level = level or s.level
  local fac = QB.faction
  local banking = QB:Banking()
  local M = QB.Model
  local here, mf, hubName = UI.Here()
  local v = { now = now and true or false }
  local groups, order = {}, {}
  local function group(cat)
    local g = groups[cat]
    if not g then
      g = { cat = D.CAT[cat], idx = cat, quests = {}, left = 0, fetch = 0, avail = 0, score = 0,
            held = 0, ready = 0, picks = 0, open = 0, notyet = 0, behind = 0, done = 0, nearest = nil, lvlSum = 0, lvlN = 0 }
      groups[cat] = g
      order[#order + 1] = g
    end
    return g
  end
  local seen = {}
  -- grp: 1 to pick up, 2 available now, 3 in your log, 4 not yet, 5 probably behind you, 6 done (counted, not shown)
  local function add(q, near, mins)
    if seen[q.id] then return end
    seen[q.id] = true
    local st = QB:Status(q)
    if st.code == "wrong" then return end
    local value = M.XpAt(q, level)
    local drop = D.DROP and D.DROP[q.id]
    local weight = (drop and drop < 25) and (0.5 + drop / 50) or 1 -- a grind at 10% counts 0.7, at 2% 0.54
    local g = group(D.Q[q.id][8])
    local held = s.log[q.id] ~= nil or st.bag or false
    local chosen = (not held) and st.code ~= "done" and QB:IsAdded(q.id) or false
    local cut = held and QB:IsCut(q.id) or false
    local it = { q = q, st = st, value = value, held = held, chosen = chosen, cut = cut, mins = mins }
    if st.code == "done" then it.grp = 6
    elseif held then it.grp = 3
    elseif chosen then it.grp = 1
    elseif st.behind then it.grp = 5
    elseif st.code == "todo" or st.code == "item" then it.grp = 2
    else it.grp = 4 end
    g.quests[#g.quests + 1] = it
    if held then
      g.held = g.held + 1
      if st.code == "banked" then g.ready = g.ready + 1 elseif not cut then g.left = g.left + value end
      g.score = g.score + value
    elseif chosen then
      g.picks = g.picks + 1
      g.left = g.left + value
      g.score = g.score + value
    elseif st.code == "done" then
      g.done = g.done + 1
    else
      if it.grp == 2 then g.open = g.open + 1 elseif it.grp == 4 then g.notyet = g.notyet + 1 else g.behind = g.behind + 1 end
      g.fetch = g.fetch + value * weight
      g.avail = g.avail + value * weight * (near or 1)
      g.score = g.score + value * weight * 0.25 * (near or 1)
    end
    if mins and not held and st.code ~= "done" and (not g.nearest or mins < g.nearest) then g.nearest = mins end
    if st.code ~= "done" then g.lvlSum, g.lvlN = g.lvlSum + q.lvl, g.lvlN + 1 end
  end
  for _, e in ipairs(s.logOrder) do local q = Q.Get(e.id); if q then add(q, 1) end end
  for _, id in ipairs(QB:BagQuests()) do
    local q = Q.Get(id)
    -- quests you hold as an item in your bags; the rest are ordinary candidates below
    if q and (s.bagStarts[id] or QB.API.ItemCount(q.bag[1]) > 0) then add(q, 1) end
  end
  -- every quest you could fetch, with the minutes to its giver; questing, a zone near you outranks a richer
  -- one across the world (never above one: the lead is for the swap list)
  for _, c in ipairs(UI:Candidates(nil, level)) do
    add(Q.Get(c.id), c.time or 1, c.mins)
  end
  -- what you chose outside the window or in a place you skip still shows, with its minutes
  for id in pairs(QB:Plan().add) do
    local q = Q.Get(id)
    if q and not seen[id] then add(q, 1, UI.MinutesTo(q, here, mf)) end
  end
  -- what you have done in each place, counted for the card
  local bit, rbit = QB.API.ClassBit(), QB.API.RaceBit()
  for id, r in pairs(D.Q) do
    local g = groups[r[8]]
    if g and not seen[id] then
      local side, cls, race = r[3], r[9], D.RACE[id]
      if (side == 0 or (side == 1 and fac == "A") or (side == 2 and fac == "H"))
        and (cls == 0 or bit == 0 or math.floor(cls / bit) % 2 == 1)
        and (not race or rbit == 0 or rbit > 128 or math.floor(race / rbit) % 2 == 1)
        and QB.API.IsDone(id) then g.done = g.done + 1 end
    end
  end
  -- questing: zone by zone from the lowest, an order that holds still while you move (the minutes column says
  -- what is near); banking: the richest place first, what you hold plus what you could fetch
  for _, g in ipairs(order) do g.band = g.lvlN > 0 and g.lvlSum / g.lvlN or 99 end
  table.sort(order, function(a, b)
    if v.now then
      -- where to go now: what you hold and could fetch there, the near places up, skipped ones down
      local set = QB:Settings()
      local sa = (set.skipCat[a.cat.key] or (a.cat.cont ~= nil and set.skipCont[a.cat.cont])) and 1 or 0
      local sb = (set.skipCat[b.cat.key] or (b.cat.cont ~= nil and set.skipCont[b.cat.cont])) and 1 or 0
      if sa ~= sb then return sa < sb end
      local na, nb = a.nearest or 60, b.nearest or 60
      local ka, kb = (a.left + a.avail) / (1 + na / 20), (b.left + b.avail) / (1 + nb / 20)
      if ka ~= kb then return ka > kb end
      return a.score > b.score
    end
    if not banking then
      if math.abs(a.band - b.band) >= 0.5 then return a.band < b.band end
      return (a.cat.name or "") < (b.cat.name or "")
    end
    local ka, kb = a.left + a.avail, b.left + b.avail
    if ka ~= kb then return ka > kb end
    return a.score > b.score
  end)
  return order, groups, here, mf, hubName
end
