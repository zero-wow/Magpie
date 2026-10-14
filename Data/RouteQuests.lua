local _, addon = ...
if type(addon) ~= "table" then return end

-- Quest routes can look beyond the current map without making map-wide API
-- calls in a frame update. At most two neighboring maps and eight quest-log
-- entries are read on each existing radar scan; results are reused between scans.
local API = {}
addon.VignetteRadarRouteQuests = API

local MAX_MAPS, MAPS_PER_SCAN, LOGS_PER_SCAN = 48, 2, 8
local MAX_RECORDS, MAX_STARTS, MAX_RESULTS = 64, 32, 128
local cache, order, currentMap, cursor = {}, {}, nil, 1
local context, logItems, logCursor, logCount, logRefreshAt = nil, {}, nil, 0, 0
local nextMapScanAt = 0
-- Candidates() is rebuilt only after the pool data changes (revision),
-- the quest-start setting flips, or a listed map entry expires.
local revision, candidates, candidatesRevision, candidatesStarts, candidatesUntil = 0, nil, -1, nil, 0

local function Changed() revision = revision + 1 end

-- /vrtrace (Core/Trace.lua): pool scans and candidate rebuilds log as "pool".
local TraceLib = addon.Trace
local function Trace(fmt, ...)
    if TraceLib then TraceLib.Log("pool", fmt, ...) end
end

local IsSecret, Number = addon.Secret.IsSecret, addon.Secret.Number
local Field, Call = addon.Secret.Field, addon.Secret.Call

