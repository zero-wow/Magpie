-- Smart Alert Tiers: worth-it filter (done, range, favorite) and the louder
-- tiers (raid-warning banner, taskbar flash).
local settings = { vignetteRadarAlertSmart = true, vignetteRadarAlertRange = 1200,
    vignetteRadarRange = 450, vignetteRadarAlertBanner = "favorite", vignetteRadarAlertFlash = true }
local addon = { GetSettings = function() return settings end }
_G.GetTime = function() return 0 end
local done = {}
_G.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return done[id] == true end,
    IsQuestFlaggedCompletedOnAccount = function() return false end }
_G.C_Minimap = { IsTrackingAccountCompletedQuests = function() return false end }
local banners, flashes = {}, 0
RaidWarningFrame = {}
ChatTypeInfo = { RAID_WARNING = { r = 1, g = .3, b = .1 } }
_G.RaidNotice_AddMessage = function(frame, text, color)
    assert(frame == RaidWarningFrame and color == ChatTypeInfo.RAID_WARNING)
    banners[#banners + 1] = text
end
_G.FlashClientIcon = function() flashes = flashes + 1 end
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Declutter.lua"))("VignetteRadar", addon)
assert(loadfile("Core/AlertTiers.lua"))("VignetteRadar", addon)
local Tiers = assert(addon.VignetteRadarAlertTiers)

local near = { name = "Near Rare", category = "rare", distance = 300.4, rewardQuestID = 5 }
local far = { name = "Far Rare", category = "rare", distance = 1900 }
local favorite = { name = "Loved Rare", category = "rare", distance = 9000, favorite = true, rewardQuestID = 6 }
assert(Tiers.Worth(near) and not Tiers.Worth(far) and Tiers.Worth(favorite),
    "near points alert, far points do not, favorites always do")
done[5], done[6] = true, true
addon.VignetteRadarDeclutter.Invalidate()
local ok, reason = Tiers.Worth(near)
assert(not ok and reason == "done", "a point whose reward quest is done does not alert")
assert(Tiers.Worth(favorite), "a favorite alerts even when done")
settings.vignetteRadarAlertRange = 0
assert(not Tiers.Worth({ name = "Edge", distance = 500 }), "0 means the radar's own range")
settings.vignetteRadarAlertRange = 10000
assert(Tiers.Worth(far), "Whole Zone lets far points alert")
settings.vignetteRadarAlertSmart = false
assert(Tiers.Worth(near), "with the switch off every alert passes")
settings.vignetteRadarAlertSmart = true

assert(Tiers.Text(near) == "Rare · Near Rare · 300 yd", "the banner names kind, name and yards")
local fired = Tiers.Fire({ near })
assert(#banners == 0 and flashes == 1 and fired.flash and not fired.banner,
    "favorite-only banners skip a plain rare; the taskbar still flashes")
Tiers.Fire({ favorite })
assert(banners[1] == "Rare · Loved Rare · 9000 yd" and flashes == 2, "a favorite gets the banner")
settings.vignetteRadarAlertBanner, settings.vignetteRadarAlertFlash = "all", false
Tiers.Fire({ near })
assert(#banners == 2 and flashes == 2, "Every Alert banners everything; flash off stays off")
settings.vignetteRadarAlertBanner = "off"
Tiers.Fire({ favorite })
assert(#banners == 2, "banners off")
assert(next(Tiers.Fire({})) == nil, "no alert fires nothing")

io.write("alert tiers tests passed\n")
