CleveRoids.RegisterActionEventHandler(function(slot, event)
    if not slot or not BActionButton or not BActionBar then return end

    local button = getglobal("BActionButton" .. slot)
    if button then
        -- For slot change events, do a full button update
        if event == "ACTIONBAR_SLOT_CHANGED" then
            BActionButton.Update(button)
        end

        -- COOLDOWN FIX: Always update the cooldown using CleveRoids' active spell
        -- Bongos uses button.cooldown for the cooldown frame
        local cooldownFrame = button.cooldown or getglobal(button:GetName() .. "Cooldown")
        if cooldownFrame then
            local start, duration, enable
            local spellSlot, bookType = CleveRoids.GetActionSpellSlot(slot)

            if spellSlot and bookType then
                start, duration, enable = GetSpellCooldown(spellSlot, bookType)
            else
                local actions = CleveRoids.GetAction(slot)
                local actionToCheck = actions and (actions.active or actions.tooltip)
                if actionToCheck and actionToCheck.item then
                    local item = actionToCheck.item
                    if item.bagID and item.slot then
                        start, duration, enable = GetContainerItemCooldown(item.bagID, item.slot)
                    elseif item.inventoryID then
                        start, duration, enable = GetInventoryItemCooldown("player", item.inventoryID)
                    end
                elseif actionToCheck then
                    local slotId = tonumber(actionToCheck.action)
                    if slotId and slotId >= 1 and slotId <= 19 then
                        start, duration, enable = GetInventoryItemCooldown("player", slotId)
                    end
                end

                if not start then
                    start, duration, enable = GetActionCooldown(slot)
                end
            end

            if start and duration then
                CooldownFrame_SetTimer(cooldownFrame, start, duration, (enable and enable > 0) and enable or 1)
            end
        end
    end
end)
