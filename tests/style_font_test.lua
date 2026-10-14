-- Style.Font / Style.SetFont: every addon string uses the bundled monospace
-- face, and a font file that fails to load falls back to the client font.
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local addon = { GetSettings = function() return {} end }
assert(loadfile("UI/Style.lua"))("Magpie", addon)
local Style = assert(addon.VignetteRadarStyle)

local folder = "Interface\\AddOns\\Magpie\\Media\\Fonts\\"
assert(Style.Font() == folder .. "JetBrainsMono-Regular.ttf", "the default weight is the bundled regular face")
assert(Style.Font("regular") == Style.Font(), "regular names the same face")
assert(Style.Font("bold") == folder .. "JetBrainsMono-Bold.ttf", "bold names the bundled bold face")
assert(Style.Font("nonsense") == Style.Font(), "an unknown weight falls back to regular")

for _, weight in ipairs({ "regular", "bold" }) do
    local file = Style.Font(weight):gsub("^Interface\\AddOns\\Magpie\\", ""):gsub("\\", "/")
    local handle = io.open(file, "rb")
    assert(handle, "the bundled font file must ship with the addon: " .. file)
    handle:close()
end

local function FontString(loads)
    local calls = {}
    return {
        calls = calls,
        SetFont = function(self, path, size, flags)
            calls[#calls + 1] = { path, size, flags }
            if loads == false and path:find("JetBrainsMono", 1, true) then return false end
            self.font = { path, size, flags }
            return loads ~= nil and true or nil
        end,
    }
end

-- A font that loads (the client returns true) keeps the bundled face.
local label = FontString(true)
assert(Style.SetFont(label, 11, "OUTLINE", "bold") == true, "a loaded font reports success")
assert(#label.calls == 1 and label.font[1] == Style.Font("bold") and label.font[2] == 11
    and label.font[3] == "OUTLINE", "SetFont passes the bundled path, size and flags")

-- Mocks that return nothing count as loaded too.
label = FontString(nil)
assert(Style.SetFont(label, 10) == true and label.font[1] == Style.Font() and label.font[3] == "",
    "a nil return is not a failure, and flags default to an empty string")

-- SetFont returns false: the label drops back to the client font.
label = FontString(false)
assert(Style.SetFont(label, 9, "OUTLINE") == false, "a failed load reports the fallback")
assert(#label.calls == 2 and label.calls[1][1] == Style.Font() and label.font[1] == STANDARD_TEXT_FONT
    and label.font[2] == 9 and label.font[3] == "OUTLINE", "the fallback keeps size and flags")

STANDARD_TEXT_FONT = nil
label = FontString(false)
Style.SetFont(label, 9)
assert(label.font[1] == "Fonts\\FRIZQT__.TTF", "without STANDARD_TEXT_FONT the stock face is used")

assert(Style.SetFont(nil, 10) == false and Style.SetFont({}, 10) == false,
    "missing font strings are ignored")

io.write("style font tests passed\n")
