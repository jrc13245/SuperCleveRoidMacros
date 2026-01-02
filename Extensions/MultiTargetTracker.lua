--[[
    Multi-Target Debuff Tracker Extension
    Tracks player's debuffs across multiple enemy targets
    Displays: Target indicator, raid icon, health bar with name, debuff icons with timers

    Styled to match Cursive/ShaguScan UI
]]

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("MultiTargetTracker")

-- ============================================================================
-- Configuration
-- ============================================================================

local MAX_TRACKED_TARGETS = 15
local MAX_ICONS_PER_ROW = 8
local UPDATE_THROTTLE = 0.1  -- 10 Hz update rate

-- Layout dimensions (Cursive-style)
local CONFIG = {
    -- Bar dimensions
    barHeight = 20,
    barSpacing = 2,

    -- First section (target indicator + raid icon)
    targetIndicatorSize = 8,
    raidIconSize = 16,

    -- Second section (health bar)
    healthBarWidth = 140,

    -- Third section (debuff icons)
    debuffIconSize = 20,
    debuffIconSpacing = 2,

    -- General
    padding = 2,
    titleHeight = 16,
    textSize = 10,
}

-- Tooltip-style backdrop (matching Cursive)
local BACKDROP_BORDER = {
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

local BACKDROP_BACKGROUND = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true, tileSize = 16,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

-- Colors
local COLORS = {
    borderNormal = { 0.2, 0.2, 0.2, 1 },
    borderHover = { 1, 1, 1, 1 },
    borderCombat = { 0.8, 0.2, 0.2, 1 },
    healthDefault = { 1, 0.8, 0.2, 1 },  -- Gold/yellow
    timerNormal = { 1, 1, 1 },
    timerExpiring = { 1, 0.2, 0.2 },     -- Red when <3s
    nameText = { 1, 1, 1, 1 },
    titleText = { 1, 0.82, 0, 1 },       -- Gold
}

-- ============================================================================
-- Local State
-- ============================================================================

local trackedTargets = {}      -- Key: normalized GUID, Value: { guid, name, addedTime }
local trackedOrder = {}        -- Array of GUIDs in order added (for FIFO removal)
local targetRows = {}          -- Pool of row frames
local mainFrame = nil
local contentFrame = nil
local lastUpdate = 0
local isFrameVisible = false
local isUnlocked = false
local lib = nil                -- Reference to CleveRoids.libdebuff

-- Debug flag for MultiTargetTracker
local MTT_DEBUG = false

-- Cache for enemy status
local confirmedEnemies = {}

-- Cache for player's known spells (populated on load)
local playerKnownSpells = {}

-- Build cache of player's known spell IDs by scanning spellbook
local function BuildPlayerSpellCache()
    playerKnownSpells = {}
    local spellIndex = 1
    while true do
        local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)
        if not spellName then break end

        -- Get the spell ID using SpellInfo (SuperWoW)
        if SpellInfo then
            local id = CleveRoids.Spells and CleveRoids.Spells[spellName]
            if id then
                playerKnownSpells[id] = true
            end
        end
        spellIndex = spellIndex + 1
    end

    -- Also check CleveRoids.Spells directly (more reliable)
    if CleveRoids.Spells then
        for name, id in pairs(CleveRoids.Spells) do
            playerKnownSpells[id] = true
        end
    end
end

-- Check if player can cast a spell (has it in spellbook)
local function PlayerCanCastSpell(spellID)
    if not spellID then return false end

    -- Check our cache first
    if playerKnownSpells[spellID] then
        return true
    end

    -- For spells not in cache, check if base spell name is known
    -- (handles different ranks of the same spell)
    if SpellInfo then
        local spellName = SpellInfo(spellID)
        if spellName and CleveRoids.Spells then
            -- Strip rank suffix for comparison
            local baseName = string.gsub(spellName, "%s*%(%s*Rank%s+%d+%s*%)", "")
            for knownName, knownID in pairs(CleveRoids.Spells) do
                local knownBase = string.gsub(knownName, "%s*%(%s*Rank%s+%d+%s*%)", "")
                if knownBase == baseName then
                    return true
                end
            end
        end
    end

    return false
end

-- ============================================================================
-- Player Cast Tracking (Clean Implementation)
-- ============================================================================
--
-- This tracking system uses Nampower's SPELL_CAST_EVENT which ONLY fires for
-- the local player's casts. This eliminates the GUID comparison issues between
-- Nampower's internal GUID system and SuperWoW's GUID system.
--
-- Data Flow:
-- 1. SPELL_CAST_EVENT fires → Record pending cast with target
-- 2. DEBUFF_ADDED_OTHER fires → Match against pending casts
-- 3. If match → Mark as player's debuff, add to tracker
--
-- ============================================================================

-- Pending casts waiting for debuff confirmation
-- Key: "spellID_normalizedTargetGUID", Value: { time, spellID, targetGuid, targetName }
local pendingCasts = {}
local CAST_CONFIRMATION_WINDOW = 3.0  -- Time window to match cast with debuff application

-- AoE debuff spells - these hit multiple targets, so pending cast tracking
-- uses spell-only keys instead of spell+target keys
local AOE_DEBUFF_SPELLS = {
    -- Warrior - Thunder Clap
    [6343] = true,   -- Thunder Clap (Rank 1)
    [8198] = true,   -- Thunder Clap (Rank 2)
    [8205] = true,   -- Thunder Clap (Rank 3)
    [11580] = true,  -- Thunder Clap (Rank 4)
    [11581] = true,  -- Thunder Clap (Rank 5)
    -- Warrior - Challenging Shout (AoE taunt)
    [1161] = true,   -- Challenging Shout
    -- Druid - Demoralizing Roar (AoE debuff)
    [99] = true,     -- Demoralizing Roar (Rank 1)
    [1735] = true,   -- Demoralizing Roar (Rank 2)
    [9490] = true,   -- Demoralizing Roar (Rank 3)
    [9747] = true,   -- Demoralizing Roar (Rank 4)
    [9898] = true,   -- Demoralizing Roar (Rank 5)
    -- Warrior - Demoralizing Shout (AoE debuff)
    [1160] = true,   -- Demoralizing Shout (Rank 1)
    [6190] = true,   -- Demoralizing Shout (Rank 2)
    [11554] = true,  -- Demoralizing Shout (Rank 3)
    [11555] = true,  -- Demoralizing Shout (Rank 4)
    [11556] = true,  -- Demoralizing Shout (Rank 5)
    -- Warlock - Howl of Terror (AoE fear)
    [5484] = true,   -- Howl of Terror (Rank 1)
    [17928] = true,  -- Howl of Terror (Rank 2)
    -- Priest - Psychic Scream (AoE fear)
    [8122] = true,   -- Psychic Scream (Rank 1)
    [8124] = true,   -- Psychic Scream (Rank 2)
    [10888] = true,  -- Psychic Scream (Rank 3)
    [10890] = true,  -- Psychic Scream (Rank 4)
}

-- Pending AoE casts - separate table for AoE spells that uses spell-only keys
-- Key: spellID, Value: { time, spellID }
local pendingAoECasts = {}

-- Excluded spells - abilities that fire SPELL_CAST_EVENT but aren't debuffs
-- These are filtered out to reduce debug spam
local EXCLUDED_SPELLS = {
    -- Direct damage abilities (not debuffs)
    [23881] = true,  -- Bloodthirst
    [23892] = true,  -- Bloodthirst (higher rank)
    [23893] = true,  -- Bloodthirst
    [23894] = true,  -- Bloodthirst
    [29707] = true,  -- Heroic Strike (various ranks)
    [11567] = true,  -- Heroic Strike
    [11566] = true,  -- Heroic Strike
    [11565] = true,  -- Heroic Strike
    [1608] = true,   -- Heroic Strike
    [285] = true,    -- Heroic Strike
    [284] = true,    -- Heroic Strike
    [78] = true,     -- Heroic Strike (Rank 1)

    -- Self-buffs (not enemy debuffs)
    [12970] = true,  -- Flurry (self-buff)

}

-- Non-stacking debuffs - don't show stack count in UI for these
local NON_STACKING_DEBUFFS = {
    -- Thunderfury (both effects)
    [21992] = true,  -- Thunderfury main
    [27648] = true,  -- Thunderfury chain

    -- Warrior debuffs that don't stack
    [355] = true,    -- Taunt
    [1161] = true,   -- Challenging Shout
}

