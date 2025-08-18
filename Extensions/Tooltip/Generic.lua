--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}


-- Indexes all spells the current player and pet knows
function CleveRoids.IndexSpells()
    local spells = {}
    local i = 0
    local book = 1
    local bookType = CleveRoids.bookTypes[book]
    local maxBooks = table.getn(CleveRoids.bookTypes)

    spells[bookType] = {}
    while true do
        i = i + 1

        local spellName, spellRank = GetSpellName(i, bookType)
        if not spellName then
            i = 0
            book = book + 1
            if book > maxBooks then
                break
            end

            bookType = CleveRoids.bookTypes[book]
            spells[bookType] = {}
        else
            local cost, reagent = CleveRoids.GetSpellCost(i, bookType)
            local texture = GetSpellTexture(i, bookType)
            if not spells[bookType][spellName] then
                spells[bookType][spellName] = {
                    spellSlot = i,
                    name = spellName,
                    bookType = bookType,
                    texture = texture,
                    cost = cost,
                    reagent = reagent,
                }
            end
            if spellRank and not spells[bookType][spellName][spellRank] then
                spells[bookType][spellName][spellRank] = {
                    spellSlot = i,
                    name = spellName,
                    rank = spellRank,
                    bookType = bookType,
                    texture = texture,
                    cost = cost,
                    reagent = reagent
                }
                spells[bookType][spellName].highest = spells[bookType][spellName][spellRank]
            end

            if reagent then
                CleveRoids.countedItemTypes[reagent] = true
            end
        end
    end

    CleveRoids.Spells = spells
end

function CleveRoids.IndexTalents()
    local talents = {[1] = true}
    for tab = 1, GetNumTalentTabs()  do
        for i = 1, GetNumTalents(tab) do
            local name, _, _, _, rank = GetTalentInfo(tab, i)
            talents[name] = tonumber(rank)
        end
    end
    CleveRoids.Talents = talents
end


function CleveRoids.IndexItems()
    local items = {}
    for bagID = 0, NUM_BAG_SLOTS do
        for slot = GetContainerNumSlots(bagID), 1, -1 do
            local link = GetContainerItemLink(bagID, slot)
            if link then
                local _, _, itemID = string.find(link, "item:(%d+)")
                local name, link, _, _, itemType, itemSubType, _, _, texture = GetItemInfo(itemID)

                if name then
                    local _, count = GetContainerItemInfo(bagID, slot)
                    if not items[name] then
                        items[name] = {
                            bagID = bagID,
                            slot = slot,
                            id = itemID,
                            name = name,
                            type = itemType,
                            count = count,
                            texture = texture,
                            link = link,
                            bagSlots = {{bagID, slot}},
                            slotsIndex = 1,
                        }
                        items[itemID] = name
                    else
                        items[name].count = (items[name].count or 0) + (count or 0)
                        table.insert(items[name].bagSlots, {bagID, slot})
                    end
                end
            end
        end
    end

    for inventoryID = 0, 19 do
        local link = GetInventoryItemLink("player", inventoryID)
        if link then
            local _, _, itemID = string.find(link, "item:(%d+)")
            local name, link, _, _, itemType, itemSubType, _, _, texture = GetItemInfo(itemID)
            if name then
                local count = GetInventoryItemCount("player", inventoryID)
                if not items[name] then
                    items[name] = {
                        inventoryID = inventoryID,
                        id = itemID,
                        name = name,
                        count = count,
                        texture = texture,
                        link = link,
                    }
                    items[itemID] = name
                else
                    items[name].inventoryID = inventoryID
                    items[name].count = (items[name].count or 0) + (count or 0)
                end
            end
        end
    end

    CleveRoids.lastGetItem = nil
    CleveRoids.Items = items

    -- relink an item action to the item if it wasn't in inventory/bags before
    for slot, actions in CleveRoids.Actions do
        for i, action in actions.list do
            if action.item then
                action.item = CleveRoids.GetItem(action.action)
            end
        end
    end
end

function CleveRoids.ClearSlot(slots, slot)
    if slots[slot] then
        slots[slots[slot]] = nil
    end
    slots[slot] = nil
end

function CleveRoids.IndexActionSlot(slot)
    if not HasAction(slot) then
        CleveRoids.Actions[slot] = nil
        CleveRoids.ClearSlot(CleveRoids.reactiveSlots, slot)
        CleveRoids.ClearSlot(CleveRoids.actionSlots, slot)
    else
        local actionType, _, name, rank = CleveRoids.GetActionButtonInfo(slot)
        if name then
            local reactiveName = CleveRoids.reactiveSpells[name] and name
            local actionSlotName = name..(rank and ("("..rank..")") or "")

            if reactiveName then
                if not CleveRoids.reactiveSlots[reactiveName] then
                    CleveRoids.reactiveSlots[reactiveName] = slot
                    CleveRoids.reactiveSlots[slot] = reactiveName
                end
            elseif not reactiveName then
                CleveRoids.ClearSlot(CleveRoids.reactiveSlots, slot)
            end

            if actionType == "SPELL" or actionType == "ITEM" then
                if not CleveRoids.actionSlots[actionSlotName] then
                    CleveRoids.actionSlots[actionSlotName] = slot
                    CleveRoids.actionSlots[slot] = actionSlotName
                end
            end
        end
    end

    CleveRoids.TestForActiveAction(CleveRoids.GetAction(slot))
    CleveRoids.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
end

function CleveRoids.IndexActionBars()
    for i = 1, 120 do
        CleveRoids.IndexActionSlot(i)
    end
end

function CleveRoids.GetSpell(text)
    text = CleveRoids.Trim(text)
    local rs, _, rank = string.find(text, "[^%s]%((Rank %d+)%)$")
    local name = rank and string.sub(text, 1, rs) or text

    for book, spells in CleveRoids.Spells do
        if spells and spells[name] then
            return spells[name][rank or "highest"]
        end
    end
end

function CleveRoids.GetTalent(text)
    text = CleveRoids.Trim(text)
    return CleveRoids.Talents[text]
end

function CleveRoids.GetItem(text)
    local item = CleveRoids.Items[text] or CleveRoids.Items[tostring(text)]

    if item then
        -- Items are stored as [name]->{item} and [id]->name
        if type(item) == "table" then return item end
        return CleveRoids.Items[tostring(item)]
    else
        local name, link, _, _, itemType, _, _, _, texture = GetItemInfo(text)
        if not name then
            return
        end

        local item = {
            id = text,
            name = name,
            link = link,
            texture = texture,
        }
        CleveRoids.Items[name] = item

        return item
    end
end

function CleveRoids.GetNextBagSlotForUse(item, text)
    if not item then return end

    if CleveRoids.lastGetItem == CleveRoids.GetItem(text) then
        if table.getn(item.bagSlots) > item.slotsIndex then
            item.slotsIndex = item.slotsIndex + 1
            item.bagID, item.slot = unpack(item.bagSlots[item.slotsIndex])
        end
    end

    CleveRoids.lastGetItem = item
    return item
end

local Extension = CleveRoids.RegisterExtension("Generic_show")
Extension.RegisterEvent("SPELLS_CHANGED", "SPELLS_CHANGED")

function Extension.OnLoad()
end

function Extension.SPELLS_CHANGED()
end
