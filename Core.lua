--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny / brian / Mewtiny
	License: MIT License
]]

-- Setup to wrap our stuff in a table so we don't pollute the global environment
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids
CleveRoids.lastItemIndexTime = 0
CleveRoids.initializationTimer = nil
CleveRoids.isActionUpdateQueued = true
CleveRoids.lastEquipTime = CleveRoids.lastEquipTime or {}
CleveRoids.lastWeaponSwapTime = 0
CleveRoids.equipInProgress = false

local requirementCheckFrame = CreateFrame("Frame")
requirementCheckFrame:RegisterEvent("ADDON_LOADED")
requirementCheckFrame:SetScript("OnEvent", function()
    if arg1 ~= "SuperCleveRoidMacros" then return end

    -- Check requirements immediately when our addon loads
    local hasSuperwow = CleveRoids.hasSuperwow
    local hasNampower = (IsSpellInRange ~= nil)
    local hasUnitXP = pcall(UnitXP, "nop", "nop")

    if not hasSuperwow or not hasNampower or not hasUnitXP then
        -- Show errors
        if not hasSuperwow then
            CleveRoids.Print("|cFFFF0000SuperCleveRoidMacros|r requires |cFF00FFFFbalakethelock's SuperWoW|r:")
            CleveRoids.Print("https://github.com/balakethelock/SuperWoW")
        end
        if not hasNampower then
            CleveRoids.Print("|cFFFF0000SuperCleveRoidMacros|r requires |cFF00FFFFpepopo978's Nampower|r:")
            CleveRoids.Print("https://gitea.com/avitasia/nampower")
        end
        if not hasUnitXP then
            CleveRoids.Print("|cFFFF0000SuperCleveRoidMacros|r requires |cFF00FFFFKonaka's UnitXP_SP3|r:")
            CleveRoids.Print("https://codeberg.org/konaka/UnitXP_SP3")
        end

        -- Disable immediately
        CleveRoids.DisableAddon("Missing Requirements")

        -- Unregister this check frame
        this:UnregisterAllEvents()
        return
    end

    -- Requirements met - allow normal initialization
    CleveRoids.Print("|cFF4477FFSuperCleveR|r|cFFFFFFFFoid Macros|r |cFF00FF00Loaded|r - See the README.")

    -- Unregister this check frame
    this:UnregisterAllEvents()
end)

local SLOT_TO_INVID = {
    ["MainHandSlot"] = 16,
    ["SecondaryHandSlot"] = 17,
    ["RangedSlot"] = 18,
    ["HeadSlot"] = 1,
    ["NeckSlot"] = 2,
    ["ShoulderSlot"] = 3,
    ["ChestSlot"] = 5,
    ["WaistSlot"] = 6,
    ["LegsSlot"] = 7,
    ["FeetSlot"] = 8,
    ["WristSlot"] = 9,
    ["HandsSlot"] = 10,
    ["Finger0Slot"] = 11,
    ["Finger1Slot"] = 12,
    ["Trinket0Slot"] = 13,
    ["Trinket1Slot"] = 14,
    ["BackSlot"] = 15,
    ["ShirtSlot"] = 4,
    ["TabardSlot"] = 19,
}

local function GetInventoryIdFromSlot(slotName)
    return SLOT_TO_INVID[slotName] or GetInventorySlotInfo(slotName)
end

local function IsSlotOnCooldown(slot)
    local now = GetTime()
    local slotTime = CleveRoids.lastEquipTime[slot] or 0
    local globalTime = CleveRoids.lastGlobalEquipTime or 0

    if (now - slotTime) < CleveRoids.EQUIP_COOLDOWN then
        return true
    end

    if (now - globalTime) < CleveRoids.EQUIP_GLOBAL_COOLDOWN then
        return true
    end

    return false
end

local function PerformEquipSwap(item, inventoryId)
    if not item or not inventoryId then return false end

    -- Check if in combat and swapping weapons
    local inCombat = UnitAffectingCombat("player")
    local isWeapon = (inventoryId == 16 or inventoryId == 17 or inventoryId == 18)

    if inCombat and isWeapon then
        -- Don't swap while casting
        if CleveRoids.CurrentSpell.type ~= "" then
            return false
        end

        -- Check for on-swing spells if available
        if GetCurrentCastingInfo then
            local _, _, _, _, _, onswing = GetCurrentCastingInfo()
            if onswing == 1 then
                return false
            end
        end
    end

    -- Try to equip
    local success = false

    -- Method 1: Use item by bag/slot
    if item.bagID and item.slot then
        PickupContainerItem(item.bagID, item.slot)
        if CursorHasItem() then
            EquipCursorItem(inventoryId)
            success = not CursorHasItem()
        end
    end

    -- Method 2: Use item by inventory ID
    if not success and item.inventoryID then
        PickupInventoryItem(item.inventoryID)
        if CursorHasItem() then
            EquipCursorItem(inventoryId)
            success = not CursorHasItem()
        end
    end

    -- Method 3: Use EquipItemByName (SuperWoW)
    if not success and item.name and EquipItemByName then
        local ok = pcall(EquipItemByName, item.name, inventoryId)
        success = ok
    end

    -- Clear cursor
    if CursorHasItem() then
        ClearCursor()
    end

    return success
end

-- Queue equipment swap function
function CleveRoids.QueueEquipItem(item, slotName)
    if not item or not slotName then return false end

    local inventoryId = GetInventoryIdFromSlot(slotName)
    if not inventoryId then return false end

    local now = GetTime()

    -- Try immediate equip if not on cooldown
    if not IsSlotOnCooldown(inventoryId) then
        local success = PerformEquipSwap(item, inventoryId)

        if success then
            CleveRoids.lastEquipTime[inventoryId] = now
            CleveRoids.lastGlobalEquipTime = now
            return true
        end
    end

    -- Queue for later
    table.insert(CleveRoids.equipmentQueue, {
        item = item,
        slotName = slotName,
        inventoryId = inventoryId,
        queueTime = now,
        retries = 0,
        maxRetries = 5
    })

    return false
end

-- Process equipment queue (called from OnUpdate)
function CleveRoids.ProcessEquipmentQueue()
    if not CleveRoids.equipmentQueue or table.getn(CleveRoids.equipmentQueue) == 0 then
        return
    end

    local now = GetTime()
    local i = 1

    while i <= table.getn(CleveRoids.equipmentQueue) do
        local queued = CleveRoids.equipmentQueue[i]

        -- Check if cooldown passed
        if not IsSlotOnCooldown(queued.inventoryId) then
            local success = PerformEquipSwap(queued.item, queued.inventoryId)

            if success then
                CleveRoids.lastEquipTime[queued.inventoryId] = now
                CleveRoids.lastGlobalEquipTime = now
                table.remove(CleveRoids.equipmentQueue, i)
            else
                queued.retries = queued.retries + 1

                if queued.retries >= queued.maxRetries then
                    table.remove(CleveRoids.equipmentQueue, i)
                else
                    i = i + 1
                end
            end
        else
            i = i + 1
        end

        -- Remove expired entries (>10 seconds old)
        if queued and (now - queued.queueTime) > 10 then
            table.remove(CleveRoids.equipmentQueue, i)
        end
    end
end

-- Improved DisableAddon function
function CleveRoids.DisableAddon(reason)
    -- Prevent multiple disable calls
    if CleveRoids.disabled then return end

    -- Mark state
    CleveRoids.disabled = true

    -- Stop main frame activity
    if CleveRoids.Frame then
        if CleveRoids.Frame.UnregisterAllEvents then
            CleveRoids.Frame:UnregisterAllEvents()
        end
        if CleveRoids.Frame.SetScript then
            CleveRoids.Frame:SetScript("OnEvent", nil)
            CleveRoids.Frame:SetScript("OnUpdate", nil)
        end
    end

    -- Neuter all slash commands
    if SlashCmdList then
        local disabledMsg = function()
            CleveRoids.Print("|cffff0000SuperCleveRoidMacros is disabled|r" ..
                (reason and (": " .. tostring(reason)) or ""))
        end

        SlashCmdList.CLEVEROIDS = disabledMsg
        SlashCmdList.CAST = disabledMsg
        SlashCmdList.USE = disabledMsg
        SlashCmdList.EQUIP = disabledMsg
        SlashCmdList.EQUIPMH = disabledMsg
        SlashCmdList.EQUIPOH = disabledMsg
    end

    -- Try to disable for next login
    local addonName = "SuperCleveRoidMacros"
    if type(DisableAddOn) == "function" then
        pcall(DisableAddOn, addonName)
    end

    -- Final notice
    CleveRoids.Print("|cffff0000Disabled|r - " .. (reason or "Unknown reason"))
    CleveRoids.Print("Please install required dependencies and /reload")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("VARIABLES_LOADED")
frame:SetScript("OnEvent", function()
    if not CleveRoidMacros then CleveRoidMacros = {} end

    if type(CleveRoidMacros.realtime) ~= "number" then
        CleveRoidMacros.realtime = 0
    end

    if type(CleveRoidMacros.refresh) ~= "number" then
        CleveRoidMacros.refresh = 5
    end
end)

-- Queues a full update of all action bars.
-- This is called by game event handlers to avoid running heavy logic inside the event itself.
function CleveRoids.QueueActionUpdate()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.isActionUpdateQueued = true
    end
end

local function _StripColor(s)
  if not s then return s end
  if string.sub(s,1,2) == "|c" then return string.sub(s,11,-3) end
  return s
end

local _ReagentBySpell = {
  ["Vanish"] = "Flash Powder",    -- 5140
  ["Blind"]  = "Blinding Powder", -- 5530
}

-- Minimal map for rogue reagents; extend as needed
local _ReagentIdByName = {
    ["Flash Powder"]   = 5140, -- Vanish
    ["Blinding Powder"] = 5530, -- Blind
}

-- Lazy bag-scan tooltip (only if we need to scan a bag slot by name)
local function CRM_GetBagScanTip()
  local tip = _G.CleveRoidsBagScanTip
  if tip then return tip end
  local ok, created = pcall(CreateFrame, "GameTooltip", "CleveRoidsBagScanTip", UIParent, "GameTooltipTemplate")
  if ok and created then
    tip = created
  else
    tip = CreateFrame("GameTooltip", "CleveRoidsBagScanTip", UIParent)
    local L1 = tip:CreateFontString("$parentTextLeft1",  nil, "GameTooltipText")
    local R1 = tip:CreateFontString("$parentTextRight1", nil, "GameTooltipText")
    tip:AddFontStrings(L1, R1)
    for i=2,10 do
      tip:CreateFontString("$parentTextLeft"..i,  nil, "GameTooltipText")
      tip:CreateFontString("$parentTextRight"..i, nil, "GameTooltipText")
    end
  end
  tip:SetOwner(WorldFrame, "ANCHOR_NONE")
  _G.CleveRoidsBagScanTip = tip
  return tip
end

-- Return total in *bags only* (not bank), by id when possible; fallback to name
function CleveRoids.GetReagentCount(reagentName)
  if not reagentName or reagentName == "" then return 0 end

  local wantId = _ReagentIdByName[reagentName]
  local total = 0

  for bag = 0, 4 do
    local slots = GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
        local _, count = GetContainerItemInfo(bag, slot)
        count = count or 0
      -- Prefer link → id when available
      local link = (GetContainerItemLink and GetContainerItemLink(bag, slot)) or nil
      if link then
          local _, _, idstr = string.find(link, "item:(%d+)")
          local id = idstr and tonumber(idstr) or nil
        if (wantId and id == wantId) or (not wantId and string.find(link, "%["..reagentName.."%]")) then
          total = total + (count or 0)
        end
      else
        -- Fallback: scan bag slot tooltip for the name
        local tip = CRM_GetBagScanTip()
        tip:ClearLines()
        tip:SetBagItem(bag, slot)
        local left1 = _G[tip:GetName().."TextLeft1"]
        local name = left1 and left1:GetText()
        if name and name == reagentName then
          total = total + (count or 0)
        end
      end
    end
  end

  return total
end

function CleveRoids.GetSpellCost(spellSlot, bookType)
  -- Fast path: existing fixed-slot read
  CleveRoids.Frame:SetOwner(WorldFrame, "ANCHOR_NONE")
  CleveRoids.Frame:SetSpell(spellSlot, bookType)

  local cost, reagent
  local costText = CleveRoids.Frame.costFontString:GetText()
  if costText then
      _, _, cost = string.find(costText, "^(%d+)%s+[^yYsS]")
  end

  local reagentText = CleveRoids.Frame.reagentFontString:GetText()
  if reagentText then
      _, _, reagent = string.find(reagentText, "^Reagents?%s*:%s*(.*)")
  end
  reagent = _StripColor(reagent)

  -- Fallback: scan all lines on a named tooltip (handles Vanish layout)
  if not reagent or not cost then
    local tip = CleveRoidsTooltipScan
    if not tip then
      -- belt & suspenders: create if somehow missing
      local ok,_ = pcall(CreateFrame, "GameTooltip", "CleveRoidsTooltipScan", UIParent, "GameTooltipTemplate")
      if not ok or not CleveRoidsTooltipScan then
        CleveRoidsTooltipScan = CreateFrame("GameTooltip", "CleveRoidsTooltipScan", UIParent)
        local L1 = CleveRoidsTooltipScan:CreateFontString("$parentTextLeft1",  nil, "GameTooltipText")
        local R1 = CleveRoidsTooltipScan:CreateFontString("$parentTextRight1", nil, "GameTooltipText")
        CleveRoidsTooltipScan:AddFontStrings(L1, R1)
        for i=2,32 do
          CleveRoidsTooltipScan:CreateFontString("$parentTextLeft"..i,  nil, "GameTooltipText")
          CleveRoidsTooltipScan:CreateFontString("$parentTextRight"..i, nil, "GameTooltipText")
        end
      end
      CleveRoidsTooltipScan:SetOwner(WorldFrame, "ANCHOR_NONE")
      tip = CleveRoidsTooltipScan
    end

    tip:ClearLines()
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tip:SetSpell(spellSlot, bookType)

    local base = tip:GetName() or "CleveRoidsTooltipScan"
    local maxLines = (tip.NumLines and tip:NumLines()) or 32

    for i = 1, maxLines do
      local L = _G[base.."TextLeft"..i]
      local R = _G[base.."TextRight"..i]
      local lt = L and L:GetText() or ""
      local rt = R and R:GetText() or ""

      if not reagent then
        if string.find(lt, "^[Rr]eagents?%s*:") then
          reagent = _StripColor((rt ~= "" and rt) or (string.gsub(lt, "^[Rr]eagents?%s*:%s*", "")))
        elseif string.find(rt, "^[Rr]eagents?%s*:") then
          reagent = _StripColor((lt ~= "" and lt) or (string.gsub(rt, "^[Rr]eagents?%s*:%s*", "")))
        end
      end

      if not cost and rt ~= "" then
          local _, _, num = string.find(rt, "^(%d+)%s+(Mana|Energy|Rage|Focus)")
          if num then cost = tonumber(num) end
      end

      if reagent and cost then break end
    end
  end

  if not reagent then
    local name = GetSpellName(spellSlot, bookType)
    if name then
        name = string.gsub(name, "%s*%(.-%)%s*$", "")  -- strip "(Rank X)"
        reagent = _ReagentBySpell[name]
    end
  end

  return (cost and tonumber(cost) or 0), (reagent and tostring(reagent) or nil)
