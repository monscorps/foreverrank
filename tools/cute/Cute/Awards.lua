-- SPDX-License-Identifier: GPL-3.0-or-later
-- Awards: the run report's 26 awards and the choice of its cards (the run report's design, sections 6 and 7). Cute's
-- own: seven GOLD STAR, nine SHOUT-OUT, eight BLOOPER and two THANKS cards that only go to a member with nothing else.
-- Each has a two-letter code for life (uppercase, on the group channel in 2A; a code taken out goes to RETIRED and is
-- never given again). No client calls here: Runs.lua hands it tables, and the harness drives it the same way.
--   A.Pick(members, facts, route)  the cards (and a raid's mentions) for a run: members { sfx, guid, name, v = { key =
--                                  value } }, facts { n, raid, bosses, runId, history }, route(code) whether this
--                                  client's policy lets that code's fields onto a card (Everyone, and settled)
--   A.Text(report, nameOf, route)  the lines Send to party posts
--   A.Sample(kind, members)        a test report's made-up values (a new set of five awards each time)
-- The values a run reads, each client's own (2V keys, Runs.lua) and what every client observes (the meter's rows,
-- deaths, the loot history): a key whose policy code routes Only you never leaves the client, and an award reading it is
-- not eligible, so a closed field takes its awards off every card, screen and chat line alike.
local _, C = ...
local A = {}
C.Awards = A

-- the kinds: the label a card shows, its weight in the choice, and its place in a tie
A.KINDS = { star = "GOLD STAR", shout = "SHOUT-OUT", blooper = "BLOOPER", thanks = "THANKS" }
local WEIGHT = { star = 3, shout = 2, blooper = 2, thanks = 0 }
local ORDER = { star = 1, shout = 2, blooper = 3, thanks = 4 }
A.RETIRED = {}

-- the 2V keys: the policy code each is routed by (nil: always, it reveals nothing), and its bounds on receipt (hi a
-- number, or "run": seconds within the run). An absent key is no data, never zero. The reused codes (deaths, "where are
-- you", jumps, consumables, the level, gold) were set for the guild alone: their keys go only while every member of
-- the group is in the guild (Runs.lua)
local RUN, BIG = "run", 2 ^ 40
A.KEYS = {
  t = { lo = 0, hi = RUN }, o = { lo = 0, hi = RUN },
  de = { code = "de", lo = 0, hi = 200 }, dt = { code = "de", lo = 0, hi = RUN }, fd = { code = "de", lo = 0, hi = RUN },
  dm = { code = "rm", lo = 0, hi = BIG }, hl = { code = "rm", lo = 0, hi = BIG }, ab = { code = "rm", lo = 0, hi = BIG },
  tk = { code = "rm", lo = 0, hi = BIG }, av = { code = "rm", lo = 0, hi = BIG }, ["in"] = { code = "rm", lo = 0, hi = 2000 },
  dp = { code = "rm", lo = 0, hi = 2000 }, mt = { code = "rm", lo = 0, hi = 1 },
  q = { code = "rq", list = true }, ch = { code = "rc", lo = 0, hi = 5000 }, wy = { code = "we", lo = 0, hi = 500 },
  yd = { code = "yw", lo = 0, hi = 500000 }, ju = { code = "ju", lo = 0, hi = 20000 }, cn = { code = "cn", lo = 0, hi = 500 },
  lv = { code = "le", lo = 0, hi = 10 }, gd = { code = "ge", lo = 0, hi = 2 ^ 31 }, lq = { code = "rl", lo = 0, hi = 8 },
  ln = { code = "rl", lo = 0, hi = 200 },
}
-- what each client observes of every member (no 2V key: never sent, Runs.lua keeps them per member), their codes
A.OBSERVED = { hr = "rl", lr = "rl", nd = "rl", wn = "rl" }
A.REUSED = { de = true, we = true, ju = true, cn = true, le = true, ge = true }
-- (the order a 2V carries its keys in)
A.ORDER = { "t", "o", "de", "dt", "fd", "dm", "hl", "ab", "tk", "av", "in", "dp", "mt", "q", "ch", "wy", "yd", "ju", "cn", "lv", "gd", "lq", "ln" }
-- the code a key or an observed fact is routed by; nil for t and o
function A.CodeOf(key) local k = A.KEYS[key]; if k then return k.code end return A.OBSERVED[key] end
-- is a received value within its key's bounds (dur: the run's seconds so far)
function A.InBounds(key, v, dur)
  local k = A.KEYS[key]
  if not k then return false end
  if k.list then
    if type(v) ~= "table" or #v > 16 then return false end
    for _, id in ipairs(v) do if type(id) ~= "number" or id < 1 or id >= 2 ^ 31 then return false end end
    return true
  end
  if type(v) ~= "number" or v ~= v then return false end
  local hi = k.hi == RUN and ((dur or 0) + 120) or k.hi
  return v >= k.lo and v <= hi
