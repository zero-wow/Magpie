-- Theme registry: Single Color and Multi-Color themes, the role mapping that
-- keeps markers apart and text readable, lazy building, and saved-name
-- migration.
local settings = { vignetteRadarTheme = "verdant", vignetteRadarColors = {} }
local addon = { GetSettings = function() return settings end }
assert(loadfile("Core/Themes.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
local Style = assert(addon.VignetteRadarStyle)
assert(addon.VignetteRadarThemes, "Core/Themes.lua registers its data")

-- Single Color: the original 32 keys keep their place, more follow.
local original = { "verdant", "ember", "frost", "violet", "amber", "mono", "rose", "ocean", "mint", "jade",
    "moss", "lime", "neon", "pine", "copper", "rust", "solar", "sand", "ivory", "slate", "steel", "ash",
    "ruby", "cherry", "coral", "peach", "lilac", "plum", "dusk", "arctic", "cobalt", "lagoon" }
for index, key in ipairs(original) do
    assert(Style.order[index] == key and Style.HasTheme(key), "single theme kept in place: " .. key)
end
assert(#Style.order >= 48, "the Single Color set should be wider than before")

local function Valid(r, g, b)
    return type(r) == "number" and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1
end
for _, key in ipairs(Style.order) do
    assert(Style.ThemeKind(key) == "single", key .. " is a single theme")
    for _, slot in ipairs(Style.slots) do
        assert(Valid(Style.PresetColor(key, slot)), key .. " needs " .. slot)
    end
end

-- Multi-Color: every variant has a unique key, a valid hex for every role,
-- and no clash with a single theme.
local required = { "catppuccin", "dracula", "nord", "gruvbox", "tokyonight", "rosepine", "solarized",
    "one", "everforest", "kanagawa", "nightfox", "monokaipro", "ayu", "github", "material",
    "synthwave84", "cyberdream", "azeroth" }
local families, seen, variants = {}, {}, 0
for _, family in ipairs(Style.Families()) do families[family.id] = family end
for _, id in ipairs(required) do assert(families[id], "missing family " .. id) end
local function Linear(c) return c <= .03928 and c / 12.92 or ((c + .055) / 1.055) ^ 2.4 end
local function Luminance(hex)
    local r, g, b = assert(Style.HexColor(hex))[1], Style.HexColor(hex)[2], Style.HexColor(hex)[3]
    return .2126 * Linear(r) + .7152 * Linear(g) + .0722 * Linear(b)
end
local function Contrast(a, b)
    local x, y = Luminance(a), Luminance(b)
    if x < y then x, y = y, x end
    return (x + .05) / (y + .05)
end
local function Distance(a, b)
    local x, y = Style.HexColor(a), Style.HexColor(b)
    return math.sqrt((x[1] - y[1]) ^ 2 + (x[2] - y[2]) ^ 2 + (x[3] - y[3]) ^ 2)
end
local markers = { "rare", "treasure", "quest", "event", "boss" }
for _, family in ipairs(Style.Families()) do
    assert(type(family.name) == "string" and #family.variants > 0, family.id .. " needs variants")
    assert(not family.default or Style.HasTheme(family.default), family.id .. " default must exist")
    for _, variant in ipairs(family.variants) do
        local key = variant.key
        assert(not seen[key] and not Style.names[key], "duplicate theme key " .. key)
        seen[key], variants = true, variants + 1
        for _, slot in ipairs(Style.slots) do
            assert(Style.HexColor(variant[slot]) or slot:find("^icon"), key .. " has no valid hex for " .. slot)
        end
        local kind, owner, record = Style.ThemeKind(key)
        assert(kind == "multi" and owner == family and record == variant, key .. " kind")
        -- Text stays readable and markers stay visible on the surface.
        assert(Contrast(variant.heading, variant.background) >= 5, key .. ": heading must read on background")
        for _, slot in ipairs(markers) do
            assert(Contrast(variant[slot], variant.background) >= 2.2, key .. ": " .. slot .. " too faint")
        end
        -- Rares, treasures, quests, events and bosses stay apart.
        for i = 1, #markers do
            for j = i + 1, #markers do
                assert(Distance(variant[markers[i]], variant[markers[j]]) >= .16,
                    key .. ": " .. markers[i] .. " and " .. markers[j] .. " look alike")
            end
        end
    end
end
assert(variants >= 55, "expected at least 55 multi-color variants, got " .. variants)
assert(families.catppuccin.variants[3].key == "catppuccin_macchiato"
    and Style.ThemeName("catppuccin_macchiato") == "Catppuccin Macchiato", "Catppuccin Macchiato is listed")

-- Exact official values survive the conversion.
local r, g, b = Style.PresetColor("catppuccin_macchiato", "background")
assert(math.abs(r - 0x18 / 255) < 1e-9 and math.abs(g - 0x19 / 255) < 1e-9 and math.abs(b - 0x26 / 255) < 1e-9,
    "Macchiato's crust #181926 must be its background")

-- Choices list every theme once for the schema.
local choices = Style.ThemeChoices()
assert(#choices == #Style.order + variants, "choices cover single and multi themes")
assert(Style.ThemeChoices() == choices, "choices are built once")

-- Applying a multi theme recolors through Style.Color; custom colors clear.
settings.vignetteRadarColors.accent = { .1, .2, .3 }
assert(Style.SetTheme("tokyonight_storm") and settings.vignetteRadarTheme == "tokyonight_storm"
    and not Style.IsCustomized(), "a multi theme applies and clears custom colors")
local ar, ag, ab = Style.Color("accent")
assert(math.abs(ar - 0x7a / 255) < 1e-9 and math.abs(ag - 0xa2 / 255) < 1e-9 and math.abs(ab - 0xf7 / 255) < 1e-9,
    "Tokyo Night Storm's accent is its blue")
assert(not Style.SetTheme("nope") and settings.vignetteRadarTheme == "tokyonight_storm", "unknown names are refused")

-- Migration: saved keys stay; other spellings and family names map; junk fails.
assert(Style.MigrateTheme("lagoon") == "lagoon", "old keys stay as they are")
assert(Style.MigrateTheme("Verdant") == "verdant", "case is ignored")
assert(Style.MigrateTheme("Catppuccin Macchiato") == "catppuccin_macchiato", "display names map to keys")
assert(Style.MigrateTheme("catppuccin") == "catppuccin_mocha", "a family name maps to its default")
assert(Style.MigrateTheme("Tokyo-Night") == "tokyonight_night", "aliases map")
assert(Style.MigrateTheme("Rose Pine Moon") == "rosepine_moon", "spaced names map")
assert(Style.MigrateTheme("Synthwave '84") == "synthwave84", "punctuation is ignored")
assert(Style.MigrateTheme("not a theme") == nil and Style.MigrateTheme(42) == nil, "junk does not map")

-- Every key in the data file is plain ASCII (WoW's Lua 5.1 rejects others).
local file = assert(io.open("Core/Themes.lua", "rb"))
local source = file:read("*a")
file:close()
for line in source:gmatch("[^\n]+") do
    local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', "")
    assert(not code:find("[\128-\255]"), "non-ASCII outside strings: " .. line)
end

-- Icon layers: every family maps all five layers to real roles, every theme
-- resolves them, glyphs read on the background, and Multi-Color themes are
-- framed while Single Color ones stay quiet (accent / rings / background).
local Themes = addon.VignetteRadarThemes
local layers = { "glyph", "border", "plate", "hover", "active" }
local roleNames = {}
for index = 1, 10 do roleNames[Style.slots[index]] = true end
for _, family in ipairs(Style.Families()) do
    local map = assert(Themes.icons[family.id], family.id .. " needs a deliberate icon map")
    for _, layer in ipairs(layers) do
        assert(roleNames[map[layer]], family.id .. " icon " .. layer .. " must name a palette role")
    end
    assert(map.glyph ~= map.border, family.id .. ": glyph and border should differ")
end
local function Table(r, g, b) return { r, g, b } end
for _, name in ipairs(Style.order) do
    assert(Style.PresetColor(name, "iconGlyph") == Style.PresetColor(name, "accent")
        and Style.PresetColor(name, "iconBorder") == Style.PresetColor(name, "rings")
        and Style.PresetColor(name, "iconPlate") == Style.PresetColor(name, "background"),
        name .. ": Single Color icons fall back to accent, rings and background")
    assert(select(2, Style.IconMap(name)) == false, name .. " icons stay quiet")
end
for _, family in ipairs(Style.Families()) do
    for _, variant in ipairs(family.variants) do
        local key = variant.key
        assert(select(2, Style.IconMap(key)) == true, key .. " icons are framed")
        local background = Table(Style.PresetColor(key, "background"))
        for _, slot in ipairs(Style.iconSlots) do
            assert(Valid(Style.PresetColor(key, slot)), key .. " resolves " .. slot)
        end
        assert(Style.Contrast(Table(Style.PresetColor(key, "iconGlyph")), background) >= 3,
            key .. ": icon glyph must read on the background")
        assert(Style.Contrast(Table(Style.PresetColor(key, "iconBorder")), background) >= 1.8,
            key .. ": icon border must show on the background")
    end
end
-- Dracula reads as purple glyph, pink border, comment plate.
assert(Style.HexOf(Style.PresetColor("dracula", "iconGlyph")) == "BD93F9"
    and Style.HexOf(Style.PresetColor("dracula", "iconBorder")) == "FF79C6"
    and Style.HexOf(Style.PresetColor("dracula", "iconPlate")) == "6272A4", "Dracula icon roles")
-- Live colors: a Multi-Color theme maps through its family; a per-role edit
-- carries into the icons; an explicit icon color wins.
settings.vignetteRadarTheme = "dracula"
assert(Style.HexOf(Style.Color("iconBorder")) == "FF79C6" and Style.IconFramed(), "live Dracula border")
settings.vignetteRadarColors = { event = { 0, 1, 0 } }
assert(Style.HexOf(Style.Color("iconBorder")) == "00FF00", "icons follow edited roles")
settings.vignetteRadarColors = { iconBorder = { 1, 1, 1 } }
assert(Style.HexOf(Style.Color("iconBorder")) == "FFFFFF", "an explicit icon color wins")
settings.vignetteRadarColors = {}
settings.vignetteRadarTheme = "verdant"
assert(not Style.IconFramed(), "Single Color icons are quiet")
-- Custom themes made before the icon roles still save (they are optional).
local savedDB = rawget(_G, "VignetteRadarDB")
_G.VignetteRadarDB = settings
local legacy = {}
for index = 1, 10 do legacy[Style.slots[index]] = { .5, .5, .5 } end
assert(Style.SaveCustomTheme(nil, "Legacy Icons", "dracula", legacy), "icon roles are optional on save")
local custom = Style.CustomThemes()[#Style.CustomThemes()]
assert(Style.PresetColor(custom.key, "iconGlyph") and select(2, Style.IconMap(custom.key)) == true,
    "a custom theme without icon roles maps them like its base")
settings.vignetteRadarCustomThemes = nil
_G.VignetteRadarDB = savedDB

print("themes_test ok")
