local corePath = arg[1] or "Core/Core.lua"
local featuresPath = arg[2] or "Core/Features.lua"

VignetteRadarDB, WaffleHouseDB = nil, nil
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile(corePath))("VignetteRadar", addon)
assert(loadfile(featuresPath))("VignetteRadar", addon)
local F, db = addon.VignetteRadarFeatures, addon.GetSettings()
local live = { enabled = true, preview = false }

local function target(key, id, name, category, x)
    return { key = key, vignetteID = id, name = name, category = category or "rare",
        mapID = 1, mapX = x or .2, mapY = .3, worldX = (x or .2) * 1000,
        worldY = 300, instanceID = 42 }
end

local a = target("a", 101, "Alpha")
assert(not F.IsFavorite(a) and not F.IsIgnored(a))
assert(F.ToggleFavorite(a) == true and F.IsFavorite(target("different-guid", 101, "Alpha")),
    "favorite identity must survive GUID changes")
assert(F.ToggleFavorite(a) == false and not F.IsFavorite(a))
assert(F.Ignore(a, false) and F.IsIgnored(a) and db.vignetteRadarIgnored["id:101"] == nil,
    "session ignore must stay out of SavedVariables")
F.ClearIgnored()
assert(not F.IsIgnored(a))
assert(F.Ignore(a, true) and db.vignetteRadarIgnored["id:101"] == true,
    "permanent ignore must be saved")
F.ClearIgnored()

local vendor = target("vendor-a", 301, "Mailbox", "other")
local vendorElsewhere = target("vendor-b", 302, "Mailbox", "other")
vendorElsewhere.mapID = 2
assert(F.SetMarkerNameHidden(vendor, true) and F.IsMarkerNameHidden(vendor)
    and F.IsIgnored(vendorElsewhere)
    and db.vignetteRadarHiddenMarkerNames["other:mailbox"] == "Mailbox",
    "a hidden live marker name must persist and cover matching markers across maps")
assert(F.SetMarkerNameHidden(vendor, false) and not F.IsIgnored(vendorElsewhere),
    "an individual marker name must be restorable without clearing other ignores")
local mailboxNote = { name = "Mailbox", kind = "note" }
assert(not F.IsMapNoteNameHidden(mailboxNote))
F.SetMarkerNameHidden({ name = "Mailbox", category = "map:note" }, true)
assert(F.IsMapNoteNameHidden(mailboxNote)
    and db.vignetteRadarHiddenMarkerNames["map:note:mailbox"] == "Mailbox",
    "saved map notes must support the same per-name visibility controls")
local decorVendor = target("decor-vendor", 401, "First Decor Merchant", "other")
decorVendor.atlasName = "VignetteDecorVendor"
local anotherVendor = target("decor-vendor-2", 402, "Second Decor Merchant", "other")
anotherVendor.atlasName = "VignetteDecorVendor"
assert(F.MarkerTypeKey(decorVendor) == "class:decor-vendors")
anotherVendor.atlasName = "MinimapHousingMerchant"
F.SetMarkerTypeHidden({ typeKey = F.MarkerTypeKey(decorVendor),
    label = "Decor Vendors", atlasName = decorVendor.atlasName }, true)
assert(F.IsMarkerTypeHidden(anotherVendor) and F.IsIgnored(anotherVendor)
    and not F.IsMarkerTypeHidden(vendor),
    "an atlas type filter must hide different names sharing one icon without hiding other icons")
local noteIcon = { name = "A Different Note", kind = "note",
    icon = { texture = 134400, texCoord = { .1, .9, .2, .8 } } }
local noteTypeKey = F.MapNoteTypeKey(noteIcon)
F.SetMarkerTypeHidden({ typeKey = noteTypeKey, label = "Other Note Icon",
    texture = 134400, texCoord = noteIcon.icon.texCoord }, true)
assert(F.IsMapNoteTypeHidden(noteIcon)
    and not F.IsMapNoteTypeHidden(mailboxNote),
    "map-note icon filters must match icon artwork, including sprite coordinates")
F.SetMarkerTypeHidden({ typeKey = noteTypeKey }, false)
assert(not F.IsMapNoteTypeHidden(noteIcon), "map-note icon types must be restorable")
F.SetMarkerNameHidden(vendor, true)
F.ClearIgnored()
assert(not F.IsIgnored(vendor) and next(F.GetHiddenMarkerNames()) == nil
    and next(F.GetHiddenMarkerTypes()) == nil,
    "clearing ignored detections must also restore saved name and icon filters")

