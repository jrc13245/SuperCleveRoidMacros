--[[
	Author: Dennis Werner Garske (DWG) / brian / Mewtiny / brian / Mewtiny
	License: MIT License
]]

-- DEBUG: Error catcher for "attempt to index a function value"
-- Remove this block once the error is identified
local _G = _G or getfenv(0)
local originalErrorHandler = geterrorhandler and geterrorhandler()
if seterrorhandler then
    seterrorhandler(function(msg)
        if msg and string.find(msg, "index a function value") then
            local trace = debugstack and debugstack(2, 20, 0) or "no stack available"
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[SCRM DEBUG] index function error:|r " .. tostring(msg))
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Stack:|r " .. tostring(trace))
        end
        if originalErrorHandler then
            return originalErrorHandler(msg)
        end
    end)
end

-- Setup to wrap our stuff in a table so we don't pollute the global environment
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids
CleveRoids.lastItemIndexTime = 0
CleveRoids.initializationTimer = nil
CleveRoids.isActionUpdateQueued = true
CleveRoids.lastEquipTime = CleveRoids.lastEquipTime or {}
CleveRoids.lastWeaponSwapTime = 0
CleveRoids.equipInProgress = false

-- PERFORMANCE: Event throttling to reduce spam from high-frequency events
CleveRoids.lastUnitAuraUpdate = 0
CleveRoids.lastUnitHealthUpdate = 0
CleveRoids.lastUnitPowerUpdate = 0
CleveRoids.EVENT_THROTTLE = 0.1  -- 100ms throttle for high-frequency events

-- PERFORMANCE: Spell ID cache to avoid repeated GetSpellIdForName lookups
CleveRoids.spellIdCache = {}

-- PERFORMANCE: Spell name construction cache
CleveRoids.spellNameCache = {}

-- PERFORMANCE: Upvalues for frequently called global functions (avoid global lookups)
local GetTime = GetTime
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local GetContainerItemLink = GetContainerItemLink
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerNumSlots = GetContainerNumSlots
local GetInventoryItemLink = GetInventoryItemLink
local GetItemInfo = GetItemInfo
local PickupContainerItem = PickupContainerItem
local PickupInventoryItem = PickupInventoryItem
local EquipCursorItem = EquipCursorItem
local CursorHasItem = CursorHasItem
local ClearCursor = ClearCursor
local TargetUnit = TargetUnit
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local tostring = tostring
local string_find = string.find
local string_lower = string.lower
local string_gsub = string.gsub
local table_insert = table.insert
local table_getn = table.getn

-- PERFORMANCE: Module-level constant for boolean conditionals (avoid per-call table creation)
local BOOLEAN_CONDITIONALS = {
    combat = true,
    nocombat = true,
    stealth = true,
    nostealth = true,
    channeled = true,
    nochanneled = true,
    checkchanneled = true,
    checkcasting = true,
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
    group = true,
    nogroup = true,
    moving = true,
    nomoving = true,
}

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
            CleveRoids.Print("|cFFFF0000SuperCleveRoidMacros|r requires |cFF00FFFFAvitasia's Nampower|r:")
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

-- Check if slot 18 is a relic (no GCD) for current player class
local function IsRelicSlot(slot)
    if slot ~= 18 then return false end
    local playerClass = CleveRoids.playerClass
    return playerClass == "PALADIN" or playerClass == "DRUID" or playerClass == "SHAMAN"
end

-- PERFORMANCE: Cache GetTime() result for cooldown checks within same frame
-- Slot 18 (relic/idol/libram/totem) has no GCD for Paladin/Druid/Shaman
local function IsSlotOnCooldown(slot, now)
    -- Relics have no GCD - skip cooldown check entirely
    if IsRelicSlot(slot) then
        return false
    end

    now = now or GetTime()
    local slotTime = CleveRoids.lastEquipTime[slot] or 0
    local globalTime = CleveRoids.lastGlobalEquipTime or 0

    return (now - slotTime) < CleveRoids.EQUIP_COOLDOWN or
           (now - globalTime) < CleveRoids.EQUIP_GLOBAL_COOLDOWN
end

-- PERFORMANCE: Consolidated cursor handling, fewer CursorHasItem() calls
local function PerformEquipSwap(item, inventoryId, useQueueScript)
    if not item or not inventoryId then return false end

    -- Check if in combat and swapping weapons
    -- Slot 18 (ranged) is only a weapon for Hunter/Warrior/Rogue/Mage/Warlock/Priest
    -- For Druid/Paladin/Shaman, slot 18 is idol/libram/totem - can swap freely
    local isWeapon = (inventoryId == 16 or inventoryId == 17)
    if inventoryId == 18 then
        -- Use cached playerClass for performance
        local playerClass = CleveRoids.playerClass
        -- Only treat slot 18 as weapon for classes that use ranged weapons
        isWeapon = (playerClass == "HUNTER" or playerClass == "WARRIOR" or
                    playerClass == "ROGUE" or playerClass == "MAGE" or
                    playerClass == "WARLOCK" or playerClass == "PRIEST")
    end

    if isWeapon and UnitAffectingCombat("player") then
        -- Don't swap while casting
        if CleveRoids.CurrentSpell.type ~= "" then
            return false
        end

        -- Check for on-swing spells if available (Nampower)
        if GetCurrentCastingInfo then
            local castId, _, _, casting, channeling, onswing = GetCurrentCastingInfo()

            if onswing == 1 then
                return false
            end

            -- If casting/channeling and QueueScript available, queue the swap for after cast
            if (casting == 1 or channeling == 1) and QueueScript and useQueueScript and item.name then
                local script = string.format('EquipItemByName("%s",%d)', item.name, inventoryId)
                QueueScript(script, 3)  -- Priority 3 = after queued spells
                return true
            end
        end
    end

    -- PERFORMANCE: Try EquipItemByName first if available (handles everything internally)
    if item.name and EquipItemByName then
        local ok = pcall(EquipItemByName, item.name, inventoryId)
        if ok then return true end
    end

    -- Fallback: Manual pickup and equip
    if item.bagID and item.slot then
        PickupContainerItem(item.bagID, item.slot)
    elseif item.inventoryID then
        PickupInventoryItem(item.inventoryID)
    else
        return false
    end

    -- Single cursor check after pickup attempt
    if not CursorHasItem() then
        return false
    end

    EquipCursorItem(inventoryId)
    local success = not CursorHasItem()
    ClearCursor()
    return success
end

-- PERFORMANCE: Get a queue entry from pool or create new
local function GetQueueEntry()
    local pool = CleveRoids.queueEntryPool
    local n = pool and table_getn(pool) or 0
    if n > 0 then
        local entry = pool[n]
        pool[n] = nil
        return entry
    end
    return {}
end

-- PERFORMANCE: Return entry to pool for reuse
local function ReleaseQueueEntry(entry)
    if not entry then return end
    -- Clear the entry (set to nil, don't create new table)
    entry.item = nil
    entry.slotName = nil
    entry.inventoryId = nil
    entry.queueTime = nil
    entry.retries = nil
    entry.maxRetries = nil
    entry.itemId = nil
    -- Add to pool (max 10 pooled entries)
    local pool = CleveRoids.queueEntryPool
    if table_getn(pool) < 10 then
        table_insert(pool, entry)
    end
end

-- PERFORMANCE: Swap-and-pop removal (O(1) instead of O(n))
local function RemoveQueueEntry(i)
    local queue = CleveRoids.equipmentQueue
    local n = CleveRoids.equipmentQueueLen
    local entry = queue[i]

    if i < n then
        queue[i] = queue[n]
    end
    queue[n] = nil
    CleveRoids.equipmentQueueLen = n - 1

    ReleaseQueueEntry(entry)
end

-- Queue equipment swap function
function CleveRoids.QueueEquipItem(item, slotName)
    if not item or not slotName then return false end

    local inventoryId = GetInventoryIdFromSlot(slotName)
    if not inventoryId then return false end

    local now = GetTime()
    local itemId = item.id

    -- PERFORMANCE: Check for duplicate queue entries before adding
    local queue = CleveRoids.equipmentQueue
    local queueLen = CleveRoids.equipmentQueueLen
    for i = 1, queueLen do
        local q = queue[i]
        if q and q.inventoryId == inventoryId and q.itemId == itemId then
            return false  -- Already queued
        end
    end

    -- Try immediate equip if not on cooldown (use QueueScript for smoother mid-cast swaps)
    if not IsSlotOnCooldown(inventoryId, now) then
        local success = PerformEquipSwap(item, inventoryId, true)

        if success then
            -- Don't set cooldowns for relic slots (no GCD)
            if not IsRelicSlot(inventoryId) then
                CleveRoids.lastEquipTime[inventoryId] = now
                CleveRoids.lastGlobalEquipTime = now
            end
            return true
        end
    end

    -- Queue for later using pooled entry
    local entry = GetQueueEntry()
    entry.item = item
    entry.slotName = slotName
    entry.inventoryId = inventoryId
    entry.queueTime = now
    entry.retries = 0
    entry.maxRetries = 5
    entry.itemId = itemId

    CleveRoids.equipmentQueueLen = queueLen + 1
    queue[CleveRoids.equipmentQueueLen] = entry

    -- PERFORMANCE: Start the queue processing frame
    if CleveRoids.equipQueueFrame then
        CleveRoids.equipQueueFrame:Show()
    end

    return false
end

-- PERFORMANCE: Process equipment queue (called from self-disabling frame)
function CleveRoids.ProcessEquipmentQueue()
    local queueLen = CleveRoids.equipmentQueueLen
    if queueLen == 0 then return end

    local now = GetTime()
    local queue = CleveRoids.equipmentQueue
    local i = 1

    while i <= CleveRoids.equipmentQueueLen do
        local queued = queue[i]

        -- Remove expired entries first (>10 seconds old)
        if (now - queued.queueTime) > 10 then
            RemoveQueueEntry(i)
            -- Don't increment i, we swapped in the last element
        elseif not IsSlotOnCooldown(queued.inventoryId, now) then
            -- Try to equip (use QueueScript for smoother mid-cast swaps)
            local success = PerformEquipSwap(queued.item, queued.inventoryId, true)

            if success then
                -- Don't set cooldowns for relic slots (no GCD)
                if not IsRelicSlot(queued.inventoryId) then
                    CleveRoids.lastEquipTime[queued.inventoryId] = now
                    CleveRoids.lastGlobalEquipTime = now
                end
                RemoveQueueEntry(i)
            else
                queued.retries = queued.retries + 1
                if queued.retries >= queued.maxRetries then
                    RemoveQueueEntry(i)
                else
                    i = i + 1
                end
            end
        else
            i = i + 1
        end
    end
end

-- PERFORMANCE: Self-disabling frame for queue processing with throttling
-- Only processes every EQUIP_QUEUE_INTERVAL instead of every frame
CleveRoids.EQUIP_QUEUE_INTERVAL = 0.1  -- 100ms between queue checks (was 50ms)
CleveRoids.equipQueueLastUpdate = 0
CleveRoids.equipQueueFrame = CreateFrame("Frame")
CleveRoids.equipQueueFrame:Hide()

-- PERFORMANCE: Upvalue for faster access in OnUpdate
local equipQueueFrame = CleveRoids.equipQueueFrame
local equipQueueInterval = CleveRoids.EQUIP_QUEUE_INTERVAL

equipQueueFrame:SetScript("OnUpdate", function()
    -- Prevent operations during shutdown (crash prevention)
    if CleveRoids.isShuttingDown then return end

    -- PERFORMANCE: Use arg1 (elapsed time) if available, otherwise GetTime()
    local elapsed = arg1
    if elapsed then
        CleveRoids.equipQueueLastUpdate = (CleveRoids.equipQueueLastUpdate or 0) + elapsed
        if CleveRoids.equipQueueLastUpdate < equipQueueInterval then
            return  -- Throttle: skip this frame
        end
        CleveRoids.equipQueueLastUpdate = 0
    else
        local now = GetTime()
        if (now - (CleveRoids.equipQueueLastUpdate or 0)) < equipQueueInterval then
            return
        end
        CleveRoids.equipQueueLastUpdate = now
    end

    CleveRoids.ProcessEquipmentQueue()
    if CleveRoids.equipmentQueueLen == 0 then
        this:Hide()
    end
end)

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

        SlashCmdList.CLEVEROID = disabledMsg
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

    if type(CleveRoidMacros.macrocheck) ~= "number" then
        CleveRoidMacros.macrocheck = 1  -- enabled by default
    end
end)

-- Queues a full update of all action bars.
-- This is called by game event handlers to avoid running heavy logic inside the event itself.
function CleveRoids.QueueActionUpdate()
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.isActionUpdateQueued = true
        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffff00ff[QueueActionUpdate]|r Queued, isActionUpdateQueued = %s",
                    tostring(CleveRoids.isActionUpdateQueued))
            )
        end
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

-- Expose for use in Generic.lua (IndexSpells fallback)
CleveRoids.ReagentBySpell = _ReagentBySpell

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
-- PERFORMANCE: Uses CleveRoids.Items cache for O(1) lookup when available
function CleveRoids.GetReagentCount(reagentName)
  if not reagentName or reagentName == "" then return 0 end

  -- Fast path: check cache first
  local Items = CleveRoids.Items
  if Items then
    local wantId = _ReagentIdByName[reagentName]

    -- Try by ID first if we have a mapping
    if wantId then
      local itemName = Items[wantId]
      if itemName then
        local itemData = Items[itemName]
        if itemData and itemData.count and not itemData.inventoryID then
          -- Item is in bags (not equipped), return cached count
          return itemData.count
        end
      end
    end

    -- Try by name
    local itemData = Items[reagentName]
    if type(itemData) == "string" then
      itemData = Items[itemData]  -- Resolve indirection
    end
    if itemData and type(itemData) == "table" and itemData.count and not itemData.inventoryID then
      return itemData.count
    end

    -- Try lowercase
    local lowerName = string.lower(reagentName)
    local resolved = Items[lowerName]
    if type(resolved) == "string" then
      itemData = Items[resolved]
    elseif type(resolved) == "table" then
      itemData = resolved
    end
    if itemData and type(itemData) == "table" and itemData.count and not itemData.inventoryID then
      return itemData.count
    end
  end

  -- Slow path fallback: full bag scan (only when cache miss)
  local wantId = _ReagentIdByName[reagentName]
  local total = 0

  for bag = 0, 4 do
    local slots = GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local _, count = GetContainerItemInfo(bag, slot)
      count = count or 0
      local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
      if link then
        local _, _, idstr = string.find(link, "item:(%d+)")
        local id = idstr and tonumber(idstr) or nil
        if (wantId and id == wantId) or (not wantId and string.find(link, "%["..reagentName.."%]")) then
          total = total + count
        end
      else
        -- Fallback: scan bag slot tooltip for the name (expensive, only when no link)
        local tip = CRM_GetBagScanTip()
        tip:ClearLines()
        tip:SetBagItem(bag, slot)
        local left1 = _G[tip:GetName().."TextLeft1"]
        local name = left1 and left1:GetText()
        if name and name == reagentName then
          total = total + count
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
        name = string.gsub(name, "%s*%(%s*Rank%s+%d+%s*%)%s*$", "")  -- strip "(Rank X)" only
        reagent = _ReagentBySpell[name]
    end
  end

  return (cost and tonumber(cost) or 0), (reagent and tostring(reagent) or nil)
end

function CleveRoids.GetProxyActionSlot(slot)
    if not slot then return end
    return CleveRoids.actionSlots[slot] or CleveRoids.actionSlots[slot.."()"]
end

-- Resolves nested macro references for #showtooltip propagation
-- If an action is a {MacroName} reference and that macro has #showtooltip,
-- returns the inner macro's active action; otherwise returns nil
-- depth parameter prevents infinite recursion
function CleveRoids.ResolveNestedMacroActive(action, depth)
    if not action or not action.action then return nil end
    depth = depth or 0
    if depth > 5 then return nil end  -- prevent infinite recursion

    -- Check if this action is a macro reference {MacroName}
    local macroName = CleveRoids.GetMacroNameFromAction(action.action)
    if not macroName then return nil end

    -- Get or parse the inner macro
    local innerMacro = CleveRoids.GetMacro(macroName)
    if not innerMacro then
        innerMacro = CleveRoids.ParseMacro(macroName)
    end
    if not innerMacro or not innerMacro.actions then return nil end

    -- Check if inner macro has #showtooltip (indicated by having a tooltip or action list)
    if not innerMacro.actions.tooltip and table.getn(innerMacro.actions.list or {}) == 0 then
        return nil
    end

    -- Run TestForActiveAction on inner macro to get its current active
    CleveRoids.TestForActiveAction(innerMacro.actions)

    -- If inner macro has an active action, check if it's also a nested macro
    if innerMacro.actions.active then
        local deeperActive = CleveRoids.ResolveNestedMacroActive(innerMacro.actions.active, depth + 1)
        if deeperActive then
            return deeperActive
        end
        return innerMacro.actions.active
    end

    return nil
end

