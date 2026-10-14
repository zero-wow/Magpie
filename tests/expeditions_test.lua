local path = arg[1] or "Routes/Expeditions.lua"
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile(path))("VignetteRadar", addon)
local Expeditions = assert(addon.VignetteRadarExpeditions)

local player = { mapID = 17, worldX = 0, worldY = 0 }
local goals = {
    { id = "rare", kind = "rare", name = "Nearby rare", mapID = 17,
        mapX = .1, mapY = .2, worldX = 10, worldY = 0 },
    { id = "quest", kind = "quest", name = "Quest", mapID = 17,
        mapX = .2, mapY = .3, worldX = 25, worldY = 0 },
    { id = "treasure", kind = "treasure", name = "Locked chest", mapID = 17,
        mapX = .3, mapY = .4, worldX = 5, worldY = 0,
        dependsOn = { "quest" } },
    { id = "unmapped", kind = "pin", name = "Unmapped note" },
}
local trip = assert(Expeditions.New(goals, { priority = {
    rare = 80, quest = 50, treasure = 50 } }))
assert(trip ~= goals and trip.goals[1] ~= goals[1]
    and trip.goals[3].dependsOn ~= goals[3].dependsOn,
    "SavedVariables trip must be detached from input records")
local state, reason = Expeditions.Status(trip, "treasure")
assert(state == "blocked" and reason:find("Quest"),
    "dependency should hold even a nearer chest")
assert(Expeditions.Status(trip, "unmapped") == "unknown",
    "an unmapped goal remains explicit but cannot route")

local now, nextStop = Expeditions.Plan(trip, player)
assert(now.id == "rare" and nextStop.id == "quest" and trip.currentID == "rare",
    "priority should choose an available rare and explain the next stop")
assert(now.reason and nextStop.reason and now.distanceKind == "straight-line yards",
    "Now/Next should carry reasons and honest distance units")
assert(Expeditions.SetPriority(trip, "quest", 100))
local stable = Expeditions.Plan(trip, { mapID = 17, worldX = 24, worldY = 0 })
assert(stable.id == "rare", "an active stop must not bounce after priority or movement changes")
local remote = Expeditions.Plan(trip, { mapID = 18, worldX = 0, worldY = 0 })
assert(remote.id == "rare" and remote.reason:find("distance unavailable"),
    "map changes must retain the current stop without claiming distance")

assert(Expeditions.Pause(trip, true))
local paused, _, pausedReason = Expeditions.Plan(trip, player)
assert(paused == nil and pausedReason == "Trip paused" and trip.currentID == "rare",
    "pause should suppress guidance without deleting progress")
assert(Expeditions.Pause(trip, false))
assert(Expeditions.Skip(trip))
local afterSkip = Expeditions.Plan(trip, player)
assert(afterSkip.id == "quest" and Expeditions.Status(trip, "rare") == "skipped",
    "manual Skip should advance to the next available goal")
assert(Expeditions.Complete(trip, "quest"))
assert(Expeditions.Status(trip, "treasure") == "available",
    "confirmed completion should release a dependency")
local afterCompletion = Expeditions.Plan(trip, player)
assert(afterCompletion.id == "treasure",
    "a newly available dependent goal can become the current stop")

assert(Expeditions.Lock(trip, "unmapped"))
local noMapped, _, noMappedReason = Expeditions.Plan(trip, player)
assert(noMapped and noMapped.id == "treasure" and noMappedReason == nil,
    "an unmapped lock must not trap routing when another mapped goal exists")
assert(Expeditions.Lock(trip, nil))
assert(Expeditions.Reorder(trip, "unmapped", 1) and trip.goals[1].id == "unmapped")
assert(not Expeditions.Reorder(trip, "unmapped", 100))

local lockTrip = assert(Expeditions.New({
    { id = "far", kind = "quest", mapID = 17, mapX = .7, mapY = .7,
        worldX = 100, worldY = 0 },
    { id = "near", kind = "quest", mapID = 17, mapX = .1, mapY = .1,
        worldX = 10, worldY = 0 },
}))
assert(Expeditions.Lock(lockTrip, "far"))
local locked = Expeditions.Plan(lockTrip, player)
assert(locked.id == "far" and locked.reason == "Locked stop",
    "a mapped manual lock must control the next selection")
assert(Expeditions.Lock(lockTrip, nil) and Expeditions.Skip(lockTrip, "far"))
local unlocked = Expeditions.Plan(lockTrip, player)
assert(unlocked.id == "near", "unlock and Skip should release selection")

local bad = Expeditions.New({
    { id = "a", kind = "quest", dependsOn = { "b" } },
    { id = "b", kind = "quest", dependsOn = { "a" } },
})
assert(bad == nil, "cycles must be rejected")
assert(Expeditions.New({ { id = "a", kind = "quest", dependsOn = { "missing" } } }) == nil,
    "unknown prerequisites must be rejected")
assert(Expeditions.New({ { id = "bad", kind = "quest", mapID = 17, mapX = 1.5, mapY = 0 } }) == nil,
    "invalid map coordinates must be rejected")
local limited = {}
for index = 1, 65 do limited[index] = { id = tostring(index), kind = "pin" } end
assert(Expeditions.New(limited) == nil, "trip size must be capped")

io.write("expeditions tests passed\n")
