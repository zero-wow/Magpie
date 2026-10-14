local _, addon = ...
if type(addon) ~= "table" then return end

-- Quest Item Button: one click (or the key bound to it) uses the special
-- item of the quest you are going for: the focused quest, else the Auto
-- Route / World Focus quest, else Blizzard's super-tracked quest. It sits to
-- the left under the radar face, next to the Next 3 Stops Strip.
-- Using a quest item is protected, so this is a SecureActionButtonTemplate
-- (type "item", item = the item link; SECURE_ACTIONS.item ->
-- SecureCmdItemParse -> C_Item.UseItemByName). Its attributes, anchor and
-- visibility change only out of combat; changes asked for in combat wait
-- for PLAYER_REGEN_ENABLED. Cooldown, count and range are cosmetic and
-- update any time.
--   QuestItem.Pick() -> questID, logIndex, itemID, link, charges | nil
--   QuestItem.Refresh() / QuestItem.GetButton()
local QuestItem = {}
addon.VignetteRadarQuestItemButton = QuestItem

local type, pcall = type, pcall
local Number, Text, Call, IsSecret = addon.Secret.Number, addon.Secret.Text, addon.Secret.Call,
    addon.Secret.IsSecret

local NAME, SIZE, TICK = "VignetteRadarQuestItemButton", 30, "VignetteRadarQuestItemButton"
local button
local pending = false
local current = {} -- what the secure attributes hold: questID, itemID, link

local function Settings() return addon.GetSettings() end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("questitem", fmt, ...) end
end

local function Locked()
    if addon.Bus and addon.Bus.InCombat() then return true end
    local lockdown = _G.InCombatLockdown
    if type(lockdown) ~= "function" then return false end
    local ok, value = pcall(lockdown)
    return ok and value == true
end

local function QuestFromFocus()
    local focus = addon.VignetteRadarFocus
    local id = focus and focus.GetQuest()
    if id then return id end
    local world = addon.VignetteRadarWorldFocus
    local active = world and world.GetActiveTarget and world.GetActiveTarget()
    if type(active) == "table" and active.kind == "quest" and Number(active.questID) then return active.questID end
    return Number(Call(C_SuperTrack, "GetSuperTrackedQuestID"))
end

-- The quest and its usable item, or nil. A complete quest keeps its item
-- only when Blizzard says to show it when complete.
function QuestItem.Pick()
    local questID = QuestFromFocus()
    if not questID or questID <= 0 then return nil end
    local logIndex = Number(Call(C_QuestLog, "GetLogIndexForQuestID", questID))
    if not logIndex then return nil end
    -- Four results (Secret.Call keeps three), so call it here, guarded.
    local info = _G.GetQuestLogSpecialItemInfo
    if type(info) ~= "function" then return nil end
    local ok, link, itemID, charges, showWhenComplete = pcall(info, logIndex)
    itemID = ok and Number(itemID) or nil
    if not itemID then return nil end
    if IsSecret(link) then link = nil end
    if IsSecret(charges) then charges = nil end
    if Call(C_QuestLog, "IsComplete", questID) == true and showWhenComplete ~= true then return nil end
    return questID, logIndex, itemID, Text(link), Number(charges)
end

local function ShowTooltip(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local logIndex = current.questID and Number(Call(C_QuestLog, "GetLogIndexForQuestID", current.questID))
    local ok = logIndex and pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, logIndex)
    if not ok and current.itemID then pcall(GameTooltip.SetItemByID, GameTooltip, current.itemID) end
    GameTooltip:Show()
end

local function Ensure()
    if button then return button end
    if Locked() then return nil end
    button = CreateFrame("Button", NAME, UIParent, "SecureActionButtonTemplate")
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("MEDIUM")
    -- The secure handler fires once: on key down or up per ActionButtonUseKeyDown.
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type", "item")
    local controls = addon.VignetteRadarControls
    if controls and controls.RoundedStatusSurface then controls.RoundedStatusSurface(button) end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.count = button:CreateFontString(nil, "OVERLAY")
    addon.VignetteRadarStyle.SetFont(button.count, 9, "OUTLINE")
    button.count:SetPoint("BOTTOMRIGHT", -3, 3)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    button:Hide()
    return button
