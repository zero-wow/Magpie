-- luacheck: ignore 131
-- luacheck: globals VignetteRadarDB WaffleHouseDB C_Map C_DateAndTime C_ChatInfo UiMapPoint CreateVector2D
-- luacheck: globals GetTime UnitName IsInGroup IsInRaid issecretvalue C_SuperTrack C_QuestLog C_Minimap
-- luacheck: globals SlashCmdList DEFAULT_CHAT_FRAME
-- Route/world track: Zone Sweep, Today, Shared Sightings In, Learned Data
-- Export/Import and the World Map Route stops.
VignetteRadarDB, WaffleHouseDB = nil, nil
local now = 100
GetTime = function() return now end
UnitName = function() return "Me" end
local inGroup, inRaid = true, false
IsInGroup = function() return inGroup end
IsInRaid = function() return inRaid end
local waypoint
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
    return { uiMapID = mapID, position = { x = x, y = y } }
end }
local linkPoint
C_Map = {
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point) waypoint = point; return true end,
    GetUserWaypoint = function() return waypoint end,
    ClearUserWaypoint = function() waypoint = nil end,
    GetWorldPosFromMapPos = function(_, position) return 42, { x = position.x * 1000, y = position.y * 1000 } end,
    GetMapInfo = function() return { name = "Test Zone" } end,
    GetUserWaypointFromHyperlink = function() return linkPoint end,
}
C_DateAndTime = { GetSecondsUntilDailyReset = function() return 4 * 3600 + 720 end,
    GetSecondsUntilWeeklyReset = function() return 2 * 86400 + 3 * 3600 end }
local lockdown = false
C_ChatInfo = { InChatMessagingLockdown = function() return lockdown end,
    RegisterAddonMessagePrefix = function() return 0 end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }

local addon = {}
for _, file in ipairs({ "Core/Secret.lua", "Core/Core.lua", "Core/Bus.lua", "Core/Points.lua", "Core/Focus.lua",
    "Core/Recent.lua", "Core/Declutter.lua", "Data/QuestService.lua", "Data/RareSpawns.lua",
    "Data/LearnedTransfer.lua", "Data/Today.lua", "Routes/PartyHunt.lua", "Routes/SharedSightings.lua",
    "Routes/WorldFocus.lua", "Routes/ZoneSweep.lua", "UI/Style.lua", "UI/MapRoute.lua" }) do
    assert(loadfile(file))("VignetteRadar", addon)
end
local settings = addon.GetSettings()
settings.vignetteRadarWorldFocusEnabled = true
local Points, World, Sweep = addon.VignetteRadarPoints, addon.VignetteRadarWorldFocus, addon.VignetteRadarZoneSweep
local Today, Shared, Transfer = addon.VignetteRadarToday, addon.VignetteRadarSharedSightings,
    addon.VignetteRadarLearnedTransfer
assert(settings.vignetteRadarSharedSightings and settings.vignetteRadarMapRoute and
    settings.vignetteRadarZoneSweepKinds == "both" and settings.vignetteRadarZoneSweepMax == 40
    and settings.vignetteRadarTodayFilter == "left" and settings.vignetteRadarSharedSightingsMinutes == 10,
    "Core validates the new settings with their defaults")

local function Note(key, kind, x, y, extra)
    local note = { key = key, kind = kind, name = key, mapID = 123, mapX = x / 1000, mapY = y / 1000,
        worldX = x, worldY = y, instanceID = 42 }
    for field, value in pairs(extra or {}) do note[field] = value end
    return note
end

