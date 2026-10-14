local _, addon = ...
if type(addon) ~= "table" then return end

-- One table that describes every setting the settings window shows: its
-- type, default, allowed values, label, help, page and section. The window,
-- its search and its live-apply all read from here. Core's ValidateSettings
-- still owns load-time validation; Set validates each write against these
-- rules first and then lets ValidateSettings re-check the table.
local Schema = { entries = {}, order = {}, pages = {}, pageOrder = {}, listeners = {} }
addon.Schema = Schema
addon.VignetteRadarSchema = Schema

local function Settings() return addon.GetSettings() end

local function Id(key, subkey)
    return subkey ~= nil and (key .. ":" .. tostring(subkey)) or key
end
Schema.Id = Id

-- Pages are the window's rail. icon is the column in Media/config-icons.tga.
function Schema.DefinePage(spec)
    assert(type(spec.id) == "string", "schema page needs an id")
    if Schema.pages[spec.id] then return Schema.pages[spec.id] end
    local page = { id = spec.id, title = spec.title or spec.id, icon = spec.icon,
        tooltip = spec.tooltip, sections = {}, sectionOrder = {} }
    Schema.pages[spec.id] = page
    Schema.pageOrder[#Schema.pageOrder + 1] = spec.id
    return page
end

-- Sections are the cards on a page, in the order they are defined.
function Schema.DefineSection(spec)
    local page = assert(Schema.pages[spec.page], "unknown schema page " .. tostring(spec.page))
    if page.sections[spec.title] then return page.sections[spec.title] end
    local section = { page = spec.page, title = spec.title, advanced = spec.advanced == true,
        level = spec.level, note = spec.note, entries = {} }
    page.sections[spec.title] = section
    page.sectionOrder[#page.sectionOrder + 1] = spec.title
    return section
end

-- spec: key, subkey, type ("bool" | "number" | "choice" | "color" | "list"),
-- default, min/max/step or choices ({ value, label } pairs or a function
-- returning them), format, label, tooltip, page, section, order, advanced,
-- widget (a custom renderer name), get/set (custom reader/writer), refresh
-- ("full" | "light" | false), onChange, validatedBy (owner other than Core),
-- level ("advanced" = shown only in the window's Advanced mode; a section's
-- level covers its entries), hidden (window state with a writer but no row:
-- not in a page, not in order, never a search hit).
-- Note: `advanced` means "only while Advanced Tools is on"; `level` is the
-- Simple / Advanced window mode. They are separate switches.
function Schema.Define(spec)
    assert(type(spec.key) == "string" and spec.key ~= "", "schema entry needs a key")
    assert(type(spec.type) == "string", "schema entry needs a type")
    local id = Id(spec.key, spec.subkey)
    assert(not Schema.entries[id], "duplicate schema entry " .. id)
    spec.id = id
    if spec.hidden then
        Schema.entries[id] = spec
        return spec
    end
    local section = Schema.DefineSection({ page = spec.page, title = spec.section })
    spec.order = spec.order or (#section.entries + 1) * 10
    Schema.entries[id] = spec
    Schema.order[#Schema.order + 1] = id
    section.entries[#section.entries + 1] = spec
    table.sort(section.entries, function(a, b) return a.order < b.order end)
    return spec
end

function Schema.Entry(key, subkey)
    return Schema.entries[Id(key, subkey)]
end

function Schema.Choices(entry)
    local choices = entry and entry.choices
    if type(choices) == "function" then choices = choices() end
    return type(choices) == "table" and choices or {}
end

function Schema.Get(key, subkey)
    local entry = Schema.Entry(key, subkey)
    local db = Settings()
    if entry and entry.get then return entry.get(db, subkey) end
    local value = db[key]
    if subkey ~= nil then
        if type(value) ~= "table" then return nil end
        return value[subkey]
    end
    return value
end

-- Returns ok, value-or-reason after applying the entry's own rules.
local function Coerce(entry, value)
    local kind = entry.type
    if kind == "bool" then return true, value == true or value == 1 end
    if kind == "number" then
        if type(value) ~= "number" or value ~= value then return false, "not a number" end
        local choices = Schema.Choices(entry)
        if #choices > 0 then
            for _, choice in ipairs(choices) do
                if math.abs(choice[1] - value) < .0001 then return true, choice[1] end
            end
            return false, "not an allowed value"
        end
        if entry.min then value = math.max(entry.min, value) end
        if entry.max then value = math.min(entry.max, value) end
        if entry.step and entry.step > 0 then
            local base = entry.min or 0
            value = base + math.floor((value - base) / entry.step + .5) * entry.step
        end
        return true, value
    end
    if kind == "choice" then
        if entry.open then return type(value) == "string", value end
        for _, choice in ipairs(Schema.Choices(entry)) do
            if choice[1] == value then return true, value end
        end
        return false, "not an allowed choice"
    end
    return true, value
end
Schema.Coerce = Coerce

local function RefreshRadar(mode)
    local radar = addon.VignetteRadarAPI
    if mode ~= false and radar and radar.Refresh then radar.Refresh(mode ~= "light") end
end

-- The one writer for settings shown in the window. Validates the value,
-- writes it (or calls the entry's own setter), lets Core re-validate,
-- refreshes the radar, runs onChange and tells listeners (open panels).
function Schema.Set(key, value, subkey)
    local entry = Schema.Entry(key, subkey)
    if not entry then return false, "unknown setting " .. Id(key, subkey) end
    local ok, coerced = Coerce(entry, value)
    if not ok then return false, coerced end
    value = coerced
    local db = Settings()
    local result, reason = true, nil
    if entry.set then
        result, reason = entry.set(value, subkey, db)
        if result == nil then result = true end
    else
        if subkey ~= nil then
            if type(db[key]) ~= "table" then db[key] = {} end
            db[key][subkey] = value
        else
            db[key] = value
        end
        if addon.ValidateSettings then addon.ValidateSettings() end
        RefreshRadar(entry.refresh == nil and "full" or entry.refresh)
    end
    if entry.onChange then entry.onChange(value, subkey, db) end
    for _, listener in ipairs(Schema.listeners) do listener(key, value, subkey, result, reason) end
    return result ~= false, reason
end

function Schema.OnChange(listener)
    Schema.listeners[#Schema.listeners + 1] = listener
end

local function SearchText(entry)
    if not entry.searchText then
        local words = { entry.label or "", entry.tooltip or "", entry.section or "",
            entry.page or "", entry.key, entry.subkey and tostring(entry.subkey) or "" }
        for _, choice in ipairs(type(entry.choices) == "table" and entry.choices or {}) do
            words[#words + 1] = tostring(choice[2] or choice[1])
        end
        for _, tag in ipairs(entry.tags or {}) do words[#words + 1] = tag end
        entry.searchText = table.concat(words, " "):lower()
    end
    return entry.searchText
end

-- Entries whose label, help, section, page, key or choice names contain
-- every word of text. options.advanced = true includes Advanced Tools entries.
function Schema.Search(text, options)
    local query = type(text) == "string" and text:lower():match("^%s*(.-)%s*$") or ""
    local results = {}
    if query == "" then return results end
    local advanced = options and options.advanced
    if advanced == nil then advanced = addon.AdvancedToolsEnabled and addon.AdvancedToolsEnabled() end
    for _, id in ipairs(Schema.order) do
        local entry = Schema.entries[id]
        local section = Schema.pages[entry.page].sections[entry.section]
        if advanced or not (entry.advanced or section.advanced) then
            local haystack, matched = SearchText(entry), true
            for word in query:gmatch("%S+") do
                if not haystack:find(word, 1, true) then matched = false; break end
            end
            if matched then
                local label = (entry.label or ""):lower()
                local score = label == query and 0 or label:find(query, 1, true) == 1 and 1
                    or label:find(query, 1, true) and 2 or 3
                results[#results + 1] = { entry = entry, score = score }
            end
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.entry.label < b.entry.label
    end)
    for index, result in ipairs(results) do results[index] = result.entry end
    return results
end

-- Simple / Advanced mode ---------------------------------------------------

-- An entry's window level: its own, else its section's, else "simple".
function Schema.Level(entry)
    if not entry then return "simple" end
    if entry.level then return entry.level end
    local page = Schema.pages[entry.page]
    local section = page and page.sections[entry.section]
    return section and section.level or "simple"
end

-- The window mode. Anything but "simple" reads as Advanced, so a table that
-- Core has not validated yet never hides a row.
function Schema.Mode()
    return Settings().vignetteRadarConfigMode == "simple" and "simple" or "advanced"
end

-- True when the entry has a row in mode (default: the saved mode).
function Schema.ShownIn(entry, mode)
    return (mode or Schema.Mode()) ~= "simple" or Schema.Level(entry) ~= "advanced"
end

function Schema.SetMode(mode)
    return Schema.Set("vignetteRadarConfigMode", mode == "simple" and "simple" or "advanced")
end

-- Ordered pages, each with ordered sections and their ordered entries.
function Schema.Pages()
    local list = {}
    for _, id in ipairs(Schema.pageOrder) do
        local page = Schema.pages[id]
        local sections = {}
        for _, title in ipairs(page.sectionOrder) do sections[#sections + 1] = page.sections[title] end
        list[#list + 1] = { id = page.id, title = page.title, icon = page.icon,
            tooltip = page.tooltip, sections = sections }
    end
    return list
end

-- Formats ---------------------------------------------------------------

local function Percent(value) return math.floor(value * 100 + .5) .. "%" end
local function Yards(value) return value .. " yd" end
local function Pixels(value) return value .. " px" end
local function Plain(value) return tostring(value) end
Schema.Format = { Percent = Percent, Yards = Yards, Pixels = Pixels, Plain = Plain }

local function Values(list, format)
    local choices = {}
    for index, value in ipairs(list) do choices[index] = { value, format and format(value) or tostring(value) } end
    return choices
end

-- Shared side effects ------------------------------------------------------

local function Call(owner, name, ...)
    local module = addon[owner]
    local method = module and module[name]
    if method then return method(...) end
end

local function RecordView(_, _, db)
    if addon.VignetteRadarViewProfiles then addon.VignetteRadarViewProfiles.Record(db) end
end

local function ConfigureRuntime() Call("VignetteRadarFeatureRuntime", "Configure") end
local function RefreshWorldMarker() Call("VignetteRadarWorldMarker", "Refresh") end
local function RefreshGuide()
    Call("VignetteRadarGuidance", "Invalidate")
    Call("VignetteRadarGuidePanel", "Refresh")
end

-- A setter that hands the value to one of the radar's own Set* functions.
local function Radar(name)
    return function(value)
        local setter = addon[name]
        if setter then setter(value) end
    end
end

local function Constellation(value, _, db, key)
    db[key] = value
    if addon.ValidateSettings then addon.ValidateSettings() end
    Call("VignetteRadarConstellation", "Refresh")
end

-- Definition helpers: Page() makes a rail page; In(page, section) returns a
-- function that defines entries in that section, in the order written.
local function Page(id, icon, tooltip)
    Schema.DefinePage({ id = id, title = id, icon = icon, tooltip = tooltip })
end

local function In(page, section, options)
    Schema.DefineSection({ page = page, title = section, advanced = options and options.advanced,
        level = options and options.level, note = options and options.note })
    return function(spec)
        spec.page, spec.section = page, section
        return Schema.Define(spec)
    end
end

-- Rows tagged level = A (or in a section tagged so) show only in the
-- window's Advanced mode: fine-tuning numbers, rare edge toggles, per-role
-- colors, debugging. Core choices stay in Simple.
local A = "advanced"

-- Pages -------------------------------------------------------------------

Page("Radar", 0, "Radar, range, trail and behavior")
Page("Looks", 1, "Theme, colors and radar guides")
Page("Alerts", 2, "Detection and approach alerts")
Page("Markers", 3, "Markers, map data packs and filters")
Page("Quests", 4, "Quest markers, guidance and quest routing")
Page("Routes", 5, "World Focus, Auto Route, route drafts and Zygor")
Page("HUD", 6, "In-world marker, Bearing Bar and Constellation")
Page("Data", 7, "Hunting presets, journal and planning tools")
Page("Tools", 8, "Advanced Tools, diagnostics and performance")

-- Radar -------------------------------------------------------------------

local radar = In("Radar", "Radar")
radar{ key = "vignetteRadarEnabled", type = "bool", default = true, label = "Enable Radar",
    tooltip = "Show the radar and scan for vignettes.", set = Radar("SetVignetteRadarEnabled") }
radar{ key = "vignetteRadarHideWhenEmpty", type = "bool", default = true, label = "Hide When Empty",
    tooltip = "Hide the radar while nothing is in range." }
radar{ key = "vignetteRadarLauncherVisible", type = "bool", default = true, label = "Show Launcher",
    tooltip = "Show the small launcher button when the radar is closed." }
radar{ key = "vignetteRadarWorldMap", level = A, type = "bool", default = true, label = "Include World-Map Detections",
    tooltip = "Also list vignettes that only the world map reports." }
radar{ key = "vignetteRadarEmptyHelp", level = A, type = "bool", default = true, label = "Explain An Empty Radar",
    tooltip = "Show a short reason when the radar has nothing to show." }

local size = In("Radar", "Range And Size", { note = "Drag the radar edges to change its size." })
size{ key = "vignetteRadarRange", type = "number", default = 450, label = "Range",
    tooltip = "How far the radar looks, in yards.", format = Yards,
    choices = function() return Values(addon.VignetteRadarRanges or {}, Yards) end,
    set = Radar("SetVignetteRadarRange") }
size{ key = "vignetteRadarScale", type = "number", default = 1, label = "Radar Scale",
    tooltip = "Overall size of the radar.", format = Percent,
    choices = Values({ .8, .9, 1, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8 }, Percent),
    set = Radar("SetVignetteRadarScale") }
size{ key = "vignetteRadarNorthUp", type = "bool", default = false, label = "Keep North At The Top",
    tooltip = "Fix north at the top instead of turning with you.", glyph = "N",
    set = Radar("SetVignetteRadarNorthUp") }
size{ key = "vignetteRadarHoverTools", level = A, type = "bool", default = true, label = "Show Controls On Hover",
    tooltip = "Show the corner tools while the mouse is over the radar.", onChange = RecordView }

local exploring = In("Radar", "Exploring")
exploring{ key = "vignetteRadarSmartZoom", type = "bool", default = false, label = "Smart Zoom While Moving",
    tooltip = "Zoom out while you travel fast and back in when you stop." }
exploring{ key = "vignetteRadarUntangle", level = A, type = "bool", default = true, label = "Spread Overlapping Markers",
    tooltip = "Nudge markers apart when they sit on top of each other." }
exploring{ key = "vignetteRadarTrailMode", type = "choice", default = "off", label = "Trails",
    tooltip = "Follow draws where you have been. Lead draws the way ahead to your target. Both shows the two.",
    choices = { { "off", "Off" }, { "follow", "Follow" }, { "lead", "Lead" }, { "both", "Both" } },
    set = Radar("SetVignetteRadarTrailMode"),
    tags = { "breadcrumbs", "travel trail", "trail", "path", "ahead", "behind" } }
exploring{ key = "vignetteRadarLeadNextStops", level = A, type = "bool", default = true, label = "Lead Through Next Stops",
    tooltip = "Carry the Lead trail on through the next Auto Route stops as a fainter chain.",
    tags = { "breadcrumbs", "travel trail", "route", "chain", "stops" } }

local function MinimapUnderlay() Call("VignetteRadarMinimapUnderlay", "Refresh") end
local underlay = In("Radar", "Minimap Underlay",
    { note = "Borrows Blizzard's minimap and gives it back exactly when turned off." })
underlay{ key = "vignetteRadarMinimapUnderlay", type = "bool", default = false, label = "Minimap Underlay",
    tooltip = "Show Blizzard's minimap terrain under the radar face, zoomed and turned to match the radar.",
    refresh = false, onChange = MinimapUnderlay, tags = { "minimap", "terrain", "map", "background" } }
underlay{ key = "vignetteRadarMinimapUnderlayTint", level = A, type = "number", default = .5, label = "Face Tint",
    tooltip = "How much of the radar face color covers the minimap. Lower shows more terrain.",
    format = Percent, choices = Values({ .1, .2, .3, .4, .5, .6, .7, .8, .9 }, Percent),
    refresh = false, onChange = MinimapUnderlay, tags = { "minimap", "tint", "opacity" } }
underlay{ key = "vignetteRadarMinimapUnderlayShape", type = "choice", default = "square", label = "Map Shape",
    tooltip = "Square fills the whole radar face. Circle fits the outer range ring exactly."
        .. " Right-click the minimap corner button to flip.",
    choices = { { "square", "Square" }, { "circle", "Circle" } },
    refresh = false, onChange = MinimapUnderlay, tags = { "minimap", "mask", "shape", "circle", "square" } }
underlay{ key = "vignetteRadarMinimapUnderlayIcons", type = "choice", default = "radar", label = "Duplicate Icons",
    tooltip = "Icons the radar and the minimap both draw. Radar Wins blanks the minimap's own icons, so only its"
        .. " terrain shows. Split By Type leaves plain map spots (delves, races, untimed events) to the minimap and"
        .. " keeps rares, treasures and quests on the radar. Minimap Wins hides every radar marker the minimap"
        .. " also draws.",
    choices = { { "radar", "Radar Wins" }, { "split", "Split By Type" }, { "minimap", "Minimap Wins" } },
    refresh = false, onChange = MinimapUnderlay, tags = { "minimap", "icons", "blips", "duplicate", "poi", "twice" } }
underlay{ key = "vignetteRadarMinimapUnderlayHideChrome", level = A, type = "bool", default = true,
    label = "Hide Default Minimap Frame",
    tooltip = "While the underlay is on, hide Blizzard's minimap frame, zone bar and minimap buttons.",
    refresh = false, onChange = MinimapUnderlay, tags = { "minimap", "chrome", "buttons", "border" } }
-- The underlay re-borrows when the tray starts or stops taking minimap
-- buttons; the tray then gathers (or gives back) on its own.
local function ButtonTray()
    MinimapUnderlay()
    Call("VignetteRadarButtonTray", "Refresh")
end
underlay{ key = "vignetteRadarButtonTray", type = "bool", default = true, label = "Gather Buttons Into Tray",
    tooltip = "While the underlay is on, move the radar's corner buttons off the face into a tray that slides"
        .. " out from a lip on the radar's side.",
    refresh = false, onChange = ButtonTray, tags = { "minimap", "buttons", "tray", "corner", "drawer", "lip" } }
underlay{ key = "vignetteRadarButtonTrayMinimap", level = A, type = "bool", default = true,
    label = "Collect Minimap Buttons",
    tooltip = "Also gather other addons' minimap buttons and Blizzard's calendar, tracking, mail, landing page"
        .. " and addon menu into the tray. The flip button in the tray swaps between the two sets.",
    refresh = false, onChange = ButtonTray, tags = { "minimap", "buttons", "libdbicon", "addons", "tray" } }
underlay{ key = "vignetteRadarButtonTrayScan", level = A, type = "bool", default = true,
    label = "Scan For Other Minimap Buttons",
    tooltip = "Also gather minimap buttons that addons make by hand (not through LibDBIcon). Alt+Right-click one"
        .. " in the tray to leave it on the minimap; /magpie buttons lists and resets them.",
    refresh = false, onChange = function() Call("VignetteRadarButtonTray", "Refresh") end,
    tags = { "minimap", "buttons", "scan", "addons", "tray", "ignore" } }
underlay{ key = "vignetteRadarButtonTrayLocked", hidden = true, type = "bool", default = false,
    label = "Keep Button Tray Open", refresh = false,
    onChange = function() Call("VignetteRadarButtonTray", "RefreshTheme") end }
underlay{ key = "vignetteRadarButtonTraySet", hidden = true, type = "choice", default = "radar", label = "Tray Shows",
    choices = { { "radar", "Radar Buttons" }, { "minimap", "Minimap Buttons" } },
    refresh = false, onChange = function() Call("VignetteRadarButtonTray", "Layout") end }
-- Button order per set ({ radar = { names }, minimap = { names } }): written
-- by press-and-hold reorder in the tray; /magpie buttons order reset clears it.
Schema.Define({ key = "vignetteRadarButtonTrayOrder", type = "list", hidden = true, label = "Button Order",
    refresh = false, onChange = function() Call("VignetteRadarButtonTray", "ApplyOrder") end })

local behavior = In("Radar", "Behavior")
behavior{ key = "vignetteRadarLastSeen", level = A, type = "bool", default = true, label = "Keep Last-Seen Markers",
    tooltip = "Keep a marker briefly after it leaves detection range." }
behavior{ key = "vignetteRadarLastSeenSeconds", level = A, type = "number", default = 10, label = "Keep For",
    format = function(value) return value .. " sec" end,
    choices = { { 5, "5 sec" }, { 10, "10 sec" }, { 15, "15 sec" } } }
behavior{ key = "vignetteRadarQuietCombat", type = "bool", default = true, label = "Mute Combat Alerts",
    tooltip = "Fade the radar and skip alerts during combat.", set = Radar("SetVignetteRadarQuietCombat") }
behavior{ key = "vignetteRadarKeepVisibleCombat", type = "bool", default = false, label = "Stay Fully Visible",
    tooltip = "Keep the radar fully visible in combat.", glyph = "eye",
    set = Radar("SetVignetteRadarKeepVisibleCombat") }
behavior{ key = "vignetteRadarQuietInstances", type = "bool", default = true, label = "Fade And Mute In Instances",
    tooltip = "Quiet the radar inside dungeons, raids and arenas." }
behavior{ key = "vignetteRadarHideCleared", type = "bool", default = false, label = "Hide Cleared Rares And Treasures",
    tooltip = "Hide rares and treasures you already completed." }

-- Looks -------------------------------------------------------------------

local theme = In("Looks", "Theme", { note = "Light variants keep their colors on a dark surface so text stays readable." })
theme{ key = "vignetteRadarTheme", type = "choice", default = "verdant", label = "Color Theme",
    tooltip = "A Single Color theme, or a Multi-Color palette where each role has its own color.",
    widget = "theme",
    choices = function()
        local style = addon.VignetteRadarStyle
        return style and style.ThemeChoices and style.ThemeChoices() or {}
    end,
    set = function(value)
        local style = addon.VignetteRadarStyle
        if style then style.SetTheme(value) end
        RefreshRadar("light")
    end, tags = { "palette", "colors", "custom", "customize" } }
theme{ key = "vignetteRadarShapes", type = "bool", default = true, label = "Use Icons",
    tooltip = "Recognizable icons for markers. Off shows colored dots." }
theme{ key = "vignetteRadarPanelsMatchRadar", level = A, type = "bool", default = true, label = "Panels Match The Radar",
    tooltip = "Paint panels with the radar's own background and ring color.",
    onChange = function() Call("VignetteRadarLegend", "Refresh") end }
theme{ key = "vignetteRadarQuestTrackerRound", level = A, type = "bool", default = true,
    label = "Round Quest Tray",
    tooltip = "Beside a round radar, the docked Quest Tracker curves around the circle. Off keeps it straight.",
    onChange = function() Call("VignetteRadarQuestTracker", "Refresh") end,
    tags = { "quest tracker", "circle", "circular", "curve" } }
theme{ key = "vignetteRadarBorderOpacity", level = A, type = "number", default = .5, label = "Radar Border Visibility",
    format = Percent, choices = Values({ 0, .25, .5, .75, 1, 1.25, 1.5, 2, 2.5, 3, 4 }, Percent) }

local text = In("Looks", "Text", { note = "Type /reload after changing Text Size so every panel resizes." })
text{ key = "vignetteRadarTextScale", type = "number", default = 1, label = "Text Size",
    tooltip = "Make every Magpie label larger. Small text never goes below a readable size.",
    refresh = false, choices = { { 1, "100%" }, { 1.1, "110%" }, { 1.2, "120%" }, { 1.35, "135%" } },
    tags = { "font", "readability", "scale" } }

local colors = In("Looks", "Colors", { level = A, note = "Click a swatch for a custom color. Choosing a theme clears them." })
do
    local style = addon.VignetteRadarStyle
    for _, slot in ipairs(style and style.slots or {}) do
        colors{ key = "vignetteRadarColors", subkey = slot, type = "color", widget = "color",
            label = addon.VignetteRadarControls and addon.VignetteRadarControls.TitleCase(style.labels[slot])
                or style.labels[slot],
            tooltip = "Custom color for " .. style.labels[slot]:lower() .. ".",
            get = function() return style.Color(slot) end,
            set = function(value)
                if type(value) == "table" then
                    style.SetColor(slot, value[1], value[2], value[3])
                else
                    style.ClearColor(slot)
                end
                RefreshRadar("light")
            end }
    end
end

local guides = In("Looks", "Radar Guides", { level = A })
guides{ key = "vignetteRadarRingOpacity", type = "number", default = .5, label = "Ring Visibility",
    format = Percent, choices = Values({ 0, .25, .5, .75, 1, 1.25, 1.5, 1.75, 2 }, Percent) }
guides{ key = "vignetteRadarRangeLabelOpacity", type = "number", default = .5, label = "Yard Text Visibility",
    format = Percent, choices = Values({ 0, .25, .5, .75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16 }, Percent) }
guides{ key = "vignetteRadarChevronOpacity", type = "number", default = .72, label = "Chevron Opacity",
    format = Percent, choices = Values({ 0, .1, .2, .3, .4, .5, .6, .72, .8, .9, 1 }, Percent) }
guides{ key = "vignetteRadarHeadingOpacity", type = "number", default = .46, label = "Facing Line Opacity",
    format = Percent, choices = Values({ 0, .1, .2, .3, .4, .46, .5, .6, .7, .8, .9, 1 }, Percent) }
guides{ key = "vignetteRadarChevronDistance", type = "number", default = 4, label = "Chevron Gap",
    format = Pixels, choices = Values({ 2, 3, 4, 5, 6, 7, 8, 9 }, Pixels) }
guides{ key = "vignetteRadarHeadingLength", type = "number", default = .3, label = "Facing Line Length",
    format = Percent, choices = Values({ .12, .16, .2, .25, .3, .35, .4, .5, .6, .7, .8 }, Percent) }
guides{ key = "vignetteRadarFullSweep", type = "bool", default = false, label = "Animated Sweep",
    tooltip = "A slow sweep line across the whole radar." }

-- Alerts ------------------------------------------------------------------

local alerts = In("Alerts", "Detections")
alerts{ key = "vignetteRadarAlerts", type = "bool", default = true, label = "Pulse For New Detections" }
alerts{ key = "vignetteRadarAlertSound", type = "bool", default = false, label = "Play Alert Sound" }
for _, category in ipairs({ { "rare", "Alert For Rares And Bosses" }, { "treasure", "Alert For Treasures" },
    { "event", "Alert For Events" }, { "other", "Alert For Other" } }) do
    alerts{ key = "vignetteRadarAlertCategories", subkey = category[1], type = "bool",
        default = category[1] == "rare" or category[1] == "treasure", label = category[2] }
end
alerts{ key = "vignetteRadarAlertCooldown", level = A, type = "number", default = 60, label = "Repeat After",
    choices = { { 30, "30 sec" }, { 60, "60 sec" }, { 120, "120 sec" } } }

local tiers = In("Alerts", "Smart Alerts", { note = "Favorites always alert. Alt-click a marker to make it a favorite." })
tiers{ key = "vignetteRadarAlertSmart", type = "bool", default = true, label = "Only Worth-It Alerts",
    tooltip = "Skip alerts for points already done today or past the alert range." }
tiers{ key = "vignetteRadarAlertRange", level = A, type = "number", default = 1200, label = "Alert Within",
    choices = { { 0, "Radar Range" }, { 600, "600 yd" }, { 1200, "1200 yd" }, { 2400, "2400 yd" },
        { 10000, "Whole Zone" } } }
tiers{ key = "vignetteRadarAlertBanner", type = "choice", default = "favorite", label = "Raid Warning Text",
    tooltip = "Show the alert in the middle of the screen.",
    choices = { { "off", "Off" }, { "favorite", "Favorites" }, { "all", "Every Alert" } } }
tiers{ key = "vignetteRadarAlertFlash", level = A, type = "bool", default = true, label = "Flash Taskbar",
    tooltip = "Flash the game's taskbar icon when an alert comes while the game is in the background." }

local approach = In("Alerts", "Approach", { level = A })
approach{ key = "vignetteRadarApproachAlerts", type = "bool", default = false, label = "Alert Near Watched Targets",
    tooltip = "Ctrl-Alt-click a marker to watch it." }
approach{ key = "vignetteRadarApproachDistance", type = "number", default = 100, label = "Approach Distance",
    format = Yards, choices = Values({ 25, 50, 75, 100, 150, 200, 300, 400, 600 }, Yards) }

-- Markers -----------------------------------------------------------------

local function Legend(name)
    return function(value, subkey)
        local legend = addon.VignetteRadarLegend
        if legend and legend[name] then
            if subkey ~= nil then legend[name](subkey, value) else legend[name](value) end
        end
    end
end

local markers = In("Markers", "Show Markers")
for _, category in ipairs({ { "rare", "Rares And Bosses" }, { "treasure", "Treasures" },
    { "event", "Events" }, { "other", "Other" } }) do
    markers{ key = "vignetteRadarCategories", subkey = category[1], type = "bool", default = true,
        label = category[2], validatedBy = "legend", set = Legend("SetCategoryEnabled") }
end
markers{ key = "vignetteRadarHighlight", type = "choice", default = "all", label = "Spotlight",
    tooltip = "Dim every marker type except one.", validatedBy = "legend",
    choices = { { "all", "All" }, { "rare", "Rares" }, { "treasure", "Loot" }, { "event", "Events" },
        { "other", "Other" } },
    get = function(db) return db.vignetteRadarHighlight or "all" end, set = Legend("SetHighlight") }
markers{ key = "vignetteRadarMarkerSize", type = "number", default = 7, label = "Marker Size",
    choices = { { 5, "Small" }, { 7, "Medium" }, { 9, "Large" } } }
markers{ key = "vignetteRadarShowHealth", level = A, type = "bool", default = true, label = "Focused Rare Health" }
markers{ key = "vignetteRadarSourceBadges", level = A, type = "bool", default = true, label = "Marker Source Badges",
    tooltip = "A small badge shows where a marker came from." }

local worth = In("Markers", "Worth-It Facts", { note = "The Guide Panel shows them for the focused point." })
worth{ key = "vignetteRadarWorthTooltip", level = A, type = "bool", default = true, label = "Facts In Marker Tooltips",
    tooltip = "Add health, ETA, done today and last seen to marker tooltips.", refresh = false }

local packs = In("Markers", "Map Data Packs", { note = "Left-click: use everywhere. Right-click: only in this zone." })
packs{ key = "vignetteRadarPOISource", type = "choice", default = "auto", label = "Map Pack",
    tooltip = "Which HandyNotes pack supplies map notes.", widget = "poiSources", open = true,
    choices = { { "none", "Off" }, { "auto", "Auto" } },
    set = function(value, _, db)
        db.vignetteRadarPOISource = value
        db.vignetteRadarMapNotesVisible = value ~= "none"
        if addon.ValidateSettings then addon.ValidateSettings() end
        RefreshRadar("full")
    end,
    tags = { "handynotes", "pack", "notes" } }
for _, kind in ipairs({ { "treasure", "Treasure Notes" }, { "mob", "Mob Notes" }, { "item", "Item Notes" },
    { "note", "Other Notes" }, { "entrance", "Entrance Notes" } }) do
    packs{ key = "vignetteRadarPOITypes", subkey = kind[1], level = A, type = "bool", default = true, label = kind[2] }
end
packs{ key = "vignetteRadarPOIIcons", level = A, type = "bool", default = false, label = "Pack Icons",
    tooltip = "Use each pack's own icons where it has them.", refresh = "light" }
packs{ key = "vignetteRadarDataStatus", level = A, type = "bool", default = false, label = "Explain Missing Map Data" }

local declutter = In("Markers", "Declutter", { note = "Applies to map pack notes. The focused point always stays." })
declutter{ key = "vignetteRadarDeclutter", type = "bool", default = true, label = "Hide Done And Duplicate Notes",
    tooltip = "Hide notes whose quest is done, notes next to a live rare or treasure, and rares killed since the daily reset." }
declutter{ key = "vignetteRadarDeclutterLiveOnly", level = A, type = "bool", default = false, label = "Packs Only When Nothing Live",
    tooltip = "Hide every pack note while a live rare or treasure is up." }
declutter{ key = "vignetteRadarDeclutterRange", level = A, type = "number", default = 0, label = "Packs Only Within",
    choices = { { 0, "Any Range" }, { 150, "150 yd" }, { 300, "300 yd" }, { 600, "600 yd" }, { 1200, "1200 yd" } },
    tags = { "clutter", "range", "distance" } }

local area = In("Markers", "Events, Delves And Races", { note = "Live from Blizzard's map, with countdowns." })
area{ key = "vignetteRadarAreaPOIs", type = "bool", default = true, label = "Show Area Points",
    tooltip = "Events, delves and races in your zone show on the radar and can be focused.",
    onChange = function() Call("VignetteRadarAreaPOIs", "Invalidate") end, tags = { "event", "delve", "race", "poi" } }
for _, kind in ipairs({ { "event", "Events" }, { "delve", "Delves" }, { "race", "Races" } }) do
    area{ key = "vignetteRadarAreaPOIKinds", subkey = kind[1], level = A, type = "bool", default = true, label = kind[2],
        onChange = function() Call("VignetteRadarAreaPOIs", "Invalidate") end }
end
area{ key = "vignetteRadarAreaPOIRoute", level = A, type = "bool", default = true, label = "Include In Closest Route",
    tooltip = "Auto Route's Closest choice can stop at them too.", refresh = false }

local tracked = In("Markers", "Tracked Collections",
    { note = "What you track in Blizzard's collections, like a mount or an appearance." })
tracked{ key = "vignetteRadarCollectionTracking", type = "bool", default = true, label = "Show Tracked Collections",
    tooltip = "Where Blizzard says a tracked mount or appearance comes from in your zone, or the next step there.",
    onChange = function() Call("VignetteRadarCollectionTracking", "Invalidate") end,
    tags = { "collection", "tracking", "mount", "appearance", "transmog" } }
tracked{ key = "vignetteRadarCollectionTrackingRoute", level = A, type = "bool", default = true,
    label = "Include In Closest Route", tooltip = "Auto Route's Closest choice can stop at them too.", refresh = false }

local lootLens = In("Markers", "Collection Lens",
    { note = "Loot comes from map packs that list it. Others show No Loot Data." })
lootLens{ key = "vignetteRadarCollectionLens", type = "choice", default = "mark", label = "Uncollected Loot",
    choices = { { "off", "Off" }, { "mark", "Mark" }, { "hide", "Hide Collected" }, { "only", "Only Uncollected" } },
    tooltip = "Mark puts a chest badge on rares and treasures that drop a mount, pet, toy or look you lack. "
        .. "Hide Collected hides pack notes with nothing left. Only Uncollected also hides notes with no loot data.",
    tags = { "loot", "mount", "pet", "toy", "transmog", "collection", "lens" } }

local plates = In("Markers", "Nameplate Marker", { note = "Skipped silently where Blizzard hides unit identity." })
plates{ key = "vignetteRadarNameplateMarker", type = "bool", default = true, label = "Mark Rare Nameplates",
    tooltip = "Put the rare's icon over its nameplate when it is in view.", refresh = false,
    onChange = function() Call("VignetteRadarNameplateMarker", "Configure") end, tags = { "nameplate", "rare", "crowd" } }
plates{ key = "vignetteRadarNameplateMarkerWho", level = A, type = "choice", default = "favorite", label = "Mark", refresh = false,
    choices = { { "focus", "Focused Rare" }, { "favorite", "Focus And Favorites" }, { "rare", "Every Rare" } },
    tooltip = "Every Rare also marks nameplates Blizzard calls rare, even without a vignette.",
    onChange = function() Call("VignetteRadarNameplateMarker", "Configure") end }
plates{ key = "vignetteRadarNameplateMarkerScale", level = A, type = "number", default = 1, label = "Icon Size", refresh = false,
    choices = { { .75, "Small" }, { 1, "Normal" }, { 1.25, "Large" }, { 1.5, "Huge" } },
    onChange = function() Call("VignetteRadarNameplateMarker", "Configure") end }

local takeover = In("Markers", "Pack Takeover",
    { level = A, note = "Magpie saves the notes your packs show, zone by zone. RareScanner pins cannot be hidden." })
takeover{ key = "vignetteRadarPackRemember", type = "bool", default = true, label = "Remember Pack Notes",
    tooltip = "Keep a compact copy of each zone's pack notes, so Magpie still has them after you disable the packs.",
    set = function(value, _, db)
        db.vignetteRadarPackRemember = value
        if not value then Call("VignetteRadarPackStore", "Clear") end
        Call("VignetteRadarPOIs", "Invalidate")
        RefreshRadar("full")
    end, tags = { "handynotes", "cache", "packs" } }
takeover{ key = "vignetteRadarPackTakeover", type = "bool", default = false, label = "Hide HandyNotes Pins",
    tooltip = "Magpie draws the pack notes itself, decluttered, and turns off the packs' own map and minimap pins.",
    set = function(value, _, db)
        db.vignetteRadarPackTakeover = value
        Call("VignetteRadarPackStore", "ApplyTakeover")
        RefreshRadar("full")
    end, tags = { "handynotes", "hide", "clutter", "pins" } }

local fusion = In("Markers", "Source Fusion", { level = A })
fusion{ key = "vignetteRadarSourceFusion", type = "bool", default = false, label = "Combine Selected Map Packs",
    tooltip = "One marker per matching place; live sightings stay distinct." }
fusion{ key = "vignetteRadarFusionSources", type = "list", default = {}, label = "Fused Packs",
    tooltip = "Choose up to 8 packs. Right-click to prefer one here.", widget = "fusionSources" }
fusion{ key = "vignetteRadarFusionDistance", type = "number", default = .002, label = "Match Within",
    choices = { { .001, "Tight" }, { .002, "Normal" }, { .005, "Loose" } } }

local lens = In("Markers", "Hold-To-Filter Key", { level = A, note = "Assign the key in WoW's AddOns key bindings." })
lens{ key = "vignetteRadarLensEnabled", type = "bool", default = false, label = "Enable Hold-To-Filter Key" }
lens{ key = "vignetteRadarLensCategory", type = "choice", default = "quest", label = "Key Shows",
    choices = { { "quest", "Quests" }, { "rare", "Rares" }, { "treasure", "Treasure" } } }

-- Quests ------------------------------------------------------------------

local quests = In("Quests", "Quests On The Radar")
quests{ key = "vignetteRadarQuestDots", type = "bool", default = false, label = "Show Quest Diamonds" }
quests{ key = "vignetteRadarQuestColors", level = A, type = "bool", default = true, label = "Color Quest Diamonds" }
quests{ key = "vignetteRadarQuestNumbers", level = A, type = "bool", default = false, label = "Number Quest Diamonds" }
quests{ key = "vignetteRadarQuestAreas", type = "bool", default = false, label = "Shade Blizzard Quest Areas" }
quests{ key = "vignetteRadarQuestHalos", level = A, type = "bool", default = true, label = "Approximate Quest Circles" }
quests{ key = "vignetteRadarQuestAreaColors", level = A, type = "bool", default = false, label = "Color Quest Circles" }
quests{ key = "vignetteRadarQuestHaloRadius", level = A, type = "number", default = 10, label = "Circle Radius",
    format = Yards, choices = Values({ 10, 20, 40, 80 }, Yards) }
quests{ key = "vignetteRadarFollowTrackedQuest", type = "bool", default = false,
    label = "Outline The Tracked Quest" }
quests{ key = "vignetteRadarEdgeCues", level = A, type = "bool", default = true, label = "Nearby Off-Screen Cues" }
quests{ key = "vignetteRadarQuestStartBadges", type = "bool", default = false, label = "Quest-Line Starts" }
quests{ key = "vignetteRadarNextQuestStep", level = A, type = "bool", default = false, label = "Use Blizzard's Next Step" }
quests{ key = "vignetteRadarQuestKeyProgress", level = A, type = "bool", default = true, label = "Progress In Quest Key" }

local guidance = In("Quests", "Quest Guidance")
guidance{ key = "vignetteRadarQuestSuperTrack", type = "bool", default = true,
    label = "Blizzard Guides Quest Objectives", onChange = RefreshWorldMarker }
guidance{ key = "vignetteRadarQuestPinWhenClose", level = A, type = "bool", default = true,
    label = "Pin Exact Quest Spot When Close", onChange = RefreshWorldMarker,
    tooltip = "Inside a quest area Blizzard hides its marker; a pin keeps the exact spot shown." }
guidance{ key = "vignetteRadarRouteNextStep", level = A, type = "bool", default = true, label = "Next Step On Guide Panel",
    tooltip = "Blizzard's route hint (\"Take the portal to ...\") shows before the quest objective.",
    onChange = function() RefreshGuide() end }
guidance{ key = "vignetteRadarAreaQuests", type = "bool", default = true, label = "Quests Here Only",
    tooltip = "Tracker and Bearing Bar list only quests in this area." }

local questRouting = In("Quests", "Quest Routing",
    { note = "Focused quests stay first. A quest stays the stop until it is turned in." })
questRouting{ key = "vignetteRadarAutoRouteQuestMoveOn", type = "choice", default = "last",
    label = "Move On",
    tooltip = "When the route leaves the active quest for the next stop.",
    choices = { { "last", "After Last Objective" }, { "each", "After Each Objective" } } }
questRouting{ key = "vignetteRadarAutoRouteQuestNearest", type = "bool", default = true,
    label = "Then Go To Closest",
    tooltip = "On: after moving on, pick the closest stop of any quest. Off: a Quest route stays on the same quest's objectives first." }
questRouting{ key = "vignetteRadarAutoRouteQuestStarts", type = "bool", default = true,
    label = "Include Quest Starts" }
questRouting{ key = "vignetteRadarAutoRouteNearbyZones", level = A, type = "bool", default = true,
    label = "Continue Into Nearby Zones" }
questRouting{ key = "vignetteRadarWorldQuestPriority", type = "bool", default = true,
    label = "Prefer Nearby World Quests" }
questRouting{ key = "vignetteRadarWorldQuestPriorityRange", level = A, type = "number", default = 300,
    label = "Prefer Within", format = Yards, choices = Values({ 150, 300, 600 }, Yards) }
questRouting{ key = "vignetteRadarLearnedQuestHints", level = A, type = "bool", default = true,
    label = "Learned Objective Hints" }

local questItem = In("Quests", "Quest Item Button",
    { note = "Bind a key under AddOns: Use Quest Item. It cannot change during combat." })
questItem{ key = "vignetteRadarQuestItemButton", type = "bool", default = true, label = "Show Quest Item Button",
    tooltip = "A button for the usable item of the quest you are going for, under the radar.", refresh = false,
    onChange = function() Call("VignetteRadarQuestItemButton", "Refresh") end, tags = { "item", "use", "quest", "button" } }

-- Routes ------------------------------------------------------------------

local arrival = { { 10, "10 yd" }, { 20, "20 yd" }, { 40, "40 yd" } }
local focusArrival = { { 3, "3 yd" }, { 5, "5 yd" }, { 10, "10 yd" }, { 20, "20 yd" }, { 40, "40 yd" } }

local focus = In("Routes", "World Focus")
focus{ key = "vignetteRadarWorldFocusEnabled", type = "bool", default = true,
    label = "Click Markers To Focus", tooltip = "Clicking a marker sets one world waypoint." }
focus{ key = "vignetteRadarWorldFocusAutoAdvance", type = "bool", default = false, label = "Advance When You Arrive" }
focus{ key = "vignetteRadarWorldFocusRoutes", level = A, type = "bool", default = true, label = "Follow Pack Path Steps",
    tooltip = "Use a pack's entrance and path steps when it has them." }
focus{ key = "vignetteRadarTreasurePlaybooks", level = A, type = "bool", default = true, label = "Treasure Path Steps",
    tooltip = "Include treasure entrance and path steps in routes." }
focus{ key = "vignetteRadarWorldFocusSavedNotes", level = A, type = "bool", default = false, label = "Include Saved Notes" }
focus{ key = "vignetteRadarLiveRareFollow", level = A, type = "bool", default = true, label = "Follow Moving Rares",
    tooltip = "A live rare is tracked itself, so the waypoint and beam walk with it instead of a fixed pin.",
    tags = { "vignette", "super-track", "walking" } }
focus{ key = "vignetteRadarWorldFocusArrivalRadius", level = A, type = "number", default = 20,
    label = "Rare Arrival Distance", choices = focusArrival }
focus{ key = "vignetteRadarKeepMarkerUntilDone", level = A, type = "bool", default = false,
    label = "Keep Marker Until Looted Or Killed",
    tooltip = "Rare and treasure markers stay until you loot the treasure or the rare dies, not when you arrive." }

-- One panel for where to go next (UI/GuidePanel.lua, fed by Core/Guidance.lua).
-- It replaced the route card, Upcoming Stops, the Next 3 Stops Strip, the
-- Worth-It Card and the Zone Briefing; their names stay as search tags.
local guide = In("Routes", "Guide Panel",
    { note = "Drag it to move it. Hover it for dock and lock. Right-click it for these settings." })
guide{ key = "vignetteRadarGuidePanel", type = "bool", default = true, label = "Show Guide Panel",
    tooltip = "Where you are going: direction, distance, ETA, the next stops and what to do there.",
    refresh = false, onChange = function() RefreshGuide() end,
    tags = { "route card", "mini route arrow", "next 3 stops", "upcoming stops", "worth-it card", "zone briefing" } }
guide{ key = "vignetteRadarGuideDensity", type = "choice", default = "expanded", label = "Layout",
    tooltip = "Compact: name, distance, a strip of stops and the action icons. Click the panel's name to switch.",
    refresh = false, onChange = function() RefreshGuide() end,
    choices = { { "compact", "Compact" }, { "expanded", "Full" } } }
guide{ key = "vignetteRadarGuideStops", type = "number", default = 3, label = "Next Stops To Show",
    refresh = false, onChange = function() RefreshGuide() end, choices = Values({ 1, 2, 3, 4, 5 }) }
for _, block in ipairs({ { "step", "Quest Step And Notes", "The quest objective, Blizzard's route hint or the map note." },
    { "facts", "Worth-It Facts", "Health, group, done today and last seen." },
    { "stops", "Next Stops", "Click one to go there now." },
    { "briefing", "Zone Arrival Briefing", "After entering a zone, and while nothing is focused: rares up, treasures left, events and quests here. Click it to start Closest." },
    { "actions", "Action Icons", "Lock, skip, why this stop and share." },
    { "notice", "Route Notes", "Route messages show in the panel instead of under the radar." } }) do
    guide{ key = "vignetteRadarGuideBlocks", subkey = block[1], type = "bool", default = true, label = block[2],
        tooltip = block[3], refresh = false, onChange = function() RefreshGuide() end }
end
-- The optional strip of the Compass system (Core/Compass.lua), off by default.
guide{ key = "vignetteRadarGuideBlocks", subkey = "compass", level = A, type = "bool", default = false,
    label = "Compass Strip",
    tooltip = "A thin compass in the panel: the next stops, the focus and live rares, where they lie as you face.",
    refresh = false, onChange = function() RefreshGuide() end, tags = { "bearing", "compass", "horizon" } }
guide{ key = "vignetteRadarGuideWidth", level = A, type = "number", default = 260, label = "Panel Width",
    format = Pixels, choices = Values({ 200, 260, 320 }, Pixels), refresh = false,
    onChange = function() RefreshGuide() end }
guide{ key = "vignetteRadarGuideBriefingSeconds", level = A, type = "number", default = 20,
    label = "Show Arrival For", choices = { { 10, "10 sec" }, { 20, "20 sec" }, { 40, "40 sec" } },
    refresh = false, onChange = function() RefreshGuide() end }
-- Block order: written by the Guide Panel card's move buttons (UI/QuickConfig.lua).
Schema.Define({ key = "vignetteRadarGuideOrder", type = "list", hidden = true, label = "Block Order",
    refresh = false, onChange = function() RefreshGuide() end })

local autoRoute = In("Routes", "Auto Route")
autoRoute{ key = "vignetteRadarAutoRouteOnSelect", type = "bool", default = false, label = "Start On Click" }
autoRoute{ key = "vignetteRadarAutoRouteRestore", level = A, type = "bool", default = true, label = "Resume On Reload" }
autoRoute{ key = "vignetteRadarAutoRouteMapNotes", type = "bool", default = false, label = "Include Map Pack" }
autoRoute{ key = "vignetteRadarWorldFocusSmoothWaypoint", level = A, type = "bool", default = true, label = "Smooth Pin" }
autoRoute{ key = "vignetteRadarWorldFocusThemedWaypoint", level = A, type = "bool", default = true, label = "Color World Pin" }
autoRoute{ key = "vignetteRadarAutoRouteTravel", level = A, type = "choice", default = "auto", label = "Travel Mode",
    choices = { { "auto", "Auto" }, { "ground", "Ground" }, { "flying", "Flying" } } }
autoRoute{ key = "vignetteRadarAutoRouteArrivalRadius", level = A, type = "number", default = 10,
    label = "Rare Arrival Distance", choices = focusArrival }

local draft = In("Routes", "Route Draft", { level = A })
draft{ key = "vignetteRadarRouteAutoAdvance", type = "bool", default = false, label = "Advance Route On Arrival" }
draft{ key = "vignetteRadarRouteArrivalRadius", type = "number", default = 20, label = "Arrival Distance",
    choices = arrival }
draft{ key = "vignetteRadarActiveCue", type = "bool", default = true, label = "Highlight Active Destination" }

local share = In("Routes", "Share To Group", { note = "The Share button sits on the Guide Panel." })
share{ key = "vignetteRadarShareButton", type = "bool", default = true, label = "Share Button",
    tooltip = "Post the focused point to chat as a map pin link.", refresh = false,
    onChange = function() RefreshGuide() end, tags = { "party", "link", "pin" } }
share{ key = "vignetteRadarShareChannel", level = A, type = "choice", default = "auto", label = "Post To", refresh = false,
    choices = { { "auto", "Auto" }, { "party", "Party" }, { "raid", "Raid" }, { "say", "Say" } },
    tooltip = "Auto picks raid, party or instance chat, and say when you are alone." }
share{ key = "vignetteRadarShareAddon", level = A, type = "bool", default = true, label = "Tell Magpie Users",
    tooltip = "Also send the point to group members who run Magpie.", refresh = false }

local sightings = In("Routes", "Shared Sightings",
    { note = "Points your group shares show as notes marked Party until they expire." })
sightings{ key = "vignetteRadarSharedSightings", type = "bool", default = true, label = "Show Group Sightings",
    tooltip = "Points Magpie users in your group share become radar notes you can route to.",
    onChange = function() Call("VignetteRadarSharedSightings", "Register") end,
    tags = { "party", "group", "raid", "share", "sighting" } }
sightings{ key = "vignetteRadarSharedSightingsChat", type = "bool", default = true, label = "Read Map Pin Links",
    tooltip = "Map pin links posted in party, raid or instance chat become notes too." }
sightings{ key = "vignetteRadarSharedSightingsMinutes", level = A, type = "choice", default = 10, label = "Keep For",
    choices = { { 5, "5 Min" }, { 10, "10 Min" }, { 20, "20 Min" } }, refresh = false,
    tooltip = "How long a shared point stays on the radar." }

local sweep = In("Routes", "Zone Sweep",
    { note = "Plans one loop over every rare and treasure not done in this zone. /magpie sweep starts it too." })
sweep{ key = "vignetteRadarZoneSweepKinds", type = "choice", default = "both", label = "Sweep For", refresh = false,
    choices = { { "both", "Rares And Treasures" }, { "rare", "Rares" }, { "treasure", "Treasures" } },
    tags = { "loop", "route", "all", "plan" } }
sweep{ key = "vignetteRadarZoneSweepMax", level = A, type = "choice", default = 40, label = "Most Stops", refresh = false,
    choices = { { 20, "20" }, { 40, "40" }, { 60, "60" }, { 80, "80" } },
    tooltip = "Over this many, the nearest stops are kept." }

local mapRoute = In("Routes", "World Map Route",
    { note = "Draws the running Auto Route on the world map: a line and numbered stops." })
mapRoute{ key = "vignetteRadarMapRoute", type = "bool", default = true, label = "Show Route On World Map",
    refresh = false, onChange = function() Call("VignetteRadarMapRoute", "Refresh") end,
    tags = { "map", "world map", "route", "line", "stops" } }
mapRoute{ key = "vignetteRadarMapRouteSweep", level = A, type = "bool", default = true, label = "Whole Sweep Loop",
    tooltip = "During a Zone Sweep, show every planned stop, not just the next few.",
    refresh = false, onChange = function() Call("VignetteRadarMapRoute", "Refresh") end }

local eta = In("Routes", "Live ETA", { note = "Uses your real speed: running, flying or skyriding." })
eta{ key = "vignetteRadarLiveEta", type = "bool", default = true, label = "Show Live ETA",
    tooltip = "Seconds or minutes to the point and the next stops on the Guide Panel.", refresh = false,
    onChange = function() RefreshGuide() end, tags = { "eta", "time", "speed", "skyriding" } }

local way = In("Routes", "Waypoint Commands", { level = A, note = "/vrway always works. Changes apply after /reload." })
way{ key = "vignetteRadarWayCommand", type = "bool", default = true, label = "/way Command",
    tooltip = "/way [#mapID] x y [title] sets the World Focus waypoint. Skipped when TomTom or another addon owns /way.",
    refresh = false, onChange = function() Call("VignetteRadarWay", "Install") end, tags = { "tomtom", "way", "coordinates" } }
way{ key = "vignetteRadarTomTomStandIn", type = "bool", default = true, label = "TomTom Stand-In",
    tooltip = "Without TomTom installed, addons that send TomTom waypoints send them to Magpie instead.",
    refresh = false, onChange = function() Call("VignetteRadarWay", "Install") end, tags = { "tomtom", "waypoint", "compat" } }

local zygor = In("Routes", "Zygor", { note = "Manual waypoints pause Follow until you resume it." })
zygor{ key = "vignetteRadarWorldFocusZygor", type = "bool", default = false, label = "Show Zygor Step On Radar" }
zygor{ key = "vignetteRadarFollowZygor", type = "bool", default = false, label = "Follow Active Guide",
    set = function(value, _, db)
        local bridge = addon.VignetteRadarZygor
        if not bridge then
            db.vignetteRadarFollowZygor = value
            RefreshRadar("full")
            return true
        end
        local ready, reason = true, nil
        if value then ready, reason = addon.VignetteRadarAPI.BindZygorGuide() end
        if ready then
            bridge.SetFollow(value)
            return true
        end
        db.vignetteRadarFollowZygor = false
        return false, reason or "Zygor is unavailable"
    end }
zygor{ key = "vignetteRadarZygorMode", level = A, type = "choice", default = "objective", label = "Follow Destination",
    choices = { { "objective", "Objective" }, { "travel", "Travel Stop" } },
    set = function(value, _, db)
        if addon.VignetteRadarZygor then addon.VignetteRadarZygor.SetMode(value)
        else db.vignetteRadarZygorMode = value end
    end }

local compass = In("Routes", "Sound Compass", { advanced = true, level = A })
compass{ key = "vignetteRadarSoundCompassEnabled", type = "bool", default = false,
    label = "Direction Cues For Active Stop", onChange = ConfigureRuntime }
compass{ key = "vignetteRadarSoundCompassMode", type = "choice", default = "text", label = "Cue Style",
    choices = { { "text", "Text" }, { "tone", "Tone" } }, onChange = ConfigureRuntime }
compass{ key = "vignetteRadarSoundCompassCooldown", type = "number", default = 6, label = "Repeat After",
    choices = { { 3, "3 sec" }, { 6, "6 sec" }, { 12, "12 sec" } }, onChange = ConfigureRuntime }
compass{ key = "vignetteRadarContextDirectorEnabled", type = "bool", default = false,
    label = "Context-Aware Radar View", onChange = ConfigureRuntime }

-- HUD ---------------------------------------------------------------------

local marker = In("HUD", "In-World Marker")
marker{ key = "vignetteRadarWorldMarker", type = "bool", default = true, label = "Marker At The Waypoint",
    onChange = RefreshWorldMarker }
marker{ key = "vignetteRadarWorldMarkerBeam", type = "bool", default = true, label = "Glowing Light Beam",
    onChange = RefreshWorldMarker }
marker{ key = "vignetteRadarWorldMarkerText", level = A, type = "bool", default = true, label = "Name, Distance And Next Step",
    onChange = RefreshWorldMarker }
marker{ key = "vignetteRadarWorldMarkerCombatFade", level = A, type = "bool", default = true, label = "Fade In Combat",
    tooltip = "Fade the marker and the Guide Panel during combat.",
    onChange = function() RefreshWorldMarker(); RefreshGuide() end }

local bearing = In("HUD", "Bearing Bar", { note = "Drag the bar's top edge to move it. Click a card to focus it." })
bearing{ key = "vignetteRadarBeaconsEnabled", type = "bool", default = false, label = "Show Bearing Bar",
    tooltip = "A multi-point bearing display across the screen.", tags = { "beacons" } }
bearing{ key = "vignetteRadarBeaconRares", level = A, type = "bool", default = true, label = "Rares" }
bearing{ key = "vignetteRadarBeaconTreasures", level = A, type = "bool", default = true, label = "Loot And Caves" }
bearing{ key = "vignetteRadarBeaconQuests", level = A, type = "bool", default = true, label = "Quests" }
bearing{ key = "vignetteRadarBeaconRange", level = A, type = "number", default = 1200, label = "Show Within",
    choices = Values({ 150, 450, 1200, 2400 }, Yards) }
bearing{ key = "vignetteRadarBeaconMax", level = A, type = "number", default = 8, label = "Most Points",
    choices = Values({ 4, 8, 12, 16, 24 }) }

local ribbon = In("HUD", "Horizon Ribbon", { note = "A thin compass at the top of the screen. The focus also gets the in-world beam." })
local function RefreshRibbon() Call("VignetteRadarHorizonRibbon", "Refresh") end
ribbon{ key = "vignetteRadarHorizonRibbon", type = "bool", default = false, label = "Show Horizon Ribbon",
    tooltip = "Ticks for the next three route stops, the focus and live rares, where they lie as you turn.",
    refresh = false, onChange = RefreshRibbon, tags = { "compass", "ribbon", "bearing", "stops" } }
ribbon{ key = "vignetteRadarHorizonRibbonRares", level = A, type = "bool", default = true, label = "Live Rares On Ribbon",
    refresh = false, onChange = RefreshRibbon }
ribbon{ key = "vignetteRadarHorizonRibbonWidth", level = A, type = "number", default = 440, label = "Ribbon Width", format = Pixels,
    choices = Values({ 320, 440, 600 }, Pixels), refresh = false, onChange = RefreshRibbon }
ribbon{ key = "vignetteRadarHorizonRibbonOffset", level = A, type = "number", default = 40, label = "Distance From Top",
    format = Pixels, choices = Values({ 8, 40, 80, 120 }, Pixels), refresh = false, onChange = RefreshRibbon }

local constellation = In("HUD", "Constellation", { level = A })
constellation{ key = "vignetteRadarConstellationEnabled", type = "bool", default = false,
    label = "Show Constellation HUD", set = function(value, _, db)
        if addon.VignetteRadarConstellation then addon.VignetteRadarConstellation.SetEnabled(value)
        else db.vignetteRadarConstellationEnabled = value end
    end }
constellation{ key = "vignetteRadarConstellationSourceMode", type = "choice", default = "mixed",
    label = "Points From", choices = { { "live", "Live Only" }, { "pack", "Map Pack" }, { "mixed", "Mixed" } },
    set = function(value, _, db)
        if addon.VignetteRadarConstellation then addon.VignetteRadarConstellation.SetSourceMode(value)
        else db.vignetteRadarConstellationSourceMode = value end
    end }
local function ConstellationKey(key)
    return function(value, subkey, db) Constellation(value, subkey, db, key) end
end
constellation{ key = "vignetteRadarConstellationGuidance", type = "bool", default = true,
    label = "Guidance Ant Trail", set = ConstellationKey("vignetteRadarConstellationGuidance") }
constellation{ key = "vignetteRadarConstellationReducedMotion", type = "bool", default = false,
    label = "Reduced Motion", set = ConstellationKey("vignetteRadarConstellationReducedMotion") }
constellation{ key = "vignetteRadarConstellationSize", type = "number", default = 520, label = "Sphere Size",
    choices = Values({ 360, 420, 520, 620, 720, 800 }), set = ConstellationKey("vignetteRadarConstellationSize") }
constellation{ key = "vignetteRadarConstellationOpacity", type = "number", default = .75, label = "Marker Opacity",
    format = Percent, choices = Values({ .2, .35, .5, .65, .75, .9, 1 }, Percent),
    set = ConstellationKey("vignetteRadarConstellationOpacity") }
constellation{ key = "vignetteRadarConstellationOffsetY", type = "number", default = -.05,
    label = "Vertical Position", format = Percent,
    choices = Values({ -.20, -.10, -.05, 0, .05, .10, .20 }, Percent),
    set = ConstellationKey("vignetteRadarConstellationOffsetY") }
constellation{ key = "vignetteRadarConstellationMaxPoints", type = "number", default = 24, label = "Point Limit",
    choices = Values({ 12, 24, 36 }), set = ConstellationKey("vignetteRadarConstellationMaxPoints") }

-- Data --------------------------------------------------------------------

local presets = In("Data", "Hunting Presets")
presets{ key = "vignetteRadarJournalEnabled", type = "bool", default = false, label = "Save Sighting History",
    tags = { "journal" } }
local spawns = In("Data", "Learned Rare Spawns",
    { level = A, note = "Saved from live rares you see, at the rare's own position. Nothing is shipped." })
spawns{ key = "vignetteRadarRareSpawnLearning", type = "bool", default = true, label = "Learn Rare Spawns",
    tooltip = "Save where each live rare appears, grouped into spawn points per rare.", refresh = false,
    tags = { "learn", "spawn", "rare", "history" } }
spawns{ key = "vignetteRadarRareSpawnNotes", type = "bool", default = true, label = "Show Learned Spawns",
    tooltip = "While a rare is not up, show its learned spawns as notes, unless a map pack already has it there." }
local respawn = In("Data", "Respawn Estimate", { note = "Only from kills you saw yourself. Needs Learn Rare Spawns." })
respawn{ key = "vignetteRadarRespawnEstimate", type = "bool", default = true, label = "Show Respawn Estimate",
    tooltip = "Adds a Respawn row like Likely Up In ~20 min to the Guide Panel facts and marker tooltips.",
    refresh = false, tags = { "respawn", "timer", "rare", "kill" } }
local heat = In("Data", "Spawn History Heatmap", { note = "Drawn from your learned rare spawns and treasure loots." })
heat{ key = "vignetteRadarSpawnHeatmap", type = "bool", default = false, label = "Show Spawn Heatmap",
    tooltip = "A faint glow on the radar where rares and treasures have been before. Brighter means more often.",
    onChange = function() Call("VignetteRadarSpawnHeatmap", "Refresh") end, tags = { "heat", "spawn", "history" } }
heat{ key = "vignetteRadarSpawnHeatmapWorldMap", level = A, type = "bool", default = true, label = "Also On World Map",
    refresh = false, onChange = function() Call("VignetteRadarSpawnHeatmap", "Refresh") end }
In("Data", "Planning Tools", { advanced = true, level = A,
    note = "Historical reports never appear as live detections." })

-- Tools -------------------------------------------------------------------

local advancedTools = In("Tools", "Advanced Tools",
    { level = A, note = "Adds niche planning, survey and tracking tools." })
advancedTools{ key = "vignetteRadarAdvancedTools", type = "bool", default = false, label = "Show Advanced Tools",
    onChange = function() Call("VignetteRadarExploration", "RefreshPanel") end }
In("Tools", "Live Diagnostics", { level = A })
In("Tools", "Share Learned Data", { note = "One text string with your learned rare spawns and pins. "
    .. "Import only reads data, checks every value and never runs code. /magpie export and /magpie import work too." })
local performance = In("Tools", "Performance",
    { note = "Sustained high load slows updates; spikes pause briefly, then retry at Low CPU." })
performance{ key = "vignetteRadarPerformance", type = "choice", default = "standard", label = "Update Rate",
    tooltip = "Standard: 10 redraws/sec. Balanced: about 7. Low CPU: 4 and slower scans.",
    choices = { { "standard", "Standard" }, { "balanced", "Balanced" }, { "low", "Low CPU" } } }
local menu = In("Tools", "Addon Menu")
menu{ key = "vignetteRadarCompartment", type = "bool", default = true, label = "Minimap Addon Menu Entry",
    tooltip = "Takes effect after a reload." }

-- The settings window's own Simple / Advanced switch (in its header, no row).
Schema.Define({ key = "vignetteRadarConfigMode", type = "choice", default = "simple", hidden = true,
    label = "Settings Mode", refresh = false,
    choices = { { "simple", "Simple" }, { "advanced", "Advanced" } } })
