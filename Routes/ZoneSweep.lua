local _, addon = ...
if type(addon) ~= "table" then return end

-- Zone Sweep: one click plans a loop over every rare and treasure still
-- worth visiting in this zone (live vignettes, learned spawns, pack notes,
-- group sightings) and hands the order to World Focus as an Auto Route.
-- Input is the point registry after Declutter, so done, killed-this-reset
-- and duplicate notes are already gone. The order is nearest-first from the
-- player, then 2-opt untangled, so the path never crosses itself needlessly.
--   ZoneSweep.Candidates([settings]) -> items     (route items, unordered)
--   ZoneSweep.Order(items, start) -> items, yards (start = { worldX, worldY })
--   ZoneSweep.Plan([settings]) -> items, yards
--   ZoneSweep.Start() -> ok, reason               (WorldFocus.StartSweep)
local ZoneSweep = {}
addon.VignetteRadarZoneSweep = ZoneSweep

local type, ipairs, sqrt = type, ipairs, math.sqrt
local Field, Number, Text = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text

local DUPLICATE_YARDS, MAX_PASSES = 60, 8
local KINDS = { rare = "rare", mob = "rare", treasure = "treasure" }

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("sweep", fmt, ...) end
end

local function Points() return addon.VignetteRadarPoints end

local function Wanted(kind, settings)
    local choice = settings.vignetteRadarZoneSweepKinds
    return kind ~= nil and (choice == "rare" and kind == "rare" or choice == "treasure" and kind == "treasure"
        or choice ~= "rare" and choice ~= "treasure")
end

-- A live vignette as the same route item World Focus builds for Closest.
local function LiveItem(target)
    return { key = target.key, kind = target.category, name = target.name, live = true,
        source = target.source, isWorldBoss = target.isWorldBoss, atlasName = target.atlasName,
        mapID = target.mapID, mapX = target.mapX, mapY = target.mapY,
        worldX = target.worldX, worldY = target.worldY, instanceID = target.instanceID,
        rewardQuestID = target.rewardQuestID, npcID = target.npcID, objectGUID = target.objectGUID,
        objectID = target.objectID }
end

local function Placed(item, mapID, instanceID)
    return Number(item.worldX) and Number(item.worldY)
        and (not mapID or Number(item.mapID) == mapID)
        and not (instanceID and Number(item.instanceID) and item.instanceID ~= instanceID)
end

local function Skip(item)
    local recent, declutter = addon.VignetteRadarRecent, addon.VignetteRadarDeclutter
    if recent and type(recent.IsHidden) == "function" and recent.IsHidden(item) then return "cleared" end
    if declutter and type(declutter.Done) == "function"
        and (declutter.Done(item.rewardQuestID) or declutter.Done(item.questID)) then return "done" end
    return nil
end

function ZoneSweep.Candidates(settings)
    settings = settings or addon.GetSettings()
    local points = Points()
    if not points then return {} end
    local view = points.View()
    local mapID = Number(view.mapID)
    local player = type(view.player) == "table" and view.player or nil
    local instanceID = player and Number(player.instanceID)
    local items, live, skipped = {}, {}, 0
    for _, target in ipairs(points.Refs("live")) do
        local kind = type(target) == "table" and KINDS[Text(Field(target, "category")) or ""]
        if kind and Wanted(kind, settings) and target.stale ~= true and target.sample ~= true
            and Placed(target, mapID, instanceID) then
            local item = LiveItem(target)
            if Skip(item) then skipped = skipped + 1
            else items[#items + 1] = item; live[#live + 1] = item end
        end
    end
    for _, note in ipairs(points.Refs("saved")) do
        local kind = type(note) == "table" and KINDS[Text(Field(note, "kind")) or ""]
        if kind and Wanted(kind, settings) and not note.areaPoiID and Placed(note, mapID, instanceID) then
            local duplicate = false
            for _, item in ipairs(live) do
                if points.Near(note, item, DUPLICATE_YARDS, mapID) then duplicate = true; break end
            end
            if duplicate or Skip(note) then skipped = skipped + 1
            else items[#items + 1] = note end
        end
    end
    Log("candidates map=%s live=%d total=%d skipped=%d", mapID, #live, #items, skipped)
    return items
end

local function Gap(a, b)
    local dx, dy = a.worldX - b.worldX, a.worldY - b.worldY
    return sqrt(dx * dx + dy * dy)
end

local function Length(start, list)
    local total, previous = 0, start
    for _, item in ipairs(list) do total = total + Gap(previous, item); previous = item end
    return total
end

-- Nearest-first from start, then 2-opt: reverse any stretch whose ends
-- swap to a shorter path. The start stays fixed; the path is open.
function ZoneSweep.Order(items, start)
    if type(items) ~= "table" or #items == 0 then return {}, 0 end
    if not (type(start) == "table" and Number(start.worldX) and Number(start.worldY)) then start = items[1] end
    local left, order, at = {}, {}, start
    for index, item in ipairs(items) do left[index] = item end
    while #left > 0 do
        local best, bestGap = 1, Gap(at, left[1])
        for index = 2, #left do
            local gap = Gap(at, left[index])
            if gap < bestGap then best, bestGap = index, gap end
        end
        at = table.remove(left, best)
        order[#order + 1] = at
    end
    local count = #order
    for _ = 1, MAX_PASSES do
        local improved = false
        for i = 1, count - 1 do
            local before = i == 1 and start or order[i - 1]
            for j = i + 1, count do
                local after = order[j + 1]
                local old = Gap(before, order[i]) + (after and Gap(order[j], after) or 0)
                local new = Gap(before, order[j]) + (after and Gap(order[i], after) or 0)
                if new + .01 < old then
                    local a, b = i, j
                    while a < b do order[a], order[b] = order[b], order[a]; a, b = a + 1, b - 1 end
                    improved = true
                end
            end
        end
        if not improved then break end
    end
    return order, Length(start, order)
end

function ZoneSweep.Plan(settings)
    settings = settings or addon.GetSettings()
    local items = ZoneSweep.Candidates(settings)
    local points = Points()
    local view = points and points.View() or {}
    local player = type(view.player) == "table" and view.player or nil
    local limit = Number(settings.vignetteRadarZoneSweepMax) or 40
    -- Over the cap, the nearest stops win.
    if #items > limit and player and Number(player.worldX) and Number(player.worldY) then
        table.sort(items, function(a, b) return Gap(player, a) < Gap(player, b) end)
        for index = #items, limit + 1, -1 do items[index] = nil end
    end
    local order, yards = ZoneSweep.Order(items, player)
    Log("plan %d stops, %d yd", #order, yards)
    return order, yards
end

function ZoneSweep.Start()
    local world = addon.VignetteRadarWorldFocus
    if not (world and type(world.StartSweep) == "function") then return false, "World Focus is unavailable" end
    local plan, yards = ZoneSweep.Plan()
    if #plan == 0 then
        Log("start: nothing left to sweep")
        return false, "No Rare or Treasure Left to Sweep"
    end
    local ok, reason = world.StartSweep(plan)
    Log("start %d stops %d yd ok=%s %s", #plan, yards, ok, type(reason) == "string" and reason or "")
    if not ok and type(reason) == "string" and addon.ShowVignetteRadarRouteNote then
        addon.ShowVignetteRadarRouteNote("AUTO ROUTE", reason)
    end
    return ok, reason
end

return ZoneSweep
