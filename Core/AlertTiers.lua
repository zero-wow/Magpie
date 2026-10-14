local _, addon = ...
if type(addon) ~= "table" then return end

-- Smart Alert Tiers. Features.Update asks Worth() before a new vignette may
-- alert, so only points worth the trip alert: not already done and within
-- the alert range. Favorites always pass. The radar then calls Fire() for
-- the chosen alert, which adds the louder tiers on top of its pulse and
-- sound: a raid-warning banner and a taskbar flash (Windows only flashes
-- the icon while the game is in the background).
--   AlertTiers.Worth(target [, settings]) -> bool, reason
--   AlertTiers.Fire(alerts [, settings]) -> fired tiers { banner, flash }
--   AlertTiers.Text(target) -> "Rare · Name · 320 yd"
local AlertTiers = {}
addon.VignetteRadarAlertTiers = AlertTiers

local type, pcall, floor = type, pcall, math.floor
local Field, Number, Text = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text

local KIND_TITLE = { rare = "Rare", treasure = "Treasure", event = "Event", other = "Point" }

local function Log(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("alerts", fmt, ...) end
end

local function Settings(settings) return settings or addon.GetSettings() end

-- The alert range in yards; 0 means the radar's own range.
local function Range(settings)
    local range = Number(settings.vignetteRadarAlertRange) or 1200
    if range <= 0 then range = Number(settings.vignetteRadarRange) or 450 end
    return range
end

function AlertTiers.Worth(target, settings)
    settings = Settings(settings)
    if settings.vignetteRadarAlertSmart ~= true then return true, "smart off" end
    if type(target) ~= "table" then return false, "no target" end
    local name = Text(Field(target, "name")) or "?"
    if Field(target, "favorite") == true then return true, "favorite" end
    local declutter = addon.VignetteRadarDeclutter
    local questID = Number(Field(target, "rewardQuestID"))
    if questID and declutter and declutter.Done(questID) then
        Log("skip %s: reward quest %s already done", name, questID)
        return false, "done"
    end
    local distance = Number(Field(target, "distance"))
    local range = Range(settings)
    if distance and distance > range then
        Log("skip %s: %d yd is past the %d yd alert range", name, floor(distance + .5), range)
        return false, "far"
    end
    return true, "worth it"
end

function AlertTiers.Text(target)
    local kind = Text(Field(target, "category")) or "other"
    local text = (KIND_TITLE[kind] or "Point") .. " · " .. (Text(Field(target, "name")) or "Unknown")
    local distance = Number(Field(target, "distance"))
    if distance then text = text .. " · " .. floor(distance + .5) .. " yd" end
    return text
end

local function Banner(text)
    local frame = _G.RaidWarningFrame
    local notice = _G.RaidNotice_AddMessage
    if not (frame and type(notice) == "function") then return false end
    local colors = _G.ChatTypeInfo
    local color = type(colors) == "table" and colors.RAID_WARNING or nil
    return (pcall(notice, frame, text, color))
end

local function Flash()
    if type(FlashClientIcon) ~= "function" then return false end
    return (pcall(FlashClientIcon))
end

-- alerts: Features.Update's chosen alerts (one at most per scan).
function AlertTiers.Fire(alerts, settings)
    settings = Settings(settings)
    local fired = {}
    local target = type(alerts) == "table" and alerts[1] or nil
    if type(target) ~= "table" then return fired end
    local favorite = Field(target, "favorite") == true
    local banner = settings.vignetteRadarAlertBanner
    if banner == "all" or (banner == "favorite" and favorite) then
        fired.banner = Banner(AlertTiers.Text(target))
    end
    if settings.vignetteRadarAlertFlash == true then fired.flash = Flash() end
    Log("fire %s favorite=%s banner=%s flash=%s", AlertTiers.Text(target), favorite,
        fired.banner == true, fired.flash == true)
    return fired
end

return AlertTiers
