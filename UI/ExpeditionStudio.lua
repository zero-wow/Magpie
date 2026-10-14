local _, addon = ...
if type(addon) ~= "table" then return end

-- A deliberately separate planning surface. Editing and importing never change
-- the active trip until Apply; the route engine remains the schema authority.
local API = {}
addon.VignetteRadarExpeditionStudio = API

local WIDTH, HEIGHT, PAGE_SIZE = 570, 500, 5
local MAX_CANDIDATES, MAX_IMPORT_BYTES = 256, 24576
local KINDS = { rare = true, treasure = true, quest = true, pin = true }
local CANDIDATE_KINDS = { "rare", "treasure", "quest" }
local engine, panel, card, cardAnchor, draft, player, onApply, estimateTravel
local candidates = { rare = {}, treasure = {}, quest = {} }
local cursor = { rare = 1, treasure = 1, quest = 1 }
local page = 1
local message = "Choose goals to build a route."

local function Engine()
    engine = addon.VignetteRadarExpeditions
    return engine
end

local function Settings()
    if type(addon.GetSettings) ~= "function" then return nil end
    local ok, db = pcall(addon.GetSettings)
    return ok and type(db) == "table" and db or nil
end

local Safe, Field, Number = addon.Secret.Safe, addon.Secret.Field, addon.Secret.Number

local function Label(parent, text, x, y, width, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size or 10, "")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetSize(width, 18)
    label:SetTextColor(.79, .87, .89, 1)
    label:SetWordWrap(false)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function Button(parent, text, x, y, width, action)
    local controls = addon.VignetteRadarControls
    local button = controls and controls.Button(parent, text, width, 22)
    if not button then
        button = CreateFrame("Button", nil, parent)
        button:SetSize(width, 22)
        button:SetText(text)
    end
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetScript("OnClick", action)
    return button
end

local function Rule(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y)
    line:SetHeight(1)
    line:SetColorTexture(.49, .75, .82, .16)
    return line
end

local function CopyTrip(source)
    local e = Engine()
    if not (e and type(source) == "table" and Safe(source)
        and type(Field(source, "goals")) == "table") then
        return nil, "Route data is unavailable"
    end
    local copy, err = e.New(source.goals, { priority = source.priority })
    if not copy then return nil, err end
    for index, goal in ipairs(copy.goals) do
        local old = source.goals[index]
        local state = Field(old, "state")
        if state == "complete" or state == "skipped" then goal.state = state end
    end
    local currentID, lockedID = Field(source, "currentID"), Field(source, "lockedID")
    for _, goal in ipairs(copy.goals) do
        if goal.state ~= "complete" and goal.state ~= "skipped" then
            if goal.id == currentID then copy.currentID = currentID end
            if goal.id == lockedID then copy.lockedID = lockedID end
        end
    end
    copy.paused = Field(source, "paused") == true
    return copy
end

