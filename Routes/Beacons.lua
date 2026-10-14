local _, addon = ...
if type(addon) ~= "table" then return end

-- A screen-space bearing display. WoW exposes one world-anchored navigation
-- frame, so these markers deliberately form a compass instead of pretending
-- that arbitrary map positions are projected into the 3D scene.
-- The Bearing Bar is the card view of the Compass system: its points come
-- from the shared Compass feed (Core/Compass.lua, also read by the Horizon
-- Ribbon); this file only picks, lays out and draws them. Names wrap (two
-- lines, else a wider card) and cards in a row never overlap.
local API = {}
addon.VignetteRadarBeacons = API

local PI, TWO_PI = math.pi, math.pi * 2
local SURFACE = "Interface\\AddOns\\Magpie\\Media\\beacon-surface.tga"
local BORDER = "Interface\\AddOns\\Magpie\\Media\\beacon-border.tga"
local QUEST = "Interface\\AddOns\\Magpie\\Media\\quest-diamond.tga"
local QUEST_HOLLOW = "Interface\\AddOns\\Magpie\\Media\\quest-diamond-hollow.tga"
local WIDTH, HEIGHT, BINS, CARD_W, ROWS = 520, 146, 19, 104, 4
-- Card text: x inside the card, base width, widest a long name may make it;
-- the first row's top and the gap between rows and between cards.
local TEXT_X, TEXT_W, TEXT_MAX, TOP, ROW_GAP, CARD_GAP = 20, CARD_W - 21, 150, 31, 3, 3
-- Pixels from the centre to the edge of the bearing scale (+-180 degrees).
local SPAN = 209
local candidates, frame, cards = {}, nil, {}
local bins = {}
local lastRight, rowHeight, rowTop, placed = {}, {}, {}, {}
-- name -> { width, height, textWidth } in the card font; cleared when big.
local sizes, sizeCount = {}, 0
local lastMapID, lastPlayer
local preview = false
local previewSaved
local paused, slowUpdates = false, 0
-- Render runs several times a second: its lookup tables are built once.
local SUMMARY_KINDS = { { "rare", "Rare" }, { "treasure", "Loot" },
    { "entrance", "Cave" }, { "quest", "Quest" } }
local kindCounts, summaryParts = {}, {}

local function Pause(reason)
    if paused then return end
    paused = true
    if frame then frame:SetScript("OnUpdate", nil); frame:Hide() end
    local message = "Magpie: Bearing Bar paused for this session (" .. reason
        .. "). /reload retries them."
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    elseif print then print(message) end
end

local Number = addon.Secret.Number

local function Compass() return addon.VignetteRadarCompass end

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("compass", fmt, ...) end
end

local function StyleColor(slot)
    local style = addon.VignetteRadarStyle
    if style and type(style.Color) == "function" then
        local ok, r, g, b = pcall(style.Color, slot)
        if ok and Number(r) and Number(g) and Number(b) then return r, g, b end
    end
    return .65, .85, .95
end

-- Shift-click pins the card's spot even while World Focus is off. It goes
-- through Focus, so World Focus places (and later clears) the waypoint.
local function NavigateToPoint(item)
    local raw = item and item.raw
    if not raw then return end
    local focus = addon.VignetteRadarFocus
    focus.Select(focus.Point({ kind = item.kind, key = raw.key, questID = raw.questID,
        name = item.name, mapID = item.mapID, mapX = raw.mapX, mapY = raw.mapY,
        worldX = raw.worldX, worldY = raw.worldY, instanceID = raw.instanceID }),
        { source = "beacons", direct = true })
end

local function RefreshTheme()
    if not frame then return end
    local ar, ag, ab = StyleColor("accent")
    local br, bg, bb = StyleColor("background")
    frame.background:SetVertexColor(br, bg, bb, .96)
    frame.border:SetVertexColor(ar, ag, ab, .72)
    frame.heading:SetTextColor(ar, ag, ab, 1)
    frame.center:SetColorTexture(ar, ag, ab, .65)
    frame.axis:SetColorTexture(ar, ag, ab, .16)
end

local function SavePosition()
    if not frame or not UIParent then return end
    local scale = frame:GetScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (Number(scale) and Number(left) and Number(top) and scale > 0) then return end
    addon.GetSettings().vignetteRadarBeaconPosition = {
        x = (left + WIDTH / 2) * scale - UIParent:GetWidth() / 2,
        y = top * scale - UIParent:GetHeight(),
    }
