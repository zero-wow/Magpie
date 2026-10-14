local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarConstellation = API

local GLYPHS = "Interface\\AddOns\\Magpie\\Media\\constellation-glyphs.tga"
local BASE = "Interface\\AddOns\\Magpie\\Media\\constellation-base-ring.tga"
local HALO = "Interface\\AddOns\\Magpie\\Media\\constellation-selected-halo.tga"
local TRAIL = "Interface\\AddOns\\Magpie\\Media\\constellation-trail.tga"
local DOT = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MODE_LABELS = { live = "LIVE ONLY", pack = "MAP PACK ONLY", mixed = "MIXED" }
local SUPPRESS_NAMES = { "WorldMapFrame", "CinematicFrame", "MovieFrame", "LoadingScreenFrame" }
local frame
local markers, grid, trailLines = {}, {}, {}
local pathX, pathY, trailLengths = {}, {}, {}
local gridSize, gridRingOpacity, gridSphereOpacity, gridR, gridG, gridB
local gridShowRings, gridShowSphere, positionedSize, positionedOffset
local phase = 0
local openAge = .18
local displayFacing, displayMapID, displaySpace
local interactionEnabled = false

local function Settings() return addon.GetSettings() end
local function Number(value) return addon.VignetteRadarSpatial.Number(value) end
local function Color(slot)
    local style = addon.VignetteRadarStyle
    if style and style.Color then return style.Color(slot) end
    return .05, .82, .62
end

local function Line(parent, layer, thickness)
    local line = parent:CreateLine(nil, layer or "ARTWORK")
    line:SetThickness(thickness or 1)
    line:Hide()
    return line
end

local function DrawLine(line, x1, y1, x2, y2, r, g, b, alpha)
    line:SetStartPoint("CENTER", frame, x1, y1)
    line:SetEndPoint("CENTER", frame, x2, y2)
    line:SetColorTexture(r, g, b, alpha)
    line:Show()
end

local function GridLine(index)
    if not grid[index] then grid[index] = Line(frame, "BACKGROUND", 1.1) end
    return grid[index]
end

local function DrawGrid(size, ringOpacity, sphereOpacity, showRings, showSphere)
    local radius = size * .42
    local r, g, b = Color("rings")
    if gridSize == size and gridRingOpacity == ringOpacity
        and gridSphereOpacity == sphereOpacity
        and gridShowRings == showRings and gridShowSphere == showSphere
        and gridR == r and gridG == g and gridB == b then return end
    local n = 0
    local function Segment(x1, y1, x2, y2, alpha, opacity)
        n = n + 1
        DrawLine(GridLine(n), x1, y1, x2, y2, r, g, b, alpha * opacity)
    end
    -- Three genuine horizontal range rings, projected with the same tilt as markers.
    if showRings then
        for ring = 1, 3 do
            local rr = radius * ring / 3
            for segment = 0, 23 do
                local a, z = segment * math.pi / 12, (segment + 1) * math.pi / 12
                Segment(rr * math.cos(a), rr * .42 * math.sin(a),
                    rr * math.cos(z), rr * .42 * math.sin(z),
                    ring == 3 and .22 or .15, ringOpacity)
            end
        end
    end
    -- A sparse transparent globe surrounding that disk. Its height is decorative.
    if showSphere then
        for segment = 0, 31 do
            local a, z = segment * math.pi / 16, (segment + 1) * math.pi / 16
            Segment(radius * math.cos(a), radius * math.sin(a),
                radius * math.cos(z), radius * math.sin(z), .18, sphereOpacity)
        end
        for meridian = 0, 2 do
            local azimuth = meridian * math.pi / 3 + .20
            for segment = 0, 23 do
                local a, z = segment * math.pi / 24, (segment + 1) * math.pi / 24
                local function Position(t)
                    local side = math.sin(t)
                    return radius * side * math.cos(azimuth),
                        radius * (math.cos(t) * .88 + side * math.sin(azimuth) * .42)
                end
                local x1, y1 = Position(a)
                local x2, y2 = Position(z)
                Segment(x1, y1, x2, y2, .10, sphereOpacity)
            end
        end
    end
    for index = n + 1, #grid do grid[index]:Hide() end
    gridSize, gridRingOpacity, gridSphereOpacity = size, ringOpacity, sphereOpacity
    gridShowRings, gridShowSphere, gridR, gridG, gridB = showRings, showSphere, r, g, b
