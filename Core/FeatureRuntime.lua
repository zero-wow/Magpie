local _, addon = ...
if type(addon) ~= "table" then return end

-- Owns optional feature lifetimes: login, leaving combat and logout arrive
-- through the bus; scans arrive from the radar. Nothing registers a new event
-- or shares data until its user setting enables it.
local Runtime = {}
addon.VignetteRadarFeatureRuntime = Runtime

local initialized, party, surveyState = false, nil, {}
local previousMapID, previousTargets = nil, {}
local board, planner, phaseLens
local director, soundCompass, lastSurveyFlush

local Safe = addon.Secret.Safe

-- Reused every Observe so the director update allocates nothing per scan.
local directorSnapshot = { group = false, treasure = false, questing = false, travel = false }
local DIRECTOR_CONTEXTS = {
    travel = { enabled = true, range = 1200 },
    questing = { enabled = true, range = 300 },
    treasure = { enabled = true, range = 150 },
    group = { enabled = true, range = 450 },
}

local function ApplyOverlay(overlay)
    addon.VignetteRadarContextOverlay = overlay
    return true
end

-- GetRoutePoint returns (step, kind). Call it directly: an `and` chain
-- would cut the results to one value and lose kind.
local function RoutePoint()
    local focus = addon.VignetteRadarWorldFocus
    local getPoint = focus and focus.GetRoutePoint
    if type(getPoint) ~= "function" then return nil, nil, focus end
    local step, kind = getPoint()
    return step, kind, focus
end

local function Clock()
    local elapsed = type(GetTime) == "function" and GetTime() or nil
    local epoch = type(GetServerTime) == "function" and GetServerTime()
        or type(time) == "function" and time() or nil
    return type(elapsed) == "number" and elapsed or nil,
        type(epoch) == "number" and epoch or nil
end

local function CharacterKey()
    if type(UnitGUID) == "function" then
        local ok, guid = pcall(UnitGUID, "player")
        if ok and Safe(guid) and type(guid) == "string" and #guid <= 80 then
            return guid
        end
    end
    return "current-character"
end

local function QuestFlag(method, questID)
    local fn = C_QuestLog and C_QuestLog[method]
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, questID)
    return ok and Safe(value) and value == true
end

local function Signal(kind, target, epoch)
    local survey = addon.VignetteRadarSurveyReplay
    if not (survey and target and type(target.mapID) == "number"
        and type(target.mapX) == "number" and type(target.mapY) == "number") then return end
    local identity = tostring(target.key or target.objectGUID or target.npcID or "point")
        :gsub("[^%w:_.%-]", ""):sub(1, 80)
    local source = tostring(target.source or "local"):gsub("[%c|]", ""):sub(1, 40)
    local name = tostring(target.name or "Signal"):gsub("[%c|]", ""):sub(1, 80)
    if identity == "" then return end
    survey.RecordSignal({ kind = kind, source = source, evidence = "live",
        identity = identity, name = name,
        point = { mapID = target.mapID, mapX = target.mapX,
            mapY = target.mapY, worldX = target.worldX,
            worldY = target.worldY, instanceID = target.instanceID } }, epoch)
end