function CleveRoids.TestForActiveAction(actions)
    if not actions then return end
    local currentActive = actions.active
    local currentSequence = actions.sequence
    local hasActive = false
    local newActiveAction = nil
    local newSequence = nil
    local firstUnconditional = nil

    -- Use tooltip-only branch when:
    -- 1. #showtooltip has an explicit argument (explicitTooltip = true), OR
    -- 2. #showtooltip exists but action list is empty (bare "#showtooltip")
    -- This ensures explicit tooltips always show their icon/usability correctly.
    if actions.tooltip and (actions.explicitTooltip or table.getn(actions.list) == 0) then
        -- For explicit tooltips, directly use the tooltip as active action
        -- (actions.cmd/args are empty, so TestAction would fail)
        if actions.explicitTooltip then
            hasActive = true
            newActiveAction = actions.tooltip
        elseif CleveRoids.TestAction(actions.cmd or "", actions.args or "") then
            -- Bare #showtooltip (no arg) - validate with TestAction
            hasActive = true
            newActiveAction = actions.tooltip
        end

        -- Resolve nested macro references for #showtooltip propagation
        if hasActive and newActiveAction then
            local macroName = CleveRoids.GetMacroNameFromAction(actions.tooltip.action)
            if macroName then
                local resolved = CleveRoids.ResolveNestedMacroActive(actions.tooltip, 0)
                if resolved then
                    newActiveAction = resolved
                else
                    -- Inner macro didn't resolve - no active action
                    hasActive = false
                    newActiveAction = nil
                end
            end
        end
    else
        -- First pass: find first action with conditionals that passes
        for _, action in ipairs(actions.list) do
            local result = CleveRoids.TestAction(action.cmd, action.args)

            -- Check if action has conditionals
            local _, conditionals = CleveRoids.GetParsedMsg(action.args)

            -- Skip this action for icon display if it has the '?' prefix
            -- Note: CleveRoids._ignoretooltip is a side-effect flag set by GetParsedMsg
            local shouldSkipForIcon = CleveRoids._ignoretooltip == 1

            -- break on first action that passes tests (unless it should be skipped for icon)
            if result and not shouldSkipForIcon then
                hasActive = true
                if action.sequence then
                    newSequence = action.sequence
                    newActiveAction = CleveRoids.GetCurrentSequenceAction(newSequence)
                    -- Check if current step is a stop step - if so, skip this sequence for icon
                    if newActiveAction and newActiveAction.action then
                        local stepLower = string.lower(CleveRoids.Trim(newActiveAction.action))
                        if stepLower == "nil" or stepLower == "null" or stepLower == "pass" or stepLower == "noop" then
                            hasActive = false
                            newActiveAction = nil
                            newSequence = nil
                        end
                    end
                    if not newActiveAction then hasActive = false end
                else
                    newActiveAction = action
                    -- Resolve nested macro references for #showtooltip propagation
                    -- If inner macro doesn't resolve, continue to next action
                    local macroName = CleveRoids.GetMacroNameFromAction(action.action)
                    if macroName then
                        local resolved = CleveRoids.ResolveNestedMacroActive(action, 0)
                        if resolved then
                            newActiveAction = resolved
                        else
                            -- Inner macro didn't resolve - try next action
                            hasActive = false
                            newActiveAction = nil
                        end
                    end
                end
                if hasActive then break end
            end

            -- Track first unconditional non-macro action as fallback
            if not conditionals and not firstUnconditional and not shouldSkipForIcon then
                -- Don't use unresolvable macro refs as fallback
                local macroName = CleveRoids.GetMacroNameFromAction(action.action)
                if not macroName then
                    firstUnconditional = action
                end
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
            -- Default to -1 (unknown) so we fall through to proxy slot or original function
            -- Only set to 1/0 when we have a definitive answer from IsSpellInRange
            actions.active.inRange = -1

            -- Enhanced nampower range check with spell ID support
			if IsSpellInRange then
                local unit = actions.active.conditionals and actions.active.conditionals.target or "target"
				if unit == "focus" and pfUI and pfUI.uf and pfUI.uf.focus and pfUI.uf.focus.label and pfUI.uf.focus.id then
					unit = pfUI.uf.focus.label .. pfUI.uf.focus.id
				end
				local resolvedMark = CleveRoids.ResolveRaidMarkUnit(unit)
				if resolvedMark then unit = resolvedMark end

				-- PERFORMANCE: Cache spell name construction using two-level cache (no string concat for lookup)
				local castName = actions.active.action
				if actions.active.spell and actions.active.spell.name then
					local spellName = actions.active.spell.name
					local rank = actions.active.spell.rank
								 or (actions.active.spell.highest and actions.active.spell.highest.rank)
					if rank and rank ~= "" then
						-- Two-level cache: spellNameCache[spellName][rank] = "SpellName(Rank X)"
						local nameCache = CleveRoids.spellNameCache[spellName]
						if not nameCache then
							nameCache = {}
							CleveRoids.spellNameCache[spellName] = nameCache
						end
						castName = nameCache[rank]
						if not castName then
							castName = spellName .. "(" .. rank .. ")"
							nameCache[rank] = castName
						end
					end
				end

				-- PERFORMANCE: Try to get spell ID with caching
				local spellId = nil
				if GetSpellIdForName then
					-- Check cache first
					local cachedId = CleveRoids.spellIdCache[castName]
					if cachedId then
						spellId = cachedId
					else
						spellId = GetSpellIdForName(castName)
						if spellId and spellId > 0 then
							CleveRoids.spellIdCache[castName] = spellId
						end
					end
				end

				-- Check range using API wrapper (handles all cases properly)
				local API = CleveRoids.NampowerAPI
				local checkValue = spellId and spellId > 0 and spellId or castName

				if UnitExists(unit) then
					-- We have a target - use API wrapper for proper range checking
					-- API.IsSpellInRange handles: native check, -1 for self-cast, UnitXP fallback
					if API then
						local r = API.IsSpellInRange(checkValue, unit)
						if r ~= nil then
							actions.active.inRange = r
						end
					elseif IsSpellInRange then
						-- No API, use native directly
						local nativeResult = IsSpellInRange(checkValue, unit)
						if nativeResult == 0 or nativeResult == 1 then
							actions.active.inRange = nativeResult
						elseif nativeResult == -1 then
							-- Self-cast/ground-targeted spell, always in range
							actions.active.inRange = 1
						end
					end
				end
				-- No target: don't set inRange, let proxy slot / original behavior handle it
			end

            -- Check if spell is usable first (handles forms, stances, and power type correctly)
            local isUsableBySpell, notEnoughPower = nil, nil
            if IsSpellUsable then
                -- pcall to handle spells not in spellbook (Nampower throws error)
                local ok, usable, oom = pcall(IsSpellUsable, actions.active.action)
                if ok then
                    isUsableBySpell, notEnoughPower = usable, oom
                end
            end

            -- For OOM check, use proper mana source
            if notEnoughPower ~= nil then
                -- Prefer IsSpellUsable result if available (Nampower)
                actions.active.oom = (notEnoughPower == 1)
            else
                -- SuperWoW: UnitMana returns (current power, caster mana) for druids
                local currentPower, casterMana = UnitMana("player")

                -- For druids with SuperWoW, use caster mana for spell cost checks
                local manaToCheck = currentPower
                if CleveRoids.playerClass == "DRUID" and type(casterMana) == "number" then
                    manaToCheck = casterMana
                end

                actions.active.oom = (manaToCheck < actions.active.spell.cost)
            end

            local start, duration = GetSpellCooldown(actions.active.spell.spellSlot, actions.active.spell.bookType)
            local onCooldown = (start > 0 and duration > 0)

            if actions.active.isReactive then
                -- For Overpower, Revenge, Riposte: ONLY use combat log tracking
                local spellName = actions.active.action
                local useCombatLogOnly = (spellName == "Overpower" or spellName == "Revenge" or spellName == "Riposte")

                if useCombatLogOnly then
                    -- Only trust HasReactiveProc for these spells
                    local hasProc = CleveRoids.HasReactiveProc and CleveRoids.HasReactiveProc(spellName)
                    if CleveRoids.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cff00ff00[UPDATE USABLE]|r %s: hasProc=%s, previousUsable=%s, inRange=%s, oom=%s",
                                spellName, tostring(hasProc), tostring(previousUsable), tostring(actions.active.inRange), tostring(actions.active.oom))
                        )
                    end
                    if hasProc then
                        -- Proc is active, show as usable if in range and have enough rage/mana
                        if actions.active.inRange ~= 0 and not actions.active.oom then
                            actions.active.usable = 1
                        elseif pfUI and pfUI.bars and actions.active.oom then
                            actions.active.usable = 2  -- pfUI: out of mana/rage
                        else
                            actions.active.usable = nil
                        end
                        if CleveRoids.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(
                                string.format("|cff00ff00[UPDATE USABLE]|r %s: SET usable=%s (proc active)",
                                    spellName, tostring(actions.active.usable))
                            )
                        end
                    else
                        -- No proc = not usable
                        actions.active.usable = nil
                        if CleveRoids.debug then
                            DEFAULT_CHAT_FRAME:AddMessage(
                                string.format("|cff00ff00[UPDATE USABLE]|r %s: SET usable=nil (no proc)", spellName)
                            )
                        end
                    end
                else
                    -- For other reactive spells, use the original fallback logic
                    -- Check combat log-based proc tracking first (stance-independent)
                    if CleveRoids.HasReactiveProc and CleveRoids.HasReactiveProc(actions.active.action) then
                        -- Proc is active, show as usable if in range and have enough rage/mana
                        if actions.active.inRange ~= 0 and not actions.active.oom then
                            actions.active.usable = 1
                        elseif pfUI and pfUI.bars and actions.active.oom then
                            actions.active.usable = 2  -- pfUI: out of mana/rage
                        else
                            actions.active.usable = nil
                        end
                    -- Use Nampower's IsSpellUsable if available (stance-aware fallback)
                    elseif IsSpellUsable then
                        -- pcall to handle spells not in spellbook (Nampower throws error)
                        local ok, usable, oom = pcall(IsSpellUsable, actions.active.action)
                        if ok and usable == 1 and oom ~= 1 then
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
                end
            elseif isUsableBySpell == 1 and actions.active.inRange ~= 0 then
                -- Use IsUsableSpell result if available (handles forms/stances correctly)
                actions.active.usable = 1
            elseif isUsableBySpell == 0 then
                -- IsSpellUsable returned 0 = wrong stance/form, not enough power type, etc.
                actions.active.usable = nil
            elseif actions.active.inRange ~= 0 and not actions.active.oom then
                -- Fallback to mana check ONLY if IsSpellUsable not available
                actions.active.usable = 1

            -- pfUI:actionbar.lua -- update usable [out-of-range = 1, oom = 2, not-usable = 3, default = 0]
            elseif pfUI and pfUI.bars and actions.active.oom then
                actions.active.usable = 2
            else
                actions.active.usable = nil
            end

            -- Check if this is a toggled buff ability (Prowl, Shadowmeld) and darken if buff is active
            -- This must come AFTER all other usability checks to have final say
            -- PERFORMANCE: Cache normalized spell name on the action object to avoid gsub per-frame
            local spellName = actions.active._normalizedName
            if not spellName then
                spellName = string.gsub(actions.active.action, "%s*%(.-%)%s*$", "")
                spellName = string.gsub(spellName, "_", " ")
                actions.active._normalizedName = spellName
            end

            -- PERFORMANCE: Use cached lookup instead of creating table per-call
            if CleveRoids.IsToggledBuffAbility(spellName) then
                if CleveRoids.ValidatePlayerBuff(spellName) then
                    -- Buff is active, darken the icon like "wrong stance" (grayed out, not red)
                    actions.active.usable = nil
                    actions.active.oom = false  -- Make sure we don't show red tint
                end
            end
        else
            actions.active.inRange = 1
            actions.active.usable = 1
        end
        if actions.active.usable ~= previousUsable or
           actions.active.oom ~= previousOom or
           actions.active.inRange ~= previousInRange then
            changed = true
            if CleveRoids.debug and actions.active.isReactive then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("|cffff00ff[STATE CHANGED]|r %s: usable %s->%s, will send ACTIONBAR_SLOT_CHANGED",
                        actions.active.action, tostring(previousUsable), tostring(actions.active.usable))
                )
            end
        end
    end
    return changed
end

-- PERFORMANCE: Static buffer references for hot path
local _actionsToSlotsBuffer = CleveRoids._actionsToSlotsBuffer
local _slotsBuffer = CleveRoids._slotsBuffer
local _actionsListBuffer = CleveRoids._actionsListBuffer

function CleveRoids.TestForAllActiveActions()
    -- PERFORMANCE: Reuse static buffers instead of creating new tables each call
    -- Group slots by their actions object to handle shared macro references
    local actionsToSlots = _actionsToSlotsBuffer
    local actionsList = _actionsListBuffer
    local actionsCount = 0

    -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
    local Actions = CleveRoids.Actions
    local slot, actions = next(Actions)
    while slot do
        if not actionsToSlots[actions] then
            -- Reuse or create slots array from pool
            local slots = _slotsBuffer[actions]
            if not slots then
                slots = {}
                _slotsBuffer[actions] = slots
            end
            slots[1] = slot
            slots._count = 1
            actionsToSlots[actions] = slots
            actionsCount = actionsCount + 1
            actionsList[actionsCount] = actions
        else
            local slots = actionsToSlots[actions]
            local count = slots._count + 1
            slots[count] = slot
            slots._count = count
        end
        slot, actions = next(Actions, slot)
    end

    -- Test each unique actions object once and send events to ALL slots that share it
    for i = 1, actionsCount do
        local actions = actionsList[i]
        local slots = actionsToSlots[actions]
        local stateChanged = CleveRoids.TestForActiveAction(actions)
        if stateChanged then
            -- Send event to ALL slots that use this macro
            local count = slots._count
            for j = 1, count do
                CleveRoids.SendEventForAction(slots[j], "ACTIONBAR_SLOT_CHANGED", slots[j])
            end
        end
        -- Clear for reuse (reset count and clear buffer reference)
        for j = 1, slots._count do
            slots[j] = nil
        end
        slots._count = 0
        actionsToSlots[actions] = nil
        actionsList[i] = nil  -- Clear actionsList entry for reuse
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

-- PERFORMANCE: Static buffer for arg backup
local _originalArgsBuffer = CleveRoids._originalArgsBuffer

function CleveRoids.SendEventForAction(slot, event, ...)
    local old_this = this

    -- PERFORMANCE: Reuse static buffer instead of creating table each call
    local original_global_args = _originalArgsBuffer
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

    -- FIX: Skip addon handler calls during initial indexing to prevent 120 rapid calls
    if CleveRoids._suppressActionHandlers then
        return
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
-- Note on macro flags:
--   stopMacroFlag: Stops ALL remaining lines (propagates to parent macros)
--   skipMacroFlag: Stops only current macro (cleared on return, parent continues)
function CleveRoids.ExecuteMacroBody(body,inline)
    local lines = CleveRoids.splitString(body, "\n")
    if inline then lines = CleveRoids.splitString(body, "\\n"); end

    -- Save parent's stopMacroFlag state (in case we need to preserve it)
    local parentStopFlag = CleveRoids.stopMacroFlag

    -- Clear flags at start of this macro execution
    -- Note: We DON'T clear if parent already set stopMacroFlag (shouldn't execute at all)
    if not parentStopFlag then
        CleveRoids.stopMacroFlag = false
    end
    CleveRoids.skipMacroFlag = false  -- Always start fresh for skipmacro

    if CleveRoids.macroRefDebug then
        CleveRoids.Print("|cff00ffff[MacroRef]|r ExecuteMacroBody called with " .. table.getn(lines) .. " lines")
    end

    for k,v in pairs(lines) do
        local trimmed = CleveRoids.Trim(v)
        local cmdHandled = false

        -- Skip #showtooltip lines - they're only meaningful for action bar display,
        -- not for execution. This allows inner macros to have #showtooltip without
        -- causing issues when called from other macros.
        if string.find(trimmed, "^#showtooltip") then
            if CleveRoids.macroRefDebug then
                CleveRoids.Print("|cff888888[MacroRef]|r Skipping #showtooltip line in inner macro")
            end
            cmdHandled = true
        end

        -- IMPORTANT: Check for /nofirstaction BEFORE the stop flag check
        -- This allows /nofirstaction to clear the stopMacroFlag set by /firstaction
        local _, _, nofirstactionArgs = string.find(trimmed, "^/nofirstaction%s*(.*)")
        if nofirstactionArgs then
            -- Capture stopOnCastFlag BEFORE DoNoFirstAction clears it
            -- If it was true, stopMacroFlag was set by /firstaction, not /stopmacro
            local wasFirstActionActive = CleveRoids.stopOnCastFlag
            CleveRoids.DoNoFirstAction(nofirstactionArgs)
            -- Also clear stopMacroFlag if it was set by firstaction mechanism
            -- (but NOT if it was set by explicit /stopmacro)
            if wasFirstActionActive and CleveRoids.stopMacroFlag then
                -- stopOnCastFlag was true before we cleared it, and stopMacroFlag is set
                -- This means stopMacroFlag was set by the firstaction mechanism, clear it
                CleveRoids.stopMacroFlag = false
                if CleveRoids.macroRefDebug then
                    CleveRoids.Print("|cff00ff00[MacroRef]|r /nofirstaction cleared stopMacroFlag - resuming macro")
                end
            end
            if CleveRoids.macroRefDebug then
                CleveRoids.Print("|cff88ff88[MacroRef]|r Executing line " .. k .. ": " .. string.sub(v, 1, 60))
            end
            cmdHandled = true
        end

        -- Check both macro stop flags before each line (but skip if we just handled /nofirstaction)
        -- stopMacroFlag: stop this AND parent macros
        -- skipMacroFlag: stop only this macro (parent continues)
        if not cmdHandled and (CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag) then
            -- If stopOnCastFlag is true, the stop was caused by the firstaction mechanism
            -- Don't break the loop - just skip this line (allows /nofirstaction to be reached)
            if CleveRoids.stopOnCastFlag and CleveRoids.stopMacroFlag and not CleveRoids.skipMacroFlag then
                if CleveRoids.macroRefDebug then
                    CleveRoids.Print("|cffff8800[MacroRef]|r Skipping line " .. k .. " (firstaction mode)")
                end
                cmdHandled = true  -- Skip this line but continue loop to allow /nofirstaction
            else
                -- This is a /stopmacro or /skipmacro stop - actually break
                if CleveRoids.macroRefDebug then
                    local reason = CleveRoids.stopMacroFlag and "/stopmacro" or "/skipmacro"
                    CleveRoids.Print("|cffff8800[MacroRef]|r Stopped at line " .. k .. " due to " .. reason)
                end
                break
            end
        end

        if not cmdHandled then
            if CleveRoids.macroRefDebug then
                CleveRoids.Print("|cff88ff88[MacroRef]|r Executing line " .. k .. ": " .. string.sub(v, 1, 60))
            end

            -- IMPORTANT: Handle macro control commands directly to bypass Blizzard's built-in /stopmacro
            -- Blizzard intercepts bare /stopmacro before it reaches our SlashCmdList handler

            -- Check for /stopmacro (with or without conditionals)
            local _, _, stopmacroArgs = string.find(trimmed, "^/stopmacro%s*(.*)")
            if stopmacroArgs then
                CleveRoids.DoStopMacro(stopmacroArgs)
                cmdHandled = true
            end

            -- Check for /skipmacro (with or without conditionals)
            if not cmdHandled then
                local _, _, skipmacroArgs = string.find(trimmed, "^/skipmacro%s*(.*)")
                if skipmacroArgs then
                    CleveRoids.DoSkipMacro(skipmacroArgs)
                    cmdHandled = true
                end
            end

            -- Check for /firstaction (with or without conditionals)
            if not cmdHandled then
                local _, _, firstactionArgs = string.find(trimmed, "^/firstaction%s*(.*)")
                if firstactionArgs then
                    CleveRoids.DoFirstAction(firstactionArgs)
                    cmdHandled = true
                end
            end

            -- FIX: Handle /startattack directly - not a native vanilla WoW command
            -- Without SuperMacro, ChatEdit_SendText may not route addon slash commands properly
            if not cmdHandled then
                local _, _, startattackArgs = string.find(trimmed, "^/startattack%s*(.*)")
                if startattackArgs then
                    if SlashCmdList.STARTATTACK then
                        SlashCmdList.STARTATTACK(startattackArgs)
                    end
                    cmdHandled = true
                end
            end

            -- FIX: Handle /stopattack directly - not a native vanilla WoW command
            if not cmdHandled then
                local _, _, stopattackArgs = string.find(trimmed, "^/stopattack%s*(.*)")
                if stopattackArgs then
                    if SlashCmdList.STOPATTACK then
                        SlashCmdList.STOPATTACK(stopattackArgs)
                    end
                    cmdHandled = true
                end
            end
        end

        -- For all other commands, use ChatEdit_SendText
        if not cmdHandled then
            ChatFrameEditBox:SetText(v)
            ChatEdit_SendText(ChatFrameEditBox)
        end
    end

    -- Clear skipMacroFlag after this macro completes (don't propagate to parent)
    -- stopMacroFlag is intentionally LEFT SET so it propagates up
    CleveRoids.skipMacroFlag = false

    return true
end

-- Gets the body of the Macro with the given name
-- name: The name of the Macro
-- returns: The body of the macro
function CleveRoids.GetMacroBody(name)
    local macro = CleveRoids.GetMacro(name)
    return macro and macro.body
end

-- Attempts to execute a macro by the given name or index (Blizzard or Super tab)
-- Returns: true if something was executed, false otherwise
-- Supports: macro name (string), macro index (number or numeric string like "19")
-- Uses CleveRoids' own ExecuteMacroBody for processing (supports enhanced syntax)
function CleveRoids.ExecuteMacroByName(name)
    if not name or name == "" then
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cffff0000[MacroRef]|r ExecuteMacroByName called with empty name")
        end
        return false
    end

    if CleveRoids.macroRefDebug then
        CleveRoids.Print("|cff00ffff[MacroRef]|r ExecuteMacroByName called with: '" .. name .. "'")
    end

    local body
    local source = nil

    -- Check if input is a numeric index (e.g., "19" or 19)
    local numericIndex = tonumber(name)

    -- 1) Try Blizzard macro (by index or name)
    if numericIndex then
        -- Numeric index - get body directly (supports character macros 19-36)
        local _n, _tex, b = GetMacroInfo(numericIndex)
        if b and b ~= "" then
            body = b
            source = "Blizzard (index " .. numericIndex .. ")"
        end
    else
        -- String name - look up by name
        local id = GetMacroIndexByName(name)
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cff888888[MacroRef]|r GetMacroIndexByName('" .. name .. "') = " .. tostring(id))
        end
        if id and id ~= 0 then
            local _n, _tex, b = GetMacroInfo(id)
            if b and b ~= "" then
                body = b
                source = "Blizzard (slot " .. id .. ")"
            end
        end
    end

    -- 2) SuperMacro's Super macros (by name only, not index)
    -- These are the 7000-char extended macros stored in SM_SUPER
    if not body and not numericIndex then
        if type(GetSuperMacroInfo) == "function" then
            local _n2, _t2, b2 = GetSuperMacroInfo(name)
            if b2 and b2 ~= "" then
                body = b2
                source = "SuperMacro"
            end
        end
    end

    -- 3) CRM cache fallback (by name only)
    if not body and not numericIndex then
        if type(CleveRoids.GetMacro) == "function" then
            local m = CleveRoids.GetMacro(name)
            if m and m.body and m.body ~= "" then
                body = m.body
                source = "CRM cache"
            end
        end
    end

    if not body or body == "" then
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cffff0000[MacroRef]|r Macro '" .. name .. "' not found in any source")
        end
        return false
    end

    if CleveRoids.macroRefDebug then
        CleveRoids.Print("|cff00ff00[MacroRef]|r Found macro '" .. name .. "' from " .. source)
    end

    -- Execute using CleveRoids' processor (supports conditionals, extended syntax)
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
        cond       = condBlock or "",  -- Store conditional block for evaluation in DoCastSequence
        list       = {},
        perTargetState = {},  -- [guid] = {index = N, lastUpdate = T} for reset=target
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

        -- check for #showtooltip on first line
        if i == 1 then
            local _, _, st, _, tt = string.find(line, "(#showtooltip)(%s?(.*))")

            if st then
                hasShowTooltip = true
                tt = CleveRoids.Trim(tt)

                -- #showtooltip with explicit item/spell/macro specified
                if tt ~= "" then
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
                end
                -- Continue parsing remaining lines for action list (needed for nested macro resolution)
            end
            -- No #showtooltip: still continue parsing to build action list for inner macro resolution
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
    action = string.gsub(action, "%s*%(%s*Rank%s+%d+%s*%)%s*$", "")

    -- IMPORTANT: if there's NO conditional block, return nil conditionals so
    -- DoWithConditionals will hit the {macroName} execution branch.
    if not conditionBlock then
        local hasFlag = (noSpam and noSpam ~= "") or (cancelAura and cancelAura ~= "")
        if hasFlag and action ~= "" then
            if noSpam ~= "" then
                local spamCond = CleveRoids.GetSpammableConditional(action)
                if spamCond then
                    conditionals[spamCond] = { action }
                    -- Also create _groups entry for consistency with Multi()
                    if not conditionals._groups then
                        conditionals._groups = {}
                    end
                    conditionals._groups[spamCond] = { { values = { action }, operator = "OR" } }
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

    -- ! prefix with explicit conditionals: store as a flag for execution-time anti-toggle,
    -- rather than injecting an implicit conditional that gets AND'd with user conditions.
    -- The anti-toggle check happens in DoWithConditionals before CastSpellByName.
    if noSpam and noSpam ~= "" then
        conditionals.noSpam = true
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
                        -- PERFORMANCE: Use module-level constant instead of creating table per-call
                        if BOOLEAN_CONDITIONALS[condition] then
                            conditionals[condition] = true
                        else
                            conditionals[condition] = conditionals.action
                            -- Create first group for non-boolean conditionals
                            if not conditionals._groups then
                                conditionals._groups = {}
                            end
                            conditionals._groups[condition] = { { values = { conditionals.action }, operator = "OR" } }
                        end
                    else
                        -- existing code for when conditionals[condition] already exists
                        if type(conditionals[condition]) ~= "table" then
                            conditionals[condition] = { conditionals[condition] }
                        end
                        table.insert(conditionals[condition], conditionals.action)

                        -- Multiple instances of same conditional = AND logic
                        if not conditionals._operators then
                            conditionals._operators = {}
                        end
                        conditionals._operators[condition] = "AND"

                        -- Add new group for this instance
                        if not conditionals._groups then
                            conditionals._groups = {}
                        end
                        if not conditionals._groups[condition] then
                            conditionals._groups[condition] = {}
                        end
                        table.insert(conditionals._groups[condition], { values = { conditionals.action }, operator = "OR" })
                    end
                else
                    -- Has args. Ensure the key's value is a table and add new arguments.
                    -- Track if this conditional already existed (repeated via comma)
                    local conditionAlreadyExists = conditionals[condition] ~= nil

                    if not conditionals[condition] then
                        conditionals[condition] = {}
                    elseif type(conditionals[condition]) ~= "table" then
                        conditionals[condition] = { conditionals[condition] }
                    end

                    -- Detect which separator is used: / (OR) or & (AND)
                    -- Initialize metadata tables if needed
                    if not conditionals._operators then
                        conditionals._operators = {}
                    end
                    if not conditionals._groups then
                        conditionals._groups = {}
                    end

                    -- Check which separator is present in the CURRENT args
                    local hasSlash = string.find(args, "/")
                    local hasAmpersand = string.find(args, "&")

                    -- Detect if & is part of a multi-comparison pattern (e.g., >0&<10)
                    -- Pattern: operator+number followed by & (with optional whitespace) followed by operator
                    -- IMPORTANT: Only whitespace allowed around &, NOT letters (to distinguish from Rip>3&Rake>3)
                    local isMultiComparison = hasAmpersand and string.find(args, "[>~=<]+%d+%.?%d*%s*&%s*[>~=<]")

                    local separator = "/"
                    local operatorType = "OR"

                    if hasAmpersand and not hasSlash and not isMultiComparison then
                        separator = "&"
                        operatorType = "AND"
                    elseif hasAmpersand and hasSlash then
                        -- Both separators present - default to / (OR) and warn
                        -- Could add a warning here in the future
                        separator = "/"
                        operatorType = "OR"
                    end

                    -- Store the operator type for this conditional (for backwards compat)
                    -- Note: when groups exist, Multi/NegatedMulti will use per-group operators
                    conditionals._operators[condition] = operatorType

                    -- Create a new group for this conditional instance
                    -- Structure: { values = { ... }, operator = "OR" or "AND" }
                    if not conditionals._groups[condition] then
                        conditionals._groups[condition] = {}
                    end
                    local currentGroup = { values = {}, operator = operatorType }
                    table.insert(conditionals._groups[condition], currentGroup)

                    -- Split args by the determined separator
                    for _, arg_item in CleveRoids.splitString(args, separator) do
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
                            table.insert(currentGroup.values, processed_arg)
                        else
                            local name_to_use = (name and name ~= "") and name or conditionals.action
                            local final_amount_str, num_replacements = string.gsub(amount, "#", "")
                            local should_check_stacks = (num_replacements == 1)

                            -- SPECIAL HANDLING FOR CONDITIONALS WITH MULTIPLE COMPARISONS
                            -- Detect if this conditional has multiple operators
                            -- Example: "ap>1800/<2200" or "Recently_Bandaged>0&<10" or "health>50&<80"
                            -- Works with ANY conditional that supports numeric operators
                            -- Pattern: only whitespace or separators allowed between comparisons, NOT letters
                            if string.find(processed_arg, "[>~=<]+%d+%.?%d*%s*[/&]%s*[>~=<]") then
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
                                    local entry = {
                                        name = CleveRoids.Trim(stat_name),
                                        comparisons = comparisons  -- Store all comparisons
                                    }
                                    table.insert(conditionals[condition], entry)
                                    table.insert(currentGroup.values, entry)
                                else
                                    -- Fallback to single comparison if parsing failed
                                    local entry = {
                                        name = CleveRoids.Trim(name_to_use),
                                        operator = operator,
                                        amount = tonumber(final_amount_str),
                                        checkStacks = should_check_stacks
                                    }
                                    table.insert(conditionals[condition], entry)
                                    table.insert(currentGroup.values, entry)
                                end
                            else
                                -- Normal single-comparison conditional (existing behavior)
                                local entry = {
                                    name = CleveRoids.Trim(name_to_use),
                                    operator = operator,
                                    amount = tonumber(final_amount_str),
                                    checkStacks = should_check_stacks
                                }
                                table.insert(conditionals[condition], entry)
                                table.insert(currentGroup.values, entry)
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

    -- PERFORMANCE: Check cache first before doing string operations
    local cached = CleveRoids.ParsedMsg[msg]
    if cached then
        -- Use cached ignoretooltip value (already computed during first parse)
        CleveRoids._ignoretooltip = cached.ignoretooltip or 0
        return cached.action, cached.conditionals
    end

    -- Only compute ignoretooltip for new messages (not cache hits)
    -- PERFORMANCE: Use string.sub for simple prefix check instead of gsub
    local trimmed = CleveRoids.Trim(msg)
    local ignorecount = (string.sub(trimmed, 1, 1) == "?") and 1 or 0
    CleveRoids._ignoretooltip = ignorecount

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
    -- Save the GUID before clearing it
    local targetGuid = sequence.lastTargetGuid

    sequence.index = 1
    sequence.lastTargetGuid = nil  -- Clear stored GUID so next use captures fresh target

    -- Also reset per-target state for current target if tracking
    if sequence.reset and sequence.reset.target and targetGuid then
        if sequence.perTargetState then
            sequence.perTargetState[targetGuid] = nil
        end
    end
