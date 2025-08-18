--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
-- CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil

local Extension = CleveRoids.RegisterExtension("MacroLengthWarn")

local edit_orig = EditMacro

function Extension.SafeEditMacro(macro_id, x, y, body)
    if SuperMacroFrame ~= nil and x and y and body == nil then
        -- super will handle macro
        edit_orig(macro_id, x, y, body)
        return
    end

    if not body then -- can't be too long without a body
        edit_orig(macro_id, x, y, body)
        return
    end

    for line in string.gfind(body, "([^\n]+)") do
        if string.len(line) > 261 then
            DEFAULT_CHAT_FRAME:AddMessage("ERROR: A line in the macro < |cffffffff"..GetMacroInfo(macro_id).."|r > is too long and will |cffff0000CRASH|r the client and may |cffff0000DELETE|r all macros on exit! Max line length: |cffffffff261|r",1,1,0)
            return
        end
    end
    edit_orig(macro_id, x, y, body)
end


function Extension.OnLoad()
    -- how do I use this with a global function?
    -- CleveRoids.RegisterMethodHook("MacroLengthWarn", _G, "EditMacro", "SafeEditMacro", true)
    EditMacro = Extension.SafeEditMacro
end

_G["CleveRoids"] = CleveRoids