local _, addon = ...
if type(addon) ~= "table" then return end

-- The expensive radar render calculates positions and quest geometry. When
-- only the player's facing changes, rotate those saved positions instead.
local Turn = {}
addon.VignetteRadarTurn = Turn

local TWO_PI = math.pi * 2
local BLEND_SECONDS, MAX_BLEND_PIXELS = .10, 48

local Number = addon.Secret.Number
local EMPTY = {}
-- Per-update rotation results keyed by each region's baseline facing. The
-- tables are reused and cleared at the start of every update (no garbage).
local rotationSine, rotationCosine, rotationDelta = {}, {}, {}

local function ClearRotations()
    for baseline in pairs(rotationDelta) do
        rotationSine[baseline], rotationCosine[baseline], rotationDelta[baseline] = nil, nil, nil
    end
end

local function Normalize(angle)
    angle = angle % TWO_PI
    if angle > math.pi then angle = angle - TWO_PI end
    return angle
end

local function Rotate(x, y, sine, cosine)
    return x * cosine + y * sine, y * cosine - x * sine
end

local function PreviousPoint(region, x, y, facing)
    if not (region._turnCenter and Number(region._turnDisplayX)
        and Number(region._turnDisplayY) and Number(region._turnDisplayFacing)
        and (not region.IsShown or region:IsShown())) then return nil end
    local delta = Normalize(facing - region._turnDisplayFacing)
    local px, py = Rotate(region._turnDisplayX, region._turnDisplayY,
        math.sin(delta), math.cos(delta))
    local dx, dy = px - x, py - y
    if dx * dx + dy * dy > MAX_BLEND_PIXELS * MAX_BLEND_PIXELS then return nil end
    return px, py, dx, dy
end

function Turn.TrackPoint(region, x, y, facing)
    if not region then return end
    if not (Number(x) and Number(y) and Number(facing)) then
        region._turnFacing = nil
        return
    end
    region._turnX, region._turnY, region._turnFacing = x, y, facing
    local px, py, dx, dy = PreviousPoint(region, x, y, facing)
    if px and dx * dx + dy * dy > .04 then
        region._turnOffsetX, region._turnOffsetY = dx, dy
        region._turnOffsetLeft = BLEND_SECONDS
        region:SetPoint("CENTER", region._turnCenter, "CENTER", px, py)
        region._turnDisplayX, region._turnDisplayY, region._turnDisplayFacing = px, py, facing
        region._turnCenter._turnPending = true
    else
        region._turnOffsetX, region._turnOffsetY, region._turnOffsetLeft = 0, 0, 0
        region._turnDisplayX, region._turnDisplayY, region._turnDisplayFacing = x, y, facing
    end
end

function Turn.TrackLine(line, x1, y1, x2, y2, facing)
    if not line then return end
    if not (Number(x1) and Number(y1) and Number(x2) and Number(y2)
        and Number(facing)) then
        line._turnFacing = nil
        return
    end
    line._turnX1, line._turnY1, line._turnX2, line._turnY2, line._turnFacing =
        x1, y1, x2, y2, facing
    if line._turnCenter and Number(line._turnDisplayX1)
        and Number(line._turnDisplayY1) and Number(line._turnDisplayX2)
        and Number(line._turnDisplayY2) and Number(line._turnDisplayFacing)
        and (not line.IsShown or line:IsShown()) then
        local delta = Normalize(facing - line._turnDisplayFacing)
        local sine, cosine = math.sin(delta), math.cos(delta)
        local px1, py1 = Rotate(line._turnDisplayX1, line._turnDisplayY1, sine, cosine)
        local px2, py2 = Rotate(line._turnDisplayX2, line._turnDisplayY2, sine, cosine)
        local dx1, dy1, dx2, dy2 = px1 - x1, py1 - y1, px2 - x2, py2 - y2
        if math.max(dx1 * dx1 + dy1 * dy1, dx2 * dx2 + dy2 * dy2)
            <= MAX_BLEND_PIXELS * MAX_BLEND_PIXELS
            and math.abs(dx1) + math.abs(dy1) + math.abs(dx2) + math.abs(dy2) > .2 then
            line._turnOffsetX1, line._turnOffsetY1 = dx1, dy1
            line._turnOffsetX2, line._turnOffsetY2 = dx2, dy2
            line._turnOffsetLeft = BLEND_SECONDS
            line:SetStartPoint("CENTER", line._turnCenter, px1, py1)
            line:SetEndPoint("CENTER", line._turnCenter, px2, py2)
            line._turnDisplayX1, line._turnDisplayY1 = px1, py1
            line._turnDisplayX2, line._turnDisplayY2 = px2, py2
            line._turnDisplayFacing = facing
            line._turnCenter._turnPending = true
            return
        end
    end
    line._turnOffsetX1, line._turnOffsetY1 = 0, 0
    line._turnOffsetX2, line._turnOffsetY2, line._turnOffsetLeft = 0, 0, 0
    line._turnDisplayX1, line._turnDisplayY1 = x1, y1
    line._turnDisplayX2, line._turnDisplayY2, line._turnDisplayFacing = x2, y2, facing
