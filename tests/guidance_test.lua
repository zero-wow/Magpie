-- Guidance: the Guide Panel's one feed. Names (the "Treasure location"
-- fix), snapshot modes, block lines, revisions, the .5 s tick, events,
-- arrival briefing, notices and the Worth-It facts.
local now = 100
GetTime = function() return now end
GetServerTime = function() return 50000 end
C_Map = { GetMapInfo = function(mapID) return mapID == 7 and { name = "Zul'Aman" } or nil end }
local health
C_VignetteInfo = { GetHealthPercent = function() return health end }

local settings = { vignetteRadarEnabled = true, vignetteRadarGuidePanel = true, vignetteRadarGuideStops = 3,
    vignetteRadarGuideBlocks = {}, vignetteRadarGuideBriefingSeconds = 20, vignetteRadarRouteNextStep = true,
    vignetteRadarWorthTooltip = true, vignetteRadarShareButton = true, vignetteRadarJournal = {} }
local addon = { GetSettings = function() return settings end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Guidance.lua"))("VignetteRadar", addon)
local Guidance = assert(addon.VignetteRadarGuidance)
local Points = addon.VignetteRadarPoints

-- Names: a pack's stand-in name reads as kind and zone.
assert(Points.IsPlaceholderName("Treasure location") and Points.IsPlaceholderName("Cave entrance")
    and Points.IsPlaceholderName("Map note") and Points.IsPlaceholderName(nil)
    and not Points.IsPlaceholderName("Forgotten Amani Cache"), "stand-in names are recognised")
assert(Guidance.StopName({ kind = "treasure", name = "Treasure location", mapID = 7 }) == "Treasure · Zul'Aman",
    "an unnamed pack treasure shows its kind and zone")
assert(Guidance.StopName({ kind = "mob", name = "Mob location", mapID = 99 }) == "Rare · Unnamed",
    "a stand-in without a known zone still says what it is")
assert(Guidance.StopName({ kind = "treasure", name = "Forgotten Amani Cache" }) == "Forgotten Amani Cache",
    "a real name is kept")
assert(Guidance.StopLabel({ kind = "quest", questID = 1, name = "Quest", objectiveText = "Kill 5 Trolls" })
    == "Kill 5 Trolls", "a quest stop in a list is named by its objective")
assert(Guidance.Yards(100.4) == "100 yd" and Guidance.Yards(1520) == "1.5k yd" and Guidance.Yards(nil) == "?",
    "yards stay short")

-- The world as World Focus reports it.
local player = { worldX = 0, worldY = 0, instanceID = 1, facing = 0 }
addon.VignetteRadarAPI = { GetPlayerSnapshot = function() return player end }
addon.VignetteRadarTravel = { EtaText = function(yards) return "~" .. math.floor(yards / 10) .. " s" end }
local active, steps, index, routeOn, locked, horizon, horizonLimit = nil, nil, 1, false, false, {}, nil
local world = {
    GetActiveTarget = function()
        if not active then return nil end
        return active, steps and steps[index] or active, index, steps and #steps or 1
    end,
    IsRouteActive = function() return routeOn end,
    IsRoutePaused = function() return false end,
    IsRouteLocked = function() return locked end,
    GetRouteChoice = function() return routeOn and "treasure" or nil end,
    GetRoutePoint = function() return routeOn and active or nil end,
    GetHorizon = function(limit) horizonLimit = limit; return horizon end,
    TargetColor = function() return .1, .2, .3 end,
}
addon.VignetteRadarWorldFocus = world
Points.Publish({ mapID = 7, player = player, targets = {}, notes = {
    { kind = "treasure", name = "Treasure location", mapID = 7, worldX = 900, worldY = 0 } } })

-- Idle: nothing focused; the zone line stands in.
local snap = Guidance.Snapshot()
assert(snap.mode == "idle" and snap.target == nil and snap.briefing
    and snap.briefing.text == "1 treasure left" and not snap.briefing.fresh,
    "with nothing focused the panel offers the zone line")
assert(#Guidance.Lines("header", snap) == 0 and #Guidance.Lines("actions", snap) == 0,
    "idle shows no header and no actions")

-- Focus: one point, no route.
local cache = { key = "cache", kind = "treasure", name = "Forgotten Amani Cache", mapID = 7,
    worldX = 120, worldY = 0, instanceID = 1, rewardQuestID = 55, note = "Behind the waterfall" }
active = cache
addon.VignetteRadarDeclutter = { Done = function(questID) return questID == 55 end }
addon.VignetteRadarShareToGroup = {}
Guidance.Invalidate()
snap = Guidance.Snapshot()
assert(snap.mode == "focus" and snap.target.name == "Forgotten Amani Cache" and snap.target.yards == 120
    and snap.target.color[3] == .3, "a focused point is the target, with yards and its pin color")
local header = Guidance.Lines("header", snap)[1]
assert(header[1] == "Forgotten Amani Cache" and header[2] == "Treasure · 120\194\160yd · ~12\194\160s",
    "the header reads kind, yards and ETA, each part kept whole: " .. tostring(header[2]))
assert(Guidance.Lines("step", snap)[1][2] == "Behind the waterfall", "a map note's own note is the step")
local facts = Guidance.Lines("facts", snap)
assert(#facts == 1 and facts[1][1] == "Today" and facts[1][2] == "Done",
    "facts leave yards and ETA to the header")
local actions = {}
for _, line in ipairs(Guidance.Lines("actions", snap)) do actions[#actions + 1] = line[1] end
assert(table.concat(actions, ",") == "why,share", "a focus without a route has no lock or skip")
assert(#Guidance.Lines("stops", snap) == 0, "a focus without a route has no next stops")
assert(snap.briefing == nil, "a focused point hides the idle zone line")

-- Revisions bump only when shown text changes.
local revision = snap.revision
Guidance.Invalidate()
assert(Guidance.Snapshot().revision == revision, "a rebuild with the same text keeps the revision")
player.worldX = 20
assert(Guidance.Tick() and Guidance.Snapshot().revision == revision + 1
    and Guidance.Snapshot().target.yards == 100, "moving changes yards on the tick and bumps the revision")
assert(not Guidance.Tick(), "a tick with nothing new changes nothing")
player.worldX = 0

-- Route: a treasure path, its step title and the next stops.
local function Note(name, x) return { key = name, kind = "treasure", name = name, worldX = x, worldY = 0, instanceID = 1 } end
steps = { Note("Entrance", 50), Note("Ledge", 80), cache }
index, routeOn = 2, true
horizon = { { current = true, item = cache, name = cache.name },
    { item = Note("Second", 300), label = "Second", kind = "treasure" },
    { item = Note("Third", 600), label = "Third", kind = "rare" },
    { item = Note("Fourth", 900), label = "Fourth" } }
settings.vignetteRadarGuideStops = 2
Guidance.Invalidate()
snap = Guidance.Snapshot()
header = Guidance.Lines("header", snap)[1]
assert(snap.mode == "route" and header[2]:find("^Approach\194\1602/3 · 80\194\160yd"),
    "a path step reads Approach i/n with the step's own yards: " .. header[2])
local stops = Guidance.Lines("stops", snap)
assert(horizonLimit == 3 and #stops == 2 and stops[1][1] == "Next" and stops[1][2] == "Second"
    and stops[1][4] == "300 yd" and stops[2][1] == "Then" and stops[2][2] == "Third",
    "next stops skip the current one (the header) and honour the count")
actions = {}
for _, line in ipairs(Guidance.Lines("actions", snap)) do actions[#actions + 1] = line[1] end
assert(table.concat(actions, ",") == "lock,skip,why,share", "a running route adds lock and skip")
settings.vignetteRadarGuideStops = 3

-- Quest step: Blizzard's route hint beats the objective.
local hint
addon.VignetteRadarQuestData = {
    GetObjectiveSummary = function() return { label = "Collect Shredder Parts", count = "2/5" } end,
    GetNextStepLine = function() return hint, hint ~= nil end,
}
active, steps, index = { key = "q", kind = "quest", questID = 9, name = "First Quest", worldX = 40, worldY = 0,
    instanceID = 1 }, nil, 1
Guidance.Invalidate()
snap = Guidance.Snapshot()
assert(Guidance.Lines("step", snap)[1][2] == "Collect Shredder Parts"
    and Guidance.Lines("header", snap)[1][2]:find("2/5", 1, true)
    and Guidance.Lines("header", snap)[1][1] == "First Quest",
    "a quest shows its title in the header and the objective as the step, count in the header")
hint = "Take the portal to Dornogal"
Guidance.Invalidate()
snap = Guidance.Snapshot()
assert(Guidance.Lines("step", snap)[1][1] == "Next Step" and Guidance.Lines("step", snap)[1][2] == hint
    and not Guidance.Lines("header", snap)[1][2]:find("2/5", 1, true),
    "Blizzard's route hint replaces the objective while it applies")
routeOn, active = false, nil

-- Events: any trigger asks for a new snapshot (coalesced; at once without C_Timer).
local announced = 0
addon.Bus.On("GUIDANCE_CHANGED", function() announced = announced + 1 end)
addon.Bus.Emit("ROUTE_CHANGED")
addon.Bus.Emit("FOCUS_CHANGED")
assert(announced == 2, "ROUTE_CHANGED and FOCUS_CHANGED announce a new snapshot")

-- The ticker runs only while watched (the panel shows).
Guidance.Watch(true)
assert(Guidance.IsWatching(), "watching starts the .5 s ticker")
Guidance.Watch(false)
assert(not Guidance.IsWatching(), "a hidden panel stops the ticker")

-- Arrival: a zone change, then the first scan of the map, briefs once.
Guidance.Invalidate()
addon.Bus.Emit("ZONE_CHANGED_NEW_AREA")
Points.Publish({ mapID = 7, player = player, targets = {}, notes = {
    { kind = "treasure", name = "A", mapID = 7 }, { kind = "treasure", name = "B", mapID = 7 } } })
snap = Guidance.Snapshot()
assert(snap.mode == "arrival" and snap.briefing.fresh and snap.briefing.text == "2 treasures left"
    and Guidance.Lines("briefing", snap)[1][1] == "Arrived", "arriving shows the zone line as fresh")
local ok, why = Guidance.Arrive(now + 40)
assert(not ok and why == "briefed recently", "a map is not briefed again soon")
now = now + 25
assert(Guidance.Tick(), "the arrival window closing is a change")
snap = Guidance.Snapshot()
assert(snap.mode == "idle" and snap.briefing and not snap.briefing.fresh,
    "after the window the line stays as the idle zone line")
settings.vignetteRadarGuideBlocks.briefing = false
Guidance.Invalidate()
assert(Guidance.Snapshot().briefing == nil, "the briefing block off hides the line")
settings.vignetteRadarGuideBlocks.briefing = true

-- Notices: shown only while the panel shows them; they expire on the tick.
assert(not Guidance.Notice("AUTO ROUTE", "Started"), "without the panel a note stays a toast")
addon.VignetteRadarGuidePanel = { ShowsNotices = function() return true end }
assert(Guidance.Notice("AUTO ROUTE", "Started · Cache", { label = "Kill 5", count = "1/5" }),
    "the panel takes the note")
snap = Guidance.Snapshot()
local notice = Guidance.Lines("notice", snap)
assert(notice[1][1] == "AUTO ROUTE" and notice[1][2] == "Started · Cache" and notice[2][2] == "Kill 5 · 1/5",
    "a note shows its label, message and objective")
now = now + 6
Guidance.Tick()
assert(#Guidance.Lines("notice", Guidance.Snapshot()) == 0, "a note fades after a few seconds")

-- Worth-It facts (were UI/WorthCard.lua) and the marker tooltip line.
do
    health = .42
    Points.Publish({ mapID = 7, player = player, targets = { { key = "rare1", category = "rare",
        name = "Silvermaw", worldX = 30, worldY = 0, instanceID = 1, groupMin = 3, groupMax = 5 } } })
    local lines = Guidance.FactLines({ key = "rare1", kind = "rare", name = "Silvermaw" }, player, now)
    local text = {}
    for _, line in ipairs(lines) do text[#text + 1] = line[1] .. "=" .. line[2] end
    assert(table.concat(text, ",") == "Health=42%,Group=3-5,Distance=30 yd,ETA=~3 s,Seen=Up Now",
        "a live rare's facts: " .. table.concat(text, ","))
    settings.vignetteRadarJournal = { { name = "Old Cache", at = 50000 - 7200 } }
    lines = Guidance.FactLines({ kind = "treasure", name = "Old Cache" }, nil, now)
    assert(lines[1][1] == "Seen" and lines[1][2] == "2 h Ago", "the journal gives last seen")
    local tooltip = { lines = {}, AddLine = function(self, line) self.lines[#self.lines + 1] = line end }
    Guidance.AddTooltipLines(tooltip, { key = "rare1", kind = "rare", name = "Silvermaw" })
    assert(tooltip.lines[1] == "Health 42% · ETA ~3 s · Seen Up Now", "the tooltip line skips distance and group")
    settings.vignetteRadarWorthTooltip = false
    tooltip.lines = {}
    Guidance.AddTooltipLines(tooltip, { key = "rare1", kind = "rare" })
    assert(#tooltip.lines == 0, "the tooltip facts have their own switch")
    assert(Guidance.CompactFacts({ key = "rare1", kind = "rare" }) == nil, "compact facts share that switch")
    settings.vignetteRadarWorthTooltip = true
    -- Short tooltips: no distance, ETA or group; empty and default values dropped.
    assert(Guidance.CompactFacts({ key = "rare1", kind = "rare", name = "Silvermaw" }) == "Health 42% · Seen Up Now",
        "compact facts keep only what is worth reading")
    local providers = Guidance.FactProviders
    local saved = #providers
    providers[saved + 1] = function(rows) rows[#rows + 1] = { "Loot", "No Loot Data" }; rows[#rows + 1] = { "Today", "Not Done" } end
    assert(Guidance.CompactFacts({ kind = "mob", name = "Nobody" }) == nil, "no loot data and not done say nothing")
    providers[saved + 1] = function(rows) rows[#rows + 1] = { "Today", "Done" } end
    assert(Guidance.CompactFacts({ kind = "mob", name = "Nobody" }) == "Done today", "done shows as Done today")
    providers[saved + 1] = nil
    -- Click hints: one line, first 3 hovers per kind only.
    settings.vignetteRadarWorldFocusEnabled, settings.vignetteRadarHideCleared = true, true
    local mob = { kind = "mob", name = "Alendis" }
    assert(Guidance.MapNoteHints(mob) == "Click: focus · Right-click: hide 1 h", "hints on one line")
    Guidance.MapNoteHints(mob)
    Guidance.MapNoteHints(mob)
    assert(Guidance.MapNoteHints(mob) == nil, "hints stop after 3 hovers of a kind")
    assert(Guidance.MapNoteHints({ kind = "treasure" }) ~= nil, "each kind counts on its own")
end

-- Zone counts (were UI/ZoneBriefing.lua).
do
    addon.Quests = { OnMap = function() return { quests = { { questID = 1 }, { questID = 2 } },
        tasks = { { questID = 2 }, { questID = 3 } } } end }
    Points.Publish({ mapID = 7, player = player, targets = { { key = "r", category = "rare" },
        { key = "e", category = "event" }, { key = "s", category = "rare", stale = true } },
        notes = { { kind = "treasure" }, { kind = "event", areaPoiID = 4 } } })
    local counts = Guidance.Count(7)
    assert(counts.rares == 1 and counts.events == 2 and counts.treasures == 1 and counts.quests == 3,
        "counts skip stale rares and count each quest once")
    assert(Guidance.BriefingText(counts) == "1 rare up · 1 treasure left · 2 events · 3 quests here"
        and Guidance.BriefingText({ rares = 0, treasures = 0, events = 0, quests = 0 }) == nil,
        "the zone line names only what is there")
end

-- Quest progress: a burst of quest events only marks the snapshot stale (no
-- timer, no work in the event); the next tick or read rebuilds once.
do
    local progress, timers = "1/5", 0
    local savedTimer = C_Timer
    C_Timer = { After = function() timers = timers + 1 end }
    addon.VignetteRadarQuestData = { GetObjectiveSummary = function() return { label = "Kill Trolls", count = progress } end }
    active, steps, index, routeOn = { kind = "quest", questID = 9, name = "Troll Trouble", worldX = 40, worldY = 0 },
        nil, 1, false
    Guidance.Invalidate()
    assert(Guidance.Snapshot().step.count == "1/5", "the step shows the quest count")
    progress = "2/5"
    for _ = 1, 3 do addon.Bus.Emit("QUEST_LOG_UPDATE") end
    assert(timers == 0, "quest events schedule no timer (the radar's deferred quest scan stays the only one)")
    assert(Guidance.Tick(now) == true, "the next tick picks the quest change up")
    assert(Guidance.Snapshot().step.count == "2/5", "and the rebuilt step shows the new count")
    C_Timer = savedTimer
end

-- Zygor: a guide point's step block shows the guide's current goal.
do
    addon.VignetteRadarZygor = { StepText = function() return "Kill 8 Raptors" end,
        GuideLabel = function() return "Example Guide · Step 3" end }
    active = { kind = "guide", name = "Zygor", worldX = 60, worldY = 0, instanceID = 1 }
    addon.Bus.Emit("ZYGOR_STEP")
    local line = Guidance.Lines("step", Guidance.Snapshot())[1]
    assert(line and line[1] == "Example Guide · Step 3" and line[2] == "Kill 8 Raptors",
        "the step block shows the Zygor goal under the guide label")
    addon.VignetteRadarZygor.StepText = function() return nil end
    Guidance.Invalidate()
    assert(Guidance.Lines("step", Guidance.Snapshot())[1] == nil, "no goal text: no step block")
    active, addon.VignetteRadarZygor, addon.VignetteRadarQuestData = nil, nil, nil
end

print("guidance tests passed")
