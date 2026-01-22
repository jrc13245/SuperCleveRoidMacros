--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    Dragonflight3 mouseover support.
    Hooks into Dragonflight3's custom unit frames.

    Dragonflight3 uses the DF global namespace.
    Frame naming pattern: DF_<Unit>Frame (e.g., DF_PlayerFrame, DF_TargetFrame)
    Each frame has a .unit property containing the unit ID.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("Dragonflight3")
Extension.RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedInit")

local hookedFrames = {}

function Extension.HookFrame(frame)
    if not frame or hookedFrames[frame] then return end

    local origOnEnter = frame:GetScript("OnEnter")
    local origOnLeave = frame:GetScript("OnLeave")

    frame:SetScript("OnEnter", function()
        local u = this.unit
        if u then
            CleveRoids.SetMouseoverFrom("df3", u)
        end
        if origOnEnter then origOnEnter() end
    end)

    frame:SetScript("OnLeave", function()
        CleveRoids.ClearMouseoverFrom("df3")
        CleveRoids.ClearMouseoverFrom("native")
        if origOnLeave then origOnLeave() end
    end)

    hookedFrames[frame] = true
end

function Extension.HookAllFrames()
    -- Dragonflight3 frame naming: DF_<Unit>Frame
    -- Unit names are capitalized: player -> Player, party1 -> Party1
    local units = {
        "Player", "Target", "Targettarget", "Pet", "Pettarget"
    }

    for _, unit in ipairs(units) do
        local frame = _G["DF_" .. unit .. "Frame"]
        if frame then
            Extension.HookFrame(frame)
        end
    end

    -- Party frames: DF_Party1Frame through DF_Party4Frame
    for i = 1, 4 do
        local frame = _G["DF_Party" .. i .. "Frame"]
        if frame then
            Extension.HookFrame(frame)
        end
    end
end

function Extension.DelayedInit()
    -- Check if Dragonflight3 is loaded
    if not DF then
        return
    end

    Extension.HookAllFrames()
end

function Extension.OnLoad()
    -- Nothing needed here, we use DelayedInit
end

_G["CleveRoids"] = CleveRoids
