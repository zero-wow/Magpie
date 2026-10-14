-- luacheck: globals VignetteRadarDB WaffleHouseDB
-- Collection Tracking Bridge: tracked mounts/appearances become radar notes
-- (sources on this map, else the next waypoint here), cached until a
-- tracking event, never dropped by Declutter, and routable on Closest.
VignetteRadarDB, WaffleHouseDB = nil, nil
local clock = 100
_G.GetTime = function() return clock end
local onMap, waypoints, calls = {}, {}, 0
_G.C_ContentTracking = {
    GetCollectableSourceTypes = function() return { 0, 1 } end,
    GetTrackablesOnMap = function(trackableType)
        calls = calls + 1
        return 0, onMap[trackableType] or {}
    end,
    GetTrackedIDs = function(trackableType)
        return trackableType == 1 and { 501, 502 } or { 77 }
    end,
    GetNextWaypointForTrackable = function(_, id)
        local info = waypoints[id]
        if info then return 0, info end
        return 2, nil
    end,
    GetTitle = function(trackableType, id) return (trackableType == 1 and "Mount " or "Look ") .. id end,
    GetObjectiveText = function() return "Kill the boss" end,
}
_G.C_Map = { GetWorldPosFromMapPos = function(_, v) return 7, { x = v.x * 1000, y = v.y * 1000 } end }
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Recent.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Declutter.lua"))("VignetteRadar", addon)
assert(loadfile("Data/CollectionTracking.lua"))("VignetteRadar", addon)
local Tracking = assert(addon.VignetteRadarCollectionTracking)
local settings = addon.GetSettings()
assert(settings.vignetteRadarCollectionTracking == true and settings.vignetteRadarCollectionTrackingRoute == true,
    "defaults on")

onMap[0] = { { x = .5, y = .25, trackableType = 0, trackableID = 77, targetType = 0, targetID = 9,
    waypointText = "Drops from Big Boss" } }
waypoints[501] = { x = .1, y = .9, trackableType = 1, trackableID = 501, targetType = 1, targetID = 4,
    waypointText = "Take the portal" }
waypoints[502] = { x = 2, y = .5, trackableType = 1, trackableID = 502 } -- off map

local notes = Tracking.Collect(2371)
assert(#notes == 2, "one source on the map plus one next waypoint: " .. #notes)
local source, way = notes[1], notes[2]
assert(source.contentTracking and source.kind == "item" and source.name == "Look 77" and source.mapX == .5
    and source.worldX == 500 and source.worldY == 250 and source.instanceID == 7 and source.note == "Drops from Big Boss"
    and source.key == "track:0:77:5000:2500" and source.trackLabel == "Appearance" and not source.waypoint,
    "a tracked source becomes a note")
assert(way.waypoint and way.name == "Mount 501" and way.note == "Next Step: Take the portal", "next waypoint here")

-- Cached until an event or 30 s.
local before = calls
Tracking.Collect(2371)
assert(calls == before, "cached")
Tracking.Invalidate()
Tracking.Collect(2371)
assert(calls > before, "rebuilt after a tracking change")

-- AppendTo, and off.
local scan = { { key = "x" } }
assert(Tracking.AppendTo(scan, 2371) == 2 and #scan == 3)
settings.vignetteRadarCollectionTracking = false
assert(#Tracking.Collect(2371) == 0, "switch off")
settings.vignetteRadarCollectionTracking = true

-- Declutter never drops them, even with "packs only within".
settings.vignetteRadarDeclutterRange = 150
local kept = addon.VignetteRadarDeclutter.Apply(Tracking.Collect(2371), {}, { worldX = 0, worldY = 0 }, settings)
assert(#kept == 2, "tracked points survive declutter")
settings.vignetteRadarDeclutterRange = 0

-- Routable on Closest while the route switch is on.
assert(Tracking.Routable(source, settings) and not Tracking.Routable({ kind = "item" }, settings))
settings.vignetteRadarCollectionTrackingRoute = false
assert(not Tracking.Routable(source, settings))
print("collection_tracking_test ok")