end

local function Rotation(facing, baseline)
    local saved = rotationDelta[baseline]
    if saved then return rotationSine[baseline], rotationCosine[baseline], saved end
    local delta = Normalize(facing - baseline)
    local sine, cosine = math.sin(delta), math.cos(delta)
    rotationSine[baseline], rotationCosine[baseline], rotationDelta[baseline] = sine, cosine, delta
    return sine, cosine, delta
end

local function Blend(region, elapsed)
    local remaining = region._turnOffsetLeft or 0
    if remaining <= 0 then return false end
    local nextRemaining = math.max(0, remaining - (elapsed or .033))
    local factor = nextRemaining / remaining
    region._turnOffsetLeft = nextRemaining
    region._turnOffsetX = (region._turnOffsetX or 0) * factor
    region._turnOffsetY = (region._turnOffsetY or 0) * factor
    return nextRemaining > 0
end

local function MovePoint(region, center, facing, elapsed)
    if not (region and Number(region._turnFacing)
        and (not region.IsShown or region:IsShown())) then return false end
    local sine, cosine, delta = Rotation(facing, region._turnFacing)
    local hadOffset = (region._turnOffsetLeft or 0) > 0
    local pending = Blend(region, elapsed)
    region._turnCenter = center
    if math.abs(delta) < .003 and not hadOffset
        and (region._turnOffsetX or 0) == 0 and (region._turnOffsetY or 0) == 0 then
        return false
    end
    local x, y = Rotate(region._turnX + (region._turnOffsetX or 0),
        region._turnY + (region._turnOffsetY or 0), sine, cosine)
    region:SetPoint("CENTER", center, "CENTER", x, y)
    region._turnDisplayX, region._turnDisplayY, region._turnDisplayFacing = x, y, facing
    if region.screenX ~= nil then region.screenX, region.screenY = x, y end
    return pending
end

local function MoveLine(line, center, facing, elapsed)
    if not (line and Number(line._turnFacing)
        and (not line.IsShown or line:IsShown())) then return false end
    local sine, cosine, delta = Rotation(facing, line._turnFacing)
    local pending = false
    local remaining = line._turnOffsetLeft or 0
    line._turnCenter = center
    if remaining > 0 then
        local nextRemaining = math.max(0, remaining - (elapsed or .033))
        local factor = nextRemaining / remaining
        line._turnOffsetLeft = nextRemaining
        line._turnOffsetX1, line._turnOffsetY1 = line._turnOffsetX1 * factor, line._turnOffsetY1 * factor
        line._turnOffsetX2, line._turnOffsetY2 = line._turnOffsetX2 * factor, line._turnOffsetY2 * factor
        pending = nextRemaining > 0
    end
    if math.abs(delta) < .003 and remaining == 0 then return false end
    local x1, y1 = Rotate(line._turnX1 + (line._turnOffsetX1 or 0),
        line._turnY1 + (line._turnOffsetY1 or 0), sine, cosine)
    local x2, y2 = Rotate(line._turnX2 + (line._turnOffsetX2 or 0),
        line._turnY2 + (line._turnOffsetY2 or 0), sine, cosine)
    line:SetStartPoint("CENTER", center, x1, y1)
    line:SetEndPoint("CENTER", center, x2, y2)
    line._turnDisplayX1, line._turnDisplayY1 = x1, y1
    line._turnDisplayX2, line._turnDisplayY2, line._turnDisplayFacing = x2, y2, facing
    return pending
