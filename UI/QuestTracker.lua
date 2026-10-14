local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarQuestTracker = API

-- Content inset from the side borders: just past the 8 px rounded corner.
local SIDE = 9
local WIDTH, HEADER_HEIGHT, HEADER_ROW_HEIGHT, QUEST_ROW_HEIGHT = 306, 47, 20, 32
local VISIBLE_ROWS, MAX_ROWS, FOOTER_HEIGHT = 8, 20, 17
-- Size limits for the detached (floating) tracker.
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 260, 120, 560, 700
-- Status-surface edge pieces hidden on the side that joins the radar.
local trayOptions
local areaFiltered = false
-- Watched quests shown in the "Quests Here Only" list.
local MAX_HERE_WATCHED = 10
-- Docked, the tray is never narrower than the detached panel's minimum.
local MIN_TRAY_WIDTH = MIN_WIDTH
local HereEntries
local DIAMOND = "Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga"
local HOLLOW = "Interface\\AddOns\\Magpie\\Media\\quest-diamond-hollow.tga"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TASK_KINDS = { "World Quests", "Bonus Objectives" }
local frame, menu, entries, offset = nil, nil, {}, 0
local lastThemeRevision = -1
local RefreshMenu

local Field = addon.Secret.Field
local Number, Call, SecretText = addon.Secret.Number, addon.Secret.Call, addon.Secret.Text

local function Word(value)
    return SecretText(value, 150, true)
end

local function Settings() return addon.GetSettings() end

local function MapID()
    local radar = addon.VignetteRadarAPI
    local value = radar and radar.GetCurrentMapID and radar.GetCurrentMapID()
    if Number(value) then return value end
    return Call(C_Map, "GetBestMapForUnit", "player")
end

local function QuestSlot(questID)
    local radar = addon.VignetteRadarAPI
    local slot = radar and radar.GetQuestColorSlot and radar.GetQuestColorSlot(questID)
    return Number(slot) or 1
end

local function QuestColor(slot)
    local palette = addon.VignetteRadarQuestColors
    local color = palette and palette[slot]
    if color then return color[1], color[2], color[3] end
    local style = addon.VignetteRadarStyle
    if style then return style.Color("quest") end
    return 1, .74, .27
end

local function DifficultyColor(level)
    if level and type(GetQuestDifficultyColor) == "function" then
        local ok, color = pcall(GetQuestDifficultyColor, level)
        if ok then
            local r, g, b = Number(Field(color, "r")), Number(Field(color, "g")),
                Number(Field(color, "b"))
            if r and g and b then return r, g, b end
        end
    end
    return .83, .87, .88
end

local function Objective(questID)
    local data = addon.VignetteRadarQuestData
    local summary = data and data.GetObjectiveSummary and data.GetObjectiveSummary(questID)
    if summary then
        local label, count = Word(summary.label), Word(summary.count)
        if label then return label, count end
    end
    local exploration = addon.VignetteRadarExploration
    local progress = exploration and exploration.ObjectiveProgress
        and exploration.ObjectiveProgress(questID)
    return nil, Word(progress) and progress:match("^%d+/%d+") or nil
end

-- The quest log supplies the player's own headers; the map APIs decide which
-- quests are local. A header is emitted only when it has a visible child.
-- One quest row in the tracker's entry format.
local function QuestEntry(id, title, level, header)
    local objective, progress = Objective(id)
    return { kind = "quest", questID = id, title = title, header = header,
        colorSlot = QuestSlot(id), level = level,
        watched = Call(C_QuestLog, "GetQuestWatchType", id) ~= nil,
        complete = Call(C_QuestLog, "IsComplete", id) == true,
        objective = objective, progress = progress }
end

