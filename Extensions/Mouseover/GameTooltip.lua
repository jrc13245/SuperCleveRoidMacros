--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
local Extension = CleveRoids.RegisterExtension("GameTooltipMouseover")

local lastUnit, setByTooltip = nil, false

function Extension.SetUnit(_, unit)
  if unit and unit ~= "" then
    CleveRoids.SetMouseoverFrom("tooltip", unit)
  end
end

function Extension.OnClose()
  CleveRoids.ClearMouseoverFrom("tooltip")
end


function Extension.OnLoad()
  Extension.HookMethod(_G["GameTooltip"], "SetUnit", "SetUnit")
  Extension.HookMethod(_G["GameTooltip"], "Hide", "OnClose")
  Extension.HookMethod(_G["GameTooltip"], "FadeOut", "OnClose")
end

_G["CleveRoids"] = CleveRoids

