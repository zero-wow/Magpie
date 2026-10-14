-- Settings window Simple / Advanced mode: the saved mode and its defaults,
-- schema level tags, Simple hiding Advanced rows and cards, the header switch
-- (small, measured, never over the search box), search still finding every
-- setting, and OpenPage revealing a card Simple mode hides.
unpack = unpack or table.unpack
STANDARD_TEXT_FONT = "default.ttf"
dofile("tests/ui_mock.lua").Install()
-- Like the client, Show and Hide run OnShow / OnHide when visibility changes.
do
    local create = CreateFrame
    CreateFrame = function(...)
        local frame = create(...)
        frame.Show = function(self)
            local was = self.shown
            self.shown = true
            if not was and self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        frame.Hide = function(self)
            local was = self.shown
            self.shown = false
            if was and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        frame.SetShown = function(self, value) if value then self:Show() else self:Hide() end end
        return frame
    end
end
GetTime = function() return 100 end
UISpecialFrames = {}
C_Timer = { After = function(_, callback) callback() end }

-- Defaults: a fresh install opens in Simple, saved settings from before the
-- switch open in Advanced, a bad value is repaired.
local addon = {}
VignetteRadarDB = {}
for _, path in ipairs({ "Core/Core.lua", "Core/Themes.lua", "UI/Style.lua", "UI/IconButton.lua",
    "UI/Controls.lua", "Core/Schema.lua", "UI/QuickConfig.lua", "UI/Tray.lua" }) do
    assert(loadfile(path))("VignetteRadar", addon)
end
local Schema = addon.Schema
assert(addon.ValidateSettings().vignetteRadarConfigMode == "simple", "a fresh install opens in Simple")
VignetteRadarDB = { vignetteRadarRange = 300 }
assert(addon.ValidateSettings().vignetteRadarConfigMode == "advanced",
    "saved settings from before the switch open in Advanced")
VignetteRadarDB = { vignetteRadarConfigMode = "expert" }
assert(addon.ValidateSettings().vignetteRadarConfigMode == "advanced", "a bad saved mode is repaired")

-- Persistence: the switch writes through Schema.Set, and a reload keeps it.
VignetteRadarDB = {}
local db = addon.ValidateSettings()
assert(Schema.Mode() == "simple", "the fresh profile is Simple")
local heard
Schema.OnChange(function(key, value) if key == "vignetteRadarConfigMode" then heard = value end end)
assert(Schema.SetMode("advanced") and db.vignetteRadarConfigMode == "advanced" and heard == "advanced",
    "SetMode saves the mode and tells listeners")
local saved = {}
for key, value in pairs(db) do saved[key] = value end
VignetteRadarDB = saved
addon.InvalidateSettings()
assert(addon.ValidateSettings().vignetteRadarConfigMode == "advanced" and Schema.Mode() == "advanced",
    "the mode survives a reload")
assert(not Schema.Set("vignetteRadarConfigMode", "expert"), "the mode accepts only Simple or Advanced")
Schema.SetMode("simple")

