local _, addon = ...
if type(addon) ~= "table" then return end

-- This module owns data only. The caller supplies validated player snapshots and
-- calls Flush at a quiet interval/logout; sampling never writes SavedVariables.
local API = {}
addon.VignetteRadarSurveyReplay = API

local MAX_CHARACTERS, MAX_ZONES, MAX_CELLS = 12, 24, 2048
local MAX_EVENTS, MAX_SAVES, MAX_SAVED_EVENTS = 256, 8, 128
local SAMPLE_SECONDS, REPLAY_SECONDS, REPLAY_SAMPLE_SECONDS = 3, 1800, 10
local CELL_SIZE = .025
local CELL_SIZES = { [.02]=true, [.025]=true, [.05]=true }
local store, coverage = nil, {}
-- character|mapID|size|cell -> entry, so a revisit needs no scan.
local coverageIndex = {}
local character = "player"
local surveying, recording = false, false
local lastSurveyAt, lastPosition, lastReplayAt, lastReplayPosition = nil, nil, nil, nil
local timeline = {}
local dirty = false

local Safe, Field = addon.Secret.Safe, addon.Secret.Field
local Number, Integer = addon.Secret.Number, addon.Secret.Integer

local function Label(value, maxLength)
    if not Safe(value) or type(value) ~= "string" or #value == 0 or #value > maxLength then return nil end
    return value
end

local function Point(value)
    local mapID = Integer(Field(value, "mapID"), 1, 1000000)
    local x, y = Number(Field(value, "mapX")), Number(Field(value, "mapY"))
    if not mapID or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local worldX, worldY = Number(Field(value, "worldX")), Number(Field(value, "worldY"))
    if (worldX == nil) ~= (worldY == nil) then worldX, worldY = nil, nil end
    local instanceID = Integer(Field(value, "instanceID"), 0, 1000000)
    return { mapID=mapID, mapX=x, mapY=y, worldX=worldX, worldY=worldY,
        instanceID=instanceID }
end

local function CopyPoint(point)
    if not point then return nil end
    return { mapID=point.mapID, mapX=point.mapX, mapY=point.mapY,
        worldX=point.worldX, worldY=point.worldY, instanceID=point.instanceID }
end

local function Distance(a, b)
    if not a or not b or a.mapID ~= b.mapID or a.instanceID ~= b.instanceID then return nil end
    if a.worldX and a.worldY and b.worldX and b.worldY then
        return math.sqrt((a.worldX-b.worldX)^2 + (a.worldY-b.worldY)^2)
    end
    return nil
end

local function Cell(point)
    local cols = math.ceil(1 / CELL_SIZE)
    local x = math.min(cols-1, math.floor(point.mapX / CELL_SIZE))
    local y = math.min(cols-1, math.floor(point.mapY / CELL_SIZE))
    return x .. ":" .. y
end

local function CoverageKey(entry)
    return entry.character .. "|" .. entry.mapID .. "|" .. entry.size .. "|" .. entry.cell
end

local function IndexCoverage()
    coverageIndex = {}
    for index = 1, #coverage do
        local entry = coverage[index]
        coverageIndex[CoverageKey(entry)] = entry
    end
end

-- Newest entries decide which zones and characters stay. A kept zone keeps
-- all of its cells, older ones too. Survivors are compacted in one pass.
local function TrimCoverage()
    local count = #coverage
    local first = math.max(1, count - MAX_CELLS + 1)
    local keepZone, keepWho = {}, {}
    local zones, characters = 0, 0
    for index = count, first, -1 do
        local entry = coverage[index]
        local who, mapID = entry.character, entry.mapID
        local whoZones = keepZone[who]
        if not whoZones then whoZones = {}; keepZone[who] = whoZones end
        local keep = whoZones[mapID]
        if keep == nil then
            zones = zones + 1
            keep = zones <= MAX_ZONES
            whoZones[mapID] = keep
        end
        -- The character cap counts only entries that survive the zone cap.
        if keep and keepWho[who] == nil then
            characters = characters + 1
            keepWho[who] = characters <= MAX_CHARACTERS
        end
    end
    local write = 0
    for index = 1, count do
        local entry = coverage[index]
        coverage[index] = nil
        local whoZones = index >= first and keepZone[entry.character]
        if whoZones and whoZones[entry.mapID] and keepWho[entry.character] then
            write = write + 1
            coverage[write] = entry
        else
            local key = CoverageKey(entry)
            if coverageIndex[key] == entry then coverageIndex[key] = nil end
        end
    end
end

