--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    LunaUnitFrames mouseover support.
    LunaUnitFrames already has SuperWoW integration, but we hook to ensure
    our priority system works correctly with other addons.

    Frame names: LUFUnit<unitName> for single units, LUFHeader<groupType> for groups
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("LunaUnitFrames")
Extension.RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedInit")

-- Track which frames we've hooked
local hookedFrames = {}

function Extension.HookFrame(frame)
    if not frame or hookedFrames[frame] then return end

    local onEnter = frame:GetScript("OnEnter")
    local onLeave = frame:GetScript("OnLeave")

    frame:SetScript("OnEnter", function()
        if this.unit then
            CleveRoids.SetMouseoverFrom("luna", this.unit)
        end
        if onEnter then onEnter() end
    end)

    frame:SetScript("OnLeave", function()
        CleveRoids.ClearMouseoverFrom("luna")
        if onLeave then onLeave() end
    end)

    hookedFrames[frame] = true
end

function Extension.HookAllFrames()
    -- Hook single unit frames
    local singleUnits = { "player", "target", "pet", "pettarget", "targettarget", "targettargettarget", "focus", "focustarget" }
    for _, unit in ipairs(singleUnits) do
        local frame = _G["LUFUnit" .. unit]
        if frame then
            Extension.HookFrame(frame)
        end
    end

    -- Hook party frames (LUFHeaderparty children)
    local partyHeader = _G["LUFHeaderparty"]
    if partyHeader then
        for i = 1, 4 do
            local frame = _G["LUFHeaderparty" .. i] or (partyHeader["unit" .. i])
            if frame then
                Extension.HookFrame(frame)
            end
        end
    end

    -- Hook party target frames
    local partyTargetHeader = _G["LUFHeaderpartytarget"]
    if partyTargetHeader then
        for i = 1, 4 do
            local frame = _G["LUFHeaderpartytarget" .. i]
            if frame then
                Extension.HookFrame(frame)
            end
        end
    end

    -- Hook party pet frames
    local partyPetHeader = _G["LUFHeaderpartypet"]
    if partyPetHeader then
        for i = 1, 4 do
            local frame = _G["LUFHeaderpartypet" .. i]
            if frame then
                Extension.HookFrame(frame)
            end
        end
    end

    -- Hook raid frames (LUFHeaderraid1 through LUFHeaderraid9)
    for raidGroup = 1, 9 do
        local raidHeader = _G["LUFHeaderraid" .. raidGroup]
        if raidHeader then
            for i = 1, 40 do
                local frame = _G["LUFHeaderraid" .. raidGroup .. "UnitButton" .. i]
                if frame then
                    Extension.HookFrame(frame)
                end
            end
        end
    end
end

function Extension.DelayedInit()
    -- Check if LunaUF is loaded
    if not LunaUF then
        return
    end

    -- Initial hook attempt
    Extension.HookAllFrames()

    -- Re-hook when units are loaded/reloaded
    if LunaUF.Units and LunaUF.Units.InitializeFrame then
        local origInit = LunaUF.Units.InitializeFrame
        LunaUF.Units.InitializeFrame = function(self, ...)
            local result = origInit(self, ...)
            -- Delay slightly to let frame be fully created
            Extension.HookAllFrames()
            return result
        end
    end
end

function Extension.OnLoad()
    -- Nothing needed here, we use DelayedInit
end

_G["CleveRoids"] = CleveRoids