-- Schema tags: the mode entry has no row; levels come from entries or sections.
local modeEntry = Schema.Entry("vignetteRadarConfigMode")
assert(modeEntry and modeEntry.hidden, "the mode is a schema entry")
for _, id in ipairs(Schema.order) do assert(id ~= modeEntry.id, "the mode has no settings row") end
assert(#Schema.Search("settings mode") == 0, "the mode is never a search hit")
local advancedCount, simpleCount = 0, 0
for _, id in ipairs(Schema.order) do
    if Schema.Level(Schema.entries[id]) == "advanced" then advancedCount = advancedCount + 1
    else simpleCount = simpleCount + 1 end
end
assert(advancedCount > 40 and simpleCount > 40, "both modes carry real settings")
assert(Schema.Level(Schema.Entry("vignetteRadarColors", "rare")) == "advanced",
    "a section's level covers its entries")
assert(Schema.Level(Schema.Entry("vignetteRadarBorderOpacity")) == "advanced"
    and Schema.Level(Schema.Entry("vignetteRadarTheme")) == "simple", "an entry carries its own level")
for _, key in ipairs({ "vignetteRadarRange", "vignetteRadarTheme", "vignetteRadarTrailMode",
    "vignetteRadarAutoRouteQuestMoveOn", "vignetteRadarTextScale", "vignetteRadarQuestDots" }) do
    assert(Schema.ShownIn(Schema.Entry(key), "simple"), key .. " is a core choice and stays in Simple")
end
assert(not Schema.ShownIn(Schema.Entry("vignetteRadarBorderOpacity"), "simple")
    and Schema.ShownIn(Schema.Entry("vignetteRadarBorderOpacity"), "advanced"), "ShownIn follows the mode")

-- The window in Simple mode.
local quickAPI = addon.VignetteRadarQuickConfig
quickAPI.OpenPage("Looks")
local quick = quickAPI.GetPanel()
local function Row(key, subkey)
    for _, row in ipairs(quick.rows) do
        if row.entry and row.entry.key == key and row.entry.subkey == subkey then return row end
    end
end
local function Search(text)
    quick.searchInput:SetText(text)
    quick.searchInput.scripts.OnTextChanged(quick.searchInput)
end
local colors, theme = quick.cards["Looks/Colors"], quick.cards["Looks/Theme"]
assert(quick.layoutMode == "simple" and theme:IsShown() and Row("vignetteRadarTheme"):IsShown()
    and not Row("vignetteRadarBorderOpacity"):IsShown() and not colors:IsShown()
    and not quick.cards["Looks/Radar Guides"]:IsShown(),
    "Simple hides Advanced rows and whole Advanced cards")
for _, button in ipairs(quick.railButtons) do
    assert(button:IsShown(), "every page keeps Simple rows, so its rail icon stays: " .. button.pageID)
end
assert(quick.pages.Looks:IsShown() and theme.point[5] == -30, "the first Simple card sits at the page top")

-- The header switch: small, measured, between the title and the search box.
local simpleButton, advancedButton = quick.modeButtons[1], quick.modeButtons[2]
local controls = addon.VignetteRadarControls
assert(simpleButton.text == "Simple" and advancedButton.text == "Advanced"
    and simpleButton._selected and not advancedButton._selected, "the switch shows the saved mode")
assert(simpleButton.width == advancedButton.width
    and controls.ButtonWidth(advancedButton) <= advancedButton.width
    and controls.ButtonWidth(simpleButton) <= simpleButton.width, "segment labels fit, never truncated")
local switchLeft = simpleButton.point[4]
local switchRight = advancedButton.point[4] + advancedButton.width
local searchLeft = quick.searchInput.point[4]
assert(switchRight - switchLeft < 170 and switchRight <= searchLeft - 4
    and switchLeft >= 46 + addon.VignetteRadarStyle.TextWidth(quick.title),
    "the switch is compact and sits between the title and the search box")
assert(searchLeft + quick.searchInput.width <= quick.close.point[4] - 4
    and quick.searchInput.width >= 120, "the search box keeps a usable width beside the switch")

-- Search finds Advanced settings in Simple mode, then they hide again.
Search("border visibility")
local border = Row("vignetteRadarBorderOpacity")
assert(border:IsShown() and border.card:IsShown() and quick.searchTarget == border,
    "search shows and lands on an Advanced setting in Simple mode")
Search("chevron gap")
assert(Row("vignetteRadarChevronDistance"):IsShown() and quick.cards["Looks/Radar Guides"]:IsShown(),
    "search opens a whole Advanced card for its match")
Search("")
assert(not border:IsShown() and not quick.cards["Looks/Radar Guides"]:IsShown(),
    "clearing the search hides Advanced rows again")

-- OpenPage by card name shows a card Simple mode hides, until another page.
quickAPI.OpenPage("Source Fusion")
local fusion = quick.cards["Markers/Source Fusion"]
assert(fusion:IsShown() and Row("vignetteRadarSourceFusion"):IsShown() and quick.revealCard == fusion,
    "OpenPage reveals the asked-for Advanced card")
quick.railButtons[2].scripts.OnClick(quick.railButtons[2])
assert(quick.revealCard == nil and not colors:IsShown(), "picking a page ends the reveal")

-- Clicking Advanced shows every row and saves the mode.
advancedButton.scripts.OnClick(advancedButton)
assert(VignetteRadarDB.vignetteRadarConfigMode == "advanced" and quick.layoutMode == "advanced"
    and colors:IsShown() and Row("vignetteRadarBorderOpacity"):IsShown()
    and advancedButton._selected and not simpleButton._selected, "Advanced shows everything")
simpleButton.scripts.OnClick(simpleButton)
assert(VignetteRadarDB.vignetteRadarConfigMode == "simple" and not colors:IsShown(),
    "Simple hides the Advanced rows again")

-- The switch follows the theme accent like every other window button.
Schema.Set("vignetteRadarTheme", "ember")
controls.RefreshTheme()
local ar, ag, ab = addon.VignetteRadarStyle.Color("accent")
local face = assert(simpleButton.face.vertex, "the segment face is tinted")
assert(math.abs(face[1] - ar) < .001 and math.abs(face[2] - ag) < .001
    and math.abs(face[3] - ab) < .001, "the selected segment uses the theme accent")

print("settings_mode_test passed (" .. advancedCount .. " Advanced, " .. simpleCount .. " Simple)")
