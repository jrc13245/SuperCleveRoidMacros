--[[
    NampowerAPI.lua - Nampower API Integration Layer

    Provides wrapper functions for Nampower's extended Lua API with fallbacks
    for older versions or when functions are unavailable.

    New Nampower Functions Wrapped:
    - GetSpellRec / GetSpellRecField - Spell record data from client DB
    - GetItemStats / GetItemStatsField - Item stats from client DB
    - GetUnitData / GetUnitField - Low-level unit field access
    - GetSpellModifiers - Spell modifier calculations (talents, buffs, etc.)

    Enhanced Functions (now accept spell name or "spellId:number"):
    - GetSpellTexture, GetSpellName, GetSpellCooldown, GetSpellAutocast
    - ToggleSpellAutocast, PickupSpell, CastSpell, IsCurrentCast, IsSpellPassive

    Settings Integration:
    - Reads from NampowerSettings addon when available
    - Falls back to CVars when addon not present
]]

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids

-- Nampower API namespace
CleveRoids.NampowerAPI = CleveRoids.NampowerAPI or {}
local API = CleveRoids.NampowerAPI

--------------------------------------------------------------------------------
-- VERSION DETECTION
--------------------------------------------------------------------------------

-- Get Nampower version as major, minor, patch
-- Returns 0, 0, 0 if Nampower not installed
function API.GetVersion()
    if GetNampowerVersion then
        local major, minor, patch = GetNampowerVersion()
        return major or 0, minor or 0, patch or 0
    end
    return 0, 0, 0
end

-- Check if installed version meets minimum requirement
function API.HasMinimumVersion(reqMajor, reqMinor, reqPatch)
    local major, minor, patch = API.GetVersion()

    if major > reqMajor then
        return true
    elseif major == reqMajor then
        if minor > reqMinor then
            return true
        elseif minor == reqMinor and patch >= reqPatch then
            return true
        end
    end
    return false
end

-- Feature flags based on version
API.features = {
    -- Base Nampower features (v2.0+)
    hasNampower = (QueueSpellByName ~= nil),
    hasSpellQueue = (QueueSpellByName ~= nil),
    hasIsSpellInRange = (IsSpellInRange ~= nil),
    hasGetCurrentCastingInfo = (GetCurrentCastingInfo ~= nil),
    hasGetSpellIdForName = (GetSpellIdForName ~= nil),

    -- Extended API (v2.8+)
    hasGetSpellRec = (GetSpellRec ~= nil),
    hasGetSpellRecField = (GetSpellRecField ~= nil),
    hasGetItemStats = (GetItemStats ~= nil),
    hasGetItemStatsField = (GetItemStatsField ~= nil),
    hasGetUnitData = (GetUnitData ~= nil),
    hasGetUnitField = (GetUnitField ~= nil),
    hasGetSpellModifiers = (GetSpellModifiers ~= nil),

    -- Enhanced spell functions (accept name/"spellId:number")
    hasEnhancedSpellFunctions = false,  -- Detected at runtime

    -- v2.18+ APIs (inventory/equipment/cast info)
    hasFindPlayerItemSlot = (FindPlayerItemSlot ~= nil),
    hasGetEquippedItems = (GetEquippedItems ~= nil),
    hasGetEquippedItem = (GetEquippedItem ~= nil),
    hasGetBagItems = (GetBagItems ~= nil),
    hasGetBagItem = (GetBagItem ~= nil),
    hasGetCastInfo = (GetCastInfo ~= nil),
    hasGetSpellIdCooldown = (GetSpellIdCooldown ~= nil),
    hasGetItemIdCooldown = (GetItemIdCooldown ~= nil),
    hasChannelStopCastingNextTick = (ChannelStopCastingNextTick ~= nil),
}

-- Detect if enhanced spell functions are available (accept name/spellId:number)
local function DetectEnhancedSpellFunctions()
    if not GetSpellTexture then return false end

    -- Try calling GetSpellTexture with a spell name
    -- If it doesn't error and returns something, enhanced functions are available
    local success, result = pcall(function()
        -- Use "Attack" which should exist for all characters
        return GetSpellTexture("Attack")
    end)

    API.features.hasEnhancedSpellFunctions = success and (result ~= nil)
    return API.features.hasEnhancedSpellFunctions
end

--------------------------------------------------------------------------------
-- NAMPOWER SETTINGS ACCESS
--------------------------------------------------------------------------------

-- Cache for settings to avoid repeated lookups
API.settingsCache = {}
API.settingsCacheTime = 0
API.SETTINGS_CACHE_DURATION = 5  -- Refresh every 5 seconds

-- All known Nampower CVars with their defaults
API.defaultSettings = {
    NP_QueueCastTimeSpells = "1",
    NP_QueueInstantSpells = "1",
    NP_QueueChannelingSpells = "1",
    NP_QueueTargetingSpells = "1",
    NP_QueueOnSwingSpells = "0",
    NP_QueueSpellsOnCooldown = "1",
    NP_InterruptChannelsOutsideQueueWindow = "0",
    NP_SpellQueueWindowMs = "500",
    NP_OnSwingBufferCooldownMs = "500",
    NP_ChannelQueueWindowMs = "1500",
    NP_TargetingQueueWindowMs = "500",
    NP_CooldownQueueWindowMs = "250",
    NP_MinBufferTimeMs = "55",
    NP_NonGcdBufferTimeMs = "100",
    NP_MaxBufferIncreaseMs = "30",
    NP_RetryServerRejectedSpells = "1",
    NP_QuickcastTargetingSpells = "0",
    NP_QuickcastOnDoubleCast = "0",  -- v2.18+: cast targeting spells by double-casting
    NP_ReplaceMatchingNonGcdCategory = "0",
    NP_OptimizeBufferUsingPacketTimings = "0",
    NP_PreventRightClickTargetChange = "0",
    NP_PreventRightClickPvPAttack = "1",
    NP_DoubleCastToEndChannelEarly = "0",
    NP_SpamProtectionEnabled = "1",
    NP_ChannelLatencyReductionPercentage = "75",
    NP_NameplateDistance = "41",
}

-- Get a Nampower setting value
-- Priority: NampowerSettings addon (per-character) > CVar > default
function API.GetSetting(settingName)
    -- Check if NampowerSettings addon is loaded and has per-character settings enabled
    if Nampower and Nampower.db and Nampower.db.profile then
        if Nampower.db.profile.per_character_settings and Nampower.db.profile[settingName] ~= nil then
            return Nampower.db.profile[settingName]
        end
    end

    -- Fall back to CVar
    local cvarValue = GetCVar(settingName)
    if cvarValue then
        return cvarValue
    end

    -- Return default if known
    return API.defaultSettings[settingName]
end

-- Get a Nampower setting as a boolean
function API.GetSettingBool(settingName)
    local value = API.GetSetting(settingName)
    if type(value) == "boolean" then
        return value
    end
    return value == "1" or value == true
end

-- Get a Nampower setting as a number
function API.GetSettingNumber(settingName)
    local value = API.GetSetting(settingName)
    return tonumber(value) or 0
