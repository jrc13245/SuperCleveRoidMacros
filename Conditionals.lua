--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

-- Permanent cache for name normalization (underscores to spaces)
local _normalizedNames = {}

-- PERFORMANCE: Cache for lowercased normalized names (for case-insensitive comparisons)
local _lowerNormalizedNames = {}

-- Cached name normalization
function CleveRoids.NormalizeName(name)
    if not name then return name end
    local c = _normalizedNames[name]
    if c then return c end
    c = string.gsub(name, "_", " ")
    _normalizedNames[name] = c
    return c
end

-- PERFORMANCE: Cached lowercase normalization (underscores to spaces + lowercase)
local function GetLowerNormalizedName(name)
    if not name then return name end
    local c = _lowerNormalizedNames[name]
    if c then return c end
    c = string.lower(string.gsub(name, "_", " "))
    _lowerNormalizedNames[name] = c
    return c
end

-- PERFORMANCE: Cache for lowercased strings
local _lowercaseCache = {}
local function GetLowercaseString(str)
    if not str then return str end
    local c = _lowercaseCache[str]
    if c then return c end
    c = string.lower(str)
    _lowercaseCache[str] = c
    return c
end

-- Direct passthrough functions (no caching overhead for normal usage)
function CleveRoids.GetCachedTime()
    return GetTime()
end

function CleveRoids.GetCachedPlayerHealthPercent()
    local max = UnitHealthMax("player")
    return max > 0 and (100 * UnitHealth("player") / max) or 0
end

function CleveRoids.GetCachedPlayerPowerPercent()
    local max = UnitManaMax("player")
    return max > 0 and (100 * UnitMana("player") / max) or 0
end

function CleveRoids.GetCachedPlayerPower()
    return UnitMana("player")
end

function CleveRoids.GetCachedTargetHealthPercent()
    if not UnitExists("target") then return 0 end
    local max = UnitHealthMax("target")
    return max > 0 and (100 * UnitHealth("target") / max) or 0
end

-- Cooldown uses original function directly
function CleveRoids.GetCachedCooldown(name, ignoreGCD)
    return CleveRoids._GetCooldownUncached(name, ignoreGCD)
end

-- No-ops for compatibility
function CleveRoids.ClearFrameCache() end
function CleveRoids.TrackButtonPress() end
function CleveRoids.GetCacheStats() return nil end
function CleveRoids.SetCacheTTL(ms) end
function CleveRoids.SetMacroThrottle(ms) end
function CleveRoids.GetMacroThrottle() return 0 end

-- ============================================================================
-- PERFORMANCE: Cache spell name -> spell ID mappings for debuff lookups
-- This avoids iterating personalDebuffs/sharedDebuffs and calling SpellInfo() repeatedly
local _spellNameToIDs = {}  -- [spellName] = { spellID1, spellID2, ... }
local _spellNameToIDsBuilt = false

-- Build the spell name to ID cache (called once on first debuff check)
local function BuildSpellNameCache()
    if _spellNameToIDsBuilt then return end
    _spellNameToIDsBuilt = true

    local lib = CleveRoids.libdebuff
    if not lib then return end

    local gsub = string.gsub

    if lib.personalDebuffs then
        for sid, _ in pairs(lib.personalDebuffs) do
            local name = SpellInfo(sid)
            if name then
                name = gsub(name, "%s*%(%s*Rank%s+%d+%s*%)", "")
                if not _spellNameToIDs[name] then
                    _spellNameToIDs[name] = {}
                end
                table.insert(_spellNameToIDs[name], sid)
            end
        end
    end

    if lib.sharedDebuffs then
        for sid, _ in pairs(lib.sharedDebuffs) do
            local name = SpellInfo(sid)
            if name then
                name = gsub(name, "%s*%(%s*Rank%s+%d+%s*%)", "")
                if not _spellNameToIDs[name] then
                    _spellNameToIDs[name] = {}
                end
                -- Avoid duplicates
                local found = false
                for _, existingId in ipairs(_spellNameToIDs[name]) do
                    if existingId == sid then found = true; break end
                end
                if not found then
                    table.insert(_spellNameToIDs[name], sid)
                end
            end
        end
    end
end

-- Get cached spell IDs for a spell name
local function GetSpellIDsForName(spellName)
    BuildSpellNameCache()
    -- Strip rank from input spell name to match cache keys
    -- This handles cases like "Faerie Fire (Feral)(Rank 4)" -> "Faerie Fire (Feral)"
    if spellName then
        spellName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
    end
    return _spellNameToIDs[spellName]
end

-- Invalidate cache (call if debuff lists change)
function CleveRoids.InvalidateSpellNameCache()
    _spellNameToIDs = {}
    _spellNameToIDsBuilt = false
end

-- PERFORMANCE: Equipment cache for HasGearEquipped (avoids 19-slot scan per call)
-- Invalidated on UNIT_INVENTORY_CHANGED via CleveRoids.InvalidateEquipmentCache()
-- Enhanced with Nampower v2.18+ GetEquippedItems when available
local _equippedItemIDs = {}      -- [slot] = itemID (number)
local _equippedItemNames = {}    -- [slot] = itemName (lowercase string)
local _equipmentCacheValid = false

-- Track if we've warned about GetEquippedItems errors (warn once per session)
local _getEquippedItemsErrorWarned = false

local function BuildEquipmentCache()
    if _equipmentCacheValid then return end
    _equipmentCacheValid = true

    -- Clear old data
    for i = 1, 19 do
        _equippedItemIDs[i] = nil
        _equippedItemNames[i] = nil
    end

    local string_find = string.find
    local string_lower = string.lower

    -- Try Nampower v2.18+ GetEquippedItems for faster enumeration
    -- Requires version check because the function may exist but be broken in older versions
    local API = CleveRoids.NampowerAPI
    local hasValidNampower = API and API.HasMinimumVersion and API.HasMinimumVersion(2, 18, 0)

    if hasValidNampower and GetEquippedItems then
        -- Use pcall to catch any internal Nampower errors and fall back gracefully
        local success, result = pcall(GetEquippedItems, "player")

        if not success then
            -- Log the error once per session for debugging
            if not _getEquippedItemsErrorWarned then
                _getEquippedItemsErrorWarned = true
                local errMsg = tostring(result)
                if CleveRoids.Print then
                    CleveRoids.Print("|cffff6600Warning:|r GetEquippedItems failed: " .. errMsg)
                    CleveRoids.Print("Using fallback equipment detection. Consider updating Nampower.")
                end
            end
            -- Fall through to manual enumeration
        elseif result and type(result) == "table" then
            local usedNampower = false
            for nampowerSlot, itemInfo in pairs(result) do
                -- Nampower uses 0-indexed slots, WoW API uses 1-indexed
                -- tonumber() handles both string and numeric keys from different Nampower versions
                local slot = tonumber(nampowerSlot) + 1
                -- itemInfo must be a table to access .itemId (userdata from some Nampower versions is not indexable)
                if slot >= 1 and slot <= 19 and type(itemInfo) == "table" and itemInfo.itemId then
                    _equippedItemIDs[slot] = itemInfo.itemId
                    usedNampower = true

                    -- Get item name via Nampower API or GetItemInfo
                    local itemName = API and API.GetItemName and API.GetItemName(itemInfo.itemId)
                    if not itemName then
                        itemName = GetItemInfo(itemInfo.itemId)
                    end
                    if itemName then
                        _equippedItemNames[slot] = string_lower(itemName)
                    end
                end
            end
            if usedNampower then
                return  -- Done with Nampower path
            end
            -- Fall through to manual enumeration if Nampower returned userdata items
        end
    end

    -- Fallback: manual slot enumeration
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, id = string_find(link, "item:(%d+)")
            local _, _, nameInBrackets = string_find(link, "%[(.+)%]")

            if id then
                _equippedItemIDs[slot] = tonumber(id)
            end
            if nameInBrackets then
                _equippedItemNames[slot] = string_lower(nameInBrackets)
            elseif id then
                -- Fallback: resolve via GetItemInfo
                local itemName = GetItemInfo(tonumber(id))
                if itemName then
                    _equippedItemNames[slot] = string_lower(itemName)
                end
            end
        end
    end
end

-- Invalidate equipment cache (call on UNIT_INVENTORY_CHANGED)
function CleveRoids.InvalidateEquipmentCache()
    _equipmentCacheValid = false
end

-- ============================================================================
-- PERFORMANCE: Unified item location lookup using CleveRoids.Items cache
-- Returns: { type="inventory"|"bag", inventoryID=N } or { type="bag", bag=N, slot=N }
-- Returns nil if item not found
-- Enhanced with Nampower v2.18+ FindPlayerItemSlot when available
-- ============================================================================
local string_lower = string.lower
local string_find = string.find

-- Fast item lookup using cache - O(1) instead of O(n) scan
-- @param item: item ID (number) or item name (string)
-- @return table with location info, or nil if not found
function CleveRoids.FindItemLocation(item)
    -- Try Nampower v2.18+ native lookup first (much faster for item ID/name)
    if FindPlayerItemSlot and item then
        local numericItem = tonumber(item)

        -- Skip native lookup for equipment slot numbers (1-19)
        if not (numericItem and numericItem >= 1 and numericItem <= 19) then
            local bag, slot = FindPlayerItemSlot(item)

            if slot then
                if bag == nil then
                    -- Equipped item - Nampower returns 1-indexed slot
                    return { type = "inventory", inventoryID = slot }
                else
                    -- Bag item
                    return { type = "bag", bag = bag, slot = slot }
                end
            end
            -- If Nampower lookup failed, fall through to cache lookup
            -- (might find via substring match or cached alias)
        end
    end

    -- Fallback to CleveRoids.Items cache
    local Items = CleveRoids.Items
    if not Items then return nil end

    local itemData = nil

    -- Case 1: Numeric item ID
    local numericItem = tonumber(item)
    if numericItem then
        -- Check if it's an equipment slot (1-19)
        if numericItem >= 1 and numericItem <= 19 then
            local link = GetInventoryItemLink("player", numericItem)
            if link then
                return { type = "inventory", inventoryID = numericItem }
            end
            return nil
        end

        -- Look up by item ID in cache (Items[id] = name)
        local itemName = Items[numericItem]
        if itemName then
            itemData = Items[itemName]
        end
    else
        -- Case 2: String item name
        if type(item) == "string" and item ~= "" then
            -- Try exact match first, then lowercase
            itemData = Items[item]
            if not itemData or type(itemData) == "string" then
                local lowerItem = string_lower(item)
                local resolved = Items[lowerItem]
                if type(resolved) == "string" then
                    itemData = Items[resolved]
                elseif type(resolved) == "table" then
                    itemData = resolved
                end
            elseif type(itemData) == "string" then
                -- Resolve indirection (lowercase -> canonical name)
                itemData = Items[itemData]
            end
        end
    end

    if not itemData or type(itemData) ~= "table" then
        return nil
    end

    -- Return location info
    if itemData.inventoryID then
        return { type = "inventory", inventoryID = itemData.inventoryID, itemData = itemData }
    elseif itemData.bagID and itemData.slot then
        return { type = "bag", bag = itemData.bagID, slot = itemData.slot, itemData = itemData }
    end

    return nil
end

-- Fast item existence check using cache
-- @param item: item ID (number) or item name (string)
-- @return boolean
function CleveRoids.HasItemCached(item)
    return CleveRoids.FindItemLocation(item) ~= nil
end

-- Fast item cooldown lookup using cache
-- Enhanced with Nampower v2.18+ GetItemIdCooldown for detailed info
-- @param item: item ID (number) or item name (string)
-- @return remainingSeconds, totalDuration, enabled
function CleveRoids.GetItemCooldownCached(item)
    local location = CleveRoids.FindItemLocation(item)
    if not location then
        return 0, 0, 0
    end

    -- Try Nampower v2.18+ GetItemIdCooldown for more detailed info
    -- This requires knowing the item ID
    if GetItemIdCooldown then
        local itemId = nil

        -- Get item ID from location or input
        if location.itemData and location.itemData.id then
            itemId = location.itemData.id
        elseif type(item) == "number" and item > 19 then
            itemId = item
        else
            -- Extract item ID from inventory/bag link
            local link
            if location.type == "inventory" then
                link = GetInventoryItemLink("player", location.inventoryID)
            else
                link = GetContainerItemLink(location.bag, location.slot)
            end
            if link then
                local _, _, id = string.find(link, "item:(%d+)")
                if id then itemId = tonumber(id) end
            end
        end

        if itemId then
            local cdInfo = GetItemIdCooldown(itemId)
            if cdInfo then
                local remaining = (cdInfo.cooldownRemainingMs or 0) / 1000
                local duration = (cdInfo.individualDurationMs or cdInfo.categoryDurationMs or 0) / 1000
                local enabled = (cdInfo.isOnCooldown == 1) and 1 or 0
                return remaining, duration, enabled
            end
        end
    end

    -- Fallback to standard WoW API
    local start, duration, enable
    if location.type == "inventory" then
        start, duration, enable = GetInventoryItemCooldown("player", location.inventoryID)
    else
        start, duration, enable = GetContainerItemCooldown(location.bag, location.slot)
    end

    -- Normalize cooldown values
    start = tonumber(start) or 0
    duration = tonumber(duration) or 0
    enable = tonumber(enable) or 0

    if duration <= 0 or start <= 0 then
        return 0, 0, enable
    end

    local remaining = (start + duration) - GetTime()
    if remaining < 0 then remaining = 0 end

    return remaining, duration, enable
end

--This table maps stat keys to the functions that retrieve their values.
local stat_checks = {
    -- Base Stats (Corrected to use the 'effective' stat with gear)
    str = function() local _, effective = UnitStat("player", 1); return effective end,
    strength = function() local _, effective = UnitStat("player", 1); return effective end,
    agi = function() local _, effective = UnitStat("player", 2); return effective end,
    agility = function() local _, effective = UnitStat("player", 2); return effective end,
    stam = function() local _, effective = UnitStat("player", 3); return effective end,
    stamina = function() local _, effective = UnitStat("player", 3); return effective end,
    int = function() local _, effective = UnitStat("player", 4); return effective end,
    intellect = function() local _, effective = UnitStat("player", 4); return effective end,
    spi = function() local _, effective = UnitStat("player", 5); return effective end,
    spirit = function() local _, effective = UnitStat("player", 5); return effective end,

    -- Combat Ratings (Corrected to use UnitAttackPower and UnitRangedAttackPower)
    ap = function() local base, pos, neg = UnitAttackPower("player"); return base + pos + neg end,
    attackpower = function() local base, pos, neg = UnitAttackPower("player"); return base + pos + neg end,
    rap = function() local base, pos, neg = UnitRangedAttackPower("player"); return base + pos + neg end,
    rangedattackpower = function() local base, pos, neg = UnitRangedAttackPower("player"); return base + pos + neg end,
    healing = function() return GetBonusHealing() end,
    healingpower = function() return GetBonusHealing() end,

    -- Bonus Spell Damage by School
    arcane_power = function() return GetSpellBonusDamage(6) end,
    fire_power = function() return GetSpellBonusDamage(3) end,
    frost_power = function() return GetSpellBonusDamage(4) end,
    nature_power = function() return GetSpellBonusDamage(2) end,
    shadow_power = function() return GetSpellBonusDamage(5) end,

    -- Defensive Stats
    armor = function() local _, effective = UnitArmor("player"); return effective end,
    defense = function()
        local base, modifier = UnitDefense("player")
        return (base or 0) + (modifier or 0)
    end,

    -- Resistances
    arcane_res = function() local _, val = UnitResistance("player", 7); return val end,
    fire_res = function() local _, val = UnitResistance("player", 3); return val end,
    frost_res = function() local _, val = UnitResistance("player", 5); return val end,
    nature_res = function() local _, val = UnitResistance("player", 4); return val end,
    shadow_res = function() local _, val = UnitResistance("player", 6); return val end
}

-- PERFORMANCE: Avoid creating wrapper tables for single values
local function And(t, func)
    if type(func) ~= "function" then return false end
    -- PERFORMANCE: Handle non-table case without allocation
    if type(t) ~= "table" then
        return func(t) and true or false
    end
    for k, v in pairs(t) do
        if not func(v) then
            return false
        end
    end
    return true
end

local function Or(t, func)
    if type(func) ~= "function" then return false end
    -- PERFORMANCE: Handle non-table case without allocation
    if type(t) ~= "table" then
        return func(t) and true or false
    end
    for k, v in pairs(t) do
        if func(v) then
            return true
        end
    end
    return false
end

-- Helper to choose And() or Or() based on operator metadata
-- For positive conditionals (hp, power, cooldown, etc.):
--   - OR separator (/) uses Or() logic -> ANY value can match
--   - AND separator (&) uses And() logic -> ALL values must match
local function Multi(t, func, conditionals, condition)
    if type(func) ~= "function" then return false end

    -- PERFORMANCE: Handle non-table case without allocation
    if type(t) ~= "table" then
        return func(t) and true or false
    end

    -- Check for grouped structure (multiple instances of same conditional)
    -- Groups are AND'd together, values within each group use group's operator
    if conditionals and conditionals._groups and conditionals._groups[condition] then
        local groups = conditionals._groups[condition]
        -- All groups must pass (AND between groups)
        for _, group in ipairs(groups) do
            local groupPassed = false
            local groupOp = group.operator or "OR"

            if groupOp == "AND" then
                -- AND within group: ALL values must match
                groupPassed = true
                for _, v in ipairs(group.values) do
                    if not func(v) then
                        groupPassed = false
                        break
                    end
                end
            else
                -- OR within group: ANY value can match
                for _, v in ipairs(group.values) do
                    if func(v) then
                        groupPassed = true
                        break
                    end
                end
            end

            -- If any group fails, the whole conditional fails (AND between groups)
            if not groupPassed then return false end
        end
        return true
    end

    -- Fallback: Check operator type from metadata (single group / backwards compat)
    local operatorType = "OR" -- default
    if conditionals and conditionals._operators and conditionals._operators[condition] then
        operatorType = conditionals._operators[condition]
    end

    if operatorType == "AND" then
        -- AND separator (&): ALL must match
        for k, v in pairs(t) do
            if not func(v) then return false end
        end
        return true
    else
        -- OR separator (/) [default]: ANY can match
        for k, v in pairs(t) do
            if func(v) then return true end
        end
        return false
    end
end

