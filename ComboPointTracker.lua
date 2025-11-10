--[[
    ComboPoint Tracker for Duration-Scaling Spells
    Author: Extension for CleveRoids
    Purpose: Track combo points used when casting spells that scale duration with combo points
]]

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

-- Initialize combo point tracking table
CleveRoids.ComboPointTracking = CleveRoids.ComboPointTracking or {}

-- Define spells that scale with combo points and their duration formulas
-- Duration = base + (combo_points - 1) * increment
CleveRoids.ComboScalingSpells = {
    -- Rupture (all ranks): 8 sec base, +2 sec per additional combo point
    ["Rupture"] = {
        base_duration = 8,
        increment = 2,
        all_ranks = true
    },
    
    -- Kidney Shot Rank 1: 1 sec base, +1 sec per additional combo point
    ["Kidney Shot(Rank 1)"] = {
        base_duration = 1,
        increment = 1
    },
    
    -- Kidney Shot Rank 2: 2 sec base, +1 sec per additional combo point
    ["Kidney Shot(Rank 2)"] = {
        base_duration = 2,
        increment = 1
    },
    
    -- Kidney Shot (generic for all ranks if rank not specified)
    ["Kidney Shot"] = {
        base_duration = 1, -- Default to rank 1 if rank unknown
        increment = 1,
        check_rank = true
    },
    
    -- Rip (all ranks): 10 sec base, +2 sec per additional combo point
    ["Rip"] = {
        base_duration = 10,
        increment = 2,
        all_ranks = true
    }
}

-- Function to get current combo points
function CleveRoids.GetComboPoints()
    return GetComboPoints("player", "target") or 0
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

-- Function to track combo points when casting
function CleveRoids.TrackComboPointCast(spellName)
    if not CleveRoids.IsComboScalingSpell(spellName) then
        return
    end
    
    local comboPoints = CleveRoids.GetComboPoints()
    local duration = CleveRoids.CalculateComboScaledDuration(spellName, comboPoints)
    
    -- Store the tracking data
    CleveRoids.ComboPointTracking[spellName] = {
        combo_points = comboPoints,
        duration = duration,
        cast_time = GetTime(),
        target = UnitName("target") or "Unknown"
    }
    
    -- Also store in spell_tracking for integration with existing system
    if not CleveRoids.spell_tracking[spellName] then
        CleveRoids.spell_tracking[spellName] = {}
    end
    
    CleveRoids.spell_tracking[spellName].last_combo_points = comboPoints
    CleveRoids.spell_tracking[spellName].last_duration = duration
    CleveRoids.spell_tracking[spellName].last_cast_time = GetTime()
    
    -- Debug output (remove in production)
    if CleveRoids.Debug then
        CleveRoids.Print(string.format("ComboTrack: %s cast with %d combo points, duration: %d seconds", 
            spellName, comboPoints, duration))
    end
end

-- Hook into the existing DoCast function
local Extension = CleveRoids.RegisterExtension("ComboPointTracker")

function Extension.OnLoad()
    -- Register for cast events
    Extension.RegisterEvent("SPELLCAST_START", "OnSpellcastStart")
    Extension.RegisterEvent("SPELLCAST_STOP", "OnSpellcastStop")
    Extension.RegisterEvent("SPELLCAST_FAILED", "OnSpellcastFailed")
    Extension.RegisterEvent("SPELLCAST_INTERRUPTED", "OnSpellcastInterrupted")
    
    -- Hook the spell cast functions if they exist
    if CleveRoids.CastSpell then
        Extension.Hook("CleveRoids.CastSpell", "CastSpell_Hook")
    end
    
    if CastSpellByName then
        Extension.Hook("CastSpellByName", "CastSpellByName_Hook")
    end
end

-- Event handlers
function Extension.OnSpellcastStart()
    -- Track combo points at cast start for channeled combo spells
    local spellName = arg1
    if spellName and CleveRoids.IsComboScalingSpell(spellName) then
        CleveRoids.TrackComboPointCast(spellName)
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
            -- Recent cast failed, clear it
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
        CleveRoids.TrackComboPointCast(spellName)
    end
end

-- Hook CleveRoids.CastSpell if it exists
function Extension.CastSpell_Hook(spellName)
    if spellName and CleveRoids.IsComboScalingSpell(spellName) then
        CleveRoids.TrackComboPointCast(spellName)
    end
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

-- Integration with DoCast function
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
            CleveRoids.TrackComboPointCast(spellName)
        end
        
        -- Call original function
        return originalDoCast(msg)
    end
end

-- Utility function to display current combo tracking info
function CleveRoids.ShowComboTracking()
    CleveRoids.Print("=== Combo Point Tracking ===")
    for spell, data in pairs(CleveRoids.ComboPointTracking) do
        CleveRoids.Print(string.format("%s: %d CP, %ds duration, target: %s", 
            spell, data.combo_points, data.duration, data.target))
    end
end

-- Slash command for debugging
SLASH_COMBOTRACK1 = "/combotrack"
SlashCmdList.COMBOTRACK = function(msg)
    if msg == "show" then
        CleveRoids.ShowComboTracking()
    elseif msg == "clear" then
        CleveRoids.ComboPointTracking = {}
        CleveRoids.Print("Combo tracking data cleared")
    elseif msg == "debug" then
        CleveRoids.Debug = not CleveRoids.Debug
        CleveRoids.Print("Combo tracking debug: " .. (CleveRoids.Debug and "ON" or "OFF"))
    else
        CleveRoids.Print("ComboTrack commands:")
        CleveRoids.Print("  /combotrack show - Display current tracking data")
        CleveRoids.Print("  /combotrack clear - Clear tracking data")
        CleveRoids.Print("  /combotrack debug - Toggle debug output")
    end
end

_G["CleveRoids"] = CleveRoids