end

-- Check if spell queuing is enabled for a given spell type
function API.IsQueueingEnabled(spellType)
    if not API.features.hasNampower then
        return false
    end

    if spellType == "cast" or spellType == "casttime" then
        return API.GetSettingBool("NP_QueueCastTimeSpells")
    elseif spellType == "instant" or spellType == "gcd" then
        return API.GetSettingBool("NP_QueueInstantSpells")
    elseif spellType == "channel" or spellType == "channeling" then
        return API.GetSettingBool("NP_QueueChannelingSpells")
    elseif spellType == "targeting" or spellType == "aoe" then
        return API.GetSettingBool("NP_QueueTargetingSpells")
    elseif spellType == "onswing" or spellType == "swing" then
        return API.GetSettingBool("NP_QueueOnSwingSpells")
    elseif spellType == "cooldown" then
        return API.GetSettingBool("NP_QueueSpellsOnCooldown")
    end

    -- Default: all queuing enabled
    return API.GetSettingBool("NP_QueueCastTimeSpells")
end

-- Check if ANY spell queuing is enabled
function API.IsAnyQueueingEnabled()
    if not API.features.hasNampower then
        return false
    end

    -- Check all spell type queuing settings
    return API.GetSettingBool("NP_QueueCastTimeSpells")
        or API.GetSettingBool("NP_QueueInstantSpells")
        or API.GetSettingBool("NP_QueueChannelingSpells")
        or API.GetSettingBool("NP_QueueOnSwingSpells")
end

-- Get the queue window for a given spell type (in seconds)
function API.GetQueueWindow(spellType)
    local ms = 500  -- default

    if spellType == "channel" or spellType == "channeling" then
        ms = API.GetSettingNumber("NP_ChannelQueueWindowMs")
    elseif spellType == "targeting" or spellType == "aoe" then
        ms = API.GetSettingNumber("NP_TargetingQueueWindowMs")
    elseif spellType == "cooldown" then
        ms = API.GetSettingNumber("NP_CooldownQueueWindowMs")
    elseif spellType == "onswing" or spellType == "swing" then
        ms = API.GetSettingNumber("NP_OnSwingBufferCooldownMs")
    else
        ms = API.GetSettingNumber("NP_SpellQueueWindowMs")
    end

    return ms / 1000  -- Convert to seconds
end

--------------------------------------------------------------------------------
-- SPELL RECORD API (GetSpellRec / GetSpellRecField)
--------------------------------------------------------------------------------

-- Cache for spell records
API.spellRecCache = {}

-- Get full spell record data
-- Returns nil if spell not found or API unavailable
function API.GetSpellRecord(spellId)
    if not spellId or spellId == 0 then return nil end

    -- Check cache first
    if API.spellRecCache[spellId] then
        return API.spellRecCache[spellId]
    end

    -- Use native function if available
    if GetSpellRec then
        local rec = GetSpellRec(spellId)
        if rec then
            API.spellRecCache[spellId] = rec
            return rec
        end
    end

    return nil
end

-- Get a specific field from spell record
-- Returns nil if not found, raises error if field name invalid (native behavior)
function API.GetSpellField(spellId, fieldName)
    if not spellId or spellId == 0 then return nil end

    -- Use native function if available (more efficient for single field)
    if GetSpellRecField then
        local success, result = pcall(GetSpellRecField, spellId, fieldName)
        if success then
            return result
        end
        -- If it errors on invalid field name, let it propagate
        -- But if spell just not found, return nil
        return nil
    end

    -- Fallback to full record lookup
    local rec = API.GetSpellRecord(spellId)
    if rec then
        return rec[fieldName]
    end

    return nil
end

-- Get spell name by ID (enhanced, uses new API when available)
function API.GetSpellNameById(spellId)
    if not spellId or spellId == 0 then return nil end

    -- Try GetSpellNameAndRankForId first (Nampower function)
    if GetSpellNameAndRankForId then
        local name, rank = GetSpellNameAndRankForId(spellId)
        if name then return name, rank end
    end

    -- Fall back to SpellInfo (SuperWoW)
    if SpellInfo then
        local name = SpellInfo(spellId)
        if name then return name end
    end

    -- Fall back to GetSpellRecField
    if GetSpellRecField then
        local name = GetSpellRecField(spellId, "name")
        local rank = GetSpellRecField(spellId, "rank")
        if name then return name, rank end
    end

    return nil
end

-- Get spell cast time in seconds
function API.GetSpellCastTime(spellId)
    local castTime = API.GetSpellField(spellId, "castTime")
    if castTime then
        return castTime / 1000  -- Convert from ms to seconds
    end
    return nil
end

-- Get spell school (0=Physical, 1=Holy, 2=Fire, 3=Nature, 4=Frost, 5=Shadow, 6=Arcane)
function API.GetSpellSchool(spellId)
    return API.GetSpellField(spellId, "school")
end

-- Get spell mana cost
function API.GetSpellManaCost(spellId)
    return API.GetSpellField(spellId, "manaCost")
end

-- Get spell range (max range in yards)
function API.GetSpellRange(spellId)
    local rangeMax = API.GetSpellField(spellId, "rangeMax")
    if rangeMax then
        return rangeMax / 10  -- Convert from game units to yards
    end
    return nil
end

-- Get spell cooldown from record (base cooldown, not current)
function API.GetSpellBaseCooldown(spellId)
    local recoveryTime = API.GetSpellField(spellId, "recoveryTime")
    if recoveryTime then
        return recoveryTime / 1000  -- Convert from ms to seconds
    end
    return nil
end

--------------------------------------------------------------------------------
-- ITEM STATS API (GetItemStats / GetItemStatsField)
--------------------------------------------------------------------------------

-- Cache for item stats
API.itemStatsCache = {}

-- Get full item stats data
function API.GetItemRecord(itemId)
    if not itemId or itemId == 0 then return nil end

    -- Check cache first
    if API.itemStatsCache[itemId] then
        return API.itemStatsCache[itemId]
    end

    -- Use native function if available (wrapped in pcall for safety)
    if GetItemStats then
        local ok, stats = pcall(GetItemStats, itemId)
        if ok and stats then
            API.itemStatsCache[itemId] = stats
            return stats
        end
    end

    return nil
end

-- Get a specific field from item stats
function API.GetItemField(itemId, fieldName)
    if not itemId or itemId == 0 then return nil end

    -- Use native function if available (more efficient)
    if GetItemStatsField then
        local success, result = pcall(GetItemStatsField, itemId, fieldName)
        if success then
            return result
        end
        return nil
    end

    -- Fallback to full record lookup
    local stats = API.GetItemRecord(itemId)
    if stats then
        return stats[fieldName]
    end

    return nil
end

-- Get item level
function API.GetItemLevel(itemId)
    -- Use dedicated function if available
    if GetItemLevel then
        local success, result = pcall(GetItemLevel, itemId)
        if success then return result end
    end

    return API.GetItemField(itemId, "itemLevel")
end