function Runtime.Initialize()
    if initialized then return true end
    local db = addon.GetSettings()
    if type(db.vignetteRadarSurveyData) ~= "table" then db.vignetteRadarSurveyData = {} end
    local survey = addon.VignetteRadarSurveyReplay
    if survey then survey.Initialize(db.vignetteRadarSurveyData, CharacterKey()) end
    local hunt = addon.VignetteRadarPartyHunt
    if hunt then
        party = hunt.New(db.vignetteRadarPartyHunt or {}, function()
            local ui = addon.VignetteRadarSurveyParty
            if ui and ui.IsOpen and ui.IsOpen() then ui.Refresh() end
        end)
    end
    local warband = addon.VignetteRadarWarbandBoard
    if warband then
        board = warband.New(db.vignetteRadarWarbandBoardData,
            { staleAfter = (db.vignetteRadarWarbandStaleDays or 7) * 86400 })
    end
    local resets = addon.VignetteRadarResetPlanner
    if resets then planner = resets.New(db.vignetteRadarResetPlannerData) end
    local phases = addon.VignetteRadarPhaseLens
    if phases then phaseLens = phases.New({ action = db.vignetteRadarPhaseLensAction or "show",
        heuristic = db.vignetteRadarPhaseHeuristics == true }) end
    local context = addon.VignetteRadarContextDirector
    if context then director = context.New({ enabled = false }) end
    local compass = addon.VignetteRadarSoundCompass
    if compass then soundCompass = compass.New({ enabled = false }) end
    initialized = true
    Runtime.Configure()
    return true
end

function Runtime.Configure()
    if not initialized then return false end
    local db = addon.GetSettings()
    local survey = addon.VignetteRadarSurveyReplay
    if survey then
        local size = db.vignetteRadarSurveyCellSize
        if size ~= surveyState.size then
            survey.SetCellSize(size)
            surveyState.size = size
        end
        local surveying = db.vignetteRadarSurveying == true
        if surveying ~= surveyState.surveying then
            survey.SetSurveying(surveying)
            surveyState.surveying = surveying
        end
        local recording = db.vignetteRadarReplayRecording == true
        if recording ~= surveyState.recording then
            survey.SetRecording(recording)
            surveyState.recording = recording
            previousMapID, previousTargets = nil, {}
        end
    end
    if party then
        party:SetSettings(db.vignetteRadarPartyHunt)
        if db.vignetteRadarPartyHunt.receive ~= "off" then
            pcall(party.Start, party)
        end
    end
    if director then
        director:Configure({ enabled = db.vignetteRadarContextDirectorEnabled,
            contexts = DIRECTOR_CONTEXTS })
    end
    if soundCompass then
        soundCompass:Configure({ enabled = db.vignetteRadarSoundCompassEnabled,
            mode = db.vignetteRadarSoundCompassMode,
            cooldown = db.vignetteRadarSoundCompassCooldown,
            quietCombat = true, quietInstance = true })
    end
    return true
end

function Runtime.GetDirector() return director end
function Runtime.GetSoundCompass() return soundCompass end

function Runtime.ManualViewOverride()
    if director and type(GetTime) == "function" then
        director:ManualOverride(GetTime())
    end
end

function Runtime.RefreshIntelligence()
    if not initialized then Runtime.Initialize() end
    local ui = addon.VignetteRadarIntelligence
    if not ui then return false end
    local db = addon.GetSettings()
    local epoch = type(GetServerTime) == "function" and GetServerTime()
        or type(time) == "function" and time() or 0
    local character = CharacterKey()
    local name = type(UnitName) == "function" and UnitName("player") or character
    if not Safe(name) or type(name) ~= "string" then name = character end
    local step, kind, focus = RoutePoint()
    if not step and focus and focus.GetFocusedStep then
        step = focus.GetFocusedStep()
        kind = step and step.kind
    end
    local goalKey = step and tostring(step.questID and ("quest:" .. step.questID)
        or step.key or step.sourceID or "")
    if goalKey == "" then goalKey = nil end
    if board then
        local goals = {}
        local previous = board.characters and board.characters[character]
        local copied = 0
        if previous and type(previous.goals) == "table" then
            for key, value in pairs(previous.goals) do
                goals[key] = value
                copied = copied + 1
                if copied >= 255 then break end
            end
        end
        if step and step.questID and goalKey then
            local questID = step.questID
            local completed = QuestFlag("IsQuestFlaggedCompleted", questID)
            local active = QuestFlag("IsOnQuest", questID)
            goals[goalKey] = { eligibility = active and "available"
                or completed and "unavailable" or "unknown",
                completion = completed, evidence = (active or completed) and "api" or nil }
        end
        board:UpdateCharacter(character, { name = name, goals = goals }, epoch)
        db.vignetteRadarWarbandBoardData = board:Export()
    end
    if planner then db.vignetteRadarResetPlannerData = planner:Export() end
    ui.SetContext({ board = board, resetPlanner = planner,
        phaseLens = phaseLens,
        getNow = function() return epoch end,
        getCurrentCharacter = function() return character end,
        getResetPeriods = function() return {} end,
        getPhaseContext = function() return {} end,
        onIntelligenceChange = function(kind, model)
            if kind == "resetPlanner" and model and model.Export then
                db.vignetteRadarResetPlannerData = model:Export()
                return true
            end
            return false
        end })
    ui.SetSelection({ goalKey = goalKey, goalName = step and step.name,
        goalCategory = kind, sourceKey = step and (step.sourceID or step.key),
        point = step })
    return true