end

function CleveRoids.AdvanceSequence(sequence)
    if sequence.index < table.getn(sequence.list) then
        -- Not at the end yet, just advance normally
        local oldIndex = sequence.index
        sequence.index = sequence.index + 1

        if CleveRoids.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
              "|cff00ff00[Sequence Advanced]|r %d -> %d (of %d)",
              oldIndex, sequence.index, table.getn(sequence.list)
            ))
        end

        -- Sync per-target state if tracking by target
        if sequence.reset and sequence.reset.target and sequence.lastTargetGuid then
            sequence.perTargetState = sequence.perTargetState or {}
            sequence.perTargetState[sequence.lastTargetGuid] = {
                index = sequence.index,
                lastUpdate = GetTime(),
            }
        end
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

    -- Resolve named raid marks (skull/cross/etc.) and mark1-mark8 to native mark# unit tokens
    if conditionals.target then
        local resolvedMark = CleveRoids.ResolveRaidMarkUnit(conditionals.target)
        if resolvedMark then conditionals.target = resolvedMark end
    end

    CleveRoids.FixEmptyTarget(conditionals)

    -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
    local k, v = next(conditionals)
    while k do
        if not CleveRoids.ignoreKeywords[k] then
            if not CleveRoids.Keywords[k] or not CleveRoids.Keywords[k](conditionals) then
                conditionals.target = origTarget
                return
            end
        end
        k, v = next(conditionals, k)
    end

    conditionals.target = origTarget
    return CleveRoids.GetMacroNameFromAction(msg) or msg
end

function CleveRoids.DoWithConditionals(msg, hook, fixEmptyTargetFunc, targetBeforeAction, action)
    -- Check macro stop flags (skip non-control commands when flag is set)
    -- This enables /stopmacro, /skipmacro, /firstaction, /nofirstaction to work without SuperMacro for vanilla macros
    if (CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag) and action ~= "STOPMACRO" and action ~= "SKIPMACRO" and action ~= "FIRSTACTION" and action ~= "NOFIRSTACTION" then
        return false
    end

    local msg, conditionals = CleveRoids.GetParsedMsg(msg)

    -- Debug: Log parsed msg and action type
    if CleveRoids.equipDebugLog and action and action ~= CastSpellByName then
        CleveRoids.Print("|cff888888[EquipLog] DoWithConditionals: parsed msg='" .. tostring(msg) .. "' action=" .. tostring(action) .. "|r")
    end

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

            -- Handle STOPMACRO/SKIPMACRO/FIRSTACTION/NOFIRSTACTION without conditionals (bare command)
            if action == "STOPMACRO" then
                CleveRoids.stopMacroFlag = true
                return true
            elseif action == "SKIPMACRO" then
                CleveRoids.skipMacroFlag = true
                return true
            elseif action == "FIRSTACTION" then
                CleveRoids.stopOnCastFlag = true
                return true
            elseif action == "NOFIRSTACTION" then
                -- Clear flags - same logic as DoNoFirstAction
                local wasFirstActionActive = CleveRoids.stopOnCastFlag
                CleveRoids.stopOnCastFlag = false
                if wasFirstActionActive and CleveRoids.stopMacroFlag then
                    CleveRoids.stopMacroFlag = false
                end
                return true
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

    -- Resolve named raid marks (skull/cross/etc.) and mark1-mark8 to native mark# unit tokens
    if conditionals.target then
        local resolvedMark = CleveRoids.ResolveRaidMarkUnit(conditionals.target)
        if resolvedMark then conditionals.target = resolvedMark end
    end

    -- Handle [multiscan:priority] - scan enemies and find best target
    -- Must be processed BEFORE the Keywords loop since it sets conditionals.target
    -- Pass origTarget so @unit syntax makes that unit exempt from combat check
    if conditionals.multiscan then
        local scanResult = CleveRoids.ResolveMultiscanTarget(conditionals, origTarget)
        if not scanResult then
            -- No valid target found - fail this conditional line (try next)
            conditionals.target = origTarget
            return false
        end
        -- Set target to the found GUID for soft-casting via SuperWoW or Nampower v2.37+
        conditionals.target = scanResult
        -- Don't need to retarget since we're using GUID directly
        needRetarget = false
    end

    for k, v in pairs(conditionals) do
        if not CleveRoids.ignoreKeywords[k] then
            local result = CleveRoids.Keywords[k] and CleveRoids.Keywords[k](conditionals)
            -- Debug logging for equipped conditional when equipDebugLog is enabled
            if CleveRoids.equipDebugLog and (k == "equipped" or k == "noequipped") then
                local valStr = type(v) == "table" and table.concat(v, ", ") or tostring(v)
                CleveRoids.Print("|cff888888[EquipLog] Conditional [" .. k .. ":" .. valStr .. "] = " ..
                    (result and "|cff00ff00PASS|r" or "|cffff0000FAIL|r") .. "|r")
            end
            -- Debug logging for macro reference debug
            if CleveRoids.macroRefDebug then
                local valStr = (v == true) and "" or (type(v) == "table" and table.concat(v, ", ") or tostring(v))
                CleveRoids.Print("|cff888888[MacroRef]|r [" .. k .. (valStr ~= "" and (":" .. valStr) or "") .. "] = " ..
                    (result and "|cff00ff00PASS|r" or "|cffff0000FAIL|r"))
            end
            if not result then
                if needRetarget then
                    TargetLastTarget()
                    needRetarget = false
                end
                conditionals.target = origTarget
                return false
            end
        end
    end

    if conditionals.target ~= nil and targetBeforeAction and not (action == CastSpellByName and (CleveRoids.hasSuperwow or CleveRoids.hasCastSpellByNameUnitToken)) then
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
        -- Set flag to stop subsequent lines in current macro AND parent macros
        CleveRoids.stopMacroFlag = true
        return true
    elseif action == "SKIPMACRO" then
        -- Set flag to skip remaining lines in current submacro only
        CleveRoids.skipMacroFlag = true
        return true
    elseif action == "FIRSTACTION" then
        -- Set flag to stop on first successful cast/use
        CleveRoids.stopOnCastFlag = true
        return true
    elseif action == "NOFIRSTACTION" then
        -- Clear flags to re-enable multi-queue behavior
        -- Also clear stopMacroFlag if it was set by the firstaction mechanism
        local wasFirstActionActive = CleveRoids.stopOnCastFlag
        CleveRoids.stopOnCastFlag = false
        if wasFirstActionActive and CleveRoids.stopMacroFlag then
            CleveRoids.stopMacroFlag = false
        end
        return true
    end

    local result = true
    if string.sub(msg, 1, 1) == "{" and string.sub(msg, -1) == "}" then
        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cff00ffff[MacroRef]|r Detected macro reference: " .. msg)
        end
        if string.sub(msg, 2, 2) == "\"" and string.sub(msg, -2,-2) == "\"" then
            result = CleveRoids.ExecuteMacroBody(string.sub(msg, 3, -3), true)
        else
            result = CleveRoids.ExecuteMacroByName(string.sub(msg, 2, -2))
        end
    elseif msg == "" or msg == nil then
        -- Empty action (conditionals passed but no spell to cast)
        -- For non-spell actions (pet commands, etc.), still execute the action
        if CleveRoids.equipDebugLog and action and action ~= CastSpellByName then
            CleveRoids.Print("|cffff8800[EquipLog] Empty msg branch - calling action() with no args|r")
        end
        if action and action ~= CastSpellByName then
            action()
            result = true
        else
            result = false
        end
    else
        local castMsg = msg
        -- FLEXIBLY check for any rank text like "(Rank 9)" before adding the highest rank
        -- Use specific "(Rank" check instead of any parentheses, so spells like
        -- "Faerie Fire (Feral)" still get their rank appended automatically
        if action == CastSpellByName and not string.find(msg, "%(Rank") then
            local sp = CleveRoids.GetSpell(msg)
            local rank = sp and (sp.rank or (sp.highest and sp.highest.rank))
            if rank and rank ~= "" then
                castMsg = msg .. "(" .. rank .. ")"
            end
        end
        if action == CastSpellByName then
            -- ! prefix anti-toggle: prevent CastSpellByName from toggling off active spells.
            -- For Attack/AutoShot/Shoot, use the non-toggling AttackTarget() API.
            -- For self-buffs/shapeshifts, skip if already active on the player.
            if conditionals.noSpam then
                local spamType = CleveRoids.spamConditions[msg]
                if spamType == "checkchanneled" then
                    -- Attack/AutoShot/Shoot: use non-toggling API
                    if msg == CleveRoids.Localized.Attack then
                        AttackTarget()
                        if needRetarget then TargetLastTarget() end
                        conditionals.target = origTarget
                        return true
                    end
                    -- AutoShot/Shoot: checkchanneled prevents toggle (already handled below)
                else
                    -- Self-buff/shapeshift: skip if already active on player
                    if CleveRoids.ValidatePlayerBuff(msg) then
                        if needRetarget then TargetLastTarget() end
                        conditionals.target = origTarget
                        return false
                    end
                end
            end
            -- Legacy path: !Attack without explicit conditionals (checkchanneled injected)
            if msg == CleveRoids.Localized.Attack and conditionals.checkchanneled then
                AttackTarget()
            elseif (CleveRoids.hasSuperwow or CleveRoids.hasCastSpellByNameUnitToken) and conditionals.target then
                -- Let Nampower DLL handle queuing natively via its CastSpellByName hook
                CastSpellByName(castMsg, conditionals.target)
            else
                CastSpellByName(castMsg)
            end
        else
            -- For other actions like UseContainerItem etc.
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cff00ff00[EquipLog] Calling action('" .. tostring(msg) .. "')|r")
            end
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
    if CleveRoids.ChannelTimeDebug then
        if msg and string.find(msg, "Arcane") then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[/cast BUTTON PRESS]|r " .. msg)
        end
    end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = parts[i]
        if CleveRoids.DoWithConditionals(v, CleveRoids.Hooks.CAST_SlashCmd, CleveRoids.FixEmptyTarget, not CleveRoids.hasSuperwow, CastSpellByName) then
            -- If /firstaction was used, stop macro evaluation after first successful cast
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

-- Resolve unit for /pfcast: mouseover → GetMouseFocus label+id → mouseoverUnit → target → player
-- Mirrors pfUI's own unit resolution order so /pfcast conditionals evaluate against the same unit
-- that pfUI would cast on.
local function ResolvePfCastUnit()
    if UnitExists("mouseover") then
        return "mouseover"
    end
    local frame = GetMouseFocus and GetMouseFocus()
    if frame and frame.label and frame.id then
        return frame.label .. frame.id
    elseif CleveRoids.mouseoverUnit and UnitExists(CleveRoids.mouseoverUnit) then
        return CleveRoids.mouseoverUnit
    elseif UnitExists("target") then
        return "target"
    elseif GetCVar and GetCVar("autoSelfCast") == "1" then
        return "player"
    end
    return nil
end

-- /pfcast with CleveRoids conditionals: evaluate conditionals then cast via pfUI's mouseover chain.
-- Called from the SlashCmdList.PFCAST hook (set up by Extensions/Mouseover/pfUI.lua after pfUI loads).
function CleveRoids.DoPfCast(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = parts[i]
        -- If conditionals are present but no explicit @unit, inject the pfUI-resolved unit so
        -- all conditionals ([help], [nodebuff:X], etc.) evaluate against the same unit pfUI
        -- would cast on, and the final CastSpellByName gets the correct unit token.
        if string.find(v, "%[") and not string.find(v, "@") then
            local unit = ResolvePfCastUnit()
            if unit then
                v = string.gsub(v, "%[", "[@" .. unit .. ",", 1)
            end
        end
        if CleveRoids.DoWithConditionals(v, CleveRoids.Hooks.PFCAST_SlashCmd, CleveRoids.FixEmptyTarget, not CleveRoids.hasSuperwow, CastSpellByName) then
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

-- PERFORMANCE: Module-level pet cast action to avoid closure allocation per call
local function _petCastAction(spellName)
    local petSpell = CleveRoids.GetPetSpell(spellName)
    if petSpell and petSpell.slot then
        CastPetAction(petSpell.slot)
        return true
    end
    return false
end

function CleveRoids.DoCastPet(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = parts[i]
        if CleveRoids.DoWithConditionals(v, _petCastAction, CleveRoids.FixEmptyTarget, false, _petCastAction) then
            return true
        end
    end
    return false
end

function CleveRoids.DoTarget(msg)
    -- Check macro stop flags
    if CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag then
        return false
    end

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

    -- Save original target GUID for potential restoration (SuperWoW returns GUID as 2nd value)
    local _, originalTargetGuid = UnitExists("target")

    -- Handle [multiscan:priority] - use ResolveMultiscanTarget for enemy scanning
    -- ResolveMultiscanTarget handles its own target save/restore internally
    if conditionals.multiscan then
        local scanResult = CleveRoids.ResolveMultiscanTarget(conditionals, conditionals.target)
        if scanResult then
            TargetUnit(scanResult)
            return true
        end
        -- No match found - restore original target if scanning changed it
        if originalTargetGuid and UnitExists(originalTargetGuid) then
            TargetUnit(originalTargetGuid)
        elseif not originalTargetGuid then
            ClearTarget()
        end
        return false
    end

    -- Track if an explicit target was specified via @unit syntax
    local explicitTarget = conditionals.target

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

        -- Resolve named raid marks (skull/cross/etc.) and mark1-mark8 to native mark# unit tokens
        local resolvedMark = CleveRoids.ResolveRaidMarkUnit(unitTok)
        if resolvedMark then unitTok = resolvedMark end

        if unitTok and UnitExists(unitTok) and IsGuidValid(unitTok, conditionals) then
            TargetUnit(unitTok)
            return true
        end

        -- If an explicit target was specified via @unit syntax but doesn't exist or isn't valid,
        -- return false instead of falling through to candidate search.
        -- This ensures "/target [@mouseover,harm,alive]" does nothing when mouse is over empty ground.
        if explicitTarget then
            return false
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

    -- UnitXP 3D enemy scanning: cycles through enemies in world space (no nameplate required)
    -- This is the most powerful scan - finds enemies by line of sight and distance
    -- Always enabled unless explicitly looking for friendlies only ([help] without [harm])
    -- UnitXP only finds enemies, so this is safe for any /target with conditionals
    local wantsFriendlyOnly = wantsHelp and not wantsHarm
    if not wantsFriendlyOnly and CleveRoids.hasUnitXP then
        -- Try nearestEnemy first - most common case and most efficient
        local found = UnitXP("target", "nearestEnemy")
        if found and UnitExists("target") and IsGuidValid("target", conditionals) then
            return true
        end

        -- Determine scan mode: use distance-priority for melee conditionals
        local wantsMelee = conditionals.meleerange or conditionals.nomeleerange
        local scanMode = wantsMelee and "nextEnemyConsideringDistance" or "nextEnemyInCycle"

        local seenGuids = {}
        local firstGuid = nil
        local maxIterations = 50  -- Safety limit

        for i = 1, maxIterations do
            found = UnitXP("target", scanMode)
            if not found then break end

            local _, currentGuid = UnitExists("target")
            if not currentGuid then break end

            -- Check if we've cycled back to start
            if firstGuid == nil then
                firstGuid = currentGuid
            elseif currentGuid == firstGuid then
                break  -- Completed full cycle
            end

            -- Skip already-seen targets
            if not seenGuids[currentGuid] then
                seenGuids[currentGuid] = true

                -- Test this target against all conditionals
                if IsGuidValid("target", conditionals) then
                    return true  -- Found matching target
                end
            end
        end

        -- No match found via UnitXP scan - restore original target if we had one
        if originalTargetGuid and UnitExists(originalTargetGuid) then
            TargetUnit(originalTargetGuid)
        elseif not originalTargetGuid then
            ClearTarget()
        end
    end

    return true
end

-- Attempts to attack a unit by a set of conditionals
-- msg: The raw message intercepted from a /petattack command
function CleveRoids.DoPetAction(action, msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], action, CleveRoids.FixEmptyTarget, true, action) then
            return true
        end
    end
    return false
end

-- PERFORMANCE: Module-level action to avoid closure allocation per call
local function _startAttackAction()
    if not UnitExists("target") or UnitIsDead("target") then TargetNearestEnemy() end
    -- Check both event-based flag AND action bar state for reliable detection
    local isAttacking = CleveRoids.CurrentSpell.autoAttack
    if not isAttacking then
        -- Fallback: check action bar state via IsCurrentAction
        local slot = CleveRoids.GetProxyActionSlot(CleveRoids.Localized.Attack)
        if slot and IsCurrentAction(slot) then
            CleveRoids.CurrentSpell.autoAttack = true
            isAttacking = true
        end
    end
    if not isAttacking and not CleveRoids.CurrentSpell.autoAttackLock and UnitExists("target") and UnitCanAttack("player", "target") then
        CleveRoids.CurrentSpell.autoAttackLock = true
        CleveRoids.autoAttackLockElapsed = GetTime()
        AttackTarget()
        -- FIX: Immediately set autoAttack flag so subsequent macro lines know attack started
        -- Don't wait for PLAYER_ENTER_COMBAT event which has a delay
        CleveRoids.CurrentSpell.autoAttack = true
        -- FIX: Queue icon update so action bars reflect the new state
        if CleveRoidMacros and CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

-- Attempts to conditionally start an attack. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStartAttack(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        -- We pass 'nil' for the hook, so DoWithConditionals does nothing if it fails to parse conditionals.
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _startAttackAction) then
            return true
        end
    end
    return false
end

-- PERFORMANCE: Module-level actions to avoid closure allocation per call
local function _stopAttackAction()
    if CleveRoids.CurrentSpell.autoAttack and UnitExists("target") then
        AttackTarget()
        CleveRoids.CurrentSpell.autoAttack = false
    end
end

local function _stopCastingAction()
    SpellStopCasting()
end

local function _clearTargetAction()
    ClearTarget()
end

-- Attempts to conditionally stop an attack. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStopAttack(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _stopAttackAction) then
            return true
        end
    end
    return false
end

-- Attempts to conditionally stop casting. Returns false if no conditionals are found.
function CleveRoids.DoConditionalStopCasting(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _stopCastingAction) then
            return true
        end
    end
    return false
end

-- Attempts to conditionally clear target. Returns false if no conditionals are found.
function CleveRoids.DoConditionalClearTarget(msg)
    if not string.find(msg, "%[") then return false end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, CleveRoids.FixEmptyTarget, false, _clearTargetAction) then
            return true
        end
    end
    return false
