-- luacheck: globals VignetteRadarDB WaffleHouseDB STANDARD_TEXT_FONT WorldMapFrame
-- Spawn History Heatmap: cells from learned rare spawns and treasure loots,
-- off by default, faint dots under the radar markers that redraw only when
-- something changed, and an optional world map layer.
STANDARD_TEXT_FONT = "default.ttf"
VignetteRadarDB, WaffleHouseDB = nil, nil
local clock = 100
_G.GetTime = function() return clock end
local mock = dofile("tests/ui_mock.lua").Install()
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/SpatialProjection.lua"))("VignetteRadar", addon)
assert(loadfile("UI/TurnSmoothing.lua"))("VignetteRadar", addon)
assert(loadfile("Data/RareSpawns.lua"))("VignetteRadar", addon)
assert(loadfile("UI/SpawnHeatmap.lua"))("VignetteRadar", addon)
local Heat = assert(addon.VignetteRadarSpawnHeatmap)
local settings = addon.GetSettings()
assert(settings.vignetteRadarSpawnHeatmap == false and settings.vignetteRadarSpawnHeatmapWorldMap == true,
    "radar layer off by default")

settings.vignetteRadarRareSpawns = {
    [1] = { name = "A", map = 2371, spawns = {
        { x = 100, y = 0, m = 2371, mx = .5, my = .4, n = 3 },
        { x = 5000, y = 5000, m = 2371, mx = .9, my = .9, n = 1 },
    } },
    [2] = { name = "B", map = 99, spawns = { { x = 0, y = 0, m = 99, mx = .1, my = .1, n = 1 } } },
}
settings.vignetteRadarTreasureLoots = {
    chest = { mapID = 2371, mapX = .2, mapY = .3, samples = { { worldX = -50, worldY = 20 }, { worldX = -52, worldY = 21 } } },
}
local cells = Heat.Cells(2371)
assert(#cells == 3, "two rare spawns and one treasure on this map")
assert(Heat.Cells(2371) == cells, "cached per map")

local field = CreateFrame("Frame")
local panel = { field = field, plotRadius = 100 }
local player = { worldX = 0, worldY = 0, facing = 0, mapID = 2371 }

-- Off: nothing drawn.
Heat.Render(panel, player, 450)
assert(panel.heatDots == nil, "nothing while off")

settings.vignetteRadarSpawnHeatmap = true
Heat.Render(panel, player, 450)
local shown = 0
for _, dot in ipairs(panel.heatDots) do if dot.shown then shown = shown + 1 end end
assert(shown == 2, "the far spawn is outside the range: " .. shown)
local dot = panel.heatDots[1]
assert(dot.vertex[4] > 0 and dot.vertex[4] <= .30, "faint")
assert(panel.heatLayer.level == (field:GetFrameLevel() + 1), "under the markers")

-- Unchanged view: no redraw (the dot keeps its old point table).
local point = dot.point
Heat.Render(panel, player, 450)
assert(dot.point == point, "skipped when nothing changed")
-- A small step stays, a long one redraws.
player.worldX = 1
Heat.Render(panel, player, 450)
assert(dot.point == point, "sub-pixel move is skipped")
player.worldX = 40
Heat.Render(panel, player, 450)
assert(dot.point ~= point, "moved: redrawn")

-- Lens / no player: hidden.
Heat.Render(panel, nil, 450)
assert(not panel.heatDots[1].shown, "hidden without a player")

-- World map layer.
local child = CreateFrame("Frame")
child.GetSize = function() return 1000, 600 end
local map = CreateFrame("Frame")
map.ScrollContainer = { Child = child }
map.GetMapID = function() return 2371 end
WorldMapFrame = map
_G.hooksecurefunc = function() end
assert(Heat.DrawMap() == 3, "all three cells on the zone map")
settings.vignetteRadarSpawnHeatmapWorldMap = false
assert(Heat.DrawMap() == 0, "world map layer off")
settings.vignetteRadarSpawnHeatmap = false
settings.vignetteRadarSpawnHeatmapWorldMap = true
assert(Heat.DrawMap() == 0, "main switch off hides the map layer too")
assert(mock.frames, "mock in use")
print("spawn_heatmap_test ok")
