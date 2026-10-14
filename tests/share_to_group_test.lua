-- Share To Group: channel choice, the Party Hunt record, Blizzard's map-pin
-- link with the user waypoint put back, and the click that posts.
local settings = { vignetteRadarShareButton = true, vignetteRadarShareChannel = "auto",
    vignetteRadarShareAddon = true }
local addon = { GetSettings = function() return settings end }
local raid, home, instance = false, false, false
_G.LE_PARTY_CATEGORY_HOME, _G.LE_PARTY_CATEGORY_INSTANCE = 1, 2
_G.IsInRaid = function() return raid end
_G.IsInGroup = function(category)
    if category == 1 then return home end
    if category == 2 then return instance end
    return home or instance
end
local waypoint, sets = nil, 0
_G.UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
    return { uiMapID = mapID, position = { x = x, y = y } }
end }
_G.C_Map = {
    CanSetUserWaypointOnMap = function() return true end,
    GetUserWaypoint = function() return waypoint end,
    SetUserWaypoint = function(point) waypoint = point; sets = sets + 1 end,
    ClearUserWaypoint = function() waypoint = nil end,
    GetUserWaypointHyperlink = function()
        return waypoint and ("|Hworldmap:" .. waypoint.uiMapID .. "|h[Map Pin]|h") or nil
    end,
}
local said = {}
_G.C_ChatInfo = { SendChatMessage = function(message, channel) said[#said + 1] = { message, channel } end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/PartyHunt.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/ShareToGroup.lua"))("VignetteRadar", addon)
local Share = assert(addon.VignetteRadarShareToGroup)

-- Channels: auto follows the group; a named channel wins.
assert(Share.Channel() == "SAY", "alone: say")
home = true
assert(Share.Channel() == "PARTY")
home, instance = false, true
assert(Share.Channel() == "INSTANCE_CHAT", "an instance group uses instance chat")
raid = true
assert(Share.Channel() == "RAID")
assert(Share.Channel("party") == "PARTY" and Share.Channel("say") == "SAY")
raid, instance, home = false, false, true

-- Record: Party Hunt's stop fields, cleaned for the addon message.
local rare = { kind = "rare", key = "Vignette-0-1|bad 2", name = "Big|Rare", mapID = 2025, mapX = .5, mapY = .25 }
local record = Share.Record(rare)
assert(record.kind == "rare" and record.identity == "Vignette-0-1bad2" and record.name == "BigRare"
    and record.mapID == 2025 and record.x == .5, "a record keeps safe characters only")
assert(Share.Record({ name = "No map" }) == nil, "no map position: nothing to share")
assert(Share.Record({ kind = "mob", name = "Pack", mapID = 1, mapX = .1, mapY = .2 }).identity == "share:1:1000:2000",
    "a point without a key gets a position identity")

-- Link: set for a moment, then the old waypoint comes back.
local old = UiMapPoint.CreateFromCoordinates(7, .9, .9)
waypoint = old
local link = Share.Link(rare)
assert(link == "|Hworldmap:2025|h[Map Pin]|h" and waypoint == old, "the user waypoint is put back")
waypoint = nil
assert(Share.Link(rare) and waypoint == nil, "no waypoint before: none after")
waypoint = UiMapPoint.CreateFromCoordinates(2025, .5, .25)
sets = 0
assert(Share.Link(rare) and sets == 0, "a waypoint already on the point is used as is")
waypoint = nil

-- Share: chat line plus the Party Hunt stop, even with Party Hunt sharing off.
local party_sent
local party
party = addon.VignetteRadarPartyHunt.New({ shareStop = false }, nil, {
    send = function(prefix, payload, channel) party_sent = { prefix, payload, channel }; return true end,
    isInParty = function() return home end, isInRaid = function() return raid end,
}, function() return 100 end)
addon.VignetteRadarFeatureRuntime = { ShareStop = function(r, requested, explicit)
    return party:PublishStop(r, requested, explicit)
end }
local posted, sent = Share.Share(rare)
assert(posted and sent and said[1][2] == "PARTY" and said[1][1]:find("[Map Pin]", 1, true)
    and said[1][1]:find("Rare: Big|Rare", 1, true) == nil and said[1][1]:find("Rare: Big", 1, true),
    "a click posts the map pin link and tells VR users")
assert(party_sent and party_sent[3] == "PARTY", "the addon message goes to the group")
assert(not party:PublishStop(record, true), "Party Hunt's own share switch still applies without explicit")

-- Alone: say only, no addon message; switched off: nothing.
home = false
party_sent = nil
posted, sent = Share.Share(rare)
assert(posted and not sent and said[2][2] == "SAY" and party_sent == nil, "alone posts to say only")
settings.vignetteRadarShareButton = false
posted = Share.Share(rare)
assert(not posted and #said == 2, "switched off: nothing is posted")

io.write("share to group tests passed\n")
