-- luacheck: globals GameTooltip
-- UI/IconButton.lua: atlas coordinates, theme tint, hover / active / pressed /
-- disabled states, tooltips and the theme-change repaint.
local mock = dofile("tests/ui_mock.lua").Install()
-- ui_mock keeps unknown methods as no-ops; record the ones the helper drives.
local function Track(object)
    object.SetTexCoord = function(self, ...) self.texCoord = { ... } end
    return object
end
local create = _G.CreateFrame
_G.CreateFrame = function(...)
    local frame = create(...)
    local createTexture = frame.CreateTexture
    frame.CreateTexture = function(self, ...) return Track(createTexture(self, ...)) end
    return frame
end
GameTooltip.IsOwned = function(self, owner) return self.owner == owner end
local setOwner = GameTooltip.SetOwner
GameTooltip.SetOwner = function(self, owner, ...) setOwner(self, owner, ...); self.owner = owner end

local colors = { accent = { .1, .2, .3 }, rings = { .4, .5, .6 }, iconGlyph = { .1, .2, .3 },
    iconBorder = { .7, .1, .1 }, iconPlate = { .2, .2, .2 }, iconHover = { .1, .7, .1 }, iconActive = { .9, .9, .1 } }
local framed = false
local style = { revision = 1, IconFramed = function() return framed end }
function style.Color(slot) local c = colors[slot]; return c[1], c[2], c[3] end
local controlsRefreshed = 0
local addon = { VignetteRadarStyle = style,
    VignetteRadarControls = { RefreshTheme = function() controlsRefreshed = controlsRefreshed + 1 end } }
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
local Icons = assert(addon.VignetteRadarIconButton)

