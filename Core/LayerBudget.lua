local _, addon = ...
if type(addon) ~= "table" then return end

-- Transient, per-layer CPU guard. Nothing here changes SavedVariables. A busy
-- layer is sampled less often, then is tried at its original rate again once
-- its measured work settles. All thresholds are milliseconds per second.
local API = {}
addon.VignetteRadarLayerBudget = API

local definitions = {
    render = { label = "radar drawing", high = 10, single = 65,
        intervals = { 0, .10, .20, .35 } },
    questBlobs = { label = "quest areas", high = 4, single = 45,
        intervals = { 0, .25, .50, 1.00 } },
    mapNotes = { label = "map notes", high = 4, single = 45,
        intervals = { 0, .25, .50, 1.00 } },
    trail = { label = "trail", high = 3, single = 45,
        intervals = { 0, .40, .80, 1.50 } },
    constellation = { label = "constellation", high = 12, single = 45,
        intervals = { 0, .05, .10, .20 } },
}

local states = {}
local active
local function Clock()
    if type(GetTime) ~= "function" then return 0 end
    local value = GetTime()
    return type(value) == "number" and value or 0
end
local function Profile()
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, value = pcall(debugprofilestop)
    if ok and type(value) == "number" and value == value then return value end
end
local function State(name)
    local config = definitions[name]
    if not config then return nil end
    local state = states[name]
    if not state then
        state = { name = name, config = config, level = 0, cost = 0,
            runs = 0, skips = 0, recent = 0, heavy = 0, quiet = 0 }
        states[name] = state
    end
    return state
end
local function Announce(state, restored)
    local chat = DEFAULT_CHAT_FRAME
    if not (chat and type(chat.AddMessage) == "function") then return end
    if restored then
        chat:AddMessage("Magpie restored normal " .. state.config.label .. " updates.")
    else
        chat:AddMessage("Magpie reduced " .. state.config.label
            .. " update frequency after high CPU use; it will restore automatically.")
    end
end
local function ChangeLevel(state, level)
    level = math.max(0, math.min(3, level))
    if level == state.level then return end
    local old = state.level
    state.level, state.heavy, state.quiet = level, 0, 0
    if old == 0 and level > 0 then Announce(state, false)
    elseif old > 0 and level == 0 then Announce(state, true) end
end
local function FinishWindow(state, now)
    local elapsed = now - state.windowAt
    if elapsed < 1 then return end
    state.recent = state.cost / elapsed
    if state.recent >= state.config.high then
        state.heavy, state.quiet = state.heavy + 1, 0
        if state.heavy >= 2 then ChangeLevel(state, state.level + 1) end
    elseif state.recent <= state.config.high * .45 then
        state.quiet, state.heavy = state.quiet + 1, 0
        if state.level > 0 and state.quiet >= 6 then ChangeLevel(state, state.level - 1) end
    else
        state.heavy, state.quiet = 0, 0
    end
    state.windowAt, state.cost = now, 0
end

function API.ShouldRun(name, force)
    local state = State(name)
    if not state then return true end
    local now = Clock()
    if state.windowAt then FinishWindow(state, now) else state.windowAt = now end
    local interval = state.config.intervals[state.level + 1]
    if not force and state.lastRun and now - state.lastRun < interval then
        state.skips = state.skips + 1
        return false
    end
    state.lastRun = now
    return true
end

-- Begin/Finish reuse one state per layer rather than allocating a token each
-- frame. Nesting subtracts child work from the parent, so "render" represents
-- only the remaining drawing cost instead of double-counting the other layers.
function API.Begin(name, force)
    local state = State(name)
    if not state then return nil end
    if state.running then
        -- An error between Begin and Finish skipped Finish. Drop the stale run
        -- (and any layers still nested inside it) so the layer is not dead
        -- until /reload.
        local stale = active
        while stale and stale ~= state do stale = stale.parent end
        if stale then
            local node = active
            while node and node ~= state do
                local parent = node.parent
                node.running, node.parent, node.started, node.child = false, nil, nil, 0
                node = parent
            end
            active = state.parent
        end
        state.running, state.parent, state.started, state.child = false, nil, nil, 0
    end
    if not API.ShouldRun(name, force) then return nil end
    state.started, state.child, state.parent = Profile(), 0, active
    state.running = true
    active = state
    return state
end

function API.Record(name, milliseconds, now)
    local state = State(name)
    if not state or type(milliseconds) ~= "number" or milliseconds < 0 then return end
    now = type(now) == "number" and now or Clock()
    if not state.windowAt or now < state.windowAt then
        state.windowAt, state.cost = now, 0
    else FinishWindow(state, now) end
    state.cost = state.cost + milliseconds
    state.runs = state.runs + 1
    if milliseconds >= state.config.single then ChangeLevel(state, state.level + 1) end
end

function API.Finish(token)
    if not token or not token.running then return end
    local finished = Profile()
    local duration = token.started and finished and finished >= token.started
        and finished - token.started or nil
    token.running = false
    active = token.parent
    if active and duration then active.child = active.child + duration end
    token.parent, token.started = nil, nil
    if duration then API.Record(token.name, math.max(0, duration - token.child)) end
    token.child = 0
end

function API.Status(name)
    local state = State(name)
    if not state then return nil end
    return { level = state.level, interval = state.config.intervals[state.level + 1],
        millisecondsPerSecond = state.recent, runs = state.runs, skips = state.skips }
end

function API.StatusLine()
    local parts = {}
    for _, name in ipairs({ "render", "questBlobs", "mapNotes", "trail", "constellation" }) do
        local state = State(name)
        parts[#parts + 1] = state.config.label .. " " .. tostring(math.floor(state.recent + .5)) .. "ms/s"
            .. (state.level > 0 and " (reduced)" or "")
    end
    return table.concat(parts, " · ")
end
