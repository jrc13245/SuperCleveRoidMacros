--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
CleveRoids.mouseoverUnit = CleveRoids.mouseoverUnit or nil

local Extension = CleveRoids.RegisterExtension("FocusFrame")

function Extension.RegisterMouseoverForFrame(frame)
    local onenter = frame:GetScript("OnEnter")
    local onleave = frame:GetScript("OnLeave")

    frame:SetScript("OnEnter", function()
        CleveRoids.mouseoverUnit = "focus"
        if onenter then
            onenter()
        end
    end)

    frame:SetScript("OnLeave", function()
        CleveRoids.mouseoverUnit = nil
        if onleave then
            onleave()
        end
    end)
end

function Extension.OnLoad()
    if not FocusFrameHealthBar
        or not FocusFrameManaBar
        or not FocusFrameTextureFrame
        or not FocusFrame then
        return
    end

    Extension.RegisterMouseoverForFrame(FocusFrameHealthBar)
    Extension.RegisterMouseoverForFrame(FocusFrameManaBar)
    Extension.RegisterMouseoverForFrame(FocusFrameTextureFrame)
    Extension.RegisterMouseoverForFrame(FocusFrame)
end