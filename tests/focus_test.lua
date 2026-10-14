VignetteRadarDB, WaffleHouseDB = nil, nil
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
assert(loadfile("Routes/Exploration.lua"))("VignetteRadar", addon)
local Focus = assert(addon.VignetteRadarFocus, "the focus service must be exposed")
local Exploration = addon.VignetteRadarExploration

-- World Focus stand-in: records projections and shows the last selection.
local calls, active = {}, nil
local function Record(name, item, extra)
    calls[#calls + 1] = { name = name, item = item, extra = extra }
    active = item
    return true
end
addon.VignetteRadarWorldFocus = {
    SelectTarget = function(target) return Record("target", { key = target.key, live = true }) end,
    SelectQuest = function(questID) return Record("quest", { kind = "quest", questID = questID }) end,
    SelectPoint = function(point, direct) return Record("point", point, direct) end,
    SelectNote = function(note, direct) return Record("note", note, direct) end,
    GetActiveTarget = function() return active end,
    Clear = function() calls[#calls + 1] = { name = "clear" }; active = nil; return true end,
}

-- Three views subscribe, the way the radar, target list and quest tracker do.
local seen = { radar = {}, list = {}, tracker = {} }
for name, log in pairs(seen) do
    Focus.OnChanged(function(_, current, previous, source)
        log[#log + 1] = { current = current, previous = previous, source = source, view = name }
    end)
end
local function Count(view) return #seen[view] end

-- One click on a radar blip updates every view once and moves the waypoint once.
local rare = { key = "guid-1", name = "Rare One", category = "rare" }
assert(Focus.Select(Focus.Target(rare), { source = "radar" }))
for view in pairs(seen) do
    assert(Count(view) == 1 and seen[view][1].current.key == "guid-1"
        and seen[view][1].source == "radar", "every view must hear one click once: " .. view)
end
assert(#calls == 1 and calls[1].name == "target", "the click must place one waypoint")
assert(Focus.GetTargetKey() == "guid-1" and Focus.GetTargetName() == "Rare One")
assert(Exploration.GetFocusedQuest() == nil)

-- Selecting the same thing again is not a change.
Focus.Select(Focus.Target(rare), { project = false })
assert(Count("radar") == 1, "an unchanged selection must not redraw the views")

-- A quest click from the tracker replaces the target: one selection, not two.
Exploration.FocusQuest(900)
assert(Focus.GetQuest() == 900 and Exploration.GetFocusedQuest() == 900
    and Focus.GetTargetKey() == nil, "a quest focus must replace the target focus")
assert(Count("list") == 2 and seen.list[2].previous.key == "guid-1",
    "the target list must hear that its target lost focus")
assert(calls[#calls].name == "quest" and calls[#calls].item.questID == 900)

-- Toggle: clicking the focused quest again clears it and its waypoint.
Exploration.FocusQuest(900)
assert(Focus.GetQuest() == nil and Focus.Get() == nil, "the second click must clear the quest focus")
assert(calls[#calls].name == "clear", "clearing the focus must clear the waypoint it placed")

-- Toggle on a target: the same rule on every view.
local before = #calls
Focus.Toggle(Focus.Target(rare), { source = "radar" })
assert(Focus.GetTargetKey() == "guid-1" and #calls == before + 1)
Focus.Toggle(Focus.Target(rare), { source = "constellation" })
assert(Focus.Get() == nil and calls[#calls].name == "clear",
    "a second click from another view must clear the same selection")

-- Clearing leaves a waypoint alone when World Focus shows something else.
Focus.Select(Focus.Target(rare), { project = false })
active = { key = "route-stop" }
before = #calls
assert(Focus.Clear())
assert(#calls == before, "an Auto Route stop the focus did not place must stay")

-- A typed clear only clears that kind of selection.
Focus.Select(Focus.Quest(5), { project = false })
assert(not Focus.Clear({ type = "target" }) and Focus.GetQuest() == 5)
assert(Focus.Clear({ type = "quest", project = false }) and Focus.Get() == nil)

-- Quest points with a position become a quest stop at that point.
Focus.Select(Focus.Quest(7, { name = "Q", mapID = 1, mapX = .5, mapY = .5, worldX = 1, worldY = 2 }))
assert(calls[#calls].name == "point" and calls[#calls].item.kind == "quest"
    and calls[#calls].item.questID == 7 and calls[#calls].item.mapX == .5)

-- Notes and direct pins pass the direct flag through.
Focus.Select(Focus.Note({ key = "n1", name = "Chest" }), { direct = true })
assert(calls[#calls].name == "note" and calls[#calls].extra == true)
Focus.Select(Focus.Point({ kind = "treasure", worldX = 1, worldY = 2 }), { direct = true })
assert(calls[#calls].name == "point" and calls[#calls].extra == true
    and Focus.Get().key == "treasure:1.000:2.000", "a point without a key uses the registry key")

-- Quest focus validation drops a vanished quest without touching the waypoint.
Exploration.SetQuestFocus(44)
before = #calls
for _ = 1, 3 do Exploration.ValidateQuestFocus({ { questID = 45 } }, false) end
assert(Exploration.GetFocusedQuest() == nil and #calls == before)

print("VignetteRadar focus tests passed")
