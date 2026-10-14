local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarFeatures = API

local MAX_TARGETS, MAX_RECENT, MAX_SESSION_IGNORED = 256, 256, 256
local GLOBAL_ALERT_SECONDS, PULSE_SECONDS = 3, 3
local activeMapID, initialized, previewing = nil, false, false
local live, stale, recent, sessionIgnored = {}, {}, {}, {}
local lastAlertAt = -math.huge

local IsSecret, Field = addon.Secret.IsSecret, addon.Secret.Field
local Number, String = addon.Secret.Number, addon.Secret.Text

local function Settings()
    return type(addon.GetSettings) == "function" and addon.GetSettings() or {}
end

local function BoundedNumber(value, default, minimum, maximum)
    value = Number(value)
    return value and math.max(minimum, math.min(maximum, value)) or default
end

local function Identity(target)
    local id = Number(Field(target, "vignetteID")) or String(Field(target, "vignetteID"))
    if not id then
        local guid = String(Field(target, "key"))
        id = guid and guid:match("^Vignette%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or nil
    end
    if id then return "id:" .. tostring(id) end

    local name = String(Field(target, "name"))
    if not name then return nil end
    local category = String(Field(target, "category")) or "other"
    local mapID = Number(Field(target, "mapID")) or activeMapID
    return "name:" .. tostring(mapID or "unknown") .. ":" .. category .. ":" .. name:lower()
end

local function MarkerNameKey(target)
    local name = String(Field(target, "name"))
    if not name then return nil end
    local category = String(Field(target, "category")) or "other"
    return category:lower() .. ":" .. name:lower()
end

local function MapNoteNameKey(note)
    local name = String(Field(note, "name"))
    local kind = String(Field(note, "kind"))
    return name and kind and "map:" .. kind:lower() .. ":" .. name:lower() or nil
end

local function MarkerTypeKey(target)
    local atlas = String(Field(target, "atlasName"))
    if atlas then
        local lower = atlas:lower()
        local vendor = lower:find("vendor", 1, true) or lower:find("vender", 1, true)
            or lower:find("merchant", 1, true)
        local decor = lower:find("decor", 1, true) or lower:find("housing", 1, true)
        local item = lower:find("item", 1, true) or lower:find("goods", 1, true)
        if vendor and decor and item then return "class:decor-vendor-items" end
        if vendor and decor then return "class:decor-vendors" end
        if vendor and item then return "class:vendor-items" end
        if vendor then return "class:vendors" end
        if lower:find("mailbox", 1, true) then return "class:mailboxes" end
        return "atlas:" .. lower
    end
    local vignetteType = Number(Field(target, "vignetteType"))
    if vignetteType then return "vignette:" .. tostring(vignetteType) end
    local category = String(Field(target, "category"))
    return category and "category:" .. category:lower() or nil
end

local function MapNoteTypeKey(note)
    local icon = Field(note, "icon")
    local texture = Field(icon, "texture")
    if Number(texture) or String(texture) then
        local key = "texture:" .. tostring(texture):lower()
        local coords = Field(icon, "texCoord")
        if type(coords) == "table" and not IsSecret(coords) then
            for index = 1, 4 do
                local coord = Number(Field(coords, index))
                if not coord then break end
                key = key .. ":" .. math.floor(coord * 10000 + .5)
            end
        end
        return key
    end
    local kind = String(Field(note, "kind"))
    return kind and "map-kind:" .. kind:lower() or nil
end

local function TableSetting(settings, key)
    local value = settings[key]
    if type(value) ~= "table" or IsSecret(value) then
        value = {}
        settings[key] = value
    end
    return value
end

function API.IsFavorite(target)
    local identity = Identity(target)
    return identity ~= nil and Field(TableSetting(Settings(), "vignetteRadarFavorites"), identity) == true or false
end

function API.ToggleFavorite(target)
    local identity = Identity(target)
    if not identity then return false, "no-stable-identity" end
    local favorites = TableSetting(Settings(), "vignetteRadarFavorites")
    local enabled = favorites[identity] ~= true
    favorites[identity] = enabled or nil
    return enabled
end

function API.IsIgnored(target)
    local settings = Settings()
    local names = TableSetting(settings, "vignetteRadarHiddenMarkerNames")
    if next(names) then
        local nameKey = MarkerNameKey(target)
        if nameKey and Field(names, nameKey) ~= nil then return true end
    end
    local types = TableSetting(settings, "vignetteRadarHiddenMarkerTypes")
    if next(types) then
        local typeKey = MarkerTypeKey(target)
        if typeKey and Field(types, typeKey) ~= nil then return true end
    end
    local identity = Identity(target)
    return identity ~= nil and (sessionIgnored[identity] == true
            or Field(TableSetting(settings, "vignetteRadarIgnored"), identity) == true)
        or false
end

function API.IsMarkerNameHidden(target)
    local key = MarkerNameKey(target)
    return key ~= nil and Field(TableSetting(Settings(), "vignetteRadarHiddenMarkerNames"), key) ~= nil or false
end

function API.IsMapNoteNameHidden(note)
    local key = MapNoteNameKey(note)
    return key ~= nil and Field(TableSetting(Settings(), "vignetteRadarHiddenMarkerNames"), key) ~= nil or false
end

function API.MarkerTypeKey(target) return MarkerTypeKey(target) end
function API.MapNoteTypeKey(note) return MapNoteTypeKey(note) end

function API.IsMarkerTypeHidden(target)
    local key = MarkerTypeKey(target)
    return key ~= nil and Field(TableSetting(Settings(), "vignetteRadarHiddenMarkerTypes"), key) ~= nil or false
end

function API.IsMapNoteTypeHidden(note)
    local key = MapNoteTypeKey(note)
    return key ~= nil and Field(TableSetting(Settings(), "vignetteRadarHiddenMarkerTypes"), key) ~= nil or false
end

function API.SetMarkerTypeHidden(entry, hidden)
    local key = String(Field(entry, "typeKey"))
    if not key then return false, "no-marker-type" end
    local types = TableSetting(Settings(), "vignetteRadarHiddenMarkerTypes")
    if hidden == true then
        local atlas = String(Field(entry, "atlasName"))
        local texture = Field(entry, "texture")
        local coords = Field(entry, "texCoord")
        local color = Field(entry, "color")
        local saved = { label = (String(Field(entry, "label")) or key):sub(1, 100) }
        if atlas then saved.atlasName = atlas:sub(1, 120) end
        if Number(texture) or String(texture) then saved.texture = texture end
        if type(coords) == "table" and not IsSecret(coords) then
            saved.texCoord = {}
            for index = 1, 4 do saved.texCoord[index] = Number(Field(coords, index)) end
        end
        if type(color) == "table" and not IsSecret(color) then
            saved.color = {}
            for index = 1, 4 do saved.color[index] = Number(Field(color, index)) end
        end
        types[key] = saved
    else
        types[key] = nil
    end
    return true
end

function API.GetHiddenMarkerTypes()
    return TableSetting(Settings(), "vignetteRadarHiddenMarkerTypes")
end

function API.SetMarkerNameHidden(target, hidden)
    local key = MarkerNameKey(target)
    if not key then return false, "no-marker-name" end
    local names = TableSetting(Settings(), "vignetteRadarHiddenMarkerNames")
    names[key] = hidden == true and Field(target, "name") or nil
    return true
end

function API.GetHiddenMarkerNames()
    return TableSetting(Settings(), "vignetteRadarHiddenMarkerNames")
end

function API.Ignore(target, permanent)
    local identity = Identity(target)
    if not identity then return false, "no-stable-identity" end
    if permanent == true then
        TableSetting(Settings(), "vignetteRadarIgnored")[identity] = true
    else
        sessionIgnored[identity] = true
        local count, oldestKey = 0, nil
        for key in pairs(sessionIgnored) do
            count = count + 1
            if not oldestKey then oldestKey = key end
        end
        if count > MAX_SESSION_IGNORED then sessionIgnored[oldestKey] = nil end
    end
    return true
end

function API.ClearIgnored()
    Settings().vignetteRadarIgnored = {}
    Settings().vignetteRadarHiddenMarkerNames = {}
    Settings().vignetteRadarHiddenMarkerTypes = {}
    sessionIgnored = {}
end

local function InCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, combat = pcall(InCombatLockdown)
    return not ok or IsSecret(combat) or combat == true
end

local function InInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    return not ok or IsSecret(inside) or inside == true
end

function API.IsQuiet()
    local settings = Settings()
    return (settings.vignetteRadarQuietCombat ~= false and InCombat())
        or (settings.vignetteRadarQuietInstances ~= false and InInstance())
end

function API.IsVisuallyQuiet()
    local settings = Settings()
    -- Retain the saved key for compatibility. The eye now overrides every
    -- automatic visual fade; IsQuiet still controls alert muting separately.
    if settings.vignetteRadarKeepVisibleCombat == true then return false end
    return InCombat() or (settings.vignetteRadarQuietInstances ~= false and InInstance())
end

function API.IsWorldBoss(info)
    local questID = Number(Field(info, "rewardQuestID"))
    if not questID or questID <= 0 or not (C_QuestLog and type(C_QuestLog.GetQuestTagInfo) == "function") then
        return false
    end
    local ok, tagInfo = pcall(C_QuestLog.GetQuestTagInfo, questID)
    if not ok or not tagInfo or IsSecret(tagInfo) then return false end
    local questTags = Enum and Field(Enum, "QuestTagType")
    local bossType = Number(Field(questTags, "WorldBoss"))
    local actualType = Number(Field(tagInfo, "worldQuestType"))
    if bossType and actualType == bossType then return true end

    -- Blizzard still identifies legacy world-boss world quests this way.
    local normalType = Number(Field(questTags, "Normal"))
    local qualities = Enum and Field(Enum, "WorldQuestQuality")
    local epicQuality = Number(Field(qualities, "Epic"))
    return normalType ~= nil and epicQuality ~= nil and actualType == normalType
        and Field(tagInfo, "isElite") == true
        and Number(Field(tagInfo, "quality")) == epicQuality or false
end

local SNAPSHOT_FIELDS = {
    "key", "vignetteID", "name", "category", "mapID", "mapX", "mapY",
    "worldX", "worldY", "instanceID", "atlasName", "vignetteType", "isWorldBoss", "source",
    "objectGUID", "rewardQuestID",
}

local function Snapshot(target, mapID, now)
    local copy = {}
    for _, field in ipairs(SNAPSHOT_FIELDS) do
        local value = Field(target, field)
        if type(value) == "string" or type(value) == "number"
            or (field == "isWorldBoss" and type(value) == "boolean") then
            copy[field] = value
        end
    end
    copy.mapID = mapID
    copy.lastSeenAt = now
    return copy
end

local function Reset(mapID)
    live, stale, recent = {}, {}, {}
    activeMapID, initialized = mapID, false
    lastAlertAt = -math.huge
end

local function TrimRecent(now, cooldown)
    local count = 0
    for identity, timestamp in pairs(recent) do
        if now - timestamp >= cooldown then
            recent[identity] = nil
        else
            count = count + 1
        end
    end
    while count > MAX_RECENT do
        local oldestKey, oldestTime
        for identity, timestamp in pairs(recent) do
            if not oldestTime or timestamp < oldestTime then
                oldestKey, oldestTime = identity, timestamp
            end
        end
        if not oldestKey then break end
        recent[oldestKey] = nil
        count = count - 1
    end
end

local function CategoryMayAlert(settings, target)
    local category = String(Field(target, "category")) or "other"
    local alerts = settings.vignetteRadarAlertCategories
    if type(alerts) ~= "table" or Field(alerts, category) ~= true then return false end
    local categories = settings.vignetteRadarCategories
    if type(categories) == "table" and Field(categories, category) == false then return false end
    local legend = addon.VignetteRadarLegend
    if type(legend) == "table" and type(legend.IsCategoryEnabled) == "function" then
        local ok, enabled = pcall(legend.IsCategoryEnabled, category)
        if not ok or enabled == false then return false end
    end
    return true
end

-- Returns visible live and fading snapshots, followed by fresh alert candidates.
function API.Update(targets, mapID, now, context)
    local settings = Settings()
    local enabled = Field(context, "enabled") == true
    local preview = Field(context, "preview") == true
    mapID, now = Number(mapID), Number(now)
    if not enabled or preview or not mapID or not now then
        Reset(nil)
        previewing = preview
        return preview and (type(targets) == "table" and targets or {}) or {}, {}
    end
    previewing = false
    if activeMapID ~= mapID then Reset(mapID) end

    local firstScan = not initialized
    initialized = true
    local output, alerts, candidates, nextLive = {}, {}, {}, {}
    local seen, seenIdentities = {}, {}
    local cooldown = BoundedNumber(settings.vignetteRadarAlertCooldown, 60, 5, 3600)
    local fadeSeconds = BoundedNumber(settings.vignetteRadarLastSeenSeconds, 10, 1, 60)
    local canAlert = not firstScan and settings.vignetteRadarAlerts == true and not API.IsQuiet()

    if type(targets) == "table" and not IsSecret(targets) then
        for index = 1, math.min(#targets, 512) do
            local target = targets[index]
            local key = String(Field(target, "key"))
            if #output < MAX_TARGETS and key and not seen[key] and not API.IsIgnored(target)
                and not (addon.VignetteRadarRecent and addon.VignetteRadarRecent.IsHidden(target, settings)) then
                seen[key] = true
                local previous = live[key]
                local identity = Identity(target)
                if identity then seenIdentities[identity] = true end
                local favorite = API.IsFavorite(target)
                target.favorite = favorite
                target.stale, target.fading = nil, nil
                target.newUntil = previous and previous.newUntil or nil
                local snapshot = Snapshot(target, mapID, now)
                nextLive[key] = { snapshot = snapshot, newUntil = target.newUntil, identity = identity }
                stale[key] = nil
                output[#output + 1] = target
                if canAlert and not previous and identity and CategoryMayAlert(settings, target)
                    and (not recent[identity] or now - recent[identity] >= cooldown)
                    and (not addon.VignetteRadarAlertTiers or addon.VignetteRadarAlertTiers.Worth(target, settings)) then
                    candidates[#candidates + 1] = target
                end
                if not previous and identity then recent[identity] = now end
            end
        end
    end

    for key, entry in pairs(live) do
        if not nextLive[key] and not seenIdentities[entry.identity]
            and not stale[key] and settings.vignetteRadarLastSeen == true
            and not API.IsIgnored(entry.snapshot)
            and not (addon.VignetteRadarRecent and addon.VignetteRadarRecent.IsHidden(entry.snapshot, settings)) then
            local snapshot = entry.snapshot
            snapshot.stale = true
            snapshot.expiresAt = now + fadeSeconds
            snapshot.favorite = API.IsFavorite(snapshot)
            snapshot.newUntil = nil
            stale[key] = snapshot
        end
    end
    live = nextLive
    if settings.vignetteRadarLastSeen == true then
        for key, snapshot in pairs(stale) do
            if snapshot.expiresAt <= now or API.IsIgnored(snapshot) or seenIdentities[Identity(snapshot)]
                or (addon.VignetteRadarRecent and addon.VignetteRadarRecent.IsHidden(snapshot, settings)) then
                stale[key] = nil
            end
        end
        local staleCount = 0
        for _ in pairs(stale) do staleCount = staleCount + 1 end
        while staleCount > MAX_TARGETS - #output do
            local oldestKey, oldestAt
            for key, snapshot in pairs(stale) do
                if not oldestAt or snapshot.lastSeenAt < oldestAt then
                    oldestKey, oldestAt = key, snapshot.lastSeenAt
                end
            end
            if not oldestKey then break end
            stale[oldestKey] = nil
            staleCount = staleCount - 1
        end
        for _, snapshot in pairs(stale) do
            snapshot.fading = math.max(0, (snapshot.expiresAt - now) / fadeSeconds)
            snapshot.favorite = API.IsFavorite(snapshot)
            output[#output + 1] = snapshot
        end
    else
        stale = {}
    end

    if #candidates > 0 and now - lastAlertAt >= GLOBAL_ALERT_SECONDS then
        table.sort(candidates, function(left, right)
            if left.favorite ~= right.favorite then return left.favorite end
            return left.key < right.key
        end)
        local selected = candidates[1]
        selected.newUntil = now + PULSE_SECONDS
        nextLive[selected.key].newUntil = selected.newUntil
        alerts[1] = selected
        lastAlertAt = now
        recent[nextLive[selected.key].identity] = now
    end
    TrimRecent(now, cooldown)
    return output, alerts
end

local function CurrentLive(target)
    local key = String(Field(target, "key"))
    if previewing or not activeMapID or not key or Field(target, "stale") == true then return nil end
    return live[key]
end

function API.Navigate(target)
    local entry = CurrentLive(target)
    if not entry then return false, "not-live" end
    local key = entry.snapshot.key
    if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedVignette) == "function" then
        local ok, result = pcall(C_SuperTrack.SetSuperTrackedVignette, key)
        if ok and not IsSecret(result) and result ~= false then return true, "vignette" end
    end
    local mapID, x, y = entry.snapshot.mapID, entry.snapshot.mapX, entry.snapshot.mapY
    if not (Number(mapID) and Number(x) and Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return false, "no-map-position"
    end
    if not (UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function"
        and C_Map and type(C_Map.SetUserWaypoint) == "function") then
        return false, "waypoint-unavailable"
    end
    if type(C_Map.CanSetUserWaypointOnMap) == "function" then
        local allowed, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
        if not allowed or IsSecret(canSet) or canSet == false then return false, "waypoint-unavailable" end
    end
    local ok, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, x, y)
    if not ok or not point or IsSecret(point) then return false, "waypoint-unavailable" end
    local placed, result = pcall(C_Map.SetUserWaypoint, point)
    if not placed or IsSecret(result) or result == false then return false, "waypoint-failed" end
    if C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return true, "waypoint"
end

-- Blizzard passes this 0..1 value to FormatPercentage, which multiplies by 100.
function API.GetHealth(target)
    local entry = CurrentLive(target)
    if not entry or entry.snapshot.category ~= "rare" or Settings().vignetteRadarShowHealth ~= true then return nil end
    if not (C_VignetteInfo and type(C_VignetteInfo.GetHealthPercent) == "function") then return nil end
    local ok, percent = pcall(C_VignetteInfo.GetHealthPercent, entry.snapshot.key)
    if not ok then return nil end
    percent = Number(percent)
    if percent and percent >= 0 and percent <= 1 then return percent * 100 end
    return nil
end
