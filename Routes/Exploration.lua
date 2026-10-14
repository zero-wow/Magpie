local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarExploration = API
local trail, trailMap, lastTrailAt = {}, nil, 0
local seen, seenMap = {}, nil
local approachInside, approachMap = {}, nil
local manualUntil, autoRange = 0, nil
local focusedQuestMisses = 0
local MAX_PINS, MAX_ROUTE, MAX_JOURNAL, MAX_TRAIL = 60, 8, 100, 150
local MAX_CUSTOM_PRESETS = 8
local MAX_ROUTE_HISTORY = 20
local routeBack, routeHistory = {}, {}
local routeArrivalKey, routeArrivalOutside
local walkRecording, walkMessage
local MAX_WALK_POINTS, MAX_WALK_PATHS = 512, 8

local function Settings() return addon.GetSettings() end
local Number, Safe = addon.Secret.Number, addon.Secret.Safe
-- Keeps "" (unlike Secret.Text) and cuts long names to 80 bytes.
local function Text(value)
    return type(value) == "string" and Safe(value) and value:sub(1, 80) or nil
end
local function Now() return GetTime and GetTime() or 0 end
local function Time() return time and time() or 0 end
local function Tell(value)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("Magpie: " .. value)
    end
end
local function Refresh()
    if addon.VignetteRadarAPI and addon.VignetteRadarAPI.Refresh then addon.VignetteRadarAPI.Refresh(false) end
    if API.RefreshPanel then API.RefreshPanel() end
end

function API.ManualZoom()
    manualUntil = Now() + 30
    autoRange = nil
end

