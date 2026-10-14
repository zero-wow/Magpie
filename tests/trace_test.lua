local addon = {}
local db = { vignetteRadarWorldFocusEnabled = true, vignetteRadarAutoRouteMapNotes = true }
addon.GetSettings = function() return db end
local now = 10
GetTime = function() return now end
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) chat[#chat + 1] = text end }
SlashCmdList = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Trace.lua"))("VignetteRadar", addon)
local Trace = addon.Trace

-- Off by default: nothing is stored or printed.
Trace.Load()
assert(not Trace.IsOn(), "the trace starts off")
Trace.Log("route", "ignored %s", "line")
assert(#Trace.Lines() == 0 and #chat == 0, "Log is a no-op while off")

-- /vrtrace on: lines are stored with a time stamp and topic, and shown live.
assert(SLASH_VIGNETTERADARTRACE1 == "/vrtrace" and SlashCmdList.VIGNETTERADARTRACE)
SlashCmdList.VIGNETTERADARTRACE("on")
assert(Trace.IsOn() and db.vignetteRadarTraceEnabled == true, "on is saved")
chat = {}
Trace.Log("route", "chose %s at %.0f yd, ok=%s", nil, 12.4, true)
local lines = Trace.Lines()
assert(lines[1] == "10.0 [route] chose nil at 12 yd, ok=true", lines[1])
assert(#chat == 1 and chat[1]:find("[route] chose nil", 1, true), "on prints new lines live")

-- Identical lines collapse into one with a repeat count.
Trace.Log("route", "chose %s at %.0f yd, ok=%s", nil, 12.4, true)
Trace.Log("route", "chose %s at %.0f yd, ok=%s", nil, 12.4, true)
assert(#lines == 1 and lines[1]:find("(x3)", 1, true), "repeats collapse")

-- A bad format never errors.
Trace.Log("route", "%d", "not a number")
assert(lines[#lines]:find("<format error>", 1, true))

-- The ring keeps the last 400 lines.
for index = 1, 450 do now = now + 1; Trace.Log("pool", "line %s", index) end
assert(#lines == 400 and lines[400]:find("line 450", 1, true)
    and lines[1]:find("line 51", 1, true), "the ring keeps the last 400 lines")

-- dump [n] prints the last n lines; clear empties the ring; off is saved.
chat = {}
SlashCmdList.VIGNETTERADARTRACE("dump 3")
assert(#chat == 4 and chat[4]:find("line 450", 1, true), "dump prints a header and the last n lines")
chat = {}
SlashCmdList.VIGNETTERADARTRACE("dump")
assert(#chat == 41, "dump defaults to 40 lines")
SlashCmdList.VIGNETTERADARTRACE("off")
assert(not Trace.IsOn() and db.vignetteRadarTraceEnabled == false and #Trace.Lines() == 400,
    "off keeps the saved lines")
SlashCmdList.VIGNETTERADARTRACE("clear")
assert(#Trace.Lines() == 0, "clear empties the ring")

-- A saved "on" is restored at login.
db.vignetteRadarTraceEnabled = true
Trace.Load()
assert(Trace.IsOn(), "saved on/off is restored")

-- World Focus logs why NextRouteStop chose or rejected each candidate.
local waypoint
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
    return { uiMapID = mapID, position = { x = x, y = y } }
end }
C_Map = {
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point) waypoint = point; return true end,
    GetUserWaypoint = function() return waypoint end,
    ClearUserWaypoint = function() waypoint = nil end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Data/QuestService.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
local focus = addon.VignetteRadarWorldFocus
local function Note(x, key, instanceID)
    return { kind = "treasure", key = key, name = key, mapID = 123, mapX = x / 1000, mapY = .5,
        worldX = x, worldY = 500, instanceID = instanceID or 42 }
end
local me = { worldX = 100, worldY = 500, instanceID = 42 }
Trace.Clear()
focus.Sync(123, me, {}, {}, { Note(300, "near"), Note(200, "elsewhere", 7) })
assert(focus.StartNearest("closest"), "Closest should start on the near note")
local found
for _, line in ipairs(Trace.Lines()) do
    if line:find("NextRouteStop kind=closest", 1, true) then found = line end
end
assert(found and found:find("seen: notes=2", 1, true)
    and found:find("rejected: otherInstance=1", 1, true)
    and found:find("chose treasure 'near'", 1, true), tostring(found))
focus.Clear(true, "test")
local cleared
for _, line in ipairs(Trace.Lines()) do
    if line:find("Clear why=test", 1, true) then cleared = true end
end
assert(cleared, "Clear logs its reason")

io.write("trace tests passed\n")
