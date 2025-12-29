--[[
    ComboPoint Tracker for Duration-Scaling Spells
    Author: Extension for CleveRoids
    Purpose: Track combo points used when casting spells that scale duration with combo points
]]

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

-- Initialize combo point tracking table
CleveRoids.ComboPointTracking = CleveRoids.ComboPointTracking or {}
-- Note: CleveRoids.lastComboPoints and CleveRoids.lastComboPointsTime are initialized in Init.lua

-- Initialize SavedVariable for learned combo durations
-- Structure: CleveRoids_ComboDurations[spellID][comboPoints] = duration
CleveRoids_ComboDurations = CleveRoids_ComboDurations or {}

-- Storage for last Rip cast (for Carnage talent mechanic)
-- Carnage talent: When Ferocious Bite procs Carnage, it refreshes Rip and Rake to their original duration
-- Detection: When combo points don't drop to 0 after FB (they stay at 1 = Carnage proc)
-- Talent Position: Tab 2 (Feral Combat), Talent 17
-- Rank 1: 10% per CP, Rank 2: 20% per CP
CleveRoids.lastRipCast = CleveRoids.lastRipCast or {
    duration = nil,
    targetGUID = nil,
    timestamp = 0
}

CleveRoids.lastRakeCast = CleveRoids.lastRakeCast or {
    duration = nil,
    targetGUID = nil,
    timestamp = 0
}

-- Define spells that scale with combo points by SPELL ID and their duration formulas
-- Duration = base + (combo_points - 1) * increment
CleveRoids.ComboScalingSpellsByID = {
    -- ROGUE: Rupture - 8 sec base, +2 sec per additional combo point
    [1943] = { base = 8, increment = 2, name = "Rupture" },        -- Rank 1
    [8639] = { base = 8, increment = 2, name = "Rupture" },        -- Rank 2
    [8640] = { base = 8, increment = 2, name = "Rupture" },        -- Rank 3
    [11273] = { base = 8, increment = 2, name = "Rupture" },       -- Rank 4
    [11274] = { base = 8, increment = 2, name = "Rupture" },       -- Rank 5
    [11275] = { base = 8, increment = 2, name = "Rupture" },       -- Rank 6

    -- ROGUE: Kidney Shot - Rank 1: 1 sec base, Rank 2: 2 sec base, +1 sec per CP
    [408] = { base = 1, increment = 1, name = "Kidney Shot" },     -- Rank 1
    [8643] = { base = 2, increment = 1, name = "Kidney Shot" },    -- Rank 2

    -- DRUID: Rip - 12 sec base, +4 sec per additional combo point (Source: Vanilla WoW Wiki)
    -- Note: Some sources say 10+2, but testing shows 12+4 is accurate for 1.12
    [1079] = { base = 10, increment = 2, name = "Rip" },           -- Rank 1
    [9492] = { base = 10, increment = 2, name = "Rip" },           -- Rank 2
    [9493] = { base = 10, increment = 2, name = "Rip" },           -- Rank 3
    [9752] = { base = 10, increment = 2, name = "Rip" },           -- Rank 4
    [9894] = { base = 10, increment = 2, name = "Rip" },           -- Rank 5
    [9896] = { base = 10, increment = 2, name = "Rip" },           -- Rank 6
}

-- Ferocious Bite spell IDs (for Carnage talent mechanic)
-- Carnage talent: When FB procs Carnage, refreshes Rip and Rake back to their original duration
-- Proc detection: combo points stay at 1 after FB instead of dropping to 0
-- Talent Position: Tab 2 (Feral Combat), Talent 17
CleveRoids.FerociousBiteSpellIDs = {
    [22557] = true,  -- Rank 1
    [22568] = true,  -- Rank 2
    [22827] = true,  -- Rank 3
    [22828] = true,  -- Rank 4
    [22829] = true,  -- Rank 5
    [31018] = true,  -- Rank 6
}

-- Rip spell IDs (for Carnage talent - refreshed when Carnage procs)
CleveRoids.RipSpellIDs = {
    [1079] = true,   -- Rank 1
    [9492] = true,   -- Rank 2
    [9493] = true,   -- Rank 3
    [9752] = true,   -- Rank 4
    [9894] = true,   -- Rank 5
    [9896] = true,   -- Rank 6
}

-- Rake spell IDs (for Carnage talent - refreshed when Carnage procs)
CleveRoids.RakeSpellIDs = {
    [1822] = true,   -- Rank 1
    [1823] = true,   -- Rank 2
    [1824] = true,   -- Rank 3
    [9904] = true,   -- Rank 4
}

-- Pounce Bleed spell IDs (for immunity detection - bleed portion of Pounce)
-- Note: Pounce also applies a stun, but these are the bleed debuff IDs
CleveRoids.PounceBleedSpellIDs = {
    [9005] = true,   -- Rank 1
    [9823] = true,   -- Rank 2
    [9827] = true,   -- Rank 3
}

