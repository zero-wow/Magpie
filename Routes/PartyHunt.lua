local _, addon = ...
if type(addon) ~= "table" then return end

-- Party Hunt transports only a small, explicitly requested report. A received
-- report is unverified group evidence; the caller decides how to display it.
local PartyHunt = {}
addon.VignetteRadarPartyHunt = PartyHunt

PartyHunt.PREFIX = "VRHUNT1"
PartyHunt.TTL = 90
PartyHunt.MAX_REPORTS = 64

local Safe, Field = addon.Secret.Safe, addon.Secret.Field
local Integer, SecretText = addon.Secret.Integer, addon.Secret.Text

-- Party messages also reject control characters and the escape pipe.
local function Text(value, limit, pattern)
    value = SecretText(value, limit)
    if not value or value:find("[%c|]") then return nil end
    if pattern and not value:match(pattern) then return nil end
    return value
end

local function Now()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and Safe(value) and type(value) == "number" then return value end
    end
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and Safe(value) and type(value) == "number" then return value end
    end
    return 0
end

-- The transport returns the raw C_ChatInfo results: retail answers with
-- Enum.RegisterAddonMessagePrefixResult / Enum.SendAddonMessageResult numbers
-- (Success = 0), older clients with booleans.
local function DefaultTransport()
    return {
        register = function(prefix)
            if not C_ChatInfo or type(C_ChatInfo.RegisterAddonMessagePrefix) ~= "function" then return false end
            return C_ChatInfo.RegisterAddonMessagePrefix(prefix)
        end,
        send = function(prefix, payload, channel)
            if not C_ChatInfo or type(C_ChatInfo.SendAddonMessage) ~= "function" then return false end
            return C_ChatInfo.SendAddonMessage(prefix, payload, channel)
        end,
        playerName = function()
            if type(UnitFullName) ~= "function" then return nil end
            local name, realm = UnitFullName("player")
            if (type(realm) ~= "string" or realm == "") and type(GetNormalizedRealmName) == "function" then
                realm = GetNormalizedRealmName()
            end
            if type(name) ~= "string" or type(realm) ~= "string" or realm == "" then return nil end
            return name .. "-" .. realm
        end,
        isInParty = function()
            return type(IsInGroup) == "function" and IsInGroup() == true
        end,
        isInRaid = function()
            return type(IsInRaid) == "function" and IsInRaid() == true
        end,
    }
end

local function Call(transport, method, ...)
    local fn = Field(transport, method)
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, ...)
    return ok and result == true
end

-- Raw result of a transport call, or nil when it is missing or errors.
local function CallResult(transport, method, ...)
    local fn = Field(transport, method)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if not ok or not Safe(result) then return nil end
    return result
end

local function EnumValue(group, name, fallback)
    local values = Enum and Field(Enum, group)
    local value = Field(values, name)
    if type(value) == "number" then return value end
    return fallback
end

local function SendSucceeded(result)
    return result == true or result == EnumValue("SendAddonMessageResult", "Success", 0)
end

-- A prefix that is already registered (by a reload or another instance) is usable.
local function RegisterSucceeded(result)
    return result == true
        or result == EnumValue("RegisterAddonMessagePrefixResult", "Success", 0)
        or result == EnumValue("RegisterAddonMessagePrefixResult", "DuplicatePrefix", 1)
end

local function GroupChannel(transport)
    if Call(transport, "isInRaid") then return "RAID" end
    if Call(transport, "isInParty") then return "PARTY" end
end

local function ValidRecord(record, reportType)
    if reportType ~= "sighting" and reportType ~= "stop" then return nil end
    local mapID = Integer(Field(record, "mapID"), 1, 9999999)
    local x, y = Field(record, "x"), Field(record, "y")
    if not Safe(x) or not Safe(y) or type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local kind = Text(Field(record, "kind"), 8, "^[a-z]+$")
    if kind ~= "rare" and kind ~= "treasure" and kind ~= "quest" and kind ~= "pin" then return nil end
    if reportType == "sighting" and kind ~= "rare" and kind ~= "treasure" then return nil end
    local identity = Text(Field(record, "identity"), 80, "^[%w:_.%-]+$")
    local name = Text(Field(record, "name"), 80)
    if not mapID or not identity or not name then return nil end
    return { mapID = mapID, x = math.floor(x * 10000 + .5),
        y = math.floor(y * 10000 + .5), kind = kind, identity = identity,
        name = name, reportType = reportType }
