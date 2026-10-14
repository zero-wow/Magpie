local _, addon = ...
if type(addon) ~= "table" then return end

-- Learned Data Export/Import: one versioned, plain-text string for learned
-- rare spawns and your pins, to share with friends or alts.
-- The import is data only and never loads code: it is size-capped, every
-- record is split by fixed separators and each field is checked for type and
-- range before anything is saved. A bad record is skipped, not trusted; a
-- wrong header, version or checksum refuses the whole string.
--   Text: VRL1:<records>:<checksum>:<body>
--     body    = record ~ record ~ ...
--     spawn   = S,npcID,name,mapID,x,y,z,instance,mx,my,sightings,first,last
--     pin     = P,name,mapID,mx,my,x,y,instance,at
--     name    = percent-encoded (only letters and digits stay as they are)
--   LearnedTransfer.Export([scope [, mapID]]) -> text, counts | nil, reason
--     scope "all" (default) or "zone" (mapID)
--   LearnedTransfer.Decode(text) -> { spawns = {...}, pins = {...}, skipped } | nil, reason
--   LearnedTransfer.Import(text) -> counts | nil, reason
local Transfer = {}
addon.VignetteRadarLearnedTransfer = Transfer

local type, ipairs, pairs, tonumber, tostring, floor = type, ipairs, pairs, tonumber, tostring, math.floor
local format, concat = string.format, table.concat
local Number, Integer = addon.Secret.Number, addon.Secret.Integer

Transfer.VERSION = "VRL1"
Transfer.MAX_BYTES = 65536
Transfer.MAX_RECORDS = 4000
local MAX_PINS = 60
local EPOCH_MAX = 4102444800 -- 2100-01-01
local WORLD_LIMIT = 1e6

local function Log(fmt, ...)
    if addon.Trace then addon.Trace.Log("transfer", fmt, ...) end
end

local function Settings() return addon.GetSettings() end

-- Additive checksum over the body: catches a cut or mangled copy.
local function Checksum(body)
    local sum = 0
    for index = 1, #body do sum = (sum * 31 + body:byte(index)) % 16777213 end
    return format("%06x", sum)
end

local function EncodeName(value)
    value = type(value) == "string" and value or ""
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c|]", ""):sub(1, 80)
    return (value:gsub("[^%w]", function(char) return format("%%%02X", char:byte()) end))
end

local function DecodeName(value)
    if type(value) ~= "string" or #value > 240 or not value:match("^[%w%%]*$") then return nil end
    local bad = false
    local name = value:gsub("%%(..)", function(hex)
        local byte = hex:match("^%x%x$") and tonumber(hex, 16)
        if not byte then bad = true; return "" end
        return string.char(byte)
    end)
    if bad or name:find("[%c|]") or #name > 80 then return nil end
    name = name:match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

local function Num(value, digits)
    if not Number(value) then return "" end
    if digits == 0 then return tostring(floor(value + .5)) end
    return (format("%." .. digits .. "f", value):gsub("%.?0+$", ""))
end

-- A field: "" for missing (only where optional), else a number in range.
local function Field(value, minimum, maximum, whole, optional)
    if value == "" then return optional and false or nil end
    if type(value) ~= "string" or #value > 24 or not value:match("^%-?%d+%.?%d*$") then return nil end
    local number = tonumber(value)
    if whole then return Integer(number, minimum, maximum) end
    number = Number(number)
    if not number or number < minimum or number > maximum then return nil end
    return number
end

