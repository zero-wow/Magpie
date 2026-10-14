local _, addon = ...
if type(addon) ~= "table" then return end

-- Guide Panel: the one panel for "where next". It draws the Guidance
-- snapshot (Core/Guidance.lua) as blocks, top to bottom in the player's
-- order: header (direction chevron, kind dot, name, then kind, path step,
-- yards and ETA), step (quest objective, Blizzard's route hint or the map
-- note), facts (the Worth-It facts), stops (the next stops; click one to go
-- there now), briefing (the zone line; click it for Closest), actions (lock,
-- skip, why, share), notice (route notes) and the optional compass strip
-- (off by default; it reads the shared Compass feed, Core/Compass.lua, and is
-- not the header's direction chevron). A theme change repaints at once
-- (GuidePanel.RefreshTheme rides Controls.RefreshTheme). Blocks switch on and off in
-- Routes > Guide Panel; Compact shows only the header, a strip of stops and
-- the actions. One Tray.RegisterPanel: docked under the radar or free, with
-- detach, lock and keep-on-screen from UI/Tray.lua. Every line wraps; no
-- text is ever cut short.
--   GuidePanel.Refresh() / GuidePanel.GetFrame() / GuidePanel.ResetPosition()
--   GuidePanel.Order(settings) -> block ids, header first
--   GuidePanel.MoveBlock(id) / GuidePanel.OrderText(settings)
--   GuidePanel.Fit(cells, available, maxAvailable)   (the compact stops strip)
--   GuidePanel.ShowsNotices()
local GuidePanel = {}
addon.VignetteRadarGuidePanel = GuidePanel

local type, ipairs, pairs, floor, max, min = type, ipairs, pairs, math.floor, math.max, math.min
local Number = addon.Secret.Number

local PAD, BLOCK_GAP, GAP, ROW_GAP = 8, 5, 4, 3
local CHEVRON, DOT, ICON, ACTION = 16, 7, 14, 20
local HEAD_X = PAD + CHEVRON + 4 + DOT + 6
local WIDTHS = { [200] = true, [260] = true, [320] = true }
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local POINTER = "Interface\\AddOns\\Magpie\\Media\\route-nav-chevron.tga"
local DIAMOND = "Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga"
local DEFAULT_ORDER = { "step", "facts", "stops", "compass", "briefing", "actions", "notice" }
local NAMES = { header = "Header", step = "Step", facts = "Facts", stops = "Stops", compass = "Compass",
    briefing = "Briefing", actions = "Actions", notice = "Notices" }
-- Blocks that stay off until the player turns them on.
local OFF_BY_DEFAULT = { compass = true }
-- Compact keeps the header, one strip of stops and the action icons; the
-- timed lines (briefing, notice) still show while they apply.
local COMPACT = { header = true, stops = true, actions = true, briefing = true, notice = true }
local TEXT, SOFT = { .88, .92, .93 }, { .66, .75, .77 }
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local frame
local BLOCKS = {}

local function Settings() return addon.GetSettings() end
local function Guidance() return addon.VignetteRadarGuidance end

local function BlockOn(settings, id)
    if id == "header" then return true end
    local blocks = settings.vignetteRadarGuideBlocks
    if OFF_BY_DEFAULT[id] then return type(blocks) == "table" and blocks[id] == true end
    return not (type(blocks) == "table" and blocks[id] == false)
end

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("guide", fmt, ...) end
end

local function Accent()
    local style = addon.VignetteRadarStyle
    if style and style.Color then return style.Color("accent") end
    return .55, .88, .82
end

-- Text helpers ---------------------------------------------------------------

local function SetText(fontString, text)
    text = text or ""
    if fontString._text ~= text then
        fontString._text = text
        fontString:SetText(text)
    end
end

-- Every panel string and its base color, so a theme change can repaint
-- them (the contrast floor depends on the theme's surface).
local texts = {}

local function NewText(parent, role, color)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(fontString, role, "")
    fontString:SetJustifyH("LEFT")
    fontString:SetJustifyV("TOP")
    -- Width only, never a height or a line cap: the client wraps the text
    -- and the block grows, so nothing gets "...".
    fontString:SetWordWrap(true)
    color = color or TEXT
    fontString:SetTextColor(color[1], color[2], color[3], 1)
    texts[#texts + 1] = { fontString, color }
    return fontString
end

local function Width(fontString)
    local style = addon.VignetteRadarStyle
    if style and style.TextWidth then return style.TextWidth(fontString) end
    return 0
end

local function SetWidth(fontString, width)
    width = max(1, floor(width))
    if fontString._width ~= width then
        fontString._width = width
        fontString:SetWidth(width)
    end
end

-- The wrapped height the client reports, else an estimate from the
-- measured width (tests, or before the font has loaded).
local function TextHeight(fontString, width)
    return addon.VignetteRadarStyle.TextHeight(fontString, width)
end

local function Place(region, parent, x, y)
    if region._x == x and region._y == y and region._parent == parent then return end
    region._x, region._y, region._parent = x, y, parent
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- A wrapped text at x, y inside block; returns its height.
local function Flow(fontString, block, x, y, width, text)
    SetText(fontString, text)
    SetWidth(fontString, width)
    Place(fontString, block, x, y)
    fontString:Show()
    return TextHeight(fontString, width)
end

local function Tooltip(owner, title, lines, anchor)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    for _, line in ipairs(lines) do
        if line then GameTooltip:AddLine(line[1], line[2] or .72, line[3] or .82, line[4] or .84, true) end
    end
    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function World() return addon.VignetteRadarWorldFocus end

local function Changed()
    local guidance = Guidance()
    if guidance then guidance.Invalidate() end
    GuidePanel.Refresh()
end

-- Settings writes go through the schema (it validates and tells open
-- windows); without it, through InvalidateSettings.
local function Write(key, value)
    local schema = addon.Schema
    if schema and schema.Entry and schema.Entry(key) then return schema.Set(key, value) end
    Settings()[key] = value
    if addon.InvalidateSettings then addon.InvalidateSettings() end
    Changed()
    return true
end

-- Header -------------------------------------------------------------------

local function Bearing(block)
    local target = block.target
    local facing
    if target and target.dx and type(GetPlayerFacing) == "function" then
        local ok, value = pcall(GetPlayerFacing)
        facing = ok and Number(value) or nil
    end
    if not facing then
        if block.pointer:IsShown() then block.pointer:Hide() end
        return
    end
    local angle = atan2(target.dy, target.dx) - facing
    if block.bearing ~= angle then
        block.bearing = angle
        block.pointer:SetRotation(angle)
    end
    if not block.pointer:IsShown() then block.pointer:Show() end
end

BLOCKS.header = {}
function BLOCKS.header.create(parent)
    local block = CreateFrame("Button", nil, parent)
    block:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    block.pointer = block:CreateTexture(nil, "OVERLAY")
    block.pointer:SetTexture(POINTER)
    block.pointer:SetSize(CHEVRON, CHEVRON)
    block.dot = block:CreateTexture(nil, "ARTWORK")
    block.dot:SetTexture(CIRCLE)
    block.dot:SetSize(DOT, DOT)
    block.name = NewText(block, "title")
    block.meta = NewText(block, "caption", SOFT)
    -- The chevron turns with the camera at 30 Hz: rotation only, no text.
    block:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + (elapsed or 0)
        if self.elapsed < .033 then return end
        self.elapsed = 0
        Bearing(self)
    end)
    block:SetScript("OnClick", function(_, button)
        local tray = addon.VignetteRadarTray
        if tray and tray.JustDragged and tray.JustDragged(frame) then return end
        if button == "RightButton" then
            local quick = addon.VignetteRadarQuickConfig
            if quick and quick.OpenPage then quick.OpenPage("Guide Panel", frame) end
        elseif button == "MiddleButton" then
            local world = World()
            if world and world.SkipRouteStop then world.SkipRouteStop() end
        else
            Write("vignetteRadarGuideDensity",
                Settings().vignetteRadarGuideDensity == "compact" and "expanded" or "compact")
        end
    end)
    block:SetScript("OnEnter", function(self)
        local world = World()
        Tooltip(self, "Guide Panel", {
            world and world.Status and { world.Status() } or false,
            world and world.ExplainActive and { world.ExplainActive(), .67, .83, .79 } or false,
            { "Click: Compact or Full. Middle-click: skip this stop. Right-click: settings. Drag to move.",
                .6, .7, .72 } })
    end)
    block:SetScript("OnLeave", HideTooltip)
    return block
end

function BLOCKS.header.render(block, snap, width)
    local line = Guidance().Lines("header", snap)[1]
    local target = snap.target
    if not (line and target) then return nil end
    local textWidth = width - HEAD_X - PAD
    block.name:SetTextColor(Accent())
    local nameHeight = Flow(block.name, block, HEAD_X, 0, textWidth, line[1])
    local metaHeight = Flow(block.meta, block, HEAD_X, nameHeight + 2, textWidth, line[2])
    Place(block.pointer, block, PAD, 0)
    Place(block.dot, block, PAD + CHEVRON + 4, 5)
    local color = target.color
    block.dot:SetVertexColor(color[1], color[2], color[3], 1)
    block.target = target
    Bearing(block)
    return max(CHEVRON + 2, nameHeight + 2 + metaHeight)
end

-- Step ---------------------------------------------------------------------

BLOCKS.step = {}
function BLOCKS.step.create(parent)
    local block = CreateFrame("Frame", nil, parent)
    block.label = NewText(block, "caption")
    block.text = NewText(block, "body")
    return block
end

function BLOCKS.step.render(block, snap, width)
    local line = Guidance().Lines("step", snap)[1]
    if not line then return nil end
    local y = 0
    if line[1] then
        block.label:SetTextColor(Accent())
        y = Flow(block.label, block, PAD, 0, width - 2 * PAD, line[1]) + 1
    else
        block.label:Hide()
    end
    return y + Flow(block.text, block, PAD, y, width - 2 * PAD, line[2])
end

-- Label / value rows (facts, briefing) -------------------------------------

local function Rows(block, lines, width)
    block.labels, block.values = block.labels or {}, block.values or {}
    local labelWidth = 0
    for index, line in ipairs(lines) do
        local label = block.labels[index]
        if not label then
            label = NewText(block, "caption", SOFT)
            block.labels[index] = label
            block.values[index] = NewText(block, "body")
        end
        SetText(label, line[1])
        label:SetWordWrap(false)
        labelWidth = max(labelWidth, Width(label))
    end
    -- The label column fits the widest label; values wrap in the rest.
    labelWidth = min(math.ceil(labelWidth) + 3, floor((width - 2 * PAD) / 2))
    local valueX, y = PAD + labelWidth + 8, 0
    for index, line in ipairs(lines) do
        local label, value = block.labels[index], block.values[index]
        local labelHeight = Flow(label, block, PAD, y, labelWidth, line[1])
        label:SetWordWrap(true)
        local valueHeight = Flow(value, block, valueX, y, width - valueX - PAD, line[2])
        y = y + max(labelHeight, valueHeight) + ROW_GAP
    end
    for index = #lines + 1, #block.labels do
        block.labels[index]:Hide()
        block.values[index]:Hide()
    end
    return y > 0 and y - ROW_GAP or nil
end

BLOCKS.facts = {}
function BLOCKS.facts.create(parent)
    return CreateFrame("Frame", nil, parent)
end

function BLOCKS.facts.render(block, snap, width)
    local lines = Guidance().Lines("facts", snap)
    if #lines == 0 then return nil end
    return Rows(block, lines, width)
end

-- Stops --------------------------------------------------------------------

local function ApplyIcon(row, item, kind)
    if row._item == item then return end
    row._item = item
    local points = addon.VignetteRadarPoints
    local icon = points and points.ApplyIcon(row.icon, nil, item or kind, DIAMOND)
    if icon and icon.diamond then
        local style = addon.VignetteRadarStyle
        local r, g, b = style.Color(kind or "accent")
        row.icon:SetVertexColor(r, g, b)
        row.badge:SetText(icon.label or "")
    else
        local tint = icon and icon.color
        row.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
        row.badge:SetText("")
    end
end

local function Jump(row)
    local tray = addon.VignetteRadarTray
    if tray and tray.JustDragged and tray.JustDragged(frame) then return end
    local world = World()
    if not (row.entry and row.entry.item and world and world.JumpRouteStop) then return end
    local ok, reason = world.JumpRouteStop(row.entry.item)
    if addon.Trace then addon.Trace.Log("guide", "jump to %s ok=%s %s", row.entry.name, ok, reason or "") end
    Changed()
end

local function StopTooltip(row)
    local entry = row.entry
    if not entry then return end
    local guidance = Guidance()
    local eta = guidance.Eta(entry.yards)
    Tooltip(row, entry.name, { { guidance.Yards(entry.yards) .. (eta and (" · ETA " .. eta) or "") },
        { "Click to go here now; the route carries on from it.", .6, .7, .72 } }, "ANCHOR_BOTTOM")
end

local function NewStopButton(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.badge = row:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(row.badge, 7, "OUTLINE")
    row.badge:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.label = NewText(row, "caption", SOFT)
    row.name = NewText(row, "body")
    row.yards = NewText(row, "caption", SOFT)
    row:SetScript("OnClick", Jump)
    row:SetScript("OnEnter", StopTooltip)
    row:SetScript("OnLeave", HideTooltip)
    return row
end

BLOCKS.stops = {}
function BLOCKS.stops.create(parent)
    local block = CreateFrame("Frame", nil, parent)
    block.rows = {}
    for index = 1, Guidance().MAX_STOPS do block.rows[index] = NewStopButton(block) end
    -- Measures names in the strip's font without touching a shown cell.
    block.ruler = NewText(block, "body")
    block.ruler:SetWordWrap(false)
    block.ruler:Hide()
    return block
end

-- Full: one row per stop, "Next" / "Then", the name and its yards, wrapping.
local function StopRows(block, lines, width, snap)
    local labelWidth = 0
    for index, line in ipairs(lines) do
        local row = block.rows[index]
        SetText(row.label, line[1])
        row.label:SetWordWrap(false)
        labelWidth = max(labelWidth, Width(row.label))
    end
    labelWidth = math.ceil(labelWidth) + 3
    local nameX = ICON + 4 + labelWidth + 6
    local nameWidth = width - 2 * PAD - nameX
    local y = 0
    for index, line in ipairs(lines) do
        local row = block.rows[index]
        row.entry = row.entry or {}
        local stop = snap.stops[index] or {}
        row.entry.item, row.entry.name, row.entry.yards = line[3], line[2], stop.yards
        ApplyIcon(row, line[3], stop.kind)
        row.yards:Hide()
        Place(row.icon, row, 0, 0)
        local labelHeight = Flow(row.label, row, ICON + 4, 1, labelWidth, line[1])
        row.label:SetWordWrap(true)
        -- The yards ride on the name's last line; their space is unbreakable.
        local nameHeight = Flow(row.name, row, nameX, 0, nameWidth,
            line[2] .. " · " .. (line[4]:gsub(" ", "\194\160")))
        local height = max(ICON, labelHeight + 1, nameHeight)
        row:SetSize(width - 2 * PAD, height)
        Place(row, block, PAD, y)
        row:Show()
        y = y + height + ROW_GAP
    end
    return y - ROW_GAP
end

-- Pure: shares the strip's width among the cells so no text is ever cut
-- and no line runs into the next cell. cells[i] = { one = the name's width
-- on one line, two = the wider line of its best two-line split, yards = the
-- second line's width }. Tries every cell with one-line names, then names
-- wrapped to two lines, then a wider strip (up to maxAvailable), then fewer
-- cells; one cell always shows. Returns the cell widths, whether names may
-- wrap, and the inner width the cells take. (Was UI/StopStrip.lua.)
local TEXT_X, SLACK, CELL_GAP = ICON + 5, 3, 4
local FITS = { { "one", false }, { "two", false }, { "two", true } }
function GuidePanel.Fit(cells, available, maxAvailable)
    maxAvailable = max(available, maxAvailable or available)
    local function Need(cell, field)
        return TEXT_X + max(cell[field] or 0, cell.yards or 0) + SLACK
    end
    for count = #cells, 1, -1 do
        for _, fit in ipairs(FITS) do
            local field, room = fit[1], fit[2] and maxAvailable or available
            local total = (count - 1) * CELL_GAP
            for index = 1, count do total = total + Need(cells[index], field) end
            if total <= room or (count == 1 and fit[2]) then
                local spare = floor(max(0, available - total) / count)
                local widths = {}
                for index = 1, count do widths[index] = Need(cells[index], field) + spare end
                return widths, field == "two", max(available, total + spare * count)
            end
        end
    end
    return {}, false, available
end

-- A name's width on one line and on its best two lines.
local function NameWidths(block, name)
    return addon.VignetteRadarStyle.LineWidths(block.ruler, name)
end

-- Compact: the stops side by side, sized by GuidePanel.Fit. A single stop
-- too long even on two lines wraps to as many lines as it needs.
local function StopStrip(block, lines, width, snap)
    local cells = {}
    for index, line in ipairs(lines) do
        local row = block.rows[index]
        SetText(row.yards, line[4])
        row.yards:SetWordWrap(false)
        local one, two = NameWidths(block, line[2])
        cells[index] = { one = one, two = two, yards = Width(row.yards) }
    end
    local available = width - 2 * PAD
    local widths = GuidePanel.Fit(cells, available, available)
    local x, height = PAD, 0
    for index, cellWidth in ipairs(widths) do
        local row, line = block.rows[index], lines[index]
        local stop = snap.stops[index] or {}
        row.entry = row.entry or {}
        row.entry.item, row.entry.name, row.entry.yards = line[3], line[2], stop.yards
        ApplyIcon(row, line[3], stop.kind)
        row.label:Hide()
        cellWidth = min(cellWidth, available - (x - PAD))
        local textWidth = cellWidth - TEXT_X
        Place(row.icon, row, 2, 1)
        -- Fit gave the name its measured width (+ SLACK), so it wraps only
        -- where it needs to.
        local nameHeight = Flow(row.name, row, TEXT_X, 0, textWidth, line[2])
        local yardsHeight = Flow(row.yards, row, TEXT_X, nameHeight + 1, textWidth, line[4])
        row.yards:SetWordWrap(true)
        local cellHeight = nameHeight + 1 + yardsHeight
        row:SetSize(cellWidth, cellHeight)
        Place(row, block, x, 0)
        row:Show()
        height = max(height, cellHeight)
        x = x + cellWidth + CELL_GAP
    end
    for index = #widths + 1, #lines do block.rows[index]:Hide() end
    return height
end

function BLOCKS.stops.render(block, snap, width, _, compact)
    local lines = Guidance().Lines("stops", snap)
    for index = #lines + 1, #block.rows do block.rows[index]:Hide() end
    if #lines == 0 then return nil end
    if compact then return StopStrip(block, lines, width, snap) end
    return StopRows(block, lines, width, snap)
end

-- Compass ------------------------------------------------------------------

-- Optional (off by default): a thin strip of the Compass system, read from
-- the same feed as the Bearing Bar and the Horizon Ribbon (Core/Compass.lua):
-- the next stops (numbered), the focus and live rares, where they lie as you
-- face. It is not the header's chevron (that is the direction arrow).
-- The tick list follows the feed (checked every .25 s); the ticks move with
-- the camera every frame, and only by .5 px or more.
local STRIP_H, TICK, COMPASS_RARES, FEED_CHECK = 20, 11, 8, .25
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function CompassTick(block, index)
    local tick = block.ticks[index]
    if tick then return tick end
    tick = CreateFrame("Frame", nil, block)
    tick:SetSize(TICK + 4, STRIP_H)
    tick.icon = tick:CreateTexture(nil, "OVERLAY")
    tick.icon:SetSize(TICK, TICK)
    tick.icon:SetPoint("CENTER", tick, "CENTER", 0, 0)
    tick.label = tick:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(tick.label, 9, "OUTLINE")
    tick.label:SetPoint("CENTER", tick.icon, "CENTER", 0, 0)
    block.ticks[index] = tick
    return tick
end

-- Per frame: reads only the facing; a tick moves when it shifts .5 px.
local function PlaceTicks(block)
    local compass = addon.VignetteRadarCompass
    local facing = compass and compass.Facing()
    local points = addon.VignetteRadarPoints
    local view = points and points.View()
    local player = view and view.player
    for index, entry in ipairs(block.list or {}) do
        local tick = block.ticks[index]
        local angle = facing and compass.Bearing(player, entry.item, facing)
        if angle then
            local x, clamped = compass.X(angle, block.half or 100)
            if not tick._x or math.abs(x - tick._x) >= .5 then
                tick._x = x
                tick:ClearAllPoints()
                tick:SetPoint("CENTER", block, "TOP", x, -STRIP_H / 2)
            end
            local alpha = clamped and .45 or 1
            if tick._alpha ~= alpha then tick._alpha = alpha; tick:SetAlpha(alpha) end
            if not tick:IsShown() then tick:Show() end
        elseif tick:IsShown() then
            tick:Hide()
        end
    end
end

-- Reads the feed into ticks; returns how many.
local function BuildTicks(block)
    local compass = addon.VignetteRadarCompass
    local feed = compass.Feed()
    block.feed = feed
    block.list = compass.Ticks(feed, COMPASS_RARES)
    local revision = addon.VignetteRadarStyle.revision
    for index, entry in ipairs(block.list) do
        local tick = CompassTick(block, index)
        if tick._item ~= entry.item or tick._revision ~= revision or tick._focus ~= entry.focus then
            tick._item, tick._revision, tick._focus = entry.item, revision, entry.focus
            local points = addon.VignetteRadarPoints
            local icon = points and points.ApplyIcon(tick.icon, nil, entry.item, DIAMOND)
            local r, g, b = compass.Color(entry.kind, entry.item)
            if icon and icon.diamond then tick.icon:SetVertexColor(r, g, b, 1)
            else tick.icon:SetVertexColor(1, 1, 1, 1) end
            tick.label:SetText(entry.label or "")
            local size = entry.focus and TICK + 3 or TICK
            tick.icon:SetSize(size, size)
            tick:SetFrameLevel(block:GetFrameLevel() + (entry.focus and 3 or 1))
        end
        tick._x = nil
    end
    for index = #block.list + 1, #block.ticks do block.ticks[index]:Hide() end
    return #block.list
end

BLOCKS.compass = {}
function BLOCKS.compass.create(parent)
    local block = CreateFrame("Frame", nil, parent)
    block.ticks = {}
    block.axis = block:CreateTexture(nil, "ARTWORK")
    block.axis:SetTexture(WHITE)
    block.axis:SetHeight(1)
    block.center = block:CreateTexture(nil, "ARTWORK")
    block.center:SetTexture(WHITE)
    block.center:SetSize(1, STRIP_H - 4)
    block:SetScript("OnUpdate", function(self, elapsed)
        self.checked = (self.checked or 0) + (elapsed or 0)
        if self.checked >= FEED_CHECK then
            self.checked = 0
            local compass = addon.VignetteRadarCompass
            if compass and compass.Feed() ~= self.feed and BuildTicks(self) == 0 then
                -- Nothing left to show: the panel closes the strip's gap.
                frame._layoutKey = nil
                GuidePanel.Refresh()
                return
            end
        end
        PlaceTicks(self)
    end)
    return block
end

function BLOCKS.compass.render(block, _, width)
    if not addon.VignetteRadarCompass or BuildTicks(block) == 0 then return nil end
    block.half = width / 2 - PAD - 6
    local r, g, b = Accent()
    block.axis:SetVertexColor(r, g, b, .25)
    block.axis:SetWidth(width - 2 * PAD)
    Place(block.axis, block, PAD, floor(STRIP_H / 2))
    block.center:SetVertexColor(r, g, b, .7)
    Place(block.center, block, floor(width / 2), 2)
    PlaceTicks(block)
    return STRIP_H
end

-- "1" when the compass block is on and has ticks, so the layout follows it.
local function CompassKey(settings)
    local compass = addon.VignetteRadarCompass
    if not (compass and BlockOn(settings, "compass")) then return "" end
    return #compass.Ticks(compass.Feed(), COMPASS_RARES) > 0 and "1" or "0"
end

-- Briefing -----------------------------------------------------------------

BLOCKS.briefing = {}
function BLOCKS.briefing.create(parent)
    local block = CreateFrame("Button", nil, parent)
    block:RegisterForClicks("LeftButtonUp")
    block:SetScript("OnClick", function()
        local tray = addon.VignetteRadarTray
        if tray and tray.JustDragged and tray.JustDragged(frame) then return end
        local world = World()
        if not (world and world.StartNearest) then return end
        local ok, reason = world.StartNearest("closest")
        if addon.Trace then addon.Trace.Log("guide", "briefing: start Closest ok=%s %s", ok,
            type(reason) == "string" and reason or "") end
        if not ok and type(reason) == "string" and addon.ShowVignetteRadarRouteNote then
            addon.ShowVignetteRadarRouteNote("AUTO ROUTE", reason)
        end
    end)
    block:SetScript("OnEnter", function(self)
        local guidance = Guidance()
        if guidance then guidance.HoldBriefing() end
        local line = guidance and guidance.Lines("briefing")[1]
        Tooltip(self, line and line[1] or "Here", { line and { line[2] } or false,
            { "Click to start a Closest Auto Route.", .6, .7, .72 } }, "ANCHOR_BOTTOM")
    end)
    block:SetScript("OnLeave", HideTooltip)
    return block
end

function BLOCKS.briefing.render(block, snap, width)
    local line = Guidance().Lines("briefing", snap)[1]
    if not line then return nil end
    -- Each part ("5 treasures left") stays whole: its spaces are
    -- non-breaking, so lines break only between parts.
    local parts = {}
    for part in (line[2] .. " · "):gmatch("(.-) · ") do parts[#parts + 1] = (part:gsub(" ", "\194\160")) end
    return Rows(block, { { line[1], table.concat(parts, " · ") } }, width)
end

-- Actions ------------------------------------------------------------------

local function Locked()
    local world = World()
    return world and world.IsRouteLocked and world.IsRouteLocked() == true or false
end

local function ShareClicked()
    local share = addon.VignetteRadarShareToGroup
    local snap = Guidance().Snapshot()
    local item = snap.target and snap.target.item
    if not (share and item) then return end
    local posted, sent, reason = share.Share(item)
    if addon.ShowVignetteRadarRouteNote then
        addon.ShowVignetteRadarRouteNote("SHARE", posted and ("Shared · " .. snap.target.name
            .. (sent and " · VR users told" or "")) or reason or "Not shared")
    end
end

local function Explain()
    local world = World()
    return world and world.ExplainActive and world.ExplainActive() or "No active destination"
end

BLOCKS.actions = {}
function BLOCKS.actions.create(parent)
    local block = CreateFrame("Frame", nil, parent)
    local icons = addon.VignetteRadarIconButton
    block.icons = {}
    if not (icons and icons.Create) then return block end
    block.icons.lock = icons.Create(block, "unlock", { size = ACTION, activeIcon = "lock",
        label = "Lock Stop", isActive = Locked,
        tooltip = function(self)
            self.labelText = Locked() and "Unlock Stop" or "Lock Stop"
            return Locked() and "Let Auto Route move past this stop again."
                or "Keep Auto Route on this stop until you unlock it."
        end,
        onClick = function()
            local world = World()
            if world and world.ToggleRouteLock then world.ToggleRouteLock() end
            Changed()
        end })
    block.icons.skip = icons.Create(block, "next", { size = ACTION, label = "Skip Stop",
        tooltip = "Move Auto Route on to the next stop.",
        onClick = function()
            local world = World()
            if world and world.SkipRouteStop then world.SkipRouteStop() end
            Changed()
        end })
    block.icons.why = icons.Create(block, "info", { size = ACTION, label = "Why This Stop", tooltip = Explain,
        onClick = function()
            if addon.ShowVignetteRadarRouteNote then addon.ShowVignetteRadarRouteNote("WHY THIS STOP", Explain()) end
        end })
    block.icons.share = icons.Create(block, "share", { size = ACTION, label = "Share To Group",
        tooltip = function()
            local share = addon.VignetteRadarShareToGroup
            return "Post this point as a map pin to " .. (share and share.Channel():lower() or "chat") .. "."
        end,
        onClick = ShareClicked })
    return block
end

function BLOCKS.actions.render(block, snap, width)
    local lines = Guidance().Lines("actions", snap)
    local shown = {}
    local perRow = max(1, floor((width - 2 * PAD + 6) / (ACTION + 6)))
    for index, line in ipairs(lines) do
        local button = block.icons[line[1]]
        if button then
            shown[button] = true
            local slot = index - 1
            Place(button, block, PAD + (slot % perRow) * (ACTION + 6), floor(slot / perRow) * (ACTION + 4))
            if button.Refresh then button:Refresh() end
            button:Show()
        end
    end
    for _, button in pairs(block.icons) do
        if not shown[button] then button:Hide() end
    end
    if #lines == 0 then return nil end
    return math.ceil(#lines / perRow) * (ACTION + 4) - 4
end

-- Notice -------------------------------------------------------------------

BLOCKS.notice = {}
function BLOCKS.notice.create(parent)
    local block = CreateFrame("Frame", nil, parent)
    block.label = NewText(block, "caption")
    block.text = NewText(block, "body")
    block.detail = NewText(block, "caption", SOFT)
    return block
end

function BLOCKS.notice.render(block, snap, width)
    local lines = Guidance().Lines("notice", snap)
    if #lines == 0 then return nil end
    block.label:SetTextColor(Accent())
    local inner = width - 2 * PAD
    local y = Flow(block.label, block, PAD, 0, inner, lines[1][1]) + 1
    y = y + Flow(block.text, block, PAD, y, inner, lines[1][2])
    if lines[2] then
        y = y + 1 + Flow(block.detail, block, PAD, y + 1, inner, lines[2][2])
    else
        block.detail:Hide()
    end
    return y
end

-- Order ----------------------------------------------------------------------

-- The blocks in the player's order (vignetteRadarGuideOrder), header first;
-- unknown ids are dropped and missing ones keep their default place.
function GuidePanel.Order(settings)
    local order, seen = { "header" }, { header = true }
    local saved = settings and settings.vignetteRadarGuideOrder
    for _, id in ipairs(type(saved) == "table" and saved or {}) do
        if BLOCKS[id] and not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    for _, id in ipairs(DEFAULT_ORDER) do
        if not seen[id] then
            seen[id] = true
            order[#order + 1] = id
        end
    end
    return order
end

-- Moves a block one place up; the top one goes to the bottom.
function GuidePanel.MoveBlock(id)
    local order = GuidePanel.Order(Settings())
    table.remove(order, 1)
    for index, existing in ipairs(order) do
        if existing == id then
            table.remove(order, index)
            if index == 1 then order[#order + 1] = id else table.insert(order, index - 1, id) end
            return Write("vignetteRadarGuideOrder", order)
        end
    end
    return false
end

function GuidePanel.OrderText(settings)
    local names = {}
    for index, id in ipairs(GuidePanel.Order(settings)) do
        if index > 1 then names[#names + 1] = NAMES[id] end
    end
    return "Order: " .. table.concat(names, " · ") .. ". Click a block below to move it up."
end

-- Frame --------------------------------------------------------------------

local function Ensure()
    if frame then return frame end
    frame = CreateFrame("Frame", "VignetteRadarGuidePanelFrame", UIParent)
    frame:SetSize(260, 40)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)
    local controls = addon.VignetteRadarControls
    if controls and controls.RoundedStatusSurface then controls.RoundedStatusSurface(frame) end
    frame.blocks = {}
    local regions = {}
    for _, id in ipairs(GuidePanel.Order(nil)) do
        local block = BLOCKS[id].create(frame)
        block:Hide()
        frame.blocks[id] = block
        regions[#regions + 1] = block
    end
    for _, row in ipairs(frame.blocks.stops.rows) do regions[#regions + 1] = row end
    -- Docked under the radar (or under nothing: then it floats), or free
    -- where it was dragged; hover for the detach and lock icons.
    local tray = addon.VignetteRadarTray
    if tray and tray.RegisterPanel then
        tray.RegisterPanel(frame, { key = "guide", label = "the Guide Panel", order = 10, floatAlone = true,
            homeY = -120, regions = regions, refresh = function() GuidePanel.Refresh() end })
    end
    frame:Hide()
    return frame
end

local function Hide()
    if frame and frame:IsShown() then frame:Hide() end
    local guidance = Guidance()
    if guidance then guidance.Watch(false) end
end

local function Skin()
    local style = addon.VignetteRadarStyle
    local revision = style and style.revision or -1
    if frame._styleRevision == revision then return false end
    frame._styleRevision = revision
    local controls = addon.VignetteRadarControls
    if controls and controls.RefreshRoundedStatusSurface then controls.RefreshRoundedStatusSurface(frame) end
    local tray = addon.VignetteRadarTray
    if tray and tray.SkinLikeRadar then tray.SkinLikeRadar(frame, .9) end
    for _, row in ipairs(frame.blocks.stops.rows) do row._item = nil end
    return true
end

-- Everything the layout depends on besides the snapshot.
local function LayoutKey(settings, snap, width)
    local blocks = {}
    for _, id in ipairs(GuidePanel.Order(settings)) do
        blocks[#blocks + 1] = id .. (BlockOn(settings, id) and "1" or "0")
    end
    return table.concat(blocks, ",") .. "|" .. tostring(settings.vignetteRadarGuideDensity) .. "|"
        .. tostring(settings.vignetteRadarShareButton) .. "|" .. width .. "|" .. snap.revision
        .. "|" .. tostring(frame._styleRevision) .. "|" .. CompassKey(settings)
end

local function Layout(snap, settings)
    local width = floor(Number(frame:GetWidth()) or 260)
    local key = LayoutKey(settings, snap, width)
    if frame._layoutKey == key then return frame._layoutHeight end
    local compact = settings.vignetteRadarGuideDensity == "compact"
    local used, y = {}, PAD
    local traced = addon.Trace and addon.Trace.IsOn() and {} or nil
    for _, id in ipairs(GuidePanel.Order(settings)) do
        local block = frame.blocks[id]
        if BlockOn(settings, id) and (not compact or COMPACT[id]) then
            local height = BLOCKS[id].render(block, snap, width, settings, compact)
            if height then
                height = math.ceil(height)
                block:SetSize(width, height)
                block._x = nil
                Place(block, frame, 0, y)
                block:Show()
                used[block] = true
                y = y + height + BLOCK_GAP
                if traced then traced[#traced + 1] = id .. "=" .. height end
            end
        end
    end
    for _, block in pairs(frame.blocks) do
        if not used[block] then block:Hide() end
    end
    local height = y == PAD and 0 or y - BLOCK_GAP + PAD
    if traced then
        Log("layout %s %dpx: %s (mode %s)", compact and "compact" or "full", width,
            #traced > 0 and table.concat(traced, " ") or "empty", snap.mode)
    end
    frame._layoutKey, frame._layoutHeight = key, height
    return height
end

function GuidePanel.Refresh()
    local settings = Settings()
    local guidance = Guidance()
    local tray = addon.VignetteRadarTray
    if settings.vignetteRadarGuidePanel ~= true or settings.vignetteRadarEnabled == false
        or not (guidance and tray and tray.PlacePanel) then return Hide() end
    local snap = guidance.Snapshot()
    if not (snap.target or snap.route or snap.briefing or snap.notice) then return Hide() end
    Ensure()
    -- With nothing focused, the zone line rides along the open radar (or a
    -- panel set free); it never floats on its own.
    if not snap.target and not snap.route and not (tray.IsPanelDetached(frame) or tray.CanDock()) then
        return Hide()
    end
    local wanted = Number(settings.vignetteRadarGuideWidth)
    local placed = tray.PlacePanel(frame, GAP, WIDTHS[wanted] and wanted or 260)
    if not placed then return Hide() end
    if Skin() then frame._layoutKey = nil end
    -- The chevron follows the live target table (Tick updates it in place).
    frame.blocks.header.target = snap.target
    local height = Layout(snap, settings)
    if height == 0 then return Hide() end
    if frame._height ~= height then
        frame._height = height
        frame:SetHeight(height)
    end
    tray.SettlePanel(frame)
    local fade = settings.vignetteRadarWorldMarkerCombatFade == true and addon.Bus and addon.Bus.InCombat() or false
    local alpha = fade and .35 or 1
    if frame._alpha ~= alpha then frame._alpha = alpha; frame:SetAlpha(alpha) end
    if not frame:IsShown() then frame:Show() end
    guidance.Watch(true)
end

function GuidePanel.GetFrame() return frame end

function GuidePanel.IsShown() return frame ~= nil and frame:IsShown() end

-- Route notes land in the panel while it shows with its notice block on.
function GuidePanel.ShowsNotices()
    return GuidePanel.IsShown() and BlockOn(Settings(), "notice")
end

-- Forgets the free spot: the panel goes back to its home spot.
function GuidePanel.ResetPosition()
    local tray = addon.VignetteRadarTray
    if frame and tray and tray.ResetPanel then tray.ResetPanel(frame) end
end

-- Theme changes repaint at once: every string's base color again (its
-- contrast floor depends on the new surface), the skin, kind colors and the
-- layout. Skips when neither the Style revision nor the accent changed (a
-- profile swap can change the accent without a revision bump).
local painted = {}
function GuidePanel.RefreshTheme()
    local style = addon.VignetteRadarStyle
    local revision = style and style.revision
    local r, g, b = Accent()
    if painted.revision == revision and painted.r == r and painted.g == g and painted.b == b then return false end
    painted.revision, painted.r, painted.g, painted.b = revision, r, g, b
    if not frame then return false end
    for _, entry in ipairs(texts) do
        local color = entry[2]
        entry[1]:SetTextColor(color[1], color[2], color[3], 1)
    end
    frame._styleRevision, frame._layoutKey = nil, nil
    for _, row in ipairs(frame.blocks.stops.rows) do row._item = nil end
    for _, tick in ipairs(frame.blocks.compass.ticks) do tick._revision = nil end
    -- Kind colors (the header dot) live in the snapshot.
    local guidance = Guidance()
    if guidance then guidance.Invalidate() end
    Log("theme: repaint (shown %s)", frame:IsShown())
    if frame:IsShown() then GuidePanel.Refresh() end
    return true
end

-- Ride the Looks broadcast: every theme change ends in Controls.RefreshTheme.
local controls = addon.VignetteRadarControls
if controls and type(controls.RefreshTheme) == "function" then
    local refreshControls = controls.RefreshTheme
    controls.RefreshTheme = function(...)
        refreshControls(...)
        GuidePanel.RefreshTheme()
    end
end

if addon.Bus then
    addon.Bus.On("LOGIN", function() GuidePanel.Refresh() end)
    addon.Bus.On("GUIDANCE_CHANGED", function() GuidePanel.Refresh() end)
end