-- GlanceQuest's ordering: Focused, then Watched (up to MAX_HERE_WATCHED),
-- then Here (in the quest's area: log quests in log order, then bonus
-- objectives and world quests by ID). Each quest appears once.
function HereEntries(taskKinds, data)
    local quests = addon.Quests
    local titles, levels, order = {}, {}, {}
    for _, info in ipairs(quests.Log()) do
        if not info.isHeader and info.questID then
            titles[info.questID], levels[info.questID] = info.title, info.level
            order[#order + 1] = info.questID
        end
    end
    local result, present = {}, {}
    local function Group(title, ids)
        local group
        for _, id in ipairs(ids) do
            if id and not present[id] then
                local name = Word(titles[id]) or Word(Call(C_QuestLog, "GetTitleForQuestID", id))
                if name then
                    if not group then
                        group = { kind = "header", title = title, count = 0 }
                        result[#result + 1] = group
                    end
                    present[id] = true
                    group.count = group.count + 1
                    result[#result + 1] = QuestEntry(id, name, levels[id]
                        or Number(Call(C_QuestLog, "GetQuestDifficultyLevel", id)), title)
                end
            end
        end
    end
    local focus = addon.VignetteRadarFocus
    local focused = focus and focus.GetQuest and focus.GetQuest()
    if not focused then focused = Number(Call(C_SuperTrack, "GetSuperTrackedQuestID")) end
    Group("Focused", { focused and focused > 0 and focused or nil })
    local watchedIDs = {}
    for _, world in ipairs({ false, true }) do
        for _, id in ipairs(quests.WatchedIDs(world)) do
            if #watchedIDs < MAX_HERE_WATCHED then watchedIDs[#watchedIDs + 1] = id end
        end
    end
    Group("Watched", watchedIDs)
    local here = {}
    for _, id in ipairs(order) do
        if data.IsQuestInArea(id) then here[#here + 1] = id end
    end
    local tasks = {}
    for id in pairs(taskKinds) do
        if not titles[id] and data.IsQuestInArea(id) then tasks[#tasks + 1] = id end
    end
    table.sort(tasks)
    for _, id in ipairs(tasks) do here[#here + 1] = id end
    Group("Here", here)
    return result
end

function API.BuildEntries(mapID, scope)
    if scope ~= "watched" and scope ~= "all" then scope = "local" end
    local localIDs, watched, taskKinds = {}, {}, {}
    local radar = addon.VignetteRadarAPI
    local radarQuests = radar and radar.GetQuests and radar.GetQuests() or {}
    for _, quest in ipairs(radarQuests) do
        local id = Number(quest.questID)
        if id and quest.mapID == mapID then localIDs[id] = true end
    end
    -- Data/QuestService.lua shares these reads with the radar in one frame.
    local quests = addon.Quests
    if Number(mapID) then
        local onMap = quests.OnMap(mapID)
        for _, record in ipairs(onMap.quests) do
            if record.questID then localIDs[record.questID] = true end
        end
        for _, record in ipairs(onMap.tasks) do
            local id = record.questID
            if id then
                localIDs[id] = true
                taskKinds[id] = (record.isWorldQuest
                    or Call(C_QuestLog, "IsWorldQuest", id) == true) and "World Quests"
                    or "Bonus Objectives"
            end
        end
    end
    for _, world in ipairs({ false, true }) do
        for _, id in ipairs(quests.WatchedIDs(world)) do
            watched[id] = true
            if Number(mapID) then
                local x, y = Call(C_QuestLog, "GetNextWaypointForMap", id, mapID)
                if Number(x) and Number(y) then localIDs[id] = true end
            end
        end
    end

    -- "Quests Here Only" builds GlanceQuest's list: the focused quest, then
    -- watched quests in watch order, then quests whose area the player
    -- stands in, in quest-log order. No whole-map fallback.
    areaFiltered = false
    local data = addon.VignetteRadarQuestData
    if scope == "local" and Settings().vignetteRadarAreaQuests == true and data and data.IsQuestInArea then
        areaFiltered = true
        return HereEntries(taskKinds, data)
    end

    local result, groups, present = {}, {}, {}
    local function AddQuest(id, title, level, header, kind)
        if not id or present[id] then return end
        if scope == "local" and not localIDs[id] then return end
        if scope == "watched" and not watched[id] then return end
        title = Word(title) or Word(Call(C_QuestLog, "GetTitleForQuestID", id))
        if not title then return end
        present[id] = true
        header = kind or Word(header) or "Quests"
        local group = groups[header]
        if not group then
            group = { kind = "header", title = header, count = 0 }
            groups[header] = group
            result[#result + 1] = group
        end
        group.count = group.count + 1
        local objective, progress = Objective(id)
        result[#result + 1] = { kind = "quest", questID = id, title = title,
            header = header, colorSlot = QuestSlot(id), level = level,
            watched = watched[id] == true, complete = Call(C_QuestLog, "IsComplete", id) == true,
            objective = objective, progress = progress }
    end

    local header = "Quests"
    for _, info in ipairs(quests.Log()) do
        if info.isHeader then
            header = Word(info.title) or header
        else
            local id = info.questID
            local kind = taskKinds[id]
            if id and Call(C_QuestLog, "IsWorldQuest", id) == true then
                kind = "World Quests"
            end
            AddQuest(id, info.title, info.level, header, kind)
        end
    end
    -- World quests and bonus objectives need not have a quest-log row.
    for _, kind in ipairs(TASK_KINDS) do
        local ids = {}
        for id, taskKind in pairs(taskKinds) do
            if taskKind == kind and not present[id] then ids[#ids + 1] = id end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            AddQuest(id, nil, Number(Call(C_QuestLog, "GetQuestDifficultyLevel", id)),
                kind, kind)
        end
    end
    return result
end

local function Label(parent, size, value)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size, "")
    label:SetText(value or "")
    label:SetWordWrap(false)
    return label
end

local function Button(parent, value, width)
    local controls = addon.VignetteRadarControls
    return controls.Button(parent, value, width, 22)
end

local function Select(button, selected)
    if selected then
        if button.LockHighlight then button:LockHighlight() end
    elseif button.UnlockHighlight then button:UnlockHighlight() end
end

-- The floating spot lives in the shared panel layout (UI/Tray.lua,
-- vignetteRadarPanelLayout.questTracker), in UIParent units.
local function SavePosition()
    local tray = addon.VignetteRadarTray
    if frame and tray and tray.SavePanelSpot then tray.SavePanelSpot(frame) end
end

-- The radar's visible face (the rounded square on its field) and the outer
-- panel. The tray is sized from the face, not the larger panel frame.
local function RadarAnchor()
    local radar = addon.VignetteRadarAPI
    local root = radar and radar.GetPanel and radar.GetPanel()
    local field = root and root.field
    return field and field.background or field or root, root
end

-- The rows' width: the panel less its padding and, in the round view, less
-- the part tucked under the radar face.
local function RowWidth()
    return (Number(frame:GetWidth()) or WIDTH) - 2 * SIDE - (frame._roundInset or 0)
end

-- Fits the rows' text to the panel width after a resize.
local function LayoutWidth()
    local width = frame and frame:GetWidth()
    if not Number(width) then return end
    -- The round view sizes each row to its own share of the curve.
    if frame._roundInset then return end
    local inner = RowWidth()
    if frame._layoutWidth == inner then return end
    frame._layoutWidth = inner
    for _, row in ipairs(frame.rows) do
        row:SetWidth(inner)
        row.header:SetWidth(inner - 21)
        row.name:SetWidth(inner - 24)
        row.progress:SetWidth(inner - 24)
    end
end

local function SaveSize()
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not (Number(width) and Number(height)) then return end
    local db = Settings()
    db.vignetteRadarQuestTrackerSize = {
        width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, math.floor(width + .5))),
        height = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(height + .5))),
    }
end

local function SetBodyInteractive(on)
    if not frame or frame._bodyInteractive == on then return end
    frame._bodyInteractive = on
    frame:EnableMouse(on)
    frame.options:EnableMouse(on)
    frame.lock:EnableMouse(on)
    frame.detach:EnableMouse(on)
    frame.close:EnableMouse(on)
    frame.moveLock:EnableMouse(on)
    frame.drag:EnableMouse(on)
    for _, row in ipairs(frame.rows) do row:EnableMouse(on) end
end

-- Hides the surface edge that meets the radar, so tray and radar read as one.
local function JoinSide(side)
    frame.actualSide = side
end

local function TrayOptions()
    if trayOptions then return trayOptions end
    trayOptions = {
        frame = frame,
        label = "Quest Tracker",
        side = function() return Settings().vignetteRadarQuestTrackerSide or "right" end,
        isOpen = function() return Settings().vignetteRadarQuestTrackerRetracted ~= true end,
        setOpen = function(open)
            Settings().vignetteRadarQuestTrackerRetracted = not open
            local _, root = RadarAnchor()
            if root and root.RefreshCornerTools then root.RefreshCornerTools() end
        end,
        setInteractive = SetBodyInteractive,
        onSide = JoinSide,
        -- Beside the radar only the part outside the face needs room.
        sideWidth = function() return (frame._fitWidth or WIDTH) - (frame._roundInset or 0) end,
        inset = function() return frame._roundInset or 0 end,
        onReplaced = function()
            frame._trayBusy = true
            frame:Hide()
        end,
        keepOpen = function() return menu and menu:IsShown() and MouseIsOver(menu) end,
    }
    return trayOptions
end

local function Place()
    if not frame then return end
    local tray = addon.VignetteRadarTray
    -- Safety net (once per session): a floating spot off screen or invalid
    -- re-docks the tracker in the tray.
    if tray and tray.CheckPanelSpot then tray.CheckPanelSpot(frame) end
    local db = Settings()
    local dock = db.vignetteRadarQuestTrackerView == "tray" and tray ~= nil
    if dock then
        local fit = frame._fitWidth or WIDTH
        local function Across()
            -- Above or below the radar the tracker is as wide as the face
            -- (never under its minimum), so it sits flush instead of overhanging.
            local side = tray.Side and tray.Side()
            local across = (side == "top" or side == "bottom") and tray.AcrossWidth and tray.AcrossWidth()
            return across and math.max(MIN_WIDTH, math.floor(across + .5)) or fit
        end
        fit = Across()
        if frame:GetWidth() ~= fit then frame:SetWidth(fit) end
        local reason
        dock, reason = tray.Attach(TrayOptions())
        if dock and frame:GetWidth() ~= Across() then
            -- The side was just chosen: size to it and dock once more.
            frame:SetWidth(Across())
            dock, reason = tray.Attach(TrayOptions())
        end
        if reason == "busy" then
            if addon.Trace then addon.Trace.Log("panel", "quest tracker waits: another panel holds the tray") end
            -- Another panel (the legend) holds the tray: wait hidden until
            -- the tracker's own toggle swaps it back in.
            frame._trayBusy = true
            frame:Hide()
            return
        end
        frame._trayBusy = nil
        if not dock then tray.Detach(frame) end
    elseif tray then
        frame._trayBusy = nil
        tray.Detach(frame)
    end
    if not dock then
        if frame._placementKey ~= "floating" then
            frame._placementKey = "floating"
            if addon.Trace then
                addon.Trace.Log("panel", "quest tracker floats (view %s, radar dock %s)",
                    db.vignetteRadarQuestTrackerView, tray and tray.CanDock and tray.CanDock() and "up" or "down")
            end
            frame:SetScale(1)
            if not (tray and tray.IsPanel and tray.IsPanel(frame)) then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 290, -160)
            end
            frame:SetFrameStrata("MEDIUM")
            SetBodyInteractive(true)
            local size = db.vignetteRadarQuestTrackerSize
            frame:SetWidth(type(size) == "table" and Number(size.width) or WIDTH)
        end
        -- The shared free placement (UI/Tray.lua): the saved spot, kept on
        -- screen; it re-anchors only when the spot changed.
        if tray and tray.IsPanel and tray.IsPanel(frame) then tray.PlaceFreePanel(frame) end
    else
        frame._placementKey = nil
    end
    JoinSide(dock and tray.Side() or nil)
    if frame._clamped ~= (not dock) then
        frame._clamped = not dock
        frame:SetClampedToScreen(not dock)
    end
    frame.close:SetShown(not dock)
    frame.lock:SetShown(dock)
    -- Floating, the shared panel lock (UI/Tray.lua) pins it: no drag, no resize.
    local pinned = tray ~= nil and tray.IsPanelLocked and tray.IsPanelLocked("questTracker")
    frame.moveLock:SetShown(not dock)
    frame.grip:SetShown(not dock and not pinned)
    if frame.detach.RefreshDetach then frame.detach:RefreshDetach() end
    LayoutWidth()