-- Combined table for all bleed spells that need immunity detection
-- Used when checking if a cast bleed failed to apply (indicates bleed immunity)
CleveRoids.BleedSpellIDs = {
    -- Rake
    [1822] = true,   -- Rank 1
    [1823] = true,   -- Rank 2
    [1824] = true,   -- Rank 3
    [9904] = true,   -- Rank 4
    -- Pounce Bleed
    [9005] = true,   -- Rank 1
    [9823] = true,   -- Rank 2
    [9827] = true,   -- Rank 3
}

-- =============================================================================
-- SHAMAN: Molten Blast → Flame Shock Refresh (TWoW Custom)
-- When Molten Blast hits, it refreshes Flame Shock duration on the target
-- Detection: Monitor combat log for Molten Blast damage, then refresh Flame Shock
-- =============================================================================
CleveRoids.MoltenBlastSpellIDs = {
    [36916] = true,  -- Rank 1
    [36917] = true,  -- Rank 2
    [36918] = true,  -- Rank 3
    [36919] = true,  -- Rank 4
    [36920] = true,  -- Rank 5
    [36921] = true,  -- Rank 6
}

CleveRoids.FlameShockSpellIDs = {
    [8050] = true,   -- Rank 1
    [8052] = true,   -- Rank 2
    [8053] = true,   -- Rank 3
    [10447] = true,  -- Rank 4
    [10448] = true,  -- Rank 5
    [29228] = true,  -- Rank 6
}

-- =============================================================================
-- WARLOCK: Conflagrate → Immolate Duration Reduction
-- When Conflagrate is cast, it reduces Immolate duration by 3 seconds
-- =============================================================================
CleveRoids.ConflagrateSpellIDs = {
    [17962] = true,  -- Rank 1
    [18930] = true,  -- Rank 2
    [18931] = true,  -- Rank 3
    [18932] = true,  -- Rank 4
}

CleveRoids.ImmolateSpellIDs = {
    [348] = true,    -- Rank 1
    [707] = true,    -- Rank 2
    [1094] = true,   -- Rank 3
    [2941] = true,   -- Rank 4
    [11665] = true,  -- Rank 5
    [11667] = true,  -- Rank 6
    [11668] = true,  -- Rank 7
    [25309] = true,  -- Rank 8
}

-- =============================================================================
-- WARLOCK: Dark Harvest Duration Acceleration (TWoW Custom)
-- Channeled spell that accelerates DoT tick rate by 30% while channeling
-- Complex tracking: debuff expires 30% faster while Dark Harvest is active
-- =============================================================================
CleveRoids.DarkHarvestSpellIDs = {
    [52550] = true,  -- Rank 1
    [52551] = true,  -- Rank 2
    [52552] = true,  -- Rank 3
}

-- =============================================================================
-- DRUID: Rake Debuff Cap Boss Whitelist
-- These bosses are likely to hit the 48 debuff cap, causing Rake to get pushed off
-- For mobs NOT in this list, we verify Rake is actually on the target before tracking
-- Prevents false tracking when debuffs get pushed off at cap
-- =============================================================================
CleveRoids.MobsThatBleed = {
    -- Karazhan Crypts / TWoW Custom
    ["0xF13000F1F3276A33"] = true, -- Keeper Gnarlmoon
    ["0xF13000F1FA276A32"] = true, -- Ley-Watcher Incantagos
    ["0xF13000EA3F276C05"] = true, -- King
    ["0xF13000EA31279058"] = true, -- Queen
    ["0xF13000EA43276C06"] = true, -- Bishop
    ["0xF13000EA44279044"] = true, -- Pawn
    ["0xF13000EA42276C07"] = true, -- Rook
    ["0xF13000EA4D05DA44"] = true, -- Sanv Tas'dal
    ["0xF13000EA57276C04"] = true, -- Kruul
    ["0xF130016C95276DAF"] = true, -- Mephistroth

    -- Naxxramas
    ["0xF130003E5401591A"] = true, -- Anub'Rekhan
    ["0xF130003E510159B0"] = true, -- Grand Widow Faerlina
    ["0xF130003E500159A3"] = true, -- Maexxna
    ["0xF130003EBD01598C"] = true, -- Razuvious
    ["0xF130003EBC01599F"] = true, -- Gothik
    ["0xF130003EBF015AB2"] = true, -- Zeliek
    ["0xF130003EBE015AB3"] = true, -- Mograine
    ["0xF130003EC1015AB1"] = true, -- Blaumeux
    ["0xF130003EC0015AB0"] = true, -- Thane
    ["0xF130003E52015824"] = true, -- Noth
    ["0xF130003E4001588D"] = true, -- Heigan
    ["0xF130003E8B0158A2"] = true, -- Loatheb
    ["0xF130003E9C0158EA"] = true, -- Patchwerk
    ["0xF130003E3B0158EF"] = true, -- Grobbulus
    ["0xF130003E3C0158F0"] = true, -- Gluth
    ["0xF130003E380159A0"] = true, -- Thaddius
    ["0xF130003E75015AB4"] = true, -- Sapphiron
    ["0xF130003E76015AED"] = true, -- Kel'Thuzad
}

