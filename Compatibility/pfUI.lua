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

-- Helper function to check for Carnage duration override
-- Returns override duration and timeleft if found, nil otherwise
local function GetCarnageOverride(effect)
    if not effect or not CleveRoids.carnageDurationOverrides then
        return nil, nil
    end

    for spellID, override in pairs(CleveRoids.carnageDurationOverrides) do
        local spellName = SpellInfo(spellID)
        if spellName then
            local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
            if baseName == effect and override.timestamp and (GetTime() - override.timestamp) < 5 then
                local timeleft = override.duration - (GetTime() - override.timestamp)
                if timeleft < 0 then timeleft = 0 end
                return override.duration, timeleft
            end
        end
    end
    return nil, nil
end

-- Hook pfUI's libdebuff to use our combo-aware durations
function Extension.HookPfUILibdebuff()
    if not pfUI or not pfUI.api or not pfUI.api.libdebuff then
        return false
    end

    local pflib = pfUI.api.libdebuff

    -- Hook GetDuration if it exists
    -- pfUI's GetDuration signature: function(effect, rank) where effect is spell NAME
    if pflib.GetDuration and not Extension.pfLibDebuffHooked then
        local originalGetDuration = pflib.GetDuration

        pflib.GetDuration = function(self, effect, rank)
            -- Check for Carnage duration overrides first (highest priority)
            local carnageDuration = GetCarnageOverride(effect)
            if carnageDuration then
                return carnageDuration
            end

            -- Check name-based tracking for fresh combo casts
            if CleveRoids.ComboPointTracking and CleveRoids.ComboPointTracking[effect] then
                local tracking = CleveRoids.ComboPointTracking[effect]
                if tracking.duration and tracking.confirmed and (GetTime() - tracking.cast_time) < 0.5 then
                    return tracking.duration
                end
            end

            return originalGetDuration(self, effect, rank)
        end

        Extension.pfLibDebuffHooked = true
        Extension.DLOG("Hooked pfUI.api.libdebuff.GetDuration for Carnage and combo duration support")
    end

    -- Hook AddEffect if it exists to inject combo-aware durations and enforce rank checking
    if pflib.AddEffect and not Extension.pfLibAddEffectHooked then
        local originalAddEffect = pflib.AddEffect

        pflib.AddEffect = function(self, unit, unitlevel, effect, duration, caster)
            -- RANK CHECKING: Preserve higher rank's remaining time if lower rank was cast
            -- NOTE: 'unit' is a unit NAME (e.g., "Expert Training Dummy"), not a unit ID
            -- Defensive: verify libdebuff is a table, not a function
            if caster == "player" and type(CleveRoids.libdebuff) == "table" and duration and duration > 0 then
                -- Try to find the GUID for this unit name
                local unitGUID = nil

                -- Check if this is the current target
                if UnitName("target") == unit then
                    local _, guid = UnitExists("target")
                    unitGUID = CleveRoids.NormalizeGUID(guid)
                end

                -- If we couldn't match to current target, check guidToName mapping
                if not unitGUID and CleveRoids.libdebuff.guidToName then
                    for guid, name in pairs(CleveRoids.libdebuff.guidToName) do
                        if name == unit then
                            unitGUID = guid
                            break
                        end
                    end
                end

                -- Check if a higher rank of this spell is already active
                if unitGUID and CleveRoids.libdebuff.objects and CleveRoids.libdebuff.objects[unitGUID] then
                    -- Find all spell IDs that match this effect name
                    for spellID, rec in pairs(CleveRoids.libdebuff.objects[unitGUID]) do
                        if rec and rec.start and rec.duration then
                            -- Get spell name for this ID
                            local spellName = SpellInfo(spellID)
                            if spellName then
                                local baseName = string.gsub(spellName, "%s*%(Rank %d+%)", "")
                                if baseName == effect then
                                    -- Same spell - check if still active
                                    local remaining = rec.duration + rec.start - GetTime()
                                    if remaining > 0 then
                                        -- If incoming duration > remaining time, we're trying to add more time
                                        -- This means either a refresh or lower rank cast - preserve existing timer
                                        if duration > remaining then
                                            if Extension.Debug then
                                                DEFAULT_CHAT_FRAME:AddMessage(
                                                    string.format("|cff00aaff[pfUI Rank Preserve]|r %s: Preserving timer (%.1fs remaining vs %.1fs incoming)",
                                                        effect, remaining, duration)
                                                )
                                            end

                                            -- Preserve the existing timer
                                            duration = remaining
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Check for Carnage duration overrides FIRST (highest priority)
            local carnageDuration = GetCarnageOverride(effect)
            if carnageDuration then
                duration = duration or carnageDuration
                caster = caster or "player"  -- Ensure caster is set for UnitOwnDebuff filtering
            end

            -- Check if this is a combo scaling spell by name
            if not duration and CleveRoids.IsComboScalingSpell and CleveRoids.IsComboScalingSpell(effect) then
                if CleveRoids.ComboPointTracking and CleveRoids.ComboPointTracking[effect] then
                    local tracking = CleveRoids.ComboPointTracking[effect]
                    if tracking.duration and tracking.confirmed and (GetTime() - tracking.cast_time) < 0.5 then
                        duration = tracking.duration
                        caster = caster or "player"
                    end
                end
            end

            return originalAddEffect(self, unit, unitlevel, effect, duration, caster)
        end

        Extension.pfLibAddEffectHooked = true
        Extension.DLOG("Hooked pfUI.api.libdebuff.AddEffect for combo duration and rank checking support")
    end

    -- Hook UnitDebuff to return Carnage override duration to display code
    if pflib.UnitDebuff and not Extension.pfLibUnitDebuffHooked then
        local originalUnitDebuff = pflib.UnitDebuff

        pflib.UnitDebuff = function(self, unit, id)
            local effect, rank, texture, stacks, dtype, duration, timeleft, caster = originalUnitDebuff(self, unit, id)

            local carnageDuration, carnageTimeleft = GetCarnageOverride(effect)
            if carnageDuration then
                duration = carnageDuration
                timeleft = carnageTimeleft
            end

            return effect, rank, texture, stacks, dtype, duration, timeleft, caster
        end

        Extension.pfLibUnitDebuffHooked = true
        Extension.DLOG("Hooked pfUI.api.libdebuff.UnitDebuff for Carnage duration display")
    end

    -- Hook UnitOwnDebuff to return Carnage override duration when selfdebuff is enabled
    if pflib.UnitOwnDebuff and not Extension.pfLibUnitOwnDebuffHooked then
        local originalUnitOwnDebuff = pflib.UnitOwnDebuff

        pflib.UnitOwnDebuff = function(self, unit, id)
            local effect, rank, texture, stacks, dtype, duration, timeleft, caster = originalUnitOwnDebuff(self, unit, id)

            local carnageDuration, carnageTimeleft = GetCarnageOverride(effect)
            if carnageDuration then
                duration = carnageDuration
                timeleft = carnageTimeleft
            -- If UnitOwnDebuff returned nil but we have a Carnage override, synthesize from UnitDebuff
            elseif not effect and CleveRoids.carnageDurationOverrides then
                -- Use pflib:UnitDebuff which includes our Carnage override hook
                local baseEffect, baseRank, baseTex, baseStacks, baseDtype, baseDur, baseLeft, _ = pflib:UnitDebuff(unit, id)
                if baseEffect then
                    carnageDuration, carnageTimeleft = GetCarnageOverride(baseEffect)
                    if carnageDuration then
                        return baseEffect, baseRank, baseTex, baseStacks, baseDtype, carnageDuration, carnageTimeleft, "player"
                    end
                end
            end

            return effect, rank, texture, stacks, dtype, duration, timeleft, caster
        end

        Extension.pfLibUnitOwnDebuffHooked = true
        Extension.DLOG("Hooked pfUI.api.libdebuff.UnitOwnDebuff for Carnage duration display (selfdebuff mode)")
    end

    return Extension.pfLibDebuffHooked or Extension.pfLibAddEffectHooked or Extension.pfLibUnitDebuffHooked or Extension.pfLibUnitOwnDebuffHooked
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

