local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("Compatibility_pfUI")
Extension.RegisterEvent("ADDON_LOADED", "ADDON_LOADED")
Extension.RegisterEvent("PLAYER_LOGIN", "PLAYER_LOGIN")
Extension.Debug = false

-- Track pfUI state
Extension.pfUILoaded = false
Extension.macrotweakLoaded = false
Extension.slashCommandsOverridden = false

function Extension.RunMacro(name)
    CleveRoids.ExecuteMacroByName(name)
end

function Extension.DLOG(msg)
    if Extension.Debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffcccc33[R]: |cffffff55" .. ( msg ))
    end
end

function Extension.FocusNameHook()
    local hook = Extension.internal.memberHooks[CleveRoids]["GetFocusName"]
    local target = hook.original()

    if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.unitname then
        target = pfUI.uf.focus.unitname
    end

    --Extension.DLOG(target)

    return target
end

-- Check if pfUI's macrotweak module is loaded
function Extension.IsPfUIMacrotweakLoaded()
    if not pfUI then return false end

    -- pfUI loads modules and stores them in pfUI.modules
    if pfUI.modules and pfUI.modules.macrotweak then
        return true
    end

    -- Also check if the slash commands exist with pfUI's pattern
    if SlashCmdList.PFUSE or SlashCmdList.PFEQUIP then
        return true
    end

    return false
end

-- Override pfUI's /use and /equip with CleveRoids versions
function Extension.OverridePfUISlashCommands()
    if Extension.slashCommandsOverridden then return end

    -- Save pfUI's original handlers as fallbacks
    if SlashCmdList.PFUSE then
        CleveRoids.Hooks.PFUI_USE = SlashCmdList.PFUSE
    end
    if SlashCmdList.PFEQUIP then
        CleveRoids.Hooks.PFUI_EQUIP = SlashCmdList.PFEQUIP
    end

    -- Override with CleveRoids' conditional-aware handlers
    SlashCmdList.USE = CleveRoids.DoUse
    SlashCmdList.EQUIP = CleveRoids.DoUse
    SlashCmdList.PFUSE = CleveRoids.DoUse
    SlashCmdList.PFEQUIP = CleveRoids.DoUse
    SlashCmdList.SMEQUIP = CleveRoids.DoUse

    Extension.slashCommandsOverridden = true

    Extension.DLOG("Overrode /use and /equip commands for conditional support")
end

-- Check and handle SendChatMessage hook compatibility
function Extension.HandleSendChatMessageHook()
    -- Check if SendChatMessage has already been hooked by something else
    local currentHook = _G.SendChatMessage
    local originalSendChat = CleveRoids.Hooks.SendChatMessage

    if not originalSendChat then return end

    -- If pfUI already hooked SendChatMessage, we need to chain properly
    if currentHook and currentHook ~= originalSendChat then
        -- pfUI's hook is in place, let it handle #showtooltip filtering
        -- Our hook is redundant, so we can skip it
        Extension.DLOG("pfUI's SendChatMessage hook detected, using pfUI's filtering")
    end
end

-- Hook pfUI's libdebuff to use our combo-aware durations
function Extension.HookPfUILibdebuff()
    if not pfUI or not pfUI.api or not pfUI.api.libdebuff then
        return false
    end

    local pflib = pfUI.api.libdebuff

    -- Hook GetDuration if it exists
    if pflib.GetDuration and not Extension.pfLibDebuffHooked then
        local originalGetDuration = pflib.GetDuration

        pflib.GetDuration = function(self, spellID, casterGUID, comboPoints)
            -- Check if this is a combo scaling spell first
            if CleveRoids.IsComboScalingSpellID and CleveRoids.IsComboScalingSpellID(spellID) then
                -- If combo points provided, check learned combo durations
                if comboPoints and CleveRoids_ComboDurations and CleveRoids_ComboDurations[spellID] then
                    local comboDur = CleveRoids_ComboDurations[spellID][comboPoints]
                    if comboDur and comboDur > 0 then
                        if CleveRoids.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(
                                string.format("|cff00ff00[pfUI Hook]|r Returning %ds for spell %d at %d CP",
                                    comboDur, spellID, comboPoints)
                            )
                        end
                        return comboDur
                    end
                end

                -- Fallback: check for highest learned combo duration
                if CleveRoids_ComboDurations and CleveRoids_ComboDurations[spellID] then
                    for cp = 5, 1, -1 do
                        if CleveRoids_ComboDurations[spellID][cp] then
                            if CleveRoids.debug then
                                DEFAULT_CHAT_FRAME:AddMessage(
                                    string.format("|cff00ff00[pfUI Hook]|r Returning %ds for spell %d (fallback %d CP)",
                                        CleveRoids_ComboDurations[spellID][cp], spellID, cp)
                                )
                            end
                            return CleveRoids_ComboDurations[spellID][cp]
                        end
                    end
                end
            end

            -- Not a combo spell or no learned duration, use original
            return originalGetDuration(self, spellID, casterGUID, comboPoints)
        end

        Extension.pfLibDebuffHooked = true
        Extension.DLOG("Hooked pfUI.api.libdebuff.GetDuration for combo duration support")
    end

    -- Hook AddEffect if it exists to inject combo-aware durations
    if pflib.AddEffect and not Extension.pfLibAddEffectHooked then
        local originalAddEffect = pflib.AddEffect

        pflib.AddEffect = function(self, unit, unitlevel, effect, duration, caster)
            -- effect is a spell name, not ID
            -- Check if this is a combo scaling spell by name
            if CleveRoids.IsComboScalingSpell and CleveRoids.IsComboScalingSpell(effect) then
                -- Use name-based tracking which is populated BEFORE pfUI's AddEffect
                if CleveRoids.ComboPointTracking and CleveRoids.ComboPointTracking[effect] then
                    local tracking = CleveRoids.ComboPointTracking[effect]
                    if tracking.duration and (GetTime() - tracking.cast_time) < 0.5 then
                        duration = tracking.duration
                        if CleveRoids.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(
                                string.format("|cff00ff00[pfUI AddEffect Hook]|r Overriding %s duration to %ds (from name tracking)",
                                    effect, duration)
                            )
                        end
                    end
                end
            end

            return originalAddEffect(self, unit, unitlevel, effect, duration, caster)
        end

        Extension.pfLibAddEffectHooked = true
        Extension.DLOG("Hooked pfUI.api.libdebuff.AddEffect for combo duration support")
    end

    return Extension.pfLibDebuffHooked or Extension.pfLibAddEffectHooked
