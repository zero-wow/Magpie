local _, addon = ...
if type(addon) ~= "table" then return end

-- One owned Blizzard waypoint at a time. Route choices are made only on
-- selection, arrival, or quest progress; there is no per-frame route scan.
local API = {}
addon.VignetteRadarWorldFocus = API
local targets, quests, notes, player = {}, {}, {}, nil
local active, candidates = nil, {}
local route, pausedRoute, lastSelected = nil, nil, nil
local horizonCache, horizonCachedAt
local lootSession
local nextRestoreAttempt = 0
local ROUTE_LIMIT, ROUTE_DUPLICATE_YARDS = 192, 60
local QuestComplete

-- /vrtrace (Core/Trace.lua): every route decision is logged under "route".
-- Trace is a no-op while the trace is off; detail that costs work is built
-- only behind TraceOn(). Horizon previews run NextRouteStop on a copy of the
-- route, so they are kept out of the trace.
local TraceLib = addon.Trace
local previewing = false
local function TraceOn()
    return TraceLib ~= nil and not previewing and TraceLib.IsOn()
end
local function Trace(fmt, ...)
    if TraceLib and not previewing then TraceLib.Log("route", fmt, ...) end
end
-- The calling file:line, for public entry points that other modules call.
-- Frames inside this file (the ROUTE_CHANGED wrappers) are skipped.
local function Caller()
    if type(debugstack) ~= "function" then return "?" end
    local ok, stack = pcall(debugstack, 3, 4, 0)
    if not ok or type(stack) ~= "string" then return "?" end
    local first
    for spot in stack:gmatch("([^\\/\n]+%.lua\"?%]?:%d+)") do
        first = first or spot
        if not spot:find("WorldFocus.lua", 1, true) then return spot end
    end
    return first or (stack:gsub("%s+$", ""))
end

local function RememberRoute(kind, running)
    local settings = addon.GetSettings()
    local oldKind, oldActive = settings.vignetteRadarAutoRouteLastKind, settings.vignetteRadarAutoRouteWasActive
    if kind then settings.vignetteRadarAutoRouteLastKind = kind end
    settings.vignetteRadarAutoRouteWasActive = running == true
    if oldKind ~= settings.vignetteRadarAutoRouteLastKind
        or oldActive ~= settings.vignetteRadarAutoRouteWasActive then
        Trace("RememberRoute lastKind %s -> %s, wasActive %s -> %s", oldKind,
            settings.vignetteRadarAutoRouteLastKind, oldActive, settings.vignetteRadarAutoRouteWasActive)
    end
end

local Number, SecretCall = addon.Secret.Number, addon.Secret.Call

-- First result only, like the old local helper.
local function Call(owner, name, ...)
    return (SecretCall(owner, name, ...))
end

