local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarAtlas = API

local MAX_MARKERS = 128
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE = "Interface\\Buttons\\WHITE8X8"
local COLORS = {
    live = { .10, .95, .68 },
    quest = { 1, .75, .24 },
    observed = { .62, .75, 1 },
    saved = { .67, .46, 1 },
    unknown = { .67, .72, .76 },
}
local PRIORITY = { live = 1, quest = 2, observed = 3, saved = 4, unknown = 5 }
local DESCRIPTIONS = {
    live = "Live local detection.",
    quest = "Quest objective or area.",
    observed = "Observed previously; current presence is unknown.",
    saved = "Saved map location; current presence is unknown.",
    unknown = "Location evidence is unknown.",
}
local mapID, entries, isOpen = nil, {}, false
local canvas, status, markers, selectedCallback, hookedMap
local Draw

local function IsCoordinate(value)
    return type(value) == "number" and value == value and value >= 0 and value <= 1
end

local function Evidence(entry)
    local value = entry.evidence or entry.evidenceClass or entry.source
    if value == "live" or value == "minimap" or value == "liveDetection" then return "live" end
    if value == "quest" or value == "objective" or value == "questMap" then return "quest" end
    if value == "observed" or value == "lastSeen" or value == "learnedObjective" then return "observed" end
    if value == "saved" or value == "pack" or value == "mapPack" then return "saved" end
    if entry.kind == "quest" or entry.type == "quest" then return "quest" end
    return "unknown"
end

local function MapFrame()
    local map = WorldMapFrame
    local child = map and map.ScrollContainer and map.ScrollContainer.Child
    if map and child and type(CreateFrame) == "function" then return map, child end
end

local function CurrentMapID(map)
    if map and type(map.GetMapID) == "function" then
        local ok, id = pcall(map.GetMapID, map)
        if ok then return id end
    end
end

local function NewMarker(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(18, 18)
    button:EnableMouse(true)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button.count = button:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(button.count, 11, "OUTLINE")
    button.count:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title or "Atlas Location")
            GameTooltip:AddLine(self.description or "Location evidence is unknown.", .8, .86, .91, true)
            if self.groupCount and self.groupCount > 1 then
                GameTooltip:AddLine(self.groupCount .. " nearby locations", 1, .8, .35)
            end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function(self)
        if selectedCallback and self.entry then selectedCallback(self.entry, self.groupCount or 1) end
    end)
    button:Hide()
    return button
end

local function EnsureUI()
    local map, child = MapFrame()
    if not map then return nil end
    if map ~= hookedMap then
        if type(hooksecurefunc) == "function" and type(map.SetMapID) == "function" then
            hooksecurefunc(map, "SetMapID", function() if isOpen then Draw() end end)
        end
        -- Closing the world map ends the overlay too, so nothing keeps drawing
        -- (or stays "open") on a hidden map.
        if type(map.HookScript) == "function" then
            map:HookScript("OnHide", function() if isOpen then API.Close() end end)
        end
        hookedMap = map
    end
    if canvas and canvas:GetParent() == child then return map end
    if canvas then canvas:Hide() end
    if status then status:Hide() end
    canvas = CreateFrame("Frame", nil, child)
    canvas:SetAllPoints(child)
    canvas:EnableMouse(false)
    canvas:SetScript("OnSizeChanged", function() if isOpen then Draw() end end)
    markers = {}
    -- This panel lives on the map frame, away from the scrolling/zooming canvas.
    status = CreateFrame("Frame", nil, map)
    status:SetSize(258, 37)
    status:SetPoint("TOPRIGHT", map, "TOPRIGHT", -42, -32)
    status:EnableMouse(false)
    local background = status:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(status)
    background:SetColorTexture(.012, .025, .035, .86)
    status.label = status:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(status.label, 11, "OUTLINE")
    status.label:SetPoint("LEFT", status, "LEFT", 10, 0)
    status.label:SetTextColor(.88, .94, .96)
    return map
end

local function HideMarkers()
    if not markers then return end
    for i = 1, #markers do markers[i]:Hide(); markers[i].entry = nil end
