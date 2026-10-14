VignetteRadarDB, WaffleHouseDB = nil, nil
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/Exploration.lua"))("VignetteRadar", addon)
local E, db = addon.VignetteRadarExploration, addon.GetSettings()
local current = 0
GetTime = function() return current end
time = function() return 123456 end
local player = { mapID=10, mapX=.2, mapY=.3, worldX=200, worldY=300, instanceID=7 }
local target = { key="guid-1", vignetteID=101, name="Rare One", category="rare",
    mapID=10, mapX=.3, mapY=.3, worldX=300, worldY=300, instanceID=7 }

assert(E.Range(player, nil) == db.vignetteRadarRange)
db.vignetteRadarSmartZoom = true
GetUnitSpeed = function() return 7 end
assert(E.Range(player, nil) == 1200, "travel speed should widen the radar")
assert(E.Range(player, { distance=180 }) == 300, "focus should select the nearest covering range")
assert(E.Range(player, { distance=4 }) == 10, "smart zoom should use the new close range for a nearby focus")
E.ManualZoom()
assert(E.Range(player, nil) == db.vignetteRadarRange, "manual zoom should temporarily override auto zoom")
current = 31
assert(E.Range(player, nil) == 1200)

E.FocusQuest(900)
assert(E.GetFocusedQuest() == 900)
E.FocusQuest(900)
assert(E.GetFocusedQuest() == nil)
E.FocusQuest(900)
for _=1,3 do E.ValidateQuestFocus({ { questID=901 } }, false) end
assert(E.GetFocusedQuest() == nil, "stale quest focus must not hide unrelated blobs")
C_QuestLog = { GetQuestObjectives=function() return {
    { finished=true, text="Collected 3/3" },
    { finished=false, text="Defeat rare: 0/1" },
} end }
assert(E.ObjectiveProgress(900) == "1/2 objectives")
assert(#E.ObjectiveLines(900) == 1 and E.ObjectiveLines(900)[1] == "Defeat rare: 0/1",
    "quest tooltips should surface the unfinished objective text")

db.vignetteRadarBreadcrumbs = true
assert(#E.UpdateTrail(player, 10, 0) == 1 and E.GetTrail()[1].arc == 0,
    "the first position must anchor the route before any movement")
