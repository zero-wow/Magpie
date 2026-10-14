local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
local Points = assert(addon.VignetteRadarPoints, "the registry must be exposed")

-- Normalization: one kind vocabulary for vignettes, notes and quests.
assert(Points.Kind({ kind = "mob" }) == "rare", "a map-note mob is a rare")
assert(Points.Kind({ category = "rare" }) == "rare")
assert(Points.Kind({ category = "treasure" }) == "treasure")
assert(Points.Kind({ kind = "entrance" }) == "entrance")
assert(Points.Kind({ questID = 7 }) == "quest", "a bare quest point is a quest")
assert(Points.Kind({ kind = "pin", questID = 7 }) == "pin", "an explicit kind wins")
assert(Points.Kind({}) == nil and Points.Kind(nil) == nil)

-- Key: quest ID, pin ID, key, then coordinates.
assert(Points.Key({ kind = "quest", questID = 12, key = "x" }) == "quest:12")
assert(Points.Key({ kind = "pin", id = 3 }) == "pin:3")
assert(Points.Key({ kind = "treasure", key = "t1" }) == "treasure:t1")
assert(Points.Key({ kind = "treasure", worldX = 1.23456, worldY = 2 }) == "treasure:1.235:2.000")
assert(Points.Key({ kind = "treasure" }) == nil)

-- Distance: one implementation, instance-aware.
local distance, dx, dy = Points.Distance({ worldX = 0, worldY = 0 }, { worldX = 3, worldY = 4 })
assert(distance == 5 and dx == 3 and dy == 4)
assert(Points.Distance({ worldX = 0, worldY = 0, instanceID = 1 },
    { worldX = 3, worldY = 4, instanceID = 2 }) == nil, "different instances have no distance")
assert(Points.Distance({ worldX = 0 }, { worldX = 3, worldY = 4 }) == nil)

-- Near: the proximity dedupe used by World Focus (60 yd) and Bearing Bar (45 yd).
local live = { category = "rare", mapID = 5, worldX = 0, worldY = 0 }
local note = { kind = "mob", mapID = 5, worldX = 59, worldY = 0 }
assert(Points.Near(note, live, 60), "a mob note within 60 yd duplicates the live rare")
assert(not Points.Near(note, live, 45), "the radius is the caller's")
note.kind = "treasure"
assert(not Points.Near(note, live, 60), "kinds must agree")
note.kind, note.mapID = "mob", 6
assert(not Points.Near(note, live, 60), "maps must agree")
note.mapID = nil
assert(Points.Near(note, live, 60, 5), "a fallback map stands in for a missing one")

-- Matches: the identity rule between a note and a live vignette.
local target = { category = "treasure", worldX = 550, worldY = 400, name = "Live Treasure" }
note = { kind = "treasure", name = "Ancient chest", worldX = 550, worldY = 400 }
assert(Points.Matches(note, target), "the loose rule accepts the same spot")
assert(not Points.Matches(note, target, true), "the strict rule needs an identity")
note.worldX = 590
assert(not Points.Matches(note, target), "a different chest 40 yd away stays separate")
note.name = "Live Treasure"
assert(Points.Matches(note, target) and Points.Matches(note, target, true), "a specific name matches")
note.worldX = 640
assert(not Points.Matches(note, target), "names do not match beyond 60 yd")
note.worldX, note.questID, target.rewardQuestID = 590, 10, 11
assert(Points.Matches(note, target), "loose: a quest mismatch falls through to the name")
assert(not Points.Matches(note, target, true), "strict: a quest mismatch is final")
note.questID, target.rewardQuestID = nil, nil
note.objectID, target.objectGUID = 26, "GameObject-0-0-0-0-25-0000000001"
assert(Points.Matches(note, target) and not Points.Matches(note, target, true),
    "an object ID mismatch is final only for the strict rule")
