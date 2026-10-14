local _, addon = ...
if type(addon) ~= "table" then return end

-- Temporary presentation state. Nothing here writes SavedVariables or frames.
local Director = {}
addon.VignetteRadarContextDirector = Director

local ORDER = { "cave", "group", "treasure", "questing", "travel" }
local LABELS = { cave = "Cave", group = "Group", treasure = "Treasure Hunt",
    questing = "Questing", travel = "Travel" }
local MAX_FILTERS, MAX_NAME = 16, 48

local Safe, Field = addon.Secret.Safe, addon.Secret.Field
local SecretNumber = addon.Secret.Number

local function Number(value, default, minimum, maximum)
    value = SecretNumber(value)
    if value == nil then return default end
    return math.max(minimum, math.min(maximum, value))
end

local function CopyPreset(config)
    local preset = Field(config, "preset")
    local range = Number(Field(config, "range"), nil, 10, 6000)
    local filters = Field(config, "filters")
    local result = { preset = type(preset) == "string" and #preset <= MAX_NAME
        and preset or nil, range = range,
        audio = Field(config, "audio") == true, filters = {} }
    if type(filters) == "table" and Safe(filters) then
        local count = 0
        for key, value in pairs(filters) do
            if count >= MAX_FILTERS then break end
            if type(key) == "string" and #key <= MAX_NAME and type(value) == "boolean" then
                result.filters[key] = value
                count = count + 1
            end
        end
    end
    return result
end

-- settings is the director's own copy, so it is indexed directly.
local function Context(snapshot, settings)
    if type(snapshot) ~= "table" or not Safe(snapshot) then return nil end
    local contexts = settings.contexts
    for index = 1, #ORDER do
        local name = ORDER[index]
        if contexts[name].enabled and Field(snapshot, name) == true then
            return name
        end
    end
end

function Director.New(settings)
    local self = { settings = {}, active = nil, candidate = nil,
        candidateSince = nil, heldUntil = 0, locked = false,
        applied = nil, appliedRevision = nil, revision = 0, lastError = nil }
    setmetatable(self, { __index = Director })
    self:Configure(settings)
    return self
end

local function SamePreset(a, b)
    if a.enabled ~= b.enabled or a.preset ~= b.preset or a.range ~= b.range
        or a.audio ~= b.audio then return false end
    for key, value in pairs(a.filters) do
        if b.filters[key] ~= value then return false end
    end
    for key in pairs(b.filters) do
        if a.filters[key] == nil then return false end
    end
    return true
end

local function SameSettings(a, b)
    if not (a and b and a.contexts and b.contexts) then return false end
    if a.enabled ~= b.enabled or a.enterSeconds ~= b.enterSeconds
        or a.exitSeconds ~= b.exitSeconds
        or a.manualHoldSeconds ~= b.manualHoldSeconds then return false end
    for index = 1, #ORDER do
        local name = ORDER[index]
        if not SamePreset(a.contexts[name], b.contexts[name]) then return false end
    end
    return true
end

function Director:Configure(settings)
    settings = type(settings) == "table" and Safe(settings) and settings or {}
    local sourceContexts = Field(settings, "contexts")
    local contexts = {}
    for _, name in ipairs(ORDER) do
        local source = Field(sourceContexts, name)
        local preset = CopyPreset(source)
        preset.enabled = Field(source, "enabled") == true
        contexts[name] = preset
    end
    local normalized = {
        enabled = Field(settings, "enabled") == true,
        enterSeconds = Number(Field(settings, "enterSeconds"), 2.5, 0, 30),
        exitSeconds = Number(Field(settings, "exitSeconds"), 2.5, 0, 30),
        manualHoldSeconds = Number(Field(settings, "manualHoldSeconds"), 30, 0, 600),
        contexts = contexts,
    }
    -- Only a real change bumps the revision; it forces the overlay to reapply.
    if SameSettings(self.settings, normalized) then return end
    self.settings = normalized
    self.revision = (self.revision or 0) + 1
end

function Director:ManualOverride(now, seconds)
    now = Number(now, 0, 0, 1e12)
    seconds = Number(seconds, self.settings.manualHoldSeconds, 0, 600)
    self.heldUntil = math.max(self.heldUntil, now + seconds)
end

function Director:SetLocked(locked)
    self.locked = locked == true
end

local function Desired(self, now)
    if not self.settings.enabled or self.locked or now < self.heldUntil then return nil end
    local name = self.active
    if not name then return nil end
    local source = self.settings.contexts[name]
    if not source or not source.enabled then return nil end
    return { context = name, label = LABELS[name], preset = source.preset,
        range = source.range, audio = source.audio, filters = source.filters }
end

-- Call on relevant events. apply(overlay) must modify only transient UI state and
-- return true on success. On combat deferral or failure, the previously applied
-- view remains; a later event can retry without a timer or per-frame polling.
function Director:Update(snapshot, now, apply, protected)
    now = Number(now, 0, 0, 1e12)
    local candidate = self.settings.enabled and Context(snapshot, self.settings) or nil
    if candidate ~= self.candidate then
        self.candidate, self.candidateSince = candidate, now
    end
    if candidate ~= self.active then
        local delay = candidate and self.settings.enterSeconds or self.settings.exitSeconds
        if now - (self.candidateSince or now) >= delay then self.active = candidate end
    end
    local desired = Desired(self, now)
    local desiredName = desired and desired.context or nil
    if desiredName == self.applied and self.appliedRevision == self.revision then
        return desired, "unchanged"
    end
    if type(apply) ~= "function" then return desired, "pending" end
    if protected == true then return desired, "deferred" end
    local ok, result = pcall(apply, desired)
    if not ok or result == false then
        self.lastError = ok and "Apply rejected" or "Apply failed"
        return desired, "failed"
    end
    self.applied, self.appliedRevision, self.lastError = desiredName, self.revision, nil
    return desired, "applied"
end

function Director:GetState(now)
    now = Number(now, 0, 0, 1e12)
    return { active = self.active, candidate = self.candidate,
        overlay = Desired(self, now), applied = self.applied,
        locked = self.locked, manualHoldRemaining = math.max(0, self.heldUntil - now),
        error = self.lastError }
end
