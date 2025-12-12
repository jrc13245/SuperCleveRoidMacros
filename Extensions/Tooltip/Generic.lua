--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny
	License: MIT License
]]
local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}

-- PERFORMANCE: Upvalues for frequently called functions
local GetTime = GetTime
local GetContainerItemLink = GetContainerItemLink
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerNumSlots = GetContainerNumSlots
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemTexture = GetInventoryItemTexture
local GetInventoryItemCount = GetInventoryItemCount
local GetItemInfo = GetItemInfo
local GetSpellName = GetSpellName
local GetSpellTexture = GetSpellTexture
local tonumber = tonumber
local type = type
local pairs = pairs
local string_find = string.find
local string_lower = string.lower
local string_gsub = string.gsub
local table_insert = table.insert
local table_getn = table.getn

-- PERFORMANCE: Extract item name directly from link without GetItemInfo call
-- Link format: |cFFFFFFFF|Hitem:12345:0:0:0|h[Item Name]|h|r
local function GetNameFromLink(link)
    if not link then return nil end
    local _, _, name = string_find(link, "|h%[(.-)%]|h")
    return name
end

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


-- Lightweight equipment-only indexing for combat situations
-- Updates existing cache rather than rebuilding it
function CleveRoids.IndexEquippedItems()
    local items = CleveRoids.Items or {}

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
                    -- Update existing entry with current equipment state
                    items[name].inventoryID = inventoryID
                    items[name].count = count
                end
            end
        else
            -- Slot is now empty - clear inventoryID from any item that was there
            -- This is handled lazily by GetItem() fallback, so we skip expensive iteration
        end
    end

    CleveRoids.lastGetItem = nil
    CleveRoids.Items = items
end

-- PERFORMANCE: Index a single equipment slot instead of all 20
-- Use when we know exactly which slot changed (e.g., from EquipBagItem)
function CleveRoids.IndexEquipSlot(inventoryID)
    if not inventoryID then return end

    local items = CleveRoids.Items or {}
    local link = GetInventoryItemLink("player", inventoryID)

    if link then
        local _, _, itemID = string.find(link, "item:(%d+)")
        local name, itemLink, _, _, itemType, itemSubType, _, _, texture = GetItemInfo(itemID)
        if name then
            local count = GetInventoryItemCount("player", inventoryID)
            if not items[name] then
                items[name] = {
                    inventoryID = inventoryID,
                    id = itemID,
                    name = name,
                    count = count,
                    texture = texture,
                    link = itemLink,
                }
                items[itemID] = name
                local lowerName = string.lower(name)
                if lowerName ~= name then
                    items[lowerName] = name
                end
            else
                items[name].inventoryID = inventoryID
                items[name].count = count
            end
        end
    end

    CleveRoids.lastGetItem = nil
    CleveRoids.Items = items
end


-- PERFORMANCE: Persistent cache for GetItemInfo results (survives between IndexItems calls)
-- This prevents repeated GetItemInfo calls for the same itemID
local _itemInfoCache = {}
local _itemInfoCacheSize = 0
local _ITEM_INFO_CACHE_MAX = 500  -- Limit cache size

local function GetCachedItemInfo(itemID)
    local cached = _itemInfoCache[itemID]
    if cached then
        return cached.name, cached.link, cached.quality, cached.level, cached.type, cached.subType, cached.stackCount, cached.equipLoc, cached.texture
    end

    local name, link, quality, level, itemType, subType, stackCount, equipLoc, texture = GetItemInfo(itemID)
    if name then
        -- Cache the result
        if _itemInfoCacheSize < _ITEM_INFO_CACHE_MAX then
            _itemInfoCache[itemID] = {
                name = name, link = link, quality = quality, level = level,
                type = itemType, subType = subType, stackCount = stackCount,
                equipLoc = equipLoc, texture = texture
            }
            _itemInfoCacheSize = _itemInfoCacheSize + 1
        end
    end
    return name, link, quality, level, itemType, subType, stackCount, equipLoc, texture
end

