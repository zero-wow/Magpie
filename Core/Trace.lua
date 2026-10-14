local _, addon = ...
if type(addon) ~= "table" then return end

-- Route-decision debug trace. Off by default: Trace.Log returns at once, so
-- callers may leave their trace lines in hot paths. Callers that build costly
-- detail check Trace.IsOn() first. Lines go to a ring of the last 400 entries
-- in VignetteRadarDB.vignetteRadarTraceLog, so a trace survives /reload.
--   /vrtrace on | off | dump [n] | clear
local Trace = {}
addon.Trace = Trace

local MAX_LINES, DEFAULT_DUMP = 400, 40
local type, tostring, select, pcall = type, tostring, select, pcall
local format, unpack = string.format, table.unpack or unpack
local enabled = false
-- Consecutive identical lines collapse into one line with a repeat count.
local lastKey, lastLine, repeats = nil, nil, 0
local scratch = {}

local function Store()
    local db = type(addon.GetSettings) == "function" and addon.GetSettings() or nil
    if type(db) ~= "table" then return nil end
    if type(db.vignetteRadarTraceLog) ~= "table" then db.vignetteRadarTraceLog = {} end
    return db.vignetteRadarTraceLog
end

local function Now()
    if type(GetTime) ~= "function" then return 0 end
    local ok, now = pcall(GetTime)
    return ok and type(now) == "number" and now or 0
end

local function Chat(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and type(frame.AddMessage) == "function" then
        frame:AddMessage("|cff8bd5caVR trace|r " .. text)
    elseif type(print) == "function" then
        print("VR trace " .. text)
    end
end

-- %s accepts any value here: everything but numbers goes through tostring.
local function Format(fmt, ...)
    local count = select("#", ...)
    if count == 0 then return tostring(fmt) end
    for index = 1, count do
        local value = select(index, ...)
        scratch[index] = type(value) == "number" and value or tostring(value)
    end
    local text = format(fmt, unpack(scratch, 1, count))
    for index = 1, count do scratch[index] = nil end
    return text
end

local function Add(topic, message)
    local lines = Store()
    if not lines then return end
    local key = topic .. "\001" .. message
    local stamp = format("%.1f", Now())
    if key == lastKey and lastLine and lines[#lines] == lastLine then
        repeats = repeats + 1
        lastLine = stamp .. " [" .. topic .. "] " .. message .. " (x" .. repeats .. ")"
        lines[#lines] = lastLine
        return
    end
    lastKey, repeats = key, 1
    lastLine = stamp .. " [" .. topic .. "] " .. message
    lines[#lines + 1] = lastLine
    while #lines > MAX_LINES do table.remove(lines, 1) end
    Chat(lastLine)
end

function Trace.IsOn() return enabled end

function Trace.Log(topic, fmt, ...)
    if not enabled then return end
    local ok, message = pcall(Format, fmt, ...)
    if not ok then message = tostring(fmt) .. " <format error>" end
    Add(tostring(topic or "trace"), message)
end

function Trace.SetEnabled(on)
    enabled = on == true
    local db = type(addon.GetSettings) == "function" and addon.GetSettings() or nil
    if type(db) == "table" then db.vignetteRadarTraceEnabled = enabled end
    lastKey, lastLine, repeats = nil, nil, 0
end

-- The saved lines, oldest first. Callers only read the list.
function Trace.Lines() return Store() or {} end

function Trace.Clear()
    local lines = Store()
    if lines then for index = #lines, 1, -1 do lines[index] = nil end end
    lastKey, lastLine, repeats = nil, nil, 0
end

function Trace.Dump(count)
    local lines = Store() or {}
    count = math.max(1, math.min(math.floor(tonumber(count) or DEFAULT_DUMP), MAX_LINES))
    local first = math.max(1, #lines - count + 1)
    Chat(format("%d of %d lines", #lines - first + 1, #lines))
    for index = first, #lines do Chat(lines[index]) end
end

-- Saved on/off is read once the SavedVariables exist.
local function Load()
    local db = type(addon.GetSettings) == "function" and addon.GetSettings() or nil
    enabled = type(db) == "table" and db.vignetteRadarTraceEnabled == true
    local lines = Store()
    if lines then
        while #lines > MAX_LINES do table.remove(lines, 1) end
    end
end
Trace.Load = Load
if addon.Bus and type(addon.Bus.On) == "function" then addon.Bus.On("LOGIN", Load) end

function Trace.Command(message)
    local command, argument = tostring(message or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if command == "on" then
        Trace.SetEnabled(true)
        Chat("on · new lines print here live · /vrtrace off to stop")
    elseif command == "off" then
        Trace.SetEnabled(false)
        Chat("off · saved lines kept · /vrtrace dump to read them")
    elseif command == "dump" then
        Trace.Dump(argument ~= "" and argument or nil)
    elseif command == "clear" then
        Trace.Clear()
        Chat("cleared")
    else
        Chat((enabled and "on" or "off") .. " · " .. #Trace.Lines() .. " saved lines")
        Chat("/vrtrace on | off | dump [n] | clear")
    end
end

if type(SlashCmdList) == "table" then
    SLASH_VIGNETTERADARTRACE1 = "/vrtrace"
    SlashCmdList.VIGNETTERADARTRACE = Trace.Command
end
