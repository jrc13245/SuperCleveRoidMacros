--[[
    Author: SuperCleveRoidMacros
    License: MIT License

    DragonflightReloaded mouseover support.

    NOTE: DragonflightReloaded (DFRL namespace) modifies the default Blizzard
    unit frames (PlayerFrame, TargetFrame, etc.) rather than creating its own.
    The Blizzard.lua extension already handles these frames with priority 3.

    This extension is intentionally minimal - we just register to ensure
    the extension system doesn't complain, but we don't need to hook anything.
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

local Extension = CleveRoids.RegisterExtension("DragonflightReloaded")

function Extension.OnLoad()
    -- DragonflightReloaded modifies Blizzard's default unit frames
    -- (PlayerFrame, TargetFrame, PetFrame, PartyMemberFrameX)
    -- These are already handled by the Blizzard.lua extension
    -- No additional hooks needed!
end

_G["CleveRoids"] = CleveRoids
