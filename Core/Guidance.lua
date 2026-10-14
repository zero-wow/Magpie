local _, addon = ...
if type(addon) ~= "table" then return end

-- Guidance: the one feed behind the Guide Panel (UI/GuidePanel.lua). It reads
-- World Focus (the focused point, its path step, the route and its horizon),
-- the point registry, travel speed and quest data, and builds one snapshot of
-- "where next". The snapshot is rebuilt on events (FOCUS_CHANGED,
-- ROUTE_CHANGED, POINTS_CHANGED, MAP_CHANGED, COMBAT, LOGIN, ZYGOR_STEP),
-- never per frame. Quest progress (QUEST_CHANGED) only marks the snapshot
-- stale: no timer, no work in the event; the .5 s ticker rebuilds it, so a
-- burst of quest events costs one rebuild. Yards, ETA and the facts refresh
-- on that ONE .5 s ticker, which runs only while the panel shows
-- (Guidance.Watch).
--   Guidance.Snapshot() -> { mode, target, stops, route, step, facts,
--                            briefing, notice, revision }
--     mode = "route" | "focus" | "arrival" | "idle"
--     Stop = { item, name, kind, kindTitle, progress, yards, eta, dx, dy,
--              color = { r, g, b }, current }
--   Guidance.Lines(block, snapshot) -> { { label, value, item }, ... } (pure)
--   Guidance.StopName(item) / Guidance.StopLabel(item) / Guidance.KindTitle(kind)
--   Guidance.Yards(yards) / Guidance.Eta(yards)
--   Guidance.FactLines(item [, player [, now]]) / Guidance.AddTooltipLines(tooltip, item)
--   Guidance.Count(mapID) / Guidance.BriefingText(counts) / Guidance.Arrive([now])
--   Guidance.Notice(label, text [, objective]) -> true when the Guide Panel shows it
--   Guidance.Watch(on) / Guidance.Tick([now]) / Guidance.Invalidate()
-- Bus topic GUIDANCE_CHANGED: a new snapshot is due (coalesced per frame).
local Guidance = {}
addon.VignetteRadarGuidance = Guidance

local type, ipairs, pairs, floor = type, ipairs, pairs, math.floor
local Field, Number, Text, SecretCall = addon.Secret.Field, addon.Secret.Number,
    addon.Secret.Text, addon.Secret.Call

local TICK = "VignetteRadarGuidance"
-- A non-breaking space keeps "236 yd" or "5 treasures left" whole when a
-- line wraps.
local NBSP = "\194\160"
local SEP = " · "
local REBRIEF_SECONDS, MIN_GAP = 600, 30
local NOTICE_SECONDS, NOTICE_DETAILED = 3.4, 5
Guidance.MAX_STOPS = 5
-- compass reads the Compass feed (Core/Compass.lua), not this snapshot.
Guidance.BLOCKS = { "step", "facts", "stops", "compass", "briefing", "actions", "notice" }

local KIND_TITLE = { quest = "Quest", treasure = "Treasure", rare = "Rare", mob = "Rare",
    boss = "World Boss", guide = "Zygor", zygor = "Zygor", exploration = "Map Note",
    event = "Event", entrance = "Cave Entrance", item = "Item", note = "Map Note" }

local snapshot = { mode = "idle", stops = {}, facts = {}, revision = 0 }
local dirty, signature = true, nil
-- Set by quest events; the next tick turns it into one rebuild.
local questDirty = false
local armed, briefedAt, lastBriefAt, arrival = false, {}, nil, nil
local notice

local function Settings() return addon.GetSettings() end

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function Epoch()
    local clock = type(GetServerTime) == "function" and GetServerTime or time
    if type(clock) ~= "function" then return nil end
    local ok, value = pcall(clock)
    return ok and Number(value) or nil
end

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("guide", fmt, ...) end
end

local function Whole(text)
    return (tostring(text):gsub(" ", NBSP))
end

-- Names ---------------------------------------------------------------------

