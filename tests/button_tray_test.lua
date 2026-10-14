-- Button Tray: while the Minimap Underlay is on, the radar's corner tools and
-- the minimap's buttons (LibDBIcon + Blizzard extras) move into a drawer
-- behind a lip on the radar's side, one set at a time, and go back exactly.
local mock = dofile("tests/ui_mock.lua").Install()
local unpack = table.unpack or unpack

-- Frames that keep parent, points, scale, mouse and fixed flags like the client.
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
    frame.SetFixedFrameStrata = function(self, value) self.fixedStrata = value end
    frame.SetFixedFrameLevel = function(self, value) self.fixedLevel = value end
    frame.HookScript = function(self, name, fn)
        self.hooks = self.hooks or {}
        local old = self.hooks[name]
        self.hooks[name] = old and function(...) old(...); fn(...) end or fn
    end
    frame.GetName = function(self) return self._name end
    frame.GetObjectType = function(self) return self.kind end
    frame.GetChildren = function(self)
        local children = {}
        for _, object in ipairs(mock.created) do
            if object.parent == self and (object.kind == "Frame" or object.kind == "Button") then
                children[#children + 1] = object
            end
        end
        return unpack(children)
    end
    return frame
end
local baseCreate = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent)
    local frame = Rich(baseCreate(kind, name, parent))
    frame._name = name
    return frame
end
local function New(kind, parent) return Rich(mock.New(kind, parent)) end

-- Post-hooks like the client's: the original runs, then the hook.
_G.hooksecurefunc = function(target, name, hook)
    local original = target[name]
    target[name] = function(...) original(...); hook(...) end
end
_G.CreateColor = function(...) return { ... } end
local over = {}
_G.MouseIsOver = function(frame) return over[frame] == true end
local lockdown = false
_G.InCombatLockdown = function() return lockdown end
local altDown = false
_G.IsAltKeyDown = function() return altDown end
-- Edit Mode's EventRegistry callbacks, fired by hand.
_G.EventRegistry = { callbacks = {} }
function _G.EventRegistry:RegisterCallback(event, fn, owner) self.callbacks[event] = { fn = fn, owner = owner } end
-- The radar's own /vr handler (UI/Radar.lua) and chat output.
local passed
_G.SlashCmdList = { VIGNETTERADAR = function(message) passed = message end }
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

-- The radar: a field with its face and the corner tools.
local panel = New("Frame")
panel.level, panel.strata = 10, "MEDIUM"
panel.field = New("Frame", panel)
panel.field.level = 11
panel.field.background = New("Texture", panel.field)
panel.field.background.width, panel.field.background.height = 180, 180
panel.hoverTools = {}
for index, id in ipairs({ "config", "target", "legend", "tracker", "eye", "player" }) do
    local tool = CreateFrame("Button", nil, panel.field)
    tool:SetSize(16, 16)
    tool.level = 19
    tool:SetPoint("TOPLEFT", panel.field, "TOPLEFT", 12 * index, -12)
    tool.toolID, tool.advancedTool = id, id == "player"
    tool.shown = false
    panel.hoverTools[index] = tool
end
panel.RefreshCornerTools = function() panel.refreshed = (panel.refreshed or 0) + 1 end
panel._chromeTools, panel._hoverToolsVisible = false, false
addon.VignetteRadarAPI = { GetPanel = function() return panel end }

-- Blizzard's minimap and its extras.
local map = New("Frame")
_G.Minimap = map
local cluster = New("Frame")
_G.MinimapCluster = cluster
local clock = CreateFrame("Button", "GameTimeFrame", cluster)
clock:SetSize(19, 18)
clock:SetPoint("TOPRIGHT", cluster, "TOPRIGHT", -2, -4)
cluster.Tracking = New("Frame", cluster)
cluster.Tracking:SetSize(17, 17)
cluster.Tracking.shown = false
cluster.IndicatorFrame = New("Frame", cluster)
cluster.IndicatorFrame:SetSize(20, 15)
local landing = CreateFrame("Button", "ExpansionLandingPageMinimapButton", New("Frame"))
landing:SetSize(53, 53)
landing.mouse = false -- the underlay's HideChrome turned it off
landing:SetPoint("TOPLEFT", landing.parent, "TOPLEFT", -3, -150)
landing.SetLandingPageIconOffset = function(self, x, y) self:SetPoint("TOPLEFT", x, y) end

