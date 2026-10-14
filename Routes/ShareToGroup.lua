local _, addon = ...
if type(addon) ~= "table" then return end

-- Share To Group: one click posts the focused point to chat as Blizzard's
-- own map-pin link (party, raid, instance or say), and sends it to other
-- VignetteRadar users in the group as a Party Hunt stop. Chat sending is
-- protected: Share() must only run from a hardware click.
--   ShareToGroup.Channel([choice]) -> "RAID" | "PARTY" | "INSTANCE_CHAT" | "SAY"
--   ShareToGroup.Record(item) -> Party Hunt stop record or nil
--   ShareToGroup.Link(item) -> Blizzard map-pin hyperlink or nil
--   ShareToGroup.Message(item, link) -> chat line
--   ShareToGroup.Share(item) -> posted, sentToAddon, reason
local ShareToGroup = {}
addon.VignetteRadarShareToGroup = ShareToGroup

local type, pcall, floor = type, pcall, math.floor
local Number, Text, SecretCall = addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local KIND = { rare = "rare", mob = "rare", treasure = "treasure", quest = "quest" }
local KIND_TITLE = { rare = "Rare", treasure = "Treasure", quest = "Quest" }

local function Settings() return addon.GetSettings() end

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("share", fmt, ...) end
end

local function Group(name, category)
    return SecretCall(_G, name, category) == true
end

-- "auto" follows Blizzard's chat edit box: raid, home party, instance group,
-- else say. A named channel is used as is.
function ShareToGroup.Channel(choice)
    choice = choice or Settings().vignetteRadarShareChannel
    if choice == "raid" then return "RAID" end
    if choice == "party" then return "PARTY" end
    if choice == "say" then return "SAY" end
    if Group("IsInRaid") then return "RAID" end
    local home, instance = _G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE
    if home and instance and not Group("IsInGroup", home) and Group("IsInGroup", instance) then
        return "INSTANCE_CHAT"
    end
    if Group("IsInGroup") then return "PARTY" end
    return "SAY"
end

local function Position(item)
    local mapID, x, y = Number(item.mapID), Number(item.mapX), Number(item.mapY)
    if not (mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil end
    return mapID, x, y
end

function ShareToGroup.Record(item)
    if type(item) ~= "table" then return nil end
    local mapID, x, y = Position(item)
    local name = Text(item.name, 80, true)
    if not (mapID and name) then return nil end
    name = name:gsub("[%c|]", "")
    local identity = Text(item.key) or Text(tostring(Number(item.questID) or ""))
    identity = identity and identity:gsub("[^%w:_.%-]", ""):sub(1, 80) or ""
    if identity == "" then identity = "share:" .. mapID .. ":" .. floor(x * 10000) .. ":" .. floor(y * 10000) end
    return { mapID = mapID, x = x, y = y, kind = KIND[item.kind] or "pin", identity = identity, name = name }
end

-- Blizzard builds the link from its user waypoint. When the waypoint is not
-- already at this point it is set for a moment and then put back, so the
-- focus (pin, quest or vignette super-track) is left as it was.
function ShareToGroup.Link(item)
    if type(item) ~= "table" then return nil end
    local mapID, x, y = Position(item)
    if not (mapID and C_Map and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function") then
        return nil
    end
    if SecretCall(C_Map, "CanSetUserWaypointOnMap", mapID) == false then return nil end
    local previous = SecretCall(C_Map, "GetUserWaypoint")
    local ok, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x, y)
    if not ok or type(point) ~= "table" then return nil end
    local at = type(previous) == "table" and type(previous.position) == "table" and previous.uiMapID == mapID
        and math.abs((Number(previous.position.x) or -1) - x) < .0001
        and math.abs((Number(previous.position.y) or -1) - y) < .0001
    if not at and not pcall(C_Map.SetUserWaypoint, point) then return nil end
    local link = Text(SecretCall(C_Map, "GetUserWaypointHyperlink"))
    if not at then
        if type(previous) == "table" then pcall(C_Map.SetUserWaypoint, previous)
        else SecretCall(C_Map, "ClearUserWaypoint") end
    end
    return link
end

function ShareToGroup.Message(item, link)
    local title = KIND_TITLE[KIND[item.kind] or ""] or "Point"
    -- A stray pipe would start an escape sequence in chat; only the link has one.
    local name = (Text(item.name, 80, true) or "Point"):gsub("[%c|]", "")
    return (link and (link .. " ") or "") .. title .. ": " .. name
end

-- Hardware click only (C_ChatInfo.SendChatMessage is protected).
function ShareToGroup.Share(item)
    local settings = Settings()
    if settings.vignetteRadarShareButton ~= true then return false, false, "Share To Group is off" end
    local record = ShareToGroup.Record(item)
    if not record then return false, false, "This point has no map position to share" end
    local channel = ShareToGroup.Channel()
    local posted = false
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or _G.SendChatMessage
    if type(send) == "function" then
        posted = pcall(send, ShareToGroup.Message(item, ShareToGroup.Link(item)), channel)
    end
    local sent, why = false, "addon message off"
    if settings.vignetteRadarShareAddon == true and channel ~= "SAY" then
        local runtime = addon.VignetteRadarFeatureRuntime
        if runtime and runtime.ShareStop then sent, why = runtime.ShareStop(record, true, true) end
    end
    Log("share %s to %s posted=%s addon=%s %s", record.name, channel, posted, sent, why or "")
    return posted, sent == true, not posted and "Chat message could not be sent" or nil
end

return ShareToGroup
