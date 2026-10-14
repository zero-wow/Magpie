local _, addon = ...
if type(addon) ~= "table" then return end

local PANEL_W, PANEL_H = 246, 278
local ZOOM_FOOTER_H = 26
local HEADER_H, FIELD_SIZE = 34, 200
local FIELD_RADIUS = (FIELD_SIZE / 2) - 9
local PLOT_RADIUS = FIELD_RADIUS - 15
local LAYOUTS = {
    classic = { width = 246, height = 278, field = 200, footer = 26, focus = 46 },
    squat = { width = 374, height = 230, field = 184 },
    compact = { width = 210, height = 260, field = 164, footer = 50, focus = 64 },
}
local LAUNCHER_DIMENSIONS = { width = 140, height = 64 }
local LAUNCHER_RADIUS, LAUNCHER_RANGE = 16, 150
local HEADING_HALF_WIDTH = 4
local SLOW_UPDATE_MS, STALLED_UPDATE_MS = 50, 250
local MAX_BLIPS = 64
local MAX_QUEST_DOTS = 64
local MAX_QUEST_BLOB_CANVAS = 4096
local MAX_MAP_NOTES = 48
local TRAIL_STYLES = addon.VignetteRadarTrailStyles
local TRAIL_STYLE_BY_ID = addon.VignetteRadarTrailStyleByID
local TRAIL_SETTING_VALUES = addon.VignetteRadarTrailSettingValues or {
    vignetteRadarTrailSpacing = { .5, .65, .75, 1, 1.25, 1.5, 2 },
    vignetteRadarTrailSpeed = { 0, .25, .5, .75, 1, 1.25, 1.5, 2, 3, 4 },
    vignetteRadarTrailSize = { .1, .25, .5, .75, 1, 1.25, 1.5, 2 },
}
local TRAIL_SPACINGS = TRAIL_SETTING_VALUES.vignetteRadarTrailSpacing
local TRAIL_SPEEDS = TRAIL_SETTING_VALUES.vignetteRadarTrailSpeed
local TRAIL_LIFETIMES = { 1, 300 }
local ACCENT = { 0.05, 0.82, 0.62 }
local RED = { 1, 0.18, 0.14 }
local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local QUEST_DIAMOND_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga"
addon.VignetteRadarQuestHollowTexture = "Interface\\AddOns\\Magpie\\Media\\quest-diamond-hollow.tga"
local SQUARE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local ROUNDED_SQUARE_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga"
local ROUNDED_BORDER_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\radar-rounded-border.tga"
local ROUNDED_CONTROL_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\control-rounded-square.tga"
local QUEST_CLIP_INSET = 4
local QUEST_AREA_BLUE = { .34, .60, 1 }
local TASK_AREA_COLORS = {
    world = { .35, .81, 1 },
    bonus = { .78, .57, 1 },
}
local QUEST_COLORS = {
    { 87/255, 153/255, 255/255 }, { 255/255, 179/255, 87/255 },
    { 181/255, 150/255, 255/255 }, { 255/255, 120/255, 133/255 },
    { 110/255, 199/255, 255/255 }, { 126/255, 129/255, 255/255 },
    { 245/255, 153/255, 212/255 }, { 255/255, 145/255, 82/255 },
}
addon.VignetteRadarQuestColors = QUEST_COLORS
local SKULL_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local TWO_PI = math.pi * 2
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local Unpack = unpack or table.unpack

local panel, launcher
local Morph = { running = false }
local launcherPeekActive = false
local radarPeekActive, radarPeekPreviousManual, radarPeekPreviousPosition
local EndLauncherPeek
local trailPopup, HideTrailPopup, ToggleTrailPopup, RefreshTrailPopup
local routeMenu = {}
function routeMenu.SetTrackedRouteTexture(texture, kind, state)
    local column = kind == "rare" and 0 or kind == "treasure" and 1
        or kind == "quest" and 2 or kind == "zygor" and 3
    if column then
        local row = state or 0
        texture:SetTexture("Interface\\AddOns\\Magpie\\Media\\radar-route-types.tga")
        texture:SetTexCoord((column * 64 + 1) / 256, (column * 64 + 63) / 256,
            (row * 64 + 1) / 256, (row * 64 + 63) / 256)
    end
end
function routeMenu.TrackedRouteColor(kind)
    local style = addon.VignetteRadarStyle
    if style and style.Color then
        return style.Color(kind == "zygor" and "accent" or kind)
    end
    return ACCENT[1], ACCENT[2], ACCENT[3]
end
local preview = false
local manualPanelState
local activeTargets = {}
local activeQuests = {}
local questColorByID, questColorMapID = {}, nil
local activeMapNotes = {}
local mapNotesMapID, mapNotesSource, mapNotesUpdatedAt
local questMapBasis
local activeMapID
local activeWorldMapMode
local followedQuestID, followedQuestMapID
local pulseUntil = 0
local approachPulseKey, approachPulseUntil
local displayedRange
local clusterHoverKey, clusterHoverUntil
local RefreshRadar, ScanVignettes, Render, UpdateLauncher, EnsureLauncher, ApplyAppearance
local function RefreshZygorVisual() if RefreshRadar then RefreshRadar(false) end end
local PREVIEW_TARGETS = {
    { key = "preview-rare", x = 28, y = 52, launcherX = 3, launcherY = 6,
        distanceFactor = 0.34, name = "Sample rare", category = "rare", sample = true },
    { key = "preview-treasure", x = -58, y = -14, launcherX = -6, launcherY = -2,
        distanceFactor = 0.58, name = "Sample treasure", category = "treasure", atlasName = "VignetteLoot", sample = true },
    { key = "preview-event", x = 49, y = -45, launcherX = 5, launcherY = -5,
        distanceFactor = 0.52, name = "Sample event", category = "event", sample = true },
    { key = "preview-boss", x = -18, y = -50, launcherX = -4, launcherY = -6,
        distanceFactor = 0.70, name = "Sample world boss", category = "rare", isWorldBoss = true, sample = true },
}

local function Settings()
    return addon.GetSettings()
end

function addon.VignetteRadarRenderSeconds(settings)
    local mode = (settings or Settings()).vignetteRadarPerformance
    if addon.VignetteRadarBudget and addon.VignetteRadarBudget.softThrottle then
        return .25
    end
    return mode == "low" and .25 or mode == "balanced" and .15 or .1
end

function addon.VignetteRadarScanSeconds(settings)
    local mode = (settings or Settings()).vignetteRadarPerformance
    if addon.VignetteRadarBudget and addon.VignetteRadarBudget.softThrottle then
        return 2.5
    end
    return mode == "low" and 2.5 or mode == "balanced" and 1.5 or 1
end

local function CircleOnly()
    return Settings().vignetteRadarCircleOnly == true and not radarPeekActive
end

local function DrawTrailGlyph(definition, primary, extras, frame, x, y, ux, uy, r, g, b, alpha, index, sizeScale, facing)
    sizeScale = sizeScale or 1
    if definition.dot or definition.square then
        local size = definition.alternating and (index % 2 == 0 and 3 or 6)
            or definition.dot or definition.square
        primary:SetSize(size * sizeScale, size * sizeScale)
        primary:SetVertexColor(r, g, b, alpha)
        primary:ClearAllPoints()
        primary:SetPoint("CENTER", frame, "CENTER", x, y)
        if facing then addon.VignetteRadarTurn.TrackPoint(primary, x, y, facing) end
        primary:Show()
        return
    end
    local scale = (definition.alternating and (index % 2 == 0 and .48 or 1) or 1) * sizeScale
    for part, segment in ipairs(definition.segments) do
        local line = part == 1 and primary or extras[part - 1]
        local x1, y1 = segment[1] * scale, segment[2] * scale
        local x2, y2 = segment[3] * scale, segment[4] * scale
        line:SetThickness(segment[5] * sizeScale)
        line:SetColorTexture(r, g, b, alpha)
        local startX, startY = x + ux*x1 - uy*y1, y + uy*x1 + ux*y1
        local endX, endY = x + ux*x2 - uy*y2, y + uy*x2 + ux*y2
        line:SetStartPoint("CENTER", frame, startX, startY)
        line:SetEndPoint("CENTER", frame, endX, endY)
        if facing then addon.VignetteRadarTurn.TrackLine(line, startX, startY, endX, endY, facing) end
        line:Show()
    end
end

-- Shared with UI/LeadTrail.lua so Lead marks are drawn by the same glyph code.
addon.VignetteRadarTrailGlyph = DrawTrailGlyph

local function TrailFadeMultiplier(progress, amount, span)
    if amount <= 0 or span <= 0 then return 1 end
    local faded = math.max(0, math.min(1, (progress - (1 - span)) / span))
    return 1 - amount * faded
end

local function ViewFacing(facing)
    return Settings().vignetteRadarNorthUp == true and 0 or facing
end

local function PreviewPosition(x, y)
    local angle = Settings().vignetteRadarNorthUp == true and 0.65 or 0
    return x * math.cos(angle) - y * math.sin(angle), x * math.sin(angle) + y * math.cos(angle)
end

local function DrawPlayerHeading(line, frame, facing, innerRadius, outerRadius)
    local angle = facing - ViewFacing(facing)
    local x, y = -math.sin(angle), math.cos(angle)
    line:SetStartPoint("CENTER", frame, x * innerRadius, y * innerRadius)
    line:SetEndPoint("CENTER", frame, x * outerRadius, y * outerRadius)
end

local function DrawLauncherChevron(lines, frame, facing)
    local angle = facing - ViewFacing(facing)
    local forwardX, forwardY = -math.sin(angle), math.cos(angle)
    local rightX, rightY = math.cos(angle), math.sin(angle)
    for index = 1, 2 do
        local side = index == 1 and -1 or 1
        local line = lines[index]
        line:SetStartPoint("CENTER", frame,
            forwardX * 3 + rightX * side * 2, forwardY * 3 + rightY * side * 2)
        line:SetEndPoint("CENTER", frame, forwardX * 6, forwardY * 6)
    end
end

local function DrawPlayerChevron(lines, frame, facing)
    local angle = facing - ViewFacing(facing)
    local base = Settings().vignetteRadarChevronDistance or 4
    local tip = base + 5
    local forwardX, forwardY = -math.sin(angle), math.cos(angle)
    local rightX, rightY = math.cos(angle), math.sin(angle)
    for index, line in ipairs(lines) do
        local side = index == 1 and -1 or 1
        line:SetStartPoint("CENTER", frame, forwardX * base + rightX * HEADING_HALF_WIDTH * side,
            forwardY * base + rightY * HEADING_HALF_WIDTH * side)
        line:SetEndPoint("CENTER", frame, forwardX * tip, forwardY * tip)
    end
end

local function HeadingGeometry(radius)
    local tip = (Settings().vignetteRadarChevronDistance or 4) + 5
    return tip, math.max(tip + 2, radius * (Settings().vignetteRadarHeadingLength or .30))
end

local function Ranges()
    return addon.VignetteRadarRanges or { 10, 25, 50, 100, 150, 300, 450, 600, 1200, 2400, 4800 }
end

local function StepRange(step)
    local ranges, current = Ranges(), displayedRange or Settings().vignetteRadarRange
    -- The Minimap Underlay snaps the drawn range to a map zoom, often off
    -- this list: step to the next entry that draws a different range.
    local underlay = addon.VignetteRadarMinimapUnderlay
    local first, last, dir = 1, #ranges, 1
    if step < 0 then first, last, dir = #ranges, 1, -1 end
    for index = first, last, dir do
        local value = ranges[index]
        if (dir > 0 and value > current) or (dir < 0 and value < current) then
            local shown = underlay and underlay.Snap and underlay.Snap(value, panel) or value
            if shown ~= current then
                addon.SetVignetteRadarRange(value)
                return
            end
        end
    end
end

local function OnZoomWheel(_, delta)
    if delta > 0 then StepRange(-1) elseif delta < 0 then StepRange(1) end
end

local function Features()
    return addon.VignetteRadarFeatures
end

local function Now()
    return GetTime and GetTime() or 0
end

local function Quiet()
    return not preview and Features() and Features().IsQuiet() or false
end

local function VisuallyQuiet()
    return not preview and Features() and Features().IsVisuallyQuiet() or false
end

local function Ignored(target)
    return Features() and Features().IsIgnored(target) or false
end

local function Favorite(target)
    if target.favorite ~= nil then return target.favorite == true end
    return Features() and Features().IsFavorite(target) or false
end

local function TargetAlpha(target)
    if not target.stale then return 1 end
    local duration = math.max(1, (target.expiresAt or 0) - (target.lastSeenAt or 0))
    return math.max(0, math.min(0.65, ((target.expiresAt or 0) - Now()) / duration * 0.65))
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

local SafeField
do
    -- One static indexer keeps protected reads from allocating a closure.
    local function Index(object, key) return object[key] end
    SafeField = function(object, key)
        if object == nil or IsSecret(object) then return nil end
        local ok, value = pcall(Index, object, key)
        if not ok or IsSecret(value) then return nil end
        return value
    end
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function SafeString(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function SafeBoolean(value)
    if IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

-- Repeating work can be suspended for this session if it starts consuming a
-- frame budget. No SavedVariable is changed, and direct controls still work.
addon.VignetteRadarBudget = { paused = {}, recent = {} }
local function ProfileTime()
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, value = pcall(debugprofilestop)
    return ok and SafeNumber(value) or nil
end

local function CheckUpdateBudget(owner, started, label)
    local finished = ProfileTime()
    if not (started and finished and finished >= started) then return end
    local duration = finished - started
    if duration >= STALLED_UPDATE_MS then
        owner._slowUpdates = 3
    elseif duration >= SLOW_UPDATE_MS then
        owner._slowUpdates = (owner._slowUpdates or 0) + 1
    else
        owner._slowUpdates = 0
    end
    if not owner._budgetWindowStart or finished < owner._budgetWindowStart then
        owner._budgetWindowStart, owner._budgetWindowCost = started, 0
    end
    owner._budgetWindowCost = (owner._budgetWindowCost or 0) + duration
    if finished - owner._budgetWindowStart >= 1000 then
        local recent = owner._budgetWindowCost * 1000
            / math.max(1000, finished - owner._budgetWindowStart)
        addon.VignetteRadarBudget.recent[label] = recent
        if label == "radar" then
            if recent >= 30 and not addon.VignetteRadarBudget.softThrottle then
                owner._heavyWindows = (owner._heavyWindows or 0) + 1
                if owner._heavyWindows >= 3 then
                    addon.VignetteRadarBudget.softThrottle = true
                    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                        DEFAULT_CHAT_FRAME:AddMessage("Magpie switched to Low CPU updates after sustained high workload. It will restore your selected rate when the load settles.")
                    end
                end
            else
                owner._heavyWindows = 0
            end
        end
        -- Let whichever updater is active prove that the load has settled.
        -- The launcher/background can recover the rate while the radar is hidden.
        if label == "radar" or not (panel and panel:IsShown()) then
            if addon.VignetteRadarBudget.softThrottle and recent <= 10
                and not next(addon.VignetteRadarBudget.paused) then
                owner._quietWindows = (owner._quietWindows or 0) + 1
                if owner._quietWindows >= 10 then
                    addon.VignetteRadarBudget.softThrottle = false
                    owner._quietWindows = 0
                    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                        DEFAULT_CHAT_FRAME:AddMessage("Magpie restored your selected update rate after the load settled.")
                    end
                end
            else owner._quietWindows = 0 end
        else owner._quietWindows = 0 end
        if recent <= 10 then
            owner._stableWindows = (owner._stableWindows or 0) + 1
            if owner._stableWindows >= 20 then owner._budgetTrips = 0 end
        else owner._stableWindows = 0 end
        if owner._budgetWindowCost >= 300 then owner._slowUpdates = 3 end
        owner._budgetWindowStart, owner._budgetWindowCost = finished, 0
    end
    if owner._slowUpdates < 3 then return end
    local update = owner:GetScript("OnUpdate")
    if not update then return end
    addon.VignetteRadarBudget.softThrottle = true
    owner._quietWindows = 0
    if not (C_Timer and type(C_Timer.After) == "function") then
        owner._slowUpdates = 0
        return -- Never leave updates paused without a recovery timer.
    end
    owner._budgetTrips = (owner._budgetTrips or 0) + 1
    local delay = math.floor(math.min(120, 10 * 2 ^ math.min(4, owner._budgetTrips - 1)))
    owner._budgetUpdate = update
    owner:SetScript("OnUpdate", nil)
    addon.VignetteRadarBudget.paused[label] = true
    local message = "Magpie paused automatic " .. label
        .. " updates after excessive CPU time. Retrying in " .. delay .. " seconds."
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    elseif print then
        print(message)
    end
    C_Timer.After(delay, function()
        if not addon.VignetteRadarBudget.paused[label]
            or owner._budgetUpdate ~= update then return end
        owner._slowUpdates, owner._heavyWindows = 0, 0
        owner._budgetWindowStart, owner._budgetWindowCost = nil, 0
        owner._budgetUpdate = nil
        addon.VignetteRadarBudget.paused[label] = nil
        owner:SetScript("OnUpdate", update)
    end)
end

local function Call(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, first, second, third, fourth = pcall(func, ...)
    if not ok then return nil end
    return first, second, third, fourth
end

local function ReadXY(vector)
    if vector == nil or IsSecret(vector) then return nil end
    local x, y = SafeNumber(SafeField(vector, "x")), SafeNumber(SafeField(vector, "y"))
    if x and y then return x, y end
    local getXY = SafeField(vector, "GetXY")
    if type(getXY) ~= "function" then return nil end
    local ok, vx, vy = pcall(getXY, vector)
    if not ok then return nil end
    return SafeNumber(vx), SafeNumber(vy)
end

local function MapVector(x, y)
    local vector = type(CreateVector2D) == "function" and Call(CreateVector2D, x, y) or nil
    return vector or { x = x, y = y }
end

local function MapToWorld(mapID, mapPosition)
    if not (C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local instanceID, worldPosition = Call(C_Map.GetWorldPosFromMapPos, mapID, mapPosition)
    local worldX, worldY = ReadXY(worldPosition)
    if not worldX or not worldY then return nil end
    return worldX, worldY, SafeNumber(instanceID)
end

local function CurrentMapID()
    return C_Map and C_Map.GetBestMapForUnit
        and SafeNumber(Call(C_Map.GetBestMapForUnit, "player")) or nil
end

local function PlayerSnapshot(mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local mapPosition = Call(C_Map.GetPlayerMapPosition, mapID, "player")
    local mapX, mapY = ReadXY(mapPosition)
    if not mapX or not mapY then return nil end
    local worldX, worldY, instanceID = MapToWorld(mapID, mapPosition)
    if not worldX or not worldY then return nil end
    local facing = GetPlayerFacing and SafeNumber(Call(GetPlayerFacing)) or nil
    return {
        mapID = mapID,
        mapX = mapX,
        mapY = mapY,
        worldX = worldX,
        worldY = worldY,
        instanceID = instanceID,
        facing = facing or 0,
        headingAvailable = facing ~= nil,
    }
end

local function DisplayableVignetteInfo(info, includeWorldMap)
    if info == nil or SafeBoolean(SafeField(info, "isDead")) == true then return false end
    if SafeBoolean(SafeField(info, "onMinimap")) == true then return true end
    return includeWorldMap == true and SafeBoolean(SafeField(info, "onWorldMap")) == true
        and SafeBoolean(SafeField(info, "inFogOfWar")) == false
end

local function ClassifyVignette(info)
    local vignetteType = SafeField(info, "type")
    local vignetteTypes = Enum and Enum.VignetteType
    if vignetteTypes then
        if vignetteTypes.Treasure ~= nil and vignetteType == vignetteTypes.Treasure then return "treasure" end
        if vignetteTypes.Rare ~= nil and vignetteType == vignetteTypes.Rare then return "rare" end
        if vignetteTypes.Event ~= nil and vignetteType == vignetteTypes.Event then return "event" end
    end

    local atlasName = (SafeString(SafeField(info, "atlasName")) or ""):lower()
    if atlasName:find("treasure", 1, true) or atlasName:find("chest", 1, true)
        or atlasName:find("container", 1, true) or atlasName:find("loot", 1, true) then
        return "treasure"
    end
    if atlasName:find("rare", 1, true) or atlasName:find("vignettekill", 1, true)
        or atlasName:find("skull", 1, true) then
        return "rare"
    end
    if atlasName:find("event", 1, true) or atlasName:find("horn", 1, true) then
        return "event"
    end
    return "other"
end

local function CollectVignettes(mapID, player)
    local targets = {}
    if not (mapID and C_VignetteInfo and C_VignetteInfo.GetVignettes
        and C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignettePosition) then
        return targets
    end
    local vignetteGUIDs = Call(C_VignetteInfo.GetVignettes)
    if IsSecret(vignetteGUIDs) or type(vignetteGUIDs) ~= "table" then return targets end
    local includeWorldMap = Settings().vignetteRadarWorldMap ~= false
    local parentMapID = C_Map and C_Map.GetMapInfo and SafeNumber(SafeField(
        Call(C_Map.GetMapInfo, mapID), "parentMapID"))
    -- Honor maps where Blizzard explicitly suppresses world-map vignette pins.
    if includeWorldMap and C_Map.GetMapInfo and FlagsUtil and FlagsUtil.IsSet and Enum and Enum.UIMapFlag then
        local flags = SafeNumber(SafeField(Call(C_Map.GetMapInfo, mapID), "flags"))
        local hiddenFlag = SafeNumber(Enum.UIMapFlag.HideVignettes)
        if flags and hiddenFlag and Call(FlagsUtil.IsSet, flags, hiddenFlag) == true then includeWorldMap = false end
    end
    for index = 1, math.min(#vignetteGUIDs, 512) do
        local guid = vignetteGUIDs[index]
        if guid ~= nil and not IsSecret(guid) then
            local info = Call(C_VignetteInfo.GetVignetteInfo, guid)
            if info and SafeBoolean(SafeField(info, "isDead")) == true
                and addon.VignetteRadarOutcomeLearning then
                addon.VignetteRadarOutcomeLearning.OnDeadVignette(guid, info)
            end
            if info and SafeBoolean(SafeField(info, "isDead")) == true
                and addon.VignetteRadarRecent then
                local kind = ClassifyVignette(info)
                if kind == "rare" or kind == "treasure"
                    or (Features() and Features().IsWorldBoss(info)) then
                    addon.VignetteRadarRecent.RecordNPCGuid(SafeString(SafeField(info, "objectGUID")))
                end
            end
            if DisplayableVignetteInfo(info, includeWorldMap) then
                local mapPosition = Call(C_VignetteInfo.GetVignettePosition, guid, mapID)
                local mapX, mapY = ReadXY(mapPosition)
                local positionMapID = mapID
                if not (mapX and mapY) and parentMapID then
                    -- Some Blizzard world-map pins are positioned only on a
                    -- parent zone map, even while the player is in its child.
                    mapPosition = Call(C_VignetteInfo.GetVignettePosition, guid, parentMapID)
                    mapX, mapY = ReadXY(mapPosition)
                    positionMapID = parentMapID
                end
                local worldX, worldY, instanceID
                if mapX and mapY then
                    worldX, worldY, instanceID = MapToWorld(positionMapID, mapPosition)
                end
                if mapX and mapY and worldX and worldY then
                    local worldBoss = Features() and Features().IsWorldBoss(info) or false
                    local groupMin, groupMax
                    if C_VignetteInfo.GetRecommendedGroupSize then
                        local minimum, maximum = Call(C_VignetteInfo.GetRecommendedGroupSize, guid)
                        groupMin, groupMax = SafeNumber(minimum), SafeNumber(maximum)
                    end
                    targets[#targets + 1] = {
                        key = tostring(guid),
                        vignetteID = SafeNumber(SafeField(info, "vignetteID")),
                        objectGUID = SafeString(SafeField(info, "objectGUID")),
                        rewardQuestID = SafeNumber(SafeField(info, "rewardQuestID")),
                        isDead = SafeBoolean(SafeField(info, "isDead")),
                        mapID = positionMapID,
                        mapX = mapX,
                        mapY = mapY,
                        name = SafeString(SafeField(info, "name")) or "Detected vignette",
                        category = worldBoss and "rare" or ClassifyVignette(info),
                        isWorldBoss = worldBoss,
                        source = SafeBoolean(SafeField(info, "onMinimap")) == true and "minimap" or "worldMap",
                        vignetteType = SafeField(info, "type"),
                        atlasName = SafeString(SafeField(info, "atlasName")),
                        worldX = worldX,
                        worldY = worldY,
                        instanceID = instanceID,
                        groupMin = groupMin, groupMax = groupMax,
                    }
                    -- Collect beyond the visible pool so ignored entries cannot starve useful ones.
                end
            end
        end
    end
    -- Nearby entries get first claim on the bounded state pool in crowded zones.
    if player == nil then player = PlayerSnapshot(mapID) end
    for _, target in ipairs(targets) do
        target.favorite = Features() and Features().IsFavorite(target) or false
        if player and (not player.instanceID or not target.instanceID or player.instanceID == target.instanceID) then
            local dx, dy = target.worldX - player.worldX, target.worldY - player.worldY
            target.distance = math.sqrt(dx * dx + dy * dy)
        end
    end
    table.sort(targets, function(left, right)
        if left.favorite ~= right.favorite then return left.favorite end
        if left.source ~= right.source then return left.source == "minimap" end
        if left.isWorldBoss ~= right.isWorldBoss then return left.isWorldBoss end
        if left.distance ~= right.distance then return (left.distance or math.huge) < (right.distance or math.huge) end
        return left.key < right.key
    end)
    return targets
end

local function CollectQuests(mapID, force)
    local quests = {}
    local db = Settings()
    if not (mapID and C_QuestLog
        and (C_QuestLog.GetQuestsOnMap or C_TaskQuest and C_TaskQuest.GetQuestsOnMap)
        and (force or db.vignetteRadarQuestDots or db.vignetteRadarQuestAreas
            or (db.vignetteRadarBeaconsEnabled and db.vignetteRadarBeaconQuests)
            or db.vignetteRadarWorldFocusEnabled)) then
        return quests
    end
    -- A live read through Data/QuestService.lua (the radar keeps its own
    -- five-second cache); the quest tracker then reuses it in this frame.
    local onMap = addon.Quests.OnMap(mapID, true)
    local records = onMap.quests
    local seen = {}
    local seenQuest = {}
    local function QuestType(questID, taskRecord)
        if SafeBoolean(Call(C_QuestLog.IsWorldQuest, questID)) == true
            or SafeBoolean(SafeField(taskRecord, "isWorldQuest")) == true then
            return "world"
        end
        if taskRecord or SafeBoolean(Call(C_QuestLog.IsQuestTask, questID)) == true then
            return "bonus"
        end
    end
    local function AddPoint(questID, x, y, name, nextStep, learned, objectiveText, taskRecord)
        if not (questID and questID > 0 and x and y and x >= 0 and x <= 1
            and y >= 0 and y <= 1) then return end
        -- A quest may have several objective locations on one map. Only fold
        -- identical coordinates, not every record with the same quest ID.
        local coordinate = math.floor(x * 100000 + .5) .. ":" .. math.floor(y * 100000 + .5)
        seen[questID] = seen[questID] or {}
        if seen[questID][coordinate] then
            local taskType = taskRecord and QuestType(questID, taskRecord)
            if taskType then
                for _, existing in ipairs(quests) do
                    if existing.questID == questID and existing.mapX == x and existing.mapY == y then
                        existing.taskType = taskType
                        break
                    end
                end
            end
            return
        end
        local worldX, worldY, instanceID = MapToWorld(mapID, MapVector(x, y))
        if not (worldX and worldY) then return end
        seen[questID][coordinate] = true
        seenQuest[questID] = true
        quests[#quests + 1] = {
            questID = questID, mapID = mapID, mapX = x, mapY = y, nextStep = nextStep,
            learned = learned, objectiveText = objectiveText,
            taskType = QuestType(questID, taskRecord),
            worldX = worldX, worldY = worldY, instanceID = instanceID,
            completed = SafeBoolean(Call(C_QuestLog.IsComplete, questID)) == true,
            name = name or SafeString(Call(C_QuestLog.GetTitleForQuestID, questID))
                or "Quest location",
        }
    end
    for index = 1, math.min(#records, 256) do
        local record = records[index]
        local questID = SafeNumber(SafeField(record, "questID"))
        local x, y = SafeNumber(SafeField(record, "x")), SafeNumber(SafeField(record, "y"))
        if questID and questID > 0 and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            local nextStep
            if db.vignetteRadarNextQuestStep and index <= 64 and not seenQuest[questID]
                and addon.VignetteRadarQuestData then
                nextStep = addon.VignetteRadarQuestData.GetNextStep(questID, mapID)
            end
            local pointX, pointY = x, y
            if nextStep and nextStep.onCurrentMap and nextStep.x and nextStep.y then
                pointX, pointY = nextStep.x, nextStep.y
            end
            local name = SafeString(SafeField(record, "name"))
            local before = #quests
            AddPoint(questID, pointX, pointY, name, nextStep)
            if #quests == before and (pointX ~= x or pointY ~= y) then
                AddPoint(questID, x, y, name, nil)
            end
        end
    end
    -- Task quests are not consistently included in the ordinary quest map API.
    for _, record in ipairs(onMap.tasks) do
        AddPoint(record.questID, record.x, record.y, record.name, nil, nil, nil, record)
    end
    -- Blizzard can provide a waypoint for a watched quest even when its
    -- quest-level map record is absent. Keep that objective and its blob visible.
    if C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex
        and C_QuestLog.GetNextWaypointForMap then
        for _, questID in ipairs(addon.Quests.WatchedIDs(false, true)) do
            if questID > 0 and not seenQuest[questID] then
                local x, y = Call(C_QuestLog.GetNextWaypointForMap, questID, mapID)
                x, y = SafeNumber(x), SafeNumber(y)
                if x and y then
                    AddPoint(questID, x, y)
                elseif db.vignetteRadarLearnedQuestHints
                    and addon.VignetteRadarOutcomeLearning then
                    local hint = addon.VignetteRadarOutcomeLearning.GetQuestHint(questID, mapID)
                    if hint then
                        AddPoint(questID, hint.mapX, hint.mapY, nil, nil,
                            true, hint.text)
                    end
                end
            end
        end
    end
    if questColorMapID ~= mapID then questColorByID, questColorMapID = {}, mapID end
    local present, used = {}, {}
    for _, quest in ipairs(quests) do present[quest.questID] = true end
    for questID, slot in pairs(questColorByID) do
        if present[questID] then used[slot] = true else questColorByID[questID] = nil end
    end
    for _, quest in ipairs(quests) do
        local slot = questColorByID[quest.questID]
        if not slot then
            for candidate = 1, #QUEST_COLORS do
                if not used[candidate] then slot = candidate; break end
            end
            slot = slot or (quest.questID % #QUEST_COLORS) + 1
            questColorByID[quest.questID] = slot
            used[slot] = true
        end
        quest.colorSlot = slot
    end
    return quests
end


local function NormalizeAngle(angle)
    angle = angle % TWO_PI
    if angle > math.pi then angle = angle - TWO_PI end
    return angle
end

local function Project(dx, dy, distance, facing, pixelRadius, rangeYards)
    if not (SafeNumber(dx) and SafeNumber(dy) and SafeNumber(distance)
        and SafeNumber(facing) and SafeNumber(pixelRadius) and SafeNumber(rangeYards))
        or rangeYards <= 0 then return nil end
    local relative = NormalizeAngle(atan2(dy, dx) - facing)
    local radius = (distance / rangeYards) * pixelRadius
    return -math.sin(relative) * radius, math.cos(relative) * radius
end

addon.VignetteRadarTesting = {
    ClassifyVignette = ClassifyVignette,
    CollectVignettes = CollectVignettes,
    CollectQuests = CollectQuests,
    DisplayableVignetteInfo = DisplayableVignetteInfo,
    NormalizeAngle = NormalizeAngle,
    Project = Project,
}

local function Text(parent, size, value, accent)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size, "")
    label:SetTextColor(accent and ACCENT[1] or 0.88, accent and ACCENT[2] or 0.90,
        accent and ACCENT[3] or 0.92, 1)
    label:SetText(value or "")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function Surface(frame, alpha)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.045, 0.052, 0.06, alpha or 0.96)
    frame:SetBackdropBorderColor(1, 1, 1, 0.15)
end

local function AddRing(field, radius, alpha)
    local lines = {}
    for index = 1, 64 do
        local line = field:CreateLine(nil, "BORDER")
        local first = ((index - 1) / 64) * TWO_PI
        local last = (index / 64) * TWO_PI
        line:SetThickness(1)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], alpha)
        line:SetStartPoint("CENTER", field, math.cos(first) * radius, math.sin(first) * radius)
        line:SetEndPoint("CENTER", field, math.cos(last) * radius, math.sin(last) * radius)
        lines[index] = line
    end
    return lines
end

local function ResizeRing(lines, field, radius)
    for index, line in ipairs(lines) do
        local first, last = ((index - 1) / #lines) * TWO_PI, (index / #lines) * TWO_PI
        line:SetStartPoint("CENTER", field, math.cos(first) * radius, math.sin(first) * radius)
        line:SetEndPoint("CENTER", field, math.cos(last) * radius, math.sin(last) * radius)
    end
end

local function LegendAPI()
    return type(addon.VignetteRadarLegend) == "table" and addon.VignetteRadarLegend or nil
end

local function TargetPickerAPI()
    return type(addon.VignetteRadarTargetPicker) == "table" and addon.VignetteRadarTargetPicker or nil
end

local function CategoryEnabled(category)
    local legend = LegendAPI()
    if not (legend and type(legend.IsCategoryEnabled) == "function") then return true end
    local ok, enabled = pcall(legend.IsCategoryEnabled, category or "other")
    return not ok or enabled ~= false
end

local function CategoryColor(category)
    local legend = LegendAPI()
    if legend and type(legend.ColorFor) == "function" then
        local ok, r, g, b = pcall(legend.ColorFor, category or "other")
        if ok and SafeNumber(r) and SafeNumber(g) and SafeNumber(b) then return r, g, b end
    end
    return RED[1], RED[2], RED[3]
end

local function TargetColor(target)
    if target.isWorldBoss then
        if addon.VignetteRadarStyle then return addon.VignetteRadarStyle.Color("boss") end
        return RED[1], RED[2], RED[3]
    end
    return CategoryColor(target.category)
end

local function TargetKind(target)
    if target.isWorldBoss then return "World Boss" end
    if target.category == "rare" then return "Rare" end
    if target.category == "treasure" then return "Treasure" end
    if target.category == "event" then return "Event" end
    return "Other Detection"
end

local function HighlightCategory()
    local legend = LegendAPI()
    if not (legend and type(legend.GetHighlight) == "function") then return nil end
    local ok, category = pcall(legend.GetHighlight)
    return ok and SafeString(category) or nil
end

local function CategoryOpacity(category)
    local legend = LegendAPI()
    if legend and type(legend.OpacityFor) == "function" then
        local ok, alpha = pcall(legend.OpacityFor, category or "other")
        if ok and SafeNumber(alpha) then return alpha end
    end
    local highlight = HighlightCategory()
    return highlight and highlight ~= (category or "other") and 0.18 or 1
end

local function FocusedTargetKey()
    local picker = TargetPickerAPI()
    if not (picker and type(picker.GetFocus) == "function") then return nil end
    local ok, key = pcall(picker.GetFocus)
    return ok and SafeString(key) or nil
end

function addon.FocusedQuestID()
    local exploration = addon.VignetteRadarExploration
    if not (exploration and type(exploration.GetFocusedQuest) == "function") then return nil end
    local ok, id = pcall(exploration.GetFocusedQuest)
    return ok and SafeNumber(id) or nil
end

-- The clear center is a screen-space region. Its yard radius follows the
-- displayed range, so zooming changes the cutoff exactly as it changes the
-- distance represented by every radar pixel.
function addon.KeepCenterMarker(kind, key, distance, range)
    if Settings().vignetteRadarKeepCenterClear ~= true then return true end
    local questID, targetKey = addon.FocusedQuestID(), FocusedTargetKey()
    if questID then return kind == "quest" and key == questID end
    if targetKey then return kind == "target" and key == targetKey end
    local focus = addon.VignetteRadarWorldFocus
    if focus and type(focus.GetFocusedStep) == "function" then
        local ok, step = pcall(focus.GetFocusedStep)
        if ok and type(step) == "table" then
            local stepQuestID = SafeNumber(step.questID)
            if stepQuestID then return kind == "quest" and key == stepQuestID end
            local stepKey = SafeString(step.key)
            if stepKey then
                return (kind == "target" or kind == "note") and key == stepKey
            end
        end
    end
    if not (panel and SafeNumber(panel.plotRadius) and panel.plotRadius > 0
        and SafeNumber(distance) and SafeNumber(range) and range > 0) then return true end
    local clearPixels = math.min(32, panel.plotRadius * .38)
    return distance > range * clearPixels / panel.plotRadius
end

local function TargetVisible(target)
    if not (target and CategoryEnabled(target.category)) or Ignored(target) or TargetAlpha(target) <= 0 then return false end
    if addon.VignetteRadarLensActive and target.category ~= addon.VignetteRadarLensActive then return false end
    if Settings().vignetteRadarKeepCenterClear and addon.FocusedQuestID() then return false end
    local focusedKey = FocusedTargetKey()
    return not focusedKey or focusedKey == target.key
end

local SelectableTargets
do
    -- Render, the picker and the launcher ask for this list several times per
    -- frame. Reuse it until the frame, the spatial generation or preview changes.
    local memo = {}
    SelectableTargets = function()
        local frameTime, generation = Now(), addon._spatialGeneration
        if memo.output and memo.at == frameTime and memo.generation == generation
            and memo.preview == preview then
            return memo.output
        end
        local output = {}
        local player = not preview and PlayerSnapshot(CurrentMapID()) or nil
        local source = preview and PREVIEW_TARGETS or addon.VignetteRadarPoints.Refs("live")
        local previewRange = tonumber(Settings().vignetteRadarRange) or 450
        for _, target in ipairs(source) do
            if CategoryEnabled(target.category) and not Ignored(target) and TargetAlpha(target) > 0 then
                if preview then
                    target.distance = previewRange * target.distanceFactor
                elseif player and not (player.instanceID and target.instanceID and player.instanceID ~= target.instanceID) then
                    local dx, dy = target.worldX - player.worldX, target.worldY - player.worldY
                    target.distance = math.sqrt((dx * dx) + (dy * dy))
                else
                    target.distance = nil
                end
                target.red, target.green, target.blue = TargetColor(target)
                output[#output + 1] = target
            end
        end
        table.sort(output, function(left, right)
            if Favorite(left) ~= Favorite(right) then return Favorite(left) end
            if (left.stale == true) ~= (right.stale == true) then return not left.stale end
            if (left.isWorldBoss == true) ~= (right.isWorldBoss == true) then return left.isWorldBoss == true end
            if type(left.distance) == "number" and type(right.distance) == "number" and left.distance ~= right.distance then
                return left.distance < right.distance
            end
            return (left.name or left.key or "") < (right.name or right.key or "")
        end)
        memo.output, memo.at, memo.generation, memo.preview = output, frameTime, generation, preview
        return output
    end
end

-- The same explicit gestures work on the radar and in the target list.
function addon.HandleVignetteClick(target, button)
    if not target then return false end
    local shift = IsShiftKeyDown and IsShiftKeyDown()
    local alt = IsAltKeyDown and IsAltKeyDown()
    local ctrl = IsControlKeyDown and IsControlKeyDown()
    local features = Features()
    if ctrl and button ~= "RightButton" and not target.sample then
        local exploration = addon.VignetteRadarExploration
        if exploration then
            if alt then exploration.Watch(target)
            else
                local ok, reason = exploration.AddRouteStop(target)
                if not ok then exploration.Tell(reason) end
            end
        end
    elseif button == "RightButton" then
        if not features then return false end
        if not target.sample then features.Ignore(target, shift == true) end
    elseif shift and features then
        local ok, reason = features.Navigate(target)
        if not ok and reason then
            local messages = {
                ["not-live"] = "Navigation needs a current live detection.",
                ["no-map-position"] = "This detection has no usable map position.",
                ["waypoint-unavailable"] = "Navigation is unavailable on this map.",
                ["waypoint-failed"] = "The game could not set a waypoint for this detection.",
            }
            reason = messages[reason] or "This detection cannot be tracked right now."
            if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(reason, 1, 0.65, 0.25)
            elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Magpie: " .. reason) end
        end
        return ok, reason
    elseif alt and features then
        if not target.sample then features.ToggleFavorite(target) end
    else
        -- One selection for every view; clicking the focused target again
        -- clears it and the waypoint it placed.
        local focus = addon.VignetteRadarFocus
        focus.Toggle(focus.Target(target), { source = "radar" })
        return true
    end
    RefreshRadar(true)
    return true
end

local function ReconcileFocusedTarget()
    local picker = TargetPickerAPI()
    if picker and type(picker.ValidateTargets) == "function" then
        pcall(picker.ValidateTargets, SelectableTargets())
    end
end

local function UpdateTargetButton()
    if not (panel and panel.target) then return end
    local focusedKey = FocusedTargetKey()
    local red, green, blue = ACCENT[1], ACCENT[2], ACCENT[3]
    if focusedKey then
        for _, target in ipairs(SelectableTargets()) do
            if target.key == focusedKey then
                red, green, blue = TargetColor(target)
                break
            end
        end
    end
    panel.target.dot:SetVertexColor(red, green, blue, 1)
    panel.target.glow:SetVertexColor(red, green, blue,
        panel.target._hovered and .25 or focusedKey and .20 or .05)
    panel.target:SetAlpha((focusedKey or panel.target._hovered) and 1 or .68)
end

local function Tooltip(owner)
    local target = owner.target
    if not (target and GameTooltip) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(target.name or "Detected Vignette", 1, 1, 1)
    if owner.cluster and #owner.cluster > 1 then
        clusterHoverKey, clusterHoverUntil = owner.cluster[1].key, Now() + 2.5
        GameTooltip:AddLine(#owner.cluster .. " Nearby Detections", .52, .91, .77)
    elseif owner.clusterKey then
        clusterHoverKey, clusterHoverUntil = owner.clusterKey, Now() + 2.5
    end
    local r, g, b = TargetColor(target)
    local typeAndRange = TargetKind(target)
    if target.distance then
        typeAndRange = typeAndRange .. " · " .. math.floor(target.distance + 0.5) .. " yd"
    end
    GameTooltip:AddLine(typeAndRange, r, g, b)
    if target.groupMin and target.groupMin > 0 then
        local group = target.groupMax and target.groupMax > target.groupMin
            and (target.groupMin .. "–" .. target.groupMax) or tostring(target.groupMin)
        GameTooltip:AddLine("Suggested Group: " .. group, 0.85, 0.76, 0.53)
    end
    local legend = LegendAPI()
    local source = legend and legend.VignetteSource and legend.VignetteSource(target)
        or (target.stale and "lastSeen" or target.sample and "preview"
            or target.source == "worldMap" and "worldMap" or "minimap")
    local status = source == "worldMap" and "Map Location · Unconfirmed"
        or source == "preview" and "Preview"
        or source == "lastSeen" and ("Last Seen · "
            .. math.floor(math.max(0, Now() - (SafeNumber(target.lastSeenAt) or Now()))) .. "s Ago")
        or "Live Detection"
    if Favorite(target) then status = status .. " · Favorite" end
    local focused = FocusedTargetKey() == target.key
    if focused then status = status .. " · Focused" end
    if addon.VignetteRadarGuidance then addon.VignetteRadarGuidance.AddTooltipLines(GameTooltip, target) end
    GameTooltip:AddLine(status, .55, .86, .76)
    GameTooltip:AddLine(focused and "Click to Show All" or "Click to Focus", .65, .80, .77)
    GameTooltip:Show()
end

local SHAPES = {
    treasure = { { 0, 0.62 }, { 0.62, 0 }, { 0, -0.62 }, { -0.62, 0 } },
    event = { { -0.5, 0.5 }, { 0.5, 0.5 }, { 0.5, -0.5 }, { -0.5, -0.5 } },
}

-- Use Blizzard's own icons first (Points.Icon: the vignette's atlas, else
-- VignetteKill/Loot/Event), with vector fallbacks for missing client art.
local function StyleMarker(owner, dot, target, size, r, g, b)
    owner.shapeLines = owner.shapeLines or {}
    local icons = Settings().vignetteRadarShapes ~= false
    local points = icons and SHAPES[target.category] or nil
    local iconSize, nativeIcon = size, false
    if icons then
        local registry = addon.VignetteRadarPoints
        local icon = registry.Icon(target)
        if icon.atlas and registry.ApplyIcon(dot, icon, target, CIRCLE_TEXTURE).atlas then
            iconSize = size + (owner.isMini and 3 or 6) + (target.isWorldBoss and 2 or 0)
            nativeIcon, points = true, nil
        end
    end
    if not nativeIcon then
        dot:SetTexture(CIRCLE_TEXTURE)
        dot:SetTexCoord(0, 1, 0, 1)
    end
    if target.stale and not points then
        points = { { 0, 0.6 }, { 0.6, 0 }, { 0, -0.6 }, { -0.6, 0 } }
    end
    for index = 1, 4 do
        local line = owner.shapeLines[index]
        if points and points[index] then
            if not line then
                line = owner:CreateLine(nil, "OVERLAY")
                owner.shapeLines[index] = line
            end
            local first, last = points[index], points[index % #points + 1]
            line:SetThickness(size < 5 and 1 or 1.3)
            line:SetColorTexture(r, g, b, 1)
            line:SetStartPoint("CENTER", owner, first[1] * size, first[2] * size)
            line:SetEndPoint("CENTER", owner, last[1] * size, last[2] * size)
            line:Show()
        elseif line then line:Hide() end
    end
    dot:SetSize(points and math.max(2, size * 0.35) or iconSize, points and math.max(2, size * 0.35) or iconSize)
    -- Blizzard's icons keep their own colors; vector fallbacks take the category color.
    if nativeIcon then dot:SetVertexColor(1, 1, 1, 1)
    else dot:SetVertexColor(r, g, b, 1) end
    dot:SetShown(not target.stale)
end

local function DrawArrow(frame, x, y, r, g, b)
    local length = math.sqrt(x * x + y * y)
    if length < 0.001 then x, y, length = 0, 1, 1 end
    local ux, uy = x / length, y / length
    frame.lines = frame.lines or {}
    for index = 1, 2 do
        local line = frame.lines[index]
        if not line then line = frame:CreateLine(nil, "OVERLAY"); frame.lines[index] = line end
        local side = index == 1 and -1 or 1
        line:SetThickness(2)
        line:SetColorTexture(r, g, b, 1)
        line:SetStartPoint("CENTER", frame, ux * 5, uy * 5)
        line:SetEndPoint("CENTER", frame, -ux * 4 - uy * side * 4, -uy * 4 + ux * side * 4)
    end
end

local function AcquireBlip()
    local blip = table.remove(panel.freeBlips)
    if not blip then
        if #panel.blips >= MAX_BLIPS then return nil end
        blip = CreateFrame("Button", nil, panel.field)
        blip:SetSize(11, 11)
        blip:SetFrameLevel(panel.field:GetFrameLevel() + 4)
        blip.glow = blip:CreateTexture(nil, "BACKGROUND")
        blip.glow:SetAllPoints()
        blip.glow:SetTexture(CIRCLE_TEXTURE)
        blip.glow:SetVertexColor(RED[1], RED[2], RED[3], 0.28)
        blip.dot = blip:CreateTexture(nil, "ARTWORK")
        blip.dot:SetSize(6, 6)
        blip.dot:SetPoint("CENTER")
        blip.dot:SetTexture(CIRCLE_TEXTURE)
        blip.dot:SetVertexColor(RED[1], RED[2], RED[3], 1)
        blip.sourceBadge = blip:CreateTexture(nil, "OVERLAY")
        blip.sourceBadge:SetTexture("Interface\\Buttons\\WHITE8X8")
        blip.sourceBadge:SetSize(3, 3)
        blip.sourceBadge:SetPoint("BOTTOMRIGHT", blip, "BOTTOMRIGHT", -1, 1)
        blip.sourceBadge:Hide()
        blip:SetScript("OnEnter", Tooltip)
        blip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        blip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        blip:EnableMouseWheel(true)
        blip:SetScript("OnMouseWheel", OnZoomWheel)
        blip:SetScript("OnClick", function(self, button) addon.HandleVignetteClick(self.target, button) end)
        blip.favorite = Text(blip, 9, "*")
        blip.favorite:SetPoint("BOTTOMLEFT", blip, "TOPRIGHT", -3, -3)
        blip.favorite:SetTextColor(1, 0.82, 0.30, 1)
        blip.count = Text(blip, 8, "")
        blip.count:SetPoint("BOTTOM", blip, "TOP", 0, -2)
        blip.count:SetTextColor(1, 1, 1, 1)
        blip.count:Hide()
        panel.blips[#panel.blips + 1] = blip
    end
    blip:Show()
    return blip
end

local function ReleaseBlip(key, blip)
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == blip then GameTooltip:Hide() end
    panel.blipByKey[key] = nil
    blip.target = nil
    blip._seen = nil
    blip:Hide()
    blip:ClearAllPoints()
    panel.freeBlips[#panel.freeBlips + 1] = blip
end

local function BeginBlips()
    if not panel then return end
    for _, blip in pairs(panel.blipByKey) do blip._seen = false end
end

local function EndBlips()
    if not panel then return end
    local stale = {}
    for key, blip in pairs(panel.blipByKey) do
        if not blip._seen then stale[#stale + 1] = { key, blip } end
    end
    for _, entry in ipairs(stale) do ReleaseBlip(entry[1], entry[2]) end
end

local function ReleaseAllBlips()
    if not panel then return end
    local assigned = {}
    for key, blip in pairs(panel.blipByKey) do assigned[#assigned + 1] = { key, blip } end
    for _, entry in ipairs(assigned) do ReleaseBlip(entry[1], entry[2]) end
end

local function HideQuestDots()
    if not panel or not panel.questDots then return end
    for _, dot in ipairs(panel.questDots) do
        dot:Hide()
        if dot.halo then dot.halo:Hide() end
    end
end

local function AddQuestTooltipObjective(questID, hint)
    if not GameTooltip then return end
    local questData = addon.VignetteRadarQuestData
    local summary = questData and questData.GetObjectiveSummary
        and questData.GetObjectiveSummary(questID, hint)
    if summary and summary.label then
        GameTooltip:AddLine((summary.count and summary.count .. " " or "") .. summary.label,
            1, .86, .52, true)
        return
    end
    local exploration = addon.VignetteRadarExploration
    local lines = exploration and exploration.ObjectiveLines and exploration.ObjectiveLines(questID)
    local objective = lines and lines[1] or hint
    if objective then GameTooltip:AddLine(objective, 1, .86, .52, true) end
end

local function HideMapNotes()
    if not panel or not panel.mapNotes then return end
    for _, dot in ipairs(panel.mapNotes) do dot:Hide() end
end

local MAP_NOTE_COLOR = { treasure = "treasure", mob = "rare", item = "event",
    note = "other", entrance = "accent", guide = "quest", event = "event" }
local MAP_NOTE_LABEL = { treasure = "Treasure", mob = "Mob", item = "Item",
    note = "Note", entrance = "Entrance", guide = "Guide step",
    event = "Event", delve = "Delve", race = "Race" }
-- The note-vs-live identity rule lives in Core/Points.lua (loose form).
addon.VignetteRadarTesting.MapNoteMatchesLive = addon.VignetteRadarPoints.Matches

local function MapNoteMinimumDistance(range)
    return math.min(9, range * 0.1)
end
local function RenderMapNotes(player, range, targets)
    local settings = Settings()
    if not (player and (settings.vignetteRadarMapNotesVisible == true
        and (settings.vignetteRadarPOISource ~= "none" or settings.vignetteRadarSourceFusion)
        or settings.vignetteRadarWorldFocusZygor or settings.vignetteRadarAreaPOIs == true
        or settings.vignetteRadarRareSpawnNotes == true)) then
        HideMapNotes(); return 0
    end
    -- A 60-yard grid bounds duplicate checks even when the selected pack
    -- contains hundreds of notes and the radar redraws frequently.
    local live = {}
    for _, target in ipairs(targets or {}) do
        if not target.stale and (target.category == "rare" or target.category == "treasure")
            and TargetVisible(target)
            and not (player.instanceID and target.instanceID and player.instanceID ~= target.instanceID)
            and target.distance and target.distance <= range then
            local cellX, cellY = math.floor(target.worldX / 60), math.floor(target.worldY / 60)
            live[cellX] = live[cellX] or {}
            live[cellX][cellY] = live[cellX][cellY] or {}
            local bucket = live[cellX][cellY]
            bucket[#bucket + 1] = target
        end
    end
    local count = 0
    local minimumDistance = MapNoteMinimumDistance(range)
    local minimumDistanceSquared, rangeSquared = minimumDistance * minimumDistance, range * range
    for _, note in ipairs(activeMapNotes) do
        if count >= MAX_MAP_NOTES then break end
        local dx, dy = note.worldX - player.worldX, note.worldY - player.worldY
        local distanceSquared = dx * dx + dy * dy
        if (distanceSquared >= minimumDistanceSquared
            or settings.vignetteRadarKeepCenterClear
                and addon.KeepCenterMarker("note", note.key, 0, range))
            and distanceSquared <= rangeSquared
            and addon.KeepCenterMarker("note", note.key, math.sqrt(distanceSquared), range)
            and settings.vignetteRadarPOITypes[note.kind] ~= false
            -- Duplicate Icons: live area POIs the minimap already draws.
            and not (note.areaPoiID and panel._underlayHide
                and (panel._underlayHide.areaPOIs or panel._underlayHide.staticPOIs and not note.endsAt))
            and (not addon.VignetteRadarLensActive
                or (addon.VignetteRadarLensActive == "quest" and note.kind == "guide")
                or (addon.VignetteRadarLensActive == "rare" and note.kind == "mob")
                or (addon.VignetteRadarLensActive == "treasure"
                    and (note.kind == "treasure" or note.kind == "entrance")))
            and not (addon.VignetteRadarRecent and addon.VignetteRadarRecent.IsHidden(note, settings))
            and not (player.instanceID and note.instanceID and player.instanceID ~= note.instanceID) then
            local duplicate = false
            if note.kind == "mob" or note.kind == "treasure" then
                local cellX, cellY = math.floor(note.worldX / 60), math.floor(note.worldY / 60)
                for x = cellX - 1, cellX + 1 do
                    local column = live[x]
                    if column then
                        for y = cellY - 1, cellY + 1 do
                            local bucket = column[y]
                            if bucket then
                                for _, target in ipairs(bucket) do
                                    if addon.VignetteRadarTesting.MapNoteMatchesLive(note, target) then
                                        duplicate = true; break
                                    end
                                end
                            end
                            if duplicate then break end
                        end
                    end
                    if duplicate then break end
                end
            end
            if not duplicate then
                local distance = math.sqrt(distanceSquared)
                -- Area POIs always show Blizzard's own atlas.
                local usePackIcon = settings.vignetteRadarPOIIcons == true and note.icon ~= nil
                    or note.areaPoiID ~= nil and note.atlasName ~= nil
                local x, y = Project(dx, dy, distance, ViewFacing(player.facing),
                    panel.plotRadius - (usePackIcon and 11 or 5), range)
                if x and y then
                    count = count + 1
                    local dot = panel.mapNotes[count]
                    if not dot then
                        dot = CreateFrame("Button", nil, panel.field)
                        dot:SetSize(13, 13)
                        dot:SetFrameLevel(panel.field:GetFrameLevel() + 2)
                        dot.rim = dot:CreateTexture(nil, "ARTWORK")
                        dot.rim:SetSize(8, 8)
                        dot.rim:SetPoint("CENTER")
                        dot.rim:SetTexture(CIRCLE_TEXTURE)
                        dot.core = dot:CreateTexture(nil, "OVERLAY")
                        dot.core:SetSize(3, 3)
                        dot.core:SetPoint("CENTER")
                        dot.core:SetTexture(CIRCLE_TEXTURE)
                        dot.core:SetVertexColor(0.02, 0.03, 0.035, 0.95)
                        dot.icon = dot:CreateTexture(nil, "OVERLAY")
                        dot.icon:SetPoint("CENTER")
                        dot.icon:Hide()
                        dot:EnableMouseWheel(true)
                        dot:SetScript("OnMouseWheel", OnZoomWheel)
                        dot:SetScript("OnEnter", function(self)
                            if not (GameTooltip and self.note) then return end
                            local entry = self.note
                            local guidance = addon.VignetteRadarGuidance
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetText(entry.name, 1, 1, 1)
                            -- Line 2: kind · source · yards · ETA.
                            local yards = math.floor(self.distance + 0.5)
                            local parts = { MAP_NOTE_LABEL[entry.areaKind or entry.kind] or "Note" }
                            local source = entry.kind == "guide" and "Zygor"
                                or entry.areaPoiID and "Blizzard" or entry.source
                            if source then parts[#parts + 1] = tostring(source) end
                            parts[#parts + 1] = yards .. " yd"
                            local eta = guidance and guidance.Eta(yards)
                            if eta then parts[#parts + 1] = eta end
                            GameTooltip:AddLine(table.concat(parts, " · "), 0.72, 0.8, 0.82)
                            if entry.note then GameTooltip:AddLine(entry.note, 0.82, 0.86, 0.8, true) end
                            local facts = guidance and guidance.CompactFacts(entry)
                            if facts then GameTooltip:AddLine(facts, .78, .86, .74, true) end
                            if entry.route then
                                GameTooltip:AddLine(#entry.route .. " guided stops", .58, .83, .73)
                            end
                            local hints = guidance and guidance.MapNoteHints(entry)
                            if hints then GameTooltip:AddLine(hints, .5, .56, .58, true) end
                            GameTooltip:Show()
                        end)
                        dot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                        dot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                        dot:SetScript("OnClick", function(self, button)
                            if button == "LeftButton" and self.note
                                and addon.VignetteRadarWorldFocus then
                                if IsShiftKeyDown and IsShiftKeyDown() and self.note.zygorPoint then
                                    addon.VignetteRadarWorldFocus.LoadZygorGuide(self.note)
                                else
                                    addon.VignetteRadarFocus.Select(addon.VignetteRadarFocus.Note(self.note),
                                        { source = "radar" })
                                end
                            elseif button == "RightButton" and self.note
                                and (self.note.kind == "mob" or self.note.kind == "treasure")
                                and Settings().vignetteRadarHideCleared and addon.VignetteRadarRecent then
                                addon.VignetteRadarRecent.HideNote(self.note)
                                RefreshRadar(false)
                            end
                        end)
                        panel.mapNotes[count] = dot
                    end
                    local slot = MAP_NOTE_COLOR[note.kind] or "other"
                    local color = addon.VignetteRadarStyle
                    if color then dot.rim:SetVertexColor(color.Color(slot))
                    else dot.rim:SetVertexColor(0.7, 0.75, 0.78, 1) end
                    if usePackIcon and note.areaPoiID then
                        if dot._iconNote ~= note then
                            addon.VignetteRadarPoints.ApplyIcon(dot.icon, nil, note)
                            dot.icon:SetVertexColor(1, 1, 1, 1)
                            dot.icon:SetSize(15, 15)
                            dot._iconNote = note
                        end
                        dot:SetSize(18, 18)
                        dot.rim:Hide()
                        dot.core:Hide()
                        dot.icon:Show()
                    elseif usePackIcon then
                        local icon = note.icon
                        if dot._iconNote ~= note then
                            dot.icon:SetTexture(icon.texture)
                            if icon.texCoord then dot.icon:SetTexCoord(Unpack(icon.texCoord))
                            else dot.icon:SetTexCoord(0, 1, 0, 1) end
                            local tint = icon.color
                            dot.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1,
                                tint and tint[3] or 1, icon.alpha * (tint and tint[4] or 1))
                            dot.icon:SetSize(math.max(10, math.min(18, 12 * icon.scale)),
                                math.max(10, math.min(18, 12 * icon.scale)))
                            dot._iconNote = note
                        end
                        dot:SetSize(18, 18)
                        dot.rim:Hide()
                        dot.core:Hide()
                        dot.icon:Show()
                    else
                        dot:SetSize(13, 13)
                        dot.icon:Hide()
                        dot.rim:Show()
                        dot.core:Show()
                    end
                    dot.note, dot.distance = note, distance
                    if addon.VignetteRadarCollectionLens then addon.VignetteRadarCollectionLens.Mark(dot, note) end
                    dot:ClearAllPoints()
                    dot:SetPoint("CENTER", panel.field, "CENTER", x, y)
                    addon.VignetteRadarTurn.TrackPoint(dot, x, y, ViewFacing(player.facing))
                    dot:Show()
                end
            end
        end
    end
    for index = count + 1, #panel.mapNotes do panel.mapNotes[index]:Hide() end
    return count
end

local function RenderQuestDots(player, range)
    local showDots = Settings().vignetteRadarQuestDots
    local showHalos = Settings().vignetteRadarQuestAreas and Settings().vignetteRadarQuestHalos
        and panel.questClip and panel.questClip.canClip
    if not ((showDots or showHalos) and player)
        or (addon.VignetteRadarLensActive and addon.VignetteRadarLensActive ~= "quest")
        or (panel._underlayHide and panel._underlayHide.quests) then
        HideQuestDots(); return 0
    end
    local haloRadius = math.max(10, math.min(panel.plotRadius,
        (Settings().vignetteRadarQuestHaloRadius or 10) * panel.plotRadius / range))
    local haloAlpha = .16 * math.max(.55, math.min(1, (SafeNumber(range) or 300) / 300))
    local count = 0
    local visibleQuestIDs, visibleQuestCount = {}, 0
    for _, quest in ipairs(activeQuests) do
        if not (player.instanceID and quest.instanceID and player.instanceID ~= quest.instanceID) then
            local dx, dy = quest.worldX - player.worldX, quest.worldY - player.worldY
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance <= range and count < MAX_QUEST_DOTS
                and addon.KeepCenterMarker("quest", quest.questID, distance, range) then
                local x, y = Project(dx, dy, distance, ViewFacing(player.facing), panel.plotRadius, range)
                if x and y then
                    if not visibleQuestIDs[quest.questID] then
                        visibleQuestIDs[quest.questID] = true
                        visibleQuestCount = visibleQuestCount + 1
                    end
                    count = count + 1
                    local dot = panel.questDots[count]
                    if not dot then
                        dot = CreateFrame("Button", nil, panel.field)
                        dot:SetSize(14, 14)
                        dot:SetFrameLevel(panel.field:GetFrameLevel() + 3)
                        dot.rim = dot:CreateTexture(nil, "ARTWORK")
                        dot.rim:SetSize(13, 13)
                        dot.rim:SetPoint("CENTER")
                        dot.rim:SetTexture(QUEST_DIAMOND_TEXTURE)
                        dot.rim:SetVertexColor(.04, .05, .06, .98)
                        dot.fill = dot:CreateTexture(nil, "OVERLAY")
                        dot.fill:SetSize(9, 9)
                        dot.fill:SetPoint("CENTER")
                        dot.fill:SetTexture(QUEST_DIAMOND_TEXTURE)
                        dot.selection = dot:CreateTexture(nil, "OVERLAY")
                        dot.selection:SetTexture(addon.VignetteRadarQuestHollowTexture)
                        dot.selection:SetSize(18, 18)
                        dot.selection:SetPoint("CENTER")
                        dot.selection:SetVertexColor(.96, .97, 1, .92)
                        dot.number = Text(dot, 8, "")
                        dot.number:SetPoint("CENTER", dot, "CENTER")
                        addon.VignetteRadarStyle.SetFont(dot.number, 9, "OUTLINE")
                        dot.number:SetJustifyH("CENTER")
                        dot.number:SetTextColor(1, 1, 1, 1)
                        dot:EnableMouseWheel(true)
                        dot:SetScript("OnMouseWheel", OnZoomWheel)
                        dot:SetScript("OnEnter", function(self)
                            if not GameTooltip then return end
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetText(self.quest.name, 1, 0.82, 0.35)
                            local kind = self.quest.completed and "Complete"
                                or self.quest.taskType == "world" and "World Quest"
                                or self.quest.taskType == "bonus" and "Bonus Objective" or "Quest"
                            GameTooltip:AddLine(kind .. " · " .. math.floor(self.distance + .5) .. " yd",
                                .72, .76, .78)
                            if not self.quest.completed then
                                AddQuestTooltipObjective(self.quest.questID,
                                    self.quest.objectiveText or (self.quest.nextStep and self.quest.nextStep.text))
                            end
                            GameTooltip:AddLine("Click to Spotlight", .6, .8, .72)
                            GameTooltip:Show()
                        end)
                        dot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                        dot:SetScript("OnClick", function(self)
                            local exploration = addon.VignetteRadarExploration
                            if exploration and self.quest then
                                exploration.FocusQuest(self.quest.questID, self.quest)
                            end
                        end)
                        panel.questDots[count] = dot
                    end
                    dot.quest, dot.distance = quest, distance
                    local tracked = Settings().vignetteRadarFollowTrackedQuest
                        and followedQuestID == quest.questID and followedQuestMapID == activeMapID
                    local red, green, blue
                    if quest.taskType and not Settings().vignetteRadarQuestColors then
                        local color = TASK_AREA_COLORS[quest.taskType]
                        red, green, blue = color[1], color[2], color[3]
                    elseif Settings().vignetteRadarQuestColors then
                        local color = QUEST_COLORS[quest.colorSlot or 1]
                        red, green, blue = color[1], color[2], color[3]
                    elseif addon.VignetteRadarStyle then
                        red, green, blue = addon.VignetteRadarStyle.Color("quest")
                    else
                        red, green, blue = 1, .74, .27
                    end
                    dot.fill:SetVertexColor(red, green, blue, 1)
                    local registry = addon.VignetteRadarPoints
                    local icon = registry.Icon(quest)
                    if dot.shownIcon ~= icon then
                        dot.shownIcon = icon
                        dot.atlasShown = icon.atlas ~= nil
                            and registry.ApplyIcon(dot.rim, icon, quest, QUEST_DIAMOND_TEXTURE).atlas ~= nil
                    end
                    if dot.atlasShown then
                        -- Blizzard's own colors: no tint, no diamond fill or number.
                        dot.rim:SetSize(16, 16)
                        dot.rim:SetVertexColor(1, 1, 1, 1)
                        dot.fill:Hide()
                    elseif quest.completed then
                        dot.rim:SetTexture(QUEST_DIAMOND_TEXTURE)
                        dot.rim:SetTexCoord(0, 1, 0, 1)
                        dot.rim:SetSize(13, 13)
                        dot.rim:SetVertexColor(tracked and .95 or .04,
                            tracked and .97 or .05, tracked and .93 or .06, .98)
                        dot.fill:Show()
                        dot.number:SetTextColor(1, 1, 1, 1)
                    else
                        dot.rim:SetTexture(addon.VignetteRadarQuestHollowTexture)
                        dot.rim:SetTexCoord(0, 1, 0, 1)
                        -- Match the visible 26px solid silhouette to the hollow file's 30px one.
                        dot.rim:SetSize(13 * 26 / 30, 13 * 26 / 30)
                        dot.rim:SetVertexColor(tracked and .95 or red,
                            tracked and .97 or green, tracked and .93 or blue, 1)
                        dot.fill:SetVertexColor(red * .18, green * .18, blue * .18, .94)
                        dot.fill:Show()
                        dot.number:SetTextColor(1, 1, 1, 1)
                    end
                    dot.number:SetText(Settings().vignetteRadarQuestNumbers and not dot.atlasShown
                        and tostring(quest.colorSlot or 1) or "")
                    local exploration = addon.VignetteRadarExploration
                    local spotlight = exploration and exploration.GetFocusedQuest()
                    dot:SetAlpha(1)
                    dot.selection:SetShown(showDots and spotlight == quest.questID)
                    dot.screenX, dot.screenY = x, y
                    dot:ClearAllPoints()
                    dot:SetPoint("CENTER", panel.field, "CENTER", x, y)
                    addon.VignetteRadarTurn.TrackPoint(dot, x, y, ViewFacing(player.facing))
                    dot:SetShown(showDots)
                    if showHalos then
                        if not dot.halo then
                            -- A clipped child frame keeps the approximation inside the
                            -- square radar without adding mouse hit regions or timers.
                            local halo = CreateFrame("Frame", nil, panel.questClip)
                            halo:SetFrameLevel(panel.field:GetFrameLevel() + 1)
                            halo:EnableMouse(false)
                            halo.fill = halo:CreateTexture(nil, "ARTWORK")
                            halo.fill:SetAllPoints(halo)
                            halo.fill:SetTexture(CIRCLE_TEXTURE)
                            dot.halo = halo
                        end
                        dot.halo:SetSize(haloRadius * 2, haloRadius * 2)
                        dot.halo:ClearAllPoints()
                        dot.halo:SetPoint("CENTER", panel.field, "CENTER", x, y)
                        addon.VignetteRadarTurn.TrackPoint(dot.halo, x, y, ViewFacing(player.facing))
                        local haloColor = quest.taskType and TASK_AREA_COLORS[quest.taskType]
                            or Settings().vignetteRadarQuestColors
                                and Settings().vignetteRadarQuestAreaColors
                                and QUEST_COLORS[quest.colorSlot or 1] or QUEST_AREA_BLUE
                        dot.halo.fill:SetVertexColor(haloColor[1], haloColor[2],
                            haloColor[3], haloAlpha)
                        dot.halo:SetAlpha(1)
                        dot.halo:Show()
                    elseif dot.halo then
                        dot.halo:Hide()
                    end
                end
            end
        end
    end
    for index = count + 1, #panel.questDots do
        panel.questDots[index]:Hide()
        if panel.questDots[index].halo then panel.questDots[index].halo:Hide() end
    end
    return visibleQuestCount
end

addon.UpdateVignetteRadarQuestKey = function()
    local legend = LegendAPI()
    if not (legend and legend.IsQuestShown and legend.IsQuestShown()
        and legend.SetQuestEntries) then return end
    local now = Now()
    if panel._questKeyNextAt and now < panel._questKeyNextAt then return end
    panel._questKeyNextAt = now + .5
    local entries = {}
    local player = PlayerSnapshot(activeMapID)
    local range = Settings().vignetteRadarRange or 150
    if player and (not addon.VignetteRadarLensActive
        or addon.VignetteRadarLensActive == "quest") then
        local entryByQuestID = {}
        for _, quest in ipairs(activeQuests) do
            if not (player.instanceID and quest.instanceID and player.instanceID ~= quest.instanceID) then
                local dx, dy = quest.worldX - player.worldX, quest.worldY - player.worldY
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance <= range then
                    local entry = entryByQuestID[quest.questID]
                    if entry then
                        entry.distance = math.min(entry.distance, distance)
                    else
                        entry = { questID = quest.questID, name = quest.name,
                            colorSlot = quest.colorSlot, distance = distance,
                            completed = quest.completed }
                        entryByQuestID[quest.questID] = entry
                        entries[#entries + 1] = entry
                    end
                end
            end
        end
    end
    legend.SetQuestEntries(entries)
end

addon.RenderVignetteRadarQuestStarts = function(player, mapID, range)
    if not panel then return 0 end
    panel.questStartDots = panel.questStartDots or {}
    local count = 0
    if player and mapID and Settings().vignetteRadarQuestStartBadges
        and (not addon.VignetteRadarLensActive or addon.VignetteRadarLensActive == "quest")
        and not (panel._underlayHide and panel._underlayHide.quests)
        and addon.VignetteRadarQuestData then
        local starts = addon.VignetteRadarAvailableStarts or {}
        for _, entry in ipairs(starts) do
            if count >= 32 then break end
            local worldX, worldY, instanceID = entry.worldX, entry.worldY, entry.instanceID
            if worldX and worldY and not (player.instanceID and instanceID
                and player.instanceID ~= instanceID) then
                local dx, dy = worldX - player.worldX, worldY - player.worldY
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance <= range
                    and addon.KeepCenterMarker("quest", entry.questID, distance, range) then
                    local x, y = Project(dx, dy, distance, ViewFacing(player.facing),
                        panel.plotRadius - 9, range)
                    if x and y then
                        count = count + 1
                        local dot = panel.questStartDots[count]
                        if not dot then
                            dot = CreateFrame("Button", nil, panel.field)
                            dot:SetSize(19, 19)
                            dot:SetFrameLevel(panel.field:GetFrameLevel() + 4)
                            dot.rim = dot:CreateTexture(nil, "ARTWORK")
                            dot.rim:SetSize(15, 15)
                            dot.rim:SetPoint("CENTER")
                            dot.rim:SetTexture(QUEST_DIAMOND_TEXTURE)
                            dot.fill = dot:CreateTexture(nil, "OVERLAY")
                            dot.fill:SetSize(11, 11)
                            dot.fill:SetPoint("CENTER")
                            dot.fill:SetTexture(QUEST_DIAMOND_TEXTURE)
                            dot.fill:SetVertexColor(.03, .05, .06, .96)
                            dot.glyph = Text(dot, 10, "!")
                            dot.glyph:SetPoint("CENTER", dot, "CENTER", 0, 0)
                            dot:SetScript("OnEnter", function(self)
                                if not (GameTooltip and self.entry) then return end
                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                GameTooltip:SetText(self.entry.questLineName or self.entry.questName
                                    or "Available quest", 1, .87, .5)
                                if self.entry.questName and self.entry.questName ~= self.entry.questLineName then
                                    GameTooltip:AddLine(self.entry.questName, .85, .87, .85)
                                end
                                local accountCompleted = SafeBoolean(Call(C_QuestLog
                                    and C_QuestLog.IsQuestFlaggedCompletedOnAccount,
                                    self.entry.questID)) == true
                                GameTooltip:AddLine(accountCompleted and "Warband-Completed Quest Start"
                                    or self.entry.isCampaign and "Campaign Quest Start"
                                    or self.entry.isImportant and "Important Quest Start"
                                    or "Available Quest Start", .62, .83, .77)
                                if self.entry.floor == "above" or self.entry.floor == "below" then
                                    GameTooltip:AddLine("Blizzard marks this " .. self.entry.floor
                                        .. " your level.", .72, .79, .85)
                                end
                                GameTooltip:AddLine(math.floor(self.distance + .5) .. " yd straight-line", .7, .74, .76)
                                if Settings().vignetteRadarWorldFocusEnabled then
                                    GameTooltip:AddLine("Click to set World Focus.", .58, .83, .73)
                                end
                                GameTooltip:Show()
                            end)
                            dot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                            dot:SetScript("OnClick", function(self)
                                local focus = addon.VignetteRadarWorldFocus
                                if focus and self.entry then
                                    focus.SelectPoint({ kind = "quest", availableStart = true,
                                        questID = self.entry.questID, isCampaign = self.entry.isCampaign,
                                        name = self.entry.questName
                                        or self.entry.questLineName or "Quest start",
                                        mapID = activeMapID, mapX = self.entry.x, mapY = self.entry.y,
                                        worldX = self.entry.worldX, worldY = self.entry.worldY,
                                        instanceID = self.entry.instanceID })
                                end
                            end)
                            panel.questStartDots[count] = dot
                        end
                        dot.entry, dot.distance = entry, distance
                        dot.iconItem = dot.iconItem or { kind = "quest", availableStart = true }
                        dot.iconItem.isCampaign = entry.isCampaign == true
                        local registry = addon.VignetteRadarPoints
                        local icon = registry.Icon(dot.iconItem)
                        if dot.shownIcon ~= icon then
                            dot.shownIcon = icon
                            dot.atlasShown = registry.ApplyIcon(dot.rim, icon, dot.iconItem,
                                QUEST_DIAMOND_TEXTURE).atlas ~= nil
                        end
                        local arrow = entry.floor == "above" and "↑" or entry.floor == "below" and "↓"
                        if dot.atlasShown then
                            -- Blizzard's own colors; the level arrow rides on top.
                            dot.rim:SetSize(18, 18)
                            dot.rim:SetVertexColor(1, 1, 1, 1)
                            dot.fill:Hide()
                            dot.glyph:SetText(arrow or "")
                        else
                            dot.rim:SetSize(15, 15)
                            dot.fill:Show()
                            if entry.isCampaign then dot.rim:SetVertexColor(1, .72, .28, 1)
                            elseif entry.isImportant then dot.rim:SetVertexColor(.48, .82, 1, 1)
                            else dot.rim:SetVertexColor(.58, .82, .72, 1) end
                            dot.glyph:SetText(arrow or "!")
                        end
                        dot:ClearAllPoints()
                        dot:SetPoint("CENTER", panel.field, "CENTER", x, y)
                        addon.VignetteRadarTurn.TrackPoint(dot, x, y, ViewFacing(player.facing))
                        dot:Show()
                    end
                end
            end
        end
    end
    for index = count + 1, #panel.questStartDots do panel.questStartDots[index]:Hide() end
    return count
end

local function HideQuestAreas()
    if panel and panel.questBlob then
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == panel.questBlob then
            GameTooltip:Hide()
        end
        panel.questBlob.tooltipQuestID = nil
        panel.questBlob:Hide()
        panel.questBlob.drawnKey = nil
        panel.questBlob.nextDrawAt = nil
    end
end

local function StyleQuestBlob(blob, range)
    -- A close zoom can put the player inside a quest shape that covers the
    -- entire radar. Fade the native mesh itself so markers remain legible.
    local opacity = math.max(.55, math.min(1, (SafeNumber(range) or 300) / 300))
    local fillAlpha = math.floor(48 * opacity + .5)
    if blob._radarDefaultStyle and blob._radarFillAlpha == fillAlpha
        and blob._radarBorderAlpha == 0 then return true end
    local ok = pcall(function()
        if not blob._radarDefaultStyle then
            blob:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
            blob:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
        end
        if blob._radarFillAlpha ~= fillAlpha then blob:SetFillAlpha(fillAlpha) end
        if blob._radarBorderAlpha ~= 0 then blob:SetBorderAlpha(0) end
    end)
    if ok then
        blob._radarDefaultStyle = true
        blob._radarFillAlpha, blob._radarBorderAlpha = fillAlpha, 0
    end
    return ok
end

local function UpdateQuestAreaTooltip()
    local blob = panel and panel.questBlob
    if not (blob and GameTooltip and type(GetCursorPosition) == "function") then return end
    local field = panel.field
    local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
    if owner and owner ~= blob and owner ~= field
        and GameTooltip.IsShown and GameTooltip:IsShown() then return end
    local cursorX, cursorY = Call(GetCursorPosition)
    local scale = field.GetEffectiveScale and SafeNumber(field:GetEffectiveScale()) or 1
    if not (SafeNumber(cursorX) and SafeNumber(cursorY) and scale and scale > 0) then return end
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local fieldLeft, fieldTop = SafeNumber(field:GetLeft()), SafeNumber(field:GetTop())
    if not (fieldLeft and fieldTop) then return end
    local fromCenterX = cursorX - fieldLeft - field:GetWidth() / 2
    local fromCenterY = cursorY - fieldTop + field:GetHeight() / 2
    local inside = panel.squarePlot
        and math.abs(fromCenterX) <= panel.fieldRadius - QUEST_CLIP_INSET
        and math.abs(fromCenterY) <= panel.fieldRadius - QUEST_CLIP_INSET
        or not panel.squarePlot
        and fromCenterX * fromCenterX + fromCenterY * fromCenterY <= panel.fieldRadius * panel.fieldRadius
    local questID, estimated
    if inside and blob:IsShown() and type(blob.UpdateMouseOverTooltip) == "function" then
        local blobScale = blob.GetScale and SafeNumber(blob:GetScale()) or 1
        local blobLeft, blobTop = SafeNumber(blob:GetLeft()), SafeNumber(blob:GetTop())
        local width, height = SafeNumber(blob:GetWidth()), SafeNumber(blob:GetHeight())
        if width and height and width > 0 and height > 0 then
            local x, y
            if blobScale > 1 and panel.questAreaPlayerMapX and panel.questAreaPlayerMapY then
                -- A capped canvas is enlarged on screen; project from the
                -- player instead of mixing the blob's scale with field pixels.
                x = panel.questAreaPlayerMapX + fromCenterX / (width * blobScale)
                y = panel.questAreaPlayerMapY - fromCenterY / (height * blobScale)
            elseif blobLeft and blobTop then
                x, y = (cursorX - blobLeft) / width, (blobTop - cursorY) / height
            end
            if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                local sources = panel.questBlobSources or { blob }
                for index = #sources, 1, -1 do
                    local source = sources[index]
                    if source:IsShown() and type(source.UpdateMouseOverTooltip) == "function" then
                        questID = SafeNumber(Call(source.UpdateMouseOverTooltip, source, x, y))
                        if questID then break end
                    end
                end
            end
        end
    end
    if inside and not questID and Settings().vignetteRadarQuestAreas
        and Settings().vignetteRadarQuestHalos then
        local nearest = math.huge
        for _, dot in ipairs(panel.questDots) do
            if dot.halo and dot.halo:IsShown() and dot.quest and dot.screenX and dot.screenY then
                local dx, dy = fromCenterX - dot.screenX, fromCenterY - dot.screenY
                local distanceSquared = dx * dx + dy * dy
                local radius = dot.halo:GetWidth() / 2
                if distanceSquared <= radius * radius and distanceSquared < nearest then
                    nearest, questID, estimated = distanceSquared, dot.quest.questID, true
                end
            end
        end
    end
    local quest
    if questID then
        for _, candidate in ipairs(activeQuests) do
            if candidate.questID == questID then quest = candidate; break end
        end
    end
    if not quest then
        if owner == blob or owner == field then GameTooltip:Hide() end
        blob.tooltipQuestID = nil
        panel.hoverQuestID = nil
        return
    end
    local tooltipOwner = estimated and field or blob
    if blob.tooltipQuestID == questID and blob.tooltipEstimated == estimated
        and owner == tooltipOwner and GameTooltip:IsShown() then return end
    blob.tooltipQuestID = questID
    blob.tooltipEstimated = estimated
    panel.hoverQuestID = questID
    GameTooltip:SetOwner(tooltipOwner, "ANCHOR_CURSOR_RIGHT", 5, 2)
    GameTooltip:SetText(quest.name, 1, .82, .35)
    GameTooltip:AddLine(estimated and "Estimated Area" or "Quest Area", .72, .76, .78)
    if not quest.completed then AddQuestTooltipObjective(quest.questID, quest.objectiveText) end
    GameTooltip:AddLine("Click to Spotlight", .6, .8, .72)
    GameTooltip:Show()
end

local function RenderQuestAreas(player, mapID, range)
    local blob = panel.questBlob
    if not (blob and player and mapID and Settings().vignetteRadarQuestAreas
        and Settings().vignetteRadarNorthUp and #activeQuests > 0
        and (not addon.VignetteRadarLensActive or addon.VignetteRadarLensActive == "quest")) then
        HideQuestAreas()
        return
    end
    -- Blizzard's quest widget draws in map coordinates. Keep its full-map canvas
    -- aligned with the north-up radar, and clip it to the plotting frame.
    local now = Now()
    if not questMapBasis or questMapBasis.mapID ~= mapID
        or (not questMapBasis.horizontal and now >= questMapBasis.retryAt) then
        local originX, originY, originInstance = MapToWorld(mapID, MapVector(0, 0))
        local rightX, rightY, rightInstance = MapToWorld(mapID, MapVector(1, 0))
        local downX, downY, downInstance = MapToWorld(mapID, MapVector(0, 1))
        -- A zone's map coordinates can be unavailable on the first attempt.
        -- Retry a failed projection instead of caching that failure for the zone.
        questMapBasis = { mapID = mapID, retryAt = now + addon.VignetteRadarScanSeconds() }
        if originX and rightX and downX
            and (not originInstance or not rightInstance or originInstance == rightInstance)
            and (not originInstance or not downInstance or originInstance == downInstance) then
            local horizontal = math.sqrt((rightX - originX)^2 + (rightY - originY)^2)
            local vertical = math.sqrt((downX - originX)^2 + (downY - originY)^2)
            -- Native blobs cannot rotate. Only show them when map axes match the radar.
            if horizontal > 0 and vertical > 0 and math.abs(rightX - originX) <= horizontal * 0.03
                and rightY < originY and math.abs(downY - originY) <= vertical * 0.03 and downX < originX then
                questMapBasis.horizontal, questMapBasis.vertical = horizontal, vertical
            end
        end
    end
    if not questMapBasis.horizontal then HideQuestAreas(); return end
    local pixelsPerYard = panel.plotRadius / range
    local width, height = questMapBasis.horizontal * pixelsPerYard, questMapBasis.vertical * pixelsPerYard
    if width < 1 or height < 1 then HideQuestAreas(); return end
    -- Keep each native widget's canvas bounded while preserving the full
    -- map-to-radar projection at very close zoom levels.
    local canvasScale = math.max(1, width / MAX_QUEST_BLOB_CANVAS,
        height / MAX_QUEST_BLOB_CANVAS)
    panel.questAreaPlayerMapX, panel.questAreaPlayerMapY = player.mapX, player.mapY
    local eligible, seen, signature = {}, {}, {}
    for _, quest in ipairs(activeQuests) do
        if not seen[quest.questID] then
            seen[quest.questID] = true
            local dx, dy = quest.worldX - player.worldX, quest.worldY - player.worldY
            local distance = math.sqrt(dx * dx + dy * dy)
            if addon.KeepCenterMarker("quest", quest.questID, distance, range) then
                eligible[#eligible + 1] = quest.questID
                signature[#signature + 1] = tostring(quest.questID)
            end
        end
    end
    if #eligible == 0 then HideQuestAreas(); return end
    local key = tostring(mapID) .. ":" .. tostring(width) .. ":" .. tostring(height)
        .. ":" .. table.concat(signature, ":")
    if not panel.questBlobSources then panel.questBlobSources = { blob } end
    if not StyleQuestBlob(blob, range) then HideQuestAreas(); return end
    if blob._radarCanvasScale ~= canvasScale then
        blob:SetScale(canvasScale)
        blob._radarCanvasScale = canvasScale
    end
    local canvasWidth, canvasHeight = width / canvasScale, height / canvasScale
    if blob._canvasWidth ~= canvasWidth or blob._canvasHeight ~= canvasHeight then
        blob:SetSize(canvasWidth, canvasHeight)
        blob._canvasWidth, blob._canvasHeight = canvasWidth, canvasHeight
    end
    local canvasX, canvasY = (0.5 - player.mapX) * canvasWidth,
        (player.mapY - 0.5) * canvasHeight
    if blob._canvasX ~= canvasX or blob._canvasY ~= canvasY then
        blob:ClearAllPoints()
        blob:SetPoint("CENTER", panel.field, "CENTER", canvasX, canvasY)
        blob._canvasX, blob._canvasY = canvasX, canvasY
    end
    if blob.drawnKey ~= key or now >= (blob.nextDrawAt or 0) then
        local ok = true
        if blob.mapContextID ~= mapID then
            ok = pcall(blob.SetMapID, blob, mapID)
            if ok then blob.mapContextID = mapID end
        end
        if ok then ok = pcall(blob.DrawNone, blob) end
        if ok then
            for _, questID in ipairs(eligible) do
                if not pcall(blob.DrawBlob, blob, questID, true) then ok = false; break end
            end
        end
        if not ok then HideQuestAreas(); return end
        blob.drawnKey = key
        -- DrawBlob can succeed before Blizzard loads the shape data.
        blob.retryDelay = math.min(20, (blob.retryDelay or 1) * 2)
        blob.nextDrawAt = now + blob.retryDelay
    end
    blob:Show()
    return true
end

local function PlaceBlip(key, screenX, screenY, target, facing)
    local blip = panel.blipByKey[key]
    if not blip then
        blip = AcquireBlip()
        if not blip then return end
        panel.blipByKey[key] = blip
    end
    blip._seen = true
    blip.target = target
    blip.cluster, blip.clusterKey = nil, nil
    blip.count:Hide()
    local r, g, b = TargetColor(target)
    local settings = Settings()
    local size = tonumber(settings.vignetteRadarMarkerSize) or 7
    local hitSize = math.max(14, size + (target.isWorldBoss and 11 or 8))
    blip:SetSize(hitSize, hitSize)
    StyleMarker(blip, blip.dot, target, size, r, g, b)
    local legend = LegendAPI()
    blip.sourceBadge:SetShown(settings.vignetteRadarSourceBadges ~= false
        and legend and legend.VignetteSource
        and legend.VignetteSource(target) == "worldMap")
    blip.sourceBadge:SetVertexColor(r, g, b, .95)
    blip.favorite:SetShown(Favorite(target))
    if addon.VignetteRadarCollectionLens then addon.VignetteRadarCollectionLens.Mark(blip, target) end
    local flashing = not Quiet() and target.newUntil and target.newUntil > Now()
    blip.glow:SetVertexColor(r, g, b, flashing and (0.4 + 0.3 * math.sin(Now() * 9)) or 0.18)
    blip.glow:SetShown(not target.stale)
    blip:SetAlpha(CategoryOpacity(target.category) * TargetAlpha(target))
    blip:ClearAllPoints()
    blip:SetPoint("CENTER", panel.field, "CENTER", screenX, screenY)
    if facing then addon.VignetteRadarTurn.TrackPoint(blip, screenX, screenY, facing) end
end

local function RenderExploration(player, range)
    local exploration = addon.VignetteRadarExploration
    if not exploration or not panel then return end
    panel.exploreLines = panel.exploreLines or {}
    panel.exploreDots = panel.exploreDots or {}
    panel.trailDots = panel.trailDots or {}
    panel.trailMarks = panel.trailMarks or {}
    panel.trailExtraMarks = panel.trailExtraMarks or {}
    for _, line in ipairs(panel.exploreLines) do line:Hide() end
    for _, dot in ipairs(panel.exploreDots) do dot:Hide() end
    for _, dot in ipairs(panel.trailDots) do dot:Hide() end
    for _, mark in ipairs(panel.trailMarks) do mark:Hide() end
    for _, mark in pairs(panel.trailExtraMarks) do mark:Hide() end
    if addon.VignetteRadarLeadTrail then
        addon.VignetteRadarLeadTrail.Render(panel, not addon.VignetteRadarLensActive and player or nil, range)
    end
    -- Spawn History Heatmap: faint heat under the markers (UI/SpawnHeatmap.lua).
    if addon.VignetteRadarSpawnHeatmap then
        addon.VignetteRadarSpawnHeatmap.Render(panel, not addon.VignetteRadarLensActive and player or nil, range)
    end
    if not player or addon.VignetteRadarLensActive then return end
    local lineCount, dotCount = 0, 0
    local function Position(item, clamp)
        if player.instanceID and item.instanceID and player.instanceID ~= item.instanceID then return nil end
        local worldX = SafeNumber(item.worldX) or SafeNumber(item.x)
        local worldY = SafeNumber(item.worldY) or SafeNumber(item.y)
        if not worldX or not worldY then return nil end
        local dx, dy = worldX - player.worldX, worldY - player.worldY
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance > range and not clamp then return nil end
        local x, y = Project(dx, dy, distance, ViewFacing(player.facing), panel.plotRadius, range)
        if not x then return nil end
        if clamp and distance > range then
            local factor = panel.plotRadius / math.max(1, math.sqrt(x*x + y*y))
            x, y = x * factor, y * factor
        end
        return x, y, distance
    end
    local function Line(x1, y1, x2, y2, r, g, b, a, thick)
        lineCount = lineCount + 1
        local line = panel.exploreLines[lineCount]
        if not line then
            line = panel.field:CreateLine(nil, "ARTWORK")
            panel.exploreLines[lineCount] = line
        end
        line:SetThickness(thick or 1)
        line:SetColorTexture(r, g, b, a)
        line:SetStartPoint("CENTER", panel.field, x1, y1)
        line:SetEndPoint("CENTER", panel.field, x2, y2)
        addon.VignetteRadarTurn.TrackLine(line, x1, y1, x2, y2, ViewFacing(player.facing))
        line:Show()
    end
    local function Dot(item, x, y, label, r, g, b, onClick)
        dotCount = dotCount + 1
        local dot = panel.exploreDots[dotCount]
        if not dot then
            dot = CreateFrame("Button", nil, panel.field)
            dot:SetSize(16, 16)
            dot:SetFrameLevel(panel.field:GetFrameLevel() + 2)
            dot.fill = dot:CreateTexture(nil, "ARTWORK")
            dot.fill:SetSize(10, 10)
            dot.fill:SetPoint("CENTER")
            dot.fill:SetTexture(CIRCLE_TEXTURE)
            dot.text = Text(dot, 8, "")
            dot.text:SetAllPoints()
            dot.text:SetJustifyH("CENTER")
            dot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            dot:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.item.name or "Stop", 1, 1, 1)
                GameTooltip:AddLine(self.hint or "", .65, .8, .75, true)
                GameTooltip:Show()
            end)
            dot:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            dot:SetScript("OnClick", function(self, button)
                if self.onClick then self.onClick(self.item, button) end
            end)
            panel.exploreDots[dotCount] = dot
        end
        dot.item, dot.onClick = item, onClick
        local dx, dy = item.worldX-player.worldX, item.worldY-player.worldY
        local distance = math.floor(math.sqrt(dx*dx+dy*dy)+.5)
        dot.hint = label == "" and (distance .. " yd straight line. Click: route; right-click: remove.")
            or ("Route stop " .. label .. " • " .. distance .. " yd straight line")
        dot.fill:SetVertexColor(r, g, b, .9)
        dot.text:SetText(label)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", panel.field, "CENTER", x, y)
        addon.VignetteRadarTurn.TrackPoint(dot, x, y, ViewFacing(player.facing))
        dot:Show()
    end
    local trail, trailMap = exploration.GetTrail()
    if Settings().vignetteRadarBreadcrumbs and trailMap == player.mapID then
        if not panel.trailLayer then
            local layer = CreateFrame("Frame", nil, panel.field)
            layer:SetAllPoints(panel.field)
            layer:SetFrameLevel(panel.field:GetFrameLevel() + 3)
            layer:EnableMouse(false)
            panel.trailLayer = layer
        end
        panel.trailSamples = panel.trailSamples or {}
        local samples, trailDotCount = panel.trailSamples, 0
        local definition = TRAIL_STYLE_BY_ID[Settings().vignetteRadarTrailStyle] or TRAIL_STYLES[1]
        local spacing = definition.spacing * (Settings().vignetteRadarTrailSpacing or 1)
        local spacingYards = spacing * range / math.max(1, panel.plotRadius)
        local sizeScale = Settings().vignetteRadarTrailSize or 1
        local tailFade = Settings().vignetteRadarTrailTailFade or 0
        local fadeSpan = Settings().vignetteRadarTrailFadeSpan or 1
        local limit = definition.segments and #definition.segments > 2 and 48 or 64
        local edge = panel.plotRadius - 7
        local now = Now()
        local speed = Settings().vignetteRadarTrailSpeed or 1
        local lifetime = Settings().vignetteRadarTrailLifetime or 180
        local r, g, b = .25, .91, .7
        if addon.VignetteRadarStyle then r, g, b = addon.VignetteRadarStyle.Color("accent") end
        local extraParts = {}
        local candidateBudget = 384
        local function TrailPosition(point)
            if player.instanceID and point.instanceID
                and player.instanceID ~= point.instanceID then return nil end
            local dx, dy = point.x - player.worldX, point.y - player.worldY
            local distance = math.sqrt(dx * dx + dy * dy)
            return Project(dx, dy, distance, ViewFacing(player.facing), panel.plotRadius, range)
        end
        local function CollectSegment(x1, y1, x2, y2, startArc, endArc, startAt, endAt)
            if not (x1 and x2 and startArc and endArc) then return end
            local dx, dy = x2 - x1, y2 - y1
            local length = math.sqrt(dx*dx + dy*dy)
            local worldLength = startArc - endArc
            if length < .01 or length > edge * 4 or worldLength <= .01 then return end
            if (x1 > edge and x2 > edge) or (x1 < -edge and x2 < -edge)
                or (y1 > edge and y2 > edge) or (y1 < -edge and y2 < -edge) then return end
            -- These grid positions are measured along the travelled route,
            -- not from the player or a clock phase. A stationary mark stays
            -- on the same patch of world as newer samples arrive.
            local offset = startArc % spacingYards
            while offset <= worldLength and trailDotCount < limit and candidateBudget > 0 do
                candidateBudget = candidateBudget - 1
                local portion = offset / worldLength
                local x, y = x1 + dx * portion, y1 + dy * portion
                local radiusSquared = x*x + y*y
                if radiusSquared >= 49 and radiusSquared <= edge*edge then
                    trailDotCount = trailDotCount + 1
                    local sample = samples[trailDotCount]
                    if not sample then sample = {}; samples[trailDotCount] = sample end
                    sample.x, sample.y = x, y
                    sample.ux, sample.uy = dx / length, dy / length
                    sample.arc = startArc - offset
                    sample.age = math.max(0, now - (startAt + (endAt - startAt) * portion))
                end
                offset = offset + spacingYards
            end
        end
        local latest = trail[#trail]
        local newerX, newerY
        if latest then newerX, newerY = TrailPosition(latest) end
        if latest and now - latest.at <= 3 then
            local dx, dy = player.worldX - latest.x, player.worldY - latest.y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance > .5 and distance <= 120 then
                CollectSegment(0, 0, newerX, newerY, (latest.arc or 0) + distance,
                    latest.arc or 0, now, latest.at)
            end
        end
        for index = #trail, 2, -1 do
            if trailDotCount >= limit or candidateBudget <= 0 then break end
            local newer, older = trail[index], trail[index - 1]
            local olderX, olderY = TrailPosition(older)
            if not newer.breakBefore then
                CollectSegment(newerX, newerY, olderX, olderY, newer.arc, older.arc,
                    newer.at, older.at)
            end
            newerX, newerY = olderX, olderY
        end
        local wavePhase = now * speed * 3.2
        for index = 1, trailDotCount do
            local sample = samples[index]
            local progress = (index - 1) / math.max(1, trailDotCount - 1)
            local remaining = math.max(0, 1 - sample.age / lifetime)
            local glow = speed == 0 and 1 or .74 + .26
                * math.cos(sample.arc / spacingYards * .85 - wavePhase)
            local markAlpha = .95 * math.sqrt(remaining)
                * TrailFadeMultiplier(progress, tailFade, fadeSpan) * glow
            if definition.dot or definition.square then
                local dot = panel.trailDots[index]
                if not dot then
                    dot = panel.trailLayer:CreateTexture(nil, "BACKGROUND")
                    panel.trailDots[index] = dot
                end
                local texture = definition.square and SQUARE_TEXTURE or CIRCLE_TEXTURE
                if dot._trailTexture ~= texture then
                    dot:SetTexture(texture)
                    dot._trailTexture = texture
                end
                DrawTrailGlyph(definition, dot, nil, panel.field, sample.x, sample.y,
                    sample.ux, sample.uy, r, g, b, markAlpha, index, sizeScale, ViewFacing(player.facing))
            else
                local mark = panel.trailMarks[index]
                if not mark then
                    mark = panel.trailLayer:CreateLine(nil, "BACKGROUND")
                    panel.trailMarks[index] = mark
                end
                for part = 2, #definition.segments do
                    local slot = (index - 1) * 3 + part - 1
                    local extra = panel.trailExtraMarks[slot]
                    if not extra then
                        extra = panel.trailLayer:CreateLine(nil, "BACKGROUND")
                        panel.trailExtraMarks[slot] = extra
                    end
                    extraParts[part - 1] = extra
                end
                DrawTrailGlyph(definition, mark, extraParts, panel.field, sample.x, sample.y,
                    sample.ux, sample.uy, r, g, b, markAlpha, index, sizeScale, ViewFacing(player.facing))
            end
        end
    end
    for _, pin in ipairs(exploration.GetPins(player.mapID)) do
        local x, y, distance = Position(pin, false)
        if x and distance > 12 then
            Dot(pin, x, y, "", .92, .71, .34, function(item, button)
                if button == "RightButton" then exploration.RemovePin(item.id)
                else exploration.AddRouteStop(item) end
            end)
        end
    end
    local priorX, priorY = 0, 0
    for index, stop in ipairs(exploration.GetRoute(player.mapID)) do
        local x, y, distance = Position(stop, true)
        if x then
            if distance > 12 then
                Line(priorX, priorY, x, y, .3, .88, .71, .55, 1.7)
                Dot(stop, x, y, tostring(index), .16, .7, .54, nil)
            end
            priorX, priorY = x, y
        end
    end
end

local CARDINALS = {
    { text = "N", angle = 0 },
    { text = "W", angle = math.pi / 2 },
    { text = "S", angle = math.pi },
    { text = "E", angle = -math.pi / 2 },
}

local function RenderCardinals(facing)
    local radius = panel.fieldRadius - (panel.squarePlot and 8 or 5)
    for index, definition in ipairs(CARDINALS) do
        local relative = NormalizeAngle(definition.angle - facing)
        local label = panel.cardinals[index]
        label:ClearAllPoints()
        local x, y = -math.sin(relative) * radius, math.cos(relative) * radius
        label:SetPoint("CENTER", panel.field, "CENTER", x, y)
        addon.VignetteRadarTurn.TrackPoint(label, x, y, facing)
    end
end

local function UpdateRingLabels(range)
    panel.innerLabel:SetText(math.floor(range / 3) .. "y")
    panel.outerLabel:SetText(math.floor((range * 2) / 3) .. "y")
end

local function PanelScale(value)
    local maximum = 1.8
    if UIParent and UIParent.GetWidth and UIParent.GetHeight then
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        if SafeNumber(width) and SafeNumber(height) and width > 0 and height > 0 then
            maximum = math.min(maximum, (width - 8) / panel:GetWidth(), (height - 8) / panel:GetHeight())
            -- Reserve room for the wider target picker beside the panel on small screens.
            maximum = math.min(maximum, (width - 274) / panel:GetWidth())
        end
    end
    return math.max(0.8, math.min(value, maximum))
end

-- GetLeft/GetTop use the panel's own scale, while UIParent dimensions and
-- saved anchors use UIParent coordinates.
local function PanelPosition()
    if not panel then return nil, nil end
    local scale = panel:GetScale()
    local left, top = SafeNumber(panel:GetLeft()), SafeNumber(panel:GetTop())
    if not (SafeNumber(scale) and left and top) then return nil, nil end
    return left * scale, top * scale
end

local function PlacePanel(left, top, scale)
    if not (UIParent and UIParent.GetWidth and UIParent.GetHeight) then return end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not (SafeNumber(width) and SafeNumber(height) and width > 0 and height > 0) then return end
    scale = PanelScale(scale)
    panel:SetScale(scale)
    if CircleOnly() then
        local layoutName = panel.layout or Settings().vignetteRadarLayout
        local layout = LAYOUTS[layoutName] or LAYOUTS.classic
        local fieldLeft = layoutName == "squat" and 10 or (layout.width - layout.field) / 2
        local fieldBottom = layoutName == "squat" and 38
            or (layout.footer or ZOOM_FOOTER_H) + (panel.layoutFocused and (layout.focus or 0) or 0) + 9
        -- The hidden frame may leave the screen. Keep the face and restore chevron visible.
        local lowerLeft = 4 - fieldLeft * scale
        local upperLeft = width - 4 - (fieldLeft + layout.field + 5) * scale
        local lowerTop = 4 + (panel:GetHeight() - fieldBottom) * scale
        local upperTop = height - 4 + (panel:GetHeight() - fieldBottom - layout.field) * scale
        left = math.max(lowerLeft, math.min(left, upperLeft))
        top = math.max(lowerTop, math.min(top, upperTop))
    else
        left = math.max(4, math.min(left, width - panel:GetWidth() * scale - 4))
        top = math.max(panel:GetHeight() * scale + 4, math.min(top, height - 4))
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left / scale, (top - height) / scale)
end

local function ApplyPanelLayout(focused)
    local name = Settings().vignetteRadarLayout or "classic"
    local square = Settings().vignetteRadarQuestAreas == true
    if not LAYOUTS[name] then name = "classic" end
    if panel.layout == name and panel.layoutFocused == focused and panel.squarePlot == square then return end
    local changed = panel.layout ~= name
    local layout = LAYOUTS[name]
    local left, top = PanelPosition()
    panel.layout, panel.layoutFocused, panel.squarePlot = name, focused, square
    local highlightTexture = square and ROUNDED_CONTROL_TEXTURE or CIRCLE_TEXTURE
    for _, control in ipairs({ panel.zoomOut, panel.zoomIn, panel.compass, panel.trailToggle,
        panel.clearToggle, panel.routeToggle, panel.arrowToggle,
        panel.combatToggle, panel.target, panel.legend, panel.minimize, panel.close, panel.frameToggle }) do
        if control and control.glow then control.glow:SetTexture(highlightTexture) end
    end
    panel.fieldRadius = layout.field / 2 - 9
    -- Keep the inner button of every corner grid clear of the plotted area,
    -- including the smaller Compact face.
    local cornerClearance = math.sqrt(2) * (layout.field / 2 - 48) - 3
    panel.plotRadius = math.min(panel.fieldRadius - (square and 22 or 15),
        cornerClearance)
    panel:SetSize(layout.width, layout.height + (focused and layout.focus or 0))
    if left and top then PlacePanel(left, top, Settings().vignetteRadarScale or 1) end
    panel.field:SetSize(layout.field, layout.field)
    -- Keep one native rectangular clip, inset far enough that its corners stay
    -- inside the rounded face, including the anti-aliased outline's inner edge.
    local radius = panel.fieldRadius
    panel.field.background:ClearAllPoints()
    if square then
        panel.field.background:SetTexture(ROUNDED_SQUARE_TEXTURE)
        panel.field.background:SetPoint("CENTER", panel.field, "CENTER")
        panel.field.background:SetSize(radius * 2, radius * 2)
    else
        panel.field.background:SetTexture(CIRCLE_TEXTURE)
        panel.field.background:SetAllPoints(panel.field)
    end
    panel.questClip:ClearAllPoints()
    panel.questClip:SetPoint("CENTER", panel.field, "CENTER")
    panel.questClip:SetSize((radius - QUEST_CLIP_INSET) * 2, (radius - QUEST_CLIP_INSET) * 2)
    panel.squareBorder:SetSize(radius * 2, radius * 2)
    panel.squareBorder:SetShown(square)
    panel.field.halo:SetShown(not square)
    for _, line in ipairs(panel.outerRing) do line:SetShown(not square) end
    if panel.frameToggle then
        panel.frameToggle:ClearAllPoints()
        panel.frameToggle:SetPoint("CENTER", panel.field, "CENTER",
            radius + (square and 8 or 5), 0)
        panel.frameToggle:SetWidth(square and 10 or 16)
        panel.frameToggle.glow:SetSize(square and 10 or 16, square and 10 or 16)
    end
    panel.field.halo:SetSize(layout.field + 4, layout.field + 4)
    ResizeRing(panel.outerRing, panel.field, panel.fieldRadius)
    ResizeRing(panel.rangeRing, panel.field, panel.plotRadius)
    ResizeRing(panel.middleRing, panel.field, panel.plotRadius * 2 / 3)
    ResizeRing(panel.innerRing, panel.field, panel.plotRadius / 3)
    local function Place(region, point, x, y, width, height)
        region:ClearAllPoints()
        region:SetPoint(point, x, y)
        if width then region:SetWidth(width) end
        if height then region:SetHeight(height) end
    end
    Place(panel.innerLabel, "CENTER", 0, -panel.plotRadius / 3)
    Place(panel.outerLabel, "CENTER", 0, -panel.plotRadius * 2 / 3)
    panel.layoutHint:SetShown(false)
    panel.sideCaption:SetShown(name == "squat")
    panel.sideGuide:SetShown(name == "squat")
    if name == "squat" then
        -- The plotting area beside the readout keeps this view short even while focused.
        Place(panel.field, "BOTTOMLEFT", 10, 38)
        Place(panel.title, "TOPLEFT", 214, -16, 122, 13)
        Place(panel.summary, "TOPLEFT", 214, -35, 148, 10)
        Place(panel.drag, "TOPLEFT", 208, -8, 130, 47)
        Place(panel.settingsDot, "TOPRIGHT", -10, -12)
        Place(panel.focusDivider, "BOTTOMLEFT", 202, 42, 1, 174)
        Place(panel.sideCaption, "TOPLEFT", 214, -68, 148, 12)
        Place(panel.focusReadout, "TOPLEFT", 214, -91, 148, 68)
        Place(panel.layoutHint, "TOPLEFT", 214, -91, 148, 54)
        Place(panel.sideGuide, "TOPLEFT", 214, -173, 148, 14)
        Place(panel.zoomOut, "BOTTOMLEFT", 12, 8)
        Place(panel.zoomLabel, "BOTTOMLEFT", 42, 12, 95, 12)
        Place(panel.zoomIn, "BOTTOMLEFT", 139, 8)
        Place(panel.combatToggle, "BOTTOMLEFT", 164, 9)
        Place(panel.compass, "BOTTOMLEFT", 185, 8)
        Place(panel.trailToggle, "BOTTOMLEFT", 211, 8)
        Place(panel.clearToggle, "TOPLEFT", 171, -10)
        Place(panel.routeToggle, "BOTTOMLEFT", 235, 8, 22, 20)
        Place(panel.arrowToggle, "BOTTOMLEFT", 195, 34, 16, 16)
        Place(panel.target, "BOTTOMLEFT", 259, 8)
        Place(panel.legend, "BOTTOMLEFT", 285, 8)
        Place(panel.minimize, "BOTTOMLEFT", 311, 8)
        Place(panel.close, "BOTTOMLEFT", 337, 8)
    else
        local compact = name == "compact"
        local footer = layout.footer
        Place(panel.field, "BOTTOM", 0, footer + (focused and layout.focus or 0) + 9)
        Place(panel.title, "TOPLEFT", 12, -6, compact and 136 or 100, 13)
        Place(panel.summary, "TOPLEFT", 12, -21, compact and 136 or 100, 10)
        Place(panel.drag, "TOPLEFT", 4, -3, compact and 144 or 106, 28)
        Place(panel.settingsDot, "TOPRIGHT", compact and -10 or -111, -6)
        Place(panel.focusDivider, "BOTTOM", 0, footer + layout.focus, layout.width - 24, 1)
        Place(panel.focusReadout, "BOTTOMLEFT", 12, footer + 8, layout.width - 24, compact and 50 or 32)
        if compact then
            Place(panel.zoomLabel, "BOTTOM", 0, 38, 92, 12)
            Place(panel.combatToggle, "BOTTOMLEFT", 178, 32)
            Place(panel.trailToggle, "BOTTOMLEFT", 18, 30)
            Place(panel.clearToggle, "TOPLEFT", 155, -6)
            Place(panel.routeToggle, "BOTTOMLEFT", 153, 32, 22, 18)
            Place(panel.arrowToggle, "BOTTOMLEFT", 180, 34, 16, 16)
        else
            Place(panel.zoomLabel, "BOTTOMLEFT", 118, 10, 62, 12)
            Place(panel.combatToggle, "BOTTOMLEFT", 72, 7)
            Place(panel.trailToggle, "BOTTOMLEFT", 94, 6)
            Place(panel.clearToggle, "TOPLEFT", 119, -6)
        end
        -- Compact puts its range above a single, evenly spaced row of controls.
        panel.zoomOut:ClearAllPoints()
        panel.zoomOut:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, compact and 8 or 6)
        panel.zoomIn:ClearAllPoints()
        if compact then
            panel.zoomIn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 38, 8)
            Place(panel.target, "BOTTOMLEFT", 64, 6)
            Place(panel.legend, "BOTTOMLEFT", 92, 6)
            Place(panel.compass, "BOTTOMLEFT", 120, 8)
            Place(panel.minimize, "BOTTOMLEFT", 148, 6)
            Place(panel.close, "BOTTOMLEFT", 174, 6)
        else
            panel.zoomIn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 6)
            Place(panel.compass, "BOTTOMLEFT", 42, 6)
            Place(panel.routeToggle, "BOTTOMLEFT", 185, 6, 22, 20)
            Place(panel.arrowToggle, "BOTTOMLEFT", 187, 30, 18, 18)
            Place(panel.target, "TOPRIGHT", -83, -5)
            Place(panel.legend, "TOPRIGHT", -57, -5)
            Place(panel.minimize, "TOPRIGHT", -31, -5)
            Place(panel.close, "TOPRIGHT", -5, -5)
        end
    end
    local textWidth = panel.focusReadout:GetWidth() - 24
    panel.focusName:SetWidth(textWidth)
    panel.focusMeta:SetSize(textWidth, name == "classic" and 12 or 28)
    panel.focusName:SetHeight(name == "squat" and 26 or 13)
    panel.focusName:SetWordWrap(name == "squat")
    if panel.resizeGrips then
        panel.resizeGrips.top:SetWidth(layout.width - 20)
        panel.resizeGrips.bottom:SetWidth(layout.width - 20)
        panel.resizeGrips.left:SetHeight(panel:GetHeight() - 20)
        panel.resizeGrips.right:SetHeight(panel:GetHeight() - 20)
    end
    if changed then
        -- Close pop-outs; opening them again chooses the side that fits the resized panel.
        if HideTrailPopup then HideTrailPopup() end
        if routeMenu.Hide then routeMenu.Hide() end
        local legend, picker = LegendAPI(), TargetPickerAPI()
        if legend and legend.Hide then legend.Hide() end
        if legend and legend.HideQuest then legend.HideQuest() end
        if picker and picker.Hide then picker.Hide() end
        panel.legend:SetAlpha(0.68)
        UpdateTargetButton()
    else
        local legend, picker = LegendAPI(), TargetPickerAPI()
        if legend and legend.Reanchor then legend.Reanchor(panel) end
        if legend and legend.ReanchorQuest and legend.IsQuestShown and legend.IsQuestShown() then
            legend.ReanchorQuest(CircleOnly() and panel.field or panel, panel)
        end
        if picker and picker.Reanchor then picker.Reanchor(CircleOnly() and panel.field or panel) end
    end
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Reanchor then quick.Reanchor(CircleOnly() and panel.field or panel) end
    local legend = LegendAPI()
    if legend and legend.ReanchorQuest and legend.IsQuestShown and legend.IsQuestShown() then
        legend.ReanchorQuest(CircleOnly() and panel.field or panel, panel)
    end
end

local function UpdateFocusReadout(target, player, selected)
    ApplyPanelLayout(selected and not CircleOnly())
    local squat = panel.layout == "squat"
    panel.focusReadout:SetShown(target ~= nil)
    panel.focusCard:SetShown(CircleOnly() and selected and target ~= nil)
    panel.focusDivider:SetShown(selected or squat)
    panel.layoutHint:SetShown(squat and target == nil)
    if squat then
        local outside = target and target.distance and target.distance > (displayedRange or Settings().vignetteRadarRange)
        local questContext = not target and #activeQuests > 0 and (Settings().vignetteRadarQuestDots
            or (Settings().vignetteRadarQuestAreas and Settings().vignetteRadarNorthUp))
        panel.sideCaption:SetText(selected and "TRACKING" or (outside and "OUTSIDE RADAR RANGE"
            or (target and "NEAREST DETECTION" or (questContext and "QUEST LOCATIONS" or "NO DETECTIONS"))))
        panel.sideGuide:SetText(selected and "CLICK AGAIN TO SHOW ALL" or (outside and "ZOOM OUT TO SEE IT"
            or (target and "CLICK TO FOCUS" or (questContext and "ZOOM FOR QUEST DETAIL" or "MOVE OR CHECK THE MAP"))))
        if not target then panel.layoutHint:SetText(questContext and "Your quest locations are on the radar."
            or "Nothing detected here yet.") end
    end
    panel.edgeArrow:Hide()
    if not target then return end
    panel.focusReadout.target = target
    panel.focusName:SetText((Favorite(target) and "* " or "") .. (target.name or "Detected vignette"))
    local age = target.stale and math.floor(math.max(0, Now() - target.lastSeenAt)) or nil
    local kind = target.isWorldBoss and "BOSS" or (target.category or "other"):upper()
    local detail = kind .. " | "
    detail = detail .. (target.distance and (math.floor(target.distance + 0.5) .. " yd") or "Distance unavailable")
    local separator = panel.layout == "classic" and " | " or "\n"
    if age then detail = detail .. separator .. "seen " .. age .. "s ago"
    elseif target.sample then detail = detail .. separator .. "preview"
    elseif Features() then
        if not target._healthAt or Now() - target._healthAt >= 1 then
            target._healthAt, target._health = Now(), Features().GetHealth(target)
        end
        if Settings().vignetteRadarShowHealth ~= false and target._health then
            detail = detail .. separator .. math.floor(target._health + 0.5) .. "% HP"
        end
    end
    panel.focusMeta:SetText(detail)
    local r, g, b = TargetColor(target)
    if CircleOnly() and selected then
        panel.focusCard.name:SetText(target.name or "Detected vignette")
        panel.focusCard.detail:SetText(TargetKind(target) .. " · " .. (target.distance
            and (math.floor(target.distance + .5) .. " yd") or "Distance Unknown"))
        local style = addon.VignetteRadarStyle
        local nr, ng, nb = r, g, b
        if style then nr, ng, nb = style.Color("accent") end
        panel.focusCard.name:SetTextColor(nr, ng, nb, 1)
    end
    if squat then panel.focusName:SetTextColor(r, g, b, 1)
    else panel.focusName:SetTextColor(0.88, 0.90, 0.92, 1) end
    local x, y
    if target.sample then x, y = PreviewPosition(target.x, target.y)
    elseif player and (player.headingAvailable or Settings().vignetteRadarNorthUp == true) then
        x, y = Project(target.worldX - player.worldX, target.worldY - player.worldY,
            target.distance or 0, ViewFacing(player.facing), 1, math.max(1, target.distance or 1))
    end
    panel.focusArrow:SetShown(x ~= nil and y ~= nil)
    if x and y then
        DrawArrow(panel.focusArrow, x, y, r, g, b)
        local range = displayedRange or tonumber(Settings().vignetteRadarRange) or 450
        if selected and not target.stale and target.distance and target.distance > range then
            local magnitude = math.sqrt(x * x + y * y)
            if magnitude > 0 then
                panel.edgeArrow:ClearAllPoints()
                panel.edgeArrow:SetPoint("CENTER", panel.field, "CENTER",
                    x / magnitude * panel.plotRadius, y / magnitude * panel.plotRadius)
                panel.edgeArrow.target = target
                DrawArrow(panel.edgeArrow, x, y, r, g, b)
                panel.edgeArrow:Show()
            end
        end
    end
end

local function UpdatePanelChrome()
    local circleOnly = CircleOnly()
    local style = addon.VignetteRadarStyle
    local showButtons = not circleOnly and Settings().vignetteRadarControlsVisible ~= false
    local showTools = circleOnly and Settings().vignetteRadarHoverTools ~= false
        and panel._hoverToolsShown == true
    local advanced = Settings().vignetteRadarAdvancedTools == true
    local frameButton = panel.frameToggle
    local quick = addon.VignetteRadarQuickConfig
    local legend = LegendAPI()
    local focused = FocusedTargetKey()
    local routeActive = addon.VignetteRadarWorldFocus
        and addon.VignetteRadarWorldFocus.IsRouteActive() or false
    local quickShown = quick and quick.IsShown and quick.IsShown() or false
    local legendShown = legend and ((legend.IsShown and legend.IsShown())
        or (legend.IsQuestShown and legend.IsQuestShown())) or false
    local helpShown = panel.emptyReason ~= nil
    if panel._chromeCircleOnly == circleOnly and panel._chromeButtons == showButtons
        and panel._chromeTools == showTools and panel._chromeLayout == panel.layout
        and panel._chromeHelp == helpShown and panel._chromeFocused == focused
        and panel._chromeRoute == routeActive and panel._chromeQuick == quickShown
        and panel._chromeLegend == legendShown
        and panel._chromeAdvanced == advanced
        and panel._chromeFrameHover == (frameButton and frameButton._hovered or false)
        and panel._chromeR == ACCENT[1] and panel._chromeG == ACCENT[2]
        and panel._chromeB == ACCENT[3]
        and panel._chromeStyleRev == (style and style.revision) then return end
    panel._chromeCircleOnly, panel._chromeButtons, panel._chromeTools =
        circleOnly, showButtons, showTools
    panel._chromeLayout, panel._chromeHelp, panel._chromeFocused =
        panel.layout, helpShown, focused
    panel._chromeRoute, panel._chromeQuick, panel._chromeLegend =
        routeActive, quickShown, legendShown
    panel._chromeAdvanced = advanced
    panel._chromeFrameHover = frameButton and frameButton._hovered or false
    panel._chromeR, panel._chromeG, panel._chromeB = ACCENT[1], ACCENT[2], ACCENT[3]
    panel._chromeStyleRev = style and style.revision
    local br, bg, bb = .02, .025, .03
    if style then br, bg, bb = style.Color("background") end
    panel:SetBackdropColor(math.min(.14, br * 2.7), math.min(.14, bg * 2.7),
        math.min(.14, bb * 2.7), circleOnly and 0 or .98)
    panel:SetBackdropBorderColor(1, 1, 1, circleOnly and 0 or .15)
    panel:EnableMouseWheel(not circleOnly)
    for _, control in ipairs({ panel.title, panel.summary, panel.drag, panel.settingsDot,
        panel.zoomLabel }) do
        control:SetShown(not circleOnly)
    end
    for _, control in ipairs({ panel.zoomOut, panel.zoomIn, panel.combatToggle,
        panel.trailToggle, panel.clearToggle, panel.routeToggle, panel.arrowToggle,
        panel.compass, panel.target, panel.legend, panel.minimize, panel.close }) do
        control:SetShown(showButtons)
    end
    if panel.emptyHelp then panel.emptyHelp:SetShown(not circleOnly and panel.emptyReason ~= nil) end
    if panel.hoverTools then
        if panel._hoverToolsVisible ~= showTools
            or panel._hoverFullConstellation ~= showButtons
            or panel._hoverAdvanced ~= advanced then
            panel._hoverToolsVisible = showTools
            panel._hoverFullConstellation = showButtons
            panel._hoverAdvanced = advanced
            -- Advanced Tools corners (Constellation, Player Tracker) stay hidden while off.
            -- Tools gathered into the Button Tray (UI/ButtonTray.lua) are shown by the tray.
            for _, tool in ipairs(panel.hoverTools) do
                if not tool._vrInTray then
                    tool:SetShown((advanced or not tool.advancedTool)
                        and (showTools or (showButtons and tool.toolID == "constellation")))
                end
            end
        end
        if panel.RefreshCornerTools then panel.RefreshCornerTools() end
    end
    if circleOnly then
        panel.focusReadout:Hide()
        panel.focusDivider:Hide()
        panel.layoutHint:Hide()
        panel.sideCaption:Hide()
        panel.sideGuide:Hide()
    else
        panel.sideCaption:SetShown(panel.layout == "squat")
        panel.sideGuide:SetShown(panel.layout == "squat")
    end
    if panel.resizeGrips then
        for _, grip in pairs(panel.resizeGrips) do grip:SetShown(not circleOnly) end
    end
    local button = panel.frameToggle
    if button then
        if button._circleOnly ~= circleOnly then
            button._circleOnly = circleOnly
            local direction = circleOnly and 1 or -1
            button.chevron[1]:SetStartPoint("CENTER", button, -direction * 2, -4)
            button.chevron[1]:SetEndPoint("CENTER", button, direction * 2, 0)
            button.chevron[2]:SetStartPoint("CENTER", button, direction * 2, 0)
            button.chevron[2]:SetEndPoint("CENTER", button, -direction * 2, 4)
        end
        local opacity = button._hovered and 1 or (circleOnly and .82 or .62)
        for _, line in ipairs(button.chevron) do
            line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], opacity)
        end
        button.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], button._hovered and .18 or 0)
    end
end

local appearanceKey, appearancePanel, appearanceLauncher
ApplyAppearance = function()
    local style = addon.VignetteRadarStyle
    if not style then return end
    local db = Settings()
    local key = table.concat({ db.vignetteRadarTheme or "verdant", style.revision or 0,
        db.vignetteRadarRingOpacity or .5, db.vignetteRadarBorderOpacity or .5,
        db.vignetteRadarChevronOpacity or .72,
        db.vignetteRadarHeadingOpacity or .46, db.vignetteRadarRangeLabelOpacity or .5 }, ":")
    if key == appearanceKey and panel == appearancePanel and launcher == appearanceLauncher then return end
    appearanceKey, appearancePanel, appearanceLauncher = key, panel, launcher
    local ar, ag, ab = style.Color("accent")
    local rr, rg, rb = style.Color("rings")
    local hr, hg, hb = style.Color("heading")
    local br, bg, bb = style.Color("background")
    ACCENT[1], ACCENT[2], ACCENT[3] = ar, ag, ab
    RED[1], RED[2], RED[3] = style.Color("boss")
    if panel then
        panel:SetBackdropColor(math.min(.14, br * 2.7), math.min(.14, bg * 2.7),
            math.min(.14, bb * 2.7), CircleOnly() and 0 or .98)
        panel:SetBackdropBorderColor(1, 1, 1, CircleOnly() and 0 or .15)
        panel.title:SetTextColor(ar, ag, ab, 1)
        panel.field.background:SetVertexColor(br, bg, bb, addon.VignetteRadarMinimapUnderlay
            and addon.VignetteRadarMinimapUnderlay.FaceAlpha() or .94)
        panel.field.halo:SetVertexColor(rr, rg, rb, .18 * db.vignetteRadarBorderOpacity)
        panel.squareBorder:SetVertexColor(rr, rg, rb, .12 * db.vignetteRadarBorderOpacity)
        local ringStrength = 2 * db.vignetteRadarRingOpacity * db.vignetteRadarRingOpacity
        for _, group in ipairs({ { panel.outerRing, .02 * db.vignetteRadarBorderOpacity, true },
            { panel.rangeRing, .045 },
            { panel.middleRing, .04 }, { panel.innerRing, .03 } }) do
            for _, line in ipairs(group[1]) do
                line:SetColorTexture(rr, rg, rb,
                    math.min(.75, group[3] and group[2] or group[2] * ringStrength))
            end
        end
        panel.direction:SetColorTexture(hr, hg, hb, db.vignetteRadarHeadingOpacity)
        for _, line in ipairs(panel.headingChevron) do
            line:SetColorTexture(hr, hg, hb, db.vignetteRadarChevronOpacity)
        end
        panel.player:SetVertexColor(ar, ag, ab, 1)
        panel.playerGlow:SetVertexColor(ar, ag, ab, .25)
        panel.innerLabel:SetTextColor(rr, rg, rb,
            .03 * db.vignetteRadarRangeLabelOpacity)
        panel.outerLabel:SetTextColor(rr, rg, rb,
            .04 * db.vignetteRadarRangeLabelOpacity)
        panel.settingsDot.dot:SetVertexColor(ar, ag, ab, 1)
        panel.settingsDot.rim:SetVertexColor(ar, ag, ab, .20)
        panel.settingsDot.inner:SetVertexColor(br, bg, bb, 1)
        panel.legend.glow:SetVertexColor(ar, ag, ab,
            panel.legend._hovered and .18 or panel.legend._open and .12 or 0)
        panel.minimize.line:SetColorTexture(ar, ag, ab, .86)
        panel.minimize.glow:SetVertexColor(ar, ag, ab, panel.minimize._hovered and .18 or 0)
        panel.close.glow:SetVertexColor(ar, ag, ab, panel.close._hovered and .18 or 0)
        for _, button in ipairs({ panel.zoomOut, panel.zoomIn, panel.compass,
            panel.trailToggle, panel.routeToggle, panel.arrowToggle }) do
            if button and button.RefreshAppearance then button:RefreshAppearance() end
        end
        if panel.RefreshCornerTools then panel.RefreshCornerTools() end
        if addon.VignetteRadarControls and addon.VignetteRadarControls.RefreshRoundedStatusSurface then
            addon.VignetteRadarControls.RefreshRoundedStatusSurface(panel.focusCard)
        end
        if RefreshTrailPopup then RefreshTrailPopup() end
        if routeMenu.Refresh then routeMenu.Refresh() end
        if panel.legend and panel.legend.dots then
            for index, slot in ipairs({ "rare", "treasure", "event" }) do
                panel.legend.dots[index]:SetVertexColor(style.Color(slot))
            end
        end
    end
    if launcher then
        launcher.face:SetVertexColor(br, bg, bb, .98)
        launcher.depth:SetVertexColor(ar, ag, ab, .07)
        launcher.center:SetVertexColor(ar, ag, ab, 1)
        launcher.centerGlow:SetVertexColor(ar, ag, ab, .22)
        launcher.direction:SetColorTexture(hr, hg, hb, db.vignetteRadarHeadingOpacity)
        for _, line in ipairs(launcher.ring) do line:SetColorTexture(rr, rg, rb, .28) end
        for index, line in ipairs(launcher.dial) do
            local mix = .5 + .5 * math.cos((index - 1) * TWO_PI / #launcher.dial)
            line:SetColorTexture(ar * mix + hr * (1 - mix),
                ag * mix + hg * (1 - mix), ab * mix + hb * (1 - mix), .64)
        end
        for _, line in ipairs(launcher.cardinals) do
            line:SetColorTexture(hr, hg, hb, .9)
        end
        for _, line in ipairs(launcher.chevron) do
            line:SetColorTexture(hr, hg, hb, db.vignetteRadarChevronOpacity)
        end
        for index, facet in ipairs(launcher.facets) do
            if index % 2 == 0 then facet.core:SetVertexColor(hr, hg, hb, 1)
            else facet.core:SetVertexColor(ar, ag, ab, 1) end
        end
        launcher.chrome:SetVertexColor(.46, .48, .52, .26)
        launcher.bezel:SetVertexColor(ar, ag, ab, 1)
        launcher.closed:SetVertexColor(.62, .65, .70, 1)
        launcher.titleLabel:SetTextColor(hr, hg, hb, .92)
        launcher.readoutLine:SetColorTexture(ar, ag, ab, .35)
        for _, line in ipairs(launcher.expandChevron) do
            line:SetColorTexture(ar, ag, ab, .84)
        end
    end
    if addon.VignetteRadarControls and addon.VignetteRadarControls.RefreshTheme then
        addon.VignetteRadarControls.RefreshTheme()
    end
    local legend = LegendAPI()
    if legend and legend.Refresh then legend.Refresh() end
end

local function UpdateFullSweep(elapsed)
    if not (panel and panel.sweepLines) then return end
    local enabled = Settings().vignetteRadarFullSweep == true and panel:IsShown()
    if not enabled then
        for _, line in ipairs(panel.sweepLines) do line:Hide() end
        panel._sweepDrawnAt = nil
        return
    end
    -- OnUpdate advances the sweep right before Render asks again with zero.
    local frameTime = Now()
    if (elapsed or 0) == 0 and panel._sweepDrawnAt == frameTime
        and panel._sweepDrawnRadius == panel.plotRadius then return end
    panel._sweepDrawnAt, panel._sweepDrawnRadius = frameTime, panel.plotRadius
    panel._sweepAngle = ((panel._sweepAngle or 0) + (elapsed or 0) * .72) % TWO_PI
    for index, line in ipairs(panel.sweepLines) do
        local angle = panel._sweepAngle - ((index - 1) * .13)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], index == 1 and .17 or .07)
        line:SetStartPoint("CENTER", panel.field, 0, 0)
        line:SetEndPoint("CENTER", panel.field, math.sin(angle) * panel.plotRadius,
            math.cos(angle) * panel.plotRadius)
        line:Show()
    end
end

local function UpdateCombatToggle()
    if not (panel and panel.combatToggle) then return end
    local button = panel.combatToggle
    local keepVisible = Settings().vignetteRadarKeepVisibleCombat == true
    if button.keepVisible == keepVisible and button._drawHovered == button._hovered
        and button._drawR == ACCENT[1] and button._drawG == ACCENT[2]
        and button._drawB == ACCENT[3] then return end
    button._drawHovered = button._hovered
    button._drawR, button._drawG, button._drawB = ACCENT[1], ACCENT[2], ACCENT[3]
    local red, green, blue, opacity
    if keepVisible then
        red, green, blue, opacity = ACCENT[1], ACCENT[2], ACCENT[3], 1
    else
        red, green, blue, opacity = .62, .70, .71, button._hovered and .9 or .62
    end
    for _, line in ipairs(button.eye) do
        line:SetColorTexture(red, green, blue, opacity)
    end
    button.pupil:SetVertexColor(red, green, blue, opacity)
    button.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3],
        button._hovered and .16 or (keepVisible and .1 or 0))
    button.keepVisible = keepVisible
end

local function UpdateTrailToggle()
    if not (panel and panel.trailToggle) then return end
    local button = panel.trailToggle
    local style = Settings().vignetteRadarTrailStyle or "dashes"
    local selected = Settings().vignetteRadarBreadcrumbs == true
    if button._style ~= style then
        button._style = style
        local definition = TRAIL_STYLE_BY_ID[style] or TRAIL_STYLES[1]
        for index, line in ipairs(button.trailMarks) do
            local x = (index - 2) * 5
            local segments = definition.segments
            for part = 1, 4 do
                local glyphLine = part == 1 and line or button.trailExtras[index][part - 1]
                local segment = segments and segments[part]
                if segment then
                    local scale = definition.alternating and index % 2 == 0 and .3 or .6
                    glyphLine:SetThickness(segment[5] * .8)
                    glyphLine:SetStartPoint("CENTER", button,
                        x + segment[1] * scale, segment[2] * scale)
                    glyphLine:SetEndPoint("CENTER", button,
                        x + segment[3] * scale, segment[4] * scale)
                    glyphLine:Show()
                elseif part == 1 and (definition.dot or definition.square) then
                    local size = definition.alternating and index % 2 == 0 and 2 or 3.2
                    glyphLine:SetThickness(size)
                    glyphLine:SetStartPoint("CENTER", button, x - .1, 0)
                    glyphLine:SetEndPoint("CENTER", button, x + .1, 0)
                    glyphLine:Show()
                else
                    glyphLine:Hide()
                end
            end
        end
        button:RefreshAppearance()
    end
    if button._selected ~= selected then button._selected = selected; button:RefreshAppearance() end
end

HideTrailPopup = function()
    if trailPopup and trailPopup:IsShown() then trailPopup:Hide() end
end

RefreshTrailPopup = function()
    if not trailPopup then return end
    local style = addon.VignetteRadarStyle
    local ar, ag, ab = ACCENT[1], ACCENT[2], ACCENT[3]
    local br, bg, bb = .045, .052, .06
    if style then
        ar, ag, ab = style.Color("accent")
        br, bg, bb = style.Color("background")
    end
    trailPopup:SetBackdropColor(math.min(.14, br * 2.7), math.min(.14, bg * 2.7),
        math.min(.14, bb * 2.7), .98)
    addon.VignetteRadarControls.RefreshPopupSurface(trailPopup)
    trailPopup.title:SetTextColor(ar, ag, ab, 1)
    trailPopup.rule:SetColorTexture(ar, ag, ab, .18)
    local trailMode = Settings().vignetteRadarTrailMode or "off"
    for _, button in ipairs(trailPopup.modeButtons or {}) do
        button._selected = button.mode == trailMode
        button:RefreshAppearance()
    end
    trailPopup.close.label:SetTextColor(ar, ag, ab, trailPopup.close._hovered and 1 or .7)
    trailPopup.close.glow:SetVertexColor(ar, ag, ab, trailPopup.close._hovered and .18 or 0)
    trailPopup.scrollTrack:SetColorTexture(ar, ag, ab, .13)
    trailPopup.scrollThumb:SetColorTexture(ar, ag, ab, .8)
    for _, row in ipairs(trailPopup.rows) do
        local selected = row.style == Settings().vignetteRadarTrailStyle
        row:SetBackdropColor(ar, ag, ab, selected and .07 or row._hovered and .05 or 0)
        row:SetBackdropBorderColor(ar, ag, ab, 0)
        row.rail:SetColorTexture(ar, ag, ab, selected and .82 or row._hovered and .28 or .08)
        row.label:SetTextColor(selected and ar or .82, selected and ag or .87,
            selected and ab or .88, 1)
        row.track:SetColorTexture(ar, ag, ab, .12)
        for _, mark in ipairs(row.marks) do
            if row.definition.dot or row.definition.square then mark:SetVertexColor(ar, ag, ab, .9)
            else mark:SetColorTexture(ar, ag, ab, .9) end
        end
        for _, mark in ipairs(row.extraMarks) do mark:SetColorTexture(ar, ag, ab, .9) end
    end
    for _, control in ipairs(trailPopup.controls) do
        control.label:SetTextColor(.72, .82, .81, 1)
        local value = Settings()[control.key]
        if not control.value._editing then control.value:SetText(control.format(value)) end
        control.value:SetTextColor(ar, ag, ab, 1)
        if control.key == "vignetteRadarTrailLifetime" or control.min then
            control.value:SetBackdropColor(ar, ag, ab, .055)
            control.value:SetBackdropBorderColor(ar, ag, ab, .3)
        end
        for _, button in ipairs({ control.minus, control.plus }) do
            local nextValue
            if control.key == "vignetteRadarTrailLifetime" then
                nextValue = value + button.direction
                if nextValue < 1 or nextValue > 300 then nextValue = nil end
            elseif control.min then
                local nextPercent = math.floor(value * 100 + .5) + button.direction * control.step
                if nextPercent >= control.min and nextPercent <= control.max then
                    nextValue = nextPercent / 100
                end
            else
                for slot, candidate in ipairs(control.values) do
                    if candidate == value then nextValue = control.values[slot + button.direction]; break end
                end
            end
            local available = nextValue ~= nil
            if button._available ~= available then
                -- SetEnabled can fire OnEnter while the cursor is on a stepper.
                -- Record the state first so that hover cannot refresh in a loop.
                button._available = available
                button:SetEnabled(available)
            end
            local opacity = not nextValue and .3 or button._hovered and 1 or .78
            button.glow:SetVertexColor(ar, ag, ab, nextValue and button._hovered and .2 or 0)
            for _, stroke in ipairs(button.strokes) do
                stroke:SetColorTexture(button._hovered and ar or .69,
                    button._hovered and ag or .77, button._hovered and ab or .78, opacity)
            end
        end
    end
    trailPopup:DrawPreviews()
end

local function PositionTrailPopup(anchor)
    if not (trailPopup and anchor) then return end
    trailPopup:ClearAllPoints()
    local screenWidth = UIParent and UIParent:GetWidth()
    local parentScale = UIParent:GetEffectiveScale()
    local function Edge(region, method)
        local value = SafeNumber(region[method](region))
        return value and value * region:GetEffectiveScale() / parentScale
    end
    if not panel or anchor ~= panel.trailToggle then
        local left, right = Edge(anchor, "GetLeft"), Edge(anchor, "GetRight")
        if screenWidth and right and screenWidth - right >= trailPopup:GetWidth() + 16 then
            trailPopup:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        elseif left and left >= trailPopup:GetWidth() + 16 then
            trailPopup:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
        else
            trailPopup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        end
        return
    end
    local panelLeft, panelRight = Edge(panel, "GetLeft"), Edge(panel, "GetRight")
    if screenWidth and panelRight and screenWidth - panelRight >= trailPopup:GetWidth() + 16 then
        trailPopup:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 8, 0)
    elseif panelLeft and panelLeft >= trailPopup:GetWidth() + 16 then
        trailPopup:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", -8, 0)
    else
        local buttonLeft, buttonRight = Edge(anchor, "GetLeft"), Edge(anchor, "GetRight")
        local screenHeight, buttonTop = UIParent:GetHeight(), Edge(anchor, "GetTop")
        local above = screenHeight and buttonTop and screenHeight - buttonTop >= trailPopup:GetHeight() + 16
        local alignRight = screenWidth and buttonLeft and buttonLeft + trailPopup:GetWidth() > screenWidth - 8
            and buttonRight ~= nil
        trailPopup:SetPoint(above and (alignRight and "BOTTOMRIGHT" or "BOTTOMLEFT")
                or (alignRight and "TOPRIGHT" or "TOPLEFT"), anchor,
            above and (alignRight and "TOPRIGHT" or "TOPLEFT")
                or (alignRight and "BOTTOMRIGHT" or "BOTTOMLEFT"), 0, above and 8 or -8)
    end
end

local function EnsureTrailPopup()
    if trailPopup then return trailPopup end
    trailPopup = CreateFrame("Frame", "VignetteRadarTrailStylePopup", UIParent, "BackdropTemplate")
    trailPopup:SetSize(244, 388)
    trailPopup:SetFrameStrata("DIALOG")
    trailPopup:SetClampedToScreen(true)
    trailPopup:EnableMouse(true)
    Surface(trailPopup)
    addon.VignetteRadarControls.PopupSurface(trailPopup)
    trailPopup.title = Text(trailPopup, 10, "TRAIL STYLE & FLOW", true)
    trailPopup.title:SetPoint("TOPLEFT", 11, -9)
    trailPopup.rule = trailPopup:CreateTexture(nil, "ARTWORK")
    trailPopup.rule:SetPoint("TOPLEFT", 9, -28)
    trailPopup.rule:SetPoint("TOPRIGHT", -9, -28)
    trailPopup.rule:SetHeight(1)
    -- Trails mode (Off / Follow / Lead / Both), the same setting as Radar >
    -- Exploring > Trails: Follow draws where you have been, Lead the way
    -- ahead to your target and next stops.
    trailPopup.modeButtons = {}
    for _, choice in ipairs({ { "off", "Off" }, { "follow", "Follow" }, { "lead", "Lead" }, { "both", "Both" } }) do
        local button = addon.VignetteRadarControls.Button(trailPopup, choice[2], 50, 21)
        button.mode = choice[1]
        button:SetScript("OnClick", function(self)
            addon.SetVignetteRadarTrailMode(self.mode)
            RefreshTrailPopup()
        end)
        trailPopup.modeButtons[#trailPopup.modeButtons + 1] = button
    end
    addon.VignetteRadarControls.FlowButtons(trailPopup, trailPopup.modeButtons, 10, -34, 224, 4, 21)
    trailPopup.close = CreateFrame("Button", nil, trailPopup)
    trailPopup.close:SetSize(18, 18)
    trailPopup.close:SetPoint("TOPRIGHT", -6, -5)
    trailPopup.close.label = Text(trailPopup.close, 15, "×")
    trailPopup.close.label:SetAllPoints()
    trailPopup.close.label:SetJustifyH("CENTER")
    trailPopup.close.glow = trailPopup.close:CreateTexture(nil, "BACKGROUND")
    trailPopup.close.glow:SetSize(18, 18)
    trailPopup.close.glow:SetPoint("CENTER")
    trailPopup.close.glow:SetTexture(CIRCLE_TEXTURE)
    trailPopup.close:SetScript("OnClick", HideTrailPopup)
    trailPopup.close:SetScript("OnEnter", function(self)
        self._hovered = true
        RefreshTrailPopup()
    end)
    trailPopup.close:SetScript("OnLeave", function(self)
        self._hovered = false
        RefreshTrailPopup()
    end)
    trailPopup.scroll = CreateFrame("ScrollFrame", nil, trailPopup)
    trailPopup.scroll:SetSize(208, 135)
    trailPopup.scroll:SetPoint("TOPLEFT", trailPopup, "TOPLEFT", 8, -62)
    trailPopup.scroll:EnableMouseWheel(true)
    trailPopup.content = CreateFrame("Frame", nil, trailPopup.scroll)
    trailPopup.content:SetSize(208, #TRAIL_STYLES * 27)
    trailPopup.scroll:SetScrollChild(trailPopup.content)
    trailPopup.scrollIndex = 0
    trailPopup.scrollTrack = trailPopup:CreateTexture(nil, "ARTWORK")
    trailPopup.scrollTrack:SetSize(3, 99)
    trailPopup.scrollTrack:SetPoint("TOPLEFT", trailPopup, "TOPLEFT", 228, -80)
    trailPopup.scrollThumb = trailPopup:CreateTexture(nil, "OVERLAY")
    trailPopup.scrollThumb:SetSize(3, math.max(24, math.floor(99 * 5 / #TRAIL_STYLES + .5)))
    trailPopup.rows = {}
    for index, definition in ipairs(TRAIL_STYLES) do
        local row = CreateFrame("Button", nil, trailPopup.content, "BackdropTemplate")
        row:SetSize(202, 24)
        row:SetPoint("TOPLEFT", trailPopup.content, "TOPLEFT", 0, -(index - 1) * 27)
        Surface(row)
        row.style, row.definition = definition.id, definition
        row.rail = row:CreateTexture(nil, "ARTWORK")
        row.rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 1)
        row.rail:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 1)
        row.rail:SetHeight(1)
        row.label = Text(row, 10, definition.label)
        row.label:SetPoint("LEFT", 11, 0)
        row.label:SetWidth(96)
        row.track = row:CreateTexture(nil, "ARTWORK")
        row.track:SetSize(79, 1)
        row.track:SetPoint("RIGHT", -9, 0)
        row.marks, row.extraMarks, row.extraByMark = {}, {}, {}
        -- The shortest style at 25% spacing needs 25 marks in this lane.
        for markIndex = 1, 13 do
            local mark
            if definition.dot or definition.square then
                mark = row:CreateTexture(nil, "OVERLAY")
                mark:SetSize(4, 4)
                mark:SetTexture(definition.square and SQUARE_TEXTURE or CIRCLE_TEXTURE)
            else
                mark = row:CreateLine(nil, "OVERLAY")
                row.extraByMark[markIndex] = {}
                for part = 2, #definition.segments do
                    local extra = row:CreateLine(nil, "OVERLAY")
                    row.extraMarks[#row.extraMarks + 1] = extra
                    row.extraByMark[markIndex][part - 1] = extra
                end
            end
            row.marks[markIndex] = mark
        end
        row:SetScript("OnClick", function(self)
            HideTrailPopup()
            addon.SetVignetteRadarTrailStyle(self.style, true)
        end)
        row:SetScript("OnEnter", function(self)
            self._hovered = true
            RefreshTrailPopup()
        end)
        row:SetScript("OnLeave", function(self)
            self._hovered = false
            RefreshTrailPopup()
        end)
        trailPopup.rows[index] = row
    end
    local function ScrollStyles(direction)
        local maxIndex = #TRAIL_STYLES - 5
        trailPopup.scrollIndex = math.max(0, math.min(maxIndex, trailPopup.scrollIndex + direction))
        trailPopup.scroll:SetVerticalScroll(trailPopup.scrollIndex * 27)
        trailPopup.scrollThumb:ClearAllPoints()
        local travel = trailPopup.scrollTrack:GetHeight() - trailPopup.scrollThumb:GetHeight()
        trailPopup.scrollThumb:SetPoint("TOPLEFT", trailPopup.scrollTrack, "TOPLEFT", 0,
            maxIndex > 0 and -travel * trailPopup.scrollIndex / maxIndex or 0)
        trailPopup:DrawPreviews()
    end
    trailPopup.ScrollStyles = ScrollStyles
    trailPopup.scroll:SetScript("OnMouseWheel", function(_, delta)
        ScrollStyles(delta > 0 and -1 or 1)
    end)
    trailPopup.scrollGrip = CreateFrame("Button", nil, trailPopup)
    trailPopup.scrollGrip:SetSize(16, 99)
    trailPopup.scrollGrip:SetPoint("TOPLEFT", trailPopup, "TOPLEFT", 221, -80)
    trailPopup.scrollGrip:RegisterForDrag("LeftButton")
    local function ScrollAtCursor()
        if type(GetCursorPosition) ~= "function" then return end
        local _, cursorY = GetCursorPosition()
        local top = trailPopup.scrollTrack:GetTop()
        if not (cursorY and top) then return end
        local scale = UIParent:GetEffectiveScale()
        local travel = trailPopup.scrollTrack:GetHeight() - trailPopup.scrollThumb:GetHeight()
        local ratio = (top - cursorY / scale - trailPopup.scrollThumb:GetHeight() / 2) / travel
        local index = math.floor(math.max(0, math.min(1, ratio)) * (#TRAIL_STYLES - 5) + .5)
        ScrollStyles(index - trailPopup.scrollIndex)
    end
    trailPopup.scrollGrip:SetScript("OnMouseDown", ScrollAtCursor)
    trailPopup.scrollGrip:SetScript("OnDragStart", function(self)
        self._dragging = true
        ScrollAtCursor()
    end)
    trailPopup.scrollGrip:SetScript("OnDragStop", function(self) self._dragging = false end)
    trailPopup.scrollGrip:SetScript("OnUpdate", function(self)
        if self._dragging then ScrollAtCursor() end
    end)
    trailPopup.rule2 = trailPopup:CreateTexture(nil, "ARTWORK")
    trailPopup.rule2:SetPoint("TOPLEFT", trailPopup, "TOPLEFT", 9, -205)
    trailPopup.rule2:SetPoint("TOPRIGHT", trailPopup, "TOPRIGHT", -9, -205)
    trailPopup.rule2:SetHeight(1)
    trailPopup.rule2:SetColorTexture(.5, .7, .7, .16)
    trailPopup.controls = {}
    local controlDefinitions = {
        { key="vignetteRadarTrailSpacing", label="Spacing", values=TRAIL_SPACINGS,
            format=function(value) return math.floor(value * 100 + .5) .. "%" end },
        { key="vignetteRadarTrailSpeed", label="Flow", values=TRAIL_SPEEDS,
            format=function(value) return value == 0 and "Still" or value .. "×" end },
        { key="vignetteRadarTrailSize", label="Size", min=10, max=200, step=5,
            format=function(value) return math.floor(value * 100 + .5) .. "%" end },
        { key="vignetteRadarTrailLifetime", label="Fade (seconds)",
            format=function(value) return tostring(value) end },
        { key="vignetteRadarTrailTailFade", label="Fade amount", min=0, max=100, step=1,
            format=function(value) return math.floor(value * 100 + .5) .. "%" end },
        { key="vignetteRadarTrailFadeSpan", label="Faded part", min=0, max=100, step=1,
            format=function(value) return math.floor(value * 100 + .5) .. "%" end },
    }
    for index, definition in ipairs(controlDefinitions) do
        local y = -212 - (index - 1) * 27
        local control = { key=definition.key, values=definition.values, format=definition.format,
            min=definition.min, max=definition.max, step=definition.step }
        control.label = Text(trailPopup, 10, definition.label)
        control.label:SetPoint("TOPLEFT", trailPopup, "TOPLEFT", 12, y - 3)
        if control.key == "vignetteRadarTrailLifetime" or control.min then
            control.value = CreateFrame("EditBox", nil, trailPopup, "BackdropTemplate")
            Surface(control.value)
            addon.VignetteRadarStyle.SetFont(control.value, 10, "")
            control.value:SetAutoFocus(false)
            control.value:SetMaxLetters(3)
            control.value:SetTextInsets(2, 2, 0, 0)
            control.value:SetScript("OnEditFocusGained", function(self) self._editing = true end)
            local function CommitValue(self)
                self._editing = false
                local raw = self:GetText() or ""
                local number = raw:match("^%s*(%d+)%%?%s*$")
                if number then
                    local value = tonumber(number)
                    if control.min then value = value / 100 end
                    addon.SetVignetteRadarTrailOption(control.key, value)
                end
                RefreshTrailPopup()
            end
            control.value:SetScript("OnEnterPressed", function(self)
                CommitValue(self)
                self:ClearFocus()
            end)
            control.value:SetScript("OnEditFocusLost", CommitValue)
            control.value:SetScript("OnEscapePressed", function(self)
                self:SetText(control.format(Settings()[control.key]))
                self._editing = false
                self:ClearFocus()
            end)
        else
            control.value = Text(trailPopup, 10, "")
        end
        control.value:SetSize(46, 20)
        control.value:SetPoint("TOPLEFT", trailPopup, "TOPLEFT", 156, y)
        control.value:SetJustifyH("CENTER")
        for _, direction in ipairs({ -1, 1 }) do
            local button = CreateFrame("Button", nil, trailPopup)
            button:SetSize(20, 20)
            button:SetPoint("TOPLEFT", trailPopup, "TOPLEFT", direction < 0 and 132 or 208, y)
            button.direction = direction
            button.glow = button:CreateTexture(nil, "BACKGROUND")
            button.glow:SetSize(18, 18)
            button.glow:SetPoint("CENTER")
            button.glow:SetTexture(CIRCLE_TEXTURE)
            button.strokes = {}
            local horizontal = button:CreateLine(nil, "OVERLAY")
            horizontal:SetThickness(2)
            horizontal:SetStartPoint("CENTER", button, -5, 0)
            horizontal:SetEndPoint("CENTER", button, 5, 0)
            button.strokes[1] = horizontal
            if direction > 0 then
                local vertical = button:CreateLine(nil, "OVERLAY")
                vertical:SetThickness(2)
                vertical:SetStartPoint("CENTER", button, 0, -5)
                vertical:SetEndPoint("CENTER", button, 0, 5)
                button.strokes[2] = vertical
            end
            button:SetScript("OnClick", function()
                local current = Settings()[control.key]
                if control.key == "vignetteRadarTrailLifetime" then
                    addon.SetVignetteRadarTrailOption(control.key, current + direction)
                elseif control.min then
                    local currentPercent = math.floor(current * 100 + .5)
                    local nextPercent = math.max(control.min, math.min(control.max,
                        currentPercent + direction * control.step))
                    addon.SetVignetteRadarTrailOption(control.key, nextPercent / 100)
                else
                    for slot, value in ipairs(control.values) do
                        if value == current then
                            local nextValue = control.values[slot + direction]
                            if nextValue then addon.SetVignetteRadarTrailOption(control.key, nextValue) end
                            break
                        end
                    end
                end
            end)
            button:SetScript("OnEnter", function(self) self._hovered = true; RefreshTrailPopup() end)
            button:SetScript("OnLeave", function(self) self._hovered = false; RefreshTrailPopup() end)
            if direction < 0 then control.minus = button else control.plus = button end
        end
        trailPopup.controls[index] = control
    end
    trailPopup:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        local speed = Settings().vignetteRadarTrailSpeed or 1
        if speed == 0 then self._elapsed = 0; return end
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < .05 then return end
        self._phase = ((self._phase or 0) + math.min(self._elapsed, .1) * 42
            * speed)
        self._elapsed = 0
        self:DrawPreviews()
    end)
    function trailPopup:DrawPreviews()
        local r, g, b = ACCENT[1], ACCENT[2], ACCENT[3]
        if addon.VignetteRadarStyle then r, g, b = addon.VignetteRadarStyle.Color("accent") end
        local settings = Settings()
        local spacing = settings.vignetteRadarTrailSpacing or 1
        local sizeScale = settings.vignetteRadarTrailSize or 1
        local tailFade = settings.vignetteRadarTrailTailFade or 0
        local fadeSpan = settings.vignetteRadarTrailFadeSpan or 1
        local lifetime = settings.vignetteRadarTrailLifetime or 180
        local phase = self._phase or 0
        for rowIndex = self.scrollIndex + 1, self.scrollIndex + 5 do
            local row = self.rows[rowIndex]
            local gap = row.definition.spacing * spacing
            for index, mark in ipairs(row.marks) do
                local x = 21 + (index - 1) * gap
                if x <= 77 then
                    -- Preview a recent 30-second slice. Mapping the tiny lane
                    -- across the full lifetime made its older marks nearly
                    -- invisible at the default three-minute setting.
                    local age = (77 - x) * 30 / 56
                    local glow = settings.vignetteRadarTrailSpeed == 0 and 1 or .74 + .26
                        * math.cos((index - 1) * .85 - phase / gap * .85)
                    local alpha = (.65 + .30 * math.max(0, math.min(1, (x - 21) / 56)))
                        * math.max(0, 1 - age / lifetime)
                        * TrailFadeMultiplier(math.max(0, math.min(1, (77 - x) / 56)), tailFade, fadeSpan)
                        * glow
                    DrawTrailGlyph(row.definition, mark, row.extraByMark[index], row, x, 0, 1, 0,
                        r, g, b, alpha, index, sizeScale)
                else
                    mark:Hide()
                    for _, extra in ipairs(row.extraByMark[index] or {}) do extra:Hide() end
                end
            end
        end
    end
    ScrollStyles(0)
    trailPopup:SetScript("OnHide", function()
        if panel and panel.trailToggle then
            panel.trailToggle._popupOpen = false
            panel.trailToggle:RefreshAppearance()
        end
    end)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarTrailStylePopup"
    end
    trailPopup:Hide()
    return trailPopup
end

ToggleTrailPopup = function(anchor, keepConfig)
    local popup = EnsureTrailPopup()
    if popup:IsShown() then HideTrailPopup(); return false end
    routeMenu.Hide()
    local legend, picker = LegendAPI(), TargetPickerAPI()
    if legend and legend.Hide then legend.Hide() end
    if picker and picker.Hide then picker.Hide() end
    if not keepConfig and addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Hide() end
    PositionTrailPopup(anchor)
    local selectedIndex = 1
    for index, definition in ipairs(TRAIL_STYLES) do
        if definition.id == Settings().vignetteRadarTrailStyle then selectedIndex = index; break end
    end
    if selectedIndex <= popup.scrollIndex then
        popup.ScrollStyles(selectedIndex - 1 - popup.scrollIndex)
    elseif selectedIndex > popup.scrollIndex + 5 then
        popup.ScrollStyles(selectedIndex - 5 - popup.scrollIndex)
    end
    popup._phase, popup._elapsed = 0, 0
    popup:DrawPreviews()
    RefreshTrailPopup()
    popup:Show()
    if panel and panel.trailToggle then
        panel.trailToggle._popupOpen = true
        panel.trailToggle:RefreshAppearance()
    end
    return true
end

function addon.ToggleVignetteRadarTrailPicker(anchor)
    return ToggleTrailPopup(anchor, true)
end

routeMenu.Hide = function()
    if routeMenu.popup and routeMenu.popup:IsShown() then routeMenu.popup:Hide() end
end

function routeMenu.Note(label, message, objective)
    if type(message) ~= "string" or message == "" then return end
    local anchor = panel and panel:IsShown() and (CircleOnly() and panel.field or panel)
        or launcher and launcher:IsShown() and launcher
    if not anchor then return end
    if not routeMenu.toast then
        local toast = CreateFrame("Frame", "VignetteRadarRouteNote", UIParent)
        toast:SetSize(304, 62)
        toast:SetFrameStrata("DIALOG")
        toast:SetClampedToScreen(true)
        toast:EnableMouse(false)
        addon.VignetteRadarControls.RoundedStatusSurface(toast)
        toast.heading = Text(toast, 9, "WORLD FOCUS", true)
        toast.heading:SetPoint("TOPLEFT", toast, "TOPLEFT", 14, -9)
        toast.message = Text(toast, 11, "")
        toast.message:SetPoint("TOPLEFT", toast, "TOPLEFT", 14, -23)
        toast.message:SetHeight(30)
        toast.message:SetWordWrap(true)
        if toast.message.SetMaxLines then toast.message:SetMaxLines(2) end
        toast.objective = Text(toast, 11, "")
        toast.objective:SetPoint("TOPLEFT", toast, "TOPLEFT", 14, -57)
        toast.objective:SetHeight(28)
        toast.objective:SetWordWrap(true)
        if toast.objective.SetMaxLines then toast.objective:SetMaxLines(2) end
        toast.objective:Hide()
        toast.count = Text(toast, 10, "")
        toast.count:SetPoint("TOPLEFT", toast, "TOPLEFT", 14, -91)
        toast.count:SetHeight(12)
        toast.count:Hide()
        toast:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            local fadeEnd = self.fadeEnd or 3.4
            local fadeStart = fadeEnd - .6
            if self.elapsed >= fadeEnd then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            elseif self.elapsed > fadeStart then
                self:SetAlpha(math.max(0, (fadeEnd - self.elapsed) / .6))
            end
        end)
        toast.update = toast:GetScript("OnUpdate")
        toast:Hide()
        routeMenu.toast = toast
    end
    local toast = routeMenu.toast
    local style = addon.VignetteRadarStyle
    local ar, ag, ab = ACCENT[1], ACCENT[2], ACCENT[3]
    if style then ar, ag, ab = style.Color("accent") end
    toast.heading:SetText(type(label) == "string" and label or "WORLD FOCUS")
    toast.heading:SetTextColor(ar, ag, ab, 1)
    toast.message:SetText(message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("[%c]", " "))
    toast.message:SetTextColor(.91, .95, .96, 1)
    local detailed = type(objective) == "table" and type(objective.label) == "string"
        and objective.label ~= ""
    toast.fadeEnd = detailed and 5 or 3.4
    toast:SetHeight(detailed and 110 or 62)
    toast.objective:SetShown(detailed)
    toast.count:SetShown(detailed)
    if detailed then
        toast.objective:SetText(objective.label:gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|r", ""):gsub("|T.-|t", ""):gsub("[%c]", " "))
        toast.objective:SetTextColor(.91, .95, .96, 1)
        toast.count:SetText(type(objective.count) == "string"
            and ("Objective · " .. objective.count) or "Current Objective")
        toast.count:SetTextColor(ar, ag, ab, 1)
    end
    toast:SetWidth(math.max(260, math.min(380, (anchor:GetWidth() or 304) - 12)))
    toast.message:SetWidth(toast:GetWidth() - 28)
    toast.objective:SetWidth(toast:GetWidth() - 28)
    toast.count:SetWidth(toast:GetWidth() - 28)
    addon.VignetteRadarControls.RefreshRoundedStatusSurface(toast)
    toast:ClearAllPoints()
    local bottom = anchor.GetBottom and anchor:GetBottom()
    local anchorScale = anchor.GetEffectiveScale and anchor:GetEffectiveScale() or 1
    local uiScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if bottom and bottom * anchorScale / math.max(.01, uiScale) < toast:GetHeight() + 12 then
        toast:SetPoint("BOTTOM", anchor, "TOP", 0, 7)
    else
        toast:SetPoint("TOP", anchor, "BOTTOM", 0, -7)
    end
    toast.elapsed = 0
    toast:SetAlpha(1)
    toast:SetScript("OnUpdate", toast.update)
    toast:Show()
end

-- Route notes show in the Guide Panel while it is up (its notice block),
-- else as the toast under the radar.
function addon.ShowVignetteRadarRouteNote(label, message, objective)
    local guidance = addon.VignetteRadarGuidance
    if guidance and guidance.Notice(label, message, objective) then return end
    routeMenu.Note(label, message, objective)
end

function routeMenu.CategoryButton(parent, kind, label, width)
    local button = addon.VignetteRadarControls.Button(parent, label, width, 42)
    addon.VignetteRadarStyle.SetFont(button.label, 9, "")
    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetSize(19, 19)
    button.icon:SetPoint("TOP", button, "TOP", 0, -5)
    if kind == "rare" then
        button.icon:SetTexture(SKULL_TEXTURE)
    elseif kind == "treasure" then
        button.icon:SetAtlas("VignetteLoot")
    elseif kind == "quest" then
        button.icon:SetTexture(addon.VignetteRadarQuestHollowTexture)
    elseif kind == "closest" then
        button.icon:SetTexture("Interface\\AddOns\\Magpie\\Media\\route-crystal-pointer.tga")
    else
        button.icon:SetTexture("Interface\\AddOns\\Magpie\\Media\\radar-corner-controls.tga")
    end
    addon.VignetteRadarControls.RoundedStatusSurface(button)
    button.face:Hide()
    button.edge:Hide()
    button.chosenPip = button:CreateTexture(nil, "OVERLAY")
    button.chosenPip:SetTexture(CIRCLE_TEXTURE)
    button.chosenPip:SetSize(6, 6)
    button.chosenPip:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -4)
    function button:RefreshRouteTile()
        local style = addon.VignetteRadarStyle
        local r, g, b = ACCENT[1], ACCENT[2], ACCENT[3]
        if style then r, g, b = style.Color((kind == "zygor" or kind == "closest")
            and "accent" or kind) end
        local selected, hovered = self._routeSelected == true, self._hovered == true
        local paused = self._routeState == "paused" or self._routeState == "waiting"
        self.label:ClearAllPoints()
        self.label:SetPoint("BOTTOM", self, "BOTTOM", 0, 5)
        self.label:SetTextColor(selected and (r + 1) / 2 or .77,
            selected and (g + 1) / 2 or .84, selected and (b + 1) / 2 or .85, 1)
        self.selection:Hide()
        for _, texture in ipairs(self.statusSurface.face) do
            texture:SetVertexColor(r, g, b, selected and (paused and .045 or .085)
                or hovered and .075 or .025)
        end
        for _, texture in ipairs(self.statusSurface.edge) do
            texture:SetVertexColor(r, g, b, selected and (paused and .65 or 1)
                or hovered and .38 or .08)
        end
        self.chosenPip:SetVertexColor(r, g, b, paused and .65 or 1)
        self.chosenPip:SetShown(selected)
        if kind == "zygor" then
            local state = (selected and 2 or 0) + (hovered and 1 or 0)
            self.icon:SetTexCoord((10 * 64 + 1) / 1024, (10 * 64 + 63) / 1024,
                (state * 64 + 1) / 256, (state * 64 + 63) / 256)
        end
        self.icon:SetVertexColor(r, g, b, selected and 1 or hovered and .9 or .72)
    end
    local baseRefresh = button.RefreshAppearance
    button.RefreshAppearance = function(self)
        baseRefresh(self)
        self:RefreshRouteTile()
    end
    for _, event in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnHide" }) do
        button:HookScript(event, function(self) self:RefreshRouteTile() end)
    end
    function button:SetRouteSelected(selected, state)
        self._routeSelected, self._routeState = selected == true, state
        if selected then self:LockHighlight() else self:UnlockHighlight() end
        self:RefreshRouteTile()
    end
    button:RefreshRouteTile()
    return button
end

routeMenu.Refresh = function()
    if not routeMenu.popup then return end
    local style, focus = addon.VignetteRadarStyle, addon.VignetteRadarWorldFocus
    local ar, ag, ab = ACCENT[1], ACCENT[2], ACCENT[3]
    if style then ar, ag, ab = style.Color("accent") end
    addon.VignetteRadarControls.RefreshPopupSurface(routeMenu.popup)
    routeMenu.popup.title:SetTextColor(ar, ag, ab, 1)
    routeMenu.popup.section:SetTextColor(ar, ag, ab, .88)
    routeMenu.popup.rule:SetColorTexture(ar, ag, ab, .2)
    if routeMenu.mode == "zygor" then
        if routeMenu.popup.zygor and routeMenu.popup.zygor.Refresh then
            routeMenu.popup.zygor.Refresh()
        end
        return
    end
    routeMenu.popup.rule2:SetColorTexture(ar, ag, ab, .16)
    local chosen, state
    if focus and focus.GetRouteChoice then chosen, state = focus.GetRouteChoice() end
    local bridge = addon.VignetteRadarZygor
    if bridge and bridge.IsFollowing and bridge.IsFollowing() then
        chosen, state = "zygor", "active"
    elseif not chosen and bridge and bridge.IsPaused and bridge.IsPaused() then
        chosen, state = "zygor", "paused"
    end
    routeMenu.popup.status:SetText(chosen == "zygor" and bridge and bridge.Status()
        or focus and focus.Status() or "Waypoint data unavailable")
    routeMenu.popup.status:SetTextColor(.7, .79, .8, 1)
    for _, kind in ipairs({ "closest", "rare", "treasure", "quest", "zygor" }) do
        routeMenu.popup.choices[kind]:SetRouteSelected(chosen == kind, state)
    end
    local routing = focus and focus.IsRouteActive()
    local questRoute = focus and focus.IsQuestRoute and focus.IsQuestRoute()
    routeMenu.popup.choices.previous:SetText(questRoute and "Previous Step" or "Previous Point")
    routeMenu.popup.choices.next:SetText(questRoute and "Next Step" or "Next Point")
    routeMenu.popup.pause:SetText(routing and "Pause Auto Route"
        or focus and focus.IsRoutePaused and focus.IsRoutePaused()
            and "Resume Auto Route" or "Start Auto Route")
    routeMenu.popup.skip:SetEnabled(routing == true)
    routeMenu.popup.skipQuest:SetEnabled(focus and focus.IsQuestRoute and focus.IsQuestRoute() or false)
    routeMenu.popup.clear:SetEnabled(focus and focus.HasFocus and focus.HasFocus() or false)
end

function routeMenu.Position(anchor)
    if not (routeMenu.popup and anchor) then return end
    routeMenu.popup:ClearAllPoints()
    local function Edge(region, method)
        if not (region and type(region[method]) == "function") then return nil end
        local ok, value = pcall(region[method], region)
        return ok and SafeNumber(value) or nil
    end
    local width, screenWidth = routeMenu.popup:GetWidth(), UIParent:GetWidth()
    local left, right, top = Edge(anchor, "GetLeft"), Edge(anchor, "GetRight"), Edge(anchor, "GetTop")
    local alignTop = top and top >= routeMenu.popup:GetHeight() + 8
    local from, to = alignTop and "TOPLEFT" or "BOTTOMLEFT",
        alignTop and "TOPRIGHT" or "BOTTOMRIGHT"
    if right and screenWidth - right >= width + 16 then
        routeMenu.popup:SetPoint(from, anchor, to, 8, 0)
    elseif left and left >= width + 16 then
        routeMenu.popup:SetPoint(alignTop and "TOPRIGHT" or "BOTTOMRIGHT", anchor,
            alignTop and "TOPLEFT" or "BOTTOMLEFT", -8, 0)
    else
        routeMenu.popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    end
end

function routeMenu.Ensure()
    if routeMenu.popup then return routeMenu.popup end
    routeMenu.popup = CreateFrame("Frame", "VignetteRadarRouteChooserPopup", UIParent, "BackdropTemplate")
    routeMenu.popup:SetSize(326, 263)
    routeMenu.popup:SetFrameStrata("DIALOG")
    routeMenu.popup:SetClampedToScreen(true)
    routeMenu.popup:EnableMouse(true)
    Surface(routeMenu.popup)
    addon.VignetteRadarControls.PopupSurface(routeMenu.popup)
    routeMenu.popup.title = Text(routeMenu.popup, 10, "ROUTE CHOOSER", true)
    routeMenu.popup.title:SetPoint("TOPLEFT", 13, -10)
    routeMenu.popup.close = addon.VignetteRadarIconButton.Create(routeMenu.popup, "close",
        { size = 20, label = "Close Route Chooser" })
    routeMenu.popup.close:SetPoint("TOPRIGHT", routeMenu.popup, "TOPRIGHT", -9, -5)
    routeMenu.popup.close:SetScript("OnClick", routeMenu.Hide)
    routeMenu.popup.rule = routeMenu.popup:CreateTexture(nil, "ARTWORK")
    routeMenu.popup.rule:SetPoint("TOPLEFT", 12, -29)
    routeMenu.popup.rule:SetPoint("TOPRIGHT", -12, -29)
    routeMenu.popup.rule:SetHeight(1)
    routeMenu.popup.status = Text(routeMenu.popup, 9, "")
    routeMenu.popup.status:SetPoint("TOPLEFT", 13, -39)
    routeMenu.popup.status:SetWidth(300)
    if routeMenu.popup.status.SetMaxLines then routeMenu.popup.status:SetMaxLines(1) end
    routeMenu.popup.section = Text(routeMenu.popup, 9, "CHOOSE A ROUTE", true)
    routeMenu.popup.section:SetPoint("TOPLEFT", 13, -61)
    routeMenu.popup.rule2 = routeMenu.popup:CreateTexture(nil, "ARTWORK")
    routeMenu.popup.rule2:SetPoint("TOPLEFT", 12, -128)
    routeMenu.popup.rule2:SetPoint("TOPRIGHT", -12, -128)
    routeMenu.popup.rule2:SetHeight(1)
    routeMenu.popup.choices = {}
    local function Choice(key, label, x, y, width, action, category)
        local button = category and routeMenu.CategoryButton(routeMenu.popup, key, label, width)
            or addon.VignetteRadarControls.Button(routeMenu.popup, label, width, 22)
        button:SetPoint("TOPLEFT", routeMenu.popup, "TOPLEFT", x, y)
        button:SetScript("OnClick", function()
            local ok, reason = action()
            if ok == "page" then
                return
            elseif ok then
                routeMenu.Hide()
            else
                reason = type(reason) == "string" and reason or "No waypoint could be set"
                routeMenu.popup.status:SetText(reason)
                routeMenu.popup.status:SetTextColor(1, .63, .38, 1)
                if UIErrorsFrame and UIErrorsFrame.AddMessage then
                    UIErrorsFrame:AddMessage(reason, 1, .65, .25)
                end
            end
            if RefreshRadar then RefreshRadar(false) end
        end)
        routeMenu.popup.choices[key] = button
        return button
    end
    for index, kind in ipairs({ "closest", "rare", "treasure", "quest" }) do
        Choice(kind, kind:sub(1, 1):upper() .. kind:sub(2), 12 + (index - 1) * 61,
            -77, 58, function()
                local focus = addon.VignetteRadarWorldFocus
                if focus then return focus.StartNearest(kind) end
                return false, "World Focus is unavailable"
            end, true)
    end
    Choice("zygor", "Zygor", 256, -77, 58, function()
        local ok, reason = addon.VignetteRadarAPI.StartZygorRoute()
        routeMenu.ShowZygorPage()
        if not ok then
            routeMenu.popup.zygor.status:SetText(reason or "No mapped Zygor objective yet")
            routeMenu.popup.zygor.status:SetTextColor(1, .63, .38, 1)
        end
        return "page"
    end, true)
    Choice("previous", "Previous Point", 13, -137, 146, function()
        local focus = addon.VignetteRadarWorldFocus
        if focus.IsQuestRoute() then return focus.PreviousQuestStep() end
        return focus.Cycle(-1)
    end)
    Choice("next", "Next Point", 167, -137, 146, function()
        local focus = addon.VignetteRadarWorldFocus
        if focus.IsQuestRoute() then return focus.NextQuestStep() end
        return focus.Cycle(1)
    end)
    routeMenu.popup.pause = Choice("pause", "Resume Auto Route", 13, -165, 146, function()
        local focus = addon.VignetteRadarWorldFocus
        local wasRouting = focus.IsRouteActive()
        local ok, reason = focus.ToggleRoute()
        return wasRouting or ok, wasRouting and nil or reason
    end)
    routeMenu.popup.skip = Choice("skip", "Skip Stop", 167, -165, 146, function()
        return addon.VignetteRadarWorldFocus.SkipRouteStop()
    end)
    routeMenu.popup.skipQuest = Choice("skipQuest", "Skip Quest", 13, -193, 146, function()
        return addon.VignetteRadarWorldFocus.SkipQuest()
    end)
    routeMenu.popup.clear = Choice("clear", "Clear Focus", 167, -193, 146, function()
        addon.VignetteRadarFocus.Clear({ project = false, source = "route" })
        return addon.VignetteRadarWorldFocus.Clear()
    end)
    Choice("settings", "Route Settings", 13, -221, 300, function()
        local quick = addon.VignetteRadarQuickConfig
        if quick and quick.OpenPage then quick.OpenPage("Auto Route", CircleOnly() and panel.field or panel) end
        return true
    end)
    routeMenu.popup.mainControls = { routeMenu.popup.status, routeMenu.popup.section,
        routeMenu.popup.rule2 }
    for _, button in pairs(routeMenu.popup.choices) do
        routeMenu.popup.mainControls[#routeMenu.popup.mainControls + 1] = button
    end
    local zygor = CreateFrame("Frame", nil, routeMenu.popup)
    zygor:SetPoint("TOPLEFT", routeMenu.popup, "TOPLEFT", 0, -32)
    zygor:SetSize(326, 258)
    zygor:EnableMouseWheel(true)
    routeMenu.popup.zygor = zygor
    zygor.status = Text(zygor, 9, "")
    zygor.status:SetPoint("TOPLEFT", 13, -4)
    zygor.status:SetWidth(300)
    if zygor.status.SetMaxLines then zygor.status:SetMaxLines(1) end
    zygor.section = Text(zygor, 9, "PIN A LOCATION", true)
    zygor.section:SetPoint("TOPLEFT", 13, -27)
    local function ZygorButton(label, x, y, width, action)
        local button = addon.VignetteRadarControls.Button(zygor, label, width, 22)
        button:SetPoint("TOPLEFT", zygor, "TOPLEFT", x, y)
        button:SetScript("OnClick", function()
            local ok, reason = action(button)
            if ok == "page" then
                return
            elseif ok then
                routeMenu.Hide()
                if RefreshRadar then RefreshRadar(false) end
            else
                routeMenu.popup.zygor.status:SetText(reason or "No mapped point for this step")
                routeMenu.popup.zygor.status:SetTextColor(1, .63, .38, 1)
            end
        end)
        return button
    end
    zygor.objective = ZygorButton("Selected Objective", 13, -45, 146, function()
        local ready, reason = addon.VignetteRadarAPI.BindZygorGuide()
        if not ready then return false, reason end
        local bridge = addon.VignetteRadarZygor
        if bridge.IsFollowing() then return bridge.SetMode("objective") end
        bridge.SetMode("objective")
        return bridge.Pin("objective")
    end)
    zygor.travel = ZygorButton("Next Travel Stop", 167, -45, 146, function()
        local ready, reason = addon.VignetteRadarAPI.BindZygorGuide()
        if not ready then return false, reason end
        local bridge = addon.VignetteRadarZygor
        if bridge.IsFollowing() then return bridge.SetMode("travel") end
        bridge.SetMode("travel")
        return bridge.Pin("travel")
    end)
    zygor.follow = ZygorButton("Follow Guide", 13, -73, 300, function()
        local ready, reason = addon.VignetteRadarAPI.BindZygorGuide()
        if not ready then return false, reason end
        local ok, reason = addon.VignetteRadarZygor.ToggleFollow()
        return ok, reason
    end)
    zygor.goalTitle = Text(zygor, 9, "OBJECTIVES · SCROLL FOR MORE", true)
    zygor.goalTitle:SetPoint("TOPLEFT", 13, -106)
    zygor.rows = {}
    for index = 1, 4 do
        local row = ZygorButton("", 13, -124 - (index - 1) * 24, 288, function(self)
            local ready, reason = addon.VignetteRadarAPI.BindZygorGuide()
            if not ready then return false, reason end
            return addon.VignetteRadarZygor.Pin("objective", self.goalIndex)
        end)
        row:HookScript("OnEnter", function(self)
            if not (self.goalReason and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.goalReason, 1, .75, .52, true)
            GameTooltip:Show()
        end)
        row:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        zygor.rows[index] = row
    end
    zygor.scrollTrack = zygor:CreateTexture(nil, "ARTWORK")
    zygor.scrollTrack:SetColorTexture(.45, .55, .57, .28)
    zygor.scrollTrack:SetPoint("TOPLEFT", zygor, "TOPLEFT", 308, -124)
    zygor.scrollTrack:SetSize(3, 94)
    zygor.scrollThumb = zygor:CreateTexture(nil, "OVERLAY")
    zygor.scrollThumb:SetColorTexture(.65, .8, .82, .85)
    zygor.scrollThumb:SetSize(3, 28)
    zygor.back = ZygorButton("Back to Routes", 13, -228, 222, function()
        routeMenu.ShowMainPage()
        return "page"
    end)
    zygor.offset = 0
    zygor.Refresh = function()
        local bridge = addon.VignetteRadarZygor
        local rows, reason
        if bridge then rows, reason = bridge.Goals()
        else rows, reason = {}, "Zygor integration unavailable" end
        zygor.status:SetText(bridge and bridge.GuideLabel() or reason)
        zygor.status:SetTextColor(.7, .79, .8, 1)
        zygor.follow:SetText(bridge and bridge.IsPaused() and "Resume Guide Follow"
            or bridge and bridge.IsFollowing() and "Pause Guide Follow" or "Follow Guide")
        zygor.objective:SetEnabled(bridge ~= nil)
        zygor.travel:SetEnabled(bridge ~= nil)
        local maxOffset = math.max(0, #rows - #zygor.rows)
        zygor.offset = math.min(zygor.offset, maxOffset)
        for index, row in ipairs(zygor.rows) do
            local goal = rows[index + zygor.offset]
            row.goalIndex = goal and goal.index
            row.goalReason = goal and (not goal.mapped and goal.reason or nil)
            row:SetShown(goal ~= nil)
            if goal then
                local name = goal.name
                if #name > 26 then name = name:sub(1, 25) .. "…" end
                row:SetText(goal.index .. ". " .. name .. (goal.complete and " · Done" or ""))
                row:SetEnabled(goal.mapped)
                row:SetAlpha(goal.complete and .62 or 1)
            end
        end
        zygor.goalTitle:SetText(#rows > 0 and (maxOffset > 0
            and "OBJECTIVES · SCROLL FOR MORE" or "OBJECTIVES")
            or reason or "NO VISIBLE OBJECTIVES IN THIS STEP")
        if #rows == 0 and reason then zygor.status:SetText(reason) end
        zygor.scrollTrack:SetShown(maxOffset > 0)
        zygor.scrollThumb:SetShown(maxOffset > 0)
        if maxOffset > 0 then
            zygor.scrollThumb:SetHeight(math.max(18, 94 * #zygor.rows / #rows))
            zygor.scrollThumb:ClearAllPoints()
            zygor.scrollThumb:SetPoint("TOP", zygor.scrollTrack, "TOP", 0,
                -(94 - zygor.scrollThumb:GetHeight()) * zygor.offset / maxOffset)
        end
    end
    zygor:SetScript("OnMouseWheel", function(_, delta)
        zygor.offset = math.max(0, zygor.offset - delta)
        zygor.Refresh()
    end)
    for _, row in ipairs(zygor.rows) do
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            zygor.offset = math.max(0, zygor.offset - delta)
            zygor.Refresh()
        end)
    end
    zygor:Hide()
    routeMenu.popup:SetScript("OnHide", function()
        if panel and panel.routeToggle then
            panel.routeToggle._popupOpen = false
            panel.routeToggle:RefreshAppearance()
        end
    end)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarRouteChooserPopup"
    end
    routeMenu.popup:Hide()
    return routeMenu.popup
end

function routeMenu.ShowZygorPage()
    local popup = routeMenu.Ensure()
    routeMenu.mode = "zygor"
    popup:SetHeight(300)
    popup.title:SetText("ZYGOR STEP PICKER")
    for _, control in ipairs(popup.mainControls) do control:Hide() end
    popup.zygor:Show()
    routeMenu.Refresh()
    if routeMenu.anchor then routeMenu.Position(routeMenu.anchor) end
end

function routeMenu.ShowMainPage()
    local popup = routeMenu.Ensure()
    routeMenu.mode = nil
    popup:SetHeight(263)
    popup.title:SetText("ROUTE CHOOSER")
    popup.zygor:Hide()
    for _, control in ipairs(popup.mainControls) do control:Show() end
    routeMenu.Refresh()
    if routeMenu.anchor then routeMenu.Position(routeMenu.anchor) end
end

function routeMenu.HideGuideStrip()
    if routeMenu.guideStrip then routeMenu.guideStrip:Hide() end
end

function routeMenu.ShowGuideStrip(anchor)
    local bridge = addon.VignetteRadarZygor
    if not (CircleOnly() and anchor and _G.ZygorGuidesViewer and bridge) then return end
    if not routeMenu.guideStrip then
        local strip = CreateFrame("Frame", nil, UIParent)
        strip:SetSize(280, 62)
        strip:SetFrameStrata("DIALOG")
        strip:SetClampedToScreen(true)
        strip:EnableMouse(true)
        addon.VignetteRadarControls.RoundedStatusSurface(strip)
        strip.title = Text(strip, 9, "ZYGOR GUIDE", true)
        strip.title:SetPoint("TOPLEFT", 12, -9)
        strip.title:SetWidth(198)
        if strip.title.SetMaxLines then strip.title:SetMaxLines(1) end
        strip.detail = Text(strip, 10, "")
        strip.detail:SetPoint("TOPLEFT", 12, -28)
        strip.detail:SetWidth(254)
        strip.detail:SetHeight(27)
        strip.detail:SetWordWrap(true)
        if strip.detail.SetMaxLines then strip.detail:SetMaxLines(2) end
        strip.action = addon.VignetteRadarIconButton.Create(strip, "follow",
            { size = 20, label = "Follow Guide" })
        strip.action:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -9, -7)
        strip.action:SetScript("OnClick", function()
            bridge.ToggleFollow()
            routeMenu.ShowGuideStrip(routeMenu.guideAnchor)
            if RefreshRadar then RefreshRadar(false) end
        end)
        strip:SetScript("OnLeave", function()
            if C_Timer and C_Timer.After then C_Timer.After(.4, function()
                if strip:IsShown() and not strip:IsMouseOver()
                    and not (routeMenu.guideAnchor and routeMenu.guideAnchor:IsMouseOver()) then
                    strip:Hide()
                end
            end) end
        end)
        strip:Hide()
        routeMenu.guideStrip = strip
    end
    local strip = routeMenu.guideStrip
    routeMenu.guideAnchor = anchor
    addon.VignetteRadarControls.RefreshRoundedStatusSurface(strip)
    strip.title:SetText(bridge.GuideLabel())
    strip.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    local focus = addon.VignetteRadarWorldFocus
    strip.detail:SetText(focus and focus.OwnsGuideWaypoint()
        and focus.Status() or bridge.Status())
    -- Pause while following; Follow (or Resume when paused) otherwise.
    strip.action:SetIcon(bridge.IsFollowing() and not bridge.IsPaused() and "pause" or "follow")
    strip.action:SetLabel(bridge.IsPaused() and "Resume Guide"
        or bridge.IsFollowing() and "Pause Guide" or "Follow Guide")
    strip:ClearAllPoints()
    local top = anchor.GetTop and anchor:GetTop()
    if top and top < strip:GetHeight() + 12 then
        strip:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -8)
    else
        strip:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
    end
    strip:Show()
end

routeMenu.Toggle = function(anchor)
    local popup = routeMenu.Ensure()
    if popup:IsShown() then routeMenu.Hide(); return false end
    HideTrailPopup()
    local legend, picker = LegendAPI(), TargetPickerAPI()
    if legend and legend.Hide then legend.Hide() end
    if picker and picker.Hide then picker.Hide() end
    if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Hide() end
    routeMenu.HideGuideStrip()
    routeMenu.anchor = anchor
    routeMenu.ShowMainPage()
    routeMenu.Position(anchor)
    routeMenu.Refresh()
    popup:Show()
    if panel and panel.routeToggle then
        panel.routeToggle._popupOpen = true
        panel.routeToggle:RefreshAppearance()
    end
    return true
end

function routeMenu.SetupButtons(panel, ToolbarIcon)
    panel.trailToggle = ToolbarIcon("trail", 22)
    panel.trailToggle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.trailToggle:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if GameTooltip then GameTooltip:Hide() end
            ToggleTrailPopup(panel._trailPopupAnchor or panel.trailToggle)
        else
            HideTrailPopup()
            routeMenu.Hide()
            addon.SetVignetteRadarTrailEnabled(Settings().vignetteRadarBreadcrumbs ~= true)
        end
    end)
    panel.trailToggle:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        local style = Settings().vignetteRadarTrailStyle or "dashes"
        local name = (TRAIL_STYLE_BY_ID[style] or TRAIL_STYLES[1]).label
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Travel trail: " .. (Settings().vignetteRadarBreadcrumbs and "ON" or "OFF"), 1, 1, 1)
        GameTooltip:AddLine("Style: " .. name .. ". Left-click to toggle; right-click to choose from moving previews.",
            .7, .8, .8, true)
        GameTooltip:Show()
    end)
    panel.trailToggle:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    UpdateTrailToggle()

    panel.routeToggle = ToolbarIcon("route", 22)
    panel.routeToggle.trackingIcon = panel.routeToggle:CreateTexture(nil, "OVERLAY")
    panel.routeToggle.trackingIcon:SetSize(16, 16)
    panel.routeToggle.trackingIcon:SetPoint("CENTER")
    panel.routeToggle.trackingIcon:Hide()
    local routeBaseRefresh = panel.routeToggle.RefreshAppearance
    function panel.routeToggle:RefreshAppearance()
        routeBaseRefresh(self)
        local kind = self._trackingKind
        self.art:SetShown(kind == nil)
        if not kind then self.trackingIcon:Hide(); return end
        local r, g, b = routeMenu.TrackedRouteColor(kind)
        self.trackingIcon:SetVertexColor(r, g, b,
            self._enabled and (self._selected and 1 or .75) or .38)
        self.trackingIcon:Show()
    end
    function panel.routeToggle:SetTrackingKind(kind)
        if self._trackingKind == kind then return end
        self._trackingKind = kind
        if kind == "rare" or kind == "treasure" or kind == "quest" or kind == "zygor" then
            routeMenu.SetTrackedRouteTexture(self.trackingIcon, kind)
        else
            self._trackingKind = nil
        end
        self:RefreshAppearance()
    end
    panel.routeToggle:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    panel.routeToggle:SetScript("OnClick", function(self, button)
        if button == "MiddleButton" then
            local bridge = addon.VignetteRadarZygor
            if bridge and bridge.IsPaused and bridge.IsPaused() then
                bridge.ToggleFollow()
                routeMenu.ShowGuideStrip(panel._routePopupAnchor or self)
                if RefreshRadar then RefreshRadar(false) end
            end
            return
        end
        if button == "RightButton" then
            if GameTooltip then GameTooltip:Hide() end
            routeMenu.Toggle(panel._routePopupAnchor or self)
            return
        end
        routeMenu.Hide()
        local focus = addon.VignetteRadarWorldFocus
        if not focus then return end
        local wasRouting = focus.IsRouteActive()
        local ok, reason = focus.ToggleRoute()
        self._selected = focus.IsRouteActive()
        self:RefreshAppearance()
        if panel.RefreshCornerTools then panel.RefreshCornerTools() end
        if reason and not ok and not wasRouting and UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(reason, 1, .65, .25)
        end
    end)
    panel.routeToggle:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        local focus = addon.VignetteRadarWorldFocus
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(focus and focus.IsRouteActive() and "Pause Auto Route"
            or focus and focus.IsRoutePaused and focus.IsRoutePaused()
                and "Resume Auto Route" or "Start Auto Route", 1, 1, 1)
        GameTooltip:AddLine("Click a rare, treasure, or quest first. The route chooses the next stop as you arrive.", .7, .8, .8, true)
        GameTooltip:AddLine("Right-click to choose a route, pin Zygor, or manage stops.", .55, .86, .76, true)
        local bridge = addon.VignetteRadarZygor
        if bridge and bridge.IsPaused and bridge.IsPaused() then
            GameTooltip:AddLine("Middle-click to resume Zygor Follow.", .55, .86, .76, true)
        end
        GameTooltip:Show()
    end)
    panel.routeToggle:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function EmptyExplanation(player, shown, quests, notes, areas, starts)
    if not Settings().vignetteRadarEmptyHelp or shown > 0 or quests > 0 or notes > 0
        or areas or (starts or 0) > 0 then return nil end
    if not player then return "Your position is not available from the current map yet." end
    if #activeTargets > 0 then
        local visible = 0
        for _, target in ipairs(activeTargets) do if TargetVisible(target) then visible = visible + 1 end end
        if visible == 0 then return "Current detections are hidden by your category, focus, or ignore settings." end
        return "Known detections are beyond this range. Zoom out or check the edge cues."
    end
    if #activeQuests > 0 and not Settings().vignetteRadarQuestDots
        and not Settings().vignetteRadarQuestAreas then
        return "Quest locations are available, but quest dots and areas are turned off."
    end
    if #activeMapNotes > 0 then return "This map pack has locations, but none are inside this range." end
    if Settings().vignetteRadarMapNotesVisible ~= true
        or Settings().vignetteRadarPOISource == "none" then
        return "No live detections here. Map-data packs are turned off."
    end
    return "No live detections or quest locations are available for this spot."
end

function addon.GetVignetteRadarStatusLines()
    local settings = Settings()
    local lines = {}
    if not activeMapID then
        lines[#lines + 1] = "Current map unavailable; radar positions cannot be projected yet."
    end
    if not PlayerSnapshot(activeMapID) then
        lines[#lines + 1] = "Player map position unavailable here; waiting for Blizzard's map data."
    end
    if not settings.vignetteRadarQuestDots then
        lines[#lines + 1] = "Quest diamonds are off in Quests settings."
    elseif #activeQuests == 0 then
        lines[#lines + 1] = "Blizzard supplied no positioned tracked quests on this map."
    end
    if not settings.vignetteRadarQuestAreas then
        lines[#lines + 1] = "Exact quest areas are off in Quests settings."
    elseif not settings.vignetteRadarNorthUp then
        lines[#lines + 1] = "Exact quest areas need north-up orientation."
    elseif panel and panel.questClip and not panel.questClip.canClip then
        lines[#lines + 1] = "This client cannot clip the native quest-area layer."
    elseif questMapBasis and not questMapBasis.horizontal then
        lines[#lines + 1] = "This map's axes cannot align with Blizzard's quest-area layer yet."
    elseif #activeQuests > 0 then
        lines[#lines + 1] = "Quest areas render only where Blizzard supplies shape data."
    end
    if settings.vignetteRadarMapNotesVisible ~= true
        or settings.vignetteRadarPOISource == "none" then
        lines[#lines + 1] = "Map notes are off; turn them on in the Radar Legend."
    elseif #activeMapNotes == 0 then
        lines[#lines + 1] = "Selected map-data pack has no usable notes for this map."
    end
    if #activeTargets == 0 then
        lines[#lines + 1] = "No live vignette detections were supplied for this map."
    end
    if #lines == 0 then lines[1] = "Map, quest, pack, and live detection data are available." end
    return lines
end

function addon.GetVignetteRadarDiagnostics()
    local settings = Settings()
    local source = settings.vignetteRadarMapNotesVisible == true
        and addon.VignetteRadarPOIs and activeMapID
        and addon.VignetteRadarPOIs.ResolveSource(activeMapID, settings.vignetteRadarPOISource)
    local paused = addon.VignetteRadarBudget.paused
    local pausedNames = {}
    for _, name in ipairs({ "radar", "launcher", "background" }) do
        if paused[name] then pausedNames[#pausedNames + 1] = name end
    end
    local lines = {
        "Map: " .. tostring(activeMapID or "unavailable"),
        "Map pack: " .. tostring(source or (settings.vignetteRadarMapNotesVisible ~= true
            or settings.vignetteRadarPOISource == "none") and "off" or "none here"),
        "Live detections: " .. #activeTargets .. "  ·  quest points: " .. #activeQuests,
        "Map notes: " .. #activeMapNotes,
        "Treasure loot observations: " .. (addon.VignetteRadarTreasureLearning
            and addon.VignetteRadarTreasureLearning.Count() or 0),
        "Rare and quest observations: " .. (function()
            local learning = addon.VignetteRadarOutcomeLearning
            if not learning then return "0 / 0" end
            local counts = learning.Count()
            return counts.rare .. " / " .. counts.quest
        end)(),
        "CPU guard: " .. (#pausedNames > 0 and ("paused " .. table.concat(pausedNames, ", ")
            .. " (auto-retrying)") or "running"),
        "Update rate: " .. (settings.vignetteRadarPerformance or "standard"),
    }
    for _, line in ipairs(addon.GetVignetteRadarStatusLines()) do
        lines[#lines + 1] = line
        if #lines >= 10 then break end
    end
    return lines
end

function addon.ToggleVignetteRadarStatus(anchor)
    if not (GameTooltip and anchor) then return end
    if GameTooltip.IsShown and GameTooltip:GetOwner() == anchor and GameTooltip:IsShown() then
        GameTooltip:Hide()
        return
    end
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:SetText("Radar data status", 1, 1, 1)
    for _, line in ipairs(addon.GetVignetteRadarStatusLines()) do
        GameTooltip:AddLine(line, .7, .83, .79, true)
    end
    GameTooltip:Show()
end

local function HideEdgeCues()
    if not panel or not panel.edgeCues then return end
    for _, cue in ipairs(panel.edgeCues) do cue:Hide() end
end

local function RenderEdgeCues(player, range, targets)
    if not (Settings().vignetteRadarEdgeCues and player) then HideEdgeCues(); return 0 end
    local nearest = {}
    local reach = math.max(300, range * 2)
    local function Consider(item, kind, worldX, worldY, name, stale)
        if not (SafeNumber(worldX) and SafeNumber(worldY)) then return end
        local dx, dy = worldX - player.worldX, worldY - player.worldY
        local distance = math.sqrt(dx * dx + dy * dy)
        if not addon.KeepCenterMarker(kind == "vignette" and "target" or "quest",
            kind == "vignette" and item.key or item.questID, distance, range) then return end
        if distance <= range or distance > reach then return end
        local candidate = { item=item, kind=kind, dx=dx, dy=dy, distance=distance,
            name=name, stale=stale }
        local slot = #nearest + 1
        for index, entry in ipairs(nearest) do
            if distance < entry.distance then slot = index; break end
        end
        table.insert(nearest, slot, candidate)
        if #nearest > 6 then table.remove(nearest) end
    end
    for _, target in ipairs(targets) do
        if TargetVisible(target) and (Settings().vignetteRadarKeepCenterClear
            or target.key ~= FocusedTargetKey())
            and not (player.instanceID and target.instanceID and player.instanceID ~= target.instanceID) then
            Consider(target, "vignette", target.worldX, target.worldY, target.name, target.stale)
        end
    end
    if (Settings().vignetteRadarQuestDots or Settings().vignetteRadarQuestAreas)
        and (not addon.VignetteRadarLensActive or addon.VignetteRadarLensActive == "quest") then
        for _, quest in ipairs(activeQuests) do
            if not (player.instanceID and quest.instanceID and player.instanceID ~= quest.instanceID) then
                Consider(quest, "quest", quest.worldX, quest.worldY, quest.name, false)
            end
        end
    end
    panel.edgeCues = panel.edgeCues or {}
    for index, entry in ipairs(nearest) do
        local cue = panel.edgeCues[index]
        if not cue then
            cue = CreateFrame("Button", nil, panel.field)
            cue:SetSize(13, 13)
            cue:SetFrameLevel(panel.field:GetFrameLevel() + 5)
            cue.rim = cue:CreateTexture(nil, "ARTWORK")
            cue.rim:SetTexture(CIRCLE_TEXTURE)
            cue.rim:SetSize(10, 10)
            cue.rim:SetPoint("CENTER")
            cue.core = cue:CreateTexture(nil, "OVERLAY")
            cue.core:SetTexture(CIRCLE_TEXTURE)
            cue.core:SetSize(5, 5)
            cue.core:SetPoint("CENTER")
            cue.core:SetVertexColor(.02, .02, .02, 1)
            cue:SetScript("OnEnter", function(self)
                if not (GameTooltip and self.entry) then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.entry.name or "Nearby location", 1, 1, 1)
                GameTooltip:AddLine(math.floor(self.entry.distance + .5) .. " yd away; outside radar range.", .7, .8, .78)
                if self.entry.kind == "quest" then
                    AddQuestTooltipObjective(self.entry.item.questID,
                        self.entry.item.objectiveText)
                else
                    GameTooltip:AddLine(self.entry.stale and "Last seen; not a live detection."
                        or "Known vignette from Blizzard's map data.", .65, .75, .75)
                end
                GameTooltip:Show()
            end)
            cue:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            cue:SetScript("OnClick", function(self)
                if not self.entry then return end
                if self.entry.kind == "quest" then
                    local exploration = addon.VignetteRadarExploration
                    if exploration then exploration.FocusQuest(self.entry.item.questID) end
                else addon.HandleVignetteClick(self.entry.item, "LeftButton") end
            end)
            panel.edgeCues[index] = cue
        end
        local x, y = Project(entry.dx, entry.dy, entry.distance,
            ViewFacing(player.facing), panel.plotRadius - 3, entry.distance)
        local r, g, b
        if entry.kind == "quest" then
            if addon.VignetteRadarStyle then r, g, b = addon.VignetteRadarStyle.Color("quest")
            else r, g, b = 1, .75, .3 end
        else r, g, b = TargetColor(entry.item) end
        cue.rim:SetVertexColor(r, g, b, .9)
        cue.entry = entry
        cue:SetAlpha((entry.stale and .5 or .84) *
            (entry.kind == "vignette" and CategoryOpacity(entry.item.category) or 1))
        if x and y then
            cue:ClearAllPoints()
            cue:SetPoint("CENTER", panel.field, "CENTER", x, y)
            addon.VignetteRadarTurn.TrackPoint(cue, x, y, ViewFacing(player.facing))
            cue:Show()
        else cue:Hide() end
    end
    for index = #nearest + 1, #panel.edgeCues do panel.edgeCues[index]:Hide() end
    return #nearest
end

Render = function()
    if not panel or not panel:IsShown() then return end
    ApplyAppearance()
    UpdateCombatToggle()
    UpdateTrailToggle()
    local routing = addon.VignetteRadarWorldFocus
        and addon.VignetteRadarWorldFocus.IsRouteActive() or false
    if panel.routeToggle and panel.routeToggle._selected ~= routing then
        panel.routeToggle._selected = routing
        panel.routeToggle:RefreshAppearance()
    end
    if panel.routeToggle then
        local focus = addon.VignetteRadarWorldFocus
        local previousKind = panel.routeToggle._trackingKind
        panel.routeToggle:SetTrackingKind(focus and focus.GetTrackedRouteKind
            and focus.GetTrackedRouteKind() or nil)
        if previousKind ~= panel.routeToggle._trackingKind and panel.RefreshCornerTools then
            panel.RefreshCornerTools()
        end
    end
    if panel.arrowToggle and panel.arrowToggle._selected ~= Settings().vignetteRadarGuidePanel then
        panel.arrowToggle._selected = Settings().vignetteRadarGuidePanel == true
        panel.arrowToggle:RefreshAppearance()
    end
    UpdateFullSweep(0)
    BeginBlips()
    local mapID = CurrentMapID()
    if not preview and mapID ~= activeMapID then ScanVignettes(mapID) end
    local targets = SelectableTargets()
    local focusedTarget
    for _, target in ipairs(targets) do
        if target.key == FocusedTargetKey() then focusedTarget = target; break end
    end
    local player = not preview and PlayerSnapshot(mapID) or nil
    local exploration = addon.VignetteRadarExploration
    local range = exploration and exploration.Range(player, focusedTarget)
        or tonumber(Settings().vignetteRadarRange) or 450
    local contextOverlay = addon.VignetteRadarContextOverlay
    if contextOverlay and type(contextOverlay.range) == "number"
        and not preview and not focusedTarget then
        range = contextOverlay.range
    end
    -- Minimap Underlay: zooms and sizes the borrowed Minimap to this range.
    if addon.VignetteRadarMinimapUnderlay and not preview then
        range = addon.VignetteRadarMinimapUnderlay.Sync(range, panel) or range
    end
    -- While the minimap terrain fills the face, the range rings and their
    -- yard labels step aside; the face outline stays.
    local terrain = not preview and addon.VignetteRadarMinimapUnderlay ~= nil
        and addon.VignetteRadarMinimapUnderlay.ShowsTerrain() or false
    if panel._ringsHidden ~= terrain then
        panel._ringsHidden = terrain
        for _, ring in ipairs({ panel.rangeRing, panel.middleRing, panel.innerRing }) do
            for _, line in ipairs(ring) do line:SetShown(not terrain) end
        end
        panel.innerLabel:SetShown(not terrain)
        panel.outerLabel:SetShown(not terrain)
        if addon.Trace then addon.Trace.Log("minimap", "range rings %s", terrain and "hidden" or "shown") end
    end
    -- Duplicate Icons: the marker kinds the radar leaves to the minimap this
    -- render (UI/MinimapUnderlay.lua RadarHides), one cached table or nil.
    panel._underlayHide = terrain and addon.VignetteRadarMinimapUnderlay.RadarHides() or nil
    if panel._underlayHideTraced ~= panel._underlayHide then
        panel._underlayHideTraced = panel._underlayHide
        if addon.Trace then
            addon.Trace.Log("minimap", "radar markers: %s",
                panel._underlayHide and panel._underlayHide.label or "all shown")
        end
    end
    displayedRange = range
    UpdateRingLabels(range)
    panel.zoomLabel:SetText(range .. " yd")
    local ranges = Ranges()
    panel.zoomIn:SetEnabled(range ~= ranges[1])
    panel.zoomOut:SetEnabled(range ~= ranges[#ranges])
    local northUp = Settings().vignetteRadarNorthUp == true
    if panel.compass._northUp ~= northUp then
        panel.compass._northUp, panel.compass._selected = northUp, northUp
        panel.compass:RefreshAppearance()
    end
    panel:SetAlpha((VisuallyQuiet() and 0.35 or 1) * (panel._morphAlpha or 1))
    local sidebarTarget = focusedTarget
    if not sidebarTarget and Settings().vignetteRadarLayout == "squat" then
        if preview then
            for _, candidate in ipairs(PREVIEW_TARGETS) do
                if TargetVisible(candidate) then sidebarTarget = candidate; break end
            end
            if sidebarTarget then sidebarTarget.distance = range * sidebarTarget.distanceFactor end
        elseif player then
            local fallback
            for _, candidate in ipairs(targets) do
                if TargetVisible(candidate)
                    and not (player.instanceID and candidate.instanceID and player.instanceID ~= candidate.instanceID) then
                    if candidate.distance and candidate.distance <= range then sidebarTarget = candidate; break end
                    if not fallback then fallback = candidate end
                end
            end
            sidebarTarget = sidebarTarget or fallback
        end
    end
    UpdateFocusReadout(sidebarTarget, player, focusedTarget ~= nil)
    UpdatePanelChrome()

    if preview then
        if panel.activeCue then panel.activeCue:Hide(); panel.activeCueHit:Hide() end
        HideEdgeCues()
        panel.emptyReason = nil
        if panel.emptyHelp then panel.emptyHelp:Hide() end
        RenderExploration(nil, range)
        HideQuestDots()
        addon.RenderVignetteRadarQuestStarts(nil)
        panel._questKeyNextAt = nil
        addon.UpdateVignetteRadarQuestKey()
        HideMapNotes()
        HideQuestAreas()
        panel.summary:SetText(FocusedTargetKey() and "PREVIEW FOCUS" or "PREVIEW")
        RenderCardinals(ViewFacing(0.65))
        local tip, outer = HeadingGeometry(panel.plotRadius)
        DrawPlayerHeading(panel.direction, panel.field, 0.65, tip, outer)
        DrawPlayerChevron(panel.headingChevron, panel.field, 0.65)
        panel.direction:Show()
        for _, line in ipairs(panel.headingChevron) do line:Show() end
        for _, target in ipairs(PREVIEW_TARGETS) do
            target.distance = range * target.distanceFactor
            local scale = panel.plotRadius / PLOT_RADIUS
            local x, y = PreviewPosition(target.x, target.y)
            if TargetVisible(target) and addon.KeepCenterMarker("target", target.key,
                target.distance, range) then
                PlaceBlip(target.key, x * scale, y * scale, target)
            end
        end
        if addon.VignetteRadarPlayerTracker then addon.VignetteRadarPlayerTracker.HideRadar() end
        EndBlips()
        return
    end

    if not player then
        if panel.activeCue then panel.activeCue:Hide(); panel.activeCueHit:Hide() end
        HideEdgeCues()
        panel.emptyReason = EmptyExplanation(nil, 0, 0, 0, false)
        if panel.emptyHelp then panel.emptyHelp:SetShown(not CircleOnly() and panel.emptyReason ~= nil) end
        RenderExploration(nil, range)
        HideQuestDots()
        addon.RenderVignetteRadarQuestStarts(nil)
        panel._questKeyNextAt = nil
        addon.UpdateVignetteRadarQuestKey()
        HideMapNotes()
        HideQuestAreas()
        panel.summary:SetText("POSITION UNAVAILABLE")
        if panel.layout == "squat" then
            panel.sideCaption:SetText("POSITION UNAVAILABLE")
            panel.layoutHint:SetText("Waiting for your map position.")
            panel.sideGuide:SetText("CHECK YOUR CURRENT MAP")
        end
        RenderCardinals(0)
        panel.direction:Hide()
        for _, line in ipairs(panel.headingChevron) do line:Hide() end
        if addon.VignetteRadarPlayerTracker then addon.VignetteRadarPlayerTracker.HideRadar() end
        EndBlips()
        return
    end
    RenderCardinals(ViewFacing(player.facing))
    local tip, outer = HeadingGeometry(panel.plotRadius)
    DrawPlayerHeading(panel.direction, panel.field, player.facing, tip, outer)
    DrawPlayerChevron(panel.headingChevron, panel.field, player.facing)
    panel.direction:SetShown(player.headingAvailable)
    for _, line in ipairs(panel.headingChevron) do line:SetShown(player.headingAvailable) end
    local layerBudget = addon.VignetteRadarLayerBudget
    local blobToken = layerBudget and layerBudget.Begin("questBlobs",
        panel._layerMapID ~= mapID or panel._layerRange ~= range)
    local questAreasShown = panel._questAreasShown or 0
    if not layerBudget or blobToken then
        questAreasShown = RenderQuestAreas(player, mapID, range)
        panel._questAreasShown = questAreasShown
        if blobToken then layerBudget.Finish(blobToken) end
    end
    local focusAPI = addon.VignetteRadarWorldFocus
    local activeStep, activeKind, activeRouteName, activeIndex, activeCount
    if focusAPI and focusAPI.GetRoutePoint then
        activeStep, activeKind, activeRouteName, activeIndex, activeCount = focusAPI.GetRoutePoint()
    end
    if not activeStep and focusAPI and focusAPI.GetFocusedStep then
        activeStep = focusAPI.GetFocusedStep()
        activeKind = activeStep and activeStep.kind
    end
    local cueX, cueY, cueDistance
    if Settings().vignetteRadarActiveCue ~= false and activeStep
        and activeKind ~= "quest" and not activeStep.questID
        and SafeNumber(activeStep.worldX) and SafeNumber(activeStep.worldY)
        and activeStep.mapID == mapID then
        local dx, dy = activeStep.worldX - player.worldX, activeStep.worldY - player.worldY
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance <= range then
            cueX, cueY = Project(dx, dy, distance, ViewFacing(player.facing), panel.plotRadius, range)
            cueDistance = distance
        end
    end
    if Settings().vignetteRadarKeepCenterClear and (addon.FocusedQuestID() or FocusedTargetKey()) then
        cueX, cueY = nil, nil
    end
    if cueX and cueY then
        local r, g, b = addon.VignetteRadarStyle.Color(activeKind or "quest")
        panel.activeCue:ClearAllPoints()
        panel.activeCue:SetPoint("CENTER", panel.field, "CENTER", cueX, cueY)
        addon.VignetteRadarTurn.TrackPoint(panel.activeCue, cueX, cueY, ViewFacing(player.facing))
        panel.activeCue:SetVertexColor(r, g, b, .16)
        panel.activeCue:Show()
        panel.activeCueHit.name = SafeString(activeStep.name)
            or SafeString(activeRouteName) or "Active Destination"
        panel.activeCueHit.kind = SafeString(activeKind) or "Destination"
        panel.activeCueHit.distance = cueDistance
        panel.activeCueHit.routeName = SafeString(activeRouteName)
        panel.activeCueHit.routeIndex = SafeNumber(activeIndex)
        panel.activeCueHit.routeCount = SafeNumber(activeCount)
        panel.activeCueHit:Show()
    else
        panel.activeCue:Hide()
        panel.activeCueHit:Hide()
    end
    local questsInRange = RenderQuestDots(player, range)
    local startsInRange = addon.RenderVignetteRadarQuestStarts(player, mapID, range)
    addon.UpdateVignetteRadarQuestKey()
    local notesToken = layerBudget and layerBudget.Begin("mapNotes",
        panel._layerMapID ~= mapID or panel._layerRange ~= range)
    local notesInRange = panel._notesInRange or 0
    if not layerBudget or notesToken then
        notesInRange = RenderMapNotes(player, range, targets)
        panel._notesInRange = notesInRange
        if notesToken then layerBudget.Finish(notesToken) end
    end
    panel._layerMapID, panel._layerRange = mapID, range
    local edgeCueCount = RenderEdgeCues(player, range, targets)
    local exploreNow = Now()
    local trailSettings = Settings()
    if not panel._exploreNextAt or exploreNow >= panel._exploreNextAt
        or panel._exploreRange ~= range or panel._exploreMapID ~= mapID
        or panel._exploreRadius ~= panel.plotRadius
        or panel._exploreEnabled ~= trailSettings.vignetteRadarBreadcrumbs
        or panel._exploreStyle ~= trailSettings.vignetteRadarTrailStyle
        or panel._exploreLens ~= addon.VignetteRadarLensActive then
        local trailForce = panel._exploreRange ~= range or panel._exploreMapID ~= mapID
            or panel._exploreRadius ~= panel.plotRadius
            or panel._exploreEnabled ~= trailSettings.vignetteRadarBreadcrumbs
            or panel._exploreStyle ~= trailSettings.vignetteRadarTrailStyle
            or panel._exploreLens ~= addon.VignetteRadarLensActive
        local trailToken = layerBudget and layerBudget.Begin("trail", trailForce)
        if not layerBudget or trailToken then
            RenderExploration(player, range)
            if trailToken then layerBudget.Finish(trailToken) end
            panel._exploreNextAt = exploreNow + .2
            panel._exploreRange, panel._exploreMapID = range, mapID
            panel._exploreRadius = panel.plotRadius
            panel._exploreEnabled = trailSettings.vignetteRadarBreadcrumbs
            panel._exploreStyle = trailSettings.vignetteRadarTrailStyle
            panel._exploreLens = addon.VignetteRadarLensActive
        end
    end
    local shown, staleShown, totalInRange = 0, 0, 0
    local groups = {}
    for _, target in ipairs(targets) do
        if TargetVisible(target)
            -- Duplicate Icons: live vignettes the minimap already draws (last-seen ones stay).
            and not (panel._underlayHide and panel._underlayHide.vignettes and not target.stale)
            and not (player.instanceID and target.instanceID and player.instanceID ~= target.instanceID) then
            local dx, dy = target.worldX - player.worldX, target.worldY - player.worldY
            local distance = math.sqrt((dx * dx) + (dy * dy))
            if distance <= range and addon.KeepCenterMarker("target", target.key, distance, range) then
                totalInRange = totalInRange + 1
                local screenX, screenY = Project(dx, dy, distance, ViewFacing(player.facing), panel.plotRadius, range)
                if screenX and screenY then
                    target.distance = distance
                    local group
                    if Settings().vignetteRadarUntangle ~= false then
                        for _, candidate in ipairs(groups) do
                            if (candidate.x-screenX)^2 + (candidate.y-screenY)^2 <= 16^2 then
                                group = candidate; break
                            end
                        end
                    end
                    if not group then
                        group = { x=screenX, y=screenY, items={} }
                        groups[#groups+1] = group
                    end
                    group.items[#group.items+1] = { target=target, x=screenX, y=screenY }
                end
            end
        end
    end
    local drawn = 0
    for _, group in ipairs(groups) do
        local items, size = group.items, #group.items
        if drawn < MAX_BLIPS then
            local expanded = size > 1 and clusterHoverKey == items[1].target.key
                and Now() < (clusterHoverUntil or 0)
            local count = expanded and math.min(size, MAX_BLIPS-drawn) or 1
            for index=1,count do
                local entry = items[index]
                local x, y = entry.x, entry.y
                if expanded then
                    local angle = (index-1) * TWO_PI / size
                    local radius = math.min(25, 14 + size*1.5)
                    x, y = group.x + math.sin(angle)*radius, group.y + math.cos(angle)*radius
                    local magnitude = math.sqrt(x*x+y*y)
                    if magnitude > panel.plotRadius-7 then
                        local factor = (panel.plotRadius-7)/magnitude
                        x, y = x*factor, y*factor
                    end
                end
                PlaceBlip(entry.target.key, x, y, entry.target, ViewFacing(player.facing))
                local blip = panel.blipByKey[entry.target.key]
                if blip and size > 1 then
                    blip.clusterKey = items[1].target.key
                    if not expanded then
                        blip.cluster = {}
                        for _, member in ipairs(items) do blip.cluster[#blip.cluster+1] = member.target end
                        blip.count:SetText(size > 9 and "9+" or tostring(size))
                        blip.count:Show()
                    end
                end
                drawn = drawn + 1
            end
            shown = shown + size
            for _, entry in ipairs(items) do if entry.target.stale then staleShown = staleShown + 1 end end
        end
    end
    if FocusedTargetKey() then
        panel.summary:SetText(focusedTarget and focusedTarget.stale and "LAST SEEN"
            or (shown > 0 and "TARGET FOCUS" or "OUT OF RANGE"))
    else
        panel.summary:SetText(totalInRange > shown and (shown .. " OF " .. totalInRange .. " SHOWN")
            or staleShown > 0 and ((shown - staleShown) .. " LIVE / " .. staleShown .. " SEEN")
            or (shown == 0 and questsInRange > 0 and (questsInRange == 1 and "1 QUEST IN RANGE"
                or questsInRange .. " QUESTS IN RANGE"))
            or (shown == 0 and questAreasShown and "QUEST AREAS")
            or (shown == 0 and notesInRange > 0 and (notesInRange == 1 and "1 MAP NOTE"
                or notesInRange .. " MAP NOTES"))
            or (shown == 0 and startsInRange > 0 and (startsInRange == 1 and "1 QUEST START"
                or startsInRange .. " QUEST STARTS"))
            or (shown == 1 and "1 IN RANGE" or shown .. " IN RANGE"))
    end
    panel.emptyReason = EmptyExplanation(player, shown, questsInRange, notesInRange,
        questAreasShown, startsInRange)
    panel.edgeCueCount = edgeCueCount
    if addon.VignetteRadarLensActive then
        panel.summary:SetText(string.upper(addon.VignetteRadarLensActive) .. " LENS")
    end
    if panel.emptyHelp then
        panel.emptyHelp:SetShown(not CircleOnly()
            and (panel.emptyReason ~= nil or Settings().vignetteRadarDataStatus))
    end
    if panel.layout == "squat" and shown == 0 and panel.emptyReason then
        panel.layoutHint:SetText(panel.emptyReason)
    end
    if addon.VignetteRadarPlayerTracker then
        addon.VignetteRadarPlayerTracker.RenderRadar(panel.field, player, range,
            panel.plotRadius, ViewFacing(player.facing), Project)
    end
    EndBlips()
end

local function SavePosition()
    if not panel then return end
    local left, top = PanelPosition()
    if SafeNumber(left) and SafeNumber(top) and UIParent and UIParent.GetHeight then
        local key = CircleOnly() and "vignetteRadarCirclePosition"
            or "vignetteRadarPosition"
        if CircleOnly() then
            PlacePanel(left, top, panel:GetScale())
            left, top = PanelPosition()
        end
        Settings()[key] = { x = left, y = top - UIParent:GetHeight() }
    end
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Reanchor then quick.Reanchor(CircleOnly() and panel.field or panel) end
    local legend = LegendAPI()
    if legend and legend.ReanchorQuest and legend.IsQuestShown and legend.IsQuestShown() then
        legend.ReanchorQuest(CircleOnly() and panel.field or panel, panel)
    end
end

local function AddResizeGrips()
    local grips = {}
    panel.resizeGrips = grips
    local definitions = {
        { "top", "TOP", 0, 1, panel:GetWidth() - 20, 5 },
        { "bottom", "BOTTOM", 0, -1, panel:GetWidth() - 20, 5 },
        { "left", "LEFT", -1, 0, 5, panel:GetHeight() - 20 },
        { "right", "RIGHT", 1, 0, 5, panel:GetHeight() - 20 },
        { "topLeft", "TOPLEFT", -1, 1, 10, 10 },
        { "topRight", "TOPRIGHT", 1, 1, 5, 5 },
        { "bottomLeft", "BOTTOMLEFT", -1, -1, 10, 10 },
        { "bottomRight", "BOTTOMRIGHT", 1, -1, 10, 10 },
    }
    for _, definition in ipairs(definitions) do
        local key, point, horizontal, vertical, width, height = Unpack(definition)
        local grip = CreateFrame("Frame", nil, panel)
        grip:SetPoint(point, panel, point, 0, 0)
        grip:SetSize(width, height)
        grip:SetFrameLevel(panel:GetFrameLevel() + 3)
        grip:EnableMouse(true)
        grip:RegisterForDrag("LeftButton")
        local highlight = grip:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
        highlight:SetAlpha(0)
        grip.highlight = highlight
        grip:SetScript("OnEnter", function(self)
            self.highlight:SetAlpha(1)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Drag to resize radar", 1, 1, 1)
                GameTooltip:AddLine("The panel grows or shrinks together, keeping its layout and controls aligned.",
                    0.7, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        grip:SetScript("OnLeave", function(self)
            self.highlight:SetAlpha(0)
            if GameTooltip then GameTooltip:Hide() end
        end)
        grip:SetScript("OnDragStart", function(self)
            if type(GetCursorPosition) ~= "function" then return end
            local x, y = GetCursorPosition()
            local factor = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            if not (SafeNumber(x) and SafeNumber(y) and SafeNumber(factor) and factor > 0) then return end
            local left, top = PanelPosition()
            if not (left and top) then return end
            self.resize = { x = x / factor, y = y / factor, left = left, top = top,
                scale = panel:GetScale(), width = panel:GetWidth(), height = panel:GetHeight(), factor = factor }
            local legend, picker = LegendAPI(), TargetPickerAPI()
            if legend and legend.Hide then legend.Hide() end
            if picker and picker.Hide then picker.Hide() end
            self:SetScript("OnUpdate", function(active)
                local cursorX, cursorY = GetCursorPosition()
                local start = active.resize
                if not (start and SafeNumber(cursorX) and SafeNumber(cursorY)) then return end
                local change, axes = 0, 0
                if horizontal ~= 0 then
                    change, axes = horizontal * ((cursorX / start.factor) - start.x) / start.width, axes + 1
                end
                if vertical ~= 0 then
                    change, axes = change + vertical * ((cursorY / start.factor) - start.y) / start.height, axes + 1
                end
                local scale = PanelScale(start.scale + change / axes)
                local oldWidth, oldHeight = start.width * start.scale, start.height * start.scale
                local newWidth, newHeight = start.width * scale, start.height * scale
                local newLeft = horizontal < 0 and start.left + oldWidth - newWidth
                    or (horizontal > 0 and start.left or start.left + (oldWidth - newWidth) / 2)
                local newTop = vertical > 0 and start.top - oldHeight + newHeight
                    or (vertical < 0 and start.top or start.top + (newHeight - oldHeight) / 2)
                PlacePanel(newLeft, newTop, scale)
            end)
        end)
        grip:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            if not self.resize then return end
            self.resize = nil
            Settings().vignetteRadarScale = panel:GetScale()
            addon.VignetteRadarViewProfiles.Record(Settings())
            SavePosition()
        end)
        grip:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            self.resize = nil
        end)
        if key == "bottomRight" then
            for _, stroke in ipairs({ { -3, -4, 4, 3 }, { 1, -4, 4, -1 } }) do
                local line = grip:CreateLine(nil, "ARTWORK")
                line:SetThickness(1)
                line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
                line:SetStartPoint("CENTER", grip, stroke[1], stroke[2])
                line:SetEndPoint("CENTER", grip, stroke[3], stroke[4])
            end
        end
        grips[key] = grip
    end
end

local function PlaceLauncher(left, top)
    if not (launcher and UIParent and UIParent.GetWidth and UIParent.GetHeight) then return end
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = launcher:GetScale()
    if not (SafeNumber(width) and SafeNumber(height) and SafeNumber(scale) and scale > 0
        and width > 0 and height > 0) then return end
    left = SafeNumber(left) and left or 30
    top = SafeNumber(top) and top or height - 170
    left = math.max(4, math.min(left, width - LAUNCHER_DIMENSIONS.width * scale - 4))
    top = math.max(LAUNCHER_DIMENSIONS.height * scale + 4, math.min(top, height - 4))
    launcher:ClearAllPoints()
    launcher:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left / scale, (top - height) / scale)
    return left, top
end

local function SaveLauncherPosition()
    if not launcher then return end
    local scale = launcher:GetScale()
    local rawLeft, rawTop = launcher:GetLeft(), launcher:GetTop()
    if SafeNumber(scale) and SafeNumber(rawLeft) and SafeNumber(rawTop)
        and UIParent and UIParent.GetHeight then
        local left, top = rawLeft * scale, rawTop * scale
        PlaceLauncher(left, top)
        rawLeft, rawTop = launcher:GetLeft(), launcher:GetTop()
        if not (SafeNumber(rawLeft) and SafeNumber(rawTop)) then return end
        left, top = rawLeft * scale, rawTop * scale
        Settings().vignetteRadarLauncherPosition = { x = left, y = top - UIParent:GetHeight() }
    end
end

function Morph.LauncherCenter()
    if not launcher then return nil end
    local scale = launcher:GetScale()
    local left, top = SafeNumber(launcher:GetLeft()), SafeNumber(launcher:GetTop())
    if not (SafeNumber(scale) and left and top) then return nil end
    return (left + LAUNCHER_DIMENSIONS.width / 2) * scale,
        (top - LAUNCHER_DIMENSIONS.height / 2) * scale
end

function Morph.RadarSurface()
    local left, top = PanelPosition()
    if not (left and top) then return nil end
    local scale = panel:GetScale()
    if not CircleOnly() then
        local width, height = panel:GetWidth() * scale, panel:GetHeight() * scale
        return left + width / 2, top - height / 2, width, height
    end
    local name = panel.layout or Settings().vignetteRadarLayout or "classic"
    local layout = LAYOUTS[name] or LAYOUTS.classic
    local fieldLeft = name == "squat" and 10 or (layout.width - layout.field) / 2
    local fieldBottom = name == "squat" and 38
        or (layout.footer or ZOOM_FOOTER_H) + (panel.layoutFocused and (layout.focus or 0) or 0) + 9
    local size = (layout.field - (panel.squarePlot and 18 or 0)) * scale
    return left + (fieldLeft + layout.field / 2) * scale,
        top - (panel:GetHeight() - fieldBottom - layout.field / 2) * scale, size, size
end

function Morph.MoveLauncherToRadar()
    if not launcher or not panel then return end
    local x, y = Morph.RadarSurface()
    if not (x and y) then return end
    local scale = launcher:GetScale()
    local left, top = PlaceLauncher(x - LAUNCHER_DIMENSIONS.width * scale / 2,
        y + LAUNCHER_DIMENSIONS.height * scale / 2)
    if left and top then
        Settings().vignetteRadarLauncherPosition = { x = left, y = top - UIParent:GetHeight() }
    end
end

function Morph.MoveRadarToLauncher(x, y)
    if not (panel and x and y) then return end
    local currentX, currentY = Morph.RadarSurface()
    local left, top = PanelPosition()
    if not (currentX and currentY and left and top) then return end
    PlacePanel(left + x - currentX, top + y - currentY, panel:GetScale())
    SavePosition()
end

function Morph.SyncLauncherVisibility()
    if not launcher then return end
    local wanted = (Settings().vignetteRadarLauncherVisible ~= false or launcherPeekActive)
        and (not panel or not panel:IsShown() or launcherPeekActive or launcher._rescueRaised)
        and not Morph.running
    if launcher:IsShown() ~= wanted then launcher:SetShown(wanted) end
end

function Morph.Start(opening, fromX, fromY, fromWidth, fromHeight,
    toX, toY, toWidth, toHeight)
    if not (fromX and fromY and fromWidth and fromHeight
        and toX and toY and toWidth and toHeight) then
        Morph.running = false
        if panel then panel._morphAlpha = nil end
        if not opening and panel then panel:Hide() end
        Morph.SyncLauncherVisibility()
        return
    end
    if not Morph.shell then
        Morph.shell = CreateFrame("Frame", "VignetteRadarMorphShell", UIParent)
        Morph.shell:SetFrameStrata("HIGH")
        Morph.shell:EnableMouse(false)
        Morph.shell.face = Morph.shell:CreateTexture(nil, "BACKGROUND")
        Morph.shell.face:SetAllPoints()
        Morph.shell.face:SetTexture(ROUNDED_SQUARE_TEXTURE)
        Morph.shell.border = Morph.shell:CreateTexture(nil, "OVERLAY")
        Morph.shell.border:SetAllPoints()
        Morph.shell.border:SetTexture(ROUNDED_BORDER_TEXTURE)
        Morph.shell.launcherFace = Morph.shell:CreateTexture(nil, "BACKGROUND", nil, 1)
        Morph.shell.launcherFace:SetAllPoints()
        Morph.shell.launcherFace:SetTexture("Interface\\AddOns\\Magpie\\Media\\launcher-housing.tga")
        Morph.shell.launcherBorder = Morph.shell:CreateTexture(nil, "OVERLAY", nil, 1)
        Morph.shell.launcherBorder:SetAllPoints()
        Morph.shell.launcherBorder:SetTexture("Interface\\AddOns\\Magpie\\Media\\launcher-outline.tga")
    end
    local morphShell = Morph.shell
    local style = addon.VignetteRadarStyle
    if style and style.Color then
        morphShell.face:SetVertexColor(style.Color("background"))
        morphShell.border:SetVertexColor(style.Color("accent"))
        morphShell.launcherFace:SetVertexColor(style.Color("background"))
        morphShell.launcherBorder:SetVertexColor(style.Color("accent"))
    end
    morphShell.opening = opening
    morphShell.elapsed = 0
    morphShell.from = { fromX, fromY, fromWidth, fromHeight }
    morphShell.to = { toX, toY, toWidth, toHeight }
    morphShell:SetSize(fromWidth, fromHeight)
    morphShell:ClearAllPoints()
    morphShell:SetPoint("CENTER", UIParent, "BOTTOMLEFT", fromX, fromY)
    morphShell:SetAlpha(1)
    morphShell.face:SetAlpha(opening and 0 or 1)
    morphShell.border:SetAlpha(opening and 0 or 1)
    morphShell.launcherFace:SetAlpha(opening and 1 or 0)
    morphShell.launcherBorder:SetAlpha(opening and 1 or 0)
    Morph.running = true
    if panel then
        panel._morphAlpha = opening and 0 or 1
        panel:SetAlpha((VisuallyQuiet() and 0.35 or 1) * panel._morphAlpha)
    end
    Morph.SyncLauncherVisibility()
    morphShell:Show()
    morphShell:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = math.min(0.18, self.elapsed + elapsed)
        local progress = self.elapsed / 0.18
        local eased = progress * progress * (3 - 2 * progress)
        local from, to = self.from, self.to
        local x = from[1] + (to[1] - from[1]) * eased
        local y = from[2] + (to[2] - from[2]) * eased
        self:SetSize(from[3] + (to[3] - from[3]) * eased,
            from[4] + (to[4] - from[4]) * eased)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        local launcherBlend = opening and 1 - eased or eased
        self.face:SetAlpha(1 - launcherBlend)
        self.border:SetAlpha(1 - launcherBlend)
        self.launcherFace:SetAlpha(launcherBlend)
        self.launcherBorder:SetAlpha(launcherBlend)
        self:SetAlpha(opening and 1 - eased or eased)
        if panel then
            panel._morphAlpha = opening and eased or 1 - eased
            panel:SetAlpha((VisuallyQuiet() and 0.35 or 1) * panel._morphAlpha)
        end
        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            Morph.running = false
            if panel then
                panel._morphAlpha = nil
                panel:SetAlpha(VisuallyQuiet() and 0.35 or 1)
                if not opening then panel:Hide() end
            end
            Morph.SyncLauncherVisibility()
        end
    end)
end

function Morph.Cancel()
    if not Morph.running then return end
    if Morph.shell then
        Morph.shell:SetScript("OnUpdate", nil)
        Morph.shell:Hide()
    end
    Morph.running = false
    if panel then
        panel._morphAlpha = nil
        panel:SetAlpha(VisuallyQuiet() and 0.35 or 1)
        if Morph.shell and not Morph.shell.opening then panel:Hide() end
    end
    Morph.SyncLauncherVisibility()
end

local function LauncherTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText("Magpie", 1, 1, 1)
    GameTooltip:AddLine((Settings().vignetteRadarEnabled == true or preview)
        and "This mini radar shows live detections within 150 yards."
        or "Tracking is off. Click to reopen the radar and resume detection.",
        0.55, 0.86, 0.76, true)
    if (owner.bosses or 0) > 0 then GameTooltip:AddLine(owner.bosses .. " world boss nearby", 1, 0.18, 0.12) end
    if (owner.rares or 0) > 0 then GameTooltip:AddLine(owner.rares .. " rare enemy nearby", 0.78, 0.88, 1) end
    GameTooltip:AddLine("Silver skull: rare enemy. Larger red skull: world boss.", 0.78, 0.88, 1, true)
    GameTooltip:AddLine("Left-click to expand this mini radar.", 0.65, 0.80, 0.77, true)
    GameTooltip:AddLine("Right-click to preview. Shift-right-click opens Living Atlas. Drag to move.",
        0.65, 0.80, 0.77, true)
    if (owner.detected or 0) == 0 then
        local reason = EmptyExplanation(PlayerSnapshot(CurrentMapID()), 0, 0, 0, false)
        if reason then GameTooltip:AddLine(reason, .7, .83, .79, true) end
    end
    GameTooltip:Show()
end

local function PlayLauncherSound()
    if Quiet() then return end
    if type(PlaySound) ~= "function" then return end
    local sound = SOUNDKIT and (SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION)
    if sound then pcall(PlaySound, sound) end
end

local function ToggleRadarPanel()
    Morph.Cancel()
    if panel and panel:IsShown() then
        local x, y, width, height = Morph.RadarSurface()
        Morph.MoveLauncherToRadar()
        local targetX, targetY = x, y
        manualPanelState = false
        preview = false
        if HideTrailPopup then HideTrailPopup() end
        if routeMenu.Hide then routeMenu.Hide() end
        local legend = LegendAPI()
        if legend and type(legend.Hide) == "function" then pcall(legend.Hide) end
        if legend and type(legend.HideQuest) == "function" then pcall(legend.HideQuest) end
        local picker = TargetPickerAPI()
        if picker and type(picker.Hide) == "function" then pcall(picker.Hide) end
        Morph.Start(false, x, y, width, height,
            targetX, targetY, LAUNCHER_DIMENSIONS.width, LAUNCHER_DIMENSIONS.height)
    else
        local x, y = Morph.LauncherCenter()
        Settings().vignetteRadarEnabled = true
        manualPanelState = true
        RefreshRadar(true)
        if panel and panel:IsShown() and x and y then
            Morph.MoveRadarToLauncher(x, y)
            local targetX, targetY, width, height = Morph.RadarSurface()
            Morph.Start(true, x, y, LAUNCHER_DIMENSIONS.width, LAUNCHER_DIMENSIONS.height,
                targetX, targetY, width, height)
        end
    end
    Morph.SyncLauncherVisibility()
    if UpdateLauncher then UpdateLauncher(0, true) end
end

local function CreateLauncherRing(parent, radius, alpha, count, thickness)
    local ring = {}
    count = count or 24
    for index = 1, count do
        local line = parent:CreateLine(nil, "ARTWORK")
        local first = ((index - 1) / count) * TWO_PI
        local last = (index / count) * TWO_PI
        line:SetThickness(thickness or 1)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], alpha)
        line:SetStartPoint("CENTER", parent, math.cos(first) * radius, math.sin(first) * radius)
        line:SetEndPoint("CENTER", parent, math.cos(last) * radius, math.sin(last) * radius)
        ring[index] = line
    end
    return ring
end

local function UpdateLauncherSweep(frame, elapsed)
    ApplyAppearance()
    frame:SetAlpha(VisuallyQuiet() and 0.35 or 1)
    local active = Settings().vignetteRadarEnabled == true or preview
    if frame._activeState ~= active then
        frame._activeState = active
        for _, group in ipairs({ frame.dial, frame.ring, frame.cardinals }) do
            for _, line in ipairs(group) do line:SetAlpha(active and 1 or .3) end
        end
        for _, facet in ipairs(frame.facets) do
            facet.rim:SetAlpha(active and 1 or .45)
            facet.core:SetAlpha(active and 1 or .3)
        end
        frame.depth:SetAlpha(active and 1 or .35)
    end
    local now = Now()
    local alerting = active and pulseUntil > now and not Quiet()
    local animated = active and ((frame.detected or 0) > 0 or frame._hovered or alerting)
    local speed = frame._hovered and 1.35 or 0.72
    if animated then frame._sweepAngle = ((frame._sweepAngle or 0) + math.min(elapsed, 0.10) * speed) % TWO_PI end
    for index, line in ipairs(frame.sweepLines) do
        line:SetShown(animated)
        if animated then
            local angle = frame._sweepAngle - ((index - 1) * 0.13)
            line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.22 / index)
            line:SetEndPoint("CENTER", frame.instrument, math.sin(angle) * 14,
                math.cos(angle) * 14)
        end
    end

    frame.bezel:SetShown(active)
    frame.closed:SetShown(not active)
    local stateTexture = active and frame.bezel or frame.closed
    local stateAlpha = active and 0.92 or 0.62
    if frame._pressed then
        stateAlpha = 0.76
    elseif frame._hovered then
        stateAlpha = 1
    elseif (frame.detected or 0) > 0 then
        stateAlpha = 1
    end
    if alerting then stateAlpha = 0.82 + 0.18 * math.abs(math.sin(now * 6)) end
    stateTexture:SetAlpha(stateAlpha)
    frame.face:SetAlpha(frame._pressed and 0.82 or 1)
    frame.center:SetAlpha(active and 1 or .34)
    frame.centerGlow:SetAlpha(active and 1 or .22)

    if frame._shock then
        frame._shock = frame._shock + elapsed / 0.24
        if frame._shock >= 1 then
            frame._shock = nil
            frame.shock:Hide()
        else
            local size = 28 + (frame._shock * 16)
            frame.shock:SetSize(size, size)
            frame.shock:SetAlpha((1 - frame._shock) * 0.22)
            frame.shock:Show()
        end
    end
end

UpdateLauncher = function(elapsed, updateTargets)
    if not launcher then return end
    UpdateLauncherSweep(launcher, elapsed or 0)
    if not updateTargets then return end

    local range = LAUNCHER_RANGE
    local shown, rares, bosses = 0, 0, 0
    local highlight = HighlightCategory()
    local player = not preview and Settings().vignetteRadarEnabled == true and PlayerSnapshot(CurrentMapID()) or nil
    local hasHeading = preview or (player and player.headingAvailable) == true
    launcher.direction:SetShown(hasHeading)
    for _, line in ipairs(launcher.chevron) do line:SetShown(hasHeading) end
    if hasHeading then
        local facing = preview and 0.65 or player.facing
        DrawPlayerHeading(launcher.direction, launcher.instrument, facing, 6, 12)
        DrawLauncherChevron(launcher.chevron, launcher.instrument, facing)
    end
    local function ShowDot(target, x, y)
        shown = shown + 1
        local dot = launcher.miniBlips[shown]
        if not dot then shown = shown - 1; return false end
        local red, green, blue = TargetColor(target)
        if not target.stale then
            if target.isWorldBoss then bosses = bosses + 1
            elseif target.category == "rare" then rares = rares + 1 end
        end
        local size = (tonumber(Settings().vignetteRadarMarkerSize) or 7) * 0.5
        if highlight == (target.category or "other") or Favorite(target) then size = size + 1 end
        StyleMarker(dot, dot.dot, target, size, red, green, blue)
        dot:SetAlpha(CategoryOpacity(target.category) * TargetAlpha(target))
        dot:SetSize(size + 2, size + 2)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", launcher.instrument, "CENTER", x, y)
        if player then addon.VignetteRadarTurn.TrackPoint(dot, x, y, ViewFacing(player.facing)) end
        dot:Show()
        return shown < #launcher.miniBlips
    end

    if preview then
        for _, target in ipairs(PREVIEW_TARGETS) do
            local x, y = PreviewPosition(target.launcherX, target.launcherY)
            if TargetVisible(target) then ShowDot(target, x, y) end
        end
    elseif player then
        for _, target in ipairs(SelectableTargets()) do
            if TargetVisible(target)
                and not (player.instanceID and target.instanceID and player.instanceID ~= target.instanceID) then
                local dx, dy = target.worldX - player.worldX, target.worldY - player.worldY
                local distance = math.sqrt((dx * dx) + (dy * dy))
                if distance <= range then
                    local x, y = Project(dx, dy, distance, ViewFacing(player.facing), LAUNCHER_RADIUS - 5, range)
                    if x and y and not ShowDot(target, x, y) then break end
                end
            end
        end
    end
    for index = shown + 1, #launcher.miniBlips do launcher.miniBlips[index]:Hide() end
    launcher.detected = shown
    launcher.rares, launcher.bosses = rares, bosses
    local active = Settings().vignetteRadarEnabled == true or preview
    launcher.rangeLabel:SetText(not active and "OFF" or (bosses > 0 and "BOSS"
        or (rares > 0 and "RARE" or "150 YD")))
    if not active then launcher.rangeLabel:SetTextColor(.72, .74, .78, .7)
    elseif bosses > 0 then launcher.rangeLabel:SetTextColor(1, 0.25, 0.18, 1)
    elseif rares > 0 then launcher.rangeLabel:SetTextColor(0.78, 0.88, 1, 1)
    else
        local style = addon.VignetteRadarStyle
        if style and style.Color then
            local r, g, b = style.Color("rings")
            launcher.rangeLabel:SetTextColor(r, g, b, .72)
        else launcher.rangeLabel:SetTextColor(.56, .78, .74, .68) end
    end
end

EnsureLauncher = function()
    if launcher then return launcher end
    launcher = CreateFrame("Button", "VignetteRadarLauncher", UIParent)
    launcher:SetSize(LAUNCHER_DIMENSIONS.width, LAUNCHER_DIMENSIONS.height)
    launcher:SetFrameStrata("MEDIUM")
    launcher:SetClampedToScreen(true)
    launcher:SetMovable(true)
    launcher:EnableMouse(true)
    launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    launcher:RegisterForDrag("LeftButton")
    local position = Settings().vignetteRadarLauncherPosition
    local savedY = type(position) == "table" and SafeNumber(tonumber(position.y))
    PlaceLauncher(type(position) == "table" and tonumber(position.x) or 30,
        UIParent:GetHeight() + (savedY or -170))

    launcher.face = launcher:CreateTexture(nil, "BORDER")
    launcher.face:SetSize(LAUNCHER_DIMENSIONS.width, LAUNCHER_DIMENSIONS.height)
    launcher.face:SetPoint("CENTER")
    launcher.face:SetTexture("Interface\\AddOns\\Magpie\\Media\\launcher-housing.tga")
    launcher.face:SetVertexColor(0.012, 0.046, 0.052, 0.98)
    launcher.instrument = CreateFrame("Frame", nil, launcher)
    launcher.instrument:SetSize(56, 56)
    launcher.instrument:SetPoint("LEFT", launcher, "LEFT", 4, 0)
    launcher.depth = launcher.instrument:CreateTexture(nil, "BORDER", nil, 1)
    launcher.depth:SetSize(42, 42)
    launcher.depth:SetPoint("CENTER")
    launcher.depth:SetTexture(CIRCLE_TEXTURE)
    launcher.depth:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .07)
    launcher.ring = CreateLauncherRing(launcher.instrument, 15, 0.18)
    launcher.dial = CreateLauncherRing(launcher.instrument, 21, .64, 32, 1.5)
    launcher.cardinals = {}
    for index = 1, 4 do
        local angle = (index - 1) * math.pi / 2
        local x, y = math.sin(angle), math.cos(angle)
        local line = launcher.instrument:CreateLine(nil, "ARTWORK")
        line:SetThickness(1.7)
        line:SetStartPoint("CENTER", launcher.instrument, x * 24, y * 24)
        line:SetEndPoint("CENTER", launcher.instrument, x * 27, y * 27)
        launcher.cardinals[index] = line
    end

    launcher.sweepLines = {}
    for index = 1, 2 do
        local line = launcher.instrument:CreateLine(nil, "OVERLAY")
        line:SetThickness(index == 1 and 1.2 or 1)
        line:SetStartPoint("CENTER", launcher.instrument, 0, 0)
        launcher.sweepLines[index] = line
    end
    launcher.centerGlow = launcher.instrument:CreateTexture(nil, "OVERLAY")
    launcher.centerGlow:SetSize(9, 9)
    launcher.centerGlow:SetPoint("CENTER")
    launcher.centerGlow:SetTexture(CIRCLE_TEXTURE)
    launcher.centerGlow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.22)
    launcher.center = launcher.instrument:CreateTexture(nil, "OVERLAY", nil, 1)
    launcher.center:SetSize(4, 4)
    launcher.center:SetPoint("CENTER")
    launcher.center:SetTexture(CIRCLE_TEXTURE)
    launcher.center:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    launcher.direction = launcher.instrument:CreateLine(nil, "OVERLAY")
    launcher.direction:SetThickness(1.5)
    launcher.direction:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.95)
    launcher.direction:Hide()
    launcher.chevron = {}
    for index = 1, 2 do
        local line = launcher.instrument:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.3)
        line:Hide()
        launcher.chevron[index] = line
    end
    launcher.miniBlips = {}
    for index = 1, 5 do
        local dot = CreateFrame("Frame", nil, launcher.instrument)
        dot.isMini = true
        dot:SetFrameLevel(launcher.instrument:GetFrameLevel() + 1)
        dot:SetSize(3, 3)
        dot.dot = dot:CreateTexture(nil, "OVERLAY")
        dot.dot:SetPoint("CENTER")
        dot.dot:SetTexture(CIRCLE_TEXTURE)
        dot:Hide()
        launcher.miniBlips[index] = dot
    end
    launcher.titleLabel = Text(launcher, 10, "RADAR", true)
    launcher.titleLabel:SetPoint("LEFT", launcher, "LEFT", 72, 9)
    launcher.titleLabel:SetWidth(54)
    launcher.rangeLabel = Text(launcher, 10, "150 YD")
    launcher.rangeLabel:SetPoint("LEFT", launcher, "LEFT", 72, -9)
    launcher.rangeLabel:SetWidth(56)
    launcher.rangeLabel:SetJustifyH("LEFT")
    launcher.rangeLabel:SetTextColor(0.56, 0.78, 0.74, 0.68)
    launcher.readoutLine = launcher:CreateLine(nil, "ARTWORK")
    launcher.readoutLine:SetThickness(1)
    launcher.readoutLine:SetStartPoint("CENTER", launcher, -4, -16)
    launcher.readoutLine:SetEndPoint("CENTER", launcher, -4, 16)
    launcher.expandChevron = {}
    for index, points in ipairs({ { 57, -5, 62, 0 }, { 62, 0, 57, 5 } }) do
        local line = launcher:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.5)
        line:SetStartPoint("CENTER", launcher, points[1], points[2])
        line:SetEndPoint("CENTER", launcher, points[3], points[4])
        launcher.expandChevron[index] = line
    end
    launcher.chrome = launcher:CreateTexture(nil, "OVERLAY", nil, 2)
    launcher.chrome:SetAllPoints()
    launcher.chrome:SetTexture("Interface\\AddOns\\Magpie\\Media\\launcher-outline.tga")
    launcher.chrome:SetVertexColor(.46, .48, .52, .26)
    launcher.bezel = launcher:CreateTexture(nil, "OVERLAY", nil, 3)
    launcher.bezel:SetSize(LAUNCHER_DIMENSIONS.width, LAUNCHER_DIMENSIONS.height)
    launcher.bezel:SetPoint("CENTER")
    launcher.bezel:SetTexture("Interface\\AddOns\\Magpie\\Media\\launcher-outline.tga")
    launcher.bezel:SetAlpha(0.92)
    launcher.closed = launcher:CreateTexture(nil, "OVERLAY", nil, 3)
    launcher.closed:SetSize(LAUNCHER_DIMENSIONS.width, LAUNCHER_DIMENSIONS.height)
    launcher.closed:SetPoint("CENTER")
    launcher.closed:SetTexture("Interface\\AddOns\\Magpie\\Media\\launcher-outline.tga")
    launcher.closed:SetAlpha(0.62)
    launcher.closed:Hide()
    launcher.facets = {}
    launcher.shock = launcher.instrument:CreateTexture(nil, "OVERLAY", nil, 4)
    launcher.shock:SetPoint("CENTER")
    launcher.shock:SetTexture(CIRCLE_TEXTURE)
    launcher.shock:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    launcher.shock:Hide()

    launcher:SetScript("OnEnter", function(self)
        self._hovered = true
        LauncherTooltip(self)
    end)
    launcher:SetScript("OnLeave", function(self)
        self._hovered = false
        self._pressed = false
        if GameTooltip then GameTooltip:Hide() end
    end)
    launcher:SetScript("OnMouseDown", function(self) self._pressed = true end)
    launcher:SetScript("OnMouseUp", function(self) self._pressed = false end)
    launcher:SetScript("OnDragStart", function(self)
        self._dragging = true
        self._suppressClick = true
        self:StartMoving()
        if GameTooltip then GameTooltip:Hide() end
    end)
    launcher:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._dragging = false
        SaveLauncherPosition()
        if self._rescueRaised then
            self:SetFrameStrata("MEDIUM")
            self._rescueRaised = nil
        end
        if self._peekReleased and EndLauncherPeek then EndLauncherPeek() end
        Morph.SyncLauncherVisibility()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() self._suppressClick = false end)
        else
            self._suppressClick = false
        end
    end)
    launcher:SetScript("OnClick", function(self, button)
        if self._suppressClick or self._dragging then return end
        self._shock = 0.001
        PlayLauncherSound()
        if button == "RightButton" then
            if IsShiftKeyDown and IsShiftKeyDown()
                and Settings().vignetteRadarAdvancedTools == true then
                addon.VignetteRadarAPI.ToggleAtlas()
            else
                preview = not preview
                manualPanelState = preview and true or nil
                RefreshRadar(true)
            end
        else
            ToggleRadarPanel()
        end
    end)
    launcher:SetScript("OnUpdate", function(self, elapsed)
        local started = ProfileTime()
        local turn = addon.VignetteRadarTurn
        self._turnElapsed = (self._turnElapsed or 0) + elapsed
        if self._turnElapsed >= turn.Interval(self, addon.VignetteRadarBudget
            and addon.VignetteRadarBudget.softThrottle) then
            local turnElapsed = self._turnElapsed
            self._turnElapsed = 0
            if not preview and Settings().vignetteRadarEnabled
                and type(GetPlayerFacing) == "function" then
                local ok, facing = pcall(GetPlayerFacing)
                facing = ok and SafeNumber(facing) or nil
                if facing then
                    if Settings().vignetteRadarNorthUp then
                        DrawPlayerHeading(self.direction, self.instrument, facing, 6, 12)
                        DrawLauncherChevron(self.chevron, self.instrument, facing)
                    end
                    turn.UpdateLauncher(self, ViewFacing(facing), turnElapsed)
                end
            end
        end
        self._sweepElapsed = (self._sweepElapsed or 0) + elapsed
        self._targetElapsed = (self._targetElapsed or 0) + elapsed
        self._scanElapsed = (self._scanElapsed or 0) + elapsed
        if self._sweepElapsed >= 0.10
            and (self._hovered or self._shock or (self.detected or 0) > 0 or pulseUntil > Now()) then
            UpdateLauncherSweep(self, self._sweepElapsed)
            self._sweepElapsed = 0
        end
        local launcherInterval = (self._hovered or self._shock or (self.detected or 0) > 0)
            and .25 or .5
        if self._targetElapsed >= launcherInterval then
            self._targetElapsed = 0
            UpdateLauncher(0, true)
        end
        if self._scanElapsed >= addon.VignetteRadarScanSeconds()
            and Settings().vignetteRadarEnabled == true
            and (not panel or not panel:IsShown()) then
            self._scanElapsed = 0
            RefreshRadar(true)
        end
        CheckUpdateBudget(self, started, "launcher")
    end)
    UpdateLauncher(0, true)
    return launcher
end

EndLauncherPeek = function()
    if not launcherPeekActive then return end
    launcherPeekActive = false
    if not launcher then return end
    launcher:SetFrameStrata(launcher._peekStrata or "MEDIUM")
    if launcher._peekLevel ~= nil then launcher:SetFrameLevel(launcher._peekLevel) end
    launcher._peekStrata, launcher._peekLevel, launcher._peekReleased = nil, nil, nil
    Morph.SyncLauncherVisibility()
end

function VignetteRadar_RaiseLauncher(keystate)
    if keystate == "up" then
        if launcher and launcher._dragging then launcher._peekReleased = true
        else EndLauncherPeek() end
        return
    end
    if keystate ~= "down" then return end
    if launcherPeekActive then return end
    launcherPeekActive = true
    local button = EnsureLauncher()
    button._peekStrata = button:GetFrameStrata()
    button._peekLevel = button:GetFrameLevel()
    button:SetFrameStrata("TOOLTIP")
    button:SetFrameLevel(1000)
    button:Show()
end

local function EnsurePanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "VignetteRadarPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(not CircleOnly())
    panel:SetMovable(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", OnZoomWheel)
    Surface(panel)
    local position = CircleOnly()
        and (Settings().vignetteRadarCirclePosition or Settings().vignetteRadarPosition)
        or Settings().vignetteRadarPosition
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
        type(position) == "table" and tonumber(position.x) or 30,
        type(position) == "table" and tonumber(position.y) or -520)

    panel.title = Text(panel, 11, "MAGPIE", true)
    panel.title:SetPoint("TOPLEFT", 12, -6)
    panel.title:SetWidth(100)
    panel.summary = Text(panel, 8, "0 IN RANGE")
    panel.summary:SetPoint("TOPLEFT", 12, -21)
    panel.summary:SetJustifyH("LEFT")
    panel.summary:SetWidth(100)
    panel.emptyHelp = CreateFrame("Button", nil, panel)
    panel.emptyHelp:SetAllPoints(panel.summary)
    panel.emptyHelp:SetFrameLevel(panel:GetFrameLevel() + 2)
    panel.emptyHelp:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(panel.emptyReason and "Why is the radar empty?"
            or "Radar data status", 1, 1, 1)
        if panel.emptyReason then GameTooltip:AddLine(panel.emptyReason, .7, .83, .79, true) end
        if Settings().vignetteRadarDataStatus then
            for _, line in ipairs(addon.GetVignetteRadarStatusLines()) do
                GameTooltip:AddLine(line, .7, .83, .79, true)
            end
        else
            GameTooltip:AddLine("Your range, filters, and selected map-data pack are in Quick settings.",
                .58, .68, .68, true)
        end
        GameTooltip:Show()
    end)
    panel.emptyHelp:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.emptyHelp:Hide()

    panel.layoutHint = Text(panel, 9, "Nothing detected here yet.")
    panel.layoutHint:SetPoint("TOPLEFT", 214, -76)
    panel.layoutHint:SetSize(148, 40)
    panel.layoutHint:SetWordWrap(true)
    panel.layoutHint:SetTextColor(0.65, 0.69, 0.71, 1)
    panel.layoutHint:Hide()
    panel.sideCaption = Text(panel, 8, "NEAREST DETECTION", true)
    panel.sideCaption:SetSize(148, 12)
    panel.sideCaption:Hide()
    panel.sideGuide = Text(panel, 8, "CLICK TO FOCUS")
    panel.sideGuide:SetSize(148, 14)
    panel.sideGuide:SetTextColor(0.55, 0.70, 0.67, 1)
    panel.sideGuide:Hide()

    panel.drag = CreateFrame("Frame", nil, panel)
    panel.drag:SetPoint("TOPLEFT", 4, -3)
    panel.drag:SetSize(106, HEADER_H - 6)
    panel.drag:EnableMouse(true)
    panel.drag:RegisterForDrag("LeftButton")
    panel.drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    panel.drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); SavePosition() end)

    panel.settingsDot = CreateFrame("Button", nil, panel)
    panel.settingsDot:SetSize(20, 20)
    panel.settingsDot:SetPoint("TOPRIGHT", -85, -6)
    panel.settingsDot:SetFrameLevel(panel:GetFrameLevel() + 2)
    panel.settingsDot.rim = panel.settingsDot:CreateTexture(nil, "ARTWORK")
    panel.settingsDot.rim:SetSize(18, 18)
    panel.settingsDot.rim:SetPoint("CENTER")
    panel.settingsDot.rim:SetTexture(CIRCLE_TEXTURE)
    panel.settingsDot.rim:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.20)
    panel.settingsDot.inner = panel.settingsDot:CreateTexture(nil, "ARTWORK")
    panel.settingsDot.inner:SetSize(13, 13)
    panel.settingsDot.inner:SetPoint("CENTER")
    panel.settingsDot.inner:SetTexture(CIRCLE_TEXTURE)
    panel.settingsDot.inner:SetVertexColor(0.018, 0.04, 0.042, 1)
    panel.settingsDot.dot = panel.settingsDot:CreateTexture(nil, "OVERLAY")
    panel.settingsDot.dot:SetSize(6, 6)
    panel.settingsDot.dot:SetPoint("CENTER")
    panel.settingsDot.dot:SetTexture(CIRCLE_TEXTURE)
    panel.settingsDot.dot:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    panel.settingsDot:SetScript("OnClick", function()
        HideTrailPopup()
        routeMenu.Hide()
        local quick = addon.VignetteRadarQuickConfig
        if not (quick and quick.Toggle) then return end
        local legend, picker = LegendAPI(), TargetPickerAPI()
        if legend and legend.Hide then legend.Hide() end
        if picker and picker.Hide then picker.Hide() end
        quick.Toggle(CircleOnly() and panel.field or panel)
    end)
    panel.settingsDot:SetScript("OnEnter", function(self)
        self.rim:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.55)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Quick settings", 1, 1, 1)
        GameTooltip:AddLine("Open compact controls for every radar setting.", 0.65, 0.80, 0.77, true)
        GameTooltip:Show()
    end)
    panel.settingsDot:SetScript("OnLeave", function(self)
        local quick = addon.VignetteRadarQuickConfig
        self.rim:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3],
            quick and quick.IsShown and quick.IsShown() and .68 or .20)
        if GameTooltip then GameTooltip:Hide() end
    end)

    panel.target = CreateFrame("Button", nil, panel)
    panel.target:SetSize(24, 24)
    panel.target:SetPoint("TOPRIGHT", -57, -5)
    panel.target:SetAlpha(0.68)
    panel.target:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.target.glow = panel.target:CreateTexture(nil, "BACKGROUND")
    panel.target.glow:SetSize(18, 18)
    panel.target.glow:SetPoint("CENTER")
    panel.target.glow:SetTexture(CIRCLE_TEXTURE)
    panel.target.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.05)
    panel.target.crossH = panel.target:CreateTexture(nil, "ARTWORK")
    panel.target.crossH:SetSize(16, 1)
    panel.target.crossH:SetPoint("CENTER")
    panel.target.crossH:SetColorTexture(0.61, 0.67, 0.68, 0.80)
    panel.target.crossV = panel.target:CreateTexture(nil, "ARTWORK")
    panel.target.crossV:SetSize(1, 16)
    panel.target.crossV:SetPoint("CENTER")
    panel.target.crossV:SetColorTexture(0.61, 0.67, 0.68, 0.80)
    panel.target.dot = panel.target:CreateTexture(nil, "OVERLAY")
    panel.target.dot:SetSize(6, 6)
    panel.target.dot:SetPoint("CENTER")
    panel.target.dot:SetTexture(CIRCLE_TEXTURE)
    panel.target.dot:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    panel.target:SetScript("OnClick", function(self, button)
        HideTrailPopup()
        routeMenu.Hide()
        if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Hide() end
        local picker = TargetPickerAPI()
        if not picker then return end
        local legend = LegendAPI()
        if legend and type(legend.Hide) == "function" then pcall(legend.Hide) end
        panel.legend:SetAlpha(0.68)
        if button == "RightButton" then
            if type(picker.ClearFocus) == "function" then pcall(picker.ClearFocus) end
        elseif type(picker.Toggle) == "function" then
            pcall(picker.Toggle, CircleOnly() and panel.field or panel)
        end
        UpdateTargetButton()
    end)
    panel.target:SetScript("OnEnter", function(self)
        self._hovered = true
        UpdateTargetButton()
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Focus a specific vignette", 1, 1, 1)
        GameTooltip:AddLine("Choose one current detection to isolate on the full radar and the 150-yard launcher view.",
            0.65, 0.80, 0.77, true)
        GameTooltip:AddLine("Right-click to show all again.", 0.55, 0.86, 0.76, true)
        GameTooltip:Show()
    end)
    panel.target:SetScript("OnLeave", function(self)
        self._hovered = false
        UpdateTargetButton()
        if GameTooltip then GameTooltip:Hide() end
    end)

    panel.legend = CreateFrame("Button", nil, panel)
    panel.legend:SetSize(24, 24)
    panel.legend:SetPoint("TOPRIGHT", -31, -5)
    panel.legend:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.legend:SetAlpha(0.68)
    panel.legend.glow = panel.legend:CreateTexture(nil, "BACKGROUND")
    panel.legend.glow:SetSize(18, 18)
    panel.legend.glow:SetPoint("CENTER")
    panel.legend.glow:SetTexture(CIRCLE_TEXTURE)
    panel.legend.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0)
    local legendColors = {
        { 0.78, 0.88, 1.00 },
        { 1.00, 0.68, 0.16 },
        { 0.67, 0.42, 1.00 },
    }
    panel.legend.dots = {}
    for index, color in ipairs(legendColors) do
        local dot = panel.legend:CreateTexture(nil, "ARTWORK")
        dot:SetSize(4, 4)
        dot:SetPoint("LEFT", 4, 12 - (index * 6))
        dot:SetTexture(CIRCLE_TEXTURE)
        dot:SetVertexColor(color[1], color[2], color[3], 1)
        panel.legend.dots[index] = dot
        local line = panel.legend:CreateTexture(nil, "ARTWORK")
        line:SetSize(9, 1)
        line:SetPoint("LEFT", 11, 12 - (index * 6))
        line:SetColorTexture(0.68, 0.72, 0.74, 0.72)
    end
    panel.legend:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if addon.ToggleVignetteRadarQuestKey then addon.ToggleVignetteRadarQuestKey() end
            return
        end
        HideTrailPopup()
        routeMenu.Hide()
        if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Hide() end
        local legend = LegendAPI()
        if not (legend and type(legend.Toggle) == "function") then return end
        local picker = TargetPickerAPI()
        if picker and type(picker.Hide) == "function" then pcall(picker.Hide) end
        local ok, shown = pcall(legend.Toggle, panel)
        if ok then
            self._open = shown
            self:SetAlpha(shown and 1 or 0.68)
            self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3],
                self._hovered and .18 or shown and .12 or 0)
        end
    end)
    panel.legend:SetScript("OnEnter", function(self)
        self._hovered = true
        self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .18)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Radar legend", 1, 1, 1)
        GameTooltip:AddLine("See live detections, saved map notes, quests, pins, routes, and trail symbols. Filter or spotlight live types here.",
            0.65, 0.80, 0.77, true)
        GameTooltip:AddLine("Right-click for the colored quest key on the left.", .65, .8, .77, true)
        GameTooltip:Show()
    end)
    panel.legend:SetScript("OnLeave", function(self)
        self._hovered = false
        self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], self._open and .12 or 0)
        if GameTooltip then GameTooltip:Hide() end
    end)

    panel.minimize = CreateFrame("Button", nil, panel)
    panel.minimize:SetSize(24, 24)
    panel.minimize.line = panel.minimize:CreateTexture(nil, "OVERLAY")
    panel.minimize.line:SetSize(9, 2)
    panel.minimize.line:SetPoint("CENTER")
    panel.minimize.line:SetColorTexture(0.68, 0.72, 0.74, 0.86)
    panel.minimize.glow = panel.minimize:CreateTexture(nil, "BACKGROUND")
    panel.minimize.glow:SetSize(18, 18)
    panel.minimize.glow:SetPoint("CENTER")
    panel.minimize.glow:SetTexture(CIRCLE_TEXTURE)
    panel.minimize.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0)
    panel.minimize:SetScript("OnClick", function()
        if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Hide() end
        ToggleRadarPanel()
    end)
    panel.minimize:SetScript("OnEnter", function(self)
        self._hovered = true
        self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .18)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Minimize to launcher", 1, 1, 1)
        GameTooltip:AddLine("Keep detection active in the live mini radar.", .72, .76, .78, true)
        GameTooltip:Show()
    end)
    panel.minimize:SetScript("OnLeave", function(self)
        self._hovered = false
        self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0)
        if GameTooltip then GameTooltip:Hide() end
    end)

    panel.close = CreateFrame("Button", nil, panel)
    panel.close:SetSize(24, 24)
    panel.close:SetPoint("TOPRIGHT", -5, -5)
    panel.close.label = Text(panel.close, 16, "×")
    panel.close.label:SetAllPoints()
    panel.close.label:SetJustifyH("CENTER")
    panel.close.glow = panel.close:CreateTexture(nil, "BACKGROUND")
    panel.close.glow:SetSize(18, 18)
    panel.close.glow:SetPoint("CENTER")
    panel.close.glow:SetTexture(CIRCLE_TEXTURE)
    panel.close.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0)
    panel.close:SetScript("OnClick", function()
        if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Hide() end
        if HideTrailPopup then HideTrailPopup() end
        if routeMenu.Hide then routeMenu.Hide() end
        local legend = LegendAPI()
        if legend and legend.Hide then pcall(legend.Hide) end
        if legend and legend.HideQuest then pcall(legend.HideQuest) end
        local picker = TargetPickerAPI()
        if picker and picker.Hide then pcall(picker.Hide) end
        addon.SetVignetteRadarEnabled(false)
    end)
    panel.close:SetScript("OnEnter", function(self)
        self._hovered = true
        self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .18)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Turn radar off", 1, 1, 1)
        GameTooltip:AddLine("Stops detection until you click the launcher again.",
            0.72, 0.76, 0.78, true)
        GameTooltip:Show()
    end)
    panel.close:SetScript("OnLeave", function(self)
        self._hovered = false
        self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0)
        if GameTooltip then GameTooltip:Hide() end
    end)

    panel.field = CreateFrame("Frame", nil, panel)
    panel.field:SetSize(FIELD_SIZE, FIELD_SIZE)
    panel.field:SetPoint("BOTTOM", 0, 9 + ZOOM_FOOTER_H)
    panel.field:EnableMouseWheel(true)
    panel.field:SetScript("OnMouseWheel", OnZoomWheel)
    panel.field:EnableMouse(true)
    panel.field:RegisterForDrag("LeftButton")
    panel.field:SetScript("OnDragStart", function()
        if CircleOnly() then
            panel.field._dragged = true
            panel:StartMoving()
        end
    end)
    panel.field:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); SavePosition() end)
    panel.field:SetScript("OnMouseUp", function(self, button)
        local dragged = self._dragged
        self._dragged = nil
        if button == "LeftButton" and not dragged and panel.hoverQuestID then
            local exploration = addon.VignetteRadarExploration
            if exploration then exploration.FocusQuest(panel.hoverQuestID) end
        end
    end)
    panel.field:SetFrameLevel(panel:GetFrameLevel() + 1)
    -- Retain the old frame switch internally for profile/API compatibility,
    -- but the finalized rounded view no longer shows an edge chevron.
    panel.frameToggle = CreateFrame("Button", nil, panel)
    panel.frameToggle:SetSize(16, 20)
    panel.frameToggle.glow = panel.frameToggle:CreateTexture(nil, "BACKGROUND")
    panel.frameToggle.glow:SetSize(16, 16)
    panel.frameToggle.glow:SetPoint("CENTER")
    panel.frameToggle.glow:SetTexture(CIRCLE_TEXTURE)
    panel.frameToggle.chevron = {}
    for index = 1, 2 do
        local line = panel.frameToggle:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.8)
        panel.frameToggle.chevron[index] = line
    end
    panel.frameToggle:SetScript("OnClick", function()
        addon.SetVignetteRadarCircleOnly(Settings().vignetteRadarCircleOnly ~= true)
    end)
    panel.frameToggle:Hide()
    panel.field.background = panel.field:CreateTexture(nil, "BACKGROUND")
    panel.field.background:SetAllPoints()
    panel.field.background:SetTexture(CIRCLE_TEXTURE)
    panel.field.background:SetVertexColor(0.015, 0.022, 0.028, 0.94)
    panel.questDots = {}
    panel.mapNotes = {}
    panel.questClip = CreateFrame("Frame", nil, panel.field)
    panel.questClip:SetAllPoints(panel.field)
    panel.questClip:SetFrameLevel(panel.field:GetFrameLevel() + 1)
    panel.questClip:EnableMouse(false)
    if type(panel.questClip.SetClipsChildren) == "function" then
        panel.questClip:SetClipsChildren(true)
        panel.questClip.canClip = true
        local ok, blob = pcall(CreateFrame, "QuestPOIFrame", nil, panel.questClip)
        if ok and blob and type(blob.SetMapID) == "function" and type(blob.DrawBlob) == "function"
            and type(blob.DrawNone) == "function" and type(blob.SetFillTexture) == "function"
            and type(blob.SetBorderTexture) == "function" and type(blob.SetFillAlpha) == "function"
            and type(blob.SetBorderAlpha) == "function" then
            panel.questBlob = blob
            blob:SetFrameLevel(panel.field:GetFrameLevel() + 2)
            blob:EnableMouse(false)
            blob:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
            blob:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
            blob:SetFillAlpha(48)
            blob:SetBorderAlpha(0)
            blob:Hide()
        end
    end
    panel.field.halo = panel.field:CreateTexture(nil, "BACKGROUND", nil, -1)
    panel.field.halo:SetPoint("CENTER")
    panel.field.halo:SetSize(FIELD_SIZE + 4, FIELD_SIZE + 4)
    panel.field.halo:SetTexture(CIRCLE_TEXTURE)
    panel.field.halo:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
    panel.outerRing = AddRing(panel.field, FIELD_RADIUS, 0.02)
    -- One continuous outline avoids tiny native Line segments disappearing at corners.
    panel.squareBorder = panel.field:CreateTexture(nil, "BORDER")
    panel.squareBorder:SetTexture(ROUNDED_BORDER_TEXTURE)
    panel.squareBorder:SetPoint("CENTER", panel.field, "CENTER")
    panel.squareBorder:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .06)
    panel.squareBorder:Hide()
    panel.rangeRing = AddRing(panel.field, PLOT_RADIUS, 0.045)
    panel.middleRing = AddRing(panel.field, PLOT_RADIUS * (2 / 3), .04)
    panel.innerRing = AddRing(panel.field, PLOT_RADIUS / 3, .03)
    panel.activeCue = panel.field:CreateTexture(nil, "ARTWORK")
    panel.activeCue:SetTexture(CIRCLE_TEXTURE)
    panel.activeCue:SetSize(30, 30)
    panel.activeCue:Hide()
    -- A texture cannot own mouse scripts. Its matching hit frame follows the
    -- smoothed cue position while the real quest and vignette buttons stay above it.
    panel.activeCueHit = CreateFrame("Frame", nil, panel.field)
    panel.activeCueHit:SetSize(30, 30)
    panel.activeCueHit:SetPoint("CENTER", panel.activeCue, "CENTER")
    panel.activeCueHit:SetFrameLevel(panel.field:GetFrameLevel() + 2)
    panel.activeCueHit:EnableMouse(true)
    panel.activeCueHit:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.name or "Active Destination", 1, .86, .59)
        local kind = addon.VignetteRadarControls and addon.VignetteRadarControls.TitleCase
            and addon.VignetteRadarControls.TitleCase(self.kind or "Destination")
            or self.kind or "Destination"
        GameTooltip:AddLine(kind .. " · " .. math.floor((self.distance or 0) + .5) .. " yd",
            .68, .84, .81)
        if self.routeName then
            local step = self.routeIndex and self.routeCount
                and (" · Step " .. self.routeIndex .. "/" .. self.routeCount) or ""
            GameTooltip:AddLine(self.routeName .. step, .57, .73, .72)
        end
        GameTooltip:Show()
    end)
    panel.activeCueHit:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    panel.activeCueHit:SetScript("OnHide", function(self)
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)
    panel.activeCueHit:Hide()
    panel.sweepLines = {}
    for index = 1, 2 do
        local line = panel.field:CreateLine(nil, "BORDER")
        line:SetThickness(index == 1 and 1.5 or 1)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], index == 1 and .17 or .07)
        line:Hide()
        panel.sweepLines[index] = line
    end

    panel.innerLabel = Text(panel.field, 8, "150y")
    panel.innerLabel:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3],
        .03 * Settings().vignetteRadarRangeLabelOpacity)
    panel.innerLabel:SetPoint("CENTER", 0, -(PLOT_RADIUS / 3))
    panel.outerLabel = Text(panel.field, 8, "300y")
    panel.outerLabel:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3],
        .04 * Settings().vignetteRadarRangeLabelOpacity)
    panel.outerLabel:SetPoint("CENTER", 0, -(PLOT_RADIUS * 2 / 3))

    panel.cardinals = {}
    for index, definition in ipairs(CARDINALS) do
        local label = Text(panel.field, 9, definition.text)
        label:SetTextColor(0.65, 0.69, 0.71, 0.82)
        label:SetJustifyH("CENTER")
        panel.cardinals[index] = label
    end
    panel.direction = panel.field:CreateLine(nil, "OVERLAY")
    panel.direction:SetThickness(2.5)
    local tip, outer = HeadingGeometry(PLOT_RADIUS)
    DrawPlayerHeading(panel.direction, panel.field, 0, tip, outer)
    panel.direction:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.46)
    panel.headingChevron = {}
    for index = 1, 2 do
        local line = panel.field:CreateLine(nil, "OVERLAY")
        line:SetThickness(2.25)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.72)
        panel.headingChevron[index] = line
    end
    DrawPlayerChevron(panel.headingChevron, panel.field, 0)
    panel.playerGlow = panel.field:CreateTexture(nil, "OVERLAY")
    panel.playerGlow:SetSize(14, 14)
    panel.playerGlow:SetPoint("CENTER")
    panel.playerGlow:SetTexture(CIRCLE_TEXTURE)
    panel.playerGlow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
    panel.player = panel.field:CreateTexture(nil, "OVERLAY", nil, 1)
    panel.player:SetSize(7, 7)
    panel.player:SetPoint("CENTER")
    panel.player:SetTexture(CIRCLE_TEXTURE)
    panel.player:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    panel.blips, panel.freeBlips, panel.blipByKey = {}, {}, {}

    panel.focusDivider = panel:CreateTexture(nil, "ARTWORK")
    panel.focusDivider:SetSize(PANEL_W - 24, 1)
    panel.focusDivider:SetPoint("BOTTOM", 0, 46 + ZOOM_FOOTER_H)
    panel.focusDivider:SetColorTexture(1, 1, 1, 0.12)
    panel.focusDivider:Hide()
    panel.focusReadout = CreateFrame("Button", nil, panel)
    panel.focusReadout:SetSize(PANEL_W - 24, 32)
    panel.focusReadout:SetPoint("BOTTOMLEFT", 12, 8 + ZOOM_FOOTER_H)
    panel.focusReadout:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.focusReadout:SetScript("OnEnter", Tooltip)
    panel.focusReadout:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.focusReadout:SetScript("OnClick", function(self, button) addon.HandleVignetteClick(self.target, button) end)
    panel.focusArrow = CreateFrame("Frame", nil, panel.focusReadout)
    panel.focusArrow:SetSize(16, 16)
    panel.focusArrow:SetPoint("LEFT", 0, 0)
    panel.focusName = Text(panel.focusReadout, 10, "")
    panel.focusName:SetPoint("TOPLEFT", 24, -1)
    panel.focusName:SetSize(172, 13)
    panel.focusMeta = Text(panel.focusReadout, 9, "")
    panel.focusMeta:SetPoint("BOTTOMLEFT", 24, 1)
    panel.focusMeta:SetSize(172, 12)
    panel.focusReadout:Hide()
    panel.focusCard = CreateFrame("Frame", "VignetteRadarFocusCard", panel)
    panel.focusCard:SetSize(185, 76)
    panel.focusCard:SetFrameLevel(panel:GetFrameLevel() + 20)
    panel.focusCard:SetClampedToScreen(true)
    panel.focusCard:EnableMouse(true)
    panel.focusCard:SetPoint("TOPLEFT", panel.field, "TOPRIGHT", 8, -16)
    addon.VignetteRadarControls.RoundedStatusSurface(panel.focusCard)
    panel.focusCard.name = Text(panel.focusCard, 10, "")
    panel.focusCard.name:SetPoint("TOPLEFT", 12, -11)
    panel.focusCard.name:SetWidth(161)
    panel.focusCard.detail = Text(panel.focusCard, 9, "")
    panel.focusCard.detail:SetPoint("TOPLEFT", 12, -32)
    panel.focusCard.detail:SetWidth(161)
    panel.focusCard.showAll = addon.VignetteRadarIconButton.Create(panel.focusCard, "eye",
        { size = 20, label = "Show All", tooltip = "Clear the focus and show every point again." })
    panel.focusCard.showAll:SetPoint("BOTTOMRIGHT", -9, 6)
    panel.focusCard.showAll:SetScript("OnClick", function()
        local picker = TargetPickerAPI()
        if picker and picker.ClearFocus then picker.ClearFocus() end
    end)
    panel.focusCard:Hide()
    panel.edgeArrow = CreateFrame("Button", nil, panel.field)
    panel.edgeArrow:SetSize(14, 14)
    panel.edgeArrow:SetFrameLevel(panel.field:GetFrameLevel() + 5)
    panel.edgeArrow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    panel.edgeArrow:SetScript("OnEnter", Tooltip)
    panel.edgeArrow:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.edgeArrow:SetScript("OnClick", function(self, button) addon.HandleVignetteClick(self.target, button) end)
    panel.edgeArrow:Hide()

    panel.zoomLabel = Text(panel, 10, "450 yd")
    panel.zoomLabel:SetPoint("BOTTOM", 0, 10)
    panel.zoomLabel:SetSize(110, 12)
    panel.zoomLabel:SetJustifyH("CENTER")
    local function ToolbarIcon(symbol, width)
        local button = CreateFrame("Button", nil, panel)
        button:SetSize(width, 20)
        -- Keep navigation controls legible when the radar surface is dimmed.
        if type(button.SetIgnoreParentAlpha) == "function" then
            button:SetIgnoreParentAlpha(true)
        end
        button.glow = button:CreateTexture(nil, "BACKGROUND")
        button.glow:SetSize(18, 18)
        button.glow:SetPoint("CENTER")
        button.glow:SetTexture(CIRCLE_TEXTURE)
        button.strokes = {}
        if symbol == "N" or symbol == "declutter" then
            button.label = Text(button, 13, symbol == "N" and "N" or "C")
            button.label:SetAllPoints()
            button.label:SetJustifyH("CENTER")
            button:SetFontString(button.label)
            button:SetText(symbol == "N" and "N" or "C")
        elseif symbol == "route" then
            button.glow:Hide()
            button.art = button:CreateTexture(nil, "OVERLAY")
            button.art:SetTexture("Interface\\AddOns\\Magpie\\Media\\radar-corner-controls.tga")
            button.art:SetSize(22, 22)
            button.art:SetPoint("CENTER")
        elseif symbol == "arrow" then
            button.glow:Hide()
            button._directArt = true
            button.art = button:CreateTexture(nil, "OVERLAY")
            button.art:SetTexture("Interface\\AddOns\\Magpie\\Media\\route-crystal-pointer.tga")
            button.art:SetSize(16, 16)
            button.art:SetPoint("CENTER")
        elseif symbol == "trail" then
            button.trailMarks, button.trailExtras = {}, {}
            for index = 1, 3 do
                local stroke = button:CreateLine(nil, "OVERLAY")
                stroke:SetThickness(1.7)
                stroke:SetStartPoint("CENTER", button, (index - 2) * 5 - 2, 0)
                stroke:SetEndPoint("CENTER", button, (index - 2) * 5 + 2, 0)
                button.strokes[#button.strokes + 1] = stroke
                button.trailMarks[index] = stroke
                button.trailExtras[index] = {}
                for part = 1, 3 do
                    local extra = button:CreateLine(nil, "OVERLAY")
                    extra:Hide()
                    button.trailExtras[index][part] = extra
                    button.strokes[#button.strokes + 1] = extra
                end
            end
        else
            local horizontal = button:CreateLine(nil, "OVERLAY")
            horizontal:SetThickness(2)
            horizontal:SetStartPoint("CENTER", button, -5, 0)
            horizontal:SetEndPoint("CENTER", button, 5, 0)
            button.strokes[1] = horizontal
            if symbol == "+" then
                local vertical = button:CreateLine(nil, "OVERLAY")
                vertical:SetThickness(2)
                vertical:SetStartPoint("CENTER", button, 0, -5)
                vertical:SetEndPoint("CENTER", button, 0, 5)
                button.strokes[2] = vertical
            end
        end
        button._enabled = true
        function button:RefreshAppearance()
            local enabled, hovered = self._enabled, self._hovered
            local selected = self._selected == true or self._popupOpen == true
            local r, g, b = .69, .77, .78
            if selected or hovered then r, g, b = ACCENT[1], ACCENT[2], ACCENT[3] end
            local opacity = not enabled and .32 or (hovered or selected) and 1 or .78
            if self.art then
                local state = (selected and 2 or 0) + (hovered and 1 or 0)
                if not self._directArt then
                    self.art:SetTexCoord((10 * 64 + 1) / 1024, (10 * 64 + 63) / 1024,
                        (state * 64 + 1) / 256, (state * 64 + 63) / 256)
                end
                self.art:SetVertexColor(r, g, b, enabled and 1 or .38)
            else
                self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3],
                    not enabled and 0 or hovered and .20 or selected and .12 or 0)
                for _, stroke in ipairs(self.strokes) do stroke:SetColorTexture(r, g, b, opacity) end
                if self.label then self.label:SetTextColor(r, g, b, opacity) end
            end
        end
        local nativeSetEnabled = button.SetEnabled
        button.SetEnabled = function(self, enabled)
            enabled = enabled == true or enabled == 1
            if self._enabled == enabled then return end
            nativeSetEnabled(self, enabled)
            self._enabled = enabled
            if not enabled then self._hovered = false end
            self:RefreshAppearance()
        end
        button:SetScript("OnEnter", function(self) self._hovered = true; self:RefreshAppearance() end)
        button:SetScript("OnLeave", function(self) self._hovered = false; self:RefreshAppearance() end)
        button:SetScript("OnHide", function(self) self._hovered = false; self:RefreshAppearance() end)
        button:RefreshAppearance()
        return button
    end
    local function ZoomButton(symbol, right, step, title)
        local button = ToolbarIcon(symbol, 22)
        button:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", panel, right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -12 or 12, 6)
        button:SetScript("OnClick", function() StepRange(step) end)
        button:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine("Range is the distance from you to the outer range ring. You can also use the mouse wheel.", 0.7, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        return button
    end
    panel.zoomOut = ZoomButton("-", false, 1, "Zoom out: show a wider area")
    panel.zoomIn = ZoomButton("+", true, -1, "Zoom in: show nearby detail")
    panel.clearToggle = ToolbarIcon("declutter", 18)
    panel.clearToggle._selected = Settings().vignetteRadarKeepCenterClear == true
    panel.clearToggle:SetScript("OnClick", function(self)
        Settings().vignetteRadarKeepCenterClear = not Settings().vignetteRadarKeepCenterClear
        self._selected = Settings().vignetteRadarKeepCenterClear
        self:RefreshAppearance()
        if panel then
            panel._layerRange = nil
            panel._questKeyNextAt = nil
        end
        RefreshRadar(false)
    end)
    panel.clearToggle:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Keep Center Clear", 1, 1, 1)
        GameTooltip:AddLine("Hide markers near your character. The cutoff follows radar zoom.",
            .7, .8, .8, true)
        GameTooltip:AddLine("When you focus a marker or quest, show only that focus and its quest area.",
            .6, .84, .77, true)
        GameTooltip:AddLine(Settings().vignetteRadarKeepCenterClear and "On" or "Off",
            .85, .9, .9)
        GameTooltip:Show()
    end)
    panel.clearToggle:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    panel.clearToggle:RefreshAppearance()
    panel.compass = ToolbarIcon("N", 24)
    panel.compass:SetScript("OnClick", function()
        addon.SetVignetteRadarNorthUp(Settings().vignetteRadarNorthUp ~= true)
    end)
    panel.compass:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        local northUp = Settings().vignetteRadarNorthUp == true
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(northUp and "North up" or "Facing up", 1, 1, 1)
        GameTooltip:AddLine(northUp and "North stays at the top. Your direction line turns as you turn."
            or "The radar turns with you. Your direction line points up.", 0.7, 0.8, 0.8, true)
        GameTooltip:AddLine(northUp and "Click to follow your facing." or "Click to keep north at the top.",
            0.55, 0.86, 0.76, true)
        GameTooltip:Show()
    end)
    panel.compass:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    routeMenu.SetupButtons(panel, ToolbarIcon)
    panel.arrowToggle = ToolbarIcon("arrow", 18)
    panel.arrowToggle:SetScript("OnClick", function(self)
        -- The Guide Panel switch (Core/Schema.lua writes, validates and refreshes it).
        local wanted = Settings().vignetteRadarGuidePanel ~= true
        if addon.Schema then addon.Schema.Set("vignetteRadarGuidePanel", wanted)
        else Settings().vignetteRadarGuidePanel = wanted; addon.InvalidateSettings() end
        self._selected = Settings().vignetteRadarGuidePanel
        self:RefreshAppearance()
        if addon.VignetteRadarGuidePanel then addon.VignetteRadarGuidePanel.Refresh() end
        if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Refresh() end
        if panel.RefreshCornerTools then panel.RefreshCornerTools() end
    end)
    panel.arrowToggle:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Guide Panel: " .. (Settings().vignetteRadarGuidePanel and "On" or "Off"), 1, 1, 1)
        GameTooltip:AddLine("Show or hide the panel with your target's direction, distance, next stops and what to do there.",
            .7, .8, .8, true)
        GameTooltip:Show()
    end)
    panel.arrowToggle:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.arrowToggle._selected = Settings().vignetteRadarGuidePanel == true
    panel.arrowToggle:RefreshAppearance()

    panel.combatToggle = CreateFrame("Button", nil, panel)
    panel.combatToggle:SetSize(18, 18)
    if type(panel.combatToggle.SetIgnoreParentAlpha) == "function" then
        panel.combatToggle:SetIgnoreParentAlpha(true)
    end
    panel.combatToggle.glow = panel.combatToggle:CreateTexture(nil, "BACKGROUND")
    panel.combatToggle.glow:SetSize(18, 18)
    panel.combatToggle.glow:SetPoint("CENTER")
    panel.combatToggle.glow:SetTexture(CIRCLE_TEXTURE)
    panel.combatToggle.eye = {}
    for index, points in ipairs({
        { -6, 0, 0, 3 }, { 0, 3, 6, 0 }, { -6, 0, 0, -3 }, { 0, -3, 6, 0 },
    }) do
        local line = panel.combatToggle:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.5)
        line:SetStartPoint("CENTER", panel.combatToggle, points[1], points[2])
        line:SetEndPoint("CENTER", panel.combatToggle, points[3], points[4])
        panel.combatToggle.eye[index] = line
    end
    panel.combatToggle.pupil = panel.combatToggle:CreateTexture(nil, "OVERLAY")
    panel.combatToggle.pupil:SetSize(3, 3)
    panel.combatToggle.pupil:SetPoint("CENTER")
    panel.combatToggle.pupil:SetTexture(CIRCLE_TEXTURE)
    panel.combatToggle:SetScript("OnClick", function()
        addon.SetVignetteRadarKeepVisibleCombat(Settings().vignetteRadarKeepVisibleCombat ~= true)
    end)
    panel.combatToggle:SetScript("OnEnter", function(self)
        self._hovered = true
        UpdateCombatToggle()
        if not GameTooltip then return end
        local enabled = Settings().vignetteRadarKeepVisibleCombat == true
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(enabled and "Stay fully visible: ON" or "Stay fully visible: OFF", 1, 1, 1)
        GameTooltip:AddLine(enabled and "Click to allow automatic fading and hiding again."
            or "Click to prevent automatic fading and hiding.", .7, .8, .8, true)
        GameTooltip:AddLine("Keeps the radar open when zone data is empty or unavailable.", .7, .8, .8, true)
        GameTooltip:AddLine("Alert muting stays separate.", .55, .7, .68, true)
        GameTooltip:Show()
    end)
    panel.combatToggle:SetScript("OnLeave", function(self)
        self._hovered = false
        UpdateCombatToggle()
        if GameTooltip then GameTooltip:Hide() end
    end)
    UpdateCombatToggle()

    -- The square face leaves four useful corner wedges beyond the plotting ring.
    -- One atlas texture replaces the old glow, line, and font stacks.
    panel.hoverTools = {}
    panel.RefreshCornerTools = function()
        if not (panel and panel.hoverTools) then return end
        local settings = Settings()
        local quick = addon.VignetteRadarQuickConfig
        local legend = LegendAPI()
        local focused = FocusedTargetKey()
        local trackedKind = panel.routeToggle and panel.routeToggle._trackingKind
        for _, tool in ipairs(panel.hoverTools) do
            local id = tool.toolID
            local active = id == "north" and settings.vignetteRadarNorthUp == true
                or id == "constellation" and settings.vignetteRadarConstellationEnabled == true
                or id == "tracker" and addon.VignetteRadarQuestTracker
                    and addon.VignetteRadarQuestTracker.IsExpanded()
                or id == "trail" and settings.vignetteRadarBreadcrumbs == true
                or id == "route" and addon.VignetteRadarWorldFocus
                    and addon.VignetteRadarWorldFocus.IsRouteActive()
                or id == "arrow" and settings.vignetteRadarGuidePanel == true
                or id == "clear" and settings.vignetteRadarKeepCenterClear == true
                or id == "eye" and settings.vignetteRadarKeepVisibleCombat == true
                or id == "player" and addon.VignetteRadarPlayerTracker
                    and type(addon.VignetteRadarPlayerTracker.IsDetecting) == "function"
                    and addon.VignetteRadarPlayerTracker.IsDetecting()
                or id == "target" and focused ~= nil
                or id == "config" and quick and quick.IsShown and quick.IsShown()
                or id == "legend" and legend and
                    ((legend.IsShown and legend.IsShown()) or (legend.IsQuestShown and legend.IsQuestShown()))
            local state = (active and 2 or 0) + (tool._hovered and 1 or 0)
            -- Layered tools (UI/IconButton.lua) take each layer from its own icon role.
            if tool.iconLayers then
                addon.VignetteRadarIconButton.Paint(tool, active, tool._hovered)
            elseif state ~= tool._artState then
                local column = tool.artColumn
                tool.art:SetTexCoord((column * 64 + 1) / 1024, (column * 64 + 63) / 1024,
                    (state * 64 + 1) / 256, (state * 64 + 63) / 256)
                tool._artState = state
            end
            if id == "route" and tool.trackingIcon then
                if tool._trackingKind ~= trackedKind or tool._trackingState ~= state then
                    tool._trackingKind = trackedKind
                    tool._trackingState = state
                    if trackedKind then
                        routeMenu.SetTrackedRouteTexture(tool.trackingIcon, trackedKind, state)
                    end
                end
                tool.art:SetShown(trackedKind == nil)
                if not tool.iconLayers then tool.art:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1) end
                tool.trackingIcon:SetShown(trackedKind ~= nil)
                if trackedKind then
                    local r, g, b = routeMenu.TrackedRouteColor(trackedKind)
                    tool.trackingIcon:SetVertexColor(r, g, b, active and 1 or .75)
                end
            elseif not tool.iconLayers and (tool._artRed ~= ACCENT[1] or tool._artGreen ~= ACCENT[2]
                or tool._artBlue ~= ACCENT[3]) then
                tool.art:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
                tool._artRed, tool._artGreen, tool._artBlue = ACCENT[1], ACCENT[2], ACCENT[3]
            end
            tool:SetAlpha(tool.reference and tool.reference._enabled == false and .38 or 1)
        end
    end
    local function HoverTool(id, title, reference, point, x, y)
        local tool = CreateFrame("Button", nil, panel.field)
        tool:SetSize(16, 16)
        tool:SetFrameLevel(panel.field:GetFrameLevel() + 8)
        tool:SetPoint(point, panel.field, point, x, y)
        if id == "route" then
            tool:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        else
            tool:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        tool.toolID, tool.reference = id, reference
        tool.advancedTool = id == "player"
        tool.artColumn = ({ config = 0, target = 1, legend = 2, minus = 3,
            plus = 4, north = 5, trail = 6, eye = 7, player = 8, close = 9,
            route = 10, tracker = 11, clear = 12, arrow = 13,
            minimize = 14, constellation = 15 })[id]
        local icons = addon.VignetteRadarIconButton
        if icons and tool.artColumn and icons.HasIcon("corner_" .. id) then
            icons.AddLayers(tool, "corner_" .. id, 18)
        else
            tool.art = tool:CreateTexture(nil, "ARTWORK")
            tool.art:SetTexture("Interface\\AddOns\\Magpie\\Media\\radar-corner-controls.tga")
            tool.art:SetSize(18, 18)
            tool.art:SetPoint("CENTER")
        end
        if id == "route" then
            tool.trackingIcon = tool:CreateTexture(nil, "OVERLAY")
            tool.trackingIcon:SetSize(18, 18)
            tool.trackingIcon:SetPoint("CENTER")
            tool.trackingIcon:Hide()
        end
        tool:SetScript("OnEnter", function(self)
            panel._hoverToolsShown = true
            self._hovered = true
            panel.RefreshCornerTools()
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(title, 1, 1, 1)
                if id == "route" then
                    local bridge = addon.VignetteRadarZygor
                    if bridge and bridge.IsPaused and bridge.IsPaused() then
                        GameTooltip:AddLine("Middle-click to resume Zygor Follow.", .55, .86, .76, true)
                    end
                end
                GameTooltip:Show()
            end
        end)
        tool:SetScript("OnLeave", function(self)
            self._hovered = false
            panel.RefreshCornerTools()
            if GameTooltip then GameTooltip:Hide() end
            if C_Timer and C_Timer.After then C_Timer.After(0, function()
                if panel.field.IsMouseOver and not panel.field:IsMouseOver() then
                    panel._hoverToolsShown = false
                    UpdatePanelChrome()
                end
            end) end
        end)
        -- A tool hidden under the cursor (corner fade, Button Tray sliding in)
        -- must not keep its hover light.
        tool:SetScript("OnHide", function(self)
            if self._hovered then
                self._hovered = false
                panel.RefreshCornerTools()
            end
        end)
        -- The tray treats its own toggle as a click inside, not a click away.
        if (id == "tracker" or id == "legend") and addon.VignetteRadarTray then
            addon.VignetteRadarTray.RegisterToggle(tool)
        end
        tool:SetScript("OnClick", function(self, button)
            if id == "tracker" then
                local tracker = addon.VignetteRadarQuestTracker
                if tracker then tracker.ToggleTray() end
                panel.RefreshCornerTools()
                return
            end
            if id == "constellation" then
                local constellation = addon.VignetteRadarConstellation
                if constellation then
                    if button == "RightButton" then constellation.ToggleMenu(self)
                    else constellation.Toggle() end
                end
                panel.RefreshCornerTools()
                return
            end
            if id == "player" then
                local tracker = addon.VignetteRadarPlayerTracker
                if tracker then
                    if button == "RightButton" then
                        local ok, reason = tracker.MarkTarget()
                        if not ok and UIErrorsFrame and UIErrorsFrame.AddMessage then
                            UIErrorsFrame:AddMessage(reason, 1, .55, .45)
                        end
                    else tracker.Open() end
                end
                panel.RefreshCornerTools()
                return
            end
            local click = reference and reference:GetScript("OnClick")
            if click then
                if id == "trail" then panel._trailPopupAnchor = self end
                if id == "route" then panel._routePopupAnchor = self end
                click(reference, button)
                panel._trailPopupAnchor = nil
                panel._routePopupAnchor = nil
            end
            panel.RefreshCornerTools()
        end)
        tool:Hide()
        panel.hoverTools[#panel.hoverTools + 1] = tool
    end
    HoverTool("config", "Quick Settings", panel.settingsDot, "TOPLEFT", 12, -12)
    HoverTool("target", "Choose A Target", panel.target, "TOPLEFT", 32, -12)
    HoverTool("legend", "Radar Legend · Right-Click For Quest Key",
        panel.legend, "TOPLEFT", 12, -32)
    HoverTool("tracker", "Quest Tracker · Slide Out Or In", nil, "TOPLEFT", 32, -32)
    HoverTool("minus", "Zoom Out", panel.zoomOut, "TOPRIGHT", -12, -12)
    HoverTool("plus", "Zoom In", panel.zoomIn, "TOPRIGHT", -32, -12)
    HoverTool("north", "North Up / Facing Up", panel.compass, "TOPRIGHT", -12, -32)
    HoverTool("constellation", "Constellation HUD · Right-Click For Views",
        nil, "TOPRIGHT", -32, -32)
    HoverTool("eye", "Stay Fully Visible", panel.combatToggle, "BOTTOMLEFT", 12, 12)
    HoverTool("clear", "Keep Center Clear", panel.clearToggle, "BOTTOMLEFT", 32, 12)
    HoverTool("trail", "Trail · Left-Click To Toggle, Right-Click For Style",
        panel.trailToggle, "BOTTOMLEFT", 12, 32)
    HoverTool("player", "Player Tracker · Right-Click To Mark Current Target",
        nil, "BOTTOMLEFT", 32, 32)
    HoverTool("route", "Auto Route · Click To Toggle, Right-Click To Choose",
        panel.routeToggle, "BOTTOMRIGHT", -12, 32)
    HoverTool("arrow", "Mini Route Arrow · Show Or Hide", panel.arrowToggle,
        "BOTTOMRIGHT", -32, 32)
    for _, tool in ipairs(panel.hoverTools) do
        if tool.toolID == "route" then
            tool:HookScript("OnEnter", function(self) routeMenu.ShowGuideStrip(self) end)
            tool:HookScript("OnLeave", function(self)
                if C_Timer and C_Timer.After then C_Timer.After(.4, function()
                    local strip = routeMenu.guideStrip
                    if strip and strip:IsShown() and not strip:IsMouseOver()
                        and not self:IsMouseOver() then strip:Hide() end
                end) end
            end)
            break
        end
    end
    HoverTool("minimize", "Minimize To Launcher", panel.minimize,
        "BOTTOMRIGHT", -32, 12)
    -- The bottom-right outer slot belongs to the Minimap Underlay toggle
    -- (UI/MinimapUnderlay.lua); Minimize, /vr and the keybind turn the radar off.
    panel.RefreshCornerTools()
    -- A switch flipped from the settings window (North Up, Trail, Guide
    -- Panel, ...) repaints the tools' selected state right away, also for
    -- entries that skip the radar refresh. Paint is cached, so this is cheap.
    if addon.Schema and addon.Schema.OnChange and not panel._cornerToolsListening then
        panel._cornerToolsListening = true
        addon.Schema.OnChange(function()
            if panel.RefreshCornerTools then panel.RefreshCornerTools() end
        end)
    end
    panel.field:SetScript("OnEnter", function()
        panel._hoverToolsShown = true
        UpdatePanelChrome()
    end)
    panel.field:SetScript("OnLeave", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, function()
            if panel.field.IsMouseOver and not panel.field:IsMouseOver() then
                panel._hoverToolsShown = false
                UpdatePanelChrome()
            end
        end) end
    end)

    AddResizeGrips()

    panel:SetScript("OnUpdate", function(self, elapsed)
        local started = ProfileTime()
        local settings = Settings()
        local turn = addon.VignetteRadarTurn
        self._turnElapsed = (self._turnElapsed or 0) + elapsed
        if self._turnElapsed >= turn.Interval(self, addon.VignetteRadarBudget
            and addon.VignetteRadarBudget.softThrottle) then
            local turnElapsed = self._turnElapsed
            self._turnElapsed = 0
            if not preview and settings.vignetteRadarEnabled
                and type(GetPlayerFacing) == "function" then
                local ok, facing = pcall(GetPlayerFacing)
                facing = ok and SafeNumber(facing) or nil
                if facing then
                    if settings.vignetteRadarNorthUp then
                        local tip, outer = HeadingGeometry(self.plotRadius)
                        DrawPlayerHeading(self.direction, self.field, facing, tip, outer)
                        DrawPlayerChevron(self.headingChevron, self.field, facing)
                    end
                    turn.UpdateRadar(self, ViewFacing(facing), turnElapsed)
                end
            end
        end
        self._renderElapsed = (self._renderElapsed or 0) + elapsed
        self._scanElapsed = (self._scanElapsed or 0) + elapsed
        if not preview and settings.vignetteRadarEnabled == true
            and settings.vignetteRadarBreadcrumbs == true
            and settings.vignetteRadarTrailLifetime <= 5 and activeMapID
            and addon.VignetteRadarExploration then
            self._shortTrailElapsed = (self._shortTrailElapsed or 0) + elapsed
            if self._shortTrailElapsed >= .25 then
                self._shortTrailElapsed = 0
                addon.VignetteRadarExploration.UpdateTrail(PlayerSnapshot(activeMapID), activeMapID, Now())
            end
        else
            self._shortTrailElapsed = 0
        end
        self._questTooltipElapsed = (self._questTooltipElapsed or 0) + elapsed
        if self._questTooltipElapsed >= .15 then
            self._questTooltipElapsed = 0
            local tooltipOwner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
            if (self.field and self.field.IsMouseOver and self.field:IsMouseOver())
                or (self.questBlob and self.questBlob.IsMouseOver
                    and self.questBlob:IsMouseOver())
                or tooltipOwner == self.field or tooltipOwner == self.questBlob then
                UpdateQuestAreaTooltip()
            end
        end
        if self._scanElapsed >= addon.VignetteRadarScanSeconds(settings) then
            self._scanElapsed = 0
            RefreshRadar(true)
            if not self:IsShown() then
                CheckUpdateBudget(self, started, "radar")
                return
            end
        end
        if self._renderElapsed >= addon.VignetteRadarRenderSeconds(settings) then
            local renderElapsed = self._renderElapsed
            self._renderElapsed = 0
            local layerBudget = addon.VignetteRadarLayerBudget
            local renderToken = layerBudget and layerBudget.Begin("render")
            if not layerBudget or renderToken then
                UpdateFullSweep(renderElapsed)
                Render()
                if renderToken then layerBudget.Finish(renderToken) end
            end
        end
        CheckUpdateBudget(self, started, "radar")
    end)
    panel:SetScript("OnHide", function()
        HideTrailPopup()
        routeMenu.Hide()
        ReleaseAllBlips()
        HideQuestDots()
        HideMapNotes()
        HideQuestAreas()
        panel.legend:SetAlpha(0.68)
        UpdateTargetButton()
        local legend = LegendAPI()
        if legend and type(legend.Hide) == "function" then pcall(legend.Hide) end
        if legend and type(legend.HideQuest) == "function" then pcall(legend.HideQuest) end
        local picker = TargetPickerAPI()
        if picker and type(picker.Hide) == "function" then pcall(picker.Hide) end
    end)
    ApplyPanelLayout(false)
    -- A newly constructed hidden frame can have no geometry yet. Always
    -- restore and clamp the saved anchor explicitly before its first Show().
    local savedX = type(position) == "table" and SafeNumber(tonumber(position.x)) or 30
    local savedY = type(position) == "table" and SafeNumber(tonumber(position.y)) or -520
    PlacePanel(savedX, UIParent:GetHeight() + savedY, Settings().vignetteRadarScale or 1)
    RenderCardinals(0)
    UpdateTargetButton()
    return panel
end

function VignetteRadar_PeekRadar(keystate)
    if keystate == "up" then
        if not radarPeekActive then return end
        radarPeekActive = false
        manualPanelState = radarPeekPreviousManual
        radarPeekPreviousManual = nil
        if panel then
            panel:SetClampedToScreen(not CircleOnly())
            if CircleOnly() then ApplyPanelLayout(false) end
            if CircleOnly() and radarPeekPreviousPosition then
                PlacePanel(radarPeekPreviousPosition[1], radarPeekPreviousPosition[2], panel:GetScale())
            end
        end
        radarPeekPreviousPosition = nil
        RefreshRadar(false)
        return
    end
    if keystate ~= "down" or radarPeekActive or Settings().vignetteRadarPeekEnabled ~= true
        or Settings().vignetteRadarEnabled ~= true then return end
    local frame = EnsurePanel()
    local left, top = PanelPosition()
    radarPeekPreviousPosition = left and top and { left, top } or nil
    radarPeekPreviousManual = manualPanelState
    radarPeekActive = true
    manualPanelState = true
    frame:SetClampedToScreen(true)
    local position = Settings().vignetteRadarPosition
    local x = type(position) == "table" and SafeNumber(tonumber(position.x))
    local y = type(position) == "table" and SafeNumber(tonumber(position.y))
    PlacePanel(x or left or 30, y and UIParent:GetHeight() + y or top or 300, frame:GetScale())
    RefreshRadar(false)
end

function VignetteRadar_HoldLens(keystate)
    if keystate == "up" then
        if addon.VignetteRadarLensActive then
            addon.VignetteRadarLensActive = nil
            RefreshRadar(false)
        end
        return
    end
    if keystate ~= "down" or Settings().vignetteRadarLensEnabled ~= true
        or Settings().vignetteRadarEnabled ~= true then return end
    local category = Settings().vignetteRadarLensCategory
    if category ~= "quest" and category ~= "rare" and category ~= "treasure" then return end
    addon.VignetteRadarLensActive = category
    RefreshRadar(false)
end

addon.UpdateAtlasSnapshot = function(mapID, now, changedMap)
    local atlas = addon.VignetteRadarAtlas
    if not (atlas and atlas.IsOpen and atlas.IsOpen())
        or (not changedMap and addon._radarAtlasUpdatedAt
            and now - addon._radarAtlasUpdatedAt < 2) then return end
    local entries = {}
    local points = addon.VignetteRadarPoints
    local targets, quests, notes = points.Refs("live"), points.Refs("quest"), points.Refs("saved")
    for index = 1, math.min(#targets, 128) do
        local target = targets[index]
        entries[#entries + 1] = {
            name = target.name, mapID = target.mapID, mapX = target.mapX,
            mapY = target.mapY, kind = target.category,
            evidence = target.stale and "observed" or "live", targetRef = target,
        }
    end
    for index = 1, math.min(#quests, 128) do
        local quest = quests[index]
        entries[#entries + 1] = {
            name = quest.name, mapID = quest.mapID, mapX = quest.mapX,
            mapY = quest.mapY, kind = "quest", questID = quest.questID,
            evidence = "quest",
        }
    end
    for index = 1, math.min(#notes, 256) do
        local note = notes[index]
        entries[#entries + 1] = {
            name = note.name, mapID = note.mapID, mapX = note.mapX,
            mapY = note.mapY, kind = note.kind, evidence = "saved", noteRef = note,
        }
    end
    atlas.SetData(mapID, entries)
    addon._radarAtlasUpdatedAt = now
end

ScanVignettes = function(mapID)
    local changedMap = activeMapID ~= mapID
    local now = Now()
    local db = Settings()
    -- One position read serves every consumer in this scan; it is returned
    -- so RefreshRadar can reuse it too.
    local player = PlayerSnapshot(mapID)
    if changedMap then questMapBasis = nil end
    if activeMapID ~= mapID or preview or db.vignetteRadarEnabled ~= true then
        pulseUntil, approachPulseKey, approachPulseUntil = 0, nil, nil
    end
    activeMapID = mapID
    addon._rawVignetteTargets = CollectVignettes(mapID, player)
    activeTargets = addon._rawVignetteTargets
    local questCache = addon._focusQuestCache
    local questOptions = tostring(db.vignetteRadarNextQuestStep) .. ":"
        .. tostring(db.vignetteRadarQuestDots) .. ":" .. tostring(db.vignetteRadarQuestAreas)
        .. ":" .. tostring(db.vignetteRadarWorldFocusEnabled) .. ":"
        .. tostring(db.vignetteRadarLearnedQuestHints) .. ":"
        .. tostring(db.vignetteRadarBeaconsEnabled and db.vignetteRadarBeaconQuests)
    if questCache and questCache.mapID == mapID and questCache.options == questOptions
        and now - questCache.at < 5 then
        activeQuests = questCache.quests
    else
        activeQuests = CollectQuests(mapID)
        addon._focusQuestCache = { quests = activeQuests, mapID = mapID,
            options = questOptions, at = now }
    end
    local startsEnabled = db.vignetteRadarQuestStartBadges == true
        or db.vignetteRadarAutoRouteQuestStarts == true
    local startsNow = Now()
    local accountTracking = SafeBoolean(Call(C_Minimap and C_Minimap.IsTrackingAccountCompletedQuests))
    if addon.VignetteRadarStartsMapID ~= mapID
        or addon.VignetteRadarStartsEnabled ~= startsEnabled
        or addon.VignetteRadarStartsBadges ~= db.vignetteRadarQuestStartBadges
        or addon.VignetteRadarStartsAccountTracking ~= accountTracking
        or not addon.VignetteRadarStartsNextAt
        or startsNow >= addon.VignetteRadarStartsNextAt then
        addon.VignetteRadarAvailableStarts = {}
        addon.VignetteRadarStartsMapID = mapID
        addon.VignetteRadarStartsEnabled = startsEnabled
        addon.VignetteRadarStartsBadges = db.vignetteRadarQuestStartBadges
        addon.VignetteRadarStartsAccountTracking = accountTracking
        addon.VignetteRadarStartsNextAt = startsNow + 5
        if mapID and startsEnabled and addon.VignetteRadarQuestData then
            local starts = addon.VignetteRadarQuestData.GetAvailableQuestStarts(mapID)
            for index = 1, math.min(80, #starts) do
                local entry = starts[index]
                local worldX, worldY, instanceID = MapToWorld(mapID, MapVector(entry.x, entry.y))
                if worldX and worldY then
                    entry.worldX, entry.worldY, entry.instanceID = worldX, worldY, instanceID
                    local dx = player and worldX - player.worldX or index
                    local dy = player and worldY - player.worldY or 0
                    entry.startDistanceSquared = dx * dx + dy * dy
                    addon.VignetteRadarAvailableStarts[#addon.VignetteRadarAvailableStarts + 1] = entry
                end
            end
            table.sort(addon.VignetteRadarAvailableStarts, function(left, right)
                return left.startDistanceSquared < right.startDistanceSquared
            end)
            while #addon.VignetteRadarAvailableStarts > 32 do
                table.remove(addon.VignetteRadarAvailableStarts)
            end
        end
    end
    local constellationWantsNotes = db.vignetteRadarEnabled == true
        and db.vignetteRadarConstellationEnabled == true
        and db.vignetteRadarConstellationSourceMode ~= "live"
    local mapNoteDemand = db.vignetteRadarMapNotesVisible == true or constellationWantsNotes
    local source = mapNoteDemand
        and db.vignetteRadarPOISource or "none"
    local fusionSources, fusionKey
    if mapNoteDemand and db.vignetteRadarSourceFusion
        and type(db.vignetteRadarFusionSources) == "table" then
        fusionSources = {}
        for index = 1, math.min(#db.vignetteRadarFusionSources, 8) do
            local id = db.vignetteRadarFusionSources[index]
            if type(id) == "string" and id ~= "" then fusionSources[#fusionSources + 1] = id end
        end
        if #fusionSources > 0 then
            local preferred = type(db.vignetteRadarFusionPreferred) == "table"
                and db.vignetteRadarFusionPreferred[tostring(mapID)] or nil
            fusionKey = "fusion:" .. table.concat(fusionSources, ",") .. ":"
                .. tostring(preferred) .. ":" .. tostring(db.vignetteRadarFusionDistance)
        end
    end
    local sourceKey = fusionKey or source
    if (source == "none" and not fusionKey) or not mapID then
        addon._mapNoteSourceCache = {}
        mapNotesMapID, mapNotesSource, mapNotesUpdatedAt = nil, nil, nil
    elseif mapNotesMapID ~= mapID or mapNotesSource ~= sourceKey
        or not mapNotesUpdatedAt or now - mapNotesUpdatedAt >=
            (db.vignetteRadarPerformance == "low" and 20
                or db.vignetteRadarPerformance == "balanced" and 10 or 5) then
        local pois = addon.VignetteRadarPOIs
        local fusion = addon.VignetteRadarSourceFusion
        if fusionKey and fusion and type(fusion.Collect) == "function" then
            addon._mapNoteSourceCache = fusion.Collect(mapID, fusionSources, MapToWorld, MapVector, {
                preferredSource = type(db.vignetteRadarFusionPreferred) == "table"
                    and db.vignetteRadarFusionPreferred[tostring(mapID)] or nil,
                conflictDistance = db.vignetteRadarFusionDistance,
            })
        else
            local selected, dataMapID
            if pois then selected, dataMapID = pois.ResolveSource(mapID, source) end
            addon._mapNoteSourceCache = selected
                and pois.Collect(dataMapID, selected, MapToWorld, MapVector) or {}
        end
        mapNotesMapID, mapNotesSource, mapNotesUpdatedAt = mapID, sourceKey, now
    end
    activeMapNotes = {}
    for _, note in ipairs(addon._mapNoteSourceCache or {}) do
        if note.kind ~= "guide" then activeMapNotes[#activeMapNotes + 1] = note end
    end
    local worldFocus = addon.VignetteRadarWorldFocus
    if worldFocus and mapID then
        local guide = worldFocus.ZygorNote(mapID, MapToWorld, MapVector)
        if guide then activeMapNotes[#activeMapNotes + 1] = guide end
    end
    -- Blizzard's events, delves and races join as notes (Data/AreaPOIs.lua).
    if addon.VignetteRadarAreaPOIs and mapID then
        addon.VignetteRadarAreaPOIs.AppendTo(activeMapNotes, mapID, now)
    end
    -- Learned rare spawns fill in where no pack note covers them (Data/RareSpawns.lua).
    if addon.VignetteRadarRareSpawns and mapID then
        addon.VignetteRadarRareSpawns.AppendTo(activeMapNotes, mapID)
    end
    -- Things tracked in Blizzard's collections UI (Data/CollectionTracking.lua).
    if addon.VignetteRadarCollectionTracking and mapID then
        addon.VignetteRadarCollectionTracking.AppendTo(activeMapNotes, mapID)
    end
    -- Points the group shared (Routes/SharedSightings.lua), evidence "party".
    if addon.VignetteRadarSharedSightings and mapID then
        addon.VignetteRadarSharedSightings.AppendTo(activeMapNotes, mapID)
    end
    addon._rawMapNotes = activeMapNotes
    local features = Features()
    local hideNames = features and next(features.GetHiddenMarkerNames())
    local hideTypes = features and next(features.GetHiddenMarkerTypes())
    if hideNames or hideTypes then
        local shown = {}
        for _, note in ipairs(activeMapNotes) do
            if (not hideNames or not features.IsMapNoteNameHidden(note))
                and (not hideTypes or not features.IsMapNoteTypeHidden(note)) then
                shown[#shown + 1] = note
            end
        end
        activeMapNotes = shown
    end
    -- Done, duplicate and out-of-range pack notes leave here, before every reader.
    if addon.VignetteRadarDeclutter then
        activeMapNotes = addon.VignetteRadarDeclutter.Apply(activeMapNotes, activeTargets, player, db)
    end
    if #activeMapNotes > 1 then
        if player then
            table.sort(activeMapNotes, function(left, right)
                local ldx, ldy = left.worldX - player.worldX, left.worldY - player.worldY
                local rdx, rdy = right.worldX - player.worldX, right.worldY - player.worldY
                return ldx * ldx + ldy * ldy < rdx * rdx + rdy * rdy
            end)
        end
    end
    if addon.VignetteRadarExploration then
        local exploration = addon.VignetteRadarExploration
        exploration.ValidateQuestFocus(activeQuests, changedMap)
        if db.vignetteRadarFollowTrackedQuest and C_SuperTrack
            and type(C_SuperTrack.GetSuperTrackedQuestID) == "function" then
            local trackedID = SafeNumber(Call(C_SuperTrack.GetSuperTrackedQuestID))
            local available = false
            for _, quest in ipairs(activeQuests) do
                if quest.questID == trackedID then available = true; break end
            end
            followedQuestID, followedQuestMapID = available and trackedID or nil,
                available and mapID or nil
        else
            followedQuestID, followedQuestMapID = nil, nil
        end
    end
    if Features() then
        local worldMapMode = db.vignetteRadarWorldMap ~= false
        if activeWorldMapMode ~= nil and worldMapMode ~= activeWorldMapMode then
            Features().Update({}, mapID, Now(), { enabled = false })
            pulseUntil = 0
        end
        activeWorldMapMode = worldMapMode
        local alerts
        activeTargets, alerts = Features().Update(activeTargets, mapID, Now(), {
            enabled = db.vignetteRadarEnabled == true, preview = preview,
        })
        if alerts and #alerts > 0 then
            local favorite = false
            for _, target in ipairs(alerts) do
                pulseUntil = math.max(pulseUntil, target.newUntil or 0)
                favorite = favorite or Favorite(target)
            end
            if db.vignetteRadarAlertSound == true and not Quiet() and PlaySound and SOUNDKIT then
                local sound = favorite and SOUNDKIT.RAID_WARNING or SOUNDKIT.TELL_MESSAGE
                    or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                if sound then pcall(PlaySound, sound, "SFX") end
            end
            -- Louder tiers (banner, taskbar flash) live in Core/AlertTiers.lua.
            if addon.VignetteRadarAlertTiers then addon.VignetteRadarAlertTiers.Fire(alerts, db) end
        end
    end
    local exploration = addon.VignetteRadarExploration
    if exploration and not preview and db.vignetteRadarEnabled == true then
        exploration.UpdateTrail(player, mapID, Now())
        if exploration.CheckRouteArrival then exploration.CheckRouteArrival(player, mapID) end
        exploration.RecordSightings(activeTargets, mapID)
        local approach = exploration.CheckApproach(activeTargets, player, mapID)
        if approach and not Quiet() then
            approach.newUntil = Now() + 3
            approachPulseKey, approachPulseUntil = approach.key, approach.newUntil
            pulseUntil = math.max(pulseUntil, approach.newUntil)
            if db.vignetteRadarAlertSound == true and PlaySound and SOUNDKIT then
                pcall(PlaySound, SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "SFX")
            end
        end
    end
    if approachPulseKey and approachPulseUntil and Now() < approachPulseUntil then
        for _, target in ipairs(activeTargets) do
            if target.key == approachPulseKey then target.newUntil = approachPulseUntil; break end
        end
    end
    -- One registry snapshot per scan: every reader below and every display
    -- until the next scan sees the same lists and the same view.
    addon.VignetteRadarPoints.Publish({ mapID = mapID, player = player,
        range = displayedRange or db.vignetteRadarRange,
        targets = activeTargets, quests = activeQuests, notes = activeMapNotes,
        pins = exploration and mapID and exploration.GetPins(mapID) or nil })
    if addon.VignetteRadarBeacons then
        addon.VignetteRadarBeacons.Sync(mapID, player,
            activeTargets, activeQuests, activeMapNotes, TargetVisible)
    end
    if worldFocus and not preview then
        local routePlayer = player
        local routeQuests = addon.VignetteRadarRouteQuests
        if routeQuests then
            routeQuests.Bind(mapID, routePlayer, MapToWorld, MapVector, db)
            routeQuests.Tick()
        end
        worldFocus.Sync(mapID, routePlayer, activeTargets, activeQuests, activeMapNotes)
        local learning = addon.VignetteRadarTreasureLearning
        if learning then learning.Sync(mapID, routePlayer, activeTargets, activeMapNotes) end
        local outcomes = addon.VignetteRadarOutcomeLearning
        if outcomes then outcomes.Sync(activeTargets, activeQuests) end
    end
    if not preview and addon.VignetteRadarFeatureRuntime then
        addon.VignetteRadarFeatureRuntime.Observe(mapID, player, activeTargets)
    end
    addon.UpdateAtlasSnapshot(mapID, now, changedMap)
    addon._spatialGeneration = (addon._spatialGeneration or 0) + 1
    return player
end

RefreshRadar = function(rescan)
    if not rescan then addon._spatialGeneration = (addon._spatialGeneration or 0) + 1 end
    if addon.VignetteRadarZygor then
        addon.VignetteRadarZygor.Bind(MapToWorld, MapVector, CurrentMapID, RefreshZygorVisual)
    end
    local settings = Settings()
    if panel then panel._exploreNextAt = nil end
    local exploration = addon.VignetteRadarExploration
    local mapID = CurrentMapID()
    local trail, trailMap
    if exploration and settings.vignetteRadarBreadcrumbs then trail, trailMap = exploration.GetTrail() end
    local hasExploration = exploration and mapID and
        (#exploration.GetPins(mapID) > 0 or #exploration.GetRoute(mapID) > 0
            or (settings.vignetteRadarBreadcrumbs and settings.vignetteRadarTrailLifetime <= 5)
            or (trailMap == mapID and #trail > 1))
    if settings.vignetteRadarLauncherVisible ~= false or launcherPeekActive then EnsureLauncher() end
    local player
    if rescan then player = ScanVignettes(mapID) end
    local quickPanel = _G.VignetteRadarQuickConfigPanel
    if quickPanel and quickPanel:IsShown() and addon.VignetteRadarQuickConfig
        and addon.VignetteRadarQuickConfig.Refresh then
        addon.VignetteRadarQuickConfig.Refresh()
    end
    local hasMapNotes = false
    if #activeMapNotes > 0 and (settings.vignetteRadarMapNotesVisible == true
        and (settings.vignetteRadarPOISource ~= "none" or settings.vignetteRadarSourceFusion)
        or settings.vignetteRadarWorldFocusZygor or settings.vignetteRadarAreaPOIs == true
        or settings.vignetteRadarRareSpawnNotes == true) then
        player = player or PlayerSnapshot(mapID)
        local range = exploration and exploration.Range(player, nil) or settings.vignetteRadarRange
        if player and type(range) == "number" then
            for _, note in ipairs(activeMapNotes) do
                if settings.vignetteRadarPOITypes[note.kind] ~= false
                    and not (addon.VignetteRadarRecent and addon.VignetteRadarRecent.IsHidden(note, settings))
                    and not (player.instanceID and note.instanceID and player.instanceID ~= note.instanceID) then
                    local dx, dy = note.worldX - player.worldX, note.worldY - player.worldY
                    local distance2 = dx * dx + dy * dy
                    local minimumDistance = MapNoteMinimumDistance(range)
                    if distance2 >= minimumDistance * minimumDistance and distance2 <= range * range then
                        hasMapNotes = true
                        break
                    end
                end
            end
        end
    end
    local hasQuestStarts = false
    if settings.vignetteRadarQuestStartBadges and addon.VignetteRadarAvailableStarts
        and #addon.VignetteRadarAvailableStarts > 0 then
        player = player or PlayerSnapshot(mapID)
        local range = exploration and exploration.Range(player, nil) or settings.vignetteRadarRange
        if player and type(range) == "number" then
            for _, entry in ipairs(addon.VignetteRadarAvailableStarts) do
                if not (player.instanceID and entry.instanceID
                    and player.instanceID ~= entry.instanceID) then
                    local dx, dy = entry.worldX - player.worldX, entry.worldY - player.worldY
                    if dx * dx + dy * dy <= range * range then
                        hasQuestStarts = true
                        break
                    end
                end
            end
        end
    end
    ReconcileFocusedTarget()
    local picker = TargetPickerAPI()
    if picker and type(picker.Refresh) == "function" then pcall(picker.Refresh) end
    if settings.vignetteRadarEnabled ~= true and not preview then
        if panel and panel:IsShown() then Morph.MoveLauncherToRadar(); panel:Hide() end
        Morph.SyncLauncherVisibility()
        if launcher then UpdateLauncher(0, true) end
        if addon.VignetteRadarGuidePanel then addon.VignetteRadarGuidePanel.Refresh() end
        return
    end
    if manualPanelState == false then
        if panel and panel:IsShown()
            and not (Morph.running and Morph.shell and not Morph.shell.opening) then
            Morph.MoveLauncherToRadar()
            panel:Hide()
        end
    elseif manualPanelState == true or preview or settings.vignetteRadarKeepVisibleCombat == true
        or settings.vignetteRadarHideWhenEmpty == false
        or hasExploration or #SelectableTargets() > 0 or hasMapNotes or hasQuestStarts
        or (#activeQuests > 0 and (settings.vignetteRadarQuestDots
            or (settings.vignetteRadarQuestAreas and settings.vignetteRadarNorthUp))) then
        EnsurePanel():Show()
        Render()
        if not preview and addon.VignetteRadarQuickConfig
            and addon.VignetteRadarQuickConfig.ShowFirstRunGuide then
            addon.VignetteRadarQuickConfig.ShowFirstRunGuide(panel.field)
        end
    elseif panel then
        if panel:IsShown() then Morph.MoveLauncherToRadar() end
        panel:Hide()
    end
    Morph.SyncLauncherVisibility()
    if launcher then UpdateLauncher(0, true) end
    UpdateTargetButton()
    local studio = addon.VignetteRadarExpeditionStudio
    if studio and studio.IsCardVisible and studio.IsCardVisible() then
        studio.SetCardAnchor(panel and panel:IsShown() and panel
            or launcher and launcher:IsShown() and launcher or nil)
    end
    if addon.VignetteRadarGuidePanel then addon.VignetteRadarGuidePanel.Refresh() end
end

addon.RefreshVignetteRadar = function(rescan)
    RefreshRadar(rescan ~= false)
    local tracker = addon.VignetteRadarQuestTracker
    if tracker and tracker.SyncFocus then tracker.SyncFocus() end
end
addon.ToggleVignetteRadarQuestKey = function()
    local legend = LegendAPI()
    if not (legend and legend.ToggleQuest) then return false end
    if not (panel and panel:IsShown()) then
        Settings().vignetteRadarEnabled = true
        manualPanelState = true
        RefreshRadar(true)
    end
    if not (panel and panel:IsShown()) then return false end
    local opened = legend.ToggleQuest(CircleOnly() and panel.field or panel, panel)
    if opened then
        panel._questKeyNextAt = nil
        addon.UpdateVignetteRadarQuestKey()
    end
    if panel.RefreshCornerTools then panel.RefreshCornerTools() end
    return opened
end
addon.VignetteRadarAPI = {
    GetPanel = function() return panel end,
    GetTargets = function() return activeTargets end,
    GetQuests = function() return activeQuests end,
    -- The slot the radar gave this quest wins, even when the map changed
    -- since the scan, so the tracker and the radar always agree.
    GetQuestColorSlot = function(questID)
        return questColorByID[questID]
            or (type(questID) == "number"
            and (questID % #QUEST_COLORS) + 1) or 1
    end,
    HighlightQuest = function(questID)
        if not (panel and panel.questDots) then return end
        local exploration = addon.VignetteRadarExploration
        local focused = exploration and exploration.GetFocusedQuest and exploration.GetFocusedQuest()
        for _, dot in ipairs(panel.questDots) do
            if dot.quest and dot:IsShown() then
                local selected = (questID or focused) == dot.quest.questID
                dot.selection:SetShown(selected)
                dot:SetAlpha(questID and not selected and .48 or 1)
            end
        end
    end,
    GetRawTargets = function() return addon._rawVignetteTargets or {} end,
    GetRawMapNotes = function() return addon._rawMapNotes or {} end,
    GetCurrentMapID = CurrentMapID,
    ToggleAtlas = function()
        local atlas = addon.VignetteRadarAtlas
        if not atlas then return false, "Living Atlas unavailable" end
        atlas.SetOnSelect(function(entry)
            local focus = addon.VignetteRadarFocus
            local options = { source = "atlas" }
            if entry.questID then focus.Select(focus.Quest(entry.questID), options)
            elseif entry.targetRef then focus.Select(focus.Target(entry.targetRef), options)
            elseif entry.noteRef then focus.Select(focus.Note(entry.noteRef), options) end
        end)
        local opened, reason = atlas.Toggle()
        if opened then addon._radarAtlasUpdatedAt = nil; RefreshRadar(true) end
        return opened, reason
    end,
    BindZygorGuide = function()
        local zygor = addon.VignetteRadarZygor
        if not (zygor and _G.ZygorGuidesViewer) then
            return false, "Zygor is not loaded"
        end
        if not zygor.Bind(MapToWorld, MapVector, CurrentMapID, RefreshZygorVisual) then
            return false, "Zygor guide updates are unavailable"
        end
        return true
    end,
    StartZygorRoute = function()
        local ready, reason = addon.VignetteRadarAPI.BindZygorGuide()
        if not ready then return false, reason end
        return addon.VignetteRadarZygor.StartObjectiveRoute()
    end,
    RefreshMapData = function()
        if addon.VignetteRadarPOIs and addon.VignetteRadarPOIs.Invalidate then
            addon.VignetteRadarPOIs.Invalidate()
        end
        mapNotesUpdatedAt = nil
        RefreshRadar(true)
        return #activeMapNotes
    end,
    PinZygorStep = function()
        local ready, reason = addon.VignetteRadarAPI.BindZygorGuide()
        if not ready then return false, reason end
        return addon.VignetteRadarZygor.Pin("objective")
    end,
    GetPlayerSnapshot = function() return PlayerSnapshot(CurrentMapID()) end,
    GetSpatialSnapshot = function(mode)
        return addon.VignetteRadarConstellationData
            and addon.VignetteRadarConstellationData.GetSnapshot(mode) or nil
    end,
    InvalidateSpatialSnapshot = function()
        addon._spatialGeneration = (addon._spatialGeneration or 0) + 1
    end,
    -- The lists themselves come from the point registry.
    GetSpatialSources = function()
        return CurrentMapID(), CategoryEnabled, Ignored, Favorite, MapNoteMinimumDistance
    end,
    RefreshConstellationControl = function()
        if panel and panel.RefreshCornerTools then panel.RefreshCornerTools() end
    end,
    GetSelectableTargets = SelectableTargets,
    GetRouteCandidates = function()
        local mapID = CurrentMapID()
        local candidates = {}
        local points = addon.VignetteRadarPoints
        local quests = points.Refs("quest")
        if #quests == 0 then quests = CollectQuests(mapID, true) end
        for _, quest in ipairs(quests) do
            if #candidates >= 128 then break end
            candidates[#candidates + 1] = {
                kind = "quest", questID = quest.questID, name = quest.name,
                mapID = mapID, worldX = quest.worldX, worldY = quest.worldY,
                instanceID = quest.instanceID, mapX = quest.mapX, mapY = quest.mapY,
            }
        end
        local liveForNotes = {}
        for _, target in ipairs(points.Refs("live")) do
            if #candidates >= 224 then break end
            if (target.category == "rare" or target.category == "treasure")
                and not target.stale and CategoryEnabled(target.category) and not Ignored(target)
                and TargetAlpha(target) > 0 then
                candidates[#candidates + 1] = {
                    kind = target.category, key = target.key, name = target.name,
                    mapID = mapID, worldX = target.worldX, worldY = target.worldY,
                    instanceID = target.instanceID, mapX = target.mapX, mapY = target.mapY,
                }
                liveForNotes[#liveForNotes + 1] = target
            end
        end
        for _, note in ipairs(points.Refs("saved")) do
            if #candidates >= 256 then break end
            local kind = points.Kind(note)
            if (kind == "rare" or kind == "treasure")
                and Settings().vignetteRadarPOITypes[note.kind] ~= false
                and not (addon.VignetteRadarRecent
                    and addon.VignetteRadarRecent.IsHidden(note, Settings())) then
                local duplicate = false
                for _, target in ipairs(liveForNotes) do
                    if points.Matches(note, target) then
                        duplicate = true
                        break
                    end
                end
                if not duplicate then
                    candidates[#candidates + 1] = {
                        kind = kind, key = note.key, name = note.name,
                        mapID = note.mapID or mapID, worldX = note.worldX,
                        worldY = note.worldY, instanceID = note.instanceID,
                        mapX = note.mapX, mapY = note.mapY,
                    }
                end
            end
        end
        local exploration = addon.VignetteRadarExploration
        if exploration and mapID then
            for _, pin in ipairs(exploration.GetPins(mapID)) do
                if #candidates >= 256 then break end
                candidates[#candidates + 1] = {
                    kind = "pin", id = pin.id, name = pin.name,
                    mapID = mapID, worldX = pin.worldX, worldY = pin.worldY,
                    instanceID = pin.instanceID, mapX = pin.mapX, mapY = pin.mapY,
                }
            end
        end
        return candidates
    end,
    GetPanel = function() return panel end,
    GetLauncher = function() return launcher end,
    IsPreviewing = function() return preview end,
    Refresh = function(rescan)
        if rescan == true then addon._focusQuestCache = nil end
        RefreshRadar(rescan == true)
    end,
    ToggleQuestKey = addon.ToggleVignetteRadarQuestKey,
    RefreshPresentation = function()
        addon._spatialGeneration = (addon._spatialGeneration or 0) + 1
        if panel and panel:IsShown() then Render() end
        if launcher then UpdateLauncher(0, true) end
    end,
}

do
    local legend = LegendAPI()
    if legend and type(legend.ApplyDefaults) == "function" then pcall(legend.ApplyDefaults, Settings()) end
    if legend and type(legend.SetChangeCallback) == "function" then
        legend.SetChangeCallback(function()
            addon._spatialGeneration = (addon._spatialGeneration or 0) + 1
            ReconcileFocusedTarget()
            local picker = TargetPickerAPI()
            if picker and type(picker.Refresh) == "function" then pcall(picker.Refresh) end
            if panel and panel:IsShown() then Render() end
            if launcher then UpdateLauncher(0, true) end
            UpdateTargetButton()
        end)
    end
    local picker = TargetPickerAPI()
    if picker and type(picker.SetProvider) == "function" then pcall(picker.SetProvider, SelectableTargets) end
    -- A focus change from any view (radar, list, HUD, bar, tracker, map)
    -- redraws the radar, its launcher and the HUD once.
    addon.VignetteRadarFocus.OnChanged(function()
        addon._spatialGeneration = (addon._spatialGeneration or 0) + 1
        if addon.VignetteRadarConstellation then addon.VignetteRadarConstellation.FocusChanged() end
        if panel and panel:IsShown() then Render() end
        if launcher then UpdateLauncher(0, true) end
        UpdateTargetButton()
    end)
end

function addon.ResetVignetteRadarPositions()
    Morph.Cancel()
    Settings().vignetteRadarPosition = nil
    Settings().vignetteRadarCirclePosition = nil
    Settings().vignetteRadarLauncherPosition = nil
    if addon.VignetteRadarGuidePanel then addon.VignetteRadarGuidePanel.ResetPosition() end
    if panel then PlacePanel(30, UIParent:GetHeight() - 520, panel:GetScale()) end
    Settings().vignetteRadarLauncherVisible = true
    local button = EnsureLauncher()
    PlaceLauncher(UIParent:GetWidth() / 2 - LAUNCHER_DIMENSIONS.width / 2,
        UIParent:GetHeight() / 2 + LAUNCHER_DIMENSIONS.height / 2)
    button:SetFrameStrata("TOOLTIP")
    button._rescueRaised = true
    button:Show()
    SaveLauncherPosition()
    if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.Reanchor(panel) end
    if addon.VignetteRadarQuickConfig and addon.VignetteRadarQuickConfig.Refresh then
        addon.VignetteRadarQuickConfig.Refresh()
    end
end

function addon.SetVignetteRadarRange(range)
    for _, supported in ipairs(Ranges()) do
        if range == supported then
            if addon.VignetteRadarExploration then addon.VignetteRadarExploration.ManualZoom() end
            if addon.VignetteRadarFeatureRuntime then
                addon.VignetteRadarFeatureRuntime.ManualViewOverride()
                addon.VignetteRadarContextOverlay = nil
            end
            Settings().vignetteRadarRange = supported
            addon.VignetteRadarViewProfiles.Record(Settings())
            RefreshRadar(false)
            return true
        end
    end
    return false
end

function addon.SetVignetteRadarEnabled(enabled)
    Morph.Cancel()
    Settings().vignetteRadarEnabled = enabled == true
    preview = false
    manualPanelState = nil
    RefreshRadar(true)
    if addon.VignetteRadarConstellation then addon.VignetteRadarConstellation.Refresh() end
end

function addon.SetVignetteRadarLayout(layout)
    if not LAYOUTS[layout] then return false end
    local settings = Settings()
    if settings.vignetteRadarCircleOnly ~= true and settings.vignetteRadarLayout ~= layout then
        addon.VignetteRadarViewProfiles.Switch(settings, layout)
    end
    Settings().vignetteRadarLayout = layout
    RefreshRadar(false)
    return true
end

function addon.SetVignetteRadarScale(scale)
    if not SafeNumber(scale) then return false end
    if not panel then
        Settings().vignetteRadarScale = math.max(.8, math.min(1.8, scale))
        addon.VignetteRadarViewProfiles.Record(Settings())
        return true
    end
    local left, top = PanelPosition()
    if not (left and top) then return false end
    PlacePanel(left, top, scale)
    Settings().vignetteRadarScale = panel:GetScale()
    addon.VignetteRadarViewProfiles.Record(Settings())
    SavePosition()
    return true
end

function addon.SetVignetteRadarNorthUp(enabled)
    Settings().vignetteRadarNorthUp = enabled == true
    RefreshRadar(false)
end

-- Trails: "off" | "follow" | "lead" | "both". The Follow half is mirrored
-- into vignetteRadarBreadcrumbs, which the breadcrumb code keeps reading.
function addon.SetVignetteRadarTrailMode(mode)
    local modes = addon.VignetteRadarTrailMode
    if not (modes and modes.valid[mode]) then return false end
    local settings = Settings()
    settings.vignetteRadarTrailMode = mode
    settings.vignetteRadarBreadcrumbs = modes.Follows(mode)
    if addon.ValidateSettings then addon.ValidateSettings() end
    if addon.Trace then addon.Trace.Log("trail", "mode %s", mode) end
    RefreshRadar(false)
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
    return true
end

-- The toolbar toggle and older callers switch only the Follow half.
function addon.SetVignetteRadarTrailEnabled(enabled)
    local modes = addon.VignetteRadarTrailMode
    if modes then
        return addon.SetVignetteRadarTrailMode(modes.Compose(enabled == true,
            modes.Leads(Settings().vignetteRadarTrailMode)))
    end
    Settings().vignetteRadarBreadcrumbs = enabled == true
    RefreshRadar(false)
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
end

function addon.SetVignetteRadarTrailStyle(style, enable)
    if not TRAIL_STYLE_BY_ID[style] then return false end
    Settings().vignetteRadarTrailStyle = style
    if enable then
        Settings().vignetteRadarBreadcrumbs = true
        local modes = addon.VignetteRadarTrailMode
        if modes then
            Settings().vignetteRadarTrailMode = modes.Compose(true, modes.Leads(Settings().vignetteRadarTrailMode))
        end
    end
    RefreshRadar(false)
    if RefreshTrailPopup then RefreshTrailPopup() end
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
    return true
end

function addon.SetVignetteRadarTrailOption(key, value)
    local allowed = key == "vignetteRadarTrailSpacing" and TRAIL_SPACINGS
        or key == "vignetteRadarTrailSpeed" and TRAIL_SPEEDS
        or key == "vignetteRadarTrailLifetime" and TRAIL_LIFETIMES
    local percentRange = key == "vignetteRadarTrailSize" and { .1, 2 }
        or (key == "vignetteRadarTrailTailFade" or key == "vignetteRadarTrailFadeSpan") and { 0, 1 }
    if not allowed and not percentRange then return false end
    local valid = key == "vignetteRadarTrailLifetime" and type(value) == "number"
        and value == math.floor(value) and value >= allowed[1] and value <= allowed[2]
    if percentRange then
        valid = type(value) == "number" and value == value
            and value >= percentRange[1] and value <= percentRange[2]
            and math.abs(value * 100 - math.floor(value * 100 + .5)) < .00001
    elseif not valid and key ~= "vignetteRadarTrailLifetime" then
        for _, candidate in ipairs(allowed) do
            if candidate == value then valid = true; break end
        end
    end
    if not valid then return false end
    Settings()[key] = value
    if panel and panel:IsShown() then Render() end
    if RefreshTrailPopup then RefreshTrailPopup() end
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
    return true
end

function addon.SetVignetteRadarQuietCombat(fadeInCombat)
    Settings().vignetteRadarQuietCombat = fadeInCombat == true
    RefreshRadar(false)
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
end

function addon.SetVignetteRadarKeepVisibleCombat(enabled)
    Settings().vignetteRadarKeepVisibleCombat = enabled == true
    RefreshRadar(false)
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
end

function addon.SetVignetteRadarCircleOnly(enabled)
    local settings = Settings()
    enabled = enabled == true
    if panel and settings.vignetteRadarCircleOnly ~= enabled then SavePosition() end
    if settings.vignetteRadarCircleOnly ~= enabled then
        addon.VignetteRadarViewProfiles.Switch(settings,
            enabled and "radarOnly" or settings.vignetteRadarLayout)
    end
    settings.vignetteRadarCircleOnly = enabled
    if panel then
        panel:SetClampedToScreen(not enabled)
        local position = enabled and settings.vignetteRadarCirclePosition or settings.vignetteRadarPosition
        local x = type(position) == "table" and SafeNumber(tonumber(position.x))
        local y = type(position) == "table" and SafeNumber(tonumber(position.y))
        local currentLeft, currentTop = PanelPosition()
        local left = x or currentLeft
        local top = y and UIParent:GetHeight() + y or currentTop
        if left and top then PlacePanel(left, top, settings.vignetteRadarScale); SavePosition() end
    end
    if enabled then
        if HideTrailPopup then HideTrailPopup() end
        if routeMenu.Hide then routeMenu.Hide() end
        local legend, picker = LegendAPI(), TargetPickerAPI()
        if legend and legend.Hide then legend.Hide() end
        if picker and picker.Hide then picker.Hide() end
    end
    RefreshRadar(false)
end

function addon.ToggleVignetteRadarPreview()
    preview = not preview
    manualPanelState = preview and true or nil
    RefreshRadar(true)
end

function VignetteRadar_CycleWorldFocus(direction)
    local focus = addon.VignetteRadarWorldFocus
    if focus then focus.Cycle(direction) end
end

function addon.VignetteRadarBindingError(reason)
    if type(reason) ~= "string" or reason == "" then return end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(reason, 1, .65, .25)
    end
end

function VignetteRadar_ToggleRadar()
    addon.SetVignetteRadarEnabled(not Settings().vignetteRadarEnabled)
end

function VignetteRadar_ToggleSettings()
    local quick = addon.VignetteRadarQuickConfig
    if quick then quick.Toggle() end
end

function VignetteRadar_ToggleBearingBar()
    Settings().vignetteRadarBeaconsEnabled = not Settings().vignetteRadarBeaconsEnabled
    RefreshRadar(false)
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
end

function VignetteRadar_ToggleAutoRoute()
    local focus = addon.VignetteRadarWorldFocus
    if not focus then return addon.VignetteRadarBindingError("World Focus is unavailable") end
    local wasRouting = focus.IsRouteActive()
    local ok, reason = focus.ToggleRoute()
    if not ok and not wasRouting then addon.VignetteRadarBindingError(reason) end
    RefreshRadar(false)
    return wasRouting or ok
end

function VignetteRadar_PinZygorStep()
    local ok, reason = addon.VignetteRadarAPI.PinZygorStep()
    if not ok then addon.VignetteRadarBindingError(reason) end
    RefreshRadar(false)
    return ok
end

function VignetteRadar_StartNearestRoute(kind)
    local focus = addon.VignetteRadarWorldFocus
    if not focus then return addon.VignetteRadarBindingError("World Focus is unavailable") end
    local ok, reason = focus.StartNearest(kind)
    if not ok then addon.VignetteRadarBindingError(reason) end
    RefreshRadar(false)
    return ok
end

function VignetteRadar_NavigateQuestRoute(direction)
    local focus = addon.VignetteRadarWorldFocus
    if not focus then return addon.VignetteRadarBindingError("World Focus is unavailable") end
    local ok, reason
    if direction and direction < 0 then ok, reason = focus.PreviousQuestStep()
    else ok, reason = focus.NextQuestStep() end
    if not ok then addon.VignetteRadarBindingError(reason) end
    RefreshRadar(false)
    return ok
end

function VignetteRadar_ClearFocus()
    local focus = addon.VignetteRadarWorldFocus
    if not focus then return addon.VignetteRadarBindingError("World Focus is unavailable") end
    addon.VignetteRadarFocus.Clear({ project = false, source = "keybind" })
    local ok, reason = focus.Clear()
    if not ok then addon.VignetteRadarBindingError(reason) end
    RefreshRadar(false)
    return ok
end

SLASH_VIGNETTERADAR1 = "/magpie"
SLASH_VIGNETTERADAR2 = "/vr"
SlashCmdList.VIGNETTERADAR = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "config" or message == "options" then
        if addon.OpenOptions then addon.OpenOptions() end
        return
    elseif message == "undo" then
        local exploration = addon.VignetteRadarExploration
        local undone = exploration and exploration.UndoPreset and exploration.UndoPreset()
        print("Magpie: " .. (undone and "preset undone" or "nothing to undo"))
        return
    elseif message == "panels" then
        local tray = addon.VignetteRadarTray
        if tray and tray.ResetAllPanels then tray.ResetAllPanels() end
        print("Magpie: panels docked back under the radar")
        return
    elseif message == "navlog" then
        if addon.VignetteRadarWorldMarker then addon.VignetteRadarWorldMarker.StartNavLog() end
        return
    elseif message == "explore" then
        if addon.VignetteRadarExploration then addon.VignetteRadarExploration.TogglePanel() end
        return
    elseif message == "route debug" then
        local focus = addon.VignetteRadarWorldFocus
        local pool = addon.VignetteRadarRouteQuests
        local route = focus and focus.Diagnostics and focus.Diagnostics()
        local data = pool and pool.Diagnostics and pool.Diagnostics()
        if route and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(("Magpie Route: %s (%s), quest %s, %d visible quest points, %d visited, %d available starts."):format(
                route.mode, route.state, tostring(route.questID or "none"),
                route.radarPoints, route.visited, route.availableStarts))
            if data then
                DEFAULT_CHAT_FRAME:AddMessage(("Magpie Cache: %d/%d quest-log entries scanned, %d local and %d other-map waypoints cached."):format(
                    data.logRead, data.logTotal, data.localPoints, data.otherPoints))
            end
        end
        return
    elseif message == "pin" or message:match("^pin%s+") then
        local exploration = addon.VignetteRadarExploration
        if exploration then
            local name = message:match("^pin%s+(.+)$") or "My pin"
            local ok, result = exploration.AddPin(PlayerSnapshot(CurrentMapID()), name)
            exploration.Tell(ok and ("Pinned " .. result.name) or result)
        end
        return
    elseif message == "layout" or message:match("^layout%s+") then
        local layout = message:match("^layout%s+(%S+)$")
        if not layout and message == "layout" then
            local nextLayout = { classic = "squat", squat = "compact", compact = "classic" }
            layout = nextLayout[Settings().vignetteRadarLayout or "classic"]
        end
        if not addon.SetVignetteRadarLayout(layout) and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("Magpie: /magpie layout [classic, squat, compact]")
        end
        return
    elseif message == "focus" then
        if addon.VignetteRadarQuickConfig then addon.VignetteRadarQuickConfig.OpenPage("World Focus") end
        return
    elseif message == "focus next" or message == "focus previous" then
        VignetteRadar_CycleWorldFocus(message == "focus next" and 1 or -1)
        return
    elseif message == "preview" then
        addon.ToggleVignetteRadarPreview()
        return
    elseif message == "recenter" then
        addon.ResetVignetteRadarPositions()
        Settings().vignetteRadarEnabled = true
        preview = false
        manualPanelState = true
        RefreshRadar(true)
        return
    elseif message == "off" then
        addon.SetVignetteRadarEnabled(false)
        return
    elseif message == "on" then
        Settings().vignetteRadarEnabled = true
        preview = false
        manualPanelState = true
    elseif message == "" then
        ToggleRadarPanel()
        return
    else
        -- help, or anything unknown: the command list instead of a silent toggle.
        local lines = { "Magpie commands (/magpie or /vr):",
            "/magpie: show or hide the radar",
            "/magpie config: settings",
            "/magpie on | off | recenter | preview",
            "/magpie layout [classic | squat | compact]",
            "/magpie focus [next | previous]: waypoint settings, or step through waypoints",
            "/magpie panels: dock the panels back under the radar",
            "/magpie explore | pin [name] | undo",
            "/magpie buttons: the minimap button tray",
            "/magpie export | import | sweep | today",
            "/vrtrace on | off: debug log" }
        if message ~= "help" then table.insert(lines, 1, "Magpie: unknown command \"" .. message .. "\".") end
        for _, line in ipairs(lines) do
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) else print(line) end
        end
        return
    end
    RefreshRadar(true)
end

addon.VignetteRadarPopupNames = {
    "VignetteRadarTargetPickerPanel", "VignetteRadarLegendPanel",
    "VignetteRadarQuestLegendPanel", "VignetteRadarMarkerLegendPanel",
    "VignetteRadarTrailStylePopup",
    "VignetteRadarRouteChooserPopup",
    "VignetteRadarQuickConfigPanel", "VignetteRadarExplorePanel",
    "VignetteRadarGuidePanel",
}
local events = CreateFrame("Frame")
function events:RefreshAfterQuestUpdate()
    if self._questRefreshQueued then return end
    self._questRefreshQueued = true
    local outcomes = addon.VignetteRadarOutcomeLearning
    self._outcomeSnapshot = outcomes and outcomes.CapturePlayer()
    if C_Timer and C_Timer.After then
        -- Quest objectives and their map POIs can settle in separate events.
        -- Merge a burst into one fresh scan instead of scanning every event.
        C_Timer.After(0.12, function()
            self._questRefreshQueued = false
            if outcomes then outcomes.OnQuestEvent(true, self._outcomeSnapshot) end
            self._outcomeSnapshot = nil
            RefreshRadar(true)
        end)
    else
        self._questRefreshQueued = false
        if outcomes then outcomes.OnQuestEvent(true, self._outcomeSnapshot) end
        self._outcomeSnapshot = nil
        RefreshRadar(true)
    end
end
function events:QueueFullRefresh()
    if not (C_Timer and C_Timer.After) then
        RefreshRadar(true)
        return
    end
    if self._fullRefreshQueued then return end
    self._fullRefreshQueued = true
    -- Vignette and zone events arrive in bursts; scan once on the next frame.
    C_Timer.After(0, function()
        self._fullRefreshQueued = false
        RefreshRadar(true)
    end)
end
-- Events arrive through the bus (Core/Bus.lua). Modules earlier in the TOC
-- subscribe for themselves and so run first: Recent, QuestData and
-- RouteQuests drop their quest caches, TreasureLearning and WorldFocus take
-- loot, and FeatureRuntime follows login, leaving combat and logout.
events.OnBusEvent = function(event)
    if event == "GLOBAL_MOUSE_DOWN" then
        -- This event runs only for clicks, never in the radar update loop.
        -- Keep related popups open while the pointer is inside any of them.
        local names = addon.VignetteRadarPopupNames
        local quickPanel = _G.VignetteRadarQuickConfigPanel
        if quickPanel and quickPanel:IsShown() and panel and panel.frameToggle
            and panel.frameToggle.IsMouseOver and panel.frameToggle:IsMouseOver() then
            return -- Switching frame style must not dismiss open settings.
        end
        -- Let each launch button handle its own open/close click. Closing here
        -- first would make its subsequent OnClick reopen the same popup.
        if panel then
            for _, opener in ipairs({ panel.settingsDot, panel.target,
                panel.legend, panel.trailToggle, panel.routeToggle }) do
                if opener and opener.IsMouseOver and opener:IsMouseOver() then return end
            end
            for _, tool in ipairs(panel.hoverTools or {}) do
                if (tool.toolID == "config" or tool.toolID == "target"
                    or tool.toolID == "legend" or tool.toolID == "trail"
                    or tool.toolID == "route")
                    and tool.IsMouseOver and tool:IsMouseOver() then return end
            end
        end
        for _, name in ipairs(names) do
            local popup = _G[name]
            if popup and popup:IsShown() and popup.IsMouseOver and popup:IsMouseOver() then return end
        end
        local closed = false
        for _, name in ipairs(names) do
            local popup = _G[name]
            if popup and popup:IsShown() then popup:Hide(); closed = true end
        end
        if closed and panel then
            if panel.legend then
                panel.legend._open = false
                panel.legend:SetAlpha(.68)
                panel.legend.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 0)
            end
            if panel.RefreshCornerTools then panel.RefreshCornerTools() end
        end
        return
    end
    local questUpdated = event == "QUEST_LOG_UPDATE" or event == "QUEST_POI_UPDATE"
        or event == "QUEST_WATCH_LIST_CHANGED" or event == "QUEST_WATCH_UPDATE"
        or event == "TASK_PROGRESS_UPDATE" or event == "QUEST_ACCEPTED"
        or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN"
    local mapChanged = event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS"
    if mapChanged or questUpdated then
        addon.VignetteRadarStartsNextAt = nil
        addon._focusQuestCache = nil
    end
    if mapChanged then questMapBasis = nil end
    if mapChanged or questUpdated or event == "SUPER_TRACKING_CHANGED" then
        if panel and panel.questBlob then
            panel.questBlob.drawnKey = nil
            panel.questBlob.retryDelay = nil
            if mapChanged then panel.questBlob.mapContextID = nil end
        end
    end
    if questUpdated then events:RefreshAfterQuestUpdate()
    else events:QueueFullRefresh() end
    if event == "PLAYER_LOGIN" or mapChanged or questUpdated then
        local studio = addon.VignetteRadarExpeditionStudio
        if studio then
            studio.SetPlayer(PlayerSnapshot(CurrentMapID()))
            studio.SetCardAnchor(panel and panel:IsShown() and panel
                or launcher and launcher:IsShown() and launcher or nil)
            studio.RefreshCard()
        end
    end
    if event == "PLAYER_LOGIN" and C_Timer and C_Timer.After then
        C_Timer.After(0.5, function() RefreshRadar(true) end)
    end
end
for _, topic in ipairs({ "LOGIN", "MAP_CHANGED", "VIGNETTES", "QUEST_CHANGED",
    "SUPERTRACK", "TRACKING", "COMBAT", "GLOBAL_MOUSE_DOWN" }) do
    addon.Bus.On(topic, events.OnBusEvent)
end
-- Detection and expiry continue when the user hides both visual surfaces.
events:SetScript("OnUpdate", function(self, elapsed)
    local settings = not preview and not (panel and panel:IsShown())
        and not (launcher and launcher:IsShown()) and Settings()
    if not settings or settings.vignetteRadarEnabled ~= true then
        self._idleElapsed = 0
        return
    end
    self._idleElapsed = (self._idleElapsed or 0) + elapsed
    if self._idleElapsed >= addon.VignetteRadarScanSeconds(settings) then
        self._idleElapsed = 0
        local started = ProfileTime()
        RefreshRadar(true)
        CheckUpdateBudget(self, started, "background")
    end
end)