-- Proc debuffs and special spells that need UNIT_CASTEVENT tracking
-- (SPELL_CAST_EVENT may not provide target GUID for these)
local PROC_DEBUFFS = {
    -- Thunderfury, Blessed Blade of the Windseeker
    [21992] = true,  -- Thunderfury (Nature damage + resistance reduction)
    [27648] = true,  -- Thunderfury chain effect

    -- Warrior - Thunder Clap (AoE spell - cast ID = debuff ID)
    [6343] = true,   -- Thunder Clap (Rank 1)
    [8198] = true,   -- Thunder Clap (Rank 2)
    [8205] = true,   -- Thunder Clap (Rank 3)
    [11580] = true,  -- Thunder Clap (Rank 4)
    [11581] = true,  -- Thunder Clap (Rank 5)

    -- Warrior - Taunts (SPELL_CAST_EVENT doesn't provide target GUID)
    [355] = true,    -- Taunt
    [1161] = true,   -- Challenging Shout
    [694] = true,    -- Mocking Blow (Rank 1)
    [7400] = true,   -- Mocking Blow (Rank 2)
    [7402] = true,   -- Mocking Blow (Rank 3)
    [20559] = true,  -- Mocking Blow (Rank 4)
    [20560] = true,  -- Mocking Blow (Rank 5)
}

-- Duration cache from AURA_CAST_ON_OTHER events
-- Key: spellID, Value: duration in seconds
local auraCastDurations = {}

-- ============================================================================
-- Duration Lookup System
-- Priority: AURA_CAST cache → lib tables → GetSpellRec → default
-- ============================================================================

-- SpellDuration.dbc lookup table (common duration indices)
-- Format: durationIndex = baseDurationMs
local SPELL_DURATION_INDEX = {
    [1] = 0,        -- Instant
    [3] = 10000,    -- 10 seconds
    [4] = 15000,    -- 15 seconds
    [5] = 30000,    -- 30 seconds
    [6] = 60000,    -- 1 minute
    [7] = 120000,   -- 2 minutes
    [8] = 180000,   -- 3 minutes
    [9] = 300000,   -- 5 minutes
    [11] = 600000,  -- 10 minutes
    [12] = 900000,  -- 15 minutes
    [21] = 6000,    -- 6 seconds
    [22] = 12000,   -- 12 seconds
    [28] = 20000,   -- 20 seconds
    [29] = 45000,   -- 45 seconds
    [35] = 8000,    -- 8 seconds
    [36] = 18000,   -- 18 seconds
    [37] = 24000,   -- 24 seconds
    [39] = 21000,   -- 21 seconds
    [85] = 9000,    -- 9 seconds
    [557] = 22000,  -- 22 seconds (Thunder Clap R4)
    [558] = 14000,  -- 14 seconds (Thunder Clap R2)
}

-- Get duration for a spell using all available sources
local function GetSpellDuration(spellId)
    local lib = CleveRoids.libdebuff

    -- 1. Check AURA_CAST cache (most accurate, includes modifiers)
    if auraCastDurations[spellId] then
        return auraCastDurations[spellId]
    end

    -- 2. Check libdebuff tables
    if lib then
        if lib.personalDebuffs and lib.personalDebuffs[spellId] then
            return lib.personalDebuffs[spellId]
        end
        if lib.sharedDebuffs and lib.sharedDebuffs[spellId] then
            return lib.sharedDebuffs[spellId]
        end
        if lib.durations and lib.durations[spellId] then
            return lib.durations[spellId]
        end
    end

    -- 3. Try GetSpellRec from Nampower
    if GetSpellRec then
        local spellRec = GetSpellRec(spellId)
        if spellRec and spellRec.durationIndex then
            local durationMs = SPELL_DURATION_INDEX[spellRec.durationIndex]
            if durationMs then
                return durationMs / 1000
            end
        end
    end

    -- 4. Default fallback
    return 30
end

-- Check if a spell is a known debuff (should be tracked)
local function IsKnownDebuffSpell(spellId)
    -- FIRST: Check exclusion list (passive procs, abilities we don't want)
    if EXCLUDED_SPELLS[spellId] then
        return false
    end

    local lib = CleveRoids.libdebuff

    -- Check our tracking tables
    if PROC_DEBUFFS[spellId] then return true end
    if AOE_DEBUFF_SPELLS[spellId] then return true end

    -- Check libdebuff tables
    if lib then
        if lib.personalDebuffs and lib.personalDebuffs[spellId] then return true end
        if lib.sharedDebuffs and lib.sharedDebuffs[spellId] then return true end
        if lib.durations and lib.durations[spellId] then return true end
    end

    return false
end

-- Forward declaration for ResolveTargetName (defined after GetUnitForGUID)
local ResolveTargetName

-- Helper to create a cast key from spell and target
local function MakeCastKey(spellID, targetGuid)
    local normalizedGuid = CleveRoids.NormalizeGUID(targetGuid)
    if normalizedGuid then
        return tostring(spellID) .. "_" .. normalizedGuid
    end
    return nil
end

-- Record a player cast (called from SPELL_CAST_EVENT)
local function RecordPlayerCast(spellID, targetGuid, targetName)
    if not spellID then return end

    local key = MakeCastKey(spellID, targetGuid)
    if key then
        pendingCasts[key] = {
            time = GetTime(),
            spellID = spellID,
            targetGuid = CleveRoids.NormalizeGUID(targetGuid),
            targetName = targetName or "Unknown"
        }
    end

    -- For AoE spells, also record in the AoE table (spell-only key)
    if AOE_DEBUFF_SPELLS[spellID] then
        pendingAoECasts[spellID] = {
            time = GetTime(),
            spellID = spellID
        }
    end

    if MTT_DEBUG then
        local spellName = SpellInfo and SpellInfo(spellID) or "?"
        local isAoE = AOE_DEBUFF_SPELLS[spellID] and " (AoE)" or ""
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff00ffff[MTT]|r Cast: %s on %s%s",
            spellName, targetName or "?", isAoE))
    end
end

-- Check if we have a pending cast for this spell+target
local function GetPendingCast(spellID, targetGuid)
    -- First check target-specific pending casts
    local key = MakeCastKey(spellID, targetGuid)
    if key then
        local pending = pendingCasts[key]
        if pending and (GetTime() - pending.time) <= CAST_CONFIRMATION_WINDOW then
            return pending
        end
    end

    -- For AoE spells, also check the AoE pending cast table
    if AOE_DEBUFF_SPELLS[spellID] then
        local aoePending = pendingAoECasts[spellID]
        if aoePending and (GetTime() - aoePending.time) <= CAST_CONFIRMATION_WINDOW then
            return aoePending
        end
    end

    return nil
end

-- Consume (remove) a pending cast after confirmation
local function ConsumePendingCast(spellID, targetGuid)
    local key = MakeCastKey(spellID, targetGuid)
    if key then
        pendingCasts[key] = nil
    end
end

-- Cleanup old pending casts
local function CleanupPendingCasts()
    local now = GetTime()
    local expireTime = CAST_CONFIRMATION_WINDOW * 2

    -- Cleanup target-specific pending casts
    for key, data in pairs(pendingCasts) do
        if (now - data.time) > expireTime then
            pendingCasts[key] = nil
        end
    end

    -- Cleanup AoE pending casts
    for spellID, data in pairs(pendingAoECasts) do
        if (now - data.time) > expireTime then
            pendingAoECasts[spellID] = nil
        end
    end
end

-- Helper function to check if a caster GUID matches the player
-- The caster field might be the string "player" (set by us) or the actual player GUID (from Nampower)
local function IsCasterPlayer(casterGuid)
    if not casterGuid then return false end
    if casterGuid == "player" then return true end

    -- Compare against actual player GUID
    local _, playerGuid = UnitExists("player")
    if playerGuid then
        return CleveRoids.GUIDsMatch(casterGuid, playerGuid)
    end
    return false
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

local function FormatTimer(seconds)
    if seconds <= 0 then
        return ""
    elseif seconds < 10 then
        return string.format("%.1f", seconds)
    elseif seconds < 60 then
        return string.format("%d", seconds)
    else
        local mins = math.floor(seconds / 60)
        local secs = math.mod(seconds, 60)
        return string.format("%d:%02d", mins, secs)
    end
end

local function FormatHealth(hp)
    if not hp then return "?" end
    if hp >= 1000000 then
        return string.format("%.1fm", hp / 1000000)
    elseif hp >= 1000 then
        return string.format("%.1fk", hp / 1000)
    else
        return tostring(hp)
    end
end

local function TruncateName(name, maxLen)
    if not name then return "?" end
    if string.len(name) <= maxLen then
        return name
    end
    return string.sub(name, 1, maxLen - 2) .. ".."
end

local function GetTimerColor(seconds)
    if seconds < 3 then
        return COLORS.timerExpiring[1], COLORS.timerExpiring[2], COLORS.timerExpiring[3]
    else
        return COLORS.timerNormal[1], COLORS.timerNormal[2], COLORS.timerNormal[3]
    end
end

-- Check if focus unit is available
local hasFocusUnit = false
if pcall(function() return UnitExists("focus") end) then
    hasFocusUnit = true
end

local function CheckUnit(unit)
    local exists, unitGUID = UnitExists(unit)
    if exists and unitGUID then
        return true, unitGUID
    end
    return false, nil
end

-- Calculate section widths
local function GetFirstSectionWidth()
    return CONFIG.targetIndicatorSize + CONFIG.raidIconSize + CONFIG.padding
end

local function GetSecondSectionWidth()
    return CONFIG.healthBarWidth + CONFIG.padding
end

local function GetThirdSectionWidth()
    return MAX_ICONS_PER_ROW * (CONFIG.debuffIconSize + CONFIG.debuffIconSpacing)
end

local function GetBarWidth()
    return GetFirstSectionWidth() + GetSecondSectionWidth() + GetThirdSectionWidth() + CONFIG.padding * 2
end

-- ============================================================================
-- GUID Health/Unit Lookup
-- ============================================================================

local function GetUnitForGUID(guid)
    local priorityUnits = { "target", "mouseover", "targettarget", "pettarget" }
    if hasFocusUnit then
        table.insert(priorityUnits, "focus")
        table.insert(priorityUnits, "focustarget")
    end

    for i = 1, table.getn(priorityUnits) do
        local unit = priorityUnits[i]
        local exists, unitGUID = CheckUnit(unit)
        if exists and unitGUID then
            if CleveRoids.NormalizeGUID(unitGUID) == guid then
                return unit
            end
        end
    end

    -- Check party targets
    for i = 1, 4 do
        local unit = "party" .. i .. "target"
        local exists, unitGUID = CheckUnit(unit)
        if exists and unitGUID then
            if CleveRoids.NormalizeGUID(unitGUID) == guid then
                return unit
            end
        end
    end

    -- Check raid targets
    for i = 1, 40 do
        local unit = "raid" .. i .. "target"
        local exists, unitGUID = CheckUnit(unit)
        if exists and unitGUID then
            if CleveRoids.NormalizeGUID(unitGUID) == guid then
                return unit
            end
        end
    end

    return nil
end

-- Helper function to resolve target name from GUID using multiple methods
-- (Defined here after GetUnitForGUID is available)
ResolveTargetName = function(guid)
    if not guid then return nil end

    -- Method 1: Try UnitName directly with GUID (SuperWoW may support this)
    local name = UnitName(guid)
    if name and name ~= "" and name ~= "Unknown" then
        return name
    end

    -- Method 2: Try to find a unit token for this GUID and use that
    local unit = GetUnitForGUID(CleveRoids.NormalizeGUID(guid))
    if unit then
        name = UnitName(unit)
        if name and name ~= "" then
            return name
        end
    end

    -- Method 3: Check libdebuff's GUID-to-name cache
    if lib and lib.guidToName then
        local normalizedGuid = CleveRoids.NormalizeGUID(guid)
        if normalizedGuid and lib.guidToName[normalizedGuid] then
            return lib.guidToName[normalizedGuid]
        end
    end

    -- Method 4: Check our tracked targets (we might have cached the name before)
    local normalizedGuid = CleveRoids.NormalizeGUID(guid)
    if normalizedGuid and trackedTargets[normalizedGuid] then
        return trackedTargets[normalizedGuid].name
    end

    return nil  -- Could not resolve name
end

local function GetHealthForGUID(guid)
    -- SuperWoW allows UnitHealth/UnitHealthMax to take GUIDs directly
    if CleveRoids.hasSuperwow and guid then
        local health = UnitHealth(guid)
        local maxHealth = UnitHealthMax(guid)
        if health and maxHealth and maxHealth > 0 then
            return health, maxHealth, nil
        end
    end

    -- Fallback: Check via unit lookup
    local unit = GetUnitForGUID(guid)
    if unit then
        local health = UnitHealth(unit)
        local maxHealth = UnitHealthMax(unit)
        if maxHealth and maxHealth > 0 then
            return health, maxHealth, unit
        end
    end
    return nil, nil, nil