function CleveRoids.IndexItems()
    local items = {}
    local NUM_BAG_SLOTS = NUM_BAG_SLOTS  -- Upvalue for bag constant

    -- PERFORMANCE: Local function references
    local GetContainerNumSlots = GetContainerNumSlots
    local GetContainerItemLink = GetContainerItemLink
    local GetContainerItemInfo = GetContainerItemInfo
    local GetInventoryItemLink = GetInventoryItemLink
    local GetInventoryItemCount = GetInventoryItemCount

    -- Scan bags (reverse order to prefer first stack)
    for bagID = 0, NUM_BAG_SLOTS do
        local numSlots = GetContainerNumSlots(bagID)
        for slot = numSlots, 1, -1 do
            local link = GetContainerItemLink(bagID, slot)
            if link then
                local _, _, itemID = string_find(link, "item:(%d+)")

                -- PERFORMANCE: Try to extract name from link first to check for duplicates
                local _, _, linkName = string_find(link, "%[(.+)%]")
                local existing = linkName and items[linkName]

                if existing then
                    -- Item already seen - just update count and add bag slot (skip GetItemInfo)
                    local _, count = GetContainerItemInfo(bagID, slot)
                    existing.count = (existing.count or 0) + (count or 0)
                    table_insert(existing.bagSlots, {bagID, slot})
                else
                    -- New item - need full info
                    local name, itemLink, _, _, itemType, itemSubType, _, _, texture = GetCachedItemInfo(itemID)

                    if name then
                        local _, count = GetContainerItemInfo(bagID, slot)
                        items[name] = {
                            bagID = bagID,
                            slot = slot,
                            id = itemID,
                            name = name,
                            type = itemType,
                            count = count,
                            texture = texture,
                            link = itemLink,
                            bagSlots = {{bagID, slot}},
                            slotsIndex = 1,
                        }
                        items[itemID] = name
                        local lowerName = string_lower(name)
                        if lowerName ~= name then
                            items[lowerName] = name
                        end
                    end
                end
            end
        end
    end

    -- Scan equipped items
    for inventoryID = 0, 19 do
        local link = GetInventoryItemLink("player", inventoryID)
        if link then
            local _, _, itemID = string_find(link, "item:(%d+)")

            -- PERFORMANCE: Try to extract name from link first
            local _, _, linkName = string_find(link, "%[(.+)%]")
            local existing = linkName and items[linkName]

            if existing then
                -- Item in bags AND equipped - update existing entry
                existing.inventoryID = inventoryID
                local count = GetInventoryItemCount("player", inventoryID)
                existing.count = (existing.count or 0) + (count or 0)
            else
                -- New equipped-only item
                local name, itemLink, _, _, itemType, itemSubType, _, _, texture = GetCachedItemInfo(itemID)
                if name then
                    local count = GetInventoryItemCount("player", inventoryID)
                    items[name] = {
                        inventoryID = inventoryID,
                        id = itemID,
                        name = name,
                        count = count,
                        texture = texture,
                        link = itemLink,
                    }
                    items[itemID] = name
                    local lowerName = string_lower(name)
                    if lowerName ~= name then
                        items[lowerName] = name
                    end
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

-- PERFORMANCE: Helper functions defined once (not inline per-call)
local function makeInventoryItem(inventoryID, link, Items)
    if not link then link = GetInventoryItemLink("player", inventoryID) end
    if not link then return end

    local _, _, itemID = string_find(link, "item:(%d+)")
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
        Items[name] = it
        local lowerName = string_lower(name)
        if lowerName ~= name then
            Items[lowerName] = name
        end
    end
    if itemID then Items[itemID] = name end
    return it
end

local function makeBagItem(bagID, slot, link, Items)
    if not link then
        link = GetContainerItemLink(bagID, slot)
    end
    if not link then return end

    local _, _, itemID = string_find(link, "item:(%d+)")
    itemID = itemID and tonumber(itemID) or nil

    local name, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
    local count = 0
    local tex, itemCount = GetContainerItemInfo(bagID, slot)
    if itemCount then count = itemCount end
    if not texture then texture = tex end

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
        Items[name] = it
        local lowerName = string_lower(name)
        if lowerName ~= name then
            Items[lowerName] = name
        end
    end
    if itemID then Items[itemID] = name end
    return it