-- Helper to choose And() or Or() based on operator metadata
-- For negated conditionals (nomybuff, nozone, etc.), operators are FLIPPED (De Morgan's law):
--   - OR separator (/) [default]: ALL must be missing (e.g., nobuff:X/Y = no X AND no Y)
--   - AND separator (&): ANY can be missing (e.g., nobuff:X&Y = no X OR no Y)
-- This matches natural language: "no X or Y" intuitively means "neither X nor Y"
local function NegatedMulti(t, func, conditionals, condition)
    if type(func) ~= "function" then return false end

    -- PERFORMANCE: Handle non-table case without allocation
    if type(t) ~= "table" then
        return func(t) and true or false
    end

    -- Check for grouped structure (multiple instances of same conditional)
    -- Groups are AND'd together, values within each group use FLIPPED group operator (De Morgan)
    if conditionals and conditionals._groups and conditionals._groups[condition] then
        local groups = conditionals._groups[condition]
        -- All groups must pass (AND between groups)
        for _, group in ipairs(groups) do
            local groupPassed = false
            local groupOp = group.operator or "OR"

            -- FLIPPED from positive conditionals (De Morgan's law for intuitive behavior)
            if groupOp == "AND" then
                -- AND separator (&) FLIPPED: ANY negation can pass (missing at least one)
                for _, v in ipairs(group.values) do
                    if func(v) then
                        groupPassed = true
                        break
                    end
                end
            else
                -- OR separator (/) FLIPPED: ALL negations must pass (missing all)
                groupPassed = true
                for _, v in ipairs(group.values) do
                    if not func(v) then
                        groupPassed = false
                        break
                    end
                end
            end

            -- If any group fails, the whole conditional fails (AND between groups)
            if not groupPassed then return false end
        end
        return true
    end

    -- Fallback: Check operator type from metadata (single group / backwards compat)
    local operatorType = "OR" -- default
    if conditionals and conditionals._operators and conditionals._operators[condition] then
        operatorType = conditionals._operators[condition]
    end

    -- FLIPPED from positive conditionals (De Morgan's law for intuitive behavior)
    if operatorType == "AND" then
        -- AND separator (&): ANY negation can pass (missing at least one)
        for k, v in pairs(t) do
            if func(v) then return true end
        end
        return false
    else
        -- OR separator (/) [default]: ALL negations must pass (missing all)
        for k, v in pairs(t) do
            if not func(v) then return false end
        end
        return true
    end
end

-- ============================================================================
-- THREAT TRACKING (reads server data via CHAT_MSG_ADDON like TWThreat)
-- ============================================================================

-- Storage for threat data
CleveRoids.ThreatData = {
    playerName = UnitName("player"),
    threats = {},      -- [playerName] = { threat, perc, tank, melee }
    lastUpdate = 0,
}

-- Parse threat packet from server (same format as TWThreat)
-- Format: TWTv4=player1:tank:threat:perc:melee;player2:tank:threat:perc:melee;...
local function ParseThreatPacket(packet)
    local threatApi = "TWTv4="
    local startPos = string.find(packet, threatApi, 1, true)
    if not startPos then return end

    local playersString = string.sub(packet, startPos + string.len(threatApi))
    local playerName = CleveRoids.ThreatData.playerName

    -- Clear old data
    CleveRoids.ThreatData.threats = {}
    CleveRoids.ThreatData.lastUpdate = GetTime()

    -- Split by semicolon
    for playerData in string.gfind(playersString, "[^;]+") do
        -- Split by colon: player:tank:threat:perc:melee
        local parts = {}
        for part in string.gfind(playerData, "[^:]+") do
            table.insert(parts, part)
        end

        if parts[1] and parts[2] and parts[3] and parts[4] and parts[5] then
            local name = parts[1]
            local tank = parts[2] == "1"
            local threat = tonumber(parts[3]) or 0
            local perc = tonumber(parts[4]) or 0
            local melee = parts[5] == "1"

            CleveRoids.ThreatData.threats[name] = {
                threat = threat,
                perc = perc,
                tank = tank,
                melee = melee,
            }
        end
    end
end

-- Get player's threat percentage
function CleveRoids.GetPlayerThreatPercent()
    local playerName = CleveRoids.ThreatData.playerName
    local data = CleveRoids.ThreatData.threats[playerName]
    if data then
        return data.perc
    end
    return nil
end

-- Create frame to listen for threat addon messages
local threatFrame = CreateFrame("Frame", "CleveRoidsThreatFrame")
threatFrame:RegisterEvent("CHAT_MSG_ADDON")
threatFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        -- arg1 = prefix, arg2 = message, arg3 = channel, arg4 = sender
        if arg2 and string.find(arg2, "TWTv4=", 1, true) then
            ParseThreatPacket(arg2)
        end
    end
end)

-- ============================================================================

-- pfUI debuff time helper (Vanilla 1.12.1 / Lua 5.0 safe)
local function PFUI_HasLibDebuff()
  return type(pfUI) == "table"
     and type(pfUI.api) == "table"
     and type(pfUI.api.libdebuff) == "table"
     and type(pfUI.api.libdebuff.UnitDebuff) == "function"
end

-- Helper: Get debuff time-left (seconds) from CleveRoids.libdebuff only
local function _get_debuff_timeleft(unitToken, auraName)
    -- Defensive: verify libdebuff is a table before accessing properties
    local lib = type(CleveRoids.libdebuff) == "table" and CleveRoids.libdebuff or nil

    -- SuperWoW path: GUID-based lookup
    -- SuperWoW debuff slots: 1-16 are regular debuffs, 17-48 overflow to buff slots 1-32
    if CleveRoids.hasSuperwow and lib then
        local _, guid = UnitExists(unitToken)
        if guid and lib.objects and lib.objects[guid] then
            -- Check 1-48: debuff slots 1-16 + overflow debuffs in buff slots 1-32
            -- NOTE: Slots 1-16 are dense (break on nil), slots 17-48 are sparse (continue on nil)
            -- Overflow debuffs in buff slots are mixed with regular buffs, so we can't break early
            for i = 1, 48 do
                local effect, _, _, _, _, duration, timeleft = lib:UnitDebuff(unitToken, i)
                -- Only break for slots 1-16 (regular debuffs are dense)
                -- For overflow slots 17-48, nil means "regular buff filtered out", not "end of list"
                if not effect and i <= 16 then break end
                if effect and effect == auraName and timeleft and timeleft >= 0 then
                    return timeleft, duration
                end
            end
        end
    end

    -- Non-SuperWoW fallback
    if lib and lib.UnitDebuff then
        for idx = 1, 48 do
            local effect, _, _, _, _, duration, timeleft = lib:UnitDebuff(unitToken, idx)
            -- Only break for slots 1-16 (regular debuffs are dense)
            -- For overflow slots 17-48, nil means "regular buff filtered out", not "end of list"
            if not effect and idx <= 16 then break end
            if effect and effect == auraName and timeleft and timeleft >= 0 then
                return timeleft, duration
            end
        end
    end

    return nil, nil
end

-- Validates that the given target is either friend (if [help]) or foe (if [harm])
-- target: The unit id to check
-- help: Optional. If set to 1 then the target must be friendly. If set to 0 it must be an enemy.
-- remarks: Will always return true if help is not given
-- returns: Whether or not the given target can either be attacked or supported, depending on help
function CleveRoids.CheckHelp(target, help)
    if help == nil then return true end
    if help then
        return UnitCanAssist("player", target)
    else
        return UnitCanAttack("player", target)
    end
end

-- Ensures the validity of the given target
-- target: The unit id to check
-- help: Optional. If set to 1 then the target must be friendly. If set to 0 it must be an enemy
-- returns: Whether or not the target is a viable target
function CleveRoids.IsValidTarget(target, help)
    -- If the conditional is not for @mouseover, use the existing logic.
    if target ~= "mouseover" then
        if not UnitExists(target) or not CleveRoids.CheckHelp(target, help) then
            return false
        end
        return true
    end

    -- --- START OF PATCH ---
    -- New logic to handle [@mouseover] with pfUI compatibility.

    local effectiveMouseoverUnit = "mouseover" -- Start with the default game token.

    -- Check if the default mouseover exists. If not, check pfUI's internal data,
    -- which is necessary because pfUI frames don't always update the default token.
    if not UnitExists(effectiveMouseoverUnit) then
        if pfUI and pfUI.uf and pfUI.uf.mouseover and pfUI.uf.mouseover.unit and UnitExists(pfUI.uf.mouseover.unit) then
            -- If pfUI has a valid mouseover unit recorded, use that instead.
            effectiveMouseoverUnit = pfUI.uf.mouseover.unit
        else
            -- If neither the default token nor the pfUI unit exists, there's no valid mouseover.
            return false
        end
    end
    -- --- END OF PATCH ---

    -- Finally, perform the help/harm check on the determined mouseover unit (either from the game or from pfUI).
    if not UnitExists(effectiveMouseoverUnit) or not CleveRoids.CheckHelp(effectiveMouseoverUnit, help) then
        return false
    end

    return true
end

-- Returns the current shapeshift / stance index
-- returns: The index of the current shapeshift form / stance. 0 if in no shapeshift form / stance
function CleveRoids.GetCurrentShapeshiftIndex()
    if CleveRoids.playerClass == "PRIEST" then
        return CleveRoids.ValidatePlayerBuff(CleveRoids.Localized.Spells["Shadowform"]) and 1 or 0
    elseif CleveRoids.playerClass == "ROGUE" then
        return CleveRoids.ValidatePlayerBuff(CleveRoids.Localized.Spells["Stealth"]) and 1 or 0
    end
    for i=1, GetNumShapeshiftForms() do
        _, _, active = GetShapeshiftFormInfo(i)
        if active then
            return i
        end
    end

    return 0
end

function CleveRoids.CancelAura(auraName)
	local ix = 0
    auraName = string.lower(string.gsub(auraName, "_"," "))
	while true do
		local aura_ix = GetPlayerBuff(ix,"HELPFUL")
		ix = ix + 1
		if aura_ix == -1 then break end

		if CleveRoids.hasSuperwow then
			local bid = GetPlayerBuffID(aura_ix)
			bid = (bid < -1) and (bid + 65536) or bid
			if string.lower(SpellInfo(bid)) == auraName then
				CancelPlayerBuff(aura_ix)
				return true
			end
		else
			AuraScanTooltip:SetPlayerBuff(aura_ix)
			local name = string.lower(getglobal("AuraScanTooltipTextLeft1"):GetText())
			if name == auraName then
				CancelPlayerBuff(aura_ix)
				break
			end
		end

	end
	return false
end

function CleveRoids.HasGearEquipped(gearId)
    if not gearId then return false end

    -- PERFORMANCE: Build/refresh equipment cache if needed
    BuildEquipmentCache()

    -- Handle both numeric IDs and string IDs like "5196"
    local wantId = tonumber(gearId)
    local wantName = (type(gearId) == "string" and not wantId) and string.lower(gearId) or nil

    -- PERFORMANCE: Use cached data instead of scanning all slots
    for slot = 1, 19 do
        if wantId and _equippedItemIDs[slot] == wantId then
            return true
        end
        if wantName and _equippedItemNames[slot] == wantName then
            return true
        end
    end
    return false
end


-- Checks whether or not the given weaponType is currently equipped
-- weaponType: The name of the weapon's type (e.g. Axe, Shield, etc.)
-- returns: True when equipped, otherwhise false
function CleveRoids.HasWeaponEquipped(weaponType)
    if not CleveRoids.WeaponTypeNames[weaponType] then
        return false
    end

    local slotName = CleveRoids.WeaponTypeNames[weaponType].slot
    local localizedName = CleveRoids.WeaponTypeNames[weaponType].name
    local slotId = GetInventorySlotInfo(slotName)
    local slotLink = GetInventoryItemLink("player",slotId)

    if not slotLink then
        return false
    end

    local _,_,itemId = string.find(slotLink,"item:(%d+)")
    if not itemId then -- Also good to check if itemId was found
        return false
    end
    local _name,_link,_,_lvl,_type,subtype = GetItemInfo(itemId)
    -- just had to be special huh?
    local fist = string.find(subtype,"^Fist")
    -- drops things like the One-Handed prefix
    local _,_,subtype = string.find(subtype,"%s?(%S+)$")

    if subtype == localizedName or (fist and (CleveRoids.WeaponTypeNames[weaponType].name == CleveRoids.Localized.FistWeapon)) then
        return true
    end

    return false
end

-- Checks whether or not the given UnitId is in your party or your raid
-- target: The UnitId of the target to check
-- groupType: The name of the group type your target has to be in ("party" or "raid")
-- returns: True when the given target is in the given groupType, otherwhise false
function CleveRoids.IsTargetInGroupType(target, groupType)
    local groupSize = (groupType == "raid") and 40 or 5

    for i = 1, groupSize do
        if UnitIsUnit(groupType..i, target) then
            return true
        end
    end

    return false
end

function CleveRoids.GetSpammableConditional(name)
    return CleveRoids.spamConditions[name] or "nomybuff"
end

-- Checks whether or not we're currently casting a spell with cast time
-- Returns TRUE if we should allow the cast (not casting, or not casting the specified spell)
-- Returns FALSE if we should block the cast (currently casting)
function CleveRoids.CheckCasting(castingSpell)
    -- No parameter: check if we're casting ANYTHING
    if not castingSpell or castingSpell == "" then
        -- Time-based prediction: if we know cast duration, check if it should be done
        if CleveRoids.CurrentSpell.type == "cast" and CleveRoids.castStartTime and CleveRoids.castDuration then
            local elapsed = GetTime() - CleveRoids.castStartTime
            local remaining = CleveRoids.castDuration - elapsed

            -- If cast should be done (with 0.1s grace period), treat as not casting
            if remaining <= 0.1 then
                CleveRoids.CurrentSpell.type = ""
                return true
            end
        end

        return CleveRoids.CurrentSpell.type ~= "cast"
    end

    -- With parameter: check if we're casting a specific spell
    local spellName = string.gsub(CleveRoids.CurrentSpell.spellName or "", "%(.-%)%s*", "")
    local casting = string.gsub(castingSpell, "%(.-%)%s*", "")

    -- If we're casting this specific spell, block the recast
    if CleveRoids.CurrentSpell.type == "cast" and spellName == casting then
        return false
    end

    -- Not casting the specified spell, allow the cast
    return true
end

-- Checks whether or not we're currently casting a channeled spell
-- Returns TRUE if we should allow the cast (not channeling, or not channeling the specified spell)
-- Returns FALSE if we should block the cast (currently channeling)
function CleveRoids.CheckChanneled(channeledSpell)
    -- No parameter: check if we're channeling ANYTHING
    if not channeledSpell or channeledSpell == "" then
        -- Time-based prediction: if we know channel duration, check if it should be done
        if CleveRoids.CurrentSpell.type == "channeled" and CleveRoids.channelStartTime and CleveRoids.channelDuration then
            local elapsed = GetTime() - CleveRoids.channelStartTime
            local remaining = CleveRoids.channelDuration - elapsed

            -- If channel should be done (with 0.1s grace period), treat as not channeling
            if remaining <= 0.1 then
                CleveRoids.CurrentSpell.type = ""
                return true
            end
        end

        return CleveRoids.CurrentSpell.type ~= "channeled"
    end

    -- Remove the "(Rank X)" part from the spells name in order to allow downranking
    local spellName = string.gsub(CleveRoids.CurrentSpell.spellName or "", "%(.-%)%s*", "")
    local channeled = string.gsub(channeledSpell, "%(.-%)%s*", "")

    -- If we're channeling this specific spell, block the recast
    if CleveRoids.CurrentSpell.type == "channeled" and spellName == channeled then
        return false
    end

    -- Special cases for auto-attacks
    if channeled == CleveRoids.Localized.Attack then
        return not CleveRoids.CurrentSpell.autoAttack
    end

    if channeled == CleveRoids.Localized.AutoShot then
        return not CleveRoids.CurrentSpell.autoShot
    end

    if channeled == CleveRoids.Localized.Shoot then
        return not CleveRoids.CurrentSpell.wand
    end

    -- If none of the special cases matched, allow the cast (not channeling the specified spell)
    return true
end

function CleveRoids.ValidateComboPoints(operator, amount)
    if not operator or not amount then return false end
    local points = GetComboPoints()

    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](points, amount)
    end

    return false
end

-- Validates swing timer percentage for SP_SwingTimer addon integration
-- operator: Comparison operator (>, <, =, >=, <=, ~=)
-- amount: Percentage of swing time elapsed (e.g., 20 means 20% of swing has elapsed)
-- returns: True if percentElapsed [operator] amount
function CleveRoids.ValidateSwingTimer(operator, amount)
    if not operator or not amount then return false end

    -- Check if SP_SwingTimer is loaded by checking for st_timer global
    if st_timer == nil then
        -- Only show error once per session
        if not CleveRoids._swingTimerErrorShown then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [swingtimer] conditional requires the SP_SwingTimer addon. Get it at: https://github.com/jrc13245/SP_SwingTimer", 1, 0.5, 0.5)
            CleveRoids._swingTimerErrorShown = true
        end
        return false
    end

    -- Get player's attack speed (main hand)
    local attackSpeed = UnitAttackSpeed("player")
    if not attackSpeed or attackSpeed <= 0 then return false end

    -- Calculate percentage of swing elapsed
    -- st_timer counts down from attackSpeed to 0 (time remaining)
    -- So: timeElapsed = attackSpeed - st_timer
    local timeElapsed = attackSpeed - st_timer
    local percentElapsed = (timeElapsed / attackSpeed) * 100

    -- Compare percent elapsed against threshold
    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](percentElapsed, amount)
    end

    return false
end

-- Constants for Slam window calculations
local GCD_DURATION = 1.5  -- Global cooldown in seconds
local DEFAULT_SLAM_CAST = 2.5  -- Default Slam cast time in Turtle WoW

-- Cache for Slam cast time from tooltip
local cachedSlamCastTime = nil
local slamCastTimeLastUpdate = 0
local SLAM_CACHE_DURATION = 2  -- Re-scan tooltip every 2 seconds

-- Hidden tooltip for scanning spell info
local SlamScanTooltip = nil

-- Create hidden tooltip for scanning (once)
local function GetSlamScanTooltip()
    if not SlamScanTooltip then
        SlamScanTooltip = CreateFrame("GameTooltip", "CleveRoidsSlamScanTooltip", nil, "GameTooltipTemplate")
        SlamScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return SlamScanTooltip
end

-- Parse cast time from tooltip text (e.g., "1.5 sec cast" or "1.59 sec cast")
local function ParseCastTimeFromText(text)
    if not text then return nil end
    -- Match patterns like "1.5 sec cast", "1.59 sec cast", "2 sec cast"
    local castTime = string.match(text, "(%d+%.?%d*) sec cast")
    if castTime then
        return tonumber(castTime)
    end
    return nil
end

-- Get Slam's spellbook slot
local function GetSlamSpellSlot()
    -- Search through spellbook for Slam
    local i = 1
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        if spellName == "Slam" then
            return i, BOOKTYPE_SPELL
        end
        i = i + 1
    end
    return nil, nil
end
-- Expose for debug command
CleveRoids.GetSlamSpellSlot = GetSlamSpellSlot

-- Scan Slam tooltip for cast time
local function ScanSlamCastTime()
    local slot, bookType = GetSlamSpellSlot()
    if not slot then return nil end

    local tooltip = GetSlamScanTooltip()
    tooltip:ClearLines()
    tooltip:SetSpell(slot, bookType)

    -- Scan tooltip lines for cast time
    for i = 1, tooltip:NumLines() do
        local leftText = getglobal("CleveRoidsSlamScanTooltipTextLeft" .. i)
        if leftText then
            local text = leftText:GetText()
            local castTime = ParseCastTimeFromText(text)
            if castTime then
                return castTime
            end
        end
        local rightText = getglobal("CleveRoidsSlamScanTooltipTextRight" .. i)
        if rightText then
            local text = rightText:GetText()
            local castTime = ParseCastTimeFromText(text)
            if castTime then
                return castTime
            end
        end
    end

    return nil
end

-- Get Slam's cast time in seconds (with caching)
-- Reads from spellbook tooltip to get accurate cast time with haste/talents
function CleveRoids.GetSlamCastTime()
    local now = GetTime()

    -- Use cached value if still valid
    if cachedSlamCastTime and (now - slamCastTimeLastUpdate) < SLAM_CACHE_DURATION then
        return cachedSlamCastTime
    end

    -- Try to scan tooltip for cast time
    local castTime = ScanSlamCastTime()
    if castTime and castTime > 0 then
        cachedSlamCastTime = castTime
        slamCastTimeLastUpdate = now
        return castTime
    end

    -- Fall back to default
    return DEFAULT_SLAM_CAST
end

-- Force refresh of cached Slam cast time (call when buffs change)
function CleveRoids.RefreshSlamCastTime()
    cachedSlamCastTime = nil
    slamCastTimeLastUpdate = 0
end

-- Calculate maximum elapsed swing timer % to cast Slam without clipping auto-attack
-- Formula: MaxSlamPercent = (SwingTimer - SlamCastTime) / SwingTimer * 100
function CleveRoids.GetSlamWindowPercent()
    local attackSpeed = UnitAttackSpeed("player")
    if not attackSpeed or attackSpeed <= 0 then return 0 end

    local slamCastTime = CleveRoids.GetSlamCastTime()
    local maxSlamStart = attackSpeed - slamCastTime

    if maxSlamStart <= 0 then return 0 end  -- Slam cast time exceeds swing timer

    return (maxSlamStart / attackSpeed) * 100
end

-- Calculate maximum elapsed swing timer % to cast instant without clipping NEXT Slam
-- Scenario: No Slam this swing, cast instant, then Slam next swing without clipping
-- Formula: MaxInstantPercent = (2 * SwingTimer - SlamCastTime - GCD) / SwingTimer * 100
function CleveRoids.GetInstantWindowPercent()
    local attackSpeed = UnitAttackSpeed("player")
    if not attackSpeed or attackSpeed <= 0 then return 0 end

    local slamCastTime = CleveRoids.GetSlamCastTime()
    local maxInstantStart = (2 * attackSpeed) - slamCastTime - GCD_DURATION

    if maxInstantStart <= 0 then return 0 end  -- Window is impossible with current timings

    return (maxInstantStart / attackSpeed) * 100
end

-- Validate if current swing timer is within the Slam window (no clip)
-- Returns true if casting Slam NOW will NOT clip the auto-attack
function CleveRoids.ValidateNoSlamClip()
    -- Check if SP_SwingTimer is loaded
    if st_timer == nil then
        if not CleveRoids._slamClipErrorShown then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [noslamclip] conditional requires the SP_SwingTimer addon. Get it at: https://github.com/jrc13245/SP_SwingTimer", 1, 0.5, 0.5)
            CleveRoids._slamClipErrorShown = true
        end
        return false
    end

    local attackSpeed = UnitAttackSpeed("player")
    if not attackSpeed or attackSpeed <= 0 then return false end

    local timeElapsed = attackSpeed - st_timer
    local percentElapsed = (timeElapsed / attackSpeed) * 100
    local maxPercent = CleveRoids.GetSlamWindowPercent()

    return percentElapsed <= maxPercent
end

-- Validate if current swing timer is within the instant window for next Slam
-- Returns true if casting an instant NOW will NOT cause the NEXT Slam to clip
function CleveRoids.ValidateNoNextSlamClip()
    -- Check if SP_SwingTimer is loaded
    if st_timer == nil then
        if not CleveRoids._slamClipErrorShown then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [nonextslamclip] conditional requires the SP_SwingTimer addon. Get it at: https://github.com/jrc13245/SP_SwingTimer", 1, 0.5, 0.5)
            CleveRoids._slamClipErrorShown = true
        end
        return false
    end

    local attackSpeed = UnitAttackSpeed("player")
    if not attackSpeed or attackSpeed <= 0 then return false end

    local timeElapsed = attackSpeed - st_timer
    local percentElapsed = (timeElapsed / attackSpeed) * 100
    local maxPercent = CleveRoids.GetInstantWindowPercent()

    return percentElapsed <= maxPercent
end

function CleveRoids.ValidateLevel(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local level = UnitLevel(unit)

    -- Treat skull/boss mobs (??) as level 63
    if level == -1 then
        level = 63
    end

    if level and CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](level, amount)
    end

    return false
end

--- Validates a threat percentage conditional using server threat data.
--- Usage: [threat:>80] [threat:<50] [threat:=100]
--- operator: Comparison operator (>, <, =, >=, <=, ~=)
--- amount: Threat percentage (0-100+, where 100 = will pull aggro)
--- returns: True if playerThreat [operator] amount
--- Note: Requires TWThreat addon to be running (sends threat requests to server)
function CleveRoids.ValidateThreat(operator, amount)
    if not operator or not amount then return false end

    -- Get threat percentage from parsed server data
    local threatpct = CleveRoids.GetPlayerThreatPercent()

    -- No threat data available
    if threatpct == nil then
        return false
    end

    -- Compare threat percentage against threshold
    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](threatpct, amount)
    end

    return false
end

--- Validates a Time-To-Kill conditional using TimeToKill addon.
--- Usage: [ttk:<10] [ttk:>30] [ttk:=5]
--- operator: Comparison operator (>, <, =, >=, <=, ~=)
--- amount: Time in seconds until target death
--- returns: True if TTK [operator] amount
function CleveRoids.ValidateTTK(operator, amount)
    if not operator or not amount then return false end

    -- Check if TimeToKill is loaded
    if type(TimeToKill) ~= "table" or type(TimeToKill.GetTTK) ~= "function" then
        -- Only show error once per session
        if not CleveRoids._ttkErrorShown then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [ttk] conditional requires the TimeToKill addon.", 1, 0.5, 0.5)
            CleveRoids._ttkErrorShown = true
        end
        return false
    end

    local ttk = TimeToKill.GetTTK()
    if ttk == nil then
        return false -- Not tracking TTK
    end

    -- Compare TTK against threshold
    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](ttk, amount)
    end

    return false
end

