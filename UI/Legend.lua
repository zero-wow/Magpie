local _, addon = ...
if type(addon) ~= "table" then return end

local PANEL_W, PANEL_H = 232, 446
local MARKER_VISIBLE_ROWS, MARKER_ROW_STEP = 8, 25
local QUEST_PANEL_W, QUEST_VISIBLE_ROWS = 224, 8
local QUEST_ROW_H, QUEST_ROW_STEP = 22, 26
local QUEST_DIAMOND_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga"
local QUEST_HOLLOW_DIAMOND_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\quest-diamond-hollow.tga"
local QUEST_HOLLOW_SIZE = 13 * 26 / 30
local ACCENT = { 0.05, 0.82, 0.62 }
local SKULL_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local UNPACK = unpack or table.unpack

local CATEGORY_ORDER = { "rare", "treasure", "event", "other" }
local CATEGORIES = {
    rare = { label = "Rare / Boss", color = { 0.78, 0.88, 1.00 } },
    treasure = { label = "Treasure", color = { 1.00, 0.68, 0.16 } },
    event = { label = "Events", color = { 0.67, 0.42, 1.00 } },
    other = { label = "Other Detections", color = { 0.66, 0.72, 0.76 } },
    quest = { label = "QUEST", color = { 1.00, 0.74, 0.27 } },
    accent = { label = "ACCENT", color = { 0.05, 0.82, 0.62 } },
}
local MAP_NOTES = {
    { kind = "treasure", label = "Treasure", color = "treasure" },
    { kind = "mob", label = "Mob", color = "rare" },
    { kind = "item", label = "Item", color = "event" },
    { kind = "note", label = "Other note", color = "other" },
    { kind = "entrance", label = "Cave entry", color = "accent" },
    { kind = "guide", label = "Guide step", color = "quest" },
}
local TRAIL_STYLES = addon.VignetteRadarTrailStyleByID or {
    dashes = { label="Dashes", segments={{-3.5,0,3.5,0,2.5}} },
    ticks = { label="Ticks", segments={{0,-3.5,0,3.5,2}} },
    dots = { label="Dots", dot=5 },
}

local fallbackSettings = {}
local panel
local attachedTo
local markerPanel, markerEntries, markerOffset, markerMode = nil, {}, 0, "types"
local questPanel, questAttachedTo, questEntries = nil, nil, {}
local questOffset = 0
local changeCallback

local API = {}
addon.VignetteRadarLegend = API

local function Settings()
    if type(addon.GetSettings) == "function" then
        local ok, settings = pcall(addon.GetSettings)
        if ok and type(settings) == "table" then return settings end
    end
    return fallbackSettings
end

local function CategoryKey(category)
    if type(category) == "string" then
        category = category:lower()
        if CATEGORIES[category] then return category end
    end
    return "other"
end

function API.ApplyDefaults(settings)
    settings = type(settings) == "table" and settings or Settings()
    if type(settings.vignetteRadarCategories) ~= "table" then
        settings.vignetteRadarCategories = {}
    end
    local enabled = settings.vignetteRadarCategories
    for _, category in ipairs(CATEGORY_ORDER) do
        if type(enabled[category]) ~= "boolean" then enabled[category] = true end
    end
    local highlight = settings.vignetteRadarHighlight
    if type(highlight) ~= "string" then
        settings.vignetteRadarHighlight = nil
    else
        highlight = highlight:lower()
        if not CATEGORIES[highlight] or enabled[highlight] ~= true then
            settings.vignetteRadarHighlight = nil
        else
            settings.vignetteRadarHighlight = highlight
        end
    end
    return settings
end

function API.IsCategoryEnabled(category)
    local settings = API.ApplyDefaults()
    return settings.vignetteRadarCategories[CategoryKey(category)] == true
end

function API.GetHighlight()
    return API.ApplyDefaults().vignetteRadarHighlight
end

function API.ColorFor(category)
    if addon.VignetteRadarStyle then return addon.VignetteRadarStyle.Color(CategoryKey(category)) end
    local color = CATEGORIES[CategoryKey(category)].color
    return color[1], color[2], color[3]
end

-- A disabled category is hidden. Enabled categories outside the spotlight remain
-- visible enough to preserve spatial context without competing with the focus.
function API.OpacityFor(category)
    category = CategoryKey(category)
    local settings = API.ApplyDefaults()
    if settings.vignetteRadarCategories[category] ~= true then return 0 end
    local highlight = settings.vignetteRadarHighlight
    if highlight and highlight ~= category then return 0.18 end
    return 1
end

function API.DotStyle(category)
    category = CategoryKey(category)
    local red, green, blue = API.ColorFor(category)
    return API.IsCategoryEnabled(category), red, green, blue, API.OpacityFor(category), category
end

-- Keep the meaning of a mark separate from its color and category. A world-map
-- vignette is game data, but it is not proof that the object is active nearby.
function API.VignetteSource(target)
    if type(target) ~= "table" then return nil end
    if target.sample then return "preview" end
    if target.stale then return "lastSeen" end
    return target.source == "worldMap" and "worldMap" or "minimap"
end

function API.QuestPointSource(quest)
    if type(quest) ~= "table" then return nil end
    if quest.learned then return "learnedObjective" end
    local step = quest.nextStep
    return type(step) == "table" and step.onCurrentMap == true
        and type(step.x) == "number" and type(step.y) == "number"
        and "objective" or "questMap"
end

local SOURCE_DESCRIPTION = {
    minimap = "Live Blizzard minimap detection.",
    worldMap = "Blizzard world-map location; nearby availability is not confirmed.",
    lastSeen = "Remembered detection; no longer live.",
    preview = "Layout preview; not a live detection.",
    saved = "Saved map-pack location; not a live detection.",
    objective = "Blizzard's next quest waypoint on this map.",
    questMap = "Blizzard quest map point; it may represent a wider area.",
    learnedObjective = "Player-observed objective area from repeated completions; approximate.",
    estimated = "Soft circle: estimated location around a quest point; not a Blizzard quest area.",
    nativeArea = "Quest area drawn from Blizzard's map data.",
}

function API.SourceDescription(source)
    return SOURCE_DESCRIPTION[source]
end

local function Text(parent, size, value)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size, "")
    label:SetText(value or "")
    label:SetTextColor(0.88, 0.90, 0.92, 1)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then label:SetWordWrap(false) end
    return label
end

local function Surface(frame, red, green, blue, alpha, borderAlpha)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(red or 0.045, green or 0.052, blue or 0.06, alpha or 0.98)
    frame:SetBackdropBorderColor(1, 1, 1, borderAlpha or 0.13)
end

local function Tooltip(owner, title, body)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(body, 0.65, 0.76, 0.74, true)
    GameTooltip:Show()
end

local function AddPressState(button)
    button.press = button:CreateTexture(nil, "OVERLAY")
    button.press:SetAllPoints()
    button.press:SetColorTexture(1, 1, 1, 0.055)
    button.press:Hide()
    button:SetScript("OnMouseDown", function(self) self.press:Show() end)
    button:SetScript("OnMouseUp", function(self) self.press:Hide() end)
    button:SetScript("OnHide", function(self) self.press:Hide() end)
end

local function NotifyChanged()
    API.Refresh()
    if type(changeCallback) == "function" then
        pcall(changeCallback)
    elseif type(addon.RefreshVignetteRadar) == "function" then
        addon.RefreshVignetteRadar()
    end
end

function API.SetChangeCallback(callback)
    changeCallback = type(callback) == "function" and callback or nil
end

function API.SetCategoryEnabled(category, enabled)
    category = CategoryKey(category)
    local settings = API.ApplyDefaults()
    enabled = enabled == true
    if settings.vignetteRadarCategories[category] == enabled then return false end
    settings.vignetteRadarCategories[category] = enabled
    if not enabled and settings.vignetteRadarHighlight == category then
        settings.vignetteRadarHighlight = nil
    end
    NotifyChanged()
    return true
end

function API.SetHighlight(category)
    local settings = API.ApplyDefaults()
    if category == nil or category == "all" then
        category = nil
    else
        category = CategoryKey(category)
        settings.vignetteRadarCategories[category] = true
    end
    if settings.vignetteRadarHighlight == category then return false end
    settings.vignetteRadarHighlight = category
    NotifyChanged()
    return true
end

function API.SetMapNotesVisible(enabled)
    local settings = Settings()
    enabled = enabled == true
    if settings.vignetteRadarMapNotesVisible == enabled then return false end
    if enabled and settings.vignetteRadarPOISource == "none" then
        settings.vignetteRadarPOISource = "auto"
    end
    settings.vignetteRadarMapNotesVisible = enabled
    NotifyChanged()
    if addon.VignetteRadarAPI and addon.VignetteRadarAPI.Refresh then
        addon.VignetteRadarAPI.Refresh(true)
    end
    return true
end

