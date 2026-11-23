-- SPDX-License-Identifier: GPL-3.0-or-later
-- The look of QuestBank's reminders (pattern D), which Cute Auras keeps: a 32 px game icon, cropped, a 1 px black edge,
-- the cooldown's sweep, a count at its bottom right; under it a 2 px bar in its part's colour (camp QUEST gold, yours
-- WHITE, the group's GROUP teal) and one word (the verb, the member, the minutes; a status in WARN or BAD).
local _, A = ...
local L = {}
A.Look = L

L.C = {
  WHITE = { 0.96, 0.96, 0.96 }, INK = { 0.86, 0.86, 0.86 }, DIM = { 0.58, 0.58, 0.58 },
  WARN = { 0.93, 0.74, 0.35 }, BAD = { 0.88, 0.36, 0.33 }, GOOD = { 0.45, 0.85, 0.45 },
  QUEST = { 1, 0.82, 0 }, GROUP = { 0.31, 0.82, 0.77 }, PINK = { 1, 0.6, 0.84 },
  PANEL = { 0.07, 0.07, 0.07 }, PANEL2 = { 0.11, 0.11, 0.11 }, RULE = { 0.2, 0.2, 0.2 },
}
local C = L.C
L.BAR = { camp = C.QUEST, mine = C.WHITE, group = C.GROUP, pull = C.GROUP, gear = C.PINK }
L.SIZE, L.GAP = 32, 6
L.COL = L.SIZE + L.GAP
L.FLAT = "Interface\\Buttons\\WHITE8x8"

local FONT
function L.Font()
  if FONT then return FONT end
  local fo = GameFontNormal
  FONT = (fo and fo.GetFont and fo:GetFont()) or "Fonts\\FRIZQT__.TTF"
  return FONT
end
-- a line of text over the world: the game's font, outlined, a 1 px shadow; with lines, it wraps at its width to that
-- many lines (the last cut with "..." only past them)
function L.Text(parent, size, col, width, justify, lines)
  local t = parent:CreateFontString(nil, "OVERLAY")
  if GameFontNormal then t:SetFontObject(GameFontNormal) end
  t:SetFont(L.Font(), size or 12, "OUTLINE")
  if t.SetShadowOffset then t:SetShadowOffset(1, -1); t:SetShadowColor(0, 0, 0, 1) end
  col = col or C.INK
  t:SetTextColor(col[1], col[2], col[3])
  t:SetJustifyH(justify or "CENTER")
  if lines and lines > 1 then
    t:SetWordWrap(true)
    t:SetMaxLines(lines)
    if t.SetJustifyV then t:SetJustifyV("TOP") end
  else
    t:SetWordWrap(false)
  end
  if width then t:SetWidth(width) end
  return t
end
-- a blessing's or Hand's short name for a card's title: "Blessing of Kings" is "Kings" (a name in another language
-- stays whole)
function L.Short(name)
  if type(name) ~= "string" then return name end
  return (name:gsub("^Greater Blessing of ", ""):gsub("^Blessing of ", ""):gsub("^Hand of ", ""))
end
-- text on a panel (the window): no outline
function L.Label(parent, size, col, justify)
  local t = parent:CreateFontString(nil, "OVERLAY")
  if GameFontNormal then t:SetFontObject(GameFontNormal) end
  t:SetFont(L.Font(), size or 12, "")
  col = col or C.INK
  t:SetTextColor(col[1], col[2], col[3])
  t:SetJustifyH(justify or "LEFT")
  t:SetWordWrap(false)
  return t
end
-- a text's whole width at its font, its box's width aside (GetUnboundedStringWidth; GetStringWidth on a client without
-- it); 0 where the client can't say
function L.Width(fs)
  local get = fs.GetUnboundedStringWidth or fs.GetStringWidth
  if type(get) ~= "function" then return 0 end
  local w = A.Plain(A.Call(get, fs))
  return type(w) == "number" and w or 0
end
function L.Fill(parent, layer, col, alpha)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(col[1], col[2], col[3], alpha or 1)
  return t
