local path = arg[1] or "Routes/RouteDraft.lua"
local savedRoute = { { name = "Existing stop", worldX = 900, worldY = 900 } }
local addon = { GetSettings = function() return { vignetteRadarRoute = savedRoute } end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile(path))("VignetteRadar", addon)
local Draft = assert(addon.VignetteRadarRouteDraft)

local player = { mapID = 17, instanceID = 4, worldX = 0, worldY = 0 }
local candidates = {
    { kind = "quest", questID = 21, name = "Quest A", mapID = 17, instanceID = 4,
        worldX = 30, worldY = 0, mapX = .3, mapY = .5 },
    { kind = "quest", questID = 21, name = "Quest A far duplicate", mapID = 17,
        worldX = 50, worldY = 0 },
    { kind = "treasure", key = "chest-1", name = "Chest", mapID = 17, instanceID = 4,
        worldX = 31, worldY = 0 },
    { kind = "pin", id = "personal-1", name = "Pin", mapID = 17, instanceID = 4,
        worldX = 32, worldY = 0 },
    { kind = "quest", questID = 22, name = "Quest B", mapID = 17, instanceID = 4,
        worldX = 100, worldY = 0 },
    { kind = "treasure", key = "chest-2", name = "Second chest", mapID = 17,
        worldX = 101, worldY = 0 },
    { kind = "pin", id = "other-zone", name = "Other map", mapID = 18, instanceID = 4,
        worldX = 10, worldY = 0 },
    { kind = "pin", id = "other-instance", name = "Other instance", mapID = 17, instanceID = 5,
        worldX = 12, worldY = 0 },
    { kind = "pin", id = "too-close", name = "At player", mapID = 17, instanceID = 4,
        worldX = 3, worldY = 0 },
    { kind = "treasure", key = "far", name = "Far chest", mapID = 17, instanceID = 4,
        worldX = 1300, worldY = 0 },
    { kind = "quest", questID = 23, name = "No coordinate", mapID = 17,
        worldX = nil, worldY = 0 },
    { kind = "treasure", key = "old-chest", mapID = 17, worldX = 15, worldY = 0,
        stale = true },
}
local originalName = candidates[1].name
local stops, status = Draft.Build(player, candidates)
assert(#stops == 5 and status.inspected == #candidates and status.eligible == 5
    and status.distanceKind == "straight-line"
    and status.reason == nil and not status.truncated,
    "draft should retain only five known, nearby, unique destinations")
assert(stops[1].questID == 21 and stops[1].name == "Quest A" and stops[1].stepDistance == 30,
    "nearest duplicate quest should win without touching its source")
assert(stops[2].key == "chest-1" and stops[2].stepDistance == 1
    and stops[3].id == "personal-1" and stops[3].stepDistance == 1,
    "nearest-neighbor ordering must use each previous stop and retain destination types")
assert(stops[4].questID == 22 and stops[5].key == "chest-2",
    "remaining destinations should follow by shortest straight-line step")
assert(savedRoute[1].name == "Existing stop" and #savedRoute == 1
    and candidates[1].name == originalName and candidates[1].stepDistance == nil,
    "drafting must not write SavedVariables or mutate caller records")
stops[1].name = "Changed preview"
assert(candidates[1].name == originalName, "preview stops must be detached copies")

local three = Draft.Build(player, candidates, { maxStops = 3, maxDistance = 35 })
assert(#three == 3 and three[3].id == "personal-1",
    "requesting three stops and a short initial range must limit the draft")

local tie = {
    { kind = "pin", id = "z", mapID = 17, worldX = 20, worldY = 0 },
    { kind = "quest", questID = 2, mapID = 17, worldX = 0, worldY = 20 },
    { kind = "treasure", key = "a", mapID = 17, worldX = -20, worldY = 0 },
}
local tied = Draft.Build(player, tie)
assert(tied[1].kind == "pin" and tied[2].kind == "quest" and tied[3].kind == "treasure",
    "equal first distances must use deterministic identity order")
local reverse = { tie[3], tie[2], tie[1] }
local tiedReverse = Draft.Build(player, reverse)
assert(tiedReverse[1].kind == tied[1].kind and tiedReverse[2].kind == tied[2].kind
    and tiedReverse[3].kind == tied[3].kind,
    "candidate input order must not affect tied route order")

local empty, unavailable = Draft.Build({ mapID = 17, worldX = 0 }, candidates)
assert(#empty == 0 and unavailable.reason == "Position unavailable",
    "missing player coordinates should fail closed")
local none, noTargets = Draft.Build(player, { candidates[7], candidates[8] })
assert(#none == 0 and noTargets.reason == "No nearby destinations",
    "mismatched map and instance cannot make preview stops")

local many = {}
for index = 1, 300 do
    many[index] = { kind = "pin", id = tostring(index), mapID = 17,
        worldX = index + 8, worldY = 0 }
end
local limited, bounded = Draft.Build(player, many)
assert(#limited == 5 and bounded.inspected == 256 and bounded.truncated,
    "a draft must inspect a fixed maximum and return no more than five stops")

local secret = {}
issecretvalue = function(value) return value == secret end
local safe = Draft.Build(player, {
    { kind = "quest", questID = 44, mapID = 17, worldX = secret, worldY = 20 },
    { kind = "treasure", key = "safe", mapID = 17, worldX = 20, worldY = 0 },
})
assert(#safe == 1 and safe[1].key == "safe",
    "secret-valued positions must be skipped without breaking the whole draft")

io.write("vignette radar route draft tests passed\n")