end

function CleveRoids.GetProxyActionSlot(slot)
    if not slot then return end
    return CleveRoids.actionSlots[slot] or CleveRoids.actionSlots[slot.."()"]
end

function CleveRoids.TestForActiveAction(actions)
    if not actions then return end
    local currentActive = actions.active
    local currentSequence = actions.sequence
    local hasActive = false
    local newActiveAction = nil
    local newSequence = nil
    local firstUnconditional = nil

    if actions.tooltip and table.getn(actions.list) == 0 then
        if CleveRoids.TestAction(actions.cmd or "", actions.args or "") then

            hasActive = true
            actions.active = actions.tooltip
        end
    else
        -- First pass: find first action with conditionals that passes
        for _, action in ipairs(actions.list) do
            local result = CleveRoids.TestAction(action.cmd, action.args)
            
            -- Check if action has conditionals
            local _, conditionals = CleveRoids.GetParsedMsg(action.args)
            
            if not conditionals and not firstUnconditional then
                -- Track first unconditional action as fallback
                firstUnconditional = action
            end
            
            -- break on first action that passes tests
            if result then
                hasActive = true
                if action.sequence then
                    newSequence = action.sequence
                    newActiveAction = CleveRoids.GetCurrentSequenceAction(newSequence)
                    if not newActiveAction then hasActive = false end
                else
                    newActiveAction = action
                end
                if hasActive then break end
            end
        end
        
        -- If no conditional action passed, use first unconditional action
        if not hasActive and firstUnconditional then
            hasActive = true
            newActiveAction = firstUnconditional
        end
    end

    local changed = false
    if currentActive ~= newActiveAction or currentSequence ~= newSequence then
        actions.active = newActiveAction
        actions.sequence = newSequence
        changed = true
    end

    if not hasActive then
        if actions.active ~= nil or actions.sequence ~= nil then
             actions.active = nil
             actions.sequence = nil
             changed = true
        end
        return changed
    end

    if actions.active then
        local previousUsable = actions.active.usable
        local previousOom = actions.active.oom
        local previousInRange = actions.active.inRange

        if actions.active.spell then
            actions.active.inRange = 1

            -- Enhanced nampower range check with spell ID support
			if IsSpellInRange then
                local unit = actions.active.conditionals and actions.active.conditionals.target or "target"
				if unit == "focus" and pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.label and pfUI.uf.focus.id then
					unit = pfUI.uf.focus.label .. pfUI.uf.focus.id
				end
				local castName = actions.active.action
				if actions.active.spell and actions.active.spell.name then
					local rank = actions.active.spell.rank
								 or (actions.active.spell.highest and actions.active.spell.highest.rank)
					if rank and rank ~= "" then
						castName = actions.active.spell.name .. "(" .. rank .. ")"
					end
				end
				if UnitExists(unit) then
					-- Try to get spell ID for more accurate range check
					local checkValue = castName
					if GetSpellIdForName then
						local spellId = GetSpellIdForName(castName)
						if spellId and spellId > 0 then
							checkValue = spellId
						end
					end

					local r = IsSpellInRange(checkValue, unit)
					if r ~= nil then
						actions.active.inRange = r
					end
				end
			end

            actions.active.oom = (UnitMana("player") < actions.active.spell.cost)

            local start, duration = GetSpellCooldown(actions.active.spell.spellSlot, actions.active.spell.bookType)
            local onCooldown = (start > 0 and duration > 0)

            if actions.active.isReactive then
                -- Use Nampower's IsSpellUsable if available for better detection
                if IsSpellUsable then
                    local usable, oom = IsSpellUsable(actions.active.action)
                    if usable == 1 and oom ~= 1 then
                        actions.active.usable = (pfUI and pfUI.bars) and nil or 1
                    else
                        actions.active.usable = nil
                    end
                    actions.active.oom = false
                elseif not CleveRoids.IsReactiveUsable(actions.active.action) then
                    actions.active.oom = false
                    actions.active.usable = nil
                else
                    actions.active.usable = (pfUI and pfUI.bars) and nil or 1
                end
            elseif actions.active.inRange ~= 0 and not actions.active.oom then
                actions.active.usable = 1

            -- pfUI:actionbar.lua -- update usable [out-of-range = 1, oom = 2, not-usable = 3, default = 0]
            elseif pfUI and pfUI.bars and actions.active.oom then
                actions.active.usable = 2
            else
                actions.active.usable = nil
            end
        else
            actions.active.inRange = 1
            actions.active.usable = 1
        end
        if actions.active.usable ~= previousUsable or
           actions.active.oom ~= previousOom or
           actions.active.inRange ~= previousInRange then
            changed = true
        end
    end
    return changed
end

function CleveRoids.TestForAllActiveActions()
    for slot, actions in pairs(CleveRoids.Actions) do
        local stateChanged = CleveRoids.TestForActiveAction(actions)
        if stateChanged then
            CleveRoids.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
        end
    end
end

function CleveRoids.ClearAction(slot)
    if not CleveRoids.Actions[slot] then return end
    CleveRoids.Actions[slot].active = nil
    CleveRoids.Actions[slot] = nil
end

function CleveRoids.GetAction(slot)
    if not slot or not CleveRoids.ready then return end

    local actions = CleveRoids.Actions[slot]
    if actions then return actions end

    local text = GetActionText(slot)

    if text then
        local macro = CleveRoids.GetMacro(text)
        if macro then
            actions = macro.actions

            CleveRoids.TestForActiveAction(actions)
            CleveRoids.Actions[slot] = actions
            CleveRoids.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
            return actions
        end
    end
end

function CleveRoids.GetActiveAction(slot)
    local action = CleveRoids.GetAction(slot)
    return action and action.active
end

function CleveRoids.SendEventForAction(slot, event, ...)
    local old_this = this

    local original_global_args = {}
    for i = 1, 10 do
        original_global_args[i] = _G["arg" .. i]
    end

    if type(arg) == "table" then

        local n_varargs_from_arg_table = arg.n or 0
        for i = 1, 10 do
            if i <= n_varargs_from_arg_table then
                _G["arg" .. i] = arg[i]
            else
                _G["arg" .. i] = nil
            end
        end
    else
        for i = 1, 10 do
            _G["arg" .. i] = nil
        end
    end

    local button_to_call_event_on
    local page = floor((slot - 1) / NUM_ACTIONBAR_BUTTONS) + 1
    local pageSlot = slot - (page - 1) * NUM_ACTIONBAR_BUTTONS

    if slot >= 73 then
        button_to_call_event_on = _G["BonusActionButton" .. pageSlot]
    elseif slot >= 61 then
        button_to_call_event_on = _G["MultiBarBottomLeftButton" .. pageSlot]
    elseif slot >= 49 then
        button_to_call_event_on = _G["MultiBarBottomRightButton" .. pageSlot]
    elseif slot >= 37 then
        button_to_call_event_on = _G["MultiBarLeftButton" .. pageSlot]
    elseif slot >= 25 then
        button_to_call_event_on = _G["MultiBarRightButton" .. pageSlot]
    end

    if button_to_call_event_on then
        this = button_to_call_event_on
        ActionButton_OnEvent(event)
    end

    if page == CURRENT_ACTIONBAR_PAGE then
        local main_bar_button = _G["ActionButton" .. pageSlot]
        if main_bar_button and main_bar_button ~= button_to_call_event_on then
            this = main_bar_button
            ActionButton_OnEvent(event)
        elseif not button_to_call_event_on and main_bar_button then
             this = main_bar_button
             ActionButton_OnEvent(event)
        end
    end

    this = old_this

    for i = 1, 10 do
        _G["arg" .. i] = original_global_args[i]
    end

    if type(arg) == "table" and arg.n then

        if arg.n == 0 then
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event) end
        elseif arg.n == 1 then
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event, arg[1]) end
        elseif arg.n == 2 then
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event, arg[1], arg[2]) end
        elseif arg.n == 3 then
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event, arg[1], arg[2], arg[3]) end
        elseif arg.n == 4 then
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event, arg[1], arg[2], arg[3], arg[4]) end
        elseif arg.n == 5 then
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event, arg[1], arg[2], arg[3], arg[4], arg[5]) end
        elseif arg.n == 6 then
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event, arg[1], arg[2], arg[3], arg[4], arg[5], arg[6]) end
        else
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do fn_h(slot, event, arg[1], arg[2], arg[3], arg[4], arg[5], arg[6], arg[7]) end
        end
    else

        for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do
            fn_h(slot, event)
        end
    end
end

-- Executes the given Macro's body
-- body: The Macro's body
function CleveRoids.ExecuteMacroBody(body,inline)
    local lines = CleveRoids.splitString(body, "\n")
    if inline then lines = CleveRoids.splitString(body, "\\n"); end

    for k,v in pairs(lines) do
        if CleveRoids.stopmacro then
            CleveRoids.stopmacro = false
            return true
        end
        ChatFrameEditBox:SetText(v)
        ChatEdit_SendText(ChatFrameEditBox)
    end
    return true
end

-- Gets the body of the Macro with the given name
-- name: The name of the Macro
-- returns: The body of the macro
function CleveRoids.GetMacroBody(name)
    local macro = CleveRoids.GetMacro(name)
    return macro and macro.body
end

-- Attempts to execute a macro by the given name (Blizzard or Super tab)
-- Returns: true if something was executed, false otherwise
function CleveRoids.ExecuteMacroByName(name)
    if not name or name == "" then return false end

    local body

    -- 1) Blizzard macro runner by name/ID
    local id = GetMacroIndexByName(name)
    if id and id ~= 0 and type(RunMacro) == "function" then
        if pcall(RunMacro, name) then return true end
        if pcall(RunMacro, id)   then return true end
        local _n, _tex, b2 = GetMacroInfo(id)
        if b2 and b2 ~= "" then body = body or b2 end
    end

    -- 2) SuperMacro runner by name
    if type(GetSuperMacroInfo) == "function" and type(RunSuperMacro) == "function" then
        local _n2, _t2, b3 = GetSuperMacroInfo(name)
        if b3 and b3 ~= "" then
            if pcall(RunSuperMacro, name) then return true end
            body = body or b3
        end
    end

    -- 3) CRM cache fallback
    if not body and type(CleveRoids.GetMacro) == "function" then
        local m = CleveRoids.GetMacro(name)
        if m and m.body and m.body ~= "" then
            body = m.body
        end
    end

    if not body or body == "" then return false end
    return CleveRoids.ExecuteMacroBody(body)
end

function CleveRoids.SetHelp(conditionals)
    if conditionals.harm then
        conditionals.help = false
    end
end

function CleveRoids.FixEmptyTarget(conditionals)
    if not conditionals.target then
        if UnitExists("target") then
            conditionals.target = "target"
        elseif GetCVar("autoSelfCast") == "1" and not conditionals.target == "help" then
            conditionals.target = "player"
        end
    end
    return false
end

-- Fixes the conditionals' target by targeting the target with the given name
-- conditionals: The conditionals containing the current target
-- name: The name of the player to target
-- hook: The target hook
-- returns: Whether or not we've changed the player's current target
function CleveRoids.FixEmptyTargetSetTarget(conditionals, name, hook)
    if not conditionals.target then
        hook(name)
        conditionals.target = "target"
        return true
    end
    return false
end

-- Returns the name of the focus target or nil
function CleveRoids.GetFocusName()
    -- 1. Add specific compatibility for pfUI.
    -- pfUI stores its focus unit information in a table.
    if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.unitname then
        return pfUI.uf.focus.unitname
    end

    -- Fallback for other focus addons
    if ClassicFocus_CurrentFocus then
        return ClassicFocus_CurrentFocus
    elseif CURR_FOCUS_TARGET then
        return CURR_FOCUS_TARGET
    end

    return nil
end

-- Attempts to target the focus target.
-- returns: Whether or not it succeeded
function CleveRoids.TryTargetFocus()
    local name = CleveRoids.GetFocusName()

    if not name then
        return false
    end

    TargetByName(name, true)

    if not UnitExists("target") or (string.lower(UnitName("target")) ~= name) then
        -- The target switch failed (out of range, LoS, etc.)
        return false
    end

    return true
end

function CleveRoids.GetMacroNameFromAction(text)
    if string.sub(text, 1, 1) == "{" and string.sub(text, -1) == "}" then
        local name
        if string.sub(text, 2, 2) == "\"" and string.sub(text, -2, -2) == "\"" then
            return string.sub(text, 3, -3)
        else
            return string.sub(text, 2, -2)
        end
    end
end

function CleveRoids.CreateActionInfo(action, conditionals)
    local _, _, text = string.find(action, "!?%??~?(.*)")
    local spell = CleveRoids.GetSpell(text)
    local petSpell  -- Add this line
    local item, macroName, macro, macroTooltip, actionType, texture

    -- NEW: Check if the action is a slot number
    local slotId = tonumber(text)
    if slotId and slotId >= 1 and slotId <= 19 then
        actionType = "item"
        local itemTexture = GetInventoryItemTexture("player", slotId)
        if itemTexture then
            texture = itemTexture
        else
            texture = CleveRoids.unknownTexture
        end
    else
        -- Original logic for named items and spells
        if not spell then
            petSpell = CleveRoids.GetPetSpell(text)  -- Add this line
        end
        if not spell and not petSpell then  -- Modify this line
            item = CleveRoids.GetItem(text)
        end
        if not item and not petSpell then  -- Modify this line
            macroName = CleveRoids.GetMacroNameFromAction(text)
            macro = CleveRoids.GetMacro(macroName)
            macroTooltip = (macro and macro.actions) and macro.actions.tooltip
        end

        if spell then
            actionType = "spell"
            texture = spell.texture or CleveRoids.unknownTexture
        elseif petSpell then  -- Add this block
            actionType = "petspell"
            texture = petSpell.texture or CleveRoids.unknownTexture
        elseif item then
            actionType = "item"
            texture = (item and item.texture) or CleveRoids.unknownTexture
        elseif macro then
            actionType = "macro"
            texture = (macro.actions and macro.actions.tooltip and macro.actions.tooltip.texture)
                        or (macro and macro.texture)
                        or CleveRoids.unknownTexture
        end
    end

    local info = {
        action = text,
        item = item,
        spell = spell,
        petSpell = petSpell,  -- Add this line
        macro = macroTooltip,
        type = actionType,
        texture = texture,
        conditionals = conditionals,
    }

    return info