local first, alerts = F.Update({ a }, 1, 0, live)
assert(#first == 1 and #alerts == 0, "initial scan must seed silently")
local b = target("b", 102, "Beta", "rare", .4)
local second
second, alerts = F.Update({ a, b }, 1, 1, live)
assert(#second == 2 and #alerts == 1 and alerts[1].key == "b"
    and b.newUntil == 4, "new eligible rare must alert once and pulse")
local bMoved = target("b", 102, "Beta", "rare", .6)
second, alerts = F.Update({ a, bMoved }, 1, 2, live)
assert(#alerts == 0 and bMoved.newUntil == 4, "pulse must persist through rescans")
second = F.Update({ a }, 1, 3, live)
local ghost
for _, item in ipairs(second) do if item.key == "b" then ghost = item end end
assert(ghost and ghost.stale and ghost.lastSeenAt == 2 and ghost.expiresAt == 13
    and ghost.fading == 1 and ghost.mapX == .6, "disappeared target must retain its last coordinates")
assert(F.GetHealth(ghost) == nil and F.Navigate(ghost) == false, "stale sightings are never actionable")
local bReappeared = target("new-guid", 102, "Beta", "rare", .8)
second, alerts = F.Update({ a, bReappeared }, 1, 4, live)
assert(#second == 2 and #alerts == 0, "stable identity must suppress brief GUID churn and old ghost")
second = F.Update({ a }, 1, 5, live)
second = F.Update({ a }, 1, 16, live)
assert(#second == 1, "last-seen snapshot must expire")

local c = target("c", 103, "Gamma")
db.vignetteRadarAlertCategories.rare = false
second, alerts = F.Update({ a, c }, 1, 20, live)
assert(#alerts == 0, "disabled alert category must stay silent")
db.vignetteRadarAlertCategories.rare = true
local d = target("d", 104, "Delta")
InCombatLockdown = function() return true end
assert(F.IsQuiet(), "combat should be quiet by default")
assert(F.IsVisuallyQuiet(), "combat should dim both surfaces by default")
db.vignetteRadarKeepVisibleCombat = true
assert(not F.IsVisuallyQuiet() and F.IsQuiet(),
    "staying visible in combat must not unmute alerts")
db.vignetteRadarKeepVisibleCombat = false
second, alerts = F.Update({ a, c, d }, 1, 21, live)
assert(#alerts == 0, "combat discoveries must stay silent")
InCombatLockdown = function() return false end
second, alerts = F.Update({ a, c, d }, 1, 22, live)
assert(#alerts == 0, "leaving combat must not replay discoveries")
IsInInstance = function() return true end
assert(F.IsQuiet(), "instances should be quiet by default")
db.vignetteRadarKeepVisibleCombat = true
assert(not F.IsVisuallyQuiet() and F.IsQuiet(),
    "stay fully visible must suppress instance fading without unmuting alerts")
InCombatLockdown = function() return true end
assert(not F.IsVisuallyQuiet() and F.IsQuiet(),
    "stay fully visible must suppress both combat and instance fading")
db.vignetteRadarKeepVisibleCombat = false
assert(F.IsVisuallyQuiet(), "turning stay fully visible off must restore fading in combat and instances")
InCombatLockdown = function() return false end
assert(F.IsVisuallyQuiet(), "instance fading must remain when out of combat and stay fully visible is off")
IsInInstance = function() return false end

local e = target("e", 105, "Echo")
db.vignetteRadarCategories = { rare = false }
second, alerts = F.Update({ a, e }, 1, 23, live)
assert(#alerts == 0, "hidden legend categories must not alert")
db.vignetteRadarCategories.rare = true
second, alerts = F.Update({ a }, 2, 30, live)
assert(#second == 1 and #alerts == 0, "map transition must clear ghosts and seed silently")
second, alerts = F.Update({ a, target("map-b", 106, "Map B") }, 2, 31, live)
assert(#alerts == 1, "new map discoveries after seed may alert")
second, alerts = F.Update({ a, target("map-c", 107, "Map C") }, 2, 32, live)
assert(#alerts == 0, "global throttle must limit burst alerts")
second = F.Update({ a }, 2, 33, { enabled = false, preview = false })
assert(#second == 0 and F.Navigate(a) == false, "disabling must clear live and stale state")
second, alerts = F.Update({ a }, 2, 34, live)
assert(#alerts == 0, "re-enabling must seed silently")
second, alerts = F.Update({ target("preview", nil, "Preview") }, 2, 35,
    { enabled = true, preview = true })
assert(#second == 1 and #alerts == 0 and F.Navigate(second[1]) == false,
    "preview must be inert and clear live state")

local nav = target("nav", 108, "Navigator", "rare", .45)
F.Update({ nav }, 3, 40, live)
local tracked
C_SuperTrack = { SetSuperTrackedVignette = function(key) tracked = key end }
assert(F.Navigate(nav) == true and tracked == "nav", "live target should use vignette supertracking")
C_SuperTrack.SetSuperTrackedVignette = function() error("protected") end
local waypoint
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y)
    return { mapID = mapID, x = x, y = y }
end }
C_Map = { CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point) waypoint = point end }
assert(F.Navigate(nav) == true and waypoint.mapID == 3 and waypoint.x == .45,
    "waypoint should replace failed supertracking when coordinates exist")
C_Map.CanSetUserWaypointOnMap = function() return false end
assert(F.Navigate(nav) == false, "waypoint restrictions must fail safely")

C_VignetteInfo = { GetHealthPercent = function(key) assert(key == "nav"); return .72 end }
assert(F.GetHealth(nav) == 72, "rare health percent should pass through")
C_VignetteInfo.GetHealthPercent = function() return { secret = true } end
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
assert(F.GetHealth(nav) == nil, "secret health must not escape")
C_VignetteInfo.GetHealthPercent = function() error("protected") end
assert(F.GetHealth(nav) == nil, "protected health failure must be harmless")
assert(F.GetHealth(target("other", 200, "Other", "treasure")) == nil)

-- Wide scans can contain 512 Blizzard vignettes; ignored entries must not starve the visible cap.
local many = {}
for index = 1, 512 do
    many[index] = target("many-" .. index, 1000 + index, "Many " .. index)
    if index <= 200 then F.Ignore(many[index], false) end
end
local visible = F.Update(many, 4, 100, live)
assert(#visible == 256 and visible[1].key == "many-201"
    and visible[256].key == "many-456",
    "ignored entries must not consume the 256 visible target slots")
local nextMany = {}
for index = 1, 300 do
    nextMany[index] = target("next-" .. index, 2000 + index, "Next " .. index)
end
visible = F.Update(nextMany, 4, 101, live)
assert(#visible == 256 and visible[256].key == "next-256",
    "live and fading state must remain bounded together")

Enum = { QuestTagType = { Normal = 0, WorldBoss = 5 }, WorldQuestQuality = { Epic = 4 } }
C_QuestLog = { GetQuestTagInfo = function(questID)
    if questID == 900 then return { worldQuestType = 5 } end
    if questID == 901 then return { worldQuestType = 0, isElite = true, quality = 4 } end
    if questID == 902 then return { worldQuestType = 0, isElite = true, quality = 2 } end
    if questID == 903 then return { worldQuestType = 0, isElite = false, quality = 4 } end
    if questID == 904 then return { secret = true } end
    if questID == 905 then error("protected") end
end }
assert(F.IsWorldBoss({ rewardQuestID = 900 }), "explicit world-boss quest tag must classify")
assert(F.IsWorldBoss({ rewardQuestID = 901 }), "Blizzard's legacy elite epic world quest must classify")
assert(not F.IsWorldBoss({ rewardQuestID = 902 }) and not F.IsWorldBoss({ rewardQuestID = 903 }),
    "ordinary elite or epic quests must not classify")
assert(not F.IsWorldBoss({ rewardQuestID = 0 }) and not F.IsWorldBoss({})
    and not F.IsWorldBoss({ rewardQuestID = { secret = true } })
    and not F.IsWorldBoss({ rewardQuestID = 904 })
    and not F.IsWorldBoss({ rewardQuestID = 905 }),
    "missing, secret, and protected quest metadata must fail closed")
local boss = target("boss", 3000, "Verified boss")
boss.isWorldBoss = F.IsWorldBoss({ rewardQuestID = 900 })
boss.source = "worldMap"
visible = F.Update({ boss }, 5, 110, live)
assert(#visible == 1 and visible[1].isWorldBoss == true)
visible = F.Update({}, 5, 111, live)
assert(#visible == 1 and visible[1].stale and visible[1].isWorldBoss == true
    and visible[1].source == "worldMap",
    "last-seen snapshot must preserve world-boss classification and map provenance")

io.write("vignette radar feature tests passed\n")
