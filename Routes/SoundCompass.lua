local _, addon = ...
if type(addon) ~= "table" then return end

-- Event-driven cue decisions for one active destination. An adapter can play a
-- proven client sound or speech API; this module never starts a timer or polls.
local Compass = {}
addon.VignetteRadarSoundCompass = Compass

local WORDS = { ahead = "Ahead", left = "Left", right = "Right", behind = "Behind" }

local Safe, Field = addon.Secret.Safe, addon.Secret.Field
local SecretNumber = addon.Secret.Number

local function Number(value, default, minimum, maximum)
    value = SecretNumber(value)
    if value == nil then return default end
    return math.max(minimum, math.min(maximum, value))
end

local function Bucket(angle, previous, hysteresis)
    local magnitude = math.abs(angle)
    if previous == "ahead" and magnitude < 25 + hysteresis then return "ahead" end
    if previous == "behind" and magnitude > 155 - hysteresis then return "behind" end
    if previous == "left" and angle < -(25 - hysteresis)
        and angle > -(155 + hysteresis) then return "left" end
    if previous == "right" and angle > 25 - hysteresis
        and angle < 155 + hysteresis then return "right" end
    if magnitude >= 155 then return "behind" end
    if magnitude <= 25 then return "ahead" end
    return angle < 0 and "left" or "right"
end

function Compass.New(settings)
    local self = setmetatable({ targetID = nil, bucket = nil,
        lastCueAt = -math.huge, nearSent = false }, { __index = Compass })
    self:Configure(settings)
    return self
end

function Compass:Configure(settings)
    settings = type(settings) == "table" and Safe(settings) and settings or {}
    local mode = Field(settings, "mode")
    if mode ~= "speech" and mode ~= "tone" then mode = "text" end
    self.settings = { enabled = Field(settings, "enabled") == true,
        mode = mode, volume = Number(Field(settings, "volume"), .7, 0, 1),
        cooldown = Number(Field(settings, "cooldown"), 6, 2, 60),
        nearDistance = Number(Field(settings, "nearDistance"), 40, 3, 300),
        hysteresis = Number(Field(settings, "hysteresis"), 10, 0, 20),
        quietCombat = Field(settings, "quietCombat") ~= false,
        quietInstance = Field(settings, "quietInstance") ~= false }
end

function Compass:Mute()
    self.settings.enabled = false
end

function Compass:Update(destination, now, emit)
    now = Number(now, 0, 0, 1e12)
    local id = Field(destination, "id")
    local angle = Number(Field(destination, "relativeDegrees"), nil, -180, 180)
    local distance = Number(Field(destination, "distance"), nil, 0, 1e7)
    if (type(id) ~= "string" and type(id) ~= "number") or not Safe(id)
        or angle == nil or distance == nil then
        self.targetID, self.bucket, self.nearSent = nil, nil, false
        return nil, nil
    end
    if id ~= self.targetID then
        self.targetID, self.bucket, self.nearSent = id, nil, false
    end
    local previous = self.bucket
    local bucket = Bucket(angle, previous, self.settings.hysteresis)
    self.bucket = bucket
    local name = Field(destination, "name")
    if type(name) ~= "string" or #name > 80 then name = "Destination" end
    local near = distance <= self.settings.nearDistance
    local textState = { targetID = id, name = name, direction = bucket,
        directionText = WORDS[bucket], distance = distance,
        label = name .. " | " .. WORDS[bucket] .. " | " .. math.floor(distance + .5) .. " yd" }
    if not self.settings.enabled or self.settings.mode == "text"
        or (self.settings.quietCombat and Field(destination, "inCombat") == true)
        or (self.settings.quietInstance and Field(destination, "inInstance") == true) then
        return textState, nil
    end
    local cueKind
    if near and not self.nearSent then
        cueKind = "near"
    elseif previous ~= bucket then
        cueKind = bucket
    end
    if not cueKind or now - self.lastCueAt < self.settings.cooldown then
        return textState, nil
    end
    local cue = { kind = cueKind, mode = self.settings.mode,
        volume = self.settings.volume, targetID = id,
        text = cueKind == "near" and "Approaching " .. name
            or WORDS[bucket] .. ": " .. name }
    self.lastCueAt = now
    if cueKind == "near" then self.nearSent = true end
    if type(emit) == "function" then
        local ok, result = pcall(emit, cue)
        if not ok or result == false then
            cue.unavailable = true
            cue.mode = "text"
        end
    end
    return textState, cue
end
