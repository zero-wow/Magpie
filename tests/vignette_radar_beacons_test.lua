local source = arg[1] or "Routes/Beacons.lua"
local settings = {
    vignetteRadarEnabled = true, vignetteRadarBeaconsEnabled = false,
    vignetteRadarBeaconRares = true, vignetteRadarBeaconTreasures = false,
    vignetteRadarBeaconQuests = true,
    vignetteRadarBeaconRange = 450, vignetteRadarBeaconMax = 8,
    vignetteRadarPOISource = "auto", vignetteRadarMapNotesVisible = true,
    vignetteRadarPOITypes = { mob = true, treasure = true },
    vignetteRadarQuestColors = true,
}
local addon = {
    GetSettings = function() return settings end,
    VignetteRadarStyle = { Color = function(slot)
        if slot == "rare" then return .8, .9, 1 end
        if slot == "boss" then return 1, .2, .1 end
        if slot == "treasure" then return 1, .7, .2 end
        return .6, .8, 1
    end },
    VignetteRadarQuestColors = { { .3, .7, 1 } },
}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Compass.lua"))("VignetteRadar", addon)
assert(loadfile(source))("VignetteRadar", addon)
local beacons = addon.VignetteRadarBeacons

CreateFrame = function() error("disabled beacons must not create a frame") end
beacons.Sync(1, { worldX = 0, worldY = 0 }, {}, {}, {})

local player = { worldX = 0, worldY = 0, instanceID = 8 }
local rare = { key = "rare-1", name = "Live rare", category = "rare",
    mapX = .4, mapY = .3, worldX = 100, worldY = 0, instanceID = 8 }
local boss = { key = "boss-1", name = "World boss", category = "rare", isWorldBoss = true,
    mapX = .2, mapY = .3, worldX = 300, worldY = 0, instanceID = 8 }
local stale = { key = "stale", category = "rare", stale = true,
    mapX = .1, mapY = .3, worldX = 50, worldY = 0, instanceID = 8 }
local quest = { questID = 17, name = "Find the stones", colorSlot = 1,
    mapX = .6, mapY = .3, worldX = 80, worldY = 10, instanceID = 8 }
local notes = {
    { kind = "mob", name = "Duplicate note", mapX = .41, mapY = .3,
        worldX = 120, worldY = 0, instanceID = 8 },
    { kind = "mob", name = "Other rare", mapX = .8, mapY = .3,
        worldX = 240, worldY = 0, instanceID = 8 },
    { kind = "treasure", name = "Not a rare", mapX = .9, mapY = .3,
        worldX = 250, worldY = 0, instanceID = 8 },
}
local result = beacons.BuildCandidates(1, player, { rare, boss, stale }, { quest }, notes,
    function() return true end, settings)
