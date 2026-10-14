local settings = { vignetteRadarHideCleared = false, vignetteRadarRecentKills = {} }
local addon = { GetSettings = function() return settings end }
local epoch, elapsed = 100000, 0
GetServerTime = function() return epoch end
GetTime = function() return elapsed end
local completed = {}
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return completed[id] == true end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Recent.lua"))("VignetteRadar", addon)
local recent = addon.VignetteRadarRecent
local rare = { category = "rare", npcID = 123, rewardQuestID = 900 }
local treasure = { kind = "treasure", objectID = 456, questID = 901, key = "Pack:1:2" }
assert(not recent.IsHidden(rare) and not recent.IsHidden(treasure))
settings.vignetteRadarHideCleared = true
completed[900], completed[901] = true, true
assert(recent.IsHidden(rare) and recent.IsHidden(treasure),
    "live rare rewards and map treasure quest flags must hide cleared locations")
completed[900], completed[901] = false, false
recent.InvalidateQuests()
assert(not recent.IsHidden(rare) and not recent.IsHidden(treasure),
    "repeatable quest flags must let markers return after a reset")
assert(recent.RecordNPCGuid("Creature-0-1-2-3-123-000001") and recent.IsHidden(rare),
    "a dead vignette must hide the matching live rare and map-pack NPC")
epoch = epoch + 3599
assert(recent.IsHidden(rare), "observed dead vignettes must remain hidden for an hour")
epoch = epoch + 1
assert(not recent.IsHidden(rare), "unflagged dead vignettes must expire instead of hiding forever")
assert(recent.RecordNPCGuid("GameObject-0-1-2-3-456-000001") and recent.IsHidden(treasure),
    "a cleared treasure object must match a pack's object ID")
epoch = epoch + 3600
assert(not recent.IsHidden(treasure))
assert(recent.HideNote(treasure) and recent.IsHidden(treasure),
    "right-click must provide a fallback for treasure notes with no exposed completion flag")
settings.vignetteRadarHideCleared = false
assert(not recent.IsHidden(rare) and not recent.IsHidden(treasure),
    "turning the filter off must reveal all live and saved locations")
io.write("vignette radar recent-clears tests passed\n")
