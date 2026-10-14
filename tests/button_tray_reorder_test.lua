-- Button Tray scroll grid and press-and-hold reorder: fixed 3 columns that
-- scroll one row per notch, the config tool pinned in the header, a ghost
-- that follows the cursor, the gap preview, cancels, and the saved order.
local mock = dofile("tests/ui_mock.lua").Install()
local unpack = table.unpack or unpack

-- Frames that keep parent, points and scripts like the client.
local function Rich(frame)
    frame.points = {}
    frame.GetParent = function(self) return self.parent end
    frame.SetParent = function(self, parent) self.parent = parent end
    frame.ClearAllPoints = function(self) self.points = {} end
    frame.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    frame.GetNumPoints = function(self) return #self.points end
    frame.GetPoint = function(self, index) return unpack(self.points[index]) end
    frame.GetScale = function(self) return self.scale or 1 end
    frame.SetScale = function(self, value) self.scale = value end
    frame.IsMouseEnabled = function(self) return self.mouse == true end
    frame.EnableMouse = function(self, value) self.mouse = value end
    frame.EnableKeyboard = function(self, value) self.keyboard = value end
    frame.SetPropagateKeyboardInput = function(self, value) self.propagate = value end
    frame.HookScript = function(self, name, fn)
        self.hooks = self.hooks or {}
        local old = self.hooks[name]
        self.hooks[name] = old and function(...) old(...); fn(...) end or fn
    end
    frame.GetName = function(self) return self._name end
    frame.GetObjectType = function(self) return self.kind end
    frame.GetChildren = function() return end
    return frame
end
local baseCreate = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent)
    local frame = Rich(baseCreate(kind, name, parent))
    frame._name = name
    return frame
end
local function New(kind, parent) return Rich(mock.New(kind, parent)) end

_G.hooksecurefunc = function(target, name, hook)
    local original = target[name]
    target[name] = function(...) original(...); hook(...) end
