local _, addon = ...
if type(addon) ~= "table" then return end

BINDING_HEADER_VIGNETTERADAR = "Magpie"
BINDING_NAME_VIGNETTERADAR_RAISE_LAUNCHER = "Hold to Raise Launcher"
BINDING_NAME_VIGNETTERADAR_PEEK_RADAR = "Hold to Peek at Full Radar"
BINDING_NAME_VIGNETTERADAR_HOLD_LENS = "Hold to Filter Radar"
BINDING_NAME_VIGNETTERADAR_FOCUS_NEXT = "World Focus: Next Point"
BINDING_NAME_VIGNETTERADAR_FOCUS_PREVIOUS = "World Focus: Previous Point"
BINDING_NAME_VIGNETTERADAR_TOGGLE_RADAR = "Toggle Radar"
BINDING_NAME_VIGNETTERADAR_TOGGLE_SETTINGS = "Toggle Radar Settings"
BINDING_NAME_VIGNETTERADAR_TOGGLE_BEARING = "Toggle Bearing Bar"
BINDING_NAME_VIGNETTERADAR_TOGGLE_CONSTELLATION = "Toggle Constellation HUD"
BINDING_NAME_VIGNETTERADAR_TOGGLE_ROUTE = "Auto Route: Start, Pause, or Resume"
BINDING_NAME_VIGNETTERADAR_PIN_ZYGOR = "Pin Zygor's Current Step"
BINDING_NAME_VIGNETTERADAR_ROUTE_RARE = "Auto Route: Nearest Rare"
BINDING_NAME_VIGNETTERADAR_ROUTE_TREASURE = "Auto Route: Nearest Treasure"
BINDING_NAME_VIGNETTERADAR_ROUTE_QUEST = "Auto Route: Nearest Quest Point"
BINDING_NAME_VIGNETTERADAR_ROUTE_CLOSEST = "Auto Route: Closest Point"
BINDING_NAME_VIGNETTERADAR_QUEST_STEP_PREVIOUS = "Quest Route: Previous Step"
BINDING_NAME_VIGNETTERADAR_QUEST_STEP_NEXT = "Quest Route: Next Step"
BINDING_NAME_VIGNETTERADAR_CLEAR_FOCUS = "World Focus: Clear Waypoint"
_G["BINDING_NAME_CLICK VignetteRadarQuestItemButton:LeftButton"] = "Use Quest Item"

addon.VignetteRadarRanges = { 10, 25, 50, 100, 150, 300, 450, 600, 1200, 2400, 4800 }
addon.VignetteRadarLayouts = { "classic", "squat", "compact" }

local MIGRATED_KEYS = {
    "vignetteRadarEnabled",
    "vignetteRadarHideWhenEmpty",
    "vignetteRadarRange",
    "vignetteRadarLauncherVisible",
    "vignetteRadarPosition",
    "vignetteRadarLauncherPosition",
    "vignetteRadarCategories",
    "vignetteRadarHighlight",
}

local TRAIL_STYLES = {
    { id="dashes", label="Dashes", spacing=12, segments={{-3.5,0,3.5,0,2.5}} },
    { id="ticks", label="Ticks", spacing=14, segments={{0,-3.5,0,3.5,2}} },
    { id="dots", label="Dots", spacing=9, dot=5 },
    { id="squares", label="Squares", spacing=12, square=5 },
    { id="hollow-squares", label="Hollow squares", spacing=15,
        segments={{-3,-3,3,-3,1.5},{3,-3,3,3,1.5},{3,3,-3,3,1.5},{-3,3,-3,-3,1.5}} },
    { id="long", label="Long dashes", spacing=17, segments={{-5.5,0,5.5,0,2}} },
    { id="slashes", label="Slashes", spacing=13, segments={{-3,-3,3,3,2}} },
    { id="chevrons", label="Chevrons", spacing=15,
        segments={{-3,-3,2,0,2},{2,0,-3,3,2}} },
    { id="crosses", label="Crosses", spacing=16,
        segments={{-3,-3,3,3,1.8},{-3,3,3,-3,1.8}} },
    { id="diamonds", label="Diamonds", spacing=18,
        segments={{-4,0,0,3,1.6},{0,3,4,0,1.6},{4,0,0,-3,1.6},{0,-3,-4,0,1.6}} },
    { id="beads", label="Beads", spacing=12, dot=6, alternating=true },
    { id="pulses", label="Pulses", spacing=14, segments={{-4,0,4,0,2.5}}, alternating=true },
}
local TRAIL_STYLE_KEYS = {}
for _, definition in ipairs(TRAIL_STYLES) do TRAIL_STYLE_KEYS[definition.id] = definition end
addon.VignetteRadarTrailStyles = TRAIL_STYLES
addon.VignetteRadarTrailStyleByID = TRAIL_STYLE_KEYS
local TRAIL_SETTING_VALUES = {
    vignetteRadarTrailSpacing = { .5, .65, .75, 1, 1.25, 1.5, 2 },
    vignetteRadarTrailSpeed = { 0, .25, .5, .75, 1, 1.25, 1.5, 2, 3, 4 },
    vignetteRadarTrailSize = { .1, .25, .5, .75, 1, 1.25, 1.5, 2 },
}
addon.VignetteRadarTrailSettingValues = TRAIL_SETTING_VALUES

-- Trails modes: Follow is the breadcrumb trail behind you, Lead is a trail
-- drawn ahead to the current target. vignetteRadarTrailMode is the setting;
-- vignetteRadarBreadcrumbs stays as the Follow half so older code and saved
-- profiles keep working. Writers of either key are reconciled in Validate.
local TrailMode = { order = { "off", "follow", "lead", "both" },
    valid = { off = true, follow = true, lead = true, both = true } }
function TrailMode.Follows(mode) return mode == "follow" or mode == "both" end
function TrailMode.Leads(mode) return mode == "lead" or mode == "both" end
function TrailMode.Compose(follow, lead)
    if follow then return lead and "both" or "follow" end
    return lead and "lead" or "off"
end
addon.VignetteRadarTrailMode = TrailMode
local function TrailSetting(db, key, default)
    for _, value in ipairs(TRAIL_SETTING_VALUES[key]) do
        if db[key] == value then return end
    end
    db[key] = default
end

-- On/off switches for the in-world marker, quest super-tracking and the
-- area quest filter.
local FEATURE_DEFAULTS = {
    -- Quest Tracker tray curves around a round radar (UI/QuestTracker.lua).
    vignetteRadarQuestTrackerRound = true,
    vignetteRadarQuestSuperTrack = true,
    vignetteRadarWorldMarker = true,
    vignetteRadarWorldMarkerBeam = true,
    vignetteRadarWorldMarkerText = true,
    vignetteRadarWorldMarkerCombatFade = true,
    vignetteRadarAreaQuests = true,
    vignetteRadarRouteNextStep = true,
    vignetteRadarCompartment = true,
    vignetteRadarLeadNextStops = true,
    vignetteRadarDeclutter = true,
    vignetteRadarDeclutterLiveOnly = false,
    vignetteRadarLiveRareFollow = true,
    vignetteRadarAlertSmart = true,
    vignetteRadarAlertFlash = true,
    vignetteRadarWorthTooltip = true,
    vignetteRadarShareButton = true,
    vignetteRadarShareAddon = true,
    vignetteRadarPackRemember = true,
    vignetteRadarPackTakeover = false,
    vignetteRadarWayCommand = true,
    vignetteRadarTomTomStandIn = true,
    vignetteRadarNameplateMarker = true,
    vignetteRadarAreaPOIs = true,
    vignetteRadarAreaPOIRoute = true,
    vignetteRadarHorizonRibbon = false,
    vignetteRadarHorizonRibbonRares = true,
    vignetteRadarRareSpawnLearning = true,
    vignetteRadarRareSpawnNotes = true,
    vignetteRadarLiveEta = true,
    vignetteRadarQuestItemButton = true,
    vignetteRadarMinimapUnderlay = false,
    vignetteRadarMinimapUnderlayHideChrome = true,
    vignetteRadarMinimapUnderlayShape = "square",
    vignetteRadarMinimapUnderlayIcons = "radar",
    vignetteRadarButtonTray = true,
    vignetteRadarButtonTrayMinimap = true,
    vignetteRadarButtonTraySet = "radar",
    vignetteRadarButtonTrayScan = true,
    vignetteRadarButtonTrayLocked = false,
    -- Data track: collection tracking bridge, respawn estimate, spawn heatmap.
    vignetteRadarCollectionTracking = true,
    vignetteRadarCollectionTrackingRoute = true,
    vignetteRadarRespawnEstimate = true,
    vignetteRadarSpawnHeatmap = false,
    vignetteRadarSpawnHeatmapWorldMap = true,
    -- Route/world track: map route overlay, shared sightings in.
    vignetteRadarMapRoute = true,
    vignetteRadarMapRouteSweep = true,
    vignetteRadarSharedSightings = true,
    vignetteRadarSharedSightingsChat = true,
}
-- Allowed values of the FEATURE_DEFAULTS entries that are choices, not
-- switches (they match the choices in Core/Schema.lua).
local FEATURE_CHOICES = {
    vignetteRadarMinimapUnderlayShape = { square = true, circle = true },
    vignetteRadarMinimapUnderlayIcons = { radar = true, split = true, minimap = true },
    vignetteRadarButtonTraySet = { radar = true, minimap = true },
}

