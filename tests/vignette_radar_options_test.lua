local sourcePath = arg[1] or "UI/Options.lua"

local objects = {}
local methods = {}
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
function methods:SetAllPoints(...) self.allPoints = { ... } end
function methods:ClearAllPoints() self.points = {} end
function methods:SetFontString(value) self.fontString = value end
function methods:SetText(value) self.text = value; if self.fontString then self.fontString:SetText(value) end end
function methods:SetFont(...) self.font = { ... } end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetBackdropColor(...) self.backdropColor = { ... } end
function methods:SetBackdropBorderColor(...) self.backdropBorderColor = { ... } end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetThickness(value) self.thickness = value end
function methods:SetStartPoint(...)
    assert(select("#", ...) == 4, "line endpoints take anchor, frame, x, y")
    self.startPoint = { ... }
    assert(type(self.startPoint[3]) == "number" and type(self.startPoint[4]) == "number")
end
function methods:SetEndPoint(...)
    assert(select("#", ...) == 4, "line endpoints take anchor, frame, x, y")
    self.endPoint = { ... }
    assert(type(self.endPoint[3]) == "number" and type(self.endPoint[4]) == "number")
end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetJustifyH(value) self.justifyH = value end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetEnabled(value) self.enabled = value end
function methods:LockHighlight() self.highlightLocked = true end
function methods:UnlockHighlight() self.highlightLocked = false end
function methods:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
function methods:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:SetFrameStrata(value) self.strata = value end
function methods:Show() self.shown = true; if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown == true end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:CreateTexture()
    local texture = setmetatable({ kind = "Texture", parent = self }, { __index = methods })
    objects[#objects + 1] = texture
    return texture
end
function methods:CreateLine()
    local line = setmetatable({ kind = "Line", parent = self }, { __index = methods })
    objects[#objects + 1] = line
    return line
end
function methods:CreateFontString()
    local label = setmetatable({ kind = "FontString", parent = self }, { __index = methods })
    objects[#objects + 1] = label
    return label
end
function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent, enabled = true }, { __index = methods })
    objects[#objects + 1] = frame
    if name then _G[name] = frame end
    return frame
end

UIParent = CreateFrame("Frame", "UIParent")
local registered, opened
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        assert(frame.name == name)
        return { GetID = function() return 42 end }
    end,
    RegisterAddOnCategory = function(value) registered = value end,
    OpenToCategory = function(id) opened = id end,
}

local db = { vignetteRadarCompartment = true }
local quickOpens, quickToggles = {}, 0
local compartment
AddonCompartmentFrame = { RegisterAddon = function(_, entry) compartment = entry end }
local addon = {
    GetSettings = function() return db end,
    VignetteRadarQuickConfig = {
        OpenPage = function(name) quickOpens[#quickOpens + 1] = name end,
        Toggle = function() quickToggles = quickToggles + 1 end,
    },
}
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Controls.lua"))("VignetteRadar", addon)
assert(loadfile(sourcePath))("VignetteRadar", addon)
local event
for _, object in ipairs(objects) do
    if object.events and object.events.PLAYER_LOGIN then event = object end
end
assert(event and event.scripts.OnEvent)
event.scripts.OnEvent(event)
local panel = assert(_G.VignetteRadarOptionsPanel)
assert(registered and panel.name == "Magpie",
    "the Blizzard AddOns canvas must still be registered")
assert(panel.title.text == "Magpie" and panel.description.text
    and not panel.description.text:find("\n", 1, true),
    "the canvas shows a title and one line of text")
assert(panel.pages == nil and panel.pageButtons == nil,
    "the canvas must not duplicate QuickConfig's settings")
local checkboxes = 0
for _, object in ipairs(objects) do
    if object.parent == panel and object.kind == "CheckButton" then checkboxes = checkboxes + 1 end
end
assert(checkboxes == 0, "no setting controls live on the canvas")
local open = assert(panel.openButton)
assert(open.text == "Open Magpie Settings" or (open.fontString
    and open.fontString.text == "Open Magpie Settings"))
open.scripts.OnClick(open)
assert(quickOpens[1] == "Radar", "the canvas button must open QuickConfig")

addon.OpenOptions()
assert(quickOpens[2] == "Radar" and opened == nil,
    "OpenOptions must open QuickConfig, not the Blizzard canvas")
compartment.func()
assert(quickToggles == 1, "the compartment entry must toggle QuickConfig")
addon.VignetteRadarQuickConfig = nil
addon.OpenOptions()
assert(opened == 42, "without QuickConfig, OpenOptions falls back to the canvas")
compartment.func()
assert(opened == 42 and #quickOpens == 2, "the compartment falls back to OpenOptions")
local Controls = addon.VignetteRadarControls
local themeButton = Controls.Button(panel, "Theme Probe", 80, 20)
local themeRepaints = 0
themeButton.RefreshAppearance = function() themeRepaints = themeRepaints + 1 end
local accent = { .1, .2, .3 }
addon.VignetteRadarStyle = { revision = 1, Color = function() return accent[1], accent[2], accent[3] end }
Controls.RefreshTheme()
assert(themeRepaints == 1, "the first theme refresh must repaint controls")
Controls.RefreshTheme()
assert(themeRepaints == 1, "an unchanged theme revision must skip the control repaint loop")
addon.VignetteRadarStyle.revision = 2
Controls.RefreshTheme()
assert(themeRepaints == 2, "a new theme revision must repaint controls")
accent[1] = .4
Controls.RefreshTheme()
assert(themeRepaints == 3, "an accent change without a revision bump must still repaint")
addon.VignetteRadarStyle = nil
io.write("vignette radar options tests passed\n")
