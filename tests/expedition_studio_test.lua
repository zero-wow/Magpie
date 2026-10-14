local enginePath = arg[1] or "Routes/Expeditions.lua"
local studioPath = arg[2] or "UI/ExpeditionStudio.lua"

local objects = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetMovable(value) self.movable = value end
function methods:RegisterForDrag(value) self.drag = value end
function methods:SetScript(event, callback)
    self.scripts = self.scripts or {}
    self.scripts[event] = callback
end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:SetTextColor(...) self.color = { ... } end
function methods:SetFont(...) self.font = { ... } end
function methods:SetFontObject(...) end
function methods:SetWordWrap(...) end
function methods:SetJustifyH(...) end
function methods:SetHeight(value) self.height = value end
function methods:SetAutoFocus(...) end
function methods:SetMultiLine(...) end
function methods:SetTextInsets(...) end
function methods:SetMaxBytes(value) self.maxBytes = value end
function methods:SetBackdrop(...) end
function methods:SetBackdropColor(...) end
function methods:SetBackdropBorderColor(...) end
function methods:SetColorTexture(...) end
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:HighlightText() self.highlighted = true end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end
function methods:SetShown(value) self.shown = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown == true end
function methods:SetEnabled(value) self.enabled = value end
function methods:CreateTexture()
    return setmetatable({ parent = self, kind = "Texture" }, { __index = methods })
end
function methods:CreateFontString()
    return setmetatable({ parent = self, kind = "FontString" }, { __index = methods })
end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, shown = true },
        { __index = methods })
    objects[#objects + 1] = frame
    return frame
end
UIParent = CreateFrame("Frame")
UISpecialFrames = {}

local db = {}
local addon = {
    GetSettings = function() return db end,
    VignetteRadarControls = {
        Button = function(parent, title, width, height)
            local button = CreateFrame("Button", nil, parent)
            button:SetSize(width, height)
            button:SetText(title)
            return button
        end,
        PopupSurface = function(frame) frame.skinned = true end,
        RefreshPopupSurface = function() end,
        RoundedStatusSurface = function(frame) frame.rounded = true end,
        RefreshRoundedStatusSurface = function() end,
    },
}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile(enginePath))("VignetteRadar", addon)
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile(studioPath))("VignetteRadar", addon)
local studio = assert(addon.VignetteRadarExpeditionStudio)

studio.SetCandidates({
    { kind = "rare", id = 101, name = "Silvermaw", mapID = 1,
        mapX = .2, mapY = .3, worldX = 10, worldY = 0 },
    { kind = "treasure", id = 102, name = "Lost 50% Cache", mapID = 1,
        mapX = .3, mapY = .4, worldX = 25, worldY = 0 },
    { kind = "quest", questID = 103, name = "Stone Rubbings", mapID = 1,
        mapX = .4, mapY = .5, worldX = 40, worldY = 0 },
    { kind = "quest", questID = 104, name = "Bad", mapID = 1,
        mapX = 4, mapY = .2 },
})
studio.SetPlayer({ mapID = 1, worldX = 0, worldY = 0 })
assert(studio.Open() == true)
local panel
for _, object in ipairs(objects) do
    if object.name == "VignetteRadarExpeditionStudioPanel" then panel = object end
end
assert(panel and panel.skinned and panel.width == 570 and panel.height == 500)
assert(panel:IsShown() and UISpecialFrames[1] == panel.name)
for _, object in ipairs(objects) do
    if (object.kind == "Button" or object.kind == "EditBox" or object == panel.transfer)
        and object.parent and object.parent.width and object.point
        and object.point[1] == "TOPLEFT" then
        local x = object.point[4]
        assert(x >= 0 and x + object.width <= object.parent.width,
            "all revealed controls stay inside their parent width")
        local y = object.point[5]
        assert(y <= 0 and y - object.height >= -object.parent.height,
            "all revealed controls stay inside their parent height")
    end
end

assert(studio.AddCandidate("rare"))
assert(studio.AddCandidate("treasure"))
assert(studio.AddCandidate("quest"))
assert(not studio.AddCandidate("pin"), "only current rare, treasure, quest candidates are exposed")
local draft = assert(studio.GetDraft())
assert(#draft.goals == 3 and draft.goals[1].id == "rare:101"
    and draft.goals[3].id == "quest:103")
draft.goals[1].name = "Mutated"
assert(studio.GetDraft().goals[1].name == "Silvermaw", "readers receive a detached copy")
assert(not studio.AddGoal({ kind = "rare", id = 101, name = "Duplicate",
    mapID = 1, mapX = .2, mapY = .3 }))
