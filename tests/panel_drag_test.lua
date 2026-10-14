-- luacheck: no global
-- Panels near the radar (UI/Tray.lua RegisterPanel) under a geometry mock
-- that resolves anchors, scales and parents the way the client does, so the
-- drag causes the simple mocks hide can be checked: StartMoving on a frame
-- anchored to another (scaled) region, a hidden or clipping parent, strata
-- after leaving the dock, user-placed state, UIParent units at a UI scale,
-- see-through panels, re-places mid-drag, a drag that never got its drop,
-- the off-screen safety net, saved-spot migration and the round-radar arc.

local UI_SCALE, SCREEN_W, SCREEN_H = .64, 2000, 1000
local unpack = table.unpack or unpack

local methods, created = {}, {}
local function Region(kind, parent)
    local region = setmetatable({ kind = kind, parent = parent, shown = true, scale = 1, width = 0, height = 0,
        strata = parent and parent.strata or "MEDIUM", level = 1, alpha = 1, scripts = {}, hooks = {} },
        { __index = function(_, key)
            if methods[key] then return methods[key] end
            if type(key) == "string" and key:match("^%u") then return function() end end
        end })
    created[#created + 1] = region
    return region
end

function CreateFrame(kind, name, parent)
    local frame = Region(kind, parent or nil)
    if name then _G[name] = frame end
    return frame
end
function methods:CreateTexture() return Region("Texture", self) end
function methods:CreateFontString() return Region("FontString", self) end
function methods:CreateLine() return Region("Line", self) end

function methods:GetEffectiveScale()
    if self == UIParent then return UI_SCALE end
    if self.kind == "Texture" or self.kind == "FontString" then return self.parent:GetEffectiveScale() end
    return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
-- A region sized by SetAllPoints takes its size from the anchor, as in game.
local Physical
function methods:GetWidth()
    if self.point and self.point[1] == "ALL" then
        local _, _, w = Physical(self); return w / self:GetEffectiveScale()
    end
    return self.width
end
function methods:GetHeight()
    if self.point and self.point[1] == "ALL" then
        local _, _, _, h = Physical(self); return h / self:GetEffectiveScale()
    end
    return self.height
end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then relative, relativePoint, x, y = nil, point, relative, relativePoint end
    self.point = { point, relative or self.parent, relativePoint or point, x or 0, y or 0 }
end
function methods:SetAllPoints(relative) self.point = { "ALL", relative or self.parent } end
function methods:ClearAllPoints() self.point = nil end
function methods:GetPoint() local p = self.point; if p then return p[1], p[2], p[3], p[4], p[5] end end

local FX = { TOPLEFT = 0, TOP = .5, TOPRIGHT = 1, LEFT = 0, CENTER = .5, RIGHT = 1, BOTTOMLEFT = 0,
    BOTTOM = .5, BOTTOMRIGHT = 1 }
local FY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = .5, CENTER = .5, RIGHT = .5, BOTTOMLEFT = 0,
    BOTTOM = 0, BOTTOMRIGHT = 0 }
-- Physical rect: left, bottom, width, height.
function Physical(region)
    if region == UIParent then return 0, 0, SCREEN_W * UI_SCALE, SCREEN_H * UI_SCALE end
    local scale = region:GetEffectiveScale()
    local point = region.point
    if not point then return nil end
    local rl, rb, rw, rh = Physical(point[2] or UIParent)
    if not rl then return nil end
    if point[1] == "ALL" then return rl, rb, rw, rh end
    local w, h = region.width * scale, region.height * scale
    local ax, ay = rl + rw * FX[point[3]], rb + rh * FY[point[3]]
    local px, py = ax + point[4] * scale, ay + point[5] * scale
    return px - w * FX[point[1]], py - h * FY[point[1]], w, h
end
function methods:GetLeft() local l = Physical(self); return l and l / self:GetEffectiveScale() end
function methods:GetBottom() local _, b = Physical(self); return b and b / self:GetEffectiveScale() end
function methods:GetRight()
    local l, _, w = Physical(self); return l and (l + w) / self:GetEffectiveScale()
end
function methods:GetTop()
    local _, b, _, h = Physical(self); return b and (b + h) / self:GetEffectiveScale()
end

function methods:Show()
    if self.shown then return end
    self.shown = true
