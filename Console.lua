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

SLASH_EQSLOT111 = "/equip11"
SlashCmdList.EQSLOT11 = CleveRoids.DoEquipRing1

SLASH_EQSLOT121 = "/equip12"
SlashCmdList.EQSLOT12 = CleveRoids.DoEquipRing2

SLASH_EQSLOT131 = "/equip13"
SlashCmdList.EQSLOT13 = CleveRoids.DoEquipTrinket1

SLASH_EQSLOT141 = "/equip14"
SlashCmdList.EQSLOT14 = CleveRoids.DoEquipTrinket2

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
    -- Check both event-based flag AND action bar state for reliable detection
    local isAttacking = CleveRoids.CurrentSpell.autoAttack
    if not isAttacking then
        -- Fallback: check action bar state via IsCurrentAction
        local slot = CleveRoids.GetProxyActionSlot(CleveRoids.Localized.Attack)
        if slot and IsCurrentAction(slot) then
            CleveRoids.CurrentSpell.autoAttack = true
            isAttacking = true
        end
    end
    if not isAttacking and not CleveRoids.CurrentSpell.autoAttackLock and UnitExists("target") and UnitCanAttack("player","target") then
        CleveRoids.CurrentSpell.autoAttackLock = true
        CleveRoids.autoAttackLockElapsed = GetTime()
        AttackTarget()
        -- FIX: Immediately set autoAttack flag so subsequent macro lines know attack started
        -- Don't wait for PLAYER_ENTER_COMBAT event which has a delay
        CleveRoids.CurrentSpell.autoAttack = true
        -- FIX: Queue icon update so action bars reflect the new state
        if CleveRoidMacros and CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
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

SLASH_CLEARTARGET1 = "/cleartarget"
SlashCmdList.CLEARTARGET = ClearTarget

----------------------------------
-- HOOK DEFINITIONS START
----------------------------------

-- /cleartarget hook
CleveRoids.Hooks.CLEARTARGET_SlashCmd = SlashCmdList.CLEARTARGET
SlashCmdList.CLEARTARGET = function(msg)
    msg = msg or ""
    if string.find(msg, "%[") then
        -- If conditionals are present, let the function handle it.
        CleveRoids.DoConditionalClearTarget(msg)
    else
        -- If no conditionals, run the original command.
        CleveRoids.Hooks.CLEARTARGET_SlashCmd()
    end
end

-- /startattack hook
CleveRoids.Hooks.STARTATTACK_SlashCmd = SlashCmdList.STARTATTACK
SlashCmdList.STARTATTACK = function(msg)
    if CleveRoids.stopMacroFlag then return end
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
    if CleveRoids.stopMacroFlag then return end
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
    if CleveRoids.stopMacroFlag then return end
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

-- /unqueue hook
CleveRoids.Hooks.UNQUEUE_SlashCmd = SlashCmdList.UNQUEUE
SlashCmdList.UNQUEUE = function(msg)
    if CleveRoids.stopMacroFlag then return end
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
    if CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag then return end
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

SLASH_SKIPMACRO1 = "/skipmacro"
SlashCmdList.SKIPMACRO = function(msg)
    CleveRoids.DoSkipMacro(msg)
end

-- Enable "first action only" mode - stop evaluation after first successful /cast or /use
-- Example:
--   /firstaction
--   /cast [myrawpower:>48] Shred
--   /cast [myrawpower:>40] Claw
-- Result: Only Shred casts if energy >= 48, Claw won't be queued
SLASH_FIRSTACTION1 = "/firstaction"
SlashCmdList.FIRSTACTION = function(msg)
    CleveRoids.DoFirstAction(msg)
end

-- Re-enable multi-queue behavior after /firstaction
-- Use this to restore normal evaluation where multiple casts can queue
-- Example:
--   /firstaction
--   /cast [myrawpower:>48] Shred      -- Priority section
--   /cast [myrawpower:>40] Claw
--   /nofirstaction
--   /cast Tiger's Fury                -- Can queue alongside above
SLASH_NOFIRSTACTION1 = "/nofirstaction"
SlashCmdList.NOFIRSTACTION = function(msg)
    CleveRoids.DoNoFirstAction(msg)
end

-- QuickHeal with conditionals support (requires QuickHeal addon)
-- Usage: /quickheal [conditionals] [target] [type]
-- Examples:
--   /quickheal                     -- Smart heal (auto-select target)
--   /quickheal target              -- Heal current target
--   /quickheal [combat] party      -- Heal party member if in combat
--   /quickheal [mypower:>50] mt    -- Heal tank if mana > 50%
--   /quickheal [threat:<80] hot    -- Apply HoT if threat is low
SLASH_QUICKHEAL1 = "/quickheal"
SLASH_QUICKHEAL2 = "/qh"
SlashCmdList.QUICKHEAL = function(msg)
    CleveRoids.DoQuickHeal(msg)
end

--- Execute QuickHeal with optional conditionals
--- @param msg string The command arguments (conditionals + QuickHeal params)
function CleveRoids.DoQuickHeal(msg)
    -- Check if QuickHeal addon is loaded
    if type(QuickHeal) ~= "function" then
        if not CleveRoids._quickHealErrorShown then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SuperCleveRoidMacros]|r The /quickheal command requires the QuickHeal addon.", 1, 0.5, 0.5)
            CleveRoids._quickHealErrorShown = true
        end
        return
    end

    msg = CleveRoids.Trim(msg or "")

    -- Check if there are conditionals
    if string.find(msg, "^%[") then
        -- Parse the conditionals and remaining args
        local actions = CleveRoids.ParseMsg(msg)

        if not actions or table.getn(actions) == 0 then
            -- No valid actions parsed, just run QuickHeal
            QuickHeal()
            return
        end

        -- Find the first action whose conditionals pass
        for i = 1, table.getn(actions) do
            local action = actions[i]
            if CleveRoids.TestAction(action) then
                -- Conditionals passed - extract the target/type from action args
                local healTarget = nil
                local healType = nil

                if action.args then
                    -- Parse args - could be "target", "party", "mt", "hot", etc.
                    local args = CleveRoids.Trim(action.args)
                    if args ~= "" then
                        -- Check if it's a target or type keyword
                        local lowerArgs = string.lower(args)
                        if lowerArgs == "hot" or lowerArgs == "heal" or lowerArgs == "hs" or lowerArgs == "chainheal" then
                            healType = args
                        else
                            -- Assume it's a target specifier
                            healTarget = args
                        end
                    end
                end

                -- Execute QuickHeal with parsed parameters
                QuickHeal(healTarget, nil, nil, nil)
                return
            end
        end
        -- No conditions matched - don't heal
        return
    else
        -- No conditionals, pass through to QuickHeal directly
        -- Parse basic args: target and/or type
        local args = msg
        if args == "" then
            QuickHeal()
        else
            -- QuickHeal accepts: Target, SpellID, extParam, forceMaxHPS
            -- Common targets: player, target, targettarget, party, mt, nonmt, subgroup
            -- Common types: heal, hot, hs (paladin), chainheal (shaman)
            QuickHeal(args)
        end
    end
end