current = 4
player.worldX = 210
assert(#E.UpdateTrail(player, 10, current) == 2)
current = 8
player.worldX = 220
assert(#E.UpdateTrail(player, 10, current) == 3)
assert(#E.UpdateTrail(player, 11, current) == 1, "new map must discard earlier trail points")
db.vignetteRadarTrailLifetime = 300
current, player.worldX = 200, 230
assert(#E.UpdateTrail(player, 11, current) == 2,
    "five-minute fade must retain a point older than the original three-minute limit")
assert(E.GetTrail()[2].breakBefore and E.GetTrail()[2].arc == 0,
    "a long pause must start a new route instead of drawing across missing travel")
db.vignetteRadarTrailLifetime = 60
current = 201
assert(#E.UpdateTrail(player, 11, current) == 1,
    "one-minute fade must prune expired trail points")
db.vignetteRadarTrailLifetime = 180
db.vignetteRadarTrailLifetime = 1
current, player.worldX = 202, 232
assert(#E.UpdateTrail(player, 11, current) == 1,
    "a one-second fade must prune older trail history")
current, player.worldX = 202.3, 233
assert(#E.UpdateTrail(player, 11, current) == 2,
    "short fades must sample movement often enough to produce a visible trail")
db.vignetteRadarTrailLifetime = 180

assert(not E.BackRouteStop() and not E.UndoRouteEdit(),
    "an untouched route has nothing to revisit or undo")
assert(E.AddPin(player, "Temporary pin"))
assert(E.UndoRouteEdit() and #E.GetPins(10) == 0,
    "undo should restore a pin list after an accidental addition")
assert(E.AddPin(player, "Cave mouth"))
local pin = E.GetPins(10)[1]
assert(pin and pin.name == "Cave mouth" and pin.mapX == .2)
assert(E.AddRouteStop(pin))
assert(E.AddRouteStop(target))
assert(#E.GetRoute(10) == 2)
assert(E.UndoRouteEdit() and #E.GetRoute(10) == 1,
    "undo should remove an accidentally added stop")
assert(E.AddRouteStop(target))
assert(E.PopRouteStop() and #E.GetRoute(10) == 1
    and E.GetRoute(10)[1].name == "Rare One", "next should advance the route")
assert(E.BackRouteStop() and #E.GetRoute(10) == 2
    and E.GetRoute(10)[1].name == "Cave mouth", "back should restore the previous stop")
assert(E.UndoRouteEdit() and #E.GetRoute(10) == 1
    and E.GetRoute(10)[1].name == "Rare One", "undo should reverse back")
assert(E.UndoRouteEdit() and #E.GetRoute(10) == 2
    and E.GetRoute(10)[1].name == "Cave mouth", "undo should reverse next")
E.RemovePin(pin.id)
assert(#E.GetPins(10) == 0 and #E.GetRoute(10) == 1,
    "deleting a pin should remove its route stop")
assert(E.UndoRouteEdit() and #E.GetPins(10) == 1 and #E.GetRoute(10) == 2,
    "undo should restore an accidentally deleted pin and route stop")
assert(E.ClearRoute() and #E.GetRoute(10) == 0)
assert(E.UndoRouteEdit() and #E.GetRoute(10) == 2,
    "undo should restore a cleared route")
assert(E.PopRouteStop())
for _=1,7 do assert(E.AddRouteStop(target)) end
assert(#E.GetRoute(10) == 8 and not E.BackRouteStop(),
    "back must not exceed the route's eight-stop cap")
assert(E.UndoRouteEdit() and #E.GetRoute(10) == 7,
    "failed back must not consume undo history")
assert(E.ClearRoute() and #E.GetRoute(10) == 0)
E.RemovePin(pin.id)
assert(#E.GetPins(10) == 0)
assert(E.AddRouteStop(target))
assert(not E.ApplyRouteDraft({ target, { name = "Broken stop" } })
    and #E.GetRoute(10) == 1,
    "a bad preview must leave the saved route untouched")
assert(E.ApplyRouteDraft({
    { name = "First", mapID = 10, worldX = 180, worldY = 180 },
    { name = "Second", mapID = 10, worldX = 190, worldY = 190 },
}) and #E.GetRoute(10) == 2 and E.GetRoute(10)[1].name == "First",
    "applying a valid preview must replace the route in one edit")
assert(E.UndoRouteEdit() and #E.GetRoute(10) == 1
    and E.GetRoute(10)[1].name == "Rare One",
    "the entire applied draft must undo as one action")
assert(E.ClearRoute())

-- Arrival is opt-in and crossing-based: entering the radius advances one stop,
-- while loading beside a stop does not silently consume the route.
assert(E.AddRouteStop({ name="Arrival stop", mapID=10, worldX=300, worldY=300, instanceID=7 }))
db.vignetteRadarRouteAutoAdvance = true
db.vignetteRadarRouteArrivalRadius = 20
player.worldX, player.worldY = 300, 300
assert(not E.CheckRouteArrival(player, 10) and #E.GetRoute(10) == 1)
player.worldX = 330
assert(not E.CheckRouteArrival(player, 10))
player.worldX = 319
assert(E.CheckRouteArrival(player, 10) and #E.GetRoute(10) == 0)
assert(E.BackRouteStop() and E.GetRoute(10)[1].name == "Arrival stop")
E.ClearRoute()
db.vignetteRadarRouteAutoAdvance = false

db.vignetteRadarApproachAlerts = true
db.vignetteRadarApproachDistance = 50
assert(E.Watch(target))
assert(E.IsWatched(target))
player.worldX = 200
assert(E.CheckApproach({target}, player, 10) == nil)
player.worldX = 260
assert(E.CheckApproach({target}, player, 10) == target,
    "approach alerts only when a watched target crosses the threshold")
assert(E.CheckApproach({target}, player, 10) == nil)
local unplaced = { key = "unplaced", name = "No position", worldY = 0 }
assert(E.Watch(unplaced) and E.CheckApproach({ unplaced, target }, player, 10) == nil,
    "a watched target without world coordinates must be skipped, not error")
assert(E.CheckApproach({target}, { worldY = 0 }, 10) == nil,
    "a player without world coordinates must not error")
local longKey = { key = string.rep("k", 90), name = "Long key", worldX = 0, worldY = 0 }
assert(E.Watch(longKey) and E.IsWatched(longKey),
    "Watch and IsWatched must agree on the stored key")
assert(not E.Watch(unplaced) and not E.Watch(longKey))
assert(not E.Watch(target))

db.vignetteRadarJournalEnabled = true
E.RecordSightings({target}, 10)
E.RecordSightings({target}, 10)
assert(#db.vignetteRadarJournal == 1 and db.vignetteRadarJournal[1].at == 123456)
E.ClearJournal()
assert(#db.vignetteRadarJournal == 0)

-- Recording is independent of the on-screen trail and stores a bounded,
-- simplified route through the actual corners of the walk.
db.vignetteRadarBreadcrumbs = false
current = 300
player.worldX, player.worldY, player.mapID = 200, 300, 10
assert(E.StartWalkRecording(player))
assert(E.GetWalkRecording().active and E.GetWalkRecording().points == 1)
for _, sample in ipairs({
    {303, 210, 300}, {306, 220, 300}, {309, 220, 320}, {312, 240, 320},
}) do
    current, player.worldX, player.worldY = sample[1], sample[2], sample[3]
    E.UpdateTrail(player, 10, current)
end
assert(E.GetWalkRecording().points == 5 and E.GetWalkRecording().distance == 60,
    "a walk should sample movement even when the visible trail is disabled")
assert(E.PauseWalkRecording() and not E.GetWalkRecording().active)
assert(E.ResumeWalkRecording(player) and E.GetWalkRecording().active)
local saved, path = E.SaveWalkRecording("Corner Walk", player)
assert(saved and path.name == "Corner Walk" and path.distance == 60
    and #path.points >= 4 and #path.points <= 8,
    "saved walks must preserve meaningful turns in a bounded route")
assert(E.GetWalkRecording() == nil and E.GetWalkPaths()[1] == path)
assert(E.ReplayWalkPath(path.id, player) and #E.GetRoute(10) >= 2
    and E.GetRoute(10)[1].worldX == 220 and E.GetRoute(10)[1].worldY == 320,
    "a replay started at the far end should reverse and skip the occupied start")
assert(E.UndoRouteEdit() and #E.GetRoute(10) == 0,
    "replaying a walk should undo as one route edit")
player.mapID = 11
assert(not E.ReplayWalkPath(path.id, player), "replays must stay on their recorded map")
assert(E.DeleteWalkPath(path.id) and #E.GetWalkPaths() == 0)
player.mapID = 10
assert(E.StartWalkRecording(player))
current, player.worldX = 315, 250
E.UpdateTrail(player, 10, current)
current, player.mapID = 318, 11
E.UpdateTrail(player, 11, current)
assert(not E.GetWalkRecording().active and not E.ResumeWalkRecording(player),
    "changing map must stop an active walk rather than connect unrelated positions")
assert(E.CancelWalkRecording())
player.mapID = 10

db.vignetteRadarCategories = { rare=true, treasure=true, event=true, other=true }
db.vignetteRadarColors.accent = { .1, .2, .3 }
assert(E.SavePreset("My Hunt"))
db.vignetteRadarRange = 150
db.vignetteRadarColors.accent[1] = .9
assert(E.ApplyPreset("My Hunt") and db.vignetteRadarRange == 450)
assert(db.vignetteRadarColors.accent[1] == .1, "custom colors must be copied into named presets")
assert(E.ApplyPreset("Treasure") and db.vignetteRadarCategories.rare == false
    and db.vignetteRadarCategories.treasure == true)
print("vignette radar exploration tests passed")