end

-- Synchronize combo durations to pfUI's libdebuff objects
function Extension.SyncComboDurationToPfUI(guid, spellID, duration)
    if not pfUI or not pfUI.api or not pfUI.api.libdebuff then
        return
    end

    -- Get unit name from GUID
    local unitName = nil
    local unitLevel = 0

    -- Check if this is the current target
    local _, targetGUID = UnitExists("target")
    if targetGUID == guid then
        unitName = UnitName("target")
        unitLevel = UnitLevel("target") or 0
    end

    -- If we couldn't find the unit, use GUID to name mapping from libdebuff
    if not unitName and CleveRoids.libdebuff and CleveRoids.libdebuff.guidToName then
        unitName = CleveRoids.libdebuff.guidToName[guid]
        -- Default to level 0 if we don't have the unit targeted
        unitLevel = 0
    end

    if not unitName then
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[pfUI Sync]|r Could not find unit name for GUID")
        end
        return
    end

    -- Get spell name from spell ID
    local spellName = SpellInfo(spellID)
    if not spellName then
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[pfUI Sync]|r Could not find spell name for ID " .. spellID)
        end
        return
    end

    -- Remove rank from spell name to match pfUI's format
    local effectName = string.gsub(spellName, "%s*%(Rank %d+%)", "")

    -- Update pfUI's stored debuff duration
    local pflib = pfUI.api.libdebuff
    if pflib.objects and pflib.objects[unitName] then
        -- Try both the specific level and level 0 (fallback)
        for _, level in ipairs({unitLevel, 0}) do
            if pflib.objects[unitName][level] and pflib.objects[unitName][level][effectName] then
                local old_duration = pflib.objects[unitName][level][effectName].duration
                pflib.objects[unitName][level][effectName].duration = duration

                if CleveRoids.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("|cff00ffaa[pfUI Sync]|r Updated %s on %s (L%d): %ds -> %ds",
                            effectName, unitName, level, old_duration or 0, duration)
                    )
                end
                return
            end
        end
    end

    if CleveRoids.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffaaaa00[pfUI Sync]|r Effect not found in pfUI storage: %s on %s",
                effectName, unitName)
        )
    end
end

-- Main compatibility check and setup
function Extension.SetupCompatibility()
    Extension.pfUILoaded = (pfUI ~= nil)
    Extension.macrotweakLoaded = Extension.IsPfUIMacrotweakLoaded()

    if Extension.pfUILoaded then
        Extension.DLOG("pfUI detected")

        -- Hook libdebuff for combo duration support
        Extension.HookPfUILibdebuff()

        if Extension.macrotweakLoaded then
            Extension.DLOG("pfUI macrotweak module detected")

            -- Override slash commands to ensure CleveRoids' conditional support works
            Extension.OverridePfUISlashCommands()

            -- Handle SendChatMessage hook
            Extension.HandleSendChatMessageHook()
        end
    end
end

function Extension.OnLoad()
    Extension.DLOG("Extension pfUI Loaded.")
    Extension.HookMethod(CleveRoids, "GetFocusName", "FocusNameHook", true)

    -- Export extension for external access
    CleveRoids.Compatibility_pfUI = Extension

    -- Initial compatibility check
    Extension.SetupCompatibility()
end

function Extension.ADDON_LOADED()
    -- Check if pfUI just loaded
    if arg1 == "pfUI" then
        Extension.pfUILoaded = true
        -- pfUI modules load after ADDON_LOADED, so schedule a check
        if CleveRoids.ScheduleTimer then
            CleveRoids.ScheduleTimer(function()
                Extension.SetupCompatibility()
            end, 0.5)
        end
    end
end

function Extension.PLAYER_LOGIN()
    -- Final check after everything is loaded
    Extension.SetupCompatibility()
end

-- Utility: Schedule a delayed function call (if not already defined)
if not CleveRoids.ScheduleTimer then
    local timerFrame = CreateFrame("Frame")
    local timers = {}

    timerFrame:SetScript("OnUpdate", function()
        local time = GetTime()
        for i = table.getn(timers), 1, -1 do
            local timer = timers[i]
            if time >= timer.time then
                timer.func()
                table.remove(timers, i)
            end
        end
    end)

    CleveRoids.ScheduleTimer = function(func, delay)
        table.insert(timers, {
            func = func,
            time = GetTime() + delay
        })
    end
end

_G["CleveRoids"] = CleveRoids
