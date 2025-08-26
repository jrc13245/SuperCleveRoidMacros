-- CleveRoidMacros/Compatibility/SuperMacro.lua
-- Makes SuperMacro's Super tab play nicely with CleveRoidMacros conditionals.

local _G = _G or getfenv(0)
local CRM = _G.CleveRoids or {}
_G.CleveRoids = CRM

local function install_supermacro_hook()
    if CRM.SM_RunLineHooked then return end
    if type(_G.RunLine) ~= "function" then return end

    -- Build the map of commands we want CRM to execute for bracketed lines.
    local hooks = {
        cast         = { action = CRM.DoCast },
        target       = { action = CRM.DoTarget },
        use          = { action = CRM.DoUse },
        castsequence = { action = CRM.DoCastSequence },
    }

    CRM.Hooks = CRM.Hooks or {}
    CRM.Hooks.RunLine = CRM.Hooks.RunLine or _G.RunLine

    _G.RunLine = function(...)
        for i = 1, arg.n do
            local text = arg[i]
            -- Respect /stopmacro from CRM
            if CRM.stopmacro then
                CRM.stopmacro = false
                return true
            end

            local handled = false
            if type(text) == "string" then
                -- Look for "/<cmd>  [ ... " or "/<cmd>  !..."
                for cmd, def in pairs(hooks) do
                    local b, e = string.find(text, "^/" .. cmd .. "%s+[!%[]")
                    if b then
                        local msg = string.sub(text, e)          -- keep the leading [ or !
                        -- trim space just in case
                        msg = string.gsub(msg, "^%s+", "")
                        -- Hand off to CRM's executor (e.g., DoCast), which knows how to evaluate conditionals
                        pcall(def.action, msg)
                        handled = true
                        break
                    end
                end
            end

            if not handled then
                -- Default behavior (lets SuperMacro process non-conditional lines)
                CRM.Hooks.RunLine(text)
            end
        end
    end

    CRM.SM_RunLineHooked = true
end

-- Install after either addon is ready (order-agnostic)
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "SuperMacro" or addon == "CleveRoidMacros" then
            install_supermacro_hook()
        end
    else -- PLAYER_LOGIN as a final safety net
        install_supermacro_hook()
    end
end)
