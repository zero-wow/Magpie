-- Guide Panel: one host frame, blocks in the player's order, on/off per
-- block, wrapping instead of "...", stop clicks, actions, compact strip,
-- dock / detach / lock through Tray, and the ticker only while shown.
local mock = dofile("tests/ui_mock.lua").Install()
local now = 100
GetTime = function() return now end
GetPlayerFacing = function() return 0 end
local settings = { vignetteRadarEnabled = true, vignetteRadarGuidePanel = true, vignetteRadarGuideStops = 3,
    vignetteRadarGuideBlocks = {}, vignetteRadarGuideWidth = 260, vignetteRadarGuideDensity = "expanded",
    vignetteRadarShareButton = true, vignetteRadarRouteNextStep = true, vignetteRadarJournal = {} }
local invalidated = 0
local addon = { GetSettings = function() return settings end,
    InvalidateSettings = function() invalidated = invalidated + 1 end }
local SIZES = { caption = 10, body = 11, label = 11, title = 12, heading = 14 }
addon.VignetteRadarStyle = {
    SetFont = function(fontString, size) fontString.vrFontSize = SIZES[size] or size; return true end,
    Color = function() return .2, .4, .6 end,
    TextWidth = function(fontString) return fontString:GetUnboundedStringWidth() end,
    revision = 1,
}
do
    -- The real wrap measures (UI/Style.lua), shared with the Bearing Bar cards.
    local real = {}
    assert(loadfile("UI/Style.lua"))("VignetteRadar", real)
    addon.VignetteRadarStyle.TextHeight = real.VignetteRadarStyle.TextHeight
    addon.VignetteRadarStyle.LineWidths = real.VignetteRadarStyle.LineWidths
