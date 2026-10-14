local _, addon = ...
if type(addon) ~= "table" then return end

-- The copy/paste box for Learned Data Export/Import (Data/LearnedTransfer.lua),
-- plus the route/world slash words, added in front of the radar's /vr:
--   /magpie export [zone]   /magpie import   /magpie sweep   /magpie today
-- The box is a short-lived dialog (Escape closes it), not a docked panel.
--   TransferBox.Open("export" | "import" [, scope])
local TransferBox = {}
addon.VignetteRadarTransferBox = TransferBox

local WIDTH, HEIGHT = 460, 330
local box

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("transfer", fmt, ...) end
end

local function Tell(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then frame:AddMessage("|cff8bd5caMagpie|r " .. text) end
end

local function Accent()
    local style = addon.VignetteRadarStyle
    if style and style.Color then
        local ok, r, g, b = pcall(style.Color, "accent")
        if ok and type(r) == "number" then return r, g, b end
    end
    return .57, .73, 1
end

local function Label(parent, size, x, y)
    local text = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(text, size, "")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    return text
end

local function Build()
    if box then return box end
    local controls = addon.VignetteRadarControls
    if type(CreateFrame) ~= "function" or not controls then return nil end
    box = CreateFrame("Frame", "VignetteRadarTransferBoxFrame", UIParent, "BackdropTemplate")
    box:SetSize(WIDTH, HEIGHT)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    box:SetFrameStrata("DIALOG")
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function(self) self:StartMoving() end)
    box:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    controls.PopupSurface(box)
    local special = _G.UISpecialFrames
    if type(special) == "table" then special[#special + 1] = "VignetteRadarTransferBoxFrame" end
    box.title = Label(box, 13, 16, -12)
    box.hint = Label(box, 10, 16, -36)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 16, -78)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -16, 84)
    scroll:EnableMouseWheel(true)
    local input = CreateFrame("EditBox", nil, scroll, "BackdropTemplate")
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetSize(WIDTH - 32, 160)
    input:SetMaxBytes(addon.VignetteRadarLearnedTransfer.MAX_BYTES + 1)
    addon.VignetteRadarStyle.SetFont(input, 10, "")
    input:SetTextInsets(8, 8, 6, 6)
    input:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1 })
    input:SetBackdropColor(.015, .025, .035, .96)
    input:SetBackdropBorderColor(.4, .53, .59, .45)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); box:Hide() end)
    scroll:SetScrollChild(input)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 30)))
    end)
    box.input = input
    box.result = Label(box, 10, 16, -(HEIGHT - 78))
    box.action = controls.Button(box, "Import", 120, 26)
    box.action:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 16, 14)
    box.action:SetScript("OnClick", function()
        if box.mode == "export" then
            box.input:SetFocus()
            box.input:HighlightText()
            return
        end
        local transfer = addon.VignetteRadarLearnedTransfer
        local counts, reason = transfer.Import(box.input:GetText())
        box.result:SetText(counts and transfer.Summary(counts) or ("Not imported: " .. tostring(reason)))
        if counts then Tell(transfer.Summary(counts)) end
    end)
    box.close = controls.Button(box, "Close", 90, 26)
    box.close:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -16, 14)
    box.close:SetScript("OnClick", function() box:Hide() end)
    box:Hide()
    return box
end

function TransferBox.Open(mode, scope)
    local frame = Build()
    if not frame then return false end
    local transfer = addon.VignetteRadarLearnedTransfer
    local r, g, b = Accent()
    addon.VignetteRadarControls.RefreshPopupSurface(frame)
    frame.title:SetTextColor(r, g, b)
    frame.hint:SetTextColor(.78, .85, .87)
    frame.result:SetTextColor(.7, .8, .82)
    frame.mode = mode
    if mode == "export" then
        local radar = addon.VignetteRadarAPI
        local mapID = scope == "zone" and radar and radar.GetCurrentMapID and radar.GetCurrentMapID() or nil
        local text, info = transfer.Export(scope, mapID)
        frame.title:SetText(scope == "zone" and "Export Learned Data: This Zone" or "Export Learned Data")
        frame.hint:SetText("Copy this text (Ctrl+C) and send it to a friend or alt. It holds learned rare spawns and your pins.")
        frame.input:SetText(text or "")
        frame.result:SetText(text and (info.records .. " records" .. (info.records < info.total
            and (" (newest " .. info.records .. " of " .. info.total .. ", size cap)") or "")) or tostring(info))
        frame.action:SetText("Select All")
        frame:Show()
        frame.input:SetFocus()
        frame.input:HighlightText()
        Log("box export scope=%s ok=%s", scope or "all", text ~= nil)
    else
        frame.title:SetText("Import Learned Data")
        frame.hint:SetText("Paste an export string (Ctrl+V), then Import. Only spawn and pin data is read; nothing runs.")
        frame.input:SetText("")
        frame.result:SetText("")
        frame.action:SetText("Import")
        frame:Show()
        frame.input:SetFocus()
        Log("box import opened")
    end
    if addon.VignetteRadarControls.FitButtonLabel then
        addon.VignetteRadarControls.FitButtonLabel(frame.action)
    end
    return true
end

-- Slash words, ahead of the radar's own /vr handler (it lowercases input).
local function OpenToday()
    local runtime = addon.VignetteRadarFeatureRuntime
    if runtime and runtime.RefreshIntelligence then pcall(runtime.RefreshIntelligence) end
    local intelligence = addon.VignetteRadarIntelligence
    if intelligence then intelligence.Open("Today") end
end
TransferBox.OpenToday = OpenToday

local function Install()
    if type(SlashCmdList) ~= "table" or type(SlashCmdList.VIGNETTERADAR) ~= "function"
        or TransferBox.installed then return end
    TransferBox.installed = true
    local slash = SlashCmdList
    local original = slash.VIGNETTERADAR
    slash.VIGNETTERADAR = function(message)
        local word, rest = tostring(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
        if word == "export" then
            TransferBox.Open("export", rest == "zone" and "zone" or "all")
        elseif word == "import" then
            TransferBox.Open("import")
        elseif word == "sweep" then
            local sweep = addon.VignetteRadarZoneSweep
            local ok, reason = false, "Zone Sweep is unavailable"
            if sweep then ok, reason = sweep.Start() end
            if not ok then Tell(tostring(reason)) end
        elseif word == "today" then
            OpenToday()
        else
            return original(message)
        end
    end
end
Install()
if addon.Bus then addon.Bus.On("LOGIN", Install) end

return TransferBox
