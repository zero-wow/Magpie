local _, addon = ...
if type(addon) ~= "table" then return end

-- Nameplate Marker: the focus icon over the nameplate of the rare you are
-- going for, so it stands out in a crowd. Who gets a mark:
--   focus     the focused live rare (or a focused rare note, by npcID)
--   favorite  the focus plus every live favourite rare (default)
--   rare      the above plus any nameplate Blizzard classifies as rare
-- Matching is on the vignette's objectGUID, then the npcID inside it. In
-- 12.0 UnitGUID is SecretWhenUnitIdentityRestricted: a secret GUID or
-- classification is skipped silently. Work happens on nameplate events and
-- when the wanted set changes; there is no per-frame update.
--   NameplateMarker.Wanted() -> guids, npcs   NameplateMarker.Rescan()
--   NameplateMarker.NpcFromGUID(guid) -> npcID
local Marker = {}
addon.VignetteRadarNameplateMarker = Marker

local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring
local Field, Number, Text, Call = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text, addon.Secret.Call

local SIZE = 26
local marks = setmetatable({}, { __mode = "k" }) -- plate -> mark frame
local shown = {}                                  -- unit -> plate with a shown mark
local wantGUID, wantNPC, signature = {}, {}, ""

local function Settings() return addon.GetSettings() end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("nameplate", fmt, ...) end
end

function Marker.NpcFromGUID(guid)
    guid = Text(guid)
    if not guid then return nil end
    local kind, id = guid:match("^([A-Za-z]+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

local function Rare(item)
    local points = addon.VignetteRadarPoints
    local kind = points and points.Kind(item)
    return kind == "rare" or kind == "mob"
end

local function Want(item, guids, npcs)
    if type(item) ~= "table" or not Rare(item) then return end
    local guid = Text(Field(item, "objectGUID"))
    if guid then guids[guid] = item end
    local npc = Marker.NpcFromGUID(guid) or Number(Field(item, "npcID"))
    if npc then npcs[npc] = item end
end

-- The GUIDs and npcIDs to mark right now.
function Marker.Wanted()
    local guids, npcs = {}, {}
    local db = Settings()
    if db.vignetteRadarNameplateMarker ~= true then return guids, npcs end
    local focus = addon.VignetteRadarFocus
    local current = focus and focus.Get()
    if current and current.ref then Want(current.ref, guids, npcs) end
    local world = addon.VignetteRadarWorldFocus
    local active = world and world.GetActiveTarget and world.GetActiveTarget()
    if active then Want(active, guids, npcs) end
    local who = db.vignetteRadarNameplateMarkerWho
    if who == "favorite" or who == "rare" then
        local points, features = addon.VignetteRadarPoints, addon.VignetteRadarFeatures
        for _, target in ipairs(points and points.Refs("live") or {}) do
            if who == "rare" or (features and features.IsFavorite(target)) then Want(target, guids, npcs) end
        end
    end
    return guids, npcs
end

local function Mark(plate)
    local mark = marks[plate]
    if mark then return mark end
    mark = CreateFrame("Frame", nil, plate)
    mark:SetSize(SIZE, SIZE)
    mark:SetPoint("BOTTOM", plate.UnitFrame or plate, "TOP", 0, 8)
    mark:SetFrameLevel(plate:GetFrameLevel() + 12)
    mark.glow = mark:CreateTexture(nil, "BACKGROUND")
    mark.glow:SetPoint("CENTER")
    mark.glow:SetSize(SIZE + 14, SIZE + 14)
    mark.glow:SetAtlas("UI-QuestPoiCampaign-OuterGlow")
    mark.glow:SetVertexColor(1, .82, .3, .55)
    mark.icon = mark:CreateTexture(nil, "OVERLAY")
    mark.icon:SetAllPoints(mark)
    mark:Hide()
    marks[plate] = mark
    return mark
end

local function Plate(unit)
    local plate = Call(C_NamePlate, "GetNamePlateForUnit", unit)
    return type(plate) == "table" and plate or nil
end

local function Hide(unit)
    local plate = shown[unit]
    if plate and marks[plate] then marks[plate]:Hide() end
    shown[unit] = nil
end

local RARE_CLASS = { rare = true, rareelite = true }

-- Returns the wanted item for a nameplate unit, or true for a classified
-- rare in "rare" mode, or nil.
local function Match(unit)
    if not (next(wantGUID) or Settings().vignetteRadarNameplateMarkerWho == "rare") then return nil end
    local guid = Text(Call(_G, "UnitGUID", unit))
    if guid then
        local item = wantGUID[guid]
        if item then return item end
        local npc = Marker.NpcFromGUID(guid)
        if npc and wantNPC[npc] then return wantNPC[npc] end
    end
    if Settings().vignetteRadarNameplateMarkerWho == "rare" then
        local class = Text(Call(_G, "UnitClassification", unit))
        if class and RARE_CLASS[class] then return true end
    end
    return nil
end

function Marker.Refresh(unit)
    if type(unit) ~= "string" then return end
    Hide(unit)
    if Settings().vignetteRadarNameplateMarker ~= true then return end
    local item = Match(unit)
    if not item then return end
    local plate = Plate(unit)
    if not plate then return end
    local mark = Mark(plate)
    local points = addon.VignetteRadarPoints
    local subject = type(item) == "table" and item or { category = "rare" }
    if points then points.ApplyIcon(mark.icon, nil, subject) end
    local scale = Number(Settings().vignetteRadarNameplateMarkerScale) or 1
    mark:SetSize(SIZE * scale, SIZE * scale)
    mark:Show()
    shown[unit] = plate
    Trace("marked %s (%s)", unit, type(item) == "table" and tostring(Text(item.name)) or "classified rare")
end

function Marker.Rescan()
    for unit in pairs(shown) do Hide(unit) end
    local plates = Call(C_NamePlate, "GetNamePlates")
    if type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        local unit = Text(Field(plate, "namePlateUnitToken"))
        if unit then Marker.Refresh(unit) end
    end
end

-- Rebuild the wanted set; rescan the visible plates only when it changed.
function Marker.Update()
    local guids, npcs = Marker.Wanted()
    local keys, guidCount = {}, 0
    for guid in pairs(guids) do keys[#keys + 1] = guid; guidCount = guidCount + 1 end
    for npc in pairs(npcs) do keys[#keys + 1] = tostring(npc) end
    table.sort(keys)
    local db = Settings()
    local who = db.vignetteRadarNameplateMarkerWho
    local sig = tostring(db.vignetteRadarNameplateMarker) .. ":" .. tostring(who) .. ":" .. table.concat(keys, ",")
    wantGUID, wantNPC = guids, npcs
    if sig == signature then return false end
    signature = sig
    Trace("wanted %d guids / %d npcs (%s)", guidCount, #keys - guidCount, tostring(who))
    Marker.Rescan()
    return true
end

function Marker.Configure()
    signature = ""
    Marker.Update()
end

local bus = addon.Bus
if bus then
    bus.On("NAME_PLATE_UNIT_ADDED", function(_, unit) Marker.Refresh(unit) end)
    bus.On("NAME_PLATE_UNIT_REMOVED", function(_, unit) Hide(unit) end)
    bus.On("FOCUS_CHANGED", function() Marker.Update() end, { coalesce = true })
    bus.On("POINTS_CHANGED", function() Marker.Update() end, { coalesce = true })
end

return Marker