end


-- Attempts to use or equip an item by a set of conditionals
-- Also checks if a condition is a spell so that you can mix item and spell use
-- msg: The raw message intercepted from a /use or /equip command
function CleveRoids.DoUse(msg)
    -- Check macro stop flags
    if CleveRoids.stopMacroFlag or CleveRoids.skipMacroFlag then
        return false
    end

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

        -- Try to interpret as item ID (numbers > 19)
        -- v2.18+: Use FindPlayerItemSlot directly for item IDs (no name resolution needed)
        if slotId and slotId > 19 then
            local API = CleveRoids.NampowerAPI
            -- v2.18+: Native lookup can find item directly by ID
            if API and API.features and API.features.hasFindPlayerItemSlot then
                local itemInfo = API.FindItemFast(slotId)
                if itemInfo then
                    ClearCursor()
                    if itemInfo.inventoryID then
                        if CleveRoids.equipDebugLog then
                            CleveRoids.Print("|cff888888[UseLog] /use " .. slotId .. " via UseInventoryItem(" .. itemInfo.inventoryID .. ") [v2.18 ID lookup]|r")
                        end
                        UseInventoryItem(itemInfo.inventoryID)
                        return
                    elseif itemInfo.bagID and itemInfo.slot then
                        if CleveRoids.equipDebugLog then
                            CleveRoids.Print("|cff888888[UseLog] /use " .. slotId .. " via UseContainerItem(" .. itemInfo.bagID .. "," .. itemInfo.slot .. ") [v2.18 ID lookup]|r")
                        end
                        UseContainerItem(itemInfo.bagID, itemInfo.slot)
                        return
                    end
                end
                -- Item not found by ID - fail
                if CleveRoids.equipDebugLog then
                    CleveRoids.Print("|cffff8800[UseLog] Item ID " .. slotId .. " not found in inventory [v2.18]|r")
                end
                return
            end

            -- Fallback: Resolve item ID to name for legacy lookup
            local itemName = nil
            if API and API.GetItemName then
                itemName = API.GetItemName(slotId)
            end
            -- Fall back to GetItemInfo
            if not itemName and GetItemInfo then
                itemName = GetItemInfo(slotId)
            end
            if itemName then
                if CleveRoids.equipDebugLog then
                    CleveRoids.Print("|cff888888[UseLog] Resolved item ID " .. slotId .. " to '" .. itemName .. "'|r")
                end
                msg = itemName  -- Replace ID with name for subsequent lookups
            else
                if CleveRoids.equipDebugLog then
                    CleveRoids.Print("|cffff8800[UseLog] Could not resolve item ID " .. slotId .. " - item not in cache|r")
                end
                -- Item not in client cache - can't resolve without seeing it first
                return
            end
        end

        -- v2.18+: Use native fast lookup (much faster than Lua cache + scan)
        local API = CleveRoids.NampowerAPI
        if API and API.features and API.features.hasFindPlayerItemSlot then
            local itemInfo = API.FindItemFast(msg)
            if itemInfo then
                ClearCursor()
                if itemInfo.inventoryID then
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via UseInventoryItem(" .. itemInfo.inventoryID .. ") [v2.18 native]|r")
                    end
                    UseInventoryItem(itemInfo.inventoryID)
                    return
                elseif itemInfo.bagID and itemInfo.slot then
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via UseContainerItem(" .. itemInfo.bagID .. "," .. itemInfo.slot .. ") [v2.18 native]|r")
                    end
                    UseContainerItem(itemInfo.bagID, itemInfo.slot)
                    return
                end
            end
            -- v2.18 lookup didn't find item - fall through to legacy path
            -- (might be partial match or different case that native doesn't handle)
        end

        -- PERFORMANCE: Try cache lookup first (O(1) instead of O(n) scan)
        -- IMPORTANT: Validate cache hits to prevent stale data during combat
        -- (IndexItems() is skipped during combat, so cache may have old bag/slot locations)
        local location = CleveRoids.FindItemLocation(msg)
        if location then
            local cacheValid = false
            local qname = string_lower(msg)

            if location.type == "inventory" then
                -- Validate: check if this slot actually contains the item we want
                local link = GetInventoryItemLink("player", location.inventoryID)
                if link then
                    local _, _, nm = string_find(link, "|h%[(.-)%]|h")
                    if nm and string_lower(nm) == qname then
                        cacheValid = true
                    end
                end
            else
                -- Validate: check if this bag slot actually contains the item we want
                local link = GetContainerItemLink(location.bag, location.slot)
                if link then
                    local _, _, nm = string_find(link, "|h%[(.-)%]|h")
                    if nm and string_lower(nm) == qname then
                        cacheValid = true
                    end
                end
            end

            if cacheValid then
                ClearCursor()
                if location.type == "inventory" then
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via UseInventoryItem(" .. location.inventoryID .. ") [cached]|r")
                    end
                    UseInventoryItem(location.inventoryID)
                else
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via UseContainerItem(" .. location.bag .. "," .. location.slot .. ") [cached]|r")
                    end
                    UseContainerItem(location.bag, location.slot)
                end
                return
            elseif CleveRoids.equipDebugLog then
                CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " - cache STALE, falling back to scan|r")
            end
        end

        -- Slow path fallback: full scan for substring matches or cache miss
        local qname = string_lower(msg)

        -- Search equipped inventory slots first (for trinkets, etc.)
        for slot = 0, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local _, _, nm = string_find(link, "|h%[(.-)%]|h")
                if nm and string_lower(nm) == qname then
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via UseInventoryItem(" .. slot .. ")|r")
                    end
                    ClearCursor()
                    UseInventoryItem(slot)
                    return
                end
            end
        end

        -- Then search bags
        for bag = 0, 4 do
            local numSlots = GetContainerNumSlots(bag) or 0
            for bagSlot = 1, numSlots do
                local link = GetContainerItemLink(bag, bagSlot)
                if link then
                    local _, _, nm = string_find(link, "|h%[(.-)%]|h")
                    if nm and string_lower(nm) == qname then
                        if CleveRoids.equipDebugLog then
                            CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " via UseContainerItem(" .. bag .. "," .. bagSlot .. ")|r")
                        end
                        ClearCursor()
                        UseContainerItem(bag, bagSlot)
                        return
                    end
                end
            end
        end

        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cff888888[UseLog] /use " .. msg .. " - not found in equipped slots or bags|r")
        end
    end

    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], action, CleveRoids.FixEmptyTarget, false, action) then
            -- If /firstaction was used, stop macro evaluation after first successful use
            if CleveRoids.stopOnCastFlag then
                CleveRoids.stopMacroFlag = true
            end
            return true
        end
    end
    return false
end

-- Find an item in bags by name (ignoring equipped items)
-- Used to prefer bag copies over swapping from paired equipped slots
-- (e.g., dual-wielding the same weapon with /equipmh + /equipoh)
local function FindItemInBagsByName(itemName)
    if not itemName then return nil, nil end
    local lowerName = string_lower(itemName)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, name = string_find(link, "|h%[(.-)%]|h")
                if name and string_lower(name) == lowerName then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

function CleveRoids.EquipBagItem(msg, slotOrOffhand)
    if CleveRoids.equipDebugLog then
        CleveRoids.Print("|cff00ffff[EquipLog] EquipBagItem called: '" .. tostring(msg) .. "' slot=" .. tostring(slotOrOffhand) .. "|r")
    end

    if CleveRoids.equipInProgress then
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cffff0000[EquipLog] Equip already in progress, skipping|r")
        end
        return false
    end

    -- Accept slot number directly, or boolean for backward compatibility (false=16/MH, true=17/OH)
    local invslot
    if type(slotOrOffhand) == "number" then
        invslot = slotOrOffhand
    else
        invslot = slotOrOffhand and 17 or 16
    end
    local API = CleveRoids.NampowerAPI

    -- v2.18+: Use native fast lookup for item ID or name
    -- Guard against API being a function instead of table (addon conflict protection)
    if type(API) == "table" and type(API.features) == "table" and API.features.hasFindPlayerItemSlot then
        local searchTerm = msg
        local itemId = tonumber(msg)

        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cff888888[EquipLog] Searching for '" .. tostring(searchTerm) .. "' (slot " .. invslot .. ")|r")
        end

        -- Check if already equipped in target slot
        if API.IsItemInSlot(searchTerm, invslot) then
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cff00ff00[EquipLog] '" .. tostring(searchTerm) .. "' already in slot " .. invslot .. "|r")
            end
            return true
        end

        -- Find the item (works with both ID and name)
        local itemInfo = API.FindItemFast(searchTerm)
        if CleveRoids.equipDebugLog then
            if itemInfo then
                CleveRoids.Print("|cff888888[EquipLog] FindItemFast found: invID=" .. tostring(itemInfo.inventoryID) .. " bag=" .. tostring(itemInfo.bagID) .. " slot=" .. tostring(itemInfo.slot) .. "|r")
            else
                CleveRoids.Print("|cffff8800[EquipLog] FindItemFast returned nil|r")
            end
        end
        if itemInfo then
            -- Already equipped in different slot - need to swap
            if itemInfo.inventoryID then
                if itemInfo.inventoryID == invslot then
                    return true  -- Already in correct slot
                end
                -- Before swapping from another equipped slot, check bags for another copy
                -- This handles dual-wielding the same weapon (e.g., /equipmh Scimitar + /equipoh Scimitar)
                local bagCopyBag, bagCopySlot = FindItemInBagsByName(itemInfo.name or searchTerm)
                if bagCopyBag then
                    ClearCursor()
                    PickupContainerItem(bagCopyBag, bagCopySlot)
                    if CursorHasItem and CursorHasItem() then
                        EquipCursorItem(invslot)
                        ClearCursor()
                        if CleveRoids.equipDebugLog then
                            CleveRoids.Print("|cff00ff00[EquipLog] Equipped bag copy of '" .. tostring(msg) .. "' from bag " .. bagCopyBag .. " slot " .. bagCopySlot .. " (preferred over swap)|r")
                        end
                        return true
                    end
                end
                -- No bag copy found - swap from equipped slot
                ClearCursor()
                PickupInventoryItem(itemInfo.inventoryID)
                if CursorHasItem and CursorHasItem() then
                    EquipCursorItem(invslot)
                    ClearCursor()
                    return true
                end
            elseif itemInfo.bagID and itemInfo.slot then
                -- In bag - equip to target slot
                ClearCursor()
                PickupContainerItem(itemInfo.bagID, itemInfo.slot)
                if CursorHasItem and CursorHasItem() then
                    EquipCursorItem(invslot)
                    ClearCursor()
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff00ff00[EquipLog] Equipped '" .. tostring(msg) .. "' from bag " .. itemInfo.bagID .. " slot " .. itemInfo.slot .. "|r")
                    end
                    return true
                end
            end
        end

        -- Item not found via v2.18 lookup - fall through to legacy path
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cffff8800[EquipLog] Item '" .. tostring(msg) .. "' not found via v2.18 FindPlayerItemSlot, trying legacy fallback|r")
            -- Debug: Try direct FindPlayerItemSlot call
            if FindPlayerItemSlot then
                local bag, slot = FindPlayerItemSlot(msg)
                CleveRoids.Print("|cff888888[EquipLog] Direct FindPlayerItemSlot('" .. msg .. "') = bag:" .. tostring(bag) .. " slot:" .. tostring(slot) .. "|r")
            end
        end
    end

    -- Fallback for older Nampower versions
    -- Try to interpret as item ID (numbers > 19)
    local itemId = tonumber(msg)
    if itemId and itemId > 19 then
        local itemName = nil
        if API and API.GetItemName then
            itemName = API.GetItemName(itemId)
        end
        if not itemName and GetItemInfo then
            itemName = GetItemInfo(itemId)
        end
        if itemName then
            msg = itemName
        else
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cffff8800[EquipLog] Can't resolve item ID " .. tostring(itemId) .. "|r")
            end
            return false  -- Can't resolve item ID
        end
    end

    -- PERFORMANCE: Fast check if already equipped (single function call)
    if CleveRoids.IsItemEquipped and CleveRoids.IsItemEquipped(msg, invslot) then
        return true
    end

    -- Note what's currently in the target slot so we can invalidate its cache
    local oldSlotLink = GetInventoryItemLink("player", invslot)
    local oldSlotName = nil
    if oldSlotLink then
        local _, _, name = string_find(oldSlotLink, "|h%[(.-)%]|h")
        oldSlotName = name
    end

    -- Helper to invalidate displaced item's cache
    local function InvalidateDisplacedItem()
        if oldSlotName and CleveRoids.Items then
            CleveRoids.Items[oldSlotName] = nil
            CleveRoids.Items[string_lower(oldSlotName)] = nil
        end
    end

    -- Check if item is already equipped in the paired slot (swap case)
    -- EquipItemByName doesn't handle swapping equipped items, so we must do it manually
    -- Paired slots: trinkets (13<->14), weapons (16<->17), rings (11<->12)
    -- BUT: check bags first for another copy (e.g., dual-wielding same weapon)
    local pairedSlots = {[13] = 14, [14] = 13, [16] = 17, [17] = 16, [11] = 12, [12] = 11}
    local checkSlot = pairedSlots[invslot]
    if checkSlot then
        local link = GetInventoryItemLink("player", checkSlot)
        if link then
            local _, _, slotItemName = string_find(link, "|h%[(.-)%]|h")
            if slotItemName and string_lower(slotItemName) == string_lower(msg) then
                -- Item found in paired slot - but prefer a bag copy if one exists
                local bagCopyBag, bagCopySlot = FindItemInBagsByName(msg)
                if bagCopyBag then
                    -- Bag copy available - equip from bag instead of swapping
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff00ffff[EquipLog] Found bag copy, equipping from bag " .. bagCopyBag .. " slot " .. bagCopySlot .. " instead of swapping from slot " .. checkSlot .. "|r")
                    end
                    ClearCursor()
                    PickupContainerItem(bagCopyBag, bagCopySlot)
                    if CursorHasItem and CursorHasItem() then
                        EquipCursorItem(invslot)
                        ClearCursor()
                        if CleveRoids.Items then
                            CleveRoids.Items[msg] = nil
                            CleveRoids.Items[string_lower(msg)] = nil
                        end
                        InvalidateDisplacedItem()
                        return true
                    end
                    ClearCursor()
                else
                    -- No bag copy - swap from paired slot
                    if CleveRoids.equipDebugLog then
                        CleveRoids.Print("|cff00ffff[EquipLog] Swapping from slot " .. checkSlot .. " to slot " .. invslot .. "|r")
                    end
                    ClearCursor()
                    PickupInventoryItem(checkSlot)
                    if CursorHasItem and CursorHasItem() then
                        EquipCursorItem(invslot)
                        ClearCursor()
                        if CleveRoids.Items then
                            CleveRoids.Items[msg] = nil
                            CleveRoids.Items[string_lower(msg)] = nil
                        end
                        InvalidateDisplacedItem()
                        return true
                    end
                    ClearCursor()
                end
            end
        end
    end

    -- PERFORMANCE: Try EquipItemByName for bag items (fast path)
    -- This is the fastest path - no item lookup, no cursor operations
    if EquipItemByName then
        local ok = pcall(EquipItemByName, msg, invslot)
        if ok then
            -- Verify the item actually landed in the target slot
            -- EquipItemByName may silently no-op for same-named items in paired slots
            -- (e.g., dual-wielding Scimitar: MH copy found first, "equipped" to same slot)
            local newLink = GetInventoryItemLink("player", invslot)
            if newLink then
                local _, _, newName = string_find(newLink, "|h%[(.-)%]|h")
                if newName and string_lower(newName) == string_lower(msg) then
                    if CleveRoids.Items then
                        CleveRoids.Items[msg] = nil
                        CleveRoids.Items[string_lower(msg)] = nil
                    end
                    InvalidateDisplacedItem()
                    return true
                end
            end
            -- Verification failed - EquipItemByName didn't place item in target slot
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cffff8800[EquipLog] EquipItemByName('" .. msg .. "', " .. invslot .. ") succeeded but item not in target slot, trying fallback|r")
            end
        end
    end

    -- PERFORMANCE: Use fast lookup first, fall back to full scan
    -- Full scan is now optimized with GetNameFromLink() instead of GetItemInfo()
    local item = CleveRoids.GetItemFast and CleveRoids.GetItemFast(msg)
    if not item then
        -- Try quick targeted scan (stops when found)
        item = CleveRoids.FindItemQuick and CleveRoids.FindItemQuick(msg)
    end
    if not item then
        -- Full scan fallback (now optimized, safe during combat)
        item = CleveRoids.GetItem(msg)
    end

    if not item or not item.name then
        if CleveRoids.equipDebugLog then
            CleveRoids.Print("|cffff8800[EquipLog] Item '" .. tostring(msg) .. "' not found in bags or equipped|r")
        end
        return false
    end

    -- Already equipped check (by item ID from lookup)
    if item.inventoryID == invslot then
        return true
    end

    if not item.bagID and not item.inventoryID then
        return false
    end

    -- Try EquipItemByName with resolved name (in case msg was partial/different case)
    if item.name and EquipItemByName and item.name ~= msg then
        local ok = pcall(EquipItemByName, item.name, invslot)
        if ok then
            -- Verify the item actually landed in the target slot (same guard as above)
            local newLink = GetInventoryItemLink("player", invslot)
            if newLink then
                local _, _, newName = string_find(newLink, "|h%[(.-)%]|h")
                if newName and string_lower(newName) == string_lower(item.name) then
                    if CleveRoids.Items then
                        CleveRoids.Items[item.name] = nil
                        CleveRoids.Items[string_lower(item.name)] = nil
                    end
                    InvalidateDisplacedItem()
                    return true
                end
            end
            -- Verification failed - fall through to manual cursor-based equip
            if CleveRoids.equipDebugLog then
                CleveRoids.Print("|cffff8800[EquipLog] EquipItemByName('" .. item.name .. "', " .. invslot .. ") succeeded but item not in target slot, trying manual fallback|r")
            end
        end
    end

    -- Fallback: Manual pickup and equip
    CleveRoids.equipInProgress = true

    -- PERFORMANCE: Single cursor check at start
    if CursorHasItem and CursorHasItem() then
        ClearCursor()
    end

    local pickupSuccess = false
    if item.bagID and item.slot then
        PickupContainerItem(item.bagID, item.slot)
        pickupSuccess = CursorHasItem and CursorHasItem()
    elseif item.inventoryID then
        PickupInventoryItem(item.inventoryID)
        pickupSuccess = CursorHasItem and CursorHasItem()
    end

    if not pickupSuccess then
        ClearCursor()
        CleveRoids.equipInProgress = false
        return false
    end

    EquipCursorItem(invslot)
    ClearCursor()

    if CleveRoids.Items and item.name then
        CleveRoids.Items[item.name] = nil
        CleveRoids.Items[string_lower(item.name)] = nil
    end
    InvalidateDisplacedItem()
    CleveRoids.equipInProgress = false
    return true
end

-- PERFORMANCE: Module-level actions to avoid closure allocation per call
local function _equipMainhandAction(msg)
    return CleveRoids.EquipBagItem(msg, false)
end

local function _equipOffhandAction(msg)
    return CleveRoids.EquipBagItem(msg, true)
end

local function _equipTrinket1Action(msg)
    return CleveRoids.EquipBagItem(msg, 13)
end

local function _equipTrinket2Action(msg)
    return CleveRoids.EquipBagItem(msg, 14)
end

local function _equipRing1Action(msg)
    return CleveRoids.EquipBagItem(msg, 11)
end

local function _equipRing2Action(msg)
    return CleveRoids.EquipBagItem(msg, 12)
end

local function _unshiftAction()
    local currentShapeshiftIndex = CleveRoids.GetCurrentShapeshiftIndex()
    if currentShapeshiftIndex ~= 0 then
        CastShapeshiftForm(currentShapeshiftIndex)
    end
end

function CleveRoids.DoEquipMainhand(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipMainhandAction, CleveRoids.FixEmptyTarget, false, _equipMainhandAction) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipOffhand(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipOffhandAction, CleveRoids.FixEmptyTarget, false, _equipOffhandAction) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipTrinket1(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipTrinket1Action, CleveRoids.FixEmptyTarget, false, _equipTrinket1Action) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipTrinket2(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipTrinket2Action, CleveRoids.FixEmptyTarget, false, _equipTrinket2Action) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipRing1(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipRing1Action, CleveRoids.FixEmptyTarget, false, _equipRing1Action) then
            return true
        end
    end
    return false
end

function CleveRoids.DoEquipRing2(msg)
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        local v = string.gsub(parts[i], "^%?", "")
        if CleveRoids.DoWithConditionals(v, _equipRing2Action, CleveRoids.FixEmptyTarget, false, _equipRing2Action) then
            return true
        end
    end
    return false
end

function CleveRoids.DoUnshift(msg)
    local handled
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(msg)
    for i = 1, table.getn(parts) do
        handled = false
        if CleveRoids.DoWithConditionals(parts[i], _unshiftAction, CleveRoids.FixEmptyTarget, false, _unshiftAction) then
            handled = true
            break
        end
    end

    if handled == nil then
        _unshiftAction()
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

-- Attempts to stop macro (stops ALL remaining lines including parent macros)
function CleveRoids.DoStopMacro(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, nil, not CleveRoids.hasSuperwow, "STOPMACRO") then
            return true
        end
    end
    return false
end

-- Attempts to skip remaining lines in current submacro ONLY (returns to parent)
function CleveRoids.DoSkipMacro(msg)
    -- PERFORMANCE: Use numeric iteration to avoid pairs() iterator allocation
    local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
    for i = 1, table.getn(parts) do
        if CleveRoids.DoWithConditionals(parts[i], nil, nil, not CleveRoids.hasSuperwow, "SKIPMACRO") then
            return true
        end
    end
    return false
