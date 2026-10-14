local _, addon = ...
if type(addon) ~= "table" then return end

-- Themed icon buttons drawn from Media/button-icons.tga
-- (tools/generate_button_icons.py). Every button stacks five white masks,
-- each tinted by its own theme role, so a Multi-Color theme can color them
-- apart (Style.iconSlots):
--   plate (iconPlate)  glow (iconHover)  border (iconBorder)
--   glyph (iconGlyph, the "art" texture)  underline (iconActive)
-- States are tint and alpha: hover lights the glow and border, active shows
-- the underline and turns the glyph to its selected color (SelectedColor), pressed nudges the glyph down a pixel, disabled fades the
-- glyph to the rings color. Single Color themes stay quiet (no plate or
-- border until hover), like the radar's own glyphs; Multi-Color themes are
-- "framed" (plate and border always drawn), see Style.IconFramed. A framed
-- idle button draws its border in the rings color and its glyph dimmer;
-- only hover (iconBorder) and selected (SelectedColor) light the border.
-- The label is the tooltip title and stays readable in button.labelText.
-- AddLayers/Paint also skin buttons made elsewhere (radar corner tools,
-- settings rail). Controls.IconButton is the separate +/- stepper glyph.
local IconButton = {}
addon.VignetteRadarIconButton = IconButton

IconButton.ATLAS = "Interface\\AddOns\\Magpie\\Media\\button-icons.tga"
-- Button icons, in the generator's order (GLYPHS starts with these).
IconButton.ICONS = { "options", "share", "undo", "refresh", "detach", "dock", "lock",
    "unlock", "close", "list", "focus", "next", "back", "minimap",
    "follow", "lead", "eye", "search", "info", "pause", "clear" }
-- Radar corner tools and settings rail glyphs follow them in the atlas.
IconButton.CORNER = { "config", "target", "legend", "minus", "plus", "north",
    "trail", "eye", "player", "close", "route", "tracker",
    "clear", "arrow", "minimize", "constellation" }
IconButton.RAIL = { "radar", "looks", "alerts", "markers", "quests", "routes",
    "hud", "data", "tools", "search" }
-- The Minimap Underlay toggle's icon name.
IconButton.MINIMAP = "minimap"

local COLUMNS, CELL, WIDTH, HEIGHT, GLYPH_ROWS = 16, 64, 1024, 256, 3
local LAYER_COLUMN = { plate = 0, border = 1, glow = 2, underline = 3 }
local INDEX = {}
do
    local count = 0
    local function Add(name) INDEX[name] = count; count = count + 1 end
    for _, name in ipairs(IconButton.ICONS) do Add(name) end
    for _, name in ipairs(IconButton.CORNER) do Add("corner_" .. name) end
    for _, name in ipairs(IconButton.RAIL) do Add("rail_" .. name) end
end
local FALLBACK = { iconGlyph = { .05, .82, .62 }, iconBorder = { .05, .82, .62 }, iconPlate = { .015, .022, .028 },
    iconHover = { .05, .82, .62 }, iconActive = { .05, .82, .62 }, rings = { .45, .52, .54 } }
local skinned = setmetatable({}, { __mode = "k" })
local painted = { revision = nil }

local function Color(slot)
    local style = addon.VignetteRadarStyle
    if style and style.Color then return style.Color(slot) end
    local value = FALLBACK[slot] or FALLBACK.iconGlyph
    return value[1], value[2], value[3]
end

-- The selected glyph's color: the theme's iconActive role, or, when that
-- matches the glyph (Single Color themes), the glyph's opposite hue.
-- Mirroring each channel through (max + min) turns the hue 180 degrees and
-- keeps lightness and saturation.
local function SelectedColor()
    local r, g, b = Color("iconActive")
    local gr, gg, gb = Color("iconGlyph")
    if math.abs(r - gr) + math.abs(g - gg) + math.abs(b - gb) > .06 then return r, g, b end
    local mirror = math.max(gr, gg, gb) + math.min(gr, gg, gb)
    return mirror - gr, mirror - gg, mirror - gb