--- Validates a Time-To-Execute conditional using TimeToKill addon.
--- Usage: [tte:<5] [tte:>10]
--- operator: Comparison operator (>, <, =, >=, <=, ~=)
--- amount: Time in seconds until target reaches 20% HP
--- returns: True if TTE [operator] amount
function CleveRoids.ValidateTTE(operator, amount)
    if not operator or not amount then return false end

    -- Check if TimeToKill is loaded
    if type(TimeToKill) ~= "table" or type(TimeToKill.GetTTE) ~= "function" then
        if not CleveRoids._ttkErrorShown then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [tte] conditional requires the TimeToKill addon.", 1, 0.5, 0.5)
            CleveRoids._ttkErrorShown = true
        end
        return false
    end

    local tte = TimeToKill.GetTTE()
    if tte == nil then
        return false -- Not tracking or already in execute phase
    end

    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](tte, amount)
    end

    return false
end

function CleveRoids.ValidateKnown(args)
    if not args then
        return false
    end
    if table.getn(CleveRoids.Talents) == 0 then
        CleveRoids.IndexTalents()
    end

    local effective_name_to_check
    local original_args_for_rank_check = args

    if type(args) ~= "table" then
        effective_name_to_check = args
        args = { name = args }
    else
        effective_name_to_check = args.name
    end

    local spell = CleveRoids.GetSpell(effective_name_to_check)
    local talent_points = nil

    if not spell then
        talent_points = CleveRoids.GetTalent(effective_name_to_check)
    end

    if not spell and talent_points == nil then
        return false
    end

    local arg_amount = nil
    local arg_operator = nil
    if type(original_args_for_rank_check) == "table" then
        arg_amount = original_args_for_rank_check.amount
        arg_operator = original_args_for_rank_check.operator
    end

    if spell then
        local spell_rank_str = spell.rank or (spell.highest and spell.highest.rank) or ""
        -- FLEXIBLY extract just the number from the rank string
        local _, _, spell_rank_num_str = string.find(spell_rank_str, "(%d+)")

        if not arg_amount and not arg_operator then
            return true
        elseif arg_amount and arg_operator and CleveRoids.operators[arg_operator] and spell_rank_num_str and spell_rank_num_str ~= "" then
            local numeric_rank = tonumber(spell_rank_num_str)
            if numeric_rank then
                return CleveRoids.comparators[arg_operator](numeric_rank, arg_amount)
            else
                return false
            end
        else
            return false
        end
    elseif talent_points ~= nil then
        if not arg_amount and not arg_operator then
            return talent_points > 0
        elseif arg_amount and arg_operator and CleveRoids.operators[arg_operator] then
            return CleveRoids.comparators[arg_operator](talent_points, arg_amount)
        else
            return false
        end
    end

    return false
end

function CleveRoids.ValidateResting()
    return IsResting()
end


-- TODO: refactor numeric comparisons...

-- Checks whether or not the given unit has power in percent vs the given amount
-- unit: The unit we're checking
-- operator: valid comparitive operator symbol
-- amount: The required amount
-- returns: True or false
function CleveRoids.ValidatePower(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local powerPercent = 100 / UnitManaMax(unit) * UnitMana(unit)

    if powerPercent and CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](powerPercent, amount)
    end

    return false
end

-- Checks whether or not the given unit has current power vs the given amount
-- unit: The unit we're checking
-- operator: valid comparitive operator symbol
-- amount: The required amount
-- returns: True or false
function CleveRoids.ValidateRawPower(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local power = UnitMana(unit)

    if power and CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](power, amount)
    end

    return false
end

-- Raw caster-form mana for druids (SuperWoW: 2nd return of UnitMana)
function CleveRoids.ValidateDruidRawMana(unit, operator, amount)
    unit = unit or "player"
    if not operator or amount == nil then return false end
    if (CleveRoids.playerClass ~= "DRUID") then return false end

    -- SuperWoW returns: current-form power, caster-form mana
    local _, casterMana = UnitMana(unit)

    -- Fallback: if for some reason we didn't get a 2nd value and we're in caster form now
    if type(casterMana) ~= "number" then
        if UnitPowerType and UnitPowerType(unit) == 0 then
            casterMana = UnitMana(unit)
        else
            return false
        end
    end

    local cmp = CleveRoids.comparators and CleveRoids.comparators[operator]
    return cmp and cmp(casterMana, amount) or false
end

-- Checks whether or not the given unit has a power deficit vs the amount specified
-- unit: The unit we're checking
-- operator: valid comparitive operator symbol
-- amount: The required amount
-- returns: True or false
function CleveRoids.ValidatePowerLost(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local powerLost = UnitManaMax(unit) - UnitMana(unit)

    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](powerLost, amount)
    end

    return false
end

-- Checks whether or not the given unit has hp in percent vs the given amount
-- unit: The unit we're checking
-- operator: valid comparitive operator symbol
-- amount: The required amount
-- returns: True or false
function CleveRoids.ValidateHp(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local hpPercent = 100 / UnitHealthMax(unit) * UnitHealth(unit)

    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](hpPercent, amount)
    end

    return false
end

-- Checks whether or not the given unit has hp vs the given amount
-- unit: The unit we're checking
-- operator: valid comparitive operator symbol
-- amount: The required amount
-- returns: True or false
function CleveRoids.ValidateRawHp(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local rawhp = UnitHealth(unit)

    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](rawhp, amount)
    end

    return false
end

-- Checks whether or not the given unit has an hp deficit vs the amount specified
-- unit: The unit we're checking
-- operator: valid comparitive operator symbol
-- amount: The required amount
-- returns: True or false
function CleveRoids.ValidateHpLost(unit, operator, amount)
    if not unit or not operator or not amount then return false end
    local hpLost = UnitHealthMax(unit) - UnitHealth(unit)

    if CleveRoids.operators[operator] then
        return CleveRoids.comparators[operator](hpLost, amount)
    end

    return false
end

-- Checks whether the given creatureType is the same as the target's creature type
-- creatureType: The type to check
-- target: The target's unitID
-- returns: True or false
-- remarks: Allows for both localized and unlocalized type names
function CleveRoids.ValidateCreatureType(creatureType, target)
    if not target then return false end
    local targetType = UnitCreatureType(target)
    if not targetType then return false end -- ooze or silithid etc
    local ct = string.lower(creatureType)
    local cl = UnitClassification(target)
    -- Check classification: "boss" matches both "boss" and "worldboss"
    if ct == "boss" then
        if cl == "boss" or cl == "worldboss" then
            return true
        end
    elseif ct == cl then
        return true
    end
    if ct == "boss" then creatureType = "worldboss" end
    local englishType = CleveRoids.Localized.CreatureTypes[targetType]
    return ct == string.lower(targetType) or creatureType == englishType
end

-- TODO: Look into https://github.com/Stanzilla/WoWUIBugs/issues/47 if needed
function CleveRoids.ValidateCooldown(args, ignoreGCD)
    if not args then return false end

    local name
    if type(args) ~= "table" then
        -- PERFORMANCE: Use cached normalization
        name = CleveRoids.NormalizeName(args)

        -- If this is a numeric slot (1-19), resolve to the equipped item's name
        local slotNum = tonumber(name)
        if slotNum and slotNum >= 1 and slotNum <= 19 then
            local link = GetInventoryItemLink("player", slotNum)
            if link then
                local _, _, itemName = string.find(link, "%[(.+)%]")
                if itemName then name = itemName end
            end
        end
        args = {name = name}
    else
        if args.name then
            -- PERFORMANCE: Use cached normalization
            name = CleveRoids.NormalizeName(args.name)

            -- If this is a numeric slot (1-19), resolve to the equipped item's name
            local slotNum = tonumber(name)
            if slotNum and slotNum >= 1 and slotNum <= 19 then
                local link = GetInventoryItemLink("player", slotNum)
                if link then
                    local _, _, itemName = string.find(link, "%[(.+)%]")
                    if itemName then name = itemName end
                end
            end
            args.name = name
        else
            name = args.name
        end
    end

    -- PERFORMANCE: GetCooldown is now cached per-frame
    local expires = CleveRoids.GetCooldown(args.name, ignoreGCD)
    local now = CleveRoids.GetCachedTime()

    if not args.operator and not args.amount then
        return expires > now
    elseif CleveRoids.operators[args.operator] then
        return CleveRoids.comparators[args.operator](expires - now, args.amount)
    end
end

function CleveRoids.GetPlayerAura(index, isbuff)
    if not index then return false end

    local buffType = isbuff and "HELPFUL" or "HARMFUL"
    local bid = GetPlayerBuff(index, buffType)
    if bid < 0 then return end

    local spellID = CleveRoids.hasSuperwow and GetPlayerBuffID(bid)

    return GetPlayerBuffTexture(bid), GetPlayerBuffApplications(bid), spellID, GetPlayerBuffTimeLeft(bid)
end

-- PERFORMANCE: Local function refs and reusable pattern for buff checking
local _string_lower = string.lower
local _string_gsub = string.gsub
local _RANK_PATTERN = "%s*%(%s*Rank%s+%d+%s*%)"

-- PERFORMANCE: Simple cache for lowercase spell names (cleared periodically)
local _spellNameCache = {}
local _spellNameCacheSize = 0
local _MAX_SPELL_CACHE = 200

-- PERFORMANCE: Cache for base spell names (rank stripped, not lowercased)
local _baseNameCache = {}
local _baseNameCacheSize = 0

local function GetLowercaseSpellName(spellID)
    local cached = _spellNameCache[spellID]
    if cached then return cached end

    local name = SpellInfo(spellID)
    if not name then return nil end

    -- Strip rank and lowercase
    local baseName = _string_gsub(name, _RANK_PATTERN, "")
    local lowerName = _string_lower(baseName)

    -- Cache if not too large
    if _spellNameCacheSize < _MAX_SPELL_CACHE then
        _spellNameCache[spellID] = lowerName
        _spellNameCacheSize = _spellNameCacheSize + 1
    end

    return lowerName
end

-- PERFORMANCE: Get base spell name (rank stripped) and full name - cached
local function GetSpellNames(spellID)
    local cached = _baseNameCache[spellID]
    if cached then
        return cached.base, cached.full
    end

    local fullName = SpellInfo(spellID)
    if not fullName then return nil, nil end

    local baseName = _string_gsub(fullName, _RANK_PATTERN, "")

    -- Cache if not too large
    if _baseNameCacheSize < _MAX_SPELL_CACHE then
        _baseNameCache[spellID] = { base = baseName, full = fullName }
        _baseNameCacheSize = _baseNameCacheSize + 1
    end

    return baseName, fullName
end

-- Clear spell name caches (called periodically from Core.lua cleanup)
function CleveRoids.ClearSpellNameCaches()
    for k in pairs(_spellNameCache) do
        _spellNameCache[k] = nil
    end
    _spellNameCacheSize = 0

    for k in pairs(_baseNameCache) do
        _baseNameCache[k] = nil
    end
    _baseNameCacheSize = 0
end

function CleveRoids.ValidateAura(unit, args, isbuff)
    if not args or not UnitExists(unit) then return false end

    if not CleveRoids.hasSuperwow then
        return false
    end

    if type(args) ~= "table" then
        args = {name = args}
    end

    local isPlayer = UnitIsUnit(unit, "player")
    local found = false
    local stacks, remaining
    local i = isPlayer and 0 or 1

    -- PERFORMANCE: Cache lowercased search name to avoid repeated string.lower calls
    local searchName = args.name and _string_lower(args.name)

    -- Primary search: BUFFS if isbuff==true, DEBUFFS if isbuff==false
    while true do
        local texture
        local current_spellID = nil

        if isPlayer then
            -- GetPlayerAura(index, isbuff) => texture, stacks, spellID, timeLeft
            texture, stacks, current_spellID, remaining = CleveRoids.GetPlayerAura(i, isbuff)
        else
            if isbuff then
                -- UnitBuff => texture, stacks, spellID
                texture, stacks, current_spellID = UnitBuff(unit, i)
            else
                -- UnitDebuff => texture, stacks, debuffType, spellID
                texture, stacks, _, current_spellID = UnitDebuff(unit, i)
            end
            remaining = nil
        end

        if not texture then break end

        if current_spellID and searchName then
            -- PERFORMANCE: Use cached lowercase spell name lookup
            local lowerName = GetLowercaseSpellName(current_spellID)
            if lowerName and lowerName == searchName then
                found = true
                break
            end
        end

        i = i + 1
    end

    -- Overflow handling: when searching DEBUFFS on non-players, also scan BUFFS
    if not isbuff and not isPlayer and not found and searchName then
        i = 1
        while true do
            local texture
            local current_spellID = nil

            -- UnitBuff => texture, stacks, spellID
            texture, stacks, current_spellID = UnitBuff(unit, i)
            if not texture then break end

            if current_spellID then
                -- PERFORMANCE: Use cached lowercase spell name lookup
                local lowerName = GetLowercaseSpellName(current_spellID)
                if lowerName and lowerName == searchName then
                    found = true
                    break
                end
            end

            i = i + 1
        end
    end

    local ops = CleveRoids.operators

    -- Handle multi-comparison (e.g., >0&<10)
    if args.comparisons and type(args.comparisons) == "table" then
        if not found then
            return false  -- Aura doesn't exist, so all comparisons fail
        end

        -- ALL comparisons must pass (AND logic)
        for _, comp in ipairs(args.comparisons) do
            if not ops[comp.operator] then
                return false  -- Invalid operator
            end

            local value_to_check
            if comp.checkStacks then
                value_to_check = stacks or -1
            elseif isPlayer then
                value_to_check = remaining or -1
            else
                -- Non-player units don't have remaining time, only check existence
                return found
            end

            if not CleveRoids.comparators[comp.operator](value_to_check, comp.amount) then
                return false  -- One comparison failed
            end
        end
        return true  -- All comparisons passed
    end

    -- Single comparison (backward compatibility)
    if not args.amount and not args.operator and not args.checkStacks then
        return found
    elseif isPlayer and not args.checkStacks and args.amount and ops[args.operator] then
        return CleveRoids.comparators[args.operator](remaining or -1, args.amount)
    elseif args.amount and args.checkStacks and ops[args.operator] then
        return CleveRoids.comparators[args.operator](stacks or -1, args.amount)
    else
        return false
    end
end

function CleveRoids.ValidateUnitBuff(unit, args)
    return CleveRoids.ValidateAura(unit, args, true)
end

function CleveRoids.ValidateUnitDebuff(unit, args)
    if not args or not UnitExists(unit) then return false end
    if type(args) ~= "table" then
        args = { name = args }
    end
    if not args.name then return false end

    local found = false
    local texture, stacks, spellID, remaining
    local i

    -- PERFORMANCE: For non-SuperWoW, early return if no texture registered
    if not CleveRoids.hasSuperwow and not CleveRoids.auraTextures[args.name] then
        return false
    end

    -- For non-player units, check tracking table directly
    -- SIMPLE: Did the player cast this spell? Is the timer still valid?
    -- Defensive: verify libdebuff is a table before accessing properties
    local lib = type(CleveRoids.libdebuff) == "table" and CleveRoids.libdebuff or nil
    if unit ~= "player" and lib and lib.objects then
        local _, guid = UnitExists(unit)
        if not guid then return false end

        -- Normalize GUID to string for consistent table key lookups
        guid = CleveRoids.NormalizeGUID(guid)
        if not guid then return false end

        -- PERFORMANCE: Use cached spell name -> ID mapping instead of iterating every call
        local matchingSpellIDs = GetSpellIDsForName(args.name) or {}

        -- Check tracking table for ANY rank of this spell: Did player cast this? Is timer valid?
        if matchingSpellIDs and table.getn(matchingSpellIDs) > 0 then
            for _, spellID in ipairs(matchingSpellIDs) do
                local rec = lib.objects[guid] and lib.objects[guid][spellID]
                -- For shared debuffs (Sunder, Faerie Fire, etc.), accept any caster (including nil)
                -- For personal debuffs (Rip, Rupture, etc.), only accept player casts
                local isSharedDebuff = lib.IsPersonalDebuff and lib:IsPersonalDebuff(spellID) == false
                if rec and rec.duration and rec.start and (isSharedDebuff or rec.caster == "player") then
                    local timeRemaining = rec.duration + rec.start - GetTime()
                    if timeRemaining > 0 then
                        found = true
                        remaining = timeRemaining
                        stacks = rec.stacks or 0

                        if CleveRoids.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(
                                string.format("|cff00ff00[Tracking]|r %s (ID:%d): %.1fs left", args.name, spellID, timeRemaining)
                            )
                        end

                        -- Get texture (optional, just for display)
                        for i = 1, 16 do
                            local _, _, _, sid = UnitDebuff(unit, i)
                            if sid == spellID then
                                texture = UnitDebuff(unit, i)
                                break
                            end
                        end
                        if not texture then
                            for i = 1, 32 do
                                local _, _, sid = UnitBuff(unit, i)
                                if sid == spellID then
                                    texture = UnitBuff(unit, i)
                                    break
                                end
                            end
                        end

                        -- Found active debuff, stop searching
                        break
                    elseif rec then
                        -- Debuff expired - remove it from tracking to avoid spam
                        local expiredTime = GetTime() - (rec.start + rec.duration)
                        if CleveRoids.debug and expiredTime < 2.0 then
                            DEFAULT_CHAT_FRAME:AddMessage(
                                string.format("|cffff6600[Tracking]|r %s (ID:%d) expired %.1fs ago",
                                    args.name, spellID, expiredTime)
                            )
                        end
                        -- Remove expired debuff to prevent repeated "expired" messages
                        if lib.objects[guid] then
                            lib.objects[guid][spellID] = nil
                        end
                    end
                end
            end

            -- Only show "not in tracking" message if CleveRoids.debugVerbose is enabled
            -- (too spammy for normal debug mode)
            if not found and CleveRoids.debugVerbose then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff0000[Tracking]|r %s not in tracking table (checked %d ranks)",
                        args.name, table.getn(matchingSpellIDs))
                )
            end
        elseif CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff0000[Tracking]|r Unknown spell: %s", args.name)
            )
        end

        -- FALLBACK: If not found in tracking table (e.g., shared debuff from another player),
        -- scan actual debuffs on target using UnitDebuff()
        -- IMPORTANT: Skip this fallback for personal debuffs - they should only match if player cast them
        local isPersonalDebuff = false
        if table.getn(matchingSpellIDs) > 0 then
            for _, spellID in ipairs(matchingSpellIDs) do
                if CleveRoids.libdebuff:IsPersonalDebuff(spellID) then
                    isPersonalDebuff = true
                    break
                end
            end
        end

        if not found and not isPersonalDebuff and CleveRoids.hasSuperwow then
            -- Scan debuff slots
            for i = 1, 16 do
                local tex, debuffStacks, _, debuffSpellID = UnitDebuff(unit, i)
                if not tex then break end

                if debuffSpellID then
                    -- PERFORMANCE: Use cached spell name lookup
                    local baseName, fullName = GetSpellNames(debuffSpellID)
                    if baseName and (baseName == args.name or fullName == args.name) then
                        found = true
                        texture = tex
                        stacks = debuffStacks or 0
                        spellID = debuffSpellID
                        -- No duration tracking for shared debuffs
                        remaining = nil
                        break
                    end
                end
            end

            -- If still not found, check buff slots (overflow debuffs)
            if not found then
                for i = 1, 32 do
                    local tex, buffStacks, buffSpellID = UnitBuff(unit, i)
                    if not tex then break end

                    if buffSpellID then
                        -- PERFORMANCE: Use cached spell name lookup
                        local baseName, fullName = GetSpellNames(buffSpellID)
                        if baseName and (baseName == args.name or fullName == args.name) then
                            found = true
                            texture = tex
                            stacks = buffStacks or 0
                            spellID = buffSpellID
                            remaining = nil
                            break
                        end
                    end
                end
            end
        end
    -- For player unit, use standard search (player only sees own debuffs on self)
    elseif unit == "player" then
        -- Search DEBUFFS first
        i = 0
        while true do
            texture, stacks, spellID, remaining = CleveRoids.GetPlayerAura(i, false)
            if not texture then break end

            if CleveRoids.hasSuperwow then
                -- PERFORMANCE: Use cached spell name lookup
                local baseName, fullName = GetSpellNames(spellID)
                if baseName and (baseName == args.name or fullName == args.name) then
                    found = true
                    break
                end
            elseif texture == CleveRoids.auraTextures[args.name] then
                found = true
                break
            end
            i = i + 1
        end

        -- If not found, search BUFFS (overflow debuffs shown as buffs on some servers)
        if not found then
            i = 0
            while true do
                texture, stacks, spellID, remaining = CleveRoids.GetPlayerAura(i, true)
                if not texture then break end

                if CleveRoids.hasSuperwow then
                    -- PERFORMANCE: Use cached spell name lookup
                    local baseName, fullName = GetSpellNames(spellID)
                    if baseName and (baseName == args.name or fullName == args.name) then
                        found = true
                        break
                    end
                elseif texture == CleveRoids.auraTextures[args.name] then
                    found = true
                    break
                end
                i = i + 1
            end
        end
    end

    -- Step 3: Perform conditional validation
    local ops = CleveRoids.operators
    local cmp = CleveRoids.comparators

    -- Handle multi-comparison (e.g., >0&<10)
    if args.comparisons and type(args.comparisons) == "table" then
        if not found then
            return false  -- Debuff doesn't exist, so all comparisons fail
        end

        -- ALL comparisons must pass (AND logic)
        for _, comp in ipairs(args.comparisons) do
            if not ops[comp.operator] then
                return false  -- Invalid operator
            end

            local value_to_check
            if comp.checkStacks then
                value_to_check = stacks or 0
            elseif unit == "player" then
                value_to_check = remaining or 0
            else
                -- Non-player units don't have remaining time, only check existence
                return found
            end

            if not cmp[comp.operator](value_to_check, comp.amount) then
                return false  -- One comparison failed
            end
        end
        return true  -- All comparisons passed
    end

    local hasNumCheck = (args.amount ~= nil) and (args.operator ~= nil) and ops[args.operator]

    -- Case A: No numeric/stack condition, just check for existence.
    if not hasNumCheck and not args.checkStacks then
        return found
    end

    -- Case B: Numeric/stack condition exists.
    if hasNumCheck then
        -- Stacks compare path
        if args.checkStacks then
            if found then
                return cmp[args.operator](stacks or 0, args.amount)
            else
                return cmp[args.operator](0, args.amount)
            end
        end

        -- Time-left compare path
        if unit == "player" then
            if not found then
                return false  -- debuff doesn't exist, fail the check
            end
            local tl = remaining or 0
            return cmp[args.operator](tl, args.amount)
        else
            -- Non-player: try pfUI → internal libdebuff → 0s
            local tl = _get_debuff_timeleft(unit, args.name)
            if tl ~= nil then
                return cmp[args.operator](tl or 0, args.amount)
            end

            -- Defensive: verify libdebuff is a table before accessing properties
            if type(CleveRoids.libdebuff) == "table" and CleveRoids.libdebuff.UnitDebuff then
                local atl = nil
                local caster = nil

                -- Auto-detect if this is a personal debuff (unless explicitly overridden)
                local filterCaster = nil
                if args.mine == true then
                    -- User explicitly requested player-only filtering
                    filterCaster = "player"
                elseif args.mine == false then
                    -- User explicitly requested no filtering
                    filterCaster = nil
                else
                    -- Auto-detect based on spell type (if available and personal, filter to player)
                    -- We'll determine this during the search
                    filterCaster = nil
                end

                -- Check 1-48: debuff slots 1-16 + overflow debuffs in buff slots 1-32
                for idx = 1, 48 do
                    local effect, _, _, _, _, duration, timeleft, effectCaster = CleveRoids.libdebuff:UnitDebuff(unit, idx, filterCaster)
                    -- Only break for slots 1-16 (regular debuffs are dense)
                    -- For overflow slots 17-48, nil means "regular buff filtered out", not "end of list"
                    if not effect and idx <= 16 then break end
                    if effect and effect == args.name then
                        local shouldSkip = false

                        -- Auto-detect: If args.mine not specified and this is a personal debuff, only match player casts
                        if args.mine == nil and spellID and CleveRoids.libdebuff.IsPersonalDebuff then
                            if CleveRoids.libdebuff:IsPersonalDebuff(spellID) and effectCaster ~= "player" then
                                -- This is a personal debuff from another player, skip it
                                shouldSkip = true
                            end
                        end

                        if not shouldSkip then
                            atl = (timeleft and timeleft >= 0) and timeleft or 0
                            caster = effectCaster
                            break
                        end
                    end
                end
                if atl ~= nil then
                    return cmp[args.operator](atl, args.amount)
                end
            end

           -- No timers at all: treat missing/unknown as 0s and compare
            if not found then
                -- If debuff doesn't exist, treat as 0 seconds and compare
                return cmp[args.operator](0, args.amount)
            end
            -- If we reach here with no timer data, treat as 0
            return cmp[args.operator](0, args.amount)
        end
    end

    -- If we get here, nothing matched
    return false