end

function CleveRoids.SplitCommandAndArgs(text)
    local _, _, cmd, args = string.find(text, "(/%w+%s?)(.*)")
    if cmd and args then
        cmd = CleveRoids.Trim(cmd)
        text = CleveRoids.Trim(args)
    end
    return cmd, args
end

function CleveRoids.ParseSequence(text)
    if not text or text == "" then return end

    -- normalize commas
    local args = string.gsub(text, "(%s*,%s*)", ",")

    -- optional [conditionals] block
    local _, condEnd, condBlock = string.find(args, "(%[.*%])")

    -- accept reset= anywhere; no trailing space required; strip it out once
    local _, _, resetVal = string.find(args, "[Rr][Ee][Ss][Ee][Tt]=([%w/]+)")
    if resetVal then
      args = string.gsub(args, "%s*[Rr][Ee][Ss][Ee][Tt]=[%w/]+%s*", " ", 1)
    end

    -- actions are what's left after any ] (if present)
    local actionSeq = CleveRoids.Trim((condEnd and string.sub(args, condEnd + 1)) or args)
    args = (condBlock or "") .. actionSeq
    if actionSeq == "" then return end

    local sequence = {
        index      = 1,
        reset      = {},
        status     = 0,
        lastUpdate = 0,
        args       = args,
        list       = {},
    }

    -- fill reset rules: seconds or flags (target/combat/alt/ctrl/shift)
    if resetVal then
        for _, rule in pairs(CleveRoids.Split(resetVal, "/")) do
            rule = string.lower(CleveRoids.Trim(rule))
            local secs = tonumber(rule)
            if secs and secs > 0 then
                sequence.reset.secs = secs
            else
                sequence.reset[rule] = true
            end
        end
    end

    -- build steps
    for _, a in ipairs(CleveRoids.Split(actionSeq, ",")) do
        local sa = CleveRoids.CreateActionInfo(CleveRoids.GetParsedMsg(a))
        table.insert(sequence.list, sa)
    end

    CleveRoids.Sequences[text] = sequence
    return sequence
end

function CleveRoids.ParseMacro(name)
    if not name then return end

    local macroID = GetMacroIndexByName(name)

    local _, texture, body
    if macroID and macroID ~= 0 then
        _, texture, body = GetMacroInfo(macroID)
    end

    if (not body) and GetSuperMacroInfo then
        _, texture, body = GetSuperMacroInfo(name)
    end

    if not texture or not body then return end

    local macro = {
        id      = macroID,
        name    = name,
        texture = texture,
        body    = body,
        actions = {},
    }
    macro.actions.list = {}

    -- build a list of testable actions for the macro
    local hasShowTooltip = false
    local showTooltipHasArg = false

    for i, line in ipairs(CleveRoids.splitString(body, "\n")) do
        line = CleveRoids.Trim(line)
        local cmd, args = CleveRoids.SplitCommandAndArgs(line)

        -- check for #showtooltip
        if i == 1 then
            local _, _, st, _, tt = string.find(line, "(#showtooltip)(%s?(.*))")

            -- if no #showtooltip, nothing to keep track of
            if not st then
                break
            end

            hasShowTooltip = true
            tt = CleveRoids.Trim(tt)

            -- #showtooltip and item/spell/macro specified, only use this tooltip
            if st and tt ~= "" then
                showTooltipHasArg = true
                for _, arg in ipairs(CleveRoids.splitStringIgnoringQuotes(tt)) do
                    -- Parse the arg to extract the spell name from any conditionals
                    local parsedArg = CleveRoids.GetParsedMsg(arg)
                    macro.actions.tooltip = CleveRoids.CreateActionInfo(parsedArg)
                    local action = CleveRoids.CreateActionInfo(parsedArg)
                    action.cmd = "/cast"
                    action.args = arg
                    action.isReactive = CleveRoids.reactiveSpells[action.action]
                    table.insert(macro.actions.list, action)
                end
                break
            end
        else
            -- make sure we have a testable action
            if line ~= "" and args ~= "" and CleveRoids.dynamicCmds[cmd] then
                for _, arg in ipairs(CleveRoids.splitStringIgnoringQuotes(args)) do
                    local action = CleveRoids.CreateActionInfo(CleveRoids.GetParsedMsg(arg))

                    if cmd == "/castsequence" then
                        local sequence = CleveRoids.GetSequence(args)
                        if sequence then
                            action.sequence = sequence
                        end
                    end
                    action.cmd = cmd
                    action.args = arg
                    action.isReactive = CleveRoids.reactiveSpells[action.action]
                    table.insert(macro.actions.list, action)
                end
            end
        end
    end

    -- If #showtooltip was present but had no argument, use the first action as the tooltip
    if hasShowTooltip and not showTooltipHasArg and table.getn(macro.actions.list) > 0 then
        macro.actions.tooltip = macro.actions.list[1]
    end

    -- Store whether #showtooltip had an explicit argument (for icon fallback logic)
    macro.actions.explicitTooltip = showTooltipHasArg

    CleveRoids.Macros[name] = macro
    return macro
end

function CleveRoids.ParseMsg(msg)
    if not msg then return end
    local conditionals = {}

    -- reset side flag for this parse
    CleveRoids._ignoretooltip = 0

    -- strip optional leading '?' and remember how many we stripped
    local ignorecount
    msg, ignorecount = string.gsub(CleveRoids.Trim(msg), "^%?", "")
    conditionals.ignoretooltip = ignorecount
    CleveRoids._ignoretooltip  = ignorecount

    -- capture a single [...] conditional block if present
    local _, cbEnd, conditionBlock = string.find(msg, "%[(.+)%]")

    -- split off flags/action after the condition block (or from start if none)
    local _, _, noSpam, cancelAura, action = string.find(
        string.sub(msg, (cbEnd or 0) + 1),
        "^%s*(!?)(~?)([^!~]+.*)"
    )
    action = CleveRoids.Trim(action or "")

    -- store the raw action for callers and strip trailing "(Rank X)" for comparisons
    conditionals.action = action
    action = string.gsub(action, "%s*%(.-%)%s*$", "")

    -- IMPORTANT: if there's NO conditional block, return nil conditionals so
    -- DoWithConditionals will hit the {macroName} execution branch.
    if not conditionBlock then
        local hasFlag = (noSpam and noSpam ~= "") or (cancelAura and cancelAura ~= "")
        if hasFlag and action ~= "" then
            if noSpam ~= "" then
                local spamCond = CleveRoids.GetSpammableConditional(action)
                if spamCond then
                    conditionals[spamCond] = { action }
                end
            end
            if cancelAura ~= "" then
                conditionals.cancelaura = action
            end
            return conditionals.action, conditionals
        end
        return conditionals.action, nil
    end

    -- With a condition block present, build out the conditionals table

    -- optional spam/cancel flags (apply only when we actually have a [] block)
    if noSpam and noSpam ~= "" then
        local spamCond = CleveRoids.GetSpammableConditional(action)
        if spamCond then
            conditionals[spamCond] = { action }
        end
    end
    if cancelAura and cancelAura ~= "" then
        conditionals.cancelaura = action
    end

    -- Set the action's target to @unitid if found (e.g., @mouseover)
    local _, _, target = string.find(conditionBlock, "(@[^%s,]+)")
    if target then
        conditionBlock = CleveRoids.Trim(string.gsub(conditionBlock, target, ""))
        conditionals.target = string.sub(target, 2)
    end

    if conditionBlock and conditionals.action then
        -- Split the conditional block by comma or space
        for _, conditionGroups in CleveRoids.splitStringIgnoringQuotes(conditionBlock, {",", " "}) do
            if conditionGroups ~= "" then
                -- Split conditional groups by colon
                local conditionGroup = CleveRoids.splitStringIgnoringQuotes(conditionGroups, ":")
                local condition, args = conditionGroup[1], conditionGroup[2]

                -- No args → the action is the implicit argument
                if not args or args == "" then
                    if not conditionals[condition] then
                        -- Check if this is a boolean conditional (combat, stealth, channeled, etc.)
                        local booleanConditionals = {
                            combat = true,
                            nocombat = true,
                            stealth = true,
                            nostealth = true,
                            channeled = true,
                            nochanneled = true,
                            dead = true,
                            alive = true,
                            help = true,
                            harm = true,
                            exists = true,
                            party = true,
                            raid = true,
                            resting = true,
                            noresting = true,
                            isplayer = true,
                            isnpc = true,
                            mhimbue = true,
                            nomhimbue = true,
                            ohimbue = true,
                            noohimbue = true,
                        }

                        if booleanConditionals[condition] then
                            conditionals[condition] = true
                        else
                            conditionals[condition] = conditionals.action
                        end
                    else
                        -- existing code for when conditionals[condition] already exists
                        if type(conditionals[condition]) ~= "table" then
                            conditionals[condition] = { conditionals[condition] }
                        end
                        table.insert(conditionals[condition], conditionals.action)
                    end
                else
                    -- Has args. Ensure the key's value is a table and add new arguments.
                    if not conditionals[condition] then
                        conditionals[condition] = {}
                    elseif type(conditionals[condition]) ~= "table" then
                        conditionals[condition] = { conditionals[condition] }
                    end

                    -- Split args by '/' for multiple values
                    for _, arg_item in CleveRoids.splitString(args, "/") do
                        local processed_arg = CleveRoids.Trim(arg_item)

                        processed_arg = string.gsub(processed_arg, '"', "")
                        processed_arg = string.gsub(processed_arg, "_", " ")
                        processed_arg = CleveRoids.Trim(processed_arg)

                        -- normalize "name#N" → "name=#N" and "#N" → "=#N"
                        local arg_for_find = processed_arg
                        arg_for_find = string.gsub(arg_for_find, "^#(%d+)$", "=#%1")
                        arg_for_find = string.gsub(arg_for_find, "([^>~=<]+)#(%d+)", "%1=#%2")

                        -- accept decimals too; capture name/op/amount
                        local _, _, name, operator, amount = string.find(arg_for_find, "([^>~=<]*)([>~=<]+)(#?%d*%.?%d+)")

                        if not operator or not amount then
                            -- No operator found, treat as simple string argument
                            table.insert(conditionals[condition], processed_arg)
                        else
                            local name_to_use = (name and name ~= "") and name or conditionals.action
                            local final_amount_str, num_replacements = string.gsub(amount, "#", "")
                            local should_check_stacks = (num_replacements == 1)

                            -- SPECIAL HANDLING FOR STAT CONDITIONALS WITH MULTIPLE COMPARISONS
                            -- Detect if this is a stat conditional with multiple operators
                            -- Example: "ap>1800/<2200" should create comparisons for both >1800 and <2200
                            if (condition == "stat" or condition == "nostat") and string.find(processed_arg, "[>~=<]+%d+[^%d]+[>~=<]") then
                                -- This arg has multiple comparisons, parse them all
                                local stat_name = name_to_use
                                local comparisons = {}

                                -- Extract all operator+number pairs
                                -- Pattern matches operator followed by optional decimal number
                                local gfind_func = string.gfind or string.gmatch
                                for op, num in gfind_func(processed_arg, "([>~=<]+)(#?%d*%.?%d+)") do
                                    local clean_num = string.gsub(num, "#", "")
                                    local check_stacks = (string.find(num, "#") ~= nil)
                                    table.insert(comparisons, {
                                        operator = op,
                                        amount = tonumber(clean_num),
                                        checkStacks = check_stacks
                                    })
                                end

                                if table.getn(comparisons) > 0 then
                                    table.insert(conditionals[condition], {
                                        name = CleveRoids.Trim(stat_name),
                                        comparisons = comparisons  -- Store all comparisons
                                    })
                                else
                                    -- Fallback to single comparison if parsing failed
                                    table.insert(conditionals[condition], {
                                        name = CleveRoids.Trim(name_to_use),
                                        operator = operator,
                                        amount = tonumber(final_amount_str),
                                        checkStacks = should_check_stacks
                                    })
                                end
                            else
                                -- Normal single-comparison conditional (existing behavior)
                                table.insert(conditionals[condition], {
                                    name = CleveRoids.Trim(name_to_use),
                                    operator = operator,
                                    amount = tonumber(final_amount_str),
                                    checkStacks = should_check_stacks
                                })
                            end
                        end
                    end
                end
            end
        end
        return conditionals.action, conditionals
    end
end


-- Get previously parsed or parse, store and return
function CleveRoids.GetParsedMsg(msg)
    if not msg then return end

    -- ALWAYS refresh the side-flag for '?' even when we hit the cache
    local _, ignorecount = string.gsub(CleveRoids.Trim(msg), "^%?", "")
    CleveRoids._ignoretooltip = ignorecount

    local cached = CleveRoids.ParsedMsg[msg]
    if cached then
        -- keep a per-msg copy too (helps future readers/tools)
        cached.ignoretooltip = cached.ignoretooltip or ignorecount
        return cached.action, cached.conditionals
    end

    local action, conditionals = CleveRoids.ParseMsg(msg)
    CleveRoids.ParsedMsg[msg] = {
        action         = action,
        conditionals   = conditionals,
        ignoretooltip  = ignorecount,
    }
    return action, conditionals
end


function CleveRoids.GetMacro(name)
    return CleveRoids.Macros[name] or CleveRoids.ParseMacro(name)
end

function CleveRoids.GetSequence(args)
    return CleveRoids.Sequences[args] or CleveRoids.ParseSequence(args)
end

function CleveRoids.GetCurrentSequenceAction(sequence)
    return sequence.list[sequence.index]
end

function CleveRoids.ResetSequence(sequence)
    sequence.index = 1
end

function CleveRoids.AdvanceSequence(sequence)
    if sequence.index < table.getn(sequence.list) then
        -- Not at the end yet, just advance normally
        sequence.index = sequence.index + 1
    else
        -- At the end of sequence - check if we should auto-reset or stay at last step
        local hasNonModifierReset = false

        if sequence.reset then
            -- Check if there are any reset conditions besides modifier keys
            for k, _ in pairs(sequence.reset) do
                -- target, combat, secs are non-modifier resets
                if k ~= "alt" and k ~= "ctrl" and k ~= "shift" then
                    hasNonModifierReset = true
                    break
                end
            end
        end

        -- Only auto-reset if:
        -- 1. No reset table exists at all, OR
        -- 2. Reset table only contains modifier keys (alt/ctrl/shift)
        -- Otherwise, stay on the last step and keep casting it until reset fires
        if not hasNonModifierReset then
            CleveRoids.ResetSequence(sequence)
        end
        -- If hasNonModifierReset is true, sequence.index stays at max,
        -- so GetCurrentSequenceAction will keep returning the last spell
    end
