local sourcePath = arg[1] or "Core/Core.lua"

WaffleHouseDB = {
    vignetteRadarEnabled = false,
    vignetteRadarHideWhenEmpty = false,
    vignetteRadarRange = 600,
    vignetteRadarLauncherVisible = false,
    vignetteRadarPosition = { x = 111, y = -222 },
    vignetteRadarLauncherPosition = { x = 33, y = -44 },
    vignetteRadarCategories = { rare = false, treasure = true },
    vignetteRadarHighlight = "treasure",
}
VignetteRadarDB = nil
local addon = {}
assert(loadfile(sourcePath))("VignetteRadar", addon)
local db = addon.GetSettings()
assert(db.vignetteRadarEnabled == false and db.vignetteRadarHideWhenEmpty == false
    and db.vignetteRadarLauncherVisible == false and db.vignetteRadarRange == 600,
    "standalone addon must migrate the user's original radar choices")
assert(db.vignetteRadarWorldMap == true, "world-map detections should be included by default")
assert(db.vignetteRadarKeepVisibleCombat == false,
    "existing quiet-combat settings should preserve combat fading")
assert(db.vignetteRadarQuestDots == false and db.vignetteRadarQuestAreas == false,
    "new quest overlays should preserve the existing uncluttered radar until enabled")
assert(db.vignetteRadarQuestHalos == true and db.vignetteRadarQuestColors == true
    and db.vignetteRadarQuestAreaColors == false
    and db.vignetteRadarQuestHaloRadius == 10,
    "estimated quest circles should be ready when quest dots and areas are enabled")
assert(db.vignetteRadarPosition.x == 111 and db.vignetteRadarLauncherPosition.y == -44
    and db.vignetteRadarCategories.rare == false and db.vignetteRadarHighlight == "treasure",
    "standalone addon must preserve placement and category choices")
db.vignetteRadarPosition.x = 999
db.vignetteRadarCategories.rare = true
assert(WaffleHouseDB.vignetteRadarPosition.x == 111 and WaffleHouseDB.vignetteRadarCategories.rare == false,
    "migrated settings must be independent of Waffle House")

WaffleHouseDB.vignetteRadarEnabled = true
assert(addon.GetSettings().vignetteRadarEnabled == false,
    "the old addon must not overwrite standalone settings after migration")

VignetteRadarDB = nil
WaffleHouseDB = nil
local fresh = {}
assert(loadfile(sourcePath))("VignetteRadar", fresh)
local defaults = fresh.GetSettings()
assert(defaults.vignetteRadarRangeLabelOpacity == defaults.vignetteRadarRingOpacity,
    "yard labels must start at the same visibility as the range rings")
defaults.vignetteRadarQuestAreaColorsReset = nil
defaults.vignetteRadarQuestAreaColors = true
fresh.ValidateSettings()
assert(defaults.vignetteRadarQuestAreaColors == false
    and defaults.vignetteRadarQuestAreaColorsReset == true,
    "the old quest-area color setting must reset to reliable blue once")
defaults.vignetteRadarQuestAreaColors = true
fresh.ValidateSettings()
assert(defaults.vignetteRadarQuestAreaColors == true,
    "an explicit later choice to color estimated circles must persist")
defaults.vignetteRadarQuestAreaColors = false
-- Choice-valued feature defaults keep an allowed choice (the Button Tray flip
-- and underlay shape used to reset on every validation).
assert(defaults.vignetteRadarButtonTraySet == "radar" and defaults.vignetteRadarMinimapUnderlayShape == "square",
    "choice feature defaults")
defaults.vignetteRadarButtonTraySet = "minimap"
defaults.vignetteRadarMinimapUnderlayShape = "circle"
defaults.vignetteRadarMinimapUnderlayIcons = "split"
fresh.ValidateSettings()
assert(defaults.vignetteRadarButtonTraySet == "minimap" and defaults.vignetteRadarMinimapUnderlayShape == "circle"
    and defaults.vignetteRadarMinimapUnderlayIcons == "split", "an allowed choice survives validation")
defaults.vignetteRadarButtonTraySet = "bogus"
defaults.vignetteRadarMinimapUnderlayShape = true
fresh.ValidateSettings()
assert(defaults.vignetteRadarButtonTraySet == "radar" and defaults.vignetteRadarMinimapUnderlayShape == "square",
    "an unknown choice falls back to the default")
