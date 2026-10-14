-- Declutter: done (character or account), duplicate-of-live, killed since
-- the daily reset, packs only when nothing live, packs only within N yd.
local settings = { vignetteRadarDeclutter = true, vignetteRadarDeclutterLiveOnly = false,
    vignetteRadarDeclutterRange = 0, vignetteRadarRecentKills = {} }
local addon = { GetSettings = function() return settings end }
local epoch, clock = 200000, 0
_G.GetServerTime = function() return epoch end
_G.GetTime = function() return clock end
local charDone, accountDone, trackingAccount = {}, {}, false
local calls = 0
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) calls = calls + 1; return charDone[id] == true end,
    IsQuestFlaggedCompletedOnAccount = function(id) return accountDone[id] == true end,
}
_G.C_Minimap = { IsTrackingAccountCompletedQuests = function() return trackingAccount end }
local untilReset = 70000 -- the reset was 16400 s ago
_G.C_DateAndTime = { GetSecondsUntilDailyReset = function() return untilReset end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Recent.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Declutter.lua"))("VignetteRadar", addon)
local Declutter = assert(addon.VignetteRadarDeclutter)

local function Note(key, kind, x, extra)
    local note = { key = key, kind = kind, worldX = x, worldY = 0, instanceID = 1 }
    for field, value in pairs(extra or {}) do note[field] = value end
    return note
end
local function Keys(list)
    local keys = {}
    for _, note in ipairs(list) do keys[note.key] = true end
    return keys
end
local player = { worldX = 0, worldY = 0, instanceID = 1 }
local notes = {
    Note("plain", "treasure", 100),
    Note("charDone", "treasure", 200, { questID = 11 }),
    Note("accountDone", "treasure", 300, { questID = 12 }),
    Note("nearLive", "mob", 410, { npcID = 77 }),
    Note("killed", "mob", 900, { npcID = 88 }),
    Note("guide", "guide", 5000, { questID = 11 }),
}
charDone[11], accountDone[12] = true, true
local live = { { category = "rare", worldX = 450, worldY = 0, instanceID = 1 },
    { category = "treasure", worldX = 10, worldY = 0, instanceID = 1, stale = true } }
assert(addon.VignetteRadarRecent.RecordNPCGuid("Creature-0-1-2-3-88-000001"),
    "Declutter alone must let Recent record kills")
epoch = epoch + 7200 -- two hours later: past Recent's hour, inside this reset.
local kept = Keys(Declutter.Apply(notes, live, player))
assert(kept.plain and kept.guide, "plain notes and guide steps stay")
assert(not kept.charDone and not kept.accountDone, "character and account done notes hide")
assert(not kept.nearLive, "a note within 60 yd of a live vignette of its kind hides")
assert(not kept.killed, "a rare killed since the daily reset hides after Recent's hour")
local counts = Declutter.LastCounts()
assert(counts.done == 2 and counts.duplicate == 1 and counts.killed == 1, "counts explain what hid")

-- Account tracking on: Blizzard shows account-done quests, so do we.
Declutter.Invalidate()
trackingAccount = true
kept = Keys(Declutter.Apply(notes, live, player))
assert(kept.accountDone and not kept.charDone, "account-done notes stay while the minimap tracks them")
trackingAccount = false

-- Quest results are cached between scans.
Declutter.Invalidate()
calls = 0
Declutter.Apply(notes, live, player)
Declutter.Apply(notes, live, player)
assert(calls == 2, "quest flags are read once per quest while cached: " .. calls)

-- Killed before the daily reset: back again.
untilReset = 86400 - 3600 -- reset was an hour ago; the kill was two hours ago.
kept = Keys(Declutter.Apply(notes, live, player))
assert(kept.killed, "a rare killed before the daily reset returns")

-- The focused point always stays.
addon.VignetteRadarWorldFocus = { GetActiveTarget = function() return notes[2] end }
kept = Keys(Declutter.Apply(notes, live, player))
assert(kept.charDone, "the World Focus destination is never hidden")
addon.VignetteRadarWorldFocus = nil

-- Packs only when nothing live; a stale vignette does not count.
settings.vignetteRadarDeclutter = false
settings.vignetteRadarDeclutterLiveOnly = true
kept = Keys(Declutter.Apply(notes, live, player))
assert(not kept.plain and kept.guide, "a live rare hides every pack note but guide steps")
kept = Keys(Declutter.Apply(notes, { live[2] }, player))
assert(kept.plain and kept.charDone, "stale vignettes are not live")

-- Packs only within N yd.
settings.vignetteRadarDeclutterLiveOnly = false
settings.vignetteRadarDeclutterRange = 250
kept = Keys(Declutter.Apply(notes, {}, player))
assert(kept.plain and kept.charDone and not kept.accountDone and not kept.killed,
    "notes past the range hide; done notes stay while Hide Done is off")

-- Everything off: the same list comes back.
settings.vignetteRadarDeclutterRange = 0
assert(Declutter.Apply(notes, live, player) == notes, "all switches off returns the list untouched")

io.write("declutter tests passed\n")
