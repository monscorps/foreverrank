-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's own chat links, and what an item link says about quests. A quest QuestBank names in your chat is a link:
--   |cffc6af8d|Haddon:QuestBank:quest:<id>|h[Name]|h|r
-- Click: the quest's menu (waypoint, pick-up list, link in chat), the same one the window shows on right-click.
-- Shift-click with a chat box open: the game's own quest link goes into the box. These links are yours alone: the
-- client never sends addon links to other players, so posts to party and guild keep the game's quest links.
-- The click reaches QuestBank through the client's SetItemRef event (EventRegistry on the Forever client; on Classic
-- Era the global SetItemRef is hooked after the fact, which is the sanctioned way: nothing of the game's is replaced).
-- Item tooltips: an item a quest gives (the catalog's reward lists) gains "Reward of: Quest (level, where)" lines,
-- through the one tooltip post-call Game.lua already holds.
local _, QB = ...
if QB.dormant then return end
local Link = {}
QB.Link = Link

local COLOR = "c6af8d"
local MAX_QUESTS_ON_TIP = 3

function Link.Format(q)
  if not (q and q.id) then return q and q.name or "" end
  return string.format("|cff%s|Haddon:QuestBank:quest:%d|h[%s]|h|r", COLOR, q.id, q.name or ("Quest " .. q.id))
end

-- the quest id in one of these links, else nil
function Link.Parse(link)
  link = QB.Plain(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("^addon:QuestBank:quest:(%d+)$")
  return id and tonumber(id) or nil
end

function Link.Click(link, text, button)
  local id = Link.Parse(link)
  if not id then return false end
  local q = QB.Quest.Get(id)
  if not q then QB:Print("QuestBank doesn't know quest " .. id .. " any more."); return true end
  if IsShiftKeyDown and IsShiftKeyDown() and QB.UI and QB.UI.LinkQuest and QB.UI.LinkQuest(q) then return true end
  if QB.UI and QB.UI.QuestMenu then QB.UI.QuestMenu(q) end
  return true
end

-- item id -> the quests that give it, built once from the catalog's reward lists (and again after Link.Reset)
local byItem
local function rewardIndex()
  if byItem then return byItem end
  byItem = {}
  local R = QB.Data.RITEMS or {}
  for qid, lists in pairs(R) do
    for _, key in ipairs({ "c", "r", "u" }) do
      for _, iid in ipairs(lists[key] or {}) do
        local t = byItem[iid]
        if not t then t = {}; byItem[iid] = t end
        t[#t + 1] = qid
      end
    end
  end
  for _, t in pairs(byItem) do table.sort(t) end
  return byItem
end
Link.RewardIndex = rewardIndex
-- the reward lists changed (the quest survey filled some in): the index is built again when next needed
function Link.Reset() byItem = nil end

-- the quests that give this item, as the catalog knows them (for you first), at most MAX_QUESTS_ON_TIP
function Link.QuestsFor(itemId)
  local ids = rewardIndex()[itemId]
  if not ids then return {} end
  local out, Q = {}, QB.Quest
  for _, qid in ipairs(ids) do
    local q = Q.Get(qid)
    if q then out[#out + 1] = q end
  end
  table.sort(out, function(a, b)
    local fa, fb = Q.ForMe(a) and 1 or 0, Q.ForMe(b) and 1 or 0
    if fa ~= fb then return fa > fb end
    return (a.lvl or 0) < (b.lvl or 0)
  end)
  return out
end

-- lines on an item tooltip: called from Game.lua's post-call with the tooltip and the data it was given
function Link.ItemTip(tip, data)
  if not (tip and tip.AddLine and type(data) == "table") then return end
  local id = QB.Plain(data.id)
  if type(id) ~= "number" then return end
  local qs = Link.QuestsFor(id)
  if #qs == 0 then return end
  for i = 1, math.min(MAX_QUESTS_ON_TIP, #qs) do
    local q = qs[i]
    local where = q.cat and q.cat.name
    tip:AddLine(string.format("%s %s (L%d%s)", i == 1 and "Reward of:" or "and", q.name, q.lvl or 0, where and (", " .. where) or ""),
                0.78, 0.69, 0.55)
  end
  if #qs > MAX_QUESTS_ON_TIP then tip:AddLine(string.format("and %d more quests", #qs - MAX_QUESTS_ON_TIP), 0.6, 0.6, 0.6) end
end

function Link:Init()
  if self.ready then return end
  self.ready = true
  local handler = QB.Safe(function(link, text, button) Link.Click(link, text, button) end, "chat link")
  if EventRegistry and EventRegistry.RegisterCallback then
    -- the Forever client: the "addon" link type ends in this event (ItemRefHandlersShared.lua)
    EventRegistry:RegisterCallback("SetItemRef", function(_, link, text, button) handler(link, text, button) end, Link)
  elseif hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link, text, button) handler(link, text, button) end)
  end
end
