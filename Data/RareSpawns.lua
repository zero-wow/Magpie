local _, addon = ...
if type(addon) ~= "table" then return end

-- Learned Rare Spawns: where live rare vignettes really were, saved per
-- npcID as clustered spawn points. The vignette's own world x/y is used,
-- not the player's; z comes from the player only when standing within 40 yd
-- of it. Each live GUID is recorded once per session on first sight, then
-- only its lastAt moves. While a rare is not up, its learned spawns show as
-- notes (source "Learned") through the same Declutter as pack notes.
--   RareSpawns.Observe(targets, player [, now]) -> recorded count
--   RareSpawns.Spawns(npcID) -> { { x, y, z, i, m, mx, my, n, f, l } }
--   RareSpawns.ForMap(mapID) -> notes      RareSpawns.AppendTo(notes, mapID)
-- Saved shape (VignetteRadarDB.vignetteRadarRareSpawns):
--   [npcID] = { name, map, spawns = { { x, y, z?, i?, m, mx, my, n, f, l } } }
--   x/y world yards (running mean), z height, i instance, m mapID, mx/my map
--   0-1, n sightings, f firstAt, l lastAt (server time).
-- Respawn Estimate (same entry): ups = { { f, l, k? } } one per appearance
-- (first seen, last seen, killed-while-watched time), gaps = seconds from a
-- watched kill to the next appearance (newest 6), k = newest kill time.
-- A rare counts as killed when its vignette dies (isDead), Recent saw the
-- kill, or it vanished while the player stood within 250 yd. One that only
-- left view is never a kill, so the player's travel never fakes a timer.
--   RareSpawns.Respawn(npcID [, now]) -> { killedAt, since, median, left, samples } | nil
--   RareSpawns.RespawnText(npcID [, now]) -> "Likely Up In ~20 min" | nil
local RareSpawns = {}
addon.VignetteRadarRareSpawns = RareSpawns

local type, pairs, ipairs, tonumber, floor = type, pairs, ipairs, tonumber, math.floor
local Field, Number, Text, Call = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local CLUSTER_YARDS, Z_YARDS, MAX_SPAWNS, MAX_PER_MAP = 40, 40, 8, 300
local PACK_DUPLICATE_YARDS = 60
local WATCH_YARDS, SAME_UP_SECONDS, MAX_UPS, MAX_GAPS = 250, 120, 6, 6
local MIN_GAP, MAX_GAP = 60, 6 * 3600
local seenGUID = {}  -- guid -> spawn table this session
local seenUp = {}    -- guid -> { up, npcID, x, y, m } while the vignette is live
local mapCache = {}  -- mapID -> notes
local generation = 0

local function Settings() return addon.GetSettings() end

local function Store()
    local db = Settings()
    if type(db.vignetteRadarRareSpawns) ~= "table" then db.vignetteRadarRareSpawns = {} end
    return db.vignetteRadarRareSpawns
end

local function Epoch()
    return Number(Call(_G, "GetServerTime")) or 0
end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("spawns", fmt, ...) end
end