function API.Range(player, focused)
    local db = Settings()
    local base = db.vignetteRadarRange
    if db.vignetteRadarSmartZoom ~= true or not player or Now() < manualUntil then return base end
    local speed = GetUnitSpeed and Number(GetUnitSpeed("player")) or 0
    local desired = speed and speed > 4 and math.max(1200, base) or base
    if focused and not focused.stale and Number(focused.distance) and focused.distance > 0 then
        desired = math.max(addon.VignetteRadarRanges[1], focused.distance * 1.25)
    end
    local ranges = addon.VignetteRadarRanges
    autoRange = ranges[#ranges]
    for _, range in ipairs(ranges) do
        if range >= desired then autoRange = range; break end
    end
    return autoRange
end

-- The focused quest is the shared Focus selection when it is a quest.
-- Clicking the focused quest again clears it, and its waypoint with it.
function API.FocusQuest(questID, point)
    local focus = addon.VignetteRadarFocus
    questID = Number(questID)
    focusedQuestMisses = 0
    if questID then focus.Toggle(focus.Quest(questID, point), { source = "quest" })
    else focus.Clear({ type = "quest", source = "quest" }) end
    Refresh()
end
function API.GetFocusedQuest() return addon.VignetteRadarFocus.GetQuest() end
-- Restores a focus without moving the waypoint.
function API.SetQuestFocus(questID)
    local focus = addon.VignetteRadarFocus
    questID = Number(questID)
    focusedQuestMisses = 0
    if questID then focus.Select(focus.Quest(questID), { project = false, source = "quest" })
    else focus.Clear({ type = "quest", project = false, source = "quest" }) end
end
function API.ValidateQuestFocus(quests, changedMap)
    local focus = addon.VignetteRadarFocus
    local focusedQuestID = focus.GetQuest()
    local drop = { type = "quest", project = false, source = "validate" }
    if changedMap then focusedQuestMisses = 0; focus.Clear(drop); return end
    if not focusedQuestID then return end
    for _, quest in ipairs(quests or {}) do
        if quest.questID == focusedQuestID then focusedQuestMisses = 0; return end
    end
    focusedQuestMisses = focusedQuestMisses + 1
    if focusedQuestMisses >= 3 then focusedQuestMisses = 0; focus.Clear(drop) end
end

function API.ObjectiveProgress(questID)
    if not (C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function") then return nil end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" or (issecretvalue and issecretvalue(objectives)) then return nil end
    local completed, total = 0, 0
    for index = 1, math.min(#objectives, 30) do
        local objective = objectives[index]
        if type(objective) == "table" and not (issecretvalue and issecretvalue(objective)) then
            total = total + 1
            local finished = objective.finished
            if not (issecretvalue and issecretvalue(finished)) and finished == true then completed = completed + 1 end
        end
    end
    return total > 0 and (completed .. "/" .. total .. " objectives") or nil
end

function API.ObjectiveLines(questID)
    local lines = {}
    if not (C_QuestLog and type(C_QuestLog.GetQuestObjectives) == "function") then return lines end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" or (issecretvalue and issecretvalue(objectives)) then
        return lines
    end
    for index = 1, math.min(#objectives, 30) do
        local objective = objectives[index]
        if type(objective) == "table" and not (issecretvalue and issecretvalue(objective)) then
            local read, finished, label = pcall(function()
                return objective.finished, objective.text
            end)
            if read and not (issecretvalue and (issecretvalue(finished) or issecretvalue(label)))
                and finished ~= true and type(label) == "string" and label ~= "" then
                lines[#lines + 1] = label
                if #lines >= 5 then break end
            end
        end
    end
    return lines
end

function API.UpdateTrail(player, mapID, now)
    if trailMap ~= mapID then trail, trailMap, lastTrailAt = {}, mapID, 0 end
    now = Number(now) or Now()
    if walkRecording and player then
        local x, y = Number(player.worldX), Number(player.worldY)
        if walkRecording.mapID ~= mapID
            or (walkRecording.instanceID and Number(player.instanceID)
                and walkRecording.instanceID ~= Number(player.instanceID)) then
            walkMessage = "Map changed. Save or discard the recorded path."
            walkRecording.active = false
        elseif walkRecording.active and x and y and now - walkRecording.lastAt >= 2 then
            local points = walkRecording.points
            local last = points[#points]
            local distance = math.sqrt((x - last.worldX)^2 + (y - last.worldY)^2)
            if distance > 120 then
                walkMessage = "Travel jump detected. Save or discard the recorded path."
                walkRecording.active = false
            elseif distance >= 4 then
                if #points >= MAX_WALK_POINTS then
                    walkMessage = "Recording limit reached. Save or discard the path."
                    walkRecording.active = false
                else
                    points[#points + 1] = { worldX=x, worldY=y,
                        mapX=Number(player.mapX), mapY=Number(player.mapY) }
                    walkRecording.lastAt = now
                    walkRecording.distance = walkRecording.distance + distance
                end
            end
        end
    end
    if Settings().vignetteRadarBreadcrumbs ~= true or not player then return trail end
    local lifetime = Settings().vignetteRadarTrailLifetime or 180
    local interval = lifetime <= 5 and .25 or 1
    local minDistance = lifetime <= 5 and .5 or 2.5
    while #trail > 0 and now - trail[1].at > lifetime do table.remove(trail, 1) end
    local x, y = Number(player.worldX), Number(player.worldY)
    if not x or not y then return trail end
    local last = trail[#trail]
    if last and last.instanceID and player.instanceID ~= last.instanceID then
        trail, last, lastTrailAt = {}, nil, 0
    end
    if not last then
        -- The first sample is the path's anchor, not a phantom line from the
        -- player dot to whichever position happens to be sampled later.
        trail[1] = { x=x, y=y, at=now, instanceID=player.instanceID, arc=0 }
        lastTrailAt = now
        return trail
    end
    local distance = math.sqrt((x-last.x)^2 + (y-last.y)^2)
    if now-lastTrailAt >= interval and distance >= minDistance then
        local gap = now-last.at > 12 or distance > 120
        trail[#trail+1] = { x=x, y=y, at=now, instanceID=player.instanceID,
            arc=gap and 0 or (last.arc or 0) + distance, breakBefore=gap }
        if #trail > MAX_TRAIL then table.remove(trail, 1) end
        lastTrailAt = now
    end
    return trail
end
function API.GetTrail() return trail, trailMap end

local function CopyList(list)
    local copy = {}
    for index, value in ipairs(list) do copy[index] = value end
    return copy
end
local function RememberRouteEdit()
    local db = Settings()
    routeHistory[#routeHistory+1] = {
        route=CopyList(db.vignetteRadarRoute),
        pins=CopyList(db.vignetteRadarPins),
        back=CopyList(routeBack),
    }
    if #routeHistory > MAX_ROUTE_HISTORY then table.remove(routeHistory, 1) end
end
function API.AddPin(player, name)
    if not player then return false, "Position unavailable" end
    local x, y = Number(player.worldX), Number(player.worldY)
    local mapID, mapX, mapY = Number(player.mapID), Number(player.mapX), Number(player.mapY)
    if not (x and y and mapID and mapX and mapY) then return false, "Position unavailable" end
    local pins = Settings().vignetteRadarPins
    local pinName = Text(name)
    if not pinName or pinName == "" then pinName = "My pin" end
    local pin = { id=Time() .. "-" .. tostring(math.random(100000)), name=pinName,
        mapID=mapID, mapX=mapX, mapY=mapY, worldX=x, worldY=y,
        instanceID=Number(player.instanceID), at=Time() }
    RememberRouteEdit()
    pins[#pins+1] = pin
    if #pins > MAX_PINS then table.remove(pins, 1) end
    Refresh()
    return true, pin
end
function API.GetPins(mapID)
    local result = {}
    for _, pin in ipairs(Settings().vignetteRadarPins) do
        if type(pin) == "table" and pin.mapID == mapID and Number(pin.worldX) and Number(pin.worldY) then
            result[#result+1] = pin
        end
    end
    return result
end
function API.RemovePin(id)
    local pins = Settings().vignetteRadarPins
    local route = Settings().vignetteRadarRoute
    local found = false
    for _, pin in ipairs(pins) do
        if type(pin) == "table" and pin.id == id then found = true; break end
    end
    if not found then return end
    RememberRouteEdit()
    for index=#pins,1,-1 do
        if type(pins[index]) == "table" and pins[index].id == id then table.remove(pins,index) end
    end
    for index=#route,1,-1 do
        if type(route[index]) == "table" and route[index].pinID == id then table.remove(route,index) end
    end
    for index=#routeBack,1,-1 do
        if type(routeBack[index]) == "table" and routeBack[index].pinID == id then
            table.remove(routeBack,index)
        end
    end
    Refresh()
end

local function RouteEntry(item)
    if type(item) ~= "table" then return nil end
    local x, y, mapID = Number(item.worldX), Number(item.worldY), Number(item.mapID)
    if not x or not y or not mapID then return nil end
    return { name=Text(item.name) or "Stop", worldX=x, worldY=y,
        mapID=mapID, mapX=Number(item.mapX), mapY=Number(item.mapY),
        instanceID=Number(item.instanceID), pinID=Text(item.id) }
end
function API.AddRouteStop(item)
    local route = Settings().vignetteRadarRoute
    if #route >= MAX_ROUTE then return false, "Route is full (8 stops)" end
    local entry = RouteEntry(item)
    if not entry then return false, "This stop has no position" end
    RememberRouteEdit()
    route[#route+1] = entry
    Refresh()
    return true
end
function API.ApplyRouteDraft(stops)
    if type(stops) ~= "table" or #stops == 0 or #stops > 5 then
        return false, "Draft has no valid stops"
    end
    local route = {}
    for _, stop in ipairs(stops) do
        local entry = RouteEntry(stop)
        if not entry then return false, "A draft stop has no position" end
        route[#route + 1] = entry
    end
    RememberRouteEdit()
    Settings().vignetteRadarRoute = route
    routeBack = {}
    Refresh()
    return true
end
function API.GetRoute(mapID)
    local result = {}
    for _, stop in ipairs(Settings().vignetteRadarRoute) do
        if type(stop) == "table" and stop.mapID == mapID and Number(stop.worldX) and Number(stop.worldY) then
            result[#result+1] = stop
        end
    end
    return result
end
function API.PopRouteStop()
    local route = Settings().vignetteRadarRoute
    if #route == 0 then return false end
    RememberRouteEdit()
    routeBack[#routeBack+1] = table.remove(route, 1)
    if #routeBack > MAX_ROUTE_HISTORY then table.remove(routeBack, 1) end
    Refresh()
    return true
end
function API.CheckRouteArrival(player, mapID)
    local db = Settings()
    if db.vignetteRadarRouteAutoAdvance ~= true or not player then
        routeArrivalKey, routeArrivalOutside = nil, nil
        return false
    end
    local stop = db.vignetteRadarRoute[1]
    local px, py = Number(player.worldX), Number(player.worldY)
    local sx, sy = stop and Number(stop.worldX), stop and Number(stop.worldY)
    if not (px and py and sx and sy and stop.mapID == mapID)
        or (stop.instanceID and player.instanceID and stop.instanceID ~= player.instanceID) then
        routeArrivalKey, routeArrivalOutside = nil, nil
        return false
    end
    if routeArrivalKey ~= stop then routeArrivalKey, routeArrivalOutside = stop, false end
    local distance = math.sqrt((px - sx)^2 + (py - sy)^2)
    local radius = db.vignetteRadarRouteArrivalRadius
    if distance > radius + 5 then routeArrivalOutside = true end
    if not routeArrivalOutside or distance > radius then return false end
    RememberRouteEdit()
    routeBack[#routeBack + 1] = table.remove(db.vignetteRadarRoute, 1)
    if #routeBack > MAX_ROUTE_HISTORY then table.remove(routeBack, 1) end
    routeArrivalKey, routeArrivalOutside = nil, nil
    Tell("Reached " .. (stop.name or "route stop") .. ". Next stop is ready; Back restores it.")
    if API.RefreshPanel then API.RefreshPanel() end
    return true
end
function API.BackRouteStop()
    local route = Settings().vignetteRadarRoute
    if #routeBack == 0 or #route >= MAX_ROUTE then return false end
    RememberRouteEdit()
    table.insert(route, 1, table.remove(routeBack))
    Refresh()
    return true
end
function API.UndoRouteEdit()
    local previous = table.remove(routeHistory)
    if not previous then return false end
    local db = Settings()
    db.vignetteRadarRoute = previous.route
    db.vignetteRadarPins = previous.pins
    routeBack = previous.back
    Refresh()
    return true
end
function API.ClearRoute()
    if #Settings().vignetteRadarRoute == 0 and #routeBack == 0 then return false end
    RememberRouteEdit()
    Settings().vignetteRadarRoute = {}
    routeBack = {}
    Refresh()
    return true
end

-- Walk recordings are sampled only while explicitly recording. The saved
-- form is an eight-stop route, so neither long sessions nor replays add a
-- per-frame cost to the radar.
local function WalkPaths()
    local db = Settings()
    if type(db.vignetteRadarWalkPaths) ~= "table" then db.vignetteRadarWalkPaths = {} end
    return db.vignetteRadarWalkPaths
end
-- A fixed two-second bus ticker; the Update Rate setting must not thin a walk.
local function StopWalkTicker()
    if addon.Bus then addon.Bus.Cancel("walk") end
end
local function StartWalkTicker()
    if not addon.Bus then return end
    addon.Bus.Every("walk", 2, function()
        if not walkRecording or not walkRecording.active then StopWalkTicker(); return end
        local radar = addon.VignetteRadarAPI
        local player = radar and radar.GetPlayerSnapshot and radar.GetPlayerSnapshot()
        if player and Number(player.mapID) then
            API.UpdateTrail(player, player.mapID, Now())
            if API.RefreshWalkRecordingStatus then API.RefreshWalkRecordingStatus() end
        end
    end, { scale = false })
end
local function WalkPoint(player)
    local x, y = player and Number(player.worldX), player and Number(player.worldY)
    if not x or not y then return nil end
    return { worldX=x, worldY=y, mapX=Number(player.mapX), mapY=Number(player.mapY) }
end
function API.StartWalkRecording(player)
    if walkRecording then return false, "Save or discard the current walk first" end
    local point = WalkPoint(player)
    local mapID = player and Number(player.mapID)
    if not point or not mapID then return false, "Current position unavailable" end
    walkRecording = { active=true, mapID=mapID,
        instanceID=Number(player.instanceID), points={point},
        lastAt=Now(), distance=0 }
    walkMessage = "Recording your walk"
    StartWalkTicker()
    if API.RefreshPanel then API.RefreshPanel() end
    return true
end
function API.CancelWalkRecording()
    if not walkRecording then return false end
    walkRecording, walkMessage = nil, nil
    StopWalkTicker()
    if API.RefreshPanel then API.RefreshPanel() end
    return true
end
function API.GetWalkRecording()
    return walkRecording and { active=walkRecording.active,
        points=#walkRecording.points, distance=walkRecording.distance,
        mapID=walkRecording.mapID, message=walkMessage } or nil
end
local function SegmentError(point, first, last)
    local dx, dy = last.worldX-first.worldX, last.worldY-first.worldY
    local lengthSquared = dx*dx + dy*dy
    if lengthSquared < .001 then
        return (point.worldX-first.worldX)^2 + (point.worldY-first.worldY)^2
    end
    local t = math.max(0, math.min(1,
        ((point.worldX-first.worldX)*dx + (point.worldY-first.worldY)*dy)/lengthSquared))
    local ox, oy = point.worldX-first.worldX-t*dx, point.worldY-first.worldY-t*dy
    return ox*ox + oy*oy
end
local function SimplifyWalk(points)
    local selected = { 1, #points }
    while #selected < math.min(MAX_ROUTE, #points) do
        local bestIndex, bestError
        for segment=1,#selected-1 do
            local first, last = selected[segment], selected[segment+1]
            for index=first+1,last-1 do
                local errorSquared = SegmentError(points[index], points[first], points[last])
                if not bestError or errorSquared > bestError then
                    bestIndex, bestError = index, errorSquared
                end
            end
        end
        if not bestIndex or bestError < 16 then break end
        selected[#selected+1] = bestIndex
        table.sort(selected)
    end
    local result = {}
    for _, index in ipairs(selected) do result[#result+1] = points[index] end
    return result
end
function API.SaveWalkRecording(name, player)
    if not walkRecording then return false, "Start a recording first" end
    local recording = walkRecording
    local final = WalkPoint(player)
    if recording.active and final and Number(player.mapID) == recording.mapID
        and (not recording.instanceID or not Number(player.instanceID)
            or recording.instanceID == Number(player.instanceID)) then
        local last = recording.points[#recording.points]
        local distance = math.sqrt((final.worldX-last.worldX)^2 + (final.worldY-last.worldY)^2)
        if distance > 1 and distance <= 120 and #recording.points < MAX_WALK_POINTS then
            recording.points[#recording.points+1] = final
            recording.distance = recording.distance + distance
        end
    end
    if #recording.points < 2 or recording.distance < 10 then
        return false, "Walk at least 10 yd before saving"
    end
    local paths = WalkPaths()
    local label = Text(name)
    if not label or label:match("^%s*$") then
        label = "Walk " .. (#paths + 1)
    else
        label = label:match("^%s*(.-)%s*$")
    end
    local path = { id=tostring(Time()) .. "-" .. tostring(math.random(100000)),
        name=label, mapID=recording.mapID, instanceID=recording.instanceID,
        distance=math.floor(recording.distance+.5), points=SimplifyWalk(recording.points), at=Time() }
    paths[#paths+1] = path
    if #paths > MAX_WALK_PATHS then table.remove(paths, 1) end
    walkRecording, walkMessage = nil, nil
    StopWalkTicker()
    if API.RefreshPanel then API.RefreshPanel() end
    return true, path
end
function API.GetWalkPaths() return WalkPaths() end
function API.PauseWalkRecording()
    if not walkRecording or not walkRecording.active then return false end
    walkRecording.active = false
    walkMessage = "Recording paused. Save, resume, or discard."
    StopWalkTicker()
    if API.RefreshPanel then API.RefreshPanel() end
    return true
end
function API.ResumeWalkRecording(player)
    if not walkRecording or walkRecording.active then return false, "No paused walk" end
    if not player or Number(player.mapID) ~= walkRecording.mapID
        or (walkRecording.instanceID and Number(player.instanceID)
            and Number(player.instanceID) ~= walkRecording.instanceID) then
        return false, "Return to the recorded map first"
    end
    local point = WalkPoint(player)
    if not point then return false, "Current position unavailable" end
    local last = walkRecording.points[#walkRecording.points]
    local distance = math.sqrt((point.worldX-last.worldX)^2 + (point.worldY-last.worldY)^2)
    if distance > 120 then return false, "Too far from the last recorded point" end
    walkRecording.active = true
    walkRecording.lastAt = Now()
    walkMessage = "Recording your walk"
    StartWalkTicker()
    if API.RefreshPanel then API.RefreshPanel() end
    return true
end
function API.DeleteWalkPath(id)
    local paths = WalkPaths()
    for index=#paths,1,-1 do
        if paths[index].id == id then
            table.remove(paths, index)
            if API.RefreshPanel then API.RefreshPanel() end
            return true
        end
    end
    return false
end
function API.ReplayWalkPath(id, player)
    local found
    for _, path in ipairs(WalkPaths()) do if path.id == id then found = path; break end end
    if not found or type(found.points) ~= "table" or #found.points < 2
        or #found.points > MAX_ROUTE or not Number(found.mapID) then
        return false, "Saved walk unavailable"
    end
    for _, point in ipairs(found.points) do
        if type(point) ~= "table" or not Number(point.worldX) or not Number(point.worldY) then
            return false, "Saved walk has an invalid point"
        end
    end
    local instanceID = Number(found.instanceID)
    if not player or Number(player.mapID) ~= found.mapID
        or (instanceID and Number(player.instanceID)
            and instanceID ~= Number(player.instanceID)) then
        return false, "Go to the recorded map to replay this walk"
    end
    local px, py = Number(player.worldX), Number(player.worldY)
    if not px or not py then return false, "Current position unavailable" end
    local first, last = found.points[1], found.points[#found.points]
    local firstDistance = (px-first.worldX)^2 + (py-first.worldY)^2
    local lastDistance = (px-last.worldX)^2 + (py-last.worldY)^2
    local backwards = lastDistance < firstDistance
    local route = {}
    for step=1,#found.points do
        local point = found.points[backwards and (#found.points-step+1) or step]
        local distance = math.sqrt((px-point.worldX)^2 + (py-point.worldY)^2)
        -- Starting on the first point would leave an arrival-gated route
        -- waiting for the player to walk away and come back.
        if step > 1 or distance > (Number(Settings().vignetteRadarRouteArrivalRadius) or 10) + 3 then
            local entry = RouteEntry({ name=(Text(found.name) or "Walk") .. " " .. step .. "/" .. #found.points,
                mapID=found.mapID, worldX=point.worldX, worldY=point.worldY,
                mapX=point.mapX, mapY=point.mapY, instanceID=instanceID })
            if entry then route[#route+1] = entry end
        end
    end
    if #route == 0 then return false, "No walk stops to replay" end
    RememberRouteEdit()
    Settings().vignetteRadarRoute = route
    routeBack = {}
    Refresh()
    return true, #route
end

-- The one saved-watch key, shared by Watch, IsWatched and CheckApproach.
local function WatchKey(target)
    if type(target) ~= "table" then return nil end
    local identity = Number(target.vignetteID) or Text(target.key)
    return identity and tostring(identity) or nil
end
function API.Watch(target)
    if not target or target.sample or target.stale then return false end
    local key = WatchKey(target)
    if not key then return false end
    local watched = Settings().vignetteRadarWatched
    if type(watched) ~= "table" then watched = {}; Settings().vignetteRadarWatched = watched end
    watched[key] = not watched[key] and true or nil
    Tell(watched[key] and ("Watching " .. (target.name or "detection")) or "Watch removed")
    return watched[key] == true
end
function API.IsWatched(target)
    local watched = Settings().vignetteRadarWatched
    local key = WatchKey(target)
    return key ~= nil and type(watched) == "table" and watched[key] == true
end
function API.CheckApproach(targets, player, mapID)
    if approachMap ~= mapID then approachInside, approachMap = {}, mapID end
    local db = Settings()
    if db.vignetteRadarApproachAlerts ~= true or not player then return nil end
    local px, py = Number(player.worldX), Number(player.worldY)
    local watched = db.vignetteRadarWatched
    if not (px and py) or type(watched) ~= "table" then return nil end
    local threshold = Number(db.vignetteRadarApproachDistance) or 100
    local candidate
    for _, target in ipairs(targets) do
        local tx, ty = Number(target.worldX), Number(target.worldY)
        local key = not target.stale and tx and ty and WatchKey(target)
        if key and watched[key] == true
            and (not player.instanceID or not target.instanceID or player.instanceID == target.instanceID) then
            local dx, dy = tx - px, ty - py
            local within = dx*dx+dy*dy <= threshold*threshold
            if within and approachInside[target.key] == false then candidate = target end
            approachInside[target.key] = within
        end
    end
    return candidate
end

function API.RecordSightings(targets, mapID)
    if seenMap ~= mapID then seen, seenMap = {}, mapID end
    if Settings().vignetteRadarJournalEnabled ~= true then return end
    local journal = Settings().vignetteRadarJournal
    for _, target in ipairs(targets) do
        if not target.stale and not seen[target.key] and Number(target.mapX) and Number(target.mapY) then
            seen[target.key] = true
            table.insert(journal, 1, { name=Text(target.name) or "Detection", category=Text(target.category),
                mapID=mapID, mapX=target.mapX, mapY=target.mapY, at=Time() })
            if #journal > MAX_JOURNAL then table.remove(journal) end
        end
    end
end
function API.ClearJournal() Settings().vignetteRadarJournal = {}; Refresh() end

local presetKeys = { "vignetteRadarRange", "vignetteRadarLayout", "vignetteRadarTheme",
    "vignetteRadarQuestDots", "vignetteRadarQuestAreas", "vignetteRadarNorthUp",
    "vignetteRadarShapes", "vignetteRadarBreadcrumbs", "vignetteRadarScale",
    "vignetteRadarMarkerSize", "vignetteRadarRingOpacity", "vignetteRadarChevronOpacity",
    "vignetteRadarHeadingOpacity", "vignetteRadarChevronDistance",
    "vignetteRadarHeadingLength", "vignetteRadarFullSweep" }
local builtin = {
    Treasure={ vignetteRadarRange=1200, vignetteRadarLayout="compact", vignetteRadarQuestDots=false,
        vignetteRadarQuestAreas=false, categories={ rare=false, treasure=true, event=false, other=false } },
    Rare={ vignetteRadarRange=1200, vignetteRadarLayout="classic", vignetteRadarQuestDots=false,
        vignetteRadarQuestAreas=false, categories={ rare=true, treasure=false, event=false, other=false } },
    Questing={ vignetteRadarRange=450, vignetteRadarLayout="squat", vignetteRadarQuestDots=true,
        vignetteRadarQuestAreas=true, vignetteRadarNorthUp=true,
        categories={ rare=true, treasure=true, event=true, other=true } },
    Exploring={ vignetteRadarRange=2400, vignetteRadarLayout="compact", vignetteRadarBreadcrumbs=true,
        categories={ rare=true, treasure=true, event=true, other=true } },
}
function API.SavePreset(name)
    name = Text(name)
    if not name or name == "" then return false end
    local db, preset = Settings(), {}
    if not db.vignetteRadarCustomPresets[name] then
        local count = 0
        for _ in pairs(db.vignetteRadarCustomPresets) do count = count + 1 end
        if count >= MAX_CUSTOM_PRESETS then return false, "8 named presets maximum" end
    end
    for _, key in ipairs(presetKeys) do preset[key] = db[key] end
    preset.colors = {}
    for slot, color in pairs(db.vignetteRadarColors) do
        if type(color) == "table" then preset.colors[slot] = { color[1], color[2], color[3] } end
    end
    preset.categories = {}
    for _, category in ipairs({ "rare", "treasure", "event", "other" }) do
        preset.categories[category] = db.vignetteRadarCategories[category] ~= false
    end
    db.vignetteRadarCustomPresets[name] = preset
    return true
end
function API.DeletePreset(name)
    Settings().vignetteRadarCustomPresets[name] = nil
    API.RefreshPanel()
end
-- What a preset changes, copied before it applies, so Undo can put it back.
-- Kept in the saved settings, so Undo also works after a /reload.
local function Snapshot(db)
    local copy = { values = {}, colors = nil, categories = {}, full = true }
    for _, key in ipairs(presetKeys) do copy.values[key] = db[key] end
    copy.values.vignetteRadarActivePreset = db.vignetteRadarActivePreset
    if type(db.vignetteRadarColors) == "table" then
        copy.colors = {}
        for slot, color in pairs(db.vignetteRadarColors) do
            if type(color) == "table" then copy.colors[slot] = { color[1], color[2], color[3] } end
        end
    end
    for key, value in pairs(db.vignetteRadarCategories or {}) do copy.categories[key] = value end
    return copy
end

local function Restore(db, copy)
    for key, value in pairs(copy.values or {}) do db[key] = value end
    if copy.full then
        for _, key in ipairs(presetKeys) do
            if copy.values and copy.values[key] == nil then db[key] = nil end
        end
    end
    if type(copy.colors) == "table" then
        db.vignetteRadarColors = {}
        for slot, color in pairs(copy.colors) do db.vignetteRadarColors[slot] = { color[1], color[2], color[3] } end
    end
    if type(copy.categories) == "table" and type(db.vignetteRadarCategories) == "table" then
        for key, value in pairs(copy.categories) do db.vignetteRadarCategories[key] = value end
    end
end

function API.CanUndoPreset()
    return type(Settings().vignetteRadarPresetUndo) == "table"
end

function API.UndoPreset()
    local db = Settings()
    local copy = db.vignetteRadarPresetUndo
    if type(copy) ~= "table" then return false end
    Restore(db, copy)
    db.vignetteRadarPresetUndo = nil
    if addon.InvalidateSettings then addon.InvalidateSettings() end
    API.ManualZoom()
    Refresh()
    return true
end

-- One-time repair (2026-10-10): the Treasure preset was clicked by mistake
-- before Undo existed. These are the settings saved just before it.
local RESTORE_ONCE_ID = "2026-10-10-treasure"
local RESTORE_ONCE = {
    -- Only what the Treasure preset changed; later choices (like a theme) stay.
    values = { vignetteRadarRange = 10, vignetteRadarLayout = "classic",
        vignetteRadarQuestDots = true, vignetteRadarQuestAreas = true },
    categories = { rare = true, treasure = true, event = true, other = true },
}
function API.RestoreOnce()
    local db = Settings()
    if db.vignetteRadarRestoreOnce == RESTORE_ONCE_ID then return false end
    db.vignetteRadarRestoreOnce = RESTORE_ONCE_ID
    Restore(db, RESTORE_ONCE)
    if addon.InvalidateSettings then addon.InvalidateSettings() end
    Refresh()
    return true
end
if addon.Bus and type(addon.Bus.On) == "function" then
    addon.Bus.On("LOGIN", function() pcall(API.RestoreOnce) end)
end

function API.ApplyPreset(name)
    local db = Settings()
    local preset = builtin[name] or db.vignetteRadarCustomPresets[name]
    if type(preset) ~= "table" then return false end
    db.vignetteRadarPresetUndo = Snapshot(db)
    for _, key in ipairs(presetKeys) do if preset[key] ~= nil then db[key] = preset[key] end end
    if type(preset.colors) == "table" then
        db.vignetteRadarColors = {}
        for slot, color in pairs(preset.colors) do
            if type(color) == "table" then db.vignetteRadarColors[slot] = { color[1], color[2], color[3] } end
        end
    end
    if type(preset.categories) == "table" then
        for key, value in pairs(preset.categories) do db.vignetteRadarCategories[key] = value end
    end
    db.vignetteRadarActivePreset = name
    API.ManualZoom()
    Refresh()
    return true
end
function API.PresetNames()
    local names = { "Treasure", "Rare", "Questing", "Exploring" }
    for name in pairs(Settings().vignetteRadarCustomPresets) do names[#names+1] = name end
    return names
end

API.Tell = Tell

local panel, selectedPage = nil, "Modes"
local page = { Pins=1, Journal=1 }
local customPage = 1
local function Label(parent, value, x, y, width, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size or 10, "")
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width or 300)
    label:SetJustifyH("LEFT")
    label:SetTextColor(.78, .85, .84, 1)
    label:SetText(value)
    return label
end
-- Small panel actions draw as atlas icons (UI/IconButton.lua), centered in
-- the slot the text button had; the label becomes the tooltip.
local ICON_ACTIONS = {
    ["×"] = { "close", "Close" }, ["‹"] = { "back", "Previous Page" }, ["›"] = { "next", "Next Page" },
    Back = { "back", "Previous Route Stop" }, Next = { "next", "Next Route Stop" },
    Undo = { "undo", "Undo Route Edit" }, Clear = { "clear", "Clear Route" },
}
local function Button(parent, title, x, y, width, callback)
    local controls = addon.VignetteRadarControls
    local icon = ICON_ACTIONS[title]
    if icon and addon.VignetteRadarIconButton then
        local button = addon.VignetteRadarIconButton.Create(parent, icon[1], { size = 22, label = icon[2] })
        button:SetPoint("TOPLEFT", x + math.floor((width - 22) / 2), y)
        button:SetScript("OnClick", callback)
        return button
    end
    title = controls.TitleCase(title)
    local button = (title == "+" or title == "-" or title == "−")
        and controls.IconButton(parent, title, width, 23) or controls.Button(parent, title, width, 23)
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", callback)
    return button
end
local function Checkbox(parent, key, title, y)
    local box = addon.VignetteRadarControls.Checkbox(parent)
    box:SetPoint("TOPLEFT", 15, y)
    local hit = CreateFrame("Button", nil, parent)
    hit:SetPoint("TOPLEFT", 44, y)
    hit:SetSize(270, 26)
    Label(hit, addon.VignetteRadarControls.TitleCase(title), 0, -6, 250)
    local function Toggle()
        Settings()[key] = not Settings()[key]
        box:SetChecked(Settings()[key] == true)
        Refresh()
    end
    box:SetScript("OnClick", function(self)
        Settings()[key] = self:GetChecked() == true or self:GetChecked() == 1
        Refresh()
    end)
    hit:SetScript("OnClick", Toggle)
    return box
end
local function Input(parent, x, y, width)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 25)
    box:SetPoint("TOPLEFT", x, y)
    box:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    box:SetBackdropColor(.035, .045, .05, .98)
    box:SetBackdropBorderColor(.28, .5, .46, .7)
    addon.VignetteRadarStyle.SetFont(box, 10, "")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end
local function BuildPanel()
    if panel then return panel end
    panel = CreateFrame("Frame", "VignetteRadarExplorePanel", UIParent, "BackdropTemplate")
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarExplorePanel"
    end
    panel:SetSize(330, 425)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    panel:SetBackdropColor(.035, .043, .049, .98)
    panel:SetBackdropBorderColor(.36, .59, .54, .45)
    addon.VignetteRadarControls.PopupSurface(panel)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel.headerLine = panel:CreateTexture(nil, "ARTWORK")
    panel.headerLine:SetPoint("TOPLEFT", 12, -36)
    panel.headerLine:SetPoint("TOPRIGHT", -12, -36)
    panel.headerLine:SetHeight(1)
    panel.title = Label(panel, "EXPLORE", 15, -12, 190, 12)
    Button(panel, "×", 297, -8, 23, function() panel:Hide() end)
    panel.pages, panel.tabs = {}, {}
    for index, name in ipairs({ "Modes", "Tools", "Pins", "Journal", "Route" }) do
        local tab = Button(panel, name, 10+(index-1)*62, -42, 58, function()
            selectedPage = name
            API.RefreshPanel()
        end)
        panel.tabs[name] = tab
        local content = CreateFrame("Frame", nil, panel)
        content:SetSize(310, 346)
        content:SetPoint("TOPLEFT", 10, -73)
        panel.pages[name] = content
    end

    local modes = panel.pages.Modes
    Label(modes, "HUNTING PRESETS", 5, -3, 260, 9):SetTextColor(.05, .82, .62, 1)
    for index, name in ipairs({ "Treasure", "Rare", "Questing", "Exploring" }) do
        local x = 5 + ((index-1)%2)*153
        local y = -25 - math.floor((index-1)/2)*34
        Button(modes, name, x, y, 145, function() API.ApplyPreset(name) end)
    end
    Label(modes, "SAVE OR LOAD YOUR OWN", 5, -104, 260, 9):SetTextColor(.05, .82, .62, 1)
    panel.presetName = Input(modes, 5, -124, 296)
    Button(modes, "Save current", 5, -160, 145, function()
        local name = panel.presetName:GetText()
        local ok, reason = API.SavePreset(name)
        Tell(ok and ("Saved preset " .. name) or (reason or "Enter a preset name"))
        API.RefreshPanel()
    end)
    Button(modes, "Load named", 158, -160, 143, function()
        if not API.ApplyPreset(panel.presetName:GetText()) then Tell("Preset not found") end
    end)
    panel.activePreset = Label(modes, "", 5, -208, 296, 10)
    Label(modes, "Stores range, layout, filters and appearance.", 5, -225, 296, 9)
    Label(modes, "SAVED PRESETS", 5, -246, 290, 9):SetTextColor(.05, .82, .62, 1)
    panel.customRows = {}
    for index=1,4 do
        local button = Button(modes, "", 5+((index-1)%2)*153,
            -264-math.floor((index-1)/2)*29, 145, function(self, mouseButton)
                if not self.presetName then return end
                if mouseButton == "RightButton" then API.DeletePreset(self.presetName)
                else API.ApplyPreset(self.presetName) end
            end)
        if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        panel.customRows[index] = button
    end
    Button(modes, "‹", 5, -322, 39, function() customPage=math.max(1,customPage-1); API.RefreshPanel() end)
    panel.customPageLabel = Label(modes, "", 129, -327, 80, 9)
    Button(modes, "›", 262, -322, 39, function() customPage=customPage+1; API.RefreshPanel() end)

    local tools = panel.pages.Tools
    panel.checks = {
        smart = Checkbox(tools, "vignetteRadarSmartZoom", "Smart zoom (manual zoom pauses 30 sec)", -3),
        untangle = Checkbox(tools, "vignetteRadarUntangle", "Spread crowded markers on hover", -34),
        trail = Checkbox(tools, "vignetteRadarBreadcrumbs", "Show dotted travel trail", -65),
        approach = Checkbox(tools, "vignetteRadarApproachAlerts", "Alert near watched detections", -96),
        journal = Checkbox(tools, "vignetteRadarJournalEnabled", "Keep a sightings journal", -127),
    }
    Label(tools, "APPROACH DISTANCE", 5, -164, 250, 9):SetTextColor(.05, .82, .62, 1)
    panel.approachValue = Label(tools, "", 114, -187, 75, 11)
    Button(tools, "−", 5, -183, 45, function()
        Settings().vignetteRadarApproachDistance = math.max(25, Settings().vignetteRadarApproachDistance - 25)
        API.RefreshPanel()
    end)
    Button(tools, "+", 254, -183, 45, function()
        Settings().vignetteRadarApproachDistance = math.min(600, Settings().vignetteRadarApproachDistance + 25)
        API.RefreshPanel()
    end)
    Label(tools, "DROP A PIN AT YOUR LOCATION", 5, -221, 290, 9):SetTextColor(.05, .82, .62, 1)
    panel.pinName = Input(tools, 5, -241, 190)
    Button(tools, "Add pin", 203, -242, 96, function()
        local player = addon.VignetteRadarAPI and addon.VignetteRadarAPI.GetPlayerSnapshot
            and addon.VignetteRadarAPI.GetPlayerSnapshot()
        local ok, result = API.AddPin(player, panel.pinName:GetText())
        Tell(ok and ("Pinned " .. result.name) or result)
    end)
    Button(tools, "Back", 5, -280, 69, function() API.BackRouteStop() end)
    Button(tools, "Next", 81, -280, 69, function() API.PopRouteStop() end)
    Button(tools, "Undo", 157, -280, 69, function() API.UndoRouteEdit() end)
    Button(tools, "Clear", 233, -280, 69, function() API.ClearRoute() end)
    panel.routeStatus = Label(tools, "", 5, -319, 295, 9)
    Label(tools, "Ctrl-Alt-click a detection to watch it.", 5, -333, 295, 9)

    for _, name in ipairs({ "Pins", "Journal" }) do
        local content = panel.pages[name]
        panel[name .. "Rows"] = {}
        for index=1,9 do
            local row = Button(content, "", 5, -4-(index-1)*30, 296, function(self, button)
                local item = self.item
                if not item then return end
                if name == "Pins" then
                    if button == "RightButton" then API.RemovePin(item.id)
                    else
                        local ok, reason = API.AddRouteStop(item)
                        Tell(ok and ("Added " .. item.name .. " to route") or reason)
                    end
                end
            end)
            if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
            panel[name .. "Rows"][index] = row
        end
        Button(content, "‹", 5, -289, 42, function() page[name] = math.max(1, page[name]-1); API.RefreshPanel() end)
        panel[name .. "Page"] = Label(content, "", 118, -294, 70, 10)
        Button(content, "›", 259, -289, 42, function() page[name] = page[name]+1; API.RefreshPanel() end)
    end
    Label(panel.pages.Pins, "Click: route stop  •  Right-click: delete", 5, -325, 290, 9)
    Button(panel.pages.Journal, "Clear journal", 5, -319, 296, function() API.ClearJournal() end)
    local routePage = panel.pages.Route
    Label(routePage, "DRAFT NEARBY STOPS", 5, -3, 290, 9):SetTextColor(.05, .82, .62, 1)
    panel.draftStopButtons, panel.draftRangeButtons = {}, {}
    for index, value in ipairs({ 3, 4, 5 }) do
        panel.draftStopButtons[index] = Button(routePage, value .. " stops",
            5 + (index - 1) * 101, -23, 95, function()
                Settings().vignetteRadarRouteDraftStops = value
                API.RefreshPanel()
            end)
    end
    for index, value in ipairs({ 300, 600, 1200 }) do
        panel.draftRangeButtons[index] = Button(routePage, value .. " yd",
            5 + (index - 1) * 101, -54, 95, function()
                Settings().vignetteRadarRouteDraftRange = value
                API.RefreshPanel()
            end)
    end
    Button(routePage, "Preview route", 5, -86, 142, function() API.BuildRouteDraft() end)
    Button(routePage, "Apply preview", 159, -86, 142, function()
        local ok, reason = API.ApplyRouteDraft(panel.routeDraft)
        Tell(ok and "Preview route applied" or reason)
        API.RefreshPanel()
    end)
    panel.draftStatus = Label(routePage, "Preview to see nearby stops.", 5, -117, 296, 10)
    panel.draftRows = {}
    for index = 1, 5 do
        panel.draftRows[index] = Label(routePage, "", 5, -144 - (index - 1) * 30, 296, 10)
    end
    -- The walk recorder is an Advanced Tool; RefreshPanel hides its entry.
    panel.walkHint = Label(routePage, "Straight-line yards; walk paths record your actual travel.", 5, -294, 296, 8)
    panel.walkPathsButton = Button(routePage, "Walk Paths", 5, -313, 296, function()
        selectedPage = "Walk"
        API.RefreshPanel()
    end)

    local walkPage = CreateFrame("Frame", nil, panel)
    walkPage:SetSize(310, 346)
    walkPage:SetPoint("TOPLEFT", 10, -73)
    panel.pages.Walk = walkPage
    Button(walkPage, "Back To Route", 5, -3, 94, function()
        selectedPage = "Route"
        API.RefreshPanel()
    end)
    panel.walkRecordButton = Button(walkPage, "Start Recording", 107, -3, 194, function()
        local radar = addon.VignetteRadarAPI
        local player = radar and radar.GetPlayerSnapshot and radar.GetPlayerSnapshot()
        local ok, reason
        if not walkRecording then ok, reason = API.StartWalkRecording(player)
        elseif walkRecording.active then ok, reason = API.PauseWalkRecording()
        else ok, reason = API.ResumeWalkRecording(player) end
        if not ok then Tell(reason) end
        API.RefreshPanel()
    end)
    panel.walkStatus = Label(walkPage, "", 5, -40, 296, 9)
    panel.walkName = Input(walkPage, 5, -62, 195)
    panel.walkName:SetText("My Walk")
    panel.walkSaveButton = Button(walkPage, "Save Walk", 207, -63, 94, function()
        local radar = addon.VignetteRadarAPI
        local player = radar and radar.GetPlayerSnapshot and radar.GetPlayerSnapshot()
        local ok, result = API.SaveWalkRecording(panel.walkName:GetText(), player)
        Tell(ok and ("Saved walk " .. result.name) or result)
        API.RefreshPanel()
    end)
    panel.walkDiscardButton = Button(walkPage, "Discard Recording", 5, -97, 296, function()
        if API.CancelWalkRecording() then Tell("Walk recording discarded") end
    end)
    Label(walkPage, "SAVED WALK PATHS", 5, -133, 296, 9):SetTextColor(.05, .82, .62, 1)
    panel.walkRows = {}
    for index=1,4 do
        local y = -153 - (index-1)*36
        local row = Button(walkPage, "", 5, y, 240, function(self)
            if not self.path then return end
            local radar = addon.VignetteRadarAPI
            local player = radar and radar.GetPlayerSnapshot and radar.GetPlayerSnapshot()
            local ok, result = API.ReplayWalkPath(self.path.id, player)
            Tell(ok and ("Loaded " .. self.path.name .. " · " .. result .. " stops") or result)
        end)
        local remove = Button(walkPage, "Delete", 250, y, 51, function()
            if row.path then API.DeleteWalkPath(row.path.id) end
        end)
        panel.walkRows[index] = { load=row, remove=remove }
    end
    panel.walkPrev = Button(walkPage, "‹", 5, -310, 42, function()
        page.Walk = math.max(1, (page.Walk or 1)-1)
        API.RefreshPanel()
    end)
    panel.walkPageLabel = Label(walkPage, "", 118, -315, 70, 10)
    panel.walkNext = Button(walkPage, "›", 259, -310, 42, function()
        page.Walk = (page.Walk or 1)+1
        API.RefreshPanel()
    end)
    panel:Hide()
    API.RefreshPanel()
    return panel
end

function API.RefreshWalkRecordingStatus()
    if not panel or not panel:IsShown() or selectedPage ~= "Walk" then return end
    panel.walkSaveButton:SetEnabled(walkRecording ~= nil)
    panel.walkSaveButton:SetAlpha(walkRecording and 1 or .35)
    panel.walkDiscardButton:SetEnabled(walkRecording ~= nil)
    panel.walkDiscardButton:SetAlpha(walkRecording and 1 or .35)
    if walkRecording then
        panel.walkRecordButton:SetText(walkRecording.active and "Pause Recording" or "Resume Recording")
        panel.walkStatus:SetText(string.format("%s · %d yd · %d points", walkMessage or "Walk",
            math.floor(walkRecording.distance + .5), #walkRecording.points))
    else
        panel.walkRecordButton:SetText("Start Recording")
        panel.walkStatus:SetText("Record a walk, then save it as a reusable route.")
    end
end

function API.RefreshPanel()
    if not panel then return end
    local style = addon.VignetteRadarStyle
    if style then
        local ar, ag, ab = style.Color("accent")
        local br, bg, bb = style.Color("background")
        panel:SetBackdropColor(math.min(.14, br * 2.7), math.min(.14, bg * 2.7),
            math.min(.14, bb * 2.7), .99)
        addon.VignetteRadarControls.RefreshPopupSurface(panel)
        panel.title:SetTextColor(ar, ag, ab, 1)
        panel.headerLine:SetColorTexture(ar, ag, ab, .2)
        addon.VignetteRadarControls.RefreshTheme()
    end
    local advanced = type(addon.AdvancedToolsEnabled) == "function" and addon.AdvancedToolsEnabled()
    if selectedPage == "Walk" and not advanced and not walkRecording then selectedPage = "Route" end
    panel.walkHint:SetShown(advanced)
    panel.walkPathsButton:SetShown(advanced)
    for name, content in pairs(panel.pages) do content:SetShown(name == selectedPage) end
    for name, tab in pairs(panel.tabs) do
        if name == selectedPage then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    local db = Settings()
    panel.activePreset:SetText("Last loaded: " .. (db.vignetteRadarActivePreset or "Custom"))
    local customNames = {}
    for name in pairs(db.vignetteRadarCustomPresets) do customNames[#customNames+1] = name end
    table.sort(customNames)
    local customPages = math.max(1, math.ceil(#customNames/4))
    customPage = math.max(1, math.min(customPage, customPages))
    panel.customPageLabel:SetText(customPage .. " / " .. customPages)
    for index, row in ipairs(panel.customRows) do
        local name = customNames[(customPage-1)*4+index]
        row.presetName = name
        if name then row:SetText(name:sub(1, 18)); row:Show() else row:Hide() end
    end
    panel.approachValue:SetText(db.vignetteRadarApproachDistance .. " yd")
    panel.routeStatus:SetText(#db.vignetteRadarRoute .. "/" .. MAX_ROUTE
        .. " stops  •  " .. #routeBack .. " behind  •  Ctrl-click to add")
    API.RefreshWalkRecordingStatus()
    local paths = WalkPaths()
    page.Walk = math.max(1, math.min(page.Walk or 1, math.max(1, math.ceil(#paths/4))))
    panel.walkPageLabel:SetText(page.Walk .. " / " .. math.max(1, math.ceil(#paths/4)))
    for index, row in ipairs(panel.walkRows) do
        local path = paths[(page.Walk-1)*4+index]
        row.load.path = path
        if path then
            row.load:SetText((Text(path.name) or "Walk"):sub(1, 19)
                .. " · " .. (Number(path.distance) or 0) .. " yd")
            row.load:Show(); row.remove:Show()
        else row.load:Hide(); row.remove:Hide() end
    end
    for index, button in ipairs(panel.draftStopButtons) do
        if db.vignetteRadarRouteDraftStops == ({ 3, 4, 5 })[index] then
            button:LockHighlight()
        else button:UnlockHighlight() end
    end
    for index, button in ipairs(panel.draftRangeButtons) do
        if db.vignetteRadarRouteDraftRange == ({ 300, 600, 1200 })[index] then
            button:LockHighlight()
        else button:UnlockHighlight() end
    end
    local draft = panel.routeDraft or {}
    panel.draftStatus:SetText(panel.routeDraftStatus or "Preview to see nearby stops.")
    for index, row in ipairs(panel.draftRows) do
        local stop = draft[index]
        row:SetText(stop and string.format("%d. %s  ·  %d yd", index,
            (stop.name or "Stop"):sub(1, 25), math.floor(stop.stepDistance + .5)) or "")
    end
    local keys = { smart="vignetteRadarSmartZoom", untangle="vignetteRadarUntangle",
        trail="vignetteRadarBreadcrumbs", approach="vignetteRadarApproachAlerts",
        journal="vignetteRadarJournalEnabled" }
    for key, checkbox in pairs(panel.checks) do checkbox:SetChecked(db[keys[key]] == true) end
    for _, name in ipairs({ "Pins", "Journal" }) do
        local records = name == "Pins" and db.vignetteRadarPins or db.vignetteRadarJournal
        local pages = math.max(1, math.ceil(#records/9))
        page[name] = math.max(1, math.min(page[name], pages))
        panel[name .. "Page"]:SetText(page[name] .. " / " .. pages)
        for index, row in ipairs(panel[name .. "Rows"]) do
            local item = records[(page[name]-1)*9 + index]
            row.item = item
            if item then
                local text = (item.name or "Location"):sub(1, 19)
                if item.mapX and item.mapY then
                    text = text .. string.format("  %.0f, %.0f", item.mapX*100, item.mapY*100)
                end
                if name == "Journal" and item.at and date then
                    text = text .. "  " .. date("%m/%d %H:%M", item.at)
                end
                row:SetText(text)
                row:Show()
            else row:Hide() end
        end
    end
end

function API.BuildRouteDraft()
    local radar = addon.VignetteRadarAPI
    local draft = addon.VignetteRadarRouteDraft
    if not (radar and radar.GetRouteCandidates and radar.GetPlayerSnapshot and draft) then
        return false, "Radar data unavailable"
    end
    local db = Settings()
    local stops, status = draft.Build(radar.GetPlayerSnapshot(), radar.GetRouteCandidates(), {
        maxStops = db.vignetteRadarRouteDraftStops,
        maxDistance = db.vignetteRadarRouteDraftRange,
    })
    if panel then
        panel.routeDraft = stops
        panel.routeDraftStatus = #stops > 0 and (#stops .. " nearby stops. Review before applying.")
            or (status and status.reason or "No nearby stops")
        API.RefreshPanel()
    end
    return #stops > 0, panel and panel.routeDraftStatus or nil
end

function API.OpenRouteDraft()
    local frame = BuildPanel()
    selectedPage = "Route"
    API.BuildRouteDraft()
    API.RefreshPanel()
    frame:Show()
end

function API.TogglePanel()
    local frame = BuildPanel()
    if frame:IsShown() then frame:Hide() else frame:Show(); API.RefreshPanel() end
end
