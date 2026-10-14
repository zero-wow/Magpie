-- Quest Item Button: picks the focused / route / super-tracked quest's item,
-- sets secure attributes only out of combat, defers changes asked for in
-- combat to PLAYER_REGEN_ENABLED, and hides completed quests' items.
local mock = dofile("tests/ui_mock.lua").Install()
local settings = { vignetteRadarQuestItemButton = true }
local addon = { GetSettings = function() return settings end }
local lockdown = false
_G.InCombatLockdown = function() return lockdown end
local created = {}
local baseCreate = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    assert(not lockdown, "no frames created in combat")
    local frame = baseCreate(kind, name, parent, template)
    frame.template = template
    frame.attributes = {}
    frame.SetAttribute = function(self, key, value)
        assert(not lockdown, "secure attribute set in combat: " .. tostring(key))
        self.attributes[key] = value
    end
    frame.RegisterForClicks = function(self, ...) self.clicks = { ... } end
    created[#created + 1] = frame
    return frame
end
local logIndex = { [500] = 3, [600] = 4 }
local items = { [3] = { "|cff|Hitem:111|h[Lure]|h|r", 111, 2, false }, [4] = { nil, 222, 1, true } }
local complete = {}
local superTracked = 600
_G.C_QuestLog = { GetLogIndexForQuestID = function(id) return logIndex[id] end,
    IsComplete = function(id) return complete[id] == true end }
_G.GetQuestLogSpecialItemInfo = function(index)
    local entry = items[index]
    if not entry then return nil end
    return entry[1], entry[2], entry[3], entry[4]
end
_G.C_SuperTrack = { GetSuperTrackedQuestID = function() return superTracked end }
_G.C_Item = { GetItemIconByID = function(id) return 1000 + id end,
    GetItemCooldown = function() return 0, 0, true end, GetItemCount = function() return 3 end }
_G.IsQuestLogSpecialItemInRange = function() return 1 end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
addon.VignetteRadarStyle = { revision = 1, SetFont = function() return true end, Color = function() return .2, .4, .6 end }
assert(loadfile("UI/QuestItemButton.lua"))("VignetteRadar", addon)
local QuestItem = assert(addon.VignetteRadarQuestItemButton)
local Focus = addon.VignetteRadarFocus
addon.VignetteRadarWorldFocus = { SelectQuest = function() return true end, GetActiveTarget = function() return nil end }

-- No focus: the super-tracked quest's item (complete, but shown when complete).
complete[600] = true
local questID, _, itemID, link = QuestItem.Pick()
assert(questID == 600 and itemID == 222 and link == nil, "super-tracked quest; shown when complete")
assert(QuestItem.Refresh())
local button = assert(QuestItem.GetButton())
assert(button.template == "SecureActionButtonTemplate" and button.attributes.type == "item"
    and button.attributes.item == "item:222" and button.shown, "secure item button")
assert(button.clicks[1] == "AnyUp" and button.clicks[2] == "AnyDown")
assert(button.icon.texture == 1222 and button.count.text == 3)

-- Focusing a quest switches to its item, by link.
Focus.Select(Focus.Quest(500), { project = false })
assert(button.attributes.item == "|cff|Hitem:111|h[Lure]|h|r", "focused quest's item")

-- In combat nothing secure changes; it applies after combat.
lockdown = true
addon.Bus.Emit("PLAYER_REGEN_DISABLED")
Focus.Clear({ project = false })
assert(QuestItem.IsPending() and button.attributes.item == "|cff|Hitem:111|h[Lure]|h|r", "deferred in combat")
QuestItem.Tick() -- cosmetic updates are fine in combat
lockdown = false
addon.Bus.Emit("PLAYER_REGEN_ENABLED")
assert(not QuestItem.IsPending() and button.attributes.item == "item:222", "applied after combat")

-- A complete quest without "show when complete" hides; no quest hides.
complete[500] = true
Focus.Select(Focus.Quest(500), { project = false })
assert(not button.shown, "completed quest item hidden")
superTracked = nil
Focus.Clear({ project = false })
assert(not button.shown and QuestItem.Pick() == nil)

-- Switched off: hidden.
superTracked = 600
settings.vignetteRadarQuestItemButton = false
QuestItem.Refresh()
assert(not button.shown)
assert(mock and #created >= 1)
print("quest_item_button_test ok")
