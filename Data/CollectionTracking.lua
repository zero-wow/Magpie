local _, addon = ...
if type(addon) ~= "table" then return end

-- Collection Tracking Bridge: what the player tracks in Blizzard's
-- collections UI (appearances, mounts, achievements, decor) becomes notes in
-- the radar scan, so the radar, Bearing Bar, Guide Panel, focus clicks and
-- the Closest Auto Route see them like any other point. Positions come from
-- C_ContentTracking.GetTrackablesOnMap for the player's map (what Blizzard's
-- own world map pins show). A tracked thing with no source on this map adds
-- its next waypoint here (GetNextWaypointForTrackable: a portal, a zone exit)
-- when Blizzard knows one. Lists are rebuilt on CONTENT_TRACKING_UPDATE,
-- TRACKING_TARGET_INFO_UPDATE, a map change, or after 30 s; never per frame.
--   Tracking.AppendTo(notes, mapID [, now]) -> count added
--   Tracking.Collect(mapID [, now]) -> notes        Tracking.Invalidate()
-- A note: { key = "track:<type>:<id>:<x>:<y>", contentTracking = true,
--   trackableType, trackableID, targetType, targetID, trackLabel, kind = "item",
--   name, note, mapID, mapX, mapY, worldX, worldY, instanceID, waypoint?,
--   source = "Tracked", evidence = "saved" }
local Tracking = {}
addon.VignetteRadarCollectionTracking = Tracking

local type, ipairs, floor, pcall = type, ipairs, math.floor, pcall
local Field, Number, Text, Call = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local MAX_AGE, MAX_NOTES, SUCCESS = 30, 32, 0
local TYPE_LABELS = { [0] = "Appearance", [1] = "Mount", [2] = "Achievement", [3] = "Decor" }
local cache = {} -- mapID -> { at, notes }
local dirty = true

local function Settings() return addon.GetSettings() end

local function Now()
    local ok, value = pcall(GetTime)
    return ok and Number(value) or 0
end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("tracking", fmt, ...) end
end

function Tracking.Invalidate() dirty = true end

-- Blizzard's list of collectable source types, else appearances and mounts.
local function Types()
    local types = Call(C_ContentTracking, "GetCollectableSourceTypes")
    if type(types) == "table" and #types > 0 then return types end
    local enum = Field(_G.Enum, "ContentTrackingType")
    local appearance, mount = Number(Field(enum, "Appearance")), Number(Field(enum, "Mount"))
    return appearance and mount and { appearance, mount } or {}
end

local function Note(mapID, info, waypoint)
    local x, y = Number(Field(info, "x")), Number(Field(info, "y"))
    local trackableType, trackableID = Number(Field(info, "trackableType")), Number(Field(info, "trackableID"))
    if not (x and y and trackableType and trackableID and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return nil
    end
    local points = addon.VignetteRadarPoints
    local worldX, worldY, instanceID
    if points then worldX, worldY, instanceID = points.MapToWorld(mapID, x, y) end
    if not (worldX and worldY) then return nil end
    local label = TYPE_LABELS[trackableType] or "Collection"
    local title = Text(Call(C_ContentTracking, "GetTitle", trackableType, trackableID), 120, true)
    local targetType, targetID = Number(Field(info, "targetType")), Number(Field(info, "targetID"))
    local text = Text(Field(info, "waypointText"), 200, true)
    if not text and targetType and targetID then
        text = Text(Call(C_ContentTracking, "GetObjectiveText", targetType, targetID, false), 200, true)
    end
    return {
        key = "track:" .. trackableType .. ":" .. trackableID .. ":" .. floor(x * 10000 + .5)
            .. ":" .. floor(y * 10000 + .5),
        contentTracking = true, trackableType = trackableType, trackableID = trackableID,
        targetType = targetType, targetID = targetID, trackLabel = label,
        kind = "item", name = title or ("Tracked " .. label), title = title,
        note = waypoint and text and ("Next Step: " .. text) or text, waypoint = waypoint or nil,
        mapID = mapID, mapX = x, mapY = y, worldX = worldX, worldY = worldY, instanceID = instanceID,
        source = "Tracked", evidence = "saved",
    }
end

local function Build(mapID)
    local notes = {}
    for _, trackableType in ipairs(Types()) do
        trackableType = Number(trackableType)
        local found = {}
        if trackableType then
            local _, infos = Call(C_ContentTracking, "GetTrackablesOnMap", trackableType, mapID)
            for _, info in ipairs(type(infos) == "table" and infos or {}) do
                if #notes >= MAX_NOTES then break end
                local note = Note(mapID, info, false)
                if note then
                    notes[#notes + 1] = note
                    found[note.trackableID] = true
                end
            end
            -- Tracked things whose source is elsewhere: the next waypoint here.
            local ids = Call(C_ContentTracking, "GetTrackedIDs", trackableType)
            for _, id in ipairs(type(ids) == "table" and ids or {}) do
                id = Number(id)
                if id and not found[id] and #notes < MAX_NOTES then
                    local result, info = Call(C_ContentTracking, "GetNextWaypointForTrackable",
                        trackableType, id, mapID)
                    if result == SUCCESS and type(info) == "table" then
                        local note = Note(mapID, info, true)
                        if note then
                            notes[#notes + 1] = note
                            found[id] = true
                        end
                    end
                end
            end
        end
    end
    Trace("map %d: %d tracked collection points", mapID, #notes)
    return notes
end

function Tracking.Collect(mapID, now)
    mapID = Number(mapID)
    if not mapID or Settings().vignetteRadarCollectionTracking ~= true then return {} end
    now = Number(now) or Now()
    local entry = cache[mapID]
    if dirty or not entry or now - entry.at >= MAX_AGE then
        if dirty then cache = {} end
        dirty = false
        entry = { at = now, notes = Build(mapID) }
        cache[mapID] = entry
    end
    return entry.notes
end

function Tracking.AppendTo(notes, mapID, now)
    if type(notes) ~= "table" then return 0 end
    local added = 0
    for _, note in ipairs(Tracking.Collect(mapID, now)) do
        notes[#notes + 1] = note
        added = added + 1
    end
    return added
end

-- Route stops: the Closest route takes tracked points while this is on.
function Tracking.Routable(note, settings)
    return type(note) == "table" and note.contentTracking == true
        and (settings or Settings()).vignetteRadarCollectionTrackingRoute == true
end

if addon.Bus then
    local function Changed(event)
        Trace("tracking changed (%s)", tostring(event))
        Tracking.Invalidate()
    end
    addon.Bus.On("CONTENT_TRACKING_UPDATE", Changed)
    addon.Bus.On("CONTENT_TRACKING_LIST_UPDATE", Changed)
    addon.Bus.On("TRACKING_TARGET_INFO_UPDATE", Changed, { coalesce = 1 })
    addon.Bus.On("MAP_CHANGED", Changed)
end

return Tracking
