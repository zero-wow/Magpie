local _, addon = ...
if type(addon) ~= "table" then return end

-- Data-only character snapshots. Offline quest eligibility is never live state.
local API = {}
addon.VignetteRadarWarbandBoard = API

local MAX_CHARACTERS, MAX_GOALS, MAX_REWARDS = 16, 256, 512
local DEFAULT_STALE = 7 * 86400

local Safe, Field, Text = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Text

local function Timestamp(value)
    return Safe(value) and type(value) == "number" and value == value
        and value >= 0 and value <= 4102444800 and value or nil
end

local function GoalState(value)
    if type(value) ~= "table" then return nil end
    local eligibility = Field(value, "eligibility")
    if eligibility ~= "available" and eligibility ~= "unavailable" then
        eligibility = "unknown"
    end
    local completion = Field(value, "completion")
    if type(completion) ~= "boolean" then completion = nil end
    local evidence = Text(Field(value, "evidence"), 48)
    -- A naked boolean is not proof that a character can take a quest.
    if eligibility ~= "unknown" and evidence ~= "api" and evidence ~= "manual" then
        eligibility = "unknown"
    end
    return { eligibility=eligibility, completion=completion, evidence=evidence }
end

local function CopyGoals(raw)
    local goals, count, inspected = {}, 0, 0
    if type(raw) ~= "table" then return goals end
    for key, value in pairs(raw) do
        inspected = inspected + 1
        if inspected > MAX_GOALS * 2 then break end
        local id = Text(key, 100)
        local state = GoalState(value)
        if id and state then
            goals[id], count = state, count + 1
            if count >= MAX_GOALS then break end
        end
    end
    return goals
end

function API.New(saved, options)
    local board = { characters={}, collections={}, staleAfter=DEFAULT_STALE }
    if saved and Field(saved, "version") ~= 1 then saved = nil end
    local stale = Field(options, "staleAfter")
    if Timestamp(stale) and stale >= 60 and stale <= 90 * 86400 then
        board.staleAfter = stale
    end
    local chars = Field(saved, "characters")
    if type(chars) == "table" then
        local count, inspected = 0, 0
        for key, raw in pairs(chars) do
            inspected = inspected + 1
            if inspected > MAX_CHARACTERS * 2 then break end
            local id, at = Text(key, 100), Timestamp(Field(raw, "lastSeenAt"))
            if id and at then
                board.characters[id] = {
                    name=Text(Field(raw, "name"), 100) or id,
                    lastSeenAt=at, favorite=Field(raw, "favorite") == true,
                    goals=CopyGoals(Field(raw, "goals")),
                }
                count = count + 1
                if count >= MAX_CHARACTERS then break end
            end
        end
    end
    local rewards = Field(saved, "collections")
    if type(rewards) == "table" then
        local count, inspected = 0, 0
        for key, raw in pairs(rewards) do
            inspected = inspected + 1
            if inspected > MAX_REWARDS * 2 then break end
            local id, at = Text(key, 100), Timestamp(Field(raw, "observedAt"))
            local collected, evidence = Field(raw, "collected"), Text(Field(raw, "evidence"), 48)
            if id and at and type(collected) == "boolean"
                and (evidence == "api" or evidence == "manual") then
                board.collections[id] = { collected=collected, observedAt=at, evidence=evidence }
                count = count + 1
                if count >= MAX_REWARDS then break end
            end
        end
    end
    return setmetatable(board, { __index=API })
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function Oldest(t, key)
    local name, at
    for id, entry in pairs(t) do
        local value = entry[key] or 0
        if not at or value < at then name, at = id, value end
    end
    return name
end

function API:UpdateCharacter(characterKey, snapshot, now)
    local id, at = Text(characterKey, 100), Timestamp(now)
    if not id or not at or type(snapshot) ~= "table" then return false end
    local old = self.characters[id]
    if old and at < old.lastSeenAt then return false end
    if not old and Count(self.characters) >= MAX_CHARACTERS then
        self.characters[Oldest(self.characters, "lastSeenAt")] = nil
    end
    self.characters[id] = {
        name=Text(Field(snapshot, "name"), 100) or id,
        lastSeenAt=at,
        favorite=old and old.favorite or false,
        goals=CopyGoals(Field(snapshot, "goals")),
    }
    return true
end

function API:SetFavorite(characterKey, favorite)
    local entry = self.characters[characterKey]
    if not entry or type(favorite) ~= "boolean" then return false end
    entry.favorite = favorite
    return true
end

function API:SetCollection(rewardKey, collected, evidence, now)
    local id, at = Text(rewardKey, 100), Timestamp(now)
    if not id or not at or type(collected) ~= "boolean"
        or (evidence ~= "api" and evidence ~= "manual") then return false end
    local previous = self.collections[id]
    if previous and at < previous.observedAt then return false end
    if not previous and Count(self.collections) >= MAX_REWARDS then
        self.collections[Oldest(self.collections, "observedAt")] = nil
    end
    self.collections[id] = { collected=collected, evidence=evidence, observedAt=at }
    return true
end

function API:GetCollection(rewardKey)
    local entry = self.collections[rewardKey]
    if not entry then return { status="unknown" } end
    return { status=entry.collected and "collected" or "uncollected",
        evidence=entry.evidence, observedAt=entry.observedAt }
end

function API:GetBoard(goalKey, now, currentCharacter)
    local goal, at = Text(goalKey, 100), Timestamp(now)
    if not goal or not at then return {} end
    local result = {}
    for id, entry in pairs(self.characters) do
        local observed = entry.goals[goal]
        local stale = at < entry.lastSeenAt
            or at - entry.lastSeenAt > self.staleAfter
        local offline = id ~= currentCharacter
        local eligibility = observed and observed.eligibility or "unknown"
        if stale then eligibility = "unknown" end
        result[#result+1] = {
            character=id, name=entry.name, favorite=entry.favorite,
            offline=offline, stale=stale, lastSeenAt=entry.lastSeenAt,
            eligibility=eligibility,
            observedEligibility=observed and observed.eligibility or "unknown",
            completion=observed and observed.completion,
            evidence=observed and observed.evidence,
        }
    end
    table.sort(result, function(a, b)
        if a.favorite ~= b.favorite then return a.favorite end
        if a.lastSeenAt ~= b.lastSeenAt then return a.lastSeenAt > b.lastSeenAt end
        return a.character < b.character
    end)
    return result
end

function API:Suggest(goalKey, now, currentCharacter)
    local rows = self:GetBoard(goalKey, now, currentCharacter)
    for _, row in ipairs(rows) do
        if row.eligibility == "available" and row.completion ~= true then
            return row
        end
    end
    return nil, "No confirmed eligible character"
end

function API:Export()
    return { version=1, characters=self.characters, collections=self.collections }
end