end

-- The width the docked tray needs: its widest line plus row padding,
-- between MIN_TRAY_WIDTH and the full WIDTH.
local function TextWidth(label)
    if not (label and label.IsShown and label:IsShown()) then return 0 end
    local measure = label.GetUnboundedStringWidth or label.GetStringWidth
    local width = measure and measure(label)
    return Number(width) or 0
end

local function FitWidth(shown)
    local need = TextWidth(frame.title) + 142
    for index = 1, shown or 0 do
        local row = frame.rows[index]
        if row and row:IsShown() then
            need = math.max(need, TextWidth(row.header) + 45,
                TextWidth(row.name) + 52, TextWidth(row.progress) + 52)
        end
    end
    return math.max(MIN_TRAY_WIDTH, math.min(WIDTH, math.ceil(need)))
end

-- Round view ------------------------------------------------------------------
-- Docked left or right of a round radar (unless vignetteRadarQuestTrackerRound
-- is off), the tray curves around the circle. It tucks `inset` under the
-- face, and each header line and row moves so its text starts a few pixels
-- past the circle's edge at that height (Tray.ArcGap). The rows share one
-- width, wide enough for their longest text, so nothing is ever cut.
-- Header pieces: key, anchor x, anchor y, and the content rows they cover.
local HEADER_TEXT = { { "title", SIDE + 2, -8, 6, 22 }, { "count", SIDE + 2, -25, 25, 37 } }
local HEADER_ICONS = { { "options", -58 }, { "detach", -34 }, { "lock", -10 }, { "close", -10 },
    { "moveLock", -82 } }

local function RoundSide()
    local db = Settings()
    if db.vignetteRadarQuestTrackerRound == false or db.vignetteRadarQuestTrackerView ~= "tray" then
        return nil
    end
    local tray = addon.VignetteRadarTray
    if not (tray and tray.ArcGap and tray.FaceIsRound and tray.IsAttached(frame) and tray.FaceIsRound()) then
        return nil
    end
    local side = tray.Side()
    if side == "left" or side == "right" then return side end
    return nil
