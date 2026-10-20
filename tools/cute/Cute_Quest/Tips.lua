-- SPDX-License-Identifier: GPL-3.0-or-later
-- Tooltip progress (6.0): a mob or object you hover that counts for a quest in your log gets a line, "Kobold Vermin:
-- 3/8 (Kobold Camp Cleanup)", and the party's counts where Sync knows them ("Brann 6/8"). Through the game's own
-- tooltip hooks (TooltipDataProcessor.AddTooltipPostCall, the unit and object types), reading the tooltip's data: the
-- name on its first line, matched against each objective's text; the guid read through QB.Plain, and nothing shown
-- when the name or the guid is a secret value. Only reads, only its lines; nothing in chat. The line tables are
-- pooled: a hover makes its strings and nothing more.
local _, QB = ...
if QB.dormant then return end
local Tips = {}
QB.Tips = Tips

local plain = QB.Plain
local out, pool, parts = {}, {}, {}
local function on() return QB:Settings().tipProgress ~= false end

-- the lines for a name: one per quest in your log whose objective names it, with the party's counts
function Tips.Lines(name)
  for k = #out, 1, -1 do out[k] = nil end
  if type(name) ~= "string" or name == "" then return out end
  local G, S = QB.Guide, QB.Sync
  if not (G and G.ParseLine) then return out end
  local lname = name:lower()
  local grouped = S and S.members and type(IsInGroup) == "function" and plain(IsInGroup()) == true
  for _, e in ipairs(QB.state.logOrder or {}) do
    if not e.complete then
      for _, o in ipairs(e.objectives or {}) do
        local oname, have, need = G.ParseLine(o.text)
        if oname and have and need and oname:lower() == lname then
          local q = QB.Quest.Get(e.id)
          local n = #out + 1
          local line = pool[n]
          if not line then line = {}; pool[n] = line end
          line.text = string.format("%s: %d/%d (%s)", name, have, need, q and q.name or plain(e.title) or ("Quest " .. e.id))
          line.party = nil
          if grouped then
            for k = #parts, 1, -1 do parts[k] = nil end
            for key, m in pairs(S.members) do
              local mq = m.quests and m.quests[e.id]
              if mq and mq.prog then parts[#parts + 1] = (m.name or key) .. " " .. mq.prog end
            end
            if #parts > 0 then table.sort(parts); line.party = table.concat(parts, ", ") end
          end
          out[n] = line
        end
      end
    end
  end
  return out
end

-- the hook: data is the tooltip's TooltipData (type, guid, lines)
function Tips.Add(tip, data)
  if not on() or type(data) ~= "table" then return end
  local guid = plain(data.guid)
  if data.guid ~= nil and guid == nil then return end -- (a secret guid: the unit is hidden from addons)
  local lines = plain(data.lines)
  local first = type(lines) == "table" and plain(lines[1]) or nil
  local name = type(first) == "table" and plain(first.leftText) or nil
  if type(name) ~= "string" then return end
  for _, l in ipairs(Tips.Lines(name)) do
    tip:AddLine(l.text, 1, 0.82, 0.3, true)
    if l.party then tip:AddLine(l.party, 0.6, 0.6, 0.6, true) end
  end
end

-- the game's hooks for units and objects (TooltipInfoSharedDocumentation.lua: Unit = 2, Object = 4), once
function Tips:Init()
  if self.ready then return end
  local TDP, E = TooltipDataProcessor, Enum and Enum.TooltipDataType
  if not (TDP and TDP.AddTooltipPostCall and E) then return end
  local fn = QB.Safe(function(tip, data) Tips.Add(tip, data) end, "tooltip progress")
  if E.Unit then pcall(TDP.AddTooltipPostCall, E.Unit, fn) end
  if E.Object then pcall(TDP.AddTooltipPostCall, E.Object, fn) end
  self.ready = true
end
