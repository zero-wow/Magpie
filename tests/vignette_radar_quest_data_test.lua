local sourcePath = arg[1] or "Data/QuestData.lua"
local addon = {}
local now, calls = 100, { map = 0, global = 0, text = 0, starts = 0, requests = 0 }
GetTime = function() return now end
issecretvalue = function(value) return type(value) == "table" and value.secret == true end

local waypoint, global, instruction = { .25, .7 }, { 88, .4, .6 }, "Enter the cave"
C_QuestLog = {
    GetNextWaypointForMap = function(questID, mapID)
        calls.map = calls.map + 1
        assert(questID == 501 and mapID == 77)
        if waypoint then return waypoint[1], waypoint[2] end
    end,
    GetNextWaypoint = function(questID)
        calls.global = calls.global + 1
        assert(questID == 501)
        if global then return global[1], global[2], global[3] end
    end,
    GetNextWaypointText = function(questID)
        calls.text = calls.text + 1
        assert(questID == 501)
        return instruction
    end,
}
local lines = {
    { questID=501, questLineID=900, questName="Campaign start", questLineName="The Beginning",
      x=.25, y=.6, isQuestStart=true, isHidden=false, isCampaign=true,
      isImportant=true, floorLocation=0, startMapID=77 },
    { questID=502, questLineID=901, questName="Side story", questLineName="The Other Path",
      x=.4, y=.5, isQuestStart=true, isHidden=false, floorLocation=1 },
    { questID=503, questLineID=902, x=.5, y=.5, isQuestStart=false },
    { questID=504, questLineID=903, x=.5, y=.5, isQuestStart=true, isHidden=true },
    { questID=505, questLineID=900, x=.5, y=.5, isQuestStart=true, isHidden=false },
    { questID={ secret=true }, questLineID=904, x=.5, y=.5, isQuestStart=true, isHidden=false },
    { questID=506, questLineID=905, x={ secret=true }, y=.5, isQuestStart=true, isHidden=false },
}
C_QuestLine = {
    RequestQuestLinesForMap = function(mapID)
        calls.requests = calls.requests + 1
        assert(mapID == 77 or mapID == 78)
    end,
    GetAvailableQuestLines = function(mapID)
        calls.starts = calls.starts + 1
        assert(mapID == 77 or mapID == 78)
        return lines
    end,
}

assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile(sourcePath))("VignetteRadar", addon)
local Q = assert(addon.VignetteRadarQuestData)
assert(Q.GetNextStep(0, 77) == nil and #Q.GetAvailableQuestStarts("bad") == 0,
    "invalid identifiers must never reach Blizzard APIs")

local step = Q.GetNextStep(501, 77)
assert(step.questID == 501 and step.mapID == 77 and step.x == .25 and step.y == .7
    and step.text == "Enter the cave" and step.onCurrentMap == true,
    "map-specific waypoint and instruction should be returned independently")
assert(calls.map == 1 and calls.global == 0 and calls.text == 1,
    "a current-map waypoint should not need the global fallback")
step.x = .9
assert(Q.GetNextStep(501, 77).x == .25 and calls.map == 1,
    "short-lived waypoint cache must copy its results")
now = 103
waypoint = nil
step = Q.GetNextStep(501, 77)
assert(step.mapID == 88 and step.onCurrentMap == false and step.x == .4,
    "a global waypoint on another map must keep its real map ID")
global = nil
now = 106
step = Q.GetNextStep(501, 77)
assert(step.text == "Enter the cave" and step.x == nil,
    "Blizzard instruction text remains useful without coordinates")
instruction = nil
now = 109
assert(Q.GetNextStep(501, 77) == nil, "no waypoint or text means no step metadata")

local starts = Q.GetAvailableQuestStarts(77)
assert(#starts == 2 and starts[1].questID == 501 and starts[2].questID == 502,
    "only visible, valid quest-line starts should be returned")
assert(starts[1].isCampaign and starts[1].isImportant and starts[1].floor == "above"
    and starts[2].isCampaign == false and starts[2].floor == "below",
    "campaign, important, and floor fields must retain Blizzard's values")
assert(starts[1].mapID == 77 and starts[1].startMapID == 77
    and starts[1].questLineName == "The Beginning",
    "start metadata must preserve names and its source map")
assert(calls.requests == 1 and calls.starts == 1,
    "a map request and one list read should populate the short cache")
starts[1].questName = "overwritten"
assert(Q.GetAvailableQuestStarts(77)[1].questName == "Campaign start" and calls.starts == 1,
    "cached starts must not be mutable by a caller")
