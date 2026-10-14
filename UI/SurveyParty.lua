local _, addon = ...
if type(addon) ~= "table" then return end

local API = {}
addon.VignetteRadarSurveyParty = API

local WIDTH, HEIGHT = 400, 488
local CELL_SIZES = { .02, .025, .05 }
local RECEIVE = { "off", "party", "raid" }
local panel, activePage, statusMessage, replayPage = nil, "Survey", nil, 1
local shareSighting, shareStop

local function Settings()
    return type(addon.GetSettings) == "function" and addon.GetSettings() or {}
end

local function Survey()
    return addon.VignetteRadarSurveyReplay
end

local function Party()
    return addon.VignetteRadarFeatureRuntime
end

local function Controls()
    return addon.VignetteRadarControls
end

local function Accent()
    local style = addon.VignetteRadarStyle
    if style and type(style.Color) == "function" then
        return style.Color("accent")
    end
    return .20, .80, .72
end

local function Label(parent, title, size, x, y, width, color)
    local label = parent:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(label, size or 11, "")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetSize(width or (WIDTH - x - 14), size + 7)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(title)
    if color then label:SetTextColor(color[1], color[2], color[3], 1)
    else label:SetTextColor(.81, .89, .90, 1) end
    return label
end

local function Notify(message)
    statusMessage = message
    API.Refresh()
end

local function Configure()
    local runtime = Party()
    if runtime and type(runtime.Configure) == "function" then
        runtime.Configure()
    end
    API.Refresh()
end

local function Button(parent, title, x, y, width, callback)
    local button = Controls().Button(parent, title, width, 25)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetScript("OnClick", callback)
    return button
end

local function Choice(button, selected)
    if selected then button:LockHighlight() else button:UnlockHighlight() end
end

local function Toggle(parent, title, x, y, key, change, getter)
    local checkbox = Controls().Checkbox(parent)
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local label = Label(parent, title, 11, x + 32, y - 4, WIDTH - x - 48)
    local hit = CreateFrame("Button", nil, parent)
    hit:SetSize(WIDTH - x - 35, 26)
    hit:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 30, y)
    local function Flip()
        local db = Settings()
        local current = key and db[key] or (getter and getter())
        local value = not (current == true)
        if key then db[key] = value end
        checkbox:SetChecked(value)
        if change then change(value) else Configure() end
    end
    checkbox:SetScript("OnClick", function(self)
        local value = self:GetChecked() == true or self:GetChecked() == 1
        if key then Settings()[key] = value end
        if change then change(value) else Configure() end
    end)
    hit:SetScript("OnClick", Flip)
    return checkbox, label
end

local function PartySettings()
    local db = Settings()
    if type(db.vignetteRadarPartyHunt) ~= "table" then
        db.vignetteRadarPartyHunt = {
            receive = "off", shareSightings = false, shareStop = false, ignored = {},
        }
    end
    local settings = db.vignetteRadarPartyHunt
    if type(settings.ignored) ~= "table" then settings.ignored = {} end
    return settings
end

local function CurrentMap()
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and type(mapID) == "number" then return mapID end
    end
end

local function OpenAtlas(mapID, entries, success)
    local atlas = addon.VignetteRadarAtlas
    if not (atlas and type(atlas.SetData) == "function"
        and type(atlas.Open) == "function") then
        Notify("Atlas Is Unavailable")
        return false
    end
    if WorldMapFrame and type(WorldMapFrame.SetMapID) == "function" then
        pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID)
    end
    atlas.SetData(mapID, entries)
    local ok = atlas.Open()
    if ok and panel then panel:Hide() end
    Notify(ok and success or "Atlas Could Not Open")
    return ok
end