end

-- Moves the header pieces, empty note and footer by their own shifts
-- (left: added to x; right: pulled in from the right edge).
local function PlaceHeader(shift)
    local key = table.concat({ shift.title[1], shift.count[1], shift.rule[1], shift.rule[2], shift.icons[2],
        shift.drag[1], shift.drag[2], shift.empty[1], shift.footer[1] }, ",")
    if frame._headerKey == key then return end
    frame._headerKey = key
    for _, spec in ipairs(HEADER_TEXT) do
        local label = frame[spec[1]]
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", spec[2] + shift[spec[1]][1], spec[3])
    end
    frame.rule:ClearAllPoints()
    frame.rule:SetPoint("TOPLEFT", SIDE + shift.rule[1], -40)
    frame.rule:SetPoint("TOPRIGHT", -SIDE - shift.rule[2], -40)
    for _, spec in ipairs(HEADER_ICONS) do
        local icon = frame[spec[1]]
        icon:ClearAllPoints()
        icon:SetPoint("TOPRIGHT", spec[2] - shift.icons[2], -9)
    end
    frame.drag:ClearAllPoints()
    frame.drag:SetPoint("TOPLEFT", 8 + shift.drag[1], -5)
    frame.drag:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -124 - shift.drag[2], -37)
    frame.empty:ClearAllPoints()
    frame.empty:SetPoint("TOPLEFT", 21 + shift.empty[1], -HEADER_HEIGHT - 7)
    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("BOTTOMLEFT", SIDE + 2 + shift.footer[1], 5)
end

-- Lays the tracker out around a round radar, or straight again. Sets
-- frame._roundInset and, while round, frame._fitWidth.
local function ApplyRound(shown)
    local side = RoundSide()
    local tray = addon.VignetteRadarTray
    frame._roundSide = side
    local gaps, deepest = {}, 0
    local function Take(key, top, bottom)
        local gap = side and tray.ArcGap(top, bottom) or 0
        gaps[key] = gap
        if gap > deepest then deepest = gap end
    end
    for _, spec in ipairs(HEADER_TEXT) do Take(spec[1], spec[4], spec[5]) end
    Take("rule", 39, 42)
    Take("icons", 9, 29)
    Take("drag", 5, 37)
    local rowTop = HEADER_HEIGHT
    for index = 1, shown do
        local entry = frame.rows[index].entry
        local height = entry and entry.kind == "header" and HEADER_ROW_HEIGHT or QUEST_ROW_HEIGHT
        Take(index, rowTop, rowTop + height)
        rowTop = rowTop + height
    end
    local height = Number(frame:GetHeight()) or rowTop
    Take("empty", HEADER_HEIGHT + 7, HEADER_HEIGHT + 21)
    Take("footer", height - FOOTER_HEIGHT, height)
    local inset = side and math.ceil(deepest) or 0
    -- Right of the radar the face is on the left: pieces move right by what
    -- the circle leaves free there. Left of it, they stay hard against the
    -- outer (left) edge and only keep their right ends clear of the circle.
    local function Shift(key)
        local gap = gaps[key] or 0
        if side == "right" then return { math.ceil(inset - gap), 0 } end
        if side == "left" then return { 0, math.ceil(inset - gap) } end
        return { 0, 0 }
    end
    -- What one piece gives up to the circle, whichever side it is on.
    local function Reserve(key)
        local pair = Shift(key)
        return pair[1] + pair[2]
    end
    local shift = {}
    for _, key in ipairs({ "title", "count", "rule", "icons", "drag", "empty", "footer" }) do
        shift[key] = Shift(key)
    end
    PlaceHeader(shift)
    frame._roundInset = side and inset or nil
    if not side then
        if addon.Trace and frame._roundTraced then
            frame._roundTraced = nil
            addon.Trace.Log("panel", "quest tracker round view off")
        end
        return
    end
    -- The narrowest panel that holds every line in full (+3 so the client
    -- never adds "..."). Each line only gives up its own share to the
    -- circle, so lines beside its curve may run wider than the middle ones.
    local fit = math.max(MIN_TRAY_WIDTH,
        TextWidth(frame.title) + 145 + shift.title[1] + shift.icons[2],
        TextWidth(frame.count) + 101 + shift.count[1] + shift.icons[2])
    local function Need(row)
        if row.entry and row.entry.kind == "header" then return TextWidth(row.header) + 2 * SIDE end
        if row.entry then return math.max(TextWidth(row.name), TextWidth(row.progress)) + 31 end
        return 0
    end
    for index = 1, shown do
        fit = math.max(fit, Need(frame.rows[index]) + 2 * SIDE + Reserve(index))
    end
    fit = math.min(MAX_WIDTH + inset, math.ceil(fit))
    frame._fitWidth = fit
    rowTop = HEADER_HEIGHT
    for index = 1, shown do
        local row = frame.rows[index]
        local rowHeight = row.entry and row.entry.kind == "header" and HEADER_ROW_HEIGHT or QUEST_ROW_HEIGHT
        local width = fit - 2 * SIDE - Reserve(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + Shift(index)[1], -rowTop)
        row:SetWidth(width)
        row.header:SetWidth(width - 21)
        row.name:SetWidth(width - 24)
        row.progress:SetWidth(width - 24)
        rowTop = rowTop + rowHeight
    end
    local rows = fit - 2 * SIDE - inset
    -- Straight again later, every row needs the shared width back.
    frame._layoutWidth = nil
    if addon.Trace and frame._roundTraced ~= side .. inset .. "," .. rows then
        frame._roundTraced = side .. inset .. "," .. rows
        addon.Trace.Log("panel", "quest tracker round view %s: inset %s, rows %s wide", side, inset, rows)
    end
end

