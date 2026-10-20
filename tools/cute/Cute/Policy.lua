-- SPDX-License-Identifier: GPL-3.0-or-later
-- The officers' visibility policy: per stat, "all" (everyone sees everyone's) or "self" (you see your own; officers
-- see all), and the officer ranks. Only-you is routing, not hiding: a value the policy keeps to the officers never goes
-- on the guild channel. Each client whispers it to the officers online (Comm.lua), so a member's client never holds
-- another member's, and a member's client deletes the ones it holds once the policy closes a stat or the roster says it
-- is no officer's. And no Everyone value may rebuild an Only-you one: a stat that would tell a member one the officers
-- keep (Stats.lua reveals) goes their way too (P:Route).
-- Where the policy lives: the guild's Guild Info. An officer who changes it in Settings saves it there with a click
-- (P:Save), as one short line at the end of the guild's own text, "Cute 1 <stamp> <ranks> <fingerprint> <what differs
-- from the defaults>", which the server keeps and only the ranks allowed to edit Guild Info can change. Every client
-- reads it as the roster comes (C_GuildInfo.GetInfoText on GUILD_ROSTER_UPDATE, P:ReadLine) and routes by the policy
-- the line carries: what differs from the defaults, with its fingerprint, which must match. A save that would not fit
-- whole beside the guild's text is refused: no line carries a fingerprint alone, so no policy is ever taken from the
-- guild channel by its fingerprint (one 64-bit FNV hash is no signature: an edited copy could forge one). Until this
-- client holds the line's policy (Guild Info not read yet, a line it cannot read, or an officer's newer policy heard
-- that Guild Info has not been read again for) nothing of yours leaves but the ask (Comm.lua, P:Settled). An officer's
-- change not saved routes on that officer's own client alone, and only while the line's ranks name them an officer.
-- A guild whose officers never saved a line routes by the newest policy an officer sent (by the roster's rank, never by
-- what a message says), as 0.6.0's first builds did: a member who was away routes by the older one it holds until an
-- officer online sends a newer one. Settings asks the officers to save the line.
-- The rules' thresholds travel in the policy too (Rules.lua): an officer retunes one in Settings and the guild applies
-- the newest an officer sent, with who set each (by GUID), so the rules adapt on launch day without an addon update.
-- And so do the members the officers marked untrusted (by GUID), whom the guild leaves out of what it learns and of the
-- rankings. Neither is privacy, and neither is in Guild Info: both go by the sender's rank in the roster, item by item,
-- each with when it was set (a threshold put back to its default, a member trusted again, kept as such), so the newest
-- of each wins: an officer who was away, and changes something before another officer's word reaches them, undoes
-- nothing that officer set meanwhile
local _, C = ...
local P = {}
C.Policy = P

local DEFAULT_THRESHOLD = 1 -- rank index 0 (guild master) and 1 count as officers
local EMPTY = {}
local AHEAD = 60        -- seconds an officer's policy may be stamped past the server's clock
local PARTS_CAP = 2000  -- parts taken from one sender's policy
local LINE_V = 1        -- the line's format
P.INFO_MAX = 499        -- Guild Info at most: the game's own editor takes 499 letters (Blizzard_Communities/GuildInfo.lua,
                        -- SetMaxLetters); counted here in bytes, which a letter never has fewer of
P.ver = 0               -- bumped whenever what the policy says may have changed (the caches below)
P.line = nil            -- Guild Info's line: nil, not read yet; false, read and none; else { at, thr, fp, diff, newer }
P.heard = {}            -- per sender, the newest whole policy heard on the guild channel
P.parts = {}            -- per sender, a policy whose parts are still coming
P.unread = nil          -- an officer's policy heard that is newer than the line and not its: no save of this client's
                        -- own until a read confirms the line (P:SaveState); { old, at, asked }
P.saved = nil           -- this client's last save, while its first reads say whether Guild Info kept it (P:ReadLine)

local resolve -- (below)
local function held()
  local p = CuteDB and CuteDB.policy
  -- (tokens kept unknown, a module's or a newer Cute's code, named once this client defines it: resolve)
  if type(p) == "table" and type(p.extra) == "table" and p.extra[1] ~= nil and p.extraAt ~= C.Stats.codeVersion then resolve(p) end
  return p
end
local function thrOf(p) return (p and type(p.threshold) == "number") and p.threshold or DEFAULT_THRESHOLD end
-- a stat nobody sets: hidden, or fixed (P:Vis)
local function unset(def) return def ~= nil and (def.hidden or def.fixed) and true or false end
function P.Fixed(id) return unset(C.Stats.byId[id]) end

