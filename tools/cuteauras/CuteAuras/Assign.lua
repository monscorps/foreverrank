-- SPDX-License-Identifier: GPL-3.0-or-later
-- Who gives which buff to whom: the same answer on every client, from the roster and what each member's Cute Auras
-- announced (Comm.lua). Members without Cute Auras are never given a duty; their buffs still count as on.
--   single buffs  Fortitude, Divine Spirit, Arcane Intellect, Mark of the Wild, Shadow Protection (when its buffers
--                 switched it on), Thorns and Earth Shield (tanks): only the buffers with the highest rank announced
--                 give it; in a raid, subgroup s goes to buffer ((s - 1) mod n) + 1 in GUID order; in a party the first
--                 buffer gives all. One tank a buffer for a single-target buff
--   blessings     each member's bucket is class and role; a bucket's wishes come from the role (tank: Kings, Might;
--                 melee: Might, Kings; hunters: Kings, Wisdom; casters and healers: Wisdom, Kings; never Wisdom without
--                 a mana bar). Paladins sort by level, then GUID. Each wish in order goes to the paladin still free for
--                 that bucket who knows it and knows the fewest of the wishes left (the first in order on a tie: with
--                 paladins who know the same, the k-th gives the k-th wish). Then a class over two buckets (warriors
--                 with a tank) is lined up so each paladin gives the whole class one blessing, a Greater one's chance.
--                 A blessing set by hand in the grid wins over the choice. A paladin heard on PallyPower (PallySync.lua)
--                 has a column too: its PallyPower cells come first and are never moved; one running PallyPower alone
--                 gets no wish and no duty, nor does one running both whose Cute Auras gives no blessing; one running
--                 both fills what PallyPower left empty
--   who gives you  every buffer's share, not only yours (As.GiverOf, As.BlesserOf): the bar's reminder of a buff
--                 someone else gives you (Buffs.lua) names that buffer, on every client the same, no message sent
local _, A = ...
local As = A.Part("Assign", { duties = {}, owe = {}, bless = {}, buckets = {}, overrides = {}, gen = 0, giver = {}, shared = {},
  blessFrom = {} })
local S, D = A.Spells, A.Data

