local _, addon = ...
if type(addon) ~= "table" then return end

-- In-world marker for the World Focus target. It rides Blizzard's
-- navigation frame (C_Navigation.GetFrame), which the game moves onto the
-- target's screen position every frame, so the marker and its light beam
-- always stand on the right spot. Off screen it clamps to an ellipse and
-- shows an arrow. Technique learned from GlanceQuest (MIT, Null0perator).
local Marker = {}
addon.VignetteRadarWorldMarker = Marker

local MEDIA = "Interface\\AddOns\\Magpie\\Media\\"
local DIAMOND = MEDIA .. "quest-diamond.tga"
local ICON_SIZE, BEAM_WIDTH, BEAM_HEIGHT = 30, 28, 256
-- Blizzard's own clamp radii for the super-tracked diamond.
local CLAMP_X, CLAMP_Y, ARROW_DISTANCE = 500, 200, 30
local TEXT_SECONDS, COMBAT_ALPHA = .25, .35

local frame, navFrame, hookedDiamond
local inCombat, clamped, textElapsed = false, nil, 0
local stateAlpha
-- Settings read by the per-frame update, cached by Marker.Refresh (which
-- QuickConfig calls on every marker setting change).
local markerOn, beamOn, textOn, combatFade = false, false, false, false
local shownAlpha

local function Settings() return addon.GetSettings() end

local Secret, SecretCall = addon.Secret.IsSecret, addon.Secret.Call

-- First result only, like the old local helper.
local function Call(owner, name, ...)
    return (SecretCall(owner, name, ...))
end

local function StateAlpha(state)
    if not stateAlpha then
        local states = Enum and Enum.NavigationState
        if not states then return 1 end
        stateAlpha = { [states.Invalid] = 0, [states.Occluded] = .6,
            [states.InRange] = 1, [states.Disabled] = 0 }
    end
    return stateAlpha[state] or 1
end

local function Target()
    local focus = addon.VignetteRadarWorldFocus
    if not (focus and focus.GetActiveTarget) then return nil end
    return focus.GetActiveTarget()
end

local function Wanted()
    return Settings().vignetteRadarWorldMarker == true and navFrame ~= nil and Target() ~= nil
end

-- Blizzard's diamond would sit on top of ours; hide it while we draw.
local function HookDiamond()
    if hookedDiamond or not SuperTrackedFrame or type(hooksecurefunc) ~= "function" then return end
    if type(SuperTrackedFrame.UpdateAlpha) ~= "function" then return end
    hooksecurefunc(SuperTrackedFrame, "UpdateAlpha", function(self)
        if frame and frame:IsShown() then self:SetAlpha(0) end
    end)
    hookedDiamond = true
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "VignetteRadarWorldMarker", UIParent)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:EnableMouse(false)
    frame.beam = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    frame.beam:SetTexture(MEDIA .. "world-beam.tga")
    frame.beam:SetBlendMode("BLEND")
    frame.beam:SetSize(BEAM_WIDTH, BEAM_HEIGHT)
    frame.beam:SetPoint("BOTTOM", frame, "CENTER")
    frame.glow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.glow:SetTexture(MEDIA .. "world-beam.tga")
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetAllPoints(frame.beam)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetAllPoints(frame)
    -- Blizzard's own icon for the kind (Points.Icon); kinds without one wear
    -- the tinted diamond with their letter (C, G, N...).
    frame.icon:SetTexture(DIAMOND)
    frame.badge = frame:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(frame.badge, 15, "OUTLINE", "bold")
    frame.badge:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.badge:SetTextColor(1, 1, 1, 1)
    frame.arrow = frame:CreateTexture(nil, "OVERLAY")
    frame.arrow:SetTexture(MEDIA .. "route-nav-chevron.tga")
    frame.arrow:SetSize(26, 26)
    frame.arrow:Hide()
    local Style = addon.VignetteRadarStyle
    frame.name = frame:CreateFontString(nil, "OVERLAY")
    Style.SetFont(frame.name, 12, "OUTLINE")
    frame.name:SetPoint("TOP", frame, "BOTTOM", 0, -3)
    frame.distance = frame:CreateFontString(nil, "OVERLAY")
    Style.SetFont(frame.distance, 11, "OUTLINE")
    frame.distance:SetTextColor(.85, .9, .9)
    frame.distance:SetPoint("TOP", frame.name, "BOTTOM", 0, -1)
    frame.step = frame:CreateFontString(nil, "OVERLAY")
    Style.SetFont(frame.step, 10, "OUTLINE")
    frame.step:SetTextColor(.75, .82, .82)
    frame.step:SetWidth(220)
    frame.step:SetPoint("TOP", frame.distance, "BOTTOM", 0, -1)
    frame:Hide()
    return frame
