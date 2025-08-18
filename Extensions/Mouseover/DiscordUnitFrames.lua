--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil

local Extension = CleveRoids.RegisterExtension("DiscordUnitFrames")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension.OnEnterFrame()
    CleveRoids.mouseoverUnit = this.unit
end

function Extension.OnLeaveFrame()
    CleveRoids.mouseoverUnit = nil
end

function Extension.OnEnterElement()
    CleveRoids.mouseoverUnit = this:GetParent().unit
end

function Extension.OnLeaveElement()
    CleveRoids.mouseoverUnit = nil
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