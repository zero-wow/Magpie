local addon = {}
local now, scans, logReads = 100, 0, 0
GetTime = function() return now end
Enum = { UIMapType = { Continent = 2, Zone = 3 } }
C_Map = {
    GetMapInfo = function(mapID)
        return mapID == 1 and { mapType = 2 }
            or { mapType = 3, parentMapID = 1 }
    end,
    GetMapChildrenInfo = function()
        local maps = {}
        for mapID = 124, 130 do maps[#maps + 1] = { mapID = mapID } end
        return maps
    end,
    CanSetUserWaypointOnMap = function() return true end,
}
C_QuestLog = {
    GetNumQuestLogEntries = function() return 0 end,
    GetQuestsOnMap = function(mapID)
        scans = scans + 1
        return { { questID = mapID + 8000, name = "Remote objective", x = .5, y = .5 } }
    end,
    IsOnQuest = function(questID) return questID ~= 9002 end,
}
addon.VignetteRadarQuestData = {
    GetAvailableQuestStarts = function(mapID)
        return mapID == 124 and { {
            questID = 9002, questName = "Available quest", x = .51, y = .5,
        } } or {}
    end,
}
local wantsPool = false
addon.VignetteRadarWorldFocus = { WantsQuestPool = function() return wantsPool end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Data/RouteQuests.lua"))("VignetteRadar", addon)
local pool = addon.VignetteRadarRouteQuests
local settings = { vignetteRadarAutoRouteNearbyZones = true,
    vignetteRadarAutoRouteQuestStarts = true }
local player = { worldX = 12350, worldY = 50, instanceID = 1 }
pool.Bind(123, player, function(mapID, vector)
    return mapID * 100 + vector.x * 100, vector.y * 100, 1
end, function(x, y) return { x = x, y = y } end, settings)
local nextStepReads = 0
addon.VignetteRadarQuestData.GetNextStep = function(questID, mapID)
    nextStepReads = nextStepReads + 1
    assert(questID == 9002 and mapID == 123)
    return { mapID = 123, x = .75, y = .4, text = "Find the objective" }
end
local acceptedStep = pool.CurrentQuestWaypoint(9002)
assert(acceptedStep and acceptedStep.questID == 9002
    and acceptedStep.mapID == 123 and acceptedStep.mapX == .75
    and acceptedStep.worldX == 12375 and acceptedStep.worldY == 40
    and acceptedStep.nextStep.text == "Find the objective",
    "an accepted quest's waypoint must be routeable without a map record or watch")
settings.vignetteRadarAutoRouteNearbyZones = false
assert(pool.CurrentQuestWaypoint(9002).mapX == .75 and nextStepReads == 2,
    "the current quest's next step must work when nearby-zone routing is off")
settings.vignetteRadarAutoRouteNearbyZones = true
pool.Tick()
assert(scans == 0, "remote maps should remain idle without a quest route")
local diagnostic = pool.Diagnostics()
assert(diagnostic.logRead == 0 and diagnostic.logTotal == 0
    and diagnostic.localPoints == 0 and diagnostic.otherPoints == 0
    and scans == 0,
    "route diagnostics must only report cached state and never trigger a scan")
wantsPool = true
pool.Tick()
assert(scans == 2, "a radar scan may read at most two remote maps")
local foundObjective, foundStart
for _, item in ipairs(pool.Candidates()) do
    if item.questID == 8124 then foundObjective = item end
    if item.questID == 9002 then foundStart = item end
end
assert(foundObjective and foundObjective.mapID == 124
    and foundStart and foundStart.availableStart,
    "the pool should expose mapped objectives and available quest starts")
pool.Tick()
assert(scans == 2, "repeated radar refreshes must reuse the map cache")
assert(pool.Candidates() == pool.Candidates(), "unchanged pool data must reuse the candidate list")
now = now + 5
pool.Tick()
assert(scans == 4, "the next scheduled pass should read only two more maps")
settings.vignetteRadarAutoRouteQuestStarts = false
for _, item in ipairs(pool.Candidates()) do
    assert(not item.availableStart, "the quest-start option should apply immediately")
end
pool.Invalidate("quest")
pool.Tick()
assert(scans == 4, "quest event bursts must not bypass the scan interval")
now = now + 1
pool.Tick()
assert(scans == 6, "a quest update should gradually refresh nearby maps")
settings.vignetteRadarAutoRouteNearbyZones = false
pool.Tick()
assert(#pool.Candidates() == 0 and scans == 6,
    "turning off nearby zones should stop remote reads and candidates")
io.write("vignette radar route quest tests passed\n")
