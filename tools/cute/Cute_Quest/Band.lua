-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step band: what the Guide's band draws while the Quests module is on, read from the engine (Cute.QuestBand).
-- Sets the engine's skin, so the step frame and the arrow the
-- copy draws are flat, in Cute's font and greys (QuestBank's own, while QuestBank is loaded, keep QuestBank's look).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
if not E then
  -- QuestBank loaded without QuestBankAPI (older than 6.1): no engine. The band says what is needed where the step
  -- would be, and each page draws that one line (QB.NeedPage) or has it as its section (QB.NeedSettings)
  local line = QB.missing or "QuestBank 6.1.0 or newer is needed."
  Cute.QuestBand = { On = function() return false end, Why = function() return line end }
  function QB.NeedPage(ui, scroll, key)
    local K, ROW = ui.COLORS, ui.ROW
    local w = scroll:Width()
    local v = ui:List(key, function(parent) return ui:MakeLine(parent) end)
    v:Set(1, 0, ROW, function(r, _, ly)
      r:SetHeight(ROW); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -ly); r:SetWidth(w)
      r.bg:SetColorTexture(1, 1, 1, 0); r.bar:Hide(); r.val:Hide(); r.who:Hide(); r.fn, r.tip = nil, nil
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 8, 0); r.name:SetWidth(w - 16); r.name:SetJustifyH("LEFT")
      ui.Color(r.name, K.MUTE); ui.FitText(r.name, line, w - 20); r.name:Show()
    end)
    ui.virtual = function() v:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
    scroll:SetContentHeight(ROW + 8)
  end
  function QB.NeedSettings(col, title) col:Head(title); col:Note(line) end
  return
end

if not QB.dormant then
  local INK, SOFT, WHITE = { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }, { 0.96, 0.96, 0.96 }
  -- (the windows round) the step frame as a stop of the route (StepFrame.lua's stop look): on the world with no
  -- backdrop unless the player asks for one (guide.backdrop, the frame's menu), its text outlined, the progress bar in
  -- the quest gold, "ready" in Cute's GOOD
  E.Skin = {
    font = Cute.Font(), INK = INK, SOFT = SOFT, ACCENT = WHITE, GOOD = { 0.45, 0.83, 0.47 }, QUEST = { 1, 0.82, 0 },
    stop = true, outline = true,
    -- (the journal's tiles: the range on a plate in its colours, a white edge on the open one: DungeonMap.lua; the
    -- Gear page's items: a 1 px edge in the quality's colour, names in Cute's lifted quality colours: Gear.lua)
    tiles = true, Quality = function(q) return Cute.Look and Cute.Look.QualityName(q) or nil end,
    -- a flat fill and a 1 px edge, as Cute's window (UI.lua's skin)
    Backdrop = function(f)
      if not f.SetBackdrop then return end
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      f:SetBackdropColor(0.035, 0.035, 0.035, 0.94)
      f:SetBackdropBorderColor(0, 0, 0, 1)
    end,
  }
end

-- the step band in the quest window's Quests tab (Cute's Guide.lua draws it): a click on the step reads its quest,
-- Ctrl-click shows it on the arrow, a right-click is its menu (Not now, Drop: the step's own, never the frame's lock,
-- scale and hide, which mean nothing in a window)
local function questOf(s) return s and s.qid and E.Quest.Get(s.qid) or nil end
-- (the windows round) a step's look for the band and the route: its icon by its kind (QuestNormal to accept, the
-- quest POI's hand-in, the game's cursor for an objective, the travel step's own, your class's icon to train, the
-- skull for your corpse), its words with the count apart (Guide.lua G.Parts), its quest's name where the words do not
-- carry it, the progress bar's colour (the quest gold for a quest's step; none for the others)
local QUEST = { 1, 0.82, 0 }
-- an objective's kind letter for its cursor (QuestMap.lua's QM.ART letters), for the pages' rows: its spot's in the
-- catalog, else "slain" a kill, a count a collect, else a use
function QB.ObjKind(id, slot, text)
  local QM, D = E.QuestMap, E.Data
  if QM and QM.Spots and D and D.SPOT then
    for _, sp in ipairs(QM.Spots(D.SPOT[id]) or {}) do if sp.slot == slot then return sp.kind end end
  end
  if type(text) == "string" and (text:find(" slain", 1, true) or text:find(" killed", 1, true)) then return "k" end
  if type(text) == "string" and text:find("%d+%s*/%s*%d+") then return "c" end
  return "u"
end
local function classArt()
  local cls = E.state and E.state.class
  local tc = type(CLASS_ICON_TCOORDS) == "table" and cls and CLASS_ICON_TCOORDS[cls] -- (SharedConstants.lua:27)
  local TEX = (E.Data and E.Data.TEX) or {}
  if type(tc) == "table" and tc[4] then return { nil, TEX.classes or 131146, { tc[1], tc[2], tc[3], tc[4] } } end
  return { nil, TEX.book or 134400 }