end

local function IsGUIDDead(guid)
    -- SuperWoW allows UnitIsDead to take a GUID directly
    if CleveRoids.hasSuperwow and guid then
        local isDead = UnitIsDead(guid)
        if isDead then
            return true
        end
    end

    -- Fallback: Check via unit lookup
    local unit = GetUnitForGUID(guid)
    if unit then
        return UnitIsDead(unit)
    end

    -- If we can't find the unit, assume not dead (will be pruned when debuffs expire)
    return false
end

local function IsEnemyGUID(guid)
    if not guid then return false, nil end

    -- Check if this is the player's GUID
    local _, playerGuid = UnitExists("player")
    if playerGuid and CleveRoids.GUIDsMatch(playerGuid, guid) then
        return false, "player"
    end

    local unit = GetUnitForGUID(guid)
    if unit then
        -- Check if it's the player or a friendly unit
        if UnitIsUnit(unit, "player") then
            return false, unit
        end
        local isEnemy = UnitIsEnemy("player", unit) or UnitCanAttack("player", unit)
        return isEnemy, unit
    end

    return nil, nil  -- Unknown
end

local function GetSpellTexture(spellID)
    if SpellInfo then
        local name, rank, icon = SpellInfo(spellID)
        return icon
    end
    return nil
end

-- ============================================================================
-- Target Management
-- ============================================================================

local function AddTrackedTarget(guid, name, skipEnemyCheck, rawGuid)
    if not guid then return end

    -- Keep raw GUID before normalizing (for API calls like UnitDebuff)
    local originalGuid = rawGuid or guid
    guid = CleveRoids.NormalizeGUID(guid)
    if not guid then return end

    -- Already tracking?
    if trackedTargets[guid] then
        if name then
            trackedTargets[guid].name = name
        end
        -- Update raw GUID if provided (might have better format)
        if rawGuid and rawGuid ~= trackedTargets[guid].rawGuid then
            trackedTargets[guid].rawGuid = rawGuid
        end
        return
    end

    -- Enemy check
    if not skipEnemyCheck then
        if confirmedEnemies[guid] then
            -- Already confirmed
        else
            local isEnemy, unit = IsEnemyGUID(guid)
            if isEnemy == false then
                return
            elseif isEnemy == true then
                confirmedEnemies[guid] = true
            else
                -- Assume enemy when casting debuffs
                confirmedEnemies[guid] = true
            end
        end
    end

    -- Enforce max limit (FIFO)
    while table.getn(trackedOrder) >= MAX_TRACKED_TARGETS do
        local oldestGUID = trackedOrder[1]
        table.remove(trackedOrder, 1)
        trackedTargets[oldestGUID] = nil
    end

    -- Add new target
    trackedTargets[guid] = {
        guid = guid,
        rawGuid = originalGuid,  -- Store raw GUID for API calls like UnitDebuff
        name = name or (lib and lib.guidToName and lib.guidToName[guid]) or "Unknown",
        addedTime = GetTime(),
    }
    table.insert(trackedOrder, guid)

    -- Show frame
    if mainFrame and not isFrameVisible then
        mainFrame:Show()
        isFrameVisible = true
    end
end

local function RemoveTrackedTarget(guid)
    if not guid then return end

    trackedTargets[guid] = nil
    confirmedEnemies[guid] = nil

    for i = table.getn(trackedOrder), 1, -1 do
        if trackedOrder[i] == guid then
            table.remove(trackedOrder, i)
            break
        end
    end

    if table.getn(trackedOrder) == 0 and mainFrame and isFrameVisible and not isUnlocked then
        mainFrame:Hide()
        isFrameVisible = false
    end
end

local function GetActivePlayerDebuffs(guid)
    if not lib or not lib.objects or not lib.objects[guid] then
        return nil, 0
    end

    local debuffs = {}
    local count = 0
    local now = GetTime()

    for spellID, rec in pairs(lib.objects[guid]) do
        -- FIRST: Only show debuffs we actually want to track
        -- This filters out abilities like Bloodthirst, Master Strike, Deep Wounds (talent proc)
        if not IsKnownDebuffSpell(spellID) then
            -- Skip unknown spells entirely
        else
            -- Check if this debuff should be shown as player's
            local isPlayerDebuff = false

            if IsCasterPlayer(rec.caster) then
                -- Explicitly marked as player
                isPlayerDebuff = true
            elseif PROC_DEBUFFS[spellID] then
                -- Proc debuffs (items/talents) are always from the player
                isPlayerDebuff = true
            elseif lib.sharedDebuffs and lib.sharedDebuffs[spellID] then
                -- For shared debuffs, include if caster is player OR we have a pending cast
                if IsCasterPlayer(rec.caster) then
                    isPlayerDebuff = true
                elseif GetPendingCast(spellID, guid) then
                    isPlayerDebuff = true
                elseif rec.caster == nil and PlayerCanCastSpell(spellID) then
                    -- Shared debuff with no caster - only claim if player can cast this spell
                    -- This prevents showing other players' Sunder Armor on a Druid, etc.
                    isPlayerDebuff = true
                end
            end

            if isPlayerDebuff then
                if rec.start and rec.duration then
                    local remaining = rec.duration + rec.start - now
                    if remaining > 0 then
                        count = count + 1
                        debuffs[count] = {
                            spellID = spellID,
                            remaining = remaining,
                            duration = rec.duration,
                            stacks = rec.stacks or 0,
                        }
                    end
                end
            end
        end  -- end IsKnownDebuffSpell check
    end

    return debuffs, count
end

local function IsGUIDInCombat(guid)
    -- SuperWoW allows UnitAffectingCombat to take a GUID directly
    if CleveRoids.hasSuperwow and guid then
        local inCombat = UnitAffectingCombat(guid)
        if inCombat then
            return true
        end
    end

    -- Fallback: Check via unit lookup
    local unit = GetUnitForGUID(guid)
    if unit then
        return UnitAffectingCombat(unit)
    end

    return false
end

local function CheckAndPruneTargets()
    local toRemove = {}
    local playerOutOfCombat = not UnitAffectingCombat("player")

    for guid, info in pairs(trackedTargets) do
        -- Check if dead - always remove dead targets
        if IsGUIDDead(guid) then
            table.insert(toRemove, guid)
        else
            -- Check if no active debuffs
            local debuffs, count = GetActivePlayerDebuffs(guid)
            if count == 0 then
                -- Remove if target out of combat OR player out of combat
                if not IsGUIDInCombat(guid) or playerOutOfCombat then
                    table.insert(toRemove, guid)
                end
            end
        end
    end

    for i = 1, table.getn(toRemove) do
        RemoveTrackedTarget(toRemove[i])
    end
end

local function ClearAllTargets()
    trackedTargets = {}
    trackedOrder = {}
    confirmedEnemies = {}

    if mainFrame and isFrameVisible then
        mainFrame:Hide()
        isFrameVisible = false
    end

    CleveRoids.Print("Multi-Target Tracker: Cleared all targets")
end

-- Forward declarations
local ScanCombatTargets
local ScanAllTrackedDebuffs

-- ============================================================================
-- UI Creation (Cursive-style)
-- ============================================================================

local function CreateDebuffIcon(parent, index)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetWidth(CONFIG.debuffIconSize)
    icon:SetHeight(CONFIG.debuffIconSize)

    -- Icon texture
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
    icon.texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Timer text (centered on icon like Cursive)
    icon.timer = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    icon.timer:SetFont(STANDARD_TEXT_FONT, CONFIG.textSize, "OUTLINE")
    icon.timer:SetTextColor(1, 1, 1)
    icon.timer:SetAllPoints(icon)

    -- Stack count (bottom right)
    icon.stacks = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon.stacks:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icon.stacks:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    icon.stacks:SetTextColor(1, 1, 1, 1)

    icon:Hide()
    return icon
end

