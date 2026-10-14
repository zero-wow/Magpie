local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Data/WarbandBoard.lua"))("VignetteRadar", addon)
assert(loadfile("Data/ResetPlanner.lua"))("VignetteRadar", addon)
assert(loadfile("Data/PhaseLens.lua"))("VignetteRadar", addon)

local board = addon.VignetteRadarWarbandBoard.New(nil, { staleAfter=60 })
assert(board:UpdateCharacter("Zero-Realm", { name="Zero", goals={
    ["rare:7"]={ eligibility="available", completion=false, evidence="api" },
    ["quest:4"]={ eligibility="available", completion=false },
} }, 100))
assert(board:UpdateCharacter("Alt-Realm", { name="Alt", goals={
    ["rare:7"]={ eligibility="available", completion=true, evidence="api" },
} }, 95))
assert(board:SetFavorite("Alt-Realm", true))
local rows = board:GetBoard("rare:7", 110, "Zero-Realm")
assert(#rows == 2 and rows[1].favorite and rows[1].offline
    and rows[1].completion == true)
assert(board:Suggest("rare:7", 110, "Zero-Realm").character == "Zero-Realm",
    "completed favorite cannot be suggested")
local unknown = board:GetBoard("quest:4", 110, "Zero-Realm")
assert(unknown[2].eligibility == "unknown", "bare availability has no evidence")
assert(board:SetCollection("mount:20", true, "api", 110))
assert(board:GetCollection("mount:20").status == "collected")
assert(board:GetCollection("mount:21").status == "unknown")
local restored = addon.VignetteRadarWarbandBoard.New(board:Export(), { staleAfter=60 })
assert(restored:GetBoard("rare:7", 170, "Other")[2].eligibility == "unknown",
    "old offline eligibility becomes unknown")
assert(restored:GetCollection("mount:20").status == "collected")
assert(not board:UpdateCharacter("Zero-Realm", {}, 99), "old snapshot cannot replace a newer one")

local planner = addon.VignetteRadarResetPlanner.New()
assert(planner:SetGoal("daily:1", { name="Daily Cache", resetKind="daily", source="api" }))
assert(planner:Observe("daily:1", "completed", {
    daily="D1", sessionID="S1", verifiedReset=true }, 100))
assert(planner:Evaluate("daily:1", { daily="D1", verifiedReset=true }).status == "Completed")
local reopened = planner:Evaluate("daily:1", { daily="D2", verifiedReset=true })
assert(reopened.status == "Expected" and reopened.queue,
    "new period does not confirm availability")
assert(planner:Evaluate("daily:1", {}).status == "Unknown")
assert(planner:Observe("daily:1", "available", {
    daily="D2", sessionID="S2", verifiedReset=true }, 200))
assert(planner:Evaluate("daily:1", { daily="D2", verifiedReset=true }).status == "Confirmed")
assert(planner:SetGoal("once:1", { resetKind="one-time", source="trusted-pack" }))
assert(planner:Observe("once:1", "available", { sessionID="S2" }, 200))
assert(planner:Evaluate("once:1", { sessionID="S2" }).status == "Confirmed")
assert(planner:Evaluate("once:1", { sessionID="S3" }).status == "Unknown")
assert(planner:Observe("once:1", "completed", { sessionID="S2" }, 201))
assert(planner:Evaluate("once:1", { sessionID="S2" }).status == "Completed")
assert(planner:SetGoal("guess:1", { resetKind="weekly", source="guess" }))
assert(planner:Evaluate("guess:1", { weekly="W2" }).status == "Unknown")
assert(#planner:GetQueue({ daily="D2", sessionID="S2", verifiedReset=true }) == 1)
local reloadedPlanner = addon.VignetteRadarResetPlanner.New(planner:Export())
assert(reloadedPlanner:Evaluate("daily:1", { daily="D2", verifiedReset=true }).status == "Confirmed")
assert(reloadedPlanner:Evaluate("daily:1", { daily="D3" }).status == "Unknown",
    "a guessed calendar day is not a verified reset")

local phase = addon.VignetteRadarPhaseLens.New({ action="hide", heuristic=true })
local pin = { key="pack:1", phaseEvidence="trusted-pack",
    phaseConditions={ { questID=42, complete=true } } }
local mismatch = phase:Evaluate(pin, { questComplete=function() return false end })
assert(mismatch.status == "condition-mismatch" and mismatch.action == "hide")
local match = phase:Evaluate(pin, { questComplete=function() return true end })
assert(match.status == "condition-match" and match.action == "show")
assert(phase:Evaluate(pin, {}).status == "unknown")
assert(phase:Evaluate({ key="pack:1", evidence="live", phaseConditions=pin.phaseConditions },
    { questComplete=function() return false end }).action == "show",
    "local live detection always wins")
assert(phase:SetOverride("pack:1", "show"))
assert(phase:Evaluate(pin, { questComplete=function() return false end }).status == "override")
assert(phase:SetOverride("pack:1", nil))
assert(phase:RecordSighting("pack:2", { at=100, evidence="live",
    questStates={ [42]=false } }))
assert(phase:Evaluate({ key="pack:2" }, { absent=true,
    questStates={ [42]=true } }).status == "possible-mismatch")
assert(phase:Evaluate({ key="pack:2" }, { absent=true,
    questStates={ [42]=false } }).status == "unknown")
assert(phase:Evaluate({ key="pack:2" }, { absent=true }).status == "unknown",
    "absence alone is never phase proof")
print("Personal intelligence tests passed")
