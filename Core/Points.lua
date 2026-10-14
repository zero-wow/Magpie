local _, addon = ...
if type(addon) ~= "table" then return end

-- One point registry. The radar scan publishes its live vignettes, quest
-- points, map notes and pins here once per scan; every reader takes the same
-- lists, the same kind names, one distance and one identity rule.
--   Points.Publish(scan) -> generation      (scan = { mapID, player, range,
--                                             targets, quests, notes, pins })
--   Points.Refs(evidence) -> raw list       ("live", "quest", "saved", "pin")
--   Points.All() / Points.Get(id) / Points.Filter(options)
--   Points.View() -> { mapID, player, range, facing, generation }
--   Points.Kind(item) / Points.Key(item) / Points.Distance(a, b)
--   Points.Badge(item) / Points.Icon(item) / Points.ApplyIcon(region, icon, item, diamond)
--   Points.Near(a, b, yards [, mapID]) / Points.Matches(note, live [, strict])
--   Points.MapToWorld(mapID, x, y) -> worldX, worldY, instanceID
--   Points.IsPlaceholderName(name)          (a pack's "Treasure location")
--   Points.OnChanged(handler)               (Bus topic POINTS_CHANGED)
-- A record never copies per-frame data: distance comes from the view.
local Points = {}
addon.VignetteRadarPoints = Points

local type, tostring, tonumber, ipairs = type, tostring, tonumber, ipairs
local Field, Number, Text = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text

local EMPTY = {}
local NOTE_KINDS = { mob = "rare" }
local PLACEHOLDER_NAMES = { treasurelocation = true, moblocation = true, detectedvignette = true }

local refs = { live = EMPTY, quest = EMPTY, saved = EMPTY, pin = EMPTY }
local records, byID = {}, {}
local generation = 0
local view = { generation = 0 }
-- raw table -> its record, so unchanged pack notes are not rebuilt each scan.
local cache = setmetatable({}, { __mode = "k" })

-- One kind vocabulary: map-note "mob" is a rare, vignettes keep their category,
-- quest points without a kind are quests.
function Points.Kind(item)
    if type(item) ~= "table" then return nil end
    local kind = Text(item.kind) or Text(item.category) or Text(item.type)
    if kind then return NOTE_KINDS[kind] or kind end
    if Number(item.questID) then return "quest" end
    return nil
end

-- One letter per kind, shown on markers so you can tell what a point is.
local BADGES = { quest = "Q", rare = "R", treasure = "T", event = "E", entrance = "C",
    guide = "G", note = "N", item = "I", other = "?" }
function Points.Badge(item)
    local kind = type(item) == "table" and Points.Kind(item) or item
    if kind == "quest" and type(item) == "table" and item.availableStart then return "!" end
    return BADGES[kind] or "?"
end

-- One icon per point, Blizzard's own art first (the atlases RareScanner and
-- HandyNotes use). Points.Icon(item) returns a shared, read-only descriptor:
--   { atlas = name }                         a Blizzard atlas, never tinted
--   { texture = path, coords = {l, r, t, b}, color = {r, g, b, a} }
--                                            a map pack's own icon
--   { diamond = true, label = text }         the tinted diamond and its letter
-- An in-progress quest is a diamond numbered with its tracker color slot,
-- like the quest tracker. Descriptors are cached, so hot paths allocate none.
local KIND_ATLAS = {
    rare = { "VignetteKill", "VignetteKillElite" },
    treasure = { "VignetteLoot", "VignetteLootElite" },
    event = { "VignetteEvent", "VignetteEventElite" },
}
local atlasIcons, diamondIcons = {}, {}
local packIcons = setmetatable({}, { __mode = "k" })

local function AtlasIcon(name)
    local icon = atlasIcons[name]
    if not icon then icon = { atlas = name }; atlasIcons[name] = icon end
    return icon
end

local function DiamondIcon(label)
    local icon = diamondIcons[label]
    if not icon then icon = { diamond = true, label = label }; diamondIcons[label] = icon end
    return icon
end
Points.DiamondIcon = DiamondIcon

-- A HandyNotes/Zygor icon: a path or file ID, or POIs' { texture, texCoord, color }.
local function PackIcon(value)
    if Text(value) or (Number(value) and value > 0) then
        local icon = packIcons[value]
        if not icon then icon = { texture = value }; packIcons[value] = icon end
        return icon
    end
    if type(value) ~= "table" then return nil end
    local icon = packIcons[value]
    if icon then return icon end
    local texture = Field(value, "texture")
    if not (Text(texture) or (Number(texture) and texture > 0)) then return nil end
    local coords = Field(value, "texCoord") or Field(value, "coords")
    local color = Field(value, "color")
    icon = { texture = texture, coords = type(coords) == "table" and coords or nil,
        color = type(color) == "table" and color or nil }
    packIcons[value] = icon
    return icon
