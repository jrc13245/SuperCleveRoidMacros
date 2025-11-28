--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("MacroLengthWarn")

-- Set a global flag so we can check if this file loaded
CleveRoids.MacroLengthWarnLoaded = true

-- Maximum line length for macros (including spaces)
local MAX_LINE_LENGTH = 261

-- Store original functions
local edit_orig = nil
local macroframe_save_orig = nil

-- Validation function - returns true if valid, false if too long
local function ValidateMacroBody(body, macroName)
    if not body then
        return true -- No body means it's valid
    end

    for line in string.gfind(body, "([^\n]+)") do
        local lineLen = string.len(line)
        if lineLen > MAX_LINE_LENGTH then
            local name = macroName or "Unknown"
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffff0000ERROR:|r A line in the macro < |cffffffff%s|r > is |cffff0000%d characters|r long (max: |cffffffff%d|r).",
                name, lineLen, MAX_LINE_LENGTH
            ), 1, 0.82, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000This will CRASH the client and may DELETE all macros!|r Macro NOT saved.", 1, 0.82, 0)
            DEFAULT_CHAT_FRAME:AddMessage("Line: |cffffffff" .. string.sub(line, 1, 100) .. "...|r", 1, 1, 1)
            return false
        end
    end
    return true
end

-- Hook for EditMacro API function
function Extension.SafeEditMacro(macro_id, x, y, body)
    if CleveRoids.MacroLengthDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r EditMacro called for ID: " .. tostring(macro_id))
    end

    -- SuperMacro compatibility - bypass validation if SuperMacro is handling it
    if SuperMacroFrame ~= nil and x and y and body == nil then
        if edit_orig then edit_orig(macro_id, x, y, body) end
        return
    end

    -- Get macro name for error messages
    local macroName = GetMacroInfo(macro_id)

    -- Validate the macro body
    if not ValidateMacroBody(body, macroName) then
        -- Validation failed - do NOT save
        if CleveRoids.MacroLengthDebug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r BLOCKED save - line too long")
        end
        return
    end

    -- Validation passed - call original
    if edit_orig then
        if CleveRoids.MacroLengthDebug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r Validation passed, saving...")
        end
        edit_orig(macro_id, x, y, body)
    end
end

-- Hook for MacroFrame_SaveMacro (Blizzard UI function)
function Extension.SafeMacroFrameSave()
    if CleveRoids.MacroLengthDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r MacroFrame_SaveMacro called")
    end

    -- This is called by the macro UI, so we need to get the text from the edit box
    if MacroFrameText and MacroFrame.selectedMacro then
        local body = MacroFrameText:GetText()
        local macroName = GetMacroInfo(MacroFrame.selectedMacro)

        -- Validate before allowing the save
        if not ValidateMacroBody(body, macroName) then
            if CleveRoids.MacroLengthDebug then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r BLOCKED MacroFrame save")
            end
            -- Don't call original - block the save
            return
        end
    end

    -- Validation passed or no text to validate
    if macroframe_save_orig then
        if CleveRoids.MacroLengthDebug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r MacroFrame validation passed")
        end
        macroframe_save_orig()
    end
end

-- Install hooks when macro frame loads
function Extension.OnMacroFrameLoad()
    if Extension.macroFrameHooked then
        return
    end

    if CleveRoids.MacroLengthDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r Hooking MacroFrame_SaveMacro")
    end

    -- Hook MacroFrame_SaveMacro if it exists
    if MacroFrame_SaveMacro then
        macroframe_save_orig = MacroFrame_SaveMacro
        MacroFrame_SaveMacro = function(...)
            local success, err = pcall(Extension.SafeMacroFrameSave, unpack(arg))
            if not success then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MacroLengthWarn]|r MacroFrame hook error: " .. tostring(err))
                -- Call original on error
                if macroframe_save_orig then
                    return macroframe_save_orig(unpack(arg))
                end
            end
        end
        Extension.macroFrameHooked = true

        if CleveRoids.MacroLengthDebug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r MacroFrame_SaveMacro hooked successfully")
        end
    end
end

function Extension.OnAddonLoaded()
    if arg1 == "Blizzard_MacroUI" then
        Extension.OnMacroFrameLoad()
    end
end

function Extension.OnLoad()
    -- Schedule messages to show after UI is ready
    local function ShowMessages()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r Extension loaded (Max line length: " .. MAX_LINE_LENGTH .. ")")

        if not EditMacro then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MacroLengthWarn]|r ERROR: EditMacro function not found!")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r EditMacro hook: " .. (edit_orig and "SUCCESS" or "FAILED"))
        end

        if MacroFrame_SaveMacro then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r MacroFrame_SaveMacro hook: " .. (Extension.macroFrameHooked and "SUCCESS" or "PENDING"))
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[MacroLengthWarn]|r MacroFrame_SaveMacro: Will hook when Blizzard UI loads")
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[MacroLengthWarn]|r Use /cleveroid macrodebug to toggle debug output")
    end

    -- Check if EditMacro exists
    if not EditMacro then
        CleveRoids.Print("[MacroLengthWarn] ERROR: EditMacro not found!")
        return
    end

    -- Capture and hook EditMacro immediately with error protection
    edit_orig = EditMacro
    EditMacro = function(...)
        local success, err = pcall(Extension.SafeEditMacro, unpack(arg))
        if not success then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[MacroLengthWarn]|r Hook error: " .. tostring(err))
            -- Call original on error to prevent breaking macros
            if edit_orig then
                return edit_orig(unpack(arg))
            end
        end
    end

    -- Listen for macro UI loading
    Extension.RegisterEvent("ADDON_LOADED", "OnAddonLoaded")

    -- Also try to hook MacroFrame_SaveMacro if it already exists
    if MacroFrame_SaveMacro then
        Extension.OnMacroFrameLoad()
    end

    -- Register PLAYER_LOGIN to show status messages
    Extension.RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")

    -- Store the message function for later
    Extension.ShowMessages = ShowMessages
end

function Extension.OnPlayerLogin()
    -- Status messages disabled by default - use /cleveroid macrostatus to check
    -- if Extension.ShowMessages then
    --     Extension.ShowMessages()
    -- end
end

_G["CleveRoids"] = CleveRoids