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

-- Main compatibility check and setup
function Extension.SetupCompatibility()
    Extension.pfUILoaded = (pfUI ~= nil)
    Extension.macrotweakLoaded = Extension.IsPfUIMacrotweakLoaded()

    if Extension.pfUILoaded then
        Extension.DLOG("pfUI detected")

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
