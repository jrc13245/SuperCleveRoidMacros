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
CleveRoids.isActionUpdateQueued = true -- Flag to check if a full action update is needed

function CleveRoids.DisableAddon(reason)
    -- mark state
    CleveRoids.disabled = true

    -- stop frame activity
    if CleveRoids.Frame then
        if CleveRoids.Frame.UnregisterAllEvents then
            CleveRoids.Frame:UnregisterAllEvents()
        end
        if CleveRoids.Frame.SetScript then
            CleveRoids.Frame:SetScript("OnEvent", nil)
            CleveRoids.Frame:SetScript("OnUpdate", nil)
        end
    end

    -- neuter slash command if you have one
    if SlashCmdList and SlashCmdList.CLEVEROIDS then
        SlashCmdList.CLEVEROIDS = function()
            CleveRoids.Print("|cffff0000CleveRoidMacros is disabled|r" ..
                (reason and (": " .. tostring(reason)) or ""))
        end
    end

    -- try to disable for next login (if available in this client)
    local addonName = CleveRoids.addonName or "SuperCleveRoidMacros"
    if type(DisableAddOn) == "function" and addonName then
        -- pcall so old clients without per-character variants don’t explode
        pcall(DisableAddOn, addonName)
        -- If your client supports per-character disabling you could also try:
        -- pcall(DisableAddOn, addonName, UnitName("player"))
    end

    -- final notice
    CleveRoids.Print("|cffff0000Disabled|r" ..
        (reason and (" - " .. tostring(reason)) or ""))
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

    if actions.tooltip and table.getn(actions.list) == 0 then
        if CleveRoids.TestAction(actions.cmd or "", actions.args or "") then

            hasActive = true
            actions.active = actions.tooltip
        end
    else
        for _, action in ipairs(actions.list) do
            -- break on first action that passes tests
            if CleveRoids.TestAction(action.cmd, action.args) then
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

            -- nampower range check (rebuild name(rank) like DoWithConditionals)
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
					local r = IsSpellInRange(castName, unit)
					if r ~= nil then
						actions.active.inRange = r
					end
				end
			end

            actions.active.oom = (UnitMana("player") < actions.active.spell.cost)

            local start, duration = GetSpellCooldown(actions.active.spell.spellSlot, actions.active.spell.bookType)
            local onCooldown = (start > 0 and duration > 0)

            if actions.active.isReactive then
                if not CleveRoids.IsReactiveUsable(actions.active.action) then
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
                for _, arg in ipairs(CleveRoids.splitStringIgnoringQuotes(tt)) do
                    macro.actions.tooltip = CleveRoids.CreateActionInfo(arg)
                    local action = CleveRoids.CreateActionInfo(CleveRoids.GetParsedMsg(arg))
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

-- Casts a pet spell by name
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

