local addon, db = {}, {}
addon.GetSettings = function() return db end
local snapshot = { mapID = 123, mapX = .502, mapY = .5,
    worldX = 502, worldY = 500, instanceID = 42 }
addon.VignetteRadarAPI = { GetPlayerSnapshot = function() return snapshot end }
local objectives = { { numFulfilled = 0, finished = false, text = "Find the stone" } }
C_QuestLog = {
    GetNumQuestWatches = function() return 1 end,
    GetQuestIDForQuestWatchIndex = function() return 987 end,
    GetQuestObjectives = function() return objectives end,
}
local rewardDone = false
local rewardReads = 0
C_QuestLog.IsQuestFlaggedCompleted = function()
    rewardReads = rewardReads + 1
    return rewardDone
end
time = function() return 1000 end
UnitPosition = function() return 502, 500, 74, 42 end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Data/OutcomeLearning.lua"))("VignetteRadar", addon)
local learning = addon.VignetteRadarOutcomeLearning
local rare = { key = "vignette-1", category = "rare", name = "Silvermaw",
    vignetteID = 456, objectGUID = "Creature-0-1-1-1-777-000",
    mapID = 123, mapX = .5, mapY = .5,
    worldX = 500, worldY = 500, instanceID = 42 }
local quest = { questID = 987, mapID = 123, mapX = .5, mapY = .5,
    worldX = 500, worldY = 500, instanceID = 42 }
learning.Sync({ rare }, { quest })
for key in pairs(rare) do
    assert(not tostring(key):find("^_outcome"), "Sync must not write onto live radar targets")
end
assert(not learning.OnDeadVignette("unseen", {})
    and not db.vignetteRadarOutcomeLocations,
    "unseen or already-dead vignettes must not count as kills")
assert(learning.OnDeadVignette(rare.key, { objectGUID = rare.objectGUID }))
local kill = db.vignetteRadarOutcomeLocations["rare:123:777"]
assert(kill and kill.samples[1].z == 74 and kill.sourceMapX == .5,
    "a live-to-dead rare transition should correlate the source with player XY/Z")
assert(not learning.OnDeadVignette(rare.key, {}),
    "one dead vignette must only produce one observation")
objectives = { { numFulfilled = 1, finished = true, text = "Find the stone" } }
learning.OnQuestEvent(true)
local objective = db.vignetteRadarOutcomeLocations["quest:987:1"]
assert(objective and objective.samples[1].z == 74
    and objective.sourceMapX == .5 and objective.objectiveIndex == 1,
    "objective progress should save a correlated player-at-progress position")
learning.OnQuestEvent(true)
assert(#objective.samples == 1, "duplicate quest events must not add samples")
objectives = { { numFulfilled = 0, finished = false, text = "Find the stone" } }
learning.OnQuestEvent(true)
snapshot = { mapID = 123, mapX = .504, mapY = .5,
    worldX = 504, worldY = 500, instanceID = 42 }
UnitPosition = function() return 504, 500, 75, 42 end
objectives = { { numFulfilled = 1, finished = true, text = "Find the stone" } }
learning.OnQuestEvent(true)
objectives = { { numFulfilled = 0, finished = false, text = "Find the stone" } }
local hint = learning.GetQuestHint(987, 123)
assert(hint and math.abs(hint.mapX - .503) < .0001
    and hint.objectiveIndex == 1 and hint.text == "Find the stone",
    "two consistent completions should give a fallback when Blizzard has no quest point")
UnitPosition = function() return 900, 900, 999, 42 end
assert(learning.PlayerHeight(snapshot) == nil,
    "height from a different coordinate basis must not be recorded")
local rewardRare = { key = "vignette-2", category = "rare", name = "Stormbeak",
    vignetteID = 457, rewardQuestID = 321,
    objectGUID = "Creature-0-1-1-1-778-000",
    mapID = 123, mapX = .5, mapY = .5,
    worldX = 500, worldY = 500, instanceID = 42 }
UnitPosition = function() return 504, 500, 75, 42 end
learning.Sync({ rewardRare }, {})
learning.Sync({ rewardRare }, {})
assert(rewardReads == 1, "ordinary radar rescans should reuse the rare reward baseline")
learning.Sync({}, {})
rewardDone = true
learning.OnQuestEvent(true)
assert(db.vignetteRadarOutcomeLocations["rare:123:778"],
    "a nearby live rare's reward-quest completion should confirm the kill even if its vignette just vanished")
learning.OnQuestEvent(true)
assert(#db.vignetteRadarOutcomeLocations["rare:123:778"].samples == 1,
    "reward updates must not record the same kill twice")
learning.Sync({ rare }, {})
snapshot = { mapID = 123, mapX = .8, mapY = .8,
    worldX = 800, worldY = 800, instanceID = 42 }
assert(not learning.OnDeadVignette(rare.key, { objectGUID = rare.objectGUID })
    and #kill.samples == 1,
    "a remote dead vignette must not be mistaken for a nearby kill")
local counts = learning.Count()
assert(counts.rare == 2 and counts.quest == 1)
io.write("vignette radar outcome learning tests passed\n")
