-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Guide: what the rules (Rules.lua) make of the seed and the guild's play, for you and, for officers, the guild.
--   band        where the knowledge comes from: research checked against this client, research this game no longer
--               matches, or none shipped
--   For you     the guild members online within guideWindow levels of yours who run the addon (a group to ask), and
--               the dungeons whose range holds your level, each with the bosses you have not killed and how sure
--               Cute is of it in words
--   Next up     the dungeons opening within guideAhead levels
--   Gear        your Missing enchants (rule 5), each with the enchants Forever has for that slot and kind of item;
--               under the rules' enchant level, the slots the research has enchants for, as advice
--   Pace        hours to the next level and to the cap, at your pace and at the guild's median
--   Officers    the dungeons the guild is in range of or has met, each with its members in range and how many of its
--               bosses the guild has killed (every boss in its tooltip); and what the guild's play changed from the
--               research: new dungeons and bosses, learned ranges, doubted entries, a stale seed
-- Where the seed is stale or none shipped, every section runs on the guild's play alone and its heading says so. The
-- page is one virtual list of lines (the Statistics page's: UI.lines), headings included, so a guild's thirty dungeons
-- and their bosses draw only the lines in view; where the knowledge comes from stays in the band above them.
local _, C = ...
local G = {}
C.Guide = G

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

-- where the knowledge comes from, as the band says it: a line, and a dim one under it
function G.Source()
  local R = C.Rules
  local st, why = R.SeedState()
  local s = R.Seed()
  if st == "none" then return "Nothing shipped with this copy: everything here is learned from the guild's play.", "Dungeons, ranges, enchants and the XP curve fill in as members meet them." end
  if st == "checking" then return "Checking what we knew against this client.", "The Guide fills in when it is done." end
  if st == "stale" then return "The game differs from what we knew; learning from the guild.", "The research: " .. (why or "") .. "." end
  local chk = R.check or {}
  local detail = "Research build " .. (s.build or "?") .. (s.generated and (", " .. s.generated) or "") .. "."
  if R.BetaAsData() then detail = detail .. " This client is " .. chk.client .. ": what the beta showed counts as research until the guild sees it." end
  return "From research and the beta, checked against this client, and what the guild has met since.", detail
end

-- your kills of a boss
local function killedIt(enc) local v = C.Char().counters["e" .. enc]; return type(v) == "number" and v > 0 end

-- a dungeon's bosses as the Guide names and counts them: a stale seed's that nobody has met are left out, research this
-- game no longer matches being neither left to kill nor counted (the first 0.5.0 build, once the guild had killed the
-- Deadmines' first boss on a stale seed, listed the research's other three as left and counted "1 of 4")
local function bossesOf(d)
  local m = C.Rules.Model()
  local out = {}
  for _, enc in ipairs(d.bosses) do
    local b = m.bosses[enc]
    if b and b.state ~= "stale" then out[#out + 1] = enc end
  end
  return out
end

-- a dungeon's tooltip: its range and where it comes from, how sure, every boss with how sure and your kills, the loot
local function dungeonTip(d)
  local R = C.Rules
  local m = R.Model()
  local bosses = bossesOf(d)
  return function(tip)
    tip:AddLine(d.name, 1, 1, 1)
    local range, from = R.RangeWords(d)
    tip:AddDoubleLine("Levels " .. range, from, 0.8, 0.8, 0.8, 0.7, 0.7, 0.7)
    tip:AddLine((d.kind == "raid" and "A raid" or "A dungeon") .. (d.new and " new in Forever, " or ", ") .. R.Words(d) .. ".", 0.7, 0.7, 0.7, true)
    if d.seedName then tip:AddLine("The research calls it " .. d.seedName .. ".", 0.6, 0.6, 0.6, true) end
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
    if #bosses == 0 then tip:AddLine("No bosses known here yet: the guild's kills name them.", 0.6, 0.6, 0.6, true) end
  end
end

-- the members online within w levels of yours who run the addon, nearest first
local function nearYou(rows, level, w, officer)
  if not C.Policy:CanSee(officer, false, "level") then return {} end
  local list = {}
  for _, r in ipairs(rows) do
    if r.addon and r.online and not r.me and type(r.level) == "number" and math.abs(r.level - level) <= w then list[#list + 1] = r end
  end
  table.sort(list, function(a, b)
    local da, db = math.abs(a.level - level), math.abs(b.level - level)
    if da ~= db then return da < db end
    return a.sort < b.sort
  end)
  local names = {}
  for _, r in ipairs(list) do names[#names + 1] = r.short .. " " .. r.level end
  return names
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

-- the page's lines, worked out once a draw: { kind = head | item | sub | note | gap, name, val, who, c (colour of the
-- name), wc (of the right), indent, tip }
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
  -- for you: who is near, then the dungeons your level is in range of
  local now, soon = R.DungeonsFor(level)
  add({ kind = "head", name = "For you, level " .. level, who = alone or "the dungeons in range at your level" })
  if st == "checking" then add({ kind = "note", name = "Checking what we knew against this client." }) end
  local near = nearYou(rows, level, w, officer)
  if #near > 0 then add({ kind = "sub", name = "Online near your level: " .. some(near), c = K.DIM, tip = function(tip)
    tip:AddLine("Online within " .. plural(w, "level", "levels") .. " of yours, with the addon", 1, 1, 1)
    for _, n in ipairs(near) do tip:AddLine(n, 0.8, 0.8, 0.8) end
  end }) end
  for _, d in ipairs(now) do
    local range = R.RangeWords(d)
    add({ kind = "item", name = d.name .. (d.kind == "raid" and " (raid)" or ""), val = range, who = R.Words(d), tip = dungeonTip(d) })
    local left, doubted = {}, {}
    local bosses = bossesOf(d)
    for _, enc in ipairs(bosses) do
      local b = m.bosses[enc]
      if not killedIt(enc) then if b.state == "doubted" then doubted[#doubted + 1] = b.name else left[#left + 1] = b.name end end
    end
    local text
    if #bosses == 0 then text = "No bosses known here yet: the guild's kills name them."
    elseif #left == 0 and #doubted == 0 then text = "Every boss here killed."
    elseif #left == 0 then text = "Every boss here killed but the doubted: " .. table.concat(doubted, ", ")
    else text = "Bosses left: " .. table.concat(left, ", ") .. (#doubted > 0 and ("; doubted: " .. table.concat(doubted, ", ")) or "") end
    add({ kind = "sub", indent = 16, name = text, c = K.DIM, tip = dungeonTip(d) })
  end
  if #now == 0 and st ~= "checking" then add({ kind = "note", name = "No dungeon known for level " .. level .. " yet. The guild's kills fill this in." }) end
  -- next up
  add({ kind = "gap" })
  add({ kind = "head", name = "Next up", who = alone or ("opening within " .. plural(ahead, "level", "levels")) })
  for _, d in ipairs(soon) do
    add({ kind = "item", name = d.name .. (d.kind == "raid" and " (raid)" or ""), val = R.RangeWords(d), who = R.Words(d), tip = dungeonTip(d) })
  end
  if #soon == 0 and st ~= "checking" then add({ kind = "note", name = "Nothing known to open in the next " .. plural(ahead, "level", "levels") .. "." }) end
  -- gear: Missing enchants, with what Forever has for the slot and the kind of item worn there; under the enchant
  -- level, the slots the research has enchants for, as advice (they count as missing from that level, rule 5)
  add({ kind = "gap" })
  add({ kind = "head", name = "Gear", who = alone or "the enchants you lack" })
  local missing = C.Sample:Value("unenchanted")
  local g = S.Gear and S.Gear() or nil
  local from = R.Get("enchantDoubtLevel")
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
  local function slotTip(slot, label, kind, head)
    local _, list, unplaced = forever(slot, kind)
    return function(tip)
      tip:AddLine(label, 1, 1, 1)
      tip:AddLine(head, 0.7, 0.7, 0.7, true)
      for _, x in ipairs(list) do
        local word = x.state == "seen" and ("seen on " .. plural(x.n, "member", "members")) or R.Words({ state = x.state })
        tip:AddDoubleLine(x.name, word, 0.85, 0.85, 0.85, 0.7, 0.7, 0.7)
      end
      if unplaced > 0 then tip:AddLine(plural(unplaced, "more enchant", "more enchants") .. " for this slot, for kinds of item the research does not name.", 0.6, 0.6, 0.6, true) end
    end
  end
  if type(missing) ~= "table" then
    local err = C.Sample:Error("unenchanted")
    add({ kind = "note", name = err and ("Could not read your enchants: " .. err) or "Your enchants have not been read yet." })
  else
    local any, advice = false, {}
    for _, slot in ipairs(S.GEAR) do
      local worn = g and g.slot[slot]
      local kind = worn and worn.kind or nil
      local label = (S.SLOT[slot] or ("Slot " .. slot)) .. (kind and (" (" .. S.KindName(kind) .. ")") or "")
      if missing[slot] then
        any = true
        local tip = slotTip(slot, label, kind, "Not enchanted. The guild's word: " .. S.EnchantSource(slot, kind) .. ".")
        add({ kind = "item", name = label, val = "missing", who = S.EnchantSource(slot, kind), c = K.WARN, tip = tip })
        local line = R.SeedUsable() and forever(slot, kind) or nil
        if line then add({ kind = "sub", indent = 16, name = line, c = K.DIM, tip = tip }) end
      elseif level < from and worn and worn.link and (worn.enchant or 0) == 0 and kind and R.SeedEnchantable(slot, kind) then
        advice[#advice + 1] = { slot = slot, label = label, kind = kind }
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
      add({ kind = "note", name = note })
    end
    if #advice > 0 then
      local names, beta, data = {}, false, false
      for _, a in ipairs(advice) do
        names[#names + 1] = S.SLOT[a.slot]
        if R.SeedSlotState(a.slot) == "beta" then beta = true else data = true end
      end
      local source = (beta and data) and "from research and the beta" or (beta and "seen in the beta" or "from research")
      add({ kind = "item", name = "Could take one: " .. some(names, 3), val = "level " .. from .. "+", who = source, c = K.DIM, tip = function(tip)
        tip:AddLine("Forever has enchants for these", 1, 1, 1)
        tip:AddLine("They count as missing from level " .. from .. ", the rules' enchant level; until then only what the guild has enchanted does.", 0.7, 0.7, 0.7, true)
        for _, a in ipairs(advice) do
          local line = forever(a.slot, a.kind)
          tip:AddDoubleLine(a.label, line and line:gsub("^Forever has:? ", "") or "", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6)
        end
      end })
    end
  end
  -- pace
  add({ kind = "gap" })
  add({ kind = "head", name = "Pace", who = alone or "at your pace and the guild's median" })
  local rate = C.Sample.values.xp_hour
  local med, n = guildPace(rows, officer)
  local xp, max = C.Num("UnitXP", "player"), C.Num("UnitXPMax", "player")
  if level >= cap then
    add({ kind = "note", name = "At the cap, level " .. cap .. "." })
  elseif xp and max then
    local function at(left, r) return (left and r and r > 0) and hoursText(left / r) or nil end
    local nextLeft = math.max(0, max - xp)
    local capLeft = R.XPLeft(level, xp, max, cap)
    local mine = type(rate) == "number" and rate > 0 and rate or nil
    local function pace(name, left, why)
      local yours = at(left, mine) or (left and "no pace yet" or "not known")
      local theirs = at(left, med)
      add({ kind = "item", name = name, val = yours, who = theirs and (theirs .. " at the median of " .. plural(n, "member", "members")) or (left and "no median yet" or ""),
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
    add({ kind = "note", name = "Your XP does not read on this client." })
  end
  -- the officers' view: the dungeons the guild is in range of or has met, and what the guild's play changed from the
  -- research. A dungeon's line folds its bosses into a count, one count per fact (the members seen killing each, kept
  -- as members leave); every boss is in its tooltip
  if officer and m then
    add({ kind = "gap" })
    add({ kind = "head", name = "The guild, per dungeon", who = alone or "members in range, bosses the guild has killed" })
    local list, rest = {}, 0
    for _, d in pairs(m.dungeons) do
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
      local bosses = e.bosses > 0 and (e.killed .. " of " .. plural(e.bosses, "boss", "bosses") .. " killed") or "no bosses known yet"
      add({ kind = "item", name = d.name .. (d.kind == "raid" and " (raid)" or ""), val = R.RangeWords(d),
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
  return items
end

-- the page
function C.Guide_Draw(UI)
  local sf = UI.scroll
  local K = UI.COLORS
  local color, fitText, ROW = UI.Color, UI.FitText, UI.ROW
  UI.header:Hide()
  UI.rows:Clear()
  UI.labels:Reset(); UI.labels:HideRest()
  local w = sf:Width()
  local officer = C.Roster:MeOfficer()
  -- the band: where the knowledge comes from
  local first, second = G.Source()
  local y = 4
  for i, s in ipairs({ first, second }) do
    local l = UI.bandLabels:Get()
    l:SetPoint("TOPLEFT", 6, -y)
    l:SetWidth(w - 12)
    l:SetJustifyH("LEFT")
    color(l, i == 1 and K.WHITE or K.DIM)
    fitText(l, s, w - 16)
    y = y + 18
  end
  UI:SetBand(y + 4)
  -- the lines: what the page shows of yours and the guild's draws it again when it changes (UI:ValueChanged, Arrived;
  -- the pace is read again with the next draw, not with every five-second tick of XP an hour)
  for _, id in ipairs({ "level", "unenchanted", "enchanted" }) do UI.shownIds[id] = true end
  local items = G.Items(officer)
  local vw = 90
  local ww = math.min(260, math.floor(w * 0.34))
  local nw = w - ww - vw - 24
  UI.lines:Set(#items, 0, ROW, function(r, i, ly)
    local it = items[i]
    r.cat, r.def, r.member = nil, nil, nil
    r:SetHeight(ROW)
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.bg:SetColorTexture(1, 1, 1, it.kind == "head" and 0.06 or (it.kind == "item" and 0.025 or 0))
    r.bar:Hide()
    local indent = it.indent or 0
    -- (a line with nothing to its right, a note or a sub-line, takes the row's whole width: at 760 wide a note was cut
    -- at the name's column with the rest of the row empty)
    local room = ((it.val or (it.who and it.who ~= "")) and nw or (w - 12)) - indent
    r.name:SetPoint("LEFT", 8 + indent, 0)
    r.name:SetWidth(room)
    color(r.name, it.c or (it.kind == "head" and K.WHITE or (it.kind == "note" and K.MUTE or K.INK)))
    fitText(r.name, it.name or "", room - 4)
    if it.val then
      r.val:Show()
      r.val:SetPoint("RIGHT", -(ww + 8), 0)
      r.val:SetWidth(vw)
      color(r.val, K.INK)
      fitText(r.val, it.val, vw - 4)
    else r.val:Hide() end
    if it.who and it.who ~= "" then
      local width = it.val and ww or (ww + vw + 4)
      r.who:Show()
      r.who:SetPoint("RIGHT", -4, 0)
      r.who:SetWidth(width)
      color(r.who, it.wc or K.DIM)
      fitText(r.who, it.who, width - 4)
    else r.who:Hide() end
    r.fn = nil
    r.tip = it.tip
  end)
  UI.virtual = function() UI.lines:Show(UI.scroll.bar:GetValue() or 0, UI.scroll:View()) end
  sf:SetContentHeight(#items * ROW + 8)
end