local function NpcID(guid)
    guid = Text(guid)
    if not guid then return nil end
    local kind, id = guid:match("^([A-Za-z]+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end
RareSpawns.NpcID = NpcID

local function Height(target, player)
    local learning = addon.VignetteRadarOutcomeLearning
    local z = learning and learning.PlayerHeight and learning.PlayerHeight(player)
    if not Number(z) then return nil end
    local dx, dy = target.worldX - player.worldX, target.worldY - player.worldY
    return dx * dx + dy * dy <= Z_YARDS * Z_YARDS and z or nil
end

-- Oldest npc on the same map leaves once the map passes MAX_PER_MAP.
local function CapMap(store, mapID)
    local count, oldest, oldestID = 0, nil, nil
    for npcID, entry in pairs(store) do
        if type(entry) == "table" and entry.map == mapID then
            count = count + 1
            local last = 0
            for _, spawn in ipairs(entry.spawns or {}) do last = math.max(last, Number(spawn.l) or 0) end
            if not oldest or last < oldest then oldest, oldestID = last, npcID end
        end
    end
    if count > MAX_PER_MAP and oldestID then store[oldestID] = nil end
end

local function Record(npcID, target, player, now)
    local store = Store()
    local entry = store[npcID]
    if type(entry) ~= "table" or type(entry.spawns) ~= "table" then
        entry = { spawns = {} }
        store[npcID] = entry
    end
    entry.name = Text(target.name, 80, true) or entry.name
    entry.map = target.mapID
    local x, y, instance = target.worldX, target.worldY, Number(target.instanceID)
    local best, bestDistance
    for _, spawn in ipairs(entry.spawns) do
        if (not instance or not spawn.i or spawn.i == instance) and spawn.m == target.mapID then
            local dx, dy = spawn.x - x, spawn.y - y
            local distance = dx * dx + dy * dy
            if distance <= CLUSTER_YARDS * CLUSTER_YARDS and (not bestDistance or distance < bestDistance) then
                best, bestDistance = spawn, distance
            end
        end
    end
    local z = Height(target, player)
    if best then
        local n = (best.n or 1) + 1
        best.x, best.y = best.x + (x - best.x) / n, best.y + (y - best.y) / n
        best.mx, best.my = best.mx + (target.mapX - best.mx) / n, best.my + (target.mapY - best.my) / n
        if z then best.z = best.z and best.z + (z - best.z) / n or z end
        best.n, best.l = n, now
        Trace("npc %d seen again at spawn %d (%d sightings)", npcID, floor(bestDistance ^ .5), n)
        return best
    end
    local spawn = { x = x, y = y, z = z, i = instance, m = target.mapID, mx = target.mapX, my = target.mapY,
        n = 1, f = now, l = now }
    entry.spawns[#entry.spawns + 1] = spawn
    -- Keep the spawns seen most recently.
    if #entry.spawns > MAX_SPAWNS then
        table.sort(entry.spawns, function(a, b) return (a.l or 0) > (b.l or 0) end)
        entry.spawns[#entry.spawns] = nil
    end
    CapMap(store, target.mapID)
    Trace("npc %d new spawn on map %d (%d known)", npcID, target.mapID, #entry.spawns)
    return spawn
end

-- Respawn Estimate ---------------------------------------------------------

local function Median(list)
    local sorted = {}
    for index, value in ipairs(list) do sorted[index] = value end
    table.sort(sorted)
    local count = #sorted
    if count == 0 then return nil end
    if count % 2 == 1 then return sorted[(count + 1) / 2] end
    return (sorted[count / 2] + sorted[count / 2 + 1]) / 2
end

-- A new appearance of npcID (or the same one again after a reload).
local function StartUp(entry, npcID, now)
    entry.ups = type(entry.ups) == "table" and entry.ups or {}
    local last = entry.ups[#entry.ups]
    if type(last) == "table" and not last.k and Number(last.l) and now - last.l <= SAME_UP_SECONDS then
        last.l = now
        return last
    end
    local killedAt = type(last) == "table" and Number(last.k)
    if killedAt then
        local gap = now - killedAt
        if gap >= MIN_GAP and gap <= MAX_GAP then
            entry.gaps = type(entry.gaps) == "table" and entry.gaps or {}
            entry.gaps[#entry.gaps + 1] = gap
            while #entry.gaps > MAX_GAPS do table.remove(entry.gaps, 1) end
            Trace("npc %d respawned %d s after its kill (%d gaps)", npcID, gap, #entry.gaps)
        end
    end
    local up = { f = now, l = now }
    entry.ups[#entry.ups + 1] = up
    while #entry.ups > MAX_UPS do table.remove(entry.ups, 1) end
    return up
end

local function MarkKilled(entry, up, at, npcID, why)
    if up.k then return end
    up.k = at
    entry.k = at
    Trace("npc %d killed (%s)", npcID, why)
end

-- Recent's kill time for the npc, when it falls inside this appearance.
local function RecentKill(npcID, up)
    local kills = Settings().vignetteRadarRecentKills
    local at = type(kills) == "table" and Number(kills["npc:" .. npcID]) or nil
    if at and at >= (up.f or 0) - 5 then return at end
end

-- Live rares that left the scan: a kill when watched, else just out of view.
local function CloseGone(present, player, now)
    for guid, live in pairs(seenUp) do
        if not present[guid] then
            seenUp[guid] = nil
            local entry = Store()[live.npcID]
            if type(entry) == "table" then
                local recent = RecentKill(live.npcID, live.up)
                local dx, dy = live.x - player.worldX, live.y - player.worldY
                local near = (not live.m or not player.mapID or live.m == player.mapID)
                    and dx * dx + dy * dy <= WATCH_YARDS * WATCH_YARDS
                if recent then MarkKilled(entry, live.up, recent, live.npcID, "recent kill")
                elseif near then MarkKilled(entry, live.up, live.up.l or now, live.npcID, "gone in view")
                else Trace("npc %d left view (no kill)", live.npcID) end
            end
        end
    end
end

-- Records each live rare once per session; later scans only move lastAt.
function RareSpawns.Observe(targets, player, now)
    if Settings().vignetteRadarRareSpawnLearning ~= true or type(targets) ~= "table" then return 0 end
    if not (type(player) == "table" and Number(player.worldX) and Number(player.worldY)) then return 0 end
    now = Number(now) or Epoch()
    local recorded = 0
    local present = {}
    for _, target in ipairs(targets) do
        if type(target) == "table" and target.category == "rare" and not target.stale and not target.sample then
            local guid = Text(Field(target, "objectGUID"))
            local npcID = NpcID(guid)
            if npcID and Number(target.worldX) and Number(target.worldY) and Number(target.mapID)
                and Number(target.mapX) and Number(target.mapY) then
                local known = seenGUID[guid]
                if known then
                    known.l = now
                else
                    seenGUID[guid] = Record(npcID, target, player, now)
                    recorded = recorded + 1
                end
                local entry = Store()[npcID]
                local live = seenUp[guid]
                if type(entry) == "table" then
                    if not live then
                        live = { up = StartUp(entry, npcID, now), npcID = npcID }
                        seenUp[guid] = live
                    end
                    live.up.l, live.x, live.y, live.m = now, target.worldX, target.worldY, target.mapID
                    if Field(target, "isDead") == true then MarkKilled(entry, live.up, now, npcID, "dead") end
                    present[guid] = true
                end
            end
        end
    end
    CloseGone(present, player, now)
    if recorded > 0 then
        mapCache = {}
        generation = generation + 1
    end
    return recorded
end

function RareSpawns.Spawns(npcID)
    local entry = Store()[Number(npcID) or 0]
    return type(entry) == "table" and type(entry.spawns) == "table" and entry.spawns or {}
end

function RareSpawns.Generation() return generation end

-- Learned spawns on a map as notes (built once per map until a new sighting).
function RareSpawns.ForMap(mapID)
    mapID = Number(mapID)
    if not mapID then return {} end
    local cached = mapCache[mapID]
    if cached then return cached end
    local notes = {}
    for npcID, entry in pairs(Store()) do
        if type(entry) == "table" and type(entry.spawns) == "table" then
            for index, spawn in ipairs(entry.spawns) do
                if spawn.m == mapID and Number(spawn.x) and Number(spawn.y) then
                    notes[#notes + 1] = {
                        key = "learned:" .. npcID .. ":" .. index, kind = "mob", source = "Learned",
                        npcID = npcID, name = Text(entry.name) or "Learned Rare",
                        note = (spawn.n or 1) .. " sightings", evidence = "saved", learned = true,
                        mapID = mapID, mapX = spawn.mx, mapY = spawn.my,
                        worldX = spawn.x, worldY = spawn.y, worldZ = spawn.z, instanceID = spawn.i,
                        firstAt = spawn.f, lastAt = spawn.l,
                    }
                end
            end
        end
    end
    mapCache[mapID] = notes
    return notes
end

-- Adds this map's learned spawns, skipping any a pack note already covers
-- (same npcID within 60 yd).
function RareSpawns.AppendTo(notes, mapID)
    if type(notes) ~= "table" or Settings().vignetteRadarRareSpawnNotes ~= true then return 0 end
    local packs = {}
    for _, note in ipairs(notes) do
        local npc = Number(note.npcID)
        if npc and not note.learned then packs[#packs + 1] = note end
    end
    local added = 0
    for _, spawn in ipairs(RareSpawns.ForMap(mapID)) do
        local covered = false
        for _, note in ipairs(packs) do
            if note.npcID == spawn.npcID and Number(note.worldX) and Number(note.worldY) then
                local dx, dy = note.worldX - spawn.worldX, note.worldY - spawn.worldY
                if dx * dx + dy * dy <= PACK_DUPLICATE_YARDS * PACK_DUPLICATE_YARDS then covered = true; break end
            end
        end
        if not covered then
            notes[#notes + 1] = spawn
            added = added + 1
        end
    end
    return added
end

-- When the npc is likely up again, from your own watched kills: the median
-- gap from kill to next appearance. nil while up, never killed, or unknown.
function RareSpawns.Respawn(npcID, now)
    npcID = Number(npcID)
    local entry = npcID and Store()[npcID]
    if type(entry) ~= "table" or not Number(entry.k) then return nil end
    for _, live in pairs(seenUp) do
        if live.npcID == npcID then return nil end
    end
    now = Number(now) or Epoch()
    local since = now - entry.k
    if since < 0 then return nil end
    local gaps = type(entry.gaps) == "table" and entry.gaps or {}
    local median = Median(gaps)
    return { killedAt = entry.k, since = since, median = median, samples = #gaps,
        left = median and median - since or nil }
end

local function Minutes(seconds)
    if seconds >= 5400 then return floor(seconds / 3600 + .5) .. " h" end
    return math.max(1, floor(seconds / 60 + .5)) .. " min"
end

function RareSpawns.RespawnText(npcID, now)
    if Settings().vignetteRadarRespawnEstimate ~= true then return nil end
    local estimate = RareSpawns.Respawn(npcID, now)
    if not estimate then return nil end
    if not estimate.median then return "Killed " .. Minutes(estimate.since) .. " Ago" end
    if estimate.left > 60 then return "Likely Up In ~" .. Minutes(estimate.left) end
    if estimate.since <= 2 * estimate.median then return "Likely Up Now" end
    return "Window Passed"
end

-- Fact row for Core/Guidance.lua's facts block.
local function RespawnFact(lines, item)
    local kind = Field(item, "kind") or Field(item, "category")
    if kind ~= "rare" and kind ~= "mob" then return end
    local npcID = Number(Field(item, "npcID")) or NpcID(Field(item, "objectGUID"))
    local text = npcID and RareSpawns.RespawnText(npcID)
    if text then lines[#lines + 1] = { "Respawn", text } end
end
RareSpawns.RespawnFact = RespawnFact
local guidance = addon.VignetteRadarGuidance
if guidance and type(guidance.FactProviders) == "table" then
    guidance.FactProviders[#guidance.FactProviders + 1] = RespawnFact
end

-- Merges already validated spawns (Data/LearnedTransfer.lua) with the same
-- cluster rule as live sightings: within 40 yd on the same map they join
-- (counts and times widen, position kept), else they are added under the
-- same per-npc and per-map caps. Returns added, merged.
function RareSpawns.Import(npcID, name, spawns)
    npcID = Number(npcID)
    if not npcID or type(spawns) ~= "table" then return 0, 0 end
    local store = Store()
    local entry = store[npcID]
    if type(entry) ~= "table" or type(entry.spawns) ~= "table" then
        entry = { spawns = {} }
        store[npcID] = entry
    end
    entry.name = entry.name or Text(name, 80, true)
    local added, merged = 0, 0
    for _, incoming in ipairs(spawns) do
        entry.map = entry.map or incoming.m
        local same
        for _, spawn in ipairs(entry.spawns) do
            local dx, dy = spawn.x - incoming.x, spawn.y - incoming.y
            if spawn.m == incoming.m and (not spawn.i or not incoming.i or spawn.i == incoming.i)
                and dx * dx + dy * dy <= CLUSTER_YARDS * CLUSTER_YARDS then same = spawn; break end
        end
        if same then
            same.n = math.max(same.n or 1, incoming.n or 1)
            same.f = math.min(same.f or incoming.f, incoming.f)
            same.l = math.max(same.l or incoming.l, incoming.l)
            same.z = same.z or incoming.z
            merged = merged + 1
        else
            entry.spawns[#entry.spawns + 1] = { x = incoming.x, y = incoming.y, z = incoming.z, i = incoming.i,
                m = incoming.m, mx = incoming.mx, my = incoming.my, n = incoming.n, f = incoming.f, l = incoming.l }
            added = added + 1
            if #entry.spawns > MAX_SPAWNS then
                table.sort(entry.spawns, function(a, b) return (a.l or 0) > (b.l or 0) end)
                entry.spawns[#entry.spawns] = nil
            end
            CapMap(store, incoming.m)
        end
    end
    if added + merged > 0 then
        mapCache = {}
        generation = generation + 1
    end
    Trace("import npc %d: %d added, %d merged", npcID, added, merged)
    return added, merged
end

function RareSpawns.Clear()
    Settings().vignetteRadarRareSpawns = {}
    seenGUID, seenUp, mapCache = {}, {}, {}
    generation = generation + 1
end

if addon.Bus then
    addon.Bus.On("POINTS_CHANGED", function()
        local points = addon.VignetteRadarPoints
        local view = points and points.View()
        if view then RareSpawns.Observe(points.Refs("live"), view.player) end
    end, { coalesce = true })
end

return RareSpawns
