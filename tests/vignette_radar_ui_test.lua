local sourcePath = arg[1] or "UI/Radar.lua"
local legendSourcePath = arg[2] or "UI/Legend.lua"
local targetPickerSourcePath = arg[3] or "UI/TargetPicker.lua"
local optionsSourcePath = arg[4] or "UI/Options.lua"
local quickSourcePath = arg[5] or "UI/QuickConfig.lua"
unpack = table.unpack or unpack

local objects = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:GetRight()
    if self.right then return self.right end
    return (self:GetLeft() or 0) + self:GetWidth()
end
function methods:SetPoint(...) self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end
function methods:ClearAllPoints() self.point, self.points = nil, {} end
function methods:SetAllPoints(...) self.allPoints = { ... } end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function methods:SetFrameStrata(value) self.strata = value end
function methods:GetFrameStrata() return self.strata or "MEDIUM" end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:SetClipsChildren(value) self.clipsChildren = value end
function methods:SetScrollChild(value) self.scrollChild = value end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetMapID(value) self.mapID = value end
function methods:SetFillTexture(value) self.fillTexture = value end
function methods:SetBorderTexture(value) self.borderTexture = value end
function methods:SetFillAlpha(value) self.fillAlpha = value end
function methods:SetBorderAlpha(value) self.borderAlpha = value end
function methods:DrawNone() self.drawnQuests = {} end
function methods:DrawBlob(questID) self.drawnQuests = self.drawnQuests or {}; self.drawnQuests[#self.drawnQuests + 1] = questID end
function methods:UpdateMouseOverTooltip(x, y)
    self.hoverPosition = { x, y }
    if self.hoverQuestID and x >= .25 and x <= .75 and y >= .25 and y <= .75 then
        return self.hoverQuestID, 1
    end
end
function methods:SetMovable(value) self.movable = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:EnableMouseWheel(value) self.mouseWheel = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:RegisterForClicks(...) self.clickButtons = { ... } end
function methods:RegisterForDrag(...) self.dragButtons = { ... } end
function methods:RegisterEvent(event)
    assert(event ~= "COMBAT_LOG_EVENT_UNFILTERED",
        "Midnight forbids addons from registering combat-log events")
    self.events = self.events or {}
    self.events[event] = true
    self.eventRegistrationCalls = (self.eventRegistrationCalls or 0) + 1
end
function methods:UnregisterEvent(event)
    self.eventUnregistrationCalls = (self.eventUnregistrationCalls or 0) + 1
    self.events[event] = nil
end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:HookScript(name, callback)
    local previous = self.scripts and self.scripts[name]
    self:SetScript(name, function(...)
        if previous then previous(...) end
        callback(...)
    end)
end
function methods:GetScript(name) return self.scripts and self.scripts[name] end
function methods:IsMouseOver() return self.hovered == true end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:LockHighlight() self.highlightLocked = true end
function methods:UnlockHighlight() self.highlightLocked = false end
function methods:SetHighlightTexture(texture) self.highlight = setmetatable({ texture = texture }, { __index = methods }) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetTexture(value) self.texture = value end
function methods:SetRotation(value) self.rotation = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetAtlas(value) self.atlas = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha == nil and 1 or self.alpha end
function methods:SetIgnoreParentAlpha(value) self.ignoreParentAlpha = value end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale()
    local parentScale = self.parent and self.parent.GetEffectiveScale
        and self.parent:GetEffectiveScale() or 1
    return parentScale * self:GetScale()
end
function methods:SetThickness(value) self.thickness = value end
function methods:SetStartPoint(...)
    assert(select("#", ...) == 4, "line endpoints take anchor, frame, x, y")
    self.startPoint = { ... }
    assert(type(self.startPoint[3]) == "number" and type(self.startPoint[3]) == "number")
end
function methods:SetEndPoint(...)
    assert(select("#", ...) == 4, "line endpoints take anchor, frame, x, y")
    self.endPoint = { ... }
    assert(type(self.endPoint[3]) == "number" and type(self.endPoint[3]) == "number")
end
function methods:SetFont(...) self.font = { ... } end
function methods:SetFontObject(value) self.fontObject = value end
function methods:SetTextInsets(...) self.textInsets = { ... } end
function methods:SetAutoFocus(value) self.autoFocus = value end
function methods:SetMaxLetters(value) self.maxLetters = value end
function methods:GetText() return self.text end
function methods:ClearFocus() self.focused = false end
function methods:SetFontString(value) self.fontString = value end
function methods:SetText(value) self.text = value; if self.fontString then self.fontString:SetText(value) end end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetJustifyV(value) self.justifyV = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:IsShown() return self.shown == true end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:GetLeft()
    if self.left then return self.left end
    if self.name == "VignetteRadarPanel" and self.point then return self.point[4] end
    return 30
end
function methods:GetTop()
    if self.top then return self.top end
    if self.name == "VignetteRadarPanel" and self.point then
        return UIParent:GetHeight() / self:GetScale() + self.point[5]
    end
    return 380
end
function methods:GetBottom() return self.bottom or (self:GetTop() - self:GetHeight()) end
function methods:CreateTexture(_, layer)
    local texture = setmetatable({ kind = "Texture", parent = self, layer = layer }, { __index = methods })
    objects[#objects + 1] = texture
    return texture
end
function methods:CreateFontString()
    local label = setmetatable({ kind = "FontString", parent = self }, { __index = methods })
    objects[#objects + 1] = label
    return label
end
function methods:CreateLine(_, layer)
    local line = setmetatable({ kind = "Line", parent = self, layer = layer }, { __index = methods })
    objects[#objects + 1] = line
    return line
end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, shown = false, enabled = true }, { __index = methods })
    objects[#objects + 1] = frame
    if name then _G[name] = frame end
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1600, 900)
UIParent:Show()
UISpecialFrames = {}
STANDARD_TEXT_FONT = "default.ttf"
SlashCmdList = {}
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    GetOwner = function(self) return self.owner end,
    SetText = function(self, value) self.text = value; self.lines = {} end,
    AddLine = function(self, value)
        self.line = value
        self.lines = self.lines or {}
        self.lines[#self.lines + 1] = value
    end,
    ClearLines = function(self) self.lines = {} end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown == true end,
}
C_Timer = { After = function(_, callback) callback() end }
C_Map = {
    GetBestMapForUnit = function() return 777 end,
    GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
    GetWorldPosFromMapPos = function(_, position) return 42, { x = position.x * 1000, y = position.y * 1000 } end,
}
C_VignetteInfo = {
    GetVignettes = function() return {} end,
    GetVignetteInfo = function() end,
    GetVignettePosition = function() end,
    GetRecommendedGroupSize = function(key)
        if key == "rare" then return 3, 5 end
    end,
}
-- The client's atlases: Blizzard's vignette and quest icons exist, anything else is missing.
local knownAtlases = { VignetteLoot = true, VignetteLootElite = true, VignetteKill = true,
    VignetteKillElite = true, VignetteEvent = true, VignetteEventElite = true, QuestTurnin = true,
    QuestNormal = true, ["Quest-Campaign-Available"] = true, ["Worldquest-icon"] = true }
C_Texture = { GetAtlasInfo = function(name) return knownAtlases[name] and {} or nil end }
GetPlayerFacing = function() return 0 end
issecretvalue = function() return false end

EllesmereUI = nil
local openedCategory, registeredCategory
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        assert(frame.name == name and name == "Magpie", "standalone options category needs the addon name")
        return { GetID = function() return 517 end }
    end,
    RegisterAddOnCategory = function(category) registeredCategory = category end,
    OpenToCategory = function(categoryID) openedCategory = categoryID end,
}

local settings = { vignetteRadarEnabled = true, vignetteRadarHideWhenEmpty = true,
    vignetteRadarRange = 450, vignetteRadarCircleOnly = false }
local addon = { GetSettings = function() return settings end }
VignetteRadarDB = settings
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Guidance.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Compass.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Themes.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Controls.lua"))("VignetteRadar", addon)
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Schema.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Features.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Recent.lua"))("VignetteRadar", addon)
assert(loadfile("Data/QuestData.lua"))("VignetteRadar", addon)
assert(loadfile("Data/QuestService.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/RouteDraft.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/Exploration.lua"))("VignetteRadar", addon)
assert(loadfile("Data/POIs.lua"))("VignetteRadar", addon)
assert(loadfile("Data/SourceFusion.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/WorldFocus.lua"))("VignetteRadar", addon)
assert(loadfile("Data/Zygor.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/Beacons.lua"))("VignetteRadar", addon)
assert(loadfile(legendSourcePath))("VignetteRadar", addon)
assert(loadfile(targetPickerSourcePath))("VignetteRadar", addon)
assert(loadfile("UI/TurnSmoothing.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Atlas.lua"))("VignetteRadar", addon)
do
    local point = { IsShown = function() return true end,
        SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end }
    local turn = addon.VignetteRadarTurn
    local radar = { field = {}, blips = { point } }
    turn.TrackPoint(point, 0, 10, 0)
    assert(turn.UpdateRadar(radar, math.pi / 2)
        and math.abs(point.x - 10) < .001 and math.abs(point.y) < .001
        and not turn.UpdateRadar(radar, math.pi / 2)
        and turn.Interval(radar, true) == .10,
        "turn-only updates must rotate cached markers without a full render and obey CPU throttling")
    point:SetPoint("CENTER", radar.field, "CENTER", 20, 0)
    turn.TrackPoint(point, 20, 0, math.pi / 2)
    assert(math.abs(point.x - 10) < .001 and radar.field._turnPending,
        "a redraw should preserve the previously displayed position before easing a small move")
    assert(turn.UpdateRadar(radar, math.pi / 2, .05)
        and math.abs(point.x - 15) < .001
        and turn.UpdateRadar(radar, math.pi / 2, .05)
        and math.abs(point.x - 20) < .001
        and not turn.UpdateRadar(radar, math.pi / 2),
        "the existing turn pass should smooth straight-line movement without a new update loop")
end
assert(loadfile("UI/Tray.lua"))("VignetteRadar", addon)
-- The Guide Panel uses the panel helper; the legend tests below run without a tray.
addon.VignetteRadarTrayForRouteCard, addon.VignetteRadarTray = addon.VignetteRadarTray, nil
assert(loadfile(sourcePath))("VignetteRadar", addon)
assert(loadfile("UI/GuidePanel.lua"))("VignetteRadar", addon)
assert(loadfile(optionsSourcePath))("VignetteRadar", addon)
assert(loadfile(quickSourcePath))("VignetteRadar", addon)

do
    local seen = {}
    local function CheckUpvalues(fn)
        if type(fn) ~= "function" or seen[fn] then return end
        seen[fn] = true
        local count, children = 0, {}
        while true do
            local name, value = debug.getupvalue(fn, count + 1)
            if not name then break end
            count = count + 1
            if type(value) == "function" then children[#children + 1] = value end
        end
        local info = debug.getinfo(fn, "S")
        if info and info.source and info.source:find("UI/Radar.lua", 1, true) then
            assert(count <= 60, "WoW's 60-upvalue limit exceeded at radar line "
                .. tostring(info.linedefined) .. ": " .. count)
        end
        for _, child in ipairs(children) do CheckUpvalues(child) end
    end
    for _, entry in pairs(addon.VignetteRadarAPI) do CheckUpvalues(entry) end
end

local optionsEvent
for _, object in ipairs(objects) do
    if object.events and object.events.PLAYER_LOGIN then optionsEvent = object end
end
assert(optionsEvent and optionsEvent.scripts.OnEvent, "standalone addon must register its own settings")
optionsEvent.scripts.OnEvent(optionsEvent)
-- Exercise legacy layout geometry through the compatibility API as well as
-- the finalized default radar tested separately below.
settings.vignetteRadarCircleOnly = false
local optionsPanel = assert(_G.VignetteRadarOptionsPanel, "standalone addon needs a Blizzard settings entry")
assert(registeredCategory and optionsPanel.openButton and optionsPanel.pages == nil,
    "the Blizzard canvas must only point to the radar's own settings window")
SlashCmdList.VIGNETTERADAR("config")
assert(addon.VignetteRadarQuickConfig.IsShown() and openedCategory == nil,
    "config command must open the radar's own settings window")
addon.VignetteRadarQuickConfig.Hide()

settings.vignetteRadarEnabled = false
settings.vignetteRadarScale = 1.35
SlashCmdList.VIGNETTERADAR("preview")
local panel = assert(_G.VignetteRadarPanel, "preview must construct the radar panel")
local launcher = assert(_G.VignetteRadarLauncher, "preview must construct the draggable launcher")
assert(panel:GetScale() == 1.35, "a saved frame size must be restored when the radar is first created")
settings.vignetteRadarScale = 1
panel:SetScale(1)
assert(settings.vignetteRadarEnabled == false, "layout preview must not silently enable live tracking")
assert(panel:IsShown() and panel.width == 246 and panel.height == 278, "preview must reserve space for zoom controls")
SlashCmdList.VIGNETTERADAR("explore")
local explore = assert(_G.VignetteRadarExplorePanel)
assert(explore:IsShown() and explore.width == 330 and explore.height == 425
    and not explore.rail, "exploration controls must fit without an outer edge rail")
for _, content in pairs(explore.pages) do
    assert(content.point[3] == -73 and content.height == 346 and 73 + content.height < explore.height,
        "all exploration pages must stay inside the popout")
end
assert(explore.pages.Route and explore.tabs.Route,
    "route drafting needs a visible management page")
for _, object in ipairs(objects) do
    if object.parent == explore.pages.Route and object.kind == "Button" and object.point then
        local x, y = object.point[2], object.point[3]
        assert(x >= 5 and x + object.width <= explore.pages.Route.width - 5
            and -y >= 0 and -y + object.height <= explore.pages.Route.height - 5,
            "route controls must keep a gutter inside the compact panel")
    end
end
assert(explore.pages.Modes:IsShown() and not explore.pages.Tools:IsShown())
explore.tabs.Tools.scripts.OnClick(explore.tabs.Tools)
assert(explore.pages.Tools:IsShown() and not explore.pages.Modes:IsShown())
assert(panel.field.width == 200 and panel.field.height == 200 and panel.field.point[1] == "BOTTOM"
    and panel.field.point[3] == 35, "radar field must fit between header and zoom controls with visible gutters")
assert(panel.drag.width == 106 and panel.target.point[1] == "TOPRIGHT"
    and panel.legend.point[1] == "TOPRIGHT" and panel.minimize.point[1] == "TOPRIGHT"
    and panel.close.point[1] == "TOPRIGHT",
    "drag target must stop before the focus, legend, minimize, and close controls")
assert(panel.title.font[1] == addon.VignetteRadarStyle.Font(), "radar text must use the bundled monospace font")
assert(panel.summary.text == "PREVIEW" and #panel.blips == 4,
    "preview must explicitly show rare, boss, treasure, and event samples")
local firstBlip, secondBlip = panel.blips[1], panel.blips[2]
for _, blip in ipairs(panel.blips) do
    assert(blip._seen and blip.target.sample == true, "preview marker must be labeled as sample data")
    assert(blip.target.category and blip.dot.vertexColor[4] == 1,
        "preview and live markers must use an opaque category treatment")
    local x, y = blip.point[4], blip.point[5]
    assert(math.sqrt(x * x + y * y) < 91, "preview markers must remain inside the radar ring")
end
panel.scripts.OnUpdate(panel, 0.06)
assert(panel.blips[1] == firstBlip and panel.blips[2] == secondBlip and firstBlip:IsShown() and secondBlip:IsShown(),
    "render ticks must retain stable blip buttons so hover tooltips do not flicker")
assert(#panel.outerRing == 64 and #panel.middleRing == 64 and #panel.innerRing == 64,
    "all radar rings must be complete and bounded")
assert(panel.clamped == true and panel.movable == true, "panel must remain movable and clamped to screen")
assert(launcher.width == 140 and launcher.height == 64 and launcher.clamped == true and launcher.movable == true,
    "launcher must be a compact draggable instrument that stays on screen")
assert(launcher.clickButtons[1] == "LeftButtonUp" and launcher.clickButtons[2] == "RightButtonUp"
    and launcher.dragButtons[1] == "LeftButton", "launcher must expose distinct click and drag gestures")
assert(#launcher.ring == 24 and #launcher.dial == 32 and #launcher.cardinals == 4
    and #launcher.facets == 0 and #launcher.chevron == 2 and #launcher.sweepLines == 2
    and launcher.instrument.width == 56 and launcher.ring[1].parent == launcher.instrument
    and launcher.face.texture:find("launcher%-housing%.tga$")
    and launcher.bezel.texture:find("launcher%-outline%.tga$")
    and launcher.closed.texture:find("launcher%-outline%.tga$")
    and launcher.titleLabel.text == "RADAR" and #launcher.expandChevron == 2,
    "launcher must be a connected horizontal control with a live radar lens and readout")
assert(launcher.rangeLabel.text == "BOSS" and #launcher.miniBlips == 5 and launcher.miniBlips[1]:IsShown(),
    "launcher preview must mirror category markers with a plain boss cue")
launcher.scripts.OnUpdate(launcher, 0.10)
assert(launcher.bezel.alpha >= 0.82 and launcher.bezel.alpha <= 1
    and launcher.shadow == nil and launcher.halo == nil and launcher.alert == nil,
    "detection feedback must preserve the crafted rim without offset shadow or alert layers")

panel.legend.scripts.OnClick(panel.legend)
local legendPanel = assert(_G.VignetteRadarLegendPanel, "radar header must open its attached legend")
assert(legendPanel:IsShown() and legendPanel.point[1] == "TOPLEFT" and legendPanel.point[3] == "TOPRIGHT",
    "legend must open outside the radar with a visible gutter")
legendPanel.rows.rare.scripts.OnClick(legendPanel.rows.rare)
assert(settings.vignetteRadarHighlight == "rare" and firstBlip:GetAlpha() == 1 and secondBlip:GetAlpha() == 0.18,
    "spotlighting a category must keep its dots strong and dim the remaining context")
legendPanel.rows.treasure.toggle.scripts.OnClick(legendPanel.rows.treasure.toggle)
assert(settings.vignetteRadarCategories.treasure == false and not secondBlip:IsShown(),
    "legend category switches must remove disabled dots from the radar immediately")

-- Restore treasure so the specific-vignette picker can exercise more than one row.
addon.VignetteRadarLegend.SetCategoryEnabled("treasure", true)
panel.target.scripts.OnClick(panel.target, "LeftButton")
local targetPanel = assert(_G.VignetteRadarTargetPickerPanel, "reticle button must open its target picker")
assert(targetPanel:IsShown() and targetPanel.rows[1].target.key == "preview-boss",
    "specific-vignette picker must prioritize bosses before ordinary detections")
local rareRow
for _, row in ipairs(targetPanel.rows) do if row.target and row.target.key == "preview-rare" then rareRow = row end end
assert(rareRow).scripts.OnClick(rareRow)
assert(addon.VignetteRadarTargetPicker.GetFocus() == "preview-rare" and firstBlip:IsShown()
    and not secondBlip:IsShown(), "specific focus must isolate one vignette across the full radar")
panel.target.scripts.OnClick(panel.target, "RightButton")
assert(addon.VignetteRadarTargetPicker.GetFocus() == nil,
    "right-clicking the reticle must restore all category-filtered vignettes")
SlashCmdList.VIGNETTERADAR("off")
assert(launcher.closed:IsShown() and not launcher.bezel:IsShown() and not launcher.miniBlips[1]:IsShown()
    and launcher.rangeLabel.text == "OFF" and launcher.center.alpha < 1
    and launcher.dial[1].alpha < 1,
    "disabled tracking must dim the instrument and clearly label its dormant state")
local idleSweepAngle = launcher._sweepAngle
for _ = 1, 6 do launcher.scripts.OnUpdate(launcher, 0.05) end
assert(launcher._sweepAngle == idleSweepAngle and not launcher.sweepLines[1]:IsShown(),
    "the launcher must stop sweeping when tracking is off and no interaction needs animation")

-- Exercise the complete feature path with deterministic live vignette data.
local now, combat, instance, shift, alt = 100, false, false, false, false
local mapID, guids, tracked, sounds = 777, {}, nil, {}
GetTime = function() return now end
InCombatLockdown = function() return combat end
IsInInstance = function() return instance end
IsShiftKeyDown = function() return shift end
IsAltKeyDown = function() return alt end
local health = 0.42
local liveInfo = {
    rare = { name = string.rep("Long rare name ", 5), atlasName = "VignetteKill", vignetteID = 101, onMinimap = true },
    treasure = { name = "Nearby treasure", atlasName = "VignetteLoot", vignetteID = 102, onMinimap = true },
    event = { name = "Event", atlasName = "VignetteEvent", vignetteID = 103, onMinimap = true },
}
local livePositions = { rare = { x = 0.85, y = 0.5 }, treasure = { x = 0.58, y = 0.5 }, event = { x = 0.52, y = 0.51 } }
C_Map.GetBestMapForUnit = function() return mapID end
C_VignetteInfo.GetVignettes = function() return guids end
C_VignetteInfo.GetVignetteInfo = function(key) return liveInfo[key] end
C_VignetteInfo.GetVignettePosition = function(key) return livePositions[key] end
C_VignetteInfo.GetHealthPercent = function() return health end
C_SuperTrack = { SetSuperTrackedVignette = function(key) tracked = key end }
SOUNDKIT = { TELL_MESSAGE = 1, RAID_WARNING = 2 }
PlaySound = function(sound) sounds[#sounds + 1] = sound end
addon.VignetteRadarLegend.SetHighlight(nil)
SlashCmdList.VIGNETTERADAR("on") -- Seed an empty first scan without alerts.
now, guids = 101, { "rare", "treasure" }
addon.VignetteRadarAPI.Refresh(true)
local rareBlip = assert(panel.blipByKey.rare)
assert(#sounds == 0 and rareBlip.target.newUntil > now, "default detection alerts must pulse silently")
assert(rareBlip.dot.atlas == "VignetteKill" and panel.blipByKey.treasure.dot.atlas == "VignetteLoot"
    and rareBlip.dot.vertexColor[1] == 1 and rareBlip.dot.vertexColor[2] == 1,
    "live rares and treasures must use Blizzard's own untinted vignette icons")
rareBlip.scripts.OnEnter(rareBlip)
-- (The Worth-It facts line comes from Core/Guidance.lua.)
assert(GameTooltip.text == liveInfo.rare.name and #GameTooltip.lines <= 5
    and table.concat(GameTooltip.lines, " | "):find("Health 42%", 1, true)
    and GameTooltip.lines[1]:find("Rare ·", 1, true)
    and GameTooltip.lines[#GameTooltip.lines] == "Click to Focus"
    and not table.concat(GameTooltip.lines, " | "):find("Shift-click", 1, true)
    and not table.concat(GameTooltip.lines, " | "):find("Blizzard minimap", 1, true),
    "marker hover must show concise, titled status and move modifier help into the Radar Guide")
rareBlip.scripts.OnLeave(rareBlip)
rareBlip.scripts.OnClick(rareBlip, "LeftButton")
assert(panel.focusReadout:IsShown() and panel.height == 324 and panel.field.point[3] == 81,
    "focusing must reserve exactly the footer space without moving the radar into its header")
assert(panel.focusMeta.text:find("350 yd", 1, true) and panel.focusMeta.text:find("42% HP", 1, true),
    "focused live rare must show distance and available health")
assert(panel.focusName.width == 198 and panel.focusMeta.width == 198,
    "long target text must stay bounded within the focus footer")
addon.SetVignetteRadarCircleOnly(true)
assert(panel.focusCard:IsShown() and panel.focusCard.name.text == liveInfo.rare.name
    and panel.focusCard.showAll and not panel.focusReadout:IsShown(),
    "radar-only focus needs a readable external card and a Show All control")
assert(panel.focusCard.statusSurface and #panel.focusCard.statusSurface.face == 9
    and #panel.focusCard.statusSurface.edge == 9 and not panel.focusCard.accent
    and not panel.focusCard.clear and panel.focusCard.showAll.icon == "eye"
    and panel.focusCard.showAll.labelText == "Show All"
    and panel.focusCard.detail.text:find("Rare ·", 1, true)
    and panel.focusCard.showAll.point[1] == "BOTTOMRIGHT"
    and panel.focusCard.width - 9 - panel.focusCard.showAll.width >= 8,
    "the focus card must use the themed popup treatment and one inset Show All action")
addon.SetVignetteRadarCircleOnly(false)
-- Field bottom is 81; divider y72 leaves 9px. Focus ends y66, above the zoom row.
assert(panel.focusReadout.point[3] + panel.focusReadout.height <= 66
    and panel.focusDivider.point[3] == 72 and panel.field.point[3] >= 81,
    "focus controls and radar must keep clear gutters on both sides of their divider")
settings.vignetteRadarRange = 150
addon.VignetteRadarAPI.Refresh(true)
assert(panel.edgeArrow:IsShown() and not panel.blipByKey.rare,
    "a live focused target outside range must become a bounded direction arrow")
local edgeX, edgeY = panel.edgeArrow.point[4], panel.edgeArrow.point[5]
assert(math.sqrt(edgeX * edgeX + edgeY * edgeY) + 7 <= 83,
    "edge arrow must leave a visible gutter before the outer ring")
shift = true
panel.edgeArrow.scripts.OnClick(panel.edgeArrow, "LeftButton")
assert(tracked == "rare", "shift-click must navigate to the actual live target")
shift, alt = false, true
panel.focusReadout.scripts.OnClick(panel.focusReadout, "LeftButton")
alt = false
assert(addon.VignetteRadarFeatures.IsFavorite(panel.focusReadout.target), "alt-click must persist a favorite")
addon.VignetteRadarTargetPicker.ClearFocus()
assert(addon.VignetteRadarAPI.GetSelectableTargets()[1].key == "rare", "favorites must rank before nearer ordinary targets")
settings.vignetteRadarRange = 450
addon.VignetteRadarAPI.Refresh(true)
rareBlip = panel.blipByKey.rare
assert(rareBlip.favorite:IsShown(), "favorite marker must remain recognizable without hovering")
rareBlip.scripts.OnClick(rareBlip, "LeftButton")
now, guids = 102, { "treasure" }
addon.VignetteRadarAPI.Refresh(true)
rareBlip = assert(panel.blipByKey.rare)
assert(rareBlip.target.stale and not rareBlip.dot:IsShown() and panel.focusMeta.text:find("seen", 1, true)
    and not panel.focusMeta.text:find("HP", 1, true), "lost targets must become hollow last-seen markers without stale health")
assert(not panel.edgeArrow:IsShown(), "stale snapshots must not present live out-of-range navigation")
shift, tracked = true, nil
rareBlip.scripts.OnClick(rareBlip, "LeftButton")
assert(tracked == nil, "last-seen positions must not silently navigate as live targets")
shift = false
local initialAlpha = rareBlip:GetAlpha()
now = 107
addon.VignetteRadarAPI.Refresh(true)
assert(panel.blipByKey.rare:GetAlpha() < initialAlpha, "last-seen markers must fade with elapsed time")
now = 113
addon.VignetteRadarAPI.Refresh(true)
assert(not panel.blipByKey.rare and not panel.focusReadout:IsShown() and panel.height == 278
    and panel.field.point[3] == 35, "expiry must clear focus and release its space while keeping zoom controls")

settings.vignetteRadarAlertSound = true
combat, now, guids = true, 120, { "treasure", "rare" }
addon.VignetteRadarAPI.Refresh(true)
assert(panel:GetAlpha() == 0.35 and launcher:GetAlpha() == 0.35 and #sounds == 0,
    "combat must fade both surfaces and suppress detection sounds")
assert(not panel.combatToggle.keepVisible and panel.combatToggle.backdrop == nil
    and #panel.combatToggle.eye == 4 and panel.combatToggle.pupil,
    "combat visibility must use a borderless eye icon rather than a lettered square")
assert(panel.combatToggle.eye[1].color[4] < 1,
    "the inactive eye must look subdued without introducing a boxed control")
assert(panel.combatToggle.ignoreParentAlpha == true,
    "the quick combat switch must remain legible while the radar is faded")
panel.combatToggle.scripts.OnClick(panel.combatToggle)
assert(settings.vignetteRadarKeepVisibleCombat == true and settings.vignetteRadarQuietCombat == true
    and panel.combatToggle.keepVisible and panel:GetAlpha() == 1 and launcher:GetAlpha() == 1
    and panel.combatToggle.eye[1].color[4] == 1
    and addon.VignetteRadarFeatures.IsQuiet() and #sounds == 0,
    "the footer eye must restore combat visibility without unmuting alerts or rescanning")
panel.combatToggle.scripts.OnClick(panel.combatToggle)
assert(settings.vignetteRadarKeepVisibleCombat == false and settings.vignetteRadarQuietCombat == true
    and not panel.combatToggle.keepVisible
    and panel:GetAlpha() == .35 and launcher:GetAlpha() == .35,
    "clicking the square again must restore combat fading")
combat, now = false, 125
addon.VignetteRadarAPI.Refresh(true)
assert(panel:GetAlpha() == 1 and launcher:GetAlpha() == 1 and #sounds == 0,
    "leaving combat must restore opacity without replaying suppressed detections")
instance = true
addon.VignetteRadarAPI.Refresh(true)
assert(panel:GetAlpha() == 0.35 and launcher:GetAlpha() == 0.35,
    "instance quiet mode must fade both surfaces")
panel.combatToggle.scripts.OnClick(panel.combatToggle)
assert(settings.vignetteRadarKeepVisibleCombat == true and panel:GetAlpha() == 1
    and launcher:GetAlpha() == 1 and addon.VignetteRadarFeatures.IsQuiet() and #sounds == 0,
    "stay fully visible must restore both surfaces inside an instance without unmuting alerts")
combat = true
addon.VignetteRadarAPI.Refresh(true)
assert(panel:GetAlpha() == 1 and launcher:GetAlpha() == 1,
    "stay fully visible must keep both surfaces opaque when combat starts inside an instance")
combat = false
addon.VignetteRadarAPI.Refresh(true)
assert(panel:GetAlpha() == 1 and launcher:GetAlpha() == 1,
    "leaving combat inside an instance must preserve stay fully visible")
panel.combatToggle.scripts.OnClick(panel.combatToggle)
assert(settings.vignetteRadarKeepVisibleCombat == false and panel:GetAlpha() == 0.35
    and launcher:GetAlpha() == 0.35,
    "turning stay fully visible off must restore instance fading on both surfaces")
instance = false
addon.VignetteRadarAPI.Refresh(true)
assert(panel:GetAlpha() == 1 and launcher:GetAlpha() == 1,
    "leaving the instance must restore normal opacity")
local treasureBlip = panel.blipByKey.treasure
treasureBlip.scripts.OnClick(treasureBlip, "RightButton")
assert(not panel.blipByKey.treasure and next(settings.vignetteRadarIgnored) == nil,
    "plain right-click must ignore only for this session")
rareBlip = panel.blipByKey.rare
shift = true
rareBlip.scripts.OnClick(rareBlip, "RightButton")
shift = false
assert(next(settings.vignetteRadarIgnored) ~= nil and #addon.VignetteRadarAPI.GetSelectableTargets() == 0,
    "shift-right-click must persist ignore and remove its target immediately")
addon.VignetteRadarFeatures.ClearIgnored()
addon.VignetteRadarAPI.Refresh(true)
assert(#addon.VignetteRadarAPI.GetSelectableTargets() == 2, "clearing ignores must restore current detections")
do
if not addon.VignetteRadarLegend.IsShown() then addon.VignetteRadarLegend.Toggle(panel.legend) end
assert(addon.VignetteRadarLegend.ToggleMarkers(), "the Radar Legend must open individual live marker controls")
local markerPanel = assert(_G.VignetteRadarMarkerLegendPanel)
markerPanel.tabs.types.scripts.OnClick(markerPanel.tabs.types)
local treasureTypeRow
for _, row in ipairs(markerPanel.rows) do
    if row.entry and row.entry.label == "Treasure" then treasureTypeRow = row; break end
end
assert(treasureTypeRow and treasureTypeRow.icon.atlas == "VignetteLoot",
    "the icon type list must show the same treasure icon used by the radar")
treasureTypeRow.toggle.scripts.OnClick(treasureTypeRow.toggle)
assert(settings.vignetteRadarHiddenMarkerTypes["atlas:vignetteloot"]
    and not panel.blipByKey.treasure and panel.blipByKey.rare,
    "hiding a live icon type must remove matching blips")
treasureTypeRow.toggle.scripts.OnClick(treasureTypeRow.toggle)
assert(settings.vignetteRadarHiddenMarkerTypes["atlas:vignetteloot"] == nil
    and panel.blipByKey.treasure,
    "the icon type switch must restore matching blips")
markerPanel.tabs.names.scripts.OnClick(markerPanel.tabs.names)
local treasureMarkerRow
for _, row in ipairs(markerPanel.rows) do
    if row.entry and row.entry.name == "Nearby treasure" then treasureMarkerRow = row; break end
end
assert(treasureMarkerRow and treasureMarkerRow.toggle.label.text == "ON",
    "live marker names must be listed separately from category visibility")
treasureMarkerRow.toggle.scripts.OnClick(treasureMarkerRow.toggle)
assert(settings.vignetteRadarHiddenMarkerNames["treasure:nearby treasure"] == "Nearby treasure"
    and not panel.blipByKey.treasure and panel.blipByKey.rare
    and #addon.VignetteRadarAPI.GetRawTargets() == 2,
    "hiding one name must rescan while retaining it for restoration")
treasureMarkerRow.toggle.scripts.OnClick(treasureMarkerRow.toggle)
assert(settings.vignetteRadarHiddenMarkerNames["treasure:nearby treasure"] == nil
    and panel.blipByKey.treasure,
    "turning a marker name back on must immediately restore its blip")
markerPanel.back.scripts.OnClick(markerPanel.back)
end
settings.vignetteRadarMarkerSize = 9
addon.VignetteRadarAPI.Refresh(true)
for _, blip in pairs(panel.blipByKey) do
    local x, y = blip.point[4], blip.point[5]
    assert(math.sqrt(x * x + y * y) + blip.width / 2 < 91,
        "largest supported marker hit target must remain clear of the outer ring")
end
now, guids = 200, { "treasure" }
addon.VignetteRadarAPI.Refresh(true)
now, guids = 270, { "rare", "treasure" }
addon.VignetteRadarAPI.Refresh(true)
assert(#sounds == 1 and sounds[1] == SOUNDKIT.RAID_WARNING,
    "an eligible favorite rediscovery after cooldown must play its distinct enabled sound")
addon.VignetteRadarAPI.Refresh(true)
assert(#sounds == 1, "repeated refreshes must not replay the same discovery sound")
-- A new map silently seeds live entries and drops old snapshots/focus.
addon.HandleVignetteClick(panel.blipByKey.rare.target, "LeftButton")
mapID, guids, now = 778, {}, 280
addon.VignetteRadarAPI.Refresh(true)
assert(#addon.VignetteRadarAPI.GetTargets() == 0 and addon.VignetteRadarTargetPicker.GetFocus() == nil,
    "zone transitions must not retain old-map targets")
Enum = { QuestTagType = { WorldBoss = 99 } }
C_QuestLog = { GetQuestTagInfo = function(id)
    return id == 700 and { worldQuestType = Enum.QuestTagType.WorldBoss } or nil
end }
liveInfo.boss = { name = "World boss", atlasName = "VignetteKillElite", rewardQuestID = 700, vignetteID = 700, onMinimap = true }
livePositions.boss = { x = 0.55, y = 0.55 }
now, guids = 281, { "boss", "rare" }
addon.VignetteRadarAPI.Refresh(true)
local bossBlip = assert(panel.blipByKey.boss)
rareBlip = assert(panel.blipByKey.rare)
assert(bossBlip.target.isWorldBoss and bossBlip.target.category == "rare"
    and bossBlip.dot.width > rareBlip.dot.width and bossBlip.dot.atlas == "VignetteKillElite"
    and rareBlip.dot.atlas == "VignetteKill",
    "confirmed world bosses must have larger elite icons distinct from rares")
assert(launcher.rangeLabel.text == "BOSS" and launcher.bosses == 1,
    "a nearby confirmed boss must have a plain-language launcher cue")
bossBlip.scripts.OnClick(bossBlip, "LeftButton")
assert(panel.focusMeta.text:find("BOSS", 1, true), "focused boss identity must be explicit without color knowledge")
now, guids = 282, { "rare" }
addon.VignetteRadarAPI.Refresh(true)
assert(panel.blipByKey.boss.target.stale and panel.blipByKey.boss.target.isWorldBoss
    and launcher.rangeLabel.text ~= "BOSS", "last-seen boss classification must persist without implying a live nearby boss")

-- Wider ranges reveal only positions actually supplied by the game.
addon.VignetteRadarTargetPicker.ClearFocus()
settings.vignetteRadarAlertSound = false
liveInfo.far = { name = "Far map treasure", atlasName = "VignetteLoot", vignetteID = 800,
    onMinimap = false, onWorldMap = true, inFogOfWar = false }
liveInfo.fogged = { name = "Fogged", atlasName = "VignetteLoot", vignetteID = 801,
    onMinimap = false, onWorldMap = true, inFogOfWar = true }
liveInfo.unpublished = { name = "Unpublished", atlasName = "VignetteLoot", vignetteID = 802,
    onMinimap = false, onWorldMap = false, inFogOfWar = false }
livePositions.far = { x = 0.8, y = 0.5 }
livePositions.fogged = { x = 0.7, y = 0.5 }
livePositions.unpublished = { x = 0.6, y = 0.5 }
C_Map.GetWorldPosFromMapPos = function(_, position) return 42, { x = position.x * 10000, y = position.y * 10000 } end
now, guids, mapID = 300, { "far", "fogged", "unpublished" }, 779
addon.VignetteRadarAPI.Refresh(true)
assert(#addon.VignetteRadarAPI.GetTargets() == 1 and addon.VignetteRadarAPI.GetTargets()[1].source == "worldMap",
    "wide view must accept exposed map data while rejecting fogged and unpublished positions")
assert(not panel.blipByKey.far, "distant data must stay outside the current display range")
for _ = 1, 5 do panel.zoomOut.scripts.OnClick(panel.zoomOut) end
assert(settings.vignetteRadarRange == 4800 and panel.zoomLabel.text == "4800 yd" and panel.blipByKey.far,
    "zoom-out controls must reveal a supplied detection 3000 yards away")
assert(panel.blipByKey.far.sourceBadge:IsShown(),
    "world-map locations need a source badge distinct from live minimap detections")
settings.vignetteRadarSourceBadges = false
addon.VignetteRadarAPI.Refresh(false)
assert(not panel.blipByKey.far.sourceBadge:IsShown(),
    "the marker-source badge must honor its settings switch")
settings.vignetteRadarSourceBadges = true
addon.VignetteRadarAPI.Refresh(false)
assert(panel.blipByKey.far.target.distance == 3000 and launcher.detected == 0,
    "full-radar zoom must preserve yard distances and the launcher's fixed 150-yard radius")
panel.field.scripts.OnMouseWheel(panel.field, 1)
assert(settings.vignetteRadarRange == 2400 and not panel.blipByKey.far, "mouse wheel up must zoom in")
panel.scripts.OnMouseWheel(panel, -1)
assert(settings.vignetteRadarRange == 4800 and panel.blipByKey.far, "mouse wheel down must zoom out")
panel.blipByKey.far.scripts.OnMouseWheel(panel.blipByKey.far, 1)
assert(settings.vignetteRadarRange == 2400, "wheel zoom must also work while hovering a marker")
panel.zoomOut.scripts.OnClick(panel.zoomOut)
panel.blipByKey.far.scripts.OnClick(panel.blipByKey.far, "LeftButton")
assert(panel.focusReadout:IsShown() and panel.height == 324 and panel.zoomOut.point[5] == 6
    and panel.zoomOut.height == 20 and panel.focusReadout.point[3] >= 34,
    "disclosed focus readout must reserve a gutter above the zoom controls")
do
    local originalMapInfo = C_Map.GetMapInfo
    local originalVignettePosition = C_VignetteInfo.GetVignettePosition
    liveInfo.parentChest = { name = "Parent map cache", atlasName = "VignetteLoot",
        vignetteID = 803, onMinimap = false, onWorldMap = true, inFogOfWar = false }
    C_Map.GetMapInfo = function(id)
        return id == 779 and { parentMapID = 780 } or nil
    end
    C_VignetteInfo.GetVignettePosition = function(key, requestedMap)
        if key == "parentChest" then
            return requestedMap == 780 and { x = .55, y = .5 } or nil
        end
        return originalVignettePosition(key, requestedMap)
    end
    guids = { "parentChest" }
    addon.VignetteRadarAPI.Refresh(true)
    local parentTarget = addon.VignetteRadarAPI.GetTargets()[1]
    assert(parentTarget and parentTarget.name == "Parent map cache"
        and parentTarget.mapID == 780 and parentTarget.mapX == .55,
        "a visible Blizzard treasure positioned on the parent map must reach route data")
    C_Map.GetMapInfo = originalMapInfo
    C_VignetteInfo.GetVignettePosition = originalVignettePosition
    guids = { "far", "fogged", "unpublished" }
    addon.VignetteRadarAPI.Refresh(true)
end
settings.vignetteRadarWorldMap = false
addon.VignetteRadarAPI.Refresh(true)
assert(#addon.VignetteRadarAPI.GetTargets() == 0 and not panel.blipByKey.far and not panel.focusReadout:IsShown(),
    "disabling world-map entries must clear them and their focus without leaving ghosts")
settings.vignetteRadarAlertSound = true
local soundCount = #sounds
settings.vignetteRadarWorldMap = true
addon.VignetteRadarAPI.Refresh(true)
assert(panel.blipByKey.far and #sounds == soundCount, "enabling wider data scope must seed silently")
assert(not addon.SetVignetteRadarRange(999999) and settings.vignetteRadarRange == 4800,
    "unsupported zoom ranges must not corrupt saved settings")
for _ = 1, 10 do panel.zoomIn.scripts.OnClick(panel.zoomIn) end
assert(settings.vignetteRadarRange == 10, "zoom-in must clamp at the minimum")
assert(panel.zoomOut.backdrop == nil and panel.zoomIn.backdrop == nil
    and #panel.zoomOut.strokes == 1 and #panel.zoomIn.strokes == 2
    and panel.zoomOut.glow and panel.zoomIn.glow,
    "zoom controls must use borderless minus and plus icons with the radar's circular glow")
assert(panel.trailToggle.backdrop == nil and #panel.trailToggle.strokes == 12
    and panel.compass.ignoreParentAlpha and panel.trailToggle.ignoreParentAlpha
    and panel.trailToggle.glow and panel.trailToggle.clickButtons[2] == "RightButtonUp",
    "the trail shortcut must match the toolbar and accept a style-changing right click")
assert(panel.routeToggle.backdrop == nil and panel.routeToggle.art.texture
        == "Interface\\AddOns\\Magpie\\Media\\radar-corner-controls.tga"
    and not panel.routeToggle.glow:IsShown()
    and panel.routeToggle.clickButtons[2] == "RightButtonUp",
    "Auto Route must use the shared themed icon states and accept a right-click")
function CornerTool(id)
    for _, tool in ipairs(panel.hoverTools) do
        if tool.toolID == id then return tool end
    end
end
local routeHover = assert(CornerTool("route"))
assert(settings.vignetteRadarAdvancedTools == false
    and not CornerTool("constellation").advancedTool and CornerTool("player").advancedTool,
    "Advanced Tools corner controls must stay hidden while the switch is off")
settings.vignetteRadarAdvancedTools = true
addon.InvalidateSettings()
addon.VignetteRadarAPI.Refresh(true)
assert(CornerTool("constellation"):IsShown(),
    "the constellation button must remain available on the normal radar frame")
assert(routeHover.toolID == "route" and routeHover.artColumn == 10
    and routeHover.glyphName == "corner_route" and routeHover.iconLayers
    and CornerTool("eye").glyphName == "corner_eye" and CornerTool("player").glyphName == "corner_player"
    and CornerTool("eye").artColumn == 7 and CornerTool("player").artColumn == 8,
    "Route, eye, and Player Tracker must use their intended cells in the shared icon atlas")
do
    local original = addon.VignetteRadarPlayerTracker
    local opened, marked = 0, 0
    addon.VignetteRadarPlayerTracker = {
        IsDetecting = function() return false end,
        Open = function() opened = opened + 1 end,
        MarkTarget = function() marked = marked + 1; return true end,
    }
    local playerTool = CornerTool("player")
    playerTool.scripts.OnClick(playerTool, "LeftButton")
    playerTool.scripts.OnClick(playerTool, "RightButton")
    assert(opened == 1 and marked == 1,
        "the radar Player Tracker control must open the list or mark the current target")
    addon.VignetteRadarPlayerTracker = original
end
do
    local tracker = addon.VignetteRadarQuestTracker
    local toggles = 0
    addon.VignetteRadarQuestTracker = {
        ToggleTray = function() toggles = toggles + 1 end,
        IsExpanded = function() return toggles % 2 == 1 end,
    }
    local button = assert(CornerTool("tracker"))
    assert(button.artColumn == 11 and button.art.texture == routeHover.art.texture
        and button.glyphName == "corner_tracker",
        "the Quest Tracker button must use the matching corner-control artwork")
    button.scripts.OnClick(button, "LeftButton")
    assert(toggles == 1 and button._artState >= 2,
        "the radar control must open the tray and show its selected state")
    addon.VignetteRadarQuestTracker = tracker
    panel.RefreshCornerTools()
end
do
    local normalState = panel.routeToggle.art.texCoord[3]
    panel.routeToggle.scripts.OnEnter(panel.routeToggle)
    assert(panel.routeToggle.art.texCoord[3] ~= normalState,
        "the framed Auto Route icon must use its hover artwork")
    panel.routeToggle.scripts.OnLeave(panel.routeToggle)
    local cornerState = routeHover._artState
    routeHover.scripts.OnEnter(routeHover)
    assert(routeHover._artState ~= cornerState and routeHover.iconLayers.glow.vertexColor[4] > 0,
        "the radar-only Auto Route icon must use the same hover-state family")
    routeHover.scripts.OnLeave(routeHover)
end
do
    local bridge = addon.VignetteRadarZygor
    local viewer = _G.ZygorGuidesViewer
    local isPaused, isFollowing = bridge.IsPaused, bridge.IsFollowing
    local guideLabel, status, toggleFollow = bridge.GuideLabel, bridge.Status, bridge.ToggleFollow
    local resumes = 0
    _G.ZygorGuidesViewer = {}
    bridge.IsPaused = function() return true end
    bridge.IsFollowing = function() return false end
    bridge.GuideLabel = function() return "Example Guide · Step 1" end
    bridge.Status = function() return "Zygor Follow Paused" end
    bridge.ToggleFollow = function() resumes = resumes + 1; return true end
    addon.SetVignetteRadarCircleOnly(true)
    routeHover.scripts.OnEnter(routeHover)
    local strip
    for _, object in ipairs(objects) do
        if object.kind == "Frame" and object.action and object.detail and object.title then
            strip = object
            break
        end
    end
    assert(strip and strip:IsShown() and strip.point[1] == "BOTTOMRIGHT"
        and strip.point[2] == routeHover and strip.point[3] == "TOPRIGHT"
        and routeHover.clickButtons[3] == "MiddleButtonUp"
        and panel.routeToggle.clickButtons[3] == "MiddleButtonUp",
        "Zygor Follow must appear next to the route control with a direct resume shortcut")
    routeHover.scripts.OnClick(routeHover, "MiddleButton")
    assert(resumes == 1, "middle-clicking the radar Auto Route control must resume paused Zygor Follow")
    strip.action.scripts.OnClick()
    assert(resumes == 2, "the visible Resume action must remain clickable")
    strip:Hide()
    _G.ZygorGuidesViewer = viewer
    bridge.IsPaused, bridge.IsFollowing = isPaused, isFollowing
    bridge.GuideLabel, bridge.Status, bridge.ToggleFollow = guideLabel, status, toggleFollow
    addon.SetVignetteRadarCircleOnly(false)
end
do
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    local chooser = assert(_G.VignetteRadarRouteChooserPopup)
    assert(chooser:IsShown() and chooser.width == 326 and chooser.height == 263
        and chooser.clamped and chooser.point[2] == panel.routeToggle
        and chooser.choices.rare and chooser.choices.treasure and chooser.choices.quest
        and chooser.choices.zygor and chooser.choices.previous and chooser.choices.next
        and chooser.choices.pause and chooser.choices.skip and chooser.choices.skipQuest
        and chooser.choices.clear
        and chooser.choices.settings
        and UISpecialFrames[#UISpecialFrames] == chooser.name,
        "right-click should open an accessible route chooser with every action")
    for _, button in pairs(chooser.choices) do
        assert(button.point[4] >= 12 and button.point[4] + button.width <= chooser.width - 12
            and -button.point[5] + button.height <= chooser.height - 12,
            "route chooser actions must fit inside the popup with a visible gutter")
    end
    assert(chooser.choices.rare.icon.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
        and chooser.choices.closest.icon.texture:find("route%-crystal%-pointer%.tga$")
        and chooser.choices.treasure.icon.atlas == "VignetteLoot"
        and chooser.choices.quest.icon.texture:find("quest%-diamond%-hollow%.tga$")
        and chooser.choices.zygor.icon.texture:find("radar%-corner%-controls%.tga$")
        and chooser.choices.rare.height == 42 and chooser.choices.zygor.height == 42
        and chooser.choices.zygor.point[4] + chooser.choices.zygor.width
            <= chooser.width - 12,
        "all five route choices need distinct artwork within the popup gutter")
    assert(not chooser.choices.quest.face:IsShown() and not chooser.choices.quest.edge:IsShown()
        and #chooser.choices.quest.statusSurface.face == 9
        and #chooser.choices.quest.statusSurface.edge == 9,
        "route tiles should use one complete rounded surface without the old square fill or underline")
    local originalChoice = addon.VignetteRadarWorldFocus.GetRouteChoice
    addon.VignetteRadarWorldFocus.GetRouteChoice = function() return "treasure", "active" end
    chooser.close.scripts.OnClick()
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    assert(chooser.choices.treasure._routeSelected
        and not chooser.choices.rare._routeSelected
        and chooser.choices.treasure.chosenPip:IsShown()
        and not chooser.choices.rare.chosenPip:IsShown()
        and chooser.choices.treasure.statusSurface.face[1].vertexColor[4] < .12
        and chooser.choices.treasure.statusSurface.face[1].vertexColor[4]
            > chooser.choices.rare.statusSurface.face[1].vertexColor[4]
        and chooser.choices.treasure.statusSurface.edge[1].vertexColor[4] > .8,
        "the active route category needs a clear border without an opaque fill")
    addon.VignetteRadarWorldFocus.GetRouteChoice = function() return "quest", "paused" end
    chooser.close.scripts.OnClick()
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    assert(chooser.choices.quest._routeSelected
        and chooser.choices.quest.statusSurface.edge[1].vertexColor[4] > .4
        and chooser.choices.quest.statusSurface.edge[1].vertexColor[4] < .8,
        "a paused route should keep its category selected with a quieter border")
    addon.VignetteRadarWorldFocus.GetRouteChoice = function() return "closest", "active" end
    chooser.close.scripts.OnClick()
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    assert(chooser.choices.closest._routeSelected
        and not chooser.choices.quest._routeSelected,
        "Closest mode should visibly select its own route tile")
    addon.VignetteRadarWorldFocus.GetRouteChoice = originalChoice
    local bridge = addon.VignetteRadarZygor
    local originalFollowing = bridge.IsFollowing
    bridge.IsFollowing = function() return true end
    chooser.close.scripts.OnClick()
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    assert(chooser.choices.zygor._routeSelected
        and chooser.choices.zygor.statusSurface.edge[1].vertexColor[4] > .8,
        "following an active Zygor step should light its route choice")
    bridge.IsFollowing = originalFollowing
    local routeAPI = addon.VignetteRadarAPI
    local originalStartZygor, originalBindZygor = routeAPI.StartZygorRoute, routeAPI.BindZygorGuide
    local startedZygor = 0
    routeAPI.StartZygorRoute = function() startedZygor = startedZygor + 1; return true end
    routeAPI.BindZygorGuide = function() return true end
    local originalPin = bridge.Pin
    local pinned
    bridge.Pin = function(mode) pinned = mode; return true end
    chooser.choices.zygor.scripts.OnClick()
    assert(startedZygor == 1 and chooser:IsShown() and chooser.height == 300 and chooser.zygor:IsShown()
        and not chooser.choices.rare:IsShown(),
        "the Zygor route choice should activate Follow and open its objective picker")
    chooser.zygor.objective.scripts.OnClick()
    assert(pinned == "objective" and not chooser:IsShown(),
        "the selected objective action should pin and dismiss the chooser")
    bridge.Pin = function()
        return false, "Zygor has no active guide waypoint"
    end
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    chooser.choices.zygor.scripts.OnClick()
    chooser.zygor.objective.scripts.OnClick()
    assert(chooser:IsShown() and chooser.zygor.status.text == "Zygor has no active guide waypoint",
        "a failed Zygor pin must explain why instead of silently closing: "
            .. tostring(chooser:IsShown()) .. ", " .. tostring(chooser.zygor.status.text))
    chooser.close.scripts.OnClick()
    bridge.Pin = originalPin
    routeAPI.StartZygorRoute, routeAPI.BindZygorGuide = originalStartZygor, originalBindZygor
    local focus = addon.VignetteRadarWorldFocus
    local originalNearest, chosen = focus.StartNearest, nil
    focus.StartNearest = function(kind) chosen = kind; return true end
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    chooser.choices.quest.scripts.OnClick()
    assert(chosen == "quest" and not chooser:IsShown(),
        "the quest choice must start its route without a separate marker click")
    focus.StartNearest = originalNearest
    local originalQuestRoute, originalPreviousStep, originalNextStep =
        focus.IsQuestRoute, focus.PreviousQuestStep, focus.NextQuestStep
    local previousCalls, nextCalls = 0, 0
    focus.IsQuestRoute = function() return true end
    focus.PreviousQuestStep = function() previousCalls = previousCalls + 1; return true end
    focus.NextQuestStep = function() nextCalls = nextCalls + 1; return true end
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    assert(chooser.choices.previous.text == "Previous Step"
        and chooser.choices.next.text == "Next Step",
        "an active quest route should label the chooser buttons as quest-step navigation")
    chooser.choices.previous.scripts.OnClick()
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    chooser.choices.next.scripts.OnClick()
    assert(VignetteRadar_NavigateQuestRoute(-1) and VignetteRadar_NavigateQuestRoute(1)
        and previousCalls == 2 and nextCalls == 2,
        "quest-step buttons and global bindings should use the same previous/next actions")
    focus.IsQuestRoute, focus.PreviousQuestStep, focus.NextQuestStep =
        originalQuestRoute, originalPreviousStep, originalNextStep
    routeHover.scripts.OnClick(routeHover, "RightButton")
    assert(chooser:IsShown() and chooser.point[2] == routeHover,
        "the radar-only route icon must anchor the same chooser")
    routeHover.scripts.OnClick(routeHover, "RightButton")
    assert(not chooser:IsShown(), "right-clicking the route icon again should close its chooser")
end
assert(not panel.zoomIn._enabled and panel.zoomIn.strokes[1].color[4] < .4,
    "the zoom-in icon must visibly dim at the closest range")
panel.zoomOut.scripts.OnEnter(panel.zoomOut)
assert(panel.zoomOut.glow.vertexColor[4] >= .2 and panel.zoomOut.strokes[1].color[4] == 1,
    "hovering zoom-out must brighten its icon without adding a square")
panel.zoomOut.scripts.OnLeave(panel.zoomOut)
assert(panel.target.highlight == nil and panel.legend.highlight == nil
    and panel.close.highlight == nil and panel.legend.glow and panel.close.glow,
    "the other radar toolbar icons must also avoid square hover highlights")
panel.close.scripts.OnEnter(panel.close)
assert(panel.close.glow.vertexColor[4] >= .18,
    "the close icon must use the same circular hover cue")
panel.close.scripts.OnLeave(panel.close)

-- Resolve frame anchors, rather than assuming each layout uses the same origin.
local anchors = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local function bounds(region)
    if region == panel then return { 0, 0, panel.width, panel.height } end
    local p = assert(region.point, "region needs an explicit anchor")
    local relative, relativePoint, x, y
    if type(p[2]) == "table" then relative, relativePoint, x, y = p[2], p[3], p[4] or 0, p[5] or 0
    else relative, relativePoint, x, y = region.parent, p[1], p[2] or 0, p[3] or 0 end
    local base, origin, target = bounds(relative), anchors[p[1]], anchors[relativePoint]
    local width, height = assert(region.width), assert(region.height)
    local left = base[1] + (base[3] - base[1]) * target[1] + x - width * origin[1]
    local bottom = base[2] + (base[4] - base[2]) * target[2] + y - height * origin[2]
    return { left, bottom, left + width, bottom + height }
end
local function separate(first, second, gap, label)
    local a, b = bounds(first), bounds(second)
    assert(a[3] + gap <= b[1] or b[3] + gap <= a[1]
        or a[4] + gap <= b[2] or b[4] + gap <= a[2], "layout gutter: " .. label
            .. " [" .. table.concat(a, ",") .. "] [" .. table.concat(b, ",") .. "]")
end
local function inside(region, parent, gutter)
    local a, b = bounds(region), bounds(parent or panel)
    assert(a[1] >= b[1] + gutter and a[2] >= b[2] + gutter
        and a[3] <= b[3] - gutter and a[4] <= b[4] - gutter,
        "layout region escapes its parent: " .. tostring(region.text or region.kind))
end
local function checkLayout(focused)
    local controls = { panel.target, panel.legend, panel.minimize, panel.close, panel.zoomOut, panel.zoomIn, panel.zoomLabel,
        panel.compass, panel.combatToggle, panel.trailToggle, panel.routeToggle }
    inside(panel.settingsDot, panel, 4)
    separate(panel.settingsDot, panel.title, 2, "settings/title")
    separate(panel.settingsDot, panel.summary, 2, "settings/status")
    separate(panel.settingsDot, panel.drag, 2, "settings/drag")
    for _, control in ipairs(controls) do separate(panel.settingsDot, control, 2, "settings/toolbar") end
    inside(panel.field.halo, panel, 4)
    inside(panel.title, panel, 4)
    inside(panel.summary, panel, 4)
    separate(panel.field.halo, panel.title, 4, "radar/title")
    separate(panel.field.halo, panel.summary, 4, "radar/summary")
    for index, control in ipairs(controls) do
        inside(control, panel, 4)
        separate(control, panel.field.halo, 4, "toolbar/radar")
        separate(control, panel.drag, 2, "toolbar/drag")
        for other = index + 1, #controls do separate(control, controls[other], 2, "toolbar hit targets") end
        if panel.layout ~= "classic" then
            assert(bounds(control)[4] <= 50, "alternate layouts must keep all controls below the radar")
        end
    end
    if focused then
        inside(panel.focusReadout, panel, 4)
        inside(panel.focusName, panel.focusReadout, 0)
        inside(panel.focusMeta, panel.focusReadout, 0)
        separate(panel.focusName, panel.focusMeta, 4, "focus name/metadata")
        separate(panel.focusReadout, panel.field.halo, 6, "focus/radar")
        separate(panel.focusDivider, panel.field.halo, 6, "divider/radar")
        separate(panel.focusDivider, panel.focusReadout, 6, "divider/focus")
        for _, control in ipairs(controls) do separate(control, panel.focusReadout, 6, "toolbar/focus") end
    elseif panel.layout == "squat" then
        inside(panel.layoutHint, panel, 4)
        separate(panel.layoutHint, panel.field.halo, 6, "hint/radar")
    end
    if panel.layout == "squat" then
        inside(panel.sideCaption, panel, 4)
        inside(panel.sideGuide, panel, 4)
        separate(panel.sideCaption, panel.focusReadout, 8, "right-rail caption/details")
        separate(panel.sideGuide, panel.focusReadout, 8, "right-rail details/action")
        separate(panel.sideCaption, panel.field.halo, 6, "right-rail caption/radar")
        separate(panel.sideGuide, panel.field.halo, 6, "right-rail action/radar")
    end
    assert(panel.resizeGrips and panel.resizeGrips.top.width == panel.width - 20
        and panel.resizeGrips.left.height == panel.height - 20,
        "each layout must keep all edge resize hit areas on its current borders")
    for _, grip in pairs(panel.resizeGrips) do
        inside(grip, panel, 0)
        for _, control in ipairs(controls) do
            separate(grip, control, 0, "resize border/button hit targets")
        end
    end
    assert(panel.field.width == panel.field.height, "layout must preserve circular radar geometry")
    inside(panel.frameToggle, panel, 4)
    local fieldRect, toggleRect = bounds(panel.field), bounds(panel.frameToggle)
    assert(toggleRect[1] >= (fieldRect[1] + fieldRect[3]) / 2 + panel.plotRadius + 8
        and panel.frameToggle.backdrop == nil and panel.frameToggle.label == nil
        and #panel.frameToggle.chevron == 2,
        "the frame toggle must be a borderless chevron outside every radar plotting area")
    if panel.layout == "squat" then
        assert(toggleRect[3] + 4 <= bounds(panel.focusDivider)[1],
            "the chevron must preserve a gutter before the squat details divider")
    end
    for _, line in ipairs(panel.rangeRing) do
        local x, y = line.startPoint[3], line.startPoint[4]
        assert(math.abs(math.sqrt(x*x + y*y) - panel.plotRadius) < 0.001, "rings must follow the active layout radius")
    end
end

addon.SetVignetteRadarRange(4800)
local savedPosition, savedCategories = { x = 90, y = -80 }, settings.vignetteRadarCategories
settings.vignetteRadarPosition = savedPosition
local originalPanel, originalField = panel, panel.field
local scanCount, getVignettes = 0, C_VignetteInfo.GetVignettes
C_VignetteInfo.GetVignettes = function() scanCount = scanCount + 1; return getVignettes() end
for _, name in ipairs({ "squat", "compact", "classic", "compact", "squat", "classic" }) do
    panel.legend.scripts.OnClick(panel.legend)
    assert(legendPanel:IsShown())
    local before = scanCount
    assert(addon.SetVignetteRadarLayout(name))
    assert(panel == originalPanel and panel.field == originalField and scanCount == before,
        "view changes must reuse existing frames without rescanning detection data")
    assert(settings.vignetteRadarLayout == name and panel.layout == name and not legendPanel:IsShown(),
        "switching views must save the selection and close old pop-outs")
    assert(settings.vignetteRadarRange == 4800 and settings.vignetteRadarPosition == savedPosition
        and settings.vignetteRadarCategories == savedCategories, "view changes must preserve range, filters and position")
    checkLayout(false)
    local far = assert(panel.blipByKey.far)
    if name == "squat" then
        assert(panel.focusReadout:IsShown() and panel.focusReadout.target.key == "far"
            and panel.sideCaption.text == "NEAREST DETECTION"
            and panel.focusName.text == "Far map treasure" and panel.focusMeta.text:find("3000 yd", 1, true)
            and panel.focusMeta.text:find("TREASURE", 1, true)
            and panel.sideGuide.text == "CLICK TO FOCUS",
            "Squat must show actionable current detection details without a manual focus")
        panel.focusReadout.scripts.OnClick(panel.focusReadout, "LeftButton")
        assert(addon.VignetteRadarTargetPicker.GetFocus() == "far" and panel.sideCaption.text == "TRACKING",
            "clicking automatic details must focus that exact detection")
        panel.focusReadout.scripts.OnClick(panel.focusReadout, "LeftButton")
        assert(addon.VignetteRadarTargetPicker.GetFocus() == nil
            and panel.sideCaption.text == "NEAREST DETECTION",
            "clicking the tracked details again must restore the automatic view")
    end
    local x, y = far.point[4], far.point[5]
    assert(math.abs(math.sqrt(x*x+y*y) - panel.plotRadius * 3000 / 4800) < 0.001,
        "live target distances must project to the resized plotting area")
    far.scripts.OnClick(far, "LeftButton")
    local baseHeight = panel.height
    if name == "squat" then
        assert(panel.sideCaption.text == "TRACKING" and panel.sideGuide.text == "CLICK AGAIN TO SHOW ALL",
            "the right side must clearly distinguish tracking from an automatic detection")
    end
    checkLayout(true)
    assert(panel.focusMeta.text:find("3000 yd", 1, true), "focus must retain actual yard distances in every layout")
    for _, other in ipairs({ "squat", "compact", "classic", name }) do
        addon.SetVignetteRadarLayout(other)
        assert(addon.VignetteRadarTargetPicker.GetFocus() == "far" and panel.focusReadout:IsShown(),
            "switching a focused view must preserve the target and disclosed details")
        checkLayout(true)
    end
    addon.SetVignetteRadarRange(150)
    assert(panel.edgeArrow:IsShown())
    x, y = panel.edgeArrow.point[4], panel.edgeArrow.point[5]
    assert(math.abs(math.sqrt(x*x+y*y) - panel.plotRadius) < 0.001
        and math.sqrt(x*x+y*y) + 7 < panel.fieldRadius, "rim arrow must track the resized plotting radius")
    if name == "squat" then
        addon.VignetteRadarTargetPicker.ClearFocus()
        assert(panel.focusReadout:IsShown() and panel.sideCaption.text == "OUTSIDE RADAR RANGE"
            and panel.sideGuide.text == "ZOOM OUT TO SEE IT",
            "automatic details must identify a reported detection beyond the selected radius")
    end
    addon.SetVignetteRadarRange(4800)
    for _, right in ipairs({ 400, 1590 }) do
        panel.right, panel.left = right, right - panel.width
        panel.target.scripts.OnClick(panel.target, "LeftButton")
        assert(targetPanel:IsShown() and targetPanel.clamped)
        separate(targetPanel, panel, 8, "target picker/panel")
        assert(targetPanel.point[1] == (right == 400 and "TOPLEFT" or "TOPRIGHT"),
            "target picker must choose the side that has space")
        panel.legend.scripts.OnClick(panel.legend)
        assert(legendPanel:IsShown() and legendPanel.clamped and not targetPanel:IsShown())
        separate(legendPanel, panel, 8, "legend/panel")
        panel.legend.scripts.OnClick(panel.legend)
    end
    panel.right, panel.left = nil, nil
    addon.VignetteRadarTargetPicker.ClearFocus()
    assert(name ~= "squat" or panel.height == baseHeight, "Squat must not grow taller when focusing a target")
    if name == "squat" then
        assert(panel.focusReadout:IsShown() and panel.sideCaption.text == "NEAREST DETECTION",
            "clearing focus should return to useful automatic details")
    end
    checkLayout(false)
end
assert(not addon.SetVignetteRadarLayout("invalid") and settings.vignetteRadarLayout == "classic")
for _, expected in ipairs({ "squat", "compact", "classic" }) do
    SlashCmdList.VIGNETTERADAR("layout")
    assert(settings.vignetteRadarLayout == expected, "bare layout command must cycle through all three views")
end
SlashCmdList.VIGNETTERADAR("layout compact")
assert(settings.vignetteRadarLayout == "compact", "layout command must also select a style by name")
SlashCmdList.VIGNETTERADAR("off")
addon.SetVignetteRadarLayout("squat")
assert(not panel:IsShown() and settings.vignetteRadarEnabled == false,
    "changing layout must not reopen or re-enable disabled tracking")
SlashCmdList.VIGNETTERADAR("preview")
for _, name in ipairs({ "squat", "compact", "classic" }) do
    addon.SetVignetteRadarLayout(name)
    checkLayout(false)
    if name == "squat" then
        addon.VignetteRadarLegend.SetCategoryEnabled("rare", false)
        assert(panel.focusReadout.target.category == "treasure",
            "automatic preview details must follow the enabled categories")
        addon.VignetteRadarLegend.SetCategoryEnabled("rare", true)
    end
    for _, blip in pairs(panel.blipByKey) do
        local x, y = blip.point[4], blip.point[5]
        assert(math.sqrt(x*x+y*y) + blip.width / 2 < panel.fieldRadius,
            "preview markers must remain inside the smallest radar with maximum marker size")
    end
end
assert(settings.vignetteRadarEnabled == false, "previewing alternate views must not enable tracking")

-- A narrow game canvas and saved positions next to screen edges must fit after resizing/focusing.
UIParent:SetSize(800, 600)
for _, name in ipairs({ "squat", "compact", "classic" }) do
    panel.left, panel.top = 780, 250
    addon.SetVignetteRadarLayout(name)
    addon.HandleVignetteClick(panel.blipByKey["preview-rare"].target, "LeftButton")
    local x, top = panel.point[4], UIParent.height + panel.point[5]
    assert(x >= 4 and x + panel.width <= UIParent.width - 4
        and top <= UIParent.height - 4 and top - panel.height >= 4,
        "expanded layout must reclamp with a visible gutter on an 800x600 canvas")
    checkLayout(true)
    addon.VignetteRadarTargetPicker.ClearFocus()
end
panel.left, panel.top = nil, nil
UIParent:SetSize(1600, 900)

-- Fixed north keeps both radars' detections still while the player direction line turns.
local playerFacing = 0
GetPlayerFacing = function() return playerFacing end
guids, now, mapID = { "rare" }, 400, 780
livePositions.rare = { x = 0.507, y = 0.5 }
addon.SetVignetteRadarRange(450)
SlashCmdList.VIGNETTERADAR("on")
local northOption
for _, object in ipairs(objects) do
    if object.optionKey == "vignetteRadarNorthUp" then northOption = object; break end
end
assert(northOption, "north-up must also be available in Layout settings")
-- QuickConfig syncs its checkboxes whenever it is shown.
local function NorthOptionChecked()
    local quick = addon.VignetteRadarQuickConfig
    local wasShown = quick.IsShown()
    quick.Refresh()
    if not wasShown then
        quick.OpenPage("Layout")
        quick.Hide()
    end
    return northOption.checked
end
local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.001,
        message .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
for _, name in ipairs({ "classic", "squat", "compact" }) do
    addon.SetVignetteRadarLayout(name)
    checkLayout(false)
    assert(panel.outerRing[1].color[4] < panel.rangeRing[1].color[4],
        "the circle outside the cardinal labels must be the faintest boundary")
    local headingLength = panel.plotRadius * 0.30
    assert(panel.direction.thickness >= 2.5 and panel.direction.color[4] < 0.5
        and headingLength < panel.plotRadius / 2 and headingLength > 9
        and #panel.headingChevron == 2
        and panel.headingChevron[1].thickness >= 2
        and panel.headingChevron[1].color[4] < 0.8,
        "the player heading must show a compact, translucent chevron and line in every panel layout")
    assert(panel.compass.text == "N" and not panel.compass._selected
        and panel.compass.backdrop == nil and panel.compass.glow,
        "the compass must clearly show whether north is locked")
    playerFacing = 0
    addon.VignetteRadarAPI.RefreshPresentation()
    local northX, northY = panel.blipByKey.rare.point[4], panel.blipByKey.rare.point[5]
    playerFacing = math.pi / 2
    addon.VignetteRadarAPI.RefreshPresentation()
    near(panel.blipByKey.rare.point[4], northY, "heading-up must rotate the radar with the player")
    near(panel.direction.endPoint[3], 0, "heading-up player line must point straight up")
    near(panel.direction.endPoint[4], headingLength, "heading-up line must stay short")
    near(panel.direction.startPoint[4], 9, "heading ray must begin at the chevron tip")
    near(panel.headingChevron[1].startPoint[3], -4, "heading-up chevron must hug the dot")
    near(panel.headingChevron[2].startPoint[3], 4, "heading-up chevron must hug the dot")
    near(panel.headingChevron[1].startPoint[4], 4, "heading-up chevron must meet the dot")
    assert(panel.direction:IsShown() and panel.headingChevron[1]:IsShown(),
        "heading-up player cue must stay visible")
    local before = scanCount
    panel.compass.scripts.OnClick(panel.compass)
    assert(settings.vignetteRadarNorthUp and panel.compass._selected and NorthOptionChecked()
        and panel.compass.glow.vertexColor[4] >= .12
        and scanCount == before, "compass click must save north-up and sync options without rescanning")
    local miniX, miniY = launcher.miniBlips[1].point[4], launcher.miniBlips[1].point[5]
    for _, angle in ipairs({ 0, math.pi / 2, math.pi, 3 * math.pi / 2 }) do
        playerFacing = angle
        addon.VignetteRadarAPI.RefreshPresentation()
        near(panel.blipByKey.rare.point[4], northX, "north-up marker horizontal position must stay fixed")
        near(panel.blipByKey.rare.point[5], northY, "north-up marker vertical position must stay fixed")
        near(panel.cardinals[1].point[4], 0, "N must remain above the player in north-up")
        near(panel.cardinals[1].point[5], panel.fieldRadius - 5, "N must remain at the top of the ring")
        near(panel.direction.endPoint[3], -math.sin(angle) * headingLength, "player line must turn toward actual facing")
        near(panel.direction.endPoint[4], math.cos(angle) * headingLength, "player line must turn toward actual facing")
        near(panel.headingChevron[1].endPoint[3], -math.sin(angle) * 9,
            "chevron tip must follow player facing")
        near(panel.headingChevron[1].endPoint[4], math.cos(angle) * 9,
            "chevron tip must follow player facing")
        assert(panel.headingChevron[1]:IsShown() and panel.headingChevron[2]:IsShown(),
            "both sides of the player chevron must stay visible")
        near(launcher.miniBlips[1].point[4], miniX, "launcher must use the same fixed orientation")
        near(launcher.miniBlips[1].point[5], miniY, "launcher must use the same fixed orientation")
        assert(launcher.direction:IsShown(), "north-up launcher needs a player direction cue")
        near(launcher.direction.endPoint[3], -math.sin(angle) * 12, "launcher player line must turn")
    end
    playerFacing = nil
    addon.VignetteRadarAPI.RefreshPresentation()
    assert(not panel.direction:IsShown() and not panel.headingChevron[1]:IsShown()
        and not panel.headingChevron[2]:IsShown() and not launcher.direction:IsShown()
        and not launcher.chevron[1]:IsShown() and panel.blipByKey.rare,
        "unknown facing must hide its direction cue without losing north-up positions")
    playerFacing = 0
    addon.HandleVignetteClick(panel.blipByKey.rare.target, "LeftButton")
    livePositions.rare = { x = 0.53, y = 0.5 }
    addon.VignetteRadarAPI.Refresh(true)
    addon.SetVignetteRadarRange(150)
    for _, angle in ipairs({ 0, math.pi / 2 }) do
        playerFacing = angle
        addon.VignetteRadarAPI.RefreshPresentation()
        assert(panel.edgeArrow:IsShown())
        near(panel.edgeArrow.point[4], 0, "north-up out-of-range direction must remain fixed")
        near(panel.edgeArrow.point[5], panel.plotRadius, "north-up edge arrow must stay at north")
    end
    checkLayout(true)
    panel.compass.scripts.OnClick(panel.compass)
    assert(not settings.vignetteRadarNorthUp and not panel.compass._selected and not NorthOptionChecked(),
        "clicking compass again must restore facing-up and synchronize the checkbox")
    near(panel.edgeArrow.point[4], panel.plotRadius, "restoring facing-up must rotate the focused edge arrow")
    assert(launcher.direction:IsShown() and launcher.chevron[1]:IsShown()
        and launcher.chevron[2]:IsShown(),
        "heading-up launcher must show the same player direction cue as the full radar")
    addon.VignetteRadarTargetPicker.ClearFocus()
    livePositions.rare = { x = 0.507, y = 0.5 }
    addon.SetVignetteRadarRange(450)
    addon.VignetteRadarAPI.Refresh(true)
end
-- The checkbox and toolbar share one saved mode, including in preview.
northOption:SetChecked(true)
northOption.scripts.OnClick(northOption)
assert(panel.compass._selected and settings.vignetteRadarNorthUp)
SlashCmdList.VIGNETTERADAR("preview")
near(panel.cardinals[1].point[4], 0, "preview must honor fixed north")
near(panel.direction.endPoint[3], -math.sin(0.65) * panel.plotRadius * 0.30,
    "preview must demonstrate the short rotating player cue")
near(panel.headingChevron[1].endPoint[3], -math.sin(0.65) * 9,
    "preview must demonstrate the player's rotating chevron")

-- Border dragging uniformly scales the panel and keeps the opposite edge stable.
UIParent:SetSize(800, 600)
local cursorX, cursorY = 400, 300
GetCursorPosition = function() return cursorX, cursorY end
local resizeDirections = {
    { "left", -1, 0 }, { "right", 1, 0 }, { "top", 0, 1 }, { "bottom", 0, -1 },
    { "topLeft", -1, 1 }, { "topRight", 1, 1 },
    { "bottomLeft", -1, -1 }, { "bottomRight", 1, -1 },
}
for _, name in ipairs({ "squat", "compact", "classic" }) do
    settings.vignetteRadarScale = 1
    panel:SetScale(1)
    addon.SetVignetteRadarLayout(name)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
    checkLayout(false)
    for _, direction in ipairs(resizeDirections) do
        local key, horizontal, vertical = direction[1], direction[2], direction[3]
        local grip = assert(panel.resizeGrips[key])
        panel:SetScale(1)
        settings.vignetteRadarScale = 1
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
        cursorX, cursorY = 400, 300
        local left, top = panel:GetLeft(), panel:GetTop()
        local right, bottom = left + panel.width, top - panel.height
        grip.scripts.OnDragStart(grip)
        assert(grip.resize and grip.scripts.OnUpdate, "every edge and corner must start a resize gesture")
        cursorX, cursorY = cursorX + horizontal * 24, cursorY + vertical * 24
        grip.scripts.OnUpdate(grip)
        assert(panel:GetScale() > 1 and panel:GetScale() < 1.3, "outward edge dragging must grow the full panel")
        if horizontal < 0 then near((panel:GetLeft() + panel.width) * panel:GetScale(), right,
            name .. " " .. key .. " resize must hold the right edge") end
        if horizontal > 0 then near(panel:GetLeft() * panel:GetScale(), left,
            "right resize must hold the left edge") end
        if vertical > 0 then near(panel:GetBottom() * panel:GetScale(), bottom,
            "top resize must hold the bottom edge") end
        if vertical < 0 then near(panel:GetTop() * panel:GetScale(), top,
            "bottom resize must hold the top edge") end
        local x, panelTop = panel:GetLeft() * panel:GetScale(), panel:GetTop() * panel:GetScale()
        assert(x >= 4 and x + panel.width * panel:GetScale() <= 796
            and panelTop <= 596 and panelTop - panel.height * panel:GetScale() >= 4,
            "resizing must keep all layout states inside an 800x600 screen")
        grip.scripts.OnDragStop(grip)
        assert(grip.scripts.OnUpdate == nil and settings.vignetteRadarScale == panel:GetScale(),
            "stopping a drag must save the scale and stop updating")
        checkLayout(false)
    end
end
local rightGrip = panel.resizeGrips.right
panel:SetScale(1)
cursorX, cursorY = 400, 300
rightGrip.scripts.OnDragStart(rightGrip)
cursorX = cursorX + 1000
rightGrip.scripts.OnUpdate(rightGrip)
assert(panel:GetScale() <= 1.8 and (panel:GetLeft() + panel.width) * panel:GetScale() <= 796,
    "oversized drags must stop before the panel clips off screen")
rightGrip.scripts.OnDragStop(rightGrip)
local savedScale = settings.vignetteRadarScale
addon.SetVignetteRadarLayout("squat")
assert(settings.vignetteRadarScale == savedScale
    and math.abs(panel:GetScale() - math.min(savedScale, (800 - 274) / panel.width)) < 0.001,
    "saved size must survive layout changes while a narrow screen temporarily limits Squat")
addon.SetVignetteRadarLayout("classic")
assert(panel:GetScale() == savedScale, "roomier layouts must restore the requested size")
addon.SetVignetteRadarLayout("squat")
panel:SetScale(1)
settings.vignetteRadarScale = 1
panel:ClearAllPoints()
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
cursorX, cursorY = 400, 300
rightGrip = panel.resizeGrips.right
rightGrip.scripts.OnDragStart(rightGrip)
cursorX = cursorX + 1000
rightGrip.scripts.OnUpdate(rightGrip)
assert(panel:GetScale() <= (800 - 274) / panel.width,
    "Squat resizing must leave room for the target picker on an 800px screen")
rightGrip.scripts.OnDragStop(rightGrip)
panel.target.scripts.OnClick(panel.target, "LeftButton")
assert(targetPanel:IsShown() and targetPanel.point[1] == "TOPLEFT"
    and (panel:GetLeft() + panel.width) * panel:GetScale() + 8 + targetPanel.width <= 796,
    "the target picker must remain beside a scaled Squat panel with an outer screen gutter")
addon.VignetteRadarTargetPicker.Hide()
panel:SetScale(1)
settings.vignetteRadarScale = 1
UIParent:SetSize(1600, 900)
mapID, guids, now = 781, {}, 500
SlashCmdList.VIGNETTERADAR("on")
addon.SetVignetteRadarLayout("squat")
assert(panel:IsShown() and not panel.focusReadout:IsShown()
    and panel.layoutHint:IsShown() and panel.sideCaption.text == "NO DETECTIONS"
    and panel.sideGuide.text == "MOVE OR CHECK THE MAP",
    "Squat needs an understandable empty state when no vignette is available")

-- Quest dots follow the chosen orientation, while Blizzard's native blob is
-- aligned and clipped only when north is fixed at the top.
local originalWorldPosition = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = function(_, position)
    return 42, { x = (0.5 - position.y) * 1000, y = (0.5 - position.x) * 1000 }
end
local completedQuestIDs = {}
C_QuestLog = {
    GetQuestsOnMap = function() return { { questID = 12345, x = 0.52, y = 0.5, name = "Nearby quest" } } end,
    IsComplete = function(questID) return completedQuestIDs[questID] == true end,
    GetTitleForQuestID = function() return "Nearby quest" end,
    GetQuestObjectives = function() return {
        { finished = false, text = "Collect supplies: 1/3" },
        { finished = true, text = "Find the camp: 1/1" },
    } end,
}
settings.vignetteRadarQuestDots = true
settings.vignetteRadarQuestAreas = true
settings.vignetteRadarNorthUp = false
GetPlayerFacing = function() return 0 end
addon.VignetteRadarAPI.Refresh(true)
local questDot = assert(panel.questDots[1], "quest locations must create a distinct dot")
assert(questDot.halo and questDot.halo:IsShown() and questDot.halo.parent == panel.questClip
    and questDot.halo.level < questDot.level and questDot.halo:GetWidth() == 20
    and questDot.rim.texture == "Interface\\AddOns\\Magpie\\Media\\quest-diamond-hollow.tga"
    and math.abs(questDot.rim.width - 13 * 26 / 30) < .001
    and questDot.fill:IsShown()
    and questDot.fill.vertexColor[1] < .25,
    "quest dots should get a subtle clipped location circle behind the dot")
completedQuestIDs[12345] = true
for _, object in ipairs(objects) do
    if object.events and object.events.QUEST_LOG_UPDATE then
        object.scripts.OnEvent(object, "QUEST_LOG_UPDATE")
        break
    end
end
assert(questDot.quest.completed and questDot.rim.atlas == "QuestTurnin"
    and questDot.rim.vertexColor[1] == 1 and not questDot.fill:IsShown()
    and questDot.number.text == "",
    "a quest ready to turn in must use Blizzard's turn-in icon")
completedQuestIDs[12345] = nil
for _, object in ipairs(objects) do
    if object.events and object.events.QUEST_LOG_UPDATE then
        object.scripts.OnEvent(object, "QUEST_LOG_UPDATE")
        break
    end
end
assert(not questDot.quest.completed and questDot.fill:IsShown()
    and questDot.fill.vertexColor[1] < .25,
    "an unfinished quest must return to a hollow diamond")
questDot.scripts.OnEnter(questDot)
assert(GameTooltip.text == "Nearby quest"
    and table.concat(GameTooltip.lines, " | "):find("1/3 Collect supplies", 1, true)
    and not table.concat(GameTooltip.lines, " | "):find("Find the camp", 1, true),
    "quest dots must name the quest and show its next unfinished objective")
assert(#GameTooltip.lines <= 3
    and not table.concat(GameTooltip.lines, " | "):find("Blizzard quest map point", 1, true),
    "quest-dot tooltips must stay brief and leave map-source explanations to the legend")
questDot.scripts.OnLeave(questDot)
assert(questDot:IsShown() and questDot.quest.questID == 12345 and questDot.point[4] > 0
    and panel.summary.text == "1 QUEST IN RANGE", "quest dots should show live positions and a readable count")
assert(panel.questBlob and not panel.questBlob:IsShown(), "exact blobs must wait for north-up mode")
assert(panel.squarePlot and panel.field.background.texture == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga",
    "enabling quest areas must select a stable square surface even before blobs are available")
local savedQuestCursor, savedFieldLeft, savedFieldTop = GetCursorPosition, panel.field.left, panel.field.top
panel.field.left, panel.field.top = 0, panel.field:GetHeight()
GetCursorPosition = function()
    return panel.field:GetWidth() / 2 + questDot.screenX,
        panel.field:GetHeight() / 2 + questDot.screenY
end
settings.vignetteRadarQuestDots = false
addon.VignetteRadarAPI.Refresh(false)
panel.field.hovered = true
panel.scripts.OnUpdate(panel, .16)
assert(not questDot:IsShown() and questDot.halo:IsShown()
    and GameTooltip:IsShown() and GameTooltip:GetOwner() == panel.field
    and table.concat(GameTooltip.lines, " | "):find("Estimated Area", 1, true),
    "an unselected quest must show a usable estimated area even with diamonds hidden")
panel.field.scripts.OnMouseUp(panel.field, "LeftButton")
assert(addon.VignetteRadarExploration.GetFocusedQuest() == 12345,
    "clicking an estimated area should spotlight that quest")
panel.field.scripts.OnMouseUp(panel.field, "LeftButton")
assert(addon.VignetteRadarExploration.GetFocusedQuest() == nil,
    "clicking the estimated area again should clear its spotlight")
settings.vignetteRadarQuestDots = true
addon.VignetteRadarAPI.Refresh(false)
panel.field.hovered = false
GameTooltip:Hide()
GetCursorPosition = savedQuestCursor
panel.field.left, panel.field.top = savedFieldLeft, savedFieldTop
settings.vignetteRadarFollowTrackedQuest = true
C_SuperTrack.GetSuperTrackedQuestID = function() return 12345 end
addon.VignetteRadarAPI.Refresh(true)
assert(addon.VignetteRadarExploration.GetFocusedQuest() == nil
    and questDot.rim.vertexColor[1] > .9,
    "Blizzard's tracked quest may gain a bright outline but must not auto-spotlight")
settings.vignetteRadarFollowTrackedQuest = false
addon.VignetteRadarExploration.SetQuestFocus(nil)
C_SuperTrack.GetSuperTrackedQuestID = nil
GetPlayerFacing = function() return math.pi / 2 end
addon.VignetteRadarAPI.Refresh(false)
assert(questDot.point[5] < 0, "quest dots should turn with the facing-up radar")
addon.SetVignetteRadarNorthUp(true)
assert(questDot.point[4] > 0 and math.abs(questDot.point[5]) < 0.001,
    "quest dots must return to their fixed map position in north-up mode")
assert(questDot.halo.point[4] == questDot.point[4] and questDot.halo.point[5] == questDot.point[5],
    "estimated circles must follow quest dots in either orientation")
settings.vignetteRadarQuestHaloRadius = 80
addon.VignetteRadarAPI.Refresh(false)
assert(questDot.halo:GetWidth() > 20, "the radius setting must change the rendered circle")
settings.vignetteRadarQuestHaloRadius = 10
settings.vignetteRadarQuestHalos = false
addon.VignetteRadarAPI.Refresh(false)
assert(not questDot.halo:IsShown() and questDot:IsShown(),
    "turning off estimates should keep the quest dot and native area")
settings.vignetteRadarQuestHalos = true
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questClip.clipsChildren and panel.questBlob:IsShown() and panel.questBlob.mapID == 781
    and panel.questBlob.drawnQuests[1] == 12345 and panel.questBlob.fillAlpha < 128
    and panel.questBlob.level < questDot.level,
    "native quest shapes must be translucent, clipped, and behind markers")
C_TaskQuest = { GetQuestsOnMap = function() return {
    { questID = 12347, x = .54, y = .5, name = "World task" },
    { questID = 12348, x = .56, y = .5, name = "Bonus task" },
} end }
C_QuestLog.IsWorldQuest = function(questID) return questID == 12347 end
addon.VignetteRadarAPI.Refresh(true)
assert(panel.questDots[2]:IsShown() and panel.questDots[2].quest.taskType == "world"
    and panel.questDots[3]:IsShown() and panel.questDots[3].quest.taskType == "bonus"
    and panel.questDots[2].halo.fill.vertexColor[1]
        ~= panel.questDots[3].halo.fill.vertexColor[1]
    and #panel.questBlob.drawnQuests == 3,
    "World Quests and bonus objectives need distinct task markers and native blobs")
C_TaskQuest, C_QuestLog.IsWorldQuest = nil, nil
addon.VignetteRadarAPI.Refresh(true)
local oneQuest = C_QuestLog.GetQuestsOnMap
C_QuestLog.GetQuestsOnMap = function() return {
    { questID = 12345, x = .52, y = .5, name = "Nearby quest" },
    { questID = 12345, x = .48, y = .5, name = "Nearby quest" },
    { questID = 12345, x = .52, y = .5, name = "Nearby quest" },
} end
addon.VignetteRadarAPI.Refresh(true)
assert(panel.questDots[2] and panel.questDots[2]:IsShown()
    and panel.questDots[2].quest.questID == 12345
    and panel.questDots[2].quest.colorSlot == questDot.quest.colorSlot
    and (not panel.questDots[3] or not panel.questDots[3]:IsShown())
    and panel.summary.text == "1 QUEST IN RANGE"
    and #panel.questBlob.drawnQuests == 1,
    "separate objectives of one quest need separate dots but one quest count and blob")
C_QuestLog.GetQuestsOnMap = function() return nil end
C_QuestLog.GetNumQuestWatches = function() return 1 end
C_QuestLog.GetQuestIDForQuestWatchIndex = function() return 12345 end
C_QuestLog.GetNextWaypointForMap = function() return .53, .5 end
addon.VignetteRadarAPI.Refresh(true)
assert(panel.questDots[1]:IsShown() and panel.questDots[1].quest.mapX == .53
    and (not panel.questDots[2] or not panel.questDots[2]:IsShown())
    and panel.questBlob:IsShown(),
    "a watched quest with only an objective waypoint must remain visible")
C_QuestLog.GetNumQuestWatches = nil
C_QuestLog.GetQuestIDForQuestWatchIndex = nil
C_QuestLog.GetNextWaypointForMap = nil
C_QuestLog.GetQuestsOnMap = function() return {
    { questID = 12345, x = .52, y = .5, name = "Nearby quest" },
    { questID = 12346, x = .49, y = .5, name = "Second quest" },
} end
addon.VignetteRadarAPI.Refresh(true)
local secondQuestDot = assert(panel.questDots[2], "a second quest needs a second diamond")
settings.vignetteRadarQuestNumbers = true
now = now + 1
addon.VignetteRadarAPI.Refresh(false)
assert(secondQuestDot:IsShown() and secondQuestDot.fill.vertexColor[1] ~= questDot.fill.vertexColor[1]
    and secondQuestDot.halo.fill.vertexColor[1] == questDot.halo.fill.vertexColor[1]
    and secondQuestDot.halo.fill.vertexColor[3] > secondQuestDot.halo.fill.vertexColor[1]
    and panel.questBlob.drawnQuests[1] == 12345
    and panel.questBlob.drawnQuests[2] == 12346
    and panel.questBlob.fillTexture == "Interface\\WorldMap\\UI-QuestBlob-Inside"
    and panel.questBlob.borderAlpha == 0,
    "distinct quest diamonds must share the original blue quest-area renderer")
assert(panel.clearToggle and panel.clearToggle.label:GetText() == "C",
    "the radar must expose the center-clear mode with a matching toolbar control")
panel.clearToggle.scripts.OnClick(panel.clearToggle)
assert(settings.vignetteRadarKeepCenterClear and panel.clearToggle._selected,
    "the center-clear control must retain its selected setting")
clearRange = settings.vignetteRadarRange
clearRadius = clearRange * math.min(32, panel.plotRadius * .38) / panel.plotRadius
assert(not addon.KeepCenterMarker("quest", 12345, clearRadius - 1, clearRange)
    and addon.KeepCenterMarker("quest", 12345, clearRadius + 1, clearRange)
    and not addon.KeepCenterMarker("quest", 12345, clearRadius * 2 - 1, clearRange * 2),
    "the near-marker yard cutoff must scale with radar zoom")
addon.VignetteRadarExploration.SetQuestFocus(12345)
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questDots[1]:IsShown() and panel.questDots[1].quest.questID == 12345
    and (not panel.questDots[2] or not panel.questDots[2]:IsShown())
    and panel.questBlob.drawnQuests[1] == 12345
    and not panel.questBlob.drawnQuests[2],
    "a focused quest must keep only its diamond and native area visible")
addon.VignetteRadarExploration.SetQuestFocus(nil)
panel.clearToggle.scripts.OnClick(panel.clearToggle)
assert(not settings.vignetteRadarKeepCenterClear
    and panel.questDots[2]:IsShown() and panel.questBlob.drawnQuests[2] == 12346,
    "turning center-clear off must restore the other quests immediately")
local regularQuestFill = panel.questBlob.fillAlpha
local regularQuestRange = settings.vignetteRadarRange
settings.vignetteRadarRange = 50
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob:IsShown() and panel.questBlob.fillAlpha < regularQuestFill
    and questDot.halo.fill.vertexColor[4] < .16,
    "close zoom must soften both exact and estimated blue quest areas")
settings.vignetteRadarRange = 10
local regularPlotRadius = panel.plotRadius
panel.plotRadius = 150
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob:IsShown() and panel.questBlob:GetScale() > 1
    and panel.questBlob:GetWidth() <= 4096 and panel.questBlob:GetHeight() <= 4096
    and panel.questBlob.fillAlpha >= 26 and panel.questBlob.fillAlpha < regularQuestFill,
    "minimum zoom must retain the exact area without an oversized native canvas")
local scaledCanvas = panel.questBlob
assert(math.abs(scaledCanvas:GetWidth() * scaledCanvas:GetScale()
    - 1000 * panel.plotRadius / 10) < .01,
    "the bounded quest canvas must preserve its full map projection")
local closeCursor, closeLeft, closeTop = GetCursorPosition, panel.field.left, panel.field.top
panel.field.left, panel.field.top = 0, panel.field:GetHeight()
panel.questBlob.hoverQuestID = 12345
GetCursorPosition = function() return panel.field:GetWidth() / 2, panel.field:GetHeight() / 2 end
panel.field.hovered = true
panel.scripts.OnUpdate(panel, .16)
assert(GameTooltip:IsShown() and GameTooltip.text == "Nearby quest",
    "the exact quest tooltip must stay aligned with the scaled close-zoom canvas")
GetCursorPosition = closeCursor
panel.field.left, panel.field.top = closeLeft, closeTop
panel.questBlob.hoverQuestID = nil
panel.field.hovered = false
GameTooltip:Hide()
panel.plotRadius = regularPlotRadius
settings.vignetteRadarRange = regularQuestRange
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob:GetScale() == 1 and panel.questBlob.fillAlpha == regularQuestFill
    and panel.questBlob.borderAlpha == 0,
    "normal zoom must restore the original quest area opacity and canvas scale")
local beforeQuestKeyLeft = panel:GetLeft()
panel.legend.scripts.OnClick(panel.legend, "RightButton")
local questKey = assert(_G.VignetteRadarQuestLegendPanel)
assert(questKey:IsShown() and questKey.point[1] == "TOPRIGHT"
    and questKey.point[3] == "TOPLEFT" and questKey.count.text == "2 IN RANGE",
    "the quest key must open from the radar's left side with nearby quests")
for index = 1, 2 do
    local row = questKey.rows[index]
    local dot = row.entry.questID == questDot.quest.questID and questDot or secondQuestDot
    assert(row.name.text == dot.quest.name
        and row.number.text == dot.number.text
        and row.number.text == tostring(dot.quest.colorSlot)
        and row.fill.texture == dot.fill.texture
        and row.fill.vertexColor[1] == dot.fill.vertexColor[1]
        and row.fill.vertexColor[2] == dot.fill.vertexColor[2]
        and row.fill.vertexColor[3] == dot.fill.vertexColor[3],
        "quest key diamonds and names must match the actual radar markers")
end
questKey.rows[1].scripts.OnClick(questKey.rows[1])
assert(addon.VignetteRadarExploration.GetFocusedQuest() == questKey.rows[1].entry.questID,
    "clicking a quest key row must spotlight that quest")
questKey.rows[1].scripts.OnClick(questKey.rows[1])
assert(addon.VignetteRadarExploration.GetFocusedQuest() == nil,
    "clicking the key row again must clear its spotlight")
questKey.close.scripts.OnClick(questKey.close)
settings.vignetteRadarQuestNumbers = false
settings.vignetteRadarNextQuestStep = true
C_QuestLog.GetNextWaypointForMap = function(questID, requestedMap)
    if questID == 12345 and requestedMap == 781 then return .54, .5 end
end
C_QuestLog.GetNextWaypointText = function() return "Travel to the camp" end
addon.VignetteRadarAPI.Refresh(true)
assert(panel.questDots[1].quest.mapX == .54
    and panel.questDots[1].quest.nextStep.text == "Travel to the camp",
    "opt-in next-step mode must move only a quest with a current-map Blizzard waypoint")
settings.vignetteRadarNextQuestStep = false
C_QuestLog.GetNextWaypointForMap = nil
C_QuestLog.GetNextWaypointText = nil
C_QuestLine = {
    RequestQuestLinesForMap = function() end,
    GetAvailableQuestLines = function() return { {
        questID = 90001, questLineID = 90002, x = .53, y = .5,
        questName = "New beginning", questLineName = "Campaign path",
        isQuestStart = true, isHidden = false, isCampaign = true,
        floorLocation = 0, startMapID = 781,
    } } end,
}
settings.vignetteRadarQuestStartBadges = true
addon.VignetteRadarQuestData.Invalidate()
addon.VignetteRadarAPI.Refresh(true)
assert(panel.questStartDots[1] and panel.questStartDots[1]:IsShown()
    and panel.questStartDots[1].entry.floor == "above",
    "available quest-line starts need a distinct projected badge and floor hint")
do
    local oldMinimap, oldCompleted = C_Minimap, C_QuestLog.IsQuestFlaggedCompletedOnAccount
    C_Minimap = { IsTrackingAccountCompletedQuests = function() return false end }
    C_QuestLog.IsQuestFlaggedCompletedOnAccount = function(id) return id == 90001 end
    addon.VignetteRadarAPI.Refresh(true)
    assert(not panel.questStartDots[1]:IsShown()
        and #addon.VignetteRadarAvailableStarts == 0,
        "warband-completed starts must disappear from the radar when Blizzard tracking is off")
    C_Minimap.IsTrackingAccountCompletedQuests = function() return true end
    addon.VignetteRadarAPI.Refresh(true)
    assert(panel.questStartDots[1]:IsShown()
        and #addon.VignetteRadarAvailableStarts == 1,
        "turning warband tracking on must restore the start without a reload")
    panel.questStartDots[1].scripts.OnEnter(panel.questStartDots[1])
    assert(table.concat(GameTooltip.lines, " | "):find("Warband-Completed Quest Start", 1, true),
        "a shown account-completed start must identify itself clearly in the tooltip")
    panel.questStartDots[1].scripts.OnLeave(panel.questStartDots[1])
    C_Minimap, C_QuestLog.IsQuestFlaggedCompletedOnAccount = oldMinimap, oldCompleted
end
settings.vignetteRadarLensEnabled = true
settings.vignetteRadarLensCategory = "rare"
VignetteRadar_HoldLens("down")
assert(addon.VignetteRadarLensActive == "rare"
    and not panel.questDots[1]:IsShown() and panel.summary.text == "RARE LENS",
    "holding the lens key must temporarily hide quest markers")
VignetteRadar_HoldLens("up")
assert(addon.VignetteRadarLensActive == nil and panel.questDots[1]:IsShown(),
    "releasing the lens key must restore the previous radar view")
settings.vignetteRadarLensEnabled = false
settings.vignetteRadarDataStatus = true
addon.VignetteRadarAPI.Refresh(false)
assert(panel.emptyHelp:IsShown()
    and #addon.GetVignetteRadarStatusLines() > 0,
    "data-status help must remain discoverable when quest markers are visible")
settings.vignetteRadarDataStatus = false
settings.vignetteRadarQuestStartBadges = false
C_QuestLine = nil
addon.VignetteRadarAPI.Refresh(true)
addon.VignetteRadarExploration.OpenRouteDraft()
assert(explore.pages.Route:IsShown() and explore.routeDraft and #explore.routeDraft > 0
    and explore.draftRows[1].text ~= "",
    "one-click route draft must show a bounded preview without applying it")
assert(#settings.vignetteRadarRoute == 0,
    "previewing a draft must leave the saved route alone")
assert(addon.VignetteRadarExploration.ApplyRouteDraft(explore.routeDraft)
    and #settings.vignetteRadarRoute == #explore.routeDraft,
    "applying the reviewed draft must replace the route atomically")
addon.VignetteRadarExploration.ClearRoute()
assert(not questKey:IsShown() and panel:GetLeft() == beforeQuestKeyLeft,
    "closing the left key must restore a radar shifted to make room")
addon.VignetteRadarExploration.FocusQuest(12346)
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob.drawnQuests[1] == 12345
    and panel.questBlob.drawnQuests[2] == 12346
    and questDot.halo:IsShown() and questDot.halo.alpha == 1
    and secondQuestDot.selection:IsShown() and not questDot.selection:IsShown()
    and not panel.activeCue:IsShown(),
    "spotlighting one quest must not erase other tracked quests' areas")
addon.VignetteRadarExploration.FocusQuest(nil)
settings.vignetteRadarQuestDots = false
addon.VignetteRadarAPI.Refresh(false)
assert(not questDot:IsShown() and questDot.halo:IsShown()
    and not secondQuestDot:IsShown() and secondQuestDot.halo:IsShown(),
    "quest-area circles must show for all map quests even with diamonds disabled")
settings.vignetteRadarQuestHalos = false
addon.VignetteRadarAPI.Refresh(false)
panel.legend.scripts.OnClick(panel.legend, "RightButton")
assert(questKey:IsShown() and questKey.count.text == "2 IN RANGE",
    "the quest key must name quests with native blobs even when dots and estimates are hidden")
assert((questKey.rows[1].name.text == "Nearby quest" or questKey.rows[2].name.text == "Nearby quest")
    and (questKey.rows[1].name.text == "Second quest" or questKey.rows[2].name.text == "Second quest"),
    "native-only quest key entries must keep both quest names")
questKey.close.scripts.OnClick(questKey.close)
settings.vignetteRadarQuestHalos = true
settings.vignetteRadarQuestDots = true
addon.VignetteRadarAPI.Refresh(false)
settings.vignetteRadarQuestAreaColors = true
addon.VignetteRadarAPI.Refresh(false)
assert(not panel.questColorBlobs and #panel.questBlobSources == 1
    and panel.questBlob.fillTexture == "Interface\\WorldMap\\UI-QuestBlob-Inside"
    and #panel.questBlob.drawnQuests == 2,
    "exact quest shapes must keep Blizzard's blue mesh even when estimated circles are colored")
assert(addon.VignetteRadarQuestColors[1][3] > addon.VignetteRadarQuestColors[1][2]
    and addon.VignetteRadarQuestColors[6][3] > addon.VignetteRadarQuestColors[6][2],
    "quest colors should not turn estimated circles green")
for _, dot in ipairs({ questDot, secondQuestDot }) do
    local color = addon.VignetteRadarQuestColors[dot.quest.colorSlot]
    assert(dot.halo.fill.vertexColor[1] == color[1]
        and dot.halo.fill.vertexColor[2] == color[2]
        and dot.halo.fill.vertexColor[3] == color[3],
        "only estimated circles should take their quest diamond's color")
end
settings.vignetteRadarQuestAreaColors = false
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob.fillTexture == "Interface\\WorldMap\\UI-QuestBlob-Inside"
    and #panel.questBlob.drawnQuests == 2
    and math.abs(questDot.halo.fill.vertexColor[1] - .34) < .001
    and math.abs(questDot.halo.fill.vertexColor[2] - .60) < .001
    and math.abs(questDot.halo.fill.vertexColor[3] - 1) < .001,
    "switching estimated colors off must restore blue native and estimated areas")
settings.vignetteRadarQuestColors = false
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob.fillTexture == "Interface\\WorldMap\\UI-QuestBlob-Inside"
    and #panel.questBlob.drawnQuests == 2,
    "turning off diamond colors must leave the shared blue quest area unchanged")
settings.vignetteRadarRange = 50
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob:IsShown() and panel.questBlob.fillAlpha < 48,
    "shared Blizzard quest areas must also fade when zoomed in")