end

local function MakeCard(index)
    local card = CreateFrame("Button", nil, frame)
    card:SetSize(CARD_W, 25)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetFrameLevel(frame:GetFrameLevel() + 1)
    card.icon = card:CreateTexture(nil, "OVERLAY")
    card.icon:SetSize(18, 18)
    card.icon:SetPoint("LEFT", card, "LEFT", 0, 0)
    -- The diamond's letter or quest number (Points.Icon), white on black outline.
    card.badge = card:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(card.badge, 9, "OUTLINE")
    card.badge:SetPoint("CENTER", card.icon, "CENTER", 0, 0)
    card.badge:SetTextColor(1, 1, 1, 1)
    card.label = card:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(card.label, 8, "OUTLINE")
    card.label:SetPoint("TOPLEFT", card, "TOPLEFT", TEXT_X, -1)
    card.label:SetWidth(TEXT_W)
    card.label:SetJustifyH("LEFT")
    card.label:SetJustifyV("TOP")
    -- Width only, never a line cap: a long name wraps, it is never cut.
    card.label:SetWordWrap(true)
    card.distance = card:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(card.distance, 8, "OUTLINE")
    card.distance:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 1)
    card.distance:SetTextColor(.73, .78, .81, .9)
    card.count = card:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(card.count, 8, "OUTLINE")
    card.count:SetPoint("TOPRIGHT", card.icon, "TOPRIGHT", 3, 3)
    card.count:SetTextColor(1, 1, 1, 1)
    card.focusLine = card:CreateTexture(nil, "OVERLAY")
    card.focusLine:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 20, 0)
    card.focusLine:SetSize(CARD_W - 20, 1)
    card.focusLine:Hide()
    card:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        for n = 1, math.min(self.groupCount or 0, 8) do
            local item = self.group[n]
            local r, g, b = item.r, item.g, item.b
            GameTooltip:AddLine((n == self.groupIndex and "› " or "  ")
                .. item.name .. (item.favorite and " · Favorite" or "")
                .. (item.focused and " · Current Waypoint" or "")
                .. "  ·  " .. math.floor(item.distance + .5) .. " yd", r, g, b)
        end
        if (self.groupCount or 0) > 8 then
            GameTooltip:AddLine("+" .. (self.groupCount - 8) .. " More Nearby", .7, .8, .83)
        end
        GameTooltip:AddLine("Click to Focus · Shift-Click for a Waypoint"
            .. ((self.groupCount or 0) > 1 and " · Right-Click to Choose" or ""),
            .66, .76, .8)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    card:SetScript("OnClick", function(self, button)
        if button == "RightButton" and (self.groupCount or 0) > 1 then
            self.groupIndex = (self.groupIndex or 1) % self.groupCount + 1
            API.Render()
            if GameTooltip then self:GetScript("OnEnter")(self) end
            return
        end
        local item = self.group and self.group[self.groupIndex or 1]
        if not item or preview then return end
        local shift = IsShiftKeyDown and IsShiftKeyDown()
        if shift then NavigateToPoint(item); return end
        local focus = addon.VignetteRadarFocus
        if item.kind == "quest" then
            -- FocusQuest toggles the shared quest focus and refreshes the quest views.
            local exploration = addon.VignetteRadarExploration
            if exploration and exploration.FocusQuest then exploration.FocusQuest(item.raw.questID)
            else focus.Toggle(focus.Quest(item.raw.questID), { source = "beacons" }) end
        elseif item.source == "live" and addon.HandleVignetteClick then
            addon.HandleVignetteClick(item.raw, button)
        elseif item.source == "note" then
            local entry = focus.Note(item.raw)
            -- With World Focus off the note is still pinned directly.
            if not focus.Select(entry, { source = "beacons" }) then
                focus.Select(entry, { source = "beacons", direct = true })
            end
        end
    end)
    card:Hide()
    cards[index] = card
    return card
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "VignetteRadarBeaconRail", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    local saved = addon.GetSettings().vignetteRadarBeaconPosition
    frame:SetPoint("TOP", UIParent, "TOP",
        type(saved) == "table" and Number(saved.x) or 0,
        type(saved) == "table" and Number(saved.y) or -84)
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetTexture(SURFACE)
    frame.border = frame:CreateTexture(nil, "BORDER")
    frame.border:SetAllPoints()
    frame.border:SetTexture(BORDER)
    frame.heading = frame:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(frame.heading, 10, "OUTLINE")
    frame.heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -8)
    frame.heading:SetText("Bearing Bar")
    frame.summary = frame:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(frame.summary, 9, "OUTLINE")
    frame.summary:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -9)
    frame.summary:SetWidth(375)
    frame.summary:SetJustifyH("RIGHT")
    frame.summary:SetWordWrap(false)
    frame.summary:SetTextColor(.73, .78, .81, .95)
    frame.empty = frame:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(frame.empty, 10, "OUTLINE")
    frame.empty:SetPoint("TOP", frame, "TOP", 0, -42)
    frame.empty:SetTextColor(.73, .78, .81, .9)
    frame.empty:Hide()
    frame.axis = frame:CreateTexture(nil, "ARTWORK")
    frame.axis:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -27)
    frame.axis:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -27)
    frame.axis:SetHeight(1)
    frame.center = frame:CreateTexture(nil, "ARTWORK")
    frame.center:SetSize(2, 11)
    frame.center:SetPoint("TOP", frame, "TOP", 0, -23)
    -- Hidden measures for card names: one line, and wrapped at a width.
    local style = addon.VignetteRadarStyle
    frame.ruler = frame:CreateFontString(nil, "OVERLAY")
    style.SetFont(frame.ruler, 8, "OUTLINE")
    frame.ruler:SetWordWrap(false)
    frame.ruler:Hide()
    frame.wrapRuler = frame:CreateFontString(nil, "OVERLAY")
    style.SetFont(frame.wrapRuler, 8, "OUTLINE")
    frame.wrapRuler:SetWordWrap(true)
    frame.wrapRuler:SetJustifyH("LEFT")
    frame.wrapRuler:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.wrapRuler:Hide()
    local distanceRuler = frame:CreateFontString(nil, "OVERLAY")
    style.SetFont(distanceRuler, 8, "OUTLINE")
    distanceRuler:SetText("000 yd")
    distanceRuler:Hide()
    frame.distanceHeight = style.TextHeight(distanceRuler, CARD_W)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    frame.update = function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        -- Cards slide with the camera every frame; the full layout (grouping,
        -- rows, text) runs on the slower interval.
        if self.elapsed < (self.interval or .2) then API.Place(); return end
        self.elapsed = 0
        local started = type(debugprofilestop) == "function" and debugprofilestop() or nil
        local ok = pcall(API.Render)
        if not ok then Pause("display error"); return end
        if started then
            local elapsedMS = debugprofilestop() - started
            slowUpdates = elapsedMS > 20 and slowUpdates + 1 or 0
            if elapsedMS > 100 or slowUpdates >= 3 then Pause("slow updates") end
        end
    end
    RefreshTheme()
    frame:Hide()
    return frame