end

-- Enables "stop on first successful cast" mode for the rest of the macro
-- When set, successful /cast or /use commands will set stopMacroFlag automatically
-- This allows priority-based macro evaluation: first matching cast wins
-- Example usage:
--   /firstaction
--   /cast [myrawpower:>48] Shred
--   /cast [myrawpower:>40] Claw
-- In this case, if Shred casts, Claw will NOT be queued
function CleveRoids.DoFirstAction(msg)
    -- Check if there are conditionals
    if msg and CleveRoids.Trim(msg) ~= "" then
        -- Has conditionals - use DoWithConditionals to evaluate them
        local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
        for i = 1, table.getn(parts) do
            if CleveRoids.DoWithConditionals(parts[i], nil, nil, not CleveRoids.hasSuperwow, "FIRSTACTION") then
                return true
            end
        end
        return false
    else
        -- No conditionals - just set the flag
        CleveRoids.stopOnCastFlag = true
        return true
    end
end

-- Disables "stop on first successful cast" mode, re-enabling multi-queue behavior
-- Use this to restore normal evaluation after /firstaction
-- Example usage:
--   /firstaction
--   /cast [myrawpower:>48] Shred      -- Priority section
--   /cast [myrawpower:>40] Claw
--   /nofirstaction
--   /cast Tiger's Fury                -- Can queue alongside above
--   /startattack
function CleveRoids.DoNoFirstAction(msg)
    -- Check if there are conditionals
    if msg and CleveRoids.Trim(msg) ~= "" then
        -- Has conditionals - use DoWithConditionals to evaluate them
        local parts = CleveRoids.splitStringIgnoringQuotes(CleveRoids.Trim(msg))
        for i = 1, table.getn(parts) do
            if CleveRoids.DoWithConditionals(parts[i], nil, nil, not CleveRoids.hasSuperwow, "NOFIRSTACTION") then
                return true
            end
        end
        return false
    else
        -- No conditionals - clear the flags
        -- Capture stopOnCastFlag BEFORE clearing it to know if firstaction was active
        local wasFirstActionActive = CleveRoids.stopOnCastFlag
        CleveRoids.stopOnCastFlag = false
        -- Also clear stopMacroFlag if it was set by the firstaction mechanism
        -- (stopOnCastFlag being true means firstaction mode caused stopMacroFlag to be set)
        if wasFirstActionActive and CleveRoids.stopMacroFlag then
            CleveRoids.stopMacroFlag = false
        end
        return true
    end
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

  -- Debug: Show sequence state
  if CleveRoids.debug then
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "|cff00ffff[Sequence]|r Step %d/%d: '%s'",
      sequence.index, table.getn(sequence.list), active.action
    ))
  end

  -- Check for stop steps - does nothing, allows macro to fall through
  -- Sequence stays on this step until a reset condition fires (target/combat/time/modifier)
  -- Usage: /castsequence reset=target Sunder Armor, nil
  local actionLower = string.lower(CleveRoids.Trim(active.action))
  if actionLower == "nil" or actionLower == "null" or actionLower == "pass" or actionLower == "noop" then
    sequence.status = 0
    sequence.lastUpdate = GetTime()
    if CleveRoids.debug then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Sequence]|r Hit stop step, falling through")
    end
    -- Don't cast anything, just return - allows macro to continue to next line
    return
  end

  sequence.status     = 0
  sequence.lastUpdate = GetTime()
  sequence.expires    = 0

  -- Capture target GUID for reset=target (only resets on NEW target, not same target)
  if sequence.reset and sequence.reset.target and UnitExists("target") then
    local _, targetGuid = UnitExists("target")
    sequence.lastTargetGuid = targetGuid
  end

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
    -- Check specifically for "(Rank" to allow spells like "Faerie Fire (Feral)"
    -- to still get their rank appended automatically
    if not string.find(msg, "%(Rank") then
      local sp = CleveRoids.GetSpell(msg)
      local r  = (sp and sp.rank) or (sp and sp.highest and sp.highest.rank)
      if r and r ~= "" then msg = msg .. "(" .. r .. ")" end
    end
    -- Let Nampower DLL handle queuing natively via its CastSpellByName hook
    CastSpellByName(msg)
    return true
  end

  local attempted = false
  if not conds then
    attempted = cast_by_name(resolvedText or active.action)
  else
    local final = CleveRoids.DoWithConditionals(actionText, nil, CleveRoids.FixEmptyTarget, false, CastSpellByName)
    if final then
      -- DoWithConditionals returns true (boolean) when it already cast the spell,
      -- or a string spell name when conditionals were skipped. Only call cast_by_name
      -- if we got a string back (spell wasn't cast yet).
      if type(final) == "string" then
        attempted = cast_by_name(final)
      else
        attempted = true  -- Spell was already cast inside DoWithConditionals
      end
    end
  end

  if not attempted then
    CleveRoids.currentSequence = prevSeq
  end
end

CleveRoids.DoConditionalCancelAura = function(msg)
  -- Check stopmacro flag
  if CleveRoids.stopMacroFlag then return false end

  local s = CleveRoids.Trim(msg or "")
  if s == "" then return false end

  -- No conditionals? cancel immediately.
  if not string.find(s, "%[") then
    return CleveRoids.CancelAura(s)
  end

  -- Has conditionals? Let the framework evaluate them, then run CancelAura.
  return CleveRoids.DoWithConditionals(s, nil, CleveRoids.FixEmptyTarget, false, CleveRoids.CancelAura) or false
end

-- PERFORMANCE: Separate periodic cleanup timer (runs every 5 seconds instead of every frame)
CleveRoids.lastCleanupTime = 0
CleveRoids.CLEANUP_INTERVAL = 5  -- Run cleanup every 5 seconds

-- PERFORMANCE: Upvalues for OnUpdate hot path
local GetTime = GetTime
local UnitAffectingCombat = UnitAffectingCombat
local pairs = pairs

function CleveRoids.OnUpdate(self)
    -- Prevent SuperWoW API calls during shutdown (crash prevention)
    if CleveRoids.isShuttingDown then return end

    -- Clear macro stop flags at the start of each frame
    -- This ensures /stopmacro and /skipmacro only affect commands in the same frame (same macro execution)
    -- Without SuperMacro, this is necessary because we can't hook into macro line execution
    if CleveRoids.stopMacroFlag then
        CleveRoids.stopMacroFlag = false
    end
    if CleveRoids.skipMacroFlag then
        CleveRoids.skipMacroFlag = false
    end
    if CleveRoids.stopOnCastFlag then
        CleveRoids.stopOnCastFlag = false
    end

    -- PERFORMANCE: Single GetTime() call per frame
    local time = GetTime()

    -- PERFORMANCE: Early exit if not ready (before any other checks)
    if not CleveRoids.ready then
        -- Handle initialization timer only when not ready
        if CleveRoids.initializationTimer and time >= CleveRoids.initializationTimer then
            CleveRoids.initializationTimer = nil
            CleveRoids.IndexItems()

            -- FIX: Set ready=true BEFORE IndexActionBars so GetAction() works
            -- IndexActionSlot calls GetAction() which has an early-exit if ready=false,
            -- preventing TestForActiveAction from populating actions.active
            CleveRoids.ready = true

            -- FIX: Suppress action event handlers during initial indexing
            -- IndexActionBars sends ACTIONBAR_SLOT_CHANGED for each slot which triggers
            -- addon handlers (pfUI, Bongos). 120 rapid calls can cause issues.
            CleveRoids._suppressActionHandlers = true
            CleveRoids.IndexActionBars()
            CleveRoids._suppressActionHandlers = false

            CleveRoids.TestForAllActiveActions()
            CleveRoids.lastUpdate = time

            -- FIX: Force refresh ALL Blizzard action buttons after initialization
            -- Blizzard queries IsUsableAction during login before we're ready,
            -- caching the wrong state. We must force a re-query for all buttons.
            -- SKIP for pfUI users - pfUI handles its own button updates and this
            -- would trigger 120 rapid handler calls causing issues.
            if not (pfUI and pfUI.bars) then
                for slot = 1, 120 do
                    if CleveRoids.Actions[slot] then
                        CleveRoids.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
                    end
                end
            end
        end
        return
    end

    -- =========================================================================
    -- CONTINUOUS POSITION TRACKING (for [moving] fallback without MonkeySpeed)
    -- =========================================================================
    -- Track player position at ~100 Hz with 4-sample circular buffer for snappy movement detection.
    -- Matches MonkeySpeed's 0.01s detection interval for similar responsiveness.
    -- PERFORMANCE: Pre-allocated circular buffer eliminates ~100 table allocs/sec and table.remove shifting.
    local posTrackInterval = 0.01  -- 10ms between position samples (100 Hz, matches MonkeySpeed)
    local lastPosTime = CleveRoids._positionTrackTime or 0

    if (time - lastPosTime) >= posTrackInterval then
        CleveRoids._positionTrackTime = time

        if UnitPosition then
            local x, y = UnitPosition("player")
            if x and y then
                -- Initialize circular buffer if needed (pre-allocate 4 entry tables)
                local history = CleveRoids._positionHistory
                if not history then
                    history = {
                        { x = 0, y = 0, time = 0 },
                        { x = 0, y = 0, time = 0 },
                        { x = 0, y = 0, time = 0 },
                        { x = 0, y = 0, time = 0 },
                    }
                    CleveRoids._positionHistory = history
                    CleveRoids._posHistoryIndex = 0
                    CleveRoids._posHistoryCount = 0
                end

                -- Advance circular index (1-based, wraps at 4)
                local idx = math.mod(CleveRoids._posHistoryIndex, 4) + 1
                CleveRoids._posHistoryIndex = idx

                -- Reuse existing entry (zero allocation)
                local entry = history[idx]
                entry.x = x
                entry.y = y
                entry.time = time

                -- Track how many samples we have (caps at 4)
                if CleveRoids._posHistoryCount < 4 then
                    CleveRoids._posHistoryCount = CleveRoids._posHistoryCount + 1
                end

                -- Maintain legacy vars for any code that uses them directly
                if CleveRoids._posHistoryCount >= 2 then
                    local prevIdx = math.mod((idx - 2 + 4), 4) + 1
                    CleveRoids._previousPlayerPos = history[prevIdx]
                    CleveRoids._currentPlayerPos = entry
                end
            end
        end
    end

    -- PERFORMANCE: Delayed WDB warmup after login (ensures GetItemInfo works after WDB clear)
    if CleveRoids.wdbWarmupTime and time >= CleveRoids.wdbWarmupTime then
        CleveRoids.wdbWarmupTime = nil
        CleveRoids.DoWDBWarmup()
    end

    -- PERFORMANCE: Cache refresh rate calculation (avoid per-frame division)
    local refreshRate = CleveRoids.cachedRefreshRate
    if not refreshRate then
        refreshRate = 1 / (CleveRoidMacros.refresh or 5)
        CleveRoids.cachedRefreshRate = refreshRate
    end

    -- PERFORMANCE: Throttle check FIRST - skip most work on non-throttled frames
    local lastUpdate = CleveRoids.lastUpdate or 0
    local bypassThrottle = CleveRoids.isActionUpdateQueued and CleveRoidMacros.realtime == 0
    local shouldUpdate = bypassThrottle or (time - lastUpdate) >= refreshRate

    if not shouldUpdate then
        return  -- Early exit for non-throttled frames
    end

    CleveRoids.lastUpdate = time

    -- Process deferred equipment index updates (for throttled UNIT_INVENTORY_CHANGED)
    -- PERFORMANCE: Skip check entirely if no pending update
    local pendingTime = CleveRoids.equipIndexPendingTime
    if pendingTime and not UnitAffectingCombat("player") then
        if (time - (CleveRoids.lastEquipIndexTime or 0)) >= 0.2 then
            CleveRoids.lastEquipIndexTime = time
            CleveRoids.equipIndexPendingTime = nil
            CleveRoids.lastItemIndexTime = time
            CleveRoids.IndexItems()
            CleveRoids.Actions = {}
            CleveRoids.Macros = {}
            CleveRoids.IndexActionBars()

            if CleveRoidMacros.realtime == 0 then
                CleveRoids.QueueActionUpdate()
            end
        end
    end

    -- PERFORMANCE: Check for expired reactive procs only if we have any
    -- Use statically allocated removal buffer to avoid per-frame allocation
    local reactiveProcs = CleveRoids.reactiveProcs
    if reactiveProcs then
        local hasExpiredProc = false
        local toRemove = CleveRoids._procRemovalBuffer
        local removeCount = 0

        -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
        local spellName, procData = next(reactiveProcs)
        while spellName do
            if procData and procData.expiry and time >= procData.expiry then
                removeCount = removeCount + 1
                toRemove[removeCount] = spellName
                hasExpiredProc = true
            end
            spellName, procData = next(reactiveProcs, spellName)
        end

        -- Remove expired procs using indexed array (no pairs() overhead)
        for i = 1, removeCount do
            reactiveProcs[toRemove[i]] = nil
            toRemove[i] = nil  -- Clear for next use
        end

        -- If any proc expired, immediately update all actions
        if hasExpiredProc then
            CleveRoids.TestForAllActiveActions()
            CleveRoids.isActionUpdateQueued = false
        end
    end
    -- PERFORMANCE: Check for modifier key state changes (no events for these in vanilla WoW)
    -- Only queue update if modifier state actually changed - avoids full TestForAllActiveActions
    local altDown = IsAltKeyDown() and true or false
    local shiftDown = IsShiftKeyDown() and true or false
    local ctrlDown = IsControlKeyDown() and true or false

    if altDown ~= CleveRoids._lastAltDown or
       shiftDown ~= CleveRoids._lastShiftDown or
       ctrlDown ~= CleveRoids._lastCtrlDown then
        CleveRoids._lastAltDown = altDown
        CleveRoids._lastShiftDown = shiftDown
        CleveRoids._lastCtrlDown = ctrlDown
        -- Modifier changed - queue update in event-driven mode, or just mark for realtime
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.isActionUpdateQueued = true
        end
    end

    -- Check the saved variable to decide which update mode to use.
    if CleveRoidMacros.realtime == 1 then
        -- Realtime Mode: Force an update on every throttled tick for maximum responsiveness.
        CleveRoids.TestForAllActiveActions()
    else
        -- Event-Driven Mode (Default): Only update if a relevant game event has queued it.
        if CleveRoids.isActionUpdateQueued then
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[OnUpdate]|r Processing queued action update")
            end
            CleveRoids.TestForAllActiveActions()
            CleveRoids.isActionUpdateQueued = false -- Reset the flag after updating
            if CleveRoids.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[OnUpdate]|r Action update complete, flag reset")
            end
        end
    end

    -- The rest of this function handles time-based logic that must always run.
    if CleveRoids.CurrentSpell.autoAttackLock and (time - CleveRoids.autoAttackLockElapsed) > refreshRate then
        CleveRoids.CurrentSpell.autoAttackLock = false
        CleveRoids.autoAttackLockElapsed = nil
    end

    -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
    local Sequences = CleveRoids.Sequences
    local seqKey, sequence = next(Sequences)
    while seqKey do
        if sequence.index > 1 and sequence.reset.secs and (time - (sequence.lastUpdate or 0)) >= sequence.reset.secs then
            CleveRoids.ResetSequence(sequence)
        end
        seqKey, sequence = next(Sequences, seqKey)
    end

    -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
    local spell_tracking = CleveRoids.spell_tracking
    local guid, cast = next(spell_tracking)
    while guid do
        local nextGuid = next(spell_tracking, guid)  -- Get next before potential removal
        if cast.expires and time > cast.expires then
            spell_tracking[guid] = nil
        end
        guid, cast = nextGuid, nextGuid and spell_tracking[nextGuid]
    end

    -- Clean stale castTracking entries (standalone mode only, pfUI 7.6 manages its own)
    if not CleveRoids.hasPfUI76 then
        local ct = CleveRoids.castTracking
        local ctGuid, ctEntry = next(ct)
        while ctGuid do
            local nextCtGuid = next(ct, ctGuid)
            if ctEntry.endTime and time > ctEntry.endTime + 0.5 then
                ct[ctGuid] = nil
            end
            ctGuid = nextCtGuid
            ctEntry = nextCtGuid and ct[nextCtGuid]
        end
    end

    -- PERFORMANCE OPTIMIZATION: Run memory cleanup less frequently (every 5 seconds instead of every frame)
    -- This reduces CPU usage while maintaining effective memory management
    if (time - CleveRoids.lastCleanupTime) >= CleveRoids.CLEANUP_INTERVAL then
        CleveRoids.lastCleanupTime = time

        -- MEMORY: Clean up carnageDurationOverrides older than 30 seconds
        -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
        local carnageOverrides = CleveRoids.carnageDurationOverrides
        if carnageOverrides then
            local spellID, data = next(carnageOverrides)
            while spellID do
                local nextID = next(carnageOverrides, spellID)
                if data.timestamp and (time - data.timestamp) > 30 then
                    carnageOverrides[spellID] = nil
                end
                spellID, data = nextID, nextID and carnageOverrides[nextID]
            end
        end

        -- MEMORY: Clean up old ComboPointTracking entries (older than 60 seconds)
        -- PERFORMANCE: Use next() directly instead of pairs() to avoid iterator allocation
        local comboTracking = CleveRoids.ComboPointTracking
        if comboTracking then
            local trackName, data = next(comboTracking)
            while trackName do
                local nextName = next(comboTracking, trackName)
                if data.cast_time and (time - data.cast_time) > 60 then
                    comboTracking[trackName] = nil
                end
                trackName, data = nextName, nextName and comboTracking[nextName]
            end
        end

        -- MEMORY: Clear spell name caches every 60 seconds (12 cleanup cycles)
        CleveRoids._spellCacheCleanupCounter = (CleveRoids._spellCacheCleanupCounter or 0) + 1
        if CleveRoids._spellCacheCleanupCounter >= 12 then
            CleveRoids._spellCacheCleanupCounter = 0
            if CleveRoids.ClearSpellNameCaches then
                CleveRoids.ClearSpellNameCaches()
            end
        end

        -- MEMORY: Clean up stale perTargetState entries in sequences (older than 5 minutes)
        -- This prevents memory bloat from tracking many targets over time
        local SEQUENCE_TARGET_STALE_TIME = 300  -- 5 minutes
        for _, sequence in pairs(CleveRoids.Sequences) do
            if sequence.perTargetState then
                for guid, state in pairs(sequence.perTargetState) do
                    if state.lastUpdate and (time - state.lastUpdate) > SEQUENCE_TARGET_STALE_TIME then
                        sequence.perTargetState[guid] = nil
                    end
                end
            end
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

    -- If this is our macro but has no active action, show just the macro name
    if actions and not actions.active then
        local macroName = GetActionText(slot)
        if macroName then
            GameTooltip:SetText(macroName)
            GameTooltip:Show()
            return
        end
    end

    local action_to_display_info = nil
    if actions then
        -- Only show spell/item tooltip when there's an active action
        if actions.active then
            action_to_display_info = actions.active
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
    if not slot then return end
    CleveRoids.ClearAction(slot)
    CleveRoids.ClearSlot(CleveRoids.actionSlots, slot)
    CleveRoids.ClearAction(CleveRoids.reactiveSlots, slot)
    return CleveRoids.Hooks.PickupAction(slot)
end

CleveRoids.Hooks.ActionHasRange = ActionHasRange
function ActionHasRange(slot)
    if not slot then return nil end
    local actions = CleveRoids.GetAction(slot)
    -- Only override for our macros with #showtooltip
    if actions and actions.tooltip then
        -- If we have an active action with valid range data, use it
        if actions.active then
            if actions.active.inRange ~= -1 then
                return 1  -- Has range check with valid data
            else
                -- For channeled spells (inRange == -1), try proxy slot lookup
                local spellName = actions.active.spell and actions.active.spell.name
                local proxySlot = spellName and CleveRoids.GetProxyActionSlot(spellName)
                if proxySlot then
                    return CleveRoids.Hooks.ActionHasRange(proxySlot)
                end
            end
        end
        -- FIX: Even without actions.active, if the macro has potential spell actions,
        -- return 1 to ensure pfUI calls IsActionInRange (which will do proper checks)
        -- This fixes Super macros where actions.active might not be populated yet
        if actions.tooltip.spell or actions.tooltip.type == "spell" then
            return 1  -- Tooltip is a spell - has range
        end
        -- Check if any action in the list is a spell
        if actions.list then
            for i = 1, table.getn(actions.list) do
                local action = actions.list[i]
                if action and (action.spell or action.type == "spell") then
                    return 1  -- Has at least one spell action
                end
            end
        end
    end
    -- Not a macro we're tracking - pass through to original
    return CleveRoids.Hooks.ActionHasRange(slot)
end

CleveRoids.Hooks.IsActionInRange = IsActionInRange
function IsActionInRange(slot, unit)
    if not slot then return nil end
    local actions = CleveRoids.GetAction(slot)
    -- Only override for our macros with #showtooltip
    if actions and actions.tooltip then
        -- If we have an active spell action, use its range data
        if actions.active and actions.active.type == "spell" then
            if actions.active.inRange ~= -1 then
                return actions.active.inRange
            else
                -- For channeled spells (inRange == -1), try proxy slot lookup
                local spellName = actions.active.spell and actions.active.spell.name
                local proxySlot = spellName and CleveRoids.GetProxyActionSlot(spellName)
                if proxySlot then
                    return CleveRoids.Hooks.IsActionInRange(proxySlot, unit)
                end
            end
        end
        -- FIX: If no active action but macro has tooltip spell, check its range directly
        -- This ensures range coloring works even when actions.active hasn't been populated
        if not actions.active and actions.tooltip.spell then
            local spell = actions.tooltip.spell
            local spellName = spell.name
            if spellName and IsSpellInRange then
                local targetUnit = unit or "target"
                if UnitExists(targetUnit) then
                    -- FIX: Wrap in pcall - spell might not be in spellbook (items, other class spells, etc.)
                    local ok, result = pcall(IsSpellInRange, spellName, targetUnit)
                    if ok then
                        if result == 0 then
                            return 0  -- Out of range
                        elseif result == 1 then
                            return 1  -- In range
                        end
                    end
                end
            end
            -- Try proxy slot as fallback
            local proxySlot = spellName and CleveRoids.GetProxyActionSlot(spellName)
            if proxySlot then
                return CleveRoids.Hooks.IsActionInRange(proxySlot, unit)
            end
        end
    end
    -- Not a macro we're tracking - pass through to original
    return CleveRoids.Hooks.IsActionInRange(slot, unit)
end

CleveRoids.Hooks.OriginalIsUsableAction = IsUsableAction
CleveRoids.Hooks.IsUsableAction = IsUsableAction
function IsUsableAction(slot, unit)
    if not slot then return nil, nil end
    local actions = CleveRoids.GetAction(slot)

    -- If this is one of our macros AND it uses #showtooltip
    if actions and actions.tooltip then
        -- IMPORTANT: Only override usability when #showtooltip is present
        -- Macros without #showtooltip should use default game behavior
        if actions.active then
            -- We have an active action - return its usable state
            -- FIX: Convert oom boolean to number (1/nil) for Blizzard's button code
            local oomValue = actions.active.oom and 1 or nil
            return actions.active.usable, oomValue
        else
            -- FIX: If no active action but tooltip has a spell, check its usability directly
            -- This ensures usability coloring works even when actions.active hasn't been populated
            if actions.tooltip.spell then
                local spell = actions.tooltip.spell
                local spellName = spell.name
                if spellName and IsSpellUsable then
                    -- FIX: Wrap in pcall - spell might not be in spellbook (items, other class spells, etc.)
                    local ok, usable, notEnoughMana = pcall(IsSpellUsable, spellName)
                    if ok then
                        if usable == 1 then
                            return 1, nil  -- Usable
                        elseif notEnoughMana == 1 then
                            return nil, 1  -- Out of mana
                        else
                            return nil, nil  -- Not usable (wrong stance, etc.)
                        end
                    end
                end
                -- Fallback: check if spell has a cost and compare to current mana
                if spell.cost and spell.cost > 0 then
                    local currentMana = UnitMana("player")
                    if currentMana < spell.cost then
                        return nil, 1  -- Out of mana
                    end
                end
                -- Default to usable if we can't determine otherwise
                return 1, nil
            elseif actions.tooltip.item then
                -- FIX: Handle item tooltips - items are always usable unless on cooldown
                -- The cooldown is handled separately by GetActionCooldown hook
                return 1, nil
            end
            -- No tooltip spell or item - this macro's conditionals all failed
            -- Return nil to make the icon dark
            return nil, nil
        end
    else
        -- Not our macro OR no #showtooltip - use game's default behavior
        return CleveRoids.Hooks.IsUsableAction(slot, unit)
    end
end

CleveRoids.Hooks.IsCurrentAction = IsCurrentAction
function IsCurrentAction(slot)
    if not slot then return nil end
    local actions = CleveRoids.GetAction(slot)

    -- When no action is active (all conditionals failed), don't check tooltip's "current" status
    if actions and not actions.active and not actions.explicitTooltip and actions.list and table.getn(actions.list) > 0 then
        return CleveRoids.Hooks.IsCurrentAction(slot)
    end

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
            -- Get spell ID for comparison
            local spellId = actionToCheck.spell.id
            if not spellId and GetSpellIdForName then
                spellId = GetSpellIdForName(name)
            end

            if spellId then
                -- Prefer GetCastInfo (Nampower 2.18+) for cleaner API
                if GetCastInfo then
                    local ok, info = pcall(GetCastInfo)
                    if ok and info and info.spellId == spellId then
                        -- Spell is actively being cast/channeled
                        return true
                    end
                end

                -- Also check GetCurrentCastingInfo for queued spell detection
                if GetCurrentCastingInfo then
                    local castId, visId, autoId, casting, channeling = GetCurrentCastingInfo()

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
    if not slot then return nil end
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

            -- When no conditionals pass, use macro icon (not first action's icon)
            -- The actions.tooltip is just the first action which didn't pass conditionals
            if macroTexture then
                return macroTexture
            end

            -- Should never reach here, but return unknown as last resort
            return CleveRoids.unknownTexture
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

        -- Check if this is a shapeshift form spell and use active texture if toggled on
        if a and a.spell and a.action then
            -- Strip rank info and underscores from spell name for comparison
            local spellName = string.gsub(a.action, "%s*%(.-%)%s*$", "")
            spellName = string.gsub(spellName, "_", " ")
            -- Check all shapeshift forms to see if this spell matches and is active
            for i = 1, GetNumShapeshiftForms() do
                local icon, name, isActive, isCastable = GetShapeshiftFormInfo(i)
                if name and string.lower(name) == string.lower(spellName) and isActive and icon then
                    texture = icon
                    break
                end
            end
        end

        -- Check if this is a toggled buff ability (Prowl, Shadowmeld) and swap icon based on buff state
        -- Note: Stealth is handled above by shapeshift form logic
        if a and a.spell and a.action then
            local spellName = string.gsub(a.action, "%s*%(.-%)%s*$", "")
            spellName = string.gsub(spellName, "_", " ")

            -- Check if this is one of our toggled buff abilities (not shapeshift forms)
            local toggledAbilities = {
                [CleveRoids.Localized.Spells["Prowl"]] = true,
                [CleveRoids.Localized.Spells["Shadowmeld"]] = true,
            }

            if toggledAbilities[spellName] then
                -- Check if the buff is active
                if CleveRoids.ValidatePlayerBuff(spellName) then
                    -- Buff is active, use the active texture from auraTextures
                    local activeTexture = CleveRoids.auraTextures[spellName]
                    if activeTexture then
                        texture = activeTexture
                    end
                end
            end
        end

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
    -- Guard against nil/invalid slot
    if not slot then return 0, 0, 0 end

    local actions = CleveRoids.GetAction(slot)
    -- Check for actions.active OR actions.tooltip
    if actions and (actions.active or actions.tooltip) then

        -- When no action is active (all conditionals failed) but tooltip exists from #showtooltip,
        -- don't show the tooltip's cooldown - fall back to the original function (no cooldown)
        -- This matches the icon behavior in GetActionTexture (lines 3958-3977)
        if not actions.active and not actions.explicitTooltip and actions.list and table.getn(actions.list) > 0 then
            return CleveRoids.Hooks.GetActionCooldown(slot)
        end

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

        -- DEBUG: Log when we fall through without finding spell/item data (once per slot)
        if CleveRoids.cooldownDebug and not CleveRoids.cooldownDebugLogged[slot] then
            CleveRoids.cooldownDebugLogged[slot] = true
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cffff0000[CD Issue]|r Slot %d: No cooldown data! action='%s' type=%s spell=%s item=%s",
                slot,
                tostring(a.action),
                tostring(a.type),
                tostring(a.spell ~= nil),
                tostring(a.item ~= nil)
            ))
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[CD Issue]|r This slot will show incorrect cooldown. Report macro text to developer.")
        end

        -- Fallback to original function (preserves SuperWoW's #showtooltip handling)
        return CleveRoids.Hooks.GetActionCooldown(slot)
    else
        return CleveRoids.Hooks.GetActionCooldown(slot)
    end
end

CleveRoids.Hooks.GetActionCount = GetActionCount
function GetActionCount(slot)
    -- Guard against nil/invalid slot
    if not slot then return 0 end

    local action = CleveRoids.GetAction(slot)
    local count

    -- When no action is active (all conditionals failed), don't show tooltip's count
    if action and not action.active and not action.explicitTooltip and action.list and table.getn(action.list) > 0 then
        return CleveRoids.Hooks.GetActionCount(slot)
    end

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
    -- Guard against nil/invalid slot
    if not slot then return nil end

    local action = CleveRoids.GetAction(slot)

    -- When no action is active (all conditionals failed), don't show tooltip's consumable status
    if action and not action.active and not action.explicitTooltip and action.list and table.getn(action.list) > 0 then
        return CleveRoids.Hooks.IsConsumableAction(slot)
    end

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

-- ============================================================================
-- RunMacro Hook - Use our own macro execution system
-- ============================================================================
-- This allows /stopmacro, /skipmacro, /firstaction to work across parent/child
-- macro boundaries without requiring SuperMacro addon.
--
-- When SuperMacro is installed, its RunLine hook takes precedence for extended
-- macro features. This hook handles vanilla Blizzard macros.
-- ============================================================================
if not CleveRoids.RunMacroHooked then
    CleveRoids.Hooks.RunMacro = RunMacro

    function RunMacro(indexOrName)
        -- Skip if SuperMacro is handling macro execution (it has its own hooks)
        if CleveRoids.SM_RunLineHooked then
            return CleveRoids.Hooks.RunMacro(indexOrName)
        end

        -- Resolve macro index
        local macroIndex
        if type(indexOrName) == "number" then
            macroIndex = indexOrName
        elseif type(indexOrName) == "string" then
            -- Could be a name or a numeric string
            local num = tonumber(indexOrName)
            if num then
                macroIndex = num
            else
                macroIndex = GetMacroIndexByName(indexOrName)
            end
        end

        if not macroIndex or macroIndex == 0 then
            -- Fallback to original if we can't resolve
            return CleveRoids.Hooks.RunMacro(indexOrName)
        end

        -- Get macro body
        local name, icon, body = GetMacroInfo(macroIndex)
        if not body or body == "" then
            return CleveRoids.Hooks.RunMacro(indexOrName)
        end

        -- Clear macro flags at the start of top-level macro execution
        CleveRoids.stopMacroFlag = false
        CleveRoids.skipMacroFlag = false
        -- Note: stopOnCastFlag is intentionally NOT cleared here - it persists
        -- within a frame and is cleared by OnUpdate

        if CleveRoids.macroRefDebug then
            CleveRoids.Print("|cff00ff00[RunMacro Hook]|r Executing macro '" .. (name or macroIndex) .. "' via CleveRoids")
        end

        -- Execute through our system
        CleveRoids.ExecuteMacroBody(body)

        -- Don't call original - we've handled it
        return
    end

    CleveRoids.RunMacroHooked = true
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

-- == SHUTDOWN PROTECTION ==
-- Flag to prevent SuperWoW API calls during logout (crash prevention)
CleveRoids.isShuttingDown = false

-- == CORE EVENT REGISTRATION ==
CleveRoids.Frame:RegisterEvent("PLAYER_LOGIN")
CleveRoids.Frame:RegisterEvent("ADDON_LOADED")
CleveRoids.Frame:RegisterEvent("PLAYER_LOGOUT")
CleveRoids.Frame:RegisterEvent("PLAYER_LEAVING_WORLD")
CleveRoids.Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
CleveRoids.Frame:RegisterEvent("UPDATE_MACROS")
CleveRoids.Frame:RegisterEvent("SPELLS_CHANGED")
CleveRoids.Frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
CleveRoids.Frame:RegisterEvent("BAG_UPDATE")
CleveRoids.Frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
CleveRoids.Frame:RegisterEvent("UNIT_PET")

-- == STATE CHANGE EVENT REGISTRATION (for performance) ==
CleveRoids.Frame:RegisterEvent("PLAYER_TARGET_CHANGED")
CleveRoids.Frame:RegisterEvent("PLAYER_FOCUS_CHANGED") -- For focus addons
CleveRoids.Frame:RegisterEvent("PLAYER_ENTER_COMBAT")  -- Auto-attack started
CleveRoids.Frame:RegisterEvent("PLAYER_LEAVE_COMBAT")  -- Auto-attack stopped
CleveRoids.Frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entered actual combat (has threat)
CleveRoids.Frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Left actual combat (no threat)
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
CleveRoids.Frame:RegisterEvent("SPELLCAST_START")
CleveRoids.Frame:RegisterEvent("SPELLCAST_STOP")
CleveRoids.Frame:RegisterEvent("SPELLCAST_FAILED")
CleveRoids.Frame:RegisterEvent("SPELLCAST_INTERRUPTED")

-- Nampower SPELL_CAST_EVENT for reliable channel tracking
if GetCurrentCastingInfo then
    CleveRoids.Frame:RegisterEvent("SPELL_CAST_EVENT")
end


-- NOTE: SuperMacro hook installation is handled by Compatibility/SuperMacro.lua
-- which has the complete implementation including the INTERCEPT path for all commands

function CleveRoids.Frame:UNIT_PET()
    if arg1 == "player" then
        CleveRoids.IndexPetSpells()
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

-- Handle shutdown to prevent SuperWoW API crashes during logout
function CleveRoids.Frame:PLAYER_LOGOUT()
    CleveRoids.isShuttingDown = true
    this:UnregisterAllEvents()
    this:SetScript("OnUpdate", nil)
    this:SetScript("OnEvent", nil)
    -- Clear spell caches to prevent stale data
    if CleveRoids.spellIdCache then
        for k in pairs(CleveRoids.spellIdCache) do
            CleveRoids.spellIdCache[k] = nil
        end
    end
end

function CleveRoids.Frame:PLAYER_LEAVING_WORLD()
    -- FIX: Only set loading flag, don't unregister events
    -- PLAYER_LEAVING_WORLD fires for both logout AND zone transitions
    -- We need to stay alive for zone transitions; PLAYER_LOGOUT handles actual logout
    CleveRoids.isLoading = true
end

-- FIX: Handle zone transitions (instance entry, etc.)
-- Refresh action button state after loading screen completes
function CleveRoids.Frame:PLAYER_ENTERING_WORLD()
    CleveRoids.isLoading = false

    -- Skip if not yet initialized
    if not CleveRoids.ready then return end

    -- Refresh all action states after zone transition
    CleveRoids.TestForAllActiveActions()

    -- FIX: Force Blizzard buttons to re-query IsUsableAction
    -- Loading screen causes UI rebuild which can cache stale button states
    -- SKIP for pfUI users - pfUI handles its own button updates
    if not (pfUI and pfUI.bars) then
        for slot = 1, 120 do
            if CleveRoids.Actions[slot] then
                CleveRoids.SendEventForAction(slot, "ACTIONBAR_SLOT_CHANGED", slot)
            end
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

    -- PERFORMANCE: Initialize event-driven cache states
    CleveRoids._cachedPlayerInCombat = UnitAffectingCombat("player") and true or false

    -- Schedule delayed WDB warmup (loads items into client cache via tooltip scan)
    -- This ensures GetItemInfo() works for all inventory items after a WDB clear
    CleveRoids.wdbWarmupTime = GetTime() + 3.0  -- 3 second delay after login
end

-- PERFORMANCE: WDB warmup - tooltip scan all bag items to ensure they're cached
-- This prevents GetItemInfo() returning nil for items after a WDB clear
function CleveRoids.DoWDBWarmup()
    if CleveRoids.wdbWarmupDone then return end
    CleveRoids.wdbWarmupDone = true

    -- Create a hidden tooltip for scanning if it doesn't exist
    local tip = CleveRoidsWDBTip
    if not tip then
        tip = CreateFrame("GameTooltip", "CleveRoidsWDBTip", UIParent, "GameTooltipTemplate")
        tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    local scanned = 0

    -- Scan all bag slots
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                -- Tooltip scan loads the item into WDB
                tip:ClearLines()
                tip:SetBagItem(bag, slot)
                scanned = scanned + 1
            end
        end
    end

    -- Scan equipped items
    for slot = 0, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            tip:ClearLines()
            tip:SetInventoryItem("player", slot)
            scanned = scanned + 1
        end
    end

    -- Now trigger a full item index to populate the cache with valid data
    if CleveRoids.IndexItems then
        CleveRoids.IndexItems()
    end

    if CleveRoids.debug then
        CleveRoids.Print("|cff88ff88[WDB Warmup]|r Scanned " .. scanned .. " items into cache")
    end
end

function CleveRoids.Frame:ADDON_LOADED(addon)
    -- keep your existing init for CRM:
    if addon == "CleveRoidMacros" or addon == "SuperCleveRoidMacros" then
        CleveRoids.InitializeExtensions()
    end
    -- NOTE: SuperMacro hook installation is handled by Compatibility/SuperMacro.lua
end

function CleveRoids.Frame:UNIT_CASTEVENT(caster,target,action,spell_id,cast_time)
    -- Handle melee swings for judgement refresh
    if action == "MAINHAND" or action == "OFFHAND" then
        -- Only process if this is the player's melee swing
        if caster == CleveRoids.playerGuid and CleveRoids.playerClass == "PALADIN" then
            -- Refresh judgements on the target
            -- Defensive: verify libdebuff is a table before accessing properties
            local lib = type(CleveRoids.libdebuff) == "table" and CleveRoids.libdebuff or nil
            if target and lib and lib.objects then
                local normalizedTarget = CleveRoids.NormalizeGUID(target)
                if normalizedTarget and lib.objects[normalizedTarget] then
                    -- Refresh all active Judgements on the target
                    for spellID, rec in pairs(lib.objects[normalizedTarget]) do
                        -- Check if this is a judgement by spell ID
                        if lib.judgementSpells and lib.judgementSpells[spellID] and rec.start and rec.duration then
                            -- Only refresh if the Judgement is still active and was cast by player
                            local remaining = rec.duration + rec.start - GetTime()
                            if remaining > 0 and rec.caster == "player" then
                                -- Refresh the Judgement by updating the start time
                                rec.start = GetTime()

                                local spellName = SpellInfo(spellID)
                                local baseName = spellName and string.gsub(spellName, "%s*%(Rank %d+%)", "") or "Unknown"

                                if CleveRoids.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage(
                                        string.format("|cff00ffaa[Judgement Refresh]|r Refreshed %s (ID:%d) on %s hit - new duration: %ds",
                                            baseName, spellID, action, rec.duration)
                                    )
                                end

                                -- Also sync to pfUI if it's loaded (pre-7.6 only)
                                if not CleveRoids.hasPfUI76 and pfUI and pfUI.api and pfUI.api.libdebuff then
                                    local targetName = (lib.guidToName and lib.guidToName[normalizedTarget]) or UnitName("target")
                                    local targetLevel = UnitLevel("target") or 0

                                    if targetName then
                                        pfUI.api.libdebuff:AddEffect(targetName, targetLevel, baseName, rec.duration, "player")

                                        if CleveRoids.debug then
                                            DEFAULT_CHAT_FRAME:AddMessage(
                                                string.format("|cff00ffaa[pfUI Judgement Refresh]|r Synced %s refresh to pfUI", baseName)
                                            )
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return  -- Still return early after processing melee
    end

    -- Debug channel tracking
    if CleveRoids.ChannelTimeDebug then
        local spellName = spell_id and SpellInfo and SpellInfo(spell_id) or "Unknown"
        if string.find(spellName, "Arcane") then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[UNIT_CASTEVENT]|r %s: %s (ID:%s) caster=%s player=%s",
                action, spellName, tostring(spell_id), tostring(caster), tostring(CleveRoids.playerGuid)))
        end
    end

    -- handle cast spell tracking
    local cast = CleveRoids.spell_tracking[caster]
    if cast_time > 0 and action == "START" or action == "CHANNEL" then
        CleveRoids.spell_tracking[caster] = { spell_id = spell_id, expires = GetTime() + cast_time/1000, type = action }

        -- ALSO store under "player" literal for easier lookup
        if caster == CleveRoids.playerGuid then
            CleveRoids.spell_tracking["player"] = CleveRoids.spell_tracking[caster]

            -- For CHANNEL events, capture duration for checkchanneled conditional
            if action == "CHANNEL" then
                CleveRoids.channelStartTime = GetTime()
                -- Try to get accurate duration from spell tooltip (reflects haste)
                local tooltipDuration = CleveRoids.GetChannelDurationFromTooltipByID(spell_id)
                if tooltipDuration then
                    CleveRoids.channelDuration = tooltipDuration
                else
                    -- Fallback to UNIT_CASTEVENT duration (may not reflect haste)
                    CleveRoids.channelDuration = cast_time / 1000
                end
            end

            -- For START events, capture cast time for checkcasting conditional
            if action == "START" then
                CleveRoids.castStartTime = GetTime()
                -- For cast-time spells, UNIT_CASTEVENT duration is usually accurate
                -- but we could add tooltip scanning here too if needed
                CleveRoids.castDuration = cast_time / 1000
            end
        end

        if CleveRoids.ChannelTimeDebug and caster == CleveRoids.playerGuid then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[Tracking]|r Set spell_tracking[%s] AND [player]: type=%s, expires=%.2f",
                tostring(caster), action, GetTime() + cast_time/1000))
        end
        -- Always show for channels if debug is on
        if CleveRoids.ChannelTimeDebug and action == "CHANNEL" then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[Tracking]|r caster=%s, playerGuid=%s, match=%s",
                tostring(caster), tostring(CleveRoids.playerGuid), tostring(caster == CleveRoids.playerGuid)))
        end
    elseif cast
        and (
            (cast.spell_id == spell_id and (action == "FAIL" or action == "CAST"))
            or (GetTime() > cast.expires)
        )
    then
        if CleveRoids.ChannelTimeDebug and caster == CleveRoids.playerGuid then
            local reason = ""
            if cast.spell_id == spell_id and (action == "FAIL" or action == "CAST") then
                reason = string.format("spell_id match (%s) and action=%s", tostring(spell_id), action)
            elseif GetTime() > cast.expires then
                reason = string.format("expired (%.2f > %.2f)", GetTime(), cast.expires)
            end
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[Tracking]|r CLEARING spell_tracking - %s", reason))
        end
        CleveRoids.spell_tracking[caster] = nil
        -- Also clear "player" literal if this is the player
        if caster == CleveRoids.playerGuid then
            CleveRoids.spell_tracking["player"] = nil
        end
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

