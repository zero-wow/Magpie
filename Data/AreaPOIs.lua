local _, addon = ...
if type(addon) ~= "table" then return end

-- Events, delves and races as points. Blizzard's area POIs for the player's
-- map become notes in the radar scan (kind "event" for events and races,
-- "entrance" for delves), so the radar, Bearing Bar, Zone Briefing, focus
-- clicks and the Closest Auto Route all see them. Timed POIs carry their
-- countdown in the name and drop out when it ends. Lists are rebuilt on
-- AREA_POIS_UPDATED, a map change or once a minute, never per frame.
--   AreaPOIs.AppendTo(notes, mapID [, now]) -> count added
--   AreaPOIs.Collect(mapID [, now]) -> notes      AreaPOIs.Invalidate()
-- A note: { key = "areapoi:<mapID>:<id>", areaPoiID, areaKind = event|delve|race,
--   kind, name, note, atlasName, mapID, mapX, mapY, worldX, worldY, instanceID,
--   endsAt (GetTime), evidence = "live" }
local AreaPOIs = {}
addon.VignetteRadarAreaPOIs = AreaPOIs

local type, ipairs, floor, format = type, ipairs, math.floor, string.format
local Field, Number, Text, Call = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local MAX_AGE, MAX_POIS = 60, 48
local SOURCES = {
    { kind = "event", call = "GetEventsForMap", noteKind = "event" },
    { kind = "race", call = "GetDragonridingRacesForMap", noteKind = "event" },
    { kind = "delve", call = "GetDelvesForMap", noteKind = "entrance" },
}
local cache = {} -- mapID -> { at, notes }
local dirty = true

local function Settings() return addon.GetSettings() end

local function Now()
    local ok, value = pcall(GetTime)
    return ok and Number(value) or 0
end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("areapoi", fmt, ...) end
end

function AreaPOIs.Invalidate() dirty = true end

local function XY(position)
    if type(position) ~= "table" then return nil end
    local getXY = Field(position, "GetXY")
    if type(getXY) == "function" then
        local ok, x, y = pcall(getXY, position)
        if ok then return Number(x), Number(y) end
        return nil
    end
    return Number(Field(position, "x")), Number(Field(position, "y"))
end

-- "12m", "1h 05m", "40s".
function AreaPOIs.Countdown(seconds)
    seconds = Number(seconds)
    if not seconds or seconds <= 0 then return nil end
    if seconds < 60 then return floor(seconds) .. "s" end
    local minutes = floor(seconds / 60)
    if minutes < 60 then return minutes .. "m" end
    return format("%dh %02dm", floor(minutes / 60), minutes % 60)
end

local function Build(mapID, now)
    local notes, seen = {}, {}
    local kinds = Settings().vignetteRadarAreaPOIKinds or {}
    local points = addon.VignetteRadarPoints
    for _, source in ipairs(SOURCES) do
        local ids = kinds[source.kind] ~= false and Call(C_AreaPoiInfo, source.call, mapID) or nil
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            id = Number(id)
            if id and not seen[id] and #notes < MAX_POIS then
                seen[id] = true
                local info = Call(C_AreaPoiInfo, "GetAreaPOIInfo", mapID, id)
                local x, y = XY(Field(info, "position"))
                local name = Text(Field(info, "name"), 120, true)
                if name and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    local worldX, worldY, instanceID
                    if points then worldX, worldY, instanceID = points.MapToWorld(mapID, x, y) end
                    if worldX and worldY then
                        local endsAt
                        if Call(C_AreaPoiInfo, "IsAreaPOITimed", id) == true then
                            local left = Number(Call(C_AreaPoiInfo, "GetAreaPOISecondsLeft", id))
                            endsAt = left and left > 0 and now + left or nil
                        end
                        notes[#notes + 1] = {
                            key = "areapoi:" .. mapID .. ":" .. id, areaPoiID = id,
                            areaKind = source.kind, kind = source.noteKind, title = name, name = name,
                            note = Text(Field(info, "description"), 200, true),
                            atlasName = Text(Field(info, "atlasName"), 120),
                            mapID = mapID, mapX = x, mapY = y,
                            worldX = worldX, worldY = worldY, instanceID = instanceID,
                            endsAt = endsAt, source = "Blizzard", evidence = "live",
                        }
                    end
                end
            end
        end
    end
    Trace("map %d: %d area POIs", mapID, #notes)
    return notes
end

-- The map's POIs, with countdown names refreshed and ended ones dropped.
function AreaPOIs.Collect(mapID, now)
    mapID = Number(mapID)
    if not mapID or Settings().vignetteRadarAreaPOIs ~= true then return {} end
    now = Number(now) or Now()
    local entry = cache[mapID]
    if dirty or not entry or now - entry.at >= MAX_AGE then
        if dirty then cache = {} end
        dirty = false
        entry = { at = now, notes = Build(mapID, now) }
        cache[mapID] = entry
    end
    local live = {}
    for _, note in ipairs(entry.notes) do
        if note.endsAt then
            local text = AreaPOIs.Countdown(note.endsAt - now)
            if text then
                note.name = note.title .. " (" .. text .. ")"
                live[#live + 1] = note
            end
        else
            live[#live + 1] = note
        end
    end
    return live
end

function AreaPOIs.AppendTo(notes, mapID, now)
    if type(notes) ~= "table" then return 0 end
    local added = 0
    for _, note in ipairs(AreaPOIs.Collect(mapID, now)) do
        notes[#notes + 1] = note
        added = added + 1
    end
    return added
end

if addon.Bus then
    addon.Bus.On("AREA_POIS_UPDATED", AreaPOIs.Invalidate)
    addon.Bus.On("MAP_CHANGED", AreaPOIs.Invalidate)
end

return AreaPOIs