local function Split(record)
    local fields = {}
    for field in (record .. ","):gmatch("([^,]*),") do
        fields[#fields + 1] = field
        if #fields > 16 then return nil end
    end
    return fields
end

local function SpawnRecord(npcID, name, spawn)
    return concat({ "S", npcID, EncodeName(name), spawn.m, Num(spawn.x, 1), Num(spawn.y, 1), Num(spawn.z, 1),
        Num(spawn.i, 0), Num(spawn.mx, 5), Num(spawn.my, 5), Num(spawn.n or 1, 0), Num(spawn.f or 0, 0),
        Num(spawn.l or 0, 0) }, ",")
end

local function PinRecord(pin)
    return concat({ "P", EncodeName(pin.name), pin.mapID, Num(pin.mapX, 5), Num(pin.mapY, 5),
        Num(pin.worldX, 1), Num(pin.worldY, 1), Num(pin.instanceID, 0), Num(pin.at or 0, 0) }, ",")
end

function Transfer.Export(scope, mapID)
    local db = Settings()
    mapID = Number(mapID)
    if scope == "zone" and not mapID then return nil, "Zone unknown" end
    local records = {}
    local function Wanted(id) return scope ~= "zone" or id == mapID end
    for npcID, entry in pairs(type(db.vignetteRadarRareSpawns) == "table" and db.vignetteRadarRareSpawns or {}) do
        if Integer(npcID, 1) and type(entry) == "table" and type(entry.spawns) == "table" then
            for _, spawn in ipairs(entry.spawns) do
                if type(spawn) == "table" and Integer(spawn.m, 1) and Number(spawn.x) and Number(spawn.y)
                    and Number(spawn.mx) and Number(spawn.my) and Wanted(spawn.m) then
                    records[#records + 1] = { at = Number(spawn.l) or 0, text = SpawnRecord(npcID, entry.name, spawn) }
                end
            end
        end
    end
    for _, pin in ipairs(type(db.vignetteRadarPins) == "table" and db.vignetteRadarPins or {}) do
        if type(pin) == "table" and Integer(pin.mapID, 1) and Number(pin.mapX) and Number(pin.mapY)
            and Number(pin.worldX) and Number(pin.worldY) and Wanted(pin.mapID) then
            records[#records + 1] = { at = math.huge, text = PinRecord(pin) }
        end
    end
    if #records == 0 then return nil, "No learned spawns or pins to export" end
    -- Pins first, then the newest spawns, until the size cap.
    table.sort(records, function(a, b) return a.at > b.at end)
    local body, size, kept = {}, 0, 0
    for _, record in ipairs(records) do
        if size + #record.text + 1 > Transfer.MAX_BYTES - 64 or kept >= Transfer.MAX_RECORDS then break end
        body[#body + 1] = record.text
        size, kept = size + #record.text + 1, kept + 1
    end
    local text = concat(body, "~")
    local result = Transfer.VERSION .. ":" .. kept .. ":" .. Checksum(text) .. ":" .. text
    Log("export scope=%s %d of %d records, %d bytes", scope or "all", kept, #records, #result)
    return result, { records = kept, total = #records }
end

function Transfer.Decode(text)
    if type(text) ~= "string" or addon.Secret.IsSecret(text) then return nil, "Paste an export string first" end
    if #text > Transfer.MAX_BYTES then return nil, "Too large (over 64 KB)" end
    text = text:gsub("%s+", "")
    local version, count, sum, body = text:match("^(%w+):(%d+):(%x+):(.*)$")
    if not version then return nil, "Not a VignetteRadar export" end
    if version ~= Transfer.VERSION then return nil, "Unsupported version " .. version:sub(1, 8) end
    count = Integer(tonumber(count), 0, Transfer.MAX_RECORDS)
    if not count then return nil, "Too many records" end
    if Checksum(body) ~= sum:lower() then return nil, "Checksum failed: the text was cut or changed" end
    local result = { spawns = {}, pins = {}, skipped = 0 }
    local seen = 0
    for record in (body .. "~"):gmatch("([^~]*)~") do
        seen = seen + 1
        if seen > Transfer.MAX_RECORDS then return nil, "Too many records" end
        local f = Split(record)
        local ok = false
        if f and f[1] == "S" and #f == 13 then
            local spawn = {
                npcID = Field(f[2], 1, 1e7, true), name = DecodeName(f[3]), m = Field(f[4], 1, 1e6, true),
                x = Field(f[5], -WORLD_LIMIT, WORLD_LIMIT), y = Field(f[6], -WORLD_LIMIT, WORLD_LIMIT),
                z = Field(f[7], -WORLD_LIMIT, WORLD_LIMIT, false, true), i = Field(f[8], 0, 1e7, true, true),
                mx = Field(f[9], 0, 1), my = Field(f[10], 0, 1), n = Field(f[11], 1, 100000, true),
                f = Field(f[12], 0, EPOCH_MAX, true), l = Field(f[13], 0, EPOCH_MAX, true),
            }
            if spawn.npcID and spawn.m and spawn.x and spawn.y and spawn.z ~= nil and spawn.i ~= nil
                and spawn.mx and spawn.my and spawn.n and spawn.f and spawn.l and spawn.f <= spawn.l then
                spawn.z, spawn.i = spawn.z or nil, spawn.i or nil
                result.spawns[#result.spawns + 1] = spawn
                ok = true
            end
        elseif f and f[1] == "P" and #f == 9 then
            local pin = { name = DecodeName(f[2]) or "Imported Pin", mapID = Field(f[3], 1, 1e6, true),
                mapX = Field(f[4], 0, 1), mapY = Field(f[5], 0, 1),
                worldX = Field(f[6], -WORLD_LIMIT, WORLD_LIMIT), worldY = Field(f[7], -WORLD_LIMIT, WORLD_LIMIT),
                instanceID = Field(f[8], 0, 1e7, true, true), at = Field(f[9], 0, EPOCH_MAX, true) }
            if pin.mapID and pin.mapX and pin.mapY and pin.worldX and pin.worldY and pin.instanceID ~= nil
                and pin.at then
                pin.instanceID = pin.instanceID or nil
                result.pins[#result.pins + 1] = pin
                ok = true
            end
        end
        if not ok then result.skipped = result.skipped + 1 end
    end
    if seen ~= count then return nil, "Record count does not match" end
    return result
end

local function SamePin(a, b)
    return a.mapID == b.mapID and math.abs((a.mapX or -1) - b.mapX) < .001 and math.abs((a.mapY or -1) - b.mapY) < .001
end

function Transfer.Import(text)
    local data, reason = Transfer.Decode(text)
    if not data then
        Log("import refused: %s", reason)
        return nil, reason
    end
    local counts = { spawnsAdded = 0, spawnsMerged = 0, pinsAdded = 0, pinsSkipped = 0, skipped = data.skipped }
    local spawns = addon.VignetteRadarRareSpawns
    if spawns and spawns.Import then
        local byNpc, order = {}, {}
        for _, spawn in ipairs(data.spawns) do
            local group = byNpc[spawn.npcID]
            if not group then
                group = { name = spawn.name, list = {} }
                byNpc[spawn.npcID] = group
                order[#order + 1] = spawn.npcID
            end
            group.list[#group.list + 1] = spawn
        end
        for _, npcID in ipairs(order) do
            local added, merged = spawns.Import(npcID, byNpc[npcID].name, byNpc[npcID].list)
            counts.spawnsAdded, counts.spawnsMerged = counts.spawnsAdded + added, counts.spawnsMerged + merged
        end
    end
    local db = Settings()
    if type(db.vignetteRadarPins) ~= "table" then db.vignetteRadarPins = {} end
    local pins = db.vignetteRadarPins
    for index, pin in ipairs(data.pins) do
        local duplicate = false
        for _, existing in ipairs(pins) do
            if type(existing) == "table" and SamePin(existing, pin) then duplicate = true; break end
        end
        if duplicate or #pins >= MAX_PINS then
            counts.pinsSkipped = counts.pinsSkipped + 1
        else
            pin.id = "import-" .. tostring(pin.at) .. "-" .. index .. "-" .. #pins
            pins[#pins + 1] = pin
            counts.pinsAdded = counts.pinsAdded + 1
        end
    end
    local exploration = addon.VignetteRadarExploration
    if counts.pinsAdded > 0 and exploration and type(exploration.RefreshPanel) == "function" then
        pcall(exploration.RefreshPanel)
    end
    local radar = addon.VignetteRadarAPI
    if radar and type(radar.RefreshMapData) == "function" then pcall(radar.RefreshMapData) end
    Log("import: spawns +%d merged %d, pins +%d skipped %d, bad records %d", counts.spawnsAdded,
        counts.spawnsMerged, counts.pinsAdded, counts.pinsSkipped, counts.skipped)
    return counts
end

-- One readable line for chat and the transfer box.
function Transfer.Summary(counts)
    if type(counts) ~= "table" then return "" end
    return format("Imported %d new spawns (%d merged) and %d pins%s%s.", counts.spawnsAdded, counts.spawnsMerged,
        counts.pinsAdded, counts.pinsSkipped > 0 and (", " .. counts.pinsSkipped .. " pins skipped") or "",
        counts.skipped > 0 and (", " .. counts.skipped .. " bad records ignored") or "")
end

return Transfer
