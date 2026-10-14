local _, addon = ...
if type(addon) ~= "table" then return end

-- Confirmed player-at-event observations are hints, not exact NPC or objective
-- coordinates. Keep them separate from the map packs and Blizzard's points.
local API = {}
addon.VignetteRadarOutcomeLearning = API

local MAX_ENTRIES, MAX_SAMPLES, MAX_WATCHES, MAX_OBJECTIVES = 256, 3, 40, 16
-- alive maps a live rare's key to { item = target, rewardDone = ..., seenAt = ... }.
-- The wrapper keeps our state off the radar's live target tables.
local alive, questState, questPoints = {}, {}, {}
local hasBaseline = false

local Number, Field = addon.Secret.Number, addon.Secret.Field

local function ID(value)
    value = Number(value)
    return value and value > 0 and value % 1 == 0 and value or nil
end

local function Snapshot()
    local radar = addon.VignetteRadarAPI
    if not (radar and type(radar.GetPlayerSnapshot) == "function") then return nil end
    local ok, value = pcall(radar.GetPlayerSnapshot)
    if not ok or type(value) ~= "table" then return nil end
    if not (ID(value.mapID) and Number(value.mapX) and Number(value.mapY)
        and value.mapX >= 0 and value.mapX <= 1
        and value.mapY >= 0 and value.mapY <= 1
        and Number(value.worldX) and Number(value.worldY)) then return nil end
    local result = {
        mapID = value.mapID, mapX = value.mapX, mapY = value.mapY,
        worldX = value.worldX, worldY = value.worldY,
        instanceID = ID(value.instanceID),
    }
    result.z = API.PlayerHeight(result)
    return result
end

function API.PlayerHeight(snapshot)
    if not (snapshot and Number(snapshot.worldX) and Number(snapshot.worldY)
        and type(UnitPosition) == "function") then return nil end
    local read, x, y, z, instanceID = pcall(UnitPosition, "player")
    if not (read and Number(x) and Number(y) and Number(z)
        and (not ID(snapshot.instanceID) or snapshot.instanceID == ID(instanceID))) then
        return nil
    end
    local dx, dy = x - snapshot.worldX, y - snapshot.worldY
    return dx * dx + dy * dy <= 64 and z or nil
end

API.CapturePlayer = Snapshot

local function Entries()
    local db = addon.GetSettings and addon.GetSettings()
    if type(db) ~= "table" then return nil end
    if type(db.vignetteRadarOutcomeLocations) ~= "table" then
        db.vignetteRadarOutcomeLocations = {}
    end
    return db.vignetteRadarOutcomeLocations
end

