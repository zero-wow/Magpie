local addonName, addon = ...
if type(addon) ~= "table" then return end

local Style = {}
addon.VignetteRadarStyle = Style
Style.revision = 0

Style.order = { "verdant", "ember", "frost", "violet", "amber", "mono", "rose", "ocean" }
Style.names = { verdant = "Verdant", ember = "Ember", frost = "Frost", violet = "Violet",
    amber = "Amber", mono = "Mono", rose = "Rose", ocean = "Ocean" }
Style.slots = { "accent", "rings", "heading", "background", "rare", "boss", "treasure", "event", "other", "quest",
    "iconGlyph", "iconBorder", "iconPlate", "iconHover", "iconActive" }
-- Icon button layers (UI/IconButton.lua). A theme may set them directly
-- (custom themes); otherwise they come from other roles: the family map in
-- Core/Themes.lua for Multi-Color themes, SINGLE_ICONS for Single Color ones.
Style.iconSlots = { "iconGlyph", "iconBorder", "iconPlate", "iconHover", "iconActive" }
local ICON_LAYER = { iconGlyph = "glyph", iconBorder = "border", iconPlate = "plate",
    iconHover = "hover", iconActive = "active" }
local SINGLE_ICONS = { glyph = "accent", border = "rings", plate = "background", hover = "accent", active = "accent" }
Style.SINGLE_ICONS = SINGLE_ICONS
Style.labels = { accent = "Player / UI", rings = "Range rings", heading = "Facing cue",
    background = "Radar surface", rare = "Rare", boss = "World boss", treasure = "Treasure",
    event = "Event", other = "Other", quest = "Quest dots", iconGlyph = "Icon glyph",
    iconBorder = "Icon border", iconPlate = "Icon plate", iconHover = "Icon hover glow",
    iconActive = "Icon active mark" }

local presets = {
    verdant = { accent = { .05, .82, .62 }, rings = { .05, .82, .62 }, heading = { .05, .82, .62 },
        background = { .015, .022, .028 }, rare = { .78, .88, 1 }, boss = { 1, .18, .12 },
        treasure = { 1, .68, .16 }, event = { .67, .42, 1 }, other = { .66, .72, .76 },
        quest = { 1, .74, .27 } },
    ember = { accent = { 1, .43, .22 }, rings = { .84, .31, .18 }, heading = { 1, .61, .32 },
        background = { .045, .020, .019 }, rare = { 1, .64, .40 }, boss = { 1, .12, .10 },
        treasure = { 1, .82, .31 }, event = { .95, .44, .62 }, other = { .75, .68, .65 },
        quest = { 1, .84, .38 } },
    frost = { accent = { .34, .75, 1 }, rings = { .25, .58, .89 }, heading = { .65, .88, 1 },
        background = { .013, .027, .043 }, rare = { .78, .90, 1 }, boss = { 1, .35, .31 },
        treasure = { .98, .83, .41 }, event = { .65, .58, 1 }, other = { .59, .76, .86 },
        quest = { .98, .83, .41 } },
    violet = { accent = { .70, .47, 1 }, rings = { .49, .35, .86 }, heading = { .86, .68, 1 },
        background = { .025, .019, .041 }, rare = { .75, .67, 1 }, boss = { 1, .31, .51 },
        treasure = { 1, .72, .33 }, event = { .93, .45, .96 }, other = { .68, .66, .79 },
        quest = { 1, .78, .46 } },
    amber = { accent = { 1, .72, .26 }, rings = { .75, .52, .19 }, heading = { 1, .86, .46 },
        background = { .036, .029, .017 }, rare = { 1, .88, .62 }, boss = { 1, .31, .18 },
        treasure = { 1, .66, .13 }, event = { .92, .51, .27 }, other = { .75, .69, .56 },
        quest = { 1, .83, .35 } },
    mono = { accent = { .78, .84, .85 }, rings = { .66, .75, .77 }, heading = { 1, 1, 1 },
        background = { .017, .020, .022 }, rare = { 1, 1, 1 }, boss = { 1, .43, .40 },
        treasure = { .91, .77, .48 }, event = { .74, .71, .91 }, other = { .58, .63, .65 },
        quest = { .91, .77, .48 } },
    rose = { accent = { 1, .47, .67 }, rings = { .86, .36, .57 }, heading = { 1, .72, .82 },
        background = { .038, .018, .030 }, rare = { 1, .72, .83 }, boss = { 1, .20, .29 },
        treasure = { 1, .78, .46 }, event = { .82, .50, 1 }, other = { .76, .65, .72 },
        quest = { 1, .78, .46 } },
    ocean = { accent = { .12, .84, .90 }, rings = { .12, .60, .70 }, heading = { .45, .94, 1 },
        background = { .010, .029, .037 }, rare = { .55, .88, 1 }, boss = { 1, .34, .30 },
        treasure = { 1, .79, .33 }, event = { .48, .68, 1 }, other = { .55, .72, .76 },
        quest = { 1, .79, .33 } },
}

