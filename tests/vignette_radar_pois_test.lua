local addon = {}
local settings = { vignetteRadarPOIZoneSources = {} }
addon.GetSettings = function() return settings end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Data/POIs.lua"))("VignetteRadar", addon)
local pois = addon.VignetteRadarPOIs
assert(#pois.Sources() == 0 and #pois.Collect(123, "Missing", function() end, function() end) == 0)

local nodes = {
    [50005000] = { label = "Hidden chest", group = { { name = "treasures" } } },
    [51005000] = { label = "Ancient chest", group = { { name = "treasures" } } },
    [52005000] = { label = "Named rare", group = { { name = "rares" } }, npc = 123 },
    [53005000] = { label = "Profession item", group = { { name = "profession_treasures" } }, loot = 456 },
    [54005000] = { label = "{npc:123:Travel point}", group = { { name = "misc" } }, note = "On the ridge" },
}
local keys = { 50005000, 51005000, 52005000, 53005000, 54005000 }
local calls = 0
HandyNotes = { plugins = {
    Midnight = { GetNodes2 = function(_, mapID, minimap)
        assert(mapID == 123 and minimap == false)
        calls = calls + 1
        local index = 1
        return function()
            index = index + 1 -- simulate plugin hiding the first, completed chest
            local coord = keys[index]
            local icons = {
                [51005000] = { icon = 134400, tCoordLeft = .1, tCoordRight = .9,
                    tCoordTop = .2, tCoordBottom = .8, r = .8, g = .6, b = .4, a = .75 },
                [52005000] = 123456,
                [53005000] = "Interface\\Icons\\INV_Misc_QuestionMark",
            }
            return coord, nil, icons[coord], 1.3, .6
        end, nodes, nil
    end },
    Disabled = { GetNodes2 = function() error("disabled source queried") end },
}, db = { profile = { enabledPlugins = { Midnight = true, Disabled = false } } } }
local sources = pois.Sources()
assert(#sources == 2 and sources[1].id == "Disabled" and not sources[1].enabled
    and sources[2].id == "Midnight" and sources[2].enabled)
local results = pois.Collect(123, "Midnight", function(mapID, vector)
    assert(mapID == 123)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end)
assert(calls == 1 and #results == 4, "only yielded, enabled nodes should be copied")
assert(results[1].kind == "treasure" and results[1].name == "Ancient chest"
    and results[1].worldX == 510 and results[1].worldY == 500)
assert(results[2].kind == "mob" and results[3].kind == "item"
    and results[4].kind == "note" and results[4].name == "Travel point"
    and results[4].note == "On the ridge")
assert(results[1].icon.texture == 134400 and results[1].icon.texCoord[1] == .1
    and results[1].icon.texCoord[4] == .8 and results[1].icon.color[1] == .8
    and results[1].icon.color[4] == .75 and results[1].icon.scale == 1.3
    and results[1].icon.alpha == .6 and results[2].icon.texture == 123456
    and results[3].icon.texture == "Interface\\Icons\\INV_Misc_QuestionMark"
    and results[4].icon == nil,
    "the pack's own file ID, path, crop, tint, and opacity must survive collection")
assert(#pois.Collect(123, "Disabled", function() error("converted disabled source") end,
    function() end) == 0)
assert(pois.Kind(nil, "MidnightTreasures") == "treasure"
    and pois.Kind({ loot = { 123 } }, "MidnightTreasures") == "treasure"
    and pois.Kind({ npc = 123, loot = { 456 } }, "MidnightTreasures") == "mob"
    and pois.Kind(nil, "RareLocations") == "mob"
    and pois.Kind(nil, "GeneralMapPack") == "note")

local now = 100
GetTime = function() return now end
Enum = { UIMapType = { Continent = 2 } }
C_Map = { GetMapInfo = function(mapID)
    if mapID == 125 then return { name = "Garrison", parentMapID = 124, mapType = 5 } end
    if mapID == 124 then return { name = "Frostfire Ridge", parentMapID = 2, mapType = 3 } end
    if mapID == 2 then return { name = "Draenor", parentMapID = 0, mapType = 2 } end
    return { parentMapID = 0, mapType = 3 }
end }
local otherZoneCalls = 0
HandyNotes.plugins.OtherZone = { GetNodes2 = function(_, mapID)
    otherZoneCalls = otherZoneCalls + 1
    if mapID ~= 124 then return function() end, {}, nil end
    local done = false
    return function()
        if done then return nil end
        done = true
        return 52005000, nil, nil, 1, 1
    end, { [52005000] = { label = "Other zone" } }, nil
end }
local zoneSources = pois.ZoneSources(123)
assert(#zoneSources == 1 and zoneSources[1].id == "Midnight"
    and zoneSources[1].mapID == 123 and zoneSources[1].count == 4,
    "current-zone sources must exclude unrelated and disabled packs")
local chosen, dataMap = pois.ResolveSource(123, "auto")
assert(chosen == "Midnight" and dataMap == 123)
assert(pois.SetZoneChoice(123, "Midnight") and pois.ZoneChoice(123) == "Midnight"
    and pois.ResolveSource(123, "auto") == "Midnight")
assert(pois.SetZoneChoice(123, "none") and pois.ResolveSource(123, "auto") == nil)
assert(pois.SetZoneChoice(123, nil) and pois.ZoneChoice(123) == nil
    and pois.ResolveSource(123, "auto") == "Midnight")
chosen, dataMap = pois.ResolveSource(125, "auto")
assert(chosen == "OtherZone" and dataMap == 124,
    "a zone pack on the parent map must be found from a nested map")
assert(pois.ResolveSource(125, "Midnight") == nil
    and pois.ResolveSource(125, "none") == nil,
    "manual sources must not leak data into unrelated zones")
local callsBeforeCache = otherZoneCalls
assert(#pois.ZoneSources(125) == 1 and otherZoneCalls == callsBeforeCache,
    "repeated source lookups must reuse the map snapshot")
local previousZoneCalls = calls
pois.ZoneSources(123)
assert(calls == previousZoneCalls,
    "crossing between nearby map IDs must retain both recent source snapshots")
HandyNotes.plugins.SparseZone = { GetNodes2 = function(_, mapID)
    if mapID ~= 123 then return function() end, {}, nil end
    local done = false
    return function()
        if done then return nil end
        done = true
        return 50005000, nil, nil, 1, 1
    end, {}, nil
end }
chosen, dataMap = pois.ResolveSource(123, "auto")
assert(chosen == "Midnight" and dataMap == 123,
    "Auto must prefer the pack with more current-zone notes")
HandyNotes.plugins.DenseZone = { GetNodes2 = function(_, mapID)
    if mapID ~= 123 then return function() end, {}, nil end
    local index = 0
    return function()
        index = index + 1
        if index > 8 then return nil end
        return 50000000 + index * 10000, nil, nil, 1, 1
    end, {}, nil
end }
chosen = pois.ResolveSource(123, "auto")
assert(chosen == "Midnight", "Auto should not change packs mid-zone as note counts update")
HandyNotes.plugins.TravelGuide = { GetNodes2 = function(_, mapID)
    if mapID ~= 124 then return function() end, {}, nil end
    local index = 0
    return function()
        index = index + 1
        if index > 12 then return nil end
        return 50000000 + index * 10000, nil, nil, 1, 1
    end, {}, nil
end }
HandyNotes.plugins.DraenorTreasures = { GetNodes2 = function(_, mapID)
    if mapID ~= 2 then return function() end, {}, nil end
    local done = false
    return function()
        if done then return nil end
        done = true
        return 50005000, nil, nil, 1, 1
    end, {}, nil
end }
chosen, dataMap = pois.ResolveSource(125, "auto")
assert(chosen == "DraenorTreasures" and dataMap == 2,
    "Auto must find a continent-level expansion pack and prefer it over a sticky TravelGuide source")
assert(#pois.ZoneSources(999) == 0, "unrelated zones must show no data packs")
local tooltipCalls = 0
C_TooltipInfo = { GetHyperlink = function(link)
    tooltipCalls = tooltipCalls + 1
    assert(link == "unit:Creature-0-0-0-0-245699")
    return { lines = { { leftText = "Ancient Watcher" } } }
end }
HandyNotes.plugins.TokenPack = { GetNodes2 = function()
    local done = false
    return function()
        if done then return nil end
        done = true
        return 55005500, nil, nil, 1, 1
    end, { [55005500] = { label = "{npc:245699}", npc = 245699,
        group = "rares", quest = 12345, note = "Find {npc:245699} here." } }, nil
end }
local tokenNotes = pois.Collect(123, "TokenPack", function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x=x, y=y } end)
assert(#tokenNotes == 1 and tokenNotes[1].name == "Ancient Watcher"
    and tokenNotes[1].note == "Find Ancient Watcher here."
    and tokenNotes[1].npcID == 245699 and tokenNotes[1].questID == 12345
    and tooltipCalls == 1,
    "numeric NPC tokens must resolve to the real name and cache repeat lookups")

local cache = { label = "Hidden cache", group = "treasures", path = { 45005000, 40005000 },
    _coord = 50005000 }
cache._main = cache
local entrance = setmetatable({ label = "Path to treasure", path = false,
    routes = { { 50005000, 45005000, 40005000 } } },
    { __index = cache })
HandyNotes.plugins.PathPack = { GetNodes2 = function()
    local keys, index = { 50005000, 40005000 }, 0
    return function()
        index = index + 1
        return keys[index], nil, nil, 1, 1
    end, { [50005000] = cache, [40005000] = entrance }, nil
end }
local pathNotes = pois.Collect(123, "PathPack", function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end)
assert(#pathNotes == 2 and pathNotes[1].kind == "treasure"
    and pathNotes[1].route and #pathNotes[1].route == 3
    and pathNotes[1].route[1].worldX == 400
    and pathNotes[1].route[2].worldX == 450
    and pathNotes[1].route[3].worldX == 500
    and pathNotes[2].kind == "entrance" and pathNotes[2].parentCoord == 50005000,
    "a pack path must yield an informational entrance and ordered entrance-to-treasure stops")
HandyNotes.plugins.PathPack.GetNodes2 = function()
    local sent = false
    return function()
        if sent then return nil end
        sent = true
        return 50005000, nil, nil, 1, 1
    end, { [50005000] = cache }, nil
end
local hiddenEntrance = pois.Collect(123, "PathPack", function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end)
assert(#hiddenEntrance == 2 and hiddenEntrance[2].kind == "entrance"
    and hiddenEntrance[2].worldX == 400 and hiddenEntrance[2].parentCoord == 50005000,
    "an explicit parent path should supply an entrance even if the pack hides its own path pin")
assert(pois.Kind({ link = 123, atlas = "CaveUnderground-Down" }, "MapLinks") == "entrance")

ZygorGuidesViewer = { Poi = { DoneLoadingPoints = true, Points = {
    [123] = { { type = "treasure", name = "Zygor cache", x = .6, y = .4,
        comment = "Find the key first", quest = 77 } },
} } }
local zygor, zygorMap = pois.ResolveSource(123, "Zygor POIs")
assert(zygor == "Zygor POIs" and zygorMap == 123,
    "Zygor must be selectable as a zone-scoped source")
local zygorNotes = pois.Collect(123, "Zygor POIs", function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end)
assert(#zygorNotes == 1 and zygorNotes[1].name == "Zygor cache"
    and zygorNotes[1].kind == "treasure" and zygorNotes[1].icon == nil
    and zygorNotes[1].worldX == 600 and zygorNotes[1].zygorPoint,
    "Zygor POIs should use bounded local coordinates and our default note dots")
local handyNotes = HandyNotes
HandyNotes = nil
assert(#pois.Collect(123, "Zygor POIs", function(_, vector)
    return vector.x * 1000, vector.y * 1000, 42
end, function(x, y) return { x = x, y = y } end) == 1,
    "Zygor POIs must remain usable without HandyNotes")
