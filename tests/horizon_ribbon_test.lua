-- Horizon Ribbon: bearing math, which ticks show (next 3 stops, focus, live
-- rares, no duplicates), placement as you turn, and on/off.
local mock = dofile("tests/ui_mock.lua").Install()
local settings = { vignetteRadarHorizonRibbon = true, vignetteRadarHorizonRibbonRares = true,
    vignetteRadarHorizonRibbonWidth = 440, vignetteRadarHorizonRibbonOffset = 40 }
local addon = { GetSettings = function() return settings end }
local facing = 0
_G.GetPlayerFacing = function() return facing end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Compass.lua"))("VignetteRadar", addon)
addon.VignetteRadarStyle = { revision = 1, SetFont = function() return true end, Color = function() return .2, .4, .6 end }
assert(loadfile("UI/HorizonRibbon.lua"))("VignetteRadar", addon)
local Ribbon = assert(addon.VignetteRadarHorizonRibbon)
local PI = math.pi

-- Bearing: same convention as the Bearing Bar (facing 0, +x is angle 0).
local player = { worldX = 0, worldY = 0, instanceID = 1 }
local function Near(a, b) return math.abs(a - b) < 1e-9 end
assert(Near(Ribbon.Bearing(player, { worldX = 10, worldY = 0 }, 0), 0), "straight ahead")
assert(Near(Ribbon.Bearing(player, { worldX = 0, worldY = 10 }, 0), PI / 2), "positive is to the left")
assert(Near(Ribbon.Bearing(player, { worldX = 0, worldY = 10 }, PI / 2), 0), "turning brings it ahead")
assert(Ribbon.Bearing(player, { worldX = 1, worldY = 1, instanceID = 2 }, 0) == nil, "other instance")
assert(Ribbon.Bearing(player, { worldX = 1 }, 0) == nil, "no position")
local x, clamped = Ribbon.X(PI / 4, 200)
assert(Near(x, -100) and not clamped, "left half of the field is left of centre")
x, clamped = Ribbon.X(-PI, 200)
assert(Near(x, 200) and clamped, "behind you clamps to the edge")

-- Items: route stops numbered, the focus once, live rares, no duplicates.
local stopA = { key = "a", kind = "treasure", name = "A", worldX = 10, worldY = 0, instanceID = 1 }
local stopB = { key = "b", kind = "rare", name = "B", worldX = 0, worldY = 10, instanceID = 1 }
local rare = { key = "r", category = "rare", name = "R", worldX = -5, worldY = -5, instanceID = 1 }
local stale = { key = "s", category = "rare", name = "S", stale = true, worldX = 1, worldY = 1 }
local routeActive = true
addon.VignetteRadarWorldFocus = {
    IsRouteActive = function() return routeActive end,
    GetHorizon = function() return { { item = stopA, kind = "treasure", current = true }, { item = stopB, kind = "rare" } } end,
    GetActiveTarget = function() return stopA end,
}
addon.VignetteRadarPoints.Publish({ player = player, targets = { rare, stale, stopB } })
local list = Ribbon.Items()
assert(#list == 3, "stops A, B and live rare R; the focus and B are not repeated")
assert(list[1].item == stopA and list[1].label == "1" and list[1].focus, "first stop is the focus, numbered 1")
assert(list[2].item == stopB and list[2].label == "2")
assert(list[3].item == rare and list[3].label == nil and list[3].kind == "rare")
settings.vignetteRadarHorizonRibbonRares = false
assert(#Ribbon.Items() == 2, "rares can be left off")
settings.vignetteRadarHorizonRibbonRares = true

-- Refresh shows the ribbon at the top; ticks move as you turn.
Ribbon.Refresh()
local frame = assert(Ribbon.GetFrame())
assert(frame.shown and frame.width == 440 and frame.point[1] == "TOP" and frame.point[5] == -40)
local function TickFor(item)
    for _, tick in ipairs(frame.ticks) do if tick.shown and tick._item == item then return tick end end
end
assert(Near(TickFor(stopA).point[4], 0), "ahead sits in the centre")
assert(TickFor(stopB).point[4] < 0, "left of you sits left")
facing = PI / 2
Ribbon.Layout()
assert(Near(TickFor(stopB).point[4], 0) and TickFor(stopA).point[4] > 0, "turning left moves ticks right")
local before = TickFor(stopB).point
Ribbon.Layout()
assert(TickFor(stopB).point == before, "no relayout while nothing moved")

-- Only the tick under the center line shows its distance, just below it.
assert(frame.aim.shown and frame.aim.text == "10 yd" and Near(frame.aim.point[4], 0),
    "the aimed-at stop shows its yards under the center")
facing = PI / 4
Ribbon.Layout()
assert(not frame.aim.shown, "nothing under the center: no distance")
facing = PI / 2
Ribbon.Layout()
assert(frame.aim.shown, "aiming again brings it back")

-- Nothing to show, or switched off: hidden.
routeActive = false
addon.VignetteRadarWorldFocus.GetActiveTarget = function() return nil end
addon.VignetteRadarPoints.Publish({ player = player, targets = {} })
Ribbon.Refresh()
assert(not frame.shown, "hidden with nothing to show")
settings.vignetteRadarHorizonRibbon = false
routeActive = true
Ribbon.Refresh()
assert(not frame.shown, "off hides it")
assert(mock)
print("horizon_ribbon_test ok")
