-- SPDX-License-Identifier: GPL-3.0-or-later
-- The officers' visibility policy: per stat, "all" (everyone sees everyone's) or "self" (you see your own; officers
-- see all). Kept in CuteDB.policy; sent on the guild channel; applied only when it comes from an officer and is newer.
-- The rules' thresholds travel in it too (Rules.lua): an officer retunes one in Settings, and the guild applies it the
-- same way, with who set each (by GUID), so the rules adapt on launch day without an addon update.
local _, C = ...
local P = {}
C.Policy = P

local DEFAULT_THRESHOLD = 1 -- rank index 0 (guild master) and 1 count as officers

function P:Threshold()
  local p = CuteDB and CuteDB.policy
  return (p and type(p.threshold) == "number") and p.threshold or DEFAULT_THRESHOLD
end

-- what the officers set for a stat, or the registry's default. A statistic (a "g" stat with a game category) takes
-- its category's setting ("gc" .. the category id), a child category its parent's, and "all" where nothing is set:
-- the officers choose per statistics category, not per statistic. A discovered stat takes its category's,
-- "gc_bosses", "gc_dungeons", "gc_raids" or "gc_rep" (a letter after "gc_", so no game category id is the same; every
-- instance's bosses share Bosses')
function P:Vis(id, depth)
  local p = CuteDB and CuteDB.policy
  local v = p and p.vis and p.vis[id]
  if v == "all" or v == "self" then return v end
  depth = (depth or 0) + 1
  if depth > 4 then return "all" end
  local def = C.Stats.byId[id]
  if def and def.game then return self:Vis("gc" .. def.game, depth) end
  if def and def.learned then return self:Vis("gc_" .. def.learned, depth) end
  local cat = tonumber(id:match("^gc(%d+)$"))
  if cat then
    local e = C.Stats.game and C.Stats.game.byId[cat]
    if e and type(e.parent) == "number" and e.parent ~= -1 and e.parent ~= cat then return self:Vis("gc" .. e.parent, depth) end
    return "all"
  end
  return def and def.default or "all"
end

-- may this viewer see this row's value of this stat
function P:CanSee(viewerIsOfficer, rowIsMe, id)
  if viewerIsOfficer or rowIsMe then return true end
  return self:Vis(id) == "all"
end

-- the officers' changes, made here
function P:Set(id, vis)
  assert(vis == "all" or vis == "self")
  local me = C.Me()
  CuteDB.policy = CuteDB.policy or { vis = {} }
  local p = CuteDB.policy
  p.vis = p.vis or {}
  p.vis[id] = vis
  p.by, p.mine, p.rank, p.at = me, true, C.Roster:MyRank(), C.Now()
  p.threshold = p.threshold or DEFAULT_THRESHOLD
end
function P:SetThreshold(n)
  CuteDB.policy = CuteDB.policy or { vis = {} }
  local p = CuteDB.policy
  p.threshold, p.by, p.mine, p.rank, p.at = n, C.Me(), true, C.Roster:MyRank(), C.Now()
end

-- a threshold an officer set here: the policy is yours from then on, as with a visibility change; nil puts the
-- default back. Who set each is kept by GUID, and travels with it
function P:SetRule(name, value)
  CuteDB.policy = CuteDB.policy or { vis = {} }
  local p = CuteDB.policy
  p.vis = p.vis or {}
  p.rules = type(p.rules) == "table" and p.rules or {}
  p.ruleBy = type(p.ruleBy) == "table" and p.ruleBy or {}
  p.rules[name] = value
  p.ruleBy[name] = value ~= nil and (C.MyGUID() or "me") or nil
  p.by, p.mine, p.rank, p.at = C.Me(), true, C.Roster:MyRank(), C.Now()
  p.threshold = p.threshold or DEFAULT_THRESHOLD
  if C.Rules then C.Rules:Retuned() end
end

