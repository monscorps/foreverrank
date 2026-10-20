-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's quest survey. The client knows some 6,600 quests by id; QuestBank's catalog has about 3,800, and for a
-- third of those no list has the rewards. So, out of combat and outside instances, QuestBank asks the game about the
-- rest, one quest every half second or so (C_QuestLog.RequestLoadQuestByID; the server answers with
-- QUEST_DATA_LOAD_RESULT), and notes what the game tells it: the title, the reward items (to choose from and always
-- given), the XP and money at your level and the quest's level. The ids are D.SURVEY (gen_data.py: the client's quest
-- table less what the catalog and the lists have, and the catalog's quests whose rewards no Forever source knows: none
-- known, or only the Classic database's).
-- What it learns is used at once: the finders (Best gear, Trinkets, Recipes), the quest and item tooltips and
-- Available. A quest no list has shows in the finders as "Seen in game", with no giver, place or side.
-- Kept once per account in QuestBankDB.disc, so an upload carries it into the next release for everyone:
--   survey[questID] = { t = title, c = { items to choose from }, r = { items always given }, xp = XP at your level
--     then, pl = that level, money = copper (when it pays any), lvl = the quest's level, b = the client build }: eight
--     fields at most, so 6,000 of them stay small. c and r are missing when the game didn't send the rewards whole,
--     empty when the quest gives no items. A quest the client has already is read as it is, without a question
--   surveyNo[questID] = tries that failed on this build (the game said no, never answered, or never sent the rewards
--     whole); after three the quest rests until the next build
--   surveyB = that build: a new build asks every quest again
-- QuestBankDB.diag.survey counts this build's questions (asked, loaded, with rewards, failed): /qb survey.
-- Settings: "Learn quests from the game", on by default. No names: quest ids, titles, item ids and numbers.
local _, QB = ...
if QB.dormant then return end
local Survey = {}
QB.Survey = Survey

local PACE = 0.5      -- seconds between two questions: two a second
local SLOWEST = 4     -- seconds between questions at most, while the game is slow to answer
local FLIGHT = 3      -- questions waiting for an answer at once, at most
local TIMEOUT = 20    -- seconds without an answer: that try failed
local TRIES = 3       -- tries a quest gets on a build: the first and two more
local READS = 4       -- reads of a loaded quest whose rewards haven't come whole yet
local REREAD = 2      -- seconds between those reads
local START = 30      -- seconds after login or a reload before the first question
local SETTLE = 10     -- seconds after a loading screen
local COMBAT_WAIT = 5 -- seconds between looks while you fight (the fight's end starts it sooner)
local REFRESH = 5     -- seconds at least between two redraws of the window for what the survey learned
local FLAG = 65536    -- D.Q's flag of a quest the survey alone knows: no giver, place or side
local NEW_ITEMS = 200000 -- Forever's new items (and Season of Discovery's) have ids from here
Survey.PACE, Survey.FLIGHT, Survey.TIMEOUT, Survey.TRIES, Survey.START, Survey.SETTLE, Survey.FLAG =
  PACE, FLIGHT, TIMEOUT, TRIES, START, SETTLE, FLAG

local plain = QB.Plain
local D = QB.Data
local floor = math.floor

local function now() return GetTime and GetTime() or 0 end

----------------------------------------------------------------------------
-- the ids: D.SURVEY's runs, each ascending, as the steps between ids in base 32 over D.ALPHA (a digit from its second
-- half when more digits of the same step follow)
----------------------------------------------------------------------------
local DIGIT = {}
for i = 1, #(D.ALPHA or "") do DIGIT[D.ALPHA:byte(i)] = i - 1 end