end

function CleveRoids.GetItem(text)
    if not text or text == "" then return end

    local Items = CleveRoids.Items
    local item = Items[text] or Items[tostring(text)]
    if not item then
        local lowerText = string_lower(text)
        local canonicalName = Items[lowerText]
        if canonicalName and type(canonicalName) == "string" then
            item = Items[canonicalName]
        end
    end

    if item then
        if type(item) == "table" then
            return item
        else
            return Items[tostring(item)]
        end
    end

    local qid = tonumber(text)
    local qname = (type(text) == "string") and string_lower(text) or nil

    -- Direct inventory slot lookup by ID
    if qid and qid >= 1 and qid <= 19 then
        local it = makeInventoryItem(qid, nil, Items)
        if it then return it end
    end

    -- Scan equipped items
    for inv = 1, 19 do
        local link = GetInventoryItemLink("player", inv)
        if link then
            local _, _, itemID = string_find(link, "item:(%d+)")
            itemID = itemID and tonumber(itemID) or nil

            if qid and itemID and qid == itemID then
                return makeInventoryItem(inv, link, Items)
            elseif qname then
                -- PERFORMANCE: Extract name from link directly instead of GetItemInfo
                local nm = GetNameFromLink(link)
                if nm and string_lower(nm) == qname then
                    return makeInventoryItem(inv, link, Items)
                end
            end
        end
    end

    -- Scan bags
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, itemID = string_find(link, "item:(%d+)")
                itemID = itemID and tonumber(itemID) or nil

                if qid and itemID and qid == itemID then
                    return makeBagItem(bag, slot, link, Items)
                elseif qname then
                    -- PERFORMANCE: Extract name from link directly instead of GetItemInfo
                    local nm = GetNameFromLink(link)
                    if nm and string_lower(nm) == qname then
                        return makeBagItem(bag, slot, link, Items)
                    end
                end
            end
        end
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

    -- PERFORMANCE: Compare item directly instead of calling GetItem(text) again
    if CleveRoids.lastGetItem == item then
        if item.bagSlots and table.getn(item.bagSlots) > item.slotsIndex then
            item.slotsIndex = item.slotsIndex + 1
            item.bagID, item.slot = unpack(item.bagSlots[item.slotsIndex])
        end
    end

    CleveRoids.lastGetItem = item
    return item
end

--------------------------------------------------------------------------------
-- FAST ITEM LOOKUP (avoids full bag scan)
--------------------------------------------------------------------------------

-- PERFORMANCE: Fast item lookup by name only - no full scan fallback
-- Returns item table or nil. Does NOT trigger IndexItems().
-- Use this for equipment swapping where we know the exact item name.
function CleveRoids.GetItemFast(text)
    if not text or text == "" then return nil end

    local Items = CleveRoids.Items
    if not Items then return nil end

    -- Direct cache lookup
    local item = Items[text]
    if item and type(item) == "table" then
        return item
    end

    -- Try lowercase
    local lowerText = string_lower(text)
    local canonicalName = Items[lowerText]
    if canonicalName and type(canonicalName) == "string" then
        item = Items[canonicalName]
        if item and type(item) == "table" then
            return item
        end
    end

    -- Try as item ID
    local itemId = tonumber(text)
    if itemId then
        local name = Items[itemId]
        if name and type(name) == "string" then
            item = Items[name]
            if item and type(item) == "table" then
                return item
            end
        end
    end

    return nil
end

