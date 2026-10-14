local _, addon = ...
if type(addon) ~= "table" then return end

-- The radar's drawer. A handle sits on the radar's own edge, and one content
-- frame at a time slides out of a clipped slot beside it, like a cash
-- register tray: it stays part of the radar, and closes back into it on
-- combat or on a click elsewhere unless the tray is locked.
local Tray = {}
addon.VignetteRadarTray = Tray

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CORNER_ICONS = "Interface\\AddOns\\Magpie\\Media\\radar-corner-controls.tga"
-- JOIN tucks the tray under the radar face so it comes out from behind it.
local SLIDE_SECONDS, FOLLOW_SECONDS, JOIN, TOP_OFFSET, MIN_SCALE = .22, .05, 5, 10, .78
-- Handle styles: "lip" (the tray's front edge), "groove" (an inset slot on
-- the face edge) and "icon" (a round button in the corner-tool style).
-- The lip's hover strip straddles the face edge (LIP_HIT wide). Hovering
-- lights that side of the radar's own rounded border, corners included
-- (RIM_SLICE of the border art), and shades just inside it so the side looks
-- pressed in. FACE_CORNER and FACE_EDGE are the art's corner and border size.
local RING_ART = "Interface\\AddOns\\Magpie\\Media\\radar-rounded-border.tga"
local FACE_CORNER, FACE_EDGE, RIM_SLICE, DENT_DEPTH = 8 / 256, 2 / 256, 11 / 256, 10
local LIP_HIT, GROOVE_INSET, GROOVE_LENGTH, ICON_SIZE, ICON_COLUMN = 14, 6, 34, 24, 2
-- The tray draws one layer below the radar, so the face covers the joint.
local STRATA_BELOW = { BACKGROUND = "BACKGROUND", LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM",
    DIALOG = "HIGH", FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG" }
local SIDES = { "right", "left", "top", "bottom" }
local OPPOSITE = { right = "left", left = "right", top = "bottom", bottom = "top" }
local IDLE = { .69, .77, .78 }

local slot, handle, events, owner
local room = {}
local progress, target, from, elapsed, follow = 0, 0, 0, 0, 0
local lockButtons = {}

local function Settings() return addon.GetSettings() end

local function Accent()
    local style = addon.VignetteRadarStyle
    if style and style.Color then return style.Color("accent") end
    return .96, .66, .5
end

-- The radar's visible face: the rounded square (or circle) on its field.
-- The outer panel frame is larger and mostly invisible, so the tray docks
-- to the face. Returns the face region and the frame that owns it.
local function Face()
    local radar = addon.VignetteRadarAPI
    local panel = radar and radar.GetPanel and radar.GetPanel()
    if not (panel and panel.IsShown and panel:IsShown()) then return nil end
    local host = panel.field or panel
    return host.background or host, host
end

-- A content frame's 3x3 rounded surface: the status style (Controls
-- RoundedStatusSurface) or the popup style (Controls PopupSurface).
local function Slices(frame)
    local surface = frame and frame.statusSurface
    if type(surface) == "table" then return surface.face or {}, surface.edge or {}, 8 / 256 end
    if frame and frame.popupFaceSlices then
        return frame.popupFaceSlices, frame.popupEdgeSlices or {}, 11 / 256
    end
end

-- Paints the surface like the radar face: the theme's background at the
-- face's opacity, outlined in the faint ring color. minAlpha, when given,
-- keeps a text-heavy surface readable over a see-through radar face.
local function SkinLikeRadar(frame, minAlpha)
    if Settings().vignetteRadarPanelsMatchRadar == false then return end
    local faces, edges = Slices(frame)
    if not faces then return end
    local style = addon.VignetteRadarStyle
    local br, bg, bb, ba, rr, rg, rb = .015, .022, .028, .94, .55, .35, .35
    if style and style.Color then
        br, bg, bb = style.Color("background")
        rr, rg, rb = style.Color("rings")
    end
    -- Copy the radar face's live color and opacity, whatever it is set to.
    local face = Face()
    if face and face.GetVertexColor then
        local r, g, b, a = face:GetVertexColor()
        if type(r) == "number" and type(a) == "number" then br, bg, bb, ba = r, g, b, a end
    end
    -- The minimap underlay thins the face so terrain shows through; panels
    -- keep the face's normal opacity instead of that tint.
    local underlay = addon.VignetteRadarMinimapUnderlay
    if underlay and underlay.IsActive and underlay.IsActive() and underlay.BaseAlpha then
        ba = underlay.BaseAlpha()
    end
    if type(minAlpha) == "number" and ba < minAlpha then ba = minAlpha end
    local edge = .1 + .3 * (Settings().vignetteRadarBorderOpacity or .5)
    for _, texture in ipairs(faces) do texture:SetVertexColor(br, bg, bb, ba) end
    for _, texture in ipairs(edges) do texture:SetVertexColor(rr, rg, rb, edge) end
end

-- Where the tray meets the radar its surface is square, not rounded: the two
-- corner slices on that side copy a straight neighbour, and the outline
-- slice along the joint is hidden. Keys are the radar side the tray sits on;
-- slices are numbered row by row. A nil side restores the rounded surface.
local JOINS = {
    left = { corners = { [3] = 2, [9] = 8 }, hide = 6 },
    right = { corners = { [1] = 2, [7] = 8 }, hide = 4 },
    top = { corners = { [7] = 4, [9] = 6 }, hide = 8 },
    bottom = { corners = { [1] = 4, [3] = 6 }, hide = 2 },
}
local function SquareJoin(frame, side)
    local faces, edges, cut = Slices(frame)
    if not faces then return end
    local uv, join = { 0, cut, 1 - cut, 1 }, side and JOINS[side]
    for _, list in ipairs({ faces, edges }) do
        for index, texture in ipairs(list) do
            local piece = join and join.corners[index] or index
            local row, column = math.floor((piece - 1) / 3) + 1, (piece - 1) % 3 + 1
            texture:SetTexCoord(uv[column], uv[column + 1], uv[row], uv[row + 1])
        end
    end
    for index, texture in ipairs(edges) do texture:SetShown(not join or index ~= join.hide) end
end

local function Ease(t) return 1 - (1 - t) * (1 - t) * (1 - t) end

local function IsLocked() return Settings().vignetteRadarTrayLocked == true end

local function HandleStyle()
    local style = Settings().vignetteRadarTrayHandle
    return (style == "groove" or style == "icon") and style or "lip"
end

local function Solid(parent, layer)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(WHITE)
    return texture
end

local function Vertical(side) return side == "left" or side == "right" end

-- Lays out the parts of the current handle style once per style/side change.
-- button is the tray's own handle or one made by Tray.CreateHandle.
local function LayoutHandle(button, style, side)
    local vertical = Vertical(side)
    for _, dot in ipairs(button.grip) do dot:SetShown(style == "lip") end
    button.groove:SetShown(style == "groove")
    button.dent:Hide()
    button.rimGlow:Hide()
    button.icon:SetShown(style == "icon")
    if style == "lip" then
        -- Three dots on the face edge; hovering lights the edge itself.
        for index, dot in ipairs(button.grip) do
            local step = (index - 2) * 5
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", button, "CENTER", vertical and 0 or step, vertical and step or 0)
        end
    elseif style == "groove" then
        button.groove:ClearAllPoints()
        button.groove:SetPoint("CENTER", button, "CENTER")
        if vertical then button.groove:SetSize(3, GROOVE_LENGTH) else button.groove:SetSize(GROOVE_LENGTH, 3) end
    end
end

