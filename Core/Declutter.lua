local _, addon = ...
if type(addon) ~= "table" then return end

-- Declutter: one pass over the scan's map-pack notes, before they reach the
-- point registry, so the radar, Bearing Bar, Auto Route and every other
-- reader see the same short list. A note is dropped when:
--   done       its quest is flagged done for this character, or for the
--              account while Blizzard's "account completed quests" minimap
--              tracking is off
--   duplicate  a live vignette of the same kind sits within 60 yd
--   killed     Recent saw it killed or cleared since the daily reset
--   live       "packs only when nothing live" is on and a rare or treasure is up
--   range      "packs only within" is set and the note is farther away
--   collected  Collection Lens "hide"/"only" and the pack's loot says there
--              is nothing left to collect (Data/CollectionLens.lua)
-- Guide steps, the World Focus destination, Blizzard's own area POIs
-- (events, delves, races: live, not pack data) and collection-tracked
-- points (Data/CollectionTracking.lua) are never dropped.
--   Declutter.Apply(notes, targets, player [, settings]) -> notes
--   Declutter.Done(questID) -> bool
--   Declutter.LastCounts() -> { done, duplicate, killed, live, range }
local Declutter = {}
addon.VignetteRadarDeclutter = Declutter

local type, ipairs, pcall = type, ipairs, pcall
local Field, Number, Integer, SecretCall = addon.Secret.Field, addon.Secret.Number,
    addon.Secret.Integer, addon.Secret.Call

local DUPLICATE_YARDS, QUEST_SECONDS, DAY = 60, 30, 86400
local DUPLICATE_KINDS = { treasure = "treasure", mob = "rare", rare = "rare" }
local questCache, counts = {}, { done = 0, duplicate = 0, killed = 0, live = 0, range = 0, collected = 0 }
local lastSummary

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, now = pcall(GetTime)
    return ok and Number(now) or 0
end

local function Flag(name, questID)
    return SecretCall(C_QuestLog, name, questID) == true
end

-- Done for this character, or for the account unless the player asked the
-- minimap to keep showing account-completed quests. Cached for 30 s and
-- cleared on quest changes.
function Declutter.Done(questID)
    questID = Integer(questID, 1)
    if not questID then return false end
    local now = Now()
    local cached = questCache[questID]
    if cached and now - cached.at < QUEST_SECONDS then return cached.done end
    local done = Flag("IsQuestFlaggedCompleted", questID)
    if not done and SecretCall(C_Minimap, "IsTrackingAccountCompletedQuests") ~= true then
        done = Flag("IsQuestFlaggedCompletedOnAccount", questID)
    end
    questCache[questID] = { done = done, at = now }
    return done
end

function Declutter.Invalidate()
    questCache = {}
end
if addon.Bus then addon.Bus.On("QUEST_TURNED_IN", function() Declutter.Invalidate() end) end

-- Seconds since the daily reset, never less than an hour (Recent's own
-- window) and never more than a day.
local function SinceDailyReset()
    local untilReset = Number(SecretCall(C_DateAndTime, "GetSecondsUntilDailyReset"))
    if not untilReset or untilReset < 0 or untilReset > DAY then return DAY end
    return math.max(3600, DAY - untilReset)
end

local function LiveTargets(targets)
    local live = {}
    for _, target in ipairs(type(targets) == "table" and targets or {}) do
        local category = type(target) == "table" and Field(target, "category")
        if (category == "rare" or category == "treasure") and Field(target, "stale") ~= true
            and Number(Field(target, "worldX")) and Number(Field(target, "worldY")) then
            live[#live + 1] = target
        end
    end
    return live
end

local function Duplicate(note, live)
    local kind = DUPLICATE_KINDS[note.kind]
    if not kind then return false end
    local x, y = Number(note.worldX), Number(note.worldY)
    if not (x and y) then return false end
    local instance = Number(note.instanceID)
    for _, target in ipairs(live) do
        if target.category == kind then
            local ti = Number(target.instanceID)
            if not (instance and ti and instance ~= ti) then
                local dx, dy = target.worldX - x, target.worldY - y
                if dx * dx + dy * dy <= DUPLICATE_YARDS * DUPLICATE_YARDS then return true end
            end
        end
    end
    return false
end

local function FocusKey()
    local world = addon.VignetteRadarWorldFocus
    local item = world and world.GetActiveTarget and world.GetActiveTarget()
    return type(item) == "table" and item.key or nil
end

local function Trace(settings)
    local trace = addon.Trace
    if not (trace and trace.IsOn()) then return end
    local summary = string.format(
        "done=%d duplicate=%d killed=%d live=%d range=%d collected=%d (on=%s liveOnly=%s within=%s)",
        counts.done, counts.duplicate, counts.killed, counts.live, counts.range, counts.collected,
        tostring(settings.vignetteRadarDeclutter), tostring(settings.vignetteRadarDeclutterLiveOnly),
        tostring(settings.vignetteRadarDeclutterRange))
    if summary ~= lastSummary then
        lastSummary = summary
        trace.Log("declutter", "hid notes: %s", summary)
    end
end

-- Returns the notes to keep. notes itself is returned untouched when every
-- declutter switch is off.
function Declutter.Apply(notes, targets, player, settings)
    settings = settings or addon.GetSettings()
    counts.done, counts.duplicate, counts.killed, counts.live, counts.range = 0, 0, 0, 0, 0
    counts.collected = 0
    local hideDone = settings.vignetteRadarDeclutter == true
    local liveOnly = settings.vignetteRadarDeclutterLiveOnly == true
    local within = Number(settings.vignetteRadarDeclutterRange)
    within = within and within > 0 and within or nil
    -- The Collection Lens learns the pack loot even when it only marks.
    local lens = addon.VignetteRadarCollectionLens
    local lensMode = lens and lens.Mode(settings) or "off"
    if lens and lensMode ~= "off" and type(notes) == "table" then lens.Learn(notes) end
    local lensHides = lensMode == "hide" or lensMode == "only"
    if type(notes) ~= "table" or not (hideDone or liveOnly or within or lensHides) then return notes end
    local live = LiveTargets(targets)
    local anyLive = #live > 0
    local px, py = player and Number(player.worldX), player and Number(player.worldY)
    local recent = addon.VignetteRadarRecent
    local resetWindow = hideDone and recent and recent.KilledWithin and SinceDailyReset() or nil
    local focusKey = FocusKey()
    local kept = {}
    for _, note in ipairs(notes) do
        local reason
        if note.kind ~= "guide" and not note.areaPoiID and not note.contentTracking
            and not (focusKey and note.key == focusKey) then
            if liveOnly and anyLive then reason = "live"
            elseif within and px and py and Number(note.worldX) and Number(note.worldY) then
                local dx, dy = note.worldX - px, note.worldY - py
                if dx * dx + dy * dy > within * within then reason = "range" end
            end
            if not reason and hideDone then
                if Declutter.Done(note.questID) then reason = "done"
                elseif Duplicate(note, live) then reason = "duplicate"
                elseif resetWindow and recent.KilledWithin(note, resetWindow, nil, settings) then
                    reason = "killed"
                end
            end
            if not reason and lensHides and lens.Hide(note, settings) then reason = "collected" end
        end
        if reason then counts[reason] = counts[reason] + 1 else kept[#kept + 1] = note end
    end
    Trace(settings)
    return kept
end

function Declutter.LastCounts() return counts end

return Declutter