end

function CleveRoids.TestAction(cmd, args)
    local msg, conditionals = CleveRoids.GetParsedMsg(args)

    -- Nil-safe guards
    local hasShowTooltip = (type(msg) == "string") and string.find(msg, "#showtooltip")
    local ignoreTooltip  = ((type(conditionals) == "table") and (conditionals.ignoretooltip == 1))
                           or (CleveRoids._ignoretooltip == 1)

    -- If the line is explicitly ignored for tooltip (via '?'),
    -- or it is a '#showtooltip' token, do not contribute icon/tooltip.
    if hasShowTooltip or ignoreTooltip then
        CleveRoids._ignoretooltip = 0 -- clear for next parse
        return
    end

    -- No [] block → return a testable token so the UI can pick a texture
    if not conditionals then
        if not msg or msg == "" then
            return
        else
            return CleveRoids.GetMacroNameFromAction(msg) or msg
        end
    end

    local origTarget = conditionals.target
    if cmd == "" or not CleveRoids.dynamicCmds[cmd] then
        return
    end

    if conditionals.target == "focus" then
        local focusUnitId = nil
        if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.label and pfUI.uf.focus.id
           and UnitExists(pfUI.uf.focus.label .. pfUI.uf.focus.id) then
            focusUnitId = pfUI.uf.focus.label .. pfUI.uf.focus.id
        end
        if focusUnitId then
            conditionals.target = focusUnitId
        else
            if not CleveRoids.GetFocusName() then
                return
            end
            conditionals.target = "target"
        end
    end

    if conditionals.target == "mouseover" then
        if not CleveRoids.IsValidTarget("mouseover", conditionals.help) then
            return false
        end
    end

    CleveRoids.FixEmptyTarget(conditionals)

    for k, v in pairs(conditionals) do
        if not CleveRoids.ignoreKeywords[k] then
            if not CleveRoids.Keywords[k] or not CleveRoids.Keywords[k](conditionals) then
                conditionals.target = origTarget
                return
            end
        end
    end

    conditionals.target = origTarget
    return CleveRoids.GetMacroNameFromAction(msg) or msg
end

function CleveRoids.DoWithConditionals(msg, hook, fixEmptyTargetFunc, targetBeforeAction, action)
    local msg, conditionals = CleveRoids.GetParsedMsg(msg)

    -- No conditionals. Just exit.
    if not conditionals then
        if not msg then -- if not even an empty string
            return false
        else
            if string.sub(msg, 1, 1) == "{" and string.sub(msg, -1) == "}" then
                if string.sub(msg, 2, 2) == "\"" and string.sub(msg, -2, -2) == "\"" then
                    return CleveRoids.ExecuteMacroBody(string.sub(msg, 3, -3), true)
                else
                    return CleveRoids.ExecuteMacroByName(string.sub(msg, 2, -2))
                end
            end

            if hook then
                hook(msg)
            end
            return true
        end
    end

    if conditionals.cancelaura then
        if CleveRoids.CancelAura(conditionals.cancelaura) then
            return true
        end
    end

    local origTarget = conditionals.target
    if conditionals.target == "mouseover" then
        if UnitExists("mouseover") then
            conditionals.target = "mouseover"
        elseif CleveRoids.mouseoverUnit and UnitExists(CleveRoids.mouseoverUnit) then
            conditionals.target = CleveRoids.mouseoverUnit
        else
            conditionals.target = "mouseover"
        end
    end

    local needRetarget = false
    if fixEmptyTargetFunc then
        needRetarget = fixEmptyTargetFunc(conditionals, msg, hook)
    end

    -- CleveRoids.SetHelp(conditionals)

    if conditionals.target == "focus" then
        local focusUnitId = nil

        -- Attempt to get the direct UnitID from pfUI's focus frame data. This is more reliable.
        if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.label and pfUI.uf.focus.id and UnitExists(pfUI.uf.focus.label .. pfUI.uf.focus.id) then
            focusUnitId = pfUI.uf.focus.label .. pfUI.uf.focus.id
        end

        if focusUnitId then
                -- If we found a valid UnitID, we will use it for all subsequent checks and the final cast.
                -- This avoids changing the player's actual target.
            conditionals.target = focusUnitId
            needRetarget = false
        else
            -- return false if pfUI is installed and no focus is set instead of "invalid target"
            if pfUI and (pfUI.uf.focus.label == nil or pfUI.uf.focus.label == "") then return false end
            -- If the direct UnitID isn't found, fall back to the original (but likely failing) method of targeting by name.
            if not CleveRoids.TryTargetFocus() then
                UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1.0, 0.0, 0.0, 1.0)
                conditionals.target = origTarget
                return false
            end
            conditionals.target = "target"
            needRetarget = true
        end
    end

    for k, v in pairs(conditionals) do
        if not CleveRoids.ignoreKeywords[k] then
            if not CleveRoids.Keywords[k] or not CleveRoids.Keywords[k](conditionals) then
                if needRetarget then
                    TargetLastTarget()
                    needRetarget = false
                end
                conditionals.target = origTarget
                return false
            end
        end
    end

    if conditionals.target ~= nil and targetBeforeAction and not (CleveRoids.hasSuperwow and action == CastSpellByName) then
        if not UnitIsUnit("target", conditionals.target) then
            if SpellIsTargeting() then
                SpellStopCasting()
            end
            TargetUnit(conditionals.target)
            needRetarget = true
        else
             if needRetarget then needRetarget = false end
        end
    elseif needRetarget then
        TargetLastTarget()
        needRetarget = false
    end

    if action == "STOPMACRO" then
        CleveRoids.stopmacro = true
        return true
    end

    local result = true
    if string.sub(msg, 1, 1) == "{" and string.sub(msg, -1) == "}" then
        if string.sub(msg, 2, 2) == "\"" and string.sub(msg, -2,-2) == "\"" then
            result = CleveRoids.ExecuteMacroBody(string.sub(msg, 3, -3), true)
        else
            result = CleveRoids.ExecuteMacroByName(string.sub(msg, 2, -2))
        end
    else -- This 'else' corresponds to 'if string.sub(msg, 1, 1) == "{"...'
        local castMsg = msg
        -- FLEXIBLY check for any rank text like "(Rank 9)" before adding the highest rank
        if action == CastSpellByName and not string.find(msg, "%(.*%)") then
            local sp = CleveRoids.GetSpell(msg)
            local rank = sp and (sp.rank or (sp.highest and sp.highest.rank))
            if rank and rank ~= "" then
                castMsg = msg .. "(" .. rank .. ")"
            end
        end
        if CleveRoids.hasSuperwow and action == CastSpellByName and conditionals.target then
            CastSpellByName(castMsg, conditionals.target) -- SuperWoW handles targeting via argument
        elseif action == CastSpellByName then
             action(castMsg)
        else
            -- For other actions like UseContainerItem etc.
            action(msg)
        end
    end

    if needRetarget then
        TargetLastTarget()
    end

    conditionals.target = origTarget
    return result
end

function CleveRoids.DoCast(msg)
    local handled = false

    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        -- Define a custom action that handles both regular and pet spells
        local castAction = function(spellName)
            -- First try regular spell
            local spell = CleveRoids.GetSpell(spellName)
            if spell then
                if CleveRoids.hasSuperwow then
                    local castMsg = spellName
                    if not string.find(spellName, "%(.*%)") then
                        local rank = spell.rank or (spell.highest and spell.highest.rank)
                        if rank and rank ~= "" then
                            castMsg = spellName .. "(" .. rank .. ")"
                        end
                    end
                    CastSpellByName(castMsg)
                else
                    CastSpellByName(spellName)
                end
                return true
            end

            -- If not a regular spell, try pet spell
            local petSpell = CleveRoids.GetPetSpell(spellName)
            if petSpell and petSpell.slot then
                CastPetAction(petSpell.slot)
                return true
            end

            return false
        end

        if CleveRoids.DoWithConditionals(v, CleveRoids.Hooks.CAST_SlashCmd, CleveRoids.FixEmptyTarget, not CleveRoids.hasSuperwow, CastSpellByName) then
            return true
        end
    end
    return false
end

function CleveRoids.DoCastPet(msg)
    local handled = false

    local action = function(spellName)
        local petSpell = CleveRoids.GetPetSpell(spellName)
        if petSpell and petSpell.slot then
            CastPetAction(petSpell.slot)
            return true
        end
        return false
    end

    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end

    return handled
end

function CleveRoids.DoTarget(msg)
    local action, conditionals = CleveRoids.GetParsedMsg(msg)

    if action ~= "" or type(conditionals) ~= "table" or not next(conditionals) then
        CleveRoids.Hooks.TARGET_SlashCmd(msg)
        return true
    end

    local function IsGuidValid(unitTok, conds)
        if not unitTok or not UnitExists(unitTok) or UnitIsDeadOrGhost(unitTok) then
            return false
        end
        local orig = conds.target
        conds.target = unitTok
        local ok = true
        for k, _ in pairs(conds) do
            if not CleveRoids.ignoreKeywords[k] then
                local fn = CleveRoids.Keywords[k]
                if not fn or not fn(conds) then ok = false; break end
            end
        end
        conds.target = orig
        return ok
    end

    do
        local unitTok = conditionals.target

        if unitTok == "mouseover" then
            if UnitExists("mouseover") then
                unitTok = "mouseover"
            elseif CleveRoids.mouseoverUnit and UnitExists(CleveRoids.mouseoverUnit) then
                unitTok = CleveRoids.mouseoverUnit
            elseif pfUI and pfUI.uf and pfUI.uf.mouseover and pfUI.uf.mouseover.unit
               and UnitExists(pfUI.uf.mouseover.unit) then
                unitTok = pfUI.uf.mouseover.unit
            else
                unitTok = nil
            end
        end

        if unitTok == "focus" and pfUI and pfUI.uf and pfUI.uf.focus
           and pfUI.uf.focus.label and pfUI.uf.focus.id then
            local fTok = pfUI.uf.focus.label .. pfUI.uf.focus.id
            if UnitExists(fTok) then unitTok = fTok else unitTok = nil end
        end

        if unitTok and UnitExists(unitTok) and IsGuidValid(unitTok, conditionals) then
            TargetUnit(unitTok)
            return true
        end
    end

    if UnitExists("target") and IsGuidValid("target", conditionals) then
        return true
    end

    local candidates = {}
    local wantsHelp = conditionals.help
    local wantsHarm = conditionals.harm

    local function addCandidate(unitId)
        if not UnitExists(unitId) then return end

        if wantsHelp and not UnitCanAssist("player", unitId) then return end

        if wantsHarm and not UnitCanAttack("player", unitId) then return end

        table.insert(candidates, { unitId = unitId })
    end

    addCandidate("mouseover")

    addCandidate("target")

    if not wantsHarm then
        table.insert(candidates, { unitId = "player" })
    end

    addCandidate("pet")

    for i = 1, 4 do
        addCandidate("party"..i)
        addCandidate("partypet"..i)
        addCandidate("party"..i.."target")
    end

    for i = 1, 40 do
        addCandidate("raid"..i)
        addCandidate("raidpet"..i)
        addCandidate("raid"..i.."target")
    end

    addCandidate("targettarget")
    addCandidate("targettargettarget")

    addCandidate("pettarget")

    if pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.label and pfUI.uf.focus.id then
        local focusTok = pfUI.uf.focus.label .. pfUI.uf.focus.id
        addCandidate(focusTok)
    end

    if CleveRoids.hasSuperwow then
        local numChildren = WorldFrame:GetNumChildren()
        local children = { WorldFrame:GetChildren() }

        for i = 1, numChildren do
            local frame = children[i]
            if frame and frame:IsVisible() then
                local success, guid = pcall(frame.GetName, frame, 1)
                if success and guid and type(guid) == "string" and string.len(guid) > 0 then
                    if UnitExists(guid) then
                        addCandidate(guid)
                    end
                end
            end
        end
    end

    for _, c in ipairs(candidates) do
        if IsGuidValid(c.unitId, conditionals) then
            TargetUnit(c.unitId)
            return true
        end
    end

    return true
end

-- Attempts to attack a unit by a set of conditionals
-- msg: The raw message intercepted from a /petattack command
function CleveRoids.DoPetAction(action, msg)
    local handled = false

    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, true, action) then
            handled = true
            break
        end
    end
    return handled
end

