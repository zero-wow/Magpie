local _, addon = ...
if type(addon) ~= "table" then return end

local Controls = {}
addon.VignetteRadarControls = Controls
local ACCENT = { 0.05, 0.82, 0.62 }
local controls = {}
local TITLE_SPECIAL = { cpu = "CPU", ui = "UI", poi = "POI", pois = "POIs",
    wow = "WoW", zygor = "Zygor", yd = "yd", sec = "sec", px = "px" }
-- Theme state the control loop last painted; RefreshTheme skips repaints that would change nothing.
local themed = { revision = nil, count = 0 }
local POPUP_FACE = "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga"
local POPUP_EDGE = "Interface\\AddOns\\Magpie\\Media\\radar-rounded-border.tga"

function Controls.TitleCase(value)
    if type(value) ~= "string" then return value end
    return (value:gsub("[%a][%a']*", function(word)
        local lower = word:lower()
        return TITLE_SPECIAL[lower] or (lower:sub(1, 1):upper() .. lower:sub(2))
    end))
end

function Controls.RefreshPopupSurface(frame)
    if not (frame and frame.popupFace) then return end
    local style = addon.VignetteRadarStyle
    local br, bg, bb = .025, .032, .038
    local ar, ag, ab = ACCENT[1], ACCENT[2], ACCENT[3]
    if style then
        br, bg, bb = style.Color("background")
        ar, ag, ab = style.Color("accent")
    end
    for _, face in ipairs(frame.popupFaceSlices or { frame.popupFace }) do
        face:SetVertexColor(math.min(.14, br * 2.7), math.min(.14, bg * 2.7),
            math.min(.14, bb * 2.7), .99)
    end
    for _, edge in ipairs(frame.popupEdgeSlices or { frame.popupEdge }) do
        edge:SetVertexColor(ar, ag, ab, .40)
    end
    if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(0, 0, 0, 0) end
end

