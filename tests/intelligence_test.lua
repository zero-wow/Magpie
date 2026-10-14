local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Data/WarbandBoard.lua"))("VignetteRadar", addon)
assert(loadfile("Data/ResetPlanner.lua"))("VignetteRadar", addon)
assert(loadfile("Data/PhaseLens.lua"))("VignetteRadar", addon)

local db = {}
addon.GetSettings = function() return db end
local methods = {}
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetAllPoints() end
function methods:SetFrameStrata() end
function methods:SetClampedToScreen() end
function methods:EnableMouse() end
function methods:SetMovable() end
function methods:RegisterForDrag() end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end
function methods:SetScript(event, script)
    self.scripts = self.scripts or {}
    self.scripts[event] = script
end
function methods:CreateTexture() return setmetatable({}, { __index = methods }) end
function methods:CreateFontString() return setmetatable({}, { __index = methods }) end
function methods:SetFont() end
function methods:SetJustifyH() end
function methods:SetWordWrap() end
function methods:SetText(value) self.text = value end
function methods:SetTextColor() end
function methods:SetTexture() end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetVertexColor() end
function methods:LockHighlight() self.selected = true end
function methods:UnlockHighlight() self.selected = false end
function methods:SetEnabled(value) self.enabled = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, parent = parent }, { __index = methods })
    if name then _G[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame")
UISpecialFrames = {}
addon.VignetteRadarControls = {
    Button = function(parent, title, width, height)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(width, height)
        button:SetText(title)
        return button
    end,
    PopupSurface = function(frame) frame.popupFace = true end,
    RefreshPopupSurface = function() end,
}
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Intelligence.lua"))("VignetteRadar", addon)
local ui = addon.VignetteRadarIntelligence
assert(ui and not ui.IsOpen())

local board = addon.VignetteRadarWarbandBoard.New(nil, { staleAfter = 60 })
assert(board:UpdateCharacter("Zero-Realm", { name = "Zero", goals = {
    ["rare:1"] = { eligibility = "available", evidence = "api", completion = false },
} }, 100))
assert(board:UpdateCharacter("Alt-Realm", { name = "Alt", goals = {
    ["rare:1"] = { eligibility = "available", evidence = "api", completion = false },
} }, 100))
local planner = addon.VignetteRadarResetPlanner.New()
assert(planner:SetGoal("daily:1", { name = "Daily Cache", resetKind = "daily", source = "api" }))
assert(planner:Observe("daily:1", "completed", {
    verifiedReset = true, daily = "D1", sessionID = "S1" }, 100))
local phase = addon.VignetteRadarPhaseLens.New({ action = "show" })
local savedPlanner, saveCalls
saveCalls = 0
local uiContext = {
    board = board, resetPlanner = planner, phaseLens = phase,
    getNow = function() return 200 end,
    getCurrentCharacter = function() return "Zero-Realm" end,
    getResetPeriods = function() return { verifiedReset = true, daily = "D2" } end,
    onIntelligenceChange = function(kind, changed)
        assert(kind == "resetPlanner" and changed == planner)
        saveCalls = saveCalls + 1
        savedPlanner = changed:Export()
        return true
    end,
}
ui.SetContext(uiContext)
ui.SetSelection({ goalKey = "rare:1", sourceKey = "rare:1",
    point = { key = "pack:1" } })

local warband = ui.GetView("Warband")
assert(warband.rows[1].detail:find("Unknown"),
    "stale snapshots must not say available")
assert(warband.rows[1].detail:find("Stale Snapshot"))
assert(warband.rows[1].detail:find("Saved Unknown"),
    "offline evidence must be labeled as a saved snapshot")
local reset = ui.GetView("Resets")
assert(reset.rows[1].detail:find("Unknown"),
    "selected goal must show its unknown reset status")
assert(reset.rows[2].detail:find("Expected"))
assert(reset.footer:find("never confirms"), "reset boundary must not prove availability")
local phaseView = ui.GetView("Phase")
assert(phaseView.summary == "Phase: Unknown" and phaseView.rows[1].detail:find("Phase not exposed"))
assert(ui.Open("Phase"))
local frame = VignetteRadarIntelligencePanel
assert(frame.width == 510 and frame.height == 388)
assert(frame.rows[6].point[5] == -313 and -313 - 32 > -356,
    "last row must leave a visible gutter before the footer")
assert(frame.resetActions.remove.point[4] + frame.resetActions.remove.width < 510 - 17
    and -315 - 28 > -356, "reset actions must stay inside the panel gutter")
assert(frame.tabs.Phase.selected)
assert(frame.tabs.Collections == nil and frame.tabs["Quest Chains"] == nil,
    "data-less Collections and Quest Chains tabs are gone")
assert(ui.SetEnabled("Phase", false))
assert(ui.GetView("Phase").summary == "Phase Is Disabled")
assert(db.vignetteRadarPhaseLensEnabled == false)
frame.enable.scripts.OnClick(frame.enable)
assert(db.vignetteRadarPhaseLensEnabled == true)
assert(ui.Open("Resets"))
assert(frame.resetActions.daily.enabled and not frame.resetActions.remove.enabled)
frame.resetActions.daily.scripts.OnClick(frame.resetActions.daily)
assert(planner.goals["rare:1"].resetKind == "daily"
    and planner.goals["rare:1"].source == "user-rule")
assert(frame.resetActions.daily.selected and not frame.resetActions.weekly.selected,
    "the selected reset rule should be visibly marked")
assert(planner:Evaluate("rare:1", { verifiedReset = true, daily = "D2" }).status == "Unknown",
    "assigning a daily rule must not confirm availability")
assert(savedPlanner.goals["rare:1"].resetKind == "daily" and saveCalls == 1)
frame.resetActions.weekly.scripts.OnClick(frame.resetActions.weekly)
assert(planner.goals["rare:1"].resetKind == "weekly" and saveCalls == 2)
uiContext.onIntelligenceChange = function() return false end
assert(not ui.SetResetRule("one-time"))
assert(planner.goals["rare:1"].resetKind == "weekly",
    "failed persistence must restore the previous rule")
assert(not ui.SetResetRule("remove") and planner.goals["rare:1"],
    "failed removal must restore the rule")
uiContext.onIntelligenceChange = function() saveCalls = saveCalls + 1; return true end
frame.resetActions["one-time"].scripts.OnClick(frame.resetActions["one-time"])
assert(planner.goals["rare:1"].resetKind == "one-time")
frame.resetActions.remove.scripts.OnClick(frame.resetActions.remove)
assert(not planner.goals["rare:1"] and saveCalls == 4)
assert(not ui.SetResetRule("remove"), "remove requires a saved rule")
ui.SetSelection({ goalKey = "daily:1", goalName = "Daily Cache" })
assert(planner:Evaluate("daily:1", { verifiedReset = true, daily = "D2" }).status == "Expected")
assert(ui.SetResetRule("one-time"))
assert(planner:Evaluate("daily:1", { verifiedReset = true, daily = "D2" }).status == "Unknown",
    "changing reset type must discard evidence from the old period")
assert(ui.Toggle() == false and not ui.IsOpen())
assert(ui.Open("Phase") and ui.IsOpen())
frame.option.scripts.OnClick(frame.option)
assert(db.vignetteRadarPhaseLensAction == "show", "first cycle starts at Show")
frame.option.scripts.OnClick(frame.option)
assert(db.vignetteRadarPhaseLensAction == "dim")
frame.extra.scripts.OnClick(frame.extra)
assert(db.vignetteRadarPhaseHeuristics == true)
ui.Close()
assert(not ui.IsOpen())
ui.SetContext({})
ui.SetSelection({})
for _, tab in ipairs({ "Warband", "Resets", "Phase" }) do
    local empty = ui.GetView(tab)
    assert(#empty.rows >= 1 and empty.rows[1].detail,
        "missing data must have a readable empty state for " .. tab)
end
do
    -- Today: the everyday tab; the evidence tabs need Advanced Tools.
    local today = ui.GetView("Today")
    assert(today.tab == "Today" and today.summary == "Today: Zone Unknown" and today.rows[1].detail,
        "Today has a readable empty state without a zone")
    assert(ui.Open() and frame.enable.text == "Sweep Zone" and frame.title.text == "Today"
        and not frame.tabs.Today.shown and not frame.tabs.Phase.shown,
        "without Advanced Tools the panel opens on Today alone")
    db.vignetteRadarAdvancedTools = true
    ui.Refresh()
    assert(frame.tabs.Today.shown and frame.tabs.Phase.shown, "Advanced Tools shows every tab")
    frame.option.scripts.OnClick(frame.option)
    assert(db.vignetteRadarTodayFilter == "done", "the option button cycles the Today filter")
    ui.Close()
end
print("Intelligence panel tests passed")
