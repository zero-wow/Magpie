local _, addon = ...
if type(addon) ~= "table" then return end

local Data = {}
addon.VignetteRadarConstellationData = Data

local cache

local Safe = addon.Secret.Safe

-- Keeps "" (unlike Secret.Text).
local function SafeString(value)
    return type(value) == "string" and Safe(value) and value or nil
end

local NOTE_CATEGORIES = { rare = true, treasure = true, entrance = true }

local function Category(kind)
    return NOTE_CATEGORIES[kind] and kind or "other"
end

local function HasPackSource(settings)
    if settings.vignetteRadarSourceFusion
        and type(settings.vignetteRadarFusionSources) == "table"
        and #settings.vignetteRadarFusionSources > 0 then return true end
    return settings.vignetteRadarPOISource ~= "none"
end

local function Build(mode, generation)
    local settings = addon.GetSettings()
    local radar = addon.VignetteRadarAPI
    local spatial = addon.VignetteRadarSpatial
    local points = addon.VignetteRadarPoints
    local mapID, categoryEnabled, ignored, favorite, noteMinimum = radar.GetSpatialSources()
    local targets, notes = points.Refs("live"), points.Refs("saved")
    local player = radar.GetPlayerSnapshot()
    local result = { generation = generation, sourceMode = mode, mapID = mapID,
        player = player, points = {}, totalEligibleCount = 0,
        effectiveRange = spatial.Number(settings.vignetteRadarRange) or 450 }
    local space = player and spatial.Number(player.instanceID)
    local playerX = player and spatial.Number(player.worldX)
    local playerY = player and spatial.Number(player.worldY)
    if not (space and playerX and playerY) then
        result.reason = "Position Unavailable"
        return result
    end
    result.coordinateSpaceID = space
    local range = result.effectiveRange
    local recent = addon.VignetteRadarRecent
    local lens = addon.VignetteRadarLensActive
    local selected = addon.VignetteRadarWorldFocus
        and addon.VignetteRadarWorldFocus.GetFocusedStep
        and addon.VignetteRadarWorldFocus.GetFocusedStep() or nil
    local pickerKey = addon.VignetteRadarFocus.GetTargetKey()
    local focusPath = addon.VignetteRadarWorldFocus
        and addon.VignetteRadarWorldFocus.GetConstellationPath
        and addon.VignetteRadarWorldFocus.GetConstellationPath() or nil
    result.focusPath = focusPath
    local destinationKey = focusPath and focusPath.destinationKey
    local focusKey = pickerKey or destinationKey or (selected and selected.key)
    local focusedTarget
    if pickerKey then
        for _, target in ipairs(targets or {}) do
            if target.key == pickerKey and not target.stale then
                focusedTarget = target
                break
            end
        end
    end
    local live, saved, grid, blocked = {}, {}, {}, {}

    local function Position(item, minimum)
        if spatial.Number(item.instanceID) ~= space then return nil end
        local distance = points.Distance(player, item)
        if not distance or distance < (minimum or 0) or distance > range then return nil end
        return distance, item.worldX, item.worldY
    end

    if mode ~= "pack" then
        for _, target in ipairs(targets or {}) do
            if not target.stale then
                local distance, x, y = Position(target)
                if distance then
                    local eligible = categoryEnabled(target.category) and not ignored(target)
                        and (not lens or target.category == lens)
                        and not (recent and recent.IsHidden(target, settings))
                    if not eligible then
                        if mode == "mixed" then
                            local gx, gy = math.floor(x / 60), math.floor(y / 60)
                            blocked[gx] = blocked[gx] or {}
                            blocked[gx][gy] = blocked[gx][gy] or {}
                            blocked[gx][gy][#blocked[gx][gy] + 1] = target
                        end
                    else
                    local key = SafeString(target.key)
                    local point = { key = key, sourceKey = key, evidence = "live",
                        targetRef = target,
                        name = SafeString(target.name) or "Detected vignette",
                        category = SafeString(target.category) or "other",
                        source = SafeString(target.source),
                        worldX = x, worldY = y, mapID = target.mapID,
                        coordinateSpaceID = space, distance = distance,
                        favorite = favorite(target) == true,
                        isWorldBoss = target.isWorldBoss == true,
                        focused = focusKey ~= nil and focusKey == key }
                    local entry = { point = point, target = target }
                    live[#live + 1] = entry
                    if mode == "mixed" then
                        local gx, gy = math.floor(x / 60), math.floor(y / 60)
                        grid[gx] = grid[gx] or {}
                        grid[gx][gy] = grid[gx][gy] or {}
                        grid[gx][gy][#grid[gx][gy] + 1] = entry
                    end
                    end
                end
            end
        end
    end

    if mode ~= "live" then
        local types = settings.vignetteRadarPOITypes or {}
        local minimum = noteMinimum(range)
        for _, note in ipairs(notes or {}) do
            if note.kind ~= "guide" and types[note.kind] ~= false
                and (not lens or (lens == "rare" and note.kind == "mob")
                    or (lens == "treasure" and (note.kind == "treasure" or note.kind == "entrance")))
                and not (recent and recent.IsHidden(note, settings)) then
                local distance, x, y = Position(note, minimum)
                if distance then
                    local duplicate
                    if mode == "mixed" and (note.kind == "mob" or note.kind == "treasure") then
                        local gx, gy = math.floor(x / 60), math.floor(y / 60)
                        for column = gx - 1, gx + 1 do
                            local rows = blocked[column]
                            if rows then
                                for row = gy - 1, gy + 1 do
                                    for _, target in ipairs(rows[row] or {}) do
                                        if points.Matches(note, target, true) then
                                            duplicate = true; break
                                        end
                                    end
                                    if duplicate then break end
                                end
                            end
                            if duplicate then break end
                        end
                    end
                    if not duplicate and mode == "mixed"
                        and (note.kind == "mob" or note.kind == "treasure") then
                        local gx, gy = math.floor(x / 60), math.floor(y / 60)
                        for column = gx - 1, gx + 1 do
                            local rows = grid[column]
                            if rows then
                                for row = gy - 1, gy + 1 do
                                    for _, entry in ipairs(rows[row] or {}) do
                                        if points.Matches(note, entry.target, true) then
                                            duplicate = true
                                            entry.point.key = SafeString(note.key) or entry.point.key
                                            entry.point.focused = entry.point.focused
                                                or (focusKey ~= nil and focusKey == note.key)
                                            break
                                        end
                                    end
                                    if duplicate then break end
                                end
                            end
                            if duplicate then break end
                        end
                    end
                    if not duplicate then
                        local key = SafeString(note.key)
                        saved[#saved + 1] = { key = key, sourceKey = key,
                            noteRef = note,
                            category = Category(points.Kind(note)),
                            kind = SafeString(note.kind), name = SafeString(note.name) or "Saved location",
                            source = SafeString(note.source), evidence = "saved",
                            worldX = x, worldY = y, mapID = note.mapID,
                            coordinateSpaceID = space, distance = distance,
                            favorite = favorite(note) == true,
                            focused = focusKey ~= nil and focusKey == key
                                or (focusedTarget and points.Matches(note, focusedTarget, true)) or false }
                    end
                end
            end
        end
    end

    local candidates = {}
    for _, entry in ipairs(live) do candidates[#candidates + 1] = entry.point end
    for _, point in ipairs(saved) do candidates[#candidates + 1] = point end
    table.sort(candidates, function(left, right)
        if left.focused ~= right.focused then return left.focused end
        if left.favorite ~= right.favorite then return left.favorite end
        if left.evidence ~= right.evidence then return left.evidence == "live" end
        if left.distance ~= right.distance then return left.distance < right.distance end
        return tostring(left.key or "") < tostring(right.key or "")
    end)
    result.totalEligibleCount = #candidates
    for index = 1, math.min(#candidates, 256) do result.points[index] = candidates[index] end
    if mode == "pack" then
        if not HasPackSource(settings) then
            result.reason = "No Map Pack Selected"
        elseif #saved == 0 and not settings.vignetteRadarSourceFusion
            and addon.VignetteRadarPOIs and addon.VignetteRadarPOIs.ResolveSource
            and not addon.VignetteRadarPOIs.ResolveSource(mapID,
                settings.vignetteRadarPOISource) then
            result.reason = "Map Pack Unavailable"
        end
    end
    return result
end

function Data.GetSnapshot(mode)
    mode = mode == "live" and "live" or mode == "pack" and "pack" or "mixed"
    local generation = addon._spatialGeneration or 0
    if not cache or cache.generation ~= generation or cache.sourceMode ~= mode then
        cache = Build(mode, generation)
    end
    return cache
end

return Data