-- Register action event handler for pfUI button updates
function Extension.RegisterPfUIActionEventHandler()
    if not pfUI or Extension.actionHandlerRegistered then
        return
    end

    -- Register a handler that will be called whenever CleveRoids updates macro states
    if CleveRoids.RegisterActionEventHandler then
        Extension.DLOG("Registering pfUI action event handler")
        CleveRoids.RegisterActionEventHandler(function(slot, event, ...)
            local button = pfUI.bars and pfUI.bars.buttons and pfUI.bars.buttons[slot]

            if Extension.Debug then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "|cff00ff00[pfUI CD]|r slot=%s event=%s button=%s cd=%s",
                    tostring(slot), tostring(event),
                    button and "yes" or "no",
                    (button and button.cd) and "yes" or "no"
                ))
            end

            -- For slot change events, do a full button update
            if event == "ACTIONBAR_SLOT_CHANGED" then
                -- Trigger pfUI's button update for this slot
                -- Mark the slot for update in pfUI's cache, which will be processed on next OnUpdate
                if pfUI.bars and pfUI.bars.update then
                    pfUI.bars.update[slot] = true
                end

                -- Also directly call ButtonFullUpdate if the button exists
                if button and pfUI.bars.ButtonFullUpdate then
                    pfUI.bars.ButtonFullUpdate(button)
                end
            end

            -- COOLDOWN FIX: Always update cooldowns explicitly
            -- pfUI's macro scanner caches spell info and doesn't know about
            -- CleveRoids' conditional spell changes. Manually update the cooldown
            -- using the active spell from CleveRoids.
            -- Note: pfUI uses button.cd for cooldown frame (not button.cooldown)
            if button and button.cd then
                local start, duration, enable
                local spellSlot, bookType = CleveRoids.GetActionSpellSlot(slot)

                if spellSlot and bookType then
                    -- Active spell found - get its cooldown
                    start, duration, enable = GetSpellCooldown(spellSlot, bookType)
                else
                    -- No active spell - check for item cooldown
                    local actions = CleveRoids.GetAction(slot)
                    local actionToCheck = actions and (actions.active or actions.tooltip)
                    if actionToCheck and actionToCheck.item then
                        local item = actionToCheck.item
                        if item.bagID and item.slot then
                            start, duration, enable = GetContainerItemCooldown(item.bagID, item.slot)
                        elseif item.inventoryID then
                            start, duration, enable = GetInventoryItemCooldown("player", item.inventoryID)
                        end
                    elseif actionToCheck then
                        -- Check for equipment slot (e.g., trinket)
                        local slotId = tonumber(actionToCheck.action)
                        if slotId and slotId >= 1 and slotId <= 19 then
                            start, duration, enable = GetInventoryItemCooldown("player", slotId)
                        end
                    end

                    -- Fallback: use the hooked GetActionCooldown for non-CleveRoids actions
                    if not start then
                        start, duration, enable = GetActionCooldown(slot)
                    end
                end

                -- Apply cooldown if we have valid data
                -- Ensure enable is at least 1 (0 can hide the cooldown)
                if start and duration then
                    CooldownFrame_SetTimer(button.cd, start, duration, (enable and enable > 0) and enable or 1)
                end
            end
        end)

        Extension.actionHandlerRegistered = true
        Extension.DLOG("Registered action event handler for pfUI button updates")
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

        -- Register action event handler for button updates
        Extension.RegisterPfUIActionEventHandler()

        if Extension.macrotweakLoaded then
            Extension.DLOG("pfUI macrotweak module detected")

            -- Override slash commands to ensure CleveRoids' conditional support works
            Extension.OverridePfUISlashCommands()

            -- Handle SendChatMessage hook
            Extension.HandleSendChatMessageHook()
        end
    end