-- Legacy name-based table for backwards compatibility
CleveRoids.ComboScalingSpells = {
    ["Rupture"] = { base_duration = 8, increment = 2, all_ranks = true },
    ["Kidney Shot(Rank 1)"] = { base_duration = 1, increment = 1 },
    ["Kidney Shot(Rank 2)"] = { base_duration = 2, increment = 1 },
    ["Rip"] = { base_duration = 10, increment = 2, all_ranks = true }
}

-- Function to get current combo points
-- Note: In Vanilla WoW 1.12, GetComboPoints() takes no parameters
-- (The "player", "target" syntax is from TBC/WotLK)
function CleveRoids.GetComboPoints()
    return GetComboPoints() or 0
end

-- Update stored combo points (call this frequently)
function CleveRoids.UpdateComboPoints()
    local current = CleveRoids.GetComboPoints()
    if current > 0 then
        CleveRoids.lastComboPoints = current
        CleveRoids.lastComboPointsTime = GetTime()
    end
end

-- Function to check if a spell scales with combo points
function CleveRoids.IsComboScalingSpell(spellName)
    if not spellName then return false end
    
    -- Check exact match first
    if CleveRoids.ComboScalingSpells[spellName] then
        return true
    end
    
    -- Check for spells marked as all_ranks
    for spell, data in pairs(CleveRoids.ComboScalingSpells) do
        if data.all_ranks then
            -- Remove rank from spell name for comparison
            local baseName = string.gsub(spell, "%(Rank %d+%)", "")
            local checkName = string.gsub(spellName, "%(Rank %d+%)", "")
            if baseName == checkName then
                return true
            end
        end
    end
    
    return false
end

-- Function to get spell data for combo scaling
function CleveRoids.GetComboScalingData(spellName)
    if not spellName then return nil end
    
    -- Check exact match first
    if CleveRoids.ComboScalingSpells[spellName] then
        return CleveRoids.ComboScalingSpells[spellName]
    end
    
    -- Check for spells marked as all_ranks
    for spell, data in pairs(CleveRoids.ComboScalingSpells) do
        if data.all_ranks then
            local baseName = string.gsub(spell, "%(Rank %d+%)", "")
            local checkName = string.gsub(spellName, "%(Rank %d+%)", "")
            if baseName == checkName then
                return data
            end
        end
    end
    
    -- Special handling for Kidney Shot ranks
    if string.find(spellName, "Kidney Shot") then
        local _, _, rank = string.find(spellName, "Kidney Shot%(Rank (%d+)%)")
        if rank then
            rank = tonumber(rank)
            if rank == 1 then
                return CleveRoids.ComboScalingSpells["Kidney Shot(Rank 1)"]
            elseif rank == 2 then
                return CleveRoids.ComboScalingSpells["Kidney Shot(Rank 2)"]
            end
        end
        -- Default to base Kidney Shot data
        return CleveRoids.ComboScalingSpells["Kidney Shot"]
    end
    
    return nil
end

-- Function to calculate duration based on combo points
function CleveRoids.CalculateComboScaledDuration(spellName, comboPoints)
    local data = CleveRoids.GetComboScalingData(spellName)
    if not data then return nil end

    comboPoints = comboPoints or CleveRoids.GetComboPoints()
    if comboPoints < 1 then comboPoints = 1 end -- Minimum 1 combo point
    if comboPoints > 5 then comboPoints = 5 end -- Maximum 5 combo points

    return data.base_duration + (comboPoints - 1) * data.increment
end

-- NEW: Check if spell ID is a combo scaling spell
function CleveRoids.IsComboScalingSpellID(spellID)
    return CleveRoids.ComboScalingSpellsByID[spellID] ~= nil
end

-- NEW: Get combo scaling data by spell ID
function CleveRoids.GetComboScalingDataByID(spellID)
    return CleveRoids.ComboScalingSpellsByID[spellID]
end

-- NEW: Get learned duration for specific combo point count
function CleveRoids.GetLearnedComboDuration(spellID, comboPoints)
    if not CleveRoids_ComboDurations then
        CleveRoids_ComboDurations = {}
    end
    if CleveRoids_ComboDurations[spellID] and CleveRoids_ComboDurations[spellID][comboPoints] then
        return CleveRoids_ComboDurations[spellID][comboPoints]
    end
    return nil
