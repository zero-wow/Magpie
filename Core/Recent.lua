local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarRecent = API
-- Kills hide markers for KILL_SECONDS; they are kept for a day so
-- Declutter can hide rares killed since the daily reset.
local KILL_SECONDS, KEEP_SECONDS, MAX_KILLS = 3600, 86400, 256
local questCache = {}

local Safe, Field, Integer = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Integer

-- Positive whole numbers only (IDs and timestamps).
local function Number(value)
    return Integer(value, 1)
end

local function Epoch()
    local clock = type(GetServerTime) == "function" and GetServerTime or time
    if type(clock) ~= "function" then return nil end
    local ok, value = pcall(clock)
    return ok and Number(value) or nil
end

local function GUIDIdentity(guid)
    if not (Safe(guid) and type(guid) == "string") then return nil end
    local kind, id = guid:match("^([A-Za-z]+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return "npc:" .. id end
    if kind == "GameObject" then return "object:" .. id end
    return nil
end

local function Kills(settings)
    settings = settings or addon.GetSettings()
    return settings.vignetteRadarRecentKills
end

local function Prune(kills, now)
    local count = 0
    for key, at in pairs(kills) do
        if type(at) ~= "number" or at > now or now - at >= KEEP_SECONDS then
            kills[key] = nil
        else
            count = count + 1
        end
    end
    if count > MAX_KILLS then
        local oldestKey, oldestAt
        for key, at in pairs(kills) do
            if not oldestAt or at < oldestAt then oldestKey, oldestAt = key, at end
        end
        if oldestKey then kills[oldestKey] = nil end
    end
end

function API.RecordNPCGuid(guid)
    local identity, now = GUIDIdentity(guid), Epoch()
    local settings = addon.GetSettings()
    if not (identity and now and (settings.vignetteRadarHideCleared or settings.vignetteRadarDeclutter)) then
        return false
    end
    local kills = Kills()
    kills[identity] = now
    Prune(kills, now)
    return true
end

function API.HideNote(note)
    local key, now = Field(note, "key"), Epoch()
    if not (type(key) == "string" and now) then return false end
    local kills = Kills()
    kills["note:" .. key] = now
    Prune(kills, now)
    return true
end

function API.InvalidateQuests()
    questCache = {}
end
if addon.Bus then addon.Bus.On("QUEST_LOG_UPDATE", function() API.InvalidateQuests() end) end

local function Completed(questID)
    if not (questID and C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function") then
        return false
    end
    local now = type(GetTime) == "function" and GetTime() or nil
    local cached = questCache[questID]
    if cached and now and now - cached.at < 5 then return cached.done end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    done = ok and Safe(done) and done == true
    if now then questCache[questID] = { done = done, at = now } end
    return done
end

function API.IsHidden(item, settings)
    settings = settings or addon.GetSettings()
    if not settings.vignetteRadarHideCleared then return false end
    local category = Field(item, "category") or Field(item, "kind")
    if category ~= "rare" and category ~= "treasure" and category ~= "mob" then return false end
    local questID = Number(Field(item, "rewardQuestID")) or Number(Field(item, "questID"))
    if Completed(questID) then return true end
    if Field(item, "isDead") == true then
        API.RecordNPCGuid(Field(item, "objectGUID"))
        return true
    end
    local now = Epoch()
    if not now then return false end
    return API.KilledWithin(item, KILL_SECONDS, now, settings)
end

-- The identities a kill can be recorded under for item.
local function KillKeys(item)
    local keys = {}
    local npcID = Number(Field(item, "npcID"))
    if npcID then keys[#keys + 1] = "npc:" .. npcID end
    local objectID = Number(Field(item, "objectID"))
    if objectID then keys[#keys + 1] = "object:" .. objectID end
    local guidIdentity = GUIDIdentity(Field(item, "objectGUID"))
    if guidIdentity then keys[#keys + 1] = guidIdentity end
    local noteKey = Field(item, "key")
    if type(noteKey) == "string" then keys[#keys + 1] = "note:" .. noteKey end
    return keys
end

-- True when item was recorded as killed or cleared within the last seconds,
-- whatever the Hide Cleared switch says.
function API.KilledWithin(item, seconds, now, settings)
    now = now or Epoch()
    if not (now and type(seconds) == "number" and seconds > 0) then return false end
    local kills = Kills(settings)
    if type(kills) ~= "table" then return false end
    for _, key in ipairs(KillKeys(item)) do
        local at = kills[key]
        if type(at) == "number" then
            if at <= now and now - at < seconds then return true end
            if at > now or now - at >= KEEP_SECONDS then kills[key] = nil end
        end
    end
    return false
end