end

function CleveRoids.ValidatePlayerBuff(args)
    -- First check regular buffs
    local found = CleveRoids.ValidateAura("player", args, true)
    if found then return true end

    -- Also check shapeshift forms (Cat Form, Bear Form, etc. are not regular buffs)
    -- This is needed for !Cat Form syntax to work correctly
    local searchName = type(args) == "table" and args.name or args
    if searchName then
        -- PERFORMANCE: Use cached lowercase normalization to avoid per-call string allocation
        searchName = GetLowerNormalizedName(searchName)
        local numForms = GetNumShapeshiftForms()
        for i = 1, numForms do
            local icon, name, isActive, isCastable = GetShapeshiftFormInfo(i)
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "|cff00ff00[ValidatePlayerBuff]|r Form %d: name=%s, isActive=%s, searching=%s",
                    i, tostring(name), tostring(isActive), searchName))
            end
            -- PERFORMANCE: Use cached lowercase to avoid per-iteration string allocation
            if name and isActive and GetLowercaseString(name) == searchName then
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[ValidatePlayerBuff]|r MATCH FOUND - returning true")
                end
                return true
            end
        end
    end

    return false
end

function CleveRoids.ValidatePlayerDebuff(args)
    return CleveRoids.ValidateAura("player", args, false)
end

function CleveRoids.ValidateWeaponImbue(slot, imbueName)
    -- Check if weapon has enchant via API
    local hasMainEnchant, mainExpiration, mainCharges, hasOffEnchant, offExpiration, offCharges = GetWeaponEnchantInfo()
    
    local hasEnchant, expiration, charges
    if slot == "mh" then
        hasEnchant = hasMainEnchant
        expiration = mainExpiration
        charges = mainCharges
    else
        hasEnchant = hasOffEnchant
        expiration = offExpiration
        charges = offCharges
    end
    
    -- Only consider temporary enchants (with time or charges)
    -- This filters out permanent enchants like Crusader, Lifestealing, etc.
    local hasTemporaryEnchant = hasEnchant and (expiration and expiration > 0 or charges and charges > 0)

    -- If no specific imbue requested, return temporary enchant status
    if not imbueName or imbueName == "" then 
        return hasTemporaryEnchant
    end
    
    -- If no temporary enchant, don't bother scanning
    if not hasTemporaryEnchant then
        return false
    end

    -- For specific imbue names, scan tooltip to match the name
    -- BUT only check lines that have time markers (temporary enchants)
    -- This prevents matching weapon stats like "Equip: ... critical strike ..."
    
    -- Create tooltip scanner if needed
    if not CleveRoidsTooltip then
        CreateFrame("GameTooltip", "CleveRoidsTooltip", nil, "GameTooltipTemplate")
    end

    -- Scan weapon tooltip
    CleveRoidsTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    CleveRoidsTooltip:ClearLines()
    CleveRoidsTooltip:SetInventoryItem("player", slot == "mh" and 16 or 17)

    -- PERFORMANCE: Use cached normalization to avoid per-call string allocation
    local searchTerm = GetLowerNormalizedName(imbueName)

    -- Look for green text with time markers - check ALL green lines with time
    for i = 1, CleveRoidsTooltip:NumLines() do
        local text = _G["CleveRoidsTooltipTextLeft"..i]
        if text then
            local line = text:GetText()
            if line then
                local r, g, b = text:GetTextColor()
                -- Green text indicates enchant
                if g > 0.8 and r < 0.2 and b < 0.2 then
                    local lowerLine = string.lower(line)
                    -- Only check lines with time markers (temporary enchants)
                    -- This skips permanent weapon stats like "Equip: ... critical strike ..."
                    if string.find(lowerLine, "%(") and (string.find(lowerLine, " min%)") or string.find(lowerLine, " sec%)") or string.find(lowerLine, " charge")) then
                        -- This is a temporary enchant line, check if it matches
                        if string.find(lowerLine, searchTerm, 1, true) then
                            return true  -- Found it!
                        end
                    end
                end
            end
        end
    end

    -- Checked all lines, didn't find it
    return false
end

-- TODO: Look into https://github.com/Stanzilla/WoWUIBugs/issues/47 if needed
-- PERFORMANCE: Uncached version - called by GetCachedCooldown
function CleveRoids._GetCooldownUncached(name, ignoreGCD)
    if not name then return 0 end

    -- Check if it's a spell first
    local spell = CleveRoids.GetSpell(name)
    if spell then
        local expires = CleveRoids.GetSpellCooldown(name, ignoreGCD)
        return expires  -- GetSpellCooldown already returns absolute time
    end

    -- Not a spell, check if it's an item
    -- GetItemCooldown returns (remainingSeconds, totalDuration, enabled)
    local remaining, duration, enabled = CleveRoids.GetItemCooldown(name, ignoreGCD)

    -- Convert remaining seconds to absolute expiry time
    if remaining and remaining > 0 then
        return CleveRoids.GetCachedTime() + remaining
    end

    return 0
end

-- PERFORMANCE: Cached wrapper - use this for conditional checks
function CleveRoids.GetCooldown(name, ignoreGCD)
    return CleveRoids.GetCachedCooldown(name, ignoreGCD)
end

-- TODO: Look into https://github.com/Stanzilla/WoWUIBugs/issues/47 if needed
-- Returns the cooldown of the given spellName or nil if no such spell was found
function CleveRoids.GetSpellCooldown(spellName, ignoreGCD)
    if not spellName then return 0 end

    local spell = CleveRoids.GetSpell(spellName)
    if not spell then return 0 end

    local start, cd = GetSpellCooldown(spell.spellSlot, spell.bookType)
    if ignoreGCD and cd and cd > 0 and cd <= 1.5 then
        return 0
    else
        return (start + cd)
    end
end

-- Check if an item exists in bags or equipped
-- Returns: true if found, false otherwise
-- PERFORMANCE: Uses CleveRoids.Items cache for O(1) lookup, with fallback for substring matches
function CleveRoids.HasItem(item)
  -- Fast path: check cache first (O(1) lookup)
  if CleveRoids.HasItemCached(item) then
    return true
  end

  -- Slow path fallback: only needed for substring matching on strings
  -- The cache handles exact matches by ID and name, but not partial/substring matches
  if type(item) == "string" and item ~= "" then
    local itemLower = string.lower(item)

    -- Check equipped slots for substring match
    for slot = 0, 19 do
      local link = GetInventoryItemLink("player", slot)
      if link then
        if string.find(string.lower(link), itemLower, 1, true) then
          return true
        end
      end
    end

    -- Check bags for substring match
    for bag = 0, 4 do
      local size = GetContainerNumSlots(bag)
      if size and size > 0 then
        for slotIndex = 1, size do
          local link = GetContainerItemLink(bag, slotIndex)
          if link then
            if string.find(string.lower(link), itemLower, 1, true) then
              return true
            end
          end
        end
      end
    end
  end

  return false
end

-- TODO: Look into https://github.com/Stanzilla/WoWUIBugs/issues/47 if needed
-- Hardened item cooldown resolver (Vanilla 1.12.1 / Lua 5.0)
-- Returns: remainingSeconds, totalDuration, enabled
-- PERFORMANCE: Uses CleveRoids.Items cache for O(1) lookup, with fallback for substring matches
function CleveRoids.GetItemCooldown(item)
  -- Helper to normalize cooldown values
  local function _norm(s, d, e)
    s = tonumber(s) or 0
    d = tonumber(d) or 0
    e = tonumber(e) or 0
    if d <= 0 or s <= 0 then
      return 0, 0, e
    end
    local rem = (s + d) - GetTime()
    if rem < 0 then rem = 0 end
    return rem, d, e
  end

  -- Fast path: check cache first (O(1) lookup)
  local remaining, duration, enable = CleveRoids.GetItemCooldownCached(item)
  if duration > 0 or remaining > 0 then
    return remaining, duration, enable
  end

  -- If cache found the item but cooldown is 0, that's a valid result
  local location = CleveRoids.FindItemLocation(item)
  if location then
    return 0, 0, enable or 0
  end

  -- Slow path fallback: only needed for substring matching on strings
  if type(item) == "string" and item ~= "" then
    local itemLower = string.lower(item)
    local start, dur, en

    -- Check equipped slots for substring match
    for slot = 0, 19 do
      local link = GetInventoryItemLink("player", slot)
      if link then
        if string.find(string.lower(link), itemLower, 1, true) then
          start, dur, en = GetInventoryItemCooldown("player", slot)
          return _norm(start, dur, en)
        end
      end
    end

    -- Check bags for substring match
    for bag = 0, 4 do
      local size = GetContainerNumSlots(bag)
      if size and size > 0 then
        for slotIndex = 1, size do
          local link = GetContainerItemLink(bag, slotIndex)
          if link then
            if string.find(string.lower(link), itemLower, 1, true) then
              start, dur, en = GetContainerItemCooldown(bag, slotIndex)
              return _norm(start, dur, en)
            end
          end
        end
      end
    end
  end

  -- Fallback: unknown item → no cooldown
  return 0, 0, 0
end

function CleveRoids.ValidatePlayerAuraCount(bigger, amount)
    local aura_ix = -1
    local num = 0
    while true do
        aura_ix = GetPlayerBuff(num,"HELPFUL|PASSIVE")
        if aura_ix == -1 then break end
        num = num + 1
    end
    if bigger == 0 then
        return num < tonumber(amount)
    else
        return num > tonumber(amount)
    end
end

function CleveRoids.IsReactive(name)
    return CleveRoids.reactiveSpells[spellName] ~= nil
end

function CleveRoids.GetActionButtonInfo(slot)
    local macroName, actionType, id = GetActionText(slot)
    if actionType == "MACRO" then
        return actionType, id, macroName
    elseif actionType == "SPELL" and id then
        local spellName, rank = SpellInfo(id)
        return actionType, id, spellName, rank
    elseif actionType == "ITEM" and id then
        local item = CleveRoids.GetItem(id)
        return actionType, id, (item and item.name), (item and item.id)
    end
end

function CleveRoids.IsReactiveUsable(spellName)
    -- For Overpower, Revenge, and Riposte: ONLY use combat log tracking
    -- These spells have specific proc conditions tracked via combat log
    if spellName == "Overpower" or spellName == "Revenge" or spellName == "Riposte" then
        if CleveRoids.HasReactiveProc and CleveRoids.HasReactiveProc(spellName) then
            return 1
        else
            return nil
        end
    end

    -- For other reactive spells, use fallback methods
    -- Use Nampower's IsSpellUsable if available (more accurate)
    if IsSpellUsable then
        -- pcall to handle spells not in spellbook (Nampower throws error)
        local ok, usable, oom = pcall(IsSpellUsable, spellName)
        if ok then
            if usable == 1 and oom ~= 1 then
                return 1
            else
                return nil, oom
            end
        end
        -- If pcall failed, spell not in spellbook - fall through to action bar check
    end

    -- Fallback to action bar slot checking (requires correct stance)
    if not CleveRoids.reactiveSlots[spellName] then return false end
    local actionSlot = CleveRoids.reactiveSlots[spellName]
    local isUsable, oom = CleveRoids.Hooks.OriginalIsUsableAction(actionSlot)
    local start, duration = GetActionCooldown(actionSlot)
    if isUsable and (start == 0 or duration == 1.5) then -- 1.5 just means gcd is active
        return 1
    else
        return nil, oom
    end
end

-- Check if any spell is usable (not just reactive)
function CleveRoids.CheckSpellUsable(spellName)
    if not spellName then return false end

    -- Use Nampower's IsSpellUsable if available
    if IsSpellUsable then
        -- pcall to handle spells not in spellbook (Nampower throws error)
        local ok, usable, oom = pcall(IsSpellUsable, spellName)
        if ok then
            return (usable == 1 and oom ~= 1)
        end
        -- If pcall failed, spell not in spellbook - fall through to fallback
    end

    -- Fallback: check if spell exists and player has mana/rage/energy
    local spell = CleveRoids.GetSpell(spellName)
    if not spell then return false end

    -- Check mana cost
    local currentPower = UnitMana("player")
    if spell.cost and currentPower < spell.cost then
        return false
    end

    -- Check cooldown (ignore GCD)
    local start, duration = GetSpellCooldown(spell.spellSlot, spell.bookType)
    if start > 0 and duration > 1.5 then
        return false
    end

    return true
end

function CleveRoids.CheckSpellCast(unit, spell)
    local spell = spell or ""
    local _,guid = UnitExists(unit)
    if not guid then return false end

    -- BUGFIX: Special handling for player unit - check CurrentSpell.type
    -- This is event-driven and more reliable than spell_tracking for the player
    if unit == "player" then
        -- Check if player is casting or channeling
        if CleveRoids.CurrentSpell and CleveRoids.CurrentSpell.type ~= "" then
            -- If checking for any spell, return true
            if spell == "" then
                return true
            end
            -- If checking for specific spell, compare spell names
            -- Note: CurrentSpell.spellName may not be set, so also check spell_tracking as fallback
            if CleveRoids.CurrentSpell.spellName and CleveRoids.CurrentSpell.spellName == spell then
                return true
            end
        end
        -- Fallback to spell_tracking for player if CurrentSpell doesn't have the info
    end

    -- For non-player units or as fallback, use spell_tracking
    if not CleveRoids.hasSuperwow then return false end

    if not CleveRoids.spell_tracking[guid] then
        return false
    else
        -- are we casting a specific spell, or any spell
        if spell == SpellInfo(CleveRoids.spell_tracking[guid].spell_id) or (spell == "") then
            return true
        end
        return false
    end
end

-- ============================================================================
-- CC (Crowd Control) Mechanic Detection
-- Uses BuffLib if available, otherwise uses built-in spell database
-- ============================================================================

-- Maps CC type names to mechanic constants (matches DBC mechanic IDs)
-- Note: Some types map to multiple mechanics via CCMechanicGroups below
CleveRoids.CCMechanics = {
    -- Movement/control impairment
    charm       = 1,   -- Mind Control, Seduction
    disoriented = 2,   -- Scatter Shot, Blind (disorient component)
    disorient   = 2,   -- Alias for disoriented
    disarm      = 3,   -- Disarm, Riposte disarm
    distract    = 4,   -- Distract (Rogue ability)
    fear        = 5,   -- Fear, Psychic Scream, Howl of Terror
    grip        = 6,   -- Grip effects
    root        = 7,   -- Entangling Roots, Frost Nova, Improved Hamstring
    pacify      = 8,   -- Pacify effects
    silence     = 9,   -- Silence, Kick, Counterspell (lockout)
    sleep       = 10,  -- Hibernate, Wyvern Sting sleep
    snare       = 11,  -- Hamstring, Wing Clip, Crippling Poison
    slow        = 11,  -- Alias for snare
    stun        = 12,  -- Consolidated: Stun(12) + Knockout(14) + Sap(30)
    freeze      = 13,  -- Freeze effects (Frost Nova freeze)
    bleed       = 15,  -- Rend, Garrote, Deep Wounds
    polymorph   = 17,  -- Polymorph (all variants)
    banish      = 18,  -- Banish (Warlock)
    shackle     = 20,  -- Shackle Undead
    horror      = 24,  -- Death Coil (Warlock), Intimidating Shout (horror)
    daze        = 27,  -- Dazed effects
}

-- Mechanic groups: CC types that check multiple DBC mechanics
-- Used when a single conditional should match several related effects
CleveRoids.CCMechanicGroups = {
    stun = {12, 14, 30},  -- Stun(12), Knockout/Gouge(14), Sap(30)
}

-- CC types that count as "crowd controlled" (loss of control)
-- Note: Mechanics 12, 14, 30 are all consolidated under "stun" for conditionals
CleveRoids.CCTypesLossOfControl = {
    [1] = true,   -- charm
    [2] = true,   -- disoriented
    [5] = true,   -- fear
    [10] = true,  -- sleep
    [12] = true,  -- stun (Cheap Shot, Kidney Shot, etc.)
    [13] = true,  -- freeze
    [14] = true,  -- knockout/gouge (now part of stun group)
    [17] = true,  -- polymorph
    [18] = true,  -- banish
    [20] = true,  -- shackle
    [24] = true,  -- horror
    [30] = true,  -- sap (now part of stun group)
}

