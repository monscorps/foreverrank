-- SPDX-License-Identifier: GPL-3.0-or-later
-- PallyPower's messages (prefix PLPWR), heard and spoken. PallyPower (AznamirWoW/PallyPower, its Forever build) is All
-- Rights Reserved: none of its code is here, only its wire format, as its source reads and writes it.
--   SELF <6 x 2>@<9>         a paladin's ranks (slots 1-3: wisdom, might, kings; a hex rank and a talent digit, "nn"
--                            none) and its class row (a digit a class: 1 wisdom, 2 might, 3 kings, 0 or n none)
--   ASSIGN <pal> <class> <b>  one class cell; MASSIGN <pal> <b> every class; PASSIGN <pal>@<9> a whole row
--   NASSIGN <wpal> <class> <wtarget> <b>[@...]  one member's own blessing from one paladin ("_" for a name's space)
--   CLEAR, CLEAR SKIP         a leader's: every cell gone
--   REQ                       everyone's SELF again (PallyPower answers by whisper to the asker outside a raid
--                             instance, unless the asker leads)
-- Heard: a paladin who sent SELF gets a column in the share-out, its cells fixed (Assign.lua); one running Cute Auras
-- alone (its hello's field 8 "-") is never listed, that SELF is our own. A leader's cell for a paladin running Cute
-- Auras alone is taken by that paladin's own client and sent as its own hand-set cell (O1, field 7 pp), so every
-- client has it from one message and one stamp; that client keeps the leader's class cells apart from a member's own
-- (NASSIGN), as PallyPower does. In an instance group inside an instance (a battleground) PallyPower has no leaders: a
-- paladin alone sets its cells there, and a CLEAR is nobody's. Spoken, by a paladin running Cute Auras without
-- PallyPower: SELF, ASELF and FREEASSIGN, so PallyPower users see our column (Free Assignment off), each SELF after an
-- S1 on our prefix (Comm.lua: a SELF from such a member without one is PallyPower's, their hello old). One client asks,
-- the asker (the lowest GUID running Cute Auras 0.2.3 or later without PallyPower; none such, the lowest GUID running
-- it with PallyPower, which passes whispers on and asks nothing): it sends REQ, and passes what PallyPower whispers to
-- it to the group (P1 on our prefix), so every client parses the same messages; a client where PallyPower runs passes
-- on what its own PallyPower's REQ as it joined the group brought it too. A whisper itself is never parsed.
local _, A = ...
local Ps = A.Part("PallySync", { pals = {}, row = {}, member = {}, stats = {}, heardAny = false })
local plain, call = A.Plain, A.Call
local PREFIX = "PLPWR"
Ps.PREFIX = PREFIX

-- PallyPower's class order on Forever (its PallyPowerValues.lua's ClassID: nine, no pet column)
Ps.CLASSES = { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
local DIGIT_KEY = { ["1"] = "wisdom", ["2"] = "might", ["3"] = "kings" }
local KEY_DIGIT = { wisdom = "1", might = "2", kings = "3" }
local SLOT_KEYS = { "wisdom", "might", "kings" }

local function count(k, n) Ps.stats[k] = (Ps.stats[k] or 0) + (n or 1) end
local function serverNow()
  local t = GetServerTime and plain(call(GetServerTime))
  if type(t) ~= "number" then t = time and time() or 0 end
  return t
end

-- PallyPower runs on this client
function Ps.Here()
  local AO = C_AddOns
  return AO ~= nil and A.Yes(AO.IsAddOnLoaded, "PallyPower")
end
-- a member running Cute Auras without PallyPower (its hello says so; you: PallyPower not loaded here)
local function cuteOnly(m)
  if m.me then return not Ps.Here() end
  local p = A.Comm.peers[m.guid]
  return p ~= nil and p.ppField == "-"
end
Ps.CuteOnly = cuteOnly
-- (PallyPower's own rule: in an instance group inside an instance, a battleground's, it lists no leader)
local function noLeaders() return A.Yes(IsInGroup, LE_PARTY_CATEGORY_INSTANCE or 2) and A.Yes(IsInInstance) end
local function isLead(m)
  return m ~= nil and not noLeaders() and (A.Yes(UnitIsGroupLeader, m.unit) or A.Yes(UnitIsGroupAssistant, m.unit))
end
-- (who may set a paladin's cells: that paladin; the leader or an assist where PallyPower has leaders)
local function maySet(sm, pal)
  return sm ~= nil and (sm == pal or (not noLeaders() and A.Assign.MayChange(sm.guid, pal.guid)))
end

----------------------------------------------------------------------------
-- what the share-out reads (Assign.lua)
----------------------------------------------------------------------------
-- a listed paladin's ranks: { wisdom, might, kings } (0 none), else nil
function Ps.Known(guid) local p = Ps.pals[guid]; return p and p.ranks or nil end
-- a paladin's own cell for one member (NASSIGN): the blessing's key, else nil
function Ps.MemberCell(pal, guid)
  local list = Ps.member[pal]
  local c = list and list[guid]
  return c and c[1] or nil
end
-- a listed paladin's cell for a bucket (its members, its class): the members' own cell when every one of them has the
-- same, else the class cell; nil for none
function Ps.Cell(pal, b)
  local list = Ps.member[pal]
  if list and #b > 0 then
    local key
    for i, m in ipairs(b) do
      local c = list[m.guid]
      local k = c and c[1] or nil
      if k == nil or (i > 1 and k ~= key) then key = nil break end
      key = k
    end
    if key then return key end
  end
  local r = Ps.row[pal]
  local c = r and r[b.class or "?"]
  return c and c[1] or nil
end

----------------------------------------------------------------------------
-- hearing
----------------------------------------------------------------------------
local function changed() if A.Assign then A.Assign.Changed() end end
-- (nine row characters: a key or false each, by class; a digit Forever has no blessing for counted)
local function readRow(s)
  local cells, odd = {}, 0
  for i, class in ipairs(Ps.CLASSES) do
    local ch = s:sub(i, i)
    local key = DIGIT_KEY[ch]
    if not key and ch ~= "n" and ch ~= "0" and ch ~= "" then odd = odd + 1 end
    cells[class] = key or false
  end
  return cells, odd
end

-- a leader's cell for your column, Cute Auras alone here: your own hand-set cell, marked pp (key nil: back to Cute
-- Auras' choice, only where a cell is set)
local function ovMine(bk)
  local me = A.MyGUID()
  local t = me and A.Assign.overrides[me]
  return t and t[bk] or nil
end
local function takeBucket(bk, key)
  local As = A.Assign
  local me = A.MyGUID()
  local ov = ovMine(bk)
  if key == nil then
    if ov and not ov.clear then return As.Set(me, bk, nil, true) end
  elseif not (ov and not ov.clear and ov.key == key and ov.pp) then
    return As.Set(me, bk, key, true)
  end
  return false
end
-- your column's cells from a leader, kept on your client alone: the class cells (ASSIGN, MASSIGN, PASSIGN), by class
-- { key or false, stamp }, for a bucket of that class that comes later and for our SELF's row where the class has no
-- member here; and the buckets a NASSIGN set, by member { bk, class, key, stamp, prev = the bucket's cell before it,
-- under = what we gave it then } (bk false: waiting, their bucket shared). A member's own cell is no class cell:
-- PallyPower keeps them apart
Ps.mine = {}
local nassigned = {}
-- (a NASSIGN's cell still its bucket's: nothing newer set it since)
local function live(rec)
  local ov = ovMine(rec.bk)
  return ov ~= nil and not ov.clear and ov.key == rec.key and ov.stamp == rec.stamp and ov.from == A.MyGUID()
end
local function liveIn(bk)
  for _, rec in pairs(nassigned) do if rec.bk == bk and live(rec) then return rec end end
  return nil
end
-- (what a NASSIGN covered: the newer of the leader's class cell and the bucket's cell before it; nil, Cute Auras'
-- choice. Third, where it came from: "cell" (a leader's 0 reads nil), "prev", or nil for neither)
local function backTo(rec)
  local cell, prev = Ps.mine[rec.class or "?"], rec.prev
  if cell and (not prev or (cell[2] or 0) >= (prev.stamp or 0)) then return cell[1] or nil, true, "cell" end
  if prev then return prev.key, prev.pp, "prev" end
  return nil, true, nil
end
local function putBack(rec)
  local key, pp = backTo(rec)
  if key == nil then return takeBucket(rec.bk, nil) end
  local ov = ovMine(rec.bk)
  if ov and not ov.clear and ov.key == key and (ov.pp and true or false) == (pp and true or false) then return false end
  return A.Assign.Set(A.MyGUID(), rec.bk, key, pp)
end
local function takeClass(class, key)
  Ps.mine[class] = { key or false, serverNow() }
  local list = {}
  for _, b in ipairs(A.Assign.bucketList or {}) do
    -- (a member's own cell from a NASSIGN stays: PallyPower's own beats its class's)
    if b.class == class and not liveIn(b.key) then list[#list + 1] = b.key end
  end
  for _, bk in ipairs(list) do takeBucket(bk, key) end
end
-- (a bucket of a class the leader set for your column whose cell is older than the leader's, a member who joined
-- since: the leader's cell; collected, then set)
local function takeNew()
  if next(Ps.mine) == nil then return end
  local m = A.Roster.Me()
  if not (m and m.class == "PALADIN" and cuteOnly(m)) then return end
  local list = {}
  for _, b in ipairs(A.Assign.bucketList or {}) do
    local cell = Ps.mine[b.class or "?"]
    local ov = ovMine(b.key)
    if cell and (ov == nil or (ov.stamp or 0) < (cell[2] or 0)) and not liveIn(b.key) then
      list[#list + 1] = { b.key, cell[1] or nil }
    end
  end
  for _, x in ipairs(list) do takeBucket(x[1], x[2]) end
end
-- ASSIGN, MASSIGN, PASSIGN: cells = { [class] = key or false }, set for the paladin palName names
local function setCells(sm, palName, cells)
  local pal = A.Roster.SenderMember(palName)
  if not pal or pal.class ~= "PALADIN" then count("unsure") return end
  if not maySet(sm, pal) then count("refused") return end
  if Ps.pals[pal.guid] then
    local r = Ps.row[pal.guid] or {}
    Ps.row[pal.guid] = r
    local stamp = serverNow()
    for class, key in pairs(cells) do r[class] = { key, stamp } end
    count("taken")
    changed()
  elseif pal.me and cuteOnly(pal) then
    -- (yours: your client alone takes it, and sends it once as your own. PallyPower's copy of your row is the leader's
    -- now, a 0 too, which Cute Auras reads as its own choice and casts on: your SELF again, as you cast)
    for _, class in ipairs(Ps.CLASSES) do
      if cells[class] ~= nil then takeClass(class, cells[class] or nil) end
    end
    count("taken")
    Ps.Stale()
    changed()
  end
end
local function onSelf(sm, text)
  local slots, row = text:match("^SELF ([0-9a-fn]+)@([0-9n]+)")
  if not slots or #slots < 12 or #row < 9 then count("bad") return end
  if not sm then count("unsure") return end
  if sm.class ~= "PALADIN" then count("refused") return end
  -- (the mirror: a member running Cute Auras alone sends a SELF only from Cute Auras, its S1 before it: parse)
  if cuteOnly(sm) then return end
  local ranks = {}
  for i, key in ipairs(SLOT_KEYS) do
    local ch = slots:sub(i * 2 - 1, i * 2 - 1)
    ranks[key] = ch ~= "n" and (tonumber(ch, 16) or 0) or 0
  end
  local p = Ps.pals[sm.guid] or {}
  p.ranks, p.at = ranks, serverNow()
  Ps.pals[sm.guid] = p
  -- (the whole row replaced, as PallyPower does; a 10-column build's tenth left out)
  local cells, odd = readRow(row:sub(1, 9))
  if odd > 0 then count("other", odd) end
  local stamp, r = serverNow(), {}
  for class, key in pairs(cells) do r[class] = { key, stamp } end
  Ps.row[sm.guid] = r
  count("self")
  changed()
end
-- (what a NASSIGN covered put back: the other members' records that set that bucket with it wait again)
local function putBackAll(rec)
  local bk = rec.bk
  local changedCell = putBack(rec)
  if bk then for _, r in pairs(nassigned) do if r.bk == bk then r.bk = false end end end
  return changedCell
end
-- (every member of a shared bucket has the same cell of yours from the leader: the bucket's, as PallyPower casts it,
-- and as Ps.Cell reads a PallyPower paladin's; each member's record sets it, one stamp)
local function allHave(list, key)
  for _, m in ipairs(list) do
    local r = nassigned[m.guid]
    if not (r and r.key == key) then return false end
  end
  return true
end
-- (what a bucket's cell covers as a NASSIGN takes it: a live NASSIGN's there already, what that one covered, never its
-- own cell; else the bucket's cell now)
local function covered(bk)
  local r = liveIn(bk)
  if r then return r.prev, r.under end
  local As, me = A.Assign, A.MyGUID()
  local prev
  local ov = ovMine(bk)
  if ov and not ov.clear and ov.key then prev = { key = ov.key, stamp = ov.stamp or 0, pp = ov.pp } end
  return prev, me and As.bless[me] and As.bless[me][bk] or nil
end
local function takeShared(list, bk, key)
  local prev, under = covered(bk)
  local changedCell = takeBucket(bk, key)
  local ov = ovMine(bk)
  for _, m in ipairs(list) do
    local r = nassigned[m.guid]
    r.bk, r.stamp, r.prev, r.under = bk, ov and ov.stamp or 0, prev, under
  end
  return changedCell
end
-- a leader's cell for one member of your column (NASSIGN; key nil, a removal), Cute Auras alone here: that member's
-- bucket when it is theirs alone, or when every member of it has the same one. A removal puts back what that NASSIGN
-- covered, in the bucket it set, whoever joined it since. One whose bucket is shared (it grew, or they moved to a
-- shared one) and not every member there has that cell: a change puts back what the earlier one covered, and the
-- leader's word waits (bk false) for a bucket that is theirs alone or whose every member has it (Ps.Settle tries the
-- waiting ones at each share-out); the same cell again changes nothing. A 0 for a member no NASSIGN set changes
-- nothing: PallyPower's grid sends one for every paladin as its leader only opens a member's menu or right-clicks
-- them. True when a cell changed
local function memberCell(tgt, key)
  local As = A.Assign
  local was = nassigned[tgt.guid]
  if key == nil then
    nassigned[tgt.guid] = nil
    return was ~= nil and live(was) and putBackAll(was) or false
  end
  local bk = As.Bucket(tgt)
  local list = As.buckets and As.buckets[bk]
  if not (list and #list == 1) then
    if was and was.key == key and ((was.bk == bk and live(was)) or was.bk == false) then
      if was.bk == false and list and allHave(list, key) then return takeShared(list, bk, key) end
      return false
    end
    local changedCell = was ~= nil and live(was) and putBackAll(was) or false
    nassigned[tgt.guid] = { bk = false, class = tgt.class, key = key, stamp = 0 }
    if list and allHave(list, key) then changedCell = takeShared(list, bk, key) or changedCell end
    return changedCell
  end
  local prev, under
  if was and was.bk == bk and live(was) then prev, under = was.prev, was.under
  else
    -- (a NASSIGN of theirs in another bucket, a role ago: that one put back first)
    if was and live(was) then putBackAll(was) end
    -- (another member's still live here, its member gone from it: what it covered, and it waits)
    local r = liveIn(bk)
    prev, under = covered(bk)
    if r then r.bk = false end
  end
  local changedCell = takeBucket(bk, key)
  local ov = ovMine(bk)
  nassigned[tgt.guid] = { bk = bk, class = tgt.class, key = key, stamp = ov and ov.stamp or 0, prev = prev, under = under }
  return changedCell
end
local function onNAssign(sm, text)
  local rest = text:match("^NASSIGN (.+)$")
  if not rest then count("bad") return end
  for entry in (rest .. "@"):gmatch("([^@]*)@") do
    local wp, wt, dg = entry:match("^(%S+) %d+ (%S+) (%d+)$")
    if not wp then count("bad")
    else
      local pal = A.Roster.SenderMember((wp:gsub("_", " ")))
      local tgt = A.Roster.SenderMember((wt:gsub("_", " ")))
      local key = DIGIT_KEY[dg]
      if not pal or pal.class ~= "PALADIN" or not tgt then count("unsure")
      elseif not maySet(sm, pal) then count("refused")
      elseif Ps.pals[pal.guid] then
        local list = Ps.member[pal.guid] or {}
        Ps.member[pal.guid] = list
        list[tgt.guid] = key and { key, serverNow() } or nil
        count("taken")
        changed()
      elseif pal.me and cuteOnly(pal) then
        if memberCell(tgt, key) then count("taken") end
      end
    end
  end
end
local function onClear(sm)
  if not isLead(sm) then return end
  count("clear")
  for k in pairs(Ps.row) do Ps.row[k] = nil end
  for k in pairs(Ps.member) do Ps.member[k] = nil end
  for k in pairs(Ps.mine) do Ps.mine[k] = nil end
  for k in pairs(nassigned) do nassigned[k] = nil end
  -- (yours a PallyPower leader set: back to Cute Auras' choice, sent)
  local me = A.MyGUID()
  local mine = me and A.Assign.overrides[me]
  if mine then
    local list = {}
    -- (a leader's 0 left a clear marked pp: plain again too, so your casts teach it)
    for bk, ov in pairs(mine) do if ov.pp and ov.from == me then list[#list + 1] = bk end end
    for _, bk in ipairs(list) do A.Assign.Set(me, bk, nil) end
  end
  -- (the CLEAR emptied every row in PallyPower's grids, ours too, while we cast on: our SELF again)
  Ps.Stale()
  changed()
end
local function onReq(sm)
  count("req")
  -- (our own; our asker, Cute Auras alone, has our hello and cells. One whose name can't be told is answered)
  if sm and (sm.me or cuteOnly(sm)) then return end
  Ps.AnswerSoon()
end

-- (what Cute Auras never sends: a member whose hello says Cute Auras alone sending one runs PallyPower)
local PP_ONLY = { ASSIGN = true, MASSIGN = true, PASSIGN = true, NASSIGN = true, CLEAR = true, PPLEADER = true, AASSIGN = true }
-- one message, as its sender's (heard on the group, or passed on by the asker)
local function parse(text, sender)
  local sm = A.Roster.SenderMember(sender)
  -- (our own echo, PallyPower not here: what we said)
  if sm and sm.me and not Ps.Here() then return end
  count("heard")
  local kind = text:match("^(%u+)")
  -- (a member whose hello says Cute Auras alone: a SELF of theirs is our own only with their S1 just before it; one
  -- without, or a message only PallyPower sends, is their PallyPower's, their hello old: Cute Auras turned off there)
  if sm and not sm.me and cuteOnly(sm) then
    local mirror = kind == "SELF" and A.Comm.TakeSelfMark(sm.guid)
    if (kind == "SELF" and not mirror) or PP_ONLY[kind] then A.Comm.Forget(sm.guid) end
  end
  local first = false
  if sm and not cuteOnly(sm) and not Ps.heardAny then Ps.heardAny, first = true, true end
  if text == "REQ" then onReq(sm)
  elseif kind == "SELF" then onSelf(sm, text)
  elseif kind == "ASSIGN" then
    count("set")
    local name, class, dg = text:match("^ASSIGN (.+) (%d+) (%d+)$")
    local c = tonumber(class)
    if not name or not Ps.CLASSES[c or 0] then count("bad")
    else setCells(sm, name, { [Ps.CLASSES[c]] = DIGIT_KEY[dg] or false }) end
  elseif kind == "MASSIGN" then
    count("set")
    local name, dg = text:match("^MASSIGN (.+) (%d+)$")
    if not name then count("bad")
    else
      local cells = {}
      for _, class in ipairs(Ps.CLASSES) do cells[class] = DIGIT_KEY[dg] or false end
      setCells(sm, name, cells)
    end
  elseif kind == "PASSIGN" then
    count("set")
    local name, row = text:match("^PASSIGN (.+)@([0-9n]+)$")
    if not name then count("bad") else setCells(sm, name, (readRow(row:sub(1, 9)))) end
  elseif kind == "NASSIGN" then count("set"); onNAssign(sm, text)
  elseif kind == "CLEAR" then onClear(sm)
  elseif kind == "FREEASSIGN" then
    local p = sm and Ps.pals[sm.guid]
    if p then p.free = text:match("^FREEASSIGN (%u+)") end
  else count("other") end
  if first then Ps.Changed() end
end

-- a whispered message passed to the group as P1: whole, or a NASSIGN too long for one (our prefix and the sender's name
-- added to PallyPower's 255 bytes) in parts of whole entries; an entry too long alone is counted dropped
local MAX = 255
local function relay(sender, text)
  local head = "P1|" .. sender .. "|"
  if #head + #text <= MAX then
    if A.Comm.Send(head .. text) then count("relayed") end
    return
  end
  local entries = text:match("^NASSIGN (.+)$")
  if not entries then count("dropped") return end
  head = head .. "NASSIGN "
  local part = nil
  local function flush() if part and A.Comm.Send(head .. part) then count("relayed") end part = nil end
  for entry in (entries .. "@"):gmatch("([^@]*)@") do
    if #head + #entry > MAX then count("dropped")
    elseif part and #head + #part + 1 + #entry <= MAX then part = part .. "@" .. entry
    else flush(); part = entry end
  end
  flush()
end
-- PLPWR from the client (Comm.lua's CHAT_MSG_ADDON, its values plain or nil): read in a group only; a whisper is never
-- parsed. The asker passes a SELF or NASSIGN whispered to it to the group; so does a client where PallyPower runs in
-- its first 30 s in a group, what its own PallyPower's REQ as it joined brought it: a newcomer where every Cute Auras
-- client runs PallyPower hears the paladins already there only so
local joinedAt -- (when you joined this group)
local JOIN_RELAY = 30
function Ps.OnMessage(text, channel, sender)
  if not A.Roster.InGroup() then return end
  if type(text) ~= "string" or type(sender) ~= "string" then count("secret") return end
  if channel == "WHISPER" then
    count("whispered")
    local joining = Ps.Here() and joinedAt ~= nil and A.Now() - joinedAt <= JOIN_RELAY
    if (Ps.IsAsker() or joining) and (text:find("^SELF ") or text:find("^NASSIGN ")) then relay(sender, text) end
    return
  end
  parse(text, sender)
end
-- a P1 on our prefix: the asker's counts, and one from a client where PallyPower runs (a newcomer's, its PallyPower's
-- answers as it joined)
function Ps.OnRelay(relayer, sender, text)
  if not A.Roster.InGroup() or type(text) ~= "string" or type(sender) ~= "string" then return end
  local rm = A.Roster.SenderMember(relayer)
  local p = rm and not rm.me and A.Comm.peers[rm.guid]
  local pp = rm ~= nil and ((rm.me and Ps.Here()) or (p and p.ppField == "pp"))
  if not rm or (rm.guid ~= Ps.Asker() and not pp) then count("refused") return end
  parse(text, sender)
end

-- a member's hello says Cute Auras alone: never listed (a SELF from them was our own)
function Ps.Drop(guid)
  if not (Ps.pals[guid] or Ps.row[guid] or Ps.member[guid]) then return end
  Ps.pals[guid], Ps.row[guid], Ps.member[guid] = nil, nil, nil
  changed()
end

----------------------------------------------------------------------------
-- speaking: a batch of SELF, ASELF and FREEASSIGN on PLPWR, to the group, through Comm's queue (its pace, its wait
-- for a fight's end or a lockdown). After a REQ: within 2 s, at most one batch per 5 s; after our SELF changed (once
-- PallyPower was heard in this group): 5 s after the last change, at most one per 15 s. The first waits for our hello.
-- A paladin who spoke in this group and then stops giving blessings (Blessings off, the bar or its group part off,
-- Nothing in this dungeon, every blessing on Never) takes its SELF back: one with no ranks and an empty row, so
-- PallyPower neither skips what we no longer cast nor shares work out to us; REQs are answered with it while silent
----------------------------------------------------------------------------
function Ps.Speaks()
  if Ps.Here() or not A.Roster.InGroup() then return false end
  local me = A.Roster.Me()
  if not me or me.class ~= "PALADIN" or A.Settings().blessings == false then return false end
  return A.Comm.WhyNoBlessings() == nil
end
-- our SELF: the ranks we announce (Comm.Known: Never'd ones nn), then each class's blessing from us in its largest
-- bucket; silent, none and none. Always 27 bytes: PallyPower's leader adds a short one's nil rank and errors
local EMPTY = "SELF nnnnnnnnnnnn@nnnnnnnnn"
Ps.EMPTY = EMPTY
function Ps.SelfText()
  if not Ps.Speaks() then return EMPTY end
  local As = A.Assign
  local known = A.Comm.ParseKnown(A.Comm.Known())
  local s = {}
  for i, key in ipairs(SLOT_KEYS) do
    local r = known[key] or 0
    s[i] = r > 0 and string.format("%x0", math.min(r, 15)) or "nn"
  end
  local mine = As.bless[A.MyGUID() or ""] or {}
  local row = {}
  local function larger(b, best) return not best or #b > #best or (#b == #best and b.key < best.key) end
  for i, class in ipairs(Ps.CLASSES) do
    -- (its largest bucket that is no member's own cell; every one a NASSIGN's: what those cover; none here: the
    -- leader's class cell for it)
    local best, own
    for _, b in ipairs(As.bucketList or {}) do
      if b.class == class then
        if not liveIn(b.key) then
          if larger(b, best) then best = b end
        elseif larger(b, own) then own = b end
      end
    end
    local key
    if best then key = mine[best.key]
    elseif own then
      -- (the leader's class cell or the bucket's cell before it, the newer: a leader's 0 is none, as their grid shows
      -- it, never the blessing it cleared; neither: what we gave the bucket as the NASSIGN took it)
      local rec = liveIn(own.key)
      if rec then
        local back, _, from = backTo(rec)
        if from then key = back else key = rec.under end
      end
    else
      local cell = Ps.mine[class]
      key = cell and cell[1] or nil
    end
    row[i] = key and KEY_DIGIT[key] or "n"
  end
  return "SELF " .. table.concat(s) .. "nnnnnn@" .. table.concat(row)
end
-- (lastSent: the SELF our last batch queued, for the debounce in this session; lastLeft: the last that left the queue,
-- what PallyPower heard from us, kept over a /reload: one still queued in a fight or a lockdown at the reload is lost)
local lastSent, lastLeft, lastBatchAt, dueAt, dueWhy, armed = nil, nil, nil, nil, nil, 0
-- PallyPower's copy of our row changed by a leader's message (a cell, a 0, a CLEAR), not by our SELF: the next change
-- sends our SELF even when it is the one we sent last (a batch, paced as any change's)
function Ps.Stale() if lastSent ~= nil then lastSent, lastLeft = "", "" end end
-- (we speak, or spoke in this group and must take it back: a paladin, PallyPower not here, in the group)
local function voiced()
  if Ps.Speaks() then return true end
  if lastSent == nil or Ps.Here() or not A.Roster.InGroup() then return false end
  local me = A.Roster.Me()
  return me ~= nil and me.class == "PALADIN"
end
local function sendBatch()
  local text = Ps.SelfText()
  -- (S1 first: the others then know this SELF is ours, not a PallyPower's; a SELF still waiting is replaced in its
  -- place, its S1 ahead of it already)
  local me = A.MyGUID()
  if me and not A.Comm.Waiting(PREFIX, "SELF") then A.Comm.Send("S1|" .. me) end
  A.Comm.Send(text, PREFIX, { sent = function() lastLeft = text end })
  A.Comm.Send("ASELF nnnnnnnnnnnnnn@0", PREFIX)
  A.Comm.Send("FREEASSIGN NO | SYMCOUNT " .. tostring(A.Spells.Count(21177)) .. " | COOLDOWNS:n:n:n:n", PREFIX)
  lastSent, lastBatchAt = text, A.Now()
  -- (sent counts a batch as one, as a REQ is one: the diag's "sent 5 (SELF 3, REQ 2)")
  count("sent"); count("sentSelf")
end
local schedule
local function fire(why)
  if not voiced() then return end
  -- (our hello first in this group: the others then know a SELF from us is ours)
  if not A.Comm.helloSent then schedule(A.Now() + 1, why) return end
  if why == "change" and Ps.SelfText() == lastSent then return end
  sendBatch()
end
function schedule(at, why)
  armed = armed + 1
  local my = armed
  dueAt, dueWhy = at, why
  A.After(math.max(0, at - A.Now()), function()
    if my ~= armed then return end
    -- (a REQ heard while a change's batch waited makes it an answer: it goes even with our SELF the same)
    local w = dueWhy or why
    dueAt, dueWhy = nil, nil
    fire(w)
  end, "pallysync: a batch")
end
local function since(t) return t and (A.Now() - t) or math.huge end
-- a REQ heard: one batch soon; REQs while one waits, or just after one left, are that one
function Ps.AnswerSoon()
  if not voiced() then return end
  local at = math.max(A.Now() + 2, (lastBatchAt or -math.huge) + 5)
  if dueAt then
    if at < dueAt then schedule(at, "req") end
    if dueWhy == "change" and at >= dueAt then dueWhy = "req" end
    return
  end
  if since(lastBatchAt) < 2 then return end
  schedule(at, "req")
end
-- after a share-out: our SELF again when it changed (debounced), once PallyPower was heard here; the empty one once
-- we fall silent
function Ps.Changed()
  if next(nassigned) ~= nil and A.Roster.InGroup() then Ps.Settle(true) end
  takeNew()
  if not (Ps.heardAny and voiced()) then return end
  if dueAt and dueWhy == "req" then return end
  if Ps.SelfText() == lastSent then
    if dueWhy == "change" then armed = armed + 1; dueAt, dueWhy = nil, nil end
    return
  end
  schedule(math.max(A.Now() + 5, (lastBatchAt or -math.huge) + 15), "change")
end

----------------------------------------------------------------------------
-- asking: the asker sends REQ, at most once per 30 s, never while it or a paladin who may answer is in a fight (the
-- client refuses that answer, and PallyPower's queue drops it for good): for a paladin 10 s in the roster with no SELF
-- and no hello that says Cute Auras alone (one running both: its SELF may have left before we listened); when its
-- Blessings tab opens; after a fight at most once per 5 minutes while a PallyPower paladin is in the group, or one asked
-- whose answer never came (three asks at most); and a few seconds after a member running Cute Auras is heard for the
-- first time while a PallyPower paladin is listed (that member never heard its SELF); when a member's hello newly says
-- PallyPower runs there (its SELF before that hello was taken for our own). The asker runs Cute Auras without
-- PallyPower and is online: the lowest GUID of those (none: one with PallyPower passes whispers on, asking nothing)
----------------------------------------------------------------------------
local function online(m) return m ~= nil and (m.me or A.Yes(UnitIsConnected, m.unit)) end
function Ps.Asker()
  local best
  local me = A.MyGUID()
  if me and not Ps.Here() then best = me end
  for guid, p in pairs(A.Comm.peers) do
    if p.ppField == "-" and (not best or guid < best) and online(A.Roster.ByGUID(guid)) then best = guid end
  end
  if best then return best end
  -- (none: the lowest running 0.2.3 or later with PallyPower passes whispers on, so what its own PallyPower's REQ
  -- brings is read; it sends no REQ, Ps.Try, its PallyPower asks)
  if me and Ps.Here() then best = me end
  for guid, p in pairs(A.Comm.peers) do
    if p.ppField == "pp" and (not best or guid < best) and online(A.Roster.ByGUID(guid)) then best = guid end
  end
  return best
end
function Ps.IsAsker() return A.MyGUID() ~= nil and Ps.Asker() == A.MyGUID() end
local reqAt, fightReqAt, reqFight, fightEndAt = nil, nil, false, nil
local seenAt, asked = {}, {} -- [guid] = first seen in the roster; the REQs sent while they were silent
local ASK_MAX = 3
-- (a paladin who might run PallyPower: not you, not one whose hello says Cute Auras alone)
local function mayPP(m) return m.class == "PALADIN" and not m.me and not cuteOnly(m) end
local function maybePP()
  for _, m in ipairs(A.Roster.members) do if mayPP(m) then return true end end
  return false
end
-- (one who would answer is in a fight, or a boss is: wait)
local function ppFighting()
  if A.Yes(IsEncounterInProgress) then return true end
  for _, m in ipairs(A.Roster.members) do
    if mayPP(m) and A.Yes(UnitAffectingCombat, m.unit) then return true end
  end
  return false
end
-- (a listed PallyPower paladin in the group, not you)
local function anyListed()
  for guid in pairs(Ps.pals) do
    local m = A.Roster.ByGUID(guid)
    if m and not m.me then return true end
  end
  return false
end
-- (a paladin who may run PallyPower, silent on it 10 s, or asked and still silent: no SELF, and no hello that says
-- Cute Auras alone. One whose hello says PallyPower runs there is asked too: its SELF may have gone before we listened)
local function silent(m, t)
  return mayPP(m) and not Ps.pals[m.guid] and (asked[m.guid] or (seenAt[m.guid] and t >= seenAt[m.guid] + 10))
end
-- (our REQ as it leaves, not as it was queued: it waits there while one who would answer fights; stamped, counted, the
-- silent ones asked)
local function reqSent()
  local t = A.Now()
  reqAt = t
  count("sent"); count("sentReq")
  if reqFight then fightReqAt, reqFight = t, false end
  for _, m in ipairs(A.Roster.members) do
    if silent(m, t) then asked[m.guid] = (asked[m.guid] or 0) + 1 end
  end
end
-- what wants a REQ: look (Ps.Look's paladins), tab, fight, join (the time a REQ answers it from), pp (a member whose
-- hello now says PallyPower runs there)
local want = {}
local tryAt
local function later(at)
  if tryAt and tryAt > A.Now() and tryAt <= at then return end
  tryAt = at
  A.After(math.max(0, at - A.Now()) + 0.05, function()
    if tryAt ~= at then return end
    tryAt = nil
    Ps.Look()
  end, "pallysync: a REQ later")
end
function Ps.Try()
  local t = A.Now()
  if want.join and reqAt and reqAt >= want.join then want.join = nil end
  if next(want) == nil then return end
  if Ps.Here() or not A.Roster.InGroup() or not Ps.IsAsker() then
    for k in pairs(want) do want[k] = nil end
    return
  end
  -- (a fight: ours, or one who would answer; looked at again every 3 s)
  if A.Fighting() or ppFighting() then later(t + 3) return end
  -- (a REQ within 30 s: the tab's was answered by it, and the fight's by one that left after the fight ended (one before
  -- the pull carries nothing sent in it); a look, a newcomer or the fight's waits for the next)
  if since(reqAt) < 30 then
    want.tab = nil
    if want.fight and (fightEndAt == nil or reqAt >= fightEndAt) then want.fight = nil end
    if next(want) then later(reqAt + 30) end
    return
  end
  if want.join and not want.look and not want.tab and not want.fight and not want.pp and want.join > t then
    later(want.join)
    return
  end
  if not A.Comm.Send("REQ", PREFIX, { hold = ppFighting, sent = reqSent }) then
    for k in pairs(want) do want[k] = nil end
    return
  end
  if want.fight then reqFight = true end
  -- (a newcomer's REQ sent before our hello could reach it: one more once it has)
  local join = want.join
  for k in pairs(want) do want[k] = nil end
  if join and join > t then want.join = join; later(math.max(join, t + 30)) end
end
local lookAt
function Ps.Look()
  if not A.Roster.InGroup() then return end
  local t = A.Now()
  local wait, due = nil, false
  for _, m in ipairs(A.Roster.members) do
    if m.class == "PALADIN" and not m.me then
      seenAt[m.guid] = seenAt[m.guid] or t
      if not cuteOnly(m) and not Ps.pals[m.guid] and not asked[m.guid] then
        local at = seenAt[m.guid] + 10
        if t >= at then due = true elseif not wait or at < wait then wait = at end
      end
    end
  end
  if due then want.look = true else want.look = nil end
  Ps.Try()
  if wait and (not lookAt or lookAt <= t or wait < lookAt) then
    lookAt = wait
    A.After(wait - t + 0.1, function() if lookAt == wait then lookAt = nil; Ps.Look() end end, "pallysync: a look")
  end
end
-- the Blessings tab opened
function Ps.AskTab()
  if maybePP() then want.tab = true; Ps.Try() end
end
local function afterFight()
  Ps.Look()
  if since(fightReqAt) < 300 then return end
  local any = anyListed()
  if not any then
    -- (asked, and still silent: its answer may have been lost)
    for guid, n in pairs(asked) do
      local m = A.Roster.ByGUID(guid)
      if n < ASK_MAX and m and silent(m, A.Now()) then any = true end
    end
  end
  if any then want.fight = true; Ps.Try() end
end
-- a member running Cute Auras 0.2.3 or later heard for the first time, or one asking again (Q1): the PallyPower
-- paladins listed here are news to it. Asked again a few seconds on, once our hello (sent to it first) has reached it
function Ps.PeerHeard()
  if not anyListed() then return end
  want.join = math.max(want.join or 0, A.Now() + 4)
  later(want.join)
end
-- a member's hello now says PallyPower runs there, where it said Cute Auras alone (turned on, then a reload in the
-- group): PallyPower's SELF at that login left before this hello and was taken for our own, and nothing else asks for
-- it again. The asker asks (a REQ that went before this hello answered nothing)
function Ps.PPOn(guid)
  if Ps.pals[guid] then return end
  want.pp = true
  Ps.Try()
end

----------------------------------------------------------------------------
-- the group changing: members gone forgotten; leaving it, everything
----------------------------------------------------------------------------
local function prune(t)
  local gone = {}
  for guid in pairs(t) do if not A.Roster.ByGUID(guid) then gone[#gone + 1] = guid end end
  for _, guid in ipairs(gone) do t[guid] = nil end
  return #gone > 0
end
-- a member a leader's NASSIGN gave a cell of your column, gone from the group (left, or left while you reloaded): that
-- bucket gets back what the NASSIGN covered, so the next member there has the leader's class cell; the member's cell
-- waits (bk false) for them, as PallyPower keeps a member's own cell by name, and is theirs again as they come back.
-- Collected, then put back. moved (a fresh share-out, Ps.Changed, whose buckets list them): a member here and out of
-- the bucket the NASSIGN set (a role changed, back in the group), or one waiting: what each covered put back first,
-- every one, so no take reads another's cell as its bucket's own; then the cell theirs where they are now when they are
-- alone there (memberCell)
local function listed(bk, guid)
  for _, m in ipairs(A.Assign.buckets and A.Assign.buckets[bk] or {}) do if m.guid == guid then return true end end
  return false
end
function Ps.Settle(moved)
  local gone, away = {}, {}
  for guid, rec in pairs(nassigned) do
    local m = A.Roster.ByGUID(guid)
    if not moved then
      if not m and rec.bk then gone[#gone + 1] = guid end
    elseif m and not listed(rec.bk, guid) and listed(A.Assign.Bucket(m), guid) then away[#away + 1] = guid end
  end
  -- (a cell set since over the NASSIGN's: it is over)
  for _, guid in ipairs(gone) do
    local rec = nassigned[guid]
    if not live(rec) then nassigned[guid] = nil
    else putBackAll(rec); rec.bk = false end
  end
  local try = {}
  for _, guid in ipairs(away) do
    local rec = nassigned[guid]
    if rec.bk and not live(rec) then nassigned[guid] = nil
    else
      if rec.bk then putBackAll(rec) end
      rec.bk = false
      try[#try + 1] = guid
    end
  end
  for _, guid in ipairs(try) do
    local rec, m = nassigned[guid], A.Roster.ByGUID(guid)
    if rec and m and memberCell(m, rec.key) then count("taken") end
  end
end
function Ps.Prune()
  local any = prune(Ps.pals)
  any = prune(Ps.row) or any
  -- (a member's own cell from a paladin kept while they are away: PallyPower keeps it by name and casts it as they
  -- come back)
  any = prune(Ps.member) or any
  prune(seenAt); prune(asked)
  Ps.Settle()
  if any then changed() end
  Ps.Look()
end
function Ps.Forget()
  for _, t in ipairs({ Ps.pals, Ps.row, Ps.member, seenAt, asked, nassigned, Ps.mine }) do
    for k in pairs(t) do t[k] = nil end
  end
  for k in pairs(want) do want[k] = nil end
  Ps.heardAny, reqFight = false, false
  lastSent, lastLeft, lastBatchAt, reqAt, fightReqAt, lookAt, tryAt, fightEndAt = nil, nil, nil, nil, nil, nil, nil, nil
  armed = armed + 1
  dueAt, dueWhy = nil, nil
  changed()
end

----------------------------------------------------------------------------
-- kept over a reload (Comm.lua's group save): the listed paladins, their rows as 9 characters, their members' cells;
-- your column's class cells from a leader and the buckets its NASSIGNs set; the SELF of ours that last left in this
-- group, never one still queued (a paladin who fell silent still owes the empty one, and answers a REQ with it) and
-- that PallyPower was heard here (a leader alone on it lists no paladin, yet our SELF follows our cells)
----------------------------------------------------------------------------
function Ps.SaveTable()
  local mine, nass
  for class, c in pairs(Ps.mine) do
    mine = mine or {}
    mine[class] = { c[1] and KEY_DIGIT[c[1]] or "0", c[2] or 0 }
  end
  for guid, r in pairs(nassigned) do
    nass = nass or {}
    local pv = r.prev
    nass[guid] = { bk = r.bk or "-", class = r.class, key = r.key, stamp = r.stamp, under = r.under,
                   prev = pv and { key = pv.key, stamp = pv.stamp, pp = pv.pp and true or nil } or nil }
  end
  local heard = Ps.heardAny and true or nil
  if next(Ps.pals) == nil and not mine and not nass and lastLeft == nil and not heard then return nil end
  local pals, row, member = {}, {}, {}
  for guid, p in pairs(Ps.pals) do
    local r = p.ranks or {}
    pals[guid] = { w = r.wisdom or 0, m = r.might or 0, k = r.kings or 0, free = p.free }
  end
  for guid, r in pairs(Ps.row) do
    local s = {}
    for i, class in ipairs(Ps.CLASSES) do
      local c = r[class]
      s[i] = c and c[1] and KEY_DIGIT[c[1]] or "n"
    end
    row[guid] = table.concat(s)
  end
  for guid, list in pairs(Ps.member) do
    local t = {}
    for target, c in pairs(list) do if c[1] then t[target] = KEY_DIGIT[c[1]] end end
    member[guid] = t
  end
  return { pals = pals, row = row, member = member, mine = mine, nass = nass, sent = lastLeft, heard = heard }
end
local IS_CLASS = {}
for _, class in ipairs(Ps.CLASSES) do IS_CLASS[class] = true end
function Ps.Restore(saved)
  if type(saved) ~= "table" then return end
  -- (we spoke here: the next change, or the empty SELF owed, goes as before the reload; PallyPower heard here)
  local spoke = false
  if type(saved.sent) == "string" and lastSent == nil then lastSent, lastLeft, spoke = saved.sent, saved.sent, true end
  if saved.heard == true and not Ps.heardAny then Ps.heardAny, spoke = true, true end
  if spoke then changed() end
  for class, c in pairs(type(saved.mine) == "table" and saved.mine or {}) do
    if IS_CLASS[class] and type(c) == "table" and not Ps.mine[class] then
      Ps.mine[class] = { DIGIT_KEY[c[1]] or false, tonumber(c[2]) or 0 }
    end
  end
  -- (a member gone since is rebuilt too: Comm's Restore puts its bucket back once your cells are, Ps.Settle)
  for guid, r in pairs(type(saved.nass) == "table" and saved.nass or {}) do
    if type(r) == "table" and type(guid) == "string" and type(r.bk) == "string" and KEY_DIGIT[r.key] and not nassigned[guid] then
      local p = r.prev
      local pv = nil
      if type(p) == "table" and KEY_DIGIT[p.key] then pv = { key = p.key, stamp = tonumber(p.stamp) or 0, pp = p.pp and true or nil } end
      nassigned[guid] = { bk = r.bk ~= "-" and r.bk or false, class = IS_CLASS[r.class] and r.class or nil, key = r.key, stamp = tonumber(r.stamp) or 0,
                          under = KEY_DIGIT[r.under] and r.under or nil, prev = pv }
    end
  end
  if type(saved.pals) ~= "table" then return end
  local stamp, any = serverNow(), false
  -- (you too, PallyPower running here: its SELF at login, refused in a fight or a lockdown, is lost, and every other
  -- client still lists you; its next SELF replaces this one)
  for guid, p in pairs(saved.pals) do
    local m = A.Roster.ByGUID(guid)
    if type(p) == "table" and m and m.class == "PALADIN" and not Ps.pals[guid] and not cuteOnly(m) then
      Ps.pals[guid] = { ranks = { wisdom = tonumber(p.w) or 0, might = tonumber(p.m) or 0, kings = tonumber(p.k) or 0 },
                        at = stamp, free = type(p.free) == "string" and p.free or nil, restored = true }
      local s = type(saved.row) == "table" and saved.row[guid]
      if type(s) == "string" then
        local cells = readRow(s:sub(1, 9))
        local r = {}
        for class, key in pairs(cells) do r[class] = { key, stamp } end
        Ps.row[guid] = r
      end
      local list = type(saved.member) == "table" and saved.member[guid]
      if type(list) == "table" then
        local t = {}
        for target, dg in pairs(list) do
          if type(target) == "string" and DIGIT_KEY[dg] then t[target] = { DIGIT_KEY[dg], stamp } end
        end
        Ps.member[guid] = t
      end
      any = true
    end
  end
  -- (PallyPower was heard in this group before the reload: our SELF follows our cells again)
  if any then Ps.heardAny = true; changed() end
end

----------------------------------------------------------------------------
-- /cauras diag's line (numbers and words, never a name)
----------------------------------------------------------------------------
function Ps.DiagLine()
  local st = Ps.stats
  local function n(k) return st[k] or 0 end
  local here = "no"
  if Ps.Here() then
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata
    local v, t = plain(call(meta, "PallyPower", "Version")), plain(call(meta, "PallyPower", "Title"))
    here = "yes " .. tostring(v or "?") .. " (" .. tostring(t or "?") .. ")"
  end
  local pals = 0
  for guid in pairs(Ps.pals) do if A.Roster.ByGUID(guid) then pals = pals + 1 end end
  return string.format("PallyPower: here %s; asker %s; heard %d (SELF %d, set %d, clear %d, REQ %d, whispered %d, relayed %d, other %d); "
    .. "taken %d, refused %d, names unsure %d, bad %d, secret %d; paladins on it %d; sent %d (SELF %d, REQ %d); O1 refused for name %d",
    here, Ps.IsAsker() and "yes" or "no", n("heard"), n("self"), n("set"), n("clear"), n("req"), n("whispered"), n("relayed"), n("other"),
    n("taken"), n("refused"), n("unsure") + (A.Roster.unsure or 0), n("bad"), n("secret"), pals, n("sent"), n("sentSelf"), n("sentReq"),
    A.Comm.refusedName or 0)
end

function Ps:Init()
  A.On("PLAYER_REGEN_ENABLED", function() fightEndAt = A.Now(); A.After(2, afterFight, "pallysync: after a fight") end)
  local inGroup = A.Roster.InGroup()
  A.On("GROUP_ROSTER_UPDATE", function()
    local now = A.Roster.InGroup()
    if now and not inGroup then joinedAt = A.Now() end
    inGroup = now
    A.After(1.5, Ps.Look, "pallysync: a look")
  end)
  -- (a member gone offline or back: the asker may be another)
  A.On("UNIT_CONNECTION", function() A.After(1.5, Ps.Look, "pallysync: a look") end)
  A.After(1.5, Ps.Look, "pallysync: a look")
end
