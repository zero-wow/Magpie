local _, addon = ...
if type(addon) ~= "table" then return end

-- The Intelligence panel presents evidence from optional, data-only systems.
-- It does no scanning or polling while closed; callers supply the current
-- selection and refresh it when their underlying evidence changes.
local Intelligence = {}
addon.VignetteRadarIntelligence = Intelligence

local WIDTH, HEIGHT, MAX_ROWS = 510, 388, 6
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Today is the everyday view; the three evidence tabs show only with
-- Advanced Tools on (Today replaces them for most players).
local TABS = { "Today", "Warband", "Resets", "Phase" }
local ENABLE_KEYS = {
    Warband = "vignetteRadarWarbandBoardEnabled",
    Resets = "vignetteRadarResetPlannerEnabled",
    Phase = "vignetteRadarPhaseLensEnabled",
}
local context, selection = {}, {}
local panel, currentTab = nil, "Today"
local todayPage, todayPages = 1, 1
local TODAY_FILTERS = { "left", "done", "all" }
local TODAY_FILTER_NAMES = { left = "Left", done = "Done", all = "All" }
local resetActionMessage

local Safe, Field, SecretText = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Text

local function Text(value, fallback)
    return SecretText(value, 130, true) or fallback
end

local function EvidenceLabel(value)
    local labels = {
        api = "API", bundled = "Bundled", ["trusted-pack"] = "Trusted Pack",
        manual = "Manual", observation = "Observation", none = "Unknown",
    }
    return labels[value] or "Unknown"
end

local function Settings()
    if type(addon.GetSettings) ~= "function" then return nil end
    local ok, db = pcall(addon.GetSettings)
    return ok and type(db) == "table" and db or nil
end

local function Enabled(tab)
    local db = Settings()
    return not db or db[ENABLE_KEYS[tab]] ~= false
end

local function Visible(tab)
    if tab == "Today" then return true end
    local db = Settings()
    return db ~= nil and db.vignetteRadarAdvancedTools == true
end

local function Known(tab)
    return tab == "Today" or ENABLE_KEYS[tab] ~= nil
end

local function Invoke(target, method, ...)
    if type(target) ~= "table" or type(target[method]) ~= "function" then return nil end
    local ok, result, other = pcall(target[method], target, ...)
    if ok and Safe(result) then return result, other end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok and Safe(result) then return result end
end

local function Add(view, title, detail, tone, payload)
    if #view.rows >= (view.rowLimit or MAX_ROWS) then
        view.more = (view.more or 0) + 1
        return
    end
    view.rows[#view.rows + 1] = {
        title = Text(title, "Unknown"), detail = Text(detail, "Unknown"),
        tone = tone or "muted", payload = payload,
    }
end

local function TimeAgo(now, at)
    if type(now) ~= "number" or type(at) ~= "number" or at > now then
        return "Last Seen: Unknown"
    end
    local seconds = now - at
    if seconds < 60 then return "Last Seen: Just Now" end
    if seconds < 3600 then return "Last Seen: " .. math.floor(seconds / 60) .. " Min Ago" end
    if seconds < 86400 then return "Last Seen: " .. math.floor(seconds / 3600) .. " Hr Ago" end
    return "Last Seen: " .. math.floor(seconds / 86400) .. " Days Ago"
end

