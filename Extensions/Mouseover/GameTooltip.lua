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
  -- Also clear native source when tooltip closes to prevent sticky highlights
  -- The native source may have been set from hovering units in the 3D world
  CleveRoids.ClearMouseoverFrom("native")
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

-- Clear mouseover when tooltip is set to a non-unit (spell, item, action, etc.)
-- This prevents TurtleRP from showing stale RP profile info for spells/items.
-- TurtleRP hooks GameTooltip:OnShow and checks UnitIsPlayer("mouseover") -
-- if that returns true (from a stale unit frame hover), it overwrites the tooltip.
-- By clearing mouseover when non-unit tooltips are shown, we prevent this.
function Extension.OnNonUnitTooltip()
  -- Clear the tooltip source (lowest priority fallback)
  CleveRoids.ClearMouseoverFrom("tooltip")

  -- Also clear the "native" source since we're explicitly clearing mouseover.
  -- Without this, a stale "native" source (from hovering units in 3D world)
  -- would persist and cause sticky highlights/tooltips.
  CleveRoids.ClearMouseoverFrom("native")

  -- Also explicitly clear the game's mouseover to ensure UnitIsPlayer returns false.
  -- This is defensive - the main fix is in Utility.lua:apply() using "" instead of nil.
  if CleveRoids.hasSuperwow and _G.SetMouseoverUnit then
    CleveRoids.__mo.selfTriggered = true
    _G.SetMouseoverUnit("")
  end
end

function Extension.OnLoad()
  Extension.HookMethod(_G["GameTooltip"], "SetUnit", "SetUnit")
  Extension.HookMethod(_G["GameTooltip"], "Hide", "OnClose")
  Extension.HookMethod(_G["GameTooltip"], "FadeOut", "OnClose")
  Extension.RegisterEvent("UPDATE_MOUSEOVER_UNIT", "UPDATE_MOUSEOVER_UNIT")

  -- Hook non-unit tooltip methods to clear stale mouseover state.
  -- This prevents TurtleRP from showing RP profiles for spells/items.
  Extension.HookMethod(_G["GameTooltip"], "SetSpell", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetBagItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetInventoryItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetAction", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetQuestLogItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetLootItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetMerchantItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetCraftItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetTradeSkillItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetTrainerService", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetHyperlink", "OnNonUnitTooltip")

  -- Additional tooltip methods that can cause sticky mouseover state
  -- Pet action bar, stance bar, buffs/debuffs, and other UI elements
  Extension.HookMethod(_G["GameTooltip"], "SetPetAction", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetShapeshift", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetUnitBuff", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetUnitDebuff", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetPlayerBuff", "OnNonUnitTooltip")

  -- Auction and mail tooltips (guild bank doesn't exist in 1.12.1)
  Extension.HookMethod(_G["GameTooltip"], "SetAuctionItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetAuctionSellItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetInboxItem", "OnNonUnitTooltip")
  Extension.HookMethod(_G["GameTooltip"], "SetSendMailItem", "OnNonUnitTooltip")

  -- Note: SetOwner and SetText are NOT hooked because they're used for ALL tooltips
  -- including unit tooltips. Hooking them would incorrectly clear mouseover for units.
end

_G["CleveRoids"] = CleveRoids

