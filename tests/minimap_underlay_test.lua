-- Minimap Underlay: borrows Blizzard's Minimap into the radar face, masks it
-- by layout, matches its zoom and size to the radar range, follows North Up,
-- defers in combat, and gives every piece of state back exactly.
local unpack = table.unpack or unpack
local mock = dofile("tests/ui_mock.lua").Install()
local settings = { vignetteRadarMinimapUnderlay = false, vignetteRadarMinimapUnderlayTint = .4,
    vignetteRadarMinimapUnderlayHideChrome = true, vignetteRadarNorthUp = false }
local addon = { GetSettings = function() return settings end }
addon.VignetteRadarRanges = { 10, 25, 50, 100, 150, 300, 450, 600, 1200, 2400, 4800 }
local lockdown = false
_G.InCombatLockdown = function() return lockdown end
local cvars = { rotateMinimap = "0", minimapZoom = "3", minimapInsideZoom = "1" }
_G.C_CVar = { GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = value end }
local ignoreRotate = false
local zoom = 3
local radius = { [0] = 233.333, 200, 166.667, 133.333, 100, 66.667 }
_G.C_Minimap = { GetViewRadius = function() return radius[zoom] end,
    IsRotateMinimapIgnored = function() return ignoreRotate end,
    SetIgnoreRotateMinimap = function(value) ignoreRotate = value end }
_G.IsIndoors = function() return false end
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
local clock = 100
_G.GetTime = function() return clock end
-- Chat lines from the module itself (trace lines go to the same frame).
local said = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text)
    if text:find("Magpie|r: ", 1, true) then said[#said + 1] = text end
end }
-- A deferred C_Timer like the client's: callbacks run on the next Tick, so a
-- re-assert lands a frame after the drift, as in game.
local timers = {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function Tick()
    local run = timers
    timers = {}
    for _, fn in ipairs(run) do fn() end
end
-- Edit Mode's EventRegistry, fired by hand.
_G.EventRegistry = { callbacks = {} }
function _G.EventRegistry:RegisterCallback(event, fn, owner)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], { fn = fn, owner = owner })
end
function _G.EventRegistry:TriggerEvent(event, ...)
    for _, entry in ipairs(self.callbacks[event] or {}) do entry.fn(entry.owner, ...) end
end
-- Post-hooks like the client's: the original runs, then every hook in order.
_G.hooksecurefunc = function(target, name, hook)
    local original = target[name]
    target[name] = function(...) original(...); hook(...) end
end

-- A Blizzard-like Minimap inside MinimapCluster.
local cluster = mock.New("Frame")
local container = mock.New("Frame", cluster)
cluster.MinimapContainer = container
container.strata, container.level = "LOW", 4
local map = mock.New("Minimap", container)
_G.MinimapCluster, _G.Minimap = cluster, map
map.width, map.height, map.level, map.strata, map.scale = 198, 198, 5, "LOW", .9
map.points = { { "CENTER", container, "CENTER", 0, 0 } }
map.mouse, map.wheel = true, true
map.GetParent = function(self) return self.parent end
map.SetParent = function(self, parent) self.parent = parent end
map.GetNumPoints = function(self) return #self.points end
map.GetPoint = function(self, index) return unpack(self.points[index]) end
map.ClearAllPoints = function(self) self.points = {} end
map.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
map.GetScale = function(self) return self.scale end
map.SetScale = function(self, value) self.scale = value end
map.GetZoom = function() return zoom end
map.SetZoom = function(_, value) zoom = value end
map.GetZoomLevels = function() return 6 end
map.SetMaskTexture = function(self, value) self.mask = value end
map.IsMouseEnabled = function(self) return self.mouse end
map.EnableMouse = function(self, value) self.mouse = value end
map.IsMouseWheelEnabled = function(self) return self.wheel end
map.EnableMouseWheel = function(self, value) self.wheel = value end
map.IsProtected = function() return false end
-- Engine icon textures: no getter exists, so the mock only records writes.
map.SetBlipTexture = function(self, value) self.blip = value end
map.SetPlayerTexture = function(self, value) self.playerArrow = value end
local hit = mock.New("Frame", map)
hit.mouse = true
hit.IsMouseEnabled = function(self) return self.mouse end
hit.EnableMouse = function(self, value) self.mouse = value end
map.ZoomHitArea = hit
local dbIcon = mock.New("Button", map)
dbIcon.GetName = function() return "LibDBIcon10_Example" end
map.GetChildren = function() return dbIcon end
local backdrop = mock.New("Frame", map)
_G.MinimapBackdrop = backdrop

