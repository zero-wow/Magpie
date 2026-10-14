local _, addon = ...
if type(addon) ~= "table" then return end

-- One reader for the quest log and quest map APIs. The radar, the quest
-- tracker and the route card ask for the same lists in the same frame, so
-- each list is read once and kept for a moment (CACHE_AGE) or until a quest
-- or map event arrives through the bus. Values come back cleaned of secrets
-- but not filtered; callers keep their own rules for what to show.
-- Pass fresh = true to skip the cache and refill it with a live read.
--   Q.OnMap(mapID, fresh) -> { quests = { {questID, x, y, name} }, tasks = { {questID, x, y, name, isWorldQuest} } }
--   Q.Log(fresh)          -> { {isHeader, title} | {questID, title, level} } in quest-log order
--   Q.Watched(fresh)      -> set of watched quest IDs (quest and world quest watches)
--   Q.WatchedIDs(world, fresh) -> ordered watched IDs; world = true for world quest watches
--   Q.Step(questID, mapID)-> QuestData next step plus `objective` summary
--   Q.Flags(questID)      -> { complete, world, task, inArea }
--   Q.Key(questID, ...)   -> "quest:<id>[:part...]", the one quest key builder
--   Q.Track(questID) / Q.Untrack(questID, removeWatch, restoreID)
local Q = {}
addon.Quests = Q

local MAX_MAP_QUESTS, MAX_MAP_TASKS, MAX_LOG, MAX_WATCHES = 256, 128, 500, 40
local CACHE_AGE, MAX_CACHED_MAPS = .25, 16

local IsSecret, Number = addon.Secret.IsSecret, addon.Secret.Number
local Field, Call, Text = addon.Secret.Field, addon.Secret.Call, addon.Secret.Text

local mapCache, mapCacheCount = {}, 0
local logCache, watchCache

local function Now()
    return Number(Call(_G, "GetTime"))
end

-- A cached entry is fresh for CACHE_AGE seconds. Without GetTime nothing is
-- cached, so every read is live.
local function Fresh(entry, now)
    return entry and now and entry.at <= now and now - entry.at < CACHE_AGE
end