HandyNotes = handyNotes
assert(pois.ResolveSource(123, "auto") ~= "Zygor POIs",
    "Auto should preserve HandyNotes pack choice until Zygor is explicitly chosen")
local beforeRescan = calls
pois.Invalidate()
pois.ZoneSources(123)
assert(calls > beforeRescan, "manual rescan must refresh cached pack availability")

-- Auto source must pick up a pack that handles the zone but is not ready yet,
-- a pack enabled after the last probe, and notes that appear a moment later.
do
    local savedHandyNotes, savedZygor, savedMap = HandyNotes, ZygorGuidesViewer, C_Map
    ZygorGuidesViewer = nil
    C_Map = { GetMapInfo = function(mapID)
        if mapID == 300 then return { name = "Midnight", parentMapID = 0, mapType = 3 } end
        return { parentMapID = 0, mapType = 3 }
    end }
    local fresh = {}
    fresh.GetSettings = function() return { vignetteRadarPOIZoneSources = {} } end
    assert(loadfile("Core/Secret.lua"))("VignetteRadar", fresh)
    assert(loadfile("Data/POIs.lua"))("VignetteRadar", fresh)
    local autoPOIs = fresh.VignetteRadarPOIs
    local ready = false
    local zoneNodes = { [40004000] = { label = "Sunken chest", group = { { name = "treasures" } } } }
    -- Zarillion-style: a handled map returns its node table even when the
    -- iterator yields nothing yet (phasing, groups or data not ready).
    local function Pack(handled)
        return { GetNodes2 = function(_, mapID)
            if not handled[mapID] then return function() return nil end, nil, nil end
            local nodes = handled[mapID]
            return function(state, previous)
                if not ready then return nil end
                local coord = next(state, previous)
                if coord then return coord, nil, nil, 1, 1 end
                return nil
            end, nodes, nil
        end }
    end
    local enabled = { HandyNotes_Midnight = true, HandyNotes_TheWarWithin = false }
    HandyNotes = { plugins = {
        HandyNotes_Midnight = Pack({ [300] = zoneNodes }),
        HandyNotes_TheWarWithin = Pack({ [301] = zoneNodes }),
    }, db = { profile = { enabledPlugins = enabled } } }
    local function Convert(_, vector) return vector.x * 1000, vector.y * 1000, 1 end
    local function Vector(x, y) return { x = x, y = y } end

    local source, map = autoPOIs.ResolveSource(300, "auto")
    assert(source == "HandyNotes_Midnight" and map == 300,
        "Auto must pick an enabled pack that handles this zone before its notes are visible")
    ready = true
    assert(#autoPOIs.Collect(map, source, Convert, Vector) == 1,
        "the auto-picked pack must deliver notes as soon as they become visible")
    assert(autoPOIs.ZoneSources(300)[1].count == 0, "within the cache window the snapshot is reused")
    now = now + 3
    assert(autoPOIs.ZoneSources(300)[1].count == 1,
        "an empty probe must only be cached briefly so counts catch up")

    ready = true
    assert(#autoPOIs.ZoneSources(301) == 0)
    enabled.HandyNotes_TheWarWithin = true
    source = autoPOIs.ResolveSource(301, "auto")
    assert(source == "HandyNotes_TheWarWithin",
        "enabling a pack in HandyNotes must refresh the cached zone sources at once")

    ready = false
    HandyNotes.plugins.HandyNotes_Silvermoon = { GetNodes2 = function(_, mapID)
        if mapID ~= 300 then return function() return nil end, nil, nil end
        local done = false
        return function()
            if done then return nil end
            done = true
            return 45004500, nil, nil, 1, 1
        end, { [45004500] = { label = "Visible" } }, nil
    end }
    source = autoPOIs.ResolveSource(300, "auto")
    assert(source == "HandyNotes_Silvermoon",
        "a pack with visible notes must beat a handled pack that shows nothing yet")
    HandyNotes, ZygorGuidesViewer, C_Map = savedHandyNotes, savedZygor, savedMap
end
io.write("vignette radar map-note tests passed\n")