local function Draw()
    if not frame then return end
    local controls = addon.VignetteRadarControls
    if controls then
        controls.RefreshRoundedStatusSurface(frame)
    end
    -- Docked or detached, the tracker keeps the radar's darker surface.
    -- Docked, the tray's own refresh skins its owner (this frame) once.
    local tray = addon.VignetteRadarTray
    if tray then
        if tray.IsAttached(frame) then tray.RefreshTheme() else tray.SkinLikeRadar(frame) end
    end
    local style = addon.VignetteRadarStyle
    local ar, ag, ab = .05, .82, .62
    if style then ar, ag, ab = style.Color("accent") end
    frame.title:SetTextColor(ar, ag, ab, 1)
    frame.rule:SetColorTexture(ar, ag, ab, .2)
    local count = 0
    for _, entry in ipairs(entries) do if entry.kind == "quest" then count = count + 1 end end
    local scope = Settings().vignetteRadarQuestTrackerScope
    local scopeName = scope == "watched" and "WATCHED" or scope == "all" and "ALL"
        or areaFiltered and "HERE" or "LOCAL"
    frame.count:SetText(scopeName .. "  ·  " .. count .. " QUEST" .. (count == 1 and "" or "S"))
    local collapsed = Settings().vignetteRadarQuestTrackerCollapsed
    local visible = frame.visibleEntries or {}
    for index = #visible, 1, -1 do visible[index] = nil end
    local hiddenHeader
    for _, entry in ipairs(entries) do
        if entry.kind == "header" then
            hiddenHeader = collapsed[entry.title] == true
            visible[#visible + 1] = entry
        elseif not hiddenHeader then
            visible[#visible + 1] = entry
        end
    end
    frame.visibleEntries = visible
    local anchor, root = RadarAnchor()
    local radarScale = root and root.GetEffectiveScale and root:GetEffectiveScale()
        or root and root.GetScale and root:GetScale() or 1
    local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    radarScale = Number(radarScale) and Number(parentScale) and parentScale > 0
        and radarScale / parentScale or 1
    local trayHeight = Settings().vignetteRadarQuestTrackerView == "tray"
        and root and root.IsShown and root:IsShown() and anchor
        and Number(anchor:GetHeight()) and math.max(110, anchor:GetHeight() * radarScale - 20)
    if not trayHeight and Settings().vignetteRadarQuestTrackerView ~= "tray" then
        local size = Settings().vignetteRadarQuestTrackerSize
        trayHeight = type(size) == "table" and Number(size.height) or nil
    end
    offset = math.max(0, math.min(offset, math.max(0, #visible - 1)))
    local capacity = VISIBLE_ROWS
    if trayHeight then
        capacity = 0
        local room, used = trayHeight - HEADER_HEIGHT - FOOTER_HEIGHT - 7, 0
        for index = offset + 1, math.min(#visible, offset + MAX_ROWS) do
            local height = visible[index].kind == "header" and HEADER_ROW_HEIGHT
                or QUEST_ROW_HEIGHT
            if capacity > 0 and used + height > room then break end
            used, capacity = used + height, capacity + 1
        end
        capacity = math.max(1, capacity)
    end
    offset = math.max(0, math.min(offset, math.max(0, #visible - capacity)))
    frame.capacity = capacity
    local shown = math.min(#visible - offset, capacity)
    local contentHeight = 0
    for index = 1, shown do
        local entry = visible[offset + index]
        contentHeight = contentHeight + (entry.kind == "header" and HEADER_ROW_HEIGHT
            or QUEST_ROW_HEIGHT)
    end
    local overflow = #visible > capacity
    frame:SetHeight(trayHeight or (HEADER_HEIGHT + math.max(24, contentHeight)
        + (overflow and FOOTER_HEIGHT or 8)))
    frame.empty:SetShown(#visible == 0)
    frame.empty:SetText(scope == "local" and "No Local Quests On This Map"
        or scope == "watched" and "No Watched Quests" or "No Quests In Your Log")
    frame.footer:SetShown(overflow)
    frame.footer:SetText(overflow and ((offset + 1) .. "–"
        .. math.min(#visible, offset + capacity) .. " Of " .. #visible .. " · Scroll") or "")
    local rowY = -HEADER_HEIGHT
    for index, row in ipairs(frame.rows) do
        local entry = index <= capacity and visible[offset + index] or nil
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local isHeader = entry.kind == "header"
            local height = isHeader and HEADER_ROW_HEIGHT or QUEST_ROW_HEIGHT
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, rowY)
            row:SetSize(RowWidth(), height)
            rowY = rowY - height
            row.header:SetShown(isHeader)
            row.quest:SetShown(not isHeader)
            if isHeader then
                row.header:SetText((collapsed[entry.title] and "+ " or "− ")
                    .. entry.title .. "  " .. entry.count)
                row.header:SetTextColor(ar, ag, ab, 1)
                row.hover:SetColorTexture(ar, ag, ab, .08)
            else
                local r, g, b = QuestColor(entry.colorSlot)
                row.diamond:SetTexture(entry.complete and DIAMOND or HOLLOW)
                row.diamond:SetVertexColor(r, g, b, 1)
                row.slot:SetText(tostring(entry.colorSlot))
                row.slot:SetTextColor(1, 1, 1, 1)
                row.center:SetVertexColor(r * .18, g * .18, b * .18, .96)
                row.center:SetShown(not entry.complete)
                local dr, dg, db = DifficultyColor(entry.level)
                row.name:SetText(entry.title)
                row.name:SetTextColor(dr, dg, db, 1)
                row.progress:SetText(entry.complete and "Ready To Turn In"
                    or entry.objective and (entry.progress and entry.progress .. "  " or "")
                        .. entry.objective or entry.progress or "Click To Focus")
                row.progress:SetTextColor(entry.complete and .48 or .66,
                    entry.complete and .9 or .77, entry.complete and .65 or .77, 1)
                local exploration = addon.VignetteRadarExploration
                local focused = exploration and exploration.GetFocusedQuest
                    and exploration.GetFocusedQuest() == entry.questID
                row.focus:SetColorTexture(r, g, b, focused and .84 or 0)
                row.hover:SetColorTexture(r, g, b, .08)
            end
        end
    end
    lastThemeRevision = style and style.revision or 0
    -- Docked, the tray slides out only as far as its widest line needs.
    frame._fitWidth = FitWidth(shown)
    ApplyRound(shown)
    Place()
    -- Docking just found (or left) a round radar's side: lay out once more.
    if RoundSide() ~= frame._roundSide then
        ApplyRound(shown)
        Place()
    end
    if menu and menu:IsShown() and RefreshMenu then RefreshMenu() end
end

local function EnsureMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", "VignetteRadarQuestTrackerOptions", UIParent)
    menu:SetSize(224, 341)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    addon.VignetteRadarControls.RoundedStatusSurface(menu)
    menu.choices = {}
    local function Heading(text, y)
        local label = Label(menu, 9, text)
        label:SetPoint("TOPLEFT", 12, y)
        label:SetTextColor(.60, .77, .79, 1)
    end
    local function Choice(text, x, y, width, key, value, action)
        local button = Button(menu, text, width)
        button:SetPoint("TOPLEFT", x, y)
        button:SetScript("OnClick", function()
            if action then
                action()
            else
                local db = Settings()
                if key == "vignetteRadarQuestTrackerView" and value == "tray"
                    and db[key] == "floating" then
                    SavePosition()
                    db.vignetteRadarQuestTrackerRetracted = false
                end
                db[key] = value
                if key == "vignetteRadarQuestDots" and addon.RefreshVignetteRadar then
                    addon.RefreshVignetteRadar(true)
                elseif key == "vignetteRadarQuestNumbers" and addon.RefreshVignetteRadar then
                    addon.RefreshVignetteRadar(false)
                end
                offset = 0
                API.Refresh()
            end
            RefreshMenu()
        end)
        menu.choices[#menu.choices + 1] = { button = button, key = key, value = value }
        return button
    end
    Heading("Tracker View", -10)
    Choice("Floating", 12, -27, 97, "vignetteRadarQuestTrackerView", "floating")
    Choice("Tray", 115, -27, 97, "vignetteRadarQuestTrackerView", "tray")
    Heading("Tray Side", -57)
    for index, spec in ipairs({ { "Left", "left" }, { "Right", "right" },
        { "Top", "top" }, { "Bottom", "bottom" } }) do
        Choice(spec[1], 12 + (index - 1) * 51, -74, 46,
            "vignetteRadarQuestTrackerSide", spec[2])
    end
    Heading("Quest Scope", -104)
    for index, spec in ipairs({ { "Local", "local" }, { "Watched", "watched" },
        { "All", "all" } }) do
        Choice(spec[1], 12 + (index - 1) * 69, -121, 64,
            "vignetteRadarQuestTrackerScope", spec[2])
    end
    Heading("Radar Quest Diamonds", -151)
    Choice("Off", 12, -168, 97, "vignetteRadarQuestDots", false)
    Choice("On", 115, -168, 97, "vignetteRadarQuestDots", true)
    Heading("Quest Number Labels", -198)
    Choice("Off", 12, -215, 97, "vignetteRadarQuestNumbers", false)
    Choice("On", 115, -215, 97, "vignetteRadarQuestNumbers", true)
    Heading("Visible Headers", -245)
    local function Fold(value)
        local saved = Settings().vignetteRadarQuestTrackerCollapsed
        for _, entry in ipairs(entries) do
            if entry.kind == "header" then saved[entry.title] = value or nil end
        end
        offset = 0
        Draw()
    end
    Choice("Fold All", 12, -262, 97, nil, nil, function() Fold(true) end)
    Choice("Expand All", 115, -262, 97, nil, nil, function() Fold(false) end)
    Heading("Tray Handle", -292)
    for index, spec in ipairs({ { "Lip", "lip" }, { "Groove", "groove" }, { "Icon", "icon" } }) do
        Choice(spec[1], 12 + (index - 1) * 69, -309, 64, "vignetteRadarTrayHandle", spec[2])
    end
    menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver()
            and not (frame and frame.options and frame.options:IsMouseOver()) then
            self:Hide()
        end
    end)
    -- The Options icon shows its active state while the menu is open.
    menu:SetScript("OnHide", function()
        if frame and frame.options and frame.options.Refresh then frame.options:Refresh() end
    end)
    menu:Hide()
    return menu
end

RefreshMenu = function()
    if not menu then return end
    addon.VignetteRadarControls.RefreshRoundedStatusSurface(menu)
    for _, choice in ipairs(menu.choices) do
        if choice.key then Select(choice.button, Settings()[choice.key] == choice.value) end
    end
end

local function EnsureFrame()
    if frame or type(CreateFrame) ~= "function" or not UIParent then return frame end
    frame = CreateFrame("Frame", "VignetteRadarQuestTrackerPanel", UIParent)
    frame:SetSize(WIDTH, HEADER_HEIGHT + QUEST_ROW_HEIGHT + 8)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    addon.VignetteRadarControls.RoundedStatusSurface(frame)
    -- Place() puts it at its saved spot (UI/Tray.lua) or in the tray.
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 290, -160)
    frame.title = Label(frame, 12, "QUEST TRACKER")
    frame.title:SetPoint("TOPLEFT", SIDE + 2, -8)
    frame.title:SetWidth(120)
    frame.title:SetJustifyH("LEFT")
    frame.count = Label(frame, 9, "0 QUESTS")
    frame.count:SetPoint("TOPLEFT", SIDE + 2, -25)
    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetPoint("TOPLEFT", SIDE, -40)
    frame.rule:SetPoint("TOPRIGHT", -SIDE, -40)
    frame.rule:SetHeight(1)
    local icons = addon.VignetteRadarIconButton
    frame.options = icons.Create(frame, "options", { size = 20, label = "Tracker Options",
        tooltip = "Choose the view, tray side, quest scope, and radar labels.",
        isActive = function() return menu ~= nil and menu:IsShown() end })
    frame.options:SetPoint("TOPRIGHT", -58, -9)
    frame.options:SetScript("OnClick", function()
        local dropdown = EnsureMenu()
        dropdown:ClearAllPoints()
        if Number(frame:GetBottom()) and frame:GetBottom() < dropdown:GetHeight() + 8 then
            dropdown:SetPoint("BOTTOMRIGHT", frame.options, "TOPRIGHT", 0, 3)
        else
            dropdown:SetPoint("TOPRIGHT", frame.options, "BOTTOMRIGHT", 0, -3)
        end
        RefreshMenu()
        dropdown:SetShown(not dropdown:IsShown())
        frame.options:Refresh()
    end)
    frame.close = icons.Create(frame, "close", { size = 20, label = "Close Tracker",
        onClick = function() API.Hide() end })
    frame.close:SetPoint("TOPRIGHT", -10, -9)
    local tray = addon.VignetteRadarTray
    frame.lock = tray and tray.CreateLockButton(frame) or CreateFrame("Button", nil, frame)
    frame.lock:SetPoint("TOPRIGHT", -10, -9)
    frame.lock:Hide()
    frame.detach = tray and tray.CreateDetachButton(frame,
        function() return Settings().vignetteRadarQuestTrackerView ~= "tray" end,
        function()
            if Settings().vignetteRadarQuestTrackerView == "tray" then API.Detach() else API.Dock() end
        end) or CreateFrame("Button", nil, frame)
    frame.detach:SetPoint("TOPRIGHT", -34, -9)
    -- Floating, this lock stops the tracker moving or resizing; the same
    -- per-panel lock the panels near the radar use.
    frame.moveLock = tray and tray.IsPanelLocked and tray.CreateLockButton(frame, {
        labels = { "Position Unlocked", "Position Locked" },
        tips = { "Drag the header to move it. Lock to stop it moving.", "Unlock to move or resize it again." },
        isLocked = function() return tray.IsPanelLocked("questTracker") end,
        setLocked = function(value)
            tray.SetPanelLocked("questTracker", value)
            frame.grip:SetShown(not value and Settings().vignetteRadarQuestTrackerView ~= "tray")
        end }) or CreateFrame("Button", nil, frame)
    frame.moveLock:SetPoint("TOPRIGHT", -82, -9)
    frame.moveLock:Hide()
    -- Detached, the tracker resizes from this corner grip.
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT) end
    frame.grip = CreateFrame("Button", nil, frame)
    frame.grip:SetSize(16, 16)
    frame.grip:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    frame.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    frame.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    frame.grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    frame.grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SaveSize()
        SavePosition()
        Draw()
    end)
    frame.grip:Hide()
    frame:SetScript("OnSizeChanged", function() LayoutWidth() end)
    frame.drag = CreateFrame("Button", nil, frame)
    frame.drag:SetPoint("TOPLEFT", 8, -5)
    frame.drag:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -124, -37)
    -- Dragging (the header, floating only) is the shared panel drag that
    -- Tray.RegisterPanel wires up at the end of EnsureFrame.
    frame.drag:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Quest Tracker", 1, .87, .66)
        GameTooltip:AddLine("Diamond: Radar Color · Title: Difficulty Color", .66, .8, .78)
        GameTooltip:Show()
    end)
    frame.drag:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetPoint("TOPLEFT", SIDE, -HEADER_HEIGHT)
        row:SetSize(WIDTH - 2 * SIDE, QUEST_ROW_HEIGHT)
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetAllPoints(row)
        row.hover:SetTexture(WHITE)
        row.hover:Hide()
        row.header = Label(row, 10)
        row.header:SetPoint("TOPLEFT", 7, -2)
        row.header:SetWidth(WIDTH - 45)
        row.header:SetJustifyH("LEFT")
        row.quest = CreateFrame("Frame", nil, row)
        row.quest:SetAllPoints(row)
        row.diamond = row.quest:CreateTexture(nil, "ARTWORK")
        row.diamond:SetSize(14, 14)
        row.diamond:SetPoint("TOPLEFT", 6, -7)
        row.center = row.quest:CreateTexture(nil, "ARTWORK")
        row.center:SetTexture(DIAMOND)
        row.center:SetSize(9, 9)
        row.center:SetPoint("CENTER", row.diamond, "CENTER")
        row.slot = Label(row.quest, 9)
        addon.VignetteRadarStyle.SetFont(row.slot, 9, "OUTLINE")
        -- Sized to the glyph and centred on the diamond, like the radar's
        -- quest numbers; a fixed box and nudge only suited the old font.
        row.slot:SetPoint("CENTER", row.diamond, "CENTER", 0, 0)
        row.slot:SetJustifyH("CENTER")
        row.name = Label(row.quest, 10)
        row.name:SetPoint("TOPLEFT", 28, -2)
        row.name:SetWidth(WIDTH - 48)
        row.name:SetJustifyH("LEFT")
        row.progress = Label(row.quest, 9)
        row.progress:SetPoint("TOPLEFT", 28, -17)
        row.progress:SetWidth(WIDTH - 48)
        row.progress:SetJustifyH("LEFT")
        row.focus = row.quest:CreateTexture(nil, "ARTWORK")
        row.focus:SetPoint("TOPLEFT", 25, -2)
        row.focus:SetSize(2, 27)
        row:SetScript("OnEnter", function(self)
            self.hover:Show()
            local radar = addon.VignetteRadarAPI
            if self.entry and self.entry.kind == "quest" and radar and radar.HighlightQuest then
                radar.HighlightQuest(self.entry.questID)
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            local radar = addon.VignetteRadarAPI
            if radar and radar.HighlightQuest then radar.HighlightQuest(nil) end
        end)
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if not entry then return end
            if entry.kind == "header" then
                local saved = Settings().vignetteRadarQuestTrackerCollapsed
                saved[entry.title] = not saved[entry.title] or nil
                Draw()
            else
                local exploration = addon.VignetteRadarExploration
                if exploration and exploration.FocusQuest then
                    exploration.FocusQuest(entry.questID)
                    Draw()
                end
            end
        end)
        frame.rows[index] = row
    end
    frame.empty = Label(frame, 10)
    frame.empty:SetPoint("TOPLEFT", 21, -HEADER_HEIGHT - 7)
    frame.empty:SetTextColor(.67, .76, .77, 1)
    frame.footer = Label(frame, 9)
    frame.footer:SetPoint("BOTTOMLEFT", SIDE + 2, 5)
    frame.footer:SetTextColor(.60, .73, .73, 1)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local capacity = frame.capacity or VISIBLE_ROWS
        local maxOffset = math.max(0, #(frame.visibleEntries or {}) - capacity)
        offset = math.max(0, math.min(maxOffset, offset - delta))
        Draw()
    end)
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.themeElapsed = (self.themeElapsed or 0) + elapsed
        if self.themeElapsed < 1 then return end
        self.themeElapsed = 0
        local style = addon.VignetteRadarStyle
        if style and style.revision ~= lastThemeRevision then Draw() end
        -- Docked beside a visible radar, the tray follows it by itself; Place
        -- only retries docking, or floats the tracker once the radar is gone.
        local dock = addon.VignetteRadarTray
        if Settings().vignetteRadarQuestTrackerView == "tray"
            and not (dock and dock.IsAttached(self) and dock.CanDock()) then Place() end
    end)
    -- On the shared panel system (UI/Tray.lua): docked = the radar's tray,
    -- floating = a free panel with a saved spot, kept on screen, with the
    -- header's position lock. Its old spot moves into the panel layout once.
    if tray and tray.RegisterPanel then
        tray.RegisterPanel(frame, { key = "questTracker", label = "the Quest Tracker", drawer = true,
            ownControls = true, keepWidth = true, strata = "MEDIUM", home = { 290, -160 },
            legacySpot = "vignetteRadarQuestTrackerPosition", regions = { frame.drag },
            isDetached = function() return Settings().vignetteRadarQuestTrackerView ~= "tray" end,
            canDrag = function() return Settings().vignetteRadarQuestTrackerView == "floating" end,
            redock = function()
                local db = Settings()
                db.vignetteRadarQuestTrackerView = "tray"
                db.vignetteRadarQuestTrackerRetracted = false
                frame._placementKey = nil
            end,
            refresh = function() API.Refresh() end })
    end
    frame:Hide()
    return frame
end

function API.Refresh()
    local panel = EnsureFrame()
    if not panel then return end
    if Settings().vignetteRadarQuestTrackerVisible ~= true then
        if addon.VignetteRadarTray then addon.VignetteRadarTray.Detach(panel) end
        panel._placementKey = nil
        panel:Hide()
        if menu then menu:Hide() end
        return
    end
    entries = API.BuildEntries(MapID(), Settings().vignetteRadarQuestTrackerScope)
    Draw()
    if not panel._trayBusy then panel:Show() end
end

function API.Hide()
    Settings().vignetteRadarQuestTrackerVisible = false
    API.Refresh()
end

local function Docked()
    local tray = addon.VignetteRadarTray
    return tray and frame and tray.IsAttached(frame) and tray or nil
end

-- In tray view this slides the tray in or out; floating, it shows or hides.
function API.Toggle()
    local db = Settings()
    if db.vignetteRadarQuestTrackerView == "tray" then
        local tray = Docked()
        local open = not (db.vignetteRadarQuestTrackerVisible == true and tray and tray.IsOpen())
        db.vignetteRadarQuestTrackerVisible = true
        db.vignetteRadarQuestTrackerRetracted = not open
        -- Another panel holds the tray: swap the tracker back in.
        local shared = addon.VignetteRadarTray
        if open and frame and not tray and shared and shared.CanDock() then
            frame._trayBusy = nil
            shared.Show(TrayOptions())
        end
        API.Refresh()
        tray = Docked()
        if tray then tray.SetOpen(open) end
    else
        db.vignetteRadarQuestTrackerVisible = not db.vignetteRadarQuestTrackerVisible
        API.Refresh()
    end
    local _, root = RadarAnchor()
    if root and root.RefreshCornerTools then root.RefreshCornerTools() end
    return db.vignetteRadarQuestTrackerVisible
end

function API.Detach()
    if not frame then return end
    local db = Settings()
    -- It stays where it was, less the part a round view tucked under the face.
    local inset = frame._roundInset or 0
    local tray = addon.VignetteRadarTray
    if tray and tray.SavePanelSpot then
        local fit = Number(frame:GetScale()) or 1
        tray.SavePanelSpot(frame, frame._roundSide == "right" and inset * fit or 0)
    end
    SaveSize()
    local size = db.vignetteRadarQuestTrackerSize
    if inset > 0 and type(size) == "table" then size.width = math.max(MIN_WIDTH, size.width - inset) end
    db.vignetteRadarQuestTrackerView = "floating"
    db.vignetteRadarQuestTrackerVisible = true
    frame._placementKey = nil
    API.Refresh()
    local _, root = RadarAnchor()
    if root and root.RefreshCornerTools then root.RefreshCornerTools() end
end

-- Dock: back into the radar's tray, slid out (swapping out another panel).
function API.Dock()
    local db = Settings()
    if frame then SavePosition() end
    db.vignetteRadarQuestTrackerView = "tray"
    db.vignetteRadarQuestTrackerVisible = true
    db.vignetteRadarQuestTrackerRetracted = true
    API.Toggle()
end

function API.ToggleTray()
    local db = Settings()
    if db.vignetteRadarQuestTrackerView ~= "tray" then
        db.vignetteRadarQuestTrackerView = "tray"
        db.vignetteRadarQuestTrackerRetracted = false
        db.vignetteRadarQuestTrackerVisible = true
        API.Refresh()
    else
        API.Toggle()
    end
    local _, root = RadarAnchor()
    if root and root.RefreshCornerTools then root.RefreshCornerTools() end
    return API.IsExpanded()
end

function API.IsExpanded()
    if not frame or not frame:IsShown() then return false end
    local tray = Docked()
    if tray then return tray.IsOpen() end
    return Settings().vignetteRadarQuestTrackerView ~= "tray"
end

function API.IsShown() return frame and frame:IsShown() or false end
function API.SyncFocus() if frame and frame:IsShown() then Draw() end end
-- The focused row follows the shared selection, whichever view changed it.
if addon.VignetteRadarFocus then addon.VignetteRadarFocus.OnChanged(function() API.SyncFocus() end) end

-- One refresh .12 s after a burst of quest or zone events; the bus coalesces it.
-- Its quest caches are already invalid: their modules subscribe earlier.
if addon.Bus then
    local function Queued() API.Refresh() end
    for _, topic in ipairs({ "LOGIN", "QUEST_CHANGED", "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED" }) do
        addon.Bus.On(topic, Queued, { coalesce = .12 })
    end
end