local function HueColor(hue, saturation, value)
    local position = (hue % 1) * 6
    local sector = math.floor(position)
    local fraction = position - sector
    local minimum = value * (1 - saturation)
    local rising = value * (1 - saturation * (1 - fraction))
    local falling = value * (1 - saturation * fraction)
    if sector == 0 then return { value, rising, minimum } end
    if sector == 1 then return { falling, value, minimum } end
    if sector == 2 then return { minimum, value, rising } end
    if sector == 3 then return { minimum, falling, value } end
    if sector == 4 then return { rising, minimum, value } end
    return { value, minimum, falling }
end

-- Additional palettes share legible category contrast while changing the
-- instrument's color family, background tint, and event marker treatment.
-- Together with the eight above they are the Single Color themes.
local additional = {
    { "mint", "Mint", .44, .63 }, { "jade", "Jade", .47, .88 },
    { "moss", "Moss", .27, .58 }, { "lime", "Lime", .22, .88 },
    { "neon", "Neon", .32, 1 }, { "pine", "Pine", .41, .74 },
    { "copper", "Copper", .075, .82 }, { "rust", "Rust", .035, .83 },
    { "solar", "Solar", .12, .94 }, { "sand", "Sand", .105, .47 },
    { "ivory", "Ivory", .13, .20 }, { "slate", "Slate", .60, .27 },
    { "steel", "Steel", .57, .48 }, { "ash", "Ash", .60, .10 },
    { "ruby", "Ruby", .97, .89 }, { "cherry", "Cherry", .00, .80 },
    { "coral", "Coral", .02, .70 }, { "peach", "Peach", .07, .56 },
    { "lilac", "Lilac", .76, .51 }, { "plum", "Plum", .80, .77 },
    { "dusk", "Dusk", .69, .59 }, { "arctic", "Arctic", .53, .43 },
    { "cobalt", "Cobalt", .62, .84 }, { "lagoon", "Lagoon", .49, .82 },
    { "azure", "Azure", .58, .78 }, { "sky", "Sky", .55, .55 },
    { "sapphire", "Sapphire", .64, .90 }, { "indigo", "Indigo", .70, .80 },
    { "lavender", "Lavender", .72, .35 }, { "orchid", "Orchid", .83, .55 },
    { "magenta", "Magenta", .86, .85 }, { "fuchsia", "Fuchsia", .90, .75 },
    { "blush", "Blush", .94, .45 }, { "tangerine", "Tangerine", .06, .92 },
    { "bronze", "Bronze", .09, .65 }, { "gold", "Gold", .14, .85 },
    { "olive", "Olive", .17, .62 }, { "emerald", "Emerald", .38, .85 },
    { "seafoam", "Seafoam", .45, .40 }, { "glacier", "Glacier", .52, .25 },
    { "storm", "Storm", .62, .18 },
}
-- Only names are registered at load; a generated palette is built the first
-- time something asks for it, so login pays for the theme in use and no more.
local generated = {}
for _, definition in ipairs(additional) do
    generated[definition[1]] = definition
    Style.order[#Style.order + 1] = definition[1]
    Style.names[definition[1]] = definition[2]
end

local function Generate(definition)
    local hue, saturation = definition[3], definition[4]
    local accent = HueColor(hue, saturation, 1)
    return {
        accent = accent,
        rings = HueColor(hue, saturation * .78, .82),
        heading = HueColor(hue, saturation * .52, 1),
        background = { .010 + accent[1] * .024, .013 + accent[2] * .024,
            .017 + accent[3] * .024 },
        rare = HueColor(.59 + hue * .07, .34, 1),
        boss = HueColor(.005 + hue * .012, .88, 1),
        treasure = HueColor(.105 + hue * .025, .80, 1),
        event = HueColor(hue + .40, .72, 1),
        other = HueColor(hue, .22, .82),
        quest = HueColor(.105 + hue * .025, .67, 1),
    }
end

-- Multi-Color themes are plain hex strings per role in Core/Themes.lua. The
-- key index and each theme's color tables are made on first use.
local multiIndex
local function MultiIndex()
    if multiIndex then return multiIndex end
    multiIndex = {}
    local themes = addon.VignetteRadarThemes
    for _, family in ipairs(themes and themes.families or {}) do
        for _, variant in ipairs(family.variants) do
            multiIndex[variant.key] = { family = family, variant = variant }
        end
    end
    return multiIndex
end

local function HexColor(hex)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then return nil end
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255 }
end
Style.HexColor = HexColor