end

local function Encode(record, nonce)
    local code = record.reportType == "sighting" and "G" or "T"
    local payload = table.concat({ "1", code, nonce, record.mapID,
        record.x, record.y, record.kind, record.identity, record.name }, "|")
    if #payload > 240 then return nil end
    return payload
end

local function Decode(payload)
    if not Safe(payload) or type(payload) ~= "string" or #payload == 0 or #payload > 240
        or payload:find("%c") then return nil end
    local version, code, nonce, mapID, x, y, kind, identity, name =
        payload:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if version ~= "1" or (code ~= "G" and code ~= "T") then return nil end
    nonce = Text(nonce, 32, "^[%w%-]+$")
    mapID = Integer(tonumber(mapID), 1, 9999999)
    x, y = Integer(tonumber(x), 0, 10000), Integer(tonumber(y), 0, 10000)
    kind = Text(kind, 8, "^[a-z]+$")
    identity = Text(identity, 80, "^[%w:_.%-]+$")
    name = Text(name, 80)
    if not nonce or not mapID or not x or not y or not kind or not identity or not name then return nil end
    if kind ~= "rare" and kind ~= "treasure" and kind ~= "quest" and kind ~= "pin" then return nil end
    if code == "G" and kind ~= "rare" and kind ~= "treasure" then return nil end
    return { reportType = code == "G" and "sighting" or "stop", mapID = mapID,
        x = x / 10000, y = y / 10000, kind = kind, identity = identity,
        name = name, nonce = nonce }
end

function PartyHunt.New(settings, onReport, transport, clock)
    local service = { settings = settings or {}, onReport = onReport,
        transport = transport or DefaultTransport(), clock = clock or Now,
        reports = {}, seen = {}, incoming = {}, outgoing = {}, sequence = 0 }
    setmetatable(service, { __index = PartyHunt })
    return service
end

function PartyHunt:SetSettings(settings)
    self.settings = type(settings) == "table" and settings or {}
    local receive = Field(self.settings, "receive")
    if receive ~= "party" and receive ~= "raid" then
        self:Stop()
    end
end

function PartyHunt:Prune()
    local now = self.clock()
    for index = #self.reports, 1, -1 do
        if now - self.reports[index].receivedAt >= PartyHunt.TTL then
            table.remove(self.reports, index)
        end
    end
    for key, expiresAt in pairs(self.seen) do
        if expiresAt <= now then self.seen[key] = nil end
    end
    for key, window in pairs(self.incoming) do
        if now - window.start >= 60 then self.incoming[key] = nil end
    end
end

function PartyHunt:GetReports()
    self:Prune()
    local result = {}
    for index, report in ipairs(self.reports) do
        local copy = {}
        for key, value in pairs(report) do copy[key] = value end
        copy.age = math.max(0, self.clock() - report.receivedAt)
        result[index] = copy
    end
    return result
end

-- requested must come from a direct user action, never a detection/update loop.
-- explicit = true is a click on a share control with its own switch (Share
-- To Group), so the Party Hunt share settings do not apply to it.
function PartyHunt:Publish(reportType, record, requested, explicit)
    if requested ~= true then return false, "user-action-required" end
    local setting = reportType == "sighting" and "shareSightings" or "shareStop"
    if explicit ~= true and Field(self.settings, setting) ~= true then return false, "sharing-off" end
    local channel = GroupChannel(self.transport)
    if not channel then return false, "local-only" end
    local checked = ValidRecord(record, reportType)
    if not checked then return false, "invalid-report" end
    local now = self.clock()
    local last = self.outgoing[reportType]
    if last and now - last < 5 then return false, "rate-limited" end
    local window = self.outgoing.window
    if not window or now - window.start >= 60 then
        window = { start = now, count = 0 }
        self.outgoing.window = window
    end
    if window.count >= 10 then return false, "rate-limited" end
    self.sequence = (self.sequence % 999999) + 1
    local nonce = tostring(math.floor(now * 1000)) .. "-" .. tostring(self.sequence)
    local payload = Encode(checked, nonce)
    if not payload then return false, "invalid-report" end
    -- Sending needs no registered prefix; Start registers it once for receiving.
    if not SendSucceeded(CallResult(self.transport, "send", PartyHunt.PREFIX, payload, channel)) then
        return false, "local-only"
    end
    self.outgoing[reportType] = now
    window.count = window.count + 1
    return true
