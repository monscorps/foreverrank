-- SPDX-License-Identifier: GPL-3.0-or-later AND MIT
-- Contains code from QuestTrail 3.0.6, Copyright (c) 2026 Krom, MIT licence (LICENSE-QuestTrail.txt): QuestTrail_Compass.lua: the dial's layers (A.Create), SizeArrow, ApplyLook, FitBg, Tint, the needle's easing
-- The direction arrow (opt-in, Settings or /qb arrow): points from where you stand and the way you
-- face to a target, with its name and how far it is. What it points at is yours to choose: right-click
-- it, or /qb arrow route|handin|pickup|pin.
--   route    the next stop on your route, or a spot of an objective of its quest still to do: the one target the
--            minimap and the Map page lead to as well (Target.lua), kept until something real changes
--   handin   the nearest NPC you can hand a finished quest in to
--   pickup   the nearest giver of a quest in your plan you haven't taken yet (a chain: its first open
--            step; a chain whose only step left is one you hold is a hand-in, which handin covers)
--   pin      whatever you last clicked a waypoint for in QuestBank: a quest, a stop, an entrance; only when you
--            choose it here (5.4.3 and before switched to it at every click, for good).
-- A click on a quest, a pin, a waypoint or the map shows that place on the arrow for now (A:Show), whether the arrow
-- is on or off: its label says "Showing X" and a right-click goes back to the route at once. It ends by itself when you
-- get there, or the quest it was for is handed in or given up (an item it was for is in your bags); then the arrow is
-- back on what it points at, and says so once ("Back to your route"), or hides again where it was off. A click changes
-- no plan: the route goes on from where you stand as if it never happened. QuestBank never sets the game's own
-- waypoint (Core.lua, API.SetWaypoint), so this is what shows the way at once.
-- It shows the way step by step (Travel.lua, TV.Guide; /qb arrow straight points straight instead): the arrow points
-- at the step's start (a flight master, a pier, the tram), the step's icon takes its place where there is something
-- to do (talk, wait, use the hearthstone), a line names the step, the next says how far or what to do, and a row of
-- icons shows the steps left. The turn, the colour for your heading and the pulses are drawn every frame; the rest
-- 20 times a second. Drawn as QuestBank's own arrow by default (5.4.4, again: the game's tutorial arrow, coloured by
-- your heading, glowing while it points ahead, pinging as you arrive and popping at a new step), or as QuestTrail's
-- compass (the dial, A.QT) when chosen in Settings or the arrow's right-click menu (arrowStyle).
local _, QB = ...
if QB.dormant then return end
local A = {}
QB.Arrow = A

local TV = QB.Travel
local plain = QB.Plain
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local sqrt, abs, floor, max, min, sin, pi, huge = math.sqrt, math.abs, math.floor, math.max, math.min, math.sin, math.pi, math.huge
local MODES = { route = "the next stop on your route", handin = "the nearest hand-in", pickup = "the nearest pick-up", pin = "where you last clicked" }
local ORDER = { "route", "handin", "pickup", "pin" }
A.MODES = MODES