function Guidance.KindTitle(kind)
    return KIND_TITLE[kind] or "Point"
end

local function ZoneName(mapID)
    mapID = Number(mapID)
    if not (mapID and C_Map and type(C_Map.GetMapInfo) == "function") then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mapID)
    return ok and type(info) == "table" and Text(info.name) or nil
end

-- A point's own name, or "<Kind> · <Zone>" when a map pack only gave it a
-- stand-in ("Treasure location"; Points.IsPlaceholderName).
function Guidance.StopName(item)
    if type(item) ~= "table" then return "Route Stop" end
    local name = Text(Field(item, "name"))
    local points = addon.VignetteRadarPoints
    if name and not (points and points.IsPlaceholderName and points.IsPlaceholderName(name)) then
        return name
    end
    local kind = points and points.Kind and points.Kind(item) or Text(Field(item, "kind"))
    return Guidance.KindTitle(kind) .. SEP .. (ZoneName(Field(item, "mapID")) or "Unnamed")
end

-- A stop's line in a list: a quest objective names the step better than its
-- quest title (World Focus HorizonLabel), anything else its name.
function Guidance.StopLabel(item)
    if type(item) == "table" and item.kind == "quest" and not item.availableStart then
        local objective = item.objectiveText or item.nextStep and item.nextStep.text
        if type(objective) == "string" and objective ~= "" then return objective end
    end
    return Guidance.StopName(item)
end

function Guidance.Yards(yards)
    yards = Number(yards)
    if not yards then return "?" end
    yards = floor(yards + .5)
    if yards < 1000 then return yards .. " yd" end
    return string.format("%.1fk yd", yards / 1000)
end

-- ETA from the shared travel reader (Core/Travel.lua: mode, smoothed speed).
function Guidance.Eta(yards)
    local travel = addon.VignetteRadarTravel
    return travel and Number(yards) and travel.EtaText(yards) or nil
end

-- Worth-It facts (were UI/WorthCard.lua) -------------------------------------

local function Ago(seconds)
    seconds = math.max(0, floor(seconds))
    if seconds < 60 then return seconds .. " s Ago" end
    if seconds < 3600 then return floor(seconds / 60) .. " min Ago" end
    if seconds < 86400 then return floor(seconds / 3600) .. " h Ago" end
    return floor(seconds / 86400) .. " d Ago"
end
Guidance.Ago = Ago

-- The scan's live record for a key, with its group size and last-seen time.
local function LiveTarget(key)
    if type(key) ~= "string" then return nil end
    local points = addon.VignetteRadarPoints
    for _, target in ipairs(points and points.Refs("live") or {}) do
        if target.key == key then return target end
    end
end

-- Blizzard's health for a live rare's vignette, as a whole percent.
local function Health(item, live)
    if (Field(item, "category") or Field(item, "kind")) ~= "rare" or not live or live.stale then return nil end
    local percent = Number(SecretCall(C_VignetteInfo, "GetHealthPercent", live.key))
    if percent and percent >= 0 and percent <= 1 then return floor(percent * 100 + .5) end
end

-- The newest journal sighting with this name (journal entries are epoch).
local function JournalSeen(name)
    local journal = Settings().vignetteRadarJournal
    if not (name and type(journal) == "table") then return nil end
    for _, entry in ipairs(journal) do
        if type(entry) == "table" and entry.name == name then return Number(entry.at) end
    end
end

-- Extra fact rows: provider(lines, item, live) appends { label, value } pairs.
Guidance.FactProviders = Guidance.FactProviders or {}