local function CopySavedValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do
        if type(key) == "string" and (type(item) == "boolean" or type(item) == "number" or type(item) == "string") then
            copy[key] = item
        end
    end
    return copy
end

-- Guide Panel (UI/GuidePanel.lua) ------------------------------------------
-- One panel replaced the route card + Upcoming Stops, the Next 3 Stops
-- Strip, the Worth-It Card and the Zone Briefing. Block ids and their order
-- live in GuideBlocks; header is always on and always first.
local GuideBlocks = { order = { "step", "facts", "stops", "compass", "briefing", "actions", "notice" } }
-- Blocks a new or older profile gets switched off (the optional compass strip).
GuideBlocks.offByDefault = { compass = true }
GuideBlocks.known = {}
for _, id in ipairs(GuideBlocks.order) do GuideBlocks.known[id] = true end
addon.VignetteRadarGuideBlocks = GuideBlocks

local function OldToggle(db, key, default)
    if type(db[key]) == "boolean" then return db[key] end
    return default
end

-- One shot (vignetteRadarGuideMigrated): any old panel on turns the Guide
-- Panel on; the old toggles become blocks; the route card's spot (or the
-- strip's) becomes the panel's. Old keys stay in the DB for one release.
function GuideBlocks.Migrate(db)
    if db.vignetteRadarGuideMigrated == true then return end
    local arrow = OldToggle(db, "vignetteRadarRouteArrow", true)
    local strip = OldToggle(db, "vignetteRadarStopStrip", true)
    local worth = OldToggle(db, "vignetteRadarWorthCard", true)
    local briefing = OldToggle(db, "vignetteRadarZoneBriefing", true)
    local upcoming = OldToggle(db, "vignetteRadarRouteHorizonExpanded", false)
    if type(db.vignetteRadarGuidePanel) ~= "boolean" then
        db.vignetteRadarGuidePanel = arrow or strip or worth or briefing
    end
    if type(db.vignetteRadarGuideBlocks) ~= "table" then
        db.vignetteRadarGuideBlocks = { step = true, facts = worth, stops = strip or upcoming,
            briefing = briefing, actions = true, notice = true }
    end
    if db.vignetteRadarGuideDensity == nil then
        db.vignetteRadarGuideDensity = strip and not upcoming and not worth and "compact" or "expanded"
    end
    local layout = type(db.vignetteRadarPanelLayout) == "table" and db.vignetteRadarPanelLayout or {}
    db.vignetteRadarPanelLayout = layout
    if type(layout.guide) ~= "table" then
        local card = type(layout.routeCard) == "table" and layout.routeCard or nil
        local spot = db.vignetteRadarRouteArrowPosition
        local x, y = type(spot) == "table" and tonumber(spot.x), type(spot) == "table" and tonumber(spot.y)
        if x and y and spot.layout ~= 2 then x, y = x - 51, y - 10 end
        if arrow and (card or (x and y)) then
            -- The route card floated by default and kept its own spot.
            layout.guide = { detached = not (card and card.detached == false),
                locked = card and card.locked == true or nil, x = x or nil, y = y or nil }
        elseif type(layout.stopStrip) == "table" then
            local old = layout.stopStrip
            layout.guide = { detached = old.detached, locked = old.locked, x = old.x, y = old.y }
        end
    end
    layout.routeCard, layout.stopStrip, layout.worthCard, layout.zoneBriefing = nil, nil, nil, nil
    db.vignetteRadarRouteArrowPosition = nil
    db.vignetteRadarGuideMigrated = true
    if addon.Trace then
        local blocks, guide = db.vignetteRadarGuideBlocks, layout.guide
        addon.Trace.Log("guide", "migrated: panel %s, %s, facts %s, stops %s, briefing %s, spot %s",
            db.vignetteRadarGuidePanel, db.vignetteRadarGuideDensity, blocks.facts, blocks.stops, blocks.briefing,
            type(guide) == "table" and ((guide.detached and "free " or "docked ") .. tostring(guide.x) .. ","
                .. tostring(guide.y)) or "default")
    end
end

function GuideBlocks.Validate(db)
    if type(db.vignetteRadarGuidePanel) ~= "boolean" then db.vignetteRadarGuidePanel = true end
    if db.vignetteRadarGuideDensity ~= "compact" and db.vignetteRadarGuideDensity ~= "expanded" then
        db.vignetteRadarGuideDensity = "expanded"
    end
    local stops = db.vignetteRadarGuideStops
    if type(stops) ~= "number" or stops ~= math.floor(stops) or stops < 1 or stops > 5 then
        db.vignetteRadarGuideStops = 3
    end
    if db.vignetteRadarGuideWidth ~= 200 and db.vignetteRadarGuideWidth ~= 260
        and db.vignetteRadarGuideWidth ~= 320 then db.vignetteRadarGuideWidth = 260 end
    if db.vignetteRadarGuideBriefingSeconds ~= 10 and db.vignetteRadarGuideBriefingSeconds ~= 20
        and db.vignetteRadarGuideBriefingSeconds ~= 40 then db.vignetteRadarGuideBriefingSeconds = 20 end
    local blocks = type(db.vignetteRadarGuideBlocks) == "table" and db.vignetteRadarGuideBlocks or {}
    for key in pairs(blocks) do
        if not GuideBlocks.known[key] then blocks[key] = nil end
    end
    for _, id in ipairs(GuideBlocks.order) do
        if type(blocks[id]) ~= "boolean" then blocks[id] = not GuideBlocks.offByDefault[id] end
    end
    db.vignetteRadarGuideBlocks = blocks
    -- The order: every known block once. A block added since the order was
    -- saved goes in after the block it follows by default; anything broken
    -- resets the order.
    local order, seen, valid = db.vignetteRadarGuideOrder, {}, type(db.vignetteRadarGuideOrder) == "table"
    for _, id in ipairs(valid and order or {}) do
        if not GuideBlocks.known[id] or seen[id] then valid = false end
        seen[id] = true
    end
    if valid and #order < #GuideBlocks.order then
        for index, id in ipairs(GuideBlocks.order) do
            if not seen[id] then
                local after = index > 1 and GuideBlocks.order[index - 1]
                local at = #order + 1
                for position, existing in ipairs(order) do
                    if existing == after then at = position + 1 end
                end
                table.insert(order, at, id)
                seen[id] = true
                if addon.Trace then addon.Trace.Log("guide", "order: added %s at %d", id, at) end
            end
        end
    end
    if not valid or #order ~= #GuideBlocks.order then
        if addon.Trace and order ~= nil then addon.Trace.Log("guide", "order: reset to default") end
        order = {}
        for index, id in ipairs(GuideBlocks.order) do order[index] = id end
        db.vignetteRadarGuideOrder = order
    end
end

-- The table that last passed full validation. Keyed on identity so the
-- SavedVariables swap after this file loads forces one fresh validation.
local validated