-- Paints a handle for its hover state and whether its drawer is out.
local function PaintHandle(button, open)
    local hovered = button._hovered == true
    local ir, ig, ib = IDLE[1], IDLE[2], IDLE[3]
    local ar, ag, ab = Accent()
    local style = addon.VignetteRadarStyle
    local rr, rg, rb = .55, .35, .35
    if style and style.Color then rr, rg, rb = style.Color("rings") end
    local kind = button._style
    if kind == "lip" then
        button.rimGlow:SetShown(hovered)
        button.dent:SetShown(hovered)
        if hovered then button.rimGlow:SetVertexColor(ar, ag, ab, .6) end
        for _, dot in ipairs(button.grip) do
            if hovered then dot:SetVertexColor(ar, ag, ab, 1) else dot:SetVertexColor(ir, ig, ib, .45) end
        end
    elseif kind == "groove" then
        if hovered then button.groove:SetVertexColor(ar, ag, ab, 1)
        else button.groove:SetVertexColor(rr, rg, rb, open and .8 or .55) end
    elseif kind == "icon" then
        -- Same atlas and states as the radar's corner tools.
        local column = button.iconColumn or ICON_COLUMN
        local state = (open and 2 or 0) + (hovered and 1 or 0)
        button.icon:SetTexCoord((column * 64 + 1) / 1024, (column * 64 + 63) / 1024,
            (state * 64 + 1) / 256, (state * 64 + 63) / 256)
        if hovered or open then button.icon:SetVertexColor(ar, ag, ab, 1)
        else button.icon:SetVertexColor(ir, ig, ib, .78) end
    end
end

local function RefreshHandle()
    if handle then PaintHandle(handle, target == 1) end
end

-- A handle's parts (grip dots, groove, rim glow, dent, icon), one level
-- above the radar host's own children.
local function BuildHandle(host, levelOffset)
    local button = CreateFrame("Button", nil, host)
    button:SetFrameLevel(host:GetFrameLevel() + (levelOffset or 30))
    button:RegisterForClicks("LeftButtonUp")
    button.grip = {}
    for index = 1, 3 do
        local dot = Solid(button, "OVERLAY")
        dot:SetSize(2, 2)
        button.grip[index] = dot
    end
    button.groove = Solid(button, "ARTWORK")
    button.dent = Solid(button, "BORDER")
    button.dent:Hide()
    button.rimGlow = button:CreateTexture(nil, "ARTWORK")
    button.rimGlow:SetTexture(RING_ART)
    button.rimGlow:Hide()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(CORNER_ICONS)
    button.icon:SetAllPoints(button)
    return button
end

local function EnsureHandle(host)
    if handle then
        if handle:GetParent() ~= host then handle:SetParent(host) end
        return handle
    end
    handle = BuildHandle(host, 30)
    handle:SetScript("OnClick", function() Tray.Toggle() end)
    handle:SetScript("OnEnter", function(self)
        self._hovered = true
        RefreshHandle()
        if not GameTooltip or not owner then return end
        -- Open the note on the tray's side, away from the radar.
        local side = self.side or "right"
        GameTooltip:SetOwner(self, side == "left" and "ANCHOR_LEFT" or side == "top" and "ANCHOR_TOP"
            or side == "bottom" and "ANCHOR_BOTTOM" or "ANCHOR_RIGHT")
        GameTooltip:SetText(owner.label or "Tray", 1, .87, .66)
        GameTooltip:AddLine(target == 1 and "Click To Slide The Tray In." or "Click To Slide The Tray Out.",
            .66, .8, .78, true)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function(self)
        self._hovered = nil
        RefreshHandle()
        if GameTooltip then GameTooltip:Hide() end
    end)
    return handle
end

-- Places a handle on the radar face edge. The lip's hover strip runs the
-- tray's full length on the joint side, so it can be clicked from the tray
-- edge next to the radar, open or closed. length and along are in the
-- radar's own units.
local function PositionHandle(button, face, side, length, along)
    local style = HandleStyle()
    if button._style ~= style or button._layoutSide ~= side then
        button._style, button._layoutSide, button._placed = style, side, nil
        LayoutHandle(button, style, side)
    end
    local vertical = Vertical(side)
    if button._placed ~= along or button.anchor ~= face or button.side ~= side or button._length ~= length then
        button._placed, button.anchor, button.side, button._length = along, face, side, length
        button:ClearAllPoints()
        if style == "lip" then
            if vertical then
                button:SetSize(LIP_HIT, length)
                button:SetPoint("TOP", face, side == "left" and "TOPLEFT" or "TOPRIGHT", 0, -along)
            else
                button:SetSize(length, LIP_HIT)
                button:SetPoint("CENTER", face, side == "top" and "TOP" or "BOTTOM", along, 0)
            end
        elseif style == "groove" then
            if vertical then button:SetSize(12, GROOVE_LENGTH + 10) else button:SetSize(GROOVE_LENGTH + 10, 12) end
            if side == "left" then button:SetPoint("CENTER", face, "LEFT", GROOVE_INSET, 0)
            elseif side == "right" then button:SetPoint("CENTER", face, "RIGHT", -GROOVE_INSET, 0)
            elseif side == "top" then button:SetPoint("CENTER", face, "TOP", 0, -GROOVE_INSET)
            else button:SetPoint("CENTER", face, "BOTTOM", 0, GROOVE_INSET) end
        else
            button:SetSize(ICON_SIZE, ICON_SIZE)
            button:SetPoint("CENTER", face, vertical and (side == "left" and "LEFT" or "RIGHT")
                or (side == "top" and "TOP" or "BOTTOM"))
        end
    end
    local size = face:GetWidth()
    if style == "lip" and size and size > 0 and (button._faceSize ~= size or button._edgeSide ~= side) then
        button._faceSize, button._edgeSide = size, side
        local corner, border = size * FACE_CORNER, size * FACE_EDGE
        local rim, dent, slice = button.rimGlow, button.dent, size * RIM_SLICE
        local shade, clear = CreateColor(0, 0, 0, .45), CreateColor(0, 0, 0, 0)
        rim:ClearAllPoints()
        dent:ClearAllPoints()
        if side == "left" then
            rim:SetPoint("TOPLEFT", face, "TOPLEFT")
            rim:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT")
            rim:SetWidth(slice)
            rim:SetTexCoord(0, RIM_SLICE, 0, 1)
            dent:SetPoint("TOPLEFT", face, "TOPLEFT", border, -corner)
            dent:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", border, corner)
            dent:SetWidth(DENT_DEPTH)
            dent:SetGradient("HORIZONTAL", shade, clear)
        elseif side == "right" then
            rim:SetPoint("TOPRIGHT", face, "TOPRIGHT")
            rim:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT")
            rim:SetWidth(slice)
            rim:SetTexCoord(1 - RIM_SLICE, 1, 0, 1)
            dent:SetPoint("TOPRIGHT", face, "TOPRIGHT", -border, -corner)
            dent:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", -border, corner)
            dent:SetWidth(DENT_DEPTH)
            dent:SetGradient("HORIZONTAL", clear, shade)
        elseif side == "top" then
            rim:SetPoint("TOPLEFT", face, "TOPLEFT")
            rim:SetPoint("TOPRIGHT", face, "TOPRIGHT")
            rim:SetHeight(slice)
            rim:SetTexCoord(0, 1, 0, RIM_SLICE)
            dent:SetPoint("TOPLEFT", face, "TOPLEFT", corner, -border)
            dent:SetPoint("TOPRIGHT", face, "TOPRIGHT", -corner, -border)
            dent:SetHeight(DENT_DEPTH)
            dent:SetGradient("VERTICAL", clear, shade)
        else
            rim:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT")
            rim:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT")
            rim:SetHeight(slice)
            rim:SetTexCoord(0, 1, 1 - RIM_SLICE, 1)
            dent:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", corner, border)
            dent:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", -corner, border)
            dent:SetHeight(DENT_DEPTH)
            dent:SetGradient("VERTICAL", shade, clear)
        end
    end
end

local function PlaceHandle(host, face, side, length, along)
    local button = EnsureHandle(host)
    PositionHandle(button, face, side, length, along)
    button:Show()
    RefreshHandle()
end

