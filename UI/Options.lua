local _, addon = ...
if type(addon) ~= "table" then return end

-- The Blizzard AddOns canvas is only a doorway. Every setting lives in the
-- radar's own settings window (QuickConfig), so nothing is shown twice.
local panel, category

local function OpenQuickConfig()
    local quick = addon.VignetteRadarQuickConfig
    if not (quick and quick.OpenPage) then return false end
    quick.OpenPage("Radar")
    return true
end

local function BuildPanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "VignetteRadarOptionsPanel", UIParent)
    panel.name = "Magpie"
    panel:Hide()

    local Style = addon.VignetteRadarStyle
    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -22)
    Style.SetFont(title, 15, "")
    title:SetTextColor(1, .82, 0, 1)
    title:SetText("Magpie")
    panel.title = title

    local description = panel:CreateFontString(nil, "OVERLAY")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    description:SetJustifyH("LEFT")
    Style.SetFont(description, 11, "")
    description:SetTextColor(.68, .77, .76, 1)
    description:SetText("All settings live in the radar's own settings window.")
    panel.description = description

    local controls = addon.VignetteRadarControls
    local open = controls.Button(panel, "Open Magpie Settings", 230, 26)
    open:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    open:SetScript("OnClick", OpenQuickConfig)
    panel.openButton = open
    return panel
end

-- Kept for /vr config, /vr options and the AddOn compartment: opens QuickConfig,
-- falling back to the Blizzard canvas only if QuickConfig did not load.
function addon.OpenOptions()
    if OpenQuickConfig() then return end
    if not panel then BuildPanel() end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BuildPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, registered = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
        if ok and registered then
            category = registered
            Settings.RegisterAddOnCategory(category)
        end
    end
    -- An entry in the minimap's addon menu that opens the radar settings.
    if addon.GetSettings().vignetteRadarCompartment == true and AddonCompartmentFrame
        and type(AddonCompartmentFrame.RegisterAddon) == "function" then
        pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
            text = "Magpie",
            icon = "Interface\\AddOns\\Magpie\\Media\\beacon-rare.tga",
            notCheckable = true,
            func = function()
                local quick = addon.VignetteRadarQuickConfig
                if quick and quick.Toggle then quick.Toggle() else addon.OpenOptions() end
            end,
        })
    end
end)