function API.SetMapNoteTypeEnabled(kind, enabled)
    local valid = false
    for _, definition in ipairs(MAP_NOTES) do
        if definition.kind == kind then valid = true; break end
    end
    if not valid then return false end
    local settings = Settings()
    if type(settings.vignetteRadarPOITypes) ~= "table" then
        settings.vignetteRadarPOITypes = {}
    end
    enabled = enabled == true
    local wasVisible = settings.vignetteRadarMapNotesVisible == true
    local wasEnabled = settings.vignetteRadarPOITypes[kind] ~= false
    if enabled and not wasVisible then
        settings.vignetteRadarMapNotesVisible = true
        if settings.vignetteRadarPOISource == "none" then
            settings.vignetteRadarPOISource = "auto"
        end
    end
    if wasEnabled == enabled and wasVisible == (settings.vignetteRadarMapNotesVisible == true) then
        return false
    end
    settings.vignetteRadarPOITypes[kind] = enabled
    NotifyChanged()
    if addon.VignetteRadarAPI and addon.VignetteRadarAPI.Refresh then
        addon.VignetteRadarAPI.Refresh(true)
    end
    return true
end

local function CreateCategoryRow(parent, category, index)
    local definition = CATEGORIES[category]
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(PANEL_W - 18, 23)
    row:SetPoint("TOPLEFT", 9, -53 - ((index - 1) * 27))
    Surface(row, 0.065, 0.073, 0.082, 0.98, 0.10)
    row.category = category

    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetPoint("TOPLEFT", 1, -1)
    row.selection:SetPoint("BOTTOMRIGHT", -1, 1)
    row.selection:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.09)
    row.selection:Hide()

    row.hover = row:CreateTexture(nil, "ARTWORK")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 1, 1, 0.035)
    row.hover:Hide()

    row.swatchGlow = row:CreateTexture(nil, "ARTWORK")
    row.swatchGlow:SetSize(13, 13)
    row.swatchGlow:SetPoint("LEFT", 8, 0)
    row.swatchGlow:SetColorTexture(definition.color[1], definition.color[2], definition.color[3], 0.14)
    row.swatch = row:CreateTexture(nil, "OVERLAY")
    row.swatch:SetSize(7, 7)
    row.swatch:SetPoint("CENTER", row.swatchGlow, "CENTER")
    row.swatch:SetTexture(CIRCLE_TEXTURE)
    row.swatch:SetVertexColor(definition.color[1], definition.color[2], definition.color[3], 1)
    if category == "rare" then
        row.swatch:SetSize(13, 13)
        row.swatch:SetTexture(SKULL_TEXTURE)
        row.swatch:SetVertexColor(definition.color[1], definition.color[2], definition.color[3], 1)
        row.bossSwatch = row:CreateTexture(nil, "OVERLAY")
        row.bossSwatch:SetSize(13, 13)
        row.bossSwatch:SetPoint("LEFT", 21, 0)
        row.bossSwatch:SetTexture(SKULL_TEXTURE)
        row.bossSwatch:SetVertexColor(1, 0.18, 0.12, 1)
    elseif category == "treasure" and row.swatch.SetAtlas then
        row.swatch:SetSize(13, 13)
        row.swatch:SetAtlas("VignetteLoot")
        row.swatch:SetVertexColor(definition.color[1], definition.color[2], definition.color[3], 1)
    end

    row.label = Text(row, 10, definition.label)
    row.label:SetPoint("LEFT", category == "rare" and 39 or 29, 0)
    row.label:SetWidth(category == "rare" and 90 or 100)
    if category == "other" then addon.VignetteRadarStyle.SetFont(row.label, 9, "") end
    if row.label.SetMaxLines then row.label:SetMaxLines(1) end

    row.toggle = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.toggle:SetSize(42, 17)
    row.toggle:SetPoint("RIGHT", -4, 0)
    Surface(row.toggle, 0.025, 0.03, 0.035, 0.95, 0.14)
    row.toggle.label = Text(row.toggle, 8, "ON")
    row.toggle.label:SetAllPoints()
    row.toggle.label:SetJustifyH("CENTER")
    row.focusCue = Text(row, 7, "FOCUS")
    row.focusCue:SetSize(31, 12)
    row.focusCue:SetPoint("RIGHT", row.toggle, "LEFT", -4, 0)
    row.focusCue:SetJustifyH("CENTER")
    row.focusCue:Hide()
    AddPressState(row)
    AddPressState(row.toggle)

    row:SetScript("OnClick", function()
        if API.GetHighlight() == category then API.SetHighlight(nil) else API.SetHighlight(category) end
    end)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        Tooltip(self, definition.label, category == "rare"
            and "Silver skull: rare enemy. Red skull: world boss. Click this row to spotlight both; click again to clear. Other shown types dim."
            or "Click this row to spotlight this live type; click again to clear. Other shown types dim.")
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        if GameTooltip then GameTooltip:Hide() end
    end)
    row.toggle:SetScript("OnClick", function()
        API.SetCategoryEnabled(category, not API.IsCategoryEnabled(category))
    end)
    row.toggle:SetScript("OnEnter", function(self)
        Tooltip(self, "Show " .. definition.label,
            category == "rare" and "Show or hide both rare enemies and world bosses. This button does not set the spotlight."
            or "Show or hide this live type. This button does not set the spotlight.")
    end)
    row.toggle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

local function GuideLabel(parent, value, x, y, width, size)
    local label = Text(parent, size or 9, value)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    label:SetSize(width, 16)
    if label.SetMaxLines then label:SetMaxLines(1) end
    return label
end

local function SectionRule(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -y)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, .08)
    return line
end

