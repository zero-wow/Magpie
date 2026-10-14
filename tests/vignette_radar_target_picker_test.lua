local sourcePath = arg[1] or "UI/TargetPicker.lua"

local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:GetLeft() return self.left end
function methods:GetRight() return self.right or 100 end
function methods:GetTop() return self.top end
function methods:GetBottom() return self.bottom end
function methods:SetPoint(...) self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end
function methods:ClearAllPoints() self.point, self.points = nil, {} end
function methods:SetAllPoints(...) self.allPoints = { ... } end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function methods:SetFrameStrata(value) self.strata = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:SetFont(...) self.font = { ... } end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetMaxLines(value) self.maxLines = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:RegisterForClicks(...) self.registeredClicks = { ... } end
function methods:IsShown() return self.shown == true end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:Show() self.shown = true end
function methods:Hide()
    self.shown = false
    if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:CreateTexture()
    return setmetatable({ shown = true, parent = self }, { __index = methods })
end
function methods:CreateFontString()
    return setmetatable({ shown = true, parent = self }, { __index = methods })
end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, shown = true }, { __index = methods })
    if name then _G[name] = frame end
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1600, 900)
STANDARD_TEXT_FONT = "fallback.ttf"
local tooltipLines = {}
GameTooltip = {
    SetOwner = function() tooltipLines = {} end,
    SetText = function(_, value) tooltipLines[#tooltipLines + 1] = value end,
    AddLine = function(_, value) tooltipLines[#tooltipLines + 1] = value end,
    Show = function() end, Hide = function() end,
}
GetTime = function() return 1000 end

local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
-- The real Style (default theme) supplies the bundled font helper.
local styleHost = { GetSettings = function() return {} end }
assert(loadfile("UI/Style.lua"))("VignetteRadar", styleHost)
addon.VignetteRadarStyle = styleHost.VignetteRadarStyle
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile(sourcePath))("VignetteRadar", addon)
local picker = assert(addon.VignetteRadarTargetPicker, "target picker must publish its API")
local changes = 0
picker.SetChangeCallback(function() changes = changes + 1 end)
local targets = {
    { key = "a", name = "Alpha Rare", category = "rare", distance = 42, red = 1, green = 0.24, blue = 0.20 },
    { key = "b", name = "Buried Cache", category = "treasure", distance = 73, red = 1, green = 0.68, blue = 0.16 },
    { key = "c", name = "Event One", category = "event", distance = 90 },
    { key = "d", name = "Event Two", category = "event", distance = 105 },
    { key = "e", name = "Other One", category = "other", distance = 120 },
    { key = "f", name = "Other Two", category = "other", distance = 145 },
}
picker.SetProvider(function() return targets end)

local anchor = CreateFrame("Frame", nil, UIParent)
anchor.right = 500
assert(picker.Toggle(anchor) and picker.IsShown(), "focus button must open the attached target list")
local panel = assert(_G.VignetteRadarTargetPickerPanel, "target list needs a stable global frame name")
assert(panel.width == 250 and panel.height == 258 and panel.clamped == true,
    "specific target picker must stay compact and screen-safe")
assert(panel.face.texture == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga"
    and panel.edge.texture == "Interface\\AddOns\\Magpie\\Media\\radar-rounded-border.tga"
    and panel.rows[1].face.texture == panel.face.texture
    and panel.rows[1].selection.texture == panel.face.texture
    and panel.clear.art.texture:find("button%-icons") ~= nil
    and panel.clear.icon == "eye" and panel.next.icon == "next" and panel.previous.icon == "back"
    and panel.backdrop == nil and panel.rows[1].backdrop == nil,
    "the focus picker must use the radar's rounded image surfaces instead of square backdrops")
assert(panel.point[1] == "TOPLEFT" and panel.point[3] == "TOPRIGHT" and panel.point[4] == 8,
    "specific target picker must open outside the radar with a gutter")
assert(panel.rows[1].target.key == "a" and panel.rows[5].target.key == "e" and panel.next:IsShown(),
    "first focus page must show five current detections with pagination")
assert(panel.rows[1].name.text == "Alpha Rare" and panel.rows[1].meta.text:find("42 YD", 1, true),
    "target rows must identify the vignette and show its distance")
assert(panel.rows[1].registeredClicks[2] == "RightButtonUp",
    "target rows must receive right clicks for ignore actions")
assert(panel.rows[1].name.width == 121 and panel.rows[1].meta.width == 132
    and panel.rows[1].action.width == 49 and panel.subtitle.width == 165,
    "names and metadata must be bounded away from row actions and the panel header")
addon.VignetteRadarStyle = { SetFont = addon.VignetteRadarStyle.SetFont, Color = function(slot)
    if slot == "accent" then return .7, .4, 1 end
    return .02, .03, .04
end }
picker.Refresh()
assert(panel.edge.vertexColor[1] == .7 and panel.title.textColor[2] == .4
    and panel.face.vertexColor[3] == .04 * 2.7,
    "the rounded focus popup must follow the active radar palette")

panel.rows[1].scripts.OnClick(panel.rows[1])
assert(picker.GetFocus() == "a" and picker.GetFocusName() == "Alpha Rare" and changes == 1,
    "clicking a row must isolate that exact active vignette")
assert(panel.rows[1].selection:IsShown() and panel.rows[1].action.text == "ACTIVE",
    "focused vignette needs a clear selected state")
panel.clear.scripts.OnClick(panel.clear)
assert(picker.GetFocus() == nil and changes == 2, "SHOW ALL must clear the specific target filter")

panel.next.scripts.OnClick(panel.next)
assert(panel.rows[1].target.key == "f" and not panel.next:IsShown() and panel.previous:IsShown(),
    "paging must expose remaining detections without extending the panel")
panel.rows[1].scripts.OnClick(panel.rows[1])
assert(picker.GetFocus() == "f", "a target on a later page must be focusable")
targets = { targets[1], targets[2] }
assert(picker.ValidateTargets(targets), "a vanished focused target must be cleared")
assert(picker.GetFocus() == nil, "stale target focus must never leave the radar blank")

local longName = ("Very Long Vignette Name "):rep(6)
targets = {
    { key = "seen", name = longName, category = "rare", distance = 28, stale = true, lastSeenAt = 950 },
    { key = "live", name = "Live Target", category = "event", distance = 35, favorite = true },
}
local favorite = { seen = true }
addon.VignetteRadarFeatures = {
    IsFavorite = function(target) return favorite[target.key] == true end,
}
picker.SetProvider(function() return targets end)
assert(panel.rows[1].name.text == longName and panel.rows[1].name.maxLines == 1,
    "long target names must remain single-line and clipped within their fixed width")
assert(panel.rows[1].favorite:IsShown() and panel.rows[1].meta.text:find("50S AGO", 1, true),
    "favorite and last-seen age must appear directly in a stale row")
assert(not panel.rows[2].favorite:IsShown(), "feature API must determine favorite state when available")
panel.rows[1].scripts.OnEnter(panel.rows[1])
local tip = table.concat(tooltipLines, "\n")
assert(tip:find("Last seen 50s ago", 1, true)
    and not tip:find("Shift-left-click", 1, true) and tip:find("Alt-left-click", 1, true)
    and tip:find("Right-click", 1, true) and tip:find("Shift-right-click", 1, true),
    "stale tooltip must explain age and available gestures without advertising live navigation")

picker.SetFocus("seen", longName)
assert(not picker.ValidateTargets(targets) and picker.GetFocus() == "seen",
    "a stale target must keep focus while it remains selectable")
local calls = {}
addon.HandleVignetteClick = function(target, button)
    calls[#calls + 1] = { target = target, button = button }
    if button == "LeftButton" then picker.SetFocus(target.key, target.name) end
    if button == "RightButton" then targets = { targets[2] } end
    if button == "LeftButton" and target.key == "seen" then favorite.seen = false end
end
panel.rows[1].scripts.OnClick(panel.rows[1], "LeftButton")
panel.rows[1].scripts.OnClick(panel.rows[1], "RightButton")
assert(picker.ValidateTargets(targets) and picker.GetFocus() == nil,
    "focus must clear after a stale target leaves the selectable list")
panel.rows[1].scripts.OnClick(panel.rows[1], "LeftButton")
assert(#calls == 3 and calls[1].target.key == "seen" and calls[1].button == "LeftButton"
    and calls[2].button == "RightButton" and calls[3].target.key == "live",
    "row clicks must forward the target and mouse button to the shared action handler")
assert(not panel.rows[1].favorite:IsShown(), "rows must refresh after the shared action handler changes state")
assert(picker.GetFocus() == "live", "shared left-click handling must be able to focus a live row")
local shiftDown, altDown = false, false
IsShiftKeyDown = function() return shiftDown end
IsAltKeyDown = function() return altDown end
local gestures = {}
addon.HandleVignetteClick = function(target, button)
    gestures[#gestures + 1] = { key = target.key, button = button,
        shift = IsShiftKeyDown(), alt = IsAltKeyDown() }
end
shiftDown = true
panel.rows[1].scripts.OnClick(panel.rows[1], "LeftButton")
shiftDown, altDown = false, true
panel.rows[1].scripts.OnClick(panel.rows[1], "LeftButton")
shiftDown, altDown = false, false
panel.rows[1].scripts.OnClick(panel.rows[1], "RightButton")
shiftDown = true
panel.rows[1].scripts.OnClick(panel.rows[1], "RightButton")
assert(#gestures == 4 and gestures[1].shift and gestures[1].button == "LeftButton"
    and gestures[2].alt and gestures[2].button == "LeftButton"
    and gestures[3].button == "RightButton" and not gestures[3].shift
    and gestures[4].button == "RightButton" and gestures[4].shift,
    "shift-left, alt-left, right, and shift-right must reach the shared handler unchanged")
addon.HandleVignetteClick = nil
addon.VignetteRadarFeatures = nil
picker.ClearFocus()
targets = { { key = "fallback", name = "Fallback", favorite = true } }
picker.SetProvider(function() return targets end)
assert(panel.rows[1].favorite:IsShown(), "favorite marker must work without the optional features module")
panel.rows[1].scripts.OnClick(panel.rows[1], "RightButton")
assert(picker.GetFocus() == nil, "standalone fallback must leave right-click inactive")
panel.rows[1].scripts.OnClick(panel.rows[1], "LeftButton")
assert(picker.GetFocus() == "fallback", "standalone left-click must retain focus behavior")
picker.ClearFocus()
targets = {
    { key = "boss", name = "World Boss", category = "rare", isWorldBoss = true,
        distance = 40, red = 1, green = 0.18, blue = 0.12 },
    { key = "rare", name = "Rare Enemy", category = "rare",
        distance = 52, red = 0.78, green = 0.88, blue = 1 },
    { key = "seen-boss", name = "Seen Boss", category = "rare", isWorldBoss = true,
        stale = true, lastSeenAt = 990, distance = 60 },
    { key = "treasure", name = "Chest", category = "treasure", distance = 65 },
}
picker.SetProvider(function() return targets end)
assert(panel.rows[1].dot.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
    and panel.rows[1].dot.width == 14 and panel.rows[1].dot.vertexColor[2] == 0.18
    and panel.rows[1].meta.text:find("WORLD BOSS", 1, true),
    "only explicitly marked bosses must use the large red skull and world boss label")
panel.rows[1].scripts.OnEnter(panel.rows[1])
assert(table.concat(tooltipLines, "\n"):find("World boss", 1, true),
    "boss tooltip must identify the world boss plainly")
assert(panel.rows[2].dot.texture == panel.rows[1].dot.texture and panel.rows[2].dot.width == 12
    and panel.rows[2].dot.vertexColor[1] == 0.78
    and panel.rows[2].meta.text:find("RARE", 1, true)
    and not panel.rows[2].meta.text:find("BOSS", 1, true),
    "an ordinary rare must use the smaller silver skull without being labeled a boss")
panel.rows[2].scripts.OnEnter(panel.rows[2])
assert(table.concat(tooltipLines, "\n"):find("Rare enemy", 1, true),
    "rare tooltip must describe an ordinary rare plainly")
assert(panel.rows[3].meta.text:find("WORLD BOSS", 1, true)
    and panel.rows[3].meta.text:find("10S AGO", 1, true),
    "a stale boss row must retain its boss label and last-seen age")
assert(panel.rows[4].dot.texture == "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    and panel.rows[4].dot.width == 7,
    "non-rare rows must retain their compact category dot")
assert(picker.Toggle(anchor) == false and not picker.IsShown(), "focus button must close the target list")

UIParent:SetSize(800, 600)
local squat = CreateFrame("Frame", nil, UIParent)
squat:SetSize(374, 230)
squat.left, squat.right, squat.top, squat.bottom = 213, 587, 415, 185
assert(picker.Toggle(squat) and picker.IsShown(), "target picker must open from a Squat panel anchor")
assert(squat.point[1] == "TOPLEFT" and squat.point[2] == UIParent and squat.point[4] == 164
    and squat.point[5] == -185,
    "a centered Squat panel must shift only enough to leave the picker an 8px right gutter")
assert(panel.point[1] == "TOPLEFT" and panel.point[2] == squat and panel.point[3] == "TOPRIGHT"
    and panel.point[4] == 8,
    "the shifted Squat anchor must place the picker beside the panel without overlap")
squat.left, squat.right = 164, 538
assert(picker.Reanchor(squat) and panel.point[1] == "TOPLEFT" and panel.point[2] == squat
    and panel.point[3] == "TOPRIGHT" and panel.point[4] == 8,
    "an open target picker must reanchor against the shifted Squat panel")
assert(picker.Toggle(squat) == false, "target picker Squat toggle must close")

local radarField = CreateFrame("Frame", nil, UIParent)
radarField:SetSize(200, 200)
radarField.left, radarField.right, radarField.top, radarField.bottom = 150, 350, 325, 125
radarField:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
_G.VignetteRadarPanel = { field = radarField }
UIParent:SetSize(500, 450)
assert(picker.Toggle(radarField), "focus popup must still open from a tightly placed radar-only field")
assert(radarField.point[1] == "CENTER" and panel.point[2] == UIParent,
    "a cramped focus popup must center itself without detaching the radar field")
picker.Hide()

do
    -- A centered radar with no clear side is moved for the picker, then put back on close.
    UIParent:SetSize(800, 600)
    local radar = CreateFrame("Frame", nil, UIParent)
    radar.left, radar.right, radar.top, radar.bottom = 213, 587, 500, 100
    radar:SetSize(374, 400)
    assert(picker.Toggle(radar) == true)
    local moved = assert(radar.point, "a boxed-in radar must be moved to make room")
    assert(moved[1] == "TOPLEFT" and moved[4] ~= 213)
    radar.left = moved[4]
    picker.Hide()
    assert(radar.point and radar.point[4] == 213 and radar.point[5] == 500 - 600,
        "closing the picker must restore the radar to where it was")
    -- If the player dragged the radar meanwhile, closing must not yank it back.
    radar.left = 213
    assert(picker.Toggle(radar) == true)
    radar.left = 50
    radar.point = { "TOPLEFT", UIParent, "TOPLEFT", 50, -100 }
    picker.Hide()
    assert(radar.point[4] == 50, "a radar moved by the player must stay where it was put")
    UIParent:SetSize(1600, 900)
end

io.write("vignette radar target picker tests passed\n")
