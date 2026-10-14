local _, addon = ...
if type(addon) ~= "table" then return end

-- Real Collection Lens: marks or filters rares and treasures by whether their
-- loot holds a mount, pet, toy or appearance this character has not
-- collected. No WoW API maps a rare to its loot, so loot comes only from map
-- pack data, read once per pack node by POIs.Collect:
--   Zarillion packs (HandyNotes_Midnight, _TheWarWithin, ...): node.rewards,
--     reward objects whose class carries display_option show_mount_rewards /
--     show_pet_rewards / show_toy_rewards / show_transmog_rewards, with
--     item (itemID) and id (mountID or speciesID).
--   Kemayo packs (HandyNotes_MidnightTreasures, ...): node.loot, reward
--     objects with classname Mount / Pet / Toy / Item and id (itemID),
--     mountid, petid; or the raw data form { itemID, mount=, pet=, toy= }.
-- A note with no such list (other packs, VR's saved pack copies, learned
-- spawns) has no loot data; the lens then says so and never hides it for
-- that alone, except in "only" mode, which keeps only proven targets.
-- Live vignettes borrow the loot of the pack note with the same npc, object
-- or quest (Lens.Learn indexes the scan's notes).
--   Lens.Read(node) -> loot | nil          Lens.Learn(notes)
--   Lens.LootFor(item) -> loot | nil       Lens.Status(item) -> status, missing
--   Lens.Hide(note [, settings]) -> bool   Lens.Mark(region, item) -> shown
--   Lens.Mode([settings]) -> "off" | "mark" | "hide" | "only"
--   Lens.FactLine(item) -> { "Loot", text } | nil
-- status: "lack" (something to collect), "have" (all collected), "none" (loot
-- known, nothing collectible here), "pending" (item data still loading), or
-- nil (no loot data). A loot entry: { k = mount|pet|toy|transmog|item,
-- item = itemID, id = mountID or speciesID }.
local Lens = {}
addon.VignetteRadarCollectionLens = Lens

local type, ipairs, pcall, tostring, tonumber = type, ipairs, pcall, tostring, tonumber
local Field, Number, Text, Safe, Call = addon.Secret.Field, addon.Secret.Number, addon.Secret.Text,
    addon.Secret.Safe, addon.Secret.Call

local MODES = { off = true, mark = true, hide = true, only = true }
local LENS_KINDS = { rare = true, mob = true, treasure = true }
local DISPLAY_KINDS = { show_mount_rewards = "mount", show_pet_rewards = "pet", show_toy_rewards = "toy",
    show_transmog_rewards = "transmog" }
local CLASS_KINDS = { Mount = "mount", Pet = "pet", Toy = "toy", Item = "item" }
local KIND_LABELS = { mount = "Mount", pet = "Pet", toy = "Toy", transmog = "Look", item = "Look" }
local LABEL_ORDER = { "Mount", "Pet", "Toy", "Look" }
local MAX_ENTRIES = 24
local MARK_ATLAS = "VignetteLoot"

local NONE = {}
local readCache = setmetatable({}, { __mode = "k" })   -- node -> loot or NONE
local lootCache = setmetatable({}, { __mode = "k" })   -- item -> { gen, loot }
local statusCache = setmetatable({}, { __mode = "k" }) -- loot -> { gen, status, missing }
local learned = setmetatable({}, { __mode = "k" })     -- note -> true
local index = {}                                        -- "npc:ID" / "obj:ID" / "q:ID" -> loot
local owned = {}                                        -- "kind:item" -> true | false | "skip"
local generation, indexGeneration = 0, 0
local waiting = false                                   -- item data asked for, not yet in

local function Settings() return addon.GetSettings() end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace then trace.Log("lens", fmt, ...) end
end

function Lens.Mode(settings)
    local mode = (settings or Settings()).vignetteRadarCollectionLens
    return MODES[mode] and mode or "off"
end

-- Item and collection data changed: every answer is asked again.
function Lens.Invalidate()
    owned = {}
    generation = generation + 1
end

-- Reward readers -------------------------------------------------------------

local function Whole(value)
    value = Number(value)
    return value and value > 0 and value == math.floor(value) and value or nil
end

local function Entry(reward)
    local itemID = Whole(reward)
    if itemID then return { k = "item", item = itemID } end
    if type(reward) ~= "table" then return nil end
    -- Zarillion: the class's display_option names the kind.
    local kind = DISPLAY_KINDS[Text(Field(reward, "display_option")) or ""]
    if kind then
        itemID = Whole(Field(reward, "item"))
        local id = (kind == "mount" or kind == "pet") and Whole(Field(reward, "id")) or nil
        if itemID or id then return { k = kind, item = itemID, id = id } end
        return nil
    end
    -- Kemayo reward objects.
    kind = CLASS_KINDS[Text(Field(reward, "classname")) or ""]
    if kind then
        itemID = Whole(Field(reward, "id"))
        local id = kind == "mount" and Whole(Field(reward, "mountid"))
            or kind == "pet" and Whole(Field(reward, "petid")) or nil
        if itemID then return { k = kind, item = itemID, id = id } end
        return nil
    end
    -- Kemayo raw data: { itemID, mount = true | mountID, pet = ..., toy = true }.
    itemID = Whole(Field(reward, 1))
    if not itemID then return nil end
    local mount, pet = Field(reward, "mount"), Field(reward, "pet")
    if mount then return { k = "mount", item = itemID, id = Whole(mount) } end
    if pet then return { k = "pet", item = itemID, id = Whole(pet) } end
    if Field(reward, "toy") then return { k = "toy", item = itemID } end
    if Field(reward, "decor") or Field(reward, "set") then return nil end
    return { k = "item", item = itemID }
end

local function AddList(loot, list)
    if type(list) ~= "table" then return false end
    for position = 1, MAX_ENTRIES do
        local reward = Field(list, position)
        if reward == nil then break end
        local entry = Entry(reward)
        if entry then loot[#loot + 1] = entry end
    end
    return true
end

-- The node's loot (possibly empty when the pack lists only currency or
-- achievements), or nil when the pack gives no loot list at all.
function Lens.Read(node)
    if type(node) ~= "table" then return nil end
    local cached = readCache[node]
    if cached then return cached ~= NONE and cached or nil end
    local loot = {}
    local listed = AddList(loot, Field(node, "rewards"))
    listed = AddList(loot, Field(node, "loot")) or listed
    readCache[node] = listed and loot or NONE
    return listed and loot or nil
end

-- Lookups -------------------------------------------------------------------

local function GuidIDs(guid)
    guid = Text(guid)
    if not guid then return nil end
    local kind, id = guid:match("^([A-Za-z]+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    id = tonumber(id)
    if kind == "Creature" or kind == "Vehicle" then return id, nil end
    if kind == "GameObject" then return nil, id end
    return nil
end

local function Keys(item)
    local npc, object = GuidIDs(Field(item, "objectGUID"))
    npc = Whole(Field(item, "npcID")) or npc
    object = Whole(Field(item, "objectID")) or object
    local quest = Whole(Field(item, "rewardQuestID")) or Whole(Field(item, "questID"))
    return npc and ("npc:" .. npc), object and ("obj:" .. object), quest and ("q:" .. quest)
end

-- Indexes the loot of the scan's pack notes by npc, object and quest, so a
-- live vignette (or a fused note) finds its pack's loot.
function Lens.Learn(notes)
    if type(notes) ~= "table" then return 0 end
    local added = 0
    for _, note in ipairs(notes) do
        if type(note) == "table" and not learned[note] then
            learned[note] = true
            local loot = Field(note, "loot")
            if type(loot) == "table" then
                local a, b, c = Keys(note)
                if a and index[a] ~= loot then index[a] = loot; added = added + 1 end
                if b and index[b] ~= loot then index[b] = loot; added = added + 1 end
                if c and index[c] ~= loot then index[c] = loot; added = added + 1 end
            end
        end
    end
    if added > 0 then
        indexGeneration = indexGeneration + 1
        Trace("indexed %d loot keys", added)
    end
    return added
end

function Lens.LootFor(item)
    if type(item) ~= "table" then return nil end
    local loot = Field(item, "loot")
    if type(loot) == "table" then return loot end
    local cached = lootCache[item]
    if cached and cached.gen == indexGeneration then return cached.loot end
    local a, b, c = Keys(item)
    loot = a and index[a] or b and index[b] or c and index[c] or nil
    lootCache[item] = { gen = indexGeneration, loot = loot }
    return loot
end

-- Collection checks ---------------------------------------------------------

-- owner[name](...) and its nth result, guarded like Secret.Call.
local function Nth(n, owner, name, ...)
    local fn = Field(owner, name)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    local value = results[n + 1]
    if not Safe(value) then return nil end
    return value
end

local function RequestItem(itemID)
    waiting = true
    Call(C_Item, "RequestLoadItemDataByID", itemID)
    return nil
end

-- true owned, false missing, nil unknown yet, "skip" not collectible here.
local function Appearance(itemID, strict)
    local _, sourceID = Call(C_TransmogCollection, "GetItemInfo", itemID)
    sourceID = Whole(sourceID)
    if not sourceID then
        if strict then return RequestItem(itemID) end
        -- A plain loot item: only equippable gear can hold an appearance.
        local equipLoc = Nth(4, C_Item, "GetItemInfoInstant", itemID)
        if type(equipLoc) ~= "string" or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE"
            or equipLoc == "INVTYPE_BAG" then return "skip" end
        return RequestItem(itemID)
    end
    local hasData, canCollect = Call(C_TransmogCollection, "PlayerCanCollectSource", sourceID)
    if hasData == true and canCollect == false then return "skip" end
    if Call(C_TransmogCollection, "PlayerHasTransmogItemModifiedAppearance", sourceID) == true then return true end
    return Call(C_TransmogCollection, "PlayerHasTransmog", itemID) == true
end

local CHECKS = {
    mount = function(entry)
        local mountID = entry.id or Whole(Call(C_MountJournal, "GetMountFromItem", entry.item))
        if not mountID then return nil end
        local collected = Nth(11, C_MountJournal, "GetMountInfoByID", mountID)
        if collected == nil then return nil end
        return collected == true
    end,
    pet = function(entry)
        local speciesID = entry.id or Whole(Nth(13, C_PetJournal, "GetPetInfoByItemID", entry.item))
        if not speciesID then return entry.item and RequestItem(entry.item) or nil end
        local count = Number(Call(C_PetJournal, "GetNumCollectedInfo", speciesID))
        if not count then return nil end
        return count > 0
    end,
    toy = function(entry)
        if not entry.item then return nil end
        local fn = _G.PlayerHasToy
        if type(fn) ~= "function" then return nil end
        local ok, has = pcall(fn, entry.item)
        if not ok or not Safe(has) then return nil end
        return has == true
    end,
    transmog = function(entry)
        if entry.item then return Appearance(entry.item, true) end
    end,
    item = function(entry)
        if entry.item then return Appearance(entry.item, false) end
    end,
}

local function Owned(entry)
    local key = entry.k .. ":" .. tostring(entry.item or entry.id)
    local value = owned[key]
    if value ~= nil then return value end
    local check = CHECKS[entry.k]
    value = check and check(entry)
    if value ~= nil then owned[key] = value end
    return value
end

local function Missing(loot)
    local cached = statusCache[loot]
    if cached and cached.gen == generation then return cached.status, cached.missing end
    local lack, have, pending, labels, seen = 0, 0, 0, {}, {}
    for _, entry in ipairs(loot) do
        local value = Owned(entry)
        if value == false then
            lack = lack + 1
            local label = KIND_LABELS[entry.k]
            if label and not seen[label] then seen[label] = true end
        elseif value == true then have = have + 1
        elseif value == nil then pending = pending + 1 end
    end
    for _, label in ipairs(LABEL_ORDER) do
        if seen[label] then labels[#labels + 1] = label end
    end
    local status = lack > 0 and "lack" or pending > 0 and "pending" or have > 0 and "have" or "none"
    statusCache[loot] = { gen = generation, status = status, missing = labels }
    return status, labels
end

local function LensKind(item)
    local kind = Text(Field(item, "kind")) or Text(Field(item, "category"))
    return kind and LENS_KINDS[kind] or false
end

-- status, missing labels; nil when the item is not a rare or treasure, or
-- when no pack gives its loot.
function Lens.Status(item)
    if type(item) ~= "table" or not LensKind(item) then return nil end
    local loot = Lens.LootFor(item)
    if type(loot) ~= "table" then return nil end
    return Missing(loot)
end

-- Declutter's "collected" reason: "hide" drops notes whose loot is all
-- collected; "only" keeps just notes that drop something you lack (and the
-- ones still loading).
function Lens.Hide(note, settings)
    local mode = Lens.Mode(settings)
    if (mode ~= "hide" and mode ~= "only") or not LensKind(note) then return false end
    local status = Lens.Status(note)
    if mode == "hide" then return status == "have" end
    return status ~= "lack" and status ~= "pending"
end

-- A small loot badge on a radar marker that drops something you lack.
function Lens.Mark(region, item)
    if type(region) ~= "table" then return false end
    local show = Lens.Mode() ~= "off" and Lens.Status(item) == "lack"
    local mark = region.vrLensMark
    if not show then
        if mark then mark:Hide() end
        return false
    end
    if not mark then
        mark = region:CreateTexture(nil, "OVERLAY")
        mark:SetSize(10, 10)
        mark:SetPoint("CENTER", region, "TOPLEFT", 1, -1)
        if not pcall(mark.SetAtlas, mark, MARK_ATLAS) then mark:SetColorTexture(1, .82, .3, .9) end
        region.vrLensMark = mark
    end
    mark:Show()
    return true
end

local FACT_TEXT = { have = "All Collected", none = "No Collectibles", pending = "Checking" }

-- The Guide Panel / tooltip fact row.
function Lens.FactLine(item)
    if Lens.Mode() == "off" or type(item) ~= "table" or not LensKind(item) then return nil end
    local status, missing = Lens.Status(item)
    if status == "lack" then return { "Loot", "Missing " .. table.concat(missing, ", ") } end
    return { "Loot", FACT_TEXT[status] or "No Loot Data" }
end

function Lens.Generation() return generation, indexGeneration end

-- Fact row for Core/Guidance.lua's facts block (a provider list it reads).
local guidance = addon.VignetteRadarGuidance
if guidance and type(guidance.FactProviders) == "table" then
    guidance.FactProviders[#guidance.FactProviders + 1] = function(lines, item)
        local line = Lens.FactLine(item)
        if line then lines[#lines + 1] = line end
    end
end

if addon.Bus then
    local function Changed(event)
        -- Item data arrives for every item the game loads; only ours matter.
        if event == "GET_ITEM_INFO_RECEIVED" then
            if not waiting then return end
            waiting = false
        end
        Trace("collections changed (%s)", tostring(event))
        Lens.Invalidate()
    end
    for _, event in ipairs({ "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "PET_JOURNAL_LIST_UPDATE", "NEW_TOY_ADDED",
        "TOYS_UPDATED", "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_ADDED",
        "GET_ITEM_INFO_RECEIVED" }) do
        addon.Bus.On(event, Changed, { coalesce = 1 })
    end
end

return Lens
