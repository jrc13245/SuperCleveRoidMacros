--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil

local Extension = CleveRoids.RegisterExtension("sRaidFrames")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension:OnEnter(frame)
    CleveRoids.mouseoverUnit = frame.unit
end

function Extension.OnLoad()
    if arg1 ~= "sRaidFrames" then
        return
    end

    Extension.HookMethod(sRaidFrames, "UnitTooltip", "OnEnter")
end

_G["CleveRoids"] = CleveRoids