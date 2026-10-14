local dataPath = arg[1] or "UI/ConstellationData.lua"
local uiPath = arg[2] or "UI/Constellation.lua"
local settingsPath = arg[3] or "UI/ConstellationSettings.lua"

local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/SpatialProjection.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
local Focus = addon.VignetteRadarFocus
-- The radar's focused target, set the way the target list sets it.
local function SetPickerFocus(key)
    if key then Focus.Select({ type = "target", key = key }, { project = false })
    else Focus.Clear({ project = false }) end
end

local settings = {
    vignetteRadarEnabled = false,
    vignetteRadarConstellationEnabled = false,
    vignetteRadarConstellationSourceMode = "mixed",
    vignetteRadarConstellationGuidance = true,
    vignetteRadarConstellationReducedMotion = false,
    vignetteRadarConstellationInteractModifier = "ctrl",
    vignetteRadarConstellationCenterArrow = true,
    vignetteRadarConstellationHeadingLine = true,
    vignetteRadarConstellationCenterOpacity = .72,
    vignetteRadarConstellationHeadingLength = .24,
    vignetteRadarConstellationShowRings = true,
    vignetteRadarConstellationShowSphere = true,
    vignetteRadarConstellationShowBases = true,
    vignetteRadarConstellationShowReadout = true,
    vignetteRadarConstellationRingOpacity = .75,
    vignetteRadarConstellationSphereOpacity = .75,
    vignetteRadarConstellationTrailOpacity = .75,
    vignetteRadarConstellationIconSize = 32,
    vignetteRadarConstellationSize = 520,
    vignetteRadarConstellationOpacity = .75,
    vignetteRadarConstellationOffsetY = -.05,
    vignetteRadarConstellationMaxPoints = 36,
    vignetteRadarRange = 450,
    vignetteRadarNorthUp = false,
    vignetteRadarShapes = true,
    vignetteRadarPOISource = "Test Pack",
    vignetteRadarPOITypes = { mob = true, treasure = true, entrance = true },
}
local player = { mapID = 1, instanceID = 7, worldX = 0, worldY = 0,
    facing = 0, headingAvailable = true }
local targets, notes = {}, {}
local invalidations, radarRefreshes, controlRefreshes = 0, 0, 0

addon.GetSettings = function() return settings end
addon.ValidateSettings = addon.GetSettings
addon.VignetteRadarAPI = {
    GetSpatialSources = function()
        -- The radar publishes its lists before every snapshot.
        addon.VignetteRadarPoints.Publish({ mapID = 1, player = player, targets = targets, notes = notes })
        return 1,
            function() return true end,
            function() return false end,
            function() return false end,
            function() return 0 end
    end,
    GetPlayerSnapshot = function()
        local copy = {}
        for key, value in pairs(player) do copy[key] = value end
        return copy
    end,
    InvalidateSpatialSnapshot = function()
        invalidations = invalidations + 1
        addon._spatialGeneration = (addon._spatialGeneration or 0) + 1
    end,
    Refresh = function() radarRefreshes = radarRefreshes + 1 end,
    RefreshConstellationControl = function() controlRefreshes = controlRefreshes + 1 end,
}

assert(loadfile(dataPath))("VignetteRadar", addon)
local Data = assert(addon.VignetteRadarConstellationData)

local savedAmber = { key = "saved-amber", kind = "treasure", name = "Amber Cache",
    worldX = 26, worldY = 0, instanceID = 7, mapID = 1, source = "Test Pack" }
local liveAmber = { key = "live-amber", category = "treasure", name = "Amber Cache",
    worldX = 25, worldY = 0, instanceID = 7, mapID = 1 }

targets, notes = { liveAmber }, { savedAmber }
addon._spatialGeneration = 1
local pack = Data.GetSnapshot("pack")
assert(#pack.points == 1 and pack.points[1].evidence == "saved"
    and pack.points[1].key == "saved-amber",
    "Map Pack Only must retain its saved point while a matching live detection exists")
