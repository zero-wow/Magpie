local sourcePath = arg[1] or "UI/QuestTracker.lua"

local objects = {}
local methods = {}
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetAllPoints() end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetScale(value) self.scale = value end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:SetMovable(value) self.movable = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:EnableMouseWheel(value) self.mouseWheel = value end
function methods:RegisterForDrag(value) self.dragButton = value end
function methods:RegisterForClicks(value) self.clickButton = value end
function methods:RegisterEvent(value) self.events = self.events or {}; self.events[value] = true end
function methods:SetScript(key, value) self.scripts = self.scripts or {}; self.scripts[key] = value end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:GetLeft() return self.left or 290 end
function methods:GetRight() return self.right or ((self.left or 290) + (self.width or 0)) end
function methods:GetTop() return self.top or 740 end
function methods:GetBottom() return self.bottom or ((self.top or 740) - (self.height or 0)) end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetFont(...) self.font = { ... } end
function methods:SetJustifyH(value) self.justify = value end
function methods:SetWordWrap(value) self.wrap = value end
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetVertexColor(...) self.vertex = { ... } end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:IsShown() return self.shown == true end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value == true end
function methods:IsMouseOver() return self.mouseOver == true end
function methods:LockHighlight() self.selected = true end
function methods:UnlockHighlight() self.selected = false end
function methods:SetClipsChildren(value) self.clips = value end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameLevel() return self.level or 1 end
function methods:GetFrameStrata() return self.strata or "MEDIUM" end
function methods:SetParent(value) self.parent = value end
function methods:GetParent() return self.parent end
function methods:GetScale() return self.scale or 1 end
function methods:SetBlendMode(value) self.blend = value end
function methods:SetThickness(value) self.thickness = value end
function methods:SetStartPoint(...) self.startPoint = { ... } end
function methods:SetEndPoint(...) self.endPoint = { ... } end
function methods:CreateLine()
    return setmetatable({ shown = true }, { __index = methods })
end
function MouseIsOver(frame) return frame.mouseOver == true end
function methods:SetGradient(...) self.gradient = { ... } end
function methods:GetScript(key) return self.scripts and self.scripts[key] end
function methods:GetStringWidth() return #(self.text or "") * 6 end
function methods:SetResizable(value) self.resizable = value end
function methods:SetResizeBounds(...) self.resizeBounds = { ... } end
function methods:SetNormalTexture(value) self.normalTexture = value end
function methods:SetHighlightTexture(value) self.highlightTexture = value end
function methods:SetPushedTexture(value) self.pushedTexture = value end
function methods:StartSizing(point) self.sizingFrom = point end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function methods:CreateTexture()
    return setmetatable({ shown = true }, { __index = methods })
end
function methods:CreateFontString()
    return setmetatable({ shown = true }, { __index = methods })
end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, parent = parent, shown = true }, { __index = methods })
    if name then _G[name] = frame end
    objects[#objects + 1] = frame
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1600, 900)
local radarPanel = CreateFrame("Frame", nil, UIParent)
radarPanel:SetSize(246, 278)
radarPanel.left, radarPanel.top = 30, 380
radarPanel.field = CreateFrame("Frame", nil, radarPanel)
radarPanel.field:SetSize(200, 200)
radarPanel.field.left, radarPanel.field.top = 52, 350
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local settings = { vignetteRadarQuestTrackerVisible = true,
    vignetteRadarQuestTrackerScope = "local", vignetteRadarQuestTrackerCollapsed = {},
    vignetteRadarQuestDots = true, vignetteRadarQuestNumbers = false }