end

function PartyHunt:PublishSighting(record, requested)
    return self:Publish("sighting", record, requested)
end
function PartyHunt:PublishStop(record, requested, explicit)
    return self:Publish("stop", record, requested, explicit)
end

function PartyHunt:HandleMessage(prefix, payload, channel, sender)
    if prefix ~= PartyHunt.PREFIX or not Text(sender, 100) then return false end
    local receive = Field(self.settings, "receive")
    if receive ~= "party" and receive ~= "raid" then return false end
    if channel == "PARTY" then
        if not Call(self.transport, "isInParty") or Call(self.transport, "isInRaid") then return false end
    elseif channel == "RAID" then
        if receive ~= "raid" or not Call(self.transport, "isInRaid") then return false end
    else return false end
    local ignored = Field(self.settings, "ignored")
    if type(ignored) == "table" and Field(ignored, sender:lower()) == true then return false end
    -- Group channels echo our own messages back to us.
    local me = self.playerName
    if not me then
        me = Text(CallResult(self.transport, "playerName"), 100)
        self.playerName = me
    end
    if me and sender:lower() == me:lower() then return false end
    local report = Decode(payload)
    if not report then return false end
    self:Prune()
    local now = self.clock()
    local bucket = self.incoming[sender]
    if not bucket or now - bucket.start >= 60 then
        bucket = { start = now, count = 0 }
        self.incoming[sender] = bucket
    end
    if bucket.count >= 20 then return false end
    bucket.count = bucket.count + 1
    local key = sender .. ":" .. report.nonce
    if self.seen[key] then return false end
    self.seen[key] = now + PartyHunt.TTL
    report.sender = sender
    report.receivedAt = now
    report.expiresAt = now + PartyHunt.TTL
    report.evidence = "group-report"
    report.phaseCompatibility = "unknown"
    report.instanceCompatibility = "unknown"
    report.nonce = nil
    self.reports[#self.reports + 1] = report
    if #self.reports > PartyHunt.MAX_REPORTS then table.remove(self.reports, 1) end
    if type(self.onReport) == "function" then pcall(self.onReport, report) end
    return true
end

function PartyHunt:OnGroupChanged()
    if not GroupChannel(self.transport) then
        self.reports, self.seen, self.incoming = {}, {}, {}
    end
end

-- Register only after a visible user control has supplied receive settings.
-- The parent owns the service lifetime and calls Stop on shutdown/reconfigure.
function PartyHunt:Start()
    local receive = Field(self.settings, "receive")
    if receive ~= "party" and receive ~= "raid" then return false end
    if self.frame then
        self.active, self.deferredStop = true, nil
        return true
    end
    -- Retail can reject event registration while combat lockdown is active.
    -- The radar's already registered regen event retries this opt-in start.
    if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
        return false, "combat-lockdown"
    end
    if type(CreateFrame) ~= "function" then return false end
    if not self.registered then
        if not RegisterSucceeded(CallResult(self.transport, "register", PartyHunt.PREFIX)) then
            return false, "prefix-unavailable"
        end
        self.registered = true
    end
    local frame = CreateFrame("Frame")
    if not frame then return false end
    local owner = self
    frame:SetScript("OnEvent", function(_, event, ...)
        if not owner.active then return end
        if event == "CHAT_MSG_ADDON" then owner:HandleMessage(...)
        elseif event == "GROUP_ROSTER_UPDATE" then owner:OnGroupChanged() end
    end)
    local ok = pcall(function()
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    end)
    if not ok then
        pcall(frame.UnregisterAllEvents, frame)
        return false, "event-unavailable"
    end
    self.active = true
    self.frame = frame
    return true
end

function PartyHunt:Stop()
    self.active = false
    if self.frame then
        if type(InCombatLockdown) == "function" and InCombatLockdown() == true then
            self.deferredStop = true
        else
            pcall(self.frame.UnregisterAllEvents, self.frame)
            self.frame, self.deferredStop = nil, nil
        end
    end
    self.reports, self.seen, self.incoming = {}, {}, {}
end