local function Position(item)
    local mapID, x, y = Number(item and item.mapID), Number(item and item.mapX), Number(item and item.mapY)
    if not (mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
    return mapID, x, y
end

-- Quest stops go to Blizzard's own quest super-tracking instead of a fixed
-- user waypoint: it picks the live objective point and moves it as
-- objectives complete. superTrack remembers what to restore afterwards.
local superTrack

local function TrackedQuestID()
    if not (C_SuperTrack and type(C_SuperTrack.GetSuperTrackedQuestID) == "function") then return end
    local ok, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if ok then return Number(questID) end
end

local function SuperTrackableQuest(item)
    if not (type(item) == "table" and item.kind == "quest" and not item.availableStart) then return end
    if addon.GetSettings().vignetteRadarQuestSuperTrack == false then return end
    local questID = Number(item.questID)
    if not questID or questID <= 0 or not (C_SuperTrack
        and type(C_SuperTrack.SetSuperTrackedQuestID) == "function"
        and C_QuestLog and type(C_QuestLog.GetLogIndexForQuestID) == "function") then return end
    local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
    if ok and Number(index) then return questID end
end

local function ReleaseQuestWatch()
    if superTrack and superTrack.addedWatch and C_QuestLog
        and type(C_QuestLog.RemoveQuestWatch) == "function" then
        pcall(C_QuestLog.RemoveQuestWatch, superTrack.questID)
    end
end

-- Named pcall targets, so the guarded reads below allocate no closure.
local function WaypointFields(point)
    return point.uiMapID, point.position.x, point.position.y
end

-- True when the super-tracked user waypoint sits at this map point.
local function UserWaypointAt(mapID, x, y)
    if not (C_Map and type(C_Map.GetUserWaypoint) == "function"
        and Number(mapID) and Number(x) and Number(y)) then return false end
    if C_SuperTrack and type(C_SuperTrack.IsSuperTrackingUserWaypoint) == "function" then
        local tracked, isUserWaypoint = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
        if not tracked or isUserWaypoint == false
            or (issecretvalue and issecretvalue(isUserWaypoint)) then return false end
    end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if not ok or not point or (issecretvalue and issecretvalue(point)) then return false end
    local read, pointMap, pointX, pointY = pcall(WaypointFields, point)
    if not read or not (Number(pointMap) and Number(pointX) and Number(pointY)) then return false end
    return pointMap == mapID and math.abs(pointX - x) < .0001
        and math.abs(pointY - y) < .0001
end

-- Close to a quest objective Blizzard hides its own marker, so the stop
-- swaps to a pinned user waypoint (superTrack.pinned) at the exact spot.
-- Removes that pin when it is still ours; the quest watch stays.
local function ReleaseQuestPin()
    local pin = superTrack and superTrack.pinned
    if not pin then return false end
    superTrack.pinned = nil
    if UserWaypointAt(pin.mapID, pin.x, pin.y) then
        if C_Map and type(C_Map.ClearUserWaypoint) == "function" then pcall(C_Map.ClearUserWaypoint) end
        return true
    end
    return false
end

local function StartQuestSuperTrack(questID)
    if not superTrack then superTrack = { previous = TrackedQuestID() } end
    ReleaseQuestPin()
    if superTrack.questID ~= questID then
        ReleaseQuestWatch()
        superTrack.questID, superTrack.addedWatch = questID, nil
        -- Blizzard only navigates to watched quests.
        if type(C_QuestLog.GetQuestWatchType) == "function"
            and type(C_QuestLog.AddQuestWatch) == "function" then
            local read, watchType = pcall(C_QuestLog.GetQuestWatchType, questID)
            if read and watchType == nil and pcall(C_QuestLog.AddQuestWatch, questID) then
                superTrack.addedWatch = true
            end
        end
    end
    local ok = pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
    Trace("SuperTrack start q%s ok=%s addedWatch=%s previous=%s", questID, ok,
        superTrack.addedWatch, superTrack.previous)
    return ok
end

-- Hands super-tracking back: the quest the person had before, or nothing.
-- Leaves it alone when the person already tracks something else.
local function StopQuestSuperTrack(why)
    if not superTrack then return end
    local ownedPin = ReleaseQuestPin()
    ReleaseQuestWatch()
    local tracked = TrackedQuestID()
    local restore = ownedPin or tracked == superTrack.questID
    if restore then
        local previous = superTrack.previous
        pcall(C_SuperTrack.SetSuperTrackedQuestID,
            previous and previous ~= superTrack.questID and previous or 0)
    end
    Trace("SuperTrack stop q%s why=%s ownedPin=%s tracked=%s restoredPrevious=%s",
        superTrack.questID, why or "?", ownedPin, tracked, restore and superTrack.previous or "no")
    superTrack = nil
end

-- Live Rare Follow: a live rare stop super-tracks the vignette itself, so
-- Blizzard's nav frame (and the World Marker riding it) walks with the rare
-- instead of sitting on a fixed pin. vignetteTrack.guid is the vignette GUID
-- we set (the live target's key, a plain string from GetVignettes).
local vignetteTrack

local function TrackedVignette()
    local guid = SecretCall(C_SuperTrack, "GetSuperTrackedVignette")
    return type(guid) == "string" and guid or nil
end

local function FollowableVignette(step, item)
    if step ~= item or type(item) ~= "table" or item.live ~= true then return nil end
    if item.kind ~= "rare" and item.kind ~= "mob" then return nil end
    if addon.GetSettings().vignetteRadarLiveRareFollow ~= true then return nil end
    if not (C_SuperTrack and type(C_SuperTrack.SetSuperTrackedVignette) == "function") then return nil end
    local guid = item.key
    if type(guid) ~= "string" or guid == "" or (issecretvalue and issecretvalue(guid)) then return nil end
    return guid
end

-- True once Blizzard reports the vignette as the super-tracked one.
local function StartVignetteTrack(guid)
    local ok = pcall(C_SuperTrack.SetSuperTrackedVignette, guid)
    if not ok or TrackedVignette() ~= guid then return false end
    vignetteTrack = { guid = guid }
    return true
end

-- Drops our vignette super-track; Blizzard's is cleared only while it is
-- still ours, like the quest super-track hand-back.
local function StopVignetteTrack(why)
    if not vignetteTrack then return end
    local ours = TrackedVignette() == vignetteTrack.guid
    if ours and C_SuperTrack and type(C_SuperTrack.ClearAllSuperTracked) == "function" then
        pcall(C_SuperTrack.ClearAllSuperTracked)
    end
    Trace("VignetteTrack stop %s why=%s ours=%s", vignetteTrack.guid, why or "?", ours)
    vignetteTrack = nil
end

local function FollowingVignette(step)
    return vignetteTrack ~= nil and type(step) == "table" and step.live == true
        and step.key == vignetteTrack.guid
end

local function ObjectiveFields(objectives, index)
    local objective = objectives[index]
    return objective.finished, objective.numFulfilled
end

local function SameWaypoint(step)
    if FollowingVignette(step) then return TrackedVignette() == vignetteTrack.guid end
    if superTrack and type(step) == "table" and step.kind == "quest"
        and Number(step.questID) == superTrack.questID then
        -- A pinned quest stop is ours while our pin is still the tracked one.
        local pin = superTrack.pinned
        if pin then return UserWaypointAt(pin.mapID, pin.x, pin.y) end
        return TrackedQuestID() == superTrack.questID
    end
    if type(step) ~= "table" then return false end
    return UserWaypointAt(step.mapID, step.mapX, step.mapY)
end

-- Why SameWaypoint answered as it did; trace detail only.
local function SameWaypointWhy(step)
    if type(step) ~= "table" then return "no step" end
    if FollowingVignette(step) then
        return "vignette super-track " .. (TrackedVignette() == vignetteTrack.guid and "still ours" or "lost")
    end
    if superTrack and step.kind == "quest" and Number(step.questID) == superTrack.questID then
        local pin = superTrack.pinned
        if pin then
            return "quest pin " .. (UserWaypointAt(pin.mapID, pin.x, pin.y) and "still ours" or "replaced")
        end
        return "quest super-track q" .. tostring(superTrack.questID)
            .. ", Blizzard tracks q" .. tostring(TrackedQuestID())
    end
    if superTrack then
        return "super-track q" .. tostring(superTrack.questID) .. " is not this stop"
    end
    return "user waypoint " .. (UserWaypointAt(step.mapID, step.mapX, step.mapY)
        and "at stop" or "missing or moved")
end

local function WaypointColor(item)
    if not item then return nil end
    local kind = item.kind == "mob" and "rare" or item.kind
    if kind ~= "rare" and kind ~= "treasure" and kind ~= "quest"
        and kind ~= "guide" then return nil end
    local r, g, b
    local style = addon.VignetteRadarStyle
    if kind == "quest" then
        if addon.GetSettings().vignetteRadarQuestColors and item.colorSlot
            and addon.VignetteRadarQuestColors then
            local color = addon.VignetteRadarQuestColors[item.colorSlot]
            if color then r, g, b = color[1], color[2], color[3] end
        end
    end
    if not r and style and type(style.Color) == "function" then
        r, g, b = style.Color(kind == "rare" and item.isWorldBoss and "boss"
            or kind == "guide" and "accent" or kind)
    end
    if not (Number(r) and Number(g) and Number(b)) then r, g, b = .55, .88, .82 end
    return r, g, b
end

-- Sets the owned user waypoint at step; quest super-track state is untouched.
local function PlacePoint(step, item)
    local mapID, x, y = Position(step)
    if not (mapID and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function"
        and C_Map and type(C_Map.SetUserWaypoint) == "function") then return false, "Waypoint unavailable" end
    if type(C_Map.CanSetUserWaypointOnMap) == "function" then
        local ok, allowed = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
        if not ok or allowed == false or (issecretvalue and issecretvalue(allowed)) then
            return false, "Waypoint unavailable on this map"
        end
    end
    local ok, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x, y)
    if not ok or not point or (issecretvalue and issecretvalue(point)) then return false, "Waypoint unavailable" end
    local wui = _G.WaypointUIAPI and _G.WaypointUIAPI.Navigation
    if item and addon.GetSettings().vignetteRadarWorldFocusThemedWaypoint
        and wui and type(wui.NewUserNavigation) == "function" then
        local r, g, b = WaypointColor(item)
        if r then
            local named, result = pcall(wui.NewUserNavigation, {
                name = item.name or "World Focus", mapID = mapID, x = x * 100, y = y * 100,
                r = r, g = g, b = b, requestRecolor = true, suppressAudio = true,
            })
            if named and result and not (issecretvalue and issecretvalue(result)) then
                local stability = addon.VignetteRadarWaypointStability
                local budget = addon.VignetteRadarBudget
                if stability and addon.GetSettings().vignetteRadarWorldFocusSmoothWaypoint
                    and not (budget and budget.paused
                        and (budget.paused.radar or budget.paused.background)) then
                    stability.Enable()
                elseif stability then stability.Disable() end
                return true
            end
        end
    end
    local stability = addon.VignetteRadarWaypointStability
    if stability then stability.Disable() end
    local placed, result = pcall(C_Map.SetUserWaypoint, point)
    if not placed or result == false or (issecretvalue and issecretvalue(result)) then
        return false, "Waypoint could not be set"
    end
    if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true
end

local function Place(step, item)
    local guid = FollowableVignette(step, item)
    if guid and (FollowingVignette(step) and TrackedVignette() == guid or StartVignetteTrack(guid)) then
        StopQuestSuperTrack("following a live rare")
        if addon.VignetteRadarWaypointStability then addon.VignetteRadarWaypointStability.Disable() end
        Trace("Place %s via vignette super-track", item and item.name)
        return true
    end
    StopVignetteTrack(guid and "vignette super-track failed, pin instead" or "stop is not a live rare")
    local questID = step == item and SuperTrackableQuest(item)
    if questID and StartQuestSuperTrack(questID) then
        if addon.VignetteRadarWaypointStability then addon.VignetteRadarWaypointStability.Disable() end
        Trace("Place %s via quest super-track", item and item.name)
        return true
    end
    StopQuestSuperTrack(questID and "super-track failed, pin instead" or "stop is not a quest objective")
    local ok, reason = PlacePoint(step, item)
    Trace("Place %s via user waypoint ok=%s %s", item and item.name, ok, reason or "")
    return ok, reason
end

local function Valid(item)
    local mapID = Position(item)
    if item and item.kind == "guide" then return mapID ~= nil end
    return mapID and Number(item.worldX) and Number(item.worldY)
        and (not player or not (Number(player.instanceID) and Number(item.instanceID)
            and player.instanceID ~= item.instanceID))
end

local function RouteKind(item)
    if not item then return nil end
    if item.kind == "rare" or item.kind == "mob" then return "rare" end
    if item.kind == "treasure" then return "treasure" end
    if item.kind == "quest" and Number(item.questID) then return "quest" end
    return nil
end

local function RouteID(item)
    local kind = RouteKind(item)
    if not kind then return nil end
    if kind == "quest" then
        return addon.Quests.Key(item.questID, item.availableStart and "start" or "objective",
            math.floor(item.mapX * 10000 + .5), math.floor(item.mapY * 10000 + .5))
    end
    return kind .. ":" .. tostring(item.key or item.name or "location")
end

local function HorizonLabel(item)
    if not item then return "Route Stop" end
    if RouteKind(item) == "quest" and not item.availableStart then
        local objective = item.objectiveText or item.nextStep and item.nextStep.text
        if type(objective) == "string" and objective ~= "" then return objective end
    end
    -- A pack's stand-in name ("Treasure location") reads as kind and zone.
    local guidance = addon.VignetteRadarGuidance
    if guidance and guidance.StopName then return guidance.StopName(item) end
    return item.name or "Route Stop"
end

local function HorizonIdentity(item)
    if RouteKind(item) == "quest" then
        return tostring(item.questID) .. ":" .. (item.availableStart and "start" or "objective")
            .. ":" .. HorizonLabel(item):lower()
    end
    return RouteID(item) or HorizonLabel(item):lower()
end

local function QuestRouteItem(quest)
    return { kind = "quest", questID = quest.questID, name = quest.name,
        colorSlot = quest.colorSlot, taskType = quest.taskType, nextStep = quest.nextStep,
        completed = quest.completed, objectiveText = quest.objectiveText,
        mapID = quest.mapID or player.mapID, mapX = quest.mapX, mapY = quest.mapY,
        worldX = quest.worldX, worldY = quest.worldY, instanceID = quest.instanceID }
end

local function StartRouteItem(start)
    return { kind = "quest", availableStart = true, questID = start.questID,
        questLineID = start.questLineID, isCampaign = start.isCampaign,
        name = start.questName or start.questLineName or "Available Quest",
        mapID = start.mapID, mapX = start.x, mapY = start.y,
        worldX = start.worldX, worldY = start.worldY,
        instanceID = start.instanceID }
end

local function Distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- A short item label for the trace: kind, name, quest, distance, map.
local function Describe(item)
    if type(item) ~= "table" then return "none" end
    local text = tostring(item.kind) .. " '" .. tostring(item.name or item.key or "?") .. "'"
    if item.questID then
        text = text .. " q" .. tostring(item.questID) .. (item.availableStart and " start" or "")
    end
    if player and Number(player.worldX) and Number(player.worldY)
        and Number(item.worldX) and Number(item.worldY) then
        text = text .. string.format(" %.0fyd", Distance(player.worldX, player.worldY,
            item.worldX, item.worldY))
    end
    if player and item.mapID and item.mapID ~= player.mapID then
        text = text .. " map" .. tostring(item.mapID)
    end
    return text
end

-- Why Valid() refused an item; trace detail only.
local function InvalidReason(item)
    if not Position(item) then return "noMapPosition" end
    if item.kind ~= "guide" and not (Number(item.worldX) and Number(item.worldY)) then
        return "noWorldPosition"
    end
    return "otherInstance"
end

-- The last single pick (quest, rare, treasure, note, pin, Zygor step) is
-- kept in vignetteRadarLastFocus so it survives /reload; Core.lua validates
-- it. Auto Route remembers itself instead (RememberRoute), so a route start
-- forgets the pick. restoring holds the record while RestoreFocus re-selects.
local Text = addon.Secret.Text
local FOCUS_TEXT = { "kind", "name", "source" }
local FOCUS_NUMBERS = { "questID", "rewardQuestID", "vignetteID", "npcID", "objectID", "colorSlot",
    "mapID", "mapX", "mapY", "worldX", "worldY", "instanceID" }
local focusMemory = { restored = false, restoring = nil, routeStarting = false, nextAttempt = 0 }

local function ForgetFocus(why)
    local settings = addon.GetSettings()
    if settings.vignetteRadarLastFocus == nil then return end
    settings.vignetteRadarLastFocus = nil
    Trace("LastFocus forget: %s", why or "?")
end

local function SaveFocus(item, stepIndex)
    if not (Position(item) and Text(item.kind)) then
        ForgetFocus("new pick has no map location")
        return
    end
    local record = { key = Text(item.key) or Number(item.key), stepIndex = stepIndex or 1,
        availableStart = item.availableStart == true or nil, live = item.live == true or nil }
    for _, field in ipairs(FOCUS_TEXT) do record[field] = Text(item[field]) end
    for _, field in ipairs(FOCUS_NUMBERS) do record[field] = Number(item[field]) end
    local focus = addon.VignetteRadarFocus
    local entry = focus and type(focus.Get) == "function" and focus.Get() or nil
    if entry and type(focus.Showing) == "function" and focus.Showing(entry) then
        record.focusType = entry.type
    end
    addon.GetSettings().vignetteRadarLastFocus = record
    Trace("LastFocus save %s step %s focus=%s", Describe(record), record.stepIndex, record.focusType)
end

-- A single pick's path step moved on; a reload resumes at that step.
local function RememberFocusStep()
    local record = addon.GetSettings().vignetteRadarLastFocus
    if route or not (active and type(record) == "table") then return end
    record.stepIndex = active.index
end

local function AttachKnownTreasurePath(item)
    if not (item and item.kind == "treasure" and not item.route
        and addon.GetSettings().vignetteRadarTreasurePlaybooks ~= false
        and Number(item.worldX) and Number(item.worldY)) then return end
    for _, note in ipairs(notes) do
        if note.kind == "treasure" and type(note.route) == "table" and #note.route > 1
            and addon.VignetteRadarPoints.Near(note, item, ROUTE_DUPLICATE_YARDS) then
            item.route = note.route
            return
        end
    end
end

local function TravelMode()
    local mode = addon.GetSettings().vignetteRadarAutoRouteTravel or "auto"
    if mode ~= "auto" then return mode end
    -- One travel reader (Core/Travel.lua); skyriding costs like flying.
    local travel = addon.VignetteRadarTravel
    if travel then return travel.Mode() == "ground" and "ground" or "flying" end
    if type(IsFlying) == "function" then
        local ok, flying = pcall(IsFlying)
        if ok and not (issecretvalue and issecretvalue(flying)) and flying == true then
            return "flying"
        end
    end
    return "ground"
end

local function RouteCost(item, travelMode, directOnly)
    local x, y = player.worldX, player.worldY
    local steps = item.route
    if type(steps) ~= "table" or #steps < 2 then
        return Distance(x, y, item.worldX, item.worldY)
    end
    local first = steps[1]
    if not (Number(first.worldX) and Number(first.worldY)) then
        return Distance(x, y, item.worldX, item.worldY)
    end
    local cost = Distance(x, y, first.worldX, first.worldY)
    if directOnly then return cost end
    local path = 0
    local prior = first
    for index = 2, math.min(#steps, 12) do
        local step = steps[index]
        if Number(step.worldX) and Number(step.worldY) then
            path = path + Distance(prior.worldX, prior.worldY, step.worldX, step.worldY)
            prior = step
        end
    end
    -- Ground travel weighs the pack's approach path fully. In flight the
    -- approach still matters, but its interior steps weigh less for ordering.
    return cost + path * (travelMode == "flying" and .35 or 1)
end

local function Visited(item)
    if not route then return false end
    local id, kind = RouteID(item), RouteKind(item)
    if id and route.visited[id] then return true end
    for _, prior in ipairs(route.visitedPlaces) do
        local limit = kind == "quest" and 8
            or (route.kind == "closest" or route.kind == "sweep")
                and (prior.live ~= (item.live == true) and ROUTE_DUPLICATE_YARDS or 8)
                or ROUTE_DUPLICATE_YARDS
        local dx, dy = prior.x - item.worldX, prior.y - item.worldY
        if prior.kind == kind and prior.mapID == item.mapID
            and (kind ~= "quest" or prior.questID == item.questID)
            and (kind ~= "quest" or prior.availableStart == (item.availableStart == true))
            and dx * dx + dy * dy <= limit * limit then return true end
    end
    return false
end

local function MarkVisited(item)
    if not route or not item then return end
    horizonCache = nil
    local id = RouteID(item)
    if id then route.visited[id] = true end
    if #route.visitedPlaces < ROUTE_LIMIT and Number(item.worldX) and Number(item.worldY) then
        route.visitedPlaces[#route.visitedPlaces + 1] = {
            kind = RouteKind(item), questID = item.questID, mapID = item.mapID,
            availableStart = item.availableStart == true,
            live = item.live == true,
            x = item.worldX, y = item.worldY,
        }
    end
end

local function RememberQuestStep(stack, item)
    if not (stack and item and RouteKind(item) == "quest") then return end
    local id = RouteID(item)
    if not id or (#stack > 0 and RouteID(stack[#stack]) == id) then return end
    if #stack >= 64 then table.remove(stack, 1) end
    stack[#stack + 1] = item
end

QuestComplete = function(questID)
    if not (questID and C_QuestLog) then return false end
    local function Done(callback)
        if type(callback) == "function" then
            local ok, done = pcall(callback, questID)
            if ok and not (issecretvalue and issecretvalue(done)) and done == true then
                return true
            end
        end
        return false
    end
    if type(C_QuestLog.IsOnQuest) == "function" then
        local ok, onQuest = pcall(C_QuestLog.IsOnQuest, questID)
        if ok and not (issecretvalue and issecretvalue(onQuest)) and onQuest == true then
            return false -- Objectives may be done, but the quest still needs its turn-in.
        end
    end
    return Done(C_QuestLog.IsQuestFlaggedCompleted) or Done(C_QuestLog.IsComplete)
end

local function HiddenWarbandQuestStart(item, trackingAccountQuests, checked)
    if not (item and item.availableStart and item.questID
        and trackingAccountQuests == false) then return false end
    if checked and checked[item.questID] ~= nil then return checked[item.questID] end
    -- Accepted quests still have real objectives even when completed elsewhere.
    local hidden = Call(C_QuestLog, "IsOnQuest", item.questID) ~= true
        and Call(C_QuestLog, "IsQuestFlaggedCompletedOnAccount", item.questID) == true
    if checked then checked[item.questID] = hidden end
    return hidden
end

local function AvailableQuestStep(saved)
    if not (saved and player and route and route.kind == "quest"
        and saved.mapID == player.mapID and not QuestComplete(saved.questID)
        and not (route.skippedQuests and route.skippedQuests[saved.questID])) then return nil end
    if C_QuestLog and type(C_QuestLog.IsOnQuest) == "function" then
        local ok, onQuest = pcall(C_QuestLog.IsOnQuest, saved.questID)
        if ok and not (issecretvalue and issecretvalue(onQuest)) and onQuest == false then
            return nil
        end
    end
    for _, quest in ipairs(quests) do
        if quest.questID == saved.questID then
            local current = QuestRouteItem(quest)
            if current.mapID == player.mapID and Valid(current)
                and (RouteID(current) == RouteID(saved)
                    or Distance(current.worldX, current.worldY, saved.worldX, saved.worldY) <= 8) then
                return current
            end
        end
    end
end

local function QuestProgress(questID)
    if not (questID and C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function") then return nil end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" or (issecretvalue and issecretvalue(objectives)) then return nil end
    local result, finishedState = {}, {}
    for index = 1, math.min(#objectives, 16) do
        local read, complete, count = pcall(ObjectiveFields, objectives, index)
        if not read or (issecretvalue and (issecretvalue(complete) or issecretvalue(count))) then return nil end
        result[#result + 1] = (complete and "1" or "0") .. ":" .. tostring(Number(count) or 0)
        finishedState[#finishedState + 1] = complete and "1" or "0"
    end
    return table.concat(result, ","), table.concat(finishedState)
end

local function NewlyFinishedObjective(previous, current)
    if type(previous) ~= "string" or type(current) ~= "string" then return false end
    for index = 1, #current do
        if current:sub(index, index) == "1" and previous:sub(index, index) ~= "1" then
            return true
        end
    end
    return false
end

-- Every objective done, turned in, abandoned or otherwise gone from the log.
-- With "Move On After Each Objective" off this is the only thing that ends a
-- quest stop; one finished objective while others remain never does.
local function QuestGone(questID)
    if not Number(questID) then return false end
    if Call(C_QuestLog, "IsOnQuest", questID) == false then return true, "quest left the log" end
    if Call(C_QuestLog, "IsQuestFlaggedCompleted", questID) == true then return true, "quest turned in" end
    if Call(C_QuestLog, "IsComplete", questID) == true then return true, "all objectives complete" end
    if Call(C_QuestLog, "ReadyForTurnIn", questID) == true then return true, "all objectives complete" end
    return false
end

-- Zone Sweep (Routes/ZoneSweep.lua) hands over a planned stop order. The
-- next stop is the first planned one still usable: not visited, not cleared
-- or looted (Recent), and its reward quest not done (Declutter).
local function SweepStop()
    local recent, declutter = addon.VignetteRadarRecent, addon.VignetteRadarDeclutter
    for index, item in ipairs(route.plan or {}) do
        local why
        if not Valid(item) then why = "invalid"
        elseif Visited(item) then why = "visited"
        elseif route.previewIdentities and route.previewIdentities[HorizonIdentity(item)] then why = "preview"
        elseif recent and type(recent.IsHidden) == "function" and recent.IsHidden(item) then why = "cleared"
        elseif declutter and type(declutter.Done) == "function"
            and (declutter.Done(item.rewardQuestID) or declutter.Done(item.questID)) then why = "done" end
        if not why then
            Trace("SweepStop chose %d/%d %s", index, #route.plan, Describe(item))
            return item
        end
    end
    Trace("SweepStop: no usable stop left in %d planned", #(route.plan or {}))
    return nil
end

local function NextRouteStop()
    if not (route and player) then
        Trace("NextRouteStop skipped: %s", route and "no player snapshot" or "no route")
        return nil
    end
    if route.kind == "sweep" then return SweepStop() end
    local kind = route.kind
    -- Trace only: items seen per source and rejections per reason.
    local tracing = TraceOn()
    local seen = tracing and {} or nil
    local rejected = tracing and {} or nil
    local function Reject(reason)
        if rejected then rejected[reason] = (rejected[reason] or 0) + 1 end
    end
    local best, bestCost, bestRank
    local bestWorldQuest, bestWorldQuestCost
    local inspected = 0
    local limit = (kind == "closest" or kind == "quest")
        and ROUTE_LIMIT * 3 or ROUTE_LIMIT
    local travelMode = TravelMode()
    local settings = addon.GetSettings()
    local questDone = {}
    local warbandDone = {}
    local trackingAccountQuests = Call(C_Minimap, "IsTrackingAccountCompletedQuests")
    -- IsOnQuest per quest, read once per call: true, false or "unknown".
    local onQuestCache = {}
    local function OnQuest(questID)
        if questID == nil then return "unknown" end
        local value = onQuestCache[questID]
        if value == nil then
            value = Call(C_QuestLog, "IsOnQuest", questID)
            if value ~= true and value ~= false then value = "unknown" end
            onQuestCache[questID] = value
        end
        return value
    end
    local exploration = addon.VignetteRadarExploration
    local focusedQuestID = kind == "quest" and exploration
        and type(exploration.GetFocusedQuest) == "function"
        and exploration.GetFocusedQuest() or nil
    -- A picked quest with every objective done no longer holds the route.
    if route.manualQuestID and QuestGone(route.manualQuestID) then
        route.manualQuestID = nil
    end
    if focusedQuestID and QuestGone(focusedQuestID) then
        focusedQuestID = nil
    end
    local selectedQuestID = route.manualQuestID or focusedQuestID
    -- Same checks, in the same order, as one early return per reason.
    local function Consider(item, source)
        if seen then seen[source] = (seen[source] or 0) + 1 end
        if inspected >= limit then return Reject("overLimit") end
        inspected = inspected + 1
        -- Area POIs (events, delves, races) and collection-tracked points ride only the Closest route.
        local itemKind = RouteKind(item)
            or (kind == "closest" and (item.areaPoiID or item.contentTracking) and "event") or nil
        if not itemKind or (kind ~= "closest" and itemKind ~= kind) then return Reject("wrongKind") end
        if not Valid(item) then return Reject(rejected and InvalidReason(item)) end
        if item.mapID ~= player.mapID and itemKind == "quest"
            and settings.vignetteRadarAutoRouteNearbyZones == false then return Reject("otherMap") end
        if Visited(item) then return Reject("visited") end
        if route.previewIdentities and route.previewIdentities[HorizonIdentity(item)] then
            return Reject("preview")
        end
        if itemKind == "quest" then
            if route.skippedQuests and route.skippedQuests[item.questID] then return Reject("skipped") end
            if selectedQuestID and item.questID ~= selectedQuestID then return Reject("notSelectedQuest") end
            if kind == "quest" and settings.vignetteRadarAutoRouteQuestNearest == false
                and route.questID and item.questID ~= route.questID then return Reject("otherQuest") end
        end
        if itemKind == "quest" then
            if HiddenWarbandQuestStart(item, trackingAccountQuests,
                warbandDone) then
                return Reject("warband")
            end
            local complete = questDone[item.questID]
            if complete == nil then
                complete = QuestGone(item.questID) == true
                questDone[item.questID] = complete
            end
            if complete and not item.availableStart then return Reject("questComplete") end
        end
        if itemKind == "quest" then
            local onQuest = OnQuest(item.questID)
            if item.availableStart and onQuest == true then return Reject("startAccepted") end
            if not item.availableStart and onQuest == false then return Reject("notOnQuest") end
        end
        local recent = addon.VignetteRadarRecent
        if itemKind ~= "quest" and recent and type(recent.IsHidden) == "function"
            and recent.IsHidden(item) then return Reject("hiddenCleared") end
        local cost = RouteCost(item, travelMode, kind == "closest")
        if kind == "quest" and not selectedQuestID
            and settings.vignetteRadarWorldQuestPriority ~= false
            and item.taskType == "world" and item.mapID == player.mapID
            and Number(item.worldX) and Number(item.worldY)
            and Distance(player.worldX, player.worldY, item.worldX, item.worldY)
                <= (Number(settings.vignetteRadarWorldQuestPriorityRange) or 300)
            and (not bestWorldQuest or cost < bestWorldQuestCost) then
            bestWorldQuest, bestWorldQuestCost = item, cost
        end
        local rank = itemKind == "rare" and 1 or itemKind == "treasure" and 2
            or item.availableStart and 3.1 or 3
        local tied = bestCost and math.abs(cost - bestCost) <= (kind == "closest" and .5 or 0)
        if not best or (not tied and cost < bestCost)
            or (tied and (rank < bestRank or (rank == bestRank
                and (cost < bestCost or cost == bestCost
                    and tostring(RouteID(item)) < tostring(RouteID(best)))))) then
            best, bestCost, bestRank = item, cost, rank
        end
    end
    if kind == "quest" or kind == "closest" then
        for _, quest in ipairs(quests) do
            Consider(QuestRouteItem(quest), "quests")
        end
        local pool = addon.VignetteRadarRouteQuests
        if pool and type(pool.CurrentQuestWaypoint) == "function"
            and route.waiting and active and active.kind == "quest" and active.item
            and route.questID == active.item.questID
            and OnQuest(route.questID) == true then
            Consider(pool.CurrentQuestWaypoint(route.questID), "nextStep")
        end
        if settings.vignetteRadarAutoRouteQuestStarts ~= false then
            for _, start in ipairs(addon.VignetteRadarAvailableStarts or {}) do
                Consider(StartRouteItem(start), "starts")
            end
        end
        if pool and settings.vignetteRadarAutoRouteNearbyZones ~= false then
            for _, quest in ipairs(pool.Candidates()) do Consider(quest, "pool") end
        end
    end
    if kind ~= "quest" then
        local live = {}
        for _, target in ipairs(targets) do
            if (target.category == kind or kind == "closest"
                and (target.category == "rare" or target.category == "treasure"))
                and not target.stale and not target.sample then
                live[#live + 1] = { key = target.key, kind = target.category, name = target.name,
                    live = true, source = target.source,
                    isWorldBoss = target.isWorldBoss, atlasName = target.atlasName,
                    mapID = target.mapID, mapX = target.mapX, mapY = target.mapY,
                    worldX = target.worldX, worldY = target.worldY,
                    instanceID = target.instanceID, rewardQuestID = target.rewardQuestID,
                    npcID = target.npcID, objectGUID = target.objectGUID,
                    objectID = target.objectID, isDead = target.isDead }
            end
        end
        local unpairedNotes = {}
        if settings.vignetteRadarAutoRouteMapNotes then
            for _, note in ipairs(notes) do
                if RouteKind(note) == kind or kind == "closest"
                    and (RouteKind(note) == "rare" or RouteKind(note) == "treasure"
                        or note.areaPoiID and settings.vignetteRadarAreaPOIRoute == true
                        or note.contentTracking and settings.vignetteRadarCollectionTrackingRoute == true) then
                    local duplicate
                    for _, target in ipairs(live) do
                        if addon.VignetteRadarPoints.Near(note, target, ROUTE_DUPLICATE_YARDS) then
                            duplicate = target
                            break
                        end
                    end
                    if duplicate then
                        if duplicate.kind == "treasure" and not duplicate.route
                            and type(note.route) == "table" and #note.route > 1 then
                            duplicate.route = note.route
                        end
                    else unpairedNotes[#unpairedNotes + 1] = note end
                end
            end
        end
        for _, item in ipairs(live) do Consider(item, "live") end
        for _, note in ipairs(unpairedNotes) do Consider(note, "notes") end
    end
    if tracing then
        local function Counts(map)
            local keys, parts = {}, {}
            for key in pairs(map) do keys[#keys + 1] = key end
            table.sort(keys)
            for index, key in ipairs(keys) do parts[index] = key .. "=" .. map[key] end
            return #parts > 0 and table.concat(parts, " ") or "none"
        end
        Trace("NextRouteStop kind=%s waiting=%s selectedQuest=%s mapNotes=%s | seen: %s | rejected: %s | chose %s%s",
            kind, route.waiting, selectedQuestID, settings.vignetteRadarAutoRouteMapNotes == true,
            Counts(seen), Counts(rejected), Describe(bestWorldQuest or best),
            bestWorldQuest and " (world quest priority)" or "")
    end
    return bestWorldQuest or best
end

local function ArrivalRadius()
    local settings = addon.GetSettings()
    if (route and route.kind == "treasure") or (active and active.kind == "treasure") then
        return 3
    end
    return route and (settings.vignetteRadarAutoRouteArrivalRadius or 10)
        or (settings.vignetteRadarWorldFocusArrivalRadius or 20)
end

local function ArmArrival()
    if not (active and player) then return end
    local step = active.steps[active.index]
    if not (step and Number(step.worldX) and Number(step.worldY)) then return end
    local radius = ArrivalRadius()
    local margin = route and 0 or 5
    active.wasOutside = Distance(player.worldX, player.worldY,
        step.worldX, step.worldY) > radius + margin
end

-- "Keep Marker Until Looted Or Killed": rare and treasure stops ignore
-- arrival distance and wait for matching loot or the rare's death.
local function KeepUntilDone(item)
    local kind = RouteKind(item)
    return (kind == "rare" or kind == "treasure")
        and addon.GetSettings().vignetteRadarKeepMarkerUntilDone == true
end

local RARE_GONE_YARDS = 100

-- A rare is done once Recent records it cleared, or its live vignette died
-- or vanished while the player was close enough to still see it.
local function RareGone(item)
    if RouteKind(item) ~= "rare" then return false end
    local recent = addon.VignetteRadarRecent
    if recent and type(recent.IsHidden) == "function" and recent.IsHidden(item) then return true end
    if not (item.live and player and item.mapID == player.mapID
        and Number(player.worldX) and Number(player.worldY)
        and Number(item.worldX) and Number(item.worldY)
        and Distance(player.worldX, player.worldY, item.worldX, item.worldY) <= RARE_GONE_YARDS) then
        return false
    end
    for _, target in ipairs(targets) do
        if target.key == item.key and not target.sample then
            return target.stale == true or target.isDead == true
        end
    end
    return true
end

-- The followed rare's live target in the latest scan, or nil.
local function LiveTargetFor(item)
    for _, target in ipairs(targets) do
        if target.key == item.key and not target.sample then return target end
    end
end

-- A walking rare: the stop takes the vignette's latest position each scan,
-- so arrival, distance and the marker text follow it.
local function FollowLiveRare(item)
    local target = LiveTargetFor(item)
    if not target then return end
    local x, y = Number(target.worldX), Number(target.worldY)
    local mapX, mapY = Number(target.mapX), Number(target.mapY)
    if x and y then item.worldX, item.worldY = x, y end
    if mapX and mapY then item.mapX, item.mapY = mapX, mapY end
end

-- The followed rare's vignette is gone, dead or stale in the latest scan.
local function LiveRareLost(item)
    local target = LiveTargetFor(item)
    return not target or target.stale == true or target.isDead == true
end

local QUEST_PIN_YARDS, QUEST_PIN_LEAVE_YARDS = 40, 60

-- The exact objective spot on the player's map: Blizzard's next waypoint
-- for this map, else the nearest live quest point, else the stop itself.
-- Once an objective of a held stop finished, the stop's own spot may be that
-- finished objective, so it is never used as the fallback then.
local function QuestPinPoint(item)
    local data = addon.VignetteRadarQuestData
    local step = data and type(data.GetNextStep) == "function"
        and data.GetNextStep(item.questID, player.mapID) or nil
    if step and step.onCurrentMap and Number(step.x) and Number(step.y) then
        local worldX, worldY = Number(item.worldX), Number(item.worldY)
        if active and active.pastObjective then
            -- The stop's own spot is stale; measure to Blizzard's point instead.
            local pool = addon.VignetteRadarRouteQuests
            local live = pool and type(pool.CurrentQuestWaypoint) == "function"
                and pool.CurrentQuestWaypoint(item.questID) or nil
            worldX, worldY = live and Number(live.worldX), live and Number(live.worldY)
        end
        return { mapID = step.mapID, x = step.x, y = step.y, worldX = worldX, worldY = worldY }
    end
    local best, bestDistance = not (active and active.pastObjective) and item or nil, nil
    for _, quest in ipairs(quests) do
        if quest.questID == item.questID and Position(quest) and quest.mapID == player.mapID
            and Number(quest.worldX) and Number(quest.worldY) then
            local distance = Distance(player.worldX, player.worldY, quest.worldX, quest.worldY)
            if not bestDistance or distance < bestDistance then best, bestDistance = quest, distance end
        end
    end
    local mapID, x, y = Position(best)
    if not mapID then return nil end
    return { mapID = mapID, x = x, y = y, worldX = Number(best.worldX), worldY = Number(best.worldY) }
end

-- While super-tracking a quest stop: pin the exact spot once inside the
-- quest area (or close to the point), and hand back to Blizzard's
-- super-track when the player leaves. superTrack.pinned keeps SameWaypoint
-- truthful, so the swap never looks like an outside waypoint change.
local function UpdateQuestPin()
    if not (superTrack and active and active.kind == "quest" and active.item
        and Number(active.item.questID) == superTrack.questID and active.index == 1
        and player and Number(player.worldX) and Number(player.worldY)) then return end
    local questID = superTrack.questID
    local point = addon.GetSettings().vignetteRadarQuestPinWhenClose ~= false
        and QuestPinPoint(active.item) or nil
    local want = false
    if point then
        local data = addon.VignetteRadarQuestData
        local inArea = data and type(data.IsQuestInArea) == "function" and data.IsQuestInArea(questID) == true
        local distance = point.worldX and point.worldY
            and Distance(player.worldX, player.worldY, point.worldX, point.worldY)
        want = inArea or (distance and distance <= (superTrack.pinned
            and QUEST_PIN_LEAVE_YARDS or QUEST_PIN_YARDS)) or false
    end
    local pin = superTrack.pinned
    if want then
        if pin and pin.mapID == point.mapID and math.abs(pin.x - point.x) < .0001
            and math.abs(pin.y - point.y) < .0001 then return end
        if PlacePoint({ mapID = point.mapID, mapX = point.x, mapY = point.y }, active.item) then
            superTrack.pinned = { mapID = point.mapID, x = point.x, y = point.y }
            Trace("QuestPin q%s pinned exact spot %.4f,%.4f (%s)", questID, point.x, point.y,
                pin and "moved" or "entered area or came close")
        else
            Trace("QuestPin q%s pin could not be placed", questID)
            return
        end
    elseif pin then
        -- Left the area: Blizzard guides again. Our old pin is removed first.
        local swapped = StartQuestSuperTrack(questID)
        Trace("QuestPin q%s left area, back to super-track ok=%s", questID, swapped)
        if not swapped then return end
        if addon.VignetteRadarWaypointStability then addon.VignetteRadarWaypointStability.Disable() end
    else return end
    if addon.VignetteRadarWorldMarker then addon.VignetteRadarWorldMarker.Refresh() end
end

local function RouteNote(label, message, item)
    if type(addon.ShowVignetteRadarRouteNote) == "function" then
        local questData = addon.VignetteRadarQuestData
        local objective = item and item.kind == "quest" and not item.availableStart
            and questData and questData.GetObjectiveSummary
            and questData.GetObjectiveSummary(item.questID,
                item.objectiveText or item.nextStep and item.nextStep.text) or nil
        addon.ShowVignetteRadarRouteNote(label, message, objective)
    end
end

local function Activate(item)
    lootSession = nil
    horizonCache = nil
    local steps = { item }
    if item.kind == "treasure" and addon.GetSettings().vignetteRadarWorldFocusRoutes
        and addon.GetSettings().vignetteRadarTreasurePlaybooks ~= false
        and type(item.route) == "table" and #item.route > 1 then steps = item.route end
    -- A restored pick resumes at its saved path step, and reuses Blizzard's
    -- user waypoint when it survived the reload instead of placing another.
    local first, ok, reason = 1, nil, nil
    local restoring = focusMemory.restoring
    if restoring then
        local index = Number(restoring.stepIndex)
        if index and index > 1 and index <= #steps and index == math.floor(index) then first = index end
    end
    if restoring and not SuperTrackableQuest(item) and SameWaypoint(steps[first]) then
        ok = true
        Trace("Activate %s: Blizzard kept this waypoint through the reload; reusing it", Describe(item))
    else
        ok, reason = Place(steps[first], item)
    end
    Trace("Activate %s steps=%s ok=%s %s", Describe(item), #steps, ok, reason or "")
    if not ok then return false, reason end
    active = { key = item.key or item.questID or item.name, name = item.name or "Location",
        kind = item.kind, questID = item.questID, item = item, steps = steps, index = first,
        wasOutside = false }
    if route and (route.kind == "closest" or route.kind == "quest") then
        route.questID = item.kind == "quest" and item.questID or nil
        if route.questID and not item.availableStart then
            route.progress, route.finished = QuestProgress(route.questID)
        else route.progress, route.finished = nil, nil end
    end
    ArmArrival()
    local detail = type(item.note) == "string" and item.note ~= "" and item.kind ~= "guide"
        and (" · " .. item.note) or ""
    RouteNote(item.kind == "guide" and "ZYGOR STEP" or route and "AUTO ROUTE" or "WORLD FOCUS",
        active.name .. (#steps > 1 and (" · " .. first .. "/" .. #steps) or "") .. detail, item)
    if addon.VignetteRadarWorldMarker then addon.VignetteRadarWorldMarker.Refresh() end
    return true
end

local function RecordQuestAdvance()
    if not (route and route.kind == "quest" and active) then return end
    route.previous = route.previous or {}
    RememberQuestStep(route.previous, active.item)
    route.forward = {}
end

-- The same quest's next live point for a held stop on a plain waypoint:
-- Blizzard's next waypoint (objective or turn-in) first, else the nearest
-- quest point not yet visited. Nil when nothing newer is known yet.
local function HeldQuestPoint(item)
    local questID = Number(item.questID)
    local current = RouteID(item)
    local function Fresh(candidate)
        return candidate and RouteKind(candidate) == "quest" and Number(candidate.questID) == questID
            and not candidate.availableStart and Valid(candidate)
            and RouteID(candidate) ~= current and not Visited(candidate)
    end
    local pool = addon.VignetteRadarRouteQuests
    local blizzard = pool and type(pool.CurrentQuestWaypoint) == "function"
        and pool.CurrentQuestWaypoint(questID) or nil
    if Fresh(blizzard) then return blizzard end
    local best, bestDistance
    for _, quest in ipairs(quests) do
        local candidate = QuestRouteItem(quest)
        if Fresh(candidate) then
            local distance = Distance(player.worldX, player.worldY, candidate.worldX, candidate.worldY)
            if not bestDistance or distance < bestDistance then best, bestDistance = candidate, distance end
        end
    end
    return best
end

-- "Move On After Each Objective" off: a finished objective keeps the quest as
-- the stop until it is turned in. Super-track and its close-range pin follow
-- Blizzard's next point by themselves; a plain waypoint moves to the same
-- quest's next point, so the marker never sits on a finished objective.
local function FollowHeldQuest(why)
    if not (route and active and active.kind == "quest" and active.item) then return end
    local item = active.item
    active.pastObjective = true
    if superTrack and superTrack.questID == Number(item.questID) then
        Trace("HoldQuest q%s (%s): super-track moves the marker; pin follows", item.questID, why)
        UpdateQuestPin()
        if addon.VignetteRadarWorldMarker then addon.VignetteRadarWorldMarker.Refresh() end
        return
    end
    local nextItem = HeldQuestPoint(item)
    if not nextItem then
        active.heldRetry = true
        Trace("HoldQuest q%s (%s): no newer point yet; keeping the stop", item.questID, why)
        return
    end
    Trace("HoldQuest q%s (%s): waypoint follows to %s", item.questID, why, Describe(nextItem))
    RecordQuestAdvance()
    MarkVisited(item)
    local ok, reason = Activate(nextItem)
    if not ok then Trace("HoldQuest q%s: next point could not be placed (%s)", item.questID, reason) end
end

local function AdvanceRoute(force, why)
    if not (route and active) then
        Trace("AdvanceRoute (%s) ignored: %s", why or "?", route and "no active stop" or "no route")
        return false
    end
    if route.locked and not force then
        Trace("AdvanceRoute (%s) refused: stop is locked", why or "?")
        return false, "Current stop is locked"
    end
    Trace("AdvanceRoute (%s) kind=%s from %s", why or "?", route.kind, Describe(active.item))
    RecordQuestAdvance()
    MarkVisited(active.item)
    local nextItem = NextRouteStop()
    if nextItem then
        route.waiting = false
        local ok, reason = Activate(nextItem)
        if not ok then
            Trace("AdvanceRoute: next stop could not be placed (%s); route stopped", reason)
            route = nil
            RememberRoute(nil, false)
            RouteNote("AUTO ROUTE", "Route stopped" .. (reason and (" · " .. reason) or ""))
        end
        return ok, reason
    end
    if route.kind == "closest" then
        route.waiting, route.waitingTicks = true, 0
        Trace("AdvanceRoute: no candidate; Closest waits")
        RouteNote("AUTO ROUTE", "Closest is waiting for a nearby point")
        return true, "Waiting for a nearby point"
    end
    route.waiting = route.kind == "quest" and (route.questID ~= nil
        or addon.GetSettings().vignetteRadarAutoRouteNearbyZones ~= false
        or addon.GetSettings().vignetteRadarAutoRouteQuestStarts ~= false)
    if route.waiting then
        Trace("AdvanceRoute: no candidate; %s route waits", route.kind)
        RouteNote("AUTO ROUTE", active.item.availableStart
            and "Waiting for the accepted quest objective"
            or "Waiting for the next quest location")
    else
        Trace("AdvanceRoute: no candidate; %s route complete, clearing", route.kind)
        route = nil
        if API.Clear then API.Clear(true, "route complete") else active = nil end
        RouteNote("AUTO ROUTE", "Route complete")
    end
    return false
end

local function Select(item, directPin)
    if not ((directPin or addon.GetSettings().vignetteRadarWorldFocusEnabled) and Valid(item)) then
        Trace("Select %s refused: no usable location", Describe(item))
        return false, "No usable location"
    end
    AttachKnownTreasurePath(item)
    local ok, reason = Activate(item)
    if not ok then return false, reason end
    if item.kind ~= "guide" and addon.VignetteRadarZygor then
        addon.VignetteRadarZygor.PauseForManual("Manual waypoint selected")
    end
    lastSelected = item
    if route or pausedRoute then
        Trace("Select %s replaces %s route %s (caller %s)", Describe(item), route and "running" or "paused",
            (route or pausedRoute).kind, TraceOn() and Caller() or "")
    end
    route, pausedRoute = nil, nil
    local kind = RouteKind(item)
    if kind and addon.GetSettings().vignetteRadarAutoRouteOnSelect then
        local progress, finished
        if kind == "quest" then progress, finished = QuestProgress(item.questID) end
        route = { kind = kind, questID = kind == "quest" and item.questID or nil,
            manualQuestID = kind == "quest" and item.questID or nil,
            visited = {}, visitedPlaces = {}, waiting = false,
            progress = progress, finished = finished }
    end
    RememberRoute(route and route.kind, route ~= nil)
    if route then ForgetFocus("Auto Route started on select; the route remembers itself")
    elseif not focusMemory.routeStarting then SaveFocus(item, active.index) end
    ArmArrival()
    if addon.VignetteRadarConstellation then addon.VignetteRadarConstellation.FocusChanged() end
    return true
end

function API.ToggleRoute()
    if route then
        Trace("ToggleRoute pause %s route", route.kind)
        pausedRoute, route = route, nil
        RememberRoute(pausedRoute.kind, false)
        RouteNote("AUTO ROUTE", "Paused · " .. (active and active.name or "Waypoint kept"))
        return false, "Auto Route paused; waypoint kept"
    end
    if pausedRoute then
        if not (active and active.steps[active.index]
            and SameWaypoint(active.steps[active.index])) then
            Trace("ToggleRoute resume refused: waypoint changed (%s)",
                active and SameWaypointWhy(active.steps[active.index]) or "no active stop")
            pausedRoute = nil
            RememberRoute(nil, false)
            return false, "Route waypoint changed; choose a point to start again"
        end
        route, pausedRoute = pausedRoute, nil
        RememberRoute(route.kind, true)
        ArmArrival()
        RouteNote("AUTO ROUTE", "Resumed · " .. (active and active.name or "Current waypoint"),
            active and active.item)
        return true, "Auto Route resumed"
    end
    local item = active and active.item or lastSelected
    local kind = RouteKind(item)
    if not kind then return false, "Click a rare, treasure, or quest point first" end
    if not addon.GetSettings().vignetteRadarWorldFocusEnabled or not Valid(item)
        or not player or item.mapID ~= player.mapID then
        return false, "This point is not available on the current map"
    end
    if not (active and active.item == item and SameWaypoint(active.steps[active.index])) then
        local ok, reason = Activate(item)
        if not ok then return false, reason end
    end
    local progress, finished
    if kind == "quest" then progress, finished = QuestProgress(item.questID) end
    route = { kind = kind, questID = kind == "quest" and item.questID or nil,
        manualQuestID = kind == "quest" and item.questID or nil,
        visited = {}, visitedPlaces = {}, waiting = false,
        progress = progress, finished = finished }
    Trace("ToggleRoute start %s route at %s", kind, Describe(item))
    RememberRoute(kind, true)
    ForgetFocus("Auto Route started; the route remembers itself")
    ArmArrival()
    RouteNote("AUTO ROUTE", "Started · " .. (active and active.name or item.name or kind), item)
    return true, "Auto Route: " .. kind
end

function API.IsRouteActive() return route ~= nil end
function API.IsRoutePaused() return pausedRoute ~= nil end
function API.IsRouteLocked() return (route or pausedRoute) and (route or pausedRoute).locked == true or false end
function API.ToggleRouteLock()
    local current = route or pausedRoute
    if not (current and active) then return false, "Start an Auto Route first" end
    current.locked = not current.locked
    RouteNote("AUTO ROUTE", current.locked and "Current stop locked" or "Current stop unlocked")
    return true, current.locked
end
function API.IsQuestRoute() return route and route.kind == "quest" or false end
-- Ends Auto Route (running or paused) and forgets it, keeping the waypoint.
-- Used when the person chooses Zygor follow instead.
function API.StopRoute()
    Trace("StopRoute (caller %s) route=%s paused=%s", TraceOn() and Caller() or "",
        route and route.kind, pausedRoute and pausedRoute.kind)
    route, pausedRoute = nil, nil
    RememberRoute(nil, false)
end
function API.WantsQuestPool()
    if route then return route.kind == "quest" or route.kind == "closest" end
    local settings = addon.GetSettings()
    return settings.vignetteRadarAutoRouteRestore == true
        and settings.vignetteRadarAutoRouteWasActive == true
        and (settings.vignetteRadarAutoRouteLastKind == "quest"
            or settings.vignetteRadarAutoRouteLastKind == "closest") or false
end
function API.GetRouteChoice()
    if route then return route.kind, "active" end
    if pausedRoute then return pausedRoute.kind, "paused" end
    if active then
        if active.kind == "guide" then return "zygor", "focus" end
        return RouteKind(active.item), "focus"
    end
    local settings = addon.GetSettings()
    if settings.vignetteRadarAutoRouteRestore == true
        and settings.vignetteRadarAutoRouteWasActive == true then
        return settings.vignetteRadarAutoRouteLastKind, "waiting"
    end
end
function API.HasFocus() return active ~= nil end
-- The focused item and its current step, for the in-world marker.
function API.GetActiveTarget()
    if not active then return nil end
    return active.item, active.steps[active.index], active.index, #active.steps
end
function API.TargetColor(item) return WaypointColor(item) end
function API.GetFocusedStep()
    return active and active.steps[active.index] or nil
end
-- True while a quest stop shows a pinned exact spot instead of super-track.
function API.IsQuestPinned() return superTrack ~= nil and superTrack.pinned ~= nil end

-- Read-only geometry for the constellation. Only remaining explicit approach
-- steps are returned; route selection and arrival state stay here.
function API.GetConstellationPath()
    if not (active and active.item and active.steps and active.index) then return nil end
    local points = {}
    for index = active.index, math.min(#active.steps, active.index + 31) do
        local step = active.steps[index]
        local x, y = Number(step and step.worldX), Number(step and step.worldY)
        if not (x and y) then break end
        points[#points + 1] = { worldX = x, worldY = y,
            instanceID = Number(step.instanceID), mapID = Number(step.mapID),
            key = type(step.key) == "string" and step.key or nil }
    end
    return { destinationKey = type(active.item.key) == "string" and active.item.key or nil,
        points = points, hasExplicitSteps = #active.steps > 1,
        truncated = #active.steps > active.index + 31 }
end

function API.GetRoutePoint()
    if not (route and not route.waiting and active) then return nil end
    return active.steps[active.index], (route.kind == "closest" or route.kind == "sweep")
        and RouteKind(active.item) or route.kind, active.name,
        active.index, #active.steps
end
function API.GetTrackedRouteKind()
    local current = route or pausedRoute
    if not active or current and current.waiting then return nil end
    return active.kind == "guide" and "zygor" or RouteKind(active.item)
end

function API.ExplainActive()
    if not (active and active.item) then return "No active destination" end
    local item = active.item
    local source = item.kind == "quest" and (item.nextStep and "Blizzard next step" or "Blizzard quest point")
        or item.kind == "guide" and "Zygor guide"
        or item.live and (item.source == "worldMap" and "Blizzard world map" or "Live vignette")
        or item.source and ("Saved map note · " .. item.source) or "Selected location"
    local rule = item.availableStart and "advances when the quest is accepted"
        or item.kind == "quest" and "advances on objective progress"
        or item.kind == "treasure" and KeepUntilDone(item) and "advances on matching loot"
        or item.kind == "treasure" and "advances at 3 yd or on matching loot"
        or item.kind == "rare" and "advances when cleared or skipped"
        or "follows its guide step"
    return source .. " · " .. rule
end

-- The current stop and a preview of the next ones: limit entries in all
-- (default 3, at most HORIZON_MAX). Cached for three seconds; a shorter
-- request is served from a longer cached preview (one memoized slice).
local HORIZON_MAX = 6
function API.GetHorizon(limit)
    if not (route and active and player) then return {} end
    limit = math.max(1, math.min(HORIZON_MAX, math.floor(Number(limit) or 3)))
    local now = type(GetTime) == "function" and GetTime() or 0
    if horizonCache and horizonCache.limit >= limit and now >= (horizonCachedAt or 0)
        and now - (horizonCachedAt or 0) < 3 then
        if horizonCache.limit == limit then return horizonCache end
        horizonCache.slices = horizonCache.slices or {}
        local slice = horizonCache.slices[limit]
        if not slice then
            slice = { limit = limit }
            for index = 1, math.min(limit, #horizonCache) do slice[index] = horizonCache[index] end
            horizonCache.slices[limit] = slice
        end
        return slice
    end
    local result, shown = {}, {}
    if not route.waiting then
        result[1] = { name = active.name, kind = RouteKind(active.item) or active.kind,
            label = HorizonLabel(active.item), item = active.item, current = true }
        shown[HorizonIdentity(active.item)] = true
    end
    local original = route
    local previewRoute = { kind = original.kind, questID = original.questID,
        manualQuestID = original.manualQuestID, waiting = original.waiting,
        skippedQuests = original.skippedQuests, visited = {}, visitedPlaces = {},
        previewIdentities = shown, plan = original.plan }
    for id, seen in pairs(original.visited or {}) do previewRoute.visited[id] = seen end
    for index, place in ipairs(original.visitedPlaces or {}) do
        previewRoute.visitedPlaces[index] = place
    end
    route = previewRoute
    previewing = true
    local ok = pcall(function()
        if not original.waiting then MarkVisited(active.item) end
        -- Candidate pools may hold several map points for one quest objective.
        -- Preview identities filter these before another destination is chosen.
        for _ = #result + 1, limit do
            local nextItem = NextRouteStop()
            if not nextItem then break end
            local identity = HorizonIdentity(nextItem)
            result[#result + 1] = { name = nextItem.name,
                label = HorizonLabel(nextItem), kind = RouteKind(nextItem),
                item = nextItem, current = false }
            shown[identity] = true
            MarkVisited(nextItem)
        end
    end)
    previewing = false
    route = original
    if not ok then return result end
    result.limit = limit
    horizonCache, horizonCachedAt = result, now
    return result
end

function API.OwnsGuideWaypoint()
    return active and active.kind == "guide" and active.steps[active.index]
        and SameWaypoint(active.steps[active.index]) or false
end

-- why: a short reason for the trace. Callers outside this file pass none;
-- the trace then names the calling file and line.
function API.Clear(silent, why)
    horizonCache = nil
    if TraceOn() then
        Trace("Clear why=%s caller=%s active=%s route=%s paused=%s", why or "external",
            Caller(), Describe(active and active.item), route and route.kind, pausedRoute and pausedRoute.kind)
    end
    if not active then
        RememberRoute(nil, false)
        ForgetFocus("Clear: " .. (why or "external"))
        return false, "No focused waypoint"
    end
    local name = active.name
    local step = active.steps[active.index]
    if superTrack then
        StopQuestSuperTrack("Clear: " .. (why or "external"))
    elseif vignetteTrack then
        StopVignetteTrack("Clear: " .. (why or "external"))
    elseif step and SameWaypoint(step) then
        if not (C_Map and type(C_Map.ClearUserWaypoint) == "function") then
            Trace("Clear refused: waypoint removal unavailable")
            return false, "Waypoint removal is unavailable"
        end
        if type(InCombatLockdown) == "function" then
            local checked, locked = pcall(InCombatLockdown)
            if not checked or (issecretvalue and issecretvalue(locked)) or locked then
                Trace("Clear refused: in combat")
                return false, "Leave combat to clear the waypoint"
            end
        end
        local cleared = pcall(C_Map.ClearUserWaypoint)
        if not cleared then
            Trace("Clear refused: ClearUserWaypoint failed")
            return false, "Waypoint could not be cleared"
        end
    end
    if active.kind == "guide" and addon.VignetteRadarZygor then
        addon.VignetteRadarZygor.PauseForManual("Guide waypoint cleared")
    end
    active, route, pausedRoute, lastSelected, lootSession = nil, nil, nil, nil, nil
    RememberRoute(nil, false)
    ForgetFocus("Clear: " .. (why or "external"))
    if addon.VignetteRadarWaypointStability then
        addon.VignetteRadarWaypointStability.Disable()
    end
    if not silent then RouteNote("WORLD FOCUS", "Cleared · " .. (name or "Waypoint")) end
    if addon.VignetteRadarConstellation then addon.VignetteRadarConstellation.FocusChanged() end
    if addon.VignetteRadarWorldMarker then addon.VignetteRadarWorldMarker.Refresh() end
    return true
end

function API.StartNearest(kind, restoring)
    if kind ~= "rare" and kind ~= "treasure" and kind ~= "quest"
        and kind ~= "closest" then
        return false, "Choose Closest, Rare, Treasure, or Quest"
    end
    if kind == "closest" or kind == "quest" or kind == "rare"
        or kind == "treasure" then
        if not addon.GetSettings().vignetteRadarWorldFocusEnabled or not player then
            Trace("StartNearest %s restoring=%s refused: World Focus off or no player", kind, restoring)
            return false, "World Focus is unavailable"
        end
        if not (Number(player.worldX) and Number(player.worldY)) then
            Trace("StartNearest %s restoring=%s refused: no player position", kind, restoring)
            return false, "Player location is unavailable"
        end
        local pool = addon.VignetteRadarRouteQuests
        if not restoring and (kind == "closest" or kind == "quest") and pool and pool.Tick then
            pool.Tick(true)
        end
        local previous = route
        route = { kind = kind, visited = {}, visitedPlaces = {}, waiting = false }
        local nearest = NextRouteStop()
        route = previous
        if not nearest then
            Trace("StartNearest %s restoring=%s: no candidate", kind, restoring)
            return false,
            kind == "quest" and "No Quest Objective or Available Start Found Yet"
            or kind == "treasure" and "No Eligible Treasure in Live or Selected Map Data"
            or kind == "rare" and "No Eligible Rare in Live or Selected Map Data"
            or "No Rare, Treasure, or Quest Point Found Yet"
        end
        route = nil
        focusMemory.routeStarting = true
        local ok, reason = Select(nearest)
        focusMemory.routeStarting = false
        Trace("StartNearest %s restoring=%s chose %s ok=%s %s", kind, restoring,
            Describe(nearest), ok, reason or "")
        if not ok then route = previous; return false, reason end
        ForgetFocus("Auto Route started; the route remembers itself")
        route = { kind = kind, visited = {}, visitedPlaces = {}, waiting = false }
        if nearest.kind == "quest" then
            route.questID = nearest.questID
            if not nearest.availableStart then
                route.progress, route.finished = QuestProgress(nearest.questID)
            end
        end
        ArmArrival()
        RememberRoute(kind, true)
        -- The route choice is exclusive and sticks: choosing an Auto Route
        -- turns Zygor follow off (not just paused), so the guide cannot take
        -- the waypoint back when this route finishes or the game reloads.
        local zygor = addon.VignetteRadarZygor
        if zygor and zygor.SetFollow and addon.GetSettings().vignetteRadarFollowZygor == true then
            zygor.SetFollow(false)
        end
        RouteNote("AUTO ROUTE", (kind == "quest" and "Quest" or kind == "rare" and "Rare"
            or kind == "treasure" and "Treasure" or "Closest")
            .. " · " .. (active and active.name or nearest.name or "Point"), nearest)
        return true, nearest
    end
end

-- Zone Sweep: runs Auto Route over a planned stop order (Routes/ZoneSweep.lua
-- builds it). Stops advance like any route stop (arrival, loot, cleared);
-- the plan is not saved, so a reload does not restore a sweep.
function API.StartSweep(plan)
    if type(plan) ~= "table" or #plan == 0 then return false, "No Rare or Treasure Left to Sweep" end
    if not addon.GetSettings().vignetteRadarWorldFocusEnabled or not player
        or not (Number(player.worldX) and Number(player.worldY)) then
        Trace("StartSweep refused: World Focus off or no player position")
        return false, "World Focus is unavailable"
    end
    local previous = route
    route = { kind = "sweep", plan = plan, visited = {}, visitedPlaces = {}, waiting = false }
    local first = SweepStop()
    route = previous
    if not first then return false, "No Rare or Treasure Left to Sweep" end
    route = nil
    focusMemory.routeStarting = true
    local ok, reason = Select(first)
    focusMemory.routeStarting = false
    Trace("StartSweep %d stops, first %s ok=%s %s", #plan, Describe(first), ok, reason or "")
    if not ok then route = previous; return false, reason end
    ForgetFocus("Zone Sweep started; the plan lives in memory only")
    route = { kind = "sweep", plan = plan, visited = {}, visitedPlaces = {}, waiting = false }
    ArmArrival()
    RememberRoute(nil, false)
    local zygor = addon.VignetteRadarZygor
    if zygor and zygor.SetFollow and addon.GetSettings().vignetteRadarFollowZygor == true then
        zygor.SetFollow(false)
    end
    RouteNote("AUTO ROUTE", "Zone Sweep · " .. #plan .. " stops · " .. (active and active.name or "Point"), first)
    return true, first
end

-- The running sweep's planned stops, in order, and the current one's place.
function API.GetSweepPlan()
    local current = route or pausedRoute
    if not (current and current.kind == "sweep" and type(current.plan) == "table") then return nil end
    local at
    for index, item in ipairs(current.plan) do
        if active and item == active.item then at = index; break end
    end
    return current.plan, at
end

function API.SkipRouteStop()
    if not (route and active) then return false, "No active route" end
    return AdvanceRoute(true, "Skip Stop")
end

-- Jumps the running route to a stop GetHorizon previewed (the Next 3 Stops
-- Strip). The current stop counts as visited, like Skip Stop, and the route
-- carries on from the chosen stop.
function API.JumpRouteStop(item)
    if not (route and active) then return false, "No active route" end
    if type(item) ~= "table" or item == active.item then return false, "Already the current stop" end
    if not Valid(item) then
        Trace("JumpRouteStop %s refused: no usable location", Describe(item))
        return false, "No usable location"
    end
    Trace("JumpRouteStop from %s to %s (caller %s)", Describe(active.item), Describe(item),
        TraceOn() and Caller() or "")
    if not route.waiting then
        RecordQuestAdvance()
        MarkVisited(active.item)
    end
    local ok, reason = Activate(item)
    if not ok then return false, reason end
    route.waiting = false
    RouteNote("AUTO ROUTE", "Jumped · " .. (active and active.name or "Route stop"), item)
    return true
end

function API.SkipQuest()
    if not (route and route.kind == "quest" and route.questID) then
        return false, "No active quest route"
    end
    route.skippedQuests = route.skippedQuests or {}
    route.skippedQuests[route.questID] = true
    route.questID, route.progress, route.finished, route.waiting = nil, nil, nil, false
    local advanced, reason = AdvanceRoute(true, "Skip Quest")
    return advanced or not route, reason or "Quest skipped"
end

function API.PreviousQuestStep()
    if not (route and route.kind == "quest" and active) then
        return false, "Start a quest Auto Route first"
    end
    route.previous = route.previous or {}
    while #route.previous > 0 do
        local point = AvailableQuestStep(route.previous[#route.previous])
        if point then
            local current = not route.waiting and active.item or nil
            local ok, reason = Activate(point)
            if not ok then return false, reason end
            table.remove(route.previous)
            route.forward = route.forward or {}
            RememberQuestStep(route.forward, current)
            route.questID, route.waiting = point.questID, false
            RouteNote("QUEST ROUTE", "Previous · " .. (point.name or "Quest point"))
            return true, point
        end
        table.remove(route.previous)
    end
    return false, "No previous quest point is still available"
end

function API.NextQuestStep()
    if not (route and route.kind == "quest" and active) then
        return false, "Start a quest Auto Route first"
    end
    route.forward = route.forward or {}
    while #route.forward > 0 do
        local point = AvailableQuestStep(route.forward[#route.forward])
        if point then
            local current = not route.waiting and active.item or nil
            local ok, reason = Activate(point)
            if not ok then return false, reason end
            table.remove(route.forward)
            route.previous = route.previous or {}
            RememberQuestStep(route.previous, current)
            route.questID, route.waiting = point.questID, false
            RouteNote("QUEST ROUTE", "Next · " .. (point.name or "Quest point"))
            return true, point
        end
        table.remove(route.forward)
    end
    if route.waiting then
        local point = NextRouteStop()
        if not point then return false, "Waiting for the next quest point" end
        local ok, reason = Activate(point)
        if ok then route.waiting = false end
        return ok, reason
    end
    local ok, reason = AdvanceRoute(true, "Next Quest Step")
    return ok, reason or (not ok and "Waiting for the next quest point")
end

function API.SelectTarget(target)
    if not target or target.stale or target.sample then return false, "No live target" end
    return Select({ key = target.key, name = target.name, kind = target.category,
        live = true, source = target.source, atlasName = target.atlasName,
        isWorldBoss = target.isWorldBoss, rewardQuestID = target.rewardQuestID,
        npcID = target.npcID, objectGUID = target.objectGUID,
        objectID = target.objectID, isDead = target.isDead,
        mapID = target.mapID, mapX = target.mapX, mapY = target.mapY,
        worldX = target.worldX, worldY = target.worldY, instanceID = target.instanceID })
end

function API.SelectQuest(questID)
    local nearest, nearestDistance, nearestOnMap
    for _, quest in ipairs(quests) do
        if quest.questID == questID and Number(quest.worldX) and Number(quest.worldY) then
            local onMap = player and quest.mapID == player.mapID or false
            local distance = onMap and Number(player.worldX) and Number(player.worldY)
                and Distance(player.worldX, player.worldY, quest.worldX, quest.worldY)
                or math.huge
            if not nearest or (onMap and not nearestOnMap)
                or (onMap == nearestOnMap and distance < nearestDistance) then
                nearest, nearestDistance, nearestOnMap = quest, distance, onMap
            end
        end
    end
    if nearest then
        return Select({ key = addon.Quests.Key(questID), questID = questID,
            name = nearest.name, kind = "quest", colorSlot = nearest.colorSlot,
            completed = nearest.completed, taskType = nearest.taskType,
            nextStep = nearest.nextStep, objectiveText = nearest.objectiveText,
            mapID = nearest.mapID, mapX = nearest.mapX, mapY = nearest.mapY,
            worldX = nearest.worldX, worldY = nearest.worldY,
            instanceID = nearest.instanceID })
    end
    return false, "Quest point unavailable"
end

function API.SelectNote(note, directPin)
    if not note then return false, "No map note" end
    if note.kind == "entrance" and note.parentCoord and type(note.source) == "string" then
        for _, candidate in ipairs(notes) do
            if candidate.kind == "treasure" and candidate.mapID == note.mapID
                and candidate.key == note.source .. ":" .. note.mapID .. ":" .. note.parentCoord then
                return Select(candidate, directPin)
            end
        end
    end
    return Select(note, directPin)
end

function API.SelectPoint(point, directPin)
    return Select(point, directPin)
end

function API.LoadZygorGuide(note)
    if not (note and note.zygorPoint) then return false end
    local viewer = _G.ZygorGuidesViewer
    local poi = viewer and viewer.Poi
    if not (poi and type(poi.LoadPoint) == "function") then return false end
    local ok = pcall(poi.LoadPoint, poi, note.zygorPoint)
    if ok then addon.GetSettings().vignetteRadarWorldFocusZygor = true end
    return ok
end

local function BuildCandidates()
    candidates = {}
    if not (player and Number(player.worldX) and Number(player.worldY)) then return end
    local db = addon.GetSettings()
    local function Add(item, priority)
        if #candidates >= 128 or not Valid(item)
            or not (Number(item.worldX) and Number(item.worldY)) then return end
        local dx, dy = item.worldX - player.worldX, item.worldY - player.worldY
        item.focusDistance = math.sqrt(dx * dx + dy * dy)
        item.focusPriority = priority
        candidates[#candidates + 1] = item
    end
    for _, target in ipairs(targets) do
        if not target.stale and not target.sample and (target.category == "rare"
            or target.category == "treasure") then
            Add({ key = target.key, name = target.name, kind = target.category, live = true,
                isWorldBoss = target.isWorldBoss, atlasName = target.atlasName,
                mapID = target.mapID, mapX = target.mapX, mapY = target.mapY,
                worldX = target.worldX, worldY = target.worldY, instanceID = target.instanceID }, 1)
        end
    end
    for _, quest in ipairs(quests) do
        Add({ key = addon.Quests.Key(quest.questID, math.floor((quest.mapX or 0) * 10000)),
            questID = quest.questID, colorSlot = quest.colorSlot,
            completed = quest.completed, taskType = quest.taskType,
            name = quest.name, kind = "quest", mapID = quest.mapID or player.mapID,
            mapX = quest.mapX, mapY = quest.mapY, worldX = quest.worldX,
            worldY = quest.worldY, instanceID = quest.instanceID }, 2)
    end
    for _, note in ipairs(notes) do
        if note.kind == "guide" and db.vignetteRadarWorldFocusZygor then Add(note, 2) end
        if db.vignetteRadarWorldFocusSavedNotes and (note.kind == "treasure"
            or note.kind == "mob" or note.kind == "entrance") then
            local duplicate = false
            if note.kind ~= "entrance" then
                for _, target in ipairs(candidates) do
                    if target.focusPriority == 1
                        and addon.VignetteRadarPoints.Near(note, target, ROUTE_DUPLICATE_YARDS) then
                        duplicate = true; break
                    end
                end
            end
            if not duplicate then Add(note, 3) end
        end
    end
    table.sort(candidates, function(a, b)
        if a.focusPriority ~= b.focusPriority then return a.focusPriority < b.focusPriority end
        if a.focusDistance ~= b.focusDistance then return a.focusDistance < b.focusDistance end
        return tostring(a.key) < tostring(b.key)
    end)
end

-- A route's quest objective stop whose quest is done or has left the log.
-- Blizzard drops (or moves) its quest super-track when a quest is turned in,
-- so a lost waypoint here is route progress, not an outside change.
local function FinishedQuestStop()
    if not (route and (route.kind == "closest" or route.kind == "quest")
        and active and active.kind == "quest" and active.item
        and not active.item.availableStart and Number(active.item.questID)) then return false end
    if active.questDone then return true, "already finished" end
    local questID = active.item.questID
    -- Held until every objective is done: one finished objective is not the end.
    return QuestGone(questID)
end

-- Why a saved pick is no longer worth restoring, or nil when it still is.
local function SavedFocusGone(record)
    local questID = Number(record.questID)
    if record.kind == "quest" then
        if Call(C_QuestLog, "IsQuestFlaggedCompleted", questID) == true then return "quest completed" end
        local onQuest = Call(C_QuestLog, "IsOnQuest", questID)
        if record.availableStart then
            if onQuest == true then return "quest start already accepted" end
        elseif onQuest == false then
            return "quest no longer in the log"
        end
        return nil
    end
    local doneID = Number(record.rewardQuestID) or questID
    if doneID and Call(C_QuestLog, "IsQuestFlaggedCompleted", doneID) == true then
        return "already done (q" .. doneID .. " completed)"
    end
    local recent = addon.VignetteRadarRecent
    if recent and type(recent.IsHidden) == "function" and recent.IsHidden(record) then
        return "cleared recently"
    end
    return nil
end

-- The same rare or treasure, live on the radar right now.
local function LiveFocusTarget(record)
    if record.kind ~= "rare" and record.kind ~= "treasure" and record.kind ~= "mob" then return nil end
    local points = addon.VignetteRadarPoints
    for _, target in ipairs(targets) do
        if not target.stale and not target.sample then
            if record.key ~= nil and target.key == record.key then return target end
            if (record.vignetteID and target.vignetteID == record.vignetteID
                or record.name and target.name == record.name)
                and points and points.Near(record, target, ROUTE_DUPLICATE_YARDS) then
                return target
            end
        end
    end
end

local function SavedFocusItem(record)
    local item = {}
    for field, value in pairs(record) do item[field] = value end
    item.stepIndex, item.focusType, item.live = nil, nil, nil
    return item
end

-- Re-selects the pick through the normal paths, so the waypoint or quest
-- super-track, world marker, route arrow and radar focus all come back.
local function ReselectFocus(record)
    local service = addon.VignetteRadarFocus
    local live = LiveFocusTarget(record)
    if live then
        Trace("LastFocus restore: '%s' is live; using the live vignette", tostring(record.name))
        local ok, reason = API.SelectTarget(live)
        return ok, reason, service and service.Target(live)
    end
    local item = SavedFocusItem(record)
    if record.kind == "quest" then
        local ok, reason
        if not record.availableStart then ok, reason = API.SelectQuest(record.questID) end
        if not ok then ok, reason = Select(item) end
        return ok, reason, service and service.Quest(record.questID, active and active.item or item)
    end
    if record.kind == "guide" then
        local ok, reason = Select(item, true)
        return ok, reason, service and service.Point(active and active.item or item)
    end
    if record.source and record.key ~= nil then
        for _, note in ipairs(notes) do
            if note.key == record.key then
                local ok, reason = API.SelectNote(note)
                return ok, reason, service and service.Note(active and active.item or note)
            end
        end
    end
    local ok, reason = Select(item)
    local entry = service and (record.focusType == "note" and service.Note(active and active.item or item)
        or service.Point(active and active.item or item))
    return ok, reason, entry
end

-- Once per session, on the first scan with a player position: brings back
-- the last single pick unless an Auto Route restore wins or it is gone.
local function RestoreFocus(settings)
    local record = settings.vignetteRadarLastFocus
    if type(record) ~= "table" then focusMemory.restored = true; return end
    local function Skip(why, forget)
        focusMemory.restored = true
        Trace("LastFocus restore skipped: %s (%s)", why, Describe(record))
        if forget then ForgetFocus(why) end
    end
    if route or pausedRoute or active then return Skip("something is already focused") end
    if settings.vignetteRadarAutoRouteRestore == true and settings.vignetteRadarAutoRouteWasActive == true then
        return Skip("Auto Route restore takes priority")
    end
    if not settings.vignetteRadarWorldFocusEnabled then return Skip("World Focus is off") end
    if record.kind == "guide" and addon.VignetteRadarZygor and addon.VignetteRadarZygor.IsFollowing() then
        return Skip("Zygor follow pins its own current step")
    end
    local gone = SavedFocusGone(record)
    if gone then return Skip(gone, true) end
    if Number(player.instanceID) and Number(record.instanceID) and player.instanceID ~= record.instanceID then
        -- Kept: retried every few seconds until the player is back there.
        local now = type(GetTime) == "function" and GetTime() or 0
        if now >= focusMemory.nextAttempt then
            focusMemory.nextAttempt = now + 5
            Trace("LastFocus restore waits: player is in another instance (%s)", Describe(record))
        end
        return
    end
    focusMemory.restored = true
    focusMemory.restoring = record
    local called, ok, reason, entry = pcall(ReselectFocus, record)
    focusMemory.restoring = nil
    if not called then ok, reason = false, tostring(ok) end
    Trace("LastFocus restore %s ok=%s %s", Describe(record), ok, reason or "")
    if not ok then return end
    local service = addon.VignetteRadarFocus
    if service and entry then service.Select(entry, { project = false, source = "restore" }) end
end

function API.Sync(mapID, snapshot, liveTargets, questPoints, mapNotes)
    targets, quests, notes, player = liveTargets or {}, questPoints or {}, mapNotes or {}, snapshot
    if player then player.mapID = mapID end
    local settings = addon.GetSettings()
    if settings.vignetteRadarWorldFocusEnabled then BuildCandidates()
    else
        candidates = {}
        if not (active and active.kind == "guide" and addon.VignetteRadarZygor
            and addon.VignetteRadarZygor.IsFollowing())
            and (active or route or pausedRoute) then
            Trace("Sync: World Focus is off; dropping focus and route")
            -- Clear releases the owned waypoint and quest super-track. It refuses
            -- in combat; then drop the super-track and our state directly.
            if not (active and API.Clear(true, "World Focus turned off")) then
                StopQuestSuperTrack("World Focus turned off")
                StopVignetteTrack("World Focus turned off")
                active, route, pausedRoute = nil, nil, nil
                ForgetFocus("World Focus turned off")
            end
        end
    end
    if not (route or pausedRoute or active)
        and settings.vignetteRadarWorldFocusEnabled == true
        and settings.vignetteRadarAutoRouteRestore == true
        and settings.vignetteRadarAutoRouteWasActive == true
        and player and Number(player.worldX) and Number(player.worldY) then
        local now = type(GetTime) == "function" and GetTime() or 0
        if now >= nextRestoreAttempt then
            nextRestoreAttempt = now + 5
            Trace("Sync: restoring Auto Route %s", settings.vignetteRadarAutoRouteLastKind)
            local restored, reason = API.StartNearest(settings.vignetteRadarAutoRouteLastKind, true)
            Trace("Sync: restore ok=%s %s", restored,
                type(reason) == "table" and Describe(reason) or reason or "")
        end
    end
    if not focusMemory.restored and player and Number(player.worldX) and Number(player.worldY) then
        RestoreFocus(settings)
    end
    if not (active and player) then
        if TraceOn() then
            Trace("Sync map=%s: nothing focused (route=%s paused=%s player=%s)", mapID,
                route and route.kind, pausedRoute and pausedRoute.kind, player ~= nil)
        end
        if addon.VignetteRadarWaypointStability then
            addon.VignetteRadarWaypointStability.Disable()
        end
        return
    end
    local step = active.steps[active.index]
    if FollowingVignette(step) then FollowLiveRare(step) end
    local same = step and SameWaypoint(step)
    if TraceOn() then
        Trace("Sync map=%s route=%s waiting=%s locked=%s paused=%s active=%s step=%s/%s same=%s (%s)",
            mapID, route and route.kind, route and route.waiting, route and route.locked,
            pausedRoute and pausedRoute.kind, Describe(active.item), active.index, #active.steps,
            same, SameWaypointWhy(step))
    end
    if not same then
        local finished, why = FinishedQuestStop()
        if finished then
            -- The finished quest's super-track is gone; release ours and
            -- keep the route: advance now, or keep waiting for a point.
            Trace("Sync: quest stop q%s finished (%s); waypoint loss is progress", active.item.questID, why)
            StopQuestSuperTrack("quest finished")
            active.questDone = true
            route.questID, route.progress, route.finished = nil, nil, nil
            if not route.waiting then
                AdvanceRoute(false, "quest finished")
                return
            end
            same = true
        end
    end
    if not same and FollowingVignette(step) and LiveRareLost(step) then
        -- Blizzard drops a vignette super-track when the vignette goes: the
        -- followed rare died or despawned, which is progress, not a change.
        Trace("Sync: followed rare %s is gone; vignette super-track ended", Describe(step))
        vignetteTrack = nil
        if route then AdvanceRoute(true, "followed rare gone") return end
        RouteNote("CLEARED", active.name)
        active = nil
        ForgetFocus("followed rare gone")
        if addon.VignetteRadarWorldMarker then addon.VignetteRadarWorldMarker.Refresh() end
        return
    end
    if not same then
        Trace("Sync: waypoint changed outside the radar (%s); dropping focus and route %s",
            SameWaypointWhy(step), route and route.kind or pausedRoute and pausedRoute.kind)
        if active.kind == "guide" and addon.VignetteRadarZygor then
            addon.VignetteRadarZygor.PauseForManual("Waypoint changed outside the radar")
        end
        StopQuestSuperTrack("waypoint changed outside the radar")
        vignetteTrack = nil
        active, route, pausedRoute = nil, nil, nil
        RememberRoute(nil, false)
        ForgetFocus("waypoint changed outside the radar")
        if addon.VignetteRadarWaypointStability then
            addon.VignetteRadarWaypointStability.Disable()
        end
        return
    end
    if route and (route.kind == "closest" or route.kind == "quest") and active.item
        and HiddenWarbandQuestStart(active.item,
            Call(C_Minimap, "IsTrackingAccountCompletedQuests")) then
        Trace("Sync: current stop is a warband-completed quest start; replacing it")
        local nextItem = NextRouteStop()
        if nextItem then
            local ok = Activate(nextItem)
            if not ok then API.Clear(true, "warband start, next stop failed") end
        else API.Clear(true, "warband start, no next stop") end
        return
    end
    local stability = addon.VignetteRadarWaypointStability
    if stability then
        local smooth = settings.vignetteRadarWorldFocusSmoothWaypoint
            and settings.vignetteRadarWorldFocusThemedWaypoint
            and _G.WaypointUIAPI and _G.WaypointUIAPI.Navigation
            and not (addon.VignetteRadarBudget and addon.VignetteRadarBudget.paused
                and (addon.VignetteRadarBudget.paused.radar
                    or addon.VignetteRadarBudget.paused.background))
        if smooth and not stability.IsEnabled() then stability.Enable()
        elseif not smooth then stability.Disable() end
    end
    if not (Number(player.worldX) and Number(player.worldY)) then return end
    UpdateQuestPin()
    if route and route.locked then Trace("Sync: route locked; no automatic advance"); return end
    if route and route.kind == "closest" and route.waiting then
        -- A waiting mixed route stays armed, but retries only on every second
        -- data scan. An empty zone should stay cheap while new points appear.
        route.waitingTicks = (route.waitingTicks or 0) + 1
        if route.waitingTicks >= 2 then
            route.waitingTicks = 0
            local nextItem = NextRouteStop()
            if nextItem then
                local ok = Activate(nextItem)
                if ok then route.waiting = false end
                if TraceOn() then Trace("Sync: Closest waiting retry chose %s ok=%s", Describe(nextItem), ok) end
            else
                Trace("Sync: Closest waiting retry found nothing; still waiting")
            end
        else
            Trace("Sync: Closest waiting, retry on the next scan (tick %s)", route.waitingTicks)
        end
        return
    end
    local keep = KeepUntilDone(active.item)
    if route and active.kind ~= "quest" and (keep and RareGone(active.item)
        or addon.VignetteRadarRecent and addon.VignetteRadarRecent.IsHidden(active.item)
        and (keep or active.kind ~= "rare" or Number(step.worldX) and Number(step.worldY)
            and Distance(player.worldX, player.worldY,
                step.worldX, step.worldY) <= ArrivalRadius())) then
        AdvanceRoute(false, keep and "kept stop looted, killed or gone" or "stop cleared or hidden")
        return
    end
    if route and active.kind == "quest"
        and (route.kind == "quest" or route.kind == "closest") then
        if active.item.availableStart then
            local onQuest = Call(C_QuestLog, "IsOnQuest", active.item.questID)
            if onQuest == true and not route.waiting then AdvanceRoute(false, "quest start accepted"); return end
            if route.waiting then
                local nextItem = NextRouteStop()
                if TraceOn() then Trace("Sync: waiting after quest start, next=%s", Describe(nextItem)) end
                if nextItem then route.waiting = false; Activate(nextItem) end
            end
            return
        end
        local perObjective = settings.vignetteRadarAutoRouteQuestMoveOn == "each"
        local gone, why = QuestGone(route.questID)
        if gone then
            Trace("Sync: quest stop q%s ended (%s); advancing", route.questID, why)
            route.questID, route.progress, route.finished = nil, nil, nil
            AdvanceRoute(false, why)
            return
        end
        local progress, finished = QuestProgress(route.questID)
        if not perObjective and NewlyFinishedObjective(route.finished, finished) then
            Trace("Sync: objective finished q%s %s -> %s; holding the quest stop until all objectives are done",
                route.questID, route.finished, finished)
            route.progress, route.finished = progress, finished
            FollowHeldQuest("objective finished")
            return
        elseif not perObjective and active.heldRetry and not route.waiting then
            active.heldRetry = nil
            FollowHeldQuest("retry after objective")
            return
        elseif NewlyFinishedObjective(route.finished, finished) then
            Trace("Sync: NewlyFinishedObjective q%s %s -> %s", route.questID, route.finished, finished)
            route.progress, route.finished = progress, finished
            if route.kind == "closest"
                or settings.vignetteRadarAutoRouteQuestNearest ~= false then
                AdvanceRoute(false, "objective finished"); return
            end
            RecordQuestAdvance()
            MarkVisited(active.item)
            route.waiting = true
            RouteNote("AUTO ROUTE", "Waiting for the next quest objective")
        else
            if TraceOn() and progress ~= route.progress then
                Trace("Sync: quest q%s progress %s -> %s", route.questID, route.progress, progress)
            end
            route.progress = progress or route.progress
            route.finished = finished or route.finished
        end
        if route.waiting then
            local nextItem = NextRouteStop()
            if TraceOn() then Trace("Sync: quest route waiting, next=%s", Describe(nextItem)) end
            if nextItem then route.waiting = false; Activate(nextItem) end
            return
        end
    end
    -- Zygor follow is driven by guide messages, never by the ordinary scan.
    if active.kind == "guide" then return end
    if not (Number(step.worldX) and Number(step.worldY)
        and Number(player.worldX) and Number(player.worldY)) then return end
    if pausedRoute or (not route and not settings.vignetteRadarWorldFocusAutoAdvance) then return end
    if active.kind == "quest" then return end -- Quest points wait for objective or quest progress.
    if keep and active.index >= #active.steps then
        -- Held until looted or killed: routes advance above or on loot.
        local recent = addon.VignetteRadarRecent
        if not route and (RareGone(active.item)
            or recent and type(recent.IsHidden) == "function" and recent.IsHidden(active.item)) then
            RouteNote("CLEARED", active.name)
            active = nil
            ForgetFocus("kept stop looted, killed or cleared")
        end
        return
    end
    if Number(player.instanceID) and Number(step.instanceID)
        and player.instanceID ~= step.instanceID then return end
    local dx, dy = player.worldX - step.worldX, player.worldY - step.worldY
    local distance = math.sqrt(dx * dx + dy * dy)
    local radius = ArrivalRadius()
    if distance > radius + (route and 0 or 5) then active.wasOutside = true end
    if not active.wasOutside or distance > radius then return end
    if active.index < #active.steps then
        local nextStep = active.steps[active.index + 1]
        local ok = Place(nextStep, active.item)
        if ok then
            active.index, active.wasOutside = active.index + 1, false
            RememberFocusStep()
            RouteNote("NEXT STEP", active.name .. " · " .. active.index .. "/" .. #active.steps)
        end
    elseif route and active.kind == "rare" then
        -- Reaching a rare is not completing it. Keep the current target while
        -- the player fights; a recorded kill/clear or Skip Stop advances it.
        return
    elseif route then AdvanceRoute(false, "arrived")
    else
        RouteNote("ARRIVED", active.name)
        active = nil
        ForgetFocus("arrived")
    end
end

function API.Cycle(direction)
    if #candidates == 0 then return false, "No nearby focus points" end
    local index = direction and direction < 0 and 1 or 0
    for i, candidate in ipairs(candidates) do
        if active and candidate.key == active.key then index = i; break end
    end
    for offset = 1, #candidates do
        local nextIndex = ((index - 1 + (direction or 1) * offset) % #candidates) + 1
        local candidate = candidates[nextIndex]
        local ok = candidate.source and API.SelectNote(candidate) or Select(candidate)
        if ok then return true, candidates[nextIndex] end
    end
    return false, "No waypoint can be set here"
end

function API.Status()
    local step = active and active.steps[active.index]
    local distance = step and player and Number(step.worldX) and Number(step.worldY)
        and Number(player.worldX) and Number(player.worldY)
        and math.floor(Distance(player.worldX, player.worldY,
            step.worldX, step.worldY) + .5)
    local prefix = distance and not (route and route.waiting)
        and distance .. " yd · " or ""
    if route then
        local kind = route.kind == "rare" and "Rare" or route.kind == "treasure"
            and "Treasure" or route.kind == "closest" and "Closest"
            or route.kind == "sweep" and "Zone Sweep" or "Quest"
        return prefix .. "Auto Route · " .. kind .. (route.locked and " · Locked" or "") .. " · " .. (route.waiting
            and (active and active.item and active.item.availableStart
                and "Waiting for Accepted Quest Objective"
                or route.kind == "closest" and "Waiting for Nearby Points"
                or "Waiting for Next Quest")
            or active and active.name or "Choosing Next Stop")
    end
    if pausedRoute then return prefix .. "Auto Route paused · " .. (active and active.name or "Waypoint kept") end
    if active then return prefix .. active.name .. "  ·  " .. active.index .. "/" .. #active.steps end
    local settings = addon.GetSettings()
    if settings.vignetteRadarAutoRouteRestore == true
        and settings.vignetteRadarAutoRouteWasActive == true then
        local kind = settings.vignetteRadarAutoRouteLastKind or "Auto"
        return "Resuming " .. kind:sub(1, 1):upper() .. kind:sub(2)
            .. " Route · Waiting for Points"
    end
    return #candidates .. " possible focus points"
end

-- A read-only snapshot for explicit troubleshooting; no quest or map APIs run here.
function API.Diagnostics()
    local current = route or pausedRoute
    local visited = 0
    for _ in pairs(current and current.visited or {}) do visited = visited + 1 end
    return { mode = current and current.kind or "off",
        state = route and (route.waiting and "waiting" or "active")
            or pausedRoute and "paused" or "off",
        questID = active and active.item and active.item.questID,
        radarPoints = #quests, availableStarts = #(addon.VignetteRadarAvailableStarts or {}),
        visited = visited }
end

function API.Advance()
    if not active or active.index >= #active.steps then return false end
    if not SameWaypoint(active.steps[active.index]) then
        Trace("Advance: waypoint changed (%s); dropping focus and route", SameWaypointWhy(active.steps[active.index]))
        StopQuestSuperTrack("Advance: waypoint changed")
        active, route = nil, nil
        ForgetFocus("Advance: waypoint changed outside the radar")
        return false
    end
    local nextStep = active.steps[active.index + 1]
    local ok = Place(nextStep, active.item)
    if ok then
        active.index, active.wasOutside = active.index + 1, false
        RememberFocusStep()
        RouteNote("NEXT STEP", active.name .. " · " .. active.index .. "/" .. #active.steps)
    end
    return ok
end

local function LootLocation()
    local snapshot = player
    local radar = addon.VignetteRadarAPI
    if radar and type(radar.GetPlayerSnapshot) == "function" then
        local ok, current = pcall(radar.GetPlayerSnapshot)
        if ok and type(current) == "table" then snapshot = current end
    end
    if not (snapshot and active and active.item and Number(snapshot.worldX)
        and Number(snapshot.worldY) and Number(active.item.worldX)
        and Number(active.item.worldY)) then return nil end
    if Number(snapshot.instanceID) and Number(active.item.instanceID)
        and snapshot.instanceID ~= active.item.instanceID then return nil end
    return Distance(snapshot.worldX, snapshot.worldY,
        active.item.worldX, active.item.worldY)
end

local function LootSourceMatch(item)
    if type(GetNumLootItems) ~= "function" or type(GetLootSourceInfo) ~= "function" then
        return "unknown"
    end
    local ok, slots = pcall(GetNumLootItems)
    if not ok or not Number(slots) then return "unknown" end
    local gameObject, creature, exact = false, false, false
    for slot = 1, math.min(slots, 32) do
        local read, guid = pcall(GetLootSourceInfo, slot)
        if read and type(guid) == "string"
            and not (issecretvalue and issecretvalue(guid)) then
            if guid:find("^GameObject%-") then
                gameObject = true
                local objectID = tonumber(guid:match(
                    "^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
                if (item.objectGUID and guid == item.objectGUID)
                    or (Number(item.objectID) and objectID == item.objectID) then
                    exact = true
                end
            elseif guid:find("^Creature%-") or guid:find("^Vehicle%-") then
                creature = true
            end
        end
    end
    if exact then return "exact" end
    if gameObject and (item.objectGUID or Number(item.objectID)) then return "wrong-object" end
    if gameObject then return "gameobject" end
    if creature then return "creature" end
    return "unknown"
end

-- Treasure stops that wait for loot: treasure routes, and any treasure
-- stop held by "Keep Marker Until Looted Or Killed" (not while paused).
local function LootTracked()
    if not (active and active.kind == "treasure" and active.item) then return false end
    if route then return route.kind == "treasure" or KeepUntilDone(active.item) end
    return not pausedRoute and KeepUntilDone(active.item)
end

function API.OnLootEvent(event)
    if event == "LOOT_CLOSED" then lootSession = nil; return false end
    if route and route.locked then return false end
    if event == "LOOT_OPENED" then
        lootSession = nil
        if not (LootTracked()
            and active.steps[active.index]
            and SameWaypoint(active.steps[active.index])) then return false end
        local source = LootSourceMatch(active.item)
        local radius = source == "exact" and 50
            or source == "gameobject" and 18 or source == "unknown" and 8 or 0
        local distance = LootLocation()
        if radius <= 0 or not (distance and distance <= radius) then return false end
        lootSession = { key = active.key, at = type(GetTime) == "function" and GetTime() or 0,
            radius = radius }
        return false
    end
    if event ~= "LOOT_SLOT_CLEARED" or not lootSession then return false end
    local session = lootSession
    lootSession = nil
    if not (LootTracked() and active.key == session.key
        and active.steps[active.index]
        and SameWaypoint(active.steps[active.index])) then return false end
    local now = type(GetTime) == "function" and GetTime() or 0
    local distance = LootLocation()
    if now < session.at or now - session.at > 5
        or not (distance and distance <= session.radius) then return false end
    if addon.VignetteRadarRecent and addon.VignetteRadarRecent.HideNote then
        addon.VignetteRadarRecent.HideNote(active.item)
    end
    if route then AdvanceRoute(false, "looted")
    else
        RouteNote("LOOTED", active.name)
        active = nil
        ForgetFocus("looted")
    end
    return true
end
-- Loot arrives after TreasureLearning (TOC order); an advanced treasure
-- route redraws the radar without a rescan.
if addon.Bus then
    addon.Bus.On("LOOT", function(event)
        local radar = addon.VignetteRadarAPI
        if API.OnLootEvent(event) and radar and radar.Refresh then radar.Refresh(false) end
    end)
end

local function ZygorPoint(source, step)
    if type(source) ~= "table" then return nil end
    local pointMapID = Number(source.map) or Number(source.m) or Number(step and step.map)
    local x, y = Number(source.x), Number(source.y)
    if not (pointMapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return nil
    end
    return { m = pointMapID, x = x, y = y, title = source.title or source.text }
end

local function ZygorGoalPoint(goal, step, directPin)
    if not goal or goal.force_noway or goal.action == "mapmarker" then return nil end
    local point
    if directPin and type(goal.GetWaypoint) == "function" then
        local ok, native = pcall(goal.GetWaypoint, goal)
        if ok then point = ZygorPoint(native, step) end
    end
    point = point or ZygorPoint(goal, step)
    if not point then return nil end
    if type(goal.IsVisible) == "function" then
        local ok, visible = pcall(goal.IsVisible, goal)
        if not ok or visible == false or (issecretvalue and issecretvalue(visible)) then
            return nil
        end
    end
    if directPin and type(goal.GetText) == "function" then
        local ok, title = pcall(goal.GetText, goal, false, true, false, true)
        if ok and type(title) == "string" and title ~= "" then point.title = title end
    end
    return point
end

local function ZygorGoalComplete(goal)
    if not goal then return false end
    if type(goal.IsComplete) == "function" then
        local ok, done = pcall(goal.IsComplete, goal)
        if ok and type(done) == "boolean" then return done end
    end
    return goal.status == "complete"
end

local function ZygorTravelPoint(step, mapToWorld, mapVector)
    local coords = step and step.waypath and step.waypath.coords
    if type(coords) ~= "table" then return nil end
    local nearest, nearestDistance, count
    count = math.min(#coords, 64)
    for index = 1, count do
        local point = ZygorPoint(coords[index], step)
        if point then
            if not nearest then nearest = index end
            if player and Number(player.worldX) and Number(player.worldY) then
                local ok, x, y, instanceID = pcall(mapToWorld, point.m,
                    mapVector(point.x, point.y))
                if ok and Number(x) and Number(y)
                    and (not Number(instanceID) or not Number(player.instanceID)
                        or instanceID == player.instanceID) then
                    local distance = (x - player.worldX)^2 + (y - player.worldY)^2
                    if not nearestDistance or distance < nearestDistance then
                        nearest, nearestDistance = index, distance
                    end
                end
            end
        end
    end
    if not nearest then return nil end
    if nearestDistance and nearestDistance <= 20^2 then
        for index = nearest + 1, count do
            local nextPoint = ZygorPoint(coords[index], step)
            if nextPoint then return nextPoint, index, count end
        end
    end
    return ZygorPoint(coords[nearest], step), nearest, count
end

function API.ZygorNote(mapID, mapToWorld, mapVector, allowHidden, allowRemote, mode, goalIndex)
    if not allowHidden and addon.GetSettings().vignetteRadarWorldFocusZygor ~= true then return nil end
    local zgv = _G.ZygorGuidesViewer
    if not zgv then return nil, "Zygor is not loaded" end
    local read, step, pointer = pcall(function() return zgv.CurrentStep, zgv.Pointer end)
    if not read or not step then return nil, "Zygor has no active guide step" end

    -- Zygor's arrow can point at a travel hop or a manual POI. Read the
    -- selected objective from the active guide step instead.
    local selected, waypoint
    local goals = type(step.goals) == "table" and step.goals or nil
    if goals and mode ~= "travel" then
        local anyIncomplete = false
        local goalNum = Number(goalIndex) or Number(step.current_waypoint_goal_num)
        if goalNum and goalNum >= 1 and goalNum <= 64 then
            selected = goals[goalNum]
            if goalIndex or not ZygorGoalComplete(selected) then
                waypoint = ZygorGoalPoint(selected, step, allowRemote)
            end
        end
        if goalIndex and not waypoint then return nil, "That Zygor objective has no mapped location" end
        if not waypoint then
            for index = 1, math.min(#goals, 64) do
                local goal = goals[index]
                if goal and not ZygorGoalComplete(goal) then
                    anyIncomplete = true
                    waypoint = ZygorGoalPoint(goal, step, allowRemote)
                    if waypoint then selected = goal; break end
                end
            end
        end
        if not waypoint and not goalIndex and #goals > 0 and not anyIncomplete then
            for index = 1, math.min(#goals, 64) do
                if goals[index] and not ZygorGoalComplete(goals[index]) then
                    anyIncomplete = true
                    break
                end
            end
            if not anyIncomplete then
                return nil, "Waiting for Zygor's next guide step"
            end
        end
    end
    local travelIndex, travelCount
    if not waypoint or mode == "travel" then
        waypoint, travelIndex, travelCount = ZygorTravelPoint(step, mapToWorld, mapVector)
    end
    if mode == "travel" and not waypoint then
        return nil, "Current Zygor step has no mapped travel stop"
    end
    if not waypoint and pointer then
        local possible = { pointer.DestinationWaypoint, pointer.current_waypoint,
            pointer.ArrowFrame and pointer.ArrowFrame.waypoint }
        for index = 1, 3 do
            local candidate = possible[index]
            if candidate and candidate.goal and candidate.goal.parentStep == step then
                waypoint = ZygorPoint(candidate, step)
                if waypoint then selected = candidate.goal; break end
            end
        end
    end
    if not waypoint then return nil, "Current Zygor step has no mapped location" end
    if not allowRemote and waypoint.m ~= mapID then return nil end
    local converted, worldX, worldY, instanceID = pcall(mapToWorld, waypoint.m,
        mapVector(waypoint.x, waypoint.y))
    if not converted or not Number(worldX) or not Number(worldY) then
        if not allowRemote then return nil end
        worldX, worldY, instanceID = nil, nil, nil
    end
    local stepNum = Number(step.num)
    local title = waypoint.title
    if mode == "travel" then
        title = "Travel Stop " .. tostring(travelIndex or 1) .. "/" .. tostring(travelCount or 1)
    end
    if type(title) ~= "string" or title == "" then
        title = "Zygor Step " .. tostring(stepNum or "?")
    end
    return { key = "zygor:" .. tostring(stepNum or 0) .. ":" .. waypoint.m
        .. ":" .. math.floor(waypoint.x * 10000) .. ":" .. math.floor(waypoint.y * 10000),
        kind = "guide", source = "Zygor", name = title, mapID = waypoint.m,
        mapX = waypoint.x, mapY = waypoint.y, worldX = worldX, worldY = worldY,
        instanceID = instanceID, stepNumber = stepNum,
        travelIndex = travelIndex, travelCount = travelCount,
        goalNumber = selected and (Number(selected.num) or Number(goalIndex)
            or Number(step.current_waypoint_goal_num)) or nil,
        goalCount = goals and #goals or 0,
        note = selected and "Selected Zygor guide objective"
            or "Current Zygor guide path" }
end

-- ROUTE_CHANGED (Bus topic): the focused stop, its path step or the route's
-- state (kind, paused, waiting, locked) changed. The Guide Panel listens
-- instead of polling. Every public entry point that can change them, and
-- Sync, checks after it returns; a call that changed nothing fires nothing.
local routeSeen = {}
local function NotifyRoute()
    local current = route or pausedRoute
    local item, index = active and active.item, active and active.index
    local kind, paused = current and current.kind, pausedRoute ~= nil
    local waiting, locked = current and current.waiting == true, current and current.locked == true
    if routeSeen.item == item and routeSeen.index == index and routeSeen.kind == kind
        and routeSeen.paused == paused and routeSeen.waiting == waiting and routeSeen.locked == locked then
        return
    end
    routeSeen.item, routeSeen.index, routeSeen.kind = item, index, kind
    routeSeen.paused, routeSeen.waiting, routeSeen.locked = paused, waiting, locked
    local bus = addon.Bus
    if bus and bus.Emit then bus.Emit("ROUTE_CHANGED") end
end

local function Notified(...)
    NotifyRoute()
    return ...
end

for _, name in ipairs({ "ToggleRoute", "ToggleRouteLock", "StopRoute", "Clear", "StartNearest", "StartSweep",
    "SkipRouteStop", "JumpRouteStop", "SkipQuest", "PreviousQuestStep", "NextQuestStep",
    "SelectTarget", "SelectQuest", "SelectNote", "SelectPoint", "LoadZygorGuide", "Sync",
    "Cycle", "Advance", "OnLootEvent" }) do
    local original = API[name]
    if type(original) == "function" then
        API[name] = function(...) return Notified(original(...)) end
    end
end
