--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

SLASH_PETATTACK1 = "/petattack"

SlashCmdList.PETATTACK = function(msg) CleveRoids.DoPetAction(PetAttack, msg); end

SLASH_PETFOLLOW1 = "/petfollow"

SlashCmdList.PETFOLLOW = function(msg) CleveRoids.DoPetAction(PetFollow, msg); end

SLASH_PETWAIT1 = "/petwait"

SlashCmdList.PETWAIT = function(msg) CleveRoids.DoPetAction(PetWait, msg); end

SLASH_PETPASSIVE1 = "/petpassive"

SlashCmdList.PETPASSIVE = function(msg) CleveRoids.DoPetAction(PetPassiveMode, msg); end

SLASH_PETAGGRESSIVE1 = "/petaggressive"

SlashCmdList.PETAGGRESSIVE = function(msg) CleveRoids.DoPetAction(PetAggressiveMode, msg); end

SLASH_PETDEFENSIVE1 = "/petdefensive"

SlashCmdList.PETDEFENSIVE = function(msg) CleveRoids.DoPetAction(PetDefensiveMode, msg); end

SLASH_RELOAD1 = "/rl"

SlashCmdList.RELOAD = function() ReloadUI(); end

SLASH_USE1 = "/use"

SlashCmdList.USE = CleveRoids.DoUse

SLASH_EQUIP1 = "/equip"

SlashCmdList.EQUIP = CleveRoids.DoUse
-- take back supermacro and pfUI /equip and /use
SlashCmdList.SMEQUIP = CleveRoids.DoUse
SlashCmdList.PFEQUIP = CleveRoids.DoUse
SlashCmdList.PFUSE = CleveRoids.DoUse

SLASH_EQUIPMH1 = "/equipmh"
SlashCmdList.EQUIPMH = CleveRoids.DoEquipMainhand

SLASH_EQUIPOH1 = "/equipoh"
SlashCmdList.EQUIPOH = CleveRoids.DoEquipOffhand

SLASH_UNSHIFT1 = "/unshift"

SlashCmdList.UNSHIFT = CleveRoids.DoUnshift

SLASH_UNQUEUE1 = "/unqueue"
SlashCmdList.UNQUEUE = SpellStopCasting

-- TODO make this conditional too
SLASH_CANCELAURA1 = "/cancelaura"
SLASH_CANCELAURA2 = "/unbuff"

SlashCmdList.CANCELAURA = CleveRoids.DoConditionalCancelAura

SLASH_CASTPET1 = "/castpet"

SlashCmdList.CASTPET = function(msg)
    CleveRoids.DoCastPet(msg)
end

-- Define original implementations before hooking them.
-- This ensures we have a fallback for non-conditional use.
local StartAttack = function(msg)
    if not UnitExists("target") or UnitIsDead("target") then TargetNearestEnemy() end
    if not CleveRoids.CurrentSpell.autoAttack and not CleveRoids.CurrentSpell.autoAttackLock and UnitExists("target") and UnitCanAttack("player","target") then
        CleveRoids.CurrentSpell.autoAttackLock = true
        CleveRoids.autoAttackLockElapsed = GetTime()
        AttackTarget()
    end
end

local StopAttack = function(msg)
    if CleveRoids.CurrentSpell.autoAttack and UnitExists("target") then
        AttackTarget()
        CleveRoids.CurrentSpell.autoAttack = false
    end
end

-- Register slash commands and assign original handlers.
-- These will be hooked immediately after.
SLASH_STARTATTACK1 = "/startattack"
SlashCmdList.STARTATTACK = StartAttack

SLASH_STOPATTACK1 = "/stopattack"
SlashCmdList.STOPATTACK = StopAttack

SLASH_STOPCASTING1 = "/stopcasting"
SlashCmdList.STOPCASTING = SpellStopCasting

----------------------------------
-- HOOK DEFINITIONS START
----------------------------------

-- /startattack hook
CleveRoids.Hooks.STARTATTACK_SlashCmd = SlashCmdList.STARTATTACK
SlashCmdList.STARTATTACK = function(msg)
    msg = msg or ""
    if string.find(msg, "%[") then
        CleveRoids.DoConditionalStartAttack(msg)
    else
        CleveRoids.Hooks.STARTATTACK_SlashCmd(msg)
    end
end

-- /stopattack hook
CleveRoids.Hooks.STOPATTACK_SlashCmd = SlashCmdList.STOPATTACK
SlashCmdList.STOPATTACK = function(msg)
    msg = msg or ""
    if string.find(msg, "%[") then
        -- If conditionals are present, let the function handle it.
        -- It will only stop the attack if the conditions are met.
        CleveRoids.DoConditionalStopAttack(msg)
    else
        -- If no conditionals, run the original command.
        CleveRoids.Hooks.STOPATTACK_SlashCmd(msg)
    end
end

-- /stopcasting hook
CleveRoids.Hooks.STOPCASTING_SlashCmd = SlashCmdList.STOPCASTING
SlashCmdList.STOPCASTING = function(msg)
    msg = msg or ""
    if string.find(msg, "%[") then
        -- If conditionals are present, let the function handle it.
        -- It will only stop the cast if the conditions are met.
        CleveRoids.DoConditionalStopCasting(msg)
    else
        -- If no conditionals, run the original command.
        CleveRoids.Hooks.STOPCASTING_SlashCmd()
    end
end