end

-- NEW: Calculate duration by spell ID and combo points (uses learned durations first)
function CleveRoids.CalculateComboScaledDurationByID(spellID, comboPoints)
    local data = CleveRoids.GetComboScalingDataByID(spellID)
    if not data then return nil end

    comboPoints = comboPoints or CleveRoids.GetComboPoints()
    if comboPoints < 1 then comboPoints = 1 end -- Minimum 1 combo point
    if comboPoints > 5 then comboPoints = 5 end -- Maximum 5 combo points

    local baseDuration

    -- Check for learned duration first
    local learned = CleveRoids.GetLearnedComboDuration(spellID, comboPoints)
    if learned then
        baseDuration = learned
    else
        -- Fall back to formula
        baseDuration = data.base + (comboPoints - 1) * data.increment
    end

    -- Apply all duration modifiers (Nampower, talents, equipment, set bonuses)
    if CleveRoids.ApplyAllDurationModifiers then
        baseDuration = CleveRoids.ApplyAllDurationModifiers(spellID, baseDuration)
    else
        -- Fallback for load order (ApplyAllDurationModifiers not yet defined)
        if CleveRoids.ApplyTalentModifier then
            baseDuration = CleveRoids.ApplyTalentModifier(spellID, baseDuration)
        end
        if CleveRoids.ApplyEquipmentModifier then
            baseDuration = CleveRoids.ApplyEquipmentModifier(spellID, baseDuration)
        end
    end

    return baseDuration
end

-- Function to track combo points when casting (by spell name)
function CleveRoids.TrackComboPointCast(spellName)
    if not CleveRoids.IsComboScalingSpell(spellName) then
        return
    end

    -- Get current combo points, but if they're 0 (already consumed), use last known value
    local comboPoints = CleveRoids.GetComboPoints()

    -- If combo points are 0, use lastComboPoints as fallback
    if comboPoints == 0 and CleveRoids.lastComboPoints > 0 then
        comboPoints = CleveRoids.lastComboPoints
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff9900CleveRoids:|r ComboTrack: Using lastComboPoints (%d) for %s",
                    comboPoints, spellName)
            )
        end
    end

    local duration = CleveRoids.CalculateComboScaledDuration(spellName, comboPoints)
    local currentTime = GetTime()

    -- Only update if this is a better (higher CP) value than existing, or if existing is stale
    local existing = CleveRoids.ComboPointTracking[spellName]
    if existing then
        local age = currentTime - existing.cast_time
        -- Keep existing if it's fresh (<0.5s) and EITHER has more combo points OR is confirmed
        if age < 0.5 then
            if existing.combo_points > comboPoints then
                -- Don't overwrite better data with worse data
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff888888CleveRoids:|r ComboTrack: Ignoring %s with %d CP (have %d CP)",
                            spellName, comboPoints, existing.combo_points)
                    )
                end
                return
            elseif existing.confirmed then
                -- Don't overwrite confirmed tracking with unconfirmed evaluation
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff888888CleveRoids:|r ComboTrack: Ignoring %s - already confirmed",
                            spellName)
                    )
                end
                return
            end
        end
    end

    -- Store the tracking data
    CleveRoids.ComboPointTracking[spellName] = {
        combo_points = comboPoints,
        duration = duration,
        cast_time = currentTime,
        target = UnitName("target") or "Unknown",
        confirmed = false  -- Will be set to true by SPELLCAST_START
    }

    -- Also store in spell_tracking for integration with existing system
    if not CleveRoids.spell_tracking[spellName] then
        CleveRoids.spell_tracking[spellName] = {}
    end

    CleveRoids.spell_tracking[spellName].last_combo_points = comboPoints
    CleveRoids.spell_tracking[spellName].last_duration = duration
    CleveRoids.spell_tracking[spellName].last_cast_time = currentTime

    -- Debug output
    if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff4b7dccCleveRoids:|r ComboTrack: %s cast with %d CP, duration: %d seconds",
                spellName, comboPoints, duration)
        )
    end
end