local function Length(list)
    if IsSecret(list) or type(list) ~= "table" then return 0 end
    local ok, count = pcall(function() return #list end)
    return ok and Number(count) or 0
end

local function Now()
    return Number(Call(_G, "GetTime")) or 0
end

local function Position(mapID, x, y)
    if not (context and Number(mapID) and Number(x) and Number(y)
        and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
    local ok, worldX, worldY, instanceID = pcall(function()
        return context.mapToWorld(mapID, context.mapVector(x, y))
    end)
    if not ok or not (Number(worldX) and Number(worldY)) then return nil end
    if Number(context.player.instanceID) and Number(instanceID)
        and context.player.instanceID ~= instanceID then return nil end
    return worldX, worldY, instanceID
end

local function WaypointMap(mapID)
    if not (Number(mapID) and C_Map) then return false end
    if type(C_Map.CanSetUserWaypointOnMap) ~= "function" then return true end
    local allowed = Call(C_Map, "CanSetUserWaypointOnMap", mapID)
    return allowed ~= false and not (type(issecretvalue) == "function"
        and issecretvalue(allowed))
end

local function Continent(mapID)
    local seen = {}
    for _ = 1, 12 do
        if not Number(mapID) or seen[mapID] then break end
        seen[mapID] = true
        local info = Call(C_Map, "GetMapInfo", mapID)
        local mapType = Field(info, "mapType")
        if mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2) then
            return mapID
        end
        mapID = Number(Field(info, "parentMapID"))
    end
end

local function BuildOrder(mapID)
    Changed()
    currentMap, order, cursor = mapID, {}, 1
    local continent = Continent(mapID)
    if not continent or type(C_Map.GetMapChildrenInfo) ~= "function" then return end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local children = Call(C_Map, "GetMapChildrenInfo", continent, zoneType, true)
    if IsSecret(children) or type(children) ~= "table" then return end
    local px, py = Number(context.player.worldX), Number(context.player.worldY)
    if not (px and py) then return end
    local seen = {}
    for index = 1, math.min(Length(children), 128) do
        local id = Number(Field(children[index], "mapID"))
        if id and id ~= mapID and not seen[id] and WaypointMap(id) then
            seen[id] = true
            local x, y = Position(id, .5, .5)
            if x and y then
                local dx, dy = x - px, y - py
                order[#order + 1] = { id = id, distance2 = dx * dx + dy * dy }
            end
        end
    end
    table.sort(order, function(a, b)
        if a.distance2 ~= b.distance2 then return a.distance2 < b.distance2 end
        return a.id < b.id
    end)
    while #order > MAX_MAPS do order[#order] = nil end
end

local function Add(items, seen, item)
    if #items >= MAX_RECORDS then return end
    local id = tostring(item.questID) .. ":" .. tostring(item.availableStart)
        .. ":" .. math.floor(item.mapX * 10000 + .5)
        .. ":" .. math.floor(item.mapY * 10000 + .5)
    if seen[id] then return end
    seen[id] = true
    items[#items + 1] = item
end

local function ScanMap(mapID, includeStarts)
    local items, seen = {}, {}
    local records = Call(C_QuestLog, "GetQuestsOnMap", mapID)
    if not IsSecret(records) and type(records) == "table" then
        for index = 1, math.min(Length(records), MAX_RECORDS) do
            local record = records[index]
            local questID = Number(Field(record, "questID"))
            local x, y = Number(Field(record, "x")), Number(Field(record, "y"))
            if questID and x and y then
                local worldX, worldY, instanceID = Position(mapID, x, y)
                if worldX then
                    Add(items, seen, { kind = "quest", questID = questID,
                        name = Field(record, "name") or Call(C_QuestLog,
                            "GetTitleForQuestID", questID) or "Quest Objective",
                        mapID = mapID, mapX = x, mapY = y,
                        worldX = worldX, worldY = worldY, instanceID = instanceID })
                end
            end
        end
    end
    if includeStarts and addon.VignetteRadarQuestData then
        local starts = addon.VignetteRadarQuestData.GetAvailableQuestStarts(mapID)
        for index = 1, math.min(#starts, MAX_STARTS) do
            local start = starts[index]
            local onQuest = Call(C_QuestLog, "IsOnQuest", start.questID)
            if onQuest ~= true then
                local worldX, worldY, instanceID = Position(mapID, start.x, start.y)
                if worldX then
                    Add(items, seen, { kind = "quest", availableStart = true,
                        questID = start.questID, questLineID = start.questLineID,
                        name = start.questName or start.questLineName or "Available Quest",
                        mapID = mapID, mapX = start.x, mapY = start.y,
                        worldX = worldX, worldY = worldY, instanceID = instanceID })
                end
            end
        end
    end
    return items
end

local function ScanLog()
    if not C_QuestLog then return end
    local now = Now()
    if not logCursor and now < logRefreshAt then return end
    Changed()
    if not logCursor then
        logItems, logCursor = {}, 1
        logCount = math.min(Number(Call(C_QuestLog, "GetNumQuestLogEntries")) or 0, 128)
    end
    for _ = 1, LOGS_PER_SCAN do
        if logCursor > logCount then
            logCursor, logRefreshAt = nil, now + 30
            break
        end
        local questID = Number(Call(C_QuestLog, "GetQuestIDForLogIndex", logCursor))
        logCursor = logCursor + 1
        if questID then
            local mapID, x, y = Call(C_QuestLog, "GetNextWaypoint", questID)
            if mapID ~= context.mapID and WaypointMap(mapID) then
                local worldX, worldY, instanceID = Position(mapID, x, y)
                if worldX then
                    logItems[#logItems + 1] = { kind = "quest", questID = questID,
                        name = Call(C_QuestLog, "GetTitleForQuestID", questID)
                            or "Quest Objective",
                        mapID = mapID, mapX = x, mapY = y,
                        worldX = worldX, worldY = worldY, instanceID = instanceID }
                end
            end
        end
    end
end

function API.Invalidate(reason)
    Changed()
    logItems, logCursor, logRefreshAt = {}, nil, 0
    if reason == "map" then
        currentMap, nextMapScanAt = nil, 0
    else
        nextMapScanAt = math.min(nextMapScanAt, Now() + 1)
    end
    for _, entry in pairs(cache) do
        entry.expires = reason == "map" and 0 or math.min(entry.expires, Now() + 1)
        entry.emptyRetries = 0
    end
end
if addon.Bus then
    addon.Bus.On("MAP_CHANGED", function() API.Invalidate("map") end)
    addon.Bus.On("QUEST_CHANGED", function() API.Invalidate("quest") end)
end

function API.Bind(mapID, player, mapToWorld, mapVector, settings)
    if not (Number(mapID) and type(player) == "table"
        and type(mapToWorld) == "function" and type(mapVector) == "function") then
        context = nil
        return
    end
    if context and context.mapID ~= mapID then
        logItems, logCursor, logRefreshAt = {}, nil, 0
    end
    Changed()
    context = { mapID = mapID, player = player, mapToWorld = mapToWorld,
        mapVector = mapVector, settings = settings }
end

-- An active quest may have a next-step waypoint without a quest-level map
-- record or a watch. Read only the current route's quest; QuestData caches
-- the Blizzard lookup between the existing radar scans.
function API.CurrentQuestWaypoint(questID)
    if not (context and Number(questID) and addon.VignetteRadarQuestData
        and type(addon.VignetteRadarQuestData.GetNextStep) == "function") then return nil end
    local step = addon.VignetteRadarQuestData.GetNextStep(questID, context.mapID)
    if not (step and Number(step.mapID) and Number(step.x) and Number(step.y)
        and WaypointMap(step.mapID)) then return nil end
    local worldX, worldY, instanceID = Position(step.mapID, step.x, step.y)
    if not worldX then return nil end
    return { kind = "quest", questID = questID,
        name = Call(C_QuestLog, "GetTitleForQuestID", questID) or "Quest Objective",
        nextStep = step, mapID = step.mapID, mapX = step.x, mapY = step.y,
        worldX = worldX, worldY = worldY, instanceID = instanceID }
end

function API.Tick(force)
    if not context or context.settings.vignetteRadarAutoRouteNearbyZones == false then return end
    if not force and not (addon.VignetteRadarWorldFocus
        and addon.VignetteRadarWorldFocus.WantsQuestPool
        and addon.VignetteRadarWorldFocus.WantsQuestPool()) then return end
    local before = #logItems
    if currentMap ~= context.mapID then BuildOrder(context.mapID) end
    ScanLog()
    local now = Now()
    if not force and now < nextMapScanAt then return end
    nextMapScanAt = now + 5
    local scanned, checked = 0, 0
    while #order > 0 and scanned < MAPS_PER_SCAN and checked < #order do
        local mapID = order[cursor].id
        cursor = cursor % #order + 1
        checked = checked + 1
        local previous = cache[mapID]
        if not previous or now >= previous.expires then
            local items = ScanMap(mapID,
                context.settings.vignetteRadarAutoRouteQuestStarts ~= false)
            local emptyRetries = #items == 0
                and ((previous and previous.emptyRetries or 0) + 1) or 0
            Changed()
            cache[mapID] = { items = items,
                emptyRetries = emptyRetries,
                expires = now + (#items > 0 and 120
                    or emptyRetries == 1 and 12 or 90) }
            scanned = scanned + 1
            Trace("Tick scanned map %s: %s points (empty retries %s)", mapID, #items, emptyRetries)
        end
    end
    Trace("Tick force=%s map=%s maps=%s scanned=%s log=%s->%s (%s)", force, context.mapID, #order,
        scanned, before, #logItems, logCursor and ("reading " .. logCursor .. "/" .. logCount) or "log done")
end

-- The returned list is shared until the pool changes; callers only read it.
function API.Candidates()
    if not context or context.settings.vignetteRadarAutoRouteNearbyZones == false then
        return {}
    end
    local starts = context.settings.vignetteRadarAutoRouteQuestStarts ~= false
    local now = Now()
    if candidates and candidatesRevision == revision and candidatesStarts == starts
        and now < candidatesUntil then
        return candidates
    end
    local result, validUntil = {}, math.huge
    candidates, candidatesRevision, candidatesStarts = result, revision, starts
    for _, item in ipairs(logItems) do
        if #result >= MAX_RESULTS then candidatesUntil = validUntil; return result end
        result[#result + 1] = item
    end
    for _, map in ipairs(order) do
        local entry = cache[map.id]
        if entry and entry.expires > now then
            if entry.expires < validUntil then validUntil = entry.expires end
            for _, item in ipairs(entry.items) do
                if #result >= MAX_RESULTS then candidatesUntil = validUntil; return result end
                if not item.availableStart or starts then
                    result[#result + 1] = item
                end
            end
        end
    end
    candidatesUntil = validUntil
    Trace("Candidates rebuilt: %s (log %s, starts %s, revision %s)", #result, #logItems, starts, revision)
    return result
end

-- Report cached counts only. Diagnostics must never trigger a map or quest scan.
function API.Diagnostics()
    local localPoints, otherPoints = 0, 0
    for _, item in ipairs(logItems) do
        if context and item.mapID == context.mapID then
            localPoints = localPoints + 1
        else otherPoints = otherPoints + 1 end
    end
    return { logRead = logCursor and logCursor - 1 or logCount,
        logTotal = logCount, localPoints = localPoints, otherPoints = otherPoints }
end
