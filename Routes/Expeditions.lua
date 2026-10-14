local _, addon = ...
if type(addon) ~= "table" then return end

-- A data-only trip planner. The caller owns persistence and passes confirmed
-- completion events; proximity and a disappearing marker never complete a goal.
local Expeditions = {}
addon.VignetteRadarExpeditions = Expeditions

local MAX_GOALS, MAX_DEPS, MAX_TEXT = 64, 16, 100
local KINDS = { quest = true, rare = true, treasure = true, pin = true }
local TERMINAL = { complete = true, skipped = true }

local Safe, Field, Number = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Number

local function ID(value)
    return type(value) == "string" and Safe(value) and #value > 0
        and #value <= MAX_TEXT and value or nil
end

local function Position(goal)
    local mapID, x, y = Number(Field(goal, "mapID")),
        Number(Field(goal, "mapX")), Number(Field(goal, "mapY"))
    if not (mapID and mapID > 0 and mapID == math.floor(mapID)
        and x and x >= 0 and x <= 1 and y and y >= 0 and y <= 1) then return nil end
    return mapID, x, y
end

local function Index(trip, id)
    if not trip or type(trip.goals) ~= "table" then return nil end
    for index = 1, math.min(#trip.goals, MAX_GOALS) do
        if trip.goals[index].id == id then return index end
    end
end

-- New returns a detached, strictly bounded schema suitable for SavedVariables.
-- A missing position is allowed as an explicit unknown goal, never as a stop.
function Expeditions.New(goals, options)
    if type(goals) ~= "table" or not Safe(goals) or #goals < 1
        or #goals > MAX_GOALS then return nil, "Goal count must be 1-64" end
    options = type(options) == "table" and Safe(options) and options or {}
    local trip = { version = 1, goals = {}, currentID = nil, lockedID = nil,
        paused = false, priority = {} }
    local seen = {}
    for index = 1, #goals do
        local source = goals[index]
        local id, kind = ID(Field(source, "id")), Field(source, "kind")
        if not id or seen[id] or not KINDS[kind] then
            return nil, "Invalid or duplicate goal at " .. index
        end
        seen[id] = true
        local name = Field(source, "name")
        if type(name) ~= "string" or not Safe(name) or name == "" then name = id end
        local goal = { id = id, kind = kind, name = name:sub(1, MAX_TEXT),
            state = "available", dependsOn = {} }
        local deps = Field(source, "dependsOn")
        if deps ~= nil then
            if type(deps) ~= "table" or not Safe(deps) or #deps > MAX_DEPS then
                return nil, "Invalid dependencies for " .. id
            end
            local unique = {}
            for depIndex = 1, #deps do
                local dep = ID(deps[depIndex])
                if not dep or dep == id or unique[dep] then
                    return nil, "Invalid dependency for " .. id
                end
                unique[dep] = true
                goal.dependsOn[#goal.dependsOn + 1] = dep
            end
        end
        local mapID, mapX, mapY = Position(source)
        if mapID then
            goal.mapID, goal.mapX, goal.mapY = mapID, mapX, mapY
        elseif Field(source, "mapID") ~= nil or Field(source, "mapX") ~= nil
            or Field(source, "mapY") ~= nil then
            return nil, "Invalid position for " .. id
        end
        local worldX, worldY = Number(Field(source, "worldX")),
            Number(Field(source, "worldY"))
        if (worldX == nil) ~= (worldY == nil) then
            return nil, "Invalid world position for " .. id
        end
        if worldX and mapID then goal.worldX, goal.worldY = worldX, worldY end
        local instanceID = Number(Field(source, "instanceID"))
        if instanceID then goal.instanceID = instanceID end
        local ref = Field(source, "sourceID")
        if ID(ref) then goal.sourceID = ref end
        trip.goals[index] = goal
    end
    for _, goal in ipairs(trip.goals) do
        for _, dep in ipairs(goal.dependsOn) do
            if not seen[dep] then return nil, "Unknown dependency " .. dep end
        end
    end
    local visiting, visited = {}, {}
    local function Cycle(goal)
        if visiting[goal.id] then return true end
        if visited[goal.id] then return false end
        visiting[goal.id] = true
        for _, dep in ipairs(goal.dependsOn) do
            if Cycle(trip.goals[Index(trip, dep)]) then return true end
        end
        visiting[goal.id], visited[goal.id] = nil, true
        return false
    end
    for _, goal in ipairs(trip.goals) do
        if Cycle(goal) then return nil, "Dependency cycle" end
    end
    local priority = Field(options, "priority")
    if type(priority) == "table" and Safe(priority) then
        for kind in pairs(KINDS) do
            local value = Number(Field(priority, kind))
            if value then trip.priority[kind] = math.max(0, math.min(100, value)) end
        end
    end
    return trip
end

local function Status(trip, goal)
    if TERMINAL[goal.state] then return goal.state end
    for _, dep in ipairs(goal.dependsOn) do
        local prerequisite = trip.goals[Index(trip, dep)]
        if prerequisite.state ~= "complete" then return "blocked", "Requires " .. prerequisite.name end
    end
    if not Position(goal) then return "unknown", "Location unknown" end
    if trip.currentID == goal.id then return "active", "Current stop" end
    return "available"
end

function Expeditions.Status(trip, id)
    local index = Index(trip, id)
    if not index then return nil, "Unknown goal" end
    return Status(trip, trip.goals[index])
end

local function Distance(goal, player)
    local mapID = Number(Field(player, "mapID"))
    if not mapID or mapID ~= goal.mapID then return nil end
    local instanceID = Number(Field(player, "instanceID"))
    if instanceID and goal.instanceID and instanceID ~= goal.instanceID then return nil end
    local x, y = Number(Field(player, "worldX")), Number(Field(player, "worldY"))
    if x and y and goal.worldX and goal.worldY then
        local dx, dy = goal.worldX - x, goal.worldY - y
        return math.sqrt(dx * dx + dy * dy), "straight-line yards"
    end
    local mapX, mapY = Number(Field(player, "mapX")), Number(Field(player, "mapY"))
    if mapX and mapY and mapX >= 0 and mapX <= 1 and mapY >= 0 and mapY <= 1 then
        local dx, dy = goal.mapX - mapX, goal.mapY - mapY
        return math.sqrt(dx * dx + dy * dy), "map fraction"
    end
end

local function Candidate(trip, player, goal)
    local status = Status(trip, goal)
    if status ~= "available" and status ~= "active" then return nil end
    local distance, unit = Distance(goal, player)
    -- Current stop can remain active across map changes; a new choice cannot
    -- claim an unknown/cross-map distance is nearby.
    if not distance then return nil end
    return { id = goal.id, kind = goal.kind, name = goal.name,
        mapID = goal.mapID, mapX = goal.mapX, mapY = goal.mapY,
        worldX = goal.worldX, worldY = goal.worldY,
        instanceID = goal.instanceID, distance = distance, distanceKind = unit }
end

local function Better(a, b, trip)
    if not b then return true end
    local pa, pb = trip.priority[a.kind] or 50, trip.priority[b.kind] or 50
    if pa ~= pb then return pa > pb end
    if a.distanceKind == b.distanceKind and a.distance ~= b.distance then
        return a.distance < b.distance
    end
    return Index(trip, a.id) < Index(trip, b.id)
end

-- Plan changes only currentID and produces detached Now/Next records. Call it
-- on relevant events (or an explicit user action), never on every frame.
function Expeditions.Plan(trip, player)
    if type(trip) ~= "table" or type(trip.goals) ~= "table" then
        return nil, nil, "No trip" end
    if trip.paused then return nil, nil, "Trip paused" end
    local currentIndex = trip.currentID and Index(trip, trip.currentID)
    local current = currentIndex and trip.goals[currentIndex]
    if current and not TERMINAL[current.state] then
        local status, reason = Status(trip, current)
        if status == "active" then
            local now = Candidate(trip, player, current)
            if not now then
                now = { id = current.id, kind = current.kind, name = current.name,
                    mapID = current.mapID, mapX = current.mapX, mapY = current.mapY }
                reason = "Current stop; distance unavailable"
            end
            now.reason = reason or "Current stop; waiting for confirmed completion or Skip"
            local nextStop
            for _, goal in ipairs(trip.goals) do
                if goal.id ~= current.id then
                    local candidate = Candidate(trip, player, goal)
                    if candidate and Better(candidate, nextStop, trip) then nextStop = candidate end
                end
            end
            if nextStop then nextStop.reason = "Next available goal" end
            return now, nextStop
        end
    end
    trip.currentID = nil
    local best, runnerUp
    local lockedIndex = trip.lockedID and Index(trip, trip.lockedID)
    local locked = lockedIndex and trip.goals[lockedIndex]
    if locked then best = Candidate(trip, player, locked) end
    local lockedCandidate = best ~= nil
    for _, goal in ipairs(trip.goals) do
        if not best or goal.id ~= best.id then
            local candidate = Candidate(trip, player, goal)
            if candidate then
                if not best or not lockedCandidate and Better(candidate, best, trip) then
                    runnerUp, best = best, candidate
                elseif Better(candidate, runnerUp, trip) then runnerUp = candidate end
            end
        end
    end
    if not best then return nil, nil, "No mapped, available goals on this map" end
    trip.currentID = best.id
    best.reason = lockedCandidate and "Locked stop"
        or "Highest priority available goal; nearest within its type priority"
    if runnerUp then runnerUp.reason = "Next available goal" end
    return best, runnerUp
end

function Expeditions.Complete(trip, id)
    local index = Index(trip, id)
    if not index then return false, "Unknown goal" end
    trip.goals[index].state = "complete"
    if trip.currentID == id then trip.currentID = nil end
    if trip.lockedID == id then trip.lockedID = nil end
    return true
end

function Expeditions.Skip(trip, id)
    id = id or trip and trip.currentID
    local index = Index(trip, id)
    if not index then return false, "Unknown goal" end
    trip.goals[index].state = "skipped"
    if trip.currentID == id then trip.currentID = nil end
    if trip.lockedID == id then trip.lockedID = nil end
    return true
end

function Expeditions.Pause(trip, paused)
    if type(trip) ~= "table" then return false end
    trip.paused = paused ~= false
    return true
end

function Expeditions.Lock(trip, id)
    if id == nil then trip.lockedID = nil; return true end
    local index = Index(trip, id)
    if not index or TERMINAL[trip.goals[index].state] then return false, "Unknown or finished goal" end
    trip.lockedID = id
    -- A manual lock is an explicit choice to switch stops.
    trip.currentID = nil
    return true
end

function Expeditions.Reorder(trip, id, newIndex)
    local oldIndex = Index(trip, id)
    if not oldIndex or not Number(newIndex) or newIndex ~= math.floor(newIndex)
        or newIndex < 1 or newIndex > #trip.goals then return false, "Invalid order" end
    table.insert(trip.goals, newIndex, table.remove(trip.goals, oldIndex))
    return true
end

function Expeditions.SetPriority(trip, kind, priority)
    if type(trip) ~= "table" or not KINDS[kind] or not Number(priority)
        or priority < 0 or priority > 100 then return false, "Invalid priority" end
    trip.priority = type(trip.priority) == "table" and trip.priority or {}
    trip.priority[kind] = priority
    return true
end

return Expeditions
