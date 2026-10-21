-- SPDX-License-Identifier: GPL-3.0-or-later
-- RunsUI: the Runs module's face (the run report's design, 8.4, 8.5, 9.7 and 14): the Runs tab in the guild window (the
-- history, newest first; the run on now in its band, with the leader's End run), Settings > Runs, Send to party, the
-- test report and the slash words (/cute run, /cute run end, /cute run test [raid], /cute diag runs). It registers the
-- module: id runs, order 45 (after the Hall of Shame), on by default.
local _, C = ...
local RU = {}
C.RunsUI = RU

local WHITE, INK, DIM, MUTE = { 0.96, 0.96, 0.96 }, { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }, { 0.52, 0.52, 0.52 }
local DOT = " \194\183 " -- (a middle dot in Windows-1252; the file stays ASCII)
local SPRINT = 132307    -- Ability_Rogue_Sprint (ManifestInterfaceData.csv): a group run's row
local function A() return C.Awards end
local function R() return C.Runs end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function callable(name) return type(_G[name]) == "function" end
local function call(name, ...) if not callable(name) then return nil end return C.Get(_G[name], ...) end
local function mySfx() return (C.MyGUID() or ""):match("([^%-]+)$") end

----------------------------------------------------------------------------
-- Send to party (8.4): plain text for members without the addon, every line inside the click (all in its one call
-- stack), on RAID in a raid, INSTANCE_CHAT in an instance group, else PARTY. A post the game blocks fails silently, so
-- the button is greyed where the game is known to block chat (CardFrame.lua CF.SendState), and /cute diag runs keeps
-- the lockdown's state at each post. Then 2P tells the group who posted
----------------------------------------------------------------------------
local function nameIn(rep) return function(sfx) local m = rep.members and rep.members[sfx]; return m and m.n or nil end end
function RU.SendToParty(rep)
  local CF = C.CardFrame
  local ok, why = CF.SendState(rep)
  local CI = C_ChatInfo
  RU.lastPost = { at = C.Now(), ok = ok and true or false, why = why,
    lockdown = type(CI) == "table" and type(CI.InChatMessagingLockdown) == "function" and C.Get(CI.InChatMessagingLockdown) == true or false }
  if not ok then return false end
  local channel = C.RunComm.Channel()
  if not (channel and type(CI) == "table" and type(CI.SendChatMessage) == "function") then return false end
  local lines = A().Text(rep, nameIn(rep))
  -- (Cute's own lines never count as typed: Sample.lua's chat hook passes them by)
  C.Sample.quiet = true
  for _, line in ipairs(lines) do pcall(CI.SendChatMessage, line, channel) end
  C.Sample.quiet = nil
  RU.lastPost.lines = #lines
  R().sentFor = rep.id
  C.RunComm:Send("2P", rep.id)
  CF:DrawSend()
  return true
end
-- the test's Print to chat: the same lines in your own chat frame, nothing sent
function RU.PrintToChat(rep)
  for _, line in ipairs(A().Text(rep, nameIn(rep))) do C.Print(line, true) end
end

----------------------------------------------------------------------------
-- the test report (9.7): in a group your real group members (so the models show) with made-up values; alone, you and
-- four made-up names with their race's portrait. A new set of five awards each time; nothing sent, saved or counted
----------------------------------------------------------------------------
local MADE_UP = { { "Mossbottom", "WARRIOR", "Dwarf", 3 }, { "Kettlewick", "MAGE", "Gnome", 2 }, { "Pell", "ROGUE", "Human", 2 }, { "Thistle", "DRUID", "NightElf", 3 } }
local RAID_UP = { "Bramble", "Fennick", "Gorse", "Hollin", "Juniper", "Larch", "Marram", "Nettle", "Osier", "Quince", "Rowan", "Sorrel", "Tansy",
  "Umber", "Vetch", "Wicken", "Yarrow", "Alder", "Burdock", "Comfrey", "Dittany", "Elder", "Furze", "Garlic", "Hazel", "Ivy", "Kale", "Lovage",
  "Madder", "Nard", "Orris", "Parsley", "Rue", "Sedge", "Teasel" }
local CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "DRUID", "PALADIN", "WARLOCK", "SHAMAN" }
local RACES = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll", "BloodElf", "Draenei" }
function RU.Test(raid, nextOne)
  RU.draws = (RU.draws or 0) + 1
  local list, members = {}, {}
  local function add(sfx, name, class, race, sex, guid)
    list[#list + 1] = { sfx = sfx }
    members[sfx] = { n = name, c = class, r = race, s = sex, g = guid }
  end
  local first = call("UnitName", "player")
  local _, class = call("UnitClass", "player")
  local _, race = call("UnitRace", "player")
  local sex = call("UnitSex", "player")
  add(mySfx() ~= "" and mySfx() or "you", type(first) == "string" and first or "You", class, race, sex, C.MyGUID())
  local want = raid and 40 or 5
  if call("IsInGroup") == true then
    local g = R().Group()
    for sfx, e in pairs(g) do
      if type(e) == "table" and e.guid and not e.me and #list < want then add(sfx, e.name or "?", e.class, e.race, e.sex, e.guid) end
    end
  end
  local k = 0
  while #list < want do
    k = k + 1
    local mu = MADE_UP[k]
    if mu then add("test" .. k, mu[1], mu[2], mu[3], mu[4])
    else
      local name = RAID_UP[(k - #MADE_UP - 1) % #RAID_UP + 1]
      add("test" .. k, name, CLASSES[k % #CLASSES + 1], RACES[k % #RACES + 1], 2 + k % 2)
    end
  end
  local cards = A().Sample(RU.draws, list)
  local mentions = {}
  if raid then
    local used = {}
    for _, c in ipairs(cards) do used[c[2]] = true end
    local i = 6
    for _, a in ipairs(A().LIST) do
      if #mentions >= 10 then break end
      if a.kind ~= "thanks" and not used[a.code] and list[i] then mentions[#mentions + 1] = { list[i].sfx, a.code, A().SAMPLE_VALUE[a.code] or 1, a.kind }; i = i + 1 end
    end
  end
  local zone = call("GetRealZoneText")
  local rep = { id = "test" .. RU.draws, kind = raid and "r" or "d", place = (type(zone) == "string" and zone ~= "") and zone or "Test run",
    start = C.ServerNow() - 2530, dur = 2530, bosses = raid and 8 or 5, known = raid and 8 or 5, wipes = 1, deaths = 7, n = #list,
    cards = cards, mentions = mentions, gone = {}, members = members, test = true }
  C.CardFrame:Report(rep, { test = true })
  return rep
end

----------------------------------------------------------------------------
-- the Runs tab (8.5): the band (the run on now, the leader's End run; with no history, "No runs yet." and Show a
-- test report), the history as rows in the windows design's pattern A, 20 units: the 2 px GROUP bar, the Dungeon or
-- Raid atlas or the sprint icon for a group run, the day and time, the place; on the right the time and the bosses,
-- and your own card's title in its kind's colour. A click opens the report, a right-click offers to delete it
----------------------------------------------------------------------------
local function makeRow(parent)
  local U = C.UI
  local r = U:MakeLine(parent)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 8, 0)
  r.date = U.Text(r, 11, DIM, "LEFT", 96)
  r.date:SetPoint("LEFT", 30, 0)
  return r
end
local function placeLine(rep)
  local s = A().Clock(rep.dur or 0)
  if rep.kind ~= "g" then s = s .. DOT .. (rep.bosses or 0) .. "/" .. math.max(rep.known or 0, rep.bosses or 0) end
  return s
end
local function deleteFromHistory(rep)
  local list = R().DB().list
  for i = #list, 1, -1 do if list[i] == rep then table.remove(list, i) end end
  C.UI:Draw()
end
function RU.Draw(ui)
  local U = C.UI
  local K = U.COLORS
  local sf = ui.scroll
  ui.header:Hide()
  ui.rows:Clear()
  local w = sf:Width()
  local ROW = U.ROW
  local db = R().DB()
  local y = 4
  local function bandLine(text, c, tip)
    local l = ui.bandLines:Get()
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", 0, -y)
    l:SetSize(w, ROW)
    l.bg:SetColorTexture(1, 1, 1, 0)
    l.bar:Hide()
    l.val:Hide(); l.who:Hide()
    l.fn, l.tip = nil, tip
    l.name:ClearAllPoints(); l.name:SetPoint("LEFT", 8, 0); l.name:SetJustifyH("LEFT")
    color(l.name, c)
    return l
  end
  local snap = R():Snapshot()
  if snap then
    local text = "Now: " .. snap.place .. DOT .. A().Clock(snap.t) .. (snap.kind ~= "g" and (DOT .. snap.bosses .. (snap.bosses == 1 and " boss" or " bosses")) or "") .. DOT .. "scribe " .. snap.scribe
    local leader = call("IsInGroup") ~= true or call("UnitIsGroupLeader", "player") == true
    local l = bandLine(text, K.INK, function(tip) tip:AddLine(text, 1, 1, 1, true) end)
    local room = w - 16 - (leader and 80 or 0)
    l.name:SetWidth(room)
    U.FitText(l.name, text, room - 4)
    -- (the band's pooled buttons, anchored and sized as every page anchors them: TOPLEFT, the pool's height)
    if leader then
      local b = ui.bandButtons:Get()
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", w - 74, -y)
      b:SetWidth(70)
      b:SetLabel("End run")
      b:SetOn(true)
      b:SetScript("OnClick", function() R():EndRun(); C.UI:Draw() end)
      b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
    end
    y = y + 24
  end
  local list = db.list
  if #list == 0 then
    local l = bandLine("No runs yet.", K.MUTE)
    l.name:SetWidth(w - 200)
    U.FitText(l.name, "No runs yet.", w - 204)
    local b = ui.bandButtons:Get()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", w - 154, -y)
    b:SetWidth(150)
    b:SetLabel("Show a test report")
    b:SetOn(true)
    b:SetScript("OnClick", function() RU.Test(false) end)
    b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
    y = y + 24
  end
  ui:SetBand(y > 4 and (y + 4) or 0)
  local rows = ui:List("runs", makeRow)
  local VAL, MINE = 110, 130
  rows:Set(#list, 0, ROW, function(r, i, ly)
    local rep = list[i]
    r:SetHeight(ROW)
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    r.bar:Show()
    r.bar:SetColorTexture(C.Cards.GROUP[1], C.Cards.GROUP[2], C.Cards.GROUP[3], 1)
    if rep.kind == "g" then r.icon:SetTexture(SPRINT) else r.icon:SetAtlas(rep.kind == "r" and "Raid" or "Dungeon") end
    r.date:SetText(date and rep.start and date("%a %d %b %H:%M", rep.start) or "")
    -- the right: your own card's title in its kind's colour, then the time and the bosses
    local mine = rep.mine and A().Of(rep.mine[1])
    r.who:ClearAllPoints(); r.who:SetPoint("RIGHT", -4, 0); r.who:SetWidth(MINE); r.who:SetJustifyH("RIGHT")
    color(r.who, (mine and C.Cards.KindColor(mine.kind)) or K.DIM)
    U.FitText(r.who, mine and mine.title or "", MINE - 4)
    r.who:Show()
    r.val:ClearAllPoints(); r.val:SetPoint("RIGHT", -(MINE + 8), 0); r.val:SetWidth(VAL); r.val:SetJustifyH("RIGHT")
    color(r.val, K.DIM)
    U.FitText(r.val, placeLine(rep), VAL - 4)
    r.val:Show()
    local room = w - 132 - VAL - MINE - 16
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 132, 0); r.name:SetWidth(room); r.name:SetJustifyH("LEFT")
    color(r.name, K.INK)
    U.FitText(r.name, rep.place or "?", room - 4)
    r.fn = function(_, which)
      if which == "RightButton" then
        if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
          MenuUtil.CreateContextMenu(r, function(_, root)
            root:CreateTitle(rep.place or "Run")
            root:CreateButton("Delete from history", function() deleteFromHistory(rep) end)
          end)
        end
        return
      end
      C.CardFrame:Report(rep)
    end
    r.tip = function(tip)
      tip:AddLine(rep.place or "?", 1, 1, 1)
      tip:AddLine((date and rep.start and date("%A %d %B %H:%M", rep.start) or "") .. DOT .. placeLine(rep), 0.7, 0.7, 0.7)
      for _, c in ipairs(rep.cards or {}) do
        local a = A().Of(c[2])
        local m = rep.members and rep.members[c[1]]
        if a then tip:AddLine(a.title .. ": " .. (m and m.n or "?"), 0.85, 0.85, 0.85) end
      end
      tip:AddLine("Click: the report. Right-click: delete it.", 0.5, 0.5, 0.5, true)
    end
  end)
  ui.virtual = function() rows:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  sf:SetContentHeight(#list * ROW + 8)
end

----------------------------------------------------------------------------
-- Settings > Runs: four rows
----------------------------------------------------------------------------
function RU.Settings(_, col)
  local db = R().DB()
  col:Head("Run reports")
  col:Check("Show the report when a run ends", db.show, true, function(on) db.show = on; C.UI:Draw() end)
  col:Check("Long groups outside instances (2 or more, 15 minutes)", db.long, true, function(on) db.long = on; C.UI:Draw() end)
  col:Choice("Keep", { "10", "20", "50" }, tostring(db.keep), function(v)
    local n = tonumber(v)
    if n then db.keep = n; while #db.list > n do table.remove(db.list) end end
    C.UI:Draw()
  end)
  col:Buttons({ { "Show a test report", true, function() RU.Test(false) end }, { "Last report", #db.list > 0, function() C.CardFrame:Report(db.list[1]) end } })
end

----------------------------------------------------------------------------
-- /cute diag runs: the meter's availability and why, the sessions read, the run's id, kind and scribe, this client's
-- messages on the group channel, the restriction, each result 11 and whether an encounter was on, the chat lockdown
-- at the last post. No name
----------------------------------------------------------------------------
function RU.Diag()
  local lines = {}
  local snap = R():Snapshot()
  if snap then
    lines[#lines + 1] = string.format("diag runs: run %s, %s, %d s, %d bosses, scribe %s | meter %s, %d sessions read | UNIT_DIED secret %d", snap.id, snap.kind,
      snap.t, snap.bosses, snap.scribe == "you" and "you" or "another member", snap.meter, snap.reads, snap.unseen)
  else
    local db = R().DB()
    lines[#lines + 1] = "diag runs: no run on | " .. #db.list .. " in the history, keeping " .. db.keep .. (db.show and "" or ", reports not shown")
  end
  lines[#lines + 1] = "diag runs: " .. C.RunComm.Report() .. " | prefix " .. tostring(R().prefixResult)
  local p = RU.lastPost
  lines[#lines + 1] = string.format("diag runs: last post %s | race model %s", p and string.format("%s, chat lockdown %s, %d lines", p.ok and "went" or ("greyed: " .. tostring(p.why)), tostring(p.lockdown), p.lines or 0) or "none",
    C.Cards.RaceModelOn() and "on (testing)" or "off")
  return lines
end

----------------------------------------------------------------------------
-- the slash words, before the core's (Core.lua's /cute takes the rest)
----------------------------------------------------------------------------
function RU.Slash(msg)
  if msg == "diag runs" then for _, l in ipairs(RU.Diag()) do C.Print(l) end return end
  local rest = msg:match("^run%s*(.*)$") or ""
  if rest == "" then
    local last = R().DB().list[1]
    if last then C.CardFrame:Report(last) else C.Print("no runs yet. /cute run test shows a test report.") end
  elseif rest == "end" then
    if not R().run then C.Print("no run on.")
    elseif not R():EndRun() then C.Print("only the group's leader ends the run.") end
  elseif rest == "test" then RU.Test(false)
  elseif rest == "test raid" then RU.Test(true)
  elseif rest == "model on" or rest == "model off" then
    -- (for the testers: the race's base model on cards of members out of sight, until it is seen to draw in game)
    C.Settings().raceModel = rest == "model on" or nil
    C.Print("the race model on cards is " .. (rest == "model on" and "on: tell us whether it draws." or "off."))
  else C.Print("/cute run: the last report; /cute run end; /cute run test [raid].") end
end
do
  local core = SlashCmdList.CUTE
  SlashCmdList.CUTE = C.Safe(function(msg)
    local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if m == "diag runs" or m == "run" or m:match("^run%s") then RU.Slash(m) return end
    return core(msg)
  end, "slash")
end

----------------------------------------------------------------------------
-- the module
----------------------------------------------------------------------------
-- (Send to party's state follows combat)
do
  local ev = C.Runs.events
  local dis, en = ev.PLAYER_REGEN_DISABLED, ev.PLAYER_REGEN_ENABLED
  ev.PLAYER_REGEN_DISABLED = function(...) dis(...); C.CardFrame:DrawSend() end
  ev.PLAYER_REGEN_ENABLED = function(...) en(...); C.CardFrame:DrawSend() end
end
C:RegisterModule({
  id = "runs", title = "Runs", order = 45, builtin = true, default = true, tab = 64,
  notes = "Run reports after dungeons, raids and long groups: a card for each of you, with Send to party.",
  page = function(ui) RU.Draw(ui) end,
  settings = function(ui, col) RU.Settings(ui, col) end,
  events = C.Runs.events,
  onToggle = function(on)
    local Rn = C.Runs
    if on then
      Rn.Register()
      Rn.startTimers()
    else
      -- (switched off: nothing counted or sent from now; a run on is dropped without a report)
      Rn.run = nil
      C.Char().run = nil
      Rn:Counting(false)
      C.RunComm:Clear()
    end
    -- (the Me page: whether this character's Runs counts the run fields)
    for _, f in ipairs(C.Stats.RUNFIELDS) do C.Sample.values[f[1]] = on and true or false end
  end,
})