end

-- ============================================================================
-- API Functions for pfUI Integration
-- These functions allow pfUI's actionbar module to query CleveRoids for
-- the active spell data, enabling proper cooldown/tooltip/icon display.
-- ============================================================================

-- Get the spell slot and book type for a given action slot
-- Returns: spellSlot, bookType (or nil, nil if not a CleveRoids-managed macro)
-- This is used by pfUI's ButtonMacroScan to get spell data for macros
function CleveRoids.GetActionSpellSlot(actionSlot)
    if not actionSlot then return nil, nil end

    local actions = CleveRoids.GetAction(actionSlot)
    if not actions then return nil, nil end

    -- Check if we have an active action with spell data
    if actions.active and actions.active.spell then
        local spell = actions.active.spell
        if spell.spellSlot and spell.bookType then
            return spell.spellSlot, spell.bookType
        end
    end

    -- Fallback: check tooltip action
    if actions.tooltip then
        local action = actions.tooltip
        if action.spell and action.spell.spellSlot and action.spell.bookType then
            return action.spell.spellSlot, action.spell.bookType
        end
    end

    return nil, nil
end

-- Get the spell slot and book type for a given macro name
-- Returns: spellSlot, bookType (or nil, nil if not found)
function CleveRoids.GetMacroSpellSlot(macroName)
    if not macroName then return nil, nil end

    local macro = CleveRoids.Macros[macroName]
    if not macro or not macro.actions then return nil, nil end

    local actions = macro.actions

    -- Check if we have an active action with spell data
    if actions.active and actions.active.spell then
        local spell = actions.active.spell
        if spell.spellSlot and spell.bookType then
            return spell.spellSlot, spell.bookType
        end
    end

    -- Fallback: check tooltip action
    if actions.tooltip then
        local action = actions.tooltip
        if action.spell and action.spell.spellSlot and action.spell.bookType then
            return action.spell.spellSlot, action.spell.bookType
        end
    end

    return nil, nil
