local _, addon = ...
if type(addon) ~= "table" then return end

-- World Map Route Overlay: the running Auto Route on Blizzard's world map,
-- as a line from you through the numbered next stops. Only route stops are
-- drawn (curated by Auto Route, Declutter and Zone Sweep), never raw pack
-- notes. A Zone Sweep shows its whole remaining loop.
-- Positions: a stop on the shown map uses its own x/y; otherwise its world
-- position is placed with C_Map.GetMapPosFromWorldPos (continent maps).
-- Redraws on ROUTE_CHANGED, map change and resize; the player end of the
-- line moves twice a second while the map is open.
--   MapRoute.Stops() -> { { item, label, current } }   (no map needed)
--   MapRoute.Place(item, mapID) -> x, y (0-1) or nil
--   MapRoute.Refresh()
local MapRoute = {}
addon.VignetteRadarMapRoute = MapRoute

local type, ipairs, pcall = type, ipairs, pcall
local Field, Number, Call = addon.Secret.Field, addon.Secret.Number, addon.Secret.Call

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAX_STOPS, PLAYER_TICK = 40, .5
local canvas, hookedMap, ticker = nil, nil, 0
local lines, marks = {}, {}

local function Settings() return addon.GetSettings() end

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("maproute", fmt, ...) end
end

local function Color(slot)
    local style = addon.VignetteRadarStyle
    if style and style.Color then
        local ok, r, g, b = pcall(style.Color, slot)
        if ok and type(r) == "number" then return r, g, b end
    end
    return .57, .73, 1
end

local function MapFrame()
    local map = _G.WorldMapFrame
    local child = map and map.ScrollContainer and map.ScrollContainer.Child
    if map and child then return map, child end
end

local function ShownMapID(map)
    local getter = map and map.GetMapID
    if type(getter) ~= "function" then return nil end
    local ok, id = pcall(getter, map)
    return ok and Number(id) or nil
end

local function XY(position)
    if type(position) ~= "table" then return nil end
    local x, y = Number(Field(position, "x")), Number(Field(position, "y"))
    if x and y then return x, y end
    local getXY = Field(position, "GetXY")
    if type(getXY) == "function" then
        local ok, a, b = pcall(getXY, position)
        if ok then return Number(a), Number(b) end
    end
end

local function Inside(x, y)
    return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function MapRoute.Place(item, mapID)
    if type(item) ~= "table" or not mapID then return nil end
    local x, y = Number(Field(item, "mapX")), Number(Field(item, "mapY"))
    if Number(Field(item, "mapID")) == mapID and Inside(x, y) then return x, y end
    local wx, wy, instance = Number(Field(item, "worldX")), Number(Field(item, "worldY")),
        Number(Field(item, "instanceID"))
    if not (wx and wy and instance) then return nil end
    local vector = Call(_G, "CreateVector2D", wx, wy) or { x = wx, y = wy }
    local _, position = Call(C_Map, "GetMapPosFromWorldPos", instance, vector, mapID)
    x, y = XY(position)
    if Inside(x, y) then return x, y end
end

local function PlayerXY(mapID)
    local position = Call(C_Map, "GetPlayerMapPosition", mapID, "player")
    local x, y = XY(position)
    if Inside(x, y) then return x, y end
end

-- The current stop, then the next ones: a running sweep's remaining plan,
-- else World Focus's horizon preview.
function MapRoute.Stops()
    local world = addon.VignetteRadarWorldFocus
    if not (world and world.IsRouteActive and (world.IsRouteActive() or world.IsRoutePaused())) then return {} end
    local stops = {}
    local current = world.GetActiveTarget and world.GetActiveTarget()
    local plan, at = nil, nil
    if Settings().vignetteRadarMapRouteSweep == true and world.GetSweepPlan then plan, at = world.GetSweepPlan() end
    if plan then
        if type(current) == "table" and not at then stops[1] = { item = current, current = true } end
        for index = at or 1, #plan do
            if #stops >= MAX_STOPS then break end
            stops[#stops + 1] = { item = plan[index], current = index == at }
        end
    else
        for _, entry in ipairs(world.GetHorizon and world.GetHorizon(6) or {}) do
            if type(entry.item) == "table" then
                stops[#stops + 1] = { item = entry.item, label = entry.label, current = entry.current == true }
            end
        end
        if #stops == 0 and type(current) == "table" then stops[1] = { item = current, current = true } end
    end
    return stops
end

local function Line(index)
    local line = lines[index]
    if not line then
        line = canvas:CreateLine(nil, "OVERLAY")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        lines[index] = line
    end
    return line
end

local function KindSlot(item)
    local points = addon.VignetteRadarPoints
    local kind = points and points.Kind(item) or nil
    return (kind == "rare" or kind == "treasure" or kind == "quest" or kind == "event") and kind or "accent"
end

local function Mark(index)
    local mark = marks[index]
    if mark then return mark end
    mark = CreateFrame("Button", nil, canvas)
    mark:SetSize(20, 20)
    mark.ring = mark:CreateTexture(nil, "ARTWORK")
    mark.ring:SetAllPoints(mark)
    mark.ring:SetTexture(CIRCLE)
    mark.face = mark:CreateTexture(nil, "ARTWORK", nil, 1)
    mark.face:SetPoint("TOPLEFT", mark, "TOPLEFT", 2, -2)
    mark.face:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", -2, 2)
    mark.face:SetTexture(CIRCLE)
    mark.number = mark:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(mark.number, 10, "OUTLINE")
    mark.number:SetPoint("CENTER", mark, "CENTER", 0, 0)
    mark:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title or "Route Stop", 1, 1, 1)
        GameTooltip:AddLine(self.current and "Current stop" or "Click to go here next", .65, .78, .75, true)
        GameTooltip:Show()
    end)
    mark:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    mark:SetScript("OnClick", function(self)
        local world = addon.VignetteRadarWorldFocus
        if self.current or not (world and world.JumpRouteStop and self.item) then return end
        local ok, reason = world.JumpRouteStop(self.item)
        Log("jump to %s ok=%s %s", self.title, ok, type(reason) == "string" and reason or "")
    end)
    marks[index] = mark
    return mark
