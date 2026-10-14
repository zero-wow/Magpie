-- Compass: the one feed behind the Bearing Bar and the Horizon Ribbon.
-- Geometry, one kind color, the feed's points (pack-note dedupe, quests
-- here), route stops and focus, caching per scan, and both views reading the
-- same feed table.
local settings = { vignetteRadarEnabled = true, vignetteRadarMapNotesVisible = true, vignetteRadarPOISource = "auto",
    vignetteRadarPOITypes = { mob = true, treasure = true, entrance = false }, vignetteRadarQuestColors = true,
    vignetteRadarBeaconsEnabled = false }
local addon = { GetSettings = function() return settings end }
addon.VignetteRadarStyle = { Color = function(slot)
    if slot == "rare" then return .8, .9, 1 end
    if slot == "boss" then return 1, .2, .1 end
    if slot == "accent" then return .5, .5, .5 end
    if slot == "treasure" then return 1, .7, .2 end
end }
addon.VignetteRadarQuestColors = { { .3, .7, 1 }, { .9, .3, .6 } }
local facing = 0
GetPlayerFacing = function() return facing end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Compass.lua"))("VignetteRadar", addon)
local Compass, Points = assert(addon.VignetteRadarCompass), addon.VignetteRadarPoints
local PI = math.pi
local function Near(a, b) return math.abs(a - b) < 1e-9 end

-- Geometry: +x is heading 0, positive bearings are to the left.
local player = { worldX = 0, worldY = 0, instanceID = 1 }
assert(Near(Compass.Heading(player, { worldX = 0, worldY = 5 }), PI / 2), "heading is the world angle")
assert(Near(Compass.Relative(PI / 2, PI / 2), 0) and Near(Compass.Relative(-PI + .1, PI - .1), .2),
    "relative bearings wrap to -pi..pi")
assert(Compass.Bearing(player, { worldX = 1, worldY = 1, instanceID = 2 }, 0) == nil, "another instance has none")
assert(Near(Compass.Facing(), 0), "facing reads GetPlayerFacing")
assert(Compass.Yards(player, { worldX = 3, worldY = 4 }) == 5, "straight-line yards")

-- One color rule for both views.
assert(select(1, Compass.Color("rare", {})) == .8 and select(1, Compass.Color("rare", { isWorldBoss = true })) == 1,
    "kind color, world bosses take the boss role")
assert(select(1, Compass.Color("quest", { colorSlot = 2 })) == .9, "quests take their radar quest color")
assert(select(1, Compass.Color("entrance")) == .5 and select(1, Compass.Color("guide")) == .5,
    "entrances and unknown kinds take the accent")

-- The feed: live rares and treasures, quests, pack notes (minus copies of
-- live points), the route's next stops and the focus.
local rare = { key = "r1", name = "Silvermaw", category = "rare", worldX = 100, worldY = 0, instanceID = 1 }
local stale = { key = "r2", name = "Gone", category = "rare", stale = true, worldX = 50, worldY = 0, instanceID = 1 }
local quest = { questID = 7, name = "Troll Trouble", colorSlot = 1, worldX = 0, worldY = 80, instanceID = 1 }
local copy = { kind = "mob", name = "Silvermaw", worldX = 110, worldY = 0, instanceID = 1 }
local chest = { kind = "treasure", name = "Treasure location", worldX = -60, worldY = 0, instanceID = 1 }
local cave = { kind = "entrance", name = "Cave", worldX = -60, worldY = 30, instanceID = 1 }
local routeOn, active = true, chest
addon.VignetteRadarWorldFocus = {
    IsRouteActive = function() return routeOn end,
    GetActiveTarget = function() return active end,
    GetHorizon = function() return { { item = chest, current = true }, { item = rare, kind = "rare" } } end,
    GetFocusedStep = function() return { mapID = 3, worldX = 100, worldY = 0 } end,
}
Points.Publish({ mapID = 3, player = player, targets = { rare, stale }, quests = { quest },
    notes = { copy, chest, cave } })
local feed = Compass.Feed()
local kinds = {}
for _, entry in ipairs(feed.points) do kinds[#kinds + 1] = entry.kind .. ":" .. entry.source end
assert(table.concat(kinds, ",") == "rare:live,quest:quest,treasure:note",
    "live rare, quest and the chest note; the stale rare, the copy of the live rare and the cave (type off) are out: "
        .. table.concat(kinds, ","))
assert(feed.points[1].focused and Near(feed.points[1].heading, 0) and feed.points[1].distance == 100,
    "entries carry the focused flag, heading and yards")
assert(feed.points[2].r == .3, "quest entries carry their quest color")
assert(#feed.stops == 2 and feed.stops[1].label == "1" and feed.stops[1].current and feed.stops[2].kind == "rare",
    "the route's next stops are numbered")
assert(feed.focus and feed.focus.raw == chest, "the focused point")

-- One feed per scan: both views read the same table until the registry
-- publishes again or the focus or route changes.
assert(Compass.Feed() == feed, "the same feed until something changes")
local revision = Compass.Revision()
local ticks = Compass.Ticks(nil, 8)
assert(Compass.Revision() == revision, "the ribbon's ticks reuse the feed")
assert(#ticks == 2 and ticks[1].item == chest and ticks[1].label == "1" and ticks[2].item == rare,
    "ticks: stops first, the focus and the rare are not repeated")
addon.Bus.Emit("FOCUS_CHANGED")
assert(Compass.Feed() ~= feed, "a focus change rebuilds the feed")
feed = Compass.Feed()
Points.Publish({ mapID = 3, player = player, targets = { rare }, quests = {}, notes = {} })
assert(Compass.Feed() ~= feed, "a new scan rebuilds the feed")

-- The Bearing Bar picks from the same feed it shares with the ribbon.
assert(loadfile("Routes/Beacons.lua"))("VignetteRadar", addon)
settings.vignetteRadarBeaconRares, settings.vignetteRadarBeaconRange, settings.vignetteRadarBeaconMax = true, 450, 8
local picked = addon.VignetteRadarBeacons.Select(Compass.Feed(), settings)
assert(#picked == 1 and picked[1].raw == rare, "the bar picks the live rare from the shared feed")
routeOn, active = false, nil
addon.Bus.Emit("ROUTE_CHANGED")
assert(#Compass.Feed().stops == 0 and Compass.Feed().focus == nil, "a route change clears the stops")

-- Quests Here Only: the bar keeps quests whose area you are in.
do
    addon.VignetteRadarQuestData = { IsQuestInArea = function(id) return id == 8 end }
    settings.vignetteRadarAreaQuests = true
    local here = Compass.Build({ mapID = 3, player = player }, { quest = { quest,
        { questID = 8, name = "Here", worldX = 0, worldY = 20, instanceID = 1 } } })
    assert(here.anyHere and not here.points[1].here and here.points[2].here, "quests are marked here or not")
    settings.vignetteRadarAreaQuests, addon.VignetteRadarQuestData = nil, nil
end

print("compass tests passed")