end

local function GlyphColumn(point)
    if point.isWorldBoss then return 1 end
    if point.category == "rare" then return 0 end
    if point.category == "treasure" then return 2 end
    if point.category == "questAvailable" then return 3 end
    if point.category == "quest" then return 4 end
    if point.category == "entrance" then return 5 end
    if point.category == "event" then return 6 end
    return 7
end

local function ModifierHeld()
    local choice = Settings().vignetteRadarConstellationInteractModifier
    if choice == "ctrl" then return type(IsControlKeyDown) == "function" and IsControlKeyDown() end
    if choice == "shift" then return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() end
    if choice == "alt" then return type(IsAltKeyDown) == "function" and IsAltKeyDown() end
    return false
end

local function HideTooltip()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

local function ShowTooltip(hit)
    local point = hit.marker and hit.marker.pointData
    if not (point and GameTooltip) then return end
    GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
    GameTooltip:SetText(point.name or "Point", 1, .85, .45)
    local category = point.category == "rare" and "Rare"
        or point.category == "treasure" and "Treasure"
        or point.category == "entrance" and "Entrance"
        or point.category == "quest" and "Quest"
        or point.category == "questAvailable" and "Quest start"
        or point.category == "event" and "Event" or "Point"
    GameTooltip:AddLine(category .. " · "
        .. (point.evidence == "live" and "Detected now" or "Saved map spot"), .68, .82, .84)
    if point.distance then
        GameTooltip:AddLine(math.floor(point.distance + .5) .. " yd away", .68, .82, .84)
    end
    if point.source then GameTooltip:AddLine(point.source, .60, .72, .75) end
    GameTooltip:AddLine("Click to focus", .35, .95, .75)
    GameTooltip:Show()
end

local function FocusMarker(hit)
    local point = hit.marker and hit.marker.pointData
    if not (point and interactionEnabled) then return end
    local focus = addon.VignetteRadarFocus
    if point.targetRef then
        focus.Select(focus.Target(point.targetRef), { source = "constellation" })
    elseif point.noteRef then
        focus.Select(focus.Note(point.noteRef), { source = "constellation", direct = true })
    end
    API.FocusChanged()
    ShowTooltip(hit)
end

local function UpdateInteraction()
    local enabled = frame and frame:IsShown() and ModifierHeld() or false
    if interactionEnabled and not enabled then HideTooltip() end
    interactionEnabled = enabled
    for _, marker in ipairs(markers) do
        marker.hit:EnableMouse(enabled)
        marker.hit:SetShown(enabled)
    end
end

local function Marker(index)
    if markers[index] then return markers[index] end
    local marker = CreateFrame("Frame", nil, frame)
    marker:SetSize(42, 44)
    marker:EnableMouse(false)
    marker.halo = marker:CreateTexture(nil, "ARTWORK")
    marker.halo:SetTexture(HALO)
    marker.halo:SetSize(30, 30)
    marker.halo:SetPoint("CENTER", marker, "CENTER", 0, 0)
    marker.base = marker:CreateTexture(nil, "ARTWORK")
    marker.base:SetTexture(BASE)
    marker.base:SetSize(17, 9)
    marker.base:SetPoint("CENTER", marker, "CENTER", 0, 0)
    marker.core = marker:CreateTexture(nil, "OVERLAY")
    marker.core:SetTexture(DOT)
    marker.core:SetSize(3, 3)
    marker.core:SetPoint("CENTER", marker, "CENTER", 0, 0)
    marker.stem = Line(marker, "ARTWORK", 1.3)
    marker.stem:SetStartPoint("CENTER", marker, 0, 2)
    marker.stem:SetEndPoint("CENTER", marker, 0, 6)
    marker.glyph = marker:CreateTexture(nil, "OVERLAY")
    marker.glyph:SetTexture(GLYPHS)
    marker.glyph:SetSize(32, 32)
    marker.glyph:SetPoint("CENTER", marker, "CENTER", 0, 13)
    marker.shadow = marker:CreateTexture(nil, "ARTWORK")
    marker.shadow:SetTexture(GLYPHS)
    marker.shadow:SetPoint("CENTER", marker.glyph, "CENTER", 0, 0)
    marker.hit = CreateFrame("Button", nil, marker)
    marker.hit.marker = marker
    marker.hit:SetSize(40, 40)
    marker.hit:SetPoint("CENTER", marker, "CENTER", 0, 13)
    marker.hit:RegisterForClicks("LeftButtonUp")
    marker.hit:SetScript("OnEnter", ShowTooltip)
    marker.hit:SetScript("OnLeave", HideTooltip)
    marker.hit:SetScript("OnClick", FocusMarker)
    marker.hit:EnableMouse(interactionEnabled)
    marker.hit:SetShown(interactionEnabled)
    marker:Hide()
    markers[index] = marker
    return marker