end

local function HideFrom(lineIndex, markIndex)
    for index = lineIndex, #lines do lines[index]:Hide() end
    for index = markIndex, #marks do marks[index]:Hide(); marks[index].item = nil end
end

local function Draw()
    if not canvas then return end
    local map = MapFrame()
    local mapID = ShownMapID(map)
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if Settings().vignetteRadarMapRoute ~= true or not mapID or not (width and width > 0 and height and height > 0) then
        HideFrom(1, 1)
        return
    end
    local stops = MapRoute.Stops()
    local guidance = addon.VignetteRadarGuidance
    local ar, ag, ab = Color("accent")
    local px, py = PlayerXY(mapID)
    local lineCount, markCount, previousX, previousY = 0, 0, px, py
    for index, stop in ipairs(stops) do
        local x, y = MapRoute.Place(stop.item, mapID)
        if x then
            if previousX then
                lineCount = lineCount + 1
                local line = Line(lineCount)
                line:SetStartPoint("TOPLEFT", canvas, previousX * width, -previousY * height)
                line:SetEndPoint("TOPLEFT", canvas, x * width, -y * height)
                line:SetThickness(index == 1 and 3 or 2)
                line:SetVertexColor(ar, ag, ab, index == 1 and .9 or .6)
                line:Show()
            end
            markCount = markCount + 1
            local mark = Mark(markCount)
            local r, g, b = Color(KindSlot(stop.item))
            mark.item, mark.current = stop.item, stop.current
            mark.title = stop.label or (guidance and guidance.StopName and guidance.StopName(stop.item))
                or Field(stop.item, "name") or "Route Stop"
            mark:SetSize(stop.current and 24 or 20, stop.current and 24 or 20)
            mark:ClearAllPoints()
            mark:SetPoint("CENTER", canvas, "TOPLEFT", x * width, -y * height)
            mark.ring:SetVertexColor(.05, .07, .09, .9)
            mark.face:SetVertexColor(r, g, b, stop.current and 1 or .85)
            mark.number:SetText(tostring(index))
            mark.number:SetTextColor(1, 1, 1)
            mark:Show()
            previousX, previousY = x, y
        end
    end
    HideFrom(lineCount + 1, markCount + 1)
    Log("drew %d stops, %d lines on map %d", markCount, lineCount, mapID)
end

local function Ensure()
    local map, child = MapFrame()
    if not (map and type(CreateFrame) == "function") then return nil end
    if map ~= hookedMap then
        if type(hooksecurefunc) == "function" and type(map.SetMapID) == "function" then
            hooksecurefunc(map, "SetMapID", function() if canvas and canvas:IsVisible() then Draw() end end)
        end
        if type(map.HookScript) == "function" then map:HookScript("OnShow", function() Draw() end) end
        hookedMap = map
    end
    if canvas and canvas:GetParent() == child then return canvas end
    canvas = CreateFrame("Frame", nil, child)
    canvas:SetAllPoints(child)
    canvas:SetFrameLevel((child:GetFrameLevel() or 0) + 40)
    canvas:EnableMouse(false)
    canvas:SetScript("OnSizeChanged", function() Draw() end)
    canvas:SetScript("OnUpdate", function(_, elapsed)
        ticker = ticker + (elapsed or 0)
        if ticker < PLAYER_TICK then return end
        ticker = 0
        if marks[1] and marks[1]:IsShown() then Draw() end
    end)
    lines, marks = {}, {}
    return canvas
end

function MapRoute.Refresh()
    if not Ensure() then return false end
    local map = MapFrame()
    if map and map.IsShown and not map:IsShown() then return false end
    Draw()
    return true
end

local bus = addon.Bus
if bus then
    bus.On("ROUTE_CHANGED", function() MapRoute.Refresh() end, { coalesce = true })
    bus.On("LOGIN", function() Ensure() end)
    -- The world map may load on demand; hook it as soon as it exists.
    bus.On("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then Ensure() end end)
end

return MapRoute
