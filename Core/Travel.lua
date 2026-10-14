local _, addon = ...
if type(addon) ~= "table" then return end

-- Live ETA: one travel-mode and speed reader for every view (Worth-It Card,
-- Next 3 Stops Strip, Auto Route costs). Skyriding speed comes from
-- C_PlayerInfo.GetGlidingInfo (GetUnitSpeed does not report it); other modes
-- from GetUnitSpeed. While moving, speed is smoothed per mode; standing
-- still, the last smoothed speed of the mode you would travel in is reused
-- for 30 s, then the mode's base speed (flight or run speed).
--   Travel.Mode() -> "skyriding" | "flying" | "ground"
--   Travel.Speed([now]) -> yards per second | nil
--   Travel.Eta(yards [, now]) -> seconds | nil
--   Travel.Format(seconds) -> "~45 s" | "~3 min" | nil
local Travel = {}
addon.VignetteRadarTravel = Travel

local type, ceil, pcall = type, math.ceil, pcall
local Number, Call = addon.Secret.Number, addon.Secret.Call

local SMOOTHING, MEMORY_SECONDS = .3, 30
local smoothed, smoothedAt = {}, {}  -- mode -> yards/s, GetTime

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, value = pcall(GetTime)
    return ok and Number(value) or 0
end

local function Gliding()
    local isGliding, canGlide, forward = Call(C_PlayerInfo, "GetGlidingInfo")
    return isGliding == true, canGlide == true, Number(forward)
end

-- The mode you are in now, or the one you would travel in from a standstill.
function Travel.Mode()
    local gliding, canGlide = Gliding()
    if gliding then return "skyriding" end
    if Call(_G, "IsFlying", "player") == true then return "flying" end
    if Call(_G, "IsMounted") == true then
        if canGlide and Call(_G, "IsAdvancedFlyableArea") == true then return "skyriding" end
        if Call(_G, "IsFlyableArea") == true then return "flying" end
    end
    return "ground"
end

function Travel.Speed(now)
    now = Number(now) or Now()
    local mode = Travel.Mode()
    local gliding, _, forward = Gliding()
    local current, run, flight = Call(_G, "GetUnitSpeed", "player")
    current, run, flight = Number(current), Number(run), Number(flight)
    local moving = gliding and forward or current
    if moving and moving > 0 then
        local old = smoothed[mode]
        if old and now - (smoothedAt[mode] or 0) <= MEMORY_SECONDS then
            moving = old + (moving - old) * SMOOTHING
        end
        smoothed[mode], smoothedAt[mode] = moving, now
        return moving
    end
    if smoothed[mode] and now - (smoothedAt[mode] or 0) <= MEMORY_SECONDS then return smoothed[mode] end
    if mode ~= "ground" and flight and flight > 0 then return flight end
    if run and run > 0 then return run end
    return nil
end

function Travel.Eta(yards, now)
    yards = Number(yards)
    if not yards or yards < 0 then return nil end
    local speed = Travel.Speed(now)
    if not speed or speed <= 0 then return nil end
    return yards / speed
end

function Travel.Format(seconds)
    seconds = Number(seconds)
    if not seconds then return nil end
    seconds = ceil(seconds)
    if seconds < 60 then return "~" .. seconds .. " s" end
    return "~" .. ceil(seconds / 60) .. " min"
end

-- Shown ETA text for a distance, honouring the Live ETA switch.
function Travel.EtaText(yards, now)
    if addon.GetSettings().vignetteRadarLiveEta == false then return nil end
    return Travel.Format(Travel.Eta(yards, now))
end

return Travel
