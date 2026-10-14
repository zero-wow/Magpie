local _, addon = ...
if type(addon) ~= "table" then return end

-- One selection: the point the player picked last, from any view (radar
-- blip, target list, HUD, bearing card, quest tracker, map). Views read it
-- and redraw on FOCUS_CHANGED; World Focus projects it onto Blizzard's
-- waypoint and quest super-track, and keeps owning both.
--   Focus.Target(target) / Focus.Quest(questID [, point]) / Focus.Note(note)
--   Focus.Point(point)                     -> selection entries
--   Focus.Select(entry [, options]) / Focus.Toggle(entry [, options])
--   Focus.Clear([options]) / Focus.Get() / Focus.Same(a, b)
--   Focus.GetTargetKey() / Focus.GetTargetName() / Focus.GetQuest()
--   Focus.OnChanged(handler)               (Bus topic FOCUS_CHANGED)
-- options: source (who asked), project = false (leave World Focus alone),
-- direct (pin even when World Focus is off), type (Clear only that type).
-- Handlers receive (topic, current, previous, source).
local Focus = {}
addon.VignetteRadarFocus = Focus

local type = type
local Number, Text = addon.Secret.Number, addon.Secret.Text

local EMPTY = {}
local current

function Focus.Target(target)
    if type(target) ~= "table" then return nil end
    return { type = "target", key = Text(target.key), name = Text(target.name), ref = target }
end

function Focus.Quest(questID, point)
    questID = Number(questID)
    if not questID then return nil end
    point = type(point) == "table" and point or nil
    return { type = "quest", questID = questID, key = "quest:" .. questID,
        name = point and Text(point.name) or nil, ref = point }
end

function Focus.Note(note)
    if type(note) ~= "table" then return nil end
    return { type = "note", key = Text(note.key), name = Text(note.name), ref = note }
end

function Focus.Point(point)
    if type(point) ~= "table" then return nil end
    local points = addon.VignetteRadarPoints
    return { type = "point", key = Text(point.key) or (points and points.Key(point)),
        name = Text(point.name), questID = Number(point.questID), ref = point }
end

function Focus.Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a.type ~= b.type then return false end
    if a.type == "quest" then return a.questID == b.questID end
    if a.key ~= nil or b.key ~= nil then return a.key == b.key end
    return a.ref == b.ref
end

function Focus.Get() return current end

function Focus.GetTargetKey()
    return current and current.type == "target" and current.key or nil
end

function Focus.GetTargetName()
    return current and current.type == "target" and current.name or nil
end

function Focus.GetQuest()
    return current and current.type == "quest" and current.questID or nil
end

-- True when World Focus is currently showing this entry.
local function Showing(entry)
    local world = addon.VignetteRadarWorldFocus
    if not (entry and world and type(world.GetActiveTarget) == "function") then return false end
    local item = world.GetActiveTarget()
    if type(item) ~= "table" then return false end
    if entry.type == "quest" then return item.kind == "quest" and Number(item.questID) == entry.questID end
    if entry.ref ~= nil and item == entry.ref then return true end
    return entry.key ~= nil and item.key == entry.key
end
Focus.Showing = Showing

-- World Focus turns the selection into the Blizzard waypoint or quest
-- super-track. Module fields are read at call time.
local function Project(entry, options)
    local world = addon.VignetteRadarWorldFocus
    if not world then return false, "World Focus is unavailable" end
    local ref = entry.ref
    if entry.type == "target" then
        if not ref then return false, "No live target" end
        return world.SelectTarget(ref)
    elseif entry.type == "quest" then
        if ref and Number(ref.mapID) and Number(ref.mapX) and Number(ref.mapY) then
            return world.SelectPoint({ kind = "quest", questID = entry.questID,
                name = ref.name, colorSlot = ref.colorSlot,
                mapID = ref.mapID, mapX = ref.mapX, mapY = ref.mapY,
                worldX = ref.worldX, worldY = ref.worldY, instanceID = ref.instanceID }, options.direct)
        end
        return world.SelectQuest(entry.questID)
    elseif entry.type == "note" then
        return world.SelectNote(ref, options.direct)
    end
    return world.SelectPoint(ref, options.direct)
end

local function Changed(previous)
    return not Focus.Same(previous, current) or (previous and previous.name) ~= (current and current.name)
end

local function Notify(previous, source)
    local bus = addon.Bus
    if bus then bus.Emit("FOCUS_CHANGED", current, previous, source) end
end

-- Views redraw before the waypoint moves, the order the old click handlers used.
-- Returns World Focus's result when projecting, else whether focus changed.
function Focus.Select(entry, options)
    options = type(options) == "table" and options or EMPTY
    if type(entry) ~= "table" then return Focus.Clear(options) end
    local previous = current
    current = entry
    local changed = Changed(previous)
    if changed then Notify(previous, options.source) end
    if options.project == false then return changed end
    return Project(entry, options)
end

-- Clears the selection. With options.type it clears only that kind of
-- selection. World Focus is cleared too when it shows the cleared entry.
function Focus.Clear(options)
    options = type(options) == "table" and options or EMPTY
    local previous = current
    if not previous or (options.type and previous.type ~= options.type) then return false end
    current = nil
    Notify(previous, options.source)
    if options.project ~= false and Showing(previous) then
        local world = addon.VignetteRadarWorldFocus
        world.Clear(options.silent)
    end
    return true
end

-- The one click-again-to-clear rule for every view.
function Focus.Toggle(entry, options)
    if type(entry) == "table" and Focus.Same(current, entry) then
        Focus.Clear(options)
        return false
    end
    return Focus.Select(entry, options)
end

function Focus.OnChanged(handler)
    local bus = addon.Bus
    if bus and type(handler) == "function" then bus.On("FOCUS_CHANGED", handler) end
end

return Focus
