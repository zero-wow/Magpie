-- A small permissive WoW UI mock for module smoke tests: frames, textures and
-- font strings keep the state the tests read (shown, text, points, scripts,
-- size) and accept every other method as a no-op.
--   local mock = dofile("tests/ui_mock.lua")
--   mock.Install()            -- sets CreateFrame, UIParent, GameTooltip
--   mock.Click(frame, button) -- runs the OnClick script
local Mock = {}

local tracked = {
    SetSize = function(self, w, h) self.width, self.height = w, h end,
    SetWidth = function(self, w) self.width = w end,
    SetHeight = function(self, h) self.height = h end,
    GetWidth = function(self) return self.width or 0 end,
    GetHeight = function(self) return self.height or 0 end,
    SetPoint = function(self, ...) self.point = { ... } end,
    ClearAllPoints = function(self) self.point = nil end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetShown = function(self, value) self.shown = value and true or false end,
    IsShown = function(self) return self.shown == true end,
    IsVisible = function(self) return self.shown == true end,
    SetText = function(self, text)
        self.text = text
        if self.fontString then self.fontString.text = text end
    end,
    GetText = function(self) return self.text end,
    SetFormattedText = function(self, fmt, ...) self.text = string.format(fmt, ...) end,
    SetScript = function(self, name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end,
    GetScript = function(self, name) return self.scripts and self.scripts[name] end,
    HookScript = function(self, name, fn) self.hooks = self.hooks or {}; self.hooks[name] = fn end,
    SetAlpha = function(self, value) self.alpha = value end,
    GetAlpha = function(self) return self.alpha or 1 end,
    SetFrameStrata = function(self, value) self.strata = value end,
    GetFrameStrata = function(self) return self.strata or "MEDIUM" end,
    SetFrameLevel = function(self, value) self.level = value end,
    GetFrameLevel = function(self) return self.level or 1 end,
    SetVertexColor = function(self, ...) self.vertex = { ... } end,
    SetTextColor = function(self, ...) self.textColor = { ... } end,
    SetAtlas = function(self, name) self.atlas = name; return true end,
    SetTexture = function(self, value) self.texture = value end,
    GetStringWidth = function(self) return #(self.text or "") * 6 end,
    -- Monospace estimate at the font size Style.SetFont applied (.6 em per glyph).
    GetUnboundedStringWidth = function(self)
        return #(tostring(self.text or ""):gsub("[\128-\191]", "")) * (self.vrFontSize or 10) * .6
    end,
    SetWordWrap = function(self, value) self.wordWrap = value end,
    SetFontString = function(self, value) self.fontString = value end,
    GetScale = function() return 1 end,
    GetEffectiveScale = function() return 1 end,
    IsMouseOver = function(self) return self.mouseOver == true end,
}

local function Noop() end

local function New(kind, parent)
    local object = { kind = kind, parent = parent, shown = true }
    Mock.created = Mock.created or {}
    Mock.created[#Mock.created + 1] = object
    return setmetatable(object, { __index = function(_, key)
        local method = tracked[key]
        if method then return method end
        if key == "CreateTexture" or key == "CreateFontString" or key == "CreateLine" then
            return function(self) return New(key, self) end
        end
        if type(key) == "string" and key:match("^%u") then return Noop end
        return nil
    end })
end
Mock.New = New

function Mock.Install()
    Mock.frames = {}
    _G.UIParent = New("Frame")
    _G.CreateFrame = function(kind, name, parent)
        local frame = New(kind, parent)
        frame.shown = true
        Mock.frames[#Mock.frames + 1] = frame
        if name then _G[name] = frame end
        return frame
    end
    local tooltip = New("GameTooltip")
    tooltip.lines = {}
    tooltip.SetOwner = function(self) self.lines = {}; self.owned = true end
    tooltip.SetText = function(self, text) self.lines = { text } end
    tooltip.AddLine = function(self, text) self.lines[#self.lines + 1] = text end
    tooltip.AddDoubleLine = function(self, left, right) self.lines[#self.lines + 1] = left .. " " .. right end
    _G.GameTooltip = tooltip
    return Mock
end

function Mock.Click(frame, button)
    local script = frame.scripts and frame.scripts.OnClick
    if script then script(frame, button or "LeftButton") end
end

function Mock.Enter(frame)
    local script = frame.scripts and frame.scripts.OnEnter
    if script then script(frame) end
end

return Mock