end
function methods:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
    for _, hook in ipairs(self.hooks.OnHide or {}) do hook(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible()
    if not self.shown then return false end
    if self.parent and self.parent ~= UIParent then return self.parent:IsVisible() end
    return true
end
function methods:SetParent(parent) self.parent = parent end
function methods:GetParent() return self.parent end
function methods:SetFrameStrata(value) self.strata = value end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameLevel() return self.level end
function methods:Raise() self.raised = true end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
end
function methods:SetMovable(value) self.movable = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:SetDontSavePosition(value) self.dontSave = value end
function methods:SetUserPlaced(value) self.userPlaced = value end
function methods:RegisterForDrag(value) self.dragButton = value end
function methods:EnableMouse(value) self.mouse = value end
-- Like the client: StartMoving marks the frame user-placed, and the frame
-- then follows the cursor. foreignAnchor records a start from an anchor that
-- is not UIParent (the case that jumps in game).
function methods:StartMoving()
    assert(self.movable, "StartMoving needs a movable frame")
    self.moving, self.userPlaced = true, true
    local relative = self.point and self.point[2]
    self.foreignAnchor = relative ~= UIParent
    self.strataAtStart, self.parentAtStart = self.strata, self.parent
end
-- Moves a moving frame by dx, dy UIParent units (the cursor), re-anchoring
-- it to UIParent's bottom-left the way the client does.
local function Drag(frame, dx, dy)
    assert(frame.moving, "drag needs StartMoving")
    local l, b = Physical(frame)
    local scale = frame:GetEffectiveScale()
    frame.point = { "BOTTOMLEFT", UIParent, "BOTTOMLEFT", (l + dx * UI_SCALE) / scale, (b + dy * UI_SCALE) / scale }
end
function methods:StopMovingOrSizing() self.moving = false end

UIParent = Region("Frame")
UIParent.width, UIParent.height = SCREEN_W, SCREEN_H
UIParent.point = { "ALL" }
GetTime = function() return 100 end
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local mouseDown = true
IsMouseButtonDown = function() return mouseDown end
MouseIsOver = function() return false end

local settings = { vignetteRadarPanelLayout = {} }
local traces = {}
local addon = {
    GetSettings = function() return settings end,
    InvalidateSettings = function() end,
    Trace = { Log = function(topic, fmt, ...)
        local values = { ... }
        for index = 1, select("#", ...) do values[index] = tostring(values[index]) end
        traces[#traces + 1] = topic .. ": " .. string.format(fmt, unpack(values, 1, select("#", ...)))
    end },
}
local function Traced(pattern)
    for _, line in ipairs(traces) do if line:find(pattern) then return line end end
end

-- The radar: a scaled panel with a round face texture on its field.
local radar = CreateFrame("Frame", nil, UIParent)
radar:SetScale(1.5)
radar:SetSize(240, 260)
radar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -100)
radar.strata = "HIGH"
radar.level = 20
radar.field = CreateFrame("Frame", nil, radar)
radar.field:SetSize(200, 200)
radar.field:SetPoint("TOP", radar, "TOP", 0, -20)
radar.field.background = radar.field:CreateTexture()
radar.field.background:SetAllPoints(radar.field)
radar.squarePlot = false
addon.VignetteRadarAPI = { GetPanel = function() return radar end }

assert(loadfile("UI/Tray.lua"))("VignetteRadar", addon)
local Tray = addon.VignetteRadarTray

local function Near(a, b, what) assert(math.abs(a - b) < .6, what .. ": " .. tostring(a) .. " vs " .. tostring(b)) end
local function Spot(frame)
    local ratio = frame:GetEffectiveScale() / UI_SCALE
    return frame:GetLeft() * ratio, frame:GetTop() * ratio - SCREEN_H
end

local function NewPanel(key, spec)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(260, 120)
    spec = spec or {}
    spec.key = key
    spec.order = spec.order or 10
    if spec.floatAlone == nil then spec.floatAlone = true end
    spec.refresh = spec.refresh or function() Tray.PlacePanel(frame, 4, 260) end
    Tray.RegisterPanel(frame, spec)
    return frame
end

-- 1. Docked under the scaled radar face, then dragged.
do
    local panel = NewPanel("guide")
    assert(panel.dontSave and panel.userPlaced == false and panel.clamped, "registered: no layout cache, clamped")
    assert(Tray.PlacePanel(panel, 4, 260), "docks")
    assert(panel.point[2] == radar.field.background, "docked to the face texture")
    assert(panel.strata == "HIGH", "docked panels take the radar's strata")
    local beforeX, beforeY = Spot(panel)
    panel.scripts.OnDragStart(panel)
    assert(panel.moving and panel._vrMoving, "drag starts")
    assert(not panel.foreignAnchor, "StartMoving begins from a UIParent anchor, never the radar face")
    assert(panel.point[1] == "TOPLEFT" and panel.point[2] == UIParent, "pinned by its top-left")
    local x, y = Spot(panel)
    Near(x, beforeX, "no horizontal jump at drag start")
    Near(y, beforeY, "no vertical jump at drag start")
    assert(panel.strataAtStart == "HIGH", "leaving the dock never drops it below the radar's strata")
    assert(panel.raised, "raised in its strata")
    local record = settings.vignetteRadarPanelLayout.guide
    assert(record.detached == true and record.x == math.floor(beforeX + .5), "detached on the spot")
    -- Re-places mid-drag leave it to the mouse.
    Drag(panel, 120, -40)
    local held = panel.point
    panel.scripts.OnDragStart(panel)
    Tray.PlacePanel(panel, 4, 260)
    Tray.RefitPanels()
    Tray.SettlePanel(panel)
    assert(panel.point == held and panel.moving, "no re-place, refit or second start mid-drag")
    panel.scripts.OnDragStop(panel)
    assert(not panel.moving and not panel._vrMoving and panel.userPlaced == false, "drop: not user-placed")
    record = settings.vignetteRadarPanelLayout.guide
    Near(record.x, beforeX + 120, "saved x in UIParent units")
    Near(record.y, beforeY - 40, "saved y in UIParent units")
    assert(panel.point[1] == "TOPLEFT" and panel.point[2] == UIParent, "re-anchored from the saved spot")
    assert(panel.strata == "HIGH", "the drop keeps the strata")
    assert(Traced("drag start guide") and Traced("drag stop guide"), "drag traced")
    Tray.SetPanelDetached(panel, false)
    Tray.PlacePanel(panel, 4, 260)
    assert(panel.point[2] == radar.field.background, "docks again")
end

-- 2. Parent hidden: refused. Parent a clipping holder: the drag moves it to UIParent.
do
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(400, 400)
    holder:SetPoint("CENTER", UIParent, "CENTER")
    local panel = NewPanel("parentTest", { detached = true })
    panel:SetParent(holder)
    panel:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -10)
    holder:Hide()
    panel.scripts.OnDragStart(panel)
    assert(not panel.moving and Traced("drag parentTest refused: not on screen"), "a hidden parent refuses the drag")
    holder:Show()
    local beforeX, beforeY = Spot(panel)
    panel.scripts.OnDragStart(panel)
    assert(panel.moving and panel.parentAtStart == UIParent, "free panels belong to UIParent")
    local x, y = Spot(panel)
    Near(x, beforeX, "same x after the parent change")
    Near(y, beforeY, "same y after the parent change")
    holder:Hide()
    assert(panel:IsVisible(), "its old parent hiding no longer hides it")
    panel.scripts.OnDragStop(panel)