end

local function ApplyLook(item)
    local focus = addon.VignetteRadarWorldFocus
    local r, g, b = focus.TargetColor(item)
    if not r then
        local style = addon.VignetteRadarStyle
        if style and style.Color then r, g, b = style.Color("accent") else r, g, b = .55, .88, .82 end
    end
    local points = addon.VignetteRadarPoints
    local icon = points.ApplyIcon(frame.icon, points.Icon(item), item, DIAMOND)
    if icon.diamond then
        frame.icon:SetVertexColor(r, g, b)
        frame.badge:SetText(icon.label)
        frame.badge:Show()
    else
        local tint = icon.color
        frame.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
        frame.badge:Hide()
    end
    frame.beam:SetVertexColor(r, g, b, .9)
    frame.glow:SetVertexColor(r, g, b, .45)
    frame.arrow:SetVertexColor(r, g, b)
    frame.name:SetText(item.name or "")
    frame.name:SetTextColor(r, g, b)
end

local function UpdateText(item)
    local showText = textOn
    frame.name:SetShown(showText)
    frame.distance:SetShown(showText)
    frame.step:SetShown(showText)
    if not showText then return end
    local distance = Call(C_Navigation, "GetDistance")
    frame.distance:SetText(type(distance) == "number" and distance > 0
        and (math.floor(distance + .5) .. " yds") or "")
    local line
    local data = addon.VignetteRadarQuestData
    if item.kind == "quest" and data and data.GetNextStepLine then line = data.GetNextStepLine(item.questID) end
    frame.step:SetText(line or "")
end

-- Off screen: Blizzard clamps the nav frame to the screen edge; re-clamp it
-- to an ellipse around the screen center and point an arrow at the target.
local function PlaceClamped()
    local x, y = navFrame:GetCenter()
    local cx, cy = WorldFrame:GetCenter()
    if not (x and y and cx and cy) or Secret(x) or Secret(cx) then return false end
    local uiScale = UIParent:GetEffectiveScale()
    x = (x * navFrame:GetEffectiveScale() - cx * WorldFrame:GetEffectiveScale()) / uiScale
    y = (y * navFrame:GetEffectiveScale() - cy * WorldFrame:GetEffectiveScale()) / uiScale
    local denominator = math.sqrt(CLAMP_X * CLAMP_X * y * y + CLAMP_Y * CLAMP_Y * x * x)
    if denominator > 0 then
        local ratio = CLAMP_X * CLAMP_Y / denominator
        if ratio < 1 then x, y = x * ratio, y * ratio end
    end
    local scale = frame:GetScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", WorldFrame, "CENTER", x / scale, y / scale)
    local length = math.sqrt(x * x + y * y)
    if length > 0 then
        frame.arrow:ClearAllPoints()
        frame.arrow:SetPoint("CENTER", frame, "CENTER", x / length * ARROW_DISTANCE, y / length * ARROW_DISTANCE)
        frame.arrow:SetRotation(math.atan2(-x, y))
    end
    return true
end

local function OnUpdate(_, elapsed)
    local item = Target()
    if not (item and navFrame and markerOn) then
        frame:Hide()
        return
    end
    if Call(C_Navigation, "HasValidScreenPosition") == false then
        if shownAlpha ~= 0 then shownAlpha = 0; frame:SetAlpha(0) end
        return
    end
    local isClamped = Call(C_Navigation, "WasClampedToScreen") == true
    if isClamped then
        if not PlaceClamped() then
            if shownAlpha ~= 0 then shownAlpha = 0; frame:SetAlpha(0) end
            return
        end
    elseif clamped ~= false then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", navFrame, "CENTER")
    end
    if clamped ~= isClamped then
        clamped = isClamped
        local beam = not isClamped and beamOn
        frame.beam:SetShown(beam)
        frame.glow:SetShown(beam)
        frame.arrow:SetShown(isClamped)
    end
    local alpha = isClamped and 1 or StateAlpha(Call(C_Navigation, "GetTargetState"))
    if inCombat and combatFade then alpha = alpha * COMBAT_ALPHA end
    if shownAlpha ~= alpha then
        shownAlpha = alpha
        frame:SetAlpha(alpha)
    end
    textElapsed = textElapsed + elapsed
    if textElapsed >= TEXT_SECONDS then
        textElapsed = 0
        UpdateText(item)
    end
end