end

----------------------------------------------------------------------------
-- formats: a card's value and what it is
----------------------------------------------------------------------------
local function commas(n)
  local s = tostring(math.floor(n + 0.5))
  local k
  repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end
local function big(n)
  if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
  if n >= 10000 then return math.floor(n / 1000) .. "k" end
  return commas(n)
end
-- seconds as the game's clocks show them: 3:12, 42:10, 1:05:00
function A.Clock(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  local h, m, sec = math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
  return string.format("%d:%02d", m, sec)
end
local function ordinal(n) return n == 1 and "1st" or (n == 2 and "2nd" or (n == 3 and "3rd" or (n .. "th"))) end
-- an item quality's name, as the game's globals give it (ITEM_QUALITYn_DESC), and its colour lifted to read on black
-- (the windows design: rare #4094ED, epic #BA69F2); the game's own colour where the table has none
local QUALITY = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }
local LIFTED = { [2] = "1eff00", [3] = "4094ed", [4] = "ba69f2", [5] = "ff8000" }
function A.QualityName(q)
  local g = _G["ITEM_QUALITY" .. tostring(q) .. "_DESC"]
  g = C.Plain(g)
  return (type(g) == "string" and g ~= "") and g or (QUALITY[q] or "?")
end
function A.QualityColor(q) return LIFTED[q] end
local function gold(v) return C.Stats and C.Stats.FmtGold and C.Stats.FmtGold(v) or tostring(v) end

----------------------------------------------------------------------------
-- the 26. reads: the codes of every field the award reads (all routed Everyone, or it is not eligible). pick(ctx) gives
-- each pair { m, value, strength }; show(value) the value as a card shows it and what it is
----------------------------------------------------------------------------
local INT = "in"
local LIST = {}
local BY = {}
local function award(code, kind, title, quip, reads, pick, show)
  local a = { code = code, kind = kind, title = title, quip = quip, reads = reads, pick = pick, show = show }
  LIST[#LIST + 1] = a
  BY[code] = a
  return a
end
A.LIST, A.BY = LIST, BY

-- the members with a value for key, highest first; ties to fewer deaths, then the smaller GUID
local function ranked(ctx, key, value)
  local cache = ctx.ranks[key]
  if cache then return cache end
  local out = {}
  for _, m in ipairs(ctx.members) do
    local v = value and value(m) or m.v[key]
    if type(v) == "number" then out[#out + 1] = { m = m, v = v } end
  end
  table.sort(out, function(a, b)
    if a.v ~= b.v then return a.v > b.v end
    local da, db = a.m.v.de or 0, b.m.v.de or 0
    if da ~= db then return da < db end
    return a.m.guid < b.m.guid
  end)
  ctx.ranks[key] = out
  return out
end
local function top(ctx, key, value) local r = ranked(ctx, key, value); return r[1] end
local function total(ctx, key)
  local t = 0
  for _, m in ipairs(ctx.members) do local v = m.v[key]; if type(v) == "number" then t = t + v end end
  return t
end
-- the median over the members with a value
local function median(ctx, key)
  local list = {}
  for _, m in ipairs(ctx.members) do local v = m.v[key]; if type(v) == "number" then list[#list + 1] = v end end
  if #list == 0 then return nil end
  table.sort(list)
  local i = math.floor((#list + 1) / 2)
  if #list % 2 == 0 then return (list[i] + list[i + 1]) / 2 end
  return list[i]
end
A.Median = median
local function over(v, x) return math.min(3, v / math.max(x, 1e-9)) end
-- the top of key, where it meets at least x: one pair
local function atLeast(key, x, raidX)
  return function(ctx)
    local t = top(ctx, key)
    local need = (ctx.raid and raidX) or x
    if t and t.v >= need and t.v > 0 then return { { m = t.m, value = t.v, strength = over(t.v, need) } } end
    return {}
  end
end
-- a share of the group's total, in whole per cent: the top, at least 1.25 fair shares
local function share(key)
  return function(ctx)
    local sum = total(ctx, key)
    local t = top(ctx, key)
    if not t or sum <= 0 or t.v <= 0 then return {} end
    local s, fair = t.v / sum, 1.25 / math.max(1, ctx.n)
    if s < fair then return {} end
    return { { m = t.m, value = math.floor(s * 100 + 0.5), strength = over(s, fair) } }
  end
end
local function count(word) return function(v) return commas(v), word end end
local function pct(word) return function(v) return v .. "%", word end end

award("HD", "star", "Headliner", "Top of the meter, and humble about it. Almost.", { "rm" }, share("dm"), pct("of the group's damage"))
award("LF", "star", "Lifeline", "Kept everyone upright, some of us twice.", { "rm" }, share("hl"), pct("of the group's healing"))
award("OS", "star", "Off Switch", "No enemy finished a spell while they were near.", { "rm" }, atLeast(INT, 5, 8), count("interrupts"))
award("CW", "star", "Clean Sweep", "Whatever stuck to us, they took off.", { "rm" }, atLeast("dp", 5, 10), count("dispels"))
award("IW", "star", "Iron Wall", "Took the most hits and never hit the floor.", { "rm", "de" }, function(ctx)
  local t = top(ctx, "tk")
  if not t or t.v <= 0 or ctx.bosses < 2 or t.m.v.de ~= 0 then return {} end
  return { { m = t.m, value = t.v, strength = over(ctx.bosses, 2) } }
end, function(v) return big(v), "damage taken" end)
award("BW", "star", "Bubble Wrap", "Wrapped us in shields like fragile post.", { "rm" }, share("ab"), pct("of the absorbs"))
-- (the value carries both: the healing share in per cent, times ten, plus the damage rank)
award("TJ", "star", "Two Jobs", "Did their job, then quietly did yours.", { "rm" }, function(ctx)
  local dm, hl = ranked(ctx, "dm"), ranked(ctx, "hl")
  local sum = total(ctx, "hl")
  if sum <= 0 or #dm == 0 then return {} end
  local out = {}
  for rank = 1, math.min(2, #dm) do
    local m = dm[rank].m
    local h = m.v.hl
    if dm[rank].v > 0 and type(h) == "number" and h / sum >= 0.15 and hl[1] and hl[1].m ~= m then
      out[#out + 1] = { m = m, value = math.floor(h / sum * 100 + 0.5) * 10 + rank, strength = over(h / sum, 0.15) }
    end
  end
  return out
end, function(v) return math.floor(v / 10) .. "%", "healing, " .. ordinal(v % 10) .. " in damage" end)
award("NS", "shout", "Not a Scratch", "Zero deaths while the floor filled up.", { "de" }, function(ctx)
  local deaths = total(ctx, "de")
  if deaths < 3 then return {} end
  local best
  for _, m in ipairs(ctx.members) do
    if m.v.de == 0 then
      local function key(x) return (x.v.tk or 0), (x.v.dm or 0) end
      if not best then best = m
      else
        local a1, a2 = key(m)
        local b1, b2 = key(best)
        if a1 > b1 or (a1 == b1 and (a2 > b2 or (a2 == b2 and m.guid < best.guid))) then best = m end
      end
    end
  end
  if not best then return {} end
  return { { m = best, value = 0, strength = over(deaths, 3) } }
end, function(v) return tostring(v), "deaths" end)
-- (quests handed in by this member that another member of the run handed in too)
award("PW", "shout", "Paperwork", "Turned the run into a tidy quest log.", { "rq" }, function(ctx)
  local by = {}
  for _, m in ipairs(ctx.members) do for _, id in ipairs(type(m.v.q) == "table" and m.v.q or {}) do by[id] = (by[id] or 0) + 1 end end
  local t = top(ctx, "pw", function(m)
    local n = 0
    for _, id in ipairs(type(m.v.q) == "table" and m.v.q or {}) do if by[id] > 1 then n = n + 1 end end
    return n > 0 and n or nil
  end)
  if not t or t.v < 3 then return {} end
  return { { m = t.m, value = t.v, strength = over(t.v, 3) } }
end, count("quests handed in together"))
award("LB", "shout", "Lucky Bags", "The loot table just likes them more.", { "rl" }, function(ctx)
  local r = ranked(ctx, "lb", function(m)
    local q = m.v.lq
    if type(q) ~= "number" then return nil end
    return q * 1000 + math.min(999, m.v.wn or m.v.ln or 0)
  end)
  local t = r[1]
  if not t or math.floor(t.v / 1000) < 3 then return {} end
  local q = math.floor(t.v / 1000)
  return { { m = t.m, value = q, strength = over(q, 3) } }
end, function(v) local c = A.QualityColor(v); return c and ("|cff" .. c .. A.QualityName(v) .. "|r") or A.QualityName(v), "best drop" end)
award("FH", "shout", "Full Hundred", "Rolled a hundred. We all saw it.", { "rl" }, function(ctx)
  local out = {}
  for _, m in ipairs(ctx.members) do if m.v.hr == 100 then out[#out + 1] = { m = m, value = 100, strength = 2.5 } end end
  return out
end, function(v) return tostring(v), "rolled" end)
award("TB", "shout", "Trailblazer", "Walked every corner so the map didn't have to.", { "yw" }, function(ctx)
  local t, med = top(ctx, "yd"), median(ctx, "yd")
  if not (t and med) or t.v <= 0 or t.v < 1.2 * med then return {} end
  return { { m = t.m, value = math.floor(t.v), strength = over(t.v, 1.2 * math.max(med, 1)) } }
end, count("yards"))
award("NR", "shout", "Narrator", "Gave us live commentary, free of charge.", { "rc" }, atLeast("ch", 15), count("lines typed"))
award("DG", "shout", "Ding!", "Walked in one level, walked out the next.", { "le" }, function(ctx)
  local t = top(ctx, "lv")
  if not t or t.v < 1 then return {} end
  return { { m = t.m, value = t.v, strength = 2 } }
end, function(v) return "+" .. v, v == 1 and "level" or "levels" end)
award("CM", "shout", "Coin Magnet", "Every corpse paid them first.", { "ge" }, function(ctx)
  local t = top(ctx, "gd")
  if not t or t.v <= 0 then return {} end
  return { { m = t.m, value = t.v, strength = 1 } }
end, function(v) return gold(v), "looted" end)
award("WL", "shout", "Well Stocked", "Came prepared and drank the evidence.", { "cn" }, atLeast("cn", 3), count("consumables"))
award("FI", "blooper", "Floor Inspector", "Checked every floor tile personally. Thorough.", { "de" }, atLeast("de", 3), count("deaths"))
award("OA", "blooper", "Opening Act", "Went first so we knew what not to do.", { "de" }, function(ctx)
  local first
  for _, m in ipairs(ctx.members) do
    local fd = m.v.fd
    if type(fd) == "number" then
      if not first or fd < first.v.fd or (fd == first.v.fd and ((m.order or 999) < (first.order or 999) or ((m.order or 999) == (first.order or 999) and m.guid < first.guid))) then first = m end
    end
  end
  if not first then return {} end
  return { { m = first, value = first.v.fd, strength = 1.2 } }
end, function(v) return A.Clock(v), "into the run" end)
award("SP", "blooper", "Spectator", "Saw most of the run from the floor. Great view.", { "de" }, atLeast("dt", 180), function(v) return A.Clock(v), "dead" end)
award("WF", "blooper", "Warm Feet", "If it glowed on the ground, they stood in it.", { "rm" }, function(ctx)
  local t, med = top(ctx, "av"), median(ctx, "av")
  if not (t and med) or t.v <= 0 or t.v < 1.5 * med then return {} end
  return { { m = t.m, value = t.v, strength = over(t.v, 1.5 * math.max(med, 1)) } }
end, function(v) return big(v), "avoidable damage" end)
award("LO", "blooper", "Lost and Found", "Asked where we were. We were right here.", { "we" }, atLeast("wy", 1), count("times asked"))
award("PG", "blooper", "Pogo Stick", "Jumped so much the boss checked for a dance.", { "ju" }, atLeast("ju", 100), count("jumps"))
award("NA", "blooper", "Need It All", "Needed every drop. Every single one.", { "rl" }, atLeast("nd", 4), count("need rolls"))
award("BD", "blooper", "Bad Dice", "Rolled almost nothing. The dice are sorry.", { "rl" }, function(ctx)
  local low
  for _, m in ipairs(ctx.members) do
    local r = m.v.lr
    if type(r) == "number" and (not low or r < low.v.lr or (r == low.v.lr and m.guid < low.guid)) then low = m end
  end
  if not low or low.v.lr > 5 then return {} end
  return { { m = low, value = low.v.lr, strength = low.v.lr <= 1 and 2.5 or 2 } }
end, function(v) return tostring(v), "lowest roll" end)
award("GC", "thanks", "Good Company", "Made the run better just by being in it.", {}, nil, function(v) return A.Clock(v), "in the run" end)
award("SH", "thanks", "Steady Hands", "Kept calm and kept going.", { "de" }, nil, function(v) return tostring(v), v == 1 and "death" or "deaths" end)

-- the line a card shows under its title, and its value: (text, what it is)
function A.Show(code, value)
  local a = BY[code]
  if not (a and type(value) == "number") then return "?", "" end
  return a.show(value)
end
-- an award's title and kind, for a card (nil for a code this client does not know: a newer Cute's)
function A.Of(code) return BY[code] end
-- (Warm Feet is the meter's verdict on someone's play: never on the party line, which strangers read)
A.PARTY_SKIP = { WF = true }

----------------------------------------------------------------------------
-- the choice (section 7). Same input, same cards, on every client: no randomness. The variety comes from the run id
-- (ties fall by a hash of the id and the award's code) and from the scribe's history (a member given the same award
-- in either of their last two reports with it scores less)
----------------------------------------------------------------------------
local function hash(s) return (C.Policy and C.Policy.Fnv) and C.Policy.Fnv(s, 2166136261) or #s end
-- eligible: every field it reads routed Everyone (route), so a closed field takes its awards off everywhere
local function eligible(a, route)
  for _, code in ipairs(a.reads) do if not route(code) then return false end end
  return true
end
-- a repeat: the member had this award in either of their last two reports in the history (newest first)
local function repeated(history, sfx, code)
  local seen = 0
  for _, rep in ipairs(history or {}) do
    local had, award = false, false
    for _, card in ipairs(rep.cards or {}) do
      if card[1] == sfx then had = true; if card[2] == code then award = true end end
    end
    for _, card in ipairs(rep.mentions or {}) do
      if card[1] == sfx then had = true; if card[2] == code then award = true end end
    end
    if had then
      if award then return true end
      seen = seen + 1
      if seen >= 2 then return false end
    end
  end
  return false
end

-- members: { sfx, guid, name, v, order }; facts: { n, raid, bosses, runId, history }; route(code). Returns cards {
-- { sfx, code, value, kind } ... } in their order on the screen (the headline first, then by score) and, for a raid, up
-- to ten mentions, no member twice
function A.Pick(members, facts, route)
  facts = facts or {}
  local n = facts.n or #members
  local raid = facts.raid or n >= 6
  local ctx = { members = members, n = n, raid = raid, bosses = facts.bosses or 0, ranks = {} }
  local runId = tostring(facts.runId or "")
  local pairs_ = {}
  for _, a in ipairs(LIST) do
    if a.pick and eligible(a, route) and not A.RETIRED[a.code] then
      for _, p in ipairs(a.pick(ctx)) do
        local score = WEIGHT[a.kind] + p.strength
        if repeated(facts.history, p.m.sfx, a.code) then score = score - 1.5 end
        pairs_[#pairs_ + 1] = { m = p.m, a = a, value = p.value, score = score, tie = hash(runId .. a.code) }
      end
    end
  end
  table.sort(pairs_, function(x, y)
    if math.abs(x.score - y.score) > 1e-9 then return x.score > y.score end
    if ORDER[x.a.kind] ~= ORDER[y.a.kind] then return ORDER[x.a.kind] < ORDER[y.a.kind] end
    if x.tie ~= y.tie then return x.tie < y.tie end
    return x.m.guid < y.m.guid
  end)
  local cap = raid and 5 or math.min(5, #members)
  local usedM, usedA, cards, bloopers = {}, {}, {}, 0
  local maxBloopers = (#members <= 2) and 0 or 2
  local function take(p)
    usedM[p.m.sfx], usedA[p.a.code] = true, true
    if p.a.kind == "blooper" then bloopers = bloopers + 1 end
    cards[#cards + 1] = { p.m.sfx, p.a.code, p.value, p.a.kind, score = p.score }
  end
  local function free(p) return not usedM[p.m.sfx] and not usedA[p.a.code] and (p.a.kind ~= "blooper" or bloopers < maxBloopers) end
  -- the headline: the best GOLD STAR, else the best SHOUT-OUT
  for _, kind in ipairs({ "star", "shout" }) do
    if #cards == 0 then for _, p in ipairs(pairs_) do if p.a.kind == kind and free(p) then take(p); break end end end
  end
  local headline = cards[1] ~= nil
  -- where a blooper pair exists, the best free one right after the headline (so a report with something to tease has
  -- one, even where its holder also holds a better shout-out); then the rest by score
  if maxBloopers > 0 and #cards < cap then
    for _, p in ipairs(pairs_) do if p.a.kind == "blooper" and free(p) then take(p); break end end
  end
  while #cards < cap do
    local pick
    for _, p in ipairs(pairs_) do if free(p) then pick = p; break end end
    if not pick then break end
    take(pick)
  end
  -- every member a card in a group of two to five: a THANKS card for each left without one, Steady Hands where their
  -- deaths are at most the median and it is free (its reads routed Everyone), else Good Company (which may repeat)
  if not raid then
    local med = median(ctx, "de")
    local shOK = eligible(BY.SH, route)
    local list = {}
    for _, m in ipairs(members) do if not usedM[m.sfx] then list[#list + 1] = m end end
    table.sort(list, function(x, y) return x.guid < y.guid end)
    for _, m in ipairs(list) do
      if #cards >= 5 then break end
      local de = m.v.de
      if shOK and not usedA.SH and type(de) == "number" and med and de <= med then
        usedA.SH = true
        cards[#cards + 1] = { m.sfx, "SH", de, "thanks" }
      else
        cards[#cards + 1] = { m.sfx, "GC", math.floor(m.v.t or 0), "thanks" }
      end
      usedM[m.sfx] = true
    end
  end
  -- headline first, then by score, left to right
  if #cards > 1 then
    local first = headline and table.remove(cards, 1) or nil
    local thanks = {}
    for i = #cards, 1, -1 do if cards[i][4] == "thanks" then table.insert(thanks, 1, table.remove(cards, i)) end end
    table.sort(cards, function(x, y) return (x.score or 0) > (y.score or 0) end)
    if first then table.insert(cards, 1, first) end
    for _, t in ipairs(thanks) do cards[#cards + 1] = t end
  end
  for _, c in ipairs(cards) do c.score = nil end
  -- a raid's honourable mentions: the next pairs by score, a member and an award not on a card, no member twice
  local mentions = {}
  if raid then
    for _, p in ipairs(pairs_) do
      if #mentions >= 10 then break end
      if not usedM[p.m.sfx] and not usedA[p.a.code] then
        usedM[p.m.sfx], usedA[p.a.code] = true, true
        mentions[#mentions + 1] = { p.m.sfx, p.a.code, p.value, p.a.kind }
      end
    end
  end
  return cards, mentions
end

----------------------------------------------------------------------------
-- Send to party: plain text for those without the addon, Windows-1252 but the names, each line at most 255 bytes.
-- report: { title, place, bosses, known, dur, wipes, deaths, cards, mentions, gone }; nameOf(sfx) the member's name;
-- route(code), where given, the fields the line may carry
----------------------------------------------------------------------------
local DOT = " \194\183 " -- (a middle dot, in Windows-1252; the file stays ASCII)
A.DOT = DOT
local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
local function cut(s, max)
  if #s <= max then return s end
  s = s:sub(1, max)
  -- (never a character cut in two)
  while #s > 0 do local b = s:byte(#s); if b < 0x80 then break end; if b >= 0xC0 then s = s:sub(1, -2); break end; s = s:sub(1, -2) end
  return s
end
-- the colour codes a card's value may carry (an item quality's), off for chat
local function bare(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
function A.Text(report, nameOf, route)
  local lines = {}
  -- (route, where given: a card or mention whose award it does not let through stays off the line)
  local function ok(a) if not route then return true end return eligible(a, route) end
  local head = "Cute recap" .. DOT .. tostring(report.place or "?")
  if report.kind ~= "g" then
    local known = math.max(report.known or 0, report.bosses or 0)
    head = head .. DOT .. (report.bosses or 0) .. "/" .. known .. " bosses"
  end
  head = head .. DOT .. A.Clock(report.dur or 0) .. DOT .. plural(report.wipes or 0, "wipe", "wipes") .. DOT .. plural(report.deaths or 0, "death", "deaths")
  lines[1] = cut(head, 255)
  for _, card in ipairs(report.cards or {}) do
    local a = BY[card[2]]
    if a and not A.PARTY_SKIP[a.code] and ok(a) then
      local v, what = a.show(card[3])
      lines[#lines + 1] = cut(string.format("%s%s%s: %s, %s %s. %s", A.KINDS[a.kind], DOT, a.title, nameOf(card[1]) or "?", bare(v), what, a.quip), 255)
    end
  end
  local mentions = {}
  for _, mn in ipairs(report.mentions or {}) do
    local a = BY[mn[2]]
    if a and not A.PARTY_SKIP[a.code] and ok(a) then
      local v, what = a.show(mn[3])
      mentions[#mentions + 1] = string.format("%s %s (%s %s)", a.title, nameOf(mn[1]) or "?", bare(v), what)
    end
  end
  if #mentions > 0 then
    local s = "Also: " .. mentions[1]
    for i = 2, #mentions do
      if #s + 2 + #mentions[i] > 255 then break end
      s = s .. ", " .. mentions[i]
    end
    lines[#lines + 1] = cut(s, 255)
  end
  if report.gone and #report.gone > 0 then
    local names = {}
    for _, sfx in ipairs(report.gone) do names[#names + 1] = nameOf(sfx) or "?" end
    lines[#lines + 1] = cut("Gone before the end: " .. table.concat(names, ", "), 255)
  end
  return lines
end

----------------------------------------------------------------------------
-- the test report: five awards drawn from the 26 (a new set each time, by the draw's number), each given to a member
-- with a made-up value that meets it. Nothing here is sent, saved or counted
----------------------------------------------------------------------------
local SAMPLE_VALUE = { HD = 38, LF = 61, OS = 14, CW = 11, IW = 212000, BW = 44, TJ = 222, NS = 0, PW = 6, LB = 4, FH = 100, TB = 2140,
  NR = 23, DG = 1, CM = 18450, WL = 7, FI = 5, OA = 192, SP = 460, WF = 18000, LO = 3, PG = 341, NA = 6, BD = 2, GC = 2530, SH = 1 }
A.SAMPLE_VALUE = SAMPLE_VALUE
function A.Sample(draw, members)
  draw = math.max(1, math.floor(tonumber(draw) or 1))
  local pool = {}
  for _, a in ipairs(LIST) do if a.kind ~= "thanks" then pool[#pool + 1] = a end end
  -- a walk through the pool by a stride prime to its size, from where the draw says: five different awards, a new set
  -- for each draw, the headline a GOLD STAR, one BLOOPER where five cards fit
  local stride, n = 7, #pool
  local picked, used = {}, {}
  local i = ((draw - 1) * 5) % n
  while #picked < 5 and #picked < n do
    local a = pool[i % n + 1]
    if not used[a.code] then used[a.code] = true; picked[#picked + 1] = a end
    i = i + stride
  end
  local stars, bloopers, rest = {}, {}, {}
  for _, a in ipairs(picked) do
    if a.kind == "star" then stars[#stars + 1] = a elseif a.kind == "blooper" then bloopers[#bloopers + 1] = a else rest[#rest + 1] = a end
  end
  if #stars == 0 then for _, a in ipairs(LIST) do if a.kind == "star" and not used[a.code] then table.insert(stars, a); break end end end
  local order = { stars[1] }
  for k = 2, #stars do rest[#rest + 1] = stars[k] end
  for k = 1, math.min(2, #bloopers) do rest[#rest + 1] = bloopers[k] end
  for _, a in ipairs(rest) do if #order < math.min(5, #members) then order[#order + 1] = a end end
  local cards = {}
  for k, a in ipairs(order) do
    local m = members[k]
    if m then cards[#cards + 1] = { m.sfx, a.code, SAMPLE_VALUE[a.code] or 1, a.kind } end
  end
  for k = #cards + 1, #members do
    if k > 5 then break end
    cards[#cards + 1] = { members[k].sfx, "GC", 2530, "thanks" }
  end
  return cards
end