end

local function PlaceMarker(marker, point, player, radius, range, opacity, settings)
    local spatial = addon.VignetteRadarSpatial
    local facing = settings.vignetteRadarNorthUp and 0
        or player.headingAvailable and Number(player.facing) or 0
    local x, y = spatial.Project(point.worldX - player.worldX,
        point.worldY - player.worldY, facing, range, radius, .42)
    if not (x and y) then marker:Hide(); return nil end
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", frame, "CENTER", x, y)
    marker.pointData = point
    local chosen = point.focused == true
    local category = point.category == "entrance" and "accent" or point.category
    local r, g, b = Color(category or "other")
    marker:SetAlpha(opacity * (point.evidence == "saved" and .88 or 1))
    local showBases = settings.vignetteRadarConstellationShowBases
    marker.base:SetShown(showBases)
    marker.base:SetVertexColor(r, g, b, chosen and 1 or .82)
    marker.base:SetSize(chosen and 22 or 18, chosen and 11 or 9)
    marker.halo:SetVertexColor(r, g, b, .32)
    marker.halo:SetSize(chosen and 44 or 30, chosen and 22 or 15)
    marker.halo:SetShown(chosen and showBases)
    marker.core:SetShown(showBases and point.evidence == "live")
    marker.core:SetVertexColor(r, g, b, 1)
    marker.stem:SetColorTexture(r, g, b, .82)
    marker.stem:SetShown(showBases)
    local shapes = settings.vignetteRadarShapes ~= false
    local iconSize = settings.vignetteRadarConstellationIconSize
    if shapes then
        marker.glyph:SetTexture(GLYPHS)
        local column, row = GlyphColumn(point), chosen and 2 or 0
        local left, right = (column * 64 + 8) / 1024, (column * 64 + 56) / 1024
        local top, bottom = (row * 64 + 8) / 256, (row * 64 + 56) / 256
        marker.glyph:SetTexCoord(left, right, top, bottom)
        marker.shadow:SetTexture(GLYPHS)
        marker.shadow:SetTexCoord(left, right, top, bottom)
        marker.glyph:SetSize(chosen and iconSize + 4 or iconSize,
            chosen and iconSize + 4 or iconSize)
    else
        marker.glyph:SetTexture(DOT)
        marker.glyph:SetTexCoord(0, 1, 0, 1)
        marker.shadow:SetTexture(DOT)
        marker.shadow:SetTexCoord(0, 1, 0, 1)
        marker.glyph:SetSize(chosen and 13 or 10, chosen and 13 or 10)
    end
    marker.shadow:SetSize(marker.glyph:GetWidth() + 3, marker.glyph:GetHeight() + 3)
    marker.shadow:SetVertexColor(0, 0, 0, .72)
    marker.glyph:SetVertexColor(r, g, b, 1)
    marker:Show()
    return x, y
end