local function GuideRow(parent, label, x, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(103, 18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    row.label = GuideLabel(row, label, 20, 1, 82, 9)
    return row
end

local function Circle(parent, size, layer)
    local dot = parent:CreateTexture(nil, layer or "ARTWORK")
    dot:SetSize(size, size)
    dot:SetPoint("LEFT", parent, "LEFT", 7, 0)
    dot:SetTexture(CIRCLE_TEXTURE)
    return dot
end

local function CreateMapNote(parent, definition, index)
    local x = index % 2 == 1 and 10 or 120
    local y = 189 + math.floor((index - 1) / 2) * 22
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(103, 18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    row.label = GuideLabel(row, definition.label, 20, 1, 82, 9)
    row.kind, row.colorSlot = definition.kind, definition.color
    row.rim = Circle(row, 9)
    row.core = row:CreateTexture(nil, "OVERLAY")
    row.core:SetSize(3, 3)
    row.core:SetPoint("CENTER", row.rim, "CENTER")
    row.core:SetTexture(CIRCLE_TEXTURE)
    row.core:SetVertexColor(.02, .03, .035, .95)
    AddPressState(row)
    row:SetScript("OnClick", function()
        local settings = Settings()
        local enabled = settings.vignetteRadarMapNotesVisible ~= true
            or type(settings.vignetteRadarPOITypes) == "table"
                and settings.vignetteRadarPOITypes[definition.kind] == false
        API.SetMapNoteTypeEnabled(definition.kind, enabled)
    end)
    row:SetScript("OnEnter", function(self)
        Tooltip(self, definition.label .. " Map Note",
            "Click to show or hide this map-note type. " .. API.SourceDescription("saved"))
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

local function CreateOtherGuide(parent, label, x, y, symbol)
    local row = GuideRow(parent, label, x, y)
    row.symbol = symbol
    if symbol == "quest" then
        row.rim = Circle(row, 11)
        row.rim:SetTexture("Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga")
        row.rim:SetVertexColor(.04, .04, .03, .9)
        row.halo = row:CreateTexture(nil, "BACKGROUND")
        row.halo:SetSize(16, 16)
        row.halo:SetPoint("CENTER", row.rim, "CENTER")
        row.halo:SetTexture(CIRCLE_TEXTURE)
        row.fill = row:CreateTexture(nil, "OVERLAY")
        row.fill:SetSize(8, 8)
        row.fill:SetPoint("CENTER", row.rim, "CENTER")
        row.fill:SetTexture("Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga")
    elseif symbol == "area" then
        row.fill = row:CreateTexture(nil, "ARTWORK")
        row.fill:SetSize(11, 11)
        row.fill:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.fill:SetTexture(CIRCLE_TEXTURE)
    elseif symbol == "trail" then
        row.dots = {}
        row.marks = {}
        row.extraMarks = {}
        for index = 1, 3 do
            local dot = row:CreateTexture(nil, "ARTWORK")
            dot:SetSize(4, 4)
            dot:SetPoint("LEFT", row, "LEFT", 3 + index * 4, 0)
            dot:SetTexture(CIRCLE_TEXTURE)
            row.dots[index] = dot
            local mark = row:CreateLine(nil, "ARTWORK")
            mark:SetThickness(1.7)
            mark:Hide()
            row.marks[index] = mark
            row.extraMarks[index] = {}
            for part = 1, 3 do
                local extra = row:CreateLine(nil, "ARTWORK")
                extra:Hide()
                row.extraMarks[index][part] = extra
            end
        end
    elseif symbol == "stale" then
        row.lines = {}
        local corners = { { 12, 5 }, { 17, 0 }, { 12, -5 }, { 7, 0 } }
        for index = 1, 4 do
            local line = row:CreateLine(nil, "ARTWORK")
            local first, last = corners[index], corners[index % 4 + 1]
            line:SetThickness(1.2)
            line:SetStartPoint("LEFT", row, first[1], first[2])
            line:SetEndPoint("LEFT", row, last[1], last[2])
            row.lines[index] = line
        end
    elseif symbol == "edge" then
        row.fill = Circle(row, 7)
        row.tip = row:CreateLine(nil, "OVERLAY")
        row.tip:SetThickness(1.3)
        row.tip:SetStartPoint("LEFT", row, 14, 0)
        row.tip:SetEndPoint("LEFT", row, 20, 0)
    else
        row.fill = Circle(row, 10)
        if symbol == "route" then
            row.number = Text(row, 8, "1")
            row.number:SetSize(10, 10)
            row.number:SetPoint("CENTER", row.fill, "CENTER")
            row.number:SetJustifyH("CENTER")
        end
    end
    return row
end

local function FrameValue(frame, method)
    if not (frame and type(frame[method]) == "function") then return nil end
    local value = frame[method](frame)
    return type(value) == "number" and value or nil
end

-- Puts back a radar panel that Attach moved to make room, unless the player
-- has dragged it since. holder.shiftedAnchor stores the original spot.
local function RestoreShift(holder)
    if not (holder and holder.shiftedAnchor) then return end
    local saved = holder.shiftedAnchor
    holder.shiftedAnchor = nil
    local anchor = saved.anchor
    local currentLeft = FrameValue(anchor, "GetLeft")
    if currentLeft and math.abs(currentLeft - saved.shiftedLeft) <= 2 then
        anchor:ClearAllPoints()
        anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", saved.left,
            (saved.top * saved.scale - saved.screenHeight) / saved.scale)
    end
end

local function Attach(anchor)
    if not panel then return end
    -- Beside the radar it is not free: the next free placement starts over.
    panel._vrFree = nil
    panel:ClearAllPoints()
    local screenWidth = FrameValue(UIParent, "GetWidth")
    local screenHeight = FrameValue(UIParent, "GetHeight")
    local anchorScale = (FrameValue(anchor, "GetEffectiveScale") or 1)
        / (FrameValue(UIParent, "GetEffectiveScale") or 1)
    local left, right = FrameValue(anchor, "GetLeft"), FrameValue(anchor, "GetRight")
    local top, bottom = FrameValue(anchor, "GetTop"), FrameValue(anchor, "GetBottom")
    if left then left = left * anchorScale end
    if right then right = right * anchorScale end
    if top then top = top * anchorScale end
    if bottom then bottom = bottom * anchorScale end
    if anchor and screenWidth and right and screenWidth - right >= PANEL_W + 12 then
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    elseif anchor and left and left >= PANEL_W + 12 then
        panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
    elseif anchor and bottom and bottom >= PANEL_H + 12 then
        panel:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
    elseif anchor and top and screenHeight and screenHeight - top >= PANEL_H + 12 then
        panel:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
    else
        local anchorWidth = left and right and right - left
            or ((FrameValue(anchor, "GetWidth") or 0) * anchorScale)
        -- A centered Squat panel can leave no side or vertical space. Move the
        -- whole panel only when it is the anchor, keeping the saved position intact.
        if anchor and anchorWidth and anchorWidth >= 100 and left and top and screenWidth and screenHeight
            and anchorWidth + PANEL_W + 24 <= screenWidth and not panel.shiftedAnchor
            and type(anchor.ClearAllPoints) == "function" and type(anchor.SetPoint) == "function" then
            local shiftedLeft = math.max(8, screenWidth - PANEL_W - 16 - anchorWidth)
            -- Remember where the radar was so hiding this panel puts it back.
            panel.shiftedAnchor = { anchor = anchor, left = left / anchorScale,
                top = top / anchorScale, scale = anchorScale,
                shiftedLeft = shiftedLeft / anchorScale, screenHeight = screenHeight }
            anchor:ClearAllPoints()
            anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
                shiftedLeft / anchorScale, (top - screenHeight) / anchorScale)
            panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        elseif anchor then
            panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        else
            panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    attachedTo = anchor
end

local function CollectNameEntries()
    local features = addon.VignetteRadarFeatures
    local radar = addon.VignetteRadarAPI
    local raw = radar and radar.GetRawTargets and radar.GetRawTargets() or {}
    local hidden = features and features.GetHiddenMarkerNames and features.GetHiddenMarkerNames() or {}
    local entries, seen = {}, {}
    for _, target in ipairs(raw) do
        local name = type(target.name) == "string" and target.name or nil
        local category = type(target.category) == "string" and target.category or "other"
        if name and name ~= "" and not target.sample then
            local key = category:lower() .. ":" .. name:lower()
            if not seen[key] then
                seen[key] = true
                entries[#entries + 1] = { name = name, category = category, key = key,
                    atlasName = target.atlasName }
            end
        end
    end
    local notes = radar and radar.GetRawMapNotes and radar.GetRawMapNotes() or {}
    for _, note in ipairs(notes) do
        local name = type(note.name) == "string" and note.name or nil
        local category = type(note.kind) == "string" and "map:" .. note.kind:lower() or nil
        if name and name ~= "" and category then
            local key = category .. ":" .. name:lower()
            if not seen[key] then
                seen[key] = true
                local icon = type(note.icon) == "table" and note.icon or nil
                entries[#entries + 1] = { name = name, category = category, key = key,
                    texture = icon and icon.texture, texCoord = icon and icon.texCoord,
                    color = icon and icon.color }
            end
        end
    end
    for key, name in pairs(hidden) do
        if type(key) == "string" and type(name) == "string" and not seen[key] then
            local category = key:match("^(map:[^:]+):") or key:match("^([^:]+):") or "other"
            entries[#entries + 1] = { name = name, category = category, key = key }
        end
    end
    table.sort(entries, function(left, right)
        if left.name:lower() ~= right.name:lower() then
            return left.name:lower() < right.name:lower()
        end
        return left.key < right.key
    end)
    return entries
end

local function MarkerTypeLabel(atlas, fallback)
    if type(atlas) ~= "string" or atlas == "" then return fallback or "Other Icon" end
    local lower = atlas:lower()
    local vendor = lower:find("vendor", 1, true) or lower:find("vender", 1, true)
        or lower:find("merchant", 1, true)
    local decor = lower:find("decor", 1, true) or lower:find("housing", 1, true)
    local item = lower:find("item", 1, true) or lower:find("goods", 1, true)
    if decor and vendor and item then
        return "Decor Vendor Items"
    elseif decor and vendor then
        return "Decor Vendors"
    elseif vendor and item then
        return "Vendor Items"
    elseif vendor then
        return "Vendors"
    elseif lower:find("mail", 1, true) then
        return "Mailboxes"
    elseif lower == "vignetteloot" then return "Treasure"
    elseif lower == "vignettekill" then return "Rare"
    elseif lower == "vignettekillelite" then return "Rare Elite"
    end
    local label = atlas:gsub("^Vignette", ""):gsub("([a-z])([A-Z])", "%1 %2")
        :gsub("[-_]", " "):gsub("[Ii]con$", "")
        :gsub("^%s+", ""):gsub("%s+$", "")
    return label ~= "" and label or fallback or "Other Icon"
end

local function CollectTypeEntries()
    local features = addon.VignetteRadarFeatures
    local radar = addon.VignetteRadarAPI
    local hidden = features and features.GetHiddenMarkerTypes and features.GetHiddenMarkerTypes() or {}
    local entries, seen = {}, {}
    for _, target in ipairs(radar and radar.GetRawTargets and radar.GetRawTargets() or {}) do
        local key = features and features.MarkerTypeKey and features.MarkerTypeKey(target)
        if key and not seen[key] and not target.sample then
            seen[key] = true
            entries[#entries + 1] = { typeKey = key,
                label = MarkerTypeLabel(target.atlasName, CATEGORIES[CategoryKey(target.category)].label),
                atlasName = target.atlasName, category = target.category }
        end
    end
    for _, note in ipairs(radar and radar.GetRawMapNotes and radar.GetRawMapNotes() or {}) do
        local key = features and features.MapNoteTypeKey and features.MapNoteTypeKey(note)
        if key and not seen[key] then
            seen[key] = true
            local icon = type(note.icon) == "table" and note.icon or nil
            local kind = type(note.kind) == "string" and note.kind or "note"
            local definition
            for _, candidate in ipairs(MAP_NOTES) do
                if candidate.kind == kind then definition = candidate; break end
            end
            local label = definition and definition.label or "Map Note"
            label = label:gsub("(%a)([%a]*)", function(first, rest)
                return first:upper() .. rest
            end)
            if icon and icon.texture then label = label .. " Icon" end
            entries[#entries + 1] = { typeKey = key, label = label,
                texture = icon and icon.texture, texCoord = icon and icon.texCoord,
                color = icon and icon.color,
                category = "map:" .. kind }
        end
    end
    for key, saved in pairs(hidden) do
        if type(key) == "string" and not seen[key] then
            local record = type(saved) == "table" and saved or {}
            entries[#entries + 1] = { typeKey = key,
                label = type(record.label) == "string" and record.label or key,
                atlasName = record.atlasName, texture = record.texture,
                texCoord = record.texCoord, color = record.color }
        end
    end
    table.sort(entries, function(left, right)
        if left.label:lower() ~= right.label:lower() then
            return left.label:lower() < right.label:lower()
        end
        return left.typeKey < right.typeKey
    end)
    return entries
end

local function RefreshMarkerRows()
    if not markerPanel then return end
    if addon.VignetteRadarControls then addon.VignetteRadarControls.RefreshPopupSurface(markerPanel) end
    markerEntries = markerMode == "types" and CollectTypeEntries() or CollectNameEntries()
    local count = #markerEntries
    markerOffset = math.max(0, math.min(markerOffset, math.max(0, count - MARKER_VISIBLE_ROWS)))
    local features = addon.VignetteRadarFeatures
    local style = addon.VignetteRadarStyle
    local red, green, blue = ACCENT[1], ACCENT[2], ACCENT[3]
    if style then red, green, blue = style.Color("accent") end
    markerPanel.title:SetTextColor(red, green, blue, 1)
    markerPanel.rule:SetColorTexture(red, green, blue, .18)
    markerPanel.count:SetText(count .. (markerMode == "types" and " TYPES" or " NAMES"))
    for mode, button in pairs(markerPanel.tabs) do
        local selected = mode == markerMode
        button.selection:SetColorTexture(red, green, blue, selected and .15 or 0)
        button.label:SetTextColor(selected and red or .68, selected and green or .75,
            selected and blue or .77, 1)
    end
    for index, row in ipairs(markerPanel.rows) do
        local entry = markerEntries[markerOffset + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local isHidden = markerMode == "types"
                and features and features.GetHiddenMarkerTypes
                    and features.GetHiddenMarkerTypes()[entry.typeKey] ~= nil
                or markerMode == "names" and features and features.IsMarkerNameHidden
                    and features.IsMarkerNameHidden(entry)
            row.name:SetText(markerMode == "types" and entry.label or entry.name)
            local atlasShown = entry.atlasName and row.icon.SetAtlas
                and pcall(row.icon.SetAtlas, row.icon, entry.atlasName)
            if not atlasShown and entry.texture then
                row.icon:SetTexture(entry.texture)
                if type(entry.texCoord) == "table" and #entry.texCoord == 4 then
                    row.icon:SetTexCoord(UNPACK(entry.texCoord))
                else row.icon:SetTexCoord(0, 1, 0, 1) end
            elseif not atlasShown then
                row.icon:SetTexture(CIRCLE_TEXTURE)
                row.icon:SetTexCoord(0, 1, 0, 1)
            end
            local color = type(entry.color) == "table" and entry.color or nil
            local r = color and type(color[1]) == "number" and color[1] or 1
            local g = color and type(color[2]) == "number" and color[2] or 1
            local b = color and type(color[3]) == "number" and color[3] or 1
            local a = color and type(color[4]) == "number" and color[4] or 1
            row.icon:SetVertexColor(r, g, b, a * (isHidden and .5 or 1))
            row.name:SetTextColor(isHidden and .55 or .84, isHidden and .60 or .89,
                isHidden and .62 or .90, 1)
            row.toggle.label:SetText(isHidden and "OFF" or "ON")
            row.toggle.label:SetTextColor(isHidden and .58 or red,
                isHidden and .60 or green, isHidden and .62 or blue, 1)
            row:SetAlpha(isHidden and .78 or 1)
        end
    end
    markerPanel.status:SetText(count == 0 and "No map markers here"
        or count > MARKER_VISIBLE_ROWS and (markerOffset + 1) .. "–"
            .. math.min(count, markerOffset + MARKER_VISIBLE_ROWS) .. " of " .. count .. " · Scroll"
        or markerMode == "types" and "Toggle an icon type" or "Toggle a name")
end

local function EnsureMarkerPanel()
    if markerPanel then return markerPanel end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end
    markerPanel = CreateFrame("Frame", "VignetteRadarMarkerLegendPanel", UIParent, "BackdropTemplate")
    markerPanel:SetSize(PANEL_W, 316)
    if markerPanel.SetFrameStrata then markerPanel:SetFrameStrata("DIALOG") end
    if markerPanel.SetClampedToScreen then markerPanel:SetClampedToScreen(true) end
    if markerPanel.EnableMouse then markerPanel:EnableMouse(true) end
    Surface(markerPanel)
    if addon.VignetteRadarControls then addon.VignetteRadarControls.PopupSurface(markerPanel) end
    markerPanel.title = Text(markerPanel, 11, "MAP MARKERS")
    markerPanel.title:SetPoint("TOPLEFT", 10, -10)
    markerPanel.count = Text(markerPanel, 8, "0 TYPES")
    markerPanel.count:SetPoint("TOPRIGHT", -10, -11)
    markerPanel.count:SetJustifyH("RIGHT")
    markerPanel.count:SetWidth(65)
    markerPanel.rule = SectionRule(markerPanel, 32)
    markerPanel.tabs = {}
    for index, mode in ipairs({ "types", "names" }) do
        local button = CreateFrame("Button", nil, markerPanel, "BackdropTemplate")
        button:SetSize(102, 21)
        button:SetPoint("TOPLEFT", 10 + (index - 1) * 110, -39)
        Surface(button, .03, .038, .043, .96, .16)
        button.selection = button:CreateTexture(nil, "BACKGROUND")
        button.selection:SetAllPoints()
        button.label = Text(button, 9, mode == "types" and "ICON TYPES" or "NAMES")
        button.label:SetAllPoints()
        button.label:SetJustifyH("CENTER")
        AddPressState(button)
        button:SetScript("OnClick", function()
            markerMode, markerOffset = mode, 0
            RefreshMarkerRows()
        end)
        markerPanel.tabs[mode] = button
    end
    markerPanel.rows = {}
    local function Scroll(_, delta)
        markerOffset = math.max(0, math.min(math.max(0, #markerEntries - MARKER_VISIBLE_ROWS),
            markerOffset - delta))
        RefreshMarkerRows()
    end
    if markerPanel.EnableMouseWheel then markerPanel:EnableMouseWheel(true) end
    markerPanel:SetScript("OnMouseWheel", Scroll)
    for index = 1, MARKER_VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, markerPanel)
        row:SetSize(PANEL_W - 20, 22)
        row:SetPoint("TOPLEFT", 10, -68 - (index - 1) * MARKER_ROW_STEP)
        if row.EnableMouseWheel then row:EnableMouseWheel(true) end
        row:SetScript("OnMouseWheel", Scroll)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 7, 0)
        row.name = Text(row, 9, "")
        row.name:SetPoint("LEFT", 29, 0)
        row.name:SetWidth(127)
        if row.name.SetMaxLines then row.name:SetMaxLines(1) end
        row.toggle = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.toggle:SetSize(42, 18)
        row.toggle:SetPoint("RIGHT", -4, 0)
        Surface(row.toggle, .03, .038, .043, .96, .16)
        row.toggle.label = Text(row.toggle, 8, "ON")
        row.toggle.label:SetAllPoints()
        row.toggle.label:SetJustifyH("CENTER")
        AddPressState(row.toggle)
        row.toggle:SetScript("OnClick", function()
            local entry = row.entry
            local features = addon.VignetteRadarFeatures
            if not (entry and features) then return end
            if markerMode == "types" then
                if not features.SetMarkerTypeHidden then return end
                features.SetMarkerTypeHidden(entry,
                    features.GetHiddenMarkerTypes()[entry.typeKey] == nil)
            else
                if not features.SetMarkerNameHidden then return end
                features.SetMarkerNameHidden(entry, not features.IsMarkerNameHidden(entry))
            end
            local radar = addon.VignetteRadarAPI
            if radar and radar.Refresh then radar.Refresh(true) else NotifyChanged() end
            RefreshMarkerRows()
        end)
        row.toggle:SetScript("OnEnter", function(self)
            if not row.entry then return end
            if markerMode == "types" then
                Tooltip(self, row.entry.label, "Show or hide every marker using this icon type.")
            else
                Tooltip(self, row.entry.name,
                    row.entry.category:match("^map:")
                        and "Show or hide matching saved map notes across maps."
                        or "Show or hide matching live detections across maps.")
            end
        end)
        row.toggle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        markerPanel.rows[index] = row
    end
    markerPanel.back = addon.VignetteRadarIconButton.Create(markerPanel, "back",
        { size = 20, label = "Back To Legend" })
    markerPanel.back:SetPoint("BOTTOMLEFT", 10, 8)
    markerPanel.back:SetScript("OnClick", function()
        markerPanel:Hide()
        if panel then API.Refresh(); panel:Show() end
    end)
    markerPanel.status = Text(markerPanel, 8, "No map markers here")
    markerPanel.status:SetPoint("BOTTOMRIGHT", -10, 13)
    markerPanel.status:SetWidth(136)
    markerPanel.status:SetJustifyH("RIGHT")
    markerPanel.status:SetTextColor(.53, .62, .63, 1)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarMarkerLegendPanel"
    end
    markerPanel:Hide()
    return markerPanel
end

local function EnsurePanel()
    if panel then return panel end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end

    panel = CreateFrame("Frame", "VignetteRadarLegendPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_W, PANEL_H)
    if panel.SetFrameStrata then panel:SetFrameStrata("DIALOG") end
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    if panel.EnableMouse then panel:EnableMouse(true) end
    Surface(panel)
    if addon.VignetteRadarControls then addon.VignetteRadarControls.PopupSurface(panel) end

    panel.title = Text(panel, 11, "LEGEND")
    panel.title:SetPoint("TOPLEFT", 10, -10)
    panel.title:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)

    panel.divider = panel:CreateTexture(nil, "ARTWORK")
    panel.divider:SetPoint("TOPLEFT", 9, -45)
    panel.divider:SetPoint("TOPRIGHT", -9, -45)
    panel.divider:SetHeight(1)
    panel.divider:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)

    -- Active (underlined) while a spotlight is on, so there is something to clear.
    panel.all = addon.VignetteRadarIconButton.Create(panel, "refresh", { size = 20,
        label = "Clear Spotlight",
        tooltip = "Return shown live types to equal strength. Hidden types stay hidden.",
        isActive = function() return API.GetHighlight() ~= nil end,
        onClick = function() API.SetHighlight(nil) end })
    panel.all:SetPoint("TOPRIGHT", -20, -6)

    panel.liveHint = Text(panel, 8, "CLICK ROW TO SPOTLIGHT")
    panel.liveHint:SetPoint("TOPLEFT", 10, -29)
    panel.liveHint:SetSize(163, 12)
    panel.liveHint:SetTextColor(.62, .72, .72, 1)
    panel.showHint = Text(panel, 8, "SHOW")
    panel.showHint:SetPoint("TOPRIGHT", -11, -29)
    panel.showHint:SetSize(42, 12)
    panel.showHint:SetJustifyH("CENTER")
    panel.showHint:SetTextColor(.62, .72, .72, 1)

    panel.rows = {}
    for index, category in ipairs(CATEGORY_ORDER) do
        panel.rows[category] = CreateCategoryRow(panel, category, index)
    end

    panel.mapRule = SectionRule(panel, 165)
    panel.mapHeading = GuideLabel(panel, "MAP NOTES", 10, 168, PANEL_W - 72, 9)
    panel.mapHeading:SetHeight(12)
    panel.mapHeading:SetTextColor(.68, .75, .77, 1)
    -- Active (underlined) while map notes show; the column header stays "SHOW".
    panel.mapToggle = addon.VignetteRadarIconButton.Create(panel, "eye", { size = 20,
        label = "Map Notes",
        tooltip = "Show or hide saved map-pack markers. Click a note type below to filter it.",
        onClick = function()
            API.SetMapNotesVisible(Settings().vignetteRadarMapNotesVisible ~= true)
        end })
    panel.mapToggle:SetPoint("TOPRIGHT", -20, -167)
    panel.mapNotes = {}
    for index, definition in ipairs(MAP_NOTES) do
        panel.mapNotes[definition.kind] = CreateMapNote(panel, definition, index)
    end
    panel.mapCaption = GuideLabel(panel, "Hollow notes = saved, not live", 10, 255, PANEL_W - 20, 8)
    panel.mapCaption:SetHeight(10)
    panel.mapCaption:SetTextColor(.5, .57, .59, 1)

    panel.otherRule = SectionRule(panel, 272)
    panel.otherHeading = GuideLabel(panel, "SYMBOL KEY · REFERENCE ONLY", 10, 277, PANEL_W - 20, 9)
    panel.otherHeading:SetHeight(12)
    panel.otherHeading:SetTextColor(.68, .75, .77, 1)
    panel.guides = {
        quest = CreateOtherGuide(panel, "Quest point", 10, 295, "quest"),
        area = CreateOtherGuide(panel, "Blizzard area", 120, 295, "area"),
        pin = CreateOtherGuide(panel, "Saved pin", 10, 317, "pin"),
        route = CreateOtherGuide(panel, "Route stop", 120, 317, "route"),
        trail = CreateOtherGuide(panel, "Travel trail", 10, 339, "trail"),
        stale = CreateOtherGuide(panel, "Last seen", 120, 339, "stale"),
        edge = CreateOtherGuide(panel, "Off-range cue", 10, 361, "edge"),
    }
    panel.guides.quest:EnableMouse(true)
    panel.guides.quest:SetScript("OnEnter", function(self)
        Tooltip(self, "Quest Point", "A diamond marks a Blizzard quest point or next waypoint. A soft circle around it is only an estimated search radius.")
    end)
    panel.guides.quest:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.guides.area:EnableMouse(true)
    panel.guides.area:SetScript("OnEnter", function(self)
        Tooltip(self, "Blizzard Quest Area", API.SourceDescription("nativeArea"))
    end)
    panel.guides.area:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.markerButton = CreateFrame("Button", nil, panel, "BackdropTemplate")
    panel.markerButton:SetSize(PANEL_W - 20, 24)
    panel.markerButton:SetPoint("TOPLEFT", 10, -390)
    Surface(panel.markerButton, .03, .038, .043, .96, .16)
    panel.markerButton.label = Text(panel.markerButton, 9, "MANAGE MAP MARKERS")
    panel.markerButton.label:SetAllPoints()
    panel.markerButton.label:SetJustifyH("CENTER")
    AddPressState(panel.markerButton)
    panel.markerButton:SetScript("OnClick", function() API.ToggleMarkers() end)
    panel.markerButton:SetScript("OnEnter", function(self)
        Tooltip(self, "Manage Map Markers",
            "Hide whole icon types or individual names, including vendors and mailboxes.")
    end)
    panel.markerButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.footerRule = SectionRule(panel, 421)

    panel.status = Text(panel, 8, "SPOTLIGHT OFF · SHOWN TYPES EQUAL")
    panel.status:SetPoint("BOTTOMLEFT", 10, 7)
    panel.status:SetTextColor(0.48, 0.55, 0.56, 1)
    -- Detach/dock: a free legend you can drag, or the radar's tray.
    local tray = addon.VignetteRadarTray
    if tray and tray.CreateDetachButton then
        panel.detach = tray.CreateDetachButton(panel,
            function() return addon.GetSettings().vignetteRadarLegendDetached == true end,
            function() API.SetDetached(addon.GetSettings().vignetteRadarLegendDetached ~= true) end)
        panel.detach:SetPoint("TOPLEFT", 104, -6)
    end
    local function IsDetached() return addon.GetSettings().vignetteRadarLegendDetached == true end
    if tray and tray.RegisterPanel then
        -- Detached, a position lock beside the detach icon (the shared
        -- per-panel lock, key "legend"): locked, it does not drag.
        panel.moveLock = tray.CreateLockButton(panel, {
            labels = { "Position Unlocked", "Position Locked" },
            tips = { "Drag the legend to move it. Lock to stop it moving.", "Unlock to move it again." },
            isLocked = function() return tray.IsPanelLocked("legend") end,
            setLocked = function(value) tray.SetPanelLocked("legend", value) end })
        panel.moveLock:SetPoint("LEFT", panel.detach, "RIGHT", 4, 0)
        panel.moveLock:SetShown(IsDetached())
        -- On the shared panel system (UI/Tray.lua): docked = the radar's
        -- tray, detached = a free panel with a saved spot, kept on screen.
        -- Its old spot (vignetteRadarLegendPosition) moves over once.
        tray.RegisterPanel(panel, { key = "legend", label = "the Legend", drawer = true, ownControls = true,
            keepWidth = true, strata = "DIALOG", legacySpot = "vignetteRadarLegendPosition",
            isDetached = IsDetached, canDrag = IsDetached,
            redock = function() addon.GetSettings().vignetteRadarLegendDetached = false end,
            refresh = function()
                if panel.moveLock then panel.moveLock:SetShown(IsDetached()) end
                if panel.detach then panel.detach:RefreshDetach() end
                API.Reanchor()
            end })
    else
        if panel.SetMovable then panel:SetMovable(true) end
        if panel.RegisterForDrag then panel:RegisterForDrag("LeftButton") end
        panel:SetScript("OnDragStart", function(self)
            if IsDetached() and self.StartMoving then self:StartMoving() end
        end)
        panel:SetScript("OnDragStop", function(self)
            if self.StopMovingOrSizing then self:StopMovingOrSizing() end
            if IsDetached() then
                local left, top = FrameValue(self, "GetLeft"), FrameValue(self, "GetTop")
                local height = FrameValue(UIParent, "GetHeight")
                if left and top and height then
                    addon.GetSettings().vignetteRadarLegendPosition = { x = left, y = top - height }
                end
            end
        end)
    end
    -- A popup legend that had to move the radar for room puts it back on close.
    panel:SetScript("OnHide", function(self) RestoreShift(self) end)
    -- WoW creates frames shown by default. Keep the lazy panel closed until the
    -- radar's legend button explicitly opens it.
    panel:Hide()
    return panel
end

local function QuestColor(entry)
    local palette = addon.VignetteRadarQuestColors
    local color = Settings().vignetteRadarQuestColors and palette and palette[entry.colorSlot or 1]
    if color then return color[1], color[2], color[3] end
    if addon.VignetteRadarStyle then return addon.VignetteRadarStyle.Color("quest") end
    return 1, .74, .27
end

local function RestoreQuestShift() RestoreShift(questPanel) end

local function AttachQuest(anchor, owner)
    if not questPanel then return end
    questPanel:ClearAllPoints()
    local screenWidth, screenHeight = FrameValue(UIParent, "GetWidth"), FrameValue(UIParent, "GetHeight")
    local parentScale = FrameValue(UIParent, "GetEffectiveScale") or 1
    local left, right = FrameValue(anchor, "GetLeft"), FrameValue(anchor, "GetRight")
    local top, bottom = FrameValue(anchor, "GetTop"), FrameValue(anchor, "GetBottom")
    local anchorScale = (FrameValue(anchor, "GetEffectiveScale") or 1) / parentScale
    if left then left = left * anchorScale end
    if right then right = right * anchorScale end
    if top then top = top * anchorScale end
    if bottom then bottom = bottom * anchorScale end
    if anchor and left and left < QUEST_PANEL_W + 12 and owner and screenWidth and screenHeight
        and not questPanel.shiftedAnchor then
        local ownerLeft, ownerRight = FrameValue(owner, "GetLeft"), FrameValue(owner, "GetRight")
        local ownerTop = FrameValue(owner, "GetTop")
        local ownerScale = (FrameValue(owner, "GetEffectiveScale") or 1) / parentScale
        local shift = QUEST_PANEL_W + 16 - left
        if ownerLeft and ownerRight and ownerTop and ownerRight * ownerScale + shift <= screenWidth - 8
            and type(owner.ClearAllPoints) == "function" and type(owner.SetPoint) == "function" then
            questPanel.shiftedAnchor = { anchor = owner, left = ownerLeft, top = ownerTop,
                scale = ownerScale, shiftedLeft = ownerLeft + shift / ownerScale,
                screenHeight = screenHeight }
            owner:ClearAllPoints()
            owner:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
                ownerLeft + shift / ownerScale,
                (ownerTop * ownerScale - screenHeight) / ownerScale)
            left = left + shift
        end
    end
    if anchor and left and left >= QUEST_PANEL_W + 12 then
        questPanel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, 0)
    elseif anchor and right and screenWidth and screenWidth - right >= QUEST_PANEL_W + 12 then
        questPanel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    elseif anchor and bottom and bottom >= questPanel:GetHeight() + 12 then
        questPanel:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
    elseif anchor then
        questPanel:SetPoint("BOTTOM", anchor, "TOP", 0, 8)
    else
        questPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    questAttachedTo = anchor