end

Draw = function()
    if not isOpen then return end
    local map = EnsureUI()
    if not map then return false, "World map unavailable" end
    HideMarkers()
    local activeMap = CurrentMapID(map)
    if activeMap and mapID and activeMap ~= mapID then
        status.label:SetText("Atlas  |  Select the source map")
        canvas:Show(); status:Show()
        return true
    end
    local cells, order = {}, {}
    for i = 1, #entries do
        local entry = entries[i]
        local x, y
        if type(entry) == "table" then x, y = entry.mapX or entry.x, entry.mapY or entry.y end
        if type(entry) == "table" and IsCoordinate(x) and IsCoordinate(y)
            and (not entry.mapID or not mapID or entry.mapID == mapID) then
            -- A fixed, bounded grid avoids a dense pack building hundreds of frames.
            local key = math.floor(x * 52) .. ":" .. math.floor(y * 30)
            local cell = cells[key]
            if not cell then
                cell = { entry = entry, x = x, y = y, evidence = Evidence(entry), count = 0 }
                cells[key] = cell
                order[#order + 1] = cell
            end
            cell.count = cell.count + 1
            local evidence = Evidence(entry)
            if PRIORITY[evidence] < PRIORITY[cell.evidence] then
                cell.entry, cell.x, cell.y, cell.evidence = entry, x, y, evidence
            end
        end
    end
    table.sort(order, function(a, b)
        if PRIORITY[a.evidence] ~= PRIORITY[b.evidence] then
            return PRIORITY[a.evidence] < PRIORITY[b.evidence]
        end
        if a.count ~= b.count then return a.count > b.count end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    local shown = math.min(#order, MAX_MARKERS)
    for i = 1, shown do
        local cell = order[i]
        local button = markers[i]
        if not button then
            button = NewMarker(canvas)
            markers[i] = button
        end
        button.entry, button.groupCount = cell.entry, cell.count
        button.title = tostring(cell.entry.name or cell.entry.title or "Atlas Location")
        button.description = cell.entry.coverage and
            "Visited ground from Survey Mode; this does not prove a target is present."
            or DESCRIPTIONS[cell.evidence]
        button:ClearAllPoints()
        button:SetPoint("CENTER", canvas, "TOPLEFT", cell.x * canvas:GetWidth(), -cell.y * canvas:GetHeight())
        local color = COLORS[cell.evidence]
        button.icon:SetTexture((cell.evidence == "quest" or cell.evidence == "observed") and CIRCLE or SQUARE)
        if cell.evidence == "live" and button.icon.SetRotation then button.icon:SetRotation(math.pi / 4)
        elseif button.icon.SetRotation then button.icon:SetRotation(0) end
        button.icon:SetVertexColor(color[1], color[2], color[3], cell.evidence == "observed" and .68 or .96)
        button.count:SetText(cell.count > 1 and (cell.count > 9 and "9+" or tostring(cell.count)) or
            (cell.evidence == "quest" and "!" or ""))
        button:Show()
    end
    status.label:SetText("Atlas  |  " .. shown .. " Locations")
    canvas:Show(); status:Show()
    return true
end

function API.SetData(id, newEntries)
    mapID = type(id) == "number" and id or nil
    entries = type(newEntries) == "table" and newEntries or {}
    if isOpen then Draw() end
end

function API.SetOnSelect(callback)
    selectedCallback = type(callback) == "function" and callback or nil
end

function API.Open()
    local map = MapFrame()
    if (not map or map.IsShown and not map:IsShown())
        and type(ToggleWorldMap) == "function" then
        pcall(ToggleWorldMap)
        map = MapFrame()
    end
    if not map then return false, "World map unavailable" end
    isOpen = true
    return Draw()
end

function API.Close()
    isOpen = false
    HideMarkers()
    if canvas then canvas:Hide() end
    if status then status:Hide() end
end

function API.Toggle()
    if isOpen then API.Close(); return false end
    return API.Open()
end

function API.IsOpen() return isOpen end
function API.Refresh() return Draw() end