defaults.vignetteRadarMinimapUnderlayIcons = "radar"
-- Button Tray order: per set, unique non-empty names, else that set starts over.
defaults.vignetteRadarButtonTrayOrder = "bogus"
fresh.ValidateSettings()
local trayOrder = defaults.vignetteRadarButtonTrayOrder
assert(type(trayOrder) == "table" and #trayOrder.radar == 0 and #trayOrder.minimap == 0,
    "a non-table button order validates to empty sets")
defaults.vignetteRadarButtonTrayOrder = { radar = { "legend", "target" }, minimap = { "A", "A" }, other = { "x" } }
fresh.ValidateSettings()
trayOrder = defaults.vignetteRadarButtonTrayOrder
assert(trayOrder.radar[1] == "legend" and trayOrder.radar[2] == "target", "a valid set order survives")
assert(#trayOrder.minimap == 0 and trayOrder.other == nil, "duplicates reset the set; unknown sets dropped")
defaults.vignetteRadarButtonTrayOrder = { radar = { "x", 3 }, minimap = { "" } }
fresh.ValidateSettings()
assert(#defaults.vignetteRadarButtonTrayOrder.radar == 0 and #defaults.vignetteRadarButtonTrayOrder.minimap == 0,
    "non-string or empty names reset the set")
assert(defaults.vignetteRadarAutoRouteArrivalRadius == 10,
    "Auto Route must wait for a ten-yard arrival by default")
defaults.vignetteRadarAutoRouteArrivalRadius = 3
fresh.ValidateSettings()
assert(defaults.vignetteRadarAutoRouteArrivalRadius == 3,
    "the close three-yard arrival choice should stay selected")
defaults.vignetteRadarAutoRouteArrivalRadius = 7
fresh.ValidateSettings()
assert(defaults.vignetteRadarAutoRouteArrivalRadius == 10,
    "an unknown arrival distance should fall back to ten yards")
defaults.vignetteRadarWorldFocusArrivalRadius = 5
fresh.ValidateSettings()
assert(defaults.vignetteRadarWorldFocusArrivalRadius == 5
    and defaults.vignetteRadarKeepMarkerUntilDone == false
    and defaults.vignetteRadarQuestPinWhenClose == true,
    "five-yard focus arrival and the new marker switches should validate")
defaults.vignetteRadarAutoRouteArrivalRadius = 20
fresh.ValidateSettings()
assert(defaults.vignetteRadarAutoRouteArrivalRadius == 20,
    "an existing larger arrival distance should stay selected")
assert(defaults.vignetteRadarGuidePanel == true and defaults.vignetteRadarGuideDensity == "expanded"
    and defaults.vignetteRadarGuideStops == 3 and defaults.vignetteRadarGuideBlocks.stops == true
    and defaults.vignetteRadarGuideBlocks.facts == true and defaults.vignetteRadarGuideMigrated == true
    and defaults.vignetteRadarRouteArrow == nil,
    "a new profile shows the Guide Panel with every block, and writes no retired key")
assert(defaults.vignetteRadarAutoRouteNearbyZones == true
    and defaults.vignetteRadarAutoRouteQuestStarts == true
    and defaults.vignetteRadarAutoRouteQuestNearest == true
    and defaults.vignetteRadarWorldQuestPriority == true
    and defaults.vignetteRadarWorldQuestPriorityRange == 300,
    "nearby zones, available starts, and closest quest continuation should default on")
defaults.vignetteRadarAutoRouteNearbyZones = false
fresh.ValidateSettings()
assert(defaults.vignetteRadarAutoRouteNearbyZones == false,
    "an explicit choice to stop at the current zone should persist")
assert(defaults.vignetteRadarAdvancedTools == false and fresh.AdvancedToolsEnabled() == false,
    "Advanced Tools must default off")
defaults.vignetteRadarAdvancedTools = "yes"
fresh.ValidateSettings()
assert(defaults.vignetteRadarAdvancedTools == false, "Advanced Tools must be a boolean")
defaults.vignetteRadarAdvancedTools = true
fresh.ValidateSettings()
assert(fresh.AdvancedToolsEnabled() == true, "Advanced Tools must keep an explicit on")
assert(defaults.vignetteRadarBeaconsEnabled == false
    and defaults.vignetteRadarPerformance == "standard"
    and defaults.vignetteRadarBeaconRares == true
    and defaults.vignetteRadarBeaconTreasures == true
    and defaults.vignetteRadarBeaconQuests == true
    and defaults.vignetteRadarBeaconRange == 1200
    and defaults.vignetteRadarBeaconMax == 8,
    "the optional bearing bar should start disabled with bounded defaults")
defaults.vignetteRadarPerformance = "low"
fresh.ValidateSettings()
assert(defaults.vignetteRadarPerformance == "low", "the user's chosen update rate must persist")
defaults.vignetteRadarPerformance = "unsupported"
fresh.ValidateSettings()
assert(defaults.vignetteRadarPerformance == "standard", "invalid update rates must reset safely")
defaults.vignetteRadarBearingBarDefaulted = nil
defaults.vignetteRadarBeaconsEnabled = true
fresh.ValidateSettings()
assert(defaults.vignetteRadarBeaconsEnabled == false,
    "the previous automatic bar should be hidden once for existing users")
defaults.vignetteRadarBeaconsEnabled = true
fresh.ValidateSettings()
assert(defaults.vignetteRadarBeaconsEnabled == true,
    "turning the bearing bar on after migration must remain the user's choice")
defaults.vignetteRadarRingOpacity = 1.25
defaults.vignetteRadarRangeLabelOpacity = nil
fresh.ValidateSettings()
assert(defaults.vignetteRadarRangeLabelOpacity == 1.25,
    "existing ring visibility must seed the independent yard-label setting")
defaults.vignetteRadarRingOpacity = .25
fresh.ValidateSettings()
assert(defaults.vignetteRadarRangeLabelOpacity == 1.25,
    "later ring changes must leave yard-label visibility alone")
defaults.vignetteRadarRangeLabelOpacity = 20
fresh.ValidateSettings()
assert(defaults.vignetteRadarRangeLabelOpacity == 16,
    "yard-label visibility must stay within its supported range")
defaults.vignetteRadarRingOpacity, defaults.vignetteRadarRangeLabelOpacity = .5, .5
assert(defaults.vignetteRadarEnabled == true and defaults.vignetteRadarHideWhenEmpty == true
    and defaults.vignetteRadarLauncherVisible == true and defaults.vignetteRadarRange == 450
    and defaults.vignetteRadarWorldMap == true and defaults.vignetteRadarLayout == "classic"
    and defaults.vignetteRadarNorthUp == false and defaults.vignetteRadarScale == 1,
    "the radar must work without either optional addon installed")
assert(defaults.vignetteRadarPOISource == "auto"
    and defaults.vignetteRadarMapNotesVisible == false
    and defaults.vignetteRadarAutoRouteMapNotes == false,
    "new installations should keep map-pack marks and routing off until selected")
assert(defaults.vignetteRadarPOIIcons == false,
    "existing map notes should remain dots until pack icons are enabled")
defaults.vignetteRadarPOIIcons = true
fresh.ValidateSettings()
assert(defaults.vignetteRadarPOIIcons == true, "the pack-icon choice must persist")
defaults.vignetteRadarPOIIcons = "bad"
fresh.ValidateSettings()
assert(defaults.vignetteRadarPOIIcons == false, "invalid pack-icon settings must reset safely")
assert(defaults.vignetteRadarTrailStyle == "dashes",
    "new and migrated installations should use trail marks distinct from quest dots")
assert(defaults.vignetteRadarTrailSpacing == 1 and defaults.vignetteRadarTrailSpeed == 1
    and defaults.vignetteRadarTrailLifetime == 180
    and defaults.vignetteRadarTrailSize == 1 and defaults.vignetteRadarTrailTailFade == .5
    and defaults.vignetteRadarTrailFadeSpan == 1,
    "new installations should have readable animated marks and a three-minute fade")
for key, values in pairs(fresh.VignetteRadarTrailSettingValues) do
    for _, value in ipairs(values) do
        defaults[key] = value
        fresh.GetSettings()
        assert(defaults[key] == value, "every trail control choice must persist: " .. key .. "=" .. value)
    end
end
defaults.vignetteRadarTrailSpacing, defaults.vignetteRadarTrailSpeed = 1, 1
defaults.vignetteRadarTrailStyle = "ticks"
fresh.ValidateSettings()
assert(defaults.vignetteRadarTrailStyle == "ticks", "the chosen trail style must persist")
defaults.vignetteRadarTrailStyle = "diamonds"
defaults.vignetteRadarTrailSpacing = 1.5
defaults.vignetteRadarTrailSpeed = 0
defaults.vignetteRadarTrailLifetime = 300
fresh.ValidateSettings()
assert(defaults.vignetteRadarTrailStyle == "diamonds" and defaults.vignetteRadarTrailSpacing == 1.5
    and defaults.vignetteRadarTrailSpeed == 0 and defaults.vignetteRadarTrailLifetime == 300,
    "new trail styles and flow controls must persist")
defaults.vignetteRadarTrailStyle = "hollow-squares"
defaults.vignetteRadarTrailLifetime = 1
fresh.ValidateSettings()
assert(defaults.vignetteRadarTrailStyle == "hollow-squares"
    and defaults.vignetteRadarTrailLifetime == 1,
    "square styles and a one-second fade must remain saved")
defaults.vignetteRadarTrailStyle = "unsupported"
defaults.vignetteRadarTrailSpacing = -1
defaults.vignetteRadarTrailSpeed = 99
defaults.vignetteRadarTrailLifetime = 999
fresh.ValidateSettings()
assert(defaults.vignetteRadarTrailStyle == "dashes" and defaults.vignetteRadarTrailSpacing == 1
    and defaults.vignetteRadarTrailSpeed == 1 and defaults.vignetteRadarTrailLifetime == 180,
    "invalid trail settings must recover safely")
defaults.vignetteRadarTrailSize = .1
defaults.vignetteRadarTrailTailFade = .37
defaults.vignetteRadarTrailFadeSpan = .63
fresh.ValidateSettings()
assert(defaults.vignetteRadarTrailSize == .1 and defaults.vignetteRadarTrailTailFade == .37
    and defaults.vignetteRadarTrailFadeSpan == .63,
    "precise trail size and fade percentages must survive settings validation")
defaults.vignetteRadarPOISource = "none"
fresh.ValidateSettings()
assert(defaults.vignetteRadarPOISource == "none", "an existing Off choice must remain Off")
defaults.vignetteRadarMapNotesVisible = true
fresh.ValidateSettings()
assert(defaults.vignetteRadarMapNotesVisible == true,
    "a later choice to show map notes must survive settings validation")
local expectedRanges = { 10, 25, 50, 100, 150, 300, 450, 600, 1200, 2400, 4800 }
assert(#fresh.VignetteRadarRanges == #expectedRanges, "all selectable ranges must be published")
for index, range in ipairs(expectedRanges) do
    assert(fresh.VignetteRadarRanges[index] == range, "range order must stay stable")
    defaults.vignetteRadarRange = range
    fresh.GetSettings()
    assert(defaults.vignetteRadarRange == range, "supported range must remain valid: " .. range)
end
local expectedLayouts = { "classic", "squat", "compact" }
assert(#fresh.VignetteRadarLayouts == #expectedLayouts, "all selectable layouts must be published")
for index, layout in ipairs(expectedLayouts) do
    assert(fresh.VignetteRadarLayouts[index] == layout, "layout order must stay stable")
end
defaults.vignetteRadarRange = 999
defaults.vignetteRadarWorldMap = "bad"
defaults.vignetteRadarQuestDots = "bad"
defaults.vignetteRadarQuestAreas = "bad"
defaults.vignetteRadarQuestHalos = "bad"
defaults.vignetteRadarQuestColors = "bad"
defaults.vignetteRadarQuestAreaColors = "bad"
defaults.vignetteRadarQuestHaloRadius = 999
defaults.vignetteRadarLayout = "unsupported"
defaults.vignetteRadarNorthUp = "bad"
defaults.vignetteRadarScale = "bad"
fresh.ValidateSettings()
assert(defaults.vignetteRadarRange == 450 and defaults.vignetteRadarWorldMap == true
    and defaults.vignetteRadarQuestDots == false and defaults.vignetteRadarQuestAreas == false
    and defaults.vignetteRadarQuestHalos == true and defaults.vignetteRadarQuestColors == true
    and defaults.vignetteRadarQuestAreaColors == false
    and defaults.vignetteRadarQuestHaloRadius == 10
    and defaults.vignetteRadarLayout == "classic" and defaults.vignetteRadarNorthUp == false
    and defaults.vignetteRadarScale == 1,
    "invalid range, mode, layout, and north-up values must reset to safe defaults")
defaults.vignetteRadarWorldMap = false
defaults.vignetteRadarNorthUp = true
defaults.vignetteRadarScale = 1.35
fresh.ValidateSettings()
assert(defaults.vignetteRadarNorthUp == true, "north-up preference must persist when enabled")
assert(defaults.vignetteRadarScale == 1.35, "user frame scale must persist")
for _, layout in ipairs({ "classic", "squat", "compact" }) do
    defaults.vignetteRadarLayout = layout
    fresh.GetSettings()
    assert(defaults.vignetteRadarLayout == layout, "supported layout must persist: " .. layout)
end
fresh.ValidateSettings()
assert(defaults.vignetteRadarWorldMap == false, "world-map choice must persist when disabled")
assert(defaults.vignetteRadarIndependentViews == false
    and defaults.vignetteRadarControlsVisible == true
    and defaults.vignetteRadarQuestKeyProgress == true
    and defaults.vignetteRadarRouteAutoAdvance == false
    and defaults.vignetteRadarRouteArrivalRadius == 20
    and type(defaults.vignetteRadarPOIZoneSources) == "table",
    "new navigation choices need safe defaults")
local profiles = fresh.VignetteRadarViewProfiles
defaults.vignetteRadarCircleOnly = false
defaults.vignetteRadarLayout = "classic"
defaults.vignetteRadarRange, defaults.vignetteRadarScale = 150, 1.2
defaults.vignetteRadarControlsVisible = false
defaults.vignetteRadarIndependentViews = true
profiles.Switch(defaults, "squat")
defaults.vignetteRadarLayout = "squat"
defaults.vignetteRadarRange, defaults.vignetteRadarScale = 300, .9
defaults.vignetteRadarControlsVisible = true
profiles.Switch(defaults, "classic")
defaults.vignetteRadarLayout = "classic"
assert(defaults.vignetteRadarRange == 150 and defaults.vignetteRadarScale == 1.2
    and defaults.vignetteRadarControlsVisible == false,
    "switching layouts must restore zoom, scale, and button visibility")
defaults.vignetteRadarIndependentViews = false
defaults.vignetteRadarCircleOnly = true
defaults.vignetteRadarControlsVisible = true
assert(defaults.vignetteRadarEdgeCues and defaults.vignetteRadarEmptyHelp
    and defaults.vignetteRadarPeekEnabled and defaults.vignetteRadarHoverTools
    and defaults.vignetteRadarFollowTrackedQuest == false,
    "new map, hover, and peek features need explicit saved defaults")
assert(defaults.vignetteRadarNextQuestStep == false
    and defaults.vignetteRadarQuestStartBadges == false
    and defaults.vignetteRadarQuestNumbers == false
    and defaults.vignetteRadarDataStatus == false
    and defaults.vignetteRadarLensEnabled == false
    and defaults.vignetteRadarLensCategory == "quest"
    and defaults.vignetteRadarRouteDraftStops == 5
    and defaults.vignetteRadarRouteDraftRange == 1200,
    "wayfinding additions need conservative opt-in defaults")
assert(defaults.vignetteRadarAlerts == true and defaults.vignetteRadarAlertSound == false
    and defaults.vignetteRadarAlertCategories.rare == true
    and defaults.vignetteRadarAlertCategories.treasure == true
    and defaults.vignetteRadarAlertCategories.event == false
    and defaults.vignetteRadarAlertCategories.other == false
    and defaults.vignetteRadarAlertCooldown == 60,
    "alert preferences need safe standalone defaults")
assert(type(defaults.vignetteRadarFavorites) == "table" and type(defaults.vignetteRadarIgnored) == "table"
    and type(defaults.vignetteRadarHiddenMarkerNames) == "table"
    and type(defaults.vignetteRadarHiddenMarkerTypes) == "table"
    and defaults.vignetteRadarLastSeen == true and defaults.vignetteRadarLastSeenSeconds == 10
    and defaults.vignetteRadarQuietCombat == true and defaults.vignetteRadarQuietInstances == true
    and defaults.vignetteRadarKeepVisibleCombat == false
    and defaults.vignetteRadarCircleOnly == true
    and defaults.vignetteRadarMarkerSize == 7 and defaults.vignetteRadarShapes == true
    and defaults.vignetteRadarShowHealth == true,
    "feature preferences need complete defaults")
defaults.vignetteRadarCircleOnly = false
fresh.ValidateSettings()
assert(defaults.vignetteRadarCircleOnly == false and defaults.vignetteRadarMainViewMigrated == true,
    "the one-time main-view migration must preserve later internal compatibility choices")
defaults.vignetteRadarAlertCooldown = -100
defaults.vignetteRadarLastSeenSeconds = 10000
defaults.vignetteRadarMarkerSize = 100
defaults.vignetteRadarScale = 99
fresh.ValidateSettings()
assert(defaults.vignetteRadarAlertCooldown == 5 and defaults.vignetteRadarLastSeenSeconds == 60
    and defaults.vignetteRadarMarkerSize == 9 and defaults.vignetteRadarScale == 1.8,
    "numeric preferences must stay inside supported bounds")

-- GetSettings is a cached fast path: it skips validation until invalidated
-- or until the saved table itself is replaced.
defaults.vignetteRadarScale = 99
assert(fresh.GetSettings() == defaults and defaults.vignetteRadarScale == 99,
    "cached settings must not revalidate on every read")
fresh.InvalidateSettings()
assert(fresh.GetSettings() == defaults and defaults.vignetteRadarScale == 1.8,
    "invalidated settings must be clamped again on the next read")
VignetteRadarDB = { vignetteRadarScale = 99 }
local swapped = fresh.GetSettings()
assert(swapped == VignetteRadarDB and swapped.vignetteRadarScale == 1.8
    and swapped.vignetteRadarEnabled == true,
    "a replaced SavedVariables table must be validated before use")

VignetteRadarDB = { vignetteRadarQuietCombat = false,
    vignetteRadarCircleOnly = false, vignetteRadarLayout = "squat",
    vignetteRadarPosition = { x = 17, y = -34 } }
local migrated = {}
assert(loadfile(sourcePath))("VignetteRadar", migrated)
assert(migrated.GetSettings().vignetteRadarKeepVisibleCombat == true,
    "existing users who disabled combat quiet mode should retain a visible radar")
assert(VignetteRadarDB.vignetteRadarCircleOnly == true
    and VignetteRadarDB.vignetteRadarLayout == "classic"
    and VignetteRadarDB.vignetteRadarCirclePosition.x == 17
    and VignetteRadarDB.vignetteRadarCirclePosition.y == -34,
    "existing full-frame users must migrate once to the rounded main view at their saved position")

VignetteRadarDB = { vignetteRadarPOISource = "auto" }
local oldAuto = {}
assert(loadfile(sourcePath))("VignetteRadar", oldAuto)
assert(oldAuto.GetSettings().vignetteRadarMapNotesVisible == false,
    "the old automatic pack default should become hidden on existing installs")
VignetteRadarDB = { vignetteRadarPOISource = "ChosenPack" }
local chosenPack = {}
assert(loadfile(sourcePath))("VignetteRadar", chosenPack)
assert(chosenPack.GetSettings().vignetteRadarMapNotesVisible == true,
    "an explicitly selected map pack should stay visible")
VignetteRadarDB = { vignetteRadarPOISource = "auto",
    vignetteRadarPOIZoneSources = { [123] = "ChosenPack" } }
local chosenZone = {}
assert(loadfile(sourcePath))("VignetteRadar", chosenZone)
assert(chosenZone.GetSettings().vignetteRadarMapNotesVisible == true,
    "a zone-specific map-pack choice should stay visible")

io.write("vignette radar settings migration tests passed\n")

-- Guide Panel migration: the retired panels' toggles become blocks, the
-- route card's spot (or the strip's) becomes the panel's, once.
do
    local function Migrate(saved)
        VignetteRadarDB = saved
        local module = {}
        assert(loadfile(sourcePath))("VignetteRadar", module)
        return module.GetSettings(), module
    end
    local db = Migrate({ vignetteRadarRouteArrow = false, vignetteRadarStopStrip = true,
        vignetteRadarWorthCard = false, vignetteRadarZoneBriefing = false,
        vignetteRadarRouteHorizonExpanded = false,
        vignetteRadarPanelLayout = { stopStrip = { detached = true, locked = true, x = 40, y = -300 },
            worthCard = { detached = true }, zoneBriefing = { locked = true } } })
    assert(db.vignetteRadarGuidePanel == true and db.vignetteRadarGuideDensity == "compact"
        and db.vignetteRadarGuideBlocks.stops == true and db.vignetteRadarGuideBlocks.facts == false
        and db.vignetteRadarGuideBlocks.briefing == false and db.vignetteRadarGuideBlocks.step == true,
        "the strip alone becomes a compact panel with stops and no facts or briefing")
    local guide = db.vignetteRadarPanelLayout.guide
    assert(guide and guide.detached == true and guide.locked == true and guide.x == 40 and guide.y == -300
        and db.vignetteRadarPanelLayout.stopStrip == nil and db.vignetteRadarPanelLayout.worthCard == nil
        and db.vignetteRadarPanelLayout.zoneBriefing == nil,
        "with the route card off, the strip's spot moves to the panel and old records go")

    db = Migrate({ vignetteRadarRouteArrow = true, vignetteRadarStopStrip = false,
        vignetteRadarWorthCard = true, vignetteRadarZoneBriefing = true,
        vignetteRadarRouteHorizonExpanded = true,
        vignetteRadarRouteArrowPosition = { x = 300, y = -200, layout = 2 },
        vignetteRadarPanelLayout = { routeCard = { locked = true }, stopStrip = { x = 1, y = -1 } } })
    guide = db.vignetteRadarPanelLayout.guide
    assert(db.vignetteRadarGuideDensity == "expanded" and db.vignetteRadarGuideBlocks.stops == true
        and db.vignetteRadarGuideBlocks.facts == true,
        "Upcoming Stops on keeps the stops block in the full layout")
    assert(guide.detached == true and guide.locked == true and guide.x == 300 and guide.y == -200
        and db.vignetteRadarRouteArrowPosition == nil and db.vignetteRadarPanelLayout.routeCard == nil,
        "the floating route card's spot and lock carry over to the panel")

    db = Migrate({ vignetteRadarRouteArrow = true, vignetteRadarRouteArrowPosition = { x = 151, y = -90 } })
    guide = db.vignetteRadarPanelLayout.guide
    assert(guide.x == 100 and guide.y == -100, "an old-layout card spot gets the same nudge the card gave it")

    db = Migrate({ vignetteRadarRouteArrow = false, vignetteRadarStopStrip = false,
        vignetteRadarWorthCard = false, vignetteRadarZoneBriefing = false })
    assert(db.vignetteRadarGuidePanel == false and db.vignetteRadarPanelLayout.guide == nil,
        "every old panel off keeps the Guide Panel off, docked by default")

    -- One shot: a later choice is never migrated again.
    db.vignetteRadarGuidePanel = true
    db.vignetteRadarRouteArrow = false
    local again, module = Migrate(db)
    module.ValidateSettings()
    assert(again.vignetteRadarGuidePanel == true, "the migration runs once")

    -- Validation: bad values reset; the order keeps every block once.
    again.vignetteRadarGuideStops, again.vignetteRadarGuideWidth = 9, 123
    again.vignetteRadarGuideBlocks = { facts = false, bogus = true }
    again.vignetteRadarGuideOrder = { "stops", "stops", "step" }
    module.ValidateSettings()
    assert(again.vignetteRadarGuideStops == 3 and again.vignetteRadarGuideWidth == 260
        and again.vignetteRadarGuideBlocks.bogus == nil and again.vignetteRadarGuideBlocks.facts == false
        and again.vignetteRadarGuideBlocks.notice == true and again.vignetteRadarGuideBlocks.compass == false,
        "Guide Panel numbers and block switches validate; the compass strip starts off")
    assert(#again.vignetteRadarGuideOrder == 7 and again.vignetteRadarGuideOrder[1] == "step",
        "a broken block order falls back to the default")
    -- An order saved before the compass block existed keeps its own order;
    -- compass goes in after stops.
    again.vignetteRadarGuideOrder = { "notice", "step", "facts", "stops", "briefing", "actions" }
    module.ValidateSettings()
    assert(again.vignetteRadarGuideOrder[1] == "notice" and again.vignetteRadarGuideOrder[5] == "compass"
        and #again.vignetteRadarGuideOrder == 7, "a valid block order is kept; new blocks slot in")
end