-- Get item name
function API.GetItemName(itemId)
    return API.GetItemField(itemId, "displayName")
end

-- Get item quality (0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic, 5=Legendary)
function API.GetItemQuality(itemId)
    return API.GetItemField(itemId, "quality")
end

-- Get weapon speed in seconds
function API.GetWeaponSpeed(itemId)
    local delay = API.GetItemField(itemId, "delay")
    if delay then
        return delay / 1000
    end
    return nil
end

-- Get item inventory type (equipment slot)
-- Returns: inventoryType number, or nil if not equippable
-- Common types: 0=Non-equip, 1=Head, 2=Neck, 3=Shoulder, 4=Shirt, 5=Chest,
--               6=Waist, 7=Legs, 8=Feet, 9=Wrist, 10=Hands, 11=Finger, 12=Trinket,
--               13=One-Hand, 14=Shield, 15=Ranged, 16=Back, 17=Two-Hand,
--               18=Bag, 20=Robe, 21=Main Hand, 22=Off Hand, 23=Holdable,
--               24=Ammo, 25=Thrown, 26=Ranged Right, 28=Relic
function API.GetItemInventoryType(itemId)
    local ok, result = pcall(API.GetItemField, itemId, "inventoryType")
    if ok then return result end
    return nil
end

-- Convert inventoryType to equipment slot ID(s)
-- Returns slotId, altSlotId (for rings/trinkets)
API.inventoryTypeToSlot = {
    [1] = 1,       -- Head -> HeadSlot
    [2] = 2,       -- Neck -> NeckSlot
    [3] = 3,       -- Shoulder -> ShoulderSlot
    [4] = 4,       -- Shirt -> ShirtSlot
    [5] = 5,       -- Chest -> ChestSlot
    [6] = 6,       -- Waist -> WaistSlot
    [7] = 7,       -- Legs -> LegsSlot
    [8] = 8,       -- Feet -> FeetSlot
    [9] = 9,       -- Wrist -> WristSlot
    [10] = 10,     -- Hands -> HandsSlot
    [11] = {11, 12}, -- Finger -> Finger0Slot or Finger1Slot
    [12] = {13, 14}, -- Trinket -> Trinket0Slot or Trinket1Slot
    [13] = 16,     -- One-Hand -> MainHandSlot (can also go off-hand)
    [14] = 17,     -- Shield -> SecondaryHandSlot
    [15] = 18,     -- Ranged -> RangedSlot
    [16] = 15,     -- Back -> BackSlot
    [17] = 16,     -- Two-Hand -> MainHandSlot
    [20] = 5,      -- Robe -> ChestSlot
    [21] = 16,     -- Main Hand -> MainHandSlot
    [22] = 17,     -- Off Hand -> SecondaryHandSlot
    [23] = 17,     -- Holdable -> SecondaryHandSlot
    [24] = 0,      -- Ammo -> AmmoSlot
    [25] = 18,     -- Thrown -> RangedSlot
    [26] = 18,     -- Ranged Right -> RangedSlot
    [28] = 18,     -- Relic -> RangedSlot
}

-- Get equipment slot ID for an item
-- Returns slotId, altSlotId for items that can go in multiple slots
function API.GetItemEquipSlot(itemId)
    local ok, invType = pcall(API.GetItemInventoryType, itemId)
    if not ok or not invType or invType == 0 then return nil end

    local slotInfo = API.inventoryTypeToSlot[invType]
    if type(slotInfo) == "table" then
        return slotInfo[1], slotInfo[2]  -- Primary and alt slot
    end
    return slotInfo, nil
end

--------------------------------------------------------------------------------
-- UNIT DATA API (GetUnitData / GetUnitField)
--------------------------------------------------------------------------------

-- Get full unit data (no caching - unit data changes frequently)
function API.GetUnitRecord(unitToken)
    if not unitToken then return nil end

    if GetUnitData then
        return GetUnitData(unitToken)
    end

    return nil
end

-- Get a specific unit field
function API.GetUnitFieldValue(unitToken, fieldName)
    if not unitToken then return nil end

    -- Use native function if available (more efficient)
    if GetUnitField then
        local success, result = pcall(GetUnitField, unitToken, fieldName)
        if success then
            return result
        end
        return nil
    end

    -- Fallback to full record
    local data = API.GetUnitRecord(unitToken)
    if data then
        return data[fieldName]
    end

    return nil
end

-- Get unit's current auras as spell IDs
function API.GetUnitAuras(unitToken)
    return API.GetUnitFieldValue(unitToken, "aura")
end

-- Get unit resistances table
function API.GetUnitResistances(unitToken)
    return API.GetUnitFieldValue(unitToken, "resistances")
end

-- Get specific resistance value
-- school: 1=Armor, 2=Holy, 3=Fire, 4=Nature, 5=Frost, 6=Shadow, 7=Arcane
function API.GetUnitResistance(unitToken, school)
    local resistances = API.GetUnitResistances(unitToken)
    if resistances and school then
        return resistances[school]
    end
    return nil
end

-- Check if unit has a specific aura by spell ID
function API.UnitHasAura(unitToken, spellId)
    local auras = API.GetUnitAuras(unitToken)
    if not auras or not spellId then return false end

    for _, auraId in ipairs(auras) do
        if auraId == spellId then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- INVENTORY & EQUIPMENT API (v2.18+)
--------------------------------------------------------------------------------

-- Find an item in player's inventory by ID or name
-- Returns: bagIndex, slot (see wiki for bag index meanings)
-- bagIndex nil + slot = equipped item (slot is equipment slot 0-18)
-- bagIndex + slot = item in bag
-- nil, nil = item not found
function API.FindPlayerItemSlot(itemIdOrName)
    if not itemIdOrName then return nil, nil end

    -- Use native function if available (v2.18+)
    if FindPlayerItemSlot then
        return FindPlayerItemSlot(itemIdOrName)
    end

    -- Fallback: manual search for older versions
    -- This is much slower but works without Nampower 2.18
    local itemName = itemIdOrName
    if type(itemIdOrName) == "number" then
        -- Try to get item name from ID
        itemName = API.GetItemName(itemIdOrName)
        if not itemName then
            -- Try GetItemInfo as fallback (only works for cached items)
            itemName = GetItemInfo(itemIdOrName)
        end
        if not itemName then
            return nil, nil  -- Can't resolve item ID
        end
    end

    -- Search equipped items first (slots 0-18, but WoW uses 1-19 in API)
    for slot = 0, 18 do
        local link = GetInventoryItemLink("player", slot + 1)  -- GetInventoryItemLink is 1-indexed
        if link then
            local name = GetItemInfo(link)
            if name and string.lower(name) == string.lower(itemName) then
                return nil, slot  -- Equipped
            end
        end
    end

    -- Search bags (0 = backpack, 1-4 = bags)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = GetItemInfo(link)
                if name and string.lower(name) == string.lower(itemName) then
                    return bag, slot
                end
            end
        end
    end

    return nil, nil  -- Not found
end

