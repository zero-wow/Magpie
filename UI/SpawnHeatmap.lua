local _, addon = ...
if type(addon) ~= "table" then return end

-- Spawn History Heatmap: a faint heat layer where rares and treasures have
-- been seen before, from VR's own learned data (Data/RareSpawns.lua spawn
-- points, Data/TreasureLearning.lua loot spots). Nothing is shipped.
-- On the radar face it sits under every marker; on the world map it is an
-- optional layer on the map canvas. Off by default.
--   Heat.Cells(mapID) -> { { x, y, mx, my, n, kind } }  (cached per map)
--   Heat.Render(panel, player, range)    (called from the radar's trail pass)
--   Heat.DrawMap() / Heat.Refresh()
-- Cost: cells are built once per map until a new sighting (RareSpawns
-- generation) or 60 s for treasures. The radar layer redraws only when the
-- player moves about two pixels, the range, size or theme changes, or the
-- view turns more than .25 rad; smaller turns are rotated by TurnSmoothing
-- (panel.heatDots). The world map layer draws on map show and map change.
local Heat = {}
addon.VignetteRadarSpawnHeatmap = Heat

local type, ipairs, pairs, abs, min, max, sqrt = type, ipairs, pairs, math.abs, math.min, math.max, math.sqrt
local Number, Field = addon.Secret.Number, addon.Secret.Field

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local KEY, MAP_KEY = "vignetteRadarSpawnHeatmap", "vignetteRadarSpawnHeatmapWorldMap"
local MAX_DOTS, MAX_MAP_DOTS, BLOB_YARDS, TREASURE_SECONDS = 64, 160, 45, 60
local cellCache = {} -- mapID -> { gen, at, cells }
local drawn = { dirty = true }
local used = 0
local mapCanvas, mapDots, hookedMap = nil, {}, nil
local lastTrace

local function Settings() return addon.GetSettings() end

local function Clock()
    local ok, value = pcall(GetTime)
    return ok and Number(value) or 0
end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("heatmap", fmt, ...) end
end

local function SpawnGeneration()
    local spawns = addon.VignetteRadarRareSpawns
    return spawns and spawns.Generation and spawns.Generation() or 0
end

local function Build(mapID)
    local cells = {}
    local settings = Settings()
    for _, entry in pairs(type(settings.vignetteRadarRareSpawns) == "table" and settings.vignetteRadarRareSpawns or {}) do
        for _, spawn in ipairs(type(entry) == "table" and type(entry.spawns) == "table" and entry.spawns or {}) do
            if spawn.m == mapID and Number(spawn.x) and Number(spawn.y) then
                cells[#cells + 1] = { x = spawn.x, y = spawn.y, mx = Number(spawn.mx), my = Number(spawn.my),
                    n = Number(spawn.n) or 1, kind = "rare", i = Number(spawn.i) }
            end
        end
    end
    for _, entry in pairs(type(settings.vignetteRadarTreasureLoots) == "table"
        and settings.vignetteRadarTreasureLoots or {}) do
        local samples = type(entry) == "table" and type(entry.samples) == "table" and entry.samples
        local last = samples and samples[#samples]
        if last and entry.mapID == mapID and Number(last.worldX) and Number(last.worldY) then
            cells[#cells + 1] = { x = last.worldX, y = last.worldY, mx = Number(entry.mapX), my = Number(entry.mapY),
                n = #samples, kind = "treasure" }
        end
    end
    Trace("map %d: %d heat cells", mapID, #cells)
    return cells
end

function Heat.Cells(mapID)
    mapID = Number(mapID)
    if not mapID then return {} end
    local now, gen = Clock(), SpawnGeneration()
    local cached = cellCache[mapID]
    if not cached or cached.gen ~= gen or now - cached.at >= TREASURE_SECONDS then
        cached = { gen = gen, at = now, cells = Build(mapID) }
        cellCache[mapID] = cached
    end
    return cached.cells
end

function Heat.Invalidate()
    cellCache = {}
    drawn.dirty = true
end

local function Color(kind)
    local style = addon.VignetteRadarStyle
    if style and style.Color then
        local r, g, b = style.Color(kind)
        if Number(r) and Number(g) and Number(b) then return r, g, b end
    end
    if kind == "treasure" then return 1, .82, .3 end
    return .95, .45, .35
end

-- Faint: a single sighting barely shows; repeats build up to a soft glow.
local function Alpha(n)
    return min(.30, .07 + .035 * min(n, 7))
end

-- Radar face ----------------------------------------------------------------

local function Layer(panel)
    if not panel.heatLayer then
        local layer = CreateFrame("Frame", nil, panel.field)
        layer:SetAllPoints(panel.field)
        layer:SetFrameLevel(panel.field:GetFrameLevel() + 1)
        layer:EnableMouse(false)
        panel.heatLayer = layer
        panel.heatDots = {}
    end
    return panel.heatLayer
end

local function HideAll(panel)
    for index = 1, used do
        local dot = panel.heatDots and panel.heatDots[index]
        if dot then dot:Hide() end
    end
    used = 0
end

local function Unchanged(panel, player, range, facing, cells)
    if drawn.dirty or drawn.cells ~= cells or drawn.range ~= range or drawn.radius ~= panel.plotRadius
        or drawn.square ~= (panel.squarePlot == true)
        or drawn.revision ~= (addon.VignetteRadarStyle and addon.VignetteRadarStyle.revision) then
        return false
    end
    local tolerance = range / max(1, panel.plotRadius) * 2
    if abs(player.worldX - drawn.px) > tolerance or abs(player.worldY - drawn.py) > tolerance then return false end
    local turn = abs(facing - drawn.facing) % (2 * math.pi)
    return min(turn, 2 * math.pi - turn) <= .25
end

function Heat.Render(panel, player, range)
    if not (panel and panel.field) then return end
    local settings = Settings()
    local facing = player and Number(settings.vignetteRadarNorthUp == true and 0 or player.facing)
    if settings[KEY] ~= true or not (facing and Number(player.worldX) and Number(player.worldY)
        and Number(range) and range > 0 and Number(panel.plotRadius)) then
        if used > 0 then HideAll(panel) end
        drawn.dirty = true
        return
    end
    local cells = Heat.Cells(player.mapID)
    if Unchanged(panel, player, range, facing, cells) then return end
    local layer = Layer(panel)
    local spatial = addon.VignetteRadarSpatial
    local turn = addon.VignetteRadarTurn
    local radius = panel.plotRadius
    local square = panel.squarePlot == true
    local base = BLOB_YARDS / range * radius
    local count = 0
    for _, cell in ipairs(cells) do
        if count >= MAX_DOTS then break end
        if not (player.instanceID and cell.i and player.instanceID ~= cell.i) then
            local x, y, distance = spatial.Project(cell.x - player.worldX, cell.y - player.worldY, facing, range, radius, 1)
            if x and distance <= range * 1.05 then
                local size = max(8, min(radius * .6, base * 2 * (1 + .12 * min(cell.n, 6))))
                local inside = square and (abs(x) <= radius - size * .25 and abs(y) <= radius - size * .25)
                    or (not square and sqrt(x * x + y * y) <= radius - size * .25)
                if inside then
                    count = count + 1
                    local dot = panel.heatDots[count]
                    if not dot then
                        dot = layer:CreateTexture(nil, "BACKGROUND")
                        dot:SetTexture(CIRCLE)
                        panel.heatDots[count] = dot
                    end
                    local r, g, b = Color(cell.kind)
                    dot:SetVertexColor(r, g, b, Alpha(cell.n))
                    dot:SetSize(size, size)
                    dot:ClearAllPoints()
                    dot:SetPoint("CENTER", panel.field, "CENTER", x, y)
                    if turn then turn.TrackPoint(dot, x, y, facing) end
                    dot:Show()
                end
            end
        end
    end
    for index = count + 1, used do panel.heatDots[index]:Hide() end
    used = count
    drawn.dirty, drawn.cells, drawn.range, drawn.radius = false, cells, range, radius
    drawn.square, drawn.px, drawn.py, drawn.facing = square, player.worldX, player.worldY, facing
    drawn.revision = addon.VignetteRadarStyle and addon.VignetteRadarStyle.revision
    if lastTrace ~= count then
        lastTrace = count
        Trace("radar: %d heat spots of %d", count, #cells)
    end
end

-- World map -----------------------------------------------------------------

local function MapParts()
    local map = _G.WorldMapFrame
    local container = Field(map, "ScrollContainer")
    local child = Field(container, "Child")
    if map and child then return map, child end
end

local function HideMap()
    for _, dot in ipairs(mapDots) do dot:Hide() end
end

function Heat.DrawMap()
    local map, child = MapParts()
    if not map then return 0 end
    local settings = Settings()
    if not (settings[KEY] == true and settings[MAP_KEY] == true and map.IsShown and map:IsShown()) then
        HideMap()
        return 0
    end
    if not mapCanvas or mapCanvas:GetParent() ~= child then
        mapCanvas = CreateFrame("Frame", nil, child)
        mapCanvas:SetAllPoints(child)
        mapCanvas:EnableMouse(false)
        mapCanvas:SetScript("OnSizeChanged", function() Heat.DrawMap() end)
        mapDots = {}
    end
    local ok, mapID = pcall(map.GetMapID, map)
    local cells = ok and Heat.Cells(mapID) or {}
    local width, height = child:GetSize()
    width, height = Number(width) or 0, Number(height) or 0
    local count = 0
    if width > 0 and height > 0 then
        for _, cell in ipairs(cells) do
            if count >= MAX_MAP_DOTS then break end
            if cell.mx and cell.my and cell.mx >= 0 and cell.mx <= 1 and cell.my >= 0 and cell.my <= 1 then
                count = count + 1
                local dot = mapDots[count]
                if not dot then
                    dot = mapCanvas:CreateTexture(nil, "BACKGROUND")
                    dot:SetTexture(CIRCLE)
                    mapDots[count] = dot
                end
                local size = width * .02 * (1 + .12 * min(cell.n, 6))
                local r, g, b = Color(cell.kind)
                dot:SetVertexColor(r, g, b, Alpha(cell.n) + .05)
                dot:SetSize(size, size)
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", child, "TOPLEFT", cell.mx * width, -cell.my * height)
                dot:Show()
            end
        end
    end
    for index = count + 1, #mapDots do mapDots[index]:Hide() end
    Trace("world map %s: %d heat spots", tostring(mapID), count)
    return count
end

local function HookMap()
    local map = MapParts()
    if not map or map == hookedMap then return end
    hookedMap = map
    if type(hooksecurefunc) == "function" and type(map.SetMapID) == "function" then
        hooksecurefunc(map, "SetMapID", function() Heat.DrawMap() end)
    end
    if type(map.HookScript) == "function" then
        map:HookScript("OnShow", function() Heat.DrawMap() end)
    end
end

function Heat.Refresh()
    drawn.dirty = true
    local settings = Settings()
    if settings[KEY] == true and settings[MAP_KEY] == true then HookMap() end
    Heat.DrawMap()
end

if addon.Schema and addon.Schema.OnChange then
    addon.Schema.OnChange(function(key)
        if key == KEY or key == MAP_KEY or key == "vignetteRadarNorthUp" then Heat.Refresh() end
    end)
end
if addon.Bus then
    addon.Bus.On("LOGIN", function() Heat.Refresh() end)
end

return Heat