local function TrailLine(index)
    if not trailLines[index] then
        local segment = CreateFrame("Frame", nil, frame,
            "VignetteRadarConstellationTrailTemplate")
        segment.Fill:SetTexture(TRAIL, "REPEAT", "CLAMP", "TRILINEAR")
        segment.Fill:SetThickness(4)
        segment.Guide:SetThickness(1.2)
        segment:Hide()
        trailLines[index] = segment
    end
    return trailLines[index]
end

local function HideTrail()
    for _, segment in ipairs(trailLines) do
        if segment.Scroll:IsPlaying() then segment.Scroll:Stop() end
        segment.startedAt = nil
        segment:Hide()
    end
end

local function DrawTrail(count, opacity, reducedMotion)
    if count < 2 then HideTrail(); return end
    local total = 0
    local lengths = trailLengths
    for index = 2, count do
        local dx, dy = pathX[index] - pathX[index - 1], pathY[index] - pathY[index - 1]
        lengths[index] = math.sqrt(dx * dx + dy * dy)
        total = total + lengths[index]
    end
    if total < 2 then HideTrail(); return end
    local r, g, b = Color("accent")
    local now = type(GetTime) == "function" and GetTime() or phase
    local spacing, speed = 14, 28
    local cursor = 0
    for index = 2, count do
        local segment = TrailLine(index - 1)
        local x1, y1 = pathX[index - 1], pathY[index - 1]
        local x2, y2 = pathX[index], pathY[index]
        DrawLine(segment.Guide, x1, y1, x2, y2, r, g, b, opacity * .20)
        segment.Fill:SetStartPoint("CENTER", frame, x1, y1)
        segment.Fill:SetEndPoint("CENTER", frame, x2, y2)
        segment.Fill:SetVertexColor(r, g, b, opacity * .82)
        if reducedMotion then
            if segment.Scroll:IsPlaying() then segment.Scroll:Stop() end
            segment.startedAt = nil
        elseif not segment.Scroll:IsPlaying() then
            segment.startedAt = now
        end
        -- Every segment uses the same wall-clock phase and cumulative length,
        -- so the texture keeps flowing through waypoint bends without a seam.
        local startPhase = segment.startedAt and (segment.startedAt * speed / spacing) % 1 or 0
        local u1, u2 = cursor / spacing - startPhase,
            (cursor + lengths[index]) / spacing - startPhase
        segment.Fill:SetTexCoord(u1, 0, u1, 1, u2, 0, u2, 1)
        segment:Show()
        segment.Fill:Show()
        if not reducedMotion and not segment.Scroll:IsPlaying() then
            segment.Scroll:Play()
        end
        cursor = cursor + lengths[index]
    end
    for index = count, #trailLines do
        local segment = trailLines[index]
        if segment.Scroll:IsPlaying() then segment.Scroll:Stop() end
        segment.startedAt = nil
        segment:Hide()
    end
end

local function Trail(snapshot, player, chosen, chosenX, chosenY, radius, range, opacity, settings)
    if not (chosen and settings.vignetteRadarConstellationGuidance) then
        HideTrail(); return nil
    end
    local count = 1
    pathX[1], pathY[1] = 0, 0
    local route = snapshot.focusPath
    local mode = "Direct Bearing"
    if route and route.hasExplicitSteps
        and (route.destinationKey == chosen.key or route.destinationKey == chosen.sourceKey)
        and not route.truncated then
        local valid = #route.points > 0
        local facing = settings.vignetteRadarNorthUp and 0
            or player.headingAvailable and Number(player.facing) or 0
        for _, point in ipairs(route.points) do
            if point.instanceID ~= snapshot.coordinateSpaceID then valid = false; break end
            local x, y, distance = addon.VignetteRadarSpatial.Project(
                point.worldX - player.worldX, point.worldY - player.worldY,
                facing, range, radius, .42)
            if not (x and y and distance <= range) then valid = false; break end
            count = count + 1
            pathX[count], pathY[count] = x, y
        end
        if valid then mode = "Known Waypoints" else count = 1 end
    end
    if count == 1 or (pathX[count] - chosenX)^2 + (pathY[count] - chosenY)^2 > 9 then
        count = count + 1
        pathX[count], pathY[count] = chosenX, chosenY
    end
    DrawTrail(count, opacity, settings.vignetteRadarConstellationReducedMotion)
    return mode