local live = Data.GetSnapshot("live")
assert(#live.points == 1 and live.points[1].evidence == "live"
    and live.points[1].key == "live-amber" and live.points[1].targetRef == liveAmber,
    "Live Only must never pull a saved pack marker into its view")

local mixed = Data.GetSnapshot("mixed")
assert(#mixed.points == 1 and mixed.points[1].evidence == "live"
    and mixed.points[1].key == "saved-amber" and mixed.points[1].worldX == 25,
    "Mixed must draw one live-upgraded marker while retaining the saved display identity")

SetPickerFocus("live-amber")
addon.VignetteRadarWorldFocus = { GetConstellationPath = function()
    return { destinationKey = "some-other-point", hasExplicitSteps = false, points = {} }
end }
addon._spatialGeneration = 11
assert(Data.GetSnapshot("mixed").points[1].focused,
    "a radar-focused live item must become the highlighted mixed marker immediately")
assert(Data.GetSnapshot("pack").points[1].focused,
    "Map Pack Only must highlight a confidently matched saved counterpart")
SetPickerFocus(nil)
addon.VignetteRadarWorldFocus = nil

targets = {}
addon._spatialGeneration = 2
mixed = Data.GetSnapshot("mixed")
assert(#mixed.points == 1 and mixed.points[1].evidence == "saved"
    and mixed.points[1].key == "saved-amber" and mixed.points[1].noteRef == savedAmber,
    "Mixed must restore an eligible saved point when the live detection disappears")

local savedDistinct = { key = "saved-distinct", kind = "treasure", name = "Ancient Cache",
    worldX = 33, worldY = 0, instanceID = 7, mapID = 1 }
local liveDistinct = { key = "live-distinct", category = "treasure", name = "Other Cache",
    worldX = 29, worldY = 0, instanceID = 7, mapID = 1 }
targets, notes = { liveDistinct }, { savedDistinct }
addon._spatialGeneration = 3
mixed = Data.GetSnapshot("mixed")
assert(#mixed.points == 2,
    "nearby treasure records with different safe identities must not merge in Mixed")

targets, notes = { { key = "expired", category = "rare", stale = true,
    name = "Expired", worldX = 40, worldY = 0, instanceID = 7 } }, {}
addon._spatialGeneration = 4
assert(#Data.GetSnapshot("live").points == 0,
    "last-seen or expired vignettes must never count as live detections")
settings.vignetteRadarPOISource = "none"
assert(Data.GetSnapshot("pack").reason == "No Map Pack Selected",
    "Map Pack Only must say when no source is selected")
settings.vignetteRadarPOISource = "Test Pack"