local function CreateTargetRow(parent, index)
    local barWidth = GetBarWidth()
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(barWidth)
    row:SetHeight(CONFIG.barHeight)
    row.hover = false

    -- ========================================
    -- First Section: Target Indicator + Raid Icon
    -- ========================================
    local firstSection = CreateFrame("Frame", nil, row)
    firstSection:SetPoint("LEFT", row, "LEFT", 0, 0)
    firstSection:SetWidth(GetFirstSectionWidth())
    firstSection:SetHeight(CONFIG.barHeight)
    row.firstSection = firstSection

    -- Target indicator arrow (shows when this unit is targeted)
    local targetIndicator = firstSection:CreateTexture(nil, "OVERLAY")
    targetIndicator:SetWidth(CONFIG.targetIndicatorSize)
    targetIndicator:SetHeight(CONFIG.targetIndicatorSize)
    targetIndicator:SetPoint("LEFT", firstSection, "LEFT", 0, 0)
    -- Use play button triangle as arrow pointing right (towards the target)
    targetIndicator:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    targetIndicator:SetVertexColor(1, 1, 0, 1)  -- Yellow for visibility
    targetIndicator:Hide()
    row.targetIndicator = targetIndicator

    -- Raid icon
    local raidIcon = firstSection:CreateTexture(nil, "OVERLAY")
    raidIcon:SetWidth(CONFIG.raidIconSize)
    raidIcon:SetHeight(CONFIG.raidIconSize)
    raidIcon:SetPoint("RIGHT", firstSection, "RIGHT", 0, 0)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:Hide()
    row.raidIcon = raidIcon

    -- ========================================
    -- Second Section: Health Bar (clickable)
    -- ========================================
    local secondSection = CreateFrame("Button", nil, row)
    secondSection:SetPoint("LEFT", firstSection, "RIGHT", 0, 0)
    secondSection:SetWidth(GetSecondSectionWidth())
    secondSection:SetHeight(CONFIG.barHeight)
    secondSection.parent = row
    row.secondSection = secondSection

    -- Health bar with backdrop
    local healthBar = CreateFrame("StatusBar", nil, secondSection)
    healthBar:SetPoint("LEFT", secondSection, "LEFT", CONFIG.padding, 0)
    healthBar:SetWidth(CONFIG.healthBarWidth)
    healthBar:SetHeight(CONFIG.barHeight - 4)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(COLORS.healthDefault[1], COLORS.healthDefault[2], COLORS.healthDefault[3], 1)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    row.healthBar = healthBar

    -- Health bar background
    healthBar:SetBackdrop(BACKDROP_BACKGROUND)
    healthBar:SetBackdropColor(0, 0, 0, 0.8)

    -- Health bar border
    local healthBorder = CreateFrame("Frame", nil, healthBar)
    healthBorder:SetBackdrop(BACKDROP_BORDER)
    healthBorder:SetBackdropBorderColor(COLORS.borderNormal[1], COLORS.borderNormal[2], COLORS.borderNormal[3], 1)
    healthBorder:SetPoint("TOPLEFT", healthBar, "TOPLEFT", -2, 2)
    healthBorder:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 2, -2)
    row.healthBorder = healthBorder

    -- Name text (on health bar)
    local nameText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    nameText:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 2, -2)
    nameText:SetWidth(CONFIG.healthBarWidth - 35)
    nameText:SetHeight(CONFIG.barHeight - 4)
    nameText:SetFont(STANDARD_TEXT_FONT, CONFIG.textSize, "THINOUTLINE")
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(COLORS.nameText[1], COLORS.nameText[2], COLORS.nameText[3], 1)
    row.nameText = nameText

    -- HP text (right side of health bar)
    local hpText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    hpText:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", -2, -2)
    hpText:SetWidth(30)
    hpText:SetHeight(CONFIG.barHeight - 4)
    hpText:SetFont(STANDARD_TEXT_FONT, CONFIG.textSize, "THINOUTLINE")
    hpText:SetJustifyH("RIGHT")
    row.hpText = hpText

    -- Click handlers for targeting
    secondSection:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    secondSection:SetScript("OnClick", function()
        if this.parent.guid then
            if arg1 == "LeftButton" then
                TargetUnit(this.parent.guid)
            elseif arg1 == "RightButton" then
                RemoveTrackedTarget(this.parent.guid)
            end
        end
    end)

    -- Hover effects (white border on hover like Cursive)
    secondSection:SetScript("OnEnter", function()
        this.parent.hover = true
        if this.parent.healthBorder then
            this.parent.healthBorder:SetBackdropBorderColor(COLORS.borderHover[1], COLORS.borderHover[2], COLORS.borderHover[3], 1)
        end
        -- Show tooltip
        if this.parent.guid then
            GameTooltip_SetDefaultAnchor(GameTooltip, this)
            GameTooltip:SetUnit(this.parent.guid)
            GameTooltip:Show()
        end
    end)

    secondSection:SetScript("OnLeave", function()
        this.parent.hover = false
        GameTooltip:Hide()
    end)

    -- ========================================
    -- Third Section: Debuff Icons
    -- ========================================
    local thirdSection = CreateFrame("Frame", nil, row)
    thirdSection:SetPoint("LEFT", secondSection, "RIGHT", 0, 0)
    thirdSection:SetWidth(GetThirdSectionWidth())
    thirdSection:SetHeight(CONFIG.barHeight)
    row.thirdSection = thirdSection

    -- Create debuff icon pool
    row.icons = {}
    for i = 1, MAX_ICONS_PER_ROW do
        row.icons[i] = CreateDebuffIcon(thirdSection, i)
        local xOffset = (i - 1) * (CONFIG.debuffIconSize + CONFIG.debuffIconSpacing)
        row.icons[i]:SetPoint("LEFT", thirdSection, "LEFT", xOffset, 0)
    end

    row:Hide()
    return row
end

local function CreateMainFrame()
    local barWidth = GetBarWidth()

    local frame = CreateFrame("Frame", "CleveRoidsMultiTargetFrame", UIParent)
    frame:SetWidth(barWidth + 8)
    frame:SetHeight(CONFIG.titleHeight + 50)
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    -- No background - transparent frame
    frame:SetBackdrop(nil)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    titleBar:SetHeight(CONFIG.titleHeight)
    titleBar:EnableMouse(true)
    frame.titleBar = titleBar

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 4, 0)
    titleText:SetFont(STANDARD_TEXT_FONT, 11, "THINOUTLINE")
    titleText:SetText("Debuff Tracker")
    titleText:SetTextColor(COLORS.titleText[1], COLORS.titleText[2], COLORS.titleText[3], 1)
    frame.titleText = titleText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 2, 0)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetScript("OnClick", function()
        if mainFrame then
            mainFrame:Hide()
            isFrameVisible = false
        end
    end)

    -- Dragging
    titleBar:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            frame:StartMoving()
        end
    end)
    titleBar:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SaveFramePosition()
    end)

    -- Content frame for rows
    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 2, -CONFIG.padding)
    contentFrame:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", -2, -CONFIG.padding)
    contentFrame:SetHeight(1)

    -- Create row pool
    for i = 1, MAX_TRACKED_TARGETS do
        targetRows[i] = CreateTargetRow(contentFrame, i)
        targetRows[i]:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -((i - 1) * (CONFIG.barHeight + CONFIG.barSpacing)))
    end

    -- OnUpdate handler
    frame:SetScript("OnUpdate", function()
        local now = GetTime()
        if now - lastUpdate < UPDATE_THROTTLE then
            return
        end
        lastUpdate = now

        -- Scan for combat targets
        ScanCombatTargets()

        -- Scan debuffs directly from game (catches missed events)
        ScanAllTrackedDebuffs()

        if table.getn(trackedOrder) == 0 and not isUnlocked then
            return
        end

        UpdateFrame()
    end)

    frame:Hide()
    return frame
end

-- ============================================================================
-- UI Update Functions
-- ============================================================================

local function UpdateDebuffIcons(row, guid)
    local debuffs, count = GetActivePlayerDebuffs(guid)

    -- Hide all icons first
    for i = 1, MAX_ICONS_PER_ROW do
        if row.icons[i] then
            row.icons[i]:Hide()
            row.icons[i].timer:Hide()
        end
    end

    if not debuffs or count == 0 then
        return
    end

    -- Sort by remaining time (shortest first)
    table.sort(debuffs, function(a, b)
        return a.remaining < b.remaining
    end)

    -- Show active debuffs
    for i = 1, math.min(count, MAX_ICONS_PER_ROW) do
        local debuff = debuffs[i]
        local icon = row.icons[i]

        if icon and debuff then
            local texture = GetSpellTexture(debuff.spellID)
            if texture then
                icon.texture:SetTexture(texture)
            else
                icon.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end

            -- Timer text (Cursive style - centered)
            local timerText = FormatTimer(debuff.remaining)
            icon.timer:SetText(timerText)

            local r, g, b = GetTimerColor(debuff.remaining)
            icon.timer:SetTextColor(r, g, b, 1)
            icon.timer:Show()

            -- Stack count (only show if stacks > 1 AND not a known non-stacking debuff)
            local showStacks = debuff.stacks and debuff.stacks > 1 and not NON_STACKING_DEBUFFS[debuff.spellID]
            if showStacks then
                icon.stacks:SetText(tostring(debuff.stacks))
                icon.stacks:Show()
            else
                icon.stacks:SetText("")
                icon.stacks:Hide()
            end

            icon:Show()
        end
    end
end

local function UpdateRow(row, guid, info)
    if not row or not guid or not info then
        row:Hide()
        return
    end

    row.guid = guid

    -- Get unit for this GUID (may be nil if not currently visible as a unit)
    local unit = GetUnitForGUID(guid)

    -- For SuperWoW, we can use GUID directly for many functions
    local unitOrGuid = unit or (CleveRoids.hasSuperwow and guid) or nil

    -- Update target indicator (shows if this is player's target)
    local isCurrentTarget = false
    if CleveRoids.hasSuperwow then
        -- Check if this GUID matches current target's GUID
        local _, targetGUID = UnitExists("target")
        if targetGUID then
            isCurrentTarget = (CleveRoids.NormalizeGUID(targetGUID) == guid)
        end
    elseif unit then
        isCurrentTarget = UnitIsUnit("target", unit)
    end

    if isCurrentTarget then
        row.targetIndicator:Show()
    else
        row.targetIndicator:Hide()
    end

    -- Update raid icon
    local raidIndex = nil
    if unitOrGuid then
        raidIndex = GetRaidTargetIndex(unitOrGuid)
    end
    if raidIndex then
        SetRaidTargetIconTexture(row.raidIcon, raidIndex)
        row.raidIcon:Show()
    else
        row.raidIcon:Hide()
    end

    -- Update name
    local displayName = TruncateName(info.name, 14)
    row.nameText:SetText(displayName)

    -- Update health (SuperWoW can use GUID directly)
    local health, maxHealth = GetHealthForGUID(guid)
    if health and maxHealth and maxHealth > 0 then
        local percent = (health / maxHealth) * 100
        row.healthBar:SetValue(percent)
        row.hpText:SetText(FormatHealth(health))

        -- Color based on unit type (like Cursive)
        local r, g, b = 1, 0.8, 0.2  -- Default gold
        if unitOrGuid then
            if UnitIsPlayer(unitOrGuid) then
                local _, class = UnitClass(unitOrGuid)
                if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
                    r = RAID_CLASS_COLORS[class].r
                    g = RAID_CLASS_COLORS[class].g
                    b = RAID_CLASS_COLORS[class].b
                end
            end
        end
        row.healthBar:SetStatusBarColor(r, g, b, 1)
    else
        row.healthBar:SetValue(100)
        row.hpText:SetText("?")
        row.healthBar:SetStatusBarColor(0.4, 0.4, 0.4, 1)
    end

    -- Update border color based on hover/combat state (Cursive style)
    if not row.hover then
        local inCombat = false
        if unitOrGuid then
            inCombat = UnitAffectingCombat(unitOrGuid)
        end
        if inCombat then
            row.healthBorder:SetBackdropBorderColor(COLORS.borderCombat[1], COLORS.borderCombat[2], COLORS.borderCombat[3], 1)
        else
            row.healthBorder:SetBackdropBorderColor(COLORS.borderNormal[1], COLORS.borderNormal[2], COLORS.borderNormal[3], 1)
        end
    end

    -- Update debuff icons
    UpdateDebuffIcons(row, guid)

    row:Show()
end

function UpdateFrame()
    -- First, prune dead targets and those with no debuffs
    CheckAndPruneTargets()

    local numTargets = table.getn(trackedOrder)

    if numTargets == 0 then
        if isUnlocked then
            -- Show placeholder for positioning
            local row = targetRows[1]
            if row then
                row.nameText:SetText("(Unlocked)")
                row.healthBar:SetValue(100)
                row.healthBar:SetStatusBarColor(0.3, 0.3, 0.3)
                row.hpText:SetText("Move")
                row.targetIndicator:Hide()
                row.raidIcon:Hide()
                for i = 1, MAX_ICONS_PER_ROW do
                    if row.icons[i] then row.icons[i]:Hide() end
                end
                row.guid = nil
                row:Show()
            end
            for i = 2, MAX_TRACKED_TARGETS do
                targetRows[i]:Hide()
            end

            local contentHeight = CONFIG.barHeight + CONFIG.barSpacing
            local totalHeight = CONFIG.titleHeight + contentHeight + 8
            if mainFrame then
                mainFrame:SetHeight(totalHeight)
                contentFrame:SetHeight(contentHeight)
                if not isFrameVisible then
                    mainFrame:Show()
                    isFrameVisible = true
                end
            end
            return
        end

        if mainFrame and isFrameVisible then
            mainFrame:Hide()
            isFrameVisible = false
        end
        return
    end

    -- Update each row
    for i = 1, MAX_TRACKED_TARGETS do
        local row = targetRows[i]
        if i <= numTargets then
            local guid = trackedOrder[i]
            local info = trackedTargets[guid]
            UpdateRow(row, guid, info)
        else
            row:Hide()
        end
    end

    -- Adjust frame height
    local contentHeight = numTargets * (CONFIG.barHeight + CONFIG.barSpacing)
    local totalHeight = CONFIG.titleHeight + contentHeight + 8

    if mainFrame then
        mainFrame:SetHeight(totalHeight)
        contentFrame:SetHeight(contentHeight)
    end
end

-- ============================================================================
-- Frame Position Persistence
-- ============================================================================

function SaveFramePosition()
    if not mainFrame then return end

    local point, relativeTo, relativePoint, xOfs, yOfs = mainFrame:GetPoint()

    CleveRoidMacros = CleveRoidMacros or {}
    CleveRoidMacros.multiTargetPos = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs,
    }