-- Get all equipped items for a unit
-- Returns table with slot indices (0-18) as keys, item info tables as values
function API.GetEquippedItems(unitToken)
    unitToken = unitToken or "player"

    -- Use native function if available (v2.18+)
    if GetEquippedItems then
        return GetEquippedItems(unitToken)
    end

    -- Fallback: manual lookup for player only
    if unitToken ~= "player" then
        return nil  -- Can't inspect other units without native API
    end

    local items = {}
    for slot = 0, 18 do
        local link = GetInventoryItemLink("player", slot + 1)
        if link then
            local _, _, itemId = string.find(link, "item:(%d+)")
            if itemId then
                items[slot] = {
                    itemId = tonumber(itemId),
                    -- Other fields not available without native API
                }
            end
        end
    end

    return items
end

-- Get equipped item info for a specific slot
-- Slot numbers: 1=Head, 2=Neck, 3=Shoulder... 16=MainHand, 17=OffHand, 18=Ranged
function API.GetEquippedItem(unitToken, slot)
    unitToken = unitToken or "player"

    -- Use native function if available (v2.18+)
    if GetEquippedItem then
        return GetEquippedItem(unitToken, slot)
    end

    -- Fallback: manual lookup for player
    if unitToken ~= "player" then
        return nil
    end

    local link = GetInventoryItemLink("player", slot + 1)  -- 1-indexed
    if link then
        local _, _, itemId = string.find(link, "item:(%d+)")
        if itemId then
            return {
                itemId = tonumber(itemId),
            }
        end
    end

    return nil
end

-- Get all items in all bags
-- Returns nested table: bagIndex -> { slot -> itemInfo }
function API.GetBagItems()
    -- Use native function if available (v2.18+)
    if GetBagItems then
        return GetBagItems()
    end

    -- Fallback: manual enumeration
    local bags = {}
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            bags[bag] = {}
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, itemId = string.find(link, "item:(%d+)")
                    local _, count = GetContainerItemInfo(bag, slot)
                    if itemId then
                        bags[bag][slot] = {
                            itemId = tonumber(itemId),
                            stackCount = count or 1,
                        }
                    end
                end
            end
        end
    end

    return bags
end

-- Get item info for a specific bag slot
function API.GetBagItem(bagIndex, slot)
    -- Use native function if available (v2.18+)
    if GetBagItem then
        return GetBagItem(bagIndex, slot)
    end

    -- Fallback: manual lookup
    local link = GetContainerItemLink(bagIndex, slot)
    if link then
        local _, _, itemId = string.find(link, "item:(%d+)")
        local _, count = GetContainerItemInfo(bagIndex, slot)
        if itemId then
            return {
                itemId = tonumber(itemId),
                stackCount = count or 1,
            }
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- OPTIMIZED ITEM FINDING (v2.18+)
-- These functions provide fast item lookup compatible with CleveRoids.Items format
--------------------------------------------------------------------------------

-- Fast item lookup using v2.18 FindPlayerItemSlot
-- Returns item info table compatible with CleveRoids.Items format:
--   { name, itemId, inventoryID } for equipped items
--   { name, itemId, bagID, slot } for bag items
-- Returns nil if item not found
function API.FindItemFast(itemIdOrName)
    if not itemIdOrName then return nil end

    -- Use native v2.18 function if available (much faster than Lua scan)
    if FindPlayerItemSlot then
        local bag, slot = FindPlayerItemSlot(itemIdOrName)

        if slot then
            local itemInfo = {}

            if bag == nil then
                -- Equipped item (slot is equipment slot 0-18)
                -- Nampower uses 0-indexed, WoW API uses 1-indexed for GetInventoryItemLink
                local invSlot = slot + 1
                local link = GetInventoryItemLink("player", invSlot)
                if link then
                    local _, _, itemId = string.find(link, "item:(%d+)")
                    local _, _, name = string.find(link, "|h%[(.-)%]|h")
                    itemInfo.inventoryID = invSlot
                    itemInfo.itemId = tonumber(itemId)
                    itemInfo.name = name
                    itemInfo._source = "nampower_equipped"
                    return itemInfo
                end
            else
                -- Bag item
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, itemId = string.find(link, "item:(%d+)")
                    local _, _, name = string.find(link, "|h%[(.-)%]|h")
                    local _, count = GetContainerItemInfo(bag, slot)
                    itemInfo.bagID = bag
                    itemInfo.slot = slot
                    itemInfo.itemId = tonumber(itemId)
                    itemInfo.name = name
                    itemInfo.count = count or 1
                    itemInfo._source = "nampower_bag"
                    return itemInfo
                end
            end
        end

        return nil  -- Not found via native lookup
    end

    -- Fallback: no v2.18 API, return nil (caller should use existing methods)
    return nil
end

-- Check if an item is equipped in a specific slot (fast)
-- Returns true if item matches by ID or name
function API.IsItemInSlot(itemIdOrName, inventorySlot)
    if not itemIdOrName or not inventorySlot then return false end

    -- Use native v2.18 GetEquippedItem if available
    if GetEquippedItem then
        local slotInfo = GetEquippedItem("player", inventorySlot - 1)  -- 0-indexed
        if slotInfo and slotInfo.itemId then
            local checkId = tonumber(itemIdOrName)
            if checkId then
                return slotInfo.itemId == checkId
            else
                -- Check by name
                local itemName = API.GetItemName(slotInfo.itemId)
                if itemName then
                    return string.lower(itemName) == string.lower(itemIdOrName)
                end
            end
        end
        return false
    end

    -- Fallback: use GetInventoryItemLink
    local link = GetInventoryItemLink("player", inventorySlot)
    if not link then return false end

    local checkId = tonumber(itemIdOrName)
    if checkId then
        local _, _, currentId = string.find(link, "item:(%d+)")
        return currentId and tonumber(currentId) == checkId
    else
        local _, _, currentName = string.find(link, "|h%[(.-)%]|h")
        return currentName and string.lower(currentName) == string.lower(itemIdOrName)
    end
end

-- Check if item is equipped anywhere (fast)
-- Returns inventorySlot if equipped, nil otherwise
function API.FindEquippedItem(itemIdOrName)
    if not itemIdOrName then return nil end

    -- Use native v2.18 FindPlayerItemSlot if available
    if FindPlayerItemSlot then
        local bag, slot = FindPlayerItemSlot(itemIdOrName)
        if bag == nil and slot then
            return slot + 1  -- Convert to 1-indexed WoW API slot
        end
        return nil  -- Not equipped (might be in bag or not found)
    end

    -- Fallback: scan equipped slots
    local checkId = tonumber(itemIdOrName)
    local checkName = (not checkId) and string.lower(itemIdOrName) or nil

    for invSlot = 1, 19 do
        local link = GetInventoryItemLink("player", invSlot)
        if link then
            if checkId then
                local _, _, currentId = string.find(link, "item:(%d+)")
                if currentId and tonumber(currentId) == checkId then
                    return invSlot
                end
            elseif checkName then
                local _, _, currentName = string.find(link, "|h%[(.-)%]|h")
                if currentName and string.lower(currentName) == checkName then
                    return invSlot
                end
            end
        end
    end

    return nil