local function ChooseSide(face, host, content)
    local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left, right, top, bottom = face:GetLeft(), face:GetRight(), face:GetTop(), face:GetBottom()
    local width, height = content:GetWidth(), content:GetHeight()
    if not (left and right and top and bottom and width > 0 and height > 0) then return end
    left, right, top, bottom = left * scale, right * scale, top * scale, bottom * scale
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    -- A panel that narrows to the face above or below the radar still picks
    -- its side by its natural width, so the side never flips back and forth.
    local sideWidth = owner.sideWidth and owner.sideWidth() or width
    room.right = (screenW - 8 - right) / sideWidth
    room.left = (left - 8) / sideWidth
    room.top = (screenH - 8 - top) / height
    room.bottom = (bottom - 8) / height
    local side = owner.side and owner.side() or "right"
    if room[side] < 1 then
        if room[OPPOSITE[side]] >= 1 then
            side = OPPOSITE[side]
        else
            for _, candidate in ipairs(SIDES) do
                if room[candidate] > room[side] then side = candidate end
            end
        end
    end
    local fit = math.floor(math.min(1, room[side]) * 1000) / 1000
    if fit < MIN_SCALE then return end
    local shift = 0
    if side == "top" or side == "bottom" then
        local half = width * fit / 2
        local center = math.max(half + 8, math.min(screenW - half - 8, (left + right) / 2))
        shift = center - (left + right) / 2
    end
    return side, fit, shift, scale
end

local function SetInteractive(value)
    if owner and owner.setInteractive and owner._interactive ~= value then
        owner._interactive = value
        owner.setInteractive(value)
    end
end

-- Lays the slot and content out for the current slide progress. Returns
-- false when the radar has no room for a docked tray.
function Tray.Place()
    if not owner then return false end
    local face, host = Face()
    local content = owner.frame
    if not face then
        if slot then slot:Hide() end
        if handle then handle:Hide() end
        return false
    end
    local side, fit, shift, scale = ChooseSide(face, host, content)
    if not side then
        if slot then slot:Hide() end
        if handle then handle:Hide() end
        return false
    end
    local vertical = Vertical(side)
    local width, height = content:GetWidth(), content:GetHeight()
    -- Beside the radar a panel is never taller than the quest tracker (the
    -- face less TOP_OFFSET above and below); a taller one scrolls inside.
    local slotHeight = height * fit
    local faceHeight = face:GetHeight()
    if vertical and faceHeight and scale then
        slotHeight = math.min(slotHeight, math.max(40, faceHeight * scale - 2 * TOP_OFFSET))
    end
    local overflow = math.max(0, height - slotHeight / fit)
    local scroll = math.max(0, math.min(overflow, owner._scroll or 0))
    owner._scroll = scroll
    -- Beside a round face a panel can tuck `inset` (its own units) under the
    -- face, so its rows curve around the circle (the Quest Tracker's round view).
    local inset = vertical and owner.inset and tonumber(owner.inset()) or 0
    inset = inset * fit
    if slot._side ~= side or slot._fit ~= fit or slot._shift ~= shift or slot._panel ~= face
        or slot._width ~= width or slot._height ~= height or slot._slotHeight ~= slotHeight
        or slot._inset ~= inset then
        local moved = slot._side ~= side
        slot._side, slot._fit, slot._shift, slot._panel = side, fit, shift, face
        slot._width, slot._height, slot._slotHeight, slot._inset = width, height, slotHeight, inset
        slot:SetFrameStrata(STRATA_BELOW[host:GetFrameStrata()] or "LOW")
        slot:SetSize(width * fit, slotHeight)
        slot:ClearAllPoints()
        if side == "right" then
            slot:SetPoint("TOPLEFT", face, "TOPRIGHT", -JOIN - inset, -TOP_OFFSET)
        elseif side == "left" then
            slot:SetPoint("TOPRIGHT", face, "TOPLEFT", JOIN + inset, -TOP_OFFSET)
        elseif side == "top" then
            slot:SetPoint("BOTTOM", face, "TOP", shift, -JOIN)
        else
            slot:SetPoint("TOP", face, "BOTTOM", shift, JOIN)
        end
        if content:GetScale() ~= fit then content:SetScale(fit) end
        if content:GetFrameStrata() ~= slot:GetFrameStrata() then content:SetFrameStrata(slot:GetFrameStrata()) end
        slot._retreat = nil
        if moved then
            SquareJoin(content, side)
            if owner.onSide then owner.onSide(side) end
        end
    end
    local hidden = 1 - progress
    local retreat = math.floor((vertical and width or height) * hidden * 10 + .5) / 10
    if slot._retreat ~= retreat or slot._scroll ~= scroll then
        slot._retreat, slot._scroll = retreat, scroll
        content:ClearAllPoints()
        if side == "right" then content:SetPoint("TOPLEFT", slot, "TOPLEFT", -retreat, scroll)
        elseif side == "left" then content:SetPoint("TOPRIGHT", slot, "TOPRIGHT", retreat, scroll)
        elseif side == "top" then content:SetPoint("BOTTOM", slot, "BOTTOM", 0, -retreat)
        else content:SetPoint("TOP", slot, "TOP", 0, retreat) end
    end
    -- Handle geometry in the radar's own units (the slot uses UIParent's).
    if scale and scale > 0 then
        PlaceHandle(host, face, side, (vertical and slotHeight or width * fit) / scale,
            (vertical and TOP_OFFSET or shift) / scale)
    end
    slot:SetShown(progress > 0 or target > 0)
    SetInteractive(progress >= .99)
    return true
end

-- Scrolls a panel taller than the tray (mouse wheel over it).
function Tray.Scroll(delta)
    if not owner then return end
    owner._scroll = (owner._scroll or 0) - (tonumber(delta) or 0) * 24
    Tray.Place()
end

-- True when anything Tray.Place reads for layout moved since the last
-- follow check: the face's spot or scale, the screen, or the content size.
-- The values are cached on the slot so a parked radar costs no relayout.
local function FollowChanged()
    local face, host = Face()
    local content = owner and owner.frame
    if not (face and content) then
        local changed = slot._followFace ~= nil
        slot._followFace = nil
        return changed or face ~= nil
    end
    local left, top = face:GetLeft(), face:GetTop()
    local scale, screen = host:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local width, height = content:GetWidth(), content:GetHeight()
    if slot._followFace == face and slot._followLeft == left and slot._followTop == top
        and slot._followScale == scale and slot._followScreen == screen
        and slot._followW == screenW and slot._followH == screenH
        and slot._followContentW == width and slot._followContentH == height then
        return false
    end
    slot._followFace, slot._followLeft, slot._followTop = face, left, top
    slot._followScale, slot._followScreen = scale, screen
    slot._followW, slot._followH = screenW, screenH
    slot._followContentW, slot._followContentH = width, height
    return true
end

local function OnUpdate(_, delta)
    if progress ~= target then
        elapsed = math.min(SLIDE_SECONDS, elapsed + delta)
        local t = elapsed / SLIDE_SECONDS
        progress = t >= 1 and target or from + (target - from) * Ease(t)
        Tray.Place()
        return
    end
    -- The radar can be dragged or rescaled while the tray is out; stay joined.
    follow = follow + delta
    if follow >= FOLLOW_SECONDS then
        follow = 0
        if FollowChanged() then Tray.Place() end
    end
end

local function EnsureSlot()
    if slot then return slot end
    slot = CreateFrame("Frame", "VignetteRadarTraySlot", UIParent)
    slot:SetClipsChildren(true)
    slot:Hide()
    slot:SetScript("OnUpdate", OnUpdate)
    return slot
end

local function Animate(value)
    if target == value then return end
    from, target, elapsed = progress, value, 0
    if value == 1 and slot then slot:Show() end
    RefreshHandle()
    for button in pairs(lockButtons) do button:RefreshLock() end
end