end
IconButton.SelectedColor = SelectedColor

local function Apart(r, g, b, slot)
    local sr, sg, sb = Color(slot)
    return math.abs(r - sr) + math.abs(g - sg) + math.abs(b - sb) > .3
end

-- The "on" color for the glyph and underline of a selected button. It must
-- read apart from hover (iconBorder, iconHover) and from the idle glyph, so
-- the selected color is kept when it is, else the hover hue turned 120 or
-- 240 degrees (a channel rotation keeps lightness and saturation).
local function OnColor()
    local r, g, b = SelectedColor()
    if Apart(r, g, b, "iconHover") and Apart(r, g, b, "iconBorder") and Apart(r, g, b, "iconGlyph") then
        return r, g, b
    end
    local hr, hg, hb = Color("iconHover")
    local best, bestScore
    for _, c in ipairs({ { hb, hr, hg }, { hg, hb, hr } }) do
        local score = (Apart(c[1], c[2], c[3], "iconGlyph") and 2 or 0)
            + (Apart(c[1], c[2], c[3], "iconBorder") and 1 or 0)
        if not bestScore or score > bestScore then best, bestScore = c, score end
    end
    return best[1], best[2], best[3]
end
IconButton.OnColor = OnColor

local function Framed()
    local style = addon.VignetteRadarStyle
    return style and style.IconFramed and style.IconFramed() == true or false
end

local function Cell(row, column)
    return (column * CELL + 1) / WIDTH, (column * CELL + CELL - 1) / WIDTH,
        (row * CELL + 1) / HEIGHT, (row * CELL + CELL - 1) / HEIGHT
end

-- Texture coordinates of a glyph ("share", "corner_north", "rail_looks").
function IconButton.Coords(name)
    local index = INDEX[name] or INDEX.close
    return Cell(math.floor(index / COLUMNS), index % COLUMNS)
end

-- Texture coordinates of a shared layer mask: plate, border, glow, underline.
function IconButton.LayerCoords(layer)
    return Cell(GLYPH_ROWS, LAYER_COLUMN[layer] or 0)
end

function IconButton.HasIcon(name) return INDEX[name] ~= nil end

-- Point any texture at one glyph (for art that is not a button).
function IconButton.SetTexture(texture, name)
    texture:SetTexture(IconButton.ATLAS)
    texture:SetTexCoord(IconButton.Coords(name))
end

local function Layer(frame, drawLayer, sublevel, size, left, right, top, bottom)
    local texture = frame:CreateTexture(nil, drawLayer, nil, sublevel)
    texture:SetTexture(IconButton.ATLAS)
    texture:SetTexCoord(left, right, top, bottom)
    texture:SetSize(size, size)
    texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
    return texture
end

-- Builds the five layers on any frame; frame.art is the glyph.
function IconButton.AddLayers(frame, glyph, size)
    local layers = {
        plate = Layer(frame, "BACKGROUND", 1, size, IconButton.LayerCoords("plate")),
        glow = Layer(frame, "BORDER", 1, size, IconButton.LayerCoords("glow")),
        border = Layer(frame, "ARTWORK", 1, size, IconButton.LayerCoords("border")),
        underline = Layer(frame, "OVERLAY", 1, size, IconButton.LayerCoords("underline")),
    }
    frame.art = Layer(frame, "ARTWORK", 2, size, IconButton.Coords(glyph))
    frame.iconLayers, frame.glyphName, frame._artPressed = layers, glyph, false
    skinned[frame] = true
    return frame
end

-- Alpha per layer: { plate, border, glow } for quiet and framed looks.
local QUIET = { idle = { 0, 0, 0 }, hover = { 0, .26, .20 }, active = { 0, 0, 0 }, both = { 0, .26, .22 } }
-- Selected keeps the idle plate and border: only the glyph and underline
-- say "on", so a selected button never looks like a hovered one.
local FRAMED = { idle = { .22, .45, 0 }, hover = { .32, .95, .24 }, active = { .22, .45, 0 },
    both = { .34, 1, .26 } }
