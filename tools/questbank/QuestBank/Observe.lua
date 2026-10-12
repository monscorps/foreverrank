-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's event probe, the observer's first step. Forever's client is a Midnight client: the combat log is closed
-- to addons and many values arrive as secret values. Before QuestBank records what creatures cast, when, and what
-- vendors sell, it has to know which events hand it readable values on this client. So this counts, per event,
-- how often every read was plain (ok), how often one was secret (sec), how often one was nil (nl), and keeps one
-- sample of the field names with the kind of value each held: never the value, never a name.
--   QuestBankDB.diag.ev[event] = { n, ok, sec, nl, s = { field = "string"|"number"|"boolean"|"table"|"secret"|"nil" } }
-- Only on the Forever client, under the same Settings box as the item notes (unticking clears it). Only reads:
-- nothing is cast, moved or targeted, so the game has nothing of QuestBank's to block. /qb events lists the counts.
local _, QB = ...
local Observe = {}
QB.Observe = Observe

local MAX_KEYS = 60 -- events kept; a new one past that is not counted
Observe.MAX_KEYS = MAX_KEYS
Observe.NIL = {}    -- a handler's way to say "this read was nil" (a nil in a table has no key)

local plain = QB.Plain

-- counting: the Forever client, with the Settings box ticked (the same box as the item, spell and loot notes)
function Observe.On() return (QB.Game and QB.Game.On()) and true or false end

local function kindOf(v)
  if v == Observe.NIL then return "nil" end
  if issecretvalue and issecretvalue(v) then return "secret" end
  if v == nil then return "nil" end
  return type(v)
end

-- one event's counts; nil when the table is full and the event is new
local function slot(event)
  if not QuestBankDB then return end
  QuestBankDB.diag = QuestBankDB.diag or {}
  local all = QuestBankDB.diag.ev
  if type(all) ~= "table" then
    all = {}
    QuestBankDB.diag.ev = all
  end
  local r = all[event]
  if type(r) ~= "table" then
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    if n >= MAX_KEYS then return end
    r = { n = 0, ok = 0, sec = 0, nl = 0, s = {} }
    all[event] = r
  end
  return r
end

-- count one event's reads. reads = { field = value }: what the handler read, as the client gave it (Observe.NIL
-- for a nil). The first call's field kinds are the sample; values are never kept
function Observe.Note(event, reads)
  local r = slot(event)
  if not r then return end
  r.n = r.n + 1
  local secret, missing = false, false
  local sample = next(r.s) == nil
  for field, v in pairs(reads) do
    local k = kindOf(v)
    if k == "secret" then secret = true elseif k == "nil" then missing = true end
    if sample then r.s[field] = k end
  end
  if secret then r.sec = r.sec + 1 end
  if missing then r.nl = r.nl + 1 end
  if not secret and not missing then r.ok = r.ok + 1 end
end

function Observe.Clear()
  if QuestBankDB and type(QuestBankDB.diag) == "table" then QuestBankDB.diag.ev = nil end
end

-- /qb events: every event counted, with its sample's fields and kinds
function Observe.Report(say)
  local all = QuestBankDB and type(QuestBankDB.diag) == "table" and QuestBankDB.diag.ev
  if type(all) ~= "table" or next(all) == nil then say("Event probe: nothing counted yet."); return end
  local keys = {}
  for k in pairs(all) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local r = all[k]
    local fields = {}
    for f, kind in pairs(r.s) do fields[#fields + 1] = f .. "=" .. kind end
    table.sort(fields)
    say(string.format("%s: %d seen, %d ok, %d secret, %d missing (%s)", k, r.n, r.ok, r.sec, r.nl, table.concat(fields, " ")))
  end
end

function Observe.OnEvent(event, ...)
  Observe.Note(event, { nargs = select("#", ...) })
end

function Observe:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  if not (QB.Game and QB.Game.Forever()) then return end
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) if Observe.On() then Observe.OnEvent(event, ...) end end, "event probe"))
end
