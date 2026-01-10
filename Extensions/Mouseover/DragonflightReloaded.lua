--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    DragonflightReloaded mouseover support.
    Attempts to hook into DragonflightReloaded's unit frames.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("DragonflightReloaded")
Extension.RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedInit")

local hookedFrames = {}

function Extension.HookFrame(frame, unit)
    if not frame or hookedFrames[frame] then return end

    local onEnter = frame:GetScript("OnEnter")
    local onLeave = frame:GetScript("OnLeave")

    frame:SetScript("OnEnter", function()
        local u = unit or this.unit
        if u then
            CleveRoids.SetMouseoverFrom("dfr", u)
        end
        if onEnter then onEnter() end
    end)

    frame:SetScript("OnLeave", function()
        CleveRoids.ClearMouseoverFrom("dfr")
        if onLeave then onLeave() end
    end)

    hookedFrames[frame] = true
end

function Extension.HookAllFrames()
    -- DragonflightReloaded uses DFR namespace
    if not DFR then return end

    -- Try to find unit frames in DFR namespace
    local units = { "player", "target", "pet", "targettarget", "focus", "focustarget" }

    for _, unit in ipairs(units) do
        -- Try common frame naming patterns
        local frame = DFR[unit] or DFR["UnitFrame_" .. unit] or _G["DFR_" .. unit] or _G["DFRUnitFrame" .. unit]
        if frame then
            Extension.HookFrame(frame, unit)
        end
    end

    -- Try party frames
    for i = 1, 4 do
        local frame = DFR["party" .. i] or _G["DFR_party" .. i] or _G["DFRPartyFrame" .. i]
        if frame then
            Extension.HookFrame(frame, "party" .. i)
        end
    end

    -- Try raid frames
    for i = 1, 40 do
        local frame = DFR["raid" .. i] or _G["DFR_raid" .. i] or _G["DFRRaidFrame" .. i]
        if frame then
            Extension.HookFrame(frame, "raid" .. i)
        end
    end

    -- If DFR has a frames table, iterate through it
    if DFR.frames then
        for unit, frame in pairs(DFR.frames) do
            Extension.HookFrame(frame, unit)
        end
    end

    -- If DFR has a UnitFrames table
    if DFR.UnitFrames then
        for unit, frame in pairs(DFR.UnitFrames) do
            Extension.HookFrame(frame, unit)
        end
    end
end

function Extension.DelayedInit()
    if not DFR then
        return
    end

    Extension.HookAllFrames()
end

function Extension.OnLoad()
end

_G["CleveRoids"] = CleveRoids
