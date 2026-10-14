local _, addon = ...
if type(addon) ~= "table" then return end

-- Shared Sightings In: points your group shares become radar notes with
-- evidence "party" (source "Party"), so they show, route and declutter like
-- any other note until they expire.
--   * VignetteRadar addon messages (Party Hunt sightings and stops, sent by
--     Share To Group): decoded and checked by a private Party Hunt service,
--     so the format, size, rate and ignore rules stay in one place.
--   * Blizzard map-pin links in party, raid and instance chat: the point is
--     read with C_Map.GetUserWaypointFromHyperlink, never parsed by hand.
-- Chat and addon messages can be secret during chat lockdown; those are
-- skipped. Own messages are skipped too.
--   SharedSightings.Add(spec) -> note | nil, reason
--     spec = { mapID, x, y, kind, name, sender, via }
--   SharedSightings.FromChat(text, sender) / SharedSightings.FromAddon(prefix, text, channel, sender)
--   SharedSightings.List([now]) -> notes        SharedSightings.AppendTo(notes, mapID [, now])
--   SharedSightings.Clear()
local SharedSightings = {}
addon.VignetteRadarSharedSightings = SharedSightings

local type, ipairs, floor, pcall = type, ipairs, math.floor, pcall
local Secret = addon.Secret
local Field, Number, Integer, Text, Call = Secret.Field, Secret.Number, Secret.Integer, Secret.Text, Secret.Call

SharedSightings.MAX = 24
SharedSightings.PER_SENDER = 10 -- points a sender may add per minute
local NOTE_KIND = { rare = "mob", treasure = "treasure" }
local CHAT_EVENTS = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
local SAME_SPOT = 0.002 -- map units, about 10-20 yd in a zone

local list, senders = {}, {}
local service

local function Settings() return addon.GetSettings() end

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("sightings", fmt, ...) end
end

local function Now()
    return Number(Call(_G, "GetTime")) or 0
end

local function Lifetime()
    return (Number(Settings().vignetteRadarSharedSightingsMinutes) or 10) * 60
end

local function Clean(value, limit)
    value = Text(value, limit or 80, true)
    if not value then return nil end
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c|]", ""):match("^%s*(.-)%s*$")
    return value ~= "" and value or nil
end

local function ShortName(sender)
    sender = Clean(sender, 100)
    return sender and (sender:match("^([^%-]+)") or sender) or nil
end

local function IsMe(sender)
    local me = Text(Call(_G, "UnitName", "player"))
    local short = ShortName(sender)
    return me ~= nil and short ~= nil and short:lower() == me:lower()
end

local function Locked()
    return Call(C_ChatInfo, "InChatMessagingLockdown") == true
end

local function Prune(now)
    for index = #list, 1, -1 do
        if list[index].expiresAt <= now then table.remove(list, index) end
    end
end

