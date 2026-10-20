-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cute_Quest: QuestBank's engine as Cute modules. This file runs first. The engine files after it are QuestBank's own,
-- copied by tools/cute/build.py (never edited here); each starts with `if QB.dormant then return end`.
-- With the addon QuestBank loaded, this copy sleeps: Bridge.lua and the pages talk to QuestBankAPI, QuestBank's own
-- table, and nothing of the engine runs twice. Without it, this copy is the engine: its saved variables are
-- CuteQuestDB, which the copied Core.lua reads and writes under the engine's name, QuestBankDB (one table, aliased
-- here when the saved variables arrive).
local ADDON, QB = ...
local A = type(C_AddOns) == "table" and C_AddOns or nil
local function loaded(name)
  if not (A and type(A.IsAddOnLoaded) == "function") then return false end
  local ok, v = pcall(A.IsAddOnLoaded, name)
  return ok and v == true
end
QB.dormant = loaded("QuestBank")
QB.host = "Cute"
QB.ADDON = ADDON
QB.ART = "Interface\\AddOns\\" .. ADDON .. "\\art\\"
-- the modules' switches by module id (PageQuests, PageMap and PageCamp set theirs), for the Bridge to run again once
-- the saved variables are in: Cute applies each module as its files register it, before ADDON_LOADED, when the
-- engine's table is not the saved one yet (QB.ready, below), so a switch run then does nothing and waits
QB.Toggles = {}
if QB.dormant then return end
-- the saved variables, once the game hands them over (ADDON_LOADED for this addon; this frame is made before the
-- engine's, so it hears first). An error recorded while the files loaded made a QuestBankDB of its own: its errors
-- are kept
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
  if name ~= ADDON then return end
  self:UnregisterEvent("ADDON_LOADED")
  local early = QuestBankDB
  if type(CuteQuestDB) ~= "table" then CuteQuestDB = {} end
  if type(early) == "table" and early ~= CuteQuestDB and type(early.errors) == "table" then
    CuteQuestDB.errors = CuteQuestDB.errors or {}
    for _, e in ipairs(early.errors) do table.insert(CuteQuestDB.errors, e) end
  end
  QuestBankDB = CuteQuestDB
  -- (an engine read before this ran on a table since thrown away: its once-a-session prune runs again, on this one)
  QB.pruned = nil
  QB.ready = true
end)