-- Glyph alpha while idle (not hovered, not active). Framed idle buttons sit
-- a step back so only the selected ones read as lit.
local IDLE_GLYPH = { quiet = .86, framed = .72 }

-- Paints a skinned frame. Cheap to call often: nothing is set when the
-- theme revision, glyph and state match the last paint.
function IconButton.Paint(frame, active, hovered, pressed, enabled, glyph)
    if not frame.iconLayers then return end
    enabled = enabled ~= false
    hovered, pressed = enabled and hovered == true, enabled and pressed == true
    active = active == true
    glyph = glyph or frame.glyphName
    local style = addon.VignetteRadarStyle
    local revision = style and style.revision or 0
    local framed = Framed()
    local key = tostring(revision) .. (framed and "f" or "q") .. (active and "a" or "") .. (hovered and "h" or "")
        .. (pressed and "p" or "") .. (enabled and "" or "d") .. glyph
    frame._paintActive, frame._paintHovered, frame._paintPressed = active, hovered, pressed
    frame._paintEnabled, frame._paintGlyph = enabled, glyph
    if frame._paintKey == key then return end
    frame._paintKey = key
    frame._artState = (active and 2 or 0) + ((hovered or pressed) and 1 or 0)
    if frame._artGlyph ~= glyph then
        frame.art:SetTexCoord(IconButton.Coords(glyph))
        frame._artGlyph = glyph
    end
    local layers = frame.iconLayers
    local look = framed and FRAMED or QUIET
    local alphas = look[(active and (hovered or pressed)) and "both" or active and "active"
        or (hovered or pressed) and "hover" or "idle"]
    local r, g, b
    if enabled then
        if active then r, g, b = OnColor() else r, g, b = Color("iconGlyph") end
        frame.art:SetVertexColor(r, g, b, (hovered or active) and 1 or IDLE_GLYPH[framed and "framed" or "quiet"])
    else
        r, g, b = Color("rings")
        frame.art:SetVertexColor(r, g, b, .38)
        alphas = { framed and .10 or 0, 0, 0 }
    end
    r, g, b = Color("iconPlate")
    layers.plate:SetVertexColor(r, g, b, alphas[1])
    -- Border by state: hover takes the theme's border role, and every other
    -- button (selected or not) the quiet rings color; selected shows only in
    -- the glyph and underline.
    -- (One bright border on every framed button made them all look selected.)
    if enabled and (hovered or pressed) then r, g, b = Color("iconBorder")
    elseif framed then r, g, b = Color("rings")
    else r, g, b = Color("iconBorder") end
    layers.border:SetVertexColor(r, g, b, alphas[2])
    r, g, b = Color("iconHover")
    layers.glow:SetVertexColor(r, g, b, pressed and alphas[3] + .12 or alphas[3])
    if enabled and active then
        r, g, b = OnColor()
        layers.underline:SetVertexColor(r, g, b, 1)
    else
        r, g, b = Color("iconActive")
        layers.underline:SetVertexColor(r, g, b, 0)
    end
    if frame._artPressed ~= pressed then
        frame._artPressed = pressed
        frame.art:ClearAllPoints()
        frame.art:SetPoint("CENTER", frame, "CENTER", 0, pressed and -1 or 0)
    end
end

local function Detail(button)
    local detail = button.tooltipDetail
    if type(detail) == "function" then detail = detail(button) end
    return detail
end

local function Active(button)
    if button.isActive then return button.isActive(button) == true end
    return button._active == true
end

