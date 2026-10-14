local _, addon = ...
if type(addon) ~= "table" then return end

-- One event frame for the whole addon. Modules subscribe to raw WoW events
-- or to named topics (one topic covers a family of events), so each module
-- owns its own cache invalidation instead of the radar fanning events out.
--   Bus.On(topic, handler [, { coalesce = true | seconds }])
--   Bus.Off(topic, handler)
--   Bus.Emit(topic, ...)
--   Bus.Every(name, seconds, fn [, { scale = false }]) / Bus.Cancel(name)
--   Bus.InCombat()
-- Handlers receive (event, ...): the raw WoW event that fired, or the topic
-- name for Bus.Emit. Handlers run in subscription order, which follows the
-- TOC, so data modules invalidate before the radar schedules its refresh.
local Bus = {}
addon.Bus = Bus

local type, pcall, ipairs, select = type, pcall, ipairs, select
local unpack = table.unpack or unpack

local TOPICS = {
    QUEST_CHANGED = { "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED",
        "QUEST_WATCH_UPDATE", "TASK_PROGRESS_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED",
        "QUEST_TURNED_IN" },
    MAP_CHANGED = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS" },
    LOOT = { "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" },
    COMBAT = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    VIGNETTES = { "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED" },
    TRACKING = { "MINIMAP_UPDATE_TRACKING" },
    SUPERTRACK = { "SUPER_TRACKING_CHANGED" },
    LOGIN = { "PLAYER_LOGIN" },
    LOGOUT = { "PLAYER_LOGOUT" },
}
Bus.TOPICS = TOPICS

-- name (raw event or topic) -> ordered list of subscriptions. Lists are
-- replaced, never edited in place, so a dispatch in progress is unaffected.
local lists, registered = {}, {}
local pendingFns, pendingArgs = {}, {}
-- name -> ticker, plus an ordered list that is replaced on every change.
local tickers, tickerList = {}, {}
local frame = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
local combat = false

local function Report(err)
    local handler = type(geterrorhandler) == "function" and geterrorhandler()
    if handler then handler(err) else error(err, 0) end
end

local function Run(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Report(err) end
end

local function Flush(fn)
    if not pendingFns[fn] then return end
    local args = pendingArgs[fn]
    pendingFns[fn], pendingArgs[fn] = nil, nil
    Run(fn, unpack(args, 1, args.n))
end

-- A coalesced handler runs once for a burst: on the next frame (true) or
-- after a fixed delay (seconds). Without C_Timer it runs at once.
local function Schedule(entry, ...)
    local fn = entry.fn
    pendingArgs[fn] = { n = select("#", ...), ... }
    if pendingFns[fn] then return end
    local after = C_Timer and C_Timer.After
    if type(after) ~= "function" then
        pendingFns[fn] = true
        Flush(fn)
        return
    end
    pendingFns[fn] = true
    after(entry.coalesce == true and 0 or entry.coalesce, function() Flush(fn) end)
end

local function Dispatch(name, ...)
    local list = lists[name]
    if not list then return end
    for _, entry in ipairs(list) do
        if not entry.dead then
            if entry.coalesce then Schedule(entry, name, ...) else Run(entry.fn, name, ...) end
        end
    end
end

local function Add(name, entry)
    local old, list = lists[name] or {}, {}
    for index, existing in ipairs(old) do list[index] = existing end
    list[#list + 1] = entry
    lists[name] = list
end

local function Remove(name, fn)
    local old = lists[name]
    if not old then return end
    local list = {}
    for _, entry in ipairs(old) do
        if entry.fn == fn then entry.dead = true else list[#list + 1] = entry end
    end
    lists[name] = #list > 0 and list or nil
end

-- Raw events stay registered once subscribed; filter toggles must not churn
-- event registration.
local function Register(event)
    if registered[event] or not frame then return end
    registered[event] = true
    pcall(frame.RegisterEvent, frame, event)
end

local function Names(topic)
    return TOPICS[topic] or { topic }
end

function Bus.On(topic, handler, options)
    if type(topic) ~= "string" or type(handler) ~= "function" then return end
    local coalesce = type(options) == "table" and options.coalesce or nil
    if coalesce ~= true and not (type(coalesce) == "number" and coalesce >= 0) then coalesce = nil end
    local entry = { fn = handler, coalesce = coalesce }
    -- The topic list serves Bus.Emit(topic); the event lists serve WoW.
    if TOPICS[topic] then Add(topic, entry) end
    for _, event in ipairs(Names(topic)) do
        Add(event, entry)
        if event:match("^[%u_]+$") then Register(event) end
    end
end

function Bus.Off(topic, handler)
    if type(topic) ~= "string" then return end
    if TOPICS[topic] then Remove(topic, handler) end
    for _, event in ipairs(Names(topic)) do Remove(event, handler) end
end

function Bus.Emit(topic, ...)
    if type(topic) == "string" then Dispatch(topic, ...) end
end

-- The combat flag follows PLAYER_REGEN_*; InCombatLockdown() lags behind
-- PLAYER_REGEN_DISABLED. It is seeded once for a reload inside combat.
function Bus.InCombat()
    return combat
end

do
    local lockdown = InCombatLockdown
    if type(lockdown) == "function" then
        local ok, value = pcall(lockdown)
        combat = ok and value == true
    end
end
Bus.On("PLAYER_REGEN_DISABLED", function() combat = true end)
Bus.On("PLAYER_REGEN_ENABLED", function() combat = false end)

-- Ticker intervals follow the Update Rate setting, with the same ratios as
-- the radar scan (standard 1x, balanced 1.5x, low and CPU throttle 2.5x).
function Bus.Scale()
    local budget = addon.VignetteRadarBudget
    if budget and budget.softThrottle then return 2.5 end
    local getter = addon.GetSettings
    local ok, settings = false, nil
    if type(getter) == "function" then ok, settings = pcall(getter) end
    local mode = ok and type(settings) == "table" and settings.vignetteRadarPerformance or nil
    return mode == "low" and 2.5 or mode == "balanced" and 1.5 or 1
end

local function OnUpdate(_, elapsed)
    for _, ticker in ipairs(tickerList) do
        ticker.elapsed = ticker.elapsed + (elapsed or 0)
        local interval = ticker.seconds * (ticker.scale and Bus.Scale() or 1)
        if ticker.elapsed >= interval then
            ticker.elapsed = 0
            if tickers[ticker.name] == ticker then Run(ticker.fn, ticker.name) end
        end
    end
end

local function Rebuild()
    local list = {}
    for _, ticker in pairs(tickers) do list[#list + 1] = ticker end
    table.sort(list, function(a, b) return a.name < b.name end)
    tickerList = list
    if frame then frame:SetScript("OnUpdate", #list > 0 and OnUpdate or nil) end
end

-- A named repeating callback; registering the same name replaces it.
function Bus.Every(name, seconds, fn, options)
    if type(name) ~= "string" or type(fn) ~= "function"
        or type(seconds) ~= "number" or seconds <= 0 then return false end
    tickers[name] = { name = name, seconds = seconds, fn = fn, elapsed = 0,
        scale = not (type(options) == "table" and options.scale == false) }
    Rebuild()
    return frame ~= nil
end

function Bus.Cancel(name)
    if not tickers[name] then return end
    tickers[name] = nil
    Rebuild()
end

function Bus.IsTicking(name)
    return tickers[name] ~= nil
end

if frame then
    frame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)
end

-- Test seam: drives the ticker loop without a real frame.
Bus._Tick = OnUpdate