end

local function RefreshQuestRows()
    if not questPanel then return end
    if addon.VignetteRadarControls then addon.VignetteRadarControls.RefreshPopupSurface(questPanel) end
    local count = #questEntries
    local visible = math.min(QUEST_VISIBLE_ROWS, count)
    local height = 54 + math.max(1, visible) * QUEST_ROW_STEP
    questPanel:SetHeight(height)
    local style = addon.VignetteRadarStyle
    local red, green, blue = ACCENT[1], ACCENT[2], ACCENT[3]
    if style then red, green, blue = style.Color("accent") end
    questPanel.title:SetTextColor(red, green, blue, 1)
    questPanel.rule:SetColorTexture(red, green, blue, .18)
    questPanel.count:SetText(count .. " IN RANGE")
    questOffset = math.max(0, math.min(questOffset, count - QUEST_VISIBLE_ROWS))
    local focused = addon.VignetteRadarExploration and addon.VignetteRadarExploration.GetFocusedQuest
        and addon.VignetteRadarExploration.GetFocusedQuest()
    local settings = addon.GetSettings()
    local exploration = addon.VignetteRadarExploration
    for index, row in ipairs(questPanel.rows) do
        local entry = questEntries[questOffset + index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local r, g, b = QuestColor(entry)
            row.fill:SetVertexColor(r, g, b, 1)
            if entry.completed then
                row.rim:SetTexture(QUEST_DIAMOND_TEXTURE)
                row.rim:SetSize(13, 13)
                row.rim:SetVertexColor(.04, .05, .06, .98)
                row.fill:Show()
                row.number:SetTextColor(1, 1, 1, 1)
            else
                row.rim:SetTexture(QUEST_HOLLOW_DIAMOND_TEXTURE)
                row.rim:SetSize(QUEST_HOLLOW_SIZE, QUEST_HOLLOW_SIZE)
                row.rim:SetVertexColor(r, g, b, 1)
                row.fill:SetVertexColor(r * .18, g * .18, b * .18, .94)
                row.fill:Show()
                row.number:SetTextColor(1, 1, 1, 1)
            end
            row.number:SetText(settings.vignetteRadarQuestNumbers
                and tostring(entry.colorSlot or 1) or "")
            row.halo:SetVertexColor(r, g, b, .14)
            row.name:SetText(entry.name)
            local progress = settings.vignetteRadarQuestKeyProgress
                and exploration and exploration.ObjectiveProgress
                and exploration.ObjectiveProgress(entry.questID)
            row.progress:SetText(progress and progress:match("^%d+/%d+") or "")
            row.name:SetWidth(progress and 127 or 164)
            row.progress:SetTextColor(r, g, b, .88)
            local selected = focused == entry.questID
            row.focus:SetColorTexture(r, g, b, .85)
            row.focus:SetShown(selected)
            row.name:SetTextColor(selected and r or .82, selected and g or .87,
                selected and b or .88, 1)
            row.hover:SetColorTexture(r, g, b, .10)
        end
    end
    local overflow = count > QUEST_VISIBLE_ROWS
    questPanel.scrollTrack:SetShown(overflow)
    questPanel.scrollThumb:SetShown(overflow)
    if overflow then
        local trackHeight = QUEST_VISIBLE_ROWS * QUEST_ROW_STEP - 4
        local thumbHeight = math.max(18, trackHeight * QUEST_VISIBLE_ROWS / count)
        questPanel.scrollTrack:SetHeight(trackHeight)
        questPanel.scrollThumb:SetHeight(thumbHeight)
        questPanel.scrollThumb:ClearAllPoints()
        questPanel.scrollThumb:SetPoint("TOP", questPanel.scrollTrack, "TOP", 0,
            -(trackHeight - thumbHeight) * questOffset / (count - QUEST_VISIBLE_ROWS))
        questPanel.scrollThumb:SetColorTexture(red, green, blue, .65)
    end
    questPanel.status:SetText(count == 0 and "No mapped quests inside this range"
        or overflow and (questOffset + 1) .. "–" .. (questOffset + visible) .. " of " .. count .. " · scroll"
        or "Click a quest to spotlight it")
end

local function EnsureQuestPanel()
    if questPanel then return questPanel end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end
    questPanel = CreateFrame("Frame", "VignetteRadarQuestLegendPanel", UIParent, "BackdropTemplate")
    questPanel:SetSize(QUEST_PANEL_W, 80)
    if questPanel.SetFrameStrata then questPanel:SetFrameStrata("DIALOG") end
    if questPanel.SetClampedToScreen then questPanel:SetClampedToScreen(true) end
    if questPanel.EnableMouse then questPanel:EnableMouse(true) end
    Surface(questPanel)
    if addon.VignetteRadarControls then addon.VignetteRadarControls.PopupSurface(questPanel) end
    questPanel.title = Text(questPanel, 11, "QUEST KEY")
    questPanel.title:SetPoint("TOPLEFT", 12, -10)
    questPanel.count = Text(questPanel, 8, "0 IN RANGE")
    questPanel.count:SetPoint("TOPRIGHT", -31, -11)
    questPanel.count:SetJustifyH("RIGHT")
    questPanel.count:SetWidth(85)
    questPanel.rule = SectionRule(questPanel, 31)
    questPanel.rows = {}
    local function Scroll(_, delta)
        questOffset = math.max(0, math.min(math.max(0, #questEntries - QUEST_VISIBLE_ROWS),
            questOffset - delta))
        RefreshQuestRows()
    end
    if questPanel.EnableMouseWheel then questPanel:EnableMouseWheel(true) end
    questPanel:SetScript("OnMouseWheel", Scroll)
    for index = 1, QUEST_VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, questPanel)
        row:SetSize(204, QUEST_ROW_H)
        row:SetPoint("TOPLEFT", 10, -37 - (index - 1) * QUEST_ROW_STEP)
        if row.EnableMouseWheel then row:EnableMouseWheel(true) end
        row:SetScript("OnMouseWheel", Scroll)
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.focus = row:CreateTexture(nil, "ARTWORK")
        row.focus:SetSize(2, 16)
        row.focus:SetPoint("LEFT", 0, 0)
        row.halo = row:CreateTexture(nil, "ARTWORK")
        row.halo:SetSize(18, 18)
        row.halo:SetPoint("LEFT", 7, 0)
        row.halo:SetTexture(CIRCLE_TEXTURE)
        row.rim = row:CreateTexture(nil, "OVERLAY")
        row.rim:SetSize(13, 13)
        row.rim:SetPoint("CENTER", row.halo, "CENTER")
        row.rim:SetTexture(QUEST_DIAMOND_TEXTURE)
        row.rim:SetVertexColor(.04, .05, .06, .98)
        row.fill = row:CreateTexture(nil, "OVERLAY")
        row.fill:SetSize(9, 9)
        row.fill:SetPoint("CENTER", row.halo, "CENTER")
        row.fill:SetTexture(QUEST_DIAMOND_TEXTURE)
        row.number = Text(row, 8, "")
        row.number:SetPoint("CENTER", row.halo, "CENTER")
        addon.VignetteRadarStyle.SetFont(row.number, 9, "OUTLINE")
        row.number:SetJustifyH("CENTER")
        row.number:SetTextColor(1, 1, 1, 1)
        row.name = Text(row, 9, "")
        row.name:SetPoint("LEFT", 30, 0)
        row.name:SetWidth(127)
        row.progress = Text(row, 9, "")
        row.progress:SetPoint("RIGHT", -8, 0)
        row.progress:SetWidth(35)
        row.progress:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function(self)
            self.hover:Show()
            if not (self.entry and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry.name, 1, .89, .78)
            local status = self.entry.completed and "Complete" or "Quest"
            if self.entry.distance then
                status = status .. " · " .. math.floor(self.entry.distance + .5) .. " yd"
            end
            GameTooltip:AddLine(status, .72, .76, .78)
            if not self.entry.completed then
                local questData = addon.VignetteRadarQuestData
                local summary = questData and questData.GetObjectiveSummary
                    and questData.GetObjectiveSummary(self.entry.questID)
                if summary and summary.label then
                    GameTooltip:AddLine((summary.count and summary.count .. " " or "") .. summary.label,
                        1, .86, .52, true)
                else
                    local exploration = addon.VignetteRadarExploration
                    local lines = exploration and exploration.ObjectiveLines
                        and exploration.ObjectiveLines(self.entry.questID)
                    if lines and lines[1] then GameTooltip:AddLine(lines[1], 1, .86, .52, true) end
                end
            end
            GameTooltip:AddLine("Click to Spotlight", .6, .8, .72)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            local exploration = addon.VignetteRadarExploration
            if self.entry and exploration and exploration.FocusQuest then
                exploration.FocusQuest(self.entry.questID)
                RefreshQuestRows()
            end
        end)
        row:Hide()
        questPanel.rows[index] = row
    end
    questPanel.scrollTrack = questPanel:CreateTexture(nil, "ARTWORK")
    questPanel.scrollTrack:SetPoint("TOPRIGHT", -5, -38)
    questPanel.scrollTrack:SetWidth(2)
    questPanel.scrollTrack:SetColorTexture(.55, .61, .63, .20)
    questPanel.scrollThumb = questPanel:CreateTexture(nil, "OVERLAY")
    questPanel.scrollThumb:SetWidth(2)
    questPanel.status = Text(questPanel, 8, "No mapped quests inside this range")
    questPanel.status:SetPoint("BOTTOMLEFT", 12, 8)
    questPanel.status:SetTextColor(.53, .62, .63, 1)
    questPanel.close = addon.VignetteRadarIconButton.Create(questPanel, "close",
        { size = 20, label = "Close Quests", onClick = function() API.HideQuest() end })
    questPanel.close:SetPoint("TOPRIGHT", -5, -5)
    questPanel:SetScript("OnHide", RestoreQuestShift)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarQuestLegendPanel"
    end
    RefreshQuestRows()
    questPanel:Hide()
    return questPanel
