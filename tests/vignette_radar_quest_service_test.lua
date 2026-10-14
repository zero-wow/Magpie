local frame = { events = {}, scripts = {} }
function frame:RegisterEvent(event) self.events[event] = true end
function frame:SetScript(name, callback) self.scripts[name] = callback end
CreateFrame = function() return frame end
issecretvalue = function(value) return type(value) == "table" and value.secret == true end

local now = 10
GetTime = function() return now end
local reads = { map = 0, tasks = 0, log = 0, watches = 0 }
local mapQuests = {
    { questID = 11, x = .4, y = .5, name = "Local" },
    { secret = true },
    { questID = 12, x = .6, y = .5, name = { secret = true } },
}
C_QuestLog = {
    GetQuestsOnMap = function() reads.map = reads.map + 1; return mapQuests end,
    GetNumQuestLogEntries = function() reads.log = reads.log + 1; return 4 end,
    GetInfo = function(index)
        return ({
            { isHeader = true, title = "Zone" },
            { questID = 11, title = "Local", difficultyLevel = 70, level = 60 },
            { secret = true },
            { questID = 13, title = "Old", level = 30 },
        })[index]
    end,
    GetNumQuestWatches = function() reads.watches = reads.watches + 1; return 2 end,
    GetQuestIDForQuestWatchIndex = function(index) return ({ 13, 11 })[index] end,
    GetNumWorldQuestWatches = function() return 1 end,
    GetQuestIDForWorldQuestWatchIndex = function() return 44 end,
    IsComplete = function(id) return id == 13 end,
    IsWorldQuest = function(id) return id == 44 end,
    IsQuestTask = function(id) return id == 44 end,
    GetQuestWatchType = function(id) return id == 11 and 0 or nil end,
    AddQuestWatch = function(id) C_QuestLog.added = id; return true end,
    RemoveQuestWatch = function(id) C_QuestLog.removed = id end,
}
C_TaskQuest = { GetQuestsOnMap = function()
    reads.tasks = reads.tasks + 1
    return { { questId = 44, x = .1, y = .2, isWorldQuest = true }, { questID = 45, x = .3, y = .3 } }
end }
local superTracked = 0
C_SuperTrack = {
    GetSuperTrackedQuestID = function() return superTracked end,
    SetSuperTrackedQuestID = function(id) superTracked = id end,
}

local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
addon.VignetteRadarQuestData = {
    GetNextStep = function(id, mapID)
        return id == 11 and { questID = id, mapID = mapID, x = .41, y = .51, text = "Go" } or nil
    end,
    GetObjectiveSummary = function(id) return id ~= 99 and { label = "Kill", count = "1/3" } or nil end,
    IsQuestInArea = function(id) return id == 11 end,
}
assert(loadfile("Data/QuestService.lua"))("VignetteRadar", addon)
local Q = assert(addon.Quests, "the quest service must be exposed as addon.Quests")

-- One entry per Blizzard record, cleaned of secrets, in Blizzard's order.
local onMap = Q.OnMap(84)
assert(#onMap.quests == 3 and onMap.quests[1].questID == 11 and onMap.quests[1].name == "Local"
    and onMap.quests[2].questID == nil and onMap.quests[3].name == nil,
    "map records keep their index and drop secret values")
assert(onMap.tasks[1].questID == 44 and onMap.tasks[1].isWorldQuest == true
    and onMap.tasks[2].questID == 45 and onMap.tasks[2].isWorldQuest == false,
    "task records accept questId and keep the world-quest flag")
assert(Q.OnMap(84) == onMap and reads.map == 1 and reads.tasks == 1,
    "a second read in the same moment must reuse the cache")
assert(Q.OnMap(84, true) ~= onMap and reads.map == 2, "fresh must bypass the cache")
now = 10.3
Q.OnMap(84)
assert(reads.map == 3, "the cache must expire after a quarter second")
frame.scripts.OnEvent(frame, "QUEST_POI_UPDATE")
Q.OnMap(84)
assert(reads.map == 4, "a quest event must invalidate the map cache")
frame.scripts.OnEvent(frame, "ZONE_CHANGED")
Q.OnMap(84)
assert(reads.map == 5, "a map event must invalidate the map cache")
assert(#Q.OnMap(nil).quests == 0, "no map yields empty lists")

local log = Q.Log()
assert(#log == 3 and log[1].isHeader and log[1].title == "Zone"
    and log[2].questID == 11 and log[2].level == 70 and log[3].level == 30,
    "the log skips secret rows and prefers difficultyLevel")
assert(Q.Log() == log and reads.log == 1)
frame.scripts.OnEvent(frame, "QUEST_LOG_UPDATE")
assert(Q.Log() ~= log and reads.log == 2, "QUEST_LOG_UPDATE must refresh the log")

local quests, world = Q.WatchedIDs(false), Q.WatchedIDs(true)
assert(quests[1] == 13 and quests[2] == 11 and world[1] == 44 and #world == 1,
    "watched IDs keep watch order per kind")
assert(Q.Watched()[11] and Q.Watched()[44] and not Q.Watched()[45] and reads.watches == 1)

local step = Q.Step(11, 84)
assert(step.x == .41 and step.text == "Go" and step.objective.count == "1/3",
    "Step joins the next waypoint with the objective summary")
assert(Q.Step(12, 84).objective and Q.Step(12, 84).x == nil, "an objective alone is a step")
assert(Q.Step(99, 84) == nil and Q.Step(-1) == nil)

local flags = Q.Flags(44)
assert(flags.world and flags.task and not flags.complete and not flags.inArea)
assert(Q.Flags(13).complete and Q.Flags(11).inArea and Q.Flags("x") == nil)

assert(Q.Key(5) == "quest:5" and Q.Key(5, "objective", 1234, 5678) == "quest:5:objective:1234:5678"
    and Q.Key(5, 4000) == "quest:5:4000", "Key must rebuild every quest key format")

local ok, added = Q.Track(13)
assert(ok and added and C_QuestLog.added == 13 and superTracked == 13,
    "tracking an unwatched quest adds a watch and super-tracks it")
ok, added = Q.Track(11)
assert(ok and not added and superTracked == 11, "an already watched quest keeps its watch")
assert(Q.Untrack(11, true, 7) and C_QuestLog.removed == 11 and superTracked == 7,
    "untracking restores the previous super-tracked quest")
superTracked = 3
Q.Untrack(11, false)
assert(superTracked == 3, "untracking must not steal a quest the player tracks now")

io.write("vignette radar quest service tests passed\n")