-- a threshold's value on the wire: whole numbers bare, shares to two places ("0.35")
local function ruleText(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return (string.format("%.2f", v):gsub("0+$", ""))
end
-- the policy as pieces for the wire: when it was set, the threshold, "id=a" / "id=s" parts and the rules'
-- "r_<name>=<value>:<who>" (the name lower case, who a GUID), sorted so the chunks are the same every time. A 0.4.0
-- client reads the visibility parts and passes the rules by
function P:Parts()
  local p = CuteDB.policy
  if not p then return nil end
  local parts = {}
  for id, v in pairs(p.vis or {}) do parts[#parts + 1] = id .. "=" .. (v == "self" and "s" or "a") end
  for name, v in pairs(type(p.rules) == "table" and p.rules or {}) do
    v = tonumber(v)
    if v and C.Rules and C.Rules.Valid(name, v) then
      local by = type(p.ruleBy) == "table" and p.ruleBy[name] or nil
      by = (by == "me" and C.MyGUID()) or by
      parts[#parts + 1] = "r_" .. name:lower() .. "=" .. ruleText(v) .. ((type(by) == "string" and by ~= "") and (":" .. by:gsub("[^%w%-]", "")) or "")
    end
  end
  table.sort(parts)
  return p.at or 0, p.threshold or DEFAULT_THRESHOLD, parts
end

-- a policy from the channel: applied when the sender is an officer by our roster and it is newer than ours. A long
-- policy comes in several messages sharing one "at": the first replaces ours, the rest add to it. Before the roster
-- is known the pieces of the newest one wait (P.pending) and Replay judges them once the ranks arrive.
function P:Receive(sender, at, threshold, body)
  at, threshold = tonumber(at), tonumber(threshold)
  if not (at and threshold) or threshold < 0 or threshold > 9 then return false, "malformed" end
  if not C.Roster.trusted then
    if not self.pending or self.pending.at < at then self.pending = { at = at, list = {} } end
    if self.pending.at == at then table.insert(self.pending.list, { sender = sender, at = at, threshold = threshold, body = body }) end
    return false, "roster not known yet"
  end
  if not C.Roster:IsOfficer(sender) then return false, "not an officer" end
  local p = CuteDB.policy
  if p and (p.at or 0) > at then return false, "older" end
  local vis = {}
  for id, v in (body or ""):gmatch("([%l%d_]+)=([as])") do vis[id] = v == "s" and "self" or "all" end
  -- the rules' thresholds: a name this client knows, a value inside its bounds, else passed by
  local rules, ruleBy = {}, {}
  for lname, v, who in (";" .. (body or "")):gmatch(";r_(%l+)=([%d%.]+):?([%w%-]*)") do
    local name, value = C.Rules and C.Rules.LOWER[lname], tonumber(v)
    if name and value and C.Rules.Valid(name, value) then rules[name] = value; ruleBy[name] = who ~= "" and who:sub(1, 40) or nil end
  end
  -- (p.by of a policy from the channel is the sender string it came under, compared with this one's as the table keys of
  -- CuteDB.roster are; your own policy is marked mine, its p.by your saved-data key, and is never compared with a sender)
  if p and not p.mine and p.at == at and p.by == sender then
    for id, v in pairs(vis) do p.vis[id] = v end
    p.rules, p.ruleBy = type(p.rules) == "table" and p.rules or {}, type(p.ruleBy) == "table" and p.ruleBy or {}
    for name, v in pairs(rules) do p.rules[name] = v; p.ruleBy[name] = ruleBy[name] end
    p.threshold = threshold
  else
    CuteDB.policy = { vis = vis, rules = rules, ruleBy = ruleBy, by = sender, rank = C.Roster:Rank(sender), at = at, threshold = threshold }
  end
  if C.Rules then C.Rules:Retuned() end
  if C.UI and C.UI.Refresh then C.UI:Refresh() end
  return true
end
function P:Replay()
  local w = self.pending
  if not w or not C.Roster.trusted then return end
  self.pending = nil
  local ok
  for _, m in ipairs(w.list) do ok = self:Receive(m.sender, m.at, m.threshold, m.body) or ok end
  return ok
end

-- who set it, for Settings
function P:Describe()
  local p = CuteDB.policy
  if not p or not p.by then return "No policy set: the defaults apply." end
  local when = (date and p.at) and date("%Y-%m-%d %H:%M", p.at) or "?"
  return string.format("Set by %s, %s.", p.mine and C.Roster:MyDisplay() or C.Roster:Display(p.by), when)
end