CleveRoids.Hooks.UNQUEUE_SlashCmd = SlashCmdList.UNQUEUE
SlashCmdList.UNQUEUE = function(msg)
    msg = msg or ""
    if string.find(msg, "%[") then
        -- If conditionals are present, let the function handle it.
        CleveRoids.DoConditionalStopCasting(msg)
    else
        -- If no conditionals, run the original command.
        CleveRoids.Hooks.UNQUEUE_SlashCmd()
    end
end

-- /cast hook
CleveRoids.Hooks.CAST_SlashCmd = SlashCmdList.CAST
SlashCmdList.CAST = function(msg)
    if msg and string.find(msg, "[%[%?!~{]") then
        CleveRoids.DoCast(msg)
    else
        -- Use lastComboPoints which is updated on every OnUpdate tick
        -- This is critical for instant-cast finishers where GetComboPoints() returns 0 immediately
        local currentCP = CleveRoids.lastComboPoints or 0

        -- Also try GetComboPoints as a fallback
        if currentCP == 0 and GetComboPoints then
            currentCP = GetComboPoints()
        end

        if currentCP > 0 then
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffaaff00[/cast Hook]|r Using %d CP for %s",
                        currentCP, msg)
                )
            end

            -- Pre-inject combo duration into pfUI for instant-cast combo finishers
            -- Get the spell data to find the proper spell name (handles case-insensitive input)
            local spellData = CleveRoids.GetSpell and CleveRoids.GetSpell(msg)
            local spellName = spellData and spellData.name or msg

            -- If GetSpell didn't find it, capitalize first letter as fallback
            if not spellData and spellName then
                spellName = string.upper(string.sub(spellName, 1, 1)) .. string.sub(spellName, 2)
            end

            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffcccccc[/cast Debug]|r input='%s', spellName='%s', GetSpell=%s, IsComboScalingSpell=%s",
                        msg, spellName or "nil", tostring(spellData ~= nil), tostring(CleveRoids.IsComboScalingSpell ~= nil))
                )
            end

            if CleveRoids.IsComboScalingSpell and CleveRoids.IsComboScalingSpell(spellName) then
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[/cast Debug]|r IS combo scaling spell")
                end
                local duration = CleveRoids.CalculateComboScaledDuration and
                                 CleveRoids.CalculateComboScaledDuration(spellName, currentCP)
                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cffcccccc[/cast Debug]|r duration=%s, pfUI=%s, pfUI.api=%s, pfUI.api.libdebuff=%s, debuffs=%s",
                            tostring(duration), tostring(pfUI ~= nil),
                            tostring(pfUI and pfUI.api ~= nil),
                            tostring(pfUI and pfUI.api and pfUI.api.libdebuff ~= nil),
                            tostring(pfUI and pfUI.api and pfUI.api.libdebuff and pfUI.api.libdebuff.debuffs ~= nil))
                    )
                end
                if duration and CleveRoids.ComboPointTracking then
                    -- Remove rank from spell name for pfUI compatibility
                    local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                    -- Populate name-based tracking BEFORE the spell is cast
                    -- This allows pfUI's AddEffect hook to find it
                    CleveRoids.ComboPointTracking[baseName] = {
                        combo_points = currentCP,
                        duration = duration,
                        cast_time = GetTime(),
                        target = UnitName("target") or "Unknown",
                        confirmed = true
                    }
                    if CleveRoids.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cffff00ff[/cast Pre-Tracking]|r Set tracking['%s'] = %ds (%d CP)",
                                baseName, duration, currentCP)
                        )
                    end
                end
            elseif CleveRoids.debug and currentCP > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[/cast Debug]|r NOT a combo scaling spell")
            end
        end
        CleveRoids.Hooks.CAST_SlashCmd(msg)
    end
end

CleveRoids.Hooks.TARGET_SlashCmd = SlashCmdList.TARGET
CleveRoids.TARGET_SlashCmd = function(msg)
    tmsg = CleveRoids.Trim(msg)

    if tmsg ~= "" and not string.find(tmsg, "%[") and not string.find(tmsg, "@") then
        CleveRoids.Hooks.TARGET_SlashCmd(tmsg)
        return
    end

    if CleveRoids.DoTarget(tmsg) then
        if UnitExists("target") then
            return
        end
    end
    CleveRoids.Hooks.TARGET_SlashCmd(msg)
end
SlashCmdList.TARGET = CleveRoids.TARGET_SlashCmd


SLASH_CASTSEQUENCE1 = "/castsequence"
SlashCmdList.CASTSEQUENCE = function(msg)
    msg = CleveRoids.Trim(msg)
    local sequence = CleveRoids.GetSequence(msg)
    if not sequence then return end
    -- if not sequence.active then return end

    CleveRoids.DoCastSequence(sequence)
end


SLASH_RUNMACRO1 = "/runmacro"
SlashCmdList.RUNMACRO = function(msg)
    return CleveRoids.ExecuteMacroByName(CleveRoids.Trim(msg))
end

-- Global RunMacro wrapper for user convenience (delegates to namespaced internal function)
-- This pattern ensures internal logic uses CleveRoids.ExecuteMacroByName and won't break
-- if another addon overwrites the global RunMacro
-- NOTE: When SuperMacro is also loaded, Compatibility/SuperMacro.lua redirects this to
-- SuperMacro_RunMacro so macros go through RunLine (where CRM commands are intercepted)
function RunMacro(name)
    return CleveRoids.ExecuteMacroByName(name)
end

SLASH_RETARGET1 = "/retarget"
SlashCmdList.RETARGET = function(msg)
    CleveRoids.DoRetarget()
end

SLASH_STOPMACRO1 = "/stopmacro"
SlashCmdList.STOPMACRO = function(msg)
    CleveRoids.DoStopMacro(msg)
end