end

-- 3. A see-through panel is made visible as it moves.
do
    local panel = NewPanel("alphaTest", { detached = true })
    Tray.PlacePanel(panel, 4, 260)
    panel:SetAlpha(0)
    panel.scripts.OnDragStart(panel)
    assert(panel.alpha == 1, "alpha restored for the drag")
    panel.scripts.OnDragStop(panel)
end

-- 4. Hidden mid-drag (no OnDragStop in the client): the drag ends.
do
    local panel = NewPanel("hideTest", { detached = true })
    Tray.PlacePanel(panel, 4, 260)
    panel.scripts.OnDragStart(panel)
    Drag(panel, 30, 0)
    panel:Hide()
    assert(not panel._vrMoving and not panel.moving and Traced("drag hideTest ended: hidden"), "hide ends it")
    assert(settings.vignetteRadarPanelLayout.hideTest.x, "and keeps the spot")
end

-- 5. A drag whose mouse-up was lost ends at the next re-place.
do
    local panel = NewPanel("lostTest", { detached = true })
    Tray.PlacePanel(panel, 4, 260)
    panel.scripts.OnDragStart(panel)
    Drag(panel, -50, 20)
    mouseDown = false
    Tray.PlacePanel(panel, 4, 260)
    mouseDown = true
    assert(not panel._vrMoving and Traced("drag lostTest ended without a drop"), "lost drop recovered")
end

-- 6. A scaled panel saves UIParent units.
do
    local panel = NewPanel("scaleTest", { detached = true })
    panel:SetScale(1.25)
    Tray.PlacePanel(panel, 4, 260)
    panel.scripts.OnDragStart(panel)
    Drag(panel, 10, -10)
    local x, y = Spot(panel)
    panel.scripts.OnDragStop(panel)
    local record = settings.vignetteRadarPanelLayout.scaleTest
    Near(record.x, x, "scaled x")
    Near(record.y, y, "scaled y")
    local again, againY = Spot(panel)
    Near(again, x, "re-anchor keeps x")
    Near(againY, y, "re-anchor keeps y")
