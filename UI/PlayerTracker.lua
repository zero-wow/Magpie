local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarPlayerTracker = API

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local observed, plateMarks, radarMarks = {}, setmetatable({}, { __mode = "k" }), {}
local panel, cachedSightings, nextPositionRead = nil, {}, 0
local cachedMapID, cachedInstanceID

local IsSecret, Number = addon.Secret.IsSecret, addon.Secret.Number

local function Plain(value)
    if IsSecret(value) then return nil end
    return value
end

local function Settings()
    local db = addon.GetSettings()
    if type(db.vignetteRadarMarkedPlayers) ~= "table" then
        db.vignetteRadarMarkedPlayers = {}
    end
    return db
end

local function Identity(value)
    value = Plain(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if #value > 80 or value:find("[%c|]") then return nil end
    local name, realm = value:match("^([^%-]+)%-(.+)$")
    if not name or not realm then return nil end
    name = name:match("^%s*(.-)%s*$")
    realm = realm:gsub("%s+", "")
    if name == "" or realm == "" then return nil end
    local label = name .. "-" .. realm
    return label:lower(), label
end

local function UnitIdentity(unit)
    if type(UnitIsPlayer) ~= "function" then return nil end
    local ok, isPlayer = pcall(UnitIsPlayer, unit)
    if not ok or Plain(isPlayer) ~= true then return nil end
    local name, realm
    if type(UnitFullName) == "function" then
        ok, name, realm = pcall(UnitFullName, unit)
        if not ok then name, realm = nil, nil end
    end
    name, realm = Plain(name), Plain(realm)
    if type(name) ~= "string" and type(UnitName) == "function" then
        ok, name = pcall(UnitName, unit)
        if not ok then name = nil end
        name = Plain(name)
    end
    if type(name) ~= "string" then return nil end
    if name:find("-", 1, true) then return Identity(name) end
    if type(realm) ~= "string" or realm == "" then
        if type(GetNormalizedRealmName) == "function" then
            ok, realm = pcall(GetNormalizedRealmName)
            if not ok then realm = nil end
            realm = Plain(realm)
        end
    end
    return Identity(name .. "-" .. (realm or ""))
end

local function PlateForUnit(unit)
    if not (C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function") then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and Plain(plate) or nil
end

local function PlateMark(plate)
    local mark = plateMarks[plate]
    if mark then return mark end
    mark = CreateFrame("Frame", nil, plate)
    mark:SetSize(25, 25)
    mark:SetPoint("BOTTOM", plate.UnitFrame or plate, "TOP", 0, 6)
    mark:SetFrameLevel(plate:GetFrameLevel() + 10)
    local shadow = mark:CreateTexture(nil, "BACKGROUND")
    shadow:SetAllPoints(mark)
    shadow:SetTexture(SKULL)
    shadow:SetVertexColor(0, 0, 0, .85)
    local skull = mark:CreateTexture(nil, "OVERLAY")
    skull:SetSize(21, 21)
    skull:SetPoint("CENTER")
    skull:SetTexture(SKULL)
    skull:SetVertexColor(1, .22, .19, 1)
    mark:Hide()
    plateMarks[plate] = mark
    return mark
end

local function HideUnit(unit)
    local entry = observed[unit]
    if entry and entry.plate and plateMarks[entry.plate] then
        plateMarks[entry.plate]:Hide()
    end
    observed[unit] = nil
    nextPositionRead = 0
end

local function RefreshPanel()
    if not (panel and panel:IsShown()) then return end
    local marks = {}
    for key, label in pairs(Settings().vignetteRadarMarkedPlayers) do
        if type(key) == "string" and type(label) == "string" then
            marks[#marks + 1] = { key = key, label = label }
        end
    end
    table.sort(marks, function(a, b) return a.label:lower() < b.label:lower() end)
    local count, seen = #marks, {}
    for _, entry in pairs(observed) do seen[entry.key] = true end
    panel.status:SetText(count .. (count == 1 and " Marked Player" or " Marked Players"))
    local maxPage = math.max(1, math.ceil(count / #panel.rows))
    panel.page = math.min(panel.page or 1, maxPage)
    panel.pageLabel:SetText(panel.page .. " / " .. maxPage)
    for index, row in ipairs(panel.rows) do
        local mark = marks[(panel.page - 1) * #panel.rows + index]
        row.mark = mark
        if mark then
            row.name:SetText(mark.label)
            row.state:SetText(seen[mark.key] and "Detected" or "Not Detected")
            row.state:SetTextColor(seen[mark.key] and 1 or .55,
                seen[mark.key] and .38 or .65, seen[mark.key] and .32 or .68, 1)
            row:Show()
        else row:Hide() end
    end
end

local function RefreshUnit(unit)
    HideUnit(unit)
    local key, label = UnitIdentity(unit)
    if not key or not Settings().vignetteRadarMarkedPlayers[key] then return end
    local plate = unit:match("^nameplate%d+$") and PlateForUnit(unit) or nil
    observed[unit] = { key = key, label = label, plate = plate }
    if plate then PlateMark(plate):Show() end
    RefreshPanel()
end

function API.Rescan()
    for unit in pairs(observed) do HideUnit(unit) end
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do RefreshUnit(unit) end
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(Plain(plates)) == "table" then
            for _, plate in ipairs(plates) do
                local read, unit = pcall(function() return plate.unitToken or plate.namePlateUnitToken end)
                if read and type(Plain(unit)) == "string" then RefreshUnit(unit) end
            end
        end
    end
    RefreshPanel()
end

function API.Mark(name)
    local key, label = Identity(name)
    if not key then return false, "Enter a Character-Realm name" end
    local marks = Settings().vignetteRadarMarkedPlayers
    if not marks[key] then
        local count = 0
        for _ in pairs(marks) do count = count + 1 end
        if count >= 64 then return false, "Player Tracker is full" end
    end
    marks[key] = label
    API.Rescan()
    return true, label
end

function API.MarkTarget()
    local _, label = UnitIdentity("target")
    if not label then return false, "Target a player with a known realm first" end
    return API.Mark(label)
end

function API.Remove(name)
    local key = Identity(name)
    if not key or not Settings().vignetteRadarMarkedPlayers[key] then return false end
    Settings().vignetteRadarMarkedPlayers[key] = nil
    API.Rescan()
    return true
end

function API.List()
    local result = {}
    for _, label in pairs(Settings().vignetteRadarMarkedPlayers) do result[#result + 1] = label end
    table.sort(result)
    return result
end

function API.IsDetecting()
    return next(observed) ~= nil
end

local function WorldPosition(unit, mapID)
    if type(UnitPosition) == "function" then
        local ok, x, y, _, instance = pcall(UnitPosition, unit)
        if ok then
            x, y, instance = Number(x), Number(y), Number(instance)
            if x and y and instance then return x, y, instance end
        end
    end
    if not (mapID and C_Map and type(C_Map.GetPlayerMapPosition) == "function"
        and type(C_Map.GetWorldPosFromMapPos) == "function") then return nil end
    local ok, vector = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
    if not ok or not Plain(vector) then return nil end
    ok, mapID, vector = pcall(C_Map.GetWorldPosFromMapPos, mapID, vector)
    if not ok or not Plain(vector) then return nil end
    local read, getter = pcall(function() return vector.GetXY end)
    if not read then return nil end
    local x, y
    if type(Plain(getter)) == "function" then
        ok, x, y = pcall(getter, vector)
        if not ok then return nil end
    else
        ok, x, y = pcall(function() return vector.x, vector.y end)
        if not ok then return nil end
    end
    return Number(x), Number(y), Number(mapID)
end

function API.GetSightings(player)
    if not player then return {} end
    local now = type(GetTime) == "function" and Number(GetTime()) or 0
    if now and now < nextPositionRead and cachedMapID == player.mapID
        and cachedInstanceID == player.instanceID then return cachedSightings end
    nextPositionRead = (now or 0) + .25
    cachedMapID, cachedInstanceID = player.mapID, player.instanceID
    cachedSightings = {}
    local seen = {}
    for unit, entry in pairs(observed) do
        if not seen[entry.key] then
            local x, y, instance = WorldPosition(unit, player.mapID)
            if x and y and (not player.instanceID or instance == player.instanceID) then
                cachedSightings[#cachedSightings + 1] = {
                    key = entry.key, name = entry.label, worldX = x, worldY = y,
                }
                seen[entry.key] = true
            end
        end
    end
    return cachedSightings
end

function API.HideRadar()
    for _, marker in ipairs(radarMarks) do marker:Hide() end
end

function API.RenderRadar(field, player, range, radius, facing, project)
    if not (field and player and range and radius and project) then API.HideRadar(); return end
    local shown = 0
    for _, entry in ipairs(API.GetSightings(player)) do
        local dx, dy = entry.worldX - player.worldX, entry.worldY - player.worldY
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance <= range and shown < 12 then
            local x, y = project(dx, dy, distance, facing, radius - 9, range)
            if x and y then
                shown = shown + 1
                local marker = radarMarks[shown]
                if not marker then
                    marker = CreateFrame("Frame", nil, field)
                    marker:SetSize(23, 23)
                    marker:SetFrameLevel(field:GetFrameLevel() + 12)
                    local skull = marker:CreateTexture(nil, "OVERLAY")
                    skull:SetAllPoints(marker)
                    skull:SetTexture(SKULL)
                    skull:SetVertexColor(1, .22, .19, 1)
                    marker.skull = skull
                    marker:EnableMouse(true)
                    marker:SetScript("OnEnter", function(self)
                        if not GameTooltip then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Marked Player: " .. self.playerName, 1, .35, .31)
                        GameTooltip:AddLine(math.floor(self.distance + .5) .. " yd · Detected Now", .8, .85, .86)
                        GameTooltip:Show()
                    end)
                    marker:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                    radarMarks[shown] = marker
                end
                marker.playerName, marker.distance = entry.name, distance
                marker:ClearAllPoints()
                marker:SetPoint("CENTER", field, "CENTER", x, y)
                marker:Show()
            end
        end
    end
    for index = shown + 1, #radarMarks do radarMarks[index]:Hide() end
end

local function Text(parent, value, x, y, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size or 10, "")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetText(value)
    return label
end

local function EnsurePanel()
    if panel then return panel end
    local controls = addon.VignetteRadarControls
    panel = CreateFrame("Frame", "VignetteRadarPlayerTrackerPanel", UIParent, "BackdropTemplate")
    panel:SetSize(338, 308)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    controls.PopupSurface(panel)
    panel.title = Text(panel, "Player Tracker", 13, -11, 12)
    panel.title:SetTextColor(1, .31, .27, 1)
    panel.status = Text(panel, "", 13, -32, 9)
    local close = addon.VignetteRadarIconButton.Create(panel, "close", { size = 20,
        label = "Close", onClick = function() panel:Hide() end })
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -9, -8)
    local target = controls.Button(panel, "Mark Current Target", 310, 22)
    target:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -52)
    target:SetScript("OnClick", function()
        local ok, message = API.MarkTarget()
        panel.message:SetText(ok and ("Marked " .. message) or message)
    end)
    panel.input = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    panel.input:SetSize(226, 23)
    panel.input:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -82)
    panel.input:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel.input:SetBackdropColor(.03, .045, .05, 1)
    panel.input:SetBackdropBorderColor(.5, .35, .34, .8)
    addon.VignetteRadarStyle.SetFont(panel.input, 10, "")
    panel.input:SetTextInsets(7, 7, 0, 0)
    panel.input:SetAutoFocus(false)
    panel.input:SetMaxLetters(80)
    panel.input:SetText("")
    local add = controls.Button(panel, "Add Player", 82, 23)
    add:SetPoint("TOPLEFT", panel, "TOPLEFT", 244, -82)
    local function AddEntered()
        local ok, message = API.Mark(panel.input:GetText())
        panel.message:SetText(ok and ("Marked " .. message) or message)
        if ok then panel.input:SetText(""); panel.input:ClearFocus() end
    end
    add:SetScript("OnClick", AddEntered)
    panel.input:SetScript("OnEnterPressed", AddEntered)
    panel.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.rows = {}
    for index = 1, 5 do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(310, 25)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -116 - (index - 1) * 28)
        local skull = row:CreateTexture(nil, "OVERLAY")
        skull:SetSize(18, 18)
        skull:SetPoint("LEFT", row, "LEFT", 1, 0)
        skull:SetTexture(SKULL)
        skull:SetVertexColor(1, .22, .19, 1)
        row.name = Text(row, "", 24, -1, 10)
        row.name:SetWidth(220)
        row.name:SetWordWrap(false)
        row.state = Text(row, "", 24, -13, 8)
        row.state:SetWidth(220)
        row.state:SetWordWrap(false)
        local remove = controls.Button(row, "Remove", 58, 20)
        remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        remove:SetScript("OnClick", function()
            if row.mark then API.Remove(row.mark.label) end
        end)
        panel.rows[index] = row
    end
    panel.message = Text(panel, "Add a Character-Realm name or mark your target.", 14, -259, 9)
    panel.message:SetTextColor(.68, .78, .78, 1)
    local previous = controls.Button(panel, "Previous", 80, 21)
    previous:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 9)
    previous:SetScript("OnClick", function()
        panel.page = math.max(1, (panel.page or 1) - 1)
        RefreshPanel()
    end)
    panel.pageLabel = Text(panel, "1 / 1", 155, -285, 9)
    local nextButton = controls.Button(panel, "Next", 80, 21)
    nextButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 9)
    nextButton:SetScript("OnClick", function()
        panel.page = (panel.page or 1) + 1
        RefreshPanel()
    end)
    panel:Hide()
    return panel
end

function API.Open()
    local frame = EnsurePanel()
    addon.VignetteRadarControls.RefreshPopupSurface(frame)
    frame:Show()
    RefreshPanel()
    return frame
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_ENTERING_WORLD", "UNIT_NAME_UPDATE" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        HideUnit(unit)
        RefreshPanel()
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_NAME_UPDATE" then
        if type(unit) == "string" then RefreshUnit(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then RefreshUnit("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then RefreshUnit("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then RefreshUnit("mouseover")
    else API.Rescan() end
end)

API._EventFrame = events
Settings()
