-- luacheck: globals VignetteRadarDB WaffleHouseDB
-- Nameplate Marker: focus / favourites / every rare, matched on the
-- vignette GUID or its npcID; secret GUIDs are skipped.
VignetteRadarDB, WaffleHouseDB = nil, nil
local mock = dofile("tests/ui_mock.lua").Install()
local addon = {}
local guids, classes, secret = {}, {}, {}
_G.issecretvalue = function(value) return secret[value] == true end
_G.UnitGUID = function(unit) return guids[unit] end
_G.UnitClassification = function(unit) return classes[unit] or "normal" end
local plates = {}
_G.C_NamePlate = {
    GetNamePlateForUnit = function(unit) return plates[unit] end,
    GetNamePlates = function()
        local list = {}
        for _, plate in pairs(plates) do list[#list + 1] = plate end
        return list
    end,
}
local function AddPlate(unit, guid, class)
    plates[unit] = mock.New("Frame")
    plates[unit].namePlateUnitToken = unit
    guids[unit], classes[unit] = guid, class
end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
assert(loadfile("UI/NameplateMarker.lua"))("VignetteRadar", addon)
local Marker = assert(addon.VignetteRadarNameplateMarker)
local settings = addon.GetSettings()
assert(settings.vignetteRadarNameplateMarker == true and settings.vignetteRadarNameplateMarkerWho == "favorite")

local favorite = {}
addon.VignetteRadarFeatures = { IsFavorite = function(target) return favorite[target] == true end }
addon.VignetteRadarWorldFocus = { SelectTarget = function() return true end, GetActiveTarget = function() return nil end }

assert(Marker.NpcFromGUID("Creature-0-1-2-3-4567-0000ABCDEF") == 4567)
assert(Marker.NpcFromGUID("Player-1-0ABC") == nil)

local GUID_A = "Creature-0-1-2-3-111-00000000A1"
local GUID_B = "Creature-0-1-2-3-222-00000000B2"
local rareA = { key = "a", name = "Rare A", category = "rare", objectGUID = GUID_A }
local rareB = { key = "b", name = "Rare B", category = "rare", objectGUID = GUID_B }
local treasure = { key = "t", name = "Chest", category = "treasure", objectGUID = "GameObject-0-1-2-3-9-00" }
AddPlate("nameplate1", GUID_A)
AddPlate("nameplate2", GUID_B)
AddPlate("nameplate3", "Creature-0-1-2-3-333-00000000C3", "rareelite")
AddPlate("nameplate4", "Creature-0-1-2-3-111-00000000FF") -- same npc as A, other spawn

local function Marked(unit)
    local plate = plates[unit]
    for _, frame in ipairs(mock.frames) do
        if frame.parent == plate then return frame.shown == true end
    end
    return false
end

-- Focus a live rare: its plate (and the same npc's other spawn) gets the mark.
addon.VignetteRadarPoints.Publish({ targets = { rareA, rareB, treasure } })
addon.VignetteRadarFocus.Select(addon.VignetteRadarFocus.Target(rareA), { project = false })
assert(Marked("nameplate1") and Marked("nameplate4"), "the focused rare is marked by guid and npc")
assert(not Marked("nameplate2") and not Marked("nameplate3"), "others stay plain")

-- Favourites join in "favorite" mode.
favorite[rareB] = true
Marker.Configure()
assert(Marked("nameplate2"), "a live favourite rare is marked")
settings.vignetteRadarNameplateMarkerWho = "focus"
Marker.Configure()
assert(not Marked("nameplate2") and Marked("nameplate1"), "focus mode marks only the focus")

-- Every Rare: Blizzard's classification marks rares without a vignette.
settings.vignetteRadarNameplateMarkerWho = "rare"
Marker.Configure()
assert(Marked("nameplate3") and Marked("nameplate2"), "every rare mode")

-- A new nameplate is checked as it appears; a removed one loses the mark.
AddPlate("nameplate5", GUID_B)
addon.Bus.Emit("NAME_PLATE_UNIT_ADDED", "nameplate5")
assert(Marked("nameplate5"))
addon.Bus.Emit("NAME_PLATE_UNIT_REMOVED", "nameplate5")
assert(not Marked("nameplate5"))

-- A secret GUID is skipped silently.
secret[GUID_A] = true
settings.vignetteRadarNameplateMarkerWho = "focus"
Marker.Configure()
assert(not Marked("nameplate1"), "secret GUID skipped")
secret[GUID_A] = nil

-- Off clears every mark.
settings.vignetteRadarNameplateMarker = false
Marker.Configure()
for unit in pairs(plates) do assert(not Marked(unit), "off hides " .. unit) end
print("nameplate_marker_test ok")
