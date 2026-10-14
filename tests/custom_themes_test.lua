-- Custom themes (Looks > Customize): Style create/edit/rename/delete, name
-- validation, Core validation of saved data, the Customize panel (hex input,
-- live preview, warnings, Save/Cancel, Escape), the picker's Custom tab, and
-- config search landing (drill into the picker, scroll, fading highlight,
-- Enter, clear button).
unpack = unpack or table.unpack
STANDARD_TEXT_FONT = "default.ttf"
local mock = dofile("tests/ui_mock.lua").Install()
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
local now = 100
GetTime = function() return now end
UISpecialFrames = {}
local timers = {}
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
local function RunTimers()
    local pending = timers
    timers = {}
    for _, timer in ipairs(pending) do timer[2]() end
end

VignetteRadarDB = { vignetteRadarTheme = "dracula" }
local addon = {}
for _, path in ipairs({ "Core/Core.lua", "Core/Themes.lua", "UI/Style.lua", "UI/IconButton.lua",
    "UI/Controls.lua", "Core/Schema.lua", "UI/QuickConfig.lua", "UI/Tray.lua", "UI/ThemeEditor.lua" }) do
    assert(loadfile(path))("VignetteRadar", addon)
end
local Style = addon.VignetteRadarStyle
local db = addon.ValidateSettings()
assert(db.vignetteRadarTheme == "dracula" and #db.vignetteRadarCustomThemes == 0,
    "a fresh profile has no custom themes and keeps its theme")

-- Name validation and suggestions.
assert(Style.ValidateThemeName("  My   Night ") == "My Night", "names are trimmed and spaces collapsed")
assert(not Style.ValidateThemeName("   "), "an empty name is refused")
assert(not Style.ValidateThemeName(string.rep("x", 25)), "names stay at 24 characters or fewer")
assert(Style.ValidateThemeName(string.rep("x", 24)), "24 characters is allowed")
assert(not Style.ValidateThemeName("verdant") and not Style.ValidateThemeName("Dracula Alucard"),
    "a name can not repeat a built-in theme")
assert(Style.ValidateThemeName("a|cffff0000b") == "acffff0000b", "escape bars are removed")
assert(Style.SuggestThemeName("dracula") == "Dracula Dracula Custom", "the suggestion is <Base> Custom")

-- Create from a base: a copy of every role, then saved and listed.
local colors = Style.CopyColors("dracula")
for _, slot in ipairs(Style.slots) do
    local r, g, b = Style.PresetColor("dracula", slot)
    assert(colors[slot][1] == r and colors[slot][2] == g and colors[slot][3] == b, "copy keeps " .. slot)
end
colors.accent = { 1, 0, 0 }
local key = assert(Style.SaveCustomTheme(nil, "Night Shift", "dracula", colors))
assert(key == "custom_1" and Style.HasTheme(key) and Style.ThemeName(key) == "Night Shift"
    and Style.ThemeKind(key) == "custom" and Style.PresetColor(key, "accent") == 1,
    "a saved custom theme resolves like any theme")
assert(colors.accent[1] == 1 and Style.CustomTheme(key).colors ~= colors, "saving copies the colors")
assert(not Style.SaveCustomTheme(nil, "night shift", "dracula", colors), "custom names are unique")
local found = false
for _, choice in ipairs(Style.ThemeChoices()) do found = found or (choice[1] == key and choice[2] == "Night Shift") end
assert(found, "custom themes are schema choices")
assert(addon.Schema.Set("vignetteRadarTheme", key) and VignetteRadarDB.vignetteRadarTheme == key
    and Style.Color("accent") == 1, "a custom theme can be selected through the schema")
assert(Style.MigrateTheme("NIGHT SHIFT") == key, "a custom theme name migrates to its key")

