--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
local Extension = CleveRoids.RegisterExtension("GameTooltipMouseover")

-- Tooltip-based mouseover (lowest priority fallback)
function Extension.SetUnit(_, unit)
  if unit and unit ~= "" then
    CleveRoids.SetMouseoverFrom("tooltip", unit)
  end
end

function Extension.OnClose()
  CleveRoids.ClearMouseoverFrom("tooltip")
end

-- Native UPDATE_MOUSEOVER_UNIT handler (priority 2)
-- This works even when tooltips are hidden by other addons
-- NOTE: We skip when selfTriggered is set to prevent TRP tooltip conflicts.
-- When we call SetMouseoverUnit ourselves, it triggers UPDATE_MOUSEOVER_UNIT,
-- which would add a redundant "native" source that persists after the real
-- source (pfUI, etc.) clears - causing TRP to show stale profile info.
function Extension.UPDATE_MOUSEOVER_UNIT()
  -- Skip if we ourselves triggered this event by calling SetMouseoverUnit
  if CleveRoids.__mo and CleveRoids.__mo.selfTriggered then
    CleveRoids.__mo.selfTriggered = false
    return
  end

  if UnitExists("mouseover") then
    CleveRoids.SetMouseoverFrom("native", "mouseover")
  else
    CleveRoids.ClearMouseoverFrom("native")
  end
end

function Extension.OnLoad()
  Extension.HookMethod(_G["GameTooltip"], "SetUnit", "SetUnit")
  Extension.HookMethod(_G["GameTooltip"], "Hide", "OnClose")
  Extension.HookMethod(_G["GameTooltip"], "FadeOut", "OnClose")
  Extension.RegisterEvent("UPDATE_MOUSEOVER_UNIT", "UPDATE_MOUSEOVER_UNIT")
end

_G["CleveRoids"] = CleveRoids