local function WarbandView(view)
    local board = context.board
    if not board then
        view.summary = "No Character Snapshots Available"
        Add(view, "Unknown", "Character status is not available yet.")
        return
    end
    local now = Call(context.getNow) or (type(time) == "function" and time()) or 0
    local character = Call(context.getCurrentCharacter)
    local key = Field(selection, "goalKey")
    local db = Settings() or {}
    if type(key) == "string" and key ~= "" then
        view.summary = "Goal: " .. Text(Field(selection, "goalName"), key)
        local rows = Invoke(board, "GetBoard", key, now, character)
        if type(rows) ~= "table" or #rows == 0 then
            Add(view, "Unknown", "No character has a saved snapshot for this goal.")
            return
        end
        for _, row in ipairs(rows) do
            if db.vignetteRadarWarbandView ~= "character"
                or row.character == character then
                local eligibility = row.eligibility == "available" and "Available"
                    or row.eligibility == "unavailable" and "Unavailable" or "Unknown"
                local evidence = row.stale and "Stale Snapshot"
                    or row.offline and "Offline Snapshot" or "Current Character"
                local detail = (row.offline and "Saved " or "") .. eligibility
                    .. " | " .. evidence .. " | "
                    .. TimeAgo(now, row.lastSeenAt)
                Add(view, Text(row.name, row.character), detail,
                    eligibility == "Available" and "positive" or "muted", row)
            end
        end
        if #view.rows == 0 then
            Add(view, "Unknown", "No snapshot for the current character.")
        end
        view.footer = "Offline eligibility is a saved observation, never live proof."
        return
    end
    view.summary = "Select A Goal To Compare Characters"
    local characters = board.characters
    if type(characters) ~= "table" then
        Add(view, "Unknown", "No character snapshots available.")
        return
    end
    local list = {}
    for id, row in pairs(characters) do
        list[#list + 1] = { id = id, row = row }
        if #list >= 16 then break end
    end
    table.sort(list, function(a, b)
        return (a.row.lastSeenAt or 0) > (b.row.lastSeenAt or 0)
    end)
    for _, item in ipairs(list) do
        Add(view, Text(item.row.name, item.id),
            "Saved Snapshot | " .. TimeAgo(now, item.row.lastSeenAt))
    end
    if #view.rows == 0 then Add(view, "Unknown", "No character snapshots available.") end
    view.footer = "Select a rare, treasure, or quest to inspect goal status."
end

local function ResetView(view)
    view.rowLimit = MAX_ROWS - 1 -- Reserve the final row for explicit rule actions.
    local planner = context.resetPlanner
    local goals = planner and planner.goals
    if type(goals) ~= "table" then
        view.summary = "No Reset Goals Available"
        Add(view, "Unknown", "Reset metadata has not been supplied.")
        return
    end
    local periods = Call(context.getResetPeriods) or {}
    local db = Settings() or {}
    local category = db.vignetteRadarResetCategory or "all"
    local list = {}
    for id, record in pairs(goals) do
        if category == "all" or record.resetKind == category then
            local result = Invoke(planner, "Evaluate", id, periods)
            if type(result) == "table" then list[#list + 1] = result end
        end
        if #list >= 256 then break end
    end
    local rank = { Confirmed = 1, Expected = 2, Unknown = 3, Completed = 4 }
    local kindNames = { daily = "Daily", weekly = "Weekly",
        ["one-time"] = "One-Time", unknown = "Unknown" }
    table.sort(list, function(a, b)
        local ra, rb = rank[a.status] or 5, rank[b.status] or 5
        if ra ~= rb then return ra < rb end
        return (a.name or a.id or "") < (b.name or b.id or "")
    end)
    local selectedKey = Field(selection, "goalKey")
    if type(selectedKey) ~= "string" or #selectedKey == 0
        or #selectedKey > 100 then selectedKey = nil end
    view.summary = selectedKey
        and ("Selected Goal: " .. Text(Field(selection, "goalName"), selectedKey))
        or ("Reset Goals: " .. #list)
    if selectedKey then
        local selected = Invoke(planner, "Evaluate", selectedKey, periods)
        Add(view, "Selected: " .. Text(Field(selection, "goalName"), selectedKey),
            selected and ((kindNames[selected.resetKind] or "Unknown") .. " | "
                .. Text(selected.status, "Unknown") .. " | "
                .. Text(selected.reason, "Evidence unavailable"))
                or "Unknown | Choose a reset rule below.",
            selected and selected.status == "Confirmed" and "positive" or "muted")
    end
    for _, result in ipairs(list) do
        if result.id ~= selectedKey then
            local status = Text(result.status, "Unknown")
            local reason = Text(result.reason, "Evidence unavailable")
            Add(view, result.name or result.id,
                (kindNames[result.resetKind] or "Unknown") .. " | "
                    .. status .. " | " .. reason,
                status == "Confirmed" and "positive"
                    or status == "Expected" and "caution" or "muted", result)
        end
    end
    if #view.rows == 0 then Add(view, "Unknown", "No goals match this reset filter.") end
    view.footer = resetActionMessage
        or "A reset rule never confirms current availability."
end

local function PhaseView(view)
    local lens = context.phaseLens
    local point = Field(selection, "point")
    if not lens or type(point) ~= "table" then
        view.summary = "Select A Saved Map Point"
        Add(view, "Unknown", "Phase evidence is unavailable for this selection.")
        return
    end
    local evaluation = Invoke(lens, "Evaluate", point,
        Call(context.getPhaseContext, point) or {})
    local status = type(evaluation) == "table" and evaluation.status or "unknown"
    local labels = {
        live = "Locally Detected", override = "Player Override",
        ["condition-match"] = "Condition Matches",
        ["condition-mismatch"] = "Condition Mismatch",
        ["possible-mismatch"] = "Possible Mismatch",
        unknown = "Unknown",
    }
    view.summary = "Phase: " .. (labels[status] or "Unknown")
    Add(view, Text(Field(point, "name"), "Selected Map Point"),
        Text(type(evaluation) == "table" and evaluation.reason,
            "Phase is not exposed by the client."),
        (status == "live" or status == "condition-match") and "positive"
            or status == "condition-mismatch" and "caution" or "muted")
    local evidence = type(evaluation) == "table" and evaluation.evidence
    Add(view, "Evidence", EvidenceLabel(evidence))
    local action = type(evaluation) == "table" and evaluation.action or "show"
    Add(view, "Display Action", Text(action, "show"):sub(1, 1):upper()
        .. Text(action, "show"):sub(2))
    view.footer = "Absence alone never proves a phase mismatch."
end

local function TodayFilter()
    local db = Settings() or {}
    local value = db.vignetteRadarTodayFilter
    return TODAY_FILTER_NAMES[value] and value or "left"
end

local TODAY_STATE = { live = "Up Now", left = "Left", done = "Done This Reset" }
local function TodayView(view)
    local today = addon.VignetteRadarToday
    local data = today and today.Build() or nil
    if not data or not data.mapID then
        view.summary = "Today: Zone Unknown"
        Add(view, "Unknown", "Open the radar in a zone to list its rares and treasures.")
        view.footer = "Reset times come from the game clock."
        return
    end
    local counts = data.counts
    view.summary = (data.zone or "This Zone") .. ": " .. counts.rareLeft .. " Rares, "
        .. counts.treasureLeft .. " Treasures Left"
    view.footer = "Daily Reset In " .. today.Duration(data.daily) .. "  \194\183  Weekly In "
        .. today.Duration(data.weekly)
    local filter, list = TodayFilter(), {}
    for _, row in ipairs(data.rows) do
        if filter == "all" or (filter == "done") == (row.state == "done") then list[#list + 1] = row end
    end
    todayPages = math.max(1, math.ceil(#list / MAX_ROWS))
    if todayPage > todayPages then todayPage = todayPages end
    local first = (todayPage - 1) * MAX_ROWS
    local guidance = addon.VignetteRadarGuidance
    local dot = "  \194\183  "
    for index = first + 1, math.min(#list, first + MAX_ROWS) do
        local row = list[index]
        local yards = row.yards and guidance and guidance.Yards and guidance.Yards(row.yards) or nil
        local detail = (row.kind == "rare" and "Rare" or "Treasure") .. dot .. TODAY_STATE[row.state]
            .. (yards and (dot .. yards) or "")
            .. (row.state ~= "done" and (dot .. "Click To Route") or "")
        Add(view, row.name, detail, row.state == "live" and "positive"
            or row.state == "left" and "caution" or "muted", row.state ~= "done" and row or nil)
    end
    if #list == 0 then
        Add(view, filter == "done" and "Nothing Done Yet" or "Nothing Left Here",
            filter == "done" and "Rares and treasures you finish this reset show here."
                or "Every known rare and treasure in this zone is done this reset.")
    end
    if addon.Trace then addon.Trace.Log("today", "view %s filter=%s rows=%d page=%d/%d", tostring(data.mapID),
        filter, #list, todayPage, todayPages) end
end

function Intelligence.GetView(tab)
    tab = Known(tab) and tab or currentTab
    if tab == "Today" then
        local view = { tab = tab, rows = {}, summary = "", footer = "", enabled = true }
        TodayView(view)
        return view
    end
    local view = { tab = tab, rows = {}, summary = "", footer = "", enabled = Enabled(tab) }
    if not view.enabled then
        view.summary = tab .. " Is Disabled"
        Add(view, "Disabled", "Enable this page to inspect available evidence.")
        return view
    end
    if tab == "Warband" then WarbandView(view)
    elseif tab == "Resets" then ResetView(view)
    else PhaseView(view) end
    if view.more then view.footer = "Showing " .. (view.rowLimit or MAX_ROWS) .. " rows; "
        .. view.more .. " more. " .. view.footer end
    return view
end

function Intelligence.SetContext(newContext)
    context = type(newContext) == "table" and newContext or {}
    local db = Settings()
    if db and context.phaseLens
        and (db.vignetteRadarPhaseLensAction or db.vignetteRadarPhaseHeuristics ~= nil) then
        Invoke(context.phaseLens, "SetOptions", {
            action = db.vignetteRadarPhaseLensAction,
            heuristic = db.vignetteRadarPhaseHeuristics,
        })
    end
    if panel and panel:IsShown() then Intelligence.Refresh() end
end

function Intelligence.SetSelection(newSelection)
    selection = type(newSelection) == "table" and newSelection or {}
    resetActionMessage = nil
    if panel and panel:IsShown() then Intelligence.Refresh() end
end

function Intelligence.SetEnabled(tab, enabled)
    local key, db = ENABLE_KEYS[tab], Settings()
    if not key or not db then return false end
    db[key] = enabled == true
    Intelligence.Refresh()
    return true
end

-- A user rule classifies a selected goal; it never calls Observe and cannot
-- create a reset period or an availability confirmation. Persistence is
-- required before the panel reports success.
function Intelligence.SetResetRule(kind)
    local planner = context.resetPlanner
    local key = Field(selection, "goalKey")
    if type(key) ~= "string" or #key == 0 or #key > 100 then
        return false, "Select a goal first"
    end
    if not planner or type(planner.goals) ~= "table" then
        return false, "Reset planner unavailable"
    end
    if kind ~= "daily" and kind ~= "weekly" and kind ~= "one-time"
        and kind ~= "remove" then return false, "Unknown reset rule" end
    if type(context.onIntelligenceChange) ~= "function" then
        return false, "Saving unavailable"
    end
    local old = planner.goals[key]
    if kind == "remove" then
        if not old then return false, "No saved rule to remove" end
        planner.goals[key] = nil
    else
        local name = Field(selection, "goalName")
        local category = Field(selection, "goalCategory")
        local changed = Invoke(planner, "SetGoal", key, {
            name = type(name) == "string" and name or key,
            category = type(category) == "string" and category or nil,
            resetKind = kind, source = "user-rule",
        })
        if changed ~= true then return false, "Could not set reset rule" end
        if old and old.resetKind ~= kind then
            local record = planner.goals[key]
            record.complete = false
            record.completedPeriod = nil
            record.confirmedPeriod = nil
            record.confirmedSession = nil
        end
    end
    local ok, saved = pcall(context.onIntelligenceChange, "resetPlanner", planner)
    if not ok or saved ~= true then
        planner.goals[key] = old
        resetActionMessage = "Could Not Save Reset Rule."
        Intelligence.Refresh()
        return false, "Saving failed"
    end
    local names = { daily = "Daily", weekly = "Weekly",
        ["one-time"] = "One-Time" }
    resetActionMessage = kind == "remove"
        and "Reset Rule Removed. Availability Was Not Changed."
        or (names[kind] .. " Rule Saved. Availability Was Not Changed.")
    Intelligence.Refresh()
    return true
end

local function Accent()
    local style = addon.VignetteRadarStyle
    if style and type(style.Color) == "function" then
        local ok, r, g, b = pcall(style.Color, "accent")
        if ok and type(r) == "number" then return r, g, b end
    end
    return .57, .73, 1
end

local function Label(parent, size, x, y, width, height)
    local text = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(text, size, "")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetSize(width, height)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function Cycle(tab)
    local db = Settings()
    if not db then return end
    local key, choices
    if tab == "Today" then
        key, choices = "vignetteRadarTodayFilter", TODAY_FILTERS
        todayPage = 1
    elseif tab == "Warband" then
        key, choices = "vignetteRadarWarbandView", { "account", "character" }
    elseif tab == "Resets" then
        key, choices = "vignetteRadarResetCategory", { "all", "daily", "weekly", "one-time" }
    else
        key, choices = "vignetteRadarPhaseLensAction", { "show", "dim", "hide" }
    end
    local index = 0
    local current = tab == "Today" and TodayFilter() or db[key]
    for i, value in ipairs(choices) do if current == value then index = i; break end end
    db[key] = choices[index % #choices + 1]
    if tab == "Phase" and context.phaseLens then
        Invoke(context.phaseLens, "SetOptions", {
            action = db[key], heuristic = db.vignetteRadarPhaseHeuristics == true,
        })
    end
    Intelligence.Refresh()
end

local function OptionText(tab)
    local db = Settings() or {}
    if tab == "Today" then
        return "Show: " .. TODAY_FILTER_NAMES[TodayFilter()]
    elseif tab == "Warband" then
        return "View: " .. (db.vignetteRadarWarbandView == "character"
            and "Character" or "Account")
    elseif tab == "Resets" then
        local value = db.vignetteRadarResetCategory or "all"
        return "Filter: " .. (value == "one-time" and "One-Time"
            or value:sub(1, 1):upper() .. value:sub(2))
    else
        local value = db.vignetteRadarPhaseLensAction or "show"
        return "Action: " .. value:sub(1, 1):upper() .. value:sub(2)
    end
end

local function Build()
    if panel then return panel end
    local controls = addon.VignetteRadarControls
    if type(CreateFrame) ~= "function" or not controls or not controls.PopupSurface
        or not controls.Button then return nil end
    panel = CreateFrame("Frame", "VignetteRadarIntelligencePanel", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    controls.PopupSurface(panel)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarIntelligencePanel"
    end
    panel.title = Label(panel, 13, 18, -12, 405, 18)
    panel.title:SetText("Today")
    panel.close = addon.VignetteRadarIconButton.Create(panel, "close", { size = 20,
        label = "Close Intelligence", onClick = function() Intelligence.Close() end })
    panel.close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -9)
    panel.tabs = {}
    for index, tab in ipairs(TABS) do
        local button = controls.Button(panel, tab, 89, 24)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (index - 1) * 96, -43)
        button:SetScript("OnClick", function() currentTab = tab; todayPage = 1; Intelligence.Refresh() end)
        panel.tabs[tab] = button
    end
    panel.headerLine = panel:CreateTexture(nil, "ARTWORK")
    panel.headerLine:SetTexture(WHITE)
    panel.headerLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 17, -74)
    panel.headerLine:SetSize(WIDTH - 34, 1)
    panel.enable = controls.Button(panel, "Enabled", 92, 24)
    panel.enable:SetPoint("TOPLEFT", panel, "TOPLEFT", 17, -83)
    panel.enable:SetScript("OnClick", function()
        if currentTab == "Today" then
            local sweep = addon.VignetteRadarZoneSweep
            if sweep then sweep.Start() end
            return
        end
        Intelligence.SetEnabled(currentTab, not Enabled(currentTab))
    end)
    panel.option = controls.Button(panel, "", 185, 24)
    panel.option:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -17, -83)
    panel.option:SetScript("OnClick", function() Cycle(currentTab) end)
    panel.extra = controls.Button(panel, "", 174, 24)
    panel.extra:SetPoint("TOPLEFT", panel, "TOPLEFT", 119, -83)
    panel.extra:SetScript("OnClick", function()
        if currentTab == "Today" then
            todayPage = todayPage % todayPages + 1
            Intelligence.Refresh()
        elseif currentTab == "Phase" then
            local db = Settings()
            if not db then return end
            db.vignetteRadarPhaseHeuristics = db.vignetteRadarPhaseHeuristics ~= true
            if context.phaseLens then
                Invoke(context.phaseLens, "SetOptions", {
                    action = db.vignetteRadarPhaseLensAction or "show",
                    heuristic = db.vignetteRadarPhaseHeuristics,
                })
            end
            Intelligence.Refresh()
        end
    end)
    panel.summary = Label(panel, 11, 19, -118, WIDTH - 38, 18)
    panel.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(WIDTH - 34, 32)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 17, -143 - (i - 1) * 34)
        row.face = row:CreateTexture(nil, "BACKGROUND")
        row.face:SetAllPoints(row)
        row.face:SetTexture(WHITE)
        row.title = Label(row, 10, 8, -3, WIDTH - 52, 13)
        row.detail = Label(row, 9, 8, -17, WIDTH - 52, 12)
        row:SetScript("OnClick", function(self)
            local payload = self.payload
            if type(payload) ~= "table" then return end
            if currentTab == "Today" then
                local today = addon.VignetteRadarToday
                if today then today.Route(payload) end
            elseif currentTab == "Resets" and payload.id then
                selection.goalKey = payload.id
                selection.goalName = payload.name
                resetActionMessage = nil
                Intelligence.Refresh()
            end
        end)
        row:SetScript("OnEnter", function(self)
            if self.payload then
                local r, g, b = Accent()
                self.face:SetVertexColor(r, g, b, .19)
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.face:SetVertexColor(.17, .21, .23, .30)
        end)
        panel.rows[i] = row
    end
    panel.resetActions = {}
    for index, action in ipairs({
        { label = "Daily", kind = "daily" },
        { label = "Weekly", kind = "weekly" },
        { label = "One-Time", kind = "one-time" },
        { label = "Remove", kind = "remove" },
    }) do
        local button = controls.Button(panel, action.label, 112, 28)
        button:SetPoint("TOPLEFT", panel, "TOPLEFT", 17 + (index - 1) * 120, -315)
        button:SetScript("OnClick", function() Intelligence.SetResetRule(action.kind) end)
        button:Hide()
        panel.resetActions[action.kind] = button
    end
    panel.footerLine = panel:CreateTexture(nil, "ARTWORK")
    panel.footerLine:SetTexture(WHITE)
    panel.footerLine:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 17, 35)
    panel.footerLine:SetSize(WIDTH - 34, 1)
    panel.footer = Label(panel, 9, 19, -356, WIDTH - 38, 18)
    panel:Hide()
    return panel
end

function Intelligence.Refresh()
    if not panel or not panel:IsShown() then return Intelligence.GetView(currentTab) end
    local view = Intelligence.GetView(currentTab)
    local r, g, b = Accent()
    addon.VignetteRadarControls.RefreshPopupSurface(panel)
    panel.title:SetTextColor(r, g, b)
    panel.summary:SetTextColor(.85, .91, .93)
    panel.headerLine:SetVertexColor(r, g, b, .22)
    panel.footerLine:SetVertexColor(r, g, b, .16)
    panel.footer:SetTextColor(.57, .69, .72)
    panel.footer:SetText(view.footer)
    panel.summary:SetText(view.summary)
    panel.title:SetText(currentTab == "Today" and "Today" or "Intelligence")
    panel.enable:SetText(currentTab == "Today" and "Sweep Zone" or view.enabled and "Enabled" or "Disabled")
    panel.option:SetText(OptionText(currentTab))
    panel.option:SetEnabled(view.enabled)
    local selectedKey = Field(selection, "goalKey")
    local canEditReset = currentTab == "Resets" and view.enabled
        and type(selectedKey) == "string" and #selectedKey > 0
        and #selectedKey <= 100 and context.resetPlanner
        and type(context.resetPlanner.goals) == "table"
        and type(context.onIntelligenceChange) == "function"
    for kind, button in pairs(panel.resetActions) do
        button:SetEnabled(canEditReset and (kind ~= "remove"
            or context.resetPlanner.goals[selectedKey] ~= nil) or false)
        local selectedGoal = canEditReset and context.resetPlanner.goals[selectedKey]
        if selectedGoal and selectedGoal.resetKind == kind then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
        if currentTab == "Resets" then button:Show() else button:Hide() end
    end
    if currentTab == "Today" then
        panel.extra:SetText("Page " .. todayPage .. " Of " .. todayPages)
        panel.extra:SetEnabled(todayPages > 1)
        if todayPages > 1 then panel.extra:Show() else panel.extra:Hide() end
    elseif currentTab == "Phase" then
        local db = Settings() or {}
        panel.extra:SetText(db.vignetteRadarPhaseHeuristics == true
            and "Heuristic: On" or "Heuristic: Off")
        panel.extra:SetEnabled(view.enabled)
        panel.extra:Show()
    else
        panel.extra:Hide()
    end
    local slot = 0
    for _, tab in ipairs(TABS) do
        local button = panel.tabs[tab]
        if tab == currentTab then button:LockHighlight() else button:UnlockHighlight() end
        -- Without Advanced Tools only Today shows, and alone it needs no tab.
        if Visible(tab) and Visible("Warband") then
            button:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + slot * 96, -43)
            slot = slot + 1
            button:Show()
        else
            button:Hide()
        end
    end
    for i, row in ipairs(panel.rows) do
        local data = view.rows[i]
        row.payload = data and data.payload or nil
        if data then
            row.title:SetText(data.title)
            row.detail:SetText(data.detail)
            row.face:SetVertexColor(.17, .21, .23, .30)
            if data.tone == "positive" then row.title:SetTextColor(.54, .91, .76)
            elseif data.tone == "caution" then row.title:SetTextColor(1, .77, .39)
            else row.title:SetTextColor(.86, .92, .94) end
            row.detail:SetTextColor(.62, .72, .75)
            row:Show()
        else
            row:Hide()
        end
    end
    return view
end

function Intelligence.Open(tab)
    -- An explicit tab opens as asked; the default falls back to Today.
    if Known(tab) then currentTab = tab
    elseif not Visible(currentTab) then currentTab = "Today" end
    todayPage = 1
    local frame = Build()
    if not frame then return false, "UI controls unavailable" end
    frame:Show()
    Intelligence.Refresh()
    return true
end

function Intelligence.Close()
    if panel then panel:Hide() end
end

function Intelligence.Toggle(tab)
    if panel and panel:IsShown() then
        Intelligence.Close()
        return false
    end
    return Intelligence.Open(tab)
end

function Intelligence.IsOpen()
    return panel ~= nil and panel:IsShown()
end

-- Today follows the radar's scans while it is open (at most every 2 s).
if addon.Bus and addon.Bus.On then
    addon.Bus.On("POINTS_CHANGED", function()
        if currentTab == "Today" and panel and panel:IsShown() then Intelligence.Refresh() end
    end, { coalesce = 2 })
end