-- Complete spell ID to mechanic mapping from DBC data
-- Extracted from BuffLib SpellData - 785 spells with mechanics
-- Mechanic IDs: 1=Charm, 2=Disorient, 3=Disarm, 5=Fear, 7=Root, 9=Silence,
--               10=Sleep, 11=Snare, 12=Stun, 13=Freeze, 14=Knockout,
--               15=Bleed, 17=Polymorph, 18=Banish, 20=Shackle, 21=Mount,
--               23=Turn, 24=Horror, 25=Invuln, 27=Daze
CleveRoids.CCSpellMechanics = {
    [17] = 19, [56] = 12, [89] = 11, [113] = 7, [118] = 17, [228] = 17,
    [246] = 11, [339] = 7, [408] = 12, [451] = 9, [458] = 21, [459] = 21,
    [468] = 21, [470] = 21, [471] = 21, [472] = 21, [474] = 6, [498] = 25,
    [507] = 6, [512] = 7, [578] = 21, [579] = 21, [580] = 21, [581] = 21,
    [592] = 19, [593] = 6, [600] = 19, [605] = 1, [642] = 25, [676] = 3,
    [700] = 10, [703] = 15, [710] = 18, [745] = 7, [746] = 16, [771] = 1,
    [772] = 15, [835] = 12, [851] = 17, [853] = 12, [861] = 9, [867] = 6,
    [998] = 6, [1020] = 25, [1022] = 25, [1062] = 7, [1079] = 15, [1090] = 10,
    [1098] = 1, [1159] = 16, [1513] = 5, [1776] = 14, [1777] = 14, [1833] = 12,
    [1943] = 15, [2070] = 14, [2094] = 2, [2637] = 10, [2878] = 23, [2880] = 12,
    [2937] = 10, [3109] = 5, [3143] = 12, [3147] = 15, [3242] = 12, [3263] = 12,
    [3267] = 16, [3268] = 16, [3355] = 13, [3363] = 21, [3409] = 11, [3410] = 11,
    [3446] = 12, [3542] = 7, [3551] = 12, [3589] = 9, [3600] = 11, [3604] = 11,
    [3609] = 12, [3635] = 12, [3636] = 10, [3747] = 19, [4060] = 17, [4064] = 12,
    [4065] = 12, [4066] = 12, [4067] = 12, [4068] = 12, [4069] = 12, [4102] = 15,
    [4244] = 15, [4962] = 7, [5106] = 12, [5116] = 11, [5134] = 5, [5159] = 11,
    [5164] = 12, [5195] = 7, [5196] = 7, [5211] = 12, [5246] = 5, [5259] = 3,
    [5276] = 12, [5376] = 4, [5403] = 12, [5484] = 5, [5530] = 12, [5531] = 12,
    [5567] = 7, [5573] = 25, [5588] = 12, [5589] = 12, [5597] = 15, [5598] = 15,
    [5599] = 25, [5627] = 23, [5648] = 12, [5649] = 12, [5703] = 12, [5708] = 12,
    [5782] = 5, [5784] = 21, [5917] = 6, [5918] = 12, [6065] = 19, [6066] = 19,
    [6136] = 11, [6146] = 11, [6213] = 5, [6215] = 5, [6253] = 12, [6266] = 12,
    [6304] = 12, [6358] = 1, [6388] = 11, [6409] = 12, [6435] = 12, [6466] = 12,
    [6524] = 12, [6533] = 7, [6546] = 15, [6547] = 15, [6548] = 15, [6605] = 5,
    [6607] = 12, [6608] = 3, [6648] = 21, [6653] = 21, [6654] = 21, [6713] = 3,
    [6726] = 9, [6728] = 12, [6730] = 12, [6749] = 12, [6770] = 14, [6777] = 21,
    [6788] = 19, [6798] = 12, [6896] = 21, [6897] = 21, [6898] = 21, [6899] = 21,
    [6927] = 12, [6942] = 9, [6945] = 12, [6982] = 12, [6984] = 11, [6985] = 11,
    [7074] = 9, [7093] = 5, [7139] = 12, [7279] = 11, [7321] = 11, [7399] = 5,
    [7645] = 1, [7803] = 12, [7922] = 12, [7926] = 16, [7927] = 16, [7964] = 12,
    [7967] = 10, [7992] = 11, [8040] = 10, [8122] = 5, [8124] = 5, [8142] = 7,
    [8150] = 12, [8208] = 12, [8225] = 5, [8242] = 12, [8281] = 9, [8285] = 12,
    [8312] = 7, [8346] = 7, [8377] = 7, [8379] = 3, [8391] = 12, [8394] = 21,
    [8395] = 21, [8396] = 21, [8399] = 10, [8629] = 14, [8631] = 15, [8632] = 15,
    [8633] = 15, [8639] = 15, [8640] = 15, [8643] = 12, [8646] = 12, [8715] = 5,
    [8716] = 11, [8818] = 15, [8901] = 10, [8902] = 10, [8980] = 21, [8983] = 12,
    [8988] = 9, [8994] = 18, [9005] = 12, [9007] = 15, [9080] = 11, [9159] = 10,
    [9484] = 20, [9485] = 20, [9552] = 9, [9823] = 12, [9824] = 15, [9826] = 15,
    [9827] = 12, [9852] = 7, [9853] = 7, [9896] = 15, [9915] = 7, [10017] = 7,
    [10234] = 10, [10253] = 17, [10266] = 15, [10278] = 25, [10308] = 12,
    [10326] = 23, [10787] = 21, [10788] = 21, [10789] = 21, [10790] = 21,
    [10792] = 21, [10793] = 21, [10795] = 21, [10796] = 21, [10798] = 21,
    [10799] = 21, [10800] = 21, [10801] = 21, [10802] = 21, [10803] = 21,
    [10804] = 21, [10838] = 16, [10839] = 16, [10851] = 3, [10852] = 7,
    [10855] = 11, [10856] = 12, [10873] = 21, [10888] = 5, [10890] = 5,
    [10898] = 19, [10899] = 19, [10900] = 19, [10901] = 19, [10911] = 1,
    [10912] = 1, [10955] = 20, [10969] = 21, [10987] = 11, [11020] = 12,
    [11201] = 11, [11264] = 7, [11273] = 15, [11274] = 15, [11275] = 15,
    [11285] = 14, [11286] = 14, [11289] = 15, [11290] = 15, [11297] = 14,
    [11428] = 12, [11430] = 12, [11436] = 11, [11446] = 1, [11572] = 15,
    [11573] = 15, [11574] = 15, [11578] = 12, [11579] = 12, [11641] = 17, [11650] = 12, [11725] = 1,
    [11726] = 1, [11820] = 7, [11831] = 7, [11836] = 12, [11876] = 12,
    [11879] = 3, [11922] = 7, [11958] = 13, [11977] = 15, [12023] = 7,
    [12024] = 7, [12054] = 15, [12096] = 5, [12098] = 10, [12252] = 7,
    [12323] = 11, [12355] = 12, [12421] = 12, [12461] = 12, [12484] = 11,
    [12485] = 11, [12486] = 11, [12494] = 7, [12528] = 9, [12531] = 11,
    [12540] = 14, [12542] = 5, [12543] = 12, [12551] = 11, [12562] = 12,
    [12674] = 7, [12705] = 11, [12721] = 15, [12730] = 5, [12734] = 12,
    [12747] = 7, [12748] = 7, [12798] = 12, [12809] = 12, [12824] = 17,
    [12825] = 17, [12826] = 17, [12946] = 9, [13005] = 12, [13099] = 7,
    [13119] = 7, [13138] = 7, [13181] = 1, [13237] = 12, [13318] = 15,
    [13323] = 17, [13327] = 14, [13443] = 15, [13445] = 15, [13534] = 3,
    [13579] = 14, [13608] = 7, [13704] = 5, [13738] = 15, [13747] = 11,
    [13808] = 12, [13810] = 11, [13819] = 21, [13902] = 12, [14030] = 7,
    [14087] = 15, [14100] = 5, [14102] = 12, [14118] = 15, [14180] = 3,
    [14207] = 11, [14308] = 13, [14309] = 13, [14326] = 5, [14327] = 5,
    [14331] = 15, [14515] = 1, [14621] = 17, [14874] = 15, [14897] = 11,
    [14902] = 12, [14903] = 15, [14907] = 7, [15063] = 7, [15091] = 14,
    [15269] = 12, [15283] = 12, [15398] = 12, [15471] = 7, [15474] = 7,
    [15487] = 9, [15531] = 7, [15532] = 7, [15534] = 17, [15535] = 12,
    [15583] = 15, [15593] = 12, [15609] = 7, [15618] = 12, [15621] = 12,
    [15652] = 12, [15655] = 12, [15744] = 14, [15752] = 3, [15753] = 12,
    [15779] = 21, [15780] = 21, [15781] = 21, [15822] = 10, [15859] = 1,
    [15878] = 12, [15970] = 10, [15976] = 15, [16045] = 18, [16046] = 14,
    [16050] = 11, [16053] = 1, [16055] = 21, [16056] = 21, [16058] = 21,
    [16059] = 21, [16060] = 21, [16075] = 12, [16080] = 21, [16081] = 21,
    [16082] = 21, [16083] = 21, [16084] = 21, [16095] = 15, [16096] = 5,
    [16097] = 17, [16104] = 12, [16350] = 12, [16393] = 15, [16403] = 15,
    [16406] = 15, [16451] = 18, [16469] = 7, [16497] = 12, [16508] = 5,
    [16509] = 15, [16566] = 7, [16568] = 11, [16600] = 12, [16707] = 17,
    [16708] = 17, [16709] = 17, [16727] = 12, [16790] = 12, [16798] = 10,
    [16803] = 12, [16838] = 9, [16869] = 12, [16922] = 12, [17011] = 12,
    [17145] = 14, [17153] = 15, [17165] = 11, [17172] = 17, [17174] = 11,
    [17229] = 21, [17276] = 12, [17277] = 14, [17286] = 12, [17293] = 12,
    [17308] = 12, [17405] = 1, [17450] = 21, [17453] = 21, [17454] = 21,
    [17455] = 21, [17456] = 21, [17458] = 21, [17459] = 21, [17460] = 21,
    [17461] = 21, [17462] = 21, [17463] = 21, [17464] = 21, [17465] = 21,
    [17481] = 21, [17500] = 12, [17504] = 15, [17738] = 17, [17928] = 5,
    [18075] = 15, [18078] = 15, [18093] = 12, [18103] = 12, [18106] = 15,
    [18118] = 11, [18144] = 12, [18200] = 15, [18202] = 15, [18223] = 11,
    [18278] = 9, [18327] = 9, [18328] = 11, [18363] = 21, [18395] = 12,
    [18425] = 9, [18431] = 5, [18469] = 9, [18498] = 9, [18503] = 17,
    [18608] = 16, [18610] = 16, [18647] = 18, [18657] = 10, [18658] = 10,
    [18763] = 12, [18802] = 11, [18812] = 12, [18972] = 11, [18989] = 21,
    [18990] = 21, [18991] = 21, [18992] = 21, [19128] = 12, [19134] = 5,
    [19136] = 12, [19137] = 11, [19185] = 7, [19229] = 7, [19364] = 12,
    [19386] = 10, [19393] = 9, [19408] = 5, [19410] = 12, [19469] = 1,
    [19482] = 12, [19496] = 11, [19501] = 2, [19503] = 2, [19641] = 12,
    [19718] = 3, [19769] = 12, [19771] = 15, [19780] = 12, [19784] = 12,
    [19821] = 9, [19970] = 7, [19971] = 7, [19972] = 7, [19973] = 7,
    [19974] = 7, [19975] = 7, [20066] = 14, [20170] = 12, [20253] = 12,
    [20276] = 12, [20277] = 12, [20310] = 12, [20511] = 5, [20549] = 12,
    [20604] = 1, [20614] = 12, [20615] = 12, [20654] = 7, [20663] = 10,
    [20669] = 10, [20683] = 12, [20685] = 12, [20699] = 7, [20706] = 19,
    [20740] = 1, [20882] = 1, [20907] = 15, [20908] = 15, [20989] = 10,
    [21099] = 12, [21152] = 12, [21330] = 5, [21331] = 7, [21748] = 12,
    [21749] = 12, [21869] = 5, [21898] = 5, [21949] = 15, [21990] = 12,
    [22127] = 7, [22274] = 17, [22289] = 12, [22356] = 11, [22415] = 7,
    [22419] = 3, [22424] = 14, [22427] = 12, [22519] = 7, [22566] = 17,
    [22570] = 14, [22592] = 12, [22639] = 11, [22645] = 7, [22666] = 9,
    [22678] = 5, [22686] = 5, [22691] = 3, [22692] = 12, [22717] = 21,
    [22718] = 21, [22719] = 21, [22720] = 21, [22721] = 21, [22722] = 21,
    [22723] = 21, [22724] = 21, [22744] = 7, [22752] = 19, [22800] = 7,
    [22884] = 5, [22914] = 11, [22915] = 12, [22919] = 11, [22924] = 7,
    [22994] = 7, [23039] = 14, [23103] = 12, [23113] = 14, [23161] = 21,
    [23207] = 9, [23214] = 21, [23219] = 21, [23220] = 21, [23221] = 21,
    [23222] = 21, [23223] = 21, [23225] = 21, [23227] = 21, [23228] = 21,
    [23229] = 21, [23238] = 21, [23239] = 21, [23240] = 21, [23241] = 21,
    [23242] = 21, [23243] = 21, [23246] = 21, [23247] = 21, [23248] = 21,
    [23249] = 21, [23250] = 21, [23251] = 21, [23252] = 21, [23275] = 5,
    [23338] = 21, [23364] = 12, [23365] = 3, [23454] = 12, [23509] = 21,
    [23510] = 21, [23567] = 16, [23568] = 16, [23569] = 16, [23600] = 11,
    [23603] = 17, [23618] = 12, [23694] = 7, [23696] = 16, [23918] = 9,
    [23919] = 12, [23953] = 11, [24004] = 10, [24053] = 17, [24110] = 7,
    [24118] = 15, [24119] = 15, [24120] = 15, [24132] = 10, [24133] = 10,
    [24152] = 7, [24192] = 15, [24213] = 12, [24225] = 11, [24242] = 21,
    [24252] = 21, [24259] = 9, [24327] = 1, [24331] = 15, [24332] = 15,
    [24333] = 12, [24335] = 10, [24360] = 10, [24375] = 12, [24394] = 12,
    [24412] = 16, [24413] = 16, [24414] = 16, [24415] = 11, [24576] = 21,
    [24600] = 12, [24648] = 7, [24664] = 10, [24671] = 12, [24687] = 9,
    [24698] = 14, [24712] = 17, [24713] = 17, [24735] = 17, [24736] = 17,
    [24778] = 10, [25022] = 11, [25049] = 14, [25056] = 12, [25057] = 3,
    [25187] = 11, [25189] = 12, [25260] = 5, [25654] = 12, [25655] = 3,
    [25675] = 21, [25771] = 25, [25809] = 11, [25815] = 5, [25852] = 12,
    [25858] = 21, [25859] = 21, [25863] = 21, [25953] = 21, [25999] = 7,
    [26042] = 5, [26054] = 21, [26055] = 21, [26056] = 21, [26069] = 9,
    [26070] = 5, [26071] = 7, [26078] = 11, [26108] = 2, [26141] = 11,
    [26143] = 11, [26157] = 17, [26180] = 10, [26211] = 11, [26272] = 17,
    [26273] = 17, [26274] = 17, [26379] = 11, [26580] = 5, [26641] = 5,
    [26655] = 21, [26740] = 1, [27555] = 15, [27556] = 15, [27559] = 9,
    [27565] = 18, [27581] = 3, [27607] = 19, [27610] = 5, [27615] = 12,
    [27619] = 13, [27634] = 11, [27638] = 15, [27640] = 11, [27641] = 5,
    [27758] = 12, [27760] = 17, [27880] = 12, [27990] = 5, [27993] = 11,
    [28270] = 17, [28271] = 17, [28272] = 17, [28314] = 12, [28315] = 5,
    [28445] = 12, [28456] = 14, [28725] = 12, [28858] = 7, [28911] = 15,
    [28913] = 15, [28991] = 7, [29059] = 21, [29168] = 5, [29407] = 11,
    [29419] = 5, [29544] = 5, [29685] = 5, [29848] = 17, [29849] = 7,
    [29915] = 15, [29943] = 9, [30001] = 5, [30002] = 5, [30020] = 16,
    [30094] = 7, [30174] = 21, [30225] = 9, [30285] = 15, [31365] = 5,
    [31700] = 21,
}

-- Check if BuffLib is available with full mechanic support
function CleveRoids.HasBuffLib()
    -- Defensive: ensure BuffLib.SpellData is a table, not a function
    return BuffLib and BuffLib.GetUnitDebuffsByMechanic
        and type(BuffLib.SpellData) == "table"
        and BuffLib.SpellData.GetMechanic
end

-- Get mechanic for a spell ID (uses BuffLib if available, otherwise built-in table)
function CleveRoids.GetSpellMechanic(spellID)
    if not spellID or spellID <= 0 then return 0 end

    -- Try BuffLib first (has complete DBC data)
    -- Defensive: verify SpellData is a table before indexing
    if BuffLib and type(BuffLib.SpellData) == "table" and BuffLib.SpellData.GetMechanic then
        local mechanic = BuffLib.SpellData:GetMechanic(spellID)
        if mechanic and mechanic > 0 then
            return mechanic
        end
    end

    -- Fall back to built-in table
    return CleveRoids.CCSpellMechanics[spellID] or 0
end

-- Validate CC on a unit (target, focus, player, etc.)
-- Returns true if the unit has the specified CC mechanic active
function CleveRoids.ValidateUnitCC(unit, ccType)
    if not unit or not UnitExists(unit) then return false end

    local ccTypeLower = string.lower(ccType or "")

    -- Special case: "cc" means any loss-of-control effect
    if ccTypeLower == "cc" or ccTypeLower == "any" then
        return CleveRoids.ValidateUnitAnyCrowdControl(unit)
    end

    -- Check if this CC type maps to a group of mechanics
    local mechanicGroup = CleveRoids.CCMechanicGroups[ccTypeLower]
    if mechanicGroup then
        -- Check all mechanics in the group (e.g., stun checks 12, 14, 30)
        for _, mechanic in ipairs(mechanicGroup) do
            if CleveRoids.ValidateUnitCCSingleMechanic(unit, mechanic) then
                return true
            end
        end
        return false
    end

    -- Single mechanic lookup
    local mechanic = CleveRoids.CCMechanics[ccTypeLower]
    if not mechanic then return false end

    return CleveRoids.ValidateUnitCCSingleMechanic(unit, mechanic)
end

-- Validate a single CC mechanic on a unit (helper function)
function CleveRoids.ValidateUnitCCSingleMechanic(unit, mechanic)
    -- Use BuffLib if available (most accurate - tracks overflow debuffs and hidden auras)
    if CleveRoids.HasBuffLib() then
        local _, guid = UnitExists(unit)
        if not guid then return false end

        if unit == "player" then
            return BuffLib:HasDebuffOfMechanic(mechanic)
        else
            local debuffs = BuffLib:GetUnitDebuffsByMechanic(guid, mechanic)
            return debuffs and table.getn(debuffs) > 0
        end
    end

    -- Fallback: scan unit debuffs directly
    return CleveRoids.ValidateUnitCCDirect(unit, mechanic)
end

-- Check if unit has any crowd control (loss of control) effect
function CleveRoids.ValidateUnitAnyCrowdControl(unit)
    if not unit or not UnitExists(unit) then return false end

    -- Use BuffLib if available
    if CleveRoids.HasBuffLib() then
        local _, guid = UnitExists(unit)
        if not guid then return false end

        if unit == "player" then
            for mechanic, _ in pairs(CleveRoids.CCTypesLossOfControl) do
                if BuffLib:HasDebuffOfMechanic(mechanic) then
                    return true
                end
            end
        else
            for mechanic, _ in pairs(CleveRoids.CCTypesLossOfControl) do
                local debuffs = BuffLib:GetUnitDebuffsByMechanic(guid, mechanic)
                if debuffs and table.getn(debuffs) > 0 then
                    return true
                end
            end
        end
        return false
    end

    -- Fallback: check all loss-of-control mechanics directly
    for mechanic, _ in pairs(CleveRoids.CCTypesLossOfControl) do
        if CleveRoids.ValidateUnitCCDirect(unit, mechanic) then
            return true
        end
    end
    return false
end

-- Direct CC check - scans unit debuffs using SuperWoW API
-- Works without BuffLib by using built-in spell mechanic table
function CleveRoids.ValidateUnitCCDirect(unit, mechanic)
    if not CleveRoids.hasSuperwow then return false end

    -- Players only have 16 debuff slots, no overflow
    -- Non-player units can have overflow debuffs in buff slots (17-48)
    local isPlayer = (unit == "player")
    local maxDebuffSlots = 16
    local maxOverflowSlots = isPlayer and 0 or 32

    -- Scan regular debuff slots (1-16)
    for i = 1, maxDebuffSlots do
        local texture, stacks, debuffType, spellID = UnitDebuff(unit, i)
        if not texture then break end

        if spellID and spellID > 0 then
            local spellMechanic = CleveRoids.GetSpellMechanic(spellID)
            if spellMechanic == mechanic then
                return true
            end
        end
    end

    -- Scan overflow slots in buff bar (non-player units only)
    if maxOverflowSlots > 0 then
        for i = 1, maxOverflowSlots do
            local texture, stacks, spellID = UnitBuff(unit, i)
            if not texture then break end

            if spellID and spellID > 0 then
                local spellMechanic = CleveRoids.GetSpellMechanic(spellID)
                if spellMechanic == mechanic then
                    return true
                end
            end
        end
    end

    return false
end

