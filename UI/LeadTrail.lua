local _, addon = ...
if type(addon) ~= "table" then return end

-- Lead trail: the Trails "Lead" mode. Draws marks on the radar from the
-- player out to the current target (World Focus / Auto Route, or the Focus
-- selection), in the same glyph style and spacing as the Follow breadcrumbs
-- and in the target's color. With "Lead Through Next Stops" on, it carries
-- on through the Next 3 Stops as a fainter chain.
--   Lead.Path(player, settings) -> n   (fills Lead.path[1..n], no garbage)
--   Lead.Render(panel, player, range)  (called from the radar's trail pass)
--   Lead.Invalidate()                  (force a redraw on the next pass)
-- Marks sit on fixed world spots (spaced back from the target and on from
-- each stop), so they stay put as you walk, like the Follow trail. Redraws
-- happen only when the player moves about a pixel, turns a lot (smaller
-- turns are rotated by TurnSmoothing), or the path, style or theme changes.
local Lead = {}
addon.VignetteRadarLeadTrail = Lead

local type, sqrt, floor, ceil, abs, max, min =
    type, math.sqrt, math.floor, math.ceil, math.abs, math.max, math.min
local Number, Text = addon.Secret.Number, addon.Secret.Text

local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MAX_STOPS = 3
local CHAIN_ALPHA = { .5, .34, .24 }
local COLOR_SLOTS = { rare = true, boss = true, treasure = true, event = true, other = true, quest = true }

local path = {}
Lead.path = path
for index = 1, MAX_STOPS + 1 do path[index] = {} end

-- Last drawn state, compared field by field so a skipped pass allocates nothing.
local drawn = { n = 0, x = {}, y = {} }
local usedDots, usedMarks, usedExtras = 0, 0, 0
local extraParts = {}
local lastKey

local function Settings() return addon.GetSettings() end

function Lead.Invalidate() drawn.dirty = true end

local function Color(item, world)
    local r, g, b
    if world and world.TargetColor then r, g, b = world.TargetColor(item) end
    if Number(r) and Number(g) and Number(b) then return r, g, b end
    local style = addon.VignetteRadarStyle
    local points = addon.VignetteRadarPoints
    local kind = points and points.Kind(item)
    if kind == "mob" then kind = "rare" end
    if style and style.Color then
        r, g, b = style.Color(COLOR_SLOTS[kind] and kind or "accent")
        if Number(r) and Number(g) and Number(b) then return r, g, b end
    end
    return .55, .88, .82
end

-- Fills one path record from a world spot; false when it has no position.
local function Put(index, spot, item, world, alpha)
    local x, y = Number(spot and spot.worldX), Number(spot and spot.worldY)
    if not (x and y) then return false end
    local record = path[index]
    record.x, record.y, record.instanceID = x, y, Number(spot.instanceID) or Number(item and item.instanceID)
    record.item, record.alpha = item, alpha
    record.r, record.g, record.b = Color(item, world)
    return true
end

local function ActiveTarget()
    local world = addon.VignetteRadarWorldFocus
    if world and world.GetActiveTarget then
        local item, step = world.GetActiveTarget()
        if type(item) == "table" then
            local spot = type(step) == "table" and Number(step.worldX) and Number(step.worldY) and step or item
            return item, spot, world
        end
    end
    local focus = addon.VignetteRadarFocus
    local entry = focus and focus.Get and focus.Get()
    local ref = type(entry) == "table" and type(entry.ref) == "table" and entry.ref or nil
    if ref then return ref, ref, world end
    return nil
end

-- Builds the Lead path for player: the target first, then up to three
-- horizon stops (skipping the target itself) when the chain is on. Returns
-- the point count; 0 means nothing to lead to.
function Lead.Path(player, settings)
    if type(player) ~= "table" then return 0 end
    settings = settings or Settings()
    local item, spot, world = ActiveTarget()
    if not item or not Put(1, spot, item, world, 1) then return 0 end
    local playerInstance = Number(player.instanceID)
    if playerInstance and path[1].instanceID and path[1].instanceID ~= playerInstance then return 0 end
    local n = 1
    if settings.vignetteRadarLeadNextStops ~= false and world and world.IsRouteActive
        and world.IsRouteActive() and world.GetHorizon then
        local horizon = world.GetHorizon()
        if type(horizon) == "table" then
            for index = 1, MAX_STOPS do
                local stop = horizon[index]
                if type(stop) ~= "table" then break end
                local stopItem = type(stop.item) == "table" and stop.item or nil
                if stopItem and stopItem ~= item and not stop.current then
                    if not Put(n + 1, stopItem, stopItem, world, CHAIN_ALPHA[n] or .2) then break end
                    local instanceID = path[n + 1].instanceID
                    if playerInstance and instanceID and instanceID ~= playerInstance then break end
                    n = n + 1
                end
            end
        end
    end
    return n
end

local function HideFrom(list, first, last)
    if not list then return end
    for index = first, last do
        local region = list[index]
        if region then region:Hide() end
    end
end

local function HideAll(panel)
    HideFrom(panel.leadDots, 1, usedDots)
    HideFrom(panel.leadMarks, 1, usedMarks)
    HideFrom(panel.leadExtraMarks, 1, usedExtras)
    usedDots, usedMarks, usedExtras = 0, 0, 0
end

-- One Liang-Barsky edge test; nil when the segment lies outside it.
local function Side(p, q, t0, t1)
    if p == 0 then
        if q < 0 then return nil end
        return t0, t1
    end
    local t = q / p
    if p < 0 then t0 = max(t0, t) else t1 = min(t1, t) end
    return t0, t1
end

-- Parametric range [t0, t1] of the segment inside the radar face: a circle
-- of radius edge, or a square of half-size edge. nil when fully outside.
local function Clip(x1, y1, x2, y2, edge, square)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    if square then
        t0, t1 = Side(-dx, x1 + edge, t0, t1)
        if t0 then t0, t1 = Side(dx, edge - x1, t0, t1) end
        if t0 then t0, t1 = Side(-dy, y1 + edge, t0, t1) end
        if t0 then t0, t1 = Side(dy, edge - y1, t0, t1) end
        if not t0 then return nil end
    else
        local a = dx * dx + dy * dy
        if a < 1e-6 then return nil end
        local b = 2 * (x1 * dx + y1 * dy)
        local c = x1 * x1 + y1 * y1 - edge * edge
        local disc = b * b - 4 * a * c
        if disc < 0 then return nil end
        local root = sqrt(disc)
        t0 = max(0, (-b - root) / (2 * a))
        t1 = min(1, (-b + root) / (2 * a))
    end
    if t0 > t1 then return nil end
    return t0, t1
end
Lead.Clip = Clip

local function Unchanged(settings, player, range, panel, facing, n)
    if drawn.dirty then return false end
    local tolerance = range / max(1, panel.plotRadius) * .75
    if drawn.n ~= n or drawn.range ~= range or drawn.radius ~= panel.plotRadius
        or drawn.square ~= (panel.squarePlot == true)
        or drawn.style ~= settings.vignetteRadarTrailStyle
        or drawn.spacing ~= settings.vignetteRadarTrailSpacing
        or drawn.size ~= settings.vignetteRadarTrailSize
        or drawn.revision ~= (addon.VignetteRadarStyle and addon.VignetteRadarStyle.revision)
        or abs(player.worldX - drawn.px) > tolerance or abs(player.worldY - drawn.py) > tolerance then
        return false
    end
    local turn = abs(facing - drawn.facing) % (2 * math.pi)
    if min(turn, 2 * math.pi - turn) > .25 then return false end
    for index = 1, n do
        if abs(path[index].x - drawn.x[index]) > tolerance
            or abs(path[index].y - drawn.y[index]) > tolerance then return false end
    end
    return true
end

local function Remember(settings, player, range, panel, facing, n)
    drawn.dirty = false
    drawn.n, drawn.range, drawn.radius = n, range, panel.plotRadius
    drawn.square = panel.squarePlot == true
    drawn.style, drawn.spacing = settings.vignetteRadarTrailStyle, settings.vignetteRadarTrailSpacing
    drawn.size = settings.vignetteRadarTrailSize
    drawn.revision = addon.VignetteRadarStyle and addon.VignetteRadarStyle.revision
    drawn.px, drawn.py, drawn.facing = player.worldX, player.worldY, facing
    for index = 1, n do drawn.x[index], drawn.y[index] = path[index].x, path[index].y end
end

local function Layer(panel)
    if not panel.leadLayer then
        local layer = CreateFrame("Frame", nil, panel.field)
        layer:SetAllPoints(panel.field)
        layer:SetFrameLevel(panel.field:GetFrameLevel() + 3)
        layer:EnableMouse(false)
        panel.leadLayer = layer
        panel.leadDots, panel.leadMarks, panel.leadExtraMarks = {}, {}, {}
    end
    return panel.leadLayer
end

-- One mark through the shared glyph drawer, from this module's own pools.
local function Mark(panel, definition, glyph, count, x, y, ux, uy, r, g, b, alpha, sizeScale, facing)
    local layer = panel.leadLayer
    if definition.dot or definition.square then
        local dot = panel.leadDots[count]
        if not dot then
            dot = layer:CreateTexture(nil, "BACKGROUND")
            panel.leadDots[count] = dot
        end
        local texture = definition.square and SQUARE_TEXTURE or CIRCLE_TEXTURE
        if dot._trailTexture ~= texture then
            dot:SetTexture(texture)
            dot._trailTexture = texture
        end
        glyph(definition, dot, nil, panel.field, x, y, ux, uy, r, g, b, alpha, count, sizeScale, facing)
        return
    end
    local mark = panel.leadMarks[count]
    if not mark then
        mark = layer:CreateLine(nil, "BACKGROUND")
        panel.leadMarks[count] = mark
    end
    for part = 2, #definition.segments do
        local slot = (count - 1) * 3 + part - 1
        local extra = panel.leadExtraMarks[slot]
        if not extra then
            extra = layer:CreateLine(nil, "BACKGROUND")
            panel.leadExtraMarks[slot] = extra
        end
        extraParts[part - 1] = extra
        if slot > usedExtras then usedExtras = slot end
    end
    glyph(definition, mark, extraParts, panel.field, x, y, ux, uy, r, g, b, alpha, count, sizeScale, facing)
end

local function Trace(n, key)
    if lastKey == key then return end
    lastKey = key
    if addon.Trace then
        addon.Trace.Log("trail", key and "lead to %s (%d points)" or "lead off", tostring(key), n)
    end
end

function Lead.Render(panel, player, range)
    if not (panel and panel.field) then return end
    local settings = Settings()
    local modes = addon.VignetteRadarTrailMode
    local glyph = addon.VignetteRadarTrailGlyph
    local spatial = addon.VignetteRadarSpatial
    local n = 0
    if player and glyph and spatial and modes and modes.Leads(settings.vignetteRadarTrailMode)
        and Number(player.worldX) and Number(player.worldY) and Number(range) and range > 0
        and Number(panel.plotRadius) then
        n = Lead.Path(player, settings)
    end
    local facing = n > 0 and Number(settings.vignetteRadarNorthUp == true and 0 or player.facing) or nil
    if n == 0 or not facing then
        if usedDots + usedMarks + usedExtras > 0 then HideAll(panel) end
        drawn.n, drawn.dirty = 0, true
        Trace(0, nil)
        return
    end
    if Unchanged(settings, player, range, panel, facing, n) then return end
    Trace(n, Text(path[1].item and path[1].item.key) or Text(path[1].item and path[1].item.name) or "target")
    Layer(panel)

    local styles = addon.VignetteRadarTrailStyles
    local definition = (addon.VignetteRadarTrailStyleByID or {})[settings.vignetteRadarTrailStyle]
        or (styles and styles[1])
    if not definition then return end
    local spacing = definition.spacing * (settings.vignetteRadarTrailSpacing or 1)
    local sizeScale = settings.vignetteRadarTrailSize or 1
    local limit = definition.segments and #definition.segments > 2 and 48 or 64
    local radius = panel.plotRadius
    local edge = radius - 7
    local square = panel.squarePlot == true
    local dots = definition.dot or definition.square
    local count, oldDots, oldMarks, oldExtras = 0, usedDots, usedMarks, usedExtras
    usedExtras = 0

    local x1, y1 = 0, 0
    for index = 1, n do
        if count >= limit then break end
        local point = path[index]
        local x2, y2 = spatial.Project(point.x - player.worldX, point.y - player.worldY,
            facing, range, radius, 1)
        if not x2 then break end
        local dx, dy = x2 - x1, y2 - y1
        local length = sqrt(dx * dx + dy * dy)
        local t0, t1 = nil, nil
        if length > spacing * .5 then t0, t1 = Clip(x1, y1, x2, y2, edge, square) end
        if t0 then
            local ux, uy = dx / length, dy / length
            local alpha = .95 * (point.alpha or 1)
            local r, g, b = point.r, point.g, point.b
            -- Segment 1 is spaced back from the target; later ones on from
            -- the stop they leave. Both ends stay clear of the markers.
            local fromEnd = index == 1
            local first = fromEnd and max(1, ceil((1 - t1) * length / spacing))
                or max(1, ceil(t0 * length / spacing))
            local last = fromEnd and floor((1 - t0) * length / spacing) or floor(t1 * length / spacing)
            for step = first, last do
                if count >= limit then break end
                local t = fromEnd and (1 - step * spacing / length) or (step * spacing / length)
                local x, y = x1 + dx * t, y1 + dy * t
                if (fromEnd or (1 - t) * length >= 5) and x * x + y * y >= 49 then
                    count = count + 1
                    Mark(panel, definition, glyph, count, x, y, ux, uy, r, g, b, alpha, sizeScale, facing)
                end
            end
        end
        x1, y1 = x2, y2
    end

    if dots then
        usedDots, usedMarks = count, 0
    else
        usedDots, usedMarks = 0, count
    end
    HideFrom(panel.leadDots, usedDots + 1, oldDots)
    HideFrom(panel.leadMarks, usedMarks + 1, oldMarks)
    HideFrom(panel.leadExtraMarks, usedExtras + 1, oldExtras)
    Remember(settings, player, range, panel, facing, n)
end

if addon.Bus and addon.Bus.On then addon.Bus.On("FOCUS_CHANGED", Lead.Invalidate) end
