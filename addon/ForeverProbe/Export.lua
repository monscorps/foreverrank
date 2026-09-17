--[[ /probe        one small panel: status, export, pace toggle
     /probe export straight to the copy box
     Export = a text blob the player copies and pastes at
     foreverrank.com. Nothing leaves the game on its own.             ]]

local ADDON, NS = ...

local function serialize(v, depth)
  depth = depth or 0
  if depth > 6 then return '"..."' end
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "table" then
    local parts = {}
    local isArray = #v > 0
    if isArray then
      for _, x in ipairs(v) do parts[#parts + 1] = serialize(x, depth + 1) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, x in pairs(v) do
      parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. serialize(x, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

local panel
local function buildPanel()
  panel = CreateFrame("Frame", "ForeverProbePanel", UIParent, "BackdropTemplate")
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
  hint:SetText("Ctrl+A then Ctrl+C, paste at foreverrank.com")

  local function btn(label, x, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(120, 20)
    b:SetPoint("BOTTOMLEFT", x, 6)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
  end
  btn("Export data", 12, function() NS.export() end)
  btn("Pace bar", 140, function() NS.paceToggle() end)
  btn("New snapshot", 268, function() NS.snapshot("manual"); NS.showPanel() end)
end

function NS.showPanel(withExport)
  if not panel then buildPanel() end
  local d = NS.db()
  local spells = d.snapshots[#d.snapshots] and #(d.snapshots[#d.snapshots].spells or {}) or 0
  panel.status:SetText(("Snapshots %d   Trainer scans %d   Known spells %d\nRead-only. Exports only when you press the button."):format(#d.snapshots, #d.trainers, spells))
  if not withExport then panel.box:SetText("") end
  panel:Show()
end

function NS.export()
  local d = NS.db()
  local blob = "FPROBE1:" .. serialize({ meta = d.meta, snapshots = d.snapshots, trainers = d.trainers, nemesis = d.nemesis, guild = d.guild })
  d.meta.lastExport = date("!%Y-%m-%dT%H:%M:%SZ")
  NS.showPanel(true)
  panel.box:SetText(blob)
  panel.box:HighlightText()
  panel.box:SetFocus()
end

SLASH_FOREVERPROBE1 = "/probe"
SLASH_FOREVERPROBE2 = "/foreverprobe"
SlashCmdList.FOREVERPROBE = function(msg)
  msg = (msg or ""):lower():gsub("%s+", "")
  if msg == "export" then NS.export()
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
    print("  A high reconciled count means this client changed its combat messages; export and report it.")
  else NS.showPanel() end
end
