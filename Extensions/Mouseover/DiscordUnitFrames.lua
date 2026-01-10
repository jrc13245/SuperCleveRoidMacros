--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("DiscordUnitFrames")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension.OnEnterFrame()
    CleveRoids.SetMouseoverFrom("duf", this.unit)
end

function Extension.OnLeaveFrame()
    CleveRoids.ClearMouseoverFrom("duf")
end

function Extension.OnEnterElement()
    CleveRoids.SetMouseoverFrom("duf", this:GetParent().unit)
end

function Extension.OnLeaveElement()
    CleveRoids.ClearMouseoverFrom("duf")
end

function Extension.OnLoad()
    if arg1 ~= "DiscordUnitFrames" then
        return
    end

    CleveRoids.ClearHooks()
    Extension.Hook("DUF_UnitFrame_OnEnter", "OnEnterFrame")
    Extension.Hook("DUF_UnitFrame_OnLeave", "OnLeaveFrame")

    Extension.Hook("DUF_Element_OnEnter", "OnEnterElement")
    Extension.Hook("DUF_Element_OnLeave", "OnLeaveElement")
end

_G["CleveRoids"] = CleveRoids
