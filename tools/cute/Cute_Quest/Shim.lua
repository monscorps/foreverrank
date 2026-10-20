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
end)