end

-- Find item in bags only (not equipped) - fast
-- Returns bag, slot if found, nil otherwise
function API.FindBagItem(itemIdOrName)
    if not itemIdOrName then return nil, nil end

    -- Use native v2.18 FindPlayerItemSlot if available
    if FindPlayerItemSlot then
        local bag, slot = FindPlayerItemSlot(itemIdOrName)
        if bag ~= nil and slot then
            return bag, slot
        end
        return nil, nil  -- Not in bags (might be equipped or not found)
    end

    -- Fallback: scan bags
    local checkId = tonumber(itemIdOrName)
    local checkName = (not checkId) and string.lower(itemIdOrName) or nil

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                if checkId then
                    local _, _, currentId = string.find(link, "item:(%d+)")
                    if currentId and tonumber(currentId) == checkId then
                        return bag, slot
                    end
                elseif checkName then
                    local _, _, currentName = string.find(link, "|h%[(.-)%]|h")
                    if currentName and string.lower(currentName) == checkName then
                        return bag, slot
                    end
                end
            end
        end
    end

    return nil, nil
end

-- Use an item by ID or name (fast lookup)
-- Returns true if item was used, false otherwise
function API.UseItem(itemIdOrName)
    if not itemIdOrName then return false end

    -- Try native v2.18 lookup first
    local itemInfo = API.FindItemFast(itemIdOrName)
    if itemInfo then
        ClearCursor()
        if itemInfo.inventoryID then
            UseInventoryItem(itemInfo.inventoryID)
            return true
        elseif itemInfo.bagID and itemInfo.slot then
            UseContainerItem(itemInfo.bagID, itemInfo.slot)
            return true
        end
    end

    -- No v2.18 API or item not found via native lookup
    return false
end

-- Equip an item from bags to a specific slot (fast lookup)
-- Returns true if equip was attempted, false if item not found
function API.EquipItem(itemIdOrName, targetSlot)
    if not itemIdOrName then return false end

    -- Check if already equipped in target slot
    if targetSlot and API.IsItemInSlot(itemIdOrName, targetSlot) then
        return true  -- Already equipped
    end

    -- Find the item
    local itemInfo = API.FindItemFast(itemIdOrName)
    if not itemInfo then return false end

    -- If already equipped (but not in target slot), need to swap
    if itemInfo.inventoryID then
        if targetSlot and itemInfo.inventoryID ~= targetSlot then
            -- Item equipped in wrong slot - pick up and move
            ClearCursor()
            PickupInventoryItem(itemInfo.inventoryID)
            if CursorHasItem and CursorHasItem() then
                EquipCursorItem(targetSlot)
                ClearCursor()
                return true
            end
        end
        return true  -- Already equipped (and no target slot specified)
    end

    -- Item in bag - equip it
    if itemInfo.bagID and itemInfo.slot then
        ClearCursor()
        PickupContainerItem(itemInfo.bagID, itemInfo.slot)
        if CursorHasItem and CursorHasItem() then
            if targetSlot then
                EquipCursorItem(targetSlot)
            else
                -- Auto-equip to appropriate slot
                AutoEquipCursorItem()
            end
            ClearCursor()
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- CAST INFO API (v2.18+)
--------------------------------------------------------------------------------

-- Get detailed information about current cast/channel
-- Returns table with: castId, spellId, guid, castType, castStartS, castEndS,
--                     castRemainingMs, castDurationMs, gcdEndS, gcdRemainingMs
-- Returns nil if no active cast
function API.GetCastInfo()
    -- Use native function if available (v2.18+)
    if GetCastInfo then
        return GetCastInfo()
    end

    -- Fallback: use GetCurrentCastingInfo (less detailed)
    if GetCurrentCastingInfo then
        local castId, visId, autoId, casting, channeling, onswing, autoattack = GetCurrentCastingInfo()
        if castId and castId > 0 then
            return {
                spellId = castId,
                castType = channeling == 1 and 3 or 0,  -- 3 = CHANNEL, 0 = NORMAL
                -- Timing info not available without native GetCastInfo
            }
        end
    end

    return nil
end

-- Check if currently casting (convenience wrapper)
function API.IsCasting()
    local info = API.GetCastInfo()
    return info ~= nil
end

-- Get GCD remaining in milliseconds
function API.GetGCDRemainingMs()
    local info = API.GetCastInfo()
    if info and info.gcdRemainingMs then
        return info.gcdRemainingMs
    end
    return 0
end

-- Get cast remaining in milliseconds
function API.GetCastRemainingMs()
    local info = API.GetCastInfo()
    if info and info.castRemainingMs then
        return info.castRemainingMs
    end
    return 0
end

--------------------------------------------------------------------------------
-- COOLDOWN API (v2.18+)
--------------------------------------------------------------------------------

-- Get detailed cooldown information for a spell
-- Returns table with: isOnCooldown, cooldownRemainingMs,
--   individual cooldown: individualStartS, individualDurationMs, individualRemainingMs, isOnIndividualCooldown
--   category cooldown: categoryId, categoryStartS, categoryDurationMs, categoryRemainingMs, isOnCategoryCooldown
--   GCD: gcdCategoryId, gcdCategoryStartS, gcdCategoryDurationMs, gcdCategoryRemainingMs, isOnGcdCategoryCooldown
function API.GetSpellCooldownInfo(spellId)
    if not spellId or spellId == 0 then return nil end

    -- Use native function if available (v2.18+)
    if GetSpellIdCooldown then
        return GetSpellIdCooldown(spellId)
    end

    -- Fallback: use GetSpellCooldown (less detailed)
    local spellName = API.GetSpellNameById(spellId)
    if spellName then
        local start, duration = GetSpellCooldown(spellName, BOOKTYPE_SPELL)
        if start and start > 0 then
            local remaining = (start + duration) - GetTime()
            if remaining > 0 then
                return {
                    isOnCooldown = 1,
                    cooldownRemainingMs = remaining * 1000,
                }
            end
        end
    end

    return { isOnCooldown = 0, cooldownRemainingMs = 0 }
end

-- Get detailed cooldown information for an item
function API.GetItemCooldownInfo(itemId)
    if not itemId or itemId == 0 then return nil end

    -- Use native function if available (v2.18+)
    if GetItemIdCooldown then
        return GetItemIdCooldown(itemId)
    end

    -- Fallback: use GetItemCooldown (less detailed)
    local start, duration = GetItemCooldown(itemId)
    if start and start > 0 then
        local remaining = (start + duration) - GetTime()
        if remaining > 0 then
            return {
                isOnCooldown = 1,
                cooldownRemainingMs = remaining * 1000,
            }
        end
    end

    return { isOnCooldown = 0, cooldownRemainingMs = 0 }
end

