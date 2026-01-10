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

-- X-Perl uses XPerl_PlayerTip(unitid) for OnEnter and XPerl_PlayerTipHide() for OnLeave
-- We hook these functions to track mouseover
-- Note: Re-entrancy is handled in Utility.lua's SetMouseoverFrom/ClearMouseoverFrom

function Extension.OnEnter(unitid)
    if unitid and unitid ~= "" then
        CleveRoids.SetMouseoverFrom("xperl", unitid)
    end
end

function Extension.OnLeave()
    CleveRoids.ClearMouseoverFrom("xperl")
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
