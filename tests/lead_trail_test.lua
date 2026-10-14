-- Trails modes: migration of the old Travel Trail switch, the Lead path to
-- the target and through the next stops, and drawing (nothing without a
-- target, clipped to the face, skipped when nothing changed).

-- 1. Migration and reconciliation in Core's ValidateSettings.
STANDARD_TEXT_FONT = "default.ttf"
local core = {}
VignetteRadarDB = { vignetteRadarBreadcrumbs = true }
assert(loadfile("Core/Core.lua"))("VignetteRadar", core)
local db = core.ValidateSettings()
assert(db.vignetteRadarTrailMode == "follow", "an old Travel Trail that was on becomes Follow")
assert(db.vignetteRadarLeadNextStops == true, "Lead Through Next Stops defaults on")
VignetteRadarDB = { vignetteRadarBreadcrumbs = false }
db = core.ValidateSettings()
assert(db.vignetteRadarTrailMode == "off" and db.vignetteRadarBreadcrumbs == false,
    "an old Travel Trail that was off becomes Off")
VignetteRadarDB = {}
db = core.ValidateSettings()
assert(db.vignetteRadarTrailMode == "off", "a fresh profile starts with Trails off")
db.vignetteRadarTrailMode = "lead"
db = core.ValidateSettings()
assert(db.vignetteRadarBreadcrumbs == false, "Lead alone keeps the breadcrumbs off")
db.vignetteRadarBreadcrumbs = true
db = core.ValidateSettings()
assert(db.vignetteRadarTrailMode == "both", "turning breadcrumbs on during Lead gives Both")
db.vignetteRadarTrailMode = "follow"
db = core.ValidateSettings()
assert(db.vignetteRadarBreadcrumbs == true and db.vignetteRadarTrailMode == "follow",
    "a new mode wins over the old flag")
db.vignetteRadarBreadcrumbs = false
db = core.ValidateSettings()
assert(db.vignetteRadarTrailMode == "off", "turning breadcrumbs off during Follow gives Off")
db.vignetteRadarTrailMode = "nonsense"
db = core.ValidateSettings()
assert(db.vignetteRadarTrailMode == "off", "an unknown mode falls back to the breadcrumb flag")
local modes = assert(core.VignetteRadarTrailMode)
assert(modes.Compose(true, true) == "both" and modes.Compose(false, true) == "lead"
    and modes.Leads("both") and not modes.Leads("follow") and modes.Follows("both"),
    "mode helpers compose and split the two halves")

-- 2. The Lead path.
local mock = dofile("tests/ui_mock.lua").Install()
local settings = { vignetteRadarEnabled = true, vignetteRadarTrailMode = "lead",
    vignetteRadarLeadNextStops = true, vignetteRadarTrailStyle = "dashes",
    vignetteRadarTrailSpacing = 1, vignetteRadarTrailSize = 1 }
local addon = { GetSettings = function() return settings end }
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/SpatialProjection.lua"))("VignetteRadar", addon)
addon.VignetteRadarTrailMode = modes
addon.VignetteRadarTrailStyles = core.VignetteRadarTrailStyles
addon.VignetteRadarTrailStyleByID = core.VignetteRadarTrailStyleByID
addon.VignetteRadarStyle = { revision = 1, Color = function(slot)
    if slot == "rare" then return 0, 0, 1 end
    return .5, .5, .5
end }
assert(loadfile("UI/LeadTrail.lua"))("VignetteRadar", addon)
local Lead = assert(addon.VignetteRadarLeadTrail)

local player = { worldX = 0, worldY = 0, instanceID = 1, facing = 0 }
local target = { key = "quest:1", kind = "quest", name = "Target", worldX = 0, worldY = 100, instanceID = 1 }
local step = { worldX = 10, worldY = 120, instanceID = 1 }
local nextStop = { key = "t:2", kind = "treasure", worldX = 0, worldY = 300, instanceID = 1 }
local thenStop = { key = "r:3", kind = "rare", worldX = 50, worldY = 400, instanceID = 1 }
local active = true
addon.VignetteRadarWorldFocus = {
    GetActiveTarget = function() if active then return target, step, 1, 1 end end,
    IsRouteActive = function() return true end,
    GetHorizon = function()
        return { { item = target, current = true }, { item = nextStop }, { item = thenStop } }
    end,
    TargetColor = function(item) if item.kind == "quest" then return 1, 0, 0 end end,
}
local n = Lead.Path(player, settings)
local path = Lead.path
assert(n == 3, "the path runs to the target and on through two later stops: " .. n)
assert(path[1].x == 10 and path[1].y == 120 and path[1].r == 1,
    "the first point is the current step in the target's color")
