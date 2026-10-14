-- luacheck: globals VignetteRadarDB WaffleHouseDB SlashCmdList SLASH_VIGNETTERADARWAY1 SLASH_VIGNETTERADARWAY2
-- /way parsing (TomTom syntax), waypoints feeding Focus/World Focus, and the
-- TomTom stand-in: installed only without a real TomTom, never over one.
VignetteRadarDB, WaffleHouseDB = nil, nil
_G.TomTom = nil
local addon = {}
local tomtomLoaded = false
_G.C_AddOns = { IsAddOnLoaded = function(name) return name == "TomTom" and tomtomLoaded, false end }
_G.C_Map = {
    GetBestMapForUnit = function() return 2371 end,
    GetWorldPosFromMapPos = function(mapID, v)
        if mapID == 1 then return nil end
        return 2552, { x = v.x * 1000, y = v.y * 1000 }
    end,
}
_G.SlashCmdList = { OTHER = function() end }
_G.SLASH_OTHER1 = "/other"
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/Way.lua"))("VignetteRadar", addon)
local Way, Focus = assert(addon.VignetteRadarWay), addon.VignetteRadarFocus
local settings = addon.GetSettings()
assert(settings.vignetteRadarWayCommand == true and settings.vignetteRadarTomTomStandIn == true, "defaults on")

local selected, active = {}, nil
addon.VignetteRadarWorldFocus = {
    SelectPoint = function(point, direct) selected[#selected + 1] = { point = point, direct = direct }; active = point; return true end,
    GetActiveTarget = function() return active end,
    Clear = function() active = nil; return true end,
}

-- Parsing.
local p = Way.Parse("45.2 30.1 Big Chest", 2371)
assert(p.mapID == 2371 and math.abs(p.x - .452) < 1e-9 and math.abs(p.y - .301) < 1e-9 and p.title == "Big Chest")
p = Way.Parse("#2248 50 60", 2371)
assert(p.mapID == 2248 and p.x == .5 and p.y == .6 and p.title == nil, "#mapID form")
p = Way.Parse("2248 50 60 Rare spot", 2371)
assert(p.mapID == 2248 and p.title == "Rare spot", "three leading numbers: map first")
p = Way.Parse("45,2 30,1", 2371)
assert(math.abs(p.x - .452) < 1e-9 and math.abs(p.y - .301) < 1e-9, "comma decimals")
p = Way.Parse("45.2, 30.1 X", 2371)
assert(math.abs(p.y - .301) < 1e-9 and p.title == "X", "comma separator")
assert(Way.Parse("clear").clear and Way.Parse("reset").clear)
assert(not Way.Parse("") and not Way.Parse("abc def") and not Way.Parse("150 20"), "bad input refused")
assert(not Way.Parse("10 20", nil), "no current map and no map given")

-- Adding focuses the newest waypoint (no C_Timer: at once).
local uid = Way.Add(2371, .5, .25, { title = "Chest", from = "Pack" })
assert(uid and uid[1] == 2371 and uid.title == "Chest" and uid.from == "Pack", "TomTom-shaped uid")
assert(#selected == 1 and selected[1].direct == true and selected[1].point.worldX == 500
    and selected[1].point.worldY == 250 and selected[1].point.instanceID == 2552, "World Focus got the point")
assert(Focus.Get().key == "way:" .. Way.Key(2371, .5, .25, "Chest"))
assert(Way.Add(2371, .5, .25, { title = "Chest" }) == uid, "same place and title: same uid")
assert(Way.IsValid(uid) and Way.Exists(2371, .5, .25, "Chest"))
assert(not Way.Add(1, .5, .5), "maps without a world position are refused")
local quiet = Way.Add(2371, .1, .1, { title = "Quiet", crazy = false })
assert(quiet and #selected == 2, "crazy = false does not move the waypoint") -- 2nd select was the duplicate add

-- Removing the shown waypoint clears focus; others leave it alone.
assert(Way.Remove(quiet) and Focus.Get() ~= nil)
assert(Way.Remove(uid) and Focus.Get() == nil and active == nil, "removing the shown waypoint clears it")
assert(not Way.IsValid(uid) and not Way.Remove(uid))

-- Closest: the player sits near the second point.
Way.Add(2371, .9, .9, { title = "Far", crazy = false })
Way.Add(2371, .2, .2, { title = "Near", crazy = false })
addon.VignetteRadarPoints.Publish({ mapID = 2371, player = { worldX = 190, worldY = 190, instanceID = 2552 } })
local closest = Way.SetClosest()
assert(closest and closest.title == "Near" and Focus.Get().name == "Near", "closest waypoint focused")

-- The command path.
Way.Command("#2371 10 10 Typed")
assert(Focus.Get().name == "Typed")
Way.Command("clear")
assert(#Way.List() == 0 and Focus.Get() == nil, "/way clear empties the list")

-- Stand-in: installed without TomTom, with /way and /vrway.
Way.Install()
assert(_G.TomTom and _G.TomTom.vignetteRadarStandIn and Way.IsStandIn(), "stand-in installed")
assert(SLASH_VIGNETTERADARWAY1 == "/vrway" and SLASH_VIGNETTERADARWAY2 == "/way")
local t = _G.TomTom:AddWaypoint(2371, .3, .4, { title = "From Pack", persistent = nil, minimap = true, world = true })
assert(t and Focus.Get().name == "From Pack")
local key = _G.TomTom:GetKeyArgs(2371, .3, .4, "From Pack")
assert(_G.TomTom.waypoints[2371][key] == t and _G.TomTom:WaypointExists(2371, .3, .4, "From Pack"),
    "WorldQuestTab-style direct waypoints lookup works")
assert(_G.TomTom:IsValidWaypoint(t) and _G.TomTom:RemoveWaypoint(t) and not _G.TomTom:IsValidWaypoint(t))

-- Switching off removes only our own stand-in.
settings.vignetteRadarTomTomStandIn = false
Way.Install()
assert(_G.TomTom == nil, "stand-in removed")

-- A real TomTom (global present or addon loaded) is never replaced, and /way is left to it.
local real = { real = true }
_G.TomTom = real
settings.vignetteRadarTomTomStandIn = true
Way.Install()
assert(_G.TomTom == real, "real TomTom kept")
_G.TomTom, tomtomLoaded = nil, true
Way.Install()
assert(_G.TomTom == nil, "a loading TomTom is not replaced")
SlashCmdList.TOMTOM_WAY, _G.SLASH_TOMTOM_WAY1 = function() end, "/way"
Way.Install()
assert(SLASH_VIGNETTERADARWAY2 == nil, "/way stays with its owner")
print("way_test ok")