-- Validates everything; a point off the map or with a bad map is refused.
function SharedSightings.Add(spec)
    if type(spec) ~= "table" then return nil, "invalid" end
    local mapID = Integer(spec.mapID, 1, 9999999)
    local x, y = Number(spec.x), Number(spec.y)
    if not (mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) then return nil, "invalid" end
    local sender = Clean(spec.sender, 100)
    if not sender then return nil, "no sender" end
    local now = Now()
    Prune(now)
    local bucket = senders[sender]
    if not bucket or now - bucket.start >= 60 then
        bucket = { start = now, count = 0 }
        senders[sender] = bucket
    end
    if bucket.count >= SharedSightings.PER_SENDER then return nil, "rate-limited" end
    local kind = NOTE_KIND[spec.kind] or "note"
    local name = Clean(spec.name) or (kind == "mob" and "Shared Rare" or kind == "treasure" and "Shared Treasure"
        or "Shared Pin")
    -- One spot from one sender (chat link plus addon message) is one point.
    for _, note in ipairs(list) do
        if note.mapID == mapID and math.abs(note.mapX - x) <= SAME_SPOT and math.abs(note.mapY - y) <= SAME_SPOT then
            note.expiresAt, note.at = now + Lifetime(), now
            if note.kind == "note" and kind ~= "note" then note.kind, note.name = kind, name end
            Log("refreshed %s from %s via %s", note.name, sender, spec.via or "?")
            return note, "refreshed"
        end
    end
    local worldX, worldY, instanceID
    local points = addon.VignetteRadarPoints
    if points and points.MapToWorld then worldX, worldY, instanceID = points.MapToWorld(mapID, x, y) end
    if not (worldX and worldY) then return nil, "no world position" end
    bucket.count = bucket.count + 1
    local short = ShortName(sender) or sender
    local note = { key = "party:" .. mapID .. ":" .. floor(x * 10000 + .5) .. ":" .. floor(y * 10000 + .5),
        kind = kind, name = name, source = "Party", evidence = "party", sender = sender,
        note = "Shared by " .. short, mapID = mapID, mapX = x, mapY = y,
        worldX = worldX, worldY = worldY, instanceID = instanceID, at = now, expiresAt = now + Lifetime() }
    list[#list + 1] = note
    while #list > SharedSightings.MAX do table.remove(list, 1) end
    Log("added %s (%s) map %d from %s via %s", name, kind, mapID, sender, spec.via or "?")
    local bus = addon.Bus
    if bus then bus.Emit("SIGHTINGS_CHANGED", note) end
    return note
end

-- "Rare: Name" / "Treasure: Name" is Share To Group's own line; otherwise
-- the words around the link pick the kind.
local function ChatKind(rest)
    local title, name = rest:match("^%s*(%a+):%s*(.-)%s*$")
    title = title and title:lower()
    if title == "rare" or title == "treasure" then return title, name end
    local lower = rest:lower()
    if lower:find("rare", 1, true) then return "rare", nil end
    if lower:find("treasure", 1, true) or lower:find("chest", 1, true) then return "treasure", nil end
    return "pin", nil
end

function SharedSightings.FromChat(text, sender)
    if Settings().vignetteRadarSharedSightings ~= true or Settings().vignetteRadarSharedSightingsChat ~= true then
        return nil, "off"
    end
    if Secret.IsSecret(text) or Secret.IsSecret(sender) or Locked() then return nil, "secret" end
    text = Text(text, 1024)
    if not text or not text:find("|Hworldmap:", 1, true) then return nil, "no link" end
    if IsMe(sender) then return nil, "own" end
    local link = text:match("(|Hworldmap:[^|]*|h.-|h)")
    if not link then return nil, "no link" end
    local point = Call(C_Map, "GetUserWaypointFromHyperlink", link)
    local position = Field(point, "position")
    local mapID = Field(point, "uiMapID")
    local x, y = Field(position, "x"), Field(position, "y")
    if not (Number(x) and Number(y)) then
        local getXY = Field(position, "GetXY")
        if type(getXY) == "function" then
            local ok, a, b = pcall(getXY, position)
            if ok then x, y = a, b end
        end
    end
    local kind, name = ChatKind((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h.-|h", "")))
    return SharedSightings.Add({ mapID = mapID, x = x, y = y, kind = kind, name = name,
        sender = sender, via = "chat" })
end

-- Addon messages: a private Party Hunt service validates, rate-limits and
-- drops our own echo. Party Hunt's ignore list applies here too.
local function Service()
    local hunt = addon.VignetteRadarPartyHunt
    if not hunt then return nil end
    local party = Settings().vignetteRadarPartyHunt
    local ignored = type(party) == "table" and type(party.ignored) == "table" and party.ignored or {}
    if not service then
        service = hunt.New({ receive = "raid", ignored = ignored }, function(report)
            SharedSightings.Add({ mapID = report.mapID, x = report.x, y = report.y, kind = report.kind,
                name = report.name, sender = report.sender, via = "addon" })
        end)
    else
        service.settings.ignored = ignored
    end
    return service
end

function SharedSightings.FromAddon(prefix, text, channel, sender)
    if Settings().vignetteRadarSharedSightings ~= true then return false end
    if Secret.IsSecret(prefix) or Secret.IsSecret(text) or Secret.IsSecret(channel) or Secret.IsSecret(sender)
        or Locked() then return false end
    local hunt = addon.VignetteRadarPartyHunt
    if not (hunt and prefix == hunt.PREFIX) then return false end
    local party = Service()
    return party and party:HandleMessage(prefix, text, channel, sender) or false
end

function SharedSightings.List(now)
    Prune(Number(now) or Now())
    return list
end

-- Adds this map's live shared points to the scan's notes.
function SharedSightings.AppendTo(notes, mapID, now)
    if type(notes) ~= "table" or Settings().vignetteRadarSharedSightings ~= true then return 0 end
    mapID = Number(mapID)
    local added = 0
    for _, note in ipairs(SharedSightings.List(now)) do
        if note.mapID == mapID then notes[#notes + 1] = note; added = added + 1 end
    end
    return added
end

function SharedSightings.Clear()
    list, senders = {}, {}
end

local function Register()
    local hunt = addon.VignetteRadarPartyHunt
    if hunt and Settings().vignetteRadarSharedSightings == true then
        local result = Call(C_ChatInfo, "RegisterAddonMessagePrefix", hunt.PREFIX)
        Log("prefix %s registered: %s", hunt.PREFIX, tostring(result))
    end
end
SharedSightings.Register = Register

local bus = addon.Bus
if bus then
    bus.On("LOGIN", Register)
    bus.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
        SharedSightings.FromAddon(prefix, text, channel, sender)
    end)
    for _, event in ipairs(CHAT_EVENTS) do
        bus.On(event, function(_, text, sender) SharedSightings.FromChat(text, sender) end)
    end
end

return SharedSightings