assert(path[2].item == nextStop and path[3].item == thenStop and path[3].b == 1,
    "the chain follows the horizon order with each stop's own color")
assert(path[1].alpha == 1 and path[2].alpha < 1 and path[3].alpha < path[2].alpha,
    "the chain fades after the target")
settings.vignetteRadarLeadNextStops = false
assert(Lead.Path(player, settings) == 1, "with the chain off only the target is led to")
settings.vignetteRadarLeadNextStops = true
active = false
assert(Lead.Path(player, settings) == 0, "no target: no path")
active = true
assert(Lead.Path({ worldX = 0, worldY = 0, instanceID = 2 }, settings) == 0,
    "a target in another instance is not led to")

-- 3. Drawing.
local field = mock.New("Frame")
local panel = { field = field, plotRadius = 80, squarePlot = false }
local glyphCalls = 0
addon.VignetteRadarTrailGlyph = function(_, primary, extras, _, x, y)
    glyphCalls = glyphCalls + 1
    primary.x, primary.y = x, y
    primary:Show()
    for _, extra in ipairs(extras or {}) do extra:Show() end
end
local function Shown()
    local count, worst = 0, 0
    for _, list in ipairs({ panel.leadDots or {}, panel.leadMarks or {} }) do
        for _, region in pairs(list) do
            if region:IsShown() then
                count = count + 1
                worst = math.max(worst, math.sqrt(region.x * region.x + region.y * region.y))
            end
        end
    end
    return count, worst
end

active = false
Lead.Render(panel, player, 450)
assert(glyphCalls == 0 and select(1, Shown()) == 0, "nothing is drawn without a target")
active = true
Lead.Render(panel, player, 450)
local count, worst = Shown()
assert(count > 3 and worst <= panel.plotRadius - 7 + .001,
    "a target draws marks inside the radar face: " .. count .. " " .. worst)
local before = glyphCalls
Lead.Render(panel, player, 450)
assert(glyphCalls == before, "an unchanged scene is not redrawn")
player.worldX = 5
Lead.Render(panel, player, 450)
assert(glyphCalls > before, "moving redraws the lead")

-- Square face: marks stay inside the square.
panel.squarePlot = true
Lead.Invalidate()
Lead.Render(panel, player, 120)
for _, region in pairs(panel.leadMarks) do
    if region:IsShown() then
        assert(math.abs(region.x) <= 73.001 and math.abs(region.y) <= 73.001, "marks clip to the square face")
    end
end

-- Follow only, or no player: the lead hides.
settings.vignetteRadarTrailMode = "follow"
Lead.Render(panel, player, 450)
assert(select(1, Shown()) == 0, "Follow alone hides the lead")
settings.vignetteRadarTrailMode = "both"
Lead.Render(panel, player, 450)
assert(select(1, Shown()) > 0, "Both draws the lead")
Lead.Render(panel, nil, 450)
assert(select(1, Shown()) == 0, "no player hides the lead")

-- Clip helper: a segment from the centre to far away ends on the edge.
local t0, t1 = Lead.Clip(0, 0, 0, 200, 50, false)
assert(t0 == 0 and math.abs(t1 - .25) < 1e-9, "circle clip stops at the edge")
t0, t1 = Lead.Clip(0, 0, 200, 200, 50, true)
assert(t0 == 0 and math.abs(t1 - .25) < 1e-9, "square clip stops at the edge")
assert(Lead.Clip(100, 100, 200, 200, 50, false) == nil, "a segment fully outside is dropped")

print("lead_trail_test: ok")