local function Record(kind, key, details, snapshot)
    if not (snapshot and type(key) == "string" and #key <= 100) then return false end
    local entries = Entries()
    if not entries then return false end
    local now = type(time) == "function" and time() or 0
    local entry = entries[key]
    if type(entry) ~= "table" then
        local count, oldestKey, oldestAt = 0, nil, nil
        for existingKey, existing in pairs(entries) do
            count = count + 1
            local at = type(existing) == "table" and Number(existing.lastAt) or 0
            if not oldestAt or at < oldestAt then oldestKey, oldestAt = existingKey, at end
        end
        if count >= MAX_ENTRIES and oldestKey then entries[oldestKey] = nil end
        entry = { samples = {} }
        entries[key] = entry
    end
    entry.kind, entry.lastAt = kind, now
    entry.name = type(details.name) == "string" and details.name:sub(1, 100) or kind
    entry.questID, entry.objectiveIndex = details.questID, details.objectiveIndex
    entry.npcID, entry.vignetteID = details.npcID, details.vignetteID
    entry.sourceMapID, entry.sourceMapX, entry.sourceMapY =
        details.sourceMapID, details.sourceMapX, details.sourceMapY
    if type(entry.samples) ~= "table" then entry.samples = {} end
    local samples = entry.samples
    samples[#samples + 1] = {
        mapID = snapshot.mapID, mapX = snapshot.mapX, mapY = snapshot.mapY,
        worldX = snapshot.worldX, worldY = snapshot.worldY,
        instanceID = snapshot.instanceID, z = snapshot.z, at = now,
    }
    while #samples > MAX_SAMPLES do table.remove(samples, 1) end
    return true
end

local function Distance(a, b)
    if not (a and b and Number(a.worldX) and Number(a.worldY)
        and Number(b.worldX) and Number(b.worldY)) then return nil end
    if ID(a.instanceID) and ID(b.instanceID)
        and a.instanceID ~= b.instanceID then return nil end
    local dx, dy = a.worldX - b.worldX, a.worldY - b.worldY
    return math.sqrt(dx * dx + dy * dy)
end

local function RewardComplete(questID)
    if not (ID(questID) and C_QuestLog
        and type(C_QuestLog.IsQuestFlaggedCompleted) == "function") then return nil end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if ok and type(done) == "boolean" then return done end
    return nil
end

local function RecordRare(source, info, snapshot)
    local distance = Distance(source, snapshot)
    if not distance or distance > 100 then return false end
    local objectGUID = Field(info, "objectGUID") or source.objectGUID
    local npcID = type(objectGUID) == "string"
        and tonumber(objectGUID:match("^[A-Za-z]+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
    local key = "rare:" .. tostring(source.mapID) .. ":"
        .. tostring(npcID or source.vignetteID or source.key)
    return Record("rare", key, {
        name = source.name, npcID = npcID, vignetteID = source.vignetteID,
        sourceMapID = source.mapID, sourceMapX = source.mapX,
        sourceMapY = source.mapY,
    }, snapshot)
end

function API.Sync(liveTargets, activeQuests)
    local current = {}
    local now = type(GetTime) == "function" and GetTime() or 0
    for index = 1, math.min(type(liveTargets) == "table" and #liveTargets or 0, 256) do
        local item = liveTargets[index]
        if item and item.isDead ~= true and (item.category == "rare" or item.isWorldBoss)
            and type(item.key) == "string" then
            local entry = alive[item.key]
            if entry then entry.item = item
            else entry = { item = item, rewardDone = RewardComplete(item.rewardQuestID) } end
            entry.seenAt = now
            current[item.key] = entry
        end
    end
    -- Keep a just-vanished live rare through the brief quest-event debounce.
    -- Disappearance itself never creates a kill observation.
    for guid, previous in pairs(alive) do
        if not current[guid] and Number(previous.seenAt)
            and now >= previous.seenAt
            and now - previous.seenAt <= 5 then
            current[guid] = previous
        end
    end
    alive = current
    questPoints = type(activeQuests) == "table" and activeQuests or {}
    if not hasBaseline then API.OnQuestEvent(false) end
end

function API.OnDeadVignette(vignetteGUID, info)
    local entry = type(vignetteGUID) == "string" and alive[vignetteGUID] or nil
    if not entry then return false end
    alive[vignetteGUID] = nil
    return RecordRare(entry.item, info, Snapshot())
end

local function ReadObjectives(questID)
    if not (C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function") then return nil end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table"
        or (issecretvalue and issecretvalue(objectives)) then return nil end
    local result = {}
    for index = 1, math.min(#objectives, MAX_OBJECTIVES) do
        local objective = objectives[index]
        local read, count, finished, label = pcall(function()
            return objective.numFulfilled, objective.finished, objective.text
        end)
        if not read or (issecretvalue and
            (issecretvalue(count) or issecretvalue(finished)
                or issecretvalue(label))) then return nil end
        result[index] = {
            count = Number(count) or 0, finished = finished == true,
            text = type(label) == "string" and label:sub(1, 100) or nil,
        }
    end
    return result
end

local function WatchedQuests()
    local result = {}
    if not (C_QuestLog and type(C_QuestLog.GetNumQuestWatches) == "function"
        and type(C_QuestLog.GetQuestIDForQuestWatchIndex) == "function") then return result end
    local ok, count = pcall(C_QuestLog.GetNumQuestWatches)
    if not ok or not Number(count) then return result end
    for index = 1, math.min(count, MAX_WATCHES) do
        local read, questID = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, index)
        questID = read and ID(questID) or nil
        if questID then result[questID] = true end
    end
    return result
end

local function NearestPoint(questID, snapshot)
    local nearest, nearestDistance
    for _, point in ipairs(questPoints) do
        if point.questID == questID then
            local distance = Distance(point, snapshot)
            if distance and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = point, distance
            end
        end
    end
    return nearestDistance and nearestDistance <= 150 and nearest or nil
end

function API.OnQuestEvent(recordProgress, eventSnapshot)
    if recordProgress then
        local rareSnapshot = eventSnapshot
        for guid, entry in pairs(alive) do
            if entry.rewardDone == false
                and RewardComplete(entry.item.rewardQuestID) == true then
                rareSnapshot = rareSnapshot or Snapshot()
                if RecordRare(entry.item, nil, rareSnapshot) then alive[guid] = nil
                else entry.rewardDone = true end
            end
        end
    end
    local watched = WatchedQuests()
    local nextState = {}
        local snapshot = eventSnapshot
    for questID in pairs(watched) do
        local objectives = ReadObjectives(questID)
        if objectives then
            nextState[questID] = objectives
            local previous = recordProgress and questState[questID]
            if previous then
                for index, objective in ipairs(objectives) do
                    local old = previous[index]
                    if old and (objective.count > old.count
                        or objective.finished and not old.finished) then
                        snapshot = snapshot or Snapshot()
                        if snapshot then
                            local source = NearestPoint(questID, snapshot)
                            Record("quest", "quest:" .. questID .. ":" .. index, {
                                name = objective.text or "Quest Objective",
                                questID = questID, objectiveIndex = index,
                                sourceMapID = source and source.mapID,
                                sourceMapX = source and source.mapX,
                                sourceMapY = source and source.mapY,
                            }, snapshot)
                        end
                    end
                end
            end
        end
    end
    questState, hasBaseline = nextState, true
end

function API.GetQuestHint(questID, mapID)
    questID, mapID = ID(questID), ID(mapID)
    if not (questID and mapID) then return nil end
    local objectives = ReadObjectives(questID)
    if not objectives then return nil end
    local entries = Entries()
    if not entries then return nil end
    for index, objective in ipairs(objectives) do
        if not objective.finished then
            local entry = entries["quest:" .. questID .. ":" .. index]
            local samples = type(entry) == "table" and entry.samples
            if type(samples) == "table" then
                for leftIndex = 1, #samples - 1 do
                    for rightIndex = leftIndex + 1, #samples do
                        local left, right = samples[leftIndex], samples[rightIndex]
                        local distance = type(left) == "table" and type(right) == "table"
                            and Distance(left, right)
                        if distance and left.mapID == mapID and right.mapID == mapID
                            and distance <= 40
                            and Number(left.mapX) and Number(left.mapY)
                            and Number(right.mapX) and Number(right.mapY) then
                            return {
                                mapX = (left.mapX + right.mapX) / 2,
                                mapY = (left.mapY + right.mapY) / 2,
                                objectiveIndex = index, text = objective.text,
                            }
                        end
                    end
                end
            end
        end
    end
end

function API.Count()
    local counts = { rare = 0, quest = 0 }
    for _, entry in pairs(Entries() or {}) do
        if type(entry) == "table" and counts[entry.kind] then
            counts[entry.kind] = counts[entry.kind] + 1
        end
    end
    return counts
end