local function ShowTooltip(button)
    if not GameTooltip then return end
    -- The detail runs first: a detail function may also update labelText.
    local detail = Detail(button)
    if not button.labelText then return end
    GameTooltip:SetOwner(button, button.tooltipAnchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(button.labelText, 1, 1, 1)
    if detail and detail ~= "" then GameTooltip:AddLine(detail, .66, .8, .78, true) end
    GameTooltip:Show()
end

local function Refresh(button)
    local active = Active(button)
    IconButton.Paint(button, active, button._hovered, button._pressed, button._enabled ~= false,
        active and button.activeIcon or button.icon)
end
IconButton.Refresh = Refresh

-- options: label (tooltip title), tooltip (detail string or function),
-- size (hit box, default 20), artSize (default size), isActive(button),
-- activeIcon (icon shown while active), onClick(button, mouseButton),
-- anchor (tooltip anchor), noTooltip (the caller shows its own).
function IconButton.Create(parent, icon, options)
    options = options or {}
    local size = options.size or 20
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.icon, button.activeIcon = icon, options.activeIcon
    button.labelText, button.tooltipDetail = options.label, options.tooltip
    button.tooltipAnchor, button.isActive = options.anchor, options.isActive
    button._enabled = true
    IconButton.AddLayers(button, icon, options.artSize or size)

    function button:Refresh() Refresh(self) end
    button.RefreshAppearance = button.Refresh
    function button:SetIcon(name, activeName)
        self.icon = name
        if activeName ~= nil then self.activeIcon = activeName or nil end
        Refresh(self)
    end
    function button:SetLabel(text, detail)
        self.labelText = text
        if detail ~= nil then self.tooltipDetail = detail end
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then ShowTooltip(self) end
    end
    function button:SetActive(value)
        self._active = value == true
        Refresh(self)
    end
    local nativeSetEnabled = button.SetEnabled
    button.SetEnabled = function(self, enabled)
        enabled = enabled == true or enabled == 1
        if nativeSetEnabled then nativeSetEnabled(self, enabled) end
        self._enabled = enabled
        if not enabled then self._hovered, self._pressed = false, false end
        Refresh(self)
    end

    button:SetScript("OnEnter", function(self)
        self._hovered = true
        Refresh(self)
        if not options.noTooltip then ShowTooltip(self) end
    end)
    button:SetScript("OnLeave", function(self)
        self._hovered, self._pressed = false, false
        Refresh(self)
        if not options.noTooltip and GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnMouseDown", function(self)
        if self._enabled ~= false then self._pressed = true; Refresh(self) end
    end)
    button:SetScript("OnMouseUp", function(self) self._pressed = false; Refresh(self) end)
    button:SetScript("OnShow", Refresh)
    button:SetScript("OnHide", function(self) self._hovered, self._pressed = false, false end)
    if options.onClick then
        button:SetScript("OnClick", function(self, mouseButton)
            options.onClick(self, mouseButton)
            Refresh(self)
            if not options.noTooltip and GameTooltip and GameTooltip.IsOwned
                and GameTooltip:IsOwned(self) then ShowTooltip(self) end
        end)
    end
    button.ownRefresh = Refresh
    Refresh(button)
    return button
end

-- Repaint every skinned frame after a theme change (profile swaps can change
-- colors without a revision bump, so the glyph color is part of the check).
-- OnShow repaints hidden buttons as well.
function IconButton.RefreshTheme(force)
    local style = addon.VignetteRadarStyle
    local r, g, b = Color("iconGlyph")
    local revision = style and style.revision
    if not force and painted.revision == revision and painted.r == r and painted.g == g and painted.b == b then
        return
    end
    painted.revision, painted.r, painted.g, painted.b = revision, r, g, b
    for frame in pairs(skinned) do
        frame._paintKey = nil
        if frame.ownRefresh then frame.ownRefresh(frame)
        else
            IconButton.Paint(frame, frame._paintActive, frame._paintHovered, frame._paintPressed,
                frame._paintEnabled, frame._paintGlyph)
        end
    end
end

-- Ride the Looks broadcast: every theme change already ends in
-- Controls.RefreshTheme (UI/Controls.lua loads just before this file).
local controls = addon.VignetteRadarControls
if controls and type(controls.RefreshTheme) == "function" then
    local refreshControls = controls.RefreshTheme
    controls.RefreshTheme = function(...)
        refreshControls(...)
        IconButton.RefreshTheme()
    end
end
