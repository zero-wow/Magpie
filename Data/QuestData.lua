local _, addon = ...
if type(addon) ~= "table" then return end

-- Read-only Blizzard quest metadata. The radar decides whether a returned map
-- point can be projected; a waypoint on another map is never moved here.
local API = {}
addon.VignetteRadarQuestData = API

local stepCache, stepCacheCount, stepCacheMap = {}, 0, nil
local startsCache, requestedMaps, startsCacheCount = {}, {}, 0
local objectiveCache, objectiveCacheCount = {}, 0
-- questID -> { at, text }; the route card asks for the hint five times a second.
local hintCache, hintCacheCount = {}, 0
local STEP_AGE, STARTS_AGE, MAX_STEPS, MAX_STARTS = 2, 5, 64, 80
local MAX_CACHED_MAPS = 64

local IsSecret, Number = addon.Secret.IsSecret, addon.Secret.Number
local Field, Call, SecretText = addon.Secret.Field, addon.Secret.Call, addon.Secret.Text

local function ID(value)
    value = Number(value)
    return value and value > 0 and value % 1 == 0 and value or nil
end

local function Position(value)
    value = Number(value)
    return value and value >= 0 and value <= 1 and value or nil
end

-- Quest text is cut to fit rather than dropped.
local function Text(value, limit)
    return SecretText(value, limit or 160, true)
end

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and Number(value) or 0
end

local function Copy(record)
    if not record then return nil end
    local result = {}
    for key, value in pairs(record) do result[key] = value end
    return result
end

local function ObjectiveLabelAndCount(label)
    local current, required = label:match("^%s*(%d+)%s*/%s*(%d+)%s*[:%-]?%s*")
    if current then
        label = label:gsub("^%s*%d+%s*/%s*%d+%s*[:%-]?%s*", "", 1)
    else
        current, required = label:match("(%d+)%s*/%s*(%d+)%s*$")
        if current then label = label:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "") end
    end
    return label, tonumber(current), tonumber(required)
end

function API.Invalidate(reason)
    stepCache, stepCacheCount, stepCacheMap = {}, 0, nil
    startsCache, startsCacheCount = {}, 0
    objectiveCache, objectiveCacheCount = {}, 0
    hintCache, hintCacheCount = {}, 0
    if reason ~= "quest" then requestedMaps = {} end
end
-- Quest and map events reach this cache through the bus, before the radar
-- schedules its rescan (subscription order follows the TOC).
if addon.Bus then
    addon.Bus.On("MAP_CHANGED", function() API.Invalidate("map") end)
    addon.Bus.On("QUEST_CHANGED", function() API.Invalidate("quest") end)
end