end

local function DrawCenterCue(player, alpha, settings)
    local r, g, b = Color("heading")
    frame.player:SetVertexColor(r, g, b, alpha)
    if not player.headingAvailable then
        frame.headingLine:Hide()
        for _, line in ipairs(frame.steeple) do line:Hide() end
        return
    end
    local angle = settings.vignetteRadarNorthUp and player.facing or 0
    local forwardX, forwardY = -math.sin(angle), math.cos(angle)
    local rightX, rightY = math.cos(angle), math.sin(angle)
    if settings.vignetteRadarConstellationHeadingLine then
        local reach = 11 + settings.vignetteRadarConstellationHeadingLength * 45
        DrawLine(frame.headingLine, forwardX * 11, forwardY * 11,
            forwardX * reach, forwardY * reach, r, g, b, alpha * .5)
    else
        frame.headingLine:Hide()
    end
    for index, line in ipairs(frame.steeple) do
        if settings.vignetteRadarConstellationCenterArrow then
            local side = index == 1 and -1 or 1
            DrawLine(line, forwardX * 2.5 + rightX * side * 3.5,
                forwardY * 2.5 + rightY * side * 3.5,
                forwardX * 9.5, forwardY * 9.5, r, g, b, alpha)
        else
            line:Hide()
        end
    end
end