-- NEW: Track combo points by spell ID (for UNIT_CASTEVENT integration)
function CleveRoids.TrackComboPointCastByID(spellID, targetGUID)
    if not CleveRoids.IsComboScalingSpellID(spellID) then
        return nil
    end

    -- Get current combo points, but if they're 0 (already consumed), use last known value
    local comboPoints = CleveRoids.GetComboPoints()

    -- If combo points are 0, try multiple fallback sources
    if comboPoints == 0 then
        -- First, try lastComboPoints (don't reset immediately - let it persist)
        if CleveRoids.lastComboPoints > 0 then
            comboPoints = CleveRoids.lastComboPoints
            -- Don't reset here - let it persist for multiple events
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff9900[TrackComboByID]|r Using lastComboPoints: %d for spell ID %d",
                        comboPoints, spellID)
                )
            end
        else
            -- Second, check if name-based tracking has recent data for this spell
            local spellName = SpellInfo(spellID)
            if spellName then
                -- Remove rank info for comparison
                local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                if CleveRoids.ComboPointTracking[spellName] then
                    local tracking = CleveRoids.ComboPointTracking[spellName]
                    if tracking.combo_points and tracking.combo_points > 0 and
                       (GetTime() - tracking.cast_time) < 0.5 then -- Within last 0.5 seconds
                        comboPoints = tracking.combo_points
                    end
                elseif CleveRoids.ComboPointTracking[baseName] then
                    local tracking = CleveRoids.ComboPointTracking[baseName]
                    if tracking.combo_points and tracking.combo_points > 0 and
                       (GetTime() - tracking.cast_time) < 0.5 then
                        comboPoints = tracking.combo_points
                    end
                end
            end
        end
    end

    local duration = CleveRoids.CalculateComboScaledDurationByID(spellID, comboPoints)

    if not duration then return nil end

    -- Store tracking data by spell ID
    if not CleveRoids.ComboPointTracking.byID then
        CleveRoids.ComboPointTracking.byID = {}
    end

    CleveRoids.ComboPointTracking.byID[spellID] = {
        combo_points = comboPoints,
        duration = duration,
        cast_time = GetTime(),
        target_guid = targetGUID
    }

    -- Debug output
    if CleveRoids.debug then
        local data = CleveRoids.ComboScalingSpellsByID[spellID]
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cff4b7dccCleveRoids:|r ComboTrack: %s (ID:%d) cast with %d CP, duration: %d seconds",
                data.name, spellID, comboPoints, duration)
        )
    end

    -- Reset lastComboPoints after successfully using it
    if comboPoints > 0 and comboPoints == CleveRoids.lastComboPoints then
        CleveRoids.lastComboPoints = 0
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff888888[TrackComboByID]|r Reset lastComboPoints after use")
            )
        end
    end

    return duration
end

-- API function to get last tracked combo points for a spell
function CleveRoids.GetLastComboPointsForSpell(spellName)
    if CleveRoids.ComboPointTracking[spellName] then
        return CleveRoids.ComboPointTracking[spellName].combo_points
    elseif CleveRoids.spell_tracking[spellName] then
        return CleveRoids.spell_tracking[spellName].last_combo_points
    end
    return nil
end

-- API function to get last calculated duration for a spell
function CleveRoids.GetLastDurationForSpell(spellName)
    if CleveRoids.ComboPointTracking[spellName] then
        return CleveRoids.ComboPointTracking[spellName].duration
    elseif CleveRoids.spell_tracking[spellName] then
        return CleveRoids.spell_tracking[spellName].last_duration
    end
    return nil
end

-- Utility function to display current combo tracking info
function CleveRoids.ShowComboTracking()
    CleveRoids.Print("=== Combo Point Tracking ===")
    local hasData = false
    for spell, data in pairs(CleveRoids.ComboPointTracking) do
        if spell ~= "byID" and data.combo_points then
            CleveRoids.Print(string.format("%s: %d CP, %ds duration, target: %s",
                spell, data.combo_points, data.duration, data.target))
            hasData = true
        end
    end
    if not hasData then
        CleveRoids.Print("No combo finishers tracked yet. Cast Rupture, Rip, or Kidney Shot!")
    end
end

-- Slash command for debugging
SLASH_COMBOTRACK1 = "/combotrack"
SlashCmdList.COMBOTRACK = function(msg)
    if msg == "show" then
        CleveRoids.ShowComboTracking()
    elseif msg == "clear" then
        CleveRoids.ComboPointTracking = {}
        CleveRoids.ComboPointTracking.byID = {}
        CleveRoids.Print("Combo tracking data cleared")
    elseif msg == "debug" then
        CleveRoids.debug = not CleveRoids.debug
        CleveRoids.Print("Combo tracking debug: " .. (CleveRoids.debug and "ON" or "OFF"))
    else
        CleveRoids.Print("ComboTrack commands:")
        CleveRoids.Print("  /combotrack show - Display current tracking data")
        CleveRoids.Print("  /combotrack clear - Clear tracking data")
        CleveRoids.Print("  /combotrack debug - Toggle debug output")
    end
end

-- Export to global namespace NOW, before Extension registration
_G["CleveRoids"] = CleveRoids

-- DEBUG: Confirm ShowComboTracking is defined (disabled to reduce login spam)
-- if CleveRoids.ShowComboTracking then
--     DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ComboPointTracker: ShowComboTracking defined and exported!|r")
-- else
--     DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ComboPointTracker: ERROR - ShowComboTracking NOT defined!|r")
-- end

