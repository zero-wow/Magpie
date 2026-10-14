local sourcePath = arg[1] or "UI/Atlas.lua"

local objects = {}
local methods = {}
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:GetWidth() return self.width or (self.parent and self.parent:GetWidth()) or 0 end
function methods:GetHeight() return self.height or (self.parent and self.parent:GetHeight()) or 0 end
function methods:GetParent() return self.parent end
function methods:SetPoint(...) self.point = { ... } end
function methods:ClearAllPoints() self.point = nil end
function methods:SetAllPoints() end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetScript(name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end
function methods:CreateTexture()
    local object = setmetatable({ parent = self, kind = "Texture" }, { __index = methods })
    objects[#objects + 1] = object
    return object
end
function methods:CreateFontString()
    local object = setmetatable({ parent = self, kind = "FontString" }, { __index = methods })
    objects[#objects + 1] = object
    return object
end
function methods:SetTexture(value) assert(type(value) == "string"); self.texture = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetVertexColor(...) self.color = { ... } end
function methods:SetRotation(value) self.rotation = value end
function methods:SetFont(...) self.font = { ... } end
function methods:SetText(value) self.text = value end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:HookScript(name, fn)
    self.hooks = self.hooks or {}
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
end

function CreateFrame(kind, name, parent)
    local frame = setmetatable({ kind = kind, name = name, parent = parent }, { __index = methods })
    objects[#objects + 1] = frame
    return frame
end

local addon = {}
assert(loadfile("UI/Style.lua"))("VignetteRadar", addon)
assert(loadfile(sourcePath))("VignetteRadar", addon)
local atlas = assert(addon.VignetteRadarAtlas)
local ok, reason = atlas.Open()
assert(ok == false and reason == "World map unavailable" and not atlas.IsOpen(),
    "missing map must leave Atlas closed with an explicit reason")

local child = CreateFrame("Frame")
child:SetSize(1000, 700)
WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.ScrollContainer = { Child = child }
function WorldMapFrame:GetMapID() return self.mapID end
WorldMapFrame.mapID = 100
local selected
atlas.SetOnSelect(function(entry, count) selected = { entry, count } end)
atlas.SetData(100, {
    { mapX = .25, mapY = .4, name = "Saved rare", evidence = "saved" },
    { mapX = .251, mapY = .401, name = "Live rare", evidence = "live" },
    { mapX = .75, mapY = .2, name = "Quest", evidence = "quest" },
    { mapX = -1, mapY = .2, name = "Invalid", evidence = "live" },
})
assert(atlas.Open() == true and atlas.IsOpen())
local buttons = {}
for _, object in ipairs(objects) do
    if object.kind == "Button" and object.shown then buttons[#buttons + 1] = object end
end
assert(#buttons == 2, "nearby notes must cluster and invalid coordinates must be ignored")
assert(buttons[1].title == "Live rare" and buttons[1].groupCount == 2,
    "live evidence must win a mixed cluster")
assert(buttons[1].point[2].kind == "Frame" and math.abs(buttons[1].point[4] - 251) < .01
    and math.abs(buttons[1].point[5] + 280.7) < .01, "marker must anchor to normalized map coordinates")
buttons[1].scripts.OnClick(buttons[1])
assert(selected[1].name == "Live rare" and selected[2] == 2, "marker selection must reach integration callback")

WorldMapFrame.mapID = 101
atlas.Refresh()
assert(not buttons[1]:IsShown() and not buttons[2]:IsShown(), "wrong map must show no markers")
WorldMapFrame.mapID = 100
local dense = {}
for i = 1, 300 do dense[i] = { mapX = ((i % 30) + .1) / 31, mapY = (math.floor(i / 30) + .1) / 11, evidence = "saved" } end
atlas.SetData(100, dense)
local shown = 0
for _, object in ipairs(objects) do if object.kind == "Button" and object.shown then shown = shown + 1 end end
assert(shown <= 128, "dense maps must use a bounded marker pool")
atlas.Close()
assert(not atlas.IsOpen(), "Close must clear open state")
for _, object in ipairs(objects) do
    if object.kind == "Button" then assert(not object.shown, "Close must hide every marker") end
end

assert(atlas.Open() == true and atlas.IsOpen())
local onHide = WorldMapFrame.hooks and WorldMapFrame.hooks.OnHide
assert(onHide and #onHide == 1, "the overlay must hook the world map's OnHide exactly once")
WorldMapFrame:Hide()
for _, hook in ipairs(onHide) do hook(WorldMapFrame) end
assert(not atlas.IsOpen(), "hiding the world map must close the Atlas overlay")
for _, object in ipairs(objects) do
    if object.kind == "Button" then assert(not object.shown, "map hide must hide every marker") end
end
print("Atlas overlay tests passed")