-- Check if a spell is on cooldown (ignoring GCD)
function API.IsSpellOnCooldown(spellId, ignoreGCD)
    local info = API.GetSpellCooldownInfo(spellId)
    if not info then return false end

    if ignoreGCD then
        -- Only check individual and category cooldowns
        return (info.isOnIndividualCooldown == 1) or (info.isOnCategoryCooldown == 1)
    end

    return info.isOnCooldown == 1
end

-- Get remaining cooldown for a spell in seconds
function API.GetSpellCooldownRemaining(spellId)
    local info = API.GetSpellCooldownInfo(spellId)
    if info and info.cooldownRemainingMs then
        return info.cooldownRemainingMs / 1000
    end
    return 0
end

--------------------------------------------------------------------------------
-- CHANNEL CONTROL API (v2.18+)
--------------------------------------------------------------------------------

-- Stop channeling early on the next tick
-- Only works if NP_QueueChannelingSpells is enabled
function API.StopChannelNextTick()
    if ChannelStopCastingNextTick then
        ChannelStopCastingNextTick()
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- EVENT CONSTANTS (v2.18+)
--------------------------------------------------------------------------------

-- Spell queue event codes
API.QUEUE_EVENT = {
    ON_SWING_QUEUED = 0,
    ON_SWING_QUEUE_POPPED = 1,
    NORMAL_QUEUED = 2,
    NORMAL_QUEUE_POPPED = 3,
    NON_GCD_QUEUED = 4,
    NON_GCD_QUEUE_POPPED = 5,
}

-- Spell cast event types
API.CAST_TYPE = {
    NORMAL = 1,
    NON_GCD = 2,
    ON_SWING = 3,
    CHANNEL = 4,
    TARGETING = 5,
    TARGETING_NON_GCD = 6,
}

-- Buff/debuff event names (v2.18+)
API.AURA_EVENTS = {
    "BUFF_ADDED_SELF",
    "BUFF_REMOVED_SELF",
    "BUFF_ADDED_OTHER",
    "BUFF_REMOVED_OTHER",
    "DEBUFF_ADDED_SELF",
    "DEBUFF_REMOVED_SELF",
    "DEBUFF_ADDED_OTHER",
    "DEBUFF_REMOVED_OTHER",
}

-- Spell school constants (for reference)
API.SPELL_SCHOOL = {
    PHYSICAL = 0,
    HOLY = 1,
    FIRE = 2,
    NATURE = 3,
    FROST = 4,
    SHADOW = 5,
    ARCANE = 6,
}

-- Resistance indices (1-indexed for Lua tables)
API.RESISTANCE_INDEX = {
    ARMOR = 1,
    HOLY = 2,
    FIRE = 3,
    NATURE = 4,
    FROST = 5,
    SHADOW = 6,
    ARCANE = 7,
}

--------------------------------------------------------------------------------
-- SPELL MODIFIERS API (GetSpellModifiers)
--------------------------------------------------------------------------------

-- Modifier type constants
API.MODIFIER_DAMAGE = 0
API.MODIFIER_DURATION = 1
API.MODIFIER_THREAT = 2
API.MODIFIER_ATTACK_POWER = 3
API.MODIFIER_CHARGES = 4
API.MODIFIER_RANGE = 5
API.MODIFIER_RADIUS = 6
API.MODIFIER_CRITICAL_CHANCE = 7
API.MODIFIER_ALL_EFFECTS = 8
API.MODIFIER_NOT_LOSE_CASTING_TIME = 9
API.MODIFIER_CASTING_TIME = 10
API.MODIFIER_COOLDOWN = 11
API.MODIFIER_SPEED = 12
API.MODIFIER_COST = 14
API.MODIFIER_CRIT_DAMAGE_BONUS = 15
API.MODIFIER_RESIST_MISS_CHANCE = 16
API.MODIFIER_JUMP_TARGETS = 17
API.MODIFIER_CHANCE_OF_SUCCESS = 18
API.MODIFIER_ACTIVATION_TIME = 19
API.MODIFIER_EFFECT_PAST_FIRST = 20
API.MODIFIER_CASTING_TIME_OLD = 21
API.MODIFIER_DOT = 22
API.MODIFIER_HASTE = 23
API.MODIFIER_SPELL_BONUS_DAMAGE = 24
API.MODIFIER_MULTIPLE_VALUE = 27
API.MODIFIER_RESIST_DISPEL_CHANCE = 28

-- Get spell modifiers
-- Returns: flatMod, percentMod, hasModifier
function API.GetModifiers(spellId, modifierType)
    if not GetSpellModifiers then
        return 0, 0, false
    end

    if not spellId or spellId == 0 then
        return 0, 0, false
    end

    local flat, percent, ret = GetSpellModifiers(spellId, modifierType)
    return flat or 0, percent or 0, ret and ret ~= 0
end

-- Get duration modifier for a spell (useful for debuff tracking)
-- Returns modified duration given base duration
function API.GetModifiedDuration(spellId, baseDuration)
    if not baseDuration then return nil end

    local flat, percent, hasModifier = API.GetModifiers(spellId, API.MODIFIER_DURATION)

    if not hasModifier then
        return baseDuration
    end

    -- Apply flat modifier first, then percentage
    local modified = baseDuration + flat
    if percent ~= 0 then
        modified = modified * (1 + percent / 100)
    end

    return modified
end

-- Get damage modifier for a spell
function API.GetDamageModifier(spellId)
    local flat, percent = API.GetModifiers(spellId, API.MODIFIER_DAMAGE)
    return flat, percent
end

-- Get cooldown modifier for a spell
function API.GetCooldownModifier(spellId)
    local flat, percent = API.GetModifiers(spellId, API.MODIFIER_COOLDOWN)
    return flat, percent
end

-- Get cast time modifier for a spell
function API.GetCastTimeModifier(spellId)
    local flat, percent = API.GetModifiers(spellId, API.MODIFIER_CASTING_TIME)
    return flat, percent
end

-- Get cost modifier for a spell
function API.GetCostModifier(spellId)
    local flat, percent = API.GetModifiers(spellId, API.MODIFIER_COST)
    return flat, percent
end

--------------------------------------------------------------------------------
-- ENHANCED SPELL LOOKUP (using new "spellId:number" and name syntax)
--------------------------------------------------------------------------------

-- Convert spell identifier to spellId:number format if needed
-- Input can be: spellSlot (number), "spellId:123", or "Spell Name"
function API.NormalizeSpellIdentifier(identifier, bookType)
    if not identifier then return nil end

    -- Already in spellId:number format
    if type(identifier) == "string" and string.find(identifier, "^spellId:") then
        return identifier
    end

    -- If it's a number and enhanced functions exist, keep as-is (slot) or convert to spellId
    if type(identifier) == "number" then
        if API.features.hasEnhancedSpellFunctions then
            -- Could be a spell slot - check if we have GetSpellSlotTypeIdForName to get the ID
            if identifier > 0 and identifier < 1000 then
                -- Likely a spell slot, use as-is
                return identifier, bookType or BOOKTYPE_SPELL
            else
                -- Likely a spell ID, convert to spellId:number format
                return "spellId:" .. identifier
            end
        end
        return identifier, bookType
    end

    -- It's a spell name
    if type(identifier) == "string" then
        -- If enhanced functions available, pass name directly
        if API.features.hasEnhancedSpellFunctions then
            return identifier
        end

        -- Fall back to manual lookup
        local spell = CleveRoids.GetSpell and CleveRoids.GetSpell(identifier)
        if spell then
            return spell.spellSlot, spell.bookType
        end
    end

    return nil
