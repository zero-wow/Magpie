local _, addon = ...
if type(addon) ~= "table" then return end

-- Pack Takeover: VR's own compact copy of the HandyNotes pack notes it has
-- read. No pack data ships with VR; a zone is harvested from the user's own
-- installed packs the first time POIs.Collect reads it in a session, so the
-- packs can later be disabled and VR still has their notes.
--   PackStore.Save(source, mapID, notes)      after a live pack read
--   PackStore.Load(source, mapID, mapToWorld, mapVector) -> notes | nil
--   PackStore.Maps(source) / PackStore.Sources() / PackStore.Count(source, mapID)
--   PackStore.Generation()                    bumps on every change
--   PackStore.HiddenByVR(source)              true while VR hid its HandyNotes pins
--   PackStore.ApplyTakeover() / PackStore.Clear()
-- Saved shape (VignetteRadarDB.vignetteRadarPackCache):
--   [source] = { [mapID] = { at = serverTime, n = count, d = "line\nline" } }
-- One string per zone keeps SavedVariables small and is only parsed when
-- that zone is read; parsed zones stay in a small in-memory ring.
local PackStore = {}
addon.VignetteRadarPackStore = PackStore

local type, tostring, tonumber, pairs, ipairs, pcall = type, tostring, tonumber, pairs, ipairs, pcall
local floor, concat = math.floor, table.concat
local Field, Number, Text = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text

local MAX_NODES, MAX_ZONES, MAX_PARSED = 768, 600, 8
local SEP = "\t"
local KINDS = { treasure = true, mob = true, item = true, note = true, entrance = true }
local harvested = {}      -- source .. ":" .. mapID -> true once saved this session
local parsed, parsedOrder = {}, {}
local generation = 0

local function Settings() return addon.GetSettings() end

local function Store()
    local db = Settings()
    if type(db.vignetteRadarPackCache) ~= "table" then db.vignetteRadarPackCache = {} end
    return db.vignetteRadarPackCache
end

local function Now()
    local stamp = addon.Secret.Call(_G, "GetServerTime")
    return Number(stamp) or 0
end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("packs", fmt, ...) end
end

local function Clean(value, limit)
    value = Text(value)
    if not value then return "" end
    value = value:gsub("[\t\r\n]", " ")
    if #value > limit then value = value:sub(1, limit) end
    return value
end

local function Whole(value)
    value = Number(value)
    return value and value == floor(value) and value or nil
end

