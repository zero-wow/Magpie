local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/SpatialProjection.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
local S = addon.VignetteRadarSpatial
-- The HUD's strict note-vs-live identity rule now lives in the point registry.
local function StrictMatch(note, target) return addon.VignetteRadarPoints.Matches(note, target, true) end
local function near(actual, expected)
    assert(actual and math.abs(actual - expected) < 0.001,
        ("expected %.3f, got %s"):format(expected, tostring(actual)))
end

local x, y, distance = S.Project(100, 0, 0, 100, 100, .42)
near(x, 0); near(y, 42); near(distance, 100)
x, y = S.Project(0, 100, 0, 100, 100, .42)
near(x, -100); near(y, 0)
x, y = S.Project(-100, 0, 0, 100, 100, .42)
near(x, 0); near(y, -42)
x, y = S.Project(100, 0, math.pi / 2, 100, 100, .42)
near(x, 100); near(y, 0)
near(S.Angle(2 * math.pi - .01), -.01)
assert(S.Project(1, 1, 0, 0, 100, .42) == nil)
assert(S.Project(0 / 0, 1, 0, 100, 100, .42) == nil)

local note = { kind = "treasure", worldX = 0, worldY = 0, name = "Amber Cache" }
local target = { category = "treasure", worldX = 5, worldY = 0, name = "Other Cache" }
assert(not StrictMatch(note, target), "nearby distinct treasures must not merge")
target.name = "Amber Cache"
assert(StrictMatch(note, target))
target.worldX = 61
assert(not StrictMatch(note, target), "remote name match must not merge")
target.worldX, target.name = 5, "Other Cache"
note.objectID = 25
target.objectGUID = "GameObject-0-0-0-0-25-0000000001"
assert(StrictMatch(note, target))
note.objectID = 26
assert(not StrictMatch(note, target), "different object IDs must stay separate")
note.objectID, target.objectGUID = nil, nil
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
target.name = { secret = true }
assert(not StrictMatch(note, target), "secret names must not be compared or exposed")
assert(S.Project({ secret = true }, 1, 0, 100, 100, .42) == nil,
    "secret coordinates must not enter the projection")
print("VignetteRadar spatial projection tests passed")