note.objectID, note.name = 25, "Other"
assert(Points.Matches(note, target, true), "a matching object ID is enough")
note.kind = "mob"
assert(not Points.Matches(note, target), "a mob note never matches a treasure")
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
note = { kind = "treasure", name = "Amber Cache", worldX = 0, worldY = 0 }
target = { category = "treasure", name = { secret = true }, worldX = 5, worldY = 0 }
assert(not Points.Matches(note, target, true), "secret names are never compared")

-- IDs: the shared ID fields.
local ids = Points.IDs({ npcID = 4, objectID = 0, questID = 2.5 })
assert(ids.npcID == 4 and ids.objectID == nil and ids.questID == nil)

-- Publish: records, refs, view and the change event.
local changes = {}
Points.OnChanged(function(_, generation) changes[#changes + 1] = generation end)
local targets = { { key = "g1", category = "rare", name = "Rare", mapID = 5, worldX = 10, worldY = 0, instanceID = 1 },
    { key = "g2", category = "treasure", name = "Old", mapID = 5, worldX = 20, worldY = 0, instanceID = 1, stale = true } }
local quests = { { questID = 77, name = "Quest", mapID = 5, mapX = .5, mapY = .25, worldX = 0, worldY = 30, instanceID = 1 } }
local notes = { { key = "hn:5:1", kind = "mob", name = "Mob", mapID = 5, worldX = 500, worldY = 0, instanceID = 1, npcID = 9 } }
local pins = { { id = 4, name = "Pin", worldX = 0, worldY = 5, instanceID = 1 } }
local player = { mapID = 5, worldX = 0, worldY = 0, instanceID = 1, facing = 1.5 }
local generation = Points.Publish({ mapID = 5, player = player, range = 450,
    targets = targets, quests = quests, notes = notes, pins = pins })
assert(generation == 1 and changes[1] == 1, "publishing must announce the new generation")
assert(Points.Refs("live") == targets and Points.Refs("saved") == notes, "readers get the published lists")
assert(#Points.All() == 5)
local rare = Points.Get("vignette:g1")
assert(rare and rare.kind == "rare" and rare.evidence == "live" and rare.ref == targets[1])
local mob = Points.Get("note:hn:5:1")
assert(mob and mob.kind == "rare" and mob.rawKind == "mob" and mob.ids.npcID == 9, "notes normalize mob to rare")
assert(Points.Get("quest:77:5000:2500").kind == "quest")
assert(Points.Get("pin:4").kind == "pin")
local view = Points.View()
assert(view.mapID == 5 and view.player == player and view.range == 450 and view.facing == 1.5
    and view.generation == 1, "the view carries the scan's position, range and facing")
assert(Points.ViewDistance(rare) == 10)
local rares = Points.Filter({ kinds = "rare" })
assert(#rares == 2, "a mob note and a live rare are both rares")
assert(#Points.Filter({ kinds = "rare", evidence = "live" }) == 1)
assert(#Points.Filter({ kinds = "rare", maxYards = 100 }) == 1, "maxYards uses the view's player")
assert(#Points.Filter({ kinds = "treasure" }) == 0, "stale entries are hidden by default")
assert(#Points.Filter({ kinds = "treasure", includeStale = true }) == 1)
Points.Publish({ mapID = 5, player = player, targets = targets })
assert(Points.Get("vignette:g1") == rare, "a republished raw entry keeps its record")
assert(#Points.Refs("saved") == 0 and changes[2] == 2)

-- Icon: Blizzard's own art first, then a map pack's icon, then the diamond.
issecretvalue = nil
local function Atlas(item) return Points.Icon(item).atlas end
assert(Atlas({ category = "rare", atlasName = "VignetteKillElite" }) == "VignetteKillElite",
    "a live vignette keeps its own atlas")
assert(Atlas({ category = "rare" }) == "VignetteKill" and Atlas({ kind = "mob" }) == "VignetteKill")
assert(Atlas({ category = "rare", isWorldBoss = true }) == "VignetteKillElite")
assert(Atlas({ category = "rare", isElite = true }) == "VignetteKillElite")
assert(Atlas({ category = "rare", isBoss = true }) == "vignettekillboss")
assert(Atlas({ kind = "treasure" }) == "VignetteLoot" and Atlas({ kind = "treasure", isElite = true }) == "VignetteLootElite")
assert(Atlas({ category = "event" }) == "VignetteEvent" and Atlas({ category = "event", elite = true }) == "VignetteEventElite")
assert(Atlas({ kind = "quest", questID = 1, completed = true }) == "QuestTurnin")
assert(Atlas({ questID = 1, readyForTurnIn = true }) == "QuestTurnin")
assert(Atlas({ kind = "quest", questID = 1, availableStart = true }) == "QuestNormal")
assert(Atlas({ kind = "quest", questID = 1, availableStart = true, isCampaign = true }) == "Quest-Campaign-Available")
assert(Atlas({ kind = "quest", questID = 1, taskType = "world" }) == "Worldquest-icon")
local progress = Points.Icon({ kind = "quest", questID = 1, colorSlot = 3 })
assert(progress.diamond and progress.label == "3", "an in-progress quest wears its tracker number")
assert(Points.Icon({ kind = "quest", questID = 1 }).label == "1")
assert(Points.Icon({ kind = "quest", questID = 1, colorSlot = 3 }) == progress, "descriptors are cached")
local entrance = Points.Icon({ kind = "entrance" })
assert(entrance.diamond and entrance.label == "C" and Points.Icon({ kind = "guide" }).label == "G"
    and Points.Icon({ kind = "note" }).label == "N" and Points.Icon(nil).label == "?")
local packIcon = { texture = "Interface\\Icons\\Cave", texCoord = { 0, .5, 0, .5 }, color = { 1, 0, 0, 1 } }
local pack = Points.Icon({ kind = "entrance", icon = packIcon })
assert(pack.texture == "Interface\\Icons\\Cave" and pack.coords[2] == .5 and pack.color[2] == 0,
    "a pack icon is kept when the kind has no Blizzard atlas")
assert(Points.Icon({ kind = "note", icon = 12345 }).texture == 12345)
assert(Atlas({ kind = "treasure", icon = packIcon }) == "VignetteLoot", "Blizzard's atlas beats a pack icon")
assert(Atlas(Points.Get("vignette:g1")) == "VignetteKill", "a point record describes its raw entry")

-- ApplyIcon: SetAtlas when the client has the atlas, the diamond otherwise.
local function Region()
    local region = {}
    function region:SetAtlas(name) self.atlas, self.texture = name, nil end
    function region:SetTexture(value) self.texture, self.atlas = value, nil end
    function region:SetTexCoord(...) self.coords = { ... } end
    return region
end
local region = Region()
assert(Points.ApplyIcon(region, nil, { kind = "treasure" }, "diamond").atlas == "VignetteLoot"
    and region.atlas == "VignetteLoot")
C_Texture = { GetAtlasInfo = function(name) return name ~= "Missing" and {} or nil end }
local shown = Points.ApplyIcon(region, nil, { category = "rare", atlasName = "Missing" }, "diamond")
assert(shown.diamond and shown.label == "R" and region.texture == "diamond" and region.coords[2] == 1,
    "an unknown atlas falls back to the diamond and resets the coordinates")
region.SetAtlas = function() return false end
shown = Points.ApplyIcon(region, nil, { kind = "event" }, "diamond")
assert(shown.diamond and shown.label == "E", "SetAtlas returning false falls back")
region.SetAtlas = function() error("bad atlas") end
assert(Points.ApplyIcon(region, nil, { kind = "quest", questID = 1, completed = true }, "diamond").label == "Q",
    "a SetAtlas error falls back")
region = Region()
shown = Points.ApplyIcon(region, nil, { kind = "entrance", icon = packIcon }, "diamond")
assert(shown == pack and region.texture == packIcon.texture and region.coords[2] == .5)
C_Texture = nil

print("VignetteRadar points tests passed")