end

local function RestoreFramePosition()
    if not mainFrame then return end

    CleveRoidMacros = CleveRoidMacros or {}
    local pos = CleveRoidMacros.multiTargetPos

    if pos and pos.point then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
    end
end

-- ============================================================================
-- lib:AddEffect Hook
-- ============================================================================

local function IsPlayerAppliedDebuff(spellID, caster)
    -- Explicitly marked as player
    if IsCasterPlayer(caster) then
        return true
    end

    -- Proc debuffs (items/talents) are always from the player
    if PROC_DEBUFFS[spellID] then
        return true
    end

    -- For shared debuffs, we rely on the caster field being set to "player"
    -- The pending cast system handles this in DEBUFF_ADDED_OTHER

    return false
end

local function HookAddEffect()
    if not lib or not lib.AddEffect then
        CleveRoids.Print("MultiTargetTracker: Could not hook libdebuff.AddEffect")
        return
    end

    local originalAddEffect = lib.AddEffect

    lib.AddEffect = function(self, guid, unitName, spellID, duration, stacks, caster)
        -- Call original first to ensure the record exists
        originalAddEffect(self, guid, unitName, spellID, duration, stacks, caster)

        -- Normalize GUID for our lookups
        local normalizedGuid = CleveRoids.NormalizeGUID(guid)

        -- Check if we have a pending cast for this spell+target
        local pending = GetPendingCast(spellID, guid)
        if pending then
            -- This is our debuff - force set caster and refresh timer
            if normalizedGuid and lib.objects[normalizedGuid] and lib.objects[normalizedGuid][spellID] then
                lib.objects[normalizedGuid][spellID].start = GetTime()
                lib.objects[normalizedGuid][spellID].duration = duration or lib.objects[normalizedGuid][spellID].duration
                lib.objects[normalizedGuid][spellID].caster = "player"
            end
            AddTrackedTarget(guid, unitName, false, guid)  -- guid is raw here
        elseif IsCasterPlayer(caster) then
            -- Explicitly marked as player's debuff
            AddTrackedTarget(guid, unitName, false, guid)  -- guid is raw here
        end
    end
end

-- ============================================================================
-- SPELL_CAST_EVENT Handler (Nampower) - PRIMARY
-- From wiki: "This will only fire for spells you (and certain pets) initiated"
-- ============================================================================

local function SetupSpellCastEventTracking()
    if not CleveRoids.hasNampower then
        return
    end

    local frame = CreateFrame("Frame", "CleveRoidsMTTSpellCastFrame", UIParent)
    frame:RegisterEvent("SPELL_CAST_EVENT")
    frame:SetScript("OnEvent", function()
        -- SPELL_CAST_EVENT args (from Nampower wiki):
        -- arg1 = success (1 if cast succeeded, 0 if failed)
        -- arg2 = spellId
        -- arg3 = castType (1=NORMAL, 2=NON_GCD, 3=ON_SWING, 4=CHANNEL, 5=TARGETING, 6=TARGETING_NON_GCD)
        -- arg4 = targetGuid (string like "0xF5300000000000A5", or "0x000000000" if no explicit target)
        -- arg5 = itemId (0 if not triggered by item)

        local success = arg1
        local spellId = arg2
        local targetGuid = arg4

        -- Only track successful casts
        if success ~= 1 or not spellId then return end

        -- Only track known debuff spells (filter out attacks like Bloodthirst, Heroic Strike)
        if not IsKnownDebuffSpell(spellId) then
            return
        end

        -- For AoE spells, targetGuid might be "0x000000000" or the current target
        -- We still want to record the cast for DEBUFF_ADDED_OTHER matching
        local isAoE = AOE_DEBUFF_SPELLS[spellId]

        -- Skip non-AoE spells with no valid target
        if not isAoE and (not targetGuid or targetGuid == "0x000000000") then
            return
        end

        -- Get target name using multiple resolution methods
        local targetName = nil
        if targetGuid and targetGuid ~= "0x000000000" then
            targetName = ResolveTargetName(targetGuid)
        end

        -- Record this cast for matching with DEBUFF_ADDED_OTHER
        RecordPlayerCast(spellId, targetGuid, targetName)

        -- Refresh existing debuff timers
        -- DEBUFF_ADDED_OTHER only fires on new applications, not refreshes
        local libdebuff = CleveRoids.libdebuff
        if libdebuff and libdebuff.objects then
            local duration = GetSpellDuration(spellId)

            if isAoE then
                -- AoE spell: refresh ALL tracked targets with this debuff
                local refreshCount = 0

                for guid, debuffs in pairs(libdebuff.objects) do
                    -- Try both number and string keys (Lua distinguishes them)
                    local rec = debuffs[spellId] or debuffs[tostring(spellId)]
                    if rec then
                        -- For AoE refreshes, we trust the pending cast system
                        -- If we just cast this AoE spell, refresh all instances of this debuff
                        -- The caster field may not be set yet for new targets hit by this AoE
                        local shouldRefresh = IsCasterPlayer(rec.caster) or pendingAoECasts[spellId]

                        if shouldRefresh then
                            rec.start = GetTime()
                            rec.duration = duration
                            rec.caster = "player"  -- Ensure caster is set for future refreshes
                            refreshCount = refreshCount + 1
                            if MTT_DEBUG then
                                local spellName = SpellInfo and SpellInfo(spellId) or "?"
                                local name = UnitName(guid) or "?"
                                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                                    "|cff88ffff[MTT]|r AoE refresh: %s on %s (dur:%.1f)",
                                    spellName, name, duration))
                            end
                        end
                    end
                end
            else
                -- Single-target spell: refresh only the targeted enemy
                local normalizedGuid = CleveRoids.NormalizeGUID(targetGuid)
                if normalizedGuid and libdebuff.objects[normalizedGuid] and libdebuff.objects[normalizedGuid][spellId] then
                    libdebuff.objects[normalizedGuid][spellId].start = GetTime()
                    libdebuff.objects[normalizedGuid][spellId].duration = duration
                    if MTT_DEBUG then
                        local spellName = SpellInfo and SpellInfo(spellId) or "?"
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(
                            "|cff88ffff[MTT]|r Debuff refresh: %s on %s (dur:%.1f)",
                            spellName, targetName or "?", duration))
                    end
                end
            end
        end
    end)

    -- Periodic cleanup of old pending casts
    frame:SetScript("OnUpdate", function()
        this.elapsed = (this.elapsed or 0) + arg1
        if this.elapsed > 1 then
            this.elapsed = 0
            CleanupPendingCasts()
        end
    end)
end

-- ============================================================================
-- Direct Debuff Scanning (SuperWoW)
-- Scans target debuffs directly to catch debuffs missed by events
-- ============================================================================

local DEBUFF_SCAN_INTERVAL = 0.5  -- Scan every 0.5 seconds
local lastDebuffScan = 0

-- Scan a target's debuffs and update libdebuff.objects
-- Also removes debuffs that are no longer present (overwritten, dispelled, etc.)
-- @param normalizedGuid - Normalized GUID for lib.objects lookup
-- @param rawGuid - Raw GUID for API calls (UnitDebuff, etc.)
local function ScanTargetDebuffs(normalizedGuid, rawGuid)
    if not CleveRoids.hasSuperwow then return end

    local lib = CleveRoids.libdebuff
    if not lib then return end

    -- Use raw GUID for API calls, normalized for table lookups
    local apiGuid = rawGuid or normalizedGuid
    normalizedGuid = CleveRoids.NormalizeGUID(normalizedGuid)
    if not normalizedGuid then return end

    local now = GetTime()

    -- Build a set of spell IDs currently on the target
    local presentDebuffs = {}

    -- SuperWoW supports UnitDebuff with raw GUID directly
    -- Scan debuff slots 1-16 (regular) and 17-48 (overflow in buff slots)
    local scannedAny = false

    for slot = 1, 48 do
        -- SuperWoW UnitDebuff(guid, slot) returns: texture, stacks, debuffType, spellID
        -- NOTE: Does NOT return duration, timeLeft, or caster - only presence info
        local texture, stacks, debuffType, spellId = UnitDebuff(apiGuid, slot)

        -- Stop at nil for slots 1-16 (dense), continue for 17-48 (sparse overflow)
        if not texture then
            if slot <= 16 then
                break
            end
        elseif spellId then
            -- Record that this debuff is present on target
            presentDebuffs[spellId] = true
            scannedAny = true
        end
    end

    -- Only do removal detection if the scan actually returned data
    -- If UnitDebuff returned nothing, the GUID might be inaccessible (out of range, etc.)
    if not scannedAny then
        -- Check if there are ANY debuffs on this target in general
        -- If the target should have debuffs (from our tracking) but scan found none,
        -- it's likely a GUID access issue, not actual removal
        if lib.objects[normalizedGuid] then
            local hasTracked = false
            for spellId, rec in pairs(lib.objects[normalizedGuid]) do
                if rec.caster == "player" then
                    hasTracked = true
                    break
                end
            end
            if hasTracked then
                -- We're tracking debuffs but scan found nothing - skip removal detection
                -- Don't spam debug - this is normal for GUIDs we can't access
                return
            end
        end
    end

    -- Check for debuffs we're tracking that are no longer on the target
    -- (overwritten by stronger effects, dispelled, etc.)
    if lib.objects[normalizedGuid] then
        local toRemove = {}

        for spellId, rec in pairs(lib.objects[normalizedGuid]) do
            -- Only check debuffs we applied (caster = player)
            if rec.caster == "player" and IsKnownDebuffSpell(spellId) then
                -- If debuff is not present on target anymore, mark for removal
                if not presentDebuffs[spellId] then
                    -- Double-check it's not just expired naturally
                    local remaining = (rec.start + rec.duration) - now
                    if remaining > 0.5 then
                        -- Debuff should still be active but isn't on target - it was removed!
                        table.insert(toRemove, spellId)

                        if MTT_DEBUG then
                            local spellName = SpellInfo and SpellInfo(spellId) or "?"
                            local targetName = UnitName(apiGuid) or "?"
                            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                                "|cffff8800[MTT]|r Removed: %s on %s (overwritten/dispelled, %.1fs left)",
                                spellName, targetName, remaining))
                        end
                    end
                end
            end
        end

        -- Remove the debuffs that are no longer present
        for _, spellId in ipairs(toRemove) do
            lib.objects[normalizedGuid][spellId] = nil
        end
    end
