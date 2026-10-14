local addon = {}
local settings = {
    vignetteRadarWorldFocusEnabled = true,
    vignetteRadarWorldFocusAutoAdvance = true,
    vignetteRadarWorldFocusRoutes = true,
    vignetteRadarWorldFocusSavedNotes = true,
    vignetteRadarWorldFocusZygor = true,
    vignetteRadarWorldFocusArrivalRadius = 20,
    vignetteRadarAutoRouteArrivalRadius = 10,
    vignetteRadarAutoRouteMapNotes = true,
}
addon.GetSettings = function() return settings end
local routeNotes = {}
addon.ShowVignetteRadarRouteNote = function(label, message, objective)
    routeNotes[#routeNotes + 1] = { label, message, objective }
end
local waypoint, placed = nil, {}
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
    return { uiMapID = mapID, position = { x = x, y = y } }
end }
C_Map = {
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point)
        waypoint = point
        placed[#placed + 1] = point.position.x
        return true
    end,
    GetUserWaypoint = function() return waypoint end,
    ClearUserWaypoint = function() waypoint = nil end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Data/QuestService.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
local focus = addon.VignetteRadarWorldFocus
local function Step(x)
    return { mapID = 123, mapX = x / 1000, mapY = .5,
        worldX = x, worldY = 500, instanceID = 42 }
end
local treasure = Step(500)
treasure.kind, treasure.name, treasure.key = "treasure", "Hidden cache", "pack:123:50005000"
treasure.route = { Step(400), Step(450), Step(500) }
local entrance = Step(400)
entrance.kind, entrance.parentCoord, entrance.source = "entrance", 50005000, "pack"
local player = { worldX = 300, worldY = 500, instanceID = 42 }
focus.Sync(123, player, {}, {}, { treasure, entrance })
assert(focus.SelectNote(entrance) and placed[1] == .4
    and focus.Status():find("100 yd", 1, true)
    and focus.Status():find("1/3", 1, true),
    "clicking a linked entrance should begin the parent treasure's complete path")
assert(routeNotes[#routeNotes][1] == "WORLD FOCUS"
    and routeNotes[#routeNotes][2]:find("Hidden cache", 1, true),
    "focusing a mapped route should announce its destination")
player.worldX = 396.9
focus.Sync(123, player, {}, {}, { treasure, entrance })
assert(#placed == 1,
    "a linked treasure path must wait until the player is within 3 yards of its stop")
player.worldX = 397.1
focus.Sync(123, player, {}, {}, { treasure, entrance })
assert(placed[2] == .45 and focus.Status():find("2/3", 1, true),
    "entering 3 yards should advance exactly one explicitly supplied treasure-path step")
assert(routeNotes[#routeNotes][1] == "NEXT STEP"
    and routeNotes[#routeNotes][2]:find("2/3", 1, true),
    "route notes should describe automatic step changes")
player.worldX = 410
local routeNoteCount = #routeNotes
focus.Sync(123, player, {}, {}, { treasure, entrance })
assert(#placed == 2 and #routeNotes == routeNoteCount,
    "remaining inside the arrival radius must not skip stops or repeat the note")
player.worldX = 450
focus.Sync(123, player, {}, {}, { treasure, entrance })
assert(placed[3] == .5 and focus.Status():find("3/3", 1, true),
    "the final waypoint must point at the treasure")

focus.SelectNote(treasure)
assert(placed[4] == .4)
waypoint = UiMapPoint.CreateFromCoordinates(123, .9, .9)
player.worldX = 400
focus.Sync(123, player, {}, {}, { treasure, entrance })
assert(#placed == 4 and not focus.Status():find("/3", 1, true),
    "a manually changed waypoint must stop automatic route ownership")

local rareA, rareB, rareNote = Step(600), Step(800), Step(900)
rareA.kind, rareA.key, rareA.name = "rare", "live:600", "First rare"
rareB.kind, rareB.key, rareB.name = "rare", "live:800", "Second rare"
rareA.category, rareB.category = "rare", "rare"
rareNote.kind, rareNote.key, rareNote.name = "mob", "pack:900", "Saved rare"
player.worldX = 300
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(focus.SelectTarget({ key = rareA.key, name = rareA.name, category = rareA.kind,
    mapID = rareA.mapID, mapX = rareA.mapX, mapY = rareA.mapY,
    worldX = rareA.worldX, worldY = rareA.worldY, instanceID = rareA.instanceID }))
local focusedKind, focusedState = focus.GetRouteChoice()
assert(focusedKind == "rare" and focusedState == "focus",
    "a manually focused point should identify its category before Auto Route starts")
assert(focus.ToggleRoute() and focus.IsRouteActive(), "route button should use the last clicked rare")
local chosenKind, chosenState = focus.GetRouteChoice()
assert(chosenKind == "rare" and chosenState == "active",
    "the route chooser should identify the active route category")
local routePoint, routeKind, routeName, routeIndex, routeCount = focus.GetRoutePoint()
assert(routePoint and routePoint.worldX == 600 and routeKind == "rare"
    and routeName == "First rare" and routeIndex == 1 and routeCount == 1,
    "the route pointer should receive the current stop and its node readout")
local pauseOk, pauseReason = focus.ToggleRoute()
assert(not pauseOk and pauseReason:find("paused", 1, true)
    and focus.IsRoutePaused() and not focus.IsRouteActive()
    and focus.Status():find("paused", 1, true)
    and focus.GetRoutePoint() == nil,
    "pausing should keep the route's visited state and explain its status")
assert(routeNotes[#routeNotes][2]:find("Paused", 1, true),
    "pausing should show a brief route note")
chosenKind, chosenState = focus.GetRouteChoice()
assert(chosenKind == "rare" and chosenState == "paused",
    "the route chooser should retain a visible choice while the route is paused")
player.worldX = 600
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(waypoint.position.x == .6 and focus.IsRoutePaused(),
    "arriving while paused must not advance through a waypoint")
player.worldX = 300
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(focus.ToggleRoute() and focus.IsRouteActive() and not focus.IsRoutePaused(),
    "resuming should continue the paused route")
focus.Sync(123, { worldX = nil, worldY = nil, instanceID = 42 }, { rareA, rareB }, {}, {})
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
player.worldX = 589.9
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(waypoint.position.x == .6,
    "the current map pin must remain until Auto Route is within 10 yards")
player.worldX = 590.1
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(waypoint.position.x == .6,
    "an engaged rare must stay current at arrival until killed, cleared, or skipped")
addon.VignetteRadarRecent = { IsHidden = function(item) return item.key == rareA.key end }
player.worldX = 589.9
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(waypoint.position.x == .6,
    "a matching clear outside the selected rare radius must not jump the route")
player.worldX = 590.1
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(waypoint.position.x == .8,
    "a recorded rare kill should advance to the next stop")
addon.VignetteRadarRecent = nil
player.worldX = 800
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(waypoint.position.x == .8, "arriving at the next rare must keep that target current")
assert(focus.SkipRouteStop() and waypoint.position.x == .9,
    "rare route should continue into the selected map pack after a confirmed skip")
waypoint = UiMapPoint.CreateFromCoordinates(123, .97, .5)
focus.Sync(123, player, { rareA, rareB }, {}, { rareNote })
assert(not focus.IsRouteActive(), "a manually replaced waypoint must stop Auto Route")

local questA, questNext, questB = Step(350), Step(500), Step(700)
settings.vignetteRadarAutoRouteQuestNearest = false -- Preserve the legacy same-quest route scenario below.
settings.vignetteRadarAutoRouteQuestMoveOn = "each" -- Legacy: each finished objective picks a new stop.
settings.vignetteRadarAutoRouteNearbyZones = false
settings.vignetteRadarAutoRouteQuestStarts = false
questA.questID, questNext.questID, questB.questID = 11, 11, 22
questA.name, questNext.name, questB.name = "First quest", "First quest", "Second quest"
questA.objectiveText, questNext.objectiveText = "Meet Riftblade Maella", "Meet Riftblade Maella"
local questDone = {}
local questActive, questTurnedIn = { [11] = true, [22] = true }, {}
local firstQuestObjective = { finished = false, numFulfilled = 0 }
C_QuestLog = {
    IsComplete = function(id) return questDone[id] == true end,
    IsOnQuest = function(id) return questActive[id] == true end,
    IsQuestFlaggedCompleted = function(id) return questTurnedIn[id] == true end,
    GetQuestObjectives = function() return { firstQuestObjective } end,
}
player.worldX = 300
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
local questSelected = focus.SelectQuest(11)
player.worldX = 350
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .35 and focus.HasFocus(),
    "a focused quest point must not clear merely because the player reached its coordinates")
player.worldX = 300
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
local questStarted, questReason = focus.ToggleRoute()
assert(questSelected and questStarted, "a clicked quest should anchor the quest route: " .. tostring(questReason))
local questHorizon = focus.GetHorizon()
assert(questHorizon[1] and questHorizon[1].label == "Meet Riftblade Maella"
    and not questHorizon[2],
    "the preview must show the objective and never repeat it as the next step")
player.worldX = 350
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .35,
    "arriving at an unfinished quest objective must keep its waypoint")
firstQuestObjective.finished = true
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .5,
    "completing a quest objective should choose the nearest remaining point")
assert(focus.PreviousQuestStep() and waypoint.position.x == .35,
    "Previous Quest Step should revisit an earlier point that still exists")
assert(focus.NextQuestStep() and waypoint.position.x == .5,
    "Next Quest Step should restore the point reached before stepping backward")
focus.Sync(123, player, {}, { questNext, questB }, {})
local previousOk, previousReason = focus.PreviousQuestStep()
assert(not previousOk and previousReason:find("still available", 1, true)
    and waypoint.position.x == .5,
    "Previous Quest Step must leave the pin alone when the old point has disappeared")
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
player.worldX = 500
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .5 and focus.GetRoutePoint(),
    "arriving at the next unfinished objective must not skip to another quest")
firstQuestObjective.finished = false
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .5,
    "a quest stage reset must not count as a newly completed objective")
firstQuestObjective.finished = true
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .5 and focus.Status():find("Waiting", 1, true)
    and focus.GetRoutePoint() == nil,
    "completed quest points must not loop back to an earlier objective")