-- Customize a custom theme again, then rename and edit.
local second = assert(Style.SaveCustomTheme(nil, Style.SuggestThemeName(key), key, Style.CopyColors(key)))
assert(second == "custom_2" and Style.ThemeName(second) == "Night Shift Custom", "customizing a custom works")
assert(Style.RenameCustomTheme(second, "Dawn Patrol") == second and Style.ThemeName(second) == "Dawn Patrol",
    "rename keeps the key")
assert(not Style.RenameCustomTheme(second, "Night Shift"), "rename refuses a taken name")
local edited = Style.CopyColors(second)
edited.rare = { 0, 0, 1 }
assert(Style.SaveCustomTheme(second, "Dawn Patrol", key, edited) == second
    and select(3, Style.PresetColor(second, "rare")) == 1, "edit updates in place")

-- Delete: the theme in use falls back to the theme it was made from.
assert(Style.DeleteCustomTheme(key) == "dracula" and VignetteRadarDB.vignetteRadarTheme == "dracula"
    and not Style.HasTheme(key), "deleting the theme in use falls back to its base")

-- Core validation: malformed entries dropped, channels clamped.
local good = Style.CustomTheme(second)
VignetteRadarDB.vignetteRadarCustomThemes = {
    good,
    { key = "custom_9", name = "Clamp Me", colors = (function()
        local c = Style.CopyColors("verdant"); c.accent = { 2, -1, .5 }; return c end)() },
    { key = "custom_3", name = "Dawn Patrol", colors = Style.CopyColors("verdant") }, -- duplicate name
    { key = "bad", name = "Bad Key", colors = Style.CopyColors("verdant") },
    { key = "custom_4", name = "Missing Role", colors = { accent = { 1, 1, 1 } } },
    { key = "custom_5", name = "", colors = Style.CopyColors("verdant") },
    "not a table",
}
VignetteRadarDB.vignetteRadarTheme = "custom_4"
addon.InvalidateSettings()
db = addon.GetSettings()
local list = db.vignetteRadarCustomThemes
assert(#list == 2 and list[1].key == second and list[2].key == "custom_9",
    "only well-formed, unique custom themes survive")