end

function Points.Icon(item)
    if type(item) ~= "table" then return DiamondIcon("?") end
    -- A point record describes its raw entry.
    local kind
    if item.evidence and type(item.ref) == "table" then kind, item = item.kind, item.ref
    else kind = Points.Kind(item) end
    local atlas = Text(Field(item, "atlasName"), 120)
    if atlas then return AtlasIcon(atlas) end
    if kind == "quest" then
        if Field(item, "completed") == true or Field(item, "isComplete") == true
            or Field(item, "readyForTurnIn") == true then return AtlasIcon("QuestTurnin") end
        if Field(item, "availableStart") == true then
            return AtlasIcon((Field(item, "isCampaign") == true or Field(item, "campaign") == true)
                and "Quest-Campaign-Available" or "QuestNormal")
        end
        if Field(item, "taskType") == "world" or Field(item, "isWorldQuest") == true then
            return AtlasIcon("Worldquest-icon")
        end
        return DiamondIcon(tostring(Number(Field(item, "colorSlot")) or 1))
    end
    local pair = KIND_ATLAS[kind]
    if pair then
        if kind == "rare" and Field(item, "isBoss") == true then return AtlasIcon("vignettekillboss") end
        local elite = Field(item, "isElite") == true or Field(item, "elite") == true
            or Field(item, "isWorldBoss") == true
        return AtlasIcon(pair[elite and 2 or 1])
    end
    return PackIcon(Field(item, "icon")) or DiamondIcon(Points.Badge(item))
end

local function AtlasExists(name)
    local textures = C_Texture
    local info = type(textures) == "table" and textures.GetAtlasInfo
    if type(info) ~= "function" then return true end
    local ok, found = pcall(info, name)
    return ok and found ~= nil
end

-- Puts a descriptor on a texture region and returns the one shown. An atlas
-- the client lacks (unknown, SetAtlas errors or returns false) falls back to
-- the diamond with the item's letter. diamondTexture is the caller's diamond
-- art. Colour is the caller's: atlases keep white, diamonds take the kind.
function Points.ApplyIcon(region, icon, item, diamondTexture)
    icon = icon or Points.Icon(item)
    if icon.atlas then
        if region.SetAtlas and AtlasExists(icon.atlas) then
            local ok, result = pcall(region.SetAtlas, region, icon.atlas)
            if ok and result ~= false then return icon end
        end
        icon = DiamondIcon(Points.Badge(item))
    end
    region:SetTexture(icon.texture or diamondTexture)
    local coords = icon.coords
    if region.SetTexCoord then
        if coords then region:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else region:SetTexCoord(0, 1, 0, 1) end
    end
    return icon
end

local function Identity(value)
    if type(value) == "string" then return Text(value, 100, true) end
    if Number(value) then return tostring(value) end
    return nil
end

-- A stable "kind:id" for an item: the quest ID for quests, the pin ID for
-- pins, the key otherwise, and rounded world coordinates as a last resort.
function Points.Key(item)
    local kind = Points.Kind(item)
    if not kind then return nil end
    local id
    if kind == "quest" then id = Identity(Field(item, "questID")) or Identity(Field(item, "key"))
    elseif kind == "pin" then id = Identity(Field(item, "id")) or Identity(Field(item, "key"))
    else id = Identity(Field(item, "key")) or Identity(Field(item, "id")) end
    if not id then
        local x, y = Number(Field(item, "worldX")), Number(Field(item, "worldY"))
        if not (x and y) then return nil end
        id = string.format("%.3f:%.3f", x, y)
    end
    return kind .. ":" .. id
end

-- Straight-line yards from a to b, then the offsets. nil when a position is
-- missing or the two sit in different instances. Hot paths call this, so it
-- indexes the addon's own tables directly and only guards the values.
function Points.Distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local ax, ay, bx, by = Number(a.worldX), Number(a.worldY), Number(b.worldX), Number(b.worldY)
    if not (ax and ay and bx and by) then return nil end
    local ai, bi = Number(a.instanceID), Number(b.instanceID)
    if ai and bi and ai ~= bi then return nil end
    local dx, dy = bx - ax, by - ay
    return math.sqrt(dx * dx + dy * dy), dx, dy
end

