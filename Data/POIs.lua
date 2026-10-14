local _, addon = ...
if type(addon) ~= "table" then return end

-- Map notes are possible locations supplied by one selected HandyNotes plugin.
-- Keep them separate from live vignettes so they cannot trigger detection alerts.
local POIs = {}
addon.VignetteRadarPOIs = POIs

local MAX_NODES = 768
local PROBE_NODES = 96
local SOURCE_CACHE_SECONDS = 10
-- Packs can answer with nothing while they finish loading (phasing, groups,
-- item data). Retry soon instead of hiding them for the full cache window.
local EMPTY_CACHE_SECONDS = 2
local sourceCache, cacheOrder = {}, {}
local autoChoice
local ZYGOR_SOURCE = "Zygor POIs"
local npcNames = {}
function POIs.Invalidate()
    sourceCache, cacheOrder, autoChoice = {}, {}, nil
end
local Safe, Field, String = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Text

local function NPCName(id)
    id = tonumber(id)
    if not id or not (C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function") then return nil end
    if npcNames[id] then return npcNames[id] end
    local ok, info = pcall(C_TooltipInfo.GetHyperlink, "unit:Creature-0-0-0-0-" .. id)
    local lines = ok and Field(info, "lines")
    local name = lines and String(Field(Field(lines, 1), "leftText"))
    if name then npcNames[id] = name end
    return name
end

local function DisplayText(value)
    value = String(value)
    if not value then return nil end
    -- Some data packs store labels as lightweight {kind:id:label} tokens.
    value = value:gsub("{npc:(%d+):([^{}]+)}", function(id, label)
        return NPCName(id) or label
    end):gsub("{npc:(%d+)}", function(id)
        return NPCName(id) or "Creature"
    end):gsub("{[^{}:]+:[^{}:]+:([^{}]+)}", "%1")
        :gsub("{[^{}]+}", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return String(value:match("^%s*(.-)%s*$"))
end

local function HandyNotes()
    local notes = _G.HandyNotes
    return type(notes) == "table" and type(notes.plugins) == "table" and notes or nil
end

local function ZygorPoints(mapID)
    local viewer = _G.ZygorGuidesViewer
    local poi = viewer and Field(viewer, "Poi")
    if not poi or Field(poi, "DoneLoadingPoints") ~= true then return nil end
    local points = Field(poi, "Points")
    local zone = points and Field(points, mapID)
    return type(zone) == "table" and zone or nil
end

-- Pack Takeover hides a pack's own HandyNotes pins; VR keeps reading it.
local function Store() return addon.VignetteRadarPackStore end

local function Enabled(notes, name)
    local profile = notes.db and notes.db.profile
    local enabled = profile and profile.enabledPlugins
    if not enabled or enabled[name] ~= false then return true end
    local store = Store()
    return store and store.HiddenByVR(name) or false
end

local function Live(notes, name)
    local handler = notes and notes.plugins[name]
    return type(handler) == "table" and type(handler.GetNodes2) == "function" or false
end

function POIs.Sources()
    local sources, notes = {}, HandyNotes()
    if notes then
        for name, handler in pairs(notes.plugins) do
            if type(name) == "string" and type(handler) == "table"
                and type(handler.GetNodes2) == "function" then
                sources[#sources + 1] = { id = name, enabled = Enabled(notes, name) }
            end
        end
    end
    -- Packs VR saved earlier keep working after the pack itself is disabled.
    local store = Store()
    for _, name in ipairs(store and store.Sources() or {}) do
        if not Live(notes, name) then sources[#sources + 1] = { id = name, enabled = true, saved = true } end
    end
    local poi = _G.ZygorGuidesViewer and Field(_G.ZygorGuidesViewer, "Poi")
    if poi and Field(poi, "DoneLoadingPoints") == true then
        sources[#sources + 1] = { id = ZYGOR_SOURCE, enabled = true }
    end
    table.sort(sources, function(a, b) return a.id:lower() < b.id:lower() end)
    return sources
end

local function CandidateMaps(mapID)
    local maps, seen = { mapID }, { [mapID] = true }
    if not (C_Map and type(C_Map.GetMapInfo) == "function") then return maps end
    for _ = 1, 3 do
        local ok, info = pcall(C_Map.GetMapInfo, maps[#maps])
        local parent = ok and Field(info, "parentMapID") or nil
        if type(parent) ~= "number" or parent <= 0 or seen[parent] then break end
        local parentOK, parentInfo = pcall(C_Map.GetMapInfo, parent)
        if not parentOK then break end
        local mapType = Field(parentInfo, "mapType")
        local continent = Enum and Enum.UIMapType and Enum.UIMapType.Continent
        maps[#maps + 1], seen[parent] = parent, true
        if continent ~= nil and mapType == continent then break end
    end
    return maps
end

-- Returns the visible note count and whether the pack handles this map. A
-- handled map hands back its node table even while it yields nothing yet.
local function Probe(handler, mapID)
    local ok, iterator, state, key = pcall(handler.GetNodes2, handler, mapID, false)
    if not ok or type(iterator) ~= "function" then return 0, false end
    local hasNodes, first = false, nil
    if Safe(state) and type(state) == "table" then
        hasNodes, first = pcall(next, state)
    end
    local handled = hasNodes and first ~= nil
    local count = 0
    for _ = 1, MAX_NODES do
        local yielded, coord, _, _, _, alpha = pcall(iterator, state, key)
        if not yielded or not Safe(coord) or type(coord) ~= "number" then break end
        key = coord
        if coord >= 0 and coord < 100010000 and Safe(alpha)
            and (type(alpha) ~= "number" or alpha > 0) then
            count = count + 1
            if count >= PROBE_NODES then break end
        end
    end
    return count, handled or count > 0
end

-- Query each registered pack for the current map, then its immediate zone
-- ancestors. A short cache keeps config redraws and one-second scans cheap.
function POIs.ZoneSources(mapID)
    local notes = HandyNotes()
    if not (type(mapID) == "number" and Safe(mapID)) then return {} end
    local now = type(GetTime) == "function" and GetTime() or nil
    -- Key the snapshot on which packs are registered AND enabled, so toggling
    -- a pack in HandyNotes re-probes at once instead of after the cache expires.
    local registry = {}
    if notes then
        for name in pairs(notes.plugins) do
            if type(name) == "string" then
                registry[#registry + 1] = name .. (Enabled(notes, name) and "+" or "-")
            end
        end
    end
    table.sort(registry)
    local poi = _G.ZygorGuidesViewer and Field(_G.ZygorGuidesViewer, "Poi")
    if poi and Field(poi, "DoneLoadingPoints") == true then registry[#registry + 1] = ZYGOR_SOURCE end
    local store = Store()
    if store then registry[#registry + 1] = "saved" .. store.Generation() end
    local registryKey = table.concat(registry, "\n")
    local snapshot = sourceCache[mapID]
    if snapshot and snapshot.registryKey == registryKey
        and now and snapshot.at and now - snapshot.at < snapshot.ttl then
        local cached = {}
        for _, entry in ipairs(snapshot.entries) do
            if entry.id == ZYGOR_SOURCE or entry.saved or (notes and Enabled(notes, entry.id)) then
                cached[#cached + 1] = entry
            end
        end
        return cached
    end
    local maps, entries, visible = CandidateMaps(mapID), {}, false
    for name, handler in pairs(notes and notes.plugins or {}) do
        if type(name) == "string" and type(handler) == "table"
            and type(handler.GetNodes2) == "function" and Enabled(notes, name) then
            local found, handledAt
            for depth, candidate in ipairs(maps) do
                local count, handled = Probe(handler, candidate)
                if count > 0 then
                    found = { id = name, enabled = true,
                        mapID = candidate, depth = depth - 1, count = count }
                    break
                elseif handled and not handledAt then
                    handledAt = { id = name, enabled = true,
                        mapID = candidate, depth = depth - 1, count = 0 }
                end
            end
            found = found or handledAt
            if found then
                entries[#entries + 1] = found
                if found.count > 0 then visible = true end
            end
        end
    end
    for _, name in ipairs(store and store.Sources() or {}) do
        if not Live(notes, name) then
            for depth, candidate in ipairs(maps) do
                local count = store.Count(name, candidate)
                if count > 0 then
                    entries[#entries + 1] = { id = name, enabled = true, saved = true,
                        mapID = candidate, depth = depth - 1, count = math.min(count, PROBE_NODES) }
                    visible = true
                    break
                end
            end
        end
    end
    for depth, candidate in ipairs(maps) do
        local zone = ZygorPoints(candidate)
        if zone and #zone > 0 then
            entries[#entries + 1] = { id = ZYGOR_SOURCE, enabled = true,
                mapID = candidate, depth = depth - 1, count = math.min(#zone, PROBE_NODES) }
            visible = true
            break
        end
    end
    table.sort(entries, function(a, b) return a.id:lower() < b.id:lower() end)
    if not snapshot then
        cacheOrder[#cacheOrder + 1] = mapID
        if #cacheOrder > 8 then sourceCache[table.remove(cacheOrder, 1)] = nil end
    end
    sourceCache[mapID] = { registryKey = registryKey, at = now, entries = entries,
        ttl = visible and SOURCE_CACHE_SECONDS or EMPTY_CACHE_SECONDS }
    return entries
end

local function MapNameHints(mapID)
    local snapshot = sourceCache[mapID]
    if snapshot and snapshot.mapNames then return snapshot.mapNames end
    local names, seen = {}, {}
    local current = mapID
    if C_Map and type(C_Map.GetMapInfo) == "function" then
        for depth = 1, 6 do
            if type(current) ~= "number" or seen[current] then break end
            seen[current] = true
            local ok, info = pcall(C_Map.GetMapInfo, current)
            if not ok then break end
            local name = String(Field(info, "name"))
            if name then
                name = name:lower():gsub("[^%w]", "")
                if #name >= 5 then names[#names + 1] = name end
            end
            current = Field(info, "parentMapID")
        end
    end
    if snapshot then snapshot.mapNames = names end
    return names
end

local function NameAffinity(id, names)
    local lower = id:lower():gsub("[^%w]", "")
    for depth, name in ipairs(names) do
        if lower:find(name, 1, true) then return #names - depth + 1 end
    end
    return 0
end

function POIs.ResolveSource(mapID, chosen)
    if chosen == "none" or type(mapID) ~= "number" then return nil end
    local best, sticky, bestAffinity = nil, nil, -1
    local entries = POIs.ZoneSources(mapID)
    local zoneChoice = chosen == "auto" and addon.GetSettings().vignetteRadarPOIZoneSources[mapID]
    if zoneChoice == "none" then return nil end
    local names = chosen == "auto" and MapNameHints(mapID) or {}
    for _, entry in ipairs(entries) do
        if chosen == entry.id then return entry.id, entry.mapID end
        if zoneChoice == entry.id and entry.enabled then return entry.id, entry.mapID end
        if chosen == "auto" and autoChoice and autoChoice.mapID == mapID
            and autoChoice.id == entry.id then sticky = entry end
        if chosen == "auto" and entry.id ~= ZYGOR_SOURCE then
            local affinity = NameAffinity(entry.id, names)
            local shows, bestShows = entry.count > 0, best and best.count > 0
            if not best or (shows and not bestShows)
                or (shows == bestShows and affinity > bestAffinity)
                or (shows == bestShows and affinity == bestAffinity and entry.depth < best.depth)
                or (shows == bestShows and affinity == bestAffinity
                    and entry.depth == best.depth and entry.count > best.count)
                or (shows == bestShows and affinity == bestAffinity and entry.depth == best.depth
                    and entry.count == best.count and entry.id < best.id) then
                best, bestAffinity = entry, affinity
            end
        end
    end
    if sticky and best and NameAffinity(sticky.id, names) == bestAffinity
        and sticky.depth == best.depth and (sticky.count > 0) == (best.count > 0) then
        best = sticky
    end
    if chosen == "auto" then autoChoice = best and { mapID = mapID, id = best.id } or nil end
    return best and best.id or nil, best and best.mapID or nil
end

function POIs.ZoneChoice(mapID)
    return type(mapID) == "number" and addon.GetSettings().vignetteRadarPOIZoneSources[mapID] or nil
end
function POIs.SetZoneChoice(mapID, choice)
    if type(mapID) ~= "number" then return false end
    if choice == "auto" then choice = nil end
    if choice and choice ~= "none" then
        local available = false
        for _, entry in ipairs(POIs.ZoneSources(mapID)) do
            if entry.id == choice and entry.enabled then available = true; break end
        end
        if not available then return false end
    end
    addon.GetSettings().vignetteRadarPOIZoneSources[mapID] = choice
    autoChoice = nil
    return true
end

local function GroupName(node)
    local group = Field(node, "group")
    if type(group) == "table" then
        local first = group[1] or group
        return String(Field(first, "name")) or String(Field(first, "label")) or ""
    end
    return String(group) or ""
end

function POIs.Kind(node, source)
    local label = (String(Field(node, "label")) or ""):lower()
    local atlas = (String(Field(node, "atlas")) or ""):lower()
    if Field(node, "link") and atlas:find("caveunderground", 1, true) then return "entrance" end
    if Field(node, "routes") and label:find("path to", 1, true) then return "entrance" end
    local group = GroupName(node):lower()
    local class = (String(Field(node, "class")) or ""):lower()
    local text = group .. " " .. class
    if text:find("profession", 1, true) or text:find("item", 1, true) then return "item" end
    if text:find("treasur", 1, true) or text:find("chest", 1, true)
        or text:find("container", 1, true) then return "treasure" end
    if text:find("rare", 1, true) or text:find("boss", 1, true)
        or Field(node, "npc") then return "mob" end
    local lowerSource = (source or ""):lower()
    if lowerSource:find("treasur", 1, true) then return "treasure" end
    if Field(node, "loot") then return "item" end
    if lowerSource:find("rare", 1, true) then return "mob" end
    return "note"
end

local function Name(node, kind)
    if kind == "entrance" then
        local main = Field(node, "_main")
        local parentName = main and (DisplayText(Field(main, "label")) or DisplayText(Field(main, "name")))
        if parentName then return "Entrance to " .. parentName end
    end
    local name = DisplayText(Field(node, "label")) or DisplayText(Field(node, "name"))
        or DisplayText(Field(node, "title"))
    if name == "Creature" then name = NPCName(Field(node, "npc")) end
    return name or NPCName(Field(node, "npc"))
        or ({ treasure = "Treasure location", mob = "Mob location",
            item = "Item location", note = "Map note", entrance = "Cave entrance" })[kind]
end

local function Route(node, coord)
    if Field(node, "_main") ~= node or Field(node, "_coord") ~= coord then return nil end
    local path = Field(node, "path")
    if type(path) ~= "number" and type(path) ~= "table" then return nil end
    local values = type(path) == "table" and path or { path }
    local route = {}
    -- HandyNotes' path is stored destination-first. Walk it in reverse, then
    -- finish at the treasure itself. Ignore metadata in mixed path tables.
    for index = math.min(#values, 15), 1, -1 do
        local value = values[index]
        if type(value) == "number" and value >= 0 and value < 100010000 then
            route[#route + 1] = value
        end
    end
    route[#route + 1] = coord
    return #route > 1 and route or nil
end

local function RouteSteps(route, mapID, mapToWorld, mapVector)
    if not route then return nil end
    local steps = {}
    for _, coord in ipairs(route) do
        local x, y = math.floor(coord / 10000) / 10000, (coord % 10000) / 10000
        local ok, worldX, worldY, instanceID = pcall(mapToWorld, mapID, mapVector(x, y))
        if ok and Safe(worldX) and Safe(worldY)
            and type(worldX) == "number" and type(worldY) == "number"
            and worldX == worldX and worldY == worldY then
            steps[#steps + 1] = { mapID = mapID, mapX = x, mapY = y,
                worldX = worldX, worldY = worldY, instanceID = instanceID }
        end
    end
    return #steps > 1 and steps or nil
end

local function Finite(value)
    return Safe(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge and value or nil
end

local function IconDescriptor(iconpath, scale, alpha)
    if not Safe(iconpath) then return nil end
    local descriptor = {}
    local texture = type(iconpath) == "table" and Field(iconpath, "icon") or iconpath
    if not ((type(texture) == "number" and Finite(texture) and texture > 0)
        or String(texture)) then return nil end
    descriptor.texture = texture
    if type(iconpath) == "table" then
        local left = Finite(Field(iconpath, "tCoordLeft"))
        local right = Finite(Field(iconpath, "tCoordRight"))
        local top = Finite(Field(iconpath, "tCoordTop"))
        local bottom = Finite(Field(iconpath, "tCoordBottom"))
        if left and right and top and bottom and left >= 0 and right <= 1
            and top >= 0 and bottom <= 1 and left < right and top < bottom then
            descriptor.texCoord = { left, right, top, bottom }
        end
        local r = Finite(Field(iconpath, "r"))
        local g = Finite(Field(iconpath, "g"))
        local b = Finite(Field(iconpath, "b"))
        local a = Finite(Field(iconpath, "a"))
        if r and g and b then
            descriptor.color = { math.max(0, math.min(1, r)),
                math.max(0, math.min(1, g)), math.max(0, math.min(1, b)),
                a and math.max(0, math.min(1, a)) or 1 }
        end
    end
    descriptor.scale = math.max(.6, math.min(1.5, Finite(scale) or 1))
    descriptor.alpha = math.max(0, math.min(1, Finite(alpha) or 1))
    return descriptor
end

function POIs.Collect(mapID, source, mapToWorld, mapVector)
    local results, notes = {}, HandyNotes()
    if not (type(mapID) == "number" and type(source) == "string"
        and type(mapToWorld) == "function" and type(mapVector) == "function") then return results end
    if source == ZYGOR_SOURCE then
        local zone = ZygorPoints(mapID)
        if not zone then return results end
        for index = 1, math.min(#zone, MAX_NODES) do
            local point = zone[index]
            local x, y = Finite(Field(point, "x")), Finite(Field(point, "y"))
            local pointType = Field(point, "type")
            local kind = pointType == "rare" and "mob"
                or pointType == "treasure" and "treasure" or nil
            if kind and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                local ok, worldX, worldY, instanceID = pcall(function()
                    return mapToWorld(mapID, mapVector(x, y))
                end)
                if ok and Finite(worldX) and Finite(worldY) then
                    results[#results + 1] = {
                        key = ZYGOR_SOURCE .. ":" .. mapID .. ":" .. index,
                        mapID = mapID, mapX = x, mapY = y,
                        worldX = worldX, worldY = worldY, instanceID = instanceID,
                        source = ZYGOR_SOURCE, kind = kind,
                        name = DisplayText(Field(point, "name")) or Name(nil, kind),
                        note = DisplayText(Field(point, "comment")),
                        questID = tonumber(Field(point, "quest")),
                        zygorPoint = point,
                    }
                end
            end
        end
        return results
    end
    local store = Store()
    if not Live(notes, source) then
        -- The pack is gone (disabled or removed): read VR's saved copy.
        for _, note in ipairs(store and store.Load(source, mapID, mapToWorld, mapVector) or {}) do
            results[#results + 1] = note
        end
        return results
    end
    local handler = notes.plugins[source]
    if not Enabled(notes, source) then return results end
    local ok, iterator, state, key = pcall(handler.GetNodes2, handler, mapID, false)
    if not ok or type(iterator) ~= "function" then return results end
    for _ = 1, MAX_NODES do
        local yielded, coord, nodeMapID, iconpath, iconScale, alpha = pcall(iterator, state, key)
        if not yielded or not Safe(coord) or type(coord) ~= "number" then break end
        if coord == nil then break end
        key = coord
        local x, y = math.floor(coord / 10000) / 10000, (coord % 10000) / 10000
        local pointMapID = type(nodeMapID) == "number" and Safe(nodeMapID) and nodeMapID or mapID
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 and Safe(alpha)
            and (type(alpha) ~= "number" or alpha > 0) then
            local node = Field(state, coord)
            local kind = POIs.Kind(node, source)
            local converted, worldX, worldY, instanceID = pcall(function()
                return mapToWorld(pointMapID, mapVector(x, y))
            end)
            if converted and type(worldX) == "number" and type(worldY) == "number" then
                results[#results + 1] = {
                    key = source .. ":" .. pointMapID .. ":" .. coord,
                    mapID = pointMapID, mapX = x, mapY = y,
                    worldX = worldX, worldY = worldY, instanceID = instanceID,
                    source = source, kind = kind, name = Name(node, kind),
                    npcID = tonumber(Field(node, "npc")),
                    objectID = tonumber(Field(node, "object")) or tonumber(Field(node, "objectID")),
                    questID = tonumber(Field(node, "quest")),
                    note = DisplayText(Field(node, "note")),
                    icon = IconDescriptor(iconpath, iconScale, alpha),
                    route = RouteSteps(Route(node, coord), pointMapID, mapToWorld, mapVector),
                    parentCoord = kind == "entrance" and tonumber(Field(Field(node, "_main"), "_coord")) or nil,
                    -- Pack loot for the Collection Lens (Data/CollectionLens.lua); nil = no loot data.
                    loot = addon.VignetteRadarCollectionLens and addon.VignetteRadarCollectionLens.Read(node) or nil,
                }
            end
        end
    end
    -- Some packs suppress their own path pin while still exposing the parent
    -- treasure's path. Keep our entrance visible when the user enabled that
    -- note type, without making a second dot over an existing entrance pin.
    local entranceAt = {}
    local originalCount = #results
    local function EntranceKey(entry)
        return entry.mapID .. ":" .. math.floor(entry.mapX * 10000 + .5)
            .. ":" .. math.floor(entry.mapY * 10000 + .5)
    end
    for index = 1, originalCount do
        local note = results[index]
        if note.kind == "entrance" then entranceAt[EntranceKey(note)] = true end
    end
    for index = 1, originalCount do
        if #results >= MAX_NODES then break end
        local note = results[index]
        local first = note.kind == "treasure" and note.route and note.route[1]
        if first and (math.abs(first.mapX - note.mapX) > .0002
            or math.abs(first.mapY - note.mapY) > .0002) then
            local key = EntranceKey(first)
            if not entranceAt[key] then
                entranceAt[key] = true
                results[#results + 1] = {
                    key = note.key .. ":entrance", mapID = first.mapID,
                    mapX = first.mapX, mapY = first.mapY,
                    worldX = first.worldX, worldY = first.worldY,
                    instanceID = first.instanceID, source = source,
                    kind = "entrance", name = "Entrance to " .. note.name,
                    parentCoord = tonumber(note.key:match(":(%d+)$")),
                    note = "First stop on the path to " .. note.name,
                }
            end
        end
    end
    if store then store.Save(source, mapID, results) end
    return results
end