end

function API.Refresh()
    local settings = API.ApplyDefaults()
    if not panel then return end
    if addon.VignetteRadarControls then addon.VignetteRadarControls.RefreshPopupSurface(panel) end
    -- Docked or detached, the legend keeps the radar's own background.
    local tray = addon.VignetteRadarTray
    if tray then
        tray.SkinLikeRadar(panel)
        if tray.IsAttached(panel) then tray.RefreshTheme() end
    end
    local highlight = API.GetHighlight()
    local style = addon.VignetteRadarStyle
    local accentRed, accentGreen, accentBlue = ACCENT[1], ACCENT[2], ACCENT[3]
    if style then
        accentRed, accentGreen, accentBlue = style.Color("accent")
        panel.title:SetTextColor(accentRed, accentGreen, accentBlue, 1)
        panel.divider:SetColorTexture(accentRed, accentGreen, accentBlue, .18)
    end
    for _, category in ipairs(CATEGORY_ORDER) do
        local row = panel.rows[category]
        row.selection:SetColorTexture(accentRed, accentGreen, accentBlue, .09)
        local red, green, blue = API.ColorFor(category)
        row.swatchGlow:SetColorTexture(red, green, blue, .14)
        local icons = settings.vignetteRadarShapes ~= false
        if category == "rare" then
            row.swatch:SetTexture(icons and SKULL_TEXTURE or CIRCLE_TEXTURE)
            row.swatch:SetSize(icons and 13 or 7, icons and 13 or 7)
            row.bossSwatch:SetTexture(icons and SKULL_TEXTURE or CIRCLE_TEXTURE)
            row.bossSwatch:SetSize(icons and 13 or 7, icons and 13 or 7)
            if style then row.bossSwatch:SetVertexColor(style.Color("boss")) end
        elseif category == "treasure" then
            if icons and row.swatch.SetAtlas then row.swatch:SetAtlas("VignetteLoot")
            else row.swatch:SetTexture(CIRCLE_TEXTURE) end
            row.swatch:SetSize(icons and row.swatch.SetAtlas and 13 or 7,
                icons and row.swatch.SetAtlas and 13 or 7)
        else
            row.swatch:SetTexture(CIRCLE_TEXTURE)
        end
        row.swatch:SetVertexColor(red, green, blue, 1)
        local enabled = API.IsCategoryEnabled(category)
        local selected = highlight == category
        if enabled then
            row:SetAlpha((selected or not highlight) and 1 or 0.58)
            row.toggle.label:SetText("ON")
            row.toggle.label:SetTextColor(accentRed, accentGreen, accentBlue, 1)
            row.swatch:SetAlpha(1)
            if row.bossSwatch then row.bossSwatch:SetAlpha(1) end
        else
            row:SetAlpha(0.46)
            row.toggle.label:SetText("OFF")
            row.toggle.label:SetTextColor(0.58, 0.60, 0.62, 1)
            row.swatch:SetAlpha(0.38)
            if row.bossSwatch then row.bossSwatch:SetAlpha(0.38) end
        end
        row.focusCue:SetShown(selected)
        row.focusCue:SetTextColor(accentRed, accentGreen, accentBlue, 1)
        if selected then row.selection:Show() else row.selection:Hide() end
    end
    local function Color(slot, fallback)
        if style then return style.Color(slot) end
        return fallback[1], fallback[2], fallback[3]
    end
    local mapEnabled = settings.vignetteRadarMapNotesVisible == true
        and (settings.vignetteRadarPOISource ~= "none" or settings.vignetteRadarSourceFusion)
    panel.mapToggle:SetActive(mapEnabled)
    for _, definition in ipairs(MAP_NOTES) do
        local row = panel.mapNotes[definition.kind]
        row.rim:SetVertexColor(Color(definition.color, CATEGORIES[definition.color].color))
        local enabled = (mapEnabled or (definition.kind == "guide"
            and settings.vignetteRadarWorldFocusZygor))
            and (type(settings.vignetteRadarPOITypes) ~= "table"
            or settings.vignetteRadarPOITypes[definition.kind] ~= false)
        row:SetAlpha(enabled and 1 or .6)
        row.label:SetText(definition.label .. (enabled and "" or " off"))
    end
    panel.mapCaption:SetText(not mapEnabled and not settings.vignetteRadarWorldFocusZygor
        and "Map Notes Off · Toggle Above"
        or settings.vignetteRadarPOIIcons and "Pack icons = saved, not live"
        or "Hollow notes = saved, not live")
    local questRed, questGreen, questBlue = Color("quest", { 1, .74, .27 })
    if settings.vignetteRadarQuestColors and addon.VignetteRadarQuestColors then
        local first = addon.VignetteRadarQuestColors[1]
        questRed, questGreen, questBlue = first[1], first[2], first[3]
    end
    panel.guides.quest.fill:SetVertexColor(questRed, questGreen, questBlue, 1)
    local areaRed, areaGreen, areaBlue = .34, .60, 1
    if settings.vignetteRadarQuestColors and settings.vignetteRadarQuestAreaColors
        and addon.VignetteRadarQuestColors then
        local first = addon.VignetteRadarQuestColors[1]
        areaRed, areaGreen, areaBlue = first[1], first[2], first[3]
    end
    panel.guides.quest.halo:SetVertexColor(areaRed, areaGreen, areaBlue, .16)
    local showQuestHalo = settings.vignetteRadarQuestDots and settings.vignetteRadarQuestAreas
        and settings.vignetteRadarQuestHalos
    panel.guides.quest.halo:SetShown(showQuestHalo == true)
    panel.guides.area.fill:SetVertexColor(areaRed, areaGreen, areaBlue, .3)
    panel.guides.quest:SetAlpha(settings.vignetteRadarQuestDots and 1 or .6)
    panel.guides.quest.label:SetText(not settings.vignetteRadarQuestDots and "Quest off"
        or showQuestHalo and "Quest + estimate" or "Quest point")
    panel.guides.area:SetAlpha(settings.vignetteRadarQuestAreas and 1 or .6)
    panel.guides.area.label:SetText(settings.vignetteRadarQuestAreas and "Blizzard area" or "Area off")
    panel.guides.pin.fill:SetVertexColor(.92, .71, .34, .9)
    panel.guides.route.fill:SetVertexColor(.16, .7, .54, .9)
    panel.guides.edge.fill:SetVertexColor(questRed, questGreen, questBlue, .9)
    panel.guides.edge.tip:SetColorTexture(questRed, questGreen, questBlue, .7)
    panel.guides.edge:SetAlpha(settings.vignetteRadarEdgeCues and 1 or .6)
    panel.guides.edge.label:SetText(settings.vignetteRadarEdgeCues and "Off-range cue" or "Edge cues off")
    local rareRed, rareGreen, rareBlue = Color("rare", CATEGORIES.rare.color)
    for _, line in ipairs(panel.guides.stale.lines) do
        line:SetColorTexture(rareRed, rareGreen, rareBlue, .4)
    end
    local trailStyle = settings.vignetteRadarTrailStyle or "dashes"
    local trailDefinition = TRAIL_STYLES[trailStyle] or TRAIL_STYLES.dashes
    for index, dot in ipairs(panel.guides.trail.dots) do
        dot:SetVertexColor(accentRed, accentGreen, accentBlue, .85)
        dot:SetTexture(trailDefinition.square and "Interface\\Buttons\\WHITE8X8"
            or "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        local dotSize = trailDefinition.alternating and index % 2 == 0 and 2.5 or 4
        dot:SetSize(dotSize, dotSize)
        dot:SetShown(trailDefinition.dot ~= nil or trailDefinition.square ~= nil)
        local mark = panel.guides.trail.marks[index]
        local x = 2 + index * 5
        for part = 1, 4 do
            local line = part == 1 and mark or panel.guides.trail.extraMarks[index][part - 1]
            local segment = trailDefinition.segments and trailDefinition.segments[part]
            if segment then
                local scale = trailDefinition.alternating and index % 2 == 0 and .22 or .45
                line:SetThickness(segment[5] * .8)
                line:SetStartPoint("LEFT", panel.guides.trail,
                    x + segment[1] * scale, segment[2] * scale)
                line:SetEndPoint("LEFT", panel.guides.trail,
                    x + segment[3] * scale, segment[4] * scale)
                line:SetColorTexture(accentRed, accentGreen, accentBlue, .85)
                line:Show()
            else
                line:Hide()
            end
        end
    end
    panel.guides.trail:SetAlpha(settings.vignetteRadarBreadcrumbs and 1 or .6)
    local trailName = trailStyle == "long" and "Long" or trailDefinition.label
    panel.guides.trail.label:SetText(settings.vignetteRadarBreadcrumbs
        and ("Trail: " .. trailName) or "Trail off")
    if highlight then
        panel.status:SetText("SPOTLIGHT: " .. CATEGORIES[highlight].label)
    else
        panel.status:SetText("SPOTLIGHT OFF · SHOWN TYPES EQUAL")
    end
    panel.all:Refresh()
end

-- With the radar up, the legend opens in the radar's tray, swapping out the
-- quest tracker; without it, the legend is a popup beside the radar.
local legendTray
local function DockTray()
    local tray = addon.VignetteRadarTray
    return tray and tray.CanDock and tray.CanDock() and tray or nil
end

local function LegendTrayOptions()
    if legendTray then return legendTray end
    legendTray = {
        frame = panel,
        label = "Legend",
        side = function() return addon.GetSettings().vignetteRadarQuestTrackerSide or "right" end,
        isOpen = function() return true end,
        setInteractive = function(on) panel:EnableMouse(on) end,
        onReplaced = function() panel:Hide() end,
        keepOpen = function()
            return markerPanel ~= nil and markerPanel:IsShown() and MouseIsOver(markerPanel)
        end,
    }
    return legendTray
end

local function Docked()
    local tray = addon.VignetteRadarTray
    return panel and tray and tray.IsAttached(panel) and tray or nil
end

local function Detached() return addon.GetSettings().vignetteRadarLegendDetached == true end

-- A detached legend reopens where it was dragged; false when never placed.
-- On the shared panel system the spot is checked once a session (off screen
-- or invalid: back to docked) and kept on screen.
local function PlaceDetached()
    local tray = addon.VignetteRadarTray
    if tray and tray.IsPanel and tray.IsPanel(panel) then
        tray.CheckPanelSpot(panel)
        if not (Detached() and tray.GetPanelSpot(panel)) then return false end
        tray.PlaceFreePanel(panel)
        return true
    end
    local position = addon.GetSettings().vignetteRadarLegendPosition
    if type(position) ~= "table" or type(position.x) ~= "number" or type(position.y) ~= "number" then
        return false
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", position.x, position.y)
    return true
end

function API.Toggle(anchor)
    local legend = EnsurePanel()
    if not legend then return false end
    local tray = not Detached() and DockTray()
    if tray then
        if tray.IsAttached(legend) and tray.IsOpen() then
            tray.SetOpen(false)
            return false
        end
        if markerPanel then markerPanel:Hide() end
        API.Refresh()
        return tray.Show(LegendTrayOptions())
    end
    if legend:IsShown() or markerPanel and markerPanel:IsShown() then
        legend:Hide()
        if markerPanel then markerPanel:Hide() end
        return false
    end
    if not (Detached() and PlaceDetached()) then Attach(anchor or attachedTo) end
    API.Refresh()
    legend:Show()
    return true
end

-- Detach: leave the tray at the legend's current spot as a free panel.
-- Dock: back into the radar's tray.
function API.SetDetached(value)
    local settings = addon.GetSettings()
    local legend = EnsurePanel()
    settings.vignetteRadarLegendDetached = value == true
    if not legend then return end
    if value then
        local scale = (FrameValue(legend, "GetEffectiveScale") or 1) / (FrameValue(UIParent, "GetEffectiveScale") or 1)
        local left, top = FrameValue(legend, "GetLeft"), FrameValue(legend, "GetTop")
        local height = FrameValue(UIParent, "GetHeight")
        local shared = addon.VignetteRadarTray
        -- Saved while it still stands in the tray, so it stays on the spot.
        local saved = shared and shared.IsPanel and shared.IsPanel(legend) and shared.SavePanelSpot(legend)
        local tray = Docked()
        if tray then tray.Detach(legend) end
        if not saved and left and top and height then
            settings.vignetteRadarLegendPosition = { x = left * scale, y = top * scale - height }
        end
        if not PlaceDetached() then Attach(attachedTo) end
        API.Refresh()
        legend:Show()
    else
        legend:Hide()
        API.Toggle(attachedTo)
    end
    if legend.detach then legend.detach:RefreshDetach() end
    if legend.moveLock then legend.moveLock:SetShown(value == true) end
end

function API.Reanchor(anchor)
    if Docked() or Detached() and panel and PlaceDetached() then return true end
    if not (panel and (panel:IsShown() or markerPanel and markerPanel:IsShown())) then return false end
    Attach(anchor or attachedTo)
    return true
end

function API.Hide()
    if markerPanel then markerPanel:Hide() end
    local tray = Docked()
    if tray then tray.Retract(); return end
    if panel then panel:Hide() end
end

function API.IsShown()
    local tray = Docked()
    if tray then return tray.IsOpen() or markerPanel ~= nil and markerPanel:IsShown() end
    return panel ~= nil and panel:IsShown() or markerPanel ~= nil and markerPanel:IsShown() or false
end

function API.ToggleMarkers()
    local markers = EnsureMarkerPanel()
    if not (markers and panel) then return false end
    if markers:IsShown() then
        markers:Hide()
        panel:Show()
        return false
    end
    markers:ClearAllPoints()
    markers:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    RefreshMarkerRows()
    panel:Hide()
    markers:Show()
    return true
end

function API.SetQuestEntries(entries)
    questEntries = type(entries) == "table" and entries or {}
    table.sort(questEntries, function(left, right)
        if left.distance ~= right.distance then
            return (left.distance or math.huge) < (right.distance or math.huge)
        end
        return left.questID < right.questID
    end)
    if questPanel and questPanel:IsShown() then RefreshQuestRows() end
end

function API.ToggleQuest(anchor, owner)
    local key = EnsureQuestPanel()
    if not key then return false end
    if key:IsShown() then key:Hide(); return false end
    RefreshQuestRows()
    AttachQuest(anchor or questAttachedTo, owner)
    key:Show()
    return true
end

function API.ReanchorQuest(anchor, owner)
    if not (questPanel and questPanel:IsShown()) then return false end
    AttachQuest(anchor or questAttachedTo, owner)
    return true
end

function API.HideQuest()
    if questPanel then questPanel:Hide() end
end

function API.IsQuestShown()
    return questPanel ~= nil and questPanel:IsShown() or false
end

API.ApplyDefaults()

API.Testing = {
    CategoryKey = CategoryKey,
    CategoryOrder = CATEGORY_ORDER,
    Categories = CATEGORIES,
    GetPanel = function() return panel end,
    GetQuestPanel = function() return questPanel end,
    GetMarkerPanel = function() return markerPanel end,
}