local function EnsureFrame()
    if frame or not UIParent then return frame end
    frame = CreateFrame("Frame", "VignetteRadarConstellationFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(20)
    frame:EnableMouse(false)
    frame.mode = frame:CreateFontString(nil, "OVERLAY")
    frame.mode:SetPoint("TOP", frame, "TOP", 0, -8)
    frame.status = frame:CreateFontString(nil, "OVERLAY")
    for _, readout in ipairs({ frame.mode, frame.status }) do
        addon.VignetteRadarStyle.SetFont(readout, 10, "")
        if readout.SetShadowOffset then readout:SetShadowOffset(1, -1) end
    end
    frame.status:SetPoint("BOTTOM", frame, "BOTTOM", 0, 7)
    frame.status:SetWidth(300)
    frame.status:SetHeight(24)
    frame.player = frame:CreateTexture(nil, "OVERLAY")
    frame.player:SetTexture(DOT)
    frame.player:SetSize(3, 3)
    frame.player:SetPoint("CENTER")
    frame.headingLine = Line(frame, "ARTWORK", 1)
    frame.steeple = { Line(frame, "OVERLAY", 1.4), Line(frame, "OVERLAY", 1.4) }
    frame.trailLines = trailLines
    frame:Hide()
    return frame
end

local function Suppressed()
    for _, name in ipairs(SUPPRESS_NAMES) do
        local shown = _G[name]
        if shown and shown.IsShown and shown:IsShown() then return true end
    end
    return false
end

-- Font strings only take a new string when it differs; Render runs up to 30x a second.
local function SetTextIfChanged(fontString, text)
    if fontString._shownText == text then return end
    fontString._shownText = text
    fontString:SetText(text)
end

local function Render(elapsed, settings)
    if not frame then return end
    if Suppressed() then frame:SetAlpha(0); displayFacing = nil; return end
    settings = settings or Settings()
    frame:SetAlpha(settings.vignetteRadarConstellationReducedMotion
        and 1 or math.min(1, openAge / .18))
    local viewportW, viewportH = Number(UIParent:GetWidth()), Number(UIParent:GetHeight())
    if not (viewportW and viewportH and viewportW > 0 and viewportH > 0) then return end
    local size = math.min(settings.vignetteRadarConstellationSize,
        viewportW * .70, viewportH * .72, viewportW - 32, viewportH - 32)
    if size < 120 then return end
    local offsetY = math.max(-viewportH / 2 + size / 2 + 16,
        math.min(viewportH / 2 - size / 2 - 16,
            viewportH * settings.vignetteRadarConstellationOffsetY))
    if positionedSize ~= size or positionedOffset ~= offsetY then
        frame:SetSize(size, size)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, offsetY)
        positionedSize, positionedOffset = size, offsetY
    end
    local quietFactor = 1
    if addon.VignetteRadarFeatures and addon.VignetteRadarFeatures.IsVisuallyQuiet
        and addon.VignetteRadarFeatures.IsVisuallyQuiet()
        and not settings.vignetteRadarKeepVisibleCombat then quietFactor = .35 end
    local opacity = settings.vignetteRadarConstellationOpacity * quietFactor
    DrawGrid(size, settings.vignetteRadarConstellationRingOpacity * quietFactor,
        settings.vignetteRadarConstellationSphereOpacity * quietFactor,
        settings.vignetteRadarConstellationShowRings,
        settings.vignetteRadarConstellationShowSphere)
    local r, g, b = Color("accent")
    frame.player:SetVertexColor(r, g, b, settings.vignetteRadarConstellationCenterOpacity * quietFactor)
    local mode = settings.vignetteRadarConstellationSourceMode
    local radar = addon.VignetteRadarAPI
    local snapshot = radar and radar.GetSpatialSnapshot and radar.GetSpatialSnapshot(mode)
    local player = radar and radar.GetPlayerSnapshot and radar.GetPlayerSnapshot()
    if player and player.headingAvailable then
        local facing = Number(player.facing)
        if facing then
            if not displayFacing or displayMapID ~= player.mapID
                or displaySpace ~= Number(player.instanceID) then
                displayFacing = facing
            else
                local delta = addon.VignetteRadarSpatial.Angle(facing - displayFacing)
                displayFacing = addon.VignetteRadarSpatial.Angle(displayFacing
                    + delta * (1 - math.exp(-math.max(0, elapsed or 0) * 18)))
            end
            displayMapID, displaySpace = player.mapID, Number(player.instanceID)
            player.facing = displayFacing
        end
    else
        displayFacing = nil
    end
    local orientation = settings.vignetteRadarNorthUp and "North Up"
        or player and player.headingAvailable and "Facing Up" or "Heading Unavailable"
    SetTextIfChanged(frame.mode, (MODE_LABELS[mode] or MODE_LABELS.mixed) .. "  ·  "
        .. orientation .. "  ·  " .. tostring(settings.vignetteRadarRange) .. " yd")
    frame.mode:SetTextColor(r, g, b, .75 * quietFactor)
    frame.status:SetTextColor(r, g, b, .75 * quietFactor)
    frame.mode:SetShown(settings.vignetteRadarConstellationShowReadout)
    frame.status:SetShown(settings.vignetteRadarConstellationShowReadout)
    if not (snapshot and player and Number(player.worldX) and Number(player.worldY)
        and snapshot.mapID == player.mapID
        and snapshot.coordinateSpaceID == Number(player.instanceID)) then
        for _, marker in ipairs(markers) do marker:Hide() end
        HideTrail()
        frame.headingLine:Hide()
        for _, line in ipairs(frame.steeple) do line:Hide() end
        SetTextIfChanged(frame.status, "Position Unavailable")
        return
    end
    local radius, range = size * .42, snapshot.effectiveRange
    DrawCenterCue(player,
        settings.vignetteRadarConstellationCenterOpacity * quietFactor, settings)
    local shown = 0
    local chosen, chosenX, chosenY
    local cap = math.min(settings.vignetteRadarConstellationMaxPoints, #snapshot.points)
    for index = 1, cap do
        local point = snapshot.points[index]
        local marker = Marker(index)
        local x, y = PlaceMarker(marker, point, player, radius, range, opacity, settings)
        if x and y then
            shown = shown + 1
            if point.focused and not chosen then chosen, chosenX, chosenY = point, x, y end
        end
    end
    for index = cap + 1, #markers do markers[index]:Hide() end
    local guidance = Trail(snapshot, player, chosen, chosenX, chosenY, radius, range,
        settings.vignetteRadarConstellationTrailOpacity * quietFactor, settings)
    local extra = math.max(0, snapshot.totalEligibleCount - shown)
    local status = snapshot.reason or (shown == 0 and "No Points In Range")
        or guidance or "Select a Point on Radar"
    if extra > 0 then status = status .. "  ·  +" .. extra .. " more" end
    SetTextIfChanged(frame.status, status)
end

local function Tick(self, elapsed)
    self._elapsed = math.min(.5, (self._elapsed or 0) + elapsed)
    phase = phase + elapsed * 24
    openAge = math.min(.18, openAge + elapsed)
    local settings = Settings()
    local performance = settings.vignetteRadarPerformance
    local interval = performance == "low" and 1 / 15
        or performance == "balanced" and 1 / 24 or 1 / 30
    if self._elapsed < interval then return end
    local budget = addon.VignetteRadarLayerBudget
    local token = budget and budget.Begin("constellation")
    if budget and not token then return end
    local stepElapsed = self._elapsed
    self._elapsed = self._elapsed % interval
    -- Finish must run even when Render errors, or the layer budget keeps the
    -- token open and the constellation stays dead until /reload.
    local ok, err = pcall(Render, stepElapsed, settings)
    if token then budget.Finish(token) end
    if not ok then
        local handler = type(geterrorhandler) == "function" and geterrorhandler()
        if handler then handler(err) end
    end
end

local function RefreshControl()
    local radar = addon.VignetteRadarAPI
    if radar and radar.RefreshConstellationControl then radar.RefreshConstellationControl() end
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
    local popup = addon.VignetteRadarConstellationSettings
    if popup and popup.Refresh then popup.Refresh() end
end

function API.Refresh()
    local settings = Settings()
    local wanted = settings.vignetteRadarEnabled == true
        and settings.vignetteRadarConstellationEnabled == true
    if wanted then
        local surface = EnsureFrame()
        if surface then
            if not surface:IsShown() then openAge = 0 end
            surface:Show()
            surface:SetScript("OnUpdate", Tick)
            UpdateInteraction()
            Render()
        end
    elseif frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        frame._elapsed = 0
        displayFacing = nil
        HideTrail()
        for _, marker in ipairs(markers) do marker:Hide() end
        UpdateInteraction()
    end
    RefreshControl()
    return wanted
end

function API.SetEnabled(enabled)
    local settings = Settings()
    if enabled and settings.vignetteRadarEnabled ~= true then
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("Enable Radar First", 1, .7, .3)
        end
        return false
    end
    enabled = enabled == true
    if settings.vignetteRadarConstellationEnabled == enabled then return enabled end
    settings.vignetteRadarConstellationEnabled = enabled
    local radar = addon.VignetteRadarAPI
    if radar and radar.InvalidateSpatialSnapshot then radar.InvalidateSpatialSnapshot() end
    if radar and radar.Refresh then radar.Refresh(true) end
    API.Refresh()
    return enabled
end

function API.Toggle() return API.SetEnabled(not Settings().vignetteRadarConstellationEnabled) end

function API.SetSourceMode(mode)
    if mode ~= "live" and mode ~= "pack" and mode ~= "mixed" then return false end
    local settings = Settings()
    if settings.vignetteRadarConstellationSourceMode == mode then return true end
    settings.vignetteRadarConstellationSourceMode = mode
    local radar = addon.VignetteRadarAPI
    if radar and radar.InvalidateSpatialSnapshot then radar.InvalidateSpatialSnapshot() end
    if radar and radar.Refresh then radar.Refresh(true) end
    API.Refresh()
    return true
end

function API.FocusChanged()
    local radar = addon.VignetteRadarAPI
    if radar and radar.InvalidateSpatialSnapshot then radar.InvalidateSpatialSnapshot() end
    if frame and frame:IsShown() then Render() end
end

function API.ToggleMenu(anchor)
    local settings = addon.VignetteRadarConstellationSettings
    if settings then settings.Toggle(anchor) end
end

function API.OpenSettings()
    local settings = addon.VignetteRadarConstellationSettings
    if settings then settings.Open() end
end

function VignetteRadar_ToggleConstellation() API.Toggle() end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "MODIFIER_STATE_CHANGED" then UpdateInteraction()
    else API.Refresh() end
end)

return API