local trackWarband = false
C_Minimap = { IsTrackingAccountCompletedQuests = function() return trackWarband end }
C_QuestLog.IsQuestFlaggedCompletedOnAccount = function(id) return id == 501 end
assert(Q.IsWarbandCompletedStartHidden(501)
    and #Q.GetAvailableQuestStarts(77) == 1
    and Q.GetAvailableQuestStarts(77)[1].questID == 502 and calls.starts == 1,
    "warband-completed starts must disappear even from the short cache when tracking is off")
trackWarband = true
assert(not Q.IsWarbandCompletedStartHidden(501)
    and #Q.GetAvailableQuestStarts(77) == 2 and calls.starts == 1,
    "switching Blizzard warband tracking on must restore starts without a data reread")
trackWarband = false
C_QuestLog.IsOnQuest = function(id) return id == 501 end
assert(#Q.GetAvailableQuestStarts(77) == 2,
    "an accepted quest must remain available to objective tracking")
C_QuestLog.IsOnQuest = nil
C_QuestLog.IsQuestFlaggedCompletedOnAccount = nil
C_Minimap = nil
now = 115
assert(#Q.GetAvailableQuestStarts(77) == 2 and calls.starts == 2 and calls.requests == 1,
    "quest-line data must refresh without repeating the map request")
assert(#Q.GetAvailableQuestStarts(78) == 2 and calls.requests == 2,
    "a map change should request available quest lines for the new map")

Q.Invalidate()
now = 116
assert(#Q.GetAvailableQuestStarts(77) == 2 and calls.requests == 3,
    "quest-log changes should be able to invalidate both caches")
now = 116.5
Q.Invalidate("quest")
assert(#Q.GetAvailableQuestStarts(77) == 2 and calls.requests == 3,
    "quest updates must refresh the list without repeating the map request")
C_QuestLine.GetAvailableQuestLines = function() error("unavailable") end
now = 122
assert(#Q.GetAvailableQuestStarts(77) == 0, "unavailable Blizzard data must fail safely")
C_QuestLog.GetNextWaypointForMap = function() return { secret=true }, .5 end
C_QuestLog.GetNextWaypoint = function() error("protected") end
C_QuestLog.GetNextWaypointText = function() return { secret=true } end
Q.Invalidate()
assert(Q.GetNextStep(501, 77) == nil, "secret coordinates and API errors must not leak")

local objectiveReads, objectiveCount = 0, 2
C_QuestLog.GetQuestObjectives = function()
    objectiveReads = objectiveReads + 1
    return { { text = "Collect crystals: " .. objectiveCount .. "/5",
        numFulfilled = objectiveCount, numRequired = 5, finished = false },
        { text = "Speak to the keeper", finished = false } }
end
local objective = Q.GetObjectiveSummary(501, "Collect crystals")
assert(objective and objective.label == "Collect crystals" and objective.count == "2/5"
    and Q.GetObjectiveSummary(501, "Collect crystals").count == "2/5"
    and objectiveReads == 1,
    "objective notes should show the selected count without polling on every redraw")
objectiveCount = 3
Q.Invalidate("quest")
assert(Q.GetObjectiveSummary(501, "Collect crystals").count == "3/5"
    and objectiveReads == 2,
    "quest events should refresh the objective count immediately")
C_QuestLog.GetQuestObjectives = function()
    return { { text = "0/1 Participate in the Brewfest Chowdown",
        numFulfilled = 0, numRequired = 1, finished = false } }
end
Q.Invalidate("quest")
local prefixed = Q.GetObjectiveSummary(501)
assert(prefixed and prefixed.label == "Participate in the Brewfest Chowdown"
    and prefixed.count == "0/1",
    "a leading Blizzard progress count must not appear twice in objective notes")
C_QuestLog.GetQuestObjectives = function() return nil end
Q.Invalidate("quest")
local fallback = Q.GetObjectiveSummary(501, "Scout the cave: 1/3")
assert(fallback and fallback.label == "Scout the cave" and fallback.count == "1/3",
    "Blizzard waypoint text should keep the objective note useful before objective rows load")
local prefixedFallback = Q.GetObjectiveSummary(501, "0/1 Participate in the Brewfest Chowdown")
assert(prefixedFallback and prefixedFallback.label == "Participate in the Brewfest Chowdown"
    and prefixedFallback.count == "0/1",
    "leading progress counts in waypoint text must also remain single")

local hintReads = 0
C_QuestLog.GetNextWaypointText = function()
    hintReads = hintReads + 1
    return "Take the portal"
end
Q.Invalidate()
assert(Q.GetNextStepLine(501) == "Take the portal" and Q.GetNextStepLine(501) == "Take the portal"
    and hintReads == 1, "route hints are reused for two seconds")
now = now + 2
assert(select(2, Q.GetNextStepLine(501)) == true and hintReads == 2, "an old route hint is read again")
print("vignette radar quest data tests passed")
