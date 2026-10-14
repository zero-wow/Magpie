local _, addon = ...
if type(addon) ~= "table" then return end

-- Quest conditions are explicit metadata. A missing vignette is not evidence
-- of a phase ID, so heuristic warnings never hide a saved point.
local API = {}
addon.VignetteRadarPhaseLens = API

local MAX_POINTS, MAX_CONDITIONS, MAX_OBSERVED_QUESTS = 256, 8, 16
local ACTIONS = { show=true, dim=true, hide=true }
local EVIDENCE = { bundled=true, ["trusted-pack"]=true, manual=true }

local Safe, Field, Text = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Text

local function ID(value)
    return Safe(value) and type(value) == "number" and value > 0
        and value <= 100000000 and value == math.floor(value) and value or nil
end

local function Time(value)
    return Safe(value) and type(value) == "number" and value == value
        and value >= 0 and value <= 4102444800 and value or nil
end

local function QuestStates(raw)
    local result, count, inspected = {}, 0, 0
    if type(raw) ~= "table" then return result end
    for questID, complete in pairs(raw) do
        inspected = inspected + 1
        if inspected > MAX_OBSERVED_QUESTS * 2 then break end
        local id = ID(questID)
        if id and type(complete) == "boolean" then
            result[id], count = complete, count + 1
            if count >= MAX_OBSERVED_QUESTS then break end
        end
    end
    return result
end

local function Conditions(raw)
    local result = {}
    if type(raw) ~= "table" then return result end
    for index = 1, math.min(#raw, MAX_CONDITIONS) do
        local row = raw[index]
        local questID = ID(Field(row, "questID"))
        local complete = Field(row, "complete")
        if questID and type(complete) == "boolean" then
            result[#result+1] = { questID=questID, complete=complete }
        end
    end
    return result
end

function API.New(options)
    return setmetatable({ action=ACTIONS[Field(options, "action")]
        and options.action or "show", heuristic=Field(options, "heuristic") == true,
        observations={}, overrides={} }, { __index=API })
end

function API:SetOverride(pointKey, action)
    local key = Text(pointKey, 160)
    if not key or (action ~= nil and not ACTIONS[action]) then return false end
    if action and not self.overrides[key] then
        local count = 0
        for _ in pairs(self.overrides) do count = count + 1 end
        if count >= MAX_POINTS then return false end
    end
    self.overrides[key] = action
    return true
end

function API:SetOptions(options)
    local action = Field(options, "action")
    if ACTIONS[action] then self.action = action end
    local heuristic = Field(options, "heuristic")
    if type(heuristic) == "boolean" then self.heuristic = heuristic end
end

function API:RecordSighting(pointKey, observation)
    local key = Text(pointKey, 160)
    local at = Time(Field(observation, "at"))
    if not key or not at or Field(observation, "evidence") ~= "live" then return false end
    local previous = self.observations[key]
    if previous and at < previous.at then return false end
    if not previous then
        local count, oldest, oldestAt = 0, nil, nil
        for id, entry in pairs(self.observations) do
            count = count + 1
            if not oldestAt or entry.at < oldestAt then oldest, oldestAt = id, entry.at end
        end
        if count >= MAX_POINTS then self.observations[oldest] = nil end
    end
    self.observations[key] = { at=at, questStates=QuestStates(Field(observation, "questStates")) }
    return true
end

function API:Evaluate(point, context)
    local key = Text(Field(point, "key"), 160)
    local live = Field(point, "evidence") == "live" or Field(point, "isLive") == true
    if live then
        return { status="live", action="show", reason="Locally detected" }
    end
    local override = key and self.overrides[key]
    if override then
        return { status="override", action=override, reason="Player override" }
    end
    local conditions = Conditions(Field(point, "phaseConditions"))
    local conditionEvidence = Field(point, "phaseEvidence")
    if #conditions > 0 and EVIDENCE[conditionEvidence] then
        local resolver = Field(context, "questComplete")
        if type(resolver) ~= "function" then
            return { status="unknown", action="show", reason="Quest state unavailable" }
        end
        local unknown, mismatched
        for _, condition in ipairs(conditions) do
            local ok, complete = pcall(resolver, condition.questID)
            if not ok or type(complete) ~= "boolean" or not Safe(complete) then
                unknown = true
            elseif complete ~= condition.complete then
                mismatched = true
            end
        end
        if mismatched then
            return { status="condition-mismatch", action=self.action,
                reason="Explicit quest condition differs", evidence=conditionEvidence,
                conditions=conditions }
        end
        if unknown then
            return { status="unknown", action="show", reason="Quest condition unverified",
                evidence=conditionEvidence, conditions=conditions }
        end
        return { status="condition-match", action="show",
            reason="Explicit quest conditions match", evidence=conditionEvidence,
            conditions=conditions }
    end
    local observed = key and self.observations[key]
    if self.heuristic and observed and Field(context, "absent") == true then
        local current = QuestStates(Field(context, "questStates"))
        for questID, oldState in pairs(observed.questStates) do
            if current[questID] ~= nil and current[questID] ~= oldState then
                return { status="possible-mismatch", action="show",
                    reason="Quest state differs from a prior local sighting",
                    evidence="observation", observedAt=observed.at }
            end
        end
    end
    return { status="unknown", action="show", reason="Phase not exposed" }
end

function API:ClearObservation(pointKey)
    local key = Text(pointKey, 160)
    if key and self.observations[key] then
        self.observations[key] = nil
        return true
    end
    return false
end
