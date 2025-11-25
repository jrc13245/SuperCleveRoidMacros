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

-- Indexes all pet spells and their action bar slots
function CleveRoids.IndexPetSpells()
    local petSpells = {}

    if not UnitExists("pet") then
        CleveRoids.PetSpells = petSpells
        return
    end

    for i = 1, NUM_PET_ACTION_SLOTS do
        local name, subtext, texture, isToken = GetPetActionInfo(i)

        if name and not isToken then
            -- Store the spell name and its slot
            petSpells[name] = {
                slot = i,
                name = name,
                subtext = subtext,
                texture = texture
            }
        end
    end

    CleveRoids.PetSpells = petSpells
end

-- Gets a pet spell by name
function CleveRoids.GetPetSpell(spellName)
    if not spellName or not CleveRoids.PetSpells then
        return nil
    end

    spellName = CleveRoids.Trim(spellName)
    return CleveRoids.PetSpells[spellName]
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
                        local lowerName = string.lower(name)
                        if lowerName ~= name then
                            items[lowerName] = name
                        end
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
                    local lowerName = string.lower(name)
                    if lowerName ~= name then
                        items[lowerName] = name
                    end
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

-- Local helper for 1.12.1: safely get action button info via tooltip
function CleveRoids.GetActionButtonInfo(slot)
    if not CleveRoidsActionTooltip then
        CreateFrame("GameTooltip", "CleveRoidsActionTooltip", UIParent, "GameTooltipTemplate")
    end

    local tooltip = CleveRoidsActionTooltip
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:SetAction(slot)

    local name, rank
    local text = _G["CleveRoidsActionTooltipTextLeft1"]
    if text then name = text:GetText() end
    local text2 = _G["CleveRoidsActionTooltipTextLeft2"]
    if text2 then
        local maybeRank = text2:GetText()
        -- Rank lines usually start with "Rank"
        if maybeRank and string.find(maybeRank, "Rank") then
            rank = maybeRank
        end
    end

    -- Determine if it's an item or spell based on texture (heuristic)
    local tex = GetActionTexture(slot)
    local actionType = tex and "SPELL" or "ITEM"

    return actionType, tex, name, rank
end