focus.Sync(123, { worldX = nil, worldY = nil, instanceID = 42 },
    {}, { questA, questNext, questB }, {})
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
questDone[11] = true
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .7, "a quest with every objective done should advance to the next available quest")
questActive[11], questTurnedIn[11] = nil, true
focus.Sync(123, player, {}, { questA, questNext, questB }, {})
assert(waypoint.position.x == .7, "turning in the finished quest must not move the route again")
assert(not focus.PreviousQuestStep() and waypoint.position.x == .7,
    "the back hotkey must not reopen a quest that was already turned in")
assert(focus.IsQuestRoute() and focus.SkipQuest()
    and not focus.IsRouteActive() and not focus.HasFocus() and waypoint == nil,
    "Skip Quest should move past a stuck quest and clear the final owned pin")
settings.vignetteRadarAutoRouteQuestMoveOn = nil

local objectiveFar, objectiveNear, objectiveNext = Step(400), Step(320), Step(520)
for _, objective in ipairs({ objectiveFar, objectiveNear, objectiveNext }) do
    objective.questID, objective.name = 33, "Three objectives"
end
questActive[33] = true
local objectiveProgress = { finished = false, numFulfilled = 0 }
C_QuestLog.GetQuestObjectives = function() return { objectiveProgress } end
player.worldX = 300
focus.Sync(123, player, {}, { objectiveFar, objectiveNear, objectiveNext }, {})
assert(focus.SelectQuest(33) and waypoint.position.x == .32,
    "choosing a quest by name should pin its closest objective")
assert(focus.ToggleRoute(), "the closest quest objective should start an Auto Route")
objectiveProgress.numFulfilled = 1
focus.Sync(123, player, {}, { objectiveFar, objectiveNear, objectiveNext }, {})
assert(waypoint.position.x == .32,
    "partial objective progress must keep the current waypoint")
objectiveProgress.finished = true
focus.Sync(123, player, {}, { objectiveFar, objectiveNear, objectiveNext }, {})
assert(waypoint.position.x == .4,
    "finishing an objective should pick the nearest remaining quest point")
assert(focus.Clear(), "the objective route should release its waypoint")
objectiveProgress.finished = false
focus.Sync(123, player, {}, { objectiveFar, objectiveNear, objectiveNext }, {})
assert(focus.SelectQuest(33) and focus.ToggleRoute() and waypoint.position.x == .32,
    "a fresh quest route should begin at its closest point")
assert(focus.NextQuestStep() and waypoint.position.x == .4,
    "Next Quest Step should move to another available point without completing the quest")
assert(focus.PreviousQuestStep() and waypoint.position.x == .32
    and focus.NextQuestStep() and waypoint.position.x == .4,
    "manual next, previous, and forward navigation should preserve the route order")
assert(focus.Clear() and not focus.PreviousQuestStep(),
    "quest-step hotkeys should not act without an active quest route")
focus.Sync(123, player, {}, { questA, questNext, questB }, {})

local customWaypoint
WaypointUIAPI = { Navigation = { NewUserNavigation = function(options)
    customWaypoint = options
    waypoint = UiMapPoint.CreateFromCoordinates(options.mapID, options.x / 100, options.y / 100)
    return { mapID = options.mapID, x = options.x, y = options.y }
end } }
settings.vignetteRadarWorldFocusThemedWaypoint = true
settings.vignetteRadarQuestColors = true
addon.VignetteRadarQuestColors = { { .2, .3, .4 }, { .3, .4, .5 }, { .4, .5, .6 } }
addon.VignetteRadarStyle = { Color = function(slot)
    if slot == "rare" then return .9, .2, .1 end
    if slot == "treasure" then return .8, .6, .1 end
    return .5, .8, .7
end }
questB.colorSlot = 3
assert(focus.SelectQuest(22) and customWaypoint
    and customWaypoint.iconTexture == nil
    and customWaypoint.r == .4 and customWaypoint.g == .5 and customWaypoint.b == .6
    and customWaypoint.x == 70 and customWaypoint.y == 50,
    "WaypointUI should receive quest color and its own unobstructed icon")
assert(focus.SelectTarget({ key = rareA.key, name = rareA.name, category = rareA.kind,
    mapID = rareA.mapID, mapX = rareA.mapX, mapY = rareA.mapY,
    worldX = rareA.worldX, worldY = rareA.worldY, instanceID = rareA.instanceID })
    and customWaypoint.iconTexture == nil and customWaypoint.r == .9,
    "rare waypoints should use their theme color without drawing over the nameplate")
assert(focus.SelectNote(treasure) and customWaypoint.iconTexture == nil
    and customWaypoint.r == .8 and customWaypoint.g == .6,
    "treasure approach waypoints should preserve color and WaypointUI layout")
assert(focus.Advance() and focus.Advance() and customWaypoint.iconTexture == nil,
    "the final treasure stop should retain WaypointUI's legible native icon")
settings.vignetteRadarAutoRouteOnSelect = true
assert(focus.SelectTarget({ key = rareA.key, name = rareA.name, category = rareA.kind,
    mapID = rareA.mapID, mapX = rareA.mapX, mapY = rareA.mapY,
    worldX = rareA.worldX, worldY = rareA.worldY, instanceID = rareA.instanceID })
    and focus.IsRouteActive(), "the opt-in setting should start routing on a marker click")
settings.vignetteRadarAutoRouteOnSelect = false
focus.ToggleRoute()

WaypointUIAPI = nil
local liveChest, packChest = Step(500), Step(520)
liveChest.category, liveChest.key, liveChest.name = "treasure", "live:chest", "Live chest"
packChest.kind, packChest.key, packChest.name = "treasure", "pack:chest", "Pack chest"
packChest.route = { Step(400), Step(520) }
player.worldX = 100
focus.Sync(123, player, { liveChest }, {}, { packChest })
assert(focus.SelectTarget({ key = liveChest.key, name = liveChest.name,
    category = liveChest.category, mapID = liveChest.mapID,
    mapX = liveChest.mapX, mapY = liveChest.mapY,
    worldX = liveChest.worldX, worldY = liveChest.worldY,
    instanceID = liveChest.instanceID }) and waypoint.position.x == .4,
    "the preferred live treasure should inherit a nearby pack's entrance path")

local start, cave, direct = Step(300), Step(400), Step(550)
start.kind, start.key, start.name = "treasure", "start", "Starting cache"
cave.kind, cave.key, cave.name = "treasure", "cave", "Cave cache"
cave.route = { Step(500), Step(400) }
direct.kind, direct.key, direct.name = "treasure", "direct", "Open cache"
settings.vignetteRadarAutoRouteTravel = "ground"
player.worldX = 100
focus.Sync(123, player, {}, {}, { start, cave, direct })
assert(focus.SelectNote(start) and focus.ToggleRoute())
player.worldX = 300
focus.Sync(123, player, {}, {}, { start, cave, direct })
assert(waypoint.position.x == .55,
    "ground mode should account for a pack's entrance path when ordering stops")
settings.vignetteRadarAutoRouteTravel = "flying"
player.worldX = 100
focus.Sync(123, player, {}, {}, { start, cave, direct })
assert(focus.SelectNote(start))
assert(focus.ToggleRoute())
player.worldX = 300
focus.Sync(123, player, {}, {}, { start, cave, direct })
assert(waypoint.position.x == .5,
    "flying mode should favor the closer entrance when path length is less costly")

do
    local rare, chest, quest = Step(320), Step(330), Step(340)
    rare.key, rare.name, rare.category = "nearest-rare", "Nearby rare", "rare"
    chest.key, chest.name, chest.kind = "nearest-chest", "Nearby chest", "treasure"
    quest.questID, quest.name = 77, "Nearby quest"
    questActive[77] = true
    player.worldX = 300
    focus.Sync(123, player, { rare }, { quest }, { chest })
    assert(focus.StartNearest("rare") and waypoint.position.x == .32 and focus.IsRouteActive(),
        "the route chooser should start a rare route without first clicking a marker")
    assert(focus.StartNearest("treasure") and waypoint.position.x == .33 and focus.IsRouteActive(),
        "the route chooser should include saved treasure locations")
    settings.vignetteRadarAutoRouteOnSelect = true
    assert(focus.StartNearest("quest") and waypoint.position.x == .34 and focus.IsRouteActive(),
        "the chooser must not pause a route already started by auto-route-on-select")
    settings.vignetteRadarAutoRouteOnSelect = false
    focus.Sync(123, player, {}, {}, {})
    local ok, reason = focus.StartNearest("rare")
    assert(not ok and reason:find("No Eligible Rare", 1, true),
        "the chooser should explain when a route category has no point here")
end

local activeZygorStep = { num = 5, map = 123, current_waypoint_goal_num = 2,
    goals = {
        { map = 123, x = .5, y = .5, text = "First objective", status = "incomplete" },
        { map = 123, x = .6, y = .4, text = "Selected objective", status = "incomplete" },
    } }
ZygorGuidesViewer = { CurrentStep = activeZygorStep, Pointer = {
    current_waypoint = { m = 123, x = .9, y = .9, title = "Unrelated manual point" },
} }
local guide = focus.ZygorNote(123, function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end)
assert(guide and guide.kind == "guide" and guide.worldX == 600
    and guide.name == "Selected objective"
    and not focus.ZygorNote(124, function() error("wrong map") end, function() end),
    "the selected, same-map guide objective should win over Zygor's manual arrow")
player.worldX = 300
focus.Sync(123, player, {}, {}, {})
assert(focus.SelectNote(guide, true))
player.worldX = 600
focus.Sync(123, player, {}, {}, {})
assert(focus.HasFocus() and waypoint.position.x == .6,
    "arriving at a Zygor objective must keep the pin until its guide step changes")
player.worldX = 300
activeZygorStep.goals[2].status = "complete"
local nextGoal = focus.ZygorNote(123, function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end)
assert(nextGoal and nextGoal.mapX == .5,
    "a completed selected goal should yield to the next incomplete objective")
activeZygorStep.goals[1].status = "complete"
local waiting, waitingReason = focus.ZygorNote(123, function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end, true, true)
assert(not waiting and waitingReason == "Waiting for Zygor's next guide step",
    "all completed goals must wait for Zygor rather than repin a finished objective")
activeZygorStep.goals[1].status = "incomplete"
activeZygorStep.goals[2].status = "incomplete"
activeZygorStep.waypath = { coords = {
    { map = 123, x = .3, y = .5 }, { map = 123, x = .45, y = .5 },
} }
local travel = focus.ZygorNote(123, function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end, true, true, "travel")
assert(travel and travel.mapX == .45 and travel.name == "Travel Stop 2/2",
    "travel mode should advance past a nearby path node instead of pinning the objective")