-- Hook global CastSpell IMMEDIATELY (before Extension system)
if _G.CastSpell then
    local originalCastSpell = _G.CastSpell
    _G.CastSpell = function(id, bookType)
        -- Capture combo points IMMEDIATELY, before anything else
        local currentCP = CleveRoids.GetComboPoints()

        -- Get spell name for checking
        local spellName = GetSpellName(id, bookType)

        if currentCP and currentCP > 0 then
            CleveRoids.lastComboPoints = currentCP
            CleveRoids.lastComboPointsTime = GetTime()
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaff00[CastSpell Hook]|r Captured %d CP before spell %d/%s (name:%s)",
                        currentCP, id or 0, bookType or "nil", spellName or "nil")
                )
            end
        end

        -- Check if it's a combo finisher and pre-populate tracking
        if spellName then
            local isCombo = CleveRoids.IsComboScalingSpell(spellName)
            if CleveRoids.debug and currentCP and currentCP > 0 then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cff888888[CastSpell Debug]|r spell='%s' isCombo=%s CP=%d",
                        spellName, tostring(isCombo), currentCP)
                )
            end

            if isCombo and currentCP and currentCP > 0 then
                local duration = CleveRoids.CalculateComboScaledDuration(spellName, currentCP)
                if duration then
                    local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                    CleveRoids.ComboPointTracking[baseName] = {
                        combo_points = currentCP,
                        duration = duration,
                        cast_time = GetTime(),
                        target = UnitName("target") or "Unknown",
                        confirmed = true
                    }
                    if CleveRoids.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cff00ff00[CastSpell Pre-Track]|r %s with %d CP, duration: %ds",
                                baseName, currentCP, duration)
                        )
                    end
                end
            end
        end

        return originalCastSpell(id, bookType)
    end
    -- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ComboPointTracker: CastSpell hook installed!|r")
end

-- Hook global UseAction IMMEDIATELY (before Extension system)
if _G.UseAction then
    local originalUseAction = _G.UseAction
    _G.UseAction = function(slot, target, button)
        -- Always capture combo points before action, in case it's a finisher
        local currentCP = CleveRoids.GetComboPoints()

        -- Inspect the action button to see what spell it is
        local macroName, actionType, actionID = GetActionText(slot)
        local spellName = nil

        if actionType == "SPELL" and actionID then
            spellName = SpellInfo(actionID)
        end

        if currentCP and currentCP > 0 then
            CleveRoids.lastComboPoints = currentCP
            CleveRoids.lastComboPointsTime = GetTime()
            -- Debug message removed to reduce spam

            -- If it's a combo finisher, pre-populate tracking
            if spellName and CleveRoids.IsComboScalingSpell(spellName) then
                local duration = CleveRoids.CalculateComboScaledDuration(spellName, currentCP)
                if duration then
                    local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                    CleveRoids.ComboPointTracking[baseName] = {
                        combo_points = currentCP,
                        duration = duration,
                        cast_time = GetTime(),
                        target = UnitName("target") or "Unknown",
                        confirmed = true
                    }
                    if CleveRoids.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cff00ff00[UseAction Pre-Track]|r %s with %d CP, duration: %ds",
                                baseName, currentCP, duration)
                        )
                    end
                end
            end
        end
        -- Debug message removed to reduce spam
        return originalUseAction(slot, target, button)
    end
    -- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ComboPointTracker: UseAction hook installed!|r")
end

-- Hook global CastSpellByName IMMEDIATELY (before Extension system)
if CastSpellByName then
    local originalCastSpellByName = CastSpellByName
    CastSpellByName = function(spellName, onSelf)
        local currentCP = CleveRoids.GetComboPoints()
        -- Debug message removed to reduce spam

        if spellName and CleveRoids.IsComboScalingSpell(spellName) then
            if currentCP and currentCP > 0 then
                CleveRoids.lastComboPoints = currentCP
                CleveRoids.lastComboPointsTime = GetTime()

                -- Pre-populate tracking
                local duration = CleveRoids.CalculateComboScaledDuration(spellName, currentCP)
                if duration then
                    local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                    CleveRoids.ComboPointTracking[baseName] = {
                        combo_points = currentCP,
                        duration = duration,
                        cast_time = GetTime(),
                        target = UnitName("target") or "Unknown",
                        confirmed = true
                    }
                    if CleveRoids.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cffff8800[CastSpellByName Pre-Track]|r %s with %d CP, duration: %ds",
                                baseName, currentCP, duration)
                        )
                    end
                end
            end
        end

        return originalCastSpellByName(spellName, onSelf)
    end
    -- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ComboPointTracker: CastSpellByName hook installed!|r")