-- A list of Conditionals and their functions to validate them
CleveRoids.Keywords = {
    exists = function(conditionals)
        return UnitExists(conditionals.target)
    end,

    noexists = function(conditionals)
        return not UnitExists(conditionals.target)
    end,

    -- Check if player has NO current target (target frame is empty)
    -- Different from noexists: notarget checks player's target, noexists checks @unit
    -- Usage: /target [notarget,@mouseover] - target mouseover only if no current target
    notarget = function(conditionals)
        return not UnitExists("target")
    end,

    -- Check if player HAS a current target (target frame is occupied)
    -- Usage: /cast [hastarget] Spell - only cast if player has a target selected
    hastarget = function(conditionals)
        return UnitExists("target")
    end,

    help = function(conditionals)
        return conditionals.help and conditionals.target and UnitExists(conditionals.target) and UnitCanAssist("player", conditionals.target)
    end,

    harm = function(conditionals)
        return conditionals.harm and conditionals.target and UnitExists(conditionals.target) and UnitCanAttack("player", conditionals.target)
    end,

    stance = function(conditionals)
        local i = CleveRoids.GetCurrentShapeshiftIndex()
        return Or(conditionals.stance, function (v)
            return (i == tonumber(v))
        end)
    end,

    nostance = function(conditionals)
        local i = CleveRoids.GetCurrentShapeshiftIndex()
        local forbiddenStances = conditionals.nostance
        if type(forbiddenStances) ~= "table" then
            return i == 0
        end
        return NegatedMulti(forbiddenStances, function (v)
            return (i ~= tonumber(v))
        end, conditionals, "nostance")
    end,

    noform = function(conditionals)
        local i = CleveRoids.GetCurrentShapeshiftIndex()
        local forbiddenForms = conditionals.noform
        if type(forbiddenForms) ~= "table" then
            return i == 0
        end
        return NegatedMulti(forbiddenForms, function (v)
            return (i ~= tonumber(v))
        end, conditionals, "noform")
    end,

    form = function(conditionals)
        local i = CleveRoids.GetCurrentShapeshiftIndex()
        return Or(conditionals.form, function (v)
            return (i == tonumber(v))
        end)
    end,

    mod = function(conditionals)
        if type(conditionals.mod) ~= "table" then
            return CleveRoids.kmods.mod()
        end
        return Multi(conditionals.mod, function(mod)
            return CleveRoids.kmods[mod]()
        end, conditionals, "mod")
    end,

    nomod = function(conditionals)
        if type(conditionals.nomod) ~= "table" then
            return CleveRoids.kmods.nomod()
        end
        return NegatedMulti(conditionals.nomod, function(mod)
            return not CleveRoids.kmods[mod]()
        end, conditionals, "nomod")
    end,

    target = function(conditionals)
        return CleveRoids.IsValidTarget(conditionals.target, conditionals.help)
    end,

    combat = function(conditionals)
        -- Check if an argument like :target or :focus was provided. The parser turns this into a table.
        if type(conditionals.combat) == "table" then
            -- If so, run the check on the provided unit(s).
            return Multi(conditionals.combat, function(unit)
                return UnitExists(unit) and UnitAffectingCombat(unit)
            end, conditionals, "combat")
        else
            -- Otherwise, this is a bare [combat]. The value might be 'true' or a spell name.
            -- In either case, it should safely default to checking the player.
            return UnitAffectingCombat("player")
        end
    end,

    nocombat = function(conditionals)
        -- Check if an argument like :target or :focus was provided.
        if type(conditionals.nocombat) == "table" then
            -- If so, run the check on the provided unit(s).
            return NegatedMulti(conditionals.nocombat, function(unit)
                if not UnitExists(unit) then
                    return true
                end
                return not UnitAffectingCombat(unit)
            end, conditionals, "nocombat")
        else
            -- Otherwise, this is a bare [nocombat]. Default to checking the player.
            return not UnitAffectingCombat("player")
        end
    end,

    stealth = function(conditionals)
        return (
            (CleveRoids.playerClass == "ROGUE" and CleveRoids.ValidatePlayerBuff(CleveRoids.Localized.Spells["Stealth"]))
            or (CleveRoids.playerClass == "DRUID" and CleveRoids.ValidatePlayerBuff(CleveRoids.Localized.Spells["Prowl"]))
        )
    end,

    nostealth = function(conditionals)
        return (
            (CleveRoids.playerClass == "ROGUE" and not CleveRoids.ValidatePlayerBuff(CleveRoids.Localized.Spells["Stealth"]))
            or (CleveRoids.playerClass == "DRUID" and not CleveRoids.ValidatePlayerBuff(CleveRoids.Localized.Spells["Prowl"]))
        )
    end,

    casting = function(conditionals)
        if type(conditionals.casting) ~= "table" then return CleveRoids.CheckSpellCast(conditionals.target, "") end
        return Or(conditionals.casting, function (spell)
            return CleveRoids.CheckSpellCast(conditionals.target, spell)
        end)
    end,

    nocasting = function(conditionals)
        if type(conditionals.nocasting) ~= "table" then return not CleveRoids.CheckSpellCast(conditionals.target, "") end
        return NegatedMulti(conditionals.nocasting, function (spell)
            return not CleveRoids.CheckSpellCast(conditionals.target, spell)
        end, conditionals, "nocasting")
    end,

    -- NEW: Direct player casting check with time-based prediction
    -- Uses our accurate state tracking instead of GetCurrentCastingInfo polling
    selfcasting = function(conditionals)
        -- Check for cast with time-based prediction
        if CleveRoids.CurrentSpell.type == "cast" and CleveRoids.castStartTime and CleveRoids.castDuration then
            local remaining = CleveRoids.castDuration - (GetTime() - CleveRoids.castStartTime)
            if remaining <= 0.1 then
                return false -- Cast is done
            end
        end

        -- Check for channel with time-based prediction
        if CleveRoids.CurrentSpell.type == "channeled" and CleveRoids.channelStartTime and CleveRoids.channelDuration then
            local remaining = CleveRoids.channelDuration - (GetTime() - CleveRoids.channelStartTime)
            if remaining <= 0.1 then
                return false -- Channel is done
            end
        end

        return CleveRoids.CurrentSpell.type == "cast" or CleveRoids.CurrentSpell.type == "channeled"
    end,

    noselfcasting = function(conditionals)
        -- Inverse of selfcasting with same prediction logic
        if CleveRoids.CurrentSpell.type == "cast" and CleveRoids.castStartTime and CleveRoids.castDuration then
            local remaining = CleveRoids.castDuration - (GetTime() - CleveRoids.castStartTime)
            if remaining <= 0.1 then
                return true -- Cast is done
            end
        end

        if CleveRoids.CurrentSpell.type == "channeled" and CleveRoids.channelStartTime and CleveRoids.channelDuration then
            local remaining = CleveRoids.channelDuration - (GetTime() - CleveRoids.channelStartTime)
            if remaining <= 0.1 then
                return true -- Channel is done
            end
        end

        return CleveRoids.CurrentSpell.type ~= "cast" and CleveRoids.CurrentSpell.type ~= "channeled"
    end,

    zone = function(conditionals)
        local zone = GetRealZoneText()
        local sub_zone = GetSubZoneText()
        return Or(conditionals.zone, function (v)
            return (sub_zone ~= "" and (v == sub_zone) or (v == zone))
        end)
    end,

    nozone = function(conditionals)
        local zone = GetRealZoneText()
        local sub_zone = GetSubZoneText()
        return NegatedMulti(conditionals.nozone, function (v)
            return not ((sub_zone ~= "" and v == sub_zone)) or (v == zone)
        end, conditionals, "nozone")
    end,

    equipped = function(conditionals)
        local itemsToCheck = {}

        -- Case 1: conditionals.equipped is a string (e.g., [equipped]ItemName)
        if type(conditionals.equipped) == "string" then
            table.insert(itemsToCheck, conditionals.equipped)
        -- Case 2: conditionals.equipped is a table (e.g., [equipped:Shields])
        elseif type(conditionals.equipped) == "table" and table.getn(conditionals.equipped) > 0 then
            itemsToCheck = conditionals.equipped
        -- Case 3: No value provided, check the action
        elseif conditionals.action then
            table.insert(itemsToCheck, conditionals.action)
        else
            return false
        end

        -- Check all items
        return Or(itemsToCheck, function(v)
            return (CleveRoids.HasWeaponEquipped(v) or CleveRoids.HasGearEquipped(v))
        end)
    end,

    noequipped = function(conditionals)
        local itemsToCheck = {}

        -- Case 1: conditionals.noequipped is a string (e.g., [noequipped]ItemName)
        if type(conditionals.noequipped) == "string" then
            table.insert(itemsToCheck, conditionals.noequipped)
        -- Case 2: conditionals.noequipped is a table (e.g., [noequipped:Shields])
        elseif type(conditionals.noequipped) == "table" and table.getn(conditionals.noequipped) > 0 then
            itemsToCheck = conditionals.noequipped
        -- Case 3: No value provided, check the action
        elseif conditionals.action then
            table.insert(itemsToCheck, conditionals.action)
        else
            return false
        end

        -- Check all items - ALL must be NOT equipped for this to pass
        return And(itemsToCheck, function(v)
            return not (CleveRoids.HasWeaponEquipped(v) or CleveRoids.HasGearEquipped(v))
        end)
    end,

    dead = function(conditionals)
        if not conditionals.target then return false end
        return UnitIsDeadOrGhost(conditionals.target)
    end,

    alive = function(conditionals)
        if not conditionals.target then return false end
        return not UnitIsDeadOrGhost(conditionals.target)
    end,

    noalive = function(conditionals)
        if not conditionals.target then return false end
        return UnitIsDeadOrGhost(conditionals.target)
    end,

    nodead = function(conditionals)
        if not conditionals.target then return false end
        return not UnitIsDeadOrGhost(conditionals.target)
    end,

    reactive = function(conditionals)
        return Multi(conditionals.reactive, function (v)
            return CleveRoids.IsReactiveUsable(v)
        end, conditionals, "reactive")
    end,

    noreactive = function(conditionals)
        return NegatedMulti(conditionals.noreactive, function (v)
            return not CleveRoids.IsReactiveUsable(v)
        end, conditionals, "noreactive")
    end,

    usable = function(conditionals)
        return Multi(conditionals.usable, function(name)
            -- If checking a reactive spell, use reactive logic
            if CleveRoids.reactiveSpells[name] then
                return CleveRoids.IsReactiveUsable(name)
            end

            -- Check if it's a spell first
            local spell = CleveRoids.GetSpell(name)
            if spell then
                return CleveRoids.CheckSpellUsable(name)
            end

            -- Not a spell - check if it's an item or slot number
            local itemName = name
            local slotNum = tonumber(name)
            if slotNum and slotNum >= 1 and slotNum <= 19 then
                -- Resolve slot number to item name
                local link = GetInventoryItemLink("player", slotNum)
                if link then
                    local _, _, extractedName = string.find(link, "%[(.+)%]")
                    if extractedName then
                        itemName = extractedName
                    end
                end
            end

            -- Check if item exists in bags/equipped first
            if not CleveRoids.HasItem(itemName) then
                return false
            end

            -- Check item cooldown (0 remaining = usable)
            local remaining = CleveRoids.GetItemCooldown(itemName)
            return remaining == 0
        end, conditionals, "usable")
    end,

    nousable = function(conditionals)
        return NegatedMulti(conditionals.nousable, function(name)
            -- If checking a reactive spell, use reactive logic
            if CleveRoids.reactiveSpells[name] then
                return not CleveRoids.IsReactiveUsable(name)
            end

            -- Check if it's a spell first
            local spell = CleveRoids.GetSpell(name)
            if spell then
                return not CleveRoids.CheckSpellUsable(name)
            end

            -- Not a spell - check if it's an item or slot number
            local itemName = name
            local slotNum = tonumber(name)
            if slotNum and slotNum >= 1 and slotNum <= 19 then
                -- Resolve slot number to item name
                local link = GetInventoryItemLink("player", slotNum)
                if link then
                    local _, _, extractedName = string.find(link, "%[(.+)%]")
                    if extractedName then
                        itemName = extractedName
                    end
                end
            end

            -- Item not existing counts as "not usable"
            if not CleveRoids.HasItem(itemName) then
                return true
            end

            -- Check item cooldown (>0 remaining = not usable)
            local remaining = CleveRoids.GetItemCooldown(itemName)
            return remaining > 0
        end, conditionals, "nousable")
    end,

    member = function(conditionals)
        return Or(conditionals.member, function(v)
            return
                CleveRoids.IsTargetInGroupType(conditionals.target, "party")
                or CleveRoids.IsTargetInGroupType(conditionals.target, "raid")
        end)
    end,

    -- [party] or [party:unitid] - check if unit is in your party
    -- Default unit is conditionals.target
    party = function(conditionals)
        local unit = conditionals.party
        if unit == true or unit == nil then
            unit = conditionals.target
        end
        return CleveRoids.IsTargetInGroupType(unit, "party")
    end,

    -- [noparty] or [noparty:unitid] - check if unit is NOT in your party
    noparty = function(conditionals)
        local unit = conditionals.noparty
        if unit == true or unit == nil then
            unit = conditionals.target
        end
        return not CleveRoids.IsTargetInGroupType(unit, "party")
    end,

    -- [raid] or [raid:unitid] - check if unit is in your raid
    -- Default unit is conditionals.target
    raid = function(conditionals)
        local unit = conditionals.raid
        if unit == true or unit == nil then
            unit = conditionals.target
        end
        return CleveRoids.IsTargetInGroupType(unit, "raid")
    end,

    -- [noraid] or [noraid:unitid] - check if unit is NOT in your raid
    noraid = function(conditionals)
        local unit = conditionals.noraid
        if unit == true or unit == nil then
            unit = conditionals.target
        end
        return not CleveRoids.IsTargetInGroupType(unit, "raid")
    end,

    -- [group] or [group:party] or [group:raid] or [group:party/raid]
    -- Checks if the PLAYER is in a group (not unit membership)
    group = function(conditionals)
        local groupVal = conditionals.group
        -- Boolean form [group] - check if in any group
        if groupVal == true then
            return GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
        end
        -- Value form [group:party] or [group:raid] or [group:party/raid]
        return Multi(groupVal, function(groupType)
            if groupType == "party" then
                return GetNumPartyMembers() > 0
            elseif groupType == "raid" then
                return GetNumRaidMembers() > 0
            end
            return false
        end, conditionals, "group")
    end,

    -- [nogroup] or [nogroup:party] or [nogroup:raid] or [nogroup:party/raid]
    -- Checks if the PLAYER is NOT in a group
    nogroup = function(conditionals)
        local groupVal = conditionals.nogroup
        -- Boolean form [nogroup] - check if not in any group
        if groupVal == true then
            return GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0
        end
        -- Value form with De Morgan's law via NegatedMulti
        return NegatedMulti(groupVal, function(groupType)
            if groupType == "party" then
                return GetNumPartyMembers() == 0
            elseif groupType == "raid" then
                return GetNumRaidMembers() == 0
            end
            return true
        end, conditionals, "nogroup")
    end,

    checkchanneled = function(conditionals)
        if conditionals.checkchanneled == true then
            -- Boolean form [checkchanneled] - check if NOT channeling anything
            return CleveRoids.CheckChanneled(nil)
        else
            -- String form [checkchanneled:SpellName] - check if NOT channeling that spell
            return Multi(conditionals.checkchanneled, function(channeledSpells)
                return CleveRoids.CheckChanneled(channeledSpells)
            end, conditionals, "checkchanneled")
        end
    end,

    checkcasting = function(conditionals)
        if conditionals.checkcasting == true then
            -- Boolean form [checkcasting] - check if NOT casting anything
            return CleveRoids.CheckCasting(nil)
        else
            -- String form [checkcasting:SpellName] - check if NOT casting that spell
            return Multi(conditionals.checkcasting, function(castingSpells)
                return CleveRoids.CheckCasting(castingSpells)
            end, conditionals, "checkcasting")
        end
    end,

    buff = function(conditionals)
        return Multi(conditionals.buff, function(v)
            return CleveRoids.ValidateUnitBuff(conditionals.target, v)
        end, conditionals, "buff")
    end,

    nobuff = function(conditionals)
        return NegatedMulti(conditionals.nobuff, function(v)
            return not CleveRoids.ValidateUnitBuff(conditionals.target, v)
        end, conditionals, "nobuff")
    end,

    debuff = function(conditionals)
        return Multi(conditionals.debuff, function(v)
            return CleveRoids.ValidateUnitDebuff(conditionals.target, v)
        end, conditionals, "debuff")
    end,

    nodebuff = function(conditionals)
        return NegatedMulti(conditionals.nodebuff, function(v)
            return not CleveRoids.ValidateUnitDebuff(conditionals.target, v)
        end, conditionals, "nodebuff")
    end,

    mybuff = function(conditionals)
        return Multi(conditionals.mybuff, function(v)
            return CleveRoids.ValidatePlayerBuff(v)
        end, conditionals, "mybuff")
    end,

    nomybuff = function(conditionals)
        if CleveRoids.debug then
            local vals = conditionals.nomybuff
            local valStr = type(vals) == "table" and table.concat(vals, ", ") or tostring(vals)
            DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[nomybuff]|r Checking: " .. valStr)
        end
        local result = NegatedMulti(conditionals.nomybuff, function(v)
            local hasBuff = CleveRoids.ValidatePlayerBuff(v)
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "|cffff00ff[nomybuff]|r ValidatePlayerBuff(%s) = %s, returning %s",
                    tostring(v), tostring(hasBuff), tostring(not hasBuff)))
            end
            return not hasBuff
        end, conditionals, "nomybuff")
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[nomybuff]|r Final result: " .. tostring(result))
        end
        return result
    end,

    mydebuff = function(conditionals)
        return Multi(conditionals.mydebuff, function(v)
            return CleveRoids.ValidatePlayerDebuff(v)
        end, conditionals, "mydebuff")
    end,

    nomydebuff = function(conditionals)
        return NegatedMulti(conditionals.nomydebuff, function(v)
            return not CleveRoids.ValidatePlayerDebuff(v)
        end, conditionals, "nomydebuff")
    end,

    power = function(conditionals)
        return Multi(conditionals.power, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<80)
            if args.comparisons and type(args.comparisons) == "table" then
                local unit = conditionals.target or "target"
                if not UnitExists(unit) then return false end
                local powerPercent = 100 / UnitManaMax(unit) * UnitMana(unit)

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](powerPercent, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidatePower(conditionals.target, args.operator, args.amount)
        end, conditionals, "power")
    end,

    mypower = function(conditionals)
        return Multi(conditionals.mypower, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<80)
            if args.comparisons and type(args.comparisons) == "table" then
                -- PERFORMANCE: Use cached player power
                local powerPercent = CleveRoids.GetCachedPlayerPowerPercent()

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](powerPercent, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidatePower("player", args.operator, args.amount)
        end, conditionals, "mypower")
    end,

    rawpower = function(conditionals)
        return Multi(conditionals.rawpower, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >500&<1000)
            if args.comparisons and type(args.comparisons) == "table" then
                local unit = conditionals.target or "target"
                if not UnitExists(unit) then return false end
                local power = UnitMana(unit)

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](power, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateRawPower(conditionals.target, args.operator, args.amount)
        end, conditionals, "rawpower")
    end,

    myrawpower = function(conditionals)
        return Multi(conditionals.myrawpower, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >500&<1000)
            if args.comparisons and type(args.comparisons) == "table" then
                -- PERFORMANCE: Use cached player power
                local power = CleveRoids.GetCachedPlayerPower()

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](power, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateRawPower("player", args.operator, args.amount)
        end, conditionals, "myrawpower")
    end,

    druidmana = function(conditionals)
        return Multi(conditionals.druidmana, function(args)
            if type(args) ~= "table" then return false end
            return CleveRoids.ValidateDruidRawMana("player", args.operator, args.amount)
        end, conditionals, "druidmana")
    end,

    powerlost = function(conditionals)
        return Multi(conditionals.powerlost, function(args)
            if type(args) ~= "table" then return false end
            return CleveRoids.ValidatePowerLost(conditionals.target, args.operator, args.amount)
        end, conditionals, "powerlost")
    end,

    mypowerlost = function(conditionals)
        return Multi(conditionals.mypowerlost, function(args)
            if type(args) ~= "table" then return false end
            return CleveRoids.ValidatePowerLost("player", args.operator, args.amount)
        end, conditionals, "mypowerlost")
    end,

    hp = function(conditionals)
        return Multi(conditionals.hp, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<80)
            if args.comparisons and type(args.comparisons) == "table" then
                local unit = conditionals.target or "target"
                if not UnitExists(unit) then return false end

                -- PERFORMANCE: Use cached health for target
                local hp
                if unit == "target" then
                    hp = CleveRoids.GetCachedTargetHealthPercent()
                else
                    local maxHp = UnitHealthMax(unit)
                    hp = maxHp > 0 and (100 * UnitHealth(unit) / maxHp) or 0
                end

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](hp, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateHp(conditionals.target, args.operator, args.amount)
        end, conditionals, "hp")
    end,

    level = function(conditionals)
        return Multi(conditionals.level, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<60)
            if args.comparisons and type(args.comparisons) == "table" then
                local unit = conditionals.target or "target"
                if not UnitExists(unit) then return false end
                local level = UnitLevel(unit)

                -- Treat skull/boss mobs (??) as level 63
                if level == -1 then
                    level = 63
                end

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](level, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateLevel(conditionals.target, args.operator, args.amount)
        end, conditionals, "level")
    end,

    mylevel = function(conditionals)
        return Multi(conditionals.mylevel, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<60)
            if args.comparisons and type(args.comparisons) == "table" then
                local level = UnitLevel("player")

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](level, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateLevel("player", args.operator, args.amount)
        end, conditionals, "mylevel")
    end,

    myhp = function(conditionals)
        return Multi(conditionals.myhp, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<80)
            if args.comparisons and type(args.comparisons) == "table" then
                -- PERFORMANCE: Use cached player health
                local hp = CleveRoids.GetCachedPlayerHealthPercent()

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](hp, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateHp("player", args.operator, args.amount)
        end, conditionals, "myhp")
    end,

    rawhp = function(conditionals)
        return Multi(conditionals.rawhp, function(args)
            if type(args) ~= "table" then return false end
            return CleveRoids.ValidateRawHp(conditionals.target, args.operator, args.amount)
        end, conditionals, "rawhp")
    end,

    myrawhp = function(conditionals)
        return Multi(conditionals.myrawhp, function(args)
            if type(args) ~= "table" then return false end
            return CleveRoids.ValidateRawHp("player", args.operator, args.amount)
        end, conditionals, "myrawhp")
    end,

    hplost = function(conditionals)
        return Multi(conditionals.hplost, function(args)
            if type(args) ~= "table" then return false end
            return CleveRoids.ValidateHpLost(conditionals.target, args.operator, args.amount)
        end, conditionals, "hplost")
    end,

    myhplost = function(conditionals)
        return Multi(conditionals.myhplost, function(args)
            if type(args) ~= "table" then return false end
            return CleveRoids.ValidateHpLost("player", args.operator, args.amount)
        end, conditionals, "myhplost")
    end,

    type = function(conditionals)
        return Or(conditionals.type, function(unittype)
            return CleveRoids.ValidateCreatureType(unittype, conditionals.target)
        end)
    end,

    notype = function(conditionals)
        return NegatedMulti(conditionals.notype, function(unittype)
            return not CleveRoids.ValidateCreatureType(unittype, conditionals.target)
        end, conditionals, "notype")
    end,

    cooldown = function(conditionals)
        return Multi(conditionals.cooldown,function (v)
            return CleveRoids.ValidateCooldown(v, true)
        end, conditionals, "cooldown")
    end,

    nocooldown = function(conditionals)
        return NegatedMulti(conditionals.nocooldown,function (v)
            return not CleveRoids.ValidateCooldown(v, true)
        end, conditionals, "nocooldown")
    end,

    cdgcd = function(conditionals)
        return Multi(conditionals.cdgcd,function (v)
            return CleveRoids.ValidateCooldown(v, false)
        end, conditionals, "cdgcd")
    end,

    nocdgcd = function(conditionals)
        return NegatedMulti(conditionals.nocdgcd,function (v)
            return not CleveRoids.ValidateCooldown(v, false)
        end, conditionals, "nocdgcd")
    end,

    channeled = function(conditionals)
        -- Use time-based prediction for accuracy
        if CleveRoids.CurrentSpell.type == "channeled" and CleveRoids.channelStartTime and CleveRoids.channelDuration then
            local remaining = CleveRoids.channelDuration - (GetTime() - CleveRoids.channelStartTime)
            if remaining <= 0.1 then
                return false -- Channel is done
            end
        end
        return CleveRoids.CurrentSpell.type == "channeled"
    end,

    nochanneled = function(conditionals)
        -- Use time-based prediction for accuracy
        if CleveRoids.CurrentSpell.type == "channeled" and CleveRoids.channelStartTime and CleveRoids.channelDuration then
            local remaining = CleveRoids.channelDuration - (GetTime() - CleveRoids.channelStartTime)
            if remaining <= 0.1 then
                return true -- Channel is done
            end
        end
        return CleveRoids.CurrentSpell.type ~= "channeled"
    end,

    channeltime = function(conditionals)
        -- Calculate remaining time (0 if not channeling)
        local timeLeft = 0

        if CleveRoids.CurrentSpell.type == "channeled" and CleveRoids.channelStartTime and CleveRoids.channelDuration then
            local elapsed = GetTime() - CleveRoids.channelStartTime
            timeLeft = CleveRoids.channelDuration - elapsed
            -- Don't allow negative time
            if timeLeft < 0 then timeLeft = 0 end
        end

        local check = conditionals.channeltime

        -- channeltime is stored as an array by the parser, get the first element
        if type(check) == "table" and type(check[1]) == "table" then
            check = check[1]
        end

        if type(check) == "table" and check.operator and check.amount then
            -- Now compare: if not channeling, timeLeft is 0, so [channeltime:<0.5] returns true
            return CleveRoids.comparators[check.operator](timeLeft, check.amount)
        end

        return false
    end,

    casttime = function(conditionals)
        -- Calculate remaining time (0 if not casting)
        local timeLeft = 0

        if CleveRoids.CurrentSpell.type == "cast" and CleveRoids.castStartTime and CleveRoids.castDuration then
            local elapsed = GetTime() - CleveRoids.castStartTime
            timeLeft = CleveRoids.castDuration - elapsed
            -- Don't allow negative time
            if timeLeft < 0 then timeLeft = 0 end
        end

        local check = conditionals.casttime

        -- casttime is stored as an array by the parser, get the first element
        if type(check) == "table" and type(check[1]) == "table" then
            check = check[1]
        end

        if type(check) == "table" and check.operator and check.amount then
            -- Now compare: if not casting, timeLeft is 0, so [casttime:<0.5] returns true
            return CleveRoids.comparators[check.operator](timeLeft, check.amount)
        end

        return false
    end,

    targeting = function(conditionals)
        return Or(conditionals.targeting, function (unit)
            return (UnitIsUnit("targettarget", unit) == 1)
        end)
    end,

    notargeting = function(conditionals)
        return NegatedMulti(conditionals.notargeting, function (unit)
            return UnitIsUnit("targettarget", unit) ~= 1
        end, conditionals, "notargeting")
    end,

    isplayer = function(conditionals)
        return UnitIsPlayer(conditionals.target)
    end,

    isnpc = function(conditionals)
        return not UnitIsPlayer(conditionals.target)
    end,

    inrange = function(conditionals)
        if not IsSpellInRange then return end
        local API = CleveRoids.NampowerAPI
        return Multi(conditionals.inrange, function(spellName)
            local target = conditionals.target or "target"
            local checkValue = spellName or conditionals.action

            -- Use API wrapper which handles self-cast spells correctly
            local result = API.IsSpellInRange(checkValue, target)
            return result == 1
        end, conditionals, "inrange")
    end,

    noinrange = function(conditionals)
        if not IsSpellInRange then return end
        local API = CleveRoids.NampowerAPI
        return NegatedMulti(conditionals.noinrange, function(spellName)
            local target = conditionals.target or "target"
            local checkValue = spellName or conditionals.action

            -- Use API wrapper which handles self-cast spells correctly
            local result = API.IsSpellInRange(checkValue, target)
            return result == 0
        end, conditionals, "noinrange")
    end,

    outrange = function(conditionals)
        if not IsSpellInRange then return end
        local API = CleveRoids.NampowerAPI
        return Multi(conditionals.outrange, function(spellName)
            local target = conditionals.target or "target"
            local checkValue = spellName or conditionals.action

            -- Use API wrapper which handles self-cast spells correctly
            local result = API.IsSpellInRange(checkValue, target)
            return result == 0
        end, conditionals, "outrange")
    end,

    combo = function(conditionals)
        return Multi(conditionals.combo, function(args)
            return CleveRoids.ValidateComboPoints(args.operator, args.amount)
        end, conditionals, "combo")
    end,

    nocombo = function(conditionals)
        return NegatedMulti(conditionals.nocombo, function(args)
            return not CleveRoids.ValidateComboPoints(args.operator, args.amount)
        end, conditionals, "nocombo")
    end,

    known = function(conditionals)
        return Multi(conditionals.known, function(args)
            return CleveRoids.ValidateKnown(args)
        end, conditionals, "known")
    end,

    noknown = function(conditionals)
        return NegatedMulti(conditionals.noknown, function(args)
            return not CleveRoids.ValidateKnown(args)
        end, conditionals, "noknown")
    end,

    resting = function()
        return IsResting() == 1
    end,

    noresting = function()
        return IsResting() == nil
    end,

    stat = function(conditionals)
        return Multi(conditionals.stat, function(args)
            if type(args) ~= "table" or not args.name then
                return false -- Malformed arguments from the parser.
            end

            local stat_key = string.lower(args.name)
            local get_stat_func = stat_checks[stat_key]

            if not get_stat_func then
                return false -- The requested stat key is invalid.
            end

            local current_value = get_stat_func()
            if not current_value then return false end

            -- Check if this is a multi-comparison stat conditional
            -- args.comparisons will be a table of {operator=, amount=} if multiple
            if args.comparisons and type(args.comparisons) == "table" then
                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.comparators[comp.operator] then
                        return false -- Invalid operator
                    end
                    if not CleveRoids.comparators[comp.operator](current_value, comp.amount) then
                        return false -- One comparison failed, so the whole conditional fails
                    end
                end
                return true -- All comparisons passed
            else
                -- Single comparison (backward compatibility)
                if not args.operator or not args.amount then
                    return false
                end
                return CleveRoids.comparators[args.operator](current_value, args.amount)
            end
        end, conditionals, "stat")
    end,

    class = function(conditionals)
        -- Determine which unit to check. Defaults to 'target' if no @unitid was specified.
        local unitToCheck = conditionals.target or "target"

        -- The conditional must fail if the unit doesn't exist OR is not a player.
        if not UnitExists(unitToCheck) or not UnitIsPlayer(unitToCheck) then
            return false
        end

        -- Get the player's class.
        local localizedClass, englishClass = UnitClass(unitToCheck)
        if not localizedClass then return false end -- Failsafe for unusual cases

        -- The "Or" helper handles multiple values like [class:Warrior/Druid].
        return Or(conditionals.class, function(requiredClass)
            return string.lower(requiredClass) == string.lower(localizedClass) or string.lower(requiredClass) == string.lower(englishClass)
        end)
    end,

    noclass = function(conditionals)
        -- Determine which unit to check. Defaults to 'target' if no @unitid was specified.
        local unitToCheck = conditionals.target or "target"

        -- A unit that doesn't exist cannot have a specific player class.
        if not UnitExists(unitToCheck) then
            return true
        end

        -- An NPC cannot have a specific player class.
        if not UnitIsPlayer(unitToCheck) then
            return true
        end

        -- If we get here, the unit is a player. Now check their class.
        local localizedClass, englishClass = UnitClass(unitToCheck)
        -- A player should always have a class, but if not, this condition is still met.
        if not localizedClass then return true end

        -- The "NegatedMulti" helper ensures the player's class is not any of the forbidden classes.
        return NegatedMulti(conditionals.noclass, function(forbiddenClass)
            return string.lower(forbiddenClass) ~= string.lower(localizedClass) and string.lower(forbiddenClass) ~= string.lower(englishClass)
        end, conditionals, "noclass")
    end,

    pet = function(conditionals)
        if not UnitExists("pet") then
            return false
        end

        return Or(conditionals.pet, function(petType)
            local currentPet = UnitCreatureFamily("pet")
            if not currentPet then
                return false
            end
            return string.lower(currentPet) == string.lower(petType)
        end)
    end,

    nopet = function(conditionals)
        if not UnitExists("pet") then
            return true
        end

        return NegatedMulti(conditionals.nopet, function(petType)
            local currentPet = UnitCreatureFamily("pet")
            if not currentPet then
                return true
            end
            return string.lower(currentPet) ~= string.lower(petType)
        end, conditionals, "nopet")
    end,

    swimming = function(conditionals)
        -- Check if "Aquatic Form" is in the reactive list and usable
        return CleveRoids.IsReactiveUsable("Aquatic Form")
    end,

    noswimming = function(conditionals)
        -- Check if "Aquatic Form" is NOT usable
        return not CleveRoids.IsReactiveUsable("Aquatic Form")
    end,

    distance = function(conditionals)
        if not CleveRoids.hasUnitXP then return false end

        return Multi(conditionals.distance, function(args)
            if type(args) ~= "table" or not args.operator or not args.amount then
                return false
            end

            local unit = conditionals.target or "target"
            if not UnitExists(unit) then return false end

            local distance = UnitXP("distanceBetween", "player", unit)
            if not distance then return false end

            return CleveRoids.comparators[args.operator](distance, args.amount)
        end, conditionals, "distance")
    end,

    nodistance = function(conditionals)
        if not CleveRoids.hasUnitXP then return false end

        return NegatedMulti(conditionals.nodistance, function(args)
            if type(args) ~= "table" or not args.operator or not args.amount then
                return false
            end

            local unit = conditionals.target or "target"
            if not UnitExists(unit) then return false end

            local distance = UnitXP("distanceBetween", "player", unit)
            if not distance then return false end

            return not CleveRoids.comparators[args.operator](distance, args.amount)
        end, conditionals, "nodistance")
    end,

    behind = function(conditionals)
        if not CleveRoids.hasUnitXP then return false end

        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return false end

        return UnitXP("behind", "player", unit) == true
    end,

    nobehind = function(conditionals)
        if not CleveRoids.hasUnitXP then return false end

        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return false end

        return UnitXP("behind", "player", unit) ~= true
    end,

    insight = function(conditionals)
        if not CleveRoids.hasUnitXP then return false end

        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return false end

        return UnitXP("inSight", "player", unit) == true
    end,

    noinsight = function(conditionals)
        if not CleveRoids.hasUnitXP then return false end

        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return false end

        return UnitXP("inSight", "player", unit) ~= true
    end,

    meleerange = function(conditionals)
        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return false end

        if CleveRoids.hasUnitXP then
            local distance = UnitXP("distanceBetween", "player", unit, "meleeAutoAttack")
            return distance and distance <= 5
        else
            -- Fallback: use CheckInteractDistance (3 = melee range)
            return CheckInteractDistance(unit, 3)
        end
    end,

    nomeleerange = function(conditionals)
        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return true end

        if CleveRoids.hasUnitXP then
            local distance = UnitXP("distanceBetween", "player", unit, "meleeAutoAttack")
            return not distance or distance > 5
        else
            return not CheckInteractDistance(unit, 3)
        end
    end,

    queuedspell = function(conditionals)
        if not CleveRoids.hasNampower then return false end
        if not CleveRoids.queuedSpell then return false end

        -- If no specific spell name provided, check if ANY spell is queued
        if not conditionals.queuedspell or table.getn(conditionals.queuedspell) == 0 then
            return true
        end

        -- Check if specific spell is queued
        return Or(conditionals.queuedspell, function(spellName)
            if not CleveRoids.queuedSpell.spellName then return false end
            local queuedName = string.gsub(CleveRoids.queuedSpell.spellName, "%s*%(.-%)%s*$", "")
            local checkName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
            return string.lower(queuedName) == string.lower(checkName)
        end)
    end,

    noqueuedspell = function(conditionals)
        if not CleveRoids.hasNampower then return false end

        -- If no specific spell name, check if NO spell is queued
        if not conditionals.noqueuedspell or table.getn(conditionals.noqueuedspell) == 0 then
            return CleveRoids.queuedSpell == nil
        end

        -- Check if specific spell is NOT queued
        if not CleveRoids.queuedSpell or not CleveRoids.queuedSpell.spellName then
            return true
        end

        return NegatedMulti(conditionals.noqueuedspell, function(spellName)
            local queuedName = string.gsub(CleveRoids.queuedSpell.spellName, "%s*%(.-%)%s*$", "")
            local checkName = string.gsub(spellName, "%s*%(.-%)%s*$", "")
            return string.lower(queuedName) ~= string.lower(checkName)
        end, conditionals, "noqueuedspell")
    end,

    onswingpending = function(conditionals)
        if not GetCurrentCastingInfo then return false end

        local _, _, _, _, _, onswing = GetCurrentCastingInfo()
        return onswing == 1
    end,

    noonswingpending = function(conditionals)
        if not GetCurrentCastingInfo then return true end

        local _, _, _, _, _, onswing = GetCurrentCastingInfo()
        return onswing ~= 1
    end,

    mybuffcount = function(conditionals)
        return Multi(conditionals.mybuffcount,function (v) return CleveRoids.ValidatePlayerAuraCount(v.bigger, v.amount) end, conditionals, "mybuffcount")
    end,

    mhimbue = function(conditionals)
        local imbueName = nil
        
        -- Case 1: conditionals.mhimbue is a string (e.g., [mhimbue]Frostbrand)
        if type(conditionals.mhimbue) == "string" then
            imbueName = conditionals.mhimbue
        -- Case 2: conditionals.mhimbue is a table (e.g., [mhimbue:Frostbrand])
        elseif type(conditionals.mhimbue) == "table" and table.getn(conditionals.mhimbue) > 0 then
            imbueName = conditionals.mhimbue[1]  -- Use first value
        -- Case 3: Boolean true means check for any imbue
        elseif conditionals.mhimbue == true then
            imbueName = nil  -- Check for existence only
        end
        
        return CleveRoids.ValidateWeaponImbue("mh", imbueName)
    end,

    nomhimbue = function(conditionals)
        local imbueName = nil
        
        -- Case 1: conditionals.nomhimbue is a string
        if type(conditionals.nomhimbue) == "string" then
            imbueName = conditionals.nomhimbue
        -- Case 2: conditionals.nomhimbue is a table
        elseif type(conditionals.nomhimbue) == "table" and table.getn(conditionals.nomhimbue) > 0 then
            imbueName = conditionals.nomhimbue[1]
        -- Case 3: Boolean true
        elseif conditionals.nomhimbue == true then
            imbueName = nil
        end
        
        return not CleveRoids.ValidateWeaponImbue("mh", imbueName)
    end,

    ohimbue = function(conditionals)
        local imbueName = nil
        
        -- Case 1: conditionals.ohimbue is a string
        if type(conditionals.ohimbue) == "string" then
            imbueName = conditionals.ohimbue
        -- Case 2: conditionals.ohimbue is a table
        elseif type(conditionals.ohimbue) == "table" and table.getn(conditionals.ohimbue) > 0 then
            imbueName = conditionals.ohimbue[1]
        -- Case 3: Boolean true
        elseif conditionals.ohimbue == true then
            imbueName = nil
        end
        
        return CleveRoids.ValidateWeaponImbue("oh", imbueName)
    end,

    noohimbue = function(conditionals)
        local imbueName = nil
        
        -- Case 1: conditionals.noohimbue is a string
        if type(conditionals.noohimbue) == "string" then
            imbueName = conditionals.noohimbue
        -- Case 2: conditionals.noohimbue is a table
        elseif type(conditionals.noohimbue) == "table" and table.getn(conditionals.noohimbue) > 0 then
            imbueName = conditionals.noohimbue[1]
        -- Case 3: Boolean true
        elseif conditionals.noohimbue == true then
            imbueName = nil
        end
        
        return not CleveRoids.ValidateWeaponImbue("oh", imbueName)
    end,

    immune = function(conditionals)
        -- Check if target is immune to the spell being cast or damage school
        -- Usage: [immune] SpellName  OR  [immune:SpellName]  OR  [immune:fire]
        local checkValue = nil

        -- Case 1: [immune:SpellName] or [immune:fire]
        if type(conditionals.immune) == "table" and table.getn(conditionals.immune) > 0 then
            checkValue = conditionals.immune[1]
        elseif type(conditionals.immune) == "string" then
            checkValue = conditionals.immune
        -- Case 2: [immune] SpellName (check the action being cast)
        elseif conditionals.action then
            checkValue = conditionals.action
        end

        if not checkValue then
            return false
        end

        return CleveRoids.CheckImmunity(conditionals.target or "target", checkValue)
    end,

    noimmune = function(conditionals)
        -- Check if target is NOT immune to the spell being cast or damage school
        -- Usage: [noimmune] SpellName  OR  [noimmune:SpellName]  OR  [noimmune:fire]
        local checkValue = nil

        -- Case 1: [noimmune:SpellName] or [noimmune:fire]
        if type(conditionals.noimmune) == "table" and table.getn(conditionals.noimmune) > 0 then
            checkValue = conditionals.noimmune[1]
        elseif type(conditionals.noimmune) == "string" then
            checkValue = conditionals.noimmune
        -- Case 2: [noimmune] SpellName (check the action being cast)
        elseif conditionals.action then
            checkValue = conditionals.action
        end

        if not checkValue then
            return true  -- If we can't determine spell/school, assume not immune
        end

        return not CleveRoids.CheckImmunity(conditionals.target or "target", checkValue)
    end,

    -- SP_SwingTimer integration conditionals
    -- Checks percentage of swing time that has elapsed
    -- Usage: [swingtimer:<15] = less than 15% of swing has elapsed (early in swing)
    --        [swingtimer:>80] = more than 80% of swing has elapsed (late in swing)
    swingtimer = function(conditionals)
        return Multi(conditionals.swingtimer, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<80)
            if args.comparisons and type(args.comparisons) == "table" then
                -- Check if SP_SwingTimer is loaded
                if st_timer == nil then
                    if not CleveRoids._swingTimerErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [swingtimer] conditional requires the SP_SwingTimer addon. Get it at: https://github.com/jrc13245/SP_SwingTimer", 1, 0.5, 0.5)
                        CleveRoids._swingTimerErrorShown = true
                    end
                    return false
                end

                local attackSpeed = UnitAttackSpeed("player")
                if not attackSpeed or attackSpeed <= 0 then return false end

                local timeElapsed = attackSpeed - st_timer
                local percentElapsed = (timeElapsed / attackSpeed) * 100

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](percentElapsed, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateSwingTimer(args.operator, args.amount)
        end, conditionals, "swingtimer")
    end,

    -- Alias for swingtimer
    stimer = function(conditionals)
        return Multi(conditionals.stimer, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<80)
            if args.comparisons and type(args.comparisons) == "table" then
                -- Check if SP_SwingTimer is loaded
                if st_timer == nil then
                    if not CleveRoids._swingTimerErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [swingtimer] conditional requires the SP_SwingTimer addon. Get it at: https://github.com/jrc13245/SP_SwingTimer", 1, 0.5, 0.5)
                        CleveRoids._swingTimerErrorShown = true
                    end
                    return false
                end

                local attackSpeed = UnitAttackSpeed("player")
                if not attackSpeed or attackSpeed <= 0 then return false end

                local timeElapsed = attackSpeed - st_timer
                local percentElapsed = (timeElapsed / attackSpeed) * 100

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](percentElapsed, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateSwingTimer(args.operator, args.amount)
        end, conditionals, "stimer")
    end,

    -- Negated swingtimer
    noswingtimer = function(conditionals)
        return NegatedMulti(conditionals.noswingtimer, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison by checking positive and negating
            if args.comparisons and type(args.comparisons) == "table" then
                -- Check if SP_SwingTimer is loaded
                if st_timer == nil then
                    if not CleveRoids._swingTimerErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [swingtimer] conditional requires the SP_SwingTimer addon. Get it at: https://github.com/jrc13245/SP_SwingTimer", 1, 0.5, 0.5)
                        CleveRoids._swingTimerErrorShown = true
                    end
                    return true
                end

                local attackSpeed = UnitAttackSpeed("player")
                if not attackSpeed or attackSpeed <= 0 then return true end

                local timeElapsed = attackSpeed - st_timer
                local percentElapsed = (timeElapsed / attackSpeed) * 100

                -- Check if ALL comparisons pass
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return true
                    end
                    if not CleveRoids.comparators[comp.operator](percentElapsed, comp.amount) then
                        return true  -- One failed, so positive=false, negated=true
                    end
                end
                return false  -- All passed, so positive=true, negated=false
            end

            return not CleveRoids.ValidateSwingTimer(args.operator, args.amount)
        end, conditionals, "noswingtimer")
    end,

    -- Alias for noswingtimer
    nostimer = function(conditionals)
        return NegatedMulti(conditionals.nostimer, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison by checking positive and negating
            if args.comparisons and type(args.comparisons) == "table" then
                -- Check if SP_SwingTimer is loaded
                if st_timer == nil then
                    if not CleveRoids._swingTimerErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [swingtimer] conditional requires the SP_SwingTimer addon. Get it at: https://github.com/jrc13245/SP_SwingTimer", 1, 0.5, 0.5)
                        CleveRoids._swingTimerErrorShown = true
                    end
                    return true
                end

                local attackSpeed = UnitAttackSpeed("player")
                if not attackSpeed or attackSpeed <= 0 then return true end

                local timeElapsed = attackSpeed - st_timer
                local percentElapsed = (timeElapsed / attackSpeed) * 100

                -- Check if ALL comparisons pass
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return true
                    end
                    if not CleveRoids.comparators[comp.operator](percentElapsed, comp.amount) then
                        return true  -- One failed, so positive=false, negated=true
                    end
                end
                return false  -- All passed, so positive=true, negated=false
            end

            return not CleveRoids.ValidateSwingTimer(args.operator, args.amount)
        end, conditionals, "nostimer")
    end,

    -- Threat percentage conditional (reads server data via CHAT_MSG_ADDON)
    -- Usage: [threat:>80] - true if threat is above 80%
    -- 100% = will pull aggro
    -- Note: Requires TWThreat addon to request threat data from server
    threat = function(conditionals)
        return Multi(conditionals.threat, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >50&<90)
            if args.comparisons and type(args.comparisons) == "table" then
                local threatpct = CleveRoids.GetPlayerThreatPercent()
                if threatpct == nil then return false end

                -- ALL comparisons must pass (AND logic)
                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](threatpct, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateThreat(args.operator, args.amount)
        end, conditionals, "threat")
    end,

    -- Negated threat conditional
    nothreat = function(conditionals)
        return NegatedMulti(conditionals.nothreat, function(args)
            if type(args) ~= "table" then return false end

            if args.comparisons and type(args.comparisons) == "table" then
                local threatpct = CleveRoids.GetPlayerThreatPercent()
                if threatpct == nil then return true end

                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return true
                    end
                    if not CleveRoids.comparators[comp.operator](threatpct, comp.amount) then
                        return true
                    end
                end
                return false
            end

            return not CleveRoids.ValidateThreat(args.operator, args.amount)
        end, conditionals, "nothreat")
    end,

    -- Time-To-Kill conditional (requires TimeToKill addon)
    -- Usage: [ttk:<10] - true if target will die in less than 10 seconds
    ttk = function(conditionals)
        return Multi(conditionals.ttk, function(args)
            if type(args) ~= "table" then return false end

            -- Handle multi-comparison (e.g., >5&<15)
            if args.comparisons and type(args.comparisons) == "table" then
                if type(TimeToKill) ~= "table" or type(TimeToKill.GetTTK) ~= "function" then
                    if not CleveRoids._ttkErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [ttk] conditional requires the TimeToKill addon.", 1, 0.5, 0.5)
                        CleveRoids._ttkErrorShown = true
                    end
                    return false
                end

                local ttk = TimeToKill.GetTTK()
                if ttk == nil then return false end

                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](ttk, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateTTK(args.operator, args.amount)
        end, conditionals, "ttk")
    end,

    -- Negated TTK conditional
    nottk = function(conditionals)
        return NegatedMulti(conditionals.nottk, function(args)
            if type(args) ~= "table" then return false end

            if args.comparisons and type(args.comparisons) == "table" then
                if type(TimeToKill) ~= "table" or type(TimeToKill.GetTTK) ~= "function" then
                    if not CleveRoids._ttkErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [ttk] conditional requires the TimeToKill addon.", 1, 0.5, 0.5)
                        CleveRoids._ttkErrorShown = true
                    end
                    return true
                end

                local ttk = TimeToKill.GetTTK()
                if ttk == nil then return true end

                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return true
                    end
                    if not CleveRoids.comparators[comp.operator](ttk, comp.amount) then
                        return true
                    end
                end
                return false
            end

            return not CleveRoids.ValidateTTK(args.operator, args.amount)
        end, conditionals, "nottk")
    end,

    -- Time-To-Execute conditional (requires TimeToKill addon)
    -- Usage: [tte:<5] - true if target will reach 20% HP in less than 5 seconds
    tte = function(conditionals)
        return Multi(conditionals.tte, function(args)
            if type(args) ~= "table" then return false end

            if args.comparisons and type(args.comparisons) == "table" then
                if type(TimeToKill) ~= "table" or type(TimeToKill.GetTTE) ~= "function" then
                    if not CleveRoids._ttkErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [tte] conditional requires the TimeToKill addon.", 1, 0.5, 0.5)
                        CleveRoids._ttkErrorShown = true
                    end
                    return false
                end

                local tte = TimeToKill.GetTTE()
                if tte == nil then return false end

                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return false
                    end
                    if not CleveRoids.comparators[comp.operator](tte, comp.amount) then
                        return false
                    end
                end
                return true
            end

            return CleveRoids.ValidateTTE(args.operator, args.amount)
        end, conditionals, "tte")
    end,

    -- Negated TTE conditional
    notte = function(conditionals)
        return NegatedMulti(conditionals.notte, function(args)
            if type(args) ~= "table" then return false end

            if args.comparisons and type(args.comparisons) == "table" then
                if type(TimeToKill) ~= "table" or type(TimeToKill.GetTTE) ~= "function" then
                    if not CleveRoids._ttkErrorShown then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The [tte] conditional requires the TimeToKill addon.", 1, 0.5, 0.5)
                        CleveRoids._ttkErrorShown = true
                    end
                    return true
                end

                local tte = TimeToKill.GetTTE()
                if tte == nil then return true end

                for _, comp in ipairs(args.comparisons) do
                    if not CleveRoids.operators[comp.operator] then
                        return true
                    end
                    if not CleveRoids.comparators[comp.operator](tte, comp.amount) then
                        return true
                    end
                end
                return false
            end

            return not CleveRoids.ValidateTTE(args.operator, args.amount)
        end, conditionals, "notte")
    end,

    -- Slam clip window conditionals for Warrior Slam rotation optimization
    -- Based on math: MaxSlamPercent = (SwingTimer - SlamCastTime) / SwingTimer * 100
    -- Requires SP_SwingTimer addon and Nampower for cast time lookup

    -- [noslamclip] - True if casting Slam NOW will NOT clip the auto-attack
    -- Usage: /cast [noslamclip] Slam
    noslamclip = function(conditionals)
        return CleveRoids.ValidateNoSlamClip()
    end,

    -- [slamclip] - True if casting Slam NOW WILL clip the auto-attack (negated)
    -- Usage: /cast [slamclip] Heroic Strike  -- Use HS instead when past slam window
    slamclip = function(conditionals)
        return not CleveRoids.ValidateNoSlamClip()
    end,

    -- [nonextslamclip] - True if casting an instant NOW will NOT cause NEXT Slam to clip
    -- Scenario: Skip Slam this swing, cast instant, then Slam next swing without clipping
    -- Formula: MaxInstantPercent = (2 * SwingTimer - SlamCastTime - GCD) / SwingTimer * 100
    -- Usage: /cast [nonextslamclip] Bloodthirst
    nonextslamclip = function(conditionals)
        return CleveRoids.ValidateNoNextSlamClip()
    end,

    -- [nextslamclip] - True if casting an instant NOW WILL cause NEXT Slam to clip (negated)
    -- Usage: Use this when you want to know you're past the instant window
    nextslamclip = function(conditionals)
        return not CleveRoids.ValidateNoNextSlamClip()
    end,

    -- Checks if the target uses a specific power type (mana, rage, energy)
    powertype = function(conditionals)
        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return false end

        return Or(conditionals.powertype, function(powerTypeName)
            local powerType = UnitPowerType(unit)
            local powerTypeLower = string.lower(powerTypeName or "")

            if powerTypeLower == "mana" then
                return powerType == 0
            elseif powerTypeLower == "rage" then
                return powerType == 1
            elseif powerTypeLower == "focus" then
                return powerType == 2
            elseif powerTypeLower == "energy" then
                return powerType == 3
            end

            return false
        end)
    end,

    -- Checks if the target does NOT use a specific power type
    nopowertype = function(conditionals)
        local unit = conditionals.target or "target"
        if not UnitExists(unit) then return true end

        return NegatedMulti(conditionals.nopowertype, function(powerTypeName)
            local powerType = UnitPowerType(unit)
            local powerTypeLower = string.lower(powerTypeName or "")

            if powerTypeLower == "mana" then
                return powerType ~= 0
            elseif powerTypeLower == "rage" then
                return powerType ~= 1
            elseif powerTypeLower == "focus" then
                return powerType ~= 2
            elseif powerTypeLower == "energy" then
                return powerType ~= 3
            end

            return true
        end, conditionals, "nopowertype")
    end,

    -- ========================================================================
    -- CC (Crowd Control) Conditionals - Requires BuffLib for full functionality
    -- ========================================================================

    -- [cc:type] - Check if target has a specific CC effect
    -- Types: stun, fear, root, snare/slow, sleep, charm, polymorph, banish, horror,
    --        disarm, silence, daze, sap, freeze, knockout/incap, disorient, shackle
    -- Special: [cc] or [cc:any] checks for any loss-of-control effect
    -- Examples: [cc:stun] [@focus,cc:fear] [cc:stun/fear/root]
    cc = function(conditionals)
        local target = conditionals.target or "target"

        -- If no specific CC type, check for ANY loss-of-control
        if not conditionals.cc or (type(conditionals.cc) == "table" and table.getn(conditionals.cc) == 0) then
            return CleveRoids.ValidateUnitAnyCrowdControl(target)
        end

        -- Check for specific CC type(s) - OR logic
        return Or(conditionals.cc, function(ccType)
            return CleveRoids.ValidateUnitCC(target, ccType)
        end)
    end,

    -- [nocc:type] - Check if target does NOT have a specific CC effect
    -- Uses AND logic for negation: [nocc:stun/fear] = not stunned AND not feared
    nocc = function(conditionals)
        local target = conditionals.target or "target"

        -- If no specific CC type, check for NO loss-of-control
        if not conditionals.nocc or (type(conditionals.nocc) == "table" and table.getn(conditionals.nocc) == 0) then
            return not CleveRoids.ValidateUnitAnyCrowdControl(target)
        end

        -- Check for absence of specific CC type(s) - AND logic (must be missing ALL)
        return NegatedMulti(conditionals.nocc, function(ccType)
            return not CleveRoids.ValidateUnitCC(target, ccType)
        end, conditionals, "nocc")
    end,

    -- [mycc:type] - Check if PLAYER has a specific CC effect
    -- Same types as [cc], but always checks the player
    -- Examples: [mycc:stun] [mycc:fear/charm] [mycc] (any CC)
    mycc = function(conditionals)
        -- If no specific CC type, check for ANY loss-of-control on player
        if not conditionals.mycc or (type(conditionals.mycc) == "table" and table.getn(conditionals.mycc) == 0) then
            return CleveRoids.ValidateUnitAnyCrowdControl("player")
        end

        -- Check for specific CC type(s) - OR logic
        return Or(conditionals.mycc, function(ccType)
            return CleveRoids.ValidateUnitCC("player", ccType)
        end)
    end,

    -- [nomycc:type] - Check if PLAYER does NOT have a specific CC effect
    -- Uses AND logic for negation: [nomycc:stun/fear] = not stunned AND not feared
    nomycc = function(conditionals)
        -- If no specific CC type, check for NO loss-of-control on player
        if not conditionals.nomycc or (type(conditionals.nomycc) == "table" and table.getn(conditionals.nomycc) == 0) then
            return not CleveRoids.ValidateUnitAnyCrowdControl("player")
        end

        -- Check for absence of specific CC type(s) - AND logic
        return NegatedMulti(conditionals.nomycc, function(ccType)
            return not CleveRoids.ValidateUnitCC("player", ccType)
        end, conditionals, "nomycc")
    end,

    -- ========================================================================
    -- RESIST TRACKING CONDITIONALS
    -- ========================================================================

    -- [resisted] - Check if last spell was resisted by current target
    -- [resisted:type] - Check for specific resist type (full, partial)
    -- [resisted:full/partial] - OR logic for multiple types
    -- Examples: [resisted] [@target,resisted:full] [resisted:partial]
    resisted = function(conditionals)
        -- If no specific resist type, check for ANY resist on current target
        if not conditionals.resisted or
           conditionals.resisted == true or
           (type(conditionals.resisted) == "table" and table.getn(conditionals.resisted) == 0) then
            return CleveRoids.CheckResistState(nil)
        end

        -- Check for specific resist type(s) - OR logic
        return Multi(conditionals.resisted, function(resistType)
            return CleveRoids.CheckResistState(resistType)
        end, conditionals, "resisted")
    end,

    -- [noresisted] - Check if last spell was NOT resisted by current target
    -- [noresisted:type] - Check target does NOT have specific resist type
    -- [noresisted:full/partial] - AND logic: not full AND not partial
    noresisted = function(conditionals)
        -- If no specific resist type, check for NO resist on current target
        if not conditionals.noresisted or
           conditionals.noresisted == true or
           (type(conditionals.noresisted) == "table" and table.getn(conditionals.noresisted) == 0) then
            return not CleveRoids.CheckResistState(nil)
        end

        -- Check for absence of specific resist type(s) - AND logic
        return NegatedMulti(conditionals.noresisted, function(resistType)
            return not CleveRoids.CheckResistState(resistType)
        end, conditionals, "noresisted")
    end
}

