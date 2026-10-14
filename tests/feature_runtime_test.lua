local addon = {}
local db = {
    vignetteRadarSurveyData = {}, vignetteRadarSurveying = true,
    vignetteRadarReplayRecording = true, vignetteRadarSurveyCellSize = .025,
    vignetteRadarPartyHunt = { receive = "off", shareSightings = false,
        shareStop = false, ignored = {} },
}
addon.GetSettings = function() return db end
local calls = { signals = {}, samples = 0 }
addon.VignetteRadarSurveyReplay = {
    Initialize = function(saved, character)
        assert(saved == db.vignetteRadarSurveyData and character == "Player-123")
    end,
    SetCellSize = function(size) calls.size = size end,
    SetSurveying = function(value) calls.surveying = value end,
    SetRecording = function(value) calls.recording = value end,
    Sample = function() calls.samples = calls.samples + 1 end,
    RecordSignal = function(signal)
        calls.signals[#calls.signals + 1] = signal
    end,
    Flush = function() calls.flushed = true end,
    ClearSession = function() calls.cleared = true end,
}
addon.VignetteRadarPartyHunt = {
    New = function()
        return {
            SetSettings = function() end,
            Start = function() calls.started = true end,
            Stop = function() calls.stopped = true end,
            PublishSighting = function(_, _, requested)
                return requested == true
            end,
            PublishStop = function(_, _, requested)
                return requested == true
            end,
        }
    end,
}
local directorCalls = { configure = 0 }
addon.VignetteRadarContextDirector = {
    New = function()
        return {
            Configure = function() directorCalls.configure = directorCalls.configure + 1 end,
            Update = function(_, snapshot, _, apply)
                directorCalls.snapshot = { treasure = snapshot.treasure,
                    questing = snapshot.questing }
                if apply then apply({ context = "treasure" }) end
            end,
        }
    end,
}
addon.VignetteRadarWorldFocus = {
    GetRoutePoint = function()
        return { key = "treasure:9", name = "Chest" }, "treasure"
    end,
}
local selection
addon.VignetteRadarIntelligence = {
    SetContext = function() end,
    SetSelection = function(value) selection = value end,
}
GetTime = function() return 10 end
GetServerTime = function() return 1800000000 end
UnitGUID = function() return "Player-123" end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/FeatureRuntime.lua"))("VignetteRadar", addon)
local runtime = addon.VignetteRadarFeatureRuntime
assert(runtime.Initialize() and calls.surveying and calls.recording
    and calls.size == .025 and not calls.started)
local point = { key = "rare:1", mapID = 100, mapX = .2, mapY = .3,
    worldX = 20, worldY = 30, category = "rare", name = "Rare" }
runtime.Observe(100, point, { point })
assert(calls.samples == 1 and #calls.signals == 1
    and calls.signals[1].kind == "appeared")
runtime.Observe(100, point, {})
assert(#calls.signals == 2 and calls.signals[2].kind == "vanished")
assert(directorCalls.snapshot and directorCalls.snapshot.treasure == true
    and directorCalls.snapshot.questing == false,
    "route point kind must reach the context director")
assert(addon.VignetteRadarContextOverlay and addon.VignetteRadarContextOverlay.context == "treasure")
assert(runtime.RefreshIntelligence() and selection.goalCategory == "treasure",
    "route point kind must reach the intelligence selection")
assert(not runtime.ShareSighting(point, false)
    and runtime.ShareSighting(point, true))
db.vignetteRadarReplayRecording = false
runtime.Configure()
runtime.Observe(100, point, { point })
assert(not calls.recording and #calls.signals == 2)
runtime.Shutdown()
assert(calls.flushed and calls.cleared and calls.stopped)
io.write("feature runtime tests passed\n")
