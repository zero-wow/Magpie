local _, addon = ...
if type(addon) ~= "table" then return end

-- The radar's settings window. Pages, cards and rows come from the settings
-- schema (Core/Schema.lua): a left rail of radar-style icons picks a page,
-- each schema section is a card painted like the radar face, and every row
-- applies live through Schema.Set. The search box filters rows across all
-- pages. A few tool panels (map packs, themes, World Focus actions, status)
-- add their own rows to the matching cards.
local WIDTH, HEIGHT = 468, 520
local RAIL, HEADER, GUTTER = 56, 44, 10
local VIEW_X = RAIL + 8
local VIEW_WIDTH = WIDTH - VIEW_X - 16
local VIEW_HEIGHT = HEIGHT - HEADER - GUTTER
local CARD_WIDTH = VIEW_WIDTH - 4
local CARD_TOP, CARD_GAP, PAGE_TOP = 30, 10, 30
local ICONS = "Interface\\AddOns\\Magpie\\Media\\config-icons.tga"
local SEARCH_ICON = 9
local THEME_COLUMNS, THEME_ROW = 5, 24
local LIST_ROWS, LIST_ROW = 4, 25
local quick, anchor, guide
-- Every row in the window, every card by "Page/Section", and every page frame.
local rows, cards = {}, {}
local API = {}
addon.VignetteRadarQuickConfig = API

-- Old page names (from the tab grid and its sub-pages) and where they live now.
local LEGACY_PAGES = {
    Radar = { "Radar" }, Layout = { "Radar", "Range And Size" }, Explore = { "Radar", "Exploring" },
    Behavior = { "Radar", "Behavior" }, Themes = { "Looks", "Theme" }, Guides = { "Looks", "Radar Guides" },
    Alerts = { "Alerts" }, Markers = { "Markers" }, ["Map Data"] = { "Markers", "Map Data Packs" },
    ["Source Fusion"] = { "Markers", "Source Fusion" }, Quests = { "Quests" },
    ["Quest Routing"] = { "Quests", "Quest Routing" }, Wayfinding = { "Routes", "Route Draft" },
    ["World Focus"] = { "Routes", "World Focus" }, ["Auto Route"] = { "Routes", "Auto Route" },
    ["Guide Panel"] = { "Routes", "Guide Panel" },
    Zygor = { "Routes", "Zygor" }, ["Routes & Cues"] = { "Routes", "Sound Compass" },
    ["In-World Marker"] = { "HUD", "In-World Marker" }, Beacons = { "HUD", "Bearing Bar" },
    ["Bearing Bar"] = { "HUD", "Bearing Bar" }, Constellation = { "HUD", "Constellation" },
    Status = { "Tools", "Live Diagnostics" }, Performance = { "Tools", "Performance" }, Tools = { "Tools" },
}
API.LEGACY_PAGES = LEGACY_PAGES

local function Settings()
    return addon.GetSettings()
end

local function Controls() return addon.VignetteRadarControls end

local function Label(parent, value, x, y, size, width)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size or 10, "")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width or WIDTH - x - 12)
    label:SetTextColor(0.81, 0.87, 0.86, 1)
    label:SetWordWrap(false)
    label:SetText(value)
    return label
end

local function SetSetting(key, value, subkey)
    return addon.Schema.Set(key, value, subkey)
end

-- Tool actions ------------------------------------------------------------

local function OpenExpeditionStudio()
    local studio, radar = addon.VignetteRadarExpeditionStudio, addon.VignetteRadarAPI
    if not studio then return end
    if radar then
        studio.SetCandidates(radar.GetRouteCandidates and radar.GetRouteCandidates() or {})
        studio.SetPlayer(radar.GetPlayerSnapshot and radar.GetPlayerSnapshot() or nil)
    end
    studio.SetOnApply(function(trip)
        if not (trip and not trip.paused) then return end
        if not trip.currentID and addon.VignetteRadarExpeditions then
            local player = radar and radar.GetPlayerSnapshot and radar.GetPlayerSnapshot()
            addon.VignetteRadarExpeditions.Plan(trip, player or {})
        end
        if not trip.currentID then return end
        local goal
        for _, candidate in ipairs(trip.goals or {}) do
            if candidate.id == trip.currentID then goal = candidate; break end
        end
        if not goal then return end
        local focus = addon.VignetteRadarWorldFocus
        if not focus then return end
        if goal.kind == "quest" and focus.SelectQuest then
            local questID = tonumber(tostring(goal.id):match("^quest:(%d+)"))
            if questID then focus.SelectQuest(questID) end
        elseif focus.SelectPoint then
            focus.SelectPoint({ key = goal.id, kind = goal.kind,
                name = goal.name, mapID = goal.mapID, mapX = goal.mapX,
                mapY = goal.mapY, worldX = goal.worldX,
                worldY = goal.worldY, instanceID = goal.instanceID })
        end
    end)
    studio.Open()
end

local function OpenSurvey()
    local survey, radar = addon.VignetteRadarSurveyParty, addon.VignetteRadarAPI
    if not survey then return end
    local sighting, stop
    local targets = radar and radar.GetTargets and radar.GetTargets() or {}
    local mapID = radar and radar.GetCurrentMapID and radar.GetCurrentMapID()
    for _, target in ipairs(targets) do
        if not target.stale and target.mapID == mapID
            and (target.category == "rare" or target.category == "treasure")
            and type(target.mapX) == "number" and type(target.mapY) == "number" then
            sighting = { mapID = mapID, x = target.mapX, y = target.mapY,
                kind = target.category, identity = tostring(target.key or target.vignetteID or "live"),
                name = target.name or "Sighting" }
            break
        end
    end
    local focus = addon.VignetteRadarWorldFocus
    local step, stepKind
    if focus and focus.GetRoutePoint then step, stepKind = focus.GetRoutePoint() end
    if step and type(step.mapX) == "number" and type(step.mapY) == "number" then
        stop = { mapID = step.mapID, x = step.mapX, y = step.mapY,
            kind = (stepKind == "rare" or stepKind == "treasure" or stepKind == "quest")
                and stepKind or "pin",
            identity = tostring(step.key or step.questID or "stop"),
            name = step.name or "Route Stop" }
    end
    survey.SetShareTargets(sighting, stop)
    survey.Open()
end

local function ToggleAtlas()
    if addon.VignetteRadarAPI and addon.VignetteRadarAPI.ToggleAtlas then
        addon.VignetteRadarAPI.ToggleAtlas()
    end
end

local function Focus(method)
    return function()
        local focus = addon.VignetteRadarWorldFocus
        if focus and focus[method] then
            if method == "Cycle" then focus.Cycle(1) else focus[method]() end
        end
        if method == "ToggleRoute" and addon.VignetteRadarGuidePanel then
            addon.VignetteRadarGuidePanel.Refresh()
        end
        API.Refresh()
    end
end

local function PinZygor(mode)
    return function()
        local bridge = addon.VignetteRadarZygor
        local ok, reason = addon.VignetteRadarAPI.BindZygorGuide()
        if ok and bridge then ok, reason = bridge.Pin(mode) end
        API.Refresh()
        if not ok and reason and quick.zygorStatus then quick.zygorStatus:SetText(reason) end
    end
end

-- Special widgets ---------------------------------------------------------

local function NewRow(card, entry, width, height, kind)
    local row = CreateFrame("Frame", nil, card)
    row:SetSize(width, height)
    row.isRow, row.kind, row.entry = true, kind, entry
    row.searchText = entry and ((entry.label or "") .. " " .. (entry.tooltip or "") .. " "
        .. entry.key .. " " .. table.concat(entry.tags or {}, " ")):lower() or ""
    return row
end

