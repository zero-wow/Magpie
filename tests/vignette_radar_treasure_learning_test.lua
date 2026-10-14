local addon, db = {}, {}
addon.GetSettings = function() return db end
local snapshot = { mapID = 123, mapX = .502, mapY = .5,
    worldX = 502, worldY = 500, instanceID = 42 }
addon.VignetteRadarAPI = { GetPlayerSnapshot = function() return snapshot end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Data/TreasureLearning.lua"))("VignetteRadar", addon)
local learning = addon.VignetteRadarTreasureLearning
local clock = 100
GetTime = function() return clock end
time = function() return 1000 + clock end
GetNumLootItems = function() return 1 end
local lootGUID = "GameObject-0-1-1-1-777-000"
GetLootSourceInfo = function() return lootGUID end

local note = { key = "HandyNotes:123:50005000", source = "HandyNotes",
    kind = "treasure", name = "Hidden Cache", objectID = 777,
    mapID = 123, mapX = .5, mapY = .5, worldX = 500,
    worldY = 500, instanceID = 42 }
learning.Sync(123, snapshot, {}, { note })
assert(not learning.OnLootEvent("LOOT_OPENED"))
assert(learning.OnLootEvent("LOOT_SLOT_CLEARED"))
local entry = db.vignetteRadarTreasureLoots[note.key]
assert(entry and entry.source == "HandyNotes" and entry.objectID == 777)
assert(entry.samples[1].worldX == 502 and entry.samples[1].mapX == .502
    and entry.samples[1].match == "object-id" and entry.samples[1].z == nil,
    "confirmed pack loot should save player-at-loot XY without inventing height")
assert(learning.Count() == 1)
-- Loot events reach the module through the bus, with no radar forwarding.
addon.Bus.Emit("LOOT_OPENED")
addon.Bus.Emit("LOOT_SLOT_CLEARED")
assert(#entry.samples == 2, "bus loot events must record a treasure sample")
table.remove(entry.samples)

lootGUID = "GameObject-0-1-1-1-999-000"
learning.OnLootEvent("LOOT_OPENED")
assert(not learning.OnLootEvent("LOOT_SLOT_CLEARED") and #entry.samples == 1,
    "looting a different nearby container must not be attributed to a known chest")
lootGUID = "Creature-0-1-1-1-777-000"
learning.OnLootEvent("LOOT_OPENED")
assert(not learning.OnLootEvent("LOOT_SLOT_CLEARED") and #entry.samples == 1,
    "creature loot must not create a treasure observation")

lootGUID = "GameObject-0-1-1-1-777-000"
learning.OnLootEvent("LOOT_OPENED")
clock = 106
assert(not learning.OnLootEvent("LOOT_SLOT_CLEARED") and #entry.samples == 1,
    "an expired loot window must not save a stale position")
clock = 110
addon.VignetteRadarOutcomeLearning = {
    PlayerHeight = function(current)
        assert(current == snapshot)
        return 74
    end,
}
learning.OnLootEvent("LOOT_OPENED")
assert(learning.OnLootEvent("LOOT_SLOT_CLEARED")
    and entry.samples[#entry.samples].z == 74,
    "confirmed treasure loot should keep a validated player height when exposed")
for index = 1, 260 do
    local item = { key = "Pack:123:" .. index, source = "Pack", kind = "treasure",
        name = "Chest", objectID = 777, mapID = 123, mapX = .5, mapY = .5,
        worldX = 500, worldY = 500, instanceID = 42 }
    learning.Sync(123, snapshot, {}, { item })
    learning.OnLootEvent("LOOT_OPENED")
    assert(learning.OnLootEvent("LOOT_SLOT_CLEARED"))
    clock = clock + 1
end
assert(learning.Count() == 256 and not db.vignetteRadarTreasureLoots[note.key],
    "SavedVariables should retain only the 256 newest treasure locations")
io.write("vignette radar treasure learning tests passed\n")