-- Attempts to conditionally start an attack. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStartAttack(msg)
    if not string.find(msg, "%[") then return false end

    local handled = false
    local action = function()
        if not UnitExists("target") or UnitIsDead("target") then TargetNearestEnemy() end
        if not CleveRoids.CurrentSpell.autoAttack and not CleveRoids.CurrentSpell.autoAttackLock and UnitExists("target") and UnitCanAttack("player", "target") then
            CleveRoids.CurrentSpell.autoAttackLock = true
            CleveRoids.autoAttackLockElapsed = GetTime()
            AttackTarget()
        end
    end

    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        -- We pass 'nil' for the hook, so DoWithConditionals does nothing if it fails to parse conditionals.
        if CleveRoids.DoWithConditionals(v, nil, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end
    return handled
end

-- Attempts to conditionally stop an attack. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStopAttack(msg)
    if not string.find(msg, "%[") then return false end

    local handled = false
    local action = function()
        if CleveRoids.CurrentSpell.autoAttack and UnitExists("target") then
            AttackTarget()
            CleveRoids.CurrentSpell.autoAttack = false
        end
    end

    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        if CleveRoids.DoWithConditionals(v, nil, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end
    return handled
end

-- Attempts to conditionally stop casting. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStopCasting(msg)
    if not string.find(msg, "%[") then return false end

    local handled = false
    local action = function()
        SpellStopCasting()
    end

    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        if CleveRoids.DoWithConditionals(v, nil, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end
    return handled
end


-- Attempts to use or equip an item by a set of conditionals
-- Also checks if a condition is a spell so that you can mix item and spell use
-- msg: The raw message intercepted from a /use or /equip command
function CleveRoids.DoUse(msg)
    local handled = false

    local action = function(msg)
        -- Defensive: make sure we are not in "split stack" mode and nothing is on the cursor
        if type(CloseStackSplitFrame) == "function" then CloseStackSplitFrame() end
        if CursorHasItem and CursorHasItem() then ClearCursor() end

        -- Try to interpret the message as a direct inventory slot ID first.
        local slotId = tonumber(msg)
        if slotId and slotId >= 1 and slotId <= 19 then -- Character slots are 1-19
            ClearCursor() -- extra safety before using equipped items
            UseInventoryItem(slotId)
            return
        end

        -- NEW: Try to interpret as an item ID (numeric but > 19)
        if slotId and slotId > 19 then
            -- Search equipped slots for this item ID
            for slot = 0, 19 do
                local link = GetInventoryItemLink("player", slot)
                if link then
                    local _, _, id = string.find(link, "item:(%d+)")
                    if id and tonumber(id) == slotId then
                        ClearCursor()
                        UseInventoryItem(slot)
                        return
                    end
                end
            end

            -- Search bags for this item ID
            for bag = 0, 4 do
                local size = GetContainerNumSlots(bag) or 0
                for bagSlot = 1, size do
                    local link = GetContainerItemLink(bag, bagSlot)
                    if link then
                        local _, _, id = string.find(link, "item:(%d+)")
                        if id and tonumber(id) == slotId then
                            ClearCursor()
                            UseContainerItem(bag, bagSlot)
                            return
                        end
                    end
                end
            end

            -- Item ID not found
            return
        end

        -- Resolve by name/id via our cache
        local item = CleveRoids.GetItem(msg) -- looks in equipped, then bags
        if not item then return end

        -- If it's an equipped item (trinket etc.), use it directly
        if item.inventoryID then
            ClearCursor()
            UseInventoryItem(item.inventoryID)
            return
        end

        -- Otherwise, use the bag item
        if item.bagID and item.slot then
            -- If we tracked multiple stacks, advance politely
            CleveRoids.GetNextBagSlotForUse(item, msg)

            ClearCursor()
            UseContainerItem(item.bagID, item.slot)
            return
        end
    end

    for _, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end
    return handled
end

function CleveRoids.EquipBagItem(msg, offhand)
    if CleveRoids.equipInProgress then
        return false
    end

    local now = GetTime()
    if (now - (CleveRoids.lastItemIndexTime or 0)) > 0.5 then
        CleveRoids.IndexItems()
        CleveRoids.lastItemIndexTime = now
    end

    local item = CleveRoids.GetItem(msg)
    if not item or not item.name then
        CleveRoids.IndexItems()
        CleveRoids.lastItemIndexTime = now
        item = CleveRoids.GetItem(msg)
        if not item or not item.name then
            return false
        end
    end

    local invslot = offhand and 17 or 16
    local throttleKey = invslot .. "_" .. (item.id or item.name)

    if UnitAffectingCombat("player") and (invslot == 16 or invslot == 17) then
        local timeSinceLastSwap = now - CleveRoids.lastWeaponSwapTime
        if timeSinceLastSwap < 1.5 then
            return false
        end
    end

    if CleveRoids.lastEquipTime[throttleKey] and (now - CleveRoids.lastEquipTime[throttleKey]) < 0.2 then
        return false
    end

    local currentItemLink = GetInventoryItemLink("player", invslot)
    if currentItemLink then
        local _, _, currentID = string.find(currentItemLink, "item:(%d+)")
        local currentItemName = GetItemInfo(currentItemLink)

        if (currentID and item.id and tonumber(currentID) == tonumber(item.id)) or
           (currentItemName and currentItemName == item.name) then
            CleveRoids.lastEquipTime[throttleKey] = now
            return true
        end
    end

    if not item.bagID and not item.inventoryID then
        return false
    end

    CleveRoids.equipInProgress = true

    if type(CloseStackSplitFrame) == "function" then
        CloseStackSplitFrame()
    end
    if CursorHasItem and CursorHasItem() then
        ClearCursor()
        CleveRoids.equipInProgress = false
        return false
    end

    local pickupSuccess = false
    if item.bagID and item.slot then
        CleveRoids.GetNextBagSlotForUse(item, msg)

        local link = GetContainerItemLink(item.bagID, item.slot)
        if link then
            local _, _, bagItemID = string.find(link, "item:(%d+)")
            if bagItemID and item.id and tonumber(bagItemID) == tonumber(item.id) then
                PickupContainerItem(item.bagID, item.slot)
                pickupSuccess = true
            end
        end
    elseif item.inventoryID then
        PickupInventoryItem(item.inventoryID)
        pickupSuccess = true
    end

    if not pickupSuccess then
        CleveRoids.equipInProgress = false
        CleveRoids.lastItemIndexTime = 0
        return false
    end

    if not CursorHasItem or not CursorHasItem() then
        ClearCursor()
        CleveRoids.equipInProgress = false
        CleveRoids.lastItemIndexTime = 0
        return false
    end

    EquipCursorItem(invslot)

    ClearCursor()

    CleveRoids.lastEquipTime[throttleKey] = now

    if UnitAffectingCombat("player") and (invslot == 16 or invslot == 17) then
        CleveRoids.lastWeaponSwapTime = now
    end

    CleveRoids.equipInProgress = false

    CleveRoids.IndexItems()
    CleveRoids.lastItemIndexTime = now

    return true
end

function CleveRoids.DoEquipMainhand(msg)
    local handled = false
    local action = function(msg)
        return CleveRoids.EquipBagItem(msg, false)
    end
    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        v = string.gsub(v, "^%?", "")
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end
    return handled
end

function CleveRoids.DoEquipOffhand(msg)
    local handled = false
    local action = function(msg)
        return CleveRoids.EquipBagItem(msg, true)
    end
    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        v = string.gsub(v, "^%?", "")
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end
    return handled
end

function CleveRoids.DoUnshift(msg)
    local handled

    local action = function(msg)
        local currentShapeshiftIndex = CleveRoids.GetCurrentShapeshiftIndex()
        if currentShapeshiftIndex ~= 0 then
            CastShapeshiftForm(currentShapeshiftIndex)
        end
    end

    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        handled = false
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end

    if handled == nil then
        action()
    end

    return handled
end

function CleveRoids.DoRetarget()
    if GetUnitName("target") == nil
        or UnitHealth("target") == 0
        or not UnitCanAttack("player", "target")
    then
        ClearTarget()
        TargetNearestEnemy()
    end
end

-- Attempts to stop macro
 function CleveRoids.DoStopMacro(msg)
    local handled = false
    for k, v in pairs(CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))) do
        if CleveRoids.DoWithConditionals(msg, nil, nil, not CleveRoids.hasSuperwow, "STOPMACRO") then
            handled = true -- we parsed at least one command
            break
        end
    end
    return handled
end

function CleveRoids.DoCastSequence(sequence)
  if not CleveRoids.hasSuperwow then
    CleveRoids.Print("|cFFFF0000/castsequence|r requires |cFF00FFFFSuperWoW|r.")
    return
  end
  if type(sequence) == "string" then
    sequence = CleveRoids.GetSequence(sequence)
    if not sequence then return end
  end

  if CleveRoids.currentSequence and not CleveRoids.CheckSpellCast("player") then
    CleveRoids.currentSequence = nil
  elseif CleveRoids.currentSequence then
    return
  end

  -- If sequence is complete, don't execute - let macro continue to next line
  if sequence.complete then
    return
  end

  if sequence.index > 1 and sequence.reset then
    for k,_ in pairs(sequence.reset) do
      if CleveRoids.kmods[k] and CleveRoids.kmods[k]() then
        CleveRoids.ResetSequence(sequence)
        break
      end
    end
  end

  local active = CleveRoids.GetCurrentSequenceAction(sequence)
  if not (active and active.action) then return end

  sequence.status     = 0
  sequence.lastUpdate = GetTime()
  sequence.expires    = 0

  local prevSeq = CleveRoids.currentSequence
  CleveRoids.currentSequence = sequence

  local actionText = (sequence.cond or "") .. active.action
  local resolvedText, conds = CleveRoids.GetParsedMsg(actionText)

  -- Check if this is a macro execution {macroname}
  local macroName = CleveRoids.GetMacroNameFromAction(active.action)
  if macroName then
    -- Execute the macro
    local success = CleveRoids.ExecuteMacroByName(macroName)
    if not success then
      CleveRoids.currentSequence = prevSeq
    end
    return
  end

  local function cast_by_name(msg)
    msg = msg or ""
    if not string.find(msg, "%(%s*.-%s*%)%s*$") then
      local sp = CleveRoids.GetSpell(msg)
      local r  = (sp and sp.rank) or (sp and sp.highest and sp.highest.rank)
      if r and r ~= "" then msg = msg .. "(" .. r .. ")" end
    end
    CastSpellByName(msg)
    return true
  end

  local attempted = false
  if not conds then
    attempted = cast_by_name(resolvedText or active.action)
  else
    local final = CleveRoids.DoWithConditionals(actionText, nil, CleveRoids.FixEmptyTarget, false, CastSpellByName)
    if final then attempted = cast_by_name(final) end
  end

  if not attempted then
    CleveRoids.currentSequence = prevSeq
  end
end

CleveRoids.DoConditionalCancelAura = function(msg)
  local s = CleveRoids.Trim(msg or "")
  if s == "" then return false end

  -- No conditionals? cancel immediately.
  if not string.find(s, "%[") then
    return CleveRoids.CancelAura(s)
  end

  -- Has conditionals? Let the framework evaluate them, then run CancelAura.
  return CleveRoids.DoWithConditionals(s, nil, CleveRoids.FixEmptyTarget, false, CleveRoids.CancelAura) or false
end

function CleveRoids.OnUpdate(self)
    -- Process equipment queue
    if CleveRoids.ProcessEquipmentQueue then
        CleveRoids.ProcessEquipmentQueue()
    end

    -- Update casting state from Nampower
    if CleveRoids.UpdateCastingState then
        CleveRoids.UpdateCastingState()
    end

    local time = GetTime()
	local refreshRate = CleveRoidMacros.refresh or 5
	refreshRate = 1/refreshRate
    if CleveRoids.initializationTimer and time >= CleveRoids.initializationTimer then
        CleveRoids.IndexItems()
        CleveRoids.IndexActionBars()
        CleveRoids.ready = true
        CleveRoids.initializationTimer = nil
        CleveRoids.TestForAllActiveActions()
        CleveRoids.lastUpdate = time
        return
    end
    if not CleveRoids.ready then return end

    -- Throttle the update loop to avoid excessive CPU usage.
    if (time - CleveRoids.lastUpdate) < refreshRate then return end
    CleveRoids.lastUpdate = time
    -- Check the saved variable to decide which update mode to use.
    if CleveRoidMacros.realtime == 1 then
        -- Realtime Mode: Force an update on every throttled tick for maximum responsiveness.
        CleveRoids.TestForAllActiveActions()
    else
        -- Event-Driven Mode (Default): Only update if a relevant game event has queued it.
        if CleveRoids.isActionUpdateQueued then
            CleveRoids.TestForAllActiveActions()
            CleveRoids.isActionUpdateQueued = false -- Reset the flag after updating
        end
    end

    -- The rest of this function handles time-based logic that must always run.
    if CleveRoids.CurrentSpell.autoAttackLock and (time - CleveRoids.autoAttackLockElapsed) > refreshRate then
        CleveRoids.CurrentSpell.autoAttackLock = false
        CleveRoids.autoAttackLockElapsed = nil
    end

    for _, sequence in pairs(CleveRoids.Sequences) do
        if sequence.index > 1 and sequence.reset.secs and (time - (sequence.lastUpdate or 0)) >= sequence.reset.secs then
            CleveRoids.ResetSequence(sequence)
        end
    end

    for guid,cast in pairs(CleveRoids.spell_tracking) do
        if cast.expires and time > cast.expires then
            CleveRoids.spell_tracking[guid] = nil
        end
    end
end

-- Initialize the nested table for the GameTooltip hooks if it doesn't exist
if not CleveRoids.Hooks.GameTooltip then CleveRoids.Hooks.GameTooltip = {} end

-- Save the original GameTooltip.SetAction function before we override it
CleveRoids.Hooks.GameTooltip.SetAction = GameTooltip.SetAction

-- Now, define our custom version of the function
function GameTooltip.SetAction(self, slot)
    local actions = CleveRoids.GetAction(slot)

    local action_to_display_info = nil
    if actions then
        if actions.active then
            action_to_display_info = actions.active
        elseif actions.tooltip then
            action_to_display_info = actions.tooltip
        end
    end

    if action_to_display_info and action_to_display_info.action then
        local action_name = action_to_display_info.action

        -- NEW: Check if action is a slot ID for tooltip
        local slotId = tonumber(action_name)
        if slotId and slotId >= 1 and slotId <= 19 then
            -- Use the more specific SetInventoryItem function to prevent conflicts with other addons.
            GameTooltip:SetInventoryItem("player", slotId)
            GameTooltip:Show()
            return
        end
        -- End new logic

        local current_spell_data = CleveRoids.GetSpell(action_name)
        if current_spell_data then
            GameTooltip:SetSpell(current_spell_data.spellSlot, current_spell_data.bookType)
            local rank_info = current_spell_data.rank or (current_spell_data.highest and current_spell_data.highest.rank)
            if rank_info and rank_info ~= "" then
                GameTooltipTextRight1:SetText("|cff808080" .. rank_info .. "|r")
            else
                GameTooltipTextRight1:SetText("")
            end
            GameTooltipTextRight1:Show()
            GameTooltip:Show()
            return
        end

        local current_item_data = CleveRoids.GetItem(action_name)
        if current_item_data then
            -- Use specific functions based on where the item is located.
            if current_item_data.inventoryID then
                GameTooltip:SetInventoryItem("player", current_item_data.inventoryID)
            elseif current_item_data.bagID and current_item_data.slot then
                GameTooltip:SetBagItem(current_item_data.bagID, current_item_data.slot)
            else
                -- Fallback to the original method if location is unknown.
                GameTooltip:SetHyperlink(current_item_data.link)
            end
            GameTooltip:Show()
            return
        end

        if action_to_display_info.macro and type(action_to_display_info.macro) == "table" then
            local nested_action_info = action_to_display_info.macro
            local nested_action_name = nested_action_info.action

            current_spell_data = CleveRoids.GetSpell(nested_action_name)
            if current_spell_data then
                GameTooltip:SetSpell(current_spell_data.spellSlot, current_spell_data.bookType)
                local rank_info = current_spell_data.rank or (current_spell_data.highest and current_spell_data.highest.rank)
                if rank_info and rank_info ~= "" then
                    GameTooltipTextRight1:SetText("|cff808080" .. rank_info .. "|r")
                else
                    GameTooltipTextRight1:SetText("")
                end
                GameTooltipTextRight1:Show()
                GameTooltip:Show()
                return
            end

            current_item_data = CleveRoids.GetItem(nested_action_name)
            if current_item_data then
                 if current_item_data.inventoryID then
                    GameTooltip:SetInventoryItem("player", current_item_data.inventoryID)
                elseif current_item_data.bagID and current_item_data.slot then
                    GameTooltip:SetBagItem(current_item_data.bagID, current_item_data.slot)
                else
                    GameTooltip:SetHyperlink(current_item_data.link)
                end
                GameTooltip:Show()
                return
            end
        end
    end

    -- If none of our custom logic handled it, call the original function we saved earlier.
    CleveRoids.Hooks.GameTooltip.SetAction(self, slot)
end

CleveRoids.Hooks.PickupAction = PickupAction
function PickupAction(slot)
    CleveRoids.ClearAction(slot)
    CleveRoids.ClearSlot(CleveRoids.actionSlots, slot)
    CleveRoids.ClearAction(CleveRoids.reactiveSlots, slot)
    return CleveRoids.Hooks.PickupAction(slot)
end

CleveRoids.Hooks.ActionHasRange = ActionHasRange
function ActionHasRange(slot)
    local actions = CleveRoids.GetAction(slot)
    -- Use the same priority as GetActionTexture: active first, then tooltip
    local actionToCheck = (actions and actions.active) or (actions and actions.tooltip)
    if actionToCheck then
        return (1 and actionToCheck.inRange ~= -1 or nil)
    else
        return CleveRoids.Hooks.ActionHasRange(slot)
    end
end

CleveRoids.Hooks.IsActionInRange = IsActionInRange
function IsActionInRange(slot, unit)
    local actions = CleveRoids.GetAction(slot)
    -- Use the same priority as GetActionTexture: active first, then tooltip
    local actionToCheck = (actions and actions.active) or (actions and actions.tooltip)
    if actionToCheck and actionToCheck.type == "spell" then
        return actionToCheck.inRange
    else
        return CleveRoids.Hooks.IsActionInRange(slot, unit)
    end
end

CleveRoids.Hooks.OriginalIsUsableAction = IsUsableAction
CleveRoids.Hooks.IsUsableAction = IsUsableAction
function IsUsableAction(slot, unit)
    local actions = CleveRoids.GetAction(slot)
    -- Use the same priority as GetActionTexture: active first, then tooltip
    local actionToCheck = (actions and actions.active) or (actions and actions.tooltip)
    if actionToCheck then
        return actionToCheck.usable, actionToCheck.oom
    else
        return CleveRoids.Hooks.IsUsableAction(slot, unit)
    end
end

CleveRoids.Hooks.IsCurrentAction = IsCurrentAction
function IsCurrentAction(slot)
    local actions = CleveRoids.GetAction(slot)

    -- Use the same priority as GetActionTexture: active first, then tooltip
    local actionToCheck = (actions and actions.active) or (actions and actions.tooltip)

    if not actionToCheck then
        return CleveRoids.Hooks.IsCurrentAction(slot)
    else
        local name
        if actionToCheck.spell then
            local rank = actionToCheck.spell.rank or actionToCheck.spell.highest.rank
            name = actionToCheck.spell.name..(rank and ("("..rank..")"))

            -- Check if this spell is currently queued or being cast via Nampower
            if GetCurrentCastingInfo then
                local castId, visId, autoId, casting, channeling, onswing, autoattack = GetCurrentCastingInfo()

                -- Get spell ID for comparison
                local spellId = actionToCheck.spell.id
                if not spellId and GetSpellIdForName then
                    spellId = GetSpellIdForName(name)
                end

                -- Only show glow if spell is actively casting, channeling, or queued
                -- castId matches when spell is queued or being cast
                -- visId matches during channeling
                if spellId then
                    -- Show glow if actively casting/channeling this spell
                    if (casting == 1 and castId == spellId) or (channeling == 1 and visId == spellId) then
                        return true
                    end
                    -- Show glow if this spell is queued (castId set but not yet casting)
                    if casting == 0 and channeling == 0 and castId == spellId then
                        return true
                    end
                end
            end
        elseif actionToCheck.item then
            name = actionToCheck.item.name
        end

        return CleveRoids.Hooks.IsCurrentAction(CleveRoids.GetProxyActionSlot(name) or slot)
    end
end

CleveRoids.Hooks.GetActionTexture = GetActionTexture
function GetActionTexture(slot)
    local actions = CleveRoids.GetAction(slot)

    -- Check if this is one of our macros
    if actions and (actions.active or actions.tooltip) then

        -- This block handles the case where all conditionals fail and no explicit
        -- #showtooltip was set. It defaults to the macro's chosen icon.
        if not actions.active and not actions.explicitTooltip and actions.list and table.getn(actions.list) > 0 then
            -- Get the macro's own icon as fallback
            local macroTexture = nil
            local macroName = GetActionText(slot)
            if macroName then
                local macroID = GetMacroIndexByName(macroName)
                if macroID and macroID > 0 then
                    local _, texture = GetMacroInfo(macroID)
                    macroTexture = texture
                end
            end

            -- Prefer tooltip texture if it exists, otherwise use macro icon
            if actions.tooltip and actions.tooltip.texture then
                return actions.tooltip.texture
            elseif macroTexture then
                return macroTexture
            end

            -- Should never reach here, but return macro texture or unknown as last resort
            return macroTexture or CleveRoids.unknownTexture
        end

        -- Prioritize active action, fall back to tooltip
        local a = actions.active or actions.tooltip

        -- Handle numeric slot actions (e.g., /use 13)
        local slotId = tonumber(a.action)
        if slotId and slotId >= 1 and slotId <= 19 then
            local currentTexture = GetInventoryItemTexture("player", slotId)
            if currentTexture then
                return currentTexture
            end

            -- Slot is empty, fall back to macro icon
            local macroName = GetActionText(slot)
            if macroName then
                local macroID = GetMacroIndexByName(macroName)
                if macroID and macroID > 0 then
                    local _, macroTexture = GetMacroInfo(macroID)
                    if macroTexture then
                        return macroTexture
                    end
                end
            end
            return CleveRoids.unknownTexture
        end

        -- *** THIS IS THE FIX ***
        -- If an action is active, return its texture directly.
        -- If no action is active, return the tooltip's texture.
        -- If neither has a texture, fall back to the macro's icon.
        local texture = (actions.active and actions.active.texture) or (actions.tooltip and actions.tooltip.texture)
        if texture then
            return texture
        end

        -- Final fallback: get the macro's icon
        local macroName = GetActionText(slot)
        if macroName then
            local macroID = GetMacroIndexByName(macroName)
            if macroID and macroID > 0 then
                local _, macroTexture = GetMacroInfo(macroID)
                if macroTexture then
                    return macroTexture
                end
            end
        end

        -- Should never reach here
        return CleveRoids.unknownTexture

    end

    -- Not one of our macros, use the original function
    return CleveRoids.Hooks.GetActionTexture(slot)
end

-- TODO: Look into https://github.com/Stanzilla/WoWUIBugs/issues/47 if needed
CleveRoids.Hooks.GetActionCooldown = GetActionCooldown
function GetActionCooldown(slot)
    local actions = CleveRoids.GetAction(slot)
    -- Check for actions.active OR actions.tooltip
    if actions and (actions.active or actions.tooltip) then
        -- Prioritize the active action, but fall back to the tooltip action
        local a = actions.active or actions.tooltip

        local slotId = tonumber(a.action)
        if slotId and slotId >= 1 and slotId <= 19 then
            return GetInventoryItemCooldown("player", slotId)
        end

        if a.spell then
            return GetSpellCooldown(a.spell.spellSlot, a.spell.bookType)
        elseif a.item then
            if a.item.bagID and a.item.slot then
                return GetContainerItemCooldown(a.item.bagID, a.item.slot)
            elseif a.item.inventoryID then
                return GetInventoryItemCooldown("player", a.item.inventoryID)
            end
        end
        return 0, 0, 0
    else
        return CleveRoids.Hooks.GetActionCooldown(slot)
    end
end

CleveRoids.Hooks.GetActionCount = GetActionCount
function GetActionCount(slot)
    local action = CleveRoids.GetAction(slot)
    local count
    -- Use the same priority as GetActionTexture: active first, then tooltip
    local actionToCheck = (action and action.active) or (action and action.tooltip)
    if actionToCheck then

        local slotId = tonumber(actionToCheck.action)
        if slotId and slotId >= 1 and slotId <= 19 then
            return GetInventoryItemCount("player", slotId)
        end

        if actionToCheck.item then
            count = actionToCheck.item.count

        elseif actionToCheck.spell then
            local reagent = actionToCheck.spell.reagent
            if not reagent then
                local ss, bt = actionToCheck.spell.spellSlot, actionToCheck.spell.bookType
                if ss and bt then
                    local _, r = CleveRoids.GetSpellCost(ss, bt)
                    reagent = r
                end
                if (not reagent) and _ReagentBySpell and actionToCheck.spell.name then
                    reagent = _ReagentBySpell[actionToCheck.spell.name]  -- e.g., Vanish → Flash Powder
                end
                actionToCheck.spell.reagent = reagent  -- cache it so we don't re-scan every frame
            end
            if reagent then
                count = CleveRoids.GetReagentCount(reagent)  -- id-first bag scan, falls back to name/tooltip
            end
        end
    end

    return count or CleveRoids.Hooks.GetActionCount(slot)
end

CleveRoids.Hooks.IsConsumableAction = IsConsumableAction
function IsConsumableAction(slot)
    local action = CleveRoids.GetAction(slot)
    -- Use the same priority as GetActionTexture: active first, then tooltip
    local actionToCheck = (action and action.active) or (action and action.tooltip)
    if actionToCheck then

        local slotId = tonumber(actionToCheck.action)
        if slotId and slotId >= 1 and slotId <= 19 then
            local _, count = GetInventoryItemCount("player", slotId)
            if count and count > 0 then return 1 end
        end

        if actionToCheck.item and
            (CleveRoids.countedItemTypes[actionToCheck.item.type]
            or CleveRoids.countedItemTypes[actionToCheck.item.name])
        then
            return 1
        end


        if actionToCheck.spell and actionToCheck.spell.reagent then
            return 1
        end
    end

    return CleveRoids.Hooks.IsConsumableAction(slot)
end

-- Create a hidden tooltip frame to read buff names
if not AuraScanTooltip and not CleveRoids.hasSuperwow then
    CreateFrame("GameTooltip", "AuraScanTooltip")
    AuraScanTooltip:SetOwner(WorldFrame, "ANCHORNONE")
    AuraScanTooltip:AddFontStrings(
        AuraScanTooltip:CreateFontString("$parentTextLeft1", nil, "GameTooltipText"),
        AuraScanTooltip:CreateFontString("$parentTextRight1", nil, "GameTooltipText")
    )
end

-- Robust named tooltip for scanning spells/items
if not CleveRoidsTooltipScan then
  -- Try to create with the standard template first
  local ok, _ = pcall(CreateFrame, "GameTooltip", "CleveRoidsTooltipScan", UIParent, "GameTooltipTemplate")
  if not ok or not CleveRoidsTooltipScan then
    -- Fallback: manual tooltip with plenty of prebuilt lines
    CleveRoidsTooltipScan = CreateFrame("GameTooltip", "CleveRoidsTooltipScan", UIParent)
    local L1 = CleveRoidsTooltipScan:CreateFontString("$parentTextLeft1",  nil, "GameTooltipText")
    local R1 = CleveRoidsTooltipScan:CreateFontString("$parentTextRight1", nil, "GameTooltipText")
    CleveRoidsTooltipScan:AddFontStrings(L1, R1)
    for i = 2, 32 do
      CleveRoidsTooltipScan:CreateFontString("$parentTextLeft"..i,  nil, "GameTooltipText")
      CleveRoidsTooltipScan:CreateFontString("$parentTextRight"..i, nil, "GameTooltipText")
    end
  end
  CleveRoidsTooltipScan:SetOwner(WorldFrame, "ANCHOR_NONE")
end

-- This single dummy frame handles events AND serves as our tooltip scanner.
CleveRoids.Frame = CreateFrame("GameTooltip")

-- Create the extra font strings needed for other functions like GetSpellCost.
CleveRoids.Frame.costFontString = CleveRoids.Frame:CreateFontString()
CleveRoids.Frame.rangeFontString = CleveRoids.Frame:CreateFontString()
CleveRoids.Frame.reagentFontString = CleveRoids.Frame:CreateFontString()
CleveRoids.Frame:AddFontStrings(CleveRoids.Frame:CreateFontString(), CleveRoids.Frame:CreateFontString())
CleveRoids.Frame:AddFontStrings(CleveRoids.Frame.costFontString, CleveRoids.Frame.rangeFontString)
CleveRoids.Frame:AddFontStrings(CleveRoids.Frame:CreateFontString(), CleveRoids.Frame:CreateFontString())
CleveRoids.Frame:AddFontStrings(CleveRoids.Frame.reagentFontString, CleveRoids.Frame:CreateFontString())

CleveRoids.Frame:SetScript("OnUpdate", CleveRoids.OnUpdate)
CleveRoids.Frame:SetScript("OnEvent", function(...)
    CleveRoids.Frame[event](this,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,arg10)
end)

-- == CORE EVENT REGISTRATION ==
CleveRoids.Frame:RegisterEvent("PLAYER_LOGIN")
CleveRoids.Frame:RegisterEvent("ADDON_LOADED")
CleveRoids.Frame:RegisterEvent("UPDATE_MACROS")
CleveRoids.Frame:RegisterEvent("SPELLS_CHANGED")
CleveRoids.Frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
CleveRoids.Frame:RegisterEvent("BAG_UPDATE")
CleveRoids.Frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
CleveRoids.Frame:RegisterEvent("UNIT_PET")

-- == STATE CHANGE EVENT REGISTRATION (for performance) ==
CleveRoids.Frame:RegisterEvent("PLAYER_TARGET_CHANGED")
CleveRoids.Frame:RegisterEvent("PLAYER_FOCUS_CHANGED") -- For focus addons
CleveRoids.Frame:RegisterEvent("PLAYER_ENTER_COMBAT")
CleveRoids.Frame:RegisterEvent("PLAYER_LEAVE_COMBAT")
CleveRoids.Frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
CleveRoids.Frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
CleveRoids.Frame:RegisterEvent("UNIT_AURA")
CleveRoids.Frame:RegisterEvent("UNIT_HEALTH")
CleveRoids.Frame:RegisterEvent("UNIT_POWER")
if CleveRoids.hasSuperwow then
  CleveRoids.Frame:RegisterEvent("UNIT_CASTEVENT")
end
if QueueSpellByName then
    CleveRoids.Frame:RegisterEvent("SPELL_QUEUE_EVENT")
    CleveRoids.Frame:RegisterEvent("SPELL_CAST_EVENT")
end
CleveRoids.Frame:RegisterEvent("START_AUTOREPEAT_SPELL")
CleveRoids.Frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
CleveRoids.Frame:RegisterEvent("SPELLCAST_CHANNEL_START")
CleveRoids.Frame:RegisterEvent("SPELLCAST_CHANNEL_STOP")



-- Order-agnostic SuperMacro hook installer
local function CRM_SM_InstallHook()
    if CleveRoids.SM_RunLineHooked then return end
    if not SuperMacroFrame or type(RunLine) ~= "function" then return end

    local orig_RunLine = RunLine

    -- Fast-path targets for extended/bracket syntax
    local tokenHooks = {
        cast   = CleveRoids.DoCast,
        target = CleveRoids.DoTarget,
        use    = CleveRoids.DoUse,
    }

    RunLine = function(...)
        local text = (arg and arg[1]) or nil

        if CleveRoids.stopmacro then
            CleveRoids.stopmacro = false
            return true
        end

        if type(text) == "string" then
            -- 1) SPECIAL-CASE: /castsequence (no token required)
            local b, e, rest = string.find(text, "^%s*/castsequence%s*(.*)")
            if b then
                if type(CleveRoids.DoCastSequence) == "function" then
                    pcall(CleveRoids.DoCastSequence, rest or "")
                    return true
                end
                local fn = _G.SlashCmdList and _G.SlashCmdList["CASTSEQUENCE"]
                if type(fn) == "function" then
                    pcall(fn, rest or "")
                    return true
                end
                -- fall through to SM if no handler
            else
                -- 2) FAST-PATH: /cast|/use|/target followed by extended token
                for k, fn in pairs(tokenHooks) do
                    if type(fn) == "function" and string.find(text, "^%s*/"..k.."%s+[!%[%{%?~]") then
                        -- IMPORTANT: keep the opening token — grab the entire remainder
                        local _, _, remainder = string.find(text, "^%s*/"..k.."%s+(.*)$")
                        remainder = remainder and string.gsub(remainder, "^%s+", "") or ""
                        pcall(fn, remainder)
                        return true
                    end
                end
            end
        end

        return orig_RunLine(text)
    end

    CleveRoids.SM_RunLineHooked = true
