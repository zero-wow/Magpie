local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile(arg[1] or "Core/ContextDirector.lua"))("VignetteRadar", addon)
local D = addon.VignetteRadarContextDirector
local writes, current = 0, nil
local function apply(overlay) writes, current = writes + 1, overlay; return true end
local settings = { enabled = true, enterSeconds = 2, exitSeconds = 2,
    manualHoldSeconds = 5, contexts = {
        travel = { enabled = true, range = 600, preset = "Wide", filters = { rare = true } },
        cave = { enabled = true, range = 100, preset = "Close" } } }
local d = D.New(settings)
assert(d:Update({ travel = true }, 0, apply) == nil)
assert(d:Update({ travel = true }, 1, apply) == nil)
local overlay = d:Update({ travel = true }, 2, apply)
assert(overlay.context == "travel" and current.range == 600)
assert(settings.contexts.travel.range == 600, "base settings must be untouched")
assert(d:Update({ cave = true }, 2.1, apply).context == "travel")
assert(d:Update({ cave = true }, 4.2, apply).context == "cave")
d:ManualOverride(5)
assert(d:Update({ cave = true }, 5, apply) == nil and current == nil)
assert(d:Update({ cave = true }, 9, apply) == nil)
assert(d:Update({ cave = true }, 10, apply).context == "cave")
d:SetLocked(true)
assert(d:Update({ cave = true }, 11, apply) == nil)
d:SetLocked(false)
local _, status = d:Update({ cave = true }, 12, apply, true)
assert(status == "deferred" and current == nil)
local fail = function() return false end
_, status = d:Update({ cave = true }, 13, fail)
assert(status == "failed" and current == nil)
_, status = d:Update({ cave = true }, 14, apply)
assert(status == "applied" and current.context == "cave")
d:Configure({ enabled = true, contexts = { cave = { enabled = true, range = 80 } } })
_, status = d:Update({ cave = true }, 15, apply)
assert(status == "applied" and current.range == 80, "preset changes must reapply")
assert(writes < 10, "context changes must be sparse")
local revision = d.revision
d:Configure({ enabled = true, contexts = { cave = { enabled = true, range = 80 } } })
assert(d.revision == revision, "identical settings must not bump the revision")
_, status = d:Update({ cave = true }, 16, apply)
assert(status == "unchanged", "identical settings must not reapply")
d:Configure({ enabled = true, contexts = { cave = { enabled = true, range = 90,
    filters = { rare = true } } } })
assert(d.revision == revision + 1, "changed settings must bump the revision")
print("context_director_test: ok")
