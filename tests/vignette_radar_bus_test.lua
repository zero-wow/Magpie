local frame = { events = {}, scripts = {}, registrations = 0 }
function frame:RegisterEvent(event) self.events[event] = true; self.registrations = self.registrations + 1 end
function frame:SetScript(name, callback) self.scripts[name] = callback end
CreateFrame = function() return frame end
InCombatLockdown = function() return true end

local timers = {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end }

local settings = { vignetteRadarPerformance = "standard" }
local addon = { GetSettings = function() return settings end }
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
local Bus = assert(addon.Bus, "the bus must be exposed as addon.Bus")

local function Fire(event, ...) frame.scripts.OnEvent(frame, event, ...) end

-- The combat flag is seeded for a reload in combat, then follows PLAYER_REGEN_*.
assert(Bus.InCombat(), "a reload inside combat must start with the combat flag set")
InCombatLockdown = function() return false end
Fire("PLAYER_REGEN_ENABLED")
assert(not Bus.InCombat(), "PLAYER_REGEN_ENABLED must clear the combat flag")
InCombatLockdown = function() return false end
Fire("PLAYER_REGEN_DISABLED")
assert(Bus.InCombat(), "PLAYER_REGEN_DISABLED must set the flag even while InCombatLockdown lags")
Fire("PLAYER_REGEN_ENABLED")

-- Topics register every member event once and pass the raw event through.
local seen = {}
local function Record(event, ...) seen[#seen + 1] = { event = event, n = select("#", ...), ... } end
Bus.On("QUEST_CHANGED", Record)
assert(frame.events.QUEST_LOG_UPDATE and frame.events.QUEST_TURNED_IN
    and frame.events.TASK_PROGRESS_UPDATE, "a topic must register all of its WoW events")
local registrations = frame.registrations
Bus.On("QUEST_LOG_UPDATE", function() end)
assert(frame.registrations == registrations, "an event already registered must not be registered again")
Fire("QUEST_ACCEPTED", 77)
assert(#seen == 1 and seen[1].event == "QUEST_ACCEPTED" and seen[1][1] == 77,
    "topic handlers receive the raw event and its arguments")
Bus.Emit("QUEST_CHANGED", "manual")
assert(#seen == 2 and seen[2].event == "QUEST_CHANGED" and seen[2][1] == "manual",
    "Emit must reach the topic's handlers")
Bus.Off("QUEST_CHANGED", Record)
Fire("QUEST_REMOVED")
Bus.Emit("QUEST_CHANGED")
assert(#seen == 2, "Off must remove a handler from the topic and from its events")

-- Handlers run in subscription order, and one failing handler does not stop the rest.
local order = {}
Bus.On("MAP_CHANGED", function() order[#order + 1] = "data" end)
Bus.On("ZONE_CHANGED", function() order[#order + 1] = "raw" end)
Bus.On("MAP_CHANGED", function() order[#order + 1] = "radar" end)
Fire("ZONE_CHANGED")
assert(table.concat(order, ",") == "data,raw,radar", "dispatch must follow subscription order")
local reported
geterrorhandler = function() return function(err) reported = err end end
order = {}
Bus.On("LOOT", function() error("boom", 0) end)
Bus.On("LOOT", function() order[#order + 1] = "after" end)
Fire("LOOT_OPENED")
assert(reported == "boom" and order[1] == "after", "an error must be reported without stopping later handlers")
geterrorhandler = nil

-- A handler that removes itself during dispatch must not disturb the others.
local calls = 0
local function Once() calls = calls + 1; Bus.Off("VIGNETTES", Once) end
local after = 0
Bus.On("VIGNETTES", Once)
Bus.On("VIGNETTES", function() after = after + 1 end)
Fire("VIGNETTES_UPDATED")
Fire("VIGNETTE_MINIMAP_UPDATED")
assert(calls == 1 and after == 2, "self-removal must be safe during dispatch")

-- Coalesced handlers run once for a burst, with the last event's arguments.
local coalesced = {}
local function Burst(event, value) coalesced[#coalesced + 1] = { event = event, value = value } end
Bus.On("QUEST_CHANGED", Burst, { coalesce = true })
Bus.On("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", Burst, { coalesce = true })
timers = {}
Fire("QUEST_LOG_UPDATE", 1)
Fire("QUEST_POI_UPDATE", 2)
Fire("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", 3)
assert(#timers == 1 and timers[1].delay == 0 and #coalesced == 0,
    "a burst across topics must schedule the shared handler once on the next frame")
timers[1].callback()
assert(#coalesced == 1 and coalesced[1].event == "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED"
    and coalesced[1].value == 3, "the coalesced run must see the latest event")
Fire("QUEST_LOG_UPDATE", 4)
assert(#timers == 2, "a later event must schedule a fresh run")
timers[2].callback()
assert(#coalesced == 2 and coalesced[2].value == 4)

local delayed = 0
Bus.On("TRACKING", function() delayed = delayed + 1 end, { coalesce = .12 })
Fire("MINIMAP_UPDATE_TRACKING")
Fire("MINIMAP_UPDATE_TRACKING")
assert(#timers == 3 and timers[3].delay == .12 and delayed == 0, "a numeric coalesce is a fixed delay")
timers[3].callback()
assert(delayed == 1)
local savedTimer = C_Timer
C_Timer = nil
Fire("MINIMAP_UPDATE_TRACKING")
assert(delayed == 2, "without C_Timer a coalesced handler runs at once")
C_Timer = savedTimer

-- Tickers scale with the Update Rate setting and share one OnUpdate.
local ticks = {}
assert(Bus.Every("scan", 1, function(name) ticks[#ticks + 1] = name end))
assert(Bus.Every("walk", 2, function(name) ticks[#ticks + 1] = name end, { scale = false }))
assert(frame.scripts.OnUpdate, "tickers must run from the bus frame")
frame.scripts.OnUpdate(frame, .99)
assert(#ticks == 0)
frame.scripts.OnUpdate(frame, .02)
assert(#ticks == 1 and ticks[1] == "scan", "a standard ticker fires after its interval")
settings.vignetteRadarPerformance = "low"
assert(Bus.Scale() == 2.5)
frame.scripts.OnUpdate(frame, 1)
assert(#ticks == 2 and ticks[2] == "walk", "an unscaled ticker keeps its interval")
frame.scripts.OnUpdate(frame, 1.4)
assert(#ticks == 2, "low update rate must stretch a scaled ticker")
frame.scripts.OnUpdate(frame, .2)
assert(#ticks == 3 and ticks[3] == "scan")
settings.vignetteRadarPerformance = "balanced"
assert(Bus.Scale() == 1.5)
addon.VignetteRadarBudget = { softThrottle = true }
assert(Bus.Scale() == 2.5, "the CPU guard's soft throttle must slow tickers")
addon.VignetteRadarBudget = nil
Bus.Cancel("scan")
assert(not Bus.IsTicking("scan") and Bus.IsTicking("walk") and frame.scripts.OnUpdate)
Bus.Cancel("walk")
assert(frame.scripts.OnUpdate == nil, "the bus must drop its OnUpdate when no ticker is left")

io.write("vignette radar bus tests passed\n")
