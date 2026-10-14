local _, addon = ...
if type(addon) ~= "table" then return end

-- Today: the rares and treasures in this zone, done or still left this
-- reset, and the time to the daily and weekly reset. Read only: it takes the
-- scan's notes before Declutter (addon._rawMapNotes, so done ones are still
-- there) plus the live vignettes from the point registry. The Intelligence
-- panel's Today tab draws it; a click routes through Focus.
--   Today.Build([settings]) -> { mapID, zone, daily, weekly, rows, counts }
--     row = { key, name, kind = "rare" | "treasure", state = "live" | "left" | "done",
--             yards, item, live }
--   Today.Route(row) -> ok, reason
--   Today.Duration(seconds) -> "4 Hr 12 Min"
local Today = {}
addon.VignetteRadarToday = Today

local type, ipairs, floor = type, ipairs, math.floor
local Field, Number, Text, Call = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local KINDS = { rare = "rare", mob = "rare", treasure = "treasure" }
local TITLES = { rare = "Rare", treasure = "Treasure" }
local STATE_RANK = { live = 1, left = 2, done = 3 }
local DUPLICATE_YARDS, DAY = 60, 86400

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("today", fmt, ...) end
end

function Today.Duration(seconds)
    seconds = Number(seconds)
    if not seconds or seconds < 0 then return "Unknown" end
    local days, hours = floor(seconds / DAY), floor(seconds % DAY / 3600)
    local minutes = floor(seconds % 3600 / 60)
    if days > 0 then return days .. (days == 1 and " Day " or " Days ") .. hours .. " Hr" end
    if hours > 0 then return hours .. " Hr " .. minutes .. " Min" end
    return math.max(1, minutes) .. " Min"
end

local function SinceDailyReset(untilReset)
    if not untilReset or untilReset < 0 or untilReset > DAY then return DAY end
    return math.max(3600, DAY - untilReset)
end

local function Name(item, kind)
    local name = Text(Field(item, "name"), 80, true)
    local points = addon.VignetteRadarPoints
    if name and not (points and points.IsPlaceholderName(name)) then return name end
    local x, y = Number(Field(item, "mapX")), Number(Field(item, "mapY"))
    return TITLES[kind] .. (x and y and string.format(" (%.1f, %.1f)", x * 100, y * 100) or "")
end

local function Done(item, recent, window, settings)
    local declutter = addon.VignetteRadarDeclutter
    if declutter and (declutter.Done(Field(item, "questID")) or declutter.Done(Field(item, "rewardQuestID"))) then
        return true
    end
    return recent and type(recent.KilledWithin) == "function" and recent.KilledWithin(item, window, nil, settings)
        or false
end

function Today.Build(settings)
    settings = settings or addon.GetSettings()
    local points = addon.VignetteRadarPoints
    local view = points and points.View() or {}
    local mapID = Number(view.mapID)
    local player = type(view.player) == "table" and view.player or nil
    local daily = Number(Call(C_DateAndTime, "GetSecondsUntilDailyReset"))
    local weekly = Number(Call(C_DateAndTime, "GetSecondsUntilWeeklyReset"))
    local info = mapID and Call(C_Map, "GetMapInfo", mapID)
    local result = { mapID = mapID, zone = Text(Field(info, "name"), 60, true), daily = daily, weekly = weekly,
        rows = {}, counts = { rareLeft = 0, rareDone = 0, treasureLeft = 0, treasureDone = 0, live = 0 } }
    if not (points and mapID) then return result end
    local recent, window = addon.VignetteRadarRecent, SinceDailyReset(daily)
    local rows, live = result.rows, {}
    local function Add(item, kind, state, isLive)
        rows[#rows + 1] = { key = Text(Field(item, "key")) or tostring(item), name = Name(item, kind),
            kind = kind, state = state, live = isLive, item = item,
            yards = player and points.Distance(player, item) or nil }
        local counts = result.counts
        if state == "live" then counts.live = counts.live + 1 end
        if state == "done" then counts[kind .. "Done"] = counts[kind .. "Done"] + 1
        else counts[kind .. "Left"] = counts[kind .. "Left"] + 1 end
    end
    for _, target in ipairs(points.Refs("live")) do
        local kind = type(target) == "table" and KINDS[Text(Field(target, "category")) or ""]
        if kind and target.stale ~= true and target.sample ~= true and Number(Field(target, "mapID")) == mapID then
            live[#live + 1] = target
            Add(target, kind, Done(target, nil, window, settings) and "done" or "live", true)
        end
    end
    for _, note in ipairs(type(addon._rawMapNotes) == "table" and addon._rawMapNotes or {}) do
        local kind = type(note) == "table" and KINDS[Text(Field(note, "kind")) or ""]
        if kind and not note.areaPoiID then
            local covered = false
            for _, target in ipairs(live) do
                if points.Near(note, target, DUPLICATE_YARDS, mapID) then covered = true; break end
            end
            if not covered then Add(note, kind, Done(note, recent, window, settings) and "done" or "left", false) end
        end
    end
    table.sort(rows, function(a, b)
        local ra, rb = STATE_RANK[a.state], STATE_RANK[b.state]
        if ra ~= rb then return ra < rb end
        if (a.yards ~= nil) ~= (b.yards ~= nil) then return a.yards ~= nil end
        if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
        return a.name < b.name
    end)
    local counts = result.counts
    Log("map %s: rares %d left %d done, treasures %d left %d done, %d up", mapID, counts.rareLeft,
        counts.rareDone, counts.treasureLeft, counts.treasureDone, counts.live)
    return result
end

-- Routes to a row through the one selection (World Focus projects it).
function Today.Route(row)
    local focus = addon.VignetteRadarFocus
    if not (focus and type(row) == "table" and type(row.item) == "table") then return false, "No point" end
    local entry = row.live and focus.Target(row.item) or focus.Note(row.item)
    local ok, reason = focus.Select(entry, { source = "today", direct = true })
    Log("route %s (%s) ok=%s %s", row.name, row.state, ok, type(reason) == "string" and reason or "")
    return ok, reason
end

return Today