local clamp = list[2].colors.accent
assert(clamp[1] == 1 and clamp[2] == 0 and clamp[3] == .5, "colors are clamped to 0-1")
assert(db.vignetteRadarTheme == "verdant", "a theme pointing at a dropped custom resets")
VignetteRadarDB.vignetteRadarCustomThemes = "junk"
addon.InvalidateSettings()
assert(#addon.GetSettings().vignetteRadarCustomThemes == 0, "a junk list becomes empty")
VignetteRadarDB.vignetteRadarCustomThemes = list
addon.InvalidateSettings()
assert(#addon.GetSettings().vignetteRadarCustomThemes == 2, "the cleaned list loads back")

-- Warnings: readable palettes pass; a light background and look-alike markers warn.
local verdant = Style.CopyColors("verdant")
assert(#Style.ThemeWarnings(verdant, verdant) == 0, "an unchanged Verdant copy reads clearly")
local shared = table.concat(Style.ThemeWarnings(verdant), " ")
assert(shared:find("Treasure and Quest Dots look alike", 1, true),
    "without a base, Verdant's shared Treasure/Quest color is reported")
local bad = Style.CopyColors("verdant")
bad.background = { .9, .9, .9 }
bad.treasure = { bad.rare[1], bad.rare[2], bad.rare[3] }
local warnings = table.concat(Style.ThemeWarnings(bad), " ")
assert(warnings:find("Background is too light", 1, true) and warnings:find("Rare and Treasure look alike", 1, true),
    "contrast and look-alike warnings are reported")

-- The Customize panel.
local Editor = addon.VignetteRadarThemeEditor
local quickAPI = addon.VignetteRadarQuickConfig
quickAPI.OpenPage("Looks")
local quick = quickAPI.GetPanel()
UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarQuickConfigPanel"
addon.Schema.Set("vignetteRadarTheme", "ember")
local before = Style.revision
assert(Editor.Open("create", "ember"), "Customize opens for any theme")
local frame = Editor.GetFrame()
assert(frame:IsShown() and frame.nameInput:GetText() == "Ember Custom" and frame.title.text == "Customize Theme",
    "the panel suggests <Base> Custom")

local escapeNames = table.concat(UISpecialFrames, ",")
assert(escapeNames:find("VignetteRadarThemeEditorPanel", 1, true)
    and not escapeNames:find("VignetteRadarQuickConfigPanel", 1, true),
    "Escape closes the panel first, not the settings window too")
assert(Style.preview and Style.revision > before, "editing starts a live preview")
assert(Editor.SetRoleHex("accent", "#00ff00") and Style.Color("accent") == 0 and select(2, Style.Color("accent")) == 1,
    "a hex code recolors the radar live")
assert(Editor.SetRoleHex("rare", "0af") and select(3, Style.Color("rare")) == 1, "short hex works")
assert(not Editor.SetRoleHex("rare", "zzz"), "bad hex is refused")
assert(VignetteRadarDB.vignetteRadarTheme == "ember" and Style.PresetColor("ember", "accent") ~= 0,
    "the preview does not touch the saved theme")
frame.roles.accent.swatch.scripts.OnEnter(frame.roles.accent.swatch)
-- Hover ring is dark (not white) on Customize swatches.
local hr, hg, hb, ha = addon.VignetteRadarControls.HoverRingColor()
assert(hr < .1 and hg < .1 and hb < .1 and ha == .9, "the hover ring is near-black, not white")
frame.roles.accent.swatch.scripts.OnLeave(frame.roles.accent.swatch)
Editor.SetRoleHex("background", "eeeeee")
assert(frame.warnings.text:find("Heads-up", 1, true), "low contrast shows a heads-up, Save stays possible")
Editor.SetRoleHex("background", "101010")
frame.nameInput:SetText("")
assert(Editor.CheckName() == nil and frame.status.text == "Enter a name.", "an empty name is explained")
assert(not Editor.Save(), "Save refuses an invalid name")
frame.nameInput:SetText("Ember Custom")
local saved = assert(Editor.Save())
assert(not frame:IsShown() and Style.preview == nil and VignetteRadarDB.vignetteRadarTheme == saved
    and Style.Color("accent") == 0, "Save keeps the colors, ends the preview and selects the new theme")
assert(table.concat(UISpecialFrames, ","):find("VignetteRadarQuickConfigPanel", 1, true),
    "the settings window gets Escape back when the panel closes")

-- Cancel (and Escape, which hides the panel) drops the preview.
Editor.Open("edit", saved)
Editor.SetRoleHex("accent", "ff00ff")
assert(Style.Color("accent") == 1, "editing previews")
frame:Hide()
assert(Style.preview == nil and Style.Color("accent") == 0 and Style.CustomTheme(saved).colors.accent[1] == 0,
    "closing without Save restores the saved colors")

-- Rename and delete through the panel.
Editor.Open("rename", saved)
frame.nameInput:SetText("Coal")
assert(Editor.Save() == saved and Style.ThemeName(saved) == "Coal", "rename through the panel")
Editor.Open("delete", saved)
assert(frame.save:GetText() == "Delete" and frame.source.text:find("Coal", 1, true), "delete asks first")
Editor.Cancel()
assert(Style.HasTheme(saved), "Cancel keeps the theme")
assert(not Editor.Open("edit", "ember"), "only custom themes can be edited")

-- The picker's Custom tab lists saved themes with their actions.
local picker = quick.themePicker
quickAPI.Refresh()
assert(picker.view.kind == "custom" and picker.customTab and quick.themeChoices[saved]:IsShown()
    and quick.themeChoices[saved]:GetText() == "Coal", "the picker opens the Custom tab on a custom theme")
assert(picker.actions.customize:IsShown() and picker.actions.edit:IsShown()
    and picker.actions.rename:IsShown() and picker.actions.delete:IsShown(), "a custom theme has every action")
assert(quick.themeChoices[saved]._selected == true and quick.themeChoices[saved].mark == nil,
    "the selected custom theme keeps the underline selection")
picker.singleTab.scripts.OnClick(picker.singleTab)
mock.Click(quick.themeChoices.frost)
assert(VignetteRadarDB.vignetteRadarTheme == "frost" and picker.actions.customize:IsShown()
    and not picker.actions.edit:IsShown(), "a built-in theme only offers Customize")
mock.Click(picker.actions.customize)
assert(frame:IsShown() and frame.mode == "create" and frame.base == "frost", "Customize opens the panel")
Editor.Cancel()
Editor.Open("delete", saved)
Editor.Save()
quickAPI.Refresh()
assert(not Style.HasTheme(saved) and not quick.themeChoices[saved]:IsShown(), "deleted themes leave the picker")

-- Search lands on the match: drill, scroll, fading highlight.
local function Search(text)
    quick.searchInput:SetText(text)
    quick.searchInput.scripts.OnTextChanged(quick.searchInput)
end
Search("dracula")
assert(quick.searchClear:IsShown(), "the clear button shows while there is text")
assert(#timers == 1, "the landing waits for typing to pause")
RunTimers()
assert(picker.view.kind == "multi" and picker.view.family == "dracula", "a family name opens that family")
local target = quick.searchTarget
assert(target == quick.themeChoices.dracula and target:IsShown() and target.searchGlow:IsShown(),
    "the family's variants glow")
local themeRow = quick.themeRow
assert(quick.searchOffset == themeRow.card.pageFrame.offset + themeRow.card.offset + themeRow.layoutY
    + target.layoutY and quick.scrollOffset == math.max(0, math.min(quick.searchOffset - 36,
    quick.contentHeight - quick.scroll.height)), "the first match is scrolled into view")
local glow = target.searchGlow
now = now + .75
quick.flashDriver.scripts.OnUpdate(quick.flashDriver)
assert(glow:IsShown() and glow.alpha > 0 and glow.alpha < 1, "the highlight fades")
now = now + 1
quick.flashDriver.scripts.OnUpdate(quick.flashDriver)
assert(not glow:IsShown() and next(quickAPI.flashes) == nil and not quick.flashDriver:IsShown(),
    "the highlight ends after about 1.5 seconds")

Search("macchiato")
RunTimers()
assert(picker.view.family == "catppuccin" and quick.searchTarget == quick.themeChoices.catppuccin_macchiato
    and quick.themeChoices.catppuccin_macchiato.searchGlow:IsShown(), "a variant name opens its family, marked")

Search("ring visibility")
RunTimers()
local ringRow = quick.searchTarget
assert(ringRow and ringRow.isRow and ringRow.entry.key == "vignetteRadarRingOpacity"
    and ringRow.searchGlow:IsShown(), "any matched setting row glows")
assert(quick.searchOffset > 0 and quick.scrollOffset == math.max(0, math.min(quick.searchOffset - 36,
    quick.contentHeight - quick.scroll.height)), "the row is scrolled into view")

-- Enter jumps to the first match again.
quick.searchTarget = nil
quick.searchInput.scripts.OnEnterPressed(quick.searchInput)
assert(quick.searchTarget == ringRow, "Enter jumps to the first match")

-- The clear button empties the search and restores the page.
Search("dracula")
RunTimers()
mock.Click(quick.searchClear)
assert(quick.query == "" and quick.searchInput:GetText() == "" and not quick.searchClear:IsShown()
    and picker.view.kind == "single" and next(quickAPI.flashes) == nil,
    "Clear Search empties the box, hides itself and returns the picker to the selected theme")
assert(quick.searchClear.labelText == "Clear Search" or quick.searchClear:GetText() == "×",
    "the clear button is labeled Clear Search")

io.write("custom themes tests passed\n")
