-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Guide: what should you do next, and with whom. What the rules (Rules.lua) make of the seed and the guild's play,
-- drawn around that one question on the quest window's Quests tab (Cute_Quest's PageQuests.lua draws it there through
-- the door Cute.Guide), in the windows' look (Look.lua):
--   band        the step now from the Quests module (Cute.QuestBand): its icon, its words with the count apart and its
--               progress, the next two, your level and the XP bar (G.DrawBand); its click reads the step's quest
--   the pick    the next best thing: the rules' pick from the dungeons in range at your level (guild mates online in
--               range first, then what is left for you there: the bosses you have not killed, the quests open to you,
--               a dungeon you have not been in; then the one closing soonest) as a card (G.DrawPick): its art, its name
--               and the reason in a phrase, its range against your level, its bosses' faces (killed, left, doubted),
--               the quests for it, the best drop, up to four mates online in range in their class colours and Invite
--               (C_PartyInfo.InviteUnit, out of combat only). Its tooltip holds the reasons, every dungeon in range
--               with its counts, where the knowledge comes from, the bosses and their loot, the quests as they stand
--               for you, every mate in range, and for officers the guild's line and what it learned in play. Nothing
--               fits: the pick's own sentence, plainly, on one row
-- Where the seed is stale or none shipped, everything runs on the guild's play alone. G.Items works out only what is
-- drawn: every dungeon in range is weighed for the pick (its counts), the card is the picked one's. Its two thresholds
-- (guideWindow, guideAhead) are in Settings > Rules under "Dungeons and gear".
local _, C = ...
local G = { invited = {}, open = {} }
C.Guide = G