end
local function stepLook(s)
  local k = s.kind
  local icon
  if k == "accept" then
    local q = questOf(s)
    icon = { art = (q and q.repeatable) and "repeatable" or "accept" }
  elseif k == "handin" or k == "reward" then icon = { poi = "ready" }
  elseif k == "objective" then icon = { art = (s.obj == "d" and "d") or (s.obj and Cute.Look and Cute.Look.ART[s.obj] and s.obj) or "u" }
  elseif k == "grind" then icon = { art = "k" }
  elseif k == "travel" then icon = { art = { s.atlas, s.icon or ((E.Data and E.Data.TEX and E.Data.TEX.map) or 134269) } }
  elseif k == "train" then icon = { art = classArt() }
  elseif k == "corpse" then icon = { art = "skull" }
  end
  -- (a QuestBank loaded beside Cute older than the windows round has no G.Parts: its words whole, no count)
  local words, have, need
  if E.Guide.Parts then words, have, need = E.Guide.Parts(s) else words = E.Guide.Text(s) end
  local q = questOf(s)
  local quest = (q and k == "objective" and s.obj ~= "d") and q.name or nil
  local short = E.Guide.Short and E.Guide.Short(s) or nil
  local bar = (k == "accept" or k == "handin" or k == "objective" or k == "reward") and QUEST or nil
  return { icon = icon, words = words, have = have, need = need, quest = quest, short = short, bar = bar }
end
-- your level as the XP bar spans it: from your level to the one the plan's quests reach (two at least), where you stand,
-- and the XP each of the route's stops adds, as fractions of a level, in order (a stop crossing a level counted at the
-- next level's size: the catalog's D.TO_NEXT)
local function levelAfter(T, level, xp, gain)
  local lv, have = level, xp + gain
  while lv < #T and have >= (T[lv] or math.huge) do have = have - T[lv]; lv = lv + 1 end
  return lv + have / math.max(1, T[lv] or 1)
end
local function xpLook(perStop)
  local st = E.state
  local level = st.level or 1
  -- (an engine that cannot say how far into the level you are: the level alone, no bar)
  local T = E.Data and E.Data.TO_NEXT
  local max = (st.xpMax and st.xpMax > 1) and st.xpMax or (T and T[level]) or nil
  if not (T and max and st.xp) then return { level = level } end
  local xp = math.max(0, math.min(max, st.xp or 0))
  local at = level + xp / max
  local r = E.Target and E.Target.Route and E.Target.Route() or nil
  local gains, total, pos, got = {}, 0, at, 0
  for _, leg in ipairs(r and r.legs or {}) do
    local g = 0
    for _, row in ipairs(leg.rows or {}) do g = g + (row.xp or 0) end
    if g > 0 then
      local after = levelAfter(T, level, xp + got, g)
      if perStop then gains[#gains + 1] = after - pos else total = total + (after - pos) end
      pos, got = after, got + g
    end
  end
  if not perStop and total > 0 then gains[1] = total end
  return { level = level, frac = xp / max, at = at, from = level, to = math.max(level + 1, math.ceil(pos + 0.001)),
    gains = gains, planned = got, plannedText = E.Comma(got), after = pos }
end
-- the art of a dungeon for the core's card (Guide.lua G.DrawPick): its Encounter Journal art as the EJ cuts it
-- (DungeonMap.lua DM.SetCover), else its LFG background; a boss's face (DM.Face: the EJ's, a portrait, never a "?");
-- the best drop there for you (Gear.lua's upgrades); a click opens the Dungeons tab on it
local function catOf(d)
  local DM = E.DMap
  return DM and d and d.name and DM.Find(d.name) or nil
end
local dropMemo = { t = -100 }
Cute.QuestArt = {
  Cover = function(t, d, w, h)
    local cat = catOf(d)
    local data = cat and E.DMap.Data(cat.key) or {}
    if cat and (data.cover or cat.bg) and E.DMap.SetCover then E.DMap.SetCover(t, data, cat, w, h)
    else t:SetColorTexture(0, 0, 0, 1) end
  end,
  Face = function(t, d, enc, name)
    local cat = catOf(d)
    local data = cat and E.DMap.Data(cat.key)
    local boss
    for _, b in ipairs(data and data.bosses or {}) do if b.n == name or (enc and b.e == enc) then boss = b break end end
    if boss and E.DMap.Face then E.DMap.Face(t, boss, data) else t:SetTexture(137025) end
  end,
  Drop = function(d)
    if not (E.Gear and E.Gear.Upgrades) then return nil end
    local now = GetTime and GetTime() or 0
    if now - dropMemo.t > 10 or dropMemo.level ~= E.state.level then dropMemo = { t = now, level = E.state.level, rows = E.Gear.Upgrades() } end
    local best
    for _, r in ipairs(dropMemo.rows or {}) do
      local c = r.best
      if c and c.cat and c.cat.name == d.name and (not best or (c.ilvl - (r.beat or 0)) > (best.ilvl - (best.beat or 0))) then best = c; best.beat = r.worn and r.worn.ilvl or 0 end
    end
    if not best then return nil end
    local CI = C_Item
    local icon = CI and CI.GetItemIconByID and select(2, pcall(CI.GetItemIconByID, best.id)) or nil
    local q = CI and CI.GetItemQualityByID and select(2, pcall(CI.GetItemQualityByID, best.id)) or nil
    return { item = type(icon) == "number" and icon or 134400, q = type(q) == "number" and q or 1, up = true }
  end,
  OpenDungeon = function(d)
    local cat = catOf(d)
    if Cute.ModuleOn("journal") then
      Cute.Open("journal")
      if cat and E.DMap.Open then E.DMap.Open(cat, "map") end
    end
  end,
}
-- the cover of a dungeon or a raid for a run report's header (Cute's CardFrame.lua CF:Report, its 130 x 72 cover): the
-- Encounter Journal art or loading screen as DM.SetCover cuts it for w x h, as { texture, texcoords }; nil where the
-- engine knows no cover for the place (the report shows the Dungeon atlas then). By the place's name as the instance
-- gave it, the catalog holding no instance ids; inst, the instance's id, is the report's and kept for a later lookup
local function cutCover(cat, data, w, h)
  local out = {}
  local probe = {
    SetTexture = function(_, file) out.texture = file end,
    SetTexCoord = function(_, a, b, c, d) out.texcoords = { a, b, c, d } end,
  }
  E.DMap.SetCover(probe, data, cat, w, h)
  return out.texture and out or nil