-- Nine textures that stretch the rounded radar art without stretching its
-- corners: fixed corner squares, stretched edges and a stretched center.
local function NineSlice(frame, path, layer, corner, cut)
    local slices, uv = {}, { 0, cut, 1 - cut, 1 }
    for row = 1, 3 do
        for column = 1, 3 do
            local texture = frame:CreateTexture(nil, layer)
            texture:SetTexture(path)
            texture:SetTexCoord(uv[column], uv[column + 1], uv[row], uv[row + 1])
            if column == 1 then
                texture:SetPoint("LEFT", frame, "LEFT", 0, 0)
                texture:SetWidth(corner)
            elseif column == 2 then
                texture:SetPoint("LEFT", frame, "LEFT", corner, 0)
                texture:SetPoint("RIGHT", frame, "RIGHT", -corner, 0)
            else
                texture:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
                texture:SetWidth(corner)
            end
            if row == 1 then
                texture:SetPoint("TOP", frame, "TOP", 0, 0)
                texture:SetHeight(corner)
            elseif row == 2 then
                texture:SetPoint("TOP", frame, "TOP", 0, -corner)
                texture:SetPoint("BOTTOM", frame, "BOTTOM", 0, corner)
            else
                texture:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
                texture:SetHeight(corner)
            end
            slices[#slices + 1] = texture
        end
    end
    return slices
end

function Controls.PopupSurface(frame)
    if frame.popupFace then return end
    -- Keep the corner radius near six UI units on every popup size. Stretching
    -- the whole square asset made large settings windows excessively round.
    frame.popupFaceSlices = NineSlice(frame, POPUP_FACE, "BACKGROUND", 6, 11 / 256)
    frame.popupEdgeSlices = NineSlice(frame, POPUP_EDGE, "BORDER", 6, 11 / 256)
    frame.popupFace, frame.popupEdge = frame.popupFaceSlices[1], frame.popupEdgeSlices[1]
    Controls.RefreshPopupSurface(frame)
end

-- Keep the small corner radius circular when a status block is much wider
-- than it is tall; stretching the full square artwork distorts its corners.
function Controls.RoundedStatusSurface(frame)
    if frame.statusSurface then return end
    frame.statusSurface = { face = NineSlice(frame, POPUP_FACE, "BACKGROUND", 8, 8 / 256),
        edge = NineSlice(frame, POPUP_EDGE, "BORDER", 8, 8 / 256) }
    Controls.RefreshRoundedStatusSurface(frame)
end

function Controls.RefreshRoundedStatusSurface(frame)
    if not (frame and frame.statusSurface) then return end
    local style = addon.VignetteRadarStyle
    local br, bg, bb, ar, ag, ab = .025, .032, .038, ACCENT[1], ACCENT[2], ACCENT[3]
    if style then
        br, bg, bb = style.Color("background")
        ar, ag, ab = style.Color("accent")
    end
    for _, texture in ipairs(frame.statusSurface.face) do
        texture:SetVertexColor(math.min(.14, br * 2.7), math.min(.14, bg * 2.7),
            math.min(.14, bb * 2.7), .97)
    end
    for _, texture in ipairs(frame.statusSurface.edge) do
        texture:SetVertexColor(ar, ag, ab, .64)
    end
end

function Controls.RefreshTheme()
    local style = addon.VignetteRadarStyle
    local r, g, b = ACCENT[1], ACCENT[2], ACCENT[3]
    if style then
        ACCENT[1], ACCENT[2], ACCENT[3] = style.Color("accent")
    end
    -- Profile swaps can change the accent without bumping Style.revision, so
    -- the accent and control count are part of the "nothing changed" check.
    local revision = style and style.revision
    if themed.revision == revision and themed.count == #controls
        and r == ACCENT[1] and g == ACCENT[2] and b == ACCENT[3] then
        return
    end
    themed.revision, themed.count = revision, #controls
    for _, control in ipairs(controls) do
        if control.RefreshAppearance then control:RefreshAppearance() end
    end
end

-- Quiet, flat controls match the unboxed glyphs on the radar. A one-pixel
-- underline carries selection; wide buttons never stretch a rounded sprite.
function Controls.Button(parent, title, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.face = button:CreateTexture(nil, "BACKGROUND")
    button.face:SetAllPoints(button)
    button.face:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.edge = button:CreateTexture(nil, "ARTWORK")
    button.edge:SetHeight(1)
    button.edge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
    button.edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.label = button:CreateFontString(nil, "OVERLAY")
    button.fitsLabel = true
    -- The label has no fixed width, so the client never cuts it with "...".
    -- FitButtonLabel picks the largest readable size that fits the button;
    -- rows size buttons from their measured labels (Controls.FlowButtons).
    button.label:SetJustifyH("CENTER")
    button.label:SetWordWrap(false)
    button:SetFontString(button.label)
    local nativeSetText = button.SetText
    button.SetText = function(self, text)
        nativeSetText(self, text)
        Controls.FitButtonLabel(self)
    end
    button:SetText(title)

    button.selection = button:CreateTexture(nil, "ARTWORK")
    button.selection:SetSize(math.max(1, width - 12), 2)
    button.selection:SetPoint("BOTTOM", 0, 1)
    button.selection:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
    button._enabled = true

    local function Refresh()
        local enabled = button._enabled
        local selected = button._selected
        local hovered = enabled and button._hovered
        local pressed = enabled and button._pressed
        button:SetAlpha(enabled and 1 or 0.38)
        button.label:ClearAllPoints()
        button.label:SetPoint("CENTER", 0, 0)
        button.selection:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], .8)
        button.selection:SetShown(enabled and selected == true)
        if pressed then
            button.face:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .24)
            button.edge:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .75)
            button.label:SetTextColor(0.95, 1, 0.98, 1)
        elseif hovered or selected then
            button.face:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], hovered and .14 or .08)
            button.edge:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], hovered and .50 or .32)
            button.label:SetTextColor(hovered and 0.86 or ACCENT[1], hovered and 1 or ACCENT[2],
                hovered and 0.95 or ACCENT[3], 1)
        else
            button.face:SetVertexColor(.13, .17, .19, .24)
            button.edge:SetVertexColor(.60, .70, .70, .10)
            button.label:SetTextColor(.76, .83, .82, 1)
        end
    end
    button.RefreshAppearance = Refresh

    -- Preserve native enabled/selected semantics used by Settings range choices.
    local setEnabled, lockHighlight, unlockHighlight = button.SetEnabled, button.LockHighlight, button.UnlockHighlight
    button.SetEnabled = function(self, enabled)
        enabled = enabled == true or enabled == 1
        if self._enabled == enabled then return end
        setEnabled(self, enabled)
        self._enabled = enabled
        if not enabled then self._hovered, self._pressed = false, false end
        Refresh()
    end
    button.LockHighlight = function(self)
        lockHighlight(self)
        self._selected = true
        Refresh()
    end
    button.UnlockHighlight = function(self)
        unlockHighlight(self)
        self._selected = false
        Refresh()
    end
    button:SetScript("OnEnter", function(self) self._hovered = true; Refresh() end)
    button:SetScript("OnLeave", function(self) self._hovered, self._pressed = false, false; Refresh() end)
    button:SetScript("OnMouseDown", function(self) self._pressed = true; Refresh() end)
    button:SetScript("OnMouseUp", function(self) self._pressed = false; Refresh() end)
    button:SetScript("OnHide", function(self) self._hovered, self._pressed = false, false; Refresh() end)
    Refresh()
    controls[#controls + 1] = button
    return button
end

-- Room a button label needs on each side, so text never touches the edge.
local BUTTON_PAD = 12

-- The largest readable size (down to Style.MIN_TEXT) whose text fits the
-- button. Short glyph captions on small buttons start large.
function Controls.FitButtonLabel(button)
    local label, style = button.label, addon.VignetteRadarStyle
    if not (label and style) then return end
    local width = button.GetWidth and button:GetWidth() or button.width or 0
    local text = tostring(label.GetText and label:GetText() or button.GetText and button:GetText() or "")
    local start = (width <= 48 and #text <= 3) and 14 or style.type.label
    for size = start, style.MIN_TEXT, -1 do
        style.SetFont(label, size, "")
        if style.TextWidth(label) <= width - 10 then break end
    end
end

-- The width a button needs to show its whole label at the label size.
function Controls.ButtonWidth(button)
    local style = addon.VignetteRadarStyle
    style.SetFont(button.label, style.type.label, "")
    return math.ceil(style.TextWidth(button.label)) + BUTTON_PAD
end

-- Resizes a button and keeps its selection underline inset 6px each side.
function Controls.SizeButton(button, width, height)
    button:SetSize(width, height or button:GetHeight())
    if button.selection then button.selection:SetSize(math.max(1, width - 12), 2) end
    Controls.FitButtonLabel(button)
end

-- Lays buttons left to right from (x, y) inside width. Each button gets at
-- least its measured label width. A line uses equal widths when the widest
-- label allows it, otherwise it shares the spare room evenly. Buttons that
-- cannot share one line wrap onto balanced lines. Returns the line count.
function Controls.FlowButtons(parent, buttons, x, y, width, gap, height, pitch)
    gap, height = gap or 4, height or 21
    pitch = pitch or (height + 4)
    local count = #buttons
    if count == 0 then return 0 end
    local need = {}
    for index, button in ipairs(buttons) do need[index] = Controls.ButtonWidth(button) end
    local function Fits(first, last)
        local sum = gap * (last - first)
        for index = first, last do sum = sum + need[index] end
        return sum <= width
    end
    local perLine = count
    for lines = 1, count do
        perLine = math.ceil(count / lines)
        local fits = true
        for first = 1, count, perLine do
            if not Fits(first, math.min(count, first + perLine - 1)) then fits = false; break end
        end
        if fits then break end
    end
    local line = 0
    for first = 1, count, perLine do
        local last = math.min(count, first + perLine - 1)
        local shown = last - first + 1
        local free = width - gap * (shown - 1)
        local widest, total = 0, 0
        for index = first, last do widest, total = math.max(widest, need[index]), total + need[index] end
        local equal = widest * shown <= free and math.floor(free / shown)
        local share = math.floor(math.max(0, free - total) / shown)
        local left = x
        for index = first, last do
            local each = math.min(free, equal or (need[index] + share))
            local button = buttons[index]
            Controls.SizeButton(button, each, height)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", parent, "TOPLEFT", left, y - line * pitch)
            left = left + each + gap
        end
        line = line + 1
    end
    return line
end

-- The small, unboxed toolbar language used by the radar also fits range
-- steppers in both settings panels. The hit target stays larger than the glyph.
function Controls.IconButton(parent, symbol, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetText(symbol)
    button.glow = button:CreateTexture(nil, "BACKGROUND")
    button.glow:SetSize(18, 18)
    button.glow:SetPoint("CENTER")
    button.glow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    button.strokes = {}
    local horizontal = button:CreateLine(nil, "OVERLAY")
    horizontal:SetThickness(2)
    horizontal:SetStartPoint("CENTER", button, -5, 0)
    horizontal:SetEndPoint("CENTER", button, 5, 0)
    button.strokes[1] = horizontal
    if symbol == "+" then
        local vertical = button:CreateLine(nil, "OVERLAY")
        vertical:SetThickness(2)
        vertical:SetStartPoint("CENTER", button, 0, -5)
        vertical:SetEndPoint("CENTER", button, 0, 5)
        button.strokes[2] = vertical
    end
    button._enabled = true
    function button:RefreshAppearance()
        local selected, hovered = self._selected == true, self._hovered == true
        local r, g, b = .69, .77, .78
        if selected or hovered then r, g, b = ACCENT[1], ACCENT[2], ACCENT[3] end
        local opacity = not self._enabled and .32 or (selected or hovered) and 1 or .78
        self.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3],
            not self._enabled and 0 or hovered and .20 or selected and .12 or 0)
        for _, stroke in ipairs(self.strokes) do stroke:SetColorTexture(r, g, b, opacity) end
    end
    local nativeSetEnabled = button.SetEnabled
    button.SetEnabled = function(self, enabled)
        enabled = enabled == true or enabled == 1
        nativeSetEnabled(self, enabled)
        self._enabled = enabled
        if not enabled then self._hovered = false end
        self:RefreshAppearance()
    end
    button:SetScript("OnEnter", function(self) self._hovered = true; self:RefreshAppearance() end)
    button:SetScript("OnLeave", function(self) self._hovered = false; self:RefreshAppearance() end)
    button:SetScript("OnHide", function(self) self._hovered = false; self:RefreshAppearance() end)
    button:RefreshAppearance()
    controls[#controls + 1] = button
    return button
end

function Controls.Checkbox(parent)
    local checkbox = CreateFrame("CheckButton", nil, parent)
    checkbox:SetSize(26, 26)
    checkbox.visual = CreateFrame("Frame", nil, checkbox, "BackdropTemplate")
    checkbox.visual:SetSize(17, 17)
    checkbox.visual:SetPoint("CENTER")
    checkbox.visual:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    checkbox.mark = {}
    local segments = {
        { -5, 0, -1, -4 },
        { -1, -4, 6, 4 },
    }
    for index, segment in ipairs(segments) do
        local line = checkbox.visual:CreateLine(nil, "OVERLAY")
        line:SetThickness(2)
        line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        line:SetStartPoint("CENTER", checkbox.visual, segment[1], segment[2])
        line:SetEndPoint("CENTER", checkbox.visual, segment[3], segment[4])
        checkbox.mark[index] = line
    end
    function checkbox:RefreshAppearance()
        local checked = self:GetChecked() == true or self:GetChecked() == 1
        local hovered = self._hovered == true
        local pressed = self._pressed == true
        for _, line in ipairs(self.mark) do line:SetShown(checked and not self.glyph) end
        if self.glyph then
            local r, g, b = checked and ACCENT[1] or 0.69,
                checked and ACCENT[2] or 0.77, checked and ACCENT[3] or 0.78
            for _, line in ipairs(self.glyph.lines or {}) do line:SetColorTexture(r, g, b, 1) end
            if self.glyph.label then self.glyph.label:SetTextColor(r, g, b, 1) end
            if self.glyph.pupil then self.glyph.pupil:SetVertexColor(r, g, b, 1) end
        end
        if checked then
            self.visual:SetBackdropColor(ACCENT[1] * .18,
                ACCENT[2] * .18, ACCENT[3] * .18, .94)
            self.visual:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3],
                pressed and 1 or hovered and .98 or .82)
        else
            self.visual:SetBackdropColor(.025, .033, .039, .88)
            self.visual:SetBackdropBorderColor(hovered and ACCENT[1] or .48,
                hovered and ACCENT[2] or .55, hovered and ACCENT[3] or .57,
                hovered and .78 or .48)
        end
        for _, line in ipairs(self.mark) do
            line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        end
        if self.label then
            self.label:SetTextColor(checked and 0.90 or (hovered and 0.95 or 0.82),
                checked and 1 or (hovered and 1 or 0.88),
                checked and 0.94 or (hovered and 0.96 or 0.88), 1)
        end
    end
    function checkbox:SetGlyph(symbol)
        if self.glyph then return end
        self.glyph = { lines = {} }
        if symbol == "N" then
            local label = self.visual:CreateFontString(nil, "OVERLAY")
            addon.VignetteRadarStyle.SetFont(label, 14, "")
            label:SetAllPoints(self.visual)
            label:SetJustifyH("CENTER")
            label:SetText("N")
            self.glyph.label = label
        elseif symbol == "eye" then
            for _, points in ipairs({
                { -7, 0, 0, 4 }, { 0, 4, 7, 0 }, { -7, 0, 0, -4 }, { 0, -4, 7, 0 },
            }) do
                local line = self.visual:CreateLine(nil, "OVERLAY")
                line:SetThickness(1.7)
                line:SetStartPoint("CENTER", self.visual, points[1], points[2])
                line:SetEndPoint("CENTER", self.visual, points[3], points[4])
                self.glyph.lines[#self.glyph.lines + 1] = line
            end
            local pupil = self.visual:CreateTexture(nil, "OVERLAY")
            pupil:SetSize(3, 3)
            pupil:SetPoint("CENTER")
            pupil:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            self.glyph.pupil = pupil
        end
        self:RefreshAppearance()
    end
    local nativeSetChecked = checkbox.SetChecked
    checkbox.SetChecked = function(self, checked)
        nativeSetChecked(self, checked == true or checked == 1)
        self:RefreshAppearance()
    end
    checkbox:SetScript("OnEnter", function(self) self._hovered = true; self:RefreshAppearance() end)
    checkbox:SetScript("OnLeave", function(self)
        self._hovered, self._pressed = false, false
        self:RefreshAppearance()
    end)
    checkbox:SetScript("OnMouseDown", function(self) self._pressed = true; self:RefreshAppearance() end)
    checkbox:SetScript("OnMouseUp", function(self) self._pressed = false; self:RefreshAppearance() end)
    checkbox:SetScript("OnHide", function(self)
        self._hovered, self._pressed = false, false
        self:RefreshAppearance()
    end)
    checkbox:RefreshAppearance()
    controls[#controls + 1] = checkbox
    return checkbox
end

-- Schema-driven widget kit. Each row is a frame of a fixed width that reads
-- its value through addon.Schema.Get and writes through addon.Schema.Set, so
-- every row applies live and validates the same way. Rows expose Refresh()
-- and a searchText; the settings window lays them out inside Section cards.
local LABEL = { .81, .87, .86 }
local ROW = 26

function Controls.Label(parent, value, size, width)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size or "body", "")
    label:SetTextColor(LABEL[1], LABEL[2], LABEL[3], 1)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    if width then label:SetWidth(width) end
    label:SetText(value)
    return label
end

local function Current(spec)
    local schema = addon.Schema
    if schema then return schema.Get(spec.key, spec.subkey) end
end

local function Apply(row, value)
    local schema = addon.Schema
    if not schema then return false end
    local ok, reason = schema.Set(row.entry.key, value, row.entry.subkey)
    if row.onApply then row.onApply(row, ok, reason) end
    return ok, reason
end

local function ShowTooltip(owner, spec)
    if not (GameTooltip and spec and spec.label) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(spec.label, 1, 1, 1)
    if spec.tooltip then GameTooltip:AddLine(spec.tooltip, .65, .78, .75, true) end
    GameTooltip:Show()
end
local function HideTooltip() if GameTooltip then GameTooltip:Hide() end end
Controls.ShowTooltip, Controls.HideTooltip = ShowTooltip, HideTooltip

local function NewRow(parent, spec, width, height, kind)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    row.isRow, row.kind, row.entry = true, kind, spec
    row.searchText = spec and table.concat({ spec.label or "", spec.tooltip or "",
        spec.key or "", spec.subkey and tostring(spec.subkey) or "" }, " "):lower() or ""
    return row
end

-- Label on the left, the radar-style checkbox on the right; the label is a
-- hit area too, so the whole line toggles.
function Controls.ToggleRow(parent, spec, width)
    local row = NewRow(parent, spec, width, ROW, "toggle")
    local box = Controls.Checkbox(row)
    box:SetPoint("TOPLEFT", row, "TOPLEFT", width - 34, 0)
    local hit = CreateFrame("Button", nil, row)
    hit:SetPoint("TOPLEFT", row, "TOPLEFT", 8, 0)
    hit:SetSize(width - 46, ROW)
    box.label = Controls.Label(hit, spec.label, "body", width - 50)
    box.label:SetPoint("TOPLEFT", hit, "TOPLEFT", 4, -7)
    box.optionKey, box.subkey = spec.key, spec.subkey
    if spec.glyph then box:SetGlyph(spec.glyph) end
    local function Checked() return box:GetChecked() == true or box:GetChecked() == 1 end
    box:SetScript("OnClick", function() Apply(row, Checked()) end)
    hit:SetScript("OnClick", function()
        box:SetChecked(not Checked())
        Apply(row, Checked())
    end)
    hit:SetScript("OnEnter", function(self)
        box._hovered = true
        box:RefreshAppearance()
        ShowTooltip(self, spec)
    end)
    hit:SetScript("OnLeave", function()
        box._hovered = false
        box:RefreshAppearance()
        HideTooltip()
    end)
    row.check, row.hit = box, hit
    function row:Refresh() box:SetChecked(Current(spec) == true) end
    return row
end

local function StepValue(values, current, direction)
    if type(current) ~= "number" then return values[1] end
    if direction > 0 then
        for _, value in ipairs(values) do
            if value > current + .0001 then return value end
        end
    else
        for index = #values, 1, -1 do
            if values[index] < current - .0001 then return values[index] end
        end
    end
end

local function StepValues(spec)
    local values, labels = {}, {}
    local choices = addon.Schema and addon.Schema.Choices(spec) or {}
    if #choices > 0 then
        for index, choice in ipairs(choices) do values[index], labels[choice[1]] = choice[1], choice[2] end
    elseif spec.min and spec.max and spec.step then
        for value = spec.min, spec.max + spec.step / 2, spec.step do values[#values + 1] = value end
    end
    return values, labels
end

-- Label, then [-] value [+] at the right edge.
function Controls.StepperRow(parent, spec, width)
    local row = NewRow(parent, spec, width, ROW, "stepper")
    row.label = Controls.Label(row, spec.label, "body", width - 150)
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -7)
    local function Step(direction)
        local values = StepValues(spec)
        local value = StepValue(values, Current(spec), direction)
        if value ~= nil then Apply(row, value) end
    end
    row.minus = Controls.IconButton(row, "−", 27, 21)
    row.minus:SetPoint("TOPLEFT", row, "TOPLEFT", width - 130, -2)
    row.minus:SetScript("OnClick", function() Step(-1) end)
    -- No fixed width: the value centers between [-] and [+] and is never cut.
    row.value = Controls.Label(row, "", "body")
    row.value:SetPoint("TOP", row, "TOPLEFT", width - 69, -7)
    row.value:SetJustifyH("CENTER")
    row.plus = Controls.IconButton(row, "+", 27, 21)
    row.plus:SetPoint("TOPLEFT", row, "TOPLEFT", width - 35, -2)
    row.plus:SetScript("OnClick", function() Step(1) end)
    row.minus.optionKey, row.plus.optionKey = spec.key, spec.key
    function row:Refresh()
        local values, labels = StepValues(spec)
        local value = Current(spec)
        local shown = labels[value]
        if not shown and type(value) == "number" then
            shown = spec.format and spec.format(value) or tostring(value)
        end
        row.value:SetText(shown or "")
        row.minus:SetEnabled(type(value) == "number" and #values > 0 and value > values[1] + .0001)
        row.plus:SetEnabled(type(value) == "number" and #values > 0 and value < values[#values] - .0001)
    end
    return row
end

-- Segmented choice buttons. Up to three choices sit beside the label when the
-- label and every choice fit there; otherwise the choices go under the label
-- and wrap to more lines rather than cut any text.
function Controls.ChoiceRow(parent, spec, width)
    local choices = addon.Schema and addon.Schema.Choices(spec) or {}
    local labelWidth = math.floor(width * .38)
    local row = NewRow(parent, spec, width, ROW, "choice")
    row.label = Controls.Label(row, spec.label, "body")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -7)
    row.buttons = {}
    for _, choice in ipairs(choices) do
        local button = Controls.Button(row, choice[2], 60, 21)
        button.optionKey, button.optionValue = spec.key, choice[1]
        button:SetScript("OnClick", function() Apply(row, choice[1]) end)
        button:HookScript("OnEnter", function(self) ShowTooltip(self, spec) end)
        button:HookScript("OnLeave", HideTooltip)
        row.buttons[#row.buttons + 1] = button
        row.searchText = row.searchText .. " " .. tostring(choice[2]):lower()
    end
    local left, gap = 12 + labelWidth + 4, 4
    local need = gap * (#choices - 1)
    for _, button in ipairs(row.buttons) do need = need + Controls.ButtonWidth(button) end
    local inline = #choices <= 3 and addon.VignetteRadarStyle.TextWidth(row.label) <= labelWidth
        and need <= width - 8 - left
    if inline then
        row.label:SetWidth(labelWidth)
        Controls.FlowButtons(row, row.buttons, left, -2, width - 8 - left, gap, 21)
    else
        row.label:SetWidth(width - 24)
        local lines = Controls.FlowButtons(row, row.buttons, 12, -23, width - 20, gap, 21)
        row:SetHeight(23 + lines * 25)
    end
    row.inline = inline
    function row:Refresh()
        local value = Current(spec)
        for _, button in ipairs(row.buttons) do
            local selected = button.optionValue == value or (type(value) == "number"
                and type(button.optionValue) == "number" and math.abs(value - button.optionValue) < .0001)
            if selected then button:LockHighlight() else button:UnlockHighlight() end
        end
    end
    return row
end

-- Hover ring for clickable color swatches: the theme background pushed near
-- black at .9 alpha, so it reads on light and dark swatches alike. (A white
-- ring vanished on light colors.) A selected swatch uses the accent instead.
function Controls.HoverRingColor()
    local style = addon.VignetteRadarStyle
    local r, g, b = .015, .022, .028
    if style and style.Color then r, g, b = style.Color("background") end
    return r * .35, g * .35, b * .35, .9
end

-- A color swatch row. The value is a { r, g, b } table; nil clears it.
function Controls.ColorRow(parent, spec, width)
    local row = NewRow(parent, spec, width, 24, "color")
    local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
    swatch:SetSize(18, 18)
    swatch:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -3)
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    swatch:SetBackdropBorderColor(.85, .9, .9, .48)
    swatch.colorSlot, swatch.optionKey = spec.subkey, spec.key
    row.label = Controls.Label(row, spec.label, "body", width - 46)
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 34, -7)
    swatch:SetScript("OnClick", function()
        if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
        local db = addon.GetSettings()
        local saved = type(db[spec.key]) == "table" and db[spec.key][spec.subkey]
        local previous = type(saved) == "table" and { saved[1], saved[2], saved[3] } or nil
        local r, g, b = Current(spec)
        ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function()
                local red, green, blue = ColorPickerFrame:GetColorRGB()
                Apply(row, { red, green, blue })
            end,
            cancelFunc = function() Apply(row, previous) end,
        })
    end)
    swatch:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(Controls.HoverRingColor())
        ShowTooltip(self, spec)
    end)
    swatch:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(.85, .9, .9, .48)
        HideTooltip()
    end)
    row.swatch = swatch
    function row:Refresh()
        local r, g, b = Current(spec)
        if type(r) == "number" then swatch:SetBackdropColor(r, g, b, 1) end
    end
    return row