end

-- Which feed points the bar shows: the kinds switched on in its settings,
-- within range, live ones only while the radar shows them ("Quests Here
-- Only" keeps the quests whose area you stand in), most important first,
-- at most vignetteRadarBeaconMax. The points come from Core/Compass.lua.
function API.Select(feed, db, visible)
    db = db or addon.GetSettings()
    local range = math.max(150, math.min(2400, Number(db.vignetteRadarBeaconRange) or 1200))
    local range2, list = range * range, {}
    for _, entry in ipairs(feed and feed.points or {}) do
        local kind = entry.kind
        local wanted = kind == "rare" and db.vignetteRadarBeaconRares
            or (kind == "treasure" or kind == "entrance") and db.vignetteRadarBeaconTreasures
            or kind == "quest" and db.vignetteRadarBeaconQuests and (not feed.anyHere or entry.here)
        if wanted and entry.distance2 <= range2
            and (entry.source ~= "live" or not visible or visible(entry.raw)) then
            list[#list + 1] = entry
        end
    end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.distance2 < b.distance2
    end)
    local max = math.max(4, math.min(24, Number(db.vignetteRadarBeaconMax) or 8))
    while #list > max do list[#list] = nil end
    return list
end

-- The bar's points from raw lists instead of the current scan (tests, and
-- callers outside the scan): the same Compass feed rules, then Select.
function API.BuildCandidates(mapID, player, targets, quests, notes, visible, db)
    db = db or addon.GetSettings()
    if not (mapID and player and Number(player.worldX) and Number(player.worldY)) then
        return {}
    end
    local feed = Compass().Build({ mapID = mapID, player = player },
        { live = targets, quest = quests, saved = notes }, db)
    return API.Select(feed, db, visible)