activeZygorStep.waypath = nil
settings.vignetteRadarWorldFocusZygor = false
assert(not focus.ZygorNote(123, function() error("hidden guide") end, function() end),
    "the guide dot toggle should still hide Zygor from the radar")
assert(focus.ZygorNote(123, function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end, true),
    "directly pinning Zygor should work even when its guide dot is hidden")
activeZygorStep.goals[2].GetWaypoint = function()
    return { m = 125, x = .61, y = .41 }
end
local normalized = focus.ZygorNote(123, function() return nil end,
    function(x, y) return { x = x, y = y } end, true, true)
assert(normalized and normalized.mapID == 125 and normalized.mapX == .61,
    "direct pinning should honor Zygor's resolved waypoint for the selected goal")
activeZygorStep.goals[2].GetWaypoint = nil
activeZygorStep.goals[2].map = 124
local remoteGuide = focus.ZygorNote(123, function() return nil end,
    function(x, y) return { x = x, y = y } end, true, true)
settings.vignetteRadarWorldFocusEnabled = false
assert(remoteGuide and remoteGuide.mapID == 124 and remoteGuide.worldX == nil
    and focus.SelectNote(remoteGuide, true) and waypoint.uiMapID == 124,
    "direct pinning should use the selected step's map even when marker focus is disabled")