-- Any panel can wear the radar's own surface, docked or not.
Tray.SkinLikeRadar = SkinLikeRadar
-- The radar's visible face and its owner, for UI docked to the radar.
Tray.Face = Face
-- Squares the content's corners on the side that meets the radar.
Tray.SquareJoin = SquareJoin
Tray.TOP_OFFSET, Tray.JOIN, Tray.STRATA_BELOW = TOP_OFFSET, JOIN, STRATA_BELOW

-- A second drawer's handle in the same style as the tray's own (lip, groove
-- or icon, per vignetteRadarTrayHandle), for a drawer that is not the tray
-- (UI/ButtonTray.lua). options: onClick(), onEnter(button), onLeave(button),
-- iconColumn (corner atlas column for the icon style), levelOffset.
-- button:PlaceOn(face, side, length, along) in the radar's units;
-- button:SetOpen(open) repaints. Theme changes repaint it with the tray.
local extraHandles = {}
function Tray.CreateHandle(host, options)
    options = options or {}
    local button = BuildHandle(host, options.levelOffset or 31)
    button.iconColumn = options.iconColumn
    button:SetScript("OnClick", function() if options.onClick then options.onClick() end end)
    button:SetScript("OnEnter", function(self)
        self._hovered = true
        PaintHandle(self, self._open == true)
        if options.onEnter then options.onEnter(self) end
    end)
    button:SetScript("OnLeave", function(self)
        self._hovered = nil
        PaintHandle(self, self._open == true)
        if options.onLeave then options.onLeave(self) end
    end)
    function button:PlaceOn(face, side, length, along)
        PositionHandle(self, face, side, length, along)
        self:Show()
        PaintHandle(self, self._open == true)
    end
    function button:SetOpen(open)
        self._open = open == true
        if self._style then PaintHandle(self, self._open) end
    end
    extraHandles[button] = true
    return button
end

-- Screen room ----------------------------------------------------------------
-- Everything near the radar stays inside the screen by MARGIN UIParent units.
local MARGIN = 8
local panels = {}