end
-- a class's colour (the game's), the ink without one
function L.ClassColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return c.r, c.g, c.b end
  return C.INK[1], C.INK[2], C.INK[3]
end

-- an icon: secure (the game's SecureActionButtonTemplate, set out of a fight only) or a plain button; edge, art, sweep,
-- count, the part's bar and, with a word, the word under it
function L.Icon(name, parent, secure, withWord, size)
  size = size or L.SIZE
  local b = CreateFrame("Button", name, parent, secure and "SecureActionButtonTemplate" or nil)
  b:SetSize(size, size)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(0, 0, 0, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  b.count = L.Text(b, 10, C.WHITE)
  b.count:SetJustifyH("RIGHT")
  b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetSize(size, 2)
  b.bar:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b.bar:Hide()
  if withWord then
    b.word = L.Text(b, 11, C.INK, size + L.GAP)
    b.word:SetPoint("TOP", b, "BOTTOM", 0, -6)
  end
  b.hi = b:CreateTexture(nil, "HIGHLIGHT")
  b.hi:SetAllPoints()
  b.hi:SetColorTexture(1, 1, 1, 0.12)
  return b
end

-- an icon's art: a number or a path, cropped of its border; nothing written that has not changed
function L.Art(t, tex)
  tex = tex or 134400
  if t.caTex == tex then return end
  t.caTex = tex
  t:SetTexture(tex)
  t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- one icon's look from its record: its art, lit or waiting, out of range, the count, the sweep, the part's bar, the word
function L.Paint(b, rec)
  L.Art(b.icon, rec.tex)
  local waiting = not rec.lit
  b.icon:SetDesaturated(waiting)
  b.icon:SetAlpha(waiting and 0.55 or 1)
  b:SetAlpha(rec.far and 0.45 or 1)
  local count = rec.count and rec.count > 1 and rec.count or nil
  if b.caCount ~= count then b.caCount = count; b.count:SetText(count and tostring(count) or "") end
  if rec.cdDur and rec.cdDur > 0 then
    if b.caCD ~= rec.cdStart then b.caCD = rec.cdStart; b.cd:SetCooldown(rec.cdStart, rec.cdDur) end
  elseif b.caCD then b.caCD = nil; b.cd:SetCooldown(0, 0) end
  local col = L.BAR[rec.part or ""]
  if col then b.bar:SetColorTexture(col[1], col[2], col[3], 1); b.bar:Show() else b.bar:Hide() end
  if b.word then
    local w = rec.word or ""
    if b.word:GetText() ~= w then b.word:SetText(w) end
    local wc = rec.status == "bad" and C.BAD or rec.status == "warn" and C.WARN or C.INK
    if rec.class and rec.status == nil then
      b.word:SetTextColor(L.ClassColor(rec.class))
    else
      b.word:SetTextColor(wc[1], wc[2], wc[3])
    end
  end
  b.rec = rec
end

-- a spell's icon and name in the player's language, the given ones where the client can't say
function L.SpellIcon(id, fallback)
  local get = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
  local tex
  if type(get) == "function" then tex = A.Plain(A.Call(get, id)) end
  return tex or fallback or 134400
end
function L.SpellName(id, fallback)
  local get = C_Spell and C_Spell.GetSpellName or GetSpellInfo
  if type(get) == "function" then
    local n = A.Plain(A.Call(get, id))
    if type(n) == "string" and n ~= "" then return n end
  end
  return fallback
end
function L.ItemIcon(id, fallback)
  if C_Item and C_Item.GetItemIconByID then
    local tex = A.Plain(A.Call(C_Item.GetItemIconByID, id))
    if tex then return tex end
  end
  return fallback or 134400
end
function L.ItemName(id, fallback)
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  if type(get) == "function" then
    local n = A.Plain(A.Call(get, id))
    if type(n) == "string" and n ~= "" then return n end
  end
  return fallback
end
-- an icon file from the item database's name ("inv_misc_bag_10"), or the number
function L.IconPath(i, fallback)
  if type(i) == "number" then return i end
  if type(i) == "string" and i ~= "" then return "Interface\\Icons\\" .. i end
  return fallback or 134400
end