local function AddCoverage(who, point, at)
    local key = Cell(point)
    local indexKey = who .. "|" .. point.mapID .. "|" .. CELL_SIZE .. "|" .. key
    local entry = coverageIndex[indexKey]
    if entry then
        -- Recency controls pruning; revisits do not grow storage.
        entry.at = at
        if coverage[#coverage] ~= entry then
            for index = #coverage - 1, 1, -1 do
                if coverage[index] == entry then
                    table.remove(coverage, index)
                    break
                end
            end
            coverage[#coverage+1] = entry
        end
        dirty = true
        return false
    end
    entry = { character=who, mapID=point.mapID, cell=key, size=CELL_SIZE, at=at }
    coverage[#coverage+1] = entry
    coverageIndex[indexKey] = entry
    TrimCoverage()
    dirty = true
    return true
end

local function CopyEvent(event)
    return { kind=event.kind, at=event.at, point=CopyPoint(event.point),
        identity=event.identity, source=event.source, evidence=event.evidence,
        name=event.name, count=event.count }
end

local function TrimTimeline(now)
    while #timeline > 0 and (timeline[1].at < now - REPLAY_SECONDS or #timeline > MAX_EVENTS) do
        table.remove(timeline, 1)
    end
end

local function AddEvent(event)
    local last = timeline[#timeline]
    if last and event.at < last.at then return false end
    if last and event.kind ~= "movement" and last.kind == event.kind
        and last.identity == event.identity and last.source == event.source
        and last.evidence == event.evidence and event.at - last.at <= 5 then
        last.at, last.count = event.at, (last.count or 1) + 1
        last.point = event.point or last.point
    else
        timeline[#timeline+1] = event
    end
    TrimTimeline(event.at)
    return true
end

function API.Initialize(saved, who)
    store = Safe(saved) and type(saved) == "table" and saved or nil
    character = Label(who, 80) or "player"
    coverage, timeline = {}, {}
    surveying, recording, dirty = false, false, false
    lastSurveyAt, lastPosition, lastReplayAt, lastReplayPosition = nil, nil, nil, nil
    local savedSize = store and Number(Field(store, "cellSize"))
    CELL_SIZE = savedSize and CELL_SIZES[savedSize] and savedSize or .025
    local old = store and Field(store, "coverage")
    if Safe(old) and type(old) == "table" then
        for index = 1, math.min(#old, MAX_CELLS) do
            local entry = old[index]
            local c = Label(Field(entry, "character"), 80)
            local m = Integer(Field(entry, "mapID"), 1, 1000000)
            local key = Label(Field(entry, "cell"), 8)
            local size = Number(Field(entry, "size"))
            size = size and CELL_SIZES[size] and size or .025
            local at = Integer(Field(entry, "at"), 1, 4102444800)
            local cx, cy
            if key then cx, cy = key:match("^(%d+):(%d+)$") end
            local limit = math.ceil(1 / size)
            if c and m and cx and cy and tonumber(cx) < limit and tonumber(cy) < limit and at then
                coverage[#coverage+1] = { character=c, mapID=m, cell=key, size=size, at=at }
            end
        end
    end
    IndexCoverage()
    TrimCoverage()
    -- Normalize old or imported snapshots once, before they can accumulate.
    if store and type(Field(store, "replays")) == "table" then
        store.replays = API.GetSavedReplays()
    end
    return true
end

function API.SetCellSize(size)
    size = Number(size)
    if not size or not CELL_SIZES[size] then return false end
    if CELL_SIZE ~= size then CELL_SIZE, dirty = size, true end
    return true
end

function API.GetCellSize() return CELL_SIZE end

function API.SetSurveying(enabled)
    surveying = enabled == true
    lastSurveyAt, lastPosition = nil, nil
    return surveying
end

function API.SetRecording(enabled)
    recording = enabled == true
    lastReplayAt, lastReplayPosition = nil, nil
    return recording
end

function API.Sample(player, elapsed, epoch)
    local point = Point(player)
    elapsed, epoch = Number(elapsed), Integer(epoch, 1, 4102444800)
    if not point or not elapsed or not epoch then return false end
    local changed = false
    if surveying and (not lastSurveyAt or elapsed - lastSurveyAt >= SAMPLE_SECONDS) then
        local gap = Distance(lastPosition, point)
        local jump = lastSurveyAt and (elapsed < lastSurveyAt or elapsed-lastSurveyAt > 30
            or (gap and gap > math.max(120, (elapsed-lastSurveyAt)*45)))
        if not jump then changed = AddCoverage(character, point, epoch) or changed end
        lastSurveyAt, lastPosition = elapsed, point
    end
    if recording and (not lastReplayAt or elapsed - lastReplayAt >= REPLAY_SAMPLE_SECONDS) then
        local gap = Distance(lastReplayPosition, point)
        local jump = lastReplayAt and (elapsed < lastReplayAt or elapsed-lastReplayAt > 30
            or (gap and gap > math.max(120, (elapsed-lastReplayAt)*45)))
        if not jump and (not gap or gap >= 15) then
            AddEvent({ kind="movement", at=epoch, point=point,
                source="player", evidence="observed" })
            changed = true
        end
        lastReplayAt, lastReplayPosition = elapsed, point
    end
    return changed
end

function API.RecordSignal(signal, epoch)
    if not recording then return false end
    epoch = Integer(epoch, 1, 4102444800)
    local kind = Label(Field(signal, "kind"), 32)
    local source = Label(Field(signal, "source"), 40)
    local evidence = Label(Field(signal, "evidence"), 40)
    local identity = Label(Field(signal, "identity"), 120)
    if not epoch or not kind or not source or not evidence or not identity then return false end
    if kind ~= "appeared" and kind ~= "vanished" and kind ~= "changed" then return false end
    local point = Point(Field(signal, "point"))
    if not point then return false end
    return AddEvent({ kind=kind, at=epoch, point=point, identity=identity,
        source=source, evidence=evidence, name=Label(Field(signal, "name"), 80) })
end

function API.GetCoverage(mapID, shared)
    mapID = Integer(mapID, 1, 1000000)
    local cells, count = {}, 0
    if not mapID then return cells, count, 0 end
    for _, entry in ipairs(coverage) do
        if entry.mapID == mapID and entry.size == CELL_SIZE
            and (shared == true or entry.character == character)
            and not cells[entry.cell] then
            cells[entry.cell] = true
            count = count + 1
        end
    end
    return cells, count, math.min(1, count / (math.ceil(1/CELL_SIZE)^2))
end

function API.GetTimeline(epoch)
    epoch = Integer(epoch, 1, 4102444800)
    if epoch then TrimTimeline(epoch) end
    local copy = {}
    for index, event in ipairs(timeline) do copy[index] = CopyEvent(event) end
    return copy
end

function API.SaveReplay(name, epoch)
    if not store then return false, "SavedVariables unavailable" end
    name, epoch = Label(name, 80), Integer(epoch, 1, 4102444800)
    if not name or not epoch or #timeline == 0 then return false, "Nothing to save" end
    local saves = API.GetSavedReplays()
    local events = {}
    for index = math.max(1, #timeline-MAX_SAVED_EVENTS+1), #timeline do
        events[#events+1] = CopyEvent(timeline[index])
    end
    saves[#saves+1] = { version=1, name=name, at=epoch, events=events }
    while #saves > MAX_SAVES do table.remove(saves, 1) end
    store.replays = saves
    return true, #saves
end

function API.GetSavedReplays()
    local result = {}
    local saves = store and Field(store, "replays")
    if type(saves) ~= "table" then return result end
    for index = math.max(1, #saves-MAX_SAVES+1), #saves do
        local item = saves[index]
        local events, raw = {}, Field(item, "events")
        if type(raw) == "table" then
            for n = 1, math.min(#raw, MAX_SAVED_EVENTS) do
                local event = raw[n]
                local point = Point(Field(event, "point"))
                local at = Integer(Field(event, "at"), 1, 4102444800)
                local kind = Label(Field(event, "kind"), 32)
                if point and at and kind then
                    events[#events+1] = { kind=kind, at=at, point=point,
                        source=Label(Field(event, "source"), 40),
                        evidence=Label(Field(event, "evidence"), 40),
                        identity=Label(Field(event, "identity"), 120),
                        name=Label(Field(event, "name"), 80),
                        count=Integer(Field(event, "count"), 1, 100000) }
                end
            end
        end
        local name = Label(Field(item, "name"), 80)
        local at = Integer(Field(item, "at"), 1, 4102444800)
        if name and at then result[#result+1] = { version=1, name=name, at=at, events=events } end
    end
    return result
end

function API.DeleteReplay(index)
    local saves = store and Field(store, "replays")
    index = Integer(index, 1, MAX_SAVES)
    if type(saves) ~= "table" or not index or not saves[index] then return false end
    table.remove(saves, index)
    return true
end

function API.Flush()
    if not store or not dirty then return false end
    local copy = {}
    for index, entry in ipairs(coverage) do
        copy[index] = { character=entry.character, mapID=entry.mapID,
            cell=entry.cell, size=entry.size, at=entry.at }
    end
    store.coverage = copy
    store.cellSize = CELL_SIZE
    store.version = 1
    dirty = false
    return true
end

function API.ClearSession()
    timeline = {}
    recording, lastReplayAt, lastReplayPosition = false, nil, nil
end

function API.ClearCoverage(mapID, shared)
    mapID = Integer(mapID, 1, 1000000)
    if not mapID then return false end
    local removed = false
    for index = #coverage, 1, -1 do
        local entry = coverage[index]
        if entry.mapID == mapID and (shared == true or entry.character == character) then
            table.remove(coverage, index)
            removed = true
        end
    end
    if removed then IndexCoverage() end
    dirty = dirty or removed
    return removed
end
