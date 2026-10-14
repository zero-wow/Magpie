-- luacheck: globals VignetteRadarDB WaffleHouseDB
-- Learned Rare Spawns: the vignette's own position per npcID, clustered,
-- once per GUID per session, z only near the player, notes per map.
VignetteRadarDB, WaffleHouseDB = nil, nil
local epoch = 5000
_G.GetServerTime = function() return epoch end
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Data/RareSpawns.lua"))("VignetteRadar", addon)
local Spawns = assert(addon.VignetteRadarRareSpawns)
local settings = addon.GetSettings()
assert(settings.vignetteRadarRareSpawnLearning and settings.vignetteRadarRareSpawnNotes, "defaults on")
local height = 77
addon.VignetteRadarOutcomeLearning = { PlayerHeight = function() return height end }

local function Rare(guid, x, y, extra)
    local target = { category = "rare", name = "Big Rare", objectGUID = guid, mapID = 2371,
        mapX = x / 10000, mapY = y / 10000, worldX = x, worldY = y, instanceID = 2552 }
    for key, value in pairs(extra or {}) do target[key] = value end
    return target
end
local player = { worldX = 0, worldY = 0, instanceID = 2552 }

assert(Spawns.NpcID("Creature-0-1-2-3-4242-00000000AA") == 4242 and not Spawns.NpcID("GameObject-0-1-2-3-9-0"))

-- First sight saves the vignette's own position, with z only when close.
assert(Spawns.Observe({ Rare("Creature-0-1-2-3-4242-0000000001", 1000, 1000) }, player) == 1)
local list = Spawns.Spawns(4242)
assert(#list == 1 and list[1].x == 1000 and list[1].y == 1000 and list[1].z == nil and list[1].n == 1
    and list[1].f == 5000 and list[1].m == 2371, "far away: no z")
-- Same GUID later: only lastAt moves.
epoch = 5100
assert(Spawns.Observe({ Rare("Creature-0-1-2-3-4242-0000000001", 1010, 1010) }, player) == 0)
assert(list[1].n == 1 and list[1].l == 5100 and list[1].x == 1000, "one GUID is one sighting")
-- A new spawn of the same rare near the first merges (running mean, z near player).
local near = { worldX = 1015, worldY = 1000, instanceID = 2552 }
assert(Spawns.Observe({ Rare("Creature-0-1-2-3-4242-0000000002", 1020, 1000) }, near) == 1)
assert(#list == 1 and list[1].n == 2 and list[1].x == 1010 and list[1].z == 77, "clustered with z")
-- Far away: a second spawn point.
Spawns.Observe({ Rare("Creature-0-1-2-3-4242-0000000003", 3000, 3000) }, player)
assert(#Spawns.Spawns(4242) == 2, "a far sighting is a new spawn point")
-- Not rares, stale, samples, objects: ignored.
assert(Spawns.Observe({ Rare("Creature-0-1-2-3-5-0000000004", 1, 1, { category = "treasure" }),
    Rare("Creature-0-1-2-3-6-0000000005", 1, 1, { stale = true }),
    Rare("GameObject-0-1-2-3-7-0000000006", 1, 1) }, player) == 0)

-- Notes for the map; a pack note for the same npc nearby covers one.
local notes = Spawns.ForMap(2371)
assert(#notes == 2 and notes[1].kind == "mob" and notes[1].source == "Learned" and notes[1].npcID == 4242
    and notes[1].evidence == "saved", "learned spawns as notes")
local scan = { { key = "pack:1", kind = "mob", npcID = 4242, worldX = 1030, worldY = 1000 } }
assert(Spawns.AppendTo(scan, 2371) == 1 and #scan == 2 and scan[2].worldX == 3000, "pack note wins nearby")
settings.vignetteRadarRareSpawnNotes = false
assert(Spawns.AppendTo({}, 2371) == 0, "notes can be switched off")
settings.vignetteRadarRareSpawnLearning = false
assert(Spawns.Observe({ Rare("Creature-0-1-2-3-9-0000000009", 1, 1) }, player) == 0, "learning off")

-- The Bus feed reads the published live refs.
settings.vignetteRadarRareSpawnLearning = true
addon.VignetteRadarPoints.Publish({ player = player, targets = { Rare("Creature-0-1-2-3-8888-000000000A", 50, 50) } })
assert(#Spawns.Spawns(8888) == 1, "POINTS_CHANGED records live rares")
print("rare_spawns_test ok")