function Survey.Decode(s)
  local out, prev, acc = {}, 0, 0
  for i = 1, #(s or "") do
    local d = DIGIT[s:byte(i)]
    if not d then break end
    if d >= 32 then
      acc = acc * 32 + d - 32
    else
      prev = prev + acc * 32 + d
      out[#out + 1] = prev
      acc = 0
    end
  end
  return out
end

function Survey.Encode(ids)
  local out, prev = {}, 0
  for _, id in ipairs(ids) do
    local step, digits = id - prev, {}
    repeat
      table.insert(digits, 1, step % 32)
      step = floor(step / 32)
    until step == 0
    for k, d in ipairs(digits) do
      local i = (k < #digits and 32 or 0) + d + 1
      out[#out + 1] = D.ALPHA:sub(i, i)
    end
    prev = id
  end
  return table.concat(out)
end

----------------------------------------------------------------------------
-- where it is kept
----------------------------------------------------------------------------
local function build()
  if not GetBuildInfo then return 0 end
  local ok, _, b = pcall(GetBuildInfo)
  return ok and tonumber(plain(b)) or 0
end

local function db()
  local d = QB.Discover.DB()
  if type(d.survey) ~= "table" then d.survey = {} end
  local b = build()
  if d.surveyB ~= b or type(d.surveyNo) ~= "table" then d.surveyNo, d.surveyB = {}, b end
  return d
end
Survey.DB = db

-- this build's counts, for /qb survey and the uploads
local function diag()
  QuestBankDB = QuestBankDB or {}
  if type(QuestBankDB.diag) ~= "table" then QuestBankDB.diag = {} end
  local s = QuestBankDB.diag.survey
  local b = build()
  if type(s) ~= "table" or s.b ~= b then
    s = { b = b, asked = 0, loaded = 0, rewards = 0, failed = 0 }
    QuestBankDB.diag.survey = s
  end
  return s
end
Survey.Diag = diag

-- the client has what the survey needs (the Forever client does; Classic Era has no use for Forever's ids)
local function able()
  local L = C_QuestLog
  return QB.Game ~= nil and QB.Game.Forever() and type(L) == "table" and type(L.RequestLoadQuestByID) == "function"
    and type(L.GetTitleForQuestID) == "function"
end
Survey.Able = able

-- asking: on that client, with the Settings box ticked (it is by default)
local function on()
  if not able() then return false end
  local s = QuestBankDB and QuestBankDB.settings
  return not (type(s) == "table" and s.survey == false)
end
Survey.On = on

local function inCombat()
  if QB.Pins and QB.Pins.InCombat then return QB.Pins.InCombat() end
  return (InCombatLockdown and InCombatLockdown()) and true or false
end

-- in a dungeon, raid, battleground or arena (and when the client hides which, as if inside)
local function inInstance()
  if not IsInInstance then return false end
  local ok, inside = pcall(IsInInstance)
  if not ok then return false end
  if issecretvalue and issecretvalue(inside) then return true end
  return inside == true or inside == 1
end

----------------------------------------------------------------------------
-- what the survey learned, in the catalog's own tables: a catalog quest with no rewards known takes the game's lists;
-- a quest no list has gets a row of its own (flag FLAG, category 0: "Seen in game") so the finders can show it.
-- Nothing a list or your own quest window knows is replaced; the Classic database's rewards (D.RCLASSIC: no Forever
-- source had them) are, as the game's word on Forever beats Classic's
----------------------------------------------------------------------------
local before = {}  -- [id] = the catalog's own entries, kept to put back
local made = {}    -- [id] = true: a row the survey made

local function keep(id)
  if before[id] then return end
  before[id] = { D.RITEMS[id], D.RUNK[id], D.REWARD[id], D.Q[id], D.QN[id], D.RCLASSIC and D.RCLASSIC[id] }
end

local function forget(id)
  if QB.Quest and QB.Quest.Forget then QB.Quest.Forget(id) end
end

-- the catalog's entries back, as they were before the survey changed them
local function restore(id)
  local b = before[id]
  if not b then return end
  D.RITEMS[id], D.RUNK[id], D.REWARD[id], D.Q[id], D.QN[id] = b[1], b[2], b[3], b[4], b[5]
  if D.RCLASSIC then D.RCLASSIC[id] = b[6] end
  D.RSURV[id], made[id], before[id] = nil, nil, nil
  forget(id)
end

local function add(k, bit) if floor(k / bit) % 2 == 0 then return k + bit end return k end

-- what the finder needs of an item, without the client's item cache: its slot, class and subclass
local function instant(id)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if type(f) ~= "function" then return nil end
  local ok, _, _, _, loc, _, class, sub = pcall(f, id)
  if not ok then return nil end
  return plain(loc), plain(class), plain(sub)
end

-- an item's level, once the client has the item (nil before: never asked here, where the item cache's own lookups would
-- ask the server for every item at once; the items wait in a queue that asks for one each half second)
local function itemLevel(id)
  if C_Item and type(C_Item.IsItemDataCachedByID) == "function" then
    local ok, cached = pcall(C_Item.IsItemDataCachedByID, id)
    if ok and plain(cached) == false then return nil end
  end
  if C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
    local ok, l = pcall(C_Item.GetDetailedItemLevelInfo, id)
    l = ok and plain(l) or nil
    if type(l) == "number" and l > 0 then return l end
  end
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if type(info) == "function" then
    local ok, name, _, _, l = pcall(info, id)
    if ok and plain(name) ~= nil then
      l = plain(l)
      if type(l) == "number" and l > 0 then return l end
    end
  end
  return nil
end

-- the finders' per-item judgement (UI.ItemFacts) reads it too, for an item no list described
Survey.ItemLevel = itemLevel

local ARMOR = { [1] = 64, [2] = 128, [3] = 256, [4] = 512 } -- cloth, leather, mail, plate offered
local NOT_WORN = { [""] = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
                   INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true }
local waitLevel = {} -- [item] = { [quest] = true }: quests whose finder facts wait for the item's level
local asked = {}     -- [item] = true: in the queue below, or asked of the server, this session
local itemQueue = {} -- items whose data the server is asked for, one each time the survey asks a quest

-- the finder's facts of a quest's reward items, as gen_data.py works out D.REWARD: { best item level among the gear,
-- kinds (1 gear, 2 trinket, 4 ring or neck, 8 recipe, 16 bag, 32 consumable, 64-512 cloth to plate), the best piece }
local function rate(id)
  local R = D.RITEMS[id]
  if not R then D.REWARD[id] = nil; return end
  local best, kinds, bestId = 0, 0, 0
  for _, key in ipairs({ "r", "c", "u" }) do
    for _, item in ipairs(R[key] or {}) do
      local loc, class, sub = instant(item)
      if class == 2 or (class == 4 and type(loc) == "string" and not NOT_WORN[loc]) then
        kinds = add(kinds, 1)
        if class == 4 and ARMOR[sub] then kinds = add(kinds, ARMOR[sub]) end
        if loc == "INVTYPE_TRINKET" then kinds = add(kinds, 2) end
        if loc == "INVTYPE_FINGER" or loc == "INVTYPE_NECK" then kinds = add(kinds, 4) end
        local l = itemLevel(item)
        if l then
          if l > best then best, bestId = l, item end
        else
          -- asked of the server in turn: ITEM_DATA_LOAD_RESULT brings it, and the quest is rated again
          waitLevel[item] = waitLevel[item] or {}
          waitLevel[item][id] = true
          if not asked[item] then
            asked[item] = true
            itemQueue[#itemQueue + 1] = item
          end
        end
      elseif class == 9 then kinds = add(kinds, 8)
      elseif class == 1 then kinds = add(kinds, 16)
      elseif class == 0 then kinds = add(kinds, 32) end
    end
  end
  D.REWARD[id] = kinds > 0 and { best, kinds, bestId } or nil
end
Survey.Rate = rate

-- placeholders the game never offers (gen_data.py's JUNK)
local JUNK = { "<", "[", "UNUSED", "NYI", "REUSE", "test quest", "Test Quest" }
local function junk(title)
  if type(title) ~= "string" or title == "" then return true end
  for _, w in ipairs(JUNK) do if title:find(w, 1, true) then return true end end
  return false
end

-- a quest the survey alone knows, as a catalog row: its level, XP at full value (0: not known), no required level,
-- side, giver, ender or place
local function place(id, lvl, xp, title)
  keep(id)
  xp = tonumber(xp) or 0
  D.Q[id] = { lvl, 0, 0, xp, 1, 0, 0, 0, 0, FLAG + (xp > 0 and 0 or 64) }
  D.QN[id] = title
  made[id] = true
  forget(id)
end

local function ids(v)
  if type(v) ~= "table" then return nil end
  local out = {}
  for _, x in ipairs(v) do
    if type(x) ~= "number" or x <= 0 then return nil end
    out[#out + 1] = x
  end
  return out
end

-- one quest's reading into the catalog's tables. True when anything the finders or tooltips show changed
local function use(id, rec)
  if type(id) ~= "number" or type(rec) ~= "table" then return false end
  local c, r = ids(rec.c), ids(rec.r)
  if not (c and r) then return false end
  if D.Q[id] and not made[id] then
    -- the catalog's quest: the game fills in what no list knew, splits a loot page's list, or replaces the Classic
    -- database's
    local have = D.RITEMS[id]
    local classic = D.RCLASSIC and D.RCLASSIC[id]
    if have and not D.RSURV[id] and not classic and (have.c or have.r) then return false end
    keep(id)
    D.RITEMS[id] = (#c + #r > 0) and { c = #c > 0 and c or nil, r = #r > 0 and r or nil } or nil
    D.RUNK[id] = nil
    if classic then D.RCLASSIC[id] = nil end
    D.RSURV[id] = true
    rate(id)
    return true
  end
  -- no list has it: with items, a level and a real title it goes to the finders, seen in game
  local lvl = tonumber(rec.lvl)
  if #c + #r == 0 or not (lvl and lvl >= 1 and lvl <= (QB.MAXLEVEL or 60)) or junk(rec.t) then return false end
  local xp = 0
  if type(rec.xp) == "number" and rec.xp > 0 and type(rec.pl) == "number" and rec.pl <= lvl + 5 then xp = QB.Unbuff(rec.xp) end
  place(id, lvl, xp, rec.t)
  D.RITEMS[id] = { c = #c > 0 and c or nil, r = #r > 0 and r or nil }
  D.RUNK[id] = nil
  D.RSURV[id] = true
  rate(id)
  return true
end
Survey.Use = use

-- something the finders, Available or the tooltips show changed: the window redraws a moment later (once for many)
local redraw = false
local function changed()
  QB.surveyVer = (QB.surveyVer or 0) + 1
  if QB.Link and QB.Link.Reset then QB.Link.Reset() end
  if redraw then return end
  redraw = true
  C_Timer.After(REFRESH, QB.Safe(function()
    redraw = false
    if QB.UI and QB.UI.frame and QB.UI.frame:IsShown() then QB.Try("window", QB.UI.Refresh, QB.UI) end
  end, "quest survey"))
end

-- at load: the release's quests from players' surveys, then what this account's game told
function Survey.Load()
  D.RSURV = D.RSURV or {}
  D.CAT[0] = D.CAT[0] or { key = "seen", name = "Seen in game", where = "Place not known yet", icon = D.TEX and D.TEX.questGeneric }
  for id, s in pairs(D.SURVEYED or {}) do
    if not D.Q[id] and type(s) == "table" then
      place(id, s[1], s[2], s[3])
      if D.RITEMS[id] and not D.REWARD[id] then rate(id) end
      before[id] = nil -- the release's row is what a reading dropped later goes back to
    end
  end
  for id, rec in pairs(db().survey) do use(id, rec) end
  QB.surveyVer = (QB.surveyVer or 0) + 1
  if QB.Link and QB.Link.Reset then QB.Link.Reset() end
end

----------------------------------------------------------------------------
-- reading what the game sent about a quest
----------------------------------------------------------------------------
local function num(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  v = ok and plain(v) or nil
  return type(v) == "number" and v or nil
end

-- the item in one reward slot ("choice" or "reward"): its id from the slot's info, else from its link
local function slot(kind, i, id)
  local get = kind == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
  if type(get) == "function" then
    local ok, _, _, _, _, _, item = pcall(get, i, id)
    item = ok and plain(item) or nil
    if type(item) == "number" and item > 0 then return item end
  end
  if type(GetQuestLogItemLink) == "function" then
    local ok, link = pcall(GetQuestLogItemLink, kind, i, id)
    link = ok and plain(link) or nil
    local item = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
    if item and item > 0 then return item end
  end
  return nil
end

-- the reward lists, each whole, or nil when a slot or a count isn't readable yet; and whether the client says the
-- reward data is all there (true too when it has no way to say)
local function rewards(id)
  local have = true
  if type(HaveQuestRewardData) == "function" then
    local ok, h = pcall(HaveQuestRewardData, id)
    have = ok and plain(h) == true
  end
  local nc, nr = num(GetNumQuestLogChoices, id), num(GetNumQuestLogRewards, id)
  if not (nc and nr) then return nil, nil, have end
  local c, r, seen = {}, {}, {}
  for i = 1, nc do
    local item = slot("choice", i, id)
    if not item then return nil, nil, have end
    if not seen[item] then seen[item] = true; c[#c + 1] = item end
  end
  for i = 1, nr do
    local item = slot("reward", i, id)
    if not item then return nil, nil, have end
    if not seen[item] then seen[item] = true; r[#r + 1] = item end
  end
  return c, r, have
end

----------------------------------------------------------------------------
-- the check: D.SURVEY's fourth run is three Forever quests whose items Wowhead lists, asked first on each build. Each
-- answer is "ok" (items, one of them on the quest's list), "none" (no items) or "wrong" (items, none of them on its
-- list: the game told another quest's). The game's word that a quest gives no items is taken only once more of them
-- came back ok than not (and one did). Until then an empty answer is a failed try, asked again later; once the check
-- has failed, it is no answer (the quest rests until the next build)
----------------------------------------------------------------------------
local CHECK_RUN = 4
local checking = {} -- [id] = true: a quest of the check

local function checkOf(d)
  local k = d.surveyCheck
  if type(k) ~= "table" or k.b ~= d.surveyB or type(k.ids) ~= "table" then
    k = { b = d.surveyB, ids = {} }
    d.surveyCheck = k
  end
  local ok, bad = 0, 0
  for _, v in pairs(k.ids) do if v == "ok" then ok = ok + 1 else bad = bad + 1 end end
  return k, ok, bad
end

-- "trusted", "failed", or nil while the check is still going
local function checked(d)
  local _, ok, bad = checkOf(d)
  if ok >= 1 and ok > bad then return "trusted" end
  if bad >= 2 or (bad >= 1 and ok + bad >= 3) then return "failed" end
  return nil
end
Survey.Checked = function() return checked(db()) end

local function listKey(c, r) return table.concat(c, ",") .. "|" .. table.concat(r, ",") end

-- one of these items is on the quest's list in the catalog (a check quest's: Wowhead's)
local function own(id, c, r)
  local R, mine = D.RITEMS[id], {}
  for _, key in ipairs({ "c", "r", "u" }) do for _, item in ipairs(R and R[key] or {}) do mine[item] = true end end
  for _, list in ipairs({ c, r }) do for _, item in ipairs(list) do if mine[item] then return true end end end
  return false
end

-- a check quest read again now, as the guards below compare it: its reward list (and whether that is its own), its XP
local function checkList(id)
  local c, r = rewards(id)
  if c and #c + #r > 0 then return listKey(c, r), own(id, c, r) end
end
local function checkXP(id)
  local x = num(GetQuestLogRewardXP, id)
  if x and x > 0 then return x, false end
end

-- a client answering one quest's numbers for every id (some answer with the selected quest's) would show it as a run:
-- four quests of different levels paying the same XP in a row (at levels where they pay in full), or six in a row with
-- the same reward items. Quests in a row can pay alike too (a series of turn-ins, a shelf of library books), so the
-- check's quests decide: read again now, one that tells its own apart from the run's means the game answers by id and
-- the readings stand; one that gives the run's (its own being something else) means it doesn't. When none can be read
-- now, the check's answers on this build decide: a wrong one, and the run is dropped. A dropped reading gives back what
-- this account read before (an earlier build's), and the rest of the session leaves that number (XP or items) out
local recent = {}
local xpBad, rwBad = false, false

local function wrongRun(value, readOf)
  for id in pairs(checking) do
    local v, mine = readOf(id)
    if v ~= nil then
      if v ~= value then return false end
      if not mine then return true end
    end
  end
  local k = checkOf(db())
  for _, v in pairs(k.ids) do if v == "wrong" then return true end end
  return false
end

-- before a reading is kept (old: the account's reading of the quest until now)
local function guard(id, rec, old)
  local key = rec.c and listKey(rec.c, rec.r) or nil
  local full = rec.xp and rec.pl and rec.lvl and rec.pl <= rec.lvl + 5
  recent[#recent + 1] = { id = id, xp = full and rec.xp or nil, lvl = rec.lvl, rw = (key ~= "|") and key or nil, old = old }
  if #recent > 6 then table.remove(recent, 1) end
  local d = db()
  local x = recent[#recent].xp
  if not xpBad and #recent >= 4 and x then
    local same, levels, nl = 0, {}, 0
    for k = #recent - 3, #recent do
      local e = recent[k]
      if e.xp == x then
        same = same + 1
        if e.lvl and not levels[e.lvl] then levels[e.lvl] = true; nl = nl + 1 end
      end
    end
    if same == 4 and nl >= 2 and wrongRun(x, checkXP) then
      xpBad = true
      for k = #recent - 3, #recent - 1 do
        local e = recent[k]
        local s, o = d.survey[e.id], type(e.old) == "table" and e.old or {}
        if type(s) == "table" then s.xp, s.pl = o.xp, o.pl end
      end
    end
  end
  local w = recent[#recent].rw
  if not rwBad and #recent >= 6 and w then
    local same = 0
    for k = #recent - 5, #recent do if recent[k].rw == w then same = same + 1 end end
    if same == 6 and wrongRun(w, checkList) then
      rwBad = true
      for k = #recent - 5, #recent - 1 do
        local e = recent[k]
        if type(e.old) == "table" and type(e.old.c) == "table" then
          d.survey[e.id] = e.old -- the earlier reading stands
        elseif type(d.survey[e.id]) == "table" then
          d.survey[e.id].c, d.survey[e.id].r = nil, nil
        end
        restore(e.id)
        use(e.id, d.survey[e.id])
      end
      restore(id)
      if type(old) == "table" then use(id, old) end
      changed()
    end
  end
  local o = type(old) == "table" and old or {}
  if xpBad then rec.xp, rec.pl = o.xp, o.pl end
  if rwBad then rec.c, rec.r = nil, nil end
end

local reads = {} -- [id] = reads of a loaded quest so far
local read, fail -- (fail: below, with the asking)

function read(id)
  -- in a fight or an instance it waits: a read can ask the server for the reward data
  if inCombat() or inInstance() then
    C_Timer.After(COMBAT_WAIT, QB.Safe(function() read(id) end, "quest survey"))
    return
  end
  local n = (reads[id] or 0) + 1
  reads[id] = n
  local L = C_QuestLog
  local okT, title = pcall(L.GetTitleForQuestID, id)
  title = okT and plain(title) or nil
  if type(title) ~= "string" or title == "" then title = nil end
  local c, r, have = rewards(id)
  -- not all there yet: read again shortly. Lists with items stand on the last read; an empty pair only when the
  -- client says the rewards are all there
  local whole = c ~= nil and (have or (#c + #r > 0 and n >= READS))
  if (not whole or not title) and n < READS then
    C_Timer.After(REREAD, QB.Safe(function() read(id) end, "quest survey"))
    return
  end
  reads[id] = nil
  -- (rewards that never came whole: the try failed, and the quest is asked again later, three times at most)
  local lvl = L.GetQuestDifficultyLevel and num(L.GetQuestDifficultyLevel, id) or nil
  local xp = num(GetQuestLogRewardXP, id)
  local money = num(GetQuestLogRewardMoney, id)
  local pl = UnitLevel and num(UnitLevel, "player") or nil
  local rec = { t = title, lvl = (lvl and lvl > 0) and lvl or nil, xp = (xp and xp > 0) and xp or nil, money = (money and money > 0) and money or nil,
                b = build() }
  if rec.xp then rec.pl = pl end
  local d = db()
  local rest = false
  if whole and checking[id] then
    local k = checkOf(d)
    if k.ids[id] == nil then k.ids[id] = (#c + #r == 0) and "none" or (own(id, c, r) and "ok" or "wrong") end
  elseif whole and #c + #r == 0 and checked(d) ~= "trusted" then
    -- no items, the game says; not taken before the check (and never when it failed)
    whole, rest = false, checked(d) == "failed"
  end
  if whole then rec.c, rec.r = c, r end
  local old = d.survey[id]
  guard(id, rec, old)
  -- a reading without the rewards never replaces one with them (an earlier build's)
  if rec.c or not (type(old) == "table" and type(old.c) == "table") then d.survey[id] = rec end
  if rest then
    d.surveyNo[id] = TRIES
    local s = diag()
    s.failed = s.failed + 1
  elseif not whole then
    fail(id)
  end
  local s = diag()
  if rec.c and #rec.c + #rec.r > 0 then
    s.rewards = s.rewards + 1
    -- and the tooltips of Forever's new items, which no datamine has, for foreverrank.com's item pages (Game.lua,
    -- while its box is ticked; Classic's items are left to what you see, so they don't crowd its notes out)
    if QB.Game and QB.Game.Want then
      for _, list in ipairs({ rec.c, rec.r }) do
        for _, item in ipairs(list) do if item >= NEW_ITEMS then QB.Game.Want(item) end end
      end
    end
  end
  if use(id, rec) then changed() end
end

----------------------------------------------------------------------------
-- asking: one quest at a time, PACE apart, at most FLIGHT waiting for an answer; never in a fight, inside an instance,
-- or in the first seconds after login or a loading screen. One timer at a time: a later schedule supersedes the one
-- before (gen)
----------------------------------------------------------------------------
local order, pos       -- this session's ids, in order (retries go to the end), and the next to ask
local orderB           -- the build the order was made for
local pending = {}     -- [id] = when it was asked
local inflight = 0
local pace = PACE
local holdUntil = 0
local gen = 0
Survey.state = "idle"  -- what it does now, for /qb survey: waiting, fight, instance, asking, done, off

-- done on this build: read with its rewards whole, or three tries failed
local function finished(d, id)
  local rec = d.survey[id]
  if type(rec) == "table" and rec.b == d.surveyB and type(rec.c) == "table" then return true end
  return (d.surveyNo[id] or 0) >= TRIES
end

-- the order: the new Forever range, then the catalog's quests nearest your level, then the rest; what this build
-- already answered (or didn't, three times) is left out
local function makeOrder()
  local d = db()
  local out = {}
  local lvl = UnitLevel and num(UnitLevel, "player") or 0
  local runs = type(D.SURVEY) == "table" and D.SURVEY or {}
  checking = {}
  for _, id in ipairs(Survey.Decode(runs[CHECK_RUN])) do
    checking[id] = true
    if not finished(d, id) then out[#out + 1] = id end
  end
  for run, s in ipairs(runs) do
    if run ~= CHECK_RUN then
      local list = Survey.Decode(s)
      if run == 2 and lvl > 0 then
        local far = {}
        for _, id in ipairs(list) do local row = D.Q[id]; far[id] = row and math.abs(row[1] - lvl) or 99 end
        table.sort(list, function(a, b) if far[a] ~= far[b] then return far[a] < far[b] end return a < b end)
      end
      for _, id in ipairs(list) do if not finished(d, id) and not checking[id] then out[#out + 1] = id end end
    end
  end
  return out
end

local function nextId()
  local d = db()
  while order and pos <= #order do
    local id = order[pos]
    pos = pos + 1
    if not pending[id] and not reads[id] and not finished(d, id) then return id end
  end
  return nil
end

-- a try that failed: the game said no, or never answered. Under three on this build, the quest is asked again at the
-- end of the pass
function fail(id)
  local d = db()
  local n = (d.surveyNo[id] or 0) + 1
  d.surveyNo[id] = n
  local s = diag()
  s.failed = s.failed + 1
  if n < TRIES and order then order[#order + 1] = id end
end

-- the game has the quest: read it a moment later (never inside the event, which can fire inside the request)
local function loaded(id)
  local s = diag()
  s.loaded = s.loaded + 1
  reads[id] = 0
  C_Timer.After(0, QB.Safe(function() read(id) end, "quest survey"))
end

local function answer(id, ok)
  if not pending[id] then return end -- not ours (Blizzard's own requests fire the event too), or too late
  pending[id] = nil
  inflight = inflight - 1
  if ok then
    pace = math.max(PACE, pace * 0.75)
    loaded(id)
  else
    fail(id)
  end
end

-- questions without an answer for TIMEOUT seconds failed; the game is slow, so the next ones go slower
local function expire()
  local t = now()
  for id, at in pairs(pending) do
    if t - at >= TIMEOUT then
      pending[id] = nil
      inflight = inflight - 1
      pace = math.min(SLOWEST, pace * 2)
      fail(id)
    end
  end
end

-- a quest the client has already is read as it is: asked for, its answer would come inside QuestBank's call, and
-- Blizzard's own listeners for it (the quest data callbacks) would run as QuestBank. Asked for, the answer comes
-- from the server later, in a call of the game's own
local function ask(id)
  if type(HaveQuestData) == "function" then
    local ok, have = pcall(HaveQuestData, id)
    if ok and plain(have) == true then loaded(id); return end
  end
  pending[id] = now()
  inflight = inflight + 1
  local s = diag()
  s.asked = s.asked + 1
  local ok = pcall(C_QuestLog.RequestLoadQuestByID, id)
  if not ok and pending[id] then answer(id, false) end
end

local tick
local function later(delay)
  gen = gen + 1
  local mine = gen
  C_Timer.After(delay, QB.Safe(function()
    if mine ~= gen then return end
    tick()
  end, "quest survey"))
end

function tick()
  if not on() then Survey.state = "off"; return end
  expire()
  local t = now()
  if t < holdUntil then Survey.state = "waiting"; later(holdUntil - t); return end
  if inCombat() then Survey.state = "fight"; later(COMBAT_WAIT); return end
  -- inside an instance it stops: the loading screen on the way out starts it again
  if inInstance() then Survey.state = "instance"; return end
  if not order or orderB ~= db().surveyB then order, pos, orderB = makeOrder(), 1, db().surveyB end
  -- an item whose level a quest's finder facts wait for, one at a time
  local item = table.remove(itemQueue, 1)
  if item and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then pcall(C_Item.RequestLoadItemDataByID, item) end
  if inflight >= FLIGHT then Survey.state = "asking"; later(pace); return end
  local id = nextId()
  if not id then
    if inflight > 0 then Survey.state = "asking"; later(TIMEOUT / 4); return end
    Survey.state = "done"
    if #itemQueue > 0 then later(PACE) end
    return
  end
  Survey.state = "asking"
  ask(id)
  later(pace)
end

-- (again) in hold seconds at the soonest
local function start(hold)
  holdUntil = math.max(holdUntil, now() + (hold or 0))
  if not on() then Survey.state = "off"; return end
  later(math.max(PACE, holdUntil - now()))
end
Survey.Start = start

function Survey.OnEvent(event, a1, a2)
  if event == "QUEST_DATA_LOAD_RESULT" then
    local id = tonumber(plain(a1))
    if id then answer(id, plain(a2) == true) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- login and /reload wait longer than a loading screen
    start((plain(a1) or plain(a2)) and START or SETTLE)
  elseif event == "LOADING_SCREEN_DISABLED" then
    start(SETTLE)
  elseif event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
    if Survey.state == "fight" then later(PACE) end
  elseif event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
    local item = tonumber(plain(a1))
    local quests = item and waitLevel[item]
    if quests and plain(a2) == true then
      waitLevel[item] = nil
      for qid in pairs(quests) do rate(qid) end
      changed()
    end
  end
end

-- the Settings box: unticked it stops asking (what it learned stays); ticked it goes on a moment later
function Survey.SetOn(yes)
  QB:Settings().survey = yes and true or false
  if yes then start(PACE) else gen = gen + 1; Survey.state = "off" end
end

-- how far it has got on this build: { asked, loaded, rewards, failed, done (answered or resting), total, state }
function Survey.Progress()
  local d, s = db(), diag()
  local total, done = 0, 0
  for _, str in ipairs(type(D.SURVEY) == "table" and D.SURVEY or {}) do
    for _, id in ipairs(Survey.Decode(str)) do
      total = total + 1
      if finished(d, id) then done = done + 1 end
    end
  end
  return { asked = s.asked, loaded = s.loaded, rewards = s.rewards, failed = s.failed, done = done, total = total,
           state = able() and (on() and Survey.state or "off") or "client", check = checked(d) }
end

local STATE = { waiting = "Starts in a moment.", fight = "Paused in combat.", instance = "Paused in this instance.",
                asking = "Asking now, two quests a second.", done = "Done for this game build.", idle = "Starts in a moment.",
                off = "Off: tick Learn quests from the game in Settings.", client = "Only on the Forever client." }

function Survey.Report(print)
  local p = Survey.Progress()
  print(string.format("Quest survey: %s of %s quests done on this build. Asked %s, loaded %s, %s with item rewards, %s failed. %s%s",
    QB.Comma(p.done), QB.Comma(p.total), QB.Comma(p.asked), QB.Comma(p.loaded), QB.Comma(p.rewards), QB.Comma(p.failed), STATE[p.state] or "",
    p.check == "failed" and " This client didn't show known rewards, so its no-reward answers aren't kept." or ""))
end

-- /qb survey find <text>: the surveyed quests whose title has the text, any case, ten lines at most:
-- "id  title  (level N)  rewards: name, name" (an item by its name when the client has it, else its id); none found:
-- how many quests have been asked so far. Returns the number found
function Survey.Find(text, print)
  local want = plain(text)
  want = type(want) == "string" and want:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
  local d, hits = db(), {}
  if want ~= "" then
    for id, rec in pairs(d.survey) do
      if type(id) == "number" and type(rec) == "table" and type(rec.t) == "string" and rec.t:lower():find(want, 1, true) then hits[#hits + 1] = id end
    end
  end
  table.sort(hits)
  if #hits == 0 then
    print(string.format("Nothing yet: %s quests asked so far.", QB.Comma(diag().asked)))
    return 0
  end
  local function itemName(item)
    local name
    if C_Item and C_Item.GetItemNameByID then
      local ok, n = pcall(C_Item.GetItemNameByID, item)
      if ok then name = plain(n) end
    end
    return (type(name) == "string" and name ~= "") and name or tostring(item)
  end
  for i = 1, math.min(10, #hits) do
    local id, rec = hits[i], d.survey[hits[i]]
    local names = {}
    for _, list in ipairs({ rec.c, rec.r }) do
      for _, item in ipairs(type(list) == "table" and list or {}) do names[#names + 1] = itemName(item) end
    end
    print(string.format("%d  %s  (level %s)  rewards: %s", id, rec.t, rec.lvl and tostring(rec.lvl) or "?", #names > 0 and table.concat(names, ", ") or "none"))
  end
  return #hits
end

function Survey:Init()
  if self.frame or not able() then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2) Survey.OnEvent(event, a1, a2) end, "quest survey"))
  for _, e in ipairs({ "QUEST_DATA_LOAD_RESULT", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED", "PLAYER_REGEN_ENABLED",
                       "ADDON_RESTRICTION_STATE_CHANGED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(f.RegisterEvent, f, e) -- (a client without one of them says no, and nothing more)
  end
  db()
  diag()
  start(START)
end