end

function CleveRoids.Frame:UNIT_PET()
    if arg1 == "player" then
        CleveRoids.IndexPetSpells()
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

-- Simplified PLAYER_LOGIN - requirements already checked
function CleveRoids.Frame:PLAYER_LOGIN()
    -- Skip if already disabled
    if CleveRoids.disabled then return end

    _, CleveRoids.playerClass = UnitClass("player")
    _, CleveRoids.playerGuid = UnitExists("player")
    CleveRoids.IndexSpells()
    CleveRoids.IndexPetSpells()
    CleveRoids.initializationTimer = GetTime() + 1.5
    CRM_SM_InstallHook()
end

function CleveRoids.Frame:ADDON_LOADED(addon)
    -- keep your existing init for CRM:
    if addon == "CleveRoidMacros" then
        CleveRoids.InitializeExtensions()
    end
    -- (re)attempt hook when either addon arrives
    if addon == "SuperMacro" or addon == "CleveRoidMacros" then
        CRM_SM_InstallHook()
    end
end

function CleveRoids.Frame:UNIT_CASTEVENT(caster,target,action,spell_id,cast_time)
    if action == "MAINHAND" or action == "OFFHAND" then return end

    -- handle cast spell tracking
    local cast = CleveRoids.spell_tracking[caster]
    if cast_time > 0 and action == "START" or action == "CHANNEL" then
        CleveRoids.spell_tracking[caster] = { spell_id = spell_id, expires = GetTime() + cast_time/1000, type = action }
    elseif cast
        and (
            (cast.spell_id == spell_id and (action == "FAIL" or action == "CAST"))
            or (GetTime() > cast.expires)
        )
    then
        CleveRoids.spell_tracking[caster] = nil
    end

    -- handle cast sequence (SuperWoW)
    if CleveRoids.currentSequence and caster == CleveRoids.playerGuid then
        local active = CleveRoids.GetCurrentSequenceAction(CleveRoids.currentSequence)

        local name, rank = SpellInfo(spell_id)
        local nameRank = (rank and rank ~= "") and (name .. "(" .. rank .. ")") or nil
        local isSeqSpell = active and active.action and (
            active.action == name or
            (nameRank and active.action == nameRank)
        )

        if isSeqSpell then
            local status = CleveRoids.currentSequence.status
            if status == 0 and (action == "START" or action == "CHANNEL") and cast_time > 0 then
                -- cast_time is ms; GetTime() is seconds
                CleveRoids.currentSequence.status  = 1
                CleveRoids.currentSequence.expires = GetTime() + (cast_time / 1000) - 2
            elseif (status == 0 and action == "CAST" and cast_time == 0)
                or (status == 1 and action == "CAST" and CleveRoids.currentSequence.expires) then
                CleveRoids.currentSequence.status     = 2
                CleveRoids.currentSequence.lastUpdate = GetTime()
                CleveRoids.AdvanceSequence(CleveRoids.currentSequence)
                CleveRoids.currentSequence = nil
            elseif action == "INTERRUPTED" or action == "FAILED" then
                CleveRoids.currentSequence.status = 1
            end
        end
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:SPELLCAST_CHANNEL_START()
    CleveRoids.CurrentSpell.type = "channeled"
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:SPELLCAST_CHANNEL_STOP()
    CleveRoids.CurrentSpell.type = ""
    CleveRoids.CurrentSpell.spellName = ""
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:PLAYER_ENTER_COMBAT()
    CleveRoids.CurrentSpell.autoAttack = true
    CleveRoids.CurrentSpell.autoAttackLock = false
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:PLAYER_LEAVE_COMBAT()
    CleveRoids.CurrentSpell.autoAttack = false
    CleveRoids.CurrentSpell.autoAttackLock = false

    -- Reset any sequence with reset=combat that has progressed past the first step
    for _, sequence in pairs(CleveRoids.Sequences) do
        if sequence.index > 1 and sequence.reset and sequence.reset.combat then
            CleveRoids.ResetSequence(sequence)
        end
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:PLAYER_TARGET_CHANGED()
    CleveRoids.CurrentSpell.autoAttack = false
    CleveRoids.CurrentSpell.autoAttackLock = false

    -- Reset any sequence with reset=target that has progressed past the first step
    for _, sequence in pairs(CleveRoids.Sequences) do
        if sequence.index > 1 and sequence.reset and sequence.reset.target then
            CleveRoids.ResetSequence(sequence)
        end
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:UPDATE_MACROS()
    CleveRoids.currentSequence = nil
    -- Explicitly nil tables before re-assignment
    CleveRoids.ParsedMsg = nil;
    CleveRoids.ParsedMsg = {}

    CleveRoids.Macros = nil;
    CleveRoids.Macros = {}

    CleveRoids.Actions = nil;
    CleveRoids.Actions = {}

    CleveRoids.Sequences = nil;
    CleveRoids.Sequences = {}

    CleveRoids.IndexSpells()
    CleveRoids.IndexTalents()
    CleveRoids.IndexPetSpells()
    CleveRoids.IndexActionBars()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:SPELLS_CHANGED()
    CleveRoids.Frame:UPDATE_MACROS()
