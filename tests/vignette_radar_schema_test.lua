-- Settings schema: Define/Get/Set/Search/Pages, and every entry the settings
-- window shows must be a key Core's ValidateSettings knows (or name its owner).
STANDARD_TEXT_FONT = "default.ttf"
VignetteRadarDB = {}
local addon = {}
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile("UI/Controls.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Schema.lua"))("VignetteRadar", addon)
local Schema = assert(addon.Schema)
assert(addon.VignetteRadarSchema == Schema, "the schema needs its addon-style alias")

-- Pages: nine rail pages, each with icons in order and at least one section.
local pages = Schema.Pages()
local expected = { "Radar", "Looks", "Alerts", "Markers", "Quests", "Routes", "HUD", "Data", "Tools" }
assert(#pages == #expected, "the settings window has nine pages")
for index, id in ipairs(expected) do
    assert(pages[index].id == id and pages[index].icon == index - 1 and #pages[index].sections > 0,
        "page " .. id .. " must keep its order, icon column and sections")
end

-- Every entry: a known type, a label, a page/section that exists, a default
-- that passes its own rules, and a key Core validates.
local db = addon.ValidateSettings()
local count = 0
for _, id in ipairs(Schema.order) do
    local entry = Schema.entries[id]
    count = count + 1
    assert(entry.id == id and type(entry.label) == "string" and entry.label ~= "", id .. " needs a label")
    assert(({ bool = true, number = true, choice = true, color = true, list = true })[entry.type],
        id .. " has an unknown type")
    local section = Schema.pages[entry.page] and Schema.pages[entry.page].sections[entry.section]
    assert(section, id .. " must sit in a defined page and section")
    if entry.validatedBy then
        assert(entry.validatedBy == "legend", id .. " names an unknown owner")
    else
        assert(db[entry.key] ~= nil, "schema key " .. entry.key .. " is not validated by Core")
        if entry.subkey ~= nil and entry.type ~= "color" then
            assert(type(db[entry.key]) == "table", entry.key .. " must be a table for subkeys")
        end
    end
    if entry.default ~= nil and (entry.type == "number" or entry.type == "choice") and not entry.open then
        local ok = Schema.Coerce(entry, entry.default)
        assert(ok, id .. " default must pass its own rules")
    end
    if entry.type == "bool" and entry.default ~= nil and not entry.validatedBy then
        local value = Schema.Get(entry.key, entry.subkey)
        assert(value == entry.default or (value == nil and entry.default == false),
            id .. " default must match Core's default")
    end
end
assert(count > 120, "the schema must cover the settings window: " .. count)

-- Define: a new entry joins its section in order; duplicates are refused.
Schema.DefinePage({ id = "Test", icon = 9 })
local defined = Schema.Define({ key = "vignetteRadarTestToggle", type = "bool", default = false,
    label = "Test Toggle", page = "Test", section = "Checks" })
assert(defined.order == 10 and Schema.Entry("vignetteRadarTestToggle") == defined
    and Schema.pages.Test.sections.Checks.entries[1] == defined, "Define must register in order")
assert(not pcall(Schema.Define, { key = "vignetteRadarTestToggle", type = "bool", label = "Again",
    page = "Test", section = "Checks" }), "Define must refuse a duplicate key")

-- Set: validates, writes, re-validates through Core, calls onChange and listeners.
local changed, heard = {}, {}
Schema.OnChange(function(key, value, subkey, ok) heard[#heard + 1] = { key, value, subkey, ok } end)
Schema.Define({ key = "vignetteRadarTestStep", type = "number", default = 2, min = 0, max = 10, step = 2,
    label = "Test Step", page = "Test", section = "Checks",
    onChange = function(value) changed[#changed + 1] = value end })
assert(Schema.Set("vignetteRadarTestStep", 5) and db.vignetteRadarTestStep == 6
    and changed[1] == 6 and heard[#heard][1] == "vignetteRadarTestStep" and heard[#heard][4] == true,
    "Set must clamp and round to the entry's step, then notify")
assert(Schema.Set("vignetteRadarTestStep", 99) and db.vignetteRadarTestStep == 10, "Set must clamp to max")
local ok, reason = Schema.Set("vignetteRadarTestStep", "lots")
assert(not ok and reason == "not a number" and db.vignetteRadarTestStep == 10, "Set must reject a bad type")

-- Choice lists: only listed values pass; Core still re-validates afterwards.
assert(Schema.Set("vignetteRadarMarkerSize", 9) and db.vignetteRadarMarkerSize == 9, "listed number must pass")
ok = Schema.Set("vignetteRadarMarkerSize", 8)
assert(not ok and db.vignetteRadarMarkerSize == 9, "an unlisted number must be refused")
assert(Schema.Set("vignetteRadarPerformance", "low") and db.vignetteRadarPerformance == "low"
    and not Schema.Set("vignetteRadarPerformance", "turbo") and db.vignetteRadarPerformance == "low",
    "choices must accept listed values only")
assert(Schema.Set("vignetteRadarAlertCategories", true, "event") and db.vignetteRadarAlertCategories.event == true
    and Schema.Get("vignetteRadarAlertCategories", "event") == true, "subkeys must write into their table")
assert(Schema.Set("vignetteRadarAlerts", 1) and db.vignetteRadarAlerts == true
    and Schema.Set("vignetteRadarAlerts", nil) and db.vignetteRadarAlerts == false,
    "booleans must coerce checkbox values")
assert(not Schema.Set("vignetteRadarNoSuchSetting", true), "unknown keys must be refused")

-- Custom setters run instead of the default write (here the radar's own Set*).
local rangeSet
addon.SetVignetteRadarRange = function(value) rangeSet = value; db.vignetteRadarRange = value end
assert(Schema.Set("vignetteRadarRange", 600) and rangeSet == 600, "range must go through the radar's setter")
assert(not Schema.Set("vignetteRadarRange", 601) and rangeSet == 600, "range must stay on the radar's steps")
local radarRefreshes = 0
addon.VignetteRadarAPI = { Refresh = function() radarRefreshes = radarRefreshes + 1 end,
    BindZygorGuide = function() return false, "Zygor has no active guide" end }
addon.VignetteRadarZygor = { SetFollow = function() error("follow must not start") end }
ok, reason = Schema.Set("vignetteRadarFollowZygor", true)
assert(not ok and reason == "Zygor has no active guide" and db.vignetteRadarFollowZygor == false
    and heard[#heard][4] == false, "a refused setter must report its reason to listeners")
Schema.Set("vignetteRadarSmartZoom", true)
assert(radarRefreshes > 0 and db.vignetteRadarSmartZoom == true, "plain writes must refresh the radar")

-- Colors: a table sets the slot, nil clears it.
assert(Schema.Set("vignetteRadarColors", { .2, .4, .6 }, "accent"))
local r = addon.VignetteRadarStyle.Color("accent")
assert(math.abs(r - .2) < .001 and addon.VignetteRadarStyle.IsCustomized(), "a color entry must set the slot")
Schema.Set("vignetteRadarColors", nil, "accent")
assert(not addon.VignetteRadarStyle.IsCustomized(), "nil must clear a custom color")

-- Search: words match labels, help, sections and choice names; Advanced
-- Tools entries stay hidden unless asked for.
local function Ids(results)
    local set = {}
    for _, entry in ipairs(results) do set[entry.id] = true end
    return set
end
local hits = Ids(Schema.Search("arrival"))
assert(hits.vignetteRadarRouteArrivalRadius and hits.vignetteRadarAutoRouteArrivalRadius
    and hits.vignetteRadarWorldFocusArrivalRadius and not hits.vignetteRadarRange, "search must match labels")
assert(Ids(Schema.Search("low cpu")).vignetteRadarPerformance, "search must match choice names")
assert(Ids(Schema.Search("FOCUS rare"))["vignetteRadarWorldFocusArrivalRadius"],
    "search must be case-insensitive and need every word")
assert(#Schema.Search("") == 0 and #Schema.Search("   ") == 0, "an empty search returns nothing")
assert(Schema.Search("enable radar")[1].id == "vignetteRadarEnabled", "exact label matches rank first")
assert(not Ids(Schema.Search("sound compass", { advanced = false })).vignetteRadarSoundCompassEnabled
    and Ids(Schema.Search("sound compass", { advanced = true })).vignetteRadarSoundCompassEnabled,
    "Advanced Tools entries appear in search only while the switch is on")
db.vignetteRadarAdvancedTools = false
assert(#Schema.Search("sound compass") == 0, "search follows the Advanced Tools switch by default")
assert(#Schema.Search("constellation") > 0, "Constellation is a normal (Advanced mode) section, not an Advanced Tool")

print("vignette radar schema tests passed")