end

-- Get spell texture (works with name, spellId:number, or slot)
function API.GetSpellTexture(identifier, bookType)
    if API.features.hasEnhancedSpellFunctions then
        -- Pass directly to native function
        local id = API.NormalizeSpellIdentifier(identifier)
        if id then
            return GetSpellTexture(id, bookType)
        end
    else
        -- Fall back to slot-based lookup
        local slot, book = API.NormalizeSpellIdentifier(identifier, bookType)
        if slot then
            return GetSpellTexture(slot, book or BOOKTYPE_SPELL)
        end
    end
    return nil
end

-- Get spell name (works with name, spellId:number, or slot)
function API.GetSpellName(identifier, bookType)
    if API.features.hasEnhancedSpellFunctions then
        local id = API.NormalizeSpellIdentifier(identifier)
        if id then
            return GetSpellName(id, bookType)
        end
    else
        local slot, book = API.NormalizeSpellIdentifier(identifier, bookType)
        if slot then
            return GetSpellName(slot, book or BOOKTYPE_SPELL)
        end
    end
    return nil
end

-- Get spell cooldown (works with name, spellId:number, or slot)
-- Returns: start, duration (same as native)
function API.GetSpellCooldown(identifier, bookType)
    if API.features.hasEnhancedSpellFunctions then
        local id = API.NormalizeSpellIdentifier(identifier)
        if id then
            return GetSpellCooldown(id, bookType)
        end
    else
        local slot, book = API.NormalizeSpellIdentifier(identifier, bookType)
        if slot then
            return GetSpellCooldown(slot, book or BOOKTYPE_SPELL)
        end
    end
    return nil
end

-- Check if spell is passive
function API.IsSpellPassive(identifier, bookType)
    if API.features.hasEnhancedSpellFunctions then
        local id = API.NormalizeSpellIdentifier(identifier)
        if id then
            return IsSpellPassive(id, bookType)
        end
    else
        local slot, book = API.NormalizeSpellIdentifier(identifier, bookType)
        if slot then
            return IsSpellPassive(slot, book or BOOKTYPE_SPELL)
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- SPELL ID LOOKUP UTILITIES
--------------------------------------------------------------------------------

-- Cache for spell ID lookups
API.spellIdCache = {}

-- Get spell ID from name (cached)
function API.GetSpellIdFromName(spellName)
    if not spellName then return nil end

    -- Check cache
    if API.spellIdCache[spellName] then
        return API.spellIdCache[spellName]
    end

    -- Use Nampower's GetSpellIdForName
    if GetSpellIdForName then
        local spellId = GetSpellIdForName(spellName)
        if spellId and spellId > 0 then
            API.spellIdCache[spellName] = spellId
            return spellId
        end
    end

    return nil
end

-- Get spell slot, book type, and ID from name
function API.GetSpellSlotInfo(spellName)
    if not spellName then return nil end

    -- Use Nampower's GetSpellSlotTypeIdForName
    if GetSpellSlotTypeIdForName then
        local slot, bookType, spellId = GetSpellSlotTypeIdForName(spellName)
        if slot and slot > 0 then
            return slot, bookType, spellId
        end
    end

    -- Fallback to CleveRoids.GetSpell
    if CleveRoids.GetSpell then
        local spell = CleveRoids.GetSpell(spellName)
        if spell then
            local spellId = API.GetSpellIdFromName(spellName)
            return spell.spellSlot, spell.bookType, spellId
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

-- Initialize the API module
function API.Initialize()
    -- Detect enhanced spell functions
    DetectEnhancedSpellFunctions()

end

-- Clear caches (call on respec/spell change)
function API.ClearCaches()
    API.spellRecCache = {}
    API.itemStatsCache = {}
    API.spellIdCache = {}
    API.settingsCache = {}
    API.spellTypeCache = {}
end

--------------------------------------------------------------------------------
-- CONVENIENCE WRAPPERS FOR EXISTING CODE
--------------------------------------------------------------------------------

-- Check if a spell is in range (wrapper around IsSpellInRange with fallbacks)
function API.IsSpellInRange(spellIdentifier, unit)
    unit = unit or "target"

    if not IsSpellInRange then
        return nil  -- Can't determine
    end

    -- Convert name to ID if needed
    local checkValue = spellIdentifier
    if type(spellIdentifier) == "string" and not string.find(spellIdentifier, "^spellId:") then
        local spellId = API.GetSpellIdFromName(spellIdentifier)
        if spellId and spellId > 0 then
            checkValue = spellId
        end
    end

    return IsSpellInRange(checkValue, unit)
end

-- Check if a spell is usable (wrapper around IsSpellUsable)
function API.IsSpellUsable(spellIdentifier)
    if not _G.IsSpellUsable then
        return nil
    end

    -- If enhanced functions available, pass directly
    if API.features.hasEnhancedSpellFunctions then
        return _G.IsSpellUsable(spellIdentifier)
    end

    -- Convert to ID if name
    if type(spellIdentifier) == "string" then
        local spellId = API.GetSpellIdFromName(spellIdentifier)
        if spellId then
            return _G.IsSpellUsable(spellId)
        end
    end

    return _G.IsSpellUsable(spellIdentifier)
end

--------------------------------------------------------------------------------
-- SMART CASTING SYSTEM
--------------------------------------------------------------------------------

-- Spell type constants
API.SPELL_TYPE_UNKNOWN = 0
API.SPELL_TYPE_CAST = 1      -- Has cast time
API.SPELL_TYPE_INSTANT = 2   -- Instant, on GCD
API.SPELL_TYPE_CHANNEL = 3   -- Channeled spell
API.SPELL_TYPE_ON_SWING = 4  -- Next-melee (Heroic Strike, etc.)
API.SPELL_TYPE_NON_GCD = 5   -- Instant, not on GCD (trinkets, etc.)

-- Known on-swing spells (by name, localized via CleveRoids.Localized when available)
API.onSwingSpells = {
    ["Heroic Strike"] = true,
    ["Cleave"] = true,
    ["Maul"] = true,
    ["Slam"] = true,
    ["Raptor Strike"] = true,
    ["Mongoose Bite"] = true,
}

-- Known channeled spells (by name)
API.channeledSpells = {
    ["Arcane Missiles"] = true,
    ["Blizzard"] = true,
    ["Drain Life"] = true,
    ["Drain Mana"] = true,
    ["Drain Soul"] = true,
    ["Evocation"] = true,
    ["Health Funnel"] = true,
    ["Hellfire"] = true,
    ["Hurricane"] = true,
    ["Mind Flay"] = true,
    ["Rain of Fire"] = true,
    ["Tranquility"] = true,
    ["Volley"] = true,
    ["Mind Soothe"] = true,
    ["Mind Vision"] = true,
    ["First Aid"] = true, -- Bandaging
}

