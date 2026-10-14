local _, addon = ...
if type(addon) ~= "table" then return end

-- A reset boundary can make a repeatable goal expected; only a direct
-- availability observation can confirm that the player can do it now.
local API = {}
addon.VignetteRadarResetPlanner = API

local MAX_GOALS = 256
local TYPES = { daily=true, weekly=true, ["one-time"]=true, unknown=true }

local Safe, Field = addon.Secret.Safe, addon.Secret.Field

local function Label(value, limit)
    return Safe(value) and type(value) == "string" and #value > 0
        and #value <= limit and value or nil
end

local function Time(value)
    return Safe(value) and type(value) == "number" and value == value
        and value >= 0 and value <= 4102444800 and value or nil
end

local function Metadata(raw)
    local kind = Field(raw, "resetKind")
    local source = Field(raw, "source")
    if not TYPES[kind] then kind = "unknown" end
    if source ~= "api" and source ~= "trusted-pack" and source ~= "user-rule" then
        source = "unknown"
    end
    if source == "unknown" then kind = "unknown" end
    return kind, source
end

local function Period(kind, periods)
    if kind ~= "daily" and kind ~= "weekly" then return nil end
    if Field(periods, "verifiedReset") ~= true then return nil end
    return Label(Field(periods, kind), 64)
end

function API.New(saved)
    local planner = { goals={} }
    if saved and Field(saved, "version") ~= 1 then saved = nil end
    local records = Field(saved, "goals")
    if type(records) == "table" then
        local count, inspected = 0, 0
        for id, raw in pairs(records) do
            inspected = inspected + 1
            if inspected > MAX_GOALS * 2 then break end
            local key, kind, source = Label(id, 100), Metadata(raw)
            if key then
                planner.goals[key] = {
                    resetKind=kind, source=source,
                    complete=Field(raw, "complete") == true,
                    completedPeriod=Label(Field(raw, "completedPeriod"), 64),
                    confirmedPeriod=Label(Field(raw, "confirmedPeriod"), 64),
                    confirmedSession=Label(Field(raw, "confirmedSession"), 64),
                    observedAt=Time(Field(raw, "observedAt")),
                    name=Label(Field(raw, "name"), 100) or key,
                    category=Label(Field(raw, "category"), 40),
                }
                count = count + 1
                if count >= MAX_GOALS then break end
            end
        end
    end
    return setmetatable(planner, { __index=API })
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function API:SetGoal(id, metadata)
    local key = Label(id, 100)
    if not key or type(metadata) ~= "table" then return false end
    if not self.goals[key] and Count(self.goals) >= MAX_GOALS then return false end
    local kind, source = Metadata(metadata)
    local old = self.goals[key]
    self.goals[key] = {
        resetKind=kind, source=source,
        complete=old and old.complete or false,
        completedPeriod=old and old.completedPeriod,
        confirmedPeriod=old and old.confirmedPeriod,
        confirmedSession=old and old.confirmedSession,
        observedAt=old and old.observedAt,
        name=Label(Field(metadata, "name"), 100) or key,
        category=Label(Field(metadata, "category"), 40),
    }
    return true
end

function API:Observe(id, observation, periods, now)
    local record = self.goals[id]
    local at = Time(now)
    if not record or not at or (record.observedAt and at < record.observedAt) then
        return false
    end
    if observation ~= "available" and observation ~= "completed" and observation ~= "unknown" then
        return false
    end
    record.observedAt = at
    if observation == "available" then
        record.confirmedPeriod = Period(record.resetKind, periods)
        record.confirmedSession = Label(Field(periods, "sessionID"), 64)
        record.complete = false
    elseif observation == "completed" then
        record.complete = true
        record.completedPeriod = Period(record.resetKind, periods)
        record.confirmedPeriod = nil
        record.confirmedSession = nil
    else
        record.confirmedPeriod = nil
        record.confirmedSession = nil
    end
    return true
end

function API:Evaluate(id, periods)
    local record = self.goals[id]
    if not record then return { status="Unknown", reason="No reset metadata" } end
    local kind = record.resetKind
    local current = Period(kind, periods)
    local session = Label(Field(periods, "sessionID"), 64)
    local sessionConfirmed = session and record.confirmedSession == session
    local result = { id=id, name=record.name, category=record.category,
        resetKind=kind, source=record.source, observedAt=record.observedAt }
    if kind == "one-time" and record.complete then
        result.status, result.reason, result.queue = "Completed", "One-time goal completed", false
    elseif (kind == "one-time" or kind == "unknown") and sessionConfirmed then
        result.status, result.reason, result.queue = "Confirmed", "Availability observed this session", true
    elseif kind == "unknown" then
        result.status, result.reason, result.queue = "Unknown", "Reset type unknown", false
    elseif kind == "one-time" then
        result.status, result.reason, result.queue = "Unknown", "Availability not observed", false
    elseif not current then
        result.status, result.reason, result.queue = "Unknown", "Reset period unavailable", false
    elseif record.complete and record.completedPeriod == current then
        result.status, result.reason, result.queue = "Completed", "Completed this period", false
    elseif record.confirmedPeriod == current then
        result.status, result.reason, result.queue = "Confirmed", "Availability observed this period", true
    elseif record.complete and record.completedPeriod and record.completedPeriod ~= current then
        result.status, result.reason, result.queue = "Expected", "New reset period; availability unconfirmed", true
    elseif record.complete then
        result.status, result.reason, result.queue = "Unknown", "Completion period unknown", false
    else
        result.status, result.reason, result.queue = "Unknown", "Availability not observed", false
    end
    return result
end

function API:GetQueue(periods, categories)
    local result = {}
    for id, record in pairs(self.goals) do
        if type(categories) ~= "table" or categories[record.category] ~= false then
            local evaluated = self:Evaluate(id, periods)
            if evaluated.queue then result[#result+1] = evaluated end
        end
    end
    table.sort(result, function(a, b)
        if a.status ~= b.status then return a.status == "Confirmed" end
        return a.name < b.name
    end)
    return result
end

function API:Export()
    return { version=1, goals=self.goals }
end