local function RefreshPOISources()
    if not quick or not quick.poiRows then return end
    local poi = addon.VignetteRadarPOIs
    local radar = addon.VignetteRadarAPI
    local mapID = radar and radar.GetCurrentMapID and radar.GetCurrentMapID()
    local sources = poi and poi.ZoneSources(mapID) or {}
    local entries = { { id = "none", enabled = true }, { id = "auto", enabled = true } }
    for _, source in ipairs(sources) do entries[#entries + 1] = source end
    quick.poiEntries = entries
    if quick.poiMapID ~= mapID then quick.poiOffset, quick.poiMapID = 0, mapID end
    local maxOffset = math.max(0, #entries - #quick.poiRows)
    quick.poiOffset = math.min(maxOffset, quick.poiOffset or 0)
    local selected = Settings().vignetteRadarPOISource
    local zoneChoice = poi and poi.ZoneChoice and poi.ZoneChoice(mapID)
    local selectedEntry
    for _, entry in ipairs(entries) do
        if entry.id == selected then selectedEntry = entry; break end
    end
    for index, row in ipairs(quick.poiRows) do
        local entry = entries[index + quick.poiOffset]
        row.sourceID = entry and entry.id
        row:SetShown(entry ~= nil)
        if entry then
            row:SetText(entry.id == "none" and "Off" or entry.id == "auto" and "Auto · Current Zone"
                or entry.id:gsub("(%l)(%u)", "%1 %2"):gsub("_", " "))
            row:SetEnabled(entry.enabled)
            if entry.id == (selected == "auto" and zoneChoice or selected) then
                row:LockHighlight()
            else row:UnlockHighlight() end
        end
    end
    local track = quick.poiTrack:GetHeight()
    quick.poiThumb:SetHeight(math.max(16, track * math.min(1, #quick.poiRows / #entries)))
    quick.poiThumb:ClearAllPoints()
    quick.poiThumb:SetPoint("TOP", quick.poiTrack, "TOP", 0,
        maxOffset > 0 and -((track - quick.poiThumb:GetHeight()) * quick.poiOffset / maxOffset) or 0)
    quick.poiTrack:SetShown(maxOffset > 0)
    quick.poiThumb:SetShown(maxOffset > 0)
    if Settings().vignetteRadarMapNotesVisible ~= true then
        quick.poiStatus:SetText("Map notes are hidden. Toggle them in the Legend.")
    elseif selected == "none" then
        quick.poiStatus:SetText("Map notes are off. Choose Auto or a pack above.")
    elseif selected == "auto" then
        local chosen = poi and poi.ResolveSource(mapID, selected)
        quick.poiStatus:SetText(zoneChoice == "none" and "Map notes are off in this zone."
            or zoneChoice and chosen == zoneChoice and ("Pinned here: " .. zoneChoice)
            or zoneChoice and ("Pinned pack unavailable; using " .. tostring(chosen or "none"))
            or chosen and ("Auto: " .. chosen .. " · right-click to pin")
            or "No enabled HandyNotes pack has notes here.")
    elseif not selectedEntry then
        quick.poiStatus:SetText("This pack has no notes here. Choose Auto.")
    else
        quick.poiStatus:SetText(Settings().vignetteRadarPOIIcons
            and "Pack icons · dots where unavailable." or "One pack here · hollow dots are saved notes.")
    end
    if Settings().vignetteRadarMapNotesVisible == true
        and Settings().vignetteRadarSourceFusion then
        quick.poiStatus:SetText("Source Fusion is on. Choose packs in its card below.")
    end
end

local function RefreshFusionSources()
    if not quick or not quick.fusionRows then return end
    local poi = addon.VignetteRadarPOIs
    local mapID = addon.VignetteRadarAPI and addon.VignetteRadarAPI.GetCurrentMapID()
    local sources = poi and poi.ZoneSources(mapID) or {}
    local visible = {}
    for _, source in ipairs(sources) do
        if source.enabled then visible[#visible + 1] = source end
    end
    quick.fusionEntries = visible
    quick.fusionOffset = math.max(0, math.min(quick.fusionOffset or 0,
        math.max(0, #visible - #quick.fusionRows)))
    local selected = Settings().vignetteRadarFusionSources
    if type(selected) ~= "table" then selected = {} end
    local preferred = type(Settings().vignetteRadarFusionPreferred) == "table"
        and Settings().vignetteRadarFusionPreferred[tostring(mapID)] or nil
    for index, row in ipairs(quick.fusionRows) do
        local source = visible[index + quick.fusionOffset]
        row.sourceID = source and source.id
        row:SetShown(source ~= nil)
        if source then
            local picked = false
            for _, id in ipairs(selected) do if id == source.id then picked = true; break end end
            row:SetText((picked and "ON  " or "OFF  ")
                .. source.id:gsub("(%l)(%u)", "%1 %2"):gsub("_", " ")
                .. (preferred == source.id and "  · Preferred Here" or ""))
            if picked then row:LockHighlight() else row:UnlockHighlight() end
        end
    end
    quick.fusionStatus:SetText(#visible == 0 and "No enabled map packs found here."
        or #selected == 0 and "Choose up to 8 packs; one-pack mode remains active."
        or #selected .. " pack(s) selected. Right-click to prefer one here.")
end

-- A short scrolling list of buttons with a thin track, then a status line.
local function SourceList(card, entry, width, kind, onClick, onWheel)
    local row = NewRow(card, entry, width, LIST_ROWS * LIST_ROW + 20, kind)
    local buttons = {}
    for index = 1, LIST_ROWS do
        local button = Controls().Button(row, "", width - 38, 21)
        button:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -2 - (index - 1) * LIST_ROW)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", onClick)
        button:EnableMouseWheel(true)
        button:SetScript("OnMouseWheel", onWheel)
        button.optionKey = entry.key
        buttons[index] = button
    end
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", onWheel)
    row.track = row:CreateTexture(nil, "ARTWORK")
    row.track:SetSize(3, LIST_ROWS * LIST_ROW - 4)
    row.track:SetPoint("TOPLEFT", row, "TOPLEFT", width - 20, -3)
    row.track:SetColorTexture(1, 1, 1, .1)
    row.thumb = row:CreateTexture(nil, "OVERLAY")
    row.thumb:SetWidth(3)
    row.thumb:SetColorTexture(1, 1, 1, .5)
    row.status = Label(row, "", 12, -3 - LIST_ROWS * LIST_ROW, 9, width - 24)
    row.status:SetTextColor(.62, .70, .70, 1)
    row.buttons = buttons
    function row:Refresh() end
    return row
end

local WIDGETS = {}

-- The selected theme or family uses the standard button selection (Controls
-- Button: darkened face, accent label, short accent underline) set through
-- LockHighlight. MarkSelected only re-applies that look, so the user's
-- preferred underline style is kept instead of a full frame and fill.
local function MarkSelected(button, on)
    button._selected = on == true
    if button.RefreshAppearance then button:RefreshAppearance() end
end
API.MarkSelected = MarkSelected

-- Theme picker: Single Color or Multi-Color, then (for multi) a family, then
-- a variant. Hovering a choice previews its role colors in the swatches at the
-- right of the trail line. Grid buttons are made the first time their view
-- opens and reused; hidden ones drop their anchors so they hold no space.
local THEME_HEAD, WIDE_ROW, WIDE_COLUMNS = 48, 27, 3
local STRIP_SLOTS = { "rings", "accent", "rare", "treasure", "quest", "event", "boss" }

function WIDGETS.theme(card, entry, width)
    local style = addon.VignetteRadarStyle
    local row = NewRow(card, entry, width, THEME_HEAD, "theme")
    local picker = { singles = {}, families = {}, variants = {}, swatches = {}, all = {} }
    quick.themeChoices, quick.themeRow, quick.themePicker = {}, row, picker
    local eachSingle = math.floor((width - 20 - (THEME_COLUMNS - 1) * 4) / THEME_COLUMNS)
    local eachWide = math.floor((width - 20 - (WIDE_COLUMNS - 1) * 4) / WIDE_COLUMNS)
    local third = math.floor((width - 28) / 3)
    local eachAction = math.floor((width - 20 - 3 * 4) / 4)
    picker.baseSearch = row.searchText

    local function Current() return Settings().vignetteRadarTheme end
    local function View()
        local kind, family = style.ThemeKind(Current())
        return { kind = kind, family = kind == "multi" and family and family.id or nil }
    end
    picker.view = View()

    local function FamilyByID(id)
        for _, family in ipairs(style.Families()) do if family.id == id then return family end end
    end

    -- The trail names where the picker is; the last part follows the hover.
    local function Trail(hovered)
        local view = picker.view
        local kind, family, variant = style.ThemeKind(Current())
        if view.kind == "single" then
            local name = hovered or (kind == "single" and Current())
            return "Single Color" .. (name and (" > " .. style.ThemeName(name)) or "")
        end
        if view.kind == "custom" then
            local name = hovered or (kind == "custom" and Current())
            return "Custom > " .. (name and style.ThemeName(name)
                or #style.CustomThemes() == 0 and "None Yet" or "Pick A Theme")
        end
        local open = view.family and FamilyByID(view.family)
        if not open then
            local shown = hovered and FamilyByID(hovered) or family
            return "Multi-Color > " .. (shown and shown.name or "Pick A Family")
        end
        if hovered then family, variant = open, select(3, style.ThemeKind(hovered)) end
        if family == open and variant then return "Multi-Color > " .. open.name .. " > " .. variant.name end
        return "Multi-Color > " .. open.name
    end

    local function Preview(name, hovered)
        name = name or Current()
        for index, slot in ipairs(style.slots) do
            local r, g, b = style.PresetColor(name, slot)
            if r then picker.swatches[index]:SetColorTexture(r, g, b, 1) end
        end
        picker.trail:SetText(Trail(hovered))
    end

    local function PaintStrip(button, name)
        for index, slot in ipairs(button.stripSlots) do
            local r, g, b = style.PresetColor(name, slot)
            if r then button.strip[index]:SetColorTexture(r, g, b, 1) end
        end
    end

    local function Choice(text, each, height, slots, previewName, hovered, onClick)
        local button = Controls().Button(row, text, each, height)
        button.strip, button.stripSlots = {}, slots
        local segment = (each - 4) / #slots
        for index = 1, #slots do
            local swatch = button:CreateTexture(nil, "OVERLAY")
            swatch:SetPoint("TOPLEFT", button, "TOPLEFT", 2 + (index - 1) * segment, -1)
            swatch:SetSize(segment, height > 21 and 3 or 2)
            button.strip[index] = swatch
        end
        PaintStrip(button, previewName)
        button:SetScript("OnClick", onClick)
        button:HookScript("OnEnter", function() Preview(hovered and previewName or nil, hovered) end)
        button:HookScript("OnLeave", function() Preview(nil) end)
        button:Hide()
        picker.all[#picker.all + 1] = button
        return button
    end

    local function Place(button, index, columns, each, pitch)
        local line, column = math.floor((index - 1) / columns), (index - 1) % columns
        button.layoutY = THEME_HEAD + line * pitch
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", row, "TOPLEFT", 10 + column * (each + 4), -THEME_HEAD - line * pitch)
        button:Show()
        return line + 1
    end

    local function Theme(name, label, each, height, slots)
        local button = quick.themeChoices[name]
        if button then return button end
        button = Choice(label, each, height, slots, name, name, function() SetSetting(entry.key, name) end)
        button.optionKey, button.optionValue = entry.key, name
        quick.themeChoices[name] = button
        return button
    end

    local function FamilyButton(family)
        local button = picker.families[family.id]
        if button then return button end
        local sample = family.default or family.variants[1].key
        button = Choice(family.name, eachWide, 24, STRIP_SLOTS, sample, family.id, function()
            picker.view = { kind = "multi", family = family.id }
            picker.Render()
        end)
        button.familyID = family.id
        button:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(family.name, 1, 1, 1)
            local names = {}
            for index, variant in ipairs(family.variants) do names[index] = variant.name end
            GameTooltip:AddLine(table.concat(names, ", "), .65, .78, .75, true)
            if family.source then GameTooltip:AddLine(family.source, .5, .58, .58, true) end
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        picker.families[family.id] = button
        return button
    end

    -- Tabs, then the trail line with the ten role swatches on its right.
    picker.singleTab = Controls().Button(row, "Single Color", third, 21)
    picker.singleTab:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -2)
    picker.singleTab:SetScript("OnClick", function() picker.view = { kind = "single" }; picker.Render() end)
    picker.multiTab = Controls().Button(row, "Multi-Color", third, 21)
    picker.multiTab:SetPoint("TOPLEFT", row, "TOPLEFT", 14 + third, -2)
    picker.multiTab:SetScript("OnClick", function() picker.view = { kind = "multi" }; picker.Render() end)
    picker.customTab = Controls().Button(row, "Custom", third, 21)
    picker.customTab:SetPoint("TOPLEFT", row, "TOPLEFT", 18 + third * 2, -2)
    picker.customTab:SetScript("OnClick", function() picker.view = { kind = "custom" }; picker.Render() end)
    picker.tabs = { single = picker.singleTab, multi = picker.multiTab, custom = picker.customTab }

    -- Under the grid: Customize copies the selected theme into a new Custom
    -- theme; a selected Custom theme also gets Edit, Rename and Delete.
    local function Editor(mode)
        return function()
            local editor = addon.VignetteRadarThemeEditor
            if editor then editor.Open(mode, Current()) end
        end
    end
    local ACTIONS = {
        { "customize", "Customize", "Copy this theme into a new Custom theme, then change its colors." },
        { "edit", "Edit", "Change this Custom theme's name and colors." },
        { "rename", "Rename", "Give this Custom theme a new name." },
        { "delete", "Delete", "Remove this Custom theme (asks first)." },
    }
    picker.actions = {}
    for _, action in ipairs(ACTIONS) do
        local mode, label, help = action[1], action[2], action[3]
        local button = Controls().Button(row, label, eachAction, 21)
        button:SetScript("OnClick", Editor(mode == "customize" and "create" or mode))
        button:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label .. " " .. style.ThemeName(Current()), 1, 1, 1)
            GameTooltip:AddLine(help, .65, .78, .75, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        button:Hide()
        picker.actions[mode] = button
    end
    picker.empty = Label(row, "No Custom themes yet. Pick any theme, then press Customize.",
        12, -THEME_HEAD - 6, 9, width - 24)
    picker.empty:SetTextColor(.62, .70, .70, 1)
    picker.empty:Hide()
    local swatchWidth = #style.slots * 13 - 2
    picker.trail = Label(row, "", 12, -30, 9, width - 32 - swatchWidth)
    for index = 1, #style.slots do
        local x = width - 10 - swatchWidth + (index - 1) * 13
        local frame = row:CreateTexture(nil, "ARTWORK")
        frame:SetSize(13, 13)
        frame:SetPoint("TOPLEFT", row, "TOPLEFT", x - 1, -28)
        frame:SetColorTexture(.85, .9, .9, .3)
        local swatch = row:CreateTexture(nil, "OVERLAY")
        swatch:SetSize(11, 11)
        swatch:SetPoint("TOPLEFT", row, "TOPLEFT", x, -29)
        picker.swatches[index] = swatch
    end
    picker.back = Choice("< Families", eachWide, 24, { "rings" }, "verdant", nil, function()
        picker.view = { kind = "multi" }
        picker.Render()
    end)

    function picker.Highlight()
        local selected = Current()
        local _, family = style.ThemeKind(selected)
        local view = picker.view
        for kind, tab in pairs(picker.tabs) do
            if kind == view.kind then tab:LockHighlight() else tab:UnlockHighlight() end
        end
        for name, button in pairs(quick.themeChoices) do
            if name == selected then button:LockHighlight() else button:UnlockHighlight() end
            MarkSelected(button, name == selected)
        end
        for id, button in pairs(picker.families) do
            local on = family and family.id == id
            if on then button:LockHighlight() else button:UnlockHighlight() end
            MarkSelected(button, on)
        end
        picker.selected = selected
    end

    -- Custom theme buttons are reused by key; names and colors can change.
    local function CustomSignature()
        local parts = {}
        for index, theme in ipairs(style.CustomThemes()) do parts[index] = theme.key .. "=" .. theme.name end
        return table.concat(parts, "\n")
    end

    function picker.Render()
        for _, button in ipairs(picker.all) do button:Hide(); button:ClearAllPoints() end
        local view, lines, pitch = picker.view, 0, WIDE_ROW
        local customs = style.CustomThemes()
        picker.customSignature, picker.customRevision = CustomSignature(), style.revision
        picker.empty:SetShown(view.kind == "custom" and #customs == 0)
        -- Search also finds Custom themes by name.
        local names = {}
        for index, theme in ipairs(customs) do names[index] = theme.name:lower() end
        row.searchText = picker.baseSearch .. " custom customize " .. table.concat(names, " ")
        if view.kind == "custom" then
            lines = #customs == 0 and 1 or 0
            for index, theme in ipairs(customs) do
                local button = Theme(theme.key, theme.name, eachWide, 24, STRIP_SLOTS)
                button:SetText(theme.name)
                PaintStrip(button, theme.key)
                lines = Place(button, index, WIDE_COLUMNS, eachWide, pitch)
            end
        elseif view.kind == "single" then
            pitch = THEME_ROW
            for index, name in ipairs(style.order) do
                lines = Place(Theme(name, style.names[name], eachSingle, 21, { "accent" }),
                    index, THEME_COLUMNS, eachSingle, pitch)
            end
        elseif not FamilyByID(view.family) then
            view.family = nil
            for index, family in ipairs(style.Families()) do
                lines = Place(FamilyButton(family), index, WIDE_COLUMNS, eachWide, pitch)
            end
        else
            lines = Place(picker.back, 1, WIDE_COLUMNS, eachWide, pitch)
            for index, variant in ipairs(FamilyByID(view.family).variants) do
                lines = Place(Theme(variant.key, variant.name, eachWide, 24, STRIP_SLOTS),
                    index + 1, WIDE_COLUMNS, eachWide, pitch)
            end
        end
        local actionsTop = THEME_HEAD + lines * pitch + 2
        local isCustom = style.ThemeKind(Current()) == "custom"
        local slot = 0
        for _, mode in ipairs({ "customize", "edit", "rename", "delete" }) do
            local button = picker.actions[mode]
            local shown = mode == "customize" or isCustom
            button:ClearAllPoints()
            button:SetShown(shown)
            if shown then
                button:SetPoint("TOPLEFT", row, "TOPLEFT", 10 + slot * (eachAction + 4), -actionsTop)
                button.layoutY = actionsTop
                slot = slot + 1
            end
        end
        row:SetHeight(actionsTop + 25)
        picker.Highlight()
        Preview(nil)
        if picker.ready then API.Layout() end
    end

    -- Search finds the row by any theme or family name.
    local words = {}
    for _, choice in ipairs(style.ThemeChoices()) do words[#words + 1] = choice[2]:lower() end
    row.searchText = row.searchText .. " single color multi-color " .. table.concat(words, " ")
    picker.baseSearch = row.searchText

    -- Search lands on the match: a Custom or Single name opens that tab, a
    -- family name opens the family (its variants are the match), a variant
    -- name opens its family. Returns the buttons to highlight, or nil.
    local function Has(text, list)
        text = text:lower()
        for _, word in ipairs(list) do
            if not text:find(word, 1, true) then return false end
        end
        return true
    end
    function picker.Reveal(list)
        local found, view = {}, nil
        for _, theme in ipairs(style.CustomThemes()) do
            if Has(theme.name, list) then found[#found + 1] = theme.key; view = view or { kind = "custom" } end
        end
        if not view then
            for _, family in ipairs(style.Families()) do
                if Has(family.name .. " " .. family.id, list) then
                    view = { kind = "multi", family = family.id }
                    for _, variant in ipairs(family.variants) do found[#found + 1] = variant.key end
                    break
                end
            end
        end
        if not view then
            for _, family in ipairs(style.Families()) do
                for _, variant in ipairs(family.variants) do
                    -- At least one word must name the variant itself.
                    local own = false
                    for _, word in ipairs(list) do
                        if variant.name:lower():find(word, 1, true) then own = true; break end
                    end
                    if own and Has(family.name .. " " .. variant.name, list) then
                        view = view or { kind = "multi", family = family.id }
                        if view.family == family.id then found[#found + 1] = variant.key end
                    end
                end
            end
        end
        if not view then
            for _, name in ipairs(style.order) do
                if Has(style.names[name], list) then found[#found + 1] = name; view = view or { kind = "single" } end
            end
        end
        if not view then
            local tabs = { single = "single color", multi = "multi-color multi color", custom = "custom customize" }
            for kind, text in pairs(tabs) do
                if Has(text, list) then view = { kind = kind } end
            end
            if not view then return nil end
            picker.view = view
            picker.Render()
            return { view.kind == "custom" and picker.actions.customize or picker.tabs[view.kind] }
        end
        picker.view = view
        picker.Render()
        local buttons = {}
        for _, key in ipairs(found) do
            local button = quick.themeChoices[key]
            if button and button:IsShown() then buttons[#buttons + 1] = button end
        end
        return #buttons > 0 and buttons or nil
    end
    -- Called when the search is cleared: back to the selected theme's group.
    function picker.ResetView()
        local view = View()
        if view.kind ~= picker.view.kind or view.family ~= picker.view.family then
            picker.view = view
            picker.Render()
        end
    end
    function row:RevealSearch(list) return picker.Reveal(list) end
    function row:ResetSearch() picker.ResetView() end

    function row:Refresh()
        local selected = Current()
        -- A saved, renamed or deleted Custom theme rebuilds the grid; a color
        -- edit (or live preview) only repaints the Custom strips.
        if picker.customSignature ~= CustomSignature() then
            picker.view = selected ~= picker.selected and View() or picker.view
            picker.Render()
            return
        end
        if picker.customRevision ~= style.revision then
            picker.customRevision = style.revision
            for _, theme in ipairs(style.CustomThemes()) do
                local button = quick.themeChoices[theme.key]
                if button then PaintStrip(button, theme.key) end
            end
        end
        if selected == picker.selected then return end
        -- A change from outside the picker (profile, preset, slash) opens the
        -- new theme's group; a click inside it is already showing it.
        local view = View()
        if view.kind ~= picker.view.kind or (view.kind == "multi" and view.family ~= picker.view.family) then
            picker.view = view
        end
        -- Render also swaps the Custom-only actions under the grid.
        picker.Render()
    end
    picker.Render()
    picker.ready = true
    return row
end

function WIDGETS.poiSources(card, entry, width)
    local function Wheel(_, delta)
        local maxOffset = math.max(0, #(quick.poiEntries or {}) - #quick.poiRows)
        quick.poiOffset = math.max(0, math.min(maxOffset, (quick.poiOffset or 0) - delta))
        RefreshPOISources()
    end
    local row = SourceList(card, entry, width, "poiSources", function(self, mouseButton)
        if not self.sourceID then return end
        if mouseButton == "RightButton" then
            local poi = addon.VignetteRadarPOIs
            local mapID = addon.VignetteRadarAPI.GetCurrentMapID()
            if poi and poi.SetZoneChoice and poi.SetZoneChoice(mapID, self.sourceID) then
                SetSetting(entry.key, "auto")
            end
        else SetSetting(entry.key, self.sourceID) end
    end, Wheel)
    for _, button in ipairs(row.buttons) do
        button:HookScript("OnEnter", function(self)
            if not (GameTooltip and self.sourceID) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.sourceID == "none" and "Hide Map Notes"
                or self.sourceID == "auto" and "Auto: Current Zone" or self.sourceID, 1, 1, 1)
            GameTooltip:AddLine(self.sourceID == "auto"
                and "Automatically pick a pack for each map."
                or "Left-click: use everywhere. Right-click: use only in this zone.", .65, .78, .75, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    quick.poiRows, quick.poiTrack, quick.poiThumb, quick.poiStatus = row.buttons, row.track, row.thumb, row.status
    row.searchText = row.searchText .. " map pack source handynotes off auto"
    return row
end

function WIDGETS.fusionSources(card, entry, width)
    local function Wheel(_, delta)
        local maxOffset = math.max(0, #(quick.fusionEntries or {}) - #quick.fusionRows)
        quick.fusionOffset = math.max(0, math.min(maxOffset, (quick.fusionOffset or 0) - delta))
        RefreshFusionSources()
    end
    local row = SourceList(card, entry, width, "fusionSources", function(self, mouseButton)
        local id = self.sourceID
        if not id then return end
        local db = Settings()
        if mouseButton == "RightButton" then
            db.vignetteRadarFusionPreferred[tostring(addon.VignetteRadarAPI.GetCurrentMapID())] = id
            addon.VignetteRadarAPI.Refresh(true)
        else
            local chosen, found = {}, false
            for _, existing in ipairs(db.vignetteRadarFusionSources) do
                if existing == id then found = true
                else chosen[#chosen + 1] = existing end
            end
            if not found then
                if #chosen >= 8 then return end
                chosen[#chosen + 1] = id
            end
            SetSetting(entry.key, chosen)
        end
        RefreshFusionSources()
    end, Wheel)
    row.track:Hide()
    row.thumb:Hide()
    quick.fusionRows, quick.fusionStatus = row.buttons, row.status
    return row
end

-- Extra rows for cards: tool actions and live status that are not settings.
-- Each list item: after = entry id (or "top"; nil = end of card), build(card, width).
-- level = "advanced" shows the extra only in Advanced mode, like a schema row.
local function Actions(list, advanced, level)
    return { build = function(card, width) return Controls().ActionRow(card, list, width) end,
        advanced = advanced, level = level }
end
local function Status(field, lines, text, level)
    return { build = function(card, width)
        local row = Controls().NoteRow(card, text or "", width, lines)
        quick[field] = row.text
        row.status = true
        return row
    end, level = level }
end

local EXTRAS = {
    ["Range And Size"] = { { after = "vignetteRadarScale", build = Actions({
        { "Preview", function() addon.ToggleVignetteRadarPreview(); API.Reanchor() end },
        { "Reset Positions", function() addon.ResetVignetteRadarPositions(); API.Reanchor() end },
    }).build } },
    Exploring = { Actions({ { "Trail Styles & Flow", function(self) addon.ToggleVignetteRadarTrailPicker(self) end,
        "vignetteRadarTrailStyle" } }, nil, "advanced") },
    Behavior = { Actions({ { "Clear Ignored Vignettes", function()
        if addon.VignetteRadarFeatures and addon.VignetteRadarFeatures.ClearIgnored then
            addon.VignetteRadarFeatures.ClearIgnored()
            addon.VignetteRadarAPI.Refresh(true)
            API.Refresh()
        end
    end } }, nil, "advanced") },
    ["Map Data Packs"] = { Actions({ { "Clear Zone Choice", function()
        local poi = addon.VignetteRadarPOIs
        local mapID = addon.VignetteRadarAPI.GetCurrentMapID()
        if poi and poi.SetZoneChoice and poi.SetZoneChoice(mapID, nil) then
            addon.VignetteRadarAPI.Refresh(true)
            RefreshPOISources()
        end
    end } }, nil, "advanced") },
    ["Hold-To-Filter Key"] = { Actions({ { "Data Status", function(self)
        if addon.ToggleVignetteRadarStatus then addon.ToggleVignetteRadarStatus(self) end
    end } }) },
    ["Quests On The Radar"] = { Actions({
        { "Quest Key", function()
            if addon.VignetteRadarAPI and addon.VignetteRadarAPI.ToggleQuestKey then
                addon.VignetteRadarAPI.ToggleQuestKey()
            end
        end },
        { "Quest Tracker", function()
            if addon.VignetteRadarQuestTracker then addon.VignetteRadarQuestTracker.Toggle() end
        end },
    }) },
    ["World Focus"] = {
        Actions({ { "Previous", function()
            if addon.VignetteRadarWorldFocus then addon.VignetteRadarWorldFocus.Cycle(-1) end
            API.Refresh()
        end }, { "Next", Focus("Cycle") }, { "Next Route Step", Focus("Advance") } }),
        Status("focusStatus", 1),
    },
    -- Guide Panel block order: each button moves its block up one place.
    ["Guide Panel"] = {
        { level = "advanced", build = function(card, width)
            local panel = addon.VignetteRadarGuidePanel
            local row = Controls().NoteRow(card, panel and panel.OrderText(Settings()) or "", width, 2)
            quick.guideOrder = row.text
            row.status = true
            return row
        end },
        Actions((function()
            local list = {}
            for _, block in ipairs({ { "step", "Step" }, { "facts", "Facts" }, { "stops", "Stops" },
                { "compass", "Compass" }, { "briefing", "Briefing" }, { "actions", "Actions" },
                { "notice", "Notices" } }) do
                list[#list + 1] = { block[2], function()
                    local panel = addon.VignetteRadarGuidePanel
                    if not panel then return end
                    panel.MoveBlock(block[1])
                    if quick.guideOrder then quick.guideOrder:SetText(panel.OrderText(Settings())) end
                end }
            end
            return list
        end)(), nil, "advanced"),
    },
    ["Auto Route"] = {
        Actions({ { "Start/Pause", Focus("ToggleRoute") }, { "Skip Stop", Focus("SkipRouteStop") },
            { "Skip Quest", Focus("SkipQuest") } }),
        Status("routeStatus", 2),
    },
    -- Route/world track: Zone Sweep + the Today view, learned data transfer.
    ["Zone Sweep"] = { { after = "top", build = Actions({ { "Sweep Zone", function()
        if addon.VignetteRadarZoneSweep then addon.VignetteRadarZoneSweep.Start() end
        API.Refresh()
    end }, { "Today", function()
        if addon.VignetteRadarTransferBox then addon.VignetteRadarTransferBox.OpenToday() end
    end } }).build } },
    ["Share Learned Data"] = { { after = "top", build = Actions({ { "Export", function()
        if addon.VignetteRadarTransferBox then addon.VignetteRadarTransferBox.Open("export", "all") end
    end }, { "Export Zone", function()
        if addon.VignetteRadarTransferBox then addon.VignetteRadarTransferBox.Open("export", "zone") end
    end }, { "Import", function()
        if addon.VignetteRadarTransferBox then addon.VignetteRadarTransferBox.Open("import") end
    end } }).build } },
    ["Route Draft"] = { Actions({ { "Draft Route", function()
        if addon.VignetteRadarExploration and addon.VignetteRadarExploration.OpenRouteDraft then
            addon.VignetteRadarExploration.OpenRouteDraft()
        end
    end } }) },
    Zygor = {
        Actions({ { "Pin Objective", PinZygor("objective") }, { "Pin Travel Stop", PinZygor("travel") },
            { "Start Follow", function()
                local ok, reason = addon.VignetteRadarAPI.BindZygorGuide()
                if ok then ok, reason = addon.VignetteRadarZygor.ToggleFollow() end
                API.Refresh()
                if not ok and reason then quick.zygorStatus:SetText(reason) end
            end } }),
        Status("zygorStatus", 2),
    },
    ["Bearing Bar"] = { Actions({ { "Preview", function()
        local beacons = addon.VignetteRadarBeacons
        if not beacons then return end
        quick.beaconPreview = not quick.beaconPreview
        beacons.Preview(quick.beaconPreview)
        API.Refresh()
    end } }) },
    Constellation = { Actions({ { "Reset Position", function()
        SetSetting("vignetteRadarConstellationOffsetY", -.05)
    end } }) },
    ["Hunting Presets"] = {
        { after = "top", build = Actions({ { "Treasure", function()
            addon.VignetteRadarExploration.ApplyPreset("Treasure"); API.Refresh()
        end }, { "Rare", function()
            addon.VignetteRadarExploration.ApplyPreset("Rare"); API.Refresh()
        end } }).build },
        { after = "top", build = Actions({ { "Questing", function()
            addon.VignetteRadarExploration.ApplyPreset("Questing"); API.Refresh()
        end }, { "Exploring", function()
            addon.VignetteRadarExploration.ApplyPreset("Exploring"); API.Refresh()
        end } }).build },
        Actions({ { "Undo Last Preset", function()
            local exploration = addon.VignetteRadarExploration
            if exploration and exploration.UndoPreset and exploration.UndoPreset() then
                API.Refresh()
            elseif exploration and exploration.Tell then
                exploration.Tell("Nothing to undo")
            end
        end } }),
        Actions({ { "Saved Presets, Pins & Journal", function()
            if addon.VignetteRadarExploration then addon.VignetteRadarExploration.TogglePanel() end
        end } }),
    },
    ["Planning Tools"] = {
        { after = "top", build = Actions({ { "Expedition Studio", OpenExpeditionStudio },
            { "Living Atlas", ToggleAtlas } }).build },
        { after = "top", build = Actions({ { "Survey & Replay", OpenSurvey }, { "Hunt Intelligence", function()
            local runtime = addon.VignetteRadarFeatureRuntime
            if runtime and runtime.RefreshIntelligence then runtime.RefreshIntelligence() end
            if addon.VignetteRadarIntelligence then addon.VignetteRadarIntelligence.Open() end
        end } }).build },
        { after = "top", build = Actions({ { "Player Tracker", function()
            if addon.VignetteRadarPlayerTracker then addon.VignetteRadarPlayerTracker.Open() end
        end } }).build },
    },
    ["Live Diagnostics"] = {
        { after = "top", build = function(card, width)
            local row = NewRow(card, nil, width, 9 * 18 + 4, "diagnostics")
            quick.diagnosticLines = {}
            for index = 1, 9 do
                quick.diagnosticLines[index] = Label(row, "", 12, -3 - (index - 1) * 18, 9, width - 24)
            end
            row.searchText = "status diagnostics live scan"
            function row:Refresh() end
            return row
        end },
        Actions({ { "Rescan Now", function()
            if addon.VignetteRadarAPI and addon.VignetteRadarAPI.RefreshMapData then
                addon.VignetteRadarAPI.RefreshMapData()
            end
            if API.RefreshStatus then API.RefreshStatus() end
        end }, { "Marker Key", function() if API.ShowGuide then API.ShowGuide(anchor) end end } }),
    },
    Performance = { Status("workload", 2, "Measuring update work...", "advanced"),
        Status("layers", 2, "Measuring drawing layers...", "advanced") },
}

-- Window ------------------------------------------------------------------

local function Query()
    return quick and quick.query or ""
end

local function RowMatches(row, words, matched)
    if row.entry and matched[row.entry.id] then return true end
    if row.status then return false end
    local text = row.searchText or ""
    if text == "" then return false end
    for _, word in ipairs(words) do
        if not text:find(word, 1, true) then return false end
    end
    return true
end

-- Positions rows inside one card; returns the card height, or 0 when hidden.
-- simple hides "advanced" level rows, except while searching (search finds
-- every setting) and on a card OpenPage was asked to show (quick.revealCard).
local function LayoutCard(card, words, matched, advanced, simple)
    if card.advanced and not advanced then card:Hide(); return 0 end
    local searching = words ~= nil
    local allLevels = not simple or searching or quick.revealCard == card
    if not allLevels and card.level == "advanced" then card:Hide(); return 0 end
    local titleMatch = false
    if searching then
        titleMatch = true
        for _, word in ipairs(words) do
            if not card.searchTitle:find(word, 1, true) then titleMatch = false; break end
        end
    end
    local y, column, halfHeight, any = CARD_TOP, 0, 0, false
    for _, row in ipairs(card.rows) do
        local show = (advanced or not row.advanced) and (allLevels or row.level ~= "advanced")
        if show and searching and not titleMatch then show = RowMatches(row, words, matched) end
        row:SetShown(show)
        if show then
            if row.half then
                row:SetPoint("TOPLEFT", card, "TOPLEFT", column * row:GetWidth(), -y)
                row.layoutY = y
                halfHeight = row:GetHeight()
                if column == 1 then y, column = y + halfHeight, 0 else column = 1 end
            else
                if column == 1 then y, column = y + halfHeight, 0 end
                row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -y)
                row.layoutY = y
                y = y + row:GetHeight()
            end
            if row.kind ~= "note" then any = true end
        end
    end
    if column == 1 then y = y + halfHeight end
    -- A card left with only notes (search misses, or Simple mode) hides.
    if not any then card:Hide(); return 0 end
    card:SetHeight(y + 8)
    card:Show()
    return y + 8
end

local function SetScroll(value)
    if not quick then return end
    local height = quick.contentHeight or VIEW_HEIGHT
    local maxScroll = math.max(0, height - VIEW_HEIGHT)
    value = math.max(0, math.min(maxScroll, value or 0))
    quick.scrollOffset = value
    quick.scroll:SetVerticalScroll(value)
    local track = VIEW_HEIGHT - 8
    local thumb = math.max(24, track * math.min(1, VIEW_HEIGHT / math.max(1, height)))
    quick.thumb:SetHeight(thumb)
    quick.thumb:ClearAllPoints()
    quick.thumb:SetPoint("TOPLEFT", quick, "TOPLEFT", WIDTH - 9,
        -HEADER - 4 - (maxScroll > 0 and (track - thumb) * value / maxScroll or 0))
    quick.thumb:SetShown(maxScroll > 0)
end
API.SetScroll = SetScroll

-- Stacks the selected page's cards, or every page's matching rows while
-- searching. Advanced Tools rows and cards appear only while that switch is on.
-- The query's words and the schema entries it matches (nil when not searching).
local function SearchTerms(query, advanced)
    if query == "" then return nil, nil end
    local words, matched = {}, {}
    for word in query:gmatch("%S+") do words[#words + 1] = word end
    for _, entry in ipairs(addon.Schema.Search(query, { advanced = advanced })) do matched[entry.id] = true end
    return words, matched
end

-- True when a page has a row to show outside search, so the rail icons of
-- pages left empty (Simple mode, Advanced Tools off) can hide.
local function PageHasRows(page, advanced, simple)
    for _, card in ipairs(page.cards) do
        if not (card.advanced and not advanced) and not (simple and card.level == "advanced") then
            for _, row in ipairs(card.rows) do
                if (advanced or not row.advanced) and not (simple and row.level == "advanced")
                    and row.kind ~= "note" then
                    return true
                end
            end
        end
    end
    return false
end

-- Stacks the rail icons of pages that have rows; the last page (Tools) keeps
-- its place at the bottom. An empty selected page falls back to the first.
local function LayoutRail(advanced, simple)
    local slot, count = 0, #quick.railButtons
    for index, button in ipairs(quick.railButtons) do
        local shown = PageHasRows(quick.pages[button.pageID], advanced, simple)
        button:SetShown(shown)
        if shown then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", quick, "TOPLEFT", 10,
                index == count and -(HEIGHT - 50) or -HEADER - 2 - slot * 40)
            slot = slot + 1
        elseif quick.selectedPage == button.pageID then
            quick.selectedPage = quick.pageOrder[1]
        end
    end
end

-- Paints the header's Simple / Advanced segments for the saved mode.
local function RefreshModeSwitch()
    if not quick.modeButtons then return end
    local mode = addon.Schema.Mode()
    for _, button in ipairs(quick.modeButtons) do
        button._selected = button.mode == mode
        button:RefreshAppearance()
    end
end

local function Layout()
    if not quick then return end
    local query = Query()
    local advanced = Settings().vignetteRadarAdvancedTools == true
    local simple = addon.Schema.Mode() == "simple"
    local words, matched = SearchTerms(query, advanced)
    LayoutRail(advanced, simple)
    RefreshModeSwitch()
    local y, results = 0, 0
    for _, id in ipairs(quick.pageOrder) do
        local page = quick.pages[id]
        local show = words ~= nil or id == quick.selectedPage
        local height = PAGE_TOP
        if show then
            for _, card in ipairs(page.cards) do
                local cardHeight = LayoutCard(card, words, matched, advanced, simple)
                if cardHeight > 0 then
                    card:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -height)
                    card.offset = height
                    height = height + cardHeight + CARD_GAP
                    results = results + 1
                end
            end
            show = words == nil or height > PAGE_TOP
        end
        page:SetShown(show)
        if show then
            page:SetPoint("TOPLEFT", quick.content, "TOPLEFT", 0, -y)
            page:SetHeight(height)
            page.offset = y
            y = y + height
        end
    end
    quick.noResults:SetShown(words ~= nil and results == 0)
    quick.contentHeight = math.max(VIEW_HEIGHT, y)
    quick.content:SetHeight(quick.contentHeight)
    quick.layoutAdvanced, quick.layoutMode = advanced, simple and "simple" or "advanced"
    SetScroll(quick.scrollOffset or 0)
end
API.Layout = Layout

-- Search landing: every matched control gets a soft accent glow that fades
-- out over FLASH_TIME seconds (no blinking). One small driver frame runs
-- OnUpdate only while a glow is fading.
local FLASH_TIME, FLASH_ALPHA, FLASH_LIMIT = 1.5, .30, 12
local flashes = {}
API.flashes = flashes

local function EndFlash(target)
    flashes[target] = nil
    if target.searchGlow then target.searchGlow:Hide() end
end

local function FlashStep()
    local now = GetTime()
    for target, started in pairs(flashes) do
        local progress = (now - started) / FLASH_TIME
        if progress >= 1 then
            EndFlash(target)
        else
            -- Ease out: bright for a moment, then a gentle fade.
            target.searchGlow:SetAlpha((1 - progress) * (1 - progress))
        end
    end
    if next(flashes) == nil and quick.flashDriver then quick.flashDriver:Hide() end
end

local function Flash(target)
    if not (quick and target and target.CreateTexture) then return end
    local glow = target.searchGlow
    if not glow then
        glow = target:CreateTexture(nil, "BACKGROUND", nil, 2)
        glow:SetAllPoints(target)
        target.searchGlow = glow
    end
    local r, g, b = addon.VignetteRadarStyle.Color("accent")
    glow:SetColorTexture(r, g, b, FLASH_ALPHA)
    glow:SetAlpha(1)
    glow:Show()
    flashes[target] = GetTime()
    if not quick.flashDriver then
        quick.flashDriver = CreateFrame("Frame", nil, quick)
        quick.flashDriver:SetScript("OnUpdate", FlashStep)
    end
    quick.flashDriver:Show()
end
API.Flash = Flash

local function ClearFlashes()
    for target in pairs(flashes) do EndFlash(target) end
    if quick and quick.flashDriver then quick.flashDriver:Hide() end
end

-- Content-space top of a row (its page, card and row offsets added up).
local function RowOffset(row)
    local card = row.card
    local page = card and card.pageFrame
    return (page and page.offset or 0) + (card and card.offset or 0) + (row.layoutY or 0)
end

-- Takes the player to the search results: rows with a sub-view (the theme
-- picker) open the matching part, every match glows, and the first one is
-- scrolled into view. Returns the first target and its content offset.
function API.RevealSearch()
    if not quick then return end
    ClearFlashes()
    local advanced = Settings().vignetteRadarAdvancedTools == true
    local words, matched = SearchTerms(Query(), advanced)
    if not words then return end
    local hits = {}
    for _, id in ipairs(quick.pageOrder) do
        for _, card in ipairs(quick.pages[id].cards) do
            if card:IsShown() then
                for _, row in ipairs(card.rows) do
                    if row:IsShown() and RowMatches(row, words, matched) then hits[#hits + 1] = row end
                end
            end
        end
    end
    -- Reveal first: opening a sub-view can change row heights and positions.
    local targets, first, firstRow = {}, nil, nil
    for _, row in ipairs(hits) do
        local inner = row.RevealSearch and row:RevealSearch(words)
        for _, target in ipairs(inner or { row }) do
            targets[#targets + 1] = target
            if not first then first, firstRow = target, row end
        end
    end
    for index = 1, math.min(FLASH_LIMIT, #targets) do Flash(targets[index]) end
    if not first then return end
    local offset = RowOffset(firstRow) + (first ~= firstRow and first.layoutY or 0)
    SetScroll(offset - 36)
    quick.searchTarget, quick.searchOffset = first, offset
    return first, offset
end

-- Runs the landing once typing pauses, so each keystroke does not glow.
local function QueueReveal()
    quick.searchToken = (quick.searchToken or 0) + 1
    local token, query = quick.searchToken, Query()
    local function Run()
        if quick.searchToken == token and Query() == query and quick:IsShown() then API.RevealSearch() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(.4, Run) else Run() end
end

local function RefreshSettingsDot()
    local style = addon.VignetteRadarStyle
    if not (style and anchor and anchor.settingsDot) then return end
    local ar, ag, ab = style.Color("accent")
    anchor.settingsDot.rim:SetVertexColor(ar, ag, ab, quick:IsShown() and .68 or .20)
end

local function IconCoords(texture, column, state)
    texture:SetTexCoord((column * 64 + 1) / 1024, (column * 64 + 63) / 1024,
        (state * 64 + 1) / 256, (state * 64 + 63) / 256)
end

local function RefreshSkin()
    local style = addon.VignetteRadarStyle
    if not style then return end
    local ar, ag, ab = style.Color("accent")
    local rr, rg, rb = style.Color("rings")
    local controls = Controls()
    controls.RefreshPopupSurface(quick)
    local tray = addon.VignetteRadarTray
    -- The settings text must stay readable whatever the radar's opacity is.
    if tray and tray.SkinLikeRadar then tray.SkinLikeRadar(quick, .96) end
    -- The radar surface is near black in every theme, so the window carries
    -- the theme itself: a face tinted toward the accent, an accent outline and
    -- accent dividers. Text stays light on it in every theme.
    local br, bg, bb = style.Color("background")
    for _, face in ipairs(quick.popupFaceSlices or {}) do
        face:SetVertexColor(math.min(.2, br * .8 + ar * .11), math.min(.2, bg * .8 + ag * .11),
            math.min(.2, bb * .8 + ab * .11), .97)
    end
    for _, edge in ipairs(quick.popupEdgeSlices or {}) do edge:SetVertexColor(ar, ag, ab, .62) end
    quick.title:SetTextColor(ar, ag, ab, 1)
    quick.bead:SetVertexColor(ar, ag, ab, 1)
    quick.railLine:SetColorTexture(ar, ag, ab, .38)
    quick.headerLine:SetColorTexture(ar, ag, ab, .38)
    quick.thumb:SetColorTexture(ar, ag, ab, .55)
    quick.searchIcon:SetVertexColor(ar, ag, ab, .9)
    quick.searchInput:SetBackdropBorderColor(rr, rg, rb, quick.searchFocused and .6 or .22)
    if quick.poiThumb then quick.poiThumb:SetColorTexture(ar, ag, ab, .7) end
    if quick.customLabel then
        quick.customLabel:SetText(style.IsCustomized() and "Custom Colors" or "Theme Colors")
    end
    controls.RefreshTheme()
    -- The radar redraws call Refresh often; repaint the many cards only when
    -- the accent or ring color actually changed.
    local key = string.format("%.3f %.3f %.3f %.3f %.3f %.3f", ar, ag, ab, rr, rg, rb)
    if quick.skinKey == key then return end
    quick.skinKey = key
    for _, button in ipairs(quick.railButtons) do button:RefreshAppearance() end
    for _, page in pairs(quick.pages) do page.heading:SetTextColor(ar, ag, ab, 1) end
    for _, card in pairs(cards) do
        card:RefreshTheme(rr, rg, rb, .095)
        card.title:SetTextColor(ar, ag, ab, .92)
    end
end

function API.Refresh()
    if not quick then return end
    -- The radar's settings dot reflects open/closed even while the panel is hidden;
    -- the rest of the panel is only refreshed while the player can see it.
    if not quick:IsShown() then RefreshSettingsDot(); return end
    local db = Settings()
    if quick.layoutAdvanced ~= (db.vignetteRadarAdvancedTools == true)
        or quick.layoutMode ~= addon.Schema.Mode() then
        Layout()
    end
    local focus = addon.VignetteRadarWorldFocus
    local focusText = focus and focus.Status() or "Waypoint data unavailable"
    if quick.focusStatus then quick.focusStatus:SetText(focusText) end
    if quick.routeStatus then quick.routeStatus:SetText(focusText) end
    local zygor = addon.VignetteRadarZygor
    if quick.zygorStatus and zygor then
        quick.zygorStatus:SetText(quick.zygorError or (zygor.GuideLabel() .. "\n" .. zygor.Status()))
        if quick.zygorFollow then
            quick.zygorFollow:SetText(zygor.IsPaused() and "Resume Follow"
                or zygor.IsFollowing() and "Pause Follow" or "Start Follow")
        end
    end
    if quick.workload then
        local budget = addon.VignetteRadarBudget
        local recent = budget and budget.recent or {}
        local total = (recent.radar or 0) + (recent.launcher or 0) + (recent.background or 0)
        quick.workload:SetText(budget and next(budget.paused)
            and string.format("Recent update work: %.1f ms/sec · retrying automatically", total)
            or budget and budget.softThrottle
                and string.format("Recent update work: %.1f ms/sec · temporarily slowed", total)
                or string.format("Recent update work: %.1f ms/sec", total))
        local layerBudget = addon.VignetteRadarLayerBudget
        if quick.layers and layerBudget then quick.layers:SetText(layerBudget.StatusLine()) end
    end
    if quick.beaconPreviewButton then
        quick.beaconPreviewButton:SetText(quick.beaconPreview and "Stop Preview" or "Preview")
    end
    for _, row in ipairs(rows) do
        if row:IsShown() then row:Refresh() end
    end
    -- The pack lists query HandyNotes; only do that while they can be seen.
    if quick.pages.Markers:IsShown() then
        RefreshPOISources()
        RefreshFusionSources()
    end
    RefreshSkin()
    RefreshSettingsDot()
end

local function SelectPage(name, keepSearch)
    if not quick then return end
    if quick.pages[name] then quick.selectedPage = name end
    quick.revealCard = nil
    if not keepSearch and Query() ~= "" then
        quick.query = ""
        quick.searchInput:SetText("")
        quick.searchHint:Show()
        if quick.searchClear then quick.searchClear:Hide() end
        ClearFlashes()
        for _, row in ipairs(rows) do
            if row.ResetSearch then row:ResetSearch() end
        end
    end
    for _, button in ipairs(quick.railButtons) do
        button._selected = button.pageID == quick.selectedPage and Query() == ""
        button:RefreshAppearance()
    end
    quick.scrollOffset = 0
    Layout()
    if quick.selectedPage == "Tools" and API.RefreshStatus then API.RefreshStatus() end
    API.Refresh()
end

function API.RefreshStatus()
    if not (quick and quick.diagnosticLines) then return end
    local lines = addon.GetVignetteRadarDiagnostics and addon.GetVignetteRadarDiagnostics() or {}
    for index, label in ipairs(quick.diagnosticLines) do
        label:SetText(lines[index] or "")
    end
end

local function OnSearchChanged()
    if not (quick and quick.searchInput) then return end
    local text = (quick.searchInput:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local changed = text ~= quick.query
    quick.query = text
    quick.searchHint:SetShown(text == "" and not quick.searchFocused)
    if quick.searchClear then quick.searchClear:SetShown((quick.searchInput:GetText() or "") ~= "") end
    for _, button in ipairs(quick.railButtons) do
        button._selected = text == "" and button.pageID == quick.selectedPage
        button:RefreshAppearance()
    end
    quick.scrollOffset = 0
    if text == "" and changed then
        -- Back to the normal page: sub-views return to the selected setting.
        ClearFlashes()
        for _, row in ipairs(rows) do
            if row.ResetSearch then row:ResetSearch() end
        end
    end
    Layout()
    API.Refresh()
    if text ~= "" and changed then QueueReveal() end
end
API.OnSearchChanged = OnSearchChanged

local function RailButton(page, y)
    local button = CreateFrame("Button", nil, quick)
    button:SetSize(36, 36)
    button:SetPoint("TOPLEFT", quick, "TOPLEFT", 10, y)
    button.pageID, button.column = page.id, page.icon or 0
    -- Layered icon (UI/IconButton.lua): glyph, border, plate, glow and mark
    -- each take their own theme role; the old state atlas is the fallback.
    local icons = addon.VignetteRadarIconButton
    local railGlyph = icons and icons.RAIL[button.column + 1]
    if railGlyph then
        icons.AddLayers(button, "rail_" .. railGlyph, 32)
    else
        button.art = button:CreateTexture(nil, "ARTWORK")
        button.art:SetTexture(ICONS)
        button.art:SetSize(32, 32)
        button.art:SetPoint("CENTER")
    end
    function button:RefreshAppearance()
        if self.iconLayers then
            icons.Paint(self, self._selected == true, self._hovered == true)
        else
            IconCoords(self.art, self.column, (self._selected and 2 or 0) + (self._hovered and 1 or 0))
        end
        -- No tile behind the icon: its own glyph color and underline mark
        -- the open page.
        local style = addon.VignetteRadarStyle
        if style and not self.iconLayers then self.art:SetVertexColor(style.Color("accent")) end
    end
    button:SetScript("OnClick", function() SelectPage(page.id) end)
    button:SetScript("OnEnter", function(self)
        self._hovered = true
        self:RefreshAppearance()
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(page.title, 1, 1, 1)
            if page.tooltip then GameTooltip:AddLine(page.tooltip, .65, .78, .75, true) end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self._hovered = false
        self:RefreshAppearance()
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:RefreshAppearance()
    return button
end

local function AddRow(card, row, advanced, level)
    row.card = card
    row.advanced = advanced or (row.entry and row.entry.advanced) or false
    row.level = level or (row.entry and addon.Schema.Level(row.entry)) or "simple"
    card.rows[#card.rows + 1] = row
    rows[#rows + 1] = row
    return row
end

local function AddExtras(card, extras, position)
    for _, extra in ipairs(extras) do
        if extra.after == position then
            AddRow(card, extra.build(card, CARD_WIDTH), extra.advanced, extra.level)
        end
    end
end

local function BuildCard(page, section)
    local controls = Controls()
    local card = controls.Section(page, section.title, CARD_WIDTH)
    card.advanced, card.level = section.advanced, section.level
    card.searchTitle = (section.title .. " " .. page.id):lower()
    card.pageFrame = page
    cards[page.id .. "/" .. section.title] = card
    local extras = EXTRAS[section.title] or {}
    AddExtras(card, extras, "top")
    for _, entry in ipairs(section.entries) do
        local row
        if entry.widget and WIDGETS[entry.widget] then
            row = WIDGETS[entry.widget](card, entry, CARD_WIDTH)
        elseif entry.type == "color" then
            row = controls.ColorRow(card, entry, CARD_WIDTH / 2)
            row.half = true
        else
            row = controls.Row(card, entry, CARD_WIDTH)
        end
        AddRow(card, row)
        AddExtras(card, extras, entry.id)
    end
    AddExtras(card, extras, nil)
    if section.note then AddRow(card, controls.NoteRow(card, section.note, CARD_WIDTH), nil, section.level) end
    if section.title == "Colors" then quick.customLabel = card.title end
    page.cards[#page.cards + 1] = card
    return card
end

-- Header switch: two small flat segments between the title and the search
-- box. Simple shows the settings most players need, Advanced every row
-- (schema `level` tags). Both segments share the width of the longer
-- measured label, so text never truncates; the search box takes the rest.
local MODE_TIP = "Simple shows the settings most players need. Advanced shows every setting. "
    .. "Search always finds every setting."
local function BuildModeSwitch()
    local controls, style = Controls(), addon.VignetteRadarStyle
    quick.modeButtons = {}
    for index, mode in ipairs({ { "simple", "Simple" }, { "advanced", "Advanced" } }) do
        local button = controls.Button(quick, mode[2], 60, 22)
        button.mode = mode[1]
        button:SetScript("OnClick", function()
            if addon.Schema.Mode() == mode[1] then return end
            quick.scrollOffset = 0
            addon.Schema.SetMode(mode[1])
        end)
        button:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(mode[2] .. " Settings", 1, 1, 1)
            GameTooltip:AddLine(MODE_TIP, .65, .78, .75, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        quick.modeButtons[index] = button
    end
    local closeLeft, gap, searchMin, searchMax = WIDTH - 32, 8, 120, 168
    local each = 0
    for _, button in ipairs(quick.modeButtons) do each = math.max(each, controls.ButtonWidth(button)) end
    local switchWidth = each * 2 + 2
    local function SearchRoom()
        local titleRight = quick.title:IsShown() and 46 + math.ceil(style.TextWidth(quick.title)) + 10 or 46
        return math.min(searchMax, closeLeft - gap - switchWidth - gap - titleRight)
    end
    -- Large Text Size: the title shortens, then yields (the radar bead still
    -- marks the window), so the search box keeps a usable width.
    local searchWidth = SearchRoom()
    if searchWidth < searchMin then
        quick.title:SetText("Settings")
        searchWidth = SearchRoom()
    end
    if searchWidth < searchMin then
        quick.title:Hide()
        searchWidth = SearchRoom()
    end
    local searchLeft = closeLeft - gap - searchWidth
    quick.searchInput:SetWidth(searchWidth)
    quick.searchInput:ClearAllPoints()
    quick.searchInput:SetPoint("TOPLEFT", quick, "TOPLEFT", searchLeft, -10)
    local left = searchLeft - gap - switchWidth
    for index, button in ipairs(quick.modeButtons) do
        controls.SizeButton(button, each, 22)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", quick, "TOPLEFT", left + (index - 1) * (each + 2), -10)
    end
    -- The placeholder keeps its long form only when it fits the box.
    quick.searchHint:SetWidth(searchWidth - 28)
    if style.TextWidth(quick.searchHint) > searchWidth - 28 then quick.searchHint:SetText("Search") end
    RefreshModeSwitch()
end

local function Build()
    if quick then return quick end
    local controls = Controls()
    quick = CreateFrame("Frame", "VignetteRadarQuickConfigPanel", UIParent, "BackdropTemplate")
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarQuickConfigPanel"
    end
    quick:SetSize(WIDTH, HEIGHT)
    quick:SetFrameStrata("DIALOG")
    quick:SetClampedToScreen(true)
    quick:EnableMouse(true)
    quick:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    controls.PopupSurface(quick)
    quick.pages, quick.pageOrder, quick.railButtons, quick.cards = {}, {}, {}, cards
    quick.rows, quick.query = rows, ""

    -- Header: radar icon, title, search, close.
    quick.bead = quick:CreateTexture(nil, "OVERLAY")
    quick.bead:SetTexture(ICONS)
    IconCoords(quick.bead, 0, 0)
    quick.bead:SetSize(24, 24)
    quick.bead:SetPoint("TOPLEFT", quick, "TOPLEFT", 16, -10)
    quick.title = Label(quick, "Magpie Settings", 46, -15, 12, 150)
    quick.headerLine = quick:CreateTexture(nil, "ARTWORK")
    quick.headerLine:SetPoint("TOPLEFT", quick, "TOPLEFT", RAIL, -HEADER + 2)
    quick.headerLine:SetPoint("TOPRIGHT", quick, "TOPRIGHT", -10, -HEADER + 2)
    quick.headerLine:SetHeight(1)
    local close = controls.Button(quick, "×", 22, 22)
    close:SetPoint("TOPLEFT", quick, "TOPLEFT", WIDTH - 32, -10)
    close:SetScript("OnClick", function() quick:Hide() end)
    quick.close = close

    local input = CreateFrame("EditBox", nil, quick, "BackdropTemplate")
    input:SetSize(168, 22)
    input:SetPoint("TOPLEFT", quick, "TOPLEFT", WIDTH - 32 - 8 - 168, -10)
    input:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    input:SetBackdropColor(0, 0, 0, .22)
    addon.VignetteRadarStyle.SetFont(input, 10, "")
    input:SetTextInsets(24, 24, 0, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(40)
    input:SetScript("OnTextChanged", OnSearchChanged)
    -- Escape while typing clears the search first; with focus gone, the next
    -- Escape closes the window through UISpecialFrames.
    input:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        OnSearchChanged()
    end)
    -- Enter jumps straight to the first match.
    input:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        API.RevealSearch()
    end)
    -- A clear "x" inside the right edge, shown only while there is text.
    local function ClearSearch()
        input:SetText("")
        input:ClearFocus()
        OnSearchChanged()
    end
    local icons = addon.VignetteRadarIconButton
    if icons and icons.Create and icons.HasIcon("close") then
        quick.searchClear = icons.Create(input, "close", { label = "Clear Search", size = 18,
            artSize = 16, onClick = ClearSearch })
    else
        quick.searchClear = controls.Button(input, "×", 18, 18)
        quick.searchClear:SetScript("OnClick", ClearSearch)
        quick.searchClear:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Clear Search", 1, 1, 1)
            GameTooltip:Show()
        end)
        quick.searchClear:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    quick.searchClear:SetPoint("RIGHT", input, "RIGHT", -3, 0)
    quick.searchClear:Hide()
    input:SetScript("OnEditFocusGained", function()
        quick.searchFocused = true
        quick.searchHint:Hide()
        RefreshSkin()
    end)
    input:SetScript("OnEditFocusLost", function()
        quick.searchFocused = false
        quick.searchHint:SetShown(Query() == "")
        RefreshSkin()
    end)
    quick.searchInput = input
    quick.searchIcon = input:CreateTexture(nil, "OVERLAY")
    quick.searchIcon:SetTexture(ICONS)
    IconCoords(quick.searchIcon, SEARCH_ICON, 0)
    quick.searchIcon:SetSize(18, 18)
    quick.searchIcon:SetPoint("LEFT", input, "LEFT", 4, 0)
    quick.searchHint = Label(input, "Search Settings", 24, -6, 10, 130)
    quick.searchHint:SetTextColor(.55, .62, .62, 1)
    BuildModeSwitch()

    -- Rail: one radar-style icon per schema page; Tools sits at the bottom.
    quick.railLine = quick:CreateTexture(nil, "ARTWORK")
    quick.railLine:SetPoint("TOPLEFT", quick, "TOPLEFT", RAIL, -HEADER + 2)
    quick.railLine:SetPoint("BOTTOMLEFT", quick, "BOTTOMLEFT", RAIL, 10)
    quick.railLine:SetWidth(1)

    -- Content: one scroll view holding every page; Layout() shows one at a time.
    quick.scroll = CreateFrame("ScrollFrame", nil, quick)
    quick.scroll:SetSize(VIEW_WIDTH, VIEW_HEIGHT)
    quick.scroll:SetPoint("TOPLEFT", quick, "TOPLEFT", VIEW_X, -HEADER)
    quick.scroll:SetClipsChildren(true)
    quick.scroll:EnableMouseWheel(true)
    quick.content = CreateFrame("Frame", nil, quick.scroll)
    quick.content:SetSize(VIEW_WIDTH, VIEW_HEIGHT)
    quick.scroll:SetScrollChild(quick.content)
    quick.scroll:SetScript("OnMouseWheel", function(_, delta)
        SetScroll((quick.scrollOffset or 0) - delta * 48)
    end)
    quick.thumb = quick:CreateTexture(nil, "OVERLAY")
    quick.thumb:SetWidth(3)
    quick.noResults = Label(quick.content, "No matching setting.", 8, -12, 11, VIEW_WIDTH - 16)

    local pages = addon.Schema.Pages()
    for index, pageSpec in ipairs(pages) do
        local page = CreateFrame("Frame", nil, quick.content)
        page:SetSize(VIEW_WIDTH, PAGE_TOP)
        page.id, page.cards = pageSpec.id, {}
        page.heading = Label(page, pageSpec.title, 4, -6, 14, VIEW_WIDTH - 8)
        page:Hide()
        quick.pages[pageSpec.id], quick.pageOrder[index] = page, pageSpec.id
        local last = index == #pages
        local button = RailButton(pageSpec, last and -(HEIGHT - 50) or -HEADER - 2 - (index - 1) * 40)
        quick.railButtons[index] = button
        for _, section in ipairs(pageSpec.sections) do BuildCard(page, section) end
    end
    for _, row in ipairs(rows) do
        for _, button in ipairs(row.buttons or {}) do
            if button:GetText() == "Start Follow" then quick.zygorFollow = button end
            if button:GetText() == "Preview" and row.card == cards["HUD/Bearing Bar"] then
                quick.beaconPreviewButton = button
            end
        end
    end

    quick.selectedPage = quick.pageOrder[1]
    SelectPage(quick.selectedPage)
    quick:SetScript("OnShow", API.Refresh)
    quick:SetScript("OnHide", function()
        if quick.beaconPreview and addon.VignetteRadarBeacons then
            addon.VignetteRadarBeacons.Preview(false)
        end
        quick.beaconPreview = false
        API.Refresh()
    end)
    quick:Hide()
    return quick
end

-- Every Schema.Set (from this window, a hover tool or a slash command) lands
-- here: remember a failed Zygor follow, record view profiles, and refresh the
-- quest tracker and this window.
if addon.Schema then
    addon.Schema.OnChange(function(key, value, _, ok, reason)
        if key == "vignetteRadarFollowZygor" and quick then
            quick.zygorError = not ok and (reason or "Zygor is unavailable") or nil
        end
        if key == "vignetteRadarControlsVisible" and addon.VignetteRadarViewProfiles then
            addon.VignetteRadarViewProfiles.Record(Settings())
        elseif key == "vignetteRadarIndependentViews" and value == true and addon.VignetteRadarViewProfiles then
            addon.VignetteRadarViewProfiles.Record(Settings())
        end
        if addon.VignetteRadarQuestTracker then addon.VignetteRadarQuestTracker.Refresh() end
        API.Refresh()
    end)
end

function API.ShowGuide(anchorFrame)
    if not guide then
        guide = CreateFrame("Frame", "VignetteRadarGuidePanel", UIParent, "BackdropTemplate")
        guide:SetSize(238, 211)
        guide:SetFrameStrata("DIALOG")
        guide:SetClampedToScreen(true)
        guide:EnableMouse(true)
        guide:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        addon.VignetteRadarControls.PopupSurface(guide)
        if type(UISpecialFrames) == "table" then
            UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarGuidePanel"
        end
        local title = Label(guide, "Marker Key", 14, -12, 11, 194)
        guide.title = title
        title:SetTextColor(addon.VignetteRadarStyle.Color("accent"))
        local items = {
            { "boss", "World Boss", "boss" },
            { "rare", "Rare", "rare" },
            { "treasure", "Treasure or Chest", "treasure" },
            { "quest", "Quest (Solid When Complete)", "quest" },
            { "note", "Saved Map Note", "other" },
            { "area", "Shaded Area: Quest Search Zone", "quest" },
        }
        guide.symbols = {}
        for index, item in ipairs(items) do
            local symbol = CreateFrame("Frame", nil, guide)
            symbol:SetSize(21, 21)
            symbol:SetPoint("TOPLEFT", guide, "TOPLEFT", 15, -36 - (index - 1) * 23)
            symbol:Show()
            local parts = {}
            local function AddTexture(path, size, dx, dy, opacity)
                local texture = symbol:CreateTexture(nil, "ARTWORK")
                texture:SetSize(size, size)
                texture:SetPoint("CENTER", symbol, "CENTER", dx or 0, dy or 0)
                texture:SetTexture(path)
                parts[#parts + 1] = { texture = texture, opacity = opacity or 1 }
                return texture
            end
            if item[1] == "boss" or item[1] == "rare" then
                AddTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
                    item[1] == "boss" and 18 or 15)
            elseif item[1] == "treasure" then
                local icon = AddTexture("Interface\\Icons\\INV_Misc_Chest_01", 15)
                if icon.SetAtlas then pcall(icon.SetAtlas, icon, "VignetteLoot") end
            elseif item[1] == "quest" then
                AddTexture("Interface\\AddOns\\Magpie\\Media\\quest-diamond-hollow.tga", 14)
            elseif item[1] == "note" then
                AddTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", 11)
                local core = symbol:CreateTexture(nil, "OVERLAY")
                core:SetSize(4, 4)
                core:SetPoint("CENTER")
                core:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                core:SetVertexColor(.02, .03, .035, 1)
            else
                AddTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", 16, -2, 1, .22)
                AddTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", 12, 3, -2, .18)
            end
            guide.symbols[index] = { frame = symbol, slot = item[3], parts = parts,
                label = Label(guide, item[2], 43, -39 - (index - 1) * 23, 10, 184) }
        end
        local controls = {
            "Click — Focus / Show All",
            "Shift-Click — Navigate",
            "Alt-Click — Favorite",
            "Right-Click — Ignore This Session",
            "Shift-Right-Click — Remember Ignore",
            "Ctrl-Click — Add Route Stop",
            "Ctrl-Alt-Click — Watch Approach",
        }
        guide.controlLines = {}
        for index, line in ipairs(controls) do
            local label = Label(guide, line, 15, -38 - (index - 1) * 20, 9, 210)
            label:Hide()
            guide.controlLines[index] = label
        end
        local function SelectGuidePage(name)
            local symbols = name == "Symbols"
            for _, row in ipairs(guide.symbols) do
                row.frame:SetShown(symbols)
                row.label:SetShown(symbols)
            end
            for _, label in ipairs(guide.controlLines) do label:SetShown(not symbols) end
            if guide.symbolTab and guide.controlTab then
                if symbols then
                    guide.symbolTab:LockHighlight()
                    guide.controlTab:UnlockHighlight()
                else
                    guide.controlTab:LockHighlight()
                    guide.symbolTab:UnlockHighlight()
                end
            end
            guide.page = name
        end
        guide.symbolTab = addon.VignetteRadarControls.Button(guide, "Symbols", 100, 20)
        guide.symbolTab:SetPoint("TOPLEFT", guide, "TOPLEFT", 15, -182)
        guide.symbolTab:SetScript("OnClick", function() SelectGuidePage("Symbols") end)
        guide.controlTab = addon.VignetteRadarControls.Button(guide, "Controls", 100, 20)
        guide.controlTab:SetPoint("TOPLEFT", guide, "TOPLEFT", 123, -182)
        guide.controlTab:SetScript("OnClick", function() SelectGuidePage("Controls") end)
        SelectGuidePage("Symbols")
        local close = addon.VignetteRadarControls.Button(guide, "×", 20, 20)
        close:SetPoint("TOPRIGHT", -8, -7)
        close:SetScript("OnClick", function() guide:Hide() end)
        guide:Hide()
    end
    addon.VignetteRadarControls.RefreshPopupSurface(guide)
    guide.title:SetTextColor(addon.VignetteRadarStyle.Color("accent"))
    for _, symbol in ipairs(guide.symbols) do
        local red, green, blue = addon.VignetteRadarStyle.Color(symbol.slot)
        for _, part in ipairs(symbol.parts) do
            part.texture:SetVertexColor(red, green, blue, part.opacity)
        end
    end
    guide:ClearAllPoints()
    if anchorFrame then guide:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 8, 0)
    else guide:SetPoint("CENTER", UIParent, "CENTER") end
    guide:Show()
end

function API.ShowFirstRunGuide(anchorFrame)
    local db = Settings()
    if db.vignetteRadarGuideSeen then return end
    db.vignetteRadarGuideSeen = true
    API.ShowGuide(anchorFrame)
end

local function PositionAt(anchorFrame)
    if not quick then return end
    local source = anchorFrame or anchor
    quick:ClearAllPoints()
    quick:SetScale(1)
    if not source then
        quick:SetPoint("CENTER", UIParent, "CENTER")
        return
    end
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local left, right, top, bottom = source:GetLeft(), source:GetRight(), source:GetTop(), source:GetBottom()
    local sourceScale = source:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if left then left = left * sourceScale end
    if right then right = right * sourceScale end
    if top then top = top * sourceScale end
    if bottom then bottom = bottom * sourceScale end
    local rightSpace = right and screenWidth - right - 12 or 0
    local leftSpace = left and left - 12 or 0
    if rightSpace >= WIDTH + 8 then
        quick:SetPoint("TOPLEFT", source, "TOPRIGHT", 8, 0)
    elseif leftSpace >= WIDTH + 8 then
        quick:SetPoint("TOPRIGHT", source, "TOPLEFT", -8, 0)
    elseif bottom and bottom >= HEIGHT + 12 then
        quick:SetPoint("TOP", source, "BOTTOM", 0, -8)
    elseif top and screenHeight - top >= HEIGHT + 12 then
        quick:SetPoint("BOTTOM", source, "TOP", 0, 8)
    elseif rightSpace >= WIDTH * .65 + 8 then
        quick:SetScale(math.min(1, (rightSpace - 8) / WIDTH))
        quick:SetPoint("TOPLEFT", source, "TOPRIGHT", 8, 0)
    elseif leftSpace >= WIDTH * .65 + 8 then
        quick:SetScale(math.min(1, (leftSpace - 8) / WIDTH))
        quick:SetPoint("TOPRIGHT", source, "TOPLEFT", -8, 0)
    else
        quick:SetScale(math.min(1, (screenWidth - 24) / WIDTH, (screenHeight - 24) / HEIGHT))
        quick:SetPoint("CENTER", UIParent, "CENTER")
    end
    anchor = source
end

-- A schema page id, or an old tab/sub-page name; returns page and card title.
local function ResolvePage(name)
    if type(name) ~= "string" then return quick.pageOrder[1] end
    if quick.pages[name] then return name end
    local legacy = LEGACY_PAGES[name]
    if legacy then return legacy[1], legacy[2] end
    for _, id in ipairs(quick.pageOrder) do
        if id:lower() == name:lower() then return id end
    end
    return quick.pageOrder[1]
end
API.ResolvePage = function(name)
    Build()
    return ResolvePage(name)
end

function API.ScrollToCard(page, section)
    local card = cards[tostring(page) .. "/" .. tostring(section)]
    if not (quick and card and card:IsShown() and card.offset) then return end
    -- The first card keeps the page heading in view; later cards scroll to their title.
    SetScroll(card.offset <= PAGE_TOP and 0 or card.offset - 6)
end

function API.Toggle(anchorFrame)
    local frame = Build()
    if frame:IsShown() then frame:Hide(); return false end
    PositionAt(anchorFrame)
    frame:Show()
    API.Refresh()
    return true
end

-- Opens the window on a page. Accepts new page ids ("Routes"), card names
-- through the old page names ("Auto Route" opens Routes at its card), and
-- "Search" (focuses the search box).
function API.OpenPage(name, anchorFrame)
    local frame = Build()
    PositionAt(anchorFrame)
    if name == "Search" then
        frame:Show()
        API.Refresh()
        if quick.searchInput.SetFocus then quick.searchInput:SetFocus() end
        return
    end
    local page, section = ResolvePage(name)
    SelectPage(page)
    -- A card Simple mode hides still opens when asked for by name: it shows
    -- in full until the player picks another page.
    local card = section and cards[page .. "/" .. section]
    if card and quick.layoutMode == "simple" and not card:IsShown() then
        quick.revealCard = card
        Layout()
    end
    frame:Show()
    API.Refresh()
    if section then API.ScrollToCard(page, section) end
end

function API.Reanchor(anchorFrame)
    if quick and quick:IsShown() then PositionAt(anchorFrame) end
end

function API.Hide()
    if quick then quick:Hide() end
end

function API.IsShown()
    return quick and quick:IsShown() or false
end

function API.GetPanel()
    return quick
end
