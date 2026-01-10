--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("sRaidFrames")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension:OnEnter(frame)
    CleveRoids.SetMouseoverFrom("sraid", frame.unit)
end

function Extension.OnLeave()
    CleveRoids.ClearMouseoverFrom("sraid")
end

function Extension.OnLoad()
    if arg1 ~= "sRaidFrames" then
        return
    end

    Extension.HookMethod(sRaidFrames, "UnitTooltip", "OnEnter")
    Extension.HookMethod(_G["GameTooltip"], "Hide", "OnLeave")
    Extension.HookMethod(_G["GameTooltip"], "FadeOut", "OnLeave")
end

_G["CleveRoids"] = CleveRoids