-- the frame: the puck (the arrow, or the step's icon in its place) at the top, then the target's name, the step, the
-- info line and the row of steps left
local WIDTH, TEXT_W, STEP_W = 232, 200, 176
local PUCK_Y = -28                -- the puck's centre, below the frame's top
local ARROW, ACT, TRAIL = 48, 36, 14
local PING_S, POP_S, PING_EVERY = 0.6, 0.25, 2
local SNAP_S, TURN = 0.25, 14     -- a frame this long snaps the arrow; else it eases this fast
local GREY = { unreachable = 0.5, ghost = 0.5, instance = 0.5 } -- nothing to do here: the icon at half alpha
local NO_TRAIL = { ghost = true, instance = true } -- the plan waits: its steps aren't shown

function A.Mode()
  local m = QB:Settings().arrowMode
  return MODES[m] and m or "route"
end

-- step by step (Travel.lua), or straight at the target: /qb arrow straight, or Travel.lua broke this session
function A.Guided()
  return QB:Settings().arrowTravel ~= false and not TV.broken
end

-- a call into Travel.lua; an error there turns the steps off for the session, and the arrow points straight
local function travel(fn, ...)
  local ok, res = pcall(fn, ...)
  if ok then return res end
  TV.broken = true
  if QUESTBANK_DEV then error(res, 0) end
  QB.Err.Record(tostring(res), "", "travel guide")
end
local function reachFrom(here, mode) return TV.Reach(here, TV.Opts(mode)) end

-- the nearest of several places from where you stand: by the way there (your flight paths, boats, the hearthstone)
-- with the steps on, else as the crow flies; another continent is far. The last choice stays until another is
-- clearly quicker (10% and half a minute), and a choice is kept a second, so two looks within it agree
local near, kept = { at = -1 }, {}
function A.Nearest(list, here, mode)
  if not (list and list[1]) then return nil end
  mode = mode or A.Mode()
  local now = GetTime and GetTime() or 0
  if near.list == list and near.mode == mode and now - near.at < 1 then return near.pick end
  local R = here and A.Guided() and travel(reachFrom, here, mode)
  local walk = QB.Model.DETOUR / QB.Model.RUN / 60
  local best, bm, cur, cm
  local was = kept[mode]
  for _, t in ipairs(list) do
    local m = huge
    if R then
      m = TV.Via(R, t)
    elseif here and here.c == t.c then
      local dn, dw = here.wx - t.wx, here.wy - t.wy
      m = sqrt(dn * dn + dw * dw) * walk
    end
    if not best or m < bm then best, bm = t, m end
    if was ~= nil and (t.idx or t.name) == was then cur, cm = t, m end
  end
  if cur and cur ~= best and not (bm <= 0.9 * cm and cm - bm >= 0.5) then best = cur end
  kept[mode] = best.idx or best.name
  near.list, near.mode, near.at, near.pick = list, mode, now, best
  return best
end

-- the route's next place: the one target the minimap and the Map page lead to as well (Target.lua): the route's first
-- stop, or a spot of an objective of its quest still to do, kept until something real changes
local function routeTarget(here) return QB.Target.Get(here or QB.API.WorldPosition()) end

-- an NPC as a target: where it stands in the world, and on its map (for the minimap's pins)
local function npcTarget(idx, p, name, what, kind)
  local n = QB.Data.NPC[idx]
  return { name = name, c = p.c, wx = p.wx, wy = p.wy, m = n and n[2], x = n and n[3], y = n and n[4], idx = idx,
           quests = 0, what = what, kind = kind }
end

-- finished quests in your log, by the NPC who takes them, outside dungeons
local function handinList()
  local Q, M = QB.Quest, QB.Model
  local byNpc, list = {}, {}
  for _, e in ipairs(QB.state.logOrder or {}) do
    if e.complete and not QB:IsSkipped(e.id) then -- (a quest you skipped: never back through the arrow)
      local q = Q.Get(e.id)
      local p = q and q.turn and not q.turn.inside and M.NpcPlace(q.turnIdx, QB.faction)
      if p then
        local t = byNpc[q.turnIdx]
        if not t then
          t = npcTarget(q.turnIdx, p, q.turn.n, "to hand in there", "handin")
          t.qid = q.id -- (its first quest: the colour of the arrow's dial and the minimap's stroke)
          byNpc[q.turnIdx] = t
          list[#list + 1] = t
        end
        t.quests = t.quests + 1
      end
    end
  end
  return list
end

-- where a chain sends you next: the first step neither done nor held (go to its giver), or, when all
-- that is left is a step you hold, that step and true (go to its turn-in)
local function firstStep(q, st)
  if not (st and st.code == "prereq") then return q, false end
  local steps = QB:ChainSteps(q)
  if not steps then return q, false end
  for _, s in ipairs(steps) do if s.q and not s.held then return s.q, false end end
  for _, s in ipairs(steps) do if s.q then return s.q, true end end
  return q, false
end
A.FirstStep = firstStep

-- quests in your plan you haven't taken yet (your own list, and the Guide's picks while it is on: 6.0), by the NPC who
-- gives them (or gives their first open step)
local function pickupList()
  local Q, M = QB.Quest, QB.Model
  local byNpc, list = {}, {}
  local plan = QB:Plan()
  local function consider(id)
    local q = Q.Get(id)
    if q and not QB.state.log[id] and not QB.API.IsDone(id) and not QB:IsSkipped(id) then
      local st = QB:Status(q)
      if st.code == "todo" or st.code == "prereq" then
        local g, held = firstStep(q, st)
        local p = not held and g.give and not g.give.inside and M.NpcPlace(g.giveIdx, QB.faction)
        if p then
          local t = byNpc[g.giveIdx]
          if not t then
            t = npcTarget(g.giveIdx, p, g.give.n, "to pick up there", "pickup")
            t.qid = g.id -- (its first quest: the colour of the arrow's dial and the minimap's stroke)
            byNpc[g.giveIdx] = t
            list[#list + 1] = t
          end
          if g.escort then t.escort = true end -- (the escort glyph on its ! on the minimap)
          t.quests = t.quests + 1
        end
      end
    end
  end
  for id in pairs(plan.add) do consider(id) end
  if QB:GuideOn() then for id in pairs(plan.auto or {}) do if not plan.add[id] then consider(id) end end end
  return list
end

-- the hand-in and pick-up lists cost a scan of your log or plan: each kept for a second (one slot a list, so the
-- minimap's pick-ups never push out the arrow's hand-ins, nor the choice A.Nearest keeps on it), and dropped the moment
-- the plan changes (QB:MarkDirty), the mode changes or you pin something
local cache = { handin = { t = -1 }, pickup = { t = -1 } }
function A.Invalidate() cache.handin.t, cache.pickup.t, near.list = -1, -1, nil end
local function listFor(m)
  local c = cache[m]
  if not c then return nil end
  local now = GetTime and GetTime() or 0
  if now - c.t < 1 then return c.list end
  c.t = now
  c.list = m == "handin" and handinList() or pickupList()
  return c.list
end
A.ListFor = listFor

-- what the arrow points at, judged from where you stand (passed in, so one read serves the whole tick). A pin with no
-- place QuestBank can lead to (an island, a dungeon with no known way in) is a target without a position
function A.Target(here)
  if A.temp then return A.temp end -- (a place clicked, shown for now: A:Show)
  local k = QB.Guide and QB.Guide.Corpse and QB.Guide.Corpse()
  if k then return k end -- (dead: your corpse, whatever the mode, until you are alive again: Guide.lua)
  local m = A.Mode()
  if m == "pin" then
    local p = QB:Settings().arrowPin
    if p and p.none then return { name = p.name or "your waypoint", kind = "pin", none = true } end
    if p and p.c and p.wx and p.wy then return { name = p.name or "your waypoint", c = p.c, wx = p.wx, wy = p.wy, kind = "pin" } end
    return nil
  elseif m == "handin" or m == "pickup" then
    return A.Nearest(listFor(m), here or QB.API.WorldPosition(), m)
  end
  return routeTarget(here)
end

local NOTHING = { route = { "No stop to go to", nil }, handin = { "Nothing finished to hand in", "Finish a quest and the arrow finds its NPC" },
                  pickup = { "Nothing on your pick-up list", "The ! on a quest on Available puts it there" }, pin = { "Nothing chosen yet", nil },
                  corpse = { "Your corpse", nil } }
-- the host's name in the arrow's words (QuestBank, or a host running this engine: QB.NAME, Bridge.lua), and how the
-- arrow is kept up (a host's players are told of its Settings alone, never of /qb); the pin mode's empty line made
-- once a name
local function hostName() return QB.NAME or "QuestBank" end
local function keepsUp() return QB.host and "Settings" or "Settings or /qb arrow" end
local pinHint, pinHintFor
local function pinNothing()
  local n = hostName()
  if n ~= pinHintFor then pinHintFor, pinHint = n, "Click a quest or a stop in " .. n end
  return pinHint
end
local HEAD = { route = "Next stop: %s", handin = "Hand in at %s", pickup = "Pick up at %s", pin = "You chose: %s", corpse = "Run to %s" }

-- world x runs north and world y west; facing counts anticlockwise from north, as SetRotation turns
function A.Bearing(me, t, facing)
  local dn, dw = t.wx - me.wx, t.wy - me.wy
  return atan2(dw, dn) - (facing or 0), sqrt(dn * dn + dw * dw)
end

-- an angle into -pi..pi
local function wrap(a) return (a + pi) % (2 * pi) - pi end

-- the arrow's colour for how far off your heading it points: green straight ahead, gold to the side, red behind
function A.Heading(a)
  a = abs(a)
  if a <= 0.2 then return 0.35, 1, 0.35 end
  if a <= 1.2 then
    local k = a - 0.2
    return 0.35 + 0.65 * k, 1 - 0.18 * k, 0.35 - 0.35 * k
  end
  local k = min(1, (a - 1.2) / (pi - 1.2))
  return 1, 0.82 - 0.47 * k, 0.2 * k
end

-- text that fits its line: as given, else its short form (the town), else cut with "...". True when it changed
function A.Fit(fs, text, short, width)
  if fs.qbText == text and fs.qbShort == short then return false end
  fs.qbText, fs.qbShort = text, short
  fs:SetText(text)
  if text == "" or (fs:GetStringWidth() or 0) <= width then return true end
  if short then
    fs:SetText(short)
    if (fs:GetStringWidth() or 0) <= width then return true end
    text = short
  end
  while #text > 1 do
    text = text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "") -- one letter off the end (a whole UTF-8 one)
    fs:SetText(text .. "...")
    if (fs:GetStringWidth() or 0) <= width then break end
  end
  return true
end

-- an icon ({atlas, file}: the game's atlas where the client has it) on a texture; an icon file is cropped of its border
local function paint(tex, icon)
  if tex.qbIcon == icon then return end
  tex.qbIcon = icon
  if not QB.Art(tex, icon.atlas, icon.file) then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

-- an icon in a line of text (the tooltip)
local markup = {}
local function inline(icon)
  local s = markup[icon]
  if s then return s end
  local ok, info = false, nil
  if icon.atlas and C_Texture and type(C_Texture.GetAtlasInfo) == "function" then ok, info = pcall(C_Texture.GetAtlasInfo, icon.atlas) end
  s = (ok and info ~= nil) and ("|A:" .. icon.atlas .. ":14:14|a ") or ("|T" .. tostring(icon.file) .. ":14:14:0:0:64:64:5:59:5:59|t ")
  markup[icon] = s
  return s
end

local distanceText = TV.DistanceText

-- what you clicked a waypoint for in QuestBank: remembered as the last place clicked, which the arrow points at only
-- when you choose "Where you last clicked" in its menu (a click no longer switches to it: A:Show shows it for now)
function A:Pin(name, c, wx, wy)
  if not (c and wx and wy) then return end
  QB:Settings().arrowPin = { name = name, c = c, wx = wx, wy = wy }
  A.Invalidate()
end

-- A place clicked, shown on the arrow for now (Core.lua's API.SetWaypoint, the camp bar's sellers): p = {c, wx, wy}, or
-- nil where QuestBank knows no way there (said so while the arrow is up); about = { qid, what = "give" | "turn" |
-- "obj", ids = { [quest id] = true } for a stop's, item = an item id, items = { item ids }: every one in your bags }
-- (each optional): what ends it besides getting there. tomtom: TomTom's arrow is there too, and with the arrow off QuestBank's shows only while there is more to the
-- way than the last walk. True when the arrow shows it (still, after its first look: a click it ended at once is not)
function A:Show(name, p, about, tomtom)
  local on = QB:Settings().arrow
  self:EndTemp(nil, true)
  if not p and not on then return false end
  local t = { name = name or "your waypoint", kind = "pin", temp = true, shown = true, on = on and true or false }
  if p then t.c, t.wx, t.wy = p.c, p.wx, p.wy else t.none = true end
  if type(about) == "table" then t.qid, t.what, t.ids, t.item, t.items = about.qid, about.what, about.ids, about.item, about.items end
  A.Mark(t)
  if not on and tomtom then
    -- (TomTom's own arrow points at it as the crow flies: QuestBank's shows the way while it is more than a walk)
    local plan = QB.Travel and QB:Settings().arrowTravel ~= false and QB.Travel.PlanTo(p, "pin")
    if not (plan and #plan.legs > 1) then return false end
    t.travel = true
  end
  A.temp = t
  A.back = nil
  A.Invalidate()
  self:Create()
  if A.inside then A.away = true; self.frame:Hide() return false end -- (inside: shown as you leave)
  self.frame:Show()
  self:Update()
  return A.temp == t
end
-- the waypoint the arrow shows, for its Shift-click ({m, x, y, title}), or nil: a place shown for now carries its own
-- (t.wp, set by API.SetWaypoint only: a camp seller or the bag chain's next step has none, where 5.4.4 as first built
-- printed the last waypoint clicked, an unrelated place); "Where you last clicked" is the last waypoint
function A.Waypoint()
  local t = A.t
  if not (t and t.kind == "pin") then return nil end
  if t.temp then return t.wp end
  return QB.API.LastWaypoint()
end
-- (the older name: the arrow switched off, shown for one waypoint)
function A:ShowFor(name, c, wx, wy)
  if QB:Settings().arrow or not (c and wx and wy) then return false end
  return self:Show(name, { c = c, wx = wx, wy = wy })
end

-- the place shown for now goes (you got there, its quest was handed in or given up, you right-clicked, another click):
-- the arrow is back on what it points at, and says so once in its label ("Back to your route"); where it was off, it
-- hides again. why: "back" (a right-click), "done" (it ended by itself); quiet: another click replaces it
function A:EndTemp(why, quiet, noUpdate)
  local t = A.temp
  if not t then return end
  A.temp = nil
  A.Invalidate()
  if not self.frame then return end
  if not QB:Settings().arrow then
    self.frame:Hide()
  elseif not quiet then
    A.back = (GetTime and GetTime() or 0) + A.BACK_S -- the label says so once, a few seconds
    if QB.tracing then QB.Trace("arrow: %s no longer shown (%s), back to the route", tostring(t.name), why or "ended") end
    if not noUpdate then self:Update() end
  end
end
A.BACK_S = 6

-- what a place shown for now is about, as it stands at the click (A:Show): its quest held, complete, handed in; the
-- stop's quests still open; its items in your bags. Only a change from this ends it (tempOver)
local function bagsHold(t)
  local API = QB.API
  if not API.ItemCount then return false end
  if t.item and API.ItemCount(t.item) > 0 then return true end
  if t.items then
    for _, id in ipairs(t.items) do if API.ItemCount(id) == 0 then return false end end
    return true
  end
  return false
end
function A.Mark(t)
  local log, API = QB.state and QB.state.log or {}, QB.API
  local id = t.qid
  if id then
    local e = log[id]
    t.held, t.complete, t.done = e ~= nil, (e and e.complete) and true or false, API.IsDone(id) and true or false
  end
  if t.ids then
    t.open = false
    for qid in pairs(t.ids) do if type(qid) == "number" and not API.IsDone(qid) and log[qid] then t.open = true end end
  end
  t.bagged = (t.item or t.items) and bagsHold(t) or false
end

-- the place shown for now: ended by what happened to it since the click (true: it is over). Its quest handed in;
-- given up (a hand-in's or an objective's quest that was in your log, gone from it); taken (a giver's, not held at the
-- click); complete (an objective's, not complete at the click); every quest of a stop that was open handed in; the item
-- in your bags that was not (every one of the items: the camp bar's Simple Wood and Flint and Tinder). What already
-- stood so at the click (the hand-in of a quest you have not taken, the giver of one you hold, a quest done or already
-- complete) ends it only when you get there. (5.4.4 as first built judged the state alone, and such a click ended the
-- moment it began: nothing shown, and chat said the arrow showed the way)
local function tempOver(t)
  local log, API = QB.state and QB.state.log or {}, QB.API
  local id = t.qid
  if id then
    if API.IsDone(id) and not t.done then return true end
    local e = log[id]
    if t.what == "give" and e and not t.held then return true end
    if (t.what == "turn" or t.what == "obj") and not e and t.held then return true end
    if t.what == "obj" and e and e.complete and not t.complete then return true end
  end
  if t.ids and t.open then
    local open = false
    for qid in pairs(t.ids) do if type(qid) == "number" and not API.IsDone(qid) and log[qid] then open = true end end
    if not open then return true end
  end
  if (t.item or t.items) and not t.bagged and bagsHold(t) then return true end
  return false
end
A.TempOver = tempOver

function A:SetMode(m)
  if not MODES[m] then return end
  self:EndTemp(nil, true) -- (what it points at chosen: a place shown for now goes)
  QB:Settings().arrowMode = m
  A.Invalidate()
  self:Update()
end

-- the quests the arrow leads to now, to skip: an objective's quest, a hand-in in reach's (those ready there), or a
-- stop's (its pin's quests, Target.lua): those you hold first, the pick-ups folded into the stop only where you hold
-- none of its quests; at most three, the lowest ids first
local function skippable(t)
  local out = {}
  if not t or t.kind ~= "route" then return out end
  if t.obj and t.qid then out[1] = t.qid; return out end
  local log = QB.state and QB.state.log or {}
  for id in pairs(t.ids or {}) do if type(id) == "number" and log[id] then out[#out + 1] = id end end
  if #out == 0 then
    for id in pairs(t.ids or {}) do if type(id) == "number" then out[#out + 1] = id end end
  end
  table.sort(out)
  for i = #out, 4, -1 do out[i] = nil end
  return out
end
A.Skippable = skippable

function A:Menu()
  if not QB.UI then return end
  local items = {}
  -- shown for a waypoint only: choosing what it points at keeps it up (the switch goes on)
  local set = QB:Settings()
  local temp = A.temp and not set.arrow
  if A.temp and set.arrow then
    items[#items + 1] = { "Back to your route", function() A:EndTemp("back") end }
  end
  -- the quest the route leads to: Skip it, for good (its menu in QuestBank, or its map pin's Shift-click, routes it again)
  for _, id in ipairs(skippable(A.t)) do
    local q = QB.Quest.Get(id)
    if q then items[#items + 1] = { "Skip " .. QB.UI.Short(q.name, 26), function() QB.UI.SkipQuest(q) end } end
  end
  for _, m in ipairs(ORDER) do
    local label = (MODES[m]:gsub("^%l", string.upper))
    if A.Mode() == m and not temp then label = label .. "  (now)" end
    if m == "pin" and not set.arrowPin and A.Mode() ~= m then label = label .. " (nothing yet)" end
    items[#items + 1] = { label, function()
      A:SetMode(m)
      if temp then A:Set(true) end
    end }
  end
  -- the hearthstone as a step, or kept for later
  items[#items + 1] = { "Hearthstone in the steps: " .. (set.arrowHearth == false and "off" or "on"), function()
    set.arrowHearth = set.arrowHearth == false
    TV.ver = TV.ver + 1
    QB:Print(set.arrowHearth and "The arrow may send you by hearthstone again." or "The arrow leaves your hearthstone out of its steps.")
    A:Update()
  end }
  -- the look: QuestBank's own arrow, or QuestTrail's compass (Settings has the same)
  items[#items + 1] = { A.QT() and "Look: QuestTrail's compass" or ("Look: " .. hostName() .. "'s arrow"), function()
    set.arrowStyle = A.QT() and "questbank" or "compass"
    A:Restyle()
    QB:Print(A.QT() and ("The arrow is QuestTrail's compass. Its menu or Settings brings " .. hostName() .. "'s own arrow back.") or ("The arrow is " .. hostName() .. "'s own again."))
    if QB.UI and QB.UI.frame and QB.UI.frame:IsShown() then QB.UI:Refresh() end
  end }
  items[#items + 1] = { "Hide the arrow", function()
    A:Set(false)
    QB:Print(temp and ("Arrow hidden. A waypoint you click shows it again; " .. keepsUp() .. " keeps it up.")
      or ("Direction arrow off. " .. keepsUp() .. " brings it back."))
  end }
  QB.UI:ShowMenu("The arrow points at", items)
end

-- who the last walk goes to: a route stop's one hand-in NPC (6.1 said "Walk to Darnassus" right after the portal into
-- Darnassus: the stop's town), else the target's name (a stop of several hand-ins, a pick-up's giver, a place clicked)
function A.WalkTo(t)
  if t and t.kind == "route" and t.qid and not t.obj and (t.quests or 1) == 1 then
    local q = QB.Quest.Get(t.qid)
    local who = q and q.turn and q.turn.n
    if type(who) == "string" and who ~= "" then return who end
  end
  return t and t.name
end

-- the steps in the tooltip: each one left with its minutes, the total, the flight paths this way flies on (the
-- continent of each flight in it: 6.1 counted the continent you stand on, "17 of 18 known here", while the way's one
-- flight was on the other), and the hearthstone
local NO_LEGS, flownOn = {}, {}
local function tipSteps(t, g)
  local plan = g.plan
  if plan and #plan.legs > 1 then
    local foot = g.trail[#g.trail]
    for i, l in ipairs(plan.legs) do
      local c = i == 1 and 1 or 0.7
      local icon = l.icon or foot
      GameTooltip:AddDoubleLine((icon and inline(icon) or "") .. (l.step or ("Walk to " .. (A.WalkTo(t) or "it"))),
        string.format("%d min", max(1, floor(l.walk + l.min + 0.5))), c, c, c, c, c, c)
    end
    GameTooltip:AddLine(string.format("About %d min in all.", max(1, floor((g.eta or plan.min) + 0.5))), 0.8, 0.8, 0.8)
  end
  -- (a way with no flight: no line)
  for k in pairs(flownOn) do flownOn[k] = nil end
  local fac = QB.faction or QB.API.Faction()
  for _, l in ipairs(plan and plan.legs or NO_LEGS) do
    local c = l.kind == "fly" and l.start and l.start.c
    local name = c and TV.CONT_NAME and TV.CONT_NAME[c]
    if name and not flownOn[c] then
      flownOn[c] = true
      local n, total, read = TV.Known(fac, c)
      if total > 0 then
        GameTooltip:AddLine((read or TV.tells) and string.format("Flight paths on %s: %d of %d known", name, n, total)
          or string.format("Flight paths on %s: not read yet, so all count", name), 0.8, 0.8, 0.8)
      end
    end
  end
  local hearth = TV.HearthLine()
  if hearth then GameTooltip:AddLine(hearth, 0.8, 0.8, 0.8, true) end
end

----------------------------------------------------------------------------
-- The look: QuestTrail's compass (the default, the Marker style setting), after QuestTrail_Compass.lua: a dial of
-- three layers of Krom's art, bottom to top the bevelled dial (arrow_bg), the glass, the one layer coloured, half
-- white and half the target's quest's colour (arrow_tint; blue on the way to a flight master, a pier or the tram) and
-- the red needle on top (arrow_needle), the only layer that turns, eased toward the target every frame; sized in
-- screen pixels whatever the UI scale (compassSize). Under it two small lines, what to do ("Fly to Lakeshire, then
-- Turn in"; the travel step blue, QuestBank's own words) and the target's name in white, then how far, then
-- QuestBank's row of the steps left; a dark backdrop behind them when asked (compassBg). No heading colour, glow,
-- ping or pop in this look. The game style keeps the game's own tutorial arrow, greyed and coloured by your heading,
-- with its glow and pulses, the name in gold above the step line.
----------------------------------------------------------------------------
local ART = QB.ART or "Interface\\AddOns\\QuestBank\\art\\" -- (a host holding a copy of the engine names its own folder: QB.ART)
local TRAVEL_KIND = { fly = true, boat = true, zeppelin = true, tram = true, portal = true }
local VERB = { route = "Turn in", handin = "Turn in", pickup = "Take", pin = "Go to", corpse = "Run to" } -- what to do at the target
local EASE = 12                   -- how fast the needle catches up (QuestTrail's: most of the way in about 0.2 s)
local LABEL_W, LINE_H, GAP = 200, 13, 2
A.EASE, A.VERB = EASE, VERB

-- the look: QuestTrail's compass only where chosen (arrowStyle "compass"); QuestBank's own arrow otherwise (a save that
-- never chose has it, 5.4.4). The minimap's Marker style no longer decides it
function A.QT() return QB:Settings().arrowStyle == "compass" end

-- the dial's size (compassSize, 24 to 128 screen pixels) in the frame's own units, whatever the UI scale
function A.DialSize()
  local px = max(24, min(128, tonumber(QB:Settings().compassSize) or ARROW))
  local h
  if type(GetPhysicalScreenSize) == "function" then
    local ok, _, ph = pcall(GetPhysicalScreenSize)
    ph = ok and plain(ph) or nil
    if type(ph) == "number" then h = ph end
  end
  local f = A.frame
  local scale = f and f:GetEffectiveScale() or 1
  if type(h) == "number" and h > 0 and type(scale) == "number" and scale > 0 then return px * 768 / h / scale end
  return px
end

-- the dial's colour for the target: its quest's (a stop's or a hand-in's own, a pick-up's, as the minimap's markers and
-- strokes), blue on the way to a flight master, a pier, the tram or a portal and while carried; gold for a waypoint
function A.TintFor(t, g)
  local Mini = QB.Mini
  local leg = g and g.leg
  if leg and TRAVEL_KIND[leg.kind] and (g.state == "approach" or g.state == "at" or g.state == "underway") then return Mini.TRAVEL end
  if t and t.obj and t.qid then return Mini.ColorFor(t.qid, "progress") end -- (an objective's spot: its quest's, as its marker)
  if t and (t.kind == "route" or t.kind == "handin") and t.qid then return Mini.ColorFor(t.qid, "finish") end
  if t and t.kind == "pickup" and t.qid then return Mini.ColorFor(t.qid, "start") end
  return Mini.SINGLE
end
-- the glass half white, half the colour (QuestTrail's TINT_MIX): set again only when it changes
A.TINT_MIX = 0.5
function A.Tint(f, c)
  local w = A.TINT_MIX
  local r, g, b = w + c[1] * (1 - w), w + c[2] * (1 - w), w + c[3] * (1 - w)
  if f.tr == r and f.tg == g and f.tb == b then return end
  f.tr, f.tg, f.tb = r, g, b
  f.tint:SetVertexColor(r, g, b)
end

-- where the arrow stands: where it was dragged to (arrowPos, kept by its top), else under the step frame while that
-- stands at its own default place (StepFrame.lua, SF.Below: followed as the frame grows, shrinks or scales), else where
-- the step frame would start (under the game's error text); moved left as far as it takes to stay 16 px clear of the
-- quest tracker's header, as the step frame is. (6.1 put the arrow at TOP 0 -170 and the step frame at -140: the
-- arrow sat on the frame's second and third rows and its time line)
local GAP_Y = 6
function A.Place()
  local f = A.frame
  if not f or f.qbDragging then return end -- (in a drag: left where the cursor has it)
  local pos = QB:Settings().arrowPos
  if pos then
    if f.qbPos ~= pos then
      f.qbPos, f.qbX, f.qbY = pos, nil, nil
      f:ClearAllPoints()
      f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    end
    return
  end
  local SF = QB.StepFrame
  local bx, by = nil, nil
  if SF and SF.Below then bx, by = SF.Below() end
  local x, y = bx or 0, by and (by + GAP_Y) or (SF and SF.TOP_Y or 190)
  local W = UIParent:GetWidth() or 1920
  local lim = (SF and SF.TrackerLeft) and (SF.TrackerLeft(W) - 16) or W
  local over = W / 2 + x + WIDTH / 2 - lim
  if over > 0 then x = x - over end
  if f.qbX == x and f.qbY == y and not f.qbPos then return end
  f.qbPos, f.qbX, f.qbY = nil, x, y
  f:ClearAllPoints()
  f:SetPoint("TOP", UIParent, "TOP", x, -y)
end

function A:Create()
  if self.frame then return self.frame end
  local T = QB.Data.TEX
  local f = CreateFrame("Button", "QuestBankArrow", UIParent)
  self.frame = f
  f:SetSize(WIDTH, 98)
  local pos = QB:Settings().arrowPos
  if pos and pos[1] ~= "TOP" and type(pos[1]) == "string" then
    -- moved by an older QuestBank: kept by the point the game chose for its 170x84 frame (CENTER, BOTTOM...). Kept by
    -- its top from now on, where that frame's top was, so the arrow stays put as the lines under it come and go
    local p, x, y = pos[1], tonumber(pos[2]) or 0, tonumber(pos[3]) or 0
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    if type(W) == "number" and type(H) == "number" and W > 0 and H > 0 then
      x = p:find("LEFT") and x + 85 - W / 2 or p:find("RIGHT") and x - 85 + W / 2 or x
      y = p:find("TOP") and y or p:find("BOTTOM") and y + 84 - H or y + 42 - H / 2
      pos = { "TOP", x, y }
      QB:Settings().arrowPos = pos
    end
  end
  A.Place()
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:SetScript("OnDragStart", function(self) self.qbDragging = true; self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self.qbDragging = nil
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    -- kept by its top, so the arrow stays put as the lines under it come and go
    local l, top, w = self:GetLeft(), self:GetTop(), self:GetWidth()
    if l and top and w then
      p, x, y = "TOP", l + w / 2 - UIParent:GetWidth() / 2, top - UIParent:GetHeight()
      self:ClearAllPoints()
      self:SetPoint(p, UIParent, p, x, y)
    end
    QB:Settings().arrowPos = { p, x, y }
    self.qbPos = QB:Settings().arrowPos -- (placed: A.Place leaves it there)
  end)
  -- the game style's puck: the game's tutorial arrow, greyed so your heading colours it, with its glow (the old quest
  -- arrow where the client lacks it); a ping behind it
  f.ping = f:CreateTexture(nil, "BACKGROUND")
  f.ping:SetPoint("CENTER", f, "TOP", 0, PUCK_Y)
  f.ping:SetTexture(T.ping)
  f.ping:SetBlendMode("ADD")
  f.ping:Hide()
  f.glow = f:CreateTexture(nil, "BACKGROUND")
  f.glow:SetPoint("CENTER", f, "TOP", 0, PUCK_Y)
  f.glow:SetSize(72, 72)
  f.arrow = f:CreateTexture(nil, "ARTWORK")
  f.arrow:SetPoint("CENTER", f, "TOP", 0, PUCK_Y)
  local atlas = QB.Art(f.arrow, "npe_arrowup", T.questArrow)
  A.size = atlas and ARROW or 40
  f.arrow:SetSize(A.size, A.size)
  f.arrow:SetDesaturated(true)
  f.arrow:Hide()
  A.glows = atlas and QB.Art(f.glow, "npe_arrowupglow", T.questArrow)
  if A.glows then
    f.glow:SetDesaturated(true)
    f.glow:SetVertexColor(0.35, 1, 0.35)
    f.glow:SetBlendMode("ADD")
    f.glow:SetAlpha(0)
  end
  f.glow:Hide()
  -- QuestTrail's dial: its three layers on one frame, shown and hidden together; the needle alone turns
  f.dial = CreateFrame("Frame", nil, f)
  f.dial:SetPoint("TOP", f, "TOP", 0, 0)
  f.dial:SetSize(ARROW, ARROW)
  local function layer(file, l)
    local t = f.dial:CreateTexture(nil, l)
    t:SetTexture(ART .. file, nil, nil, "TRILINEAR")
    t:SetAllPoints(f.dial)
    return t
  end
  f.dialBg, f.tint, f.needle = layer("arrow_bg.png", "BACKGROUND"), layer("arrow_tint.png", "ARTWORK"), layer("arrow_needle.png", "OVERLAY")
  f.dial:Hide()
  -- the step's icon in the puck's place, with a cooldown swipe
  f.act = f:CreateTexture(nil, "ARTWORK")
  f.act:SetPoint("CENTER", f, "TOP", 0, PUCK_Y)
  f.act:SetSize(ACT, ACT)
  f.act:Hide()
  f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cd:SetAllPoints(f.act)
  if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
  f.cd:Hide()
  f.name = f:CreateFontString(nil, "OVERLAY")
  f.name:SetFontObject(GameFontNormal)
  f.name:SetPoint("TOP", 0, -56)
  f.name:SetWidth(TEXT_W)
  f.name:SetWordWrap(false)
  f.stepIcon = f:CreateTexture(nil, "OVERLAY")
  f.stepIcon:SetSize(14, 14)
  f.stepIcon:Hide()
  f.step = f:CreateFontString(nil, "OVERLAY")
  f.step:SetFontObject(GameFontHighlightSmall)
  f.step:SetPoint("TOP", 8, -73)
  f.step:SetWidth(STEP_W)
  f.step:SetWordWrap(false)
  f.step:Hide()
  -- QuestTrail's first line: what to do at the target ("Turn in"), after the travel step when there is one
  f.kind = f:CreateFontString(nil, "OVERLAY")
  f.kind:SetFontObject(GameFontNormalSmall)
  f.kind:SetTextColor(1, 0.82, 0)
  f.kind:SetWordWrap(false)
  f.kind:Hide()
  f.dist = f:CreateFontString(nil, "OVERLAY")
  f.dist:SetFontObject(GameFontHighlightSmall)
  f.dist:SetTextColor(0.85, 0.85, 0.85)
  f.dist:SetPoint("TOP", 0, -73)
  f.dist:SetWidth(TEXT_W)
  f.dist:SetWordWrap(false)
  -- the last line: "Right-click: back to your route" while a place clicked is shown for now, and "Back to your route"
  -- for a few seconds once it is over (A.hint)
  f.hint = f:CreateFontString(nil, "OVERLAY")
  f.hint:SetFontObject(GameFontHighlightSmall)
  f.hint:SetTextColor(0.6, 0.85, 0.6)
  f.hint:SetWidth(TEXT_W)
  f.hint:SetWordWrap(false)
  f.hint:Hide()
  f.trail = {}
  for i = 1, 6 do
    f.trail[i] = f:CreateTexture(nil, "OVERLAY")
    f.trail[i]:SetSize(TRAIL, TRAIL)
    f.trail[i]:Hide()
  end
  -- what the frame shows now, so a tick sets only what changed
  A.clock, A.distY, A.h, A.shownRot, A.shownAlpha, A.cr, A.cg, A.cb = 0, -73, 98, huge, -1, -1, -1, -1
  f:SetScript("OnShow", function() A.snap = true end)
  -- (Shift-click on a waypoint: its line in chat again, with the game's map-pin link, which QuestBank says once a
  -- session: Core.lua, API.SayWaypoint)
  f:SetScript("OnClick", QB.Safe(function(_, which)
    -- (a place shown for now with the arrow up: the right-click is the one click back to the route)
    if which == "RightButton" and A.temp and QB:Settings().arrow then A:EndTemp("back")
    elseif which == "RightButton" then A:Menu()
    elseif IsShiftKeyDown and IsShiftKeyDown() and A.Waypoint() then
      local w = A.Waypoint()
      QB.API.SayWaypoint(w.m, w.x, w.y, w.title, A.temp ~= nil)
    elseif QB.UI then QB.UI:Open(3) end
  end, "arrow click"))
  f:SetScript("OnEnter", QB.Safe(function(self)
    A:Update()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local t, m, g = A.t, A.Mode(), A.g
    GameTooltip:AddLine(t and string.format(t.head or (t.temp and t.on and "Showing %s for now") or HEAD[t.kind] or "%s", t.name) or NOTHING[m][1], 1, 0.82, 0)
    if t and t.quests then GameTooltip:AddLine(string.format("%d quest%s %s.", t.quests, t.quests == 1 and "" or "s", t.what or ""), 1, 1, 1) end
    if t and t.after then GameTooltip:AddLine(t.after, 1, 1, 1, true) end
    if t and g and A.guided then tipSteps(t, g) end
    if t and t.temp and t.on then
      GameTooltip:AddLine("Shown for now: it goes when you get there or its quest is done, and the arrow is back on your route.", 0.8, 0.8, 0.8, true)
    elseif t and t.temp then
      GameTooltip:AddLine("Shown for this waypoint: it goes when you get there. " .. keepsUp() .. " keeps it up.", 0.8, 0.8, 0.8, true)
    else
      GameTooltip:AddLine("Pointing at " .. MODES[m] .. ".", 0.8, 0.8, 0.8)
    end
    -- (the page a click opens: a host's own name for it, Cute's Quests while its Route module is off: UI.PageName)
    local page = (QB.UI and QB.UI.PageName and QB.UI.PageName(3)) or "Route"
    GameTooltip:AddLine(t and t.temp and t.on and ("Click: the " .. page .. " page. Drag: move. Right-click: back to your route.")
      or ("Click: the " .. page .. " page. Drag: move. Right-click: choose what it points at, skip a quest, or hide it."), 0.6, 0.6, 0.6, true)
    if A.Waypoint() then
      GameTooltip:AddLine("Shift-click: the waypoint in chat, with the game's map pin.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
  end, "arrow tooltip"))
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local wait = 0
  f:SetScript("OnUpdate", QB.Safe(function(self, elapsed)
    if not self:IsShown() then return end -- (the game runs it only while shown)
    elapsed = elapsed or 0
    wait = wait - elapsed
    if wait <= 0 then
      wait = 0.05
      A:Update()
    end
    A:Render(elapsed)
  end, "arrow"))
  f:Hide()
  self:ApplyLook()
  return f
end

-- the frame laid out for the look (QuestTrail's dial, or the game's puck) and the dial's size: at its making, and
-- again when the Marker style or the dial's size setting changes (A:Update watches them; the Settings page calls
-- A:Restyle)
function A:ApplyLook()
  local f = self.frame
  if not f then return end
  local set = QB:Settings()
  local qt = A.QT()
  local S = qt and A.DialSize() or 0
  A.lookKey = (qt and "qt" or "game") .. ":" .. tostring(set.compassSize) .. ":" .. tostring(set.compassBg)
  A.qt, A.dialPx = qt, S
  f.act:ClearAllPoints()
  f.name:ClearAllPoints()
  if qt then
    f.dial:SetSize(S, S)
    f.dial:ClearAllPoints()
    f.dial:SetPoint("TOP", f, "TOP", 0, 0)
    f.act:SetPoint("CENTER", f.dial, "CENTER", 0, 0)
    A.actSize = S
    f.name:SetFontObject(GameFontNormalSmall)
    f.name:SetTextColor(1, 1, 1)
    f.name:SetPoint("TOP", f, "TOP", 0, -(S + GAP + LINE_H))
    f.step:SetFontObject(GameFontNormalSmall)
    f.step:SetTextColor(0.4, 0.8, 1)
    f.step:SetJustifyH("LEFT")
    f.arrow:Hide(); f.glow:Hide(); f.ping:Hide()
  else
    f.dial:Hide()
    f.act:SetPoint("CENTER", f, "TOP", 0, PUCK_Y)
    A.actSize = ACT
    f.name:SetFontObject(GameFontNormal)
    f.name:SetTextColor(1, 0.82, 0)
    f.name:SetPoint("TOP", f, "TOP", 0, -56)
    f.step:SetFontObject(GameFontHighlightSmall)
    f.step:SetTextColor(1, 1, 1)
    f.step:SetJustifyH("CENTER")
    f.step:SetWidth(STEP_W)
    f.step:ClearAllPoints()
    f.step:SetPoint("TOP", 8, -73) -- (where A:Create put it; the dial's line moved it)
    f.kind:Hide()
    if f.bg then f.bg:Hide() end
  end
  -- a host's skin (QB.Skin: Cute_Quest): its font on every line, its colours; QuestBank sets none
  local sk = QB.Skin
  if sk then
    for _, t in ipairs({ f.name, f.step, f.kind, f.dist, f.hint }) do
      if sk.font then t:SetFont(sk.font, t == f.name and 13 or 11, "") end
    end
    local ink, soft, accent = sk.INK or { 1, 1, 1 }, sk.SOFT or { 0.85, 0.85, 0.85 }, sk.ACCENT or { 1, 0.82, 0 }
    f.name:SetTextColor(ink[1], ink[2], ink[3])
    f.step:SetTextColor(soft[1], soft[2], soft[3])
    f.dist:SetTextColor(soft[1], soft[2], soft[3])
    f.kind:SetTextColor(accent[1], accent[2], accent[3])
    f.hint:SetTextColor(soft[1], soft[2], soft[3])
  end
  f.act:SetSize(A.actSize, A.actSize)
  -- (laid out afresh: the puck, the lines' places, the steps row)
  A.pointing, A.distY, A.h, A.trailY, A.trailPlan, A.line1, A.hintY = nil, nil, nil, nil, nil, nil, nil
  f.step.qbText, f.name.qbText, f.dist.qbText = nil, nil, nil
  A.shownRot, A.shownAlpha, A.cr = huge, -1, -1
  self:Update()
end
function A:Restyle() self:ApplyLook() end

-- every frame: the arrow turns toward its aim as you turn (eased, so it glides: QuestTrail's needle, most of the way
-- in a fifth of a second), the game style's takes the colour of your heading and glows while it points ahead, and
-- its ping and pop play out. Nothing is set that didn't change
function A:Render(elapsed)
  local f = self.frame
  local now = A.clock + elapsed
  A.clock = now
  local qt = A.qt
  if A.pingAt then
    local k = (now - A.pingAt) / PING_S
    if k >= 1 then
      A.pingAt = nil
      f.ping:Hide()
    else
      local s = 40 + 56 * k
      f.ping:SetSize(s, s)
      f.ping:SetAlpha(0.9 * (1 - k))
    end
  end
  if A.popAt then
    local k = (now - A.popAt) / POP_S
    local s = 1.25 - 0.25 * min(1, k)
    if k >= 1 then A.popAt = nil end
    f.arrow:SetSize(A.size * s, A.size * s)
    f.act:SetSize(A.actSize * s, A.actSize * s)
  end
  if not A.pointing then return end
  local facing
  if A.bear and type(GetPlayerFacing) == "function" then
    local ok, v = pcall(GetPlayerFacing)
    facing = ok and plain(v) or nil
  end
  -- which way you face is unknown (an instance, a secret value), or there is no aim: the arrow dims, upright
  local rot, alpha, known = 0, 0.3, type(facing) == "number"
  if known then
    local target = wrap(A.bear - facing)
    local cur = A.rot
    if A.snap or not cur or elapsed >= SNAP_S then cur = target else cur = wrap(cur + wrap(target - cur) * (1 - math.exp(-elapsed * EASE))) end
    A.rot, rot, alpha = cur, cur, A.alpha
  else
    A.rot = nil
  end
  A.snap = not known
  if abs(rot - A.shownRot) > 0.002 then
    if qt then f.needle:SetRotation(rot) else f.arrow:SetRotation(rot); f.glow:SetRotation(rot) end
    A.shownRot = rot
  end
  if alpha ~= A.shownAlpha then
    if qt then f.dial:SetAlpha(alpha) else f.arrow:SetAlpha(alpha) end
    A.shownAlpha = alpha
  end
  if qt then return end
  local r, g, b = A.Heading(known and rot or 1.2)
  if abs(r - A.cr) > 0.02 or abs(g - A.cg) > 0.02 or abs(b - A.cb) > 0.02 then
    f.arrow:SetVertexColor(r, g, b)
    A.cr, A.cg, A.cb = r, g, b
  end
  if A.glows then
    local ga = (known and abs(rot) <= 0.2) and (0.25 + 0.3 * (0.5 + 0.5 * sin(4 * now))) or 0
    if ga ~= A.glowA then
      f.glow:SetAlpha(ga)
      A.glowA = ga
    end
  end
end

-- a ring that grows and fades behind the puck (the game style's; QuestTrail's compass has none)
function A.Ping()
  if A.qt then return end
  local f = A.frame
  A.pingAt, A.pinged = A.clock, A.clock
  f.ping:SetSize(40, 40)
  f.ping:SetAlpha(0.9)
  f.ping:Show()
end

-- straight at the target, as before the steps: with them off, or broken
local sg = { trail = {} }
local function straight(me, t)
  sg.aim, sg.act, sg.step, sg.short, sg.icon, sg.cd, sg.plan, sg.leg, sg.eta = nil
  if not me then
    sg.state, sg.info = "nopos", ""
  elseif me.c ~= t.c then
    sg.state, sg.info = "far", "On the other continent"
  else
    local dn, dw = t.wx - me.wx, t.wy - me.wy
    local d = sqrt(dn * dn + dw * dw)
    if d < 15 then
      sg.state, sg.info, sg.act = "there", "You're there", TV.Icons(QB.faction or QB.API.Faction()).there
    else
      sg.state, sg.info, sg.aim = "straight", distanceText(d), t
    end
  end
  return sg
end
local none = { trail = {}, state = "unreachable", info = "No known way there" } -- a pin QuestBank can't lead to
local nothing = { trail = {}, state = "nothing" }

-- where you stand, read into one table each update (A.me: only ever the latest)
local here = {}
function A:Update()
  local f = self.frame
  if not f then return end
  local set = QB:Settings()
  if A.lookKey ~= (A.QT() and "qt" or "game") .. ":" .. tostring(set.compassSize) .. ":" .. tostring(set.compassBg) then self:ApplyLook(); return end
  local me = QB.API.WorldPosition(nil, here)
  -- a place shown for now whose quest was handed in, given up or taken (its item in your bags): over
  if A.temp and tempOver(A.temp) then
    self:EndTemp("done", nil, true)
    if not f:IsShown() then return end
  end
  local t = A.Target(me)
  A.t, A.me, A.guided = t, me, false
  -- the last line: how to get back to the route while a click is shown, and that it is back once it is over
  local hint
  if t and t.temp and t.on then
    hint = "Right-click: back to your route"
  elseif A.back then
    if (GetTime and GetTime() or 0) < A.back then hint = "Back to your route" else A.back = nil end
  end
  A.hint = hint
  if not t then
    local m = A.Mode()
    nothing.info = NOTHING[m][2] or (m == "pin" and pinNothing()) or (QB:Banking() and "Nothing banked yet" or "Nothing ready to hand in")
    A.g = nil
    self:Draw(NOTHING[m][1], nothing, me)
    return
  end
  local g
  if t.none then
    none.act = TV.Icons(QB.faction or QB.API.Faction()).unreachable
    g = none
  elseif t.kind == "corpse" then
    g = straight(me, t) -- (as the crow flies, lit: the travel guide shows "Resurrect first" to a ghost)
  elseif A.Guided() then
    g = travel(TV.Guide, me, t, t.temp and "pin" or A.Mode())
    A.guided = g ~= nil
  end
  g = g or straight(me, t)
  A.g = g
  -- a hand-in with nothing done yet (Target.lua's pending target, no way in known: "Finish <quest>"): standing there
  -- is not "You're there", there is nothing to hand in
  if t.pending and not t.obj and g.state == "there" then g.info = "Finish it first, then hand in here" end
  -- shown for a waypoint: it goes a few seconds after you get there; shown beside TomTom's arrow for the way there,
  -- it goes once only the last walk is left (TomTom's arrow has that)
  if t.temp then
    local s = g.state
    if s == "there" then
      local now = GetTime and GetTime() or 0
      t.there = t.there or now
      if now - t.there >= 4 then self:EndTemp("done", nil, true); return f:IsShown() and self:Update() end
    else
      t.there = nil
    end
    if t.travel and (s == "walk" or s == "straight" or s == "there") then self:EndTemp("done", nil, true); return f:IsShown() and self:Update() end
  end
  -- the label: "Showing X" while a click is shown for now (the arrow up), "Hand in X here" at a hand-in in reach
  -- (Target.lua), else the target's name
  self:Draw((t.temp and t.on) and ("Showing " .. t.name) or t.label or t.name, g, me, t.labelShort)
end

-- QuestTrail's first line, laid out as one centred line: the step's icon, the step (blue) and what to do at the
-- target (gold: ", then Turn in", the comma straight after the step's name as QuestTrail writes it; "Turn in" alone
-- with no step; nothing while carried, or with no target). Returns the line's width
local function line1(f, step, g, S)
  local t = A.t
  local verb = t and (t.verb or VERB[t.kind] or "Go to") or ""
  local kindText = step and (g.state == "underway" and "" or (verb ~= "" and (", then " .. verb) or "")) or verb
  local iw = (step and g.icon) and 17 or 0
  if f.kind.qbText ~= kindText then f.kind.qbText = kindText; f.kind:SetText(kindText) end
  local kw = kindText ~= "" and (f.kind:GetStringWidth() or 0) or 0
  if step then A.Fit(f.step, step, g.short, LABEL_W - iw - kw) end
  local sw = step and (f.step:GetStringWidth() or 0) or 0
  local total = iw + sw + kw
  local x0, y = -total / 2, -(S + GAP)
  if step then
    f.step:SetWidth(sw + 2)
    f.step:ClearAllPoints()
    f.step:SetPoint("TOPLEFT", f, "TOP", x0 + iw, y)
    f.step:Show()
    if g.icon then
      paint(f.stepIcon, g.icon)
      f.stepIcon:ClearAllPoints()
      f.stepIcon:SetPoint("TOPLEFT", f, "TOP", x0, y + 1)
    end
    f.stepIcon:SetShown(g.icon ~= nil)
  else
    f.step:Hide()
    f.stepIcon:Hide()
  end
  if kw > 0 then
    f.kind:SetWidth(kw + 2)
    f.kind:ClearAllPoints()
    f.kind:SetPoint("TOPLEFT", f, "TOP", x0 + iw + sw, y)
    f.kind:Show()
  else
    f.kind:Hide()
  end
  return total
end

-- the backdrop behind the dial and its lines (compassBg): QuestTrail's, fitted to what shows
local function fitBg(f, S, lineW, trailY)
  local set = QB:Settings()
  if not (A.qt and set.compassBg) then
    if f.bg then f.bg:Hide() end
    return
  end
  if not f.bg then
    f.bg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f.bg:SetFrameLevel(max(0, (f:GetFrameLevel() or 1) - 1))
    if f.bg.SetBackdrop then
      f.bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f.bg:SetBackdropColor(0, 0, 0, 0.6)
      f.bg:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    else
      local t = f.bg:CreateTexture(nil, "BACKGROUND")
      t:SetAllPoints()
      t:SetColorTexture(0, 0, 0, 0.6)
    end
  end
  local w = max(S, lineW, f.name:GetStringWidth() or 0, f.dist:GetStringWidth() or 0, A.hint and (f.hint:GetStringWidth() or 0) or 0)
  local bottom = trailY and (trailY - TRAIL) or (-(S + GAP + 2 * LINE_H) - LINE_H - (A.hint and LINE_H or 0))
  if f.bg.w ~= w or f.bg.bottom ~= bottom then
    f.bg.w, f.bg.bottom = w, bottom
    f.bg:ClearAllPoints()
    f.bg:SetPoint("TOP", f, "TOP", 0, 8)
    f.bg:SetSize(w + 20, 8 - bottom + 8)
  end
  f.bg:Show()
end

-- the frame for what the guide says (TV.Guide's g, or the same fields when straight): the name, the step and info
-- lines, the puck (the arrow toward g.aim, or g.act in its place), the row of steps left, the pulses
function A:Draw(name, g, me, short)
  local f = self.frame
  local qt, S = A.qt, A.dialPx
  local step = g.step
  local lineW = 0
  if qt then
    A.Fit(f.name, name, short, LABEL_W)
    lineW = line1(f, step, g, S)
  else
    A.Fit(f.name, name, short, TEXT_W)
    if step then
      if A.Fit(f.step, step, g.short, STEP_W) then
        -- the icon just left of the text, which is centred
        local w = min(f.step:GetStringWidth() or 0, STEP_W)
        f.stepIcon:ClearAllPoints()
        f.stepIcon:SetPoint("RIGHT", f, "TOP", 8 - w / 2 - 3, -79)
      end
      if g.icon then paint(f.stepIcon, g.icon) end
      f.step:Show()
      f.stepIcon:SetShown(g.icon ~= nil)
    else
      f.step:Hide()
      f.stepIcon:Hide()
    end
  end
  A.Fit(f.dist, g.info or "", nil, TEXT_W)
  local y = qt and -(S + GAP + 2 * LINE_H) or (step and -89 or -73)
  if y ~= A.distY then
    A.distY = y
    f.dist:ClearAllPoints()
    f.dist:SetPoint("TOP", 0, y)
  end
  -- the hint line under it (A.hint), a line's height lower; the steps' row and the frame make room for it
  local hint = A.hint
  local hy = y - (qt and LINE_H or 13)
  if hint then
    A.Fit(f.hint, hint, nil, TEXT_W)
    if A.hintY ~= hy then A.hintY = hy; f.hint:ClearAllPoints(); f.hint:SetPoint("TOP", 0, hy) end
  end
  if (hint ~= nil) ~= (A.hintShown == true) then f.hint:SetShown(hint ~= nil); A.hintShown = hint ~= nil end
  local extra = hint and (qt and LINE_H or 13) or 0
  -- the puck. An aim on another continent (a boat on its way over) shows the step's icon instead
  local act, aim = g.act, g.aim
  if aim and not act and not (me and me.c == aim.c) then act, aim = g.icon, nil end
  if act then
    if A.pointing ~= false then
      f.arrow:Hide(); f.glow:Hide(); f.dial:Hide(); f.act:Show()
      A.pointing = false
    end
    paint(f.act, act)
    local grey, alpha = g.state == "unreachable", GREY[g.state] or 1
    if grey ~= A.actGrey or alpha ~= A.actAlpha then
      f.act:SetDesaturated(grey)
      f.act:SetAlpha(alpha)
      A.actGrey, A.actAlpha = grey, alpha
    end
    local cd = g.cd
    if cd and (cd.start ~= A.cdStart or cd.duration ~= A.cdDur) then
      f.cd:SetCooldown(cd.start, cd.duration)
      f.cd:Show()
      A.cdStart, A.cdDur = cd.start, cd.duration
    elseif not cd and A.cdStart then
      f.cd:Hide()
      A.cdStart = nil
    end
  else
    if A.pointing ~= true then
      f.act:Hide(); f.cd:Hide()
      if qt then f.dial:Show() else f.arrow:Show(); if A.glows then f.glow:Show() end end
      A.pointing, A.snap, A.cdStart = true, true, nil
    end
    A.bear = aim and me and atan2(aim.wy - me.wy, aim.wx - me.wx) or nil
    A.alpha = g.state == "underway" and 0.85 or 1
    if qt then A.Tint(f, A.TintFor(A.t, g)) end
  end
  -- a new step (planned, or the last one done): the arrow snaps to it, the puck pops and pings (the game style's;
  -- QuestTrail's compass has neither). Arriving pings, and so does every couple of seconds where there is something to do
  local leg = g.leg
  local kind, to, town = leg and leg.kind, leg and leg.to, leg and leg.town
  if kind ~= A.stepKind or to ~= A.stepTo or town ~= A.stepTown then
    A.stepKind, A.stepTo, A.stepTown = kind, to, town
    A.snap = true
    if not qt then
      A.popAt = A.clock
      if leg then A.Ping() end
    end
  end
  if g.state ~= A.state then
    A.state = g.state
    if g.state == "there" then A.Ping() end
  end
  if g.state == "at" and A.clock - (A.pinged or -huge) >= PING_EVERY then A.Ping() end
  -- the steps left, this one first
  local tr = g.trail
  local n = (tr and not NO_TRAIL[g.state]) and min(#tr, #f.trail) or 0
  if n < 2 then n = 0 end
  local ty = (qt and -(S + GAP + 3 * LINE_H + 2) or (step and -106 or -90)) - extra
  if g.plan ~= A.trailPlan or n ~= A.trailN or ty ~= A.trailY then
    A.trailPlan, A.trailN, A.trailY = g.plan, n, ty
    local x0 = -(n * TRAIL + (n - 1) * 4) / 2
    for i, tx in ipairs(f.trail) do
      if i <= n then
        paint(tx, tr[i])
        tx:ClearAllPoints()
        tx:SetPoint("TOPLEFT", f, "TOP", x0 + (i - 1) * (TRAIL + 4), ty)
        tx:SetAlpha(i == 1 and 1 or 0.5)
        tx:Show()
      else
        tx:Hide()
      end
    end
  end
  local h
  if qt then h = S + GAP + 3 * LINE_H + 10 + (n > 0 and (TRAIL + 4) or 0) + extra
  else h = (step and 114 or 98) + (n > 0 and 16 or 0) + extra end
  if h ~= A.h then
    A.h = h
    f:SetHeight(h)
  end
  fitBg(f, S, lineW, n > 0 and ty or nil)
end

-- the arrow's step for the minimap: where it sends you first (a flight master, a pier, the tram), while the arrow
-- shows and you walk there on this continent. Nil otherwise
local ms = { kind = "step" }
function A.MiniStep()
  local f, g, me = A.frame, A.g, A.me
  if not (f and f:IsShown() and g and g.step and g.aim and g.aim ~= A.t and me and g.aim.c == me.c) then return nil end
  if g.state ~= "approach" and g.state ~= "walk" then return nil end
  ms.c, ms.wx, ms.wy, ms.name = g.aim.c, g.aim.wx, g.aim.wy, g.step
  ms.atlas, ms.icon = g.icon and g.icon.atlas, g.icon and g.icon.file
  return ms
end

function A:Set(on)
  QB:Settings().arrow = on and true or false
  A.temp = nil -- on: it points where its mode says; off: hidden, the waypoint's showing too
  self:Create()
  if on and A.inside then A.away = true; self.frame:Hide() return end -- (inside: back as you leave)
  A.away = nil
  self.frame:SetShown(on and true or false)
  if on then self:Update() end
end

-- (the launch round) inside a dungeon, a raid or a battleground (Travel.lua, TV.Inside) the arrow said "Leave the
-- dungeon first" for a whole run: it goes away at the loading screen in, whatever turns it on or shows a place clicked
-- meanwhile (A.away: it was up, or asked for), and is back at the loading screen out where it is still wanted (the
-- switch on, or a place shown for now). Read at each loading screen and new zone, never per frame
function A.Inside()
  local inside = (TV.Inside and TV.Inside()) and true or false
  if inside == (A.inside == true) then return inside end
  A.inside = inside
  local f = A.frame
  if inside then
    if f and f:IsShown() then A.away = true; f:Hide() end
  elseif A.away then
    A.away = nil
    if f and (QB:Settings().arrow or A.temp) then f:Show(); A:Update() end
  end
  return inside
end

function A:Init()
  if not A.eventFrame then
    local ev = CreateFrame("Frame")
    A.eventFrame = ev
    ev:SetScript("OnEvent", QB.Safe(function() A.Inside() end, "arrow: instance"))
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do pcall(ev.RegisterEvent, ev, e) end
  end
  A.Inside()
  if QB:Settings().arrow then self:Set(true) end
end