end

-- 7. Safety net: an off-screen or half-saved spot re-docks on load.
do
    settings.vignetteRadarPanelLayout.farAway = { detached = true, x = 5200, y = -300 }
    local far = NewPanel("farAway")
    Tray.PlacePanel(far, 4, 260)
    local record = settings.vignetteRadarPanelLayout.farAway
    assert(record.detached == false and record.x == false and far.point[2] == radar.field.background,
        "off screen: back in the dock")
    assert(Traced("re%-dock farAway: saved spot 5200, %-300 is off screen"), "re-dock traced")
    settings.vignetteRadarPanelLayout.half = { detached = true, x = 400 }
    local half = NewPanel("half")
    Tray.PlacePanel(half, 4, 260)
    assert(settings.vignetteRadarPanelLayout.half.detached == false and Traced("re%-dock half: .* invalid"),
        "a half-saved spot re-docks")
    settings.vignetteRadarPanelLayout.fine = { detached = true, x = 400, y = -300 }
    local fine = NewPanel("fine")
    Tray.PlacePanel(fine, 4, 260)
    local x, y = Spot(fine)
    assert(settings.vignetteRadarPanelLayout.fine.detached == true and fine.point[2] == UIParent, "a good spot stays")
    Near(x, 400, "good spot x")
    Near(y, -300, "good spot y")
    -- Only once a session: a later move off screen is KeepOnScreen's job.
    settings.vignetteRadarPanelLayout.fine.x = 9000
    Tray.PlacePanel(fine, 4, 260)
    assert(settings.vignetteRadarPanelLayout.fine.detached == true, "checked once")
end

-- 8. Drawer panels: docked means the tray; free placement, migration, redock.
do
    settings.vignetteRadarQuestTrackerPosition = { x = 300.4, y = -200.2 }
    local floating, redocked = true, 0
    local drawer = NewPanel("questTracker", { drawer = true, ownControls = true, keepWidth = true,
        legacySpot = "vignetteRadarQuestTrackerPosition",
        isDetached = function() return floating end, canDrag = function() return floating end,
        redock = function() floating = false; redocked = redocked + 1 end })
    local record = settings.vignetteRadarPanelLayout.questTracker
    assert(record.x == 300 and record.y == -200 and settings.vignetteRadarQuestTrackerPosition == nil,
        "the old spot moved into the panel layout")
    assert(Traced("moved questTracker spot"), "migration traced")
    assert(not drawer.vrPanelBar, "own controls: no hover bar")
    assert(Tray.PlaceFreePanel(drawer) and drawer.point[2] == UIParent, "free at the saved spot")
    local x, y = Spot(drawer)
    Near(x, 300, "drawer x")
    Near(y, -200, "drawer y")
    floating = false
    assert(Tray.PlacePanel(drawer) == false, "docked drawer panels are docked by their module")
    drawer.scripts.OnDragStart(drawer)
    assert(not drawer.moving, "canDrag: no drag while docked")
    floating = true
    Tray.ResetAllPanels()
    assert(redocked == 1 and not floating, "/vr panels re-docks drawer panels too")
end

-- 9. Round radar: the arc gap beside the face and the tray's inset.
do
    local content = CreateFrame("Frame", nil, UIParent)
    content:SetSize(260, 180)
    local inset = 0
    assert(Tray.Attach({ frame = content, side = function() return "right" end, isOpen = function() return true end,
        inset = function() return inset end }))
    assert(Tray.FaceIsRound(), "the face is round")
    local slot = Tray.GetSlot()
    assert(slot._side == "right", "docked right")
    -- Face 200 x 1.5 = 300 UIParent units: radius 150. Rows 0..10 sit at
    -- 10..20 from the face top: 130 from the middle.
    local radius = 150
    Near(Tray.ArcGap(0, 10), radius - math.sqrt(radius * radius - 130 * 130), "gap near the top")
    Near(Tray.ArcGap(130, 150), 0, "no gap across the middle")
    Near(Tray.ArcGap(400, 420), radius, "below the circle the gap is the radius")
    inset = 30
    Tray.Place()
    assert(slot.point[2] == radar.field.background and slot.point[4] == -5 - 30, "the slot tucks the inset under")
    radar.squarePlot = true
    assert(not Tray.FaceIsRound(), "a square face is not round")
    radar.squarePlot = false
    Tray.Detach(content)
end

print("panel drag tests passed")
