local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarConstellationSettings = API

local popup
local WIDTH, HEIGHT = 406, 550
local MODE_HELP = {
    live = "Only things the game detects right now. They leave when detection ends.",
    pack = "Possible places saved by your chosen map pack. A saved spot may be empty.",
    mixed = "Both kinds. A real detection replaces its matching saved guess.",
}

local function Settings() return addon.GetSettings() end
local function HUD() return addon.VignetteRadarConstellation end
local function Controls() return addon.VignetteRadarControls end

local function Text(parent, value, x, y, width, height, size, accent)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size or 10, "")
    label:SetSize(width, height)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetTextColor(accent and .30 or .72, accent and .95 or .81,
        accent and .78 or .82, 1)
    label:SetText(value)
    if accent and popup and popup.accentLabels then
        popup.accentLabels[#popup.accentLabels + 1] = label
    end
    return label
end

local function Button(parent, caption, x, y, width, callback)
    local button = Controls().Button(parent, caption, width, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetScript("OnClick", callback)
    return button
end

local function StepButton(parent, caption, x, y, callback)
    local controls = Controls()
    local button = controls.IconButton and controls.IconButton(parent, caption, 27, 26)
        or controls.Button(parent, caption, 27, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetScript("OnClick", callback)
    return button
end

local function Highlight(button, selected)
    if button.LockHighlight and button.UnlockHighlight then
        if selected then button:LockHighlight() else button:UnlockHighlight() end
    elseif button.SetSelected then
        button:SetSelected(selected)
    end
end

local function SetOption(key, value)
    local hud = HUD()
    if key == "vignetteRadarConstellationEnabled" then
        hud.SetEnabled(value)
    elseif key == "vignetteRadarConstellationSourceMode" then
        hud.SetSourceMode(value)
    else
        Settings()[key] = value
        addon.ValidateSettings() -- apply the same bounds as a saved-profile reload
        hud.Refresh()
    end
    if popup then popup:Refresh() end
end

local function AddToggle(page, title, help, key, y)
    Text(page, title, 16, y, 310, 20, 11, true)
    Text(page, help, 16, y - 21, 310, 30, 10)
    local button = Controls().Checkbox(page)
    button:SetPoint("TOPLEFT", page, "TOPLEFT", 355, y)
    button:SetScript("OnClick", function()
        SetOption(key, not Settings()[key])
    end)
    local hit = CreateFrame("Button", nil, page)
    hit:SetPoint("TOPLEFT", page, "TOPLEFT", 16, y)
    hit:SetSize(310, 44)
    hit:SetScript("OnClick", function() SetOption(key, not Settings()[key]) end)
    popup.toggles[#popup.toggles + 1] = { key = key, button = button }
    return button
end

local function NextValue(values, current, direction)
    if direction > 0 then
        for _, value in ipairs(values) do
            if value > current + .001 then return value end
        end
    else
        for index = #values, 1, -1 do
            if values[index] < current - .001 then return values[index] end
        end
    end
end

local function AddStepper(page, title, help, key, y, values, format)
    Text(page, title, 16, y, 250, 20, 11, true)
    Text(page, help, 16, y - 21, 246, 30, 10)
    local value = Text(page, "", 305, y + 1, 55, 25, 10)
    value:SetJustifyH("CENTER")
    local minus = StepButton(page, "−", 274, y, function()
        local nextValue = NextValue(values, Settings()[key], -1)
        if nextValue then SetOption(key, nextValue) end
    end)
    local plus = StepButton(page, "+", 363, y, function()
        local nextValue = NextValue(values, Settings()[key], 1)
        if nextValue then SetOption(key, nextValue) end
    end)
    popup.steppers[#popup.steppers + 1] = {
        key = key, values = values, format = format, value = value,
        minus = minus, plus = plus,
    }
end

local function Page(name)
    local page = CreateFrame("Frame", nil, popup)
    page:SetSize(WIDTH, HEIGHT - 128)
    page:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, -112)
    page:Hide()
    popup.pages[name] = page
    return page
end

local function BuildShowPage()
    local page = Page("Show")
    AddToggle(page, "Show the constellation", "Turns this floating map on or off.",
        "vignetteRadarConstellationEnabled", -8)
    Text(page, "Which dots should appear?", 16, -68, 350, 19, 11, true)
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(.45, .76, .70, .20)
    line:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -89)
    line:SetSize(374, 1)
    popup.modes = {}
    for index, entry in ipairs({ { "live", "Live Only" },
        { "pack", "Map Pack Only" }, { "mixed", "Mixed" } }) do
        local button = Button(page, entry[2], 16 + (index - 1) * 128, -99, 118,
            function() SetOption("vignetteRadarConstellationSourceMode", entry[1]) end)
        popup.modes[index] = { button = button, value = entry[1] }
    end
    popup.modeHelp = Text(page, "", 16, -137, 374, 62, 10)
    AddStepper(page, "How many dots?", "A lower limit keeps a busy area easier to read.",
        "vignetteRadarConstellationMaxPoints", -222, { 12, 24, 36 },
        function(value) return tostring(value) end)
    Text(page, "Hold a key to inspect icons", 16, -282, 365, 19, 11, true)
    Text(page, "While held, hover for details or click to focus and show a trail.",
        16, -303, 374, 23, 9)
    popup.modifiers = {}
    for index, entry in ipairs({ { "ctrl", "Ctrl" }, { "shift", "Shift" },
        { "alt", "Alt" }, { "off", "Off" } }) do
        local button = Button(page, entry[2], 16 + (index - 1) * 96, -329, 86,
            function() SetOption("vignetteRadarConstellationInteractModifier", entry[1]) end)
        popup.modifiers[index] = { button = button, value = entry[1] }
    end
end

local function BuildLooksPage()
    local page = Page("Looks")
    AddStepper(page, "Icon size", "Makes the symbols easier to spot.",
        "vignetteRadarConstellationIconSize", -10, { 24, 28, 32, 36 },
        function(value) return tostring(value) end)
    AddStepper(page, "Icon visibility", "Lower makes object symbols more see-through.",
        "vignetteRadarConstellationOpacity", -77,
        { .2, .35, .5, .65, .75, .9, 1 },
        function(value) return math.floor(value * 100 + .5) .. "%" end)
    AddStepper(page, "Sphere size", "Makes the whole floating map bigger or smaller.",
        "vignetteRadarConstellationSize", -144,
        { 360, 420, 520, 620, 720, 800 },
        function(value) return tostring(value) end)
    AddStepper(page, "Move it up or down", "The middle is near your character; this shifts it vertically.",
        "vignetteRadarConstellationOffsetY", -211,
        { -.20, -.10, -.05, 0, .05, .10, .20 },
        function(value)
            if value == 0 then return "Center" end
            return math.floor(math.abs(value) * 100 + .5)
                .. (value > 0 and "% up" or "% down")
        end)
    Button(page, "Reset Position", 16, -285, 154, function()
        SetOption("vignetteRadarConstellationOffsetY", -.05)
    end)
    Text(page, "The map stays click-through until you hold your chosen inspection key.",
        16, -328, 374, 30, 10)
end

local function BuildLayersPage()
    local page = Page("Layers")
    AddToggle(page, "Show range rings", "Three flat circles show distance from your dot.",
        "vignetteRadarConstellationShowRings", -8)
    AddStepper(page, "Ring visibility", "How faint or bright those distance circles look.",
        "vignetteRadarConstellationRingOpacity", -65,
        { .1, .25, .4, .55, .75, .9, 1 },
        function(value) return math.floor(value * 100 + .5) .. "%" end)
    AddToggle(page, "Show globe lines", "The outer circle and curved lines frame the map.",
        "vignetteRadarConstellationShowSphere", -122)
    AddStepper(page, "Globe visibility", "How faint or bright the curved globe lines look.",
        "vignetteRadarConstellationSphereOpacity", -179,
        { .1, .25, .4, .55, .75, .9, 1 },
        function(value) return math.floor(value * 100 + .5) .. "%" end)
    AddToggle(page, "Show icon bases", "Small ground anchors sit directly below symbols.",
        "vignetteRadarConstellationShowBases", -236)
    AddStepper(page, "Trail visibility", "How bright the moving dots and their guide line look.",
        "vignetteRadarConstellationTrailOpacity", -293,
        { .1, .25, .4, .55, .75, .9, 1 },
        function(value) return math.floor(value * 100 + .5) .. "%" end)
    AddToggle(page, "Show readout", "Mode and guidance words above and below the sphere.",
        "vignetteRadarConstellationShowReadout", -350)
end

local function BuildDirectionPage()
    local page = Page("Direction")
    AddToggle(page, "Center steeple", "A tiny arrow sits on your dot and shows where you face.",
        "vignetteRadarConstellationCenterArrow", -8)
    AddToggle(page, "Facing line", "A short line extends from the steeple in that direction.",
        "vignetteRadarConstellationHeadingLine", -65)
    AddStepper(page, "Center cue visibility", "Lower makes your arrow and facing line more see-through.",
        "vignetteRadarConstellationCenterOpacity", -124,
        { .2, .35, .5, .72, .85, 1 },
        function(value) return math.floor(value * 100 + .5) .. "%" end)
    AddStepper(page, "Facing line length", "How far the short line extends past the little arrow.",
        "vignetteRadarConstellationHeadingLength", -185,
        { .10, .18, .24, .32, .42, .50 },
        function(value) return math.floor(value * 45 + .5) .. " px" end)
    AddToggle(page, "Trail to selected item", "Moving dots lead toward the point you focused.",
        "vignetteRadarConstellationGuidance", -248)
    AddToggle(page, "Reduce motion", "Stops the moving dots and opening fade.",
        "vignetteRadarConstellationReducedMotion", -307)
end

local function EnsurePopup()
    if popup or not UIParent then return popup end
    popup = CreateFrame("Frame", "VignetteRadarConstellationMenu", UIParent, "BackdropTemplate")
    popup:SetSize(WIDTH, HEIGHT)
    popup:SetFrameStrata("DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarConstellationMenu"
    end
    popup.pages, popup.tabs, popup.toggles, popup.steppers = {}, {}, {}, {}
    popup.accentLabels = {}
    if Controls().PopupSurface then
        Controls().PopupSurface(popup)
    else
        popup:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    popup.bead = popup:CreateTexture(nil, "OVERLAY")
    popup.bead:SetSize(5, 5)
    popup.bead:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -19)
    popup.bead:SetTexture("Interface\\Buttons\\WHITE8X8")
    popup.title = Text(popup, "CONSTELLATION", 28, -14, 315, 24, 12, true)
    Text(popup, "A floating map around you. Object height is unknown.",
        16, -40, 370, 20, 10)
    popup.headerLine = popup:CreateTexture(nil, "ARTWORK")
    popup.headerLine:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -65)
    popup.headerLine:SetSize(374, 1)
    popup.close = addon.VignetteRadarIconButton.Create(popup, "close", { size = 20,
        label = "Close", onClick = function() popup:Hide() end })
    popup.close:SetPoint("TOPLEFT", popup, "TOPLEFT", 368, -15)
    for index, name in ipairs({ "Show", "Looks", "Layers", "Direction" }) do
        popup.tabs[name] = Button(popup, name, 16 + (index - 1) * 96,
            -78, 86, function() popup:SelectTab(name) end)
    end
    BuildShowPage()
    BuildLooksPage()
    BuildLayersPage()
    BuildDirectionPage()
    function popup:SelectTab(name)
        self.activeTab = self.pages[name] and name or "Show"
        for pageName, page in pairs(self.pages) do page:SetShown(pageName == self.activeTab) end
        for tabName, button in pairs(self.tabs) do
            Highlight(button, tabName == self.activeTab)
        end
        self:Refresh()
    end
    function popup:Refresh()
        local settings = Settings()
        if Controls().RefreshPopupSurface then
            Controls().RefreshPopupSurface(self)
        else
            self:SetBackdropColor(.02, .05, .08, .97)
            self:SetBackdropBorderColor(.08, .85, .68, .75)
        end
        local style = addon.VignetteRadarStyle
        if style and style.Color then
            local r, g, b = style.Color("accent")
            self.bead:SetVertexColor(r, g, b, 1)
            self.headerLine:SetColorTexture(r, g, b, .18)
            for _, label in ipairs(self.accentLabels) do
                label:SetTextColor(r, g, b, 1)
            end
        end
        if Controls().RefreshTheme then Controls().RefreshTheme() end
        for _, toggle in ipairs(self.toggles) do
            local enabled = settings[toggle.key] == true
            toggle.button:SetChecked(enabled)
        end
        for _, stepper in ipairs(self.steppers) do
            local value = settings[stepper.key]
            stepper.value:SetText(stepper.format(value))
            if stepper.minus.SetEnabled then
                stepper.minus:SetEnabled(value > stepper.values[1] + .001)
                stepper.plus:SetEnabled(value < stepper.values[#stepper.values] - .001)
            end
        end
        for _, choice in ipairs(self.modes) do
            Highlight(choice.button,
                choice.value == settings.vignetteRadarConstellationSourceMode)
        end
        for _, choice in ipairs(self.modifiers) do
            Highlight(choice.button,
                choice.value == settings.vignetteRadarConstellationInteractModifier)
        end
        self.modeHelp:SetText((MODE_HELP[settings.vignetteRadarConstellationSourceMode]
            or MODE_HELP.mixed)
            .. "\nChoose your map pack in Radar Settings → Map Data.")
    end
    popup:SelectTab("Show")
    popup:Hide()
    return popup
end

function API.Toggle(anchor)
    local panel = EnsurePopup()
    if not panel then return end
    if panel:IsShown() then panel:Hide(); return end
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", anchor or UIParent, "TOPLEFT", 0, 6)
    panel:Refresh()
    panel:Show()
end

function API.Open(anchor)
    local panel = EnsurePopup()
    if not panel then return end
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", anchor or UIParent, "TOPLEFT", 0, 6)
    panel:Refresh()
    panel:Show()
end

function API.Refresh()
    if popup and popup:IsShown() then popup:Refresh() end
end

return API
