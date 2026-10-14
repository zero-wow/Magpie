-- luacheck: globals VignetteRadarDB WaffleHouseDB
-- Respawn Estimate: kills seen in view (vignette gone near the player, dead
-- flag, or Recent's kill) start a timer; the next appearance records the gap;
-- the median gap gives "Likely Up In ~N min". Leaving view is never a kill.
VignetteRadarDB, WaffleHouseDB = nil, nil
local epoch = 10000
_G.GetServerTime = function() return epoch end
_G.GetTime = function() return epoch end
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Guidance.lua"))("VignetteRadar", addon)
assert(loadfile("Data/RareSpawns.lua"))("VignetteRadar", addon)
local Spawns = assert(addon.VignetteRadarRareSpawns)
local settings = addon.GetSettings()
assert(settings.vignetteRadarRespawnEstimate == true, "default on")

local function Rare(serial, extra)
    local target = { category = "rare", name = "Big Rare", mapID = 2371, mapX = .1, mapY = .1,
        worldX = 1000, worldY = 1000, objectGUID = "Creature-0-1-2-3-4242-000000000" .. serial }
    for key, value in pairs(extra or {}) do target[key] = value end
    return target
end
local near = { worldX = 1100, worldY = 1000, mapID = 2371 }
local far = { worldX = 9000, worldY = 9000, mapID = 2371 }

-- Up, then gone while the player is far: no kill, no estimate.
Spawns.Observe({ Rare(1) }, near)
assert(Spawns.Respawn(4242) == nil, "nothing while up")
epoch = 10060
Spawns.Observe({}, far)
assert(Spawns.Respawn(4242) == nil and Spawns.RespawnText(4242) == nil, "left view is not a kill")

-- Seen again (same appearance after travel), then gone in view: a kill.
epoch = 10100
Spawns.Observe({ Rare(1) }, near)
epoch = 10200
Spawns.Observe({}, near)
local estimate = Spawns.Respawn(4242, 10500)
assert(estimate and estimate.killedAt == 10100 and estimate.since == 400 and not estimate.median, "kill recorded")
assert(Spawns.RespawnText(4242, 10500) == "Killed 7 min Ago", Spawns.RespawnText(4242, 10500))

-- It comes back 20 minutes after the kill: one gap.
epoch = 10100 + 1200
Spawns.Observe({ Rare(2) }, near)
assert(Spawns.Respawn(4242) == nil, "up again")
-- Dies (dead flag), then gone.
epoch = 11400
Spawns.Observe({ Rare(2, { isDead = true }) }, near)
epoch = 11410
Spawns.Observe({}, far)
estimate = Spawns.Respawn(4242, 11400 + 300)
assert(estimate.median == 1200 and estimate.left == 900 and estimate.samples == 1, "median gap")
assert(Spawns.RespawnText(4242, 11700) == "Likely Up In ~15 min")
assert(Spawns.RespawnText(4242, 11400 + 1190) == "Likely Up Now")
assert(Spawns.RespawnText(4242, 11400 + 3000) == "Window Passed")

-- The fact row.
local lines = {}
Spawns.RespawnFact(lines, { kind = "mob", npcID = 4242 })
assert(lines[1] and lines[1][1] == "Respawn", "fact row")
local facts = addon.VignetteRadarGuidance.FactLines({ kind = "mob", npcID = 4242, key = "n" })
local found
for _, fact in ipairs(facts) do if fact[1] == "Respawn" then found = fact[2] end end
assert(found, "Guidance facts carry the respawn row")
lines = {}
Spawns.RespawnFact(lines, { kind = "treasure", npcID = 4242 })
assert(#lines == 0, "rares only")
settings.vignetteRadarRespawnEstimate = false
assert(Spawns.RespawnText(4242) == nil, "switch off")
print("respawn_estimate_test ok")
