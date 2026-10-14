local _, addon = ...
if type(addon) ~= "table" then return end

-- Compass: the one data feed behind the Compass (bearing) system. Two views
-- read it and keep their own looks: the Bearing Bar cards (Routes/Beacons.lua)
-- and the Horizon Ribbon ticks (UI/HorizonRibbon.lua); the Guide Panel's
-- optional compass block reads it too.
-- It is NOT the direction arrow (the Guide Panel chevron, the radar edge
-- arrow): those point at one target and keep their own code. Never merge them.
-- The feed is built from the point registry (Core/Points.lua) once per scan
-- generation, or after a focus or route change, never per frame. Each view
-- picks what it shows from the feed and places its marks every frame from
-- the stored world heading and GetPlayerFacing() (ADDON-METHODS: per-frame
-- Place for camera-relative HUDs).
--   Compass.Facing() -> radians | nil
--   Compass.Heading(player, item) -> world angle (atan2 of the offset) | nil
--   Compass.Relative(heading, facing) -> -pi..pi, positive is to your left
--   Compass.Bearing(player, item, facing) -> Relative(Heading(...)) | nil
--   Compass.X(angle, halfWidth [, fov]) -> x, clamped
--   Compass.Yards(player, item) -> yards | nil
--   Compass.Color(kind, item) -> r, g, b (theme kind color, quest palette)
--   Compass.Build(view, sources, db) -> feed            (no caching)
--   Compass.Feed() -> the cached feed for the current scan
--   Compass.Ticks(feed, rares) -> { { item, kind, label, focus } }
--   Compass.Revision() / Compass.Invalidate()
-- feed = { mapID, player, generation, revision, anyHere,
--          points = { Entry }, stops = { Entry + label }, focus = Entry | nil }
-- Entry = { kind, source ("live" | "quest" | "note" | "stop"), raw, name, mapID,
--           worldX, worldY, instanceID, distance, distance2, heading,
--           r, g, b, completed, favorite, focused, priority, here }
local Compass = {}
addon.VignetteRadarCompass = Compass

local type, ipairs, tostring, sqrt = type, ipairs, tostring, math.sqrt
local PI, TWO_PI = math.pi, math.pi * 2
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local Number, Text, Call = addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local FOV = PI / 2
local MAX_LIVE, MAX_QUESTS, MAX_NOTES, MAX_STOPS = 128, 128, 64, 3
-- A pack note this close to a live point of the same kind is that point.
local DUPLICATE_YARDS = 45
-- The focused step and a point this close (yards, squared) are one place.
local FOCUSED_YARDS2 = 144
local FALLBACK_NAME = { quest = "Quest Point", treasure = "Treasure", entrance = "Entrance", rare = "Rare" }

local cached, revision, focusRevision = nil, 0, 0

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("compass", fmt, ...) end
end

-- Geometry -------------------------------------------------------------------

function Compass.Facing()
    return Number(Call(_G, "GetPlayerFacing"))
end

function Compass.Heading(player, item)
    if type(player) ~= "table" or type(item) ~= "table" then return nil end
    local px, py, x, y = Number(player.worldX), Number(player.worldY), Number(item.worldX), Number(item.worldY)
    if not (px and py and x and y) then return nil end
    local pi, ii = Number(player.instanceID), Number(item.instanceID)
    if pi and ii and pi ~= ii then return nil end
    return atan2(y - py, x - px)
end

function Compass.Relative(heading, facing)
    return (heading - facing + PI) % TWO_PI - PI
end

function Compass.Bearing(player, item, facing)
    facing = Number(facing)
    local heading = facing and Compass.Heading(player, item)
    return heading and Compass.Relative(heading, facing) or nil
end

-- x for an angle on a strip spanning -fov..fov; beyond it sits on the
-- nearer edge and reports clamped.
function Compass.X(angle, halfWidth, fov)
    fov = fov or FOV
    local clamped = angle > fov or angle < -fov
    if angle > fov then angle = fov elseif angle < -fov then angle = -fov end
    return -angle / fov * halfWidth, clamped
end

function Compass.Yards(player, item)
    if type(player) ~= "table" or type(item) ~= "table" then return nil end
    local px, py, x, y = Number(player.worldX), Number(player.worldY), Number(item.worldX), Number(item.worldY)
    if not (px and py and x and y) then return nil end
    return sqrt((x - px) ^ 2 + (y - py) ^ 2)
end

-- Colors ---------------------------------------------------------------------

local function StyleColor(slot)
    local style = addon.VignetteRadarStyle
    if not (style and type(style.Color) == "function" and slot) then return nil end
    local ok, r, g, b = pcall(style.Color, slot)
    if ok and Number(r) and Number(g) and Number(b) then return r, g, b end
