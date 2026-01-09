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
function Extension.UPDATE_MOUSEOVER_UNIT()
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

