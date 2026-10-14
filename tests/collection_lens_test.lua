-- luacheck: globals VignetteRadarDB WaffleHouseDB PlayerHasToy
-- Real Collection Lens: pack loot read from Zarillion (rewards +
-- display_option) and Kemayo (loot + classname, or raw) nodes; status per
-- point; live vignettes borrow loot by npc; marks, facts and the Declutter
-- filter; "no loot data" when a pack lists none.
VignetteRadarDB, WaffleHouseDB = nil, nil
_G.GetTime = function() return 100 end
local mounts = { [2001] = false, [2002] = true }
local toys = { [3001] = true }
_G.C_MountJournal = {
    GetMountFromItem = function(itemID) return itemID == 9002 and 2002 or nil end,
    GetMountInfoByID = function(id) return "M", 1, 1, false, true, 0, false, false, nil, false, mounts[id], id end,
}
_G.PlayerHasToy = function(itemID) return toys[itemID] == true end
_G.C_PetJournal = {
    GetPetInfoByItemID = function(itemID)
        if itemID == 4001 then return "P", 1, 1, 1, "", "", false, true, true, true, true, 1, 55 end
    end,
    GetNumCollectedInfo = function(species) return species == 55 and 0 or 1, 3 end,
}
local requested = {}
_G.C_TransmogCollection = {
    GetItemInfo = function(itemID) if itemID == 5001 then return 10, 500 elseif itemID == 5002 then return 11, 501 end end,
    PlayerCanCollectSource = function(source) return true, source ~= 501 end,
    PlayerHasTransmogItemModifiedAppearance = function() return false end,
    PlayerHasTransmog = function() return false end,
}
_G.C_Item = {
    GetItemInfoInstant = function(itemID)
        return itemID, "", "", itemID == 6001 and "INVTYPE_CHEST" or "", 1, 4, 1
    end,
    RequestLoadItemDataByID = function(itemID) requested[itemID] = true end,
}
local addon = {}
assert(loadfile("Core/Secret.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Core.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Bus.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Points.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Guidance.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Recent.lua"))("VignetteRadar", addon)
assert(loadfile("Core/Declutter.lua"))("VignetteRadar", addon)
assert(loadfile("Data/CollectionLens.lua"))("VignetteRadar", addon)
local Lens = assert(addon.VignetteRadarCollectionLens)
local settings = addon.GetSettings()
assert(settings.vignetteRadarCollectionLens == "mark" and Lens.Mode() == "mark", "default mark")