local INVITED = 60 -- seconds an invited mate's button says so
local MATES = 4    -- mates a card shows before "and N more"

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
-- a list of names for a line: the first few, then how many more
local function some(names, max)
  max = max or 4
  if #names <= max then return table.concat(names, ", ") end
  local first = {}
  for i = 1, max do first[i] = names[i] end
  return table.concat(first, ", ") .. " and " .. (#names - max) .. " more"
end

-- the line while Rule 0 is still checking the seed: how far it got (Rules.lua chk.i of chk.n), so a chain that
-- stalls shows where, and a long one shows it moving
function G.Checking()
  local chk = C.Rules.check
  if type(chk) == "table" and type(chk.n) == "number" and chk.n > 0 then
    return string.format("Checking what we knew against this client, %d of %d.", math.min(chk.i or 0, chk.n), chk.n)
  end
  return "Checking what we knew against this client."
end
-- where the knowledge comes from, as the band says it: a line, and its detail (the band's tooltip)
function G.Source()
  local R = C.Rules
  local st, why = R.SeedState()
  local s = R.Seed()
  if st == "none" then return "Nothing shipped with this copy: everything here is learned from the guild's play.", "Dungeons, ranges, enchants and the XP curve fill in as members meet them." end
  if st == "checking" then return G.Checking(), "The Guide fills in when it is done; thirty seconds at most." end
  if st == "stale" then return "The game differs from what we knew; learning from the guild.", "The research: " .. (why or "") .. "." end
  local chk = R.check or {}
  local detail = "Research build " .. (s.build or "?") .. (s.generated and (", " .. s.generated) or "") .. "."
  if R.BetaAsData() then detail = detail .. " This client is " .. chk.client .. ": what the beta showed counts as research until the guild sees it." end
  return "From research and the beta, checked against this client, and what the guild has met since.", detail
end

-- how sure we are of a fact, in one word (its tooltip has the rules' whole words)
local WORD = { seen = "seen", beta = "beta", data = "research", doubted = "doubted", stale = "stale", absent = "absent" }
function G.Word(fact) return type(fact) == "table" and WORD[fact.state] or "" end

-- your kills of a boss, your entries into an instance
local function killedIt(enc) local v = C.Char().counters["e" .. enc]; return type(v) == "number" and v > 0 end
local function beenIn(d) local v = d.id and C.Char().counters["i" .. d.id]; return type(v) == "number" and v > 0 end

-- a dungeon's bosses as the Guide names and counts them: a stale seed's that nobody has met are left out, research this
-- game no longer matches being neither left to kill nor counted (the first 0.5.0 build, once the guild had killed the
-- Deadmines' first boss on a stale seed, listed the research's other three as left and counted "1 of 4")
local function bossesOf(d)
  local m = C.Rules.Model()
  local out = {}
  for _, enc in ipairs(d.bosses or {}) do
    local b = m.bosses[enc]
    if b and b.state ~= "stale" then out[#out + 1] = enc end
  end
  return out
end

-- an awaited dungeon's rule, in the officers' tooltip and /cute rules; a member reads what it means
local AWAITED_RULE = "Not placed yet: two members entering it, or a kill there a group mate names back, give it its place, and the guild's kills name its bosses."
-- a dungeon's tooltip: its range and where it comes from, how sure, every boss with how sure and your kills, the loot.
-- The research's own names and the rule that places an awaited one are the officers' (a member reads what it means)
local function dungeonTip(d, extra)
  local R = C.Rules
  local m = R.Model()
  local bosses = bossesOf(d)
  return function(tip)
    local officer = C.Roster:MeOfficer()
    tip:AddLine(d.name, 1, 1, 1)
    local range, from = R.RangeWords(d)
    tip:AddDoubleLine("Levels " .. range, from, 0.8, 0.8, 0.8, 0.7, 0.7, 0.7)
    tip:AddLine((d.kind == "raid" and "A raid" or "A dungeon") .. (d.new and " new in Forever, " or ", ") .. R.Words(d) .. ".", 0.7, 0.7, 0.7, true)
    if d.seedName and officer then tip:AddLine("The research calls it " .. d.seedName .. ".", 0.6, 0.6, 0.6, true) end
    if d.awaited then tip:AddLine(officer and AWAITED_RULE or "Its levels and bosses are not known yet: they come as the guild goes inside.", 0.6, 0.6, 0.6, true) end
    for _, enc in ipairs(bosses) do
      local b = m.bosses[enc]
      local mine = killedIt(enc) and "you killed it" or "not by you"
      local st = R.Words(b)
      local dim = b.state == "doubted" and 0.45 or 0.75
      tip:AddDoubleLine(b.name, st .. "; " .. mine, 0.85, 0.85, 0.85, dim, dim, dim)
      if b.seedName and officer then tip:AddLine("   The research calls it " .. b.seedName .. ".", 0.6, 0.6, 0.6, true) end
      -- the loot: what the guild saw drop, what research lists and has not been seen, and in how many kills
      local seen, unseen = 0, 0
      for _, ls in pairs(b.loot) do if ls == "seen" then seen = seen + 1 elseif ls ~= "absent" then unseen = unseen + 1 end end
      if seen + unseen > 0 then
        local line = plural(seen, "item", "items") .. " seen in play"
        if unseen > 0 then line = line .. ", " .. unseen .. " from research" .. (b.lootQuiet and (" not seen in " .. (b.kills or 0) .. " kills") or "") end
        tip:AddLine("   Loot: " .. line, 0.6, 0.6, 0.6, true)
      end
    end
    if #bosses == 0 and not d.awaited then tip:AddLine("No bosses known here yet: the guild's kills name them.", 0.6, 0.6, 0.6, true) end
    if extra then extra(tip) end
  end
end

G.DungeonTip = dungeonTip -- (the harness reads a dungeon's tooltip whether or not it is the pick)
-- where the knowledge comes from and the awaited rule, for the reports a bug report pastes: /cute diag and /cute rules
do
  local coreDiag = C.Diag
  function C.Diag()
    local lines = coreDiag and coreDiag() or {}
    local ok, first, detail = pcall(G.Source)
    table.insert(lines, math.max(1, #lines), ok and ("diag guide: " .. tostring(first) .. " " .. tostring(detail)) or ("diag guide: " .. tostring(first)))
    return lines
  end
  local R = C.Rules
  local rulesReport = R.RulesReport
  function R.RulesReport()
    local out = rulesReport and rulesReport() or {}
    out[#out + 1] = "A dungeon the research names and the guild has not met: " .. AWAITED_RULE
    return out
  end
end

----------------------------------------------------------------------------
-- you and the guild, per dungeon
----------------------------------------------------------------------------
-- your side as the seed's quests name it: "a", "h", or nil where the client does not say (UnitFactionGroup, documented)
local function mySide()
  local tag = C.Get("UnitFactionGroup", "player")
  return tag == "Alliance" and "a" or (tag == "Horde" and "h" or nil)
end
-- a dungeon's quests as they stand for you, the other side's left out: each { q, state }, state done (the client says
-- you did it), log (in your quest log), later (it opens above your level), open, or maybe (the seed has no id for it,
-- so the client cannot be asked: named, never counted), and how many of each. Done and in your log are asked of the
-- client by the quest's id (C_QuestLog.IsQuestFlaggedCompleted and GetLogIndexForQuestID, both documented). The quests
-- are the research's: none while Rule 0 is checking it or where this game no longer matches it
local function questsFor(d, level, side)
  local out, n = {}, { open = 0, log = 0, done = 0, later = 0, maybe = 0 }
  if not C.Rules.SeedUsable() then return out, n end
  local isDone = type(C_QuestLog) == "table" and C_QuestLog.IsQuestFlaggedCompleted or nil
  local inLog = type(C_QuestLog) == "table" and C_QuestLog.GetLogIndexForQuestID or nil
  for _, q in ipairs(d.quests or {}) do
    if not (q.side and side and q.side ~= side) then
      local st
      if q.id and C.Get(isDone, q.id) == true then st = "done"
      elseif q.id and type(C.Get(inLog, q.id)) == "number" then st = "log"
      elseif q.min and level < q.min then st = "later"
      elseif not q.id then st = "maybe"
      else st = "open" end
      n[st] = n[st] + 1
      out[#out + 1] = { q = q, state = st }
    end
  end
  local order = { log = 1, open = 2, maybe = 3, later = 4, done = 5 }
  table.sort(out, function(a, b)
    if a.state ~= b.state then return order[a.state] < order[b.state] end
    if (a.q.min or 0) ~= (b.q.min or 0) then return (a.q.min or 0) < (b.q.min or 0) end
    return a.q.name < b.q.name
  end)
  return out, n
end

-- the GUIDs of your group (UnitGUID of party1-4, raid1-40 in a raid)
local function groupGuids()
  local out = {}
  for i = 1, 4 do local g = C.Get(UnitGUID, "party" .. i); if type(g) == "string" then out[g] = true end end
  if C.Get(UnitInRaid, "player") then
    for i = 1, 40 do local g = C.Get(UnitGUID, "raid" .. i); if type(g) == "string" then out[g] = true end end
  end
  return out
end
-- the name an invite goes to: the sender string the member's own Cute speaks under (the name the game takes for a
-- whisper, Comm.lua), else the roster's name where it is a plain one, which Blizzard's own guild roster passes
-- (Blizzard_Communities/GuildRoster.xml: C_PartyInfo.InviteUnit of the row's name). A Kstring is no name to send to
local function inviteName(r)
  if r.entry and type(r.key) == "string" and r.key ~= "" and not C.IsKstring(r.key) then return r.key end
  local n = r.name
  if type(n) == "string" and n ~= "" and not C.IsKstring(n) then return n end
  return nil
end
-- the guild mates online whose level (the roster's: the server's word, not their addon's) is in a dungeon's range and
-- within guideWindow levels of yours, nearest yours first; for a member, only where the policy lets them see levels
local function matesFor(d, rows, level, w, officer, group)
  local out = {}
  if not (d.min and C.Policy:CanSee(officer, false, "level")) then return out end
  for _, r in ipairs(rows) do
    if r.online and not r.me and type(r.level) == "number" and r.level >= d.min and r.level <= d.max and math.abs(r.level - level) <= w then
      out[#out + 1] = { row = r, name = r.short, level = r.level, class = r.class, guid = r.guid, invite = inviteName(r), grouped = r.guid ~= nil and group[r.guid] == true }
    end
  end
  table.sort(out, function(a, b)
    local da, db = math.abs(a.level - level), math.abs(b.level - level)
    if da ~= db then return da < db end
    return a.row.sort < b.row.sort
  end)
  return out
end

-- invites: never in combat (InCombatLockdown, documented), only where the client lets you invite (C_PartyInfo.CanInvite:
-- in a group, the leader or an assistant), and nothing else: the invite is the game's own, no chat line, no chat box
local function inCombat() return C.Callable("InCombatLockdown") and C.Get(InCombatLockdown) == true end
G.InCombat = inCombat
local function canInvite()
  local f = type(C_PartyInfo) == "table" and C_PartyInfo.CanInvite or nil
  if type(f) ~= "function" then return true end -- (where the client cannot say, the invite answers for itself)
  return C.Get(f) ~= false
end
function G.Invite(mate)
  if inCombat() or not (mate and mate.invite) or not canInvite() then return false end
  local f = C.Api("C_PartyInfo", "InviteUnit")
  if not f then return false end
  C.Get(f, mate.invite)
  G.invited[mate.guid or mate.invite] = C.Now()
  if C.UI and C.UI.RefreshAll then C.UI.RefreshAll() end
  return true
end
-- the pick drawn again where it shows: the quest window on its Quests or Dungeons tab (PageQuests.lua and
-- PageJournal.lua draw it through Cute.Guide.DrawPick), once a second at most and not while it is hidden (UI:Refresh:
-- it draws as it opens). What the pick weighs calls it: Rule 0's verdict and the model built again (Rules.lua), a mate
-- online or off, a level, a new member's values (Roster.lua). The guild window's own refresh never reached it
local PICK_PAGES = { quests = true, journal = true }
function G.Redraw()
  local U = C.UI
  local win = U and U.windows and U.windows.quests
  if win and PICK_PAGES[win.page] and win.Refresh then win:Refresh() end
end
local function invitedRecently(mate)
  local t = G.invited[mate.guid or mate.invite or ""]
  return t ~= nil and C.Now() - t < INVITED
end

----------------------------------------------------------------------------
-- the next best thing
----------------------------------------------------------------------------
-- what a card leaves for you, in words: "2 guild mates online in range, 3 bosses you have not killed, 2 quests"
local function reasons(card)
  local out = {}
  if #card.mates > 0 then out[#out + 1] = plural(#card.mates, "guild mate online in range", "guild mates online in range") end
  if card.left > 0 then out[#out + 1] = plural(card.left, "boss you have not killed", "bosses you have not killed") end
  if card.quests > 0 then out[#out + 1] = plural(card.quests, "quest", "quests") end
  if card.unexplored then out[#out + 1] = "you have not been in" end
  return out
end
local function short(card)
  local out = {}
  if #card.mates > 0 then out[#out + 1] = plural(#card.mates, "mate", "mates") end
  if card.left > 0 then out[#out + 1] = plural(card.left, "boss", "bosses") end
  if card.quests > 0 then out[#out + 1] = plural(card.quests, "quest", "quests") end
  if card.unexplored then out[#out + 1] = "not been in" end
  return #out > 0 and table.concat(out, ", ") or "nothing left for you"
end
-- the rules' pick: of the dungeons in range that leave you something to do (a boss you have not killed, a quest open
-- to you, or, where no boss is known yet, a dungeon you have not been in), the one with the most guild mates online in
-- range, then the most left for you, then the one closing soonest. Returns { line, tip, card } (card nil where nothing
-- fits, the line saying so plainly)
function G.Pick(cards, level, soon, st)
  local fit = {}
  for _, c in ipairs(cards) do if c.left + c.quests > 0 or c.unexplored then fit[#fit + 1] = c end end
  table.sort(fit, function(a, b)
    if #a.mates ~= #b.mates then return #a.mates > #b.mates end
    local la, lb = a.left + a.quests + (a.unexplored and 1 or 0), b.left + b.quests + (b.unexplored and 1 or 0)
    if la ~= lb then return la > lb end
    if a.d.max ~= b.d.max then return a.d.max < b.d.max end
    return a.d.name < b.d.name
  end)
  local function why(tip)
    tip:AddLine("The next best thing", 1, 1, 1)
    tip:AddLine("The rules' pick from the dungeons in range at level " .. level .. ": guild mates online in range first, then what is left for you there (bosses you have not killed, quests open to you, a dungeon you have not been in), then the one closing soonest.", 0.7, 0.7, 0.7, true)
    for _, c in ipairs(cards) do tip:AddDoubleLine(c.d.name, short(c), 0.85, 0.85, 0.85, 0.65, 0.65, 0.65) end
    if soon[1] then tip:AddLine("Next to open: " .. soon[1].name .. " at " .. soon[1].min .. ".", 0.6, 0.6, 0.6, true) end
  end
  if st == "checking" then
    return { line = G.Checking(), tip = function(tip) tip:AddLine("The Guide fills in when it is done; thirty seconds at most.", 1, 1, 1, true) end }
  end
  local after = soon[1] and ("; " .. soon[1].name .. " opens at " .. soon[1].min .. ".") or "."
  if #cards == 0 then
    return { line = "No dungeon known for level " .. level .. " yet" .. after, tip = function(tip)
      tip:AddLine("Nothing to run at level " .. level, 1, 1, 1)
      tip:AddLine("No dungeon the research or the guild knows holds your level. The guild's entries and kills fill this in.", 0.7, 0.7, 0.7, true)
      if soon[1] then tip:AddLine("Next to open: " .. soon[1].name .. " at " .. soon[1].min .. ".", 0.6, 0.6, 0.6, true) end
    end }
  end
  local c = fit[1]
  if not c then return { line = "Nothing left for you in range at level " .. level .. after, tip = why } end
  return { line = "Run " .. c.d.name .. ": " .. table.concat(reasons(c), ", "), tip = why, card = c }
end

-- the guild's version, for officers: where most members are (the roster's levels, the server's word: the window of
-- twice guideWindow levels holding the most members, the lowest such) and the dungeon whose range holds the most of
-- them. Returns { line, tip, d }
function G.GuildPick(rows)
  local R = C.Rules
  local levels = {}
  for _, r in ipairs(rows) do if type(r.level) == "number" then levels[#levels + 1] = r.level end end
  if #levels == 0 then return { line = "No member's level to go by yet.", tip = function(tip) tip:AddLine("The guild roster gives no levels yet.", 1, 1, 1, true) end } end
  table.sort(levels)
  local span = math.max(1, 2 * R.Get("guideWindow"))
  -- (the members at each level counted once, and a window of span levels slid over the counts: a guild of a thousand
  -- costs a thousand steps, not a million)
  local at, top = {}, levels[#levels]
  for _, l in ipairs(levels) do at[l] = (at[l] or 0) + 1 end
  local lo, best = levels[1], 0
  local seen = {}
  for _, l in ipairs(levels) do
    if not seen[l] then
      seen[l] = true
      local n = 0
      for x = l, math.min(top, l + span - 1) do n = n + (at[x] or 0) end
      if n > best then lo, best = l, n end
    end
  end
  local hi = lo + span - 1
  local band = lo == hi and tostring(lo) or (lo .. "-" .. hi)
  local list = {}
  for _, d in ipairs(R.EachDungeon()) do
    if d.min and d.state ~= "stale" then
      local n, inBand = 0, 0
      for _, l in ipairs(levels) do
        if l >= d.min and l <= d.max then n = n + 1; if l >= lo and l <= hi then inBand = inBand + 1 end end
      end
      if n > 0 then list[#list + 1] = { d = d, n = n, band = inBand } end
    end
  end
  table.sort(list, function(a, b)
    if a.band ~= b.band then return a.band > b.band end
    if a.n ~= b.n then return a.n > b.n end
    if a.d.min ~= b.d.min then return a.d.min < b.d.min end
    return a.d.name < b.d.name
  end)
  local tip = function(tip)
    tip:AddLine("Where the guild is", 1, 1, 1)
    tip:AddLine(string.format("%d of %d members are %s by the guild roster's levels, more than in any other %s.", best, #levels,
      lo == hi and ("at level " .. lo) or ("between " .. lo .. " and " .. hi), plural(span, "level", "levels")), 0.7, 0.7, 0.7, true)
    for i = 1, math.min(8, #list) do tip:AddDoubleLine(list[i].d.name, plural(list[i].n, "member", "members") .. " in range", 0.85, 0.85, 0.85, 0.65, 0.65, 0.65) end
  end
  local top = list[1]
  if not top or top.band == 0 then return { line = "Most members are " .. band .. ": no dungeon known for those levels yet.", tip = tip } end
  return { line = "Most members are " .. band .. ": " .. top.d.name, tip = tip, d = top.d }
end

----------------------------------------------------------------------------
-- the page's rows
----------------------------------------------------------------------------
-- The rows, worked out once a draw, each one row high: { kind, name, val, who, label, c (the name's colour), wc (the
-- right's), tip, ... } where kind is
--   head     a heading: name, and who on the right (the page's own: the pick's line, the officer's guild line)
--   card     the picked dungeon: name, its range (val) by a level bar (d), how sure in one word (who); pick marks it
--   bosses   its bosses as pips ({ name, state = killed | left | doubted }), who how many are left
--   quests   its quests open to you by name, who how many
--   mate     a guild mate online in range: name in the class's colour, level (val), an Invite button (mate)
--   more     "and N more online in range", a click shows them (fn)
--   note     a line of text, its whole text in the tooltip
-- and the plan beside them: every dungeon in range with its counts (cards), the next best thing (next), the guild's
-- version and what it learned (guild, learned; officers), the bar's level scale (lo, hi)

-- a dungeon's bosses as pips, and how many are left or doubted, for its card
local function pipsOf(d)
  local m = C.Rules.Model()
  local pips, left, doubted = {}, 0, 0
  for _, enc in ipairs(bossesOf(d)) do
    local b = m.bosses[enc]
    local state = killedIt(enc) and "killed" or (b.state == "doubted" and "doubted" or "left")
    if state == "left" then left = left + 1 elseif state == "doubted" then doubted = doubted + 1 end
    pips[#pips + 1] = { name = b.name, state = state }
  end
  return pips, left, doubted
end

-- a card's rows: the dungeon, its bosses, its quests, its mates (the page draws the picked one's; the harness reads any)
function G.CardRows(card, plan)
  local R = C.Rules
  local K = C.UI.COLORS
  local d = card.d
  local pick = plan and plan.next and plan.next.card == card
  local out = {}
  local function add(it) out[#out + 1] = it; return it end
  add({ kind = "card", name = d.name .. (d.kind == "raid" and " (raid)" or ""), val = R.RangeWords(d), who = G.Word(d), d = d, pick = pick,
    tip = dungeonTip(d, pick and function(tip) tip:AddLine("Your next best thing: " .. plan.next.line, 0.9, 0.9, 0.9, true) end or nil) })
  -- the bosses: a pip each, how many are left
  local pips, left, doubted = pipsOf(d)
  local who
  if #pips == 0 then who = nil
  elseif left > 0 then who = left .. " left" .. (doubted > 0 and (", " .. doubted .. " doubted") or "")
  elseif doubted > 0 then who = "every one killed but the doubted"
  else who = "every one killed" end
  add({ kind = "bosses", label = "Bosses", pips = pips, who = who, d = d, tip = dungeonTip(d), c = #pips == 0 and K.MUTE or nil,
    name = #pips == 0 and (d.awaited and "None known: the guild has not placed it yet." or "None known yet: the guild's kills name them.") or nil })
  -- the quests known for it, as they stand for you
  if #card.qlist > 0 then
    local open, n = {}, card.qn
    for _, x in ipairs(card.qlist) do if x.state == "log" or x.state == "open" or x.state == "maybe" then open[#open + 1] = x.q.name end end
    local whoQ
    if card.quests > 0 then
      whoQ = n.log > 0 and (n.log .. " in your log" .. (n.open > 0 and (", " .. n.open .. " to take") or "")) or (n.open .. " to take")
    elseif n.maybe > 0 then whoQ = "not known if done" end
    local parts = {}
    if n.done > 0 then parts[#parts + 1] = n.done .. " done" end
    if n.later > 0 then parts[#parts + 1] = n.later .. " later" end
    add({ kind = "quests", label = "Quests", name = #open > 0 and some(open, 3) or ("None open to you: " .. table.concat(parts, ", ") .. "."),
      c = #open > 0 and K.INK or K.MUTE, who = whoQ, d = d, qlist = card.qlist, tip = function(tip)
        tip:AddLine("Quests for " .. d.name, 1, 1, 1)
        tip:AddLine("From research (the dungeon's quests players recorded); done and in your log as the client says.", 0.6, 0.6, 0.6, true)
        local words = { log = "in your log", open = "to take", done = "done", maybe = "not known whether done" }
        for _, x in ipairs(card.qlist) do
          local q = x.q
          local word = x.state == "later" and ("from level " .. q.min) or words[x.state]
          local dim = x.state == "done" and 0.45 or 0.8
          tip:AddDoubleLine(q.name .. (q.level and (" (" .. q.level .. ")") or ""), word, dim, dim, dim, 0.65, 0.65, 0.65)
        end
      end })
  end
  -- who to run it with: the guild mates online in range, an Invite button each; past a few, a click shows the rest
  local key = d.id or d.name
  local shown = (#card.mates > MATES + 1 and not G.open[key]) and MATES or #card.mates
  for i = 1, shown do
    local mt = card.mates[i]
    add({ kind = "mate", label = i == 1 and "Online" or nil, name = mt.name, val = tostring(mt.level), mate = mt, c = C.UI.ClassColor(mt.class),
      who = mt.grouped and "in your group" or nil, tip = function(tip)
        tip:AddLine(mt.name, 1, 1, 1)
        tip:AddLine("Level " .. mt.level .. ", online, in " .. d.name .. "'s range" .. (mt.row.addon and "." or "; no addon."), 0.7, 0.7, 0.7, true)
      end })
  end
  if #card.mates == 0 then
    add({ kind = "mate", label = "Online", name = "Nobody in range online now.", c = K.MUTE })
  elseif shown < #card.mates then
    local rest = {}
    for i = shown + 1, #card.mates do rest[#rest + 1] = card.mates[i].name .. " " .. card.mates[i].level end
    add({ kind = "more", name = "and " .. (#card.mates - shown) .. " more online in range", c = K.DIM, fn = function() G.open[key] = true; C.UI.DrawAll() end,
      tip = function(tip)
        tip:AddLine("Online in range", 1, 1, 1)
        for _, n in ipairs(rest) do tip:AddLine(n, 0.8, 0.8, 0.8) end
        tip:AddLine("Click to show them all.", 0.45, 0.45, 0.45)
      end })
  elseif G.open[key] and #card.mates > MATES + 1 then
    add({ kind = "more", name = "Show fewer", c = K.DIM, fn = function() G.open[key] = nil; C.UI.DrawAll() end })
  end
  return out
end

function G.Items(officer)
  local R = C.Rules
  local st = R.SeedState()
  local rows = C.Roster:Rows()
  local level = C.Sample.values.level or C.Num("UnitLevel", "player") or 1
  local w = R.Get("guideWindow")
  local m = R.Model()
  local side, group = mySide(), groupGuids()
  local plan = { level = level, cards = {} }
  -- in range: what each dungeon leaves you, the counts the pick weighs (the rows are the picked one's alone, below)
  local now, soon = R.DungeonsFor(level)
  plan.soon = soon
  for _, d in ipairs(now) do
    local card = { d = d, left = 0, doubted = 0, known = 0 }
    for _, enc in ipairs(bossesOf(d)) do
      card.known = card.known + 1
      if killedIt(enc) then
      elseif m.bosses[enc].state == "doubted" then card.doubted = card.doubted + 1
      else card.left = card.left + 1 end
    end
    card.qlist, card.qn = questsFor(d, level, side)
    card.quests = card.qn.open + card.qn.log
    card.mates = matesFor(d, rows, level, w, officer, group)
    card.unexplored = card.known == 0 and not beenIn(d)
    plan.cards[#plan.cards + 1] = card
  end
  plan.next = G.Pick(plan.cards, level, soon, st)
  if officer then
    plan.guild = G.GuildPick(rows)
    -- what the guild's play changed from the research (R.Changes; with no research to weigh it against, what the
    -- guild learned), for the head's tooltip
    plan.learned = {}
    for _, ch in ipairs(R.Changes()) do plan.learned[#plan.learned + 1] = ch.what .. (ch.detail and (": " .. ch.detail) or "") end
    if #plan.learned == 0 then plan.learned[1] = "Nothing yet: the guild's play has matched the research." end
  end
  local items = plan.next.card and G.CardRows(plan.next.card, plan) or {}
  -- the bar's scale: the picked dungeon's range and your level
  local lo, hi = level, level
  local d = plan.next.card and plan.next.card.d
  if d and d.min then lo = math.min(lo, d.min); hi = math.max(hi, d.max) end
  plan.lo, plan.hi = lo - 1, hi + 2
  return items, plan
end

----------------------------------------------------------------------------
-- the page
----------------------------------------------------------------------------
----------------------------------------------------------------------------
-- the Quests tab's band and the guild's pick, in the windows' look (Look.lua)
----------------------------------------------------------------------------
-- The band (the quest window's Quests tab, over both its columns): the step now from the quest module
-- (Cute.QuestBand, C.API.QuestBand) at 15 px white with the step's icon at 24, its quest's name after it in dim where
-- the words do not carry it, the count at the right and a 2 px bar of its progress in the quest gold; the next two at
-- 14 px and 12 px, dim; your level, how far into it and the time to the next, over a 6 px XP bar (your XP white, the
-- planned quests' green, a tick a level). A click on the step reads its quest, Ctrl-click shows it on the arrow, a
-- right-click is its menu (Not now, Drop). Before the log is read, one line says so. Returns the band's height
local BAND_STEP, BAND_NEXT = 34, 17
local function bandKit(UI)
  local kit = UI.bandKit
  if kit then kit:Show() return kit end
  local L, K = UI.Look, UI.COLORS
  kit = UI:Kit("quests")
  local step = CreateFrame("Button", nil, kit)
  step:SetHeight(BAND_STEP)
  step:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  step.icon = L.MakeSlot(step, 24)
  step.icon:SetPoint("LEFT", 0, 0)
  step.text = UI.Text(step, 15, K.WHITE, "LEFT")
  step.quest = UI.Text(step, 11, K.DIM, "LEFT")
  step.count = UI.Text(step, 13, K.INK, "RIGHT")
  step:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
  step:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.04)
  step:SetScript("OnClick", C.Safe(function(self, which) if self.fn then self.fn(self, which) end end, "band: the step"))
  step:SetScript("OnEnter", C.Safe(function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self.tip(GameTooltip); GameTooltip:Show()
  end, "tooltip"))
  step:SetScript("OnLeave", function() GameTooltip:Hide() end)
  kit.step = step
  kit.track = L.Flat(kit, "ARTWORK", { 0.16, 0.16, 0.16 }, 1)
  kit.track:SetHeight(2)
  kit.fill = L.Flat(kit, "OVERLAY", K.QUEST, 1)
  kit.fill:SetHeight(2)
  kit.next = {}
  for i = 1, 2 do
    local r = CreateFrame("Button", nil, kit)
    r:SetHeight(BAND_NEXT)
    r.icon = L.MakeSlot(r, 14)
    r.icon:SetPoint("LEFT", 5, 0)
    r.text = UI.Text(r, 12, K.DIM, "LEFT")
    r:SetScript("OnEnter", C.Safe(function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self.tip(GameTooltip); GameTooltip:Show()
    end, "tooltip"))
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    kit.next[i] = r
  end
  -- (merge3) the step frame's line under the next two (Train, Flight path, Sleeping bag: Cute.QuestBand.Reminder), as the
  -- step frame draws it: a 14 px icon, its words in the ink, its minutes on the right, a 2 px bar at its left in its
  -- category's colour; a click shows its place on the arrow, a right-click is Remind's menu, the tooltip Remind's
  local rr = CreateFrame("Button", nil, kit)
  rr:SetHeight(BAND_NEXT)
  rr:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  rr.icon = L.MakeSlot(rr, 14)
  rr.icon:SetPoint("LEFT", 5, 0)
  rr.bar = L.Flat(rr, "ARTWORK", K.QUEST, 1)
  rr.bar:SetSize(2, 14)
  rr.bar:SetPoint("LEFT", 0, 0)
  rr.text = UI.Text(rr, 12, K.INK, "LEFT")
  rr.mins = UI.Text(rr, 11, K.INK, "RIGHT")
  rr:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
  rr:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.04)
  rr:SetScript("OnClick", C.Safe(function(self, which)
    local Q = C.API.QuestBand
    if not (Q and self.rec) then return end
    if which == "RightButton" then if Q.ReminderMenu then Q.ReminderMenu(self) end
    elseif Q.ReminderGo then Q.ReminderGo(self.rec) end
  end, "band: the line"))
  rr:SetScript("OnEnter", C.Safe(function(self)
    local Q = C.API.QuestBand
    if Q and Q.ReminderTip and self.rec then Q.ReminderTip(self, self.rec) end
  end, "tooltip"))
  rr:SetScript("OnLeave", function() GameTooltip:Hide() end)
  kit.remind = rr
  kit.level = CreateFrame("Button", nil, kit)
  kit.level:SetHeight(16)
  kit.level.text = UI.Text(kit.level, 12, K.INK, "LEFT")
  kit.level.text:SetPoint("LEFT", 0, 0)
  kit.level:SetScript("OnEnter", C.Safe(function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self.tip(GameTooltip); GameTooltip:Show()
  end, "tooltip"))
  kit.level:SetScript("OnLeave", function() GameTooltip:Hide() end)
  kit.xp = L.MakeXP(kit)
  kit.line = L.Flat(kit, "ARTWORK", K.LINE, 1)
  kit.line:SetHeight(1)
  kit.why = UI.Text(kit, 12, K.DIM, "LEFT")
  UI.bandKit = kit
  return kit
end
function G.DrawBand(UI)
  local K, L = UI.COLORS, UI.Look
  local put, fitText = L.Put, UI.FitText
  local kit = bandKit(UI)
  kit:Show()
  local w = (UI.band:GetWidth() or 0)
  if w < 100 then w = UI.scroll:Width() end
  local Q = C.API.QuestBand
  local y = 2
  for _, r in ipairs(kit.next) do r:Hide() end
  kit.step:Hide(); kit.track:Hide(); kit.fill:Hide(); kit.level:Hide(); kit.xp:Hide(); kit.why:Hide()
  kit.remind:Hide(); kit.remind.rec = nil
  if not (Q and Q.On()) then
    -- (no step yet: the module says why, reading the log or a QuestBank too old for it)
    local why = (Q and Q.Why and Q.Why()) or "Reading your quest log."
    put(kit.why, "TOPLEFT", 0, -y - 2, w, why, K.DIM, "LEFT", 12)
    y = y + 22
  else
    local steps = Q.Steps()
    local s1 = steps[1]
    local look = s1 and Q.Look and Q.Look(s1) or {}
    local st = kit.step
    st:ClearAllPoints(); st:SetPoint("TOPLEFT", 0, -y); st:SetWidth(w); st:Show()
    L.FillSlot(st.icon, look.icon)
    local words = s1 and (look.words or Q.Text(s1)) or "Nothing to do yet: the places below are worth your time."
    local count = (look.have and look.need) and (look.have .. "/" .. look.need) or nil
    local right = count and 60 or 0
    put(st.text, "LEFT", 32, 0, w - 32 - right - 8, words, K.WHITE, "LEFT", 15)
    local tw = math.min(w - 32 - right - 8, math.ceil((st.text.GetUnboundedStringWidth or st.text.GetStringWidth)(st.text) or 0))
    local qroom = w - 32 - tw - 8 - right - 8
    if look.quest and qroom > 40 then put(st.quest, "LEFT", 32 + tw + 8, -1, qroom, look.quest, K.DIM, "LEFT", 11) else st.quest:Hide() end
    if count then put(st.count, "RIGHT", 0, 0, right, count, K.INK, "RIGHT", 13) else st.count:Hide() end
    st.fn = function(_, which)
      if not s1 then return end
      if which == "RightButton" then Q.Menu(s1)
      elseif IsControlKeyDown and IsControlKeyDown() then if Q.Arrow then Q.Arrow(s1) end
      elseif Q.Read then Q.Read(s1, UI) end
    end
    st.tip = function(tip)
      tip:AddLine(s1 and Q.Text(s1) or words, 1, 1, 1, true)
      if look.quest then tip:AddLine(look.quest, 0.8, 0.8, 0.8, true) end
      if s1 then tip:AddLine("Click: read its quest. Ctrl-click: show it on the arrow. Right-click: Not now, Drop.", 0.5, 0.5, 0.5, true) end
    end
    y = y + BAND_STEP + 1
    -- the step's progress in its category's colour (the quest gold), where it has a count
    if count and look.need > 0 then
      kit.track:ClearAllPoints(); kit.track:SetPoint("TOPLEFT", 0, -y); kit.track:SetWidth(w); kit.track:Show()
      local c = look.bar or K.QUEST
      kit.fill:SetColorTexture(c[1], c[2], c[3], 1)
      kit.fill:ClearAllPoints(); kit.fill:SetPoint("TOPLEFT", 0, -y)
      kit.fill:SetWidth(math.max(1, math.floor(w * math.min(1, look.have / look.need) + 0.5)))
      kit.fill:SetShown(look.have > 0)
    end
    y = y + 4
    for i = 2, 3 do
      local s = steps[i]
      local r = kit.next[i - 1]
      if s then
        local lk = Q.Look and Q.Look(s) or {}
        r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:SetWidth(w); r:Show()
        L.FillSlot(r.icon, lk.icon and { art = lk.icon.art, poi = lk.icon.poi, desat = lk.icon.desat } or nil)
        local t = lk.short or Q.Text(s)
        put(r.text, "LEFT", 32, 0, w - 40, t, K.DIM, "LEFT", 12)
        local full = Q.Text(s)
        r.tip = function(tip) tip:AddLine(full, 1, 1, 1, true) end
        y = y + BAND_NEXT
      end
    end
    -- (merge3) the step frame's line, where it has one now
    local rl = Q.Reminder and Q.Reminder() or nil
    if rl then
      local rr = kit.remind
      rr.rec = rl
      rr:ClearAllPoints(); rr:SetPoint("TOPLEFT", 0, -y); rr:SetWidth(w); rr:Show()
      L.FillSlot(rr.icon, { art = { rl.atlas, rl.tex or 134400, rl.tc }, desat = rl.desat == true })
      rr.bar:SetShown(rl.cat == "xp")
      local minsW = rl.mins and 60 or 0
      if rl.mins then put(rr.mins, "RIGHT", 0, 0, minsW, rl.word or "", K.INK, "RIGHT", 11) else rr.mins:Hide() end
      put(rr.text, "LEFT", 32, 0, w - 32 - minsW - 8, rl.text or rl.name or "", K.INK, "LEFT", 12)
      y = y + BAND_NEXT
    end
    -- the level: where you stand in it, the time to the next, over the XP bar (what the plan adds in green)
    local xp = Q.XP and Q.XP() or nil
    if xp then
      y = y + 4
      local ttl, _, measured = Q.TimeToLevel()
      local line = "Level " .. xp.level .. (xp.frac and (L.DOT .. math.floor(xp.frac * 100) .. "%") or "") .. (ttl and (L.DOT .. ttl) or "")
      kit.level:ClearAllPoints(); kit.level:SetPoint("TOPLEFT", 0, -y); kit.level:SetWidth(w); kit.level:Show()
      kit.level.text:SetWidth(w)
      UI.Color(kit.level.text, K.INK)
      fitText(kit.level.text, line, w - 4)
      kit.level.tip = function(tip)
        tip:AddLine(line, 1, 1, 1, true)
        if xp.planned and xp.planned > 0 then tip:AddLine(string.format("The planned quests add %s XP: the green on the bar.", xp.plannedText or tostring(xp.planned)), 0.8, 0.8, 0.8, true) end
        tip:AddLine(measured and "The time from your XP an hour at this level." or "The time from the plan's XP a minute.", 0.6, 0.6, 0.6, true)
      end
      y = y + 18
      if xp.from then
        kit.xp:ClearAllPoints(); kit.xp:SetPoint("TOPLEFT", 0, -y); kit.xp:Show()
        L.FillXP(kit.xp, w, xp.from, xp.to, xp.at, xp.gains)
        y = y + 6
      end
    end
  end
  y = y + 8
  kit.line:ClearAllPoints(); kit.line:SetPoint("TOPLEFT", 0, -y); kit.line:SetPoint("TOPRIGHT", 0, -y)
  kit:SetHeight(y + 1)
  UI:SetBand(y + 2)
  -- what the page shows of yours draws it again when it changes (UI:ValueChanged)
  UI.shownIds.level = true
  return y + 2
end

-- the pick's reason in one dim phrase, after the card's name: "3 mates online", "4 bosses left", "2 quests"
local function why(card)
  if #card.mates > 0 then return plural(#card.mates, "mate online", "mates online") end
  if card.left > 0 then return plural(card.left, "boss left", "bosses left") end
  if card.quests > 0 then return plural(card.quests, "quest", "quests") end
  if card.unexplored then return "not been in" end
  return nil
end
-- the Invite on the card: the mates it shows (four at most) not in your group and not invited this minute, each by the
-- name their own Cute speaks under (G.Invite: never in a fight, only where the client lets you invite)
local function invitable(card)
  local out = {}
  for i = 1, math.min(MATES, #card.mates) do
    local m = card.mates[i]
    if not m.grouped and m.invite and not invitedRecently(m) then out[#out + 1] = m end
  end
  return out
end
G.Invitable = invitable

-- The guild's pick, the Quests tab's Dungeon section (its right column, or under the questing at the narrow size): a
-- head ("Dungeon", the group's teal bar, the Dungeon atlas, "the guild's pick" on its right), then the picked dungeon as
-- a card (Look.lua's pattern C): its art, its name and the reason, its level range against yours, its bosses' faces
-- (killed, left, doubted) and how many are left, the quests for it, the best drop for you, the mates online in range and
-- Invite. Its tooltip holds the reasons, where the knowledge comes from, the dungeon's bosses and loot, its quests, every
-- mate in range, and for officers the guild's line and what it learned in play. A click opens the Dungeons tab on it.
-- With no pick, the pick's own sentence as one dim row. Into host from y, w wide; returns the height it took
function G.DrawPick(UI, host, y, w, narrow)
  local K, L = UI.COLORS, UI.Look
  local officer = C.Roster:MeOfficer()
  local items, plan = G.Items(officer)
  local first, detail = G.Source()
  local learned = plan.learned or {}
  local art = C.API.QuestArt
  host.pickHead = host.pickHead or L.MakeRow(host)
  local hd = host.pickHead
  hd:ClearAllPoints(); hd:SetPoint("TOPLEFT", 0, -y); hd:Show()
  local y0 = y
  y = y + L.FillRow(hd, { kind = "head", bar = K.GROUP, icon = { art = "dungeon" }, name = "Dungeon", who = "the guild's pick" }, w)
  local top = plan.next
  -- (where the knowledge comes from, research and builds, is the officers' and /cute diag's; a member reads what the
  -- card means: the guild's levels and bosses, or, while the seed is checked or once the game differs from it, that)
  local sourceTip = function(tip)
    tip:AddLine(" ")
    local st = C.Rules.SeedState()
    if officer then tip:AddLine(first, 1, 1, 1, true); tip:AddLine(detail, 0.7, 0.7, 0.7, true)
    else tip:AddLine((st == "stale" or st == "checking") and first or "Levels and bosses as the guild has met them.", 0.7, 0.7, 0.7, true) end
  end
  local guildTip = function(tip)
    if officer and plan.guild then
      tip:AddLine(" ")
      tip:AddLine(plan.guild.line, 1, 1, 1, true)
      if plan.guild.tip then plan.guild.tip(tip) end
    end
    if officer and #learned > 0 then
      tip:AddLine(" "); tip:AddLine("Learned in play", 1, 1, 1)
      for _, l in ipairs(learned) do tip:AddLine(l, 0.8, 0.8, 0.8, true) end
    end
  end
  local card = top.card
  host.pickCard = host.pickCard or L.MakeCard(host)
  host.pickNote = host.pickNote or L.MakeRow(host)
  local cw = host.pickCard
  if not card then
    cw:Hide()
    local nr = host.pickNote
    nr:ClearAllPoints(); nr:SetPoint("TOPLEFT", 0, -y); nr:Show()
    y = y + L.FillRow(nr, { kind = "note", x = 10, name = top.line, nameC = K.DIM, tip = function(tip)
      tip:AddLine(top.line, 1, 1, 1, true)
      if top.tip then tip:AddLine(" "); top.tip(tip) end
      sourceTip(tip)
      guildTip(tip)
    end }, w)
    host.pickShown = nil
    return y - y0
  end
  host.pickNote:Hide()
  local d = card.d
  local pips = pipsOf(d)
  local faces = {}
  for i, p in ipairs(pips) do
    local enc = bossesOf(d)[i]
    faces[i] = { state = p.state, name = p.name, paint = art and art.Face and function(t) art.Face(t, d, enc, p.name) end or nil }
  end
  local mates = {}
  for i = 1, math.min(MATES, #card.mates) do local m = card.mates[i]; mates[i] = { name = m.name, class = m.class } end
  local combat = G.InCombat()
  local can = canInvite()
  local list = invitable(card)
  local invite
  if #card.mates > 0 then
    local names = {}
    for _, m in ipairs(list) do names[#names + 1] = m.name end
    local whyNot = (combat and "Not in combat: invites wait until it ends.") or (not can and "Only your group's leader or an assistant can invite.")
      or (#list == 0 and "Invited, or in your group.") or nil
    invite = { on = not whyNot, label = (#list == 0 and not combat and can) and "Invited" or "Invite",
      why = whyNot or ("Invite " .. some(names, 4) .. " to your group."),
      fn = function()
        if G.InCombat() or not canInvite() then return end
        for _, m in ipairs(invitable(card)) do G.Invite(m) end
      end }
  end
  local data = {
    name = d.name .. (d.kind == "raid" and " (raid)" or ""), why = why(card), min = d.min, max = d.max, level = plan.level, raid = d.kind == "raid",
    cover = art and art.Cover and function(t, aw, ah) art.Cover(t, d, aw, ah) end or nil,
    faces = faces, left = (#pips > 0) and (card.left .. " left") or nil, quests = card.quests,
    drop = art and art.Drop and art.Drop(d) or nil, mates = mates, invite = invite,
    fn = art and art.OpenDungeon and function(_, which) if which ~= "RightButton" then art.OpenDungeon(d) end end or nil,
    tip = function(tip)
      tip:AddLine(top.line, 1, 1, 1, true)
      if top.tip then tip:AddLine(" "); top.tip(tip) end
      tip:AddLine(" ")
      dungeonTip(d)(tip)
      local rows = G.CardRows(card, plan)
      for _, it in ipairs(rows) do
        if it.kind == "quests" and it.tip then tip:AddLine(" "); it.tip(tip) end
      end
      if #card.mates > 0 then
        tip:AddLine(" ")
        tip:AddLine("Online in range", 1, 1, 1)
        for _, m in ipairs(card.mates) do
          local c = C.UI.ClassColor(m.class)
          tip:AddDoubleLine(m.name .. " " .. m.level, m.grouped and "in your group" or "", c[1], c[2], c[3], 0.6, 0.6, 0.6)
        end
      end
      sourceTip(tip)
      guildTip(tip)
      if art and art.OpenDungeon then tip:AddLine("Click: the Dungeons tab on it.", 0.45, 0.45, 0.45) end
    end,
  }
  cw:ClearAllPoints(); cw:SetPoint("TOPLEFT", 0, -y - 4); cw:Show()
  y = y + 4 + L.FillCard(cw, data, w, narrow) + 4
  host.pickShown = { card = card, plan = plan, invitable = list }
  return y - y0
end

-- the band and the pick in one list, for a host with no columns of its own (the harness's stand-in Quests tab for a
-- character without Cute_Quest): the band, then the pick under it in the scroll area. Returns the height and a no-op
-- for the scroll (nothing in it is virtual)
function G.Draw(UI, y0)
  G.DrawBand(UI)
  local host = UI:Host("guide")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0)
  local w = UI.scroll:Width()
  host:SetSize(w, 10)
  local h = G.DrawPick(UI, host, y0 or 0, w, false)
  host:SetHeight(math.max(10, (y0 or 0) + h))
  return (y0 or 0) + h, function() end
end

-- (the launch round's windows) the Guide is no page of its own any more: its band is the Quests tab's, its pick the
-- Quests tab's Dungeon rows (G.Draw), its two thresholds Settings > Rules' "Dungeons and gear". Its logic stays here, as
-- guild knowledge a module addon reads through the door below. A character that ran it keeps its old choice, unread
C.API.Guide = {
  DrawBand = function(ui) return G.DrawBand(ui) end,
  DrawPick = function(ui, host, y, w, narrow) return G.DrawPick(ui, host, y, w, narrow) end,
  Items = function(officer) return G.Items(officer) end,
  Pick = function(cards, level, soon, st) return G.Pick(cards, level, soon, st) end,
  CardRows = function(card, plan) return G.CardRows(card, plan) end,
  Draw = function(ui, top) return G.Draw(ui, top) end,
  Invite = function(mate) return G.Invite(mate) end,
}