end

-- One kind color for every compass view: quests take their radar quest
-- color, world bosses the boss role, cave entrances the accent.
function Compass.Color(kind, item)
    if kind == "quest" then
        local palette = addon.VignetteRadarQuestColors
        if palette and addon.GetSettings().vignetteRadarQuestColors and type(item) == "table" then
            local color = palette[Number(item.colorSlot) or 1]
            if color then return color[1], color[2], color[3] end
        end
    end
    local slot = type(item) == "table" and item.isWorldBoss and "boss"
        or kind == "entrance" and "accent" or kind == "mob" and "rare" or kind
    local r, g, b = StyleColor(slot)
    if r then return r, g, b end
    r, g, b = StyleColor("accent")
    if r then return r, g, b end
    return .55, .88, .82
end

-- Entries --------------------------------------------------------------------

local function Entry(kind, source, raw, player, mapID, step)
    if type(raw) ~= "table" then return nil end
    local x, y = Number(raw.worldX), Number(raw.worldY)
    local distance, dx, dy = addon.VignetteRadarPoints.Distance(player, raw)
    if not (x and y and distance) then return nil end
    local r, g, b = Compass.Color(kind, raw)
    local pointMap = Number(raw.mapID) or mapID
    local focused = step ~= nil and step.mapID == pointMap and Number(step.worldX) and Number(step.worldY)
        and (x - step.worldX) ^ 2 + (y - step.worldY) ^ 2 <= FOCUSED_YARDS2
    local name = Text(raw.name)
    return {
        kind = kind, source = source, raw = raw, mapID = pointMap,
        worldX = x, worldY = y, instanceID = Number(raw.instanceID),
        name = name or FALLBACK_NAME[kind] or "Point",
        distance2 = dx * dx + dy * dy, distance = distance, heading = atan2(dy, dx),
        r = r, g = g, b = b, completed = raw.completed == true, favorite = raw.favorite == true,
        focused = focused == true,
        priority = raw.favorite == true and 0 or raw.isWorldBoss and 1 or kind == "rare" and 2
            or (kind == "treasure" or kind == "entrance") and 3 or 4,
    }
end

-- Pack note kinds the compass shows, as compass kinds.
local NOTE_KIND = { mob = "rare", treasure = "treasure", entrance = "entrance" }