end

-- The scan (UI/Radar.lua) calls Sync right after Points.Publish with the
-- same lists, so the shared Compass feed already holds them; other lists
-- (tests, previews) get a feed of their own.
local function ScanCandidates(db, mapID, player, targets, quests, notes, visible)
    local points = addon.VignetteRadarPoints
    if targets == points.Refs("live") and quests == points.Refs("quest") and notes == points.Refs("saved") then
        return API.Select(Compass().Feed(), db, visible)
    end
    return API.BuildCandidates(mapID, player, targets, quests, notes, visible, db)
end

function API.Sync(mapID, player, targets, quests, notes, visible)
    if preview or paused then return end
    local db = addon.GetSettings()
    if not (db.vignetteRadarBeaconsEnabled and db.vignetteRadarEnabled) then
        candidates, lastMapID, lastPlayer = {}, nil, nil
        if frame then frame:SetScript("OnUpdate", nil); frame:Hide() end
        return
    end
    if not (mapID and player and Number(player.worldX) and Number(player.worldY)) then
        candidates, lastMapID, lastPlayer = {}, nil, nil
        EnsureFrame():SetHeight(64)
        frame:SetScript("OnUpdate", nil)
        frame:Show()
        local ok = pcall(API.Render)
        if not ok then Pause("display error") end
        return
    end
    local ok, list = pcall(ScanCandidates, db, mapID, player, targets, quests, notes, visible)
    if not ok then Pause("scan error"); return end
    if #list ~= #candidates then Log("bar: %d points", #list) end
    candidates, lastMapID, lastPlayer = list, mapID, player
    EnsureFrame():SetHeight(#list > 0 and HEIGHT or 64)
    local mode = db.vignetteRadarPerformance
    frame.interval = mode == "low" and .4 or mode == "balanced" and .3 or .2
    frame:SetScript("OnUpdate", #list > 0 and frame.update or nil)
    frame:Show()
    RefreshTheme()
    ok = pcall(API.Render)
    if not ok then Pause("display error") end
end

local function Facing() return Compass().Facing() end

-- Card x for a world heading: the bar spans 360 degrees, ahead in the middle.
local function CardX(heading, facing)
    return -Compass().Relative(heading, facing) / PI * SPAN
end

-- A card's size for its name: one line in the base width, else two lines
-- at the best word split, else wider (up to TEXT_MAX), else more lines.
-- Never "...". Cached per name.
local function CardSize(name)
    local size = sizes[name]
    if size then return size end
    local style = addon.VignetteRadarStyle
    local one, two = style.LineWidths(frame.ruler, name)
    local textWidth = TEXT_W
    if one + 3 > TEXT_W and two + 3 > TEXT_W then textWidth = math.min(TEXT_MAX, math.ceil(two) + 3) end
    local ruler = frame.wrapRuler
    ruler:SetWidth(textWidth)
    ruler:SetText(name)
    local labelHeight = style.TextHeight(ruler, textWidth)
    size = { width = TEXT_X + textWidth + 1, height = math.max(25, labelHeight + frame.distanceHeight + 3),
        textWidth = textWidth }
    if sizeCount >= 200 then sizes, sizeCount = {}, 0 end
    sizes[name], sizeCount = size, sizeCount + 1
    return size
end

local function Heading(item, player)
    return item.heading or Compass().Heading(player, item)
end

-- The point a bin's card shows: the one picked with right-click while the
-- bin keeps its first point, else the focused one, else the first.
local function GroupChoice(card, bin, groupKey)
    if card and card.groupKey == groupKey then return math.min(card.groupIndex or 1, #bin) end
    for position, candidate in ipairs(bin) do
        if candidate.focused then return position end
    end
    return 1
end

local function Paint(card, item, bin, points)
    card.group, card.groupCount = bin, #bin
    -- Only changed parts are pushed to the card's regions. Blizzard's icon
    -- for the point (Points.Icon); diamonds keep the kind or quest colour,
    -- atlases keep their own.
    local raw = item.raw
    local source = points.Kind(raw) and raw or item
    local icon = points.Icon(source)
    local colorChanged = card.shownR ~= item.r or card.shownG ~= item.g or card.shownB ~= item.b
    if card.shownIcon ~= icon then
        card.shownIcon = icon
        local diamond = item.kind == "quest" and not item.completed and QUEST_HOLLOW or QUEST
        card.appliedIcon = points.ApplyIcon(card.icon, icon, source, diamond)
        card.badge:SetText(card.appliedIcon.diamond and card.appliedIcon.label or "")
        colorChanged = true
    end
    if colorChanged then
        card.shownR, card.shownG, card.shownB = item.r, item.g, item.b
        local applied = card.appliedIcon
        local tint = applied.color
        if applied.diamond then card.icon:SetVertexColor(item.r, item.g, item.b, 1)
        else card.icon:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1,
            tint and tint[3] or 1, 1) end
        card.label:SetTextColor(item.r, item.g, item.b, 1)
        card.shownFocusColor = nil
    end
    if card.shownName ~= item.name then
        local size = CardSize(item.name)
        card.shownName = item.name
        card.label:SetWidth(size.textWidth)
        card.label:SetText(item.name)
        card:SetSize(size.width, size.height)
        card.focusLine:SetSize(size.width - TEXT_X, 1)
    end
    local yards = math.floor(item.distance + .5)
    if card.shownYards ~= yards then
        card.shownYards = yards
        card.distance:SetText(yards .. " yd")
    end
    card.focusLine:SetShown(item.focused == true)
    if item.focused and not card.shownFocusColor then
        card.shownFocusColor = true
        card.focusLine:SetColorTexture(item.r, item.g, item.b, .8)
    end
    local extra = #bin - 1
    if card.shownExtra ~= extra then
        card.shownExtra = extra
        card.count:SetText(extra > 0 and ("+" .. extra) or "")
    end
end

local function ShowEmpty(summary, empty)
    frame.summaryText = nil
    frame.summary:SetText(summary)
    frame.empty:SetText(empty)
    frame.empty:Show()
    for _, card in ipairs(cards) do card:Hide() end
end

-- Sorts the candidates into bearing bins and writes the summary line.
local function Bin(player, facing)
    for index = 1, BINS do
        local bin = bins[index]
        if not bin then bin = {}; bins[index] = bin end
        for j = #bin, 1, -1 do bin[j] = nil end
    end
    local kinds = kindCounts
    kinds.rare, kinds.treasure, kinds.entrance, kinds.quest = 0, 0, 0, 0
    for _, item in ipairs(candidates) do
        local heading = Heading(item, player)
        if heading then
            local angle = Compass().Relative(heading, facing)
            local index = math.max(1, math.min(BINS, math.floor((angle + PI) / TWO_PI * BINS) + 1))
            local bin = bins[index]
            bin[#bin + 1] = item
            kinds[item.kind] = (kinds[item.kind] or 0) + 1
        end
    end
    local summary = summaryParts
    for index = #summary, 1, -1 do summary[index] = nil end
    for index = 1, #SUMMARY_KINDS do
        local entry = SUMMARY_KINDS[index]
        local amount = kinds[entry[1]]
        if amount > 0 then summary[#summary + 1] = amount .. " " .. entry[2]
            .. (amount > 1 and entry[1] ~= "treasure" and "s" or "") end
    end
    local summaryText = table.concat(summary, "  ·  ") .. "  ·  Facing"
    if frame.summaryText ~= summaryText then
        frame.summaryText = summaryText
        frame.summary:SetText(summaryText)
    end
end

function API.Render()
    if not (frame and frame:IsShown()) then return end
    local points = addon.VignetteRadarPoints
    local player = lastPlayer
    local facing = Facing()
    if not (player and lastMapID) then
        return ShowEmpty("Position Unavailable", "Waiting for Map Position")
    end
    if not facing then
        return ShowEmpty("Heading Unavailable", "Waiting for Player Heading")
    end
    if #candidates == 0 then
        local db = addon.GetSettings()
        return ShowEmpty("0 Points in " .. db.vignetteRadarBeaconRange .. " yd",
            (db.vignetteRadarBeaconRares or db.vignetteRadarBeaconTreasures
                or db.vignetteRadarBeaconQuests) and "No Markers in Range" or "Choose Marker Types in Settings")
    end
    frame.empty:Hide()
    Bin(player, facing)
    for row = 1, ROWS do lastRight[row], rowHeight[row] = -math.huge, 0 end
    local shown = 0
    -- Left to right. Each card sits at its own point's exact bearing (turning
    -- never snaps it to a bin) and takes the first row where it clears the
    -- card before it; with no room in any row the bin is left out.
    for index = BINS, 1, -1 do
        local bin = bins[index]
        if #bin > 0 then
            local first = bin[1]
            local groupKey = tostring(first.raw and (first.raw.key or first.raw.questID)
                or first.name) .. ":" .. tostring(first.mapID)
            local groupIndex = GroupChoice(cards[shown + 1], bin, groupKey)
            local item = bin[groupIndex]
            local size = CardSize(item.name)
            local heading = Heading(item, player)
            local x = CardX(heading, facing)
            local left = x - size.width / 2
            local row
            for r = 1, ROWS do
                if left - lastRight[r] >= CARD_GAP then row = r; break end
            end
            if row then
                lastRight[row] = left + size.width
                rowHeight[row] = math.max(rowHeight[row], size.height)
                shown = shown + 1
                local card = cards[shown] or MakeCard(shown)
                card.groupKey, card.groupIndex = groupKey, groupIndex
                Paint(card, item, bin, points)
                card.bearing, card.shownX, card.row = heading, x, row
                placed[shown] = card
            end
        end
    end
    -- Rows stack under each other by their tallest card; the bar grows (it
    -- never shrinks below its own height) so every card stays inside it.
    local y = TOP
    for row = 1, ROWS do
        rowTop[row] = y
        if rowHeight[row] > 0 then y = y + rowHeight[row] + ROW_GAP end
    end
    for index = 1, shown do
        local card = placed[index]
        card.shownY = -rowTop[card.row]
        card:ClearAllPoints()
        card:SetPoint("TOP", frame, "TOP", card.shownX, card.shownY)
        card:Show()
    end
    for index = shown + 1, #cards do cards[index]:Hide() end
    local height = math.max(HEIGHT, y + 6)
    if frame:GetHeight() ~= height then frame:SetHeight(height) end
end

-- Per-frame slide: only the facing is read, and a card moves only when it
-- would shift by half a pixel or more. Cards turn together, so a row keeps
-- its spacing; a card wrapping round behind you asks for a fresh layout.
function API.Place()
    if not (frame and frame:IsShown()) then return end
    local facing = Facing()
    if not facing then return end
    for index = 1, #cards do
        local card = cards[index]
        if card.bearing and card:IsShown() then
            local x = CardX(card.bearing, facing)
            local shift = math.abs(x - (card.shownX or x + 1))
            if shift > SPAN then
                frame.elapsed = math.huge
                return
            end
            if shift >= .5 then
                card.shownX = x
                card:SetPoint("TOP", frame, "TOP", x, card.shownY)
            end
        end
    end
end

function API.Preview(value)
    if paused then return end
    if value ~= true then
        preview = false
        if previewSaved then
            candidates, lastMapID, lastPlayer =
                previewSaved.candidates, previewSaved.mapID, previewSaved.player
            previewSaved = nil
        end
        if frame then
            frame:SetHeight(#candidates > 0 and HEIGHT or 64)
            local db = addon.GetSettings()
            frame:SetScript("OnUpdate", #candidates > 0 and db.vignetteRadarBeaconsEnabled
                and db.vignetteRadarEnabled and frame.update or nil)
            frame:SetShown(db.vignetteRadarBeaconsEnabled and db.vignetteRadarEnabled)
            API.Render()
        end
        return
    end
    if not preview then
        previewSaved = { candidates = candidates, mapID = lastMapID, player = lastPlayer }
    end
    preview = true
    local demo = {
        { kind = "rare", name = "Sample Rare", worldX = 100, worldY = 20,
            distance = 102, r = 1, g = .55, b = .35, priority = 2, raw = {} },
        { kind = "quest", name = "Quest Objective", worldX = 120, worldY = -35,
            distance = 125, r = .46, g = .80, b = 1, priority = 3, raw = {} },
    }
    candidates, lastMapID, lastPlayer = demo, 1, { worldX = 0, worldY = 0 }
    EnsureFrame():SetHeight(HEIGHT)
    frame.interval = frame.interval or .2
    frame:SetScript("OnUpdate", frame.update)
    frame:Show()
    API.Render()
end

function API.IsAvailable() return type(CreateFrame) == "function" end
