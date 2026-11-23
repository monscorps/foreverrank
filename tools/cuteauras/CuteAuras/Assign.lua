-- SPDX-License-Identifier: GPL-3.0-or-later
-- Who gives which buff to whom: the same answer on every client, from the roster and what each member's Cute Auras
-- announced (Comm.lua). Members without Cute Auras are never given a duty; their buffs still count as on.
--   single buffs  Fortitude, Divine Spirit, Arcane Intellect, Mark of the Wild, Shadow Protection (when its buffers
--                 switched it on), Thorns and Earth Shield (tanks): in a raid, subgroup s goes to buffer ((s - 1) mod n)
--                 + 1 in GUID order; in a party the first buffer gives all. One tank a buffer for a single-target buff
--   blessings     each member's bucket is class and role; a bucket's wishes come from the role (tank: Kings, Might;
--                 melee: Might, Kings; hunters: Kings, Wisdom; casters and healers: Wisdom, Kings; never Wisdom without
--                 a mana bar). Paladins sort by level, then GUID: the k-th gives each bucket its k-th wish they know,
--                 else the best one left. A blessing set by hand in the grid wins over the choice
local _, A = ...
local As = A.Part("Assign", { duties = {}, owe = {}, bless = {}, buckets = {}, overrides = {}, gen = 0 })
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

-- what a member gives: their announced buffs (yours read now)
local function knownOf(m)
  if m.me then return A.Comm.ParseKnown(A.Comm.Known()) end
  local p = A.Comm.peers[m.guid]
  return p and p.known or nil
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
  local known = {}
  for _, m in ipairs(members) do known[m.guid] = knownOf(m) end

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
      table.sort(buffers, byGUID)
      if e.single then
        -- (one target a buffer: the tanks in GUID order, the k-th to the k-th buffer)
        local tanks = {}
        for _, m in ipairs(members) do if wants(e, m) then tanks[#tanks + 1] = m end end
        table.sort(tanks, byGUID)
        for i, m in ipairs(tanks) do
          local b = buffers[i]
          if b and b.guid == me then duty(key, e).targets[#duty(key, e).targets + 1] = m; owes(m, e, key) end
        end
      else
        for _, m in ipairs(members) do
          if wants(e, m) then
            local b = raid and buffers[((m.sub - 1) % #buffers) + 1] or buffers[1]
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
  local paladins = {}
  for _, m in ipairs(members) do
    local k = known[m.guid]
    if m.class == "PALADIN" and k and ((k.kings or 0) + (k.might or 0) + (k.wisdom or 0)) > 0 and m.online ~= false then
      paladins[#paladins + 1] = m
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
  for _, b in ipairs(bucketList) do
    local given = {}
    local fixed = {}
    for _, pal in ipairs(paladins) do
      local ov = As.overrides[pal.guid] and As.overrides[pal.guid][b.key]
      if ov then
        fixed[pal.guid] = true
        local k = known[pal.guid]
        if ov.key and k and (k[ov.key] or 0) > 0 then bless[pal.guid][b.key] = ov.key; given[ov.key] = true end
      end
    end
    for i, pal in ipairs(paladins) do
      if not fixed[pal.guid] then
        local k = known[pal.guid]
        local pick
        local w = b.wishes[i]
        if w and not given[w] and (k[w] or 0) > 0 then pick = w end
        if not pick then
          for _, x in ipairs(b.wishes) do if not given[x] and (k[x] or 0) > 0 then pick = x; break end end
        end
        if pick then bless[pal.guid][b.key] = pick; given[pick] = true end
      end
    end
  end
  -- your blessings as duties, one a blessing; Greater for a class whose every bucket takes the same from you
  local mine = me and bless[me]
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
  As.duties, As.owe, As.bless, As.buckets, As.bucketList, As.paladins = duties, owe, bless, buckets, bucketList, paladins
  As.gen = As.gen + 1
end
As.Compute = compute

-- what you owe a member now: { { key, entry }, ... } or nil
function As.Owed(guid) return As.owe[guid] end
-- the blessing a paladin gives a bucket
function As.BlessingOf(palGUID, bucketKey) return As.bless[palGUID] and As.bless[palGUID][bucketKey] end

----------------------------------------------------------------------------
-- blessings set by hand: the paladin for their own, the group's leader or an assist for anyone's. Kept for the session
-- and sent again to each member heard for the first time
----------------------------------------------------------------------------
local function mayChange(fromGUID, palGUID)
  if fromGUID == palGUID then return true end
  local m = A.Roster.ByGUID(fromGUID)
  if not m then return false end
  return A.Yes(UnitIsGroupLeader, m.unit) or A.Yes(UnitIsGroupAssistant, m.unit)
end
As.MayChange = mayChange
function As.SetOverride(pal, bucket, key, stamp, from)
  if not mayChange(from, pal) then return false end
  As.overrides[pal] = As.overrides[pal] or {}
  local was = As.overrides[pal][bucket]
  if was and (was.stamp or 0) > (stamp or 0) then return false end
  As.overrides[pal][bucket] = { key = key, stamp = stamp or 0, from = from, clear = key == nil }
  if key == nil then As.overrides[pal][bucket] = nil end
  As.Changed()
  return true
end
-- the blessings you set by hand, sent again with their stamps (a member heard for the first time, a reload's Q1)
function As.Resend()
  local me = A.MyGUID()
  for pal, list in pairs(As.overrides) do
    for bucket, ov in pairs(list) do
      if ov.from == me then A.Comm.Send(string.format("O1|%s|%s|%s|%s|%d", me, pal, bucket, ov.key or "-", ov.stamp or 0)) end
    end
  end
end
-- from the grid: key nil puts the bucket back to Cute Auras' choice
function As.Set(pal, bucket, key)
  local me = A.MyGUID()
  local stamp = (GetServerTime and A.Plain(A.Call(GetServerTime))) or (time and time()) or 0
  if not As.SetOverride(pal, bucket, key, stamp, me) then return false end
  A.Comm.Send(string.format("O1|%s|%s|%s|%s|%d", me, pal, bucket, key or "-", stamp))
  return true
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
  end, "assign")
end

function As:Init()
  compute()
  A.On("SPELLS_CHANGED", As.Changed)
end