-- Custom themes (Copy + Modify of any theme) live in saved settings as
-- { key = "custom_N", name, base, colors = { role = { r, g, b } } }. Core's
-- ValidateSettings drops malformed ones and clamps colors, so they are read
-- straight from the saved table (no GetSettings here: Core asks HasTheme while
-- it is validating). They are never cached in presets because they can change.
Style.CUSTOM_LIMIT, Style.NAME_LIMIT = 50, 24
local NO_CUSTOMS = {}
local function Customs()
    local db = rawget(_G, "VignetteRadarDB")
    local list = type(db) == "table" and db.vignetteRadarCustomThemes
    return type(list) == "table" and list or NO_CUSTOMS
end
Style.CustomThemes = Customs

function Style.CustomTheme(key)
    if type(key) ~= "string" or key:sub(1, 7) ~= "custom_" then return nil end
    for _, theme in ipairs(Customs()) do
        if theme.key == key then return theme end
    end
end

-- While the Customize panel is open its working colors win over the saved
-- theme, so the radar and panels show every edit live. nil ends the preview.
function Style.SetPreview(colors)
    Style.preview = type(colors) == "table" and colors or nil
    Style.revision = Style.revision + 1
end

local function Resolve(name)
    if type(name) ~= "string" then return nil end
    local preset = presets[name]
    if preset then return preset end
    local custom = Style.CustomTheme(name)
    if custom then return custom.colors end
    if generated[name] then
        preset = Generate(generated[name])
    else
        local found = MultiIndex()[name]
        if not found then return nil end
        preset = {}
        for _, slot in ipairs(Style.slots) do preset[slot] = HexColor(found.variant[slot]) end
    end
    presets[name] = preset
    return preset
end

function Style.HasTheme(name)
    if type(name) ~= "string" then return false end
    return presets[name] ~= nil or generated[name] ~= nil or MultiIndex()[name] ~= nil
        or Style.CustomTheme(name) ~= nil
end

function Style.PresetColor(name, slot)
    local preset = Resolve(name)
    local value = preset and preset[slot or "accent"]
    if value then return value[1], value[2], value[3] end
    if preset and ICON_LAYER[slot] then
        return Style.IconLayerColor(name, slot, function(role)
            local color = preset[role] or presets.verdant[role]
            return color[1], color[2], color[3]
        end)
    end
end

-- Which roles feed the icon layers of a theme, and whether its buttons are
-- "framed" (plate and border always drawn: Multi-Color themes, and custom
-- themes made from one) or quiet like the radar's own glyphs (Single Color).
function Style.IconMap(name, depth)
    local kind, owner = Style.ThemeKind(name)
    if kind == "multi" then
        local themes = addon.VignetteRadarThemes
        local map = themes and (themes.icons and themes.icons[owner.id] or themes.DEFAULT_ICONS)
        return map or SINGLE_ICONS, true
    end
    if kind == "custom" and (depth or 0) < 4 and owner.base and owner.base ~= name then
        return Style.IconMap(owner.base, (depth or 0) + 1)
    end
    return SINGLE_ICONS, false
