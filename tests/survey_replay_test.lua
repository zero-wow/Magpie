local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Data/SurveyReplay.lua"))("VignetteRadar", addon)
local api = addon.VignetteRadarSurveyReplay
local saved = {}
api.Initialize(saved, "Zero-Realm")
api.SetSurveying(true)
api.SetRecording(true)

local function point(x, y, wx, wy, map)
    return { mapID=map or 100, mapX=x, mapY=y, worldX=wx, worldY=wy, instanceID=1 }
end

assert(api.Sample(point(.1, .1, 0, 0), 0, 1000))
assert(not api.Sample(point(.2, .2, 20, 20), 1, 1001), "sampling interval must throttle")
assert(api.Sample(point(.13, .1, 20, 0), 3, 1003))
local cells, count = api.GetCoverage(100)
assert(count == 2 and cells["4:4"] and cells["5:4"], "only visited cells are covered")
assert(not api.Sample(point(.9, .9, 10000, 10000), 6, 1006), "teleport must not paint destination")
assert(api.Sample(point(.91, .9, 10020, 10000), 9, 1009), "sampling resumes after jump")
assert(select(2, api.GetCoverage(100)) == 3)
assert(saved.coverage == nil, "sampling must not write SavedVariables")
assert(api.Flush() and #saved.coverage == 3 and saved.version == 1)
assert(not api.Flush(), "clean flush is a no-op")
assert(api.SetCellSize(.05) and api.GetCellSize() == .05)
assert(select(2, api.GetCoverage(100)) == 0, "cell sizes must not mix in one layer")
assert(api.Flush() and saved.cellSize == .05)
assert(api.SetCellSize(.025))
assert(api.Flush())

local signal = { kind="appeared", identity="npc:42", source="local vignette",
    evidence="live detection", name="A Rare", point=point(.91, .9, 10020, 10000) }
assert(api.RecordSignal(signal, 1010))
assert(api.RecordSignal(signal, 1012))
local timeline = api.GetTimeline()
assert(timeline[#timeline].count == 2 and timeline[#timeline].source == "local vignette")
timeline[#timeline].source = "changed"
assert(api.GetTimeline()[#timeline].source == "local vignette", "readers cannot mutate replay")
assert(not api.RecordSignal({kind="appeared", identity="npc:1"}, 1013))
assert(api.SaveReplay("Rare sighting", 1015))
local savedReplay = api.GetSavedReplays()[1]
assert(savedReplay.name == "Rare sighting" and savedReplay.events[#savedReplay.events].evidence == "live detection")
assert(api.DeleteReplay(1) and #api.GetSavedReplays() == 0)
api.ClearSession()
assert(#api.GetTimeline() == 0 and not api.RecordSignal(signal, 1016))

api.Initialize(saved, "Other-Realm")
assert(select(2, api.GetCoverage(100)) == 0, "character coverage stays separate")
assert(select(2, api.GetCoverage(100, true)) == 3, "shared view unions characters")
api.SetSurveying(true)
for n = 1, 3000 do
    local x = ((n-1) % 40 + .1) / 40
    local y = (math.floor((n-1) / 40) % 40 + .1) / 40
    api.Sample(point(x, y, n*20, 0, 100 + math.floor(n/1600)), n*3, 2000+n)
end
api.Flush()
assert(#saved.coverage <= 2048, "coverage storage must stay capped")

api.SetRecording(true)
for n = 1, 400 do
    assert(api.RecordSignal({ kind="changed", identity="npc:" .. n,
        source="saved pack", evidence="saved location", point=point(.2, .2, 1, 1) }, 5000+n))
end
assert(#api.GetTimeline() == 256, "replay ring must stay capped")
assert(api.SaveReplay("Bounded", 6000))
assert(#api.GetSavedReplays()[1].events == 128, "saved excerpt must stay capped")
-- A zone that stays inside the cap keeps all of its cells, even ones older
-- than the zone that falls out.
local capped = { coverage = {} }
local function cell(mapID, key, at)
    capped.coverage[#capped.coverage+1] = { character="Trim-Realm", mapID=mapID,
        cell=key, size=.025, at=at }
end
cell(500, "0:0", 1000)
for zone = 1, 24 do cell(600 + zone, "1:1", 1000 + zone) end
cell(500, "2:2", 1100)
api.Initialize(capped, "Trim-Realm")
assert(select(2, api.GetCoverage(500)) == 2, "a retained zone must keep its older cells")
assert(select(2, api.GetCoverage(601)) == 0, "the oldest zone past the cap is dropped")
assert(select(2, api.GetCoverage(624)) == 1)
io.write("survey and replay tests passed\n")