end

function CleveRoids.Frame:ACTIONBAR_SLOT_CHANGED()
    CleveRoids.ClearAction(arg1)
    CleveRoids.IndexActionSlot(arg1)
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:BAG_UPDATE()
    local now = GetTime()
    -- Only index items if more than 1 second has passed since the last index
    if (now - (CleveRoids.lastItemIndexTime or 0)) > 1.0 then
        CleveRoids.lastItemIndexTime = now
        CleveRoids.IndexItems()

        -- Directly clear all relevant caches and force a UI refresh for all buttons.
        CleveRoids.Actions = {}
        CleveRoids.Macros = {}
        --CleveRoids.ParsedMsg = {}
        CleveRoids.IndexActionBars()
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

function CleveRoids.Frame:UNIT_INVENTORY_CHANGED()
    if arg1 ~= "player" then return end
    
    -- Equipment changes need immediate response, bypass BAG_UPDATE throttle
    local now = GetTime()
    CleveRoids.lastItemIndexTime = now
    CleveRoids.IndexItems()

    -- Directly clear all relevant caches and force a UI refresh for all buttons
    CleveRoids.Actions = {}
    CleveRoids.Macros = {}
    CleveRoids.IndexActionBars()
    
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:START_AUTOREPEAT_SPELL()
    local _, className = UnitClass("player")
    if className == "HUNTER" then
        CleveRoids.CurrentSpell.autoShot = true
    else
        CleveRoids.CurrentSpell.wand = true
    end
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:STOP_AUTOREPEAT_SPELL()
    local _, className = UnitClass("player")
    if className == "HUNTER" then
        CleveRoids.CurrentSpell.autoShot = false
    else
        CleveRoids.CurrentSpell.wand = false
    end
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- Generic event handlers that just queue an update
function CleveRoids.Frame:PLAYER_FOCUS_CHANGED()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
function CleveRoids.Frame:UPDATE_SHAPESHIFT_FORM()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
function CleveRoids.Frame:SPELL_UPDATE_COOLDOWN()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
function CleveRoids.Frame:UNIT_AURA()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
function CleveRoids.Frame:UNIT_HEALTH()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end
function CleveRoids.Frame:UNIT_POWER()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:SPELL_QUEUE_EVENT()
    if event == "SPELL_QUEUE_EVENT" then
        local eventCode = arg1
        local spellId = arg2

        local NORMAL_QUEUED = 2
        local NON_GCD_QUEUED = 4
        local ON_SWING_QUEUED = 0
        local NORMAL_QUEUE_POPPED = 3
        local NON_GCD_QUEUE_POPPED = 5
        local ON_SWING_QUEUE_POPPED = 1

        if eventCode == NORMAL_QUEUED or eventCode == NON_GCD_QUEUED or eventCode == ON_SWING_QUEUED then
            CleveRoids.queuedSpell = {
                spellId = spellId,
                queueType = eventCode,
                queueTime = GetTime()
            }
            if SpellInfo then
                local name = SpellInfo(spellId)
                if name then
                    CleveRoids.queuedSpell.spellName = name
                end
            end
            CleveRoids.QueueActionUpdate()
        elseif eventCode == NORMAL_QUEUE_POPPED or eventCode == NON_GCD_QUEUE_POPPED or eventCode == ON_SWING_QUEUE_POPPED then
            CleveRoids.queuedSpell = nil
            CleveRoids.QueueActionUpdate()
        end
    end
end

function CleveRoids.Frame:SPELL_CAST_EVENT()
    if event == "SPELL_CAST_EVENT" then
        local success = arg1
        local spellId = arg2

        if success == 1 then
            CleveRoids.lastCastSpell = {
                spellId = spellId,
                timestamp = GetTime()
            }
            if SpellInfo then
                local name = SpellInfo(spellId)
                if name then
                    CleveRoids.lastCastSpell.spellName = name
                end
            end
        end
    end
end


CleveRoids.Hooks.SendChatMessage = SendChatMessage
function SendChatMessage(msg, ...)
    -- Filter out #showtooltip lines
    -- pfUI's macrotweak also does this, but our pattern is more specific
    if msg and string.find(msg, "^#showtooltip") then
        return
    end
    
    -- Call the original (or pfUI's hook if it's in the chain)
    CleveRoids.Hooks.SendChatMessage(msg, unpack(arg))
end

CleveRoids.RegisterActionEventHandler = function(fn)
    if type(fn) == "function" then
        table.insert(CleveRoids.actionEventHandlers, fn)
    end
end

CleveRoids.RegisterMouseOverResolver = function(fn)
    if type(fn) == "function" then
        table.insert(CleveRoids.mouseOverResolvers, fn)
    end
end

CleverMacro = true

do
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_LOGIN" then
            -- This ensures we wait until the player is fully in the world and all addons are loaded.
            self:UnregisterEvent("PLAYER_LOGIN")

            -- Ensure both pfUI and its focus module are loaded before attempting to hook.
            -- This also checks that the slash command we want to modify exists.
            if pfUI and pfUI.uf and pfUI.uf.focus and SlashCmdList.PFFOCUS then

                local original_PFFOCUS_Handler = SlashCmdList.PFFOCUS
                SlashCmdList.PFFOCUS = function(msg)
                    -- First, execute the original /focus command from pfUI to set the unit name.
                    original_PFFOCUS_Handler(msg)

                -- Now, if a focus name was set, find the corresponding UnitID.
                if pfUI.uf.focus.unitname then
                    local focusName = pfUI.uf.focus.unitname
                    local found_label, found_id = nil, nil

                    -- This function iterates through all known friendly units to find a
                    -- name match and return its specific UnitID components.
                    local function findUnitID()
                        -- Check party members and their pets
                        for i = 1, GetNumPartyMembers() do
                            if strlower(UnitName("party"..i) or "") == focusName then
                                return "party", i
                            end
                            if UnitExists("partypet"..i) and strlower(UnitName("partypet"..i) or "") == focusName then
                                return "partypet", i
                            end
                        end

                        -- Check raid members and their pets
                        for i = 1, GetNumRaidMembers() do
                            if strlower(UnitName("raid"..i) or "") == focusName then
                                return "raid", i
                            end
                            if UnitExists("raidpet"..i) and strlower(UnitName("raidpet"..i) or "") == focusName then
                                return "raidpet", i
                            end
                        end

                        -- Check player and pet
                        if strlower(UnitName("player") or "") == focusName then return "player", nil end
                        if UnitExists("pet") and strlower(UnitName("pet") or "") == focusName then return "pet", nil end

                            return nil, nil
                        end

                        found_label, found_id = findUnitID()

                        -- Store the found label and ID. CleveRoids' Core.lua will use this
                        -- for a direct, reliable cast without needing to change your target.
                        pfUI.uf.focus.label = found_label
                        pfUI.uf.focus.id = found_id
                    else
                        -- Focus was cleared (e.g., via /clearfocus), so ensure our cached data is cleared too.
                        pfUI.uf.focus.label = nil
                        pfUI.uf.focus.id = nil
                    end
                end
            end
        end
    end)
    f:RegisterEvent("PLAYER_LOGIN")
end

