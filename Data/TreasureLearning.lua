local _, addon = ...
if type(addon) ~= "table" then return end

-- Loot events can confirm a nearby chest, but the map API only gives us XY.
-- Keep player-at-loot observations separate from pack coordinates and never
-- invent a height or silently replace a pack's pin with the player's position.
local API = {}
addon.VignetteRadarTreasureLearning = API

local MAX_ENTRIES, MAX_SAMPLES, MAX_LOOT_SLOTS = 256, 3, 32
local targets, notes, player = {}, {}, nil
local session

local Number = addon.Secret.Number

local function Snapshot()
    local radar = addon.VignetteRadarAPI
    if radar and type(radar.GetPlayerSnapshot) == "function" then
        local ok, current = pcall(radar.GetPlayerSnapshot)
        if ok and type(current) == "table" then return current end
    end
    return player
end

local function Distance(a, b)
    if not (a and b and Number(a.worldX) and Number(a.worldY)
        and Number(b.worldX) and Number(b.worldY)) then return nil end
    if Number(a.instanceID) and Number(b.instanceID)
        and a.instanceID ~= b.instanceID then return nil end
    local dx, dy = a.worldX - b.worldX, a.worldY - b.worldY
    return math.sqrt(dx * dx + dy * dy)
end

local function LootObjects()
    if type(GetNumLootItems) ~= "function" or type(GetLootSourceInfo) ~= "function" then return nil end
    local ok, count = pcall(GetNumLootItems)
    if not ok or not Number(count) then return nil end
    local found, seen = {}, {}
    for slot = 1, math.min(count, MAX_LOOT_SLOTS) do
        local read, guid = pcall(GetLootSourceInfo, slot)
        if read and type(guid) == "string"
            and not (issecretvalue and issecretvalue(guid)) and not seen[guid] then
            local objectID = tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
            if objectID then
                seen[guid] = true
                found[#found + 1] = { guid = guid, objectID = objectID }
            end
        end
    end
    return found
end

local function Key(item, objectID)
    if type(item.key) == "string" and #item.key <= 160 and item.source then return item.key end
    local mapID = Number(item.mapID)
    local vignetteID = Number(item.vignetteID)
    if mapID and (Number(item.objectID) or objectID) then
        return "live:" .. mapID .. ":" .. (Number(item.objectID) or objectID)
            .. ":" .. (vignetteID or 0)
    end
end

local function Candidate(item, source, snapshot)
    if not (item and (item.kind == "treasure" or item.category == "treasure")
        and not item.stale and not item.sample) then return nil end
    local distance = Distance(item, snapshot)
    if not distance then return nil end
    local exactGUID = type(item.objectGUID) == "string" and item.objectGUID == source.guid
    local exactID = Number(item.objectID) and item.objectID == source.objectID
    if (type(item.objectGUID) == "string" and not exactGUID)
        or (Number(item.objectID) and not exactID) then return nil end
    local rank = exactGUID and 3 or exactID and 2 or 1
    local radius = rank == 3 and 80 or rank == 2 and 80 or 6
    if distance > radius or not Key(item, source.objectID) then return nil end
    return { item = item, source = source, rank = rank, distance = distance }
end

local function Match(snapshot)
    local objects = LootObjects()
    if not objects or #objects == 0 then return nil end
    local best, nearbyCount = nil, 0
    for _, source in ipairs(objects) do
        for _, pool in ipairs({ notes, targets }) do
            for _, item in ipairs(pool) do
                local candidate = Candidate(item, source, snapshot)
                if candidate then
                    if candidate.rank == 1 then nearbyCount = nearbyCount + 1 end
                    if not best or candidate.rank > best.rank
                        or candidate.rank == best.rank and candidate.distance < best.distance
                        or candidate.rank == best.rank and candidate.distance == best.distance
                            and item.source and not best.item.source then
                        best = candidate
                    end
                end
            end
        end
    end
    -- An unlabelled nearby container is not enough to distinguish two pins.
    if best and best.rank == 1 and nearbyCount ~= 1 then return nil end
    return best
end

local function Entries()
    local db = addon.GetSettings and addon.GetSettings()
    if type(db) ~= "table" then return nil end
    if type(db.vignetteRadarTreasureLoots) ~= "table" then
        db.vignetteRadarTreasureLoots = {}
    end
    return db.vignetteRadarTreasureLoots
end

local function Record(matched, snapshot)
    local item, source = matched.item, matched.source
    local key = Key(item, source.objectID)
    if not (key and Number(snapshot.worldX) and Number(snapshot.worldY)
        and Number(snapshot.mapID) and Number(snapshot.mapX) and Number(snapshot.mapY)
        and snapshot.mapX >= 0 and snapshot.mapX <= 1
        and snapshot.mapY >= 0 and snapshot.mapY <= 1) then return false end
    local entries = Entries()
    if not entries then return false end
    local now = type(time) == "function" and time() or 0
    local entry = entries[key]
    if type(entry) ~= "table" then
        local count, oldestKey, oldestAt = 0, nil, nil
        for existingKey, existing in pairs(entries) do
            count = count + 1
            local at = type(existing) == "table" and Number(existing.lastAt) or 0
            if not oldestAt or at < oldestAt then oldestKey, oldestAt = existingKey, at end
        end
        if count >= MAX_ENTRIES and oldestKey then entries[oldestKey] = nil end
        entry = { samples = {} }
        entries[key] = entry
    end
    entry.source = type(item.source) == "string" and item.source or "Blizzard"
    entry.name = type(item.name) == "string" and item.name:sub(1, 100) or "Treasure"
    entry.mapID, entry.mapX, entry.mapY = item.mapID, item.mapX, item.mapY
    entry.objectID = source.objectID
    entry.lastAt = now
    if type(entry.samples) ~= "table" then entry.samples = {} end
    local samples = entry.samples
    local outcomes = addon.VignetteRadarOutcomeLearning
    local z = outcomes and outcomes.PlayerHeight and outcomes.PlayerHeight(snapshot)
    samples[#samples + 1] = {
        -- This is where the player stood when a loot slot cleared, not the
        -- treasure's exact center. Height is retained only when UnitPosition
        -- agrees with the map API's horizontal coordinates.
        mapID = snapshot.mapID, mapX = snapshot.mapX, mapY = snapshot.mapY,
        worldX = snapshot.worldX, worldY = snapshot.worldY, z = z,
        match = matched.rank == 3 and "object-guid"
            or matched.rank == 2 and "object-id" or "nearby-gameobject",
        at = now,
    }
    while #samples > MAX_SAMPLES do table.remove(samples, 1) end
    return true
end

function API.Sync(_, snapshot, liveTargets, mapNotes)
    player = snapshot
    targets = type(liveTargets) == "table" and liveTargets or {}
    notes = type(mapNotes) == "table" and mapNotes or {}
end

function API.OnLootEvent(event)
    if event == "LOOT_CLOSED" then session = nil; return false end
    if event == "LOOT_OPENED" then
        session = nil
        local snapshot = Snapshot()
        if not snapshot then return false end
        local match = Match(snapshot)
        if match then
            session = { match = match,
                at = type(GetTime) == "function" and GetTime() or 0 }
        end
        return false
    end
    if event ~= "LOOT_SLOT_CLEARED" or not session then return false end
    local completed = session
    session = nil
    local now = type(GetTime) == "function" and GetTime() or 0
    local snapshot = Snapshot()
    if now < completed.at or now - completed.at > 5 or not snapshot then return false end
    local distance = Distance(completed.match.item, snapshot)
    if not distance or distance > (completed.match.rank > 1 and 80 or 6) then return false end
    return Record(completed.match, snapshot)
end
if addon.Bus then addon.Bus.On("LOOT", function(event) API.OnLootEvent(event) end) end

function API.Count()
    local entries = Entries()
    local count = 0
    for _ in pairs(entries or {}) do count = count + 1 end
    return count
end