-- =============================================================================
-- MULTISCAN SYSTEM
-- =============================================================================
-- [multiscan:priority] - Scan nearby enemies and find best target matching priority
-- Requires UnitXP_SP3 for enemy enumeration
-- Uses SuperWoW for soft-casting (CastSpellByName with GUID)

-- Raid mark indices (WoW API GetRaidTargetIndex values)
CleveRoids.RAID_MARKS = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, skull = 8,
}

-- Priority types for multiscan
-- String values = custom handling, number values = raid mark index
CleveRoids.MULTISCAN_PRIORITIES = {
    -- Distance-based (use UnitXP direct targeting where possible)
    nearest   = "nearest",
    farthest  = "farthest",
    -- Health percentage
    highesthp = "highesthp",
    lowesthp  = "lowesthp",
    -- Raw health value
    highestrawhp = "highestrawhp",
    lowestrawhp  = "lowestrawhp",
    -- Raid mark order (skull → cross → square → moon → triangle → diamond → circle → star)
    markorder = "markorder",
    -- Individual raid marks (direct unit reference via SuperWoW "mark#" tokens)
    skull    = 8, cross = 7, square = 6, moon = 5,
    triangle = 4, diamond = 3, circle = 2, star = 1,
}

-- Static conditionals that don't depend on target (checked before scanning)
CleveRoids.STATIC_CONDITIONALS = {
    group = true, nogroup = true,
    combat = true, nocombat = true,
    zone = true, subzone = true,
    instance = true, noinstance = true,
    stealth = true, nostealth = true,
    form = true, noform = true, stance = true, nostance = true,
    talent = true, notalent = true,
    equipped = true, noequipped = true,
    mod = true, nomod = true,
    btn = true,
    outdoors = true, indoors = true,
    swimming = true, noswimming = true,
    resting = true, noresting = true,
    flying = true, noflying = true,
    mounted = true, nomounted = true,
    vehicle = true, novehicle = true,
    bar = true,
}

