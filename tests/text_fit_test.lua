-- Text never truncates: every settings row built from the schema keeps each
-- button label inside its button, buttons inside the row and apart from each
-- other, and single-line labels inside their width. Also checks the type
-- scale floor, the Text Size scale and the contrast floor for panel text.
local Mock = dofile("tests/ui_mock.lua")
Mock.Install()
STANDARD_TEXT_FONT = "default.ttf"
VignetteRadarDB = {}
local addon = {}
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Themes.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Controls.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Schema.lua"))("VignetteRadar", addon)
local Style, Controls, Schema = addon.VignetteRadarStyle, addon.VignetteRadarControls, addon.Schema
local CARD_WIDTH = 384 -- QuickConfig: 468 - 64 - 16 - 4

-- Type scale: panel text never below 10, outlined HUD text never below 9.
assert(Style.FontSize(7, "") == 10 and Style.FontSize(8) == 10, "panel text has a floor of 10")
assert(Style.FontSize(7, "OUTLINE") == 9, "outlined HUD text has a floor of 9")
assert(Style.FontSize("body") == 11 and Style.FontSize("title") == 12, "roles map to the type scale")
VignetteRadarDB.vignetteRadarTextScale = 1.2
assert(Style.FontSize("body") == 13 and Style.FontSize(7, "") == 12, "Text Size scales every size")
VignetteRadarDB.vignetteRadarTextScale = 99
assert(Style.TextScale() == 1.5, "a bad saved scale is clamped")
VignetteRadarDB.vignetteRadarTextScale = nil

-- Contrast floor: a dark accent is lifted, a readable color is kept.
local function Contrast(r, g, b)
    local sr, sg, sb = Style.TextSurface()
    return (Style.Luminance(r, g, b) + .05) / (Style.Luminance(sr, sg, sb) + .05)
end
local r, g, b = Style.Readable(.10, .20, .45)
assert(Contrast(r, g, b) >= Style.CONTRAST_FLOOR - .01, "dark text is lifted to the contrast floor")
assert(b > g and g > r, "the lifted color keeps its hue order")
r, g, b = Style.Readable(.81, .87, .86)
assert(r == .81 and g == .87 and b == .86, "readable text keeps its exact color")
local label = Mock.New("FontString")
Style.SetFont(label, 10)
label:SetTextColor(.05, .05, .30, 1)
assert(Contrast(label.textColor[1], label.textColor[2], label.textColor[3]) >= Style.CONTRAST_FLOOR - .01,
    "panel font strings apply the floor on every SetTextColor")
local hud = Mock.New("FontString")
Style.SetFont(hud, 9, "OUTLINE")
hud:SetTextColor(.05, .05, .30, 1)
assert(hud.textColor[3] == .30, "outlined HUD text keeps its color")

-- Build every schema row the settings window shows.
local built = {}
for _, page in ipairs(Schema.Pages()) do
    for _, section in ipairs(page.sections) do
        for _, entry in ipairs(section.entries) do
            if not entry.widget or entry.widget == "color" then
                local width = entry.type == "color" and CARD_WIDTH / 2 or CARD_WIDTH
                local parent = Mock.New("Frame")
                local row = entry.type == "color" and Controls.ColorRow(parent, entry, width)
                    or Controls.Row(parent, entry, width)
                if row.Refresh then row:Refresh() end
                built[#built + 1] = { row = row, name = entry.id, width = width }
            end
        end
        if section.note then
            built[#built + 1] = { row = Controls.NoteRow(Mock.New("Frame"), section.note, CARD_WIDTH),
                name = section.title .. " note", width = CARD_WIDTH }
        end
    end
end
-- Action rows: several long labels must wrap, not cut.
built[#built + 1] = { name = "long actions", width = CARD_WIDTH, row = Controls.ActionRow(Mock.New("Frame"), {
    { "Open Expedition Studio" }, { "Share To Group" }, { "Clear Saved Routes" }, { "Whole Zone Survey" } },
    CARD_WIDTH) }
assert(#built > 100, "the test must cover the whole schema")

local function Left(frame) return frame.point and frame.point[4] or 0 end

local failures = {}
local function Fail(text) failures[#failures + 1] = text end
for _, item in ipairs(built) do
    local row = item.row
    assert(row:GetWidth() <= item.width + .01, item.name .. " row is wider than its card")
    local buttons = row.buttons or {}
    for index, button in ipairs(buttons) do
        local text = button.label.text or ""
        local need = Style.TextWidth(button.label)
        if need > button:GetWidth() - 10 + .01 then
            Fail(string.format("%s: button %q needs %.0f px, has %.0f", item.name, text, need,
                button:GetWidth() - 10))
        end
        if Left(button) + button:GetWidth() > item.width + .01 then
            Fail(item.name .. ": button " .. text .. " runs past the row")
        end
        local selection = button.selection and button.selection.width
        if selection and math.abs(selection - math.max(1, button:GetWidth() - 12)) > .01 then
            Fail(item.name .. ": the selection underline must stay 6px inside each side")
        end
        local nextButton = buttons[index + 1]
        if nextButton and nextButton.point[5] == button.point[5]
            and Left(nextButton) < Left(button) + button:GetWidth() then
            Fail(item.name .. ": buttons " .. text .. " and " .. (nextButton.label.text or "") .. " overlap")
        end
    end
    for _, key in ipairs({ "label", "value", "text" }) do
        local fontString = row[key]
        if fontString and fontString.wordWrap == false and fontString.width
            and Style.TextWidth(fontString) > fontString.width + .01 then
            Fail(string.format("%s: %s %q is cut (%.0f > %.0f)", item.name, key, fontString.text or "",
                Style.TextWidth(fontString), fontString.width))
        end
    end
    local toggle = row.check and row.check.label
    if toggle and toggle.width and Style.TextWidth(toggle) > toggle.width + .01 then
        Fail(item.name .. ": toggle label " .. (toggle.text or "") .. " is cut")
    end
end
assert(#failures == 0, "text would truncate:\n" .. table.concat(failures, "\n"))
-- The measure is real: a fixed narrow button shrinks to the floor and still
-- reports that its label does not fit.
local narrow = Controls.Button(Mock.New("Frame"), "Whole Zone", 40, 21)
assert(narrow.label.vrFontSize == Style.MIN_TEXT and Style.TextWidth(narrow.label) > 30,
    "an overfull button is measured, not silently cut")
assert(narrow.label.width == nil, "button labels have no fixed width, so the client never adds an ellipsis")

-- The reported row: Alert Within shows every label in full on one wrapped block.
local alert
for _, item in ipairs(built) do if item.name == "vignetteRadarAlertRange" then alert = item.row end end
assert(alert and #alert.buttons == 5, "Alert Within must be built")
for _, button in ipairs(alert.buttons) do
    assert(Style.TextWidth(button.label) <= button:GetWidth() - 10, button.label.text .. " fits")
end

-- A row that cannot fit on one line wraps and grows instead of cutting.
local long = built[#built].row
assert(long:GetHeight() > 26, "a crowded action row wraps to a second line")
io.write("text fit tests passed (" .. #built .. " rows)\n")
