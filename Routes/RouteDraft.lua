local _, addon = ...
if type(addon) ~= "table" then return end

-- Builds a short preview from positions that the caller already collected. This module
-- deliberately neither scans the world nor changes the player's saved route.
local Draft = {}
addon.VignetteRadarRouteDraft = Draft

local MAX_CANDIDATES = 256
local DEFAULT_RANGE = 1200
local MIN_DISTANCE_SQUARED = 8 * 8
local ALLOWED_KINDS = { quest = true, treasure = true, pin = true }

local Safe, Field, Number = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Number

local function Identity(value)
    if not Safe(value) then return nil end
    if type(value) == "string" and value ~= "" then return value:sub(1, 100) end
    if Number(value) then return tostring(value) end
    return nil
end

local function Candidate(item, player, rangeSquared)
    if Field(item, "stale") == true or Field(item, "cleared") == true
        or Field(item, "hidden") == true then return nil end
    local points = addon.VignetteRadarPoints
    local kind = points.Kind(item)
    if not ALLOWED_KINDS[kind] then return nil end
    local mapID = Number(Field(item, "mapID"))
    local x, y = Number(Field(item, "worldX")), Number(Field(item, "worldY"))
    if mapID ~= player.mapID or not x or not y then return nil end
    local instanceID = Number(Field(item, "instanceID"))
    if player.instanceID and instanceID and player.instanceID ~= instanceID then return nil end
    local dx, dy = x - player.worldX, y - player.worldY
    local distanceSquared = dx * dx + dy * dy
    if distanceSquared < MIN_DISTANCE_SQUARED or distanceSquared > rangeSquared then return nil end

    local uniqueKey = points.Key(item)
    local name = Field(item, "name")
    if type(name) ~= "string" or name == "" then name = kind == "quest" and "Quest location"
        or kind == "treasure" and "Treasure" or "My pin" end
    local result = {
        kind = kind, name = name:sub(1, 80), mapID = mapID,
        worldX = x, worldY = y, instanceID = instanceID,
        mapX = Number(Field(item, "mapX")), mapY = Number(Field(item, "mapY")),
        identity = uniqueKey, playerDistanceSquared = distanceSquared,
    }
    if kind == "quest" then result.questID = Number(Field(item, "questID"))
    elseif kind == "pin" then result.id = Identity(Field(item, "id"))
    else result.key = Identity(Field(item, "key")) end
    return result
end

local function Prefer(candidate, prior)
    if not prior or candidate.playerDistanceSquared < prior.playerDistanceSquared then return true end
    if candidate.playerDistanceSquared > prior.playerDistanceSquared then return false end
    if candidate.worldX ~= prior.worldX then return candidate.worldX < prior.worldX end
    if candidate.worldY ~= prior.worldY then return candidate.worldY < prior.worldY end
    return candidate.name < prior.name
end

-- Build(player, candidates, options) -> previewStops, status.
-- A stop's stepDistance is straight-line yards from the player/previous stop,
-- never an estimate of walkable distance. Each call is bounded to 256 inputs.
function Draft.Build(player, candidates, options)
    local px, py = Number(Field(player, "worldX")), Number(Field(player, "worldY"))
    local mapID = Number(Field(player, "mapID"))
    if not px or not py or not mapID then
        return {}, { reason = "Position unavailable", inspected = 0, eligible = 0,
            distanceKind = "straight-line" }
    end
    if type(candidates) ~= "table" or not Safe(candidates) then candidates = {} end
    if type(options) ~= "table" or not Safe(options) then options = {} end
    local maxStops = Number(Field(options, "maxStops")) or 5
    maxStops = math.max(3, math.min(5, math.floor(maxStops)))
    local maxDistance = Number(Field(options, "maxDistance")) or DEFAULT_RANGE
    maxDistance = math.max(10, math.min(10000, maxDistance))
    local origin = { worldX = px, worldY = py, mapID = mapID,
        instanceID = Number(Field(player, "instanceID")) }

    local count = math.min(#candidates, MAX_CANDIDATES)
    local byID = {}
    for index = 1, count do
        local candidate = Candidate(candidates[index], origin, maxDistance * maxDistance)
        if candidate and Prefer(candidate, byID[candidate.identity]) then
            byID[candidate.identity] = candidate
        end
    end
    local pool = {}
    for _, candidate in pairs(byID) do pool[#pool + 1] = candidate end

    local stops, x, y = {}, px, py
    while #stops < maxStops and #pool > 0 do
        local bestIndex, bestDistanceSquared
        for index, candidate in ipairs(pool) do
            local dx, dy = candidate.worldX - x, candidate.worldY - y
            local distanceSquared = dx * dx + dy * dy
            local best = bestIndex and pool[bestIndex]
            if not best or distanceSquared < bestDistanceSquared
                or (distanceSquared == bestDistanceSquared and candidate.identity < best.identity) then
                bestIndex, bestDistanceSquared = index, distanceSquared
            end
        end
        local chosen = table.remove(pool, bestIndex)
        chosen.stepDistance = math.sqrt(bestDistanceSquared)
        chosen.playerDistance = math.sqrt(chosen.playerDistanceSquared)
        chosen.playerDistanceSquared = nil
        chosen.identity = nil
        stops[#stops + 1] = chosen
        x, y = chosen.worldX, chosen.worldY
    end
    return stops, { reason = #stops == 0 and "No nearby destinations" or nil,
        inspected = count, eligible = #pool + #stops, truncated = #candidates > MAX_CANDIDATES,
        distanceKind = "straight-line" }
end