end

local function MovePoints(collection, center, facing, elapsed)
    if type(collection) ~= "table" then return false end
    local pending = false
    for _, region in ipairs(collection) do
        if MovePoint(region, center, facing, elapsed) then pending = true end
    end
    return pending
end

local function MoveLines(collection, center, facing, elapsed)
    if type(collection) ~= "table" then return false end
    local pending = false
    for _, line in pairs(collection) do
        if MoveLine(line, center, facing, elapsed) then pending = true end
    end
    return pending
end

function Turn.UpdateRadar(panel, facing, elapsed)
    if not (panel and panel.field and Number(facing)) then return false end
    local center = panel.field
    if panel._turnFacing and math.abs(Normalize(facing - panel._turnFacing)) < .003
        and not center._turnPending then
        return false
    end
    panel._turnFacing = facing
    ClearRotations()
    local pending = false
    if MovePoints(panel.blips, center, facing, elapsed) then pending = true end
    if MovePoints(panel.questDots, center, facing, elapsed) then pending = true end
    if panel.questDots then
        for _, dot in ipairs(panel.questDots) do
            if MovePoint(dot.halo, center, facing, elapsed) then pending = true end
        end
    end
    if MovePoints(panel.mapNotes, center, facing, elapsed) then pending = true end
    if MovePoints(panel.questStartDots, center, facing, elapsed) then pending = true end
    if MovePoints(panel.edgeCues, center, facing, elapsed) then pending = true end
    if MovePoints(panel.exploreDots, center, facing, elapsed) then pending = true end
    if MovePoints(panel.trailDots, center, facing, elapsed) then pending = true end
    if MovePoints(panel.cardinals, center, facing, elapsed) then pending = true end
    if MovePoint(panel.activeCue, center, facing, elapsed) then pending = true end
    if MoveLines(panel.exploreLines, center, facing, elapsed) then pending = true end
    if MoveLines(panel.trailMarks, center, facing, elapsed) then pending = true end
    if MoveLines(panel.trailExtraMarks, center, facing, elapsed) then pending = true end
    if MovePoints(panel.leadDots, center, facing, elapsed) then pending = true end
    if MoveLines(panel.leadMarks, center, facing, elapsed) then pending = true end
    if MoveLines(panel.leadExtraMarks, center, facing, elapsed) then pending = true end
    if MovePoints(panel.heatDots, center, facing, elapsed) then pending = true end
    center._turnPending = pending
    return true
end

function Turn.UpdateLauncher(launcher, facing, elapsed)
    if not (launcher and launcher.instrument and Number(facing)) then return false end
    local center = launcher.instrument
    if launcher._turnFacing and math.abs(Normalize(facing - launcher._turnFacing)) < .003
        and not center._turnPending then
        return false
    end
    launcher._turnFacing = facing
    ClearRotations()
    center._turnPending = MovePoints(launcher.miniBlips, center, facing, elapsed)
    return true
end

function Turn.Interval(owner, throttled)
    if throttled then return .10 end
    if not owner then return .033 end
    local count = #(owner.blips or owner.miniBlips or EMPTY)
        + #(owner.questDots or EMPTY) + #(owner.mapNotes or EMPTY)
        + #(owner.trailDots or EMPTY) + #(owner.trailMarks or EMPTY)
        + #(owner.trailExtraMarks or EMPTY)
    return count > 160 and .067 or count > 80 and .05 or .033
end
