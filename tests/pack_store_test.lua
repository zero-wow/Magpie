-- Pack Takeover: harvest a live HandyNotes pack into VR's compact store,
-- read it back once the pack is gone, and hide/restore the pack's own pins
-- through HandyNotes' enabledPlugins + UpdatePluginMap.
local settings = { vignetteRadarPOIZoneSources = {}, vignetteRadarPackRemember = true,
    vignetteRadarPackTakeover = false }
local addon = { GetSettings = function() return settings end }
_G.GetServerTime = function() return 1000 end
_G.GetTime = function() return 0 end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Data/PackStore.lua"))("VignetteRadar", addon)
assert(loadfile("Data/POIs.lua"))("VignetteRadar", addon)
local Store, POIs = assert(addon.VignetteRadarPackStore), assert(addon.VignetteRadarPOIs)

local nodes = {
    [50005000] = { label = "Old Chest", group = { { name = "treasures" } }, quest = 901 },
    [60004000] = { label = "Big\tRare", group = { { name = "rares" } }, npc = 77, note = "On the hill" },
}
local reads, redraws = 0, {}
local handler = { GetNodes2 = function(_, mapID)
    reads = reads + 1
    local keys, index = { 50005000, 60004000 }, 0
    if mapID ~= 123 then return function() return nil end, {}, nil end
    return function()
        index = index + 1
        return keys[index], nil, nil, 1, 1
    end, nodes, nil
end }
local enabled = {}
_G.HandyNotes = { plugins = { Treasures = handler }, db = { profile = { enabledPlugins = enabled } } }
function _G.HandyNotes:UpdatePluginMap(_, name) redraws[#redraws + 1] = name end
local toWorld = function(mapID, v) return v.x * 1000 + mapID, v.y * 1000, 5 end
local vector = function(x, y) return { x = x, y = y } end

-- A live read saves the zone once per session.
local live = POIs.Collect(123, "Treasures", toWorld, vector)
assert(#live == 2, "live pack read")
local zone = settings.vignetteRadarPackCache.Treasures[123]
assert(zone and zone.n == 2 and zone.at == 1000 and type(zone.d) == "string", "zone saved as one string")
assert(not zone.d:find("Big\tRare", 1, true), "tabs in names are cleaned")
local generation = Store.Generation()
POIs.Collect(123, "Treasures", toWorld, vector)
assert(Store.Generation() == generation, "a second read in the session does not re-save")

-- The pack is disabled in the AddOns list: VR's saved copy takes over.
_G.HandyNotes.plugins.Treasures = nil
POIs.Invalidate()
local sources = POIs.Sources()
assert(#sources == 1 and sources[1].id == "Treasures" and sources[1].saved, "saved pack is still a source")
local zoneSources = POIs.ZoneSources(123)
assert(#zoneSources == 1 and zoneSources[1].count == 2 and zoneSources[1].mapID == 123, "saved zone is found")
assert(POIs.ResolveSource(123, "auto") == "Treasures", "auto picks the saved pack")
local saved = POIs.Collect(123, "Treasures", toWorld, vector)
assert(#saved == 2, "saved notes come back")
local byKey = {}
for _, note in ipairs(saved) do byKey[note.key] = note end
local chest, rare = byKey["Treasures:123:50005000"], byKey["Treasures:123:60004000"]
assert(chest and chest.kind == "treasure" and chest.questID == 901 and chest.name == "Old Chest"
    and chest.mapX == .5 and chest.mapY == .5 and chest.worldX == 623 and chest.instanceID == 5,
    "a saved note keeps key, kind, quest, name and world position")
assert(rare and rare.kind == "mob" and rare.npcID == 77 and rare.note == "On the hill"
    and rare.evidence == "saved", "a saved rare keeps npc and note")
assert(POIs.Collect(123, "Treasures", toWorld, vector)[1] == saved[1], "parsed once per zone")
assert(#POIs.Collect(999, "Treasures", toWorld, vector) == 0, "unsaved zones are empty")

-- Takeover hides the pack's own pins and VR keeps reading it.
_G.HandyNotes.plugins.Treasures = handler
_G.HandyNotes.plugins.UserOff = { GetNodes2 = handler.GetNodes2 }
enabled.UserOff = false
settings.vignetteRadarPackTakeover = true
assert(Store.ApplyTakeover() == 1, "one visible pack hidden")
assert(enabled.Treasures == false and redraws[1] == "Treasures", "HandyNotes redraws the hidden pack")
assert(Store.HiddenByVR("Treasures") and not Store.HiddenByVR("UserOff"), "VR remembers only its own")
local readsBefore = reads
assert(#POIs.Collect(123, "Treasures", toWorld, vector) == 2 and reads > readsBefore,
    "a pack VR hid is still read live")
assert(#POIs.Collect(123, "UserOff", toWorld, vector) == 0, "a pack the user hid stays off")
settings.vignetteRadarPackTakeover = false
assert(Store.ApplyTakeover() == 1 and enabled.Treasures == true and enabled.UserOff == false,
    "switching off restores only what VR hid")
assert(not Store.HiddenByVR("Treasures"))

-- Remember off: nothing new is saved and Clear empties the store.
Store.Clear()
settings.vignetteRadarPackRemember = false
POIs.Collect(123, "Treasures", toWorld, vector)
assert(next(settings.vignetteRadarPackCache) == nil, "remember off saves nothing")
print("pack_store_test ok")
