--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local CreateFrames = nil
CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil

local Extension = CleveRoids.RegisterExtension("NotGrid")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

function Extension.OnEnter()
    CleveRoids.mouseoverUnit = this.unit
end

function Extension.OnLeave()
    CleveRoids.mouseoverUnit = nil
end

function CleveRoids:NotGrid_CreateFrames()
    CreateFrames(NotGrid); -- call the original

    -- NotGrid stores all of it's frames in the NotGrid.UnitFrames table.
    for k, frame in pairs(NotGrid.UnitFrames) do
        local enter = frame:GetScript("OnEnter")
        local leave = frame:GetScript("OnLeave")

        frame:SetScript("OnEnter", function()
            enter()
            Extension.OnEnter()
        end)

        frame:SetScript("OnLeave", function()
            leave()
            Extension.OnLeave()
        end)
    end
end

function Extension.OnLoad()
    -- NotGrid loads before CleveRoids, so if NotGrid is enabled, then it's global will exist.
    if not NotGrid then
        return
    end
    -- Hooking manually as we need a post hook.
    CreateFrames = NotGrid.CreateFrames
    NotGrid.CreateFrames = CleveRoids.NotGrid_CreateFrames

    Extension.UnregisterEvent("ADDON_LOADED", "Onload")
end

_G["CleveRoids"] = CleveRoids