end

-- Scan tracked targets for debuffs
-- SuperWoW supports UnitDebuff with GUIDs directly
ScanAllTrackedDebuffs = function()
    if not CleveRoids.hasSuperwow then return end

    local now = GetTime()
    if now - lastDebuffScan < DEBUFF_SCAN_INTERVAL then
        return
    end
    lastDebuffScan = now

    -- Scan current target first (most reliable) - use raw GUID
    if UnitExists("target") then
        local _, targetGuid = UnitExists("target")
        if targetGuid then
            ScanTargetDebuffs(targetGuid, targetGuid)  -- raw GUID for API calls
        end
    end

    -- Also scan other tracked targets (SuperWoW supports GUID access)
    for normalizedGuid, info in pairs(trackedTargets) do
        -- Use stored raw GUID for API calls
        local rawGuid = info.rawGuid or normalizedGuid
        ScanTargetDebuffs(normalizedGuid, rawGuid)
    end
end

-- ============================================================================
-- UNIT_CASTEVENT Handler (SuperWoW) - BACKUP
-- Used when Nampower is not available, or as additional tracking
-- ============================================================================

local function SetupUnitCastEventTracking()
    if not CleveRoids.hasSuperwow then
        return
    end

    local frame = CreateFrame("Frame", "CleveRoidsMTTUnitCastFrame", UIParent)
    frame:RegisterEvent("UNIT_CASTEVENT")
    frame:SetScript("OnEvent", function()
        -- UNIT_CASTEVENT args (from SuperWoW wiki):
        -- arg1 = casterGUID
        -- arg2 = targetGUID
        -- arg3 = event type ("START", "CAST", "FAIL", "CHANNEL", "MAINHAND", "OFFHAND")
        -- arg4 = spell id
        -- arg5 = cast duration

        local casterGuid = arg1
        local targetGuid = arg2
        local eventType = arg3
        local spellId = arg4

        -- Check if caster is player by comparing GUIDs (SuperWoW GUIDs are consistent)
        local _, playerGuid = UnitExists("player")
        if not playerGuid or casterGuid ~= playerGuid then
            return
        end

        -- Only track cast starts and instant casts
        if eventType ~= "START" and eventType ~= "CAST" then
            return
        end

        if not spellId or not targetGuid then return end

        -- Skip empty GUIDs (can happen for some AoE spells)
        if targetGuid == "" or targetGuid == "0x0" or targetGuid == "0x000000000" then
            return
        end

        -- Skip self-targeted spells (buffs like Flurry go on player, not enemies)
        if targetGuid == playerGuid then
            return
        end

        -- Get target name using multiple resolution methods
        local targetName = ResolveTargetName(targetGuid)

        -- Skip if we can't resolve the target name (avoid "Unknown" entries)
        if not targetName then return end

        -- Record this cast (backup to SPELL_CAST_EVENT)
        RecordPlayerCast(spellId, targetGuid, targetName)
    end)
end

-- ============================================================================
-- AURA_CAST_ON_OTHER Handler (Nampower) - Duration data + caster verification
-- Requires CVar NP_EnableAuraCastEvents=1
-- ============================================================================

local function SetupAuraCastTracking()
    if not CleveRoids.hasNampower then
        return
    end

    -- Check if AURA_CAST events are enabled (they're off by default!)
    local auraCastEnabled = GetCVar and GetCVar("NP_EnableAuraCastEvents")
    if auraCastEnabled ~= "1" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[MTT]|r Warning: AURA_CAST events disabled. Run: /run SetCVar('NP_EnableAuraCastEvents','1')")
    end

    local frame = CreateFrame("Frame", "CleveRoidsMTTAuraCastFrame", UIParent)
    frame:RegisterEvent("AURA_CAST_ON_OTHER")
    frame:SetScript("OnEvent", function()
        -- AURA_CAST_ON_OTHER args (from Nampower wiki):
        -- arg1 = spellId
        -- arg2 = casterGuid
        -- arg3 = targetGuid
        -- arg4 = effect
        -- arg5 = effectAuraName
        -- arg6 = effectAmplitude
        -- arg7 = effectMiscValue
        -- arg8 = durationMs (duration in milliseconds!)
        -- arg9 = auraCapStatus

        local spellId = arg1
        local casterGuid = arg2
        local targetGuid = arg3
        local durationMs = arg8

        if not spellId or not targetGuid then return end

        -- Safety check: skip if target is the player (self-buff)
        -- This prevents tracking self-buffs like Lightning Shield on enemies
        local _, playerGuid = UnitExists("player")
        if playerGuid and CleveRoids.GUIDsMatch(playerGuid, targetGuid) then
            return  -- Self-targeted aura, skip
        end

        -- Cache duration from AURA_CAST_ON_OTHER (most accurate, includes client modifiers)
        if durationMs and durationMs > 0 and IsCasterPlayer(casterGuid) then
            auraCastDurations[spellId] = durationMs / 1000
        end

        -- Check pending casts for NEW debuff applications
        local pending = GetPendingCast(spellId, targetGuid)

        -- Also check if this is a REFRESH of an existing debuff we're already tracking
        local libdebuff = CleveRoids.libdebuff
        local normalizedGuid = CleveRoids.NormalizeGUID(targetGuid)
        local isRefresh = false

        if libdebuff and normalizedGuid then
            local existingDebuff = libdebuff.objects[normalizedGuid] and libdebuff.objects[normalizedGuid][spellId]
            if existingDebuff and IsCasterPlayer(existingDebuff.caster) then
                -- This is a refresh of our existing debuff!
                isRefresh = true
            end
        end

        -- For AoE spells, also treat as refresh if we have an AoE pending cast AND
        -- the target already has this debuff from us (tracked in our system)
        if not isRefresh and AOE_DEBUFF_SPELLS[spellId] and pending then
            -- AoE spell with pending cast - check if target is already tracked with this debuff
            if libdebuff and normalizedGuid and libdebuff.objects[normalizedGuid] and libdebuff.objects[normalizedGuid][spellId] then
                isRefresh = true
            end
        end


        if not pending and not isRefresh then
            -- Not our debuff (no pending cast and not a refresh of existing tracked debuff)
            return
        end

        -- libdebuff and normalizedGuid already set above
        if not libdebuff or not normalizedGuid then return end

        -- Get duration in seconds (from milliseconds) - key value from this event!
        local duration = durationMs and (durationMs / 1000) or 0

        -- Fallback to unified duration lookup
        if duration <= 0 then
            duration = GetSpellDuration(spellId)
        end

        -- Get target name using multiple resolution methods
        local targetName = ResolveTargetName(targetGuid)

        -- Skip if we can't resolve the target name (avoid "Unknown" entries)
        if not targetName then return end

        -- Update debuff record with accurate duration from DBC
        libdebuff.objects[normalizedGuid] = libdebuff.objects[normalizedGuid] or {}
        local hasExisting = libdebuff.objects[normalizedGuid][spellId]
        libdebuff.objects[normalizedGuid][spellId] = libdebuff.objects[normalizedGuid][spellId] or {}
        libdebuff.objects[normalizedGuid][spellId].start = GetTime()
        libdebuff.objects[normalizedGuid][spellId].duration = duration
        libdebuff.objects[normalizedGuid][spellId].caster = "player"
        -- Force stacks to 1 for non-stacking debuffs
        if NON_STACKING_DEBUFFS[spellId] then
            libdebuff.objects[normalizedGuid][spellId].stacks = 1
        else
            libdebuff.objects[normalizedGuid][spellId].stacks = libdebuff.objects[normalizedGuid][spellId].stacks or 1
        end

        -- Add target to tracker (pass raw targetGuid for API calls)
        AddTrackedTarget(normalizedGuid, targetName, false, targetGuid)

        if MTT_DEBUG then
            local spellName = SpellInfo and SpellInfo(spellId) or "?"
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ff00[MTT]|r %s: %s on %s (%.0fs)",
                hasExisting and "Refresh" or "Track",
                spellName, targetName, duration))
        end
    end)
end

-- ============================================================================
-- DEBUFF_ADDED_OTHER Handler (Nampower) - Debuff confirmation
-- ============================================================================

