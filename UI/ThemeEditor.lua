local _, addon = ...
if type(addon) ~= "table" then return end

-- Customize (Copy + Modify) for themes. Opened from the Looks theme picker:
--   create  a new custom theme from any theme (name + every role color)
--   edit    change a saved custom theme in place
--   rename  give a saved custom theme a new name
--   delete  confirm removing a saved custom theme
-- While the panel is open its working colors are the Style preview, so the
-- radar and every panel recolor live; Cancel, Escape or closing drops the
-- preview, Save writes the theme through Style and selects it.
local Editor = {}
addon.VignetteRadarThemeEditor = Editor

local WIDTH, PAD, ROLE_ROW = 384, 14, 26
local LIGHT, SOFT, WARN, ERROR = { .81, .87, .86 }, { .62, .70, .70 }, { 1, .78, .42 }, { 1, .45, .42 }
local NAME = "VignetteRadarThemeEditorPanel"
local QUICK = "VignetteRadarQuickConfigPanel"
local TITLES = { create = "Customize Theme", edit = "Edit Theme", rename = "Rename Theme",
    delete = "Delete Theme" }
local frame

local function Style() return addon.VignetteRadarStyle end
local function Controls() return addon.VignetteRadarControls end

local function Label(parent, text, size, width, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    Style().SetFont(label, size or 10, "")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    if width then label:SetWidth(width) end
    color = color or LIGHT
    label:SetTextColor(color[1], color[2], color[3], 1)
    label:SetText(text or "")
    return label
end

local function Input(parent, width, letters)
    local input = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    input:SetSize(width, 20)
    input:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    input:SetBackdropColor(0, 0, 0, .35)
    Style().SetFont(input, 10, "")
    input:SetTextInsets(6, 6, 0, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(letters)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return input
end

-- Escape closes the top window only: while this panel is open the settings
-- window leaves UISpecialFrames, so CloseSpecialWindows hides just this one.
local function SetQuickEscape(enabled)
    if type(UISpecialFrames) ~= "table" then return end
    for index = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[index] == QUICK then
            if enabled then return end
            table.remove(UISpecialFrames, index)
        end
    end
    if enabled and _G[QUICK] then UISpecialFrames[#UISpecialFrames + 1] = QUICK end
end

local function RefreshEverything()
    local radar = addon.VignetteRadarAPI
    if radar and radar.Refresh then radar.Refresh(false) end
    local quick = addon.VignetteRadarQuickConfig
    if quick and quick.Refresh then quick.Refresh() end
    if frame and frame:IsShown() then Editor.RefreshSkin() end
end

-- Swatch rings: a dark ring on hover reads on light and dark colors alike;
-- the role open in the color picker keeps an accent ring.
local function PaintRing(swatch)
    local style = Style()
    if frame and frame.activeSlot == swatch.slot then
        local r, g, b = style.Color("accent")
        swatch:SetBackdropBorderColor(r, g, b, 1)
    elseif swatch._hovered then
        swatch:SetBackdropBorderColor(Controls().HoverRingColor())
    else
        swatch:SetBackdropBorderColor(.85, .9, .9, .35)
    end
end
Editor.PaintRing = PaintRing

function Editor.RefreshSkin()
    if not frame then return end
    local style, controls = Style(), Controls()
    controls.RefreshPopupSurface(frame)
    local tray = addon.VignetteRadarTray
    if tray and tray.SkinLikeRadar then tray.SkinLikeRadar(frame, .96) end
    local ar, ag, ab = style.Color("accent")
    local rr, rg, rb = style.Color("rings")
    frame.title:SetTextColor(ar, ag, ab, 1)
    frame.nameInput:SetBackdropBorderColor(rr, rg, rb, .5)
    for _, role in pairs(frame.roles) do
        role.hex:SetBackdropBorderColor(rr, rg, rb, .35)
        PaintRing(role.swatch)
    end
    controls.RefreshTheme()
end

-- Shows the working colors and readability warnings, then previews them live.
local function ShowWork(skipHex)
    local style = Style()
    for slot, role in pairs(frame.roles) do
        local color = frame.work[slot]
        role.swatch:SetBackdropColor(color[1], color[2], color[3], 1)
        if not skipHex or skipHex ~= slot then role.hex:SetText(style.HexOf(color[1], color[2], color[3])) end
    end
    local warnings = style.ThemeWarnings(frame.work, frame.startColors)
    frame.warnings:SetText(#warnings > 0 and ("Heads-up: " .. table.concat(warnings, " ", 1, math.min(2, #warnings))
        .. (#warnings > 2 and (" +" .. (#warnings - 2) .. " more.") or "")) or "Colors read clearly.")
    local color = #warnings > 0 and WARN or SOFT
    frame.warnings:SetTextColor(color[1], color[2], color[3], 1)
    frame.warningList = warnings
    style.SetPreview(frame.work)
    RefreshEverything()
end

function Editor.SetRole(slot, r, g, b, skipHex)
    if not (frame and frame.work and frame.work[slot]) then return false end
    for _, value in ipairs({ r, g, b }) do
        if type(value) ~= "number" or value ~= value then return false end
    end
    frame.work[slot] = { math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b)) }
    ShowWork(skipHex)
    return true
end

-- "#a1b2c3", "a1b2c3" or "abc" (short form). Returns false for anything else.
function Editor.SetRoleHex(slot, text, skipHex)
    if type(text) ~= "string" then return false end
    local hex = text:gsub("^%s*#?", ""):gsub("%s+$", "")
    if hex:match("^%x%x%x$") then hex = hex:gsub("(%x)", "%1%1") end
    local color = Style().HexColor(hex)
    if not color then return false end
    return Editor.SetRole(slot, color[1], color[2], color[3], skipHex)
end

local function OpenPicker(slot)
    if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
    local before = frame.work[slot]
    local previous = { before[1], before[2], before[3] }
    frame.activeSlot = slot
    Editor.RefreshSkin()
    ColorPickerFrame:SetupColorPickerAndShow({ r = previous[1], g = previous[2], b = previous[3],
        hasOpacity = false,
        swatchFunc = function()
            if not (frame:IsShown() and frame.activeSlot == slot) then return end
            Editor.SetRole(slot, ColorPickerFrame:GetColorRGB())
        end,
        cancelFunc = function()
            if frame:IsShown() and frame.work then Editor.SetRole(slot, previous[1], previous[2], previous[3]) end
            frame.activeSlot = nil
            Editor.RefreshSkin()
        end,
    })
end

local function RoleCell(slot, index)
    local style, controls = Style(), Controls()
    local column, line = (index - 1) % 2, math.floor((index - 1) / 2)
    local each = (WIDTH - PAD * 2 - 10) / 2
    local x, y = PAD + column * (each + 10), -frame.rolesTop - line * ROLE_ROW
    local swatch = CreateFrame("Button", nil, frame, "BackdropTemplate")
    swatch:SetSize(18, 18)
    swatch:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    swatch:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    swatch.slot = slot
    swatch:SetScript("OnClick", function() OpenPicker(slot) end)
    swatch:SetScript("OnEnter", function(self)
        self._hovered = true
        PaintRing(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(controls.TitleCase(style.labels[slot]), 1, 1, 1)
            GameTooltip:AddLine("Click to pick a color, or type a hex code.", .65, .78, .75, true)
            GameTooltip:Show()
        end
    end)
    swatch:SetScript("OnLeave", function(self)
        self._hovered = false
        PaintRing(self)
        if GameTooltip then GameTooltip:Hide() end
    end)
    local label = Label(frame, controls.TitleCase(style.labels[slot]), 9, each - 92)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 24, y - 4)
    local hex = Input(frame, 64, 7)
    hex:SetPoint("TOPLEFT", frame, "TOPLEFT", x + each - 64, y + 1)
    hex:SetScript("OnTextChanged", function(self, userInput)
        -- Live while typing once six digits are in; short forms apply on Enter.
        local text = self:GetText() or ""
        if userInput and text:match("^%s*#?%x%x%x%x%x%x%s*$") then Editor.SetRoleHex(slot, text, slot) end
    end)
    local function Commit(self)
        if not Editor.SetRoleHex(slot, self:GetText() or "") then
            local color = frame.work[slot]
            self:SetText(style.HexOf(color[1], color[2], color[3]))
        end
    end
    hex:SetScript("OnEnterPressed", function(self) Commit(self); self:ClearFocus() end)
    hex:SetScript("OnEditFocusLost", Commit)
    frame.roles[slot] = { swatch = swatch, label = label, hex = hex }
end

local function Build()
    if frame then return frame end
    local style, controls = Style(), Controls()
    frame = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = NAME end
    frame:SetFrameStrata("DIALOG")
    if frame.SetToplevel then frame:SetToplevel(true) end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    controls.PopupSurface(frame)
    frame.roles = {}

    frame.title = Label(frame, "", 12, WIDTH - 60)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -12)
    frame.source = Label(frame, "", 9, WIDTH - PAD * 2, SOFT)
    frame.source:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -30)
    local icons = addon.VignetteRadarIconButton
    if icons and icons.Create and icons.HasIcon("close") then
        frame.close = icons.Create(frame, "close", { label = "Cancel", size = 22,
            onClick = function() Editor.Cancel() end })
    else
        frame.close = controls.Button(frame, "×", 22, 22)
        frame.close:SetScript("OnClick", function() Editor.Cancel() end)
    end
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -9)

    frame.nameLabel = Label(frame, "Name", 10, 50)
    frame.nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -56)
    frame.nameInput = Input(frame, WIDTH - PAD * 2 - 56, style.NAME_LIMIT + 8)
    frame.nameInput:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 56, -52)
    frame.nameInput:SetScript("OnTextChanged", function() Editor.CheckName() end)
    frame.nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Editor.Save() end)
    frame.status = Label(frame, "", 9, WIDTH - PAD * 2 - 56)
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 56, -76)

    frame.rolesTop = 98
    for index, slot in ipairs(style.slots) do RoleCell(slot, index) end
    local rolesBottom = frame.rolesTop + math.ceil(#style.slots / 2) * ROLE_ROW
    frame.warnings = Label(frame, "", 9, WIDTH - PAD * 2, SOFT)
    frame.warnings:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -rolesBottom - 4)
    frame.warnings:SetWordWrap(true)
    frame.warnings:SetHeight(24)
    frame.fullHeight = rolesBottom + 70

    local half = math.floor((WIDTH - PAD * 2 - 10) / 2)
    frame.save = controls.Button(frame, "Save", half, 22)
    frame.save:SetScript("OnClick", function() Editor.Save() end)
    frame.cancel = controls.Button(frame, "Cancel", half, 22)
    frame.cancel:SetScript("OnClick", function() Editor.Cancel() end)

    frame:SetScript("OnShow", function() SetQuickEscape(false) end)
    frame:SetScript("OnHide", function()
        SetQuickEscape(true)
        -- Closing any way but Save drops the preview.
        if frame.previewing then
            frame.previewing = false
            frame.activeSlot = nil
            style.SetPreview(nil)
            RefreshEverything()
        end
    end)
    frame:Hide()
    return frame
