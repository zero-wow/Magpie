local sourcePath = arg[1] or "UI/Radar.lua"

local eventFrame = {}
function eventFrame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
function eventFrame:SetScript(script, callback) self[script] = callback end

CreateFrame = function() return eventFrame end
SlashCmdList = {}
issecretvalue = function(value) return type(value) == "table" and value.secret == true end

local function vector(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

local infos = {
    live = { name = "Live Treasure", atlasName = "VignetteLoot", onMinimap = true, isDead = false },
    worldOnly = { name = "World Map Only", onMinimap = false, isDead = false },
    dead = { name = "Dead Rare", onMinimap = true, isDead = true },
    hidden = { name = "Hidden", onMinimap = { secret = true }, isDead = false },
}
local positions = {
    live = vector(0.55, 0.4), worldOnly = vector(0.2, 0.2), dead = vector(0.3, 0.3), hidden = vector(0.4, 0.4),
}

C_Map = {
    GetBestMapForUnit = function() return 777 end,
    GetPlayerMapPosition = function() return vector(0.5, 0.5) end,
    GetWorldPosFromMapPos = function(mapID, position)
        assert(mapID == 777, "unexpected map")
        return 42, vector(position.x * 1000, position.y * 1000)
    end,
}
C_VignetteInfo = {
    GetVignettes = function() return { "live", "worldOnly", "dead", "hidden" } end,
    GetVignetteInfo = function(guid) return infos[guid] end,
    GetVignettePosition = function(guid) return positions[guid] end,
}
GetPlayerFacing = function() return 0 end

local settings = { vignetteRadarEnabled = true, vignetteRadarHideWhenEmpty = true, vignetteRadarRange = 450 }
local addon = { GetSettings = function() return settings end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Focus.lua"))("VignetteRadar", addon)
assert(loadfile(sourcePath))("VignetteRadar", addon)

local T = assert(addon.VignetteRadarTesting, "module must expose its pure test boundary")
assert(T.DisplayableVignetteInfo(infos.live), "a live minimap vignette must be accepted")
assert(not T.DisplayableVignetteInfo(infos.worldOnly), "world-map-only vignettes must be rejected")
assert(not T.DisplayableVignetteInfo(infos.dead), "dead vignettes must be rejected")
assert(not T.DisplayableVignetteInfo(infos.hidden), "secret visibility values must be rejected")
local distant = { onMinimap = false, onWorldMap = true, inFogOfWar = false, isDead = false }
assert(T.DisplayableVignetteInfo(distant, true) and not T.DisplayableVignetteInfo(distant, false),
    "world-map entries must require the broader data scope")
distant.inFogOfWar = true
assert(not T.DisplayableVignetteInfo(distant, true), "fogged map entries must stay excluded")
distant.inFogOfWar = { secret = true }
assert(not T.DisplayableVignetteInfo(distant, true), "unreadable fog state must not expose a world-map position")
distant.inFogOfWar, distant.onWorldMap = false, { secret = true }
assert(not T.DisplayableVignetteInfo(distant, true), "unreadable map visibility must stay excluded")
distant.onWorldMap, distant.isDead = true, true
assert(not T.DisplayableVignetteInfo(distant, true), "world-map scope must still exclude dead vignettes")

local targets = T.CollectVignettes(777)
assert(#targets == 1 and targets[1].name == "Live Treasure", "only usable active minimap vignettes should be collected")
assert(targets[1].category == "treasure", "Blizzard vignette metadata must drive the visible legend category")
assert(targets[1].worldX == 550 and targets[1].worldY == 400 and targets[1].instanceID == 42,
    "vignette positions must be converted to world yards")
local note = { kind = "treasure", name = "Ancient chest", worldX = 550, worldY = 400 }
assert(T.MapNoteMatchesLive(note, targets[1]),
    "a live treasure at the same position must replace its map-pack note")
note.worldX = 590
assert(not T.MapNoteMatchesLive(note, targets[1]),
    "a differently named chest forty yards away must remain visible")
note.name = "Live Treasure"
assert(T.MapNoteMatchesLive(note, targets[1]),
    "a named treasure may suppress its less precise map-pack location")
note.worldX = 640
assert(not T.MapNoteMatchesLive(note, targets[1]),
    "a similarly named but distant location must remain visible")
note.kind, note.worldX = "mob", 550
assert(not T.MapNoteMatchesLive(note, targets[1]),
    "treasure data must not suppress an unrelated rare note")

local northX, northY = T.Project(100, 0, 100, 0, 90, 450)
assert(math.abs(northX) < 0.0001 and math.abs(northY - 20) < 0.0001,
    "a target ahead must appear above the player")
local westX, westY = T.Project(0, 100, 100, 0, 90, 450)
assert(math.abs(westX + 20) < 0.0001 and math.abs(westY) < 0.0001,
    "a target west must appear left of the player")
local turnedX, turnedY = T.Project(0, 100, 100, math.pi / 2, 90, 450)
assert(math.abs(turnedX) < 0.0001 and math.abs(turnedY - 20) < 0.0001,
    "projection must rotate with player facing")

assert(eventFrame.events.VIGNETTES_UPDATED and eventFrame.events.VIGNETTE_MINIMAP_UPDATED,
    "radar must react to both vignette update events")
assert(type(SlashCmdList.VIGNETTERADAR) == "function", "radar slash command must be installed")
assert(SLASH_VIGNETTERADAR1 == "/magpie" and SLASH_VIGNETTERADAR2 == "/vr" and SLASH_VIGNETTERADAR3 == nil,
    "/magpie is primary, /vr stays as the short alias, the old aliases are gone")

local sourceFile = assert(io.open(sourcePath, "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
assert(source:find('SafeBoolean(SafeField(info, "onMinimap")) == true', 1, true),
    "collection must explicitly require Blizzard minimap visibility")
assert(source:find('CategoryColor(target.category)', 1, true),
    "live radar markers must use the shared legend category treatment")
assert(source:find('C_Map.GetWorldPosFromMapPos', 1, true), "radar must use world-yard projection")
assert(not source:find('Minimap:SetParent', 1, true), "radar must never reparent or alter the real minimap")

io.write("vignette radar tests passed\n")
