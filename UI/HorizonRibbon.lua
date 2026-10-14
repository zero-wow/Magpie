local _, addon = ...
if type(addon) ~= "table" then return end

-- Horizon Ribbon: a thin compass across the top of the screen. Ticks show
-- Auto Route's next three stops (numbered), the World Focus point and the
-- live rares around you, coloured per kind, where they lie relative to the
-- way you face. WoW's nav frame can follow only one target (the focus, which
-- also gets the in-world beam); this is the honest view of the rest.
-- The tick list comes from the shared Compass feed (Core/Compass.lua) and is
-- re-read on POINTS_CHANGED / FOCUS_CHANGED / ROUTE_CHANGED; while shown,
-- an OnUpdate re-lays the ticks only when your facing, position or the scan
-- changed. The one tick under the center line (what you are aiming at) shows
-- its distance just below the ribbon; no other tick does.
--   Ribbon.Bearing(player, item, facing) -> angle (-pi..pi, + = left) | nil
--   Ribbon.X(angle, halfWidth, fov) -> x, clamped
--   Ribbon.Items() -> { { item, kind, label, focus } }
--   Ribbon.Refresh() / Ribbon.Layout() / Ribbon.GetFrame()
local Ribbon = {}
addon.VignetteRadarHorizonRibbon = Ribbon

local ipairs, abs = ipairs, math.abs
local PI = math.pi
local Number = addon.Secret.Number

local HEIGHT, ICON, MAX_RARES = 24, 13, 8
-- How far (px) a tick may sit from the center line and still count as aimed at.
local AIM_PX = 9
local DIAMOND = "Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CARDINALS = { { "N", 0 }, { "W", PI / 2 }, { "S", PI }, { "E", -PI / 2 } }

local frame
local items = {}
local lastFacing, lastGeneration, lastWidth, lastX, lastY

local function Settings() return addon.GetSettings() end

-- The bearing math, the tick list and the kind colors come from the shared
-- Compass feed (Core/Compass.lua), the same feed the Bearing Bar reads.
local Compass = addon.VignetteRadarCompass
Ribbon.Bearing, Ribbon.X, Ribbon.Yards = Compass.Bearing, Compass.X, Compass.Yards

-- What gets a tick, most important first, without duplicates.
function Ribbon.Items()
    return Compass.Ticks(nil, Settings().vignetteRadarHorizonRibbonRares == true and MAX_RARES or 0)
end

local function KindColor(kind, item)
    return Compass.Color(kind, item)
end

local function Tick(index)
    local tick = frame.ticks[index]
    if tick then return tick end
    tick = CreateFrame("Frame", nil, frame)
    tick:SetSize(ICON + 4, HEIGHT)
    tick.line = tick:CreateTexture(nil, "ARTWORK")
    tick.line:SetTexture(WHITE)
    tick.line:SetSize(2, 6)
    tick.line:SetPoint("BOTTOM", tick, "BOTTOM", 0, 2)
    tick.icon = tick:CreateTexture(nil, "OVERLAY")
    tick.icon:SetSize(ICON, ICON)
    tick.icon:SetPoint("BOTTOM", tick.line, "TOP", 0, 1)
    tick.label = tick:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(tick.label, 7, "OUTLINE")
    tick.label:SetPoint("CENTER", tick.icon, "CENTER", 0, 0)
    frame.ticks[index] = tick
    return tick
end

local function Ensure()
    if frame then return frame end
    frame = CreateFrame("Frame", "VignetteRadarHorizonRibbon", UIParent)
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(false)
    local controls = addon.VignetteRadarControls
    if controls and controls.RoundedStatusSurface then controls.RoundedStatusSurface(frame) end
    frame.center = frame:CreateTexture(nil, "ARTWORK")
    frame.center:SetTexture(WHITE)
    frame.center:SetSize(1, HEIGHT - 6)
    frame.center:SetPoint("CENTER")
    frame.cardinals = {}
    for index, entry in ipairs(CARDINALS) do
        local text = frame:CreateFontString(nil, "OVERLAY")
        addon.VignetteRadarStyle.SetFont(text, 8, "OUTLINE")
        text:SetText(entry[1])
        frame.cardinals[index] = text
    end
    frame.ticks = {}
    frame.aim = frame:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(frame.aim, 9, "OUTLINE")
    frame.aim:SetPoint("TOP", frame, "BOTTOM", 0, -1)
    frame.aim:Hide()
    frame:SetScript("OnUpdate", function() Ribbon.Layout() end)
    frame:Hide()
    return frame
end

local Facing = Compass.Facing

