local _, addon = ...
if type(addon) ~= "table" then return end

-- Waypoint compatibility: /way (TomTom syntax) and, only when the real
-- TomTom is not loaded, a small TomTom stand-in so addons that call
-- TomTom:AddWaypoint (HandyNotes packs, BtWQuests, WorldQuestTab...) put
-- their waypoint on VR's Focus and World Focus instead of nowhere.
--   /way [#mapID | mapID] x y [title]   x, y in 0-100; no map = your map
--   /way clear | reset                   clears the /way waypoints
--   /vrway ...                           same, always registered
--   Way.Parse(text, currentMapID) -> { mapID, x, y, title } | { clear = true } | nil, why
--   Way.Add(mapID, x, y, opts) -> uid | nil, why      (x, y in 0-1)
--   Way.Remove(uid) / Way.Clear() / Way.SetClosest() / Way.List()
-- uids keep TomTom's shape ({ mapID, x, y, title = , from = }) and its
-- waypoints[mapID][key] table, which WorldQuestTab reads directly. The
-- stand-in never replaces a real TomTom and is never installed over one.
-- luacheck: globals SLASH_VIGNETTERADARWAY1 SLASH_VIGNETTERADARWAY2 SlashCmdList
local Way = {}
addon.VignetteRadarWay = Way

local type, tonumber, tostring, pairs, ipairs = type, tonumber, tostring, pairs, ipairs
local format, concat = string.format, table.concat
local Number, Text, Call = addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local waypoints = {}      -- TomTom shape: [mapID][key] = uid
local pending             -- uid to focus on the next frame
local standIn             -- the TomTom table VR installed, if any

local function Settings() return addon.GetSettings() end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("way", fmt, ...) end
end

local function Chat(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and type(frame.AddMessage) == "function" then frame:AddMessage("|cff8bd5caVR|r " .. text) end
end

-- TomTom's own key format, so TomTom.waypoints[m][TomTom:GetKeyArgs(...)] works.
function Way.Key(mapID, x, y, title)
    return format("%d:%s:%s:%s", mapID, x * 10000 * 10e4, y * 10000 * 10e4, tostring(title))
end

local function Usage()
    return "usage: /way [#mapID] x y [title]  ·  /way clear"
end

-- TomTom accepts "45.2, 30.1" and "45,2 30,1"; so does this.
function Way.Parse(text, currentMapID)
    text = Text(text) or ""
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, Usage() end
    local lower = text:lower()
    if lower == "clear" or lower == "reset" or lower == "reset all" then return { clear = true } end
    text = text:gsub("(%d)[%.,] (%d)", "%1 %2"):gsub("(%d),(%d)", "%1.%2")
    local tokens = {}
    for token in text:gmatch("%S+") do tokens[#tokens + 1] = token end
    local mapID, first = nil, 1
    local forced = tokens[1] and tokens[1]:match("^#(%d+)$")
    if forced then
        mapID, first = tonumber(forced), 2
    elseif #tokens >= 3 and tokens[1]:match("^%d+$") and tonumber(tokens[2]) and tonumber(tokens[3]) then
        -- Three leading numbers: the first, a whole number, is the map.
        mapID, first = tonumber(tokens[1]), 2
    end
    local x, y = tonumber(tokens[first]), tonumber(tokens[first + 1])
    if not (x and y) then return nil, Usage() end
    if x < 0 or x > 100 or y < 0 or y > 100 then return nil, "x and y go from 0 to 100" end
    mapID = mapID or Number(currentMapID)
    if not mapID then return nil, "no map: use /way #mapID x y" end
    local title = #tokens >= first + 2 and concat(tokens, " ", first + 2) or nil
    return { mapID = mapID, x = x / 100, y = y / 100, title = title }
end

local function Point(uid)
    return uid and uid.vrPoint
end

local function Focused(uid)
    local focus = addon.VignetteRadarFocus
    local current = focus and focus.Get()
    local point = Point(uid)
    return point and current and current.key == point.key or false
end

-- Focus the newest waypoint once per frame, so a pack adding a whole group
-- (closest last, like TomTom's arrow) moves the waypoint once.
local function FocusPending()
    local uid = pending
    pending = nil
    local point = Point(uid)
    local focus = addon.VignetteRadarFocus
    if not (point and focus and Way.IsValid(uid)) then return end
    local ok, why = focus.Select(focus.Point(point), { source = "way", direct = true })
    Trace("focus %s (%s) -> %s %s", point.name, uid.from or "?", tostring(ok), tostring(why or ""))
end

if addon.Bus then addon.Bus.On("VR_WAY_FOCUS", FocusPending, { coalesce = true }) end

function Way.Add(mapID, x, y, opts)
    opts = type(opts) == "table" and opts or {}
    mapID, x, y = Number(mapID), Number(x), Number(y)
    if not (mapID and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil, "bad position" end
    local title = Text(opts.title, 200, true)
    local key = Way.Key(mapID, x, y, title)
    waypoints[mapID] = waypoints[mapID] or {}
    local uid = waypoints[mapID][key]
    if not uid then
        local points = addon.VignetteRadarPoints
        local worldX, worldY, instanceID
        if points then worldX, worldY, instanceID = points.MapToWorld(mapID, x, y) end
        if not (worldX and worldY) then
            Trace("refused %d %.4f %.4f: map has no world position", mapID, x, y)
            return nil, "that map has no world position"
        end
        uid = { mapID, x, y, title = title, from = Text(opts.from, 64, true) or "?" }
        for field, value in pairs(opts) do
            if uid[field] == nil and type(field) == "string" then uid[field] = value end
        end
        uid.vrPoint = { key = "way:" .. key, kind = "note", source = "way", evidence = "pin",
            name = title or "Waypoint", mapID = mapID, mapX = x, mapY = y,
            worldX = worldX, worldY = worldY, instanceID = instanceID }
        waypoints[mapID][key] = uid
        Trace("added %s at %d %.4f %.4f from %s", uid.vrPoint.name, mapID, x, y, uid.from)
    end
    if opts.crazy ~= false then
        pending = uid
        if addon.Bus then addon.Bus.Emit("VR_WAY_FOCUS") else FocusPending() end
    end
    return uid
end

function Way.IsValid(uid)
    if type(uid) ~= "table" then return false end
    local mapID = uid[1]
    local list = mapID and waypoints[mapID]
    if not list then return false end
    for _, value in pairs(list) do if value == uid then return true end end
    return false
end

function Way.Exists(mapID, x, y, title)
    local list = waypoints[mapID]
    return list ~= nil and list[Way.Key(mapID, x, y, title)] ~= nil
end

-- Removing the waypoint VR is showing also clears the World Focus pin.
function Way.Remove(uid)
    if type(uid) ~= "table" or not Way.IsValid(uid) then return false end
    local list = waypoints[uid[1]]
    for key, value in pairs(list) do if value == uid then list[key] = nil end end
    if not next(list) then waypoints[uid[1]] = nil end
    if pending == uid then pending = nil end
    if Focused(uid) then
        local focus = addon.VignetteRadarFocus
        focus.Clear({ source = "way" })
    end
    Trace("removed %s", Point(uid) and Point(uid).name or "?")
    return true
end

function Way.Clear()
    local count = 0
    for _, list in pairs(waypoints) do
        for _, uid in pairs(list) do
            if Focused(uid) then addon.VignetteRadarFocus.Clear({ source = "way" }) end
            count = count + 1
        end
    end
    waypoints, pending = {}, nil
    Trace("cleared %d waypoints", count)
    return count
end

function Way.List()
    local list = {}
    for _, byKey in pairs(waypoints) do
        for _, uid in pairs(byKey) do list[#list + 1] = uid end
    end
    return list
end

-- Focus the closest waypoint (TomTom:SetClosestWaypoint).
function Way.SetClosest()
    local points = addon.VignetteRadarPoints
    local view = points and points.View()
    local player = view and view.player
    local best, bestDistance
    for _, uid in ipairs(Way.List()) do
        local distance = player and points.Distance(player, Point(uid))
        if distance and (not bestDistance or distance < bestDistance) then best, bestDistance = uid, distance end
    end
    if best then
        pending = best
        FocusPending()
    end
    return best
end

local function CurrentMap()
    return Number(Call(C_Map, "GetBestMapForUnit", "player"))
end

function Way.Command(text)
    local parsed, why = Way.Parse(text, CurrentMap())
    if not parsed then Chat(why); return end
    if parsed.clear then
        Chat(Way.Clear() .. " waypoints cleared")
        return
    end
    local uid, reason = Way.Add(parsed.mapID, parsed.x, parsed.y,
        { title = parsed.title, from = "VR/way" })
    if not uid then Chat(reason) end
end

-- TomTom stand-in ------------------------------------------------------------
-- Only what other addons call (counted across the installed addons):
-- AddWaypoint, RemoveWaypoint, SetClosestWaypoint, IsValidWaypoint,
-- WaypointExists, GetKeyArgs and the waypoints table. Kaliel's Tracker and
-- Zygor check for the real addon and keep away from it.

local function BuildStandIn()
    local shim = { waypoints = waypoints, vignetteRadarStandIn = true }
    function shim:AddWaypoint(m, x, y, opts) return Way.Add(m, x, y, opts) end
    function shim:RemoveWaypoint(uid) return Way.Remove(uid) end
    function shim:SetClosestWaypoint() return Way.SetClosest() end
    function shim:IsValidWaypoint(uid) return Way.IsValid(uid) end
    function shim:WaypointExists(m, x, y, title) return Way.Exists(m, x, y, title) end
    function shim:GetKeyArgs(m, x, y, title) return Way.Key(m, x, y, title) end
    function shim:GetKey(uid) return type(uid) == "table" and Way.Key(uid[1], uid[2], uid[3], uid.title) or nil end
    return shim
end

local function TomTomLoaded()
    local loading, loaded = Call(C_AddOns, "IsAddOnLoaded", "TomTom")
    return loading == true or loaded == true
end

-- True when another addon already answers a slash command.
local function SlashTaken(command)
    if type(SlashCmdList) ~= "table" then return true end
    for name in pairs(SlashCmdList) do
        if name ~= "VIGNETTERADARWAY" and type(name) == "string" then
            for index = 1, 9 do
                local value = _G["SLASH_" .. name .. index]
                if value == nil then break end
                if type(value) == "string" and value:lower() == command then return true end
            end
        end
    end
    return false
end

function Way.Install()
    local db = Settings()
    if type(SlashCmdList) == "table" then
        SLASH_VIGNETTERADARWAY1 = "/vrway"
        SLASH_VIGNETTERADARWAY2 = nil
        if db.vignetteRadarWayCommand == true and not SlashTaken("/way") then
            SLASH_VIGNETTERADARWAY2 = "/way"
        end
        SlashCmdList.VIGNETTERADARWAY = Way.Command
    end
    local current = _G.TomTom
    if db.vignetteRadarTomTomStandIn == true then
        if current == nil and not TomTomLoaded() then
            standIn = standIn or BuildStandIn()
            _G.TomTom = standIn
            Trace("TomTom stand-in installed")
        end
    elseif standIn and current == standIn then
        _G.TomTom = nil
        Trace("TomTom stand-in removed")
    end
end

function Way.IsStandIn() return standIn ~= nil and _G.TomTom == standIn end

-- Every non-LoadOnDemand addon (TomTom included) has loaded by PLAYER_LOGIN.
if addon.Bus then addon.Bus.On("LOGIN", function() Way.Install() end) end

return Way