local objects, lines = {}, {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetFrameLevel(value) self.level = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:RegisterForClicks(...) self.clicks = { ... } end
function methods:RegisterEvent(event)
    self.events = self.events or {}
    self.events[event] = true
end
function methods:SetScript(name, callback)
    self.scripts = self.scripts or {}
    self.scripts[name] = callback
end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetThickness(value) self.thickness = value end
function methods:SetStartPoint(...) self.startPoint = { ... } end
function methods:SetEndPoint(...) self.endPoint = { ... } end
function methods:SetText(value) self.text = value end
function methods:SetFont(...) self.font = { ... } end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetJustifyV(value) self.justifyV = value end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorder = { ... } end
function methods:SetSelected(value) self.selected = value == true end
function methods:SetChecked(value) self.checked = value == true end
function methods:GetChecked() return self.checked end
function methods:LockHighlight() self.selected = true end
function methods:UnlockHighlight() self.selected = false end
function methods:SetEnabled(value) self.enabled = value == true end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value == true end
function methods:IsShown() return self.shown == true end
function methods:CreateTexture()
    return setmetatable({ shown = true, parent = self }, { __index = methods })
end
function methods:CreateFontString()
    return setmetatable({ shown = true, parent = self }, { __index = methods })
end
function methods:CreateLine(_, layer)
    local line = setmetatable({ shown = true, parent = self, layer = layer }, { __index = methods })
    lines[#lines + 1] = line
    return line
end

function CreateFrame(kind, name, parent, template)
    local object = setmetatable({ kind = kind, name = name, parent = parent, shown = true },
        { __index = methods })
    if template == "VignetteRadarConstellationTrailTemplate" then
        object.Guide = object:CreateLine(nil, "ARTWORK")
        object.Fill = object:CreateLine(nil, "ARTWORK")
        object.Scroll = { playing = false, plays = 0 }
        function object.Scroll:IsPlaying() return self.playing end
        function object.Scroll:Play() self.playing = true; self.plays = self.plays + 1 end
        function object.Scroll:Stop() self.playing = false end
    end
    if name then _G[name] = object end
    objects[#objects + 1] = object
    return object
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1600, 900)
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local uiError
UIErrorsFrame = { AddMessage = function(_, message) uiError = message end }
local ctrlHeld, shiftHeld, altHeld = false, false, false
function IsControlKeyDown() return ctrlHeld end
function IsShiftKeyDown() return shiftHeld end
function IsAltKeyDown() return altHeld end
local fakeTime = 0
function GetTime() return fakeTime end
GameTooltip = setmetatable({ lines = {} }, { __index = {
    SetOwner = function(self, owner) self.owner = owner end,
    SetText = function(self, value) self.title = value end,
    AddLine = function(self, value) self.lines[#self.lines + 1] = value end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
} })
local fontStyle = {}
assert(loadfile("UI/Style.lua"))("VignetteRadar", fontStyle)
addon.VignetteRadarStyle = { SetFont = fontStyle.VignetteRadarStyle.SetFont, Color = function(slot)
    return slot == "treasure" and 1, .72, .2 or .2, .78, 1
end }
addon.VignetteRadarControls = { Button = function(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetText(label)
    button:SetSize(width, height)
    return button
end, Checkbox = function(parent)
    local box = CreateFrame("CheckButton", nil, parent)
    box:SetSize(26, 26)
    return box
end }

local uiSnapshot
addon.VignetteRadarAPI.GetSpatialSnapshot = function(mode)
    return uiSnapshot or Data.GetSnapshot(mode)
end

assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile(uiPath))("VignetteRadar", addon)
local HUD = assert(addon.VignetteRadarConstellation)
assert(loadfile(settingsPath))("VignetteRadar", addon)

assert(not HUD.SetEnabled(true) and uiError == "Enable Radar First",
    "the constellation toggle must refuse to enable detection while the radar is off")
settings.vignetteRadarEnabled = true
assert(HUD.SetEnabled(true) and settings.vignetteRadarConstellationEnabled,
    "enabling the HUD must save the preference once the radar is enabled")
assert(radarRefreshes > 0 and invalidations > 0 and controlRefreshes > 0,
    "a HUD toggle must invalidate the snapshot and refresh its existing controls")
VignetteRadar_ToggleConstellation()
assert(not settings.vignetteRadarConstellationEnabled,
    "the binding entry point must share the same toggle state")
VignetteRadar_ToggleConstellation()
assert(settings.vignetteRadarConstellationEnabled,
    "the binding entry point must restore the HUD")

HUD.ToggleMenu(UIParent)
local menu = assert(_G.VignetteRadarConstellationMenu)
assert(menu:IsShown() and #menu.modes == 3 and menu.modes[3].value == "mixed"
    and menu.pages.Show and menu.pages.Looks and menu.pages.Layers
    and menu.pages.Direction,
    "right-clicking the orbit must open the dedicated settings popup")
for _, object in ipairs(objects) do
    local parent = object.parent
    if parent == menu.pages.Show or parent == menu.pages.Looks
        or parent == menu.pages.Layers or parent == menu.pages.Direction then
        local anchor = object.point
        if anchor and anchor[1] == "TOPLEFT" then
            local x, y = anchor[4], anchor[5]
            assert(x >= 16 and x + (object.width or 0) <= 390
                and y <= 0 and y - (object.height or 0) >= -406,
                "all revealed popup controls and explanations need a visible gutter")
        end
    end
end
menu.modes[2].button.scripts.OnClick(menu.modes[2].button)
assert(settings.vignetteRadarConstellationSourceMode == "pack" and menu:IsShown(),
    "changing Map Pack Only must keep the popup open for further adjustments")
assert(menu.modeHelp.text:find("Possible places", 1, true),
    "the popup must explain what saved map-pack spots mean")
assert(#menu.modifiers == 4 and menu.modifiers[1].value == "ctrl",
    "the popup must explain and configure the icon inspection key")
menu.modifiers[2].button.scripts.OnClick(menu.modifiers[2].button)
assert(settings.vignetteRadarConstellationInteractModifier == "shift",
    "the popup must save a chosen interaction key")
menu.modifiers[1].button.scripts.OnClick(menu.modifiers[1].button)
menu:SelectTab("Looks")
assert(menu.pages.Looks:IsShown() and not menu.pages.Show:IsShown(),
    "the Looks tab must reveal only its own controls")
local sizeStepper
for _, stepper in ipairs(menu.steppers) do
    if stepper.key == "vignetteRadarConstellationIconSize" then sizeStepper = stepper; break end
end
assert(sizeStepper, "icon size must be configurable directly from the orbit popup")
sizeStepper.plus.scripts.OnClick(sizeStepper.plus)
assert(settings.vignetteRadarConstellationIconSize == 36,
    "the icon-size control must make hard-to-see symbols larger")
menu:SelectTab("Layers")
local ringToggle, baseToggle, readoutToggle, ringVisibility
for _, toggle in ipairs(menu.toggles) do
    if toggle.key == "vignetteRadarConstellationShowRings" then ringToggle = toggle end
    if toggle.key == "vignetteRadarConstellationShowBases" then baseToggle = toggle end
    if toggle.key == "vignetteRadarConstellationShowReadout" then readoutToggle = toggle end
end
for _, stepper in ipairs(menu.steppers) do
    if stepper.key == "vignetteRadarConstellationRingOpacity" then ringVisibility = stepper end
end
assert(ringToggle and baseToggle and readoutToggle and ringVisibility,
    "the Layers tab must expose the globe, marker, and readout controls")
ringVisibility.plus.scripts.OnClick(ringVisibility.plus)
assert(settings.vignetteRadarConstellationRingOpacity == .9,
    "ring transparency must be independent of icon transparency")
ringVisibility.minus.scripts.OnClick(ringVisibility.minus)
menu:SelectTab("Direction")
local arrowToggle
for _, toggle in ipairs(menu.toggles) do
    if toggle.key == "vignetteRadarConstellationCenterArrow" then arrowToggle = toggle; break end
end
assert(arrowToggle, "the center steeple must have a plain-language toggle")
arrowToggle.button.scripts.OnClick(arrowToggle.button)
assert(settings.vignetteRadarConstellationCenterArrow == false,
    "the center-steeple toggle must update the HUD preference")
arrowToggle.button.scripts.OnClick(arrowToggle.button)
assert(HUD.SetSourceMode("mixed") and not HUD.SetSourceMode("invalid"),
    "the HUD must accept only its three explicit source modes")
targets, notes = { liveAmber }, { savedAmber }
SetPickerFocus("live-amber")
local beforeFocusChange = invalidations
HUD.FocusChanged()
assert(invalidations == beforeFocusChange + 1,
    "changing radar focus must invalidate and redraw the HUD snapshot at once")
local focusFrame = assert(_G.VignetteRadarConstellationFrame)
local focusVisible
for _, object in ipairs(objects) do
    if object.parent == focusFrame and object.glyph and object.pointData
        and object.pointData.focused and object.halo:IsShown() then focusVisible = true; break end
end
assert(focusVisible, "the focused radar item must be obvious in the constellation")
SetPickerFocus(nil)
HUD.FocusChanged()

local focusedStep, selectedLive, selectedNote
addon.VignetteRadarWorldFocus = {
    GetFocusedStep = function() return focusedStep end,
    GetConstellationPath = function()
        return focusedStep and { destinationKey = focusedStep.key,
            hasExplicitSteps = false, points = {} } or nil
    end,
    SelectTarget = function(target)
        selectedLive = target
        focusedStep = { key = target.key }
        return true
    end,
    SelectNote = function(note)
        selectedNote = note
        focusedStep = { key = note.key }
        return true
    end,
}
local modifierEvent
for _, object in ipairs(objects) do
    if object.events and object.events.MODIFIER_STATE_CHANGED then modifierEvent = object end
end
assert(modifierEvent, "modifier changes must toggle icon interaction without polling")
local liveMarker
for _, object in ipairs(objects) do
    if object.parent == focusFrame and object.pointData
        and object.pointData.targetRef == liveAmber then liveMarker = object; break end
end
assert(liveMarker and not liveMarker.hit.mouseEnabled and not liveMarker.hit:IsShown(),
    "icon hit targets must be inactive until the configured key is held")
ctrlHeld = true
modifierEvent.scripts.OnEvent(modifierEvent, "MODIFIER_STATE_CHANGED")
assert(liveMarker.hit.mouseEnabled and liveMarker.hit:IsShown(),
    "holding Ctrl must expose the icon hit target")
liveMarker.hit.scripts.OnEnter(liveMarker.hit)
assert(GameTooltip.shown and GameTooltip.title == "Amber Cache",
    "hovering with the key held must show the object's name in a tooltip")
liveMarker.hit.scripts.OnClick(liveMarker.hit)
assert(selectedLive == liveAmber and Focus.GetTargetKey() == "live-amber"
    and #focusFrame.trailLines > 0 and focusFrame.trailLines[1].Scroll:IsPlaying(),
    "clicking a live icon must focus it and draw guidance")
HUD.SetSourceMode("pack")
local savedMarker
for _, object in ipairs(objects) do
    if object.parent == focusFrame and object.pointData
        and object.pointData.noteRef == savedAmber then savedMarker = object; break end
end
assert(savedMarker, "a saved icon must retain its map-note selection reference")
savedMarker.hit.scripts.OnClick(savedMarker.hit)
assert(selectedNote == savedAmber and Focus.GetTargetKey() == nil
    and savedMarker.pointData.focused,
    "clicking a saved icon must focus its map note even after a live focus")
ctrlHeld = false
modifierEvent.scripts.OnEvent(modifierEvent, "MODIFIER_STATE_CHANGED")
assert(not savedMarker.hit.mouseEnabled and not GameTooltip.shown,
    "releasing the key must restore click-through behavior and hide the tooltip")
HUD.SetSourceMode("mixed")
focusedStep = nil
HUD.FocusChanged()

uiSnapshot = { generation = 40, mapID = 1, coordinateSpaceID = 7,
    effectiveRange = 450, points = {}, totalEligibleCount = 50,
    focusPath = { destinationKey = "point-1", hasExplicitSteps = true, truncated = false, points = {} } }
for index = 1, 50 do
    uiSnapshot.points[index] = { key = "point-" .. index, name = "Point " .. index,
        category = index == 1 and "treasure" or "rare", evidence = "live",
        worldX = index == 1 and 400 or (index % 18 - 9) * 20,
        worldY = (index % 9 - 4) * 20, focused = index == 1 }
end
for index = 1, 34 do
    uiSnapshot.focusPath.points[index] = { instanceID = 7,
        worldX = index % 2 == 0 and 400 or -400, worldY = 0 }
end
HUD.Refresh()
local hudFrame = assert(_G.VignetteRadarConstellationFrame)
assert(hudFrame.headingLine:IsShown() and hudFrame.steeple[1]:IsShown()
    and hudFrame.steeple[2]:IsShown(),
    "the player dot must have a visible steeple and facing line by default")
local function VisibleGridLines()
    local count = 0
    for _, line in ipairs(lines) do
        if line.parent == hudFrame and line.layer == "BACKGROUND" and line:IsShown() then
            count = count + 1
        end
    end
    return count
end
local fullGrid = VisibleGridLines()
settings.vignetteRadarConstellationShowRings = false
HUD.Refresh()
assert(VisibleGridLines() < fullGrid and VisibleGridLines() > 0,
    "hiding range rings must leave the decorative globe visible")
settings.vignetteRadarConstellationShowSphere = false
HUD.Refresh()
assert(VisibleGridLines() == 0,
    "turning off both grid layers must hide every globe line")
settings.vignetteRadarConstellationShowRings = true
settings.vignetteRadarConstellationShowSphere = true
HUD.Refresh()
assert(VisibleGridLines() == fullGrid,
    "restoring the layers must reuse the original bounded grid")
settings.vignetteRadarConstellationHeadingLine = false
HUD.Refresh()
assert(not hudFrame.headingLine:IsShown() and hudFrame.steeple[1]:IsShown(),
    "the facing line must turn off independently of the steeple")
settings.vignetteRadarConstellationHeadingLine = true
HUD.Refresh()
local markerCount = 0
for _, object in ipairs(objects) do
    if object.parent == hudFrame and object.glyph then markerCount = markerCount + 1 end
end
assert(markerCount == 36,
    "the HUD must not allocate marker frames beyond its selected 36-point maximum")
assert(#hudFrame.trailLines <= 35,
    "the explicit guidance path must retain a bounded number of GPU-animated segments")
assert(hudFrame:IsShown() and hudFrame.scripts.OnUpdate,
    "an enabled HUD must render through its bounded update callback")
local leadingSegment = assert(hudFrame.trailLines[1])
assert(leadingSegment:IsShown() and leadingSegment.Scroll:IsPlaying()
    and leadingSegment.Fill.texture
        == "Interface\\AddOns\\Magpie\\Media\\constellation-trail.tga",
    "a selected point must use the independent scrolling ant-trail texture")
local initialPlays = leadingSegment.Scroll.plays
fakeTime = fakeTime + .2
hudFrame.scripts.OnUpdate(hudFrame, .2)
assert(leadingSegment.Scroll:IsPlaying() and leadingSegment.Scroll.plays == initialPlays,
    "the game animation must keep running across HUD redraws instead of restarting")
local trailAlpha = leadingSegment.Fill.vertexColor[4]
settings.vignetteRadarConstellationTrailOpacity = .25
HUD.Refresh()
assert(leadingSegment.Fill.vertexColor[4] < trailAlpha,
    "trail visibility must change independently of the object icons")
settings.vignetteRadarConstellationTrailOpacity = .75
HUD.Refresh()
assert(hudFrame.trailLines[1].Fill.texCoord[5]
    == hudFrame.trailLines[2].Fill.texCoord[1],
    "texture phase must flow continuously across explicit waypoint segments")
settings.vignetteRadarConstellationReducedMotion = true
HUD.Refresh()
assert(not leadingSegment.Scroll:IsPlaying(),
    "reduced motion must stop the trail animation")
settings.vignetteRadarConstellationReducedMotion = false
HUD.Refresh()
assert(leadingSegment.Scroll:IsPlaying(),
    "disabling reduced motion must resume the trail animation")
local focusedMarker
for _, object in ipairs(objects) do
    if object.parent == hudFrame and object.glyph and object.pointData
        and object.pointData.focused then focusedMarker = object; break end
end
assert(focusedMarker and focusedMarker.shadow and focusedMarker.halo:IsShown(),
    "a focused radar item must be brighter and outlined in the HUD")
player.facing = math.pi / 2
hudFrame.scripts.OnUpdate(hudFrame, .04)
assert(focusedMarker.point[4] > 0 and focusedMarker.point[4] < 195,
    "a quarter-turn must ease marker movement instead of snapping it in one frame")
player.facing = 0

UIParent:SetSize(800, 600)
HUD.Refresh()
assert(hudFrame.width <= 560 and hudFrame.height <= 432
    and hudFrame.point[1] == "CENTER" and math.abs(hudFrame.point[5]) <= 68,
    "the full sphere and controls must fit inside an 800x600 viewport")
local centerY = 300 + hudFrame.point[5]
assert(400 - hudFrame.width / 2 >= 16 and 400 + hudFrame.width / 2 <= 784
    and centerY - hudFrame.height / 2 >= 16
    and centerY + hudFrame.height / 2 <= 584,
    "the HUD frame must retain a visible 16-unit screen gutter")
local firstMarker
for _, object in ipairs(objects) do
    if object.parent == hudFrame and object.glyph then firstMarker = object; break end
end
assert(firstMarker and firstMarker.base and firstMarker.stem and firstMarker.halo,
    "every point needs a mapped base, short stem, and selected halo")
settings.vignetteRadarConstellationShowBases = false
HUD.Refresh()
assert(not firstMarker.base:IsShown() and not firstMarker.stem:IsShown()
    and firstMarker.glyph:IsShown(),
    "hiding bases must keep object symbols visible")
settings.vignetteRadarConstellationShowBases = true
settings.vignetteRadarConstellationShowReadout = false
HUD.Refresh()
assert(firstMarker.base:IsShown() and not hudFrame.mode:IsShown()
    and not hudFrame.status:IsShown(),
    "readout visibility must be independent of bases and symbols")
settings.vignetteRadarConstellationShowReadout = true
HUD.Refresh()
assert(firstMarker.glyph.point[5] == 13 and firstMarker.base.point[5] == 0,
    "the base must sit directly beneath the icon instead of floating far below it")
assert(firstMarker.label == nil, "object names must not clutter the constellation")
assert(firstMarker.glyph.texCoord[1] > 2 / 1024
    and firstMarker.glyph.texCoord[2] < 3 * 64 / 1024,
    "treasure glyph UVs must use the power-of-two runtime atlas")

local modeSetText, modeWrites = hudFrame.mode.SetText, 0
hudFrame.mode.SetText = function(self, value) modeWrites = modeWrites + 1; modeSetText(self, value) end
fakeTime = fakeTime + .2
hudFrame.scripts.OnUpdate(hudFrame, .2)
fakeTime = fakeTime + .2
hudFrame.scripts.OnUpdate(hudFrame, .2)
assert(modeWrites == 0, "an unchanged readout must not be re-sent to the font string every frame")
settings.vignetteRadarRange = (settings.vignetteRadarRange or 0) + 50
fakeTime = fakeTime + .2
hudFrame.scripts.OnUpdate(hudFrame, .2)
assert(modeWrites == 1 and hudFrame.mode.text:find(tostring(settings.vignetteRadarRange), 1, true),
    "a changed readout must still update the font string")
settings.vignetteRadarRange = settings.vignetteRadarRange - 50
hudFrame.mode.SetText = nil

local finished, reported = 0, nil
local savedBudget, savedHandler = addon.VignetteRadarLayerBudget, _G.geterrorhandler
local savedSpatial = addon.VignetteRadarAPI.GetSpatialSnapshot
addon.VignetteRadarLayerBudget = {
    Begin = function() return "token" end,
    Finish = function(token) if token == "token" then finished = finished + 1 end end,
}
_G.geterrorhandler = function() return function(err) reported = err end end
addon.VignetteRadarAPI.GetSpatialSnapshot = function() error("render boom") end
fakeTime = fakeTime + .2
hudFrame.scripts.OnUpdate(hudFrame, .2)
assert(finished == 1 and reported and tostring(reported):find("render boom", 1, true),
    "a Render error must still finish the layer budget and reach the error handler")
addon.VignetteRadarAPI.GetSpatialSnapshot = savedSpatial
addon.VignetteRadarLayerBudget, _G.geterrorhandler = savedBudget, savedHandler

assert(HUD.SetEnabled(false) == false and not hudFrame:IsShown()
    and hudFrame.scripts.OnUpdate == nil,
    "turning the HUD off must hide it and detach its update work immediately")

print("constellation data views, controls, bounds, and lifecycle tests passed")
