-- The quest engine's mocks for Cute's harness: what QuestBank's engine reads of the client that Cute's own mock does
-- not define, ported from tools/questbank/harness.lua's newClient (its lines are named at each block) and its BASE
-- (the map canvas family, 281-379), and kept to the shape the engine reads. Installed on a client made with
-- o.quest = true, after Cute's mocks, never over them: where Cute's table has the function, Cute's stays (the engine
-- reads the same shape), and where the engine needs more of a table, the functions are added to Cute's.
--   install(env, c, o, newObj, api, secret)
-- The character is Cute's charOf: o.level, o.class, o.faction, o.done (ids), o.log (id -> log index); o.world =
-- { continent, wx, wy } is where it stands (Northshire by default), o.race its race, o.map the map it is on.
local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/test/[^/]*$")) or "."
return function(env, c, o, newObj, api, secret)
  local function nothing() end
  o.world = o.world or { 0, -8914, -133 }
  o.map = o.map or 1453
  o.race = o.race or "Human"
  -- the quest engine's own addon table (Cute_Quest's private table, once loaded): its Data answers the map mocks
  local function QBData()
    for _, a in ipairs(c.addons or {}) do if a.name == "Cute_Quest" then return a.private.Data end end
    return nil
  end
  -- the log as the engine reads it: { { id, complete }, ... } in o.log's index order; c.done the completed ids
  local function logList()
    local out = {}
    for id, idx in pairs(o.log or {}) do out[#out + 1] = { id, 0, idx = type(idx) == "number" and idx or 0 } end
    table.sort(out, function(x, y) if x.idx ~= y.idx then return x.idx < y.idx end return x[1] < y[1] end)
    return out
  end
  c.done = o.done or {}

  ----------------------------------------------------------------------------
  -- BASE: the globals QuestBank's harness keeps for every client (281-379 and 250-280), set on this env alone
  ----------------------------------------------------------------------------
  env.QUESTBANK_DEV = true
  env.debugprofilestop = function() return os.clock() * 1000 end
  env.SetPortraitTexture = nothing
  env.SetPortraitTextureFromCreatureDisplayID = function(t, id) t.__tex = "portrait:" .. tostring(id); t.__portrait = id end
  env.geterrorhandler = function() return error end
  env.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
  -- the game's super-tracking: the engine never touches it (its listeners would run as the addon)
  env.C_SuperTrack = setmetatable({}, { __index = function(_, k)
    return function() error("the quest engine called C_SuperTrack." .. tostring(k) .. ": the game's tracking is the player's own", 2) end
  end })
  env.CreateVector2D = function(x, y) return { x = x, y = y } end
  env.Ambiguate = function(name) return name end
  env.CLASS_ICON_TCOORDS = { PALADIN = { 0, 0.25, 0.5, 0.75 }, WARRIOR = { 0, 0.25, 0, 0.25 }, SHAMAN = { 0.25, 0.49, 0.25, 0.5 } }
  env.CreateFromMixins = function(...)
    local t = {}
    for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do t[k] = v end end
    return t
  end
  env.MapCanvasDataProviderMixin = {
    GetMap = function(self) return self.owningMap end,
    OnAdded = function(self, map) self.owningMap = map end,
    OnRemoved = function(self) self.owningMap = nil end,
    OnMapChanged = function(self) self:RefreshAllData() end,
    RefreshAllData = nothing, RemoveAllData = nothing, OnShow = nothing, OnHide = nothing,
    OnCanvasScaleChanged = nothing, OnCanvasSizeChanged = nothing,
  }
  for _, name in ipairs({ "MapExplorationDataProviderMixin", "MapHighlightDataProviderMixin", "AreaLabelDataProviderMixin",
                          "GroupMembersDataProviderMixin", "QuestBlobDataProviderMixin" }) do
    env[name] = env.CreateFromMixins(env.MapCanvasDataProviderMixin, { __blizzard = name, OnAdded = function(self, map)
      if map.__client and map.__client.combat then error("ADDON_ACTION_BLOCKED: " .. name .. " acquired its pin in combat", 2) end
      self.owningMap = map
    end })
  end
  env.Mixin = function(obj, ...)
    for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end
    return obj
  end
  env.secureexecuterange = function(t, fn, ...) for k, v in pairs(t) do fn(k, v, ...) end end
  env.GetQuestDifficultyColor = function() return { r = 1, g = 0.82, b = 0 } end
  env.ClearCachedActivitiesForPlayer = function() error("the quest engine cleared the map caches", 2) end
  local function cleared() env.ClearCachedActivitiesForPlayer() end
  local function asked(name) return function(self, ...) table.insert(self.__calls, { name, ... }) end end
  local GAME_LEVELS = { PIN_FRAME_LEVEL_QUEST_BLOB = 2007, PIN_FRAME_LEVEL_DIG_SITE = 2014, PIN_FRAME_LEVEL_DUNGEON_ENTRANCE = 2015,
    PIN_FRAME_LEVEL_FLIGHT_POINT = 2017, PIN_FRAME_LEVEL_INVASION = 2019, PIN_FRAME_LEVEL_AREA_POI = 2023, PIN_FRAME_LEVEL_QUEST_OFFER = 2228,
    PIN_FRAME_LEVEL_ACTIVE_QUEST = 2740, PIN_FRAME_LEVEL_SUPER_TRACKED_CONTENT = 2765, PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST = 2766,
    PIN_FRAME_LEVEL_WAYPOINT_LOCATION = 2769, PIN_FRAME_LEVEL_GROUP_MEMBER = 2770,
    RANGE = { PIN_FRAME_LEVEL_QUEST_OFFER = 7, PIN_FRAME_LEVEL_ACTIVE_QUEST = 25 } }
  function GAME_LEVELS.Valid(t, i)
    local start = GAME_LEVELS[t]
    if type(start) ~= "number" then return nil end
    return start + math.min(math.max(i or 1, 1), GAME_LEVELS.RANGE[t] or 1) - 1
  end
  env.GAME_LEVELS = GAME_LEVELS
  local function canvasLevels()
    local m = { defs = { PIN_FRAME_LEVEL_DEFAULT = { start = 2000, range = 1 } }, maxLevel = 2000 }
    function m:AddFrameLevel(t, range)
      if self.defs[t] or t == "PIN_FRAME_LEVEL_TOPMOST" then return false end
      range = range or 1
      self.defs[t] = { start = self.maxLevel + 1, range = range }
      self.maxLevel = self.maxLevel + range
      return true
    end
    function m:GetValidFrameLevel(t, i)
      local d = self.defs[t] or self.defs.PIN_FRAME_LEVEL_DEFAULT
      return d.start + math.min(math.max(i or 1, 1), d.range) - 1
    end
    return m
  end
  env.MapCanvasMixin = {
    OnLoad = function(self)
      self.dataProviders, self.__calls, self.__clickHandlers = {}, {}, {}
      self.pinFrameLevelsManager = canvasLevels()
      self:EvaluateLockReasons()
    end,
    OnShow = cleared, OnUpdate = cleared, OnMapChanged = cleared,
    OnHide = function(self) for dp in pairs(self.dataProviders) do dp:OnHide() end end,
    OnEvent = nothing,
    EvaluateLockReasons = function(self) self.BorderFrame:EnableMouse(false) end,
    SetMapID = function(self, id)
      table.insert(self.__calls, { "SetMapID", id })
      if id == self.mapID then return end
      self.mapID = id
      self.ScrollContainer.Child:SetSize(self:GetWidth(), self:GetHeight())
      self:OnMapChanged()
    end,
    GetMapID = function(self) return self.mapID end,
    GetCanvas = function(self) return self.ScrollContainer.Child end,
    OnFrameSizeChanged = function(self)
      self.ScrollContainer.Child:SetSize(self:GetWidth(), self:GetHeight())
      for dp in pairs(self.dataProviders) do dp:OnCanvasSizeChanged() end
    end,
    AddDataProvider = function(self, dp) self.dataProviders[dp] = true; dp:OnAdded(self) end,
    RemoveDataProvider = function(self, dp) dp:RemoveAllData(); self.dataProviders[dp] = nil; dp:OnRemoved(self) end,
    RefreshAll = function(self) for dp in pairs(self.dataProviders) do dp:RefreshAllData(true) end end,
    GetCanvasScale = function() return 1 end,
    GetCanvasZoomPercent = function() return 0 end,
    GetGlobalPinScale = function() return 1 end,
    GetPinFrameLevelsManager = function(self) return self.pinFrameLevelsManager end,
    AddCanvasClickHandler = function(self, fn) table.insert(self.__clickHandlers, fn) end,
    TriggerEvent = asked("TriggerEvent"), RegisterCallback = asked("RegisterCallback"), PanTo = asked("PanTo"),
    PanAndZoomTo = asked("PanAndZoomTo"), ResetZoom = asked("ResetZoom"), NavigateToParentMap = asked("NavigateToParentMap"),
    SetShouldNavigateOnClick = asked("SetShouldNavigateOnClick"), SetShouldZoomInOnClick = asked("SetShouldZoomInOnClick"),
    SetShouldPanOnClick = asked("SetShouldPanOnClick"),
    UpdatePinSuppression = nothing, UpdatePinNudging = nothing, ProcessCursorHandlers = nothing, RunDataProviderOnUpdate = nothing,
  }
  env.MapCanvasScrollControllerMixin = { OnLoad = nothing }

  ----------------------------------------------------------------------------
  -- the minimap in its cluster (415-424): the engine's Minimap.lua sizes and moves it
  ----------------------------------------------------------------------------
  env.MinimapCluster = newObj("Frame", nil, env.UIParent); env.MinimapCluster:SetSize(256, 256)
  env.MinimapCluster.__left, env.MinimapCluster.__top = 1344, 1000
  rawset(env.MinimapCluster, "ApplySystemAnchor", function(self) self.__anchored = true end)
  env.MinimapCluster.MinimapContainer = newObj("Frame", nil, env.MinimapCluster); env.MinimapCluster.MinimapContainer:SetSize(215, 226)
  env.Minimap:SetParent(env.MinimapCluster.MinimapContainer)
  env.Minimap:SetScript("OnMouseUp", function() c.gameClicks = (c.gameClicks or 0) + 1 end)
  env.Minimap:SetScript("OnMouseWheel", function() c.gameWheel = (c.gameWheel or 0) + 1 end)
  for _, key in ipairs({ "ZoomIn", "ZoomOut" }) do env.Minimap[key] = newObj("Button", nil, env.Minimap); env.Minimap[key]:Hide() end
  env.IsIndoors = function() return c.indoors or false end
  env.IsMouseButtonDown = function(b) return b == "LeftButton" and c.leftDown or false end
  -- the context menus (431-447): entries recorded in c.contextMenus, as MenuUtil's root gets them
  c.contextMenus = {}
  env.MenuUtil = { CreateContextMenu = function(owner, gen)
    local entries, root = {}, {}
    function root:CreateCheckbox(text, get, set) entries[#entries + 1] = { kind = "check", text = text, get = get, set = set } end
    function root:CreateButton(text, fn) entries[#entries + 1] = { kind = "button", text = text, set = fn } end
    function root:CreateDivider() entries[#entries + 1] = { kind = "divider" } end
    function root:CreateTitle(text) entries[#entries + 1] = { kind = "title", text = text } end
    gen(owner, root)
    entries.owner = owner
    c.contextMenus[#c.contextMenus + 1] = entries
  end }
  -- the minimap's tracking list and the game's menu hook (449-454), the professions, the CVars (455-466)
  c.tracking = { { name = "Battlemaster", filterID = 4, active = false }, { name = "Target", filterID = 16384, active = false },
                 { name = "Focus", filterID = 32768, active = false } }
  env.GetProfessions = function() local p = c.profs or {}; return p[1] and 1 or nil, p[2] and 2 or nil, nil, p[3] and 3 or nil, p[4] and 4 or nil, p[5] and 5 or nil end
  env.GetProfessionInfo = function(i) local p = (c.profs or {})[i]; if not p then return nil end return p[1], 0, p[2], 300, 0, 0, 0, 0 end
  env.C_Minimap = { GetViewRadius = function() return c.miniRadius or 233.33 end,
    GetNumTrackingTypes = function() return #c.tracking end,
    GetTrackingFilter = function(i) local t = c.tracking[i]; return t and { filterID = t.filterID } or nil end,
    GetTrackingInfo = function(i) local t = c.tracking[i]; return t and { name = t.name, active = t.active, texture = 0, type = "other" } or nil end,
    SetTracking = function(i, on) local t = c.tracking[i]; if t then t.active = on and true or false end end }
  c.menus = {}
  env.Menu = { ModifyMenu = function(tag, fn) c.menus[tag] = fn end }
  c.cvars = c.cvars or {}
  env.C_CVar = { GetCVarBool = function(name) return c.cvars[name] == "1" end }
  env.GetCVar = function(name) return c.cvars[name] end
  env.SetCVar = function(name, v)
    v = tostring(v)
    if c.cvars[name] ~= v then c.cvarChanges = c.cvarChanges or {}; table.insert(c.cvarChanges, { name, v, c.cvars.statusTextDisplay }) end
    c.cvars[name] = v
  end
  -- soft targeting (475): c.soft = { name, plate } is the object the Interact key would use
  env.C_NamePlate = { GetNamePlateForUnit = function(unit) if unit == "softinteract" and c.soft then return c.soft.plate end return nil end }

  ----------------------------------------------------------------------------
  -- CreateFrame: Pins.xml's templates (each template's child regions, as the game builds a frame from it, 480-520) and
  -- Blizzard_MapCanvas's scroll container, over Cute's CreateFrame
  ----------------------------------------------------------------------------
  local xml = io.open(HERE .. "/Cute_Quest/Pins.xml")
  xml = xml and xml:read("*a"):gsub("<!%-%-.-%-%->", "") or ""
  local templates = {}
  for attrs, body in xml:gmatch("<Frame (name=\"[^\"]+\"[^>]*)>(.-)</Frame>") do
    local t = { name = attrs:match('name="([^"]+)"'), mixin = attrs:match('mixin="([^"]+)"'), scripts = {}, regions = {}, fill = {} }
    local w, h = body:match('^%s*<Size x="(%d+)" y="(%d+)"/>')
    t.size = w and { tonumber(w), tonumber(h) } or nil
    for tag in body:gmatch("<(On%a+)") do t.scripts[tag] = true end
    for kind, key, more in body:gmatch("<(%a+) parentKey=\"(%a+)\"([^>]*)>") do
      t.regions[key] = kind
      if more:find('setAllPoints="true"', 1, true) then t.fill[key] = true end
    end
    t.layerOf = {}
    for lattrs, lbody in body:gmatch("<Layer ([^>]*)>(.-)</Layer>") do
      local level, sub = lattrs:match('level="(%u+)"'), tonumber(lattrs:match('textureSubLevel="(%-?%d+)"')) or 0
      for key in lbody:gmatch("parentKey=\"(%a+)\"") do t.layerOf[key] = { level, sub } end
    end
    templates[t.name] = t
  end
  c.templates = templates
  local cuteCreateFrame = env.CreateFrame
  env.CreateFrame = function(kind, name, parent, template)
    local f = cuteCreateFrame(kind, name, parent, template)
    local t = template and templates[template]
    if template and template:find("^QuestBank") then
      assert(t, "a template Pins.xml defines: " .. template)
      assert(not t.mixin and not next(t.scripts), "the engine's map templates carry no mixin or scripts (never the canvas's pins): " .. template)
      if t.size then f:SetSize(t.size[1], t.size[2]) end
      for key, rk in pairs(t.regions) do
        f[key] = newObj(rk, nil, f)
        if t.fill[key] then f[key]:SetAllPoints(f) end
        local lay = t.layerOf[key]
        if lay then f[key].__layer, f[key].__sub = lay[1], lay[2] end
      end
    end
    if template == "MapCanvasFrameScrollContainerTemplate" then
      env.Mixin(f, env.MapCanvasScrollControllerMixin)
      f.Child = newObj("Frame", nil, f)
      f.Child.TiledBackground = f.Child:CreateTexture(nil, "BACKGROUND")
      f.Child.TiledBackground:SetAtlas("AdventureMap_TileBg")
      f:SetScrollChild(f.Child)
      f.Child:SetPoint("TOPLEFT")
      parent.ScrollContainer = f
      f:OnLoad()
    end
    return f
  end
  -- the client's event registry, as far as chat links use it (530-534)
  env.EventRegistry = { cbs = {},
    RegisterCallback = function(self, event, fn, owner) self.cbs[event] = self.cbs[event] or {}; table.insert(self.cbs[event], { fn, owner }) end,
    TriggerEvent = function(self, event, ...) for _, cb in ipairs(self.cbs[event] or {}) do cb[1](cb[2], ...) end end }
  env.IsShiftKeyDown = function() return c.shift or false end
  env.IsControlKeyDown = function() return c.ctrl or false end
  env.IsAltKeyDown = function() return c.alt or false end
  env.IsPlayerSpell = function() return o.riding or false end
  env.IsResting = function() return c.resting or false end
  env.AuraUtil = { FindAuraByName = function(name) if c.rested and name == "Well Rested" then return name end end }
  -- the party as the engine reads it (c.party = { { name, class file, level, pos = { inst, wx, wy } }, ... }, party1..),
  -- and where you stand: o.world = { continent, wx, wy } (572-600)
  local function partyOf(unit) local i = unit and unit:match("^party(%d)$"); return i and (c.party or {})[tonumber(i)] end
  env.GetNumGroupMembers = function() return c.party and (#c.party + 1) or 0 end
  env.GetNumSubgroupMembers = function() return c.party and #c.party or 0 end
  env.IsInGroup = function() return (c.party ~= nil) or o.group or false end
  env.IsInRaid = function() return false end
  env.UnitPosition = api(function(unit)
    local pm = partyOf(unit)
    if pm then return pm.pos and pm.pos.wy, pm.pos and pm.pos.wx, 0, pm.pos and pm.pos.inst end
    if unit == "player" then local p = c.pos or { wx = o.world[2], wy = o.world[3], inst = o.world[1] }; return p.wy, p.wx, 0, p.inst or 0 end
    return nil
  end)
  c.pushed = {}
  env.QuestLogPushQuest = function(index) c.pushed[#c.pushed + 1] = index end
  env.UnitRace = api(function() return o.race, o.race end)
  env.MAX_QUESTS, env.MAX_QUESTLOG_QUESTS = 40, 40
  env.UpdateQuestAcceptLogFullDialog = function() error("the quest engine called UpdateQuestAcceptLogFullDialog: the escort prompt's Yes would be set as the addon", 2) end
  env.WaypointLocationDataProviderMixin = {}
  env.GetTitleText = function() return c.window and c.window.title or "" end
  env.GetSuggestedGroupNum = function() return 0 end
  -- the AddOns list the engine's note of other addons reads (Core.lua NoteAddons): Cute's list answers by name, and
  -- an addon not in it is missing rather than an error
  local A = env.C_AddOns
  local function known(n) for _, a in ipairs(c.addons or {}) do if a.name == n then return a end end end
  A.DoesAddOnExist = api(function(n) return known(n) ~= nil end)
  local cuteInfo = A.GetAddOnInfo
  A.GetAddOnInfo = api(function(n) if type(n) == "string" and not known(n) then return n, nil, nil, false, "MISSING", "INSECURE" end return cuteInfo(n) end)
  A.GetAddOnInterfaceVersion = api(function(n) return known(n) and 16001 or 0 end)
  A.IsAddOnLoadable = api(function(n) if not known(n) then return false, "MISSING" end return true end)
  A.DoesAddOnHaveLoadError = api(function() return false end)
  A.IsAddonVersionCheckEnabled = api(function() return true end)
  -- the quest windows (629-700): what the engine clicked, in order (c.auto); the gossip and greeting lists
  env.C_GossipInfo = {
    GetAvailableQuests = function() return c.gossipAvail or {} end,
    GetActiveQuests = function() return c.gossipActive or {} end,
    SelectAvailableQuest = function(id) c.auto[#c.auto + 1] = "SelectAvailableQuest " .. id end,
    SelectActiveQuest = function(id) c.auto[#c.auto + 1] = "SelectActiveQuest " .. id end,
  }
  c.auto = {}
  env.AcceptQuest = function() c.auto[#c.auto + 1] = "AcceptQuest " .. (c.window and c.window.id or 0) end
  env.CompleteQuest = function() c.auto[#c.auto + 1] = "CompleteQuest " .. (c.window and c.window.id or 0) end
  env.GetQuestReward = function(i) c.auto[#c.auto + 1] = "GetQuestReward " .. tostring(i) end
  env.GetNumQuestChoices = function() return (c.window and c.window.rc and #c.window.rc) or c.choices or 0 end
  env.GetNumQuestRewards = function() return (c.window and c.window.rr and #c.window.rr) or 0 end
  env.GetQuestItemLink = function(kind, i)
    local list = c.window and (kind == "choice" and c.window.rc or c.window.rr)
    local id = list and list[i]
    if not id or (c.window.unloaded and c.window.unloaded[id]) then return nil end
    return "|cff1eff00|Hitem:" .. id .. "::::::::20:::::::|h[Item " .. id .. "]|h|r"
  end
  env.GetQuestItemInfo = function() return nil end
  c.questItems = {}
  env.GetQuestLogSpecialItemInfo = function(index)
    local e = logList()[index - 1]
    local it = e and c.questItems[e[1]]
    if not it then return nil end
    return "|cffffffff|Hitem:" .. it[1] .. "::::::::1:::::|h[Quest Item]|h|r", it[2], 0, false
  end
  env.QuestInfoFrame = { rewardsFrame = { RewardButtons = {} } }
  for i = 1, 4 do
    local rb = newObj("Button", nil, env.UIParent)
    rb:SetSize(140, 40)
    env.QuestInfoFrame.rewardsFrame.RewardButtons[i] = rb
  end
  env.ChatFrame_OpenChat = function() error("the quest engine opened the chat box (ChatFrame_OpenChat)", 2) end
  env.IsQuestCompletable = function() return c.completable and true or false end
  env.QuestGetAutoAccept = function() return false end
  env.ConfirmAcceptQuest = function() error("the quest engine called ConfirmAcceptQuest: the escort prompt is the player's to answer", 2) end
  env.StaticPopup_Hide = function() error("the quest engine hid a Blizzard popup (StaticPopup_Hide)", 2) end
  env.StaticPopup_Show = function() error("the quest engine showed a Blizzard popup (StaticPopup_Show)", 2) end
  env.QuestFlagsPVP = function() return c.pvpQuest or false end
  env.GetQuestMoneyToGet = function() return c.questCost or 0 end
  env.GetNumActiveQuests = function() return #(c.greetActive or {}) end
  env.GetActiveTitle = function(i) local e = c.greetActive[i]; return e.title, e.isComplete end
  env.GetActiveQuestID = function(i) return c.greetActive[i].questID end
  env.SelectActiveQuest = function(i) c.auto[#c.auto + 1] = "SelectActiveQuest #" .. i end
  env.GetNumAvailableQuests = function() return #(c.greetAvail or {}) end
  env.GetAvailableQuestInfo = function(i) local e = c.greetAvail[i]; return e.isTrivial or false, 0, e.repeatable or false, false, e.questID end
  env.SelectAvailableQuest = function(i) c.auto[#c.auto + 1] = "SelectAvailableQuest #" .. i end
  env.GetPlayerFacing = function() return c.facing end
  -- the chat box (712-717) and the quest log's XP (729-736)
  c.chatLinks = {}
  c.chatBox = { HasFocus = function() return c.chatFocus ~= false end }
  env.ChatEdit_GetActiveWindow = function() return c.chatOpen and c.chatBox or nil end
  env.ChatEdit_InsertLink = function(link) c.chatLinks[#c.chatLinks + 1] = link; return true end
  env.GetQuestLink = function(id) if (o.log or {})[id] then return "|cffffff00|Hquest:" .. id .. ":20|h[Quest " .. id .. "]|h|r" end end
  env.GetItemInfo = function(id) return "Item " .. id, "|cffffffff|Hitem:" .. id .. "::::::::20:::::::|h[Item " .. id .. "]|h|r" end
  -- the bar's top: the catalog's XP to the next level at your level, once the engine is loaded
  env.UnitXPMax = api(function()
    local D = QBData()
    return D and D.TO_NEXT and D.TO_NEXT[o.level] or o.xpmax or 1000
  end)
  -- chat channels (the version notice's quiet channel), filters, the reward window's XP, the log's XP
  c.channels = {}
  env.JoinTemporaryChannel = function(name) c.channels[name] = true return 5, name end
  env.LeaveChannelByName = function(name) c.channels[name] = nil end
  env.GetChannelName = function(name) return c.channels[name] and 5 or 0, c.channels[name] and name or nil end
  env.ChatFrame_RemoveChannel = nothing
  env.ChatFrame_AddMessageEventFilter = function(ev, fn) c.chatFilters = c.chatFilters or {}; c.chatFilters[#c.chatFilters + 1] = { ev, fn } end
  env.GetQuestID = function() return c.window and c.window.id or 0 end
  env.GetRewardXP = function() return c.window and c.window.xp or 0 end
  env.GetQuestLogSelection = function() return c.selected or 0 end
  env.SelectQuestLogEntry = function(i) c.selected = i end
  env.GetQuestLogRewardXP = function(id) return c.logXP and c.logXP[id] or 0 end
  -- the bags (Cute's o.bags: [bag][slot] = { link, count }), the calls the engine adds to Cute's table (729-736)
  local function itemId(x) if type(x) == "number" then return x end return tonumber(tostring(x):match("item:(%d+)")) or 0 end
  local function bagItem(bag, slot) return ((o.bags or {})[bag] or {})[slot] end
  local CC = env.C_Container
  CC.GetContainerItemID = api(function(bag, slot) local it = bagItem(bag, slot); return it and itemId(it.link) or nil end)
  CC.GetContainerItemLink = api(function(bag, slot) local it = bagItem(bag, slot); return it and it.link or nil end)
  CC.GetContainerItemQuestInfo = api(function(bag, slot) local it = bagItem(bag, slot); return { questID = it and it.questID or nil, isActive = false } end)
  CC.GetItemCooldown = api(function() return c.hearthCD or 0, c.hearthCD and 3600 or 0, 1 end)
  -- the items (737-763): the icon, the load request, the cooldown, added to Cute's C_Item
  local CI = env.C_Item
  c.loadRequests = {}
  CI.GetItemIconByID = api(function(id) return id and 133328 or nil end)
  CI.RequestLoadItemDataByID = api(function(id) c.loadRequests[#c.loadRequests + 1] = id end)
  CI.GetItemCooldown = api(function() return c.hearthCD or 0, c.hearthCD and 3600 or 0, 1 end)
  -- the modern spellbook (764-787): a General line and a class line
  env.Enum = setmetatable({
    SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Corpse = 3, Object = 4 },
    TooltipDataLineType = { None = 0, Blank = 1, NestedBlock = 2, Separator = 3 },
  }, { __index = env.Enum })
  c.book = o.book or { { spellID = 6603, itemType = 1 }, { spellID = 20598, itemType = 1 }, { spellID = 635, itemType = 1 }, { spellID = 879, itemType = 2 } }
  env.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 2 end,
    GetSpellBookSkillLineInfo = function(i)
      if i == 1 then return { name = "General", itemIndexOffset = 0, numSpellBookItems = 2 } end
      if i == 2 then return { name = o.class, itemIndexOffset = 2, numSpellBookItems = #c.book - 2 } end
    end,
    GetSpellBookItemInfo = function(slot, bank)
      if bank ~= 0 and bank ~= 1 then error("bad argument #2 to 'GetSpellBookItemInfo' (Enum.SpellBookSpellBank expected)", 2) end
      return c.book[slot]
    end,
    IsSpellKnown = function(id) return (c.known or {})[id] == true end,
  }
  -- item tooltips (788-825): every post-call hook is kept in c.tipHooks; c.tipLines[id] replaces an item's lines
  c.tipHooks, c.tipLines, c.tipHooksByKind = {}, {}, {}
  env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    if kind == 0 then c.tipHooks[#c.tipHooks + 1] = fn end
    c.tipHooksByKind[kind] = c.tipHooksByKind[kind] or {}
    table.insert(c.tipHooksByKind[kind], fn)
  end }
  env.RETRIEVING_ITEM_INFO = "Retrieving item information"
  env.C_TooltipInfo = {
    GetItemByID = function(id)
      if c.tipLines[id] then return { id = id, lines = c.tipLines[id] } end
      return { id = id, lines = { { leftText = "Item " .. id }, { leftText = "Binds when picked up" }, { leftText = "Chest", rightText = "Cloth" },
        { leftText = "39 Armor" }, { leftText = "+5 Stamina" }, { leftText = "Item Level 27" }, { leftText = "Requires Level 22" } } }
    end,
  }
  env.GetLocale = function() return c.locale or "enUS" end
  -- the loot window's source and kind, the fishing flag, a vendor's wares (c.merchant = { id, ... })
  c.merchant = {}
  env.GetLootSlotType = function() return 1 end
  env.GetLootSourceInfo = function() return nil end
  env.IsFishingLoot = function() return c.fishing or false end
  env.GetMerchantNumItems = function() return #c.merchant end
  env.GetMerchantItemID = function(i) return c.merchant[i] end
  -- the quest log as the engine reads it (826-860), over Cute's shape: one header, then o.log's quests in index order
  local QL = env.C_QuestLog
  QL.IsPushableQuest = api(function(id) return (c.pushable or {})[id] == true end)
  QL.GetNumQuestLogEntries = api(function() if c.logReady == false then return 0, 0 end local l = logList(); return #l + 1, #l end)
  QL.GetMaxNumQuestsCanAccept = api(function() return 25 end)
  QL.GetInfo = api(function(i)
    if i == 1 then return { title = "Zone", isHeader = true } end
    local e = logList()[i - 1]
    if not e then return nil end
    return { title = "Quest " .. e[1], level = 20, questID = e[1], isHeader = false }
  end)
  QL.IsComplete = api(function(id) return (c.complete or {})[id] == true end)
  QL.GetLogIndexForQuestID = api(function(id) for i, e in ipairs(logList()) do if e[1] == id then return i + 1 end end end)
  QL.GetQuestObjectives = api(function(id) return (c.objectives or {})[id] or { { text = "thing", finished = false, numFulfilled = 3, numRequired = 10 } } end)
  QL.GetQuestWatchType = api(function(id) return (c.watched or {})[id] and 0 or nil end)
  QL.AddQuestWatch = function() error("the quest engine called C_QuestLog.AddQuestWatch: the tracker would redraw as the addon", 2) end
  QL.RemoveQuestWatch = function() error("the quest engine called C_QuestLog.RemoveQuestWatch: the tracker would redraw as the addon", 2) end
  QL.GetQuestTagInfo = api(function(id) if (c.elite or {})[id] then return { tagID = 1, isElite = true, tagName = "Elite" } end return nil end)
  QL.RequestLoadQuestByID = nothing
  -- the maps (861-948): Kalimdor's by id, the islands, the player's own map (o.map, Northshire's zone by default)
  local KALIMDOR = { [1411] = true, [1412] = true, [1413] = true, [1438] = true, [1439] = true, [1440] = true, [1441] = true, [1442] = true,
    [1443] = true, [1444] = true, [1445] = true, [1446] = true, [1447] = true, [1448] = true, [1449] = true, [1450] = true, [1451] = true,
    [1452] = true, [1454] = true, [1456] = true, [1457] = true, [2521] = true, [2524] = true }
  local function continentOf(id) return KALIMDOR[id] and 1414 or 1415 end
  local ISLE = { [2521] = { cont = 2991, kind = 3, minx = 1247.917, maxx = 4956.25, miny = -1331.25, maxy = 4231.25 },
                 [2524] = { cont = 2997, kind = 6, minx = -835.416, maxx = 447.916, miny = 993.75, maxy = 2918.75 } }
  local function mapName(id)
    local D = QBData()
    return ({ [947] = "Azeroth", [1414] = "Kalimdor", [1415] = "Eastern Kingdoms" })[id] or (D and D.MAPNAME and D.MAPNAME[id]) or ("Map " .. id)
  end
  local function xy(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
  env.C_Map = {
    GetBestMapForUnit = api(function() return c.playerMap or o.map end),
    CanSetUserWaypointOnMap = api(function(m) return not (c.noPins or {})[m] end),
    SetUserWaypoint = function() error("the quest engine called C_Map.SetUserWaypoint: the game's waypoint listeners would run as the addon", 2) end,
    ClearUserWaypoint = function() error("the quest engine called C_Map.ClearUserWaypoint: the game's waypoint listeners would run as the addon", 2) end,
    GetUserWaypointFromHyperlink = function(link)
      local m, x, y = tostring(link):match("worldmap:(%d+):(%d+):(%d+)")
      if not m then return nil end
      return env.UiMapPoint.CreateFromCoordinates(tonumber(m), tonumber(x) / 10000, tonumber(y) / 10000)
    end,
    GetPlayerMapPosition = api(function() if c.noPos then return nil end return xy(0.66, 0.62) end),
    GetWorldPosFromMapPos = api(function(m, v)
      if (c.instWorld or {})[m] then return 36, xy(0, 0) end
      local isle = ISLE[m]
      if isle and type(v) == "table" then
        return isle.cont, xy(isle.maxx - (v.y or 0) * (isle.maxx - isle.minx), isle.maxy - (v.x or 0) * (isle.maxy - isle.miny))
      end
      local cont = continentOf(m) == 1414 and 1 or 0
      local D = QBData()
      local mine = c.playerMap or o.map
      if m ~= mine and (o.world[1] == 0 or o.world[1] == 1) and cont ~= o.world[1] and type(v) == "table" and D and D.HUB then
        local wx, wy, found = 0, 0, false
        for _, fac in ipairs({ "A", "H" }) do
          for _, h in ipairs(D.HUB[fac]) do
            if h[7] == m then wx, wy, found = h[3] - ((v.y or 0) * 100 - h[9]) * 40, h[4] - ((v.x or 0) * 100 - h[8]) * 40, true; break end
          end
          if found then break end
        end
        return cont, xy(wx, wy)
      end
      return o.world[1], xy(o.world[2], o.world[3])
    end),
    GetMapRectOnMap = api(function() return 0.4, 0.6, 0.4, 0.6 end),
    GetMapInfo = api(function(id)
      local kind = (c.mapTypes or {})[id] or ((c.instWorld or {})[id] and 4) or (ISLE[id] and ISLE[id].kind)
        or ({ [947] = 1, [1414] = 2, [1415] = 2 })[id] or 3
      return { mapID = id, mapType = kind, parentMapID = kind == 1 and 0 or (kind == 3 and not ISLE[id]) and continentOf(id) or 947, name = mapName(id) }
    end),
    MapHasArt = api(function(id) return not (c.noArt or {})[id] end),
    GetMapChildrenInfo = api(function(id)
      local out = {}
      if id == 947 then
        out = { { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947 }, { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 } }
      elseif id == 1414 or id == 1415 then
        local D = QBData()
        for m, name in pairs(D and D.MAPNAME or {}) do
          if continentOf(m) == id then out[#out + 1] = { mapID = m, name = name, mapType = 3, parentMapID = id } end
        end
      end
      return out
    end),
    GetMapLevels = api(function(id)
      local l = (c.mapLevels or {})[id]
      if l then return l[1], l[2], 0, 0 end
      if env.C_Map.GetMapInfo(id).mapType == 3 then return 10, 20, 0, 0 end
      return 0, 0, 0, 0
    end),
    GetMapPosFromWorldPos = api(function(cont, pos, id)
      local r = (c.mapRects or {})[id]
      if not r or r.c ~= cont then return nil end
      return id, env.CreateVector2D((r.y - pos.y) / r.size, (r.x - pos.x) / r.size)
    end),
  }
  -- an atlas at the size the game draws it (949-953)
  env.C_Texture = { GetAtlasInfo = function(name)
    if (c.noAtlas or {})[name] then return nil end
    local px = type(name) == "string" and name:lower():find("^taxinode") and 21 or 32
    return { file = 1, width = px, height = px }
  end }
  -- flight points (960-1005): c.taxiKnown = { [TaxiNodes id] = true } the ones found (nil: the client answers nothing)
  env.C_TaxiMap = {
    ShouldMapShowTaxiNodes = function(m) return c.taxiKnown ~= nil and not (c.taxiNoContinent and (m == 1414 or m == 1415)) end,
    GetTaxiNodesForMap = function(m)
      if c.taxiKnown == nil or (c.taxiNoContinent and (m == 1414 or m == 1415)) then return {} end
      local D = QBData()
      local out = {}
      for _, h in ipairs(D and D.HUB and D.HUB[o.faction == "Horde" and "H" or "A"] or {}) do
        if h[6] > 0 and (h[7] == m or (m == 1415 and h[2] == 0) or (m == 1414 and h[2] == 1)) then
          out[#out + 1] = { nodeID = h[6], name = h[1], faction = 0, isUndiscovered = not c.taxiKnown[h[6]], position = env.CreateVector2D(h[8] / 100, h[9] / 100) }
        end
      end
      return out
    end,
    GetAllTaxiNodes = function() return c.taxiOpen and c.taxiOpen.nodes or {} end,
  }
  local function taxiSlot(i) for _, n in ipairs(c.taxiOpen and c.taxiOpen.nodes or {}) do if n.slotIndex == i then return n end end end
  env.GetTaxiMapID = function() return c.taxiOpen and c.taxiOpen.map end
  env.NumTaxiNodes = function() return c.taxiOpen and #c.taxiOpen.nodes or 0 end
  env.TaxiNodeName = function(i) local n = taxiSlot(i); return n and n.name or "INVALID" end
  env.TaxiNodeGetType = function(i) local n = taxiSlot(i); return n and ({ [0] = "CURRENT", [1] = "REACHABLE", [2] = "UNREACHABLE" })[n.state] or "NONE" end
  env.TakeTaxiNode = function(slot) c.took = slot end
  env.UnitIsDeadOrGhost = function() return c.ghost or o.ghost or false end
  -- where your corpse lies (991-999)
  env.C_DeathInfo = { GetCorpseMapPosition = function(m)
    local k = c.corpse
    if not (k and c.ghost and k[1] == m) then return nil end
    return xy(k[2], k[3])
  end }
  env.ERR_NEWTAXIPATH = "New flight path discovered!"
  env.GetUnitSpeed = function() local sp = c.speed or { 0, 7 }; return sp[1], sp[2], 7, 4.72 end
  env.IsMounted = function() return c.mounted or false end
  env.C_Spell.GetSpellTexture = api(function(id) return id == 556 and 136010 or 134400 end)
  env.C_Spell.GetSpellCooldown = api(function() return { startTime = c.recallCD or 0, duration = c.recallCD and 900 or 0, isEnabled = true, modRate = 1 } end)
  -- chat people read (1041-1052): one line of at most 255 bytes, no escape codes, to a channel you are in
  c.said, c.chatErrors = {}, {}
  env.SendChatMessage = function(msg, chatType)
    local function bad(why) c.chatErrors[#c.chatErrors + 1] = why; error(why) end
    if not (type(msg) == "string" and #msg > 0 and #msg <= 255) then bad("chat message empty or over 255 bytes") end
    if msg:find("[\r\n]") then bad("chat message with a line break") end
    if msg:find("|") then bad("chat message with an escape code") end
    if not (chatType == "PARTY" or chatType == "RAID" or chatType == "GUILD" or chatType == "INSTANCE_CHAT") then bad("posted to " .. tostring(chatType)) end
    c.said[#c.said + 1] = { msg, chatType }
  end
  -- the engine's own addon channel (its prefix, to the party): kept apart from Cute's, which the guild channel checks
  local CH = env.C_ChatInfo
  local cuteRegister, cuteSend = CH.RegisterAddonMessagePrefix, CH.SendAddonMessage
  c.outbox = {}
  CH.RegisterAddonMessagePrefix = function(p) if p == "Cute" then return cuteRegister(p) end return true end
  CH.SendAddonMessage = function(prefix, msg, channel, target)
    if prefix == "Cute" then return cuteSend(prefix, msg, channel, target) end
    assert(#msg <= 255, "addon message too long: " .. #msg)
    if (channel == "PARTY" or channel == "RAID") and not (c.party or o.group) then return 5 end
    c.outbox[#c.outbox + 1] = { prefix, msg, channel, target }
    return 0
  end
  -- the world map (1055-1140): the engine's layers are data providers the map tells of a refresh, a new map and a new
  -- scale; map.id the map on show, map.shown whether it is open
  local map = { shown = false, providers = {}, id = o.map, scale = 1, zoom = 0, WorldMapTrackingPinButton = { isActive = false } }
  local canvas = newObj("Frame"); canvas:SetSize(1002, 668)
  env.WorldMapFrame = {
    AddDataProvider = function(_, p) p.owningMap = map; map.providers[#map.providers + 1] = p end,
    IsShown = function() return map.shown end,
    IsVisible = function() return map.shown end,
    GetCanvas = function() return canvas end,
    GetMapID = function() return map.id end,
    HookScript = function(_, script) error("the quest engine hooked the world map's " .. tostring(script), 2) end,
  }
  function map:GetMapID() return self.id end
  function map:GetCanvas() return canvas end
  function map:GetCanvasScale() return self.scale end
  function map:GetCanvasZoomPercent() return self.zoom end
  function map:GetGlobalPinScale() return 1 end
  map.levels = GAME_LEVELS
  local levels = { GetValidFrameLevel = function(_, t, i) return GAME_LEVELS.Valid(t, i) or 1 end }
  function map:GetPinFrameLevelsManager() return levels end
  function map:RefreshAll() for _, p in ipairs(self.providers) do p:RefreshAllData() end end
  function map:Open() self.shown = true; self:RefreshAll() end
  function map:Close()
    self.shown = false
    for _, p in ipairs(self.providers) do if p.OnHide then p:OnHide() end end
  end
  function map:SetMapID(id)
    if id == self.id then return end
    self.id = id
    for _, p in ipairs(self.providers) do p:OnMapChanged() end
  end
  function map:Zoom(scale, zoom)
    self.scale, self.zoom = scale, zoom
    for _, p in ipairs(self.providers) do p:OnCanvasScaleChanged() end
  end
  c.panelCalls = {}
  env.MapUtil = { GetDisplayableMapForPlayer = function() return c.playerMap or o.map end }
  env.OpenWorldMap = function(mapID)
    c.panelCalls[#c.panelCalls + 1] = "open"
    if c.combat then c.panelBlocked = true; return end
    if not map.shown then map.id = env.MapUtil.GetDisplayableMapForPlayer(); map:Open() end
    if mapID then map:SetMapID(mapID) end
  end
  env.ToggleWorldMap = function() if map.shown then env.HideUIPanel(env.WorldMapFrame) else env.OpenWorldMap() end end
  env.HideUIPanel = function(f)
    c.panelCalls[#c.panelCalls + 1] = "hide"
    if c.combat then c.panelBlocked = true; return end
    if f == env.WorldMapFrame and map.shown then map:Close() end
  end
  for _, name in ipairs({ "AcquirePin", "RemoveAllPinsByTemplate", "RemovePin", "EnumeratePinsByTemplate", "SetPinPosition", "ApplyPinPosition" }) do
    map[name] = function() error("the quest engine called the map canvas's " .. name .. ": that writes the addon's taint into the map", 2) end
  end
  map.ScrollContainer = { MarkCanvasDirty = function() error("the quest engine wrote into the map's scroll container", 2) end }
  c.map = map
end
