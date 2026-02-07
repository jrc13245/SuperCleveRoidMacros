--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    X-Perl UnitFrames mouseover support.
    Hooks into X-Perl's tooltip functions to track mouseover unit.

    X-Perl uses XPerl_PlayerTip(unitid) for OnEnter and XPerl_PlayerTipHide() for OnLeave.
    These are global functions defined in XPerl/XPerl.lua.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("XPerl")
-- Use PLAYER_ENTERING_WORLD instead of ADDON_LOADED for reliable timing
Extension.RegisterEvent("PLAYER_ENTERING_WORLD", "DelayedInit")

local hooked = false

function Extension.OnEnter(unitid)
    if unitid and unitid ~= "" then
        CleveRoids.SetMouseoverFrom("xperl", unitid)
    end
end

function Extension.OnLeave()
    CleveRoids.ClearMouseoverFrom("xperl")
    CleveRoids.ClearMouseoverFrom("native")
end

function Extension.DelayedInit()
    if hooked then return end

    -- Check if X-Perl is loaded by looking for its global functions
    if not XPerl_PlayerTip then
        return
    end

    -- Hook the tooltip show function
    Extension.Hook("XPerl_PlayerTip", "OnEnter")

    -- Hook the tooltip hide function
    Extension.Hook("XPerl_PlayerTipHide", "OnLeave")

    hooked = true
end

function Extension.OnLoad()
    -- Nothing needed here, we use DelayedInit
end

_G["CleveRoids"] = CleveRoids