end

-- Check if CleveRoids is managing a given action slot
-- Returns: true if CleveRoids has parsed this macro, false otherwise
function CleveRoids.IsManagedAction(actionSlot)
    if not actionSlot then return false end
    local actions = CleveRoids.GetAction(actionSlot)
    return actions ~= nil and (actions.tooltip ~= nil or actions.list ~= nil)
end

-- Check if CleveRoids is managing a given macro by name
-- Returns: true if CleveRoids has parsed this macro, false otherwise
function CleveRoids.IsManagedMacro(macroName)
    if not macroName then return false end
    return CleveRoids.Macros[macroName] ~= nil
end

-- Get the active spell name for a given action slot (for debugging/display)
-- Returns: spellName (or nil if not found)
function CleveRoids.GetActionActiveSpellName(actionSlot)
    if not actionSlot then return nil end

    local actions = CleveRoids.GetAction(actionSlot)
    if not actions then return nil end

    if actions.active and actions.active.action then
        return actions.active.action
    end

    if actions.tooltip and actions.tooltip.action then
        return actions.tooltip.action
    end

    return nil
end

function Extension.OnLoad()
    Extension.DLOG("Extension pfUI Loaded.")
    Extension.HookMethod(CleveRoids, "GetFocusName", "FocusNameHook", true)

    -- Export extension for external access
    CleveRoids.Compatibility_pfUI = Extension

    -- Initial compatibility check
    Extension.SetupCompatibility()

    -- Add slash command to toggle pfUI cooldown debug
    -- Usage: /pfuicd to toggle debug mode
    SlashCmdList["PFUICD"] = function()
        Extension.Debug = not Extension.Debug
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfUI Compat]|r Debug mode: " .. (Extension.Debug and "ON" or "OFF"))
        if Extension.Debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfUI Compat]|r Handler registered: " .. (Extension.actionHandlerRegistered and "YES" or "NO"))
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfUI Compat]|r pfUI detected: " .. (Extension.pfUILoaded and "YES" or "NO"))
            if pfUI and pfUI.bars then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfUI Compat]|r pfUI.bars exists: YES")
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfUI Compat]|r pfUI.bars.buttons: " .. (pfUI.bars.buttons and "YES" or "NO"))
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[pfUI Compat]|r pfUI.bars exists: NO")
            end
        end
    end
    SLASH_PFUICD1 = "/pfuicd"
end

function Extension.ADDON_LOADED()
    -- Check if pfUI just loaded AND the global actually exists
    -- (another addon could be named "pfUI" without being the real UI framework)
    if arg1 == "pfUI" and pfUI then
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

    -- Print startup status only if pfUI global exists and compatibility was set up
    if Extension.pfUILoaded and pfUI then
        local statusMsg = "|cff00ff00[SCRM]|r pfUI compatibility loaded"
        if CleveRoids.hasPfUI76 then
            statusMsg = statusMsg .. " (7.6+ GUID cast tracking)"
        end
        -- statusMsg = statusMsg .. ". Use /pfuicd for debug."
        DEFAULT_CHAT_FRAME:AddMessage(statusMsg)
        if not Extension.actionHandlerRegistered then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[SCRM]|r WARNING: pfUI action handler NOT registered!")
        end
    end
end

-- Utility: Schedule a delayed function call (if not already defined)
if not CleveRoids.ScheduleTimer then
    local timerFrame = CreateFrame("Frame")
    local timers = {}

    timerFrame:SetScript("OnUpdate", function()
        -- Prevent SuperWoW API calls during shutdown (crash prevention)
        if CleveRoids.isShuttingDown then return end

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