-- Cache for spell type lookups
API.spellTypeCache = {}

-- Determine spell type for a given spell
-- Returns: SPELL_TYPE_* constant
function API.GetSpellType(spellName)
    if not spellName then return API.SPELL_TYPE_UNKNOWN end

    -- Strip rank from name for cache lookup
    local baseName = string.gsub(spellName, "%s*%([Rr]ank%s*%d+%)%s*$", "")

    -- Check cache first
    if API.spellTypeCache[baseName] then
        return API.spellTypeCache[baseName]
    end

    local spellType = API.SPELL_TYPE_UNKNOWN

    -- Check known on-swing spells first (highest priority)
    if API.onSwingSpells[baseName] then
        spellType = API.SPELL_TYPE_ON_SWING
        API.spellTypeCache[baseName] = spellType
        return spellType
    end

    -- Check known channeled spells
    if API.channeledSpells[baseName] then
        spellType = API.SPELL_TYPE_CHANNEL
        API.spellTypeCache[baseName] = spellType
        return spellType
    end

    -- Try to use GetSpellRec for accurate detection
    local spellId = API.GetSpellIdFromName(spellName)
    if spellId and spellId > 0 and API.features.hasGetSpellRec then
        local rec = API.GetSpellRecord(spellId)
        if rec then
            -- Check for channeled via attributes
            -- SPELL_ATTR_EX_CHANNELED = 4 (0x00000004) in attributesEx
            local attrEx = rec.attributesEx or 0
            if bit and bit.band(attrEx, 4) ~= 0 then
                spellType = API.SPELL_TYPE_CHANNEL
                API.spellTypeCache[baseName] = spellType
                return spellType
            end

            -- Check cast time
            local castTime = rec.castTime or 0
            if castTime > 0 then
                spellType = API.SPELL_TYPE_CAST
            else
                -- Instant spell - check if it's on GCD
                -- startRecoveryTime > 0 means it triggers GCD
                local recoveryTime = rec.startRecoveryTime or 0
                if recoveryTime > 0 then
                    spellType = API.SPELL_TYPE_INSTANT
                else
                    spellType = API.SPELL_TYPE_NON_GCD
                end
            end

            API.spellTypeCache[baseName] = spellType
            return spellType
        end
    end

    -- Fallback: assume instant if no other info
    -- This is safe because Nampower will handle it correctly anyway
    spellType = API.SPELL_TYPE_INSTANT
    API.spellTypeCache[baseName] = spellType
    return spellType
end

-- Get the queue setting name for a spell type
local function GetQueueSettingForType(spellType)
    if spellType == API.SPELL_TYPE_CAST then
        return "NP_QueueCastTimeSpells"
    elseif spellType == API.SPELL_TYPE_INSTANT then
        return "NP_QueueInstantSpells"
    elseif spellType == API.SPELL_TYPE_CHANNEL then
        return "NP_QueueChannelingSpells"
    elseif spellType == API.SPELL_TYPE_ON_SWING then
        return "NP_QueueOnSwingSpells"
    elseif spellType == API.SPELL_TYPE_NON_GCD then
        return "NP_QueueInstantSpells"  -- Non-GCD uses instant setting
    end
    return nil
end

-- Check if queuing is enabled for a specific spell
function API.IsSpellQueueingEnabled(spellName)
    if not API.features.hasSpellQueue then
        return false
    end

    local spellType = API.GetSpellType(spellName)
    local settingName = GetQueueSettingForType(spellType)

    if settingName then
        return API.GetSettingBool(settingName)
    end

    -- Default: use cast time spell setting
    return API.GetSettingBool("NP_QueueCastTimeSpells")
end

-- Smart cast function that uses QueueSpellByName when appropriate
-- Returns: true if cast was attempted, false otherwise
-- Parameters:
--   spellName: The spell name (with optional rank)
--   target: Optional target unit (for SuperWoW CastSpellByName)
--   forceQueue: If true, always use QueueSpellByName (if available)
--   forceNoQueue: If true, never use QueueSpellByName
function API.SmartCast(spellName, target, forceQueue, forceNoQueue)
    if not spellName then return false end

    -- Determine whether to use queuing
    local useQueue = false

    if forceNoQueue then
        useQueue = false
    elseif forceQueue then
        useQueue = API.features.hasSpellQueue
    else
        -- Check if queuing is enabled for this spell type
        useQueue = API.IsSpellQueueingEnabled(spellName)
    end

    -- Check if we have a non-standard target (e.g., @mouseover)
    -- QueueSpellByName in older Nampower versions doesn't support target parameter
    -- Only Nampower v2.13+ supports QueueSpellByName with target
    local hasNonStandardTarget = target and target ~= "target"
    local canQueueWithTarget = API.HasMinimumVersion(2, 13, 0)

    -- Cast the spell
    if useQueue and QueueSpellByName then
        if hasNonStandardTarget then
            if canQueueWithTarget then
                -- Nampower v2.13+ supports target parameter in QueueSpellByName
                QueueSpellByName(spellName, target)
                return true
            else
                -- Older Nampower: can't queue with non-standard target
                -- Fall through to CastSpellByName with target
            end
        else
            -- No target or target is "target" - safe to use queue
            QueueSpellByName(spellName)
            return true
        end
    end

    -- Use standard casting (either queuing wasn't possible or we need target support)
    if CastSpellByName then
        if target and CleveRoids.hasSuperwow then
            -- SuperWoW supports target parameter
            CastSpellByName(spellName, target)
        else
            CastSpellByName(spellName)
        end
        return true
    end

    return false
end

-- Cast without queuing (uses CastSpellByNameNoQueue if available)
function API.CastNoQueue(spellName, target)
    if not spellName then return false end

    -- Use Nampower's no-queue function if available
    if CastSpellByNameNoQueue then
        CastSpellByNameNoQueue(spellName)
        return true
    end

    -- Fall back to standard cast
    if CastSpellByName then
        if target and CleveRoids.hasSuperwow then
            CastSpellByName(spellName, target)
        else
            CastSpellByName(spellName)
        end
        return true
    end

    return false
end

-- Force queue a spell (uses QueueSpellByName directly)
function API.ForceQueue(spellName)
    if not spellName then return false end

    if QueueSpellByName then
        QueueSpellByName(spellName)
        return true
    end

    -- Fall back to standard cast if queue not available
    if CastSpellByName then
        CastSpellByName(spellName)
        return true
    end

    return false
end

-- Queue a script to run after current cast (uses QueueScript if available)
function API.QueueScript(script, priority)
    if not script then return false end

    if QueueScript then
        QueueScript(script, priority or 1)
        return true
    end

    return false
end

-- Clear spell type cache (call on spec change)
function API.ClearSpellTypeCache()
    API.spellTypeCache = {}
end

-- Expose API globally for other addons
_G.CleveRoidsNampowerAPI = API