-- A LibDBIcon-1.0 stand-in with one button and a late one.
local function DBButton(name, hide)
    local button = CreateFrame("Button", "LibDBIcon10_" .. name, map)
    button:SetSize(31, 31)
    button:SetPoint("CENTER", map, "CENTER", 80, 0)
    button.fixedStrata, button.fixedLevel = true, true
    button.strata, button.level = "MEDIUM", 8
    button.db = { hide = hide }
    button.border = New("Texture", button)
    button.border.shown = true
    button.showOnMouseover = true
    button.alpha = 0
    button.fadeOut = { Stop = function(self) self.stopped = true end }
    local start, stop = function() end, function() end
    button:SetScript("OnDragStart", start)
    button:SetScript("OnDragStop", stop)
    button.handlers = { start, stop }
    return button
end
local lib = { objects = {}, refreshed = {} }
lib.objects.Alpha = DBButton("Alpha")
lib.objects.Hidden = DBButton("Hidden", true)
lib.objects.Hidden.shown = false
function lib:GetButtonList() local list = {}; for name in pairs(self.objects) do list[#list + 1] = name end; return list end
function lib:GetMinimapButton(name) return self.objects[name] end
function lib:Refresh(name)
    self.refreshed[#self.refreshed + 1] = name
    local button = self.objects[name]
    button:SetPoint("CENTER", map, "CENTER", 80, 0)
end
function lib.RegisterCallback(owner, event, fn) lib.callback = { owner = owner, event = event, fn = fn } end
_G.LibStub = setmetatable({}, { __call = function(_, name) return name == "LibDBIcon-1.0" and lib or nil end })

local function Load(path)
    local chunk = assert(loadfile(path))
    return chunk("VignetteRadar", addon)
end
-- Hand-made minimap buttons for the fallback scan.
local function Hand(name, parent, width, height, mouse)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(width or 30, height or width or 30)
    button.mouse = mouse ~= false
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    return button
end
local handMade = Hand("MyAddonMinimapButton", map)
local tooBig = Hand("BigAddonFrame", map, 60)
local unnamed = Hand(nil, map)
local stretched = Hand("WideAddonBar", map, 40, 20)
local mouseless = Hand("DeafAddonButton", map, 30, 30, false)
local clockButton = Hand("TimeManagerClockButton", cluster)
local notButton = CreateFrame("Frame", "NotAButtonFrame", map)
notButton:SetSize(30, 30)
local holder = CreateFrame("Frame", "AddonHolder", cluster)
holder:SetSize(200, 200)
local nested = Hand("NestedAddonButton", holder, 24)
local preIgnored = Hand("IgnoredAddonButton", map)
settings.vignetteRadarButtonTrayIgnore = { IgnoredAddonButton = true }
local handHome = { handMade:GetPoint(1) }

Load("UI/IconButton.lua")
Load("UI/Tray.lua")
Load("UI/MinimapUnderlay.lua")
local Underlay = addon.VignetteRadarMinimapUnderlay
local underlayTool = Underlay.EnsureTool(panel)
local toolHome = { underlayTool:GetPoint(1) }
local Buttons = Load("UI/ButtonTray.lua")
assert(Buttons == addon.VignetteRadarButtonTray, "module registered")
local driver
for _, frame in ipairs(mock.frames) do
    if frame.scripts and frame.scripts.OnUpdate and frame.scripts.OnEvent and not frame.parent then driver = frame end
end
assert(driver, "tray driver frame")
local function Tick(seconds) driver.scripts.OnUpdate(driver, seconds or 1) end
local function Fire(event) driver.scripts.OnEvent(driver, event) end

-- Grid math -----------------------------------------------------------------
do
    assert(Buttons.Rows(0) == 0 and Buttons.Rows(1) == 1 and Buttons.Rows(3) == 1 and Buttons.Rows(4) == 2,
        "rows of three")
    assert(Buttons.VisibleRows(180, 15) == 5, "15 radar tools under a 180 cap: 5 rows")
    assert(Buttons.VisibleRows(60, 15) == 1, "a 60 cap still shows one row")
    assert(Buttons.VisibleRows(180, 0) == 1, "no radar tools: one row")
    assert(Buttons.VisibleRows(400, 4) == 2, "only the rows the radar set needs")
    local width, height = Buttons.Size(5)
    assert(width == 2 * 6 + 3 * 22 + 2 * 3 and height == 2 * 6 + 22 + 3 + 5 * 25 - 3, "size for 5 rows")
    assert(select(1, Buttons.Size(1)) == width, "width never depends on the rows")
    assert(Buttons.ClampScroll(-2, 8, 5) == 0 and Buttons.ClampScroll(9, 8, 5) == 3
        and Buttons.ClampScroll(2, 8, 5) == 2 and Buttons.ClampScroll(1, 4, 5) == 0, "scroll clamps")
    -- SlotAt(x, y, n, scrollRows, visibleRows): viewport-local units, 25 px pitch.
    assert(Buttons.SlotAt(5, 5, 10, 0, 5) == 0, "left half of cell 0")
    assert(Buttons.SlotAt(2 * 25 + 15, 5, 10, 0, 5) == 3, "right half of cell 2")
    assert(Buttons.SlotAt(5, 25 + 5, 10, 1, 5) == 6, "row 1 col 0 scrolled one row")
    assert(Buttons.SlotAt(5, 4 * 25 + 5, 4, 0, 5) == 4, "past the last row: the end")
    assert(Buttons.SlotAt(72 + 23, 5, 10, 0, 5) == nil, "beyond width + cell: outside")
    assert(Buttons.SlotAt(5, -23, 10, 0, 5) == nil, "above the viewport: outside")
    assert(Buttons.SlotAt(5, 5, 0, 0, 5) == 0, "empty set: slot 0")
    local _, position = Buttons.SlotAt(30, 30, 10, 0, 5)
    assert(position == 4, "grid position under the cursor")
    -- Saved order: saved names first, unknown after in default order.
    local saved = { "B", "A" }
    assert(Buttons.Rank(saved, "A", 1) == 2 and Buttons.Rank(saved, "B", 5) == 1, "saved order wins")
    assert(Buttons.Rank(saved, "C", 100) == 102, "unknown after the saved ones")
    assert(Buttons.Rank(nil, "C", 7) == 7, "no saved order: default")
    local merged = Buttons.MergeOrder({ "A", "C" }, { "B", "A", "Gone" })
    assert(table.concat(merged, ",") == "A,C,B,Gone", "absent saved names kept at the tail")
end

-- Off by default until the underlay borrows ----------------------------------
assert(not Buttons.IsGathered(), "nothing gathered before the underlay")
assert(Buttons.CollectsMinimap() == true, "collects minimap buttons by default")

-- Underlay on: the radar's tools leave the face ------------------------------
local homes = {}
for _, tool in ipairs(panel.hoverTools) do homes[tool] = { tool:GetPoint(1) } end
Underlay.NotifyTray(true, panel)
assert(Buttons.IsGathered(), "gathered on borrow")
for _, tool in ipairs(panel.hoverTools) do
    assert(tool:GetParent() ~= panel.field and Buttons.Holds(tool), tool.toolID .. " left the face")
    assert(tool._vrInTray == true, tool.toolID .. " flagged for the radar chrome")
    assert(tool:IsShown() == (tool.toolID ~= "player"), tool.toolID .. " shown in the tray unless advanced")
end
assert(Buttons.Holds(underlayTool), "underlay toggle gathered too")
assert(Buttons.GetHandle() and Buttons.GetHandle():IsShown(), "lip shown while underlay is on")
assert(Buttons.Side() == "right", "tray on the right while the radar tray is not docked right")
assert(not Buttons.IsOpen() and not Buttons.GetSlot():IsShown(), "hidden by default")
assert(Buttons.CurrentSet() == "radar", "radar set first")
assert(Traced("buttons: gather config"), "gather traced")

-- The other set is gathered too, hidden behind the flip.
local alpha = lib.objects.Alpha
assert(Buttons.Holds(alpha) and Buttons.Holds(lib.objects.Hidden), "LibDBIcon buttons gathered")
assert(alpha.fixedStrata == false and alpha.fixedLevel == false, "fixed strata lifted while gathered")
assert(alpha:GetScript("OnDragStart") == nil and alpha:GetScript("OnDragStop") == nil, "drag off while gathered")
assert(alpha.showOnMouseover == false and alpha.alpha == 1 and alpha.fadeOut.stopped, "mouseover fade off")
assert(alpha.border.shown == false, "LibDBIcon border hidden in the tray")
assert(math.abs(alpha.scale - 22 / 31) < 1e-6, "scaled to the cell")
assert(alpha:IsShown() and not lib.objects.Hidden:IsShown(), "db.hide respected")
assert(Buttons.Holds(clock) and Buttons.Holds(cluster.Tracking) and Buttons.Holds(cluster.IndicatorFrame),
    "Blizzard extras gathered")
assert(Buttons.Holds(landing) and landing.mouse == true, "landing page clickable in the tray")

-- Addon buttons are locked (MinimapButtonBag style): an owner's move does nothing.
lib:Refresh("Alpha")
assert(alpha:GetNumPoints() == 1 and select(2, alpha:GetPoint(1)) ~= map, "LibDBIcon re-place ignored")
assert(not Traced("re%-pin Alpha"), "locked button needs no re-pin")
-- Blizzard frames keep the re-pin hook.
landing:SetLandingPageIconOffset(-3, -150)
assert(landing:GetNumPoints() == 1 and select(1, landing:GetPoint(1)) == "CENTER", "landing offset re-pinned")

-- Open, close, click away, combat -------------------------------------------
mock.Click(Buttons.GetHandle())
Tick(1)
assert(Buttons.IsOpen() and Buttons.GetSlot():IsShown(), "lip click slides the tray out")
over[Buttons.GetSlot()] = true
Fire("GLOBAL_MOUSE_DOWN")
assert(Buttons.IsOpen(), "a click inside keeps it out")
over[Buttons.GetSlot()] = nil
Fire("GLOBAL_MOUSE_DOWN")
Tick(1)
assert(not Buttons.IsOpen() and not Buttons.GetSlot():IsShown(), "a click away slides it in")
mock.Click(Buttons.GetHandle()); Tick(1)
-- The tray's own lock (header button), not the radar tray's.
settings.vignetteRadarTrayLocked = true
Fire("PLAYER_REGEN_DISABLED")
assert(not Buttons.IsOpen(), "the radar tray's lock no longer holds this tray")
settings.vignetteRadarTrayLocked = nil
mock.Click(Buttons.GetHandle()); Tick(1)
local lockButton = Buttons.GetLock()
assert(lockButton and lockButton:IsShown(), "lock button in the tray header")
mock.Click(lockButton)
assert(settings.vignetteRadarButtonTrayLocked == true and Buttons.IsLocked(), "lock click saves the lock")
assert(Traced("buttons: lock on"), "lock traced")
Fire("PLAYER_REGEN_DISABLED")
assert(Buttons.IsOpen(), "locked: combat keeps it out")
Fire("GLOBAL_MOUSE_DOWN")
assert(Buttons.IsOpen(), "locked: a click away keeps it out")
mock.Click(lockButton)
assert(settings.vignetteRadarButtonTrayLocked == false, "second click unlocks")
Fire("PLAYER_REGEN_DISABLED")
assert(not Buttons.IsOpen(), "combat slides it in")
mock.Click(Buttons.GetHandle())
mock.Click(Buttons.GetHandle())
assert(not Buttons.IsOpen() and Traced("close %(lip%)"), "second lip click slides it in")

-- Flip ------------------------------------------------------------------------
Buttons.Flip()
assert(settings.vignetteRadarButtonTraySet == "minimap" and Buttons.CurrentSet() == "minimap", "flip saved")
assert(Traced("flip to minimap"), "flip traced")
Buttons.Flip()
assert(Buttons.CurrentSet() == "radar", "flip back")

-- A late LibDBIcon button joins.
lib.objects.Late = DBButton("Late")
lib.callback.fn("LibDBIcon_IconCreated", lib.objects.Late, "Late")
assert(Buttons.Holds(lib.objects.Late), "late IconCreated button gathered")

-- Advanced Tools turned on shows the Player Tracker tool in the tray.
settings.vignetteRadarAdvancedTools = true
Buttons.Layout()
assert(panel.hoverTools[6]:IsShown(), "advanced tool shown once Advanced Tools is on")
settings.vignetteRadarAdvancedTools = false

-- The radar tray docked right puts this one on the left.
local tray = addon.VignetteRadarTray
local side = tray.Side
tray.Side = function() return "right" end
Buttons.Place()
assert(Buttons.Side() == "left", "opposite the radar tray")
tray.Side = side
Buttons.Place()

-- Collect Minimap Buttons off gives the minimap set back, radar stays.
settings.vignetteRadarButtonTrayMinimap = false
settings.vignetteRadarButtonTraySet = "minimap"
Buttons.Sync()
assert(not Buttons.Holds(alpha) and alpha:GetParent() == map, "minimap set given back")
assert(Buttons.CurrentSet() == "radar", "only the radar set without minimap buttons")
assert(Buttons.Holds(panel.hoverTools[1]), "radar set kept")
settings.vignetteRadarButtonTrayMinimap = nil
settings.vignetteRadarButtonTraySet = "radar"
Buttons.Sync()
assert(Buttons.Holds(alpha), "minimap set gathered again")

-- Combat: a protected frame waits ---------------------------------------------
local secure = CreateFrame("Button", "LibDBIcon10_Secure", map)
secure:SetSize(31, 31)
secure.IsProtected = function() return true end
secure.border, secure.fadeOut = New("Texture", secure), { Stop = function() end }
lib.objects.Secure = secure
lockdown = true
lib.callback.fn("LibDBIcon_IconCreated", secure, "Secure")
assert(not Buttons.Holds(secure) and Traced("gather Secure waits"), "protected frame waits for combat")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
assert(Buttons.Holds(secure), "gathered after combat")

-- Fallback scan for hand-made buttons --------------------------------------
assert(Buttons.Holds(handMade) and Buttons.KindOf(handMade) == "scan", "named 30 px button on the Minimap gathered")
assert(Buttons.Holds(nested), "button one level under a cluster child gathered")
assert(not Buttons.Holds(tooBig) and Traced("skip BigAddonFrame %(size 60x60%)"), "60 px frame skipped")
assert(not Buttons.Holds(stretched) and Traced("skip WideAddonBar %(size 40x20%)"), "non-square skipped")
assert(not Buttons.Holds(unnamed), "unnamed button skipped")
assert(not Buttons.Holds(mouseless) and Traced("skip DeafAddonButton %(no mouse%)"), "mouse-off button skipped")
assert(not Buttons.Holds(notButton), "plain Frame skipped")
assert(not Buttons.Holds(clockButton) and Traced("skip TimeManagerClockButton %(Blizzard%)"), "Blizzard name skipped")
assert(not Buttons.Holds(preIgnored) and preIgnored:GetParent() == map, "ignored name left alone")
assert(Traced("skip IgnoredAddonButton %(ignored%)"), "ignore skip traced")
assert(not Traced("skip LibDBIcon10_Alpha"), "LibDBIcon buttons are the lib's, never traced as scan skips")
assert(Buttons.ScanReason(lib.objects.Alpha) == "gathered", "gathered LibDBIcon button not scanned twice")
do
    local probe = Hand("LibDBIcon10_Probe", New("Frame"))
    assert(Buttons.ScanReason(probe) == "LibDBIcon", "LibDBIcon names left to the lib path")
    local ours = Hand("VignetteRadarProbe", New("Frame"))
    assert(Buttons.ScanReason(ours) == "ours", "our own frames skipped")
end
assert(handMade.scale == 22 / 30 and handMade.level ~= nil, "scanned button scaled to the cell")

-- A button made later joins when the tray opens.
local lateHand = Hand("LateAddonButton", map)
assert(not Buttons.Holds(lateHand), "not gathered before a rescan")
mock.Click(Buttons.GetHandle())
assert(Buttons.Holds(lateHand) and Traced("scan %(open%): 1 joined"), "rescan when the tray opens")
mock.Click(Buttons.GetHandle()); Tick(1)

-- ADDON_LOADED: one throttled scan a moment later.
local loadedHand = Hand("LoadedAddonButton", map)
Fire("ADDON_LOADED"); Fire("ADDON_LOADED")
Tick(.5)
assert(not Buttons.Holds(loadedHand), "scan waits after ADDON_LOADED")
Tick(.6)
assert(Buttons.Holds(loadedHand) and Traced("scan %(addon loaded%): 1 joined"), "scan after ADDON_LOADED")

-- Scan setting off gives scanned buttons back; on gathers them again.
settings.vignetteRadarButtonTrayScan = false
Buttons.Sync()
assert(not Buttons.Holds(handMade) and handMade:GetParent() == map, "scan off: hand-made buttons given back")
assert(Buttons.Holds(alpha), "scan off: LibDBIcon buttons stay")
settings.vignetteRadarButtonTrayScan = nil
Buttons.Sync()
assert(Buttons.Holds(handMade), "scan on again")

-- Cell plates and hover tint -------------------------------------------------
do
    local cell = Buttons.CellOf(alpha)
    assert(cell and cell.plate and cell.plate.texture:find("control%-rounded%-square"), "rounded plate on the cell")
    local idle = cell.plate.vertex
    assert(idle and math.abs(idle[4] - .8) < 1e-6, "idle plate")
    alpha.hooks.OnEnter(alpha)
    assert(cell._hovered and math.abs(cell.plate.vertex[4] - .32) < 1e-6, "hover tints the plate")
    alpha.hooks.OnLeave(alpha)
    assert(not cell._hovered and cell.plate.vertex[4] == idle[4], "leave restores the plate")
    addon.VignetteRadarStyle = { Color = function(role)
        if role == "accent" then return 1, 0, 0 end
        return .5, .5, .5
    end }
    Buttons.RefreshTheme()
    assert(math.abs(cell.plate.vertex[1] - (.5 + .5 * .12)) < 1e-6, "theme change repaints plates")
    alpha.hooks.OnEnter(alpha)
    assert(cell.plate.vertex[1] == 1 and cell.plate.vertex[2] == 0, "hover uses the theme accent")
    alpha.hooks.OnLeave(alpha)
    addon.VignetteRadarStyle = nil
    Buttons.RefreshTheme()
end

-- Header: config pinned left, then flip and lock ------------------------------
do
    Buttons.Layout()
    local flipButton
    for _, object in ipairs(mock.created) do
        if object.parent == Buttons.GetContent() and object.kind == "Button" and object ~= lockButton
            and object.toolID == nil then
            flipButton = object
        end
    end
    local _, _, _, flipX = flipButton:GetPoint(1)
    local _, _, _, lockX = lockButton:GetPoint(1)
    local config = panel.hoverTools[1]
    local cell = Buttons.CellOf(config)
    assert(cell:GetParent() == Buttons.GetContent(), "config cell pinned to the content, not a group")
    local _, _, _, cellX, cellY = cell:GetPoint(1)
    assert(cellX == 6 and cellY == -6, "config in the header corner")
    assert(flipX == 6 + 22 + 3 and lockX - flipX == 16 + 3, "flip right of config, lock right of flip")
    assert(Buttons.GetContent():GetWidth() == 84, "fixed 3-column width")
end

-- Ignore: Alt+Right-click, slash ----------------------------------------------
handMade.hooks.OnMouseUp(handMade, "RightButton")
assert(Buttons.Holds(handMade), "right-click alone does not ignore")
altDown = true
panel.hoverTools[1].hooks.OnMouseUp(panel.hoverTools[1], "RightButton")
assert(Buttons.Holds(panel.hoverTools[1]), "radar tools cannot be ignored")
handMade.hooks.OnMouseUp(handMade, "RightButton")
altDown = false
assert(not Buttons.Holds(handMade) and handMade:GetParent() == map, "Alt+Right-click ignores and gives back")
assert(settings.vignetteRadarButtonTrayIgnore.MyAddonMinimapButton == true, "ignore saved")
assert(Said("/magpie buttons unignore MyAddonMinimapButton"), "chat line says how to undo")
mock.Click(Buttons.GetHandle())
assert(not Buttons.Holds(handMade), "ignored button stays out on rescan")
mock.Click(Buttons.GetHandle()); Tick(1)

SlashCmdList.VIGNETTERADAR("config")
assert(passed == "config", "other /vr words reach the radar's handler")
SlashCmdList.VIGNETTERADAR("buttons ignore Alpha")
assert(not Buttons.Holds(alpha) and alpha:GetParent() == map, "/vr buttons ignore <LibDBIcon name>")
chat = {}
SlashCmdList.VIGNETTERADAR("buttons")
assert(Said("Minimap buttons in the tray %(%d+%):.*GameTimeFrame"), "/vr buttons lists the minimap set")
assert(Said("Radar buttons in the tray %(%d+%):.*config"), "/vr buttons lists the radar set")
assert(Said("Ignored %(3%): Alpha, IgnoredAddonButton, MyAddonMinimapButton"), "/vr buttons lists ignored")
SlashCmdList.VIGNETTERADAR("buttons unignore alpha")
assert(Buttons.Holds(alpha) and Said("Alpha is no longer ignored"), "unignore (any case) gathers it again")
SlashCmdList.VIGNETTERADAR("buttons unignore Nope")
assert(Said("Nope is not on the ignore list"), "unknown unignore reported")
SlashCmdList.VIGNETTERADAR("buttons reset")
assert(Said("Ignore list cleared %(2 removed%)"), "reset reports the count")
assert(Buttons.Holds(handMade) and Buttons.Holds(preIgnored), "reset gathers the ignored buttons")
assert(next(settings.vignetteRadarButtonTrayIgnore) == nil, "ignore list empty")
SlashCmdList.VIGNETTERADAR("buttons what")
assert(Said("Usage: /magpie buttons"), "usage line")

-- Edit Mode gives Blizzard's frames back ---------------------------------------
do
    local enter, exit = EventRegistry.callbacks["EditMode.Enter"], EventRegistry.callbacks["EditMode.Exit"]
    assert(enter and exit and enter.owner == Buttons, "Edit Mode callbacks registered")
    enter.fn(enter.owner)
    assert(not Buttons.Holds(clock) and clock:GetParent() == cluster, "calendar back for Edit Mode")
    assert(not Buttons.Holds(cluster.Tracking) and not Buttons.Holds(cluster.IndicatorFrame), "cluster pieces back")
    assert(Buttons.Holds(alpha) and Buttons.Holds(handMade), "addon buttons stay in the tray")
    assert(Traced("edit mode on"), "Edit Mode traced")
    exit.fn(exit.owner)
    assert(Buttons.Holds(clock) and Buttons.Holds(cluster.Tracking), "re-gathered after Edit Mode")
end

-- Underlay off: everything goes back exactly ---------------------------------
local refreshes = #lib.refreshed
Underlay.NotifyTray(false, panel)
assert(not Buttons.IsGathered(), "tray put away")
for _, tool in ipairs(panel.hoverTools) do
    local point, home = { tool:GetPoint(1) }, homes[tool]
    assert(tool:GetParent() == panel.field and tool:GetNumPoints() == 1, tool.toolID .. " back on the field")
    for index = 1, 5 do assert(point[index] == home[index], tool.toolID .. " back in its corner slot") end
    assert(tool._vrInTray == nil and tool.level == 19 and tool:GetScale() == 1, tool.toolID .. " restored")
    assert(tool:IsShown() == false, tool.toolID .. " shown state restored")
end
assert(panel._chromeTools == nil and panel._hoverToolsVisible == nil, "radar re-applies corner visibility")
assert(underlayTool:GetParent() == panel.field and select(2, underlayTool:GetPoint(1)) == toolHome[2],
    "underlay toggle back in its slot")
assert(alpha:GetParent() == map and alpha.fixedStrata == true and alpha.fixedLevel == true, "LibDBIcon restored")
assert(alpha:GetScript("OnDragStart") == alpha.handlers[1] and alpha:GetScript("OnDragStop") == alpha.handlers[2],
    "drag scripts restored")
assert(alpha.showOnMouseover == true and alpha.border.shown == true and alpha.alpha == 0, "fade and border restored")
assert(alpha.strata == "MEDIUM" and alpha.level == 8 and alpha:GetScale() == 1, "strata, level, scale restored")
assert(#lib.refreshed > refreshes, "LibDBIcon re-placed by lib:Refresh")
assert(clock:GetParent() == cluster and select(1, clock:GetPoint(1)) == "TOPRIGHT", "calendar back")
assert(cluster.Tracking:GetParent() == cluster and cluster.Tracking.shown == false, "tracking back, still hidden")
assert(landing.mouse == false and landing:GetParent() ~= nil, "landing mouse back for the underlay chrome")
assert(not Buttons.GetHandle():IsShown(), "lip hidden with the underlay off")
landing:SetLandingPageIconOffset(-3, -150)
assert(landing:GetNumPoints() == 2, "hooks idle once given back")
do
    local point = { handMade:GetPoint(1) }
    assert(handMade:GetParent() == map and handMade:GetNumPoints() == 1, "hand-made button back on the Minimap")
    for index = 1, 5 do assert(point[index] == handHome[index], "hand-made button back in its spot") end
    assert(handMade:GetScale() == 1 and nested:GetParent() == holder, "scale and nested parent restored")
end

-- Setting off: the underlay leaves the corner tools alone ---------------------
settings.vignetteRadarButtonTray = false
Underlay.NotifyTray(true, panel)
assert(not Buttons.IsGathered() and panel.hoverTools[1]:GetParent() == panel.field, "off: tools stay on the face")
assert(Buttons.CollectsMinimap() == false, "off: the underlay hides LibDBIcon buttons as before")
settings.vignetteRadarButtonTray = true
Buttons.Sync()
assert(Buttons.IsGathered(), "turned on while the underlay is on")
Underlay.NotifyTray(false, panel)
assert(not Buttons.IsGathered(), "and given back")

_G.print = realPrint
print("button_tray_test passed")