assert(studio.Move("quest:103", -1))
assert(studio.GetDraft().goals[2].id == "quest:103")
assert(studio.Lock("quest:103"))
local now, nextStop = studio.Preview()
assert(now.id == "quest:103" and now.reason == "Locked stop"
    and nextStop, "preview should explain a locked current and next stop")
assert(studio.Skip("quest:103"))
assert(studio.GetDraft().goals[2].state == "skipped")
assert(studio.Pause(true))
local paused, _, reason = studio.Preview()
assert(paused == nil and reason == "Trip paused")
assert(studio.Pause(false))

local exported = assert(studio.Export())
assert(exported:find("VR%-EXPEDITION%-1") and exported:find("Silvermaw"))
assert(not studio.Import("return os.execute('anything')"))
assert(not studio.Import("VR-EXPEDITION-1\nquest\tbad%Q0\tname\t1\t.2\t.3\t\t\t\t\t"))
assert(not studio.Import("VR-EXPEDITION-1\nquest\tbad\tname\t1\t2\t.3\t\t\t\t\t"))
assert(not studio.Import("VR-EXPEDITION-1\nquest\tbad\tbad%0Aname\t1\t.2\t.3\t\t\t\t\t"))
assert(studio.Import(exported))
assert(#studio.GetDraft().goals == 3
    and studio.GetDraft().goals[2].state == "available",
    "imported routes are data-only fresh drafts, not progress restoration")
local estimateCalls = 0
studio.SetEstimateTravel(function(origin, goal)
    estimateCalls = estimateCalls + 1
    assert(origin.mapID == 1)
    return { costYards = goal.kind == "treasure" and 3 or 100,
        basis = "verified transition estimate", reason = "Verified cave entry" }
end)
local travelNow = studio.Preview()
assert(travelNow.id == "treasure:102" and travelNow.reason == "Verified cave entry"
    and estimateCalls <= 12, "verified travel estimates should rank the preview")
local imported = studio.GetDraft()
assert(imported.goals[2].name == "Stone Rubbings")
assert(imported.goals[3].name == "Lost 50% Cache",
    "percent escaping should round-trip ordinary route names")
assert(studio.Remove("quest:103"))
assert(#studio.GetDraft().goals == 2)

local applied
studio.SetOnApply(function(trip) applied = trip end)
assert(studio.Apply())
assert(db.vignetteRadarExpedition and applied == db.vignetteRadarExpedition)
assert(applied.currentID == "treasure:102",
    "Apply should preserve the travel-ranked preview as the stable current stop")
studio.Close()
assert(not studio.IsOpen() and studio.GetDraft() == nil)
local card
for _, object in ipairs(objects) do
    if object.name == "VignetteRadarExpeditionCard" then card = object end
end
assert(card and card.rounded and studio.IsCardVisible(),
    "an active expedition should show the compact Now/Next/Progress card")
for _, object in ipairs(objects) do
    if object.parent == card and object.kind == "Button" then
        local x, y = object.point[4], object.point[5]
        assert(x >= 8 and x + object.width <= card.width - 8
            and y <= -5 and y - object.height >= -card.height + 3,
            "compact card buttons need a visible border gutter")
    end
end
assert(card.now.text:find("Lost 50%% Cache") and card.next.text:find("Silvermaw")
    and card.progress.text == "0 Complete | 0 Skipped | 2 Total",
    "card should describe the applied current, next, and progress")
assert(card.scripts.OnUpdate == nil, "the compact card must be event-driven")
assert(studio.SkipCurrent())
assert(db.vignetteRadarExpedition.goals[2].state == "skipped"
    and db.vignetteRadarExpedition.currentID == "rare:101"
    and card.now.text:find("Silvermaw"),
    "Skip Current must be explicit and advance the saved route")
assert(studio.SetCardVisible(false) and not studio.IsCardVisible()
    and db.vignetteRadarExpeditionCardVisible == false)
assert(studio.SetCardVisible(true) and studio.IsCardVisible())
assert(studio.Open() and not studio.IsCardVisible(),
    "opening Studio should hide the compact card")
studio.Close()
assert(studio.IsCardVisible(), "closing Studio should restore the compact card")
assert(studio.Open() and #studio.GetDraft().goals == 2,
    "reopening loads the persisted expedition")
assert(studio.Remove("rare:101") and studio.Remove("treasure:102"))
assert(studio.Apply() and db.vignetteRadarExpedition == nil,
    "applying an empty draft clears the active trip")
studio.Close()
assert(not studio.IsCardVisible(), "clearing the trip should hide the compact card")

print("Expedition Studio tests passed")