-- Target using GUIDs (actually unit tokens) and correct targeting.
function CleveRoids.DoTarget(msg)
    local action, conditionals = CleveRoids.GetParsedMsg(msg)

    if action ~= "" or type(conditionals) ~= "table" or not next(conditionals) then
        CleveRoids.Hooks.TARGET_SlashCmd(msg)
        return true
    end

    -- Validate a *unit token* against parsed conditionals
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

    ----------------------------------------------------------------
    -- FAST-PATH: explicit @unit (e.g. [@mouseover], [@focus], [@party1])
    ----------------------------------------------------------------
    do
        local unitTok = conditionals.target

        -- Resolve @mouseover to an actual unit token that exists (works on pfUI frames)
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

        -- Resolve @focus via pfUI focus emulation if present
        if unitTok == "focus" and pfUI and pfUI.uf and pfUI.uf.focus
           and pfUI.uf.focus.label and pfUI.uf.focus.id then
            local fTok = pfUI.uf.focus.label .. pfUI.uf.focus.id
            if UnitExists(fTok) then unitTok = fTok else unitTok = nil end
        end

        -- If explicit unit resolves and passes conditionals, target it now (works out of range)
        if unitTok and UnitExists(unitTok) and IsGuidValid(unitTok, conditionals) then
            TargetUnit(unitTok)
            return true
        end
    end
    ----------------------------------------------------------------

    -- 1) Keep current target if already valid
    if UnitExists("target") and IsGuidValid("target", conditionals) then
        return true
    end

    -- 2) Build candidates: party1..4 and raid1..40 (not mutually exclusive)
    local candidates = {}

    -- Party
    for i = 1, 4 do
        local u = "party"..i
        if UnitExists(u) then table.insert(candidates, { unitId = u }) end
    end

    -- Raid (all 1..40)
    for i = 1, 40 do
        local u = "raid"..i
        if UnitExists(u) then table.insert(candidates, { unitId = u }) end
    end

    -- Optional: also consider targettarget and mouseover if present
    if UnitExists("targettarget") then table.insert(candidates, { unitId = "targettarget" }) end
    if UnitExists("mouseover") then table.insert(candidates, { unitId = "mouseover" }) end

    -- 3) Find first valid and target it
    for _, c in ipairs(candidates) do
        if IsGuidValid(c.unitId, conditionals) then
            TargetUnit(c.unitId)
            return true
        end
    end

    -- 4) Nothing found; preserve original target
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
    local item = CleveRoids.GetItem(msg)
    if not item or not item.name then return false end

    local invslot = offhand and 17 or 16

    local currentItemLink = GetInventoryItemLink("player", invslot)
    if currentItemLink then
        local currentItemName = GetItemInfo(currentItemLink)
        if currentItemName and currentItemName == item.name then
            return true
        end
    end

    if not item.bagID and not item.inventoryID then
        return false
    end

    if item.bagID then
        CleveRoids.GetNextBagSlotForUse(item, msg)

        if type(CloseStackSplitFrame) == "function" then CloseStackSplitFrame() end
        if CursorHasItem and CursorHasItem() then ClearCursor() end

        PickupContainerItem(item.bagID, item.slot)
    else
        PickupInventoryItem(item.inventoryID)
    end

    EquipCursorItem(invslot)
    ClearCursor()
    CleveRoids.lastItemIndexTime = 0
    return true
end

-- TODO: Refactor all these DoWithConditionals sections
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
        if time > cast.expires then
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
    if actions and actions.active then
        return (1 and actions.active.inRange ~= -1 or nil)
    else
        return CleveRoids.Hooks.ActionHasRange(slot)
    end
end

CleveRoids.Hooks.IsActionInRange = IsActionInRange
function IsActionInRange(slot, unit)
    local actions = CleveRoids.GetAction(slot)
    if actions and actions.active and actions.active.type == "spell" then
        return actions.active.inRange
    else
        return CleveRoids.Hooks.IsActionInRange(slot, unit)
    end
end

CleveRoids.Hooks.OriginalIsUsableAction = IsUsableAction
CleveRoids.Hooks.IsUsableAction = IsUsableAction
function IsUsableAction(slot, unit)
    local actions = CleveRoids.GetAction(slot)
    if actions and actions.active then
        return actions.active.usable, actions.active.oom
    else
        return CleveRoids.Hooks.IsUsableAction(slot, unit)
    end
end

CleveRoids.Hooks.IsCurrentAction = IsCurrentAction
function IsCurrentAction(slot)
    local active = CleveRoids.GetActiveAction(slot)

    if not active then
        return CleveRoids.Hooks.IsCurrentAction(slot)
    else
        local name
        if active.spell then
            local rank = active.spell.rank or active.spell.highest.rank
            name = active.spell.name..(rank and ("("..rank..")"))
        elseif active.item then
            name = active.item.name
        end

        return CleveRoids.Hooks.IsCurrentAction(CleveRoids.GetProxyActionSlot(name) or slot)
    end
end