-- Zone Sweep order: nearest first, then 2-opt removes the crossing.
do
    local start = { worldX = 0, worldY = 0 }
    local a, b, c, d = Note("a", "treasure", 100, 0), Note("b", "treasure", 100, 100),
        Note("c", "treasure", 0, 150), Note("d", "treasure", 200, 50)
    local order, yards = Sweep.Order({ c, a, d, b }, start)
    assert(#order == 4, "every stop is planned once")
    local naive = 0
    for _, list in ipairs({ { a, b, c, d } }) do
        local at = start
        for _, item in ipairs(list) do
            naive = naive + math.sqrt((item.worldX - at.worldX) ^ 2 + (item.worldY - at.worldY) ^ 2); at = item
        end
    end
    assert(yards <= naive + .01, "2-opt never makes the path longer")
    assert(#Sweep.Order({}, start) == 0, "empty plan")
end

-- A zone: one live rare, its pack note (duplicate), two treasures (one done).
local done = {}
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsQuestFlaggedCompletedOnAccount = function() return false end }
C_Minimap = { IsTrackingAccountCompletedQuests = function() return false end }
local player = { worldX = 0, worldY = 0, instanceID = 42, mapID = 123 }
local rare = { key = "live:1", category = "rare", name = "Live Rare", mapID = 123, mapX = .3, mapY = .0,
    worldX = 300, worldY = 0, instanceID = 42 }
local packRare = Note("pack:rare", "mob", 310, 0, { name = "Live Rare" })
local chestA = Note("pack:chestA", "treasure", 100, 0, { questID = 501 })
local chestB = Note("pack:chestB", "treasure", 600, 0, { questID = 502 })
done[502] = true
local notes = { packRare, chestA, chestB }
addon._rawMapNotes = notes
local kept = addon.VignetteRadarDeclutter.Apply(notes, { rare }, player, settings)
Points.Publish({ mapID = 123, player = player, targets = { rare }, notes = kept })

local candidates = Sweep.Candidates()
assert(#candidates == 2, "live rare + chest A; done chest and duplicate pack rare are out: " .. #candidates)
settings.vignetteRadarZoneSweepKinds = "treasure"
assert(#Sweep.Candidates() == 1 and Sweep.Candidates()[1] == chestA, "kind filter")
settings.vignetteRadarZoneSweepKinds = "both"

World.Sync(123, player, { rare }, {}, kept)
local ok = Sweep.Start()
assert(ok and World.GetRouteChoice() == "sweep" and World.Status():find("Zone Sweep", 1, true),
    "Start hands a sweep route to World Focus")
local plan, at = World.GetSweepPlan()
assert(#plan == 2 and at == 1 and plan[1].key == "pack:chestA" and select(2, World.GetRoutePoint()) == "treasure",
    "the nearest stop first, kind from the item")
local horizon = World.GetHorizon(3)
assert(#horizon == 2 and horizon[2].item.key == "live:1", "the horizon previews the planned order")
local stops = addon.VignetteRadarMapRoute.Stops()
assert(#stops == 2 and stops[1].current and stops[2].item.key == "live:1", "map route follows the sweep plan")
assert(World.SkipRouteStop() and World.GetActiveTarget().key == "live:1", "skip moves to the next planned stop")
World.SkipRouteStop()
assert(not World.IsRouteActive(), "the sweep completes after the last stop")
assert(#addon.VignetteRadarMapRoute.Stops() == 0, "no route, no map stops")
assert(not World.StartSweep({}), "an empty plan is refused")

-- Map route placement: own map coordinates, or the world position on another map.
do
    local x, y = addon.VignetteRadarMapRoute.Place(chestA, 123)
    assert(x == .1 and y == 0, "same map uses the stop's map x/y")
    C_Map.GetMapPosFromWorldPos = function(_, _, mapID) return mapID, { x = .25, y = .75 } end
    x, y = addon.VignetteRadarMapRoute.Place(chestA, 12)
    assert(x == .25 and y == .75, "another map projects the world position")
    C_Map.GetMapPosFromWorldPos = function(_, _, mapID) return mapID, { x = 1.5, y = .5 } end
    assert(addon.VignetteRadarMapRoute.Place(chestA, 12) == nil, "off-map stops are skipped")
end

-- Today: done and left in this zone, reset times, routing.
do
    local data = Today.Build()
    assert(data.zone == "Test Zone" and data.daily == 4 * 3600 + 720, "zone and reset")
    assert(data.counts.rareLeft == 1 and data.counts.treasureLeft == 1 and data.counts.treasureDone == 1
        and data.counts.live == 1, "counts: live rare, chest A left, chest B done")
    assert(data.rows[1].state == "live" and data.rows[#data.rows].state == "done", "live first, done last")
    assert(Today.Duration(4 * 3600 + 720) == "4 Hr 12 Min" and Today.Duration(2 * 86400 + 3600) == "2 Days 1 Hr"
        and Today.Duration(30) == "1 Min", "durations")
    local routed = Today.Route(data.rows[2])
    assert(routed and World.GetActiveTarget().key == "pack:chestA", "a click routes through Focus")
    World.Clear()
end

-- Shared Sightings In: chat map-pin links and VR addon messages.
do
    linkPoint = { uiMapID = 123, position = { x = .4, y = .5 } }
    local link = "|cffffff00|Hworldmap:123:4000:5000|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r"
    local note = Shared.FromChat(link .. " Rare: Big Bad", "Friend-Realm")
    assert(note and note.kind == "mob" and note.name == "Big Bad" and note.evidence == "party"
        and note.source == "Party" and note.worldX == 400 and note.note == "Shared by Friend", "chat link becomes a note")
    assert(Shared.FromChat(link .. " Rare: Big Bad", "Me-Realm") == nil, "own messages are skipped")
    local again, why = Shared.FromChat(link .. " look", "Friend-Realm")
    assert(again == note and why == "refreshed" and #Shared.List() == 1, "same spot refreshes")
    lockdown = true
    assert(Shared.FromChat(link, "Other-Realm") == nil, "chat lockdown: skipped")
    lockdown = false
    issecretvalue = function(value) return value == "SECRET" end
    assert(Shared.FromChat("SECRET", "Other-Realm") == nil, "secret text: skipped")
    issecretvalue = nil
    settings.vignetteRadarSharedSightingsChat = false
    assert(Shared.FromChat(link, "Other-Realm") == nil, "chat reading can be switched off")
    settings.vignetteRadarSharedSightingsChat = true
    -- An addon message in Party Hunt's own format.
    local payload = table.concat({ "1", "G", "77-1", 123, 7000, 2000, "treasure", "pack:x", "Shiny Chest" }, "|")
    assert(Shared.FromAddon("VRHUNT1", payload, "PARTY", "Ally-Realm"), "addon message accepted")
    assert(#Shared.List() == 2 and Shared.List()[2].kind == "treasure" and Shared.List()[2].mapX == .7,
        "addon sighting becomes a note")
    assert(not Shared.FromAddon("VRHUNT1", "1|G|bad", "PARTY", "Ally-Realm"), "bad payload refused")
    assert(not Shared.FromAddon("OTHER", payload, "PARTY", "Ally-Realm"), "other prefixes ignored")
    local scan = {}
    assert(Shared.AppendTo(scan, 123) == 2 and Shared.AppendTo({}, 999) == 0, "notes join this map's scan")
    Points.Publish({ mapID = 123, player = player, notes = scan })
    assert(#Points.Filter({ evidence = "party" }) == 2, "the registry keeps evidence party")
    now = now + 601
    assert(#Shared.List() == 0, "shared points expire")
end

-- Learned Data Export/Import: round trip, merge, and a safe import.
do
    settings.vignetteRadarRareSpawns = { [4242] = { name = "Big, Rare~|cffff0000X|r", map = 123, spawns = {
        { x = 100.26, y = -50, z = 12.5, i = 42, m = 123, mx = .1, my = .2, n = 3, f = 1000, l = 2000 } } } }
    settings.vignetteRadarPins = { { id = "p1", name = "My pin", mapID = 123, mapX = .5, mapY = .5,
        worldX = 500, worldY = 500, instanceID = 42, at = 3000 } }
    local text, info = Transfer.Export()
    assert(text and info.records == 2 and text:match("^VRL1:2:%x+:"), "export header")
    assert(not text:find("|", 1, true), "no escape pipes in the string")
    local zone = Transfer.Export("zone", 999)
    assert(zone == nil, "zone export only takes that map")
    local data = assert(Transfer.Decode(text))
    assert(#data.spawns == 1 and data.spawns[1].name == "Big, Rare~X" and data.spawns[1].x == 100.3
        and data.spawns[1].z == 12.5 and #data.pins == 1 and data.pins[1].name == "My pin", "decode")
    -- Import into an empty profile.
    settings.vignetteRadarRareSpawns, settings.vignetteRadarPins = {}, {}
    local counts = assert(Transfer.Import(text))
    assert(counts.spawnsAdded == 1 and counts.pinsAdded == 1, "import adds")
    assert(#addon.VignetteRadarRareSpawns.Spawns(4242) == 1, "spawn stored")
    counts = assert(Transfer.Import(text))
    assert(counts.spawnsMerged == 1 and counts.spawnsAdded == 0 and counts.pinsSkipped == 1, "re-import merges")
    assert(Transfer.Summary(counts):find("merged", 1, true), "summary line")
    -- Refused: wrong header, version, checksum, size, count.
    assert(not Transfer.Decode("hello"), "not an export")
    assert(not Transfer.Decode(text:gsub("^VRL1", "VRL9")), "unknown version")
    local tampered = text:sub(1, -2) .. (text:sub(-1) == "0" and "1" or "0")
    assert(not Transfer.Decode(tampered), "checksum catches a change")
    assert(not Transfer.Decode(string.rep("A", Transfer.MAX_BYTES + 1)), "size cap")
    local function Build(body, count)
        local sum = 0
        for index = 1, #body do sum = (sum * 31 + body:byte(index)) % 16777213 end
        return string.format("VRL1:%d:%06x:%s", count, sum, body)
    end
    assert(not Transfer.Decode(Build("P,x,1,.5,.5,1,1,,1", 2)), "count must match")
    -- Bad records are skipped, never trusted: code, out of range, bad names.
    local evil = Build(table.concat({ "S,1,os.exit(),123,1,1,,,0.5,0.5,1,1,2", "S,1,Name,123,1,1,,,5,0.5,1,1,2",
        "P,%7C,1,0.5,0.5,1,1,,1", "X,1,2,3", "S,99999999999,N,1,1,1,,,0.5,0.5,1,1,2" }, "~"), 5)
    data = assert(Transfer.Decode(evil))
    assert(#data.spawns == 0 and #data.pins == 0 and data.skipped == 5, "every bad record skipped")
end

-- /vr words go ahead of the radar's own handler; the rest pass through.
do
    local passed
    SlashCmdList = { VIGNETTERADAR = function(message) passed = message end }
    DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    assert(loadfile("UI/TransferBox.lua"))("VignetteRadar", addon)
    local opened
    addon.VignetteRadarIntelligence = { Open = function(tab) opened = tab end }
    SlashCmdList.VIGNETTERADAR("Config")
    assert(passed == "Config", "other words reach the radar unchanged")
    SlashCmdList.VIGNETTERADAR("today")
    assert(opened == "Today" and passed == "Config", "/vr today opens the Today tab")
    local started
    local original = Sweep.Start
    Sweep.Start = function() started = true; return false, "none" end
    SlashCmdList.VIGNETTERADAR("sweep")
    Sweep.Start = original
    assert(started, "/vr sweep starts a Zone Sweep")
end

print("route/world tests passed")