-- A radar panel with a round face and the corner tools.
local panel = mock.New("Frame")
panel.level = 10
panel.field = mock.New("Frame", panel)
panel.field.level = 11
panel.field.GetChildren = function() return nil end
panel.field.background = mock.New("Texture", panel.field)
panel.field.background.GetVertexColor = function(self) local v = self.vertex or {} return v[1], v[2], v[3], v[4] end
panel.fieldRadius, panel.plotRadius, panel.squarePlot = 91, 70, false
local eye = mock.New("Button", panel.field)
eye.toolID = "eye"
panel.hoverTools = { eye }
local refreshes = 0
-- The real RefreshRadar renders at once (UI/Radar.lua), and Render calls Sync.
local Underlay
addon.VignetteRadarAPI = { GetPanel = function() return panel end, Refresh = function()
    refreshes = refreshes + 1
    if Underlay then Underlay.Sync(150, panel) end
end }
addon.VignetteRadarStyle = { revision = 1, Color = function() return .1, .2, .3 end }

assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Trace.lua"))("VignetteRadar", addon)
assert(loadfile("UI/MinimapUnderlay.lua"))("VignetteRadar", addon)
Underlay = assert(addon.VignetteRadarMinimapUnderlay)
addon.Trace.SetEnabled(true)
local function LastTrace() local lines = addon.Trace.Lines(); return lines[#lines] or "" end
-- True when one of the last few trace lines matches (the view and icon
-- traces follow the borrow line inside one Sync).
local function RecentTrace(pattern)
    local lines = addon.Trace.Lines()
    for index = #lines, math.max(1, #lines - 5), -1 do
        if lines[index]:find(pattern) then return true end
    end
    return false
end

-- Fill mapping: the Minimap fills the face; the range snaps to the closest zoom.
local radii = { 233.333, 200, 166.667, 133.333, 100, 66.667 }
local z, half, drawn = Underlay.ZoomFor(150, 70, 91, radii)
assert(z == 1 and half == 91 and drawn == 154, "150 yd snaps to zoom 1 at 154 yd, filling the face")
z, half, drawn = Underlay.ZoomFor(25, 70, 91, radii)
assert(z == 5 and drawn == 51 and half == 91, "too close for any zoom snaps to the closest zoom")
z, half, drawn = Underlay.ZoomFor(4800, 70, 91, radii)
assert(z == 0 and half == 91 and drawn == 179, "far past the widest zoom locks to it")
assert(Underlay.ZoomFor(200, 70, 91, radii) == 0, "a little past the widest zoom still snaps to it")
assert(Underlay.MaskFor(true) == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga"
    and Underlay.MaskFor(false) == 186178, "mask by layout")
local indoorRadii, indoor = (function() zoom = 1; radius[1] = 120; return Underlay.Radii() end)()
assert(indoor and math.abs(indoorRadii[1] - 150) < .01, "live view radius picks the indoor table")
zoom, radius[1] = 3, 200

-- Off: nothing is touched; the corner toggle exists.
assert(Underlay.Sync(150, panel) == 150 and map.parent == container and not Underlay.IsActive())
local tool = assert(Underlay.GetTool(), "corner toggle")
assert(tool.parent == panel.field and tool.art.texture:find("radar%-minimap%-underlay"))
mock.Enter(tool)
assert(GameTooltip.lines[1] == "Minimap Underlay", "toggle tooltip")

-- Clicking the toggle turns it on; the next render borrows the Minimap.
mock.Click(tool)
assert(settings.vignetteRadarMinimapUnderlay == true and refreshes > 0)
assert(Underlay.Sync(150, panel) == 140 and Underlay.IsActive(), "range snaps to the zoom filling the face")
assert(map.parent == panel and map.level == 11 and panel.field.level == 13, "minimap sits under the raised face")
assert(map.mask == 186178 and map.mouse == false and map.wheel == false, "round mask, mouse off")
assert(hit.mouse == false, "zoom hit area passes the mouse through")
assert(zoom == 1 and map.width == 200, "the minimap fills the whole round face")
assert(cluster.shown == false and backdrop.alpha == 0 and dbIcon.shown == false, "chrome hidden")
assert(cvars.rotateMinimap == "1", "a turning radar turns the minimap")
assert(math.abs(panel.field.background.vertex[4] - .4) < 1e-6 and math.abs(Underlay.FaceAlpha() - .4) < 1e-6,
    "the face carries the tint over the terrain")
assert(map.alpha == 1 and Underlay.MapAlpha() == 1, "terrain always opaque (indoor art needs alpha 1)")
assert(tool.point[1] == "BOTTOMRIGHT" and tool.point[4] == -12 and tool.point[5] == 12,
    "toggle sits in the bottom-right corner grid")

-- Right-click flips to Circle: a round map the size of the outer range ring,
-- with the range snapped to that zoom's own radius.
mock.Click(tool, "RightButton")
assert(settings.vignetteRadarMinimapUnderlayShape == "circle" and Underlay.Shape() == "circle")
assert(Underlay.Sync(150, panel) == 167 and zoom == 2, "circle snaps to the zoom radius")
assert(map.width == 140 and map.mask == 186178, "circle fits the range ring")
mock.Click(tool, "RightButton")
assert(Underlay.Shape() == "square" and Underlay.Sync(150, panel) == 140 and map.width == 200, "back to square")
assert(Underlay.IsEnabled(), "right-click never turns the underlay off")

-- North Up ignores rotation without touching the CVar further.
settings.vignetteRadarNorthUp = true
Underlay.Sync(150, panel)
assert(ignoreRotate == true and cvars.rotateMinimap == "1", "north-up ignores rotate")

-- A square layout switches the mask; a wide range hides the terrain.
panel.squarePlot = true
Underlay.Sync(150, panel)
assert(map.mask == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga" and map.width == 182,
    "square faces use the face's rounded square and fill it")
local locked = Underlay.Sync(4800, panel)
assert(map.shown == true and map.width == 182 and locked < 4800, "past the widest zoom: the range locks, the map stays")
assert(Underlay.Snap(4800, panel) == locked, "zoom steps see the locked range")
Underlay.Sync(0, panel)
assert(map.shown == false and Underlay.FaceAlpha() == .94, "no usable range: hidden, face opaque")
Underlay.Sync(150, panel)
assert(map.shown == true)

-- In combat, turning it off waits; after combat everything is restored.
lockdown = true
addon.Bus.Emit("PLAYER_REGEN_DISABLED")
settings.vignetteRadarMinimapUnderlay = false
Underlay.Refresh()
assert(Underlay.IsActive() and Underlay.IsPending() and map.parent == panel, "no restore in combat")
lockdown = false
addon.Bus.Emit("PLAYER_REGEN_ENABLED")
assert(not Underlay.IsActive(), "restored after combat")
assert(map.parent == container and #map.points == 1 and map.points[1][2] == container, "parent and points")
assert(map.width == 198 and map.height == 198 and map.scale == .9 and map.level == 5 and map.strata == "LOW")
assert(map.mouse == true and map.wheel == true and map.mask == 186178 and map.shown == true)
assert(zoom == 3 and cvars.minimapZoom == "3" and cvars.minimapInsideZoom == "1", "zoom restored")
assert(cvars.rotateMinimap == "0" and ignoreRotate == false, "rotation restored")
assert(cluster.shown == true and backdrop.alpha == 1 and dbIcon.shown == true and hit.mouse == true,
    "chrome restored")
assert(panel.field.level == 11 and panel.field.background.vertex[4] == .94, "face restored")

-- The hold: Blizzard (or anyone) moving the Minimap is noticed by the hooks
-- and put back once, with the cause in the trace.
settings.vignetteRadarMinimapUnderlay = true
Underlay.Refresh()
Underlay.Sync(150, panel)
assert(Underlay.IsActive() and RecentTrace("borrowed from"), "borrow traced")
local before = refreshes
map:ClearAllPoints()
map:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
Tick()
assert(#map.points == 1 and map.points[1][2] == panel.field, "a SetPoint from outside is re-asserted")
assert(refreshes == before + 1, "outside calls in one frame are one re-assert and one redraw")
assert(RecentTrace("re%-assert #1 after ClearAllPoints"), "re-assert traced with its cause")
clock = clock + 5

-- Regression: an outside SetSize must heal in one re-assert. ApplyHold used to
-- leave the size alone while the render check failed on it, so the underlay
-- fought itself every frame until the cap paused it.
addon.Trace.Clear()
map:SetSize(570, 570)
Underlay.Sync(150, panel)
Tick()
assert(map.width == 182 and map.height == 182, "a SetSize from outside is re-asserted on the next frame")
assert(Underlay.IsActive(), "still holding after an outside SetSize")
do
    local count = 0
    for _, line in ipairs(addon.Trace.Lines()) do
        if line:find("re%-assert #") then count = count + 1 end
    end
    assert(count == 1 and RecentTrace("re%-assert #1 after SetSize"), "exactly one re-assert for one SetSize")
end
for _ = 1, 10 do Underlay.Sync(150, panel); Tick() end
assert(Underlay.IsActive() and not RecentTrace("re%-assert #2"), "no self-fight after the heal")

map:Hide()
Underlay.Sync(150, panel)
Tick()
assert(map.shown == true, "a Hide from outside is undone")
map:SetMaskTexture("Interface\\AddOns\\Other\\square")
Underlay.Sync(150, panel)
Tick()
assert(map.mask == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga", "a mask from outside is undone")
-- Drift the hooks cannot see (a direct re-parent) is caught by the render check.
map.parent = cluster
Underlay.Sync(150, panel)
Tick()
assert(Underlay.IsActive() and map.parent == panel, "a silent re-parent is re-asserted")
assert(RecentTrace("check: parent"), "render check traced")
map.scale = 1.4
Underlay.Sync(150, panel)
Tick()
assert(map.scale == 1, "a silent rescale is re-asserted")
clock = clock + 5

-- Blizzard HUD relayout events re-check the hold once.
map.parent = cluster
addon.Bus.Emit("UI_SCALE_CHANGED")
Tick()
assert(map.parent == panel, "UI_SCALE_CHANGED re-asserts a broken hold")

-- Drift during combat on a protected Minimap waits for the fight to end.
map.IsProtected = function() return true end
lockdown = true
addon.Bus.Emit("PLAYER_REGEN_DISABLED")
map.parent = cluster
Underlay.Sync(150, panel)
Tick()
assert(Underlay.IsActive() and Underlay.IsPending() and map.parent == cluster, "no re-assert in combat")
lockdown = false
addon.Bus.Emit("PLAYER_REGEN_ENABLED")
Underlay.Sync(150, panel)
Tick()
assert(map.parent == panel and not Underlay.IsPending(), "re-asserted after combat")
map.IsProtected = function() return false end

-- A fight: an addon that takes the Minimap back every time is given it after
-- the cap, and the underlay backs off instead of pulling every frame.
clock = clock + 5
local fighting = true
_G.hooksecurefunc(map, "SetParent", function(self, parent)
    if fighting and parent == panel then self.parent = cluster end
end)
map.parent = cluster
for _ = 1, 12 do Underlay.Sync(150, panel); Tick() end
assert(not Underlay.IsActive() and map.parent == cluster, "left to the fighting addon")
assert(RecentTrace("gave back %(fight over the minimap%)") and RecentTrace("backing off 2s"), "give-up traced")
Underlay.Sync(150, panel)
assert(not Underlay.IsActive() and Underlay.IsPaused(), "not grabbed again every frame")
assert(cluster.shown == true and panel.field.background.vertex[4] == .94, "chrome and face restored after a fight")
-- The fighter left the Minimap sized and anchored by us: toggling again must
-- keep the original home for the give-back, not snapshot our own layout.
fighting = false
Underlay.Refresh()
Underlay.Sync(150, panel)
assert(Underlay.IsActive() and map.parent == panel, "toggling tries again")

-- HybridMinimap (cities): stays in Blizzard's BACKGROUND strata, so the
-- backing moves under it; its canvas gives up the mouse; square faces swap
-- in the face's mask. Everything goes back on release.
local hybrid = mock.New("Frame", map)
hybrid.CircleMask = mock.New("MaskTexture", hybrid)
hybrid.CreateMaskTexture = function(self) return mock.New("MaskTexture", self) end
local canvas = mock.New("Frame", hybrid)
canvas.mouse, canvas.wheel, canvas.mask = true, true, hybrid.CircleMask
canvas.IsMouseEnabled = function(self) return self.mouse end
canvas.EnableMouse = function(self, value) self.mouse = value end
canvas.IsMouseWheelEnabled = function(self) return self.wheel end
canvas.EnableMouseWheel = function(self, value) self.wheel = value end
canvas.GetMaskTexture = function(self) return self.mask end
canvas.SetMaskTexture = function(self, value) self.mask = value end
hybrid.MapCanvas = canvas
_G.HybridMinimap = hybrid
local framesBefore = #mock.frames
Underlay.Sync(150, panel)
local under = mock.frames[#mock.frames]
assert(#mock.frames == framesBefore + 1 and under.strata == "BACKGROUND" and under.level == 1 and under.shown,
    "a BACKGROUND-strata backing sits under the hybrid")
assert(under.texture.texture == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga"
    and under.texture.vertex[4] == .94, "hybrid backing painted like the face")
assert(canvas.mouse == false and canvas.wheel == false, "hybrid canvas gives up the mouse")
assert(canvas.mask ~= hybrid.CircleMask and canvas.mask.texture
    == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga", "square face masks the hybrid")
assert(Underlay.ShowsTerrain(), "terrain still counts as shown")
hybrid.shown = false
hybrid.hooks.OnHide(hybrid)
Underlay.Sync(150, panel)
assert(under.shown == false, "hybrid hidden: the panel backing is back")
hybrid.shown = true
hybrid.hooks.OnShow(hybrid)
Underlay.Sync(150, panel)
assert(under.shown == true)
settings.vignetteRadarMinimapUnderlay = false
Underlay.Refresh()
assert(not Underlay.IsActive() and canvas.mouse == true and canvas.wheel == true
    and canvas.mask == hybrid.CircleMask, "hybrid canvas restored")
assert(under.shown == false and map.parent == container and map.width == 198
    and map.points[1][2] == container, "minimap home again, from the snapshot taken before the fight")

-- Duplicate Icons: Radar Wins blanks the minimap's blips and player arrow;
-- Split and Minimap Wins keep the blips and tell the radar what to leave
-- out; every texture goes back when the terrain hides or the map is given back.
do
    local BLANK = "Interface\\AddOns\\Magpie\\Media\\blank.tga"
    local BLIPS, ARROW = "Interface\\Minimap\\ObjectIconsAtlas", "Interface\\Minimap\\MinimapArrow"
    _G.HybridMinimap = nil
    assert(Underlay.IconMode() == "radar", "unset defaults to Radar Wins")
    assert(Underlay.RadarHides() == nil, "no terrain: the radar hides nothing")
    settings.vignetteRadarMinimapUnderlay = true
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    assert(Underlay.ShowsTerrain() and map.blip == BLANK and map.playerArrow == BLANK,
        "Radar Wins blanks blips and the player arrow")
    local hides = assert(Underlay.RadarHides(), "terrain on: the radar gets a hide table")
    assert(not hides.vignettes and not hides.quests and not hides.areaPOIs and not hides.staticPOIs,
        "Radar Wins keeps every radar marker")
    assert(LastTrace():find("player arrow blanked") or LastTrace():find("blips blanked"), "blanking traced")

    settings.vignetteRadarMinimapUnderlayIcons = "split"
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    assert(Underlay.IconMode() == "split" and map.blip == BLIPS and map.playerArrow == BLANK,
        "Split restores the blips, keeps the radar's own center")
    hides = Underlay.RadarHides()
    assert(hides.staticPOIs and not hides.areaPOIs and not hides.vignettes and not hides.quests,
        "Split hides only plain map spots")
    assert(Underlay.RadarHides() == hides, "the hide table is cached between renders")

    settings.vignetteRadarMinimapUnderlayIcons = "minimap"
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    hides = Underlay.RadarHides()
    assert(map.blip == BLIPS and hides.areaPOIs and hides.vignettes and hides.quests,
        "Minimap Wins keeps the blips and hides the shared radar kinds")

    settings.vignetteRadarMinimapUnderlayIcons = "bogus"
    assert(Underlay.IconMode() == "radar", "an unknown value reads as Radar Wins")
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    assert(map.blip == BLANK, "back to Radar Wins: blips blanked again")

    -- Terrain off (no usable range): everything goes back, no hides.
    Underlay.Sync(0, panel)
    assert(not Underlay.ShowsTerrain() and map.blip == BLIPS and map.playerArrow == ARROW
        and Underlay.RadarHides() == nil, "terrain hidden: textures restored, nothing hidden")
    Underlay.Sync(150, panel)
    assert(map.blip == BLANK and map.playerArrow == BLANK and Underlay.RadarHides(), "terrain back: blanked again")

    -- Give-back restores the engine textures exactly.
    settings.vignetteRadarMinimapUnderlay = false
    Underlay.Refresh()
    assert(not Underlay.IsActive() and map.blip == BLIPS and map.playerArrow == ARROW
        and Underlay.RadarHides() == nil, "give-back restores blips and arrow")

    -- A give-up to a fighting addon leaves the layout, never blank icons.
    settings.vignetteRadarMinimapUnderlay = true
    settings.vignetteRadarMinimapUnderlayIcons = "radar"
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    assert(map.blip == BLANK)
    fighting = true
    clock = clock + 5
    map.parent = cluster
    for _ = 1, 12 do Underlay.Sync(150, panel); Tick() end
    assert(not Underlay.IsActive() and map.blip == BLIPS and map.playerArrow == ARROW,
        "textures restored even when the minimap is left to the other addon")
    fighting = false
end

-- An ignored LibDBIcon button (Button Tray ignore list) is left alone by the chrome.
do
    addon.VignetteRadarButtonTray = { CollectsMinimap = function() return false end,
        IsIgnored = function(frame) return frame == dbIcon end }
    dbIcon.shown = true
    clock = clock + 10
    map.parent = container
    settings.vignetteRadarMinimapUnderlay = true
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    assert(Underlay.IsActive() and cluster.shown == false, "borrowed with the chrome hidden")
    assert(dbIcon.shown == true, "ignored button not hidden with the chrome")
    settings.vignetteRadarMinimapUnderlay = false
    Underlay.Refresh()
    addon.VignetteRadarButtonTray = nil
end

local function TraceCount(pattern)
    local count = 0
    for _, line in ipairs(addon.Trace.Lines()) do
        if line:find(pattern) then count = count + 1 end
    end
    return count
end
local function TurnOn()
    settings.vignetteRadarMinimapUnderlay = true
    Underlay.Refresh()
    Underlay.Sync(150, panel)
end
local function TurnOff()
    settings.vignetteRadarMinimapUnderlay = false
    Underlay.Refresh()
end
assert(#said == 1, "two fights so far, one chat line for the whole session")

-- Events with the hold intact never count as re-asserts.
do
    clock = clock + 40
    TurnOn()
    assert(Underlay.IsActive())
    addon.Trace.Clear()
    for _ = 1, 10 do addon.Bus.Emit("UI_SCALE_CHANGED") end
    addon.Bus.Emit("DISPLAY_SIZE_CHANGED")
    addon.Bus.Emit("EDIT_MODE_LAYOUTS_UPDATED")
    addon.Bus.Emit("ZONE_CHANGED_NEW_AREA")
    addon.Bus.Emit("PLAYER_ENTERING_WORLD")
    Tick()
    Tick()
    assert(Underlay.IsActive() and TraceCount("re%-assert") == 0 and TraceCount("backing off") == 0,
        "relayout events with nothing moved are not counted")
end

-- Takeover: an outside SetParent is a hand-over, not a fight. The underlay
-- yields and borrows again when that owner hides.
do
    local hud = mock.New("Frame")
    hud.GetName = function() return "HomeDecorGatherHUD" end
    local holder = mock.New("Frame", hud)
    holder.GetParent = function() return hud end
    local chat = #said
    map:SetParent(holder)
    map:ClearAllPoints()
    map:SetPoint("CENTER", holder, "CENTER", 0, 0)
    map:SetSize(300, 300)
    assert(not Underlay.IsActive() and map.parent == holder, "the new owner keeps the minimap")
    assert(RecentTrace("taken by HomeDecorGatherHUD"), "takeover traced with the owner's name")
    assert(map.width == 300 and #map.points == 1 and map.points[1][2] == holder, "its layout is left alone")
    Tick()
    for _ = 1, 5 do Underlay.Sync(150, panel); Tick() end
    assert(not Underlay.IsActive() and map.parent == holder and Underlay.YieldedTo() == holder,
        "no grab-back while the owner holds it")
    assert(#said == chat, "a hand-over prints nothing")
    holder.shown = false
    holder.hooks.OnHide(holder)
    Tick()
    assert(Underlay.IsActive() and map.parent == panel and map.width == 182, "borrowed again when the owner hides")
    assert(Underlay.YieldedTo() == nil)
    TurnOff()
    assert(map.parent == container and map.width == 198 and map.mouse == true,
        "given back to the real home, not the hidden HUD")
end

-- Stale copy while inactive: another addon restores a copy of our old hold
-- after we gave the Minimap back; it is re-homed.
do
    assert(not Underlay.IsActive())
    map:SetParent(panel)
    map:ClearAllPoints()
    map:SetPoint("CENTER", panel.field, "CENTER", 0, 0)
    map:SetSize(182, 182)
    map:EnableMouse(false)
    Tick()
    assert(map.parent == container and map.width == 198 and map.height == 198 and map.mouse == true
        and map.points[1][2] == container, "a restored copy of our hold is re-homed")
    assert(RecentTrace("re%-homing"), "re-home traced")
end

-- Invalid home: borrowed from a foreign frame that is hidden by give-back
-- time; the Minimap goes to Blizzard's default home instead.
do
    local foreign = mock.New("Frame")
    foreign.GetName = function() return "OtherHolder" end
    map.parent = foreign
    map.points = { { "CENTER", foreign, "CENTER", 0, 0 } }
    TurnOn()
    assert(Underlay.IsActive() and map.parent == panel)
    foreign.shown = false
    TurnOff()
    assert(map.parent == container and map.width == 198 and map.points[1][2] == container and map.mouse == true,
        "a hidden foreign home falls back to MinimapContainer")
    assert(RecentTrace("home OtherHolder invalid"), "invalid home traced")
end

-- Backoff: a fighter that leaves the Minimap in our panel gets it put back
-- home (Release(true)), and the borrow is tried again after the backoff with
-- no toggle.
do
    clock = clock + 40
    TurnOn()
    local sizeFight = true
    _G.hooksecurefunc(map, "SetSize", function(self)
        if sizeFight and self.parent == panel then self.width, self.height = 570, 570 end end)
    map.width = 570
    for _ = 1, 12 do Underlay.Sync(150, panel); Tick() end
    assert(not Underlay.IsActive() and Underlay.IsPaused(), "backed off")
    sizeFight = false
    assert(map.parent == container and map.width == 198, "still in our panel at the give-up: put back home")
    assert(#said == 1, "still one chat line for the session")
    local seconds
    for _, line in ipairs(addon.Trace.Lines()) do seconds = tonumber(line:match("backing off (%d+)s")) or seconds end
    assert(seconds and seconds >= 2 and seconds <= 60, "backoff between 2 and 60 s")
    Tick()
    Underlay.Sync(150, panel)
    assert(not Underlay.IsActive(), "no borrow before the backoff ends")
    clock = clock + seconds + 1
    Tick()
    assert(Underlay.IsActive() and map.parent == panel, "borrowed again after the backoff, no toggle")
end

-- Combat give-up: one chat line at most, no per-frame spam, a clean state after.
do
    clock = clock + 5
    lockdown = true
    addon.Bus.Emit("PLAYER_REGEN_DISABLED")
    fighting = true
    map.parent = cluster
    for _ = 1, 9 do Underlay.Sync(150, panel); Tick() end
    assert(Underlay.IsActive() and Underlay.IsPending(), "give-up waits for combat")
    local reasserted = TraceCount("re%-assert #")
    for _ = 1, 5 do Underlay.Sync(150, panel); Tick() end
    assert(TraceCount("re%-assert #") == reasserted, "no more re-asserts once giving up")
    assert(#said <= 1, "no chat spam in combat")
    lockdown = false
    addon.Bus.Emit("PLAYER_REGEN_ENABLED")
    Tick()
    assert(not Underlay.IsActive() and not Underlay.IsPending() and Underlay.IsPaused() and map.parent == cluster,
        "cleanly released after combat")
    fighting = false
end

-- Edit Mode: the Minimap goes home while it is open and comes back after.
do
    TurnOn()
    assert(Underlay.IsActive())
    _G.EventRegistry:TriggerEvent("EditMode.Enter")
    assert(not Underlay.IsActive() and map.parent == container and cluster.shown == true, "home during Edit Mode")
    Underlay.Sync(150, panel)
    Tick()
    assert(not Underlay.IsActive(), "no borrow while Edit Mode is open")
    _G.EventRegistry:TriggerEvent("EditMode.Exit")
    Tick()
    assert(Underlay.IsActive() and map.parent == panel, "borrowed again after Edit Mode")
    TurnOff()
    assert(map.parent == container)
end

-- W2UI's minimap layout and hover zoom pause while borrowed, re-run on give-back.
do
    TurnOff()
    local calls = { layout = 0, hover = 0 }
    _G.W2UI = { Modules = { Minimap = {
        ApplyLayout = function() calls.layout = calls.layout + 1 end,
        ApplyHoverZoomScale = function() calls.hover = calls.hover + 1 end,
    } } }
    local module = _G.W2UI.Modules.Minimap
    TurnOn()
    Underlay.Sync(150, panel)
    assert(Underlay.IsActive(), "borrowed with W2UI loaded")
    module:ApplyLayout()
    module:ApplyHoverZoomScale(1.2)
    assert(calls.layout == 0 and calls.hover == 0, "W2UI writers paused while the underlay holds the map")
    TurnOff()
    assert(calls.layout == 1, "W2UI layout re-runs once on give-back")
    module:ApplyHoverZoomScale(1.2)
    assert(calls.hover == 1, "W2UI hover zoom works again after give-back")
    _G.W2UI = nil
end

-- Magpie's player dot wins: a face-colored disc covers the engine's arrow while terrain shows.
do
    TurnOff()
    TurnOn()
    settings.vignetteRadarMinimapUnderlayIcons = "radar"
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    local cover = Underlay.ArrowCover()
    assert(cover and cover.shown ~= false and cover:IsShown(), "the arrow cover shows over the terrain")
    settings.vignetteRadarMinimapUnderlayIcons = "minimap"
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    assert(not cover:IsShown(), "Minimap Wins keeps the engine arrow")
    settings.vignetteRadarMinimapUnderlayIcons = "radar"
    Underlay.Refresh()
    Underlay.Sync(150, panel)
    assert(cover:IsShown(), "back to Radar Wins: covered again")
    TurnOff()
    assert(not cover:IsShown(), "the cover goes away with the underlay")
end

print("minimap_underlay_test ok")