end

-- Hook into the existing DoCast function (safe to fail)
if not CleveRoids.RegisterExtension then
    -- ExtensionsManager not loaded yet, skip extension system
    -- DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ComboPointTracker: RegisterExtension not found, skipping Extension system|r")
    return
end

local Extension = CleveRoids.RegisterExtension("ComboPointTracker")

function Extension.OnLoad()
    -- Register for cast events
    Extension.RegisterEvent("SPELLCAST_START", "OnSpellcastStart")
    Extension.RegisterEvent("SPELLCAST_STOP", "OnSpellcastStop")
    Extension.RegisterEvent("SPELLCAST_FAILED", "OnSpellcastFailed")
    Extension.RegisterEvent("SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
    Extension.RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    Extension.RegisterEvent("UNIT_AURA", "OnUnitAura")
    Extension.RegisterEvent("PLAYER_COMBO_POINTS", "OnComboPointsChanged")

    -- PERFORMANCE OPTIMIZATION: Removed OnUpdate polling for combo points
    -- Combo points are now tracked via PLAYER_COMBO_POINTS event + spell cast hooks
    -- This eliminates continuous polling while maintaining identical functionality
    -- Events that trigger combo point updates:
    --   - PLAYER_COMBO_POINTS (native event when CP change)
    --   - PLAYER_TARGET_CHANGED (target switch clears CP)
    --   - UNIT_AURA (for debuff applications)
    --   - CastSpellByName/QueueSpellByName hooks (pre-cast capture)

    -- Note: CastSpell, UseAction, and CastSpellByName hooks are set up immediately when file loads (see above)
end

-- Update combo points on relevant events
function Extension.OnTargetChanged()
    CleveRoids.UpdateComboPoints()
end

function Extension.OnUnitAura()
    if arg1 == "target" or arg1 == "player" then
        CleveRoids.UpdateComboPoints()
    end
end

function Extension.OnComboPointsChanged()
    CleveRoids.UpdateComboPoints()

    -- CARNAGE PROC DETECTION (Cursive-style)
    -- When Ferocious Bite is used, combo points should drop to 0
    -- If Carnage procs, combo points will be 1 instead (the Carnage-granted combo point)
    -- Check: After Ferocious Bite (within 0.5s), if combo points > 0, Carnage procced
    if CleveRoids.lastFerociousBiteTime and CleveRoids.lastFerociousBiteTargetGUID then
        local timeSinceBite = GetTime() - CleveRoids.lastFerociousBiteTime
        if timeSinceBite < 0.5 then
            local currentCP = CleveRoids.GetComboPoints()
            if currentCP > 0 then
                -- Carnage procced! Combo points didn't drop to 0 (or rose back to 1)
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cffff00ff[Carnage]|r PROC DETECTED! CP=%d after Ferocious Bite (%.2fs ago)",
                            currentCP, timeSinceBite)
                    )
                end

                -- Apply the Carnage refresh to Rip and Rake
                local targetGUID = CleveRoids.lastFerociousBiteTargetGUID
                local targetName = CleveRoids.lastFerociousBiteTargetName or "Unknown"
                local biteSpellID = CleveRoids.lastFerociousBiteSpellID

                -- Call the Carnage refresh function in Utility.lua
                if CleveRoids.libdebuff and CleveRoids.libdebuff.ApplyCarnageRefresh then
                    CleveRoids.libdebuff.ApplyCarnageRefresh(targetGUID, targetName, biteSpellID)
                end

                -- Clear the tracking to prevent multiple refreshes
                CleveRoids.lastFerociousBiteTime = nil
                CleveRoids.lastFerociousBiteTargetGUID = nil
                CleveRoids.lastFerociousBiteTargetName = nil
                CleveRoids.lastFerociousBiteSpellID = nil
            end
        else
            -- Time window expired, clear tracking
            if CleveRoids.lastFerociousBiteTime then
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cffff00ff[Carnage]|r No proc - time window expired (%.2fs)", timeSinceBite)
                    )
                end
                CleveRoids.lastFerociousBiteTime = nil
                CleveRoids.lastFerociousBiteTargetGUID = nil
                CleveRoids.lastFerociousBiteTargetName = nil
                CleveRoids.lastFerociousBiteSpellID = nil
            end
        end
    end
end

-- Event handlers
function Extension.OnSpellcastStart()
    -- Track combo points at cast start for channeled combo spells
    local spellName = arg1
    if spellName and CleveRoids.IsComboScalingSpell(spellName) then
        -- Capture current combo points BEFORE the spell cast
        local currentCP = CleveRoids.GetComboPoints()
        if currentCP and currentCP > 0 then
            CleveRoids.lastComboPoints = currentCP
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaaaff[Pre-Cast]|r Captured %d combo points before casting %s",
                        currentCP, spellName)
                )
            end
        end

        CleveRoids.TrackComboPointCast(spellName)

        -- Mark this tracking as confirmed (actual cast, not just evaluation)
        if CleveRoids.ComboPointTracking[spellName] then
            CleveRoids.ComboPointTracking[spellName].confirmed = true
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cff00ff00[Confirmed]|r %s tracking confirmed (SPELLCAST_START)",
                        spellName)
                )
            end
        end
    end