end

-- Validates the typed name; shows why it cannot be used. Returns the clean name.
function Editor.CheckName()
    if not (frame and frame.mode) then return nil end
    if frame.mode == "delete" then return true end
    local name, reason = Style().ValidateThemeName(frame.nameInput:GetText() or "", frame.key)
    local color = name and SOFT or ERROR
    frame.status:SetText(name and ("Saved under Custom as " .. name .. ".") or reason)
    frame.status:SetTextColor(color[1], color[2], color[3], 1)
    frame.save:SetEnabled(name ~= nil)
    return name
end

local function Layout(mode)
    local full = mode == "create" or mode == "edit"
    for _, role in pairs(frame.roles) do
        role.swatch:SetShown(full)
        role.label:SetShown(full)
        role.hex:SetShown(full)
    end
    frame.warnings:SetShown(full)
    frame.nameLabel:SetShown(mode ~= "delete")
    frame.nameInput:SetShown(mode ~= "delete")
    local height = full and frame.fullHeight or 132
    local half = math.floor((WIDTH - PAD * 2 - 10) / 2)
    frame.save:ClearAllPoints()
    frame.save:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(height - 36))
    frame.cancel:ClearAllPoints()
    frame.cancel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + half + 10, -(height - 36))
    frame.save:SetText(mode == "delete" and "Delete" or "Save")
    frame:SetSize(WIDTH, height)
