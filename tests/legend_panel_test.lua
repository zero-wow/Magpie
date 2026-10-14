-- The Legend on the shared panel system (UI/Tray.lua RegisterPanel): its old
-- saved spot moves into the panel layout, a detached legend opens there, the
-- position lock stops the drag, a drop saves the spot, and a spot off screen
-- re-docks it on load.
-- luacheck: no global
local mock = dofile("tests/ui_mock.lua")
mock.Install()
UIParent.width, UIParent.height = 1600, 900
STANDARD_TEXT_FONT = "default.ttf"

local function Load(settings)
    local addon = { GetSettings = function() return settings end, InvalidateSettings = function() end }
    assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
    assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
    assert(loadfile("UI/Tray.lua"))("VignetteRadar", addon)
    assert(loadfile("UI/Legend.lua"))("VignetteRadar", addon)
    return addon
end

-- Gives a mock frame a laid-out rect (UIParent units, top-left at x, y from
-- the screen's top-left).
local function Rect(frame, x, y)
    frame.GetLeft = function() return x end
    frame.GetRight = function() return x + frame:GetWidth() end
    frame.GetTop = function() return 900 + y end
    frame.GetBottom = function() return 900 + y - frame:GetHeight() end
end

local anchor = CreateFrame("Frame")

do
    local settings = { vignetteRadarLegendDetached = true, vignetteRadarLegendPosition = { x = 120.4, y = -90 } }
    local addon = Load(settings)
    local legend, tray = addon.VignetteRadarLegend, addon.VignetteRadarTray
    assert(legend.Toggle(anchor), "a detached legend opens")
    local panel = legend.Testing.GetPanel()
    assert(tray.IsPanel(panel), "the legend is a registered panel")
    local record = settings.vignetteRadarPanelLayout.legend
    assert(record.x == 120 and record.y == -90 and settings.vignetteRadarLegendPosition == nil,
        "its old spot moved into the panel layout")
    assert(panel.point[1] == "TOPLEFT" and panel.point[2] == UIParent and panel.point[4] == 120
        and panel.point[5] == -90, "it opens at its saved spot")
    assert(panel.moveLock and panel.moveLock:IsShown() and panel.moveLock.labelText == "Position Unlocked",
        "detached, it shows a position lock")
    mock.Click(panel.moveLock)
    assert(tray.IsPanelLocked("legend") and panel.moveLock.labelText == "Position Locked", "the lock locks")
    Rect(panel, 300, -200)
    local moving = false
    panel.StartMoving = function() moving = true end
    panel.StopMovingOrSizing = function() moving = false end
    panel.scripts.OnDragStart(panel)
    assert(not moving and not panel._vrMoving, "locked: no drag")
    mock.Click(panel.moveLock)
    assert(not tray.IsPanelLocked("legend"), "unlocked")
    panel.scripts.OnDragStart(panel)
    assert(moving and panel._vrMoving, "unlocked: it drags")
    Rect(panel, 340, -260)
    panel.scripts.OnDragStop(panel)
    record = settings.vignetteRadarPanelLayout.legend
    assert(not moving and record.x == 340 and record.y == -260, "the drop saves the spot")
    legend.SetDetached(false)
    assert(not panel.moveLock:IsShown(), "docked or beside the radar, no position lock")
    panel.scripts.OnDragStart(panel)
    assert(not panel._vrMoving, "not detached: no drag")
end

-- Safety net: a saved spot far off screen re-docks the legend on load.
do
    local settings = { vignetteRadarLegendDetached = true,
        vignetteRadarPanelLayout = { legend = { x = 4000, y = -100 } } }
    local addon = Load(settings)
    local legend = addon.VignetteRadarLegend
    legend.Toggle(anchor)
    local panel = legend.Testing.GetPanel()
    assert(settings.vignetteRadarLegendDetached == false and settings.vignetteRadarPanelLayout.legend.x == false,
        "an off-screen legend re-docks")
    assert(panel.point and panel.point[2] == anchor, "and opens beside the radar instead")
end

print("legend panel tests passed")