end

function Style.IconFramed()
    local db = addon.GetSettings()
    local _, framed = Style.IconMap(db and db.vignetteRadarTheme)
    return framed
end

-- An icon layer's color from its mapped role, read through colorOf(role).
-- A glyph, border, glow or mark that would be hard to see on the background
-- uses the heading color instead; the plate is meant to be quiet.
local ICON_FLOOR = { glyph = 3, border = 1.8, hover = 1.8, active = 2.2 }
function Style.IconLayerColor(name, slot, colorOf)
    local layer = ICON_LAYER[slot]
    local map = Style.IconMap(name)
    local r, g, b = colorOf(map[layer] or SINGLE_ICONS[layer])
    local floor = ICON_FLOOR[layer]
    if floor and Style.Luminance then
        local br, bg, bb = colorOf("background")
        if Style.Contrast({ r, g, b }, { br, bg, bb }) < floor then r, g, b = colorOf("heading") end
    end
    return r, g, b
end

-- The Multi-Color families in display order: { id, name, source, variants }.
function Style.Families()
    local themes = addon.VignetteRadarThemes
    return themes and themes.families or {}
end

-- "single", "multi" (then the family and variant records) or "custom" (then
-- the saved custom theme record).
function Style.ThemeKind(name)
    local found = type(name) == "string" and not Style.names[name] and MultiIndex()[name]
    if found then return "multi", found.family, found.variant end
    local custom = Style.CustomTheme(name)
    if custom then return "custom", custom end
    return "single"
end

function Style.ThemeName(name)
    if Style.names[name] then return Style.names[name] end
    local custom = Style.CustomTheme(name)
    if custom then return custom.name end
    local found = type(name) == "string" and MultiIndex()[name]
    return found and (found.family.name .. " " .. found.variant.name) or tostring(name)
end