-- The Lua glyph lists must match the generator's order: button icons, then
-- the corner tools and rail icons drawn by the two older generators.
local function Names(path, pattern)
    local text = assert(io.open(path)):read("*a")
    local list = {}
    for name in assert(text:match(pattern)):gmatch('"([%w_]+)"') do list[#list + 1] = name end
    return list
end
local function Same(a, b, what)
    assert(#a == #b, what .. " count differs")
    for index = 1, #a do assert(a[index] == b[index], what .. " differs at " .. index .. ": " .. a[index]) end
end
Same(Names("tools/generate_button_icons.py", "\nICONS = %((.-)%)"), Icons.ICONS, "button icons")
Same(Names("tools/generate_corner_controls.py", "\nICONS = %((.-)%)"), Icons.CORNER, "corner icons")
Same(Names("tools/generate_config_icons.py", "\nICONS = %((.-)%)"), Icons.RAIL, "rail icons")
assert(Icons.HasIcon(Icons.MINIMAP) and Icons.HasIcon("corner_north") and Icons.HasIcon("rail_looks"))

-- The atlas is a power-of-two TGA: three glyph rows and one layer row.
local tga = assert(io.open("Media/button-icons.tga", "rb")):read(18)
local width = tga:byte(13) + tga:byte(14) * 256
local height = tga:byte(15) + tga:byte(16) * 256
assert(width == 1024 and height == 256 and tga:byte(17) == 32, "button-icons.tga must be 1024x256 32-bit")

local _
local function Near(a, b) return math.abs(a - b) < 1e-9 end
local left, right, top, bottom = Icons.Coords("options")
assert(Near(left, 1 / 1024) and Near(right, 63 / 1024) and Near(top, 1 / 256) and Near(bottom, 63 / 256))
left, _, top = Icons.Coords("search")
assert(Near(left, 65 / 1024) and Near(top, 65 / 256), "glyph 17 is row 1, column 1")
left, _, top = Icons.Coords("rail_search")
assert(Near(left, (14 * 64 + 1) / 1024) and Near(top, (2 * 64 + 1) / 256), "rail glyphs follow the corner set")
left, _, top = Icons.LayerCoords("underline")
assert(Near(left, (3 * 64 + 1) / 1024) and Near(top, (3 * 64 + 1) / 256), "layer masks sit in row 3")

local clicks, active = 0, false
local button = Icons.Create(UIParent, "share", { size = 18, label = "Share To Group",
    tooltip = function() return "Post a pin." end,
    isActive = function() return active end,
    onClick = function() clicks = clicks + 1 end })
local layers = button.iconLayers
assert(button.width == 18 and button.art.width == 18 and button.labelText == "Share To Group"
    and button.art.texture == Icons.ATLAS and layers.plate and layers.border and layers.glow
    and layers.underline, "size, layers and label")
-- Each layer takes its own role.
assert(button.art.vertex[1] == .1 and layers.border.vertex[1] == .7 and layers.plate.vertex[1] == .2
    and layers.glow.vertex[2] == .7 and layers.underline.vertex[1] == .9, "one theme role per layer")
assert(button._artState == 0 and button.art.vertex[4] == .86 and layers.border.vertex[4] == 0
    and layers.plate.vertex[4] == 0 and layers.underline.vertex[4] == 0, "quiet idle: glyph only")

mock.Enter(button)
assert(button._artState == 1 and button.art.vertex[4] == 1 and layers.glow.vertex[4] > 0
    and layers.border.vertex[4] > 0, "hover lights the glow and border")
assert(GameTooltip.lines[1] == "Share To Group" and GameTooltip.lines[2] == "Post a pin.", "tooltip")
button.scripts.OnMouseDown(button)
assert(button.art.point[5] == -1, "pressed nudges the glyph down")
button.scripts.OnMouseUp(button)
assert(button.art.point[5] == 0, "release puts it back")
mock.Click(button)
assert(clicks == 1, "onClick runs")
button.scripts.OnLeave(button)
assert(button._artState == 0 and layers.glow.vertex[4] == 0, "leave drops the hover")

active = true
button:Refresh()
assert(button._artState == 2 and layers.underline.vertex[4] > .9, "active shows the underline")
assert(button.art.vertex[1] == .9 and button.art.vertex[3] == .1, "active turns the glyph to iconActive")
mock.Enter(button)
assert(button._artState == 3, "active + hover")
button.scripts.OnLeave(button)

button:SetEnabled(false)
assert(button.art.vertex[1] == .4 and button.art.vertex[4] == .38 and layers.underline.vertex[4] == 0,
    "disabled: rings tint, low alpha, no marks")
mock.Enter(button)
assert(button._artState == 2, "disabled ignores hover")
button.scripts.OnLeave(button)
button:SetEnabled(true)

-- Framed look (Multi-Color themes): plate and border show while idle.
active = false
framed = true
style.revision = 2
button:Refresh()
assert(layers.plate.vertex[4] > 0 and layers.border.vertex[4] > 0 and layers.glow.vertex[4] == 0,
    "framed idle: plate and border drawn")
-- Only the selected button is lit: idle takes the quiet rings border and a
-- dimmer glyph; selected takes the selected color on glyph and border.
assert(layers.border.vertex[1] == .4 and layers.border.vertex[3] == .6 and button.art.vertex[1] == .1
    and button.art.vertex[4] < .86, "framed idle: rings border, base glyph, dimmed")
local idleBorder = layers.border.vertex[4]
mock.Enter(button)
assert(layers.border.vertex[1] == .7 and button.art.vertex[4] == 1, "framed hover: theme border role")
button.scripts.OnLeave(button)
active = true
button:Refresh()
assert(layers.border.vertex[1] == .4 and layers.border.vertex[4] == idleBorder
    and button.art.vertex[1] == .9 and button.art.vertex[4] == 1 and layers.underline.vertex[1] == .9,
    "framed selected: idle border, only glyph and underline take the on color")
active = false
button:Refresh()
assert(layers.border.vertex[1] == .4, "deselect goes back to the quiet border")
framed = false

-- Active icon swap and SetIcon.
local toggle = Icons.Create(UIParent, "unlock", { activeIcon = "lock" })
assert(Near(toggle.art.texCoord[1], (Icons.Coords("unlock"))), "inactive shows the base icon")
toggle:SetActive(true)
assert(Near(toggle.art.texCoord[1], (Icons.Coords("lock"))), "active shows the active icon")
toggle:SetIcon("pause")
assert(toggle._artGlyph == "lock", "the active icon still wins while active")
toggle:SetActive(false)
assert(toggle._artGlyph == "pause", "SetIcon changes the base icon")

-- Skinning a frame made elsewhere (corner tools, settings rail).
local tool = Icons.AddLayers(CreateFrame("Button", nil, UIParent), "corner_north", 18)
Icons.Paint(tool, true, false)
assert(tool._artState == 2 and tool.art.vertex[1] == .9 and tool.iconLayers.underline.vertex[4] > .9,
    "Paint drives any skinned frame")
-- Single Color themes: iconActive equals the glyph, so the glyph flips hue.
do
    local saved = colors.iconActive
    colors.iconActive = colors.iconGlyph
    local r, g, b = Icons.SelectedColor()
    assert(Near(r, .3) and Near(g, .2) and Near(b, .1), "a matching active color flips to the opposite hue")
    colors.iconActive = saved
end
-- The on color never matches hover: an active role equal to iconHover turns.
do
    local saved = colors.iconActive
    colors.iconActive = colors.iconHover
    local r, g, b = Icons.OnColor()
    local h = colors.iconHover
    assert(math.abs(r - h[1]) + math.abs(g - h[2]) + math.abs(b - h[3]) > .3, "on color differs from hover")
    colors.iconActive = saved
    r = Icons.OnColor()
    assert(r == .9, "a distinct active role is kept")
end

-- Theme change: the Looks broadcast repaints every button with new roles.
colors.iconGlyph = { .9, .8, .7 }
colors.iconBorder = { .3, .3, .9 }
style.revision = 3
addon.VignetteRadarControls.RefreshTheme()
assert(controlsRefreshed == 1, "the wrapped Controls.RefreshTheme still runs")
assert(button.art.vertex[1] == .9 and toggle.art.vertex[1] == .9 and tool.art.vertex[1] == .9
    and layers.border.vertex[3] == .9, "the Looks broadcast re-tints every layer of every button")
toggle.art.vertex = nil
Icons.RefreshTheme()
assert(toggle.art.vertex == nil, "an unchanged theme skips the repaint")
Icons.RefreshTheme(true)
assert(toggle.art.vertex[1] == .9, "force repaints")

print("icon button tests passed")
