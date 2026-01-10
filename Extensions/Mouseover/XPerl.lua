--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    X-Perl UnitFrames mouseover support.
    Hooks into X-Perl's tooltip functions to track mouseover unit.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("XPerl")
Extension.RegisterEvent("ADDON_LOADED", "OnLoad")

-- Re-entrancy guard to prevent stack overflow
local isProcessing = false

-- X-Perl uses XPerl_PlayerTip(unitid) for OnEnter and XPerl_PlayerTipHide() for OnLeave
-- We hook these functions to track mouseover

function Extension.OnEnter(unitid)
    if isProcessing then return end
    if unitid and unitid ~= "" then
        isProcessing = true
        CleveRoids.SetMouseoverFrom("xperl", unitid)
        isProcessing = false
    end
end

function Extension.OnLeave()
    if isProcessing then return end
    isProcessing = true
    CleveRoids.ClearMouseoverFrom("xperl")
    isProcessing = false
end

function Extension.OnLoad()
    -- Check if X-Perl is loaded by looking for its global functions
    if not XPerl_PlayerTip then
        return
    end

    -- Hook the tooltip show function
    Extension.Hook("XPerl_PlayerTip", "OnEnter")

    -- Hook the tooltip hide function
    Extension.Hook("XPerl_PlayerTipHide", "OnLeave")
end

_G["CleveRoids"] = CleveRoids