-- Quest objectives are read at most once per two seconds between quest events,
-- even though the movable arrow redraws much more often.
function API.GetObjectiveSummary(questID, hint)
    questID = ID(questID)
    if not questID then return nil end
    local now = Now()
    local cached = objectiveCache[questID]
    if not cached or now - cached.at >= STEP_AGE then
        local raw = Call(C_QuestLog, "GetQuestObjectives", questID)
        local rows = {}
        if not IsSecret(raw) and type(raw) == "table" then
            local ok, count = pcall(function() return #raw end)
            if ok and Number(count) then
                for index = 1, math.min(count, 16) do
                    local objective = Field(raw, index)
                    local label = Text(Field(objective, "text"), 150)
                    if label then
                        local current = Number(Field(objective, "numFulfilled"))
                        local required = Number(Field(objective, "numRequired"))
                        local fromText, totalText
                        label, fromText, totalText = ObjectiveLabelAndCount(label)
                        current = current or tonumber(fromText)
                        required = required or tonumber(totalText)
                        if label == "" then label = "Quest Objective" end
                        rows[#rows + 1] = { label = label,
                            count = current and required and required > 0
                                and (math.floor(current) .. "/" .. math.floor(required)) or nil,
                            finished = Field(objective, "finished") == true }
                    end
                end
            end
        end
        if objectiveCacheCount >= MAX_STEPS then objectiveCache, objectiveCacheCount = {}, 0 end
        if not objectiveCache[questID] then objectiveCacheCount = objectiveCacheCount + 1 end
        cached = { at = now, rows = rows }
        objectiveCache[questID] = cached
    end
    local wanted = Text(hint, 160)
    if wanted then wanted = ObjectiveLabelAndCount(wanted); wanted = wanted:lower() end
    local first
    for _, row in ipairs(cached.rows) do
        if not row.finished then
            if wanted and wanted ~= "" and (row.label:lower():find(wanted, 1, true)
                or wanted:find(row.label:lower(), 1, true)) then return Copy(row) end
            first = first or row
        end
    end
    if not first and #cached.rows == 0 then
        local fallback = Text(hint, 150)
        if fallback then
            local current, required
            fallback, current, required = ObjectiveLabelAndCount(fallback)
            return { label = fallback ~= "" and fallback or "Quest Objective",
                count = current and required and (current .. "/" .. required) or nil }
        end
    end
    return Copy(first)
end


-- One line saying what to do next: Blizzard's route hint ("Take the portal
-- to ...") while one applies, else the first unfinished objective.
function API.GetNextStepLine(questID)
    questID = ID(questID)
    if not questID then return nil end
    local now = Now()
    local cached = hintCache[questID]
    if not cached or now - cached.at >= STEP_AGE or now < cached.at then
        if not cached and hintCacheCount >= MAX_STEPS then
            hintCache, hintCacheCount = {}, 0
        end
        if not cached then
            cached = {}
            hintCache[questID] = cached
            hintCacheCount = hintCacheCount + 1
        end
        cached.at = now
        cached.text = Text(Call(C_QuestLog, "GetNextWaypointText", questID), 120) or false
    end
    local hint = cached.text
    if hint and hint ~= "" then return hint, true end
    local objective = API.GetObjectiveSummary(questID)
    if not objective then return nil end
    return objective.count and (objective.label .. " " .. objective.count) or objective.label, false
end


-- True while the player stands inside the quest's objective area: the
-- quest's map blob, or the area of a bonus objective or world quest.
function API.IsQuestInArea(questID)
    questID = ID(questID)
    if not questID then return false end
    if Call(C_Minimap, "IsInsideQuestBlob", questID) == true then return true end
    if type(GetTaskInfo) == "function" then
        local ok, isInArea = pcall(GetTaskInfo, questID)
        if ok and isInArea == true then return true end
    end
    return false
end

-- Returns a map point when Blizzard provides one and its separate instruction
-- text when available. `onCurrentMap` is false for a waypoint on another map.
function API.GetNextStep(questID, mapID)
    questID, mapID = ID(questID), ID(mapID)
    if not questID then return nil end
    if stepCacheMap ~= mapID then
        stepCache, stepCacheCount, stepCacheMap = {}, 0, mapID
    end
    local now = Now()
    local cached = stepCache[questID]
    if cached and now - cached.at < STEP_AGE then return Copy(cached.value) end

    local result = { questID = questID }
    local x, y
    if mapID then
        x, y = Call(C_QuestLog, "GetNextWaypointForMap", questID, mapID)
        x, y = Position(x), Position(y)
        if x and y then
            result.mapID, result.x, result.y, result.onCurrentMap = mapID, x, y, true
        end
    end
    if not result.x then
        local waypointMap
        waypointMap, x, y = Call(C_QuestLog, "GetNextWaypoint", questID)
        waypointMap, x, y = ID(waypointMap), Position(x), Position(y)
        if waypointMap and x and y then
            result.mapID, result.x, result.y = waypointMap, x, y
            result.onCurrentMap = waypointMap == mapID
        end
    end
    result.text = Text(Call(C_QuestLog, "GetNextWaypointText", questID), 160)
    if not (result.x or result.text) then result = nil end

    if stepCacheCount >= MAX_STEPS then stepCache, stepCacheCount = {}, 0 end
    if not stepCache[questID] then stepCacheCount = stepCacheCount + 1 end
    stepCache[questID] = { at = now, value = result }
    return Copy(result)
end

local function Floor(value)
    value = Number(value)
    if value == 0 then return "above" end
    if value == 1 then return "below" end
    if value == 2 then return "same" end
    return nil
end

local function ReadStarts(mapID)
    local raw = Call(C_QuestLine, "GetAvailableQuestLines", mapID)
    if IsSecret(raw) or type(raw) ~= "table" then return {} end
    local result, seen = {}, {}
    local ok, count = pcall(function() return #raw end)
    if not ok or not Number(count) then return result end
    for index = 1, math.min(count, MAX_STARTS) do
        local read, entry = pcall(function() return raw[index] end)
        if not read then entry = nil end
        local questID, lineID = ID(Field(entry, "questID")), ID(Field(entry, "questLineID"))
        local x, y = Position(Field(entry, "x")), Position(Field(entry, "y"))
        if questID and lineID and x and y and Field(entry, "isQuestStart") == true
            and Field(entry, "isHidden") == false and not seen[lineID] then
            seen[lineID] = true
            result[#result + 1] = {
                questID = questID, questLineID = lineID,
                questName = Text(Field(entry, "questName"), 120),
                questLineName = Text(Field(entry, "questLineName"), 120),
                mapID = mapID, startMapID = ID(Field(entry, "startMapID")), x = x, y = y,
                isCampaign = Field(entry, "isCampaign") == true,
                isImportant = Field(entry, "isImportant") == true,
                floor = Floor(Field(entry, "floorLocation")),
            }
        end
    end
    return result
end

-- Blizzard supplies only lines currently available on this map. It may return
-- an empty list until its own map request has loaded; never invent quest starts.
local function WarbandCompletedStartHidden(questID, tracking)
    questID = ID(questID)
    if not questID then return false end
    if IsSecret(tracking) or tracking ~= false then return false end
    local completed = Call(C_QuestLog, "IsQuestFlaggedCompletedOnAccount", questID)
    if IsSecret(completed) or completed ~= true then return false end
    local onQuest = Call(C_QuestLog, "IsOnQuest", questID)
    return not IsSecret(onQuest) and onQuest ~= true
end

function API.IsWarbandCompletedStartHidden(questID)
    return WarbandCompletedStartHidden(questID,
        Call(C_Minimap, "IsTrackingAccountCompletedQuests"))
end

local function VisibleStarts(entries)
    local copy = {}
    local tracking = Call(C_Minimap, "IsTrackingAccountCompletedQuests")
    for _, entry in ipairs(entries) do
        if not WarbandCompletedStartHidden(entry.questID, tracking) then
            copy[#copy + 1] = Copy(entry)
        end
    end
    return copy
end

function API.GetAvailableQuestStarts(mapID)
    mapID = ID(mapID)
    if not mapID then return {} end
    local now = Now()
    local cached = startsCache[mapID]
    if cached and now - cached.at < STARTS_AGE then
        return VisibleStarts(cached.value)
    end
    if not requestedMaps[mapID] then
        Call(C_QuestLine, "RequestQuestLinesForMap", mapID)
        requestedMaps[mapID] = true
    end
    local result = ReadStarts(mapID)
    if startsCacheCount >= MAX_CACHED_MAPS then startsCache, startsCacheCount = {}, 0 end
    if not startsCache[mapID] then startsCacheCount = startsCacheCount + 1 end
    startsCache[mapID] = { at = now, value = result }
    return VisibleStarts(result)
end