SLASH_CLEVEROID1 = "/cleveroid"
SLASH_CLEVEROID2 = "/cleveroidmacros"
SlashCmdList["CLEVEROID"] = function(msg)
    if type(msg) ~= "string" then
        msg = ""
    end
    local cmd, val, val2
    local s, e, a, b, c = string.find(msg, "^(%S*)%s*(%S*)%s*(%S*)$")
    if a then cmd = a else cmd = "" end
    if b then val = b else val = "" end
    if c then val2 = c else val2 = "" end

    -- No command: show current value and available commands
    if cmd == "" then
        CleveRoids.Print("Current Settings:")
        DEFAULT_CHAT_FRAME:AddMessage("realtime (force fast updates, CPU intensive) = " .. CleveRoidMacros.realtime .. " (Default: 0)")
        DEFAULT_CHAT_FRAME:AddMessage("refresh (updates per second) = " .. CleveRoidMacros.refresh .. " (Default: 5)")
        DEFAULT_CHAT_FRAME:AddMessage("debug (show learning messages) = " .. (CleveRoids.debug and "1" or "0") .. " (Default: 0)")
        DEFAULT_CHAT_FRAME:AddMessage(" ")
        CleveRoids.Print("Available Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid realtime 0 or 1 - Force realtime updates")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid refresh X - Set refresh rate (1-10 updates/sec)")
        if CleveRoids.hasSuperwow then
            DEFAULT_CHAT_FRAME:AddMessage("/cleveroid learn <spellID> <duration> - Manually set spell duration")
            DEFAULT_CHAT_FRAME:AddMessage("/cleveroid forget <spellID|all> - Forget learned duration(s)")
            DEFAULT_CHAT_FRAME:AddMessage("/cleveroid debug [0|1] - Toggle learning debug messages")
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Immunity Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listimmune [school] - List immunity data')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addimmune "<NPC>" <school> [buff] - Add immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeimmune "<NPC>" <school> - Remove immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearimmune [school] - Clear immunity data')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Combo Point Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combotrack - Show combo point tracking info')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid comboclear - Clear combo tracking data')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combolearn - Show learned combo durations (per CP)')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Talent Modifiers:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid talents - Show current talent ranks')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid testtalent <spellID> - Test talent modifier for a spell')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Equipment Modifiers:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid testequip <spellID> - Test equipment modifier for a spell')
        return
    end

    -- realtime
    if cmd == "realtime" then
        local num = tonumber(val)
        if num == 0 or num == 1 then
            CleveRoidMacros.realtime = num
            CleveRoids.Print("realtime set to " .. num)
        else
            CleveRoids.Print("Usage: /cleveroid realtime 0 or 1 - Force realtime updates rather than event based updates (Default: 0. 1 = on, increases CPU load.)")
            CleveRoids.Print("Current realtime = " .. tostring(CleveRoidMacros.realtime))
        end
        return
    end

    -- refresh
    if cmd == "refresh" then
        local num = tonumber(val)
        if num and num >= 1 and num <= 10 then
            CleveRoidMacros.refresh = num
            CleveRoids.Print("refresh set to " .. num .. " times per second")
        else
            CleveRoids.Print("Usage: /cleveroid refresh X - Set refresh rate. (1 to 10 updates per second. Default: 5)")
            CleveRoids.Print("Current refresh = " .. tostring(CleveRoidMacros.refresh) .. " times per second")
        end
        return
    end

    -- learn (manual set duration)
    if cmd == "learn" then
        if not CleveRoids.hasSuperwow then
            CleveRoids.Print("Learning system requires SuperWoW client!")
            return
        end
        local spellID = tonumber(val)
        local duration = tonumber(val2)
        if spellID and duration then
            local _, playerGUID = UnitExists("player")
            CleveRoids_LearnedDurations = CleveRoids_LearnedDurations or {}
            CleveRoids_LearnedDurations[spellID] = CleveRoids_LearnedDurations[spellID] or {}
            CleveRoids_LearnedDurations[spellID][playerGUID] = duration
            local spellName = SpellInfo(spellID) or "Unknown"
            CleveRoids.Print("Set " .. spellName .. " (ID:" .. spellID .. ") duration to " .. duration .. "s")
        else
            CleveRoids.Print("Usage: /cleveroid learn <spellID> <duration> - Manually set spell duration")
            CleveRoids.Print("Example: /cleveroid learn 11597 30")
        end
        return
    end

    -- forget (delete learned duration)
    if cmd == "forget" or cmd == "unlearn" then
        if not CleveRoids.hasSuperwow then
            CleveRoids.Print("Learning system requires SuperWoW client!")
            return
        end
        if val == "all" then
            CleveRoids_LearnedDurations = {}
            CleveRoids.Print("Forgot all learned spell durations")
        else
            local spellID = tonumber(val)
            if spellID and CleveRoids_LearnedDurations and CleveRoids_LearnedDurations[spellID] then
                local spellName = SpellInfo(spellID) or "Unknown"
                CleveRoids_LearnedDurations[spellID] = nil
                CleveRoids.Print("Forgot " .. spellName .. " (ID:" .. spellID .. ") duration")
            elseif spellID then
                CleveRoids.Print("No learned duration for spell ID " .. spellID)
            else
                CleveRoids.Print("Usage: /cleveroid forget <spellID> - Forget learned duration")
                CleveRoids.Print("       /cleveroid forget all - Forget all learned durations")
            end
        end
        return
    end

    -- debug (toggle learning messages)
    if cmd == "debug" then
        local num = tonumber(val)
        if num == 0 or num == 1 then
            CleveRoids.debug = (num == 1)
            CleveRoids.Print("debug set to " .. num)
        else
            CleveRoids.debug = not CleveRoids.debug
            CleveRoids.Print("debug " .. (CleveRoids.debug and "enabled" or "disabled"))
        end
        return
    end

    -- listimmune (list immunity data)
    if cmd == "listimmune" or cmd == "immunelist" then
        CleveRoids.ListImmunities(val ~= "" and val or nil)
        return
    end

    -- clearimmune (clear immunity data)
    if cmd == "clearimmune" then
        CleveRoids.ClearImmunities(val ~= "" and val or nil)
        return
    end

    -- addimmune (manually add immunity)
    if cmd == "addimmune" then
        -- Parse: /cleveroid addimmune <NPC Name> <school> [buff]
        -- Example: /cleveroid addimmune "Golemagg the Incinerator" fire
        -- Example: /cleveroid addimmune Vaelastrasz fire "Burning Adrenaline"
        local npcName, school, buffName = nil, nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, rest = string.find(msg, '^addimmune%s+"([^"]+)"%s*(.*)$')
        if quotedNpc then
            npcName = quotedNpc
            -- Parse school and optional buff from rest
            local _, _, sch, buff = string.find(rest, "^(%S+)%s*(.*)$")
            school = sch
            if buff and buff ~= "" then
                -- Check if buff is quoted
                local _, _, quotedBuff = string.find(buff, '^"([^"]+)"$')
                buffName = quotedBuff or buff
            end
        else
            -- No quoted NPC, use simple parsing
            npcName = val
            school = val2
        end

        CleveRoids.AddImmunity(npcName, school, buffName)
        return
    end

    -- removeimmune (manually remove immunity)
    if cmd == "removeimmune" then
        -- Parse: /cleveroid removeimmune <NPC Name> <school>
        local npcName, school = nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, sch = string.find(msg, '^removeimmune%s+"([^"]+)"%s*(%S*)$')
        if quotedNpc then
            npcName = quotedNpc
            school = sch
        else
            npcName = val
            school = val2
        end

        CleveRoids.RemoveImmunity(npcName, school)
        return
    end

    -- combotrack (show combo point tracking info)
    if cmd == "combotrack" or cmd == "combo" then
        CleveRoids.ShowComboTracking()
        return
    end

    -- comboclear (clear combo tracking data)
    if cmd == "comboclear" then
        CleveRoids.ComboPointTracking = {}
        CleveRoids.ComboPointTracking.byID = {}
        CleveRoids.Print("Combo point tracking data cleared")
        return
    end

    -- combolearn (show learned combo durations)
    if cmd == "combolearn" or cmd == "combodurations" then
        CleveRoids.Print("=== Learned Combo Durations ===")
        if not CleveRoids_ComboDurations or not next(CleveRoids_ComboDurations) then
            CleveRoids.Print("No learned combo durations yet. Cast finishers and let them expire!")
        else
            for spellID, cpData in pairs(CleveRoids_ComboDurations) do
                local spellName = SpellInfo(spellID) or ("Spell " .. spellID)
                CleveRoids.Print(spellName .. " (ID:" .. spellID .. "):")
                for cp = 1, 5 do
                    if cpData[cp] then
                        CleveRoids.Print("  " .. cp .. " CP = " .. cpData[cp] .. "s")
                    end
                end
            end
        end
        return
    end

    -- talents (show current talent ranks)
    if cmd == "talents" or cmd == "talent" then
        CleveRoids.Print("=== Current Talents ===")

        -- Ensure talents are indexed
        if not CleveRoids.Talents or table.getn(CleveRoids.Talents) == 0 then
            if CleveRoids.IndexTalents then
                CleveRoids.IndexTalents()
            end
        end

        local count = 0
        for name, rank in pairs(CleveRoids.Talents) do
            if type(name) == "string" and tonumber(rank) and tonumber(rank) > 0 then
                CleveRoids.Print(name .. ": Rank " .. rank)
                count = count + 1
            end
        end

        if count == 0 then
            CleveRoids.Print("No talents learned yet!")
        else
            CleveRoids.Print("Total: " .. count .. " talents")
        end
        return
    end

    -- testtalent (test talent modifier for a spell)
    if cmd == "testtalent" or cmd == "talenttest" then
        local spellID = tonumber(val)
        if not spellID then
            CleveRoids.Print("Usage: /cleveroid testtalent <spellID>")
            CleveRoids.Print("Example: /cleveroid testtalent 1943  (Rupture Rank 1)")
            return
        end

        local spellName = SpellInfo(spellID) or ("Spell " .. spellID)
        local modifier = CleveRoids.talentModifiers and CleveRoids.talentModifiers[spellID]

        if not modifier then
            CleveRoids.Print(spellName .. " (ID:" .. spellID .. ") has no talent modifier configured")
            return
        end

        local talentRank = CleveRoids.GetTalentRank and CleveRoids.GetTalentRank(modifier.talent) or 0

        CleveRoids.Print("=== Talent Modifier Test ===")
        CleveRoids.Print("Spell: " .. spellName .. " (ID:" .. spellID .. ")")
        CleveRoids.Print("Talent: " .. modifier.talent)
        CleveRoids.Print("Your Rank: " .. talentRank .. "/3")

        if talentRank == 0 then
            CleveRoids.Print("|cffff0000You don't have this talent!|r")
        else
            -- Test with a base duration (use 10s as example)
            local baseDur = 10
            local modDur = modifier.modifier(baseDur, talentRank)
            CleveRoids.Print("Example: 10s base -> " .. modDur .. "s modified (+" .. (modDur - baseDur) .. "s)")
        end
        return
    end

    -- testequip (test equipment modifier for a spell)
    if cmd == "testequip" or cmd == "equiptest" then
        local spellID = tonumber(val)
        if not spellID then
            CleveRoids.Print("Usage: /cleveroid testequip <spellID>")
            CleveRoids.Print("Example: /cleveroid testequip 1079  (Rip Rank 1)")
            return
        end

        local spellName = SpellInfo(spellID) or ("Spell " .. spellID)
        local modifier = CleveRoids.equipmentModifiers and CleveRoids.equipmentModifiers[spellID]

        if not modifier then
            CleveRoids.Print(spellName .. " (ID:" .. spellID .. ") has no equipment modifier configured")
            return
        end

        local itemID = CleveRoids.GetEquippedItemID and CleveRoids.GetEquippedItemID(modifier.slot)
        local itemName = "None"
        if itemID then
            local itemLink = GetInventoryItemLink("player", modifier.slot)
            if itemLink then
                itemName = string.match(itemLink, "%[(.-)%]") or ("Item " .. itemID)
            end
        end

        CleveRoids.Print("=== Equipment Modifier Test ===")
        CleveRoids.Print("Spell: " .. spellName .. " (ID:" .. spellID .. ")")
        CleveRoids.Print("Slot: " .. modifier.slot .. " (Ranged/Relic)")
        CleveRoids.Print("Equipped: " .. itemName .. (itemID and (" [" .. itemID .. "]") or ""))

        if not itemID then
            CleveRoids.Print("|cffff0000No item equipped in this slot!|r")
        else
            -- Test with a base duration (use 10s as example)
            local baseDur = 10
            local modDur = modifier.modifier(baseDur, itemID)
            if modDur ~= baseDur then
                CleveRoids.Print("Example: 10s base -> " .. modDur .. "s modified")
                if modDur < baseDur then
                    CleveRoids.Print("|cffff0000Duration reduced by " .. (baseDur - modDur) .. "s|r")
                else
                    CleveRoids.Print("|cff00ff00Duration increased by " .. (modDur - baseDur) .. "s|r")
                end
            else
                CleveRoids.Print("|cffffaa00This item has no effect on this spell|r")
            end
        end
        return
    end

    -- Unknown command fallback
    CleveRoids.Print("Usage:")
    DEFAULT_CHAT_FRAME:AddMessage("/cleveroid - Show current settings")
    DEFAULT_CHAT_FRAME:AddMessage("/cleveroid realtime 0 or 1 - Force realtime updates (Default: 0. 1 = on, increases CPU load)")
    DEFAULT_CHAT_FRAME:AddMessage("/cleveroid refresh X - Set refresh rate (1 to 10 updates per second. Default: 5)")
    if CleveRoids.hasSuperwow then
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid learn <spellID> <duration> - Manually set spell duration")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid forget <spellID|all> - Forget learned duration(s)")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid debug [0|1] - Toggle learning debug messages")
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Immunity Tracking:|r")
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listimmune [school] - List immunity data')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addimmune "<NPC>" <school> [buff] - Add immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeimmune "<NPC>" <school> - Remove immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearimmune [school] - Clear immunity data')
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Combo Point Tracking:|r")
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combotrack - Show combo point tracking info')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid comboclear - Clear combo tracking data')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combolearn - Show learned combo durations (per CP)')
end

SLASH_CLEAREQUIPQUEUE1 = "/clearequipqueue"
SlashCmdList.CLEAREQUIPQUEUE = function()
    CleveRoids.equipmentQueue = {}
    CleveRoids.Print("Equipment queue cleared")
end

SLASH_EQUIPQUEUESTATUS1 = "/equipqueuestatus"
SlashCmdList.EQUIPQUEUESTATUS = function()
    local count = table.getn(CleveRoids.equipmentQueue)
    CleveRoids.Print("Equipment queue has " .. count .. " pending items")

    for i, entry in ipairs(CleveRoids.equipmentQueue) do
        local itemName = entry.item.name or "Unknown"
        local slotName = entry.slotName or "Unknown"
        local retries = entry.retries or 0
        CleveRoids.Print(i .. ". " .. itemName .. " -> " .. slotName .. " (retries: " .. retries .. ")")
    end
end
