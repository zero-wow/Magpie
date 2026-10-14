local addon = {}
local counts = { A = 0, B = 0, C = 0 }
local fixtures = {
    A = {
        { key = "A:1", source = "A", mapID = 100, mapX = .5, mapY = .5,
            kind = "mob", name = "The Old Hunter", npcID = 42, worldX = 500, worldY = 500 },
        { key = "A:2", source = "A", mapID = 100, mapX = .7, mapY = .7,
            kind = "treasure", name = "Hidden Chest" },
    },
    B = {
        { key = "B:1", source = "B", mapID = 100, mapX = .501, mapY = .5,
            kind = "mob", name = "Old Hunter", npcID = 42, worldX = 501, worldY = 500 },
        { key = "B:2", source = "B", mapID = 100, mapX = .503, mapY = .5,
            kind = "mob", name = "The Old Hunter", npcID = 99 },
        { key = "B:3", source = "B", mapID = 100, mapX = .7, mapY = .7,
            kind = "treasure", name = "Hidden Chest" },
    },
    C = {
        { key = "C:1", source = "C", mapID = 101, mapX = .5, mapY = .5,
            kind = "mob", name = "The Old Hunter", npcID = 42 },
    },
}
addon.VignetteRadarPOIs = {
    ZoneSources = function(mapID)
        if mapID == 100 then
            return { { id = "A", mapID = 100, enabled = true },
                { id = "B", mapID = 100, enabled = true },
                { id = "C", mapID = 101, enabled = true },
                { id = "Disabled", mapID = 100, enabled = false } }
        end
        return {}
    end,
    Collect = function(_, source)
        assert(fixtures[source], "queried unavailable source")
        counts[source] = counts[source] + 1
        return fixtures[source]
    end,
}
local now = 100
GetTime = function() return now end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Data/SourceFusion.lua"))("VignetteRadar", addon)
local fusion = addon.VignetteRadarSourceFusion
local vector = function(x, y) return { x = x, y = y } end
local mapToWorld = function(_, point) return point.x * 1000, point.y * 1000, 1 end
local markers, stats = fusion.Collect(100, { "A", "B", "C", "Disabled" },
    mapToWorld, vector, { preferredSource = "B" })
assert(stats.sources == 3 and stats.input == 6 and stats.merged == 2
    and stats.output == 4 and not stats.limited)
assert(counts.A == 1 and counts.B == 1 and counts.C == 1)
assert(markers[1].key == "B:1" and markers[1].displayPoint == fixtures.B[1]
    and markers[1].matchCount == 2 and #markers[1].provenance == 2
    and markers[1].conflicts.names and markers[1].conflicts.coordinates)
assert(markers[2].matchCount == 2 and markers[3].matchCount == 1
    and markers[4].mapID == 101, "different IDs and maps stay separate")
fusion.Collect(100, { "A", "B" }, mapToWorld, vector)
assert(counts.A == 1 and counts.B == 1, "provider snapshots are reused")
fusion.Invalidate("B", 100)
fusion.Collect(100, { "A", "B" }, mapToWorld, vector)
assert(counts.A == 1 and counts.B == 2, "only changed provider refreshes")
now = now + 31
fusion.Collect(100, { "A", "B" }, mapToWorld, vector)
assert(counts.A == 2 and counts.B == 3, "snapshots expire")

local live = { key = "live:42", source = "local", evidence = "live", mapID = 100,
    mapX = .5, mapY = .5, kind = "mob", name = "The Old Hunter", npcID = 42 }
local liveMarkers = fusion.Fuse({ fixtures.A[1], live }, { preferredSource = "A" })
assert(#liveMarkers == 1 and liveMarkers[1].displayPoint == live
    and liveMarkers[1].evidence == "live", "live evidence wins the display point")
local separate = fusion.Fuse({
    { source = "A", mapID = 100, mapX = .1, mapY = .1, kind = "mob", name = "A", npcID = 1 },
    { source = "B", mapID = 100, mapX = .1, mapY = .1, kind = "treasure", name = "A", npcID = 1 },
    { source = "C", mapID = 100, mapX = .1, mapY = .1, kind = "mob", name = "A", npcID = 2 },
})
assert(#separate == 3, "type and ID conflict prevent false merges")
local many = {}
for index = 1, 2200 do
    many[index] = { source = tostring(index), key = tostring(index), mapID = 100,
        mapX = .3, mapY = .3, kind = "note", name = "Same Place" }
end
local bounded, limits = fusion.Fuse(many)
assert(limits.input == 2048 and limits.limited and #bounded >= 1)
print("Source Fusion tests passed")
