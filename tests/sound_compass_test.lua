local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile(arg[1] or "Routes/SoundCompass.lua"))("VignetteRadar", addon)
local S = addon.VignetteRadarSoundCompass
local c, emitted = S.New({ enabled = true, mode = "tone", cooldown = 5 }), {}
local function emit(cue) emitted[#emitted + 1] = cue; return true end
local dest = { id = "rare:1", name = "Silvermaw", relativeDegrees = -90, distance = 100 }
local textState, cue = c:Update(dest, 0, emit)
assert(textState.direction == "left" and cue.kind == "left" and #emitted == 1)
dest.relativeDegrees = -23
textState, cue = c:Update(dest, 1, emit)
assert(textState.direction == "left" and cue == nil, "hysteresis must hold a bucket")
dest.relativeDegrees = -10
textState, cue = c:Update(dest, 2, emit)
assert(textState.direction == "ahead" and cue == nil, "cooldown must suppress rapid cues")
dest.distance = 35
textState, cue = c:Update(dest, 5, emit)
assert(cue.kind == "near" and #emitted == 2)
for t = 6, 50 do
    local _, repeated = c:Update(dest, t, emit)
    assert(repeated == nil, "approach cue must not loop")
end
c:Mute()
dest.relativeDegrees = 90
textState, cue = c:Update(dest, 60, emit)
assert(textState.direction == "right" and cue == nil and #emitted == 2,
    "mute must take effect immediately while retaining text")
c:Configure({ enabled = true, mode = "speech", quietCombat = true })
dest.inCombat = true
assert(select(2, c:Update(dest, 70, emit)) == nil)
dest.inCombat = false
dest.relativeDegrees = 180
textState, cue = c:Update(dest, 80, function() return false end)
assert(textState.direction == "behind" and cue.mode == "text" and cue.unavailable,
    "failed speech must degrade to text")
c:Configure({ enabled = true, mode = "tone", quietCombat = false, quietInstance = false })
assert(c.settings.quietCombat == false and c.settings.quietInstance == false,
    "explicit false quiet settings must survive Field")
dest.inCombat, dest.inInstance = true, true
dest.relativeDegrees = -90
textState, cue = c:Update(dest, 200, emit)
assert(textState.direction == "left" and cue and cue.kind == "left",
    "quietCombat=false must still cue in combat")
print("sound_compass_test: ok")