-- Places cardinals and ticks. Skips the work when nothing moved.
function Ribbon.Layout(force)
    if not (frame and frame:IsShown()) then return end
    local facing = Facing()
    local points = addon.VignetteRadarPoints
    local view = points and points.View()
    local player = view and view.player
    local generation = points and points.Generation() or 0
    local width = frame:GetWidth()
    local px, py = player and Number(player.worldX), player and Number(player.worldY)
    local moved = px and py and (not lastX or abs(px - lastX) + abs(py - lastY) > 1)
    if not force and not moved and facing and lastFacing and abs(facing - lastFacing) < .002
        and generation == lastGeneration and width == lastWidth then return end
    lastFacing, lastGeneration, lastWidth = facing, generation, width
    if moved then lastX, lastY = px, py end
    local aimItem, aimX, aimDistance
    local half = width / 2 - 10
    for index, entry in ipairs(CARDINALS) do
        local text = frame.cardinals[index]
        if facing then
            local angle = Compass.Relative(entry[2], facing)
            local x, clamped = Ribbon.X(angle, half)
            text:SetShown(not clamped)
            text:ClearAllPoints()
            text:SetPoint("TOP", frame, "TOP", x, -2)
        else
            text:Hide()
        end
    end
    local shown = 0
    for _, entry in ipairs(items) do
        local angle = facing and Ribbon.Bearing(player, entry.item, facing)
        if angle then
            shown = shown + 1
            local tick = Tick(shown)
            local x, clamped = Ribbon.X(angle, half)
            if tick._item ~= entry.item or tick._revision ~= (addon.VignetteRadarStyle.revision or 0) then
                tick._item, tick._revision = entry.item, addon.VignetteRadarStyle.revision or 0
                local icon = points.ApplyIcon(tick.icon, nil, entry.item, DIAMOND)
                local r, g, b = KindColor(entry.kind, entry.item)
                if icon.diamond then tick.icon:SetVertexColor(r, g, b, 1) else tick.icon:SetVertexColor(1, 1, 1, 1) end
                tick.line:SetVertexColor(r, g, b, 1)
                tick.label:SetText(entry.label or "")
                local size = entry.focus and ICON + 3 or ICON
                tick.icon:SetSize(size, size)
            end
            tick:SetAlpha(clamped and .45 or 1)
            tick:SetFrameLevel(frame:GetFrameLevel() + (entry.focus and 3 or 1))
            tick:ClearAllPoints()
            tick:SetPoint("BOTTOM", frame, "BOTTOM", x, 0)
            tick:Show()
            if not clamped and abs(x) <= AIM_PX and (not aimDistance or abs(x) < abs(aimDistance)) then
                aimItem, aimX, aimDistance = entry.item, x, x
            end
        end
    end
    for index = shown + 1, #frame.ticks do frame.ticks[index]:Hide() end
    Ribbon.ShowAim(aimItem, aimX, player)
end

-- The distance under the aimed-at tick only; hidden when nothing is aimed at.
function Ribbon.ShowAim(item, x, player)
    local aim = frame and frame.aim
    if not aim then return end
    local yards = item and Ribbon.Yards(player, item)
    if not yards then
        if aim:IsShown() then aim:Hide() end
        return
    end
    local text = math.floor(yards + .5) .. " yd"
    if aim._text ~= text then aim._text = text; aim:SetText(text) end
    if aim._x ~= x then
        aim._x = x
        aim:ClearAllPoints()
        aim:SetPoint("TOP", frame, "BOTTOM", x, -1)
    end
    if not aim:IsShown() then aim:Show() end
end

local function Paint()
    local style = addon.VignetteRadarStyle
    local revision = style and style.revision or -1
    if frame._styleRevision == revision then return end
    frame._styleRevision = revision
    local controls = addon.VignetteRadarControls
    if controls and controls.RefreshRoundedStatusSurface then controls.RefreshRoundedStatusSurface(frame) end
    local tray = addon.VignetteRadarTray
    if tray and tray.SkinLikeRadar then tray.SkinLikeRadar(frame) end
    local r, g, b = KindColor(nil)
    frame.center:SetVertexColor(r, g, b, .55)
    for _, text in ipairs(frame.cardinals) do text:SetTextColor(.72, .8, .82, .85) end
    frame.aim:SetTextColor(r, g, b, 1)
end

function Ribbon.Refresh()
    local db = Settings()
    if db.vignetteRadarHorizonRibbon ~= true then
        items = {}
        if frame then frame:Hide() end
        return
    end
    items = Ribbon.Items()
    if #items == 0 then
        if frame then frame:Hide() end
        return
    end
    Ensure()
    local width = Number(db.vignetteRadarHorizonRibbonWidth) or 440
    frame:SetSize(width, HEIGHT)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, -(Number(db.vignetteRadarHorizonRibbonOffset) or 40))
    Paint()
    local fade = db.vignetteRadarWorldMarkerCombatFade == true and addon.Bus and addon.Bus.InCombat() or false
    frame:SetAlpha(fade and .35 or 1)
    frame:Show()
    Ribbon.Layout(true)
    if addon.Trace then addon.Trace.Log("ribbon", "%d ticks", #items) end
end

function Ribbon.GetFrame() return frame end

if addon.Bus then
    addon.Bus.On("LOGIN", function() Ribbon.Refresh() end)
    addon.Bus.On("POINTS_CHANGED", function() Ribbon.Refresh() end, { coalesce = true })
    addon.Bus.On("FOCUS_CHANGED", function() Ribbon.Refresh() end, { coalesce = true })
    addon.Bus.On("ROUTE_CHANGED", function() Ribbon.Refresh() end, { coalesce = true })
    addon.Bus.On("COMBAT", function() Ribbon.Refresh() end, { coalesce = true })
end

return Ribbon
