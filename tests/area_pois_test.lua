-- luacheck: globals VignetteRadarDB WaffleHouseDB
-- Events, delves and races as points: area POIs become radar notes with
-- countdowns, per-kind switches, and Declutter never drops them.
VignetteRadarDB, WaffleHouseDB = nil, nil
local clock = 100
_G.GetTime = function() return clock end
local calls = 0
local function Vec(x, y) return { GetXY = function() return x, y end } end
local infos = {
    [1] = { name = "Storm Surge", position = Vec(.5, .5), atlasName = "minimap-genericevent-hornicon", description = "Kill elementals" },
    [2] = { name = "Ring Race", position = Vec(.2, .2) },
    [3] = { name = "Deep Delve", position = Vec(.8, .8), atlasName = "delves-regular" },
    [4] = { name = "Off Map", position = Vec(1.5, .2) },
}
local timed = { [1] = 600 }
_G.C_AreaPoiInfo = {
    GetEventsForMap = function() calls = calls + 1; return { 1, 4 } end,
    GetDragonridingRacesForMap = function() return { 2 } end,
    GetDelvesForMap = function() return { 3 } end,
    GetAreaPOIInfo = function(_, id) return infos[id] end,
    IsAreaPOITimed = function(id) return timed[id] ~= nil end,
    GetAreaPOISecondsLeft = function(id) return timed[id] end,
}
_G.C_Map = { GetWorldPosFromMapPos = function(_, v) return 7, { x = v.x * 1000, y = v.y * 1000 } end }
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Recent.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Declutter.lua"))("VignetteRadar", addon)
assert(loadfile("Data/AreaPOIs.lua"))("VignetteRadar", addon)
local Area = assert(addon.VignetteRadarAreaPOIs)
local settings = addon.GetSettings()
assert(settings.vignetteRadarAreaPOIs and settings.vignetteRadarAreaPOIRoute
    and settings.vignetteRadarAreaPOIKinds.delve == true, "defaults on")

local notes = {}
assert(Area.AppendTo(notes, 2371, clock) == 3, "three POIs on the map; the off-map one is skipped")
local byID = {}
for _, note in ipairs(notes) do byID[note.areaPoiID] = note end
assert(byID[1].kind == "event" and byID[1].areaKind == "event" and byID[1].name == "Storm Surge (10m)"
    and byID[1].worldX == 500 and byID[1].instanceID == 7 and byID[1].atlasName, "timed event with countdown")
assert(byID[2].kind == "event" and byID[2].areaKind == "race" and byID[2].name == "Ring Race", "race")
assert(byID[3].kind == "entrance" and byID[3].areaKind == "delve", "delve is an entrance")
assert(addon.VignetteRadarPoints.Icon(byID[3]).atlas == "delves-regular", "Blizzard's atlas is the icon")

-- Cached between scans; the countdown moves without a rebuild.
clock = clock + 45
local again = Area.Collect(2371, clock)
assert(calls == 1 and #again == 3 and byID[1].name == "Storm Surge (9m)", "countdown refreshed from cache")
-- An ended event drops out.
timed[1] = 20
Area.Invalidate()
assert(#Area.Collect(2371, clock) == 3 and calls == 2)
clock = clock + 30
assert(#Area.Collect(2371, clock) == 2 and calls == 2, "ended event dropped without a rebuild")

-- AREA_POIS_UPDATED rebuilds; per-kind switches apply.
settings.vignetteRadarAreaPOIKinds.delve = false
addon.Bus.Emit("AREA_POIS_UPDATED")
local list = Area.Collect(2371, clock)
assert(calls == 3 and #list == 2, "rebuilt without delves")
settings.vignetteRadarAreaPOIs = false
assert(#Area.Collect(2371, clock) == 0, "off shows none")
settings.vignetteRadarAreaPOIs = true

-- Declutter's "packs only" switches never drop live area POIs.
settings.vignetteRadarDeclutterLiveOnly, settings.vignetteRadarDeclutterRange = true, 150
local live = { { category = "rare", worldX = 0, worldY = 0 } }
local kept = addon.VignetteRadarDeclutter.Apply(list, live, { worldX = 0, worldY = 0 }, settings)
assert(#kept == #list, "area POIs survive declutter")
print("area_pois_test ok")