-- Quests whose area you stand in (plus the focused quest), when "Quests
-- Here Only" is on; nil when the filter is off or none are here.
local function QuestsHere(quests, db)
    local data = addon.VignetteRadarQuestData
    if db.vignetteRadarAreaQuests ~= true or not (data and data.IsQuestInArea) then return nil end
    local exploration = addon.VignetteRadarExploration
    local focused = exploration and exploration.GetFocusedQuest and exploration.GetFocusedQuest()
    local here
    for index = 1, math.min(#quests, MAX_QUESTS) do
        local id = quests[index].questID
        if id and (id == focused or data.IsQuestInArea(id)) then
            here = here or {}
            here[id] = true
        end
    end
    return here
end

local function AddNotes(feed, notes, player, mapID, step, db, live)
    if not (type(notes) == "table" and db.vignetteRadarMapNotesVisible == true
        and db.vignetteRadarPOISource ~= "none") then return end
    local points, recent = addon.VignetteRadarPoints, addon.VignetteRadarRecent
    local types = type(db.vignetteRadarPOITypes) == "table" and db.vignetteRadarPOITypes or {}
    for index = 1, math.min(#notes, MAX_NOTES) do
        local note = notes[index]
        local kind = type(note) == "table" and NOTE_KIND[note.kind]
        if kind and types[note.kind] ~= false
            and not (recent and recent.IsHidden and recent.IsHidden(note, db)) then
            local duplicate = false
            for _, entry in ipairs(live) do
                if points.Near(note, entry.raw, DUPLICATE_YARDS, mapID) then duplicate = true; break end
            end
            local entry = not duplicate and Entry(kind, "note", note, player, mapID, step)
            if entry then feed.points[#feed.points + 1] = entry end
        end
    end
end

local function AddRoute(feed, player, mapID, step)
    local world = addon.VignetteRadarWorldFocus
    if not world then return end
    local active = world.GetActiveTarget and world.GetActiveTarget() or nil
    local points = addon.VignetteRadarPoints
    if world.IsRouteActive and world.IsRouteActive() and world.GetHorizon then
        for index, stop in ipairs(world.GetHorizon(MAX_STOPS)) do
            if index > MAX_STOPS then break end
            local kind = Text(stop.kind) or points.Kind(stop.item)
            local entry = Entry(kind, "stop", stop.item, player, mapID, step)
                or type(stop.item) == "table" and { kind = kind, source = "stop", raw = stop.item } or nil
            if entry then
                entry.label, entry.current = tostring(index), stop.current == true
                feed.stops[#feed.stops + 1] = entry
            end
        end
    end
    if type(active) == "table" then
        local kind = points.Kind(active)
        feed.focus = Entry(kind, "focus", active, player, mapID, step) or { kind = kind, source = "focus", raw = active }
    end
end

-- Builds a feed from a view ({ mapID, player }) and sources ({ live, quest,
-- saved } raw lists). Reads World Focus for the focused step and the route.
function Compass.Build(view, sources, db)
    db = db or addon.GetSettings()
    view, sources = view or {}, sources or {}
    local mapID, player = view.mapID, view.player
    local feed = { mapID = mapID, player = player, points = {}, stops = {}, anyHere = false }
    if not (type(player) == "table" and Number(player.worldX) and Number(player.worldY)) then
        return feed
    end
    local world = addon.VignetteRadarWorldFocus
    local step = world and world.GetFocusedStep and world.GetFocusedStep() or nil
    local live = {}
    local targets = type(sources.live) == "table" and sources.live or {}
    for index = 1, math.min(#targets, MAX_LIVE) do
        local target = targets[index]
        local kind = type(target) == "table" and not target.stale
            and (target.category == "rare" or target.category == "treasure") and target.category
        local entry = kind and Entry(kind, "live", target, player, mapID, step)
        if entry then live[#live + 1] = entry; feed.points[#feed.points + 1] = entry end
    end
    local quests = type(sources.quest) == "table" and sources.quest or {}
    local here = QuestsHere(quests, db)
    feed.anyHere = here ~= nil
    for index = 1, math.min(#quests, MAX_QUESTS) do
        local entry = Entry("quest", "quest", quests[index], player, mapID, step)
        if entry then
            entry.here = here == nil or here[quests[index].questID] == true
            feed.points[#feed.points + 1] = entry
        end
    end
    AddNotes(feed, sources.saved, player, mapID, step, db, live)
    AddRoute(feed, player, mapID, step)
    return feed
end

-- The feed for the current scan: rebuilt when the point registry publishes
-- a new generation or the focus or route changed, else the same table.
function Compass.Feed()
    local points = addon.VignetteRadarPoints
    local generation = points and points.Generation() or 0
    if cached and cached.generation == generation and cached.focusRevision == focusRevision then
        return cached
    end
    local view = points and points.View() or {}
    local feed = Compass.Build(view, points and {
        live = points.Refs("live"), quest = points.Refs("quest"), saved = points.Refs("saved") } or {})
    revision = revision + 1
    feed.generation, feed.focusRevision, feed.revision = generation, focusRevision, revision
    -- Logged only when what the feed holds changes, not on every scan.
    local focusName = feed.focus and tostring(feed.focus.name or feed.focus.kind) or "none"
    if not cached or #cached.points ~= #feed.points or #cached.stops ~= #feed.stops
        or (cached.focus and tostring(cached.focus.name or cached.focus.kind) or "none") ~= focusName then
        Log("feed: %d points, %d stops, focus %s", #feed.points, #feed.stops, focusName)
    end
    cached = feed
    return feed
end

function Compass.Revision() return revision end

function Compass.Invalidate()
    cached = nil
end

local function Key(item)
    local points = addon.VignetteRadarPoints
    return Text(item.key) or (points and points.Key(item)) or tostring(item)
end

-- The ribbon's marks, most important first, no duplicates: the route's
-- next stops (numbered), the focused point, then up to `rares` live rares.
function Compass.Ticks(feed, rares)
    feed = feed or Compass.Feed()
    local list, seen = {}, {}
    local function Add(item, kind, label, focus)
        if type(item) ~= "table" then return end
        local key = Key(item)
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = { item = item, kind = kind, label = label, focus = focus }
    end
    for _, stop in ipairs(feed.stops) do Add(stop.raw, stop.kind, stop.label, stop.current) end
    if feed.focus then Add(feed.focus.raw, feed.focus.kind, nil, true) end
    local count = 0
    for _, entry in ipairs(feed.points) do
        if count >= (Number(rares) or 0) then break end
        if entry.source == "live" and entry.kind == "rare" then
            count = count + 1
            Add(entry.raw, "rare", nil, false)
        end
    end
    return list
end

if addon.Bus then
    local function Moved() focusRevision = focusRevision + 1 end
    addon.Bus.On("FOCUS_CHANGED", Moved)
    addon.Bus.On("ROUTE_CHANGED", Moved)
end

return Compass