end

local function Position()
    frame:ClearAllPoints()
    local quick = _G[QUICK]
    if quick and quick.IsShown and quick:IsShown() then
        frame:SetPoint("TOPLEFT", quick, "TOPRIGHT", 8, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- mode: "create" (key = any theme to copy), "edit", "rename" or "delete"
-- (key = a custom theme). Returns false when the theme does not exist.
function Editor.Open(mode, key)
    local style = Style()
    if not TITLES[mode] or not style.HasTheme(key) then return false end
    local custom = style.CustomTheme(key)
    if mode ~= "create" and not custom then return false end
    Build()
    if frame:IsShown() then frame:Hide() end
    frame.mode, frame.key = mode, mode ~= "create" and key or nil
    frame.base = mode == "create" and key or custom.base
    frame.activeSlot, frame.previewing = nil, false
    frame.title:SetText(TITLES[mode])
    if mode == "create" then
        frame.source:SetText("Copy of " .. style.ThemeName(key) .. ". Change any color below.")
        frame.nameInput:SetText(style.SuggestThemeName(key))
    elseif mode == "delete" then
        frame.source:SetText("Delete " .. custom.name .. "? This cannot be undone.")
    else
        frame.source:SetText(mode == "edit" and "Change the name or any color below."
            or "Pick a new name for " .. custom.name .. ".")
        frame.nameInput:SetText(custom.name)
    end
    if mode == "delete" then
        frame.status:SetText("")
        frame.save:SetEnabled(true)
    end
    Layout(mode)
    Position()
    frame:Show()
    Editor.RefreshSkin()
    if mode == "create" or mode == "edit" then
        frame.work = style.CopyColors(key)
        frame.startColors = style.CopyColors(key)
        frame.previewing = true
        ShowWork()
    else
        frame.work = nil
    end
    Editor.CheckName()
    return true
end

local function Finish(selectKey)
    local style = Style()
    frame.previewing = false
    frame.activeSlot = nil
    style.SetPreview(nil)
    frame:Hide()
    local schema = addon.Schema
    if selectKey and schema then schema.Set("vignetteRadarTheme", selectKey) end
    RefreshEverything()
end

-- Saves (or deletes, in delete mode). Returns the theme key, or nil and a reason.
function Editor.Save()
    if not (frame and frame:IsShown()) then return nil end
    local style, mode = Style(), frame.mode
    if mode == "delete" then
        local current = addon.GetSettings().vignetteRadarTheme
        local after = style.DeleteCustomTheme(frame.key)
        Finish(current == frame.key and after or nil)
        return after
    end
    local name = Editor.CheckName()
    if not name then return nil, frame.status:GetText() end
    local key, reason
    if mode == "rename" then
        key, reason = style.RenameCustomTheme(frame.key, name)
    else
        key, reason = style.SaveCustomTheme(frame.key, name, frame.base, frame.work)
    end
    if not key then
        frame.status:SetText(reason)
        frame.status:SetTextColor(ERROR[1], ERROR[2], ERROR[3], 1)
        return nil, reason
    end
    -- A new or edited theme is put to use; a rename keeps whatever is in use.
    Finish(mode ~= "rename" and key or nil)
    return key
end

function Editor.Cancel()
    if frame and frame:IsShown() then frame:Hide() end
end

function Editor.IsShown() return frame ~= nil and frame:IsShown() end
function Editor.GetFrame() return frame end