-- Re-reads the target and settings; call when the focus or settings change.
function Marker.Refresh()
    navFrame = Call(C_Navigation, "GetFrame") or nil
    local settings = Settings()
    markerOn = settings.vignetteRadarWorldMarker == true
    beamOn = settings.vignetteRadarWorldMarkerBeam == true
    textOn = settings.vignetteRadarWorldMarkerText == true
    combatFade = settings.vignetteRadarWorldMarkerCombatFade == true
    if not Wanted() then
        if frame then frame:Hide(); frame:SetScript("OnUpdate", nil) end
        return
    end
    Build()
    HookDiamond()
    local item = Target()
    ApplyLook(item)
    clamped, textElapsed, shownAlpha = nil, TEXT_SECONDS, nil
    frame:SetScript("OnUpdate", OnUpdate)
    frame:Show()
end

function Marker.IsShown() return frame ~= nil and frame:IsShown() end

-- Diagnostics: /vr navlog arms a recorder. Each spell cast while skyriding
-- then records 2 seconds of per-frame positions (Blizzard's nav frame, our
-- marker, Blizzard's diamond, WaypointUI's pin) plus forward speed, saved
-- in vignetteRadarNavLog (up to 5 recordings) for tuning a Surge filter.
local NAV_LOG_SECONDS, NAV_LOG_MAX = 2, 5
local recorder, recording, armed

local function Center(region)
    if not (region and region.GetCenter and region.IsShown and region:IsShown()) then return end
    local x, y = region:GetCenter()
    if type(x) ~= "number" or Secret(x) or Secret(y) then return end
    local scale = region:GetEffectiveScale()
    return math.floor(x * scale * 10 + .5) / 10, math.floor(y * scale * 10 + .5) / 10
end

local function Cell(value) return value == nil and "" or tostring(value) end

local function Say(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff8fd6c9Magpie:|r " .. text) end
end

local function RecordFrame(_, elapsed)
    if not recording then return end
    local now = GetTime()
    local nav = Call(C_Navigation, "GetFrame")
    local nx, ny = Center(nav)
    local mx, my = Center(frame)
    local sx, sy = Center(_G.SuperTrackedFrame)
    local wx, wy = Center(_G.WUIWaypointFrame)
    local speed
    local ok, _, _, forward = pcall(C_PlayerInfo.GetGlidingInfo)
    if ok and type(forward) == "number" and not Secret(forward) then speed = math.floor(forward * 10 + .5) / 10 end
    local rows = recording.rows
    rows[#rows + 1] = table.concat({ math.floor((now - recording.start) * 1000 + .5),
        math.floor(elapsed * 1000 * 10 + .5) / 10, Cell(nx), Cell(ny),
        Cell(Call(C_Navigation, "WasClampedToScreen")), Cell(mx), Cell(my),
        Cell(sx), Cell(sy), Cell(wx), Cell(wy), Cell(speed) }, ",")
    if now - recording.start >= NAV_LOG_SECONDS then
        local db = Settings()
        local logs = db.vignetteRadarNavLog
        logs[#logs + 1] = recording
        while #logs > NAV_LOG_MAX do table.remove(logs, 1) end
        Say(("Recording %d of %d saved (%d frames)."):format(#logs, NAV_LOG_MAX, #rows))
        recording = nil
        if #logs >= NAV_LOG_MAX then
            armed = false
            recorder:UnregisterAllEvents()
            Say("All recordings done. Type /reload to save them.")
        end
    end
end

local function OnCast(_, _, _, _, spellID)
    if not armed or recording then return end
    local ok, gliding = pcall(C_PlayerInfo.GetGlidingInfo)
    if not ok or gliding ~= true then return end
    recording = { start = GetTime(), spell = Secret(spellID) and "secret" or Cell(spellID),
        columns = "ms,frameMs,navX,navY,clamped,markerX,markerY,diamondX,diamondY,wuiX,wuiY,speed", rows = {} }
end

function Marker.StartNavLog()
    if not recorder then
        recorder = CreateFrame("Frame")
        recorder:SetScript("OnEvent", OnCast)
        recorder:SetScript("OnUpdate", RecordFrame)
    end
    Settings().vignetteRadarNavLog = {}
    armed, recording = true, nil
    recorder:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    Say("Nav recorder armed. Surge while skyriding (up to " .. NAV_LOG_MAX .. " times), then /reload.")
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "NAVIGATION_FRAME_CREATED", "NAVIGATION_FRAME_DESTROYED",
    "SUPER_TRACKING_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then inCombat = true; return end
    if event == "PLAYER_REGEN_ENABLED" then inCombat = false; return end
    -- Next frame: World Focus updates its own state on the same events.
    if C_Timer and C_Timer.After then C_Timer.After(0, Marker.Refresh) else Marker.Refresh() end
end)