end

local function Skin()
    local style = addon.VignetteRadarStyle
    local revision = style and style.revision or -1
    if button._styleRevision == revision then return end
    button._styleRevision = revision
    local controls = addon.VignetteRadarControls
    if controls and controls.RefreshRoundedStatusSurface then controls.RefreshRoundedStatusSurface(button) end
    local tray = addon.VignetteRadarTray
    if tray and tray.SkinLikeRadar then tray.SkinLikeRadar(button) end
end

-- Left of the radar face's bottom edge (where the strip docks), else a
-- fixed spot under the screen centre while the radar is closed.
local function Anchor()
    button:ClearAllPoints()
    local tray = addon.VignetteRadarTray
    local face = tray and tray.Face and tray.Face()
    if face then
        button:SetPoint("TOPRIGHT", face, "BOTTOMLEFT", -4, -4)
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

-- Cosmetic, safe in combat: icon tint for range, cooldown sweep, count.
function QuestItem.Tick()
    if not (button and button:IsShown() and current.itemID) then return end
    local start, duration, enabled = Call(C_Item, "GetItemCooldown", current.itemID)
    start, duration = Number(start), Number(duration)
    if start and duration and duration > 0 and enabled ~= false then
        button.cooldown:SetCooldown(start, duration)
    else
        button.cooldown:Clear()
    end
    local count = Number(Call(C_Item, "GetItemCount", current.itemID))
    button.count:SetText(count and count > 1 and count or "")
    local logIndex = Number(Call(C_QuestLog, "GetLogIndexForQuestID", current.questID))
    local inRange = logIndex and Call(_G, "IsQuestLogSpecialItemInRange", logIndex)
    if inRange == 0 or inRange == false then button.icon:SetVertexColor(1, .35, .35, 1)
    else button.icon:SetVertexColor(1, 1, 1, 1) end
end

local function Hide()
    current = {}
    if button and button:IsShown() then button:Hide() end
    if addon.Bus then addon.Bus.Cancel(TICK) end
end

function QuestItem.Refresh()
    if Locked() then
        pending = true
        return false
    end
    pending = false
    if Settings().vignetteRadarQuestItemButton ~= true then Hide(); return true end
    local questID, _, itemID, link = QuestItem.Pick()
    if not itemID then
        if current.itemID then Trace("hide: no quest item") end
        Hide()
        return true
    end
    if not Ensure() then pending = true; return false end
    local value = link or ("item:" .. itemID)
    if current.itemID ~= itemID or current.link ~= value then
        button:SetAttribute("item", value)
        Trace("quest %d item %d", questID, itemID)
    end
    current = { questID = questID, itemID = itemID, link = value }
    local icon = Call(C_Item, "GetItemIconByID", itemID)
    button.icon:SetTexture(icon or 134400)
    Skin()
    Anchor()
    button:Show()
    if addon.Bus then addon.Bus.Every(TICK, .5, QuestItem.Tick) end
    QuestItem.Tick()
    return true
end

function QuestItem.GetButton() return button end
function QuestItem.IsPending() return pending end

local bus = addon.Bus
if bus then
    local function Refresh() QuestItem.Refresh() end
    bus.On("LOGIN", Refresh)
    bus.On("FOCUS_CHANGED", Refresh, { coalesce = true })
    bus.On("QUEST_CHANGED", Refresh, { coalesce = .2 })
    bus.On("SUPERTRACK", Refresh, { coalesce = true })
    -- Lockdown can outlast the event by a moment: retry once a second.
    local function AfterCombat()
        if pending and not QuestItem.Refresh() and C_Timer and C_Timer.After then C_Timer.After(1, AfterCombat) end
    end
    bus.On("PLAYER_REGEN_ENABLED", AfterCombat)
end

return QuestItem