-- PERFORMANCE: Quick scan for a single item by name (doesn't update full cache)
-- Only scans until item is found, then stops.
-- Optimized: extracts name from link directly instead of calling GetItemInfo.
-- Uses cache with VALIDATION - checks if item is actually at cached location before trusting it.
function CleveRoids.FindItemQuick(text)
    if not text or text == "" then return nil end

    local Items = CleveRoids.Items or {}
    local qid = tonumber(text)
    -- Only compute lowercase name if we're NOT searching by ID
    local qname = (not qid) and string_lower(text) or nil

    -- Try cache first, but VALIDATE the cached location is still correct
    local cached = CleveRoids.GetItemFast(text)
    if cached then
        -- Validate: check if item is actually at the cached location
        if cached.inventoryID then
            local link = GetInventoryItemLink("player", cached.inventoryID)
            if link then
                local nm = GetNameFromLink(link)
                if nm and qname and string_lower(nm) == qname then
                    cached._validated = true
                    return cached  -- Cache is valid
                elseif qid then
                    local _, _, itemID = string_find(link, "item:(%d+)")
                    if itemID and tonumber(itemID) == qid then
                        cached._validated = true
                        return cached  -- Cache is valid
                    end
                end
            end
            -- Cache is stale - item not at cached equipped slot, invalidate
            if cached.name then
                Items[cached.name] = nil
                Items[string_lower(cached.name)] = nil
            end
        elseif cached.bagID and cached.slot then
            local link = GetContainerItemLink(cached.bagID, cached.slot)
            if link then
                local nm = GetNameFromLink(link)
                if nm and qname and string_lower(nm) == qname then
                    cached._validated = true
                    return cached  -- Cache is valid
                elseif qid then
                    local _, _, itemID = string_find(link, "item:(%d+)")
                    if itemID and tonumber(itemID) == qid then
                        cached._validated = true
                        return cached  -- Cache is valid
                    end
                end
            end
            -- Cache is stale - item not at cached bag slot, invalidate
            if cached.name then
                Items[cached.name] = nil
                Items[string_lower(cached.name)] = nil
            end
        end
    end

    -- Cache miss or stale - do a fresh scan
    -- Quick scan equipped items first (only 19 slots)
    for inv = 1, 19 do
        local link = GetInventoryItemLink("player", inv)
        if link then
            local _, _, itemID = string_find(link, "item:(%d+)")
            if itemID then
                itemID = tonumber(itemID)
                -- ID match: fast path
                if qid and qid == itemID then
                    return makeInventoryItem(inv, link, Items)
                end
                -- Name match: extract name from link (faster than GetItemInfo)
                if qname then
                    local nm = GetNameFromLink(link)
                    if nm and string_lower(nm) == qname then
                        return makeInventoryItem(inv, link, Items)
                    end
                end
            end
        end
    end

    -- Quick scan bags - stop as soon as found
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, itemID = string_find(link, "item:(%d+)")
                if itemID then
                    itemID = tonumber(itemID)
                    -- ID match: fast path
                    if qid and qid == itemID then
                        return makeBagItem(bag, slot, link, Items)
                    end
                    -- Name match: extract name from link (faster than GetItemInfo)
                    if qname then
                        local nm = GetNameFromLink(link)
                        if nm and string_lower(nm) == qname then
                            return makeBagItem(bag, slot, link, Items)
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- PERFORMANCE: Check if item is already equipped in slot (fast path)
-- Returns true if the item (by name or ID) is already in the specified slot
function CleveRoids.IsItemEquipped(text, inventoryId)
    if not text or not inventoryId then return false end

    local link = GetInventoryItemLink("player", inventoryId)
    if not link then return false end

    local _, _, currentID = string_find(link, "item:(%d+)")
    if not currentID then return false end

    -- Check by ID (fast path)
    local textId = tonumber(text)
    if textId and textId == tonumber(currentID) then
        return true
    end

    -- Check by name - extract from link instead of GetItemInfo for performance
    local currentName = GetNameFromLink(link)
    if currentName then
        local textLower = string_lower(text)
        if string_lower(currentName) == textLower then
            return true
        end
    end

    return false
end

local Extension = CleveRoids.RegisterExtension("Generic_show")
Extension.RegisterEvent("SPELLS_CHANGED", "SPELLS_CHANGED")

function Extension.OnLoad()
end

function Extension.SPELLS_CHANGED()
end
