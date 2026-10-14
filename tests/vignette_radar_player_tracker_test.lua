local path = arg[1] or "UI/PlayerTracker.lua"
local objects = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetAllPoints(value) self.allPoints = value end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetMovable(value) self.movable = value end
function methods:RegisterForDrag(value) self.drag = value end
function methods:RegisterEvent(value) self.events = self.events or {}; self.events[value] = true end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown == true end
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetVertexColor(...) self.color = { ... } end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function methods:SetFont(...) self.font = { ... } end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetTextInsets(...) self.insets = { ... } end
function methods:SetAutoFocus(value) self.autoFocus = value end
function methods:SetMaxLetters(value) self.maxLetters = value end
function methods:ClearFocus() self.focused = false end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:CreateTexture()
    local texture = setmetatable({ kind = "Texture", parent = self }, { __index = methods })
    objects[#objects + 1] = texture
    return texture
end
function methods:CreateFontString()
    local label = setmetatable({ kind = "FontString", parent = self }, { __index = methods })
    objects[#objects + 1] = label
    return label
end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent }, { __index = methods })
    objects[#objects + 1] = frame
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
STANDARD_TEXT_FONT = "default.ttf"
local now, reads = 1, 0
GetTime = function() return now end
issecretvalue = function() return false end
local players = {
    target = { name = "Soleet", realm = "Wyrmrest Accord", x = 102, y = 101 },
    nameplate1 = { name = "Soleet", realm = "Wyrmrest Accord", x = 102, y = 101 },
}
UnitIsPlayer = function(unit) return players[unit] ~= nil end
UnitFullName = function(unit)
    local player = players[unit]
    return player and player.name, player and player.realm
end
UnitPosition = function(unit)
    reads = reads + 1
    local player = players[unit]
    return player and player.x, player and player.y, 0, player and 42
end
local plate = CreateFrame("Frame")
plate.unitToken = "nameplate1"
plate.UnitFrame = CreateFrame("Frame", nil, plate)
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return unit == "nameplate1" and plate or nil end,
    GetNamePlates = function() return { plate } end,
}
local settings = {}
local addon = {
    GetSettings = function() return settings end,
    VignetteRadarControls = {
        PopupSurface = function(frame) frame.surface = true end,
        RefreshPopupSurface = function() end,
        Button = function(parent, title, width, height)
            local button = CreateFrame("Button", nil, parent)
            button:SetSize(width, height)
            button:SetText(title)
            return button
        end,
    },
}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile(path))("VignetteRadar", addon)
local tracker = addon.VignetteRadarPlayerTracker
assert(next(settings.vignetteRadarMarkedPlayers or {}) == nil
    and settings.vignetteRadarPlayerTrackerSeeded == nil,
    "a fresh profile must start with no marked players (no shipped seed)")
assert(tracker.Mark("Soleet-WyrmrestAccord")
    and settings.vignetteRadarMarkedPlayers["soleet-wyrmrestaccord"] == "Soleet-WyrmrestAccord",
    "marking a character-realm must persist it")
local events = tracker._EventFrame
assert(events.events.NAME_PLATE_UNIT_ADDED and events.events.NAME_PLATE_UNIT_REMOVED
    and events.events.PLAYER_TARGET_CHANGED and events.events.UPDATE_MOUSEOVER_UNIT,
    "tracking must react to visible unit tokens")
events.scripts.OnEvent(events, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(tracker.IsDetecting(), "visible marked players must light the radar shortcut")
local nameplateSkull
for _, object in ipairs(objects) do
    if object.parent == plate and object.kind == "Frame" and object.width == 25 then
        nameplateSkull = object
    end
end
assert(nameplateSkull and nameplateSkull:IsShown(),
    "a matched visible nameplate must immediately receive the skull")
local player = { mapID = 777, worldX = 100, worldY = 100, instanceID = 42 }
local sightings = tracker.GetSightings(player)
assert(#sightings == 1 and sightings[1].name == "Soleet-WyrmrestAccord"
    and sightings[1].worldX == 102 and sightings[1].worldY == 101,
    "the radar must use the detected unit's actual position")
local firstReads = reads
assert(#tracker.GetSightings(player) == 1 and reads == firstReads,
    "positions should be cached between radar paints")
local field = CreateFrame("Frame")
local function Project(dx, dy) return dx * 10, dy * 10 end
tracker.RenderRadar(field, player, 100, 70, 0, Project)
local radarSkull
for _, object in ipairs(objects) do
    if object.parent == field and object.kind == "Frame" and object.width == 23 then
        radarSkull = object
    end
end
assert(radarSkull and radarSkull:IsShown() and radarSkull.point[4] == 20
    and radarSkull.point[5] == 10, "the radar skull must plot the observed position")
local frame = tracker.Open()
assert(frame.surface and frame:IsShown() and frame.rows[1].mark.label
    == "Soleet-WyrmrestAccord", "the themed manager must show the saved player")
players.target = { name = "Another", realm = "Other Realm", x = 104, y = 100 }
assert(tracker.MarkTarget() and settings.vignetteRadarMarkedPlayers["another-otherrealm"],
    "Mark Current Target must persist the character and realm")
assert(tracker.Remove("Soleet-WyrmrestAccord") and not nameplateSkull:IsShown(),
    "removing a mark must immediately clear its nameplate skull")
assert(not tracker.Mark("Soleet") and tracker.Mark("Soleet-WyrmrestAccord"),
    "manual entry needs a realm to avoid false matches")
assert(tracker.Remove("Another-OtherRealm"))
now = now + 1
players.nameplate1 = nil
events.scripts.OnEvent(events, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(not tracker.IsDetecting(), "the shortcut must clear when no marked player is visible")
assert(#tracker.GetSightings(player) == 0 and not nameplateSkull:IsShown(),
    "leaving detection range must remove both skulls without a stale location")
tracker.HideRadar()
assert(not radarSkull:IsShown())
io.write("vignette radar player tracker tests passed\n")