-- who is an officer, and whom this client whispers the officers' values to: the officer ranks of the policy it routes
-- by (Guild Info's, where the guild has a line; an officer's own change not saved included, for their own client alone)
function P:Threshold() return thrOf(held()) end
-- who is an officer for what others send (their policy, their word, the asks that get the whispered part, the account's
-- other characters): the line's ranks where the guild has one this client can read, never an officer's change not
-- saved (an officer who raised them without saving made a rank-2 copy an officer on their client, and its untrusted
-- marks went to the guild under the officer's name)
function P:LineThreshold()
  local line = self.line
  if type(line) == "table" and line.fp and not line.newer and type(line.thr) == "number" then return line.thr end
  return self:Threshold()
end

-- the id a stat takes its visibility from where the officers set none for it: a statistic (a "g" stat with a game
-- category) its category ("gc" .. the category id), a child category its parent, a discovered stat its category,
-- "gc_bosses", "gc_dungeons", "gc_raids" or "gc_rep" (a letter after "gc_", so no game category id is the same; every
-- instance's bosses share Bosses'); nil at the top. The officers choose per statistics category, not per statistic
local function up(id)
  local def = C.Stats.byId[id]
  if def and def.game then return "gc" .. def.game end
  if def and def.learned then return "gc_" .. def.learned end
  local cat = tonumber(id:match("^gc(%d+)$"))
  if cat then
    local e = C.Stats.game and C.Stats.game.byId[cat]
    if e and type(e.parent) == "number" and e.parent ~= -1 and e.parent ~= cat then return "gc" .. e.parent end
  end
  return nil
end
-- what a visibility list says for an id, or for the nearest one up it takes its visibility from; nil where it says nothing
local function said(vis, id)
  if type(vis) ~= "table" then return nil end
  for _ = 1, 5 do
    local v = vis[id]
    if v == "all" or v == "self" then return v end
    id = up(id)
    if not id then return nil end
  end
  return nil
end

----------------------------------------------------------------------------
-- the policy as text: what differs from the defaults, by code, and its fingerprint
----------------------------------------------------------------------------
-- a policy id's code (Stats.lua S.CODES and S.FOUND; a statistics category its number), and the id a code names here
local function codeOf(id)
  local def = C.Stats.byId[id]
  if def then return def.code end
  local n = id:match("^gc([1-9]%d*)$")
  if n then return n end
  for _, f in ipairs(C.Stats.FOUND) do if id == "gc_" .. f[1] then return f[3] end end
  return nil
end
P.Code = codeOf
local function idOf(code)
  if code:match("^[1-9]%d*$") then return #code <= 10 and ("gc" .. code) or nil end
  return C.Stats.byCode[code]
end
-- the value an id takes where the list says nothing of it: a stat's default, Everyone for a discovered category, a
-- statistics category its parent's; nil for a category this client does not list (its choice is kept as it is)
local function fallback(vis, id)
  local def = C.Stats.byId[id]
  if def then return def.default or "all" end
  if id:match("^gc_") then return "all" end
  local cat = tonumber(id:match("^gc(%d+)$"))
  if not (cat and C.Stats.game and C.Stats.game.byId[cat]) then return nil end
  local u = up(id)
  return u and (said(vis, u) or "all") or "all"
end
-- tokens in canonical order (by code, byte by byte: a string's < goes by the client's locale, which may differ from
-- one client to the next), one per code: the text the fingerprint is of; nil where a code comes twice
local function less(a, b, from)
  for i = from or 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then return x < y end
  end
  return #a < #b
end
local function byCode(a, b) return less(a, b, 2) end
local function canonical(list)
  table.sort(list, byCode)
  for i = 2, #list do if list[i]:sub(2) == list[i - 1]:sub(2) then return nil end end
  return table.concat(list)
end
-- a visibility list as what differs from the defaults: "+go" Everyone, "-zo" Only you, sorted by code. extra: the
-- tokens of codes this client does not know (a newer Cute's stat), kept as they came, unless the list names the code
-- now (one token a code: two would make no text at all)
local function diffOf(vis, extra)
  local list, named = {}, {}
  for id, v in pairs(type(vis) == "table" and vis or EMPTY) do
    local code = type(id) == "string" and (v == "all" or v == "self") and not unset(C.Stats.byId[id]) and codeOf(id)
    if code then named[code] = true end
    if code and v ~= fallback(vis, id) then list[#list + 1] = (v == "all" and "+" or "-") .. code end
  end
  for _, t in ipairs(type(extra) == "table" and extra or EMPTY) do if not named[t:sub(2)] then list[#list + 1] = t end end
  return canonical(list) or ""
end
-- and back: the list this client can name, and the tokens it cannot
local function visOf(diff)
  local vis, extra = {}, {}
  for sign, code in (diff or ""):gmatch("([%+%-])([%w_]+)") do
    local id = idOf(code)
    if id then vis[id] = sign == "+" and "all" or "self" else extra[#extra + 1] = sign .. code end
  end
  return vis, extra
end
-- the tokens of a policy held that this client could not name when it took them (a module's stat, defined only once the
-- module is on; a newer Cute's): each whose code it names now goes into the list, unless the list sets that id already,
-- so the stat routes as the policy says, not by its default. Its text, and so its fingerprint, stays as it came
resolve = function(p)
  p.extraAt = C.Stats.codeVersion
  local left, moved = {}, false
  for _, t in ipairs(p.extra) do
    local id = type(t) == "string" and idOf(t:sub(2)) or nil
    if id then
      p.vis = type(p.vis) == "table" and p.vis or {}
      if p.vis[id] == nil then p.vis[id] = t:sub(1, 1) == "+" and "all" or "self" end
      moved = true
    else left[#left + 1] = t end
  end
  if moved then p.extra = left; P.ver = P.ver + 1 end
end
-- the policy's text: what it holds as it came (Guild Info's line, a 1P), else made from its list (an officer's change,
-- saved variables of 0.5.x)
function P:Diff(p)
  p = p or held()
  if not p then return "" end
  if type(p.diff) == "string" then return p.diff end
  return diffOf(p.vis, p.extra)
end

-- FNV-1a, 32 bits: the byte xor'd in (the bit library the client's own code uses, else by hand), then times 16777619
-- in two parts, so no product passes the 2^53 a number holds exactly
local bxor = type(bit) == "table" and bit.bxor or nil
local function xor8(a, b)
  if bxor then return bxor(a, b) end
  local r, p = 0, 1
  for _ = 1, 8 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = (a - x) / 2, (b - y) / 2, p * 2
  end
  return r
end
local function fnv(s, h)
  for i = 1, #s do
    local lo = h % 256
    h = h - lo + xor8(lo, s:byte(i))
    h = (h * 403 + (h % 256) * 16777216) % 4294967296
  end
  return h
end
P.Fnv = fnv
local function hex8(h) return string.format("%04x%04x", math.floor(h / 65536), h % 65536) end
-- the fingerprint of a policy: two FNV-1a hashes of "<ranks>:<what differs>", the text forwards from the standard
-- basis and backwards from another, 16 hex digits. Not a signature: Guild Info is what only the officers can write
function P.Fingerprint(thr, diff)
  local s = tostring(thr) .. ":" .. (diff or "")
  return hex8(fnv(s, 2166136261)) .. hex8(fnv(s:reverse(), 2654435769))
end
-- the fingerprint of the policy held (or p), kept with it while its text stays the same
function P:Fp(p)
  p = p or held()
  local thr, diff = thrOf(p), self:Diff(p)
  local text = thr .. ":" .. diff
  if p and p.fpText == text and type(p.fp) == "string" then return p.fp end
  local fp = P.Fingerprint(thr, diff)
  if p then p.fpText, p.fp = text, fp end
  return fp
end

----------------------------------------------------------------------------
-- what a stat is, under the policy
----------------------------------------------------------------------------
-- what the officers set for a stat, or the registry's default ("all" for a statistic or a discovered stat whose
-- category nobody set). A hidden stat (the GUID above all) is nobody's to set, nor a fixed one (Addon version, which
-- says who takes whispers and whose Ready counts what: closed, every member's whispers to the officers stopped)
function P:Vis(id)
  local def = C.Stats.byId[id]
  if unset(def) then return def.default or "all" end
  local p = held()
  return said(p and p.vis, id) or (def and def.default) or "all"
end

-- may this viewer see this row's value of this stat: where it travels, not only what the officers chose for it (a stat
-- kept with another, below, reaches no member)
function P:CanSee(viewerIsOfficer, rowIsMe, id)
  if viewerIsOfficer or rowIsMe then return true end
  return self:Route(id) == "all"
end

-- No Everyone value may rebuild an Only-you one. A stat names the ones a member could work out from it (Stats.lua
-- reveals: Enchanted slots, with the slots the guild knows take an enchant, gives Missing enchants), and a category
-- names its counts and its children (Stats.lua S.CatReveals); each goes the strictest way of its own and of everything
-- it reveals, followed through (a statistic its category's, Bosses killed Bosses'). closed(id): true, and the id that
-- keeps it to the officers, where it or what it reveals is "self"
local function revealsOf(id)
  local def = C.Stats.byId[id]
  if def then return def.reveals end
  return C.Stats.CatReveals and C.Stats.CatReveals(id) or nil
end
local function catOf(def) return def and ((def.game and ("gc" .. def.game)) or (def.learned and ("gc_" .. def.learned))) or nil end
local function closed(self, id, seen)
  if seen[id] then return false end
  seen[id] = true
  if self:Vis(id) == "self" then return true, id end
  for _, r in ipairs(revealsOf(id) or EMPTY) do
    local c, why = closed(self, r, seen)
    if c then return true, why end
  end
  -- (a stat in a category goes the category's way too, what the category reveals included; a parent's own choice Vis
  -- has walked up to already)
  local cat = catOf(C.Stats.byId[id])
  if cat then return closed(self, cat, seen) end
  return false
end
-- the route of a policy id: a stat's, a category's ("gc_bosses", "gc130")
local function routeOf(self, id)
  -- (the quick way for a stat that reveals nothing and has no category: most of them)
  local def = C.Stats.byId[id]
  if def and not def.reveals and not catOf(def) then return self:Vis(id) end
  return closed(self, id, {}) and "self" or "all"
end
-- the stat or category an Everyone choice is kept to the officers by (what this one would tell a member), nil where
-- it is not: for Settings, which shows the pair greyed with the reason
function P:KeptWith(id)
  if self:Vis(id) == "self" then return nil end
  local c, why = closed(self, id, {})
  if c and why ~= id then return why end
  return nil
end
-- a policy id as Settings names it: a stat's label, a discovered category's or a statistics category's name
function P:Label(id)
  local def = C.Stats.byId[id]
  if def then return def.label end
  for _, f in ipairs(C.Stats.FOUND) do if id == "gc_" .. f[1] then return f[2] end end
  local cat = tonumber(tostring(id):match("^gc(%d+)$"))
  local e = cat and C.Stats.game and C.Stats.game.byId[cat]
  return e and e.name or tostring(id)
end

-- where a value travels: "all", on the guild channel, or "self", whispered to the officers alone. Any id the wire
-- carries: a stat by its route (its visibility and what it reveals, above); a hidden one by the stat it travels with
-- (Stats.lua: the kinds of your enchanted items with Enchanted slots, the XP your level takes with the level); a
-- first kill's level (k<id>) with its boss; a discovered id this client has not defined by its category (an instance
-- whose kind is not known here for sure by the stricter of Dungeons and Raids: one member's label alone does not say
-- it, Stats.lua S.KindOf; a statistic by the strictest of the game's categories); a category id ("gc_bosses") by its own
local KIND_CAT = { party = "gc_dungeons", raid = "gc_raids" }
-- (whether any statistics category is closed, kept per version of what the policy says and of the table it says it in)
local catCache, catKey
local function anyCategoryClosed()
  local p = held()
  local key = tostring(p) .. tostring(p and p.vis) .. P.ver
  if catKey == key then return catCache end
  local out = false
  for k, v in pairs(p and type(p.vis) == "table" and p.vis or EMPTY) do
    if v == "self" and type(k) == "string" and k:match("^gc%d+$") then out = true end
  end
  catCache, catKey = out, key
  return out
end
function P:Route(id)
  if type(id) ~= "string" then return "all" end
  local def = C.Stats.byId[id]
  if def and def.with then return self:Route(def.with) end
  if def and not (def.learned and id:match("^i%d+$")) then return routeOf(self, id) end
  local p, n = id:match("^([efgikl])(%d+)$")
  if p == "k" or p == "l" then return self:Route("e" .. n) end
  -- (a statistic this client has not defined: its category is not known here, so it goes as the strictest of the
  -- game's categories the officers set)
  if p == "g" then return anyCategoryClosed() and "self" or "all" end
  if p == "e" then return routeOf(self, "gc_bosses") end
  if p == "f" then return routeOf(self, "gc_rep") end
  if p == "i" then
    local kind, sure = C.Stats.KindOf(tonumber(n))
    local cat = sure and KIND_CAT[kind or ""]
    if cat then return routeOf(self, cat) end
    return (routeOf(self, "gc_dungeons") == "self" or routeOf(self, "gc_raids") == "self") and "self" or "all"
  end
  if id:match("^gc") then return routeOf(self, id) end
  return "all"
end

----------------------------------------------------------------------------
-- Guild Info's line
----------------------------------------------------------------------------
local FP = string.rep("%x", 16)
-- a line of Guild Info that is Cute's: "Cute <format> <stamp> <ranks> <fingerprint>", a newer Cute's format included
local function cuteLine(l) return (l:gsub("\r$", "")):match("^Cute %d+ %w+ %d " .. FP) ~= nil end
-- the guild's text with Cute's line out, and the blank lines it ended on
local function guildText(text)
  local out = {}
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do if not cuteLine(l) then out[#out + 1] = l end end
  return (table.concat(out, "\n"):gsub("[\r\n]+$", ""))
end
-- Cute's line in a Guild Info text (the last, where an edit left two), as this client reads it: nil where there is
-- none; newer where its format is a newer Cute's; diff, the policy it carries, and fp its fingerprint, only where the
-- one is of the other. A line whose text does not match its fingerprint (one 0.6.0's first builds wrote with the
-- fingerprint alone, or an edit by hand) has no fp: it cannot be read, and an officer saves it again
local function parseLine(text)
  local found
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do if cuteLine(l) then found = (l:gsub("\r$", "")) end end
  if not found then return nil end
  local v, at, thr, fp, rest = found:match("^Cute (%d+) (%w+) (%d) (" .. FP .. ")%s*(.-)%s*$")
  if tonumber(v) ~= LINE_V then return { newer = (tonumber(v) or 0) > LINE_V, at = 0, thr = DEFAULT_THRESHOLD } end
  local line = { at = (C.Comm and C.Comm.unb36(at)) or 0, thr = tonumber(thr), fp = fp:lower() }
  if rest == "" or rest:gsub("[%+%-][%w_]+", "") == "" then
    local list = {}
    for t in rest:gmatch("[%+%-][%w_]+") do list[#list + 1] = t end
    local diff = canonical(list)
    if diff and P.Fingerprint(line.thr, diff) == line.fp then line.diff = diff end
  end
  if not line.diff then line.fp = nil end
  return line
end
P.ParseLine = parseLine
-- the line for a policy: its fingerprint, and what it holds (full false: the fingerprint alone, which no save writes
-- now and no client reads; the harness makes one)
local function lineText(at, thr, diff, full)
  local s = string.format("Cute %d %s %d %s", LINE_V, C.Comm.b36(at), thr, P.Fingerprint(thr, diff))
  if full and diff ~= "" then s = s .. " " .. diff end
  return s
end
P.LineText = lineText

-- the officer's own change not saved to Guild Info: made on the line this client held (or with none there), until the
-- line changes, and only while the line's officer ranks name this character an officer (the roster's rank: one
-- demoted keeps no change of theirs, which would keep the members' Only-you values on their client, or take them for
-- an officer still). Another officer's line that comes meanwhile wins. The saved variables are the account's: a change
-- is its author's (editBy), and another character of the account routes by the line (P:Settle parks the change for
-- its author)
local function ownEdit(p, line)
  if not (p and p.edit) then return false end
  if type(line) ~= "table" then return true end
  if p.editBy ~= nil and p.editBy ~= C.Me() then return false end
  local R = C.Roster
  if R and R.SelfKnown and R:SelfKnown() and R:MyRank() > (line.thr or DEFAULT_THRESHOLD) then return false end
  return p.base == line.fp
end
-- does this client hold the policy to route by: Guild Info read, and its line's policy held (or the officer's own
-- change of it), or no line there; and no officer's policy heard since that is newer than the line and not its (a save
-- this client has not read yet: P.doubt, until Guild Info reads again, which inside an instance may be the whole run).
-- Until then nothing of yours leaves but the ask (Comm.lua)
function P:Settled()
  local line = self.line
  if self.doubt then return false end
  if line == false then return true end
  if type(line) ~= "table" or line.newer or not line.fp then return false end
  local p = held()
  return ownEdit(p, line) or self:Fp(p) == line.fp
end

----------------------------------------------------------------------------
-- taking a policy
----------------------------------------------------------------------------
local function policy() CuteDB.policy = CuteDB.policy or { vis = {} }; return CuteDB.policy end
local function tbl(t) return type(t) == "table" and t or {} end
-- the rules and the untrusted held, each with when it was set: ruleAt[name] (a threshold put back to its default keeps
-- its stamp, its value gone), trustAt[GUID] (a member trusted again keeps theirs). One held from before item stamps
-- takes the stamp of the word it came with
local function stampItems(p)
  local at = tonumber(p.at) or 0
  p.rules, p.ruleBy, p.ruleAt, p.untrusted, p.trustAt = tbl(p.rules), tbl(p.ruleBy), tbl(p.ruleAt), tbl(p.untrusted), tbl(p.trustAt)
  for name in pairs(p.rules) do if not tonumber(p.ruleAt[name]) then p.ruleAt[name] = at end end
  for g in pairs(p.untrusted) do if not tonumber(p.trustAt[g]) then p.trustAt[g] = at end end
end
-- an officer's word (h) into the policy held, item by item: a rule or a mark newer than the one held wins (of the same
-- second, the higher value, and untrusted over trusted, so every client ends on the same), an item the word does not
-- name is left as it is. True where something changed
local function mergeWord(p, h)
  local changed = false
  for name, v in pairs(h.rules) do
    local at, was = tonumber(h.ruleAt[name]) or h.at, tonumber(p.ruleAt[name]) or -1
    local val = v or nil
    if at > was or (at == was and tostring(val or "") > tostring(p.rules[name] or "")) then
      if p.rules[name] ~= val then changed = true end
      p.rules[name], p.ruleBy[name], p.ruleAt[name] = val, val and h.ruleBy[name] or nil, at
    end
  end
  for g, on in pairs(h.untrusted) do
    local at, was = tonumber(h.trustAt[g]) or h.at, tonumber(p.trustAt[g]) or -1
    if at > was or (at == was and on and not p.untrusted[g]) then
      if (p.untrusted[g] == true) ~= on then changed = true end
      p.untrusted[g], p.trustAt[g] = on or nil, at
    end
  end
  return changed
end
-- the routing: the visibility and the ranks, as their text says
local function takeRouting(p, thr, diff)
  p.threshold, p.diff = thr, diff
  p.vis, p.extra = visOf(diff)
  p.edit, p.base, p.editBy = nil, nil, nil
end
-- the newest officers' word, from an officer's policy (h, heard from sender): when it was said and by whom, and where
-- the guild has no line its routing too, its officer ranks no lower than the sender's own rank (no officer makes the
-- officers of their own rank members, which only the guild master could undo). Its rules and untrusted go item by item
-- (mergeWord), as every officer's do
local function takeWord(h, sender, routing)
  local p = policy()
  local rank = C.Roster:Rank(sender)
  p.at, p.by, p.rank, p.mine, p.wordFp = h.at, sender, rank, nil, h.fp
  if routing then takeRouting(p, (rank and h.thr < rank) and rank or h.thr, h.diff) end