end
addon.VignetteRadarIconButton = { Create = function(parent, icon, options)
    local button = CreateFrame("Button", nil, parent)
    button.icon, button.labelText = icon, options.label
    button:SetSize(options.size, options.size)
    button:SetScript("OnClick", options.onClick)
    function button:Refresh() end
    return button
end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Compass.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Guidance.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Tray.lua"))("VignetteRadar", addon)
assert(loadfile("UI/GuidePanel.lua"))("VignetteRadar", addon)
local Guidance, Panel, Tray = addon.VignetteRadarGuidance, addon.VignetteRadarGuidePanel, addon.VignetteRadarTray
local Points = addon.VignetteRadarPoints

-- The radar face the panel docks under.
local face = mock.New("Texture")
face.width = 220
local host = mock.New("Frame")
host.background = face
local radar = mock.New("Frame")
radar.field = host
local player = { worldX = 0, worldY = 0, instanceID = 1, facing = 0 }
addon.VignetteRadarAPI = { GetPanel = function() return radar end, GetPlayerSnapshot = function() return player end }
addon.VignetteRadarTravel = { EtaText = function(yards) return "~" .. math.floor(yards / 10) .. " s" end }

-- World Focus as the panel's feed reads it.
local calls = {}
local function Note(name, x, kind)
    return { key = name, kind = kind or "treasure", name = name, worldX = x, worldY = 0, instanceID = 1, mapID = 7 }
end
local active, routeOn = nil, false
local horizon = {}
addon.VignetteRadarWorldFocus = {
    GetActiveTarget = function() if active then return active, active, 1, 1 end end,
    IsRouteActive = function() return routeOn end,
    IsRoutePaused = function() return false end,
    IsRouteLocked = function() return calls.locked == true end,
    GetRouteChoice = function() return routeOn and "treasure" or nil end,
    GetRoutePoint = function() return routeOn and active or nil end,
    GetHorizon = function() return horizon end,
    JumpRouteStop = function(item) calls.jump = item; return true end,
    SkipRouteStop = function() calls.skip = (calls.skip or 0) + 1; return true end,
    ToggleRouteLock = function() calls.locked = not calls.locked; return true end,
    ExplainActive = function() return "Live vignette · advances when cleared" end,
    Status = function() return "Auto Route" end,
    StartNearest = function(kind) calls.started = kind; return true end,
}
local notes = {}
addon.ShowVignetteRadarRouteNote = function(label, message) notes[#notes + 1] = { label, message } end
addon.VignetteRadarShareToGroup = { Channel = function() return "Party" end }
Points.Publish({ mapID = 7, player = player, targets = {}, notes = {} })

-- Nothing focused, nothing here: no panel is built.
Panel.Refresh()
assert(Panel.GetFrame() == nil, "nothing to show builds nothing")

-- A route: docked under the radar face, blocks top to bottom.
local cache = Note("Forgotten Amani Cache", 120)
cache.note = "Behind the waterfall"
active, routeOn = cache, true
horizon = { { current = true, item = cache }, { item = Note("Second Cache", 300), label = "Second Cache" },
    { item = Note("Silvermaw", 900, "rare"), label = "Silvermaw", kind = "rare" } }
addon.VignetteRadarDeclutter = { Done = function() return false end }
cache.rewardQuestID = 5
Guidance.Invalidate()
Panel.Refresh()
local frame = assert(Panel.GetFrame(), "a route builds the panel")
local blocks = frame.blocks
assert(frame:IsShown() and frame.point[2] == face and frame.point[3] == "BOTTOM" and frame.width == 260,
    "the panel docks under the radar face at its own width")
assert(blocks.header.name.text == "Forgotten Amani Cache"
    and blocks.header.meta.text == "Treasure · 120\194\160yd · ~12\194\160s",
    "the header names the stop with kind, yards and ETA: " .. tostring(blocks.header.meta.text))
assert(blocks.step.text.text == "Behind the waterfall" and blocks.facts.values[1].text == "Not Done",
    "the step and the facts render")
assert(blocks.stops.rows[1].name.text == "Second Cache · 300\194\160yd" and blocks.stops.rows[1].label.text == "Next"
    and blocks.stops.rows[2].label.text == "Then" and not blocks.stops.rows[3]:IsShown(),
    "the next stops list the stops after the header's")
local function Top(block) return -block.point[5] end
assert(Top(blocks.header) < Top(blocks.step) and Top(blocks.step) < Top(blocks.facts)
    and Top(blocks.facts) < Top(blocks.stops) and Top(blocks.stops) < Top(blocks.actions),
    "blocks stack in the default order")
assert(frame.height == Top(blocks.actions) + blocks.actions.height + 8, "the panel is as tall as its blocks")
assert(Guidance.IsWatching(), "a shown panel runs the yards ticker")

-- Clicks: a stop jumps the route; actions lock, skip and explain.
mock.Click(blocks.stops.rows[2])
assert(calls.jump == horizon[3].item, "clicking a stop jumps the route to it")
mock.Click(blocks.actions.icons.lock)
mock.Click(blocks.actions.icons.skip)
mock.Click(blocks.actions.icons.why)
assert(calls.locked == true and calls.skip == 1 and notes[#notes][1] == "WHY THIS STOP",
    "the action icons lock, skip and explain")
assert(blocks.actions.icons.share:IsShown() and blocks.actions.icons.lock:IsShown(), "route actions show")
blocks.header.scripts.OnClick(blocks.header, "MiddleButton")
assert(calls.skip == 2, "middle-clicking the header skips the stop")
local opened
addon.VignetteRadarQuickConfig = { OpenPage = function(name) opened = name end }
blocks.header.scripts.OnClick(blocks.header, "RightButton")
assert(opened == "Guide Panel", "right-clicking the header opens the panel's settings")

-- Blocks on and off, and their order.
settings.vignetteRadarGuideBlocks.facts = false
Panel.Refresh()
assert(not blocks.facts:IsShown() and blocks.stops:IsShown(), "a block switched off is gone")
settings.vignetteRadarGuideBlocks.facts = true
settings.vignetteRadarGuideOrder = { "stops", "step", "facts", "briefing", "actions", "notice" }
Panel.Refresh()
assert(Top(blocks.stops) < Top(blocks.step), "the saved order moves stops above the step")
assert(Panel.Order(settings)[1] == "header" and Panel.Order({ vignetteRadarGuideOrder = { "bogus", "notice" } })[2]
    == "notice", "the header stays first; unknown ids are dropped")
assert(Panel.MoveBlock("step") and settings.vignetteRadarGuideOrder[1] == "step" and invalidated > 0,
    "moving a block up writes the new order")
assert(Panel.MoveBlock("step") and settings.vignetteRadarGuideOrder[7] == "step", "the top block wraps to the end")
assert(Panel.OrderText(settings):find("^Order: Stops · Facts"), "the order reads back by name")
settings.vignetteRadarGuideOrder = nil

-- Compass strip: off by default; on, it draws the shared Compass feed's
-- ticks (Core/Compass.lua), which move with the camera every frame.
do
    Panel.Refresh()
    assert(not blocks.compass:IsShown(), "the compass strip starts off")
    settings.vignetteRadarGuideBlocks.compass = true
    addon.VignetteRadarCompass.Invalidate()
    Panel.Refresh()
    assert(blocks.compass:IsShown() and Top(blocks.compass) > Top(blocks.stops),
        "switched on, the strip sits after the stops")
    local tick = blocks.compass.ticks[1]
    assert(tick and tick:IsShown() and tick._item == cache and tick.label.text == "1",
        "the current stop is tick 1")
    local x, facing = tick.point[4], .3
    GetPlayerFacing = function() return facing end
    blocks.compass.scripts.OnUpdate(blocks.compass, .016)
    assert(tick.point[4] > x, "turning left moves the ticks right, on the next frame")
    facing = 0
    blocks.compass.scripts.OnUpdate(blocks.compass, .016)
    settings.vignetteRadarGuideBlocks.compass = nil
    Panel.Refresh()
    assert(not blocks.compass:IsShown(), "off again")
end

-- A theme change repaints at once, not on the next event.
do
    local style, accent = addon.VignetteRadarStyle, { .2, .4, .6 }
    local oldColor = style.Color
    style.Color = function() return accent[1], accent[2], accent[3] end
    Panel.RefreshTheme()
    accent = { .9, .1, .1 }
    style.revision = 2
    assert(Panel.RefreshTheme(), "a new theme repaints")
    assert(blocks.header.name.textColor[1] == .9, "the name takes the new accent at once")
    assert(not Panel.RefreshTheme(), "an unchanged theme does no work")
    style.Color = oldColor
end

-- Wrapping: a long name grows the header; nothing is ever cut.
do
    local shortHeight = blocks.header.height
    cache.name = "Akil'zon's Hoard of the Storm Crow Above the Amani Pass"
    Guidance.Invalidate()
    Panel.Refresh()
    assert(blocks.header.height > shortHeight and blocks.header.name.wordWrap == true
        and blocks.header.name.width == 260 - 41 - 8,
        "a long name wraps to more lines and the header grows")
    for _, object in ipairs(mock.created) do
        if object.kind == "CreateFontString" and object.text and object ~= blocks.stops.ruler then
            assert(not tostring(object.text):find("...", 1, true), "no text is ever cut short")
            assert(object.wordWrap ~= false or object.text == "", "panel text wraps: " .. tostring(object.text))
        end
    end
    cache.name = "Forgotten Amani Cache"
end

-- Compact: header, a strip of stops side by side, actions.
settings.vignetteRadarGuideDensity = "compact"
Guidance.Invalidate()
Panel.Refresh()
local first, second = blocks.stops.rows[1], blocks.stops.rows[2]
assert(not blocks.step:IsShown() and not blocks.facts:IsShown() and blocks.stops:IsShown(),
    "compact keeps the header, stops and actions")
assert(first.name.text == "Second Cache" and first.yards.text == "300 yd" and second:IsShown()
    and second.point[4] >= first.point[4] + first.width and second.point[4] + second.width <= 260 - 8,
    "compact stops sit side by side inside the panel")
blocks.header.scripts.OnClick(blocks.header, "LeftButton")
assert(settings.vignetteRadarGuideDensity == "expanded", "clicking the header switches back to Full")

-- Fit (was the Next 3 Stops Strip's): names wrap, then fewer cells.
do
    local widths, wrap, inner = Panel.Fit({ { one = 40, two = 40, yards = 30 },
        { one = 40, two = 40, yards = 30 } }, 200, 300)
    assert(#widths == 2 and not wrap and inner == 200 and widths[1] == widths[2], "short names share the width")
    widths, wrap = Panel.Fit({ { one = 120, two = 60, yards = 40 }, { one = 120, two = 60, yards = 40 } }, 180, 300)
    assert(#widths == 2 and wrap, "long names wrap to two lines first")
    widths = Panel.Fit({ { one = 150, two = 150, yards = 40 }, { one = 150, two = 150, yards = 40 } }, 180, 180)
    assert(#widths == 1, "then fewer cells show")
end

-- Notices land in the panel while it shows.
assert(Panel.ShowsNotices() and Guidance.Notice("AUTO ROUTE", "Jumped · Silvermaw"), "the panel takes notes")
Panel.Refresh()
assert(blocks.notice:IsShown() and blocks.notice.text.text == "Jumped · Silvermaw", "a note shows in the panel")

-- Dock, detach and lock through Tray.
Tray.SetPanelDetached(frame, true)
assert(Tray.IsPanelDetached(frame) and frame._vrFree and settings.vignetteRadarPanelLayout.guide.detached == true,
    "detaching frees the panel under its own layout key")
Tray.SetPanelLocked("guide", true)
assert(Tray.IsPanelLocked(frame), "the panel locks")
frame.scripts.OnDragStart(frame)
assert(not frame._vrMoving, "a locked panel does not drag")
Tray.SetPanelLocked("guide", false)
Tray.SetPanelDetached(frame, false)
assert(not frame._vrFree and frame.point[2] == face, "docking puts it back under the radar")

-- The radar closed: a focus floats; the idle zone line does not.
radar.shown = false
Panel.Refresh()
assert(frame:IsShown() and frame._vrFree, "with the radar closed a route floats on its own")
active, routeOn, horizon = nil, false, {}
Points.Publish({ mapID = 7, player = player, targets = {}, notes = { { kind = "treasure" } } })
Guidance.Invalidate()
Panel.Refresh()
assert(not frame:IsShown() and not Guidance.IsWatching(),
    "the idle zone line never floats alone, and a hidden panel stops the ticker")
radar.shown = true
Panel.Refresh()
assert(frame:IsShown() and blocks.briefing:IsShown() and not blocks.header:IsShown(),
    "with the radar open the idle panel is the zone line")
mock.Click(blocks.briefing)
assert(calls.started == "closest", "clicking the zone line starts a Closest Auto Route")

-- Off: hidden, and the ticker stops.
settings.vignetteRadarGuidePanel = false
Panel.Refresh()
assert(not frame:IsShown() and not Guidance.IsWatching(), "switching the panel off hides it and its ticker")

print("guide panel tests passed")
