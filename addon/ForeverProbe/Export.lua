--[[ /probe        one small panel: status, export, pace toggle
     /probe export straight to the copy box
     Export = a text blob the player copies and pastes at
     foreverrank.com/questbank (or the Windows companion uploads the
     saved file). Nothing leaves the game on its own.                ]]

local ADDON, NS = ...

-- JSON the site can read as it is: lists are lists even when empty, strings are JSON strings,
-- and a table is a list only when it has nothing but 1..n.
local LIST = { snapshots = true, trainers = true, spells = true, futureSpells = true, items = true, services = true,
               kills = true, deaths = true, roster = true, skills = true, engraving = true, errors = true, history = true,
               from = true, to = true, p = true }
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function str(s)
  return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end

local function serialize(v, depth, key)
  depth = depth or 0
  if depth > 10 then return "null" end
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.6g", v)
  end
  if t == "boolean" then return tostring(v) end
  if t == "string" then return str(v) end
  if t ~= "table" then return "null" end
  local n, count = 0, 0
  for _ in pairs(v) do count = count + 1 end
  while v[n + 1] ~= nil do n = n + 1 end
  local parts = {}
  if (n > 0 and count == n) or (count == 0 and LIST[key]) then
    for i = 1, n do parts[i] = serialize(v[i], depth + 1) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for k, x in pairs(v) do
    local ks = tostring(k)
    parts[#parts + 1] = str(ks) .. ":" .. serialize(x, depth + 1, ks)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end
NS.serialize = serialize

-- what goes out: the newest snapshot in full, the older ones as a line each, and the rest
function NS.exportData()
  local d = NS.db()
  local function key(sn) return sn.char or ((sn.name or "?") .. "-" .. (sn.realm or "?")) end
  local last = {}
  for i, sn in ipairs(d.snapshots) do last[key(sn)] = i end
  local snaps = {}
  for i, sn in ipairs(d.snapshots) do
    if last[key(sn)] == i then
      snaps[i] = sn
    else
      snaps[i] = { at = sn.at, why = sn.why, char = sn.char, name = sn.name, realm = sn.realm, class = sn.class, level = sn.level,
                   xp = sn.xp, xpMax = sn.xpMax, zone = sn.zone, money = sn.money, version = sn.version, build = sn.build }
    end
  end
  -- the characters' level records, with the current level's time live (stored time moves only with XP)
  local chars = {}
  local me = NS.util.CharKey()
  for k, c in pairs(d.chars or {}) do
    local cur = c.current
    if cur then
      local copy = {}
      for f, x in pairs(cur) do if f ~= "startedAt" and f ~= "lastEventAt" then copy[f] = x end end
      if k == me and NS.History then copy.elapsed = NS.History:LiveElapsed() end
      cur = copy
    end
    chars[k] = { history = c.history, current = cur }
  end
  return { meta = d.meta, snapshots = snaps, trainers = d.trainers, nemesis = d.nemesis, guild = d.guild,
           chars = chars, questbank = NS.questbank and NS.questbank() or nil }
end

local panel
local function buildPanel()
  local panel = CreateFrame("Frame", "ForeverProbePanel", UIParent, "BackdropTemplate")
  panel:SetSize(420, 300)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    panel:SetBackdropColor(0.03, 0.06, 0.12, 0.97)
    panel:SetBackdropBorderColor(0.9, 0.8, 0.5, 0.45)
  end

  local title = panel:CreateFontString(nil, "OVERLAY")
  title:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetTextColor(0.9, 0.8, 0.5)
  title:SetText("ForeverProbe")

  local status = panel:CreateFontString(nil, "OVERLAY")
  status:SetFont(STANDARD_TEXT_FONT, 10)
  status:SetPoint("TOPLEFT", 12, -30)
  status:SetTextColor(0.8, 0.82, 0.9)
  panel.status = status

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local scroll = CreateFrame("ScrollFrame", "ForeverProbeScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -74)
  scroll:SetPoint("BOTTOMRIGHT", -30, 44)
  local box = CreateFrame("EditBox", "ForeverProbeBox", scroll)
  box:SetMultiLine(true)
  box:SetFont(STANDARD_TEXT_FONT, 9, "")
  box:SetWidth(370)
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  scroll:SetScrollChild(box)
  panel.box = box

  local hint = panel:CreateFontString(nil, "OVERLAY")
  hint:SetFont(STANDARD_TEXT_FONT, 9)
  hint:SetPoint("BOTTOMLEFT", 12, 30)
  hint:SetTextColor(0.55, 0.58, 0.68)
  hint:SetText("Ctrl+A then Ctrl+C, then paste it in the upload box at foreverrank.com/questbank")

  local function btn(label, x, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(120, 20)
    b:SetPoint("BOTTOMLEFT", x, 6)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
  end
  btn("Export data", 12, function() NS.util.Try("export", NS.export) end)
  btn("Pace bar", 140, function() NS.paceToggle() end)
  btn("New snapshot", 268, function() NS.util.Try("snapshot", NS.snapshot, "manual"); NS.showPanel() end)
  return panel
end

local function questbankCount()
  local qb = NS.questbank and NS.questbank()
  if not qb then return nil end
  local n = 0
  for _ in pairs(qb.disc.q or {}) do n = n + 1 end
  return n
end

function NS.showPanel(withExport, size)
  if not panel then panel = buildPanel() end
  local d = NS.db()
  local spells = d.snapshots[#d.snapshots] and #(d.snapshots[#d.snapshots].spells or {}) or 0
  local qb = questbankCount()
  local line1 = ("Snapshots %d   Trainer scans %d   Known spells %d"):format(#d.snapshots, #d.trainers, spells)
  if qb then line1 = line1 .. ("   QuestBank notes %d quests"):format(qb) end
  local line2 = size and ("Export ready: %d KB. Read-only; nothing is sent."):format(math.ceil(size / 1024))
    or "Read-only. Exports only when you press the button."
  panel.status:SetText(line1 .. "\n" .. line2)
  if not withExport then panel.box:SetText("") end
  panel:Show()
end

function NS.export()
  local d = NS.db()
  d.meta.lastExport = date("!%Y-%m-%dT%H:%M:%SZ")
  d.meta.addon = NS.version
  local blob = "FPROBE2:" .. serialize(NS.exportData())
  NS.showPanel(true, #blob)
  panel.box:SetText(blob)
  panel.box:HighlightText()
  panel.box:SetFocus()
end

SLASH_FOREVERPROBE1 = "/probe"
SLASH_FOREVERPROBE2 = "/foreverprobe"
SlashCmdList.FOREVERPROBE = function(msg)
  msg = (msg or ""):lower():gsub("%s+", "")
  if msg == "export" then
    if not NS.util.Try("export", NS.export) and panel then
      local errs = NS.db().meta.errors or {}
      local e = errs[#errs]
      panel.status:SetText("Export failed: " .. (e and e.msg or "?") .. "\nType /probe debug for details.")
      panel:Show()
    end
  elseif msg == "bar" then NS.paceToggle()
  elseif msg == "debug" then
    local dbg = NS.Ledger.debug or {}
    local r = NS.Estimator.result or {}
    local rec = NS.History:Current() or {}
    print("|cffe5cc80ForeverProbe|r debug")
    print("  chat patterns compiled: " .. NS.Ledger:PatternCount())
    print("  XP events this session: " .. (dbg.parsed or 0) .. " kills parsed, " .. (dbg.quests or 0) .. " quests, " .. (dbg.unknown or 0) .. " reconciled (" .. (dbg.unknownXP or 0) .. " XP the patterns missed)")
    print("  this level: " .. (rec.killCount or 0) .. " kills, " .. (rec.questCount or 0) .. " quests, base XP " .. (rec.baseXP or 0))
    print("  estimate: rate source " .. (r.rateSource or "none") .. ", confidence " .. (r.confidence or "none"))
    if (dbg.secret or 0) > 0 then print("  " .. dbg.secret .. " XP lines the client kept from addons (counted from the XP bar instead).") end
    print("  A high reconciled count means this client changed its combat messages; export and report it.")
    local errs = NS.db().meta.errors or {}
    if #errs == 0 then print("  No errors noted.") end
    for _, e in ipairs(errs) do print(("  error x%d in %s (%s): %s"):format(e.n or 1, e.where or "?", e.v or "?", e.msg or "")) end
    local qb = questbankCount()
    print("  QuestBank discoveries: " .. (qb and (qb .. " quests, carried in your export") or "none (QuestBank isn't running, and doesn't have to be)"))
  else NS.util.Try("panel", NS.showPanel) end
end