-- One note as one line: tail, mapID, coord, kind, quest, npc, object,
-- parentCoord, name, note. tail is the key after "source:mapID:".
local function Line(source, note)
    local key, mapID = Text(note.key), Whole(note.mapID)
    local x, y = Number(note.mapX), Number(note.mapY)
    local prefix = mapID and (source .. ":" .. mapID .. ":")
    if not (key and prefix and x and y and KINDS[note.kind]) or key:sub(1, #prefix) ~= prefix then return nil end
    local coord = floor(x * 10000 + .5) * 10000 + floor(y * 10000 + .5)
    return concat({ key:sub(#prefix + 1), mapID, coord, note.kind,
        Whole(note.questID) or "", Whole(note.npcID) or "", Whole(note.objectID) or "",
        Whole(note.parentCoord) or "", Clean(note.name, 96), Clean(note.note, 160) }, SEP)
end

local function Forget(source, mapID)
    local id = source .. ":" .. tostring(mapID)
    if parsed[id] then
        parsed[id] = nil
        for index, value in ipairs(parsedOrder) do
            if value == id then table.remove(parsedOrder, index); break end
        end
    end
end

-- Oldest zones go first once the whole store passes MAX_ZONES.
local function Trim(store)
    local total, oldest, oldSource, oldMap = 0, nil, nil, nil
    for source, maps in pairs(store) do
        for mapID, entry in pairs(maps) do
            total = total + 1
            local at = type(entry) == "table" and Number(entry.at) or 0
            if not oldest or at < oldest then oldest, oldSource, oldMap = at, source, mapID end
        end
    end
    if total > MAX_ZONES and oldSource then
        store[oldSource][oldMap] = nil
        if not next(store[oldSource]) then store[oldSource] = nil end
        Forget(oldSource, oldMap)
        return Trim(store)
    end
end

-- Saves what a live pack read returned for one zone, once per session.
function PackStore.Save(source, mapID, notes)
    local db = Settings()
    if db.vignetteRadarPackRemember ~= true or type(notes) ~= "table" then return false end
    source, mapID = Text(source, 128), Whole(mapID)
    if not (source and mapID) then return false end
    local id = source .. ":" .. mapID
    if harvested[id] then return false end
    local lines = {}
    for _, note in ipairs(notes) do
        if #lines >= MAX_NODES then break end
        local line = type(note) == "table" and Line(source, note)
        if line then lines[#lines + 1] = line end
    end
    -- An empty answer can mean the pack is still loading: keep what we had
    -- and try again on the next read.
    if #lines == 0 then return false end
    harvested[id] = true
    local store = Store()
    local data = concat(lines, "\n")
    local old = store[source] and store[source][mapID]
    if type(old) == "table" and old.d == data then
        old.at = Now()
        return false
    end
    store[source] = store[source] or {}
    store[source][mapID] = { at = Now(), n = #lines, d = data }
    Forget(source, mapID)
    Trim(store)
    generation = generation + 1
    Trace("saved %d notes from %s for map %d", #lines, source, mapID)
    return true
end

local function Parse(source, data)
    local notes = {}
    for line in data:gmatch("[^\n]+") do
        local f = {}
        for value in (line .. SEP):gmatch("([^\t]*)\t") do f[#f + 1] = value end
        local pointMap, coord = tonumber(f[2]), tonumber(f[3])
        if #f >= 10 and f[1] ~= "" and pointMap and coord and KINDS[f[4]] then
            notes[#notes + 1] = {
                key = source .. ":" .. pointMap .. ":" .. f[1], mapID = pointMap,
                mapX = floor(coord / 10000) / 10000, mapY = (coord % 10000) / 10000,
                source = source, kind = f[4], name = f[9] ~= "" and f[9] or nil,
                questID = tonumber(f[5]), npcID = tonumber(f[6]), objectID = tonumber(f[7]),
                parentCoord = tonumber(f[8]), note = f[10] ~= "" and f[10] or nil,
                evidence = "saved", cached = true,
            }
        end
    end
    return notes
end

-- Notes for one zone from the store, with world positions filled in. The
-- parse and the world conversion run once per zone; later calls reuse them.
function PackStore.Load(source, mapID, mapToWorld, mapVector)
    source, mapID = Text(source, 128), Whole(mapID)
    if not (source and mapID and type(mapToWorld) == "function" and type(mapVector) == "function") then return nil end
    local maps = Store()[source]
    local entry = maps and maps[mapID]
    if type(entry) ~= "table" or type(entry.d) ~= "string" then return nil end
    local id = source .. ":" .. mapID
    local cached = parsed[id]
    if cached and cached.data == entry.d then return cached.notes end
    local notes, kept = Parse(source, entry.d), {}
    for _, note in ipairs(notes) do
        local ok, worldX, worldY, instanceID = pcall(mapToWorld, note.mapID, mapVector(note.mapX, note.mapY))
        if ok and Number(worldX) and Number(worldY) then
            note.worldX, note.worldY, note.instanceID = worldX, worldY, instanceID
            kept[#kept + 1] = note
        end
    end
    if not cached then
        parsedOrder[#parsedOrder + 1] = id
        if #parsedOrder > MAX_PARSED then parsed[table.remove(parsedOrder, 1)] = nil end
    end
    parsed[id] = { data = entry.d, notes = kept }
    Trace("loaded %d saved notes from %s for map %d", #kept, source, mapID)
    return kept
end

function PackStore.Count(source, mapID)
    local maps = type(source) == "string" and Store()[source]
    local entry = maps and maps[mapID]
    return type(entry) == "table" and Number(entry.n) or 0
end

function PackStore.Maps(source)
    local maps = type(source) == "string" and Store()[source]
    return type(maps) == "table" and maps or {}
end

function PackStore.Sources()
    local list = {}
    for source, maps in pairs(Store()) do
        if type(source) == "string" and type(maps) == "table" and next(maps) then list[#list + 1] = source end
    end
    table.sort(list)
    return list
end

function PackStore.Generation() return generation end

function PackStore.Clear()
    Settings().vignetteRadarPackCache = {}
    harvested, parsed, parsedOrder = {}, {}, {}
    generation = generation + 1
    Trace("cleared the saved pack notes")
end

-- HandyNotes takeover --------------------------------------------------------
-- Verified in HandyNotes.lua: its own "Show the following plugins" option sets
-- db.profile.enabledPlugins[name] and calls HandyNotes:UpdatePluginMap(nil, name),
-- which clears and redraws that plugin's world map and minimap pins. VR does the
-- same, and remembers which packs it hid so turning the switch off gives them back.
-- RareScanner keeps its pin state in a file-local namespace, so VR cannot hide
-- its pins; that part is skipped.

local function HandyNotes()
    local notes = _G.HandyNotes
    local plugins = type(notes) == "table" and Field(notes, "plugins")
    local db = type(notes) == "table" and Field(notes, "db")
    local profile = db and Field(db, "profile")
    local enabled = profile and Field(profile, "enabledPlugins")
    if type(plugins) ~= "table" or type(enabled) ~= "table" then return nil end
    return notes, plugins, enabled
end

local function Hidden()
    local db = Settings()
    if type(db.vignetteRadarPackHidden) ~= "table" then db.vignetteRadarPackHidden = {} end
    return db.vignetteRadarPackHidden
end

function PackStore.HiddenByVR(source)
    return type(source) == "string" and Hidden()[source] == true
end

local function Redraw(notes, name)
    local update = Field(notes, "UpdatePluginMap")
    if type(update) == "function" then pcall(update, notes, nil, name) end
end

-- Hides every HandyNotes pack VR can read while the switch is on, and shows
-- back only the ones VR hid when it is off. Packs the user hid stay hidden.
function PackStore.ApplyTakeover()
    local notes, plugins, enabled = HandyNotes()
    local hidden = Hidden()
    local on = Settings().vignetteRadarPackTakeover == true
    if not notes then
        if not on then for name in pairs(hidden) do hidden[name] = nil end end
        return 0
    end
    local changed = 0
    if on then
        for name, handler in pairs(plugins) do
            if type(name) == "string" and type(handler) == "table"
                and type(handler.GetNodes2) == "function" and enabled[name] ~= false then
                enabled[name], hidden[name] = false, true
                Redraw(notes, name)
                changed = changed + 1
            end
        end
    else
        for name in pairs(hidden) do
            hidden[name] = nil
            if plugins[name] and enabled[name] == false then
                enabled[name] = true
                Redraw(notes, name)
                changed = changed + 1
            end
        end
    end
    if changed > 0 then
        local pois = addon.VignetteRadarPOIs
        if pois and pois.Invalidate then pois.Invalidate() end
        Trace("%s %d HandyNotes packs", on and "hid" or "restored", changed)
    end
    return changed
end

if addon.Bus then
    -- Packs register while they load; apply once the world is up.
    addon.Bus.On("PLAYER_ENTERING_WORLD", function()
        if Settings().vignetteRadarPackTakeover == true or next(Hidden()) then PackStore.ApplyTakeover() end
    end)
end

return PackStore