local function SetupDebuffAddedTracking()
    if not CleveRoids.hasNampower then
        return
    end

    local frame = CreateFrame("Frame", "CleveRoidsMTTDebuffAddedFrame", UIParent)
    frame:RegisterEvent("DEBUFF_ADDED_OTHER")
    frame:SetScript("OnEvent", function()
        -- DEBUFF_ADDED_OTHER args (from Nampower wiki):
        -- arg1 = guid (target who received the debuff)
        -- arg2 = slot (1-based debuff slot)
        -- arg3 = spellId
        -- arg4 = stackCount
        -- arg5 = auraLevel (caster level)

        local targetGuid = arg1
        local spellId = arg3
        local stackCount = arg4 or 1

        if not targetGuid or not spellId then return end

        -- Safety check: skip if target is the player (self-buff)
        local _, playerGuid = UnitExists("player")
        if playerGuid and CleveRoids.GUIDsMatch(playerGuid, targetGuid) then
            return  -- Self-targeted aura, skip
        end

        -- Only track known debuff spells
        local isKnown = IsKnownDebuffSpell(spellId)

        -- Debug: Show if we received DEBUFF_ADDED for known spells
        if MTT_DEBUG and isKnown then
            local spellName = SpellInfo and SpellInfo(spellId) or "?"
            local targetName = UnitName(targetGuid) or "?"
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ff00[MTT]|r DEBUFF_ADDED: %s (id=%d) on %s",
                spellName, spellId, targetName))
        end

        if not isKnown then
            return
        end

        -- Check if we have a pending cast for this spell+target
        local pending = GetPendingCast(spellId, targetGuid)

        -- Also check if this is a REFRESH of an existing debuff we're already tracking
        local libdebuff = CleveRoids.libdebuff
        local normalizedGuid = CleveRoids.NormalizeGUID(targetGuid)
        local isRefresh = false

        if libdebuff and normalizedGuid then
            local existingDebuff = libdebuff.objects[normalizedGuid] and libdebuff.objects[normalizedGuid][spellId]
            if existingDebuff and IsCasterPlayer(existingDebuff.caster) then
                -- This is a refresh of our existing debuff!
                isRefresh = true
            end
        end

        -- For AoE spells, also treat as refresh if we have an AoE pending cast AND
        -- the target already has this debuff tracked
        if not isRefresh and AOE_DEBUFF_SPELLS[spellId] and pending then
            if libdebuff and normalizedGuid and libdebuff.objects[normalizedGuid] and libdebuff.objects[normalizedGuid][spellId] then
                isRefresh = true
            end
        end

        if not pending and not isRefresh then
            -- No pending cast and not a refresh - not our debuff
            return
        end

        -- We have a pending cast or refresh - this is our debuff!
        if not libdebuff or not normalizedGuid then return end

        -- Get duration using unified lookup system
        local duration = GetSpellDuration(spellId)

        -- Get target name using multiple resolution methods
        local targetName = ResolveTargetName(targetGuid)

        -- Skip if we can't resolve the target name (avoid "Unknown" entries)
        if not targetName then return end

        -- Add target to tracker (pass raw targetGuid for API calls)
        AddTrackedTarget(normalizedGuid, targetName, false, targetGuid)

        -- Update debuff record
        if libdebuff.objects then
            libdebuff.objects[normalizedGuid] = libdebuff.objects[normalizedGuid] or {}
            local hasExisting = libdebuff.objects[normalizedGuid][spellId]
            libdebuff.objects[normalizedGuid][spellId] = libdebuff.objects[normalizedGuid][spellId] or {}
            libdebuff.objects[normalizedGuid][spellId].start = GetTime()
            libdebuff.objects[normalizedGuid][spellId].duration = duration
            libdebuff.objects[normalizedGuid][spellId].caster = "player"
            -- Force stacks to 1 for non-stacking debuffs
            libdebuff.objects[normalizedGuid][spellId].stacks = NON_STACKING_DEBUFFS[spellId] and 1 or stackCount

            if MTT_DEBUG then
                local spellName = SpellInfo and SpellInfo(spellId) or "?"
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "|cff00ff00[MTT]|r %s: %s on %s (%.0fs)",
                    hasExisting and "Refresh" or "Track",
                    spellName, targetName, duration))
            end
        end
    end)
end

-- ============================================================================
-- BUFF_ADDED_OTHER Handler (Nampower) - Debuff overflow tracking
-- When debuff bar is full, debuffs appear in buff slots 17-48
-- Also catches aura refreshes that might not trigger DEBUFF_ADDED_OTHER
-- ============================================================================

local function SetupBuffAddedTracking()
    if not CleveRoids.hasNampower then
        return
    end

    local frame = CreateFrame("Frame", "CleveRoidsMTTBuffAddedFrame", UIParent)
    frame:RegisterEvent("BUFF_ADDED_OTHER")
    frame:SetScript("OnEvent", function()
        -- BUFF_ADDED_OTHER args (same as DEBUFF_ADDED_OTHER):
        -- arg1 = guid (target who received the buff)
        -- arg2 = slot (1-based slot)
        -- arg3 = spellId
        -- arg4 = stackCount
        -- arg5 = auraLevel (caster level)

        local targetGuid = arg1
        local spellId = arg3
        local stackCount = arg4 or 1

        if not targetGuid or not spellId then return end

        -- Safety check: skip if target is the player (self-buff)
        local _, playerGuid = UnitExists("player")
        if playerGuid and CleveRoids.GUIDsMatch(playerGuid, targetGuid) then
            return  -- Self-targeted aura, skip
        end

        -- Only process if this is a debuff we're already tracking (refresh in overflow slot)
        local libdebuff = CleveRoids.libdebuff
        local normalizedGuid = CleveRoids.NormalizeGUID(targetGuid)

        if not libdebuff or not normalizedGuid then return end

        local existingDebuff = libdebuff.objects[normalizedGuid] and libdebuff.objects[normalizedGuid][spellId]
        if not existingDebuff or existingDebuff.caster ~= "player" then
            -- Not a debuff we're tracking
            return
        end

        -- This is a refresh of our existing debuff (appearing in buff overflow)!
        -- Get duration from our known durations
        local duration = existingDebuff.duration
                      or (libdebuff.personalDebuffs and libdebuff.personalDebuffs[spellId])
                      or (libdebuff.sharedDebuffs and libdebuff.sharedDebuffs[spellId])
                      or (libdebuff.durations and libdebuff.durations[spellId])
                      or 30

        -- Update debuff record
        libdebuff.objects[normalizedGuid][spellId].start = GetTime()
        libdebuff.objects[normalizedGuid][spellId].stacks = stackCount

        if MTT_DEBUG then
            local spellName = SpellInfo and SpellInfo(spellId) or "?"
            local targetName = ResolveTargetName(targetGuid) or "?"
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff00ff00[MTT]|r Refresh: %s on %s (%.0fs)",
                spellName, targetName, duration))
        end
    end)
end

-- ============================================================================
-- Death Detection (immediate removal of dead units)
-- Uses UNIT_DIED from Nampower when available
-- ============================================================================

local function SetupDeathDetection()
    local deathFrame = CreateFrame("Frame", "CleveRoidsMTTDeathFrame", UIParent)

    -- Register for target changes and health updates to catch deaths quickly
    deathFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    deathFrame:RegisterEvent("UNIT_HEALTH")
    deathFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

    -- UNIT_DIED from Nampower (most reliable)
    if CleveRoids.hasNampower then
        deathFrame:RegisterEvent("UNIT_DIED")
    end

    -- Player leaving combat - cleanup targets with no active debuffs
    deathFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    deathFrame:SetScript("OnEvent", function()
        if event == "PLAYER_REGEN_ENABLED" then
            -- Player left combat - immediately prune targets with no active debuffs
            local toRemove = {}
            for guid, info in pairs(trackedTargets) do
                if IsGUIDDead(guid) then
                    table.insert(toRemove, guid)
                else
                    local debuffs, count = GetActivePlayerDebuffs(guid)
                    if count == 0 then
                        table.insert(toRemove, guid)
                    end
                end
            end
            for i = 1, table.getn(toRemove) do
                RemoveTrackedTarget(toRemove[i])
            end
            if MTT_DEBUG and table.getn(toRemove) > 0 then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "|cff00ff00[MTT]|r Left combat, removed %d targets with no debuffs",
                    table.getn(toRemove)))
            end

        elseif event == "UNIT_DIED" then
            -- UNIT_DIED args (from Nampower wiki):
            -- arg1 = guid of the unit that died
            local deadGuid = arg1
            if deadGuid then
                local normalizedGUID = CleveRoids.NormalizeGUID(deadGuid)
                if normalizedGUID and trackedTargets[normalizedGUID] then
                    if MTT_DEBUG then
                        local info = trackedTargets[normalizedGUID]
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(
                            "|cffff0000[MTT]|r UNIT_DIED: %s", info.name or "?"))
                    end
                    RemoveTrackedTarget(normalizedGUID)
                end
            end

        elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
            -- arg1 = death message like "Mob Name dies."
            if arg1 then
                -- Extract name from "X dies." message
                local deadName = string.gsub(arg1, " dies%.$", "")
                if deadName and deadName ~= "" then
                    -- Find and remove any tracked target with this name
                    for guid, info in pairs(trackedTargets) do
                        if info.name == deadName then
                            RemoveTrackedTarget(guid)
                            break
                        end
                    end
                end
            end

        elseif event == "PLAYER_TARGET_CHANGED" or event == "UNIT_HEALTH" then
            -- Quick check: if current target is dead and tracked, remove it
            if UnitExists("target") and UnitIsDead("target") then
                local _, targetGUID = UnitExists("target")
                if targetGUID then
                    local normalizedGUID = CleveRoids.NormalizeGUID(targetGUID)
                    if normalizedGUID and trackedTargets[normalizedGUID] then
                        RemoveTrackedTarget(normalizedGUID)
                    end
                end
            end

            -- Also do a quick scan of all tracked targets for deaths (SuperWoW)
            if CleveRoids.hasSuperwow then
                local toRemove = {}
                for guid, info in pairs(trackedTargets) do
                    if UnitIsDead(guid) then
                        table.insert(toRemove, guid)
                    end
                end
                for i = 1, table.getn(toRemove) do
                    RemoveTrackedTarget(toRemove[i])
                end
            end
        end
    end)
end

-- ============================================================================
-- Combat Target Scanning
-- ============================================================================

local combatScanInterval = 0.5
local lastCombatScan = 0

ScanCombatTargets = function()
    if not CleveRoids.hasUnitXP then
        return
    end

    if not UnitAffectingCombat("player") then
        return
    end

    local now = GetTime()
    if now - lastCombatScan < combatScanInterval then
        return
    end
    lastCombatScan = now

    local hadTarget = UnitExists("target")
    local currentTargetGuid = nil
    if hadTarget then
        local _, guid = UnitExists("target")
        currentTargetGuid = guid
    end

    local firstGuid = nil
    local maxIterations = 30

    for i = 1, maxIterations do
        local found = UnitXP("target", "nextEnemyConsideringDistance")
        if not found then break end

        if not UnitExists("target") then break end

        local _, currentGuid = UnitExists("target")
        if not currentGuid then break end

        if firstGuid == nil then
            firstGuid = currentGuid
        elseif currentGuid == firstGuid then
            break
        end

        local normalizedGuid = CleveRoids.NormalizeGUID(currentGuid)

        if normalizedGuid and not trackedTargets[normalizedGuid] then
            local name = UnitName("target")
            confirmedEnemies[normalizedGuid] = true
            AddTrackedTarget(normalizedGuid, name, true, currentGuid)  -- pass raw GUID
        end
    end

    -- Restore original target state
    if currentTargetGuid then
        TargetUnit(currentTargetGuid)
    else
        -- User had no target before scan - clear whatever UnitXP selected
        ClearTarget()
    end
end

-- ============================================================================
-- Multiscan Integration
-- ============================================================================

