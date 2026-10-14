local path = arg[1] or "Routes/PartyHunt.lua"
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile(path))("VignetteRadar", addon)
local PartyHunt = assert(addon.VignetteRadarPartyHunt)

-- The real C_ChatInfo calls return enum numbers, not booleans.
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 },
    RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1,
        InvalidPrefix = 2, MaxPrefixes = 3 } }
local now, sent, callbacks = 100, {}, {}
local group = "PARTY"
local sendResult, registerResult, registerCalls = 0, 0, 0
local transport = {
    register = function(prefix)
        registerCalls = registerCalls + 1
        return prefix == PartyHunt.PREFIX and registerResult or 2
    end,
    send = function(prefix, payload, channel)
        sent[#sent + 1] = { prefix, payload, channel }
        return sendResult
    end,
    isInParty = function() return group == "PARTY" end,
    isInRaid = function() return group == "RAID" end,
    playerName = function() return "Me-Realm" end,
}
local settings = { receive = "party", shareSightings = false, shareStop = false,
    ignored = { ["ignored-realm"] = true } }
local service = PartyHunt.New(settings, function(report) callbacks[#callbacks + 1] = report end,
    transport, function() return now end)
local sighting = { mapID = 2025, x = .437, y = .812, kind = "rare",
    identity = "rare:123", name = "Crystal Beast" }

assert(not service:PublishSighting(sighting, true) and #sent == 0,
    "sightings must never broadcast before opt-in")
settings.shareSightings = true
assert(not service:PublishSighting(sighting) and #sent == 0,
    "a sharing setting alone must not trigger a background send")
assert(service:PublishSighting(sighting, true) and #sent == 1 and sent[1][3] == "PARTY",
    "opted-in sightings should send one party message")
assert(not service:PublishSighting(sighting, true) and #sent == 1,
    "repeated clicks must respect the send cooldown")
assert(registerCalls == 0, "publishing must not register the prefix every time")
assert(not service:HandleMessage(sent[1][1], sent[1][2], "PARTY", "Me-Realm"),
    "our own echoed message must be ignored")
assert(service:HandleMessage(sent[1][1], sent[1][2], "PARTY", "Friend-Realm"),
    "a valid group report should be accepted")
local reports = service:GetReports()
assert(#reports == 1 and reports[1].evidence == "group-report"
    and reports[1].phaseCompatibility == "unknown"
    and reports[1].instanceCompatibility == "unknown"
    and reports[1].sender == "Friend-Realm" and reports[1].age == 0,
    "remote evidence must be labeled and not promoted to a live local detection")
assert(#callbacks == 1 and not service:HandleMessage(sent[1][1], sent[1][2], "PARTY", "Friend-Realm"),
    "duplicates must not trigger a second callback")
reports[1].name = "changed"
assert(service:GetReports()[1].name == "Crystal Beast", "callers must get detached report copies")

local malformed = {
    "1|G|x|2025|5000|5000|rare|id", -- missing name
    "2|G|x|2025|5000|5000|rare|id|Name", -- unknown version
    "1|G|x|2025|10001|5000|rare|id|Name", -- out of map
    "1|G|x|2025|5000|5000|quest|id|Name", -- quest is not a sighting
    "1|G|x|2025|5000|5000|rare|id|Bad\nName", -- control text
    "1|G|x|2025|5000|5000|rare|id|Name|extra", -- extra field
}
for _, message in ipairs(malformed) do
    assert(not service:HandleMessage(PartyHunt.PREFIX, message, "PARTY", "Friend-Realm"),
        "malformed messages must be ignored")
end
assert(not service:HandleMessage(sent[1][1], sent[1][2], "PARTY", "Ignored-Realm"),
    "ignored senders must be rejected")
assert(not service:HandleMessage(sent[1][1], sent[1][2], "WHISPER", "Other-Realm"),
    "whispers must not inject group reports")

now = now + 91
assert(#service:GetReports() == 0, "reports must expire")
settings.shareStop = true
group = "RAID"
assert(service:PublishStop({ mapID = 2025, x = 0, y = 1, kind = "quest",
    identity = "quest:99", name = "Next stop" }, true) and sent[#sent][3] == "RAID",
    "opted-in selected stops can be shared in a raid")
assert(not service:HandleMessage(sent[#sent][1], sent[#sent][2], "RAID", "Raidmate-Realm"),
    "party receive scope must exclude raid")
settings.receive = "raid"
assert(service:HandleMessage(sent[#sent][1], sent[#sent][2], "RAID", "Raidmate-Realm"),
    "raid receive scope should accept a selected stop")
assert(service:GetReports()[1].reportType == "stop", "the selected stop stays distinct from a sighting")

now = now + 6
sendResult = Enum.SendAddonMessageResult.AddonMessageThrottle
local throttled, reason = service:PublishStop({ mapID = 2025, x = 0, y = 1, kind = "quest",
    identity = "quest:98", name = "Throttled" }, true)
assert(not throttled and reason == "local-only",
    "a non-success send result must count as a failure")
sendResult = 0

group = nil
service:OnGroupChanged()
assert(#service:GetReports() == 0, "disconnecting must clear old reports")
assert(not service:PublishSighting(sighting, true) and #sent == 3,
    "outside a group the service must fall back to local-only")
settings.receive = "off"
service:SetSettings(settings)
assert(not service:HandleMessage(sent[1][1], sent[1][2], "PARTY", "Friend-Realm"),
    "receive off must reject all messages")

local combat, registered, unregistered = true, 0, 0
InCombatLockdown = function() return combat end
CreateFrame = function()
    return { SetScript = function() end,
        RegisterEvent = function() registered = registered + 1 end,
        UnregisterAllEvents = function() unregistered = unregistered + 1 end }
end
settings.receive = "party"
service:SetSettings(settings)
registerResult = Enum.RegisterAddonMessagePrefixResult.MaxPrefixes
combat = false
assert(not service:Start() and registered == 0, "a failed prefix registration must not start")
registerResult = Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix
combat = true
assert(not service:Start() and registered == 0,
    "opt-in event registration must wait until combat lockdown ends")
combat = false
assert(service:Start() and registered == 2,
    "the service should start when a later safe event retries it")
local calls = registerCalls
settings.shareSightings = true
group = "PARTY"
now = now + 100
assert(service:PublishSighting(sighting, true) and registerCalls == calls,
    "an already registered prefix is not registered again on publish")
combat = true
settings.receive = "off"
service:SetSettings(settings)
assert(unregistered == 0 and service.active == false,
    "turning Party Hunt off in combat must mute it without a protected unregister")
combat = false
service:SetSettings(settings)
assert(unregistered == 1 and service.frame == nil,
    "the deferred event cleanup should finish after combat")

io.write("vignette radar party hunt tests passed\n")
