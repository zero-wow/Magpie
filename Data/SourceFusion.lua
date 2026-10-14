local _, addon = ...
if type(addon) ~= "table" then return end

-- A saved POI remains a possible location. Fusion changes its presentation,
-- never its evidence class or the live-vignette detection rules.
local Fusion = {}
addon.VignetteRadarSourceFusion = Fusion

local MAX_SOURCES, MAX_POINTS, MAX_CANDIDATES = 8, 2048, 48
local MAX_SNAPSHOTS, CACHE_SECONDS = 32, 30
local snapshots, snapshotOrder = {}, {}

local Safe, Field = addon.Secret.Safe, addon.Secret.Field
local IDs = addon.VignetteRadarPoints.IDs
local ID_FIELDS = addon.VignetteRadarPoints.ID_FIELDS

local function Finite(value)
    return Safe(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge and value or nil
end

local function Name(value)
    if not Safe(value) or type(value) ~= "string" then return nil end
    local result = value:lower():gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", ""):gsub("[^%w]+", " "):match("^%s*(.-)%s*$")
    if not result or #result < 3 or result == "map note"
        or result == "mob location" or result == "treasure location"
        or result == "item location" or result == "cave entrance" then return nil end
    return result
end

local function Compatible(a, b)
    if a.mapID ~= b.mapID or a.kind ~= b.kind then return false end
    if a.instanceID and b.instanceID and a.instanceID ~= b.instanceID then return false end
    if a.source == b.source then return false end
    local ai, bi = a._identity, b._identity
    local matchedID = false
    for index = 1, #ID_FIELDS do
        local field = ID_FIELDS[index]
        local left, right = ai[field], bi[field]
        if left and right then
            if left ~= right then return false end
            matchedID = true
        end
    end
    return matchedID or (a._name and a._name == b._name) or false
end

local function Distance(a, b)
    local ax, ay, bx, by = Finite(a.mapX), Finite(a.mapY), Finite(b.mapX), Finite(b.mapY)
    if not ax or not ay or not bx or not by then return nil end
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function Point(entry)
    if type(entry) ~= "table" then return nil end
    local mapID, x, y = Field(entry, "mapID"), Finite(Field(entry, "mapX")), Finite(Field(entry, "mapY"))
    local kind, source = Field(entry, "kind"), Field(entry, "source")
    if type(mapID) ~= "number" or not x or not y or x < 0 or x > 1 or y < 0 or y > 1
        or type(kind) ~= "string" or type(source) ~= "string" or source == "" then return nil end
    local point = {
        key = Field(entry, "key"), mapID = mapID, mapX = x, mapY = y,
        worldX = Finite(Field(entry, "worldX")), worldY = Finite(Field(entry, "worldY")),
        instanceID = Field(entry, "instanceID"), source = source, kind = kind,
        name = Field(entry, "name"), note = Field(entry, "note"),
        npcID = Field(entry, "npcID"), objectID = Field(entry, "objectID"),
        questID = Field(entry, "questID"), icon = Field(entry, "icon"),
        route = Field(entry, "route"), parentCoord = Field(entry, "parentCoord"),
        evidence = Field(entry, "evidence") or "saved",
        _original = entry,
    }
    point._name, point._identity = Name(point.name), IDs(point)
    return point
end

local function Preferred(point, preferred)
    return point.source == preferred and 1 or 0
end

local function Reconcile(group, preferred)
    local chosen = group.points[1]
    for index = 2, #group.points do
        local candidate = group.points[index]
        local live = candidate.evidence == "live" and 1 or 0
        local chosenLive = chosen.evidence == "live" and 1 or 0
        if live > chosenLive or (live == chosenLive
            and Preferred(candidate, preferred) > Preferred(chosen, preferred)) then
            chosen = candidate
        end
    end
    local output, conflicts, provenance = {}, {}, {}
    for key, value in pairs(chosen._original) do output[key] = value end
    output.key = chosen.key or (chosen.source .. ":" .. chosen.mapID .. ":" .. chosen.mapX .. ":" .. chosen.mapY)
    output.displayPoint = chosen._original
    output.evidence = chosen.evidence
    output.sources = {}
    for _, point in ipairs(group.points) do
        output.sources[#output.sources + 1] = point.source
        provenance[#provenance + 1] = {
            source = point.source, key = point.key, name = point.name,
            mapID = point.mapID, mapX = point.mapX, mapY = point.mapY,
            kind = point.kind, evidence = point.evidence,
            npcID = point.npcID, objectID = point.objectID, questID = point.questID,
        }
        if point ~= chosen then
            if point.name ~= chosen.name then conflicts.names = true end
            if point.mapX ~= chosen.mapX or point.mapY ~= chosen.mapY then conflicts.coordinates = true end
        end
    end
    output.provenance, output.conflicts = provenance, conflicts
    output.matchCount = #group.points
    return output
end

-- Pure merger. Its grid searches at most 9 cells and MAX_CANDIDATES entries
-- per point; overload leaves conservative separate markers instead of stalling.
function Fusion.Fuse(entries, options)
    options = type(options) == "table" and options or {}
    local threshold = Finite(options.conflictDistance) or .002
    threshold = math.max(.0002, math.min(.01, threshold))
    local grid, groups, stats = {}, {}, { input = 0, accepted = 0, merged = 0, limited = false }
    local preferred = type(options.preferredSource) == "string" and options.preferredSource or nil
    if type(entries) ~= "table" then return {}, stats end
    for index = 1, math.min(#entries, MAX_POINTS) do
        stats.input = stats.input + 1
        local point = Point(entries[index])
        if point then
            stats.accepted = stats.accepted + 1
            local cx, cy = math.floor(point.mapX / threshold), math.floor(point.mapY / threshold)
            local prefix = tostring(point.mapID) .. ":" .. point.kind .. ":"
            local best, bestDistance, examined = nil, threshold, 0
            for gx = cx - 1, cx + 1 do
                for gy = cy - 1, cy + 1 do
                    local cell = grid[prefix .. gx .. ":" .. gy]
                    if cell then
                        for _, group in ipairs(cell) do
                            examined = examined + 1
                            if examined > MAX_CANDIDATES then stats.limited = true; break end
                            local representative = group.points[1]
                            local distance = Distance(point, representative)
                            if distance and distance <= bestDistance and Compatible(point, representative) then
                                local sourceAlreadyPresent = false
                                for _, member in ipairs(group.points) do
                                    if member.source == point.source or not Compatible(point, member) then
                                        sourceAlreadyPresent = true; break
                                    end
                                end
                                if not sourceAlreadyPresent then best, bestDistance = group, distance end
                            end
                        end
                    end
                    if examined > MAX_CANDIDATES then break end
                end
                if examined > MAX_CANDIDATES then break end
            end
            if best then
                best.points[#best.points + 1] = point
                stats.merged = stats.merged + 1
            else
                local group = { points = { point } }
                groups[#groups + 1] = group
                local key = prefix .. cx .. ":" .. cy
                local cell = grid[key]
                if not cell then cell = {}; grid[key] = cell end
                cell[#cell + 1] = group
            end
        end
    end
    if #entries > MAX_POINTS then stats.limited = true end
    local output = {}
    for _, group in ipairs(groups) do output[#output + 1] = Reconcile(group, preferred) end
    stats.output = #output
    return output, stats
end

local function CacheKey(mapID, source)
    return tostring(mapID) .. "\031" .. source
end

function Fusion.Invalidate(source, mapID)
    if source == nil and mapID == nil then snapshots, snapshotOrder = {}, {}; return end
    for key, snapshot in pairs(snapshots) do
        if (source == nil or snapshot.source == source)
            and (mapID == nil or snapshot.mapID == mapID) then snapshots[key] = nil end
    end
    local retained = {}
    for _, key in ipairs(snapshotOrder) do
        if snapshots[key] then retained[#retained + 1] = key end
    end
    snapshotOrder = retained
end

local function Snapshot(mapID, source, mapToWorld, mapVector)
    local key = CacheKey(mapID, source)
    local now = type(GetTime) == "function" and GetTime() or nil
    local cached = snapshots[key]
    if cached and now and cached.at and now >= cached.at and now - cached.at < CACHE_SECONDS then
        return cached.points
    end
    local pois = addon.VignetteRadarPOIs
    local ok, points = pcall(pois.Collect, mapID, source, mapToWorld, mapVector)
    if not ok or type(points) ~= "table" then points = {} end
    if #points > 768 then
        local bounded = {}
        for index = 1, 768 do bounded[index] = points[index] end
        points = bounded
    end
    if not cached then
        snapshotOrder[#snapshotOrder + 1] = key
        if #snapshotOrder > MAX_SNAPSHOTS then
            snapshots[table.remove(snapshotOrder, 1)] = nil
        end
    end
    snapshots[key] = { source = source, mapID = mapID, at = now, points = points }
    return points
end

-- selected is an ordered list of explicit source IDs. The caller owns the
-- single-source default and may pass options.preferredSource for this zone.
function Fusion.Collect(mapID, selected, mapToWorld, mapVector, options)
    local empty = { input = 0, accepted = 0, merged = 0, output = 0, sources = 0, limited = false }
    local pois = addon.VignetteRadarPOIs
    if type(mapID) ~= "number" or type(selected) ~= "table"
        or type(mapToWorld) ~= "function" or type(mapVector) ~= "function"
        or type(pois) ~= "table" or type(pois.Collect) ~= "function"
        or type(pois.ZoneSources) ~= "function" then return {}, empty end
    local available = {}
    for _, source in ipairs(pois.ZoneSources(mapID)) do
        if type(source) == "table" and source.enabled and type(source.id) == "string" then
            available[source.id] = source.mapID
        end
    end
    local all, seen, sources = {}, {}, 0
    for _, id in ipairs(selected) do
        if sources >= MAX_SOURCES or #all >= MAX_POINTS then empty.limited = true; break end
        if type(id) == "string" and available[id] and not seen[id] then
            seen[id], sources = true, sources + 1
            local points = Snapshot(available[id], id, mapToWorld, mapVector)
            for index = 1, math.min(#points, MAX_POINTS - #all) do
                all[#all + 1] = points[index]
            end
            if #all >= MAX_POINTS then empty.limited = true end
        end
    end
    local fused, stats = Fusion.Fuse(all, options)
    stats.sources, stats.limited = sources, stats.limited or empty.limited
    return fused, stats
end