-- Nampower SPELL_CAST_EVENT handler for reliable channel tracking
-- This is the PRIMARY source of truth for channel state (not GetCurrentCastingInfo polling)
function CleveRoids.Frame:SPELL_CAST_EVENT(success, spellId, castType, targetGuid, itemId)
    local CHANNEL = 4

    if castType == CHANNEL and success == 1 then
        -- Channel started successfully
        CleveRoids.CurrentSpell.type = "channeled"
        CleveRoids.CurrentSpell.castingSpellId = spellId

        local spellName = SpellInfo and SpellInfo(spellId)
        if spellName then
            CleveRoids.CurrentSpell.spellName = spellName
        end

        -- Force immediate action update
        CleveRoids.TestForAllActiveActions()
    end
end

function CleveRoids.Frame:SPELLCAST_CHANNEL_START()
    -- Set channel state immediately when event fires
    -- Duration is captured by UNIT_CASTEVENT which fires earlier
    CleveRoids.CurrentSpell.type = "channeled"

    -- Try to get spell info - prefer GetCastInfo (Nampower 2.18+) for better data
    local spellId = nil
    if GetCastInfo then
        local ok, info = pcall(GetCastInfo)
        if ok and info and info.spellId and info.spellId > 0 then
            spellId = info.spellId
            -- Also capture timing data
            CleveRoids.CurrentSpell.castRemainingMs = info.castRemainingMs
            CleveRoids.CurrentSpell.castEndTime = info.castEndS
        end
    end
    -- Fallback to GetCurrentCastingInfo for older Nampower
    if not spellId and GetCurrentCastingInfo then
        local _, visId = GetCurrentCastingInfo()
        if visId and visId > 0 then
            spellId = visId
        end
    end
    -- Update spell info
    if spellId then
        CleveRoids.CurrentSpell.castingSpellId = spellId
        local spellName = SpellInfo(spellId)
        if spellName then
            CleveRoids.CurrentSpell.spellName = spellName
        end
    end

    -- v2.38+: Override channelDuration with the accurate server-provided value stored by
    -- SPELL_START_SELF (which fires before this event).  This beats the tooltip scan or
    -- UNIT_CASTEVENT cast_time fallback, because the server already applied all modifiers.
    if CleveRoids._v238ChannelDuration then
        if not spellId or not CleveRoids._v238ChannelSpellId
            or CleveRoids._v238ChannelSpellId == spellId then
            CleveRoids.channelDuration = CleveRoids._v238ChannelDuration
        end
        CleveRoids._v238ChannelDuration = nil
        CleveRoids._v238ChannelSpellId  = nil
    end

    -- Force immediate action update
    CleveRoids.TestForAllActiveActions()