local highlights, focused, refreshes = {}, nil, 0
local fontStyle = {}
assert(loadfile("UI/Style.lua"))("VignetteRadar", fontStyle)
local addon = {
    GetSettings = function() return settings end,
    VignetteRadarQuestColors = { { .3, .6, 1 }, { 1, .7, .3 }, { .7, .4, 1 } },
    VignetteRadarStyle = { revision = 0, SetFont = fontStyle.VignetteRadarStyle.SetFont,
        Color = function() return .3, .7, .9 end },
    VignetteRadarControls = {
        Button = function(parent, label, w, h)
            local button = CreateFrame("Button", nil, parent)
            button:SetSize(w, h)
            button:SetText(label)
            return button
        end,
        RoundedStatusSurface = function(frame)
            frame.statusSurface = { edge = {} }
            for index = 1, 9 do
                frame.statusSurface.edge[index] = frame:CreateTexture()
            end
        end,
        RefreshRoundedStatusSurface = function() end,
    },
    VignetteRadarQuestData = { GetObjectiveSummary = function(id)
        if id == 11 then return { label = "Collect Shells", count = "1/4" } end
    end },
    VignetteRadarExploration = {
        GetFocusedQuest = function() return focused end,
        FocusQuest = function(id) focused = focused == id and nil or id end,
    },
    VignetteRadarAPI = {
        GetPanel = function() return radarPanel end,
        GetCurrentMapID = function() return 84 end,
        GetQuests = function() return { { questID = 11, mapID = 84, colorSlot = 2 },
            { questID = 22, mapID = 99, colorSlot = 1 } } end,
        GetQuestColorSlot = function(id) return id == 11 and 2 or 3 end,
        HighlightQuest = function(id) highlights[#highlights + 1] = id or "clear" end,
    },
    RefreshVignetteRadar = function() refreshes = refreshes + 1 end,
}
C_QuestLog = {
    GetQuestsOnMap = function() return { { questID = 11 }, { questID = 33 } } end,
    GetNumQuestLogEntries = function() return 5 end,
    GetInfo = function(index)
        return ({
            { isHeader = true, title = "Dragon Isles" },
            { questID = 11, title = "Shell Search", difficultyLevel = 78 },
            { questID = 22, title = "Faraway Errand", difficultyLevel = 70 },
            { isHeader = true, title = "Old World" },
            { questID = 33, title = "Local History", difficultyLevel = 80 },
        })[index]
    end,
    GetNumQuestWatches = function() return 1 end,
    GetQuestIDForQuestWatchIndex = function() return 22 end,
    GetNextWaypointForMap = function() return nil end,
    IsComplete = function(id) return id == 33 end,
    IsWorldQuest = function() return false end,
    GetTitleForQuestID = function(id) return id == 44 and "World Event" end,
}
C_TaskQuest = { GetQuestsOnMap = function()
    return { { questID = 44, isWorldQuest = true } }
end }
GetQuestDifficultyColor = function(level)
    return level == 78 and { r = 1, g = .6, b = .2 } or { r = .7, g = .8, b = .9 }
end

assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Data/QuestService.lua"))("VignetteRadar", addon)
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Tray.lua"))("VignetteRadar", addon)
assert(loadfile(sourcePath))("VignetteRadar", addon)
local tracker = assert(addon.VignetteRadarQuestTracker)
local localEntries = tracker.BuildEntries(84, "local")
assert(#localEntries == 6, "local scope should retain only populated quest-log headers and task quests")
assert(localEntries[1].title == "Dragon Isles" and localEntries[1].count == 1
    and localEntries[2].questID == 11 and localEntries[2].colorSlot == 2,
    "a local quest must keep its visible header and exact radar color slot")
assert(localEntries[3].title == "Old World" and localEntries[4].complete == true,
    "a second local header and ready quest should remain distinct")
assert(localEntries[5].title == "World Quests" and localEntries[6].questID == 44,
    "map tasks absent from the quest log should still surface")
local watched = tracker.BuildEntries(84, "watched")
assert(#watched == 2 and watched[1].title == "Dragon Isles" and watched[2].questID == 22,
    "watched scope must include an out-of-zone watched quest without empty headers")

local eventFrame
for _, object in ipairs(objects) do
    if object.events and object.events.PLAYER_LOGIN then eventFrame = object end
end
assert(eventFrame and eventFrame.events.QUEST_LOG_UPDATE)
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
local panel = assert(_G.VignetteRadarQuestTrackerPanel)
assert(panel:IsShown() and panel.clamped and panel.movable and panel.mouseWheel,
    "the tracker must be visible, movable, and scrollable by default")
assert(not panel.accent and panel.statusSurface and panel.count.text == "LOCAL  ·  3 QUESTS",
    "the tracker should use the shared surface without a left accent bar")
assert(panel.height == 211 and panel.rows[1].height == 20 and panel.rows[2].height == 32,
    "header and quest rows must use compact, content-sized layout")
assert(panel.rows[2].entry.questID == 11 and panel.rows[2].name.textColor[2] == .6
    and panel.rows[2].diamond.vertex[2] == .7,
    "difficulty title and radar diamond must use independent colors")
assert(panel.rows[2].center.shown and panel.rows[2].slot.text == "2"
    and panel.rows[2].slot.font[3] == "OUTLINE"
    and panel.rows[2].slot.point[2] == panel.rows[2].diamond
    and panel.rows[2].slot.point[4] == 0,
    "the outlined quest number must be optically centered in the diamond")
panel.rows[2].scripts.OnEnter(panel.rows[2])
assert(highlights[#highlights] == 11, "hover should highlight matching radar diamonds")
panel.rows[2].scripts.OnLeave(panel.rows[2])
assert(highlights[#highlights] == "clear", "leaving should restore radar selection")
panel.rows[2].scripts.OnClick(panel.rows[2])
assert(focused == 11, "clicking a tracker quest should focus that quest")
panel.options.scripts.OnClick(panel.options)
local menu = assert(_G.VignetteRadarQuestTrackerOptions)
assert(menu:IsShown() and #menu.choices == 18,
    "a skinned options dropdown must expose explicit values instead of cycling settings")
local function Choose(key, value)
    for _, choice in ipairs(menu.choices) do
        if choice.key == key and choice.value == value then
            choice.button.scripts.OnClick(choice.button)
            return
        end
    end
    error("missing tracker menu choice: " .. key .. " = " .. tostring(value))
end
Choose("vignetteRadarQuestDots", false)
assert(settings.vignetteRadarQuestDots == false and refreshes == 1)
Choose("vignetteRadarQuestNumbers", true)
assert(settings.vignetteRadarQuestNumbers == true and refreshes == 2)
Choose("vignetteRadarQuestTrackerView", "tray")
local tray = addon.VignetteRadarTray
local slot = assert(tray.GetSlot())
local handle = assert(tray.GetHandle())
local face = radarPanel.field
assert(settings.vignetteRadarQuestTrackerView == "tray" and panel.parent == slot and slot.clips
    and slot.point[1] == "TOPLEFT" and slot.point[2] == face
    and slot.point[3] == "TOPRIGHT" and slot.point[4] == -5 and slot.point[5] == -10
    and panel.point[2] == slot and panel.point[4] == 0 and panel.height == 180
    and handle:IsShown() and handle.parent == face and handle.clickButton == "LeftButtonUp"
    and handle.point[1] == "TOP" and handle.point[2] == face and handle.point[3] == "TOPRIGHT"
    and handle.point[4] == 0 and handle.point[5] == -10 and handle.width == 14 and handle.height == 180
    and handle.grip[1]:IsShown() and not handle.rimGlow:IsShown()
    and panel.clamped == false and not panel.close:IsShown() and panel.lock:IsShown()
    and not panel.statusSurface.edge[4].shown and panel.statusSurface.edge[1].shown
    and panel.statusSurface.edge[1].texCoord[1] == 8 / 256,
    "Tray must dock to the visible radar face with its handle on the face edge")
handle.scripts.OnEnter(handle)
assert(handle.rimGlow:IsShown() and handle.rimGlow.point[1] == "BOTTOMRIGHT"
    and handle.rimGlow.point[2] == face and handle.rimGlow.texCoord[1] > .9
    and handle.dent:IsShown() and handle.dent.gradient[1] == "HORIZONTAL",
    "hovering the dots must light the radar's rounded edge and press it in")
handle.scripts.OnLeave(handle)
assert(not handle.rimGlow:IsShown() and not handle.dent:IsShown() and handle.grip[1]:IsShown(),
    "leaving must return to the dots")
face:SetSize(180, 180)
tracker.Refresh()
assert(panel.height == 160 and panel.footer:IsShown()
    and panel.rows[3]:IsShown() and not panel.rows[4]:IsShown(),
    "the smallest radar tray must scroll before quest rows reach its bottom edge")
face:SetSize(200, 200)
tracker.Refresh()
handle.scripts.OnClick(handle)
slot.scripts.OnUpdate(slot, .23)
assert(settings.vignetteRadarQuestTrackerRetracted == true and not tray.IsOpen()
    and panel.point[4] == -panel.width and not slot:IsShown() and handle:IsShown()
    and panel.options.mouse == false and handle.point[4] == 0,
    "a retracted tray must slide fully back behind the radar edge, leaving the lip at the edge")
assert(tracker.ToggleTray())
slot.scripts.OnUpdate(slot, .23)
assert(settings.vignetteRadarQuestTrackerRetracted == false and slot:IsShown()
    and panel.point[4] == 0 and panel.options.mouse == true,
    "the radar button must slide the same tray back out")
_G.VignetteRadarTraySlot.mouseOver = true
for _, object in ipairs(objects) do
    if object.events and object.events.GLOBAL_MOUSE_DOWN and object.scripts then
        object.scripts.OnEvent(object, "GLOBAL_MOUSE_DOWN")
    end
end
assert(tray.IsOpen(), "a click inside the tray must keep it open")
_G.VignetteRadarTraySlot.mouseOver = false
panel.lock.scripts.OnClick(panel.lock)
for _, object in ipairs(objects) do
    if object.events and object.events.PLAYER_REGEN_DISABLED and object.scripts then
        object.scripts.OnEvent(object, "PLAYER_REGEN_DISABLED")
    end
end
assert(settings.vignetteRadarTrayLocked == true and tray.IsOpen(),
    "a locked tray must stay out through combat")
panel.lock.scripts.OnClick(panel.lock)
for _, object in ipairs(objects) do
    if object.events and object.events.GLOBAL_MOUSE_DOWN and object.scripts then
        object.scripts.OnEvent(object, "GLOBAL_MOUSE_DOWN")
    end
end
assert(settings.vignetteRadarTrayLocked == false and not tray.IsOpen()
    and settings.vignetteRadarQuestTrackerRetracted == true,
    "an unlocked tray must slide in on a click elsewhere")
slot.scripts.OnUpdate(slot, .23)
assert(tracker.ToggleTray())
slot.scripts.OnUpdate(slot, .23)
Choose("vignetteRadarQuestTrackerSide", "top")
assert(slot.point[1] == "BOTTOM" and slot.point[3] == "TOP" and panel.point[1] == "BOTTOM"
    and handle.point[3] == "TOP"
    and not panel.statusSurface.edge[8].shown and panel.statusSurface.edge[1].shown,
    "the upper tray should attach directly above the radar")
settings.vignetteRadarQuestTrackerCollapsed = {
    ["Dragon Isles"] = true, ["Old World"] = true, ["World Quests"] = true,
}
face.left, face.top = 700, 600
Choose("vignetteRadarQuestTrackerSide", "bottom")
assert(panel.height == 180 and slot.point[1] == "TOP"
    and slot.point[3] == "BOTTOM" and not panel.statusSurface.edge[2].shown,
    "the lower tray should keep its edge aligned with the radar")
Choose("vignetteRadarQuestTrackerSide", "left")
assert(slot.point[1] == "TOPRIGHT" and slot.point[3] == "TOPLEFT" and handle.point[3] == "TOPLEFT"
    and not panel.statusSurface.edge[6].shown,
    "the left tray should emerge horizontally from the radar")
face.left = 1300
Choose("vignetteRadarQuestTrackerSide", "right")
assert(panel.actualSide == "left" and slot.point[1] == "TOPRIGHT",
    "Tray must switch to an edge that fits rather than cover the radar")
face.left = 50
slot.scripts.OnUpdate(slot, .06)
assert(panel.actualSide == "right" and slot.point[2] == face,
    "moving the radar must promptly reattach the tray on the clear side")
-- Neither side has a full tray's room (86% each), so it shrinks on the right.
local tightRoom = math.floor(.86 * panel.width)
UIParent:SetSize(200 + 2 * (tightRoom + 8), 500)
face.left, face.top = tightRoom + 8, 340
slot.scripts.OnUpdate(slot, .06)
assert(panel.actualSide == "right" and panel.scale >= .78 and panel.scale < 1
    and slot.point[2] == face and not panel.clamped,
    "a tight screen must fit the docked tray without clamping it over the radar")
UIParent:SetSize(1600, 900)
slot.scripts.OnUpdate(slot, .06)
assert(panel.scale == 1, "restoring screen space must restore full-size tray text")
radarPanel.scale, face.scale = 1.5, 1.5
face.left, face.top = 300, 500
tracker.Refresh()
assert(panel.height == 280 and slot.point[2] == face
    and panel.actualSide == "right",
    "a scaled radar must size and dock its tray against the visible outer border")
radarPanel.scale, face.scale = nil, nil
tracker.Refresh()
radarPanel:Hide()
panel.scripts.OnUpdate(panel, 1)
assert(panel.parent == UIParent and panel.point[2] == UIParent and panel.close:IsShown()
    and not handle:IsShown() and not panel.lock:IsShown() and panel.statusSurface.edge[1].shown,
    "Tray should use the saved floating position while the radar is hidden")
radarPanel:Show()
panel.scripts.OnUpdate(panel, 1)
assert(panel.parent == slot and slot.point[2] == face and handle:IsShown(),
    "Tray should redock as soon as the radar is visible again")
local legendFrame = CreateFrame("Frame", nil, UIParent)
legendFrame:SetSize(220, 300)
local legendReplaced = false
assert(tray.Show({ frame = legendFrame, label = "Radar Legend", isOpen = function() return true end,
    onReplaced = function() legendReplaced = true; legendFrame:Hide() end }))
assert(tray.IsAttached(legendFrame) and not panel:IsShown() and legendFrame.parent == slot
    and panel.parent == UIParent, "the legend must swap the tracker out of the tray")
assert(slot.height == 180 and legendFrame.point[5] == 0,
    "a panel taller than the tracker must be capped to the tracker's height")
legendFrame.scripts.OnMouseWheel(legendFrame, -1)
assert(legendFrame.point[5] == 24, "the mouse wheel must scroll a capped panel")
legendFrame.scripts.OnMouseWheel(legendFrame, -50)
assert(legendFrame.point[5] == 120, "scrolling must stop at the panel's end")
tracker.Refresh()
assert(not panel:IsShown() and tray.IsAttached(legendFrame),
    "a swapped-out tracker must stay hidden and must not take the tray back on refresh")
tracker.Toggle()
assert(tray.IsAttached(panel) and panel:IsShown() and legendReplaced and tray.IsOpen()
    and panel.parent == slot, "the tracker toggle must swap the tracker back in")
Choose("vignetteRadarTrayHandle", "groove")
assert(settings.vignetteRadarTrayHandle == "groove" and handle.groove:IsShown()
    and not handle.grip[1]:IsShown() and handle.point[1] == "CENTER" and handle.point[2] == face,
    "the groove handle must sit inside the radar face edge")
Choose("vignetteRadarTrayHandle", "icon")
assert(handle.icon:IsShown() and not handle.groove:IsShown() and handle.width == 24,
    "the icon handle must use the corner-tool button size")
Choose("vignetteRadarTrayHandle", "lip")
assert(handle.grip[1]:IsShown() and not handle.icon:IsShown(), "the lip handle must come back")
assert(tray.IsAttached(panel) and panel.detach:IsShown(), "the docked tracker must offer a detach button")
local dockedWidth = panel.width
assert(dockedWidth >= 260 and dockedWidth < 306,
    "the docked tray must slide out only as wide as its widest line needs")
panel.detach.scripts.OnClick(panel.detach)
assert(settings.vignetteRadarQuestTrackerView == "floating" and panel.parent == UIParent
    and panel.grip:IsShown() and not tray.IsAttached(panel) and panel.close:IsShown()
    and settings.vignetteRadarQuestTrackerSize.width == dockedWidth,
    "detaching must turn the tray panel into a free, resizable panel of the same size")
panel:SetSize(400, 300)
panel.grip.scripts.OnMouseDown(panel.grip)
panel.grip.scripts.OnMouseUp(panel.grip)
assert(panel.sizingFrom == "BOTTOMRIGHT" and settings.vignetteRadarQuestTrackerSize.width == 400
    and settings.vignetteRadarQuestTrackerSize.height == 300 and panel.rows[1].width == 382
    and panel.height == 300, "resizing must save the size and widen the rows")
-- Floating, the shared panel lock pins it: no drag, no resize grip.
assert(panel.moveLock:IsShown() and panel.moveLock.labelText == "Position Unlocked",
    "a floating tracker shows its position lock")
panel.moveLock.scripts.OnClick(panel.moveLock)
assert(tray.IsPanelLocked("questTracker") and not panel.grip:IsShown(), "locked: the grip hides")
panel.moving = nil
panel.drag.scripts.OnDragStart(panel.drag)
assert(not panel.moving, "locked: the header does not drag")
panel.moveLock.scripts.OnClick(panel.moveLock)
assert(not tray.IsPanelLocked("questTracker") and panel.grip:IsShown(), "unlocked: it moves again")
panel.detach.scripts.OnClick(panel.detach)
assert(settings.vignetteRadarQuestTrackerView == "tray" and tray.IsAttached(panel) and tray.IsOpen()
    and panel.width == panel._fitWidth and panel.width < 306 and not panel.grip:IsShown(), "dock must put the tracker back in the tray")
Choose("vignetteRadarQuestTrackerView", "floating")
assert(settings.vignetteRadarQuestTrackerView == "floating" and panel.close:IsShown()
    and panel.parent == UIParent and panel.point[2] == UIParent and not handle:IsShown(),
    "Floating view should restore its independent saved placement")
panel.close.scripts.OnClick(panel.close)
assert(not panel:IsShown() and settings.vignetteRadarQuestTrackerVisible == false)
assert(tracker.Toggle() and panel:IsShown(), "the settings button should restore the tracker")
-- "Quests Here Only" follows GlanceQuest: Focused, then Watched, then Here.
settings.vignetteRadarAreaQuests = true
addon.VignetteRadarQuestData.IsQuestInArea = function(id) return id == 33 or id == 44 end
addon.VignetteRadarFocus = { GetQuest = function() return 11 end }
if addon.Quests and addon.Quests.Invalidate then addon.Quests.Invalidate() end
local here = tracker.BuildEntries(84, "local")
local shape = {}
for _, entry in ipairs(here) do
    shape[#shape + 1] = entry.kind == "header" and entry.title or tostring(entry.questID)
end
assert(table.concat(shape, ",") == "Focused,11,Watched,22,Here,33,44",
    "Quests Here Only must list focused, then watched, then in-area quests: " .. table.concat(shape, ","))
addon.VignetteRadarQuestData.IsQuestInArea = function() return false end
addon.VignetteRadarFocus = { GetQuest = function() return nil end }
local none = tracker.BuildEntries(84, "local")
for _, entry in ipairs(none) do
    assert(entry.questID ~= 33 and entry.questID ~= 44, "no whole-map fallback when nothing is here")
end
settings.vignetteRadarAreaQuests = nil

-- The tracker is on the shared panel system: its floating spot lives in the
-- panel layout, and the header drag is the shared one.
do
    assert(tray.IsPanel(panel), "the tracker is a registered panel")
    local record = settings.vignetteRadarPanelLayout and settings.vignetteRadarPanelLayout.questTracker
    assert(record and type(record.x) == "number" and settings.vignetteRadarQuestTrackerPosition == nil,
        "the floating spot is saved in the panel layout")
    settings.vignetteRadarQuestTrackerView = "floating"
    panel.moving = nil
    panel.drag.scripts.OnDragStart(panel.drag)
    assert(panel.moving and panel.point[2] == UIParent, "floating: the header drags the panel")
    panel.left, panel.top = 410, 700
    panel.drag.scripts.OnDragStop(panel.drag)
    assert(not panel.moving and settings.vignetteRadarPanelLayout.questTracker.x == 410,
        "the drop saves the new spot")
    panel.left, panel.top = nil, nil
end

-- Round view: docked beside a round radar, the tray curves around it.
do
    settings.vignetteRadarQuestTrackerView = "tray"
    settings.vignetteRadarQuestTrackerRetracted = false
    settings.vignetteRadarQuestTrackerSide = "right"
    settings.vignetteRadarQuestTrackerScope = "all"
    for title in pairs(settings.vignetteRadarQuestTrackerCollapsed) do
        settings.vignetteRadarQuestTrackerCollapsed[title] = nil
    end
    radarPanel.squarePlot = false
    tracker.Refresh()
    assert(tray.IsAttached(panel) and tray.Side() == "right", "docked right of the radar")
    local inset = panel._roundInset
    assert(inset and inset > 0, "the round view tucks part of the tray under the face")
    assert(slot.point[4] == -5 - inset * (slot._fit or 1), "the slot moves under the face by the inset")
    local first, middle, quests = nil, nil, 0
    for index, row in ipairs(panel.rows) do
        if row:IsShown() then
            first = first or row
            if index == 3 then middle = row end
            if row.entry.kind == "quest" then
                quests = quests + 1
                assert(row.name.width >= row.name:GetStringWidth() + 3
                    and row.progress.width >= row.progress:GetStringWidth() + 3,
                    "round view never cuts a quest's text")
            end
        end
    end
    assert(quests > 0, "the round view lays out quest rows")
    assert(first and middle and first.point[4] <= middle.point[4] and middle.point[4] <= 9 + inset,
        "rows near the top sit closer in, following the circle")
    assert(panel.title.point[2] < 11 + inset, "the title follows the curve too")
    settings.vignetteRadarQuestTrackerSide = "left"
    tracker.Refresh()
    if tray.Side() == "left" then
        assert(panel._roundInset and panel.options.point[2] < -58, "left of the radar the icons keep clear")
        assert(panel.title.point[2] == 11, "left of the radar the title stays hard left")
        for _, row in ipairs(panel.rows) do
            if row:IsShown() then
                assert(row.point[4] == 9, "left of the radar every row stays hard left")
                if row.entry.kind == "quest" then
                    assert(row.name.width >= row.name:GetStringWidth() + 3, "left round view never cuts text")
                end
            end
        end
    end
    settings.vignetteRadarQuestTrackerRound = false
    tracker.Refresh()
    assert(panel._roundInset == nil and panel.title.point[2] == 11 and first.point[4] == 9,
        "the setting off keeps the tray straight")
    settings.vignetteRadarQuestTrackerRound = nil
    settings.vignetteRadarQuestTrackerScope = "local"
    radarPanel.squarePlot = nil
    settings.vignetteRadarQuestTrackerSide = "right"
end
print("quest tracker data, identity, interaction, and default visibility ok")