end

-- One line of buttons sized from their labels: actions = { { label, onClick,
-- key }, ... }. Buttons that cannot share the line wrap to a second one.
function Controls.ActionRow(parent, actions, width)
    local row = NewRow(parent, nil, width, ROW, "action")
    row.buttons = {}
    local words = {}
    for index, action in ipairs(actions) do
        local button = Controls.Button(row, action[1], 60, 21)
        button:SetScript("OnClick", action[2])
        button.optionKey = action[3]
        row.buttons[index] = button
        words[#words + 1] = action[1]
    end
    local lines = Controls.FlowButtons(row, row.buttons, 10, -2, width - 20, 8, 21)
    row:SetHeight(ROW + math.max(0, lines - 1) * 25)
    row.searchText = table.concat(words, " "):lower()
    function row:Refresh() end
    return row
end

-- Small help text that may wrap. Height comes from the measured text width
-- (with room for word breaks), so the card leaves room for every line.
function Controls.NoteRow(parent, text, width, lines)
    local style = addon.VignetteRadarStyle
    local row = NewRow(parent, nil, width, ROW, "note")
    row.text = Controls.Label(row, text, "caption")
    local measured = math.max(1, math.ceil(style.TextWidth(row.text) * 1.15 / (width - 24)))
    lines = math.max(lines or 1, measured)
    local lineHeight = (row.text.vrFontSize or 10) + 3
    row:SetHeight(lines * lineHeight + 6)
    row.text:SetWidth(width - 24)
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -3)
    row.text:SetHeight(lines * lineHeight)
    row.text:SetWordWrap(lines > 1)
    row.text:SetTextColor(.62, .70, .70, 1)
    row.searchText = (text or ""):lower()
    function row:Refresh() end
    return row
end

-- Dispatches on the entry type: short fixed lists become segmented choices,
-- long or formatted number lists become steppers.
function Controls.Row(parent, spec, width)
    if spec.type == "bool" then return Controls.ToggleRow(parent, spec, width) end
    if spec.type == "color" then return Controls.ColorRow(parent, spec, width) end
    if spec.type == "number" and (spec.format or #(addon.Schema.Choices(spec)) > 5) then
        return Controls.StepperRow(parent, spec, width)
    end
    return Controls.ChoiceRow(parent, spec, width)
end

-- A section card: a soft rounded wash cut from the radar face art (no
-- outline, no stripe) with a title. Rows are laid out by the caller.
function Controls.Section(parent, title, width)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(width, 40)
    card.isCard, card.rows = true, {}
    card.faceSlices = NineSlice(card, POPUP_FACE, "BACKGROUND", 6, 11 / 256)
    card.title = Controls.Label(card, title, "title", width - 24)
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -9)
    card.titleText = title
    function card:RefreshTheme(r, g, b, alpha)
        for _, texture in ipairs(self.faceSlices) do texture:SetVertexColor(r, g, b, alpha) end
    end
    return card
end
Controls.Card = Controls.Section