-- Every theme as { key, label } pairs for the settings schema. The built-in
-- list is made once; saved custom themes are added on each call when present.
local choiceList
function Style.ThemeChoices()
    if not choiceList then
        choiceList = {}
        for _, name in ipairs(Style.order) do choiceList[#choiceList + 1] = { name, Style.names[name] } end
        for _, family in ipairs(Style.Families()) do
            for _, variant in ipairs(family.variants) do
                choiceList[#choiceList + 1] = { variant.key, family.name .. " " .. variant.name }
            end
        end
    end
    local customs = Customs()
    if #customs == 0 then return choiceList end
    local list = {}
    for index, choice in ipairs(choiceList) do list[index] = choice end
    for _, theme in ipairs(customs) do list[#list + 1] = { theme.key, theme.name } end
    return list
end

-- Custom theme names: trimmed, 1-24 characters, no control characters or "|"
-- (WoW escape codes), and not the name of any other theme (case-insensitive).
-- Returns the cleaned name, or nil and a reason a player can read.
function Style.ValidateThemeName(name, ignoreKey)
    if type(name) ~= "string" then return nil, "Enter a name." end
    name = (name:gsub("[%c|]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$"))
    if name == "" then return nil, "Enter a name." end
    if #(name:gsub("[\128-\191]", "")) > Style.NAME_LIMIT then
        return nil, "Use " .. Style.NAME_LIMIT .. " characters or fewer."
    end
    local lower = name:lower()
    for _, choice in ipairs(Style.ThemeChoices()) do
        if choice[1] ~= ignoreKey and (choice[2]:lower() == lower or choice[1] == lower) then
            return nil, "A theme named " .. choice[2] .. " already exists."
        end
    end
    return name
end

-- "<Base> Custom", then "<Base> Custom 2" and so on, always a valid name.
function Style.SuggestThemeName(base)
    local stem = Style.ThemeName(base)
    if type(stem) ~= "string" or not Style.HasTheme(base) then stem = "My" end
    stem = stem:gsub("%s+Custom%s*%d*$", "")
    for number = 1, Style.CUSTOM_LIMIT + 1 do
        local suffix = number == 1 and " Custom" or (" Custom " .. number)
        local room = Style.NAME_LIMIT - #suffix
        local name = (#stem > room and stem:sub(1, room):gsub("%s+$", "") or stem) .. suffix
        if Style.ValidateThemeName(name) then return name end
    end
    return "Custom"
end

-- A full role table copied from a theme: the live colors (with any per-slot
-- Colors overrides) when it is the current theme, otherwise its own colors.
function Style.CopyColors(name)
    local colors, current = {}, addon.GetSettings().vignetteRadarTheme == name
    for _, slot in ipairs(Style.slots) do
        local r, g, b
        if current then r, g, b = Style.Color(slot) else r, g, b = Style.PresetColor(name, slot) end
        if not r then r, g, b = Style.PresetColor("verdant", slot) end
        colors[slot] = { r, g, b }
    end
    return colors
end

local function CleanColors(colors)
    local clean = {}
    for _, slot in ipairs(Style.slots) do
        local value = type(colors) == "table" and colors[slot]
        -- Icon roles are optional: without them the icons follow other roles.
        if type(value) ~= "table" then
            if not ICON_LAYER[slot] then return nil end
        else
            clean[slot] = {}
            for index = 1, 3 do
                local channel = value[index]
                if type(channel) ~= "number" or channel ~= channel then return nil end
                clean[slot][index] = math.max(0, math.min(1, channel))
            end
        end
    end
    return clean
end

-- Creates (key nil) or updates a custom theme. Returns its key, or nil and a reason.
function Style.SaveCustomTheme(key, name, base, colors)
    local db = addon.GetSettings()
    if type(db.vignetteRadarCustomThemes) ~= "table" then db.vignetteRadarCustomThemes = {} end
    local list = db.vignetteRadarCustomThemes
    local theme = key and Style.CustomTheme(key)
    if key and not theme then return nil, "That custom theme no longer exists." end
    local cleanName, reason = Style.ValidateThemeName(name, key)
    if not cleanName then return nil, reason end
    local clean = CleanColors(colors)
    if not clean then return nil, "Every role needs a color." end
    if not theme then
        if #list >= Style.CUSTOM_LIMIT then return nil, "Up to " .. Style.CUSTOM_LIMIT .. " custom themes." end
        local highest = 0
        for _, saved in ipairs(list) do
            highest = math.max(highest, tonumber(saved.key:match("^custom_(%d+)$")) or 0)
        end
        theme = { key = "custom_" .. (highest + 1) }
        list[#list + 1] = theme
    end
    theme.name, theme.colors = cleanName, clean
    if type(base) == "string" then theme.base = base end
    Style.revision = Style.revision + 1
    return theme.key
end

function Style.RenameCustomTheme(key, name)
    local theme = Style.CustomTheme(key)
    if not theme then return nil, "That custom theme no longer exists." end
    return Style.SaveCustomTheme(key, name, theme.base, theme.colors)
end

-- Removes a custom theme. If it was in use, the radar falls back to the theme
-- it was made from (or Verdant). Returns the theme now in use.
function Style.DeleteCustomTheme(key)
    local list = Customs()
    for index, theme in ipairs(list) do
        if theme.key == key then
            table.remove(list, index)
            local db = addon.GetSettings()
            if db.vignetteRadarTheme == key then
                local fallback = theme.base ~= key and Style.HasTheme(theme.base) and theme.base or "verdant"
                db.vignetteRadarTheme = fallback
            end
            Style.revision = Style.revision + 1
            return db.vignetteRadarTheme
        end
    end
end

-- Readability checks for a role table: WCAG contrast of the fixed light label
-- text and the facing cue on the background, markers against the background,
-- and markers that are too close to tell apart. Warnings only; never blocks.
local LABEL_TEXT = { .81, .87, .86 }
-- WCAG contrast ratio of two { r, g, b } colors (Style.Luminance is defined
-- further down with the text readability helpers; this runs after load).
function Style.Contrast(a, b)
    local la, lb = Style.Luminance(a[1], a[2], a[3]), Style.Luminance(b[1], b[2], b[3])
    if la < lb then la, lb = lb, la end
    return (la + .05) / (lb + .05)
end
local MARKERS = { "rare", "treasure", "quest", "event", "boss" }
local function Distance(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end
-- base (optional) is the theme the colors were copied from: a pair of markers
-- that already matched there (many Single themes share Treasure and Quest)
-- is not reported again, so only the player's own edits raise look-alikes.
function Style.ThemeWarnings(colors, base)
    local warnings, background = {}, colors.background
    local controls = addon.VignetteRadarControls
    local function Name(slot)
        local label = Style.labels[slot]
        return controls and controls.TitleCase(label) or label
    end
    if Style.Contrast(LABEL_TEXT, background) < 4.5 then
        warnings[#warnings + 1] = "Background is too light for the light settings text."
    end
    if colors.iconGlyph and Style.Contrast(colors.iconGlyph, background) < 3 then
        warnings[#warnings + 1] = "Icon Glyph is hard to see on the background."
    end
    if Style.Contrast(colors.heading, background) < 3 then
        warnings[#warnings + 1] = "Facing Cue is hard to see on the background."
    end
    for _, slot in ipairs(MARKERS) do
        if Style.Contrast(colors[slot], background) < 2.2 then
            warnings[#warnings + 1] = Name(slot) .. " is hard to see on the background."
        end
    end
    for first = 1, #MARKERS - 1 do
        for second = first + 1, #MARKERS do
            local a, b = MARKERS[first], MARKERS[second]
            if Distance(colors[a], colors[b]) < .16
                and not (base and base[a] and base[b] and Distance(base[a], base[b]) < .16) then
                warnings[#warnings + 1] = Name(a) .. " and " .. Name(b) .. " look alike."
            end
        end
    end
    return warnings
end

function Style.HexOf(r, g, b)
    return string.format("%02X%02X%02X", math.floor(r * 255 + .5), math.floor(g * 255 + .5),
        math.floor(b * 255 + .5))
end

-- Saved theme names from older builds, presets and the slash command: keys stay
-- as they were, other spellings ("Rose Pine Moon", "tokyo-night") and bare
-- family names map onto a theme. Returns nil when nothing matches.
function Style.MigrateTheme(value)
    if Style.HasTheme(value) then return value end
    if type(value) ~= "string" then return nil end
    for _, theme in ipairs(Customs()) do
        if theme.name:lower() == value:lower() then return theme.key end
    end
    local key = (value:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
    if Style.HasTheme(key) then return key end
    local themes = addon.VignetteRadarThemes
    local alias = themes and themes.aliases and themes.aliases[key]
    if Style.HasTheme(alias) then return alias end
    local squashed = key:gsub("_", "")
    for _, family in ipairs(Style.Families()) do
        if family.id == squashed or family.id == key then return family.default or family.variants[1].key end
        for _, variant in ipairs(family.variants) do
            if (variant.key:gsub("_", "")) == squashed then return variant.key end
        end
    end
    return nil
end

local function ValidColor(value)
    return type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number"
        and type(value[3]) == "number" and value[1] == value[1] and value[2] == value[2]
        and value[3] == value[3] and value[1] >= 0 and value[1] <= 1
        and value[2] >= 0 and value[2] <= 1 and value[3] >= 0 and value[3] <= 1
end

function Style.Color(slot)
    local preview = Style.preview
    if preview and ValidColor(preview[slot]) then
        local value = preview[slot]
        return value[1], value[2], value[3]
    end
    local db = addon.GetSettings()
    local custom = db.vignetteRadarColors
    local value = type(custom) == "table" and custom[slot]
    if ValidColor(value) then return value[1], value[2], value[3] end
    local theme = Resolve(db.vignetteRadarTheme) or presets.verdant
    -- Icon layers follow their mapped roles live (so per-role edits carry
    -- over) unless the theme sets the icon role itself.
    if ICON_LAYER[slot] and not ValidColor(theme[slot]) then
        return Style.IconLayerColor(db.vignetteRadarTheme, slot, Style.Color)
    end
    value = theme[slot] or presets.verdant[slot] or presets.verdant.accent
    return value[1], value[2], value[3]
end

function Style.SetColor(slot, r, g, b)
    if not Style.labels[slot] then return false end
    if not ValidColor({ r, g, b }) then return false end
    local db = addon.GetSettings()
    if type(db.vignetteRadarColors) ~= "table" then db.vignetteRadarColors = {} end
    db.vignetteRadarColors[slot] = { r, g, b }
    Style.revision = Style.revision + 1
    return true
end

function Style.ClearColor(slot)
    local colors = addon.GetSettings().vignetteRadarColors
    if type(colors) == "table" then colors[slot] = nil; Style.revision = Style.revision + 1 end
end

function Style.SetTheme(name)
    if not Resolve(name) then return false end
    local db = addon.GetSettings()
    db.vignetteRadarTheme = name
    db.vignetteRadarColors = {}
    Style.revision = Style.revision + 1
    return true
end

function Style.IsCustomized()
    local colors = addon.GetSettings().vignetteRadarColors
    return type(colors) == "table" and next(colors) ~= nil
end

-- One bundled monospace face for every addon string (JetBrains Mono, SIL OFL 1.1,
-- see Media/Fonts/JetBrainsMono-OFL.txt). Blizzard frames keep their own fonts.
local fontFolder = "Interface\\AddOns\\" .. (type(addonName) == "string" and addonName or "Magpie")
    .. "\\Media\\Fonts\\"
Style.fonts = {
    regular = fontFolder .. "JetBrainsMono-Regular.ttf",
    bold = fontFolder .. "JetBrainsMono-Bold.ttf",
}

function Style.Font(weight)
    return Style.fonts[weight] or Style.fonts.regular
end

function Style.FallbackFont()
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Type scale. Callers pass a role name or a raw size; SetFont lifts anything
-- below the readable floor and applies the Text Size setting. Panel text
-- (no outline) never drops below 10; outlined HUD text over the world can go
-- to 9 because the outline carries its contrast.
Style.type = { caption = 10, body = 11, label = 11, title = 12, heading = 14 }
Style.MIN_TEXT, Style.MIN_HUD_TEXT = 10, 9
Style.TEXT_SCALES = { 1, 1.1, 1.2, 1.35 }
-- Minimum WCAG contrast for panel text against the panel surface.
Style.CONTRAST_FLOOR = 4.5

function Style.TextScale()
    local db = type(VignetteRadarDB) == "table" and VignetteRadarDB
    local scale = db and db.vignetteRadarTextScale
    if type(scale) ~= "number" or scale ~= scale then return 1 end
    return math.max(.9, math.min(1.5, scale))
end

function Style.FontSize(size, flags)
    if type(size) == "string" then size = Style.type[size] end
    size = tonumber(size) or Style.type.body
    local floor = (flags and flags ~= "") and Style.MIN_HUD_TEXT or Style.MIN_TEXT
    return math.floor(math.max(size, floor) * Style.TextScale() + .5)
end

-- Relative luminance (WCAG) of an sRGB color in 0..1.
local function Channel(value)
    return value <= .03928 and value / 12.92 or ((value + .055) / 1.055) ^ 2.4
end
local function Luminance(r, g, b)
    return .2126 * Channel(r) + .7152 * Channel(g) + .0722 * Channel(b)
end
Style.Luminance = Luminance

-- The lightest surface addon text sits on: the popup face (background x2.7,
-- capped at .14), so a color that reads there reads on every darker panel.
function Style.TextSurface()
    local r, g, b = Style.Color("background")
    return math.min(.14, (r or 0) * 2.7), math.min(.14, (g or 0) * 2.7), math.min(.14, (b or 0) * 2.7)
end

-- Text colors below the contrast floor are mixed toward a soft light (not
-- white, which glows) until they read; colors that already read are kept.
-- Results are cached per color until the theme surface changes.
local SOFT_TEXT = { .86, .90, .89 }
local readable = { cache = {} }
function Style.Readable(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return r, g, b end
    -- Before saved variables load there is no theme yet; reading settings
    -- here would validate an empty table early.
    if type(VignetteRadarDB) ~= "table" then return r, g, b end
    local sr, sg, sb = Style.TextSurface()
    if readable.sr ~= sr or readable.sg ~= sg or readable.sb ~= sb then
        readable.sr, readable.sg, readable.sb, readable.cache = sr, sg, sb, {}
        readable.surface = Luminance(sr, sg, sb) + .05
    end
    local key = math.floor(r * 255 + .5) * 65536 + math.floor(g * 255 + .5) * 256 + math.floor(b * 255 + .5)
    local hit = readable.cache[key]
    if hit then return hit[1], hit[2], hit[3] end
    local floor, low, high = Style.CONTRAST_FLOOR * readable.surface - .05, 0, 1
    local out = { r, g, b }
    if Luminance(r, g, b) < floor then
        for _ = 1, 10 do
            local mid = (low + high) / 2
            if Luminance(r + (SOFT_TEXT[1] - r) * mid, g + (SOFT_TEXT[2] - g) * mid,
                b + (SOFT_TEXT[3] - b) * mid) < floor then low = mid else high = mid end
        end
        out = { r + (SOFT_TEXT[1] - r) * high, g + (SOFT_TEXT[2] - g) * high, b + (SOFT_TEXT[3] - b) * high }
    end
    readable.cache[key] = out
    return out[1], out[2], out[3]
end

local function ReadableTextColor(self, r, g, b, a)
    r, g, b = Style.Readable(r, g, b)
    return self.vrNativeSetTextColor(self, r, g, b, a)
end

-- Width of a font string's text without wrapping or truncation. Uses the
-- client measure when there is one, else a monospace estimate (JetBrains
-- Mono advances .6 em per glyph).
function Style.TextWidth(fontString)
    if not fontString then return 0 end
    local measure = fontString.GetUnboundedStringWidth or fontString.GetStringWidth
    local width = measure and tonumber(measure(fontString))
    if width then return width end
    local text = fontString.GetText and fontString:GetText() or ""
    return #(tostring(text or ""):gsub("[\128-\191]", "")) * (fontString.vrFontSize or 10) * .6
end

-- The wrapped height the client reports for a font string set to width,
-- else an estimate from its measured width (tests, or before the font has
-- loaded).
function Style.TextHeight(fontString, width)
    local height = fontString.GetStringHeight and tonumber((fontString:GetStringHeight()))
    if height and height > 0 then return math.ceil(height) end
    local line = (fontString.vrFontSize or 10) + 2
    return math.max(1, math.ceil(Style.TextWidth(fontString) / math.max(1, width or 1))) * line
end

-- A text's width on one line, and on two lines at its best word split (the
-- wider of the two lines), measured with a hidden one-line ruler string.
-- Leaves the ruler holding the last measured part.
function Style.LineWidths(ruler, text)
    text = tostring(text or "")
    ruler:SetText(text)
    local one = Style.TextWidth(ruler)
    local words = {}
    for word in text:gmatch("%S+") do words[#words + 1] = word end
    local two = one
    for split = 1, #words - 1 do
        ruler:SetText(table.concat(words, " ", 1, split))
        local first = Style.TextWidth(ruler)
        ruler:SetText(table.concat(words, " ", split + 1))
        two = math.min(two, math.max(first, Style.TextWidth(ruler)))
    end
    return one, two
end

-- FontString:SetFont returns false when the file cannot be loaded; drop back to
-- the client font so text never goes blank. Panel text also gets the contrast
-- floor on every later SetTextColor.
function Style.SetFont(fontString, size, flags, weight)
    if not fontString or not fontString.SetFont then return false end
    flags = flags or ""
    size = Style.FontSize(size, flags)
    fontString.vrFontSize = size
    if flags == "" and not fontString.vrNativeSetTextColor and fontString.SetTextColor then
        fontString.vrNativeSetTextColor = fontString.SetTextColor
        fontString.SetTextColor = ReadableTextColor
    end
    if fontString:SetFont(Style.Font(weight), size, flags) ~= false then return true end
    fontString:SetFont(Style.FallbackFont(), size, flags)
    return false
end