-- Zarillion-style reward instances: kind from the class's display_option.
local function Class(attrs) return { __index = attrs } end
local MountClass = Class({ display_option = "show_mount_rewards" })
local ToyClass = Class({ display_option = "show_toy_rewards" })
local AchievementClass = Class({ type = "achievement" })
local zNode = { rewards = {
    setmetatable({ item = 9001, id = 2001 }, MountClass),
    setmetatable({ item = 3001 }, ToyClass),
    setmetatable({ id = 1 }, AchievementClass),
} }
local loot = Lens.Read(zNode)
assert(#loot == 2 and loot[1].k == "mount" and loot[1].id == 2001 and loot[2].k == "toy", "Zarillion rewards")
assert(Lens.Read(zNode) == loot, "read once per node")
-- Kemayo-style objects and raw data.
local kNode = { loot = {
    setmetatable({ id = 9002 }, Class({ classname = "Mount" })),
    { 4001, pet = true },
    6001,
    7001,
} }
local kLoot = Lens.Read(kNode)
assert(#kLoot == 4 and kLoot[1].k == "mount" and kLoot[2].k == "pet" and kLoot[3].k == "item", "Kemayo loot")
assert(Lens.Read({ name = "plain" }) == nil, "no list is no loot data")
assert(#Lens.Read({ rewards = { setmetatable({}, AchievementClass) } }) == 0, "a list without collectibles")

-- Status per point.
local rare = { kind = "mob", npcID = 42, loot = loot }
local status, missing = Lens.Status(rare)
assert(status == "lack" and missing[1] == "Mount", "missing mount")
mounts[2001] = true
assert(Lens.Status(rare) == "lack", "cached until a collection event")
Lens.Invalidate()
assert(Lens.Status(rare) == "have", "all collected after the mount was learned")
-- Kemayo: owned mount, missing pet, chest look 6001 is loading, 7001 is not gear.
status, missing = Lens.Status({ kind = "treasure", loot = kLoot })
assert(status == "lack" and missing[1] == "Pet" and requested[6001], "pet missing, look requested")
assert(Lens.Status({ kind = "treasure", loot = {} }) == "none", "nothing collectible")
assert(Lens.Status({ kind = "treasure" }) == nil, "no loot data")
assert(Lens.Status({ kind = "quest", loot = kLoot }) == nil, "quests are not lensed")
-- An appearance this class cannot collect is skipped.
assert(Lens.Status({ kind = "treasure", loot = { { k = "transmog", item = 5002 } } }) == "none")
assert(Lens.Status({ kind = "treasure", loot = { { k = "transmog", item = 5001 } } }) == "lack")

-- Live vignettes borrow the pack note's loot by npc.
local note = { key = "pack:1", kind = "mob", npcID = 77, loot = kLoot, worldX = 0, worldY = 0 }
assert(Lens.Learn({ note }) >= 1)
local live = { category = "rare", objectGUID = "Creature-0-1-2-3-77-0000000001" }
assert(Lens.LootFor(live) == kLoot and Lens.Status(live) == "lack", "live rare uses pack loot")

-- Facts.
local line = Lens.FactLine(live)
assert(line[1] == "Loot" and line[2] == "Missing Pet", "fact row: " .. tostring(line[2]))
assert(Lens.FactLine({ kind = "treasure" })[2] == "No Loot Data")
local facts = addon.VignetteRadarGuidance.FactLines({ kind = "treasure", key = "t" })
local found
for _, fact in ipairs(facts) do if fact[1] == "Loot" then found = fact[2] end end
assert(found == "No Loot Data", "Guidance facts carry the loot row")

-- Mark: a badge only on "lack".
local created
local region = { CreateTexture = function()
    created = { SetSize = function() end, SetPoint = function() end, SetAtlas = function() end,
        Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end }
    return created
end }
assert(Lens.Mark(region, live) and created.shown, "marked")
assert(not Lens.Mark(region, rare) and not created.shown, "collected: no mark")
settings.vignetteRadarCollectionLens = "off"
assert(not Lens.Mark(region, live) and Lens.FactLine(live) == nil, "off")

-- Declutter filter.
local haveNote = { key = "a", kind = "mob", loot = loot, worldX = 0, worldY = 0 }
local noneNote = { key = "b", kind = "treasure", worldX = 0, worldY = 0 }
local lackNote = { key = "c", kind = "treasure", loot = kLoot, worldX = 0, worldY = 0 }
settings.vignetteRadarDeclutter = false
settings.vignetteRadarCollectionLens = "hide"
local kept = addon.VignetteRadarDeclutter.Apply({ haveNote, noneNote, lackNote }, {}, nil, settings)
assert(#kept == 2 and kept[1] == noneNote and addon.VignetteRadarDeclutter.LastCounts().collected == 1,
    "hide collected keeps no-data notes")
settings.vignetteRadarCollectionLens = "only"
kept = addon.VignetteRadarDeclutter.Apply({ haveNote, noneNote, lackNote }, {}, nil, settings)
assert(#kept == 1 and kept[1] == lackNote, "only uncollected")
settings.vignetteRadarCollectionLens = "mark"
assert(#addon.VignetteRadarDeclutter.Apply({ haveNote, noneNote }, {}, nil, settings) == 2, "mark never hides")
print("collection_lens_test ok")
