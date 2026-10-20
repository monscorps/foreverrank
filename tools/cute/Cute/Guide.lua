-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Guide: what should you do next, and with whom. What the rules (Rules.lua) make of the seed and the guild's play,
-- drawn around that one question:
--   band        the next best thing, one line, its reason in the tooltip: the rules' pick from the dungeons in range
--               at your level (guild mates online in range first, then what is left for you there: the bosses you have
--               not killed, the quests open to you, a dungeon you have not been in; then the one closing soonest), or
--               plainly that nothing fits. Officers get the guild's version: where most members are and the dungeon
--               that holds them. Under it, where the knowledge comes from, its detail in the tooltip
--   cards       one per dungeon in range: its name, a level bar with its range drawn against your level, how sure we
--               are in one word, the bosses as pips (killed, not killed, doubted), the quests known for it as they
--               stand for you, and the guild mates online in range, class-coloured, each with an Invite button
--               (C_PartyInfo.InviteUnit, out of combat only). Your next best one is marked
--   strips      gear (your Missing enchants, rule 5, a row a slot, what Forever has for each in its tooltip; under the
--               rules' enchant level, the slots the research has enchants for, as advice) and pace (hours to the next
--               level and to the cap, at your pace and at the guild's median), a row each, no paragraphs
--   Next up     a short timeline of the dungeons opening within guideAhead levels, the seed's awaited ones too
--   Officers    the dungeons the guild is in range of or has met, each with its members in range and how many of its
--               bosses the guild has killed (every boss in its tooltip); and what the guild's play changed from the
--               research: new dungeons and bosses, learned ranges, doubted entries, a stale seed
-- Where the seed is stale or none shipped, every section runs on the guild's play alone and its heading says so. The
-- page is one virtual list of rows of one height (the window's kind: UI:List), headings included, so a guild's thirty
-- dungeons and their members draw only the rows in view; the next best thing and the source stay in the band above.
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
local function hoursText(h) return h and C.Stats.FmtHours(h * 3600) or nil end

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

-- a dungeon's tooltip: its range and where it comes from, how sure, every boss with how sure and your kills, the loot
local function dungeonTip(d, extra)
  local R = C.Rules
  local m = R.Model()
  local bosses = bossesOf(d)
  return function(tip)
    tip:AddLine(d.name, 1, 1, 1)
    local range, from = R.RangeWords(d)
    tip:AddDoubleLine("Levels " .. range, from, 0.8, 0.8, 0.8, 0.7, 0.7, 0.7)
    tip:AddLine((d.kind == "raid" and "A raid" or "A dungeon") .. (d.new and " new in Forever, " or ", ") .. R.Words(d) .. ".", 0.7, 0.7, 0.7, true)
    if d.seedName then tip:AddLine("The research calls it " .. d.seedName .. ".", 0.6, 0.6, 0.6, true) end
    if d.awaited then tip:AddLine("Not placed yet: two members entering it, or a kill there a group mate names back, give it its place, and the guild's kills name its bosses.", 0.6, 0.6, 0.6, true) end
    for _, enc in ipairs(bosses) do
      local b = m.bosses[enc]
      local mine = killedIt(enc) and "you killed it" or "not by you"
      local st = R.Words(b)
      local dim = b.state == "doubted" and 0.45 or 0.75
      tip:AddDoubleLine(b.name, st .. "; " .. mine, 0.85, 0.85, 0.85, dim, dim, dim)
      if b.seedName then tip:AddLine("   The research calls it " .. b.seedName .. ".", 0.6, 0.6, 0.6, true) end
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
  if C.UI and C.UI.frame and C.UI.frame:IsShown() then C.UI:Refresh() end
  return true
end
local function invitedRecently(mate)
  local t = G.invited[mate.guid or mate.invite or ""]
  return t ~= nil and C.Now() - t < INVITED
end

-- the median of the members' XP an hour that this viewer may see, and how many it is over
local function guildPace(rows, officer)
  local list = {}
  for _, r in ipairs(rows) do
    local v = r.addon and r.stats.xp_hour
    if type(v) == "number" and v > 0 and C.Policy:CanSee(officer, r.me, "xp_hour") then list[#list + 1] = v end
  end
  if #list == 0 then return nil, 0 end
  table.sort(list)
  local n = #list
  local med = n % 2 == 1 and list[(n + 1) / 2] or (list[n / 2] + list[n / 2 + 1]) / 2
  return med, n
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
--   head     a heading: name, and who on the right
--   card     a dungeon in range: name, its range (val) by a level bar (d), how sure in one word (who); pick marks the
--            next best one
--   bosses   its bosses as pips ({ name, state = killed | left | doubted }), who how many are left
--   quests   its quests open to you by name, who how many
--   mate     a guild mate online in range: name in the class's colour, level (val), an Invite button (mate)
--   more     "and N more online in range", a click shows them (fn)
--   strip    a compact row with a label: Gear, Pace
--   time     Next up: the level it opens at (at), the rail and a dot, then like a card's head
--   item     an officer's line: name, val, who (a dungeon's with its bar)
--   note     a line of text, its whole text in the tooltip; gap: a blank row
-- and the plan beside them: the cards, the next best thing, the guild's version (officers), the bars' level scale
function G.Items(officer)
  local R, S = C.Rules, C.Stats
  local K = C.UI.COLORS
  local items = {}
  -- (a note's tooltip holds its whole text, which a narrow window cuts)
  local function add(it)
    if it.kind == "note" and not it.tip then local text = it.name; it.tip = function(tip) tip:AddLine(text, 1, 1, 1, true) end end
    items[#items + 1] = it
    return it
  end
  local st = R.SeedState()
  local alone = (st == "stale" or st == "none") and "from the guild's play alone" or nil
  local rows = C.Roster:Rows()
  local level = C.Sample.values.level or C.Num("UnitLevel", "player") or 1
  local w, ahead = R.Get("guideWindow"), R.Get("guideAhead")
  local cap = R.Cap()
  local m = R.Model()
  local side, group = mySide(), groupGuids()
  local plan = { level = level, cards = {} }
  -- the bars share one scale across the page: every dungeon drawn, and your level
  local lo, hi = level, level
  local function scale(d) if d and d.min then lo = math.min(lo, d.min); hi = math.max(hi, d.max) end end

  -- in range: a card each
  local now, soon = R.DungeonsFor(level)
  plan.soon = soon
  add({ kind = "head", name = "In range at level " .. level, who = alone or (#now > 0 and plural(#now, "dungeon", "dungeons") or "") })
  if st == "checking" then add({ kind = "note", name = G.Checking() }) end
  for _, d in ipairs(now) do
    scale(d)
    local card = { d = d, pips = {}, left = 0, doubted = 0 }
    for _, enc in ipairs(bossesOf(d)) do
      local b = m.bosses[enc]
      local state = killedIt(enc) and "killed" or (b.state == "doubted" and "doubted" or "left")
      if state == "left" then card.left = card.left + 1 elseif state == "doubted" then card.doubted = card.doubted + 1 end
      card.pips[#card.pips + 1] = { name = b.name, state = state }
    end
    card.qlist, card.qn = questsFor(d, level, side)
    card.quests = card.qn.open + card.qn.log
    card.mates = matesFor(d, rows, level, w, officer, group)
    card.unexplored = #card.pips == 0 and not beenIn(d)
    plan.cards[#plan.cards + 1] = card
  end
  plan.next = G.Pick(plan.cards, level, soon, st)
  if officer then plan.guild = G.GuildPick(rows) end
  for _, card in ipairs(plan.cards) do
    local d = card.d
    local pick = plan.next.card == card
    add({ kind = "card", name = d.name .. (d.kind == "raid" and " (raid)" or ""), val = R.RangeWords(d), who = G.Word(d), d = d, pick = pick,
      tip = dungeonTip(d, pick and function(tip) tip:AddLine("Your next best thing: " .. plan.next.line, 0.9, 0.9, 0.9, true) end or nil) })
    -- the bosses: a pip each, how many are left
    local who
    if #card.pips == 0 then who = nil
    elseif card.left > 0 then who = card.left .. " left" .. (card.doubted > 0 and (", " .. card.doubted .. " doubted") or "")
    elseif card.doubted > 0 then who = "every one killed but the doubted"
    else who = "every one killed" end
    add({ kind = "bosses", label = "Bosses", pips = card.pips, who = who, d = d, tip = dungeonTip(d), c = #card.pips == 0 and K.MUTE or nil,
      name = #card.pips == 0 and (d.awaited and "None known: the guild has not placed it yet." or "None known yet: the guild's kills name them.") or nil })
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
      add({ kind = "more", name = "and " .. (#card.mates - shown) .. " more online in range", c = K.DIM, fn = function() G.open[key] = true; C.UI:Draw() end,
        tip = function(tip)
          tip:AddLine("Online in range", 1, 1, 1)
          for _, n in ipairs(rest) do tip:AddLine(n, 0.8, 0.8, 0.8) end
          tip:AddLine("Click to show them all.", 0.45, 0.45, 0.45)
        end })
    elseif G.open[key] and #card.mates > MATES + 1 then
      add({ kind = "more", name = "Show fewer", c = K.DIM, fn = function() G.open[key] = nil; C.UI:Draw() end })
    end
  end
  if #now == 0 and st ~= "checking" then add({ kind = "note", name = "No dungeon known for level " .. level .. " yet. The guild's entries and kills fill this in." }) end

  -- gear: Missing enchants, a row a slot, what Forever has for the slot and kind in the tooltip; under the enchant
  -- level, the slots the research has enchants for, as advice (they count as missing from that level, rule 5)
  add({ kind = "gap" })
  local missing = C.Sample:Value("unenchanted")
  local g = S.Gear and S.Gear() or nil
  local from = R.Get("enchantDoubtLevel")
  local label = "Gear"
  local function strip(it) it.kind, it.label = "strip", label; label = nil; return add(it) end
  -- what Forever has for a worn item: the names of the enchants that take its kind, or, where the research does not
  -- say which of a hand slot's enchants take it, how many it has for the slot
  local function forever(slot, kind)
    local list, unplaced = R.SlotEnchants(slot, kind)
    local names = {}
    for _, x in ipairs(list) do if x.state ~= "absent" then names[#names + 1] = x.name end end
    local line
    if #names > 0 then line = "Forever has: " .. some(names, 3)
    elseif unplaced > 0 then line = "Forever has " .. plural(unplaced, "enchant", "enchants") .. " for this slot; which take " .. S.KindName(kind) .. " is not in the research" end
    return line, list, unplaced
  end
  local function slotTip(slot, name, kind, head)
    local line, list, unplaced = forever(slot, kind)
    return function(tip)
      tip:AddLine(name, 1, 1, 1)
      tip:AddLine(head, 0.7, 0.7, 0.7, true)
      if line and R.SeedUsable() then tip:AddLine(line, 0.8, 0.8, 0.8, true) end
      for _, x in ipairs(list) do
        local word = x.state == "seen" and ("seen on " .. plural(x.n, "member", "members")) or R.Words({ state = x.state })
        tip:AddDoubleLine(x.name, word, 0.85, 0.85, 0.85, 0.7, 0.7, 0.7)
      end
      if unplaced > 0 then tip:AddLine(plural(unplaced, "more enchant", "more enchants") .. " for this slot, for kinds of item the research does not name.", 0.6, 0.6, 0.6, true) end
    end
  end
  if type(missing) ~= "table" then
    local err = C.Sample:Error("unenchanted")
    strip({ name = err and ("Could not read your enchants: " .. err) or "Your enchants have not been read yet.", c = K.MUTE })
  else
    local any, advice = false, {}
    for _, slot in ipairs(S.GEAR) do
      local worn = g and g.slot[slot]
      local kind = worn and worn.kind or nil
      local name = (S.SLOT[slot] or ("Slot " .. slot)) .. (kind and (" (" .. S.KindName(kind) .. ")") or "")
      if missing[slot] then
        any = true
        strip({ name = name, val = "missing", who = S.EnchantSource(slot, kind), c = K.WARN,
          tip = slotTip(slot, name, kind, "Not enchanted. The guild's word: " .. S.EnchantSource(slot, kind) .. ".") })
      elseif level < from and worn and worn.link and (worn.enchant or 0) == 0 and kind and R.SeedEnchantable(slot, kind) then
        advice[#advice + 1] = { slot = slot, label = name, kind = kind }
      end
    end
    if not any then
      -- (where no slot is known to take an enchant at all, neither by the guild nor by research it can use, that is
      -- what the line says: "every worn item has one" would claim what nobody knows)
      local known = false
      for _, slot in ipairs(S.GEAR) do if S.EnchantLearned(slot) or R.SeedEnchantable(slot) then known = true; break end end
      local note = "Every worn item that takes an enchant has one."
      if not known then note = "No enchant slots known yet: they are learned as the guild enchants."
      elseif #advice > 0 then note = "Nothing missing: under level " .. from .. " only what the guild has enchanted counts." end
      strip({ name = note, c = K.MUTE, tip = function(tip) tip:AddLine(note, 1, 1, 1, true) end })
    end
    if #advice > 0 then
      local names, beta, data = {}, false, false
      for _, a in ipairs(advice) do
        names[#names + 1] = S.SLOT[a.slot]
        if R.SeedSlotState(a.slot) == "beta" then beta = true else data = true end
      end
      local source = (beta and data) and "from research and the beta" or (beta and "seen in the beta" or "from research")
      strip({ name = "Could take one: " .. some(names, 3), val = "level " .. from .. "+", who = source, c = K.DIM, tip = function(tip)
        tip:AddLine("Forever has enchants for these", 1, 1, 1)
        tip:AddLine("They count as missing from level " .. from .. ", the rules' enchant level; until then only what the guild has enchanted does.", 0.7, 0.7, 0.7, true)
        for _, a in ipairs(advice) do
          local line = forever(a.slot, a.kind)
          tip:AddDoubleLine(a.label, line and line:gsub("^Forever has:? ", "") or "", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6)
        end
      end })
    end
  end
  -- pace: a row to the next level and one to the cap, at your pace and at the guild's median
  label = "Pace"
  local rate = C.Sample.values.xp_hour
  local med, n = guildPace(rows, officer)
  local xp, max = C.Num("UnitXP", "player"), C.Num("UnitXPMax", "player")
  if level >= cap then
    strip({ name = "At the cap, level " .. cap .. ".", c = K.INK })
  elseif xp and max then
    local function at(left, r) return (left and r and r > 0) and hoursText(left / r) or nil end
    local nextLeft = math.max(0, max - xp)
    local capLeft = R.XPLeft(level, xp, max, cap)
    local mine = type(rate) == "number" and rate > 0 and rate or nil
    local function pace(name, left, why)
      local yours = at(left, mine) or (left and "no pace yet" or "not known")
      local theirs = at(left, med)
      strip({ name = name, val = yours, who = theirs and (theirs .. " at the median of " .. plural(n, "member", "members")) or (left and "no median yet" or ""),
        c = K.INK, tip = function(tip)
          tip:AddLine(name, 1, 1, 1)
          if left then tip:AddLine(string.format("%d XP to go.", math.floor(left)), 0.8, 0.8, 0.8) else tip:AddLine(why, 0.8, 0.8, 0.8, true) end
          tip:AddLine(mine and string.format("Your pace: %d XP an hour, over the last hour of play.", mine) or "Your pace shows after a few minutes of play.", 0.6, 0.6, 0.6, true)
          if med then tip:AddLine(string.format("The guild's median: %d XP an hour, over %s.", math.floor(med), plural(n, "member", "members")), 0.6, 0.6, 0.6, true) end
        end })
    end
    pace("Level " .. (level + 1), nextLeft)
    pace("The cap, level " .. cap, capLeft, "The XP each level takes is not known that far yet: the guild's levels fill it in.")
  else
    strip({ name = "Your XP does not read on this client.", c = K.MUTE })
  end

  -- next up: a short timeline of the dungeons opening in the next levels, the seed's awaited ones among them
  add({ kind = "gap" })
  add({ kind = "head", name = "Next up", who = alone or ("opening in the next " .. plural(ahead, "level", "levels")) })
  for i, d in ipairs(soon) do
    scale(d)
    add({ kind = "time", at = d.min, first = i == 1, last = i == #soon, name = d.name .. (d.kind == "raid" and " (raid)" or ""), val = R.RangeWords(d), who = G.Word(d), d = d,
      tip = dungeonTip(d, function(tip) tip:AddLine("Opens at level " .. d.min .. ", " .. plural(d.min - level, "level", "levels") .. " from yours.", 0.8, 0.8, 0.8, true) end) })
  end
  if #soon == 0 and st ~= "checking" then add({ kind = "note", name = "Nothing known to open in the next " .. plural(ahead, "level", "levels") .. "." }) end

  -- the officers' view: the dungeons the guild is in range of or has met, and what the guild's play changed from the
  -- research. A dungeon's line folds its bosses into a count, one count per fact (the members seen killing each, kept
  -- as members leave); every boss is in its tooltip
  if officer and m then
    add({ kind = "gap" })
    add({ kind = "head", name = "The guild, per dungeon", who = alone or "members in range, bosses the guild has killed" })
    local list, rest = {}, 0
    for _, d in ipairs(R.EachDungeon()) do
      if d.state ~= "stale" then
        local inRange, killed = 0, 0
        local bosses = bossesOf(d)
        if d.min then for _, r in ipairs(rows) do if r.addon and type(r.level) == "number" and r.level >= d.min and r.level <= d.max then inRange = inRange + 1 end end end
        for _, enc in ipairs(bosses) do if (m.bosses[enc].n or 0) > 0 then killed = killed + 1 end end
        if inRange > 0 or killed > 0 or (d.n or 0) > 0 then list[#list + 1] = { d = d, inRange = inRange, killed = killed, bosses = #bosses } else rest = rest + 1 end
      end
    end
    table.sort(list, function(a, b)
      a, b = a.d, b.d
      if (a.min ~= nil) ~= (b.min ~= nil) then return a.min ~= nil end
      if a.min and a.min ~= b.min then return a.min < b.min end
      return a.name < b.name
    end)
    for _, e in ipairs(list) do
      local d = e.d
      scale(d)
      local bosses = e.bosses > 0 and (e.killed .. " of " .. plural(e.bosses, "boss", "bosses") .. " killed") or "no bosses known yet"
      add({ kind = "item", name = d.name .. (d.kind == "raid" and " (raid)" or ""), val = R.RangeWords(d), d = d,
        who = (d.min and (e.inRange .. " in range, ") or "") .. bosses, tip = dungeonTip(d) })
    end
    if #list == 0 then add({ kind = "note", name = "No dungeon the guild is in range of or has met yet." }) end
    if rest > 0 then add({ kind = "note", name = plural(rest, "more dungeon", "more dungeons") .. " from the research nobody is in range of or has met yet." }) end
    add({ kind = "gap" })
    -- (with no research to weigh it against, what the guild learned, not changes from research: R.Changes)
    local changes = R.Changes()
    add({ kind = "head", name = "Learned in play", who = alone or (#changes > 0 and plural(#changes, "change", "changes") .. " from the research" or "") })
    for _, ch in ipairs(changes) do
      add({ kind = "item", name = ch.what, who = ch.detail, c = ch.kind == "doubted" and K.MUTE or K.INK, tip = function(tip)
        tip:AddLine(ch.what, 1, 1, 1)
        tip:AddLine(ch.detail, 0.8, 0.8, 0.8, true)
        for _, name in ipairs(ch.names or {}) do tip:AddLine(name, 0.7, 0.7, 0.7) end
      end })
    end
    if #changes == 0 then add({ kind = "note", name = "Nothing yet: the guild's play has matched the research." }) end
  end
  plan.lo, plan.hi = lo - 1, hi + 2
  return items, plan
end

----------------------------------------------------------------------------
-- the page
----------------------------------------------------------------------------
-- the pips' and the level bar's colours, the page's mock the same (addons/cute/index.html). Each mark is 3:1 at least
-- on what it sits on: a pip on its row, hovered or not, and a range on the track (a doubted pip and a range below you
-- were 1.5:1, there and hardly seen). The track is the scale alone and stays faint; in range is the window's green
local PIP_COLOR = { killed = { 0.96, 0.96, 0.96 }, left = { 0.62, 0.62, 0.62 }, doubted = { 0.42, 0.42, 0.42 } }
local BAR_COLOR = { track = { 0.16, 0.16, 0.16 }, above = { 0.58, 0.58, 0.58 }, below = { 0.47, 0.47, 0.47 } }

-- a row of the Guide's list: the window's line (a background, the mark on the left, the name, a value and a right
-- column, the tooltip and the click) with the Guide's pieces added: a label column, the level bar (its track, the range
-- on it and your level), the pips, the timeline's rail and dot, and an Invite button. Each fill shows what its kind
-- uses and hides the rest
function G.MakeRow(parent)
  local UI = C.UI
  local K = UI.COLORS
  local r = UI:MakeLine(parent)
  r.label = UI.Text(r, 11, K.DIM, "LEFT")
  r.track = UI.Flat(r, "ARTWORK", BAR_COLOR.track, 1)
  r.track:SetHeight(4)
  r.seg = UI.Flat(r, "ARTWORK", K.GOOD, 1)
  r.seg:SetHeight(4)
  r.mark = UI.Flat(r, "OVERLAY", K.WHITE, 1)
  r.mark:SetSize(2, 12)
  r.rail = UI.Flat(r, "BORDER", K.MUTE, 1)
  r.rail:SetWidth(1)
  r.dot = UI.Flat(r, "ARTWORK", K.DIM, 1)
  r.dot:SetSize(7, 7)
  r.pips = {}
  r.invite = UI.Button(r, "Invite", 58, 16)
  r.invite:SetScript("OnClick", function(self) if self.mate then G.Invite(self.mate) end end)
  r.invite:SetScript("OnEnter", C.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.why then GameTooltip:AddLine(self.why, 1, 1, 1, true) end
    GameTooltip:Show()
  end, "tooltip"))
  r.invite:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- (what a fill hides first, kept once: the fill runs for every row in view on each draw and scroll step)
  r.pieces = { r.label, r.track, r.seg, r.mark, r.rail, r.dot, r.invite, r.val, r.who }
  return r
end
local PIP, PIP_GAP = 8, 3
-- the kinds that sit under a card's name, a label column before them
local UNDER = { bosses = true, quests = true, mate = true, more = true }

function C.Guide_Draw(UI)
  local sf = UI.scroll
  local K = UI.COLORS
  local color, fitText, ROW = UI.Color, UI.FitText, UI.ROW
  UI.header:Hide()
  UI.rows:Clear()
  UI.labels:Reset(); UI.labels:HideRest()
  local w = sf:Width()
  local officer = C.Roster:MeOfficer()
  local items, plan = G.Items(officer)
  -- the band: the step now from the quest module (Cute.QuestBand, Cute_Quest's Band.lua) big and white, the next two
  -- steps, the time to level, your party's steps; with the module off, one line saying where to switch it on
  local first, detail = G.Source()
  local y = 4
  local function bandRow(s, c, big, tip, fn)
    local l = UI.bandLines:Get()
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", 0, -y)
    local h = big and (ROW + 6) or ROW
    l:SetSize(w, h)
    l.bg:SetColorTexture(1, 1, 1, big and 0.05 or 0)
    l.bar:SetShown(big)
    l.bar:SetColorTexture(K.WHITE[1], K.WHITE[2], K.WHITE[3], 1)
    l.val:Hide(); l.who:Hide()
    l.fn, l.tip = fn, tip
    if big then
      UI.bandBig = UI.bandBig or UI.Text(UI.band, 15, K.WHITE)
      UI.bandBig:ClearAllPoints(); UI.bandBig:SetPoint("LEFT", l, "LEFT", 8, 0); UI.bandBig:SetWidth(w - 16)
      fitText(UI.bandBig, s, w - 20)
      UI.bandBig:Show()
      l.name:Hide()
    else
      l.name:ClearAllPoints(); l.name:SetPoint("LEFT", 8, 0); l.name:SetWidth(w - 16); l.name:SetJustifyH("LEFT")
      color(l.name, c)
      fitText(l.name, s, w - 20)
      l.name:Show()
    end
    y = y + h
    return l
  end
  if UI.bandBig then UI.bandBig:Hide() end
  local Q = Cute.QuestBand
  local qm = C.Modules.byId.quests
  local on = qm ~= nil and qm.active
  if on and Q and Q.On() then
    local steps = Q.Steps()
    local s1 = steps[1]
    local text1 = s1 and Q.Text(s1) or "Nothing to do yet: Quests says why."
    bandRow(text1, K.WHITE, true, function(tip) tip:AddLine(text1, 1, 1, 1, true); tip:AddLine("Click: the Quests page. Right-click: not now, drop, lock, scale, hide.", 0.5, 0.5, 0.5, true) end,
      function(_, which) if which == "RightButton" and s1 then Q.Menu(s1) else Q.Open() end end)
    for i = 2, 3 do
      local s = steps[i]
      if s then local t = Q.Text(s); bandRow(t, K.DIM, false, function(tip) tip:AddLine(t, 1, 1, 1, true) end) end
    end
    local ttl, _, measured = Q.TimeToLevel()
    if ttl then bandRow(ttl, K.MUTE, false, function(tip) tip:AddLine(measured and "From your XP an hour at this level." or "From the plan's XP a minute.", 1, 1, 1, true) end) end
    for _, m in ipairs(Q.Members()) do bandRow(m.name .. ": " .. m.text, UI.ClassColor(m.class)) end
  elseif on then
    -- (ticked, no step yet: the module says why, reading the log or a QuestBank too old for it)
    local why = (Q and Q.Why and Q.Why()) or "Reading your quest log."
    bandRow(why, K.DIM, false, function(tip) tip:AddLine(why, 1, 1, 1, true) end)
  else
    bandRow("Tick Quests in Settings, Modules for the step now.", K.DIM, false,
      function(tip) tip:AddLine("The quest engine's step frame, in this band: what to do now, the next two steps, the time to level, your party's steps.", 1, 1, 1, true) end,
      function() C.UI:Open("settings", "modules") end)
  end
  UI:SetBand(y + 4)
  -- what the page shows of yours draws it again when it changes (UI:ValueChanged)
  UI.shownIds.level = true
  local level = plan.level
  local combat = G.InCombat()
  local invites = true
  local can = type(C_PartyInfo) == "table" and C_PartyInfo.CanInvite or nil
  if type(can) == "function" and C.Get(can) == false then invites = false end
  -- the columns from the right: how sure (a card's word) or a count; the level bar beside it; the range left of the bar
  local ww = math.min(260, math.floor(w * 0.34)) -- an officer's line's and a strip's right column
  local vw = 90                                  -- a strip's value
  local word = 74                                -- a card's word
  local count = 150                              -- a card part's count
  local bw = math.max(90, math.min(180, math.floor(w * 0.18)))
  local lo, hi = plan.lo, plan.hi
  local function xOf(l, x0) return x0 + math.floor((l - lo) / math.max(1, hi - lo) * bw + 0.5) end
  -- the level bar of a dungeon, its right edge `right` from the row's: the range on the track, green where your level is
  -- in it, grey where it is above you, dim where it is below; your level a white tick. Returns the bar's left edge
  local function levelBar(r, d, right)
    local x0 = w - right - bw
    r.track:ClearAllPoints(); r.track:SetPoint("LEFT", x0, 0); r.track:SetWidth(bw); r.track:Show()
    if d.min then
      local a, b = xOf(d.min, x0), xOf(d.max + 1, x0)
      local c = (level >= d.min and level <= d.max) and K.GOOD or (d.min > level and BAR_COLOR.above or BAR_COLOR.below)
      r.seg:ClearAllPoints(); r.seg:SetPoint("LEFT", a, 0); r.seg:SetWidth(math.max(2, b - a)); r.seg:SetColorTexture(c[1], c[2], c[3], 1); r.seg:Show()
    end
    r.mark:ClearAllPoints(); r.mark:SetPoint("LEFT", xOf(level + 0.5, x0) - 1, 0); r.mark:Show()
    return x0
  end
  local function put(fs, point, x, width, s, c, justify)
    fs:ClearAllPoints()
    fs:SetPoint(point, x, 0)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    color(fs, c)
    fitText(fs, s, width - 4)
    fs:Show()
  end
  -- the page: the pick's line as its head (the officer's guild line at its right), then the picked dungeon's rows
  -- alone; everything else G.Items gathers (the other cards, the strips, Next up, the officers' lines) lives in the
  -- head's tooltip where the spec keeps it (the reasons, the source, the learned lines) or nowhere
  local top = plan.next
  local learned, inLearned = {}, false
  for _, it in ipairs(items) do
    if it.kind == "head" then inLearned = (it.name or ""):find("^Learned") ~= nil
    elseif inLearned and (it.kind == "item" or it.kind == "note") then learned[#learned + 1] = (it.name or "") .. (it.who and (": " .. it.who) or "") end
  end
  -- the officer's guild line at the head's right where the right column holds it whole; else on a line of its own under
  -- the head, so nothing on the page is cut (its counts stay in the head's tooltip either way)
  local guildLine = officer and plan.guild and plan.guild.line or nil
  local guildRow
  if guildLine then
    UI.measure = UI.measure or UI.Text(UI.band, 12, K.DIM, "RIGHT")
    UI.measure:Hide()
    UI.measure:SetText(guildLine)
    local width = UI.measure.GetUnboundedStringWidth or UI.measure.GetStringWidth
    if width(UI.measure) > ww - 4 then
      local guild = plan.guild
      guildRow = { kind = "note", name = guildLine, c = K.DIM, tip = function(tip) tip:AddLine(guildLine, 1, 1, 1, true); if guild.tip then guild.tip(tip) end end }
      guildLine = nil
    end
  end
  local shown = { { kind = "head", name = top.line, who = guildLine, tip = function(tip)
    if top.tip then top.tip(tip) end
    tip:AddLine(" ")
    tip:AddLine(first, 1, 1, 1, true); tip:AddLine(detail, 0.7, 0.7, 0.7, true)
    -- (the guild's line and its counts, whole)
    if officer and plan.guild and plan.guild.tip then tip:AddLine(" "); tip:AddLine(plan.guild.line, 1, 1, 1, true); plan.guild.tip(tip) end
    if officer and #learned > 0 then
      tip:AddLine(" "); tip:AddLine("Learned in play", 1, 1, 1)
      for _, l in ipairs(learned) do tip:AddLine(l, 0.8, 0.8, 0.8, true) end
    end
  end } }
  if guildRow then shown[#shown + 1] = guildRow end
  local take = false
  for _, it in ipairs(items) do
    if it.kind == "card" then take = it.pick == true
    elseif it.kind == "gap" or it.kind == "head" then take = false end
    if take then shown[#shown + 1] = it end
  end
  local list = UI:List("guide", G.MakeRow)
  list:Set(#shown, 0, ROW, function(r, i, ly)
    local it = shown[i]
    local kind = it.kind
    r:SetHeight(ROW)
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.bg:SetColorTexture(1, 1, 1, (kind == "head" and 0.06) or ((kind == "card" or kind == "time") and 0.035) or ((kind == "item" or kind == "strip") and 0.025) or 0)
    r.bar:SetShown(kind == "card" and it.pick == true)
    r.bar:SetColorTexture(K.WHITE[1], K.WHITE[2], K.WHITE[3], 1)
    for _, piece in ipairs(r.pieces) do piece:Hide() end
    for _, p in ipairs(r.pips) do p:Hide() end
    r.fn, r.tip = it.fn, it.tip
    r.invite.mate = nil
    -- the left: the name's edge after a label column (a card's parts under its name, a strip at the left edge) or the
    -- timeline's level, rail and dot
    local x = 8
    if UNDER[kind] then put(r.label, "LEFT", 24, 50, it.label or "", K.DIM, "LEFT"); x = 78
    elseif kind == "strip" then put(r.label, "LEFT", 8, 50, it.label or "", K.DIM, "LEFT"); x = 62
    elseif kind == "time" then
      put(r.label, "LEFT", 4, 30, tostring(it.at), K.INK, "RIGHT")
      r.rail:ClearAllPoints()
      r.rail:SetPoint("TOP", r, "TOPLEFT", 44, it.first and -ROW / 2 or 0)
      r.rail:SetPoint("BOTTOM", r, "BOTTOMLEFT", 44, it.last and ROW / 2 or 0)
      r.rail:SetShown(not (it.first and it.last))
      local dc = it.d.state == "seen" and K.WHITE or K.DIM
      r.dot:ClearAllPoints(); r.dot:SetPoint("CENTER", r, "LEFT", 44, 0); r.dot:SetColorTexture(dc[1], dc[2], dc[3], 1); r.dot:Show()
      x = 56
    end
    -- the right, from the row's edge in: the right column, then a dungeon's bar and range, or a strip's value, or a
    -- mate's Invite button and level
    local right = 4
    local hasWho = it.who ~= nil and it.who ~= ""
    if kind == "card" or kind == "time" then
      if hasWho then put(r.who, "RIGHT", -4, word, it.who, it.wc or K.DIM, "RIGHT") end
      right = 4 + word + 8
    elseif kind == "bosses" or kind == "quests" or kind == "more" then
      if hasWho then put(r.who, "RIGHT", -4, count, it.who, it.wc or K.DIM, "RIGHT") end
      right = 4 + count + 8
    elseif kind == "mate" and it.mate then
      -- a mate's name, level and Invite button side by side (or "in your group" where the button would be)
      local mt = it.mate
      local nameW = math.max(60, math.min(170, w - x - 190))
      put(r.val, "LEFT", x + nameW + 4, 30, it.val, K.DIM, "LEFT")
      local bx = x + nameW + 40
      if mt.grouped then
        put(r.who, "LEFT", bx, 110, it.who, K.DIM, "LEFT")
      else
        -- greyed in combat, where you cannot invite, where no name reaches them, and for a minute after an invite
        local b = r.invite
        local recent = invitedRecently(mt)
        b:ClearAllPoints(); b:SetPoint("LEFT", bx, 0)
        b:SetLabel(recent and "Invited" or "Invite")
        b:SetOn(not combat and invites and mt.invite ~= nil and not recent)
        b.mate = mt
        b.why = (combat and "Not in combat: invites wait until it ends.") or (not invites and "Only your group's leader or an assistant can invite.")
          or (mt.invite == nil and "The game encodes this name: invite them from the guild roster.") or (recent and "Invited.") or ("Invite " .. mt.name .. " to your group.")
        b:Show()
      end
      right = w - x - nameW
    elseif kind == "item" or kind == "strip" then
      if it.d then
        if hasWho then put(r.who, "RIGHT", -4, ww, it.who, it.wc or K.DIM, "RIGHT") end
        right = 4 + ww + 8
      else
        if hasWho then put(r.who, "RIGHT", -4, it.val and ww or (ww + vw + 4), it.who, it.wc or K.DIM, "RIGHT") end
        if it.val then put(r.val, "RIGHT", -(ww + 8), vw, it.val, K.INK, "RIGHT"); right = ww + 8 + vw + 4
        elseif hasWho then right = 4 + ww + vw + 8 end
      end
    elseif hasWho then
      put(r.who, "RIGHT", -4, ww, it.who, it.wc or K.DIM, "RIGHT")
      right = 4 + ww + 4
    end
    if it.d and (kind == "card" or kind == "time" or kind == "item") then
      local x0 = levelBar(r, it.d, right)
      r.val:ClearAllPoints(); r.val:SetPoint("RIGHT", r, "LEFT", x0 - 6, 0); r.val:SetWidth(44); r.val:SetJustifyH("RIGHT")
      color(r.val, K.INK)
      fitText(r.val, it.val, 42)
      r.val:Show()
      right = w - x0 + 6 + 44 + 6
    end
    -- the pips, one a boss, as many as the row holds
    if kind == "bosses" and it.pips and #it.pips > 0 then
      local fit = math.max(1, math.floor((w - x - right + PIP_GAP) / (PIP + PIP_GAP)))
      for k = 1, math.min(#it.pips, fit) do
        local p = r.pips[k]
        if not p then p = UI.Flat(r, "ARTWORK", K.DIM, 1); p:SetSize(PIP, PIP); r.pips[k] = p end
        local pc = PIP_COLOR[it.pips[k].state] or PIP_COLOR.left
        p:SetColorTexture(pc[1], pc[2], pc[3], 1)
        p:ClearAllPoints(); p:SetPoint("LEFT", x + (k - 1) * (PIP + PIP_GAP), 0)
        p:Show()
      end
    end
    -- the name, in the room left between the two
    local room = w - x - right
    if it.name and it.name ~= "" and room > 16 then
      put(r.name, "LEFT", x, room, it.name, it.c or ((kind == "head" or kind == "card") and K.WHITE or (kind == "note" and K.MUTE or K.INK)), "LEFT")
    else
      r.name:SetText("")
    end
  end)
  UI.virtual = function() list:Show(UI.scroll.bar:GetValue() or 0, UI.scroll:View()) end
  sf:SetContentHeight(#shown * ROW + 8)
end

-- a built-in module, off until it is switched on in Settings > Modules (a character that ran 0.5.x, where it was a fixed
-- tab, too). Its section holds the two thresholds only it reads, the officers' to set. While it
-- is on, combat and your group draw the open page again (its Invite buttons follow them), and so do your quests
local function redraw() if C.UI and C.UI.page == "guide" and C.UI.frame and C.UI.frame:IsShown() then C.UI:Refresh() end end
C:RegisterModule({
  id = "guide", title = "Guide", order = 20, builtin = true, default = false, tab = 64,
  notes = "The step now from Quests, then the one dungeon to run: its bosses, quests and guild mates to invite; officers see the guild per dungeon in its tooltip.",
  page = function(ui) C.Guide_Draw(ui) end,
  settings = function(_, col)
    col:Head("Levels")
    col:Note(C.Roster:MeOfficer() and "White: set by an officer. A change goes to the guild on its own." or "White: set by an officer. Only officers can change them.")
    col:Rule("guideWindow", "Members near your level")
    col:Rule("guideAhead", "Dungeons ahead")
    col:Broadcast()
    -- (the quest module on: the engine's step frame and arrow, its rows)
    local Q, qm = Cute.QuestBand, C.Modules.byId.quests
    if qm and qm.active and Q and Q.Settings then Q.Settings(col) end
  end,
  events = { PLAYER_REGEN_DISABLED = redraw, PLAYER_REGEN_ENABLED = redraw, GROUP_ROSTER_UPDATE = redraw, QUEST_TURNED_IN = redraw, QUEST_ACCEPTED = redraw },
})
