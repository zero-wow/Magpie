local addon = {}
local function Frame(x, y)
    local frame = { x = x, y = y }
    function frame:GetCenter() return self.x, self.y end
    function frame:GetPoint() return self.point, self.relative end
    function frame:ClearAllPoints() self.point, self.relative = nil, nil end
    function frame:SetPoint(point, relative, relativePoint, offsetX, offsetY)
        self.point, self.relative, self.relativePoint = point, relative, relativePoint
        self.offsetX, self.offsetY = offsetX, offsetY
    end
    function frame:HookScript(_, callback) self.onUpdate = callback end
    function frame:SetSize() end
    return frame
end
UIParent = Frame(500, 500)
WorldFrame = Frame(500, 500)
local nav = Frame(600, 500)
WUIWaypointFrame = Frame()
WUIPinpointFrame = Frame()
WUIWaypointFrame:SetPoint("CENTER", nav)
WUIPinpointFrame:SetPoint("BOTTOM", nav, "TOP", 0, 75)
C_Navigation = {
    GetFrame = function() return nav end,
    GetDistance = function() return 1000 end,
}
CreateFrame = function() return Frame() end
local clock = 1
GetTime = function() return clock end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/WaypointStability.lua"))("VignetteRadar", addon)
local stability = addon.VignetteRadarWaypointStability
assert(stability.Enable())
WUIWaypointFrame.onUpdate(WUIWaypointFrame, .05)
local proxy = WUIWaypointFrame.relative
assert(proxy and proxy ~= nav and proxy.offsetX == 100
    and WUIPinpointFrame.relative == proxy,
    "our waypoint pylon and label should share a smoothed display anchor")
nav.x = 700
clock = 2
WUIWaypointFrame.onUpdate(WUIWaypointFrame, .05)
assert(proxy.offsetX == 200,
    "a fast move (a Skyriding surge) must be followed in the same frame, never trail")
nav.x = 700.8
clock = 3
local proxySetPoint, proxyMoves = proxy.SetPoint, 0
proxy.SetPoint = function(...) proxyMoves = proxyMoves + 1; return proxySetPoint(...) end
WUIWaypointFrame.onUpdate(WUIWaypointFrame, .05)
assert(proxy.offsetX == 200, "sub-pixel jitter must be held back")
assert(proxyMoves == 0, "an unchanged proxy position must not be re-anchored")
proxy.SetPoint = proxySetPoint
nav.x = 760
WUIPinpointFrame.onUpdate(WUIPinpointFrame, .05)
assert(proxy.offsetX == 200, "the second WaypointUI frame must not update twice in one frame")
stability.Disable()
assert(WUIWaypointFrame.relative == nav and WUIPinpointFrame.relative == nav,
    "clearing our waypoint should restore WaypointUI's own anchors")
addon.VignetteRadarBudget = { paused = { radar = true } }
assert(stability.Enable())
WUIWaypointFrame.onUpdate(WUIWaypointFrame, .05)
assert(not stability.IsEnabled() and WUIWaypointFrame.relative == nav,
    "the CPU guard should immediately release the optional waypoint smoother")
io.write("vignette radar waypoint stability tests passed\n")