-- the buffs castable on others, by key (any class's)
local OTHER = {}
for class, list in pairs(D.BUFFS) do
  for _, e in ipairs(list) do if e.other then e.class = class; OTHER[e.key] = e end end
end
As.OTHER = OTHER
As.BLESS_KEYS = { "kings", "might", "wisdom" }

local function wants(e, m)
  if e.want == "all" then return true end
  if e.want == "mana" then return m.mana == true end
  if e.want == "tank" then return m.role == "tank" end
  return false
end
As.Wants = wants

-- a member's blessing wishes, best first
local WISH = { tank = { "kings", "might" }, melee = { "might", "kings" }, ranged = { "kings", "wisdom" },
  caster = { "wisdom", "kings" }, healer = { "wisdom", "kings" } }
function As.Wishes(m)
  local base = WISH[m.role or ""] or WISH.melee
  local out = {}
  for _, k in ipairs(base) do if k ~= "wisdom" or m.mana then out[#out + 1] = k end end
  -- (a paladin tank and a melee with a mana bar, Retribution or Enhancement, take Wisdom third; a feral druid does not)
  if (m.role == "tank" and m.class == "PALADIN") or (m.role == "melee" and m.mana and m.class ~= "DRUID" and m.class ~= "HUNTER") then
    out[#out + 1] = "wisdom"
  end
  return out
end
function As.Bucket(m) return (m.class or "?") .. ":" .. (m.role or "melee") end

-- what a member's Cute Auras gives: their hello's buffs (yours read now), else nil
local function helloOf(m)
  if m.me then return A.Comm.ParseKnown(A.Comm.Known()) end
  local p = A.Comm.peers[m.guid]
  return p and p.known or nil
end
local function hasBless(k) return k ~= nil and ((k.kings or 0) + (k.might or 0) + (k.wisdom or 0)) > 0 end
-- what a member gives: their announced buffs; a paladin heard on PallyPower, the blessing ranks its SELF says too (one
-- running both whose Cute Auras gives no blessing, or puts one on Never, still casts PallyPower's); on PallyPower
-- alone, those alone
local function withPP(k, m)
  local Ps = A.PallySync
  local pk = Ps and Ps.pals[m.guid] and Ps.Known(m.guid) or nil
  if not pk then return k end
  if not k then return pk end
  local out = {}
  for key, r in pairs(k) do out[key] = r end
  for key, r in pairs(pk) do if (out[key] or 0) < r then out[key] = r end end
  return out
end
local function knownOf(m) return withPP(helloOf(m), m) end
As.KnownOf = knownOf
-- (what its own Cute Auras gives: a cell Cute Auras fills, or one set by hand, takes only these)
As.HelloOf = helloOf
-- (the ranks a paladin's PallyPower cells count: its SELF's, else what it announced)
local function cellKnown(m)
  local Ps = A.PallySync
  return (Ps and Ps.pals[m.guid] and Ps.Known(m.guid)) or knownOf(m)
end
local function byGUID(a, b) return a.guid < b.guid end

----------------------------------------------------------------------------
-- the computation
----------------------------------------------------------------------------
local function compute()
  local members = A.Roster.members
  local raid = A.Roster.InRaid()
  local me = A.MyGUID()
  local duties, owe, bless = {}, {}, {}
  -- (every buffer's share: giver[key][target GUID] = the buffer's GUID; shared[key]: a buffer running Cute Auras gives it)
  local giver, shared = {}, {}
  local known, hello = {}, {}
  for _, m in ipairs(members) do
    local h = helloOf(m)
    hello[m.guid], known[m.guid] = h, withPP(h, m)
  end

  -- single buffs
  local order = {}
  for key, e in pairs(OTHER) do order[#order + 1] = key end
  table.sort(order)
  local dutyOf = {}
  local function duty(key, e, isBless)
    local d = dutyOf[key]
    if not d then
      d = { key = key, entry = e, bless = isBless, targets = {}, greater = {} }
      dutyOf[key] = d
      duties[#duties + 1] = d
    end
    return d
  end
  local function owes(m, e, key)
    local list = owe[m.guid]
    if not list then list = {}; owe[m.guid] = list end
    list[#list + 1] = { key = key, entry = e }
  end
  for _, key in ipairs(order) do
    local e = OTHER[key]
    local buffers = {}
    for _, m in ipairs(members) do
      local k = known[m.guid]
      if k and (k[key] or 0) > 0 and m.online ~= false then buffers[#buffers + 1] = m end
    end
    if #buffers > 0 then
      -- (only the buffers with the highest rank announced: a low-level buffer's weaker rank would count as on for its
      -- hour and nobody would be asked to replace it; a high rank still casts the rank a low-level target takes)
      local best = 0
      for _, m in ipairs(buffers) do best = math.max(best, known[m.guid][key]) end
      for i = #buffers, 1, -1 do if known[buffers[i].guid][key] < best then table.remove(buffers, i) end end
      table.sort(buffers, byGUID)
      shared[key] = true
      local gives = {}
      giver[key] = gives
      if e.single then
        -- (one target a buffer: the tanks in GUID order, the k-th to the k-th buffer)
        local tanks = {}
        for _, m in ipairs(members) do if wants(e, m) then tanks[#tanks + 1] = m end end
        table.sort(tanks, byGUID)
        for i, m in ipairs(tanks) do
          local b = buffers[i]
          if b then gives[m.guid] = b.guid end
          if b and b.guid == me then duty(key, e).targets[#duty(key, e).targets + 1] = m; owes(m, e, key) end
        end
      else
        for _, m in ipairs(members) do
          if wants(e, m) then
            local b = raid and buffers[((m.sub - 1) % #buffers) + 1] or buffers[1]
            gives[m.guid] = b.guid
            if b.guid == me then
              local d = duty(key, e)
              d.targets[#d.targets + 1] = m
              owes(m, e, key)
            end
          end
        end
      end
    end
  end

  -- blessings
  local Ps = A.PallySync
  local paladins = {}
  -- (ppOnly [GUID] = true: PallyPower alone, or running both with Cute Auras' own blessings off; no wish, no duty, no
  -- cell set by hand, its cells PallyPower's alone)
  local ppOnly = {}
  for _, m in ipairs(members) do
    local k = known[m.guid]
    if m.class == "PALADIN" and hasBless(k) and m.online ~= false then
      paladins[#paladins + 1] = m
      if Ps and Ps.pals[m.guid] and not hasBless(hello[m.guid]) then ppOnly[m.guid] = true end
    end
  end
  table.sort(paladins, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.guid < b.guid end)
  local buckets, bucketList = {}, {}
  for _, m in ipairs(members) do
    local b = As.Bucket(m)
    local list = buckets[b]
    if not list then list = { key = b, class = m.class, role = m.role, wishes = As.Wishes(m) }; buckets[b] = list; bucketList[#bucketList + 1] = list end
    list[#list + 1] = m
  end
  table.sort(bucketList, function(a, b) return a.key < b.key end)
  for _, pal in ipairs(paladins) do bless[pal.guid] = {} end
  local fixedIn = {} -- [bucket key] = { [paladin GUID] = true }: the blessings set by hand there, never moved below
  local ppCell = {}  -- [paladin GUID] = { [bucket key] = true }: set in PallyPower
  for _, b in ipairs(bucketList) do
    local given = {}
    local fixed = {}
    fixedIn[b.key] = fixed
    -- PallyPower's cells first: a member's own cell when the bucket's every member has the same, else the class's; one
    -- that paladin knows
    for _, pal in ipairs(paladins) do
      local key = Ps and Ps.pals[pal.guid] and Ps.Cell(pal.guid, b) or nil
      local k = key and cellKnown(pal)
      if key and k and (k[key] or 0) > 0 then
        fixed[pal.guid] = true
        bless[pal.guid][b.key] = key; given[key] = true
        ppCell[pal.guid] = ppCell[pal.guid] or {}
        ppCell[pal.guid][b.key] = true
      end
    end
    for _, pal in ipairs(paladins) do
      local ov = As.overrides[pal.guid] and As.overrides[pal.guid][b.key]
      local k = hello[pal.guid]
      -- (a clear, or a blessing that paladin doesn't give: Cute Auras' choice for them instead, never a blank)
      if not fixed[pal.guid] and not ppOnly[pal.guid] and ov and not ov.clear and ov.key and k and (k[ov.key] or 0) > 0 then
        fixed[pal.guid] = true
        bless[pal.guid][b.key] = ov.key; given[ov.key] = true
      end
    end
    -- each wish in order to the paladin free for this bucket who knows it and knows the fewest of the wishes still open,
    -- so one who knows more is kept for a wish only they give (a level 26 paladin's Kings beside a level 14's Might);
    -- a tie goes to the first in the paladins' order
    for wi, x in ipairs(b.wishes) do
      if not given[x] then
        local pick, pickN
        for _, pal in ipairs(paladins) do
          -- (the wishes go by what its own Cute Auras gives: a blessing on Never there is none)
          local k = hello[pal.guid] or {}
          if not ppOnly[pal.guid] and not bless[pal.guid][b.key] and (k[x] or 0) > 0 then
            local n = 0
            for j = wi, #b.wishes do
              local y = b.wishes[j]
              if not given[y] and (k[y] or 0) > 0 then n = n + 1 end
            end
            if not pickN or n < pickN then pick, pickN = pal, n end
          end
        end
        if pick then bless[pick.guid][b.key] = x; given[x] = true end
      end
    end
  end
  -- a class over two or more buckets (warrior damage and a warrior tank): where the paladins free in a bucket give it
  -- the same blessings as they give the class's largest bucket, only in another order, each gives it the one they give
  -- there. Every bucket keeps the blessings it had, and a paladin now gives the whole class one blessing, so a Greater
  -- one can do it
  local ref = {}
  for _, b in ipairs(bucketList) do
    local c = b.class or "?"
    local r = ref[c]
    if not r or #b > #r or (#b == #r and b.key < r.key) then ref[c] = b end
  end
  local function setOf(list)
    table.sort(list)
    return table.concat(list, ",")
  end
  for _, b in ipairs(bucketList) do
    local r = ref[b.class or "?"]
    if r ~= b then
      local fixed = fixedIn[b.key]
      local here, there = {}, {}
      for _, pal in ipairs(paladins) do
        if not fixed[pal.guid] and not ppOnly[pal.guid] then
          here[#here + 1] = bless[pal.guid][b.key]
          there[#there + 1] = bless[pal.guid][r.key]
        end
      end
      if #here > 0 and setOf(here) == setOf(there) then
        for _, pal in ipairs(paladins) do
          if not fixed[pal.guid] and not ppOnly[pal.guid] then bless[pal.guid][b.key] = bless[pal.guid][r.key] end
        end
      end
    end
  end
  -- who gives each bucket each blessing (the first paladin in the paladins' order, should two give the same)
  local blessFrom = {}
  for _, pal in ipairs(paladins) do
    for bk, key in pairs(bless[pal.guid]) do
      local t = blessFrom[bk]
      if not t then t = {}; blessFrom[bk] = t end
      if not t[key] then t[key] = pal.guid end
    end
  end
  -- your blessings as duties, one a blessing; Greater for a class whose every bucket takes the same from you (none
  -- while your own Cute Auras gives no blessing: your PallyPower casts that column)
  local mine = me and not ppOnly[me] and bless[me]
  if mine then
    local classKey = {}
    for _, b in ipairs(bucketList) do
      local key = mine[b.key]
      local c = b.class or "?"
      if classKey[c] == nil then classKey[c] = key or false elseif classKey[c] ~= key then classKey[c] = false end
      if key then
        local d = duty("bless:" .. key, D.BLESS[key], true)
        d.blessKey = key
        for _, m in ipairs(b) do d.targets[#d.targets + 1] = m; owes(m, D.BLESS[key], "bless:" .. key) end
      end
    end
    for c, key in pairs(classKey) do
      if key then dutyOf["bless:" .. key].greater[c] = true end
    end
  end
  -- (the duties in a fixed order: blessings, then the buffs by key)
  table.sort(duties, function(a, b)
    if a.bless ~= b.bless then return a.bless end
    return a.key < b.key
  end)
  -- (since when each of your cells is what it is now: a blessing of yours put on before that teaches nothing, Teach)
  local was, t = (me and As.bless[me]) or {}, A.Now()
  local since = {}
  for bk, key in pairs(mine or {}) do since[bk] = (was[bk] == key and As.cellSince and As.cellSince[bk]) or t end
  As.cellSince = since
  As.duties, As.owe, As.bless, As.buckets, As.bucketList, As.paladins = duties, owe, bless, buckets, bucketList, paladins
  As.giver, As.shared, As.blessFrom, As.ppCell, As.ppOnly = giver, shared, blessFrom, ppCell, ppOnly
  As.gen = As.gen + 1
end
As.Compute = compute

-- what you owe a member now: { { key, entry }, ... } or nil
function As.Owed(guid) return As.owe[guid] end
-- the blessing a paladin gives a bucket
function As.BlessingOf(palGUID, bucketKey) return As.bless[palGUID] and As.bless[palGUID][bucketKey] end
-- who the share-out gives a member's buff to, any buffer's: that buffer's GUID, else nil (nobody, or they don't want it)
function As.GiverOf(key, guid) local g = As.giver[key]; return g and g[guid] or nil end
-- a buffer running Cute Auras gives this buff: the share-out has it, whoever it goes to
function As.Shared(key) return As.shared[key] == true end
-- the paladin who gives a bucket a blessing, else nil
function As.BlesserOf(bucketKey, blessKey) local t = As.blessFrom[bucketKey]; return t and t[blessKey] or nil end
-- where a paladin's cell comes from: "pp" (set in PallyPower: a PallyPower cell of theirs there, or every cell of a
-- paladin on PallyPower alone), else "cute"
function As.Source(palGUID, bucketKey)
  if As.ppOnly and As.ppOnly[palGUID] then return "pp" end
  if bucketKey and As.ppCell and As.ppCell[palGUID] and As.ppCell[palGUID][bucketKey] then return "pp" end
  return "cute"
end
-- the paladin who gives one member a blessing, and where it was set ("pp", "cute"): a PallyPower paladin's own cell for
-- that member first (another blessing there: that paladin gives them that one instead), then the bucket's
function As.BlesserFor(m, blessKey)
  local Ps = A.PallySync
  local bk = As.Bucket(m)
  if Ps then
    for _, pal in ipairs(As.paladins or {}) do
      if Ps.pals[pal.guid] and Ps.MemberCell(pal.guid, m.guid) == blessKey then
        local k = cellKnown(pal)
        if k and (k[blessKey] or 0) > 0 then return pal.guid, "pp" end
      end
    end
  end
  local function other(pg)
    local c = Ps and Ps.pals[pg] and Ps.MemberCell(pg, m.guid)
    return c ~= nil and c ~= blessKey
  end
  local g = As.BlesserOf(bk, blessKey)
  if g and other(g) then
    g = nil
    for _, pal in ipairs(As.paladins or {}) do
      if As.bless[pal.guid] and As.bless[pal.guid][bk] == blessKey and not other(pal.guid) then g = pal.guid break end
    end
  end
  if not g then return nil end
  return g, As.Source(g, bk)
end

----------------------------------------------------------------------------
-- blessings set by hand: the paladin for their own, the group's leader or an assist for anyone's. Kept until you leave
-- the group, sent again to each member heard for the first time, and the ones you set kept over a reload or a relog
-- (Comm.lua saves them with the group's hellos at logout)
----------------------------------------------------------------------------
local function mayChange(fromGUID, palGUID)
  if fromGUID == palGUID then return true end
  local m = A.Roster.ByGUID(fromGUID)
  if not m then return false end
  return A.Yes(UnitIsGroupLeader, m.unit) or A.Yes(UnitIsGroupAssistant, m.unit)
end
As.MayChange = mayChange
-- (pp: a PallyPower leader set it for that paladin, who took it as its own: PallySync.lua)
function As.SetOverride(pal, bucket, key, stamp, from, pp)
  if not mayChange(from, pal) then return false end
  stamp = stamp or 0
  As.overrides[pal] = As.overrides[pal] or {}
  local was = As.overrides[pal][bucket]
  -- (the newest wins; two set in the same second: the setter with the higher GUID, so every client keeps the same one)
  if was and (was.stamp > stamp or (was.stamp == stamp and (was.from or "") > (from or ""))) then return false end
  -- (a clear is kept, stamped, so an older blessing still waiting out a lockdown can't win after it; compute() and the
  -- grid read it as Cute Auras' choice)
  As.overrides[pal][bucket] = { key = key, stamp = stamp, from = from, clear = key == nil, pp = pp and true or nil }
  As.Changed()
  return true
end
local function o1(me, pal, bucket, ov)
  return string.format("O1|%s|%s|%s|%s|%d", me, pal, bucket, ov.key or "-", ov.stamp or 0) .. (ov.pp and "|pp" or "")
end
-- the blessings you set by hand, sent again with their stamps (a member heard for the first time, a reload's Q1)
function As.Resend()
  local me = A.MyGUID()
  for pal, list in pairs(As.overrides) do
    for bucket, ov in pairs(list) do
      if ov.from == me then A.Comm.Send(o1(me, pal, bucket, ov)) end
    end
  end
end
-- the ones you set, for the saved variables: { { pal, bucket, key or "-", stamp, "pp" or nil }, ... }
function As.Mine()
  local me, out = A.MyGUID(), {}
  for pal, list in pairs(As.overrides) do
    for bucket, ov in pairs(list) do
      if ov.from == me then out[#out + 1] = { pal, bucket, ov.key or "-", ov.stamp or 0, ov.pp and "pp" or nil } end
    end
  end
  return out
end
-- back after a reload: yours again as they were (each still checked, a newer one heard meanwhile wins), then sent
function As.Restore(list)
  if type(list) ~= "table" then return end
  local me = A.MyGUID()
  for _, o in ipairs(list) do
    if type(o) == "table" and type(o[1]) == "string" and type(o[2]) == "string" and A.Roster.ByGUID(o[1]) then
      As.SetOverride(o[1], o[2], o[3] ~= "-" and o[3] or nil, tonumber(o[4]) or 0, me, o[5] == "pp")
    end
  end
  As.Resend()
end
-- you left the group: what was set there is let go
function As.Forget()
  for k in pairs(As.overrides) do As.overrides[k] = nil end
  As.Changed()
end
-- from the grid: key nil puts the bucket back to Cute Auras' choice. pp: a PallyPower leader's choice for your column,
-- sent as your own (O1's field 7)
function As.Set(pal, bucket, key, pp)
  local me = A.MyGUID()
  local stamp = (GetServerTime and A.Plain(A.Call(GetServerTime))) or (time and time()) or 0
  if not As.SetOverride(pal, bucket, key, stamp, me, pp) then return false end
  A.Comm.Send(o1(me, pal, bucket, As.overrides[pal][bucket]))
  return true
end
-- your own casts set your column (out of a fight, PallyPower not here; Buffs.lua reads them): every member of a bucket
-- you give, in sight, carrying a blessing of yours of one kind that is not your cell, none of the other paladins giving
-- them that kind, and your cell Cute Auras' choice or one you set (never the leader's, an O1 of theirs or pp): that
-- kind, set by hand and sent
function As.Teach(bucket, key)
  local me = A.MyGUID()
  local mine = me and As.bless[me]
  if not (mine and mine[bucket]) or mine[bucket] == key or A.Fighting() then return false end
  if As.Source(me, bucket) == "pp" then return false end
  for _, pal in ipairs(As.paladins or {}) do
    if pal.guid ~= me and As.bless[pal.guid] and As.bless[pal.guid][bucket] == key then return false end
  end
  local ov = As.overrides[me] and As.overrides[me][bucket]
  if ov and (ov.from ~= me or ov.pp) then return false end
  local m = A.Roster.Me()
  local k = m and knownOf(m)
  if not (k and (k[key] or 0) > 0) then return false end
  return As.Set(me, bucket, key)
end

----------------------------------------------------------------------------
-- a change: one computation for a burst, then the bar, the rebuff handler and the grid
----------------------------------------------------------------------------
local soon = false
function As.Changed()
  if soon then return end
  soon = true
  A.After(0.2, function()
    soon = false
    compute()
    if A.Bar then A.Bar.Dirty("group") end
    if A.Rebuff then A.Rebuff.Update() end
    if A.Window and A.Window.Refresh then A.Window.Refresh() end
    -- (our SELF to PallyPower users, when it changed)
    if A.PallySync then A.PallySync.Changed() end
  end, "assign")
end

function As:Init()
  compute()
  A.On("SPELLS_CHANGED", As.Changed)
end