-- Map x/y (0-1) to world yards through C_Map.GetWorldPosFromMapPos, for
-- point sources outside the radar scan (/way, area POIs). Returns worldX,
-- worldY, instanceID, or nil when the map has no world position.
function Points.MapToWorld(mapID, x, y)
    mapID, x, y = Number(mapID), Number(x), Number(y)
    if not (mapID and x and y) then return nil end
    local vector = type(CreateVector2D) == "function" and addon.Secret.Call(_G, "CreateVector2D", x, y)
        or { x = x, y = y }
    local instanceID, position = addon.Secret.Call(C_Map, "GetWorldPosFromMapPos", mapID, vector)
    if type(position) ~= "table" then return nil end
    local getXY = Field(position, "GetXY")
    local wx, wy
    if type(getXY) == "function" then
        local ok, a, b = pcall(getXY, position)
        if ok then wx, wy = Number(a), Number(b) end
    else
        wx, wy = Number(Field(position, "x")), Number(Field(position, "y"))
    end
    if not (wx and wy) then return nil end
    return wx, wy, Number(instanceID)
end

-- The proximity dedupe: same kind, same map, within yards. mapID stands in
-- for an item without its own map.
function Points.Near(a, b, yards, mapID)
    local kind = Points.Kind(a)
    if not kind or kind ~= Points.Kind(b) then return false end
    if (a.mapID or mapID) ~= (b.mapID or mapID) then return false end
    local ax, ay, bx, by = Number(a.worldX), Number(a.worldY), Number(b.worldX), Number(b.worldY)
    if not (ax and ay and bx and by and Number(yards)) then return false end
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy <= yards * yards
end

local function NormalName(value)
    local name = Text(value)
    if not name then return nil end
    name = name:lower():gsub("[^%w]", "")
    if #name < 6 or PLACEHOLDER_NAMES[name] then return nil end
    return name
end

