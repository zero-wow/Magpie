-- Live ETA: travel mode (ground, flying, skyriding), smoothed speed per
-- mode, standing-still memory, format, and the on/off switch.
local settings = { vignetteRadarLiveEta = true }
local addon = { GetSettings = function() return settings end }
local clock = 0
_G.GetTime = function() return clock end
local unit = { 0, 7, 20 }
local glide = { false, false, 0 }
local flying, mounted, flyable, advanced = false, false, false, false
_G.GetUnitSpeed = function() return unit[1], unit[2], unit[3], 4.5 end
_G.C_PlayerInfo = { GetGlidingInfo = function() return glide[1], glide[2], glide[3] end }
_G.IsFlying = function() return flying end
_G.IsMounted = function() return mounted end
_G.IsFlyableArea = function() return flyable end
_G.IsAdvancedFlyableArea = function() return advanced end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Travel.lua"))("VignetteRadar", addon)
local Travel = assert(addon.VignetteRadarTravel)

-- Standing on foot: run speed.
assert(Travel.Mode() == "ground" and Travel.Speed() == 7 and Travel.Eta(140) == 20)
assert(Travel.Format(20) == "~20 s" and Travel.Format(61) == "~2 min" and Travel.Format(nil) == nil)
assert(Travel.EtaText(140) == "~20 s")
-- Mounted in a flyable zone, not moving: flight speed.
mounted, flyable = true, true
assert(Travel.Mode() == "flying" and Travel.Speed() == 20, "would fly: flight speed")
-- Skyriding: the gliding forward speed, smoothed.
advanced, glide = true, { false, true, 0 }
assert(Travel.Mode() == "skyriding", "mounted where skyriding works")
glide = { true, true, 60 }
clock = 1
assert(Travel.Speed() == 60, "first sample")
glide[3] = 40
clock = 2
assert(math.abs(Travel.Speed() - 54) < 1e-9, "smoothed toward the new speed")
-- Stopped: the mode's last smoothed speed is remembered for 30 s.
glide = { false, true, 0 }
clock = 20
assert(math.abs(Travel.Speed() - 54) < 1e-9, "remembered while standing")
clock = 40
assert(Travel.Speed() == 20, "then the base speed of the mode")
-- Switch off: no text.
settings.vignetteRadarLiveEta = false
assert(Travel.EtaText(100) == nil)
assert(Travel.Eta(-1) == nil)
print("travel_test ok")
