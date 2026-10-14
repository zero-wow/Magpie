local _, addon = ...
if type(addon) ~= "table" then return end

-- Shared guards for Blizzard secret values. Every module binds these as
-- locals (local Field = addon.Secret.Field) instead of keeping its own copy.
-- issecretvalue is read on every call so tests and late API loads still work.
local Secret = {}
addon.Secret = Secret

local type, pcall, floor, HUGE = type, pcall, math.floor, math.huge

-- True when value is secret. A failing issecretvalue counts as secret.
local function IsSecret(value)
    local check = issecretvalue
    if type(check) ~= "function" then return false end
    local ok, secret = pcall(check, value)
    return not ok or (secret and true or false)
end

local function Safe(value)
    return not IsSecret(value)
end

-- One static getter: pcall passes record and key as arguments, so a field
-- read allocates no closure and stays re-entrant through __index.
local function GetField(record, key)
    return record[key]
end

-- Reads record[key] without letting an error or a secret through.
-- Keeps false; returns nil for secret or non-table records.
local function Field(record, key)
    if type(record) ~= "table" or IsSecret(record) then return nil end
    local ok, value = pcall(GetField, record, key)
    if not ok or IsSecret(value) then return nil end
    return value
end

-- A finite, non-secret number, or nil.
local function Number(value)
    if type(value) ~= "number" or IsSecret(value) or value ~= value
        or value == HUGE or value == -HUGE then return nil end
    return value
end

-- A whole Number inside the optional [minimum, maximum] bounds, or nil.
local function Integer(value, minimum, maximum)
    value = Number(value)
    if not value or value ~= floor(value) then return nil end
    if (minimum and value < minimum) or (maximum and value > maximum) then return nil end
    return value
end

-- A non-empty, non-secret string. Over limit it is rejected, or cut to
-- limit when truncate is set.
local function Text(value, limit, truncate)
    if type(value) ~= "string" or IsSecret(value) or value == "" then return nil end
    if limit and #value > limit then
        if not truncate then return nil end
        return value:sub(1, limit)
    end
    return value
end

local function Results(ok, a, b, c)
    if not ok then return nil end
    if IsSecret(a) then a = nil end
    if IsSecret(b) then b = nil end
    if IsSecret(c) then c = nil end
    return a, b, c
end

-- Calls owner[name](...) with the read and the call both guarded.
-- Returns up to three results; a secret result comes back as nil.
local function Call(owner, name, ...)
    local callback = Field(owner, name)
    if type(callback) ~= "function" then return nil end
    return Results(pcall(callback, ...))
end

Secret.IsSecret = IsSecret
Secret.Safe = Safe
Secret.Field = Field
Secret.Number = Number
Secret.Integer = Integer
Secret.Text = Text
Secret.Call = Call