local function GetTrackedTargetGUIDs()
    local guids = {}
    for i = 1, table.getn(trackedOrder) do
        local guid = trackedOrder[i]
        if trackedTargets[guid] then
            table.insert(guids, guid)
        end
    end
    return guids
end

local function GetTrackedTargetInfo(guid)
    return trackedTargets[guid]
end

local function IsTracked(guid)
    if not guid then return false end
    guid = CleveRoids.NormalizeGUID(guid)
    return trackedTargets[guid] ~= nil
end

local function GetTrackedCount()
    return table.getn(trackedOrder)
end

local function FindTrackedTarget(priority, validateFunc)
    if table.getn(trackedOrder) == 0 then
        return nil
    end

    local bestGuid = nil
    local bestScore = nil

    for i = 1, table.getn(trackedOrder) do
        local guid = trackedOrder[i]
        local info = trackedTargets[guid]

        if info then
            if validateFunc and not validateFunc(guid) then
                -- Skip
            else
                local score = nil

                if priority == "oldest" then
                    return guid
                elseif priority == "newest" then
                    bestGuid = guid
                elseif priority == "lowestdebuff" then
                    local debuffs, count = GetActivePlayerDebuffs(guid)
                    if debuffs and count > 0 then
                        for j = 1, count do
                            local remaining = debuffs[j].remaining
                            if not score or remaining < score then
                                score = remaining
                            end
                        end
                    end
                elseif priority == "highestdebuff" then
                    local debuffs, count = GetActivePlayerDebuffs(guid)
                    if debuffs and count > 0 then
                        for j = 1, count do
                            local remaining = debuffs[j].remaining
                            if not score or remaining > score then
                                score = remaining
                            end
                        end
                    end
                    if score then score = -score end
                elseif priority == "fewestdebuffs" then
                    local _, count = GetActivePlayerDebuffs(guid)
                    score = count
                elseif priority == "mostdebuffs" then
                    local _, count = GetActivePlayerDebuffs(guid)
                    score = -count
                end

                if score then
                    if not bestScore or score < bestScore then
                        bestScore = score
                        bestGuid = guid
                    end
                end
            end
        end
    end

    return bestGuid
end

-- ============================================================================
-- Extension Lifecycle
-- ============================================================================

-- Sync all our debuff durations to pfUI's libdebuff
local function SyncDurationsToPfUI()
    if not pfUI or not pfUI.api or not pfUI.api.libdebuff then
        return
    end

    local pflib = pfUI.api.libdebuff
    pflib.debuffs = pflib.debuffs or {}

    local count = 0

    -- Sync personal debuffs
    if lib.personalDebuffs then
        for spellID, duration in pairs(lib.personalDebuffs) do
            local spellName = SpellInfo(spellID)
            if spellName then
                -- Strip rank from name
                local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                -- Only update if our duration is different (prefer longer/more accurate)
                if not pflib.debuffs[baseName] or pflib.debuffs[baseName] < duration then
                    pflib.debuffs[baseName] = duration
                    count = count + 1
                end
            end
        end
    end

    -- Sync shared debuffs
    if lib.sharedDebuffs then
        for spellID, duration in pairs(lib.sharedDebuffs) do
            local spellName = SpellInfo(spellID)
            if spellName then
                local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                if not pflib.debuffs[baseName] or pflib.debuffs[baseName] < duration then
                    pflib.debuffs[baseName] = duration
                    count = count + 1
                end
            end
        end
    end

    -- Sync proc debuffs
    for spellID, _ in pairs(PROC_DEBUFFS) do
        local duration = lib.durations and lib.durations[spellID]
        if duration then
            local spellName = SpellInfo(spellID)
            if spellName then
                local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                if not pflib.debuffs[baseName] or pflib.debuffs[baseName] ~= duration then
                    pflib.debuffs[baseName] = duration
                    count = count + 1
                end
            end
        end
    end

end

function Extension.OnLoad()
    lib = CleveRoids.libdebuff

    if not lib then
        CleveRoids.Print("MultiTargetTracker: libdebuff not found, extension disabled")
        return
    end

    -- Build cache of player's known spells for attribution checks
    BuildPlayerSpellCache()

    -- Add item proc debuffs to shared debuffs table (if not already present)
    -- Thunderfury, Blessed Blade of the Windseeker
    lib.sharedDebuffs = lib.sharedDebuffs or {}
    lib.sharedDebuffs[21992] = lib.sharedDebuffs[21992] or 12  -- Thunderfury (12s duration)
    lib.sharedDebuffs[27648] = lib.sharedDebuffs[27648] or 12  -- Thunderfury secondary effect

    -- Also add to durations table for GetDuration lookups
    lib.durations = lib.durations or {}
    lib.durations[21992] = lib.durations[21992] or 12
    lib.durations[27648] = lib.durations[27648] or 12

    mainFrame = CreateMainFrame()
    HookAddEffect()

    -- Enable AURA_CAST events in Nampower (required for AURA_CAST_ON_OTHER to fire)
    if CleveRoids.hasNampower and SetCVar then
        SetCVar("NP_EnableAuraCastEvents", "1")
    end

    -- Setup tracking handlers based on wiki documentation:
    -- SPELL_CAST_EVENT: "only fires for spells you (and certain pets) initiated"
    -- DEBUFF_ADDED_OTHER: confirms debuff landed, provides stacks
    -- AURA_CAST_ON_OTHER: provides durationMs from DBC
    -- UNIT_CASTEVENT: SuperWoW backup with consistent GUIDs
    -- UNIT_DIED: reliable death detection from Nampower
    SetupSpellCastEventTracking()  -- Primary: Nampower SPELL_CAST_EVENT (only YOUR casts)
    SetupUnitCastEventTracking()   -- Backup: SuperWoW UNIT_CASTEVENT
    SetupDebuffAddedTracking()     -- Confirmation: DEBUFF_ADDED_OTHER
    SetupBuffAddedTracking()       -- Overflow/refresh: BUFF_ADDED_OTHER (debuffs in buff slots 17-48)
    SetupAuraCastTracking()        -- Duration data + refresh: AURA_CAST_ON_OTHER
    SetupDeathDetection()          -- Cleanup: UNIT_DIED + fallbacks
    RestoreFramePosition()

    -- Sync our durations to pfUI (delayed slightly to ensure pfUI is loaded)
    local syncFrame = CreateFrame("Frame")
    syncFrame:SetScript("OnUpdate", function()
        this.elapsed = (this.elapsed or 0) + arg1
        if this.elapsed > 1 then
            SyncDurationsToPfUI()
            this:SetScript("OnUpdate", nil)
        end
    end)

    CleveRoids.Print("Multi-Target Tracker loaded. Use /cleveroid mtt for commands.")
end

-- Export API
CleveRoids.MultiTargetTracker = {
    -- Target management
    AddTarget = AddTrackedTarget,
    RemoveTarget = RemoveTrackedTarget,
    ClearTargets = ClearAllTargets,

    -- Query functions
    GetTrackedGUIDs = GetTrackedTargetGUIDs,
    GetTargetInfo = GetTrackedTargetInfo,
    IsTracked = IsTracked,
    GetTrackedCount = GetTrackedCount,
    FindTrackedTarget = FindTrackedTarget,
    GetActiveDebuffs = GetActivePlayerDebuffs,

    -- Frame control
    Show = function()
        if mainFrame then
            mainFrame:Show()
            isFrameVisible = true
        end
    end,
    Hide = function()
        if mainFrame then
            mainFrame:Hide()
            isFrameVisible = false
        end
    end,
    Toggle = function()
        if mainFrame then
            if isFrameVisible then
                mainFrame:Hide()
                isFrameVisible = false
            else
                mainFrame:Show()
                isFrameVisible = true
            end
        end
    end,
    IsVisible = function()
        return isFrameVisible
    end,

    -- Frame positioning
    Unlock = function()
        isUnlocked = true
        if mainFrame then
            mainFrame:Show()
            isFrameVisible = true
            if mainFrame.titleText then
                mainFrame.titleText:SetText("Debuff Tracker (UNLOCKED)")
                mainFrame.titleText:SetTextColor(0, 1, 0, 1)
            end
        end
        CleveRoids.Print("Multi-Target Tracker: Unlocked - drag to move, then /cleveroid mtt lock")
    end,
    Lock = function()
        isUnlocked = false
        if mainFrame and mainFrame.titleText then
            mainFrame.titleText:SetText("Debuff Tracker")
            mainFrame.titleText:SetTextColor(COLORS.titleText[1], COLORS.titleText[2], COLORS.titleText[3], 1)
        end
        if table.getn(trackedOrder) == 0 and mainFrame then
            mainFrame:Hide()
            isFrameVisible = false
        end
        CleveRoids.Print("Multi-Target Tracker: Locked")
    end,
    ResetPosition = function()
        CleveRoidMacros = CleveRoidMacros or {}
        CleveRoidMacros.multiTargetPos = nil
        if mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
        end
        CleveRoids.Print("Multi-Target Tracker: Position reset")
    end,

    -- Debug mode
    Debug = function(enable)
        if enable == nil then
            MTT_DEBUG = not MTT_DEBUG
        else
            MTT_DEBUG = enable
        end
        CleveRoids.Print("Multi-Target Tracker: Debug " .. (MTT_DEBUG and "ON" or "OFF"))
    end,

    -- Dump current tracking state for debugging
    DumpState = function()
        CleveRoids.Print("=== MTT State Dump ===")
        CleveRoids.Print("Tracked targets: " .. table.getn(trackedOrder))
        for i, guid in ipairs(trackedOrder) do
            local info = trackedTargets[guid]
            local debuffs, count = GetActivePlayerDebuffs(guid)
            CleveRoids.Print(string.format("  %d. %s (GUID:%s) - %d debuffs",
                i, info and info.name or "?", string.sub(tostring(guid), 1, 16), count))

            -- Show lib.objects state
            local libdebuff = CleveRoids.libdebuff
            if libdebuff and libdebuff.objects then
                local hasRecord = libdebuff.objects[guid] and true or false
                CleveRoids.Print(string.format("     lib.objects[guid]: %s", hasRecord and "EXISTS" or "nil"))
                if hasRecord then
                    for spellID, rec in pairs(libdebuff.objects[guid]) do
                        local name = SpellInfo and SpellInfo(spellID) or "?"
                        local remaining = rec.duration and rec.start and (rec.duration + rec.start - GetTime()) or 0
                        local stacksInfo = rec.stacks and rec.stacks > 1 and (" x" .. rec.stacks) or ""
                        CleveRoids.Print(string.format("       - %s: %.1fs, caster=%s%s",
                            name, remaining, tostring(rec.caster), stacksInfo))
                    end
                end
            end
        end
    end,
}

_G["CleveRoids"] = CleveRoids