--- Calculate score for a unit based on priority type
--- @param unit string Unit token or GUID
--- @param priority string Priority type (e.g., "nearest", "highesthp")
--- @param currentTargetGuid string|nil GUID of player's current target (exempt from combat check)
--- @param specifiedUnitGuid string|nil GUID of @unit specified in macro (also exempt from combat check)
--- @return number|nil Score (lower = better) or nil if invalid candidate
function CleveRoids.GetMultiscanScore(unit, priority, currentTargetGuid, specifiedUnitGuid)
    if not unit or not UnitExists(unit) then return nil end
    if UnitIsDeadOrGhost(unit) then return nil end

    -- Must be attackable
    if not UnitCanAttack("player", unit) then return nil end

    -- Combat check: must be in combat with player, UNLESS it's current target OR specified @unit
    local _, unitGuid = UnitExists(unit)
    local isCurrentTarget = currentTargetGuid and unitGuid == currentTargetGuid
    local isSpecifiedUnit = specifiedUnitGuid and unitGuid == specifiedUnitGuid
    if not isCurrentTarget and not isSpecifiedUnit and not UnitAffectingCombat(unit) then
        return nil
    end

    -- Calculate score based on priority
    if priority == "nearest" then
        if CleveRoids.hasUnitXP then
            local distance = UnitXP("distanceBetween", "player", unit)
            return distance or 9999
        end
        return 0  -- No distance info, treat as equal

    elseif priority == "farthest" then
        if CleveRoids.hasUnitXP then
            local distance = UnitXP("distanceBetween", "player", unit)
            return distance and -distance or -9999
        end
        return 0

    elseif priority == "highesthp" then
        local maxHp = UnitHealthMax(unit)
        if maxHp <= 0 then return nil end
        local hpPct = 100 * UnitHealth(unit) / maxHp
        return -hpPct  -- Negative so highest becomes lowest score

    elseif priority == "lowesthp" then
        local maxHp = UnitHealthMax(unit)
        if maxHp <= 0 then return nil end
        local hpPct = 100 * UnitHealth(unit) / maxHp
        return hpPct

    elseif priority == "highestrawhp" then
        local rawHp = UnitHealth(unit)
        return -rawHp  -- Negative so highest becomes lowest score

    elseif priority == "lowestrawhp" then
        local rawHp = UnitHealth(unit)
        return rawHp
    end

    return 0  -- Unknown priority, treat as equal
end

--- Check if a candidate passes all target-dependent conditionals
--- @param conditionals table The conditionals table
--- @param candidateUnit string Unit token or GUID to test
--- @return boolean True if candidate passes all conditionals
function CleveRoids.ValidateMultiscanCandidate(conditionals, candidateUnit)
    local originalTarget = conditionals.target
    conditionals.target = candidateUnit

    local passes = true
    for k, _ in pairs(conditionals) do
        -- Skip static conditionals (already checked) and metadata
        if not CleveRoids.ignoreKeywords[k] and not CleveRoids.STATIC_CONDITIONALS[k] then
            local fn = CleveRoids.Keywords[k]
            if fn and not fn(conditionals) then
                passes = false
                break
            end
        end
    end

    conditionals.target = originalTarget
    return passes
end

--- Check static conditionals before scanning
--- @param conditionals table The conditionals table
--- @return boolean True if all static conditionals pass
function CleveRoids.CheckStaticConditionals(conditionals)
    for k, _ in pairs(conditionals) do
        if CleveRoids.STATIC_CONDITIONALS[k] then
            local fn = CleveRoids.Keywords[k]
            if fn and not fn(conditionals) then
                return false
            end
        end
    end
    return true
end

--- Main multiscan resolution function
--- Scans enemies using UnitXP, finds best target matching priority and conditionals
--- @param conditionals table The conditionals table containing multiscan value
--- @param specifiedUnit string|nil The @unit specified in the macro (exempt from combat check)
--- @return string|nil GUID of best target, or nil if none found
function CleveRoids.ResolveMultiscanTarget(conditionals, specifiedUnit)
    -- Require UnitXP for enemy scanning
    if not CleveRoids.hasUnitXP then
        return nil
    end

    -- Parse priority from conditionals.multiscan
    local priority = nil
    if type(conditionals.multiscan) == "table" then
        priority = conditionals.multiscan[1]
    elseif type(conditionals.multiscan) == "string" then
        priority = conditionals.multiscan
    end

    if not priority then return nil end
    priority = string.lower(CleveRoids.Trim(priority))

    -- Validate priority type
    local priorityType = CleveRoids.MULTISCAN_PRIORITIES[priority]
    if not priorityType then
        CleveRoids.Print("|cffff0000[multiscan]|r Unknown priority: " .. priority)
        return nil
    end

    -- Check static conditionals first (group, combat, zone, etc.)
    if not CleveRoids.CheckStaticConditionals(conditionals) then
        return nil
    end

    -- Save current target for restoration and combat-check exemption
    local currentTargetGuid = nil
    if UnitExists("target") then
        local _, guid = UnitExists("target")
        currentTargetGuid = guid
    end

    -- Resolve specified @unit GUID (also exempt from combat check)
    local specifiedUnitGuid = nil
    if specifiedUnit and UnitExists(specifiedUnit) then
        local _, guid = UnitExists(specifiedUnit)
        specifiedUnitGuid = guid
    end

    -- Handle raid mark priorities (direct unit reference)
    if type(priorityType) == "number" then
        local markUnit = "mark" .. priorityType
        if UnitExists(markUnit) and UnitCanAttack("player", markUnit) then
            -- Validate against target-dependent conditionals
            if CleveRoids.ValidateMultiscanCandidate(conditionals, markUnit) then
                local _, guid = UnitExists(markUnit)
                return guid
            end
        end
        return nil  -- Raid mark not found or doesn't pass conditionals
    end

    -- Handle markorder priority (skull → cross → square → moon → triangle → diamond → circle → star)
    if priorityType == "markorder" then
        -- Iterate marks from skull (8) down to star (1) in standard kill order
        for markIndex = 8, 1, -1 do
            local markUnit = "mark" .. markIndex
            if UnitExists(markUnit) and UnitCanAttack("player", markUnit) then
                -- Validate against target-dependent conditionals
                if CleveRoids.ValidateMultiscanCandidate(conditionals, markUnit) then
                    local _, guid = UnitExists(markUnit)
                    return guid
                end
            end
        end
        return nil  -- No valid marked target found
    end

    -- Handle UnitXP direct targeting for simple priorities
    if priorityType == "nearest" then
        -- If no specified unit, use UnitXP's nearestEnemy directly for efficiency
        if not specifiedUnitGuid then
            local found = UnitXP("target", "nearestEnemy")
            if found and UnitExists("target") then
                local _, foundGuid = UnitExists("target")
                -- Restore original target
                if currentTargetGuid then
                    TargetUnit(currentTargetGuid)
                else
                    ClearTarget()
                end
                -- Validate the found target
                if CleveRoids.ValidateMultiscanCandidate(conditionals, foundGuid) then
                    return foundGuid
                end
            end
            -- Restore target if nearestEnemy failed
            if currentTargetGuid then
                TargetUnit(currentTargetGuid)
            else
                ClearTarget()
            end
            return nil
        end
        -- Fall through to custom scan if there's a specified unit to consider
    end

    if priorityType == "highesthp" then
        -- If no specified unit, try UnitXP's mostHP directly for efficiency
        if not specifiedUnitGuid then
            local found = UnitXP("target", "mostHP")
            if found and UnitExists("target") then
                local _, foundGuid = UnitExists("target")
                -- Restore original target
                if currentTargetGuid then
                    TargetUnit(currentTargetGuid)
                else
                    ClearTarget()
                end
                -- Validate the found target
                if CleveRoids.ValidateMultiscanCandidate(conditionals, foundGuid) then
                    return foundGuid
                end
            end
            -- Restore target if mostHP failed validation
            if currentTargetGuid then
                TargetUnit(currentTargetGuid)
            else
                ClearTarget()
            end
        end
        -- Fall through to custom scan if there's a specified unit or built-in didn't pass validation
    end

    -- Custom scan for complex priorities (lowesthp, highestrawhp, lowestrawhp, farthest)
    -- Also used as fallback if UnitXP direct targeting didn't pass validation
    local candidates = {}  -- { { guid = X, score = Y }, ... }
    local seenGuids = {}

    -- Helper to evaluate a candidate
    local function evaluateCandidate(unit)
        if not UnitExists(unit) then return end

        local _, guid = UnitExists(unit)
        if not guid or seenGuids[guid] then return end
        seenGuids[guid] = true

        local score = CleveRoids.GetMultiscanScore(unit, priorityType, currentTargetGuid, specifiedUnitGuid)
        if not score then return end

        -- Validate against target-dependent conditionals
        if CleveRoids.ValidateMultiscanCandidate(conditionals, guid) then
            table.insert(candidates, { guid = guid, score = score })
        end
    end

    -- Always consider current target (exempt from combat check via GetMultiscanScore)
    if currentTargetGuid then
        evaluateCandidate("target")
    end

    -- Also consider specified @unit (exempt from combat check via GetMultiscanScore)
    if specifiedUnitGuid and specifiedUnitGuid ~= currentTargetGuid then
        evaluateCandidate(specifiedUnit)
    end

    -- Scan via UnitXP enemy iteration
    local firstGuid = nil
    local maxIterations = 50

    for i = 1, maxIterations do
        local found = UnitXP("target", "nextEnemyConsideringDistance")
        if not found then break end

        if not UnitExists("target") then break end
        local _, currentGuid = UnitExists("target")
        if not currentGuid then break end

        if firstGuid == nil then
            firstGuid = currentGuid
        elseif currentGuid == firstGuid then
            break  -- Completed full cycle
        end

        evaluateCandidate("target")
    end

    -- Restore original target
    if currentTargetGuid then
        TargetUnit(currentTargetGuid)
    else
        ClearTarget()
    end

    -- Find best candidate (lowest score wins)
    if table.getn(candidates) == 0 then
        return nil
    end

    table.sort(candidates, function(a, b) return a.score < b.score end)
    return candidates[1].guid
end