end
Cute.QuestCover = function(inst, place, w, h)
  if type(place) ~= "string" or place == "" or not (E.DMap and E.DMap.SetCover) then return nil end
  local cat = catOf({ name = place })
  local data = cat and E.DMap.Data(cat.key)
  if not (data and (data.cover or cat.bg)) then return nil end
  return cutCover(cat, data, w or 130, h or 72)
end
Cute.QuestBand = {
  On = function() return Cute.ModuleOn("quests") and E.logReady == true end,
  -- why not, in a line (the engine reads the log at the game's first QUEST_LOG_UPDATE)
  Why = function() return "Reading your quest log." end,
  Steps = function() return E.Guide.Steps() end,
  Text = function(s) return E.Guide.Text(s) end,
  Look = function(s) return stepLook(s) end,
  XP = function(perStop) return xpLook(perStop) end,
  TimeToLevel = function() return E.Guide.TimeToLevel() end,
  Members = function() return E.Guide.MemberSteps() end,
  Open = function() Cute.Open("quests") end,
  Read = function(s, ui) local q = questOf(s); if q and QB.Reader then QB.Reader.Read(ui, q) end end,
  Arrow = function(s) local q = questOf(s); if q then E.UI.QuestClick(q, E:Status(q), "LeftButton") end end,
  Menu = function(s)
    local q = questOf(s)
    if not q then return end
    local name = E.UI.Short(q.name, 24)
    E.UI:ShowMenu(q.name, { { "Not now", function() E.Guide.Skip(q.id, "later") end }, { "Drop " .. name, function() E.Guide.Skip(q.id, "drop") end } })
  end,
  -- /cute diag's look line (the windows round): the game's tracker and the game's map as only the live client shows
  -- them, no names (StepFrame.lua SF.TrackerDiag, QuestMap.lua QM.DiagLine; an older QuestBank without them: "?")
  Diag = function()
    local SF, QM = E.StepFrame, E.QuestMap
    local t = SF and type(SF.TrackerDiag) == "function" and SF.TrackerDiag() or "tracker: ?"
    local m = QM and type(QM.DiagLine) == "function" and QM.DiagLine() or "game's map: ?"
    return t .. "; " .. m
  end,
}
-- the on-screen switches in Cute's menu (Quests (L) > Step frame, Direction arrow): the engine's own settings, the
-- copy's (while QuestBank is loaded its settings are its own: none)
Cute.OnScreen = function()
  if QB.dormant then return {} end
  local s = E:Settings()
  return {
    { "Step frame", function() return s.guide.frame == true end, function() s.guide.frame = not (s.guide.frame == true); if E.StepFrame then E.StepFrame.Apply() end end },
    { "Direction arrow", function() return s.arrow == true end, function() if E.Arrow then E.Arrow:Set(not (s.arrow == true)) else s.arrow = not s.arrow end end },
  }
end