-- The facts that decide "is this worth flying to": health, suggested group,
-- yards, ETA, done today and last seen.
function Guidance.FactLines(item, player, now)
    local lines = {}
    if type(item) ~= "table" then return lines end
    local live = LiveTarget(Field(item, "key"))
    local health = Health(item, live)
    if health then lines[#lines + 1] = { "Health", health .. "%" } end
    local groupMin = Number(Field(live or item, "groupMin"))
    if groupMin and groupMin > 0 then
        local groupMax = Number(Field(live or item, "groupMax"))
        lines[#lines + 1] = { "Group", groupMax and groupMax > groupMin
            and (groupMin .. "-" .. groupMax) or tostring(groupMin) }
    end
    local points = addon.VignetteRadarPoints
    local distance = points and player and points.Distance(player, live or item)
    distance = Number(distance) and floor(distance + .5) or nil
    if distance then
        lines[#lines + 1] = { "Distance", distance .. " yd" }
        local eta = Guidance.Eta(distance)
        if eta then lines[#lines + 1] = { "ETA", eta } end
    end
    local questID = Number(Field(item, "rewardQuestID")) or Number(Field(item, "questID"))
    local declutter = addon.VignetteRadarDeclutter
    if questID and declutter and Field(item, "kind") ~= "quest" then
        lines[#lines + 1] = { "Today", declutter.Done(questID) and "Done" or "Not Done" }
    end
    if live and not live.stale then
        lines[#lines + 1] = { "Seen", "Up Now" }
    elseif live and Number(live.lastSeenAt) and Number(now) then
        lines[#lines + 1] = { "Seen", Ago(now - live.lastSeenAt) }
    else
        local at, epoch = JournalSeen(Text(Field(item, "name"))), Epoch()
        if at and epoch then lines[#lines + 1] = { "Seen", Ago(epoch - at) } end
    end
    -- Data modules add their own rows (Respawn: Data/RareSpawns.lua, Loot: Data/CollectionLens.lua).
    for _, provider in ipairs(Guidance.FactProviders) do pcall(provider, lines, live or item, live) end
    return lines
end

local function Player()
    local radar = addon.VignetteRadarAPI
    return radar and radar.GetPlayerSnapshot and radar.GetPlayerSnapshot() or nil
end

-- Hover: the facts as one compact marker tooltip line. Lines the tooltip
-- already shows (distance) are left out.
function Guidance.AddTooltipLines(tooltip, item)
    if Settings().vignetteRadarWorthTooltip ~= true or not (tooltip and tooltip.AddLine) then return end
    local parts = {}
    for _, line in ipairs(Guidance.FactLines(item, Player(), Now())) do
        if line[1] ~= "Distance" and line[1] ~= "Group" then parts[#parts + 1] = line[1] .. " " .. line[2] end
    end
    if #parts > 0 then tooltip:AddLine(table.concat(parts, SEP), .78, .86, .74, true) end
end

-- Only the facts worth reading, as one line, or nil: no defaults or empty
-- values ("No Loot Data", "Not Done"), and nothing line 2 of a short
-- tooltip already says (distance, ETA).
local QUIET_FACTS = { ["No Loot Data"] = true, ["No Collectibles"] = true, ["Checking"] = true }
function Guidance.CompactFacts(item)
    if Settings().vignetteRadarWorthTooltip ~= true then return nil end
    local parts = {}
    for _, line in ipairs(Guidance.FactLines(item, Player(), Now())) do
        local label, value = line[1], line[2]
        if label == "Today" then
            if value == "Done" then parts[#parts + 1] = "Done today" end
        elseif label ~= "Distance" and label ~= "ETA" and label ~= "Group" and not QUIET_FACTS[value] then
            parts[#parts + 1] = label .. " " .. value
        end
    end
    return #parts > 0 and table.concat(parts, SEP) or nil
end

-- Click hints for a map note tooltip as one dim line, only for the first
-- HINT_HOVERS hovers of each kind per session; nil after that.
local HINT_HOVERS, hintHovers = 3, {}
function Guidance.MapNoteHints(entry)
    if type(entry) ~= "table" then return nil end
    local kind = entry.kind or "note"
    hintHovers[kind] = (hintHovers[kind] or 0) + 1
    if hintHovers[kind] > HINT_HOVERS then return nil end
    local settings, hints = Settings(), {}
    if settings.vignetteRadarWorldFocusEnabled then hints[#hints + 1] = "Click: focus" end
    if entry.zygorPoint then hints[#hints + 1] = "Shift-click: Zygor guide" end
    if (entry.kind == "mob" or entry.kind == "treasure") and settings.vignetteRadarHideCleared then
        hints[#hints + 1] = "Right-click: hide 1 h"
    end
    return #hints > 0 and table.concat(hints, SEP) or nil
end

-- Zone briefing (was UI/ZoneBriefing.lua) ------------------------------------

-- Live rares and events up now, treasures left (live plus the decluttered
-- pack notes), and quests with a point on this map (log and tasks).
function Guidance.Count(mapID)
    local counts = { rares = 0, treasures = 0, events = 0, quests = 0 }
    local points = addon.VignetteRadarPoints
    if not points then return counts end
    for _, target in ipairs(points.Refs("live")) do
        if not target.stale then
            if target.category == "rare" then counts.rares = counts.rares + 1
            elseif target.category == "treasure" then counts.treasures = counts.treasures + 1
            elseif target.category == "event" then counts.events = counts.events + 1 end
        end
    end
    for _, note in ipairs(points.Refs("saved")) do
        if note.kind == "treasure" then counts.treasures = counts.treasures + 1
        -- Blizzard's area events and races (Data/AreaPOIs.lua) count as events.
        elseif note.kind == "event" and note.areaPoiID then counts.events = counts.events + 1 end
    end
    local quests = addon.Quests
    if quests and Number(mapID) then
        local onMap, seen = quests.OnMap(mapID), {}
        for _, list in pairs({ onMap.quests or {}, onMap.tasks or {} }) do
            for _, quest in ipairs(list) do
                local id = Number(quest.questID)
                if id and not seen[id] then seen[id] = true; counts.quests = counts.quests + 1 end
            end
        end
    end
    return counts
end

local function Part(count, one, many)
    if count <= 0 then return nil end
    return count .. " " .. (count == 1 and one or many)
end

-- "2 rares up · 5 treasures left · 1 event · 3 quests here", or nil.
function Guidance.BriefingText(counts)
    local parts = {}
    for _, part in ipairs({ Part(counts.rares, "rare up", "rares up") or false,
        Part(counts.treasures, "treasure left", "treasures left") or false,
        Part(counts.events, "event", "events") or false,
        Part(counts.quests, "quest here", "quests here") or false }) do
        if part then parts[#parts + 1] = part end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, SEP)
end

local function BlockOn(settings, id)
    local blocks = settings.vignetteRadarGuideBlocks
    return not (type(blocks) == "table" and blocks[id] == false)
end

-- The first scan of a newly entered map starts the arrival briefing. False
-- (and why) when it stays quiet: a map is briefed again only after a while.
function Guidance.Arrive(now)
    now = now or Now()
    local settings = Settings()
    if settings.vignetteRadarGuidePanel ~= true or settings.vignetteRadarEnabled == false
        or not BlockOn(settings, "briefing") then return false, "off" end
    local points = addon.VignetteRadarPoints
    local mapID = points and Number(points.View().mapID)
    if not mapID then return false, "no map" end
    if briefedAt[mapID] and now - briefedAt[mapID] < REBRIEF_SECONDS then return false, "briefed recently" end
    if lastBriefAt and now - lastBriefAt < MIN_GAP then return false, "too soon" end
    if addon.Bus and addon.Bus.InCombat() then return false, "combat" end
    briefedAt[mapID] = now
    local text = Guidance.BriefingText(Guidance.Count(mapID))
    if not text then
        Log("map %s: nothing to brief", mapID)
        return false, "nothing here"
    end
    lastBriefAt = now
    arrival = { mapID = mapID, at = now }
    dirty = true
    Log("map %s: %s", mapID, text)
    return true, text
end

-- Hovering the briefing holds it on the panel.
function Guidance.HoldBriefing(now)
    if arrival then arrival.at = now or Now() end
end

local function BriefingSeconds(settings)
    local seconds = Number(settings.vignetteRadarGuideBriefingSeconds)
    return seconds and seconds > 0 and seconds or 20
end

local function Fresh(settings, now, mapID)
    return arrival ~= nil and arrival.mapID == mapID and now - arrival.at < BriefingSeconds(settings)
end

-- Notices (the route-note toast, shown in the panel) -------------------------

function Guidance.Notice(label, text, objective)
    local panel = addon.VignetteRadarGuidePanel
    if not (panel and panel.ShowsNotices and panel.ShowsNotices()) then return false end
    if type(text) ~= "string" or text == "" then return false end
    local detail = type(objective) == "table" and Text(objective.label) or nil
    local count = detail and Text(objective.count) or nil
    notice = { label = Text(label) or "World Focus", text = text,
        detail = detail and (detail .. (count and (SEP .. count) or "")) or nil,
        expires = Now() + (detail and NOTICE_DETAILED or NOTICE_SECONDS) }
    dirty = true
    -- Notes come from inside World Focus while it changes stops; the
    -- rebuild waits a frame (coalesced) so it never reads half a change.
    if addon.Bus then addon.Bus.Emit("GUIDANCE_NOTICE") end
    return true
end

-- Snapshot -------------------------------------------------------------------

local function TargetColor(item, kind)
    local world = addon.VignetteRadarWorldFocus
    local r, g, b
    if world and world.TargetColor then r, g, b = world.TargetColor(item) end
    if not (Number(r) and Number(g) and Number(b)) then
        local style = addon.VignetteRadarStyle
        if style and style.Color then r, g, b = style.Color(KIND_TITLE[kind] and kind ~= "guide" and kind or "accent") end
    end
    if not (Number(r) and Number(g) and Number(b)) then r, g, b = .55, .88, .82 end
    return { r, g, b }
end

-- Entrance / Approach / Treasure on a treasure's path, Quest Start for a
-- quest you have not picked up yet.
local function StepTitle(kind, item, index, count)
    local title = Guidance.KindTitle(kind)
    if kind == "quest" and item.availableStart then title = "Quest Start" end
    if kind == "treasure" and Number(count) and count > 1 then
        title = index == 1 and "Entrance" or index < count and "Approach" or "Treasure"
    end
    return title
end

-- Sound Compass cue player, shared by every update instead of a new closure.
local function PlayCompassCue(cue)
    if cue.mode ~= "tone" or type(PlaySound) ~= "function" or not SOUNDKIT then return false end
    local sound = cue.kind == "left" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        or cue.kind == "right" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
        or SOUNDKIT.TELL_MESSAGE
    if not sound then return false end
    return (pcall(PlaySound, sound, "SFX"))
end

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- The optional Sound Compass direction cue for a route stop.
local function CompassCue(settings, target, player)
    if not (settings.vignetteRadarSoundCompassEnabled and target.dx and Number(player and player.facing)) then
        return nil
    end
    local runtime = addon.VignetteRadarFeatureRuntime
    local compass = runtime and runtime.GetSoundCompass and runtime.GetSoundCompass()
    if not compass then return nil end
    local angle = atan2(target.dy, target.dx) - player.facing
    angle = atan2(math.sin(angle), math.cos(angle)) * 180 / math.pi
    local state = compass:Update({ id = tostring(target.item.key or target.item.questID or target.name),
        name = target.name, relativeDegrees = angle, distance = target.yards,
        inCombat = addon.Bus and addon.Bus.InCombat() or false,
        inInstance = type(IsInInstance) == "function" and IsInInstance() == true },
        Now(), PlayCompassCue)
    return state and state.directionText or nil
end

-- Yards, ETA and offsets for a stop (the target's current path step, or
-- a later stop's own point). Returns true when the shown text changed.
local function Measure(stop, point, player)
    local points = addon.VignetteRadarPoints
    local distance, dx, dy
    if points and player then distance, dx, dy = points.Distance(player, point) end
    distance = Number(distance)
    local yards = distance and floor(distance + .5) or nil
    stop.dx, stop.dy = distance and dx or nil, distance and dy or nil
    local eta = yards and Guidance.Eta(yards) or nil
    local changed = stop.yards ~= yards or stop.eta ~= eta
    stop.yards, stop.eta = yards, eta
    return changed
end

-- What the step block says: Blizzard's route hint ("Take the portal to
-- ...") beats the quest objective while one applies; a map note shows its
-- note.
local function StepFor(settings, item, kind)
    if kind == "quest" and not item.availableStart then
        local questData = addon.VignetteRadarQuestData
        local objective = questData and questData.GetObjectiveSummary
            and questData.GetObjectiveSummary(item.questID,
                item.objectiveText or item.nextStep and item.nextStep.text) or nil
        local hint
        if objective and settings.vignetteRadarRouteNextStep == true and questData.GetNextStepLine then
            local line, isHint = questData.GetNextStepLine(item.questID)
            if isHint then hint = line end
        end
        local text = hint or objective and Text(objective.label)
        if text then
            return { text = text, count = not hint and objective and Text(objective.count) or nil, hint = hint ~= nil }
        end
        return nil
    end
    -- A Zygor point: the guide's current goal text, under its guide label.
    if kind == "guide" then
        local zygor = addon.VignetteRadarZygor
        local text = zygor and zygor.StepText and zygor.StepText()
        if not text then return nil end
        return { text = text, label = zygor.GuideLabel and zygor.GuideLabel() or "Zygor" }
    end
    local note = Text(item.note)
    if note and note ~= "" then return { text = note } end
    return nil
end

local function Build(now)
    local settings = Settings()
    local world = addon.VignetteRadarWorldFocus
    local player = Player()
    local previous = snapshot
    local built = { stops = {}, facts = {}, revision = previous.revision }
    local item, step, index, count
    if world and world.GetActiveTarget then item, step, index, count = world.GetActiveTarget() end
    local routeOn = world and world.IsRouteActive and world.IsRouteActive() or false
    local paused = world and world.IsRoutePaused and world.IsRoutePaused() or false
    if routeOn or paused then
        built.route = { kind = world.GetRouteChoice and world.GetRouteChoice() or nil, paused = paused,
            locked = world.IsRouteLocked and world.IsRouteLocked() or false,
            waiting = routeOn and not (world.GetRoutePoint and world.GetRoutePoint()) }
    end
    if built.route and built.route.waiting then item = nil end
    if type(item) == "table" then
        local points = addon.VignetteRadarPoints
        local kind = points and points.Kind and points.Kind(item) or item.kind
        local target = { item = item, step = step or item, current = true, kind = kind,
            name = Guidance.StopName(item), kindTitle = StepTitle(kind, item, index, count),
            progress = Number(index) and Number(count) and count > 1 and (index .. "/" .. count) or nil,
            color = TargetColor(item, kind) }
        Measure(target, step or item, player)
        if routeOn then target.cue = CompassCue(settings, target, player) end
        built.target = target
        built.step = StepFor(settings, item, kind)
        if kind ~= "guide" then
            for _, line in ipairs(Guidance.FactLines(item, player, now)) do
                if line[1] ~= "Distance" and line[1] ~= "ETA" then built.facts[#built.facts + 1] = line end
            end
        end
    end
    if routeOn and world.GetHorizon then
        local wanted = Number(settings.vignetteRadarGuideStops) or 3
        for _, stop in ipairs(world.GetHorizon(wanted + 1)) do
            if #built.stops >= wanted then break end
            if not stop.current and type(stop.item) == "table" then
                local entry = { item = stop.item, kind = Text(stop.kind) or Text(stop.item.kind),
                    name = Text(stop.label) or Text(stop.name) or Guidance.StopLabel(stop.item), current = false }
                Measure(entry, stop.item, player)
                built.stops[#built.stops + 1] = entry
            end
        end
    end
    built.mode = built.target and (routeOn and "route" or "focus") or built.route and "route" or "idle"
    -- The arrival briefing shows for a while after entering a map; with
    -- nothing focused it stays as the panel's idle line.
    local points = addon.VignetteRadarPoints
    local mapID = points and Number(points.View().mapID)
    if BlockOn(settings, "briefing") and mapID then
        local fresh = Fresh(settings, now, mapID)
        if fresh and built.mode == "idle" then built.mode = "arrival" end
        if fresh or built.mode == "idle" then
            local text = Guidance.BriefingText(Guidance.Count(mapID))
            if text then built.briefing = { text = text, fresh = fresh } end
        end
    end
    if notice and now >= notice.expires then notice = nil end
    built.notice = notice
    return built
end

-- Block lines: what each block shows, as label/value rows. Pure: reads only
-- the snapshot.
function Guidance.Lines(block, snap)
    local lines = {}
    snap = snap or snapshot
    local target = snap.target
    if block == "header" then
        if target then
            local parts = {}
            if target.cue then parts[#parts + 1] = Whole(target.cue) end
            parts[#parts + 1] = Whole(target.kindTitle .. (target.progress and (" " .. target.progress) or ""))
            if snap.step and snap.step.count then parts[#parts + 1] = Whole(snap.step.count) end
            parts[#parts + 1] = Whole(Guidance.Yards(target.yards))
            if target.eta then parts[#parts + 1] = Whole(target.eta) end
            lines[1] = { target.name, table.concat(parts, SEP), target.item }
        end
    elseif block == "step" then
        if snap.step then
            lines[1] = { snap.step.label or snap.step.hint and "Next Step" or nil, snap.step.text }
        elseif snap.route and snap.route.waiting then
            lines[1] = { nil, "Auto Route is waiting for the next stop." }
        end
    elseif block == "facts" then
        for index, line in ipairs(snap.facts or {}) do lines[index] = { line[1], line[2] } end
    elseif block == "stops" then
        for index, stop in ipairs(snap.stops or {}) do
            lines[index] = { index == 1 and "Next" or "Then", stop.name, stop.item, Guidance.Yards(stop.yards) }
        end
    elseif block == "briefing" then
        if snap.briefing then lines[1] = { snap.briefing.fresh and "Arrived" or "Here", snap.briefing.text } end
    elseif block == "actions" then
        local route = snap.route
        if route and not route.waiting and target then
            lines[#lines + 1] = { "lock" }
            lines[#lines + 1] = { "skip" }
        end
        if target then
            lines[#lines + 1] = { "why" }
            if target.kind ~= "guide" and Settings().vignetteRadarShareButton == true
                and addon.VignetteRadarShareToGroup then lines[#lines + 1] = { "share" } end
        end
    elseif block == "notice" then
        if snap.notice then
            lines[1] = { snap.notice.label, snap.notice.text }
            if snap.notice.detail then lines[2] = { nil, snap.notice.detail } end
        end
    end
    return lines
end

local SIGNED = { "header", "step", "facts", "stops", "briefing", "actions", "notice" }
local function Sign(snap)
    local parts = { snap.mode, snap.route and tostring(snap.route.locked) or "" }
    for _, block in ipairs(SIGNED) do
        for _, line in ipairs(Guidance.Lines(block, snap)) do
            parts[#parts + 1] = tostring(line[1]) .. "\t" .. tostring(line[2]) .. "\t" .. tostring(line[4])
        end
    end
    -- A different focused table with the same text still re-binds buttons.
    parts[#parts + 1] = tostring(snap.target and snap.target.item)
    return table.concat(parts, "\n")
end

local function Settle(next)
    local sign = Sign(next)
    if sign ~= signature then
        signature = sign
        next.revision = (next.revision or 0) + 1
    end
    if next.mode ~= snapshot.mode then
        Log("mode %s -> %s (%s)", snapshot.mode, next.mode, next.target and next.target.name or "no target")
    end
    snapshot = next
end

-- The current snapshot, rebuilt first when an event made it stale.
function Guidance.Snapshot()
    if dirty then
        dirty = false
        Settle(Build(Now()))
    end
    return snapshot
end

function Guidance.Invalidate()
    dirty = true
end

-- The .5 s refresh while the panel shows: yards, ETA, the compass cue and
-- the facts (health, seen) of the shown stops, plus the timed notice and
-- arrival briefing. True when anything the panel shows changed.
function Guidance.Tick(now)
    now = now or Now()
    if questDirty then
        questDirty = false
        Log("quest progress: rebuild")
    end
    if dirty then return true end
    local settings = Settings()
    local changed = false
    if notice and now >= notice.expires then notice = nil; changed = true end
    local points = addon.VignetteRadarPoints
    local mapID = points and Number(points.View().mapID)
    if snapshot.briefing and snapshot.briefing.fresh and not Fresh(settings, now, mapID) then changed = true end
    if changed then
        dirty = true
        return true
    end
    local player = Player()
    local target = snapshot.target
    if target then
        Measure(target, target.step, player)
        if snapshot.route and not snapshot.route.paused then target.cue = CompassCue(settings, target, player) end
        if target.kind ~= "guide" then
            local facts = {}
            for _, line in ipairs(Guidance.FactLines(target.item, player, now)) do
                if line[1] ~= "Distance" and line[1] ~= "ETA" then facts[#facts + 1] = line end
            end
            snapshot.facts = facts
        end
    end
    for _, stop in ipairs(snapshot.stops) do Measure(stop, stop.item, player) end
    local before = snapshot.revision
    Settle(snapshot)
    return snapshot.revision ~= before
end

local function OnTick()
    if Guidance.Tick() and addon.Bus then addon.Bus.Emit("GUIDANCE_CHANGED") end
end

-- The ticker runs only while the Guide Panel shows.
function Guidance.Watch(on)
    local bus = addon.Bus
    if not bus then return end
    if on then
        if not bus.IsTicking(TICK) then bus.Every(TICK, .5, OnTick) end
    else
        bus.Cancel(TICK)
    end
end

function Guidance.IsWatching()
    return addon.Bus ~= nil and addon.Bus.IsTicking(TICK)
end

-- Test seam: forget the arrival gates and the transient lines.
function Guidance._Reset()
    armed, briefedAt, lastBriefAt, arrival, notice = false, {}, nil, nil, nil
    snapshot, signature, dirty = { mode = "idle", stops = {}, facts = {}, revision = 0 }, nil, true
    questDirty = false
end

if addon.Bus then
    local bus = addon.Bus
    local function Changed()
        dirty = true
        bus.Emit("GUIDANCE_CHANGED")
    end
    -- A zone change arms the briefing; the first scan of the new map fires it.
    bus.On("MAP_CHANGED", function(event)
        if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then armed = true end
    end)
    bus.On("POINTS_CHANGED", function()
        if not armed then return end
        local points = addon.VignetteRadarPoints
        if not (points and Number(points.View().mapID)) then return end
        armed = false
        Guidance.Arrive()
    end)
    for _, topic in ipairs({ "FOCUS_CHANGED", "ROUTE_CHANGED", "POINTS_CHANGED", "MAP_CHANGED", "COMBAT", "LOGIN",
        "GUIDANCE_NOTICE", "ZYGOR_STEP" }) do
        bus.On(topic, Changed, { coalesce = true })
    end
    -- Quest progress: mark stale only. QUEST_LOG_UPDATE fires in bursts and
    -- the quest caches (Data/QuestData.lua) clear on the same events; the
    -- ticker's next pass rebuilds once, after they have. No C_Timer here, so
    -- the radar's single deferred quest scan stays the only one scheduled.
    bus.On("QUEST_CHANGED", function()
        dirty, questDirty = true, true
    end)
end