assert(#result == 4, "show live rare, boss, quest point, and nonduplicate data rare")
assert(result[1].name == "World boss" and result[1].r == 1,
    "bosses take priority and keep their theme color")
assert(result[2].name == "Live rare" and result[3].name == "Other rare",
    "a live rare should suppress the nearby data-pack copy")
assert(result[4].kind == "quest" and result[4].r == .3,
    "quest diamonds should use their radar quest color")
settings.vignetteRadarMapNotesVisible = false
local liveOnly = beacons.BuildCandidates(1, player, { rare, boss }, { quest }, notes,
    function() return true end, settings)
assert(#liveOnly == 3 and liveOnly[1].name == "World boss",
    "hiding map-pack notes should leave live and quest bearings alone")
settings.vignetteRadarMapNotesVisible = true
local favorite = { key = "favorite", name = "Favorite rare", category = "rare",
    favorite = true, mapX = .1, mapY = .1, worldX = 400, worldY = 0, instanceID = 8 }
assert(beacons.BuildCandidates(1, player, { boss, favorite }, {}, {}, nil, settings)[1].favorite,
    "a favorite should stay visible ahead of ordinary and boss bearings when space is limited")

settings.vignetteRadarBeaconTreasures = true
addon.VignetteRadarWorldFocus = { GetFocusedStep = function()
    return { mapID = 1, worldX = 155, worldY = 20 }
end }
local treasure = { key = "chest-1", name = "Live chest", category = "treasure",
    mapX = .3, mapY = .5, worldX = 155, worldY = 20, instanceID = 8 }
local withTreasure = beacons.BuildCandidates(1, player, { rare, treasure }, { quest }, notes,
    function() return true end, settings)
assert(#withTreasure == 5 and withTreasure[3].kind == "treasure"
    and withTreasure[3].r == 1 and withTreasure[3].name == "Live chest",
    "bearing markers should show live treasures with their theme color")
assert(withTreasure[3].focused,
    "the current focused waypoint should be recognizable in the bearing display")
local overlapping = { kind = "treasure", name = "Copy of live chest", mapID = 1,
    mapX = .31, mapY = .5, worldX = 160, worldY = 20, instanceID = 8 }
assert(#beacons.BuildCandidates(1, player, { treasure }, {}, { overlapping }, nil, settings) == 1,
    "a live treasure should suppress the nearby data-pack copy")
overlapping.mapID = 2
assert(#beacons.BuildCandidates(1, player, { treasure }, {}, { overlapping }, nil, settings) == 2,
    "data-pack copies on a different map must not be suppressed")
local cave = { kind = "entrance", name = "Cave Entrance", mapID = 1,
    mapX = .25, mapY = .35, worldX = 220, worldY = 40, instanceID = 8 }
local cavePoints = beacons.BuildCandidates(1, player, {}, {}, { cave }, nil, settings)
assert(#cavePoints == 1 and cavePoints[1].kind == "entrance",
    "the loot bearing filter should also guide players to pack cave entrances")
settings.vignetteRadarBeaconTreasures = false

settings.vignetteRadarBeaconMax = 4
local moreQuests = { quest }
for index = 1, 4 do
    moreQuests[#moreQuests + 1] = { questID = 17 + index, name = "Other objective",
        mapX = .5, mapY = .4, worldX = 90 + index, worldY = 25, instanceID = 8 }
end
assert(#beacons.BuildCandidates(1, player, { rare, boss }, moreQuests, notes, nil, settings) == 4,
    "the visible candidate limit must be enforced before creating buttons")
settings.vignetteRadarBeaconMax = 8
settings.vignetteRadarBeaconQuests = false
assert(#beacons.BuildCandidates(1, player, { rare }, { quest }, {}, nil, settings) == 1,
    "quest points can be turned off independently")
settings.vignetteRadarBeaconQuests = true
settings.vignetteRadarBeaconRange = 150
local farRare = { key = "far", category = "rare", mapX = .2, mapY = .4,
    worldX = 200, worldY = 0, instanceID = 8 }
assert(#beacons.BuildCandidates(1, player, { farRare }, { quest }, {}, nil, settings) == 1,
    "the range filter must exclude distant rares")
assert(#beacons.BuildCandidates(1, player, { rare }, {}, {}, function() return false end, settings) == 0,
    "ignored or filtered live rares must stay hidden")

-- Cards: long names wrap (two lines, else a wider card), never "...", and
-- no two cards overlap, whatever the bearings.
do
    local mock = dofile("tests/ui_mock.lua").Install()
    local real = {}
    assert(loadfile("UI/Style.lua"))("VignetteRadar", real)
    local style = addon.VignetteRadarStyle
    style.SetFont = function(fontString, size) fontString.vrFontSize = math.max(9, size); return true end
    style.TextWidth = function(fontString) return fontString:GetUnboundedStringWidth() end
    style.TextHeight, style.LineWidths = real.VignetteRadarStyle.TextHeight, real.VignetteRadarStyle.LineWidths
    _G.GetPlayerFacing = function() return 0 end
    settings.vignetteRadarBeaconsEnabled, settings.vignetteRadarBeaconTreasures = true, true
    settings.vignetteRadarBeaconMax, settings.vignetteRadarBeaconRange = 24, 1200
    addon.VignetteRadarWorldFocus = nil
    local here = { worldX = 0, worldY = 0, instanceID = 8 }
    local names = { "Gorgonzormu the Unbelievably Ancient Stone Watcher of the Deep Hollow",
        "Short", "Another Long Named Rare Elite Beast", "Ironjaw Matriarch", "Glimmering Hoard of the Tidesage",
        "Skittering Mother Of Many Legs", "Lost Supply Cache", "Cave" }
    local live = {}
    for index, name in ipairs(names) do
        live[index] = { key = "card" .. index, name = name, category = index % 2 == 0 and "treasure" or "rare",
            mapX = .5, mapY = .5, worldX = 100, worldY = (index - 4.5) * 30, instanceID = 8 }
    end
    addon.VignetteRadarPoints.Publish({ mapID = 1, player = here, targets = live })
    beacons.Sync(1, here, live, {}, {}, nil)
    local rail = assert(_G.VignetteRadarBeaconRail)
    local shown = {}
    for _, object in ipairs(mock.created) do
        if object.parent == rail and object.kind == "Button" and object.shown then shown[#shown + 1] = object end
    end
    assert(#shown >= 4, "close bearings stack into rows: " .. #shown)
    local function Box(card)
        local x, y = card.point[4], card.point[5]
        return x - card.width / 2, x + card.width / 2, -y, -y + card.height
    end
    for i = 1, #shown do
        local card = shown[i]
        local label = card.label
        assert(label.wordWrap == true, "card names wrap instead of being cut")
        assert(label.width >= 83, "a card name keeps at least the base width")
        local left, right, top, bottom = Box(card)
        assert(bottom <= rail.height - 4, "the bar grows so every card stays inside it")
        for j = i + 1, #shown do
            local l2, r2, t2, b2 = Box(shown[j])
            assert(right + 3 <= l2 or r2 + 3 <= left or bottom <= t2 or b2 <= top,
                "cards must never overlap: " .. tostring(card.label.text) .. " / " .. tostring(shown[j].label.text))
        end
    end
    local wide
    for _, card in ipairs(shown) do
        if card.label.text == "Another Long Named Rare Elite Beast" then wide = card end
    end
    assert(wide and wide.label.width > 83 and wide.height > 25,
        "a name too long for two base lines gets a wider, taller card")
    -- Turning moves every card by the same amount: rows keep their spacing.
    local before = shown[1].point[4]
    _G.GetPlayerFacing = function() return .1 end
    beacons.Place()
    assert(shown[1].point[4] ~= before, "cards slide with the camera every frame")
end

print("beacon candidate tests passed")
