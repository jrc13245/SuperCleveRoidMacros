--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    Dragonflight3 mouseover support.
    Attempts to hook into Dragonflight3's unit frames.
    The addon uses DF3 namespace and requires SuperWoW 1.5+ and UnitXP SP3.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("Dragonflight3")
Extension.RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedInit")

local hookedFrames = {}

function Extension.HookFrame(frame, unit)
    if not frame or hookedFrames[frame] then return end

    local onEnter = frame:GetScript("OnEnter")
    local onLeave = frame:GetScript("OnLeave")

    frame:SetScript("OnEnter", function()
        local u = unit or this.unit
        if u then
            CleveRoids.SetMouseoverFrom("df3", u)
        end
        if onEnter then onEnter() end
    end)

    frame:SetScript("OnLeave", function()
        CleveRoids.ClearMouseoverFrom("df3")
        if onLeave then onLeave() end
    end)

    hookedFrames[frame] = true
end

function Extension.HookAllFrames()
    -- Dragonflight3 uses DF3 or Dragonflight3 namespace
    local DF = DF3 or Dragonflight3
    if not DF then return end

    -- Try to find unit frames
    local units = { "player", "target", "pet", "targettarget", "focus", "focustarget" }

    for _, unit in ipairs(units) do
        -- Try common frame naming patterns
        local frame = DF[unit] or DF["UnitFrame_" .. unit] or _G["DF3_" .. unit] or _G["DF3UnitFrame" .. unit]
        if frame then
            Extension.HookFrame(frame, unit)
        end
    end

    -- Try party frames
    for i = 1, 4 do
        local frame = DF["party" .. i] or _G["DF3_party" .. i] or _G["DF3PartyFrame" .. i]
        if frame then
            Extension.HookFrame(frame, "party" .. i)
        end
    end

    -- Try raid frames
    for i = 1, 40 do
        local frame = DF["raid" .. i] or _G["DF3_raid" .. i] or _G["DF3RaidFrame" .. i]
        if frame then
            Extension.HookFrame(frame, "raid" .. i)
        end
    end

    -- If DF has a frames table, iterate through it
    if DF.frames then
        for unit, frame in pairs(DF.frames) do
            Extension.HookFrame(frame, unit)
        end
    end

    -- If DF has a UnitFrames table
    if DF.UnitFrames then
        for unit, frame in pairs(DF.UnitFrames) do
            Extension.HookFrame(frame, unit)
        end
    end

    -- Try mods directory structure (Dragonflight3 uses /mods/)
    if DF.mods then
        for modName, mod in pairs(DF.mods) do
            if mod.frames then
                for unit, frame in pairs(mod.frames) do
                    Extension.HookFrame(frame, unit)
                end
            end
        end
    end
end

function Extension.DelayedInit()
    local DF = DF3 or Dragonflight3
    if not DF then
        return
    end

    Extension.HookAllFrames()
end

function Extension.OnLoad()
end

_G["CleveRoids"] = CleveRoids