local function ValidGoal(source)
    local e = Engine()
    if not e or type(source) ~= "table" then return nil end
    local kind = Field(source, "kind") or Field(source, "category")
    if kind == "mob" or kind == "boss" then kind = "rare" end
    if kind == "item" or kind == "chest" then kind = "treasure" end
    if not KINDS[kind] then return nil end
    local id = Field(source, "id") or Field(source, "questID")
        or Field(source, "vignetteID") or Field(source, "npcID")
    local mapID = Field(source, "mapID")
    local x, y = Field(source, "mapX") or Field(source, "x"),
        Field(source, "mapY") or Field(source, "y")
    if id == nil and Number(mapID) and Number(x) and Number(y) then
        id = tostring(mapID) .. ":" .. math.floor(x * 10000 + .5)
            .. ":" .. math.floor(y * 10000 + .5)
    end
    if type(id) ~= "string" and type(id) ~= "number" then return nil end
    id = tostring(id)
    if id:sub(1, #kind + 1) ~= kind .. ":" then id = kind .. ":" .. id end
    local name = Field(source, "name") or Field(source, "title") or id
    local goal = { id = id, kind = kind, name = name, mapID = mapID,
        mapX = x, mapY = y, worldX = Field(source, "worldX"),
        worldY = Field(source, "worldY"),
        instanceID = Field(source, "instanceID"),
        sourceID = Field(source, "sourceID") }
    local trip = e.New({ goal })
    return trip and trip.goals[1] or nil
end

function API.SetCandidates(entries)
    candidates = { rare = {}, treasure = {}, quest = {} }
    cursor = { rare = 1, treasure = 1, quest = 1 }
    if type(entries) == "table" and Safe(entries) then
        for index = 1, math.min(#entries, MAX_CANDIDATES) do
            local goal = ValidGoal(entries[index])
            if goal and candidates[goal.kind] then
                candidates[goal.kind][#candidates[goal.kind] + 1] = goal
            end
        end
    end
    API.Refresh()
end

function API.SetPlayer(snapshot)
    player = type(snapshot) == "table" and Safe(snapshot) and snapshot or nil
    API.Refresh()
end

function API.SetOnApply(callback)
    onApply = type(callback) == "function" and callback or nil
end

-- The callback receives (player, goal) and may return a travel
-- { costYards, basis, reason } estimate. It is evaluated only when the Studio
-- refreshes or applies, never by an OnUpdate script.
function API.SetEstimateTravel(callback)
    estimateTravel = type(callback) == "function" and callback or nil
    API.Refresh()
end

function API.GetActive()
    local db = Settings()
    if not db or db.vignetteRadarExpedition == nil then return nil end
    return CopyTrip(db.vignetteRadarExpedition)
end

function API.GetDraft()
    return draft and CopyTrip(draft) or nil
end

function API.LoadDraft()
    local db = Settings()
    local source = db and db.vignetteRadarExpedition
    if source == nil then draft, message = nil, "Choose goals to build a route."; page = 1; return true end
    local copy, err = CopyTrip(source)
    if not copy then
        draft, message = nil, "Saved route invalid: " .. tostring(err)
        page = 1
        return false, err
    end
    draft, page, message = copy, 1, "Saved route loaded as a draft."
    return true
end

function API.AddGoal(source)
    local goal = ValidGoal(source)
    if not goal then return false, "Goal has no valid type or location" end
    local goals = {}
    if draft then
        for index, existing in ipairs(draft.goals) do
            if existing.id == goal.id then return false, "Goal already in route" end
            goals[index] = existing
        end
    end
    goals[#goals + 1] = goal
    local e = Engine()
    local nextDraft, err = e.New(goals, { priority = draft and draft.priority })
    if not nextDraft then return false, err end
    if draft then
        for index, old in ipairs(draft.goals) do
            nextDraft.goals[index].state = old.state
        end
        nextDraft.currentID, nextDraft.lockedID = draft.currentID, draft.lockedID
        nextDraft.paused = draft.paused
    end
    draft = nextDraft
    page = math.max(1, math.ceil(#draft.goals / PAGE_SIZE))
    message = goal.name .. " added to the draft."
    API.Refresh()
    return true
end

function API.AddCandidate(kind)
    local list = candidates[kind]
    if not list or not list[cursor[kind]] then return false, "No " .. tostring(kind) .. " candidate" end
    return API.AddGoal(list[cursor[kind]])
end

function API.Move(id, offset)
    if not draft then return false, "No draft" end
    local from
    for index, goal in ipairs(draft.goals) do if goal.id == id then from = index; break end end
    if not from then return false, "Unknown goal" end
    local to = from + offset
    local ok, err = Engine().Reorder(draft, id, to)
    if ok then
        page = math.max(1, math.ceil(to / PAGE_SIZE))
        message = "Goal order updated."
        API.Refresh()
    end
    return ok, err
end

function API.Skip(id)
    if not draft then return false, "No draft" end
    local ok, err = Engine().Skip(draft, id)
    if ok then message = "Stop skipped in the draft."; API.Refresh() end
    return ok, err
end

function API.Lock(id)
    if not draft then return false, "No draft" end
    local target = draft.lockedID == id and nil or id
    local ok, err = Engine().Lock(draft, target)
    if ok then message = target and "Stop locked in the draft." or "Stop unlocked."; API.Refresh() end
    return ok, err
end

function API.Pause(paused)
    if not draft then return false, "No draft" end
    local ok = Engine().Pause(draft, paused)
    if ok then message = draft.paused and "Draft route paused." or "Draft route resumed."; API.Refresh() end
    return ok
end

function API.Remove(id)
    if not draft then return false, "No draft" end
    local goals, found = {}, false
    for _, goal in ipairs(draft.goals) do
        if goal.id == id then found = true
        else
            local clean = {}
            for key, value in pairs(goal) do clean[key] = value end
            clean.dependsOn = {}
            for _, dep in ipairs(goal.dependsOn or {}) do
                if dep ~= id then clean.dependsOn[#clean.dependsOn + 1] = dep end
            end
            goals[#goals + 1] = clean
        end
    end
    if not found then return false, "Unknown goal" end
    if #goals == 0 then draft = nil
    else
        local nextDraft, err = Engine().New(goals, { priority = draft.priority })
        if not nextDraft then return false, err end
        for index, goal in ipairs(goals) do nextDraft.goals[index].state = goal.state end
        nextDraft.currentID = draft.currentID ~= id and draft.currentID or nil
        nextDraft.lockedID = draft.lockedID ~= id and draft.lockedID or nil
        nextDraft.paused = draft.paused
        draft = nextDraft
    end
    page = math.min(page, math.max(1, math.ceil((draft and #draft.goals or 0) / PAGE_SIZE)))
    message = "Goal removed from the draft."
    API.Refresh()
    return true
end

function API.Preview()
    if not draft then return nil, nil, "Add a goal to preview the route" end
    local copy = CopyTrip(draft)
    if not copy then return nil, nil, "Draft route is invalid" end
    if estimateTravel and player and not (copy.paused or copy.currentID or copy.lockedID) then
        local ranked = {}
        for index, goal in ipairs(copy.goals) do
            local state = Engine().Status(copy, goal.id)
            if state == "available" then
                local ok, estimate = pcall(estimateTravel, player, goal)
                if ok then
                    local cost = Number(type(estimate) == "table"
                        and Field(estimate, "costYards") or estimate)
                    if cost and cost >= 0 and cost <= 100000000 then
                        local reason = type(estimate) == "table" and Field(estimate, "reason")
                        local basis = type(estimate) == "table" and Field(estimate, "basis")
                        ranked[#ranked + 1] = {
                            id = goal.id, kind = goal.kind, name = goal.name,
                            mapID = goal.mapID, mapX = goal.mapX, mapY = goal.mapY,
                            worldX = goal.worldX, worldY = goal.worldY,
                            instanceID = goal.instanceID, distance = cost,
                            distanceKind = type(basis) == "string" and basis or "travel estimate",
                            reason = type(reason) == "string" and reason:sub(1, 120)
                                or "Estimated travel cost",
                            travelEstimate = true, order = index,
                            priority = copy.priority[goal.kind] or 50,
                        }
                    end
                end
            end
        end
        if #ranked > 0 then
            table.sort(ranked, function(a, b)
                if a.priority ~= b.priority then return a.priority > b.priority end
                if a.distance ~= b.distance then return a.distance < b.distance end
                return a.order < b.order
            end)
            return ranked[1], ranked[2]
        end
    end
    return Engine().Plan(copy, player or {})
end

function API.Apply()
    local db = Settings()
    if not db then return false, "Settings unavailable" end
    if not draft then
        db.vignetteRadarExpedition = nil
        message = "Expedition cleared."
    else
        local copy, err = CopyTrip(draft)
        if not copy then return false, err end
        if estimateTravel and not (copy.currentID or copy.lockedID or copy.paused) then
            local now = API.Preview()
            if now and now.travelEstimate then copy.currentID = now.id end
        end
        db.vignetteRadarExpedition = copy
        message = "Expedition applied."
    end
    if onApply then pcall(onApply, db.vignetteRadarExpedition) end
    API.Refresh()
    API.RefreshCard()
    return true
end

function API.SkipCurrent()
    local db = Settings()
    local trip = API.GetActive()
    if not (db and trip) then return false, "No active expedition" end
    if not trip.currentID and not trip.paused then
        Engine().Plan(trip, player or {})
    end
    if not trip.currentID then return false, "No current stop to skip" end
    local ok, err = Engine().Skip(trip, trip.currentID)
    if not ok then return false, err end
    if not trip.paused then Engine().Plan(trip, player or {}) end
    db.vignetteRadarExpedition = trip
    if onApply then pcall(onApply, trip) end
    message = "Current stop skipped."
    API.Refresh()
    API.RefreshCard()
    return true
end

local function Encode(value)
    return (tostring(value or ""):gsub("([^%w%-%._ ])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function Decode(value)
    if value:gsub("%%[%x][%x]", ""):find("%%") then return nil end
    local decoded = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return not decoded:find("[%c]") and decoded or nil
end

function API.Export()
    if not draft then return nil, "No draft route" end
    local valid, err = CopyTrip(draft)
    if not valid then return nil, err end
    local lines = { "VR-EXPEDITION-1",
        "# kind  id  name  mapID  mapX  mapY  sourceID  dependsOn  worldX  worldY  instanceID" }
    for _, goal in ipairs(valid.goals) do
        local deps = {}
        for _, id in ipairs(goal.dependsOn or {}) do deps[#deps + 1] = Encode(id) end
        lines[#lines + 1] = table.concat({
            goal.kind, Encode(goal.id), Encode(goal.name), goal.mapID or "",
            goal.mapX or "", goal.mapY or "", Encode(goal.sourceID),
            table.concat(deps, ","), goal.worldX or "", goal.worldY or "",
            goal.instanceID or "",
        }, "\t")
    end
    local output = table.concat(lines, "\n")
    return #output <= MAX_IMPORT_BYTES and output or nil,
        #output > MAX_IMPORT_BYTES and "Route too large to export" or nil
end

function API.Import(text)
    if type(text) ~= "string" or not Safe(text) or #text > MAX_IMPORT_BYTES then
        return false, "Route text must be under 24 KB"
    end
    local lines = {}
    text = text:gsub("\r\n", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if #lines >= 67 then return false, "Too many route lines" end
        lines[#lines + 1] = line
    end
    if lines[1] ~= "VR-EXPEDITION-1" then return false, "Unknown route format" end
    local goals = {}
    for index = 2, #lines do
        local line = lines[index]
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local fields = {}
            for value in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = value end
            if #fields ~= 11 then return false, "Invalid row " .. index end
            local id, name, sourceID = Decode(fields[2]), Decode(fields[3]), Decode(fields[7])
            if not id or not name or not sourceID then return false, "Invalid text in row " .. index end
            local goal = { id = id, kind = fields[1], name = name }
            if fields[4] ~= "" or fields[5] ~= "" or fields[6] ~= "" then
                goal.mapID, goal.mapX, goal.mapY =
                    tonumber(fields[4]), tonumber(fields[5]), tonumber(fields[6])
                if not goal.mapID or not goal.mapX or not goal.mapY then
                    return false, "Invalid position in row " .. index
                end
            end
            if sourceID ~= "" then goal.sourceID = sourceID end
            if fields[8] ~= "" then
                goal.dependsOn = {}
                for dep in (fields[8] .. ","):gmatch("(.-),") do
                    local decoded = Decode(dep)
                    if not decoded then return false, "Invalid dependency in row " .. index end
                    goal.dependsOn[#goal.dependsOn + 1] = decoded
                end
            end
            if fields[9] ~= "" or fields[10] ~= "" then
                goal.worldX, goal.worldY = tonumber(fields[9]), tonumber(fields[10])
                if not goal.worldX or not goal.worldY then
                    return false, "Invalid world position in row " .. index
                end
            end
            if fields[11] ~= "" then
                goal.instanceID = tonumber(fields[11])
                if not goal.instanceID then return false, "Invalid instance in row " .. index end
            end
            goals[#goals + 1] = goal
            if #goals > 64 then return false, "Route has more than 64 goals" end
        end
    end
    local imported, err = Engine().New(goals)
    if not imported then return false, err end
    draft, page = imported, 1
    message = "Route imported as a draft. Review it, then Apply."
    API.Refresh()
    return true
end

local function Accent()
    local style = addon.VignetteRadarStyle
    if style and type(style.Color) == "function" then return style.Color("accent") end
    return .05, .82, .62
end

local function CardEnabled()
    local db = Settings()
    return db and db.vignetteRadarExpeditionCardVisible ~= false
end

local function EnsureCard()
    if card then return card end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end
    card = CreateFrame("Frame", "VignetteRadarExpeditionCard", UIParent, "BackdropTemplate")
    card:SetSize(300, 127)
    card:SetFrameStrata("DIALOG")
    card:SetClampedToScreen(true)
    card:EnableMouse(true)
    card:SetMovable(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", function(self) self:StartMoving() end)
    card:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if cardAnchor then
        card:SetPoint("TOPLEFT", cardAnchor, "TOPRIGHT", 8, 0)
    else
        card:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -210)
    end
    local controls = addon.VignetteRadarControls
    if controls then controls.RoundedStatusSurface(card) end
    card.title = Label(card, "Expedition", 12, -9, 170, 11)
    local icons = addon.VignetteRadarIconButton
    card.open = icons.Create(card, "list", { size = 20, label = "Open Studio",
        tooltip = "Plan, order and share this expedition's goals.", onClick = function() API.Open() end })
    card.open:SetPoint("TOPLEFT", card, "TOPLEFT", 240, -7)
    card.hide = icons.Create(card, "close", { size = 20, label = "Hide Card",
        onClick = function() API.SetCardVisible(false) end })
    card.hide:SetPoint("TOPLEFT", card, "TOPLEFT", 266, -7)
    Rule(card, -32)
    card.now = Label(card, "", 12, -38, 276, 9)
    card.next = Label(card, "", 12, -59, 276, 9)
    card.progress = Label(card, "", 12, -80, 276, 9)
    card.skip = Button(card, "Skip Current", 12, -102, 112, function()
        local ok, err = API.SkipCurrent()
        if not ok then
            card.progress:SetText(err or "No current stop to skip.")
        end
    end)
    card:Hide()
    return card
end

function API.SetCardAnchor(anchor)
    if cardAnchor == anchor then return end
    cardAnchor = anchor
    if card and type(card.ClearAllPoints) == "function" then
        card:ClearAllPoints()
        if cardAnchor then
            card:SetPoint("TOPLEFT", cardAnchor, "TOPRIGHT", 8, 0)
        else
            card:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -210)
        end
    end
end

function API.SetCardVisible(enabled)
    local db = Settings()
    if not db then return false, "Settings unavailable" end
    db.vignetteRadarExpeditionCardVisible = enabled == true
    API.RefreshCard()
    return true
end

function API.IsCardVisible()
    return card and card:IsShown() or false
end

-- Event-driven only. The parent calls this after route, quest, loot, or map
-- changes; a hidden card never creates widgets or plans a route.
function API.RefreshCard()
    if panel and panel:IsShown() then
        if card then card:Hide() end
        return
    end
    local db = Settings()
    if not (CardEnabled() and db and db.vignetteRadarExpedition) then
        if card then card:Hide() end
        return
    end
    local trip = API.GetActive()
    if not trip then
        if card then card:Hide() end
        return
    end
    local ui = EnsureCard()
    if not ui then return end
    local now, nextStop, reason = Engine().Plan(trip, player or {})
    local complete, skipped = 0, 0
    for _, goal in ipairs(trip.goals) do
        if goal.state == "complete" then complete = complete + 1
        elseif goal.state == "skipped" then skipped = skipped + 1 end
    end
    local r, g, b = Accent()
    ui.title:SetTextColor(r, g, b, 1)
    if addon.VignetteRadarControls then
        addon.VignetteRadarControls.RefreshRoundedStatusSurface(ui)
    end
    ui.now:SetText(now and ("Now: " .. now.name) or ("Now: " .. (reason or "No available stop")))
    ui.next:SetText(nextStop and ("Next: " .. nextStop.name) or "Next: No available stop")
    ui.progress:SetText(complete .. " Complete | " .. skipped .. " Skipped | "
        .. #trip.goals .. " Total")
    ui.skip:SetEnabled(now ~= nil or trip.currentID ~= nil)
    ui:Show()
end

local function Transfer(mode)
    if not panel then return end
    local box = panel.transfer
    box.mode = mode
    box.title:SetText(mode == "export" and "Export Route" or "Import Route")
    box.hint:SetText(mode == "export"
        and "Select all and copy this data-only route."
        or "Paste a VR-EXPEDITION-1 route, then choose Load Draft.")
    if mode == "export" then
        local text, err = API.Export()
        box.input:SetText(text or "")
        box.result:SetText(err or "Route text is ready to copy.")
        box.load:Hide()
        box.select:Show()
        box.input:HighlightText()
    else
        box.input:SetText("")
        box.result:SetText("Imported goals remain a draft until Apply.")
        box.load:Show()
        box.select:Hide()
    end
    box:Show()
    box.input:SetFocus()
end

local function EnsureUI()
    if panel then return panel end
    if type(CreateFrame) ~= "function" or not UIParent then return nil end
    panel = CreateFrame("Frame", "VignetteRadarExpeditionStudioPanel", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarExpeditionStudioPanel"
    end
    if addon.VignetteRadarControls then addon.VignetteRadarControls.PopupSurface(panel) end
    panel.title = Label(panel, "Expedition Studio", 18, -10, 400, 12)
    panel.close = addon.VignetteRadarIconButton.Create(panel, "close", { size = 20,
        label = "Close Studio", onClick = function() API.Close() end })
    panel.close:SetPoint("TOPLEFT", panel, "TOPLEFT", WIDTH - 40, -9)
    Rule(panel, -37)
    panel.candidateHeader = Label(panel, "Add Current Goals", 18, -46, 300, 10)
    panel.candidateRows = {}
    for index, kind in ipairs(CANDIDATE_KINDS) do
        local y = -70 - (index - 1) * 32
        local row = {}
        row.kind = Label(panel, kind:sub(1, 1):upper() .. kind:sub(2), 18, y - 2, 72, 10)
        row.name = Label(panel, "", 94, y - 2, 258, 10)
        row.prev = Button(panel, "Prev", 359, y, 48, function()
            local count = #candidates[kind]
            if count > 0 then cursor[kind] = (cursor[kind] - 2) % count + 1; API.Refresh() end
        end)
        row.next = Button(panel, "Next", 413, y, 48, function()
            local count = #candidates[kind]
            if count > 0 then cursor[kind] = cursor[kind] % count + 1; API.Refresh() end
        end)
        row.add = Button(panel, "Add", 467, y, 84, function()
            local ok, err = API.AddCandidate(kind)
            if not ok then message = err; API.Refresh() end
        end)
        panel.candidateRows[kind] = row
    end
    Rule(panel, -173)
    panel.routeHeader = Label(panel, "Draft Goals", 18, -182, 280, 10)
    panel.rows = {}
    for index = 1, PAGE_SIZE do
        local y = -206 - (index - 1) * 31
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(WIDTH - 36, 28)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not (self.reason and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.goalName or "Route Goal")
            GameTooltip:AddLine(self.reason, .72, .82, .86, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        row.name = Label(row, "", 0, -4, 255, 10)
        row.up = Button(row, "Up", 260, -2, 37, function() API.Move(row.goalID, -1) end)
        row.down = Button(row, "Down", 302, -2, 48, function() API.Move(row.goalID, 1) end)
        row.lock = Button(row, "Lock", 355, -2, 48, function() API.Lock(row.goalID) end)
        row.skip = Button(row, "Skip", 408, -2, 48, function() API.Skip(row.goalID) end)
        row.remove = Button(row, "Remove", 461, -2, 72, function() API.Remove(row.goalID) end)
        panel.rows[index] = row
    end
    panel.pagePrev = Button(panel, "Previous Page", 18, -366, 105, function()
        page = math.max(1, page - 1); API.Refresh()
    end)
    panel.pageLabel = Label(panel, "", 240, -368, 90, 9)
    panel.pageLabel:SetJustifyH("CENTER")
    panel.pageNext = Button(panel, "Next Page", 447, -366, 105, function()
        page = page + 1; API.Refresh()
    end)
    Rule(panel, -395)
    panel.now = Label(panel, "", 18, -400, WIDTH - 36, 10)
    panel.next = Label(panel, "", 18, -419, WIDTH - 36, 10)
    panel.message = Label(panel, "", 18, -439, WIDTH - 36, 9)
    panel.pause = Button(panel, "Pause", 18, -464, 80, function()
        local ok, err = API.Pause(not (draft and draft.paused))
        if not ok then message = err; API.Refresh() end
    end)
    panel.preview = Button(panel, "Preview", 108, -464, 80, function() API.Refresh() end)
    panel.apply = Button(panel, "Apply", 198, -464, 80, function()
        local ok, err = API.Apply()
        if not ok then message = err; API.Refresh() end
    end)
    panel.cancel = Button(panel, "Cancel", 288, -464, 80, function() API.Close() end)
    panel.import = Button(panel, "Import", 378, -464, 80, function() Transfer("import") end)
    panel.export = Button(panel, "Export", 468, -464, 84, function() Transfer("export") end)

    local transfer = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    transfer:SetSize(WIDTH - 28, 257)
    transfer:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -177)
    transfer:EnableMouse(true)
    if addon.VignetteRadarControls then addon.VignetteRadarControls.PopupSurface(transfer) end
    transfer.title = Label(transfer, "", 14, -10, 460, 11)
    transfer.hint = Label(transfer, "", 14, -36, WIDTH - 60, 9)
    transfer.input = CreateFrame("EditBox", nil, transfer, "BackdropTemplate")
    transfer.input:SetSize(WIDTH - 60, 136)
    transfer.input:SetPoint("TOPLEFT", transfer, "TOPLEFT", 16, -62)
    transfer.input:SetMultiLine(true)
    transfer.input:SetAutoFocus(false)
    addon.VignetteRadarStyle.SetFont(transfer.input, 11, "")
    transfer.input:SetTextInsets(8, 8, 7, 7)
    transfer.input:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    transfer.input:SetBackdropColor(.015, .025, .035, .96)
    transfer.input:SetBackdropBorderColor(.4, .53, .59, .45)
    transfer.input:SetMaxBytes(MAX_IMPORT_BYTES)
    transfer.input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); transfer:Hide() end)
    transfer.result = Label(transfer, "", 16, -205, WIDTH - 60, 9)
    transfer.load = Button(transfer, "Load Draft", 16, -228, 124, function()
        local ok, err = API.Import(transfer.input:GetText())
        if ok then transfer:Hide()
        else transfer.result:SetText(err or "Invalid route.") end
    end)
    transfer.select = Button(transfer, "Select All", 16, -228, 124, function()
        transfer.input:SetFocus(); transfer.input:HighlightText()
    end)
    Button(transfer, "Close", WIDTH - 126, -228, 82, function() transfer:Hide() end)
    panel.transfer = transfer
    transfer:Hide()
    panel:Hide()
    return panel
end

function API.Refresh()
    if not (panel and panel:IsShown()) then return end
    local r, g, b = Accent()
    panel.title:SetTextColor(r, g, b, 1)
    panel.candidateHeader:SetTextColor(r, g, b, 1)
    panel.routeHeader:SetTextColor(r, g, b, 1)
    if addon.VignetteRadarControls then
        addon.VignetteRadarControls.RefreshPopupSurface(panel)
        addon.VignetteRadarControls.RefreshPopupSurface(panel.transfer)
    end
    for _, kind in ipairs(CANDIDATE_KINDS) do
        local list, row = candidates[kind], panel.candidateRows[kind]
        local selected = list[cursor[kind]]
        row.name:SetText(selected and (selected.name .. "  (" .. cursor[kind] .. "/" .. #list .. ")")
            or "No current " .. kind .. " goals")
        row.prev:SetEnabled(#list > 1)
        row.next:SetEnabled(#list > 1)
        row.add:SetEnabled(selected ~= nil)
    end
    local count = draft and #draft.goals or 0
    local pages = math.max(1, math.ceil(count / PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    panel.routeHeader:SetText("Draft Goals  (" .. count .. "/64)")
    panel.pageLabel:SetText(page .. " / " .. pages)
    panel.pagePrev:SetEnabled(page > 1)
    panel.pageNext:SetEnabled(page < pages)
    for index, row in ipairs(panel.rows) do
        local goalIndex = (page - 1) * PAGE_SIZE + index
        local goal = draft and draft.goals[goalIndex]
        row.goalID = goal and goal.id or nil
        row.goalName = goal and goal.name or nil
        row.reason = nil
        row:SetShown(goal ~= nil)
        if goal then
            local state, reason = Engine().Status(draft, goal.id)
            row.name:SetText(goalIndex .. ". " .. goal.name .. "  [" .. state .. "]")
            row.up:SetEnabled(goalIndex > 1)
            row.down:SetEnabled(goalIndex < count)
            row.lock:SetText(draft.lockedID == goal.id and "Unlock" or "Lock")
            row.lock:SetEnabled(state ~= "complete" and state ~= "skipped")
            row.skip:SetEnabled(state ~= "complete" and state ~= "skipped")
            row.reason = reason
        end
    end
    local now, nextStop, reason = API.Preview()
    panel.now:SetText(now and ("Now: " .. now.name .. " - " .. (now.reason or "Available"))
        or ("Now: " .. (reason or "No mapped stop on this map")))
    panel.next:SetText(nextStop and ("Next: " .. nextStop.name .. " - "
        .. (nextStop.reason or "Available")) or "Next: No available stop")
    panel.message:SetText(message)
    panel.pause:SetText(draft and draft.paused and "Resume" or "Pause")
    panel.pause:SetEnabled(draft ~= nil)
    panel.apply:SetEnabled(draft ~= nil or API.GetActive() ~= nil)
    panel.export:SetEnabled(draft ~= nil)
end

function API.Open()
    local ui = EnsureUI()
    if not ui then return false, "UI unavailable" end
    API.LoadDraft()
    ui:Show()
    if card then card:Hide() end
    API.Refresh()
    return true
end

function API.Close()
    if panel then panel.transfer:Hide(); panel:Hide() end
    draft = nil
    API.RefreshCard()
end

function API.Toggle()
    if panel and panel:IsShown() then API.Close(); return false end
    return API.Open()
end

function API.IsOpen()
    return panel and panel:IsShown() or false
end

return API