function API.ViewCoverage()
    local survey, mapID = Survey(), CurrentMap()
    if not (survey and mapID and type(survey.GetCoverage) == "function") then
        Notify("Current Map Coverage Is Unavailable")
        return false
    end
    local cells, count = survey.GetCoverage(mapID,
        Settings().vignetteRadarSurveyShared == true)
    if type(cells) ~= "table" or not count or count == 0 then
        Notify("No Visited Ground On This Map")
        return false
    end
    local size = type(survey.GetCellSize) == "function" and survey.GetCellSize()
        or Settings().vignetteRadarSurveyCellSize
    if size ~= .02 and size ~= .025 and size ~= .05 then size = .025 end
    local columns = math.ceil(1 / size)
    local buckets = {}
    -- One 16 x 8 overview snapshot. It is built only for this click, not
    -- refreshed by movement or the radar's update loop.
    for row = 0, columns - 1 do
        for column = 0, columns - 1 do
            if cells[column .. ":" .. row] then
                local x, y = (column + .5)*size, (row + .5)*size
                local slot = math.min(7, math.floor(y*8))*16
                    + math.min(15, math.floor(x*16)) + 1
                local entry = buckets[slot]
                if entry then entry.cellCount = entry.cellCount + 1
                else
                    buckets[slot] = {
                        mapID = mapID, mapX = x, mapY = y,
                        name = "Visited Ground", title = "Observed Survey Coverage",
                        source = "survey", evidence = "observed",
                        coverage = true, cellCount = 1,
                    }
                end
            end
        end
    end
    local entries = {}
    for slot = 1, 128 do
        local entry = buckets[slot]
        if entry then
            entry.name = entry.cellCount == 1 and "Visited Ground"
                or ("Visited Ground (" .. entry.cellCount .. " Cells)")
            entries[#entries+1] = entry
        end
    end
    if #entries == 0 then
        Notify("No Visited Ground On This Map")
        return false
    end
    return OpenAtlas(mapID, entries,
        "Viewing " .. #entries .. " Observed Coverage Areas")
end

local function ViewEvents(events, title)
    if type(events) ~= "table" or #events == 0 then
        return Notify("No Signals To View")
    end
    local mapID = CurrentMap()
    local anyCurrent = false
    local first = math.max(1, #events - 127)
    for index = first, #events do
        local point = events[index] and events[index].point
        if point and point.mapID == mapID then anyCurrent = true; break end
    end
    if not anyCurrent then
        for index = #events, 1, -1 do
            local point = events[index] and events[index].point
            if point and type(point.mapID) == "number" then
                mapID = point.mapID
                break
            end
        end
    end
    local entries = {}
    for index = first, #events do
        local event = events[index]
        local point = event and event.point
        if point and point.mapID == mapID
            and type(point.mapX) == "number" and type(point.mapY) == "number" then
            entries[#entries+1] = {
                mapID = mapID, mapX = point.mapX, mapY = point.mapY,
                name = event.name or event.identity or "Past Signal",
                title = title, source = "replay", evidence = "observed",
                historical = true, at = event.at, kind = event.kind,
            }
        end
    end
    if #entries == 0 then return Notify("No Mapped Signals To View") end
    return OpenAtlas(mapID, entries, "Viewing " .. #entries .. " Past Signals")
end

function API.ViewReplay(index)
    local survey = Survey()
    if not survey then return false end
    if index == nil then
        return ViewEvents(survey.GetTimeline and survey.GetTimeline() or {},
            "Recent Session")
    end
    local saves = survey.GetSavedReplays and survey.GetSavedReplays() or {}
    local replay = saves[index]
    if not replay then return false end
    return ViewEvents(replay.events, replay.name)
end

local function BuildSurvey(page)
    page.header = Label(page, "SURVEY MODE", 13, 14, -8, 330)
    page.surveyBox = Toggle(page, "Record Visited Ground", 14, -43,
        "vignetteRadarSurveying")
    page.sharedBox = Toggle(page, "Show Shared Character Coverage", 14, -80,
        "vignetteRadarSurveyShared")
    Label(page, "Coverage Cell Size", 11, 16, -125, 320, { .63, .77, .79 })
    page.sizes = {}
    for index, size in ipairs(CELL_SIZES) do
        local title = ({ "Fine", "Balanced", "Coarse" })[index]
        page.sizes[index] = Button(page, title, 14 + (index-1)*125, -150, 118, function()
            Settings().vignetteRadarSurveyCellSize = size
            Configure()
        end)
    end
    page.coverage = Label(page, "Current Map: Coverage Unavailable", 11, 16, -204, 365)
    page.viewCoverage = Button(page, "View Coverage In Atlas", 14, -236, 366, function()
        API.ViewCoverage()
    end)
    Label(page, "Visited cells are observations, not proof of a hidden treasure.",
        9, 16, -285, 370, { .57, .68, .71 })
    page.note = Label(page, "Survey samples only while moving. Teleports do not paint the path.",
        9, 16, -320, 370, { .57, .68, .71 })
end

local function BuildReplay(page)
    page.header = Label(page, "SIGNAL REPLAY", 13, 14, -8, 330)
    page.recordBox = Toggle(page, "Record Session Signals", 14, -43,
        "vignetteRadarReplayRecording")
    page.timeline = Label(page, "Session: 0 Signals", 11, 16, -85, 240)
    page.viewSession = Button(page, "View Session", 277, -80, 103, function()
        API.ViewReplay()
    end)
    page.input = CreateFrame("EditBox", nil, page, "BackdropTemplate")
    page.input:SetSize(257, 27)
    page.input:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -117)
    page.input:SetAutoFocus(false)
    page.input:SetMaxLetters(80)
    addon.VignetteRadarStyle.SetFont(page.input, 11, "")
    page.input:SetTextInsets(8, 8, 0, 0)
    page.input:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    page.input:SetBackdropColor(.025, .035, .043, .9)
    page.input:SetBackdropBorderColor(.35, .49, .52, .5)
    page.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    page.save = Button(page, "Save", 277, -118, 103, function()
        local survey = Survey()
        if not survey then return Notify("Replay Is Unavailable") end
        local name = page.input:GetText()
        if type(name) ~= "string" or not name:match("%S") then
            return Notify("Enter A Replay Name")
        end
        local now = type(GetServerTime) == "function" and GetServerTime()
            or type(time) == "function" and time() or nil
        local ok, reason = survey.SaveReplay(name, now)
        if ok then
            page.input:SetText("")
            replayPage = 1
            Notify("Replay Saved")
        else
            Notify(reason or "Replay Could Not Be Saved")
        end
    end)
    Label(page, "SAVED REPLAYS", 10, 16, -161, 240, { .63, .77, .79 })
    page.saved = {}
    for index = 1, 4 do
        local y = -183 - (index-1)*35
        local row = {}
        row.name = Label(page, "", 10, 18, y - 4, 206)
        row.view = Button(page, "View", 237, y, 57, function()
            API.ViewReplay((replayPage-1)*4 + index)
        end)
        row.delete = Button(page, "Delete", 300, y, 80, function()
            local survey = Survey()
            local position = (replayPage-1)*4 + index
            if survey and survey.DeleteReplay(position) then
                Notify("Replay Deleted")
            end
        end)
        page.saved[index] = row
    end
    page.prev = Button(page, "Previous", 14, -327, 105, function()
        replayPage = math.max(1, replayPage - 1)
        API.Refresh()
    end)
    page.next = Button(page, "Next", 275, -327, 105, function()
        replayPage = math.min(2, replayPage + 1)
        API.Refresh()
    end)
    page.pager = Label(page, "1 / 1", 10, 176, -331, 55)
end

local function BuildParty(page)
    page.header = Label(page, "PARTY HUNT", 13, 14, -8, 330)
    Label(page, "Receive Reports", 11, 16, -41, 320)
    page.receive = {}
    for index, mode in ipairs(RECEIVE) do
        local title = ({ "Off", "Party", "Raid" })[index]
        page.receive[index] = Button(page, title, 14 + (index-1)*125, -65, 118, function()
            PartySettings().receive = mode
            Configure()
        end)
    end
    page.sightingBox = Toggle(page, "Allow Sharing Sightings", 14, -106,
        nil, function(value)
            PartySettings().shareSightings = value
            Configure()
        end, function() return PartySettings().shareSightings end)
    page.stopBox = Toggle(page, "Allow Sharing Chosen Stop", 14, -143,
        nil, function(value)
            PartySettings().shareStop = value
            Configure()
        end, function() return PartySettings().shareStop end)
    page.shareSighting = Button(page, "Share Sighting", 14, -187, 177, function()
        local runtime = Party()
        if not runtime or type(runtime.ShareSighting) ~= "function" then
            return Notify("Party Hunt Is Unavailable")
        end
        local ok, reason = runtime.ShareSighting(shareSighting, true)
        Notify(ok and "Sighting Shared" or ("Could Not Share: " .. tostring(reason or "Unknown")))
    end)
    page.shareStop = Button(page, "Share Chosen Stop", 203, -187, 177, function()
        local runtime = Party()
        if not runtime or type(runtime.ShareStop) ~= "function" then
            return Notify("Party Hunt Is Unavailable")
        end
        local ok, reason = runtime.ShareStop(shareStop, true)
        Notify(ok and "Stop Shared" or ("Could Not Share: " .. tostring(reason or "Unknown")))
    end)
    Label(page, "GROUP REPORTS - UNVERIFIED", 10, 16, -226, 340, { .63, .77, .79 })
    page.report = {}
    for index = 1, 3 do
        local y = -250 - (index-1)*34
        local row = {}
        row.label = Label(page, "", 10, 17, y - 4, 276)
        row.ignore = Button(page, "Ignore", 302, y, 78, function()
            if not row.sender then return end
            PartySettings().ignored[row.sender:lower()] = true
            Configure()
            Notify("Sender Ignored")
        end)
        page.report[index] = row
    end
    page.note = Label(page, "Reports expire after 90 sec. They never change your route.",
        10, 16, -358, 370, { .57, .68, .71 })
end

local function Build()
    if panel then return panel end
    local controls = Controls()
    if not controls or type(CreateFrame) ~= "function" then return nil end
    panel = CreateFrame("Frame", "VignetteRadarSurveyPartyPanel", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
    })
    panel:SetBackdropColor(0, 0, 0, 0)
    panel:SetBackdropBorderColor(0, 0, 0, 0)
    controls.PopupSurface(panel)
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "VignetteRadarSurveyPartyPanel"
    end
    panel.title = Label(panel, "FIELD INTELLIGENCE", 13, 16, -12, 310)
    panel.close = addon.VignetteRadarIconButton.Create(panel, "close", { size = 20,
        label = "Close", onClick = function() panel:Hide() end })
    panel.close:SetPoint("TOPLEFT", panel, "TOPLEFT", 365, -11)
    panel.tabs, panel.pages = {}, {}
    for index, name in ipairs({ "Survey", "Replay", "Party" }) do
        local tab = Button(panel, name, 14 + (index-1)*125, -44, 118, function()
            activePage = name
            API.Refresh()
        end)
        panel.tabs[name] = tab
        local page = CreateFrame("Frame", nil, panel)
        page:SetSize(WIDTH, 390)
        page:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -75)
        panel.pages[name] = page
    end
    BuildSurvey(panel.pages.Survey)
    BuildReplay(panel.pages.Replay)
    BuildParty(panel.pages.Party)
    panel.status = Label(panel, "", 10, 17, -463, 365, { .63, .77, .79 })
    panel:SetScript("OnShow", API.Refresh)
    panel:Hide()
    return panel
end

function API.SetShareTargets(sighting, stop)
    shareSighting = type(sighting) == "table" and sighting or nil
    shareStop = type(stop) == "table" and stop or nil
    API.Refresh()
end

function API.Refresh()
    if not panel then return false end
    local db, survey, runtime = Settings(), Survey(), Party()
    local partySettings = PartySettings()
    local red, green, blue = Accent()
    panel.title:SetTextColor(red, green, blue, 1)
    if Controls().RefreshPopupSurface then Controls().RefreshPopupSurface(panel) end
    for name, page in pairs(panel.pages) do
        page:SetShown(name == activePage)
        Choice(panel.tabs[name], name == activePage)
        page.header:SetTextColor(red, green, blue, 1)
    end
    local surveyPage = panel.pages.Survey
    surveyPage.surveyBox:SetChecked(db.vignetteRadarSurveying == true)
    surveyPage.sharedBox:SetChecked(db.vignetteRadarSurveyShared == true)
    local cellSize = db.vignetteRadarSurveyCellSize or .025
    for index, size in ipairs(CELL_SIZES) do
        Choice(surveyPage.sizes[index], size == cellSize)
    end
    local mapID = CurrentMap()
    local count, fraction = 0, 0
    if survey and mapID and type(survey.GetCoverage) == "function" then
        count, fraction = select(2, survey.GetCoverage(mapID,
            db.vignetteRadarSurveyShared == true))
    end
    surveyPage.coverage:SetText(mapID and
        string.format("Current Map: %d Cells Visited (%.1f%%)", count or 0, (fraction or 0)*100)
        or "Current Map: Coverage Unavailable")
    surveyPage.viewCoverage:SetEnabled(mapID ~= nil and count > 0)
    local replay = panel.pages.Replay
    replay.recordBox:SetChecked(db.vignetteRadarReplayRecording == true)
    local timeline = survey and survey.GetTimeline and survey.GetTimeline() or {}
    replay.timeline:SetText("Session: " .. #timeline .. " Signals (Recent 30 Min)")
    local saves = survey and survey.GetSavedReplays and survey.GetSavedReplays() or {}
    local pages = math.max(1, math.ceil(#saves / 4))
    replayPage = math.min(replayPage, pages)
    replay.pager:SetText(replayPage .. " / " .. pages)
    replay.prev:SetEnabled(replayPage > 1)
    replay.next:SetEnabled(replayPage < pages)
    for index, row in ipairs(replay.saved) do
        local item = saves[(replayPage-1)*4 + index]
        row.name:SetText(item and item.name or "")
        row.view:SetShown(item ~= nil)
        row.delete:SetShown(item ~= nil)
    end
    local partyPage = panel.pages.Party
    for index, mode in ipairs(RECEIVE) do
        Choice(partyPage.receive[index], partySettings.receive == mode)
    end
    partyPage.sightingBox:SetChecked(partySettings.shareSightings == true)
    partyPage.stopBox:SetChecked(partySettings.shareStop == true)
    partyPage.shareSighting:SetEnabled(shareSighting ~= nil and partySettings.shareSightings == true)
    partyPage.shareStop:SetEnabled(shareStop ~= nil and partySettings.shareStop == true)
    local service = runtime and type(runtime.GetParty) == "function" and runtime.GetParty()
    local reports = service and type(service.GetReports) == "function" and service:GetReports() or {}
    local shown = 0
    for index = #reports, 1, -1 do
        local report = reports[index]
        if report and type(report.sender) == "string"
            and partySettings.ignored[report.sender:lower()] ~= true then
            shown = shown + 1
            if shown > #partyPage.report then break end
            local row = partyPage.report[shown]
            row.sender = report.sender
            row.label:SetText(string.format("%s: %s (%d sec)", report.sender,
                report.name or "Location", math.floor(report.age or 0)))
            row.ignore:SetShown(true)
        end
    end
    for index = shown + 1, #partyPage.report do
        local row = partyPage.report[index]
        row.sender = nil
        row.label:SetText("")
        row.ignore:SetShown(false)
    end
    panel.status:SetText(statusMessage or "")
    return true
end

function API.Open()
    if not Build() then return false, "UI unavailable" end
    panel:Show()
    API.Refresh()
    return true
end

function API.Close()
    if panel then panel:Hide() end
end

function API.Toggle()
    if panel and panel:IsShown() then API.Close(); return false end
    return API.Open()
end

function API.IsOpen() return panel and panel:IsShown() or false end