end

-- what the line and the policies heard say now, applied: the officers' word from the newest an officer sent (the
-- roster names the sender one; one this client holds stamped past the server's clock from before gives way to any
-- officer's), once Guild Info has been read, for where it has no line the word brings the routing too, and the rules
-- and the untrusted item by item from every officer's; and the routing from Guild Info: the policy its line carries
-- (never one heard on the guild channel). Every change reroutes what this client sends (P:Rerouted), and whether it is
-- settled goes to Comm.lua. Run as the roster comes (Roster.lua), as a policy comes whole, and on a save
function P:Settle()
  if type(CuteDB) ~= "table" then return end
  local p, line, R = held(), self.line, C.Roster
  local before, items
  if p then stampItems(p) end
  -- (an officer whose word counts: the line's ranks name the sender one, and the officers have not marked it untrusted)
  local function voice(sender) return R:IsOfficer(sender) and not self:Untrusted(R:GuidOf(sender)) end
  local lost = R.lostUnsettled
  if R.trusted and line ~= nil then
    local now = C.ServerNow()
    local at = (p and tonumber(p.at)) or 0
    if at > now + AHEAD then at = 0 end
    local wfp = (p and p.wordFp) or self:Fp(p)
    local best, from
    for sender, h in pairs(self.heard) do
      if voice(sender) then
        -- (an officer's word at least as new as the one held: what this client holds is the officers' newest)
        if h.at >= at then self.confirmed = true end
        if (h.at > at or (h.at == at and h.at > 0 and less(wfp, h.fp))) and (not best or h.at > best.at or (h.at == best.at and less(best.fp, h.fp))) then best, from = h, sender end
      end
    end
    if best then
      before = self:Snapshot()
      takeWord(best, from, line == false)
      p = held()
    end
    for sender, h in pairs(self.heard) do
      if voice(sender) then p = policy(); stampItems(p); if mergeWord(p, h) then items = true end end
    end
  end
  local readable = type(line) == "table" and line.fp and line.diff and not line.newer
  -- (a change that says what the line says is no change)
  if readable and p and p.edit and not ownEdit(p, line) and self:Fp(p) == line.fp then p.edit, p.base, p.editBy = nil, nil, nil end
  -- (another character's change: kept for its author, who finds it again at their next login while the line stands;
  -- this character routes by the line, and is told nothing)
  if readable and p and p.edit and p.editBy ~= nil and p.editBy ~= C.Me() then
    before = before or self:Snapshot()
    p.drafts = type(p.drafts) == "table" and p.drafts or {}
    p.drafts[p.editBy] = { base = p.base, threshold = thrOf(p), diff = self:Diff(p) }
    takeRouting(policy(), line.thr, line.diff)
  end
  -- (this character's change, parked while another character of the account was logged in: back where the line it was
  -- made on is still Guild Info's; where another officer saved since, it gave way, and its author is told)
  local draft = readable and p and type(p.drafts) == "table" and p.drafts[C.Me()]
  if draft then
    p.drafts[C.Me()] = nil
    if next(p.drafts) == nil then p.drafts = nil end
    if type(draft) == "table" and draft.base == line.fp and type(draft.diff) == "string" then
      before = before or self:Snapshot()
      p.threshold, p.diff, p.vis, p.extra = tonumber(draft.threshold) or line.thr, draft.diff, visOf(draft.diff)
      p.edit, p.base, p.editBy = true, draft.base, C.Me()
    else
      C.Print("another officer saved the policy to Guild Info: your change, not saved, gave way to it.")
    end
  end
  if readable and not ownEdit(p, line) and self:Fp(p) ~= line.fp then
    before = before or self:Snapshot()
    -- (an officer's own change, not saved, gives way to the line another officer saved, or to its ranks, which name
    -- this character no officer: said once, in chat)
    if p and p.edit then
      C.Print(p.base == line.fp and "Guild Info's officer ranks do not include yours: your change, not saved, gave way to its policy."
        or "another officer saved the policy to Guild Info: your change, not saved, gave way to it.")
    end
    takeRouting(policy(), line.thr, line.diff)
  end
  if before then self:Rerouted(before) end
  if before or items then
    if items then self.ver = self.ver + 1 end
    if C.Roster then C.Roster:Changed() end
    if C.Rules then C.Rules:Retuned() end
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
  local settled = self:Settled()
  if settled ~= self.settled then
    self.settled = settled
    if C.Comm and C.Comm.PolicySettled then C.Comm:PolicySettled(settled) end
  end
  -- (a member's client that dropped a value while it waited for Guild Info or routed by the line from before, a stat
  -- the officers opened meanwhile sent once by every client: asked for again, once, as the doubt ends or the line
  -- changes, so what rarely changes comes again)
  if settled and (self.doubtEnded or self.lineChanged) then
    if lost and C.Comm and C.Comm.Ask and C.Comm.hello and not R:MeOfficer() then
      R.lostUnsettled = nil
      C.Comm:Ask()
    end
    self.doubtEnded, self.lineChanged = nil, nil
  end
end

-- Guild Info read (C_GuildInfo.GetInfoText, documented; HasRestrictions, so under pcall, and a secret is no answer), as
-- Blizzard_Communities/GuildInfo.lua reads it: when the roster comes (Roster.lua, on GUILD_ROSTER_UPDATE alone; on
-- PLAYER_GUILD_UPDATE Blizzard's panel reads only its permissions, and Cute asks for the roster). Inside an instance an
-- empty text may be the restriction's: no answer. Where a read says nothing the client waits for one that says
-- something (outside, after the encounter), a /reload and a relog included: no line read in an earlier session stands
-- for this one (0.6.0's first builds brought back the line read in the last ten minutes, and a client that was away
-- when an officer saved, or that had read a guild with no line, sent what the officers had just closed on GUILD). A
-- read that says something ends the doubt an officer's newer policy raised (P.doubt). A client without the call has no
-- line.
-- The game also says the roster changed (GUILD_ROSTER_UPDATE, which Blizzard's panels answer by asking for it again)
-- before the new text has come, so a read may be the game's copy from before. An empty text outside an instance,
-- unless a read this session found no line already, is taken as no line only from a read eleven seconds after an ask
-- made since the first (LINE_WAIT, as a line waited for is judged). While this client waits for a line (an officer's
-- newer policy heard, P.doubt, or its own save), a read of the line it held then is no answer until eleven seconds
-- after the first ask made since (LINE_WAIT; the ask once more twelve seconds on, Roster.lua R:AskSoon, is that read):
-- the game answers a roster ask with the text it has, so a line not changed by then is the server's (the game did not
-- take a save). Such a read changes nothing, the doubt included. The doubt, the wait and the last line read are kept
-- with the guild in the saved variables (kept, below): a /reload or a relog changes nothing, and a guild that had a
-- line and reads none has its line missing (P.missing), never no line
local LINE_WAIT = 11
local function sameLine(a, b)
  if a == b then return true end
  return type(a) == "table" and type(b) == "table" and a.fp == b.fp and a.at == b.at and a.diff == b.diff and a.newer == b.newer
end
local function copyLine(l)
  if type(l) ~= "table" then return l end
  return { fp = l.fp, at = l.at, thr = l.thr, diff = l.diff, newer = l.newer }
end
-- what this client knows of the guild's line from one session to the next, per guild (CuteDB.lines[club]): line, the
-- last line read or saved, so a guild that had one is never taken for one without; doubt, whether this client waits
-- for Guild Info to be read again (an officer's newer policy heard, the line missing); wait, the line (or false, none)
-- a read of which is no answer while the wait runs. A /reload or a relog changes nothing: a client in doubt stays in
-- doubt until a read outside an instance confirms a line (0.6.0's first builds kept the doubt in memory alone, and a
-- /reload took the game's copy from before as the line: a value the officers had just closed went on GUILD)
local function kept()
  if type(CuteDB) ~= "table" or not (C.Roster and C.Roster.ClubId) then return nil end
  local club = C.Roster:ClubId()
  if club == nil then return nil end
  CuteDB.lines = type(CuteDB.lines) == "table" and CuteDB.lines or {}
  local k = CuteDB.lines[tostring(club)]
  if type(k) ~= "table" then k = {}; CuteDB.lines[tostring(club)] = k end
  return k
end
-- does a policy (h: thr, diff) keep anything to the officers that the line does not: a stat or category it closes
-- that the line does not, one the line opens that it does not, or fewer officer ranks (a rank the line makes an
-- officer, whispered to, would be a member's). Where it does not, routing by the line sends nothing h closes, so no
-- doubt is raised for it: an officer who missed a save and clicks a rule or Broadcast sends the old line's routing
-- stamped now, and 0.6.0's first builds put every member in doubt for it, those inside an instance the whole run
local function tokens(diff)
  local t = {}
  for s in (diff or ""):gmatch("[%+%-][%w_]+") do t[s] = true end
  return t
end
local function stricter(h, line)
  if (tonumber(h.thr) or 0) < (tonumber(line.thr) or 0) then return true end
  local a, b = tokens(h.diff), tokens(line.diff)
  for t in pairs(a) do if t:sub(1, 1) == "-" and not b[t] then return true end end
  for t in pairs(b) do if t:sub(1, 1) == "+" and not a[t] then return true end end
  return false
end
-- an officer whose policy and word count: the line's ranks name the sender one, and the officers have not marked it
-- untrusted (one they did is as good as absent)
local function voice(self, sender)
  local R = C.Roster
  return R:IsOfficer(sender) and not self:Untrusted(R:GuidOf(sender))
end
-- an officer's policy heard that is newer than the line, not its, and stricter: maybe a line saved that this client
-- has not read yet (a 1P that came before the first read of the session, or a read of the game's copy from before)
local function doubtful(self, line)
  if not (type(line) == "table" and line.fp and line.diff) then return false end
  for sender, h in pairs(self.heard) do
    if h.at > (line.at or 0) and h.fp ~= line.fp and stricter(h, line) and voice(self, sender) then return true end
  end
  return false
end
-- nothing of yours leaves until Guild Info is read again (P.doubt), and a read of the line held now is no answer for
-- a while (P.waitFor; a wait running is never replaced: the officer who saved waits for the line from before, whatever
-- another officer sends meanwhile). Kept with the guild (kept), so a /reload changes nothing
local function raiseDoubt(self, line)
  self.doubt = true
  if not self.waitFor then self.waitFor = { old = copyLine(line), at = C.Now() } end
  local k = kept()
  if k then
    k.doubt = true
    if k.wait == nil then k.wait = copyLine(self.waitFor.old) end
  end
  if C.Roster.AskSoon then C.Roster:AskSoon(function() return P.doubt == true end) end
end
-- an officer's policy heard that is newer than the line and not its, stricter or not: maybe a line saved that this
-- client has not read yet, so no save of this client's own goes over it until a read confirms the line (P:SaveState;
-- a read of the line held now is no answer for a while, as a line waited for is judged). Kept with the guild (kept).
-- The doubt is the members' (raiseDoubt: a policy no stricter closes nothing the line sends); this is the officers'
-- (0.6.0's first builds let a second officer, holding the game's copy from before and an unsaved change, save over
-- a line another officer had saved two seconds before, the other's stat opened again with nobody told)
local function raiseUnread(self, line)
  if self.unread then return end
  self.unread = { old = copyLine(line), at = C.Now() }
  local k = kept()
  if k then k.unread = copyLine(line) end
  if C.Roster.AskSoon then C.Roster:AskSoon(function() return P.unread ~= nil end) end
end
-- an ask for the roster went (Roster.lua): the first since a wait began is what that wait's reads are judged by
function P:Asked()
  local t = C.Now()
  if self.waitFor and not self.waitFor.asked then self.waitFor.asked = t end
  if self.emptyWait and not self.emptyWait.asked then self.emptyWait.asked = t end
  if self.unread and not self.unread.asked then self.unread.asked = t end
end
-- the first read of a session: the doubt and the wait of the last one go on (kept), the officers' wait for a read
-- (unread) and the save whose read-back had not come (saved) too, and the roster, Guild Info with it, is asked for
-- again so that a read after that ask can end them
local function restore(self)
  if self.restored then return end
  self.restored = true
  local k = kept()
  if not k then return end
  if k.doubt then self.doubt = true end
  if k.wait ~= nil and not self.waitFor then self.waitFor = { old = copyLine(k.wait), at = C.Now() } end
  if k.unread ~= nil and not self.unread then self.unread = { old = copyLine(k.unread), at = C.Now() } end
  if type(k.saved) == "table" and k.saved.fp and not self.saved then
    local s = {}
    for f, v in pairs(k.saved) do s[f] = v end
    s.at = C.Now()
    self.saved = s
  end
  if (self.doubt or self.waitFor or self.unread) and C.Roster.AskSoon then C.Roster:AskSoon(function() return P.doubt == true or P.waitFor ~= nil or P.unread ~= nil end) end
end
-- the first reads after a save say whether Guild Info kept it, for a minute (SAVED_WINDOW: the read-back comes
-- within half of it, a /reload or a relog meanwhile included, the save kept with the guild). A read whose line is
-- neither the one saved nor the one saved over is another officer's, saved over it (the same second, before either
-- heard the other's policy; or one that missed it): the officer is told, and the change is made again on that line,
-- not saved, where the line does not say it already and the other officer's save did not touch the same thing (theirs
-- is the newer intent there), for the officer to save again. A read whose line is the one from before (or none,
-- where there was none) is the game's refusal: told, and the change back, not saved (0.6.0's first builds said
-- "does not hold" once, of either, and the change was gone; a relog within the wait said nothing at all)
local SAVED_WINDOW = 60
local function byCodes(diff)
  local t = {}
  for s in (diff or ""):gmatch("[%+%-][%w_]+") do t[s:sub(2)] = s end
  return t
end
-- the codes a save changed from the line it was made on, each with the token saved (false: back to the default); and
-- whether it changed the officer ranks
local function changeOf(s)
  local base, saved, out = byCodes(s.baseDiff), byCodes(s.diff), {}
  for code, t in pairs(base) do if saved[code] ~= t then out[code] = saved[code] or false end end
  for code, t in pairs(saved) do if base[code] ~= t then out[code] = t end end
  return out, s.thr ~= s.baseThr
end
-- the change a save made, put back on the line read (false: none) as this officer's change, not saved. Whether
-- something is back, and whether the line says the whole change already
local function putBack(self, s, line)
  local change, thrChanged = changeOf(s)
  local lineDiff, lineThr, lineFp = s.baseDiff, s.baseThr, nil
  if type(line) == "table" then lineDiff, lineThr, lineFp = line.diff or "", line.thr or DEFAULT_THRESHOLD, line.fp end
  local lineBy, base = byCodes(lineDiff), byCodes(s.baseDiff)
  local list, back, stands = {}, false, true
  for code, t in pairs(lineBy) do list[code] = t end
  for code, t in pairs(change) do
    local want = t or nil
    if lineBy[code] ~= want then
      stands = false
      if lineBy[code] == base[code] then list[code] = want; back = true end
    end
  end
  local thr = lineThr
  if thrChanged and lineThr ~= s.thr then
    stands = false
    if lineThr == s.baseThr then thr = s.thr; back = true end
  end
  if not back then return false, stands end
  local toks = {}
  for _, t in pairs(list) do toks[#toks + 1] = t end
  local diff = canonical(toks) or lineDiff
  local before = self:Snapshot()
  local p = policy()
  stampItems(p)
  p.threshold, p.diff, p.vis, p.extra = thr, diff, visOf(diff)
  p.edit, p.base, p.editBy = true, lineFp, C.Me()
  p.wordFp = self:Fp(p)
  self:Rerouted(before)
  if C.UI and C.UI.Refresh then C.UI:Refresh() end
  return true, false
end
local function readBack(self, s, line, k, now)
  local holds = type(line) == "table" and line.fp == s.fp
  if holds then
    if now - s.at < SAVED_WINDOW then return end
  elseif line == false and s.base then
    -- (the line gone: the missing line's own words, below, which offer Save, the change still held)
    return
  end
  self.saved = nil
  if k then k.saved = nil end
  if holds then return end
  if type(line) == "table" and line.fp and line.fp ~= s.base then
    local back, stands = putBack(self, s, line)
    C.Print(stands and "another officer saved Guild Info since your save: your change stands in their line."
      or back and "another officer saved over your save: your change is back on their line, not saved. Save it again."
      or "another officer saved over your save: their line says otherwise, and your change gave way to it.")
  else
    putBack(self, s, line)
    C.Print("Guild Info does not hold the policy you saved: the game did not take it. Your change is back, not saved: save it again.")
  end
end
function P:ReadLine()
  local fn = type(C_GuildInfo) == "table" and C_GuildInfo.GetInfoText or nil
  local line, k
  if type(fn) ~= "function" then
    if self.line ~= nil then return end
    line = false
  else
    if self.line == nil then restore(self) end
    k = kept()
    local ok, text = pcall(fn)
    local usable = ok and not (issecretvalue and issecretvalue(text)) and type(text) == "string"
    local now = C.Now()
    if usable then
      line = parseLine(text) or false
      if not line and text == "" and self.line ~= false then
        if C.Get(IsInInstance) == true then usable = false
        else
          local w = self.emptyWait
          if not w then
            w = { at = now }
            self.emptyWait = w
            if C.Roster.AskSoon then C.Roster:AskSoon(function() return P.emptyWait ~= nil end) end
          end
          -- (judged as a line waited for is: usable only from a read eleven seconds after an ask made since; the
          -- game's "the roster changed" a second after an ask it never answered said "no line" before)
          if not (w.asked and now - w.asked >= LINE_WAIT) then usable = false end
        end
      end
    end
    local w = self.waitFor
    local awaited
    if usable and w then
      if sameLine(line, w.old) and not (w.asked and now - w.asked >= LINE_WAIT) then return end
      awaited = w.old
      self.waitFor = nil
    end
    if not usable then return end
    if self.doubt then self.doubtEnded = true end
    self.doubt, self.emptyWait = nil, nil
    -- (the officers' wait for a read ends as a line waited for does: another line, or the one held eleven seconds
    -- after an ask made since)
    local u = self.unread
    if u and (not sameLine(line, u.old) or (u.asked and now - u.asked >= LINE_WAIT)) then
      self.unread = nil
      if k then k.unread = nil end
    end
    -- (the first reads after a save say whether Guild Info kept it)
    if self.saved then readBack(self, self.saved, line, k, now) end
    if line == false and k and type(k.line) == "table" then
      -- (Guild Info had Cute's line and has none now, deleted by hand or wiped with the text: not a guild without a
      -- line, but one whose line is missing. The last line read routes, nothing of yours leaves, and the officers are
      -- asked to save it again, in Settings and once in chat; a brand-new client, which never read the line, cannot
      -- know one existed)
      line = type(self.line) == "table" and self.line or copyLine(k.line)
      if not self.missing then
        self.missing = true
        if text ~= "" and C.Roster:MeOfficer() then C.Print("Cute's line is missing from Guild Info; Save to Guild Info to put it back.") end
      end
      self.doubt = true
      k.doubt, k.wait = true, nil
    else
      self.missing = nil
      if k then
        k.doubt, k.wait = nil, nil
        if type(line) == "table" then k.line = copyLine(line) end
      end
    end
    local old = self.line
    if sameLine(old, line) then return end
    self.line = line
    self.ver = self.ver + 1
    if type(old) == "table" and type(line) == "table" then self.lineChanged = true end
    -- (an officer's newer policy heard before this read, and the read not the line it waited for: the doubt rises now)
    if not self.missing and not sameLine(awaited, line) and doubtful(self, line) then raiseDoubt(self, line) end
    return
  end
  local old = self.line
  if sameLine(old, line) then return end
  self.line = line
  self.ver = self.ver + 1
end
-- the officer ranks this client holds may be older than the officers': a guild with no line, this character an officer
-- at its last login, and no officer's word heard this session at least as new. Its saved file is an officer's, and
-- the first purge waits (Roster.lua R:PurgeCheck): a threshold the officers raised while it was away keeps it one. For
-- half a minute after the hello at most (UNCONFIRMED: the answers to its ask are in by then; an officer holding a word
-- as new answers none), then the ranks it holds decide
local UNCONFIRMED = 30
P.UNCONFIRMED = UNCONFIRMED
function P:Unconfirmed()
  if self.line ~= false or self.confirmed then return false end
  local hello = C.Comm and C.Comm.helloAt
  if hello and C.Now() - hello >= UNCONFIRMED then return false end
  local club = C.Roster:ClubId()
  return club ~= nil and C.Char().officerOf == club
end
-- the roster came: Guild Info read where the event says it may have changed, then what it says applied
function P:Refresh(read)
  if read then self:ReadLine() end
  self:Settle()
end

-- a policy from the guild channel, from any sender: its parts gathered by sender and stamp (part i of n), and taken
-- once whole: kept as that sender's newest (P.heard), then applied by what it is (P:Settle): the officers' word where
-- the roster names its sender an officer, its routing too where the guild has no line. The policy whole (for Comm.lua's
-- answers), or false and why
function P:Receive(sender, at, thr, body, part, parts)
  at, thr, part, parts = tonumber(at), tonumber(thr), tonumber(part or 1), tonumber(parts or 1)
  if not (at and thr and part and parts) or thr < 0 or thr > 9 or at < 0 or part < 1 or part > parts or parts > 64 then return false, "malformed" end
  if type(sender) ~= "string" then return false, "malformed" end
  local a = self.parts[sender]
  if not a or a.at ~= at or a.thr ~= thr or a.n ~= parts then
    a = { at = at, thr = thr, n = parts, got = {}, have = 0, tokens = {}, rules = {}, ruleBy = {}, ruleAt = {}, untrusted = {}, trustAt = {}, nu = 0 }
  end
  if a.got[part] then return false, "held" end
  a.got[part], a.have = true, a.have + 1
  for kv in (body or ""):gmatch("[^;]+") do
    if kv:match("^[%+%-][%w_]+$") then
      if #a.tokens < PARTS_CAP and #kv <= 24 then a.tokens[#a.tokens + 1] = kv end
    else
      -- (a rule "r_<name>=<value>:<who>@<when>", "-" its default again, as a value out of its bounds here is; a member
      -- "u=<GUID>@<when>" untrusted, "t=" trusted again; when in base 36, the word's own where none is said)
      local lname, v, who, when = kv:match("^r_(%l+)=([%d%.%-]+):?([%w%-]*)@?(%w*)$")
      local name, value = lname and C.Rules and C.Rules.LOWER[lname], tonumber(v)
      if name then
        local ok = value ~= nil and C.Rules.Valid(name, value)
        a.rules[name] = ok and value or false
        a.ruleBy[name] = (ok and who ~= "") and who:sub(1, 40) or nil
        -- (an item's stamp no later than its word's: one stamped ahead would win over every change made since)
        local w = tonumber(when, 36)
        a.ruleAt[name] = w and math.min(w, at) or nil
      end
      local mark, g, gwhen = kv:match("^([ut])=([%w%-]+)@?(%w*)$")
      if g and a.nu < 1000 then
        g = g:sub(1, 40)
        local w = tonumber(gwhen, 36)
        a.untrusted[g], a.trustAt[g], a.nu = mark == "u", w and math.min(w, at) or nil, a.nu + 1
      end
    end
  end
  if a.have < a.n then self.parts[sender] = a; return false, "waiting for its other parts" end
  self.parts[sender] = nil
  local diff = canonical(a.tokens)
  if not diff then return false, "malformed" end
  -- (one stamped more than a minute past the server's clock is no honest client's: not kept, and its sender marked)
  if at > C.ServerNow() + AHEAD then C.Roster:Forged(sender, "sent a policy stamped ahead of the server's clock", true); return false, "stamped ahead" end
  local h = { at = at, thr = thr, diff = diff, fp = P.Fingerprint(thr, diff), rules = a.rules, ruleBy = a.ruleBy, ruleAt = a.ruleAt,
    untrusted = a.untrusted, trustAt = a.trustAt }
  local old = self.heard[sender]
  if not old or old.at <= at then self.heard[sender] = h end
  -- (an officer's policy newer than the line, not its and stricter: maybe a line just saved, so nothing of yours goes
  -- until Guild Info is read again (P.doubt, a read of the line held now no answer for a while, P:ReadLine), and the
  -- roster, Guild Info with it, is asked for again soon. One no stricter than the line closes nothing the line sends,
  -- so it raises no doubt (an officer who missed a save sends the old line's routing). A member's policy, or an
  -- untrusted officer's, asks for nothing: only an officer can save a line, and an officer promoted since the last
  -- read is one at the next minute's)
  local R = C.Roster
  local officer = voice(self, sender)
  local line = self.line
  local newer = officer and not self.missing and type(line) == "table" and line.fp and h.at > (line.at or 0) and h.fp ~= line.fp and self.heard[sender] == h
  if newer and stricter(h, line) then raiseDoubt(self, line) end
  -- (stricter or not, no save of this client's own over a line it may not have read yet: raiseUnread)
  if newer then raiseUnread(self, line) end
  self:Settle()
  local function unnamed() return self.line ~= nil and not (self.line and self.line.fp == h.fp) and self.heard[sender] == h end
  -- (while the line is missing an officer's policy may be the save that puts it back, the same policy or not)
  if officer and (unnamed() or self.missing) and R.AskSoon then R:AskSoon(function() return P.missing or unnamed() end) end
  return h
end

-- the policy as pieces for the wire: when the officers' word was set, the officer ranks, and the parts: what differs
-- from the defaults, a token each ("+go", "-zo"), then the rules' "r_<name>=<value>:<who>@<when>" (the name lower case,
-- who a GUID, when in base 36; "-" for one put back to its default) and the untrusted "u=<GUID>@<when>" ("t=" for one
-- trusted again). An officer's change not saved stays on their client: while one is pending the routing sent is the
-- line's (members take none from the guild channel where there is a line, and an officer's policy not the line's makes
-- them wait for Guild Info, P.doubt)
local function ruleText(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return (string.format("%.2f", v):gsub("0+$", ""))
end
local function stampText(at) return "@" .. C.Comm.b36(tonumber(at) or 0) end
function P:Parts()
  local p = held()
  local parts = {}
  local line = self.line
  local thr, diff = thrOf(p), self:Diff(p)
  if type(line) == "table" and line.diff and ownEdit(p, line) then thr, diff = line.thr, line.diff end
  for t in diff:gmatch("[%+%-][%w_]+") do parts[#parts + 1] = t end
  if p then
    stampItems(p)
    local rest = {}
    for g, at in pairs(p.trustAt) do
      local clean = type(g) == "string" and g:gsub("[^%w%-]", ""):sub(1, 40) or ""
      if clean ~= "" then rest[#rest + 1] = (p.untrusted[g] == true and "u=" or "t=") .. clean .. stampText(at) end
    end
    for name, at in pairs(p.ruleAt) do
      local v = tonumber(p.rules[name])
      if type(name) == "string" and C.Rules and C.Rules.TUNE_BY[name] then
        if v and C.Rules.Valid(name, v) then
          local by = p.ruleBy[name]
          by = (by == "me" and C.MyGUID()) or by
          rest[#rest + 1] = "r_" .. name:lower() .. "=" .. ruleText(v) .. ((type(by) == "string" and by ~= "") and (":" .. by:gsub("[^%w%-]", "")) or "") .. stampText(at)
        elseif p.rules[name] == nil then
          rest[#rest + 1] = "r_" .. name:lower() .. "=-" .. stampText(at)
        end
      end
    end
    table.sort(rest)
    for _, x in ipairs(rest) do parts[#parts + 1] = x end
  end
  return (p and tonumber(p.at)) or 0, thr, parts
end
-- the stamp of the officers' word this client holds, which an ask carries (an officer whose word is newer answers)
function P:Stamp() local p = held(); return (p and tonumber(p.at)) or 0 end
-- the policy Guild Info names is the one held (Settings, /cute diag)
function P:Holds()
  local line = self.line
  return type(line) == "table" and line.fp ~= nil and not line.newer and not self.missing and not ownEdit(held(), line) and self:Fp() == line.fp
end

----------------------------------------------------------------------------
-- the officers' changes, made here
----------------------------------------------------------------------------
-- (routing: a change of the visibility or the ranks, which is not saved to Guild Info until the officer saves it, and
-- routes on this client alone until then where the guild has a line. Made on the line held now, by this character: a
-- change from before the line, or another character's, is made again on it)
local function edit(routing)
  local p = policy()
  stampItems(p)
  p.vis = type(p.vis) == "table" and p.vis or {}
  if routing and not ownEdit(p, P.line) then p.edit, p.base, p.editBy = true, type(P.line) == "table" and P.line.fp or nil, C.Me() end
  P.ver = P.ver + 1
  return p
end
-- who sees what is changed only once Guild Info has been read (with no line there, or a line this client can read):
-- a change made before would be made on no line, and give way to the first one read as if another officer had saved it
local function editable(id)
  local line = P.line
  if line == nil or (type(line) == "table" and (line.newer or not line.fp)) then return false end
  return id == nil or not unset(C.Stats.byId[id])
end
P.Editable = function() return editable() end
local function mine(p, routing)
  p.by, p.mine, p.rank, p.at = C.Me(), true, C.Roster:MyRank(), math.floor(C.ServerNow())
  p.threshold = thrOf(p)
  if routing then p.diff = diffOf(p.vis, p.extra) end
  p.wordFp = P:Fp(p)
  -- (back to what Guild Info says: no change of yours)
  if p.edit and type(P.line) == "table" and p.wordFp == P.line.fp then p.edit, p.base, p.editBy = nil, nil, nil end
end
function P:Set(id, vis)
  assert(vis == "all" or vis == "self")
  if not editable(id) then return false end
  local before = self:Snapshot()
  local p = edit(true)
  p.vis[id] = vis
  mine(p, true)
  self:Rerouted(before)
  return true
end
-- the officer ranks, never above your own: an officer who lowered them past their own rank would make every officer
-- of that rank a member on every client, their saved values deleted, and only the guild master could put it back.
-- False where refused
function P:SetThreshold(n)
  local rank = C.Roster:MyRank()
  if type(n) ~= "number" or n < 0 or n > 9 or not rank or n < rank or not editable() then return false end
  local before = self:Snapshot()
  local p = edit(true)
  p.threshold = n
  mine(p, true)
  self:Rerouted(before)
  return true
end
-- the policy held, stamped now as yours (Broadcast now): the officers' word sent again, newer than any
function P:Restamp()
  local p = edit(false)
  mine(p)
end
-- the whole visibility list back to the registry's defaults (Settings), the ranks, the rules and the untrusted kept
function P:Reset()
  if not editable() then return false end
  local before = self:Snapshot()
  local p = edit(true)
  p.vis, p.extra = {}, {}
  mine(p, true)
  self:Rerouted(before)
  return true
end

-- untrusted members, by GUID: the officers' word (the Officers page), which travels with the policy as "u=<GUID>"
-- parts ("t=" for one trusted again), each with when it was set. An untrusted member is left out of what the guild
-- learns (Rules.lua, the enchants in Stats.lua) and of the rankings (UI.lua); their row says so to the officers
function P:UntrustedSet()
  local p = CuteDB and CuteDB.policy
  return (p and type(p.untrusted) == "table") and p.untrusted or EMPTY
end
function P:Untrusted(guid) return type(guid) == "string" and self:UntrustedSet()[guid] == true end
function P:SetUntrusted(guid, on)
  if type(guid) ~= "string" or guid == "" then return end
  local p = edit(false)
  p.untrusted[guid], p.trustAt[guid] = on and true or nil, math.floor(C.ServerNow())
  mine(p)
  if C.Rules then C.Rules:Retuned() end
  if C.Roster then C.Roster:Changed() end
end
-- a threshold an officer set here: nil puts the default back. Who set each is kept by GUID, and travels with it
function P:SetRule(name, value)
  local p = edit(false)
  p.rules[name], p.ruleAt[name] = value, math.floor(C.ServerNow())
  p.ruleBy[name] = value ~= nil and (C.MyGUID() or "me") or nil
  mine(p)
  if C.Rules then C.Rules:Retuned() end
end

-- an officer's change of who sees what not saved yet where the guild has a line (Rules.lua: the officers' word then
-- says everything, so no member loses what it learned from the saved one by a change the members do not route by)
function P:EditPending() return type(self.line) == "table" and ownEdit(held(), self.line) end
-- what the members go by: the line's policy, the officer's own change not saved set aside (fn run with it held). The
-- tooltips on an officer's client say what the members see of a stat and what their Ready counts, and mark the
-- officer's change as not saved yet (0.6.0's first builds said "Everyone sees this" of a stat the officer had just
-- opened without saving, while every member's client still whispered it)
local function byLine(self, fn, ...)
  local line = self.line
  if not (type(line) == "table" and line.diff and self:EditPending()) then return fn(...) end
  local keep = CuteDB.policy
  CuteDB.policy = { vis = (visOf(line.diff)), threshold = line.thr }
  local ok, out = pcall(fn, ...)
  CuteDB.policy = keep
  if not ok then error(out, 0) end
  return out
end
-- the gaps Ready counts by the line's policy: what the members' clients count their Ready by (UI.lua, the tooltip of a
-- member's Ready on an officer's client, which said gaps the verdict beside it never counted)
function P:LineReadyCounts() return byLine(self, C.Stats.ReadyCounts) end
-- where a stat travels on the members' clients, and the stat it is kept with there
function P:LineRoute(id) return byLine(self, function() return self:Route(id) end) end
function P:LineKeptWith(id) return byLine(self, function() return self:KeptWith(id) end) end
-- the officer's own change, not in Guild Info yet (or the guild has no line, or its line is missing): Settings offers
-- to save it
function P:Unsaved()
  local p = held()
  if self.line == false or self.missing then return true end
  return type(self.line) == "table" and ((p and p.edit) or self.line.newer or not self.line.fp or false)
end
-- what saving would write (Settings shows it, and P:Save writes it): the whole Guild Info, the guild's own text as it
-- is with Cute's line at its end in place of the one there, the policy itself in the line (P.INFO_MAX); where
-- it does not fit, nothing (the guild shortens its text). Never inside an instance, where Guild Info may read empty
-- (P:ReadLine): the guild's text would be lost. Nor while this client waits for Guild Info to be read again (another
-- officer's newer policy heard, stricter, P.doubt, or not, P.unread, or its own save not read back yet), nor where
-- the text the game holds has another line than the one this client routes by: a save then would write over a line
-- saved seconds before, unseen (0.6.0's first builds took it, and another officer's closed stat opened again with
-- nobody told; a save in the same second, before either officer heard the other, is told at the read-back, P.saved).
-- ok where this client may save it; why where not
function P:SaveState()
  local st = { ok = false }
  local p = held()
  local thr, diff, at = thrOf(p), self:Diff(p), math.floor(C.ServerNow())
  if self.line == nil then st.why = "Guild Info has not been read yet." return st end
  if self.line and self.line.newer then st.why = "Guild Info's line is a newer Cute's: update Cute to change it." return st end
  if C.Get(IsInInstance) == true then st.why = "Save outside an instance: Guild Info may read empty here." return st end
  if self.doubt and not self.missing then st.why = "Another officer saved Guild Info since you read it: wait a moment." return st end
  if self.unread and not self.missing then st.why = "Another officer's policy came since you read Guild Info: wait a moment." return st end
  if self.waitFor then st.why = "Guild Info is being read again after a save: wait a moment." return st end
  local fn = type(C_GuildInfo) == "table" and C_GuildInfo.GetInfoText or nil
  local ok, text = false, nil
  if type(fn) == "function" then ok, text = pcall(fn) end
  if not ok or (issecretvalue and issecretvalue(text)) or type(text) ~= "string" then st.why = "Guild Info cannot be read here." return st end
  -- (the text the game holds now says what the last read said: no line where the line is missing)
  local expect = self.line
  if self.missing then expect = false end
  if not sameLine(parseLine(text) or false, expect) then st.why = "Guild Info has changed since it was read: wait a moment." return st end
  local own = guildText(text)
  local line = lineText(at, thr, diff, true)
  local t = own ~= "" and (own .. "\n" .. line) or line
  st.line, st.text = line, t
  if #t > P.INFO_MAX then st.why = "Guild Info is full: its text needs " .. (#t - P.INFO_MAX) .. " bytes fewer for Cute's line (a letter such as \195\166 takes two)." return st end
  if C.Get("CanEditGuildInfo") ~= true then st.why = "Saving needs a rank allowed to edit Guild Info." return st end
  st.ok = true
  return st
end
-- save the policy held to Guild Info (Settings' button, a click: C_GuildInfo.SetInfoText, documented). True, or false
-- and why
function P:Save()
  local st = self:SaveState()
  if not st.ok then return false, st.why end
  local ok, err = pcall(C_GuildInfo.SetInfoText, st.text)
  if not ok then return false, "the game did not take it: " .. tostring(err) end
  local p = policy()
  p.edit, p.base, p.editBy = nil, nil, nil
  -- (a read of the line from before, the game's own copy (none where the line was missing), is no answer until the
  -- roster asked for since has had time; kept with the guild, so a /reload meanwhile changes nothing)
  local old = self.line
  if self.missing then old = false end
  self.waitFor = { old = copyLine(old), at = C.Now() }
  self.line = parseLine(st.text) or false
  self.doubt, self.missing = nil, nil
  local k = kept()
  if k then k.line, k.wait, k.doubt = copyLine(self.line), copyLine(old), nil end
  -- (the save, with the change it made on the line from before: the first reads say whether Guild Info kept it, and
  -- put the change back where it did not, readBack; kept with the guild, so a relog within the wait loses neither)
  self.saved = nil
  if k then k.saved = nil end
  if type(self.line) == "table" and self.line.fp then
    local base = type(old) == "table" and old or nil
    local s = { fp = self.line.fp, thr = self.line.thr, diff = self.line.diff, base = base and base.fp or false,
      baseThr = base and base.thr or DEFAULT_THRESHOLD, baseDiff = base and base.diff or "" }
    if k then k.saved = s end
    self.saved = { fp = s.fp, thr = s.thr, diff = s.diff, base = s.base, baseThr = s.baseThr, baseDiff = s.baseDiff, at = C.Now() }
  end
  self.ver = self.ver + 1
  self:Settle()
  -- (read again soon: the game may not have taken it)
  if C.Roster.AskSoon then C.Roster:AskSoon(function() return self.waitFor ~= nil end) end
  return true
end

----------------------------------------------------------------------------
-- rerouting and the purge
----------------------------------------------------------------------------
-- the ids the policy keeps to the officers now: every stat of the registry and every id the list names, as P:Vis says
-- them. A change that adds none deletes nothing (P:Rerouted), so the same policy taken again costs no purge
local function closedSet()
  local out = {}
  for _, def in ipairs(C.Stats.list) do if P:Vis(def.id) == "self" then out[def.id] = true end end
  local p = held()
  for id in pairs(p and type(p.vis) == "table" and p.vis or EMPTY) do if type(id) == "string" and P:Vis(id) == "self" then out[id] = true end end
  return out
end
-- the route of each value this client has of its own, before a change of the policy
function P:Routes()
  local out = {}
  for id in pairs(C.Sample and C.Sample.values or EMPTY) do if type(id) == "string" then out[id] = self:Route(id) end end
  return out
end
-- before a change: the routes of this client's own values, what the policy keeps to the officers and the gaps Ready
-- counts
function P:Snapshot() return { routes = self:Routes(), closed = closedSet(), ready = C.Stats.ReadyCounts() } end
-- after a change: what the officers opened goes to the guild from now on (Comm.lua sends it again, on the guild
-- channel), and a member's client deletes what it holds of others that is now the officers' alone. A change that
-- closes nothing new deletes nothing. Where Ready counts fewer gaps than it did, the members' Ready held here counted
-- one the officers keep now (an offline member's stays until they log in): it goes too, and its sender's next read
-- says it again
function P:Rerouted(before)
  self.ver = self.ver + 1
  before = before or EMPTY
  local opened = {}
  for id, r in pairs(before.routes or EMPTY) do if r == "self" and self:Route(id) == "all" then opened[#opened + 1] = id end end
  if #opened > 0 and C.Comm and C.Comm.Opened then C.Comm:Opened(opened) end
  -- (the officers' threshold may have changed who this client is)
  if C.Roster and C.Roster.PurgeCheck then C.Roster:PurgeCheck() end
  local grew = before.closed == nil
  if not grew then for id in pairs(closedSet()) do if not before.closed[id] then grew = true break end end end
  local counts, shrank = C.Stats.ReadyCounts(), false
  for id in pairs(before.ready or EMPTY) do if not counts[id] then shrank = true end end
  if grew or shrank then self:Purge(shrank) end
  -- Ready counts what the guild may see (Stats.lua): read again now, before anything held back leaves by the policy in
  -- force (a line read ends the wait in this same call, and the record released then carried a Ready counted under the
  -- policy held before, an empty slot the line keeps among its gaps); and an officer's client says what the guild
  -- learned from what the members no longer hear (Comm.lua's 1N)
  if C.Sample and C.Sample.started then C.Sample:Read("ready") end
  if C.Comm and C.Comm.WordSoon then C.Comm:WordSoon(true) end
  if C.Comm and C.Comm.Officers then C.Comm:Officers() end
end
-- the values this client holds for other members that the policy keeps to the officers: deleted, unless you are one.
-- Run once the roster first says whether you are (a login: saved records from before carry none past it), whenever
-- the policy closes a stat, and when the roster says you are an officer no more. The traces go too: who killed a boss,
-- saw its loot or wore an enchant, by GUID, in what the guild learned (Rules.lua StripTraces, Stats.lua
-- StripEnchantTraces), where the officers keep Bosses, Dungeons, Raids or Enchanted slots to themselves; what was
-- learned, and how many members it was seen on, stays. The saved variables are the account's: where another character
-- of it is an officer of this guild (Roster.lua R:AccountOfficer), the file is that officer's and nothing is deleted
-- (this character's window shows none of it all the same: P:CanSee). And a 0.5.x member's Ready goes, which counted the
-- gear gaps the officers keep, and every member's Ready where it counts fewer gaps than it did (ready). Nothing before
-- the roster has said whether you are an officer, from a roster that lists you with your rank, and Guild Info has been
-- read (Roster.lua R:PurgeCheck): one read that lacks you deletes nothing. A statistic this client has not defined while
-- its probe may still define it (Stats.lua gamePending) is left for the probe's last word, which runs this again
-- (Roster.lua R:ReleaseHeld). One it cannot name at all (a module's stat while the module is off here, whose route the
-- officers may have closed) goes too: the member's next record brings it again where it may. A purge of the Readys
-- that waits (the roster not read yet, or this client an officer's) is kept for the one that runs, so none survives
-- the wait. The number deleted
local OLD_READY = "0.6.0" -- the first version whose Ready counts only what everyone may see
function P:Purge(ready)
  local R = C.Roster
  if ready then self.readyDue = true end
  if not (R and R.trusted) or R.wasOfficer == nil or not R:SelfKnown() or R:MeOfficer() then return 0 end
  -- (whose the file is waits for a roster read that says, R:AccountOfficer: a purge due meanwhile runs then, R:PurgeCheck)
  local account = R.AccountOfficer and R:AccountOfficer()
  if account == nil then self.purgeDue = true; return 0 end
  if account then return 0 end
  ready, self.readyDue, self.purgeDue = self.readyDue, nil, nil
  local n = 0
  local pending = C.Stats.gamePending == true
  -- (each id routed once, however many records hold it)
  local routes = {}
  local function route(id) local r = routes[id]; if r == nil then r = self:Route(id); routes[id] = r end return r end
  for key, e in pairs(CuteDB.roster or EMPTY) do
    if type(e) == "table" and type(e.stats) == "table" and not R:IsSelfRecord(key, e) then
      for id in pairs(e.stats) do
        local wait = pending and type(id) == "string" and id:match("^g%d+$") ~= nil and not C.Stats.byId[id]
        -- (an id this client cannot name now, a module's stat while the module is off, has no route here: not kept)
        local unknown = type(id) ~= "string" or (not C.Stats.byId[id] and not C.Stats.IsDynamic(id))
        if not wait and (unknown or route(id) == "self" or (id == "ready" and (ready or not P.CurrentReady(e.stats.addon_ver)))) then
          e.stats[id] = nil
          if type(e.at) == "table" then e.at[id] = nil end
          n = n + 1
        end
      end
      -- (a suspect's reason names the value that could not be: the mark stays, a value the officers keep goes)
      local s = e.suspect
      if type(s) == "table" and type(s.id) == "string" and route(s.id) == "self" then
        s.why, s.id = "sent a value that cannot be, of a stat the officers keep", nil
      end
    end
  end
  -- (what the guild learned is the account's first guild's, CuteDB.knownClub: another guild's policy takes out only the
  -- traces of the members its roster lists, its own, and nothing of the first guild's)
  local traces, only = 0, nil
  local club = R:ClubId()
  if club ~= nil and CuteDB.knownClub ~= tostring(club) then only = function(g) return R.byGuid[g] ~= nil end end
  if C.Rules and C.Rules.StripTraces then
    traces = traces + C.Rules.StripTraces({ bosses = self:Route("gc_bosses") == "self", party = self:Route("gc_dungeons") == "self",
      raid = self:Route("gc_raids") == "self", rep = self:Route("gc_rep") == "self", level = self:Route("xpmax") == "self" }, only)
  end
  if self:Route("enchanted") == "self" and C.Stats.StripEnchantTraces then traces = traces + C.Stats.StripEnchantTraces(only) end
  if n > 0 then
    R:Changed()
    if C.Rules then C.Rules:Dirty() end
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
  return n + traces
end
-- a member's Ready that counts only what everyone may see: from 0.6.0 on (0.5.x counted the empty slots and the missing
-- enchants, the officers' by default)
function P.CurrentReady(ver) return C.ParseVersion(ver) ~= nil and not C.VersionNewer(OLD_READY, ver) end

-- what the policy is, for Settings and the Officers page: one line
local function when(t) return (date and t and t > 0) and date("%Y-%m-%d %H:%M", t) or "?" end
function P:Describe()
  local p, line = held(), self.line
  if line == nil then return "Guild Info not read yet: nothing of yours is sent until it is." end
  if type(line) == "table" and line.newer then return "Guild Info's Cute line is from a newer Cute: update Cute." end
  if type(line) == "table" and not line.fp and not self.missing then return "Guild Info's Cute line cannot be read: an officer saves it again." end
  if self.missing then
    return C.Roster:MeOfficer() and "Cute's line is missing from Guild Info; Save to Guild Info to put it back."
      or "Cute's line is missing from Guild Info: nothing of yours is sent until an officer saves it again."
  end
  if self.doubt then return "An officer sent a newer policy: nothing of yours is sent until Guild Info is read again." end
  if not self:Settled() then return "Waiting for the policy Guild Info names: nothing of yours is sent." end
  if line and p and p.edit then return "Your change, not saved: only your client routes by it." end
  if line then return "Saved to Guild Info " .. when(line.at) .. "." end
  if not (p and p.by) then return "The defaults apply. Guild Info has no Cute line yet." end
  return string.format("Set by %s, %s. Guild Info has no Cute line yet.", p.mine and C.Roster:MyDisplay() or C.Roster:Display(p.by), when(p.at))
end

-- for /cute diag: Guild Info's line as this client read it, and the policy it routes by
function P:Report()
  local line = self.line
  local said = line == nil and "Guild Info not read" or (line == false and "no Cute line in Guild Info")
    or (self.missing and "Cute's line missing from Guild Info, the last read routing")
    or (line.newer and "a newer Cute's line in Guild Info") or (not line.fp and "an unreadable line in Guild Info")
    or ("line " .. line.fp .. " carrying the policy, saved " .. when(line.at))
  return string.format("%s | routes by %s, officer ranks 0 to %d%s", said, self:Fp(), self:Threshold(), self:Settled() and "" or ", waiting for the line's")
end

-- The saved variables are the account's, and its characters may be in different guilds: each guild's policy and its
-- members' records are kept by the guild's club (CuteDB.policies), the current guild's in CuteDB.policy and
-- CuteDB.roster, so another guild's roster prunes, and its policy purges, none of this guild's. What the guild learned
-- (CuteDB.known) is the first guild's (CuteDB.knownClub): another guild's purge takes out only its own members' traces
-- (P:Purge). Run whenever the roster is read in a guild, before anything goes by the policy. A policy and records saved
-- by 0.5.x, which say no guild, wait for the roster (P:Adopt). Another guild's Guild Info is read anew
local function hasRecords(roster) return type(roster) == "table" and next(roster) ~= nil end
function P:ForClub(club)
  if club == nil or type(CuteDB) ~= "table" then return end
  local key, was = tostring(club), CuteDB.policyClub
  if was == key then return end
  if was == nil then
    -- (0.5.x's records: whose guild they are waits for the roster, P:Adopt; none, or a fresh install: this one's)
    if hasRecords(CuteDB.roster) then return end
    CuteDB.policyClub = key
    if CuteDB.knownClub == nil then CuteDB.knownClub = key end
    return
  end
  CuteDB.policyClub = key
  self:Left()
  CuteDB.policies = type(CuteDB.policies) == "table" and CuteDB.policies or {}
  CuteDB.policies[was] = { policy = CuteDB.policy, roster = CuteDB.roster }
  local other = CuteDB.policies[key]
  CuteDB.policies[key] = nil
  CuteDB.policy = type(other) == "table" and other.policy or nil
  CuteDB.roster = type(other) == "table" and type(other.roster) == "table" and other.roster or {}
  if C.Roster and C.Roster.ClubChanged then C.Roster:ClubChanged() end
  self.ver = self.ver + 1
end
-- the records and policy 0.5.x saved, which say no guild, are this guild's only where the roster (byGuid, the members by
-- GUID, read before anything reads, learns from or prunes them: Roster.lua R:Refresh) lists a member one of the
-- records carries: an alt's login in a second guild would have pruned the first guild's records and taken its policy.
-- Elsewhere they are put aside (CuteDB.policies["?"]), this guild starts with none, and the first guild whose roster
-- lists one of them takes them while it has none of its own; what the guild learned (CuteDB.known) is that guild's
-- once it does (knownClub, unset till then: another guild's purge takes out only its own members' traces). True where
-- the records held changed
function P:Adopt(club, byGuid)
  if club == nil or type(CuteDB) ~= "table" or type(byGuid) ~= "table" then return false end
  local key = tostring(club)
  local function vouched(roster)
    for _, e in pairs(type(roster) == "table" and roster or EMPTY) do
      local g = type(e) == "table" and type(e.stats) == "table" and e.stats.guid
      if type(g) == "string" and byGuid[g] then return true end
    end
    return false
  end
  CuteDB.policies = type(CuteDB.policies) == "table" and CuteDB.policies or {}
  if CuteDB.policyClub == nil then
    if not hasRecords(CuteDB.roster) or vouched(CuteDB.roster) then
      CuteDB.policyClub = key
      if CuteDB.knownClub == nil then CuteDB.knownClub = key end
      return false
    end
    if CuteDB.policies["?"] == nil then CuteDB.policies["?"] = { policy = CuteDB.policy, roster = CuteDB.roster } end
    CuteDB.policy, CuteDB.roster, CuteDB.policyClub = nil, {}, key
    self.ver = self.ver + 1
    return true
  end
  local parked = CuteDB.policies["?"]
  if CuteDB.policyClub ~= key or type(parked) ~= "table" or CuteDB.policy ~= nil or hasRecords(CuteDB.roster) or not vouched(parked.roster) then return false end
  CuteDB.policies["?"] = nil
  CuteDB.policy = type(parked.policy) == "table" and parked.policy or nil
  CuteDB.roster = type(parked.roster) == "table" and parked.roster or {}
  if CuteDB.knownClub == nil then CuteDB.knownClub = key end
  self.ver = self.ver + 1
  return true
end
-- out of the guild (or into another): its line and what was heard there are no more this client's
function P:Left()
  self.line, self.heard, self.parts, self.settled, self.doubt, self.confirmed = nil, {}, {}, nil, nil, nil
  self.waitFor, self.emptyWait, self.missing, self.restored, self.doubtEnded, self.lineChanged = nil, nil, nil, nil, nil, nil
  self.unread, self.saved = nil, nil
  self.ver = self.ver + 1
end