assert(routeNotes[#routeNotes][1] == "ZYGOR STEP"
    and routeNotes[#routeNotes][2] == "Selected objective",
    "pinning the active Zygor objective should announce its text")
settings.vignetteRadarWorldFocusEnabled = true
focus.Sync(124, { worldX = 300, worldY = 500, instanceID = 42 }, {}, {}, {})
activeZygorStep.goals[2].x = nil
activeZygorStep.goals[1].map = nil
local objective = focus.ZygorNote(123, function() return nil end,
    function(x, y) return { x = x, y = y } end, true, true)
assert(objective and objective.mapID == 123 and objective.mapX == .5,
    "an unmapped selected goal should use another incomplete goal and inherit its step map")
activeZygorStep.goals = {}
activeZygorStep.waypath = { coords = { { map = 124, x = .7, y = .3 } } }
assert(focus.ZygorNote(123, function() return nil end,
    function(x, y) return { x = x, y = y } end, true, true).mapX == .7,
    "a guide step with no goal coordinates should use its own travel path")
activeZygorStep.waypath = nil
ZygorGuidesViewer.Pointer.current_waypoint = { m = 124, x = .8, y = .2,
    goal = { parentStep = activeZygorStep } }
assert(focus.ZygorNote(123, function() return nil end,
    function(x, y) return { x = x, y = y } end, true, true).mapX == .8,
    "a goal-owned pointer remains a last fallback for this guide step")
ZygorGuidesViewer.Pointer.current_waypoint = { m = 123, x = .9, y = .9,
    title = "Unrelated manual point" }
local missing, reason = focus.ZygorNote(124, function() end,
    function(x, y) return { x = x, y = y } end, true, true)
assert(not missing and reason == "Current Zygor step has no mapped location",
    "an unrelated manual arrow must not masquerade as the selected guide step")
ZygorGuidesViewer.CurrentStep = nil
local noStep, noStepReason = focus.ZygorNote(124, function() end,
    function(x, y) return { x = x, y = y } end, true, true)
assert(not noStep and noStepReason == "Zygor has no active guide step",
    "a missing guide step should explain why pinning cannot proceed")
local remoteQuest = Step(650)
remoteQuest.questID, remoteQuest.name, remoteQuest.mapID = 81, "Nearby map quest", 124
focus.Sync(123, player, {}, { remoteQuest }, {})
assert(focus.SelectQuest(81) and waypoint.uiMapID == 124,
    "quest focus must keep the quest point's map instead of replacing it with the player's map")
assert(focus.HasFocus() and focus.Clear() and not focus.HasFocus() and waypoint == nil,
    "clear focus should remove only the waypoint currently owned by the addon")
assert(focus.SelectQuest(81))
waypoint = UiMapPoint.CreateFromCoordinates(124, .1, .1)
assert(focus.Clear() and waypoint.position.x == .1,
    "clearing addon focus must preserve a waypoint another addon or the player set")
do
    local live = Step(700)
    live.key, live.category, live.name = "valid-live", "rare", "Valid rare"
    local incomplete = { key = "missing-coordinate", kind = "mob", mapID = 123 }
    player.worldX = 690
    focus.Sync(123, player, { live }, {}, { incomplete })
    assert(focus.StartNearest("rare") and waypoint.position.x == .7,
        "incomplete map notes must not break duplicate checking or valid rare routes")
end
do
    local first, second = Step(500), Step(600)
    first.kind, first.key, first.name = "treasure", "range:first", "First cache"
    second.kind, second.key, second.name = "treasure", "range:second", "Second cache"
    player.worldX = 480
    focus.Sync(123, player, {}, {}, { first, second })
    assert(focus.SelectNote(first) and focus.ToggleRoute() and waypoint.position.x == .5,
        "treasure Auto Route should start at the selected cache")
    player.worldX = 496.9
    focus.Sync(123, player, {}, {}, { first, second })
    assert(waypoint.position.x == .5,
        "treasure Auto Route must keep its stop at 3.1 yards even with rare distance set to 10")
    player.worldX = 497.1
    focus.Sync(123, player, {}, {}, { first, second })
    assert(waypoint.position.x == .6,
        "treasure Auto Route should continue after entering 3 yards")
    assert(focus.Clear())
end
do
    local looted, nextChest = Step(500), Step(600)
    looted.kind, looted.key, looted.name, looted.objectID =
        "treasure", "loot:first", "First cache", 777
    nextChest.kind, nextChest.key, nextChest.name =
        "treasure", "loot:second", "Second cache"
    player.worldX = 496
    focus.Sync(123, player, {}, {}, { looted, nextChest })
    assert(focus.SelectNote(looted) and focus.ToggleRoute()
        and waypoint.position.x == .5)
    GetTime = function() return 100 end
    GetNumLootItems = function() return 1 end
    GetLootSourceInfo = function() return "Creature-0-1-1-1-777-000" end
    focus.OnLootEvent("LOOT_OPENED")
    assert(not focus.OnLootEvent("LOOT_SLOT_CLEARED") and waypoint.position.x == .5,
        "looting a nearby creature must not consume a treasure route stop")
    GetLootSourceInfo = function() return "GameObject-0-1-1-1-999-000" end
    focus.OnLootEvent("LOOT_OPENED")
    assert(not focus.OnLootEvent("LOOT_SLOT_CLEARED") and waypoint.position.x == .5,
        "a different nearby container must not consume the saved treasure")
    GetLootSourceInfo = function() return "GameObject-0-1-1-1-777-000" end
    focus.OnLootEvent("LOOT_OPENED")
    assert(focus.OnLootEvent("LOOT_SLOT_CLEARED") and waypoint.position.x == .6,
        "looting the matched nearby treasure should advance even outside 3 yards")
end
do
    local rare, cache, objective = Step(330), Step(320), Step(315)
    rare.key, rare.name, rare.category = "closest:rare", "Nearby rare", "rare"
    cache.key, cache.name, cache.kind = "closest:cache", "Nearby cache", "treasure"
    objective.questID, objective.name = 99, "Nearby objective"
    local progress = { finished = false, numFulfilled = 0 }
    questActive[99], questDone[99], questTurnedIn[99] = true, false, false
    C_QuestLog.GetQuestObjectives = function() return { progress } end
    player.worldX = 300
    focus.Sync(123, player, { rare }, { objective }, { cache })
    assert(focus.StartNearest("closest") and waypoint.position.x == .315
        and focus.GetRouteChoice() == "closest"
        and select(2, focus.GetRoutePoint()) == "quest",
        "Closest should start at the nearest eligible point and expose its actual type")
    progress.finished = true
    focus.Sync(123, player, { rare }, { objective }, { cache })
    assert(waypoint.position.x == .315 and select(2, focus.GetRoutePoint()) == "quest",
        "a completed objective must keep the quest as the Closest stop until turn-in")
    questActive[99], questTurnedIn[99] = false, true
    focus.Sync(123, player, { rare }, { objective }, { cache })
    assert(waypoint.position.x == .32 and select(2, focus.GetRoutePoint()) == "treasure",
        "turning the quest in should let Closest choose the next nearest type")
    player.worldX = 316.9
    focus.Sync(123, player, { rare }, { objective }, { cache })
    assert(waypoint.position.x == .32,
        "a treasure stop in Closest must keep its three-yard arrival rule")
    player.worldX = 317.1
    focus.Sync(123, player, { rare }, { objective }, { cache })
    assert(waypoint.position.x == .33 and select(2, focus.GetRoutePoint()) == "rare",
        "Closest should continue from the treasure to the nearby rare")
    player.worldX = 321
    focus.Sync(123, player, { rare }, { objective }, { cache })
    assert(waypoint.position.x == .33 and select(2, focus.GetRoutePoint()) == "rare",
        "Closest must not switch away from a rare merely because the player engaged it")
    assert(focus.SkipRouteStop(), "a rare can still be advanced explicitly")
    assert(focus.IsRouteActive() and focus.GetRoutePoint() == nil
        and focus.Status():find("Waiting for Nearby Points", 1, true),
        "Closest should remain armed after its current points are exhausted")
    local later = Step(350)
    later.key, later.name, later.kind = "closest:later", "Later cache", "treasure"
    for _ = 1, 2 do
        focus.Sync(123, player, { rare }, { objective }, { cache, later })
    end
    assert(waypoint.position.x == .35 and select(2, focus.GetRoutePoint()) == "treasure",
        "the waiting route should acquire a newly available point without a reload")
    assert(focus.Clear())
    local tiedRare, tiedCache = Step(340), Step(340)
    tiedRare.key, tiedRare.name, tiedRare.category = "closest:tied-rare", "Tied rare", "rare"
    tiedCache.key, tiedCache.name, tiedCache.kind = "closest:tied-cache", "Tied cache", "treasure"
    player.worldX = 300
    focus.Sync(123, player, { tiedRare }, {}, { tiedCache })
    assert(focus.StartNearest("closest") and select(2, focus.GetRoutePoint()) == "rare",
        "equal-distance choices should prefer rare before treasure")
    local horizon = focus.GetHorizon()
    assert(horizon[1] and horizon[1].name == "Tied rare"
        and horizon[2] and horizon[2].name == "Tied cache"
        and focus.ExplainActive():find("cleared or skipped", 1, true),
        "the route horizon must show likely next stops and explain the active stop")
    assert(focus.ToggleRouteLock() and focus.IsRouteLocked())
    player.worldX = 339
    focus.Sync(123, player, { tiedRare }, {}, { tiedCache })
    assert(select(2, focus.GetRoutePoint()) == "rare",
        "locking the current stop must prevent proximity advancement")
    assert(focus.ToggleRouteLock() and not focus.IsRouteLocked())
    focus.Sync(123, player, { tiedRare }, {}, { tiedCache })
    assert(select(2, focus.GetRoutePoint()) == "rare",
        "unlocking must keep a nearby rare current until it is cleared or skipped")
    assert(focus.SkipRouteStop() and select(2, focus.GetRoutePoint()) == "treasure",
        "skipping the rare must resume the mixed route")
    assert(focus.Clear())
end
do
    focus.Clear()
    settings.vignetteRadarAutoRouteQuestMoveOn = "each" -- Old per-objective advancing.
    settings.vignetteRadarAutoRouteQuestNearest = true
    settings.vignetteRadarAutoRouteQuestStarts = true
    settings.vignetteRadarAutoRouteNearbyZones = true
    local first, other = Step(320), Step(400)
    first.questID, first.name = 301, "First objective"
    other.questID, other.name = 303, "Other objective"
    local remote = { kind = "quest", questID = 304, name = "Next zone objective",
        mapID = 124, mapX = .5, mapY = .5,
        worldX = 500, worldY = 500, instanceID = 42 }
    local progress = { [301] = { finished = false },
        [302] = { finished = false }, [303] = { finished = false },
        [304] = { finished = false } }
    questActive[301], questActive[303], questActive[304] = true, true, true
    questActive[302] = false
    C_QuestLog.GetQuestObjectives = function(id) return { progress[id] } end
    addon.VignetteRadarAvailableStarts = { {
        questID = 302, questName = "Available quest", mapID = 123,
        x = .33, y = .5, worldX = 330, worldY = 500, instanceID = 42,
    } }
    addon.VignetteRadarRouteQuests = {
        Tick = function() end,
        Candidates = function() return { remote } end,
    }
    player.worldX = 300
    focus.Sync(123, player, {}, { first, other }, {})
    assert(focus.StartNearest("quest") and waypoint.position.x == .32,
        "quest routing should begin with the nearest objective")
    assert(focus.GetTrackedRouteKind() == "quest",
        "the route button should identify its current quest stop")
    progress[301].finished = true
    focus.Sync(123, player, {}, { first, other }, {})
    assert(waypoint.position.x == .33
        and focus.GetRoutePoint().availableStart == true,
        "after progress, a closer available quest should beat another objective")
    questActive[302] = true
    focus.Sync(123, player, {}, { first, other }, {})
    assert(waypoint.position.x == .4 and focus.GetRoutePoint().questID == 303,
        "accepting the quest should advance to the next closest objective")
    settings.vignetteRadarAutoRouteNearbyZones = false
    progress[303].finished = true
    focus.Sync(123, player, {}, { first, other }, {})
    assert(focus.IsRouteActive() and focus.GetRoutePoint() == nil,
        "disabling nearby zones should keep the quest route waiting locally")
    settings.vignetteRadarAutoRouteNearbyZones = true
    focus.Sync(123, player, {}, { first, other }, {})
    assert(waypoint.uiMapID == 124 and focus.GetRoutePoint().questID == 304,
        "the waiting quest route should pin a known objective in the next zone")
    assert(focus.Clear())
    settings.vignetteRadarAutoRouteQuestMoveOn = nil
end
do
    focus.Clear()
    settings.vignetteRadarAutoRouteQuestNearest = false
    settings.vignetteRadarAutoRouteQuestStarts = true
    settings.vignetteRadarAutoRouteNearbyZones = false
    questActive[305] = false
    local objectiveAvailable = false
    local acceptedObjective = Step(420)
    acceptedObjective.kind, acceptedObjective.questID = "quest", 305
    acceptedObjective.name = "New quest objective"
    addon.VignetteRadarAvailableStarts = { {
        questID = 305, questName = "New quest", mapID = 123,
        x = .33, y = .5, worldX = 330, worldY = 500, instanceID = 42,
    } }
    addon.VignetteRadarRouteQuests = {
        Tick = function() end,
        Candidates = function() return {} end,
        CurrentQuestWaypoint = function(id)
            if objectiveAvailable and id == 305 then return acceptedObjective end
        end,
    }
    player.worldX = 300
    focus.Sync(123, player, {}, {}, {})
    assert(focus.StartNearest("quest") and waypoint.position.x == .33,
        "an available quest may be the only initial route point")
    questActive[305] = true
    focus.Sync(123, player, {}, {}, {})
    assert(focus.IsRouteActive() and focus.GetRoutePoint() == nil
        and focus.Status():find("Waiting for Accepted Quest Objective", 1, true),
        "the route must clearly remain armed while Blizzard's new objective settles")
    objectiveAvailable = true
    focus.Sync(123, player, {}, {}, {})
    assert(waypoint.position.x == .42 and focus.GetRoutePoint().questID == 305,
        "the accepted quest must automatically advance to its next-step waypoint")
    assert(focus.Clear())
end
do
    focus.Clear()
    settings.vignetteRadarAutoRouteQuestNearest = false
    settings.vignetteRadarAutoRouteQuestStarts = false
    settings.vignetteRadarAutoRouteNearbyZones = false
    settings.vignetteRadarAutoRouteQuestMoveOn = "each" -- Old per-objective waiting.
    local first, later = Step(320), Step(460)
    first.questID, first.name = 308, "First stage"
    later.kind, later.questID, later.name = "quest", 308, "Next stage"
    questActive[308] = true
    local progress = { finished = false, numFulfilled = 0 }
    local nextReady = false
    local nextStepReads = 0
    C_QuestLog.GetQuestObjectives = function(id)
        if id == 308 then return { progress } end
        return { { finished = false, numFulfilled = 0 } }
    end
    addon.VignetteRadarRouteQuests = {
        Tick = function() end,
        Candidates = function() return {} end,
        CurrentQuestWaypoint = function(id)
            nextStepReads = nextStepReads + 1
            if id == 308 and nextReady then return later end
        end,
    }
    player.worldX = 300
    focus.Sync(123, player, {}, { first }, {})
    assert(focus.StartNearest("quest") and waypoint.position.x == .32
        and nextStepReads == 0,
        "choosing Quest must not request a new next-step lookup synchronously")
    progress.finished = true
    focus.Sync(123, player, {}, { first }, {})
    assert(focus.IsRouteActive() and focus.GetRoutePoint() == nil
        and focus.GetRouteChoice() == "quest",
        "Quest mode must stay selected while the next objective is unavailable")
    nextReady = true
    focus.Sync(123, player, {}, { first }, {})
    assert(waypoint.position.x == .46 and focus.GetRouteChoice() == "quest",
        "a delayed next step should resume Quest routing without a broad quest-log scan")
    local diagnostic = focus.Diagnostics()
    assert(diagnostic.mode == "quest" and diagnostic.state == "active"
        and diagnostic.questID == 308 and diagnostic.radarPoints == 1,
        "diagnostics should report the route's cached state")
    assert(focus.Clear())
    settings.vignetteRadarAutoRouteQuestMoveOn = nil
end
do
    focus.Clear()
    settings.vignetteRadarWorldFocusSavedNotes = false
    settings.vignetteRadarAutoRouteMapNotes = true
    player.worldX = 300
    local packChest = Step(340)
    packChest.kind, packChest.key, packChest.name = "treasure", "pack:nearby", "Mapped Cache"
    focus.Sync(123, player, {}, {}, { packChest })
    assert(focus.StartNearest("treasure") and waypoint.position.x == .34,
        "Nearest Treasure should use selected map data even if manual focus notes are hidden")
    focus.Clear()
    local parentChest = Step(330)
    parentChest.mapID, parentChest.category, parentChest.key = 124, "treasure", "parent:chest"
    parentChest.name = "Blizzard Map Cache"
    focus.Sync(123, player, { parentChest }, {}, {})
    assert(focus.StartNearest("treasure") and waypoint.uiMapID == 124
        and waypoint.position.x == .33 and focus.GetTrackedRouteKind() == "treasure",
        "a parent-map treasure pin should be routeable from the child zone")
    focus.Clear()
    settings.vignetteRadarWorldFocusSavedNotes = true
end
do
    focus.Clear()
    settings.vignetteRadarAutoRouteQuestNearest = true
    settings.vignetteRadarAutoRouteQuestStarts = false
    settings.vignetteRadarAutoRouteNearbyZones = false
    settings.vignetteRadarWorldQuestPriority = true
    settings.vignetteRadarWorldQuestPriorityRange = 300
    addon.VignetteRadarAvailableStarts = {}
    addon.VignetteRadarRouteQuests = nil
    local ordinary, world = Step(320), Step(500)
    ordinary.questID, ordinary.name = 801, "Nearby objective"
    world.questID, world.name, world.taskType = 800, "World Quest", "world"
    questActive[800], questActive[801] = true, true
    C_QuestLog.GetQuestObjectives = function() return { { finished = false } } end
    player.worldX = 300
    focus.Sync(123, player, {}, { ordinary, world }, {})
    assert(focus.StartNearest("quest") and waypoint.position.x == .5,
        "a World Quest inside the preference radius should beat a closer regular objective")
    focus.Clear()
    settings.vignetteRadarWorldQuestPriorityRange = 150
    assert(focus.StartNearest("quest") and waypoint.position.x == .32,
        "a World Quest outside the configured radius should not preempt the closest objective")
    focus.Clear()
    settings.vignetteRadarWorldQuestPriorityRange = 300
    addon.VignetteRadarExploration = { GetFocusedQuest = function() return 801 end }
    assert(focus.StartNearest("quest") and waypoint.position.x == .32,
        "spotlighting a quest should override the World Quest preference")
    addon.VignetteRadarExploration = nil
    focus.Clear()
end
do
    focus.Clear()
    settings.vignetteRadarAutoRouteQuestStarts = true
    settings.vignetteRadarAutoRouteNearbyZones = false
    settings.vignetteRadarAutoRouteMapNotes = false
    addon.VignetteRadarRouteQuests = nil
    local showWarbandCompleted = false
    C_Minimap = {
        IsTrackingAccountCompletedQuests = function() return showWarbandCompleted end,
    }
    C_QuestLog.IsQuestFlaggedCompletedOnAccount = function(id) return id == 910 end
    questActive[910] = false
    addon.VignetteRadarAvailableStarts = { {
        questID = 910, questName = "Warband completed quest", mapID = 123,
        x = .31, y = .5, worldX = 310, worldY = 500, instanceID = 42,
    } }
    local rare = Step(340)
    rare.kind, rare.category, rare.key, rare.name = "rare", "rare", "warband-filter-rare", "Nearby rare"
    player.worldX = 300
    focus.Sync(123, player, { rare }, {}, {})
    assert(focus.StartNearest("closest") and waypoint.position.x == .34,
        "Closest must skip account-completed quest starts when Blizzard tracking is off")
    focus.Clear()
    showWarbandCompleted = true
    focus.Sync(123, player, { rare }, {}, {})
    assert(focus.StartNearest("closest") and waypoint.position.x == .31,
        "Closest may include account-completed quest starts when Blizzard tracking is on")
    showWarbandCompleted = false
    focus.Sync(123, player, { rare }, {}, {})
    assert(waypoint.position.x == .34 and select(2, focus.GetRoutePoint()) == "rare",
        "turning off Warband tracking must replace an already pinned completed quest")
    focus.Clear()
    showWarbandCompleted = true
    focus.Sync(123, player, {}, {}, {})
    assert(focus.StartNearest("closest") and waypoint.position.x == .31)
    showWarbandCompleted = false
    focus.Sync(123, player, {}, {}, {})
    assert(waypoint == nil and not focus.HasFocus(),
        "when no eligible point remains, the completed quest pin must clear")
    focus.Clear()
    showWarbandCompleted = false
    focus.Sync(123, player, {}, {}, {})
    assert(not focus.StartNearest("quest"),
        "Quest routing must also skip a warband-completed quest start when tracking is off")
    showWarbandCompleted = true
    focus.Sync(123, player, {}, {}, {})
    assert(focus.StartNearest("quest") and waypoint.position.x == .31,
        "Quest routing may use that start again when warband tracking is on")
    showWarbandCompleted = false
    focus.Sync(123, player, {}, {}, {})
    assert(not focus.HasFocus(),
        "disabling warband tracking must clear an already active Quest route to that start")
end

do
    settings.vignetteRadarAutoRouteRestore = true
    settings.vignetteRadarAutoRouteWasActive = false
    addon.VignetteRadarAvailableStarts = {}
    local now = 1000
    GetTime = function() return now end
    local rare = Step(360)
    rare.kind, rare.category, rare.key, rare.name = "rare", "rare", "restore-rare", "Remembered Rare"
    player.worldX = 300
    focus.Sync(123, player, { rare }, {}, {})
    assert(focus.StartNearest("rare") and settings.vignetteRadarAutoRouteLastKind == "rare"
        and settings.vignetteRadarAutoRouteWasActive,
        "starting a route should remember its kind for reload")
    assert(not focus.ToggleRoute() and not settings.vignetteRadarAutoRouteWasActive,
        "a deliberately paused route must stay paused after reload")
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    local restored = addon.VignetteRadarWorldFocus
    restored.Sync(123, player, { rare }, {}, {})
    assert(not restored.IsRouteActive(), "reload must not restart a paused route")
    assert(restored.StartNearest("rare") and settings.vignetteRadarAutoRouteWasActive)
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    restored = addon.VignetteRadarWorldFocus
    restored.Sync(123, player, {}, {}, {})
    assert(not restored.IsRouteActive() and settings.vignetteRadarAutoRouteWasActive,
        "missing startup data should keep the remembered route pending")
    assert(select(1, restored.GetRouteChoice()) == "rare"
        and select(2, restored.GetRouteChoice()) == "waiting",
        "the route chooser should still show the remembered kind while points load")
    now = now + 5
    restored.Sync(123, player, { rare }, {}, {})
    assert(restored.IsRouteActive() and select(2, restored.GetRoutePoint()) == "rare"
        and waypoint.position.x == .36,
        "the last route kind should resume when its points become available")
    assert(restored.Clear() and not settings.vignetteRadarAutoRouteWasActive,
        "clearing a route should cancel future automatic restoration")
    settings.vignetteRadarAutoRouteWasActive = true
    settings.vignetteRadarAutoRouteRestore = false
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    restored = addon.VignetteRadarWorldFocus
    restored.Sync(123, player, { rare }, {}, {})
    assert(not restored.IsRouteActive(), "the restore setting should stop automatic restart")
    addon.VignetteRadarQuestData = { GetObjectiveSummary = function(id, hint)
        assert(id == 998 and hint == "Gather Parts")
        return { label = "Gather Parts", count = "2/5" }
    end }
    local objective = Step(340)
    objective.questID, objective.name, objective.objectiveText = 998, "Parts Quest", "Gather Parts"
    restored.Sync(123, player, {}, { objective }, {})
    assert(restored.SelectQuest(998) and routeNotes[#routeNotes][3]
        and routeNotes[#routeNotes][3].count == "2/5",
        "selecting a quest objective should send its progress to the rounded route note")
end

do
    settings.vignetteRadarAutoRouteRestore = false
    settings.vignetteRadarAutoRouteWasActive = false
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    local fresh = addon.VignetteRadarWorldFocus
    local me = { worldX = 300, worldY = 500, instanceID = 42 }
    local first, second = Step(310), Step(520)
    first.key, first.name, first.category = "stop-first", "First stop", "rare"
    second.key, second.name, second.category = "stop-second", "Second stop", "rare"
    fresh.Sync(123, me, { first, second }, {}, {})
    assert(fresh.StartNearest("rare") and fresh.IsRouteActive()
        and settings.vignetteRadarAutoRouteWasActive)
    local canSet = C_Map.CanSetUserWaypointOnMap
    C_Map.CanSetUserWaypointOnMap = function() return false end
    assert(not fresh.SkipRouteStop(), "a stop that cannot be placed must fail the advance")
    C_Map.CanSetUserWaypointOnMap = canSet
    assert(not fresh.IsRouteActive() and not settings.vignetteRadarAutoRouteWasActive,
        "a failed advance must stop and forget the route")
    assert(routeNotes[#routeNotes][2]:find("Route stopped", 1, true),
        "a failed advance must say the route stopped")

    fresh.Clear(true)
    assert(fresh.SelectNote(first) and waypoint and waypoint.position.x == .31)
    settings.vignetteRadarWorldFocusEnabled = false
    fresh.Sync(123, me, { first, second }, {}, {})
    assert(waypoint == nil and not fresh.HasFocus(),
        "disabling World Focus must clear its owned Blizzard waypoint")
    settings.vignetteRadarWorldFocusEnabled = true
end

-- Close arrival choices: 3 and 5 yards for single picks and Auto Route.
do
    settings.vignetteRadarAutoRouteRestore = false
    settings.vignetteRadarAutoRouteWasActive = false
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    local close = addon.VignetteRadarWorldFocus
    local recent = addon.VignetteRadarRecent
    addon.VignetteRadarRecent = { IsHidden = function() return false end }
    local me = { worldX = 300, worldY = 500, instanceID = 42 }
    local spot = Step(600)
    spot.kind, spot.key, spot.name = "rare", "close:spot", "Close spot"
    settings.vignetteRadarWorldFocusArrivalRadius = 3
    close.Sync(123, me, {}, {}, {})
    assert(close.SelectPoint(spot) and close.HasFocus())
    me.worldX = 596.5
    close.Sync(123, me, {}, {}, {})
    assert(close.HasFocus(), "a 3 yard pick must stay at 3.5 yards")
    me.worldX = 597.1
    close.Sync(123, me, {}, {}, {})
    assert(not close.HasFocus(), "a 3 yard pick should arrive inside 3 yards")

    settings.vignetteRadarWorldFocusArrivalRadius = 5
    me.worldX = 300
    close.Sync(123, me, {}, {}, {})
    assert(close.SelectPoint(spot))
    me.worldX = 594.5
    close.Sync(123, me, {}, {}, {})
    assert(close.HasFocus(), "a 5 yard pick must stay at 5.5 yards")
    me.worldX = 595.1
    close.Sync(123, me, {}, {}, {})
    assert(not close.HasFocus(), "a 5 yard pick should arrive inside 5 yards")

    -- Auto Route: a cleared rare advances only inside the 5 yard setting.
    settings.vignetteRadarAutoRouteArrivalRadius = 5
    local closeA, closeB = Step(600), Step(800)
    closeA.kind, closeA.key, closeA.name, closeA.category = "rare", "close:a", "Rare A", "rare"
    closeB.kind, closeB.key, closeB.name, closeB.category = "rare", "close:b", "Rare B", "rare"
    me.worldX = 300
    close.Sync(123, me, { closeA, closeB }, {}, {})
    assert(close.StartNearest("rare") and waypoint.position.x == .6)
    addon.VignetteRadarRecent = { IsHidden = function(item) return item.key == closeA.key end }
    me.worldX = 594.5
    close.Sync(123, me, { closeA, closeB }, {}, {})
    assert(waypoint.position.x == .6, "a cleared rare at 5.5 yards must not advance a 5 yard route")
    me.worldX = 595.1
    close.Sync(123, me, { closeA, closeB }, {}, {})
    assert(waypoint.position.x == .8, "a cleared rare inside 5 yards should advance the route")
    close.Clear(true)
    addon.VignetteRadarRecent = recent
    settings.vignetteRadarWorldFocusArrivalRadius = 20
    settings.vignetteRadarAutoRouteArrivalRadius = 10
end

-- Keep Marker Until Looted Or Killed holds rare and treasure stops.
do
    settings.vignetteRadarAutoRouteRestore = false
    settings.vignetteRadarAutoRouteWasActive = false
    settings.vignetteRadarKeepMarkerUntilDone = true
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    local keep = addon.VignetteRadarWorldFocus
    local recent = addon.VignetteRadarRecent
    addon.VignetteRadarRecent = { IsHidden = function() return false end }
    local me = { worldX = 300, worldY = 500, instanceID = 42 }

    -- A single treasure pick stays at the chest until its loot matches.
    local chest = Step(500)
    chest.kind, chest.key, chest.name, chest.objectID = "treasure", "keep:chest", "Kept cache", 555
    keep.Sync(123, me, {}, {}, { chest })
    assert(keep.SelectNote(chest) and keep.HasFocus())
    me.worldX = 500
    keep.Sync(123, me, {}, {}, { chest })
    keep.Sync(123, me, {}, {}, { chest })
    assert(keep.HasFocus() and waypoint.position.x == .5,
        "a kept treasure must not count as arrived by distance")
    assert(keep.ExplainActive():find("advances on matching loot", 1, true))
    GetTime = function() return 200 end
    GetNumLootItems = function() return 1 end
    GetLootSourceInfo = function() return "GameObject-0-1-1-1-999-000" end
    keep.OnLootEvent("LOOT_OPENED")
    assert(not keep.OnLootEvent("LOOT_SLOT_CLEARED") and keep.HasFocus(),
        "another container must not release a kept treasure")
    GetLootSourceInfo = function() return "GameObject-0-1-1-1-555-000" end
    keep.OnLootEvent("LOOT_OPENED")
    assert(keep.OnLootEvent("LOOT_SLOT_CLEARED") and not keep.HasFocus(),
        "looting the kept treasure should release its marker")

    -- A treasure route holds at the chest, then advances on loot.
    local mapNotes = settings.vignetteRadarAutoRouteMapNotes
    settings.vignetteRadarAutoRouteMapNotes = true
    local first, second = Step(500), Step(700)
    first.kind, first.key, first.name, first.objectID = "treasure", "keep:first", "First kept", 556
    second.kind, second.key, second.name = "treasure", "keep:second", "Second kept"
    me.worldX = 300
    keep.Sync(123, me, {}, {}, { first, second })
    assert(keep.SelectNote(first) and keep.ToggleRoute() and waypoint.position.x == .5)
    me.worldX = 500
    keep.Sync(123, me, {}, {}, { first, second })
    assert(waypoint.position.x == .5 and keep.IsRouteActive(),
        "a kept treasure route stop must wait at the chest")
    GetLootSourceInfo = function() return "GameObject-0-1-1-1-556-000" end
    keep.OnLootEvent("LOOT_OPENED")
    assert(keep.OnLootEvent("LOOT_SLOT_CLEARED") and waypoint.position.x == .7,
        "looting a kept treasure route stop should advance the route")
    keep.Clear(true)
    settings.vignetteRadarAutoRouteMapNotes = mapNotes

    -- A live rare stays until its vignette dies or disappears nearby.
    local rare, other = Step(600), Step(800)
    rare.kind, rare.key, rare.name, rare.category = "rare", "keep:rare", "Kept rare", "rare"
    other.kind, other.key, other.name, other.category = "rare", "keep:other", "Other rare", "rare"
    me.worldX = 300
    keep.Sync(123, me, { rare, other }, {}, {})
    assert(keep.SelectTarget(rare) and keep.HasFocus())
    me.worldX = 600
    keep.Sync(123, me, { rare, other }, {}, {})
    assert(keep.HasFocus(), "a kept rare must not count as arrived by distance")
    rare.isDead = true
    keep.Sync(123, me, { rare, other }, {}, {})
    assert(not keep.HasFocus(), "a dead kept rare should release its marker")
    rare.isDead = nil

    me.worldX = 300
    keep.Sync(123, me, { rare, other }, {}, {})
    assert(keep.SelectTarget(rare) and keep.ToggleRoute() and waypoint.position.x == .6)
    me.worldX = 600
    keep.Sync(123, me, { rare, other }, {}, {})
    assert(waypoint.position.x == .6, "a kept rare route stop waits while the rare lives")
    keep.Sync(123, me, { other }, {}, {})
    assert(waypoint.position.x == .8 and keep.IsRouteActive(),
        "a kept rare whose vignette vanished nearby should advance the route")
    keep.Clear(true)
    addon.VignetteRadarRecent = recent
    settings.vignetteRadarKeepMarkerUntilDone = false
end

-- Quest stops: Blizzard super-track far away, a pinned exact spot inside
-- the quest area, and back, without dropping the route.
do
    settings.vignetteRadarAutoRouteRestore = false
    settings.vignetteRadarAutoRouteWasActive = false
    local savedQuestLog, savedSuperTrack = C_QuestLog, C_SuperTrack
    local trackedQuest, trackingUser = 7, false
    C_SuperTrack = {
        GetSuperTrackedQuestID = function() return trackedQuest end,
        SetSuperTrackedQuestID = function(id) trackedQuest, trackingUser = id, false end,
        SetSuperTrackedUserWaypoint = function(on) trackingUser = on == true end,
        IsSuperTrackingUserWaypoint = function() return trackingUser end,
    }
    C_QuestLog = {
        GetLogIndexForQuestID = function() return 1 end,
        GetQuestWatchType = function() return 0 end,
        IsOnQuest = function() return true end,
        GetQuestObjectives = function() return { { finished = false, numFulfilled = 1 } } end,
    }
    local inArea = false
    addon.VignetteRadarQuestData = {
        IsQuestInArea = function() return inArea end,
        GetNextStep = function() return nil end,
    }
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    local quest = addon.VignetteRadarWorldFocus
    local me = { worldX = 100, worldY = 500, instanceID = 42 }
    local spot = Step(600)
    spot.questID, spot.name, spot.objectiveText = 4242, "Pinned Quest", "Find the spot"
    waypoint = nil
    quest.Sync(123, me, {}, { spot }, {})
    assert(quest.SelectQuest(4242) and quest.ToggleRoute() and quest.IsRouteActive())
    assert(trackedQuest == 4242 and not trackingUser and waypoint == nil
        and not quest.IsQuestPinned(), "a far quest stop uses Blizzard super-tracking")

    inArea = true
    me.worldX = 300
    quest.Sync(123, me, {}, { spot }, {})
    assert(quest.IsQuestPinned() and trackingUser and waypoint
        and waypoint.position.x == .6 and quest.IsRouteActive() and quest.HasFocus(),
        "inside the quest area the stop should pin the exact objective spot")
    quest.Sync(123, me, {}, { spot }, {})
    assert(quest.IsQuestPinned() and quest.IsRouteActive(),
        "the pinned spot must not look like an outside waypoint change")

    local moved = Step(650)
    moved.questID, moved.name, moved.objectiveText = 4242, "Pinned Quest", "Find the spot"
    quest.Sync(123, me, {}, { moved }, {})
    assert(quest.IsQuestPinned() and waypoint.position.x == .65 and quest.IsRouteActive(),
        "a moved objective should move the pin")

    inArea = false
    me.worldX = 100
    quest.Sync(123, me, {}, { moved }, {})
    assert(not quest.IsQuestPinned() and trackedQuest == 4242 and not trackingUser
        and waypoint == nil and quest.IsRouteActive() and quest.HasFocus(),
        "leaving the area should hand back to super-track and keep the route")
    quest.Sync(123, me, {}, { moved }, {})
    assert(quest.IsRouteActive(), "the route must survive the swap back")

    -- Close by distance alone also pins; Clear removes the pin and restores.
    me.worldX = 630
    quest.Sync(123, me, {}, { moved }, {})
    assert(quest.IsQuestPinned() and waypoint.position.x == .65)
    assert(quest.Clear(true) and waypoint == nil and trackedQuest == 7
        and not quest.HasFocus(), "clearing a pinned quest stop restores the prior quest")

    settings.vignetteRadarQuestPinWhenClose = false
    me.worldX = 300
    inArea = true
    quest.Sync(123, me, {}, { spot }, {})
    assert(quest.SelectQuest(4242))
    quest.Sync(123, me, {}, { spot }, {})
    assert(not quest.IsQuestPinned() and trackedQuest == 4242,
        "turning the pin setting off keeps Blizzard super-tracking")
    quest.Clear(true)
    settings.vignetteRadarQuestPinWhenClose = nil
    addon.VignetteRadarQuestData = nil
    C_QuestLog, C_SuperTrack = savedQuestLog, savedSuperTrack
end

-- Closest route on a quest: turning the quest in drops Blizzard's quest
-- super-track. That is quest progress, not an outside waypoint change, so
-- the route must rescan, choose the next closest point and place it.
do
    settings.vignetteRadarAutoRouteRestore = false
    settings.vignetteRadarAutoRouteWasActive = false
    settings.vignetteRadarAutoRouteNearbyZones = false
    settings.vignetteRadarAutoRouteQuestStarts = false
    local savedMapNotes = settings.vignetteRadarAutoRouteMapNotes
    settings.vignetteRadarAutoRouteMapNotes = true
    local savedQuestLog, savedSuperTrack = C_QuestLog, C_SuperTrack
    local savedRecent, savedMarker = addon.VignetteRadarRecent, addon.VignetteRadarWorldMarker
    addon.VignetteRadarRecent = nil
    local markerRefreshes = 0
    addon.VignetteRadarWorldMarker = { Refresh = function() markerRefreshes = markerRefreshes + 1 end }
    local trackedQuest, trackingUser = 0, false
    C_SuperTrack = {
        GetSuperTrackedQuestID = function() return trackedQuest end,
        SetSuperTrackedQuestID = function(id) trackedQuest, trackingUser = id, false end,
        SetSuperTrackedUserWaypoint = function(on) trackingUser = on == true end,
        IsSuperTrackingUserWaypoint = function() return trackingUser end,
    }
    local onLog, turnedIn = { [5151] = true, [5252] = true }, {}
    C_QuestLog = {
        GetLogIndexForQuestID = function(id) return onLog[id] and 1 or nil end,
        GetQuestWatchType = function() return 0 end,
        IsOnQuest = function(id) return onLog[id] == true end,
        IsQuestFlaggedCompleted = function(id) return turnedIn[id] == true end,
        IsComplete = function() return false end,
        GetQuestObjectives = function() return { { finished = false, numFulfilled = 0 } } end,
    }
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    local closest = addon.VignetteRadarWorldFocus
    local me = { worldX = 100, worldY = 500, instanceID = 42 }
    local job = Step(600)
    job.questID, job.name, job.objectiveText = 5151, "Finished Job", "Do the job"
    local cache = Step(400)
    cache.kind, cache.key, cache.name = "treasure", "closest:after-quest", "After cache"
    waypoint = nil
    closest.Sync(123, me, {}, { job }, {})
    assert(closest.StartNearest("closest") and trackedQuest == 5151
        and closest.IsRouteActive(), "Closest should start on the only quest")

    -- Turn-in: the quest leaves the log and Blizzard drops its super-track.
    onLog[5151], turnedIn[5151], trackedQuest = nil, true, 0
    markerRefreshes = 0
    closest.Sync(123, me, {}, {}, { cache })
    assert(closest.IsRouteActive() and closest.GetRouteChoice() == "closest",
        "a turned-in quest must not stop the Closest route")
    assert(waypoint and waypoint.position.x == .4 and trackingUser
        and closest.GetActiveTarget() and closest.GetActiveTarget().key == cache.key
        and markerRefreshes > 0,
        "a turned-in quest should pick and place the next closest point")

    -- Nothing nearby yet: the route waits, then takes the first new point.
    closest.Clear(true)
    local job2 = Step(600)
    job2.questID, job2.name, job2.objectiveText = 5252, "Second Job", "Do it again"
    closest.Sync(123, me, {}, { job2 }, {})
    assert(closest.StartNearest("closest") and trackedQuest == 5252)
    onLog[5252], turnedIn[5252], trackedQuest = nil, true, 0
    closest.Sync(123, me, {}, {}, {})
    assert(closest.IsRouteActive() and closest.Status():find("Waiting for Nearby Points", 1, true),
        "with no next point a turned-in quest should leave Closest waiting")
    closest.Sync(123, me, {}, {}, {})
    assert(closest.IsRouteActive(), "a waiting Closest route must survive later scans")
    markerRefreshes = 0
    closest.Sync(123, me, {}, {}, { cache })
    assert(closest.IsRouteActive() and waypoint and waypoint.position.x == .4
        and closest.GetActiveTarget().key == cache.key and markerRefreshes > 0
        and not closest.Status():find("Waiting", 1, true),
        "a waiting Closest route should pick and place the first point that appears")
    closest.Clear(true)
    settings.vignetteRadarAutoRouteMapNotes = savedMapNotes
    addon.VignetteRadarRecent, addon.VignetteRadarWorldMarker = savedRecent, savedMarker
    C_QuestLog, C_SuperTrack = savedQuestLog, savedSuperTrack
end

-- A quest stop is held until all its objectives are done: one finished
-- objective keeps the quest super-tracked and the close pin follows
-- Blizzard's next objective. "Move On After Each Objective" restores the old advance.
do
    settings.vignetteRadarAutoRouteRestore = false
    settings.vignetteRadarAutoRouteWasActive = false
    settings.vignetteRadarAutoRouteNearbyZones = false
    settings.vignetteRadarAutoRouteQuestStarts = false
    settings.vignetteRadarAutoRouteQuestMoveOn = nil
    local savedMapNotes = settings.vignetteRadarAutoRouteMapNotes
    settings.vignetteRadarAutoRouteMapNotes = true
    local savedQuestLog, savedSuperTrack = C_QuestLog, C_SuperTrack
    local savedRecent, savedMarker = addon.VignetteRadarRecent, addon.VignetteRadarWorldMarker
    local savedData, savedPool = addon.VignetteRadarQuestData, addon.VignetteRadarRouteQuests
    addon.VignetteRadarRecent = nil
    addon.VignetteRadarWorldMarker = { Refresh = function() end }
    local trackedQuest, trackingUser = 0, false
    C_SuperTrack = {
        GetSuperTrackedQuestID = function() return trackedQuest end,
        SetSuperTrackedQuestID = function(id) trackedQuest, trackingUser = id, false end,
        SetSuperTrackedUserWaypoint = function(on) trackingUser = on == true end,
        IsSuperTrackingUserWaypoint = function() return trackingUser end,
    }
    local onLog, turnedIn, allDone = { [6161] = true, [6262] = true, [7171] = true }, {}, {}
    local objectives = {
        [6161] = { { finished = false, numFulfilled = 0 }, { finished = false, numFulfilled = 0 } },
        [7171] = { { finished = false, numFulfilled = 0 }, { finished = false, numFulfilled = 0 } },
    }
    C_QuestLog = {
        GetLogIndexForQuestID = function(id) return onLog[id] and 1 or nil end,
        GetQuestWatchType = function() return 0 end,
        IsOnQuest = function(id) return onLog[id] == true end,
        IsQuestFlaggedCompleted = function(id) return turnedIn[id] == true end,
        IsComplete = function(id) return allDone[id] == true end,
        GetQuestObjectives = function(id)
            return objectives[id] or { { finished = false, numFulfilled = 0 } }
        end,
    }
    -- Blizzard's next point for the quest: nil until set below.
    local nextX, inArea = nil, false
    addon.VignetteRadarQuestData = {
        IsQuestInArea = function() return inArea end,
        GetNextStep = function(questID, mapID)
            if questID == 6161 and nextX then
                return { questID = questID, mapID = mapID, x = nextX / 1000, y = .5, onCurrentMap = true }
            end
        end,
    }
    addon.VignetteRadarRouteQuests = {
        Tick = function() end,
        Candidates = function() return {} end,
        CurrentQuestWaypoint = function(id)
            if id ~= 6161 or not nextX then return nil end
            local point = Step(nextX)
            point.kind, point.questID, point.name = "quest", 6161, "Held Job"
            return point
        end,
    }
    assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
    local held = addon.VignetteRadarWorldFocus
    local me = { worldX = 100, worldY = 500, instanceID = 42 }
    local job = Step(300)
    job.questID, job.name, job.objectiveText = 6161, "Held Job", "Two things"
    local other = Step(500)
    other.questID, other.name = 6262, "Other Job"
    local cache = Step(400)
    cache.kind, cache.key, cache.name = "treasure", "held:cache", "Held cache"
    waypoint = nil
    held.Sync(123, me, {}, { job, other }, { cache })
    assert(held.StartNearest("closest") and trackedQuest == 6161
        and held.GetRoutePoint().questID == 6161, "Closest should start on the nearest quest")

    -- One objective done: same stop, still super-tracked, nothing pinned yet.
    objectives[6161][1].finished = true
    held.Sync(123, me, {}, { job, other }, { cache })
    assert(held.IsRouteActive() and held.GetRoutePoint().questID == 6161
        and trackedQuest == 6161 and not trackingUser and waypoint == nil,
        "finishing one objective must keep the quest stop and its super-track")

    -- In the area, the close pin sits on Blizzard's next objective.
    nextX, inArea, me.worldX = 350, true, 330
    held.Sync(123, me, {}, { job, other }, { cache })
    assert(held.IsQuestPinned() and waypoint and waypoint.position.x == .35
        and held.GetRoutePoint().questID == 6161,
        "the pin should follow the next objective, not the finished one")

    -- All objectives done (IsComplete true, still in the log): the quest
    -- stop is finished and the route moves to the next closest.
    objectives[6161][2].finished, allDone[6161], trackedQuest, nextX, inArea = true, true, 0, nil, false
    held.Sync(123, me, {}, { job, other }, { cache })
    assert(held.IsRouteActive() and waypoint and waypoint.position.x == .4
        and held.GetActiveTarget() and held.GetActiveTarget().key == cache.key,
        "completing every objective should advance to the next closest point")
    held.Clear(true)

    -- Setting on: each finished objective advances, as before.
    settings.vignetteRadarAutoRouteQuestMoveOn = "each"
    me.worldX = 100
    local job3 = Step(300)
    job3.questID, job3.name = 7171, "Per Objective Job"
    held.Sync(123, me, {}, { job3, other }, { cache })
    assert(held.StartNearest("closest") and trackedQuest == 7171)
    objectives[7171][1].finished = true
    held.Sync(123, me, {}, { job3, other }, { cache })
    assert(held.IsRouteActive() and waypoint and waypoint.position.x == .4
        and held.GetActiveTarget().key == cache.key,
        "Move On After Each Objective should advance on each finished objective")
    held.Clear(true)

    settings.vignetteRadarAutoRouteQuestMoveOn = nil
    settings.vignetteRadarAutoRouteMapNotes = savedMapNotes
    addon.VignetteRadarRecent, addon.VignetteRadarWorldMarker = savedRecent, savedMarker
    addon.VignetteRadarQuestData, addon.VignetteRadarRouteQuests = savedData, savedPool
    C_QuestLog, C_SuperTrack = savedQuestLog, savedSuperTrack
end

-- The last single pick survives /reload: a new module instance reading the
-- same saved DB re-selects it, unless it is done, cleared, or a route wins.
do
    settings.vignetteRadarAutoRouteRestore = true
    settings.vignetteRadarAutoRouteWasActive = false
    settings.vignetteRadarAutoRouteLastKind = nil
    settings.vignetteRadarAutoRouteOnSelect = false
    settings.vignetteRadarLastFocus = nil
    local savedQuestLog, savedSuperTrack = C_QuestLog, C_SuperTrack
    local savedRecent, savedMarker = addon.VignetteRadarRecent, addon.VignetteRadarWorldMarker
    local savedService = addon.VignetteRadarFocus
    addon.VignetteRadarRecent, addon.VignetteRadarWorldMarker = nil, nil
    local trackedQuest, trackingUser = 0, false
    C_SuperTrack = {
        GetSuperTrackedQuestID = function() return trackedQuest end,
        SetSuperTrackedQuestID = function(id) trackedQuest, trackingUser = id, false end,
        SetSuperTrackedUserWaypoint = function(on) trackingUser = on == true end,
        IsSuperTrackingUserWaypoint = function() return trackingUser end,
    }
    local onLog, turnedIn = { [7001] = true, [7002] = true }, {}
    C_QuestLog = {
        GetLogIndexForQuestID = function(id) return onLog[id] and 1 or nil end,
        GetQuestWatchType = function() return 0 end,
        IsOnQuest = function(id) return onLog[id] == true end,
        IsQuestFlaggedCompleted = function(id) return turnedIn[id] == true end,
        IsComplete = function() return false end,
        GetQuestObjectives = function() return { { finished = false, numFulfilled = 0 } } end,
    }
    -- A /reload: fresh Focus service and World Focus, same settings table.
    local function Reload()
        assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
        assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
        return addon.VignetteRadarWorldFocus, addon.VignetteRadarFocus
    end
    local me = { worldX = 100, worldY = 500, instanceID = 42 }
    local hunt = Step(600)
    hunt.questID, hunt.name, hunt.objectiveText = 7001, "Saved Hunt", "Hunt it"
    local errand = Step(700)
    errand.questID, errand.name, errand.objectiveText = 7002, "Saved Errand", "Run it"

    -- Manual quest pick, then reload: it comes back on the first scan.
    waypoint = nil
    local world, service = Reload()
    world.Sync(123, me, {}, { hunt }, {})
    assert(service.Select(service.Quest(7001, hunt), { source = "test" }) and trackedQuest == 7001)
    local record = settings.vignetteRadarLastFocus
    assert(record and record.kind == "quest" and record.questID == 7001 and record.focusType == "quest",
        "a manual quest pick should be saved for the next reload")
    trackedQuest = 0
    world, service = Reload()
    assert(not world.HasFocus() and service.Get() == nil)
    world.Sync(123, me, {}, { hunt }, {})
    assert(world.HasFocus() and world.GetActiveTarget().questID == 7001 and trackedQuest == 7001
        and not world.IsRouteActive(),
        "a manual quest pick must be re-selected (super-track included) after /reload")
    assert(service.GetQuest() == 7001, "the radar focus should come back with the pick")

    -- Turned in before the next reload: not restored, and forgotten.
    onLog[7001], turnedIn[7001], trackedQuest = nil, true, 0
    world = Reload()
    world.Sync(123, me, {}, {}, {})
    assert(not world.HasFocus() and trackedQuest == 0 and settings.vignetteRadarLastFocus == nil,
        "a completed quest must not be restored")

    -- A manual clear forgets the pick.
    world = Reload()
    world.Sync(123, me, {}, { errand }, {})
    assert(world.SelectQuest(7002) and settings.vignetteRadarLastFocus.questID == 7002)
    assert(world.Clear() and settings.vignetteRadarLastFocus == nil,
        "a manual clear must forget the saved pick")
    world = Reload()
    world.Sync(123, me, {}, { errand }, {})
    assert(not world.HasFocus(), "a cleared pick must stay gone after /reload")

    -- Blizzard kept the user waypoint through the reload: reuse it.
    local cache = Step(200)
    cache.kind, cache.key, cache.name, cache.source = "treasure", "pack:123:20005000", "Kept Cache", "pack"
    world = Reload()
    world.Sync(123, me, {}, {}, { cache })
    assert(world.SelectNote(cache) and settings.vignetteRadarLastFocus.key == cache.key)
    local placedBefore = #placed
    world = Reload()
    world.Sync(123, me, {}, {}, { cache })
    assert(world.HasFocus() and world.GetActiveTarget().key == cache.key and #placed == placedBefore,
        "a restored pick should reuse Blizzard's surviving waypoint, not place another")
    world.Clear(true)

    -- An Auto Route restore wins over the saved single pick.
    world = Reload()
    world.Sync(123, me, {}, { errand }, {})
    assert(world.SelectQuest(7002) and settings.vignetteRadarLastFocus.questID == 7002)
    settings.vignetteRadarAutoRouteWasActive, settings.vignetteRadarAutoRouteLastKind = true, "closest"
    world = Reload()
    world.Sync(123, me, {}, { errand }, { cache })
    assert(world.IsRouteActive() and world.GetRouteChoice() == "closest"
        and world.HasFocus() and settings.vignetteRadarLastFocus == nil,
        "an Auto Route restore must win over the saved single pick")
    world.Clear(true)

    settings.vignetteRadarAutoRouteWasActive, settings.vignetteRadarAutoRouteLastKind = false, nil
    settings.vignetteRadarLastFocus = nil
    addon.VignetteRadarFocus = savedService
    addon.VignetteRadarRecent, addon.VignetteRadarWorldMarker = savedRecent, savedMarker
    C_QuestLog, C_SuperTrack = savedQuestLog, savedSuperTrack
end

-- Next 3 Stops Strip: a click on a later horizon stop jumps the route there,
-- and the skipped current stop counts as visited.
do
    focus.Clear(true)
    local near, middle, far = Step(320), Step(450), Step(600)
    near.key, near.name, near.kind = "jump:near", "Near cache", "treasure"
    middle.key, middle.name, middle.kind = "jump:middle", "Middle cache", "treasure"
    far.key, far.name, far.kind = "jump:far", "Far cache", "treasure"
    player.worldX, player.worldY, player.instanceID = 300, 500, 42
    settings.vignetteRadarAutoRouteMapNotes = true
    local savedRecent = addon.VignetteRadarRecent
    addon.VignetteRadarRecent = nil
    focus.Sync(123, player, {}, {}, { near, middle, far })
    assert(not focus.JumpRouteStop(far), "a jump needs a running route")
    local started = focus.StartNearest("treasure")
    assert(started and focus.GetActiveTarget().key == "jump:near")
    local horizon = focus.GetHorizon()
    assert(#horizon == 3 and horizon[1].current and horizon[3].item.key == "jump:far",
        "the horizon should preview three stops in route order")
    assert(not focus.JumpRouteStop(horizon[1].item), "the current stop is not a jump target")
    assert(focus.JumpRouteStop(horizon[3].item) and focus.GetActiveTarget().key == "jump:far"
        and focus.IsRouteActive(), "a jump should make the chosen stop current and keep the route")
    local after = focus.GetHorizon()
    for _, stop in ipairs(after) do
        assert(stop.item.key ~= "jump:near", "the skipped stop must count as visited")
    end
    focus.Clear(true)
    addon.VignetteRadarRecent = savedRecent
end

-- Live Rare Follow: a live rare super-tracks its vignette; the stop follows
-- the walking rare; the rare vanishing is progress, not a waypoint change.
do
    focus.Clear(true)
    local savedSuperTrack = C_SuperTrack
    local trackedVignette, cleared = nil, 0
    C_SuperTrack = {
        SetSuperTrackedUserWaypoint = function() trackedVignette = nil end,
        SetSuperTrackedVignette = function(guid) trackedVignette = guid end,
        GetSuperTrackedVignette = function() return trackedVignette end,
        ClearAllSuperTracked = function() trackedVignette = nil; cleared = cleared + 1 end,
    }
    settings.vignetteRadarLiveRareFollow = true
    local walker = Step(700)
    walker.key, walker.name, walker.category = "Vignette-0-1-2-3-4-5", "Walking rare", "rare"
    player.worldX, player.worldY, player.instanceID = 300, 500, 42
    focus.Sync(123, player, { walker }, {}, {})
    local placedBefore = #placed
    assert(focus.SelectTarget(walker) and trackedVignette == walker.key and #placed == placedBefore,
        "a live rare should super-track its vignette instead of placing a pin")
    local moved = Step(760)
    moved.key, moved.name, moved.category = walker.key, walker.name, "rare"
    focus.Sync(123, player, { moved }, {}, {})
    assert(focus.HasFocus() and focus.GetActiveTarget().worldX == 760,
        "the followed stop takes the rare's latest position")
    trackedVignette = nil
    focus.Sync(123, player, {}, {}, {})
    assert(not focus.HasFocus() and cleared == 0,
        "a followed rare that vanished ends the focus without clearing someone else's track")
    -- A vignette still up but no longer tracked: the person picked something else.
    focus.Sync(123, player, { moved }, {}, {})
    assert(focus.SelectTarget(moved) and trackedVignette == moved.key)
    trackedVignette = "Vignette-other"
    focus.Sync(123, player, { moved }, {}, {})
    assert(not focus.HasFocus(), "an outside super-track change still drops the focus")
    -- Switched off: the old pin.
    settings.vignetteRadarLiveRareFollow = false
    trackedVignette = nil
    assert(focus.SelectTarget(moved) and trackedVignette == nil and #placed == placedBefore + 1,
        "with the switch off a live rare gets a user waypoint")
    focus.Clear(true)
    -- Clear hands the vignette track back while it is still ours.
    settings.vignetteRadarLiveRareFollow = true
    assert(focus.SelectTarget(moved) and trackedVignette == moved.key)
    assert(focus.Clear(true) and trackedVignette == nil and cleared == 1,
        "clearing the focus clears our own vignette super-track")
    settings.vignetteRadarLiveRareFollow = nil
    C_SuperTrack = savedSuperTrack
end

-- ROUTE_CHANGED: Select, Skip, Lock and Clear tell the Guide Panel once
-- each; a call that changes nothing stays quiet. Horizon labels show
-- "Treasure · <Zone>" for a pack's stand-in "Treasure location".
do
    focus.Clear(true)
    local savedBus, savedRecent, savedGetMapInfo = addon.Bus, addon.VignetteRadarRecent, C_Map.GetMapInfo
    local fired = 0
    addon.Bus = { Emit = function(topic) if topic == "ROUTE_CHANGED" then fired = fired + 1 end end,
        On = function() end, InCombat = function() return false end }
    addon.VignetteRadarRecent = nil
    C_Map.GetMapInfo = function(mapID) return mapID == 123 and { name = "Zul'Aman" } or nil end
    assert(loadfile("Core/Guidance.lua"))("VignetteRadar", addon)
    local near, middle, far = Step(320), Step(450), Step(600)
    near.key, near.name, near.kind = "changed:near", "Near cache", "treasure"
    middle.key, middle.name, middle.kind = "changed:middle", "Treasure location", "treasure"
    far.key, far.name, far.kind = "changed:far", "Far cache", "treasure"
    player.worldX, player.worldY, player.instanceID = 300, 500, 42
    focus.Sync(123, player, {}, {}, { near, middle, far })
    fired = 0
    focus.Sync(123, player, {}, {}, { near, middle, far })
    assert(fired == 0, "a scan that changes nothing fires nothing")
    assert(focus.StartNearest("treasure") and fired == 1, "starting a route fires once")
    local horizon = focus.GetHorizon(4)
    assert(#horizon == 3 and horizon[2].label == "Treasure · Zul'Aman",
        "a stand-in pack name reads as kind and zone: " .. tostring(horizon[2] and horizon[2].label))
    assert(#focus.GetHorizon() == 3 and #focus.GetHorizon(2) == 2 and focus.GetHorizon(2)[2] == horizon[2],
        "a shorter horizon comes from the cached longer one")
    assert(focus.ToggleRouteLock() and fired == 2, "locking the stop fires")
    assert(focus.ToggleRouteLock() and fired == 3, "unlocking fires")
    assert(focus.SkipRouteStop() and fired == 4, "skipping to the next stop fires")
    assert(focus.Clear(true) and fired == 5, "clearing fires")
    assert(not focus.Clear(true) and fired == 5, "clearing nothing fires nothing")
    addon.Bus, addon.VignetteRadarRecent, C_Map.GetMapInfo = savedBus, savedRecent, savedGetMapInfo
    addon.VignetteRadarGuidance = nil
end

io.write("vignette radar World Focus tests passed\n")