end
_G.CreateColor = function(...) return { ... } end
-- Presses land inside the tray (no click-away).
_G.MouseIsOver = function() return true end
local lockdown = false
_G.InCombatLockdown = function() return lockdown end
_G.IsAltKeyDown = function() return false end
-- The cursor, mouse focus and button state each step sets.
local cursorX, cursorY, foci, mouseDown = 0, 0, {}, true
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.GetMouseFoci = function() return foci end
_G.IsMouseButtonDown = function() return mouseDown end
_G.SlashCmdList = { VIGNETTERADAR = function() end }
local chat = {}
local realPrint = print
_G.print = function(text) chat[#chat + 1] = tostring(text) end
local function Said(pattern)
    for _, line in ipairs(chat) do if line:find(pattern) then return true end end
    return false
end

local settings = { vignetteRadarAdvancedTools = false }
local addon = { GetSettings = function() return settings end }
local traces = {}
addon.Trace = { Log = function(topic, fmt, ...)
    local ok, text = pcall(string.format, fmt, ...)
    traces[#traces + 1] = topic .. ": " .. (ok and text or fmt)
end }
local function Traced(pattern)
    for _, line in ipairs(traces) do if line:find(pattern) then return true end end
    return false
end

-- The radar: 15 corner tools (config first) on a 180 px face.
local panel = New("Frame")
panel.level, panel.strata = 10, "MEDIUM"
panel.field = New("Frame", panel)
panel.field.background = New("Texture", panel.field)
panel.field.background.width, panel.field.background.height = 180, 180
panel.hoverTools = {}
local ids = { "config", "target", "legend", "minus", "plus", "north", "trail", "eye", "route", "tracker",
    "clear", "arrow", "minimize", "constellation", "close" }
for index, id in ipairs(ids) do
    local tool = CreateFrame("Button", nil, panel.field)
    tool:SetSize(16, 16)
    tool:SetPoint("TOPLEFT", panel.field, "TOPLEFT", 12 * index, -12)
    tool.toolID = id
    tool.shown = false
    panel.hoverTools[index] = tool
end
panel.RefreshCornerTools = function() end
addon.VignetteRadarAPI = { GetPanel = function() return panel end }

-- The minimap with 20 LibDBIcon buttons (B01..B20).
local map = New("Frame")
_G.Minimap = map
local lib = { objects = {} }
local function DBButton(name)
    local button = CreateFrame("Button", "LibDBIcon10_" .. name, map)
    button:SetSize(31, 31)
    button:SetPoint("CENTER", map, "CENTER", 80, 0)
    button.db = {}
    button.border = New("Texture", button)
    button.icon = New("Texture", button)
    button.icon.texture = "Interface\\Icons\\" .. name
    button.icon.GetTexture = function(self) return self.texture end
    button.icon.GetTexCoord = function() return 0, 1, 0, 1 end
    button.fadeOut = { Stop = function() end }
    return button
end
for index = 1, 20 do
    local name = ("B%02d"):format(index)
    lib.objects[name] = DBButton(name)
end
function lib:GetButtonList() local list = {}; for name in pairs(self.objects) do list[#list + 1] = name end; return list end
function lib:GetMinimapButton(name) return self.objects[name] end
function lib:Refresh() end
function lib.RegisterCallback(_, _, fn) lib.callback = fn end
_G.LibStub = setmetatable({}, { __call = function(_, name) return name == "LibDBIcon-1.0" and lib or nil end })

local function Load(path)
    local chunk = assert(loadfile(path))
    return chunk("VignetteRadar", addon)
end
Load("UI/IconButton.lua")
Load("UI/Tray.lua")
Load("UI/MinimapUnderlay.lua")
local Underlay = addon.VignetteRadarMinimapUnderlay
Underlay.EnsureTool(panel)
local Buttons = Load("UI/ButtonTray.lua")
local driver
for _, frame in ipairs(mock.frames) do
    if frame.scripts and frame.scripts.OnUpdate and frame.scripts.OnEvent and not frame.parent then driver = frame end
end
assert(driver, "tray driver frame")
local function Tick(seconds) driver.scripts.OnUpdate(driver, seconds or 1) end
local function Fire(event, ...) driver.scripts.OnEvent(driver, event, ...) end
local function B(index) return lib.objects[("B%02d"):format(index)] end

Underlay.NotifyTray(true, panel)
mock.Click(Buttons.GetHandle())
Tick(1)
assert(Buttons.IsOpen(), "tray out")
local viewport = Buttons.GetViewport()
viewport.GetLeft = function() return 100 end
viewport.GetTop = function() return 500 end
viewport.mouseOver = true

-- Screen position of the middle of grid position p (or a dx, dy from it).
local function At(position, dx, dy)
    local rows = Buttons.ScrollInfo()
    local x = (position % 3) * 25 + 11 + (dx or 0)
    local y = math.floor(position / 3) * 25 + 11 - rows * 25 + (dy or 0)
    return 100 + x, 500 - y
end
local function Point(frame)
    local cell = Buttons.CellOf(frame)
    local _, _, _, x, y = cell:GetPoint(1)
    return x, y
end
local function Names()
    return table.concat(Buttons.Gathered(Buttons.CurrentSet()), ",")
end
local function PressOn(frame, position)
    foci = { frame }
    cursorX, cursorY = At(position)
    mouseDown = true
    Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
end
local function MoveTo(x, y, seconds)
    cursorX, cursorY = x, y
    Tick(seconds or .01)
end
local function Up()
    mouseDown = false
    Fire("GLOBAL_MOUSE_UP", "LeftButton")
end

-- Fixed grid, scroll and the pinned config (radar set) -----------------------
do
    assert(Buttons.CurrentSet() == "radar", "radar set first")
    local rows, total, visible = Buttons.ScrollInfo()
    assert(rows == 0 and total == 5 and visible == 5, "14 tools + underlay toggle: 5 rows, all visible")
    local content = Buttons.GetContent()
    local width, height = content:GetWidth(), content:GetHeight()
    assert(width == 84 and height == 2 * 6 + 22 + 3 + 5 * 25 - 3, "content sized for 5 rows")
    local config = panel.hoverTools[1]
    assert(Buttons.CellOf(config):GetParent() == content and config:IsShown(), "config pinned in the header")
    -- Row-major: the second grid tool (legend) sits in column 1 of row 0.
    local x, y = Point(panel.hoverTools[3])
    assert(x == 25 and y == 0, "row-major fill")
    x, y = Point(panel.hoverTools[5])
    assert(x == 0 and y == -25, "fourth grid tool starts row 1")
    foci = { config }
    cursorX, cursorY = At(0)
    assert(not Buttons.Press(cursorX, cursorY), "the pinned config is never picked up")

    -- Minimap set: 20 buttons scroll inside the same 5 rows.
    Buttons.Flip()
    assert(Buttons.CurrentSet() == "minimap", "flipped")
    assert(content:GetWidth() == width and content:GetHeight() == height, "a flip never resizes the drawer")
    assert(Buttons.CellOf(config):GetParent() == content and Buttons.CellOf(config):IsShown(),
        "config stays in the header for the minimap set")
    rows, total, visible = Buttons.ScrollInfo()
    assert(rows == 0 and total == 7 and visible == 5, "20 buttons: 7 rows, 5 shown")
    local group = Buttons.CellOf(B(1)):GetParent()
    viewport.scripts.OnMouseWheel(viewport, -1)
    assert(Buttons.ScrollInfo() == 1 and select(5, group:GetPoint(1)) == 25, "one row per notch")
    viewport.scripts.OnMouseWheel(viewport, -1)
    viewport.scripts.OnMouseWheel(viewport, -1)
    assert(Buttons.ScrollInfo() == 2, "clamps at the last row")
    local thumbShown = false
    for _, object in ipairs(mock.created) do
        if object.kind == "CreateTexture" and object.parent == content and object.width == 3 then
            thumbShown = object.shown
        end
    end
    assert(thumbShown, "thumb shown while there is more to scroll")
    viewport.scripts.OnMouseWheel(viewport, 2)
    assert(Buttons.ScrollInfo() == 0, "wheel up scrolls back")
end

-- Click vs drag ----------------------------------------------------------------
local defaultOrder = Names()
do
    local x0, y0 = Point(B(1))
    PressOn(B(1), 0)
    assert(Buttons.DragState() == "pressed", "a press on a gathered button is watched")
    MoveTo(cursorX + 2, cursorY, .1)
    assert(Buttons.DragState() == "pressed", "2 px in .1 s is still a click")
    Up()
    assert(Buttons.DragState() == nil, "release ends the press")
    local x1, y1 = Point(B(1))
    assert(x0 == x1 and y0 == y1 and Names() == defaultOrder, "no layout change")
    assert(settings.vignetteRadarButtonTrayOrder == nil, "nothing saved")
end

-- Move threshold, then Esc cancels ------------------------------------------------
do
    local content = Buttons.GetContent()
    local width, height = content:GetWidth(), content:GetHeight()
    PressOn(B(1), 0)
    MoveTo(cursorX + 7, cursorY)
    assert(Buttons.DragState() == "dragging", "7 px lifts")
    local ghost = Buttons.GetGhost()
    assert(ghost and ghost:IsShown() and ghost.mouse == true and ghost.strata == "TOOLTIP", "ghost under the cursor")
    assert(ghost.keyboard == true, "keyboard on while dragging")
    assert(ghost.icon.texture == "Interface\\Icons\\B01", "ghost shows the button's icon")
    local cell = Buttons.CellOf(B(1))
    assert(math.abs(cell.plate.vertex[4] - .35) < 1e-6, "origin plate dimmed")
    assert(content:GetWidth() == width and content:GetHeight() == height, "no resize while dragging")
    ghost.scripts.OnKeyDown(ghost, "ESCAPE")
    assert(Buttons.DragState() == nil and not ghost:IsShown() and ghost.keyboard == false, "Esc cancels")
    assert(ghost.propagate == false, "Esc is not passed on")
    assert(math.abs(cell.plate.vertex[4] - .8) < 1e-6, "plate back to idle")
    assert(Names() == defaultOrder and settings.vignetteRadarButtonTrayOrder == nil, "order unchanged")
    assert(Traced("reorder B01 cancelled %(escape%)"), "cancel traced")
end

-- Hold threshold, release in place ------------------------------------------------
do
    PressOn(B(2), 1)
    Tick(.2)
    assert(Buttons.DragState() == "pressed", "not yet held long enough")
    Tick(.2)
    assert(Buttons.DragState() == "dragging", "a still hold lifts after .35 s")
    -- A small wiggle over the gap keeps the slot.
    MoveTo(cursorX + 3, cursorY)
    Up()
    assert(Buttons.DragState() == nil and Names() == defaultOrder, "dropped back in place")
    assert(settings.vignetteRadarButtonTrayOrder == nil, "nothing saved for a drop in place")
end

-- Reorder: B01 to after B04 -----------------------------------------------------------
do
    PressOn(B(1), 0)
    MoveTo(At(0, 8, 0))
    -- Right half of position 2: the gap opens at 3 (B02, B03, B04 shift left).
    MoveTo(At(2, 6, 0))
    local _, gapSlot = Buttons.DragState()
    assert(gapSlot == 3, "gap at slot 3")
    local x, y = Point(B(2))
    assert(x == 0 and y == 0, "B02 shifted into the first cell (live preview)")
    x, y = Point(B(1))
    assert(x == 0 and y == -25, "the lifted button waits in the gap")
    MoveTo(At(2, 7, 0))
    assert(select(2, Buttons.DragState()) == 3, "steady while over the gap")
    Up()
    local saved = settings.vignetteRadarButtonTrayOrder
    assert(saved and saved.minimap[1] == "LibDBIcon10_B02" and saved.minimap[4] == "LibDBIcon10_B01",
        "new order saved by stable names")
    assert(Names():find("^GameTimeFrame") == nil and Names():find("^LibDBIcon10_B02,LibDBIcon10_B03,LibDBIcon10_B04,"
        .. "LibDBIcon10_B01,LibDBIcon10_B05"), "tray order changed")
    x, y = Point(B(1))
    assert(x == 0 and y == -25, "cells re-anchored row-major")
    assert(Traced("reorder B01 to slot 4"), "reorder traced")
end

-- Cancels: right button, drop outside, combat ------------------------------------------
do
    local before = Names()
    PressOn(B(5), 4)
    MoveTo(At(4, 0, 10))
    Fire("GLOBAL_MOUSE_DOWN", "RightButton")
    assert(Buttons.DragState() == nil and Names() == before, "right-click cancels")
    mouseDown = false
    Fire("GLOBAL_MOUSE_UP", "LeftButton")

    PressOn(B(5), 4)
    MoveTo(At(4, 0, 10))
    MoveTo(100 + 200, 500 - 20)
    assert(select(2, Buttons.DragState()) == nil, "outside: no slot")
    Up()
    assert(Buttons.DragState() == nil and Names() == before and not Buttons.GetGhost():IsShown(),
        "drop outside cancels")

    PressOn(B(5), 4)
    MoveTo(At(4, 0, 10))
    Fire("PLAYER_REGEN_DISABLED")
    assert(Buttons.DragState() == nil and Names() == before, "combat cancels")
    assert(Traced("cancelled %(combat%)"), "combat cancel traced")
    mouseDown = false
    mock.Click(Buttons.GetHandle())
    Tick(1)
    assert(Buttons.IsOpen(), "tray out again")

    lockdown = true
    PressOn(B(5), 4)
    assert(Buttons.DragState() == nil, "no pickups in combat")
    lockdown = false
end

-- Auto-scroll at the bottom edge ------------------------------------------------------
do
    PressOn(B(5), 4)
    MoveTo(At(4, 0, 10))
    assert(Buttons.ScrollInfo() == 0, "not scrolled yet")
    -- Bottom band of the 5-row viewport (height 122): y 115 is in the inner half.
    cursorX, cursorY = 100 + 11, 500 - 115
    Tick(.05)
    Tick(.05)
    assert(Buttons.ScrollInfo() == 1, "scrolls one row after the fast period")
    cursorX, cursorY = 100 + 11, 500 - 60
    Tick(.5)
    assert(Buttons.ScrollInfo() == 1, "no scroll away from the edges")
    Up()
    viewport.scripts.OnMouseWheel(viewport, 5)
end

-- Rebuild mid-drag ----------------------------------------------------------------------
do
    PressOn(B(6), 5)
    MoveTo(At(5, 0, 10))
    lib.objects.Late = DBButton("Late")
    lib.callback("LibDBIcon_IconCreated", lib.objects.Late, "Late")
    assert(Buttons.Holds(lib.objects.Late) and Buttons.DragState() == "dragging", "a joining button keeps the drag")
    Buttons.Ignore("LibDBIcon10_B06")
    assert(Buttons.DragState() == nil and not Buttons.Holds(B(6)), "the dragged button leaving cancels")
    mouseDown = false
    Fire("GLOBAL_MOUSE_UP", "LeftButton")
    Buttons.Unignore("LibDBIcon10_B06")
end

-- Saved order: unknown names ranked after, missing ones kept --------------------------------
do
    settings.vignetteRadarButtonTrayOrder = { radar = {}, minimap = { "LibDBIcon10_B07", "LibDBIcon10_Gone" } }
    Buttons.ApplyOrder()
    assert(Names():find("^LibDBIcon10_B07,GameTimeFrame") or Names():find("^LibDBIcon10_B07,LibDBIcon10_B01"),
        "saved name first, the rest in default order")
    PressOn(B(7), 0)
    MoveTo(At(0, 8, 0))
    MoveTo(At(1, 6, 0))
    Up()
    local saved = settings.vignetteRadarButtonTrayOrder.minimap
    assert(saved[1] ~= "LibDBIcon10_B07" and saved[#saved] == "LibDBIcon10_Gone", "absent name kept at the tail")
    chat = {}
    SlashCmdList.VIGNETTERADAR("buttons order")
    assert(Said("Saved minimap order %(%d+%): LibDBIcon10_"), "/vr buttons order lists the saved order")
    SlashCmdList.VIGNETTERADAR("buttons order reset minimap")
    assert(#settings.vignetteRadarButtonTrayOrder.minimap == 0 and Said("Button order reset for minimap"),
        "/vr buttons order reset minimap")
    assert(Names():find("^LibDBIcon10_B01,LibDBIcon10_B02"), "default order back")
    SlashCmdList.VIGNETTERADAR("buttons order reset bogus")
    assert(Said("Usage: /magpie buttons order reset"), "bad set name: usage")
end

-- Radar tools reorder too (config stays pinned) -------------------------------------------
do
    Buttons.Flip()
    assert(Buttons.CurrentSet() == "radar", "radar set")
    for _, object in ipairs(mock.created) do
        if object.kind == "CreateTexture" and object.parent == Buttons.GetContent() and object.width == 3 then
            assert(not object.shown, "thumb hidden when every row fits")
        end
    end
    local first = panel.hoverTools[2]
    PressOn(first, 0)
    MoveTo(At(0, 8, 0))
    MoveTo(At(1, 6, 0))
    Up()
    local saved = settings.vignetteRadarButtonTrayOrder.radar
    assert(saved[1] == "legend" and saved[2] == "minus" and saved[3] == "target", "radar order saved by tool ID")
    for _, name in ipairs(saved) do assert(name ~= "config", "the pinned tool is never saved") end
end

-- Underlay off with a drag going: cancelled, everything back -----------------------------
do
    PressOn(panel.hoverTools[3], 0)
    MoveTo(At(0, 8, 0))
    Underlay.NotifyTray(false, panel)
    assert(Buttons.DragState() == nil and not Buttons.GetGhost():IsShown(), "put away cancels")
    assert(panel.hoverTools[3]:GetParent() == panel.field, "tools back on the face")
end

_G.print = realPrint
print("button_tray_reorder_test passed")