end

function Runtime.Observe(mapID, player, targets)
    if not initialized then return end
    local elapsed, epoch = Clock()
    if not (elapsed and epoch) then return end
    if director then
        local step, kind = RoutePoint()
        local snapshot = directorSnapshot
        snapshot.group = type(IsInGroup) == "function" and IsInGroup() == true
        snapshot.treasure = step and kind == "treasure" or false
        snapshot.questing = step and kind == "quest" or false
        snapshot.travel = type(IsMounted) == "function" and IsMounted() == true
        director:Update(snapshot, elapsed, ApplyOverlay,
            addon.Bus and addon.Bus.InCombat() or false)
    end
    if not (surveyState.surveying or surveyState.recording) then return end
    local survey = addon.VignetteRadarSurveyReplay
    if survey and (surveyState.surveying or surveyState.recording) then
        survey.Sample(player, elapsed, epoch)
        if not lastSurveyFlush or elapsed - lastSurveyFlush >= 60 then
            survey.Flush()
            lastSurveyFlush = elapsed
        end
    end
    if not surveyState.recording then return end
    if mapID ~= previousMapID then
        previousMapID, previousTargets = mapID, {}
    end
    local current = {}
    if type(targets) == "table" then
        for index = 1, math.min(#targets, 128) do
            local target = targets[index]
            if type(target) == "table" and not target.stale
                and target.mapID == mapID and type(target.mapX) == "number"
                and type(target.mapY) == "number" then
                local key = tostring(target.key or target.objectGUID or index)
                current[key] = target
                if not previousTargets[key] then Signal("appeared", target, epoch) end
            end
        end
    end
    for key, target in pairs(previousTargets) do
        if not current[key] then Signal("vanished", target, epoch) end
    end
    previousTargets = current
end

function Runtime.GetParty() return party end

function Runtime.ShareSighting(record, requested)
    if not (initialized and party) then return false, "Party Hunt unavailable" end
    return party:PublishSighting(record, requested)
end

function Runtime.ShareStop(record, requested, explicit)
    if not (initialized and party) then return false, "Party Hunt unavailable" end
    return party:PublishStop(record, requested, explicit)
end

function Runtime.Shutdown()
    if not initialized then return end
    local survey = addon.VignetteRadarSurveyReplay
    if survey then survey.Flush(); survey.ClearSession() end
    if party then party:Stop() end
    initialized, party, surveyState = false, nil, {}
    previousMapID, previousTargets = nil, {}
    board, planner, phaseLens = nil, nil, nil
    director, soundCompass, lastSurveyFlush = nil, nil, nil
end

-- PartyHunt may defer a start or stop while in combat; leaving combat retries.
if addon.Bus then
    addon.Bus.On("LOGIN", function() Runtime.Initialize() end)
    addon.Bus.On("PLAYER_REGEN_ENABLED", function() Runtime.Configure() end)
    addon.Bus.On("LOGOUT", function() Runtime.Shutdown() end)
end
