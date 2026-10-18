-- SPDX-License-Identifier: GPL-3.0-or-later
-- The officers' visibility policy: per stat, "all" (everyone sees everyone's) or "self" (you see your own; officers
-- see all). Kept in CuteDB.policy; sent on the guild channel; applied only when it comes from an officer and is newer.
local _, C = ...
local P = {}
C.Policy = P

local DEFAULT_THRESHOLD = 1 -- rank index 0 (guild master) and 1 count as officers

function P:Threshold()
  local p = CuteDB and CuteDB.policy
  return (p and type(p.threshold) == "number") and p.threshold or DEFAULT_THRESHOLD
end

-- what the officers set for a stat, or the registry's default
function P:Vis(id)
  local p = CuteDB and CuteDB.policy
  local v = p and p.vis and p.vis[id]
  if v == "all" or v == "self" then return v end
  local def = C.Stats.byId[id]
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
  p.by, p.rank, p.at = me, C.Roster:Rank(me), C.Now()
  p.threshold = p.threshold or DEFAULT_THRESHOLD
end
function P:SetThreshold(n)
  CuteDB.policy = CuteDB.policy or { vis = {} }
  local p = CuteDB.policy
  p.threshold, p.by, p.rank, p.at = n, C.Me(), C.Roster:Rank((C.Me())), C.Now()
end

-- "at|threshold|id=v;id=v" for the wire
function P:Encode()
  local p = CuteDB.policy
  if not p then return nil end
  local parts = {}
  for id, v in pairs(p.vis or {}) do parts[#parts + 1] = id .. "=" .. (v == "self" and "s" or "a") end
  table.sort(parts)
  return string.format("%d|%d|%s", p.at or 0, p.threshold or DEFAULT_THRESHOLD, table.concat(parts, ";"))
end

-- a policy from the channel: applied when the sender is an officer by our roster and it is newer than ours
function P:Receive(sender, at, threshold, body)
  at, threshold = tonumber(at), tonumber(threshold)
  if not (at and threshold) then return false, "malformed" end
  if not C.Roster:IsOfficer(sender) then return false, "not an officer" end
  local p = CuteDB.policy
  if p and (p.at or 0) >= at then return false, "older" end
  local vis = {}
  for id, v in (body or ""):gmatch("([%l%d_]+)=([as])") do vis[id] = v == "s" and "self" or "all" end
  CuteDB.policy = { vis = vis, by = sender, rank = C.Roster:Rank(sender), at = at, threshold = threshold }
  if C.UI and C.UI.Refresh then C.UI:Refresh() end
  return true
end

-- who set it, for Settings
function P:Describe()
  local p = CuteDB.policy
  if not p or not p.by then return "No policy set: the defaults apply." end
  local when = (date and p.at) and date("%Y-%m-%d %H:%M", p.at) or "?"
  return string.format("Set by %s, %s.", C.Short(p.by), when)
end