end

function Extension.OnSpellcastStop()
    -- Track combo points at successful cast completion
    local spellName = arg1
    if spellName and CleveRoids.IsComboScalingSpell(spellName) then
        -- Update tracking if spell successfully completed
        local tracking = CleveRoids.ComboPointTracking[spellName]
        if tracking and (GetTime() - tracking.cast_time) < 1 then
            -- Cast was recent, mark as successful
            tracking.successful = true
        end
    end
end

function Extension.OnSpellcastFailed()
    -- Clear tracking for failed casts
    local spellName = arg1
    if spellName and CleveRoids.ComboPointTracking[spellName] then
        local tracking = CleveRoids.ComboPointTracking[spellName]
        if tracking and (GetTime() - tracking.cast_time) < 1 then
            -- Recent cast failed, clear confirmed flag and the tracking
            tracking.confirmed = false
            CleveRoids.ComboPointTracking[spellName] = nil
        end
    end
end

function Extension.OnSpellcastInterrupted()
    -- Clear tracking for interrupted casts
    Extension.OnSpellcastFailed()
end

-- Hook CastSpellByName to track combo points
function Extension.CastSpellByName_Hook(spellName, onSelf)
    if spellName and CleveRoids.IsComboScalingSpell(spellName) then
        -- Capture current combo points BEFORE the spell cast
        local currentCP = CleveRoids.GetComboPoints()
        if currentCP and currentCP > 0 then
            CleveRoids.lastComboPoints = currentCP
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaaaff[Pre-Cast]|r Captured %d combo points before casting %s",
                        currentCP, spellName)
                )
            end
        end

        CleveRoids.TrackComboPointCast(spellName)

        -- Confirm the tracking immediately - this only fires on actual casts
        if CleveRoids.ComboPointTracking[spellName] then
            CleveRoids.ComboPointTracking[spellName].confirmed = true
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cff00ff00[Confirmed]|r %s tracking confirmed (CastSpellByName)",
                        spellName)
                )
            end
        end
    end
end

-- Hook CleveRoids.CastSpell if it exists
function Extension.CastSpell_Hook(spellName)
    if spellName and CleveRoids.IsComboScalingSpell(spellName) then
        -- Capture current combo points BEFORE the spell cast
        local currentCP = CleveRoids.GetComboPoints()
        if currentCP and currentCP > 0 then
            CleveRoids.lastComboPoints = currentCP
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaaaff[Pre-Cast]|r Captured %d combo points before casting %s",
                        currentCP, spellName)
                )
            end
        end

        CleveRoids.TrackComboPointCast(spellName)

        -- Confirm the tracking immediately - this only fires on actual casts
        if CleveRoids.ComboPointTracking[spellName] then
            CleveRoids.ComboPointTracking[spellName].confirmed = true
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cff00ff00[Confirmed]|r %s tracking confirmed (CleveRoids.CastSpell)",
                        spellName)
                )
            end
        end
    end
end

-- Integration with DoCast function (moved before Extension registration)
if CleveRoids.DoCast then
    local originalDoCast = CleveRoids.DoCast
    CleveRoids.DoCast = function(msg)
        -- Extract spell name from message
        local spellName = msg

        -- Remove conditionals if present
        local condEnd = string.find(msg, "]")
        if condEnd then
            spellName = string.sub(msg, condEnd + 1)
        end

        spellName = CleveRoids.Trim(spellName)

        -- Track combo points if it's a scaling spell
        if CleveRoids.IsComboScalingSpell(spellName) then
            -- Capture current combo points BEFORE the spell cast
            local currentCP = CleveRoids.GetComboPoints()
            if currentCP and currentCP > 0 then
                CleveRoids.lastComboPoints = currentCP
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cffaaaaff[Pre-Cast]|r Captured %d combo points before casting %s",
                            currentCP, spellName)
                    )
                end
            end

            CleveRoids.TrackComboPointCast(spellName)

            -- Confirm the tracking - DoCast only fires on actual casts
            if CleveRoids.ComboPointTracking[spellName] then
                CleveRoids.ComboPointTracking[spellName].confirmed = true
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff00ff00[Confirmed]|r %s tracking confirmed (DoCast)",
                            spellName)
                    )
                end
            end
        end

        -- Call original function
        return originalDoCast(msg)
    end
end