settings.vignetteRadarRange = regularQuestRange
settings.vignetteRadarQuestColors = true
C_QuestLog.GetQuestsOnMap = oneQuest
addon.VignetteRadarAPI.Refresh(true)
assert(not secondQuestDot:IsShown() and not secondQuestDot.halo:IsShown(),
    "removed quests must release both their diamond and estimated circle")
for _, layoutName in ipairs({ "classic", "compact", "squat" }) do
    addon.SetVignetteRadarLayout(layoutName)
    addon.SetVignetteRadarCircleOnly(true)
    panel.field.hovered = true
    panel.field.scripts.OnEnter(panel.field)
    assert(#panel.hoverTools >= 15 and CornerTool("route") == routeHover
        and CornerTool("arrow").reference == panel.arrowToggle
        and CornerTool("clear").reference == panel.clearToggle
        and panel.hoverTools[#panel.hoverTools].toolID == "minimize"
        and panel.hoverTools[#panel.hoverTools].artColumn == 14
        and CornerTool("close") == nil
        and panel.hoverTools[1]:IsShown()
        and not panel.settingsDot:IsShown(),
        "square radar-only view must reveal its corner controls on hover")
    assert(panel.hoverTools[1].glow == nil
        and panel.hoverTools[1].art.texture
            == "Interface\\AddOns\\Magpie\\Media\\button-icons.tga"
        and panel.hoverTools[1].iconLayers.plate.texture == panel.hoverTools[1].art.texture
        and panel.zoomIn.glow.texture
            == "Interface\\AddOns\\Magpie\\Media\\control-rounded-square.tga",
        "corner controls must use state artwork instead of a separate glow and glyph stack")
    local configTool = panel.hoverTools[1]
    local normalRow = configTool._artState
    configTool.scripts.OnEnter(configTool)
    assert(configTool._artState == normalRow + 1 and configTool.iconLayers.glow.vertexColor[4] > 0,
        "hover must light the hover glow layer")
    configTool.scripts.OnLeave(configTool)
    assert(configTool._artState == normalRow and configTool.iconLayers.glow.vertexColor[4] == 0,
        "mouse leave must restore the normal look")
    assert(CornerTool("north")._artState >= 2 and CornerTool("north").iconLayers.underline.vertexColor[4] > .9,
        "north-up must show the active mark")
    local side, center = panel.field:GetWidth(), panel.field:GetWidth() / 2
    local occupied = {}
    for _, tool in ipairs(panel.hoverTools) do
        local point, x, y = tool.point[1], tool.point[4], tool.point[5]
        local width, height = tool:GetWidth(), tool:GetHeight()
        local slot = table.concat({ point, x, y }, ":")
        assert(width == 16 and height == 16 and tool.art.width == 18
            and tool.art.height == 18
            and (math.abs(x) == 12 or math.abs(x) == 32)
            and (math.abs(y) == 12 or math.abs(y) == 32)
            and not occupied[slot],
            "hover control " .. tostring(tool.toolID) .. " must share the aligned corner grid")
        occupied[slot] = true
        local left = point:find("RIGHT") and side + x - width or x
        local top = point:find("BOTTOM") and side - y - height or -y
        local nearestX = math.max(left, math.min(center, left + width))
        local nearestY = math.max(top, math.min(center, top + height))
        local distance = math.sqrt((nearestX-center)^2 + (nearestY-center)^2)
        assert(left >= 9 and top >= 9 and left + width <= side - 9
            and top + height <= side - 9 and distance > panel.plotRadius + 2,
            "hover control " .. tostring(tool.toolID) .. " must stay inside the square border and outside the plotting ring"
                .. " (" .. tostring(left) .. ", " .. tostring(top) .. "; distance " .. tostring(distance) .. ")")
    end
    panel.field.hovered = false
    panel.field.scripts.OnLeave(panel.field)
    assert(not panel.hoverTools[1]:IsShown(), "corner controls must hide after mouse leave")
end
settings.vignetteRadarPeekEnabled = true
VignetteRadar_PeekRadar("down")
assert(panel.title:IsShown() and settings.vignetteRadarCircleOnly,
    "hold-to-peek must expose full controls without changing the saved view")
VignetteRadar_PeekRadar("up")
assert(not panel.title:IsShown() and settings.vignetteRadarCircleOnly,
    "releasing peek must restore the saved radar-only view")
settings.vignetteRadarPeekEnabled = false
VignetteRadar_PeekRadar("down")
assert(not panel.title:IsShown(), "disabled hold-to-peek must leave the view alone")
settings.vignetteRadarPeekEnabled = true
addon.SetVignetteRadarCircleOnly(false)
local originalBlob = panel.questBlob
for _, name in ipairs({ "classic", "compact", "squat" }) do
    addon.SetVignetteRadarLayout(name)
    checkLayout(false)
    local face, clip, toggle = bounds(panel.field.background), bounds(panel.questClip), bounds(panel.frameToggle)
    assert(panel.questBlob == originalBlob and panel.questBlob:IsShown()
        and panel.questBlob.parent == panel.questClip and panel.questClip.clipsChildren,
        "every square layout must preserve the working native blob renderer")
    assert(face[3] - face[1] == panel.fieldRadius * 2 and face[4] - face[2] == panel.fieldRadius * 2
        and clip[1] == face[1] + 4 and clip[2] == face[2] + 4
        and clip[3] == face[3] - 4 and clip[4] == face[4] - 4,
        "native shading must retain the safe inset inside the rounded face")
    assert(toggle[1] >= face[3] + 3 and not panel.field.halo:IsShown() and not panel.outerRing[1]:IsShown(),
        "square mode must leave a clear restore-control gutter and remove the old circular outer rim")
    local corner = (face[3] - face[1]) * .04
    assert(math.sqrt(2) * (corner - 4) <= corner - 1,
        "every native clip corner must stay at least one unit inside the rounded outline")
    local border = assert(panel.squareBorder, "square layouts must create one rounded border texture")
    local borderPoint = assert(border.point, "rounded border texture needs an explicit center anchor")
    local borderBounds, faceBounds = bounds(border), bounds(panel.field.background)
    assert(border.kind == "Texture" and border.parent == panel.field and border.layer == "BORDER"
        and border.texture == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-border.tga"
        and borderPoint[1] == "CENTER" and borderPoint[2] == panel.field
        and borderPoint[3] == "CENTER" and (borderPoint[4] or 0) == 0 and (borderPoint[5] or 0) == 0
        and border.width == panel.field.background.width and border.height == panel.field.background.height
        and borderBounds[1] == faceBounds[1] and borderBounds[2] == faceBounds[2]
        and borderBounds[3] == faceBounds[3] and borderBounds[4] == faceBounds[4]
        and border:IsShown(),
        "the rounded border texture must cover the square face in the BORDER layer in every layout")
    panel:SetScale(.8)
    checkLayout(false)
    panel:SetScale(1)
end
local blobCount = 0
for _, object in ipairs(objects) do
    if object.kind == "QuestPOIFrame" then blobCount = blobCount + 1 end
end
assert(blobCount == 1 and panel.questBlob.fillTexture == "Interface\\WorldMap\\UI-QuestBlob-Inside",
    "exact areas should use one blue widget without allocating colored duplicates")
SlashCmdList.VIGNETTERADAR("preview")
addon.HandleVignetteClick(panel.blipByKey["preview-rare"].target, "LeftButton")
for _, name in ipairs({ "classic", "compact", "squat" }) do
    addon.SetVignetteRadarLayout(name)
    panel:SetScale(.8)
    checkLayout(true)
    inside(panel.field.background, panel, 4)
    inside(panel.questClip, panel.field.background, 4)
    separate(panel.frameToggle, panel.field.background, 3, "square surface/restore control")
    assert(panel.squarePlot and not panel.questBlob:IsShown(),
        "focused previews must keep square geometry without inventing quest blobs")
end
panel:SetScale(1)
addon.HandleVignetteClick(panel.blipByKey["preview-rare"].target, "LeftButton")
SlashCmdList.VIGNETTERADAR("on")
local originalCursor = GetCursorPosition
panel.field.left, panel.field.top = 0, panel.field:GetHeight()
panel.questBlob.left, panel.questBlob.top = 0, panel.field:GetHeight()
panel.questBlob:SetSize(panel.field:GetWidth(), panel.field:GetHeight())
panel.questBlob.hoverQuestID = 12345
GetCursorPosition = function() return panel.field:GetWidth() / 2, panel.field:GetHeight() / 2 end
panel.questBlob.hovered = true
panel.scripts.OnUpdate(panel, .16)
assert(GameTooltip:IsShown() and GameTooltip:GetOwner() == panel.questBlob
    and GameTooltip.text == "Nearby quest" and GameTooltip.line:find("Click to Spotlight", 1, true)
    and table.concat(GameTooltip.lines, " | "):find("1/3 Collect supplies", 1, true),
    "hovering a native quest shape must identify the quest and its unfinished objectives")
panel.questBlob.hovered = false
panel.field.scripts.OnMouseUp(panel.field, "LeftButton")
assert(addon.VignetteRadarExploration.GetFocusedQuest() == 12345,
    "clicking a hovered native blob must spotlight its quest")
panel.field.scripts.OnMouseUp(panel.field, "LeftButton")
assert(addon.VignetteRadarExploration.GetFocusedQuest() == nil,
    "clicking a spotlighted blob again must restore all quest areas")
GetCursorPosition = function() return panel.field:GetWidth() * .8, panel.field:GetHeight() / 2 end
panel.scripts.OnUpdate(panel, .16)
assert(not GameTooltip:IsShown(), "hovering outside the exact quest shape must clear its tooltip")
panel.questBlob.UpdateMouseOverTooltip = function() return 12345 end
for _, sign in ipairs({ -1, 1 }) do
    for _, otherSign in ipairs({ -1, 1 }) do
        -- This point is in the square's corner, beyond the old circular hit area.
        panel.questBlob:SetSize(panel.field:GetWidth(), panel.field:GetHeight())
        GetCursorPosition = function()
            return panel.field:GetWidth() / 2 + sign * (panel.fieldRadius - 5),
                panel.field:GetHeight() / 2 + otherSign * (panel.fieldRadius - 5)
        end
        panel.scripts.OnUpdate(panel, .16)
        assert(GameTooltip:IsShown() and GameTooltip:GetOwner() == panel.questBlob,
            "quest tooltips must work in all four visible square corners")
    end
end
GetCursorPosition = function()
    return panel.field:GetWidth() / 2 + panel.fieldRadius - 3, panel.field:GetHeight() / 2
end
panel.scripts.OnUpdate(panel, .16)
assert(not GameTooltip:IsShown(), "quest tooltip hit testing must stop at the same square edge as shading")
panel.questBlob.UpdateMouseOverTooltip = nil
GetCursorPosition = originalCursor
panel.field.left, panel.field.top = nil, nil
panel.questBlob.left, panel.questBlob.top = nil, nil
panel.frameToggle.scripts.OnClick(panel.frameToggle)
assert(settings.vignetteRadarCircleOnly and panel.questBlob:IsShown() and questDot:IsShown()
    and panel.squarePlot and panel.squareBorder:IsShown() and not panel.frameToggle:IsShown()
    and panel.backdropColor[4] == 0,
    "main radar view must keep square shading while hiding the retired frame control")
panel.frameToggle.scripts.OnClick(panel.frameToggle)
assert(not settings.vignetteRadarCircleOnly and panel.questBlob:IsShown(),
    "restoring the frame must restore available quest-area shading")
settings.vignetteRadarQuestAreas = false
settings.vignetteRadarQuestDots = false
addon.VignetteRadarAPI.Refresh(true)
assert(not questDot:IsShown() and not questDot.halo:IsShown() and not panel.questBlob:IsShown(),
    "each quest overlay must disappear as soon as its option is disabled")
assert(not panel.squarePlot and panel.field.background.texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    and panel.field.halo:IsShown() and panel.outerRing[1]:IsShown() and not panel.squareBorder:IsShown()
    and panel.frameToggle.width == 16 and panel.questBlob == originalBlob,
    "disabling quest areas must restore the original circular face without replacing the blob renderer")
assert(panel.hoverTools[1].art.texture
        == "Interface\\AddOns\\Magpie\\Media\\button-icons.tga"
    and panel.zoomIn.glow.texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    "circular view must restore circular main controls while keeping corner art ready")
settings.vignetteRadarQuestAreas = true
mapID = 782
C_Map.GetWorldPosFromMapPos = originalWorldPosition
addon.VignetteRadarAPI.Refresh(true)
assert(not panel.questBlob:IsShown(),
    "unrotatable native blobs must not appear on maps whose axes disagree with the radar")

-- Map corners can arrive after player and quest positions on the same map.
-- Missing basis data must be retried without requiring another zone change.
local missingQuestCorner = true
C_Map.GetWorldPosFromMapPos = function(_, position)
    if missingQuestCorner and position.x == 0 and position.y == 0 then return nil end
    return 42, { x = (0.5 - position.y) * 1000, y = (0.5 - position.x) * 1000 }
end
settings.vignetteRadarQuestDots = true
mapID, now = 783, 600
addon.VignetteRadarAPI.Refresh(true)
assert(panel.questDots[1]:IsShown() and not panel.questBlob:IsShown(),
    "quest dots must survive a temporarily missing map corner while native shading waits")
missingQuestCorner = false
now = 602
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob:IsShown() and panel.questBlob.mapID == 783,
    "native shading must recover when map corners become available on the same map")

-- DrawBlob may return successfully before Blizzard has loaded shape data.
-- Updates and a slow retry must redraw even when map, size, and IDs stay fixed.
local questEvents
for _, object in ipairs(objects) do
    if object.kind == "Frame" and object.events and object.events.QUEST_POI_UPDATE then
        questEvents = object
        break
    end
end
assert(questEvents and questEvents.events.QUEST_LOG_UPDATE and questEvents.scripts.OnEvent,
    "quest update events must be registered on the radar event frame")
assert(questEvents.events.QUEST_ACCEPTED and questEvents.events.QUEST_REMOVED
    and questEvents.events.QUEST_TURNED_IN and questEvents.events.TASK_PROGRESS_UPDATE
    and questEvents.events.QUEST_WATCH_UPDATE,
    "quest acquisition and turn-in must trigger route refreshes")
local savedDrawNone, savedDrawBlob = panel.questBlob.DrawNone, panel.questBlob.DrawBlob
local drawNoneCount, drawBlobCount, shapeReady, shapeVersion = 0, 0, false, 1
panel.questBlob.DrawNone = function(self)
    drawNoneCount = drawNoneCount + 1
    self.renderedShape = nil
end
panel.questBlob.DrawBlob = function(self, questID)
    drawBlobCount = drawBlobCount + 1
    if shapeReady then self.renderedShape = tostring(questID) .. ":" .. tostring(shapeVersion) end
end
mapID, now = 784, 610
addon.VignetteRadarAPI.Refresh(true)
assert(panel.questBlob:IsShown() and drawBlobCount == 1 and drawNoneCount == 1
    and panel.questBlob.renderedShape == nil,
    "an initially empty native draw may still report success")
shapeReady = true
questEvents.scripts.OnEvent(questEvents, "QUEST_POI_UPDATE")
assert(panel.questBlob.renderedShape == "12345:1" and drawBlobCount == 2 and drawNoneCount == 2,
    "QUEST_POI_UPDATE must redraw late native shape data with unchanged quest IDs")
shapeVersion = 2
questEvents.scripts.OnEvent(questEvents, "QUEST_LOG_UPDATE")
assert(panel.questBlob.renderedShape == "12345:2" and drawBlobCount == 3 and drawNoneCount == 3,
    "QUEST_LOG_UPDATE must redraw changed native geometry with unchanged quest IDs")
local drawCount = drawBlobCount
for _ = 1, 5 do addon.VignetteRadarAPI.Refresh(false) end
assert(drawBlobCount == drawCount,
    "ordinary radar refreshes must not redraw native shapes at frame rate")
shapeVersion = 3
now = 612
addon.VignetteRadarAPI.Refresh(false)
assert(panel.questBlob.renderedShape == "12345:3" and drawBlobCount == drawCount + 1,
    "a slow retry must repair native geometry when a quest update event was missed")
do
    local savedAfter, pendingQuestRefresh = C_Timer.After, {}
    C_Timer.After = function(delay, callback)
        pendingQuestRefresh[#pendingQuestRefresh + 1] = { delay = delay, callback = callback }
    end
    shapeVersion = 4
    questEvents.scripts.OnEvent(questEvents, "QUEST_LOG_UPDATE")
    questEvents.scripts.OnEvent(questEvents, "QUEST_POI_UPDATE")
    assert(#pendingQuestRefresh == 1 and pendingQuestRefresh[1].delay > 0,
        "a burst of quest events should schedule only one deferred scan")
    assert(panel.questBlob.renderedShape == "12345:3",
        "the quest route should wait briefly for Blizzard's new map POIs")
    pendingQuestRefresh[1].callback()
    assert(panel.questBlob.renderedShape == "12345:4",
        "the coalesced quest scan should refresh the latest objective geometry")
    C_Timer.After = savedAfter
end
do
    local savedAfter, pendingScan = C_Timer.After, {}
    C_Timer.After = function(delay, callback)
        pendingScan[#pendingScan + 1] = { delay = delay, callback = callback }
    end
    local before = scanCount
    for _ = 1, 4 do questEvents.scripts.OnEvent(questEvents, "VIGNETTE_MINIMAP_UPDATED") end
    questEvents.scripts.OnEvent(questEvents, "VIGNETTES_UPDATED")
    assert(#pendingScan == 1 and pendingScan[1].delay == 0 and scanCount == before,
        "a burst of vignette events in one frame must queue a single scan")
    pendingScan[1].callback()
    assert(scanCount == before + 1, "the queued vignette scan must run exactly once")
    questEvents.scripts.OnEvent(questEvents, "VIGNETTE_MINIMAP_UPDATED")
    assert(#pendingScan == 2, "a later vignette event must queue a fresh scan")
    pendingScan[2].callback()
    C_Timer.After = nil
    before = scanCount
    questEvents.scripts.OnEvent(questEvents, "VIGNETTE_MINIMAP_UPDATED")
    assert(scanCount == before + 1, "without C_Timer vignette events must still scan at once")
    C_Timer.After = savedAfter
end
do
    local savedCycle, savedOpenPage = VignetteRadar_CycleWorldFocus, addon.VignetteRadarQuickConfig.OpenPage
    local cycled, openedPage = {}, nil
    VignetteRadar_CycleWorldFocus = function(direction) cycled[#cycled + 1] = direction end
    addon.VignetteRadarQuickConfig.OpenPage = function(name) openedPage = name end
    SlashCmdList.VIGNETTERADAR("focus next")
    SlashCmdList.VIGNETTERADAR("focus previous")
    SlashCmdList.VIGNETTERADAR("focus")
    assert(cycled[1] == 1 and cycled[2] == -1 and openedPage == "World Focus",
        "/vr focus commands must reach World Focus")
    VignetteRadar_CycleWorldFocus, addon.VignetteRadarQuickConfig.OpenPage = savedCycle, savedOpenPage
end
do
    local api = addon.VignetteRadarAPI
    local first = api.GetSelectableTargets()
    assert(api.GetSelectableTargets() == first,
        "selectable targets should be built once per frame")
    api.InvalidateSpatialSnapshot()
    assert(api.GetSelectableTargets() ~= first,
        "a spatial change must rebuild selectable targets in the same frame")
end
shapeVersion = 5
questEvents.scripts.OnEvent(questEvents, "TASK_PROGRESS_UPDATE")
assert(panel.questBlob.renderedShape == "12345:5",
    "World Quest progress must invalidate and redraw native quest areas")
panel.questBlob.DrawNone, panel.questBlob.DrawBlob = savedDrawNone, savedDrawBlob
settings.vignetteRadarQuestDots = false
C_Map.GetWorldPosFromMapPos = originalWorldPosition
settings.vignetteRadarQuestAreas = false
addon.VignetteRadarAPI.Refresh(false)
local savedFieldPoint = panel.field.point
panel.frameToggle.scripts.OnClick(panel.frameToggle)
assert(settings.vignetteRadarCircleOnly == true and panel.backdropColor[4] == 0
    and panel.backdropBorderColor[4] == 0 and not panel.title:IsShown()
    and not panel.combatToggle:IsShown() and not panel.trailToggle:IsShown()
    and not panel.resizeGrips.bottomRight:IsShown()
    and not panel.frameToggle:IsShown() and panel.field.point == savedFieldPoint
    and panel.frameToggle.chevron[1].endPoint[3] > panel.frameToggle.chevron[1].startPoint[3],
    "circle-only view must hide the rectangular frame without moving the radar or its restore chevron")
panel.field.scripts.OnEnter(panel.field)
assert(panel.hoverTools[1]:IsShown() and not panel.squarePlot,
    "a new radar-only circle must still reveal its settings and focus controls on hover")
panel.field.hovered = false
panel.field.scripts.OnLeave(panel.field)
panel.frameToggle.scripts.OnClick(panel.frameToggle)
assert(settings.vignetteRadarCircleOnly == false and panel.backdropColor[4] == .98
    and panel.title:IsShown() and panel.combatToggle:IsShown() and panel.trailToggle:IsShown()
    and panel.resizeGrips.bottomRight:IsShown()
    and panel.frameToggle.chevron[1].endPoint[3] < panel.frameToggle.chevron[1].startPoint[3],
    "the circle control must restore full panel chrome and resize grips")

local originalLayout = panel.layout
for _, layout in ipairs({ "classic", "squat", "compact" }) do
    addon.SetVignetteRadarLayout(layout)
    local framedY = panel.point[5]
    addon.SetVignetteRadarCircleOnly(true)
    assert(panel.clamped == false,
        "radar-only mode must allow its invisible frame to cross the screen edge")
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -1200)
    panel.field.scripts.OnDragStop(panel.field)
    local circleY = panel.point[5]
    local fieldBottom = layout == "squat" and 38 or layout == "compact" and 59 or 35
    local visibleBottom = UIParent:GetHeight() + circleY - (panel.height - fieldBottom) * panel:GetScale()
    assert(visibleBottom >= 4 and visibleBottom < 5
        and panel:GetBottom() < 0 and settings.vignetteRadarCirclePosition,
        "radar-only dragging must stop at the visible face, with the hidden frame below the screen")
    addon.SetVignetteRadarCircleOnly(false)
    assert(panel.clamped == true and panel.point[5] == framedY and panel:GetBottom() >= 4,
        "showing the full UI must restore its earlier, fully visible position")
    addon.SetVignetteRadarCircleOnly(true)
    assert(panel.point[5] == circleY,
        "returning to radar-only mode must restore the separately saved lower position")
    addon.SetVignetteRadarCircleOnly(false)
end
addon.SetVignetteRadarLayout(originalLayout)

-- The compact panel owns every user-facing setting and remains usable at its
-- smallest page bounds. Theme edits must affect the actual radar textures.
addon.SetVignetteRadarNorthUp(false)
SlashCmdList.VIGNETTERADAR("preview")
settings.vignetteRadarBeaconsEnabled = true
addon.VignetteRadarAPI.Refresh(true)
panel.settingsDot.scripts.OnClick(panel.settingsDot)
local quick = assert(addon.VignetteRadarQuickConfig.GetPanel())
local quickAPI = addon.VignetteRadarQuickConfig
local QC = {}
-- Helpers for the schema-driven window: a control's card is its nearest
-- ancestor with isCard; old page names resolve to a page and card.
function QC.ObjectCard(object)
    local node = object
    while node do
        if node.isCard then return node end
        node = node.parent
    end
end
function QC.quickCard(name)
    local page, section = quickAPI.ResolvePage(name)
    return section and quick.cards[page .. "/" .. section] or nil, page, section
end
function QC.quickFind(name, match)
    local card, page = QC.quickCard(name)
    for _, object in ipairs(objects) do
        local owner = match(object) and QC.ObjectCard(object)
        if owner and ((card and owner == card) or (not card and owner.parent == quick.pages[page])) then
            return object
        end
    end
end
local function quickControl(name, key, value)
    return QC.quickFind(name, function(object)
        return object.optionKey == key and (value == nil or object.optionValue == value)
    end)
end
function QC.quickButton(name, text)
    return QC.quickFind(name, function(object) return object.kind == "Button" and object.text == text end)
end
local function quickShowsCard(name)
    local card, page = QC.quickCard(name)
    return quick:IsShown() and quick.selectedPage == page and quick.pages[page]:IsShown()
        and (card == nil or card:IsShown())
end
function QC.quickRow(key, subkey)
    for _, row in ipairs(quick.rows) do
        if row.entry and row.entry.key == key and row.entry.subkey == subkey then return row end
    end
end
function QC.quickSearch(text)
    quick.searchInput:SetText(text)
    quick.searchInput.scripts.OnTextChanged(quick.searchInput)
end
-- Every visible control stays inside its row, every row inside its card and
-- every card inside the scroll view, so nothing clips against a border.
function QC.CheckQuickBounds(label)
    assert(quick.scroll.point[4] + quick.scroll.width <= quick.width - 10
        and quick.content.width == quick.scroll.width, "the settings view must fit inside the window")
    for _, object in ipairs(objects) do
        local row = object.parent
        if row and row.isRow and row:IsShown() and QC.ObjectCard(row) and QC.ObjectCard(row):IsShown()
            and (object.kind == "Button" or object.kind == "CheckButton") and object.point then
            local p = object.point
            assert(p[1] == "TOPLEFT" and p[2] == row, "row controls need explicit row anchors")
            assert(p[4] >= 8 and p[4] + object.width <= row.width - 6
                and -p[5] >= 0 and -p[5] + object.height <= row.height + 1,
                label .. ": control " .. tostring(object.optionKey or object.text)
                    .. " must not clip at " .. tostring(p[4]) .. ", " .. tostring(p[5]))
        end
        if object.isRow and object:IsShown() and object.card and object.card:IsShown() then
            local p, card = object.point, object.card
            assert(p and p[2] == card and p[4] >= 0 and p[4] + object.width <= card.width + .01
                and -p[5] + object.height <= card.height - 4,
                label .. ": row " .. tostring(object.entry and object.entry.id or object.kind)
                    .. " must stay inside its card")
        end
        if object.isCard and object:IsShown() and object.parent and object.parent.parent == quick.content then
            assert(object.point[4] >= 0 and object.point[4] + object.width <= quick.content.width,
                label .. ": card " .. tostring(object.titleText) .. " must fit the view")
        end
    end
end
assert(quick:IsShown() and quick.width == 468 and quick.height == 520
    and #quick.railButtons == 9 and quick.railButtons[1].pageID == "Radar"
    and quick.railButtons[9].pageID == "Tools",
    "the settings dot must open the window with a nine-page icon rail")
do
    local expected = { "Radar", "Looks", "Alerts", "Markers", "Quests", "Routes", "HUD", "Data", "Tools" }
    for index, id in ipairs(expected) do
        local button = quick.railButtons[index]
        assert(quick.pageOrder[index] == id and button.pageID == id
            and button.art.texture:find("button%-icons%.tga$") and button.column == index - 1
            and button.glyphName == "rail_" .. addon.VignetteRadarIconButton.RAIL[index]
            and button.width == 36 and button.point[4] == 10,
            "rail icon " .. id .. " must use its layered rail glyph")
    end
    local radarIcon = quick.railButtons[1]
    assert(radarIcon._selected and radarIcon._artState == 2
        and radarIcon.iconLayers.underline.vertexColor[4] > .9,
        "the selected page icon must show the active mark")
    assert(quick.close.backdrop == nil and quick.close.face.texture == "Interface\\Buttons\\WHITE8X8"
        and quick.close.edge.height == 1, "window buttons need the quiet flat radar artwork")
    -- The window is skinned like the radar face, outlined in the ring color,
    -- through the tray's shared SkinLikeRadar.
    local savedTray, skinned = addon.VignetteRadarTray, nil
    addon.VignetteRadarTray = { SkinLikeRadar = function(frame) skinned = frame end }
    quickAPI.Refresh()
    addon.VignetteRadarTray = savedTray
    assert(skinned == quick and quick.popupFaceSlices and #quick.popupEdgeSlices == 9,
        "the settings window must be painted by Tray.SkinLikeRadar")
    local rr, rg, rb = addon.VignetteRadarStyle.Color("rings")
    local cardFace = quick.cards["Radar/Radar"].faceSlices[5].vertexColor
    assert(math.abs(cardFace[1] - rr) < .001 and math.abs(cardFace[2] - rg) < .001
        and math.abs(cardFace[3] - rb) < .001 and cardFace[4] < .1 and #quick.cards["Radar/Radar"].faceSlices == 9,
        "cards must be a soft ring-colored wash without an outline")
    local ar = addon.VignetteRadarStyle.Color("accent")
    assert(quick.title.textColor[1] == ar and quick.title.text == "Magpie Settings",
        "the window title must use the theme accent")
end
-- Every schema entry has a control, and the old page names still open.
for _, id in ipairs(addon.Schema.order) do
    local entry = addon.Schema.entries[id]
    local found
    for _, row in ipairs(quick.rows) do if row.entry == entry then found = true; break end end
    assert(found, "settings window missing a row for " .. id)
end
for _, name in ipairs({ "Status", "Search", "Beacons", "World Focus", "Auto Route", "Quest Routing",
    "Performance", "Tools", "Routes & Cues", "Themes", "Guides", "Explore", "Wayfinding", "Map Data",
    "Source Fusion", "Zygor", "In-World Marker", "Constellation", "Layout", "Behavior" }) do
    assert(name == "Search" or quick.pages[(quickAPI.ResolvePage(name))],
        "old page name " .. name .. " must map to a new page")
end
settings.vignetteRadarPerformance = "low"
assert(addon.VignetteRadarRenderSeconds() == .25
    and addon.VignetteRadarScanSeconds() == 2.5,
    "Low CPU mode must reduce both redraws and scans")
settings.vignetteRadarPerformance = "balanced"
assert(addon.VignetteRadarRenderSeconds() == .15
    and addon.VignetteRadarScanSeconds() == 1.5,
    "Balanced mode must offer a middle update rate")
settings.vignetteRadarPerformance = "standard"
-- Search filters rows across every page and hides everything else.
QC.quickSearch("update rate")
do
    local performanceRow, enableRow = QC.quickRow("vignetteRadarPerformance"), QC.quickRow("vignetteRadarEnabled")
    assert(performanceRow:IsShown() and performanceRow.card:IsShown() and quick.pages.Tools:IsShown()
        and not quick.pages.Radar:IsShown() and not enableRow:IsShown() and not quick.noResults:IsShown(),
        "settings search must show the matching update-rate row and hide the rest")
    assert(#performanceRow.buttons == 3 and performanceRow.buttons[3].text == "Low CPU",
        "settings search must show each update-rate choice once")
end
QC.quickSearch("arrival")
do
    local count = 0
    for _, row in ipairs(quick.rows) do
        if row:IsShown() and row.card:IsShown() and row.entry then
            count = count + 1
            assert(row.entry.label:lower():find("arrival", 1, true) or row.entry.key:lower():find("arrival", 1, true),
                "search results must only contain matching rows")
        end
    end
    assert(count >= 4 and quick.pages.Routes:IsShown() and not quick.pages.Looks:IsShown(),
        "search must find every route and waypoint arrival option across pages")
end
QC.CheckQuickBounds("search results")
quick.railButtons[1].scripts.OnClick(quick.railButtons[1])
assert(quick.query == "" and quick.searchInput.text == "" and quick.pages.Radar:IsShown()
    and not quick.pages.Routes:IsShown(), "choosing a page must clear the search")
local exposed, colorSlots = {}, {}
-- Every page lays out inside its bounds with Advanced Tools on.
settings.vignetteRadarAdvancedTools = true
addon.InvalidateSettings()
for _, button in ipairs(quick.railButtons) do
    button.scripts.OnClick(button)
    assert(quick.pages[button.pageID]:IsShown() and button._selected, "rail icon must open " .. button.pageID)
    for id, page in pairs(quick.pages) do
        assert(page:IsShown() == (id == button.pageID), "only the selected page may show")
    end
    QC.CheckQuickBounds(button.pageID)
end
do
    local openPlayerTracker = QC.quickButton("Data", "Player Tracker")
    local original, openings = addon.VignetteRadarPlayerTracker, 0
    addon.VignetteRadarPlayerTracker = { Open = function() openings = openings + 1 end }
    assert(openPlayerTracker and QC.ObjectCard(openPlayerTracker) == quick.cards["Data/Planning Tools"],
        "Player Tracker must have a visible Planning Tools action")
    openPlayerTracker.scripts.OnClick()
    assert(openings == 1, "the Planning Tools action must open Player Tracker")
    addon.VignetteRadarPlayerTracker = original
    quickAPI.OpenPage("Data")
    local planning, compass = quick.cards["Data/Planning Tools"], quick.cards["Routes/Sound Compass"]
    assert(planning:IsShown(), "Advanced Tools must show their entry points while the switch is on")
    quickAPI.OpenPage("Routes & Cues")
    assert(compass:IsShown() and quickShowsCard("Routes & Cues"),
        "the old Routes & Cues page must open Sound Compass while Advanced Tools is on")
    settings.vignetteRadarAdvancedTools = false
    addon.InvalidateSettings()
    addon.VignetteRadarQuickConfig.Refresh()
    assert(not compass:IsShown(), "Advanced Tools off must hide Sound Compass")
    quickAPI.OpenPage("Data")
    assert(not planning:IsShown() and quick.cards["Data/Hunting Presets"]:IsShown(),
        "Advanced Tools off must hide Studio, Survey, Atlas, Intelligence and Player Tracker")
    QC.quickSearch("expedition studio")
    assert(quick.noResults:IsShown() and not planning:IsShown(),
        "search must not reveal hidden Advanced Tools")
    QC.quickSearch("sound compass")
    assert(not compass:IsShown(), "search must not reveal hidden Advanced Tools settings")
    QC.quickSearch("")
    settings.vignetteRadarAdvancedTools = true
    addon.InvalidateSettings()
    quickAPI.OpenPage("Radar")
end
quickAPI.OpenPage("Bearing Bar")
local previewBeacons = QC.quickButton("Bearing Bar", "Preview")
assert(quickShowsCard("Bearing Bar") and previewBeacons
    and quickControl("Beacons", "vignetteRadarBeaconMax", 24),
    "multi-point beacons must have a visible card and preview in settings")
previewBeacons.scripts.OnClick(previewBeacons)
assert(previewBeacons.text == "Stop Preview", "the preview button must offer to stop the sample")
local beaconRail = assert(_G.VignetteRadarBeaconRail)
assert(beaconRail:IsShown() and beaconRail.width == 520 and beaconRail.height == 146
    and beaconRail.heading.text == "Bearing Bar",
    "beacon preview must show a bounded movable display")
local previewCards = 0
for _, object in ipairs(objects) do
    if object.parent == beaconRail and object.kind == "Button" and object:IsShown() then
        previewCards = previewCards + 1
        local x, y = object.point[4], object.point[5]
        assert(math.abs(x) + object.width / 2 < beaconRail.width / 2 - 8
            and -y + object.height < beaconRail.height - 4,
            "beacon cards must stay inside the themed display at its smallest size")
    end
end
assert(previewCards == 2, "preview should show both a rare and a quest point")
previewBeacons.scripts.OnClick(previewBeacons)
assert(quickShowsCard("Bearing Bar") and beaconRail:IsShown()
    and beaconRail.summary.text == "1 Quest  ·  Facing",
    "leaving preview must restore real beacon data without a stuck sample: "
        .. tostring(beaconRail.summary.text))
do
    local oldSource, oldTreasure, oldMapVisible = settings.vignetteRadarPOISource,
        settings.vignetteRadarBeaconTreasures, settings.vignetteRadarMapNotesVisible
    local oldSelect = addon.VignetteRadarWorldFocus.SelectNote
    local oldFocused = addon.VignetteRadarWorldFocus.GetFocusedStep
    local selected
    settings.vignetteRadarPOISource = "auto"
    settings.vignetteRadarMapNotesVisible = true
    settings.vignetteRadarBeaconTreasures = true
    settings.vignetteRadarPOITypes.treasure = true
    addon.VignetteRadarWorldFocus.SelectNote = function(note) selected = note; return true end
    addon.VignetteRadarWorldFocus.GetFocusedStep = function()
        return { mapID = 1, worldX = 100, worldY = 0 }
    end
    local first = { kind = "treasure", key = "first", name = "First Chest", mapID = 1,
        mapX = .2, mapY = .2, worldX = 100, worldY = 0 }
    local second = { kind = "treasure", key = "second", name = "Second Chest", mapID = 1,
        mapX = .3, mapY = .2, worldX = 110, worldY = 0 }
    addon.VignetteRadarBeacons.Sync(1, { worldX = 0, worldY = 0 }, {}, {},
        { first, second })
    local grouped
    for _, object in ipairs(objects) do
        if object.parent == beaconRail and object.groupCount == 2 and object:IsShown() then
            grouped = object; break
        end
    end
    assert(grouped and grouped.icon.atlas == "VignetteLoot" and grouped.icon.vertexColor[1] == 1
        and grouped.badge.text == ""
        and grouped.label.text == "First Chest" and grouped.focusLine:IsShown(),
        "treasures need Blizzard's untinted chest icon and an owned-waypoint cue")
    grouped.scripts.OnClick(grouped, "RightButton")
    assert(grouped.label.text == "Second Chest" and grouped.groupIndex == 2,
        "right-click should choose a different point in a crowded bearing")
    grouped.scripts.OnClick(grouped, "LeftButton")
    assert(selected == second, "clicking a saved treasure bearing must focus the selected note")
    local beaconQuest = { questID = 4242, name = "Bearing Quest", mapID = 1,
        mapX = .4, mapY = .4, worldX = -120, worldY = 40 }
    addon.VignetteRadarBeacons.Sync(1, { worldX = 0, worldY = 0 }, {}, { beaconQuest }, {})
    local questCard
    for _, object in ipairs(objects) do
        if object.parent == beaconRail and object.label and object.label.text == "Bearing Quest"
            and object:IsShown() then questCard = object; break end
    end
    assert(questCard, "the quest bearing card must render")
    local exploration = addon.VignetteRadarExploration
    local oldFocusQuest, oldSelectQuest = exploration.FocusQuest,
        addon.VignetteRadarWorldFocus.SelectQuest
    local focusCalls, selectCalls = 0, 0
    exploration.FocusQuest = function(id)
        focusCalls = focusCalls + 1
        addon.VignetteRadarWorldFocus.SelectQuest(id)
    end
    addon.VignetteRadarWorldFocus.SelectQuest = function() selectCalls = selectCalls + 1 end
    questCard.scripts.OnClick(questCard, "LeftButton")
    assert(focusCalls == 1 and selectCalls == 1,
        "a quest bearing click must select its quest once")
    addon.VignetteRadarExploration = nil
    questCard.scripts.OnClick(questCard, "LeftButton")
    addon.VignetteRadarExploration = exploration
    assert(selectCalls == 2, "without Exploration the click must still select the quest")
    exploration.FocusQuest = oldFocusQuest
    addon.VignetteRadarWorldFocus.SelectQuest = oldSelectQuest
    addon.VignetteRadarWorldFocus.SelectNote = oldSelect
    addon.VignetteRadarWorldFocus.GetFocusedStep = oldFocused
    settings.vignetteRadarPOISource, settings.vignetteRadarBeaconTreasures = oldSource, oldTreasure
    settings.vignetteRadarMapNotesVisible = oldMapVisible
end
addon.VignetteRadarBeacons.Sync(1, { worldX = 0, worldY = 0 }, {}, {}, {})
assert(beaconRail:IsShown() and beaconRail.height == 64 and beaconRail.empty:IsShown()
    and beaconRail.scripts.OnUpdate == nil
    and beaconRail.summary.text:find("0 Points in", 1, true),
    "enabled beacons must show a compact explanation when no points are in range")
settings.vignetteRadarBeaconsEnabled = false
addon.VignetteRadarBeacons.Sync(1, { worldX = 0, worldY = 0 }, {}, {}, {})
assert(not beaconRail:IsShown(), "the bearing bar must hide when its opt-in is disabled")
local escapePanels = {}
for _, name in ipairs(UISpecialFrames) do escapePanels[name] = true end
assert(escapePanels.VignetteRadarExplorePanel
    and escapePanels.VignetteRadarQuestLegendPanel
    and escapePanels.VignetteRadarQuickConfigPanel,
    "Escape must close exploration, the quest key, and compact settings")
for _, object in ipairs(objects) do
    if object.optionKey and QC.ObjectCard(object) then exposed[object.optionKey] = true end
    if object.colorSlot and QC.ObjectCard(object) == quick.cards["Looks/Colors"] then colorSlots[object.colorSlot] = true end
end
for _, key in ipairs({ "vignetteRadarEnabled", "vignetteRadarHideWhenEmpty", "vignetteRadarLauncherVisible",
    "vignetteRadarWorldMap", "vignetteRadarRange", "vignetteRadarScale",
    "vignetteRadarNorthUp", "vignetteRadarHoverTools", "vignetteRadarActiveCue",
    "vignetteRadarSourceBadges",
    "vignetteRadarEmptyHelp", "vignetteRadarEdgeCues",
    "vignetteRadarFollowTrackedQuest",
    "vignetteRadarAlerts", "vignetteRadarAlertSound", "vignetteRadarAlertCategories",
    "vignetteRadarAlertCooldown", "vignetteRadarCategories", "vignetteRadarHighlight",
    "vignetteRadarMarkerSize", "vignetteRadarShapes", "vignetteRadarShowHealth",
    "vignetteRadarLastSeen", "vignetteRadarLastSeenSeconds", "vignetteRadarQuietCombat",
    "vignetteRadarKeepVisibleCombat",
    "vignetteRadarQuietInstances", "vignetteRadarQuestDots", "vignetteRadarQuestAreas",
    "vignetteRadarQuestHalos", "vignetteRadarQuestHaloRadius", "vignetteRadarQuestColors",
    "vignetteRadarQuestAreaColors",
    "vignetteRadarNextQuestStep", "vignetteRadarQuestStartBadges",
    "vignetteRadarQuestNumbers", "vignetteRadarDataStatus",
    "vignetteRadarLensEnabled", "vignetteRadarLensCategory",
    "vignetteRadarRingOpacity", "vignetteRadarBorderOpacity", "vignetteRadarRangeLabelOpacity",
    "vignetteRadarChevronOpacity", "vignetteRadarHeadingOpacity",
    "vignetteRadarChevronDistance", "vignetteRadarHeadingLength", "vignetteRadarFullSweep",
    "vignetteRadarTheme", "vignetteRadarSmartZoom", "vignetteRadarUntangle",
    "vignetteRadarTrailMode", "vignetteRadarLeadNextStops", "vignetteRadarTrailStyle", "vignetteRadarApproachAlerts",
    "vignetteRadarJournalEnabled", "vignetteRadarApproachDistance",
    "vignetteRadarPOISource", "vignetteRadarPOITypes", "vignetteRadarPOIIcons",
    "vignetteRadarHideCleared", "vignetteRadarWorldFocusEnabled",
    "vignetteRadarWorldFocusAutoAdvance", "vignetteRadarWorldFocusRoutes",
    "vignetteRadarWorldFocusSavedNotes", "vignetteRadarWorldFocusZygor",
    "vignetteRadarWorldFocusArrivalRadius",
    "vignetteRadarAutoRouteNearbyZones", "vignetteRadarAutoRouteQuestStarts",
    "vignetteRadarAutoRouteQuestNearest" }) do
    assert(exposed[key], "compact settings missing: " .. key)
end
for _, slot in ipairs(addon.VignetteRadarStyle.slots) do
    assert(colorSlots[slot], "theme missing color slot: " .. slot)
end
quickAPI.OpenPage("Quest Routing")
assert(quickShowsCard("Quest Routing")
    and quickControl("Quest Routing", "vignetteRadarAutoRouteNearbyZones").checked
    and quickControl("Quest Routing", "vignetteRadarAutoRouteQuestStarts").checked
    and quickControl("Quest Routing", "vignetteRadarAutoRouteQuestNearest").checked,
    "all new quest routing choices should be enabled and visible by default")
do
    quickAPI.OpenPage("World Focus")
    assert(quickShowsCard("World Focus") and quickControl("World Focus", "vignetteRadarWorldFocusEnabled")
        and quick.focusStatus, "World Focus must open as a card on the Routes page")
    quickAPI.OpenPage("Zygor")
    assert(quickShowsCard("Zygor")
        and quickControl("Zygor", "vignetteRadarWorldFocusZygor")
        and quickControl("Zygor", "vignetteRadarFollowZygor")
        and quickControl("Zygor", "vignetteRadarZygorMode", "travel"),
        "the Zygor card must hold follow and destination controls")
    local bridge = addon.VignetteRadarZygor
    local routeAPI = addon.VignetteRadarAPI
    local originalBindZygor = routeAPI.BindZygorGuide
    routeAPI.BindZygorGuide = function() return true end
    local originalPinZygor, pinZygorCalled = bridge.Pin, false
    bridge.Pin = function(mode)
        pinZygorCalled = mode == "objective"
        return true
    end
    local pinObjective = assert(QC.quickButton("Zygor", "Pin Objective"))
    pinObjective.scripts.OnClick()
    assert(pinZygorCalled, "the Zygor card must pin the active objective")
    bridge.Pin = function()
        return false, "Zygor has no active guide waypoint"
    end
    pinObjective.scripts.OnClick()
    assert(quick.zygorStatus.text == "Zygor has no active guide waypoint",
        "the settings action must show a persistent explanation when pinning fails")
    bridge.Pin = originalPinZygor
    routeAPI.BindZygorGuide = originalBindZygor
end
quickAPI.OpenPage("Explore")
assert(quickShowsCard("Explore") and quickControl("Explore", "vignetteRadarTrailMode", "follow")
    and quickControl("Explore", "vignetteRadarTrailMode", "lead")
    and quickControl("Explore", "vignetteRadarLeadNextStops")
    and quickControl("Explore", "vignetteRadarTrailStyle").text == "Trail Styles & Flow",
    "the Exploring card must expose the trail and its complete picker")
do
    local range = QC.quickRow("vignetteRadarRange")
    assert(range.kind == "stepper" and range.minus.backdrop == nil and #range.minus.strokes == 1
        and range.plus.backdrop == nil and #range.plus.strokes == 2
        and quickControl("Layout", "vignetteRadarNorthUp").glyph.label
        and #quickControl("Behavior", "vignetteRadarKeepVisibleCombat").glyph.lines == 4,
        "range, north, and visibility controls must match the radar glyphs")
    range.plus.scripts.OnClick(range.plus)
    assert(settings.vignetteRadarRange == 600 and range.value.text == "600 yd",
        "the range stepper must apply live through the schema")
    range.minus.scripts.OnClick(range.minus)
    assert(settings.vignetteRadarRange == 450, "the range stepper must step back down")
end
-- The content scrolls with the wheel and moves its thumb.
quickAPI.OpenPage("Markers")
assert(quick.contentHeight > quick.scroll.height, "the Markers page must be taller than the view")
quick.scroll.scripts.OnMouseWheel(quick.scroll, -1)
assert(quick.scrollOffset == 48 and quick.scroll:GetVerticalScroll() == 48 and quick.thumb:IsShown()
    and quick.thumb.point[5] < -48, "wheel scrolling must move the page and its thumb")
for _ = 1, 40 do quick.scroll.scripts.OnMouseWheel(quick.scroll, -1) end
assert(quick.scrollOffset == quick.contentHeight - quick.scroll.height, "scrolling must stop at the last card")
quickAPI.OpenPage("Themes")
assert(quickShowsCard("Themes") and not quick.pages.Radar:IsShown() and quick.scrollOffset == 0)
local style = addon.VignetteRadarStyle
do
    local row, picker = quick.themeRow, quick.themePicker
    local each = math.floor((row.width - 20 - 16) / 5)
    local count = #style.order
    assert(picker.view.kind == "single" and picker.singleTab.highlightLocked
        and row.height == 48 + math.ceil(count / 5) * 24 + 2 + 25,
        "the picker opens on Single Color with every palette in a five-column grid, then Customize")
    for index, name in ipairs(style.order) do
        local choice = assert(quick.themeChoices[name])
        local p = choice.point
        assert(choice.parent == row and choice.width == each and choice:IsShown()
            and p[4] == 10 + ((index - 1) % 5) * (each + 4)
            and p[4] + choice.width <= row.width - 8
            and -p[5] == 48 + math.floor((index - 1) / 5) * 24,
            "each single palette needs a grid cell inside the card")
    end
    assert(quick.themeChoices.verdant._selected == true and not quick.themeChoices.ember._selected
        and not quick.themeChoices.verdant.mark,
        "the selected theme uses the underline selection, never a full frame")
    -- Drill in: Multi-Color, then a family, then a variant.
    picker.multiTab.scripts.OnClick(picker.multiTab)
    assert(picker.view.kind == "multi" and not picker.view.family and picker.multiTab.highlightLocked
        and not quick.themeChoices.verdant:IsShown() and quick.themeChoices.verdant.point == nil,
        "Multi-Color lists families and drops the single grid")
    local family = assert(picker.families.catppuccin)
    assert(family:IsShown() and #family.strip == 7, "families show a palette strip")
    family.scripts.OnEnter(family)
    assert(picker.trail.text == "Multi-Color > Catppuccin", "hovering a family names it in the trail")
    family.scripts.OnLeave(family)
    family.scripts.OnClick(family)
    local macchiato = assert(quick.themeChoices.catppuccin_macchiato)
    assert(picker.view.family == "catppuccin" and picker.back:IsShown() and macchiato:IsShown()
        and macchiato.optionValue == "catppuccin_macchiato", "a family opens its variants")
    macchiato.scripts.OnEnter(macchiato)
    local mr, mg, mb = style.PresetColor("catppuccin_macchiato", "rare")
    assert(picker.swatches[5].color[1] == mr and picker.swatches[5].color[2] == mg
        and picker.trail.text == "Multi-Color > Catppuccin > Macchiato", "hover previews the variant's roles")
    macchiato.scripts.OnLeave(macchiato)
    macchiato.scripts.OnClick(macchiato)
    assert(settings.vignetteRadarTheme == "catppuccin_macchiato" and macchiato.highlightLocked
        and macchiato._selected == true and family.highlightLocked,
        "a variant applies and stays marked, with its family")
    local ar = style.Color("accent")
    assert(math.abs(ar - 0xc6 / 255) < 1e-9 and quick.title.textColor[1] == ar
        and quick.railButtons[2].tile == nil, "the window takes the variant's accent")
    picker.back.scripts.OnClick(picker.back)
    assert(not picker.view.family and not macchiato:IsShown(), "Back returns to the families")
    QC.CheckQuickBounds("theme families")
    picker.singleTab.scripts.OnClick(picker.singleTab)
    assert(quick.themeChoices.lagoon:IsShown(), "Single Color brings the grid back")
    QC.CheckQuickBounds("single themes")
end
quick.themeChoices.lagoon.scripts.OnClick()
assert(settings.vignetteRadarTheme == "lagoon" and quick.themeChoices.lagoon.highlightLocked,
    "a palette in the final row must remain selectable")
quickControl("Themes", "vignetteRadarTheme", "ember").scripts.OnClick()
assert(settings.vignetteRadarTheme == "ember" and panel.title.textColor[1] == 1
    and panel.field.background.vertexColor[1] > .04,
    "theme presets must recolor the panel and radar surface")
assert(launcher.bezel.vertexColor[1] == 1 and launcher.dial[1].color[1] > .8
    and launcher.expandChevron[1].color[1] == 1,
    "the launcher lens, outline, and expansion cue must follow the selected theme")
do
    local er, eg, eb = style.Color("accent")
    assert(quick.title.textColor[1] == er and quick.title.textColor[2] == eg
        and quick.title.textColor[3] == eb
        and quick.railButtons[2].art.vertexColor[1] == (quick.railButtons[2]._selected
            and select(1, addon.VignetteRadarIconButton.SelectedColor()) or er)
        and quick.cards["Looks/Theme"].title.textColor[1] == er,
        "a theme change must recolor the settings window's title, rail and cards live")
end
ColorPickerFrame = {
    SetupColorPickerAndShow = function(self, info) self.info = info end,
    GetColorRGB = function() return .2, .4, .6 end,
}
for _, object in ipairs(objects) do
    if object.colorSlot == "accent" and QC.ObjectCard(object) == quick.cards["Looks/Colors"] then
        object.scripts.OnClick(object)
        break
    end
end
assert(ColorPickerFrame.info, "a color swatch must open Blizzard's color picker")
ColorPickerFrame.info.swatchFunc()
assert(math.abs(panel.player.vertexColor[1] - .2) < .001 and quick.customLabel.text == "Custom Colors",
    "a custom accent must immediately recolor the player dot")
assert(math.abs(launcher.expandChevron[1].color[1] - .2) < .001,
    "custom accent colors must also recolor the miniature instrument")
quickControl("Themes", "vignetteRadarTheme", "frost").scripts.OnClick()
assert(settings.vignetteRadarTheme == "frost" and not addon.VignetteRadarStyle.IsCustomized(),
    "choosing a preset must replace the prior custom palette")
panel.zoomOut.scripts.OnEnter(panel.zoomOut)
local themedRed, themedGreen, themedBlue = addon.VignetteRadarStyle.Color("accent")
assert(panel.zoomOut.strokes[1].color[1] == themedRed
    and panel.zoomOut.strokes[1].color[2] == themedGreen
    and panel.zoomOut.strokes[1].color[3] == themedBlue
    and panel.compass.glow.vertexColor[1] == themedRed,
    "borderless footer icons must follow the selected color theme")
panel.routeToggle.scripts.OnEnter(panel.routeToggle)
routeHover.scripts.OnEnter(routeHover)
assert(panel.routeToggle.art.vertexColor[1] == themedRed
    and panel.routeToggle.art.vertexColor[2] == themedGreen
    and panel.routeToggle.art.vertexColor[3] == themedBlue
    and routeHover.art.vertexColor[1] == themedRed
    and _G.VignetteRadarRouteChooserPopup.popupEdge.vertexColor[1] == themedRed,
    "Auto Route artwork and its chooser must follow the active theme")
routeHover.scripts.OnLeave(routeHover)
panel.routeToggle.scripts.OnLeave(panel.routeToggle)
panel.zoomOut.scripts.OnLeave(panel.zoomOut)
local iconToggle = quickControl("Themes", "vignetteRadarShapes")
iconToggle:SetChecked(false)
iconToggle.scripts.OnClick(iconToggle)
assert(settings.vignetteRadarShapes == false
    and panel.blipByKey["preview-rare"].dot.texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    and panel.blipByKey["preview-boss"].dot.vertexColor[1] > panel.blipByKey["preview-rare"].dot.vertexColor[1],
    "dots-only mode must keep rare and boss colors visibly distinct")
for _, object in ipairs(objects) do
    if object.colorSlot == "boss" and QC.ObjectCard(object) == quick.cards["Looks/Colors"] then
        object.scripts.OnClick(object)
        break
    end
end
ColorPickerFrame.info.swatchFunc()
assert(math.abs(panel.blipByKey["preview-boss"].dot.vertexColor[1] - .2) < .001
    and math.abs(panel.blipByKey["preview-rare"].dot.vertexColor[1] - .78) < .001,
    "world-boss color must be independently editable from rare color")
quickAPI.OpenPage("Guides")
assert(math.abs(panel.innerLabel.textColor[4] - panel.innerRing[1].color[4]) < .001
    and math.abs(panel.outerLabel.textColor[4] - panel.middleRing[1].color[4]) < .001,
    "yard labels must initially match the opacity of their rings")
assert(quickShowsCard("Guides") and quickControl("Guides", "vignetteRadarFullSweep"),
    "the Radar Guides card must hold the sweep toggle")
local function plusFor(key)
    return QC.quickFind("Guides", function(object) return object.optionKey == key and object.text == "+" end)
end
plusFor("vignetteRadarRingOpacity").scripts.OnClick()
assert(settings.vignetteRadarRingOpacity == .75
    and math.abs(panel.rangeRing[1].color[4] - .045 * 2 * .75 * .75) < .001
    and math.abs(panel.innerLabel.textColor[4] - .03 * .5) < .001,
    "ring visibility must change rings without changing yard-label opacity")
plusFor("vignetteRadarRangeLabelOpacity").scripts.OnClick()
assert(settings.vignetteRadarRangeLabelOpacity == .75
    and math.abs(panel.innerLabel.textColor[4] - .03 * .75) < .001
    and math.abs(panel.outerLabel.textColor[4] - .04 * .75) < .001
    and math.abs(panel.innerRing[1].color[4] - .03 * 2 * .75 * .75) < .001,
    "yard-label visibility must redraw both labels independently of ring settings")
do
    local independentBorder = panel.squareBorder.vertexColor[4]
    addon.SetVignetteRadarCircleOnly(true)
    local earlierRing = panel.rangeRing[1].color[4]
    plusFor("vignetteRadarRingOpacity").scripts.OnClick()
    assert(panel.backdropColor[4] == 0 and panel.backdropBorderColor[4] == 0
        and panel.rangeRing[1].color[4] > earlierRing
        and math.abs(panel.squareBorder.vertexColor[4] - independentBorder) < .001,
        "changing ring strength in the rounded view must not reveal the hidden rectangle or change its border")
    settings.vignetteRadarRingOpacity = .75
    addon.VignetteRadarAPI.Refresh(false)
    addon.SetVignetteRadarCircleOnly(false)
end
plusFor("vignetteRadarChevronOpacity").scripts.OnClick()
plusFor("vignetteRadarHeadingOpacity").scripts.OnClick()
assert(math.abs(panel.headingChevron[1].color[4] - .8) < .001
    and math.abs(panel.direction.color[4] - .5) < .001,
    "chevron and facing-line opacity must be separate live controls")
plusFor("vignetteRadarChevronDistance").scripts.OnClick()
assert(settings.vignetteRadarChevronDistance == 5
    and math.abs(panel.headingChevron[1].startPoint[4] - 5) < .001,
    "chevron gap must redraw at the new distance from the center dot")
plusFor("vignetteRadarHeadingLength").scripts.OnClick()
assert(math.abs(panel.direction.endPoint[4] - panel.plotRadius * .35) < .001,
    "facing-line length must redraw using the selected radius fraction")
local sweepToggle = quickControl("Guides", "vignetteRadarFullSweep")
sweepToggle:SetChecked(true)
sweepToggle.scripts.OnClick(sweepToggle)
local sweep = panel.sweepLines
assert(settings.vignetteRadarFullSweep and #sweep == 2 and sweep[1]:IsShown()
    and sweep[1].parent == panel.field and sweep[1].layer == "BORDER"
    and sweep[1].color[4] < .2 and panel.blipByKey["preview-rare"].level > panel.field.level,
    "the optional full-size sweep must stay subtle and behind markers")
local oldAngle = panel._sweepAngle
panel.scripts.OnUpdate(panel, .11)
assert(panel._sweepAngle ~= oldAngle and sweep[1]:IsShown(),
    "the full-size sweep must animate while enabled")
sweepToggle:SetChecked(false)
sweepToggle.scripts.OnClick(sweepToggle)
assert(not settings.vignetteRadarFullSweep and not sweep[1]:IsShown(),
    "turning the sweep off must hide its lines immediately")
do
    local ringAlpha = panel.rangeRing[1].color[4]
    local borderAlpha = panel.squareBorder.vertexColor[4]
    local roundBorderAlpha = panel.field.halo.vertexColor[4]
    quickAPI.OpenPage("Themes")
    local borderPlus = QC.quickFind("Themes", function(object)
        return object.optionKey == "vignetteRadarBorderOpacity" and object.text == "+"
    end)
    assert(borderPlus, "Themes must expose an independent radar border control")
    borderPlus.scripts.OnClick(borderPlus)
    assert(panel.squareBorder.vertexColor[4] > borderAlpha
        and panel.field.halo.vertexColor[4] > roundBorderAlpha
        and math.abs(panel.rangeRing[1].color[4] - ringAlpha) < .001,
        "border visibility must leave the range rings unchanged")
    settings.vignetteRadarBorderOpacity = .5
    addon.VignetteRadarAPI.Refresh(false)
end
quickAPI.OpenPage("Behavior")
local combatCheck = quickControl("Behavior", "vignetteRadarKeepVisibleCombat")
combatCheck:SetChecked(true)
combatCheck.scripts.OnClick(combatCheck)
assert(settings.vignetteRadarKeepVisibleCombat == true and panel.combatToggle.keepVisible,
    "the compact combat setting must update the footer square")
panel.combatToggle.scripts.OnClick(panel.combatToggle)
assert(settings.vignetteRadarKeepVisibleCombat == false and combatCheck:GetChecked() == false,
    "the footer square must keep compact settings synchronized")
panel.settingsDot.scripts.OnClick(panel.settingsDot)
assert(not quick:IsShown(), "clicking the dot again must close compact settings")
panel.settingsDot.scripts.OnClick(panel.settingsDot)
quickAPI.OpenPage("Layout")
local hoverCheck = quickControl("Layout", "vignetteRadarHoverTools")
assert(hoverCheck and not quickControl("Layout", "vignetteRadarCircleOnly")
    and not panel.frameToggle:IsShown(),
    "the finalized layout must expose hover controls without a full-frame switch")
hoverCheck:SetChecked(false)
hoverCheck.scripts.OnClick(hoverCheck)
assert(settings.vignetteRadarHoverTools == false and quick:IsShown(),
    "changing the main radar controls must keep settings open")
hoverCheck:SetChecked(true)
hoverCheck.scripts.OnClick(hoverCheck)
quick.close.scripts.OnClick(quick.close)
UIParent:SetSize(800, 600)
addon.SetVignetteRadarLayout("squat")
panel:SetScale(1)
panel:ClearAllPoints()
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -100)
panel.settingsDot.scripts.OnClick(panel.settingsDot)
assert(quick:IsShown() and quick.point[1] == "TOPLEFT" and quick.point[2] == panel
    and quick:GetScale() > .8 and quick:GetScale() < .9,
    "on an 800px canvas the settings window must shrink beside Squat instead of covering it: "
        .. tostring(quick:GetScale()))
panel.settingsDot.scripts.OnClick(panel.settingsDot)
panel:ClearAllPoints()
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 210, -100)
panel.settingsDot.scripts.OnClick(panel.settingsDot)
assert(quick:IsShown() and quick.point[1] == "CENTER" and quick:GetScale() * quick.height <= 600 - 24,
    "without room beside the radar the settings window must center and fit the screen")
panel.settingsDot.scripts.OnClick(panel.settingsDot)
UIParent:SetSize(1600, 900)

-- A map transition can briefly yield no map, position, vignettes, or quests.
-- The stay-visible choice keeps the instrument present without stale markers.
local savedQuestLog = C_QuestLog
C_QuestLog = { GetQuestsOnMap = function() return {} end }
settings.vignetteRadarHideWhenEmpty = true
settings.vignetteRadarKeepVisibleCombat = true
guids, mapID, now = {}, nil, 1000
addon.SetVignetteRadarEnabled(true) -- Reset the temporary manual open/closed choice.
for _, circleOnly in ipairs({ false, true }) do
    addon.SetVignetteRadarCircleOnly(circleOnly)
    addon.VignetteRadarAPI.Refresh(true)
    assert(panel:IsShown() and panel.summary.text == "POSITION UNAVAILABLE"
        and next(panel.blipByKey) == nil,
        "stay visible must keep an empty radar open through a missing map without old markers")
    assert(panel.emptyReason and panel.emptyReason:find("position", 1, true)
        and panel.emptyHelp:IsShown() == (not circleOnly),
        "empty-state help must explain missing position in the full frame")
    mapID = 901
    addon.VignetteRadarAPI.Refresh(true)
    assert(panel:IsShown() and #addon.VignetteRadarAPI.GetTargets() == 0
        and next(panel.blipByKey) == nil,
        "stay visible must survive a new map whose vignette and quest scans are empty")
    mapID = nil
end

-- Explicit close and disable still take priority over automatic visibility.
panel.minimize.scripts.OnClick(panel.minimize)
addon.VignetteRadarAPI.Refresh(true)
local morph = assert(_G.VignetteRadarMorphShell, "minimizing must animate into the mini radar")
assert(panel:IsShown() and morph:IsShown() and not launcher:IsShown() and settings.vignetteRadarEnabled,
    "the radar must remain live while its surface shrinks into the launcher")
morph.scripts.OnUpdate(morph, .09)
assert(morph.width > 58 and morph.width < morph.from[3] and morph.alpha > 0
    and morph.alpha < 1 and panel:GetAlpha() > 0 and panel:GetAlpha() < 1,
    "the compacting surface must animate its size and crossfade with the live radar")
morph.scripts.OnUpdate(morph, .11)
assert(not panel:IsShown() and not morph:IsShown() and morph.scripts.OnUpdate == nil and launcher:IsShown(),
    "a completed minimize must leave only the live mini radar visible")
launcher.scripts.OnClick(launcher, "LeftButton")
assert(panel:IsShown(), "the launcher must reopen a manually closed radar")
assert(morph:IsShown() and not launcher:IsShown() and panel:GetAlpha() == 0,
    "opening the compact radar must grow its surface into the full panel")
morph.scripts.OnUpdate(morph, .09)
assert(morph.width > 58 and morph.width < morph.to[3] and panel:GetAlpha() > 0
    and panel:GetAlpha() < 1, "expansion must reveal the full radar as the compact surface grows")
morph.scripts.OnUpdate(morph, .11)
assert(not morph:IsShown() and panel:GetAlpha() > 0 and not launcher:IsShown(),
    "the expanded panel must replace the compact launcher after the transition")
panel.close.scripts.OnClick(panel.close)
addon.VignetteRadarAPI.Refresh(true)
assert(not panel:IsShown() and not settings.vignetteRadarEnabled and launcher.closed:IsShown(),
    "close must turn tracking off while retaining the launcher for reopening")

-- With the setting off, the original hide-when-empty behavior still applies.
settings.vignetteRadarKeepVisibleCombat = false
addon.SetVignetteRadarEnabled(true)
assert(not panel:IsShown(), "hide when empty must still work when stay visible is off")
settings.vignetteRadarKeepVisibleCombat = true
addon.VignetteRadarAPI.Refresh(true)
assert(panel:IsShown(), "turning stay visible back on must reopen the automatically hidden radar")

local savedTreasurePosition = livePositions.treasure
livePositions.treasure = { x = 0.51, y = 0.5 }
mapID, guids = 902, { "treasure" }
addon.VignetteRadarAPI.Refresh(true)
assert(panel:IsShown() and panel.blipByKey.treasure and panel.blipByKey.treasure.target.stale ~= true,
    "live detections returning after a map transition must render normally")
local savedRange = settings.vignetteRadarRange
livePositions.treasure = { x = .52, y = .5 }
settings.vignetteRadarRange = 10
settings.vignetteRadarEdgeCues = true
addon.VignetteRadarAPI.Refresh(true)
assert(panel.edgeCues and panel.edgeCues[1] and panel.edgeCues[1]:IsShown()
    and panel.edgeCues[1].entry.distance > 10,
    "a known off-range treasure must have a bounded edge cue without another scan")
settings.vignetteRadarEdgeCues = false
addon.VignetteRadarAPI.Refresh(false)
assert(not panel.edgeCues[1]:IsShown(), "the edge cue option must hide existing cues")
settings.vignetteRadarEdgeCues = true
settings.vignetteRadarRange = savedRange
livePositions.treasure = savedTreasurePosition
C_QuestLog = savedQuestLog

-- Auto Route: the radar's route symbols, and the corner tool that switches the Guide Panel.
do
    local focus = addon.VignetteRadarWorldFocus
    local originalRoutePoint = focus.GetRoutePoint
    local originalTrackedKind = focus.GetTrackedRouteKind
    local originalHorizon = focus.GetHorizon
    local snapshot = addon.VignetteRadarAPI.GetPlayerSnapshot()
    local routeStep = { name = "Crystal Cache", worldX = snapshot.worldX + 300, worldY = snapshot.worldY,
        instanceID = snapshot.instanceID }
    focus.GetRoutePoint = function() return routeStep, "treasure", "Treasure Route", 2, 3 end
    focus.GetTrackedRouteKind = function() return "treasure" end
    routeStep.mapID = snapshot.mapID
    local routeX = routeStep.worldX
    routeStep.worldX = snapshot.worldX + 20
    addon.VignetteRadarAPI.Refresh(false)
    assert(panel.activeCue:IsShown() and panel.activeCueHit:IsShown()
        and panel.activeCueHit.name == "Crystal Cache",
        "the active destination cue needs a matching mouse hit target")
    panel.activeCueHit.scripts.OnEnter(panel.activeCueHit)
    assert(GameTooltip:IsShown() and GameTooltip:GetOwner() == panel.activeCueHit
        and GameTooltip.text == "Crystal Cache"
        and GameTooltip.lines[1]:find("Treasure", 1, true),
        "hovering the active destination should explain the point and distance: "
            .. tostring(GameTooltip.text) .. " / " .. tostring(GameTooltip.lines[1]))
    panel.activeCueHit.scripts.OnLeave(panel.activeCueHit)
    assert(not GameTooltip:IsShown(), "the destination tooltip must dismiss on leave")
    routeStep.worldX = routeX
    focus.GetHorizon = function()
        return { { name = "Crystal Cache" }, { name = "Silvermaw" } }
    end
    addon.VignetteRadarTray = addon.VignetteRadarTrayForRouteCard
    settings.vignetteRadarGuidePanel = true
    addon.VignetteRadarAPI.Refresh(false)
    local cornerRoute = routeHover
    assert(panel.routeToggle.trackingIcon:IsShown()
        and panel.routeToggle.trackingIcon.texture
            == "Interface\\AddOns\\Magpie\\Media\\radar-route-types.tga"
        and panel.routeToggle.trackingIcon.texCoord[1] > .25
        and panel.routeToggle.trackingIcon.texCoord[1] < .5
        and not panel.routeToggle.art:IsShown()
        and cornerRoute.trackingIcon:IsShown()
        and cornerRoute.trackingIcon.texCoord[1] > .25,
        "both Auto Route buttons should show the themed treasure symbol")
    focus.GetTrackedRouteKind = function() return "quest" end
    addon.VignetteRadarAPI.Refresh(false)
    assert(panel.routeToggle.trackingIcon.texCoord[1] > .5
        and panel.routeToggle.trackingIcon.texCoord[1] < .75
        and cornerRoute.trackingIcon.texCoord[1] > .5,
        "the route symbol should follow a new quest stop")
    focus.GetTrackedRouteKind = function() return "rare" end
    addon.VignetteRadarAPI.Refresh(false)
    assert(panel.routeToggle.trackingIcon.texCoord[1] < .25
        and cornerRoute.trackingIcon.texCoord[1] < .25,
        "the route symbol should follow a rare stop")
    focus.GetTrackedRouteKind = function() return "zygor" end
    addon.VignetteRadarAPI.Refresh(false)
    assert(panel.routeToggle.trackingIcon.texCoord[1] > .75
        and cornerRoute.trackingIcon.texCoord[1] > .75,
        "the route symbol should retain the themed guide mark for Zygor")
    focus.GetTrackedRouteKind = function() return "treasure" end
    addon.VignetteRadarAPI.Refresh(false)
    -- The route card is now the Guide Panel (tests/guide_panel_test.lua);
    -- the radar's arrow corner tool switches it.
    do
        local arrowTool = CornerTool("arrow")
        assert(arrowTool.toolID == "arrow" and arrowTool.reference == panel.arrowToggle)
        arrowTool.scripts.OnClick(arrowTool, "LeftButton")
        assert(addon.GetSettings().vignetteRadarGuidePanel == false,
            "the radar's crystal button must turn the Guide Panel off")
        arrowTool.scripts.OnClick(arrowTool, "LeftButton")
        assert(addon.GetSettings().vignetteRadarGuidePanel == true,
            "the same radar button must turn the Guide Panel back on")
    end
    focus.GetRoutePoint = function() return nil end
    addon.VignetteRadarAPI.Refresh(false)
    assert(not panel.activeCueHit:IsShown(), "paused routes must hide the radar cue hit target")
    focus.GetRoutePoint = originalRoutePoint
    addon.VignetteRadarTray = nil
    focus.GetTrackedRouteKind = originalTrackedKind
    focus.GetHorizon = originalHorizon
    addon.VignetteRadarAPI.Refresh(false)
    assert(not panel.routeToggle.trackingIcon:IsShown() and panel.routeToggle.art:IsShown()
        and not cornerRoute.trackingIcon:IsShown() and cornerRoute.art:IsShown(),
        "the ordinary Auto Route mark should return when no stop is tracked")
end

-- Exploration overlays stay inside the field and crowded detections remain selectable.
local exploration = addon.VignetteRadarExploration
local ok, pin = exploration.AddPin(addon.VignetteRadarAPI.GetPlayerSnapshot(), "Test cave")
pin.worldX = pin.worldX + 40
assert(ok and exploration.AddRouteStop(pin))
addon.VignetteRadarAPI.Refresh(false)
assert(panel.exploreDots and panel.exploreDots[1]:IsShown() and panel.exploreLines[1]:IsShown(),
    "pins and numbered route stops must draw on the radar")
for _, dot in ipairs(panel.exploreDots) do
    if dot:IsShown() then
        local x, y = dot.point[4], dot.point[5]
        assert(x*x+y*y <= panel.plotRadius*panel.plotRadius,
            "exploration dots must stay inside the plotting ring")
    end
end
exploration.ClearRoute()
exploration.RemovePin(pin.id)
addon.VignetteRadarTargetPicker.ClearFocus()
settings.vignetteRadarCategories = { rare=true, treasure=true, event=true, other=true }
settings.vignetteRadarUntangle = true
livePositions.rare = { x=.51, y=.5 }
livePositions.treasure = { x=.51, y=.5 }
now, guids = 1100, { "rare", "treasure" }
addon.VignetteRadarAPI.Refresh(true)
local crowded
for _, blip in pairs(panel.blipByKey) do if blip.cluster then crowded = blip; break end end
assert(crowded and crowded.count:IsShown() and crowded.count.text == "2",
    "overlapping detections must expose a count badge")
crowded.scripts.OnEnter(crowded)
panel.scripts.OnUpdate(panel, .11)
assert(panel.blipByKey.rare and panel.blipByKey.treasure,
    "hovering a count badge must spread individual targets for selection")
assert(panel.blipByKey.rare.target.groupMin == 3 and panel.blipByKey.rare.target.groupMax == 5,
    "Blizzard's available group-size recommendation must reach the marker")

-- Trail samples use x/y internally; each style reuses a bounded marker pool.
local originalPlayerPosition = C_Map.GetPlayerMapPosition
local movingX = .5
C_Map.GetPlayerMapPosition = function() return { x=movingX, y=.5 } end
settings.vignetteRadarBreadcrumbs = true
now = 1200
addon.VignetteRadarAPI.Refresh(true)
movingX, now = .51, 1203
addon.VignetteRadarAPI.Refresh(true)
assert(panel.trailMarks[1] and panel.trailMarks[1]:IsShown()
    and panel.trailMarks[1].kind == "Line" and panel.trailMarks[1].thickness == 2.5
    and panel.trailMarks[1].parent == panel.trailLayer
    and panel.trailLayer.level == panel.field.level + 3
    and #panel.trailMarks <= 64 and not panel.exploreLines[1]:IsShown(),
    "walking must draw a capped dashed trail without clickable markers")
local firstTrailMark = panel.trailMarks[1]
local trail = exploration.GetTrail()
local currentPlayer = addon.VignetteRadarAPI.GetPlayerSnapshot()
for index = 1, 16 do
    local x = currentPlayer.worldX + (index % 2 == 0 and 180 or -180)
    local previous = trail[#trail]
    trail[#trail + 1] = { x = x, y = currentPlayer.worldY, at = now,
        arc = (previous.arc or 0) + math.abs(x - previous.x),
        instanceID = currentPlayer.instanceID }
end
addon.VignetteRadarAPI.Refresh(false)
local markCount = #panel.trailMarks
assert(markCount > 0 and markCount <= 64 and panel.trailMarks[1] == firstTrailMark,
    "a long dashed trail must respect the 64-mark cap")
addon.VignetteRadarAPI.Refresh(false)
assert(#panel.trailMarks == markCount and panel.trailMarks[1] == firstTrailMark,
    "redrawing a stationary trail must not allocate more marks")
local dashX = firstTrailMark.endPoint[3] - firstTrailMark.startPoint[3]
local dashY = firstTrailMark.endPoint[4] - firstTrailMark.startPoint[4]
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
local trailPopup = assert(_G.VignetteRadarTrailStylePopup)
do
    -- The popup also switches the Trails mode (Follow / Lead / Both).
    local modes = trailPopup.modeButtons
    assert(modes and #modes == 4 and modes[3].mode == "lead", "the trail popup offers Off, Follow, Lead and Both")
    local before = settings.vignetteRadarTrailMode
    modes[3].scripts.OnClick(modes[3])
    assert(settings.vignetteRadarTrailMode == "lead" and modes[3]._selected and not modes[2]._selected,
        "Lead switches the trail mode and stays marked")
    addon.SetVignetteRadarTrailMode(before)
end
assert(trailPopup:IsShown() and trailPopup.width == 244 and trailPopup.height == 388
    and trailPopup.clamped and settings.vignetteRadarTrailStyle == "dashes"
    and not trailPopup.rail
    and trailPopup.point[1] == "BOTTOMLEFT" and trailPopup.point[2] == panel
    and trailPopup.point[3] == "BOTTOMRIGHT" and trailPopup.point[4] == 8
    and #trailPopup.rows == 12 and UISpecialFrames[#UISpecialFrames] == trailPopup.name,
    "right-click must open a compact, screen-clamped style picker without changing the trail")
assert(trailPopup.rows[4].style == "squares" and trailPopup.rows[5].style == "hollow-squares"
    and trailPopup.rows[4].marks[1].texture == "Interface\\Buttons\\WHITE8X8",
    "both square styles must be visible without scrolling the default picker")
local previewRed, previewGreen, previewBlue = addon.VignetteRadarStyle.Color("accent")
assert(trailPopup.title.textColor[1] == previewRed and trailPopup.title.textColor[2] == previewGreen
    and trailPopup.title.textColor[3] == previewBlue
    and trailPopup.rows[1].rail.color[4] > trailPopup.rows[2].rail.color[4],
    "the picker must match the active theme and identify the current style")
for _, row in ipairs(trailPopup.rows) do
    assert(row.width == 202 and row.height == 24 and row.parent == trailPopup.content
        and row.point[4] >= 0 and row.point[4] + row.width <= trailPopup.scroll.width
        and -row.point[5] + row.height <= trailPopup.content.height
        and #row.marks == 13,
        "every scrollable choice needs a bounded animated example beside its label")
end
local previewStart = trailPopup.rows[1].marks[1].startPoint[3]
local previewBrightness = trailPopup.rows[1].marks[1].color[4]
trailPopup.scripts.OnUpdate(trailPopup, .06)
assert(trailPopup.rows[1].marks[1].startPoint[3] == previewStart
    and trailPopup.rows[1].marks[1].color[4] ~= previewBrightness,
    "open previews must animate brightness without sliding their route marks")
trailPopup.rows[2].scripts.OnClick(trailPopup.rows[2])
local stoppedPreview = trailPopup.rows[1].marks[1].startPoint[3]
trailPopup.scripts.OnUpdate(trailPopup, .2)
assert(trailPopup.rows[1].marks[1].startPoint[3] == stoppedPreview,
    "closed preview animation must do no work")
local tickX = firstTrailMark.endPoint[3] - firstTrailMark.startPoint[3]
local tickY = firstTrailMark.endPoint[4] - firstTrailMark.startPoint[4]
assert(settings.vignetteRadarTrailStyle == "ticks" and settings.vignetteRadarBreadcrumbs
    and not trailPopup:IsShown() and not panel.trailToggle._popupOpen
    and panel.trailToggle._selected and panel.trailMarks[1] == firstTrailMark
    and panel.trailMarks[1].thickness == 2
    and math.abs(dashX * tickX + dashY * tickY) < .001
    and trailPopup.rows[2].style == "ticks",
    "right-click must switch to crosswise ticks without reallocating the line pool")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
assert(trailPopup:IsShown() and trailPopup.rows[2].rail.color[4] >
    trailPopup.rows[1].rail.color[4],
    "reopening the picker must highlight the saved style")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
assert(not trailPopup:IsShown(), "a second right-click must close the picker")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
trailPopup.rows[3].scripts.OnClick(trailPopup.rows[3])
assert(settings.vignetteRadarTrailStyle == "dots" and panel.trailDots[1]
    and panel.trailDots[1]:IsShown() and not panel.trailMarks[1]:IsShown()
    and #panel.trailDots <= 64,
    "the optional dot style must reuse a capped texture pool")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
assert(#trailPopup.controls == 6 and trailPopup.controls[1].value.text == "100%"
    and trailPopup.controls[2].value.text == "1×"
    and trailPopup.controls[3].value.text == "100%"
    and trailPopup.controls[4].value.text == "180"
    and trailPopup.controls[4].value.kind == "EditBox"
    and trailPopup.controls[5].value.text == "50%"
    and trailPopup.controls[6].value.text == "100%"
    and not trailPopup.scrollButtons and trailPopup.scrollGrip,
    "spacing, flow, size, fade time, fade amount, and faded part must be visible in the picker")
for _, control in ipairs(trailPopup.controls) do
    for _, button in ipairs({ control.minus, control.plus }) do
        assert(button.point[4] >= 8 and button.point[4] + button.width <= trailPopup.width - 8
            and -button.point[5] + button.height <= trailPopup.height - 8
            and button.backdrop == nil and button.glow and #button.strokes >= 1,
            "trail steppers must use bounded, borderless radar glyphs")
    end
end
local tenYards = quickControl("Auto Route", "vignetteRadarAutoRouteArrivalRadius", 10)
do
    local routeArrowCheck = quickControl("Auto Route", "vignetteRadarAutoRouteOnSelect")
    local worldPinCheck = quickControl("Auto Route", "vignetteRadarWorldFocusThemedWaypoint")
    assert(routeArrowCheck and worldPinCheck
        and routeArrowCheck.label.parent.point[4] + routeArrowCheck.label.parent.width
            <= routeArrowCheck.point[4],
        "an Auto Route toggle label must stop before its checkbox")
end
assert(tenYards and tenYards.parent.isRow and tenYards.point[4] + tenYards.width <= tenYards.parent.width - 8
    and quick.routeStatus and quick.routeStatus.parent.isRow,
    "the ten-yard route setting and status must fit inside the Auto Route card")
local tailMinus = trailPopup.controls[5].minus
local originalSetEnabled = tailMinus.SetEnabled
local enableCalls = 0
tailMinus.SetEnabled = function(self, enabled)
    enableCalls = enableCalls + 1
    assert(enableCalls <= 2, "a stepper hover must not recursively enable the same button")
    originalSetEnabled(self, enabled)
    self.scripts.OnEnter(self)
end
addon.SetVignetteRadarTrailOption("vignetteRadarTrailTailFade", 0)
assert(enableCalls == 1 and tailMinus.enabled == false,
    "the fade-minimum stepper must disable once even when that fires OnEnter")
addon.SetVignetteRadarTrailOption("vignetteRadarTrailTailFade", .5)
assert(enableCalls == 2 and tailMinus.enabled == true,
    "the stepper must re-enable once when the fade setting returns to range")
tailMinus.SetEnabled = originalSetEnabled
tailMinus.scripts.OnLeave(tailMinus)
local previewDots = trailPopup.rows[3]
local oldGap = previewDots.marks[2].point[4] - previewDots.marks[1].point[4]
local oldFade = previewDots.marks[1].vertexColor[4]
assert(oldFade > .24,
    "default trail previews must stay legible while still showing the fade")
local oldTailAlpha = previewDots.marks[1].vertexColor[4]
trailPopup.controls[5].plus.scripts.OnClick(trailPopup.controls[5].plus)
assert(settings.vignetteRadarTrailTailFade == .51
    and previewDots.marks[1].vertexColor[4] < oldTailAlpha,
    "tail fade must dim the old end of every animated preview")
trailPopup.controls[5].minus.scripts.OnClick(trailPopup.controls[5].minus)
trailPopup.controls[1].plus.scripts.OnClick(trailPopup.controls[1].plus)
assert(previewDots.marks[2].point[4] - previewDots.marks[1].point[4] > oldGap,
    "spacing must update the animated style examples immediately")
trailPopup.controls[2].minus.scripts.OnClick(trailPopup.controls[2].minus)
local halfSpeedPhase = trailPopup._phase
trailPopup.scripts.OnUpdate(trailPopup, .06)
assert(trailPopup._phase > halfSpeedPhase and trailPopup._phase - halfSpeedPhase < 2
    and trailPopup.controls[2].value.text == "0.75×",
    "preview flow must follow the selected fractional-speed setting")
for index = 1, 3 do
    trailPopup.controls[2].minus.scripts.OnClick(trailPopup.controls[2].minus)
end
local stillPhase = trailPopup._phase
trailPopup.scripts.OnUpdate(trailPopup, .2)
assert(trailPopup._phase == stillPhase and trailPopup.controls[2].value.text == "Still",
    "Still flow must freeze the preview marks")
for index = 1, 2 do
    trailPopup.controls[2].plus.scripts.OnClick(trailPopup.controls[2].plus)
end
local initialMarkWidth = previewDots.marks[1].width
trailPopup.controls[3].plus.scripts.OnClick(trailPopup.controls[3].plus)
addon.VignetteRadarAPI.Refresh(false)
assert(settings.vignetteRadarTrailSize == 1.05 and previewDots.marks[1].width > initialMarkWidth
    and panel.trailDots[1].width == 5.25,
    "Size must enlarge both preview and live trail marks")
trailPopup.controls[3].minus.scripts.OnClick(trailPopup.controls[3].minus)
local sizeField = trailPopup.controls[3].value
sizeField.scripts.OnEditFocusGained(sizeField)
sizeField:SetText("10%")
sizeField.scripts.OnEnterPressed(sizeField)
assert(settings.vignetteRadarTrailSize == .1 and sizeField.text == "10%"
    and not trailPopup.controls[3].minus.enabled,
    "trail marks must accept a precise 10% minimum size")
sizeField.scripts.OnEditFocusGained(sizeField)
sizeField:SetText("100")
sizeField.scripts.OnEnterPressed(sizeField)
local amountField = trailPopup.controls[5].value
amountField.scripts.OnEditFocusGained(amountField)
amountField:SetText("37%")
amountField.scripts.OnEnterPressed(amountField)
assert(settings.vignetteRadarTrailTailFade == .37 and amountField.text == "37%",
    "fade amount must accept arbitrary whole percentages")
local spanField = trailPopup.controls[6].value
spanField.scripts.OnEditFocusGained(spanField)
spanField:SetText("0")
spanField.scripts.OnEnterPressed(spanField)
local noFadeAlpha = previewDots.marks[1].vertexColor[4]
spanField.scripts.OnEditFocusGained(spanField)
spanField:SetText("100")
spanField.scripts.OnEnterPressed(spanField)
assert(settings.vignetteRadarTrailFadeSpan == 1 and spanField.text == "100%"
    and previewDots.marks[1].vertexColor[4] < noFadeAlpha,
    "fade span must range from no fading to the whole trail")
local fadeField = trailPopup.controls[4].value
fadeField.scripts.OnEditFocusGained(fadeField)
fadeField:SetText("300")
fadeField.scripts.OnEnterPressed(fadeField)
assert(previewDots.marks[1].vertexColor[4] > oldFade,
    "a longer fade must brighten older marks in every preview")
local longFade = previewDots.marks[1].vertexColor[4]
assert(settings.vignetteRadarTrailSpacing == 1.25 and settings.vignetteRadarTrailSpeed == .5
    and settings.vignetteRadarTrailLifetime == 300
    and trailPopup.controls[1].value.text == "125%"
    and trailPopup.controls[2].value.text == "0.5×"
    and fadeField.text == "300"
    and not addon.SetVignetteRadarTrailOption("vignetteRadarTrailSpeed", 99),
    "picker steppers must persist valid choices and reject invalid values")
fadeField.scripts.OnEditFocusGained(fadeField)
fadeField:SetText("1")
fadeField.scripts.OnEnterPressed(fadeField)
assert(settings.vignetteRadarTrailLifetime == 1 and fadeField.text == "1"
    and not trailPopup.controls[4].minus.enabled
    and previewDots.marks[1].vertexColor[4] < longFade,
    "fade duration must accept one second and change the previews")
trailPopup.controls[4].plus.scripts.OnClick(trailPopup.controls[4].plus)
assert(settings.vignetteRadarTrailLifetime == 2 and fadeField.text == "2",
    "the skinned fade stepper must advance one second at a time")
fadeField.scripts.OnEditFocusGained(fadeField)
fadeField:SetText("0")
fadeField.scripts.OnEnterPressed(fadeField)
assert(settings.vignetteRadarTrailLifetime == 2 and fadeField.text == "2",
    "an invalid fade entry must restore the saved value")
assert(addon.SetVignetteRadarTrailOption("vignetteRadarTrailSpacing", .5)
    and addon.SetVignetteRadarTrailOption("vignetteRadarTrailSpeed", 4),
    "the densest spacing and fastest flow must be available")
trailPopup._phase = 0
trailPopup:DrawPreviews()
assert(previewDots.marks[13]:IsShown()
    and math.abs(previewDots.marks[2].point[4] - previewDots.marks[1].point[4] - 4.5) < .001,
    "a 50% dot trail must preview as a dense, nearly continuous line")
addon.VignetteRadarAPI.Refresh(false)
assert(#panel.trailDots <= 64 and #panel.trailMarks <= 64,
    "dense live trails must retain their bounded mark pools")
addon.SetVignetteRadarTrailOption("vignetteRadarTrailSpacing", 1.25)
addon.SetVignetteRadarTrailOption("vignetteRadarTrailSpeed", .5)
fadeField.scripts.OnEditFocusGained(fadeField)
fadeField:SetText("300")
fadeField.scripts.OnEnterPressed(fadeField)
for index = 1, 5 do trailPopup.scroll.scripts.OnMouseWheel(trailPopup.scroll, -1) end
assert(trailPopup.scrollIndex == 5 and trailPopup.scroll.verticalScroll == 135
    and trailPopup.scrollThumb.point[5] < -40,
    "the style rows must scroll with a visible scrollbar")
local previousCursor = GetCursorPosition
trailPopup.scrollTrack.top = 300
GetCursorPosition = function() return 0, 300 - trailPopup.scrollTrack.height
    + trailPopup.scrollThumb.height / 2 end
trailPopup.scrollGrip.scripts.OnMouseDown(trailPopup.scrollGrip)
GetCursorPosition = previousCursor
assert(trailPopup.scrollIndex == 7 and trailPopup.scrollThumb.point[5]
    == -(trailPopup.scrollTrack.height - trailPopup.scrollThumb.height),
    "the arrow-free scrollbar must remain draggable")
local diamondPreviewX = trailPopup.rows[10].marks[1].startPoint[3]
local diamondPreviewAlpha = trailPopup.rows[10].marks[1].color[4]
trailPopup.scripts.OnUpdate(trailPopup, .06)
assert(trailPopup.rows[10].marks[1].startPoint[3] == diamondPreviewX
    and trailPopup.rows[10].marks[1].color[4] ~= diamondPreviewAlpha,
    "scrolled styles must animate their examples (shown=" .. tostring(trailPopup:IsShown())
        .. ", before=" .. tostring(diamondPreviewAlpha) .. ", after="
        .. tostring(trailPopup.rows[10].marks[1].color[4]) .. ")")
trailPopup.rows[10].scripts.OnClick(trailPopup.rows[10])
assert(settings.vignetteRadarTrailStyle == "diamonds" and panel.trailExtraMarks[1]:IsShown()
    and #panel.trailMarks <= 64 and panel.trailToggle.trailExtras[1][1]:IsShown(),
    "multi-line glyphs must share the capped trail mark pool")
addon.VignetteRadarLegend.Refresh()
assert(legendPanel.guides.trail.label.text == "Trail: Diamonds"
    and legendPanel.guides.trail.extraMarks[1][1]:IsShown(),
    "the legend must name and depict the newly selected trail style")
for _, styleID in ipairs({ "long", "slashes", "chevrons", "crosses", "beads", "pulses",
    "squares", "hollow-squares" }) do
    assert(addon.SetVignetteRadarTrailStyle(styleID) and settings.vignetteRadarTrailStyle == styleID,
        "every new style must render and persist")
end
addon.SetVignetteRadarTrailStyle("squares")
assert(panel.trailDots[1]:IsShown() and panel.trailDots[1].texture == "Interface\\Buttons\\WHITE8X8",
    "filled squares must render as actual square trail marks")
addon.VignetteRadarLegend.Refresh()
assert(legendPanel.guides.trail.dots[1].texture == "Interface\\Buttons\\WHITE8X8",
    "the legend must show the selected square mark")
assert(not addon.SetVignetteRadarTrailStyle("invalid"), "unknown trail styles must be rejected")
addon.SetVignetteRadarTrailStyle("dashes")
addon.SetVignetteRadarTrailOption("vignetteRadarTrailSpeed", 0)
local stillStart = firstTrailMark.startPoint[3]
now = now + .5
addon.VignetteRadarAPI.Refresh(false)
assert(firstTrailMark.startPoint[3] == stillStart,
    "Still flow must hold trail marks in place while the player is stationary")
addon.SetVignetteRadarTrailOption("vignetteRadarTrailSpeed", 1)
local flowingStart = firstTrailMark.startPoint[3]
local flowingAlpha = firstTrailMark.color[4]
now = now + .5
addon.VignetteRadarAPI.Refresh(false)
assert(firstTrailMark.startPoint[3] == flowingStart
    and math.abs(firstTrailMark.color[4] - flowingAlpha) > .001,
    "Flow should move light across fixed trail marks without sliding their positions")
addon.SetVignetteRadarTrailStyle("dots")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "LeftButton")
assert(not settings.vignetteRadarBreadcrumbs and not panel.trailToggle._selected
    and not panel.trailDots[1]:IsShown(),
    "left-click must hide the trail and update settings immediately")
-- The hidden settings panel skips refreshes; opening it (OnShow) must show the new state.
assert(not quick:IsShown())
quick:Show(); quick.scripts.OnShow(quick)
assert(settings.vignetteRadarTrailMode == "off"
    and quickControl("Explore", "vignetteRadarTrailMode", "off").highlightLocked
    and not quickControl("Explore", "vignetteRadarTrailMode", "follow").highlightLocked,
    "reopening settings must show the trail turned off")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
assert(trailPopup:IsShown() and not settings.vignetteRadarBreadcrumbs
    and settings.vignetteRadarTrailStyle == "dots",
    "opening the picker while off must preserve the off state until a style is chosen")
trailPopup.rows[1].scripts.OnClick(trailPopup.rows[1])
assert(settings.vignetteRadarBreadcrumbs and settings.vignetteRadarTrailStyle == "dashes"
    and panel.trailMarks[1] == firstTrailMark,
    "choosing a preview while off must select and show that trail style")
addon.VignetteRadarQuickConfig.OpenPage("Explore", panel.settingsDot)
local quickTrailPicker = quickControl("Explore", "vignetteRadarTrailStyle")
quickTrailPicker.scripts.OnClick(quickTrailPicker)
assert(quick:IsShown() and trailPopup:IsShown() and trailPopup.point[2] == quickTrailPicker,
    "the compact settings button must open the picker beside itself without hiding settings")
trailPopup.controls[1].minus.scripts.OnClick(trailPopup.controls[1].minus)
assert(quick:IsShown() and trailPopup:IsShown() and settings.vignetteRadarTrailSpacing == 1,
    "adjusting trail settings must leave both the settings panel and picker open")
trailPopup.close.scripts.OnClick(trailPopup.close)
addon.VignetteRadarQuickConfig.Hide()
local oldWidth, oldHeight = UIParent.width, UIParent.height
local oldPanelLeft, oldPanelRight = panel.left, panel.right
local oldButtonLeft, oldButtonRight, oldButtonTop = panel.trailToggle.left,
    panel.trailToggle.right, panel.trailToggle.top
UIParent:SetSize(800, 600)
panel.left, panel.right = 213, 587
panel.trailToggle.left, panel.trailToggle.right, panel.trailToggle.top = 459, 481, 190
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
assert(trailPopup.point[1] == "BOTTOMLEFT" and trailPopup.point[2] == panel.trailToggle
    and trailPopup.point[3] == "TOPLEFT" and trailPopup.point[5] == 8,
    "when neither side fits, the picker must open above the button in the free gutter")
panel.left, panel.right = 8, 792
panel.trailToggle.left, panel.trailToggle.right = 758, 780
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
assert(trailPopup.point[1] == "BOTTOMRIGHT" and trailPopup.point[3] == "TOPRIGHT",
    "a picker near the screen edge must align its right edge with the button")
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
UIParent:SetSize(oldWidth, oldHeight)
panel.left, panel.right = oldPanelLeft, oldPanelRight
panel.trailToggle.left, panel.trailToggle.right, panel.trailToggle.top =
    oldButtonLeft, oldButtonRight, oldButtonTop
panel.trailToggle.scripts.OnClick(panel.trailToggle, "RightButton")
panel.legend.scripts.OnClick(panel.legend)
assert(not trailPopup:IsShown() and legendPanel:IsShown(),
    "opening the legend must close the trail picker")
panel.legend.scripts.OnClick(panel.legend)
C_Map.GetPlayerMapPosition = originalPlayerPosition

-- One chosen HandyNotes pack supplies hollow, typed map notes without entering
-- the live vignette pool; zone matching probes but never draws other packs.
local otherPackCalls = 0
HandyNotes = { plugins = {
    TestPack = { GetNodes2 = function(_, requestedMap)
        if requestedMap ~= 902 then return function() end, {}, nil end
        local done = false
        return function()
            if done then return nil end
            done = true
            return 52005000, nil, { icon = 134400,
                tCoordLeft = .1, tCoordRight = .9, tCoordTop = .2, tCoordBottom = .8,
                r = .8, g = .6, b = .4, a = .75 }, 1.25, .8
        end, { [52005000] = { label = "A map note", group = "misc" } }, nil
    end },
    OtherPack = { GetNodes2 = function(_, requestedMap)
        otherPackCalls = otherPackCalls + 1
        if requestedMap ~= 903 then return function() end, {}, nil end
        local done = false
        return function()
            if done then return nil end
            done = true
            return 51005000, nil, nil, 1, 1
        end, { [51005000] = { label = "Other zone note", group = "misc" } }, nil
    end },
}, db = { profile = { enabledPlugins = { TestPack = true, OtherPack = true } } } }
quick:Show() -- tabs are only clickable on a visible panel
quickAPI.OpenPage("Map Data")
local testPackRow
for _, row in ipairs(quick.poiRows) do if row.sourceID == "TestPack" then testPackRow = row end end
assert(quickShowsCard("Map Data") and testPackRow,
    "the map-data tab must list each available pack for a single-source choice")
assert(testPackRow.point[4] + testPackRow.width + 8 <= quick.poiTrack.point[4],
    "the map-data scrollbar must keep a visible gutter from pack buttons")
testPackRow.scripts.OnClick(testPackRow)
assert(settings.vignetteRadarPOISource == "TestPack"
    and settings.vignetteRadarMapNotesVisible and otherPackCalls > 0,
    "the picker may probe other packs but must save only the chosen source")
for index = 1, 6 do
    HandyNotes.plugins["ZPack" .. index] = { GetNodes2 = function(_, requestedMap)
        if requestedMap ~= 902 then return function() end, {}, nil end
        local done = false
        return function()
            if done then return nil end
            done = true
            return 53005000, nil, nil, 1, 1
        end, { [53005000] = { label = "Extra note" } }, nil
    end }
end
addon.VignetteRadarQuickConfig.Refresh()
assert(quick.poiTrack:IsShown(), "a long pack list must expose a scrollbar")
quick.poiRows[1].scripts.OnMouseWheel(quick.poiRows[1], -1)
assert(quick.poiOffset == 1 and quick.poiThumb.point[5] < 0,
    "the pack list must scroll while the pointer is over a source button")
quick.poiRows[1].scripts.OnMouseWheel(quick.poiRows[1], 1)
assert(quick.cards["Markers/Source Fusion"]
    and quickControl("Source Fusion", "vignetteRadarSourceFusion"),
    "Source Fusion must have a visible settings page")
settings.vignetteRadarFusionSources = { "TestPack", "ZPack1" }
settings.vignetteRadarSourceFusion = true
addon.VignetteRadarAPI.Refresh(true)
assert(panel.mapNotes[1] and panel.mapNotes[1]:IsShown()
    and panel.mapNotes[2] and panel.mapNotes[2]:IsShown()
    and ((panel.mapNotes[1].note.source == "TestPack" and panel.mapNotes[2].note.source == "ZPack1")
        or (panel.mapNotes[1].note.source == "ZPack1" and panel.mapNotes[2].note.source == "TestPack")),
    "enabling Source Fusion must render selected packs together")
settings.vignetteRadarSourceFusion = false
settings.vignetteRadarFusionSources = {}
addon.VignetteRadarAPI.Refresh(true)
settings.vignetteRadarBreadcrumbs = false
settings.vignetteRadarKeepVisibleCombat = false
now, guids = 1300, {}
addon.VignetteRadarAPI.Refresh(true)
assert(panel:IsShown() and panel.mapNotes[1] and panel.mapNotes[1]:IsShown()
    and panel.mapNotes[1].note.kind == "note" and panel.mapNotes[1].note.source == "TestPack",
    "the chosen pack must draw its map note")
do
    if not addon.VignetteRadarLegend.IsShown() then addon.VignetteRadarLegend.Toggle(panel.legend) end
    assert(addon.VignetteRadarLegend.ToggleMarkers())
    local markerPanel = assert(_G.VignetteRadarMarkerLegendPanel)
    markerPanel.tabs.types.scripts.OnClick(markerPanel.tabs.types)
    local noteTypeRow
    for _, row in ipairs(markerPanel.rows) do
        if row.entry and row.entry.label == "Other Note Icon" then noteTypeRow = row; break end
    end
    assert(noteTypeRow and noteTypeRow.icon.texture == 134400,
        "saved map-note types must show their actual pack icons")
    noteTypeRow.toggle.scripts.OnClick(noteTypeRow.toggle)
    assert(not panel.mapNotes[1]:IsShown()
        and next(settings.vignetteRadarHiddenMarkerTypes) ~= nil,
        "hiding a map-note icon type must filter its matching dots")
    noteTypeRow.toggle.scripts.OnClick(noteTypeRow.toggle)
    assert(panel.mapNotes[1]:IsShown()
        and next(settings.vignetteRadarHiddenMarkerTypes) == nil,
        "restoring a map-note icon type must redraw its dots")
    markerPanel.tabs.names.scripts.OnClick(markerPanel.tabs.names)
    local noteRow
    for _, row in ipairs(markerPanel.rows) do
        if row.entry and row.entry.name == "A map note" then noteRow = row; break end
    end
    assert(noteRow and noteRow.entry.category == "map:note"
        and #addon.VignetteRadarAPI.GetRawMapNotes() == 1,
        "the marker list must include individual notes from the chosen map pack")
    noteRow.toggle.scripts.OnClick(noteRow.toggle)
    assert(settings.vignetteRadarHiddenMarkerNames["map:note:a map note"] == "A map note"
        and not panel.mapNotes[1]:IsShown()
        and #addon.VignetteRadarAPI.GetRawMapNotes() == 1,
        "hiding one map note name must remove its dot without discarding the source data")
    noteRow.toggle.scripts.OnClick(noteRow.toggle)
    assert(settings.vignetteRadarHiddenMarkerNames["map:note:a map note"] == nil
        and panel.mapNotes[1]:IsShown(),
        "restoring a map note name must redraw its dot immediately")
    markerPanel.back.scripts.OnClick(markerPanel.back)
end
legendPanel.mapToggle.scripts.OnClick(legendPanel.mapToggle)
assert(settings.vignetteRadarMapNotesVisible == false
    and settings.vignetteRadarPOISource == "TestPack"
    and not panel.mapNotes[1]:IsShown(),
    "the Radar Legend should hide map-pack dots without forgetting the chosen pack")
legendPanel.mapToggle.scripts.OnClick(legendPanel.mapToggle)
assert(settings.vignetteRadarMapNotesVisible == true and panel.mapNotes[1]:IsShown(),
    "the Radar Legend should restore dots when map notes are turned back on")
legendPanel.mapNotes.note.scripts.OnClick(legendPanel.mapNotes.note)
assert(settings.vignetteRadarPOITypes.note == false and not panel.mapNotes[1]:IsShown(),
    "a legend note row should filter only its matching marker type")
legendPanel.mapNotes.note.scripts.OnClick(legendPanel.mapNotes.note)
assert(settings.vignetteRadarPOITypes.note == true and panel.mapNotes[1]:IsShown(),
    "the legend note row should restore its marker type")
local closeNote = panel.mapNotes[1].note
local previousTreasurePosition = livePositions.treasure
closeNote.kind = "treasure"
livePositions.treasure = { x = .52, y = .5 }
guids = { "treasure" }
addon.VignetteRadarAPI.Refresh(true)
assert(addon.VignetteRadarAPI.GetTargets()[1]
    and addon.VignetteRadarAPI.GetTargets()[1].category == "treasure"
    and not panel.mapNotes[1]:IsShown(),
    "a live treasure must replace a coincident map-pack treasure marker")
closeNote.kind = "note"
addon.VignetteRadarAPI.Refresh(false)
assert(panel.mapNotes[1]:IsShown(),
    "a nearby map note of another kind must remain visible beside a live treasure")
guids, livePositions.treasure = {}, previousTreasurePosition
addon.VignetteRadarAPI.Refresh(true)
local savedNoteX, savedNoteY = closeNote.worldX, closeNote.worldY
local savedRange = settings.vignetteRadarRange
local closePlayer = addon.VignetteRadarAPI.GetPlayerSnapshot()
closeNote.worldX, closeNote.worldY = closePlayer.worldX + 5, closePlayer.worldY
settings.vignetteRadarRange = 10
addon.VignetteRadarAPI.Refresh(false)
assert(panel.mapNotes[1]:IsShown() and panel.mapNotes[1].note == closeNote,
    "a map note five yards away must remain visible at ten-yard zoom")
closeNote.worldX = closePlayer.worldX + 20
addon.VignetteRadarAPI.Refresh(false)
assert(not panel.mapNotes[1]:IsShown(),
    "a cached map note outside the displayed range must not draw")
settings.vignetteRadarRange = 25
addon.VignetteRadarAPI.Refresh(false)
assert(panel.mapNotes[1]:IsShown() and panel.mapNotes[1].note == closeNote,
    "zooming out must restore the cached note without collecting map data again")
closeNote.worldX, closeNote.worldY = savedNoteX, savedNoteY
settings.vignetteRadarRange = savedRange
addon.VignetteRadarAPI.Refresh(false)
for _, target in ipairs(addon.VignetteRadarAPI.GetTargets()) do
    assert(target.source ~= "TestPack", "map notes must stay outside the live detection pool")
end
local noteX, noteY = panel.mapNotes[1].point[4], panel.mapNotes[1].point[5]
assert(noteX * noteX + noteY * noteY <= (panel.plotRadius - 5)^2,
    "map-note dots must stay inside the radar's plotting boundary")
local packIconToggle = assert(quickControl("Map Data", "vignetteRadarPOIIcons"))
local clearedToggle = assert(quickControl("Behavior", "vignetteRadarHideCleared"))
local radarEvents
for _, object in ipairs(objects) do
    if object.events and object.events.VIGNETTES_UPDATED then radarEvents = object end
end
assert(radarEvents and not radarEvents.events.COMBAT_LOG_EVENT_UNFILTERED,
    "radar must not register the forbidden combat-log event")
local eventRegistrationCalls = radarEvents.eventRegistrationCalls
clearedToggle:SetChecked(true)
clearedToggle.scripts.OnClick(clearedToggle)
assert(settings.vignetteRadarHideCleared,
    "enabling cleared-target filtering must save the setting")
clearedToggle:SetChecked(false)
clearedToggle.scripts.OnClick(clearedToggle)
assert(not settings.vignetteRadarHideCleared,
    "disabling cleared-target filtering must save the setting")
assert(radarEvents.eventRegistrationCalls == eventRegistrationCalls
    and not radarEvents.eventUnregistrationCalls,
    "filter toggles must not change event registration")
packIconToggle:SetChecked(true)
packIconToggle.scripts.OnClick(packIconToggle)
local mapNote = panel.mapNotes[1]
assert(settings.vignetteRadarPOIIcons and mapNote.icon:IsShown()
    and not mapNote.rim:IsShown() and not mapNote.core:IsShown()
    and mapNote.icon.texture == 134400
    and mapNote.icon.texCoord[1] == .1 and mapNote.icon.texCoord[4] == .8
    and mapNote.icon.vertexColor[1] == .8 and math.abs(mapNote.icon.vertexColor[4] - .6) < .0001
    and mapNote.icon.width == 15,
    "pack-icon mode must show the pack's cropped, tinted, scaled artwork")
noteX, noteY = mapNote.point[4], mapNote.point[5]
assert(noteX * noteX + noteY * noteY <= (panel.plotRadius - 11)^2,
    "pack artwork must remain inside the radar's plotting boundary")
packIconToggle:SetChecked(false)
packIconToggle.scripts.OnClick(packIconToggle)
assert(not settings.vignetteRadarPOIIcons and not mapNote.icon:IsShown()
    and mapNote.rim:IsShown() and mapNote.core:IsShown(),
    "turning pack icons off must restore the original typed dots")
packIconToggle:SetChecked(true)
packIconToggle.scripts.OnClick(packIconToggle)
settings.vignetteRadarPOITypes.note = false
addon.VignetteRadarAPI.Refresh(false)
assert(not panel.mapNotes[1]:IsShown(), "type filters must hide only that map-note type")
settings.vignetteRadarPOITypes.note = true
mapID, now = 903, 1311
addon.VignetteRadarAPI.Refresh(true)
-- Radar refreshes skip the hidden settings panel; it refreshes when opened.
addon.VignetteRadarQuickConfig.Refresh()
assert(not panel.mapNotes[1]:IsShown() and quick.poiStatus.text:find("no notes here", 1, true),
    "a manually chosen pack must not leak into a different zone")
settings.vignetteRadarPOISource = "auto"
addon.VignetteRadarAPI.Refresh(true)
assert(panel.mapNotes[1]:IsShown() and panel.mapNotes[1].note.source == "OtherPack"
    and quick.poiMapID == 903 and quick.poiOffset == 0,
    "Auto must switch to one matching pack and reset the source list on a zone change")
assert(not panel.mapNotes[1].icon:IsShown() and panel.mapNotes[1].rim:IsShown()
    and panel.mapNotes[1].core:IsShown(),
    "nodes without pack artwork must fall back to the typed dot in icon mode")
for _, entry in ipairs(quick.poiEntries) do
    assert(entry.id ~= "TestPack", "the picker must omit packs with no notes for this zone")
end
settings.vignetteRadarPOISource = "none"
addon.VignetteRadarAPI.Refresh(true)
assert(not panel.mapNotes[1]:IsShown(), "turning map data off must clear its dots")

-- WoW reports a scaled frame's edges in that frame's own coordinate system.
-- A saved circle-only position and Reset must keep the visible face on screen.
UIParent:SetSize(3413.3335, 960)
addon.SetVignetteRadarLayout("compact")
addon.SetVignetteRadarCircleOnly(false)
assert(addon.SetVignetteRadarScale(1.6433441638947))
settings.vignetteRadarCirclePosition = { x = 1532.168579101563, y = -700 }
addon.SetVignetteRadarCircleOnly(true)
local function assertFaceVisible(message)
    local scale = panel:GetScale()
    local fieldLeft = panel:GetLeft() * scale + (panel.width - panel.field.width) * scale / 2
    local fieldBottom = panel:GetBottom() * scale + panel.field.point[3] * scale
    assert(fieldLeft >= 3.99 and fieldLeft + panel.field.width * scale <= UIParent:GetWidth() - 3.99
        and fieldBottom >= 3.99 and fieldBottom + panel.field.height * scale <= UIParent:GetHeight() - 3.99,
        ("%s (left %.2f, bottom %.2f, field %.2fx%.2f, scale %.2f)"):format(
            message, fieldLeft, fieldBottom, panel.field.width, panel.field.height, scale))
end
assertFaceVisible("saved scaled circle-only position must keep the radar face visible")
addon.ResetVignetteRadarPositions()
assertFaceVisible("Reset must bring a scaled radar face fully onto the screen")
SlashCmdList.VIGNETTERADAR("recenter")
assert(panel:IsShown() and settings.vignetteRadarEnabled,
    "recenter command must recover a hidden radar panel")
assertFaceVisible("recenter command must keep the scaled radar face visible")
assert(launcher:IsShown() and launcher.strata == "TOOLTIP" and launcher._rescueRaised,
    "recenter must visibly rescue the launcher above overlapping UI")
launcher.scripts.OnDragStop(launcher)
assert(launcher.strata == "MEDIUM" and not launcher._rescueRaised,
    "dragging the rescued launcher must restore its normal layer")

VignetteRadar_RaiseLauncher("down")
assert(launcher.strata == "TOOLTIP" and launcher.level == 1000
    and not _G.VignetteRadarLauncherPeekWatcher,
    "key down must raise the launcher without creating a polling frame")
VignetteRadar_RaiseLauncher("up")
assert(launcher.strata == "MEDIUM" and launcher.level == 1,
    "key up must restore the normal launcher layer")
VignetteRadar_RaiseLauncher("down")
launcher._dragging = true
VignetteRadar_RaiseLauncher("up")
assert(launcher.strata == "TOOLTIP" and launcher._peekReleased,
    "releasing the key during a drag must keep the launcher raised")
launcher.scripts.OnDragStop(launcher)
assert(launcher.strata == "MEDIUM", "the launcher must restore its layer after dragging stops")
settings.vignetteRadarLauncherPosition = nil
settings.vignetteRadarLauncherVisible = false
launcher:Hide()
VignetteRadar_RaiseLauncher("down")
assert(launcher:IsShown(), "the binding must reveal a normally hidden launcher")
addon.VignetteRadarAPI.Refresh(false)
assert(launcher:IsShown(), "normal radar refreshes must not hide the launcher during a held binding")
VignetteRadar_RaiseLauncher("up")
assert(not launcher:IsShown(), "the launcher must return to its visibility preference on release")
settings.vignetteRadarLauncherVisible = true
launcher:Show()

local outsideClickEvents
for _, object in ipairs(objects) do
    -- (The tray's own click-away frame also listens for UI scale changes.)
    if object.events and object.events.GLOBAL_MOUSE_DOWN and not object.events.UI_SCALE_CHANGED then
        outsideClickEvents = object
    end
end
assert(outsideClickEvents and outsideClickEvents.scripts.OnEvent,
    "radar popups need a click-outside event without a polling frame")
local registrations = outsideClickEvents.eventRegistrationCalls
quick:Show()
addon.VignetteRadarQuickConfig.ShowGuide(panel.field)
local guidePanel = assert(_G.VignetteRadarGuidePanel)
assert(guidePanel:IsShown(), "the visual first-run guide must be reopenable")
assert(#guidePanel.symbols == 6 and guidePanel.symbols[1].frame.kind == "Frame"
    and guidePanel.symbols[1].frame:IsShown()
    and guidePanel.symbols[1].parts[1].texture.texture
        == "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
    and guidePanel.symbols[4].parts[1].texture.texture:find("quest%-diamond%-hollow%.tga$")
    and guidePanel.symbols[6].parts[1].opacity < 1,
    "the guide must draw real rare, quest, and area markers instead of unsupported font glyphs")
guidePanel.controlTab.scripts.OnClick(guidePanel.controlTab)
assert(guidePanel.page == "Controls" and not guidePanel.symbols[1].frame:IsShown()
    and #guidePanel.controlLines == 7 and guidePanel.controlLines[2]:IsShown()
    and guidePanel.controlLines[2].text == "Shift-Click — Navigate"
    and guidePanel.controlTab.point[4] + guidePanel.controlTab.width <= guidePanel.width - 8,
    "the Radar Guide must present modifier controls separately inside its popup")
assert(-guidePanel.controlLines[7].point[5] + 12 <= -guidePanel.controlTab.point[5] - 8
    and -guidePanel.controlTab.point[5] + guidePanel.controlTab.height <= guidePanel.height - 8,
    "guide controls and tabs must leave a visible gutter without touching the popup border")
guidePanel.symbolTab.scripts.OnClick(guidePanel.symbolTab)
assert(guidePanel.page == "Symbols" and guidePanel.symbols[1].frame:IsShown()
    and not guidePanel.controlLines[1]:IsShown(),
    "the guide must return to its visual marker key")
for _, symbol in ipairs(guidePanel.symbols) do
    assert(symbol.frame.width == 21 and symbol.frame.height == 21
        and symbol.frame.point[4] >= 12 and symbol.frame.point[4] + 21 < guidePanel.width - 12,
        "guide markers must fit inside the popup without touching its border")
end
panel.settingsDot.hovered = true
outsideClickEvents.scripts.OnEvent(outsideClickEvents, "GLOBAL_MOUSE_DOWN")
assert(quick:IsShown(), "clicking a popup launch button must leave its toggle action in control")
panel.settingsDot.hovered = false
panel.frameToggle.hovered = true
outsideClickEvents.scripts.OnEvent(outsideClickEvents, "GLOBAL_MOUSE_DOWN")
assert(quick:IsShown(), "switching the outer frame must keep settings open")
panel.frameToggle.hovered = false
quick.hovered = true
outsideClickEvents.scripts.OnEvent(outsideClickEvents, "GLOBAL_MOUSE_DOWN")
assert(quick:IsShown() and guidePanel:IsShown(),
    "clicks inside one related popup must keep the popup group open")
quick.hovered = false
outsideClickEvents.scripts.OnEvent(outsideClickEvents, "GLOBAL_MOUSE_DOWN")
assert(not quick:IsShown() and not guidePanel:IsShown()
    and outsideClickEvents.eventRegistrationCalls == registrations,
    "a click elsewhere must dismiss popups without registering or unregistering events")
do
    panel.routeToggle.scripts.OnClick(panel.routeToggle, "RightButton")
    local chooser = assert(_G.VignetteRadarRouteChooserPopup)
    panel.routeToggle.hovered = true
    outsideClickEvents.scripts.OnEvent(outsideClickEvents, "GLOBAL_MOUSE_DOWN")
    assert(chooser:IsShown(), "clicking the route opener must leave its toggle action in control")
    panel.routeToggle.hovered = false
    chooser.hovered = true
    outsideClickEvents.scripts.OnEvent(outsideClickEvents, "GLOBAL_MOUSE_DOWN")
    assert(chooser:IsShown(), "clicks inside the route chooser must keep it open")
    chooser.hovered = false
    outsideClickEvents.scripts.OnEvent(outsideClickEvents, "GLOBAL_MOUSE_DOWN")
    assert(not chooser:IsShown() and outsideClickEvents.eventRegistrationCalls == registrations,
        "a click outside must dismiss the chooser without adding another event loop")
end

do
    panel:Show()
    panel.bottom = 180
    addon.ShowVignetteRadarRouteNote("ZYGOR STEP", "Find the cave entrance")
    local toast = assert(_G.VignetteRadarRouteNote)
    assert(toast:IsShown() and toast.heading:GetText() == "ZYGOR STEP"
        and toast.message:GetText() == "Find the cave entrance"
        and toast.point[1] == "TOP" and #toast.statusSurface.face == 9
        and #toast.statusSurface.edge == 9,
        "route notes should appear below the radar with an unstretched rounded surface")
    toast.scripts.OnUpdate(toast, 2.9)
    assert(toast:IsShown() and toast:GetAlpha() < 1,
        "route notes should begin fading after a short reading interval")
    toast.scripts.OnUpdate(toast, .6)
    assert(not toast:IsShown() and toast.scripts.OnUpdate == nil,
        "the route note should fully hide and stop updating after its fade")
    panel.bottom = 5
    panel.field.bottom = 5
    addon.ShowVignetteRadarRouteNote("NEXT STEP", "Reach the treasure")
    assert(toast:IsShown() and toast.point[1] == "BOTTOM",
        "a radar near the screen bottom should keep the note on screen")
    local originalWidth = panel:GetWidth()
    panel:SetWidth(164)
    UIParent:SetSize(800, 600)
    addon.ShowVignetteRadarRouteNote("AUTO ROUTE", "Next stop")
    assert(toast:GetWidth() == 260 and toast.message:GetWidth() == 232,
        "the smallest radar layout must retain readable text and 14-pixel side gutters")
    addon.ShowVignetteRadarRouteNote("AUTO ROUTE", "Quest destination",
        { label = "Collect Shredder Parts", count = "2/5" })
    assert(toast:GetHeight() == 110 and toast.objective:GetText() == "Collect Shredder Parts"
        and toast.count:GetText() == "Objective · 2/5"
        and toast.objective:GetWidth() == 232 and toast.fadeEnd == 5,
        "the temporary note should reserve its own space for objective progress")
    addon.ShowVignetteRadarRouteNote("AUTO ROUTE", "Next stop")
    assert(toast:GetHeight() == 62 and not toast.objective:IsShown(),
        "a non-objective note should release the extra space")
    panel:SetWidth(originalWidth)
    UIParent:SetSize(1600, 900)
    toast:Hide()
    panel.bottom = nil
    panel.field.bottom = nil
end

local profileClock, performanceWarning = 0, nil
recoveryTimers = {}
originalTimerAfter = C_Timer.After
C_Timer.After = function(delay, callback)
    recoveryTimers[#recoveryTimers + 1] = { delay = delay, callback = callback }
end
debugprofilestop = function() profileClock = profileClock + 300; return profileClock end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) performanceWarning = message end }
local launcherUpdate = assert(launcher.scripts.OnUpdate)
launcherUpdate(launcher, .2)
assert(launcher.scripts.OnUpdate == nil and performanceWarning
    and performanceWarning:find("Retrying in 10 seconds", 1, true)
    and recoveryTimers[#recoveryTimers].delay == 10,
    "an excessive update must pause briefly and schedule automatic recovery")
recoveryTimers[#recoveryTimers].callback()
assert(launcher.scripts.OnUpdate == launcherUpdate
    and not addon.VignetteRadarBudget.paused.launcher
    and addon.VignetteRadarBudget.softThrottle,
    "the launcher must restart automatically at the safer update rate")
debugprofilestop = nil

sustainedClock = 0
debugprofilestop = function() sustainedClock = sustainedClock + 15; return sustainedClock end
radarUpdate = assert(panel.scripts.OnUpdate)
sustainedIterations = 0
while sustainedIterations < 40 and panel.scripts.OnUpdate do
    radarUpdate(panel, 0)
    sustainedIterations = sustainedIterations + 1
end
assert(panel.scripts.OnUpdate == nil and addon.VignetteRadarBudget.paused.radar,
    "sustained costly redraws must trip the cumulative CPU guard")
recoveryTimers[#recoveryTimers].callback()
assert(panel.scripts.OnUpdate == radarUpdate
    and not addon.VignetteRadarBudget.paused.radar,
    "the full radar must recover without a reload")
quietClock, quietCall = 0, 0
debugprofilestop = function()
    quietCall = quietCall + 1
    quietClock = quietClock + (quietCall % 2 == 1 and 1200 or 1)
    return quietClock
end
quietIterations = 0
while quietIterations < 12 do
    radarUpdate(panel, 0)
    quietIterations = quietIterations + 1
end
assert(not addon.VignetteRadarBudget.softThrottle,
    "a sustained quiet period must restore the user's selected update rate")
debugprofilestop = nil
C_Timer.After = originalTimerAfter

-- Duplicate Icons: the radar reads one hide table per render from the
-- Minimap Underlay and leaves out the marker kinds the minimap draws.
do
    local savedUnderlay, savedGuids, iconsPosition = addon.VignetteRadarMinimapUnderlay, guids, livePositions.treasure
    local iconsRange = settings.vignetteRadarRange
    local hide
    addon.VignetteRadarMinimapUnderlay = {
        Sync = function(range) return range end,
        ShowsTerrain = function() return hide ~= nil end,
        RadarHides = function() return hide end,
        FaceAlpha = function() return .94 end,
        BaseAlpha = function() return .94 end,
        IsActive = function() return hide ~= nil end,
    }
    local function ShownTreasures()
        local count = 0
        for _, blip in pairs(panel.blipByKey) do
            if blip:IsShown() and blip.target and blip.target.category == "treasure" then count = count + 1 end
        end
        return count
    end
    settings.vignetteRadarRange = 450
    livePositions.treasure = { x = .52, y = .5 }
    guids = { "treasure" }
    addon.VignetteRadarAPI.Refresh(true)
    assert(ShownTreasures() == 1, "a live treasure draws with no underlay hide table")
    hide = { staticPOIs = true, label = "plain map spots hidden" }
    addon.VignetteRadarAPI.Refresh(false)
    assert(ShownTreasures() == 1 and panel._underlayHide == hide, "Split By Type keeps live treasures")
    hide = { areaPOIs = true, vignettes = true, quests = true, label = "minimap-drawn kinds hidden" }
    addon.VignetteRadarAPI.Refresh(false)
    assert(ShownTreasures() == 0, "Minimap Wins hides live vignettes")
    assert(panel._underlayHide == hide and panel._underlayHideTraced == hide, "the hide table is cached on the panel")
    hide = nil
    addon.VignetteRadarAPI.Refresh(false)
    assert(ShownTreasures() == 1 and panel._underlayHide == nil, "terrain off: every marker is back")
    addon.VignetteRadarMinimapUnderlay = savedUnderlay
    guids, livePositions.treasure, settings.vignetteRadarRange = savedGuids, iconsPosition, iconsRange
    addon.VignetteRadarAPI.Refresh(true)
end

-- No Controls button anywhere in the built UI may cut its label: the label
-- has no fixed width and its measured text fits inside the button.
;(function()
    local overfull = {}
    for _, object in ipairs(objects) do
        local label = object.label
        if object.kind == "Button" and object.fitsLabel and label and label.kind == "FontString"
            and object.point and (label.text or "") ~= "" then
            local need = addon.VignetteRadarStyle.TextWidth(label)
            if label.width or need > (object.width or 0) - 10 + .01 then
                overfull[#overfull + 1] = string.format("%q needs %.0f, has %.0f", label.text, need,
                    (object.width or 0) - 10)
            end
        end
    end
    assert(#overfull == 0, "button labels would truncate:\n" .. table.concat(overfull, "\n"))
end)()

io.write("vignette radar UI tests passed\n")