function CleveRoids.IndexActionSlot(slot)
    if not HasAction(slot) then
        CleveRoids.Actions[slot] = nil
        -- When clearing a reactive slot, check if we need to find it elsewhere
        local clearedReactiveName = CleveRoids.reactiveSlots[slot]
        CleveRoids.ClearSlot(CleveRoids.reactiveSlots, slot)
        CleveRoids.ClearSlot(CleveRoids.actionSlots, slot)

        -- If we cleared a reactive spell, rescan to find it in another slot
        if clearedReactiveName then
            for i = 1, 120 do
                if i ~= slot and HasAction(i) then
                    local _, _, scanName = CleveRoids.GetActionButtonInfo(i)
                    if scanName == clearedReactiveName then
                        CleveRoids.reactiveSlots[clearedReactiveName] = i
                        CleveRoids.reactiveSlots[i] = clearedReactiveName
                        break
                    end
                end
            end
        end
    else
        local actionType, _, name, rank = CleveRoids.GetActionButtonInfo(slot)
        if name then
            local reactiveName = CleveRoids.reactiveSpells[name] and name
            local actionSlotName = name..(rank and ("("..rank..")") or "")
            if reactiveName then
                -- Always update the mapping to ensure we track the correct slot
                -- Clear old mapping for this spell name first
                local oldSlot = CleveRoids.reactiveSlots[reactiveName]
                if oldSlot and oldSlot ~= slot then
                    CleveRoids.reactiveSlots[oldSlot] = nil
                end
                CleveRoids.reactiveSlots[reactiveName] = slot
                CleveRoids.reactiveSlots[slot] = reactiveName
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
    if not text or text == "" then return end

    local item = CleveRoids.Items[text] or CleveRoids.Items[tostring(text)]
    if not item then
        local lowerText = string.lower(text)
        local canonicalName = CleveRoids.Items[lowerText]
        if canonicalName and type(canonicalName) == "string" then
            item = CleveRoids.Items[canonicalName]
        end
    end
    
    if item then
        if type(item) == "table" then
            return item
        else
            return CleveRoids.Items[tostring(item)]
        end
    end

    local function makeInv(inventoryID, link)
        if not link then link = GetInventoryItemLink("player", inventoryID) end
        if not link then return end

        local _, _, itemID = string.find(link, "item:(%d+)")
        itemID = itemID and tonumber(itemID) or nil

        local name = itemID and GetItemInfo(itemID) or nil
        local texture = GetInventoryItemTexture("player", inventoryID)
        local count = GetInventoryItemCount("player", inventoryID)

        local it = {
            inventoryID = inventoryID,
            id = itemID,
            name = name,
            texture = texture,
            link = link,
            count = count
        }
        if name then
            CleveRoids.Items[name] = it
            local lowerName = string.lower(name)
            if lowerName ~= name then
                CleveRoids.Items[lowerName] = name
            end
        end
        if itemID then CleveRoids.Items[itemID] = name end
        return it
    end

    local function makeBag(bagID, slot, link)
        if not link and GetContainerItemLink then
            link = GetContainerItemLink(bagID, slot)
        end
        if not link then return end

        local _, _, itemID = string.find(link, "item:(%d+)")
        itemID = itemID and tonumber(itemID) or nil

        local name, _, _, _, _, _, _, _, texture = GetItemInfo(itemID or text)
        local count = 0
        if GetContainerItemInfo then
            local tex, itemCount = GetContainerItemInfo(bagID, slot)
            if itemCount then count = itemCount end
            if not texture then texture = tex end
        end

        local it = {
            bagID = bagID,
            slot = slot,
            id = itemID,
            name = name,
            texture = texture,
            link = link,
            count = count,
            bagSlots = { { bagID, slot } },
            slotsIndex = 1
        }
        if name then
            CleveRoids.Items[name] = it
            local lowerName = string.lower(name)
            if lowerName ~= name then
                CleveRoids.Items[lowerName] = name
            end
        end
        if itemID then CleveRoids.Items[itemID] = name end
        return it
    end

    local qid = tonumber(text)
    local qname = (type(text) == "string") and string.lower(text) or nil

    if qid and qid >= 1 and qid <= 19 then
        local it = makeInv(qid)
        if it then return it end
    end

    local inv = 1
    while inv <= 19 do
        local link = GetInventoryItemLink("player", inv)
        if link then
            local _, _, itemID = string.find(link, "item:(%d+)")
            itemID = itemID and tonumber(itemID) or nil

            if qid and itemID and qid == itemID then
                local it = makeInv(inv, link)
                if it then return it end
            elseif qname and itemID then
                local nm = GetItemInfo(itemID)
                if nm and string.lower(nm) == qname then
                    local it = makeInv(inv, link)
                    if it then return it end
                end
            end
        end
        inv = inv + 1
    end

    local bag = 0
    while bag <= 4 do
        local slots = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        local slot = 1
        while slot <= slots do
            local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
            if link then
                local _, _, itemID = string.find(link, "item:(%d+)")
                itemID = itemID and tonumber(itemID) or nil

                if qid and itemID and qid == itemID then
                    local it = makeBag(bag, slot, link)
                    if it then return it end
                elseif qname and itemID then
                    local nm = GetItemInfo(itemID)
                    if nm and string.lower(nm) == qname then
                        local it = makeBag(bag, slot, link)
                        if it then return it end
                    end
                end
            end
            slot = slot + 1
        end
        bag = bag + 1
    end

    local name, link, _, _, _, _, _, _, texture = GetItemInfo(text)
    if not name then return end
    local fallback = { id = text, name = name, link = link, texture = texture }
    CleveRoids.Items[name] = fallback
    local lowerName = string.lower(name)
    if lowerName ~= name then
        CleveRoids.Items[lowerName] = name
    end
    return fallback
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