-- The identity rule between a saved note and a live vignette, within 60 yd:
-- the same reward quest, the same object or NPC ID in the vignette's GUID,
-- or the same specific name. The loose form (the radar's) also accepts
-- anything within 10 yd and lets a mismatched ID fall through to the name;
-- the strict form (the HUD's) does neither.
function Points.Matches(note, live, strict)
    if type(note) ~= "table" or type(live) ~= "table" then return false end
    local nx, ny, lx, ly = Number(note.worldX), Number(note.worldY), Number(live.worldX), Number(live.worldY)
    if not (nx and ny and lx and ly) then return false end
    local kind, category = Text(note.kind), Text(live.category)
    if not ((kind == "treasure" and category == "treasure")
        or (kind == "mob" and category == "rare")) then return false end
    local dx, dy = nx - lx, ny - ly
    local squared = dx * dx + dy * dy
    if not strict and squared <= 100 then return true end
    if squared > 3600 then return false end
    local noteQuest, liveQuest = Number(note.questID), Number(live.rewardQuestID)
    if noteQuest and liveQuest then
        if noteQuest == liveQuest then return true end
        if strict then return false end
    end
    local guid = Text(live.objectGUID)
    if guid then
        local guidKind, id = guid:match("^([A-Za-z]+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        id = tonumber(id)
        local noteID = guidKind == "GameObject" and Number(note.objectID)
            or (guidKind == "Creature" or guidKind == "Vehicle") and Number(note.npcID)
            or nil
        if noteID and id then
            if noteID == id then return true end
            if strict then return false end
        end
    end
    local left, right = NormalName(note.name), NormalName(live.name)
    return left ~= nil and left == right
end

-- The ID fields every source shares (SourceFusion matches on these).
local ID_FIELDS = { "npcID", "objectID", "questID" }
Points.ID_FIELDS = ID_FIELDS

function Points.IDs(item, into)
    local ids = into or {}
    for index = 1, #ID_FIELDS do
        local field = ID_FIELDS[index]
        local id = tonumber(Field(item, field))
        ids[field] = id and id > 0 and id == math.floor(id) and id or nil
    end
    return ids
end

local ID_PREFIX = { live = "vignette", quest = "quest", saved = "note", pin = "pin", party = "party" }

local function Record(raw, evidence)
    local record = cache[raw]
    if not record then
        record = { ids = {} }
        cache[raw] = record
    end
    local kind = Points.Kind(raw)
    if evidence == "quest" then kind = "quest" elseif evidence == "pin" then kind = "pin" end
    -- Group-shared notes (Routes/SharedSightings.lua) ride the notes list but
    -- keep their own evidence, so readers can tell "a friend said" from a pack.
    if evidence == "saved" and Field(raw, "evidence") == "party" then evidence = "party" end
    record.ref, record.evidence, record.kind = raw, evidence, kind
    record.rawKind = Text(Field(raw, "kind")) or Text(Field(raw, "category"))
    record.name = Text(Field(raw, "name"))
    record.mapID = Number(Field(raw, "mapID"))
    record.mapX, record.mapY = Number(Field(raw, "mapX")), Number(Field(raw, "mapY"))
    record.worldX, record.worldY = Number(Field(raw, "worldX")), Number(Field(raw, "worldY"))
    record.instanceID = Number(Field(raw, "instanceID"))
    record.source = Text(Field(raw, "source"))
    Points.IDs(raw, record.ids)
    record.ids.vignetteID = Number(Field(raw, "vignetteID"))
    local id
    if evidence == "quest" then
        id = Identity(Field(raw, "questID"))
        if id and record.mapX and record.mapY then
            id = id .. ":" .. math.floor(record.mapX * 10000 + .5) .. ":" .. math.floor(record.mapY * 10000 + .5)
        end
    elseif evidence == "pin" then id = Identity(Field(raw, "id")) or Identity(Field(raw, "key"))
    else id = Identity(Field(raw, "key")) end
    record.id = id and (ID_PREFIX[evidence] .. ":" .. id) or nil
    return record
end

local function Collect(list, evidence, output, seen)
    if type(list) ~= "table" then return EMPTY end
    for _, raw in ipairs(list) do
        if type(raw) == "table" then
            local record = Record(raw, evidence)
            output[#output + 1] = record
            if record.id and not seen[record.id] then seen[record.id] = record end
        end
    end
    return list
end

-- Called once per radar scan with the final, filtered lists. Lists are kept
-- by reference; readers must not edit them.
function Points.Publish(scan)
    scan = type(scan) == "table" and scan or EMPTY
    local output, seen = {}, {}
    refs = {
        live = Collect(scan.targets, "live", output, seen),
        quest = Collect(scan.quests, "quest", output, seen),
        saved = Collect(scan.notes, "saved", output, seen),
        pin = Collect(scan.pins, "pin", output, seen),
    }
    records, byID = output, seen
    generation = generation + 1
    local player = type(scan.player) == "table" and scan.player or nil
    view = { mapID = scan.mapID, player = player, range = Number(scan.range),
        facing = player and Number(player.facing) or nil, generation = generation }
    local bus = addon.Bus
    if bus then bus.Emit("POINTS_CHANGED", generation) end
    return generation
end

function Points.Refs(evidence)
    return refs[evidence] or EMPTY
end

-- The stand-in names map packs give unnamed notes (Data/POIs.lua: "Treasure
-- location", "Mob location", "Item location", "Map note", "Cave entrance")
-- and the scan's "Detected vignette". Readers show a kind and zone instead.
local STAND_IN_NAMES = { treasurelocation = true, moblocation = true, itemlocation = true,
    mapnote = true, caveentrance = true, detectedvignette = true }
function Points.IsPlaceholderName(name)
    name = Text(name)
    if not name then return true end
    name = name:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[^%w]", "")
    return name == "" or STAND_IN_NAMES[name] == true
end

function Points.All() return records end
function Points.Get(id) return id and byID[id] or nil end
function Points.View() return view end
function Points.Generation() return generation end

-- Yards from the scan's player, nil without a usable position.
function Points.ViewDistance(record)
    return view.player and Points.Distance(view.player, record) or nil
end

local function Set(value)
    if type(value) == "string" then return { [value] = true } end
    return type(value) == "table" and value or nil
end

-- Filter{ kinds =, evidence =, maxYards =, mapID =, includeStale = false }:
-- kinds and evidence take a name or a set of names.
function Points.Filter(options)
    options = type(options) == "table" and options or EMPTY
    local kinds, evidence = Set(options.kinds), Set(options.evidence)
    local maxYards = Number(options.maxYards)
    local output = {}
    for _, record in ipairs(records) do
        if (not kinds or kinds[record.kind]) and (not evidence or evidence[record.evidence])
            and (not options.mapID or record.mapID == options.mapID)
            and (options.includeStale or Field(record.ref, "stale") ~= true) then
            local distance = maxYards and Points.ViewDistance(record)
            if not maxYards or (distance and distance <= maxYards) then output[#output + 1] = record end
        end
    end
    return output
end

function Points.OnChanged(handler)
    local bus = addon.Bus
    if bus and type(handler) == "function" then bus.On("POINTS_CHANGED", handler) end
end

return Points