CleveRoids.Hooks.GetActionTexture = GetActionTexture
function GetActionTexture(slot)
    local actions = CleveRoids.GetAction(slot)

    if actions and (actions.active or actions.tooltip) then
        local proxySlot = (actions.active and actions.active.spell) and CleveRoids.GetProxyActionSlot(actions.active.spell.name)
        if proxySlot and CleveRoids.Hooks.GetActionTexture(proxySlot) ~= actions.active.spell.texture then
            return CleveRoids.Hooks.GetActionTexture(proxySlot)
        else
            return (actions.active and actions.active.texture) or (actions.tooltip and actions.tooltip.texture) or CleveRoids.unknownTexture
        end
    end
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
    if action and action.active then

        local slotId = tonumber(action.active.action)
        if slotId and slotId >= 1 and slotId <= 19 then
            return GetInventoryItemCount("player", slotId)
        end

        if action.active.item then
            count = action.active.item.count

        elseif action.active.spell then
            local reagent = action.active.spell.reagent
            if not reagent then
                local ss, bt = action.active.spell.spellSlot, action.active.spell.bookType
                if ss and bt then
                    local _, r = CleveRoids.GetSpellCost(ss, bt)
                    reagent = r
                end
                if (not reagent) and _ReagentBySpell and action.active.spell.name then
                    reagent = _ReagentBySpell[action.active.spell.name]  -- e.g., Vanish → Flash Powder
                end
                action.active.spell.reagent = reagent  -- cache it so we don’t re-scan every frame
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
    if action and action.active then

        local slotId = tonumber(action.active.action)
        if slotId and slotId >= 1 and slotId <= 19 then
            local _, count = GetInventoryItemCount("player", slotId)
            if count and count > 0 then return 1 end
        end

        if action.active.item and
            (CleveRoids.countedItemTypes[action.active.item.type]
            or CleveRoids.countedItemTypes[action.active.item.name])
        then
            return 1
        end


        if action.active.spell and action.active.spell.reagent then
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

function CleveRoids.Frame:PLAYER_LOGIN()
    _, CleveRoids.playerClass = UnitClass("player")
    _, CleveRoids.playerGuid = UnitExists("player")
    CleveRoids.IndexSpells()
    CleveRoids.IndexPetSpells()
    CleveRoids.initializationTimer = GetTime() + 1.5
    CRM_SM_InstallHook()
    if not CleveRoids.hasSuperwow or not IsSpellInRange then
        if not CleveRoids.hasSuperwow then
            CleveRoids.Print("|cFFFF0000CleveRoidMacros|r requires |cFF00FFFFbalakethelock's SuperWoW|r:")
            CleveRoids.Print("https://github.com/balakethelock/SuperWoW")
        end
        if not IsSpellInRange then
            CleveRoids.Print("|cFFFF0000CleveRoidMacros|r requires |cFF00FFFFpepopo978's Nampower|r:")
            CleveRoids.Print("https://github.com/pepopo978/nampower")
        end
        CleveRoids.DisableAddon("Missing Requirements")
        return
    else
        CleveRoids.Print("|cFF4477FFCleveR|r|cFFFFFFFFoid Macros|r |cFF00FF00Loaded|r - See the README.")
    end
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
        --CleveRoids.Macros = {}
        --CleveRoids.ParsedMsg = {}
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

function CleveRoids.Frame:UNIT_INVENTORY_CHANGED()
    if arg1 ~= "player" then return end
    CleveRoids.Frame:BAG_UPDATE()
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


CleveRoids.Hooks.SendChatMessage = SendChatMessage
function SendChatMessage(msg, ...)
    if msg and string.find(msg, "^#showtooltip") then
        return
    end
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

    -- No command: show current value
    if cmd == "" then
        CleveRoids.Print("Current Settings:")
        DEFAULT_CHAT_FRAME:AddMessage("realtime (force fast updates, CPU intensive) = " .. CleveRoidMacros.realtime .. " (Default: 0)")
        DEFAULT_CHAT_FRAME:AddMessage("refresh (updates per second) = " .. CleveRoidMacros.refresh .. " (Default: 5)")
        DEFAULT_CHAT_FRAME:AddMessage("debug (show learning messages) = " .. (CleveRoids.debug and "1" or "0") .. " (Default: 0)")
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
end
