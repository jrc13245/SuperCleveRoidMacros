--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    LunaUnitFrames mouseover support.

    NOTE: LunaUnitFrames already has native SuperWoW integration!
    It calls SetMouseoverUnit(this.unit) directly in its OnEnter handler.
    This triggers the UPDATE_MOUSEOVER_UNIT event which our system picks up
    as the "native" source with priority 2.

    This extension is intentionally minimal - we just register to ensure
    the extension system doesn't complain, but we don't need to hook anything.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("LunaUnitFrames")

function Extension.OnLoad()
    -- LunaUnitFrames already has native SuperWoW integration
    -- It calls SetMouseoverUnit(this.unit) in modules/units.lua lines 186-207
    -- This is picked up by our UPDATE_MOUSEOVER_UNIT handler as "native" source
    -- No hooks needed!
end

_G["CleveRoids"] = CleveRoids