function addon.ValidateSettings()
    if type(VignetteRadarDB) ~= "table" then
        VignetteRadarDB = {}
        -- The old addon is optional; when it is installed, preserve the user's
        -- radar choices and draggable positions without sharing its DB forever.
        if type(WaffleHouseDB) == "table" then
            for _, key in ipairs(MIGRATED_KEYS) do
                if WaffleHouseDB[key] ~= nil then
                    VignetteRadarDB[key] = CopySavedValue(WaffleHouseDB[key])
                end
            end
        end
    end

    local db = VignetteRadarDB
    -- Settings window mode (Core/Schema.lua level tags). A fresh install
    -- (empty table) opens in Simple; saved settings from before the switch
    -- existed open in Advanced, so no row the player already used disappears.
    if db.vignetteRadarConfigMode ~= "simple" and db.vignetteRadarConfigMode ~= "advanced" then
        db.vignetteRadarConfigMode = next(db) == nil and "simple" or "advanced"
    end
    GuideBlocks.Migrate(db)
    GuideBlocks.Validate(db)
    if type(db.vignetteRadarEnabled) ~= "boolean" then db.vignetteRadarEnabled = true end
    if type(db.vignetteRadarHideWhenEmpty) ~= "boolean" then db.vignetteRadarHideWhenEmpty = true end
    if type(db.vignetteRadarLauncherVisible) ~= "boolean" then db.vignetteRadarLauncherVisible = true end
    -- dev.67 enabled the screen-space bar automatically. Return it to an
    -- explicit opt-in once, then preserve every later on/off choice.
    if db.vignetteRadarBearingBarDefaulted ~= true then
        db.vignetteRadarBeaconsEnabled = false
        db.vignetteRadarBearingBarDefaulted = true
    end
    if type(db.vignetteRadarBeaconsEnabled) ~= "boolean" then db.vignetteRadarBeaconsEnabled = false end
    if type(db.vignetteRadarConstellationEnabled) ~= "boolean" then db.vignetteRadarConstellationEnabled = false end
    if db.vignetteRadarConstellationSourceMode ~= "live" and db.vignetteRadarConstellationSourceMode ~= "pack"
        and db.vignetteRadarConstellationSourceMode ~= "mixed" then
        db.vignetteRadarConstellationSourceMode = "mixed"
    end
    if type(db.vignetteRadarConstellationGuidance) ~= "boolean" then db.vignetteRadarConstellationGuidance = true end
    if type(db.vignetteRadarConstellationReducedMotion) ~= "boolean" then db.vignetteRadarConstellationReducedMotion = false end
    if db.vignetteRadarConstellationInteractModifier ~= "ctrl"
        and db.vignetteRadarConstellationInteractModifier ~= "shift"
        and db.vignetteRadarConstellationInteractModifier ~= "alt"
        and db.vignetteRadarConstellationInteractModifier ~= "off" then
        db.vignetteRadarConstellationInteractModifier = "ctrl"
    end
    if type(db.vignetteRadarConstellationCenterArrow) ~= "boolean" then db.vignetteRadarConstellationCenterArrow = true end
    if type(db.vignetteRadarConstellationHeadingLine) ~= "boolean" then db.vignetteRadarConstellationHeadingLine = true end
    if type(db.vignetteRadarConstellationShowRings) ~= "boolean" then db.vignetteRadarConstellationShowRings = true end
    if type(db.vignetteRadarConstellationShowSphere) ~= "boolean" then db.vignetteRadarConstellationShowSphere = true end
    if type(db.vignetteRadarConstellationShowBases) ~= "boolean" then db.vignetteRadarConstellationShowBases = true end
    if type(db.vignetteRadarConstellationShowReadout) ~= "boolean" then db.vignetteRadarConstellationShowReadout = true end
    local iconSize = db.vignetteRadarConstellationIconSize
    if type(iconSize) ~= "number" or iconSize ~= iconSize
        or iconSize == math.huge or iconSize == -math.huge then iconSize = 32 end
    db.vignetteRadarConstellationIconSize = math.max(24, math.min(36, iconSize))
    local centerOpacity = db.vignetteRadarConstellationCenterOpacity
    if type(centerOpacity) ~= "number" or centerOpacity ~= centerOpacity
        or centerOpacity == math.huge or centerOpacity == -math.huge then centerOpacity = .72 end
    db.vignetteRadarConstellationCenterOpacity = math.max(.2, math.min(1, centerOpacity))
    local headingLength = db.vignetteRadarConstellationHeadingLength
    if type(headingLength) ~= "number" or headingLength ~= headingLength
        or headingLength == math.huge or headingLength == -math.huge then headingLength = .24 end
    db.vignetteRadarConstellationHeadingLength = math.max(.10, math.min(.50, headingLength))
    local constellationSize = db.vignetteRadarConstellationSize
    if type(constellationSize) ~= "number" or constellationSize ~= constellationSize
        or constellationSize == math.huge or constellationSize == -math.huge then constellationSize = 520 end
    db.vignetteRadarConstellationSize = math.max(360, math.min(800, constellationSize))
    local constellationOpacity = db.vignetteRadarConstellationOpacity
    if type(constellationOpacity) ~= "number" or constellationOpacity ~= constellationOpacity
        or constellationOpacity == math.huge or constellationOpacity == -math.huge then constellationOpacity = .75 end
    db.vignetteRadarConstellationOpacity = math.max(.2, math.min(1, constellationOpacity))
    for _, key in ipairs({ "vignetteRadarConstellationRingOpacity",
        "vignetteRadarConstellationSphereOpacity", "vignetteRadarConstellationTrailOpacity" }) do
        local value = db[key]
        if type(value) ~= "number" or value ~= value
            or value == math.huge or value == -math.huge then value = db.vignetteRadarConstellationOpacity end
        db[key] = math.max(.1, math.min(1, value))
    end
    local constellationOffset = db.vignetteRadarConstellationOffsetY
    if type(constellationOffset) ~= "number" or constellationOffset ~= constellationOffset
        or constellationOffset == math.huge or constellationOffset == -math.huge then constellationOffset = -.05 end
    db.vignetteRadarConstellationOffsetY = math.max(-.2, math.min(.2, constellationOffset))
    if db.vignetteRadarConstellationMaxPoints ~= 12 and db.vignetteRadarConstellationMaxPoints ~= 24
        and db.vignetteRadarConstellationMaxPoints ~= 36 then db.vignetteRadarConstellationMaxPoints = 24 end
    if db.vignetteRadarPerformance ~= "standard" and db.vignetteRadarPerformance ~= "balanced"
        and db.vignetteRadarPerformance ~= "low" then db.vignetteRadarPerformance = "standard" end
    if type(db.vignetteRadarWorldFocusEnabled) ~= "boolean" then db.vignetteRadarWorldFocusEnabled = true end
    if type(db.vignetteRadarWorldFocusAutoAdvance) ~= "boolean" then db.vignetteRadarWorldFocusAutoAdvance = false end
    if type(db.vignetteRadarWorldFocusRoutes) ~= "boolean" then db.vignetteRadarWorldFocusRoutes = true end
    if type(db.vignetteRadarWorldFocusSavedNotes) ~= "boolean" then db.vignetteRadarWorldFocusSavedNotes = false end
    if type(db.vignetteRadarWorldFocusZygor) ~= "boolean" then db.vignetteRadarWorldFocusZygor = false end
    if type(db.vignetteRadarFollowZygor) ~= "boolean" then db.vignetteRadarFollowZygor = false end
    if db.vignetteRadarZygorMode ~= "objective" and db.vignetteRadarZygorMode ~= "travel" then
        db.vignetteRadarZygorMode = "objective"
    end
    if type(db.vignetteRadarAutoRouteOnSelect) ~= "boolean" then db.vignetteRadarAutoRouteOnSelect = false end
    if type(db.vignetteRadarAutoRouteRestore) ~= "boolean" then db.vignetteRadarAutoRouteRestore = true end
    if db.vignetteRadarAutoRouteLastKind ~= "closest" and db.vignetteRadarAutoRouteLastKind ~= "quest"
        and db.vignetteRadarAutoRouteLastKind ~= "rare" and db.vignetteRadarAutoRouteLastKind ~= "treasure" then
        db.vignetteRadarAutoRouteLastKind = nil
    end
    if type(db.vignetteRadarAutoRouteWasActive) ~= "boolean" then db.vignetteRadarAutoRouteWasActive = false end
    -- World Focus's last single pick, restored after /reload (Routes/WorldFocus.lua
    -- writes it). Flat fields only; a malformed record is dropped.
    local lastFocus = db.vignetteRadarLastFocus
    if lastFocus ~= nil then
        local valid = type(lastFocus) == "table" and type(lastFocus.kind) == "string" and lastFocus.kind ~= ""
            and type(lastFocus.mapID) == "number" and lastFocus.mapID > 0
            and type(lastFocus.mapX) == "number" and lastFocus.mapX >= 0 and lastFocus.mapX <= 1
            and type(lastFocus.mapY) == "number" and lastFocus.mapY >= 0 and lastFocus.mapY <= 1
            and (lastFocus.kind ~= "quest" or type(lastFocus.questID) == "number" and lastFocus.questID > 0)
            and (lastFocus.kind == "guide"
                or type(lastFocus.worldX) == "number" and type(lastFocus.worldY) == "number")
        if valid then
            for field, value in pairs(lastFocus) do
                local valueType = type(value)
                if type(field) ~= "string"
                    or (valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean")
                    or (valueType == "number" and (value ~= value or value == math.huge or value == -math.huge)) then
                    valid = false
                    break
                end
            end
        end
        if not valid then db.vignetteRadarLastFocus = nil end
    end
    if type(db.vignetteRadarActiveCue) ~= "boolean" then db.vignetteRadarActiveCue = true end
    if type(db.vignetteRadarSourceBadges) ~= "boolean" then db.vignetteRadarSourceBadges = true end
    if type(db.vignetteRadarAutoRouteMapNotes) ~= "boolean" then db.vignetteRadarAutoRouteMapNotes = false end
    if type(db.vignetteRadarAutoRouteNearbyZones) ~= "boolean" then db.vignetteRadarAutoRouteNearbyZones = true end
    if type(db.vignetteRadarAutoRouteQuestStarts) ~= "boolean" then db.vignetteRadarAutoRouteQuestStarts = true end
    if type(db.vignetteRadarAutoRouteQuestNearest) ~= "boolean" then db.vignetteRadarAutoRouteQuestNearest = true end
    -- "Move On" replaced the old per-objective switch; keep a saved choice.
    if db.vignetteRadarAutoRouteQuestMoveOn ~= "last" and db.vignetteRadarAutoRouteQuestMoveOn ~= "each" then
        db.vignetteRadarAutoRouteQuestMoveOn = db.vignetteRadarAutoRouteQuestPerObjective == true and "each" or "last"
    end
    db.vignetteRadarAutoRouteQuestPerObjective = nil
    if type(db.vignetteRadarWorldQuestPriority) ~= "boolean" then db.vignetteRadarWorldQuestPriority = true end
    if db.vignetteRadarWorldQuestPriorityRange ~= 150
        and db.vignetteRadarWorldQuestPriorityRange ~= 300
        and db.vignetteRadarWorldQuestPriorityRange ~= 600 then
        db.vignetteRadarWorldQuestPriorityRange = 300
    end
    if type(db.vignetteRadarLearnedQuestHints) ~= "boolean" then db.vignetteRadarLearnedQuestHints = true end
    if type(db.vignetteRadarWorldFocusThemedWaypoint) ~= "boolean" then db.vignetteRadarWorldFocusThemedWaypoint = true end
    if type(db.vignetteRadarWorldFocusSmoothWaypoint) ~= "boolean" then db.vignetteRadarWorldFocusSmoothWaypoint = true end
    if db.vignetteRadarAutoRouteArrivalRadius ~= 3 and db.vignetteRadarAutoRouteArrivalRadius ~= 5
        and db.vignetteRadarAutoRouteArrivalRadius ~= 10 and db.vignetteRadarAutoRouteArrivalRadius ~= 20
        and db.vignetteRadarAutoRouteArrivalRadius ~= 40 then
        db.vignetteRadarAutoRouteArrivalRadius = 10
    end
    if db.vignetteRadarAutoRouteTravel ~= "auto" and db.vignetteRadarAutoRouteTravel ~= "ground"
        and db.vignetteRadarAutoRouteTravel ~= "flying" then db.vignetteRadarAutoRouteTravel = "auto" end
    if db.vignetteRadarWorldFocusArrivalRadius ~= 3 and db.vignetteRadarWorldFocusArrivalRadius ~= 5
        and db.vignetteRadarWorldFocusArrivalRadius ~= 10 and db.vignetteRadarWorldFocusArrivalRadius ~= 20
        and db.vignetteRadarWorldFocusArrivalRadius ~= 40 then db.vignetteRadarWorldFocusArrivalRadius = 20 end
    if type(db.vignetteRadarKeepMarkerUntilDone) ~= "boolean" then db.vignetteRadarKeepMarkerUntilDone = false end
    if type(db.vignetteRadarQuestPinWhenClose) ~= "boolean" then db.vignetteRadarQuestPinWhenClose = true end
    if type(db.vignetteRadarBeaconRares) ~= "boolean" then db.vignetteRadarBeaconRares = true end
    if type(db.vignetteRadarBeaconTreasures) ~= "boolean" then db.vignetteRadarBeaconTreasures = true end
    if type(db.vignetteRadarBeaconQuests) ~= "boolean" then db.vignetteRadarBeaconQuests = true end
    if db.vignetteRadarBeaconRange ~= 150 and db.vignetteRadarBeaconRange ~= 450
        and db.vignetteRadarBeaconRange ~= 1200 and db.vignetteRadarBeaconRange ~= 2400 then
        db.vignetteRadarBeaconRange = 1200
    end
    if db.vignetteRadarBeaconMax ~= 4 and db.vignetteRadarBeaconMax ~= 8
        and db.vignetteRadarBeaconMax ~= 12 and db.vignetteRadarBeaconMax ~= 16
        and db.vignetteRadarBeaconMax ~= 24 then
        db.vignetteRadarBeaconMax = 8
    end
    local validRange = false
    for _, range in ipairs(addon.VignetteRadarRanges) do
        if db.vignetteRadarRange == range then
            validRange = true
            break
        end
    end
    if not validRange then db.vignetteRadarRange = 450 end
    local validLayout = false
    for _, layout in ipairs(addon.VignetteRadarLayouts) do
        if db.vignetteRadarLayout == layout then
            validLayout = true
            break
        end
    end
    if not validLayout then db.vignetteRadarLayout = "classic" end
    if type(db.vignetteRadarScale) ~= "number" or db.vignetteRadarScale ~= db.vignetteRadarScale
        or db.vignetteRadarScale == math.huge or db.vignetteRadarScale == -math.huge then
        db.vignetteRadarScale = 1
    else
        db.vignetteRadarScale = math.max(0.8, math.min(1.8, db.vignetteRadarScale))
    end
    if type(db.vignetteRadarNorthUp) ~= "boolean" then db.vignetteRadarNorthUp = false end
    if type(db.vignetteRadarWorldMap) ~= "boolean" then db.vignetteRadarWorldMap = true end
    if type(db.vignetteRadarQuestDots) ~= "boolean" then db.vignetteRadarQuestDots = false end
    if type(db.vignetteRadarQuestAreas) ~= "boolean" then db.vignetteRadarQuestAreas = false end
    if type(db.vignetteRadarQuestHalos) ~= "boolean" then db.vignetteRadarQuestHalos = true end
    if type(db.vignetteRadarQuestColors) ~= "boolean" then db.vignetteRadarQuestColors = true end
    if type(db.vignetteRadarQuestAreaColors) ~= "boolean" then db.vignetteRadarQuestAreaColors = false end
    if db.vignetteRadarQuestAreaColorsReset ~= true then
        db.vignetteRadarQuestAreaColors = false
        db.vignetteRadarQuestAreaColorsReset = true
    end
    if type(db.vignetteRadarNextQuestStep) ~= "boolean" then db.vignetteRadarNextQuestStep = false end
    if type(db.vignetteRadarQuestStartBadges) ~= "boolean" then db.vignetteRadarQuestStartBadges = false end
    if type(db.vignetteRadarQuestNumbers) ~= "boolean" then db.vignetteRadarQuestNumbers = false end
    if type(db.vignetteRadarDataStatus) ~= "boolean" then db.vignetteRadarDataStatus = false end
    if type(db.vignetteRadarLensEnabled) ~= "boolean" then db.vignetteRadarLensEnabled = false end
    if db.vignetteRadarLensCategory ~= "quest" and db.vignetteRadarLensCategory ~= "rare"
        and db.vignetteRadarLensCategory ~= "treasure" then db.vignetteRadarLensCategory = "quest" end
    if db.vignetteRadarRouteDraftStops ~= 3 and db.vignetteRadarRouteDraftStops ~= 4
        and db.vignetteRadarRouteDraftStops ~= 5 then db.vignetteRadarRouteDraftStops = 5 end
    if db.vignetteRadarRouteDraftRange ~= 300 and db.vignetteRadarRouteDraftRange ~= 600
        and db.vignetteRadarRouteDraftRange ~= 1200 then db.vignetteRadarRouteDraftRange = 1200 end
    local haloRadius = db.vignetteRadarQuestHaloRadius
    if haloRadius ~= 10 and haloRadius ~= 20 and haloRadius ~= 40 and haloRadius ~= 80 then
        db.vignetteRadarQuestHaloRadius = 10
    end
    if type(db.vignetteRadarFollowTrackedQuest) ~= "boolean" then db.vignetteRadarFollowTrackedQuest = false end
    if type(db.vignetteRadarEdgeCues) ~= "boolean" then db.vignetteRadarEdgeCues = true end
    if type(db.vignetteRadarEmptyHelp) ~= "boolean" then db.vignetteRadarEmptyHelp = true end
    if type(db.vignetteRadarPeekEnabled) ~= "boolean" then db.vignetteRadarPeekEnabled = true end
    if type(db.vignetteRadarHoverTools) ~= "boolean" then db.vignetteRadarHoverTools = true end
    if type(db.vignetteRadarControlsVisible) ~= "boolean" then db.vignetteRadarControlsVisible = true end
    if type(db.vignetteRadarIndependentViews) ~= "boolean" then db.vignetteRadarIndependentViews = false end
    if type(db.vignetteRadarViewProfiles) ~= "table" then db.vignetteRadarViewProfiles = {} end
    if type(db.vignetteRadarQuestKeyProgress) ~= "boolean" then db.vignetteRadarQuestKeyProgress = true end
    if type(db.vignetteRadarQuestTrackerVisible) ~= "boolean" then db.vignetteRadarQuestTrackerVisible = true end
    if type(db.vignetteRadarTrayLocked) ~= "boolean" then db.vignetteRadarTrayLocked = false end
    local trackerSize = db.vignetteRadarQuestTrackerSize
    if trackerSize ~= nil and not (type(trackerSize) == "table" and type(trackerSize.width) == "number"
        and type(trackerSize.height) == "number") then db.vignetteRadarQuestTrackerSize = nil end
    if type(db.vignetteRadarLegendDetached) ~= "boolean" then db.vignetteRadarLegendDetached = false end
    -- Panels near the radar (UI/Tray.lua RegisterPanel): per panel key,
    -- { detached, locked, x, y }; anything else is dropped.
    if type(db.vignetteRadarPanelLayout) ~= "table" then db.vignetteRadarPanelLayout = {} end
    for key, record in pairs(db.vignetteRadarPanelLayout) do
        if type(key) ~= "string" or type(record) ~= "table" then
            db.vignetteRadarPanelLayout[key] = nil
        else
            for field, value in pairs(record) do
                local keep = (field == "detached" or field == "locked") and type(value) == "boolean"
                    or (field == "x" or field == "y") and type(value) == "number" and value == value
                        and math.abs(value) < 100000
                if not keep then record[field] = nil end
            end
        end
    end
    -- Button Tray ignore list (UI/ButtonTray.lua): name -> true only.
    if type(db.vignetteRadarButtonTrayIgnore) ~= "table" then db.vignetteRadarButtonTrayIgnore = {} end
    for name, value in pairs(db.vignetteRadarButtonTrayIgnore) do
        if type(name) ~= "string" or value ~= true then db.vignetteRadarButtonTrayIgnore[name] = nil end
    end
    -- Button Tray order (UI/ButtonTray.lua): per set, unique non-empty names;
    -- a set holding anything else starts over.
    if type(db.vignetteRadarButtonTrayOrder) ~= "table" then db.vignetteRadarButtonTrayOrder = {} end
    for set in pairs(db.vignetteRadarButtonTrayOrder) do
        if set ~= "radar" and set ~= "minimap" then db.vignetteRadarButtonTrayOrder[set] = nil end
    end
    for _, set in ipairs({ "radar", "minimap" }) do
        local list, seen = db.vignetteRadarButtonTrayOrder[set], {}
        local valid = type(list) == "table"
        if valid then
            local count = 0
            for _ in pairs(list) do count = count + 1 end
            valid = count == #list
            for _, name in ipairs(list) do
                if type(name) ~= "string" or name == "" or seen[name] then valid = false; break end
                seen[name] = true
            end
        end
        if not valid then db.vignetteRadarButtonTrayOrder[set] = {} end
    end
    if type(db.vignetteRadarPanelsMatchRadar) ~= "boolean" then db.vignetteRadarPanelsMatchRadar = true end
    if db.vignetteRadarTrayHandle ~= "lip" and db.vignetteRadarTrayHandle ~= "groove"
        and db.vignetteRadarTrayHandle ~= "icon" then db.vignetteRadarTrayHandle = "lip" end
    -- Switches must stay booleans; the few string defaults keep any allowed
    -- choice (a bare boolean check reset them on every validation, so the
    -- Button Tray flip and the underlay shape never stuck).
    for key, default in pairs(FEATURE_DEFAULTS) do
        local allowed = FEATURE_CHOICES[key]
        if allowed then
            if not allowed[db[key]] then db[key] = default end
        elseif type(db[key]) ~= "boolean" then db[key] = default end
    end
    if db.vignetteRadarQuestTrackerView ~= "tray" and db.vignetteRadarQuestTrackerView ~= "floating" then
        db.vignetteRadarQuestTrackerView = "floating"
    end
    if db.vignetteRadarQuestTrackerSide ~= "left" and db.vignetteRadarQuestTrackerSide ~= "right"
        and db.vignetteRadarQuestTrackerSide ~= "top" and db.vignetteRadarQuestTrackerSide ~= "bottom" then
        db.vignetteRadarQuestTrackerSide = "right"
    end
    if db.vignetteRadarQuestTrackerScope ~= "local" and db.vignetteRadarQuestTrackerScope ~= "watched"
        and db.vignetteRadarQuestTrackerScope ~= "all" then db.vignetteRadarQuestTrackerScope = "local" end
    if type(db.vignetteRadarQuestTrackerCollapsed) ~= "table" then
        db.vignetteRadarQuestTrackerCollapsed = {}
    end
    if type(db.vignetteRadarGuideSeen) ~= "boolean" then db.vignetteRadarGuideSeen = false end
    if type(db.vignetteRadarRouteAutoAdvance) ~= "boolean" then db.vignetteRadarRouteAutoAdvance = false end
    if db.vignetteRadarRouteArrivalRadius ~= 10 and db.vignetteRadarRouteArrivalRadius ~= 20
        and db.vignetteRadarRouteArrivalRadius ~= 40 then db.vignetteRadarRouteArrivalRadius = 20 end
    local savedPOISource = db.vignetteRadarPOISource
    if type(db.vignetteRadarPOISource) ~= "string" then db.vignetteRadarPOISource = "auto" end
    if type(db.vignetteRadarMapNotesVisible) ~= "boolean" then
        -- Auto was the old implicit default. Hide it once on existing installs,
        -- while keeping an explicitly selected pack, zone, or fusion visible.
        db.vignetteRadarMapNotesVisible = type(savedPOISource) == "string"
            and savedPOISource ~= "auto" and savedPOISource ~= "none"
            or type(db.vignetteRadarPOIZoneSources) == "table"
                and next(db.vignetteRadarPOIZoneSources) ~= nil
            or db.vignetteRadarSourceFusion == true
    end
    if type(db.vignetteRadarSourceFusion) ~= "boolean" then db.vignetteRadarSourceFusion = false end
    if type(db.vignetteRadarFusionSources) ~= "table" then db.vignetteRadarFusionSources = {} end
    if type(db.vignetteRadarFusionPreferred) ~= "table" then db.vignetteRadarFusionPreferred = {} end
    if db.vignetteRadarFusionDistance ~= .001 and db.vignetteRadarFusionDistance ~= .002
        and db.vignetteRadarFusionDistance ~= .005 then db.vignetteRadarFusionDistance = .002 end
    if type(db.vignetteRadarSurveyData) ~= "table" then db.vignetteRadarSurveyData = {} end
    if type(db.vignetteRadarSurveying) ~= "boolean" then db.vignetteRadarSurveying = false end
    if type(db.vignetteRadarSurveyShared) ~= "boolean" then db.vignetteRadarSurveyShared = false end
    if type(db.vignetteRadarReplayRecording) ~= "boolean" then db.vignetteRadarReplayRecording = false end
    if db.vignetteRadarSurveyCellSize ~= .02 and db.vignetteRadarSurveyCellSize ~= .025
        and db.vignetteRadarSurveyCellSize ~= .05 then db.vignetteRadarSurveyCellSize = .025 end
    if type(db.vignetteRadarPartyHunt) ~= "table" then db.vignetteRadarPartyHunt = {} end
    local party = db.vignetteRadarPartyHunt
    if party.receive ~= "party" and party.receive ~= "raid" then party.receive = "off" end
    if type(party.shareSightings) ~= "boolean" then party.shareSightings = false end
    if type(party.shareStop) ~= "boolean" then party.shareStop = false end
    if type(party.ignored) ~= "table" then party.ignored = {} end
    if type(db.vignetteRadarWarbandBoardData) ~= "table" then db.vignetteRadarWarbandBoardData = {} end
    if type(db.vignetteRadarResetPlannerData) ~= "table" then db.vignetteRadarResetPlannerData = {} end
    if db.vignetteRadarWarbandStaleDays ~= 3 and db.vignetteRadarWarbandStaleDays ~= 7
        and db.vignetteRadarWarbandStaleDays ~= 14 then db.vignetteRadarWarbandStaleDays = 7 end
    if type(db.vignetteRadarContextDirectorEnabled) ~= "boolean" then
        db.vignetteRadarContextDirectorEnabled = false
    end
    if type(db.vignetteRadarSoundCompassEnabled) ~= "boolean" then
        db.vignetteRadarSoundCompassEnabled = false
    end
    if db.vignetteRadarSoundCompassMode ~= "text" and db.vignetteRadarSoundCompassMode ~= "tone" then
        db.vignetteRadarSoundCompassMode = "text"
    end
    if db.vignetteRadarSoundCompassCooldown ~= 3 and db.vignetteRadarSoundCompassCooldown ~= 6
        and db.vignetteRadarSoundCompassCooldown ~= 12 then
        db.vignetteRadarSoundCompassCooldown = 6
    end
    if type(db.vignetteRadarTreasurePlaybooks) ~= "boolean" then
        db.vignetteRadarTreasurePlaybooks = true
    end
    -- Off hides the niche tools' buttons; their saved data and code stay.
    if type(db.vignetteRadarAdvancedTools) ~= "boolean" then
        db.vignetteRadarAdvancedTools = false
    end
    -- /vrtrace: the route-decision debug trace (off by default) and its saved lines.
    if type(db.vignetteRadarTraceEnabled) ~= "boolean" then db.vignetteRadarTraceEnabled = false end
    if type(db.vignetteRadarTraceLog) ~= "table" then db.vignetteRadarTraceLog = {} end
    if type(db.vignetteRadarPOIZoneSources) ~= "table" then db.vignetteRadarPOIZoneSources = {} end
    if db.vignetteRadarNameplateMarkerWho ~= "focus" and db.vignetteRadarNameplateMarkerWho ~= "favorite"
        and db.vignetteRadarNameplateMarkerWho ~= "rare" then db.vignetteRadarNameplateMarkerWho = "favorite" end
    if db.vignetteRadarNameplateMarkerScale ~= .75 and db.vignetteRadarNameplateMarkerScale ~= 1
        and db.vignetteRadarNameplateMarkerScale ~= 1.25 and db.vignetteRadarNameplateMarkerScale ~= 1.5 then
        db.vignetteRadarNameplateMarkerScale = 1
    end
    if db.vignetteRadarHorizonRibbonWidth ~= 320 and db.vignetteRadarHorizonRibbonWidth ~= 440
        and db.vignetteRadarHorizonRibbonWidth ~= 600 then db.vignetteRadarHorizonRibbonWidth = 440 end
    if db.vignetteRadarHorizonRibbonOffset ~= 8 and db.vignetteRadarHorizonRibbonOffset ~= 40
        and db.vignetteRadarHorizonRibbonOffset ~= 80 and db.vignetteRadarHorizonRibbonOffset ~= 120 then
        db.vignetteRadarHorizonRibbonOffset = 40
    end
    if type(db.vignetteRadarAreaPOIKinds) ~= "table" then db.vignetteRadarAreaPOIKinds = {} end
    for _, kind in ipairs({ "event", "delve", "race" }) do
        if type(db.vignetteRadarAreaPOIKinds[kind]) ~= "boolean" then db.vignetteRadarAreaPOIKinds[kind] = true end
    end
    if type(db.vignetteRadarRareSpawns) ~= "table" then db.vignetteRadarRareSpawns = {} end
    -- Collection Lens: off, mark, hide collected, or only what you lack.
    if db.vignetteRadarCollectionLens ~= "off" and db.vignetteRadarCollectionLens ~= "mark"
        and db.vignetteRadarCollectionLens ~= "hide" and db.vignetteRadarCollectionLens ~= "only" then
        db.vignetteRadarCollectionLens = "mark"
    end
    -- Pack Takeover: VR's saved pack notes and the HandyNotes packs VR hid.
    if type(db.vignetteRadarPackCache) ~= "table" then db.vignetteRadarPackCache = {} end
    if type(db.vignetteRadarPackHidden) ~= "table" then db.vignetteRadarPackHidden = {} end
    if type(db.vignetteRadarPOIIcons) ~= "boolean" then db.vignetteRadarPOIIcons = false end
    if type(db.vignetteRadarHideCleared) ~= "boolean" then db.vignetteRadarHideCleared = false end
    if type(db.vignetteRadarRecentKills) ~= "table" then db.vignetteRadarRecentKills = {} end
    if db.vignetteRadarAlertRange ~= 0 and db.vignetteRadarAlertRange ~= 600
        and db.vignetteRadarAlertRange ~= 1200 and db.vignetteRadarAlertRange ~= 2400
        and db.vignetteRadarAlertRange ~= 10000 then
        db.vignetteRadarAlertRange = 1200
    end
    if db.vignetteRadarShareChannel ~= "auto" and db.vignetteRadarShareChannel ~= "party"
        and db.vignetteRadarShareChannel ~= "raid" and db.vignetteRadarShareChannel ~= "say" then
        db.vignetteRadarShareChannel = "auto"
    end
    -- Route/world track: Zone Sweep, Today filter, shared sightings lifetime.
    if db.vignetteRadarZoneSweepKinds ~= "both" and db.vignetteRadarZoneSweepKinds ~= "rare"
        and db.vignetteRadarZoneSweepKinds ~= "treasure" then db.vignetteRadarZoneSweepKinds = "both" end
    if db.vignetteRadarZoneSweepMax ~= 20 and db.vignetteRadarZoneSweepMax ~= 40
        and db.vignetteRadarZoneSweepMax ~= 60 and db.vignetteRadarZoneSweepMax ~= 80 then
        db.vignetteRadarZoneSweepMax = 40
    end
    if db.vignetteRadarTodayFilter ~= "left" and db.vignetteRadarTodayFilter ~= "done"
        and db.vignetteRadarTodayFilter ~= "all" then db.vignetteRadarTodayFilter = "left" end
    if db.vignetteRadarSharedSightingsMinutes ~= 5 and db.vignetteRadarSharedSightingsMinutes ~= 10
        and db.vignetteRadarSharedSightingsMinutes ~= 20 then db.vignetteRadarSharedSightingsMinutes = 10 end
    if db.vignetteRadarAlertBanner ~= "off" and db.vignetteRadarAlertBanner ~= "favorite"
        and db.vignetteRadarAlertBanner ~= "all" then
        db.vignetteRadarAlertBanner = "favorite"
    end
    if db.vignetteRadarDeclutterRange ~= 0 and db.vignetteRadarDeclutterRange ~= 150
        and db.vignetteRadarDeclutterRange ~= 300 and db.vignetteRadarDeclutterRange ~= 600
        and db.vignetteRadarDeclutterRange ~= 1200 then
        db.vignetteRadarDeclutterRange = 0
    end
    if type(db.vignetteRadarPOITypes) ~= "table" then db.vignetteRadarPOITypes = {} end
    for kind, enabled in pairs({ treasure = true, mob = true, item = true, note = true,
        entrance = true, guide = true }) do
        if type(db.vignetteRadarPOITypes[kind]) ~= "boolean" then
            db.vignetteRadarPOITypes[kind] = enabled
        end
    end
    if type(db.vignetteRadarAlerts) ~= "boolean" then db.vignetteRadarAlerts = true end
    if type(db.vignetteRadarAlertSound) ~= "boolean" then db.vignetteRadarAlertSound = false end
    if type(db.vignetteRadarAlertCategories) ~= "table" then db.vignetteRadarAlertCategories = {} end
    for category, enabled in pairs({ rare = true, treasure = true, event = false, other = false }) do
        if type(db.vignetteRadarAlertCategories[category]) ~= "boolean" then
            db.vignetteRadarAlertCategories[category] = enabled
        end
    end
    if type(db.vignetteRadarAlertCooldown) ~= "number" or db.vignetteRadarAlertCooldown ~= db.vignetteRadarAlertCooldown then
        db.vignetteRadarAlertCooldown = 60
    else
        db.vignetteRadarAlertCooldown = math.max(5, math.min(3600, db.vignetteRadarAlertCooldown))
    end
    if type(db.vignetteRadarFavorites) ~= "table" then db.vignetteRadarFavorites = {} end
    if type(db.vignetteRadarIgnored) ~= "table" then db.vignetteRadarIgnored = {} end
    if type(db.vignetteRadarHiddenMarkerNames) ~= "table" then db.vignetteRadarHiddenMarkerNames = {} end
    if type(db.vignetteRadarHiddenMarkerTypes) ~= "table" then db.vignetteRadarHiddenMarkerTypes = {} end
    if type(db.vignetteRadarLastSeen) ~= "boolean" then db.vignetteRadarLastSeen = true end
    if type(db.vignetteRadarLastSeenSeconds) ~= "number" or db.vignetteRadarLastSeenSeconds ~= db.vignetteRadarLastSeenSeconds then
        db.vignetteRadarLastSeenSeconds = 10
    else
        db.vignetteRadarLastSeenSeconds = math.max(1, math.min(60, db.vignetteRadarLastSeenSeconds))
    end
    if type(db.vignetteRadarQuietCombat) ~= "boolean" then db.vignetteRadarQuietCombat = true end
    if type(db.vignetteRadarQuietInstances) ~= "boolean" then db.vignetteRadarQuietInstances = true end
    if type(db.vignetteRadarKeepVisibleCombat) ~= "boolean" then
        -- Older versions tied combat fading to alert muting. Preserve their
        -- visual choice when these two controls become independent.
        db.vignetteRadarKeepVisibleCombat = db.vignetteRadarQuietCombat == false
    end
    -- Move existing characters to the finalized rounded radar once, while
    -- retaining the legacy setting for imported profiles and API callers.
    if db.vignetteRadarMainViewMigrated ~= true then
        if db.vignetteRadarCircleOnly == false and not db.vignetteRadarCirclePosition
            and type(db.vignetteRadarPosition) == "table" then
            db.vignetteRadarCirclePosition = {
                x = db.vignetteRadarPosition.x, y = db.vignetteRadarPosition.y }
        end
        db.vignetteRadarCircleOnly = true
        db.vignetteRadarLayout = "classic"
        db.vignetteRadarMainViewMigrated = true
    end
    if type(db.vignetteRadarMarkerSize) ~= "number" or db.vignetteRadarMarkerSize ~= db.vignetteRadarMarkerSize then
        db.vignetteRadarMarkerSize = 7
    else
        db.vignetteRadarMarkerSize = math.max(5, math.min(9, db.vignetteRadarMarkerSize))
    end
    if type(db.vignetteRadarShapes) ~= "boolean" then db.vignetteRadarShapes = true end
    if type(db.vignetteRadarShowHealth) ~= "boolean" then db.vignetteRadarShowHealth = true end
    if type(db.vignetteRadarFullSweep) ~= "boolean" then db.vignetteRadarFullSweep = false end
    if type(db.vignetteRadarSmartZoom) ~= "boolean" then db.vignetteRadarSmartZoom = false end
    if type(db.vignetteRadarUntangle) ~= "boolean" then db.vignetteRadarUntangle = true end
    if type(db.vignetteRadarBreadcrumbs) ~= "boolean" then db.vignetteRadarBreadcrumbs = false end
    -- Old profiles: Travel Trail on becomes Follow, off becomes Off. After
    -- that, whichever key changed since the last pass wins: a new mode
    -- rewrites the Follow flag; a flipped Follow flag (toolbar, presets)
    -- rewrites the mode and keeps its Lead half.
    if not TrailMode.valid[db.vignetteRadarTrailMode] then
        db.vignetteRadarTrailMode = db.vignetteRadarBreadcrumbs and "follow" or "off"
    elseif db.vignetteRadarTrailMode ~= db.vignetteRadarTrailModeSeen then
        db.vignetteRadarBreadcrumbs = TrailMode.Follows(db.vignetteRadarTrailMode)
    elseif db.vignetteRadarBreadcrumbs ~= TrailMode.Follows(db.vignetteRadarTrailMode) then
        db.vignetteRadarTrailMode = TrailMode.Compose(db.vignetteRadarBreadcrumbs,
            TrailMode.Leads(db.vignetteRadarTrailMode))
    end
    db.vignetteRadarTrailModeSeen = db.vignetteRadarTrailMode
    if not TRAIL_STYLE_KEYS[db.vignetteRadarTrailStyle] then db.vignetteRadarTrailStyle = "dashes" end
    TrailSetting(db, "vignetteRadarTrailSpacing", 1)
    TrailSetting(db, "vignetteRadarTrailSpeed", 1)
    if type(db.vignetteRadarTrailSize) ~= "number" or db.vignetteRadarTrailSize ~= db.vignetteRadarTrailSize then
        db.vignetteRadarTrailSize = 1
    end
    db.vignetteRadarTrailSize = math.max(.1, math.min(2, db.vignetteRadarTrailSize))
    if type(db.vignetteRadarTrailTailFade) ~= "number" or db.vignetteRadarTrailTailFade ~= db.vignetteRadarTrailTailFade then
        db.vignetteRadarTrailTailFade = .5
    end
    db.vignetteRadarTrailTailFade = math.max(0, math.min(1, db.vignetteRadarTrailTailFade))
    if type(db.vignetteRadarTrailFadeSpan) ~= "number" or db.vignetteRadarTrailFadeSpan ~= db.vignetteRadarTrailFadeSpan then
        db.vignetteRadarTrailFadeSpan = 1
    end
    db.vignetteRadarTrailFadeSpan = math.max(0, math.min(1, db.vignetteRadarTrailFadeSpan))
    if type(db.vignetteRadarTrailLifetime) ~= "number"
        or db.vignetteRadarTrailLifetime ~= math.floor(db.vignetteRadarTrailLifetime)
        or db.vignetteRadarTrailLifetime < 1 or db.vignetteRadarTrailLifetime > 300 then
        db.vignetteRadarTrailLifetime = 180
    end
    if type(db.vignetteRadarApproachAlerts) ~= "boolean" then db.vignetteRadarApproachAlerts = false end
    if type(db.vignetteRadarApproachDistance) ~= "number" then db.vignetteRadarApproachDistance = 100 end
    db.vignetteRadarApproachDistance = math.max(25, math.min(600, db.vignetteRadarApproachDistance))
    if type(db.vignetteRadarJournalEnabled) ~= "boolean" then db.vignetteRadarJournalEnabled = false end
    if type(db.vignetteRadarPins) ~= "table" then db.vignetteRadarPins = {} end
    if type(db.vignetteRadarRoute) ~= "table" then db.vignetteRadarRoute = {} end
    if type(db.vignetteRadarJournal) ~= "table" then db.vignetteRadarJournal = {} end
    if type(db.vignetteRadarCustomPresets) ~= "table" then db.vignetteRadarCustomPresets = {} end
    -- Custom themes (Looks > Customize): { key = "custom_N", name, base,
    -- colors = { role = { r, g, b } } }. Malformed or duplicate entries are
    -- dropped and channels clamped to 0-1, so Style can read them as they are.
    -- The required roles are Style.slots minus the optional icon roles (Style loads after Core).
    do
        local roles = { "accent", "rings", "heading", "background", "rare", "boss", "treasure",
            "event", "other", "quest" }
        local kept, keys, names = {}, {}, {}
        for _, theme in ipairs(type(db.vignetteRadarCustomThemes) == "table"
            and db.vignetteRadarCustomThemes or {}) do
            local name = type(theme) == "table" and type(theme.name) == "string"
                and (theme.name:gsub("[%c|]", ""):match("^%s*(.-)%s*$")) or ""
            local valid = name ~= "" and #(name:gsub("[\128-\191]", "")) <= 24
                and type(theme.key) == "string" and theme.key:match("^custom_%d+$") ~= nil
                and not keys[theme.key] and not names[name:lower()] and type(theme.colors) == "table"
                and #kept < 50
            local colors = {}
            for _, role in ipairs(roles) do
                local color = valid and theme.colors[role]
                if type(color) ~= "table" then valid = false; break end
                colors[role] = {}
                for index = 1, 3 do
                    local channel = color[index]
                    if type(channel) ~= "number" or channel ~= channel then valid = false; break end
                    colors[role][index] = math.max(0, math.min(1, channel))
                end
                if not valid then break end
            end
            -- Icon layer roles (Style.iconSlots) are optional; valid ones are kept.
            for _, role in ipairs(valid and { "iconGlyph", "iconBorder", "iconPlate", "iconHover",
                "iconActive" } or {}) do
                local color = theme.colors[role]
                if type(color) == "table" and type(color[1]) == "number" and type(color[2]) == "number"
                    and type(color[3]) == "number" and color[1] == color[1] and color[2] == color[2]
                    and color[3] == color[3] then
                    colors[role] = { math.max(0, math.min(1, color[1])), math.max(0, math.min(1, color[2])),
                        math.max(0, math.min(1, color[3])) }
                end
            end
            if valid then
                keys[theme.key], names[name:lower()] = true, true
                kept[#kept + 1] = { key = theme.key, name = name, colors = colors,
                    base = type(theme.base) == "string" and theme.base or nil }
            end
        end
        db.vignetteRadarCustomThemes = kept
    end
    local style = addon.VignetteRadarStyle
    if style and not style.HasTheme(db.vignetteRadarTheme) then
        -- Other spellings and bare family names map onto a theme; anything else resets.
        db.vignetteRadarTheme = style.MigrateTheme and style.MigrateTheme(db.vignetteRadarTheme) or "verdant"
    elseif not style and type(db.vignetteRadarTheme) ~= "string" then
        db.vignetteRadarTheme = "verdant"
    end
    if type(db.vignetteRadarColors) ~= "table" then db.vignetteRadarColors = {} end
    local appearance = {
        vignetteRadarRingOpacity = { .5, 0, 2 },
        vignetteRadarChevronOpacity = { .72, 0, 1 },
        vignetteRadarHeadingOpacity = { .46, 0, 1 },
        vignetteRadarChevronDistance = { 4, 2, 9 },
        vignetteRadarHeadingLength = { .30, .12, .8 },
        -- Minimap Underlay: how opaque the radar face stays over the minimap.
        vignetteRadarMinimapUnderlayTint = { .5, .1, .9 },
    }
    for key, limits in pairs(appearance) do
        local value = db[key]
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
            db[key] = limits[1]
        else
            db[key] = math.max(limits[2], math.min(limits[3], value))
        end
    end
    if type(db.vignetteRadarBorderOpacity) ~= "number"
        or db.vignetteRadarBorderOpacity ~= db.vignetteRadarBorderOpacity
        or db.vignetteRadarBorderOpacity == math.huge
        or db.vignetteRadarBorderOpacity == -math.huge then
        -- Keep the existing outline when separating border and ring controls.
        db.vignetteRadarBorderOpacity = db.vignetteRadarRingOpacity
    end
    db.vignetteRadarBorderOpacity = math.max(0, math.min(4, db.vignetteRadarBorderOpacity))
    -- Text Size: one of the offered scales, else 100%.
    local textScale = db.vignetteRadarTextScale
    if textScale ~= 1 and textScale ~= 1.1 and textScale ~= 1.2 and textScale ~= 1.35 then
        db.vignetteRadarTextScale = 1
    end
    local labelOpacity = db.vignetteRadarRangeLabelOpacity
    if type(labelOpacity) ~= "number" or labelOpacity ~= labelOpacity
        or labelOpacity == math.huge or labelOpacity == -math.huge then
        -- Existing characters start with text matching their current rings.
        db.vignetteRadarRangeLabelOpacity = db.vignetteRadarRingOpacity
    else
        db.vignetteRadarRangeLabelOpacity = math.max(0, math.min(16, labelOpacity))
    end
    validated = db
    return db
end

-- Hot paths call this many times per frame; only revalidate when the saved
-- table changed or a writer asked for it through InvalidateSettings.
function addon.GetSettings()
    local db = VignetteRadarDB
    if db ~= nil and db == validated then return db end
    return addon.ValidateSettings()
end

function addon.InvalidateSettings()
    validated = nil
end

-- Survey, Expedition Studio, Intelligence and similar niche tools show their
-- buttons only while this switch is on.
function addon.AdvancedToolsEnabled()
    return addon.GetSettings().vignetteRadarAdvancedTools == true
end

-- View profiles are opt-in so existing saved layouts continue to share their
-- range and scale until the player explicitly separates them.
addon.VignetteRadarViewProfiles = {}
function addon.VignetteRadarViewProfiles.Key(db)
    return db.vignetteRadarCircleOnly and "radarOnly" or db.vignetteRadarLayout
end
function addon.VignetteRadarViewProfiles.Record(db)
    if db.vignetteRadarIndependentViews ~= true then return end
    local key = addon.VignetteRadarViewProfiles.Key(db)
    db.vignetteRadarViewProfiles[key] = {
        range = db.vignetteRadarRange, scale = db.vignetteRadarScale,
        hoverTools = db.vignetteRadarHoverTools,
        controlsVisible = db.vignetteRadarControlsVisible,
    }
end
function addon.VignetteRadarViewProfiles.Switch(db, nextKey)
    if db.vignetteRadarIndependentViews ~= true then return end
    local profiles = db.vignetteRadarViewProfiles
    addon.VignetteRadarViewProfiles.Record(db)
    local saved = profiles[nextKey]
    if type(saved) ~= "table" then
        profiles[nextKey] = { range = db.vignetteRadarRange, scale = db.vignetteRadarScale,
            hoverTools = db.vignetteRadarHoverTools,
            controlsVisible = db.vignetteRadarControlsVisible }
        return
    end
    for _, supported in ipairs(addon.VignetteRadarRanges) do
        if saved.range == supported then db.vignetteRadarRange = supported; break end
    end
    if type(saved.scale) == "number" and saved.scale == saved.scale
        and saved.scale ~= math.huge and saved.scale ~= -math.huge then
        db.vignetteRadarScale = math.max(.8, math.min(1.8, saved.scale))
    end
    if type(saved.hoverTools) == "boolean" then db.vignetteRadarHoverTools = saved.hoverTools end
    if type(saved.controlsVisible) == "boolean" then
        db.vignetteRadarControlsVisible = saved.controlsVisible
    end
end

addon.GetSettings()