end

function CleveRoids.Frame:SPELLCAST_CHANNEL_STOP()
    -- Channel ended - clear state immediately
    CleveRoids.CurrentSpell.type = ""
    CleveRoids.CurrentSpell.spellName = ""
    CleveRoids.CurrentSpell.castingSpellId = nil

    -- WARLOCK DARK HARVEST: Mark channeling as ended
    -- Credits: Avitasia / Cursive addon
    if CleveRoids.darkHarvestData and CleveRoids.darkHarvestData.isActive then
        CleveRoids.darkHarvestData.isActive = false
        CleveRoids.darkHarvestData.endTime = GetTime()

        -- Apply Dark Harvest end to all DoTs on target (finalizes reduction)
        if CleveRoids.libdebuff and CleveRoids.libdebuff.ApplyDarkHarvestEnd then
            CleveRoids.libdebuff.ApplyDarkHarvestEnd(CleveRoids.darkHarvestData.targetGUID)
        end

        if CleveRoids.debug then
            local activeTime = CleveRoids.darkHarvestData.endTime - CleveRoids.darkHarvestData.startTime
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cff9482c9[Dark Harvest]|r Channel ended after %.1fs (DoT acceleration stopped)",
                    activeTime)
            )
        end
    end

    -- Force immediate action update
    CleveRoids.TestForAllActiveActions()
end

function CleveRoids.Frame:SPELLCAST_START()
    -- Cast-time spell started
    -- Duration is captured by UNIT_CASTEVENT which fires earlier
    CleveRoids.CurrentSpell.type = "cast"

    -- Try to get spell info - prefer GetCastInfo (Nampower 2.18+) for better data
    local spellId = nil
    if GetCastInfo then
        local ok, info = pcall(GetCastInfo)
        if ok and info and info.spellId and info.spellId > 0 then
            spellId = info.spellId
            -- Also capture timing data
            CleveRoids.CurrentSpell.castRemainingMs = info.castRemainingMs
            CleveRoids.CurrentSpell.castEndTime = info.castEndS
            CleveRoids.CurrentSpell.gcdRemainingMs = info.gcdRemainingMs
            CleveRoids.CurrentSpell.gcdEndTime = info.gcdEndS
        end
    end
    -- Fallback to GetCurrentCastingInfo for older Nampower
    if not spellId and GetCurrentCastingInfo then
        local castId = GetCurrentCastingInfo()
        if castId and castId > 0 then
            spellId = castId
        end
    end
    -- Update spell info
    if spellId then
        CleveRoids.CurrentSpell.castingSpellId = spellId
        local spellName = SpellInfo(spellId)
        if spellName then
            CleveRoids.CurrentSpell.spellName = spellName
        end
    end

    -- Force immediate action update
    CleveRoids.TestForAllActiveActions()
end

function CleveRoids.Frame:SPELLCAST_STOP()
    -- Cast finished - clear state immediately
    if CleveRoids.CurrentSpell.type == "cast" then
        CleveRoids.CurrentSpell.type = ""
        CleveRoids.CurrentSpell.spellName = ""
        CleveRoids.CurrentSpell.castingSpellId = nil

        -- Force immediate action update
        CleveRoids.TestForAllActiveActions()
    end
end

function CleveRoids.Frame:SPELLCAST_FAILED()
    -- Cast failed - clear state immediately
    if CleveRoids.CurrentSpell.type == "cast" then
        CleveRoids.CurrentSpell.type = ""
        CleveRoids.CurrentSpell.spellName = ""
        CleveRoids.CurrentSpell.castingSpellId = nil

        -- Force immediate action update
        CleveRoids.TestForAllActiveActions()
    end
end

function CleveRoids.Frame:SPELLCAST_INTERRUPTED()
    -- Cast interrupted - clear state immediately
    if CleveRoids.CurrentSpell.type == "cast" then
        CleveRoids.CurrentSpell.type = ""
        CleveRoids.CurrentSpell.spellName = ""
        CleveRoids.CurrentSpell.castingSpellId = nil

        -- Force immediate action update
        CleveRoids.TestForAllActiveActions()
    end
end

-- PLAYER_ENTER_COMBAT/PLAYER_LEAVE_COMBAT are for AUTO-ATTACK state (not actual combat)
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

    -- Full re-index after combat to refresh any items/bags that were skipped
    -- during combat for performance. Use a slight delay to avoid spam.
    local now = GetTime()
    if (now - (CleveRoids.lastItemIndexTime or 0)) > 0.5 then
        CleveRoids.lastItemIndexTime = now
        CleveRoids.IndexItems()
        CleveRoids.Actions = {}
        CleveRoids.Macros = {}
        CleveRoids.IndexActionBars()
    end

    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

-- PLAYER_REGEN_DISABLED/PLAYER_REGEN_ENABLED are for ACTUAL combat state (threat/aggro)
-- These events track what UnitAffectingCombat("player") reports
function CleveRoids.Frame:PLAYER_REGEN_DISABLED()
    -- PERFORMANCE: Cache actual combat state for event-driven [combat]/[nocombat] conditionals
    CleveRoids._cachedPlayerInCombat = true
    if CleveRoidMacros.realtime == 0 then
        CleveRoids.QueueActionUpdate()
    end
end

function CleveRoids.Frame:PLAYER_REGEN_ENABLED()
    -- PERFORMANCE: Cache actual combat state for event-driven [combat]/[nocombat] conditionals
    CleveRoids._cachedPlayerInCombat = false

    -- Reset any sequence with reset=combat that has progressed past the first step
    -- Uses PLAYER_REGEN_ENABLED (actual combat ends) instead of PLAYER_LEAVE_COMBAT (auto-attack stops)
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

    -- Clear resist state when target changes
    CleveRoids.ClearResistState()

    -- Handle sequences with reset=target - save/restore per-target state
    -- Instead of resetting, we remember each target's progress in the sequence
    local currentGuid = nil
    if UnitExists("target") then
        local _, guid = UnitExists("target")
        currentGuid = guid
    end

    for _, sequence in pairs(CleveRoids.Sequences) do
        if sequence.reset and sequence.reset.target then
            local oldGuid = sequence.lastTargetGuid

            -- Only process if target actually changed
            if oldGuid ~= currentGuid then
                -- Save current state for the old target (if we had one and progressed)
                if oldGuid and sequence.index > 1 then
                    sequence.perTargetState = sequence.perTargetState or {}
                    sequence.perTargetState[oldGuid] = {
                        index = sequence.index,
                        lastUpdate = sequence.lastUpdate,
                    }
                end

                -- Restore state for the new target (or start fresh)
                if currentGuid and sequence.perTargetState and sequence.perTargetState[currentGuid] then
                    -- Restore saved state for this target
                    local saved = sequence.perTargetState[currentGuid]
                    sequence.index = saved.index
                    sequence.lastUpdate = saved.lastUpdate
                else
                    -- New target we haven't seen - start at step 1
                    sequence.index = 1
                    sequence.status = 0
                end

                -- Update the current target GUID
                sequence.lastTargetGuid = currentGuid
            end
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
    -- PERFORMANCE: Clear spell caches when spells change (learn new ranks, etc.)
    CleveRoids.spellIdCache = {}
    CleveRoids.spellNameCache = {}
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
    -- In combat: Skip entirely for zero lag
    if UnitAffectingCombat("player") then
        return
    end

    -- Out of combat: Full indexing with throttle
    local now = GetTime()
    if (now - (CleveRoids.lastItemIndexTime or 0)) > 1.0 then
        CleveRoids.lastItemIndexTime = now
        CleveRoids.IndexItems()

        -- Directly clear all relevant caches and force a UI refresh for all buttons.
        CleveRoids.Actions = {}
        CleveRoids.Macros = {}
        CleveRoids.IndexActionBars()
        if CleveRoidMacros.realtime == 0 then
            CleveRoids.QueueActionUpdate()
        end
    end
end

function CleveRoids.Frame:UNIT_INVENTORY_CHANGED()
    if arg1 ~= "player" then return end

    -- PERFORMANCE: Invalidate equipment cache for HasGearEquipped
    if CleveRoids.InvalidateEquipmentCache then
        CleveRoids.InvalidateEquipmentCache()
    end

    -- In combat: Skip ALL processing - EquipBagItem already handles cache invalidation
    -- This eliminates lag from IndexEquippedItems during rapid gear swapping
    if UnitAffectingCombat("player") then
        return
    end

    -- Out of combat: Full indexing with throttle
    local now = GetTime()
    if (now - (CleveRoids.lastEquipIndexTime or 0)) < 0.2 then
        CleveRoids.equipIndexPendingTime = now
        return
    end

    CleveRoids.lastEquipIndexTime = now
    CleveRoids.equipIndexPendingTime = nil
    CleveRoids.lastItemIndexTime = now
    CleveRoids.IndexItems()
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

    -- COOLDOWN FIX: Explicitly update cooldowns on all managed action buttons
    -- This ensures cooldowns display correctly even when the active action hasn't changed
    CleveRoids.UpdateAllManagedCooldowns()
end

-- Helper function to notify addon handlers about cooldown updates
-- NOTE: Blizzard action buttons are handled natively via ActionButton_OnEvent which calls
-- our GetActionCooldown hook. We do NOT call CooldownFrame_SetTimer directly to avoid
-- conflicts with SuperWoW's own GetActionCooldown handling for #showtooltip macros.
-- Track which slots have been logged to avoid spam
CleveRoids.cooldownDebugLogged = {}

function CleveRoids.UpdateAllManagedCooldowns()
    local Actions = CleveRoids.Actions
    if not Actions then return end

    -- Only notify third-party handlers (pfUI/Bongos)
    -- Blizzard buttons update themselves via GetActionCooldown hook
    local handlerCount = CleveRoids.actionEventHandlers and table.getn(CleveRoids.actionEventHandlers) or 0
    if handlerCount == 0 then return end

    for slot, actions in pairs(Actions) do
        if actions then
            -- Notify action event handlers (for pfUI/Bongos) about the cooldown update
            for _, fn_h in ipairs(CleveRoids.actionEventHandlers) do
                fn_h(slot, "ACTIONBAR_UPDATE_COOLDOWN")
            end
        end
    end
end
-- PERFORMANCE OPTIMIZATION: Throttled event handlers to reduce CPU spam
-- UNIT_AURA can fire dozens of times per second during combat
-- 100ms throttle reduces calls by 90%+ while maintaining responsiveness
function CleveRoids.Frame:UNIT_AURA()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitAuraUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitAuraUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end
function CleveRoids.Frame:UNIT_HEALTH()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitHealthUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitHealthUpdate = now
            CleveRoids.QueueActionUpdate()
        end
    end
end
function CleveRoids.Frame:UNIT_POWER()
    if CleveRoidMacros.realtime == 0 then
        local now = GetTime()
        if (now - CleveRoids.lastUnitPowerUpdate) >= CleveRoids.EVENT_THROTTLE then
            CleveRoids.lastUnitPowerUpdate = now
            CleveRoids.QueueActionUpdate()
        end
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
            -- BUGFIX: Update casting state when spell is queued (for [casting] conditional)
            if CleveRoids.UpdateCastingState then
                CleveRoids.UpdateCastingState()
            end
            CleveRoids.QueueActionUpdate()
        elseif eventCode == NORMAL_QUEUE_POPPED or eventCode == NON_GCD_QUEUE_POPPED or eventCode == ON_SWING_QUEUE_POPPED then
            CleveRoids.queuedSpell = nil
            -- BUGFIX: Update casting state when spell queue pops (for [casting] conditional)
            if CleveRoids.UpdateCastingState then
                CleveRoids.UpdateCastingState()
            end
            CleveRoids.QueueActionUpdate()
        end
    end
end