local function Length(list)
    if IsSecret(list) or type(list) ~= "table" then return 0 end
    local ok, count = pcall(function() return #list end)
    return ok and Number(count) or 0
end

function Q.Invalidate()
    mapCache, mapCacheCount = {}, 0
    logCache, watchCache = nil, nil
end
if addon.Bus then
    addon.Bus.On("QUEST_CHANGED", function() Q.Invalidate() end)
    addon.Bus.On("MAP_CHANGED", function() Q.Invalidate() end)
end

-- One entry per Blizzard record, in Blizzard's order (callers count indexes).
local function ReadMap(mapID)
    local result = { quests = {}, tasks = {} }
    local records = Call(C_QuestLog, "GetQuestsOnMap", mapID)
    for index = 1, math.min(Length(records), MAX_MAP_QUESTS) do
        local record = Field(records, index)
        result.quests[index] = { questID = Number(Field(record, "questID")),
            x = Number(Field(record, "x")), y = Number(Field(record, "y")),
            name = Text(Field(record, "name")) }
    end
    local tasks = Call(C_TaskQuest, "GetQuestsOnMap", mapID)
    for index = 1, math.min(Length(tasks), MAX_MAP_TASKS) do
        local record = Field(tasks, index)
        result.tasks[index] = {
            questID = Number(Field(record, "questID")) or Number(Field(record, "questId")),
            x = Number(Field(record, "x")), y = Number(Field(record, "y")),
            name = Text(Field(record, "name")),
            isWorldQuest = Field(record, "isWorldQuest") == true }
    end
    return result
end

local EMPTY_MAP = { quests = {}, tasks = {} }

function Q.OnMap(mapID, fresh)
    mapID = Number(mapID)
    if not mapID then return EMPTY_MAP end
    local now = Now()
    local cached = mapCache[mapID]
    if not fresh and Fresh(cached, now) then return cached.value end
    local value = ReadMap(mapID)
    if now then
        if not cached and mapCacheCount >= MAX_CACHED_MAPS then mapCache, mapCacheCount = {}, 0 end
        if not mapCache[mapID] then mapCacheCount = mapCacheCount + 1 end
        mapCache[mapID] = { at = now, value = value }
    end
    return value
end

function Q.Log(fresh)
    local now = Now()
    if not fresh and Fresh(logCache, now) then return logCache.value end
    local result = {}
    local count = Number(Call(C_QuestLog, "GetNumQuestLogEntries")) or 0
    for index = 1, math.min(count, MAX_LOG) do
        local info = Call(C_QuestLog, "GetInfo", index)
        if type(info) == "table" and not IsSecret(info) then
            if Field(info, "isHeader") == true then
                result[#result + 1] = { isHeader = true, title = Field(info, "title") }
            else
                result[#result + 1] = { questID = Number(Field(info, "questID")),
                    title = Field(info, "title"),
                    level = Number(Field(info, "difficultyLevel")) or Number(Field(info, "level")) }
            end
        end
    end
    if now then logCache = { at = now, value = result } end
    return result
end

local WATCH_SPECS = {
    { "GetNumQuestWatches", "GetQuestIDForQuestWatchIndex" },
    { "GetNumWorldQuestWatches", "GetQuestIDForWorldQuestWatchIndex" },
}

local function ReadWatches()
    local value = { quest = {}, world = {}, set = {} }
    for spec, list in ipairs({ value.quest, value.world }) do
        local names = WATCH_SPECS[spec]
        local count = Number(Call(C_QuestLog, names[1])) or 0
        for index = 1, math.min(count, MAX_WATCHES) do
            local id = Number(Call(C_QuestLog, names[2], index))
            if id then
                list[#list + 1] = id
                value.set[id] = true
            end
        end
    end
    return value
end

local function Watches(fresh)
    local now = Now()
    if not fresh and Fresh(watchCache, now) then return watchCache.value end
    local value = ReadWatches()
    if now then watchCache = { at = now, value = value } end
    return value
end

function Q.Watched(fresh) return Watches(fresh).set end
function Q.WatchedIDs(world, fresh)
    local value = Watches(fresh)
    return world and value.world or value.quest
end

local function ID(value)
    value = Number(value)
    return value and value > 0 and value % 1 == 0 and value or nil
end

-- Blizzard's next waypoint for the quest (QuestData caches it) with the first
-- unfinished objective attached.
function Q.Step(questID, mapID)
    questID = ID(questID)
    local data = addon.VignetteRadarQuestData
    if not (questID and data) then return nil end
    local step = data.GetNextStep(questID, mapID) or { questID = questID }
    step.objective = data.GetObjectiveSummary(questID)
    if not (step.x or step.text or step.objective) then return nil end
    return step
end

function Q.Flags(questID)
    questID = ID(questID)
    if not questID then return nil end
    local data = addon.VignetteRadarQuestData
    return {
        complete = Call(C_QuestLog, "IsComplete", questID) == true,
        world = Call(C_QuestLog, "IsWorldQuest", questID) == true,
        task = Call(C_QuestLog, "IsQuestTask", questID) == true,
        inArea = data and data.IsQuestInArea and data.IsQuestInArea(questID) == true or false,
    }
end

-- "quest:<id>" plus optional parts, e.g. Key(id, "objective", x, y).
function Q.Key(questID, ...)
    local key = "quest:" .. tostring(questID)
    for index = 1, select("#", ...) do
        key = key .. ":" .. tostring((select(index, ...)))
    end
    return key
end

-- Blizzard navigates only to watched quests: add a watch when the quest has
-- none, then super-track it. Returns whether super-tracking took and whether
-- this call added the watch (so Untrack can remove only what it added).
function Q.Track(questID)
    questID = ID(questID)
    if not questID then return false, false end
    local log, added = C_QuestLog, false
    if log and type(log.GetQuestWatchType) == "function" and type(log.AddQuestWatch) == "function" then
        local read, watchType = pcall(log.GetQuestWatchType, questID)
        if read and watchType == nil and pcall(log.AddQuestWatch, questID) then added = true end
    end
    local track = C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
    local ok = type(track) == "function" and pcall(track, questID) or false
    if added then watchCache = nil end
    return ok, added
end

-- Drops the watch when asked, and hands super-tracking to restoreID (or
-- nothing) only while this quest is still the super-tracked one.
function Q.Untrack(questID, removeWatch, restoreID)
    questID = ID(questID)
    if not questID then return false end
    if removeWatch and C_QuestLog and type(C_QuestLog.RemoveQuestWatch) == "function" then
        pcall(C_QuestLog.RemoveQuestWatch, questID)
        watchCache = nil
    end
    if Number(Call(C_SuperTrack, "GetSuperTrackedQuestID")) == questID then
        local track = C_SuperTrack.SetSuperTrackedQuestID
        if type(track) == "function" then
            pcall(track, restoreID and restoreID ~= questID and restoreID or 0)
        end
    end
    return true
end