local function Num(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
        and value or nil
end

-- A region's size relative to UIParent; scaler answers for a texture.
local function Ratio(region, scaler)
    scaler = scaler or region
    local own = scaler.GetEffectiveScale and Num(scaler:GetEffectiveScale())
    local base = UIParent and UIParent.GetEffectiveScale and Num(UIParent:GetEffectiveScale())
    if not (own and base and own > 0 and base > 0) then return 1 end
    return own / base
end

-- A region's edges in UIParent units, or nil before it is laid out.
local function Rect(region, scaler)
    if not (region and region.GetLeft) then return nil end
    local left, right = Num(region:GetLeft()), Num(region:GetRight())
    local top, bottom = Num(region:GetTop()), Num(region:GetBottom())
    if not (left and right and top and bottom) then return nil end
    local scale = Ratio(region, scaler)
    return left * scale, right * scale, top * scale, bottom * scale
end
Tray.Rect = Rect

local function Screen()
    if not UIParent then return nil end
    return Num(UIParent:GetWidth()), Num(UIParent:GetHeight())
end

-- How far the span low..high moves to sit inside MARGIN..size - MARGIN. A
-- span too big for the screen keeps its start inside: the left edge, or the
-- top edge when keepHigh is set (so a panel's title stays reachable).
local function Inside(low, high, size, keepHigh)
    if high - low > size - 2 * MARGIN then
        return keepHigh and (size - MARGIN - high) or (MARGIN - low)
    end
    if low < MARGIN then return MARGIN - low end
    if high > size - MARGIN then return size - MARGIN - high end
    return 0
end

-- Nudges a free frame back inside the screen, anchored by its top-left like
-- the saved panel spots. Returns true and the new left and top (UIParent
-- units, top measured from the screen's top) when it had to move.
function Tray.KeepOnScreen(frame)
    local left, right, top, bottom = Rect(frame)
    local screenW, screenH = Screen()
    if not (left and screenW and screenH) then return false end
    local dx, dy = Inside(left, right, screenW), Inside(bottom, top, screenH, true)
    if math.abs(dx) < .5 and math.abs(dy) < .5 then return false end
    local scale = Ratio(frame)
    left, top = left + dx, top + dy - screenH
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left / scale, top / scale)
    return true, left, top
end

-- Docked panels and everything stacked with them, below the anchor (plus
-- the panel being placed), in UIParent units.
local function StackHeight(frame, gap)
    local total = (Num(frame:GetHeight()) or 0) * Ratio(frame) + gap
    for other in pairs(panels) do
        if other ~= frame and other._dockAnchor and other:IsShown() then
            total = total + (Num(other:GetHeight()) or 0) * Ratio(other) + gap
        end
    end
    return total
end

-- The stack goes under its anchor unless that runs off the bottom of the
-- screen and above has more room.
local function RoomBelow(base, scaler, frame, gap)
    local _, _, top, bottom = Rect(base, scaler)
    local _, screenH = Screen()
    if not (bottom and screenH) then return true end
    if bottom - MARGIN >= StackHeight(frame, gap) then return true end
    return bottom - MARGIN >= screenH - MARGIN - top
end

-- The sideways shift (in frame units) that keeps a panel of this width,
-- centered under anchor, inside the screen's left and right edges.
local function SideShift(anchor, scaler, frame, width)
    local left, right = Rect(anchor, scaler)
    local screenW = Screen()
    if not (left and screenW and Num(width)) then return 0 end
    local scale = Ratio(frame)
    local half, center = width * scale / 2, (left + right) / 2
    local shift = math.max(half + MARGIN, math.min(screenW - half - MARGIN, center)) - center
    return math.floor(shift / scale + .5)
end

-- Docks a small panel to the radar: under the face, or above it while the
-- tray is out below or when the stack would run off the bottom of the
-- screen; with the radar closed, under the Guide Panel. When the panel after
-- is shown on the same side, frame stacks past it instead. A panel near a
-- screen edge slides sideways to stay inside. keepWidth leaves the width.
-- Returns false when there is nothing to dock to, else true, the width and
-- whether the anchor or width changed (so callers relayout only then).
function Tray.DockPanel(frame, after, gap, minWidth, keepWidth)
    local face, host = Face()
    local anchor, below, width = face, true
    gap = gap or 4
    if face then
        width = face:GetWidth()
        if Tray.Side() == "bottom" and Tray.IsOpen() then below = false end
    else
        local guide = addon.VignetteRadarGuidePanel
        local card = guide and guide.GetFrame and guide.GetFrame()
        if not (card and card ~= frame and card:IsShown()) then return false end
        anchor, host, width = card, card, card:GetWidth()
    end
    local base, scaler = anchor, host
    -- (Never above while the tray is out on top: it already sits there.)
    if below and not (face and Tray.Side() == "top" and Tray.IsOpen())
        and not RoomBelow(base, scaler, frame, gap) then below = false end
    if after and after ~= frame and after:IsShown() and after._dockBelow == below and not after._vrFree then
        anchor, scaler = after, after
    end
    width = math.max(minWidth or 0, type(width) == "number" and width or 0)
    if keepWidth then width = Num(frame:GetWidth()) or width end
    local shift = SideShift(anchor, scaler, frame, width)
    local changed = frame._dockAnchor ~= anchor or frame._dockBelow ~= below or frame._dockWidth ~= width
        or frame._dockShift ~= shift
    if changed then
        frame._dockAnchor, frame._dockBelow, frame._dockWidth, frame._dockShift = anchor, below, width, shift
        frame:ClearAllPoints()
        if below then frame:SetPoint("TOP", anchor, "BOTTOM", shift, -gap)
        else frame:SetPoint("BOTTOM", anchor, "TOP", shift, gap) end
        if not keepWidth then frame:SetWidth(width) end
    end
    if host and host.GetFrameStrata then
        frame:SetFrameStrata(host:GetFrameStrata())
        frame:SetFrameLevel((host:GetFrameLevel() or 1) + 4)
    end
    return true, width, changed
end

function Tray.IsOpen() return owner ~= nil and target == 1 end
function Tray.Side() return owner and slot and slot._side or nil end

-- The radar face's width in the docked panel's own units: a panel above or
-- below the radar uses it to sit flush with the face.
function Tray.AcrossWidth()
    local face, host = Face()
    local width = face and face:GetWidth()
    if not (width and width > 0 and host) then return nil end
    return width * host:GetEffectiveScale() / UIParent:GetEffectiveScale() / (slot and slot._fit or 1)
end
function Tray.GetHandle() return handle end
function Tray.GetSlot() return slot end
function Tray.IsAttached(frame) return owner ~= nil and owner.frame == frame end

function Tray.SetOpen(value)
    if not owner then return end
    value = value and true or false
    if owner.setOpen then owner.setOpen(value) end
    Animate(value and 1 or 0)
    Tray.Place()
end

function Tray.Toggle() Tray.SetOpen(target ~= 1) end

-- Closes the tray unless the person locked it open.
function Tray.Retract()
    if owner and target == 1 and not IsLocked() then Tray.SetOpen(false) end
end

-- options: frame, label, side(), isOpen(), setOpen(open),
-- setInteractive(on), keepOpen() (true while a related popup is in use),
-- onSide(side) when the tray moves to another edge of the radar.
-- Returns false, "busy" while another panel holds the tray; Tray.Show swaps.
function Tray.Attach(options)
    if type(options) ~= "table" or not options.frame then return false end
    EnsureSlot()
    if owner and owner.frame ~= options.frame then return false, "busy" end
    local fresh = owner == nil
    owner = options
    -- In the tray a panel is not free: its next free placement starts over.
    local content = options.frame
    if content._vrMoving then
        content._vrMoving = nil
        if content.StopMovingOrSizing then pcall(content.StopMovingOrSizing, content) end
    end
    content._vrFree, content._freeX, content._freeY = nil, nil, nil
    if fresh then
        owner._strata, owner._interactive, owner._scroll = options.frame:GetFrameStrata(), nil, 0
        if not options.frame:GetScript("OnMouseWheel") then
            options.frame:EnableMouseWheel(true)
            options.frame:SetScript("OnMouseWheel", function(_, delta) Tray.Scroll(delta) end)
            owner._wheel = true
        end
    end
    if options.frame:GetParent() ~= slot then options.frame:SetParent(slot) end
    SkinLikeRadar(options.frame)
    if fresh then
        target = options.isOpen and options.isOpen() and 1 or 0
        progress, from, elapsed = target, target, 0
        slot._retreat, slot._side = nil, nil
    end
    return Tray.Place()
end

function Tray.Detach(frame)
    if not owner or (frame and owner.frame ~= frame) then return end
    local content, previous = owner.frame, owner
    owner = nil
    progress, target = 0, 0
    if slot then slot:Hide() end
    if handle then handle:Hide() end
    content:SetParent(UIParent)
    content:SetScale(1)
    if previous._strata then content:SetFrameStrata(previous._strata) end
    if previous._wheel then
        content:SetScript("OnMouseWheel", nil)
        content:EnableMouseWheel(false)
    end
    SquareJoin(content, nil)
    local controls = addon.VignetteRadarControls
    if controls and content.popupFaceSlices and controls.RefreshPopupSurface then
        controls.RefreshPopupSurface(content)
    elseif controls and controls.RefreshRoundedStatusSurface then
        controls.RefreshRoundedStatusSurface(content)
    end
end

-- Puts this panel in the tray, swapping out whichever panel held it (that
-- panel's onReplaced runs), and slides the tray out.
function Tray.Show(options)
    if type(options) ~= "table" or not options.frame then return false end
    if owner and owner.frame ~= options.frame then
        local previous = owner
        Tray.Detach(previous.frame)
        if previous.onReplaced then previous.onReplaced() end
    end
    if not Tray.Attach(options) then return false end
    options.frame:Show()
    Tray.SetOpen(true)
    return true
end

-- True when the radar face is up, so a panel can dock beside it.
function Tray.CanDock() return Face() ~= nil end

function Tray.RefreshTheme()
    RefreshHandle()
    for button in pairs(extraHandles) do
        if button._style then PaintHandle(button, button._open == true) end
    end
    if owner then SkinLikeRadar(owner.frame) end
    for button in pairs(lockButtons) do button:RefreshLock() end
end

-- A detach/dock toggle (UI/IconButton.lua): the detach icon while docked,
-- the dock icon while free. isDetached() picks its state; onClick switches
-- between the tray and a free panel. options: size, labels ({ docked,
-- detached }) and tips (the same pair) for panels outside the tray.
function Tray.CreateDetachButton(parent, isDetached, onClick, options)
    options = options or {}
    local icons = addon.VignetteRadarIconButton
    local labels = options.labels or { "Detach From Radar", "Dock To Radar" }
    local tips = options.tips or { "Make this a free panel you can move and resize.",
        "Put this panel back in the radar's tray." }
    local function Label(button)
        local detached = isDetached() == true
        button.labelText = detached and labels[2] or labels[1]
        return detached and tips[2] or tips[1]
    end
    local button = icons.Create(parent, "detach", {
        size = options.size or 20, activeIcon = "dock", tooltip = Label,
        isActive = function() return isDetached() == true end,
        onClick = function() onClick() end,
    })
    Label(button)
    function button:RefreshDetach() Label(self); self:Refresh() end
    return button
end

-- A lock toggle (UI/IconButton.lua); locked keeps the tray out through
-- combat and clicks elsewhere. options (for other locks, such as a panel's
-- position): isLocked(), setLocked(value), size, labels ({ unlocked,
-- locked }) and tips (the same pair).
function Tray.CreateLockButton(parent, options)
    options = options or {}
    local icons = addon.VignetteRadarIconButton
    local isLocked = options.isLocked or IsLocked
    local setLocked = options.setLocked or function(value) Settings().vignetteRadarTrayLocked = value end
    local labels = options.labels or { "Tray Unlocked", "Tray Locked" }
    local tips = options.tips or { "Slides back in when combat starts or you click elsewhere.",
        "Stays out in combat and when you click elsewhere." }
    local function Label(button)
        local locked = isLocked() == true
        button.labelText = locked and labels[2] or labels[1]
        return locked and tips[2] or tips[1]
    end
    local button = icons.Create(parent, "unlock", {
        size = options.size or 20, activeIcon = "lock", tooltip = Label,
        isActive = function() return isLocked() == true end,
        onClick = function()
            setLocked(isLocked() ~= true)
            for other in pairs(lockButtons) do other:RefreshLock() end
        end,
    })
    Label(button)
    function button:RefreshLock() Label(self); self:Refresh() end
    lockButtons[button] = true
    return button
end

-- Panels near the radar -----------------------------------------------------
-- The small panels around the radar (the Guide Panel, UI/GuidePanel.lua)
-- share one behavior through RegisterPanel:
--  * Docked (the default), PlacePanel stacks them under the radar face, or
--    under the Guide Panel while the radar is closed, in `order`.
--    The stack goes above its anchor when there is no room below and slides
--    sideways to stay inside the screen (DockPanel).
--  * Detached, a panel floats where it is dragged. Its spot is saved per
--    panel in vignetteRadarPanelLayout[key] = { detached, locked, x, y }
--    (x and y in UIParent units from the screen's top-left). Dragging a
--    docked panel detaches it on the spot; the lock stops all dragging.
--  * A free panel is nudged back inside the screen after a move, a resize,
--    a UI scale change or a new screen size (KeepOnScreen).
-- Detach and lock icons show beside the panel while it is hovered.

local function Record(key)
    local layout = Settings().vignetteRadarPanelLayout
    local record = type(layout) == "table" and layout[key]
    return type(record) == "table" and record or nil
end

local function WriteRecord(key, fields)
    local db = Settings()
    if type(db.vignetteRadarPanelLayout) ~= "table" then db.vignetteRadarPanelLayout = {} end
    local record = db.vignetteRadarPanelLayout[key]
    if type(record) ~= "table" then
        record = {}
        db.vignetteRadarPanelLayout[key] = record
    end
    for field, value in pairs(fields) do record[field] = value end
    if addon.InvalidateSettings then addon.InvalidateSettings() end
end

-- True when the panel with this key (or this registered frame) is locked.
function Tray.IsPanelLocked(key)
    if panels[key] then key = panels[key].key end
    local record = Record(key)
    return record ~= nil and record.locked == true
end

function Tray.SetPanelLocked(key, value)
    if panels[key] then key = panels[key].key end
    WriteRecord(key, { locked = value == true })
    for button in pairs(lockButtons) do button:RefreshLock() end
end

function Tray.IsPanelDetached(frame)
    local spec = panels[frame]
    if not spec then return false end
    if spec.isDetached then return spec.isDetached() == true end
    local record = Record(spec.key)
    if record and type(record.detached) == "boolean" then return record.detached end
    return spec.detached == true
end

-- Trace lines for panel decisions (/vrtrace on, topic "panel").
local function Log(fmt, ...)
    local trace = addon.Trace
    if trace and trace.Log then trace.Log("panel", fmt, ...) end
end

-- The saved free spot as stored: the panel's own reader (spec.spot) when it
-- keeps one, else its layout record. false (a forgotten spot) reads as nil.
local function RawSpot(spec)
    local x, y
    if spec.spot then
        x, y = spec.spot()
    else
        local record = Record(spec.key)
        if record then x, y = record.x, record.y end
    end
    if x == false then x = nil end
    if y == false then y = nil end
    return x, y
end

local function Spot(spec)
    local x, y = RawSpot(spec)
    return Num(x), Num(y)
end

local function SaveSpot(spec, left, top)
    if spec.saveSpot then spec.saveSpot(left, top)
    else WriteRecord(spec.key, { x = left, y = top }) end
end

-- The frame's current top-left in saved-spot units, or nil.
local function CurrentSpot(frame)
    local left, _, top = Rect(frame)
    local _, screenH = Screen()
    if not (left and top and screenH) then return nil end
    return math.floor(left + .5), math.floor(top - screenH + .5)
end

-- On screen means a visible parent too: a shown panel under a hidden parent
-- (IsShown alone) is not on screen.
local function Visible(frame)
    if frame.IsVisible then return frame:IsVisible() == true end
    return frame:IsShown() == true
end

-- Free panels sit at their own strata (spec.strata, else MEDIUM) but never
-- below the strata they had docked, so leaving the dock never drops a panel
-- behind the radar or the window it stood over.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function FreeStrata(frame, spec)
    local wanted = spec.strata or "MEDIUM"
    local current = frame:GetFrameStrata()
    if (STRATA_RANK[current] or 0) > (STRATA_RANK[wanted] or 0) then return current end
    return wanted
end

-- Pins a free panel by its top-left to UIParent at left, top (saved-spot
-- units). A free panel is always UIParent's child: under the tray's clipped
-- slot or a hidden frame it would be cut off or hidden along with it.
local function Pin(frame, left, top)
    if frame:GetParent() ~= UIParent then frame:SetParent(UIParent) end
    local scale = Ratio(frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left / scale, top / scale)
end

local function PlaceFree(frame, spec, minWidth)
    local x, y = Spot(spec)
    local changed = not frame._vrFree or frame._freeX ~= x or frame._freeY ~= y
    if changed then
        frame._vrFree, frame._freeX, frame._freeY = true, x, y
        frame._dockAnchor, frame._dockBelow, frame._dockWidth, frame._dockShift = nil, nil, nil, nil
        local home = spec.home
        if x and y then
            Pin(frame, x, y)
        elseif type(home) == "table" then
            Pin(frame, home[1], home[2])
        else
            if frame:GetParent() ~= UIParent then frame:SetParent(UIParent) end
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, spec.homeY or -120)
        end
        frame:SetFrameStrata(FreeStrata(frame, spec))
        if not spec.keepWidth and minWidth then frame:SetWidth(minWidth) end
        Log("free %s at %s, %s", spec.key, x, y)
    end
    Tray.KeepOnScreen(frame)
    return changed
end

-- Safety net: a saved free spot must leave MIN_VISIBLE units of the panel
-- on screen each way. One off screen, or half missing, or not a number,
-- re-docks the panel instead, so a bad spot can never strand it.
local MIN_VISIBLE = 24
local function SpotProblem(frame, spec)
    local rawX, rawY = RawSpot(spec)
    if rawX == nil and rawY == nil then return nil end
    local x, y = Num(rawX), Num(rawY)
    if not (x and y) then return "invalid", rawX, rawY end
    local screenW, screenH = Screen()
    local scale = Ratio(frame)
    local width = math.max(MIN_VISIBLE, (Num(frame:GetWidth()) or 0) * scale)
    local height = math.max(MIN_VISIBLE, (Num(frame:GetHeight()) or 0) * scale)
    local top = screenH + y
    if x + width < MIN_VISIBLE or x > screenW - MIN_VISIBLE or top < MIN_VISIBLE
        or top - height > screenH - MIN_VISIBLE then
        return "off screen", x, y
    end
    return nil
end

local function Redock(frame, spec, why, x, y)
    Log("re-dock %s: saved spot %s, %s is %s", spec.key, x, y, why)
    if spec.saveSpot then spec.saveSpot(nil, nil) end
    WriteRecord(spec.key, { detached = false, x = false, y = false })
    frame._vrFree, frame._freeX, frame._freeY = nil, nil, nil
    if spec.redock then spec.redock() end
end

-- Runs once per panel per session, before it is first placed with a known
-- screen size: re-docks the panel when its saved spot is off screen or
-- invalid. Returns false when it re-docked.
function Tray.CheckPanelSpot(frame)
    local spec = panels[frame]
    if not spec or frame._vrSpotChecked then return true end
    local screenW, screenH = Screen()
    if not (screenW and screenH and screenW > 0 and screenH > 0) then return true end
    frame._vrSpotChecked = true
    local why, x, y = SpotProblem(frame, spec)
    if not why then return true end
    Redock(frame, spec, why, x, y)
    return false
end

-- The panel's saved free spot (x, y), or nil when it has none.
function Tray.GetPanelSpot(frame)
    local spec = panels[frame]
    if not spec then return nil end
    local x, y = Spot(spec)
    if x and y then return x, y end
    return nil
end

-- Saves where the panel stands now (moved by dx, dy UIParent units) as its
-- free spot.
function Tray.SavePanelSpot(frame, dx, dy)
    local spec = panels[frame]
    local left, top = CurrentSpot(frame)
    if not (spec and left) then return false end
    left, top = left + math.floor((Num(dx) or 0) + .5), top + math.floor((Num(dy) or 0) + .5)
    SaveSpot(spec, left, top)
    Log("save %s spot %s, %s", spec.key, left, top)
    return true
end

-- The registered panel just above frame in the docked stack, if shown.
local function PreviousDocked(frame)
    local mine, best, bestOrder = panels[frame].order or 0, nil, nil
    for other, spec in pairs(panels) do
        local order = spec.order or 0
        if other ~= frame and order < mine and other._dockAnchor and not other._vrFree
            and other:IsShown() and (not bestOrder or order > bestOrder) then
            best, bestOrder = other, order
        end
    end
    return best
end

-- True while the left button is down (true when the client can't say).
local function MouseHeld()
    if type(IsMouseButtonDown) ~= "function" then return true end
    local ok, down = pcall(IsMouseButtonDown, "LeftButton")
    return not ok or down == true
end

-- Ends a drag: back inside the screen, spot saved, re-anchored from it.
local function DragStop(frame)
    if not frame._vrMoving then return end
    frame._vrMoving = nil
    if frame.StopMovingOrSizing then pcall(frame.StopMovingOrSizing, frame) end
    -- StartMoving marks the frame user-placed; the spot is ours to keep, so
    -- the client's layout cache must never move the panel at the next login.
    if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
    frame._vrDraggedAt = type(GetTime) == "function" and GetTime() or nil
    Tray.KeepOnScreen(frame)
    local spec = panels[frame]
    local left, top = CurrentSpot(frame)
    if not left then left, top = frame._freeX, frame._freeY end
    if spec then Log("drag stop %s at %s, %s", spec.key, left, top) end
    if spec and left and top then
        SaveSpot(spec, left, top)
        -- Re-anchor from the saved spot, the same way a reload places it.
        frame._vrFree = nil
        PlaceFree(frame, spec)
    end
end

-- A drag the client never finished (no OnDragStop, the mouse is up) ends
-- here, so a panel is never stuck "moving" and skipped by every re-place.
-- True while the mouse still owns the panel.
local function StillDragging(frame)
    if not frame._vrMoving then return false end
    if MouseHeld() then return true end
    local spec = panels[frame]
    Log("drag %s ended without a drop", spec and spec.key)
    DragStop(frame)
    return false
end

-- Places a panel: free at its saved spot, or docked in the stack (after the
-- registered panel before it, else after `after`). A docked panel with
-- nothing to dock to floats when its spec says floatAlone. Returns like
-- DockPanel: placed, width, changed.
function Tray.PlacePanel(frame, gap, minWidth, after)
    local spec = panels[frame]
    if not spec then return Tray.DockPanel(frame, after, gap, minWidth) end
    -- Mid-drag the mouse owns the spot.
    if StillDragging(frame) then return true, Num(frame:GetWidth()) or minWidth or 0, false end
    Tray.CheckPanelSpot(frame)
    if not Tray.IsPanelDetached(frame) then
        -- A drawer panel docks in the radar's tray (Tray.Attach), not here.
        if spec.drawer then return false, Num(frame:GetWidth()) or minWidth or 0, false end
        if frame._vrFree then frame._vrFree, frame._freeX, frame._freeY = nil, nil, nil end
        local docked, width, changed = Tray.DockPanel(frame, PreviousDocked(frame) or after, gap, minWidth,
            spec.keepWidth)
        if docked or not spec.floatAlone then return docked, width, changed end
    end
    local changed = PlaceFree(frame, spec, minWidth)
    return true, Num(frame:GetWidth()) or minWidth or 0, changed
end

-- A drawer panel (spec.drawer: docked means the radar's tray) set free: out
-- of the tray and at its saved spot, kept on screen. True when it moved.
function Tray.PlaceFreePanel(frame, minWidth)
    local spec = panels[frame]
    if not spec or StillDragging(frame) then return false end
    if owner and owner.frame == frame then Tray.Detach(frame) end
    return PlaceFree(frame, spec, minWidth)
end

-- After a free panel changes size: back inside the screen.
function Tray.SettlePanel(frame)
    if frame and frame._vrFree and not frame._vrMoving then Tray.KeepOnScreen(frame) end
end

-- A click that ends a drag is not a click.
function Tray.JustDragged(frame)
    local at = frame and frame._vrDraggedAt
    return at ~= nil and type(GetTime) == "function" and GetTime() - at < .3
end

local function PanelChanged(frame)
    local spec = panels[frame]
    frame._dockAnchor, frame._vrFree = nil, nil
    if spec and spec.refresh then spec.refresh() end
    local bar = frame.vrPanelBar
    if bar then
        bar.detach:RefreshDetach()
        bar.lock:RefreshLock()
    end
end

-- Detach leaves the panel where it is; dock puts it back in the stack.
function Tray.SetPanelDetached(frame, value)
    local spec = panels[frame]
    if not spec then return end
    value = value == true
    if value then
        local left, top = CurrentSpot(frame)
        if left then SaveSpot(spec, left, top) end
    end
    if spec.setDetached then spec.setDetached(value)
    else WriteRecord(spec.key, { detached = value }) end
    Log("%s %s", value and "detach" or "dock", spec.key)
    PanelChanged(frame)
end

-- Forgets the saved free spot: the panel goes back to its home spot.
function Tray.ResetPanel(frame)
    local spec = panels[frame]
    if not spec then return end
    if spec.saveSpot then spec.saveSpot(nil, nil) else WriteRecord(spec.key, { x = false, y = false }) end
    -- Move it now, even while it is hidden.
    frame._vrFree = nil
    if Tray.IsPanelDetached(frame) then PlaceFree(frame, spec) end
    PanelChanged(frame)
end

-- Puts every panel back in the docked stack (drawer panels back in the
-- tray) and forgets the free spots (/vr panels): the way back when a panel
-- ends up somewhere you can't reach.
function Tray.ResetAllPanels()
    local db = Settings()
    db.vignetteRadarPanelLayout = {}
    if addon.InvalidateSettings then addon.InvalidateSettings() end
    Log("reset all panels")
    for frame, spec in pairs(panels) do
        if frame._vrMoving then
            frame._vrMoving = nil
            if frame.StopMovingOrSizing then pcall(frame.StopMovingOrSizing, frame) end
        end
        if spec.saveSpot then spec.saveSpot(nil, nil) end
        if spec.redock then spec.redock() end
        PanelChanged(frame)
    end
end

-- Starting a drag unhooks the panel in place. In the real client:
--  * StartMoving on a frame anchored to another region (the radar face, a
--    texture inside a scaled frame) can jump or keep following that anchor,
--    so the panel is pinned to UIParent at the exact spot it stands first;
--  * a panel parented to a clipped or hidden frame would be cut off or
--    vanish as it leaves, so Pin makes UIParent its parent;
--  * its free strata is set now, not at the drop, so it never slips behind
--    the radar or another window mid-drag, and it is raised in its strata;
--  * _vrMoving is set before anything that could refresh the panel (the
--    settings write below, a ticker), so nothing re-places it mid-drag.
local function DragStart(frame)
    local spec = panels[frame]
    if not spec or frame._vrMoving then return end
    if Tray.IsPanelLocked(spec.key) or (spec.canDrag and not spec.canDrag()) then return end
    if not Visible(frame) then
        Log("drag %s refused: not on screen", spec.key)
        return
    end
    local left, top = CurrentSpot(frame)
    if not left then
        Log("drag %s refused: no position yet", spec.key)
        return
    end
    frame._vrMoving = true
    local wasDocked = not Tray.IsPanelDetached(frame)
    frame._dockAnchor, frame._dockBelow, frame._dockWidth, frame._dockShift = nil, nil, nil, nil
    frame._vrFree, frame._freeX, frame._freeY = true, left, top
    Pin(frame, left, top)
    frame:SetFrameStrata(FreeStrata(frame, spec))
    if frame.Raise then frame:Raise() end
    -- A see-through panel would look like it vanished on the way.
    local alpha = frame.GetAlpha and Num(frame:GetAlpha())
    if alpha and alpha < .05 then frame:SetAlpha(1) end
    SaveSpot(spec, left, top)
    if wasDocked then
        if spec.setDetached then spec.setDetached(true) else WriteRecord(spec.key, { detached = true }) end
        if frame.vrPanelBar then frame.vrPanelBar.detach:RefreshDetach() end
    end
    Log("drag start %s at %s, %s%s", spec.key, left, top, wasDocked and " (was docked)" or "")
    local ok, problem = pcall(frame.StartMoving, frame)
    if not ok then
        frame._vrMoving = nil
        Log("drag %s failed: %s", spec.key, problem)
    end
end

-- The hover controls: detach/dock and lock icons on whichever side of the
-- panel has room, shown while the mouse is over the panel or them.
local BAR_ICON = 18
local function PlaceBar(frame, bar)
    local _, right = Rect(frame)
    local screenW = Screen()
    local left = right and screenW and right + 2 * BAR_ICON + 6 > screenW - MARGIN
    if bar._left == left then return end
    bar._left = left
    bar:ClearAllPoints()
    if left then bar:SetPoint("TOPRIGHT", frame, "TOPLEFT", -2, 0)
    else bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0) end
end

local function BarUpdate(bar, delta)
    bar._wait = (bar._wait or 0) + delta
    if bar._wait < .1 then return end
    local frame = bar:GetParent()
    local over = type(MouseIsOver) == "function" and frame:IsShown()
        and (MouseIsOver(frame) or MouseIsOver(bar))
    bar._out = over and 0 or (bar._out or 0) + bar._wait
    bar._wait = 0
    -- A short grace period lets the mouse cross the gap to the icons.
    if bar._out >= .6 then bar:Hide() end
end

local function ShowBar(frame)
    local bar = frame.vrPanelBar
    if not bar then return end
    PlaceBar(frame, bar)
    bar._out, bar._wait = 0, 0
    bar:SetFrameStrata(frame:GetFrameStrata())
    bar:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    bar.detach:RefreshDetach()
    bar.lock:RefreshLock()
    if not bar:IsShown() then bar:Show() end
end
Tray.ShowPanelControls = ShowBar

local function Controls(frame, spec)
    local icons = addon.VignetteRadarIconButton
    if not (icons and icons.Create) then return end
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetSize(BAR_ICON, 2 * BAR_ICON + 2)
    bar.detach = Tray.CreateDetachButton(bar, function() return Tray.IsPanelDetached(frame) end,
        function() Tray.SetPanelDetached(frame, not Tray.IsPanelDetached(frame)) end, {
            size = BAR_ICON, labels = { "Detach", "Dock To Radar" },
            tips = { "Make " .. (spec.label or "this panel") .. " a free panel. Or drag it anywhere.",
                "Put " .. (spec.label or "this panel") .. " back under the radar." } })
    bar.detach:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.lock = Tray.CreateLockButton(bar, {
        size = BAR_ICON, labels = { "Unlocked", "Locked" },
        isLocked = function() return Tray.IsPanelLocked(spec.key) end,
        setLocked = function(value) Tray.SetPanelLocked(spec.key, value) end,
        tips = { "Drag to move it. Lock to stop it moving.", "Unlock to drag it again." } })
    bar.lock:SetPoint("TOP", bar.detach, "BOTTOM", 0, -2)
    bar:SetScript("OnUpdate", BarUpdate)
    bar:Hide()
    frame.vrPanelBar = bar
end

-- A panel that kept its free spot in its own setting before the shared
-- system (spec.legacySpot = that key, { x, y } in UIParent units from the
-- screen's top-left) moves it into its layout record once.
local function MigrateSpot(spec)
    local key = spec.legacySpot
    if not key or spec.spot then return end
    local db = Settings()
    local old = db[key]
    if old == nil then return end
    local record = Record(spec.key)
    local x, y = type(old) == "table" and Num(old.x), type(old) == "table" and Num(old.y)
    if x and y and not (record and Num(record.x) and Num(record.y)) then
        WriteRecord(spec.key, { x = math.floor(x + .5), y = math.floor(y + .5) })
        Log("moved %s spot from %s: %s, %s", spec.key, key, x, y)
    end
    db[key] = nil
end

-- spec: key (layout record), label ("the strip", for tooltips), order (place
-- in the docked stack), regions (child frames that also start a drag and
-- show the controls), detached (default when nothing is saved), floatAlone
-- (float instead of hiding when there is nothing to dock to), keepWidth,
-- strata and homeY or home = { x, y } (free placement), spot() /
-- saveSpot(left, top) (a panel that keeps its own saved spot), canDrag(),
-- refresh() (re-place now).
-- Drawer panels (the Quest Tracker, the Legend) dock in the radar's tray
-- instead of the stack: drawer = true, isDetached() / setDetached(value)
-- (their own setting decides), redock() (back to the tray, for the safety
-- net and /vr panels), legacySpot (old saved-spot key to migrate) and
-- ownControls = true (their header already has detach and lock icons, so no
-- hover bar). Their module docks them; Tray.PlaceFreePanel sets them free.
function Tray.RegisterPanel(frame, spec)
    if not (frame and type(spec) == "table" and spec.key) or panels[frame] then return end
    panels[frame] = spec
    MigrateSpot(spec)
    frame:SetMovable(true)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    -- A spot the client's layout cache kept from an older build would move
    -- the panel at login; the saved spot here is the only one.
    if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
    if not spec.ownControls then Controls(frame, spec) end
    local regions = { frame }
    for _, region in ipairs(spec.regions or {}) do regions[#regions + 1] = region end
    for _, region in ipairs(regions) do
        if region.EnableMouse and region ~= frame then region:EnableMouse(true) end
        region:RegisterForDrag("LeftButton")
        region:SetScript("OnDragStart", function() DragStart(frame) end)
        region:SetScript("OnDragStop", function() DragStop(frame) end)
        if region.HookScript then region:HookScript("OnEnter", function() ShowBar(frame) end) end
    end
    -- Hidden mid-drag (the client skips OnDragStop then): end the drag, so
    -- the panel is not left "moving" and skipped by every re-place.
    if frame.HookScript then
        frame:HookScript("OnHide", function()
            if frame._vrMoving then
                Log("drag %s ended: hidden", spec.key)
                DragStop(frame)
            end
        end)
    end
end

function Tray.IsPanel(frame) return panels[frame] ~= nil end

-- A new UI scale or screen size: every panel re-places itself (a panel
-- mid-drag finishes its drag first).
local function RefitPanels()
    for frame, spec in pairs(panels) do
        if not frame._vrMoving then
            frame._dockAnchor, frame._vrFree = nil, nil
            if frame:IsShown() and spec.refresh then spec.refresh() end
        end
    end
end
Tray.RefitPanels = RefitPanels

-- Round radar ----------------------------------------------------------------
-- True when the radar's face is a circle (the round plot, not the rounded
-- square), so a docked tray can curve around it.
function Tray.FaceIsRound()
    local radar = addon.VignetteRadarAPI
    local panel = radar and radar.GetPanel and radar.GetPanel()
    return panel ~= nil and panel.squarePlot == false and Face() ~= nil
end

-- For a tray docked left or right of a round face: how far the circle's
-- edge sits back from its bounding box beside the content rows top..bottom
-- (content units from the content's top), taken at the rows' point nearest
-- the face's middle, so text placed past it never runs under the circle.
-- nil while no tray is placed.
function Tray.ArcGap(top, bottom)
    local face, host = Face()
    if not (face and host and owner and slot and slot._side) then return nil end
    local fit = slot._fit or 1
    local scale = Ratio(face, host)
    local height = Num(face:GetHeight())
    if not (height and height > 0 and fit > 0) then return nil end
    local radius = height * scale / 2
    local scroll = owner._scroll or 0
    local a, b = TOP_OFFSET + top * fit - scroll, TOP_OFFSET + bottom * fit - scroll
    local near = 0
    if b < radius then near = radius - b elseif a > radius then near = a - radius end
    if near >= radius then return radius / fit end
    return (radius - math.sqrt(radius * radius - near * near)) / fit
end

-- Other buttons that open or close the tray, such as the radar's tracker
-- corner tool. Their clicks must not also count as a click away.
local toggles = {}
function Tray.RegisterToggle(button) if button then toggles[button] = true end end

local function ClickedInside()
    if slot and slot:IsShown() and MouseIsOver(slot) then return true end
    if handle and handle:IsShown() and MouseIsOver(handle) then return true end
    for button in pairs(toggles) do
        if button:IsShown() and MouseIsOver(button) then return true end
    end
    return owner and owner.keepOpen and owner.keepOpen() or false
end

events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("GLOBAL_MOUSE_DOWN")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        -- UIParent takes its new size a frame later.
        if C_Timer and C_Timer.After then C_Timer.After(0, RefitPanels) else RefitPanels() end
        return
    end
    if not owner or target ~= 1 or IsLocked() then return end
    if event == "GLOBAL_MOUSE_DOWN" and ClickedInside() then return end
    Tray.Retract()
end)