function CleveRoids.Frame:SPELL_CAST_EVENT()
    if event == "SPELL_CAST_EVENT" then
        local success = arg1
        local spellId = arg2
        local castType = arg3
        local targetGuid = arg4

        -- BUGFIX: Update casting state on spell cast events (for [casting] conditional)
        if CleveRoids.UpdateCastingState then
            CleveRoids.UpdateCastingState()
        end

        if success == 1 then
            CleveRoids.lastCastSpell = {
                spellId = spellId,
                castType = castType,
                targetGuid = targetGuid,
                timestamp = GetTime()
            }
            if SpellInfo then
                local name = SpellInfo(spellId)
                if name then
                    CleveRoids.lastCastSpell.spellName = name
                end
            end

            -- Track pending cast for SPELL_GO correlation (reactive ability detection)
            -- Keyed by spellId so concurrent casts don't overwrite each other
            CleveRoids.pendingCasts = CleveRoids.pendingCasts or {}

            -- Clean up consumed entries older than 5 seconds (lightweight, runs per-cast)
            local cleanupTime = GetTime() - 5
            for id, entry in pairs(CleveRoids.pendingCasts) do
                if entry.consumed and entry.consumedAt and entry.consumedAt < cleanupTime then
                    CleveRoids.pendingCasts[id] = nil
                end
            end

            CleveRoids.pendingCasts[spellId] = {
                castType = castType,
                targetGuid = targetGuid,
                timestamp = GetTime(),
                comboPoints = nil,
            }

            -- Capture combo points NOW (before server consumes them)
            -- SPELL_CAST_EVENT fires client-side, so CP are guaranteed available
            if (CleveRoids.IsComboScalingSpellID and CleveRoids.IsComboScalingSpellID(spellId)) or
               (CleveRoids.FerociousBiteSpellIDs and CleveRoids.FerociousBiteSpellIDs[spellId]) then
                local cp = CleveRoids.GetComboPoints and CleveRoids.GetComboPoints() or 0
                if cp > 0 then
                    CleveRoids.pendingCasts[spellId].comboPoints = cp
                    if CleveRoids.debug then
                        local castSpellName = SpellInfo and SpellInfo(spellId) or "Unknown"
                        DEFAULT_CHAT_FRAME:AddMessage(
                            string.format("|cff00ff88[SPELL_CAST_EVENT]|r Captured %d CP for %s (ID:%d)",
                                cp, castSpellName, spellId)
                        )
                    end
                end
            end
        else
            -- Cast failed - clear pending entry for this spell
            if CleveRoids.pendingCasts then
                CleveRoids.pendingCasts[spellId] = nil
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
    local s, e, a, b, c = string.find(msg, "^(%S*)%s*(%S*)%s*(.*)$")
    if a then cmd = a else cmd = "" end
    if b then val = b else val = "" end
    if c then val2 = c else val2 = "" end

    -- No command: show current value and available commands
    if cmd == "" then
        CleveRoids.Print("Current Settings:")
        DEFAULT_CHAT_FRAME:AddMessage("realtime (force fast updates, CPU intensive) = " .. CleveRoidMacros.realtime .. " (Default: 0)")
        DEFAULT_CHAT_FRAME:AddMessage("refresh (updates per second) = " .. CleveRoidMacros.refresh .. " (Default: 5)")
        DEFAULT_CHAT_FRAME:AddMessage("macrocheck (syntax checker) = " .. CleveRoidMacros.macrocheck .. " (Default: 1)")
        DEFAULT_CHAT_FRAME:AddMessage("debug (show learning messages) = " .. (CleveRoids.debug and "1" or "0") .. " (Default: 0)")
        DEFAULT_CHAT_FRAME:AddMessage(" ")
        CleveRoids.Print("Available Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid realtime 0 or 1 - Force realtime updates")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid refresh X - Set refresh rate (1-10 updates/sec)")
        DEFAULT_CHAT_FRAME:AddMessage("/cleveroid macrocheck 0 or 1 - Enable/disable macro syntax checker")
        if CleveRoids.hasSuperwow then
            DEFAULT_CHAT_FRAME:AddMessage("/cleveroid learn <spellID> <duration> - Manually set spell duration")
            DEFAULT_CHAT_FRAME:AddMessage("/cleveroid forget <spellID|all> - Forget learned duration(s)")
            DEFAULT_CHAT_FRAME:AddMessage("/cleveroid debug [0|1] - Toggle learning debug messages")
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Spell Schools:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listschools - List all learned spell schools')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearschools - Clear learned spell school data')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Immunity Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listimmune [school] - List immunity data')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addimmune "<NPC>" <school> [buff] - Add immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeimmune "<NPC>" <school> - Remove immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearimmune [school] - Clear immunity data')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00CC Immunity Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listccimmune [type] - List CC immunity data')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addccimmune "<NPC>" <type> [buff] - Add CC immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeccimmune "<NPC>" <type> - Remove CC immunity')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearccimmune [type] - Clear CC immunity data')
        DEFAULT_CHAT_FRAME:AddMessage("  CC types: stun, fear, root, silence, sleep, charm, polymorph, banish, horror, disorient, snare")
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Combo Point Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combotrack - Show combo point tracking info')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid comboclear - Clear combo tracking data')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combolearn - Show learned combo durations (per CP)')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Talent Modifiers:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid talenttabs - Show talent tab IDs for your class')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listtab <tab> - List all talents in a tab with their IDs')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid talents - Show current talent ranks')
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid testtalent <spellID> - Test talent modifier for a spell')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Debuff Tracking Debug:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid debuffdebug [spell] - Debug debuff tracking on target')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00pfUI Tank Integration:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid tankdebug - Debug tank targeting conditionals')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00All-Caster Aura Tracking:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid auradebug - Debug buff/debuff time tracking from all casters')
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Overflow Buff Frame:|r")
        DEFAULT_CHAT_FRAME:AddMessage('/cleveroid overflowtest - Toggle overflow buff frame test mode')
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
            CleveRoids.cachedRefreshRate = nil  -- Invalidate cached rate
            CleveRoids.Print("refresh set to " .. num .. " times per second")
        else
            CleveRoids.Print("Usage: /cleveroid refresh X - Set refresh rate. (1 to 10 updates per second. Default: 5)")
            CleveRoids.Print("Current refresh = " .. tostring(CleveRoidMacros.refresh) .. " times per second")
        end
        return
    end

    -- macrocheck
    if cmd == "macrocheck" then
        local num = tonumber(val)
        if num == 0 or num == 1 then
            CleveRoidMacros.macrocheck = num
            if num == 1 then
                CleveRoids.Print("Macro syntax checker |cff00ff00enabled|r")
            else
                CleveRoids.Print("Macro syntax checker |cffff0000disabled|r (reload UI to take effect)")
            end
        else
            CleveRoids.Print("Usage: /cleveroid macrocheck 0 or 1 - Enable/disable macro syntax checker (Default: 1)")
            CleveRoids.Print("Current macrocheck = " .. tostring(CleveRoidMacros.macrocheck))
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

    -- ========== CC IMMUNITY COMMANDS ==========

    -- listccimmune (list CC immunity data)
    if cmd == "listccimmune" or cmd == "ccimmunelist" then
        CleveRoids.ListCCImmunities(val ~= "" and val or nil)
        return
    end

    -- clearccimmune (clear CC immunity data)
    if cmd == "clearccimmune" then
        CleveRoids.ClearCCImmunities(val ~= "" and val or nil)
        return
    end

    -- addccimmune (manually add CC immunity)
    if cmd == "addccimmune" then
        -- Parse: /cleveroid addccimmune <NPC Name> <cctype> [buff]
        -- Example: /cleveroid addccimmune "Stone Guardian" stun
        -- Example: /cleveroid addccimmune "Boss Name" fear "Enrage"
        local npcName, ccType, buffName = nil, nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, rest = string.find(msg, '^addccimmune%s+"([^"]+)"%s*(.*)$')
        if quotedNpc then
            npcName = quotedNpc
            -- Parse ccType and optional buff from rest
            local _, _, cct, buff = string.find(rest, "^(%S+)%s*(.*)$")
            ccType = cct
            if buff and buff ~= "" then
                -- Check if buff is quoted
                local _, _, quotedBuff = string.find(buff, '^"([^"]+)"$')
                buffName = quotedBuff or buff
            end
        else
            -- No quoted NPC, use simple parsing
            npcName = val
            ccType = val2
        end

        CleveRoids.AddCCImmunity(npcName, ccType, buffName)
        return
    end

    -- removeccimmune (manually remove CC immunity)
    if cmd == "removeccimmune" then
        -- Parse: /cleveroid removeccimmune <NPC Name> <cctype>
        local npcName, ccType = nil, nil

        -- Try to extract quoted NPC name
        local _, _, quotedNpc, cct = string.find(msg, '^removeccimmune%s+"([^"]+)"%s*(%S*)$')
        if quotedNpc then
            npcName = quotedNpc
            ccType = cct
        else
            npcName = val
            ccType = val2
        end

        CleveRoids.RemoveCCImmunityCommand(npcName, ccType)
        return
    end

    -- listschools (show learned spell schools)
    if cmd == "listschools" or cmd == "schools" then
        CleveRoids.Print("|cff88ff88=== Learned Spell Schools ===|r")
        if not CleveRoids_SpellSchools or not next(CleveRoids_SpellSchools) then
            CleveRoids.Print("No spell schools learned yet. Deal damage to enemies!")
            CleveRoids.Print("Nampower damage events will automatically track spell schools.")
        else
            local count = 0
            local bySchool = {}

            -- Group by school
            for spellID, school in pairs(CleveRoids_SpellSchools) do
                if not bySchool[school] then
                    bySchool[school] = {}
                end
                table.insert(bySchool[school], spellID)
                count = count + 1
            end

            CleveRoids.Print("Total spells tracked: " .. count)
            CleveRoids.Print(" ")

            -- Display by school
            for school, spellIDs in pairs(bySchool) do
                local schoolColor = "|cff88ff88"
                if school == "fire" then schoolColor = "|cffff4400"
                elseif school == "frost" then schoolColor = "|cff00ffff"
                elseif school == "nature" then schoolColor = "|cff00ff00"
                elseif school == "shadow" then schoolColor = "|cff8800ff"
                elseif school == "arcane" then schoolColor = "|cffff00ff"
                elseif school == "holy" then schoolColor = "|cffffff00"
                elseif school == "bleed" then schoolColor = "|cffff0000"
                end

                CleveRoids.Print(schoolColor .. string.upper(school) .. "|r (" .. table.getn(spellIDs) .. " spells):")
                for _, spellID in ipairs(spellIDs) do
                    local spellName = SpellInfo and SpellInfo(spellID) or "Unknown"
                    CleveRoids.Print("  " .. spellName .. " (ID:" .. spellID .. ")")
                end
            end
        end
        return
    end

    -- clearschools (clear learned spell schools)
    if cmd == "clearschools" then
        local count = 0
        if CleveRoids_SpellSchools then
            for _ in pairs(CleveRoids_SpellSchools) do
                count = count + 1
            end
        end
        CleveRoids_SpellSchools = {}
        CleveRoids.spellSchoolMapping = CleveRoids_SpellSchools
        CleveRoids.Print("Cleared " .. count .. " learned spell schools")
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

    -- talenttabs (show talent tab IDs)
    if cmd == "talenttabs" or cmd == "tabs" then
        CleveRoids.Print("=== Talent Tabs ===")
        for i = 1, GetNumTalentTabs() do
            local name, _, pointsSpent = GetTalentTabInfo(i)
            CleveRoids.Print("Tab " .. i .. ": " .. name .. " (" .. pointsSpent .. " points)")
        end
        return
    end

    -- listtab (show all talents in a specific tab with their IDs)
    if cmd == "listtab" or cmd == "tab" then
        local tabNum = tonumber(val)
        if not tabNum or tabNum < 1 or tabNum > GetNumTalentTabs() then
            CleveRoids.Print("Usage: /cleveroid listtab <tab number>")
            CleveRoids.Print("Example: /cleveroid listtab 2")
            CleveRoids.Print("Use /cleveroid talenttabs to see your tab numbers")
            return
        end

        local tabName = GetTalentTabInfo(tabNum)
        CleveRoids.Print("=== " .. tabName .. " (Tab " .. tabNum .. ") ===")

        local numTalents = GetNumTalents(tabNum)
        for i = 1, numTalents do
            local name, _, _, _, rank, maxRank = GetTalentInfo(tabNum, i)
            if name then
                local rankText = rank .. "/" .. maxRank
                CleveRoids.Print("ID " .. i .. ": " .. name .. " [" .. rankText .. "]")
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

        -- Get talent rank using position-based or name-based lookup
        local talentRank = 0
        local maxRank = 3
        local talentName = modifier.talent or ("Tab " .. tostring(modifier.tab) .. " ID " .. tostring(modifier.id))

        -- Position-based lookup (preferred)
        if modifier.tab and modifier.id then
            local _, name, _, _, rank, max = GetTalentInfo(modifier.tab, modifier.id)
            talentRank = tonumber(rank) or 0
            maxRank = tonumber(max) or 3
            if name then
                talentName = name
            end
        end

        -- Name-based fallback
        if talentRank == 0 and modifier.talent and CleveRoids.GetTalentRank then
            talentRank = CleveRoids.GetTalentRank(modifier.talent)
        end

        CleveRoids.Print("=== Talent Modifier Test ===")
        CleveRoids.Print("Spell: " .. spellName .. " (ID:" .. spellID .. ")")
        CleveRoids.Print("Talent: " .. talentName)
        CleveRoids.Print("Your Rank: " .. talentRank .. "/" .. maxRank)

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

    -- debuffdebug (debug debuff tracking on target)
    if cmd == "debuffdebug" or cmd == "debuff" or cmd == "trackdebug" then
        local searchName = val
        if val2 and val2 ~= "" then
            searchName = val .. " " .. val2
        end
        -- Strip underscores and quotes
        if searchName and searchName ~= "" then
            searchName = string.gsub(searchName, "_", " ")
            searchName = string.gsub(searchName, '"', "")
        end

        CleveRoids.Print("|cff88ff88=== Debuff Tracking Debug ===|r")

        local _, guid = UnitExists("target")
        if not guid then
            CleveRoids.Print("|cffff0000No target selected!|r")
            return
        end

        local targetName = UnitName("target") or "Unknown"
        guid = CleveRoids.NormalizeGUID(guid)
        CleveRoids.Print("Target: " .. targetName .. " (GUID: " .. tostring(guid) .. ")")

        -- Show tracking table for this target
        CleveRoids.Print(" ")
        CleveRoids.Print("|cff00ff00=== Tracked Debuffs (libdebuff.objects) ===|r")
        local lib = CleveRoids.libdebuff
        if lib and lib.objects and lib.objects[guid] then
            local count = 0
            for spellID, rec in pairs(lib.objects[guid]) do
                if rec and rec.start and rec.duration then
                    local timeRemaining = rec.duration + rec.start - GetTime()
                    local spellName = SpellInfo and SpellInfo(spellID) or "Unknown"
                    local caster = rec.caster or "unknown"
                    local stacks = rec.stacks or 0
                    if timeRemaining > 0 then
                        CleveRoids.Print(string.format("  |cff00ff00[%d]|r %s: %.1fs left (caster: %s, stacks: %d)",
                            spellID, spellName, timeRemaining, caster, stacks))
                        count = count + 1
                    else
                        CleveRoids.Print(string.format("  |cffff0000[%d]|r %s: EXPIRED %.1fs ago (caster: %s)",
                            spellID, spellName, -timeRemaining, caster))
                    end
                end
            end
            if count == 0 then
                CleveRoids.Print("  (no active tracked debuffs)")
            end
        else
            CleveRoids.Print("  (no tracking data for this target)")
        end

        -- Show actual debuff slots (1-16 via UnitDebuff, 17-48 via overflow)
        CleveRoids.Print(" ")
        CleveRoids.Print("|cff00ff00=== Debuff Slots (UnitDebuff 1-16) ===|r")
        local debuffCount = 0
        for i = 1, 16 do
            local texture, stacks, debuffType, spellID = UnitDebuff("target", i)
            if texture then
                local spellName = SpellInfo and SpellInfo(spellID) or "slot" .. i
                CleveRoids.Print(string.format("  Slot %d: [%d] %s (stacks: %d)",
                    i, spellID or 0, spellName, stacks or 0))
                debuffCount = debuffCount + 1
            end
        end
        if debuffCount == 0 then
            CleveRoids.Print("  (no debuffs in slots 1-16)")
        end

        -- Show overflow debuffs in buff slots (17-48)
        CleveRoids.Print(" ")
        CleveRoids.Print("|cff00ff00=== Overflow Debuffs (UnitBuff 1-32 as debuffs 17-48) ===|r")
        local overflowCount = 0
        for i = 1, 32 do
            local texture, stacks, spellID = UnitBuff("target", i)
            if texture and spellID then
                -- Check if this might be an overflow debuff by checking libdebuff durations
                local isDebuff = lib and lib.durations and lib.durations[spellID]
                if isDebuff then
                    local spellName = SpellInfo and SpellInfo(spellID) or "slot" .. i
                    CleveRoids.Print(string.format("  Buff Slot %d (=Debuff %d): [%d] %s (stacks: %d) |cffff8800OVERFLOW|r",
                        i, i + 16, spellID, spellName, stacks or 0))
                    overflowCount = overflowCount + 1
                end
            end
        end
        if overflowCount == 0 then
            CleveRoids.Print("  (no overflow debuffs detected)")
        end

        -- If a specific debuff name was provided, test the conditional
        if searchName and searchName ~= "" then
            CleveRoids.Print(" ")
            CleveRoids.Print("|cff00ff00=== Testing [debuff:\"" .. searchName .. "\"] ===|r")

            -- Test ValidateUnitDebuff
            local result = CleveRoids.ValidateUnitDebuff("target", { name = searchName })
            CleveRoids.Print("ValidateUnitDebuff(target, {name='" .. searchName .. "'}): " ..
                (result and "|cff00ff00true|r" or "|cffff0000false|r"))

            -- Test with time conditional
            local resultTime = CleveRoids.ValidateUnitDebuff("target", { name = searchName, operator = "<", amount = 99999 })
            CleveRoids.Print("ValidateUnitDebuff(target, {name='" .. searchName .. "', operator='<', amount=99999}): " ..
                (resultTime and "|cff00ff00true|r" or "|cffff0000false|r"))

            -- Look for spell IDs matching this name
            CleveRoids.Print(" ")
            CleveRoids.Print("|cff00ff00=== Spell ID Lookup for \"" .. searchName .. "\" ===|r")
            local foundIDs = {}
            -- Check Spells table
            if CleveRoids.Spells then
                for id, name in pairs(CleveRoids.Spells) do
                    if type(name) == "string" and string.lower(name) == string.lower(searchName) then
                        table.insert(foundIDs, id)
                    end
                end
            end
            -- Also check SpellInfo
            if SpellInfo then
                for id = 1, 30000 do
                    local name = SpellInfo(id)
                    if name and string.lower(name) == string.lower(searchName) then
                        local found = false
                        for _, existingID in ipairs(foundIDs) do
                            if existingID == id then found = true break end
                        end
                        if not found then
                            table.insert(foundIDs, id)
                        end
                    end
                    -- Stop early if we found some
                    if table.getn(foundIDs) > 10 then break end
                end
            end

            if table.getn(foundIDs) > 0 then
                for _, id in ipairs(foundIDs) do
                    local tracked = lib and lib.objects and lib.objects[guid] and lib.objects[guid][id]
                    local trackedStr = tracked and "|cff00ff00TRACKED|r" or "|cff888888not tracked|r"
                    CleveRoids.Print("  SpellID " .. id .. ": " .. trackedStr)
                    if tracked then
                        local remaining = tracked.duration + tracked.start - GetTime()
                        CleveRoids.Print("    -> " .. string.format("%.1fs remaining (caster: %s)", remaining, tracked.caster or "?"))
                    end
                end
            else
                CleveRoids.Print("  (no spell IDs found for this name)")
            end
        end

        return
    end

    -- tankdebug (debug pfUI tank integration)
    if cmd == "tankdebug" then
        CleveRoids.Print("=== Tank Debug ===")

        -- Check pfUI availability
        if not CleveRoids.HasPfUITanks() then
            CleveRoids.Print("|cffff0000pfUI tank system not available!|r")
            CleveRoids.Print("  pfUI loaded: " .. tostring(type(pfUI) == "table"))
            CleveRoids.Print("  pfUI_config: " .. tostring(type(pfUI_config) == "table"))
            return
        end

        CleveRoids.Print("|cff00ff00pfUI tank system available|r")

        -- List raid frame tanks
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Raid Frame Tanks (right-click toggle):|r")
        local raidTankCount = 0
        if type(pfUI) == "table" and type(pfUI.uf) == "table" and
           type(pfUI.uf.raid) == "table" and type(pfUI.uf.raid.tankrole) == "table" then
            for name, isTank in pairs(pfUI.uf.raid.tankrole) do
                if isTank then
                    CleveRoids.Print("  - " .. name)
                    raidTankCount = raidTankCount + 1
                end
            end
        end
        if raidTankCount == 0 then
            CleveRoids.Print("  (none)")
        end

        -- List nameplate off-tank names
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Nameplate Off-Tank Names (config setting):|r")
        local npTankCount = 0
        if type(pfUI_config) == "table" and type(pfUI_config.nameplates) == "table" then
            local list = pfUI_config.nameplates.combatofftanks or ""
            if list ~= "" then
                CleveRoids.Print("  Raw setting: \"" .. list .. "\"")
                -- pfUI uses # as separator
                for name in string.gfind(list, "[^#]+") do
                    name = string.gsub(name, "^%s*(.-)%s*$", "%1") -- trim
                    if name ~= "" then
                        CleveRoids.Print("  - " .. name .. " (lowercase: " .. string.lower(name) .. ")")
                        npTankCount = npTankCount + 1
                    end
                end
            end
        end
        if npTankCount == 0 then
            CleveRoids.Print("  (none)")
        end

        -- Check current target
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Current Target Check:|r")
        if not UnitExists("target") then
            CleveRoids.Print("  No target selected")
        else
            local targetName = UnitName("target") or "Unknown"
            CleveRoids.Print("  Your target: " .. targetName)

            if UnitExists("targettarget") then
                local ttName = UnitName("targettarget") or "Unknown"
                CleveRoids.Print("  Target's target: " .. ttName)
                local isTank = CleveRoids.IsPlayerTank(ttName)
                if isTank then
                    CleveRoids.Print("  |cff00ff00" .. ttName .. " IS marked as tank|r")
                else
                    CleveRoids.Print("  |cffff8800" .. ttName .. " is NOT marked as tank|r")
                    CleveRoids.Print("  (lowercase check: " .. string.lower(ttName) .. ")")
                end
            else
                CleveRoids.Print("  Target's target: (none)")
            end

            -- Test the conditional functions
            CleveRoids.Print(" ")
            CleveRoids.Print("|cffffaa00Conditional Results:|r")
            local isTargetingTank = CleveRoids.IsTargetingAnyTank("target")
            CleveRoids.Print("  IsTargetingAnyTank('target'): " .. tostring(isTargetingTank))
            CleveRoids.Print("  [targeting:tank] would be: " .. tostring(isTargetingTank))
            CleveRoids.Print("  [notargeting:tank] would be: " .. tostring(not isTargetingTank))
        end

        return
    end

    -- auradebug (debug all-caster aura tracking)
    if cmd == "auradebug" or cmd == "bufftracking" then
        CleveRoids.Print("=== All-Caster Aura Tracking Debug ===")

        -- Check CVar status
        local auraCastEnabled = GetCVar("NP_EnableAuraCastEvents")
        if auraCastEnabled == "1" then
            CleveRoids.Print("|cff00ff00NP_EnableAuraCastEvents = 1 (ENABLED)|r")
        else
            CleveRoids.Print("|cffff0000NP_EnableAuraCastEvents = " .. tostring(auraCastEnabled) .. " (DISABLED)|r")
            CleveRoids.Print("  Enable with: |cff00ffff/run SetCVar(\"NP_EnableAuraCastEvents\", \"1\")|r")
            CleveRoids.Print("  Then /reload")
        end

        -- Check Nampower version
        local API = CleveRoids.NampowerAPI
        if API and API.features then
            CleveRoids.Print("Nampower hasAuraCastEvents: " .. tostring(API.features.hasAuraCastEvents))
        else
            CleveRoids.Print("|cffff0000Nampower API not available|r")
        end

        -- Show tracking data for current target/mouseover
        CleveRoids.Print(" ")
        CleveRoids.Print("|cffffaa00Tracked Auras:|r")
        local trackingCount = 0
        local now = GetTime()
        for targetGuid, spells in pairs(CleveRoids.AllCasterAuraTracking or {}) do
            local unitName = nil
            -- Try to find unit name for this GUID (use pcall to handle invalid units like "focus")
            for _, testUnit in ipairs({"target", "mouseover", "party1", "party2", "party3", "party4"}) do
                local ok, exists, testGuid = pcall(function() return UnitExists(testUnit) end)
                if ok and exists then
                    _, testGuid = UnitExists(testUnit)
                    if testGuid == targetGuid then
                        unitName = UnitName(testUnit)
                        break
                    end
                end
            end

            for spellId, auraData in pairs(spells) do
                if auraData.start and auraData.duration then
                    local remaining = auraData.duration + auraData.start - now
                    if remaining > 0 then
                        local spellName = SpellInfo(spellId) or ("ID:" .. spellId)
                        local display = unitName or (string.sub(targetGuid, 1, 16) .. "...")
                        CleveRoids.Print(string.format("  %s on %s: %.1fs left", spellName, display, remaining))
                        trackingCount = trackingCount + 1
                    end
                end
            end
        end
        if trackingCount == 0 then
            CleveRoids.Print("  (no auras currently tracked)")
        end

        -- Check specific target
        if UnitExists("target") then
            CleveRoids.Print(" ")
            CleveRoids.Print("|cffffaa00Target Buff Check:|r")
            local _, targetGuid = UnitExists("target")
            CleveRoids.Print("  Target GUID: " .. tostring(targetGuid))
            local targetData = CleveRoids.AllCasterAuraTracking[targetGuid]
            if targetData then
                local count = 0
                for _ in pairs(targetData) do count = count + 1 end
                CleveRoids.Print("  Tracked spells on target: " .. count)
            else
                CleveRoids.Print("  |cffff9900No tracking data for this target|r")
            end
        end

        return
    end

    -- overflowtest (toggle overflow buff frame test mode)
    if cmd == "overflowtest" then
        if CleveRoids.ToggleOverflowTest then
            CleveRoids.ToggleOverflowTest()
        else
            CleveRoids.Print("|cffff0000OverflowBuffFrame extension not loaded|r")
        end
        return
    end

    -- Delegate to extension console handlers (chain pattern)
    if CleveRoids.HandleConsoleCommand then
        CleveRoids.HandleConsoleCommand(msg)
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
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00CC Immunity Tracking:|r")
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid listccimmune [type] - List CC immunity data')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid addccimmune "<NPC>" <type> [buff] - Add CC immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid removeccimmune "<NPC>" <type> - Remove CC immunity')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid clearccimmune [type] - Clear CC immunity data')
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00Combo Point Tracking:|r")
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combotrack - Show combo point tracking info')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid comboclear - Clear combo tracking data')
    DEFAULT_CHAT_FRAME:AddMessage('/cleveroid combolearn - Show learned combo durations (per CP)')
end

SLASH_CLEAREQUIPQUEUE1 = "/clearequipqueue"
SlashCmdList.CLEAREQUIPQUEUE = function()
    -- Release all entries back to pool
    for i = 1, CleveRoids.equipmentQueueLen do
        local entry = CleveRoids.equipmentQueue[i]
        if entry then
            CleveRoids.equipmentQueue[i] = nil
            -- Return to pool if space available
            if table.getn(CleveRoids.queueEntryPool) < 10 then
                entry.item = nil
                entry.slotName = nil
                entry.inventoryId = nil
                table.insert(CleveRoids.queueEntryPool, entry)
            end
        end
    end
    CleveRoids.equipmentQueueLen = 0
    if CleveRoids.equipQueueFrame then
        CleveRoids.equipQueueFrame:Hide()
    end
    CleveRoids.Print("Equipment queue cleared")
end

SLASH_EQUIPQUEUESTATUS1 = "/equipqueuestatus"
SlashCmdList.EQUIPQUEUESTATUS = function()
    local count = CleveRoids.equipmentQueueLen
    CleveRoids.Print("Equipment queue has " .. count .. " pending items")

    for i = 1, count do
        local entry = CleveRoids.equipmentQueue[i]
        if entry then
            local itemName = (entry.item and entry.item.name) or "Unknown"
            local slotName = entry.slotName or "Unknown"
            local retries = entry.retries or 0
            CleveRoids.Print(i .. ". " .. itemName .. " -> " .. slotName .. " (retries: " .. retries .. ")")
        end
    end
end

-- Apply temporary weapon enchants (poisons, oils, sharpening stones, etc.)
-- Usage: /applymain [conditionals] ItemName
-- Usage: /applyoff [conditionals] ItemName
-- Example: /applymain [nomhimbue] Instant Poison
-- Example: /applyoff [combat] Crippling Poison

local function FindItemInBags(itemName)
    -- Require a non-empty item name to prevent matching everything
    if not itemName or itemName == "" then
        return nil
    end

    local searchName = string.lower(itemName)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, foundName = string.find(link, "%[(.+)%]")
                if foundName and string.find(string.lower(foundName), searchName, 1, true) then
                    return bag, slot, foundName
                end
            end
        end
    end
    return nil
end

function CleveRoids.DoApply(hand, msg)
    local weaponSlots = {
        ["main"] = 16,
        ["off"] = 17,
    }

    local slot = weaponSlots[hand]
    if not slot then
        CleveRoids.Print("Invalid hand: " .. tostring(hand))
        return false
    end

    local action = function(itemName)
        local bag, bagSlot, foundName = FindItemInBags(itemName)
        if not bag then
            CleveRoids.Print("Item not found: " .. itemName)
            return false
        end

        -- Apply the item to the weapon
        UseContainerItem(bag, bagSlot)
        PickupInventoryItem(slot)
        ReplaceEnchant()
        ClearCursor()
        return true
    end

    local handled = false
    for _, v in pairs(CleveRoids.splitStringIgnoringQuotes(msg)) do
        if CleveRoids.DoWithConditionals(v, action, CleveRoids.FixEmptyTarget, false, action) then
            handled = true
            break
        end
    end
    return handled
end

SLASH_APPLYMAIN1 = "/applymain"
SlashCmdList.APPLYMAIN = function(msg)
    -- Require an item name argument
    if not msg or msg == "" or string.gsub(msg, "%s+", "") == "" then
        CleveRoids.Print("Usage: /applymain [conditionals] ItemName")
        return
    end
    CleveRoids.DoApply("main", msg)
end

SLASH_APPLYOFF1 = "/applyoff"
SlashCmdList.APPLYOFF = function(msg)
    -- Require an item name argument
    if not msg or msg == "" or string.gsub(msg, "%s+", "") == "" then
        CleveRoids.Print("Usage: /applyoff [conditionals] ItemName")
        return
    end
    CleveRoids.DoApply("off", msg)
end
